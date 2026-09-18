# SPDX-License-Identifier: GPL-2.0-only
#
# Sysupgrade platform hooks for intel-mips.
#
# NAND layout (seale_avm_fritz7560.dts, seale_avm_fritz7580.dts,
# seale_avm_fritz7590.dts): two raw 8 MiB kernel slots, each holding a bare EVA
# container, plus a "ubi" partition holding the rootfs and rootfs_data volumes.
#
# BOTH kernel slots are written, with the same container, and that is the whole
# point of this file. Which slot EVA boots is chosen by linux_fs_start in the
# boot-loader environment, which is *runtime state*: the boot loader may change
# it on its own. Reading it and writing only the slot it names cannot work -- it
# may change after the write -- and a fixed choice cannot work either, because
# the variable moves. Writing both makes the question moot, and makes EVA's
# fallback self-healing: whichever slot it picks holds the kernel that matches
# the rootfs.
#
# This replaces relying on nand.sh's CI_KERNPART default, which silently wrote
# one slot: on a board whose linux_fs_start pointed at the other one, sysupgrade
# reported success at every layer and the device kept running its old kernel.
#
# Partitions are addressed by NAME throughout; the boards number them
# differently.

REQUIRE_IMAGE_METADATA=1

INTEL_MIPS_KERNEL_SLOTS="kernel0 kernel1"

# head and sha256sum are not in switch_to_ramfs()'s default list, and the
# readback below cannot run without them.
RAMFS_COPY_BIN='head sha256sum'

# Attach the ubi partition if nothing has attached it yet, and echo the ubi
# device. Deliberately not nand_attach_ubi(): that one falls back to
# "ubiformat -y" when the attach fails, and this runs before the upgrade has
# been allowed to touch flash at all.
platform_probe_ubi() {
	local mtdnum ubidev

	ubidev="$(nand_find_ubi "$CI_UBIPART")"
	if [ -z "$ubidev" ]; then
		mtdnum="$(find_mtd_index "$CI_UBIPART")"
		[ -n "$mtdnum" ] || return 1
		ubiattach -m "$mtdnum" >/dev/null 2>&1
		ubidev="$(nand_find_ubi "$CI_UBIPART")"
	fi

	echo "$ubidev"
}

# True when the ubi device carries volumes but none of them is the rootfs
# volume, i.e. it is still the vendor's UBI (avm_filesys_0, avm_config, ...).
# A UBI that is empty because it was just reformatted, and any UBI this
# firmware wrote, both come out false.
platform_ubi_is_foreign() {
	local ubidev="$1"
	local voldir found=0

	for voldir in /sys/class/ubi/${ubidev}_*; do
		[ -d "$voldir" ] || continue
		[ "$(cat "$voldir/name")" = "$CI_ROOTPART" ] && return 1
		found=1
	done

	[ "$found" = 1 ]
}

platform_check_image() {
	nand_do_platform_check "$(board_name)" "$1"
}

# Write one kernel slot and prove it landed. mtd cannot report a failed write
# -- mtd_write()'s return value is discarded and mtd's main() returns 0
# unconditionally -- so the readback is not belt-and-braces here, it is the
# only check there is. This controller also has a measured silent page-drop
# class: a dropped page reads back pristine-erased and ECC-valid, invisible to
# every write-side check.
platform_write_kernel_slot() {
	local slot="$1" file="$2" len="$3" want="$4"
	local idx got

	idx="$(find_mtd_index "$slot")"
	[ -n "$idx" ] || {
		echo "kernel slot $slot is not in the flash map."
		return 1
	}

	# mtd write only erases as far as it writes, so a shorter new container
	# would leave the previous one's tail behind; EVA parses the slot as a
	# bare container. Erasing first leaves the tail at 0xFF.
	mtd erase "$slot" || return 1
	mtd write "$file" "$slot" || return 1

	got="$(dd if="/dev/mtd$idx" bs=65536 2>/dev/null | head -c "$len" | \
		sha256sum | cut -d' ' -f1)"
	[ "$want" = "$got" ] || {
		echo "readback of $slot does not match the image:"
		echo "  expected $want"
		echo "  read     $got"
		return 1
	}

	echo "$slot written and verified"
}

platform_do_upgrade() {
	local ubidev board_dir slot klen kwant tool
	local cmd kernel=/tmp/kernel.eva

	case "$(board_name)" in
	avm,fritz7560|avm,fritz7580|avm,fritz7590)
		cmd="$(identify_if_gzip "$1")cat"
		# Verify the tar before anything below erases flash.
		# platform_check_image() is skipped by "sysupgrade -F", so without
		# this a forced upgrade with a truncated image would erase the
		# kernel slot and only then discover it has nothing to write
		# there, leaving a box that no longer cold-boots.
		nand_verify_tar_file "$1" "$cmd" || nand_do_upgrade_failed

		# Refuse before touching flash if either slot is missing, rather
		# than writing one of the two and calling it an upgrade.
		for slot in $INTEL_MIPS_KERNEL_SLOTS; do
			[ -n "$(find_mtd_index "$slot")" ] && continue
			echo "kernel slot $slot is missing from the flash map;"
			echo "refusing to upgrade."
			nand_do_upgrade_failed
		done

		# Refuse on a device still holding the vendor's UBI. nand.sh would
		# attach it happily, find none of the three volumes it knows how
		# to remove, and then fail in ubimkvol with the device full -- by
		# which point the kernel slot is already gone. Those volumes have
		# to be cleared by the first-install procedure instead.
		ubidev="$(platform_probe_ubi)"
		if [ -n "$ubidev" ] && platform_ubi_is_foreign "$ubidev"; then
			echo "the ubi partition holds volumes but no rootfs volume;"
			echo "this looks like the vendor firmware's UBI."
			echo "run the first-install procedure before using sysupgrade."
			nand_do_upgrade_failed
		fi

		# Stage the kernel and hash it BEFORE anything erases, so a
		# missing tool or a truncated member aborts while the flash is
		# still intact.
		board_dir="$($cmd < "$1" | tar tf - | sed -ne '/^sysupgrade-.*\/$/{s|/$||;p;q;}')"
		[ -n "$board_dir" ] || {
			echo "cannot find the sysupgrade directory in the image."
			nand_do_upgrade_failed
		}

		$cmd < "$1" | tar xOf - "$board_dir/kernel" > "$kernel"
		klen="$(wc -c < "$kernel")"
		[ "$klen" -gt 0 ] && [ "$klen" -le 8388608 ] || {
			echo "the image carries no usable kernel ($klen bytes;"
			echo "a slot is 8 MiB)."
			nand_do_upgrade_failed
		}

		# Both tools are checked here, before the first write, because the
		# readback below is the only failure signal there is: if it could
		# not run we would rather abort with the flash untouched than
		# discover it after erasing a slot.
		for tool in sha256sum head; do
			command -v "$tool" >/dev/null && continue
			echo "$tool is missing from the ramfs, so a written slot"
			echo "could not be verified; refusing to upgrade."
			nand_do_upgrade_failed
		done

		kwant="$(sha256sum < "$kernel" | cut -d' ' -f1)"
		[ "${#kwant}" = 64 ] || {
			echo "cannot hash the kernel; refusing rather than"
			echo "writing unverified."
			nand_do_upgrade_failed
		}

		# The rootfs first: it leaves both old kernels in place, so an
		# abort here still has something that cold-boots. CI_KERNPART=none
		# makes nand.sh skip the kernel entirely -- the slots are ours.
		CI_KERNPART=none
		nand_do_flash_file "$1" "$cmd" || nand_do_upgrade_failed

		# One slot at a time. Each is verified before the next is erased,
		# so there is never a moment with no loadable container: either
		# the untouched previous one, or the freshly verified new one.
		for slot in $INTEL_MIPS_KERNEL_SLOTS; do
			platform_write_kernel_slot "$slot" "$kernel" "$klen" \
				"$kwant" || nand_do_upgrade_failed
		done

		nand_do_upgrade_success
		;;
	*)
		echo "sysupgrade is not supported on this board."
		exit 1
		;;
	esac
}

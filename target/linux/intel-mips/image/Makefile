# SPDX-License-Identifier: GPL-2.0-only
#
# Image build infrastructure for the intel-mips target.
# Minimal-by-design — only the macros the two Seale devices (seale.mk) need.

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

# The board DTS files live in the kernel tree's intel-mips/ subdirectory, not
# at the top of arch/mips/boot/dts/ where image.mk points DTS_DIR. Narrow it
# once here (the same idiom lantiq/image/Makefile uses) rather than giving each
# device a DEVICE_DTS_DIR: image.mk's Image/BuildDTB falls back to DTS_DIR when
# DEVICE_DTS_DIR is unset, so one line covers both the dtb compile rule and
# Device/Default's KERNEL_DEPENDS wildcard below. That wildcard silently
# matched nothing while DTS_DIR was the parent directory and DEVICE_DTS was a
# bare name, which is exactly the sort of dependency that fails by not
# rebuilding.
DTS_DIR := $(DTS_DIR)/intel-mips

# AVM urlader's DTB-table scanner needs a lookup table at the kernel
# entry address. inject_avm_preamble.py finds embedded FDTs in the
# kernel binary, reads each one's /avm-hw-revision/subrevision, and
# writes the table into the kernel's first 0x400 zero-padding bytes
# (with a MIPS BEQ branch at +0x00 that skips the table to land at
# +0x10 = the real kernel entry). Without this, the urlader rejects
# the boot with "Device Tree Blob for SubRevision N not found". The script
# reads only the FDT layout, so it is independent of the kernel version.
define Build/avm-preamble
	$(TOPDIR)/target/linux/intel-mips/image/inject_avm_preamble.py \
		$@ $@.preamble $(KERNEL_LOADADDR) && \
		mv $@.preamble $@
endef

# Appends a SECOND copy of the board DTB, for EVA to destroy.
#
# EVA does not just look the SubRevision up in the preamble table; when the
# lookup does not satisfy it, it WRITES its own DTB over whatever the table
# entry points at. Its replacement blob is larger than ours and describes a
# different board, so whichever copy the table names is unusable afterwards.
#
# Which copy the table names is decided by inject_avm_preamble.py: it scans
# for FDT magic in ascending file order and assigns subrev -> VA with a plain
# dict store, so for two blobs carrying the same subrevision the LAST one
# found wins. Appending a second copy therefore moves the table entry — and
# with it EVA's write — off the first copy and onto the second.
#
# That matters because the first copy is the one the kernel reads.
# CONFIG_MIPS_RAW_APPENDED_DTB places __appended_dtb at the end of the last
# PROGBITS section, which is exactly where the first `cat` lands, and
# get_fdt() (arch/mips/include/asm/bootinfo.h) returns &__appended_dtb ahead
# of both the UHI pointer and the built-in __dtb_start. Leave the second copy
# out and EVA overwrites the blob the kernel is about to parse, which panics
# in early_init_dt_alloc_memory_arch trying to honour the foreign totalsize.
#
# Both copies live inside the 1 MiB the linker reserves after __appended_dtb
# (arch/mips/kernel/vmlinux.lds.S), so EVA's larger blob has room to land
# without reaching .bss, and it grows upwards from the second copy and so
# never reaches back down to the first.
#
# The pad is what keeps the second copy 16-byte aligned; the scanner finds
# FDT magic at any offset, so this is for EVA's benefit and not the script's.
define Build/append-sacrificial-dtb
	pad=$$(( (16 - $$(stat -c%s $@) % 16) % 16 )); \
		[ "$$pad" -eq 0 ] || dd if=/dev/zero bs=1 count=$$pad >> $@
	cat $(KDIR)/image-$(firstword $(DEVICE_DTS)).dtb >> $@
endef

# The AVM urladers on this target refuse the image produced by the generic
# Build/eva-image (lzma2eva) in include/image-commands.mk. That is a fact about
# lzma2eva's container and not about record counts: a one-record TI container
# packed by eva-image is accepted, both from RAM and out of the NAND kernel
# slot, which is what Build/eva-single-kernel below relies on. Do not read the
# lzma2eva refusal as "this urlader requires two records".
#
# eva-image (built as a host tool from tools/eva-kernel-image) takes raw kernel
# binaries and does the LZMA compression itself, so the KERNEL chain must not
# pre-compress with `| lzma`.
#
# Omitting --kernel2 is what makes eva-image emit a one-record container, and
# there is deliberately no recipe here that supplies one. The two-record form
# this replaced packed AVM's bootcore as kernel2: a blob that runs on the 4Kec
# boot core, programs the NGI fabric and then releases the interAptiv cluster
# the OpenWrt kernel runs on. With no such record the 4Kec never starts, so
# protect_unattached() never runs and the deny-all fabric region it programs
# above the bootcore's compiled-in ram-size never exists.
#
# That is not a side effect worked around, it is the point: it is what lets a
# device declare DRAM the bootcore blob does not believe in, and it is why both
# boards here were moved off the two-record chain rather than given a bootcore
# each. ⚠ Reintroducing a kernel2 record re-arms that denial across the upper
# part of the RAM the kernel has been told it owns, and the failure is a fault
# or a hang on first touch up there rather than a diagnosable message. The
# device blocks and seale_avm_fritz7590.dts's memory node carry the evidence.
define Build/eva-single-kernel
	$(STAGING_DIR_HOST)/bin/eva-image pack \
		--output $@.eva \
		--kernel1 $@ \
		--load1 $(KERNEL_LOADADDR) \
		--entry1 $(KERNEL_ENTRY) \
	&& mv $@.eva $@
endef

# Per-device defaults. Deliberately carries no NAND geometry: the boards on
# this target do not share a flash chip, and a wrong geometry is invisible
# at build time. See Device/NAND below for the four values a NAND device
# owes and where they have to be set.
define Device/Default
  PROFILES = Default
  KERNEL_DEPENDS = $$(wildcard $(DTS_DIR)/$$(DEVICE_DTS).dts)
  KERNEL_INITRAMFS_NAME = $$(KERNEL_NAME)-initramfs
  KERNEL := kernel-bin | append-dtb | lzma | uImage lzma
  KERNEL_INITRAMFS := kernel-bin | append-dtb | lzma | uImage lzma
  FILESYSTEMS := squashfs
  SOC := $(DEFAULT_SOC)
  DEVICE_DTS = $$(SOC)_$(1)
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := append-kernel | append-rootfs | pad-rootfs | check-size | append-metadata
endef

# AVM device family template — the EVA build pipeline. Same shape as
# lantiq's Device/AVM (target/linux/lantiq/image/Makefile:132), minus its
# image recipe: both devices here are NAND-rooted and take their
# sysupgrade.bin from Device/NAND below.
#
# Both device blocks spell the two chains out again rather than inherit them —
# see either block for why — so what this default really owes is to name a
# recipe that exists and is right for a new device added here.
define Device/AVM
  DEVICE_VENDOR := AVM
  KERNEL := kernel-bin | append-dtb | avm-preamble | eva-single-kernel
  KERNEL_INITRAMFS := $$(KERNEL)
endef

# NAND-rooted device family template. Per-device blocks that include
# `$(Device/NAND)` AFTER `$(Device/AVM)` get the stock NAND sysupgrade
# image: a tar carrying the kernel container and the rootfs. The rootfs goes
# into the "rootfs" UBI volume, which is already nand.sh's CI_UBIPART/
# CI_ROOTPART default. The kernel does NOT go through nand.sh: this target has
# two kernel slots and writes both, so base-files' platform.sh sets
# CI_KERNPART=none and places the container itself — see it for the reason.
# Adds ubifs to FILESYSTEMS so mkfs.ubifs runs and produces the
# rootfs image consumed by append-ubi.
#
# The two halves sysupgrade puts on flash are also emitted on their own,
# because a device that still carries the vendor firmware cannot be
# installed through sysupgrade at all: nand.sh only removes the UBI
# volumes it recognises, and AVM's four fill the partition, so the rootfs
# volume can never be created. That first install writes the kernel slot
# and reformats the UBI by hand from a rambooted initramfs, and these are
# the two files it needs. Same pair, and the same names, as lantiq's
# avm_fritz3370.
#
# Every device including this template owes four values, and all four are
# properties of its flash chip rather than of the SoC, so they belong in the
# device block and nowhere above it:
#
#   BLOCKSIZE PAGESIZE SUBPAGESIZE   ubinize's -p/-m/-s, via Build/append-ubi
#   MKUBIFS_OPTS                     mkfs.ubifs's -m/-e/-c
#
# The first three need no DEVICE_VARS line: include/image.mk already lists
# them in DEFAULT_DEVICE_VARS. The fourth is the subtle one. UBIFS_OPTS is
# NOT per-device — Image/mkfs/ubifs reads it at target scope and produces one
# shared $(KDIR)/root.ubifs — so it must stay unset here. The per-device route
# is MKUBIFS_OPTS, which image.mk feeds into FS_OPTIONS/ubifs; Device/Build/image
# then gives each device its own root.ubifs+fs=<opts> and points IMAGE_ROOTFS
# at it. Leaving UBIFS_OPTS unset is also what keeps install-images from
# building the unparameterised root.ubifs nobody consumes (image.mk filters
# ubifs out of that list precisely when UBIFS_OPTS is empty).
#
# Getting any of the four wrong is silent: mkfs.ubifs and ubinize both accept
# a geometry the chip does not have and emit an image, and the failure only
# appears on the device, as UBI refusing to attach. The three ubinize numbers
# have to reproduce the VID-header and data offsets the kernel derives from
# the *probed* chip (mtd->writesize and mtd->subpage_sft), because
# validate_ec_hdr() compares them and rejects a mismatch.
define Device/NAND
  FILESYSTEMS += ubifs
  IMAGES := sysupgrade.bin eva-kernel.bin eva-filesystem.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
  IMAGE/eva-kernel.bin := append-kernel
  IMAGE/eva-filesystem.bin := append-ubi | check-size
endef

# Both boards come from seale.mk. SOC here names the DTSI family rather than
# the silicon variant — GRX350 and GRX550 share xrx500.dtsi — so one value
# covers both and there is nothing per-board to select at this level.
DEFAULT_SOC := xrx500
include seale.mk

$(eval $(call BuildImage))

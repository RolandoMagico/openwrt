# SPDX-License-Identifier: GPL-2.0-only
#
# Image rules for the AVM "Seale" boards: the FRITZ!Box 7560 (GRX350) and the
# FRITZ!Box 7580 and 7590 (both GRX550), all three devices of the single xrx500
# subtarget. They share a file because they share the whole EVA image pipeline
# and the load addresses below; what differs is per-device and lives in the
# device blocks.
#
# KERNEL_LOADADDR / KERNEL_ENTRY. There is no target-wide default to inherit,
# and the generic MIPS value is wrong for this family under EVA in any case.
# The kernel's arch/mips/intel-mips/Platform sets
#   load-$(CONFIG_INTEL_MIPS) = 0xffffffff80500000   (CONFIG_EVA=y path)
# CONFIG_INTEL_MIPS in v6.18 selects CPU_MIPS32_3_5_EVA which selects
# EVA, so the EVA branch is taken. The 64-bit sign-extended form
# 0xffffffff80500000 truncates to 0x80500000 in OpenWrt's 32-bit
# KERNEL_LOADADDR makefile variable. This matches the canonical PHYS_OFFSET
# 0x20000000 + 0x500000 offset mapped into KSEG0.
#
# Note the address keys off CONFIG_INTEL_MIPS, not off a board: it is an SoC
# property and GRX350 and GRX550 share it, which is why it sits here at file
# scope rather than in either device block.
KERNEL_LOADADDR := 0x80500000
KERNEL_ENTRY := 0x80500000

define Device/avm_fritz7560
  $(Device/AVM)
  $(Device/NAND)
  DEVICE_VENDOR := AVM
  DEVICE_MODEL := FRITZ!Box 7560
  SOC := xrx500
  # Not for a build-plumbing reason any more. That reason was an out-of-tree
  # bootcore blob, fetched from a repository the buildbots cannot reach and
  # packed as a second kernel record; the single-kernel chain below drops the
  # record entirely, so this device no longer depends on anything fetched from
  # outside the tree and a buildbot could now build it. Kept n deliberately
  # rather than by inheritance: the board is still hardware-gated and this
  # target is not upstream. Flipping it is a decision about release readiness,
  # not a leftover.
  DEFAULT := n
  # Explicit DEVICE_DTS override. The Device/Default block in image/Makefile
  # sets DEVICE_DTS = $$(SOC)_$(1) which would auto-resolve to
  # xrx500_avm_fritz7560, but the board DTS lives at
  # arch/mips/boot/dts/intel-mips/seale_avm_fritz7560.dts. Use the
  # bare name (no subdir) so append-dtb's `cat $(KDIR)/image-$(DEVICE_DTS).dtb`
  # path resolves cleanly. The intel-mips/ subdirectory the source actually
  # lives in comes from DTS_DIR, narrowed once in ../Makefile, which is also
  # what makes Device/Default's KERNEL_DEPENDS wildcard match this file.
  DEVICE_DTS := seale_avm_fritz7560
  # append-dtb concatenates the DTS-compiled DTB after vmlinux.bin, which
  # under CONFIG_MIPS_RAW_APPENDED_DTB is exactly where __appended_dtb sits,
  # and get_fdt() returns it. This is the ONLY device tree the kernel has —
  # there is no built-in blob to fall back on any more.
  # append-sacrificial-dtb then adds a second copy for EVA's DTB-selection
  # fallback to overwrite instead of this one; see it in ../Makefile for why
  # a second copy is what protects the first.
  # avm-preamble injects a DTB lookup table into the kernel's entry padding
  # so AVM's urlader finds the SubRevision-1 DTB (from avm-hw-revision node)
  # inside the binary. MUST run BEFORE eva-single-kernel — the preamble scans
  # raw FDT magic bytes which would be unreachable after LZMA compression.
  # eva-single-kernel packs the raw kernel into the one-record EVA TI-record
  # container. It performs LZMA compression internally, so no `| lzma` step is
  # added. A one-record container is accepted by this urlader both from RAM and
  # out of the NAND kernel slot; the dual form's second record was the bootcore
  # and nothing else needed it.
  #
  # KERNEL_INITRAMFS is spelled out rather than left as $$(KERNEL), matching the
  # 7590 block below: $$(Device/AVM) binds it where IT is expanded, above this
  # line, and stating the chain twice makes the ramboot vehicle and the flashed
  # image provably the same container rather than incidentally the same.
  KERNEL := kernel-bin | append-dtb | append-sacrificial-dtb | avm-preamble | eva-single-kernel
  KERNEL_INITRAMFS := kernel-bin | append-dtb | append-sacrificial-dtb | avm-preamble | eva-single-kernel
  # KERNEL_SIZE matches the kernel partition size from the AVM 5-partition
  # map (seale_avm_fritz7560.dts partition@500000 / partition@d00000 — both
  # are 0x800000 = 8 MiB). sysupgrade writes BOTH slots with this same
  # container, so one size covers them; see base-files' platform.sh for why.
  KERNEL_SIZE := 8192k
  # IMAGE_SIZE is the partition-size cap (0x6b00000 = 109568 KiB = the ubi
  # partition size from the AVM map). check-size enforces this upper bound on
  # eva-filesystem.bin — not on sysupgrade.bin, whose recipe Device/NAND
  # replaces with an unchecked sysupgrade-tar. NOTE: this is NOT the
  # rootfs-usable bound — UBI
  # consumes some PEBs for its own metadata (typically ~5 PEBs * 128 KiB =
  # 640 KiB for the volume table + EC headers + VID headers, plus the
  # UBINIZE_OPTS -E 5 marker PEBs below); the rootfs-usable cap is
  # enforced at mkfs.ubifs time via MKUBIFS_OPTS, not in IMAGE_SIZE.
  IMAGE_SIZE := 109568k
  # NAND geometry of this board's Macronix MX30LF1GE8AB: 2 KiB page,
  # 128 KiB erase block. SUBPAGESIZE is 512 rather than absent because the
  # chip runs on-die ECC and nand_macronix.c's on-die init sets
  # ecc.size = 512 without NAND_NO_SUBPAGE_WRITE, so nand_scan_tail() sees
  # 2048/512 = 4 ECC steps and settles on mtd->subpage_sft = 2. UBI then
  # places the VID header at 2048 >> 2 = 512 and the data at the next page
  # boundary, 2048, leaving a 126 KiB LEB — which is where MKUBIFS_OPTS's
  # -e comes from. Read back off this board's flash to confirm: the UBI EC
  # header carries vid_hdr_offset 0x200, data_offset 0x800.
  #
  # -c 4096 is headroom, not a fit: the 107 MiB ubi partition needs ~864
  # LEBs at 126 KiB. Same shape as the lantiq xrx200 UBIFS geometry.
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  SUBPAGESIZE := 512
  MKUBIFS_OPTS := -m 2048 -e 126KiB -c 4096
  # 5 EOF-marker erase blocks appended after the volumes — not a bad-block
  # reserve, which is what this comment used to claim. -E is an
  # OpenWrt-local ubinize option (tools/mtd-utils/patches/201-*) that writes
  # N erase blocks whose EC header carries an "EOF" tag, marking where the
  # image ends when it is written raw into a partition larger than itself.
  # -E 5 is the tree-wide value and matches the lantiq avm_fritz3370
  # precedent (vr9.mk).
  UBINIZE_OPTS := -E 5
  # kmod-dsa-lantiq-gswip-xrx500 is the switch driver, which stages the GPHY
  # firmware; xrx500-phy11g-firmware is the firmware it stages, installed as
  # /lib/firmware/lantiq/xrx500-phy-fw.bin — the exact path the DT
  # 'firmware-name' property in seale_avm.dtsi's gphy-fw node names, and
  # therefore the string request_firmware_direct() looks up. Renaming either
  # side alone leaves the GPHYs in ROM mode and the LAN ports dead. The
  # blob lives in the root filesystem, so the driver is built as a module
  # and loads once that is mounted; ../config-6.18 says why.
  #
  # Blob: ltq_fw_PHY11G_IP_1v1_xRx5xx_A21_R8548.bin, sha256
  # d8269703afd369c28a6aeeb65d2751334e38e2228816eda0bdb11c2475b0df33.
  #
  # It has to be the xRx5xx variant, not the xRx3xx one carried in the
  # FRITZ.Box_7560-07.11 GPL drop: these boards were brought up and tested
  # on R8548, and with the xRx3xx blob the loader reports success and the
  # links stay down.
  #
  # fritz-tffs-nand, not fritz-tffs: the two package names build different
  # binaries for two incompatible on-flash layouts. fritz-tffs reads the
  # NOR-flash scheme, a pair of mirrored partitions read through a plain
  # file or mtdblock; this board carries the NAND scheme, a single 4 MiB
  # log-structured partition whose per-entry tags live in the pages' spare
  # area, which only fritz_tffs_nand knows how to walk (and which it reaches
  # through the mtd char device, for the OOB ioctl). Shipping the NOR tool
  # here left the box with no way to read its own MAC addresses.
  #
  # fritz-caldata provides fritz_cal_extract, which pulls the per-unit WiFi
  # calibration blobs out of the urlader partition. The two
  # hotplug.d/firmware scripts in ../base-files are what call it.
  #
  # pciutils is bring-up instrumentation for the PCIe host bridges. lspci
  # -vv is the only thing that distinguishes the three ways this bridge
  # can fail — PHY/link never trained, link trained but config reads come
  # back all-ones, and config reads work but the capability chain does not
  # walk — which are indistinguishable from the kernel log alone. It drags
  # in libpci and the pciids database; both can go once the radios are up.
  #
  # The two WiFi radios sit on the first two PCIe root complexes. 5 GHz is
  # a QCA9882 (168c:003c, QCA988X hw2.0) driven by kmod-ath10k; 2.4 GHz is
  # an AR93xx 3x3 part reporting the blank ID 168c:abcd, which binds to
  # plain kmod-ath9k. Not kmod-owl-loader: its PCI table covers
  # 168c:ff1c/168c:ff1d only and never matches 0xabcd. The ID that does
  # match comes from mac80211's own
  # patches/ath9k/513-ath9k_add_pci_ids.patch, and the EEPROM then reaches
  # the driver over ath9k's DT qca,no-eeprom path.
  #
  # ath10k-firmware-qca988x drags in ath10k-board-qca988x, which is what
  # actually matters here: board.bin is not optional just because the
  # calibration blob is supplied by file. ath10k_core_fetch_board_file()
  # hard-errors without it and the radio never registers.
  #
  # wpad-basic-mbedtls rather than the wolfssl or openssl flavour, to match
  # the mbedtls this image already links, and to match the lantiq AVM
  # siblings. Without a wpad/hostapd variant the radios come up but can
  # only run open or client-mode; there is no AP encryption.
  #
  # 802.11ac for the QCA9882 needs DRIVER_11AC_SUPPORT, a hidden
  # (bool, default n) symbol in package/network/services/hostapd/Config.in.
  # Nothing here sets it by hand — kmod-ath10k carries +@DRIVER_11AC_SUPPORT,
  # which makes selecting the module select the symbol. That is also why
  # the .config for this device must be regenerated with `make defconfig`
  # rather than edited: hand-writing the line does not survive.
  #
  # USB. The dwc3 controller, its xHCI half and the USB PHY are built into
  # the kernel from ../config-6.18, so none of them is re-stated here:
  # listing kmod-usb-core or kmod-usb-dwc3 alongside a =y symbol installs an
  # empty package and a "NOTICE: module ... is built-in." line, nothing
  # more. kmod-usb3 is absent for a sharper reason than redundancy — its
  # KCONFIG is "CONFIG_USB_PCI=y CONFIG_USB_XHCI_PCI CONFIG_USB_XHCI_PLATFORM",
  # so selecting it would reverse the deliberate "# CONFIG_USB_PCI is not
  # set" in the kernel fragment and build xhci-pci for a bus that carries
  # the two radios and no xHCI endpoint at all.
  #
  # What belongs here instead is everything that only matters once
  # something is plugged in, kept modular so a size-constrained build can
  # drop it without touching the kernel fragment.
  #
  # kmod-usb-storage is the bulk-only mass-storage class driver. Its
  # "+kmod-scsi-core" is a hard dependency and therefore becomes a select,
  # which is why it cannot be lost to a stale negative the way the entries
  # below can; kmod-scsi-core is also what supplies CONFIG_BLK_DEV_SD,
  # without which a stick enumerates and no /dev/sda ever appears.
  #
  # kmod-usb-storage-uas adds UAS/UASP. It earns its place specifically
  # because this is a SuperSpeed port: a USB3 device that speaks UAS falls
  # back to bulk-only without it, which works but caps throughput far below
  # what the link can carry — and throughput on that link is exactly what
  # the bring-up gate for this phase measures.
  #
  # kmod-fs-vfat and kmod-fs-ext4 are the two filesystems a stick
  # realistically arrives formatted with. Not exfat, ntfs3 or f2fs: each is
  # another module for a case nothing here needs yet, and any of them
  # installs later with opkg. vfat drags in kmod-nls-base and the
  # cp437/iso8859-1/utf8 codepages through AddDepends/nls. nls_base itself
  # ends up built in rather than modular, because CONFIG_USB selects NLS and
  # a Kconfig select overrides generic's "# CONFIG_NLS is not set" — so that
  # one package installs empty, exactly as it does on lantiq.
  #
  # block-mount is what turns any of the above into a mounted filesystem:
  # block-hotplug, mount_root's fstab handling and the /etc/config/fstab UCI
  # schema. Without it the stick enumerates, the partition table is parsed,
  # /dev/sda1 exists — and nothing ever mounts it. It is not inherited from
  # anywhere: DEFAULT_PACKAGES.nas in include/target.mk is keyed on
  # DEVICE_TYPE=nas, and the "usb" FEATURES token adds no packages at all.
  #
  # usbutils is bring-up instrumentation, in the same spirit as pciutils
  # above. "lsusb -t" is what separates the three ways this controller can
  # fail — xhci-hcd never probes, it probes but no root hub registers, or
  # the root hub is there and the port never leaves Powered — which the
  # kernel log alone does not distinguish. It is a feed package and drags in
  # usbids and libusb-1.0; all three can go once the port is proven.
  #
  # kmod-leds-gpio is named here rather than in ../xrx500/target.mk because it
  # is this board's answer and not the subtarget's: every LED on the 7560 hangs
  # off a raw SoC GPIO, while the 7590 drives its panel through the SSO shift
  # register and takes kmod-leds-lgm-sso instead.
  DEVICE_PACKAGES := fritz-tffs-nand fritz-caldata kmod-dsa-lantiq-gswip-xrx500 \
	xrx500-phy11g-firmware \
	pciutils kmod-ath9k kmod-ath10k ath10k-firmware-qca988x wpad-basic-mbedtls \
	kmod-usb-storage kmod-usb-storage-uas kmod-fs-vfat kmod-fs-ext4 block-mount usbutils \
	kmod-leds-gpio
endef

# AVM FRITZ!Box 7590 (HW226 / GRX550). Same EVA pipeline as the 7560 above, so
# only what genuinely differs is restated; anything not mentioned here is
# either identical and inherited from $(Device/AVM)/$(Device/NAND), or is a
# comment on the 7560 block that applies verbatim.
define Device/avm_fritz7590
  $(Device/AVM)
  $(Device/NAND)
  DEVICE_MODEL := FRITZ!Box 7590
  SOC := xrx500
  # n for the same reason as the 7560 above, and for no build-plumbing reason
  # either: hardware-gated board, target not upstream.
  DEFAULT := n
  # Bare name, for the reasons spelled out on the 7560; the intel-mips/ subdir
  # comes from DTS_DIR in ../Makefile.
  DEVICE_DTS := seale_avm_fritz7590
  # SINGLE-kernel containers, and this is coupled to the DTS, not a preference.
  #
  # There is no 7590 bootcore, and borrowing the 7560's is not an option here:
  # that blob declares ram-size = <256>, and its protect_unattached() programs
  # a deny-all NGI fabric region over everything above that — the upper half of
  # a 512 MiB board, denied to every initiator. With no second record the 4Kec
  # core never starts, protect_unattached() never runs, and the region never
  # exists. Verified on this board from RAM and out of the NAND kernel slot,
  # each boot showing zero "ngi:" lines and no bootcore.
  #
  # The DTS declares all 512 MiB of it. It used to declare 256, against a
  # second and unrelated bound -- the top of the uncached window at
  # 0x30000000, above which a page's KSEG1 alias is a register address -- and
  # that bound is now held where the allocation happens instead: ZONE_DMA is
  # sized to the window and dma-direct takes uncached coherent allocations
  # from it. seale_avm_fritz7590.dts's memory node carries the derivation and
  # the standing warning that the blob is single-kernel-only.
  #
  # ⚠ Therefore: do not reintroduce a second kernel record here. The recipe that
  # packed one and the package that staged the blob are both gone from this
  # tree, which is the intent rather than an accident; image/Makefile's
  # Build/eva-single-kernel says what a kernel2 record would re-arm.
  #
  # KERNEL_INITRAMFS is restated rather than inherited. $$(Device/AVM) sets it to
  # $$(KERNEL) at the point IT is expanded, which is above this line, so the
  # inherited value tracks the template's default rather than the chain named
  # here. They agree today; spelling both out is what makes the ramboot vehicle
  # and the flashed image the same container by statement instead of by luck.
  #
  # Two appended DTB copies, for the reasons spelled out on the 7560: the first
  # lands on __appended_dtb and is what get_fdt() returns, the second is there
  # for EVA's DTB-selection fallback to overwrite instead. This board needs the
  # pair as much as the 7560 does — CONFIG_MIPS_RAW_APPENDED_DTB is set in the
  # shared ../../config-6.18, so a single copy would leave the table entry
  # pointing at the blob the kernel parses. ../Makefile's
  # Build/append-sacrificial-dtb carries the full derivation.
  KERNEL := kernel-bin | append-dtb | append-sacrificial-dtb | avm-preamble | eva-single-kernel
  KERNEL_INITRAMFS := kernel-bin | append-dtb | append-sacrificial-dtb | avm-preamble | eva-single-kernel
  # 8 MiB, the same as the 7560: the boot loader's partition table gives both
  # kernel slots 8 MiB on this board too. Which slot EVA boots is runtime
  # state (linux_fs_start), which is why sysupgrade writes both and nothing
  # here depends on it.
  KERNEL_SIZE := 8192k
  # 0x1eb00000 = 502784 KiB = the ubi partition, which is where the whole
  # 7560/7590 flash-map delta lives: mtd0-mtd4 are identical on the two units
  # and only this one grows, from 107 MiB to 491 MiB.
  IMAGE_SIZE := 502784k
  # NAND geometry of this board's part: 4 KiB page, 256 KiB erase block.
  # SUBPAGESIZE is 1024, which is neither the page size nor the 7560's 512.
  # Both the Toshiba BENAND and the Macronix candidate in AVM's chip allowlist
  # run on-die ECC, and both manufacturer inits set ecc.size = 512 without
  # NAND_NO_SUBPAGE_WRITE, so nand_scan_tail() sees 4096/512 = 8 ECC steps and
  # settles on mtd->subpage_sft = 2 either way. UBI then puts the VID header at
  # 4096 >> 2 = 1024 and the data at the next page boundary, 4096, leaving a
  # 252 KiB LEB.
  #
  # Note 252 KiB, not the 248 KiB a no-subpage chip would give — that is the
  # difference between a rootfs that attaches and one that does not, and it is
  # invisible until the image is on the device.
  #
  # Confirmation on the first boot that probes this NAND is one read:
  # /sys/class/mtd/mtd4/subpagesize should be 1024, and UBI should report
  # "LEB size: 258048 bytes" with "sub-page size 1024". That value earns the
  # check for a second reason — it is the only place the on-die ECC binding
  # shows up. The subpage exists *because* nand-ecc-mode = "on-die" resolved
  # and the manufacturer init ran with ecc.size = 512; if the binding had
  # failed silently, which is the standing trap on this property, the engine
  # would not be ON_DIE, that init would never run, and subpagesize would read
  # 4096 — followed by a UBI that will not attach and no diagnostic naming the
  # cause. 4096 here means "the DT ECC property did not take", not "the
  # geometry below is wrong".
  #
  # -c 4096 is headroom: the 491 MiB partition holds ~1960 LEBs at 252 KiB.
  BLOCKSIZE := 256k
  PAGESIZE := 4096
  SUBPAGESIZE := 1024
  MKUBIFS_OPTS := -m 4096 -e 252KiB -c 4096
  UBINIZE_OPTS := -E 5
  # Same as the 7560 except for the radios. Both bands here are QCA9984
  # (168c:0046, one per PCIe domain), which ath10k drives with the qca9984
  # firmware and board data — so no kmod-ath9k and no qca988x blobs. The
  # per-unit calibration route is the same fritz-caldata/hotplug one: AVM
  # prom_config records of type 7 and type 8 in the urlader, which
  # fritz_cal_extract now locates by scanning for the type rather than by
  # seeking to an offset — the offsets move between units.
  #
  # kmod-leds-lgm-sso drives the front panel, which hangs off a shift register
  # here rather than off GPIOs; ../xrx500/target.mk says why kmod-leds-gpio is
  # not the answer on this board, and the 7560 block above names it instead.
  DEVICE_PACKAGES := fritz-tffs-nand fritz-caldata kmod-dsa-lantiq-gswip-xrx500 \
	xrx500-phy11g-firmware \
	pciutils kmod-ath10k ath10k-firmware-qca9984 wpad-basic-mbedtls \
	kmod-usb-storage kmod-usb-storage-uas kmod-fs-vfat kmod-fs-ext4 block-mount usbutils \
	kmod-leds-lgm-sso
endef

# AVM FRITZ!Box 7580 (HW225 / GRX550). Same silicon and same flash part as the
# 7590, and AVM describes the two boards with one shared GRX550 device-tree
# layer, so everything below is the 7590's value rather than an independently
# derived one. This block therefore sits after its template rather than in
# numeric order, and every comment in the 7590 block above applies verbatim
# unless contradicted here.
define Device/avm_fritz7580
  $(Device/AVM)
  $(Device/NAND)
  DEVICE_MODEL := FRITZ!Box 7580
  SOC := xrx500
  # n for the same reason as the two boards above: hardware-gated, target not
  # upstream. Nothing here needs fetching from outside the tree.
  DEFAULT := n
  # Bare name, for the reasons spelled out on the 7560; the intel-mips/ subdir
  # comes from DTS_DIR in ../Makefile.
  DEVICE_DTS := seale_avm_fritz7580
  # Same chain as the other two, restated rather than inherited for the same
  # two reasons: $$(Device/AVM) binds KERNEL_INITRAMFS where IT is expanded,
  # above this line, and the two appended DTB copies are what make the first
  # one — the blob get_fdt() returns — survive EVA overwriting the table
  # target. ../Makefile's Build/append-sacrificial-dtb carries the derivation.
  #
  # ⚠ Single-kernel, and on this board that is not merely inherited style. The
  # 7580 has 512 MiB like the 7590 and there is no 7580 bootcore either, so a
  # kernel2 record would have to borrow the 7560's — which declares
  # ram-size = <256> and denies the upper half of the board to every initiator.
  # See the 7590 block for the full account.
  KERNEL := kernel-bin | append-dtb | append-sacrificial-dtb | avm-preamble | eva-single-kernel
  KERNEL_INITRAMFS := kernel-bin | append-dtb | append-sacrificial-dtb | avm-preamble | eva-single-kernel
  # 8 MiB. Checked against this board's own partition table rather than assumed
  # from the 7590: kernel slot 0 at 0x500000-0xd00000 and slot 1 at
  # 0xd00000-0x1500000, i.e. 0x800000 each, the same map as the 7590 down to
  # the byte. Which slot EVA boots is runtime state (linux_fs_start), so
  # sysupgrade writes both and nothing here depends on it.
  KERNEL_SIZE := 8192k
  # 0x1eb00000 = 502784 KiB, again from this board's own map: ubi runs
  # 0x1500000-0x20000000 of a 512 MiB chip. Identical to the 7590, which is
  # the whole story of the flash layout on these two boards — the 7560's
  # smaller ubi is the only one that differs.
  IMAGE_SIZE := 502784k
  # NAND geometry. Same part as the 7590 — Toshiba TC58BVG2S0HTA BENAND,
  # 4 KiB page, 256 KiB erase block — and the derivation of SUBPAGESIZE = 1024
  # in the 7590 block applies unchanged: on-die ECC with ecc.size = 512 gives
  # 4096/512 = 8 steps and mtd->subpage_sft = 2, so UBI puts the VID header at
  # 1024 and the data at 4096, leaving a 252 KiB LEB.
  #
  # Same first-boot check as the 7590 — /sys/class/mtd/mtd<ubi>/subpagesize
  # must read 1024, and 4096 there means the DT's nand-ecc-mode = "on-die"
  # did not take rather than that these numbers are wrong.
  BLOCKSIZE := 256k
  PAGESIZE := 4096
  SUBPAGESIZE := 1024
  MKUBIFS_OPTS := -m 4096 -e 252KiB -c 4096
  UBINIZE_OPTS := -E 5
  # The 7590's list unchanged. Both radios are QCA9984 here too, one per PCIe
  # root complex, so kmod-ath10k with the qca9984 firmware and board data; and
  # the front panel hangs off the same SSO shift register, so kmod-leds-lgm-sso
  # rather than kmod-leds-gpio.
  #
  # fritz-caldata is the one entry this board may not need. Unlike the 7560 and
  # the 7590, whose per-unit calibration blobs sit zlib-compressed in the
  # urlader, this board's radios calibrate from on-chip OTP, and
  # ../base-files' 11-ath10k-caldata extracts nothing for it. The package is
  # kept anyway, as bring-up insurance. Drop it once both radios are proven to
  # associate on OTP calibration alone.
  DEVICE_PACKAGES := fritz-tffs-nand fritz-caldata kmod-dsa-lantiq-gswip-xrx500 \
	xrx500-phy11g-firmware \
	pciutils kmod-ath10k ath10k-firmware-qca9984 wpad-basic-mbedtls \
	kmod-usb-storage kmod-usb-storage-uas kmod-fs-vfat kmod-fs-ext4 block-mount usbutils \
	kmod-leds-lgm-sso
endef

# All three devices, in the one subtarget. This used to be a guarded block per
# board, because the kernel carried a built-in DTB chosen at compile time:
# naming more than one would have let a build produce one board's image on top
# of a kernel holding another board's device tree, which assembles cleanly and
# fails only on hardware. The DTB now arrives appended to each device's own
# image, so the kernel binary is board-agnostic and that failure no longer has
# a mechanism — which is also what makes adding a third device here free.
TARGET_DEVICES += avm_fritz7560 avm_fritz7580 avm_fritz7590

# SPDX-License-Identifier: GPL-2.0-only
#
# Intel MIPS (xRX500 / GRX500 family) target, named after the kernel-side
# arch/mips/intel-mips/ platform it builds for.
#
# This is a sibling of target/linux/lantiq/, not a subtarget of it. The
# kernel System type symbols CONFIG_INTEL_MIPS and CONFIG_LANTIQ sit in the
# same arch/mips/Kconfig choice block and are mutually exclusive, while
# OpenWrt's config merge keeps a parent's =y over a subtarget's "is not
# set". Placed under lantiq/, xrx500 would inherit CONFIG_LANTIQ=y and
# could not turn it off, breaking the kernel build.

include $(TOPDIR)/rules.mk

BOARD:=intel-mips
BOARDNAME:=Intel MIPS (xRX500 / GRX500)
# "pci", not "pci pcie": scripts/target-metadata.pl maps the two tokens to
# two independent symbols and PCIE_SUPPORT selects nothing. The wifi
# packages this exists for (kmod-ath9k, kmod-ath10k) depend on
# @PCI_SUPPORT; no package in the tree depends on @PCIE_SUPPORT. The
# "pcie" token is also what include/target.mk derives from
# CONFIG_PCIEPORTBUS, which this target deliberately leaves off.
#
# "usb" pulls in no packages of its own. include/target.mk keys
# DEFAULT_PACKAGES on the base set, on DEVICE_TYPE and on procd-ujail only;
# the storage-flavoured DEFAULT_PACKAGES.nas hangs off DEVICE_TYPE=nas, not
# off this token. Its entire effect is scripts/target-metadata.pl emitting
# "select USB_SUPPORT", which is what makes kmod-usb-core's "@USB_SUPPORT"
# satisfiable and with it every $(call AddDepends/usb) package in the tree.
# Without it the target's USB Support menu stays empty, which is what it
# has been until now.
#
# It is declared rather than left to be derived, even though include/target.mk
# would now derive it anyway: it reads the merged kernel fragments back as
# make variables and adds "usb" when CONFIG_USB or CONFIG_USB_SUPPORT is set
# alongside CONFIG_USB_ARCH_HAS_HCD, and config-6.18 now spells all three
# out. But that derivation describes how the stack happens to be built, not
# what the board has. Move the USB symbols out of the fragment and let them
# arrive from the package overrides instead and the token silently
# disappears, taking every @USB_SUPPORT package out of menuconfig with it
# and reporting nothing. The ports are soldered on either way.
FEATURES:=squashfs nand pci usb
# One subtarget for the whole family. There used to be one per board, forced
# by arch/mips/intel-mips/Kconfig: the device tree came out of a Kconfig
# `choice`, so a kernel build carried exactly one board DTB and two boards
# could not share a subtarget. That choice is gone — the DTB now arrives
# appended to the image and the kernel binary is board-agnostic — so the split
# has nothing left to enforce and the boards are ordinary sibling devices.
#
# xrx500 is the right name for the merged subtarget, and not merely because it
# is the published one. GRX350 and GRX550 are the same System type to the
# kernel: ltq_soc_detect() maps both families to SOC_TYPE_GRX500 and they share
# xrx500.dtsi. Naming the subtarget after either silicon variant would be wrong
# for the other, and a board-shaped name would have collided the moment the
# third board arrived, as the 7580 since has: a different board on the same
# GRX550.
SUBTARGETS:=xrx500

KERNEL_PATCHVER:=6.18

define Target/Description
	Build firmware images for Intel/Lantiq xRX500 (GRX350/GRX550) SoCs.
	Devices: AVM FRITZ!Box 7560 (GRX350), AVM FRITZ!Box 7580 (GRX550),
	AVM FRITZ!Box 7590 (GRX550).
endef

include $(INCLUDE_DIR)/target.mk

$(eval $(call BuildTarget))

# SPDX-License-Identifier: GPL-2.0-only
ARCH:=mips
SUBTARGET:=xrx500
BOARDNAME:=XRX500 (GRX350/GRX550)
# Both "pci" and "usb" are on now, at board level in ../Makefile, because
# the PCIe host bridge and the dwc3 USB3 controller both landed. Nothing
# hardware-related is held back here any more; what stays subtarget-scoped
# is only what genuinely differs per subtarget.
FEATURES+=nand targz
# Drop the mips16 default that include/target.mk adds for CPU_MIPS32_R2.
# Userspace binaries built with -mips16 hit SIGBUS on this kernel at init.
FEATURES := $(filter-out mips16,$(FEATURES))
CPU_TYPE:=24kc

# Buttons only. All three boards drive fon/DECT, wlan and connect/WPS off
# ordinary SoC GPIOs, so the hotplug driver belongs to every device here. Which
# pin carries which button is a board fact and lives in each DTS -- the 7560
# and 7590 share the wlan pin and the 7580 does not, which is exactly the
# sort of thing that would go wrong if this were pinned at subtarget level.
#
# kmod-leds-gpio is deliberately NOT in this list, because the boards disagree
# about how the front panel is wired. On the 7560 every LED hangs off a raw
# SoC GPIO and plain gpio-leds drives them; on the 7580 and 7590 they hang
# off the SSO shift-register controller at 0x16d00000 instead, so gpio-leds
# would install a module with nothing to bind to. Each board names its own LED
# driver in DEVICE_PACKAGES -- kmod-leds-gpio for the 7560, kmod-leds-lgm-sso
# for the other two -- see image/seale.mk.
DEFAULT_PACKAGES+=kmod-gpio-button-hotplug

define Target/Description
	Intel/Lantiq xRX500 family (GRX350, GRX550) -- AVM FRITZ!Box 7560, 7580 and 7590
endef

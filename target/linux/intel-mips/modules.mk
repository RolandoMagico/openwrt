# SPDX-License-Identifier: GPL-2.0-only
#
# Target level, which is also the only level that would work: package/kernel/
# linux/Makefile builds its list by globbing target/linux/* exactly one level
# deep, so a modules.mk under a subtarget directory would never be read at all.
# DEPENDS keeps these packages off other targets; which board carries which is
# decided per device in image/seale.mk.

define KernelPackage/leds-lgm-sso
  SUBMENU:=$(LEDS_MENU)
  TITLE:=Intel SSO LED controller support
  KCONFIG:=CONFIG_LEDS_LGM
  FILES:=$(LINUX_DIR)/drivers/leds/blink/leds-lgm-sso.ko
  DEPENDS:=@TARGET_intel_mips
  #
  # The trailing 1 is the boot flag: it puts the module in
  # /etc/modules-boot.d rather than /etc/modules.d, so preinit loads it
  # instead of the normal modules stage. That matters here because the
  # boot-progress and failsafe states are set during preinit, and a missing
  # LED is silent -- led_set_attr() in lib/functions/leds.sh tests for the
  # sysfs file and skips the write when it is absent, so a late module means
  # a dark panel and no diagnostic. The DT carries default-state = "on" for
  # the power lamp to cover the window before even this load happens.
  #
  AUTOLOAD:=$(call AutoLoad,60,leds-lgm-sso,1)
endef

define KernelPackage/leds-lgm-sso/description
  Kernel support for the Serial Shift Output LED controller in the GSWIP
  block of Intel MIPS SoCs. Drives the FRITZ!Box 7590's front panel, whose
  lamps hang off a shift register rather than off SoC GPIOs.
endef

$(eval $(call KernelPackage,leds-lgm-sso))

define KernelPackage/dsa-lantiq-gswip-xrx500
  SUBMENU:=$(NETWORK_DEVICES_MENU)
  TITLE:=Lantiq/Intel GSWIP 3.0 switch support
  KCONFIG:=CONFIG_NET_DSA_LANTIQ_GSWIP_XRX500
  FILES:= \
	$(LINUX_DIR)/drivers/net/dsa/lantiq/lantiq_gswip_common.ko \
	$(LINUX_DIR)/drivers/net/dsa/lantiq/lantiq_gswip_xrx500.ko
  DEPENDS:=@TARGET_intel_mips +xrx500-phy11g-firmware
  #
  # The trailing 1 is the boot flag: /etc/modules-boot.d rather than
  # /etc/modules.d, so preinit loads it. The integrated PHYs stay in ROM
  # mode until their firmware is read out of the root filesystem, so the
  # driver cannot be built in -- and it has to run before the network
  # comes up, because until the switch registers there are no ports at
  # all and failsafe has no LAN jack.
  #
  # The two modules are named in link order. The second depends on the
  # first, which is a library rather than a driver of its own.
  #
  AUTOLOAD:=$(call AutoLoad,41,lantiq_gswip_common lantiq_gswip_xrx500,1)
endef

define KernelPackage/dsa-lantiq-gswip-xrx500/description
  Distributed Switch Architecture driver for the two GSWIP 3.0 switch
  macros of the Intel xRX500 SoC family, the four-port LAN macro every
  board has and the WAN macro of the GRX550 die. It brings up the
  integrated Gigabit PHYs from firmware in the root filesystem, so
  without this package no front-panel port comes up.
endef

$(eval $(call KernelPackage,dsa-lantiq-gswip-xrx500))

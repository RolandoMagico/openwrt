# SPDX-License-Identifier: GPL-2.0-or-later

include $(TOPDIR)/rules.mk

PKG_NAME:=ltq_fw_phy_ip
PKG_VERSION:=8.5.2.10
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://gitlab.com/prpl-foundation/intel/ltq_fw_phy_ip.git
PKG_SOURCE_VERSION:=178c46f36e398ddc54748c61ddf1d537ddc319d1
PKG_MIRROR_HASH:=bb64c6de8cf9062248db1f5bbb71572d159da0845b078be925fede14ca037b56

PKG_FLAGS:=nonshared
PKG_LICENSE:=Lantiq-Software-License-Agreement
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/xrx500-phy11g-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=xRx500 Gigabit Ethernet PHY Firmware
  DEPENDS:=@TARGET_intel_mips
  DEFAULT:=n
endef

define Package/xrx500-phy11g-firmware/description
  The Gigabit Ethernet PHYs integrated in the xRX500/GRX350 SoC stay in ROM
  mode until firmware is loaded into them; without it the PHYs do not answer
  MDIO and no LAN port comes up.

  The firmware is Lantiq proprietary - not GPL - and is not carried in
  linux-firmware, so it is fetched at build time from the prpl Foundation's
  Intel repository, pinned to an immutable commit, the same way vrx518_aca_fw,
  vrx518_ppe_fw and dsl_vr11_firmware_xdsl already source their blobs. Tag
  ugw_8.5.2.10 provides xRx5xx/ltq_fw_PHY11G_IP_1v1_xRx5xx_A21_R8548.bin,
  sha256 d8269703afd369c28a6aeeb65d2751334e38e2228816eda0bdb11c2475b0df33.
  The same bytes, under the same name and with the same LICENSE file, are
  published in NETGEAR's RAX40/RAX38/RAX35 GPL source release
  (UGW-7.5.2.50/dl/ltq_fw_PHY_IP-2.3.tar.gz).

  xRx5xx is this silicon: GRX350 and GRX550 both take this blob. It is
  installed as lantiq/xrx500-phy-fw.bin, the path the device tree's
  firmware-name property names and therefore the string
  request_firmware_direct() looks up - renaming a vendor blob to the
  kernel's requested name follows the xRX200 packages in
  package/firmware/lantiq/lantiq-gphy-firmware.

  Two nearby revisions are easy to confuse. The repository's master branch
  carries A21 R8547; only the ugw-* branches carry R8548. The xRx3xx A21 blob
  is not a substitute: it loads without complaint and the links stay down.
  R8548 is the revision these boards were brought up and tested on.

  The firmware is covered by the Lantiq Software License Agreement, whose
  text is installed next to the blob as xrx500-phy-fw.bin.LICENSE, as the
  vrx518 firmware packages do. It is kept a separate file in the rootfs and
  is deliberately not built into the kernel image; kmod-dsa-lantiq-gswip-xrx500
  reads it from there.
endef

define Build/Compile
endef

define Package/xrx500-phy11g-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/lantiq
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE \
		$(1)/lib/firmware/lantiq/xrx500-phy-fw.bin.LICENSE
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/xRx5xx/ltq_fw_PHY11G_IP_1v1_xRx5xx_A21_R8548.bin \
		$(1)/lib/firmware/lantiq/xrx500-phy-fw.bin
endef

$(eval $(call BuildPackage,xrx500-phy11g-firmware))

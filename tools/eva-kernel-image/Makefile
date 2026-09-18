# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=eva-kernel-image
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

PKG_SOURCE:=eva_kernel_image-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/source/e/eva_kernel_image
PKG_HASH:=2dca3198c7bcc7129ba1d056bfe15693e0cce5695f677fbdf915300790522827
# the sdist unpacks to the normalised distribution name, not to PKG_NAME
HOST_BUILD_DIR:=$(BUILD_DIR_HOST)/eva_kernel_image-$(PKG_VERSION)

PKG_LICENSE:=AGPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/host-build.mk

# Staged as a zipapp because the sdist builds with hatchling/hatch-vcs, which
# pip would resolve over the network. files/__main__.py propagates main()'s
# exit status; the entry point `zipapp -m` generates discards it.
define Host/Prepare
	$(call Host/Prepare/Default)
	$(CP) ./files/__main__.py $(HOST_BUILD_DIR)/src/
endef

define Host/Compile
	$(STAGING_DIR_HOST)/bin/python3 -m zipapp $(HOST_BUILD_DIR)/src \
		--python "/usr/bin/env python3" \
		--output $(HOST_BUILD_DIR)/eva-image
endef

define Host/Install
	$(INSTALL_DIR) $(STAGING_DIR_HOST)/bin
	$(INSTALL_BIN) $(HOST_BUILD_DIR)/eva-image $(STAGING_DIR_HOST)/bin/
endef

define Host/Clean
	rm -f $(STAGING_DIR_HOST)/bin/eva-image
endef

$(eval $(call HostBuild))

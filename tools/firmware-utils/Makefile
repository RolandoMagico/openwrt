#
# Copyright (C) 2006-2020 OpenWrt.org
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=firmware-utils
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL=https://github.com/RolandoMagico/firmware-utils.git
PKG_SOURCE_DATE:=2023-12-30
PKG_SOURCE_VERSION:=9b4cb5642ebed7b851aca264570f94c51382f371
#PKG_MIRROR_HASH:=f34fbf4dc4bd13d18ea94e6e25090b57cde11b3dc7133e46f6ce3bb9164ab8fb

include $(INCLUDE_DIR)/host-build.mk
include $(INCLUDE_DIR)/cmake.mk

$(eval $(call HostBuild))

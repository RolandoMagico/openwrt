# SPDX-License-Identifier: GPL-2.0-only

define Device/d-link_covr-1100-a1
  SOC := rtl8197f
  KERNEL_SIZE := 6m
  IMAGE_SIZE := 26m
  DEVICE_VENDOR := D-Link
  DEVICE_MODEL := COVR-1100
  DEVICE_VARIANT := A1
endef
TARGET_DEVICES += d-link_covr-1100-a1

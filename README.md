ipq40xx: Add support for Linksys MR6350

This pull request is based on the discussions in https://forum.openwrt.org/t/adding-openwrt-support-for-linksys-mr6350.

Device Specs:
- 256 MB RAM
- 256 MB FLASH
- 4 LAN ports, 1 WAN port

Download initramfs:
- Connect serial interface
- Set up a TFTP server on IP 192.168.1.254
- Copy openwrt-ipq40xx-generic-linksys_mr6350-initramfs-zImage.itb to TFTP server
- Rename file to C0A80101.img
- Boot up the device and stop in U-Boot
- Run the following commands after a link has been established:
  tftp
  bootm

Initramfs image is started now.

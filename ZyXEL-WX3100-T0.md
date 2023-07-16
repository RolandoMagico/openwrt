# ZyXEL-WX3100-T0
## Hardware Specs
- CPU: ECONET EN7516GT
- RAM: 256MB
- FLAHS: 128MB W25N01G
- Wifi: MEDIATEK MT7975DN and MEDIATEK MT7905DEN

## OpenWrt Support
The CPU is currently not supported by OpenWrt.
- Similar device (same CPU): [ZyXEL VMG8623-T50B](Zyxel https://openwrt.org/toh/zyxel/vmg8623-t50b)

## UART Interface
The pins for UART are populated by default, pin assignment:
- GND
- not populated
- RXD
- TXD
- VCC

## OEM flash image
The oem flash image can be downloaded via bootloader using the command
```
ATUR FilenameOfImage
```

After executing the command, the image must be transmitted to the device using TFTP. Example:
```
ZHAL> ATUR test.img
Upgrade to rootfs partition 1
TFTP server is started, put your file 'test.img' to server (IP is 192.168.1.1).
```

The oem flash images contain a header. Until now, the following data are known:

| Start Address | Length | Data |
|---------------|------------|--------------------------------------------------|
| 0x00000000    | 0x00000004 | 	ASCII "2RDH"                                    |
| 0x00000004    | 0x00000004 | Length of the header (0x174: 372 Bytes)          |
| 0x00000008    | 0x00000004 | Length of the file (including header)            |
| 0x0000000C    | 0x00000004 | Checksum                                         |


## Useful links
[ramips: mt7621: Add support for ZyXEL NR7101](https://git.freifunk-franken.de/mirror/openwrt/commit/2449a632084b29632605e5a79ce5d73028eb15dd): Maybe it contains useful information how to use the bootloader, even if it's a different device

[Multiple Critical Vulnerabilities in multiple Zyxel devices](https://sec-consult.com/vulnerability-lab/advisory/multiple-critical-vulnerabilities-in-multiple-zyxel-devices/): Vulnerabilities wich may also apply to this device

[Unauthenticated remote root buffer overflow in Zyxel devices](https://youtu.be/hbF3LEljxSA): A YouTube video showing how to get shell access to the device using Metasploit framework




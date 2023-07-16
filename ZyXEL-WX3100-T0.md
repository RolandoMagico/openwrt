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

## SSH Access
The device can be accessed by SSH. The shell is ZySH which is quite limited in usage. I saw that traceroute can be crashed using
```
traceroute AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
```
This causes closing the SSH connection and additional output on the serial console:
```
Unhandled kernel unaligned access[#1]:
CPU: 3 PID: 3179 Comm: zysh Tainted: P           O   3.18.21 #1
task: 8af226b8 ti: 86174000 task.ti: 86174000
$ 0   : 00000000 00000001 0000003d376.685063: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d6:1a:d1:31:e6:65)
376.685328: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d6:1a:d1:21:e6:65)
376.685466: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d6:1a:d1:11:e6:65)
376.685604: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d4:1a:d1:11:e6:65)
376.685740: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d6:1a:d1:91:e6:65)
376.685913: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d6:1a:d1:71:e6:65)
376.686050: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d6:1a:d1:61:e6:65)
376.686188: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d6:1a:d1:51:e6:65)
376.686325: [mapd][send_ap_metric_rsp_to_own_device][260]bssid(d4:1a:d1:11:e6:66)
[_1905_Set_Ap_Metric_Rsp_Info][DEBUG] _1905_Set_Ap_Metric_Rsp_Info,ap_metrics_info_cnt = 9, sta_states_cnt =0, sta_metrics_cnt = 0

[1905Daemon][cmdu_send], [1458]no need send msg with dummy almac

 86177ce8
$ 4   : 811fe294 41414141 00000000 00000000
$ 8   : 8089bcdc afbf0000 3c1c0000 633a3078
$12   : 703a3078 81207248 00000000 37666130
$16   : 00000001 ffff0000 00000020 27bd0000
$20   : 00000000 00000000 afbe0000 41414141
$24   : 00000008 00000cb1
$28   : 86174000 86177c88 7fa04250 8004fd30
Hi    : 00000057
Lo    : b2af7d00
epc   : 8004fd70 backtrace_mips32+0xe4/0x1e0
    Tainted: P           O
ra    : 8004fd30 backtrace_mips32+0xa4/0x1e0
Status: 11000003        KERNEL EXL IE
Cause : 40807010
BadVA : 41414141
PrId  : 0001992f (MIPS 1004Kc)
Modules linked in: ebt_mark nf_nat_ftp nf_conntrack_ftp ebt_mark_m iptable_nat ip6t_ipv6header ip6t_ah ip6t_hbh ip6t_REJECT ip6t_rt ip6t_frag ip6t_mh ip6t_eui64 ip6table_raw ip6table_mangle nf_conntrack_ipv6 nf_defrag_ipv6 ip6table_filter ip6_tables xt_policer xt_AUTOMAP xt_DSCP xt_dscp zy_nfhook(O) sw_rps_for_wifi(O) dying_gasp(PO) hw_nat(PO) ebt_policer ebt_ip6 ebt_ip ebtable_filter ebtable_broute ebtables sch_prio sch_htb cls_fw act_mirred mapfilter(O) tc3162_dmt(PO) qdma_wan(PO) eth_ephy(PO) eth(PO) qdma_lan(PO) fe_core(PO) sif(PO) tccicmd(PO) tcledctrl(PO) speedtest(PO) tcvlantag(O) tcportbind(O) tcsmux(O) module_sel(PO)
Process zysh (pid: 3179, threadinfo=86174000, task=8af226b8, tls=77bbb460)
Stack : 8a23bd40 7fa04250 41414141 41414141 8a396400 86177e60 41414141 80990000
          80980000 807d9348 8a23bd40 86177f28 00020000 86177e78 8a396400 86177e60
          8a23c944 80990000 80980000 8004fecc 80ed0000 08100000 00000001 80ec5db0
          41414141 80070dc8 80897774 80897778 80ecb950 86177e18 00000001 00000000
          812097a8 80ed0000 80ed0000 80ed0000 812097a8 80ed0000 80ed0000 80ed0000
          ...
Call Trace:
[<8004fd70>] backtrace_mips32+0xe4/0x1e0
[<8004fecc>] do_backtrace_mips32+0x58/0xec
[<8003d248>] get_signal+0x58c/0x5e0
[<80012e90>] do_signal+0x18/0x20c
[<80013ed0>] do_notify_resume+0x64/0x74
[<8000f420>] work_notifysig+0xc/0x14


Code: 00003021  3c09afbf  3c0a3c1c <8ca20000> 00512024  10930022  00000000  1089001e  00000000
---[ end trace b7c703d0b16b5625 ]---

```
## Useful links
[ramips: mt7621: Add support for ZyXEL NR7101](https://git.freifunk-franken.de/mirror/openwrt/commit/2449a632084b29632605e5a79ce5d73028eb15dd): Maybe it contains useful information how to use the bootloader, even if it's a different device

[Multiple Critical Vulnerabilities in multiple Zyxel devices](https://sec-consult.com/vulnerability-lab/advisory/multiple-critical-vulnerabilities-in-multiple-zyxel-devices/): Vulnerabilities wich may also apply to this device

[Unauthenticated remote root buffer overflow in Zyxel devices](https://youtu.be/hbF3LEljxSA): A YouTube video showing how to get shell access to the device using Metasploit framework




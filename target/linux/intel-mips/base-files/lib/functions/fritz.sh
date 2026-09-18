# SPDX-License-Identifier: GPL-2.0-only
#
# Shared AVM FRITZ!Box helpers for intel-mips.
#
# Everything in here reads the per-unit factory data AVM leaves in flash.
# It lives in its own file rather than in board.d because more than one
# consumer needs it: etc/board.d/02_network for the Ethernet addresses and
# etc/hotplug.d/ieee80211/05_fix_wifi_mac for the 7580's radios.
#

#
# Read one MAC-valued TFFS entry: fritz_tffs_mac <chardev> <key>.
# fritz_tffs_nand does raw MEMREADOOB reads, so it needs the mtd char
# device, and TFFS values are not necessarily NUL-terminated at their
# stated length — the output is filtered down to the characters a MAC
# can be spelled with before anyone looks at it.
#
# Two read attempts. -o asks the tool to cross-check each sector's
# spare-area header mirror against the in-band header, and the 7560
# depends on it: the tool requests 64 spare bytes where that board's
# on-die-ECC layout frees only 62, the last page EINVALs, and only
# under -o is that a skipped sector rather than an aborted read.
#
# The plain read is the fallback. AVM writes the mirrors on every
# firmware version, but the tool used to look for them at fixed raw
# spare-area offsets, which are ECC parity on a chip whose free bytes
# are split into several ranges (Macronix MX30LF4GE8AB, found in some
# 7590s) — so -o rejected every sector there. It now asks mtd for
# the free bytes instead, which is layout agnostic; the fallback
# remains for unknown chips and for kernels without MEMREAD (< 6.1).
# An empty first attempt costs one retry, and junk never gets past the
# callers' case patterns.
#
# Do NOT add -b to either attempt. It byte-swaps the on-flash
# big-endian fields for little-endian hosts; this target is big-endian,
# where the swap turns correct values into garbage.
#
fritz_tffs_mac() {
	local val
	val=$(/usr/bin/fritz_tffs_nand -d "$1" -n "$2" -o 2>/dev/null |
		tr -dc '0-9A-Fa-f:')
	[ -n "$val" ] || val=$(/usr/bin/fritz_tffs_nand -d "$1" -n "$2" 2>/dev/null |
		tr -dc '0-9A-Fa-f:')
	echo "$val"
}

#!/bin/sh
#
# Packet steering for intel-mips.
#
# /etc/init.d/packet_steering prefers this script over the generic one when it
# exists, and runs it at boot and on every network or firewall reload. It has
# to exist, because the generic script runs whether packet steering is asked
# for or not, and what it settles on for the buffer-manager conduits is one
# core.
#
# Each switch macro has exactly one receive queue in hardware and its
# interrupt is registered IRQF_NOBALANCING, so the poll always runs on the
# core the interrupt landed on at boot -- core 0. The conduits' receive
# packet steering has to leave that core out. A flow steered onto it runs
# the protocol stack on the same core as the poll.
#
# So the conduits get every online core except core 0, which is "e" on the
# four-VPE parts this target builds for. If the receive interrupt's affinity
# is ever moved off core 0, this has to move with it.
#
# Everything else -- the wireless devices, the NAPI thread affinity, the
# flow-count option -- is left to the generic script, which runs first.

steering="$1"

opts=
steering_flows="$(uci -q get network.@globals[0].steering_flows)"
[ "${steering_flows:-0}" -gt 0 ] && opts="-l $steering_flows"

/usr/libexec/network/packet-steering.uc $opts "$steering"

# An explicit "off" is the administrator's decision and stands.
[ "$steering" = "0" ] && exit 0

mask=0
for cpudir in /sys/devices/system/cpu/cpu[0-9]*; do
	id="${cpudir##*/cpu}"
	[ "$id" = 0 ] && continue
	[ -f "$cpudir/online" ] && [ "$(cat "$cpudir/online")" = 0 ] && continue
	mask=$((mask | (1 << id)))
done

[ "$mask" -gt 0 ] || exit 0

for queue in /sys/class/net/cbm*/queues/rx-*/rps_cpus; do
	[ -w "$queue" ] || continue
	printf '%x\n' "$mask" > "$queue"
done

exit 0

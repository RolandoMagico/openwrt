#!/bin/bash
set -e

./scripts/feeds update -a
./scripts/feeds install -a

# Write changes to .config
cp diffconfig .config
 
# Expand to full config
make defconfig

# Number of jobs used for make: Use number of processors
OPENWRT_BUILD_JOB_COUNT=$(cat /proc/cpuinfo | grep processor | wc -l)

make -j${OPENWRT_BUILD_JOB_COUNT}

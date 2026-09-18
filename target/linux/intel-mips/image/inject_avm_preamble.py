#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""
inject_avm_preamble.py — patch an OpenWrt MIPS kernel-bin so AVM's 7560
urlader's DTB scanner finds a SubRevision-matching DTB.

AVM's urlader expects, at the KERNEL ENTRY ADDRESS, this layout:

    +0x00  BEQ zero, zero, +3   (skips 3 words so the CPU resumes at +0x10)
    +0x04  NOP                  (delay slot)
    +0x08  NOP                  (the kernel's own second nop)
    +0x0C  u32  pointer to DTB table header (big-endian, virtual address)
    +0x10  (real kernel code continues here)

The DTB table header, in turn, is:
    +0x00  u32  pointer to first entry  (self-pointer, +0x10)
    +0x04..+0x0F  zero padding
    +0x10  entry[0]: u32 key, u32 ptr     (subrev index = key - 5)
    +0x18  entry[1]: u32 key, u32 ptr
    ...
    +0xNN  entry[last]: u32 key, 0x00000000  (terminator: ptr == 0)

The urlader looks up `table[HWSubRevision]`. When no entry matches, it writes
a DTB of its own over the slot the table points at, which is what the second
appended copy of the board DTB absorbs.

The OpenWrt lantiq/xrx500 fritz7560 kernel is linked at 0x80020000 with
__kernel_entry at 0x80020400 (the first 0x400 bytes are zero padding).
We inject the AVM preamble into those 0x400 zero bytes and set the TI
record's entry_addr = 0x80020000 so the CPU lands on the BEQ, which
harmlessly branches to the real __kernel_entry at 0x80020400.

Usage:
  ./inject_avm_preamble.py INPUT.bin OUTPUT.bin LOAD_ADDR

INPUT.bin  = raw OpenWrt vmlinux.bin (before LZMA, before EVA container)
OUTPUT.bin = patched binary, feed this to `eva-image pack --kernel1 OUTPUT.bin --entry1 LOAD_ADDR ...`
LOAD_ADDR  = virtual load address of the kernel image (e.g., 0x80020000)

The script scans the input for all DTBs (FDT magic), reads each DTB's
/avm-hw-revision/subrevision property, and builds a table entry for
every DTB that has one.
"""

import struct
import sys

FDT_MAGIC = 0xD00DFEED


def u32be(b, off):
    return struct.unpack('>I', b[off:off+4])[0]


def find_fdts(data):
    """Return a list of (file_offset, total_size) for every FDT magic found."""
    out = []
    pos = 0
    magic = struct.pack('>I', FDT_MAGIC)
    while True:
        p = data.find(magic, pos)
        if p < 0:
            break
        if p + 8 <= len(data):
            total_size = u32be(data, p + 4)
            if 0 < total_size < 2 * 1024 * 1024 and p + total_size <= len(data):
                out.append((p, total_size))
        pos = p + 4
    return out


def get_fdt_subrevision(data, fdt_off, fdt_size):
    """Parse a DTB and return the string value of /avm-hw-revision/subrevision, or None."""
    fdt = data[fdt_off:fdt_off + fdt_size]
    # Minimal FDT walker: find the strings block, then walk the struct block.
    # Header: magic(4) totalsize(4) off_dt_struct(4) off_dt_strings(4) off_mem_rsvmap(4)
    #         version(4) last_comp(4) boot_cpuid(4) size_dt_strings(4) size_dt_struct(4)
    off_struct  = u32be(fdt, 8)
    off_strings = u32be(fdt, 12)
    size_strings = u32be(fdt, 32)
    strs = fdt[off_strings:off_strings + size_strings]

    # Token definitions: FDT_BEGIN_NODE=1, FDT_END_NODE=2, FDT_PROP=3, FDT_NOP=4, FDT_END=9
    pos = off_struct
    depth = 0
    in_avm_hw = False
    avm_hw_depth = -1
    while pos < len(fdt) - 4:
        tok = u32be(fdt, pos)
        pos += 4
        if tok == 1:  # BEGIN_NODE
            end = fdt.find(b'\x00', pos)
            name = fdt[pos:end].decode('ascii', errors='replace')
            pos = (end + 4) & ~3  # align to 4
            depth += 1
            if name == 'avm-hw-revision':
                in_avm_hw = True
                avm_hw_depth = depth
        elif tok == 2:  # END_NODE
            if in_avm_hw and depth == avm_hw_depth:
                in_avm_hw = False
            depth -= 1
        elif tok == 3:  # PROP
            plen = u32be(fdt, pos)
            pname_off = u32be(fdt, pos + 4)
            pos += 8
            pname_end = strs.find(b'\x00', pname_off)
            pname = strs[pname_off:pname_end].decode('ascii', errors='replace')
            pvalue = fdt[pos:pos + plen]
            pos = (pos + plen + 3) & ~3
            if in_avm_hw and pname == 'subrevision':
                # Value is a null-terminated string
                return pvalue.rstrip(b'\x00').decode('ascii', errors='replace')
        elif tok == 4:  # NOP
            pass
        elif tok == 9:  # END
            break
        else:
            break
    return None


def main():
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    inp, outp, load_addr = sys.argv[1], sys.argv[2], int(sys.argv[3], 0)

    with open(inp, 'rb') as f:
        data = bytearray(f.read())

    # Sanity: first 0x400 bytes must be mostly zero (our preamble scratch area)
    if any(data[:0x40]):
        print(f"WARNING: first 0x40 bytes are not all zero; preamble may collide with code.",
              file=sys.stderr)

    # Find all DTBs and their subrevisions
    fdts = find_fdts(data)
    print(f"Found {len(fdts)} FDT(s) in {inp}:")
    subrev_to_va = {}
    for fdt_off, fdt_size in fdts:
        va = load_addr + fdt_off
        subrev = get_fdt_subrevision(data, fdt_off, fdt_size)
        mark = f"  subrev={subrev!r}" if subrev is not None else "  (no avm-hw-revision node)"
        print(f"  @0x{fdt_off:06x} size={fdt_size:<6d}  VA=0x{va:08x}{mark}")
        if subrev is not None:
            try:
                subrev_int = int(subrev)
                if 0 <= subrev_int < 256:
                    subrev_to_va[subrev_int] = va
            except ValueError:
                print(f"    (could not parse subrev={subrev!r} as int; skipping)", file=sys.stderr)

    if not subrev_to_va:
        print("ERROR: no DTB with /avm-hw-revision/subrevision found. Cannot build table.",
              file=sys.stderr)
        sys.exit(2)

    # Build preamble in the first 0x400 bytes.
    #
    # Layout (file offset 0x00..0x3FF, all big-endian u32):
    #
    #   0x00  BEQ zero,zero,+0xFF    0x100000FF  (skip to kernel code at +0x400)
    #   0x04  NOP                    0x00000000
    #   0x08  (unused)               0x00000000
    #   0x0C  u32 ptr to tbl header = load_addr + 0x20
    #   0x10..0x1F  zero
    #   0x20  u32 self-pointer       = load_addr + 0x30   (first entry)
    #   0x24..0x2F  zero
    #   0x30  first entry: key, ptr
    #   0x38  next entry, ...
    #   ...
    #   0xNN  terminator entry: key=0x107 (avm_kernel_config_tags_last), ptr=0
    #   rest zero
    #
    # Entry key = subrevision + 5. The device-tree tags start at enum ordinal 5
    # in the vendor's avm_kernel_config_device_tree.h.

    # Branch to 0x400 as an offset from (branch_pc + 4):
    #   offset = (0x80020400 - 0x80020004) / 4 = 0xFF
    BEQ_OP = 0x10000000 | 0xFF  # beq $zero, $zero, +0xFF
    table_hdr_va   = load_addr + 0x20
    entries_va     = load_addr + 0x30

    preamble = bytearray(0x400)  # all zero by default
    struct.pack_into('>I', preamble, 0x00, BEQ_OP)
    struct.pack_into('>I', preamble, 0x04, 0x00000000)
    struct.pack_into('>I', preamble, 0x08, 0x00000000)
    struct.pack_into('>I', preamble, 0x0C, table_hdr_va)

    # Table header
    struct.pack_into('>I', preamble, 0x20, entries_va)
    # 0x24..0x2F already zero

    # Entries
    entry_off = 0x30
    for subrev in sorted(subrev_to_va.keys()):
        key = subrev + 5
        ptr = subrev_to_va[subrev]
        struct.pack_into('>II', preamble, entry_off, key, ptr)
        entry_off += 8
    # Terminator. Its tag is avm_kernel_config_tags_last and its pointer is
    # null, and a walk ends at either.
    struct.pack_into('>II', preamble, entry_off, 0x107, 0x00000000)
    entry_off += 8

    # Overlay the preamble on the input
    data[:0x400] = preamble

    with open(outp, 'wb') as f:
        f.write(bytes(data))

    print(f"\nInjected AVM preamble into {outp}")
    print(f"  BEQ @0x{load_addr:08x} -> 0x{load_addr + 0x400:08x}")
    print(f"  Table hdr ptr  @0x{load_addr + 0x0C:08x} -> 0x{table_hdr_va:08x}")
    print(f"  Entries start  @0x{table_hdr_va:08x} -> 0x{entries_va:08x}")
    print(f"  Pack with: eva-image pack ... --kernel1 {outp} --load1 0x{load_addr:08x} --entry1 0x{load_addr:08x}")


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Rebuild the released BC-250 P3.00 8-core ROM.

The released image contains two surgical changes over the pinned 16 MiB base:

1. Insert Bc250CoreUnlockPei into the existing PEI firmware-volume pad region.
2. Change the AmdCcxVhAriPei OPN downcore token from SIX (0x07) to Auto (0x00).

The assembler rejects every unrecognized base, PEIM, layout, or patch context.
It verifies the changed ranges and the final release SHA-256 before writing.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
from pathlib import Path

BASE_ROM_SHA256 = "2854b3863b447e71212890d9a2fcc5b79623a7b66b5aefd827d39d5c23cf42ca"
PEIM_FFS_SHA256 = "ceaafd7b0896d4631e951662e5aa5e46d1883623b2fb228d93800bc39c1cf40d"
OUTPUT_ROM_SHA256 = "1b7bcaa65e247363ad19e6a1dd3e296ae54b254fdeeeb32c8fb8ac505c86ac17"
ROM_SIZE = 16 * 1024 * 1024

PEIM_GUID = bytes.fromhex("8a1bec457a95e84488bd7ff8abae06bb")
CCX_FILE_OFFSET = 0xE14AC8
# CCX TE payload: depex section (0x70) at 0xE14AE0, TE header at 0xE14B50.
# TE offset 0x608 is the immediate of `movb $0x07,-4(%ebp)` - the OPN token
# SIX(=3+3 cores, mask 0x88). Zeroing it selects the Auto case, so CCX never
# calls SmuSetDownCoreRegister and our presence flip survives.
CCX_TE_PAYLOAD_OFFSET = 0xE14B54
CCX_PATCH_OFFSET = CCX_TE_PAYLOAD_OFFSET + 0x608
CCX_PATCH_OLD = 0x07
CCX_PATCH_NEW = 0x00
PAD_ORIGINAL_SIZE = 0x105FC8
PAD_HEADER_OFFSET = 0xEF8B20
FFS_HEADER_SIZE = 24
FFS_FIXED_CHECKSUM = 0xAA


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def ffs_header_checksum(header: bytearray) -> int:
    """PI spec: with IntegrityCheck.File and State treated as zero, the whole
    header (including the Header checksum byte itself) must sum to zero."""
    work = bytearray(header)
    work[16] = 0
    work[17] = 0
    work[23] = 0
    return (-sum(work)) & 0xFF

def make_pad_file(length: int) -> bytes:
    assert length >= FFS_HEADER_SIZE
    header = bytearray(b"\xff" * FFS_HEADER_SIZE)
    header[18] = 0xF0  # EFI_FV_FILETYPE_FFS_PAD
    header[19] = 0x00
    header[20] = length & 0xFF
    header[21] = (length >> 8) & 0xFF
    header[22] = (length >> 16) & 0xFF
    header[23] = 0xF8  # erase-polarity-1 constructed/valid/data-valid
    header[16] = ffs_header_checksum(header)
    header[17] = FFS_FIXED_CHECKSUM
    return bytes(header)


def adapt_ffs_to_erase_polarity_1(ffs: bytes) -> bytes:
    """The development FV stores State with erase polarity 0 (0x07); the
    target PEI FV uses polarity 1, where the same state reads 0xF8."""
    converted = bytearray(ffs)
    if converted[18] != 0x06:
        raise SystemExit("not a PEIM")
    if converted[23] not in (0x07, 0xF8):
        raise SystemExit(f"unexpected PEIM state byte {converted[23]:#x}")
    expected = ffs_header_checksum(converted[:FFS_HEADER_SIZE])
    if expected != converted[16]:
        raise SystemExit(f"source PEIM header checksum broken: {converted[16]:#x} != {expected:#x}")
    converted[23] = 0xF8
    # State is excluded from the header checksum, so it stays valid.
    return bytes(converted)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--base-rom",
        type=Path,
        required=True,
        help=f"16 MiB base ROM with SHA-256 {BASE_ROM_SHA256}",
    )
    parser.add_argument(
        "--peim-ffs",
        type=Path,
        default=Path("build-output/BC250CoreUnlockPei-BUILD/Bc250CoreUnlockPei.ffs"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("BC250-P3.00-8Core.rebuilt.rom"),
    )
    args = parser.parse_args()

    rom = bytearray(args.base_rom.read_bytes())
    peim_ffs = args.peim_ffs.read_bytes()
    if len(rom) != ROM_SIZE:
        raise SystemExit(f"unexpected base ROM size: {len(rom)}")
    if sha256(bytes(rom)) != BASE_ROM_SHA256:
        raise SystemExit(f"unexpected base ROM SHA-256: {sha256(bytes(rom))}")
    if sha256(peim_ffs) != PEIM_FFS_SHA256:
        raise SystemExit(f"unexpected PEIM FFS SHA-256: {sha256(peim_ffs)}")
    if peim_ffs[:16] != PEIM_GUID or peim_ffs[18] != 0x06:
        raise SystemExit("PEIM FFS header mismatch")
    peim_ffs = adapt_ffs_to_erase_polarity_1(peim_ffs)

    # --- 1. pad region checks -------------------------------------------------
    pad_header = rom[PAD_HEADER_OFFSET:PAD_HEADER_OFFSET + FFS_HEADER_SIZE]
    pad_size = pad_header[20] | pad_header[21] << 8 | pad_header[22] << 16
    if pad_header[18] != 0xF0 or pad_size != PAD_ORIGINAL_SIZE:
        raise SystemExit(f"unexpected pad file at {PAD_HEADER_OFFSET:#x}: type={pad_header[18]:#x} size={pad_size:#x}")
    pad_end = PAD_HEADER_OFFSET + PAD_ORIGINAL_SIZE
    tail_start = (PAD_HEADER_OFFSET + len(peim_ffs) + 7) & ~7
    ffs_room = tail_start - (PAD_HEADER_OFFSET + FFS_HEADER_SIZE)
    if any(byte != 0xFF for byte in rom[PAD_HEADER_OFFSET + FFS_HEADER_SIZE:PAD_HEADER_OFFSET + FFS_HEADER_SIZE + ffs_room]):
        raise SystemExit("pad region ahead of the PEIM is not erased")

    # --- 2. insert PEIM FFS + recreated pad ----------------------------------
    # The recreated pad spans the remainder of the original pad file, so the
    # legacy bytes near 0xffe000 stay untouched inside an ignored pad body.
    new_pad_size = pad_end - tail_start
    rom[PAD_HEADER_OFFSET:PAD_HEADER_OFFSET + len(peim_ffs)] = peim_ffs
    rom[tail_start:tail_start + FFS_HEADER_SIZE] = make_pad_file(new_pad_size)

    # --- 3. CCX OPN-Auto byte patch ------------------------------------------
    window = rom[CCX_PATCH_OFFSET - 3:CCX_PATCH_OFFSET + 1]
    if window != bytes.fromhex("c645fc07"):
        raise SystemExit(f"unexpected CCX OPN store at {CCX_PATCH_OFFSET:#x}: {window.hex()}")
    rom[CCX_PATCH_OFFSET] = CCX_PATCH_NEW

    # --- 4. verification ------------------------------------------------------
    changed_ranges = []
    diff_run = None
    base = args.base_rom.read_bytes()
    for offset in range(len(base)):
        if base[offset] != rom[offset]:
            if diff_run is None:
                diff_run = offset
        elif diff_run is not None:
            changed_ranges.append((diff_run, offset))
            diff_run = None
    if diff_run is not None:
        changed_ranges.append((diff_run, len(base)))
    merged = []
    for start, end in changed_ranges:
        if merged and start - merged[-1][1] < 64:
            merged[-1] = (merged[-1][0], end)
        else:
            merged.append((start, end))
    print("changed ranges vs base:")
    for start, end in merged:
        print(f"  {start:#09x}..{end:#09x} ({end - start} bytes)")

    expected = [
        (CCX_PATCH_OFFSET, CCX_PATCH_OFFSET + 1),
        (PAD_HEADER_OFFSET, tail_start + FFS_HEADER_SIZE),
    ]
    if len(merged) != len(expected) or any(
        not (a[0] <= b[0] and b[1] <= a[1]) for a, b in zip(expected, merged)
    ):
        raise SystemExit(f"unexpected change layout: {[(hex(a),hex(b)) for a,b in merged]}")

    output = bytes(rom)
    output_hash = sha256(output)
    if output_hash != OUTPUT_ROM_SHA256:
        raise SystemExit(f"unexpected output ROM SHA-256: {output_hash}")
    args.output.write_bytes(output)
    print(f"wrote {args.output}")
    print(f"output SHA-256: {output_hash}")
    print(f"base  SHA-256: {BASE_ROM_SHA256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Decode FFXI's English status-icon DAT metadata for research and review."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


RECORD_SIZE = 0x1800


def bit_count(value: int) -> int:
    return value.bit_count()


def rotate_right(value: int, shift: int) -> int:
    return ((value >> shift) | (value << (8 - shift))) & 0xFF


def decode_record(data: bytes) -> bytes:
    value = bit_count(data[2]) - bit_count(data[11]) + bit_count(data[12])
    shift = (7, 1, 6, 2, 5)[abs(value) % 5]
    return bytes(rotate_right(byte, shift) for byte in data)


def text_at(data: bytes, offset: int, size: int) -> str:
    raw = data[offset : offset + size].split(b"\0", 1)[0]
    return raw.decode("cp1252", errors="replace").strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dat", type=Path)
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    raw = args.dat.read_bytes()
    count = len(raw) // RECORD_SIZE
    if len(raw) % RECORD_SIZE:
        raise SystemExit(f"Unexpected DAT size {len(raw)}; not a multiple of {RECORD_SIZE}.")

    print("index\tid\theader_00_2b\tdescription\thelp")
    for index in range(count if args.limit is None else min(count, args.limit)):
        start = index * RECORD_SIZE
        decoded = decode_record(raw[start : start + RECORD_SIZE])
        status_id = struct.unpack_from("<H", decoded, 0)[0]
        header = decoded[:0x2C].hex(" ")
        description = text_at(decoded, 0x2C, 0x100).replace("\t", " ")
        help_text = text_at(decoded, 0x42, 0x80).replace("\t", " ")
        print(f"{index}\t{status_id}\t{header}\t{description}\t{help_text}")


if __name__ == "__main__":
    main()

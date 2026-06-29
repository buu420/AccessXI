from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path


DEFAULT_FFXI_ROOT = Path(r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI")
DEFAULT_ADDON = Path(r"C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua")
DEFAULT_SUPERWARP_GUIDES = Path(r"C:\Users\buu42\windower\addons\superwarp\map\guides.lua")


def decode_text(raw: bytes) -> str:
    raw = raw.split(b"\x00", 1)[0]
    for encoding in ("cp932", "shift_jis", "utf-8", "latin-1"):
        try:
            return raw.decode(encoding).strip()
        except UnicodeDecodeError:
            pass
    return raw.decode("latin-1", errors="replace").strip()


def parse_xistring(path: Path) -> list[tuple[int, str]]:
    data = path.read_bytes()
    if not data.startswith(b"XISTRING"):
        return []
    if len(data) < 0x38:
        return []

    count = struct.unpack_from("<I", data, 0x24)[0]
    if count <= 0 or count > 0x10000:
        return []

    table_start = 0x38
    text_start = table_start + (count * 12)
    if text_start > len(data):
        return []

    rows: list[tuple[int, str]] = []
    for index in range(count):
        rec = table_start + (index * 12)
        offset, length, _unused = struct.unpack_from("<III", data, rec)
        if length == 0:
            continue
        start = text_start + offset
        end = min(start + length, len(data))
        if start >= len(data) or end <= start:
            continue
        text = decode_text(data[start:end])
        if text:
            rows.append((index, text))
    return rows


def resolve_dat_id(root: Path, file_id: int) -> Path | None:
    tables = [
        ("", "VTABLE.DAT", "FTABLE.DAT"),
        ("ROM2", "VTABLE2.DAT", "FTABLE2.DAT"),
        ("ROM3", "VTABLE3.DAT", "FTABLE3.DAT"),
        ("ROM4", "VTABLE4.DAT", "FTABLE4.DAT"),
        ("ROM5", "VTABLE5.DAT", "FTABLE5.DAT"),
        ("ROM6", "VTABLE6.DAT", "FTABLE6.DAT"),
        ("ROM7", "VTABLE7.DAT", "FTABLE7.DAT"),
        ("ROM8", "VTABLE8.DAT", "FTABLE8.DAT"),
        ("ROM9", "VTABLE9.DAT", "FTABLE9.DAT"),
    ]
    for prefix, vtable, ftable in tables:
        base = root / prefix if prefix else root
        vpath = base / vtable
        fpath = base / ftable
        if not vpath.exists() or not fpath.exists():
            continue
        vdata = vpath.read_bytes()
        if file_id >= len(vdata):
            continue
        rom_index = vdata[file_id]
        if rom_index == 0:
            continue
        fdata = fpath.read_bytes()
        offset = file_id * 2
        if offset + 2 > len(fdata):
            continue
        file_value = struct.unpack_from("<H", fdata, offset)[0]
        relative = Path("ROM") / str(file_value >> 7) / f"{file_value & 0x7F}.DAT"
        if rom_index != 1:
            relative = Path(f"ROM{rom_index}") / str(file_value >> 7) / f"{file_value & 0x7F}.DAT"
        return root / relative
    return None


def parse_d_msg(path: Path) -> list[tuple[int, str]]:
    data = bytearray(path.read_bytes())
    if not data.startswith(b"d_msg") or len(data) < 0x40:
        return []

    data_encoded = struct.unpack_from("<H", data, 0x0A)[0]
    file_size = struct.unpack_from("<I", data, 0x14)[0]
    header_size = struct.unpack_from("<I", data, 0x18)[0]
    toc_size = struct.unpack_from("<I", data, 0x1C)[0]
    entry_count = struct.unpack_from("<I", data, 0x28)[0]
    file_size = min(file_size, len(data))

    if data_encoded == 1:
        for i in range(0x40, file_size):
            data[i] ^= 0xFF

    rows: list[tuple[int, str]] = []
    for index in range(entry_count):
        toc = header_size + (index * 8)
        if toc + 8 > len(data):
            break
        offset, length = struct.unpack_from("<II", data, toc)
        if length == 0 or offset + length > max(0, file_size - header_size):
            continue
        entry_start = header_size + toc_size + offset
        entry_end = min(entry_start + length, len(data))
        entry = data[entry_start:entry_end]
        if len(entry) < 4:
            continue
        count = struct.unpack_from("<I", entry, 0)[0]
        if count <= 0 or 4 + (count * 8) > len(entry):
            continue
        for child in range(count):
            rec = 4 + (child * 8)
            child_offset, flag = struct.unpack_from("<II", entry, rec)
            if flag != 0 or child_offset == 0:
                continue
            text_start = child_offset + 0x1C
            if text_start >= len(entry):
                continue
            out = bytearray()
            pos = text_start
            while pos < len(entry):
                chunk = entry[pos : min(pos + 4, len(entry))]
                out.extend(chunk)
                pos += 4
                if len(chunk) < 4 or chunk[-1] == 0:
                    break
            text = decode_text(bytes(out))
            if text:
                rows.append((index, text))
            break
    return rows


def dat_files(root: Path) -> list[Path]:
    dirs = [root / "ROM"] + [root / f"ROM{i}" for i in range(2, 10)]
    files: list[Path] = []
    for directory in dirs:
        if directory.exists():
            files.extend(sorted(directory.rglob("*.DAT")))
    return files


def parse_survival_guide_lua(path: Path) -> list[dict[str, int]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    rows: list[dict[str, int]] = []
    pattern = re.compile(
        r"\{\s*index\s*=\s*(\d+),\s*unlock_bit\s*=\s*(\d+),\s*content\s*=\s*(\d+),\s*zone\s*=\s*(\d+)\s*\}"
    )
    for match in pattern.finditer(text):
        rows.append(
            {
                "index": int(match.group(1)),
                "unlock_bit": int(match.group(2)),
                "content": int(match.group(3)),
                "zone": int(match.group(4)),
            }
        )
    return rows


def parse_superwarp_guides(path: Path) -> list[dict[str, int | str]]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="replace")
    rows: list[dict[str, int | str]] = []
    pattern = re.compile(
        r'\["([^"]+)"\]\s*=\s*\{\s*index\s*=\s*(\d+),\s*offset\s*=\s*(\d+),\s*zone\s*=\s*(\d+),'
    )
    for match in pattern.finditer(text):
        rows.append(
            {
                "label": match.group(1),
                "index": int(match.group(2)),
                "unlock_bit": int(match.group(3)),
                "zone": int(match.group(4)),
            }
        )
    return rows


def compare_guide_tables(addon_rows: list[dict[str, int]], superwarp_rows: list[dict[str, int | str]]) -> None:
    if not superwarp_rows:
        print("\nSuperwarp comparison: skipped, table not found")
        return

    print("\nSuperwarp comparison")
    addon_by_index = {row["index"]: row for row in addon_rows}
    super_by_index = {int(row["index"]): row for row in superwarp_rows}
    indexes = sorted(set(addon_by_index) | set(super_by_index))
    mismatches = []
    for index in indexes:
        addon = addon_by_index.get(index)
        superwarp = super_by_index.get(index)
        if addon is None:
            mismatches.append(f"missing-in-addon index={index} superwarp={superwarp}")
            continue
        if superwarp is None:
            mismatches.append(f"missing-in-superwarp index={index} addon={addon}")
            continue
        if addon["unlock_bit"] != int(superwarp["unlock_bit"]) or addon["zone"] != int(superwarp["zone"]):
            mismatches.append(f"mismatch index={index} addon={addon} superwarp={superwarp}")
    print(f"superwarp rows={len(superwarp_rows)} mismatches={len(mismatches)}")
    for item in mismatches[:40]:
        print(f"  {item}")


def fmt_path(path: Path, root: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def print_xistring_summary(root: Path, terms: list[str]) -> None:
    print("XISTRING tables")
    for path in dat_files(root):
        rows = parse_xistring(path)
        if not rows:
            continue
        sample = "; ".join(f"{i}:{t}" for i, t in rows[:4])
        print(f"{fmt_path(path, root)}\trows={len(rows)}\t{sample}")
        for term in terms:
            hits = [(i, t) for i, t in rows if term.lower() in t.lower()]
            if hits:
                joined = "; ".join(f"{i}:{t}" for i, t in hits[:8])
                print(f"  term={term!r}\t{joined}")


def print_dat_id_summary(root: Path, file_id: int, terms: list[str]) -> None:
    path = resolve_dat_id(root, file_id)
    if path is None:
        print(f"\nDAT id {file_id}: unresolved")
        return
    rows = parse_d_msg(path)
    print(f"\nDAT id {file_id}: {fmt_path(path, root)} d_msg rows={len(rows)}")
    if rows:
        print("  sample " + "; ".join(f"{i}:{t}" for i, t in rows[:8]))
    for term in terms:
        hits = [(i, t) for i, t in rows if term.lower() in t.lower()]
        if hits:
            print(f"  term={term!r}\t" + "; ".join(f"{i}:{t}" for i, t in hits[:12]))


def search_exact_bytes(root: Path, patterns: list[tuple[str, bytes]]) -> None:
    print("\nExact byte patterns")
    for name, pattern in patterns:
        hits: list[str] = []
        for path in dat_files(root):
            data = path.read_bytes()
            off = data.find(pattern)
            if off >= 0:
                hits.append(f"{fmt_path(path, root)}@0x{off:X}")
        print(f"{name}\tlen={len(pattern)}\thits={len(hits)}")
        for hit in hits[:20]:
            print(f"  {hit}")


def search_strided_zone_sequence(root: Path, zones: list[int], min_match: int) -> None:
    first = zones[0]
    first16 = struct.pack("<H", first)
    strides = (2, 4, 6, 8, 10, 12, 16)
    print("\nStrided Survival Guide zone sequence search")
    best: list[tuple[int, str, int, int, list[int]]] = []
    for path in dat_files(root):
        data = path.read_bytes()
        start = 0
        while True:
            off = data.find(first16, start)
            if off < 0:
                break
            for stride in strides:
                matched: list[int] = []
                for i, zone in enumerate(zones):
                    pos = off + (i * stride)
                    if pos + 2 > len(data):
                        break
                    value = struct.unpack_from("<H", data, pos)[0]
                    if value != zone:
                        break
                    matched.append(value)
                if len(matched) >= min_match:
                    best.append((len(matched), fmt_path(path, root), off, stride, matched[:12]))
            start = off + 1
    best.sort(reverse=True)
    for count, path, off, stride, sample in best[:40]:
        print(f"match={count}\tstride={stride}\t{path}@0x{off:X}\tsample={sample}")
    if not best:
        print("no strided zone sequence hits")


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Decode FFXI XISTRING resources and search Survival Guide resource patterns.")
    parser.add_argument("--root", type=Path, default=DEFAULT_FFXI_ROOT)
    parser.add_argument("--addon", type=Path, default=DEFAULT_ADDON)
    parser.add_argument("--superwarp-guides", type=Path, default=DEFAULT_SUPERWARP_GUIDES)
    parser.add_argument("--terms", nargs="*", default=["Survival Guide", "Original release areas", "Teleportation Assistance", "West Ronfaure", "Rabao"])
    parser.add_argument("--dat-id", type=int, action="append", default=[55465])
    parser.add_argument("--min-match", type=int, default=8)
    args = parser.parse_args()

    guide_rows = parse_survival_guide_lua(args.addon)
    zones = [row["zone"] for row in sorted(guide_rows, key=lambda row: row["index"])]
    unlocks = [row["unlock_bit"] for row in sorted(guide_rows, key=lambda row: row["index"])]
    contents = [row["content"] for row in sorted(guide_rows, key=lambda row: row["index"])]

    print(f"FFXI root: {args.root}")
    print(f"Survival Guide rows from addon: {len(guide_rows)}")
    if zones:
        print(f"First zones: {zones[:16]}")
        print(f"First unlock bits: {unlocks[:16]}")
        print(f"First contents: {contents[:16]}")

    compare_guide_tables(guide_rows, parse_superwarp_guides(args.superwarp_guides))

    print_xistring_summary(args.root, args.terms)
    for file_id in args.dat_id or []:
        print_dat_id_summary(args.root, file_id, args.terms + ["Bastok Markets [S]", "Eastern Adoulin"])

    if zones:
        zone16 = b"".join(struct.pack("<H", value) for value in zones[:16])
        zone32 = b"".join(struct.pack("<I", value) for value in zones[:16])
        unlock8 = bytes(value & 0xFF for value in unlocks[:16])
        content8 = bytes(value & 0xFF for value in contents[:24])
        search_exact_bytes(
            args.root,
            [
                ("first16-zones-u16", zone16),
                ("first16-zones-u32", zone32),
                ("first16-unlockbits-u8", unlock8),
                ("first24-content-u8", content8),
            ],
        )
        search_strided_zone_sequence(args.root, zones, args.min_match)


if __name__ == "__main__":
    main()

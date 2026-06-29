from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_TABLE_DIR = (
    Path(__file__).resolve().parent
    / "xi-tinkerer"
    / "src"
    / "crates"
    / "encoding"
    / "conversion_tables"
)


EMPTY_TABLE = bytes([0xFF]) * 512


def rotate_byte(byte: int, shift_size: int) -> int:
    if shift_size < 1 or shift_size > 8:
        return byte & 0xFF
    return ((byte >> shift_size) | ((byte << (8 - shift_size)) & 0xFF)) & 0xFF


def rotate_all(data: bytearray, shift_size: int) -> None:
    if shift_size < 1 or shift_size > 7:
        return
    for index, byte in enumerate(data):
        data[index] = rotate_byte(byte, shift_size)


def get_text_shift_size(data: bytes | bytearray) -> int:
    if len(data) < 2:
        return 0
    if data[0] == 0 and data[1] == 0:
        return 0

    bit_count = data[1].bit_count() - data[0].bit_count()
    match abs(bit_count) % 5:
        case 0:
            return 1
        case 1:
            return 7
        case 2:
            return 2
        case 3:
            return 6
        case 4:
            return 3
    return 0


def decode_text_block(data: bytearray) -> None:
    rotate_all(data, get_text_shift_size(data))


def encode_text_block(data: bytearray) -> None:
    rotate_all(data, 8 - get_text_shift_size(data))


class ConversionTables:
    def __init__(self, table_dir: Path = DEFAULT_TABLE_DIR) -> None:
        self.table_dir = table_dir
        self._tables: dict[int, bytes] = {}

    def get_table(self, table: int) -> bytes:
        table &= 0xFF
        if table not in self._tables:
            path = self.table_dir / f"{table:02X}xx.dat"
            self._tables[table] = path.read_bytes() if path.exists() else EMPTY_TABLE
        return self._tables[table]

    def lookup(self, table: int, index: int) -> int:
        lookup_index = (index & 0xFF) * 2
        raw = self.get_table(table)[lookup_index : lookup_index + 2]
        return int.from_bytes(raw, "little")


class FfxiStringDecoder:
    def __init__(self, table_dir: Path = DEFAULT_TABLE_DIR) -> None:
        self.tables = ConversionTables(table_dir)

    def decode_simple(self, data: bytes | bytearray) -> str:
        output: list[str] = []
        index = 0
        size = len(data)

        while index < size:
            byte = data[index]

            if byte == 0x00:
                break
            if byte in (0x07, 0x0A):
                output.append("\n")
                index += 1
                continue
            if byte == 0x02:
                index += 5
                continue
            if byte == 0xFD and index + 5 < size and data[index + 5] == 0xFD:
                index += 6
                continue
            if 0x00 < byte <= 0x19:
                index += 2 if index + 1 < size else 1
                continue

            value = self.tables.lookup(0x00, byte)
            if value == 0xFFFE:
                if index + 1 >= size:
                    break
                second = data[index + 1]
                value = self.tables.lookup(byte, second)
                index += 2
            else:
                index += 1

            if value == 0xFFFF:
                continue
            if value == 0:
                break
            try:
                output.append(chr(value))
            except ValueError:
                continue

        return "".join(output).strip()


@dataclass(frozen=True)
class TermHit:
    offset: int
    term: str
    text: str
    transform: str


@dataclass(frozen=True)
class RoeRecord:
    record_id: int
    title: str
    description: str
    goal: int | None
    sparks: int | None
    exp: int | None
    accolades: int | None
    title_offset: int
    description_offset: int


@dataclass(frozen=True)
class RoeRecordMeta:
    goal: int | None
    sparks: int | None
    exp: int | None
    accolades: int | None
    flags: tuple[str, ...]
    not_repeatable: bool


ROE_DAT_RELATIVE_PATH = Path("ROM") / "307" / "16.DAT"
ROE_ROTATE_SHIFT = 5
ROE_RECORD_START = 0x0C00
ROE_RECORD_SIZE = 0x0C00
ROE_GOAL_OFFSET = 0x0C
ROE_SPARKS_OFFSET = 0x10
ROE_EXP_OFFSET = 0x14
ROE_ACCOLADES_OFFSET = 0x1C
ROE_REPEATABLE_FLAGS = frozenset(("repeat", "daily", "weekly", "timed", "unity"))
DEFAULT_LSB_ROE_RECORDS = (
    Path(r"C:\Users\buu42\AccessXI\third_party\LandSandBoat-server")
    / "scripts"
    / "globals"
    / "roe_records.lua"
)


def _candidate_end(data: bytes, offset: int, max_bytes: int) -> int:
    limit = min(len(data), offset + max_bytes)
    end = offset
    while end < limit and data[end] != 0:
        end += 1
    return end + 1 if end < limit else limit


def _looks_like_text(text: str) -> bool:
    if not text:
        return False
    printable = sum(1 for char in text if char == "\n" or char.isprintable())
    return printable == len(text)


def _looks_like_roe_text(text: str) -> bool:
    if not _looks_like_text(text):
        return False
    useful = sum(1 for char in text if char == "\n" or char in "[]().,+-/':;!? \"%" or char.isalnum())
    return useful >= max(3, int(len(text) * 0.85))


def _extract_block_strings(data: bytes, base: int, size: int, decoder: FfxiStringDecoder) -> list[tuple[int, str]]:
    rows: list[tuple[int, str]] = []
    end = min(len(data), base + size)
    pos = base
    while pos < end:
        byte = data[pos]
        previous = data[pos - 1] if pos > base else 0
        if byte != 0 and previous == 0:
            stop = pos
            while stop < end and data[stop] != 0:
                stop += 1
            text = decoder.decode_simple(data[pos : min(stop + 1, end)])
            if text and any(char.isalpha() for char in text) and _looks_like_roe_text(text):
                rows.append((pos - base, text))
            pos = stop
        pos += 1
    return rows


def _record_u32(block: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(block):
        return 0
    return int.from_bytes(block[offset : offset + 4], "little")


def _record_meta_value(block: bytes, offset: int) -> int | None:
    value = _record_u32(block, offset)
    if value <= 0 or value > 100000:
        return None
    return value


def extract_roe_records(dat_path: Path) -> dict[int, RoeRecord]:
    data = bytearray(dat_path.read_bytes())
    rotate_all(data, ROE_ROTATE_SHIFT)
    decoded = bytes(data)
    ffxi = FfxiStringDecoder()
    records: dict[int, RoeRecord] = {}

    max_record = (len(decoded) - ROE_RECORD_START) // ROE_RECORD_SIZE
    for index in range(max_record):
        record_id = index + 1
        base = ROE_RECORD_START + (index * ROE_RECORD_SIZE)
        block = decoded[base : base + ROE_RECORD_SIZE]
        strings = _extract_block_strings(decoded, base, ROE_RECORD_SIZE, ffxi)
        if not strings:
            continue

        title_offset = -1
        title = ""
        for offset, text in strings:
            if 0x40 <= offset <= 0xC0 and "\n" not in text and not text.startswith("["):
                title_offset = offset
                title = text
                break
        if title == "":
            continue

        description_offset = -1
        description = ""
        for offset, text in strings:
            if offset <= title_offset:
                continue
            if text == title:
                continue
            if len(text) > len(description):
                description_offset = offset
                description = text

        records[record_id] = RoeRecord(
            record_id=record_id,
            title=title,
            description=description,
            goal=_record_meta_value(block, ROE_GOAL_OFFSET),
            sparks=_record_meta_value(block, ROE_SPARKS_OFFSET),
            exp=_record_meta_value(block, ROE_EXP_OFFSET),
            accolades=_record_meta_value(block, ROE_ACCOLADES_OFFSET),
            title_offset=title_offset,
            description_offset=description_offset,
        )

    return records


def extract_lsb_roe_meta(roe_records_path: Path) -> dict[int, RoeRecordMeta]:
    text = roe_records_path.read_text(encoding="utf-8", errors="replace")
    starts = list(re.finditer(r"(?m)^\s*\[(\d+)\]\s*=\s*\{", text))
    metadata: dict[int, RoeRecordMeta] = {}

    for index, match in enumerate(starts):
        record_id = int(match.group(1))
        end = starts[index + 1].start() if index + 1 < len(starts) else text.find("\n};", match.end())
        if end < 0:
            end = len(text)
        block = text[match.end() : end]

        goal_match = re.search(r"\bgoal\s*=\s*(\d+)", block)
        reward_pos = block.find("reward")
        reward = block[reward_pos:] if reward_pos >= 0 else ""

        def reward_int(name: str) -> int | None:
            value_match = re.search(rf"\b{name}\s*=\s*(\d+)", reward)
            return int(value_match.group(1)) if value_match else None

        goal = int(goal_match.group(1)) if goal_match else None
        sparks = reward_int("sparks")
        exp = reward_int("exp")
        accolades = reward_int("accolades")
        flags_match = re.search(r"\bflags\s*=\s*set\s*\{([^}]*)\}", block)
        flags = tuple(
            re.findall(r"['\"]([A-Za-z0-9_ -]+)['\"]", flags_match.group(1))
            if flags_match
            else ()
        )
        not_repeatable = not any(flag in ROE_REPEATABLE_FLAGS for flag in flags)
        metadata[record_id] = RoeRecordMeta(
            goal=goal,
            sparks=sparks,
            exp=exp,
            accolades=accolades,
            flags=flags,
            not_repeatable=not_repeatable,
        )

    return metadata


def scan_exact_terms(
    data: bytes,
    terms: Iterable[str],
    *,
    max_bytes: int = 512,
    decoder: FfxiStringDecoder | None = None,
    transform: str = "raw",
) -> Iterable[TermHit]:
    ffxi = decoder or FfxiStringDecoder()
    wanted = tuple(term for term in terms if term)
    seen: set[tuple[int, str, str]] = set()
    ascii_terms = [(term, term.encode("ascii")) for term in wanted if term.isascii()]

    if ascii_terms:
        candidate_starts: set[int] = set()
        for _term, raw in ascii_terms:
            position = data.find(raw)
            while position >= 0:
                start = data.rfind(b"\x00", max(0, position - max_bytes), position) + 1
                candidate_starts.add(start)
                position = data.find(raw, position + 1)

        for offset in sorted(candidate_starts):
            end = _candidate_end(data, offset, max_bytes)
            text = ffxi.decode_simple(data[offset:end])
            if not _looks_like_text(text):
                continue
            for term in wanted:
                if term in text:
                    key = (offset, term, text)
                    if key not in seen:
                        seen.add(key)
                        yield TermHit(offset=offset, term=term, text=text, transform=transform)
        return

    for offset, byte in enumerate(data):
        if byte == 0:
            continue
        end = _candidate_end(data, offset, max_bytes)
        if end <= offset:
            continue
        text = ffxi.decode_simple(data[offset:end])
        if not _looks_like_text(text):
            continue
        for term in wanted:
            if term in text:
                key = (offset, term, text)
                if key not in seen:
                    seen.add(key)
                    yield TermHit(offset=offset, term=term, text=text, transform=transform)


def scan_file_exact_terms(path: Path, terms: Iterable[str]) -> list[TermHit]:
    data = path.read_bytes()
    hits = list(scan_exact_terms(data, terms))

    for shift in range(1, 8):
        rotated = bytearray(data)
        rotate_all(rotated, shift)
        hits.extend(
            scan_exact_terms(
                bytes(rotated),
                terms,
                transform=f"rotate-right-{shift}",
            )
        )

    decoded_text = bytearray(data)
    decode_text_block(decoded_text)
    hits.extend(scan_exact_terms(bytes(decoded_text), terms, transform="text-block"))
    return hits


def dat_files(root: Path) -> list[Path]:
    if root.is_file():
        return [root]
    files: list[Path] = []
    for name in ("ROM", "ROM2", "ROM3", "ROM4", "ROM5", "ROM6", "ROM7", "ROM8", "ROM9"):
        base = root / name
        if base.exists():
            files.extend(sorted(base.rglob("*.DAT")))
    return files


def scan_root_fast(root: Path, terms: Iterable[str]) -> list[tuple[Path, TermHit]]:
    wanted = tuple(term for term in terms if term)
    raw_terms = [term.encode("ascii") for term in wanted if term.isascii()]
    rotated_terms = {
        shift: [bytes(rotate_byte(byte, 8 - shift) for byte in term) for term in raw_terms]
        for shift in range(1, 8)
    }
    matches: list[tuple[Path, TermHit]] = []

    for path in dat_files(root):
        data = path.read_bytes()
        variants: list[tuple[str, bytes]] = []

        for term in raw_terms:
            if term in data:
                variants.append(("raw", data))
                break

        for shift, encoded_terms in rotated_terms.items():
            if any(term in data for term in encoded_terms):
                rotated = bytearray(data)
                rotate_all(rotated, shift)
                variants.append((f"rotate-right-{shift}", bytes(rotated)))

        if not variants:
            continue

        for label, blob in variants:
            for hit in scan_exact_terms(blob, wanted, transform=label):
                matches.append((path, hit))

    return matches


def lua_quote(text: str) -> str:
    return "'" + text.replace("\\", "\\\\").replace("'", "\\'").replace("\r", "").replace("\n", "\\n") + "'"


def roe_static_category_lua() -> list[str]:
    return [
        "-- RoE objective list category metadata is only used for context;",
        "-- character-dependent submenu rows must come from native text.",
        "data.objective_list_categories = T{",
        "    [1] = { label = 'Tutorial', source = 'roe-category-index:objective-list', category_key = 'tutorial' },",
        "    [2] = { label = 'Combat (Wide Area)', source = 'roe-category-index:objective-list', category_key = 'combat_wide_area' },",
        "    [3] = { label = 'Combat (Region)', source = 'roe-category-index:objective-list', category_key = 'combat_region' },",
        "    [4] = { label = 'Fishing', source = 'dat:ROM/165/77.DAT#270', category_key = 'fishing' },",
        "    [5] = { label = 'Crafting', source = 'roe-category-index:objective-list', category_key = 'crafting' },",
        "    [6] = { label = 'Harvesting', source = 'roe-category-index:objective-list', category_key = 'harvesting' },",
        "    [7] = { label = 'Content', source = 'roe-category-index:objective-list', category_key = 'content' },",
        "    [8] = { label = 'Achievements', source = 'roe-category-index:objective-list', category_key = 'achievements' },",
        "    [9] = { label = 'Unity', source = 'dat:ROM/165/77.DAT#442', category_key = 'unity' },",
        "    [10] = { label = 'Vana\\'versary', source = 'roe-category-index:objective-list', category_key = 'vanaversary' },",
        "    [11] = { label = 'Other', source = 'roe-category-index:objective-list', category_key = 'other', optional = true },",
        "    [12] = { label = 'Limited-time Challenges', source = 'roe-category-index:objective-list', category_key = 'limited_time_challenges', optional = true },",
        "};",
        "data.objective_list_optional_category_indices = T{ 11, 12 };",
        "",
    ]


def write_roe_lua_module(dat_path: Path, out_path: Path, lsb_roe_records_path: Path | None = None) -> int:
    records = extract_roe_records(dat_path)
    lsb_metadata = extract_lsb_roe_meta(lsb_roe_records_path) if lsb_roe_records_path is not None and lsb_roe_records_path.exists() else {}

    lines = [
        "local data = {};",
        "",
        "-- Generated from the installed FFXI DAT, not from screenshots or wiki fallback text.",
        "-- Source: {}, transform=rotate-right-{}, recordStart=0x{:X}, recordSize=0x{:X}".format(
            str(ROE_DAT_RELATIVE_PATH).replace("\\", "/"),
            ROE_ROTATE_SHIFT,
            ROE_RECORD_START,
            ROE_RECORD_SIZE,
        ),
        "",
        "data.records = T{",
    ]
    for record_id in sorted(records):
        record = records[record_id]
        fields = [
            f"label = {lua_quote(record.title)}",
            "source = 'dat:ROM/307/16.DAT rotate-right-5'",
        ]
        if record.description:
            fields.append(f"description = {lua_quote(record.description)}")
            if record.description.startswith("[Limited-time Challenge]"):
                fields.append("timed = true")
            elif record.description.startswith("Daily Objective:"):
                fields.append("daily = true")
        if record.goal is not None:
            fields.append(f"goal = {record.goal}")
        reward_fields: list[str] = []
        if record.sparks is not None:
            reward_fields.append(f"sparks = {record.sparks}")
        if record.exp is not None:
            reward_fields.append(f"exp = {record.exp}")
        if record.accolades is not None:
            reward_fields.append(f"accolades = {record.accolades}")
        if reward_fields:
            fields.append("rewards = { " + ", ".join(reward_fields) + " }")
            fields.append("reward_source = 'dat:ROM/307/16.DAT fixed-fields'")
        lsb_meta = lsb_metadata.get(record_id)
        if lsb_meta is not None and lsb_meta.not_repeatable:
            fields.append("not_repeatable = true")
            fields.append("repeat_source = 'lsb:scripts/globals/roe_records.lua flags'")
        fields.append(f"title_offset = 0x{record.title_offset:X}")
        if record.description_offset >= 0:
            fields.append(f"description_offset = 0x{record.description_offset:X}")
        lines.append(f"    [{record_id}] = {{ {', '.join(fields)} }},")
    lines.extend([
        "};",
        "",
        *roe_static_category_lua(),
        "return data;",
        "",
    ])
    out_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return len(records)


def main() -> int:
    parser = argparse.ArgumentParser(description="Search FFXI DAT bytes with Xi-Tinkerer string decoding.")
    parser.add_argument("dat", type=Path, help="DAT file or FFXI root to scan")
    parser.add_argument("terms", nargs="*", help="Exact decoded terms to find")
    parser.add_argument("--root", action="store_true", help="Scan all ROM DAT files under an FFXI root")
    parser.add_argument("--generate-roe-lua", type=Path, help="Write a DAT-backed records_of_eminence.lua module")
    parser.add_argument(
        "--lsb-roe-records",
        type=Path,
        default=DEFAULT_LSB_ROE_RECORDS if DEFAULT_LSB_ROE_RECORDS.exists() else None,
        help="Optional LandSandBoat scripts/globals/roe_records.lua metadata source for goals and rewards",
    )
    args = parser.parse_args()

    if args.generate_roe_lua is not None:
        count = write_roe_lua_module(args.dat, args.generate_roe_lua, args.lsb_roe_records)
        print(f"wrote={args.generate_roe_lua} records={count}")
        return 0

    if not args.terms:
        parser.error("terms are required unless --generate-roe-lua is used")

    if args.root:
        root_hits = scan_root_fast(args.dat, args.terms)
        for path, hit in root_hits:
            print(f"{path}\t{hit.transform}\t0x{hit.offset:08X}\t{hit.term}\t{hit.text}")
        print(f"hits={len(root_hits)}")
        return 0

    hits = scan_file_exact_terms(args.dat, args.terms)
    for hit in hits:
        print(f"{args.dat}\t{hit.transform}\t0x{hit.offset:08X}\t{hit.term}\t{hit.text}")
    print(f"hits={len(hits)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

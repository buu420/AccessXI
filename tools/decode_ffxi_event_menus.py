from __future__ import annotations

import argparse
import re
import struct
from pathlib import Path


DEFAULT_ROOT = Path(r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI")
DEFAULT_XIEVENTS = Path(r"C:\Users\buu42\AccessXI\external\XiEvents\Event DAT Files.md")


def decode_event_string_bytes(data: bytes) -> bytes:
    """Decode the simple high-bit text transform used by zone string DATs."""
    return bytes((b ^ 0x80) if b >= 0x80 else b for b in data)


def clean_piece(text: str) -> str:
    text = text.replace("\x00", " ")
    text = re.sub(r"\x7f1", " ", text)
    text = re.sub(r"[\x01-\x06\x08-\x0a\x0b\x0c\x0e-\x1f]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"^\d+(?=[A-Z])", "", text)
    text = re.sub(r"\s+\d+$", "", text)
    text = text.strip(". ")
    if re.fullmatch(r"\d+", text or ""):
        return ""
    return text + "." if text and not text.endswith((".", "?", "!")) else text


def parse_zone_table(path: Path) -> dict[int, dict[str, str]]:
    rows: dict[int, dict[str, str]] = {}
    if not path.exists():
        return rows
    line_re = re.compile(
        r"^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|"
    )
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = line_re.match(line)
        if not match:
            continue
        zone = int(match.group(1))
        rows[zone] = {
            "name": match.group(2).strip(),
            "entities": match.group(3).strip(),
            "events": match.group(4).strip(),
            "strings_jp": match.group(5).strip(),
            "strings_na": match.group(6).strip(),
        }
    return rows


def resolve(root: Path, rel: str) -> Path:
    return root / Path(rel.replace("/", "\\"))


def parse_event_dat(path: Path) -> list[dict]:
    data = path.read_bytes()
    if len(data) < 8:
        return []
    block_count = struct.unpack_from("<I", data, 0)[0]
    if block_count <= 0 or block_count > 10000:
        return []
    sizes_off = 4
    blocks_off = sizes_off + (block_count * 4)
    if blocks_off > len(data):
        return []
    sizes = list(struct.unpack_from("<" + ("I" * block_count), data, sizes_off))
    blocks = []
    pos = blocks_off
    for block_index, size in enumerate(sizes):
        start = pos
        end = min(pos + size, len(data))
        pos += size
        if end - start < 16:
            continue
        actor, event_count = struct.unpack_from("<II", data, start)
        cursor = start + 8
        if event_count <= 0 or event_count > 1024 or cursor + (event_count * 4) > end:
            continue
        offsets = list(struct.unpack_from("<" + ("H" * event_count), data, cursor))
        cursor += event_count * 2
        event_ids = list(struct.unpack_from("<" + ("H" * event_count), data, cursor))
        cursor += event_count * 2
        if cursor + 4 > end:
            continue
        ref_count = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        if ref_count > 100000 or cursor + (ref_count * 4) + 4 > end:
            continue
        refs = list(struct.unpack_from("<" + ("I" * ref_count), data, cursor))
        cursor += ref_count * 4
        event_size = struct.unpack_from("<I", data, cursor)[0]
        cursor += 4
        event_data = data[cursor : min(cursor + event_size, end)]
        blocks.append(
            {
                "index": block_index,
                "actor": actor,
                "event_ids": event_ids,
                "offsets": offsets,
                "refs": refs,
                "event_data": event_data,
            }
        )
    return blocks


def load_string_dat(path: Path) -> tuple[bytes, list[int]]:
    decoded = decode_event_string_bytes(path.read_bytes())
    count = len(decoded) // 4
    offsets: list[int] = []
    for index in range(count):
        value = struct.unpack_from("<I", decoded, index * 4)[0]
        if 0 <= value < len(decoded):
            offsets.append(value)
    return decoded, sorted(set(offsets))


def message_bytes(decoded: bytes, message_id: int, span: int = 1600) -> bytes:
    table_off = message_id * 4
    if table_off + 4 > len(decoded):
        return b""
    start = struct.unpack_from("<I", decoded, table_off)[0]
    if start <= 0 or start >= len(decoded):
        return b""
    # Event string table entries can point into the middle of a larger dialog
    # run. Query menus may follow several message separators after the pointer,
    # so read a bounded window rather than stopping at the next table offset.
    return decoded[start : min(start + span, len(decoded))]


def split_message_chunks(raw: bytes) -> list[str]:
    chunks: list[str] = []
    # 0x7f "1" NUL is the common message/page terminator in these event
    # strings. Keeping chunks separate avoids mixing several later queries into
    # one candidate.
    for chunk in raw.split(b"\x7f1\x00"):
        text = chunk.decode("cp1252", errors="replace")
        if "\x0b" not in text and "\x07" not in text:
            continue
        pieces = query_pieces(text)
        if len(pieces) >= 2:
            chunks.append(text)
    return chunks


def query_pieces(text: str) -> list[str]:
    pieces: list[str] = []
    for part in text.split("\x07"):
        piece = clean_piece(part)
        if piece and piece not in pieces:
            pieces.append(piece)
    return pieces


def ref_value(refs: list[int], encoded: int) -> int | None:
    if encoded & 0x8000:
        index = encoded & 0x7FFF
        return refs[index] if index < len(refs) else None
    return encoded


def query_candidates(block: dict, event_id: int, decoded_strings: bytes, string_offsets: list[int]) -> list[dict]:
    event_ids = block["event_ids"]
    offsets = block["offsets"]
    if event_id not in event_ids:
        return []
    idx = event_ids.index(event_id)
    start = offsets[idx]
    end = offsets[idx + 1] if idx + 1 < len(offsets) else len(block["event_data"])
    code = block["event_data"][start:end]
    refs = block["refs"]
    out = []
    for pos, opcode in enumerate(code):
        if opcode != 0x24 or pos + 7 > len(code):
            continue
        msg_arg, default_arg, flags_arg = struct.unpack_from("<HHH", code, pos + 1)
        if (msg_arg & 0x8000) == 0:
            continue
        msg_id = ref_value(refs, msg_arg)
        if msg_id is None:
            continue
        raw = message_bytes(decoded_strings, msg_id)
        chunks = split_message_chunks(raw)
        if not chunks:
            continue
        chunk_pieces = [query_pieces(chunk) for chunk in chunks]
        out.append(
            {
                "offset": start + pos,
                "message_id": msg_id,
                "default": ref_value(refs, default_arg),
                "flags": ref_value(refs, flags_arg),
                "chunks": chunk_pieces,
            }
        )
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Decode FFXI event query menu messages from native DATs.")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    parser.add_argument("--xievents", type=Path, default=DEFAULT_XIEVENTS)
    parser.add_argument("--zone", type=int, required=True)
    parser.add_argument("--actor", type=lambda s: int(s, 0), default=None)
    parser.add_argument("--event", type=lambda s: int(s, 0), action="append", default=[])
    parser.add_argument("--all-chunks", action="store_true", help="Print later query chunks found in the bounded message span.")
    args = parser.parse_args()

    zones = parse_zone_table(args.xievents)
    if args.zone not in zones:
        raise SystemExit(f"zone {args.zone} not found in {args.xievents}")
    zone = zones[args.zone]
    events_path = resolve(args.root, zone["events"])
    strings_path = resolve(args.root, zone["strings_na"])
    blocks = parse_event_dat(events_path)
    decoded_strings, string_offsets = load_string_dat(strings_path)

    print(f"Zone {args.zone}: {zone['name']}")
    print(f"Events: {events_path}")
    print(f"Strings NA: {strings_path}")
    print(f"Event blocks: {len(blocks)}")

    selected = blocks
    if args.actor is not None:
        selected = [block for block in blocks if block["actor"] == args.actor]
    for block in selected:
        print(f"\nBlock {block['index']} actor=0x{block['actor']:08X} events=" + ", ".join(f"0x{x:04X}" for x in block["event_ids"]))
        event_ids = args.event or block["event_ids"]
        for event_id in event_ids:
            candidates = query_candidates(block, event_id, decoded_strings, string_offsets)
            if not candidates:
                continue
            print(f"  Event 0x{event_id:04X}: query candidates={len(candidates)}")
            for candidate in candidates:
                print(
                    f"    +0x{candidate['offset']:04X} message={candidate['message_id']} "
                    f"default={candidate['default']} flags={candidate['flags']}"
                )
                chunks = candidate["chunks"][:8] if args.all_chunks else candidate["chunks"][:1]
                for chunk_index, pieces in enumerate(chunks, start=1):
                    label = f"chunk {chunk_index}" if args.all_chunks else "query"
                    print(f"      {label}:")
                    for index, piece in enumerate(pieces[:16], start=1):
                        print(f"        {index}. {piece}")


if __name__ == "__main__":
    main()

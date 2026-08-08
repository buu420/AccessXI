from __future__ import annotations

import re
import struct
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from .model import ManifestError, NativeObjective


MISSION_LAYOUT_BASE_OFFSET = 0x18
MISSION_LAYOUT_STRIDE_OFFSET = 0x20
MISSION_LAYOUT_COUNT_OFFSET = 0x28
MISSION_ID_OFFSET = 0x1C
MISSION_TEXT_OFFSET = 0x3C

QUEST_STRIDE = 0x280
QUEST_ID_OFFSET = 0x5C
QUEST_TITLE_OFFSET = 0x7C


MISSION_DAT_TABLES: dict[str, str] = {
    "San d'Oria": "ROM/176/67.DAT",
    "Bastok": "ROM/176/68.DAT",
    "Windurst": "ROM/176/69.DAT",
    "Rise of the Zilart": "ROM/176/70.DAT",
    "Chains of Promathia": "ROM/176/71.DAT",
    "Assault": "ROM/176/72.DAT",
    "Treasures of Aht Urhgan": "ROM/176/73.DAT",
    "Campaign": "ROM/196/6.DAT",
    "Wings of the Goddess": "ROM/196/7.DAT",
    "Seekers of Adoulin": "ROM/293/69.DAT",
    "Rhapsodies of Vana'diel": "ROM/333/4.DAT",
    "The Voracious Resurgence": "ROM/364/36.DAT",
    "A Crystalline Prophecy": "ROM/222/18.DAT",
    "A Moogle Kupo d'Etat": "ROM/223/12.DAT",
    "A Shantotto Ascension": "ROM/223/13.DAT",
}


@dataclass(frozen=True, slots=True)
class QuestDatSection:
    relative_path: str
    start_slot: int = 0
    end_slot: int | None = None
    progress_id_offset: int = 0


@dataclass(frozen=True, slots=True)
class QuestDatSource:
    label: str
    sections: tuple[QuestDatSection, ...]


def _quest_source(label: str, relative_path: str) -> QuestDatSource:
    return QuestDatSource(label, (QuestDatSection(relative_path),))


QUEST_DAT_TABLES: dict[str, QuestDatSource] = {
    "sandoria": _quest_source("San d'Oria", "ROM/176/60.DAT"),
    "bastok": _quest_source("Bastok", "ROM/176/61.DAT"),
    "windurst": _quest_source("Windurst", "ROM/176/62.DAT"),
    "jeuno": _quest_source("Jeuno", "ROM/176/63.DAT"),
    "other_areas": QuestDatSource(
        "Other Areas",
        (QuestDatSection("ROM/176/64.DAT", start_slot=0, end_slot=111),),
    ),
    "outlands": _quest_source("Outlands", "ROM/176/65.DAT"),
    "aht_urhgan": _quest_source("Aht Urhgan", "ROM/176/66.DAT"),
    "crystal_war": _quest_source("Crystal War", "ROM/196/6.DAT"),
    "abyssea": _quest_source("Abyssea", "ROM/242/64.DAT"),
    "adoulin": QuestDatSource(
        "Adoulin",
        (
            QuestDatSection("ROM/293/70.DAT"),
            # Mog Garden objectives are displayed from the tail of the Other
            # Areas DAT but are tracked in the Adoulin 0x056 packet.  The first
            # supplemental block's embedded IDs are 24 below their packet bits.
            QuestDatSection(
                "ROM/176/64.DAT",
                start_slot=111,
                end_slot=121,
                progress_id_offset=24,
            ),
            QuestDatSection("ROM/176/64.DAT", start_slot=121, end_slot=131),
        ),
    ),
    "coalition": _quest_source("Coalition", "ROM/293/71.DAT"),
}


def _read_u32(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise ManifestError(f"Native DAT is truncated at offset 0x{offset:X}.")
    return struct.unpack_from("<I", data, offset)[0]


def _read_inverted_u32(data: bytes, offset: int) -> int:
    if offset < 0 or offset + 4 > len(data):
        raise ManifestError(f"Native DAT is truncated at inverted offset 0x{offset:X}.")
    decoded = bytes(255 - byte for byte in data[offset : offset + 4])
    return struct.unpack("<I", decoded)[0]


def _clean_native_text(value: str) -> str:
    value = value.replace("\r", " ").replace("\n", " ").replace("\t", " ")
    value = re.sub(r"\s+", " ", value).strip()
    return value.lstrip("_")


def _decode_inverted_text(data: bytes, offset: int, maximum: int) -> str:
    if offset < 0 or maximum <= 0 or offset >= len(data):
        return ""
    decoded = bytearray()
    for raw in data[offset : min(len(data), offset + maximum)]:
        value = 255 - raw
        if value == 0:
            break
        if value >= 0x20:
            decoded.append(value)
    return _clean_native_text(decoded.decode("latin-1", errors="replace"))


def _decode_inverted_runs(data: bytes, offset: int, maximum: int) -> tuple[str, ...]:
    if offset < 0 or maximum <= 0 or offset >= len(data):
        return ()
    runs: list[str] = []
    current = bytearray()

    def flush() -> None:
        if not current:
            return
        text = _clean_native_text(current.decode("latin-1", errors="replace"))
        current.clear()
        if text and len(text) <= 240 and any(character.isalnum() for character in text):
            runs.append(text)

    for raw in data[offset : min(len(data), offset + maximum)]:
        value = 255 - raw
        if value == 0 or value < 0x20:
            flush()
        else:
            current.append(value)
    flush()
    return tuple(runs)


def _placeholder_title(title: str) -> bool:
    if not title:
        return True
    if any(ord(character) < 0x20 or ord(character) > 0x7E for character in title):
        return True
    return title.startswith(("AS~", "ATV", "ZL"))


def _mission_details(runs: tuple[str, ...], title: str) -> tuple[str, ...]:
    body: list[str] = []
    collecting = False
    seen_title = False
    for run in runs:
        if not seen_title and run.casefold() == title.casefold():
            seen_title = True
            continue
        lower = run.casefold()
        if lower == "mission orders" or lower == "mission orders:":
            collecting = True
            continue
        if lower.startswith("mission orders:"):
            collecting = True
            inline = run.split(":", 1)[1].strip()
            if inline:
                body.append(inline)
            continue
        if collecting or seen_title:
            body.append(run)
    return tuple(body)


def decode_mission_dat_bytes(
    data: bytes,
    context: str,
    source_dat: str,
) -> tuple[NativeObjective, ...]:
    if len(data) < 5 or data[:5] != b"d_msg":
        raise ManifestError(f"Mission DAT {source_dat} does not have d_msg magic.")

    base = _read_u32(data, MISSION_LAYOUT_BASE_OFFSET)
    stride = _read_u32(data, MISSION_LAYOUT_STRIDE_OFFSET)
    count = _read_u32(data, MISSION_LAYOUT_COUNT_OFFSET)
    if stride <= MISSION_TEXT_OFFSET or base <= 0 or count <= 0:
        raise ManifestError(
            f"Mission DAT {source_dat} has invalid layout base=0x{base:X} stride={stride} count={count}."
        )
    if base + (stride * count) > len(data):
        raise ManifestError(f"Mission DAT {source_dat} layout extends past the file.")

    rows: list[NativeObjective] = []
    for ordinal in range(count):
        record = base + (ordinal * stride)
        title = _decode_inverted_text(data, record + MISSION_TEXT_OFFSET, stride - MISSION_TEXT_OFFSET)
        if _placeholder_title(title):
            continue
        mission_id = _read_inverted_u32(data, record + MISSION_ID_OFFSET)
        runs = _decode_inverted_runs(data, record + MISSION_TEXT_OFFSET, stride - MISSION_TEXT_OFFSET)
        rows.append(
            NativeObjective(
                kind="mission",
                context=context,
                native_id=ordinal + 1,
                title=title,
                source_dat=source_dat,
                record_offset=record,
                progress_id=mission_id,
                details=_mission_details(runs, title),
            )
        )

    return validate_unique_objectives(rows)


def _valid_quest_title(title: str) -> bool:
    if len(title) < 3 or title.startswith(" ") or _placeholder_title(title):
        return False
    lower = title.casefold()
    if lower.startswith(("client:", "clients:", "summary:")):
        return False
    if re.fullmatch(r"(?:san d'oria|bastok|windurst|jeuno|other areas|outlands|aht urhgan|crystal war) quest #\d+", lower):
        return False
    return re.fullmatch(r"g\d+", lower) is None


def decode_quest_dat_bytes(
    data: bytes,
    area_key: str,
    area_label: str,
    source_dat: str,
    *,
    start_slot: int = 0,
    end_slot: int | None = None,
    progress_id_offset: int = 0,
) -> tuple[NativeObjective, ...]:
    del area_label
    rows: list[NativeObjective] = []
    seen_ids: set[int] = set()
    slot_count = len(data) // QUEST_STRIDE
    start_slot = max(0, int(start_slot))
    if end_slot is None:
        end_slot = slot_count
    end_slot = min(slot_count, max(start_slot, int(end_slot)))
    for slot in range(start_slot, end_slot):
        record = slot * QUEST_STRIDE
        title = _decode_inverted_text(
            data,
            record + QUEST_TITLE_OFFSET,
            min(96, QUEST_STRIDE - QUEST_TITLE_OFFSET),
        )
        if not _valid_quest_title(title):
            continue
        title = title.lstrip("+")
        quest_id = (255 - data[record + QUEST_ID_OFFSET]) + int(progress_id_offset)
        if quest_id < 0 or quest_id > 255:
            raise ManifestError(
                f"Quest DAT {source_dat} maps slot {slot} outside the 0..255 packet range."
            )
        if quest_id in seen_ids:
            raise ManifestError(
                f"Quest DAT {source_dat} repeats quest ID {quest_id} in {area_key}."
            )
        seen_ids.add(quest_id)
        runs = _decode_inverted_runs(
            data,
            record + QUEST_TITLE_OFFSET,
            QUEST_STRIDE - QUEST_TITLE_OFFSET,
        )
        details = tuple(run for run in runs if run.casefold() != title.casefold())
        rows.append(
            NativeObjective(
                kind="quest",
                context=area_key,
                native_id=quest_id,
                title=title,
                source_dat=source_dat,
                record_offset=record,
                progress_id=quest_id,
                details=details,
            )
        )

    return validate_unique_objectives(rows)


def validate_unique_objectives(
    objectives: Iterable[NativeObjective],
) -> tuple[NativeObjective, ...]:
    result: list[NativeObjective] = []
    seen: set[str] = set()
    for objective in objectives:
        if objective.key in seen:
            raise ManifestError(f"Native objective key is duplicated: {objective.key}")
        seen.add(objective.key)
        result.append(objective)
    return tuple(result)


def _native_path(root: Path, relative_path: str) -> Path:
    return root.joinpath(*PurePosixPath(relative_path).parts)


def build_native_manifest(
    ffxi_root: Path,
    *,
    mission_tables: dict[str, str] | None = None,
    quest_tables: dict[str, QuestDatSource] | None = None,
) -> tuple[NativeObjective, ...]:
    root = Path(ffxi_root)
    missions = MISSION_DAT_TABLES if mission_tables is None else mission_tables
    quests = QUEST_DAT_TABLES if quest_tables is None else quest_tables
    objectives: list[NativeObjective] = []

    for context, relative_path in missions.items():
        path = _native_path(root, relative_path)
        if not path.is_file():
            raise ManifestError(f"Required mission DAT is missing: {path}")
        objectives.extend(decode_mission_dat_bytes(path.read_bytes(), context, relative_path))

    for area_key, source in quests.items():
        area_objectives: list[NativeObjective] = []
        for section in source.sections:
            path = _native_path(root, section.relative_path)
            if not path.is_file():
                raise ManifestError(f"Required quest DAT is missing: {path}")
            area_objectives.extend(
                decode_quest_dat_bytes(
                    path.read_bytes(),
                    area_key,
                    source.label,
                    section.relative_path,
                    start_slot=section.start_slot,
                    end_slot=section.end_slot,
                    progress_id_offset=section.progress_id_offset,
                )
            )
        objectives.extend(validate_unique_objectives(area_objectives))

    return validate_unique_objectives(objectives)

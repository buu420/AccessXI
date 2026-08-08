from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from tools.objective_guides.model import ManifestError, NativeObjective
from tools.objective_guides.native_manifest import (
    MISSION_DAT_TABLES,
    QUEST_DAT_TABLES,
    QuestDatSection,
    QuestDatSource,
    build_native_manifest,
    decode_mission_dat_bytes,
    decode_quest_dat_bytes,
    validate_unique_objectives,
)


def _write_u32(buffer: bytearray, offset: int, value: int) -> None:
    buffer[offset : offset + 4] = struct.pack("<I", value)


def _write_inverted_u32(buffer: bytearray, offset: int, value: int) -> None:
    encoded = bytes(255 - byte for byte in struct.pack("<I", value))
    buffer[offset : offset + 4] = encoded


def _write_inverted_text(buffer: bytearray, offset: int, text: str) -> None:
    encoded = text.encode("latin-1")
    buffer[offset : offset + len(encoded)] = bytes(255 - byte for byte in encoded)
    buffer[offset + len(encoded)] = 255


def _mission_dat(rows: list[tuple[int, str, str]]) -> bytes:
    base = 0x40
    stride = 0x180
    buffer = bytearray(base + (stride * len(rows)))
    buffer[:5] = b"d_msg"
    _write_u32(buffer, 0x18, base)
    _write_u32(buffer, 0x20, stride)
    _write_u32(buffer, 0x28, len(rows))
    for ordinal, (mission_id, title, orders) in enumerate(rows):
        record = base + (ordinal * stride)
        _write_inverted_u32(buffer, record + 0x1C, mission_id)
        _write_inverted_text(buffer, record + 0x3C, title)
        if orders:
            orders_offset = record + 0x3C + len(title) + 1
            _write_inverted_text(buffer, orders_offset, "Mission Orders:")
            body_offset = orders_offset + len("Mission Orders:") + 1
            _write_inverted_text(buffer, body_offset, orders)
    return bytes(buffer)


def _quest_dat(rows: list[tuple[int, str, tuple[str, ...]]]) -> bytes:
    stride = 0x280
    buffer = bytearray(stride * len(rows))
    for slot, (quest_id, title, details) in enumerate(rows):
        record = slot * stride
        buffer[record + 0x5C] = 255 - quest_id
        _write_inverted_text(buffer, record + 0x7C, title)
        cursor = record + 0x7C + len(title) + 1
        for detail in details:
            _write_inverted_text(buffer, cursor, detail)
            cursor += len(detail) + 1
    return bytes(buffer)


class NativeManifestTests(unittest.TestCase):
    def test_mission_decoder_uses_native_layout_and_keeps_orders(self) -> None:
        data = _mission_dat(
            [
                (1, "A Geological Survey", "Assist Cid in studying Dangruf Wadi."),
                (2, "Fetichism", "Collect the requested fragments."),
            ]
        )

        rows = decode_mission_dat_bytes(data, "Bastok", "ROM/176/68.DAT")

        self.assertEqual([row.native_id for row in rows], [1, 2])
        self.assertEqual(rows[0].key, "mission:Bastok:1")
        self.assertEqual(rows[0].title, "A Geological Survey")
        self.assertEqual(rows[0].progress_id, 1)
        self.assertEqual(rows[0].source_dat, "ROM/176/68.DAT")
        self.assertEqual(rows[0].record_offset, 0x40)
        self.assertEqual(rows[0].details, ("Assist Cid in studying Dangruf Wadi.",))

    def test_mission_decoder_rejects_bad_magic(self) -> None:
        with self.assertRaises(ManifestError):
            decode_mission_dat_bytes(b"not-a-dmsg", "Bastok", "bad.DAT")

    def test_mission_native_keys_use_row_identity_when_progress_ids_repeat(self) -> None:
        duplicate = _mission_dat([(1, "First", ""), (1, "Second", "")])
        rows = decode_mission_dat_bytes(duplicate, "Seekers of Adoulin", "duplicate.DAT")

        self.assertEqual([row.key for row in rows], [
            "mission:Seekers of Adoulin:1",
            "mission:Seekers of Adoulin:2",
        ])
        self.assertEqual([row.progress_id for row in rows], [1, 1])

    def test_mission_decoder_rejects_non_english_placeholder_rows(self) -> None:
        data = _mission_dat(
            [
                (1, "A Geological Survey", "Assist Cid."),
                (2, "BS\x83placeholder", ""),
                (3, "Fetichism", "Collect the fragments."),
            ]
        )

        rows = decode_mission_dat_bytes(data, "Bastok", "ROM/176/68.DAT")

        self.assertEqual([row.native_id for row in rows], [1, 3])
        self.assertEqual([row.progress_id for row in rows], [1, 3])

    def test_quest_decoder_filters_native_nonobjective_rows(self) -> None:
        data = _quest_dat(
            [
                (2, "The Pickpocket", ("Client: Altiret", "Summary: Recover the item.")),
                (3, "Client: Not a quest", ()),
                (4, "Summary: Not a quest", ()),
                (5, "G12", ()),
                (6, "+A Timely Visit", ("Client: Eugballion",)),
                (7, "BS\x83placeholder", ()),
                (8, "Bastok Quest #99", ()),
            ]
        )

        rows = decode_quest_dat_bytes(data, "sandoria", "San d'Oria", "ROM/176/60.DAT")

        self.assertEqual([row.native_id for row in rows], [2, 6])
        self.assertEqual(rows[0].key, "quest:sandoria:2")
        self.assertEqual(rows[0].title, "The Pickpocket")
        self.assertEqual(rows[0].details, ("Client: Altiret", "Summary: Recover the item."))
        self.assertEqual(rows[1].title, "A Timely Visit")
        self.assertEqual(rows[1].record_offset, 4 * 0x280)

    def test_quest_decoder_supports_explicit_supplemental_sections(self) -> None:
        data = _quest_dat(
            [
                (15, "Old Other Areas Quest", ()),
                (15, "Full Fields", ("Client: Zenicca",)),
                (200, "Titillating Tomes", ("Client: Green Thumb Moogle",)),
            ]
        )

        main = decode_quest_dat_bytes(
            data,
            "other_areas",
            "Other Areas",
            "ROM/176/64.DAT",
            start_slot=0,
            end_slot=1,
        )
        offset_supplement = decode_quest_dat_bytes(
            data,
            "adoulin",
            "Adoulin",
            "ROM/176/64.DAT",
            start_slot=1,
            end_slot=2,
            progress_id_offset=24,
        )
        direct_supplement = decode_quest_dat_bytes(
            data,
            "adoulin",
            "Adoulin",
            "ROM/176/64.DAT",
            start_slot=2,
            end_slot=3,
        )

        self.assertEqual(main[0].key, "quest:other_areas:15")
        self.assertEqual(offset_supplement[0].key, "quest:adoulin:39")
        self.assertEqual(offset_supplement[0].progress_id, 39)
        self.assertEqual(offset_supplement[0].record_offset, 0x280)
        self.assertEqual(direct_supplement[0].key, "quest:adoulin:200")

    def test_manifest_rejects_duplicate_native_keys(self) -> None:
        row = NativeObjective(
            kind="quest",
            context="sandoria",
            native_id=2,
            title="The Pickpocket",
            source_dat="ROM/176/60.DAT",
            record_offset=0,
        )
        with self.assertRaises(ManifestError):
            validate_unique_objectives([row, row])

    def test_manifest_builder_uses_declared_relative_dat_tables(self) -> None:
        self.assertEqual(MISSION_DAT_TABLES["Bastok"], "ROM/176/68.DAT")
        self.assertEqual(QUEST_DAT_TABLES["sandoria"].label, "San d'Oria")
        self.assertEqual(QUEST_DAT_TABLES["sandoria"].sections[0].relative_path, "ROM/176/60.DAT")
        self.assertEqual(QUEST_DAT_TABLES["adoulin"].sections[0].relative_path, "ROM/293/70.DAT")
        self.assertEqual(QUEST_DAT_TABLES["coalition"].sections[0].relative_path, "ROM/293/71.DAT")
        self.assertEqual(
            QUEST_DAT_TABLES["adoulin"].sections[1],
            QuestDatSection("ROM/176/64.DAT", start_slot=111, end_slot=121, progress_id_offset=24),
        )

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mission_path = root / "ROM" / "176" / "68.DAT"
            quest_path = root / "ROM" / "176" / "60.DAT"
            mission_path.parent.mkdir(parents=True)
            mission_path.write_bytes(_mission_dat([(1, "A Geological Survey", ("Assist Cid."))]))
            quest_path.write_bytes(_quest_dat([(2, "The Pickpocket", ("Client: Altiret",))]))

            manifest = build_native_manifest(
                root,
                mission_tables={"Bastok": "ROM/176/68.DAT"},
                quest_tables={
                    "sandoria": QuestDatSource(
                        "San d'Oria",
                        (QuestDatSection("ROM/176/60.DAT"),),
                    )
                },
            )

        self.assertEqual([row.key for row in manifest], ["mission:Bastok:1", "quest:sandoria:2"])


if __name__ == "__main__":
    unittest.main()

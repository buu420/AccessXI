from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

import roe_dat_decoder as decoder


class RoeDatDecoderTests(unittest.TestCase):
    def test_rotation_matches_xi_tinkerer(self) -> None:
        self.assertEqual(decoder.rotate_byte(0x91, 1), 0xC8)
        self.assertEqual(decoder.rotate_byte(0x91, 7), 0x23)
        self.assertEqual(decoder.get_text_shift_size(b"ABCD"), 1)
        self.assertEqual(decoder.get_text_shift_size(b"\x00\x00AB"), 0)

    def test_text_block_round_trip(self) -> None:
        original = bytearray(b"ABCD")
        encoded = bytearray(original)
        decoder.encode_text_block(encoded)
        self.assertNotEqual(encoded, original)
        decoder.decode_text_block(encoded)
        self.assertEqual(encoded, original)

    def test_decode_simple_ascii_and_terminator(self) -> None:
        ffxi = decoder.FfxiStringDecoder()
        self.assertEqual(ffxi.decode_simple(b"Vanquish Beasts\x00ignored"), "Vanquish Beasts")

    def test_decode_simple_secondary_conversion_table(self) -> None:
        ffxi = decoder.FfxiStringDecoder()
        self.assertEqual(ord(ffxi.decode_simple(bytes([0x8D, 0x49, 0x00]))), 0x5DE7)

    def test_exact_term_scan_does_not_invent_text(self) -> None:
        data = b"\x00\x01garbage\x00Vanquish Beasts\x00tail"
        hits = list(decoder.scan_exact_terms(data, ["Vanquish Beasts"]))
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0].term, "Vanquish Beasts")
        self.assertEqual(hits[0].text, "Vanquish Beasts")

    def test_extract_real_roe_record_when_dat_is_installed(self) -> None:
        dat = Path(r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\ROM\307\16.DAT")
        if not dat.exists():
            self.skipTest("FFXI RoE DAT is not installed")

        records = decoder.extract_roe_records(dat)
        record = records[4009]
        self.assertEqual(record.title, "Vanquish Beasts")
        self.assertIn("Limited-time Challenge", record.description)
        self.assertIn("experience-yielding beasts", record.description)
        self.assertEqual(record.goal, 20)
        self.assertEqual(record.sparks, 300)
        self.assertEqual(record.exp, 1500)
        self.assertEqual(record.accolades, 300)

    def test_extract_real_regular_roe_record_description_when_dat_is_installed(self) -> None:
        dat = Path(r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\ROM\307\16.DAT")
        if not dat.exists():
            self.skipTest("FFXI RoE DAT is not installed")

        records = decoder.extract_roe_records(dat)
        record = records[12]
        self.assertEqual(record.title, "Vanquish Multiple Enemies I")
        self.assertIn("experience-yielding enemies", record.description)
        self.assertEqual(record.goal, 200)
        self.assertEqual(record.sparks, 1000)
        self.assertEqual(record.exp, 5000)
        self.assertEqual(record.accolades, 100)

    def test_extract_real_unity_roe_metadata_when_dat_is_installed(self) -> None:
        dat = Path(r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\ROM\307\16.DAT")
        if not dat.exists():
            self.skipTest("FFXI RoE DAT is not installed")

        records = decoder.extract_roe_records(dat)
        unity_enemies = records[3059]
        self.assertEqual(unity_enemies.title, "Van. Enemies w. Unity Leader E (UC)")
        self.assertEqual(unity_enemies.goal, 10)
        self.assertEqual(unity_enemies.sparks, 100)
        self.assertEqual(unity_enemies.exp, 500)
        self.assertEqual(unity_enemies.accolades, 500)

        cure_ailments = records[3557]
        self.assertEqual(cure_ailments.title, "Cure Status Ailments (UC)")
        self.assertEqual(cure_ailments.goal, 5)
        self.assertEqual(cure_ailments.sparks, 100)
        self.assertEqual(cure_ailments.exp, 500)
        self.assertEqual(cure_ailments.accolades, 500)

    def test_extract_lsb_roe_goal_and_reward_metadata_when_available(self) -> None:
        lsb = Path(r"C:\Users\buu42\AccessXI\third_party\LandSandBoat-server\scripts\globals\roe_records.lua")
        if not lsb.exists():
            self.skipTest("LandSandBoat RoE records are not available")

        metadata = decoder.extract_lsb_roe_meta(lsb)
        self.assertEqual(metadata[12].goal, 200)
        self.assertEqual(metadata[12].sparks, 1000)
        self.assertEqual(metadata[12].exp, 5000)
        self.assertEqual(metadata[12].accolades, 100)
        self.assertEqual(metadata[4015].goal, 20)
        self.assertEqual(metadata[4015].sparks, 300)

    def test_extract_lsb_roe_repeatability_metadata_when_available(self) -> None:
        lsb = Path(r"C:\Users\buu42\AccessXI\third_party\LandSandBoat-server\scripts\globals\roe_records.lua")
        if not lsb.exists():
            self.skipTest("LandSandBoat RoE records are not available")

        metadata = decoder.extract_lsb_roe_meta(lsb)
        self.assertFalse(metadata[12].not_repeatable)
        self.assertIn("repeat", metadata[12].flags)
        self.assertTrue(metadata[13].not_repeatable)
        self.assertNotIn("repeat", metadata[13].flags)
        self.assertFalse(metadata[4009].not_repeatable)
        self.assertIn("timed", metadata[4009].flags)
        self.assertIn("repeat", metadata[4009].flags)

    def test_generated_category_metadata_does_not_include_dynamic_submenu_rows(self) -> None:
        lua = "\n".join(decoder.roe_static_category_lua())
        self.assertIn("data.objective_list_categories = T{", lua)
        self.assertNotIn("data.objective_category_rows", lua)
        self.assertNotIn("roe-category-index:tutorial", lua)
        self.assertNotIn("native_id = 0xF230", lua)


if __name__ == "__main__":
    unittest.main()

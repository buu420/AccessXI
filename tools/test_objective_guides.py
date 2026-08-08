from __future__ import annotations

import struct
import tempfile
import unittest
import json
from pathlib import Path

from tools.objective_guides.model import ManifestError, NativeObjective
from tools.objective_guides.mediawiki import (
    ACCESSXI_USER_AGENT,
    MediaWikiClient,
    MediaWikiError,
    PageRevision,
    refresh_snapshot,
)
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


class _ScriptedTransport:
    def __init__(self, responses: list[dict | Exception]) -> None:
        self.responses = list(responses)
        self.calls: list[tuple[str, dict[str, str], dict[str, str], float]] = []

    def __call__(
        self,
        api_url: str,
        params: dict[str, str],
        headers: dict[str, str],
        timeout: float,
    ) -> dict:
        self.calls.append((api_url, dict(params), dict(headers), timeout))
        if not self.responses:
            raise AssertionError("Unexpected MediaWiki request")
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


def _load_api_fixture(name: str) -> dict:
    path = Path(__file__).parent / "testdata" / "objective_guides" / name
    return json.loads(path.read_text(encoding="utf-8"))


class MediaWikiAcquisitionTests(unittest.TestCase):
    def test_category_members_follow_continuation_with_required_request_policy(self) -> None:
        transport = _ScriptedTransport(
            [
                {
                    "batchcomplete": True,
                    "continue": {"cmcontinue": "page|414354494e47", "continue": "-||"},
                    "query": {
                        "categorymembers": [
                            {"pageid": 12562, "ns": 0, "title": "Bastok Mission 1-2"}
                        ]
                    },
                },
                {
                    "batchcomplete": True,
                    "query": {
                        "categorymembers": [
                            {"pageid": 6, "ns": 0, "title": "Acting in Good Faith"}
                        ]
                    },
                },
            ]
        )
        client = MediaWikiClient(
            "bg",
            "https://www.bg-wiki.com/api.php",
            transport=transport,
        )

        members = client.category_members("Category:Missions")

        self.assertEqual([member.title for member in members], ["Bastok Mission 1-2", "Acting in Good Faith"])
        self.assertEqual(len(transport.calls), 2)
        first_params = transport.calls[0][1]
        second_params = transport.calls[1][1]
        self.assertEqual(first_params["formatversion"], "2")
        self.assertEqual(first_params["maxlag"], "5")
        self.assertEqual(first_params["cmlimit"], "max")
        self.assertEqual(second_params["cmcontinue"], "page|414354494e47")
        self.assertEqual(transport.calls[0][2]["User-Agent"], ACCESSXI_USER_AGENT)

    def test_fetch_pages_keeps_redirect_aliases_and_deduplicates_canonical_page(self) -> None:
        fixture = _load_api_fixture("bg-api-pages.json")
        response = dict(fixture["response"])
        response["query"] = dict(response["query"])
        response["query"]["redirects"] = [
            {"from": "A Geological Survey", "to": "Bastok Mission 1-2"}
        ]
        transport = _ScriptedTransport([response])
        client = MediaWikiClient(
            "bg",
            "https://www.bg-wiki.com/api.php",
            transport=transport,
        )

        pages = client.fetch_pages(["A Geological Survey", "Bastok Mission 1-2", "Acting in Good Faith"])

        self.assertEqual([page.canonical_title for page in pages], ["Acting in Good Faith", "Bastok Mission 1-2"])
        geological = pages[1]
        self.assertEqual(geological.page_id, 12562)
        self.assertEqual(geological.revision_id, 686732)
        self.assertIn("A Geological Survey", geological.aliases)
        params = transport.calls[0][1]
        self.assertEqual(params["rvslots"], "main")
        self.assertEqual(params["rvprop"], "ids|timestamp|content")
        self.assertEqual(params["redirects"], "1")
        self.assertLessEqual(len(params["titles"].split("|")), 40)

    def test_fetch_pages_rejects_missing_or_conflicting_canonical_pages(self) -> None:
        missing = _ScriptedTransport(
            [{"batchcomplete": True, "query": {"pages": [{"ns": 0, "title": "Missing", "missing": True}]}}]
        )
        with self.assertRaises(MediaWikiError):
            MediaWikiClient("bg", "https://www.bg-wiki.com/api.php", transport=missing).fetch_pages(["Missing"])

        fixture = _load_api_fixture("bg-api-pages.json")["response"]
        duplicate = json.loads(json.dumps(fixture))
        second = json.loads(json.dumps(duplicate["query"]["pages"][0]))
        second["revisions"][0]["revid"] += 1
        duplicate["query"]["pages"].append(second)
        with self.assertRaises(MediaWikiError):
            MediaWikiClient(
                "bg",
                "https://www.bg-wiki.com/api.php",
                transport=_ScriptedTransport([duplicate]),
            ).fetch_pages(["Acting in Good Faith"])

    def test_revision_cache_key_carries_site_ids_and_content_hash(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Bastok Mission 1-2",
            page_id=12562,
            revision_id=686732,
            parent_revision_id=678203,
            revision_timestamp="2023-07-27T00:56:06Z",
            content="walkthrough",
            aliases=("A Geological Survey",),
        )

        self.assertRegex(
            page.cache_key,
            r"^bg-page-12562-revision-686732-sha256-[0-9a-f]{64}$",
        )
        self.assertEqual(page.source_url, "https://www.bg-wiki.com/ffxi/Bastok_Mission_1-2")

        with tempfile.TemporaryDirectory() as temporary:
            client = MediaWikiClient(
                "bg",
                "https://www.bg-wiki.com/api.php",
                cache_dir=Path(temporary),
                transport=_ScriptedTransport([]),
            )
            cache_path = client.cache_revision(page)
            self.assertIsNotNone(cache_path)
            assert cache_path is not None
            self.assertEqual(cache_path.stem, page.cache_key)
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            self.assertEqual(cached["content_sha256"], page.content_sha256)
            self.assertEqual(cached["license"], "CC-BY-NC-SA-3.0")

    def test_failed_refresh_does_not_replace_prior_snapshot(self) -> None:
        first_page = _load_api_fixture("bg-api-pages.json")["response"]["query"]["pages"][0]
        transport = _ScriptedTransport(
            [
                {"batchcomplete": True, "query": {"pages": [first_page]}},
                MediaWikiError("simulated second batch failure"),
            ]
        )
        client = MediaWikiClient(
            "bg",
            "https://www.bg-wiki.com/api.php",
            transport=transport,
            batch_size=1,
            max_attempts=1,
        )

        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary) / "snapshot.json"
            snapshot.write_text('{"reviewed":"prior"}\n', encoding="utf-8")
            before = snapshot.read_bytes()

            with self.assertRaises(MediaWikiError):
                refresh_snapshot(client, ["Acting in Good Faith", "Bastok Mission 1-2"], snapshot)

            self.assertEqual(snapshot.read_bytes(), before)

    def test_recorded_fixtures_decode_both_sites(self) -> None:
        for site, fixture_name, api_url in (
            ("bg", "bg-api-pages.json", "https://www.bg-wiki.com/api.php"),
            ("ffxiclopedia", "ffxiclopedia-api-pages.json", "https://ffxiclopedia.fandom.com/api.php"),
        ):
            fixture = _load_api_fixture(fixture_name)
            pages = MediaWikiClient(site, api_url, transport=_ScriptedTransport([fixture["response"]])).fetch_pages(
                fixture["requested_titles"]
            )
            self.assertEqual(len(pages), 2)
            self.assertTrue(all(page.content for page in pages))
            self.assertEqual(fixture["source"]["license"], pages[0].license_id)


if __name__ == "__main__":
    unittest.main()

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
    load_snapshot,
    recursive_category_pages,
    refresh_snapshot,
)
from tools.objective_guides.wikitext import parse_objective_page
from tools.objective_guides.matching import match_objective_pages, normalize_title
from tools.objective_guides.reconcile import reconcile_objectives
from tools.objective_guides.model import ParsedObjective, SourceStep
from tools.objective_guides.generate_lua import (
    build_guide_artifacts,
    lua_quote,
    source_module_name,
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


def _fixture_revisions(site: str, fixture_name: str, api_url: str) -> dict[str, PageRevision]:
    fixture = _load_api_fixture(fixture_name)
    pages = MediaWikiClient(site, api_url, transport=_ScriptedTransport([fixture["response"]])).fetch_pages(
        fixture["requested_titles"]
    )
    return {page.canonical_title: page for page in pages}


class MediaWikiAcquisitionTests(unittest.TestCase):
    def test_recursive_category_walk_returns_pages_once_and_stops_cycles(self) -> None:
        transport = _ScriptedTransport(
            [
                {
                    "batchcomplete": True,
                    "query": {
                        "categorymembers": [
                            {"pageid": 10, "ns": 0, "title": "First Mission"},
                            {"pageid": 20, "ns": 14, "title": "Category:Nation Missions"},
                        ]
                    },
                },
                {
                    "batchcomplete": True,
                    "query": {
                        "categorymembers": [
                            {"pageid": 11, "ns": 0, "title": "Second Mission"},
                            {"pageid": 21, "ns": 14, "title": "Category:Missions"},
                        ]
                    },
                },
            ]
        )
        client = MediaWikiClient("bg", "https://www.bg-wiki.com/api.php", transport=transport)

        pages, categories = recursive_category_pages(client, ["Category:Missions"])

        self.assertEqual([page.title for page in pages], ["First Mission", "Second Mission"])
        self.assertEqual(categories, ("Category:Missions", "Category:Nation Missions"))
        self.assertEqual(len(transport.calls), 2)

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

    def test_lenient_page_fetch_keeps_existing_pages_and_reports_missing_titles(self) -> None:
        fixture_page = _load_api_fixture("bg-api-pages.json")["response"]["query"]["pages"][0]
        transport = _ScriptedTransport(
            [
                {
                    "batchcomplete": True,
                    "query": {
                        "pages": [
                            fixture_page,
                            {"ns": 0, "title": "Definitely Missing", "missing": True},
                        ]
                    },
                }
            ]
        )
        client = MediaWikiClient("bg", "https://www.bg-wiki.com/api.php", transport=transport)

        pages, missing = client.fetch_existing_pages(["Acting in Good Faith", "Definitely Missing"])

        self.assertEqual([page.canonical_title for page in pages], ["Acting in Good Faith"])
        self.assertEqual(missing, ("Definitely Missing",))

    def test_snapshot_loader_rejects_content_hash_tampering(self) -> None:
        fixture = _load_api_fixture("bg-api-pages.json")
        client = MediaWikiClient(
            "bg",
            "https://www.bg-wiki.com/api.php",
            transport=_ScriptedTransport([fixture["response"]]),
        )
        with tempfile.TemporaryDirectory() as temporary:
            snapshot_path = Path(temporary) / "bg.json"
            refresh_snapshot(client, fixture["requested_titles"], snapshot_path)
            loaded = load_snapshot(snapshot_path, expected_site="bg")
            self.assertEqual(len(loaded), 2)

            payload = json.loads(snapshot_path.read_text(encoding="utf-8"))
            payload["pages"][0]["content"] += "tampered"
            snapshot_path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaises(MediaWikiError):
                load_snapshot(snapshot_path, expected_site="bg")

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


class WikitextParserTests(unittest.TestCase):
    def test_parses_both_mission_header_dialects_and_preserves_coordinate_conflict(self) -> None:
        bg = _fixture_revisions(
            "bg",
            "bg-api-pages.json",
            "https://www.bg-wiki.com/api.php",
        )["Bastok Mission 1-2"]
        ffxiclopedia = _fixture_revisions(
            "ffxiclopedia",
            "ffxiclopedia-api-pages.json",
            "https://ffxiclopedia.fandom.com/api.php",
        )["A Geological Survey"]

        bg_parsed = parse_objective_page(bg)
        ffxiclopedia_parsed = parse_objective_page(ffxiclopedia)

        self.assertEqual(bg_parsed.kind, "mission")
        self.assertEqual(ffxiclopedia_parsed.kind, "mission")
        self.assertEqual(bg_parsed.objective_name, "A Geological Survey")
        self.assertEqual(ffxiclopedia_parsed.objective_name, "A Geological Survey")
        self.assertEqual(bg_parsed.mission_number, "1-2")
        self.assertEqual(ffxiclopedia_parsed.mission_number, "1-2")
        self.assertEqual(
            [step.action for step in bg_parsed.steps],
            ["talk", "talk", "travel", "use", "talk"],
        )
        self.assertEqual(
            [step.action for step in ffxiclopedia_parsed.steps],
            ["talk", "talk", "travel", "use", "talk"],
        )
        bg_cid = next(step for step in bg_parsed.steps if "Cid" in step.linked_entities)
        ffxi_cid = next(step for step in ffxiclopedia_parsed.steps if "Cid" in step.spoken_text)
        self.assertIn("G-8", bg_cid.grid_coordinates)
        self.assertIn("H-8", ffxi_cid.grid_coordinates)

    def test_dynamic_question_mark_candidates_and_source_disagreement_remain_visible(self) -> None:
        bg = _fixture_revisions(
            "bg",
            "bg-api-pages.json",
            "https://www.bg-wiki.com/api.php",
        )["Acting in Good Faith"]
        ffxiclopedia = _fixture_revisions(
            "ffxiclopedia",
            "ffxiclopedia-api-pages.json",
            "https://ffxiclopedia.fandom.com/api.php",
        )["Acting in Good Faith"]

        bg_parsed = parse_objective_page(bg)
        ffxiclopedia_parsed = parse_objective_page(ffxiclopedia)
        expected = {"I-7", "I-10", "M-6", "D-5"}

        self.assertTrue(expected.issubset({coord for step in bg_parsed.steps for coord in step.grid_coordinates}))
        self.assertTrue(expected.issubset({coord for step in ffxiclopedia_parsed.steps for coord in step.grid_coordinates}))
        self.assertTrue(any("always fail" in step.spoken_text.lower() for step in bg_parsed.steps))
        self.assertTrue(any("rarely" in step.spoken_text.lower() for step in ffxiclopedia_parsed.steps))

    def test_nested_lists_templates_and_page_furniture_are_handled_without_row_guessing(self) -> None:
        page = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Synthetic Quest",
            page_id=9001,
            revision_id=42,
            parent_revision_id=41,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "{{Quest|startnpc=[[Tester]] - {{Location|Port Windurst|E-7}}}}\n"
                "==Walkthrough==\n"
                "[[File:Map.png|thumb|A map caption that must not become a step.]]\n"
                "#Talk to [[Tester]] at {{Location Tooltip|area=Port Windurst|text=E-7|pos=E-7}}.\n"
                "#*Bring {{KeyItem}}[[Test key item]].\n"
                "#**{{Unknown Guide Box|opaque=yes}} This warning remains readable.\n"
                "{| class=\"wikitable\"\n| Reward || 999 gil\n|}\n"
                "==Plot Details==\n*This must not be imported.\n"
            ),
        )

        parsed = parse_objective_page(page)

        self.assertEqual([step.marker for step in parsed.steps], ["#", "#*", "#**"])
        self.assertEqual([step.depth for step in parsed.steps], [1, 2, 3])
        self.assertIn("Port Windurst", parsed.steps[0].zone_candidates)
        self.assertIn("Test key item", parsed.steps[1].key_items)
        self.assertTrue(parsed.steps[2].warnings)
        self.assertFalse(any("999 gil" in step.source_text for step in parsed.steps))
        self.assertFalse(any("Plot Details" in step.source_text for step in parsed.steps))

    def test_spoken_step_cap_retains_required_entities_and_coordinates(self) -> None:
        filler = "very long explanatory phrase " * 30
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Long Quest",
            page_id=9002,
            revision_id=43,
            parent_revision_id=42,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "{{Quest Header|Start=[[Guide NPC]]}}\n==Walkthrough==\n"
                f"*Talk to [[Guide NPC]] {filler}in [[Western Adoulin]] at (K-9).\n"
            ),
        )

        parsed = parse_objective_page(page)
        spoken = parsed.steps[0].spoken_text

        self.assertLessEqual(len(spoken), 420)
        self.assertIn("Talk", spoken)
        self.assertIn("Guide NPC", spoken)
        self.assertIn("K-9", spoken)


class MatchingTests(unittest.TestCase):
    def test_reviewed_geological_mapping_seeds_stages_without_unreviewed_targets(self) -> None:
        path = Path(__file__).parents[1] / "data" / "mission-quest-guides" / "reviewed-overrides.json"
        overrides = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(overrides["page_matches"]["mission:Bastok:2"]["bg"]["page_id"], 12562)
        self.assertEqual(
            set(overrides["automatic_stage_links"]["mission:Bastok:2"]),
            {"obtain-blue-tester", "charge-blue-tester", "return-red-tester"},
        )
        self.assertEqual(overrides["target_overrides"], {})

    def test_exact_mission_context_number_title_and_redirect_alias_match(self) -> None:
        native = NativeObjective(
            kind="mission",
            context="Bastok",
            native_id=2,
            title="A Geological Survey",
            source_dat="ROM/176/68.DAT",
            record_offset=0x280,
            progress_id=1,
        )
        page = parse_objective_page(
            _fixture_revisions(
                "bg",
                "bg-api-pages.json",
                "https://www.bg-wiki.com/api.php",
            )["Bastok Mission 1-2"]
        )

        report = match_objective_pages([native], [page])

        self.assertEqual(len(report.matches), 1)
        self.assertEqual(report.matches[0].native_key, "mission:Bastok:2")
        self.assertEqual(report.matches[0].page_id, 12562)
        self.assertEqual(report.matches[0].method, "exact-title-context")

        alias_page = ParsedObjective(
            site="bg",
            page_id=77,
            revision_id=88,
            canonical_title="Geological Survey",
            kind="mission",
            objective_name="Geological Survey",
            aliases=("A Geological Survey",),
            context_hint="Bastok",
        )
        alias_report = match_objective_pages([native], [alias_page])
        self.assertEqual(alias_report.matches[0].native_key, native.key)
        self.assertEqual(alias_report.matches[0].method, "exact-alias-context")

    def test_quest_duplicate_title_uses_area_and_start_npc_without_guessing(self) -> None:
        natives = [
            NativeObjective(
                kind="quest",
                context="sandoria",
                native_id=103,
                title="Escort for Hire",
                source_dat="sandoria.DAT",
                record_offset=0,
                progress_id=103,
                details=("Client: Rondipur",),
            ),
            NativeObjective(
                kind="quest",
                context="bastok",
                native_id=70,
                title="Escort for Hire",
                source_dat="bastok.DAT",
                record_offset=0,
                progress_id=70,
                details=("Client: Deidogg",),
            ),
        ]
        page = ParsedObjective(
            site="ffxiclopedia",
            page_id=99,
            revision_id=100,
            canonical_title="Escort for Hire (Bastok)",
            kind="quest",
            objective_name="Escort for Hire",
            categories=("Bastok Quests",),
            start_entities=("Deidogg",),
        )

        report = match_objective_pages(natives, [page])

        self.assertEqual([match.native_key for match in report.matches], ["quest:bastok:70"])
        self.assertFalse(report.ambiguous_pages)

    def test_punctuation_normalization_is_exact_but_fuzzy_results_are_review_only(self) -> None:
        self.assertEqual(normalize_title("Café...teria"), normalize_title("Cafe-teria"))
        native = NativeObjective(
            kind="quest",
            context="adoulin",
            native_id=94,
            title="Cafe...teria",
            source_dat="adoulin.DAT",
            record_offset=0,
            progress_id=94,
        )
        exact = ParsedObjective(
            site="bg",
            page_id=101,
            revision_id=102,
            canonical_title="Café-teria",
            kind="quest",
            objective_name="Café-teria",
            categories=("Adoulin Quests",),
        )
        fuzzy = ParsedObjective(
            site="bg",
            page_id=103,
            revision_id=104,
            canonical_title="Cafe Taria",
            kind="quest",
            objective_name="Cafe Taria",
            categories=("Adoulin Quests",),
        )

        exact_report = match_objective_pages([native], [exact])
        fuzzy_report = match_objective_pages([native], [fuzzy])

        self.assertEqual(exact_report.matches[0].native_key, native.key)
        self.assertFalse(fuzzy_report.matches)
        self.assertEqual(fuzzy_report.suggestions[103], (native.key,))

    def test_ambiguous_exact_page_never_maps_to_multiple_native_keys(self) -> None:
        natives = [
            NativeObjective("quest", "sandoria", 1, "Shared Name", "a", 0, 1),
            NativeObjective("quest", "bastok", 1, "Shared Name", "b", 0, 1),
        ]
        page = ParsedObjective(
            site="bg",
            page_id=105,
            revision_id=106,
            canonical_title="Shared Name",
            kind="quest",
            objective_name="Shared Name",
        )

        report = match_objective_pages(natives, [page])

        self.assertFalse(report.matches)
        self.assertEqual(report.ambiguous_pages[105], ("quest:bastok:1", "quest:sandoria:1"))


class ReconciliationTests(unittest.TestCase):
    def test_geological_survey_aligns_material_steps_but_keeps_cid_grid_conflict(self) -> None:
        bg = parse_objective_page(
            _fixture_revisions("bg", "bg-api-pages.json", "https://www.bg-wiki.com/api.php")[
                "Bastok Mission 1-2"
            ]
        )
        ffxi = parse_objective_page(
            _fixture_revisions(
                "ffxiclopedia",
                "ffxiclopedia-api-pages.json",
                "https://ffxiclopedia.fandom.com/api.php",
            )["A Geological Survey"]
        )

        reconciled = reconcile_objectives("mission:Bastok:2", bg, ffxi)

        cid = next(step for step in reconciled.steps if "Cid" in step.entities and step.order < len(reconciled.steps))
        self.assertEqual(cid.comparison, "conflict")
        self.assertIn("grid_coordinates", cid.conflicting_fields)
        self.assertFalse(cid.route_ready)
        self.assertTrue(any(step.comparison == "corroborated" for step in reconciled.steps))

    def test_dynamic_candidate_set_is_corroborated_and_never_collapsed(self) -> None:
        bg = parse_objective_page(
            _fixture_revisions("bg", "bg-api-pages.json", "https://www.bg-wiki.com/api.php")[
                "Acting in Good Faith"
            ]
        )
        ffxi = parse_objective_page(
            _fixture_revisions(
                "ffxiclopedia",
                "ffxiclopedia-api-pages.json",
                "https://ffxiclopedia.fandom.com/api.php",
            )["Acting in Good Faith"]
        )

        reconciled = reconcile_objectives("quest:windurst:77", bg, ffxi)

        self.assertEqual(reconciled.dynamic_candidate_grid, ("D-5", "I-7", "I-10", "M-6"))
        self.assertEqual(reconciled.dynamic_candidate_comparison, "corroborated")
        self.assertIsNone(reconciled.selected_candidate_grid)
        self.assertTrue(any("result" in step.conflicting_fields for step in reconciled.steps))

    def test_alignment_uses_factual_fields_instead_of_prose_similarity(self) -> None:
        bg = ParsedObjective(
            site="bg",
            page_id=1,
            revision_id=1,
            canonical_title="One",
            kind="quest",
            objective_name="One",
            steps=(
                SourceStep(
                    1,
                    "*",
                    1,
                    "Proceed to the engineer.",
                    "Proceed to the engineer.",
                    "talk",
                    linked_entities=("Cid",),
                    zone_candidates=("Metalworks",),
                    grid_coordinates=("H-8",),
                ),
            ),
        )
        ffxi = ParsedObjective(
            site="ffxiclopedia",
            page_id=2,
            revision_id=2,
            canonical_title="One",
            kind="quest",
            objective_name="One",
            steps=(
                SourceStep(
                    1,
                    "#",
                    1,
                    "Speak with Cid in his laboratory.",
                    "Speak with Cid in his laboratory.",
                    "talk",
                    linked_entities=("Cid",),
                    zone_candidates=("Metalworks",),
                    grid_coordinates=("H-8",),
                ),
            ),
        )

        reconciled = reconcile_objectives("quest:bastok:1", bg, ffxi)

        self.assertEqual(len(reconciled.steps), 1)
        self.assertEqual(reconciled.steps[0].comparison, "corroborated")
        self.assertEqual(reconciled.steps[0].source_orders, (1, 1))


class GeneratedArtifactTests(unittest.TestCase):
    def _native_rows(self) -> tuple[NativeObjective, ...]:
        return (
            NativeObjective(
                "mission",
                "Bastok",
                2,
                "A Geological Survey",
                "ROM/176/68.DAT",
                0x280,
                1,
            ),
            NativeObjective(
                "quest",
                "windurst",
                77,
                "Acting in Good Faith",
                "ROM/176/62.DAT",
                0xC080,
                77,
            ),
            NativeObjective(
                "quest",
                "bastok",
                92,
                "No Source Objective",
                "ROM/176/61.DAT",
                0xE600,
                92,
            ),
        )

    def _source_pages(self) -> tuple[ParsedObjective, ...]:
        bg = _fixture_revisions("bg", "bg-api-pages.json", "https://www.bg-wiki.com/api.php")
        ffxi = _fixture_revisions(
            "ffxiclopedia",
            "ffxiclopedia-api-pages.json",
            "https://ffxiclopedia.fandom.com/api.php",
        )
        return (
            parse_objective_page(bg["Bastok Mission 1-2"]),
            parse_objective_page(bg["Acting in Good Faith"]),
            parse_objective_page(ffxi["A Geological Survey"]),
            parse_objective_page(ffxi["Acting in Good Faith"]),
        )

    def test_lua_escaping_and_module_names_are_stable(self) -> None:
        self.assertEqual(lua_quote("Cid's\\lab\nnext"), '"Cid\'s\\\\lab\\nnext"')
        self.assertEqual(
            source_module_name("bg", "mission", "San d'Oria"),
            "mission_quest_bg_mission_san_doria",
        )
        self.assertEqual(
            source_module_name("ffxiclopedia", "quest", "other_areas"),
            "mission_quest_ffxiclopedia_quest_other_areas",
        )

    def test_generation_is_deterministic_complete_and_source_separated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module_root = root / "modules"
            data_root = root / "data"

            first = build_guide_artifacts(
                self._native_rows(),
                self._source_pages(),
                module_root=module_root,
                data_root=data_root,
            )
            first_bytes = {
                path.relative_to(root).as_posix(): path.read_bytes()
                for path in sorted(root.rglob("*"))
                if path.is_file()
            }
            second = build_guide_artifacts(
                self._native_rows(),
                self._source_pages(),
                module_root=module_root,
                data_root=data_root,
            )
            second_bytes = {
                path.relative_to(root).as_posix(): path.read_bytes()
                for path in sorted(root.rglob("*"))
                if path.is_file()
            }

            self.assertEqual(first_bytes, second_bytes)
            self.assertEqual(first, second)
            index = (module_root / "mission_quest_guide_index.lua").read_text(encoding="utf-8")
            self.assertEqual(index.count('["mission:Bastok:2"]'), 1)
            self.assertEqual(index.count('["quest:windurst:77"]'), 1)
            self.assertEqual(index.count('["quest:bastok:92"]'), 1)
            self.assertIn('status = "source-missing"', index)

            bg_quest = (module_root / "mission_quest_bg_quest_windurst.lua").read_text(encoding="utf-8")
            ffxi_quest = (
                module_root / "mission_quest_ffxiclopedia_quest_windurst.lua"
            ).read_text(encoding="utf-8")
            self.assertIn("always fail", bg_quest)
            self.assertNotIn("rarely report success", bg_quest)
            self.assertIn("rarely report success", ffxi_quest)
            self.assertNotIn("always fail", ffxi_quest)
            self.assertIn("CC BY-NC-SA 3.0", bg_quest)
            self.assertIn("CC BY-SA 3.0", ffxi_quest)
            self.assertIn("revision_id = 774429", bg_quest)
            self.assertIn("revision_id = 1771132", ffxi_quest)

            reconcile = (
                module_root / "mission_quest_reconcile_quest_windurst.lua"
            ).read_text(encoding="utf-8")
            self.assertNotIn("always fail", reconcile)
            self.assertNotIn("rarely report success", reconcile)
            self.assertIn('dynamic_candidate_comparison = "corroborated"', reconcile)
            self.assertIn('"D-5", "I-7", "I-10", "M-6"', reconcile)

            coverage = json.loads((data_root / "coverage.json").read_text(encoding="utf-8"))
            self.assertEqual(coverage["counts"]["valid_native"], 3)
            self.assertEqual(sum(coverage["counts"]["by_status"].values()), 3)
            self.assertEqual(coverage["objectives"]["quest:bastok:92"]["status"], "source-missing")
            self.assertEqual(len(coverage["objectives"]), 3)

            snapshot = json.loads((data_root / "source-snapshot.json").read_text(encoding="utf-8"))
            self.assertTrue(all("content" not in page for page in snapshot["pages"]))
            self.assertEqual(len(snapshot["pages"]), 4)
            self.assertTrue(all(page["content_sha256"] for page in snapshot["pages"]))
            self.assertTrue(all(page["revision_timestamp"] for page in snapshot["pages"]))
            self.assertEqual(
                {page["license"] for page in snapshot["pages"]},
                {"CC-BY-NC-SA-3.0", "CC-BY-SA-3.0"},
            )
            self.assertTrue(all(page["source_url"].startswith("https://") for page in snapshot["pages"]))


if __name__ == "__main__":
    unittest.main()

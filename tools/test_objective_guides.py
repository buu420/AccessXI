from __future__ import annotations

import struct
import tempfile
import unittest
import json
from pathlib import Path

from tools.objective_guides.model import ManifestError, NativeObjective, SourceActionSpan
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
from tools.objective_guides.reconcile import ReviewedObjectiveDestination, reconcile_objectives
from tools.objective_guides.objective_destinations import (
    ObjectiveDestinationError,
    resolve_reviewed_objective_destinations,
)
from tools.objective_guides.model import ParsedObjective, SourceStep
from tools.objective_guides.generate_lua import (
    GenerationError,
    build_guide_artifacts,
    lua_quote,
    source_module_name,
)
from tools.objective_guides.cli import _load_navigation_catalog, _requested_source_titles
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
    def test_source_title_candidates_include_reviewed_non_log_aliases(self) -> None:
        native = NativeObjective(
            "quest",
            "outlands",
            128,
            "The Sahagin's Key",
            "quests.dat",
            0,
            128,
        )

        titles = _requested_source_titles(
            ("Category-discovered quest",),
            (native,),
            ("Sahagin Key Quest",),
        )

        self.assertEqual(
            titles,
            ("Category-discovered quest", "The Sahagin's Key", "Sahagin Key Quest"),
        )

    def test_successful_api_batches_resume_across_clients_until_cleared(self) -> None:
        response = {
            "batchcomplete": True,
            "query": {
                "categorymembers": [
                    {"pageid": 10, "ns": 0, "title": "First Mission"},
                ]
            },
        }
        with tempfile.TemporaryDirectory() as temporary:
            resume_root = Path(temporary) / "resume"
            first_transport = _ScriptedTransport([response])
            first = MediaWikiClient(
                "bg",
                "https://www.bg-wiki.com/api.php",
                transport=first_transport,
                request_cache_dir=resume_root,
            )

            self.assertEqual(first.category_members("Category:Missions")[0].title, "First Mission")
            self.assertEqual(len(first_transport.calls), 1)

            resumed_transport = _ScriptedTransport([])
            resumed = MediaWikiClient(
                "bg",
                "https://www.bg-wiki.com/api.php",
                transport=resumed_transport,
                request_cache_dir=resume_root,
            )
            self.assertEqual(resumed.category_members("Category:Missions")[0].title, "First Mission")
            self.assertEqual(resumed_transport.calls, [])

            resumed.clear_request_cache()
            self.assertEqual(list(resume_root.glob("*.json")), [])

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
        self.assertLessEqual(len(params["titles"].split("|")), 50)

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
    def test_nyzul_special_pages_keep_only_progress_sections(self) -> None:
        bg = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Nyzul Isle Uncharted Area Survey",
            page_id=87211,
            revision_id=751150,
            parent_revision_id=751149,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "{{Nyzul Header\n"
                "|Assault Area=Nyzul Isle\n"
                "|Orders=Complete on-site objectives.\n"
                "|Level=99\n"
                "}}[[Category:Assault]]\n"
                "==Entry==\n"
                "Speak with [[Sorrowful Sage]] before entering.\n"
                "==Floor Objectives==\n"
                "*Defeat the enemy that checks as [[Impossible to Gauge]].\n"
                "==Advancement==\n"
                "*Use the [[Rune of Transfer]] after completing the objective.\n"
                "==Rewards==\n"
                "*A reward table is not progress guidance.\n"
            ),
        )
        ffxiclopedia = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Nyzul Isle Investigation",
            page_id=46228,
            revision_id=1700640,
            parent_revision_id=1700639,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "[[Category:Missions]][[Category:Assault Missions]]\n"
                "==Rules==\n"
                "*Obtain an [[Imperial Army I.D. Tag]].\n"
                "==Objectives==\n"
                "*Complete the randomly assigned floor objective.\n"
                "==Rewards==\n"
                "*A reward table is not progress guidance.\n"
            ),
        )

        parsed_bg = parse_objective_page(bg)
        parsed_ffxi = parse_objective_page(ffxiclopedia)

        self.assertEqual((parsed_bg.kind, parsed_bg.context_hint), ("mission", "Assault"))
        self.assertIn("Complete on-site objectives", parsed_bg.steps[0].spoken_text)
        self.assertTrue(any("Sorrowful Sage" in step.spoken_text for step in parsed_bg.steps))
        self.assertTrue(any("Rune of Transfer" in step.spoken_text for step in parsed_bg.steps))
        self.assertEqual((parsed_ffxi.kind, parsed_ffxi.context_hint), ("mission", "Assault"))
        self.assertTrue(any("Imperial Army I.D. Tag" in step.spoken_text for step in parsed_ffxi.steps))
        self.assertFalse(any("reward table" in step.spoken_text.casefold() for step in (*parsed_bg.steps, *parsed_ffxi.steps)))

    def test_sahagin_key_miniquest_page_uses_obtainment_sections_only(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Sahagin Key",
            page_id=1787,
            revision_id=767515,
            parent_revision_id=767514,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "[[Category:Mini-Quests]]\n"
                "==Obtainment==\n"
                "*Speak to [[Gimb]] in [[Norg]].\n"
                "==Additional Keys==\n"
                "*Trade a [[Gold Beastcoin]] and a [[Norg Shell]].\n"
                "==Notes==\n"
                "*This note is not part of the ordered acquisition guide.\n"
            ),
        )

        parsed = parse_objective_page(page)

        self.assertEqual(parsed.kind, "quest")
        self.assertTrue(any("Gimb" in step.spoken_text for step in parsed.steps))
        self.assertTrue(any("Gold Beastcoin" in step.spoken_text for step in parsed.steps))
        self.assertFalse(any("not part" in step.spoken_text for step in parsed.steps))

    def test_legacy_objective_templates_preserve_source_details_without_inventing_routes(self) -> None:
        assault = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Synthetic Assault",
            page_id=9100,
            revision_id=50,
            parent_revision_id=49,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "{{Assault Mission\n"
                "| name = Synthetic Assault\n"
                "| area = [[Leujaoam Sanctum]]\n"
                "| npc = [[Yahsra]] - [[Aht Urhgan Whitegate]] (L-10)\n"
                "| staging point = [[Azouph Isle Staging Point]]\n"
                "| objective = Remove all threats\n"
                "| orders = Destroy all creatures in the area.\n"
                "}}\n"
                "==Walkthrough==\n"
                "* Go north and defeat every [[Leujaoam Worm]].\n"
            ),
        )
        gobbiebag = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Synthetic Gobbiebag",
            page_id=9101,
            revision_id=51,
            parent_revision_id=50,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "{{Gobbiebag Quest\n"
                "|item1=[[Dhalmel Leather]]\n"
                "|summary=[[Bluffnix]] will enlarge your pack if you bring [[Dhalmel Leather]].\n"
                "}}\n"
            ),
        )

        parsed_assault = parse_objective_page(assault)
        parsed_gobbiebag = parse_objective_page(gobbiebag)

        self.assertEqual(parsed_assault.kind, "mission")
        self.assertEqual(parsed_assault.objective_name, "Synthetic Assault")
        self.assertIn("Remove all threats", parsed_assault.steps[0].spoken_text)
        self.assertIn("Leujaoam Sanctum", parsed_assault.steps[0].spoken_text)
        self.assertNotIn("..", parsed_assault.steps[0].spoken_text)
        self.assertIn("Leujaoam Worm", parsed_assault.steps[1].linked_entities)
        self.assertEqual(parsed_gobbiebag.kind, "quest")
        self.assertEqual(len(parsed_gobbiebag.steps), 1)
        self.assertIn("Bluffnix", parsed_gobbiebag.steps[0].spoken_text)
        self.assertIn("Dhalmel Leather", parsed_gobbiebag.steps[0].linked_entities)

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

    def test_plain_and_numbered_walkthrough_paragraphs_become_ordered_steps(self) -> None:
        page = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Paragraph Quest",
            page_id=9003,
            revision_id=44,
            parent_revision_id=43,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "Speak with [[Maat]] at {{Location|Ru'Lude Gardens|H-5}}.\n\n"
                "1. Trade a [[Test Item]] to [[Maat]].\n"
                ":*The item can be obtained from a monster.\n"
                "{{Quest/Description\n|summary=Template furniture must not become a step.\n}}\n"
                "===Battle notes===\n"
                "Defeat the target and inspect the ??? again.\n"
            ),
        )

        parsed = parse_objective_page(page)

        self.assertEqual(len(parsed.steps), 5)
        self.assertIn("Maat", parsed.steps[0].linked_entities)
        self.assertEqual(parsed.steps[1].action, "trade")
        self.assertGreater(parsed.steps[2].depth, parsed.steps[1].depth)
        self.assertEqual(parsed.steps[3].spoken_text, "Section: Battle notes.")
        self.assertIn("Defeat the target", parsed.steps[4].spoken_text)
        self.assertFalse(any("Template furniture" in step.spoken_text for step in parsed.steps))

    def test_numbered_route_headings_at_walkthrough_level_stay_inside_the_guide(self) -> None:
        page = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Composite Mission",
            page_id=9004,
            revision_id=45,
            parent_revision_id=44,
            revision_timestamp="2026-08-08T00:00:00Z",
            content=(
                "{{Mission|name=Composite Mission}}\n"
                "==Walkthrough==\nStart the mission.\n"
                "==3-3A: First Route==\nTalk to [[First NPC]].\n"
                "==3-3B: Second Route==\nTalk to [[Second NPC]].\n"
                "==Notes==\nThis must not be imported.\n"
            ),
        )

        parsed = parse_objective_page(page)

        self.assertEqual([step.spoken_text for step in parsed.steps], [
            "Start the mission.",
            "Section: 3-3A: First Route.",
            "Talk to First NPC.",
            "Section: 3-3B: Second Route.",
            "Talk to Second NPC.",
        ])

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

    def test_typed_action_spans_preserve_ordered_chains_and_result_relations(self) -> None:
        page = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Typed Action Quest",
            page_id=9200,
            revision_id=81,
            parent_revision_id=80,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Trade a [[Scholar Stone]] to the [[Task Delegator]], then talk to the [[Task Delegator]].\n"
                "*Defeat [[Orcish Fodder]] to obtain an [[Orcish Axe]].\n"
                "*Kill [[Badshah]] and re-examine the ??? to obtain [[Silver Comet's collar]].\n"
                "*Return to [[Cid]].\n"
            ),
        )

        parsed = parse_objective_page(page)

        trade, fodder, badshah, returned = parsed.steps
        self.assertEqual([span.action for span in trade.action_spans], ["trade", "talk"])
        self.assertEqual(
            (
                trade.action_spans[0].relationship,
                trade.action_spans[0].target,
                trade.action_spans[0].item_mentions,
            ),
            ("trade-to", "Task Delegator", ("Scholar Stone",)),
        )
        self.assertEqual(
            (trade.action_spans[1].relationship, trade.action_spans[1].target),
            ("talk-to", "Task Delegator"),
        )
        self.assertEqual([span.action for span in fodder.action_spans], ["fight"])
        self.assertEqual(
            (
                fodder.action_spans[0].target,
                fodder.action_spans[0].enemy_mentions,
                fodder.action_spans[0].result_items,
                fodder.action_spans[0].result_relation,
            ),
            ("Orcish Fodder", ("Orcish Fodder",), ("Orcish Axe",), "obtain-from"),
        )
        self.assertEqual(
            [span.action for span in badshah.action_spans],
            ["fight", "examine", "obtain"],
        )
        self.assertEqual(badshah.action_spans[0].target, "Badshah")
        self.assertEqual(
            (badshah.action_spans[1].target, badshah.action_spans[1].target_kind),
            ("???", "question-mark"),
        )
        self.assertEqual(badshah.action_spans[2].item_mentions, ("Silver Comet's collar",))
        self.assertEqual(
            [(span.action, span.relationship, span.target) for span in returned.action_spans],
            [("talk", "talk-to", "Cid")],
        )

    def test_typed_evidence_is_local_to_each_action_clause(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Clause Local Evidence",
            page_id=9300,
            revision_id=91,
            parent_revision_id=90,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Go to [[West Ronfaure]], then talk to [[Makarim]] in [[Zeruhn Mines]].\n"
                "*Defeat [[Mob A]] in [[East Ronfaure]] at (H-8) on map 1, then trade "
                "{{Item}}[[Stone]] to [[NPC A]] in [[West Ronfaure]] at (H-9) on map 2.\n"
                "*Use [[Switch A]], then trade {{KI}}[[Dawn Talisman]] to [[NPC A]].\n"
            ),
        )

        parsed = parse_objective_page(page)

        travel, talk = parsed.steps[0].action_spans
        self.assertEqual((travel.action, travel.target, travel.zone_mentions), (
            "travel",
            "West Ronfaure",
            ("West Ronfaure",),
        ))
        self.assertEqual((talk.action, talk.target, talk.zone_mentions), (
            "talk",
            "Makarim",
            ("Zeruhn Mines",),
        ))

        fight, trade = parsed.steps[1].action_spans
        self.assertEqual(
            (
                fight.target,
                fight.item_mentions,
                fight.zone_mentions,
                fight.map_numbers,
                fight.grid_coordinates,
            ),
            ("Mob A", (), ("East Ronfaure",), ("1",), ("H-8",)),
        )
        self.assertEqual(
            (
                trade.target,
                trade.item_mentions,
                trade.zone_mentions,
                trade.map_numbers,
                trade.grid_coordinates,
            ),
            ("NPC A", ("Stone",), ("West Ronfaure",), ("2",), ("H-9",)),
        )

        use, key_trade = parsed.steps[2].action_spans
        self.assertEqual(use.key_item_mentions, ())
        self.assertEqual(key_trade.target, "NPC A")
        self.assertEqual(key_trade.key_item_mentions, ("Dawn Talisman",))

    def test_reversed_obtain_chain_preserves_surrounding_actions(self) -> None:
        page = PageRevision(
            site="ffxiclopedia",
            api_url="https://ffxiclopedia.fandom.com/api.php",
            canonical_title="Surrounding Actions",
            page_id=9301,
            revision_id=92,
            parent_revision_id=91,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Talk to [[Cid]], then obtain an [[Orcish Axe]] by defeating "
                "[[Orcish Fodder]], then examine the ???.\n"
            ),
        )

        spans = parse_objective_page(page).steps[0].action_spans

        self.assertEqual(
            [(span.action, span.target) for span in spans],
            [("talk", "Cid"), ("fight", "Orcish Fodder"), ("examine", "???")],
        )
        self.assertEqual(spans[1].result_items, ("Orcish Axe",))
        self.assertEqual(spans[1].result_relation, "obtain-from")

    def test_leading_location_evidence_belongs_to_the_first_action_clause(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Leading Evidence",
            page_id=9302,
            revision_id=93,
            parent_revision_id=92,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*In [[East Ronfaure]] at (H-8) on map 1, defeat [[Orcish Fodder]].\n"
            ),
        )

        span = parse_objective_page(page).steps[0].action_spans[0]

        self.assertEqual(span.text_start, 0)
        self.assertEqual(span.zone_mentions, ("East Ronfaure",))
        self.assertEqual(span.grid_coordinates, ("H-8",))
        self.assertEqual(span.map_numbers, ("1",))
        self.assertTrue(span.supporting_clause.startswith("In East Ronfaure"))

    def test_interstitial_location_evidence_belongs_only_to_the_following_action(self) -> None:
        def action_spans(instruction: str) -> tuple[SourceActionSpan, ...]:
            page = PageRevision(
                site="bg",
                api_url="https://www.bg-wiki.com/api.php",
                canonical_title="Interstitial Evidence",
                page_id=9304,
                revision_id=95,
                parent_revision_id=94,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0].action_spans

        fight, talk = action_spans(
            "Defeat [[Mob A]] in [[East Ronfaure]], and in [[West Ronfaure]] "
            "at (H-8) talk to [[NPC B]]."
        )
        self.assertEqual(
            (fight.target, fight.zone_mentions, fight.grid_coordinates),
            ("Mob A", ("East Ronfaure",), ()),
        )
        self.assertEqual(
            (talk.target, talk.zone_mentions, talk.grid_coordinates),
            ("NPC B", ("West Ronfaure",), ("H-8",)),
        )

        (subordinate_fight,) = action_spans(
            "After talking to [[NPC A]] in [[East Ronfaure]], in [[West Ronfaure]] "
            "at (H-8) defeat [[Mob B]]."
        )
        self.assertEqual(
            (
                subordinate_fight.target,
                subordinate_fight.zone_mentions,
                subordinate_fight.grid_coordinates,
            ),
            ("Mob B", ("West Ronfaure",), ("H-8",)),
        )

    def test_strong_sentence_boundary_owns_following_location_and_bare_grid_leaders(self) -> None:
        for leader in (
            "At (H-8) in [[West Ronfaure]],",
            "(H-8) in [[West Ronfaure]],",
        ):
            with self.subTest(leader=leader):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Strong Boundary Evidence",
                    page_id=9305,
                    revision_id=96,
                    parent_revision_id=95,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Defeat [[Mob A]] in [[East Ronfaure]]. {leader} talk to [[NPC B]].\n"
                    ),
                )

                fight, talk = parse_objective_page(page).steps[0].action_spans

                self.assertEqual(
                    (fight.zone_mentions, fight.grid_coordinates),
                    (("East Ronfaure",), ()),
                )
                self.assertEqual(
                    (talk.zone_mentions, talk.grid_coordinates),
                    (("West Ronfaure",), ("H-8",)),
                )

    def test_complete_prior_sentence_does_not_supply_first_action_evidence(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Prior Sentence Evidence",
            page_id=9306,
            revision_id=97,
            parent_revision_id=96,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*After a cutscene in [[East Ronfaure]]. In [[West Ronfaure]] at (H-8) "
                "defeat [[Mob B]].\n"
            ),
        )

        (fight,) = parse_objective_page(page).steps[0].action_spans

        self.assertEqual(fight.zone_mentions, ("West Ronfaure",))
        self.assertEqual(fight.grid_coordinates, ("H-8",))

    def test_upon_and_once_gerund_prefixes_do_not_supply_first_action_evidence(self) -> None:
        for subordinator in ("Upon", "Once"):
            with self.subTest(subordinator=subordinator):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Gerund Prefix Evidence",
                    page_id=9307,
                    revision_id=98,
                    parent_revision_id=97,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*{subordinator} talking to [[NPC A]] in [[East Ronfaure]], in "
                        "[[West Ronfaure]] at (H-8) defeat [[Mob B]].\n"
                    ),
                )

                (fight,) = parse_objective_page(page).steps[0].action_spans

                self.assertEqual(fight.zone_mentions, ("West Ronfaure",))
                self.assertEqual(fight.grid_coordinates, ("H-8",))

    def test_delimiter_free_ambiguous_location_evidence_is_not_owned_by_either_action(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Ambiguous Interstitial Evidence",
            page_id=9308,
            revision_id=99,
            parent_revision_id=98,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Defeat [[Mob A]] in [[East Ronfaure]] in [[West Ronfaure]] at (H-8) "
                "talk to [[NPC B]].\n"
            ),
        )

        fight, talk = parse_objective_page(page).steps[0].action_spans

        self.assertEqual((fight.zone_mentions, fight.grid_coordinates), ((), ()))
        self.assertEqual((talk.zone_mentions, talk.grid_coordinates), ((), ()))

    def test_literal_question_mark_target_uses_its_following_period_as_the_boundary(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Question Mark Boundary",
            page_id=9309,
            revision_id=100,
            parent_revision_id=99,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*In [[East Ronfaure]], examine the ???. At (H-8) in [[West Ronfaure]], "
                "talk to [[NPC B]].\n"
            ),
        )

        examine, talk = parse_objective_page(page).steps[0].action_spans

        self.assertEqual(
            (examine.target, examine.zone_mentions, examine.grid_coordinates),
            ("???", ("East Ronfaure",), ()),
        )
        self.assertEqual(
            (talk.target, talk.zone_mentions, talk.grid_coordinates),
            ("NPC B", ("West Ronfaure",), ("H-8",)),
        )

    def test_link_occurrence_tracking_preserves_question_mark_spacing(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Linked Question Spacing",
            page_id=9324,
            revision_id=115,
            parent_revision_id=114,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Talk to [[Cid]]??? then examine the ???[[Object]].\n"
            ),
        )

        source_text = parse_objective_page(page).steps[0].source_text

        self.assertEqual(source_text, "Talk to Cid??? then examine the??? Object.")
        self.assertNotRegex(source_text, "[\ue000-\ue002]")

    def test_initialism_abbreviations_do_not_split_one_action_clause(self) -> None:
        for abbreviation in ("e.g.", "i.e."):
            with self.subTest(abbreviation=abbreviation):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Abbreviation Boundary",
                    page_id=9310,
                    revision_id=101,
                    parent_revision_id=100,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Trade an item, {abbreviation} Scholar Stone, to [[Cid]] in "
                        "[[East Ronfaure]], then talk to [[NPC B]] in [[West Ronfaure]].\n"
                    ),
                )

                trade, talk = parse_objective_page(page).steps[0].action_spans

                self.assertIn("Scholar Stone", trade.supporting_clause)
                self.assertNotIn("Scholar Stone", talk.supporting_clause)
                self.assertEqual(trade.zone_mentions, ("East Ronfaure",))
                self.assertEqual(talk.zone_mentions, ("West Ronfaure",))

    def test_common_single_token_abbreviations_do_not_split_action_clauses(self) -> None:
        for phrase in (
            "Lv. 75",
            "Mr. Smith",
            "Mrs. Smith",
            "Ms. Smith",
            "Dr. Shantotto",
            "No. 13",
            "etc. details",
        ):
            with self.subTest(phrase=phrase):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Common Abbreviation Boundary",
                    page_id=9311,
                    revision_id=102,
                    parent_revision_id=101,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Defeat [[Mob A]], {phrase} in [[East Ronfaure]], then talk to "
                        "[[NPC B]] in [[West Ronfaure]].\n"
                    ),
                )

                fight, talk = parse_objective_page(page).steps[0].action_spans

                self.assertEqual(fight.target, "Mob A")
                self.assertEqual(fight.zone_mentions, ("East Ronfaure",))
                self.assertEqual(talk.zone_mentions, ("West Ronfaure",))

    def test_common_abbreviations_require_compatible_continuations(self) -> None:
        for abbreviation in ("Lv.", "No.", "Mr.", "Mrs.", "Ms.", "Dr."):
            with self.subTest(abbreviation=abbreviation):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Terminal Common Abbreviation",
                    page_id=9319,
                    revision_id=110,
                    parent_revision_id=109,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Defeat [[Mob A]] in [[East Ronfaure]], {abbreviation} "
                        "A cutscene occurs in [[West Ronfaure]].\n"
                    ),
                )

                (fight,) = parse_objective_page(page).steps[0].action_spans

                self.assertEqual(fight.zone_mentions, ("East Ronfaure",))
                self.assertNotIn("cutscene", fight.supporting_clause.casefold())

    def test_etc_is_terminal_only_when_a_new_sentence_follows(self) -> None:
        terminal = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Terminal Etc Boundary",
            page_id=9315,
            revision_id=106,
            parent_revision_id=105,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Defeat [[Mob A]] in [[East Ronfaure]], etc. A cutscene occurs in "
                "[[West Ronfaure]].\n"
            ),
        )
        (fight,) = parse_objective_page(terminal).steps[0].action_spans
        self.assertEqual(fight.zone_mentions, ("East Ronfaure",))
        self.assertNotIn("cutscene", fight.supporting_clause.casefold())

        internal = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Internal Etc Boundary",
            page_id=9316,
            revision_id=107,
            parent_revision_id=106,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Trade an item, etc. to [[Cid]] in [[East Ronfaure]], then talk to "
                "[[NPC B]] in [[West Ronfaure]].\n"
            ),
        )
        trade, talk = parse_objective_page(internal).steps[0].action_spans
        self.assertIn("etc. to Cid", trade.supporting_clause)
        self.assertEqual(trade.zone_mentions, ("East Ronfaure",))
        self.assertEqual(talk.zone_mentions, ("West Ronfaure",))

    def test_lowercase_sentence_after_contextual_abbreviation_does_not_leak(self) -> None:
        for abbreviation in ("etc.", "N.M."):
            for following_context in ("a cutscene occurs", "something happens"):
                with self.subTest(
                    abbreviation=abbreviation,
                    following_context=following_context,
                ):
                    page = PageRevision(
                        site="bg",
                        api_url="https://www.bg-wiki.com/api.php",
                        canonical_title="Lowercase Abbreviation Boundary",
                        page_id=9322,
                        revision_id=113,
                        parent_revision_id=112,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=(
                            "{{Quest Header}}\n==Walkthrough==\n"
                            f"*Defeat [[Mob A]] in [[East Ronfaure]], {abbreviation} "
                            f"{following_context} in [[West Ronfaure]].\n"
                        ),
                    )

                    (fight,) = parse_objective_page(page).steps[0].action_spans

                    self.assertEqual(fight.zone_mentions, ("East Ronfaure",))
                    self.assertNotIn("West Ronfaure", fight.supporting_clause)

    def test_multi_initialism_is_terminal_only_before_new_sentence_context(self) -> None:
        def spans(instruction: str) -> tuple[SourceActionSpan, ...]:
            page = PageRevision(
                site="bg",
                api_url="https://www.bg-wiki.com/api.php",
                canonical_title="Multi Initialism Boundary",
                page_id=9318,
                revision_id=109,
                parent_revision_id=108,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0].action_spans

        (terminal,) = spans(
            "Defeat [[Mob A]] in [[East Ronfaure]] as an N.M. A cutscene occurs in "
            "[[West Ronfaure]]."
        )
        self.assertEqual(terminal.zone_mentions, ("East Ronfaure",))
        self.assertNotIn("cutscene", terminal.supporting_clause.casefold())

        fight, talk = spans(
            "Defeat [[Mob A]] in [[East Ronfaure]], N.M. At (H-8) in "
            "[[West Ronfaure]], talk to [[NPC B]]."
        )
        self.assertEqual((fight.zone_mentions, fight.grid_coordinates), (("East Ronfaure",), ()))
        self.assertEqual(
            (talk.zone_mentions, talk.grid_coordinates),
            (("West Ronfaure",), ("H-8",)),
        )

        for initialism in ("e.g.", "i.e.", "U.S.", "N.M."):
            with self.subTest(initialism=initialism):
                internal_fight, internal_talk = spans(
                    f"Defeat [[Mob A]], {initialism} encounter details in "
                    "[[East Ronfaure]], then talk to [[NPC B]] in [[West Ronfaure]]."
                )
                self.assertIn("encounter details", internal_fight.supporting_clause)
                self.assertEqual(internal_fight.zone_mentions, ("East Ronfaure",))
                self.assertEqual(internal_talk.zone_mentions, ("West Ronfaure",))

        continuing_fight, continuing_talk = spans(
            "Defeat [[Mob A]] as an N.M. in [[East Ronfaure]], then talk to "
            "[[NPC B]] in [[West Ronfaure]]."
        )
        self.assertEqual(continuing_fight.zone_mentions, ("East Ronfaure",))
        self.assertEqual(continuing_talk.zone_mentions, ("West Ronfaure",))

    def test_multi_initialism_before_exact_linked_target_stays_in_action_clause(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Linked Initialism Target",
            page_id=9321,
            revision_id=112,
            parent_revision_id=111,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Defeat the N.M. [[Bugallug]] in [[Oldton Movalpolos]], then talk to "
                "[[Cid]] in [[Metalworks]].\n"
            ),
        )

        fight, talk = parse_objective_page(page).steps[0].action_spans

        with self.subTest(action="fight"):
            self.assertEqual(
                (fight.target, fight.enemy_mentions, fight.zone_mentions),
                ("Bugallug", ("Bugallug",), ("Oldton Movalpolos",)),
            )
        with self.subTest(action="talk"):
            self.assertEqual(
                (talk.target, talk.npc_mentions, talk.zone_mentions),
                ("Cid", ("Cid",), ("Metalworks",)),
            )

    def test_example_initialism_before_exact_link_stays_in_action_clause(self) -> None:
        for initialism in ("e.g.", "i.e."):
            with self.subTest(initialism=initialism):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Linked Example Target",
                    page_id=9323,
                    revision_id=114,
                    parent_revision_id=113,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Defeat an enemy, {initialism} [[Mob A]] in [[East Ronfaure]], "
                        "then talk to [[NPC B]] in [[West Ronfaure]].\n"
                    ),
                )

                fight, talk = parse_objective_page(page).steps[0].action_spans

                with self.subTest(initialism=initialism, action="fight"):
                    self.assertEqual(
                        (fight.target, fight.enemy_mentions, fight.zone_mentions),
                        ("Mob A", ("Mob A",), ("East Ronfaure",)),
                    )
                with self.subTest(initialism=initialism, action="talk"):
                    self.assertEqual(
                        (talk.target, talk.npc_mentions, talk.zone_mentions),
                        ("NPC B", ("NPC B",), ("West Ronfaure",)),
                    )

    def test_exact_clause_link_refines_decorated_target_without_cross_clause_borrowing(self) -> None:
        def spans(instruction: str) -> tuple[SourceActionSpan, ...]:
            page = PageRevision(
                site="bg",
                api_url="https://www.bg-wiki.com/api.php",
                canonical_title="Linked Target Refinement",
                page_id=9317,
                revision_id=108,
                parent_revision_id=107,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0].action_spans

        (fight,) = spans(
            "Defeat the Lv. 75 [[Mob A]] in [[East Ronfaure]]."
        )
        self.assertEqual((fight.target, fight.enemy_mentions), ("Mob A", ("Mob A",)))

        (ambiguous,) = spans(
            "Defeat [[Mob A]] and [[Mob B]] in [[East Ronfaure]]."
        )
        self.assertEqual(ambiguous.target, "")
        self.assertEqual(ambiguous.enemy_mentions, ("Mob A", "Mob B"))

        unlinked_fight, talk = spans(
            "Defeat the Lv. 75 foe in [[East Ronfaure]], then talk to [[NPC B]] in "
            "[[West Ronfaure]]."
        )
        self.assertEqual(unlinked_fight.target, "Lv. 75 foe")
        self.assertNotIn("NPC B", unlinked_fight.enemy_mentions)
        self.assertEqual(talk.target, "NPC B")

        repeated_fight, repeated_talk = spans(
            "Defeat the Lv. 75 Mob A in [[East Ronfaure]], then talk to [[Mob A]] in "
            "[[West Ronfaure]]."
        )
        with self.subTest(action="unlinked-repeated-fight"):
            self.assertEqual(
                (repeated_fight.target, repeated_fight.enemy_mentions),
                ("Lv. 75 Mob A", ("Lv. 75 Mob A",)),
            )
        with self.subTest(action="linked-repeated-talk"):
            self.assertEqual(repeated_talk.target, "Mob A")

    def test_unlinked_sparkling_object_normalization_remains_consistent(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Unlinked Sparkling Object",
            page_id=9320,
            revision_id=111,
            parent_revision_id=110,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Examine the sparkling object in [[East Ronfaure]].\n"
            ),
        )

        (examine,) = parse_objective_page(page).steps[0].action_spans

        self.assertEqual((examine.target, examine.object_mentions), ("object", ("object",)))

    def test_action_evidence_stops_at_first_terminal_and_skips_intermediate_sentences(self) -> None:
        single = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Trailing Context Boundary",
            page_id=9312,
            revision_id=103,
            parent_revision_id=102,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Defeat [[Mob A]] in [[East Ronfaure]]. A cutscene occurs in "
                "[[West Ronfaure]].\n"
            ),
        )
        (fight,) = parse_objective_page(single).steps[0].action_spans
        self.assertEqual(fight.zone_mentions, ("East Ronfaure",))
        self.assertNotIn("cutscene", fight.supporting_clause.casefold())

        paired = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Intermediate Context Boundary",
            page_id=9313,
            revision_id=104,
            parent_revision_id=103,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Defeat [[Mob A]] in [[East Ronfaure]]. A cutscene occurs in "
                "[[West Ronfaure]]. At (H-8) in [[North Gustaberg]], talk to [[NPC B]].\n"
            ),
        )
        fight, talk = parse_objective_page(paired).steps[0].action_spans
        self.assertEqual((fight.zone_mentions, fight.grid_coordinates), (("East Ronfaure",), ()))
        self.assertEqual(
            (talk.zone_mentions, talk.grid_coordinates),
            (("North Gustaberg",), ("H-8",)),
        )
        self.assertTrue(all("West Ronfaure" not in span.zone_mentions for span in (fight, talk)))

    def test_punctuated_linked_target_identities_remain_whole(self) -> None:
        cases = (
            ("Talk to [[Dr. Shantotto]] in [[East Ronfaure]].", "talk", "Dr. Shantotto"),
            ("Defeat [[Lamia No.13]] in [[East Ronfaure]].", "fight", "Lamia No.13"),
            ("Defeat [[Prototype 1.5]] in [[East Ronfaure]].", "fight", "Prototype 1.5"),
        )
        for instruction, action, target in cases:
            with self.subTest(target=target):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Punctuated Identity",
                    page_id=9314,
                    revision_id=105,
                    parent_revision_id=104,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                )

                (span,) = parse_objective_page(page).steps[0].action_spans

                self.assertEqual((span.action, span.target), (action, target))
                self.assertIn(target, (*span.npc_mentions, *span.enemy_mentions))

    def test_only_explicit_obtain_from_syntax_collapses_actions(self) -> None:
        def spans(instruction: str) -> tuple[SourceActionSpan, ...]:
            page = PageRevision(
                site="ffxiclopedia",
                api_url="https://ffxiclopedia.fandom.com/api.php",
                canonical_title="Explicit Obtain Relation",
                page_id=9303,
                revision_id=94,
                parent_revision_id=93,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0].action_spans

        obtain_then_fight = spans(
            "Obtain a [[Bronze Key]], then defeat the [[Gate Guardian]]."
        )
        self.assertEqual(
            [(span.action, span.target) for span in obtain_then_fight],
            [("obtain", "Bronze Key"), ("fight", "Gate Guardian")],
        )
        self.assertTrue(all(not span.result_relation for span in obtain_then_fight))

        fight_then_obtain = spans(
            "Defeat the [[Gate Guardian]], then obtain a [[Bronze Key]] from a chest."
        )
        self.assertEqual(
            [(span.action, span.target) for span in fight_then_obtain],
            [("fight", "Gate Guardian"), ("obtain", "Bronze Key")],
        )
        self.assertTrue(all(not span.result_relation for span in fight_then_obtain))

    def test_typed_mentions_keep_prose_zones_unlinked_objects_and_question_marks(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Typed Location Mission",
            page_id=9201,
            revision_id=82,
            parent_revision_id=81,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Mission|name=Typed Location Mission}}\n==Walkthrough==\n"
                "*Go to [[Sauromugue Champaign (S)]] and talk to [[Mham Lahrih]] at (K-9).\n"
                "*Touch the Disturbed Dirt at (K-9).\n"
                "*Examine the sparkling ??? in Sea Serpent Grotto at (J-12).\n"
                "*Click the Abandoned Mineshaft again to enter the battlefield.\n"
            ),
        )

        parsed = parse_objective_page(page)

        journey, dirt, marker, battlefield = parsed.steps
        self.assertEqual([span.action for span in journey.action_spans], ["travel", "talk"])
        self.assertEqual(journey.action_spans[0].zone_mentions, ("Sauromugue Champaign [S]",))
        self.assertEqual(journey.action_spans[0].temporal_zone_variant, "past")
        self.assertEqual(journey.action_spans[1].npc_mentions, ("Mham Lahrih",))
        self.assertEqual(dirt.action_spans[0].target, "Disturbed Dirt")
        self.assertEqual(dirt.action_spans[0].object_mentions, ("Disturbed Dirt",))
        self.assertEqual(dirt.action_spans[0].grid_coordinates, ("K-9",))
        self.assertEqual(marker.action_spans[0].target_kind, "question-mark")
        self.assertEqual(marker.action_spans[0].zone_mentions, ("Sea Serpent Grotto",))
        self.assertEqual(marker.action_spans[0].grid_coordinates, ("J-12",))
        self.assertEqual(
            (
                battlefield.action_spans[0].action,
                battlefield.action_spans[0].target,
                battlefield.action_spans[0].target_kind,
            ),
            ("examine", "Abandoned Mineshaft", "object"),
        )
        self.assertEqual(
            [
                (span.action, span.relationship, span.target, span.target_kind)
                for span in battlefield.action_spans
            ],
            [
                ("examine", "examine-object", "Abandoned Mineshaft", "object"),
                ("travel", "enter-through", "battlefield", "entrance"),
            ],
        )

    def test_material_protect_touch_and_key_item_warning_are_typed_actions(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Material Instructions",
            page_id=9202,
            revision_id=83,
            parent_revision_id=82,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Protect the Elvaan and Hume NPCs.\n"
                "*Touch the 6 Pips.\n"
                "*Warning: leaving the battlefield loses the required {{KI}}[[Dawn Talisman]].\n"
            ),
        )

        parsed = parse_objective_page(page)

        self.assertEqual([span.action for span in parsed.steps[0].action_spans], ["protect"])
        self.assertEqual(parsed.steps[0].action_spans[0].target, "Elvaan and Hume NPCs")
        self.assertEqual([span.action for span in parsed.steps[1].action_spans], ["examine"])
        self.assertEqual(parsed.steps[1].action_spans[0].target, "6 Pips")
        self.assertEqual([span.action for span in parsed.steps[2].action_spans], ["warning"])
        self.assertEqual(parsed.steps[2].action_spans[0].item_mentions, ("Dawn Talisman",))
        self.assertTrue(all(step.action_spans[0].material for step in parsed.steps))


class MatchingTests(unittest.TestCase):
    def test_campaign_log_rows_mirror_exact_crystal_war_quest_guides_only(self) -> None:
        campaign = NativeObjective("mission", "Campaign", 14, "Fires of Discontent", "missions.dat", 0, 14)
        voidwatch_campaign = NativeObjective(
            "mission", "Campaign", 84, "VW Op. #126: Qufim Incursion", "missions.dat", 1, 84
        )
        quest = NativeObjective("quest", "crystal_war", 13, "Fires of Discontent", "quests.dat", 0, 13)
        page = ParsedObjective(
            site="ffxiclopedia",
            page_id=5000,
            revision_id=1,
            canonical_title="Fires of Discontent",
            kind="quest",
            objective_name="Fires of Discontent",
            categories=("Quests", "Crystal War Quests"),
        )
        unrelated = ParsedObjective(
            site="ffxiclopedia",
            page_id=5001,
            revision_id=1,
            canonical_title="The Swarm",
            kind="quest",
            objective_name="The Swarm",
            categories=("Side Quests",),
        )
        unrelated_campaign = NativeObjective("mission", "Campaign", 32, "The Swarm", "missions.dat", 1, 32)
        voidwatch_page = ParsedObjective(
            site="ffxiclopedia",
            page_id=5002,
            revision_id=1,
            canonical_title="VW Op. No. 126: Qufim Incursion",
            kind="quest",
            objective_name="VW Op. No. 126: Qufim Incursion",
            categories=("Crystal War Quests", "Voidwatch Quests"),
        )

        report = match_objective_pages(
            [campaign, voidwatch_campaign, quest, unrelated_campaign],
            [page, unrelated, voidwatch_page],
        )

        self.assertEqual(
            {match.native_key for match in report.matches},
            {"mission:Campaign:14", "mission:Campaign:84", "quest:crystal_war:13"},
        )
        self.assertNotIn("mission:Campaign:32", {match.native_key for match in report.matches})

    def test_kind_and_context_disambiguation_suffixes_match_exactly(self) -> None:
        windurst = NativeObjective("quest", "windurst", 77, "Wild Card", "quests.dat", 0, 77)
        wild_card = ParsedObjective(
            site="ffxiclopedia",
            page_id=8315,
            revision_id=1,
            canonical_title="Wild Card (Quest)",
            kind="quest",
            objective_name="Wild Card (Quest)",
            categories=("Windurst Quests",),
        )
        eco_natives = [
            NativeObjective("quest", context, native_id, "Eco-Warrior", "quests.dat", 0, native_id)
            for context, native_id in (("bastok", 65), ("sandoria", 97), ("windurst", 84))
        ]
        eco_bastok = ParsedObjective(
            site="ffxiclopedia",
            page_id=5745,
            revision_id=1,
            canonical_title="Eco-Warrior (Bastok)",
            kind="quest",
            objective_name="Eco-Warrior (Bastok)",
            categories=("Bastok Quests",),
        )

        wild_report = match_objective_pages([windurst], [wild_card])
        eco_report = match_objective_pages(eco_natives, [eco_bastok])

        self.assertEqual(wild_report.matches[0].native_key, "quest:windurst:77")
        self.assertEqual(eco_report.matches[0].native_key, "quest:bastok:65")

    def test_literal_title_wins_when_lossy_normalization_collides(self) -> None:
        first = NativeObjective(
            kind="quest",
            context="windurst",
            native_id=32,
            title="Curses, Foiled Again!",
            source_dat="ROM/176/62.DAT",
            record_offset=0,
        )
        second = NativeObjective(
            kind="quest",
            context="windurst",
            native_id=33,
            title="Curses, Foiled...Again!?",
            source_dat="ROM/176/62.DAT",
            record_offset=0x280,
        )
        page = ParsedObjective(
            site="ffxiclopedia",
            page_id=8412,
            revision_id=99,
            canonical_title="Curses, Foiled...Again!?",
            kind="quest",
            objective_name="Curses, Foiled...Again!?",
        )

        report = match_objective_pages([first, second], [page])

        self.assertEqual([match.native_key for match in report.matches], ["quest:windurst:33"])
        self.assertEqual(report.ambiguous_pages, {})

    def test_reviewed_mapping_seeds_stages_and_only_exact_named_npc_targets(self) -> None:
        path = Path(__file__).parents[1] / "data" / "mission-quest-guides" / "reviewed-overrides.json"
        overrides = json.loads(path.read_text(encoding="utf-8"))

        self.assertEqual(overrides["page_matches"]["mission:Bastok:2"]["bg"]["page_id"], 12562)
        self.assertEqual(
            set(overrides["automatic_stage_links"]["mission:Bastok:2"]),
            {"obtain-blue-tester", "charge-blue-tester", "return-red-tester"},
        )
        targets = overrides["target_overrides"]
        makarim = targets["mission:Bastok:1:step-007"]
        self.assertEqual(
            makarim["reference"],
            {
                "zone": 172,
                "zone_name": "Zeruhn Mines",
                "name": "Makarim",
                "kind": "npc",
            },
        )
        self.assertEqual(set(makarim["source_revisions"]), {"bg", "ffxiclopedia"})
        self.assertGreater(len(targets), 100)
        self.assertTrue(
            all(target["reference"]["name"] != "???" for target in targets.values())
        )
        self.assertTrue(
            all(target["reference"]["name"] != "Trodden Snow" for target in targets.values())
        )

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
    def test_geological_survey_aligns_material_steps_without_whole_step_grid_conflict(self) -> None:
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
        self.assertEqual(cid.comparison, "corroborated")
        self.assertNotIn("grid_coordinates", cid.conflicting_fields)
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

    def test_candidate_reconciliation_keeps_shared_and_source_only_grids(self) -> None:
        def page(site: str, page_id: int, coordinates: tuple[str, ...]) -> ParsedObjective:
            span = SourceActionSpan(
                source_step_order=1,
                order=1,
                text_start=0,
                text_end=38,
                supporting_clause="Touch the Disturbed Dirt at H-8/H-9.",
                action="examine",
                verb="touch",
                relationship="examine-object",
                target="Disturbed Dirt",
                target_kind="object",
                object_mentions=("Disturbed Dirt",),
                zone_mentions=("East Ronfaure",),
                grid_coordinates=coordinates,
            )
            return ParsedObjective(
                site=site,
                page_id=page_id,
                revision_id=page_id,
                canonical_title="Candidate Grids",
                kind="quest",
                objective_name="Candidate Grids",
                steps=(
                    SourceStep(
                        1,
                        "*",
                        1,
                        span.supporting_clause,
                        span.supporting_clause,
                        "examine",
                        linked_entities=("Disturbed Dirt",),
                        zone_candidates=("East Ronfaure",),
                        grid_coordinates=coordinates,
                        action_spans=(span,),
                    ),
                ),
            )

        reconciled = reconcile_objectives(
            "quest:other_areas:7",
            page("bg", 101, ("H-8",)),
            page("ffxiclopedia", 202, ("H-8", "H-9")),
        )

        step = reconciled.steps[0]
        grid_candidates = {
            candidate.value: (candidate.comparison, candidate.sources)
            for candidate in step.claims[0].candidates
            if candidate.field == "grid"
        }
        self.assertEqual(
            grid_candidates,
            {
                "H-8": ("corroborated", ("bg", "ffxiclopedia")),
                "H-9": ("single-source", ("ffxiclopedia",)),
            },
        )
        self.assertEqual(step.comparison, "corroborated")
        self.assertNotIn("grid_coordinates", step.conflicting_fields)

    def test_unpaired_dual_source_step_keeps_score_and_reason(self) -> None:
        common = SourceActionSpan(
            source_step_order=1,
            order=1,
            text_start=0,
            text_end=12,
            supporting_clause="Talk to Cid.",
            action="talk",
            verb="talk",
            relationship="talk-to",
            target="Cid",
            target_kind="npc",
            npc_mentions=("Cid",),
        )
        extra = SourceActionSpan(
            source_step_order=2,
            order=1,
            text_start=0,
            text_end=22,
            supporting_clause="Touch the Left Beacon.",
            action="examine",
            verb="touch",
            relationship="examine-object",
            target="Left Beacon",
            target_kind="object",
            object_mentions=("Left Beacon",),
        )
        bg = ParsedObjective(
            site="bg",
            page_id=301,
            revision_id=301,
            canonical_title="Unpaired",
            kind="quest",
            objective_name="Unpaired",
            steps=(
                SourceStep(1, "*", 1, "Talk to Cid.", "Talk to Cid.", "talk", action_spans=(common,)),
                SourceStep(2, "*", 1, "Touch the Left Beacon.", "Touch the Left Beacon.", "examine", action_spans=(extra,)),
            ),
        )
        ffxi = ParsedObjective(
            site="ffxiclopedia",
            page_id=302,
            revision_id=302,
            canonical_title="Unpaired",
            kind="quest",
            objective_name="Unpaired",
            steps=(
                SourceStep(1, "*", 1, "Talk to Cid.", "Talk to Cid.", "talk", action_spans=(common,)),
            ),
        )

        reconciled = reconcile_objectives("quest:bastok:9", bg, ffxi)

        unpaired = next(step for step in reconciled.steps if step.source_orders == (2, 0))
        self.assertEqual(unpaired.alignment_score, 0)
        self.assertEqual(unpaired.alignment_reason, "unpaired-bg")
        self.assertEqual(unpaired.unpaired_reason, "no-compatible-ffxiclopedia-step")

    def test_fight_to_obtain_word_order_variants_reconcile_as_one_chain(self) -> None:
        pages = []
        for site, page_id, sentence in (
            ("bg", 801, "Defeat [[Orcish Fodder]] to obtain an [[Orcish Axe]]."),
            (
                "ffxiclopedia",
                802,
                "Obtain an [[Orcish Axe]] by defeating [[Orcish Fodder]].",
            ),
        ):
            pages.append(
                parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title="Chain Order",
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{sentence}\n",
                    )
                )
            )

        reconciled = reconcile_objectives("quest:other_areas:80", pages[0], pages[1])

        self.assertEqual(len(reconciled.steps), 1)
        self.assertEqual(len(reconciled.steps[0].claims), 1)
        claim = reconciled.steps[0].claims[0]
        self.assertEqual((claim.action, claim.relationship), ("fight", "defeat-to-obtain"))
        self.assertEqual(claim.comparison, "corroborated")
        self.assertNotIn("action", reconciled.steps[0].conflicting_fields)

    def test_reconciliation_conflicts_only_compare_aligned_action_claims(self) -> None:
        def page(site: str, page_id: int, second_target: str) -> ParsedObjective:
            return parse_objective_page(
                PageRevision(
                    site=site,
                    api_url="https://example.invalid/api.php",
                    canonical_title="Two Talks",
                    page_id=page_id,
                    revision_id=page_id,
                    parent_revision_id=page_id - 1,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Talk to [[Alpha]], then talk to [[{second_target}]].\n"
                    ),
                )
            )

        identical = reconcile_objectives(
            "quest:other_areas:81",
            page("bg", 811, "Beta"),
            page("ffxiclopedia", 812, "Beta"),
        )
        self.assertEqual(identical.steps[0].comparison, "corroborated")
        self.assertEqual(
            [(claim.target, claim.comparison) for claim in identical.steps[0].claims],
            [("Alpha", "corroborated"), ("Beta", "corroborated")],
        )
        self.assertNotIn("target_identity", identical.steps[0].conflicting_fields)

        disagreement = reconcile_objectives(
            "quest:other_areas:82",
            page("bg", 821, "Beta"),
            page("ffxiclopedia", 822, "Gamma"),
        )
        self.assertEqual(
            [(claim.target, claim.comparison) for claim in disagreement.steps[0].claims],
            [("Alpha", "corroborated"), ("", "conflict")],
        )
        self.assertEqual(
            [
                (candidate.value, candidate.comparison)
                for candidate in disagreement.steps[0].claims[0].candidates
                if candidate.field == "target"
            ],
            [("Alpha", "corroborated")],
        )


class ObjectiveDestinationTests(unittest.TestCase):
    @staticmethod
    def _source_page(site: str, page_id: int, revision_id: int) -> ParsedObjective:
        span = SourceActionSpan(
            source_step_order=1,
            order=1,
            text_start=0,
            text_end=65,
            supporting_clause="Defeat Orcish Fodder in East Ronfaure to obtain an Orcish Axe.",
            action="fight",
            verb="defeat",
            relationship="defeat-to-obtain",
            target="Orcish Fodder",
            target_kind="enemy",
            enemy_mentions=("Orcish Fodder",),
            item_mentions=("Orcish Axe",),
            zone_mentions=("East Ronfaure",),
            result_items=("Orcish Axe",),
            result_relation="obtain-from",
        )
        return ParsedObjective(
            site=site,
            page_id=page_id,
            revision_id=revision_id,
            canonical_title="Smash the Orcish Scouts",
            kind="mission",
            objective_name="Smash the Orcish Scouts",
            steps=(
                SourceStep(
                    1,
                    "*",
                    1,
                    span.supporting_clause,
                    span.supporting_clause,
                    "fight",
                    linked_entities=("Orcish Fodder", "East Ronfaure", "Orcish Axe"),
                    zone_candidates=("East Ronfaure",),
                    items=("Orcish Axe",),
                    action_spans=(span,),
                ),
            ),
        )

    @classmethod
    def _fixture(
        cls,
        kind: str,
    ) -> tuple[NativeObjective, ParsedObjective, ParsedObjective, object, dict]:
        context = "San d'Oria" if kind == "mission" else "sandoria"
        native = NativeObjective(kind, context, 1, "Smash the Orcish Scouts", "objectives.dat", 0)
        bg = cls._source_page("bg", 401, 4001)
        ffxi = cls._source_page("ffxiclopedia", 402, 4002)
        bg = ParsedObjective(**{**{field: getattr(bg, field) for field in bg.__dataclass_fields__}, "kind": kind})
        ffxi = ParsedObjective(**{**{field: getattr(ffxi, field) for field in ffxi.__dataclass_fields__}, "kind": kind})
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        override = {
            "id": "orcish-fodder-east-ronfaure",
            "source_revisions": {"bg": 4001, "ffxiclopedia": 4002},
            "source_step_ids": [f"{native.key}:step-001"],
            "source_claim_ids": [f"{native.key}:step-001:claim-01"],
            "action": "obtain",
            "items": ["Orcish Axe"],
            "enemies": ["Orcish Fodder"],
            "destination_id": "camp:101:orcish-fodder:fixture-hash",
            "zone": 101,
            "zone_name": "East Ronfaure",
            "label": "Orcish Fodder camp in East Ronfaure",
            "reference": {"name": "Orcish Fodder", "kind": "enemy"},
            "arrival_instruction": "Defeat Orcish Fodder until you obtain an Orcish Axe.",
        }
        overrides = {"objective_destination_overrides": {native.key: [override]}}
        return native, bg, ffxi, reconciled, overrides

    @staticmethod
    def _resolve(
        native: NativeObjective,
        bg: ParsedObjective,
        ffxi: ParsedObjective,
        reconciled: object,
        overrides: dict,
    ) -> tuple[ReviewedObjectiveDestination, ...]:
        return resolve_reviewed_objective_destinations(
            native,
            reconciled,
            bg,
            ffxi,
            overrides,
            (
                {
                    "zone": 101,
                    "name": "Orcish Fodder",
                    "kind": "enemy",
                    "x": 123.0,
                    "z": 45.0,
                    "y": -2.0,
                    "confidence": "untested",
                },
            ),
            {101: "East Ronfaure"},
        )

    def test_missions_and_quests_use_the_same_immutable_destination_type(self) -> None:
        results = []
        for kind in ("mission", "quest"):
            fixture = self._fixture(kind)
            rows = self._resolve(*fixture)
            self.assertEqual(len(rows), 1)
            self.assertIsInstance(rows[0], ReviewedObjectiveDestination)
            self.assertTrue(rows[0].stable_id.startswith(fixture[0].key + ":destination:"))
            self.assertEqual(rows[0].source_step_ids, (f"{fixture[0].key}:step-001",))
            self.assertEqual(rows[0].source_claim_ids, (f"{fixture[0].key}:step-001:claim-01",))
            self.assertEqual(rows[0].destination_id, "camp:101:orcish-fodder:fixture-hash")
            self.assertEqual(rows[0].target_point, (123.0, 45.0, -2.0))
            self.assertEqual(
                rows[0].source_revisions,
                (("bg", 4001), ("ffxiclopedia", 4002)),
            )
            self.assertEqual(rows[0].eligibility, "catalogue")
            results.append(type(rows[0]))
        self.assertIs(results[0], results[1])

    def test_quest_destination_emits_only_the_shared_runtime_field(self) -> None:
        native, bg, ffxi, _reconciled, overrides = self._fixture("quest")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                (native,),
                (bg, ffxi),
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(
                    {
                        "zone": 101,
                        "name": "Orcish Fodder",
                        "kind": "enemy",
                        "x": 123.0,
                        "z": 45.0,
                        "y": -2.0,
                    },
                ),
                navigation_zone_names={101: "East Ronfaure"},
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_quest_sandoria.lua"
            ).read_text(encoding="utf-8")
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))

        self.assertIn("objective_destinations = {", reconcile)
        self.assertNotIn("mission_destinations = {", reconcile)
        self.assertIn('["bg"] = 4001', reconcile)
        self.assertIn('["ffxiclopedia"] = 4002', reconcile)
        self.assertIn(f'{native.key}:step-001:claim-01', reconcile)
        self.assertEqual(review["objective_destinations"][0]["native_key"], native.key)
        self.assertEqual(
            review["objective_destinations"][0]["source_claim_ids"],
            [f"{native.key}:step-001:claim-01"],
        )
        self.assertEqual(
            review["objective_destinations"][0]["source_revisions"],
            {"bg": 4001, "ffxiclopedia": 4002},
        )
        self.assertNotIn("mission_destinations", review)

    def test_destination_overrides_reject_unknown_steps_and_stale_revisions(self) -> None:
        native, bg, ffxi, reconciled, overrides = self._fixture("mission")
        row = overrides["objective_destination_overrides"][native.key][0]
        row["source_step_ids"] = [f"{native.key}:step-999"]
        with self.assertRaises(ObjectiveDestinationError):
            self._resolve(native, bg, ffxi, reconciled, overrides)

        native, bg, ffxi, reconciled, overrides = self._fixture("mission")
        overrides["objective_destination_overrides"][native.key][0]["source_revisions"]["bg"] = 3999
        with self.assertRaises(ObjectiveDestinationError):
            self._resolve(native, bg, ffxi, reconciled, overrides)

    def test_destination_requires_every_pinned_source_revision_to_be_present(self) -> None:
        native, bg, _ffxi, _reconciled, overrides = self._fixture("mission")
        bg_only = reconcile_objectives(native.key, bg, None)

        with self.assertRaises(ObjectiveDestinationError):
            resolve_reviewed_objective_destinations(
                native,
                bg_only,
                bg,
                None,
                overrides,
                (
                    {
                        "zone": 101,
                        "name": "Orcish Fodder",
                        "kind": "enemy",
                        "x": 123.0,
                        "z": 45.0,
                        "y": -2.0,
                    },
                ),
                {101: "East Ronfaure"},
            )

    def test_destination_rejects_a_point_that_disagrees_with_its_exact_reference(self) -> None:
        native, bg, ffxi, reconciled, overrides = self._fixture("mission")
        overrides["objective_destination_overrides"][native.key][0]["target_point"] = [
            999.0,
            999.0,
            999.0,
        ]

        with self.assertRaises(ObjectiveDestinationError):
            self._resolve(native, bg, ffxi, reconciled, overrides)

    def test_destination_requires_complete_finite_catalogue_coordinates(self) -> None:
        native, bg, ffxi, reconciled, overrides = self._fixture("mission")
        invalid_points = (
            {"zone": 101, "name": "Orcish Fodder", "kind": "enemy", "z": 45.0, "y": -2.0},
            {"zone": 101, "name": "Orcish Fodder", "kind": "enemy", "x": 123.0, "y": -2.0},
            {"zone": 101, "name": "Orcish Fodder", "kind": "enemy", "x": 123.0, "z": 45.0},
            {
                "zone": 101,
                "name": "Orcish Fodder",
                "kind": "enemy",
                "x": float("nan"),
                "z": 45.0,
                "y": -2.0,
            },
            {
                "zone": 101,
                "name": "Orcish Fodder",
                "kind": "enemy",
                "x": 123.0,
                "z": float("inf"),
                "y": -2.0,
            },
        )
        for point in invalid_points:
            with self.subTest(point=point), self.assertRaises(ObjectiveDestinationError):
                resolve_reviewed_objective_destinations(
                    native,
                    reconciled,
                    bg,
                    ffxi,
                    overrides,
                    (point,),
                    {101: "East Ronfaure"},
                )

    def test_destination_conflict_isolated_to_the_selected_claim(self) -> None:
        native = NativeObjective("quest", "other_areas", 83, "Claim Isolation", "quests.dat", 0)

        def page(site: str, page_id: int, second_target: str) -> ParsedObjective:
            return parse_objective_page(
                PageRevision(
                    site=site,
                    api_url="https://example.invalid/api.php",
                    canonical_title="Claim Isolation",
                    page_id=page_id,
                    revision_id=page_id,
                    parent_revision_id=page_id - 1,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Talk to [[Alpha]] in [[East Ronfaure]], then talk to "
                        f"[[{second_target}]] in [[West Ronfaure]].\n"
                    ),
                )
            )

        bg = page("bg", 831, "Beta")
        ffxi = page("ffxiclopedia", 832, "Gamma")
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        step_id = f"{native.key}:step-001"
        override = {
            "id": "alpha-east-ronfaure",
            "source_revisions": {"bg": 831, "ffxiclopedia": 832},
            "source_step_ids": [step_id],
            "source_claim_ids": [f"{step_id}:claim-01"],
            "action": "talk",
            "items": [],
            "enemies": [],
            "destination_id": "npc:101:alpha:fixture",
            "zone": 101,
            "zone_name": "East Ronfaure",
            "label": "Alpha in East Ronfaure",
            "reference": {"name": "Alpha", "kind": "npc"},
            "arrival_instruction": "Talk to Alpha.",
        }
        overrides = {"objective_destination_overrides": {native.key: [override]}}
        points = (
            {"zone": 101, "name": "Alpha", "kind": "npc", "x": 1.0, "z": 2.0, "y": 3.0},
        )

        rows = resolve_reviewed_objective_destinations(
            native, reconciled, bg, ffxi, overrides, points, {101: "East Ronfaure"}
        )

        self.assertEqual(rows[0].source_claim_ids, (f"{step_id}:claim-01",))
        override["source_claim_ids"] = [f"{step_id}:claim-02"]
        with self.assertRaises(ObjectiveDestinationError):
            resolve_reviewed_objective_destinations(
                native, reconciled, bg, ffxi, overrides, points, {101: "East Ronfaure"}
            )

    def test_destination_items_and_enemies_must_belong_to_the_selected_claim(self) -> None:
        native = NativeObjective("quest", "other_areas", 84, "Claim Local Destination", "quests.dat", 0)

        def page(site: str, page_id: int) -> ParsedObjective:
            return parse_objective_page(
                PageRevision(
                    site=site,
                    api_url="https://example.invalid/api.php",
                    canonical_title="Claim Local Destination",
                    page_id=page_id,
                    revision_id=page_id,
                    parent_revision_id=page_id - 1,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        "*Defeat [[Orcish Fodder]] in [[East Ronfaure]], then trade "
                        "an {{Item}}[[Scholar Stone]] to [[Cid]] in [[West Ronfaure]].\n"
                    ),
                )
            )

        bg = page("bg", 841)
        ffxi = page("ffxiclopedia", 842)
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        step_id = f"{native.key}:step-001"
        override = {
            "id": "orcish-fodder-east-ronfaure",
            "source_revisions": {"bg": 841, "ffxiclopedia": 842},
            "source_step_ids": [step_id],
            "source_claim_ids": [f"{step_id}:claim-01"],
            "action": "fight",
            "items": ["Scholar Stone"],
            "enemies": ["Orcish Fodder"],
            "destination_id": "enemy:101:orcish-fodder:fixture",
            "zone": 101,
            "zone_name": "East Ronfaure",
            "label": "Orcish Fodder in East Ronfaure",
            "reference": {"name": "Orcish Fodder", "kind": "enemy"},
            "arrival_instruction": "Defeat Orcish Fodder.",
        }
        overrides = {"objective_destination_overrides": {native.key: [override]}}
        points = (
            {
                "zone": 101,
                "name": "Orcish Fodder",
                "kind": "enemy",
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            },
        )

        with self.assertRaises(ObjectiveDestinationError):
            resolve_reviewed_objective_destinations(
                native, reconciled, bg, ffxi, overrides, points, {101: "East Ronfaure"}
            )

        override["items"] = []
        rows = resolve_reviewed_objective_destinations(
            native, reconciled, bg, ffxi, overrides, points, {101: "East Ronfaure"}
        )
        self.assertEqual(rows[0].enemies, ("Orcish Fodder",))

    def test_destination_rejects_interstitial_evidence_from_a_later_claim(self) -> None:
        native = NativeObjective("quest", "other_areas", 85, "Interstitial Destination", "quests.dat", 0)

        def page(site: str, page_id: int) -> ParsedObjective:
            return parse_objective_page(
                PageRevision(
                    site=site,
                    api_url="https://example.invalid/api.php",
                    canonical_title="Interstitial Destination",
                    page_id=page_id,
                    revision_id=page_id,
                    parent_revision_id=page_id - 1,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        "*Defeat [[Mob A]] in [[East Ronfaure]], and in [[West Ronfaure]] "
                        "at (H-8) talk to [[NPC B]].\n"
                    ),
                )
            )

        bg = page("bg", 851)
        ffxi = page("ffxiclopedia", 852)
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        step_id = f"{native.key}:step-001"
        override = {
            "id": "unsafe-mob-a-west",
            "source_revisions": {"bg": 851, "ffxiclopedia": 852},
            "source_step_ids": [step_id],
            "source_claim_ids": [f"{step_id}:claim-01"],
            "action": "fight",
            "items": [],
            "enemies": ["Mob A"],
            "grid_coordinates": ["H-8"],
            "destination_id": "enemy:100:mob-a:fixture",
            "zone": 100,
            "zone_name": "West Ronfaure",
            "label": "unsafe Mob A in West Ronfaure",
            "reference": {"name": "Mob A", "kind": "enemy"},
            "arrival_instruction": "Defeat Mob A.",
        }
        overrides = {"objective_destination_overrides": {native.key: [override]}}
        west_point = {
            "zone": 100,
            "name": "Mob A",
            "kind": "enemy",
            "x": 1.0,
            "z": 2.0,
            "y": 3.0,
        }

        with self.assertRaises(ObjectiveDestinationError):
            resolve_reviewed_objective_destinations(
                native,
                reconciled,
                bg,
                ffxi,
                overrides,
                (west_point,),
                {100: "West Ronfaure"},
            )

        override.update(
            {
                "id": "mob-a-east",
                "grid_coordinates": [],
                "destination_id": "enemy:101:mob-a:fixture",
                "zone": 101,
                "zone_name": "East Ronfaure",
                "label": "Mob A in East Ronfaure",
            }
        )
        east_point = {**west_point, "zone": 101}
        rows = resolve_reviewed_objective_destinations(
            native,
            reconciled,
            bg,
            ffxi,
            overrides,
            (east_point,),
            {101: "East Ronfaure"},
        )
        self.assertEqual(rows[0].target_name, "Mob A")

    def test_destination_rejects_period_and_ambiguous_interstitial_evidence(self) -> None:
        native = NativeObjective("quest", "other_areas", 86, "Boundary Destination", "quests.dat", 0)

        def resolve(instruction: str, *, zone: int, zone_name: str, grid: list[str]):
            def page(site: str, page_id: int) -> ParsedObjective:
                return parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title="Boundary Destination",
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                    )
                )

            bg = page("bg", 861)
            ffxi = page("ffxiclopedia", 862)
            reconciled = reconcile_objectives(native.key, bg, ffxi)
            step_id = f"{native.key}:step-001"
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": "mob-a-boundary-probe",
                            "source_revisions": {"bg": 861, "ffxiclopedia": 862},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-01"],
                            "action": "fight",
                            "items": [],
                            "enemies": ["Mob A"],
                            "grid_coordinates": grid,
                            "destination_id": f"enemy:{zone}:mob-a:fixture",
                            "zone": zone,
                            "zone_name": zone_name,
                            "label": f"Mob A in {zone_name}",
                            "reference": {"name": "Mob A", "kind": "enemy"},
                            "arrival_instruction": "Defeat Mob A.",
                        }
                    ]
                }
            }
            point = {
                "zone": zone,
                "name": "Mob A",
                "kind": "enemy",
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native,
                reconciled,
                bg,
                ffxi,
                overrides,
                (point,),
                {zone: zone_name},
            )

        strong = (
            "Defeat [[Mob A]] in [[East Ronfaure]]. At (H-8) in [[West Ronfaure]], "
            "talk to [[NPC B]]."
        )
        bare_grid = (
            "Defeat [[Mob A]] in [[East Ronfaure]]. (H-8) in [[West Ronfaure]], "
            "talk to [[NPC B]]."
        )
        ambiguous = (
            "Defeat [[Mob A]] in [[East Ronfaure]] in [[West Ronfaure]] at (H-8) "
            "talk to [[NPC B]]."
        )
        for instruction in (strong, bare_grid, ambiguous):
            with self.subTest(instruction=instruction), self.assertRaises(ObjectiveDestinationError):
                resolve(instruction, zone=100, zone_name="West Ronfaure", grid=["H-8"])

        self.assertEqual(
            resolve(strong, zone=101, zone_name="East Ronfaure", grid=[])[0].target_name,
            "Mob A",
        )
        with self.assertRaises(ObjectiveDestinationError):
            resolve(ambiguous, zone=101, zone_name="East Ronfaure", grid=[])

    def test_destination_rejects_question_target_and_abbreviation_boundary_leaks(self) -> None:
        def resolve(
            *,
            native: NativeObjective,
            instruction: str,
            claim_order: int,
            action: str,
            target_name: str,
            target_kind: str,
            zone: int,
            zone_name: str,
            grid: list[str],
        ):
            def page(site: str, page_id: int) -> ParsedObjective:
                return parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title=native.title,
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                    )
                )

            bg = page("bg", 871)
            ffxi = page("ffxiclopedia", 872)
            reconciled = reconcile_objectives(native.key, bg, ffxi)
            step_id = f"{native.key}:step-001"
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": "punctuation-boundary-probe",
                            "source_revisions": {"bg": 871, "ffxiclopedia": 872},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-{claim_order:02d}"],
                            "action": action,
                            "items": [],
                            "enemies": [],
                            "grid_coordinates": grid,
                            "destination_id": f"{target_kind}:{zone}:punctuation:fixture",
                            "zone": zone,
                            "zone_name": zone_name,
                            "label": f"{target_name} in {zone_name}",
                            "reference": {"name": target_name, "kind": target_kind},
                            "arrival_instruction": f"{action.title()} {target_name}.",
                        }
                    ]
                }
            }
            point = {
                "zone": zone,
                "name": target_name,
                "kind": target_kind,
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native,
                reconciled,
                bg,
                ffxi,
                overrides,
                (point,),
                {zone: zone_name},
            )

        question_native = NativeObjective(
            "quest", "other_areas", 87, "Question Boundary Destination", "quests.dat", 0
        )
        question_instruction = (
            "In [[East Ronfaure]], examine the ???. At (H-8) in [[West Ronfaure]], "
            "talk to [[NPC B]]."
        )
        with self.assertRaises(ObjectiveDestinationError):
            resolve(
                native=question_native,
                instruction=question_instruction,
                claim_order=1,
                action="examine",
                target_name="???",
                target_kind="question-mark",
                zone=100,
                zone_name="West Ronfaure",
                grid=["H-8"],
            )

        abbreviation_native = NativeObjective(
            "quest", "other_areas", 88, "Abbreviation Destination", "quests.dat", 0
        )
        for abbreviation in ("e.g.", "i.e."):
            instruction = (
                f"Trade an item, {abbreviation} Scholar Stone, to [[Cid]] in "
                "[[East Ronfaure]], then talk to [[NPC B]] in [[West Ronfaure]]."
            )
            with self.subTest(abbreviation=abbreviation), self.assertRaises(ObjectiveDestinationError):
                resolve(
                    native=abbreviation_native,
                    instruction=instruction,
                    claim_order=2,
                    action="talk",
                    target_name="NPC B",
                    target_kind="npc",
                    zone=101,
                    zone_name="East Ronfaure",
                    grid=[],
                )
        for phrase in (
            "Lv. 75",
            "Mr. Smith",
            "Mrs. Smith",
            "Ms. Smith",
            "Dr. Shantotto",
            "No. 13",
            "etc. details",
        ):
            instruction = (
                f"Defeat [[Mob A]], {phrase} in [[East Ronfaure]], then talk to "
                "[[NPC B]] in [[West Ronfaure]]."
            )
            with self.subTest(phrase=phrase), self.assertRaises(ObjectiveDestinationError):
                resolve(
                    native=abbreviation_native,
                    instruction=instruction,
                    claim_order=2,
                    action="talk",
                    target_name="NPC B",
                    target_kind="npc",
                    zone=101,
                    zone_name="East Ronfaure",
                    grid=[],
                )

    def test_destination_rejects_trailing_and_intermediate_context_zones(self) -> None:
        native = NativeObjective("quest", "other_areas", 89, "Context Boundary", "quests.dat", 0)

        def resolve(instruction: str, zone_name: str):
            def page(site: str, page_id: int) -> ParsedObjective:
                return parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title=native.title,
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                    )
                )

            bg = page("bg", 891)
            ffxi = page("ffxiclopedia", 892)
            reconciled = reconcile_objectives(native.key, bg, ffxi)
            step_id = f"{native.key}:step-001"
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": "mob-a-context-probe",
                            "source_revisions": {"bg": 891, "ffxiclopedia": 892},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-01"],
                            "action": "fight",
                            "items": [],
                            "enemies": ["Mob A"],
                            "destination_id": "enemy:100:mob-a:context",
                            "zone": 100,
                            "zone_name": zone_name,
                            "label": f"Mob A in {zone_name}",
                            "reference": {"name": "Mob A", "kind": "enemy"},
                            "arrival_instruction": "Defeat Mob A.",
                        }
                    ]
                }
            }
            point = {
                "zone": 100,
                "name": "Mob A",
                "kind": "enemy",
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native, reconciled, bg, ffxi, overrides, (point,), {100: zone_name}
            )

        trailing = (
            "Defeat [[Mob A]] in [[East Ronfaure]]. A cutscene occurs in "
            "[[West Ronfaure]]."
        )
        intermediate = (
            "Defeat [[Mob A]] in [[East Ronfaure]]. A cutscene occurs in "
            "[[West Ronfaure]]. At (H-8) in [[North Gustaberg]], talk to [[NPC B]]."
        )
        for instruction in (trailing, intermediate):
            with self.subTest(instruction=instruction), self.assertRaises(ObjectiveDestinationError):
                resolve(instruction, "West Ronfaure")

    def test_destination_rejects_context_after_terminal_etc(self) -> None:
        native = NativeObjective("quest", "other_areas", 93, "Terminal Etc", "quests.dat", 0)

        def page(site: str, page_id: int) -> ParsedObjective:
            return parse_objective_page(
                PageRevision(
                    site=site,
                    api_url="https://example.invalid/api.php",
                    canonical_title=native.title,
                    page_id=page_id,
                    revision_id=page_id,
                    parent_revision_id=page_id - 1,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        "*Defeat [[Mob A]] in [[East Ronfaure]], etc. A cutscene occurs in "
                        "[[West Ronfaure]].\n"
                    ),
                )
            )

        bg = page("bg", 931)
        ffxi = page("ffxiclopedia", 932)
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        step_id = f"{native.key}:step-001"
        overrides = {
            "objective_destination_overrides": {
                native.key: [
                    {
                        "id": "unsafe-mob-a-west",
                        "source_revisions": {"bg": 931, "ffxiclopedia": 932},
                        "source_step_ids": [step_id],
                        "source_claim_ids": [f"{step_id}:claim-01"],
                        "action": "fight",
                        "items": [],
                        "enemies": ["Mob A"],
                        "destination_id": "enemy:100:mob-a:etc",
                        "zone": 100,
                        "zone_name": "West Ronfaure",
                        "label": "Mob A in West Ronfaure",
                        "reference": {"name": "Mob A", "kind": "enemy"},
                        "arrival_instruction": "Defeat Mob A.",
                    }
                ]
            }
        }
        point = {
            "zone": 100,
            "name": "Mob A",
            "kind": "enemy",
            "x": 1.0,
            "z": 2.0,
            "y": 3.0,
        }

        with self.assertRaises(ObjectiveDestinationError):
            resolve_reviewed_objective_destinations(
                native, reconciled, bg, ffxi, overrides, (point,), {100: "West Ronfaure"}
            )

    def test_destination_rejects_lowercase_sentence_after_contextual_abbreviation(self) -> None:
        native = NativeObjective(
            "quest", "other_areas", 97, "Lowercase Abbreviation Boundary", "quests.dat", 0
        )

        def resolve(abbreviation: str, following_context: str):
            instruction = (
                f"Defeat [[Mob A]] in [[East Ronfaure]], {abbreviation} "
                f"{following_context} in [[West Ronfaure]]."
            )

            def page(site: str, page_id: int) -> ParsedObjective:
                return parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title=native.title,
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                    )
                )

            bg = page("bg", 971)
            ffxi = page("ffxiclopedia", 972)
            reconciled = reconcile_objectives(native.key, bg, ffxi)
            step_id = f"{native.key}:step-001"
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": "unsafe-lowercase-abbreviation-context",
                            "source_revisions": {"bg": 971, "ffxiclopedia": 972},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-01"],
                            "action": "fight",
                            "items": [],
                            "enemies": ["Mob A"],
                            "destination_id": "enemy:105:lowercase-context:fixture",
                            "zone": 105,
                            "zone_name": "West Ronfaure",
                            "label": "Mob A in West Ronfaure",
                            "reference": {"name": "Mob A", "kind": "enemy"},
                            "arrival_instruction": "Defeat Mob A.",
                        }
                    ]
                }
            }
            point = {
                "zone": 105,
                "name": "Mob A",
                "kind": "enemy",
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native, reconciled, bg, ffxi, overrides, (point,), {105: "West Ronfaure"}
            )

        for abbreviation in ("etc.", "N.M."):
            for following_context in ("a cutscene occurs", "something happens"):
                with self.subTest(
                    abbreviation=abbreviation,
                    following_context=following_context,
                ), self.assertRaises(ObjectiveDestinationError):
                    resolve(abbreviation, following_context)

    def test_destination_rejects_context_after_terminal_multi_initialism(self) -> None:
        native = NativeObjective(
            "quest", "other_areas", 95, "Terminal Multi Initialism", "quests.dat", 0
        )

        def resolve(instruction: str, grid: list[str]):
            def page(site: str, page_id: int) -> ParsedObjective:
                return parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title=native.title,
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                    )
                )

            bg = page("bg", 951)
            ffxi = page("ffxiclopedia", 952)
            reconciled = reconcile_objectives(native.key, bg, ffxi)
            step_id = f"{native.key}:step-001"
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": "unsafe-mob-a-initialism-context",
                            "source_revisions": {"bg": 951, "ffxiclopedia": 952},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-01"],
                            "action": "fight",
                            "items": [],
                            "enemies": ["Mob A"],
                            "grid_coordinates": grid,
                            "destination_id": "enemy:102:mob-a:initialism-context",
                            "zone": 102,
                            "zone_name": "West Ronfaure",
                            "label": "Mob A in West Ronfaure",
                            "reference": {"name": "Mob A", "kind": "enemy"},
                            "arrival_instruction": "Defeat Mob A.",
                        }
                    ]
                }
            }
            point = {
                "zone": 102,
                "name": "Mob A",
                "kind": "enemy",
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native, reconciled, bg, ffxi, overrides, (point,), {102: "West Ronfaure"}
            )

        cases = (
            (
                "Defeat [[Mob A]] in [[East Ronfaure]] as an N.M. A cutscene occurs in "
                "[[West Ronfaure]].",
                [],
            ),
            (
                "Defeat [[Mob A]] in [[East Ronfaure]], N.M. At (H-8) in "
                "[[West Ronfaure]], talk to [[NPC B]].",
                ["H-8"],
            ),
        )
        for instruction, grid in cases:
            with self.subTest(instruction=instruction), self.assertRaises(
                ObjectiveDestinationError
            ):
                resolve(instruction, grid)

    def test_destination_keeps_linked_initialism_target_claim_local(self) -> None:
        native = NativeObjective(
            "quest", "other_areas", 96, "Linked Initialism Target", "quests.dat", 0
        )
        instruction = (
            "Defeat the N.M. [[Bugallug]] in [[Oldton Movalpolos]], then talk to "
            "[[Cid]] in [[Metalworks]]."
        )

        def page(site: str, page_id: int) -> ParsedObjective:
            return parse_objective_page(
                PageRevision(
                    site=site,
                    api_url="https://example.invalid/api.php",
                    canonical_title=native.title,
                    page_id=page_id,
                    revision_id=page_id,
                    parent_revision_id=page_id - 1,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                )
            )

        bg = page("bg", 961)
        ffxi = page("ffxiclopedia", 962)
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        step_id = f"{native.key}:step-001"

        def resolve(
            *, claim_order: int, action: str, target: str, kind: str, zone: int, zone_name: str
        ):
            enemies = [target] if action == "fight" else []
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": f"linked-initialism-{action}-{zone}",
                            "source_revisions": {"bg": 961, "ffxiclopedia": 962},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-{claim_order:02d}"],
                            "action": action,
                            "items": [],
                            "enemies": enemies,
                            "destination_id": f"{kind}:{zone}:linked-initialism:fixture",
                            "zone": zone,
                            "zone_name": zone_name,
                            "label": f"{target} in {zone_name}",
                            "reference": {"name": target, "kind": kind},
                            "arrival_instruction": f"{action.title()} {target}.",
                        }
                    ]
                }
            }
            point = {
                "zone": zone,
                "name": target,
                "kind": kind,
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native,
                reconciled,
                bg,
                ffxi,
                overrides,
                (point,),
                {zone: zone_name},
            )

        with self.subTest(route="fight-correct"):
            fight_rows = resolve(
                claim_order=1,
                action="fight",
                target="Bugallug",
                kind="enemy",
                zone=103,
                zone_name="Oldton Movalpolos",
            )
            self.assertEqual(fight_rows[0].target_name, "Bugallug")

        with self.subTest(route="talk-correct"):
            talk_rows = resolve(
                claim_order=2,
                action="talk",
                target="Cid",
                kind="npc",
                zone=104,
                zone_name="Metalworks",
            )
            self.assertEqual(talk_rows[0].target_name, "Cid")

        for claim_order, action, target, kind, zone, zone_name in (
            (1, "fight", "Bugallug", "enemy", 104, "Metalworks"),
            (2, "talk", "Cid", "npc", 103, "Oldton Movalpolos"),
        ):
            with self.subTest(action=action, zone_name=zone_name), self.assertRaises(
                ObjectiveDestinationError
            ):
                resolve(
                    claim_order=claim_order,
                    action=action,
                    target=target,
                    kind=kind,
                    zone=zone,
                    zone_name=zone_name,
                )

    def test_destination_keeps_example_initialism_target_claim_local(self) -> None:
        native = NativeObjective(
            "quest", "other_areas", 98, "Linked Example Target", "quests.dat", 0
        )

        def resolve(initialism: str, *, claim_order: int, action: str, target: str, kind: str,
                    zone: int, zone_name: str):
            instruction = (
                f"Defeat an enemy, {initialism} [[Mob A]] in [[East Ronfaure]], then "
                "talk to [[NPC B]] in [[West Ronfaure]]."
            )

            def page(site: str, page_id: int) -> ParsedObjective:
                return parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title=native.title,
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                    )
                )

            bg = page("bg", 981)
            ffxi = page("ffxiclopedia", 982)
            reconciled = reconcile_objectives(native.key, bg, ffxi)
            step_id = f"{native.key}:step-001"
            enemies = [target] if action == "fight" else []
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": f"example-initialism-{initialism.replace('.', '')}-{action}-{zone}",
                            "source_revisions": {"bg": 981, "ffxiclopedia": 982},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-{claim_order:02d}"],
                            "action": action,
                            "items": [],
                            "enemies": enemies,
                            "destination_id": f"{kind}:{zone}:example-initialism:fixture",
                            "zone": zone,
                            "zone_name": zone_name,
                            "label": f"{target} in {zone_name}",
                            "reference": {"name": target, "kind": kind},
                            "arrival_instruction": f"{action.title()} {target}.",
                        }
                    ]
                }
            }
            point = {
                "zone": zone,
                "name": target,
                "kind": kind,
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native, reconciled, bg, ffxi, overrides, (point,), {zone: zone_name}
            )

        for initialism in ("e.g.", "i.e."):
            with self.subTest(initialism=initialism, route="fight-correct"):
                self.assertEqual(
                    resolve(
                        initialism,
                        claim_order=1,
                        action="fight",
                        target="Mob A",
                        kind="enemy",
                        zone=106,
                        zone_name="East Ronfaure",
                    )[0].target_name,
                    "Mob A",
                )
            with self.subTest(initialism=initialism, route="talk-correct"):
                self.assertEqual(
                    resolve(
                        initialism,
                        claim_order=2,
                        action="talk",
                        target="NPC B",
                        kind="npc",
                        zone=107,
                        zone_name="West Ronfaure",
                    )[0].target_name,
                    "NPC B",
                )
            with self.subTest(initialism=initialism, route="talk-wrong-zone"):
                with self.assertRaises(ObjectiveDestinationError):
                    resolve(
                        initialism,
                        claim_order=2,
                        action="talk",
                        target="NPC B",
                        kind="npc",
                        zone=106,
                        zone_name="East Ronfaure",
                    )

    def test_destination_uses_only_exact_linked_target_from_selected_clause(self) -> None:
        native = NativeObjective("quest", "other_areas", 94, "Linked Target", "quests.dat", 0)

        def resolve(instruction: str, target_name: str):
            def page(site: str, page_id: int) -> ParsedObjective:
                return parse_objective_page(
                    PageRevision(
                        site=site,
                        api_url="https://example.invalid/api.php",
                        canonical_title=native.title,
                        page_id=page_id,
                        revision_id=page_id,
                        parent_revision_id=page_id - 1,
                        revision_timestamp="2026-08-09T00:00:00Z",
                        content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                    )
                )

            bg = page("bg", 941)
            ffxi = page("ffxiclopedia", 942)
            reconciled = reconcile_objectives(native.key, bg, ffxi)
            step_id = f"{native.key}:step-001"
            overrides = {
                "objective_destination_overrides": {
                    native.key: [
                        {
                            "id": "linked-target-probe",
                            "source_revisions": {"bg": 941, "ffxiclopedia": 942},
                            "source_step_ids": [step_id],
                            "source_claim_ids": [f"{step_id}:claim-01"],
                            "action": "fight",
                            "items": [],
                            "enemies": [target_name],
                            "destination_id": "enemy:101:linked-target:fixture",
                            "zone": 101,
                            "zone_name": "East Ronfaure",
                            "label": f"{target_name} in East Ronfaure",
                            "reference": {"name": target_name, "kind": "enemy"},
                            "arrival_instruction": f"Defeat {target_name}.",
                        }
                    ]
                }
            }
            point = {
                "zone": 101,
                "name": target_name,
                "kind": "enemy",
                "x": 1.0,
                "z": 2.0,
                "y": 3.0,
            }
            return resolve_reviewed_objective_destinations(
                native,
                reconciled,
                bg,
                ffxi,
                overrides,
                (point,),
                {101: "East Ronfaure"},
            )

        rows = resolve(
            "Defeat the Lv. 75 [[Mob A]] in [[East Ronfaure]].",
            "Mob A",
        )
        self.assertEqual(rows[0].target_name, "Mob A")

        with self.assertRaises(ObjectiveDestinationError):
            resolve(
                "Defeat the Lv. 75 foe in [[East Ronfaure]], then talk to [[NPC B]] in "
                "[[West Ronfaure]].",
                "NPC B",
            )

        with self.subTest(case="repeated-later-link"), self.assertRaises(
            ObjectiveDestinationError
        ):
            resolve(
                "Defeat the Lv. 75 Mob A in [[East Ronfaure]], then talk to [[Mob A]] in "
                "[[West Ronfaure]].",
                "Mob A",
            )

        for ambiguous_target in ("Mob A", "Mob B"):
            with self.subTest(ambiguous_target=ambiguous_target), self.assertRaises(
                ObjectiveDestinationError
            ):
                resolve(
                    "Defeat [[Mob A]] and [[Mob B]] in [[East Ronfaure]].",
                    ambiguous_target,
                )

    def test_destination_accepts_exact_punctuated_target_identities(self) -> None:
        cases = (
            (90, "Talk to [[Dr. Shantotto]] in [[East Ronfaure]].", "talk", "Dr. Shantotto", "npc"),
            (91, "Defeat [[Lamia No.13]] in [[East Ronfaure]].", "fight", "Lamia No.13", "enemy"),
            (92, "Defeat [[Prototype 1.5]] in [[East Ronfaure]].", "fight", "Prototype 1.5", "enemy"),
        )
        for native_id, instruction, action, target_name, target_kind in cases:
            with self.subTest(target_name=target_name):
                native = NativeObjective(
                    "quest", "other_areas", native_id, "Punctuated Identity", "quests.dat", 0
                )

                def page(site: str, page_id: int) -> ParsedObjective:
                    return parse_objective_page(
                        PageRevision(
                            site=site,
                            api_url="https://example.invalid/api.php",
                            canonical_title=native.title,
                            page_id=page_id,
                            revision_id=page_id,
                            parent_revision_id=page_id - 1,
                            revision_timestamp="2026-08-09T00:00:00Z",
                            content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                        )
                    )

                bg = page("bg", 900 + native_id)
                ffxi = page("ffxiclopedia", 1000 + native_id)
                reconciled = reconcile_objectives(native.key, bg, ffxi)
                step_id = f"{native.key}:step-001"
                overrides = {
                    "objective_destination_overrides": {
                        native.key: [
                            {
                                "id": "exact-punctuated-identity",
                                "source_revisions": {
                                    "bg": 900 + native_id,
                                    "ffxiclopedia": 1000 + native_id,
                                },
                                "source_step_ids": [step_id],
                                "source_claim_ids": [f"{step_id}:claim-01"],
                                "action": action,
                                "items": [],
                                "enemies": [target_name] if target_kind == "enemy" else [],
                                "destination_id": f"{target_kind}:101:punctuated:fixture",
                                "zone": 101,
                                "zone_name": "East Ronfaure",
                                "label": f"{target_name} in East Ronfaure",
                                "reference": {"name": target_name, "kind": target_kind},
                                "arrival_instruction": f"{action.title()} {target_name}.",
                            }
                        ]
                    }
                }
                point = {
                    "zone": 101,
                    "name": target_name,
                    "kind": target_kind,
                    "x": 1.0,
                    "z": 2.0,
                    "y": 3.0,
                }

                rows = resolve_reviewed_objective_destinations(
                    native,
                    reconciled,
                    bg,
                    ffxi,
                    overrides,
                    (point,),
                    {101: "East Ronfaure"},
                )
                self.assertEqual(rows[0].target_name, target_name)

    def test_destination_order_is_stable_and_native_qualified(self) -> None:
        native, bg, ffxi, reconciled, overrides = self._fixture("quest")
        first = overrides["objective_destination_overrides"][native.key][0]
        second = dict(first)
        first["id"] = "zeta-camp"
        first["destination_id"] = "camp:101:orcish-fodder:zeta"
        second["id"] = "alpha-camp"
        second["destination_id"] = "camp:101:orcish-fodder:alpha"
        overrides["objective_destination_overrides"][native.key] = [first, second]

        rows = self._resolve(native, bg, ffxi, reconciled, overrides)

        self.assertEqual(
            [row.stable_id for row in rows],
            [
                "quest:sandoria:1:destination:alpha-camp",
                "quest:sandoria:1:destination:zeta-camp",
            ],
        )

    def test_legacy_route_evidence_never_promotes_destination_eligibility(self) -> None:
        native, bg, ffxi, reconciled, _overrides = self._fixture("mission")
        legacy = {
            "mission_destination_overrides": {
                native.key: [
                    {
                        "id": "legacy-camp",
                        "source_revisions": {"bg": 4001, "ffxiclopedia": 4002},
                        "source_step_ids": [f"{native.key}:step-001"],
                        "action": "obtain",
                        "items": ["Orcish Axe"],
                        "enemies": ["Orcish Fodder"],
                        "zone": 101,
                        "zone_name": "East Ronfaure",
                        "camp_label": "legacy Orcish Fodder camp",
                        "reference": {"name": "Orcish Fodder", "kind": "enemy"},
                        "route_evidence": "navprobe:legacy-free-text-proof",
                        "arrival_instruction": "Defeat Orcish Fodder until you obtain an Orcish Axe.",
                    }
                ]
            }
        }

        rows = self._resolve(native, bg, ffxi, reconciled, legacy)

        self.assertEqual(rows[0].eligibility, "catalogue")
        self.assertEqual(rows[0].route_contract_id, "")
        self.assertFalse(rows[0].instruction_only)

    def test_target_and_unrelated_zone_from_different_sources_cannot_form_destination(self) -> None:
        native = NativeObjective("quest", "other_areas", 8, "Split Claims", "quests.dat", 0)
        bg_span = SourceActionSpan(
            source_step_order=1,
            order=1,
            text_start=0,
            text_end=22,
            supporting_clause="Defeat Orcish Fodder.",
            action="fight",
            verb="defeat",
            relationship="defeat-enemy",
            target="Orcish Fodder",
            target_kind="enemy",
            enemy_mentions=("Orcish Fodder",),
        )
        ffxi_span = SourceActionSpan(
            source_step_order=1,
            order=1,
            text_start=0,
            text_end=38,
            supporting_clause="Defeat enemies in West Sarutabaruta.",
            action="fight",
            verb="defeat",
            relationship="defeat-enemy",
            zone_mentions=("West Sarutabaruta",),
        )
        pages = []
        for site, page_id, revision_id, span in (
            ("bg", 501, 5001, bg_span),
            ("ffxiclopedia", 502, 5002, ffxi_span),
        ):
            pages.append(
                ParsedObjective(
                    site=site,
                    page_id=page_id,
                    revision_id=revision_id,
                    canonical_title="Split Claims",
                    kind="quest",
                    objective_name="Split Claims",
                    steps=(
                        SourceStep(
                            1,
                            "*",
                            1,
                            span.supporting_clause,
                            span.supporting_clause,
                            "fight",
                            linked_entities=span.enemy_mentions,
                            zone_candidates=span.zone_mentions,
                            action_spans=(span,),
                        ),
                    ),
                )
            )
        bg, ffxi = pages
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        claim = reconciled.steps[0].claims[0]
        self.assertEqual(
            [
                (candidate.field, candidate.value, candidate.sources)
                for candidate in claim.candidates
                if candidate.field in {"target", "zone"}
            ],
            [
                ("target", "Orcish Fodder", ("bg",)),
                ("zone", "West Sarutabaruta", ("ffxiclopedia",)),
            ],
        )
        overrides = {
            "objective_destination_overrides": {
                native.key: [
                    {
                        "id": "unsafe-joined-claim",
                        "source_revisions": {"bg": 5001, "ffxiclopedia": 5002},
                        "source_step_ids": [f"{native.key}:step-001"],
                        "action": "fight",
                        "items": [],
                        "enemies": ["Orcish Fodder"],
                        "destination_id": "enemy:115:orcish-fodder:fixture",
                        "zone": 115,
                        "zone_name": "West Sarutabaruta",
                        "label": "unsafe joined claim",
                        "reference": {"name": "Orcish Fodder", "kind": "enemy"},
                        "arrival_instruction": "Defeat Orcish Fodder.",
                    }
                ]
            }
        }
        with self.assertRaises(ObjectiveDestinationError):
            resolve_reviewed_objective_destinations(
                native,
                reconciled,
                bg,
                ffxi,
                overrides,
                ({"zone": 115, "name": "Orcish Fodder", "kind": "enemy"},),
                {115: "West Sarutabaruta"},
            )


class GeneratedArtifactTests(unittest.TestCase):
    def test_navigation_catalog_loader_uses_exact_tsv_identity_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destinations = root / "destinations.tsv"
            graph = root / "graph.tsv"
            destinations.write_text(
                "# comment\n"
                "172\tMakarim\t-60.925\t-333.294\t8.471\tnpc\tcurrent-nav\tuntested\treview note\n",
                encoding="utf-8",
            )
            graph.write_text(
                "zoneline_id\tfrom_zone\tfrom_name\tfrom_code\tfrom_x\tfrom_z\tfrom_y\t"
                "to_zone\tto_name\tto_code\tto_x\tto_z\tto_y\tsource\tconfidence\tnote\n"
                "1\t172\tZeruhn Mines\tz5c0\t0\t0\t0\t234\tBastok Mines\tz750\t0\t0\t0\ttest\tverified\t\n",
                encoding="utf-8",
            )

            catalog = _load_navigation_catalog(destinations, graph)

        self.assertEqual(len(catalog), 3)
        points, zone_names, edges = catalog
        self.assertEqual(len(points), 1)
        self.assertEqual(points[0]["zone"], 172)
        self.assertEqual(points[0]["name"], "Makarim")
        self.assertEqual(points[0]["kind"], "npc")
        self.assertEqual(points[0]["confidence"], "untested")
        self.assertEqual(points[0]["note"], "review note")
        self.assertEqual(zone_names[172], "Zeruhn Mines")
        self.assertEqual(zone_names[234], "Bastok Mines")
        self.assertEqual(
            edges,
            (
                {
                    "id": 1,
                    "from_zone": 172,
                    "from_name": "Zeruhn Mines",
                    "to_zone": 234,
                    "to_name": "Bastok Mines",
                    "source": "test",
                    "confidence": "verified",
                },
            ),
        )

    def _named_npc_target_fixture(
        self,
        *,
        bg_name: str = "Makarim",
        ffxi_name: str = "Makarim",
        bg_action: str = "talk",
        ffxi_action: str = "talk",
        bg_instruction: str | None = None,
        ffxi_instruction: str | None = None,
    ) -> tuple[tuple[NativeObjective, ...], tuple[ParsedObjective, ...]]:
        natives = (
            NativeObjective(
                "mission",
                "Bastok",
                1,
                "The Zeruhn Report",
                "missions.dat",
                0,
                1,
            ),
        )
        pages = (
            ParsedObjective(
                site="bg",
                page_id=101,
                revision_id=1001,
                canonical_title="The Zeruhn Report",
                kind="mission",
                objective_name="The Zeruhn Report",
                steps=(
                    SourceStep(
                        1,
                        "*",
                        1,
                        bg_instruction or f"Talk to {bg_name} in Zeruhn Mines.",
                        bg_instruction or f"Talk to {bg_name} in Zeruhn Mines.",
                        bg_action,
                        linked_entities=(bg_name, "Zeruhn Mines"),
                        zone_candidates=("Zeruhn Mines",),
                        action_spans=(
                            SourceActionSpan(
                                source_step_order=1,
                                order=1,
                                text_start=0,
                                text_end=len(bg_instruction or f"Talk to {bg_name} in Zeruhn Mines."),
                                supporting_clause=bg_instruction or f"Talk to {bg_name} in Zeruhn Mines.",
                                action=bg_action,
                                verb="talk" if bg_action == "talk" else bg_action,
                                relationship="talk-to" if bg_action == "talk" else bg_action,
                                target=bg_name,
                                target_kind="npc",
                                npc_mentions=(bg_name,),
                                zone_mentions=("Zeruhn Mines",),
                            ),
                        ),
                    ),
                ),
            ),
            ParsedObjective(
                site="ffxiclopedia",
                page_id=202,
                revision_id=2002,
                canonical_title="The Zeruhn Report",
                kind="mission",
                objective_name="The Zeruhn Report",
                steps=(
                    SourceStep(
                        1,
                        "*",
                        1,
                        ffxi_instruction or f"Speak with {ffxi_name} in Zeruhn Mines.",
                        ffxi_instruction or f"Speak with {ffxi_name} in Zeruhn Mines.",
                        ffxi_action,
                        linked_entities=(ffxi_name, "Zeruhn Mines"),
                        zone_candidates=("Zeruhn Mines",),
                        action_spans=(
                            SourceActionSpan(
                                source_step_order=1,
                                order=1,
                                text_start=0,
                                text_end=len(ffxi_instruction or f"Speak with {ffxi_name} in Zeruhn Mines."),
                                supporting_clause=(
                                    ffxi_instruction or f"Speak with {ffxi_name} in Zeruhn Mines."
                                ),
                                action=ffxi_action,
                                verb="speak" if ffxi_action == "talk" else ffxi_action,
                                relationship="talk-to" if ffxi_action == "talk" else ffxi_action,
                                target=ffxi_name,
                                target_kind="npc",
                                npc_mentions=(ffxi_name,),
                                zone_mentions=("Zeruhn Mines",),
                            ),
                        ),
                    ),
                ),
            ),
        )
        return natives, pages

    @staticmethod
    def _named_npc_target_overrides() -> dict:
        return {
            "target_overrides": {
                "mission:Bastok:1:step-001": {
                    "source_revisions": {"bg": 1001, "ffxiclopedia": 2002},
                    "reference": {
                        "zone": 172,
                        "zone_name": "Zeruhn Mines",
                        "name": "Makarim",
                        "kind": "npc",
                    },
                    "arrival_instruction": "Talk to Makarim.",
                }
            }
        }

    def _mission_destination_fixture(
        self,
    ) -> tuple[tuple[NativeObjective, ...], tuple[ParsedObjective, ...], dict]:
        items = ("Fetich Head", "Fetich Torso", "Fetich Arms", "Fetich Legs")
        natives = (
            NativeObjective(
                "mission",
                "Bastok",
                3,
                "Fetichism",
                "missions.dat",
                0,
                2,
            ),
        )
        pages = tuple(
            ParsedObjective(
                site=site,
                page_id=page_id,
                revision_id=revision_id,
                canonical_title="Fetichism",
                kind="mission",
                objective_name="Fetichism",
                steps=(
                    SourceStep(
                        1,
                        "*",
                        1,
                        "Obtain the four Fetich pieces.",
                        "Obtain the four Fetich pieces.",
                        "obtain",
                        linked_entities=items,
                        items=items,
                        action_spans=(
                            SourceActionSpan(
                                source_step_order=1,
                                order=1,
                                text_start=0,
                                text_end=30,
                                supporting_clause="Obtain the four Fetich pieces.",
                                action="obtain",
                                verb="obtain",
                                relationship="obtain-item",
                                target="Fetich pieces",
                                target_kind="item",
                                item_mentions=items,
                            ),
                        ),
                    ),
                    SourceStep(
                        2,
                        "*",
                        1,
                        "Defeat Amber Quadav in Palborough Mines for the Fetich pieces.",
                        "Defeat Amber Quadav in Palborough Mines for the Fetich pieces.",
                        "fight",
                        linked_entities=("Amber Quadav", "Palborough Mines"),
                        zone_candidates=("Palborough Mines",),
                        action_spans=(
                            SourceActionSpan(
                                source_step_order=2,
                                order=1,
                                text_start=0,
                                text_end=68,
                                supporting_clause=(
                                    "Defeat Amber Quadav in Palborough Mines for the Fetich pieces."
                                ),
                                action="fight",
                                verb="defeat",
                                relationship="defeat-to-obtain",
                                target="Amber Quadav",
                                target_kind="enemy",
                                enemy_mentions=("Amber Quadav",),
                                item_mentions=items,
                                zone_mentions=("Palborough Mines",),
                                result_items=items,
                                result_relation="obtain-from",
                            ),
                        ),
                    ),
                ),
            )
            for site, page_id, revision_id in (
                ("bg", 303, 3003),
                ("ffxiclopedia", 404, 4004),
            )
        )
        overrides = {
            "mission_destination_overrides": {
                "mission:Bastok:3": [
                    {
                        "id": "palborough-lower-amber",
                        "source_revisions": {"bg": 3003, "ffxiclopedia": 4004},
                        "source_step_ids": [
                            "mission:Bastok:3:step-001",
                            "mission:Bastok:3:step-002",
                        ],
                        "action": "farm",
                        "items": list(items),
                        "enemies": ["Amber Quadav"],
                        "zone": 143,
                        "zone_name": "Palborough Mines",
                        "camp_label": "lower camp",
                        "reference": {"name": "Amber Quadav", "kind": "enemy"},
                        "route_evidence": (
                            "navprobe:Palborough_Mines.nav:"
                            "north-gustaberg-entry-to-lower-amber:2026-08-08"
                        ),
                        "arrival_instruction": (
                            "Farm Fetich Head, Fetich Torso, Fetich Arms, and Fetich Legs "
                            "from Amber Quadav."
                        ),
                    }
                ]
            }
        }
        return natives, pages, overrides

    def test_reviewed_mission_destination_is_emitted(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(
                    {
                        "zone": 143,
                        "name": "Amber Quadav",
                        "kind": "enemy",
                        "x": 142.0,
                        "z": 154.0,
                        "y": -0.076,
                        "confidence": "untested",
                    },
                ),
                navigation_zone_names={143: "Palborough Mines"},
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_mission_bastok.lua"
            ).read_text(encoding="utf-8")
            review = json.loads(
                (root / "data" / "target-review.json").read_text(encoding="utf-8")
            )

        self.assertIn("objective_destinations = {", reconcile)
        self.assertNotIn("mission_destinations = {", reconcile)
        self.assertIn('stable_id = "mission:Bastok:3:destination:palborough-lower-amber"', reconcile)
        self.assertIn('items = { "Fetich Head", "Fetich Torso", "Fetich Arms", "Fetich Legs" }', reconcile)
        self.assertIn('enemies = { "Amber Quadav" }', reconcile)
        self.assertIn('name = "Amber Quadav"', reconcile)
        self.assertIn('eligibility = "catalogue"', reconcile)
        self.assertNotIn("route_evidence", reconcile)
        self.assertEqual(review["objective_destinations"][0]["classification"], "catalogue-candidate")
        self.assertFalse(review["objective_destinations"][0]["route_ready"])

    def test_reviewed_mission_destination_rejects_unknown_canonical_ingress(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        destination = overrides["mission_destination_overrides"]["mission:Bastok:3"][0]
        destination["canonical_ingress"] = {"edge_id": 999999, "from_zone": 106}
        with tempfile.TemporaryDirectory() as temporary, self.assertRaises(GenerationError):
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(
                    {
                        "zone": 143,
                        "name": "Amber Quadav",
                        "kind": "enemy",
                        "confidence": "untested",
                    },
                ),
                navigation_zone_names={143: "Palborough Mines"},
            )

    def test_reviewed_mission_destination_rejects_unclaimed_item(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        destination = overrides["mission_destination_overrides"]["mission:Bastok:3"][0]
        destination["items"] = [*destination["items"], "Imaginary Fetich"]
        with tempfile.TemporaryDirectory() as temporary, self.assertRaises(GenerationError):
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(
                    {
                        "zone": 143,
                        "name": "Amber Quadav",
                        "kind": "enemy",
                        "confidence": "untested",
                    },
                ),
                navigation_zone_names={143: "Palborough Mines"},
            )

    def test_every_reconciled_row_enters_review_once_with_typed_claims(self) -> None:
        native = NativeObjective("quest", "other_areas", 77, "Audit Stream", "quests.dat", 0)
        protect_span = SourceActionSpan(
            source_step_order=1,
            order=1,
            text_start=0,
            text_end=33,
            supporting_clause="Protect the Elvaan and Hume NPCs.",
            action="protect",
            verb="protect",
            relationship="protect-role",
            target="Elvaan and Hume NPCs",
            target_kind="role",
        )
        warning_span = SourceActionSpan(
            source_step_order=2,
            order=1,
            text_start=0,
            text_end=66,
            supporting_clause="Leaving the battlefield loses the required Dawn Talisman.",
            action="warning",
            verb="loses",
            relationship="required-state-warning",
            target="Dawn Talisman",
            target_kind="key-item",
            item_mentions=("Dawn Talisman",),
        )
        page = ParsedObjective(
            site="bg",
            page_id=707,
            revision_id=7007,
            canonical_title="Audit Stream",
            kind="quest",
            objective_name="Audit Stream",
            steps=(
                SourceStep(
                    1,
                    "*",
                    1,
                    protect_span.supporting_clause,
                    protect_span.supporting_clause,
                    "note",
                    action_spans=(protect_span,),
                ),
                SourceStep(
                    2,
                    "*",
                    1,
                    warning_span.supporting_clause,
                    warning_span.supporting_clause,
                    "note",
                    key_items=("Dawn Talisman",),
                    action_spans=(warning_span,),
                ),
                SourceStep(
                    3,
                    "*",
                    1,
                    "The client shows a final explanatory note.",
                    "The client shows a final explanatory note.",
                    "note",
                ),
            ),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                (native,),
                (page,),
                module_root=root / "modules",
                data_root=root / "data",
            )
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))
            reconcile = (
                root / "modules" / "mission_quest_reconcile_quest_other_areas.lua"
            ).read_text(encoding="utf-8")

        stable_ids = [row["stable_step_id"] for row in review["steps"]]
        self.assertEqual(
            stable_ids,
            [
                "quest:other_areas:77:step-001",
                "quest:other_areas:77:step-002",
                "quest:other_areas:77:step-003",
            ],
        )
        self.assertEqual(len(stable_ids), len(set(stable_ids)))
        self.assertEqual(review["steps"][0]["typed_claims"][0]["action"], "protect")
        self.assertEqual(review["steps"][1]["typed_claims"][0]["action"], "warning")
        self.assertTrue(all(row["classification"] != "context-only" for row in review["steps"]))
        self.assertIn("typed_claims = {", reconcile)

    def test_repository_reviews_both_fetichism_farming_camps(self) -> None:
        overrides = json.loads(
            (
                Path(__file__).parents[1]
                / "data"
                / "mission-quest-guides"
                / "reviewed-overrides.json"
            ).read_text(encoding="utf-8")
        )
        rows = overrides.get("mission_destination_overrides", {}).get("mission:Bastok:3", [])

        self.assertEqual(
            [row["id"] for row in rows],
            ["palborough-lower-amber", "palborough-upper-quadav"],
        )
        expected_items = ["Fetich Head", "Fetich Torso", "Fetich Arms", "Fetich Legs"]
        self.assertEqual(rows[0]["items"], expected_items)
        self.assertEqual(rows[1]["items"], expected_items)
        self.assertEqual(rows[0]["enemies"], ["Amber Quadav"])
        self.assertEqual(
            rows[1]["enemies"],
            ["Greater Quadav", "Onyx Quadav", "Veteran Quadav"],
        )
        self.assertEqual(rows[0]["canonical_ingress"], {"edge_id": 947466874, "from_zone": 106})
        self.assertEqual(rows[1]["canonical_ingress"], {"edge_id": 947466874, "from_zone": 106})
        self.assertEqual(rows[0].get("transport_id", ""), "")
        self.assertEqual(rows[1]["transport_id"], "palborough-mines-lift")
        self.assertTrue(rows[0]["route_evidence"].startswith("navprobe:Palborough_Mines.nav:"))
        self.assertTrue(rows[1]["route_evidence"].startswith("navprobe:Palborough_Mines.nav:"))

    def test_reviewed_named_npc_target_is_emitted_after_exact_nav_validation(self) -> None:
        natives, pages = self._named_npc_target_fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=self._named_npc_target_overrides(),
                navigation_points=(
                    {
                        "zone": 172,
                        "name": "Makarim",
                        "kind": "npc",
                        "x": -60.925,
                        "z": -333.294,
                        "y": 8.471,
                    },
                ),
                navigation_zone_names={172: "Zeruhn Mines"},
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_mission_bastok.lua"
            ).read_text(encoding="utf-8")
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))

        self.assertIn("route_ready = true", reconcile)
        self.assertIn('zone = 172', reconcile)
        self.assertIn('zone_name = "Zeruhn Mines"', reconcile)
        self.assertIn('name = "Makarim"', reconcile)
        self.assertIn('kind = "npc"', reconcile)
        self.assertIn('arrival_instruction = "Talk to Makarim."', reconcile)
        self.assertEqual(result["counts"]["verified_navigation"], 1)
        self.assertEqual(review["steps"][0]["review_status"], "verified-reviewed-target")
        self.assertTrue(review["steps"][0]["route_ready"])

    def test_exact_named_npc_candidate_is_reported_but_not_activated(self) -> None:
        natives, pages = self._named_npc_target_fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides={"target_overrides": {}},
                navigation_points=(
                    {"zone": 172, "name": "Makarim", "kind": "npc"},
                ),
                navigation_zone_names={172: "Zeruhn Mines"},
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_mission_bastok.lua"
            ).read_text(encoding="utf-8")
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))

        self.assertNotIn("route_ready = true", reconcile)
        self.assertFalse(review["steps"][0]["route_ready"])
        self.assertEqual(
            review["steps"][0]["proposed_navigation_target"],
            {
                "type": "static-reference",
                "zone": 172,
                "zone_name": "Zeruhn Mines",
                "name": "Makarim",
                "kind": "npc",
            },
        )

    def test_object_like_return_target_is_not_proposed_as_a_person(self) -> None:
        natives, pages = self._named_npc_target_fixture(
            bg_name="Trodden Snow",
            ffxi_name="Trodden Snow",
            bg_instruction="Return to the Trodden Snow in Zeruhn Mines.",
            ffxi_instruction="Go back to the Trodden Snow in Zeruhn Mines.",
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides={"target_overrides": {}},
                navigation_points=({"zone": 172, "name": "Trodden Snow", "kind": "npc"},),
                navigation_zone_names={172: "Zeruhn Mines"},
            )
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))

        self.assertIsNone(review["steps"][0].get("proposed_navigation_target"))

    def test_reviewed_named_npc_target_rejects_ambiguous_nav_point(self) -> None:
        natives, pages = self._named_npc_target_fixture()
        duplicate_points = (
            {"zone": 172, "name": "Makarim", "kind": "npc", "x": 1, "z": 2, "y": 3},
            {"zone": 172, "name": "Makarim", "kind": "npc", "x": 4, "z": 5, "y": 6},
        )
        with tempfile.TemporaryDirectory() as temporary, self.assertRaises(GenerationError):
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=self._named_npc_target_overrides(),
                navigation_points=duplicate_points,
                navigation_zone_names={172: "Zeruhn Mines"},
            )

    def test_reviewed_named_npc_target_rejects_changed_source_revision(self) -> None:
        natives, pages = self._named_npc_target_fixture()
        overrides = self._named_npc_target_overrides()
        overrides["target_overrides"]["mission:Bastok:1:step-001"]["source_revisions"]["bg"] = 9999
        with tempfile.TemporaryDirectory() as temporary, self.assertRaises(GenerationError):
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=({"zone": 172, "name": "Makarim", "kind": "npc"},),
                navigation_zone_names={172: "Zeruhn Mines"},
            )

    def test_reviewed_named_npc_target_requires_dual_source_name_and_talk_action(self) -> None:
        nav_points = ({"zone": 172, "name": "Makarim", "kind": "npc"},)
        invalid_fixtures = (
            self._named_npc_target_fixture(ffxi_name="Naji"),
            self._named_npc_target_fixture(ffxi_action="examine"),
        )
        for natives, pages in invalid_fixtures:
            with self.subTest(pages=pages), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                with self.assertRaises(GenerationError):
                    build_guide_artifacts(
                        natives,
                        pages,
                        module_root=root / "modules",
                        data_root=root / "data",
                        reviewed_overrides=self._named_npc_target_overrides(),
                        navigation_points=nav_points,
                        navigation_zone_names={172: "Zeruhn Mines"},
                    )

    def _fixture_overrides(self) -> dict:
        overrides = json.loads(
            (Path(__file__).parents[1] / "data" / "mission-quest-guides" / "reviewed-overrides.json").read_text(
                encoding="utf-8"
            )
        )
        overrides["page_matches"] = {
            "mission:Bastok:2": overrides["page_matches"]["mission:Bastok:2"]
        }
        overrides["shared_page_groups"] = []
        overrides["target_overrides"] = {}
        return overrides

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
        return tuple(parse_objective_page(revision) for revision in self._source_revisions())

    def _source_revisions(self) -> tuple[PageRevision, ...]:
        bg = _fixture_revisions("bg", "bg-api-pages.json", "https://www.bg-wiki.com/api.php")
        ffxi = _fixture_revisions(
            "ffxiclopedia",
            "ffxiclopedia-api-pages.json",
            "https://ffxiclopedia.fandom.com/api.php",
        )
        return (
            bg["Bastok Mission 1-2"],
            bg["Acting in Good Faith"],
            ffxi["A Geological Survey"],
            ffxi["Acting in Good Faith"],
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

    def test_reviewed_shared_page_requires_explicit_consent_for_every_objective(self) -> None:
        natives = (
            NativeObjective("quest", "sandoria", 75, "The Rivalry", "quests.dat", 0, 75),
            NativeObjective("quest", "sandoria", 76, "The Competition", "quests.dat", 0x280, 76),
        )
        page = ParsedObjective(
            site="ffxiclopedia",
            page_id=4506,
            revision_id=123,
            canonical_title="The Rivalry - The Competition",
            kind="quest",
            objective_name="The Rivalry - The Competition",
            steps=(
                SourceStep(1, "*", 1, "Talk to either brother.", "Talk to either brother.", "talk"),
                SourceStep(
                    2,
                    "*",
                    1,
                    "Section: The Competition.",
                    "Section: The Competition.",
                    "note",
                ),
                SourceStep(
                    3,
                    "*",
                    1,
                    "Section: The Competition.",
                    "Section: The Competition.",
                    "note",
                ),
            ),
        )
        unsafe = {
            "page_matches": {
                native.key: {"ffxiclopedia": {"page_id": 4506}}
                for native in natives
            }
        }
        safe = {
            "shared_page_groups": [
                {
                    "site": "ffxiclopedia",
                    "page_id": 4506,
                    "canonical_title": "The Rivalry - The Competition",
                    "native_keys": [native.key for native in natives],
                }
            ]
        }
        wrong_title = {
            "page_matches": {
                natives[0].key: {
                    "ffxiclopedia": {
                        "page_id": 4506,
                        "canonical_title": "A different page",
                    }
                }
            }
        }

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(GenerationError):
                build_guide_artifacts(
                    natives,
                    (page,),
                    module_root=root / "unsafe-modules",
                    data_root=root / "unsafe-data",
                    reviewed_overrides=unsafe,
                )
            with self.assertRaises(GenerationError):
                build_guide_artifacts(
                    natives,
                    (page,),
                    module_root=root / "wrong-title-modules",
                    data_root=root / "wrong-title-data",
                    reviewed_overrides=wrong_title,
                )
            result = build_guide_artifacts(
                natives,
                (page,),
                module_root=root / "safe-modules",
                data_root=root / "safe-data",
                reviewed_overrides=safe,
            )
            reconcile = (root / "safe-modules" / "mission_quest_reconcile_quest_sandoria.lua").read_text(
                encoding="utf-8"
            )

        self.assertEqual(result["counts"]["guide_only"], 2)
        self.assertIn('default_step_id = "quest:sandoria:76:step-002"', reconcile)

    def test_shared_page_default_accepts_a_native_title_with_a_route_suffix(self) -> None:
        natives = (
            NativeObjective(
                "mission",
                "Chains of Promathia",
                14,
                "The Road Forks",
                "missions.dat",
                0,
                14,
            ),
            NativeObjective(
                "mission",
                "Chains of Promathia",
                15,
                "Emerald Waters",
                "missions.dat",
                0x180,
                15,
            ),
        )
        page = ParsedObjective(
            site="bg",
            page_id=5812,
            revision_id=456,
            canonical_title="The Road Forks",
            kind="mission",
            objective_name="The Road Forks",
            steps=(
                SourceStep(1, "*", 1, "Start the mission.", "Start the mission.", "talk"),
                SourceStep(
                    2,
                    "*",
                    1,
                    "Section: Emerald Waters (San d'Oria Path).",
                    "Section: Emerald Waters (San d'Oria Path).",
                    "note",
                ),
                SourceStep(3, "*", 1, "Continue the route.", "Continue the route.", "travel"),
            ),
        )
        overrides = {
            "shared_page_groups": [
                {
                    "site": "bg",
                    "page_id": 5812,
                    "canonical_title": "The Road Forks",
                    "native_keys": [native.key for native in natives],
                }
            ]
        }

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                (page,),
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_mission_chains_of_promathia.lua"
            ).read_text(encoding="utf-8")

        self.assertIn(
            'default_step_id = "mission:Chains of Promathia:15:step-002"',
            reconcile,
        )

    def test_generation_is_deterministic_complete_and_source_separated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            module_root = root / "modules"
            data_root = root / "data"
            source_only = PageRevision(
                site="bg",
                api_url="https://www.bg-wiki.com/api.php",
                canonical_title="Source Only Category Page",
                page_id=9999,
                revision_id=1,
                parent_revision_id=0,
                revision_timestamp="2026-08-08T00:00:00Z",
                content="This page deliberately has no objective header.",
            )
            source_revisions = (*self._source_revisions(), source_only)
            parse_failures = ({
                "site": "bg",
                "page_id": 9999,
                "revision_id": 1,
                "title": "Source Only Category Page",
                "reason": "missing supported objective header",
            },)

            first = build_guide_artifacts(
                self._native_rows(),
                self._source_pages(),
                module_root=module_root,
                data_root=data_root,
                source_revisions=source_revisions,
                parse_failures=parse_failures,
                reviewed_overrides=self._fixture_overrides(),
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
                source_revisions=source_revisions,
                parse_failures=parse_failures,
                reviewed_overrides=self._fixture_overrides(),
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

            mission_reconcile = (
                module_root / "mission_quest_reconcile_mission_bastok.lua"
            ).read_text(encoding="utf-8")
            self.assertIn('["obtain-blue-tester"] = "mission:Bastok:2:step-002"', mission_reconcile)
            self.assertIn('["charge-blue-tester"] = "mission:Bastok:2:step-004"', mission_reconcile)
            self.assertIn('["return-red-tester"] = "mission:Bastok:2:step-005"', mission_reconcile)
            self.assertIn("route_ready = true", mission_reconcile)

            coverage = json.loads((data_root / "coverage.json").read_text(encoding="utf-8"))
            self.assertEqual(coverage["counts"]["valid_native"], 3)
            self.assertEqual(sum(coverage["counts"]["by_status"].values()), 3)
            self.assertEqual(coverage["objectives"]["quest:bastok:92"]["status"], "source-missing")
            self.assertEqual(coverage["objectives"]["mission:Bastok:2"]["status"], "automatic-stage")
            self.assertEqual(len(coverage["objectives"]), 3)
            self.assertEqual(coverage["source_inventory"]["bg:9999"]["status"], "parser-failure")

            target_review = json.loads((data_root / "target-review.json").read_text(encoding="utf-8"))
            acting_reviews = [
                row for row in target_review["steps"] if row["native_key"] == "quest:windurst:77"
            ]
            self.assertTrue(acting_reviews)
            self.assertTrue(all(row["route_ready"] is False for row in acting_reviews))
            self.assertNotIn("selected_candidate_grid", json.dumps(target_review))

            snapshot = json.loads((data_root / "source-snapshot.json").read_text(encoding="utf-8"))
            self.assertTrue(all("content" not in page for page in snapshot["pages"]))
            self.assertEqual(len(snapshot["pages"]), 5)
            self.assertTrue(all(page["content_sha256"] for page in snapshot["pages"]))
            self.assertTrue(all(page["revision_timestamp"] for page in snapshot["pages"]))
            self.assertEqual(
                {page["license"] for page in snapshot["pages"]},
                {"CC-BY-NC-SA-3.0", "CC-BY-SA-3.0"},
            )
            self.assertTrue(all(page["source_url"].startswith("https://") for page in snapshot["pages"]))


if __name__ == "__main__":
    unittest.main()

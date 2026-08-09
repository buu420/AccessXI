from __future__ import annotations

import importlib
import hashlib
import json
import struct
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from tools.objective_guides.model import ManifestError, NativeObjective, SourceActionSpan
from tools.objective_guides.mediawiki import (
    ACCESSXI_USER_AGENT,
    MediaWikiClient,
    MediaWikiError,
    PageRevision,
    load_snapshot,
    recursive_category_pages,
    refresh_snapshot,
    write_snapshot,
)
from tools.objective_guides.wikitext import parse_objective_page
from tools.objective_guides import wikitext as wikitext_parser
from tools.objective_guides.matching import match_objective_pages, normalize_title
from tools.objective_guides.reconcile import ReviewedObjectiveDestination, reconcile_objectives
from tools.objective_guides.objective_destinations import (
    ObjectiveDestinationError,
    resolve_reviewed_objective_destinations,
)
from tools.objective_guides import objective_destinations as action_resolver
from tools.objective_guides import mission_destinations as legacy_mission_resolver
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
from tools import generate_nav_zoneline_destinations as nav_destination_generator


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


def _source_api_url(site: str) -> str:
    return {
        "bg": "https://www.bg-wiki.com/api.php",
        "ffxiclopedia": "https://ffxiclopedia.fandom.com/api.php",
    }[site]


class MediaWikiAcquisitionTests(unittest.TestCase):
    @staticmethod
    def _siteinfo_response(site: str) -> dict:
        project = "BGWiki" if site == "bg" else "FFXIclopedia"
        custom_id = 274 if site == "bg" else 110
        custom_name = "Widget" if site == "bg" else "Forum"
        return {
            "batchcomplete": True,
            "query": {
                "general": {
                    "generator": "MediaWiki 1.43.3",
                    "time": "2026-08-09T12:34:56Z",
                    "wikiid": f"{site}-fixture-wiki",
                },
                "namespaces": {
                    "0": {"id": 0, "case": "first-letter", "content": True, "name": ""},
                    "1": {
                        "id": 1,
                        "case": "first-letter",
                        "canonical": "Talk",
                        "name": "Talk",
                    },
                    "4": {
                        "id": 4,
                        "case": "first-letter",
                        "canonical": "Project",
                        "name": project,
                    },
                    "6": {
                        "id": 6,
                        "case": "first-letter",
                        "canonical": "File",
                        "name": "File",
                    },
                    "14": {
                        "id": 14,
                        "case": "first-letter",
                        "canonical": "Category",
                        "name": "Category",
                    },
                    str(custom_id): {
                        "id": custom_id,
                        "case": "first-letter",
                        "canonical": custom_name,
                        "name": custom_name,
                    },
                },
                "namespacealiases": [{"id": 6, "alias": "Image"}],
                "interwikimap": [
                    {"prefix": "wikipedia", "url": "https://example.invalid/wiki/$1"},
                    {"prefix": "commons", "url": "https://example.invalid/commons/$1"},
                    {
                        "prefix": "de",
                        "language": "Deutsch",
                        "bcp47": "de",
                        "url": "https://example.invalid/de/$1",
                    },
                ],
            },
        }

    def test_mediawiki_client_validates_source_binding_before_assigning_state(self) -> None:
        transport_calls: list[tuple] = []

        def transport(*args, **kwargs):
            transport_calls.append((args, kwargs))
            raise AssertionError("constructor must not call the transport")

        invalid_bindings = (
            ("bg", "https://example.invalid/api.php"),
            ("unsupported", "https://www.bg-wiki.com/api.php"),
            ("bg", "http://www.bg-wiki.com/api.php"),
            ("bg", "https://user:password@www.bg-wiki.com/api.php"),
            ("bg", "https://www.bg-wiki.com/api.php?origin=*"),
            ("bg", "https://www.bg-wiki.com/api.php#fragment"),
            ("bg", "https://www.bg-wiki.com/API.php"),
            ("bg", "https://www.bg-wiki.com:444/api.php"),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for ordinal, (site, api_url) in enumerate(invalid_bindings):
                cache_dir = root / f"cache-{ordinal}"
                request_cache_dir = root / f"requests-{ordinal}"
                candidate = object.__new__(MediaWikiClient)
                with self.subTest(site=site, api_url=api_url):
                    with self.assertRaises(ValueError):
                        MediaWikiClient.__init__(
                            candidate,
                            site,
                            api_url,
                            cache_dir=cache_dir,
                            request_cache_dir=request_cache_dir,
                            transport=transport,
                        )
                    self.assertEqual(candidate.__dict__, {})
                    self.assertFalse(cache_dir.exists())
                    self.assertFalse(request_cache_dir.exists())

        self.assertEqual(transport_calls, [])

        bg = MediaWikiClient(
            "bg",
            "HTTPS://WWW.BG-WIKI.COM:443/api.php",
            transport=transport,
        )
        self.assertEqual(bg.api_url, "https://www.bg-wiki.com/api.php")
        ffxiclopedia = MediaWikiClient(
            "ffxiclopedia",
            "https://ffxiclopedia.fandom.com/api.php",
            transport=transport,
        )
        self.assertEqual(
            ffxiclopedia.api_url,
            "https://ffxiclopedia.fandom.com/api.php",
        )

    def test_cache_revision_validates_binding_before_filesystem_mutation(self) -> None:
        def revision(site: str, api_url: str, page_id: int) -> PageRevision:
            return PageRevision(
                site=site,
                api_url=api_url,
                canonical_title=f"Page {page_id}",
                page_id=page_id,
                revision_id=page_id + 100,
                parent_revision_id=page_id + 99,
                revision_timestamp="2026-08-09T12:34:56Z",
                content=f"content {page_id}",
            )

        wrong_api = revision("bg", "https://example.invalid/api.php", 1)
        no_cache_client = MediaWikiClient(
            "bg",
            "https://www.bg-wiki.com/api.php",
            transport=_ScriptedTransport([]),
        )
        with self.assertRaises(MediaWikiError):
            no_cache_client.cache_revision(wrong_api)

        invalid_revisions = (
            revision("ffxiclopedia", "https://ffxiclopedia.fandom.com/api.php", 2),
            wrong_api,
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for ordinal, page in enumerate(invalid_revisions):
                cache_dir = root / f"invalid-{ordinal}"
                client = MediaWikiClient(
                    "bg",
                    "https://www.bg-wiki.com/api.php",
                    cache_dir=cache_dir,
                    transport=_ScriptedTransport([]),
                )
                self.assertFalse(cache_dir.exists())
                with self.subTest(site=page.site, api_url=page.api_url), self.assertRaises(
                    MediaWikiError
                ):
                    client.cache_revision(page)
                self.assertFalse(cache_dir.exists())

            valid_cache = root / "valid"
            client = MediaWikiClient(
                "bg",
                "HTTPS://WWW.BG-WIKI.COM:443/api.php",
                cache_dir=valid_cache,
                transport=_ScriptedTransport([]),
            )
            page = revision("bg", "https://WWW.BG-WIKI.COM:443/api.php", 3)
            cached_path = client.cache_revision(page)
            self.assertIsNotNone(cached_path)
            assert cached_path is not None
            self.assertTrue(cached_path.is_file())
            self.assertEqual(cached_path.parent, valid_cache / "bg")

    def test_site_config_capture_is_deterministic_and_hash_validated(self) -> None:
        site_config = importlib.import_module("tools.objective_guides.site_config")
        bg_response = self._siteinfo_response("bg")
        ffxi_response = self._siteinfo_response("ffxiclopedia")
        transport = _ScriptedTransport([bg_response])
        client = MediaWikiClient(
            "bg",
            "https://www.bg-wiki.com/api.php",
            transport=transport,
        )

        captured = client.site_info()
        self.assertEqual(captured, bg_response)
        params = transport.calls[0][1]
        self.assertEqual(params["meta"], "siteinfo")
        self.assertEqual(
            params["siprop"],
            "general|namespaces|namespacealiases|interwikimap",
        )

        bg_entry = site_config.site_config_entry_from_response(
            "bg",
            "https://www.bg-wiki.com/api.php",
            captured,
        )
        reversed_response = json.loads(json.dumps(captured))
        reversed_response["query"]["namespaces"] = dict(
            reversed(list(reversed_response["query"]["namespaces"].items()))
        )
        reversed_response["query"]["namespacealiases"].reverse()
        reversed_response["query"]["interwikimap"].reverse()
        self.assertEqual(
            bg_entry,
            site_config.site_config_entry_from_response(
                "bg",
                "https://www.bg-wiki.com/api.php",
                reversed_response,
            ),
        )

        ffxi_entry = site_config.site_config_entry_from_response(
            "ffxiclopedia",
            "https://ffxiclopedia.fandom.com/api.php",
            ffxi_response,
        )
        artifact = site_config.build_site_config_artifact((ffxi_entry, bg_entry))
        self.assertRegex(artifact["payload_sha256"], r"^[0-9a-f]{64}$")
        self.assertEqual(list(artifact["sites"]), ["bg", "ffxiclopedia"])

        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "source-site-config.json"
            path.write_text(json.dumps(artifact), encoding="utf-8")
            policies = site_config.load_site_link_policies(path)
            self.assertEqual(tuple(policies), ("bg", "ffxiclopedia"))
            self.assertEqual(policies["bg"].namespace_id("Widget"), 274)
            self.assertTrue(policies["ffxiclopedia"].is_interwiki("Wikipedia"))
            self.assertTrue(policies["ffxiclopedia"].is_language_interwiki("de"))

            tampered = json.loads(json.dumps(artifact))
            tampered["sites"]["bg"]["interwiki"][0]["prefix"] = "tampered"
            path.write_text(json.dumps(tampered), encoding="utf-8")
            with self.assertRaises(site_config.SiteConfigError):
                site_config.load_site_link_policies(path)

            missing_site = site_config.build_site_config_artifact((bg_entry,))
            path.write_text(json.dumps(missing_site), encoding="utf-8")
            with self.assertRaises(site_config.SiteConfigError):
                site_config.load_site_link_policies(path)

    def test_site_config_capture_rejects_incomplete_siteinfo(self) -> None:
        site_config = importlib.import_module("tools.objective_guides.site_config")
        incomplete = self._siteinfo_response("bg")
        incomplete.pop("batchcomplete")

        with self.assertRaises(site_config.SiteConfigError):
            site_config.site_config_entry_from_response(
                "bg",
                "https://www.bg-wiki.com/api.php",
                incomplete,
            )

    def test_parse_batch_requires_site_policy_for_every_revision(self) -> None:
        site_config = importlib.import_module("tools.objective_guides.site_config")
        objective_cli = importlib.import_module("tools.objective_guides.cli")
        revision = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Strict Site Policy",
            page_id=9336,
            revision_id=127,
            parent_revision_id=126,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Examine [[Door:Orastery]] in [[East Ronfaure]].\n"
            ),
        )

        with self.assertRaises(site_config.SiteConfigError):
            objective_cli._parse_pages((revision,), site_policies={})

    def test_parse_batch_binds_policy_keys_and_revision_api_provenance(self) -> None:
        site_config = importlib.import_module("tools.objective_guides.site_config")
        objective_cli = importlib.import_module("tools.objective_guides.cli")
        policies = site_config.load_default_site_link_policies()

        def revision(site: str, api_url: str, page_id: int, instruction: str) -> PageRevision:
            return PageRevision(
                site=site,
                api_url=api_url,
                canonical_title=f"Bound Site Policy {page_id}",
                page_id=page_id,
                revision_id=page_id + 100,
                parent_revision_id=page_id + 99,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=(
                    "{{Quest Header}}\n==Walkthrough==\n"
                    f"*{instruction}\n"
                ),
            )

        bg = revision(
            "bg",
            "https://www.bg-wiki.com/api.php",
            9360,
            "Examine [[Door:Orastery]] in [[East Ronfaure]].",
        )
        ffxi = revision(
            "ffxiclopedia",
            "https://ffxiclopedia.fandom.com/api.php",
            9361,
            "Talk to [[Trust: Ajido-Marujido]] in [[East Ronfaure]].",
        )

        with self.subTest(case="mapping-key-policy-site"), self.assertRaises(
            site_config.SiteConfigError
        ):
            objective_cli._parse_pages(
                (bg,),
                site_policies={"bg": policies["ffxiclopedia"]},
            )

        with self.subTest(case="mapping-policy-api"), self.assertRaises(
            site_config.SiteConfigError
        ):
            objective_cli._parse_pages(
                (bg,),
                site_policies={
                    "bg": replace(
                        policies["bg"],
                        api_url="https://example.invalid/api.php",
                    )
                },
            )

        with self.subTest(case="revision-api"), self.assertRaises(
            site_config.SiteConfigError
        ):
            objective_cli._parse_pages(
                (replace(bg, api_url="https://example.invalid/api.php"),),
                site_policies=policies,
            )

        parsed, failures = objective_cli._parse_pages(
            (bg, ffxi),
            site_policies=policies,
        )
        self.assertEqual(failures, ())
        self.assertEqual(
            tuple(page.steps[0].action_spans[0].target for page in parsed),
            ("Door:Orastery", "Trust: Ajido-Marujido"),
        )

    def test_refresh_site_config_capture_bypasses_resumable_request_cache(self) -> None:
        objective_cli = importlib.import_module("tools.objective_guides.cli")
        created: list[tuple[str, float]] = []

        class SiteInfoClient:
            def __init__(
                self,
                site: str,
                api_url: str,
                *,
                request_cache_dir: Path,
                min_request_interval: float,
                request_cache_max_age: float = 7200.0,
            ) -> None:
                del api_url, request_cache_dir, min_request_interval
                self.site = site
                created.append((site, request_cache_max_age))

            def site_info(self) -> dict:
                return MediaWikiAcquisitionTests._siteinfo_response(self.site)

            def clear_request_cache(self) -> None:
                pass

        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(
            objective_cli,
            "MediaWikiClient",
            SiteInfoClient,
        ):
            artifact = objective_cli._capture_source_site_config(Path(temporary))

        self.assertEqual(tuple(artifact["sites"]), ("bg", "ffxiclopedia"))
        self.assertEqual(created, [("bg", 0.0), ("ffxiclopedia", 0.0)])

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

    def test_snapshot_load_and_write_bind_site_to_pinned_api(self) -> None:
        cases = (
            (
                "bg",
                "bg-api-pages.json",
                "https://www.bg-wiki.com/api.php",
            ),
            (
                "ffxiclopedia",
                "ffxiclopedia-api-pages.json",
                "https://ffxiclopedia.fandom.com/api.php",
            ),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for site, fixture_name, api_url in cases:
                fixture = _load_api_fixture(fixture_name)
                client = MediaWikiClient(
                    site,
                    api_url,
                    transport=_ScriptedTransport([fixture["response"]]),
                )
                pages = client.fetch_pages(fixture["requested_titles"])
                snapshot = root / f"{site}.json"
                write_snapshot(client, pages, snapshot)
                self.assertEqual(len(load_snapshot(snapshot, expected_site=site)), 2)

                tampered = json.loads(snapshot.read_text(encoding="utf-8"))
                tampered["api_url"] = "https://example.invalid/api.php"
                snapshot.write_text(json.dumps(tampered), encoding="utf-8")
                with self.subTest(site=site, case="tampered-load"), self.assertRaises(
                    MediaWikiError
                ):
                    load_snapshot(snapshot, expected_site=site)

                wrong_client = MediaWikiClient(
                    site,
                    api_url,
                    transport=_ScriptedTransport([]),
                )
                wrong_client.api_url = "https://example.invalid/api.php"
                wrong_snapshot = root / f"{site}-wrong.json"
                with self.subTest(site=site, case="wrong-client-write"), self.assertRaises(
                    MediaWikiError
                ):
                    write_snapshot(wrong_client, pages, wrong_snapshot)
                self.assertFalse(wrong_snapshot.exists())

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
    def test_explicit_site_policy_must_bind_revision_site_and_api(self) -> None:
        site_config = importlib.import_module("tools.objective_guides.site_config")
        policies = site_config.load_default_site_link_policies()

        def revision(site: str, api_url: str, page_id: int, instruction: str) -> PageRevision:
            return PageRevision(
                site=site,
                api_url=api_url,
                canonical_title=f"Explicit Site Policy {page_id}",
                page_id=page_id,
                revision_id=page_id + 100,
                parent_revision_id=page_id + 99,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=(
                    "{{Quest Header}}\n==Walkthrough==\n"
                    f"*{instruction}\n"
                ),
            )

        bg = revision(
            "bg",
            "https://www.bg-wiki.com/api.php",
            9350,
            "Examine [[Door:Orastery]] in [[East Ronfaure]].",
        )
        ffxi = revision(
            "ffxiclopedia",
            "https://ffxiclopedia.fandom.com/api.php",
            9351,
            "Talk to [[Trust: Ajido-Marujido]] in [[East Ronfaure]].",
        )

        with self.subTest(case="wrong-site-policy"), self.assertRaises(
            wikitext_parser.WikitextError
        ):
            parse_objective_page(bg, site_policy=policies["ffxiclopedia"])

        for api_url in (
            "https://example.invalid/api.php",
            "http://www.bg-wiki.com/api.php",
            "https://user@www.bg-wiki.com/api.php",
            "https://www.bg-wiki.com/api.php?site=other",
            "https://www.bg-wiki.com/api.php#other",
            "https://www.bg-wiki.com/API.php",
        ):
            with self.subTest(case="revision-api", api_url=api_url), self.assertRaises(
                wikitext_parser.WikitextError
            ):
                parse_objective_page(
                    replace(bg, api_url=api_url),
                    site_policy=policies["bg"],
                )

        parsed_bg = parse_objective_page(bg, site_policy=policies["bg"])
        parsed_bg_equivalent = parse_objective_page(
            replace(bg, api_url="HTTPS://WWW.BG-WIKI.COM:443/api.php"),
            site_policy=policies["bg"],
        )
        parsed_ffxi = parse_objective_page(ffxi, site_policy=policies["ffxiclopedia"])
        self.assertEqual(
            (
                parsed_bg.steps[0].action_spans[0].target,
                parsed_bg_equivalent.steps[0].action_spans[0].target,
                parsed_ffxi.steps[0].action_spans[0].target,
            ),
            (
                "Door:Orastery",
                "Door:Orastery",
                "Trust: Ajido-Marujido",
            ),
        )

    def test_header_start_entities_require_site_eligible_link_identity(self) -> None:
        natives = (
            NativeObjective(
                "quest",
                "other_areas",
                601,
                "Ambiguous Start Quest",
                "quests.dat",
                0,
                details=("Client: Client A",),
            ),
            NativeObjective(
                "quest",
                "outlands",
                602,
                "Ambiguous Start Quest",
                "quests.dat",
                1,
                details=("Client: Client B",),
            ),
        )

        def parsed(site: str, start_link: str, page_id: int) -> ParsedObjective:
            api_url = (
                "https://www.bg-wiki.com/api.php"
                if site == "bg"
                else "https://ffxiclopedia.fandom.com/api.php"
            )
            return parse_objective_page(
                PageRevision(
                    site=site,
                    api_url=api_url,
                    canonical_title="Ambiguous Start Quest",
                    page_id=page_id,
                    revision_id=page_id + 100,
                    parent_revision_id=page_id + 99,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        f"{{{{Quest Header|Start={start_link}}}}}\n"
                        "==Walkthrough==\n*Talk to the client.\n"
                    ),
                )
            )

        for page_id, site, start_link in (
            (9340, "bg", "[[Wikipedia:Client A|Client A]]"),
            (9341, "bg", "[[Widget:Client A|Client A]]"),
            (9342, "ffxiclopedia", "[[Forum:Client A|Client A]]"),
        ):
            with self.subTest(site=site, start_link=start_link):
                page = parsed(site, start_link, page_id)
                self.assertEqual(page.start_entities, ())
                report = match_objective_pages(natives, (page,))
                self.assertFalse(report.matches)
                self.assertEqual(
                    report.ambiguous_pages[page_id],
                    ("quest:other_areas:601", "quest:outlands:602"),
                )

        for page_id, start_link in (
            (9343, "[[Canonical Client|Client A]]"),
            (9344, "[[Client A#Location|Client A]]"),
        ):
            with self.subTest(start_link=start_link):
                page = parsed("bg", start_link, page_id)
                self.assertEqual(page.start_entities, ("Client A",))
                report = match_objective_pages(natives, (page,))
                self.assertEqual(
                    tuple(match.native_key for match in report.matches),
                    ("quest:other_areas:601",),
                )

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

    def test_safe_wrapper_and_article_keep_linked_qualifier_targets_clause_local(self) -> None:
        cases = (
            (
                "Defeat the N.M. {{Color|red|[[Bugallug]]}} in [[Oldton Movalpolos]], "
                "then talk to [[Cid]] in [[Metalworks]].",
                "Defeat the N.M. Bugallug in Oldton Movalpolos, then talk to Cid in Metalworks.",
                (0, 47),
                (51, 77),
                ("Bugallug", ("Bugallug",), ("Oldton Movalpolos",)),
                ("Cid", ("Cid",), ("Metalworks",)),
            ),
            (
                "Defeat an enemy, e.g. the [[Mob A]] in [[East Ronfaure]], then talk to "
                "[[NPC B]] in [[West Ronfaure]].",
                "Defeat an enemy, e.g. the Mob A in East Ronfaure, then talk to NPC B in West Ronfaure.",
                (0, 50),
                (54, 85),
                ("Mob A", ("Mob A",), ("East Ronfaure",)),
                ("NPC B", ("NPC B",), ("West Ronfaure",)),
            ),
        )
        for (
            instruction,
            expected_source,
            expected_fight_range,
            expected_talk_range,
            expected_fight,
            expected_talk,
        ) in cases:
            with self.subTest(instruction=instruction):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Qualified Wrapped Target",
                    page_id=9325,
                    revision_id=116,
                    parent_revision_id=115,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
                )

                step = parse_objective_page(page).steps[0]
                fight, talk = step.action_spans

                self.assertEqual(step.source_text, expected_source)
                self.assertEqual((fight.text_start, fight.text_end), expected_fight_range)
                self.assertEqual((talk.text_start, talk.text_end), expected_talk_range)
                self.assertEqual(
                    (fight.target, fight.enemy_mentions, fight.zone_mentions),
                    expected_fight,
                )
                self.assertEqual(
                    (talk.target, talk.npc_mentions, talk.zone_mentions),
                    expected_talk,
                )
                self.assertNotRegex(step.source_text, "[\ue000-\ue002]")
                self.assertNotRegex(step.spoken_text, "[\ue000-\ue002]")

    def test_link_aliases_preserve_canonical_identity_and_display_only_speech(self) -> None:
        def step(instruction: str) -> SourceStep:
            page = PageRevision(
                site="bg",
                api_url="https://www.bg-wiki.com/api.php",
                canonical_title="Canonical Link Identity",
                page_id=9326,
                revision_id=117,
                parent_revision_id=116,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0]

        single = step("Defeat [[Mob A|Mob Alpha]] in [[East Ronfaure]].")
        (single_fight,) = single.action_spans
        self.assertEqual(single.source_text, "Defeat Mob Alpha in East Ronfaure.")
        self.assertEqual(single.linked_entities, ("Mob A", "East Ronfaure"))
        self.assertEqual(
            (single_fight.target, single_fight.enemy_mentions),
            ("Mob A", ("Mob A",)),
        )

        ambiguous = step(
            "Defeat [[Mob A|Mob]] and [[Mob B|Mob]] in [[East Ronfaure]]."
        ).action_spans[0]
        self.assertEqual(ambiguous.target, "")
        self.assertEqual(ambiguous.enemy_mentions, ("Mob A", "Mob B"))

        repeated = step(
            "Defeat [[Mob A|Mob]] and [[Mob A|the same mob]] in [[East Ronfaure]]."
        ).action_spans[0]
        self.assertEqual((repeated.target, repeated.enemy_mentions), ("Mob A", ("Mob A",)))

        zone_alias = step(
            "Defeat [[Mob A]] in [[East Ronfaure|the forest]]."
        )
        self.assertEqual(
            zone_alias.source_text,
            "Defeat Mob A in the forest.",
        )
        self.assertEqual(zone_alias.linked_entities, ("Mob A", "East Ronfaure"))
        self.assertEqual(zone_alias.action_spans[0].zone_mentions, ("East Ronfaure",))

    def test_long_spoken_step_uses_link_display_labels_not_hidden_canonical_titles(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Long Display Alias",
            page_id=9328,
            revision_id=119,
            parent_revision_id=118,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Talk to [[Hidden Canonical Title (disambiguation)|Visible NPC]] in "
                "[[East Ronfaure]]. "
                + ("This visible instruction remains part of the walkthrough. " * 12)
                + "\n"
            ),
        )

        step = parse_objective_page(page).steps[0]

        self.assertGreater(len(step.source_text), 420)
        self.assertIn("Visible NPC", step.spoken_text)
        self.assertNotIn("Hidden Canonical Title", step.spoken_text)
        self.assertNotRegex(step.spoken_text, "[\ue000-\ue002]")

    def test_mediawiki_link_identity_normalizes_pages_zones_and_namespaces(self) -> None:
        def step(instruction: str) -> SourceStep:
            page = PageRevision(
                site="bg",
                api_url="https://www.bg-wiki.com/api.php",
                canonical_title="Normalized MediaWiki Identity",
                page_id=9331,
                revision_id=122,
                parent_revision_id=121,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0]

        for link in ("[[Mob_A|Mob A]]", "[[Mob A#Spawn Locations|Mob A]]"):
            with self.subTest(link=link):
                normalized = step(f"Defeat {link} in [[East Ronfaure]].")
                (fight,) = normalized.action_spans
                self.assertEqual(normalized.linked_entities, ("Mob A", "East Ronfaure"))
                self.assertEqual(
                    (fight.target, fight.enemy_mentions, fight.zone_mentions),
                    ("Mob A", ("Mob A",), ("East Ronfaure",)),
                )

        zone_alias = step(
            "Defeat [[Mob_A|Mob A]] in [[East_Ronfaure#Map|the forest]]."
        ).action_spans[0]
        self.assertEqual(zone_alias.zone_mentions, ("East Ronfaure",))

        past_zone = step(
            "Defeat [[Mob_A|Mob A]] in [[East Ronfaure (S)#Map|the past]]."
        ).action_spans[0]
        self.assertEqual(past_zone.zone_mentions, ("East Ronfaure [S]",))
        self.assertEqual(past_zone.temporal_zone_variant, "past")

        namespace_qualified = step(
            "Defeat the N.M. [[:Category:Notorious Monsters|N.M.]] [[Bugallug]] in "
            "[[Oldton Movalpolos]]."
        )
        (bugallug,) = namespace_qualified.action_spans
        self.assertEqual(
            namespace_qualified.source_text,
            "Defeat the N.M. N.M. Bugallug in Oldton Movalpolos.",
        )
        self.assertIn("N.M. Bugallug", namespace_qualified.spoken_text)
        self.assertEqual(
            namespace_qualified.linked_entities,
            ("Bugallug", "Oldton Movalpolos"),
        )
        self.assertEqual(
            (bugallug.target, bugallug.enemy_mentions, bugallug.zone_mentions),
            ("Bugallug", ("Bugallug",), ("Oldton Movalpolos",)),
        )

        for namespace_link, visible_label in (
            ("[[Category:Notorious Monsters|category]]", ""),
            ("[[:Category:Notorious Monsters|category]]", "category"),
            ("[[Talk:Bugallug|discussion]]", "discussion"),
            ("[[:File:Bugallug.png|image]]", "image"),
        ):
            with self.subTest(namespace_link=namespace_link):
                namespaced = step(
                    "Defeat [[Bugallug]] in [[Oldton Movalpolos]] "
                    f"{namespace_link}."
                )
                self.assertEqual(
                    namespaced.linked_entities,
                    ("Bugallug", "Oldton Movalpolos"),
                )
                expected = "Defeat Bugallug in Oldton Movalpolos"
                if visible_label:
                    expected += f" {visible_label}"
                    self.assertIn(visible_label, namespaced.spoken_text)
                self.assertEqual(namespaced.source_text, expected + ".")

        for namespace_link in (
            "[[:Category:Notorious Monsters|category]]",
            "[[:Talk:Bugallug|discussion]]",
            "[[:File:Bugallug.png|image]]",
        ):
            with self.subTest(namespace_link=namespace_link):
                namespaced = step(
                    f"Defeat {namespace_link} in [[Oldton Movalpolos]]."
                )
                self.assertEqual(
                    namespaced.linked_entities,
                    ("Oldton Movalpolos",),
                )
                (namespaced_fight,) = namespaced.action_spans
                self.assertEqual(
                    (namespaced_fight.target, namespaced_fight.enemy_mentions),
                    ("", ()),
                )

        empty_page = step(
            "Defeat [[#Spawn Locations|Mob A]] in [[East Ronfaure]]."
        )
        (empty_fight,) = empty_page.action_spans
        self.assertEqual(empty_page.linked_entities, ("East Ronfaure",))
        self.assertEqual((empty_fight.target, empty_fight.enemy_mentions), ("", ()))

    def test_fragment_display_is_preserved_without_authorizing_entity_routes(self) -> None:
        page = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Fragment Display Identity",
            page_id=9333,
            revision_id=124,
            parent_revision_id=123,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Defeat [[Bivouac#2_Administrator]] in [[East Ronfaure]].\n"
            ),
        )

        parsed = parse_objective_page(page)
        (step,) = parsed.steps
        (fight,) = step.action_spans

        self.assertEqual(
            step.source_text,
            "Defeat Bivouac#2 Administrator in East Ronfaure.",
        )
        self.assertIn("Bivouac#2 Administrator", step.spoken_text)
        self.assertEqual(step.linked_entities, ("East Ronfaure",))
        self.assertEqual((fight.target, fight.enemy_mentions), ("", ()))
        self.assertEqual(fight.zone_mentions, ("East Ronfaure",))
        self.assertEqual(
            step.source_text[fight.text_start : fight.text_end],
            fight.supporting_clause,
        )

    def test_zone_link_evidence_requires_real_untyped_source_link(self) -> None:
        def occurrences(fragment: str) -> tuple[object, ...]:
            return wikitext_parser._render_fragment(fragment)[2]

        (anchored_zone,) = occurrences(
            "[[East Ronfaure#Map|the forest]]"
        )
        self.assertEqual(
            (
                anchored_zone.canonical,
                anchored_zone.display,
                anchored_zone.target_identity,
                anchored_zone.source_link,
                anchored_zone.role,
            ),
            ("East Ronfaure", "the forest", False, True, ""),
        )
        self.assertEqual(
            wikitext_parser._canonical_zone_links_in_range(
                (anchored_zone,),
                0,
                anchored_zone.end,
            ),
            ("East Ronfaure",),
        )

        (typed_only_zone,) = occurrences(
            "{{ItemIcon|East Ronfaure|22}}"
        )
        self.assertEqual(
            (
                typed_only_zone.canonical,
                typed_only_zone.source_link,
                typed_only_zone.role,
            ),
            ("East Ronfaure", False, "item"),
        )
        self.assertEqual(
            wikitext_parser._canonical_zone_links_in_range(
                (typed_only_zone,),
                0,
                typed_only_zone.end,
            ),
            (),
        )

        for display_only_link in (
            "[[:BGWiki:East Ronfaure|East Ronfaure]]",
            "[[:zz:East Ronfaure|East Ronfaure]]",
        ):
            with self.subTest(display_only_link=display_only_link):
                (display_only,) = occurrences(display_only_link)
                self.assertEqual(
                    (
                        display_only.canonical,
                        display_only.display,
                        display_only.target_identity,
                        display_only.source_link,
                    ),
                    ("", "East Ronfaure", False, True),
                )
                self.assertEqual(
                    wikitext_parser._canonical_zone_links_in_range(
                        (display_only,),
                        0,
                        display_only.end,
                    ),
                    (),
                )

    def test_interwiki_links_are_not_entities_but_game_colon_titles_are(self) -> None:
        def step(site: str, instruction: str) -> SourceStep:
            page = PageRevision(
                site=site,
                api_url=(
                    "https://www.bg-wiki.com/api.php"
                    if site == "bg"
                    else "https://ffxiclopedia.fandom.com/api.php"
                ),
                canonical_title="Colon Identity Classification",
                page_id=9334,
                revision_id=125,
                parent_revision_id=124,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0]

        configured_links = (
            ("bg", "[[Wikipedia:Mob A|Mob A]]", True),
            ("bg", "[[:Wiktionary:Mob A|Mob A]]", True),
            ("bg", "[[Commons:Mob A|Mob A]]", True),
            ("bg", "[[fr.be:Mob A|Mob A]]", True),
            ("bg", "[[BGWiki:Mob A|Mob A]]", True),
            ("bg", "[[Widget:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[Wikipedia:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[Wiktionary:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[Commons:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[w:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[fr.be:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[FFXIclopedia:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[Forum:Mob A|Mob A]]", True),
            ("ffxiclopedia", "[[de:Mob A|Mob A]]", False),
            ("ffxiclopedia", "[[:de:Mob A|Mob A]]", True),
        )
        for site, interwiki_link, visible_inline in configured_links:
            with self.subTest(site=site, interwiki_link=interwiki_link):
                interwiki = step(
                    site,
                    f"Defeat {interwiki_link} [[Bugallug]] in [[Oldton Movalpolos]].",
                )
                (fight,) = interwiki.action_spans
                self.assertEqual(
                    interwiki.linked_entities,
                    ("Bugallug", "Oldton Movalpolos"),
                )
                self.assertEqual(
                    (fight.target, fight.enemy_mentions, fight.zone_mentions),
                    ("Bugallug", ("Bugallug",), ("Oldton Movalpolos",)),
                )
                if visible_inline:
                    self.assertIn("Mob A", interwiki.source_text)
                    self.assertIn("Mob A", interwiki.spoken_text)
                else:
                    self.assertNotIn("Mob A", interwiki.source_text)
                    self.assertNotIn("Mob A", interwiki.spoken_text)

                configured_only = step(
                    site,
                    f"Defeat {interwiki_link} in [[Oldton Movalpolos]].",
                )
                (configured_fight,) = configured_only.action_spans
                self.assertEqual(
                    (configured_fight.target, configured_fight.enemy_mentions),
                    ("", ()),
                )

        trust = step(
            "ffxiclopedia",
            "Talk to [[Trust: Ajido-Marujido]] in [[East Ronfaure]].",
        )
        self.assertEqual(
            (trust.linked_entities, trust.action_spans[0].target),
            (("Trust: Ajido-Marujido", "East Ronfaure"), "Trust: Ajido-Marujido"),
        )
        self.assertIn("Trust: Ajido-Marujido", trust.source_text)
        self.assertIn("Trust: Ajido-Marujido", trust.spoken_text)

        door = step("bg", "Examine [[Door:Orastery]] in [[East Ronfaure]].")
        self.assertEqual(
            (door.linked_entities, door.action_spans[0].target),
            (("Door:Orastery", "East Ronfaure"), "Door:Orastery"),
        )

    def test_missing_site_policy_preserves_inline_colon_text_but_fails_targets_closed(self) -> None:
        for instruction, visible_label in (
            (
                "Examine [[Door:Orastery]] in [[East Ronfaure]].",
                "Door:Orastery",
            ),
            (
                "Defeat [[:Wikipedia:Mob A|Mob A]] in [[East Ronfaure]].",
                "Mob A",
            ),
            (
                "Talk to [[Trust: Ajido-Marujido]] in [[East Ronfaure]].",
                "Trust: Ajido-Marujido",
            ),
        ):
            with self.subTest(instruction=instruction):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Missing Site Policy",
                    page_id=9335,
                    revision_id=126,
                    parent_revision_id=125,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*{instruction}\n"
                    ),
                )
                parsed = parse_objective_page(page, site_policy=None)
                (step,) = parsed.steps
                (action,) = step.action_spans
                self.assertEqual(
                    step.linked_entities,
                    ("East Ronfaure",),
                )
                self.assertEqual(
                    (action.target, action.enemy_mentions, action.npc_mentions, action.object_mentions),
                    ("", (), (), ()),
                )
                self.assertIn(visible_label, step.source_text)
                self.assertIn(visible_label, step.spoken_text)

    def test_contained_template_links_keep_item_and_target_roles_separate(self) -> None:
        cases = (
            ("{{Item|[[Bronze Key]]}}", "Bronze Key", False, True),
            ("{{ItemIcon|[[Bronze Key]]}}", "Bronze Key", False, True),
            ("{{KI|[[Bronze Key]]}}", "Bronze Key", True, True),
            ("{{Item|name=[[Bronze Key]]}}", "Bronze Key", False, True),
            ("{{ItemIcon|item=[[Bronze Key]]}}", "Bronze Key", False, True),
            ("{{KI|name=[[Bronze Key]]}}", "Bronze Key", True, True),
            (
                "{{Item|{{Color|red|[[Bronze Key]]}}}}",
                "Bronze Key",
                False,
                True,
            ),
            ("{{Item}}[[Bronze Key]]", "Bronze Key", False, True),
            (
                "{{ItemIcon|Giant Shell Bug|22}} [[Giant Shell Bug]]",
                "Giant Shell Bug",
                False,
                True,
            ),
            (
                "{{ItemIcon|Gallant Leggings|22}}",
                "Gallant Leggings",
                False,
                False,
            ),
        )
        for item_syntax, item_name, is_key_item, is_linked_item in cases:
            with self.subTest(item_syntax=item_syntax):
                page = PageRevision(
                    site="bg",
                    api_url="https://www.bg-wiki.com/api.php",
                    canonical_title="Structural Item Role",
                    page_id=9327,
                    revision_id=118,
                    parent_revision_id=117,
                    revision_timestamp="2026-08-09T00:00:00Z",
                    content=(
                        "{{Quest Header}}\n==Walkthrough==\n"
                        f"*Use {item_syntax} on [[Locked Door]] in [[East Ronfaure]].\n"
                    ),
                )

                step = parse_objective_page(page).steps[0]
                (use,) = step.action_spans

                self.assertEqual((use.target, use.object_mentions), ("Locked Door", ("Locked Door",)))
                self.assertIn(item_name, use.item_mentions)
                self.assertEqual(use.key_item_mentions, (item_name,) if is_key_item else ())
                expected_links = (
                    (item_name, "Locked Door", "East Ronfaure")
                    if is_linked_item
                    else ("Locked Door", "East Ronfaure")
                )
                self.assertEqual(step.linked_entities, expected_links)

        unrelated = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Unrelated Adjacent Item Link",
            page_id=9329,
            revision_id=120,
            parent_revision_id=119,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Use {{ItemIcon|Bronze Key|22}} [[Locked Door]] in [[East Ronfaure]].\n"
            ),
        )
        (unrelated_use,) = parse_objective_page(unrelated).steps[0].action_spans
        self.assertEqual(unrelated_use.target, "Locked Door")
        self.assertIn("Bronze Key", unrelated_use.item_mentions)
        self.assertNotIn("Locked Door", unrelated_use.item_mentions)

        item_only = PageRevision(
            site="bg",
            api_url="https://www.bg-wiki.com/api.php",
            canonical_title="Typed Item Is Not Object",
            page_id=9330,
            revision_id=121,
            parent_revision_id=120,
            revision_timestamp="2026-08-09T00:00:00Z",
            content=(
                "{{Quest Header}}\n==Walkthrough==\n"
                "*Use {{ItemIcon|Gallant Leggings|22}} in [[East Ronfaure]].\n"
            ),
        )
        (item_only_use,) = parse_objective_page(item_only).steps[0].action_spans
        self.assertEqual((item_only_use.target, item_only_use.object_mentions), ("", ()))
        self.assertEqual(item_only_use.item_mentions, ("Gallant Leggings",))

    def test_typed_entity_overlap_blocks_modified_raw_target_fallback(self) -> None:
        def span(instruction: str) -> SourceActionSpan:
            page = PageRevision(
                site="bg",
                api_url="https://www.bg-wiki.com/api.php",
                canonical_title="Typed Entity Modifier",
                page_id=9332,
                revision_id=123,
                parent_revision_id=122,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            return parse_objective_page(page).steps[0].action_spans[0]

        use_item = span(
            "Use one {{ItemIcon|Gallant Leggings|22}} in [[East Ronfaure]]."
        )
        self.assertEqual((use_item.target, use_item.object_mentions), ("", ()))
        self.assertEqual(use_item.item_mentions, ("Gallant Leggings",))
        self.assertEqual(use_item.zone_mentions, ("East Ronfaure",))

        fight_item = span(
            "Defeat the Lv. 75 {{Item|Mob A}} in [[East Ronfaure]]."
        )
        self.assertEqual((fight_item.target, fight_item.enemy_mentions), ("", ()))
        self.assertEqual(fight_item.item_mentions, ("Mob A",))
        self.assertEqual(fight_item.zone_mentions, ("East Ronfaure",))

        independent_target = span(
            "Use one {{ItemIcon|Gallant Leggings|22}} on [[Locked Door]] in "
            "[[East Ronfaure]]."
        )
        self.assertEqual(
            (independent_target.target, independent_target.object_mentions),
            ("Locked Door", ("Locked Door",)),
        )
        self.assertEqual(independent_target.item_mentions, ("Gallant Leggings",))

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

    def test_reviewed_target_key_migration_preserves_collision_chain_values(self) -> None:
        path = Path(__file__).parents[1] / "data" / "mission-quest-guides" / "reviewed-overrides.json"
        targets = json.loads(path.read_text(encoding="utf-8"))["target_overrides"]

        self.assertEqual(len(targets), 505)
        self.assertEqual(targets["mission:Bastok:13:step-002"]["reference"]["name"], "Lucius")
        self.assertEqual(targets["mission:Bastok:13:step-003"]["reference"]["name"], "Goggehn")
        for native_id in range(39, 44):
            prefix = f"mission:Chains of Promathia:{native_id}"
            self.assertEqual(targets[f"{prefix}:step-038"]["reference"]["name"], "Monberaux")
            self.assertEqual(targets[f"{prefix}:step-039"]["reference"]["name"], "Pherimociel")

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
                        api_url=_source_api_url(site),
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
                    api_url=_source_api_url(site),
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
    FIXTURE_CAMP_ID = "camp:v1:101:orcish-fodder:8e9715f6e64706a1d634"
    FIXTURE_CAMP_RAW_IDENTITY = "lsb:mob_spawn_points:group:13:mobname:Orcish_Fodder"
    FIXTURE_CAMP_RAW_SPAWN_IDS = (17191174, 17191228)

    @staticmethod
    def _catalogue_point(
        zone: int,
        name: str,
        kind: str,
        raw_record_id: int,
        *,
        x: float = 1.0,
        z: float = 2.0,
        y: float = 3.0,
    ) -> dict:
        if kind == "enemy":
            raw_identity = (
                f"lsb:mob_spawn_points:group:{raw_record_id}:mobname:"
                + name.replace(" ", "_")
            )
            raw_spawn_ids = (raw_record_id,)
            policy = nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION
            destination_id = nav_destination_generator.enemy_destination_id(
                zone=zone,
                raw_identity=raw_identity,
                raw_spawn_ids=raw_spawn_ids,
                policy_version=policy,
            )
        else:
            raw_identity = (
                f"lsb:zonelines:{raw_record_id}"
                if kind == "area"
                else f"lsb:npc_list:{raw_record_id}"
            )
            raw_spawn_ids = ()
            policy = ""
            destination_id = f"{kind}:v1:{zone}:{raw_record_id}"
        return {
            "zone": zone,
            "name": name,
            "kind": kind,
            "x": x,
            "z": z,
            "y": y,
            "destination_id": destination_id,
            "raw_identity": raw_identity,
            "raw_spawn_ids": raw_spawn_ids,
            "cluster_policy_version": policy,
        }

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
            "destination_id": cls.FIXTURE_CAMP_ID,
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
                    "destination_id": ObjectiveDestinationTests.FIXTURE_CAMP_ID,
                    "raw_identity": ObjectiveDestinationTests.FIXTURE_CAMP_RAW_IDENTITY,
                    "raw_spawn_ids": ObjectiveDestinationTests.FIXTURE_CAMP_RAW_SPAWN_IDS,
                    "cluster_policy_version": nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION,
                },
            ),
            {101: "East Ronfaure"},
        )

    @staticmethod
    def _resolve_literal_instruction(
        *,
        native_id: int,
        instruction: str,
        claim_order: int,
        action: str,
        target_name: str,
        target_kind: str,
        zone: int,
        zone_name: str,
        items: tuple[str, ...] = (),
        enemies: tuple[str, ...] = (),
        use_default_site_policy: bool = True,
    ) -> tuple[ReviewedObjectiveDestination, ...]:
        native = NativeObjective(
            "quest",
            "other_areas",
            native_id,
            f"Literal destination fixture {native_id}",
            "quests.dat",
            0,
        )
        bg_revision = 10000 + (native_id * 2)
        ffxiclopedia_revision = bg_revision + 1

        def page(site: str, revision_id: int) -> ParsedObjective:
            revision = PageRevision(
                site=site,
                api_url=_source_api_url(site),
                canonical_title=native.title,
                page_id=revision_id,
                revision_id=revision_id,
                parent_revision_id=revision_id - 1,
                revision_timestamp="2026-08-09T00:00:00Z",
                content=f"{{{{Quest Header}}}}\n==Walkthrough==\n*{instruction}\n",
            )
            if use_default_site_policy:
                return parse_objective_page(revision)
            return parse_objective_page(revision, site_policy=None)

        bg = page("bg", bg_revision)
        ffxiclopedia = page("ffxiclopedia", ffxiclopedia_revision)
        reconciled = reconcile_objectives(native.key, bg, ffxiclopedia)
        step_id = f"{native.key}:step-001"
        raw_record_id = (zone * 100000) + native_id
        if target_kind == "enemy":
            raw_identity = (
                f"lsb:mob_spawn_points:group:{native_id}:mobname:"
                + target_name.replace(" ", "_")
            )
            raw_spawn_ids = (raw_record_id,)
            cluster_policy_version = nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION
            destination_id = nav_destination_generator.enemy_destination_id(
                zone=zone,
                raw_identity=raw_identity,
                raw_spawn_ids=raw_spawn_ids,
                policy_version=cluster_policy_version,
            )
        else:
            raw_identity = (
                f"lsb:zonelines:{raw_record_id}"
                if target_kind == "area"
                else f"lsb:npc_list:{raw_record_id}"
            )
            raw_spawn_ids = ()
            cluster_policy_version = ""
            destination_id = f"{target_kind}:v1:{zone}:{raw_record_id}"
        overrides = {
            "objective_destination_overrides": {
                native.key: [
                    {
                        "id": "literal-destination-probe",
                        "source_revisions": {
                            "bg": bg_revision,
                            "ffxiclopedia": ffxiclopedia_revision,
                        },
                        "source_step_ids": [step_id],
                        "source_claim_ids": [f"{step_id}:claim-{claim_order:02d}"],
                        "action": action,
                        "items": list(items),
                        "enemies": list(enemies),
                        "destination_id": destination_id,
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
            "destination_id": destination_id,
            "raw_identity": raw_identity,
            "raw_spawn_ids": raw_spawn_ids,
            "cluster_policy_version": cluster_policy_version,
        }
        return resolve_reviewed_objective_destinations(
            native,
            reconciled,
            bg,
            ffxiclopedia,
            overrides,
            (point,),
            {zone: zone_name},
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
            self.assertEqual(rows[0].destination_id, self.FIXTURE_CAMP_ID)
            self.assertEqual(rows[0].target_point, (123.0, 45.0, -2.0))
            self.assertEqual(
                rows[0].source_revisions,
                (("bg", 4001), ("ffxiclopedia", 4002)),
            )
            self.assertEqual(rows[0].eligibility, "catalogue")
            results.append(type(rows[0]))
        self.assertIs(results[0], results[1])

    def test_nonlegacy_override_rejects_identityless_navigation_point(self) -> None:
        native, bg, ffxi, reconciled, overrides = self._fixture("quest")
        with self.assertRaisesRegex(ObjectiveDestinationError, "immutable destination"):
            resolve_reviewed_objective_destinations(
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
                    },
                ),
                {101: "East Ronfaure"},
            )

    def test_nonlegacy_override_rejects_a_different_immutable_destination_id(self) -> None:
        native, bg, ffxi, reconciled, overrides = self._fixture("quest")
        with self.assertRaisesRegex(ObjectiveDestinationError, "destination_id"):
            resolve_reviewed_objective_destinations(
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
                        "x": 289.535,
                        "z": 150.856,
                        "y": -50.375,
                        "destination_id": "camp:v1:101:orcish-fodder:6c7a4f36673f6091fd2c",
                        "raw_identity": "lsb:mob_spawn_points:group:13:mobname:Orcish_Fodder",
                        "raw_spawn_ids": (17191007,),
                        "cluster_policy_version": nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION,
                    },
                ),
                {101: "East Ronfaure"},
            )

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
                        "destination_id": self.FIXTURE_CAMP_ID,
                        "raw_identity": self.FIXTURE_CAMP_RAW_IDENTITY,
                        "raw_spawn_ids": self.FIXTURE_CAMP_RAW_SPAWN_IDS,
                        "cluster_policy_version": nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION,
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
                    api_url=_source_api_url(site),
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
            "destination_id": "npc:v1:101:101083",
            "zone": 101,
            "zone_name": "East Ronfaure",
            "label": "Alpha in East Ronfaure",
            "reference": {"name": "Alpha", "kind": "npc"},
            "arrival_instruction": "Talk to Alpha.",
        }
        overrides = {"objective_destination_overrides": {native.key: [override]}}
        points = (self._catalogue_point(101, "Alpha", "npc", 101083),)

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
                    api_url=_source_api_url(site),
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
            "destination_id": "",
            "zone": 101,
            "zone_name": "East Ronfaure",
            "label": "Orcish Fodder in East Ronfaure",
            "reference": {"name": "Orcish Fodder", "kind": "enemy"},
            "arrival_instruction": "Defeat Orcish Fodder.",
        }
        overrides = {"objective_destination_overrides": {native.key: [override]}}
        point = self._catalogue_point(101, "Orcish Fodder", "enemy", 101084)
        override["destination_id"] = point["destination_id"]
        points = (point,)

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
                    api_url=_source_api_url(site),
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
            "destination_id": "",
            "zone": 100,
            "zone_name": "West Ronfaure",
            "label": "unsafe Mob A in West Ronfaure",
            "reference": {"name": "Mob A", "kind": "enemy"},
            "arrival_instruction": "Defeat Mob A.",
        }
        overrides = {"objective_destination_overrides": {native.key: [override]}}
        west_point = self._catalogue_point(100, "Mob A", "enemy", 100085)
        override["destination_id"] = west_point["destination_id"]

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
                "zone": 101,
                "zone_name": "East Ronfaure",
                "label": "Mob A in East Ronfaure",
            }
        )
        east_point = self._catalogue_point(101, "Mob A", "enemy", 101085)
        override["destination_id"] = east_point["destination_id"]
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
                        api_url=_source_api_url(site),
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
                            "destination_id": "",
                            "zone": zone,
                            "zone_name": zone_name,
                            "label": f"Mob A in {zone_name}",
                            "reference": {"name": "Mob A", "kind": "enemy"},
                            "arrival_instruction": "Defeat Mob A.",
                        }
                    ]
                }
            }
            point = self._catalogue_point(zone, "Mob A", "enemy", (zone * 1000) + 86)
            overrides["objective_destination_overrides"][native.key][0][
                "destination_id"
            ] = point["destination_id"]
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
                        api_url=_source_api_url(site),
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
                        api_url=_source_api_url(site),
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
                    api_url=_source_api_url(site),
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
                        api_url=_source_api_url(site),
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
                        api_url=_source_api_url(site),
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
                    api_url=_source_api_url(site),
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
                            "destination_id": "",
                            "zone": zone,
                            "zone_name": zone_name,
                            "label": f"{target} in {zone_name}",
                            "reference": {"name": target, "kind": kind},
                            "arrival_instruction": f"{action.title()} {target}.",
                        }
                    ]
                }
            }
            point = self._catalogue_point(zone, target, kind, (zone * 1000) + 96)
            overrides["objective_destination_overrides"][native.key][0][
                "destination_id"
            ] = point["destination_id"]
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
                        api_url=_source_api_url(site),
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
                            "destination_id": "",
                            "zone": zone,
                            "zone_name": zone_name,
                            "label": f"{target} in {zone_name}",
                            "reference": {"name": target, "kind": kind},
                            "arrival_instruction": f"{action.title()} {target}.",
                        }
                    ]
                }
            }
            point = self._catalogue_point(zone, target, kind, (zone * 1000) + 98)
            overrides["objective_destination_overrides"][native.key][0][
                "destination_id"
            ] = point["destination_id"]
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
                        api_url=_source_api_url(site),
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
                            "destination_id": "",
                            "zone": 101,
                            "zone_name": "East Ronfaure",
                            "label": f"{target_name} in East Ronfaure",
                            "reference": {"name": target_name, "kind": "enemy"},
                            "arrival_instruction": f"Defeat {target_name}.",
                        }
                    ]
                }
            }
            point = self._catalogue_point(101, target_name, "enemy", 101094)
            overrides["objective_destination_overrides"][native.key][0][
                "destination_id"
            ] = point["destination_id"]
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

    def test_paired_destination_keeps_wrapped_and_article_qualifiers_claim_local(self) -> None:
        cases = (
            (
                201,
                "Defeat the N.M. {{Color|red|[[Bugallug]]}} in [[Oldton Movalpolos]], "
                "then talk to [[Cid]] in [[Metalworks]].",
                "Bugallug",
                "Oldton Movalpolos",
                "Cid",
                "Metalworks",
            ),
            (
                202,
                "Defeat an enemy, e.g. the [[Mob A]] in [[East Ronfaure]], then talk to "
                "[[NPC B]] in [[West Ronfaure]].",
                "Mob A",
                "East Ronfaure",
                "NPC B",
                "West Ronfaure",
            ),
        )
        for native_id, instruction, enemy, enemy_zone, npc, npc_zone in cases:
            with self.subTest(native_id=native_id, route="fight-correct"):
                rows = self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="fight",
                    target_name=enemy,
                    target_kind="enemy",
                    zone=201,
                    zone_name=enemy_zone,
                    enemies=(enemy,),
                )
                self.assertEqual((rows[0].target_name, rows[0].zone_name), (enemy, enemy_zone))

            with self.subTest(native_id=native_id, route="talk-correct"):
                rows = self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=2,
                    action="talk",
                    target_name=npc,
                    target_kind="npc",
                    zone=202,
                    zone_name=npc_zone,
                )
                self.assertEqual((rows[0].target_name, rows[0].zone_name), (npc, npc_zone))

            with self.subTest(native_id=native_id, route="fight-cross-zone"), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="fight",
                    target_name=enemy,
                    target_kind="enemy",
                    zone=202,
                    zone_name=npc_zone,
                    enemies=(enemy,),
                )

            with self.subTest(native_id=native_id, route="talk-cross-zone"), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=2,
                    action="talk",
                    target_name=npc,
                    target_kind="npc",
                    zone=201,
                    zone_name=enemy_zone,
                )

    def test_paired_destination_uses_canonical_link_identity_not_display_aliases(self) -> None:
        single = "Defeat [[Mob A|Mob Alpha]] in [[East Ronfaure]]."
        rows = self._resolve_literal_instruction(
            native_id=203,
            instruction=single,
            claim_order=1,
            action="fight",
            target_name="Mob A",
            target_kind="enemy",
            zone=203,
            zone_name="East Ronfaure",
            enemies=("Mob A",),
        )
        self.assertEqual(rows[0].target_name, "Mob A")

        with self.subTest(case="display-alias"), self.assertRaises(ObjectiveDestinationError):
            self._resolve_literal_instruction(
                native_id=203,
                instruction=single,
                claim_order=1,
                action="fight",
                target_name="Mob Alpha",
                target_kind="enemy",
                zone=203,
                zone_name="East Ronfaure",
                enemies=("Mob Alpha",),
            )

        ambiguous = "Defeat [[Mob A|Mob]] and [[Mob B|Mob]] in [[East Ronfaure]]."
        for target_name in ("Mob", "Mob A", "Mob B"):
            with self.subTest(case="distinct-canonical-ambiguity", target_name=target_name), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=204,
                    instruction=ambiguous,
                    claim_order=1,
                    action="fight",
                    target_name=target_name,
                    target_kind="enemy",
                    zone=204,
                    zone_name="East Ronfaure",
                    enemies=(target_name,),
                )

        repeated = "Defeat [[Mob A|Mob]] and [[Mob A|the same mob]] in [[East Ronfaure]]."
        rows = self._resolve_literal_instruction(
            native_id=205,
            instruction=repeated,
            claim_order=1,
            action="fight",
            target_name="Mob A",
            target_kind="enemy",
            zone=205,
            zone_name="East Ronfaure",
            enemies=("Mob A",),
        )
        self.assertEqual(rows[0].target_name, "Mob A")

        zone_alias_rows = self._resolve_literal_instruction(
            native_id=212,
            instruction="Defeat [[Mob A]] in [[East Ronfaure|the forest]].",
            claim_order=1,
            action="fight",
            target_name="Mob A",
            target_kind="enemy",
            zone=212,
            zone_name="East Ronfaure",
            enemies=("Mob A",),
        )
        self.assertEqual(zone_alias_rows[0].zone_name, "East Ronfaure")

        for native_id, instruction in (
            (206, "Defeat [[Mob A (monster)|Mob A]] in [[East Ronfaure]]."),
            (207, "Defeat [[Mission 1-1|Mob A]] in [[East Ronfaure]]."),
        ):
            with self.subTest(case="unmapped-canonical-title", instruction=instruction), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="fight",
                    target_name="Mob A",
                    target_kind="enemy",
                    zone=native_id,
                    zone_name="East Ronfaure",
                    enemies=("Mob A",),
                )

    def test_paired_destination_normalizes_mediawiki_entity_and_zone_identities(self) -> None:
        cases = (
            (
                220,
                "Defeat [[Mob_A|Mob A]] in [[East Ronfaure]].",
                "Mob A",
                "East Ronfaure",
            ),
            (
                221,
                "Defeat [[Mob A#Spawn Locations|Mob A]] in [[East Ronfaure]].",
                "Mob A",
                "East Ronfaure",
            ),
            (
                222,
                "Defeat [[Mob_A|Mob A]] in [[East_Ronfaure#Map|the forest]].",
                "Mob A",
                "East Ronfaure",
            ),
            (
                223,
                "Defeat [[Mob_A|Mob A]] in [[East Ronfaure (S)#Map|the past]].",
                "Mob A",
                "East Ronfaure [S]",
            ),
            (
                224,
                "Defeat the N.M. [[:Category:Notorious Monsters|N.M.]] "
                "[[Bugallug]] in [[Oldton Movalpolos]].",
                "Bugallug",
                "Oldton Movalpolos",
            ),
        )
        for native_id, instruction, target_name, zone_name in cases:
            with self.subTest(instruction=instruction):
                rows = self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="fight",
                    target_name=target_name,
                    target_kind="enemy",
                    zone=native_id,
                    zone_name=zone_name,
                    enemies=(target_name,),
                )
                self.assertEqual(
                    (rows[0].target_name, rows[0].zone_name),
                    (target_name, zone_name),
                )

        for target_name in ("N.M.", "Category:Notorious Monsters"):
            with self.subTest(namespace_target=target_name), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=224,
                    instruction=cases[-1][1],
                    claim_order=1,
                    action="fight",
                    target_name=target_name,
                    target_kind="enemy",
                    zone=224,
                    zone_name="Oldton Movalpolos",
                    enemies=(target_name,),
                )

        with self.subTest(case="empty-anchored-page"), self.assertRaises(
            ObjectiveDestinationError
        ):
            self._resolve_literal_instruction(
                native_id=225,
                instruction="Defeat [[#Spawn Locations|Mob A]] in [[East Ronfaure]].",
                claim_order=1,
                action="fight",
                target_name="Mob A",
                target_kind="enemy",
                zone=225,
                zone_name="East Ronfaure",
                enemies=("Mob A",),
            )

    def test_paired_destination_rejects_fragment_aliases_and_interwiki_identities(self) -> None:
        fragment_instruction = (
            "Defeat [[Bivouac#2_Administrator]] in [[East Ronfaure]]."
        )
        for target_name in ("Bivouac", "Bivouac#2 Administrator"):
            with self.subTest(fragment_target=target_name), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=229,
                    instruction=fragment_instruction,
                    claim_order=1,
                    action="fight",
                    target_name=target_name,
                    target_kind="enemy",
                    zone=229,
                    zone_name="East Ronfaure",
                    enemies=(target_name,),
                )

        for native_id, interwiki_link, canonical in (
            (230, "[[Wikipedia:Mob A|Mob A]]", "Wikipedia:Mob A"),
            (231, "[[:Wiktionary:Mob A|Mob A]]", "Wiktionary:Mob A"),
            (232, "[[Commons:Mob A|Mob A]]", "Commons:Mob A"),
            (233, "[[:fr.be:Mob A|Mob A]]", "fr.be:Mob A"),
        ):
            instruction = f"Defeat {interwiki_link} in [[East Ronfaure]]."
            for target_name in ("Mob A", canonical):
                with self.subTest(
                    interwiki_link=interwiki_link,
                    target_name=target_name,
                ), self.assertRaises(ObjectiveDestinationError):
                    self._resolve_literal_instruction(
                        native_id=native_id,
                        instruction=instruction,
                        claim_order=1,
                        action="fight",
                        target_name=target_name,
                        target_kind="enemy",
                        zone=native_id,
                        zone_name="East Ronfaure",
                        enemies=(target_name,),
                    )

        for native_id, instruction, action, target_name, target_kind in (
            (
                234,
                "Talk to [[Trust: Ajido-Marujido]] in [[East Ronfaure]].",
                "talk",
                "Trust: Ajido-Marujido",
                "npc",
            ),
            (
                235,
                "Examine [[Door:Orastery]] in [[East Ronfaure]].",
                "examine",
                "Door:Orastery",
                "object",
            ),
        ):
            with self.subTest(game_title=target_name):
                rows = self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action=action,
                    target_name=target_name,
                    target_kind=target_kind,
                    zone=native_id,
                    zone_name="East Ronfaure",
                )
                self.assertEqual(rows[0].target_name, target_name)

    def test_paired_destination_uses_complete_site_policy_and_missing_policy_fails_closed(self) -> None:
        for native_id, prefix in (
            (238, "Wikipedia"),
            (239, "Wiktionary"),
            (240, "Commons"),
            (241, "fr.be"),
        ):
            configured_link = f"[[{prefix}:Notorious Monsters|N.M.]]"
            instruction = (
                f"Defeat the {configured_link} [[Bugallug]] in [[Oldton Movalpolos]], "
                "then talk to [[Cid]] in [[Metalworks]]."
            )

            with self.subTest(prefix=prefix, route="fight-correct"):
                rows = self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="fight",
                    target_name="Bugallug",
                    target_kind="enemy",
                    zone=native_id,
                    zone_name="Oldton Movalpolos",
                    enemies=("Bugallug",),
                )
                self.assertEqual(
                    (rows[0].target_name, rows[0].zone_name),
                    ("Bugallug", "Oldton Movalpolos"),
                )

            with self.subTest(prefix=prefix, route="talk-correct"):
                rows = self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=2,
                    action="talk",
                    target_name="Cid",
                    target_kind="npc",
                    zone=native_id + 100,
                    zone_name="Metalworks",
                )
                self.assertEqual(
                    (rows[0].target_name, rows[0].zone_name),
                    ("Cid", "Metalworks"),
                )

            for target_name in ("N.M.", f"{prefix}:Notorious Monsters"):
                with self.subTest(
                    prefix=prefix,
                    route="configured-prefix-rejected",
                    target_name=target_name,
                ), self.assertRaises(ObjectiveDestinationError):
                    self._resolve_literal_instruction(
                        native_id=native_id,
                        instruction=instruction,
                        claim_order=1,
                        action="fight",
                        target_name=target_name,
                        target_kind="enemy",
                        zone=native_id,
                        zone_name="Oldton Movalpolos",
                        enemies=(target_name,),
                    )

            with self.subTest(prefix=prefix, route="fight-cross-zone"), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="fight",
                    target_name="Bugallug",
                    target_kind="enemy",
                    zone=native_id + 100,
                    zone_name="Metalworks",
                    enemies=("Bugallug",),
                )

        with self.subTest(route="missing-policy-door-colon"), self.assertRaises(
            ObjectiveDestinationError
        ):
            self._resolve_literal_instruction(
                native_id=242,
                instruction="Examine [[Door:Orastery]] in [[East Ronfaure]].",
                claim_order=1,
                action="examine",
                target_name="Door:Orastery",
                target_kind="object",
                zone=242,
                zone_name="East Ronfaure",
                use_default_site_policy=False,
            )

    def test_paired_destination_accepts_structurally_typed_contained_items(self) -> None:
        for native_id, item_syntax, item_name in (
            (208, "{{Item|[[Bronze Key]]}}", "Bronze Key"),
            (209, "{{ItemIcon|[[Bronze Key]]}}", "Bronze Key"),
            (210, "{{KI|[[Bronze Key]]}}", "Bronze Key"),
            (214, "{{Item|name=[[Bronze Key]]}}", "Bronze Key"),
            (215, "{{ItemIcon|item=[[Bronze Key]]}}", "Bronze Key"),
            (216, "{{KI|name=[[Bronze Key]]}}", "Bronze Key"),
            (
                217,
                "{{Item|{{Color|red|[[Bronze Key]]}}}}",
                "Bronze Key",
            ),
            (211, "{{Item}}[[Bronze Key]]", "Bronze Key"),
            (
                213,
                "{{ItemIcon|Giant Shell Bug|22}} [[Giant Shell Bug]]",
                "Giant Shell Bug",
            ),
            (
                218,
                "{{ItemIcon|Gallant Leggings|22}}",
                "Gallant Leggings",
            ),
        ):
            instruction = (
                f"Use {item_syntax} on [[Locked Door]] in [[East Ronfaure]]."
            )
            with self.subTest(item_syntax=item_syntax, route="exact-item"):
                rows = self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="use",
                    target_name="Locked Door",
                    target_kind="object",
                    zone=native_id,
                    zone_name="East Ronfaure",
                    items=(item_name,),
                )
                self.assertEqual(
                    (rows[0].target_name, rows[0].items),
                    ("Locked Door", (item_name,)),
                )

            with self.subTest(item_syntax=item_syntax, route="wrong-item"), self.assertRaises(
                ObjectiveDestinationError
            ):
                self._resolve_literal_instruction(
                    native_id=native_id,
                    instruction=instruction,
                    claim_order=1,
                    action="use",
                    target_name="Locked Door",
                    target_kind="object",
                    zone=native_id,
                    zone_name="East Ronfaure",
                    items=("Iron Key",),
                )

        with self.subTest(route="typed-item-is-not-object"), self.assertRaises(
            ObjectiveDestinationError
        ):
            self._resolve_literal_instruction(
                native_id=219,
                instruction=(
                    "Use {{ItemIcon|Gallant Leggings|22}} in [[East Ronfaure]]."
                ),
                claim_order=1,
                action="use",
                target_name="Gallant Leggings",
                target_kind="object",
                zone=219,
                zone_name="East Ronfaure",
                items=("Gallant Leggings",),
            )

    def test_paired_destination_rejects_modified_typed_entities_as_route_targets(self) -> None:
        with self.subTest(case="modified-item-object"), self.assertRaises(
            ObjectiveDestinationError
        ):
            self._resolve_literal_instruction(
                native_id=226,
                instruction=(
                    "Use one {{ItemIcon|Gallant Leggings|22}} in [[East Ronfaure]]."
                ),
                claim_order=1,
                action="use",
                target_name="one Gallant Leggings",
                target_kind="object",
                zone=226,
                zone_name="East Ronfaure",
                items=("Gallant Leggings",),
            )

        with self.subTest(case="modified-item-enemy"), self.assertRaises(
            ObjectiveDestinationError
        ):
            self._resolve_literal_instruction(
                native_id=227,
                instruction="Defeat the Lv. 75 {{Item|Mob A}} in [[East Ronfaure]].",
                claim_order=1,
                action="fight",
                target_name="Lv. 75 Mob A",
                target_kind="enemy",
                zone=227,
                zone_name="East Ronfaure",
                items=("Mob A",),
                enemies=("Lv. 75 Mob A",),
            )

        rows = self._resolve_literal_instruction(
            native_id=228,
            instruction=(
                "Use one {{ItemIcon|Gallant Leggings|22}} on [[Locked Door]] in "
                "[[East Ronfaure]]."
            ),
            claim_order=1,
            action="use",
            target_name="Locked Door",
            target_kind="object",
            zone=228,
            zone_name="East Ronfaure",
            items=("Gallant Leggings",),
        )
        self.assertEqual(
            (rows[0].target_name, rows[0].items),
            ("Locked Door", ("Gallant Leggings",)),
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
                            api_url=_source_api_url(site),
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
                                "destination_id": "",
                                "zone": 101,
                                "zone_name": "East Ronfaure",
                                "label": f"{target_name} in East Ronfaure",
                                "reference": {"name": target_name, "kind": target_kind},
                                "arrival_instruction": f"{action.title()} {target_name}.",
                            }
                        ]
                    }
                }
                point = self._catalogue_point(
                    101,
                    target_name,
                    target_kind,
                    101000 + native_id,
                )
                overrides["objective_destination_overrides"][native.key][0][
                    "destination_id"
                ] = point["destination_id"]

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
        first["destination_id"] = self.FIXTURE_CAMP_ID
        second["id"] = "alpha-camp"
        second["destination_id"] = self.FIXTURE_CAMP_ID
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

        self.assertEqual(rows, ())

    def test_identityless_legacy_target_is_catalogue_ineligible(self) -> None:
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

        rows = resolve_reviewed_objective_destinations(
            native,
            reconciled,
            bg,
            ffxi,
            legacy,
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

        self.assertEqual(rows, ())

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


class ObjectiveActionResolutionTests(unittest.TestCase):
    @staticmethod
    def _span(
        order: int,
        action: str,
        target: str,
        target_kind: str,
        zone_names: tuple[str, ...] = (),
        *,
        relationship: str | None = None,
        grid: tuple[str, ...] = (),
        item_mentions: tuple[str, ...] = (),
        result_items: tuple[str, ...] = (),
        material: bool = True,
    ) -> SourceActionSpan:
        clause = f"{action.title()} {target or 'as instructed'}"
        mention_fields: dict[str, tuple[str, ...]] = {}
        if target_kind == "npc":
            mention_fields["npc_mentions"] = (target,)
        elif target_kind in {"object", "area", "entrance", "question-mark"}:
            mention_fields["object_mentions"] = (target,)
        elif target_kind == "enemy":
            mention_fields["enemy_mentions"] = (target,)
        elif target_kind == "transport":
            mention_fields["transport_mentions"] = (target,)
        return SourceActionSpan(
            source_step_order=order,
            order=1,
            text_start=0,
            text_end=len(clause),
            supporting_clause=clause,
            action=action,
            verb=action,
            relationship=relationship or f"{action}-target",
            target=target,
            target_kind=target_kind,
            item_mentions=item_mentions,
            zone_mentions=zone_names,
            grid_coordinates=grid,
            result_items=result_items,
            result_relation="obtain-from" if result_items else "",
            material=material,
            **mention_fields,
        )

    @staticmethod
    def _page(
        site: str,
        revision_id: int,
        title: str,
        spans: tuple[SourceActionSpan | None, ...],
        texts: tuple[str, ...] = (),
    ) -> ParsedObjective:
        steps = []
        for index, span in enumerate(spans, start=1):
            text = texts[index - 1] if index <= len(texts) else (
                span.supporting_clause if span is not None else "Historical background for this objective."
            )
            linked = ()
            zones = ()
            grids = ()
            if span is not None:
                linked = tuple(
                    dict.fromkeys(
                        value
                        for value in (
                            span.target,
                            *span.npc_mentions,
                            *span.object_mentions,
                            *span.enemy_mentions,
                            *span.transport_mentions,
                            *span.item_mentions,
                            *span.result_items,
                            *span.zone_mentions,
                        )
                        if value
                    )
                )
                zones = span.zone_mentions
                grids = span.grid_coordinates
            steps.append(
                SourceStep(
                    index,
                    "*",
                    1,
                    text,
                    text,
                    span.action if span is not None else "note",
                    linked_entities=linked,
                    zone_candidates=zones,
                    grid_coordinates=grids,
                    items=tuple(span.item_mentions) if span is not None else (),
                    action_spans=(span,) if span is not None else (),
                )
            )
        return ParsedObjective(
            site=site,
            page_id=revision_id,
            revision_id=revision_id,
            canonical_title=title,
            kind="mission",
            objective_name=title,
            steps=tuple(steps),
        )

    @staticmethod
    def _pinned_orcish_pages() -> tuple[ParsedObjective, ParsedObjective]:
        bg_content = """{{Mission Header
|Mission Name=Smash the Orcish Scouts
|Expansion=sandoria
|Start=Any San d'Oria [[Gate Guard]]
|Description=Mission Orders: Hunt Orcs lurking outside San d'Oria and bring back one of their axes.
|Level=
|Repeatable=Yes
|Previous=
|Next=San d'Oria Mission 1-2{{!}}Bat Hunt
|Title=None
|Reward=*[[Rank Points]]
|Image=
}}

==Walkthrough==\x20
*Speak to any San d'Orian [[Gate Guard]] to begin this Mission.
** [[Ambrotien]] - [[Southern San d'Oria]] (K-10)
** [[Endracion]] - [[Southern San d'Oria]] (F-9)
** [[Grilau]] - [[Northern San d'Oria]] (D-8)
*Go outside the city and kill [[Orcish Fodder]] until you receive an {{ItemIcon|Orcish Axe|22}} [[Orcish Axe]].
**[[Orcish Fodder]] can be found in [[East Ronfaure]] and [[West Ronfaure]].
*After you receive an [[Orcish Axe]] return to the [[Gate Guard]] and trade them the [[Orcish Axe]] to finish the Mission.

[[category:Missions]][[Category:San d'Oria Missions]]"""
        ffxi_content = """[[category:Missions]][[Category:San d'Oria Missions]]
[[de:San d'Oria-Mission 1-1]]
{{Mission
| name = Smash the Orcish Scouts
| number = 1-1
| npc = A [[San d'Orian Gate Guard]]
| requirements =\x20
| level = 1
| title =\x20
| reward = Rank points
| items = [[Orcish Axe]]
| repeatable = Yes
| parent =\x20
| children =\x20
| previous =\x20
| next = [[Bat Hunt]]
| cutscenes =\x20
{{Mission/Cutscene|Smash the Orcish Scouts|[[Gizel]] {{Location|Southern San d'Oria|H-8}}}}
}}

== Walkthrough ==
*Talk to a [[San d'Orian Gate Guard]] to accept the mission.
*Defeat [[Orcish Fodder]] in either [[West Ronfaure]], [[Ghelsba Outpost]] or [[La Theine Plateau]] to obtain an [[Orcish Axe]].
*Return to San d'Oria and trade the Orcish Axe to the San d'Orian Gate Guard to complete the mission.

{{Mission/Description
| orders = Hunt Orcs lurking outside San d'Oria and bring back one of their axes.
}}

{{spoiler2}}"""
        bg_revision = PageRevision(
            "bg",
            "https://www.bg-wiki.com/api.php",
            "San d'Oria Mission 1-1",
            11438,
            766630,
            678629,
            "2026-05-27T17:18:15Z",
            bg_content,
            ("Smash the Orcish Scouts",),
        )
        ffxi_revision = PageRevision(
            "ffxiclopedia",
            "https://ffxiclopedia.fandom.com/api.php",
            "Smash the Orcish Scouts",
            3300,
            1720865,
            1720864,
            "2020-05-21T15:12:29Z",
            ffxi_content,
        )
        if bg_revision.content_sha256 != "e0d5cabd0fa1a409fac83461f930601c7c5d3b70f8a475ba945dcb5d2feb276b":
            raise AssertionError("Pinned BG revision content changed.")
        if ffxi_revision.content_sha256 != "ee90087fef11f944d1d8feffb608e75b576c2690a680413e9ed2d6a1e0a904f5":
            raise AssertionError("Pinned FFXIclopedia revision content changed.")
        return parse_objective_page(bg_revision), parse_objective_page(ffxi_revision)

    @staticmethod
    def _point(
        zone: int,
        zone_name: str,
        name: str,
        kind: str,
        raw_id: int,
        *,
        x: float = 1.0,
        z: float = 2.0,
        y: float = 3.0,
        raw_spawn_ids: tuple[int, ...] = (),
    ) -> dict:
        if kind == "enemy":
            raw_identity = (
                f"lsb:mob_spawn_points:group:{raw_id}:mobname:"
                + name.replace(" ", "_")
            )
            policy = nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION
            destination_id = nav_destination_generator.enemy_destination_id(
                zone=zone,
                raw_identity=raw_identity,
                raw_spawn_ids=raw_spawn_ids,
                policy_version=policy,
            )
        else:
            raw_identity = (
                f"lsb:zonelines:{raw_id}"
                if kind == "area"
                else f"lsb:npc_list:{raw_id}"
            )
            policy = ""
            destination_id = f"{kind}:v1:{zone}:{raw_id}"
        return {
            "zone": zone,
            "zone_name": zone_name,
            "name": name,
            "kind": kind,
            "x": x,
            "z": z,
            "y": y,
            "source": "lsb-test-fixture",
            "confidence": "untested",
            "destination_id": destination_id,
            "raw_identity": raw_identity,
            "raw_spawn_ids": raw_spawn_ids,
            "cluster_policy_version": policy,
        }

    @staticmethod
    def _resolve(
        native: NativeObjective,
        bg: ParsedObjective | None,
        ffxi: ParsedObjective | None,
        points: tuple[dict, ...],
        zone_names: dict[int, str],
        overrides: dict | None = None,
    ) -> object:
        resolver = getattr(action_resolver, "resolve_objective_actions", None)
        if not callable(resolver):
            return SimpleNamespace(ledger=(), candidates=(), groups=(), review_items=())
        reconciled = reconcile_objectives(native.key, bg, ffxi)
        return resolver(
            native,
            reconciled,
            bg,
            ffxi,
            overrides or {},
            points,
            zone_names,
        )

    def _resolve_metadata_override(
        self,
        *,
        native_id: int,
        action: str,
        source_target: str,
        source_kind: str,
        zone: int,
        zone_name: str,
        metadata_class: str,
        point_name: str,
        point_kind: str,
        source_zones: tuple[str, ...] | None = None,
    ) -> object:
        native = NativeObjective(
            "mission",
            "Bastok",
            native_id,
            f"Metadata trust fixture {native_id}",
            "missions.dat",
            0,
        )
        span = self._span(
            1,
            action,
            source_target,
            source_kind,
            (zone_name,) if source_zones is None else source_zones,
        )
        bg_revision = 10000 + native_id
        ffxiclopedia_revision = 20000 + native_id
        bg = self._page("bg", bg_revision, native.title, (span,))
        ffxi = self._page("ffxiclopedia", ffxiclopedia_revision, native.title, (span,))
        action_id = f"{native.key}:step-001:claim-01"
        point = self._point(
            zone,
            zone_name,
            point_name,
            point_kind,
            30000 + native_id,
            raw_spawn_ids=(30000 + native_id,) if point_kind == "enemy" else (),
        )
        metadata = {
            "source_revisions": {
                "bg": bg_revision,
                "ffxiclopedia": ffxiclopedia_revision,
            },
            "class": metadata_class,
            "destination_ids": [point["destination_id"]],
        }
        if metadata_class == "battlefield":
            metadata["battlefield_id"] = "horlais-peak"
        else:
            metadata["transport_id"] = "palborough-mines-lift"
        return self._resolve(
            native,
            bg,
            ffxi,
            (point,),
            {zone: zone_name},
            {"action_metadata_overrides": {action_id: metadata}},
        )

    def test_exact_typed_actions_use_only_the_current_catalogue_kinds(self) -> None:
        native = NativeObjective("mission", "Bastok", 91, "Typed actions", "missions.dat", 0)
        definitions = (
            ("talk", "Alpha", "npc", 101, "East Ronfaure"),
            ("trade", "Beta", "npc", 102, "La Theine Plateau"),
            ("examine", "Door:Orastery", "object", 103, "Valkurm Dunes"),
            ("use", "Ancient Lever", "object", 104, "Jugner Forest"),
            ("fight", "Orcish Fodder", "enemy", 105, "Batallia Downs"),
            ("obtain", "Huge Hornet", "enemy", 106, "North Gustaberg"),
            ("travel", "West Ronfaure zone line", "area", 107, "Northern San d'Oria"),
        )
        spans = tuple(
            self._span(order, action, target, kind, (zone_name,))
            for order, (action, target, kind, _zone, zone_name) in enumerate(definitions, start=1)
        )
        bg = self._page("bg", 9101, native.title, spans)
        ffxi = self._page("ffxiclopedia", 9102, native.title, spans)
        points = tuple(
            self._point(zone, zone_name, target, kind, 9000 + order, raw_spawn_ids=(9000 + order,) if kind == "enemy" else ())
            for order, (action, target, kind, zone, zone_name) in enumerate(definitions, start=1)
        )
        resolution = self._resolve(native, bg, ffxi, points, {row[3]: row[4] for row in definitions})

        self.assertEqual(len(resolution.ledger), 7)
        self.assertEqual({row.status for row in resolution.ledger}, {"catalogue-candidate"})
        self.assertEqual(len(resolution.candidates), 7)
        actual = {candidate.action: candidate.target_kind for candidate in resolution.candidates}
        self.assertEqual(
            actual,
            {
                "talk": "npc",
                "trade": "npc",
                "examine": "object",
                "use": "object",
                "fight": "enemy",
                "obtain": "enemy",
                "travel": "area",
            },
        )
        self.assertTrue(all(candidate.route_ready is False for candidate in resolution.candidates))

    def test_orcish_scouts_keeps_two_reviewed_zone_groups_and_every_camp(self) -> None:
        native = NativeObjective("mission", "San d'Oria", 1, "Smash the Orcish Scouts", "missions.dat", 0)
        bg_span = self._span(
            1,
            "fight",
            "Orcish Fodder",
            "enemy",
            ("East Ronfaure", "West Ronfaure"),
            relationship="defeat-to-obtain",
            result_items=("Orcish Axe",),
        )
        ffxi_span = self._span(
            1,
            "fight",
            "Orcish Fodder",
            "enemy",
            ("West Ronfaure", "Ghelsba Outpost", "La Theine Plateau"),
            relationship="defeat-to-obtain",
            result_items=("Orcish Axe",),
        )
        bg = self._page("bg", 766630, native.title, (bg_span,))
        ffxi = self._page("ffxiclopedia", 1720865, native.title, (ffxi_span,))
        points = (
            self._point(101, "East Ronfaure", "Orcish Fodder", "enemy", 10101, raw_spawn_ids=(10101, 10102)),
            self._point(101, "East Ronfaure", "Orcish Fodder", "enemy", 10103, raw_spawn_ids=(10103,)),
            self._point(100, "West Ronfaure", "Orcish Fodder", "enemy", 10001, raw_spawn_ids=(10001, 10002)),
            self._point(100, "West Ronfaure", "Orcish Fodder", "enemy", 10003, raw_spawn_ids=(10003,)),
            self._point(140, "Ghelsba Outpost", "Orcish Fodder", "enemy", 14001, raw_spawn_ids=(14001,)),
            self._point(102, "La Theine Plateau", "Orcish Fodder", "enemy", 10201, raw_spawn_ids=(10201,)),
            self._point(81, "East Ronfaure [S]", "Orcish Fodder", "enemy", 8101, raw_spawn_ids=(8101,)),
            self._point(141, "Fort Ghelsba", "Orcish Fodder", "enemy", 14101, raw_spawn_ids=(14101,)),
        )
        action_id = "mission:San d'Oria:1:step-001:claim-01"
        overrides = {
            "single_source_zone_overrides": {
                action_id: {
                    "source_revisions": {"bg": 766630, "ffxiclopedia": 1720865},
                    "action": "fight",
                    "target": "Orcish Fodder",
                    "allowed_zones": ["East Ronfaure"],
                    "review_basis": "BG claim plus exact raw LandSandBoat spawn identities",
                }
            }
        }
        zone_names = {point["zone"]: point["zone_name"] for point in points}
        resolution = self._resolve(native, bg, ffxi, points, zone_names, overrides)

        self.assertEqual([group.zone_name for group in resolution.groups], ["East Ronfaure", "West Ronfaure"])
        self.assertEqual([len(group.candidate_ids) for group in resolution.groups], [2, 2])
        self.assertEqual(len(resolution.candidates), 4)
        self.assertEqual(
            {candidate.zone_name for candidate in resolution.candidates},
            {"East Ronfaure", "West Ronfaure"},
        )
        self.assertTrue(
            {"East Ronfaure [S]", "Fort Ghelsba", "Ghelsba Outpost", "La Theine Plateau"}.isdisjoint(
                {candidate.zone_name for candidate in resolution.candidates}
            )
        )
        self.assertEqual(
            {raw_id for candidate in resolution.candidates for raw_id in candidate.raw_spawn_ids},
            {10101, 10102, 10103, 10001, 10002, 10003},
        )
        self.assertEqual(
            [(item.zone_name, item.reason) for item in resolution.review_items],
            [
                ("Ghelsba Outpost", "single-source-needs-independent-corroboration"),
                ("La Theine Plateau", "single-source-needs-independent-corroboration"),
            ],
        )

    def test_pinned_ffxi_plural_causal_zone_list_stays_on_fight_span(self) -> None:
        bg, ffxi = self._pinned_orcish_pages()

        self.assertEqual(bg.steps[5].spoken_text, "Orcish Fodder can be found in East Ronfaure and West Ronfaure.")
        self.assertEqual(bg.steps[5].zone_candidates, ("East Ronfaure", "West Ronfaure"))
        self.assertEqual(bg.steps[5].action_spans, ())
        (fight,) = ffxi.steps[1].action_spans
        self.assertEqual(fight.action, "fight")
        self.assertEqual(fight.target, "Orcish Fodder")
        self.assertEqual(fight.result_relation, "obtain-from")
        self.assertEqual(
            fight.zone_mentions,
            ("West Ronfaure", "Ghelsba Outpost", "La Theine Plateau"),
        )

    def test_pinned_orcish_pages_resolve_only_reviewed_gate_guards_and_east_west_camps(self) -> None:
        native = NativeObjective("mission", "San d'Oria", 1, "Smash the Orcish Scouts", "missions.dat", 0)
        bg, ffxi = self._pinned_orcish_pages()
        fight_action_id = "mission:San d'Oria:1:step-005:claim-01"
        role_action_id = "mission:San d'Oria:1:step-001:claim-01"
        points = (
            self._point(230, "Southern San d'Oria", "Ambrotien", "npc", 17719394),
            self._point(230, "Southern San d'Oria", "Endracion", "npc", 17719393),
            self._point(231, "Northern San d'Oria", "Grilau", "npc", 17723426),
            self._point(101, "East Ronfaure", "Orcish Fodder", "enemy", 34, raw_spawn_ids=(413697, 413698)),
            self._point(101, "East Ronfaure", "Orcish Fodder", "enemy", 35, raw_spawn_ids=(413705,)),
            self._point(100, "West Ronfaure", "Orcish Fodder", "enemy", 36, raw_spawn_ids=(409601, 409602)),
            self._point(100, "West Ronfaure", "Orcish Fodder", "enemy", 37, raw_spawn_ids=(409611,)),
            self._point(140, "Ghelsba Outpost", "Orcish Fodder", "enemy", 38, raw_spawn_ids=(573441,)),
            self._point(102, "La Theine Plateau", "Orcish Fodder", "enemy", 39, raw_spawn_ids=(417793,)),
            self._point(81, "East Ronfaure [S]", "Orcish Fodder", "enemy", 40, raw_spawn_ids=(331777,)),
            self._point(141, "Fort Ghelsba", "Orcish Fodder", "enemy", 41, raw_spawn_ids=(577537,)),
        )
        overrides = {
            "role_overrides": {
                role_action_id: {
                    "source_revisions": {"bg": 766630, "ffxiclopedia": 1720865},
                    "source_roles": ["Gate Guard", "San d'Orian Gate Guard"],
                    "allowed_zones": ["Southern San d'Oria", "Northern San d'Oria"],
                    "members": [
                        {
                            "destination_id": "npc:v1:230:17719394",
                            "name": "Ambrotien",
                            "zone": 230,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-002",
                        },
                        {
                            "destination_id": "npc:v1:230:17719393",
                            "name": "Endracion",
                            "zone": 230,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-003",
                        },
                        {
                            "destination_id": "npc:v1:231:17723426",
                            "name": "Grilau",
                            "zone": 231,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-004",
                        },
                    ],
                    "review_basis": "Exact gate-guard member notes in the pinned BG revision and matching role claim in both pinned guide revisions",
                }
            },
            "single_source_zone_overrides": {
                fight_action_id: {
                    "source_revisions": {"bg": 766630, "ffxiclopedia": 1720865},
                    "action": "fight",
                    "target": "Orcish Fodder",
                    "allowed_zones": ["East Ronfaure"],
                    "location_facts": [
                        {
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-006",
                            "relationship": "target-location",
                            "target": "Orcish Fodder",
                            "zones": ["East Ronfaure", "West Ronfaure"],
                        }
                    ],
                    "review_basis": "Pinned BG target-location fact plus exact raw LandSandBoat spawn identities",
                }
            },
        }
        checked_in_overrides = json.loads(
            (Path(__file__).parents[1] / "data" / "mission-quest-guides" / "reviewed-overrides.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(overrides["role_overrides"], checked_in_overrides["role_overrides"])
        self.assertEqual(
            overrides["single_source_zone_overrides"],
            checked_in_overrides["single_source_zone_overrides"],
        )
        resolution = self._resolve(
            native,
            bg,
            ffxi,
            points,
            {point["zone"]: point["zone_name"] for point in points},
            overrides,
        )

        self.assertEqual(
            [candidate.target_name for candidate in resolution.candidates if candidate.action_id == role_action_id],
            ["Ambrotien", "Endracion", "Grilau"],
        )
        role_ledger = next(row for row in resolution.ledger if row.action_id == role_action_id)
        expected_member_facts = {
            "mission:San d'Oria:1:bg:step-002:role-member-fact-01",
            "mission:San d'Oria:1:bg:step-003:role-member-fact-01",
            "mission:San d'Oria:1:bg:step-004:role-member-fact-01",
        }
        self.assertTrue(expected_member_facts.issubset(role_ledger.source_action_span_ids))
        for candidate in resolution.candidates:
            if candidate.action_id != role_action_id:
                continue
            self.assertEqual(
                len(expected_member_facts.intersection(candidate.source_action_span_ids)),
                1,
            )
        self.assertTrue(
            {
                "mission:San d'Oria:1:step-002:context-01",
                "mission:San d'Oria:1:step-003:context-01",
                "mission:San d'Oria:1:step-004:context-01",
            }.isdisjoint({row.action_id for row in resolution.ledger})
        )
        self.assertEqual(
            [group.zone_name for group in resolution.groups if group.action_id == fight_action_id],
            ["East Ronfaure", "West Ronfaure"],
        )
        location_fact_id = "mission:San d'Oria:1:bg:step-006:location-fact-01"
        fight_ledger = next(row for row in resolution.ledger if row.action_id == fight_action_id)
        self.assertIn(location_fact_id, fight_ledger.source_action_span_ids)
        self.assertTrue(
            all(
                location_fact_id in candidate.source_action_span_ids
                for candidate in resolution.candidates
                if candidate.action_id == fight_action_id
            )
        )
        self.assertNotIn(
            "mission:San d'Oria:1:step-006:context-01",
            {row.action_id for row in resolution.ledger},
        )
        self.assertEqual(
            [(item.zone_name, item.reason) for item in resolution.review_items if item.action_id == fight_action_id],
            [
                ("Ghelsba Outpost", "single-source-needs-independent-corroboration"),
                ("La Theine Plateau", "single-source-needs-independent-corroboration"),
            ],
        )
        self.assertTrue(
            {"East Ronfaure [S]", "Fort Ghelsba"}.isdisjoint(
                {candidate.zone_name for candidate in resolution.candidates}
            )
        )

    def test_pinned_location_fact_override_rejects_stale_target_or_zones(self) -> None:
        native = NativeObjective("mission", "San d'Oria", 1, "Smash the Orcish Scouts", "missions.dat", 0)
        bg, ffxi = self._pinned_orcish_pages()
        action_id = "mission:San d'Oria:1:step-005:claim-01"
        base_override = {
            "single_source_zone_overrides": {
                action_id: {
                    "source_revisions": {"bg": 766630, "ffxiclopedia": 1720865},
                    "action": "fight",
                    "target": "Orcish Fodder",
                    "allowed_zones": ["East Ronfaure"],
                    "location_facts": [
                        {
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-006",
                            "relationship": "target-location",
                            "target": "Orcish Fodder",
                            "zones": ["East Ronfaure", "West Ronfaure"],
                        }
                    ],
                }
            }
        }
        stale_cases = {
            "target": {"target": "Huge Hornet"},
            "zones": {"zones": ["East Ronfaure"]},
            "relationship": {"relationship": "spawn-location"},
            "source-step": {"source_step_id": "mission:San d'Oria:1:bg:step-005"},
            "source-site": {"source_site": "ffxiclopedia"},
        }
        for label, mutation in stale_cases.items():
            override = json.loads(json.dumps(base_override))
            override["single_source_zone_overrides"][action_id]["location_facts"][0].update(mutation)
            with self.subTest(label=label), self.assertRaises(ObjectiveDestinationError):
                self._resolve(
                    native,
                    bg,
                    ffxi,
                    (
                        self._point(
                            101,
                            "East Ronfaure",
                            "Orcish Fodder",
                            "enemy",
                            34,
                            raw_spawn_ids=(413697,),
                        ),
                    ),
                    {101: "East Ronfaure", 100: "West Ronfaure"},
                    override,
                )

    def test_revision_pinned_gate_guard_role_expands_to_three_exact_members(self) -> None:
        native = NativeObjective("mission", "San d'Oria", 1, "Smash the Orcish Scouts", "missions.dat", 0)
        bg, ffxi = self._pinned_orcish_pages()
        points = (
            self._point(230, "Southern San d'Oria", "Ambrotien", "npc", 17719394),
            self._point(230, "Southern San d'Oria", "Endracion", "npc", 17719393),
            self._point(231, "Northern San d'Oria", "Grilau", "npc", 17723426),
        )
        action_id = "mission:San d'Oria:1:step-001:claim-01"
        overrides = {
            "role_overrides": {
                action_id: {
                    "source_revisions": {"bg": 766630, "ffxiclopedia": 1720865},
                    "source_roles": ["Gate Guard", "San d'Orian Gate Guard"],
                    "allowed_zones": ["Southern San d'Oria", "Northern San d'Oria"],
                    "members": [
                        {
                            "destination_id": "npc:v1:230:17719394",
                            "name": "Ambrotien",
                            "zone": 230,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-002",
                        },
                        {
                            "destination_id": "npc:v1:230:17719393",
                            "name": "Endracion",
                            "zone": 230,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-003",
                        },
                        {
                            "destination_id": "npc:v1:231:17723426",
                            "name": "Grilau",
                            "zone": 231,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-004",
                        },
                    ],
                    "review_basis": "Exact gate-guard member list in the pinned guide revision",
                }
            }
        }
        resolution = self._resolve(
            native,
            bg,
            ffxi,
            points,
            {230: "Southern San d'Oria", 231: "Northern San d'Oria"},
            overrides,
        )

        role_ledger = next(row for row in resolution.ledger if row.action_id == action_id)
        self.assertEqual(role_ledger.status, "catalogue-candidate")
        self.assertEqual(
            [candidate.target_name for candidate in resolution.candidates if candidate.action_id == action_id],
            ["Ambrotien", "Endracion", "Grilau"],
        )
        self.assertEqual(
            len({candidate.destination_id for candidate in resolution.candidates if candidate.action_id == action_id}),
            3,
        )

    def test_revision_pinned_role_member_facts_reject_stale_name_zone_step_or_site(self) -> None:
        native = NativeObjective("mission", "San d'Oria", 1, "Smash the Orcish Scouts", "missions.dat", 0)
        bg, ffxi = self._pinned_orcish_pages()
        action_id = "mission:San d'Oria:1:step-001:claim-01"
        base_override = {
            "role_overrides": {
                action_id: {
                    "source_revisions": {"bg": 766630, "ffxiclopedia": 1720865},
                    "source_roles": ["Gate Guard", "San d'Orian Gate Guard"],
                    "allowed_zones": ["Southern San d'Oria", "Northern San d'Oria"],
                    "members": [
                        {
                            "destination_id": "npc:v1:230:17719394",
                            "name": "Ambrotien",
                            "zone": 230,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-002",
                        }
                    ],
                }
            }
        }
        stale_cases = {
            "name": {"name": "Huge Hornet"},
            "zone": {"zone": 231},
            "source-step": {"source_step_id": "mission:San d'Oria:1:bg:step-003"},
            "source-site": {"source_site": "ffxiclopedia"},
        }
        for label, mutation in stale_cases.items():
            override = json.loads(json.dumps(base_override))
            override["role_overrides"][action_id]["members"][0].update(mutation)
            with self.subTest(label=label), self.assertRaises(ObjectiveDestinationError):
                self._resolve(
                    native,
                    bg,
                    ffxi,
                    (self._point(230, "Southern San d'Oria", "Ambrotien", "npc", 17719394),),
                    {230: "Southern San d'Oria", 231: "Northern San d'Oria"},
                    override,
                )

    def test_revision_pinned_role_member_rejects_object_with_matching_name_and_zone(self) -> None:
        native = NativeObjective("mission", "San d'Oria", 1, "Smash the Orcish Scouts", "missions.dat", 0)
        bg, ffxi = self._pinned_orcish_pages()
        action_id = "mission:San d'Oria:1:step-001:claim-01"
        override = {
            "role_overrides": {
                action_id: {
                    "source_revisions": {"bg": 766630, "ffxiclopedia": 1720865},
                    "source_roles": ["Gate Guard", "San d'Orian Gate Guard"],
                    "allowed_zones": ["Southern San d'Oria", "Northern San d'Oria"],
                    "members": [
                        {
                            "destination_id": "object:v1:230:17719394",
                            "name": "Ambrotien",
                            "zone": 230,
                            "source_site": "bg",
                            "source_step_id": "mission:San d'Oria:1:bg:step-002",
                        }
                    ],
                }
            }
        }

        with self.assertRaisesRegex(ObjectiveDestinationError, "NPC"):
            self._resolve(
                native,
                bg,
                ffxi,
                (self._point(230, "Southern San d'Oria", "Ambrotien", "object", 17719394),),
                {230: "Southern San d'Oria", 231: "Northern San d'Oria"},
                override,
            )

    def test_instruction_context_and_unresolved_actions_are_each_accounted_once(self) -> None:
        native = NativeObjective("mission", "Bastok", 92, "Instruction accounting", "missions.dat", 0)
        spans = (
            self._span(1, "wait", "", ""),
            self._span(2, "select", "Yes", "menu-choice"),
            self._span(3, "warning", "Dawn Talisman", "key-item"),
            self._span(4, "protect", "Elvaan and Hume NPCs", "role"),
            None,
        )
        texts = (
            "Wait until the next game day.",
            "Select Yes from the menu.",
            "Do not leave the battlefield or the Dawn Talisman is lost.",
            "Protect the Elvaan and Hume NPCs.",
            "This paragraph is historical background only.",
        )
        bg = self._page("bg", 9201, native.title, spans, texts)
        ffxi = self._page("ffxiclopedia", 9202, native.title, spans, texts)
        context_action_id = "mission:Bastok:92:step-005:context-01"
        overrides = {
            "context_overrides": {
                context_action_id: {
                    "source_revisions": {"bg": 9201, "ffxiclopedia": 9202},
                    "reason": "historical-explanation",
                }
            }
        }
        resolution = self._resolve(native, bg, ffxi, (), {}, overrides)

        self.assertEqual(len(resolution.ledger), 5)
        by_action = {row.action: row for row in resolution.ledger}
        self.assertEqual(by_action["wait"].status, "instruction-only")
        self.assertEqual(by_action["select"].status, "instruction-only")
        self.assertEqual(by_action["warning"].status, "instruction-only")
        self.assertEqual(by_action["protect"].status, "unresolved")
        self.assertEqual(by_action["context"].status, "context-only")
        self.assertEqual(len(resolution.candidates), 0)

    def test_duplicate_static_target_and_coordinate_conflict_fail_closed(self) -> None:
        native = NativeObjective("mission", "Bastok", 93, "Fail closed", "missions.dat", 0)
        bg_span = self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",), grid=("H-8",))
        ffxi_span = self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",), grid=("H-9",))
        bg = self._page("bg", 9301, native.title, (bg_span,))
        ffxi = self._page("ffxiclopedia", 9302, native.title, (ffxi_span,))
        points = (
            self._point(101, "East Ronfaure", "Alpha", "npc", 1, x=1.0),
            self._point(101, "East Ronfaure", "Alpha", "npc", 2, x=10.0),
        )
        resolution = self._resolve(native, bg, ffxi, points, {101: "East Ronfaure"})

        self.assertEqual(len(resolution.ledger), 1)
        self.assertEqual(resolution.ledger[0].status, "conflict")
        self.assertEqual(resolution.ledger[0].reason, "source-conflict")
        self.assertEqual(resolution.ledger[0].candidate_ids, ())
        self.assertEqual(len(resolution.candidates), 0)

        same_coordinate = self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",), grid=("H-8",))
        nonconflicting = self._resolve(
            native,
            self._page("bg", 9301, native.title, (same_coordinate,)),
            self._page("ffxiclopedia", 9302, native.title, (same_coordinate,)),
            points,
            {101: "East Ronfaure"},
        )
        self.assertEqual(nonconflicting.ledger[0].status, "unresolved")
        self.assertEqual(nonconflicting.ledger[0].reason, "ambiguous-static-reference")

    def test_single_source_plus_raw_game_identity_can_yield_a_candidate(self) -> None:
        native = NativeObjective("mission", "Bastok", 94, "Single source", "missions.dat", 0)
        span = self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",))
        bg = self._page("bg", 9401, native.title, (span,))
        resolution = self._resolve(
            native,
            bg,
            None,
            (self._point(101, "East Ronfaure", "Alpha", "npc", 1001),),
            {101: "East Ronfaure"},
        )

        self.assertEqual(len(resolution.ledger), 1)
        self.assertEqual(resolution.ledger[0].status, "catalogue-candidate")
        self.assertEqual(resolution.candidates[0].evidence_level, "single-source+game-data")
        self.assertEqual(resolution.candidates[0].source_sites, ("bg",))
        self.assertEqual(resolution.candidates[0].source_revisions, (("bg", 9401),))

    def test_question_mark_battlefield_and_transport_require_reviewed_metadata(self) -> None:
        native = NativeObjective("mission", "Bastok", 95, "Reviewed metadata", "missions.dat", 0)
        spans = (
            self._span(1, "examine", "???", "question-mark", ("East Ronfaure",)),
            self._span(2, "travel", "Horlais Peak entrance", "entrance", ("Yughott Grotto",)),
            self._span(3, "use", "Mine lift", "transport", ("Palborough Mines",)),
        )
        bg = self._page("bg", 9501, native.title, spans)
        ffxi = self._page("ffxiclopedia", 9502, native.title, spans)
        points = (
            self._point(101, "East Ronfaure", "???", "object", 1011, x=1.0, z=2.0, y=3.0),
            self._point(101, "East Ronfaure", "???", "object", 1012, x=9.0, z=9.0, y=9.0),
            self._point(142, "Yughott Grotto", "Horlais Peak entrance", "area", 1421),
            self._point(143, "Palborough Mines", "Mine lift", "object", 1431),
        )
        prefix = "mission:Bastok:95"
        overrides = {
            "dynamic_target_overrides": {
                f"{prefix}:step-001:claim-01": {
                    "source_revisions": {"bg": 9501, "ffxiclopedia": 9502},
                    "destination_ids": ["object:v1:101:1011"],
                    "target_point": [1.0, 2.0, 3.0],
                }
            },
            "action_metadata_overrides": {
                f"{prefix}:step-002:claim-01": {
                    "source_revisions": {"bg": 9501, "ffxiclopedia": 9502},
                    "class": "battlefield",
                    "destination_ids": ["area:v1:142:1421"],
                    "battlefield_id": "horlais-peak",
                },
                f"{prefix}:step-003:claim-01": {
                    "source_revisions": {"bg": 9501, "ffxiclopedia": 9502},
                    "class": "transport",
                    "destination_ids": ["object:v1:143:1431"],
                    "transport_id": "palborough-mines-lift",
                },
            },
        }
        resolution = self._resolve(
            native,
            bg,
            ffxi,
            points,
            {101: "East Ronfaure", 142: "Yughott Grotto", 143: "Palborough Mines"},
            overrides,
        )

        self.assertEqual([row.status for row in resolution.ledger], ["catalogue-candidate"] * 3)
        by_class = {candidate.metadata_class: candidate for candidate in resolution.candidates}
        self.assertEqual(by_class["dynamic"].destination_id, "object:v1:101:1011")
        self.assertEqual(by_class["battlefield"].battlefield_id, "horlais-peak")
        self.assertEqual(by_class["transport"].transport_id, "palborough-mines-lift")

    def test_battlefield_override_rejects_unrelated_orc_identity(self) -> None:
        with self.assertRaisesRegex(ObjectiveDestinationError, "typed source target"):
            self._resolve_metadata_override(
                native_id=951,
                action="travel",
                source_target="Horlais Peak entrance",
                source_kind="entrance",
                zone=142,
                zone_name="Yughott Grotto",
                metadata_class="battlefield",
                point_name="Unrelated Orc",
                point_kind="enemy",
            )

    def test_transport_override_rejects_cid_identity(self) -> None:
        with self.assertRaisesRegex(ObjectiveDestinationError, "typed source target"):
            self._resolve_metadata_override(
                native_id=952,
                action="use",
                source_target="Mine lift",
                source_kind="transport",
                zone=143,
                zone_name="Palborough Mines",
                metadata_class="transport",
                point_name="Cid",
                point_kind="npc",
            )

    def test_battlefield_override_rejects_stale_area_name(self) -> None:
        with self.assertRaisesRegex(ObjectiveDestinationError, "typed source target"):
            self._resolve_metadata_override(
                native_id=953,
                action="travel",
                source_target="Horlais Peak entrance",
                source_kind="entrance",
                zone=142,
                zone_name="Yughott Grotto",
                metadata_class="battlefield",
                point_name="Unrelated entrance",
                point_kind="area",
            )

    def test_transport_override_rejects_stale_object_name(self) -> None:
        with self.assertRaisesRegex(ObjectiveDestinationError, "typed source target"):
            self._resolve_metadata_override(
                native_id=954,
                action="use",
                source_target="Mine lift",
                source_kind="transport",
                zone=143,
                zone_name="Palborough Mines",
                metadata_class="transport",
                point_name="Wrong lift",
                point_kind="object",
            )

    def test_battlefield_override_rejects_enemy_kind_when_name_matches(self) -> None:
        with self.assertRaisesRegex(ObjectiveDestinationError, "destination kind"):
            self._resolve_metadata_override(
                native_id=955,
                action="travel",
                source_target="Horlais Peak entrance",
                source_kind="entrance",
                zone=142,
                zone_name="Yughott Grotto",
                metadata_class="battlefield",
                point_name="Horlais Peak entrance",
                point_kind="enemy",
            )

    def test_transport_override_rejects_enemy_kind_when_name_matches(self) -> None:
        with self.assertRaisesRegex(ObjectiveDestinationError, "destination kind"):
            self._resolve_metadata_override(
                native_id=956,
                action="use",
                source_target="Mine lift",
                source_kind="transport",
                zone=143,
                zone_name="Palborough Mines",
                metadata_class="transport",
                point_name="Mine lift",
                point_kind="enemy",
            )

    def test_transport_override_rejects_claim_without_same_claim_zone(self) -> None:
        with self.assertRaisesRegex(ObjectiveDestinationError, "source zone"):
            self._resolve_metadata_override(
                native_id=957,
                action="use",
                source_target="Mine lift",
                source_kind="transport",
                zone=143,
                zone_name="Palborough Mines",
                metadata_class="transport",
                point_name="Mine lift",
                point_kind="object",
                source_zones=(),
            )

    def test_distinct_item_sources_have_truthful_separate_instructions(self) -> None:
        native = NativeObjective("mission", "Bastok", 97, "Separate drops", "missions.dat", 0)
        spans = (
            self._span(
                1,
                "obtain",
                "River Crab",
                "enemy",
                ("West Ronfaure",),
                relationship="obtain-from",
                item_mentions=("Crab Shell",),
                result_items=("Crab Shell",),
            ),
            self._span(
                2,
                "obtain",
                "Stag Beetle",
                "enemy",
                ("East Ronfaure",),
                relationship="obtain-from",
                item_mentions=("Beetle Wing",),
                result_items=("Beetle Wing",),
            ),
        )
        bg = self._page("bg", 9701, native.title, spans)
        ffxi = self._page("ffxiclopedia", 9702, native.title, spans)
        resolution = self._resolve(
            native,
            bg,
            ffxi,
            (
                self._point(100, "West Ronfaure", "River Crab", "enemy", 1001, raw_spawn_ids=(1001,)),
                self._point(101, "East Ronfaure", "Stag Beetle", "enemy", 1011, raw_spawn_ids=(1011,)),
            ),
            {100: "West Ronfaure", 101: "East Ronfaure"},
        )

        self.assertEqual(len(resolution.candidates), 2)
        self.assertEqual(
            [candidate.arrival_instruction for candidate in resolution.candidates],
            [
                "Obtain Crab Shell from River Crab in West Ronfaure.",
                "Obtain Beetle Wing from Stag Beetle in East Ronfaure.",
            ],
        )
        self.assertTrue(
            all("complete" not in candidate.arrival_instruction.casefold() for candidate in resolution.candidates)
        )
        self.assertEqual(
            [(candidate.items, candidate.enemies, candidate.result_relation) for candidate in resolution.candidates],
            [
                (("Crab Shell",), ("River Crab",), "obtain-from"),
                (("Beetle Wing",), ("Stag Beetle",), "obtain-from"),
            ],
        )
        self.assertTrue(
            all(candidate.source_revisions == (("bg", 9701), ("ffxiclopedia", 9702)) for candidate in resolution.candidates)
        )

    def test_partial_grid_agreement_stays_candidate_scoped_and_auditable(self) -> None:
        native = NativeObjective("mission", "Bastok", 99, "Partial coordinates", "missions.dat", 0)
        bg_span = self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",), grid=("H-8",))
        ffxi_span = self._span(
            1,
            "talk",
            "Alpha",
            "npc",
            ("East Ronfaure",),
            grid=("H-8", "H-9"),
        )
        resolution = self._resolve(
            native,
            self._page("bg", 9901, native.title, (bg_span,)),
            self._page("ffxiclopedia", 9902, native.title, (ffxi_span,)),
            (self._point(101, "East Ronfaure", "Alpha", "npc", 99001),),
            {101: "East Ronfaure"},
        )

        self.assertEqual(len(resolution.candidates), 1)
        candidate = resolution.candidates[0]
        self.assertEqual(candidate.coordinate_comparison, "partial")
        self.assertEqual(
            candidate.coordinate_support,
            (("bg", "grid", "H-8"), ("ffxiclopedia", "grid", "H-8"), ("ffxiclopedia", "grid", "H-9")),
        )

    def test_ledger_and_candidate_parent_cardinality_are_exact(self) -> None:
        native = NativeObjective("mission", "Bastok", 96, "Ledger accounting", "missions.dat", 0)
        spans = (
            self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",)),
            self._span(2, "fight", "Orcish Fodder", "enemy", ("West Ronfaure",)),
            None,
        )
        bg = self._page("bg", 9601, native.title, spans)
        ffxi = self._page("ffxiclopedia", 9602, native.title, spans)
        resolution = self._resolve(
            native,
            bg,
            ffxi,
            (
                self._point(101, "East Ronfaure", "Alpha", "npc", 1),
                self._point(100, "West Ronfaure", "Orcish Fodder", "enemy", 2, raw_spawn_ids=(2, 3)),
            ),
            {101: "East Ronfaure", 100: "West Ronfaure"},
        )

        expected_action_ids = {
            "mission:Bastok:96:step-001:claim-01",
            "mission:Bastok:96:step-002:claim-01",
            "mission:Bastok:96:step-003:context-01",
        }
        self.assertEqual({row.action_id for row in resolution.ledger}, expected_action_ids)
        self.assertEqual(len(resolution.ledger), len(expected_action_ids))
        self.assertTrue(
            {row.status for row in resolution.ledger}.issubset(
                {"catalogue-candidate", "instruction-only", "context-only", "conflict", "unresolved"}
            )
        )
        self.assertNotIn("routable", {row.status for row in resolution.ledger})
        allowed_reasons = {
            "dual-source-exact-catalogue-match",
            "single-source-independent-game-data",
            "reviewed-role-members",
            "reviewed-single-source-zone",
            "reviewed-dynamic-target",
            "reviewed-battlefield-metadata",
            "reviewed-transport-metadata",
            "missing-action-target",
            "missing-zone",
            "no-exact-catalogue-match",
            "ambiguous-static-reference",
            "dynamic-identity-required",
            "source-conflict",
            "single-source-needs-independent-corroboration",
            "transport-metadata-required",
            "complete-instruction",
            "non-material-context-reason",
            "unsupported-target-class",
        }
        self.assertTrue({row.reason for row in resolution.ledger}.issubset(allowed_reasons))
        span_ids = [span_id for row in resolution.ledger for span_id in row.source_action_span_ids]
        self.assertEqual(len(span_ids), len(set(span_ids)))
        candidate_ids = [candidate.candidate_id for candidate in resolution.candidates]
        self.assertEqual(len(candidate_ids), len(set(candidate_ids)))
        ledger_by_id = {row.action_id: row for row in resolution.ledger}
        for candidate in resolution.candidates:
            self.assertIn(candidate.action_id, ledger_by_id)
            self.assertIn(candidate.candidate_id, ledger_by_id[candidate.action_id].candidate_ids)
            self.assertTrue(
                set(candidate.source_action_span_ids).issubset(
                    set(ledger_by_id[candidate.action_id].source_action_span_ids)
                )
            )
        for row in resolution.ledger:
            self.assertEqual(bool(row.candidate_ids), row.status == "catalogue-candidate")
        group_ids = [group.group_id for group in resolution.groups]
        self.assertEqual(len(group_ids), len(set(group_ids)))
        candidate_by_id = {candidate.candidate_id: candidate for candidate in resolution.candidates}
        seen_group_candidates: set[str] = set()
        for group in resolution.groups:
            self.assertIn(group.action_id, ledger_by_id)
            self.assertEqual(len(group.candidate_ids), len(set(group.candidate_ids)))
            for candidate_id in group.candidate_ids:
                self.assertIn(candidate_id, candidate_by_id)
                self.assertEqual(candidate_by_id[candidate_id].group_id, group.group_id)
                self.assertNotIn(candidate_id, seen_group_candidates)
                seen_group_candidates.add(candidate_id)

    def test_mismatched_typed_relationship_cannot_supply_dual_source_support(self) -> None:
        native = NativeObjective("mission", "Bastok", 100, "Typed mismatch", "missions.dat", 0)
        bg_span = self._span(
            1,
            "talk",
            "Alpha",
            "npc",
            ("East Ronfaure",),
            relationship="talk-to",
        )
        ffxi_span = self._span(
            1,
            "trade",
            "Alpha",
            "npc",
            ("East Ronfaure",),
            relationship="trade-to",
        )
        resolution = self._resolve(
            native,
            self._page("bg", 10001, native.title, (bg_span,)),
            self._page("ffxiclopedia", 10002, native.title, (ffxi_span,)),
            (self._point(101, "East Ronfaure", "Alpha", "npc", 100001),),
            {101: "East Ronfaure"},
        )

        self.assertEqual(len(resolution.ledger), 1)
        self.assertEqual(resolution.ledger[0].status, "unresolved")
        self.assertEqual(
            resolution.ledger[0].reason,
            "single-source-needs-independent-corroboration",
        )
        self.assertEqual(resolution.candidates, ())

    def test_immutable_identity_must_be_congruent_with_kind_zone_raw_id_and_enemy_policy(self) -> None:
        immutable = action_resolver.navigation_point_has_immutable_identity
        static = self._point(101, "East Ronfaure", "Alpha", "npc", 1001)
        self.assertTrue(immutable(static))
        wrong_zone = dict(static, destination_id="npc:v1:999:1001")
        wrong_kind = dict(static, destination_id="object:v1:101:1001")
        wrong_raw_tail = dict(static, raw_identity="lsb:test:2002")
        wrong_raw_source = dict(static, raw_identity="arbitrary:1001")
        self.assertFalse(immutable(wrong_zone))
        self.assertFalse(immutable(wrong_kind))
        self.assertFalse(immutable(wrong_raw_tail))
        self.assertFalse(immutable(wrong_raw_source))

        raw_identity = "lsb:mob_spawn_points:group:34:mobname:Orcish_Fodder"
        spawn_ids = (413697, 413698)
        policy = nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION
        destination_id = nav_destination_generator.enemy_destination_id(
            zone=101,
            raw_identity=raw_identity,
            raw_spawn_ids=spawn_ids,
            policy_version=policy,
        )
        enemy = {
            **self._point(101, "East Ronfaure", "Orcish Fodder", "enemy", 1, raw_spawn_ids=spawn_ids),
            "destination_id": destination_id,
            "raw_identity": raw_identity,
            "cluster_policy_version": policy,
        }
        self.assertTrue(immutable(enemy))
        self.assertFalse(immutable(dict(enemy, name="Amber Quadav")))
        self.assertFalse(immutable(dict(enemy, destination_id=destination_id + "0")))
        self.assertFalse(immutable(dict(enemy, raw_spawn_ids=(413697, 413699))))
        self.assertFalse(immutable(dict(enemy, cluster_policy_version="complete-link-v2-h100-y20")))
        for display_name, raw_name in (
            ("Amber", "Amber_Quadav"),
            ("Garuda", "Garuda_Prime_ASA"),
            ("Tonberry's", "Tonberrys_Avatar"),
            ("Invincible", "Invincible_Shield"),
            ("Goblin", "Goblin_Brigand"),
        ):
            with self.subTest(display_name=display_name, raw_name=raw_name):
                raw_identity = f"lsb:mob_spawn_points:group:34:mobname:{raw_name}"
                truncated = dict(
                    enemy,
                    name=display_name,
                    raw_identity=raw_identity,
                    destination_id=nav_destination_generator.enemy_destination_id(
                        zone=101,
                        raw_identity=raw_identity,
                        raw_spawn_ids=spawn_ids,
                        policy_version=policy,
                    ),
                )
                self.assertFalse(immutable(truncated))
        snow_raw_identity = "lsb:mob_spawn_points:group:9:mobname:Snow_Devil_blm"
        snow_devil = dict(
            enemy,
            name="Snow Devil",
            raw_identity=snow_raw_identity,
            destination_id=nav_destination_generator.enemy_destination_id(
                zone=101,
                raw_identity=snow_raw_identity,
                raw_spawn_ids=spawn_ids,
                policy_version=policy,
            ),
        )
        self.assertTrue(immutable(snow_devil))
        reviewed_name_rows = "".join(
            f"{raw_name}\t{display_name}\n"
            for raw_name, display_name in sorted(
                action_resolver._ENEMY_REVIEWED_DISPLAY_NAMES.items()
            )
        )
        self.assertEqual(len(action_resolver._ENEMY_REVIEWED_DISPLAY_NAMES), 104)
        self.assertEqual(
            hashlib.sha256(reviewed_name_rows.encode("utf-8")).hexdigest(),
            "a88697fc5048b62f60c5d19a86e6075826da94fa01669f46b006e03a4f1dc87d",
        )

    def test_duplicate_canonical_zone_names_fail_closed(self) -> None:
        native = NativeObjective("mission", "Bastok", 101, "Zone alias collision", "missions.dat", 0)
        span = self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",))
        bg = self._page("bg", 10101, native.title, (span,))
        ffxi = self._page("ffxiclopedia", 10102, native.title, (span,))

        with self.assertRaises(ObjectiveDestinationError):
            self._resolve(
                native,
                bg,
                ffxi,
                (self._point(101, "East Ronfaure", "Alpha", "npc", 101001),),
                {101: "East Ronfaure", 999: "East Ronfaure"},
            )

    def test_generated_review_and_lua_emit_the_nonroutable_action_ledger(self) -> None:
        native = NativeObjective("mission", "Bastok", 98, "Generated ledger", "missions.dat", 0)
        bg_span = self._span(1, "talk", "Alpha", "npc", ("East Ronfaure",))
        ffxi_span = self._span(
            1,
            "talk",
            "Alpha",
            "npc",
            ("East Ronfaure", "West Ronfaure"),
        )
        bg = self._page("bg", 9801, native.title, (bg_span,))
        ffxi = self._page("ffxiclopedia", 9802, native.title, (ffxi_span,))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                (native,),
                (bg, ffxi),
                module_root=root / "modules",
                data_root=root / "data",
                navigation_points=(self._point(101, "East Ronfaure", "Alpha", "npc", 98001),),
                navigation_zone_names={101: "East Ronfaure", 100: "West Ronfaure"},
            )
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))
            lua = (root / "modules" / "mission_quest_reconcile_mission_bastok.lua").read_text(
                encoding="utf-8"
            )

        ledger = review.get("action_resolution_ledger", [])
        candidates = review.get("objective_destination_candidates", [])
        review_items = review.get("objective_resolution_review_items", [])
        self.assertEqual(len(ledger), 1)
        self.assertEqual(ledger[0]["status"], "catalogue-candidate")
        self.assertEqual(ledger[0]["candidate_count"], 1)
        self.assertFalse(ledger[0]["route_ready"])
        self.assertEqual(len(candidates), 1)
        self.assertFalse(candidates[0]["route_ready"])
        self.assertEqual(len(review_items), 1)
        self.assertEqual(review_items[0]["zone_name"], "West Ronfaure")
        self.assertEqual(
            review_items[0]["reason"],
            "single-source-needs-independent-corroboration",
        )
        self.assertFalse(review_items[0]["route_ready"])
        self.assertIn("action_resolution_ledger = {", lua)
        self.assertIn("objective_destination_candidates = {", lua)
        self.assertIn("objective_resolution_review_items = {", lua)
        self.assertNotIn('status = "routable"', lua)
        self.assertNotIn("route_ready = true", lua)

    def test_legacy_adapter_discards_free_text_route_authorization(self) -> None:
        native, bg, ffxi, reconciled, _overrides = ObjectiveDestinationTests._fixture("mission")
        override = {
            "mission_destination_overrides": {
                native.key: [
                    {
                        "id": "unsafe-legacy-proof",
                        "source_revisions": {"bg": 4001, "ffxiclopedia": 4002},
                        "source_step_ids": [f"{native.key}:step-001"],
                        "action": "obtain",
                        "items": ["Orcish Axe"],
                        "enemies": ["Orcish Fodder"],
                        "zone": 101,
                        "zone_name": "East Ronfaure",
                        "camp_label": "legacy camp",
                        "reference": {"name": "Orcish Fodder", "kind": "enemy"},
                        "route_evidence": "free text must never authorize",
                        "canonical_ingress": {"edge_id": 1234, "from_zone": 100},
                        "arrival_instruction": "Defeat Orcish Fodder.",
                    }
                ]
            }
        }
        point = self._point(101, "East Ronfaure", "Orcish Fodder", "enemy", 1, raw_spawn_ids=(1,))
        point["confidence"] = "proven"
        rows = legacy_mission_resolver.resolve_reviewed_mission_destinations(
            native,
            reconciled,
            bg,
            ffxi,
            override,
            (point,),
            {101: "East Ronfaure"},
            ({"id": 1234, "from_zone": 100, "to_zone": 101},),
        )

        self.assertEqual(rows, ())


class GeneratedArtifactTests(unittest.TestCase):
    def test_navigation_catalog_loader_uses_exact_tsv_identity_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            destinations = root / "destinations.tsv"
            graph = root / "graph.tsv"
            raw_enemy_identity = "lsb:mob_spawn_points:group:1:mobname:Tunnel_Worm"
            enemy_destination_id = nav_destination_generator.enemy_destination_id(
                zone=172,
                raw_identity=raw_enemy_identity,
                raw_spawn_ids=(1001, 1002),
                policy_version=nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION,
            )
            destinations.write_text(
                "# comment\n"
                "172\tLegacy\t1\t2\t3\tnpc\tmanual\n"
                "172\tMakarim\t-60.925\t-333.294\t8.471\tnpc\tcurrent-nav\tuntested\treview note\n"
                "172\tTunnel Worm\t4\t5\t6\tenemy\tlsb-mob-spawn-camps\tuntested\tcamp note\t"
                f"{enemy_destination_id}\t{raw_enemy_identity}\t"
                "1001,1002\tcomplete-link-v1-h120-y24\n",
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
        self.assertEqual(len(points), 3)
        self.assertEqual(points[0]["zone"], 172)
        self.assertEqual(points[0]["name"], "Legacy")
        self.assertEqual(points[0]["kind"], "npc")
        self.assertEqual(points[0]["confidence"], "")
        self.assertEqual(points[0].get("section", ""), "")
        self.assertEqual(points[0]["note"], "")
        self.assertEqual(points[0].get("destination_id", ""), "")
        self.assertEqual(points[1]["name"], "Makarim")
        self.assertEqual(points[1]["confidence"], "untested")
        self.assertEqual(points[1].get("section", ""), "review note")
        self.assertEqual(points[1]["note"], "review note")
        self.assertEqual(points[1].get("destination_id", ""), "")
        self.assertEqual(points[2].get("destination_id", ""), enemy_destination_id)
        self.assertEqual(
            points[2].get("raw_identity", ""),
            "lsb:mob_spawn_points:group:1:mobname:Tunnel_Worm",
        )
        self.assertEqual(points[2].get("raw_spawn_ids", ()), (1001, 1002))
        self.assertEqual(points[2].get("cluster_policy_version", ""), "complete-link-v1-h120-y24")
        immutable = getattr(action_resolver, "navigation_point_has_immutable_identity", lambda _point: False)
        self.assertFalse(immutable(points[0]))
        self.assertFalse(immutable(points[1]))
        self.assertTrue(immutable(points[2]))
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

    @staticmethod
    def _pinned_fetichism_pages() -> tuple[ParsedObjective, ParsedObjective]:
        bg_content = """{{Mission Header
|Mission Name=Fetichism
|Expansion=bastok
|Start=Any Bastok [[Gate Guard]]
|Description=Hunt the [[Quadav]] in the [[Palborough Mines]] and collect the four parts of a Quadav fetich.
|Level=
|Repeatable=Yes
|Previous=Bastok Mission 1-2{{!}}A Geological Survey
|Next=Bastok Mission 2-1{{!}}The Crystal Line
|Title=
|Reward=*[[Image:Bastok_icon.png|22px|link=Bastok]] Rank 2
*1,000 [[Gil]]
|Image=Fetichism.jpg
}}

==Walkthrough==
* Speak to any Bastokan [[Gate Guard]] to accept the Mission.
* You will have to obtain 4 Fetich pieces ({{ItemIcon|Fetich Head|22}} {{tooltip|text=[[Fetich Head]]|tooltip=[[File:Fetich Head description.png]]}}, {{ItemIcon|Fetich Torso|22}} {{tooltip|text=[[Fetich Torso]]|tooltip=[[File:Fetich Torso description.png]]}}, {{ItemIcon|Fetich Arms|22}} {{tooltip|text=[[Fetich Arms]]|tooltip=[[File:Fetich Arms description.png]]}} and {{ItemIcon|Fetich Legs|22}} {{tooltip|text=[[Fetich Legs]]|tooltip=[[File:Fetich Legs description.png]]}}.)
**The Fetich pieces are not Exclusive, and can be traded or purchased from Bazaars or the [[Auction House]]. ([[File:Auction House 16.png|link=]] ➞ Others ➞ Beast-made)
**Alternatively, you can kill [[Quadav]]s  ([[Amber Quadav]], [[Greater Quadav]], [[Onyx Quadav]], [[Veteran Quadav]]) in [[Palborough Mines]] which drop the 4 Fetich pieces.
*If you elect to get these items yourself and not purchase them, travel to (K-3) in [[North Gustaberg]] to enter [[Palborough Mines]].
** You can reach [[North Gustaberg]] from [[Port Bastok]] (L-7) or [[South Gustaberg]] by zoning at (H-5).
**To get to the higher level Quadav, travel north until you hit the big room at (G-7). Make your way over to (H-7) and head south, turning right at the split, followed by a left. This will put you on a straight path down to (H-9) where you'll follow the bend into a circular room, followed by another bend twisting north and finally end up at the elevator in the center.
** Take the elevator up to the second floor by pulling the lever to make it go up and down.
** This entire floor is filled with [[Onyx Quadav]], [[Greater Quadav]], and [[Veteran Quadav]] about Lv.13 (Be careful of [[Zi'Ghi Boneeater]], a Lvl.15-16 NM).
** '''⚠ Note:''' Using the boat at (H-8) on the second floor will transport you to [[Zeruhn Mines]] and will place you on the other side of a guarded gate. You <u>won't be able to pass this gate to get back</u>, so be careful.
*Once you obtained your 4 Fetich pieces, trade them simultaneously to one of the Bastok [[Gate Guard]]s to complete the Mission.

===Maps===
<gallery>
File:Palborough Mines-map1.jpg | Palborough Mines Map 1
File:Palborough Mines-map2.jpg | Palborough Mines Map 2
File:Palborough Mines-map3.jpg | Palborough Mines Map 3
</gallery>

==Notes==
*The second tier Quadavs in [[Konschtat Highlands]] or [[Pashhow Marshlands]] ([[Onyx Quadav]], [[Greater Quadav]], and [[Veteran Quadav]]) also drop Fetich pieces.

[[Category:Missions]][[Category:Bastok Missions]]"""
        ffxi_content = """[[de:Bastok-Mission 1-3]][[category:Missions]][[Category:Bastok Missions]]
{{Mission
|name=Fetichism
|number=1-3
|requirements=
|level=
|npc=Any [[Bastok Gate Guard]]
|title=
|reward=Rank 2<br>1000gil
|items=[[Fetich Head]]<br>[[Fetich Arms]]<br>[[Fetich Torso]]<br>[[Fetich Legs]]
|repeatable=Yes
|previous=[[A Geological Survey]]
|next=[[The Crystal Line]]
|cutscenes=
{{Mission/Cutscene|Fetichism|[[Lamepaue]] [[Bastok Markets]] (I-8)}}
{{Mission/Cutscene|Fetichism|[[Taulluque]] [[Metalworks]] (I-8)}}
{{Mission/Cutscene|Fetichism|[[Dalba]] [[Port Bastok]] (D-7)}}
{{Mission/Cutscene|Fetichism|[[Gorvik]] [[Bastok Mines]] (I-9)}}
{{Quest/Cutscene|Werei's Disappearance|[[Gorvik]] [[Bastok Mines]] (I-9)}} {{Verification}}
}}

''Recommended: Level 15+ job, preferably [[Thief]].''
== Walkthrough ==

#Receive the mission from a [[Bastok Gate Guard]].
#Trade each of the following items to a guard to complete the mission.
#*[[Fetich Head]] | [[Fetich Arms]] | [[Fetich Torso]] | [[Fetich Legs]]
#**These items can be purchased from the [[Auction House]]. They drop from the following varieties of [[Quadav]]:
#***Amber, Brass, Greater, Old, Onyx, and Veteran.
#**[[Palborough Mines]] is a great place for farming due to the high density of Quadav; you need only ignore Amethyst, Copper, and Young Quadav.
#***[[Palborough Mines/Maps|Palborough Mines]] can be reached from [[North Gustaberg/Maps|North Gustaberg]] at (K-3). It can also be reached by the [[Home Point]] if you've been there before or teleporting to "Waughroon Shrine" via [[Domenic]] (J-7) in [[Lower Jeuno/Maps|Lower Jeuno]] if you have completed [[Beyond Infinity]].
#**The cutscene will differ notably depending on which [[Bastok Gate Guard]] you trade the items to. To view all of the cutscenes you will need four sets of items; however, as they are {{Rare|nc}}, you will need to farm each set one at a time.
#''Optional:'' Talk to [[Gumbah]] (J-7) in an upper-level house in [[Bastok Mines]] for an extra cutscene. {{Verification}}

{{Mission/Description
|orders= Hunt the Quadav in the Palborough Mines and collect the four parts of a Quadav fetich.
}}

{{spoiler2}}"""
        revisions = (
            PageRevision(
                "bg",
                "https://www.bg-wiki.com/api.php",
                "Bastok Mission 1-3",
                303,
                754820,
                754819,
                "2026-01-01T00:00:00Z",
                bg_content,
                ("Fetichism",),
            ),
            PageRevision(
                "ffxiclopedia",
                "https://ffxiclopedia.fandom.com/api.php",
                "Fetichism",
                404,
                1748519,
                1748518,
                "2026-01-01T00:00:00Z",
                ffxi_content,
            ),
        )
        if revisions[0].content_sha256 != "9b81d1d8867dc3971af3ae07fe75cc0855addee18ce6299bbec501d551a46d52":
            raise AssertionError("Pinned Fetichism BG content changed.")
        if revisions[1].content_sha256 != "95280cd294e8e7de21f43cf30cb8b3f839c9a0bcf9d06f6b08da47afabc17f5b":
            raise AssertionError("Pinned Fetichism FFXIclopedia content changed.")
        return tuple(parse_objective_page(revision) for revision in revisions)  # type: ignore[return-value]

    @staticmethod
    def _quadav_nav_point(name: str, raw_spawn_id: int, x: float, z: float, y: float) -> dict:
        raw_identity = f"lsb:mob_spawn_points:group:7:mobname:{name.replace(' ', '_')}"
        policy = nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION
        destination_id = nav_destination_generator.enemy_destination_id(
            zone=143,
            raw_identity=raw_identity,
            raw_spawn_ids=(raw_spawn_id,),
            policy_version=policy,
        )
        return {
            "zone": 143,
            "zone_name": "Palborough Mines",
            "name": name,
            "kind": "enemy",
            "x": x,
            "z": z,
            "y": y,
            "source": "lsb-test-fixture",
            "confidence": "untested",
            "destination_id": destination_id,
            "raw_identity": raw_identity,
            "raw_spawn_ids": (raw_spawn_id,),
            "cluster_policy_version": policy,
        }

    @staticmethod
    def _fetichism_action_migration() -> dict:
        return {
            "mission:Bastok:3": {
                "action_id": "mission:Bastok:3:step-006:claim-01",
                "source_revisions": {"bg": 754820, "ffxiclopedia": 1748519},
                "zone": 143,
                "zone_name": "Palborough Mines",
                "items": ["Fetich Head", "Fetich Torso", "Fetich Arms", "Fetich Legs"],
                "legacy_source_step_ids": [
                    "mission:Bastok:3:step-003",
                    "mission:Bastok:3:step-006",
                ],
                "legacy_source_claim_ids": [],
                "source_facts": {
                    "bg": {
                        "item_step_id": "mission:Bastok:3:bg:step-002",
                        "farming_step_id": "mission:Bastok:3:bg:step-004",
                    },
                    "ffxiclopedia": {
                        "item_step_id": "mission:Bastok:3:ffxiclopedia:step-003",
                        "drop_step_id": "mission:Bastok:3:ffxiclopedia:step-004",
                        "enemy_step_id": "mission:Bastok:3:ffxiclopedia:step-005",
                        "farming_zone_step_id": "mission:Bastok:3:ffxiclopedia:step-006",
                    },
                },
                "mappings": [
                    {
                        "legacy_override_id": "palborough-lower-amber",
                        "enemy_groups": [
                            {
                                "id": "amber-quadav",
                                "enemy": "Amber Quadav",
                                "source_mentions": {
                                    "bg": "Amber Quadav",
                                    "ffxiclopedia": "Amber",
                                },
                            }
                        ],
                    },
                    {
                        "legacy_override_id": "palborough-upper-quadav",
                        "enemy_groups": [
                            {
                                "id": "greater-quadav",
                                "enemy": "Greater Quadav",
                                "source_mentions": {
                                    "bg": "Greater Quadav",
                                    "ffxiclopedia": "Greater",
                                },
                            },
                            {
                                "id": "onyx-quadav",
                                "enemy": "Onyx Quadav",
                                "source_mentions": {
                                    "bg": "Onyx Quadav",
                                    "ffxiclopedia": "Onyx",
                                },
                            },
                            {
                                "id": "veteran-quadav",
                                "enemy": "Veteran Quadav",
                                "source_mentions": {
                                    "bg": "Veteran Quadav",
                                    "ffxiclopedia": "Veteran",
                                },
                            },
                        ],
                    },
                ],
            }
        }

    @staticmethod
    def _amber_nav_point(raw_spawn_id: int, x: float, z: float, y: float) -> dict:
        raw_identity = "lsb:mob_spawn_points:group:7:mobname:Amber_Quadav"
        policy = nav_destination_generator.ENEMY_CLUSTER_POLICY_VERSION
        destination_id = nav_destination_generator.enemy_destination_id(
            zone=143,
            raw_identity=raw_identity,
            raw_spawn_ids=(raw_spawn_id,),
            policy_version=policy,
        )
        return {
            "zone": 143,
            "name": "Amber Quadav",
            "kind": "enemy",
            "x": x,
            "z": z,
            "y": y,
            "confidence": "untested",
            "destination_id": destination_id,
            "raw_identity": raw_identity,
            "raw_spawn_ids": (raw_spawn_id,),
            "cluster_policy_version": policy,
        }

    def test_legacy_farming_destination_with_distinct_camps_is_review_only(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        points = (
            self._amber_nav_point(17362953, 58.904, 123.259, -0.483),
            self._amber_nav_point(17362981, 104.811, 187.422, -2.108),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=points,
                navigation_zone_names={143: "Palborough Mines"},
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_mission_bastok.lua"
            ).read_text(encoding="utf-8")
            review = json.loads(
                (root / "data" / "target-review.json").read_text(encoding="utf-8")
            )

        self.assertNotIn("objective_destinations = {", reconcile)
        self.assertNotIn("mission_destinations = {", reconcile)
        self.assertIn("objective_destination_candidates = {", reconcile)
        self.assertNotIn("route_evidence", reconcile)
        self.assertEqual(review["objective_destinations"], [])
        candidates = [
            row for row in review["objective_destination_candidates"]
            if row["native_key"] == "mission:Bastok:3"
        ]
        self.assertEqual(
            {row["destination_id"] for row in candidates},
            {point["destination_id"] for point in points},
        )
        self.assertTrue(all(row["route_ready"] is False for row in candidates))

    def test_legacy_mission_destination_with_unknown_ingress_is_skipped(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        destination = overrides["mission_destination_overrides"]["mission:Bastok:3"][0]
        destination["canonical_ingress"] = {"edge_id": 999999, "from_zone": 106}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(self._amber_nav_point(17362953, 58.904, 123.259, -0.483),),
                navigation_zone_names={143: "Palborough Mines"},
            )
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))

        self.assertEqual(review["objective_destinations"], [])

    def test_legacy_mission_destination_with_unclaimed_item_is_skipped(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        destination = overrides["mission_destination_overrides"]["mission:Bastok:3"][0]
        destination["items"] = [*destination["items"], "Imaginary Fetich"]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(self._amber_nav_point(17362953, 58.904, 123.259, -0.483),),
                navigation_zone_names={143: "Palborough Mines"},
            )
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))

        self.assertEqual(review["objective_destinations"], [])

    def test_pinned_fetichism_migrates_every_legacy_row_to_four_exact_enemy_groups(self) -> None:
        native = NativeObjective("mission", "Bastok", 3, "Fetichism", "missions.dat", 0, 2)
        bg, ffxi = self._pinned_fetichism_pages()
        checked_in = json.loads(
            (
                Path(__file__).parents[1]
                / "data"
                / "mission-quest-guides"
                / "reviewed-overrides.json"
            ).read_text(encoding="utf-8")
        )
        expected_migration = self._fetichism_action_migration()
        self.assertEqual(
            checked_in.get("legacy_action_migrations"),
            expected_migration,
            "the reviewed migration must be revision-pinned and checked in",
        )
        overrides = {
            "mission_destination_overrides": {
                native.key: checked_in["mission_destination_overrides"][native.key]
            },
            "legacy_action_migrations": expected_migration,
        }
        points = (
            self._quadav_nav_point("Amber Quadav", 17362953, 58.904, 123.259, -0.483),
            self._quadav_nav_point("Amber Quadav", 17362981, 104.811, 187.422, -2.108),
            self._quadav_nav_point("Greater Quadav", 17363001, 201.0, 301.0, 8.0),
            self._quadav_nav_point("Onyx Quadav", 17363011, 221.0, 321.0, 12.0),
            self._quadav_nav_point("Onyx Quadav", 17363012, 331.0, 431.0, 16.0),
            self._quadav_nav_point("Veteran Quadav", 17363021, 241.0, 341.0, 12.0),
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                (native,),
                (bg, ffxi),
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=points,
                navigation_zone_names={143: "Palborough Mines"},
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_mission_bastok.lua"
            ).read_text(encoding="utf-8")
            review = json.loads(
                (root / "data" / "target-review.json").read_text(encoding="utf-8")
            )

        action_id = "mission:Bastok:3:step-006:claim-01"
        groups = [
            row
            for row in review["objective_destination_groups"]
            if row["native_key"] == native.key and row["action_id"] == action_id
        ]
        self.assertEqual(
            [row["group_id"] for row in groups],
            [
                f"{action_id}:group:amber-quadav",
                f"{action_id}:group:greater-quadav",
                f"{action_id}:group:onyx-quadav",
                f"{action_id}:group:veteran-quadav",
            ],
        )
        self.assertEqual([row["candidate_count"] for row in groups], [2, 1, 2, 1])
        candidates = [
            row
            for row in review["objective_destination_candidates"]
            if row["native_key"] == native.key and row["action_id"] == action_id
        ]
        self.assertEqual(
            {row["destination_id"] for row in candidates},
            {point["destination_id"] for point in points},
        )
        self.assertEqual(
            {row["target_name"] for row in candidates},
            {"Amber Quadav", "Greater Quadav", "Onyx Quadav", "Veteran Quadav"},
        )
        expected_items = {"Fetich Head", "Fetich Torso", "Fetich Arms", "Fetich Legs"}
        self.assertTrue(all(set(row["items"]) == expected_items for row in candidates))
        self.assertTrue(all(row["enemies"] == [row["target_name"]] for row in candidates))
        self.assertTrue(all(row["result_relation"] == "obtain-from" for row in candidates))
        self.assertTrue(all(row["route_ready"] is False for row in candidates + groups))
        ledger = next(
            row
            for row in review["action_resolution_ledger"]
            if row["native_key"] == native.key and row["action_id"] == action_id
        )
        self.assertEqual(ledger["status"], "catalogue-candidate")
        self.assertEqual(ledger["candidate_count"], 6)
        self.assertTrue(
            any(source_id.endswith(":farming-items-fact-01") for source_id in ledger["source_action_span_ids"])
        )
        self.assertTrue(
            all(
                set(row["source_action_span_ids"]).issubset(ledger["source_action_span_ids"])
                for row in candidates + groups
            )
        )
        outcomes = [
            row for row in review["legacy_destination_outcomes"] if row["native_key"] == native.key
        ]
        self.assertEqual(
            [row["legacy_override_id"] for row in outcomes],
            [
                "mission:Bastok:3:destination:palborough-lower-amber",
                "mission:Bastok:3:destination:palborough-upper-quadav",
            ],
        )
        self.assertEqual([row["classification"] for row in outcomes], ["catalogue-candidate"] * 2)
        self.assertEqual([row["reason"] for row in outcomes], ["migrated-to-action-candidates"] * 2)
        self.assertEqual([len(row["group_ids"]) for row in outcomes], [1, 3])
        self.assertTrue(all(row["route_ready"] is False for row in outcomes))
        self.assertEqual(review["objective_destinations"], [])
        self.assertNotIn("objective_destinations = {", reconcile)
        self.assertNotIn("route_evidence", reconcile)
        self.assertNotIn("canonical_ingress", reconcile)

    def test_checked_navigation_catalog_retains_all_27_fetichism_enemy_camps(self) -> None:
        native = NativeObjective("mission", "Bastok", 3, "Fetichism", "missions.dat", 0, 2)
        bg, ffxi = self._pinned_fetichism_pages()
        repo_root = Path(__file__).parents[1]
        checked_in = json.loads(
            (
                repo_root / "data" / "mission-quest-guides" / "reviewed-overrides.json"
            ).read_text(encoding="utf-8")
        )
        points, zone_names, edges = _load_navigation_catalog(
            repo_root / "data" / "ffxi-nav-destinations.tsv",
            repo_root / "data" / "ffxi-nav-zoneline-graph.tsv",
        )
        enemy_points = [point for point in points if point["kind"] == "enemy"]
        self.assertEqual(len(enemy_points), 24040)
        self.assertEqual(
            [
                (point["name"], point["raw_identity"])
                for point in enemy_points
                if not action_resolver.navigation_point_has_immutable_identity(point)
            ],
            [],
        )
        overrides = {
            "mission_destination_overrides": {
                native.key: checked_in["mission_destination_overrides"][native.key]
            },
            "legacy_action_migrations": {
                native.key: checked_in["legacy_action_migrations"][native.key]
            },
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                (native,),
                (bg, ffxi),
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=points,
                navigation_zone_names=zone_names,
                navigation_edges=edges,
            )
            review = json.loads(
                (root / "data" / "target-review.json").read_text(encoding="utf-8")
            )

        action_id = "mission:Bastok:3:step-006:claim-01"
        candidates = [
            row
            for row in review["objective_destination_candidates"]
            if row["native_key"] == native.key and row["action_id"] == action_id
        ]
        groups = [
            row
            for row in review["objective_destination_groups"]
            if row["native_key"] == native.key and row["action_id"] == action_id
        ]
        candidate_by_id = {row["candidate_id"]: row for row in candidates}
        group_counts = {}
        for group in groups:
            target_names = {
                candidate_by_id[candidate_id]["target_name"]
                for candidate_id in group["candidate_ids"]
            }
            self.assertEqual(len(target_names), 1)
            group_counts[next(iter(target_names))] = group["candidate_count"]
        self.assertEqual(
            group_counts,
            {
                "Amber Quadav": 8,
                "Greater Quadav": 6,
                "Onyx Quadav": 6,
                "Veteran Quadav": 7,
            },
        )
        self.assertEqual(len(candidates), 27)
        self.assertEqual(len({row["candidate_id"] for row in candidates}), 27)
        self.assertEqual(len({row["destination_id"] for row in candidates}), 27)
        canonical = "".join(
            f'{row["target_name"]}\t{row["destination_id"]}\n'
            for row in sorted(
                candidates,
                key=lambda row: (row["target_name"], row["destination_id"]),
            )
        )
        self.assertEqual(
            hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
            "98c0a43d129eea7521ed1742321045d3b1f22a5053fd5121bc6f6dc08c875cd6",
        )
        self.assertEqual(len(review["legacy_destination_outcomes"]), 2)
        self.assertTrue(all(row["route_ready"] is False for row in candidates + groups))

    def test_unmapped_legacy_destination_is_explicitly_unresolved(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        destination = overrides["mission_destination_overrides"]["mission:Bastok:3"][0]
        destination["canonical_ingress"] = {"edge_id": 947466874, "from_zone": 106}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(self._amber_nav_point(17362953, 58.904, 123.259, -0.483),),
                navigation_zone_names={143: "Palborough Mines"},
                navigation_edges=(
                    {"id": 947466874, "from_zone": 106, "to_zone": 143},
                ),
            )
            review = json.loads(
                (root / "data" / "target-review.json").read_text(encoding="utf-8")
            )
            reconcile = (
                root / "modules" / "mission_quest_reconcile_mission_bastok.lua"
            ).read_text(encoding="utf-8")

        self.assertEqual(review["objective_destinations"], [])
        self.assertEqual(
            review["legacy_destination_outcomes"],
            [
                {
                    "native_key": "mission:Bastok:3",
                    "legacy_override_id": "mission:Bastok:3:destination:palborough-lower-amber",
                    "action_id": "",
                    "classification": "unresolved",
                    "reason": "legacy-action-migration-required",
                    "candidate_ids": [],
                    "candidate_count": 0,
                    "group_ids": [],
                    "source_action_span_ids": [],
                    "source_revisions": {"bg": 3003, "ffxiclopedia": 4004},
                    "legacy_review_metadata": {
                        "zone": 143,
                        "zone_name": "Palborough Mines",
                        "target_name": "Amber Quadav",
                        "target_kind": "enemy",
                        "canonical_ingress_edge_id": 947466874,
                        "canonical_ingress_from_zone": 106,
                        "transport_id": "",
                        "route_evidence": (
                            "navprobe:Palborough_Mines.nav:"
                            "north-gustaberg-entry-to-lower-amber:2026-08-08"
                        ),
                    },
                    "route_ready": False,
                }
            ],
        )
        self.assertNotIn("objective_destinations = {", reconcile)
        self.assertNotIn("route_evidence", reconcile)
        self.assertNotIn("canonical_ingress", reconcile)
        self.assertNotIn("route_ready = true", reconcile)

    def test_legacy_farming_migration_rejects_stale_revision_or_source_fact(self) -> None:
        native = NativeObjective("mission", "Bastok", 3, "Fetichism", "missions.dat", 0, 2)
        bg, ffxi = self._pinned_fetichism_pages()
        checked_in = json.loads(
            (
                Path(__file__).parents[1]
                / "data"
                / "mission-quest-guides"
                / "reviewed-overrides.json"
            ).read_text(encoding="utf-8")
        )
        base = {
            "mission_destination_overrides": {
                native.key: checked_in["mission_destination_overrides"][native.key]
            },
            "legacy_action_migrations": self._fetichism_action_migration(),
        }
        mutations = {
            "revision": ("source_revisions", "bg", 754819),
            "item-step": ("source_facts", "bg", "item_step_id", "mission:Bastok:3:bg:step-003"),
            "enemy-step": (
                "source_facts",
                "ffxiclopedia",
                "enemy_step_id",
                "mission:Bastok:3:ffxiclopedia:step-004",
            ),
            "zone-step": (
                "source_facts",
                "ffxiclopedia",
                "farming_zone_step_id",
                "mission:Bastok:3:ffxiclopedia:step-007",
            ),
        }
        for label, path in mutations.items():
            overrides = json.loads(json.dumps(base))
            cursor = overrides["legacy_action_migrations"][native.key]
            for key in path[:-2]:
                cursor = cursor[key]
            cursor[path[-2]] = path[-1]
            with self.subTest(label=label), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                with self.assertRaises(GenerationError):
                    build_guide_artifacts(
                        (native,),
                        (bg, ffxi),
                        module_root=root / "modules",
                        data_root=root / "data",
                        reviewed_overrides=overrides,
                        navigation_points=(
                            self._quadav_nav_point(
                                "Amber Quadav", 17362953, 58.904, 123.259, -0.483
                            ),
                        ),
                        navigation_zone_names={143: "Palborough Mines"},
                    )

    def test_legacy_farming_migration_fails_closed_on_a_distinct_identityless_camp(self) -> None:
        native = NativeObjective("mission", "Bastok", 3, "Fetichism", "missions.dat", 0, 2)
        bg, ffxi = self._pinned_fetichism_pages()
        checked_in = json.loads(
            (
                Path(__file__).parents[1]
                / "data"
                / "mission-quest-guides"
                / "reviewed-overrides.json"
            ).read_text(encoding="utf-8")
        )
        legacy_row = checked_in["mission_destination_overrides"][native.key][0]
        migration = self._fetichism_action_migration()[native.key]
        migration["mappings"] = migration["mappings"][:1]
        identityless = self._quadav_nav_point("Amber Quadav", 17362999, 999.0, 999.0, 0.0)
        identityless.update(destination_id="", raw_identity="", raw_spawn_ids=(), cluster_policy_version="")
        overrides = {
            "mission_destination_overrides": {native.key: [legacy_row]},
            "legacy_action_migrations": {native.key: migration},
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build_guide_artifacts(
                (native,),
                (bg, ffxi),
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=overrides,
                navigation_points=(
                    self._quadav_nav_point("Amber Quadav", 17362953, 58.904, 123.259, -0.483),
                    identityless,
                ),
                navigation_zone_names={143: "Palborough Mines"},
            )
            review = json.loads(
                (root / "data" / "target-review.json").read_text(encoding="utf-8")
            )

        self.assertEqual(review["objective_destination_candidates"], [])
        self.assertEqual(review["objective_destination_groups"], [])
        (outcome,) = review["legacy_destination_outcomes"]
        self.assertEqual(outcome["classification"], "unresolved")
        self.assertEqual(outcome["reason"], "legacy-action-migration-catalogue-ambiguous")
        self.assertEqual(outcome["candidate_ids"], [])
        self.assertFalse(outcome["route_ready"])

    def test_legacy_farming_migration_rejects_stale_legacy_source_steps(self) -> None:
        native = NativeObjective("mission", "Bastok", 3, "Fetichism", "missions.dat", 0, 2)
        bg, ffxi = self._pinned_fetichism_pages()
        checked_in = json.loads(
            (
                Path(__file__).parents[1]
                / "data"
                / "mission-quest-guides"
                / "reviewed-overrides.json"
            ).read_text(encoding="utf-8")
        )
        legacy_rows = json.loads(
            json.dumps(checked_in["mission_destination_overrides"][native.key])
        )
        legacy_rows[0]["source_step_ids"] = [
            "mission:Bastok:3:step-004",
            "mission:Bastok:3:step-006",
        ]
        overrides = {
            "mission_destination_overrides": {native.key: legacy_rows},
            "legacy_action_migrations": self._fetichism_action_migration(),
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(GenerationError):
                build_guide_artifacts(
                    (native,),
                    (bg, ffxi),
                    module_root=root / "modules",
                    data_root=root / "data",
                    reviewed_overrides=overrides,
                    navigation_points=(
                        self._quadav_nav_point(
                            "Amber Quadav", 17362953, 58.904, 123.259, -0.483
                        ),
                        self._quadav_nav_point(
                            "Greater Quadav", 17363001, 201.0, 301.0, 8.0
                        ),
                        self._quadav_nav_point(
                            "Onyx Quadav", 17363011, 221.0, 321.0, 12.0
                        ),
                        self._quadav_nav_point(
                            "Veteran Quadav", 17363021, 241.0, 341.0, 12.0
                        ),
                    ),
                    navigation_zone_names={143: "Palborough Mines"},
                )

    def test_unknown_legacy_action_migration_native_key_fails_generation(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        overrides["legacy_action_migrations"] = {
            "mission:Bastok:999": {
                "action_id": "mission:Bastok:999:step-001:claim-01"
            }
        }
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(GenerationError):
                build_guide_artifacts(
                    natives,
                    pages,
                    module_root=root / "modules",
                    data_root=root / "data",
                    reviewed_overrides=overrides,
                    navigation_points=(
                        self._amber_nav_point(17362953, 58.904, 123.259, -0.483),
                    ),
                    navigation_zone_names={143: "Palborough Mines"},
                )

    def test_unknown_legacy_destination_native_key_fails_generation(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        orphan = json.loads(
            json.dumps(overrides["mission_destination_overrides"]["mission:Bastok:3"])
        )
        overrides["mission_destination_overrides"]["mission:Bastok:999"] = orphan
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(GenerationError):
                build_guide_artifacts(
                    natives,
                    pages,
                    module_root=root / "modules",
                    data_root=root / "data",
                    reviewed_overrides=overrides,
                    navigation_points=(
                        self._amber_nav_point(17362953, 58.904, 123.259, -0.483),
                    ),
                    navigation_zone_names={143: "Palborough Mines"},
                )

    def test_legacy_action_migration_with_empty_override_list_fails_generation(self) -> None:
        natives, pages, overrides = self._mission_destination_fixture()
        overrides["mission_destination_overrides"]["mission:Bastok:3"] = []
        overrides["legacy_action_migrations"] = self._fetichism_action_migration()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaises(GenerationError):
                build_guide_artifacts(
                    natives,
                    pages,
                    module_root=root / "modules",
                    data_root=root / "data",
                    reviewed_overrides=overrides,
                    navigation_points=(
                        self._amber_nav_point(17362953, 58.904, 123.259, -0.483),
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

    def test_reviewed_named_npc_target_with_distinct_points_fails_closed_without_aborting(self) -> None:
        natives, pages = self._named_npc_target_fixture()
        duplicate_points = (
            {"zone": 172, "name": "Makarim", "kind": "npc", "x": 1, "z": 2, "y": 3},
            {"zone": 172, "name": "Makarim", "kind": "npc", "x": 4, "z": 5, "y": 6},
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=self._named_npc_target_overrides(),
                navigation_points=duplicate_points,
                navigation_zone_names={172: "Zeruhn Mines"},
            )
            review = json.loads((root / "data" / "target-review.json").read_text(encoding="utf-8"))
            coverage = json.loads((root / "data" / "coverage.json").read_text(encoding="utf-8"))

        self.assertEqual(result["counts"]["verified_navigation"], 0)
        failure = review["reviewed_target_failures"][0]
        self.assertEqual(failure["override_step_id"], "mission:Bastok:1:step-001")
        self.assertEqual(failure["reason"], "current-navigation-ambiguous")
        self.assertEqual(failure["candidate_step_ids"], ["mission:Bastok:1:step-001"])
        self.assertFalse(failure["route_ready"])
        self.assertEqual(
            coverage["objectives"]["mission:Bastok:1"]["reviewed_target_failures"],
            [failure],
        )

    def test_reviewed_named_npc_target_accepts_physically_identical_duplicate_rows(self) -> None:
        natives, pages = self._named_npc_target_fixture()
        duplicate_points = (
            {
                "zone": 172,
                "name": "Makarim",
                "kind": "npc",
                "x": -60.925,
                "z": -333.294,
                "y": 8.471,
                "source": "legacy-reference",
            },
            {
                "zone": 172,
                "name": "Makarim",
                "kind": "npc",
                "x": -60.925,
                "z": -333.294,
                "y": 8.471,
                "source": "lsb-npc-list-all",
                "destination_id": "npc:v1:172:17481828",
                "raw_identity": "lsb:npc_list:17481828",
            },
        )
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = build_guide_artifacts(
                natives,
                pages,
                module_root=root / "modules",
                data_root=root / "data",
                reviewed_overrides=self._named_npc_target_overrides(),
                navigation_points=duplicate_points,
                navigation_zone_names={172: "Zeruhn Mines"},
            )

        self.assertEqual(result["counts"]["verified_navigation"], 1)

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

    def test_stale_reviewed_named_npc_target_fails_closed_without_aborting(self) -> None:
        nav_points = ({"zone": 172, "name": "Makarim", "kind": "npc"},)
        invalid_fixtures = (
            (self._named_npc_target_fixture(ffxi_name="Naji"), "source-claim-no-match"),
            (
                self._named_npc_target_fixture(ffxi_action="examine"),
                "source-claim-evidence-insufficient-at-key",
            ),
        )
        for (natives, pages), expected_reason in invalid_fixtures:
            with self.subTest(pages=pages), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                result = build_guide_artifacts(
                    natives,
                    pages,
                    module_root=root / "modules",
                    data_root=root / "data",
                    reviewed_overrides=self._named_npc_target_overrides(),
                    navigation_points=nav_points,
                    navigation_zone_names={172: "Zeruhn Mines"},
                )
                self.assertEqual(result["counts"]["verified_navigation"], 0)
                review = json.loads(
                    (root / "data" / "target-review.json").read_text(encoding="utf-8")
                )
                failure = review["reviewed_target_failures"][0]
                self.assertEqual(failure["override_step_id"], "mission:Bastok:1:step-001")
                self.assertEqual(failure["reason"], expected_reason)
                self.assertEqual(failure["candidate_step_ids"], [])
                self.assertFalse(failure["route_ready"])

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
        overrides["mission_destination_overrides"] = {}
        overrides["legacy_action_migrations"] = {}
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

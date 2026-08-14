from __future__ import annotations

import copy
import hashlib
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
import unittest
import unicodedata
from collections import Counter
from pathlib import Path

from tools.objective_guides.mediawiki import load_snapshot
from tools.objective_guides.wikitext import parse_objective_page


REPO_ROOT = Path(__file__).resolve().parents[1]
DATA_ROOT = REPO_ROOT / "data" / "mission-quest-guides"
MODULE_ROOT = REPO_ROOT / "ashita" / "addons" / "accessxi_reader" / "modules"
FFXI_ROOT = Path(r"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI")
PYTHON = REPO_ROOT / "tools" / ".objective-guides-venv" / "Scripts" / "python.exe"
LUA = REPO_ROOT / "tools" / "lua51" / "lua5.1.exe"
CACHE_ROOT = REPO_ROOT / "tools" / "objective_guides_cache" / "snapshots"
SOURCE_SPAN_ID = re.compile(
    r"^(?P<native_key>.+):(?P<site>bg|ffxiclopedia):"
    r"step-(?P<step_order>\d+):span-(?P<span_order>\d+)$"
)

EXPECTED_CONTEXT_COUNTS = {
    ("mission", "A Crystalline Prophecy"): 13,
    ("mission", "A Moogle Kupo d'Etat"): 15,
    ("mission", "A Shantotto Ascension"): 16,
    ("mission", "Assault"): 52,
    ("mission", "Bastok"): 24,
    ("mission", "Campaign"): 95,
    ("mission", "Chains of Promathia"): 65,
    ("mission", "Rhapsodies of Vana'diel"): 98,
    ("mission", "Rise of the Zilart"): 20,
    ("mission", "San d'Oria"): 24,
    ("mission", "Seekers of Adoulin"): 112,
    ("mission", "The Voracious Resurgence"): 46,
    ("mission", "Treasures of Aht Urhgan"): 48,
    ("mission", "Windurst"): 24,
    ("mission", "Wings of the Goddess"): 54,
    ("quest", "abyssea"): 192,
    ("quest", "adoulin"): 119,
    ("quest", "aht_urhgan"): 72,
    ("quest", "bastok"): 93,
    ("quest", "coalition"): 96,
    ("quest", "crystal_war"): 95,
    ("quest", "jeuno"): 158,
    ("quest", "other_areas"): 81,
    ("quest", "outlands"): 60,
    ("quest", "sandoria"): 82,
    ("quest", "windurst"): 90,
}

NATIVE_SENTINEL_KEYS = {
    "mission:A Crystalline Prophecy:13",
    "mission:A Shantotto Ascension:16",
    "mission:Chains of Promathia:65",
    "mission:Rhapsodies of Vana'diel:99",
    "mission:Rise of the Zilart:64",
    "mission:Seekers of Adoulin:111",
    "mission:Seekers of Adoulin:112",
}
CHAPTER_INDEX_KEYS = {
    "mission:Chains of Promathia:1",
    "mission:Chains of Promathia:5",
    "mission:Chains of Promathia:11",
    "mission:Chains of Promathia:25",
    "mission:Chains of Promathia:30",
    "mission:Chains of Promathia:48",
    "mission:Chains of Promathia:53",
    "mission:Chains of Promathia:59",
    "mission:Rhapsodies of Vana'diel:2",
    "mission:Rhapsodies of Vana'diel:20",
    "mission:Rhapsodies of Vana'diel:62",
    "mission:Seekers of Adoulin:1",
    "mission:Seekers of Adoulin:10",
    "mission:Seekers of Adoulin:30",
    "mission:Seekers of Adoulin:60",
    "mission:Seekers of Adoulin:95",
}
NATIVE_PLACEHOLDER_KEYS = {
    "quest:coalition:47",
    "quest:jeuno:122",
    "quest:jeuno:125",
    "quest:jeuno:126",
    "quest:jeuno:127",
    "quest:outlands:0",
    "quest:outlands:5",
}
SOURCE_ABSENT_KEYS = {f"quest:jeuno:{native_id}" for native_id in range(33, 41)}
SOURCE_MISSING_KEYS = (
    NATIVE_SENTINEL_KEYS | CHAPTER_INDEX_KEYS | NATIVE_PLACEHOLDER_KEYS | SOURCE_ABSENT_KEYS
)

PROHIBITED_ACTION_IDS = {
    "mission:A Crystalline Prophecy:7:step-024:claim-01",
    "mission:A Moogle Kupo d'Etat:13:step-098:claim-01",
    "mission:A Moogle Kupo d'Etat:15:step-005:claim-06",
    "mission:A Moogle Kupo d'Etat:2:step-015:claim-01",
    "mission:A Shantotto Ascension:4:step-011:claim-01",
    "mission:Assault:16:step-019:claim-01",
    "mission:Assault:23:step-003:claim-01",
    "mission:Assault:37:step-004:claim-01",
    "mission:Assault:47:step-034:claim-01",
    "mission:Assault:3:step-014:claim-01",
    "mission:Assault:46:step-009:claim-01",
    "mission:Assault:52:step-103:claim-02",
    "mission:Assault:52:step-132:claim-01",
    "mission:Bastok:11:step-012:claim-01",
    "mission:Bastok:17:step-012:claim-02",
    "mission:Bastok:17:step-015:claim-01",
    "mission:Campaign:4:step-013:claim-02",
    "mission:Campaign:29:step-010:claim-01",
    "mission:Campaign:30:step-007:claim-02",
    "mission:Campaign:40:step-013:claim-01",
    "mission:Campaign:44:step-001:claim-02",
    "mission:Campaign:46:step-010:claim-01",
    "mission:Campaign:51:step-001:claim-03",
    "mission:Campaign:51:step-009:claim-01",
    "mission:Campaign:59:step-018:claim-01",
    "mission:Campaign:52:step-022:claim-01",
    "mission:Campaign:63:step-028:claim-01",
    "mission:Campaign:83:step-022:claim-01",
    "mission:Campaign:84:step-006:claim-01",
    "mission:Chains of Promathia:27:step-018:claim-02",
    "mission:Chains of Promathia:58:step-009:claim-01",
    "mission:Chains of Promathia:28:step-078:claim-01",
    "mission:Chains of Promathia:31:step-020:claim-01",
    "mission:Rhapsodies of Vana'diel:96:step-026:claim-01",
    "mission:Rise of the Zilart:9:step-024:claim-02",
    "mission:Rise of the Zilart:9:step-044:claim-01",
    "mission:San d'Oria:21:step-036:claim-01",
    "mission:San d'Oria:3:step-003:claim-01",
    "mission:Seekers of Adoulin:33:step-003:claim-01",
    "mission:Windurst:17:step-018:claim-01",
    "mission:Treasures of Aht Urhgan:42:step-002:claim-01",
    "mission:Windurst:5:step-025:claim-01",
    "quest:abyssea:128:step-019:claim-01",
    "quest:abyssea:31:step-013:claim-01",
    "quest:abyssea:61:step-015:claim-01",
    "quest:abyssea:86:step-002:claim-01",
    "quest:abyssea:86:step-006:claim-01",
    "quest:adoulin:5:step-006:claim-01",
    "quest:adoulin:53:step-002:claim-01",
    "quest:adoulin:70:step-003:claim-02",
    "quest:adoulin:111:step-024:claim-01",
    "quest:adoulin:133:step-005:claim-02",
    "quest:adoulin:33:step-003:claim-02",
    "quest:adoulin:54:step-019:claim-01",
    "quest:aht_urhgan:102:step-026:claim-01",
    "quest:aht_urhgan:102:step-026:claim-04",
    "quest:aht_urhgan:25:step-016:claim-01",
    "quest:aht_urhgan:26:step-033:claim-01",
    "quest:aht_urhgan:71:step-061:claim-02",
    "quest:aht_urhgan:21:step-004:claim-01",
    "quest:bastok:59:step-013:claim-01",
    "quest:bastok:60:step-038:claim-01",
    "quest:bastok:90:step-017:claim-01",
    "quest:bastok:28:step-030:claim-01",
    "quest:bastok:53:step-006:claim-01",
    "quest:bastok:60:step-019:claim-02",
    "quest:bastok:8:step-004:claim-03",
    "quest:coalition:86:step-004:claim-02",
    "quest:coalition:87:step-002:claim-02",
    "quest:coalition:88:step-003:claim-01",
    "quest:coalition:89:step-003:claim-01",
    "quest:coalition:90:step-003:claim-01",
    "quest:coalition:91:step-003:claim-01",
    "quest:crystal_war:28:step-010:claim-01",
    "quest:crystal_war:29:step-007:claim-02",
    "quest:crystal_war:39:step-013:claim-01",
    "quest:crystal_war:43:step-001:claim-02",
    "quest:crystal_war:45:step-010:claim-01",
    "quest:crystal_war:50:step-001:claim-03",
    "quest:crystal_war:50:step-009:claim-01",
    "quest:crystal_war:58:step-018:claim-01",
    "quest:crystal_war:3:step-013:claim-02",
    "quest:crystal_war:51:step-022:claim-01",
    "quest:crystal_war:62:step-028:claim-01",
    "quest:crystal_war:82:step-022:claim-01",
    "quest:crystal_war:83:step-006:claim-01",
    "quest:jeuno:130:step-032:claim-01",
    "quest:jeuno:13:step-015:claim-01",
    "quest:jeuno:186:step-019:claim-02",
    "quest:jeuno:1:step-011:claim-02",
    "quest:jeuno:79:step-013:claim-02",
    "quest:jeuno:83:step-027:claim-01",
    "quest:jeuno:132:step-025:claim-01",
    "quest:jeuno:15:step-003:claim-01",
    "quest:jeuno:170:step-005:claim-02",
    "quest:jeuno:8:step-003:claim-01",
    "quest:other_areas:105:step-014:claim-01",
    "quest:outlands:144:step-029:claim-01",
    "quest:sandoria:118:step-014:claim-01",
    "quest:sandoria:98:step-015:claim-02",
    "quest:sandoria:84:step-017:claim-01",
    "quest:windurst:14:step-015:claim-01",
    "quest:windurst:14:step-022:claim-02",
    "quest:windurst:17:step-026:claim-01",
    "quest:windurst:11:step-002:claim-01",
    "quest:windurst:13:step-005:claim-01",
    "quest:windurst:24:step-004:claim-01",
    "quest:windurst:3:step-004:claim-01",
    "quest:windurst:64:step-007:claim-01",
    "quest:windurst:71:step-041:claim-02",
    "quest:windurst:75:step-048:claim-01",
    "quest:windurst:75:step-072:claim-01",
    "quest:windurst:79:step-013:claim-01",
    "quest:windurst:8:step-008:claim-01",
    "quest:windurst:17:step-028:claim-01",
    "quest:windurst:46:step-002:claim-01",
    "quest:windurst:50:step-006:claim-01",
    "quest:windurst:71:step-066:claim-01",
}

CONTRAST_ACTION_IDS = {
    "mission:Campaign:44:step-014:claim-01",
    "mission:Bastok:17:step-012:claim-03",
    "mission:Chains of Promathia:61:step-011:claim-03",
    "mission:San d'Oria:23:step-010:claim-01",
    "mission:Windurst:17:step-013:claim-02",
    "mission:Windurst:5:step-029:claim-01",
    "quest:crystal_war:43:step-014:claim-01",
    "quest:aht_urhgan:6:step-027:claim-01",
    "quest:aht_urhgan:6:step-027:claim-02",
    "quest:aht_urhgan:6:step-057:claim-02",
    "quest:jeuno:101:step-003:claim-02",
    "quest:jeuno:129:step-009:claim-02",
    "quest:jeuno:44:step-021:claim-01",
    "quest:jeuno:78:step-016:claim-02",
    "quest:jeuno:89:step-042:claim-02",
}

LEGACY_PROHIBITED_ACTION_IDS = {
    "mission:Assault:52:step-050:claim-01",
    "mission:Chains of Promathia:14:step-060:claim-01",
    "mission:Chains of Promathia:15:step-060:claim-01",
    "mission:Chains of Promathia:16:step-060:claim-01",
    "mission:Chains of Promathia:17:step-060:claim-01",
    "mission:Chains of Promathia:18:step-060:claim-01",
    "mission:Chains of Promathia:19:step-060:claim-01",
    "mission:Chains of Promathia:20:step-060:claim-01",
    "mission:Chains of Promathia:21:step-060:claim-01",
    "mission:Chains of Promathia:22:step-060:claim-01",
}

AFFIRMATIVE_SURVIVAL_GUIDE_CANDIDATE = (
    "quest:sandoria:82",
    "quest:sandoria:82:step-006:claim-02",
    "object:v1:196:17580429",
)

SUPPLEMENTAL_PROVENANCE_PINS = {
    "mission:Bastok:3:step-006:claim-01": (
        "mission:Bastok:3:bg:step-004:farming-claim-fact-01",
        "mission:Bastok:3:bg:step-002:farming-items-fact-01",
        "mission:Bastok:3:ffxiclopedia:step-004:farming-drop-fact-01",
        "mission:Bastok:3:ffxiclopedia:step-005:farming-enemies-fact-01",
        "mission:Bastok:3:ffxiclopedia:step-006:farming-zone-fact-01",
        "mission:Bastok:3:ffxiclopedia:step-003:farming-items-fact-01",
    ),
    "mission:San d'Oria:1:step-001:claim-01": (
        "mission:San d'Oria:1:bg:step-002:role-member-fact-01",
        "mission:San d'Oria:1:bg:step-003:role-member-fact-01",
        "mission:San d'Oria:1:bg:step-004:role-member-fact-01",
    ),
    "mission:San d'Oria:1:step-005:claim-01": (
        "mission:San d'Oria:1:bg:step-006:location-fact-01",
    ),
}

CONTEXT_MODULE_TOKENS = (
    "mission_a_crystalline_prophecy",
    "mission_a_moogle_kupo_detat",
    "mission_a_shantotto_ascension",
    "mission_assault",
    "mission_bastok",
    "mission_campaign",
    "mission_chains_of_promathia",
    "mission_rhapsodies_of_vanadiel",
    "mission_rise_of_the_zilart",
    "mission_san_doria",
    "mission_seekers_of_adoulin",
    "mission_the_voracious_resurgence",
    "mission_treasures_of_aht_urhgan",
    "mission_windurst",
    "mission_wings_of_the_goddess",
    "quest_abyssea",
    "quest_adoulin",
    "quest_aht_urhgan",
    "quest_bastok",
    "quest_coalition",
    "quest_crystal_war",
    "quest_jeuno",
    "quest_other_areas",
    "quest_outlands",
    "quest_sandoria",
    "quest_windurst",
)
SOURCE_MODULE_TOKENS = tuple(
    token for token in CONTEXT_MODULE_TOKENS if token != "quest_coalition"
)

BASELINE_CORPUS_RUNTIME_BYTES = 33_018_529
MAX_PRESENTATION_BYTES = BASELINE_CORPUS_RUNTIME_BYTES * 5 // 4
MAX_PROGRESSION_BYTES = BASELINE_CORPUS_RUNTIME_BYTES
MAX_CORPUS_RUNTIME_BYTES = BASELINE_CORPUS_RUNTIME_BYTES * 9 // 4

PROGRESSION_PAYLOAD_FIELDS = {
    "native_key",
    "progression_schema_version",
    "progression_module",
    "source_authority",
    "progression_revision",
    "progression_actions",
}
PROGRESSION_ACTION_FIELDS = {
    "step_id",
    "step_order",
    "action_id",
    "action_order",
    "order",
    "action",
    "relationship",
    "target",
    "target_key",
    "target_kind",
    "npcs",
    "objects",
    "enemies",
    "items",
    "key_items",
    "transports",
    "zones",
    "destination_zone_name",
    "destination_zone_id",
    "grid_coordinates",
    "result_items",
    "result_relation",
    "instruction",
    "required_count",
    "count_mode",
    "count_explicit",
    "material",
    "source_authority",
    "field_sources",
    "source_revisions",
    "source_action_span_ids",
    "catalogue",
}
PROGRESSION_FIELD_SOURCE_FIELDS = {
    "action",
    "relationship",
    "target",
    "target_key",
    "target_kind",
    "npcs",
    "objects",
    "enemies",
    "items",
    "key_items",
    "transports",
    "zones",
    "destination_zone_name",
    "destination_zone_id",
    "grid_coordinates",
    "result_items",
    "result_relation",
    "instruction",
    "required_count",
    "count_mode",
    "count_explicit",
    "catalogue",
}
PROGRESSION_CATALOGUE_FIELDS = {
    "destination_id",
    "zone_id",
    "zone_name",
    "target_name",
    "target_kind",
    "target_key",
    "target_point",
    "raw_identity",
    "raw_spawn_ids",
    "cluster_policy_version",
    "transport_id",
    "battlefield_id",
    "metadata_class",
    "group_id",
    "arrival_instruction",
}


def _json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _independent_target_key(value: object) -> str:
    normalized = unicodedata.normalize("NFKD", str(value or "")).casefold()
    normalized = "".join(
        character for character in normalized if not unicodedata.combining(character)
    ).replace("&", "and")
    return re.sub(r"[^a-z0-9]+", "", normalized)


def _pinned_parsed_pages(
    coverage: dict[str, object],
) -> dict[tuple[str, int], object]:
    needed = {
        (site, page["page_id"])
        for row in coverage["objectives"].values()
        for site, page in row["source_pages"].items()
    }
    parsed: dict[tuple[str, int], object] = {}
    for site in ("bg", "ffxiclopedia"):
        revisions = load_snapshot(CACHE_ROOT / f"{site}.json", expected_site=site)
        for revision in revisions:
            identity = (site, revision.page_id)
            if identity in needed:
                parsed[identity] = parse_objective_page(revision)
    if set(parsed) != needed:
        raise AssertionError(
            f"Pinned raw snapshots omitted parsed coverage pages: {sorted(needed - set(parsed))!r}"
        )
    return parsed


def _independent_direct_prohibition(span: object) -> bool:
    verb = str(span.verb or "").strip()
    if not verb:
        return False
    match = re.search(rf"(?<![A-Za-z0-9]){re.escape(verb)}(?![A-Za-z0-9])", span.supporting_clause, re.IGNORECASE)
    if match is None:
        return False
    prefix = span.supporting_clause[: match.start()]
    if re.search(
        r"\b(?:key|key\s+item|pass|permit|seal)\s+is\s+not\s+required\s+to\s+$",
        prefix,
        re.IGNORECASE,
    ):
        return False
    coordinated = re.search(
        r"(?:"
        r"(?:no\s+need|not\s+(?:necessary|required))\s+to\s+(?:actually\s+)?|"
        r"(?:do(?:es)?\s+not|don['’]t|doesn['’]t)\s+(?:need|have)\s+to\s+|"
        r"need\s+not\s+|will\s+not\s+need\s+to\s+|"
        r"(?:cannot|can['’]t|unable\s+to|not\s+allowed\s+to|"
        r"will\s+not\s+be\s+able\s+to)\s+|"
        r"(?:do\s+not|don['’]t|never|not\s+to|not)\s+(?:try\s+to\s+)?"
        r")"
        r"(?:find|see|go|zone|attack|use|wait|fight|kill|defeat|trade|talk|speak|check|"
        r"examine|enter|obtain|receive|select|choose|board|open)\b"
        r"(?P<bridge>[^,.;:()]{0,100})\b(?:and|or)\s+$",
        prefix,
        re.IGNORECASE,
    )
    if coordinated and re.search(
        r"\b(?:if|unless|until|before|after|when|while|then|just|instead|past)\b",
        coordinated.group("bridge"),
        re.IGNORECASE,
    ) is None:
        return True
    return re.search(
        r"(?:"
        r"\b(?:no\s+need|not\s+(?:necessary|required))\s+to\s+(?:actually\s+)?|"
        r"\b(?:do(?:es)?\s+not|don['’]t|doesn['’]t)\s+(?:need|have)\s+to\s+|"
        r"\bneed\s+not\s+|"
        r"\bwill\s+not\s+need\s+to\s+|"
        r"\b(?:cannot|can['’]t|unable\s+to|not\s+allowed\s+to|will\s+not\s+be\s+able\s+to)\s+|"
        r"\b(?:do\s+not|don['’]t|never|not\s+to|not)\s+(?:try\s+to\s+)?|"
        r"\b(?:avoid|without)\s+(?:(?:an?|the|any)\s+)?|"
        r"\bmake\s+sure\s+not\s+to\s+go\s+past\b[^.;]{0,160}\bthat\s+"
        r"|\b(?:the|an?)\s+(?:npc|enemy|monster|mob|bomb)\s+will\s+(?:attempt|try)\s+to\s+"
        r")$",
        prefix,
        re.IGNORECASE,
    ) is not None


def _independent_pre_polarity_prohibition(span: object) -> bool:
    verb = str(span.verb or "").strip()
    if not verb:
        return False
    match = re.search(
        rf"(?<![A-Za-z0-9]){re.escape(verb)}(?![A-Za-z0-9])",
        span.supporting_clause,
        re.IGNORECASE,
    )
    if match is None:
        return False
    return re.search(
        r"(?:\bnot\s+(?:to\s+|need\s+to\s+)?|\bnever\s+|\bavoid\s+|\bdon't\s+)$",
        span.supporting_clause[: match.start()],
        re.IGNORECASE,
    ) is not None


def _artifact_paths() -> tuple[Path, ...]:
    data_names = (
        "coverage.json",
        "coverage.md",
        "native-manifest.json",
        "source-discovery.json",
        "source-parse-failures.json",
        "source-site-config.json",
        "source-snapshot.json",
        "target-review.json",
        "route-evidence-v2.jsonl",
    )
    module_patterns = (
        "mission_quest_bg_*.lua",
        "mission_quest_ffxiclopedia_*.lua",
        "mission_quest_reconcile_*.lua",
        "mission_quest_progression_*.lua",
        "mission_quest_guide_index.lua",
        "mission_quest_route_contracts.lua",
        "mission_quest_route_policy.lua",
        "mission_quest_route_transitions.lua",
    )
    paths = [DATA_ROOT / name for name in data_names]
    paths.append(REPO_ROOT / "ashita" / "addons" / "accessxi_reader" / "data" / "mission-quest-route-manifest.tsv")
    paths.append(REPO_ROOT / "ashita" / "addons" / "accessxi_reader" / "accessxi_reader.lua")
    for pattern in module_patterns:
        paths.extend(MODULE_ROOT.glob(pattern))
    return tuple(sorted(paths))


def _expected_artifact_paths() -> set[str]:
    data_names = {
        "coverage.json",
        "coverage.md",
        "native-manifest.json",
        "source-discovery.json",
        "source-parse-failures.json",
        "source-site-config.json",
        "source-snapshot.json",
        "target-review.json",
        "route-evidence-v2.jsonl",
    }
    paths = {f"data/mission-quest-guides/{name}" for name in data_names}
    paths.update(
        {
            "ashita/addons/accessxi_reader/accessxi_reader.lua",
            "ashita/addons/accessxi_reader/data/mission-quest-route-manifest.tsv",
            "ashita/addons/accessxi_reader/modules/mission_quest_guide_index.lua",
            "ashita/addons/accessxi_reader/modules/mission_quest_route_contracts.lua",
            "ashita/addons/accessxi_reader/modules/mission_quest_route_policy.lua",
            "ashita/addons/accessxi_reader/modules/mission_quest_route_transitions.lua",
        }
    )
    for token in SOURCE_MODULE_TOKENS:
        paths.add(f"ashita/addons/accessxi_reader/modules/mission_quest_bg_{token}.lua")
    for token in CONTEXT_MODULE_TOKENS:
        paths.add(
            f"ashita/addons/accessxi_reader/modules/mission_quest_ffxiclopedia_{token}.lua"
        )
        paths.add(f"ashita/addons/accessxi_reader/modules/mission_quest_reconcile_{token}.lua")
        paths.add(f"ashita/addons/accessxi_reader/modules/mission_quest_progression_{token}.lua")
    return paths


def _artifact_hashes() -> dict[str, str]:
    return {
        path.relative_to(REPO_ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in _artifact_paths()
    }


LUA_JSON_DUMP = r'''
local function quote(value)
    return '"' .. value:gsub('[%z\1-\31\\"]', function(character)
        if character == '"' then return '\\"' end
        if character == '\\' then return '\\\\' end
        if character == '\b' then return '\\b' end
        if character == '\f' then return '\\f' end
        if character == '\n' then return '\\n' end
        if character == '\r' then return '\\r' end
        if character == '\t' then return '\\t' end
        return string.format('\\u%04x', string.byte(character))
    end) .. '"'
end

local function array_shape(value)
    local count, maximum = 0, 0
    for key, _ in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
        if key > maximum then maximum = key end
    end
    return count == maximum
end

local encode
encode = function(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then return string.format('%.17g', value) end
    if kind == 'string' then return quote(value) end
    assert(kind == 'table', 'unsupported Lua value: ' .. kind)
    if array_shape(value) then
        local rows = {}
        for index = 1, #value do rows[index] = encode(value[index]) end
        return '[' .. table.concat(rows, ',') .. ']'
    end
    local keys = {}
    for key, _ in pairs(value) do
        assert(type(key) == 'string', 'non-string object key')
        keys[#keys + 1] = key
    end
    table.sort(keys)
    local rows = {}
    for index, key in ipairs(keys) do
        rows[index] = quote(key) .. ':' .. encode(value[key])
    end
    return '{' .. table.concat(rows, ',') .. '}'
end

for index = 1, #arg do
    local chunk, load_error = loadfile(arg[index])
    assert(chunk, load_error)
    local ok, value = pcall(chunk)
    assert(ok, value)
    assert(type(value) == 'table', arg[index] .. ' did not return a table')
    io.write(arg[index], '\t', encode(value), '\n')
end
'''


LUA_KEY_DUMP = r'''
for index = 1, #arg do
    local chunk, load_error = loadfile(arg[index])
    assert(chunk, load_error)
    local ok, value = pcall(chunk)
    assert(ok, value)
    assert(type(value) == 'table', arg[index] .. ' did not return a table')
    local keys = {}
    for key, _ in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do io.write(arg[index], '\t', key, '\n') end
end
'''


def _lua_values(paths: tuple[Path, ...]) -> dict[Path, object]:
    with tempfile.TemporaryDirectory() as temporary:
        script = Path(temporary) / "dump.lua"
        script.write_text(LUA_JSON_DUMP, encoding="utf-8", newline="\n")
        result = subprocess.run(
            [str(LUA), str(script), *(str(path) for path in paths)],
            cwd=REPO_ROOT,
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=300,
        )
    if result.returncode != 0:
        raise AssertionError(result.stdout + result.stderr)
    values: dict[Path, object] = {}
    for line in result.stdout.splitlines():
        raw_path, payload = line.split("\t", 1)
        values[Path(raw_path)] = json.loads(payload)
    if set(values) != set(paths):
        raise AssertionError("Lua value dump omitted or duplicated a requested module.")
    return values


def _lua_keys(paths: tuple[Path, ...]) -> dict[Path, set[str]]:
    with tempfile.TemporaryDirectory() as temporary:
        script = Path(temporary) / "keys.lua"
        script.write_text(LUA_KEY_DUMP, encoding="utf-8", newline="\n")
        result = subprocess.run(
            [str(LUA), str(script), *(str(path) for path in paths)],
            cwd=REPO_ROOT,
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=300,
        )
    if result.returncode != 0:
        raise AssertionError(result.stdout + result.stderr)
    values = {path: set() for path in paths}
    for line in result.stdout.splitlines():
        raw_path, key = line.split("\t", 1)
        values[Path(raw_path)].add(key)
    return values


def _recomputed_progression_revision(payload: dict[str, object]) -> str:
    revision_payload = copy.deepcopy(
        {
            "progression_schema_version": payload["progression_schema_version"],
            "progression_module": payload["progression_module"],
            "native_key": payload["native_key"],
            "source_authority": payload["source_authority"],
            "progression_actions": payload["progression_actions"],
        }
    )
    for action in revision_payload["progression_actions"]:
        for catalogue in action["catalogue"]:
            catalogue["target_point"] = [float(value) for value in catalogue["target_point"]]
    encoded = json.dumps(
        revision_payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


class WikiAuthoritativeObjectiveCorpusTests(unittest.TestCase):
    maxDiff = None

    def test_checked_in_corpus_has_complete_deterministic_provenance_and_authority(self) -> None:
        coverage = _json(DATA_ROOT / "coverage.json")
        manifest = _json(DATA_ROOT / "native-manifest.json")
        snapshot = _json(DATA_ROOT / "source-snapshot.json")
        review = _json(DATA_ROOT / "target-review.json")

        self.assertEqual(coverage["counts"]["valid_native"], 1844)
        native_rows = manifest["objectives"]
        self.assertEqual(Counter(row["kind"] for row in native_rows), {"mission": 706, "quest": 1138})
        self.assertEqual(
            Counter((row["kind"], row["context"]) for row in native_rows),
            EXPECTED_CONTEXT_COUNTS,
        )
        native_keys = [row["key"] for row in native_rows]
        self.assertEqual(len(native_keys), len(set(native_keys)))
        self.assertEqual(set(native_keys), set(coverage["objectives"]))

        self.assertEqual({page["site"] for page in snapshot["pages"]}, {"bg", "ffxiclopedia"})
        source_pages = {(page["site"], page["page_id"]): page for page in snapshot["pages"]}
        self.assertEqual(len(source_pages), len(snapshot["pages"]))
        for identity, page in source_pages.items():
            self.assertGreater(identity[1], 0)
            self.assertGreater(page["revision_id"], 0)
            self.assertRegex(page["content_sha256"], r"^[0-9a-f]{64}$")
            self.assertTrue(page["source_url"].startswith("https://"))
        source_backed = {
            key: row
            for key, row in coverage["objectives"].items()
            if row["source_pages"]
        }
        self.assertEqual(len(source_backed), 1806)
        self.assertEqual(set(coverage["objectives"]).difference(source_backed), SOURCE_MISSING_KEYS)
        for key, row in source_backed.items():
            self.assertEqual(
                row.get("source_authority"),
                {"primary": "bg", "fallback": "ffxiclopedia"},
                key,
            )
            self.assertTrue(row["reconcile_module"], key)
            self.assertTrue(row.get("progression_module"), key)
            self.assertRegex(row.get("progression_revision", ""), r"^[0-9a-f]{64}$")
            for site, page in row["source_pages"].items():
                self.assertIn((site, page["page_id"]), source_pages, (key, site))
                revision = source_pages[(site, page["page_id"])]
                self.assertEqual(page["revision_id"], revision["revision_id"], (key, site))
                self.assertTrue(page["source_url"].startswith("https://"), (key, site))
                self.assertRegex(revision["content_sha256"], r"^[0-9a-f]{64}$", (key, site))

        expected_classes = {
            "native-sentinel": NATIVE_SENTINEL_KEYS,
            "chapter-index": CHAPTER_INDEX_KEYS,
            "native-placeholder": NATIVE_PLACEHOLDER_KEYS,
            "source-absent": SOURCE_ABSENT_KEYS,
        }
        self.assertEqual(
            coverage["counts"].get("by_source_missing_classification"),
            {classification: len(keys) for classification, keys in expected_classes.items()},
        )
        for classification, keys in expected_classes.items():
            self.assertEqual(
                {
                    key
                    for key, row in coverage["objectives"].items()
                    if row.get("source_missing_classification") == classification
                },
                keys,
            )
        for key, row in coverage["objectives"].items():
            if key not in SOURCE_MISSING_KEYS:
                self.assertFalse(row.get("source_missing_classification"), key)
                self.assertFalse(row.get("source_identity_pages"), key)
                continue
            self.assertEqual(row["status"], "source-missing", key)
            self.assertEqual(row["source_pages"], {}, key)
            self.assertEqual(row["source_modules"], {}, key)
            self.assertEqual(row["reconcile_module"], "", key)
            self.assertEqual(row["progression_module"], "", key)
            if key in CHAPTER_INDEX_KEYS:
                self.assertEqual(set(row.get("source_identity_pages", {})), {"ffxiclopedia"}, key)
                identity = row["source_identity_pages"]["ffxiclopedia"]
                self.assertIn(
                    ("ffxiclopedia", identity["page_id"]),
                    source_pages,
                    key,
                )
                self.assertEqual(
                    identity["revision_id"],
                    source_pages[("ffxiclopedia", identity["page_id"])]["revision_id"],
                    key,
                )
            else:
                self.assertEqual(row.get("source_identity_pages", {}), {}, key)
        self.assertEqual(
            coverage["objectives"]["mission:Rhapsodies of Vana'diel:62"]
            ["source_identity_pages"]["ffxiclopedia"]["match_method"],
            "chapter-ordinal-normalized",
        )
        self.assertEqual(
            coverage["objectives"]["mission:Seekers of Adoulin:95"]
            ["source_identity_pages"]["ffxiclopedia"]["match_method"],
            "chapter-disambiguator",
        )

        ledger = review.get("action_resolution_ledger", [])
        material_actions = [row for row in ledger if row.get("material") is True]
        self.assertTrue(material_actions)
        self.assertTrue(all(row.get("status") != "context-only" for row in material_actions))

        steps_by_objective: dict[str, list[dict[str, object]]] = {}
        stable_step_ids: set[str] = set()
        for step in review["steps"]:
            native_key = step["native_key"]
            stable_step_id = step["stable_step_id"]
            self.assertNotIn(stable_step_id, stable_step_ids)
            stable_step_ids.add(stable_step_id)
            steps_by_objective.setdefault(native_key, []).append(step)
        self.assertEqual(set(steps_by_objective), set(source_backed))
        for native_key, steps in steps_by_objective.items():
            ordered_ids = [step["stable_step_id"] for step in steps]
            self.assertEqual(ordered_ids, sorted(ordered_ids), native_key)
            self.assertEqual(
                ordered_ids,
                [f"{native_key}:step-{order:03d}" for order in range(1, len(steps) + 1)],
                native_key,
            )

    def test_generated_index_and_shards_are_exact_flat_and_self_pinned(self) -> None:
        coverage = _json(DATA_ROOT / "coverage.json")
        manifest = _json(DATA_ROOT / "native-manifest.json")
        review = _json(DATA_ROOT / "target-review.json")
        snapshot = _json(DATA_ROOT / "source-snapshot.json")
        manifest_by_key = {row["key"]: row for row in manifest["objectives"]}
        snapshot_by_identity = {
            (row["site"], row["page_id"]): row for row in snapshot["pages"]
        }
        zone_ids_by_name: dict[str, set[int]] = {}
        for line in (
            REPO_ROOT
            / "ashita"
            / "addons"
            / "accessxi_reader"
            / "data"
            / "ffxi-nav-zoneline-graph.tsv"
        ).read_text(encoding="utf-8").splitlines()[1:]:
            fields = line.split("\t")
            if len(fields) < 9 or not fields[0].isdigit():
                continue
            for zone_id, zone_name in ((int(fields[1]), fields[2]), (int(fields[7]), fields[8])):
                zone_ids_by_name.setdefault(zone_name.strip().casefold(), set()).add(zone_id)
        navigation_by_destination_id: dict[str, dict[str, object]] = {}
        navigation_path = (
            REPO_ROOT
            / "ashita"
            / "addons"
            / "accessxi_reader"
            / "data"
            / "ffxi-nav-destinations.tsv"
        )
        for line in navigation_path.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) < 10 or not fields[0].isdigit() or not fields[9].strip():
                continue
            destination_id = fields[9].strip()
            self.assertNotIn(destination_id, navigation_by_destination_id)
            navigation_by_destination_id[destination_id] = {
                "zone_id": int(fields[0]),
                "target_name": fields[1].strip(),
                "target_point": [float(fields[index]) for index in (2, 3, 4)],
                "target_kind": fields[5].strip(),
                "raw_identity": fields[10].strip() if len(fields) > 10 else "",
                "raw_spawn_ids": (
                    [int(value) for value in fields[11].split(",") if value]
                    if len(fields) > 11
                    else []
                ),
                "cluster_policy_version": fields[12].strip() if len(fields) > 12 else "",
            }
        actual_artifacts = {
            path.relative_to(REPO_ROOT).as_posix() for path in _artifact_paths()
        }
        self.assertEqual(actual_artifacts, _expected_artifact_paths())
        self.assertTrue(all(path.is_file() for path in _artifact_paths()))
        pinned_parsed_pages = _pinned_parsed_pages(coverage)
        raw_span_by_id: dict[str, object] = {}
        for native_key, coverage_row in coverage["objectives"].items():
            for site, source_page in coverage_row["source_pages"].items():
                parsed_page = pinned_parsed_pages[(site, source_page["page_id"])]
                for source_step in parsed_page.steps:
                    for source_span in source_step.action_spans:
                        source_span_id = (
                            f"{native_key}:{site}:step-{source_step.order:03d}:"
                            f"span-{source_span.order:02d}"
                        )
                        self.assertNotIn(source_span_id, raw_span_by_id)
                        raw_span_by_id[source_span_id] = source_span

        index_path = MODULE_ROOT / "mission_quest_guide_index.lua"
        index = _lua_values((index_path,))[index_path]
        self.assertEqual(len(index), 1844)
        self.assertEqual(set(index), set(manifest_by_key))
        for key in SOURCE_MISSING_KEYS:
            index_row = index[key]
            coverage_row = coverage["objectives"][key]
            expected_revision = hashlib.sha256(
                json.dumps(
                    {
                        "progression_schema_version": 2,
                        "progression_module": "",
                        "native_key": key,
                        "source_authority": {
                            "primary": "bg",
                            "fallback": "ffxiclopedia",
                        },
                        "progression_actions": [],
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                    separators=(",", ":"),
                ).encode("utf-8")
            ).hexdigest()
            self.assertEqual(index_row["progression_schema_version"], 2, key)
            self.assertEqual(index_row.get("progression_module") or "", "", key)
            self.assertEqual(index_row["progression_revision"], expected_revision, key)
            self.assertEqual(coverage_row["progression_schema_version"], 2, key)
            self.assertEqual(coverage_row["progression_module"], "", key)
            self.assertEqual(coverage_row["progression_revision"], expected_revision, key)

        source_paths = tuple(
            sorted(
                (*MODULE_ROOT.glob("mission_quest_bg_*.lua"),
                 *MODULE_ROOT.glob("mission_quest_ffxiclopedia_*.lua"))
            )
        )
        reconcile_paths = tuple(sorted(MODULE_ROOT.glob("mission_quest_reconcile_*.lua")))
        progression_paths = tuple(sorted(MODULE_ROOT.glob("mission_quest_progression_*.lua")))
        self.assertEqual((len(source_paths), len(reconcile_paths), len(progression_paths)), (51, 26, 26))

        source_values = _lua_values(source_paths)
        reconcile_values = _lua_values(reconcile_paths)
        progression_modules = _lua_values(progression_paths)
        source_module_by_name = {path.stem: values for path, values in source_values.items()}
        reconcile_keys_by_name = {
            path.stem: set(values) for path, values in reconcile_values.items()
        }
        progression_by_name = {
            path.stem: values for path, values in progression_modules.items()
        }
        reconcile_steps = [
            step
            for module in reconcile_values.values()
            for objective in module.values()
            for step in objective["steps"]
        ]
        self.assertEqual(len(reconcile_steps), 31197)
        for step in reconcile_steps:
            self.assertTrue(
                step.get("bg_instruction") or step.get("ffxiclopedia_instruction"),
                step["stable_step_id"],
            )

        material_ledger: dict[str, dict[str, dict[str, object]]] = {}
        nonmaterial_ids: set[str] = set()
        all_ledger_ids: set[str] = set()
        for row in review["action_resolution_ledger"]:
            action_id = row["action_id"]
            self.assertNotIn(action_id, all_ledger_ids)
            all_ledger_ids.add(action_id)
            if row["material"]:
                material_ledger.setdefault(row["native_key"], {})[action_id] = row
            else:
                nonmaterial_ids.add(action_id)
        typed_claim_ids: set[str] = set()
        expected_raw_span_ids: dict[str, tuple[str, ...]] = {}
        for step in review["steps"]:
            stable_step_id = step["stable_step_id"]
            typed_claims = step["typed_claims"]
            self.assertEqual(
                [claim["order"] for claim in typed_claims],
                list(range(1, len(typed_claims) + 1)),
                stable_step_id,
            )
            for claim in typed_claims:
                action_id = claim["stable_claim_id"]
                self.assertEqual(
                    action_id,
                    f"{stable_step_id}:claim-{claim['order']:02d}",
                    stable_step_id,
                )
                self.assertNotIn(action_id, typed_claim_ids)
                typed_claim_ids.add(action_id)
                expected_raw_span_ids[action_id] = tuple(
                    f"{step['native_key']}:{site}:step-{source_order:03d}:span-{span_order:02d}"
                    for site, source_order, span_order in (
                        ("bg", step["source_orders"][0], claim["bg_span_order"]),
                        (
                            "ffxiclopedia",
                            step["source_orders"][1],
                            claim["ffxiclopedia_span_order"],
                        ),
                    )
                    if source_order and span_order
                )
        self.assertTrue(typed_claim_ids.issubset(all_ledger_ids))
        self.assertEqual(len(typed_claim_ids), 22829)
        self.assertEqual(len(all_ledger_ids), 39727)
        context_ledger_ids = all_ledger_ids - typed_claim_ids
        self.assertEqual(len(context_ledger_ids), 16898)
        ledger_by_id = {
            row["action_id"]: row for row in review["action_resolution_ledger"]
        }
        for action_id in context_ledger_ids:
            row = ledger_by_id[action_id]
            self.assertTrue(action_id.endswith(":context-01"), action_id)
            self.assertEqual(row["status"], "context-only", action_id)
            self.assertEqual(row["reason"], "no-material-action-span", action_id)
            self.assertFalse(row["material"], action_id)
        typed_material_ids = {
            action_id for action_id in typed_claim_ids if ledger_by_id[action_id]["material"]
        }
        typed_nonmaterial_ids = typed_claim_ids - typed_material_ids
        self.assertEqual(len(typed_material_ids), 22479)
        self.assertEqual(len(typed_nonmaterial_ids), 350)
        seen_ledger_supplemental_action_ids: set[str] = set()
        for row in review["action_resolution_ledger"]:
            if row["action_id"] not in typed_claim_ids:
                continue
            raw_span_ids = tuple(
                source_span_id
                for source_span_id in row["source_action_span_ids"]
                if SOURCE_SPAN_ID.fullmatch(source_span_id)
            )
            supplemental_span_ids = tuple(
                source_span_id
                for source_span_id in row["source_action_span_ids"]
                if not SOURCE_SPAN_ID.fullmatch(source_span_id)
            )
            self.assertEqual(raw_span_ids, expected_raw_span_ids[row["action_id"]], row["action_id"])
            self.assertEqual(
                supplemental_span_ids,
                SUPPLEMENTAL_PROVENANCE_PINS.get(row["action_id"], ()),
                row["action_id"],
            )
            if supplemental_span_ids:
                seen_ledger_supplemental_action_ids.add(row["action_id"])
        self.assertEqual(
            seen_ledger_supplemental_action_ids,
            set(SUPPLEMENTAL_PROVENANCE_PINS),
        )
        old_authoritative_nonmaterial_ids: set[str] = set()
        current_authoritative_nonmaterial_ids: set[str] = set()
        for row in review["action_resolution_ledger"]:
            source_spans = {
                SOURCE_SPAN_ID.fullmatch(source_span_id).group("site"): raw_span_by_id[
                    source_span_id
                ]
                for source_span_id in row["source_action_span_ids"]
                if SOURCE_SPAN_ID.fullmatch(source_span_id)
            }
            if not source_spans:
                continue
            authoritative_span = source_spans.get("bg") or source_spans["ffxiclopedia"]
            self.assertEqual(row["material"], authoritative_span.material, row["action_id"])
            if not authoritative_span.material:
                current_authoritative_nonmaterial_ids.add(row["action_id"])
            if _independent_pre_polarity_prohibition(authoritative_span):
                old_authoritative_nonmaterial_ids.add(row["action_id"])
        self.assertEqual(len(old_authoritative_nonmaterial_ids), 232)
        self.assertEqual(
            current_authoritative_nonmaterial_ids,
            old_authoritative_nonmaterial_ids | PROHIBITED_ACTION_IDS,
        )
        self.assertEqual(len(current_authoritative_nonmaterial_ids), 350)
        review_candidates: dict[tuple[str, str, str], dict[str, object]] = {}
        review_destination_ids_by_action: dict[tuple[str, str], set[str]] = {}
        candidate_ids: set[str] = set()
        for row in review["objective_destination_candidates"]:
            candidate_id = row["candidate_id"]
            self.assertNotIn(candidate_id, candidate_ids)
            candidate_ids.add(candidate_id)
            candidate_key = (row["native_key"], row["action_id"], row["destination_id"])
            self.assertNotIn(candidate_key, review_candidates)
            review_candidates[candidate_key] = row
            review_destination_ids_by_action.setdefault(
                (row["native_key"], row["action_id"]), set()
            ).add(row["destination_id"])
            ledger = material_ledger[row["native_key"]][row["action_id"]]
            self.assertEqual(ledger["candidate_ids"].count(candidate_id), 1, candidate_id)
        self.assertEqual(
            candidate_ids,
            {
                candidate_id
                for rows in material_ledger.values()
                for ledger in rows.values()
                for candidate_id in ledger["candidate_ids"]
            },
        )
        self.assertIsNotNone(
            review_candidates.get(AFFIRMATIVE_SURVIVAL_GUIDE_CANDIDATE),
            AFFIRMATIVE_SURVIVAL_GUIDE_CANDIDATE,
        )
        self.assertEqual(len(candidate_ids), 1803)

        emitted_action_ids: set[str] = set()
        shard_objective_keys: set[str] = set()
        authoritative_transport_destinations = 0
        counted_semantics: Counter[tuple[str, str]] = Counter()
        seen_supplemental_action_ids: set[str] = set()

        def authoritative_value(bg_value: object, ffxi_value: object) -> tuple[object, str]:
            def present(value: object) -> bool:
                if isinstance(value, str):
                    return bool(value.strip())
                if isinstance(value, (tuple, list, dict, set)):
                    return bool(value)
                return value is not None

            if present(bg_value):
                return bg_value, "bg"
            if present(ffxi_value):
                return ffxi_value, "ffxiclopedia"
            return bg_value if bg_value is not None else ffxi_value, ""

        for module_name, module in progression_by_name.items():
            self.assertEqual(module["schema_version"], 2, module_name)
            self.assertEqual(module["module_name"], module_name, module_name)
            self.assertEqual(
                module["source_authority"],
                {"primary": "bg", "fallback": "ffxiclopedia"},
                module_name,
            )
            for key, payload in module["objectives"].items():
                self.assertNotIn(key, shard_objective_keys)
                shard_objective_keys.add(key)
                self.assertEqual(set(payload), PROGRESSION_PAYLOAD_FIELDS, key)
                self.assertEqual(payload["native_key"], key)
                self.assertEqual(payload["progression_module"], module_name, key)
                self.assertEqual(payload["progression_schema_version"], 2, key)
                self.assertEqual(
                    payload["source_authority"],
                    {"primary": "bg", "fallback": "ffxiclopedia"},
                    key,
                )
                self.assertEqual(
                    payload["progression_revision"],
                    _recomputed_progression_revision(payload),
                    key,
                )
                self.assertEqual(
                    payload["progression_revision"],
                    coverage["objectives"][key]["progression_revision"],
                    key,
                )
                self.assertEqual(
                    payload["progression_revision"],
                    index[key]["progression_revision"],
                    key,
                )
                expected_revisions = {
                    site: page["revision_id"]
                    for site, page in coverage["objectives"][key]["source_pages"].items()
                }
                actions = payload["progression_actions"]
                self.assertEqual(
                    [action["order"] for action in actions],
                    list(range(1, len(actions) + 1)),
                    key,
                )
                by_step: dict[str, list[int]] = {}
                for action in actions:
                    self.assertEqual(set(action), PROGRESSION_ACTION_FIELDS, action["action_id"])
                    self.assertEqual(
                        set(action["field_sources"]),
                        PROGRESSION_FIELD_SOURCE_FIELDS,
                        action["action_id"],
                    )
                    self.assertTrue(action["material"], action["action_id"])
                    self.assertNotIn(action["action_id"], emitted_action_ids)
                    self.assertNotIn(action["action_id"], nonmaterial_ids)
                    emitted_action_ids.add(action["action_id"])
                    self.assertEqual(
                        action["action_id"],
                        f"{action['step_id']}:claim-{action['action_order']:02d}",
                    )
                    self.assertEqual(
                        action["step_id"],
                        f"{key}:step-{action['step_order']:03d}",
                    )
                    by_step.setdefault(action["step_id"], []).append(action["action_order"])
                    self.assertEqual(action["source_revisions"], expected_revisions)
                    for site, revision_id in action["source_revisions"].items():
                        page = coverage["objectives"][key]["source_pages"][site]
                        self.assertEqual(
                            revision_id,
                            snapshot_by_identity[(site, page["page_id"])]["revision_id"],
                        )
                    ledger = material_ledger[key][action["action_id"]]
                    self.assertEqual(
                        action["source_action_span_ids"],
                        ledger["source_action_span_ids"],
                    )
                    source_spans: dict[str, object] = {}
                    raw_source_span_ids = [
                        source_span_id
                        for source_span_id in action["source_action_span_ids"]
                        if SOURCE_SPAN_ID.fullmatch(source_span_id)
                    ]
                    supplemental_pins = tuple(
                        source_span_id
                        for source_span_id in action["source_action_span_ids"]
                        if not SOURCE_SPAN_ID.fullmatch(source_span_id)
                    )
                    self.assertEqual(
                        supplemental_pins,
                        SUPPLEMENTAL_PROVENANCE_PINS.get(action["action_id"], ()),
                        action["action_id"],
                    )
                    if supplemental_pins:
                        seen_supplemental_action_ids.add(action["action_id"])
                    for source_span_id in raw_source_span_ids:
                        source_match = SOURCE_SPAN_ID.fullmatch(source_span_id)
                        self.assertIsNotNone(source_match, source_span_id)
                        self.assertEqual(source_match.group("native_key"), key, source_span_id)
                        site = source_match.group("site")
                        self.assertNotIn(site, source_spans, source_span_id)
                        source_span = raw_span_by_id.get(source_span_id)
                        self.assertIsNotNone(source_span, source_span_id)
                        source_spans[site] = source_span
                    self.assertTrue(source_spans, action["action_id"])
                    bg_span = source_spans.get("bg")
                    ffxi_span = source_spans.get("ffxiclopedia")
                    authoritative_span = bg_span or ffxi_span
                    self.assertTrue(authoritative_span.material, action["action_id"])
                    self.assertFalse(
                        _independent_direct_prohibition(authoritative_span),
                        action["action_id"],
                    )

                    def items_without_key_items(span: object | None) -> tuple[str, ...]:
                        if span is None:
                            return ()
                        key_items = {value.casefold() for value in span.key_item_mentions}
                        return tuple(
                            value
                            for value in span.item_mentions
                            if value.casefold() not in key_items
                        )

                    source_values = {
                        "action": (
                            bg_span.action if bg_span else "",
                            ffxi_span.action if ffxi_span else "",
                        ),
                        "relationship": (
                            bg_span.relationship if bg_span else "",
                            ffxi_span.relationship if ffxi_span else "",
                        ),
                        "target": (
                            bg_span.target if bg_span else "",
                            ffxi_span.target if ffxi_span else "",
                        ),
                        "target_kind": (
                            bg_span.target_kind if bg_span else "",
                            ffxi_span.target_kind if ffxi_span else "",
                        ),
                        "npcs": (
                            bg_span.npc_mentions if bg_span else (),
                            ffxi_span.npc_mentions if ffxi_span else (),
                        ),
                        "objects": (
                            bg_span.object_mentions if bg_span else (),
                            ffxi_span.object_mentions if ffxi_span else (),
                        ),
                        "enemies": (
                            bg_span.enemy_mentions if bg_span else (),
                            ffxi_span.enemy_mentions if ffxi_span else (),
                        ),
                        "items": (
                            items_without_key_items(bg_span),
                            items_without_key_items(ffxi_span),
                        ),
                        "key_items": (
                            bg_span.key_item_mentions if bg_span else (),
                            ffxi_span.key_item_mentions if ffxi_span else (),
                        ),
                        "transports": (
                            bg_span.transport_mentions if bg_span else (),
                            ffxi_span.transport_mentions if ffxi_span else (),
                        ),
                        "zones": (
                            bg_span.zone_mentions if bg_span else (),
                            ffxi_span.zone_mentions if ffxi_span else (),
                        ),
                        "destination_zone_name": (
                            bg_span.destination_zone_name if bg_span else "",
                            ffxi_span.destination_zone_name if ffxi_span else "",
                        ),
                        "grid_coordinates": (
                            bg_span.grid_coordinates if bg_span else (),
                            ffxi_span.grid_coordinates if ffxi_span else (),
                        ),
                        "result_items": (
                            bg_span.result_items if bg_span else (),
                            ffxi_span.result_items if ffxi_span else (),
                        ),
                        "result_relation": (
                            bg_span.result_relation if bg_span else "",
                            ffxi_span.result_relation if ffxi_span else "",
                        ),
                        "instruction": (
                            bg_span.supporting_clause if bg_span else "",
                            ffxi_span.supporting_clause if ffxi_span else "",
                        ),
                    }
                    expected_field_sources: dict[str, str] = {}
                    for field, (bg_value, ffxi_value) in source_values.items():
                        expected_value, expected_source = authoritative_value(
                            bg_value, ffxi_value
                        )
                        if isinstance(expected_value, tuple):
                            expected_value = list(expected_value)
                        self.assertEqual(action[field], expected_value, action["action_id"])
                        expected_field_sources[field] = expected_source

                    if bg_span is not None and bg_span.count_explicit:
                        count_span, count_source = bg_span, "bg"
                    elif ffxi_span is not None and ffxi_span.count_explicit:
                        count_span, count_source = ffxi_span, "ffxiclopedia"
                    elif bg_span is not None:
                        count_span, count_source = bg_span, "bg"
                    else:
                        count_span, count_source = ffxi_span, "ffxiclopedia"
                    self.assertIsNotNone(count_span, action["action_id"])
                    for field in ("required_count", "count_mode", "count_explicit"):
                        self.assertEqual(
                            action[field], getattr(count_span, field), action["action_id"]
                        )
                        expected_field_sources[field] = count_source
                    self.assertEqual(
                        action["target_key"],
                        _independent_target_key(action["target"]),
                        action["action_id"],
                    )
                    expected_field_sources["target_key"] = expected_field_sources["target"]
                    destination_ids = zone_ids_by_name.get(
                        action["destination_zone_name"].casefold(), set()
                    )
                    expected_destination_id = (
                        next(iter(destination_ids)) if len(destination_ids) == 1 else 0
                    )
                    self.assertEqual(
                        action["destination_zone_id"],
                        expected_destination_id,
                        action["action_id"],
                    )
                    expected_field_sources["destination_zone_id"] = (
                        expected_field_sources["destination_zone_name"]
                        if expected_destination_id > 0
                        else ""
                    )
                    expected_field_sources["catalogue"] = (
                        "catalogue" if action["catalogue"] else ""
                    )
                    self.assertEqual(
                        action["source_authority"],
                        "bg" if bg_span is not None else "ffxiclopedia",
                        action["action_id"],
                    )
                    self.assertEqual(
                        action["field_sources"],
                        expected_field_sources,
                        action["action_id"],
                    )
                    required_count = action["required_count"]
                    self.assertIs(type(required_count), int)
                    self.assertGreaterEqual(required_count, 1)
                    self.assertIn(action["count_mode"], {"single", "credited-defeat", "inventory-gain"})
                    count_sources = {
                        action["field_sources"][field]
                        for field in ("required_count", "count_mode", "count_explicit")
                    }
                    self.assertEqual(len(count_sources), 1)
                    self.assertTrue(count_sources.issubset({"bg", "ffxiclopedia"}))
                    if required_count == 1:
                        self.assertEqual(action["count_mode"], "single")
                    else:
                        self.assertTrue(action["count_explicit"])
                        if action["result_relation"] == "obtain-from":
                            self.assertIn(
                                action["relationship"],
                                {"defeat-to-obtain", "examine-to-obtain"},
                            )
                            self.assertEqual(action["count_mode"], "inventory-gain")
                            counted_semantics[(action["relationship"], "inventory-gain")] += 1
                        elif action["action"] == "fight":
                            self.assertEqual(action["relationship"], "defeat-enemy")
                            self.assertEqual(action["count_mode"], "credited-defeat")
                            counted_semantics[("defeat-enemy", "credited-defeat")] += 1
                        elif action["action"] in {"obtain", "collect"}:
                            self.assertEqual(action["count_mode"], "inventory-gain")
                            counted_semantics[("obtain-item", "inventory-gain")] += 1
                        else:
                            self.fail(
                                f"Unsupported counted action {action['action']!r}: {action['action_id']}"
                            )
                    destination_zone_name = action["destination_zone_name"]
                    destination_zone_id = action["destination_zone_id"]
                    self.assertIs(type(destination_zone_name), str)
                    self.assertIs(type(destination_zone_id), int)
                    self.assertGreaterEqual(destination_zone_id, 0)
                    if destination_zone_id > 0:
                        self.assertTrue(destination_zone_name)
                        self.assertEqual(
                            zone_ids_by_name.get(destination_zone_name.casefold()),
                            {destination_zone_id},
                            action["action_id"],
                        )
                        self.assertEqual(
                            action["field_sources"]["destination_zone_id"],
                            action["field_sources"]["destination_zone_name"],
                            action["action_id"],
                        )
                        if action["relationship"] == "board-transport":
                            authoritative_transport_destinations += 1
                    else:
                        self.assertEqual(
                            action["field_sources"]["destination_zone_id"],
                            "",
                            action["action_id"],
                        )
                    catalogue_by_id = {
                        candidate["destination_id"]: candidate
                        for candidate in action["catalogue"]
                    }
                    self.assertEqual(
                        len(catalogue_by_id),
                        len(action["catalogue"]),
                        action["action_id"],
                    )
                    self.assertEqual(
                        set(catalogue_by_id),
                        review_destination_ids_by_action.get(
                            (key, action["action_id"]), set()
                        ),
                        action["action_id"],
                    )
                    self.assertEqual(
                        action["field_sources"]["catalogue"],
                        "catalogue" if catalogue_by_id else "",
                    )
                    for candidate in catalogue_by_id.values():
                        self.assertEqual(set(candidate), PROGRESSION_CATALOGUE_FIELDS)
                        self.assertRegex(candidate["destination_id"], r"^.+$")
                        self.assertGreater(candidate["zone_id"], 0)
                        self.assertTrue(candidate["zone_name"])
                        self.assertIn(
                            candidate["zone_id"],
                            zone_ids_by_name.get(candidate["zone_name"].casefold(), set()),
                            candidate["destination_id"],
                        )
                        navigation = navigation_by_destination_id[candidate["destination_id"]]
                        review_candidate = review_candidates[
                            (key, action["action_id"], candidate["destination_id"])
                        ]
                        self.assertEqual(review_candidate["native_key"], key)
                        self.assertEqual(review_candidate["action_id"], action["action_id"])
                        self.assertTrue(
                            set(review_candidate["source_action_span_ids"]).issubset(
                                action["source_action_span_ids"]
                            ),
                            review_candidate["candidate_id"],
                        )
                        self.assertTrue(review_candidate["source_action_span_ids"])
                        self.assertTrue(review_candidate["source_sites"])
                        self.assertEqual(
                            set(review_candidate["source_revisions"]),
                            set(review_candidate["source_sites"]),
                        )
                        self.assertTrue(
                            set(review_candidate["source_sites"]).issubset(
                                action["source_revisions"]
                            )
                        )
                        self.assertEqual(
                            review_candidate["source_revisions"],
                            {
                                site: action["source_revisions"][site]
                                for site in review_candidate["source_sites"]
                            },
                        )
                        self.assertEqual(
                            candidate["target_key"],
                            _independent_target_key(review_candidate["target_name"]),
                        )
                        for catalogue_field, review_field in (
                            ("zone_id", "zone"),
                            ("zone_name", "zone_name"),
                            ("target_name", "target_name"),
                            ("target_kind", "target_kind"),
                            ("target_point", "target_point"),
                            ("raw_identity", "raw_identity"),
                            ("raw_spawn_ids", "raw_spawn_ids"),
                            ("cluster_policy_version", "cluster_policy_version"),
                            ("transport_id", "transport_id"),
                            ("battlefield_id", "battlefield_id"),
                            ("metadata_class", "metadata_class"),
                            ("group_id", "group_id"),
                            ("arrival_instruction", "arrival_instruction"),
                        ):
                            self.assertEqual(
                                candidate[catalogue_field],
                                review_candidate[review_field],
                                candidate["destination_id"],
                            )
                        for field in (
                            "zone_id",
                            "target_name",
                            "target_kind",
                            "target_point",
                            "raw_identity",
                            "raw_spawn_ids",
                            "cluster_policy_version",
                        ):
                            self.assertEqual(
                                candidate[field],
                                navigation[field],
                                candidate["destination_id"],
                            )
                for step_id, orders in by_step.items():
                    self.assertEqual(orders, sorted(orders), step_id)

                self.assertEqual(
                    {action["action_id"] for action in actions},
                    set(material_ledger.get(key, {})),
                    key,
                )

        self.assertEqual(shard_objective_keys, set(manifest_by_key).difference(SOURCE_MISSING_KEYS))
        self.assertEqual(emitted_action_ids, set().union(*(set(rows) for rows in material_ledger.values())))
        self.assertEqual(emitted_action_ids, typed_material_ids)
        self.assertEqual(len(PROHIBITED_ACTION_IDS), 118)
        self.assertEqual(len(CONTRAST_ACTION_IDS), 15)
        self.assertEqual(len(LEGACY_PROHIBITED_ACTION_IDS), 10)
        self.assertTrue(PROHIBITED_ACTION_IDS.isdisjoint(emitted_action_ids))
        self.assertTrue(PROHIBITED_ACTION_IDS.issubset(nonmaterial_ids))
        self.assertTrue(LEGACY_PROHIBITED_ACTION_IDS.isdisjoint(emitted_action_ids))
        self.assertTrue(LEGACY_PROHIBITED_ACTION_IDS.issubset(nonmaterial_ids))
        self.assertTrue(CONTRAST_ACTION_IDS.issubset(emitted_action_ids))
        self.assertEqual(
            seen_supplemental_action_ids, set(SUPPLEMENTAL_PROVENANCE_PINS)
        )
        self.assertGreater(authoritative_transport_destinations, 0)
        self.assertGreater(counted_semantics[("defeat-enemy", "credited-defeat")], 0)
        self.assertGreater(counted_semantics[("defeat-to-obtain", "inventory-gain")], 0)
        self.assertGreater(counted_semantics[("examine-to-obtain", "inventory-gain")], 0)
        self.assertGreater(counted_semantics[("obtain-item", "inventory-gain")], 0)

        for key, native in manifest_by_key.items():
            coverage_row = coverage["objectives"][key]
            index_row = index[key]
            self.assertEqual(
                (index_row["kind"], index_row["context"], index_row["native_id"], index_row["title"]),
                (native["kind"], native["context"], native["native_id"], native["title"]),
                key,
            )
            self.assertEqual(index_row["status"], coverage_row["status"], key)
            self.assertEqual(index_row["source_authority"], coverage_row["source_authority"], key)
            source_modules = index_row.get("source_modules") or {}
            self.assertEqual(source_modules, coverage_row["source_modules"], key)
            for site, module_name in source_modules.items():
                self.assertIn(key, source_module_by_name[module_name], key)
                source_page = source_module_by_name[module_name][key]["page"]
                expected_page = coverage_row["source_pages"][site]
                self.assertEqual(source_page["page_id"], expected_page["page_id"], key)
                self.assertEqual(source_page["revision_id"], expected_page["revision_id"], key)
                snapshot_page = snapshot_by_identity[(site, source_page["page_id"])]
                self.assertEqual(source_page["content_sha256"], snapshot_page["content_sha256"], key)
            if coverage_row["reconcile_module"]:
                self.assertIn(key, reconcile_keys_by_name[coverage_row["reconcile_module"]], key)
            self.assertEqual(index_row.get("reconcile_module") or "", coverage_row["reconcile_module"])
            self.assertEqual(index_row.get("progression_module") or "", coverage_row["progression_module"])

    def test_runtime_corpus_footprint_stays_compact_and_evidence_remains_json_only(self) -> None:
        source_paths = tuple(
            (*MODULE_ROOT.glob("mission_quest_bg_*.lua"),
             *MODULE_ROOT.glob("mission_quest_ffxiclopedia_*.lua"))
        )
        reconcile_paths = tuple(MODULE_ROOT.glob("mission_quest_reconcile_*.lua"))
        progression_paths = tuple(MODULE_ROOT.glob("mission_quest_progression_*.lua"))
        index_path = MODULE_ROOT / "mission_quest_guide_index.lua"
        source_bytes = sum(path.stat().st_size for path in source_paths)
        reconcile_bytes = sum(path.stat().st_size for path in reconcile_paths)
        progression_bytes = sum(path.stat().st_size for path in progression_paths)
        presentation_bytes = source_bytes + reconcile_bytes + index_path.stat().st_size
        runtime_bytes = presentation_bytes + progression_bytes

        self.assertLessEqual(presentation_bytes, MAX_PRESENTATION_BYTES)
        self.assertLessEqual(progression_bytes, MAX_PROGRESSION_BYTES)
        self.assertLessEqual(runtime_bytes, MAX_CORPUS_RUNTIME_BYTES)
        self.assertEqual((len(source_paths), len(reconcile_paths), len(progression_paths)), (51, 26, 26))
        self.assertTrue(
            all("action_spans =" not in path.read_text(encoding="utf-8") for path in source_paths)
        )
        forbidden_reconcile = (
            "typed_claims =",
            "action_resolution_ledger =",
            "objective_destination_candidates =",
        )
        self.assertTrue(
            all(
                all(token not in path.read_text(encoding="utf-8") for token in forbidden_reconcile)
                for path in reconcile_paths
            )
        )
        forbidden_progression = (
            "claims =",
            "typed_claims =",
            "action_resolution_ledger =",
            "objective_destination_candidates =",
        )
        self.assertTrue(
            all(
                all(token not in path.read_text(encoding="utf-8") for token in forbidden_progression)
                for path in progression_paths
            )
        )
        review = _json(DATA_ROOT / "target-review.json")
        self.assertTrue(review["action_resolution_ledger"])
        self.assertTrue(review["objective_destination_candidates"])
        self.assertTrue(any(step["typed_claims"] for step in review["steps"]))

    def test_git_archive_preserves_deterministic_jsonl_bytes(self) -> None:
        relative_path = "data/mission-quest-guides/route-evidence-v2.jsonl"
        result = subprocess.run(
            [
                "git",
                "-c",
                f"safe.directory={REPO_ROOT.as_posix()}",
                "archive",
                "--worktree-attributes",
                "--format=tar",
                "HEAD",
                "--",
                relative_path,
            ],
            cwd=REPO_ROOT,
            capture_output=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        with tarfile.open(fileobj=io.BytesIO(result.stdout), mode="r:") as archive:
            member = archive.extractfile(relative_path)
            self.assertIsNotNone(member)
            archived_bytes = member.read()
        self.assertEqual(
            archived_bytes,
            (REPO_ROOT / relative_path).read_bytes(),
            "Git archive changed the byte-pinned JSONL corpus artifact",
        )

    def test_second_offline_build_is_byte_identical_for_checked_in_generated_artifacts(self) -> None:
        command = [
            str(PYTHON),
            "-m",
            "tools.objective_guides.cli",
            "all",
            "--repo-root",
            ".",
            "--ffxi-root",
            str(FFXI_ROOT),
            "--offline",
        ]
        frozen_hashes = _artifact_hashes()
        first = subprocess.run(
            command, cwd=REPO_ROOT, text=True, capture_output=True, timeout=900
        )
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        first_hashes = _artifact_hashes()
        self.assertEqual(frozen_hashes, first_hashes)
        second = subprocess.run(
            command, cwd=REPO_ROOT, text=True, capture_output=True, timeout=900
        )
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(first_hashes, _artifact_hashes())


if __name__ == "__main__":
    unittest.main()

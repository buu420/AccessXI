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

# Independent semantic audit contract.  These predicates intentionally do not
# import the production wikitext classifier: generated reducer actions must
# survive a second implementation of the player-instruction boundary.
SEMANTIC_ACTION_MATCH = re.compile(
    r"\b(?P<verb>re-examine|examine|touch|click|inspect|check|trade|give|hand over|deliver|"
    r"talk|speak|return to|report to|visit|defeat|defeating|fight|kill|killing|slay|slaying|destroy|"
    r"obtain|receive|collect|purchase|go to|head to|travel to|enter|exit|zone into|proceed to|"
    r"make your way to|wait|use|activate|light|open|protect|select|choose|board)\b",
    re.IGNORECASE,
)
SEMANTIC_DETERMINERS = (
    "the|this|a|an|each|every|another|following|previous|next|upcoming|same|"
    "entire|whole|final|initial|first|second|your|that|such"
)
SEMANTIC_COPULAR_FIGHT_FOLLOWERS = (
    "is|was|are|were|can|will|may|should|has|had|begins|starts|ends|lasts|"
    "takes|continues|progresses|appears|does|needs|makes"
)
SEMANTIC_LIGHT_PREDECESSORS = (
    "of|item|fire|dark|wind|earth|water|ice|lightning|the|a|an|with"
)
SEMANTIC_LIGHT_FOLLOWERS = (
    "of|crystal|elemental|element|magic|damage|attack|attacks|based|ore|cluster|"
    "sap|skillchain|weather|shot|spirit|maneuver"
)
SEMANTIC_GENERIC_RECEIVE_TARGET = re.compile(
    r"\b(?:message|announcement|cutscene|option|credit|reward|title|experience|EXP)\b",
    re.IGNORECASE,
)
SEMANTIC_FALSE_UNION_FAMILIES = frozenset(
    {
        "will_give",
        "give_up",
        "noun_fight",
        "noun_use",
        "use_this_time",
        "lexical_light",
        "adjective_open",
        "will_open",
        "noun_board",
        "spell_protect",
        "external_return",
        "generic_receive",
        "check_status",
        "select_pool",
        "malformed_target",
    }
)
SEMANTIC_BRANCH_GUIDANCE_PATTERNS = {
    "conditional_guidance": re.compile(r"^\s*[\[(]?\s*if\b", re.IGNORECASE),
    "optional_guidance": re.compile(
        r"(?:^\s*[\[(]?\s*optional(?:ly)?\s*[\])]?\s*:?|"
        r"\b(?:this\s+)?step\s+is\s+optional\b)",
        re.IGNORECASE,
    ),
    "alternative_guidance": re.compile(
        r"^\s*(?:[\[(]?\s*)?(?:alternatively\b|alternative\s*:|or\b|either\b|"
        r"another\s+(?:option|method|way)\b)",
        re.IGNORECASE,
    ),
    "preference_guidance": re.compile(
        r"\bif\s+you\s+(?:want|wish|prefer|choose|decide|would\s+like|"
        r"do\s+not\s+want|don['’]t\s+want)\b",
        re.IGNORECASE,
    ),
    "repeat_guidance": re.compile(
        r"(?:^|\b)(?:(?:when|while)\s+repeating\b|(?:for|on)\s+(?:a\s+)?repeat\b|"
        r"if\s+(?:repeating|redoing)\b|repeat(?:ing)?\s+(?:the\s+)?"
        r"(?:quest|mission)\b)",
        re.IGNORECASE,
    ),
    "advice_guidance": re.compile(
        r"^\s*(?:[\[(]?\s*)?(?:(?:strategy|tip|note|warning|recommendation|"
        r"recommended)\s*:|best\s+to\b|be\s+careful\b)",
        re.IGNORECASE,
    ),
}
SEMANTIC_STRICT_FALSE_UNION_FAMILIES = frozenset(
    (
        *SEMANTIC_FALSE_UNION_FAMILIES,
        "modal_use",
        "internal_alternative_guidance",
        "entity_alternative_guidance",
        *SEMANTIC_BRANCH_GUIDANCE_PATTERNS,
    )
)
SEMANTIC_FALSE_RED_BASELINE = {
    "commit": "d1fe063a6d32e36ea80331fc7a0aa08c5017bd9c",
    "material_rows": 22479,
    "high_confidence_union": {
        "actions": 2252,
        "objectives": 920,
        "steps": 2057,
        "by_action": {
            "examine": 185,
            "fight": 606,
            "obtain": 537,
            "protect": 20,
            "select": 65,
            "talk": 254,
            "trade": 298,
            "travel": 55,
            "use": 232,
        },
    },
    "strict_flat_reducer_union": {
        "actions": 4157,
        "objectives": 1184,
        "steps": 3784,
        "by_action": {
            "examine": 315,
            "fight": 728,
            "obtain": 728,
            "protect": 21,
            "select": 152,
            "talk": 720,
            "trade": 396,
            "travel": 295,
            "use": 714,
            "wait": 88,
        },
    },
}
RENDERER_SPEECH_DUPLICATE_FOLLOWUP_IDS = frozenset(
    {
        "mission:Bastok:12:step-003:claim-01",
        "mission:Bastok:3:step-003:claim-01",
        "mission:Bastok:4:step-004:claim-01",
        "mission:Bastok:5:step-003:claim-01",
        "mission:Campaign:68:step-002:claim-01",
        "mission:Windurst:21:step-011:claim-02",
        "quest:aht_urhgan:77:step-011:claim-01",
        "quest:crystal_war:67:step-002:claim-01",
    }
)

# Independent source-obligation audit.  These predicates intentionally do not
# import the production player-instruction classifier.  The exact 59-span
# baseline was frozen from d1fe063 before the bounded obligation fix; 47 are
# required player barriers and 12 are reviewed branch/advice exceptions.
OBLIGATION_CUE_PATTERNS = {
    "passive_player_obligation": re.compile(
        r"\byou\s+(?:are|were|have\s+been)\s+"
        r"(?:asked|instructed|required|requested|told|ordered|tasked|expected)\s+"
        r"to(?:\s+now)?\s*$",
        re.IGNORECASE,
    ),
    "possessive_task": re.compile(
        r"\byour\s+(?:task|objective|orders?)\s+(?:is|are)\s+to(?:\s+now)?\s*$",
        re.IGNORECASE,
    ),
    "actor_directive": re.compile(
        r"\b(?:tells?|told|tasks?|tasked|orders?|ordered|expects?|expected)\s+"
        r"you\s+to(?:\s+now)?\s*$",
        re.IGNORECASE,
    ),
    "passive_directive": re.compile(
        r"\byou\s+(?:will\s+be|are|were)\s+"
        r"(?:told|asked|instructed|ordered|tasked|required|expected)\s+"
        r"to(?:\s+now)?\s*$",
        re.IGNORECASE,
    ),
    "goal_is_to": re.compile(
        r"\b(?:the\s+)?(?:goal|aim|next\s+step|objective|task)\s+"
        r"(?:is|will\s+be)\s+to(?:\s+now)?\s*$",
        re.IGNORECASE,
    ),
}
OBLIGATION_REJECT_IDENTITIES = frozenset(
    {
        ("bg", 19733, 762436, 13, 1),
        ("bg", 102306, 661567, 14, 1),
        ("bg", 71, 724760, 6, 1),
        ("bg", 58960, 725244, 8, 1),
        ("bg", 117267, 766576, 2, 2),
        ("bg", 117267, 766576, 6, 2),
        ("bg", 38725, 771667, 11, 1),
        ("bg", 110864, 768481, 4, 1),
        ("ffxiclopedia", 170470, 1798295, 2, 1),
        ("ffxiclopedia", 125762, 1793247, 5, 1),
        ("ffxiclopedia", 125762, 1793247, 6, 1),
        ("ffxiclopedia", 125762, 1793247, 7, 1),
    }
)

# Independent direct-imperative audit.  The 80 identities were frozen after
# extractor-debris recovery against the pinned source revisions.  Review then
# separated 40 required head actions from 40 genuine branch/advice choices;
# production materiality helpers are intentionally not reused here.
DIRECT_IMPERATIVE_START = re.compile(
    r"^\s*(?:(?:first|next|then|finally|afterwards|now)\s*[,;:]\s*)?"
    r"(?P<verb>re-examine|examine|touch|click|inspect|check|trade|hand over|"
    r"deliver|talk|speak|return to|report to|visit|defeat|kill|slay|destroy|"
    r"obtain|collect|purchase|go to|head to|travel to|enter|exit|zone into|"
    r"proceed to|make your way to|wait|use|activate|protect|select|choose)\b",
    re.IGNORECASE,
)
DIRECT_IMPERATIVE_ADMIT_IDENTITIES = frozenset(
    {
        ("bg", 13164, 774298, 9, 1),
        ("bg", 44, 768836, 6, 1),
        ("bg", 71, 724760, 15, 1),
        ("bg", 156, 695577, 3, 1),
        ("bg", 42227, 748419, 51, 1),
        ("bg", 117267, 766576, 6, 1),
        ("bg", 120849, 745636, 3, 1),
        ("bg", 12700, 774331, 8, 1),
        ("bg", 38703, 773744, 3, 1),
        ("bg", 284, 684880, 2, 1),
        ("bg", 143553, 774145, 2, 1),
        ("bg", 144444, 768451, 3, 1),
        ("bg", 13294, 767352, 8, 1),
        ("ffxiclopedia", 136928, 1792377, 28, 1),
        ("ffxiclopedia", 10632, 1551846, 1, 1),
        ("ffxiclopedia", 10632, 1551846, 3, 1),
        ("ffxiclopedia", 10630, 1551848, 1, 1),
        ("ffxiclopedia", 10630, 1551848, 4, 1),
        ("ffxiclopedia", 10577, 1551847, 1, 1),
        ("ffxiclopedia", 10577, 1551847, 3, 1),
        ("ffxiclopedia", 9925, 927517, 2, 1),
        ("ffxiclopedia", 179622, 1585943, 3, 1),
        ("ffxiclopedia", 130056, 1737938, 5, 1),
        ("ffxiclopedia", 53568, 1751774, 13, 1),
        ("ffxiclopedia", 11396, 1795852, 8, 1),
        ("ffxiclopedia", 179476, 1695862, 16, 1),
        ("ffxiclopedia", 8355, 1764589, 4, 1),
        ("ffxiclopedia", 8985, 1782338, 14, 1),
        ("ffxiclopedia", 197578, 1770024, 4, 1),
        ("ffxiclopedia", 39115, 1749400, 5, 1),
        ("ffxiclopedia", 12571, 1803973, 5, 1),
        ("ffxiclopedia", 3300, 1720865, 2, 1),
        ("ffxiclopedia", 9882, 1782492, 2, 1),
        ("ffxiclopedia", 30313, 1747753, 1, 1),
        ("ffxiclopedia", 211495, 1780825, 5, 1),
        ("ffxiclopedia", 3711, 1795833, 9, 1),
        ("ffxiclopedia", 8462, 1794200, 41, 1),
        ("ffxiclopedia", 10627, 1792830, 2, 1),
        ("ffxiclopedia", 8315, 1772189, 3, 1),
        ("ffxiclopedia", 13358, 1780673, 5, 1),
    }
)
DIRECT_IMPERATIVE_REJECT_IDENTITIES = frozenset(
    {
        ("bg", 50609, 645022, 1, 1),
        ("bg", 38765, 631597, 12, 1),
        ("bg", 26296, 775115, 3, 1),
        ("bg", 81, 735922, 3, 1),
        ("bg", 38783, 384997, 2, 1),
        ("bg", 101762, 699252, 1, 1),
        ("bg", 213, 751548, 3, 1),
        ("bg", 11514, 764231, 29, 1),
        ("bg", 11692, 723288, 25, 1),
        ("bg", 116513, 766554, 1, 1),
        ("bg", 12650, 766961, 1, 1),
        ("bg", 143839, 774151, 18, 1),
        ("bg", 25923, 63768, 4, 1),
        ("bg", 58960, 725244, 1, 1),
        ("ffxiclopedia", 67362, 1777762, 5, 1),
        ("ffxiclopedia", 20025, 1781944, 4, 1),
        ("ffxiclopedia", 207275, 1730672, 1, 1),
        ("ffxiclopedia", 17466, 1776050, 5, 1),
        ("ffxiclopedia", 3396, 1782330, 7, 1),
        ("ffxiclopedia", 210485, 1715349, 2, 1),
        ("ffxiclopedia", 26811, 1551867, 21, 1),
        ("ffxiclopedia", 20172, 1551943, 2, 1),
        ("ffxiclopedia", 4538, 1769084, 16, 1),
        ("ffxiclopedia", 209402, 1727984, 37, 1),
        ("ffxiclopedia", 4773, 1781610, 1, 1),
        ("ffxiclopedia", 201595, 1800068, 11, 1),
        ("ffxiclopedia", 201005, 1704032, 1, 1),
        ("ffxiclopedia", 144549, 1552335, 4, 1),
        ("ffxiclopedia", 210486, 1724412, 12, 1),
        ("ffxiclopedia", 188138, 1749165, 2, 1),
        ("ffxiclopedia", 4174, 1803778, 46, 1),
        ("ffxiclopedia", 201582, 1727098, 10, 1),
        ("ffxiclopedia", 8354, 1780299, 4, 1),
        ("ffxiclopedia", 22059, 1757306, 25, 1),
        ("ffxiclopedia", 257929, 1755833, 3, 1),
        ("ffxiclopedia", 26782, 1756172, 16, 1),
        ("ffxiclopedia", 209846, 1750146, 1, 1),
        ("ffxiclopedia", 4506, 1724252, 1, 1),
        ("ffxiclopedia", 20313, 1790015, 4, 1),
        ("ffxiclopedia", 20313, 1790015, 13, 1),
    }
)


DIRECT_IMPERATIVE_SUPPLEMENTAL_ADMIT_IDENTITIES = frozenset(
    {
        ("bg", 98197, 610221, 12, 1),
        ("bg", 98197, 610221, 16, 1),
        ("bg", 112166, 748994, 1, 1),
        ("bg", 13168, 766614, 1, 1),
        ("bg", 89, 747438, 3, 1),
        ("bg", 15062, 750965, 5, 1),
        ("bg", 104680, 769835, 3, 1),
        ("bg", 38746, 767809, 10, 1),
        ("bg", 124, 762675, 3, 1),
        ("bg", 11618, 770664, 10, 1),
        ("bg", 89258, 693673, 10, 1),
        ("bg", 120852, 744531, 1, 1),
        ("bg", 12678, 766638, 1, 1),
        ("bg", 38775, 774830, 5, 1),
        ("bg", 25925, 721807, 2, 1),
        ("bg", 38713, 770215, 1, 1),
        ("bg", 26170, 689337, 1, 1),
        ("bg", 110864, 768481, 8, 1),
        ("bg", 13289, 767470, 1, 1),
        ("bg", 13293, 773992, 1, 1),
        ("bg", 21070, 774574, 17, 1),
        ("ffxiclopedia", 207266, 1781832, 4, 1),
        ("ffxiclopedia", 20004, 1751874, 1, 1),
        ("ffxiclopedia", 8264, 1763260, 2, 1),
        ("ffxiclopedia", 12894, 1775532, 12, 1),
        ("ffxiclopedia", 201803, 1777037, 2, 1),
        ("ffxiclopedia", 8422, 1762871, 13, 1),
        ("ffxiclopedia", 197585, 1762094, 2, 1),
        ("ffxiclopedia", 3718, 1747094, 1, 1),
        ("ffxiclopedia", 13087, 1734730, 3, 1),
        ("ffxiclopedia", 13087, 1734730, 4, 1),
        ("ffxiclopedia", 13087, 1734730, 5, 1),
        ("ffxiclopedia", 12611, 1794199, 15, 1),
        ("ffxiclopedia", 7848, 1396690, 5, 1),
        ("ffxiclopedia", 13493, 1783877, 3, 1),
        ("ffxiclopedia", 13164, 1719601, 4, 1),
        ("ffxiclopedia", 8067, 1801110, 3, 1),
        ("ffxiclopedia", 13282, 1754892, 3, 1),
        ("ffxiclopedia", 26819, 1765239, 2, 1),
        ("ffxiclopedia", 20131, 1772417, 10, 1),
    }
)


DIRECT_IMPERATIVE_SUPPLEMENTAL_REJECT_IDENTITIES = frozenset(
    {
        ("bg", 56926, 735283, 11, 1),
        ("bg", 13172, 774999, 13, 1),
        ("bg", 56922, 770985, 17, 1),
        ("bg", 12117, 732248, 6, 1),
        ("bg", 1787, 767515, 2, 1),
        ("bg", 123332, 733053, 3, 1),
        ("bg", 25923, 63768, 3, 1),
        ("bg", 13129, 767960, 21, 1),
        ("ffxiclopedia", 46038, 1780072, 2, 1),
        ("ffxiclopedia", 208261, 1730725, 1, 1),
        ("ffxiclopedia", 201605, 1582968, 16, 1),
        ("ffxiclopedia", 11447, 1721789, 3, 1),
        ("ffxiclopedia", 11427, 1787854, 14, 1),
        ("ffxiclopedia", 13595, 1780468, 10, 1),
        ("ffxiclopedia", 8128, 1748635, 10, 1),
        ("ffxiclopedia", 12258, 1776520, 9, 1),
    }
)
OBLIGATION_BASELINE_IDENTITIES = frozenset(
    {
        ("bg", 40344, 750529, 10, 1),
        ("bg", 19733, 762436, 13, 1),
        ("bg", 43045, 668354, 6, 1),
        ("bg", 6, 774429, 12, 1),
        ("bg", 102306, 661567, 14, 1),
        ("bg", 58976, 773835, 3, 1),
        ("bg", 11920, 712438, 4, 3),
        ("bg", 13178, 769204, 3, 1),
        ("bg", 48, 727555, 4, 3),
        ("bg", 67143, 651775, 2, 1),
        ("bg", 12117, 732248, 4, 3),
        ("bg", 71, 724760, 6, 1),
        ("bg", 11822, 727419, 4, 3),
        ("bg", 103, 767949, 1, 2),
        ("bg", 40340, 763079, 7, 1),
        ("bg", 125, 758137, 4, 3),
        ("bg", 58960, 725244, 8, 1),
        ("bg", 67141, 671975, 5, 1),
        ("bg", 486, 754676, 4, 3),
        ("bg", 487, 746946, 5, 1),
        ("bg", 205, 756999, 4, 3),
        ("bg", 117267, 766576, 2, 2),
        ("bg", 117267, 766576, 6, 2),
        ("bg", 12650, 766961, 2, 1),
        ("bg", 58978, 767233, 3, 1),
        ("bg", 11947, 730452, 5, 1),
        ("bg", 498, 764545, 4, 3),
        ("bg", 19682, 760903, 1, 2),
        ("bg", 12119, 712443, 4, 3),
        ("bg", 38725, 771667, 11, 1),
        ("bg", 12120, 712436, 4, 3),
        ("bg", 11936, 733900, 4, 3),
        ("bg", 110864, 768481, 4, 1),
        ("bg", 15077, 771214, 9, 1),
        ("bg", 313, 772667, 16, 3),
        ("ffxiclopedia", 6940, 1760723, 9, 1),
        ("ffxiclopedia", 4228, 1794092, 23, 3),
        ("ffxiclopedia", 126147, 1776951, 4, 1),
        ("ffxiclopedia", 8133, 1765921, 6, 1),
        ("ffxiclopedia", 8413, 1793411, 7, 1),
        ("ffxiclopedia", 5746, 1771123, 20, 2),
        ("ffxiclopedia", 11419, 1782026, 4, 1),
        ("ffxiclopedia", 170470, 1798295, 2, 1),
        ("ffxiclopedia", 8066, 1779650, 4, 1),
        ("ffxiclopedia", 136936, 1791166, 1, 1),
        ("ffxiclopedia", 265067, 1794450, 4, 2),
        ("ffxiclopedia", 8313, 1551316, 14, 1),
        ("ffxiclopedia", 13038, 1769958, 2, 2),
        ("ffxiclopedia", 13036, 1794214, 1, 1),
        ("ffxiclopedia", 60734, 1736452, 4, 1),
        ("ffxiclopedia", 42397, 1775989, 11, 2),
        ("ffxiclopedia", 144363, 1755001, 9, 1),
        ("ffxiclopedia", 144363, 1755001, 24, 1),
        ("ffxiclopedia", 3281, 1793313, 13, 1),
        ("ffxiclopedia", 125762, 1793247, 5, 1),
        ("ffxiclopedia", 125762, 1793247, 6, 1),
        ("ffxiclopedia", 125762, 1793247, 7, 1),
        ("ffxiclopedia", 12475, 1787477, 5, 1),
        ("ffxiclopedia", 8462, 1794200, 2, 1),
    }
)
INVENTORY_SCHEMA_RED_IDS = frozenset(
    {
        "mission:A Moogle Kupo d'Etat:6:step-031:claim-01",
        "mission:A Shantotto Ascension:10:step-021:claim-01",
        "mission:Campaign:30:step-002:claim-01",
        *(f"mission:Chains of Promathia:{native_id}:step-073:claim-01" for native_id in range(14, 23)),
        "mission:Chains of Promathia:24:step-023:claim-04",
        "mission:Wings of the Goddess:41:step-001:claim-01",
        "quest:adoulin:60:step-006:claim-02",
        "quest:adoulin:73:step-004:claim-03",
        "quest:bastok:21:step-009:claim-01",
        "quest:bastok:39:step-002:claim-02",
        "quest:bastok:71:step-009:claim-01",
        "quest:bastok:78:step-005:claim-03",
        "quest:crystal_war:29:step-002:claim-01",
        "quest:outlands:14:step-009:claim-01",
        "quest:sandoria:104:step-009:claim-01",
        "quest:sandoria:20:step-010:claim-01",
        "quest:windurst:89:step-009:claim-01",
    }
)
COUNTED_TARGET_RED_IDS = frozenset(
    {
        "mission:Assault:37:step-015:claim-01",
        "mission:Campaign:53:step-016:claim-01",
        "mission:Chains of Promathia:62:step-080:claim-01",
        "mission:Chains of Promathia:63:step-016:claim-02",
        "quest:bastok:40:step-001:claim-01",
        "quest:crystal_war:52:step-016:claim-01",
        "quest:jeuno:161:step-004:claim-03",
        "quest:jeuno:161:step-006:claim-01",
        "quest:jeuno:172:step-055:claim-02",
        "quest:sandoria:75:step-005:claim-01",
        "quest:sandoria:76:step-005:claim-01",
        "quest:windurst:32:step-003:claim-01",
    }
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
    "mission:Assault:52:step-132:claim-01",
    "mission:Bastok:11:step-012:claim-01",
    "mission:Bastok:17:step-012:claim-02",
    "mission:Bastok:17:step-015:claim-01",
    "mission:Campaign:4:step-013:claim-02",
    "mission:Campaign:29:step-010:claim-01",
    "mission:Campaign:30:step-007:claim-02",
    "mission:Campaign:40:step-013:claim-01",
    "mission:Campaign:44:step-001:claim-02",
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
    "mission:San d'Oria:21:step-036:claim-01",
    "mission:San d'Oria:3:step-003:claim-01",
    "mission:Seekers of Adoulin:33:step-003:claim-01",
    "mission:Windurst:17:step-018:claim-01",
    "mission:Treasures of Aht Urhgan:42:step-002:claim-01",
    "mission:Windurst:5:step-025:claim-01",
    "quest:abyssea:128:step-019:claim-01",
    "quest:abyssea:31:step-013:claim-01",
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
    "quest:windurst:75:step-072:claim-01",
    "quest:windurst:8:step-008:claim-01",
    "quest:windurst:17:step-028:claim-01",
    "quest:windurst:46:step-002:claim-01",
    "quest:windurst:50:step-006:claim-01",
    "quest:windurst:71:step-066:claim-01",
}

CONTRAST_ACTION_IDS = {
    "mission:Chains of Promathia:61:step-011:claim-03",
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
    "mission:Rhapsodies of Vana'diel:73",
    "mission:Rhapsodies of Vana'diel:73:step-004:claim-01",
    "object:v1:122:17277256",
)

SUPPLEMENTAL_PROVENANCE_PINS = {
    "mission:Bastok:3:step-003:claim-01": (
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


def _independent_entities_separated_by_or(
    instruction: str,
    entities: object,
) -> bool:
    positions: list[tuple[int, int]] = []
    for entity in dict.fromkeys(str(value) for value in entities if str(value).strip()):
        match = re.search(
            rf"(?<![A-Za-z0-9]){re.escape(entity)}(?![A-Za-z0-9])",
            instruction,
            re.IGNORECASE,
        )
        if match is not None:
            positions.append((match.start(), match.end()))
    positions.sort()
    return any(
        re.fullmatch(
            r"\s*(?:,\s*)?or\s*",
            instruction[left[1] : right[0]],
            re.IGNORECASE,
        )
        is not None
        for left, right in zip(positions, positions[1:])
    )


def _independent_internal_alternative_is_method_or_outcome(
    action: dict[str, object],
    instruction: str,
    internal_either: re.Match[str],
) -> bool:
    """Independently distinguish one head goal from later method/result choices."""

    before = instruction[: internal_either.start()]
    after = re.sub(
        r"^\s*either\b",
        "",
        instruction[internal_either.start() :],
        count=1,
        flags=re.IGNORECASE,
    )
    target = str(action["target"] or "").strip()
    target_before = False
    if target:
        occurrence = re.search(
            rf"(?<![A-Za-z0-9]){re.escape(target)}(?![A-Za-z0-9])",
            instruction,
            re.IGNORECASE,
        )
        target_before = occurrence is not None and occurrence.end() <= internal_either.start()

    if (
        action["action"] == "examine"
        and target_before
        and re.search(r"\b(?:reward|result|cutscene)\b[^.;]{0,160}\(?\s*$", before, re.IGNORECASE)
    ):
        return True
    if action["action"] != "travel" or re.match(
        r"^\s*(?:enter|exit|zone\s+into|go\s+to|head\s+to|travel\s+to|"
        r"make\s+your\s+way\s+to)\b",
        instruction,
        re.IGNORECASE,
    ) is None:
        return False
    before_method = re.search(
        r"\b(?:by|via|through|from|in|at)\s*$",
        before,
        re.IGNORECASE,
    )
    after_method = re.match(
        r"\s*(?:by|via|through|from|in|at)\b",
        after,
        re.IGNORECASE,
    )
    if before_method is None and after_method is None:
        return False
    head = before[: before_method.start()] if before_method is not None else before
    if not target_before and re.search(
        r"\b(?:any\s+)?one\s+of\b",
        head,
        re.IGNORECASE,
    ):
        return False
    return target_before or re.search(r"[A-Za-z0-9?]", head) is not None


def _independent_semantic_false_families(action: dict[str, object]) -> tuple[str, ...]:
    instruction = str(action["instruction"])
    match = SEMANTIC_ACTION_MATCH.search(instruction)
    if match is None:
        raise AssertionError(
            f"Material progression row has no independently selected verb: "
            f"{action['action_id']!r}"
        )
    verb = match.group("verb").casefold()
    prefix = instruction[: match.start()]
    suffix = instruction[match.end() :]
    target = str(action["target"])
    found: list[str] = []

    if verb == "give" and re.search(r"\bwill\s*$", prefix, re.IGNORECASE):
        found.append("will_give")
    if verb == "give" and re.match(r"\s+up\b", suffix, re.IGNORECASE):
        found.append("give_up")
    if verb == "fight" and (
        re.search(rf"\b(?:{SEMANTIC_DETERMINERS})\s*$", prefix, re.IGNORECASE)
        or re.match(
            rf"\s+(?:{SEMANTIC_COPULAR_FIGHT_FOLLOWERS})\b",
            suffix,
            re.IGNORECASE,
        )
    ):
        found.append("noun_fight")
    if verb == "use" and re.search(
        r"\b(?:without|through|for|of|during|by|with|in)\s+(?:the\s+)?$",
        prefix,
        re.IGNORECASE,
    ):
        found.append("noun_use")
    if verb == "use" and re.search(
        r"\b(?:can|could|may|might)(?:\s+(?:also|then))?\s*$",
        prefix,
        re.IGNORECASE,
    ):
        found.append("modal_use")
    if verb == "use" and re.match(
        r"\s+this\s+(?:time|opportunity)\b",
        suffix,
        re.IGNORECASE,
    ):
        found.append("use_this_time")
    if verb == "light" and (
        re.search(
            rf"\b(?:{SEMANTIC_LIGHT_PREDECESSORS})\s*$",
            prefix,
            re.IGNORECASE,
        )
        or re.match(
            rf"(?:\s+|-)(?:{SEMANTIC_LIGHT_FOLLOWERS})\b",
            suffix,
            re.IGNORECASE,
        )
    ):
        found.append("lexical_light")
    if (
        verb == "open"
        and re.search(
            r"\b(?:an?|the|large|wide|big|main|another|that|next)\s*$",
            prefix,
            re.IGNORECASE,
        )
        and re.match(
            r"\s+(?:area|space|room|field|world|section)\b",
            suffix,
            re.IGNORECASE,
        )
    ):
        found.append("adjective_open")
    if verb == "open" and re.search(r"\bwill\s*$", prefix, re.IGNORECASE):
        found.append("will_open")
    if verb == "board" and (
        instruction.strip().casefold() == "board"
        or re.search(r"\bon\s*$", prefix, re.IGNORECASE)
        or re.search(r"\b(?:runic|tonberry)\s*$", prefix, re.IGNORECASE)
        or re.match(r"(?:'s|s')\b", suffix, re.IGNORECASE)
        or re.match(r"\s+for\s+the\s+next\b", suffix, re.IGNORECASE)
    ):
        found.append("noun_board")
    if verb == "protect" and (
        re.match(r"\s+(?:I|II|III|IV|V|VI)\b", suffix, re.IGNORECASE)
        or re.match(
            r"\s*[,/]\s*(?:and\s+|or\s+)?Shell\b",
            suffix,
            re.IGNORECASE,
        )
        or re.search(
            r"\b(?:cast(?:s|ing)?|spells?\s+such\s+as|white\s+magic:|"
            r"defensive:|buffed\s+with|gain(?:s|ed)?\s+(?:an\s+additional\s+)?)\s*$",
            prefix,
            re.IGNORECASE,
        )
    ):
        found.append("spell_protect")
    if verb == "return to" and (
        re.search(r"\b(?:he|she|it|they)\s+will\s*$", prefix, re.IGNORECASE)
        or re.search(r"\b(?:their|his|her|its)\s*$", prefix, re.IGNORECASE)
    ):
        found.append("external_return")
    if verb == "receive" and SEMANTIC_GENERIC_RECEIVE_TARGET.search(target):
        found.append("generic_receive")
    if verb == "check" and re.match(
        r"\s+(?:normally|as\s+(?:DC|Easy|Decent|Incredibly|Impossible|EP))\b",
        suffix,
        re.IGNORECASE,
    ):
        found.append("check_status")
    if verb == "select" and re.match(r"\s+pool\b", suffix, re.IGNORECASE):
        found.append("select_pool")
    if re.search(
        r"\b(?:and|to|or|then|with|for)\s*$",
        target,
        re.IGNORECASE,
    ) or re.match(
        r"\s*(?:is|are|was|were|will|can|may|should|has|have)\b",
        target,
        re.IGNORECASE,
    ):
        found.append("malformed_target")
    for family, pattern in SEMANTIC_BRANCH_GUIDANCE_PATTERNS.items():
        if pattern.search(instruction):
            found.append(family)
    internal_either = re.search(r"\beither\b.{0,400}\bor\b", instruction, re.IGNORECASE)
    leading_either = re.match(
        r"^\s*(?:[\[(]?\s*)?either\b",
        instruction,
        re.IGNORECASE,
    )
    canonical_acquisition = bool(
        action["action"] == "obtain"
        and target
        and re.match(
            r"^\s*(?:once\b[^,]{0,120},\s*)?(?:obtain|collect|purchase)\b",
            instruction,
            re.IGNORECASE,
        )
    )
    if (
        internal_either
        and not leading_either
        and not canonical_acquisition
        and not _independent_internal_alternative_is_method_or_outcome(
            action,
            instruction,
            internal_either,
        )
    ):
        found.append("internal_alternative_guidance")
    if (
        action["action"] == "talk"
        and not re.search(r"\beither\b", instruction, re.IGNORECASE)
        and re.match(r"^\s*(?:talk|speak)\b", instruction, re.IGNORECASE)
        and len(tuple(action["npcs"])) >= 2
        and _independent_entities_separated_by_or(instruction, action["npcs"])
    ):
        found.append("entity_alternative_guidance")
    return tuple(found)


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

    def test_pinned_direct_imperative_review_contract(self) -> None:
        coverage = _json(DATA_ROOT / "coverage.json")
        parsed_pages = _pinned_parsed_pages(coverage)
        reviewed = (
            DIRECT_IMPERATIVE_ADMIT_IDENTITIES
            | DIRECT_IMPERATIVE_REJECT_IDENTITIES
            | DIRECT_IMPERATIVE_SUPPLEMENTAL_ADMIT_IDENTITIES
            | DIRECT_IMPERATIVE_SUPPLEMENTAL_REJECT_IDENTITIES
        )
        self.assertEqual(len(DIRECT_IMPERATIVE_ADMIT_IDENTITIES), 40)
        self.assertEqual(len(DIRECT_IMPERATIVE_REJECT_IDENTITIES), 40)
        self.assertEqual(len(DIRECT_IMPERATIVE_SUPPLEMENTAL_ADMIT_IDENTITIES), 40)
        self.assertEqual(len(DIRECT_IMPERATIVE_SUPPLEMENTAL_REJECT_IDENTITIES), 16)
        self.assertFalse(
            DIRECT_IMPERATIVE_ADMIT_IDENTITIES
            & DIRECT_IMPERATIVE_REJECT_IDENTITIES
        )
        self.assertEqual(
            sum(
                len(rows)
                for rows in (
                    DIRECT_IMPERATIVE_ADMIT_IDENTITIES,
                    DIRECT_IMPERATIVE_REJECT_IDENTITIES,
                    DIRECT_IMPERATIVE_SUPPLEMENTAL_ADMIT_IDENTITIES,
                    DIRECT_IMPERATIVE_SUPPLEMENTAL_REJECT_IDENTITIES,
                )
            ),
            len(reviewed),
        )
        self.assertEqual(len(reviewed), 136)

        observed: dict[tuple[str, int, int, int, int], object] = {}
        current_nonmaterial: set[tuple[str, int, int, int, int]] = set()
        missing_action_spans: list[tuple[str, int, int, int]] = []
        for (site, page_id), parsed_page in parsed_pages.items():
            for source_step in parsed_page.steps:
                if DIRECT_IMPERATIVE_START.match(source_step.spoken_text) is None:
                    continue
                if not source_step.action_spans:
                    missing_action_spans.append(
                        (site, page_id, parsed_page.revision_id, source_step.order)
                    )
                    continue
                first = min(
                    source_step.action_spans,
                    key=lambda span: (span.text_start, span.order),
                )
                identity = (
                    site,
                    page_id,
                    parsed_page.revision_id,
                    source_step.order,
                    first.order,
                )
                if identity in reviewed:
                    observed[identity] = first
                if not first.material:
                    current_nonmaterial.add(identity)

        self.assertEqual(missing_action_spans, [])
        self.assertEqual(set(observed), reviewed)
        self.assertEqual(
            {identity for identity, span in observed.items() if span.material},
            (
                DIRECT_IMPERATIVE_ADMIT_IDENTITIES
                | DIRECT_IMPERATIVE_SUPPLEMENTAL_ADMIT_IDENTITIES
            ),
        )
        self.assertEqual(
            {identity for identity, span in observed.items() if not span.material},
            (
                DIRECT_IMPERATIVE_REJECT_IDENTITIES
                | DIRECT_IMPERATIVE_SUPPLEMENTAL_REJECT_IDENTITIES
            ),
        )
        self.assertEqual(
            current_nonmaterial,
            (
                DIRECT_IMPERATIVE_REJECT_IDENTITIES
                | DIRECT_IMPERATIVE_SUPPLEMENTAL_REJECT_IDENTITIES
            ),
        )

        acquisition_composites = {
            ("ffxiclopedia", 9925, 927517, 2, 1): ("Sand Bat Fang", "Sand Bats"),
            ("ffxiclopedia", 3300, 1720865, 2, 1): ("Orcish Axe", "Orcish Fodder"),
        }
        for identity, (item, enemy) in acquisition_composites.items():
            span = observed[identity]
            self.assertEqual(span.action, "obtain", identity)
            self.assertEqual(span.relationship, "obtain-item", identity)
            self.assertEqual(span.target, item, identity)
            self.assertEqual(span.target_kind, "item", identity)
            self.assertEqual(span.item_mentions, (item,), identity)
            self.assertIn(enemy, span.enemy_mentions, identity)
            self.assertEqual(span.result_relation, "obtain-from", identity)
            self.assertEqual(
                (span.required_count, span.count_mode, span.count_explicit),
                (1, "single", False),
                identity,
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

        obligation_rows: dict[tuple[str, int, int, int, int], tuple[object, tuple[str, ...]]] = {}
        nonmaterial_obligation_cues: set[tuple[str, int, int, int, int]] = set()
        obligation_family_counts: Counter[str] = Counter()
        for (site, page_id), parsed_page in pinned_parsed_pages.items():
            for source_step in parsed_page.steps:
                for source_span in source_step.action_spans:
                    verb = str(source_span.verb or "").strip()
                    if not verb:
                        continue
                    match = re.search(
                        rf"(?<![A-Za-z0-9]){re.escape(verb)}(?![A-Za-z0-9])",
                        source_span.supporting_clause,
                        re.IGNORECASE,
                    )
                    if match is None:
                        continue
                    prefix = source_span.supporting_clause[: match.start()]
                    families = tuple(
                        family
                        for family, pattern in OBLIGATION_CUE_PATTERNS.items()
                        if pattern.search(prefix)
                    )
                    identity = (
                        site,
                        page_id,
                        parsed_page.revision_id,
                        source_step.order,
                        source_span.order,
                    )
                    if identity in OBLIGATION_BASELINE_IDENTITIES:
                        self.assertTrue(families, identity)
                        self.assertNotIn(identity, obligation_rows)
                        obligation_rows[identity] = (source_span, families)
                        obligation_family_counts.update(families)
                    if families and not source_span.material:
                        nonmaterial_obligation_cues.add(identity)

        self.assertEqual(set(obligation_rows), OBLIGATION_BASELINE_IDENTITIES)
        self.assertEqual(len(OBLIGATION_BASELINE_IDENTITIES), 59)
        self.assertEqual(len(OBLIGATION_REJECT_IDENTITIES), 12)
        self.assertEqual(
            {
                identity
                for identity, (source_span, _families) in obligation_rows.items()
                if source_span.material
            },
            OBLIGATION_BASELINE_IDENTITIES - OBLIGATION_REJECT_IDENTITIES,
        )
        self.assertEqual(
            {
                identity
                for identity, (source_span, _families) in obligation_rows.items()
                if not source_span.material
            },
            OBLIGATION_REJECT_IDENTITIES,
        )
        self.assertEqual(nonmaterial_obligation_cues, OBLIGATION_REJECT_IDENTITIES)
        self.assertEqual(
            obligation_family_counts,
            {
                "actor_directive": 13,
                "goal_is_to": 8,
                "passive_directive": 38,
                "passive_player_obligation": 8,
                "possessive_task": 3,
            },
        )

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
        self.assertEqual(len(reconcile_steps), 31124)
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
        self.assertEqual(len(typed_claim_ids), 22951)
        self.assertEqual(len(all_ledger_ids), 39728)
        context_ledger_ids = all_ledger_ids - typed_claim_ids
        self.assertEqual(len(context_ledger_ids), 16777)
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
        self.assertEqual(len(typed_material_ids), 12069)
        self.assertEqual(len(typed_nonmaterial_ids), 10882)
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
        ffxi_material_fallback_ids: set[str] = set()
        ffxi_material_fallback_objectives: set[str] = set()
        ffxi_material_fallback_steps: set[str] = set()
        ffxi_material_fallback_actions: Counter[str] = Counter()
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
            bg_span = source_spans.get("bg")
            ffxi_span = source_spans.get("ffxiclopedia")
            material_bg = bg_span if bg_span is not None and bg_span.material else None
            material_ffxi = (
                ffxi_span if ffxi_span is not None and ffxi_span.material else None
            )
            semantic_owner = material_bg or material_ffxi
            if row["material"]:
                self.assertIsNotNone(semantic_owner, row["action_id"])
            if (
                row["material"]
                and material_ffxi is not None
                and semantic_owner is material_ffxi
                and bg_span is not None
                and not bg_span.material
            ):
                self.assertEqual(set(source_spans), {"bg", "ffxiclopedia"}, row["action_id"])
                ffxi_material_fallback_ids.add(row["action_id"])
                ffxi_material_fallback_objectives.add(row["native_key"])
                ffxi_material_fallback_steps.add(row["action_id"].rsplit(":claim-", 1)[0])
                ffxi_material_fallback_actions[row["action"]] += 1
        self.assertEqual(len(ffxi_material_fallback_ids), 467)
        self.assertEqual(len(ffxi_material_fallback_objectives), 350)
        self.assertEqual(len(ffxi_material_fallback_steps), 445)
        self.assertEqual(
            ffxi_material_fallback_actions,
            {
                "examine": 59,
                "fight": 53,
                "obtain": 62,
                "select": 5,
                "talk": 124,
                "trade": 49,
                "travel": 83,
                "use": 23,
                "wait": 9,
            },
        )
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
        self.assertEqual(len(candidate_ids), 1506)

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
                    material_bg = (
                        bg_span if bg_span is not None and bg_span.material else None
                    )
                    material_ffxi = (
                        ffxi_span if ffxi_span is not None and ffxi_span.material else None
                    )
                    source_authority = "bg" if material_bg is not None else "ffxiclopedia"
                    semantic_owner = material_bg or material_ffxi
                    self.assertIsNotNone(semantic_owner, action["action_id"])
                    self.assertFalse(
                        _independent_direct_prohibition(semantic_owner),
                        action["action_id"],
                    )

                    semantic_fallback = material_ffxi if source_authority == "bg" else None
                    if semantic_fallback is not None and not (
                        semantic_owner.action == semantic_fallback.action
                        and semantic_owner.relationship == semantic_fallback.relationship
                        and semantic_owner.target_kind == semantic_fallback.target_kind
                        and _independent_target_key(semantic_owner.target)
                        == _independent_target_key(semantic_fallback.target)
                    ):
                        semantic_fallback = None
                    auxiliary_bg = material_bg
                    auxiliary_ffxi = (
                        semantic_fallback if source_authority == "bg" else material_ffxi
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

                    owned_values = {
                        "action": semantic_owner.action,
                        "relationship": semantic_owner.relationship,
                        "target": semantic_owner.target,
                        "target_kind": semantic_owner.target_kind,
                        "items": items_without_key_items(semantic_owner),
                        "key_items": semantic_owner.key_item_mentions,
                        "result_items": semantic_owner.result_items,
                        "result_relation": semantic_owner.result_relation,
                        "instruction": semantic_owner.supporting_clause,
                    }
                    source_values = {
                        "npcs": (
                            auxiliary_bg.npc_mentions if auxiliary_bg else (),
                            auxiliary_ffxi.npc_mentions if auxiliary_ffxi else (),
                        ),
                        "objects": (
                            auxiliary_bg.object_mentions if auxiliary_bg else (),
                            auxiliary_ffxi.object_mentions if auxiliary_ffxi else (),
                        ),
                        "enemies": (
                            auxiliary_bg.enemy_mentions if auxiliary_bg else (),
                            auxiliary_ffxi.enemy_mentions if auxiliary_ffxi else (),
                        ),
                        "transports": (
                            auxiliary_bg.transport_mentions if auxiliary_bg else (),
                            auxiliary_ffxi.transport_mentions if auxiliary_ffxi else (),
                        ),
                        "zones": (
                            auxiliary_bg.zone_mentions if auxiliary_bg else (),
                            auxiliary_ffxi.zone_mentions if auxiliary_ffxi else (),
                        ),
                        "destination_zone_name": (
                            auxiliary_bg.destination_zone_name if auxiliary_bg else "",
                            auxiliary_ffxi.destination_zone_name if auxiliary_ffxi else "",
                        ),
                        "grid_coordinates": (
                            auxiliary_bg.grid_coordinates if auxiliary_bg else (),
                            auxiliary_ffxi.grid_coordinates if auxiliary_ffxi else (),
                        ),
                    }
                    expected_field_sources: dict[str, str] = {}
                    for field, expected_value in owned_values.items():
                        if isinstance(expected_value, tuple):
                            expected_value = list(expected_value)
                        self.assertEqual(action[field], expected_value, action["action_id"])
                        expected_field_sources[field] = (
                            source_authority
                            if expected_value not in ("", [], {}, None)
                            else ""
                        )
                    for field, (bg_value, ffxi_value) in source_values.items():
                        expected_value, expected_source = authoritative_value(
                            bg_value, ffxi_value
                        )
                        if isinstance(expected_value, tuple):
                            expected_value = list(expected_value)
                        self.assertEqual(action[field], expected_value, action["action_id"])
                        expected_field_sources[field] = expected_source

                    count_bg = material_bg
                    count_ffxi = (
                        semantic_fallback if source_authority == "bg" else material_ffxi
                    )
                    if count_bg is not None and count_bg.count_explicit:
                        count_span, count_source = count_bg, "bg"
                    elif count_ffxi is not None and count_ffxi.count_explicit:
                        count_span, count_source = count_ffxi, "ffxiclopedia"
                    elif count_bg is not None:
                        count_span, count_source = count_bg, "bg"
                    else:
                        count_span, count_source = count_ffxi, "ffxiclopedia"
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
                        source_authority,
                        action["action_id"],
                    )
                    self.assertEqual(
                        action["field_sources"],
                        expected_field_sources,
                        action["action_id"],
                    )
                    if action["action_id"] in ffxi_material_fallback_ids:
                        self.assertEqual(source_authority, "ffxiclopedia", action["action_id"])
                        self.assertFalse(
                            any(
                                field_source == "bg"
                                for field_source in action["field_sources"].values()
                            ),
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
                        if action["action"] == "fight":
                            self.assertEqual(action["relationship"], "defeat-enemy")
                            self.assertEqual(action["count_mode"], "credited-defeat")
                            counted_semantics[("defeat-enemy", "credited-defeat")] += 1
                        elif action["action"] == "obtain":
                            self.assertEqual(action["relationship"], "obtain-item")
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
        self.assertEqual(len(PROHIBITED_ACTION_IDS), 108)
        self.assertEqual(len(CONTRAST_ACTION_IDS), 1)
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

    def test_progression_actions_pass_independent_semantic_and_speech_audit(self) -> None:
        paths = tuple(sorted(MODULE_ROOT.glob("mission_quest_progression_*.lua")))
        modules = _lua_values(paths)
        actions = {
            action["action_id"]: action
            for module in modules.values()
            for objective in module["objectives"].values()
            for action in objective["progression_actions"]
        }
        family_actions: dict[str, list[dict[str, object]]] = {}
        suspect_actions: list[dict[str, object]] = []
        strict_suspect_actions: list[dict[str, object]] = []
        for action in actions.values():
            families = _independent_semantic_false_families(action)
            for family in families:
                family_actions.setdefault(family, []).append(action)
            if SEMANTIC_FALSE_UNION_FAMILIES.intersection(families):
                suspect_actions.append(action)
            if SEMANTIC_STRICT_FALSE_UNION_FAMILIES.intersection(families):
                strict_suspect_actions.append(action)

        def summarize(rows: list[dict[str, object]]) -> dict[str, object]:
            return {
                "actions": len(rows),
                "objectives": len(
                    {
                        str(action["action_id"]).split(":step-", 1)[0]
                        for action in rows
                    }
                ),
                "steps": len({str(action["step_id"]) for action in rows}),
                "by_action": dict(
                    sorted(Counter(str(action["action"]) for action in rows).items())
                ),
            }

        semantic_summary = summarize(suspect_actions)
        self.assertEqual(
            semantic_summary,
            {"actions": 0, "objectives": 0, "steps": 0, "by_action": {}},
            (
                "Generated reducer actions still contain independently detected descriptive "
                "or malformed prose. Frozen RED baseline: "
                f"{SEMANTIC_FALSE_RED_BASELINE!r}. Current family counts: "
                f"{ {family: len(rows) for family, rows in sorted(family_actions.items())}!r}"
            ),
        )
        self.assertEqual(
            summarize(strict_suspect_actions),
            {"actions": 0, "objectives": 0, "steps": 0, "by_action": {}},
            (
                "Generated reducer actions still contain independently detected modal, "
                "conditional, optional, alternative, repeat-only, or advice prose. Frozen "
                "RED baseline: "
                f"{SEMANTIC_FALSE_RED_BASELINE!r}. Current family counts: "
                f"{ {family: len(rows) for family, rows in sorted(family_actions.items())}!r}"
            ),
        )

        duplicate_action_ids: list[str] = []
        for action_id, action in actions.items():
            target = action["target"].strip()
            if not target:
                continue
            duplicate = re.compile(
                rf"(?i)(?<![A-Za-z0-9]){re.escape(target)}(?:s|es)?\s+"
                rf"{re.escape(target)}(?:s|es)?(?![A-Za-z0-9])"
            )
            if duplicate.search(action["instruction"]):
                duplicate_action_ids.append(action_id)
        self.assertEqual(
            set(duplicate_action_ids),
            RENDERER_SPEECH_DUPLICATE_FOLLOWUP_IDS,
            "Only the exact frozen renderer-speech follow-up rows may remain duplicated.",
        )

        self.assertNotIn("quest:abyssea:32:step-002:claim-01", actions)
        subsequent = [
            action
            for action in actions.values()
            if action["step_id"] == "quest:abyssea:32:step-012"
        ]
        self.assertEqual(
            [
                (
                    action["action_id"],
                    action["action"],
                    action["relationship"],
                    action["target"],
                )
                for action in subsequent
            ],
            [
                (
                    "quest:abyssea:32:step-012:claim-02",
                    "obtain",
                    "obtain-item",
                    "Viscous Spittle",
                )
            ],
        )

    def test_reviewed_ryoma_completion_retains_exact_pinned_source_steps(self) -> None:
        overrides = _json(DATA_ROOT / "reviewed-overrides.json")
        self.assertNotIn("quest:outlands:143:step-020", overrides["target_overrides"])
        override = overrides["target_overrides"]["quest:outlands:143:step-021"]
        self.assertEqual(
            (
                override["source_revisions"],
                override["reference"]["zone"],
                override["reference"]["name"],
            ),
            ({"bg": 748842, "ffxiclopedia": 1780114}, 252, "Ryoma"),
        )

        review = _json(DATA_ROOT / "target-review.json")
        step = next(
            row
            for row in review["steps"]
            if row["stable_step_id"] == "quest:outlands:143:step-021"
        )
        self.assertEqual(step["source_orders"], [11, 17])
        self.assertIn("speak with Ryoma", step["source_instructions"]["bg"])
        self.assertIn("speak with Ryoma", step["source_instructions"]["ffxiclopedia"])
        self.assertTrue(
            any(
                claim["action"] == "talk"
                and claim["target"] == "Ryoma"
                for claim in step["typed_claims"]
            )
        )

        progression_path = MODULE_ROOT / "mission_quest_progression_quest_outlands.lua"
        progression = _lua_values((progression_path,))[progression_path]
        ryoma_action = next(
            action
            for action in progression["objectives"]["quest:outlands:143"]["progression_actions"]
            if action["action_id"] == "quest:outlands:143:step-021:claim-02"
        )
        self.assertEqual(
            (
                ryoma_action["action"],
                ryoma_action["target"],
                ryoma_action["material"],
            ),
            ("talk", "Ryoma", True),
        )

    def test_counted_progression_actions_have_observable_typed_completion(self) -> None:
        paths = tuple(sorted(MODULE_ROOT.glob("mission_quest_progression_*.lua")))
        modules = _lua_values(paths)
        actions = {
            action["action_id"]: action
            for module in modules.values()
            for objective in module["objectives"].values()
            for action in objective["progression_actions"]
        }

        invalid_inventory = {
            action_id
            for action_id, action in actions.items()
            if action["count_mode"] == "inventory-gain"
            and (action["action"] != "obtain" or bool(action["key_items"]))
        }
        counted_without_target = {
            action_id
            for action_id, action in actions.items()
            if action["count_mode"] != "single" and not action["target_key"]
        }
        self.assertEqual(
            (invalid_inventory, counted_without_target),
            (set(), set()),
            (
                "Counted reducer actions must have one exact, typed, observable completion "
                "signal. Frozen d1fe063 REDs were exactly "
                f"inventory={sorted(INVENTORY_SCHEMA_RED_IDS)!r} and "
                f"targetless={sorted(COUNTED_TARGET_RED_IDS)!r}; current="
                f"{(sorted(invalid_inventory), sorted(counted_without_target))!r}"
            ),
        )

        for action_id, action in actions.items():
            if action["count_mode"] == "inventory-gain":
                self.assertEqual(action["action"], "obtain", action_id)
                self.assertEqual(action["relationship"], "obtain-item", action_id)
                self.assertEqual(action["target_kind"], "item", action_id)
                self.assertTrue(action["target"], action_id)
                self.assertTrue(action["target_key"], action_id)
                self.assertTrue(action["items"], action_id)
                self.assertFalse(action["key_items"], action_id)
            if action["count_mode"] == "credited-defeat":
                self.assertEqual(action["action"], "fight", action_id)
                self.assertEqual(action["relationship"], "defeat-enemy", action_id)
                self.assertEqual(action["target_kind"], "enemy", action_id)
                self.assertTrue(action["target"], action_id)
                self.assertTrue(action["target_key"], action_id)
                self.assertIn(action["target"], action["enemies"], action_id)

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

from __future__ import annotations

import difflib
import re
import unicodedata
from dataclasses import dataclass
from typing import Iterable

from .model import NativeObjective, ParsedObjective


@dataclass(frozen=True, slots=True)
class ObjectiveMatch:
    native_key: str
    site: str
    page_id: int
    revision_id: int
    canonical_title: str
    method: str


@dataclass(frozen=True, slots=True)
class MatchingReport:
    matches: tuple[ObjectiveMatch, ...]
    ambiguous_pages: dict[int, tuple[str, ...]]
    unmatched_pages: tuple[int, ...]
    unmatched_native_keys: tuple[str, ...]
    suggestions: dict[int, tuple[str, ...]]


def normalize_title(value: str) -> str:
    value = unicodedata.normalize("NFKD", str(value or "")).casefold()
    value = "".join(character for character in value if not unicodedata.combining(character))
    value = value.replace("&", "and")
    return re.sub(r"[^a-z0-9]+", "", value)


def _literal_title(value: str) -> str:
    value = unicodedata.normalize("NFKC", str(value or "")).casefold()
    return re.sub(r"\s+", " ", value).strip()


def _campaign_title_key(value: str) -> str:
    return re.sub(r"^vwopno(?=\d)", "vwop", normalize_title(value))


_CONTEXT_ALIASES = {
    "sandoria": "sandoria",
    "sandoriaquests": "sandoria",
    "sandoriamissions": "sandoria",
    "bastok": "bastok",
    "bastokquests": "bastok",
    "bastokmissions": "bastok",
    "windurst": "windurst",
    "windurstquests": "windurst",
    "windurstmissions": "windurst",
    "jeuno": "jeuno",
    "jeunoquests": "jeuno",
    "otherareas": "otherareas",
    "otherareasquests": "otherareas",
    "outlands": "outlands",
    "outlandsquests": "outlands",
    "ahturhgan": "ahturhgan",
    "ahturhganquests": "ahturhgan",
    "crystalwar": "crystalwar",
    "crystalwarquests": "crystalwar",
    "abyssea": "abyssea",
    "abysseaquests": "abyssea",
    "adoulin": "adoulin",
    "adoulinquests": "adoulin",
    "coalition": "coalition",
    "coalitionassignments": "coalition",
    "riseofthezilart": "riseofthezilart",
    "chainsofpromathia": "chainsofpromathia",
    "treasuresofahturhgan": "treasuresofahturhgan",
    "wingsofthegoddess": "wingsofthegoddess",
    "seekersofadoulin": "seekersofadoulin",
    "rhapsodiesofvanadiel": "rhapsodiesofvanadiel",
    "thevoraciousresurgence": "thevoraciousresurgence",
}


def _context_key(value: str) -> str:
    normalized = normalize_title(value)
    return _CONTEXT_ALIASES.get(normalized, normalized)


def _page_contexts(page: ParsedObjective) -> set[str]:
    values = [page.context_hint, *page.categories]
    mission_prefix = re.match(
        r"^(San d'Oria|Bastok|Windurst)\s+Mission\b",
        page.canonical_title,
        re.IGNORECASE,
    )
    if mission_prefix:
        values.append(mission_prefix.group(1))
    result: set[str] = set()
    for value in values:
        key = _context_key(value)
        if key:
            result.add(key)
    return result


def _native_clients(native: NativeObjective) -> set[str]:
    clients: set[str] = set()
    for detail in native.details:
        match = re.match(r"\s*clients?\s*:\s*(.+)", detail, re.IGNORECASE)
        if match:
            clients.add(normalize_title(match.group(1)))
    return clients


def _title_match_method(native: NativeObjective, page: ParsedObjective) -> str | None:
    native_title = normalize_title(native.title)
    if native_title == normalize_title(page.objective_name):
        return "exact-title"
    if native_title == normalize_title(page.canonical_title):
        return "exact-canonical"
    if native_title in {normalize_title(alias) for alias in page.aliases}:
        return "exact-alias"
    source_titles = {
        normalize_title(page.objective_name),
        normalize_title(page.canonical_title),
        *(normalize_title(alias) for alias in page.aliases),
    }
    if native_title + normalize_title(native.kind) in source_titles:
        return "exact-kind-suffix"
    if native_title + _context_key(native.context) in source_titles:
        return "exact-context-suffix"
    return None


def _literal_title_matches(native: NativeObjective, page: ParsedObjective) -> bool:
    title = _literal_title(native.title)
    return title in {
        _literal_title(page.objective_name),
        _literal_title(page.canonical_title),
        *(_literal_title(alias) for alias in page.aliases),
    }


def match_objective_pages(
    native_objectives: Iterable[NativeObjective],
    pages: Iterable[ParsedObjective],
) -> MatchingReport:
    natives = tuple(native_objectives)
    matches: list[ObjectiveMatch] = []
    ambiguous: dict[int, tuple[str, ...]] = {}
    unmatched_pages: list[int] = []
    suggestions: dict[int, tuple[str, ...]] = {}
    matched_native: set[str] = set()

    for page in pages:
        page_title_keys = {
            normalize_title(page.objective_name),
            normalize_title(page.canonical_title),
            *(normalize_title(alias) for alias in page.aliases),
        }
        category_keys = {normalize_title(category) for category in page.categories}
        if page.kind == "quest" and "crystalwarquests" in category_keys:
            campaign_page_keys: set[str] = set()
            for source_title in (page.objective_name, page.canonical_title, *page.aliases):
                campaign_page_keys.add(_campaign_title_key(source_title))
                without_kind_suffix = re.sub(r"\s*\(\s*quest\s*\)\s*$", "", source_title, flags=re.IGNORECASE)
                if without_kind_suffix != source_title:
                    campaign_page_keys.add(_campaign_title_key(without_kind_suffix))
            campaign_candidates = [
                native
                for native in natives
                if native.kind == "mission"
                and native.context == "Campaign"
                and _campaign_title_key(native.title) in campaign_page_keys
            ]
            if len(campaign_candidates) == 1:
                campaign = campaign_candidates[0]
                matches.append(
                    ObjectiveMatch(
                        native_key=campaign.key,
                        site=page.site,
                        page_id=page.page_id,
                        revision_id=page.revision_id,
                        canonical_title=page.canonical_title,
                        method="campaign-log-exact-title",
                    )
                )
                matched_native.add(campaign.key)

        candidates: list[tuple[NativeObjective, str]] = []
        for native in natives:
            if native.kind != page.kind:
                continue
            method = _title_match_method(native, page)
            if method is not None:
                candidates.append((native, method))

        if len(candidates) > 1:
            literal = [candidate for candidate in candidates if _literal_title_matches(candidate[0], page)]
            if literal:
                candidates = literal

        context_used = False
        page_contexts = _page_contexts(page)
        if len(candidates) > 1 and page_contexts:
            narrowed = [candidate for candidate in candidates if _context_key(candidate[0].context) in page_contexts]
            if narrowed:
                candidates = narrowed
                context_used = True

        if len(candidates) > 1 and page.start_entities:
            starts = {normalize_title(entity) for entity in page.start_entities}
            narrowed = [
                candidate
                for candidate in candidates
                if _native_clients(candidate[0]) and _native_clients(candidate[0]).intersection(starts)
            ]
            if narrowed:
                candidates = narrowed
                context_used = True

        if len(candidates) == 1:
            native, method = candidates[0]
            if context_used or _context_key(native.context) in page_contexts:
                method += "-context"
            matches.append(
                ObjectiveMatch(
                    native_key=native.key,
                    site=page.site,
                    page_id=page.page_id,
                    revision_id=page.revision_id,
                    canonical_title=page.canonical_title,
                    method=method,
                )
            )
            matched_native.add(native.key)
            continue

        if len(candidates) > 1:
            ambiguous[page.page_id] = tuple(sorted(candidate[0].key for candidate in candidates))
            continue

        unmatched_pages.append(page.page_id)
        page_title = normalize_title(page.objective_name or page.canonical_title)
        scored: list[tuple[float, str]] = []
        for native in natives:
            if native.kind != page.kind:
                continue
            score = difflib.SequenceMatcher(None, page_title, normalize_title(native.title)).ratio()
            if score >= 0.72:
                scored.append((score, native.key))
        if scored:
            best = max(score for score, _key in scored)
            suggestions[page.page_id] = tuple(
                key for score, key in sorted(scored, key=lambda value: (-value[0], value[1])) if score >= best - 0.04
            )

    return MatchingReport(
        matches=tuple(sorted(matches, key=lambda match: (match.native_key, match.site, match.page_id))),
        ambiguous_pages=ambiguous,
        unmatched_pages=tuple(sorted(unmatched_pages)),
        unmatched_native_keys=tuple(sorted(native.key for native in natives if native.key not in matched_native)),
        suggestions=suggestions,
    )

from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass, replace
from pathlib import Path

import mwparserfromhell
from mwparserfromhell.nodes import Template, Wikilink

from .mediawiki import PageRevision
from .model import ParsedObjective, SourceActionSpan, SourceStep
from .site_config import (
    SiteConfigError,
    SiteLinkPolicy,
    load_default_site_link_policies,
    validate_source_site_binding,
)


MAX_SPOKEN_STEP = 420

_ZONE_NAMES: tuple[str, ...] | None = None
_DEFAULT_SITE_POLICY = object()

_NYZUL_OBJECTIVE_TITLES = {
    "Nyzul Isle Investigation",
    "Nyzul Isle Uncharted Area Survey",
}
_NYZUL_PROGRESS_SECTIONS = {
    "differencesfromotherassaults",
    "rules",
    "entry",
    "lobby",
    "runeoftransfer",
    "runicdisc",
    "floorobjectives",
    "objectives",
    "floorrestrictions",
    "floorbonusesandrestrictions",
    "secondaryobjectives",
    "advancement",
    "completion",
}


class WikitextError(ValueError):
    """Raised when a source page cannot safely become objective guidance."""


@dataclass(frozen=True, slots=True)
class _EntityOccurrence:
    canonical: str
    display: str
    start: int
    end: int
    role: str = ""
    target_identity: bool = True
    source_link: bool = True


def _clean(value: object) -> str:
    return re.sub(r"\s+", " ", str(value or "").replace("\xa0", " ")).strip()


def _name_key(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", _clean(value).casefold())


def _unique(values: Iterable[str]) -> tuple[str, ...]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        value = _clean(value)
        key = value.casefold()
        if value and key not in seen:
            seen.add(key)
            result.append(value)
    return tuple(result)


def _strip_code(value: object) -> str:
    code = mwparserfromhell.parse(str(value or ""))
    return _clean(code.strip_code(normalize=True, collapse=True))


def _template_parameter(template: Template, *names: str) -> str:
    wanted = {_name_key(name) for name in names}
    for parameter in template.params:
        if _name_key(parameter.name) in wanted:
            return _strip_code(parameter.value)
    return ""


def _raw_template_parameter(template: Template, *names: str) -> str:
    wanted = {_name_key(name) for name in names}
    for parameter in template.params:
        if _name_key(parameter.name) in wanted:
            return str(parameter.value).strip()
    return ""


def _positional_parameters(template: Template) -> tuple[str, ...]:
    values: list[str] = []
    for parameter in template.params:
        if str(parameter.name).strip().isdigit():
            value = _strip_code(parameter.value)
            if value:
                values.append(value)
    return tuple(values)


def _template_location(template: Template) -> tuple[str, str, str, str]:
    positional = _positional_parameters(template)
    zone = _template_parameter(template, "area", "zone") or (positional[0] if positional else "")
    text = _template_parameter(template, "text", "label")
    map_label = _template_parameter(template, "map", "map number", "mapnumber")
    position = _template_parameter(template, "pos", "position", "grid")
    if not position:
        for value in positional[1:]:
            if re.search(r"(?<![A-Z0-9])[A-P]-\d{1,2}(?!\d)", value, re.IGNORECASE):
                position = value
                break
    return zone, text, map_label, position


def _template_entity_value(template: Template) -> str:
    positional = _positional_parameters(template)
    return (
        (positional[0] if positional else "")
        or _template_parameter(
            template,
            "item",
            "key item",
            "keyitem",
            "ki",
            "name",
            "text",
            "label",
        )
    )


def _readable_template_values(template: Template) -> tuple[str, ...]:
    ignored_names = {
        "align",
        "class",
        "color",
        "image",
        "link",
        "opaque",
        "size",
        "style",
        "width",
    }
    values: list[str] = []
    for parameter in template.params:
        if _name_key(parameter.name) in ignored_names:
            continue
        value = _strip_code(parameter.value)
        if not value or value.casefold() in {"yes", "no", "true", "false"}:
            continue
        if any(character.isalpha() for character in value):
            values.append(value)
    return _unique(values)


def _render_template(template: Template, warnings: list[str]) -> str:
    key = _name_key(template.name)
    if key in {"location", "locationtooltip"}:
        zone, text, map_label, position = _template_location(template)
        parts: list[str] = [text or zone]
        current = (text or zone).casefold()
        if map_label and map_label.casefold() not in current:
            parts.append(map_label)
        if position and position.casefold() not in " ".join(parts).casefold():
            parts.append(position)
        return " ".join(part for part in parts if part)
    if key in {"ki", "keyitem", "keyitems"}:
        return "key item " + _template_entity_value(template)
    if key in {"item", "itemicon", "itemlink"}:
        return _template_entity_value(template)
    if key in {"tooltip", "abbr"}:
        return _template_parameter(template, "text", "1") or " ".join(_readable_template_values(template))
    if key in {"color", "fontcolor"}:
        values = _positional_parameters(template)
        return (
            _template_parameter(template, "text", "label", "2")
            or (values[-1] if len(values) >= 2 else "")
        )
    if key in {"small", "nowrap", "nobr", "verification", "mob", "npc", "zone"}:
        return " ".join(_readable_template_values(template))
    if key == "!":
        return "|"
    if key in {"clear", "toc", "stub", "spoiler", "spoiler2"}:
        return ""

    readable = _readable_template_values(template)
    warnings.append(f"unknown-template:{_clean(template.name)}")
    return " ".join(readable)


def _render_link_display(value: object) -> str:
    code = mwparserfromhell.parse(str(value or ""))
    warnings: list[str] = []
    for template in reversed(list(code.filter_templates(recursive=True))):
        code.replace(template, _render_template(template, warnings))
    return _clean(code.strip_code(normalize=True, collapse=True))


def _normalized_wikilink_page_identity(
    value: object,
    site_policy: SiteLinkPolicy | None,
) -> str:
    target = _clean(str(value or "").replace("_", " "))
    if target.startswith(":"):
        target = _clean(target[1:])
    target = _clean(target.split("#", 1)[0])
    if not target:
        return ""
    if ":" in target:
        if site_policy is None:
            return ""
        prefix = _clean(target.split(":", 1)[0])
        if site_policy.classifies_prefix(prefix):
            return ""
    return target


def _wikilink_identity_details(
    link: Wikilink,
    site_policy: SiteLinkPolicy | None,
) -> tuple[str, str, bool]:
    raw_target = _clean(str(link.title or "").replace("_", " "))
    escaped_inline = raw_target.startswith(":")
    visible_target = _clean(raw_target[1:]) if escaped_inline else raw_target
    target = _normalized_wikilink_page_identity(raw_target, site_policy)
    display = _render_link_display(link.text) if link.text is not None else visible_target
    display = display or visible_target or target
    if not target:
        prefix = (
            _clean(visible_target.split(":", 1)[0]).casefold()
            if ":" in visible_target
            else ""
        )
        if site_policy is None:
            suppressed_metadata = not escaped_inline and prefix in {
                "category",
                "file",
                "image",
            }
        else:
            suppressed_metadata = not escaped_inline and (
                site_policy.namespace_id(prefix) in {6, 14}
                or site_policy.is_language_interwiki(prefix)
            )
        return "", ("" if suppressed_metadata else display), False
    fragment_identity_agrees = (
        "#" not in visible_target
        or _clean(display).casefold() == target.casefold()
    )
    return target, display, fragment_identity_agrees


def _wikilink_identity(
    link: Wikilink,
    site_policy: SiteLinkPolicy | None,
) -> tuple[str, str]:
    target, display, _target_identity = _wikilink_identity_details(link, site_policy)
    return target, display


def _template_entity_role(template: Template) -> str:
    key = _name_key(template.name)
    if key in {"ki", "keyitem", "keyitems"}:
        return "key-item"
    if key in {"item", "itemicon", "itemlink"}:
        return "item"
    return ""


def _set_link_role(roles: dict[int, str], link: Wikilink, role: str) -> None:
    if not role:
        return
    previous = roles.get(id(link), "")
    if not previous or role == "key-item":
        roles[id(link)] = role


def _structural_entity_roles(
    code: object,
    site_policy: SiteLinkPolicy | None,
) -> tuple[dict[int, str], dict[int, tuple[str, str, str]]]:
    roles: dict[int, str] = {}
    template_entities: dict[int, tuple[str, str, str]] = {}
    for template in code.filter_templates(recursive=True):
        role = _template_entity_role(template)
        if not role:
            continue
        contained_links: list[Wikilink] = []
        for parameter in template.params:
            for link in parameter.value.filter_wikilinks(recursive=True):
                contained_links.append(link)
                _set_link_role(roles, link, role)
        entity_name = _template_entity_value(template)
        if entity_name and not contained_links:
            template_entities[id(template)] = (entity_name, entity_name, role)

    def mark_adjacent(wikicode: object) -> None:
        pending: tuple[Template, str, str] | None = None
        for node in wikicode.nodes:
            if isinstance(node, Template):
                role = _template_entity_role(node)
                has_link = any(
                    parameter.value.filter_wikilinks(recursive=True)
                    for parameter in node.params
                )
                entity_name = _template_entity_value(node) if role else ""
                pending = (node, role, entity_name) if role and not has_link else None
                for parameter in node.params:
                    mark_adjacent(parameter.value)
                continue
            if not str(node).strip():
                continue
            if isinstance(node, Wikilink) and pending is not None:
                template, role, expected_name = pending
                canonical, display = _wikilink_identity(node, site_policy)
                if not expected_name or _name_key(expected_name) in {
                    _name_key(canonical),
                    _name_key(display),
                }:
                    _set_link_role(roles, node, role)
                    template_entities.pop(id(template), None)
            pending = None

    mark_adjacent(code)
    return roles, template_entities


def _render_fragment(
    fragment: str,
    site_policy: SiteLinkPolicy | None = None,
) -> tuple[
    str,
    tuple[str, ...],
    tuple[_EntityOccurrence, ...],
    tuple[str, ...],
    tuple[str, ...],
    tuple[str, ...],
]:
    code = mwparserfromhell.parse(fragment)
    warnings: list[str] = []
    structural_roles, template_entities = _structural_entity_roles(code, site_policy)
    entities: list[tuple[str, str, str, bool, bool]] = []
    for link in list(code.filter_wikilinks(recursive=True)):
        canonical, display, target_identity = _wikilink_identity_details(link, site_policy)
        if display:
            entity_index = len(entities)
            entities.append(
                (
                    canonical,
                    display,
                    structural_roles.get(id(link), ""),
                    target_identity,
                    True,
                )
            )
            code.replace(link, f"\ue000{entity_index}\ue001{display}\ue002")
        else:
            code.replace(link, "")

    locations: list[str] = []
    map_labels: list[str] = []
    for template in reversed(list(code.filter_templates(recursive=True))):
        key = _name_key(template.name)
        if key in {"location", "locationtooltip"}:
            zone, _text, map_label, _position = _template_location(template)
            if zone:
                locations.append(zone)
            if map_label:
                map_labels.append(map_label)
        replacement = _render_template(template, warnings)
        template_entity = template_entities.get(id(template))
        if template_entity is not None:
            canonical, display, role = template_entity
            display_start = replacement.find(display)
            if display_start >= 0:
                entity_index = len(entities)
                entities.append((canonical, display, role, False, False))
                display_end = display_start + len(display)
                replacement = (
                    replacement[:display_start]
                    + f"\ue000{entity_index}\ue001{display}\ue002"
                    + replacement[display_end:]
                )
        code.replace(template, replacement)

    rendered = _clean(code.strip_code(normalize=True, collapse=True))
    rendered = re.sub(r"(?<=[A-Za-z0-9])(\?{3})", r" \1", rendered)
    rendered = re.sub(r"(\?{3})(?=[A-Za-z0-9])", r"\1 ", rendered)
    rendered = re.sub(r"(\?{3})(?=\ue000\d+\ue001[A-Za-z0-9])", r"\1 ", rendered)
    rendered = re.sub(r"\s+([,.;:!?])", r"\1", rendered)
    plain_parts: list[str] = []
    entity_occurrences: list[_EntityOccurrence] = []
    cursor = 0
    plain_length = 0
    for marker in re.finditer(r"\ue000(\d+)\ue001(.*?)\ue002", rendered):
        prefix = rendered[cursor : marker.start()]
        plain_parts.append(prefix)
        plain_length += len(prefix)
        entity_index = int(marker.group(1))
        display = marker.group(2)
        canonical, _original_display, role, target_identity, source_link = entities[entity_index]
        plain_parts.append(display)
        entity_occurrences.append(
            _EntityOccurrence(
                canonical=canonical,
                display=display,
                start=plain_length,
                end=plain_length + len(display),
                role=role,
                target_identity=target_identity,
                source_link=source_link,
            )
        )
        plain_length += len(display)
        cursor = marker.end()
    plain_parts.append(rendered[cursor:])
    rendered = "".join(plain_parts)
    return (
        rendered,
        _unique(
            occurrence.canonical
            for occurrence in entity_occurrences
            if occurrence.target_identity
        ),
        tuple(entity_occurrences),
        _unique(locations),
        _unique((*map_labels, *_extract_map_numbers(rendered))),
        _unique(warnings),
    )


def _extract_coordinates(value: str) -> tuple[str, ...]:
    return _unique(match.group(1).upper() for match in re.finditer(r"(?<![A-Z0-9])([A-P]-\d{1,2})(?!\d)", value, re.IGNORECASE))


def _extract_map_numbers(value: str) -> tuple[str, ...]:
    return _unique(match.group(1) for match in re.finditer(r"\bmap\s*(?:number\s*)?([0-9]+|north|south|east|west)\b", value, re.IGNORECASE))


def _authoritative_zone_names() -> tuple[str, ...]:
    global _ZONE_NAMES
    if _ZONE_NAMES is not None:
        return _ZONE_NAMES
    graph_path = Path(__file__).resolve().parents[2] / "data" / "ffxi-nav-zoneline-graph.tsv"
    names: list[str] = []
    if graph_path.is_file():
        for line in graph_path.read_text(encoding="utf-8").splitlines():
            fields = line.split("\t")
            if len(fields) >= 9 and fields[0].strip().isdigit():
                names.extend((fields[2], fields[8]))
    _ZONE_NAMES = tuple(sorted(_unique(names), key=lambda value: (-len(value), value.casefold())))
    return _ZONE_NAMES


def _zone_aliases(zone_name: str) -> tuple[str, ...]:
    if zone_name.endswith(" [S]"):
        return zone_name, zone_name[:-4] + " (S)"
    return (zone_name,)


def _extract_zone_mentions(
    text: str,
    explicit_locations: Iterable[str] = (),
    zone_names: Iterable[str] | None = None,
) -> tuple[str, ...]:
    catalogue = tuple(zone_names) if zone_names is not None else _authoritative_zone_names()
    aliases: list[tuple[str, str]] = []
    for canonical in catalogue:
        canonical = _clean(canonical)
        if canonical:
            aliases.extend((alias, canonical) for alias in _zone_aliases(canonical))
    aliases.sort(key=lambda row: (-len(row[0]), row[0].casefold()))
    occupied: list[tuple[int, int]] = []
    found: list[tuple[int, str]] = []
    for alias, canonical in aliases:
        pattern = re.compile(rf"(?<![A-Za-z0-9]){re.escape(alias)}(?![A-Za-z0-9])", re.IGNORECASE)
        for match in pattern.finditer(text):
            if any(match.start() < end and start < match.end() for start, end in occupied):
                continue
            occupied.append((match.start(), match.end()))
            found.append((match.start(), canonical))
    canonical_by_key = {
        alias.casefold(): canonical
        for canonical in catalogue
        for alias in _zone_aliases(_clean(canonical))
    }
    for explicit in explicit_locations:
        canonical = canonical_by_key.get(_clean(explicit).casefold())
        if canonical and canonical.casefold() not in {value.casefold() for _offset, value in found}:
            found.append((-1, canonical))
    return _unique(value for _offset, value in sorted(found, key=lambda row: (row[0], row[1].casefold())))


_ACTION_MATCH = re.compile(
    r"\b(?P<verb>re-examine|examine|touch|click|inspect|check|trade|give|hand over|deliver|"
    r"talk|speak|return to|report to|visit|defeat|defeating|fight|kill|killing|slay|slaying|destroy|obtain|receive|collect|"
    r"purchase|go to|head to|travel to|enter|exit|zone into|proceed to|make your way to|"
    r"wait|use|activate|light|open|protect|select|choose|board)\b",
    re.IGNORECASE,
)

_NAME_ABBREVIATIONS = frozenset({"dr", "mr", "mrs", "ms"})
_NUMERIC_ABBREVIATIONS = frozenset({"lv", "no"})
_NEW_SENTENCE_EVENT = re.compile(
    r"(?:a|an|the)\s+(?:cutscene|event|scene)\b",
    re.IGNORECASE,
)
_NEW_SENTENCE_LEADER = re.compile(
    r"(?:at|in|on|inside|outside|near|from)\b|"
    r"(?:talk|speak|defeat|kill|slay|trade|obtain|receive|collect|examine|check|inspect|"
    r"touch|use|select|return|report|visit|go|travel|enter|exit|leave)\b",
    re.IGNORECASE,
)
_PROVEN_ABBREVIATION_CONTINUATION = re.compile(
    r"(?:details?|encounters?|in|to)\b",
    re.IGNORECASE,
)


def _trim_target(value: str) -> str:
    value = _clean(value).strip(" ,.;:!?")
    value = re.sub(r"^(?:the|an|a)\s+", "", value, flags=re.IGNORECASE)
    return value.strip(" ,.;:!?")


def _action_for_verb(verb: str) -> tuple[str, str]:
    key = verb.casefold()
    if key in {"talk", "speak", "return to", "report to", "visit"}:
        return "talk", "talk-to"
    if key in {"trade", "give", "hand over", "deliver"}:
        return "trade", "trade-to"
    if key in {"defeat", "defeating", "fight", "kill", "killing", "slay", "slaying", "destroy"}:
        return "fight", "defeat-enemy"
    if key in {"re-examine", "examine", "touch", "click", "inspect", "check"}:
        return "examine", "examine-object"
    if key in {"obtain", "receive", "collect", "purchase"}:
        return "obtain", "obtain-item"
    if key == "enter":
        return "travel", "enter-through"
    if key in {"go to", "head to", "travel to", "exit", "zone into", "proceed to", "make your way to"}:
        return "travel", "travel-to"
    if key in {"select", "choose"}:
        return "select", "menu-choice"
    if key == "board":
        return "travel", "board-transport"
    if key == "protect":
        return "protect", "protect-role"
    if key == "wait":
        return "wait", "wait-for"
    return "use", "use-object"


def _values_in_clause(values: Iterable[str], clause: str) -> tuple[str, ...]:
    return _unique(
        value
        for value in values
        if re.search(
            rf"(?<![A-Za-z0-9]){re.escape(value)}(?![A-Za-z0-9])",
            clause,
            re.IGNORECASE,
        )
    )


def _links_in_range(
    link_occurrences: tuple[_EntityOccurrence, ...],
    start: int,
    end: int,
) -> tuple[str, ...]:
    return _unique(
        occurrence.canonical
        for occurrence in link_occurrences
        if occurrence.target_identity
        and start <= occurrence.start
        and occurrence.end <= end
    )


def _links_in_match(
    link_occurrences: tuple[_EntityOccurrence, ...],
    offset: int,
    match: re.Match[str],
    group: int,
) -> tuple[str, ...]:
    return _links_in_range(
        link_occurrences,
        offset + match.start(group),
        offset + match.end(group),
    )


def _links_with_role_in_range(
    link_occurrences: tuple[_EntityOccurrence, ...],
    start: int,
    end: int,
    *roles: str,
) -> tuple[str, ...]:
    wanted = set(roles)
    return _unique(
        occurrence.canonical
        for occurrence in link_occurrences
        if occurrence.role in wanted
        and start <= occurrence.start
        and occurrence.end <= end
    )


def _canonical_zone_links_in_range(
    link_occurrences: tuple[_EntityOccurrence, ...],
    start: int,
    end: int,
) -> tuple[str, ...]:
    zones = {
        alias.casefold(): zone
        for zone in _authoritative_zone_names()
        for alias in _zone_aliases(zone)
    }
    return _unique(
        zones[occurrence.canonical.casefold()]
        for occurrence in link_occurrences
        if occurrence.source_link
        and not occurrence.role
        and start <= occurrence.start
        and occurrence.end <= end
        and occurrence.canonical.casefold() in zones
    )


def _refine_linked_target(
    raw_target: str,
    target_links: tuple[str, ...],
    excluded_links: tuple[str, ...],
    *,
    raw_fallback_blocked: bool = False,
) -> tuple[str, tuple[str, ...]]:
    target = _trim_target(raw_target)
    excluded = {value.casefold() for value in excluded_links}
    candidates = tuple(
        value
        for value in target_links
        if value.casefold() not in excluded
    )
    if len(candidates) == 1:
        return candidates[0], candidates
    if len(candidates) > 1:
        return "", candidates
    if raw_fallback_blocked:
        return "", ()
    if target.casefold() in excluded:
        return "", ()
    return target, ((target,) if target else ())


def _refine_match_target(
    raw_target: str,
    link_occurrences: tuple[_EntityOccurrence, ...],
    offset: int,
    match: re.Match[str],
    group: int,
    excluded_links: tuple[str, ...],
) -> tuple[str, tuple[str, ...]]:
    group_start = offset + match.start(group)
    group_end = offset + match.end(group)
    excluded = {value.casefold() for value in excluded_links}
    unsafe_occurrence_overlaps = any(
        (
            not occurrence.target_identity
            or occurrence.canonical.casefold() in excluded
        )
        and occurrence.start < group_end
        and group_start < occurrence.end
        for occurrence in link_occurrences
    )
    return _refine_linked_target(
        raw_target,
        _links_in_match(link_occurrences, offset, match, group),
        excluded_links,
        raw_fallback_blocked=unsafe_occurrence_overlaps,
    )


def _period_is_internal_abbreviation(
    value: str,
    end: int,
    *,
    next_is_qualified_link: bool,
) -> bool:
    continuation = value[end:].lstrip()
    if not continuation or _NEW_SENTENCE_EVENT.match(continuation):
        return False
    if continuation[0].isupper() and _NEW_SENTENCE_LEADER.match(continuation):
        return False

    initialism = re.search(
        r"(?i)(?<![A-Za-z])((?:[A-Za-z]\.){2,})$",
        value[:end],
    )
    if initialism:
        token = initialism.group(1).casefold()
        if next_is_qualified_link:
            prefix = value[:end]
            if token in {"e.g.", "i.e."} and re.search(
                r"(?:^\s+(?:an?\s+)?enemy|\b(?:defeat|fight|kill|slay|destroy)\b[^.!?]*)"
                r",\s*(?:e\.g\.|i\.e\.)$",
                prefix,
                re.IGNORECASE,
            ):
                return True
            if re.search(
                r"(?:^|\b(?:defeat|fight|kill|slay|destroy))\s+(?:the\s+)?"
                r"(?:(?:[A-Za-z]\.){2,}\s+)*(?:[A-Za-z]\.){2,}$",
                prefix,
                re.IGNORECASE,
            ):
                return True
        if _PROVEN_ABBREVIATION_CONTINUATION.match(continuation):
            return True
        if token in {"e.g.", "i.e."} and re.match(
            r"[^.!?]*,\s*(?:to|in|at|on)\b",
            continuation,
            re.IGNORECASE,
        ):
            return True
        return False

    abbreviation = re.search(r"([A-Za-z]+)\.$", value[:end])
    if not abbreviation:
        return False
    token = abbreviation.group(1).casefold()
    if token in _NUMERIC_ABBREVIATIONS:
        return re.match(r"\d", continuation) is not None
    if token in _NAME_ABBREVIATIONS:
        return re.match(r"[A-Z][A-Za-z'-]+\b", continuation) is not None
    if token == "etc":
        return _PROVEN_ABBREVIATION_CONTINUATION.match(continuation) is not None
    return False


def _strong_sentence_boundaries(
    value: str,
    *,
    text_offset: int = 0,
    link_occurrences: tuple[_EntityOccurrence, ...] = (),
) -> tuple[tuple[int, int], ...]:
    boundaries: list[tuple[int, int]] = []
    for match in re.finditer(r"[.!?]+", value):
        start, end = match.span()
        run = match.group(0)
        if end < len(value) and not value[end].isspace():
            continue
        if set(run) == {"?"} and len(run) >= 3:
            continue
        if set(run) == {"."} and len(run) >= 2:
            continue
        if run == ".":
            if (
                start > 0
                and end < len(value)
                and value[start - 1].isdigit()
                and value[end].isdigit()
            ):
                continue
            continuation_start = end
            while continuation_start < len(value) and value[continuation_start].isspace():
                continuation_start += 1
            following_links = sorted(
                (
                    occurrence
                    for occurrence in link_occurrences
                    if occurrence.start >= text_offset + continuation_start
                    and occurrence.start <= text_offset + len(value)
                ),
                key=lambda occurrence: occurrence.start,
            )
            next_is_qualified_link = False
            if following_links:
                link_start = following_links[0].start - text_offset
                qualifier = value[continuation_start:link_start]
                next_is_qualified_link = re.fullmatch(
                    r"\s*(?:(?:the|an?)\s+)?",
                    qualifier,
                    re.IGNORECASE,
                ) is not None
            if _period_is_internal_abbreviation(
                value,
                end,
                next_is_qualified_link=next_is_qualified_link,
            ):
                continue
        boundary_start = start
        if len(run) > 1 and run[-1] in ".!" and (
            run.startswith("???") or run.startswith("...")
        ):
            boundary_start = end - 1
        boundaries.append((boundary_start, end))
    return tuple(boundaries)


def _extract_action_spans(
    text: str,
    *,
    source_step_order: int,
    link_occurrences: tuple[_EntityOccurrence, ...],
    zones: tuple[str, ...],
    maps: tuple[str, ...],
    coordinates: tuple[str, ...],
) -> tuple[SourceActionSpan, ...]:
    matches = list(_ACTION_MATCH.finditer(text))
    warning_match = re.search(
        r"\b(?:leaving|exiting)\b.+?\b(?:lose|loses|removes?)\b.+?(?=[.;]|$)",
        text,
        re.IGNORECASE,
    )
    if warning_match and not any(match.start() == warning_match.start() for match in matches):
        matches.append(
            re.search(r"\b(?:lose|loses|removes?)\b", text[warning_match.start() : warning_match.end()], re.IGNORECASE)
        )
        synthetic = matches[-1]
        if synthetic is not None:
            offset = warning_match.start()
            matches[-1] = _OffsetMatch(synthetic, offset)
    matches = sorted((match for match in matches if match is not None), key=lambda match: match.start())
    clause_starts = [match.start() for match in matches]
    clause_ends = [matches[index + 1].start() if index + 1 < len(matches) else len(text) for index in range(len(matches))]
    suppressed_location_evidence: set[int] = set()
    if matches:
        clause_starts[0] = 0
        leading = text[: matches[0].start()]
        strong_boundaries = _strong_sentence_boundaries(
            leading,
            link_occurrences=link_occurrences,
        )
        subordinate = re.match(
            r"\s*(?:after|before|while|upon|once)\s+(?:talking|speaking|visiting|defeating|fighting|"
            r"killing|examining|touching|using|entering|exiting|travelling|traveling)\b",
            leading,
            re.IGNORECASE,
        )
        punctuation = list(re.finditer(r"[,;]", leading))
        if strong_boundaries:
            clause_starts[0] = strong_boundaries[-1][1]
        elif subordinate and punctuation:
            clause_starts[0] = punctuation[-1].end()
    for index in range(1, len(matches)):
        between = text[matches[index - 1].end() : matches[index].start()]
        strong_boundaries = _strong_sentence_boundaries(
            between,
            text_offset=matches[index - 1].end(),
            link_occurrences=link_occurrences,
        )
        if strong_boundaries:
            first_boundary = strong_boundaries[0]
            last_boundary = strong_boundaries[-1]
            offset = matches[index - 1].end()
            clause_ends[index - 1] = offset + first_boundary[0]
            clause_starts[index] = offset + last_boundary[1]
            continue
        connectors = list(re.finditer(r"\bthen\b", between, re.IGNORECASE))
        if connectors:
            connector = connectors[-1]
            offset = matches[index - 1].end()
            clause_ends[index - 1] = offset + connector.start()
            clause_starts[index] = offset + connector.end()
            continue
        location_leader = r"(?=(?:in|at|on|inside|outside|near|from)\b)"
        leading_connector = re.search(
            r"[,;]\s*(?:and\s+)?" + location_leader,
            between,
            re.IGNORECASE,
        )
        if leading_connector is None:
            leading_connector = re.search(r"\band\s+" + location_leader, between, re.IGNORECASE)
        if leading_connector:
            offset = matches[index - 1].end()
            clause_ends[index - 1] = offset + leading_connector.start()
            clause_starts[index] = offset + leading_connector.end()
            continue
        if len(_extract_zone_mentions(between)) > 1:
            suppressed_location_evidence.add(index - 1)
    for index, match in enumerate(matches):
        trailing_start = match.end()
        boundaries = _strong_sentence_boundaries(
            text[trailing_start : clause_ends[index]],
            text_offset=trailing_start,
            link_occurrences=link_occurrences,
        )
        if boundaries:
            clause_ends[index] = trailing_start + boundaries[0][0]
    spans: list[SourceActionSpan] = []
    for index, match in enumerate(matches):
        verb = match.group("verb") if "verb" in match.groupdict() else match.group(0)
        action, relationship = _action_for_verb(verb)
        if warning_match and warning_match.start() <= match.start() < warning_match.end() and verb.casefold() in {
            "lose",
            "loses",
            "remove",
            "removes",
        }:
            action, relationship = "warning", "required-state-warning"
        start = clause_starts[index]
        end = clause_ends[index]
        raw_clause = text[start:end]
        clause = _clean(raw_clause).strip(" ,")
        remainder = text[match.end() : end]
        clause_zones = _unique(
            (
                *_extract_zone_mentions(raw_clause),
                *_canonical_zone_links_in_range(link_occurrences, start, end),
            )
        )
        clause_maps = _extract_map_numbers(raw_clause)
        clause_coordinates = _extract_coordinates(raw_clause)
        if index in suppressed_location_evidence:
            clause_zones = ()
            clause_maps = ()
            clause_coordinates = ()
        clause_marked_items = _links_with_role_in_range(
            link_occurrences,
            start,
            end,
            "item",
        )
        clause_key_items = _links_with_role_in_range(
            link_occurrences,
            start,
            end,
            "key-item",
        )
        excluded_target_links = _unique((*clause_zones, *clause_marked_items, *clause_key_items))
        target = ""
        target_kind = ""
        item_mentions: tuple[str, ...] = ()
        key_item_mentions = clause_key_items
        npc_mentions: tuple[str, ...] = ()
        object_mentions: tuple[str, ...] = ()
        enemy_mentions: tuple[str, ...] = ()
        transport_mentions: tuple[str, ...] = ()

        if action == "trade":
            trade = re.match(
                r"\s+(?:the\s+|an?\s+)?(.+?)\s+to\s+(?:the\s+)?"
                r"(.+?)(?=\s+(?:in|at)\b|\s+on\s+map\b|\s*\([A-P]-\d{1,2}\)|[;,]|$)",
                remainder,
                re.IGNORECASE,
            )
            if trade:
                item = _trim_target(trade.group(1))
                target, npc_mentions = _refine_match_target(
                    trade.group(2),
                    link_occurrences,
                    match.end(),
                    trade,
                    2,
                    excluded_target_links,
                )
                item_mentions = (item,) if item else ()
                target_kind = "npc"
        elif action == "talk":
            if verb.casefold() in {"return to", "report to", "visit"}:
                talked = re.match(
                    r"\s+(?:the\s+)?(.+?)(?=\s+(?:at|in|for)\b|\s*\(|[;,]|$)",
                    remainder,
                    re.IGNORECASE,
                )
            else:
                talked = re.match(
                    r"\s+(?:to|with)\s+(?:the\s+)?(.+?)(?=\s+(?:at|in|for)\b|\s*\(|[;,]|$)",
                    remainder,
                    re.IGNORECASE,
                )
            if talked:
                target, npc_mentions = _refine_match_target(
                    talked.group(1),
                    link_occurrences,
                    match.end(),
                    talked,
                    1,
                    excluded_target_links,
                )
            if target.casefold() in {"him", "her", "them", "it"}:
                target_kind = "role"
                npc_mentions = ()
            else:
                target_kind = "npc" if target or npc_mentions else ""
        elif action == "fight":
            fought = re.match(
                r"\s+(?:an?\s+)?enemy\s*,\s*(?:e\.g\.|i\.e\.)\s+(.+?)"
                r"(?=\s+(?:in|at|for)\b|[;,]|$)",
                remainder,
                re.IGNORECASE,
            )
            if fought is None:
                fought = re.match(
                    r"\s+(?:the\s+)?(.+?)(?=\s+(?:to|and)\s*$|"
                    r"\s+to\s+(?:obtain|receive|collect)\b|\s+(?:in|at|for)\b|"
                    r"\s+and\s+(?:re-examine|examine|touch|click)\b|[;,]|$)",
                    remainder,
                    re.IGNORECASE,
                )
            if fought:
                target, enemy_mentions = _refine_match_target(
                    fought.group(1),
                    link_occurrences,
                    match.end(),
                    fought,
                    1,
                    excluded_target_links,
                )
            target_kind = "enemy" if target or enemy_mentions else ""
        elif action == "examine":
            examined = re.match(
                r"\s+(?:the\s+)?(.+?)(?=\s+to\s+(?:obtain|receive|collect|enter)\b|"
                r"\s+again\b|\s+(?:in|at)\b|[;,]|$)",
                remainder,
                re.IGNORECASE,
            )
            raw_target = examined.group(1) if examined else ""
            if "???" in raw_target:
                target, target_kind = "???", "question-mark"
                object_mentions = (target,)
            else:
                if examined is not None:
                    target, object_mentions = _refine_match_target(
                        raw_target,
                        link_occurrences,
                        match.end(),
                        examined,
                        1,
                        excluded_target_links,
                    )
                else:
                    target, object_mentions = _refine_linked_target(
                        raw_target,
                        (),
                        excluded_target_links,
                    )
                target = re.sub(r"^sparkling\s+", "", target, flags=re.IGNORECASE)
                if target:
                    object_mentions = (target,)
                target_kind = "object" if target or object_mentions else ""
        elif action == "obtain":
            obtained = re.match(
                r"\s+(?:the\s+|an?\s+)?(.+?)(?=\s+by\b|\s+from\b|\s+in\b|[,;]|$)",
                remainder,
                re.IGNORECASE,
            )
            target = _trim_target(obtained.group(1)) if obtained else ""
            target_kind = "item" if target else ""
            item_mentions = (target,) if target else ()
        elif action == "travel":
            target = clause_zones[0] if clause_zones else ""
            target_kind = "zone" if target else ("transport" if relationship == "board-transport" else "")
            if relationship == "board-transport":
                boarded = re.match(r"\s+(?:the\s+)?(.+?)(?=[;,]|$)", remainder, re.IGNORECASE)
                target = _trim_target(boarded.group(1)) if boarded else target
                transport_mentions = (target,) if target else ()
            elif relationship == "enter-through" and not target:
                entered = re.match(r"\s+(?:the\s+)?(.+?)(?=[;,]|$)", remainder, re.IGNORECASE)
                target = _trim_target(entered.group(1)) if entered else ""
                target_kind = "entrance" if target else ""
        elif action == "protect":
            protected = re.match(r"\s+(?:the\s+)?(.+?)(?=[;]|$)", remainder, re.IGNORECASE)
            target = _trim_target(protected.group(1)) if protected else ""
            target_kind = "role" if target else ""
        elif action == "warning":
            target = clause_key_items[0] if clause_key_items else ""
            target_kind = "key-item" if target else "state"
            item_mentions = clause_key_items
            clause = _clean(warning_match.group(0)) if warning_match else clause
        elif action in {"use", "select"}:
            used = re.match(r"\s+(?:the\s+)?(.+?)(?=\s+(?:in|at)\b|[;,]|$)", remainder, re.IGNORECASE)
            if used:
                target, object_mentions = _refine_match_target(
                    used.group(1),
                    link_occurrences,
                    match.end(),
                    used,
                    1,
                    excluded_target_links,
                )
            target_kind = "menu-choice" if action == "select" else "object"
            if action == "select":
                object_mentions = ()

        item_mentions = _unique((*item_mentions, *clause_marked_items, *clause_key_items))
        spans.append(
            SourceActionSpan(
                source_step_order=source_step_order,
                order=len(spans) + 1,
                text_start=start,
                text_end=end,
                supporting_clause=clause,
                action=action,
                verb=verb.casefold(),
                relationship=relationship,
                target=target,
                target_kind=target_kind,
                target_role=target_kind,
                npc_mentions=npc_mentions,
                object_mentions=object_mentions,
                enemy_mentions=enemy_mentions,
                item_mentions=item_mentions,
                key_item_mentions=key_item_mentions,
                transport_mentions=transport_mentions,
                zone_mentions=clause_zones,
                temporal_zone_variant="past" if any(zone.endswith(" [S]") for zone in clause_zones) else "",
                map_numbers=clause_maps,
                grid_coordinates=clause_coordinates,
            )
        )

    collapsed: list[SourceActionSpan] = []
    index = 0
    while index < len(spans):
        span = spans[index]
        next_span = spans[index + 1] if index + 1 < len(spans) else None
        forward_relation = bool(
            next_span is not None
            and next_span.verb in {"obtain", "receive", "collect"}
            and re.search(r"\bto\s*$", text[span.text_start : span.text_end], re.IGNORECASE)
        )
        if (
            span.action in {"fight", "examine"}
            and next_span is not None
            and next_span.action == "obtain"
            and forward_relation
            and not (
                span.action == "examine"
                and collapsed
                and collapsed[-1].action == "fight"
            )
        ):
            collapsed.append(
                replace(
                    span,
                    text_end=next_span.text_end,
                    supporting_clause=_clean(text[span.text_start : next_span.text_end]).strip(" ,"),
                    relationship="defeat-to-obtain" if span.action == "fight" else "examine-to-obtain",
                    item_mentions=_unique((*span.item_mentions, *next_span.item_mentions)),
                    key_item_mentions=_unique((*span.key_item_mentions, *next_span.key_item_mentions)),
                    result_items=(next_span.target,) if next_span.target else (),
                    result_relation="obtain-from",
                )
            )
            index += 2
            continue
        reversed_relation = bool(
            next_span is not None
            and next_span.verb in {"defeating", "killing", "slaying"}
            and re.search(r"\bby\s*$", text[span.text_start : span.text_end], re.IGNORECASE)
        )
        if (
            span.action == "obtain"
            and next_span is not None
            and next_span.action == "fight"
            and reversed_relation
        ):
            collapsed.append(
                replace(
                    next_span,
                    text_start=span.text_start,
                    supporting_clause=_clean(text[span.text_start : next_span.text_end]).strip(" ,"),
                    relationship="defeat-to-obtain",
                    item_mentions=_unique((*span.item_mentions, *next_span.item_mentions)),
                    key_item_mentions=_unique((*span.key_item_mentions, *next_span.key_item_mentions)),
                    result_items=(span.target,) if span.target else (),
                    result_relation="obtain-from",
                )
            )
            index += 2
            continue
        collapsed.append(span)
        index += 1
    spans = collapsed
    return tuple(replace(span, order=order) for order, span in enumerate(spans, start=1))


class _OffsetMatch:
    def __init__(self, match: re.Match[str], offset: int) -> None:
        self._match = match
        self._offset = offset

    def start(self) -> int:
        return self._offset + self._match.start()

    def end(self) -> int:
        return self._offset + self._match.end()

    def group(self, *args: object) -> str:
        return self._match.group(*args)

    def groupdict(self) -> dict[str, str | None]:
        return self._match.groupdict()


def _classify_action(text: str) -> str:
    lower = text.casefold()
    if re.search(r"\b(?:talk|speak|deliver .* to|return to)\b", lower):
        return "talk"
    if re.search(r"\b(?:trade|give|hand over)\b", lower):
        return "trade"
    if re.search(r"\b(?:examine|touch|click|inspect|check the \?\?\?)\b", lower):
        return "examine"
    if re.search(r"\b(?:defeat|fight|kill|battle|slay)\b", lower):
        return "fight"
    if re.search(r"\b(?:wait|stand on|remain on)\b", lower):
        return "wait"
    if re.search(r"\b(?:use|activate|light|open)\b", lower):
        return "use"
    if re.search(r"\b(?:go to|head to|travel to|enter|exit|zone into|proceed to|make your way)\b", lower):
        return "travel"
    if re.search(r"\b(?:obtain|receive|collect|bring|purchase)\b", lower):
        return "obtain"
    return "note"


def _spoken_step(
    text: str,
    action: str,
    links: tuple[str, ...],
    coordinates: tuple[str, ...],
    maps: tuple[str, ...],
) -> str:
    if len(text) <= MAX_SPOKEN_STEP:
        return text
    required = _unique((*links, *coordinates, *(f"Map {value}" for value in maps)))
    suffix = " Required details: " + ", ".join(required) + "." if required else ""
    budget = MAX_SPOKEN_STEP - len(suffix) - 3
    if budget < 80:
        budget = max(20, MAX_SPOKEN_STEP - len(suffix) - 3)
    prefix = text[:budget].rsplit(" ", 1)[0].rstrip(" ,;:")
    if not prefix:
        prefix = action.capitalize()
    return (prefix + "..." + suffix)[:MAX_SPOKEN_STEP]


def _walkthrough_lines(content: str) -> tuple[str, ...]:
    lines = content.replace("\r", "").split("\n")
    start = -1
    level = 0
    heading_pattern = re.compile(r"^\s*(={2,6})\s*(.*?)\s*\1\s*$")
    for index, line in enumerate(lines):
        match = heading_pattern.match(line)
        if match and _strip_code(match.group(2)).casefold() in {"walkthrough", "walk-through"}:
            start = index + 1
            level = len(match.group(1))
            break
    if start < 0:
        return ()

    result: list[str] = []
    for line in lines[start:]:
        heading = heading_pattern.match(line)
        if heading and len(heading.group(1)) <= level:
            heading_text = _strip_code(heading.group(2))
            numbered_route = (
                len(heading.group(1)) == level
                and (
                    re.search(r"\b\d+-\d+[A-Za-z]\d*\b", heading_text) is not None
                    or heading_text.casefold().startswith("completing ")
                )
            )
            if not numbered_route:
                break
        result.append(line)
    return tuple(result)


def _selected_level_two_sections(content: str, wanted: set[str]) -> tuple[str, ...]:
    lines = content.replace("\r", "").split("\n")
    heading_pattern = re.compile(r"^\s*(={2,6})\s*(.*?)\s*\1\s*$")
    result: list[str] = []
    selected = False
    for line in lines:
        heading = heading_pattern.match(line)
        if heading and len(heading.group(1)) == 2:
            selected = _name_key(_strip_code(heading.group(2))) in wanted
            if selected:
                result.append(line)
            continue
        if selected:
            result.append(line)
    return tuple(result)


def _special_guidance_lines(revision: PageRevision) -> tuple[str, ...]:
    if revision.canonical_title in _NYZUL_OBJECTIVE_TITLES:
        return _selected_level_two_sections(revision.content, _NYZUL_PROGRESS_SECTIONS)
    if revision.site == "bg" and revision.canonical_title == "Sahagin Key":
        return _selected_level_two_sections(
            revision.content,
            {"obtainment", "additionalkeys"},
        )
    return ()


def _legacy_template_guidance_lines(content: str) -> tuple[str, ...]:
    """Expose objective-specific legacy template fields without expanding or guessing them."""

    code = mwparserfromhell.parse(content)
    for template in code.filter_templates(recursive=True):
        key = _name_key(template.name)
        labeled: list[tuple[str, str]] = []
        if key == "assaultmission":
            for label, names in (
                ("Objective", ("objective",)),
                ("Orders", ("orders",)),
                ("Area", ("area",)),
                ("Staging point", ("staging point", "stagingpoint")),
                ("Mission contact", ("npc",)),
            ):
                value = _raw_template_parameter(template, *names)
                if value:
                    labeled.append((label, value))
        elif key == "nyzulheader":
            for label, names in (
                ("Orders", ("orders",)),
                ("Area", ("assault area", "area")),
                ("Recommended level", ("level",)),
            ):
                value = _raw_template_parameter(template, *names)
                if value:
                    labeled.append((label, value))
        elif key == "gobbiebagquest":
            summary = _raw_template_parameter(template, "summary")
            if summary:
                labeled.append(("Summary", summary))
            else:
                for number in range(1, 5):
                    value = _raw_template_parameter(template, f"item{number}")
                    if value:
                        labeled.append((f"Required item {number}", value))
        elif key == "boghertzquest":
            for label, names in (
                ("Job", ("job",)),
                ("Previous quest", ("previous quest", "previousquest")),
                ("Hands area", ("hands area", "handsarea")),
                ("Hands key", ("hands key", "handskey")),
                ("Hands item", ("hands item", "handsitem")),
                ("Second area", ("area 2", "area2")),
                ("Second key", ("key 2", "key2")),
                ("Second item", ("item 2", "item2")),
                ("Third area", ("area 3", "area3")),
                ("Third key", ("key 3", "key3")),
                ("Third item", ("item 3", "item3")),
            ):
                value = _raw_template_parameter(template, *names)
                if value:
                    labeled.append((label, value))
        elif key == "unlockingmyth":
            positional = [str(parameter.value).strip() for parameter in template.params if str(parameter.name).strip().isdigit()]
            for label, value in zip(("Weapon", "Weapon skill", "Weapon type", "Job"), positional):
                if value:
                    labeled.append((label, value))
        elif key == "mogws":
            for label, names in (
                ("Weapon skill", ("ws",)),
                ("Weapon type", ("type",)),
                ("Walk of Echoes weapon", ("woeweapon",)),
                ("Empyrean weapon", ("empyrean",)),
                ("Jobs", ("jobs",)),
            ):
                value = _raw_template_parameter(template, *names)
                if value:
                    labeled.append((label, value))
        if labeled:
            phrases = [f"{label}: {value.rstrip(' .;:!?')}" for label, value in labeled]
            return ("* " + ". ".join(phrases) + ".",)
    return ()


def _header_details(revision: PageRevision) -> tuple[str, str, str, str, tuple[str, ...]]:
    code = mwparserfromhell.parse(revision.content)
    warnings: list[str] = []
    for template in code.filter_templates(recursive=True):
        key = _name_key(template.name)
        if key == "missionheader":
            name = _template_parameter(template, "Mission Name", "name") or revision.canonical_title
            context = _template_parameter(template, "Expansion")
            number_match = re.search(r"\b(?:mission\s+)?(\d+-\d+)\b", revision.canonical_title, re.IGNORECASE)
            number = number_match.group(1) if number_match else ""
            return "mission", name, number, context, tuple(warnings)
        if key == "mission":
            name = _template_parameter(template, "name") or revision.canonical_title
            number = _template_parameter(template, "number")
            return "mission", name, number, "", tuple(warnings)
        if key == "assaultmission":
            name = _template_parameter(template, "name") or revision.canonical_title
            return "mission", name, "", "Assault", tuple(warnings)
        if key == "nyzulheader" and revision.canonical_title in _NYZUL_OBJECTIVE_TITLES:
            return "mission", revision.canonical_title, "", "Assault", tuple(warnings)
        if key == "questheader":
            return "quest", revision.canonical_title, "", "", tuple(warnings)
        if key == "quest":
            return "quest", revision.canonical_title, "", "", tuple(warnings)
        if key in {"gobbiebagquest", "boghertzquest", "unlockingmyth", "mogws"}:
            return "quest", revision.canonical_title, "", "", tuple(warnings)
    categories = {_name_key(category) for category in _page_categories(revision.content)}
    if revision.canonical_title in _NYZUL_OBJECTIVE_TITLES and categories.intersection(
        {"assault", "assaultmissions"}
    ):
        return "mission", revision.canonical_title, "", "Assault", tuple(warnings)
    if (
        revision.site == "bg"
        and revision.canonical_title == "Sahagin Key"
        and "miniquests" in categories
    ):
        return "quest", revision.canonical_title, "", "", tuple(warnings)
    raise WikitextError(f"{revision.site} page {revision.canonical_title!r} has no supported mission or quest header.")


def _page_categories(content: str) -> tuple[str, ...]:
    categories: list[str] = []
    for link in mwparserfromhell.parse(content).filter_wikilinks(recursive=True):
        target = _clean(link.title)
        if target.casefold().startswith("category:"):
            categories.append(target.split(":", 1)[1])
    return _unique(categories)


def _header_start_entities(
    content: str,
    site_policy: SiteLinkPolicy | None,
) -> tuple[str, ...]:
    code = mwparserfromhell.parse(content)
    for template in code.filter_templates(recursive=True):
        if _name_key(template.name) not in {"mission", "missionheader", "quest", "questheader"}:
            continue
        for parameter_name in ("Start", "npc", "startnpc", "client"):
            for parameter in template.params:
                if _name_key(parameter.name) != _name_key(parameter_name):
                    continue
                entities: list[str] = []
                for link in mwparserfromhell.parse(str(parameter.value)).filter_wikilinks(recursive=True):
                    canonical, display, target_identity = _wikilink_identity_details(
                        link,
                        site_policy,
                    )
                    if canonical and display and target_identity:
                        entities.append(display)
                return _unique(entities)
    return ()


def parse_objective_page(
    revision: PageRevision,
    *,
    site_policy: SiteLinkPolicy | None | object = _DEFAULT_SITE_POLICY,
) -> ParsedObjective:
    if site_policy is _DEFAULT_SITE_POLICY:
        try:
            site_policy = load_default_site_link_policies()[revision.site]
        except (KeyError, SiteConfigError):
            site_policy = None
    if site_policy is not None and not isinstance(site_policy, SiteLinkPolicy):
        raise TypeError("site_policy must be a SiteLinkPolicy or None.")
    try:
        validate_source_site_binding(
            revision.site,
            revision.api_url,
            site_policy,
        )
    except SiteConfigError as error:
        raise WikitextError(
            f"{revision.site} page {revision.canonical_title!r} has mismatched source policy provenance."
        ) from error
    kind, objective_name, mission_number, context_hint, header_warnings = _header_details(revision)
    steps: list[SourceStep] = []
    page_warnings = list(header_warnings)
    guide_lines = (
        *_legacy_template_guidance_lines(revision.content),
        *_walkthrough_lines(revision.content),
        *_special_guidance_lines(revision),
    )
    for line in guide_lines:
        candidate = line.lstrip()
        heading_match = re.match(r"^(={2,6})\s*(.*?)\s*\1\s*$", candidate)
        if heading_match:
            heading = _strip_code(heading_match.group(2)).rstrip(" .")
            marker = "*" * max(1, len(heading_match.group(1)) - 2)
            fragment = f"Section: {heading}." if heading else ""
        else:
            if candidate.startswith("|") and len(candidate) > 1 and candidate[1] in "#*":
                candidate = candidate[1:].lstrip()
            if not candidate or candidate.startswith(("{{", "}}", "{|", "|}", "|", "!", "=", "<")):
                continue
            if re.match(r"^\[\[(?:file|image):", candidate, re.IGNORECASE):
                continue
            match = re.match(r"^([#*]+)\s*(.*)$", candidate)
            colon_match = re.match(r"^(:+)([#*]+)\s*(.*)$", candidate)
            numbered_match = re.match(r"^\d+[.)]\s*(.*)$", candidate)
            if match:
                marker, fragment = match.groups()
            elif colon_match:
                colons, symbols, fragment = colon_match.groups()
                marker = "*" * (len(colons) + len(symbols))
            elif numbered_match:
                marker, fragment = "#", numbered_match.group(1)
            else:
                marker, fragment = "*", candidate
        if not fragment.strip():
            continue
        rendered, links, link_occurrences, locations, maps, warnings = _render_fragment(
            fragment,
            site_policy,
        )
        if not rendered:
            continue
        coordinates = _extract_coordinates(rendered)
        key_items = _links_with_role_in_range(
            link_occurrences,
            0,
            len(rendered),
            "key-item",
        )
        items = _links_with_role_in_range(
            link_occurrences,
            0,
            len(rendered),
            "item",
        )
        typed_zones = _unique(
            (
                *_extract_zone_mentions(rendered, locations),
                *_canonical_zone_links_in_range(link_occurrences, 0, len(rendered)),
            )
        )
        zones = _unique((*locations, *typed_zones))
        action_spans = _extract_action_spans(
            rendered,
            source_step_order=len(steps) + 1,
            link_occurrences=link_occurrences,
            zones=typed_zones,
            maps=maps,
            coordinates=coordinates,
        )
        action = _classify_action(rendered)
        spoken = _spoken_step(
            rendered,
            action,
            _unique(occurrence.display for occurrence in link_occurrences),
            coordinates,
            maps,
        )
        steps.append(
            SourceStep(
                order=len(steps) + 1,
                marker=marker,
                depth=len(marker),
                source_text=rendered,
                spoken_text=spoken,
                action=action,
                linked_entities=links,
                zone_candidates=zones,
                map_numbers=maps,
                grid_coordinates=coordinates,
                items=items,
                key_items=key_items,
                warnings=warnings,
                action_spans=action_spans,
            )
        )

    if not steps:
        page_warnings.append("missing-walkthrough-steps")
    return ParsedObjective(
        site=revision.site,
        page_id=revision.page_id,
        revision_id=revision.revision_id,
        canonical_title=revision.canonical_title,
        kind=kind,
        objective_name=objective_name,
        mission_number=mission_number,
        context_hint=context_hint,
        aliases=_unique(revision.aliases),
        categories=_page_categories(revision.content),
        start_entities=_header_start_entities(revision.content, site_policy),
        steps=tuple(steps),
        warnings=_unique(page_warnings),
        revision_timestamp=revision.revision_timestamp,
        content_sha256=revision.content_sha256,
        source_url=revision.source_url,
        license_id=revision.license_id,
    )

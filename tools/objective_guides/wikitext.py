from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import replace
from pathlib import Path

import mwparserfromhell
from mwparserfromhell.nodes import Template, Wikilink

from .mediawiki import PageRevision
from .model import ParsedObjective, SourceActionSpan, SourceStep


MAX_SPOKEN_STEP = 420

_ZONE_NAMES: tuple[str, ...] | None = None

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
        values = _positional_parameters(template)
        return "key item " + (values[0] if values else "")
    if key in {"item", "itemicon", "itemlink"}:
        values = _positional_parameters(template)
        return values[0] if values else ""
    if key in {"tooltip", "abbr"}:
        return _template_parameter(template, "text", "1") or " ".join(_readable_template_values(template))
    if key in {"color", "fontcolor", "small", "nowrap", "nobr", "verification", "mob", "npc", "zone"}:
        return " ".join(_readable_template_values(template))
    if key == "!":
        return "|"
    if key in {"clear", "toc", "stub", "spoiler", "spoiler2"}:
        return ""

    readable = _readable_template_values(template)
    warnings.append(f"unknown-template:{_clean(template.name)}")
    return " ".join(readable)


def _wikilink_label(link: Wikilink) -> str:
    target = _clean(link.title)
    if not target or ":" in target and target.split(":", 1)[0].casefold() in {
        "category",
        "file",
        "image",
    }:
        return ""
    if len(target) >= 3 and target[2:3] == ":":
        return ""
    display = _strip_code(link.text) if link.text is not None else target
    return display or target


def _render_fragment(
    fragment: str,
) -> tuple[str, tuple[str, ...], tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
    code = mwparserfromhell.parse(fragment)
    warnings: list[str] = []
    links: list[str] = []
    for link in list(code.filter_wikilinks(recursive=True)):
        label = _wikilink_label(link)
        if label:
            links.append(label)
            code.replace(link, label)
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
        code.replace(template, _render_template(template, warnings))

    rendered = _clean(code.strip_code(normalize=True, collapse=True))
    rendered = re.sub(r"(?<=[A-Za-z0-9])(\?{3})", r" \1", rendered)
    rendered = re.sub(r"(\?{3})(?=[A-Za-z0-9])", r"\1 ", rendered)
    rendered = re.sub(r"\s+([,.;:!?])", r"\1", rendered)
    return (
        rendered,
        _unique(links),
        _unique(locations),
        _unique((*map_labels, *_extract_map_numbers(rendered))),
        _unique(warnings),
    )


def _extract_coordinates(value: str) -> tuple[str, ...]:
    return _unique(match.group(1).upper() for match in re.finditer(r"(?<![A-Z0-9])([A-P]-\d{1,2})(?!\d)", value, re.IGNORECASE))


def _extract_map_numbers(value: str) -> tuple[str, ...]:
    return _unique(match.group(1) for match in re.finditer(r"\bmap\s*(?:number\s*)?([0-9]+|north|south|east|west)\b", value, re.IGNORECASE))


def _extract_marked_links(fragment: str, template_names: str) -> tuple[str, ...]:
    pattern = re.compile(
        rf"\{{\{{\s*(?:{template_names})\b[^}}]*\}}\}}\s*\[\[([^\]|]+)(?:\|[^\]]+)?\]\]",
        re.IGNORECASE,
    )
    return _unique(match.group(1) for match in pattern.finditer(fragment))


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
    r"talk|speak|return to|report to|visit|defeat|defeating|fight|kill|killing|slay|destroy|obtain|receive|collect|"
    r"purchase|go to|head to|travel to|enter|exit|zone into|proceed to|make your way to|"
    r"wait|use|activate|light|open|protect|select|choose|board)\b",
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
    if key in {"defeat", "defeating", "fight", "kill", "killing", "slay", "destroy"}:
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


def _result_item_after(text: str, start: int) -> str:
    match = re.search(
        r"\b(?:obtain|receive|collect)\s+(?:the\s+|an?\s+)?(.+?)(?=\s+by\b|\s+from\b|[.;]|$)",
        text[start:],
        re.IGNORECASE,
    )
    return _trim_target(match.group(1)) if match else ""


def _extract_action_spans(
    text: str,
    *,
    source_step_order: int,
    links: tuple[str, ...],
    zones: tuple[str, ...],
    maps: tuple[str, ...],
    coordinates: tuple[str, ...],
    marked_items: tuple[str, ...],
    key_items: tuple[str, ...],
) -> tuple[SourceActionSpan, ...]:
    reversed_chain = re.search(
        r"\b(?:obtain|receive|collect)\s+(?:the\s+|an?\s+)?(?P<item>.+?)\s+by\s+"
        r"(?:defeating|killing|slaying)\s+(?:the\s+)?(?P<enemy>.+?)(?=\s+in\b|\s+at\b|[.;]|$)",
        text,
        re.IGNORECASE,
    )
    if reversed_chain:
        item = _trim_target(reversed_chain.group("item"))
        enemy = _trim_target(reversed_chain.group("enemy"))
        return (
            SourceActionSpan(
                source_step_order=source_step_order,
                order=1,
                text_start=reversed_chain.start(),
                text_end=reversed_chain.end(),
                supporting_clause=_clean(reversed_chain.group(0)),
                action="fight",
                verb="defeat",
                relationship="defeat-to-obtain",
                target=enemy,
                target_kind="enemy",
                enemy_mentions=(enemy,) if enemy else (),
                item_mentions=(item,) if item else (),
                zone_mentions=zones,
                temporal_zone_variant="past" if any(zone.endswith(" [S]") for zone in zones) else "",
                map_numbers=maps,
                grid_coordinates=coordinates,
                result_items=(item,) if item else (),
                result_relation="obtain-from",
            ),
        )

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
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        clause = _clean(text[match.start() : end]).strip(" ,")
        remainder = text[match.end() :]
        target = ""
        target_kind = ""
        item_mentions: tuple[str, ...] = ()
        npc_mentions: tuple[str, ...] = ()
        object_mentions: tuple[str, ...] = ()
        enemy_mentions: tuple[str, ...] = ()
        transport_mentions: tuple[str, ...] = ()

        if action == "trade":
            trade = re.match(
                r"\s+(?:the\s+|an?\s+)?(.+?)\s+to\s+(?:the\s+)?(.+?)(?=,?\s+then\b|[.;]|$)",
                remainder,
                re.IGNORECASE,
            )
            if trade:
                item = _trim_target(trade.group(1))
                target = _trim_target(trade.group(2))
                item_mentions = (item,) if item else ()
                npc_mentions = (target,) if target else ()
                target_kind = "npc"
        elif action == "talk":
            if verb.casefold() in {"return to", "report to", "visit"}:
                talked = re.match(
                    r"\s+(?:the\s+)?(.+?)(?=\s+(?:at|in|for)\b|\s*\(|[.;,]|$)",
                    remainder,
                    re.IGNORECASE,
                )
            else:
                talked = re.match(
                    r"\s+(?:to|with)\s+(?:the\s+)?(.+?)(?=\s+(?:at|in|for)\b|\s*\(|[.;,]|$)",
                    remainder,
                    re.IGNORECASE,
                )
            target = _trim_target(talked.group(1)) if talked else ""
            if target.casefold() in {"him", "her", "them", "it"}:
                target_kind = "role"
            else:
                target_kind = "npc" if target else ""
                npc_mentions = (target,) if target else ()
        elif action == "fight":
            fought = re.match(
                r"\s+(?:the\s+)?(.+?)(?=\s+to\s+(?:obtain|receive|collect)\b|\s+(?:in|at|for)\b|"
                r"\s+and\s+(?:re-examine|examine|touch|click)\b|[.;,]|$)",
                remainder,
                re.IGNORECASE,
            )
            target = _trim_target(fought.group(1)) if fought else ""
            target_kind = "enemy" if target else ""
            enemy_mentions = (target,) if target else ()
        elif action == "examine":
            examined = re.match(
                r"\s+(?:the\s+)?(.+?)(?=\s+to\s+(?:obtain|receive|collect|enter)\b|"
                r"\s+again\b|\s+(?:in|at)\b|[.;,]|$)",
                remainder,
                re.IGNORECASE,
            )
            raw_target = examined.group(1) if examined else ""
            if "???" in raw_target:
                target, target_kind = "???", "question-mark"
            else:
                target = _trim_target(raw_target)
                target = re.sub(r"^sparkling\s+", "", target, flags=re.IGNORECASE)
                target_kind = "object" if target else ""
            object_mentions = (target,) if target else ()
        elif action == "obtain":
            obtained = re.match(
                r"\s+(?:the\s+|an?\s+)?(.+?)(?=\s+by\b|\s+from\b|\s+in\b|[.;]|$)",
                remainder,
                re.IGNORECASE,
            )
            target = _trim_target(obtained.group(1)) if obtained else ""
            target_kind = "item" if target else ""
            item_mentions = (target,) if target else ()
        elif action == "travel":
            target = next((zone for zone in zones if zone.casefold() in text[match.start() :].casefold() or zone.endswith(" [S]")), "")
            target_kind = "zone" if target else ("transport" if relationship == "board-transport" else "")
            if relationship == "board-transport":
                boarded = re.match(r"\s+(?:the\s+)?(.+?)(?=[.;,]|$)", remainder, re.IGNORECASE)
                target = _trim_target(boarded.group(1)) if boarded else target
                transport_mentions = (target,) if target else ()
            elif relationship == "enter-through" and not target:
                entered = re.match(r"\s+(?:the\s+)?(.+?)(?=[.;,]|$)", remainder, re.IGNORECASE)
                target = _trim_target(entered.group(1)) if entered else ""
                target_kind = "entrance" if target else ""
        elif action == "protect":
            protected = re.match(r"\s+(?:the\s+)?(.+?)(?=[.;]|$)", remainder, re.IGNORECASE)
            target = _trim_target(protected.group(1)) if protected else ""
            target_kind = "role" if target else ""
        elif action == "warning":
            target = key_items[0] if key_items else ""
            target_kind = "key-item" if target else "state"
            item_mentions = key_items
            clause = _clean(warning_match.group(0)) if warning_match else clause
        elif action in {"use", "select"}:
            used = re.match(r"\s+(?:the\s+)?(.+?)(?=\s+(?:in|at)\b|[.;,]|$)", remainder, re.IGNORECASE)
            target = _trim_target(used.group(1)) if used else ""
            target_kind = "menu-choice" if action == "select" else "object"
            object_mentions = (target,) if target and action == "use" else ()

        result_item = _result_item_after(text, match.end()) if action in {"fight", "examine"} else ""
        if result_item:
            relationship = "defeat-to-obtain" if action == "fight" else "examine-to-obtain"
        item_mentions = _unique((*item_mentions, *marked_items, *key_items, *((result_item,) if result_item else ())))
        spans.append(
            SourceActionSpan(
                source_step_order=source_step_order,
                order=len(spans) + 1,
                text_start=match.start(),
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
                transport_mentions=transport_mentions,
                zone_mentions=zones,
                temporal_zone_variant="past" if any(zone.endswith(" [S]") for zone in zones) else "",
                map_numbers=maps,
                grid_coordinates=coordinates,
                result_items=(result_item,) if result_item else (),
                result_relation="obtain-from" if result_item else "",
            )
        )

    obtain_indexes = [index for index, span in enumerate(spans) if span.action == "obtain"]
    if len(spans) == 2 and obtain_indexes == [1] and spans[0].action in {"fight", "examine"}:
        spans.pop()
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


def _header_start_entities(content: str) -> tuple[str, ...]:
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
                    label = _wikilink_label(link)
                    if label:
                        entities.append(label)
                return _unique(entities)
    return ()


def parse_objective_page(revision: PageRevision) -> ParsedObjective:
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
        rendered, links, locations, maps, warnings = _render_fragment(fragment)
        if not rendered:
            continue
        coordinates = _extract_coordinates(rendered)
        key_items = _extract_marked_links(fragment, r"KI|KeyItem|KeyItems")
        items = _extract_marked_links(fragment, r"Item|ItemIcon|ItemLink")
        typed_zones = _extract_zone_mentions(rendered, locations)
        zones = _unique((*locations, *typed_zones))
        action_spans = _extract_action_spans(
            rendered,
            source_step_order=len(steps) + 1,
            links=links,
            zones=typed_zones,
            maps=maps,
            coordinates=coordinates,
            marked_items=items,
            key_items=key_items,
        )
        action = _classify_action(rendered)
        spoken = _spoken_step(rendered, action, links, coordinates, maps)
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
        start_entities=_header_start_entities(revision.content),
        steps=tuple(steps),
        warnings=_unique(page_warnings),
        revision_timestamp=revision.revision_timestamp,
        content_sha256=revision.content_sha256,
        source_url=revision.source_url,
        license_id=revision.license_id,
    )

from __future__ import annotations

import re
from collections.abc import Iterable

import mwparserfromhell
from mwparserfromhell.nodes import Template, Wikilink

from .mediawiki import PageRevision
from .model import ParsedObjective, SourceStep


MAX_SPOKEN_STEP = 420


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
            break
        result.append(line)
    return tuple(result)


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
        if key == "questheader":
            return "quest", revision.canonical_title, "", "", tuple(warnings)
        if key == "quest":
            return "quest", revision.canonical_title, "", "", tuple(warnings)
    raise WikitextError(f"{revision.site} page {revision.canonical_title!r} has no supported mission or quest header.")


def parse_objective_page(revision: PageRevision) -> ParsedObjective:
    kind, objective_name, mission_number, context_hint, header_warnings = _header_details(revision)
    steps: list[SourceStep] = []
    page_warnings = list(header_warnings)
    for line in _walkthrough_lines(revision.content):
        candidate = line.lstrip()
        if candidate.startswith("|") and len(candidate) > 1 and candidate[1] in "#*":
            candidate = candidate[1:].lstrip()
        match = re.match(r"^([#*]+)\s*(.*)$", candidate)
        if not match:
            continue
        marker, fragment = match.groups()
        if not fragment.strip():
            continue
        rendered, links, locations, maps, warnings = _render_fragment(fragment)
        if not rendered:
            continue
        coordinates = _extract_coordinates(rendered)
        key_items = _extract_marked_links(fragment, r"KI|KeyItem|KeyItems")
        items = _extract_marked_links(fragment, r"Item|ItemIcon|ItemLink")
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
                zone_candidates=locations,
                map_numbers=maps,
                grid_coordinates=coordinates,
                items=items,
                key_items=key_items,
                warnings=warnings,
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
        steps=tuple(steps),
        warnings=_unique(page_warnings),
    )

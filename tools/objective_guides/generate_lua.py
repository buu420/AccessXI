from __future__ import annotations

import json
import os
import re
import unicodedata
import urllib.parse
from collections import Counter, defaultdict
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

from .matching import MatchingReport, match_objective_pages
from .model import NativeObjective, ParsedObjective, SourceStep
from .reconcile import ReconciledObjective, reconcile_objectives


_SITE_LICENSE_IDS = {
    "bg": "CC-BY-NC-SA-3.0",
    "ffxiclopedia": "CC-BY-SA-3.0",
}

_SITE_LICENSE_LABELS = {
    "bg": "CC BY-NC-SA 3.0",
    "ffxiclopedia": "CC BY-SA 3.0",
}

_SITE_LABELS = {
    "bg": "BG Wiki",
    "ffxiclopedia": "FFXIclopedia",
}

_COVERAGE_STATUSES = (
    "guide",
    "verified-navigation",
    "automatic-stage",
    "source-missing",
    "ambiguous-match",
    "source-conflict",
)


class GenerationError(ValueError):
    """Raised when guide inputs cannot be published without ambiguity."""


def lua_quote(value: object) -> str:
    """Return a deterministic Lua 5.1 double-quoted string literal."""

    text = str(value if value is not None else "")
    text = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )
    return f'"{text}"'


def _module_token(value: object) -> str:
    normalized = unicodedata.normalize("NFKD", str(value or ""))
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii").casefold()
    ascii_value = ascii_value.replace("'", "")
    return re.sub(r"[^a-z0-9]+", "_", ascii_value).strip("_")


def source_module_name(site: str, kind: str, context: str) -> str:
    site_token = _module_token(site)
    kind_token = _module_token(kind)
    context_token = _module_token(context)
    if not site_token or not kind_token or not context_token:
        raise GenerationError("A source module name requires site, kind, and context.")
    return f"mission_quest_{site_token}_{kind_token}_{context_token}"


def _reconcile_module_name(kind: str, context: str) -> str:
    kind_token = _module_token(kind)
    context_token = _module_token(context)
    if not kind_token or not context_token:
        raise GenerationError("A reconciliation module name requires kind and context.")
    return f"mission_quest_reconcile_{kind_token}_{context_token}"


def _lua_array(values: Iterable[object]) -> str:
    return "{ " + ", ".join(lua_quote(value) for value in values) + " }"


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if not normalized.endswith("\n"):
        normalized += "\n"
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(normalized, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def _write_json(path: Path, value: object) -> None:
    _write_text(path, json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def _source_url(page: ParsedObjective) -> str:
    if page.source_url:
        return page.source_url
    title = urllib.parse.quote(page.canonical_title.replace(" ", "_"), safe="()_'!,-")
    if page.site == "bg":
        return f"https://www.bg-wiki.com/ffxi/{title}"
    if page.site == "ffxiclopedia":
        return f"https://ffxiclopedia.fandom.com/wiki/{title}"
    raise GenerationError(f"Unsupported guide source site: {page.site!r}")


def _license_id(page: ParsedObjective) -> str:
    declared = page.license_id or _SITE_LICENSE_IDS.get(page.site, "")
    if not declared:
        raise GenerationError(f"No license is declared for guide source site {page.site!r}.")
    expected = _SITE_LICENSE_IDS.get(page.site)
    if expected is not None and declared != expected:
        raise GenerationError(
            f"Guide source {page.site!r} declared {declared!r}, expected {expected!r}."
        )
    return declared


def _step_lua(step: SourceStep, indent: str = "      ") -> list[str]:
    inner = indent + "  "
    return [
        indent + "{",
        f"{inner}order = {step.order},",
        f"{inner}marker = {lua_quote(step.marker)},",
        f"{inner}depth = {step.depth},",
        f"{inner}instruction = {lua_quote(step.spoken_text)},",
        f"{inner}action = {lua_quote(step.action)},",
        f"{inner}entities = {_lua_array(step.linked_entities)},",
        f"{inner}zones = {_lua_array(step.zone_candidates)},",
        f"{inner}map_numbers = {_lua_array(step.map_numbers)},",
        f"{inner}grid_coordinates = {_lua_array(step.grid_coordinates)},",
        f"{inner}items = {_lua_array(step.items)},",
        f"{inner}key_items = {_lua_array(step.key_items)},",
        f"{inner}warnings = {_lua_array(step.warnings)},",
        indent + "},",
    ]


def _source_module_text(
    site: str,
    entries: Iterable[tuple[NativeObjective, ParsedObjective]],
) -> str:
    try:
        label = _SITE_LABELS[site]
        license_label = _SITE_LICENSE_LABELS[site]
    except KeyError as error:
        raise GenerationError(f"Unsupported guide source site: {site!r}") from error

    lines = [
        "-- Generated by tools/objective_guides. Do not edit by hand.",
        f"-- Adapted {label} guidance. {license_label}.",
        "-- Each entry records the exact source page and revision used.",
        "return {",
    ]
    for native, page in sorted(entries, key=lambda item: item[0].key):
        _license_id(page)
        lines.extend(
            [
                f"  [{lua_quote(native.key)}] = {{",
                f"    objective_name = {lua_quote(page.objective_name)},",
                "    page = {",
                f"      title = {lua_quote(page.canonical_title)},",
                f"      page_id = {page.page_id},",
                f"      revision_id = {page.revision_id},",
                f"      revision_timestamp = {lua_quote(page.revision_timestamp)},",
                f"      content_sha256 = {lua_quote(page.content_sha256)},",
                f"      source_url = {lua_quote(_source_url(page))},",
                f"      license = {lua_quote(_license_id(page))},",
                "    },",
                "    steps = {",
            ]
        )
        for step in page.steps:
            lines.extend(_step_lua(step))
        lines.extend(
            [
                "    },",
                f"    warnings = {_lua_array(page.warnings)},",
                "  },",
            ]
        )
    lines.append("}")
    return "\n".join(lines) + "\n"


def _reconcile_module_text(entries: Iterable[tuple[NativeObjective, ReconciledObjective]]) -> str:
    lines = [
        "-- Generated AccessXI reconciliation facts. Do not edit by hand.",
        "-- No source walkthrough prose is combined in this module.",
        "return {",
    ]
    for native, objective in sorted(entries, key=lambda item: item[0].key):
        lines.extend(
            [
                f"  [{lua_quote(native.key)}] = {{",
                f"    dynamic_candidate_comparison = {lua_quote(objective.dynamic_candidate_comparison)},",
                f"    dynamic_candidate_grid = {_lua_array(objective.dynamic_candidate_grid)},",
                "    selected_candidate_grid = nil,",
                "    steps = {",
            ]
        )
        for step in objective.steps:
            lines.extend(
                [
                    "      {",
                    f"        stable_step_id = {lua_quote(step.stable_step_id)},",
                    f"        order = {step.order},",
                    f"        source_orders = {{ {step.source_orders[0]}, {step.source_orders[1]} }},",
                    f"        comparison = {lua_quote(step.comparison)},",
                    f"        agreed_fields = {_lua_array(step.agreed_fields)},",
                    f"        conflicting_fields = {_lua_array(step.conflicting_fields)},",
                    f"        action = {lua_quote(step.action)},",
                    f"        entities = {_lua_array(step.entities)},",
                    f"        zones = {_lua_array(step.zones)},",
                    f"        grid_coordinates = {_lua_array(step.grid_coordinates)},",
                    "        route_ready = false,",
                    "      },",
                ]
            )
        lines.extend(["    },", "  },"])
    lines.append("}")
    return "\n".join(lines) + "\n"


def _matches_by_native(
    native_rows: tuple[NativeObjective, ...],
    pages: tuple[ParsedObjective, ...],
) -> tuple[dict[str, ParsedObjective], set[str], MatchingReport]:
    report = match_objective_pages(native_rows, pages)
    page_by_id = {page.page_id: page for page in pages}
    grouped: dict[str, list[ParsedObjective]] = defaultdict(list)
    for match in report.matches:
        page = page_by_id.get(match.page_id)
        if page is None:
            raise GenerationError(f"Matched source page {match.page_id} disappeared during generation.")
        grouped[match.native_key].append(page)

    ambiguous_keys = {
        native_key
        for candidates in report.ambiguous_pages.values()
        for native_key in candidates
    }
    unique: dict[str, ParsedObjective] = {}
    for native_key, candidates in grouped.items():
        if len(candidates) == 1:
            unique[native_key] = candidates[0]
        else:
            ambiguous_keys.add(native_key)
    return unique, ambiguous_keys, report


def _apply_reviewed_page_matches(
    native_by_key: Mapping[str, NativeObjective],
    pages: tuple[ParsedObjective, ...],
    source_maps: dict[str, dict[str, ParsedObjective]],
    reviewed_overrides: Mapping[str, Any] | None,
) -> None:
    if not reviewed_overrides:
        return
    raw_matches = reviewed_overrides.get("page_matches", {})
    if not isinstance(raw_matches, Mapping):
        raise GenerationError("Reviewed page_matches must be an object.")
    page_lookup = {(page.site, page.page_id): page for page in pages}
    for native_key, per_site in raw_matches.items():
        native = native_by_key.get(str(native_key))
        if native is None:
            raise GenerationError(f"Reviewed override names unknown native key {native_key!r}.")
        if not isinstance(per_site, Mapping):
            raise GenerationError(f"Reviewed matches for {native_key!r} must be an object.")
        for site, raw_identity in per_site.items():
            if not isinstance(raw_identity, Mapping) or "page_id" not in raw_identity:
                raise GenerationError(f"Reviewed {site} match for {native_key!r} lacks page_id.")
            identity = (str(site), int(raw_identity["page_id"]))
            page = page_lookup.get(identity)
            if page is None:
                raise GenerationError(
                    f"Reviewed match {identity[0]} page {identity[1]} for {native_key!r} is absent."
                )
            if page.kind != native.kind:
                raise GenerationError(f"Reviewed page {identity!r} has the wrong objective kind.")
            source_map = source_maps.setdefault(identity[0], {})
            for other_key, other_page in tuple(source_map.items()):
                if other_page.page_id == identity[1] and other_key != native_key:
                    raise GenerationError(
                        f"Reviewed page {identity!r} is already assigned to {other_key!r}."
                    )
            source_map[str(native_key)] = page


def _has_material_conflict(reconciled: ReconciledObjective) -> bool:
    return reconciled.dynamic_candidate_comparison == "conflict" or any(
        step.comparison == "conflict" for step in reconciled.steps
    )


def _native_manifest_row(native: NativeObjective) -> dict[str, Any]:
    return {
        "key": native.key,
        "kind": native.kind,
        "context": native.context,
        "native_id": native.native_id,
        "progress_id": native.progress_id,
        "title": native.title,
        "details": list(native.details),
        "source_dat": native.source_dat,
        "record_offset": native.record_offset,
    }


def _source_snapshot_page(page: ParsedObjective) -> dict[str, Any]:
    return {
        "site": page.site,
        "page_id": page.page_id,
        "revision_id": page.revision_id,
        "revision_timestamp": page.revision_timestamp,
        "canonical_title": page.canonical_title,
        "objective_name": page.objective_name,
        "kind": page.kind,
        "aliases": list(page.aliases),
        "content_sha256": page.content_sha256,
        "source_url": _source_url(page),
        "license": _license_id(page),
    }


def _index_text(
    natives: tuple[NativeObjective, ...],
    coverage: Mapping[str, Mapping[str, Any]],
) -> str:
    lines = [
        "-- Generated objective guide index. Do not edit by hand.",
        "-- Every valid native objective appears exactly once.",
        "return {",
    ]
    for native in natives:
        record = coverage[native.key]
        modules = record["source_modules"]
        lines.extend(
            [
                f"  [{lua_quote(native.key)}] = {{",
                f"    kind = {lua_quote(native.kind)},",
                f"    context = {lua_quote(native.context)},",
                f"    native_id = {native.native_id},",
                f"    progress_id = {native.progress_id if native.progress_id is not None else 'nil'},",
                f"    title = {lua_quote(native.title)},",
                f"    status = {lua_quote(record['status'])},",
                "    source_modules = {",
            ]
        )
        for site in sorted(modules):
            lines.append(f"      [{lua_quote(site)}] = {lua_quote(modules[site])},")
        lines.extend(
            [
                "    },",
                f"    reconcile_module = {lua_quote(record['reconcile_module']) if record['reconcile_module'] else 'nil'},",
                "  },",
            ]
        )
    lines.append("}")
    return "\n".join(lines) + "\n"


def _coverage_markdown(counts: Mapping[str, Any], pages: tuple[ParsedObjective, ...]) -> str:
    lines = [
        "# Mission and quest guide coverage",
        "",
        "This file is generated from the installed native FFXI objective tables and revisioned guide snapshots.",
        "A guide status does not establish a verified walking route.",
        "",
        f"- Valid native objectives: {counts['valid_native']}",
        f"- Source pages in snapshot: {len(pages)}",
    ]
    for status in _COVERAGE_STATUSES:
        lines.append(f"- {status}: {counts['by_status'].get(status, 0)}")
    lines.extend(
        [
            f"- Dual-source matches: {counts['dual_source']}",
            f"- Guide-only objectives: {counts['guide_only']}",
            f"- Verified navigation objectives: {counts['verified_navigation']}",
            f"- Automatic-stage objectives: {counts['automatic_stage']}",
            "",
        ]
    )
    return "\n".join(lines)


def build_guide_artifacts(
    native_objectives: Iterable[NativeObjective],
    parsed_pages: Iterable[ParsedObjective],
    *,
    module_root: Path,
    data_root: Path,
    reviewed_overrides: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Build deterministic, license-separated runtime and coverage artifacts."""

    natives = tuple(sorted(native_objectives, key=lambda row: row.key))
    pages = tuple(sorted(parsed_pages, key=lambda page: (page.site, page.page_id, page.revision_id)))
    if len({native.key for native in natives}) != len(natives):
        raise GenerationError("Native objective keys must be unique before guide generation.")
    if len({(page.site, page.page_id) for page in pages}) != len(pages):
        raise GenerationError("A source snapshot contains duplicate site/page identities.")
    for page in pages:
        _license_id(page)

    native_by_key = {native.key: native for native in natives}
    source_maps: dict[str, dict[str, ParsedObjective]] = {}
    ambiguous_by_site: dict[str, set[str]] = {}
    reports: dict[str, MatchingReport] = {}
    for site in sorted({page.site for page in pages}.union(_SITE_LICENSE_IDS)):
        site_pages = tuple(page for page in pages if page.site == site)
        source_map, ambiguous, report = _matches_by_native(natives, site_pages)
        source_maps[site] = source_map
        ambiguous_by_site[site] = ambiguous
        reports[site] = report
    _apply_reviewed_page_matches(native_by_key, pages, source_maps, reviewed_overrides)

    source_groups: dict[tuple[str, str, str], list[tuple[NativeObjective, ParsedObjective]]] = defaultdict(list)
    reconcile_groups: dict[tuple[str, str], list[tuple[NativeObjective, ReconciledObjective]]] = defaultdict(list)
    coverage_objectives: dict[str, dict[str, Any]] = {}

    for native in natives:
        bg = source_maps.get("bg", {}).get(native.key)
        ffxiclopedia = source_maps.get("ffxiclopedia", {}).get(native.key)
        matched = {site: page for site, page in (("bg", bg), ("ffxiclopedia", ffxiclopedia)) if page is not None}
        for site, page in matched.items():
            source_groups[(site, native.kind, native.context)].append((native, page))

        reconciled: ReconciledObjective | None = None
        if matched:
            reconciled = reconcile_objectives(native.key, bg, ffxiclopedia)
            reconcile_groups[(native.kind, native.context)].append((native, reconciled))

        has_steps = any(page.steps for page in matched.values())
        ambiguous_sites = sorted(
            site for site, keys in ambiguous_by_site.items() if native.key in keys and site not in matched
        )
        if reconciled is not None and _has_material_conflict(reconciled):
            status = "source-conflict"
        elif has_steps:
            status = "guide"
        elif ambiguous_sites:
            status = "ambiguous-match"
        else:
            status = "source-missing"

        source_modules = {
            site: source_module_name(site, native.kind, native.context)
            for site in sorted(matched)
        }
        reconcile_module = _reconcile_module_name(native.kind, native.context) if reconciled else ""
        coverage_objectives[native.key] = {
            "status": status,
            "title": native.title,
            "kind": native.kind,
            "context": native.context,
            "source_pages": {
                site: {
                    "page_id": page.page_id,
                    "revision_id": page.revision_id,
                    "title": page.canonical_title,
                    "source_url": _source_url(page),
                }
                for site, page in sorted(matched.items())
            },
            "source_modules": source_modules,
            "reconcile_module": reconcile_module,
            "ambiguous_sites": ambiguous_sites,
            "dynamic_candidate_comparison": (
                reconciled.dynamic_candidate_comparison if reconciled else "none"
            ),
            "route_ready": False,
            "automatic_stage": False,
        }

    module_root = Path(module_root)
    data_root = Path(data_root)
    module_root.mkdir(parents=True, exist_ok=True)
    data_root.mkdir(parents=True, exist_ok=True)
    generated_module_paths: set[Path] = set()
    for (site, kind, context), entries in sorted(source_groups.items()):
        path = module_root / f"{source_module_name(site, kind, context)}.lua"
        _write_text(path, _source_module_text(site, entries))
        generated_module_paths.add(path)
    for (kind, context), entries in sorted(reconcile_groups.items()):
        path = module_root / f"{_reconcile_module_name(kind, context)}.lua"
        _write_text(path, _reconcile_module_text(entries))
        generated_module_paths.add(path)

    index_path = module_root / "mission_quest_guide_index.lua"
    _write_text(index_path, _index_text(natives, coverage_objectives))
    generated_module_paths.add(index_path)

    generated_patterns = (
        "mission_quest_bg_*.lua",
        "mission_quest_ffxiclopedia_*.lua",
        "mission_quest_reconcile_*.lua",
    )
    for pattern in generated_patterns:
        for stale_path in module_root.glob(pattern):
            if stale_path not in generated_module_paths:
                stale_path.unlink()

    status_counts = Counter(record["status"] for record in coverage_objectives.values())
    by_status = {status: status_counts.get(status, 0) for status in _COVERAGE_STATUSES}
    counts = {
        "valid_native": len(natives),
        "by_status": by_status,
        "dual_source": sum(1 for record in coverage_objectives.values() if len(record["source_pages"]) == 2),
        "guide_only": sum(1 for record in coverage_objectives.values() if record["status"] == "guide"),
        "verified_navigation": 0,
        "automatic_stage": 0,
    }

    native_manifest = {"schema_version": 1, "objectives": [_native_manifest_row(native) for native in natives]}
    source_snapshot = {
        "schema_version": 1,
        "pages": [_source_snapshot_page(page) for page in pages],
    }
    coverage = {
        "schema_version": 1,
        "counts": counts,
        "objectives": coverage_objectives,
        "matching": {
            site: {
                "matched": len(report.matches),
                "ambiguous_pages": {str(key): list(value) for key, value in sorted(report.ambiguous_pages.items())},
                "unmatched_pages": list(report.unmatched_pages),
                "suggestions": {str(key): list(value) for key, value in sorted(report.suggestions.items())},
            }
            for site, report in sorted(reports.items())
        },
    }
    _write_json(data_root / "native-manifest.json", native_manifest)
    _write_json(data_root / "source-snapshot.json", source_snapshot)
    _write_json(data_root / "coverage.json", coverage)
    _write_text(data_root / "coverage.md", _coverage_markdown(counts, pages))

    return {
        "counts": counts,
        "module_files": sorted(path.name for path in generated_module_paths),
        "data_files": ["coverage.json", "coverage.md", "native-manifest.json", "source-snapshot.json"],
    }

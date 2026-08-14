from __future__ import annotations

import hashlib
import json
import math
import os
import re
import unicodedata
import urllib.parse
from collections import Counter, defaultdict
from collections.abc import Iterable, Mapping
from dataclasses import replace
from pathlib import Path
from typing import Any

from .matching import MatchingReport, match_objective_pages, normalize_title
from .mediawiki import PageRevision
from .objective_destinations import (
    ObjectiveDestinationError,
    resolve_objective_actions,
    resolve_reviewed_objective_destinations,
    task3_route_contract_inputs,
)
from .model import NativeObjective, ParsedObjective, SourceActionSpan, SourceStep
from .reconcile import (
    LegacyDestinationOutcome,
    ReconciledActionClaim,
    ObjectiveActionLedgerRow,
    ObjectiveDestinationCandidate,
    ObjectiveDestinationGroup,
    ObjectiveResolutionReviewItem,
    ReviewedObjectiveDestination,
    ReviewedNavigationTarget,
    ReconciledObjective,
    ReconciledStep,
    reconcile_objectives,
)


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

_SOURCE_AUTHORITY = {
    "primary": "bg",
    "fallback": "ffxiclopedia",
}

_PROGRESSION_REVISION_SCHEMA = 1

_OBJECT_LIKE_TARGET_NAME = re.compile(
    r"\b(?:door|gate|snow|mark|point|switch|lever|device|stone|rock|crystal|altar|"
    r"book|wall|floor|chest|coffer|brazier|ornament|stair|trail|sign|target|machine|"
    r"torch|pool|water|tree)\b",
    re.IGNORECASE,
)

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


def _progression_module_name(kind: str, context: str) -> str:
    kind_token = _module_token(kind)
    context_token = _module_token(context)
    if not kind_token or not context_token:
        raise GenerationError("A progression module name requires kind and context.")
    return f"mission_quest_progression_{kind_token}_{context_token}"


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


def _source_action_span_lua(span: SourceActionSpan, indent: str) -> list[str]:
    inner = indent + "  "
    return [
        indent + "{",
        f"{inner}source_step_order = {span.source_step_order},",
        f"{inner}order = {span.order},",
        f"{inner}text_start = {span.text_start},",
        f"{inner}text_end = {span.text_end},",
        f"{inner}supporting_clause = {lua_quote(span.supporting_clause)},",
        f"{inner}action = {lua_quote(span.action)},",
        f"{inner}verb = {lua_quote(span.verb)},",
        f"{inner}relationship = {lua_quote(span.relationship)},",
        f"{inner}target = {lua_quote(span.target)},",
        f"{inner}target_kind = {lua_quote(span.target_kind)},",
        f"{inner}target_role = {lua_quote(span.target_role)},",
        f"{inner}npc_mentions = {_lua_array(span.npc_mentions)},",
        f"{inner}object_mentions = {_lua_array(span.object_mentions)},",
        f"{inner}enemy_mentions = {_lua_array(span.enemy_mentions)},",
        f"{inner}item_mentions = {_lua_array(span.item_mentions)},",
        f"{inner}key_item_mentions = {_lua_array(span.key_item_mentions)},",
        f"{inner}transport_mentions = {_lua_array(span.transport_mentions)},",
        f"{inner}zone_mentions = {_lua_array(span.zone_mentions)},",
        f"{inner}temporal_zone_variant = {lua_quote(span.temporal_zone_variant)},",
        f"{inner}map_numbers = {_lua_array(span.map_numbers)},",
        f"{inner}grid_coordinates = {_lua_array(span.grid_coordinates)},",
        f"{inner}result_items = {_lua_array(span.result_items)},",
        f"{inner}result_relation = {lua_quote(span.result_relation)},",
        f"{inner}material = {'true' if span.material else 'false'},",
        indent + "},",
    ]


def _step_lua(step: SourceStep, indent: str = "      ") -> list[str]:
    inner = indent + "  "
    lines = [
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
    ]
    lines.append(indent + "},")
    return lines


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


def _reconcile_module_text(
    entries: Iterable[
        tuple[NativeObjective, ReconciledObjective, Mapping[str, str], str, set[str]]
    ],
) -> str:
    lines = [
        "-- Generated AccessXI reconciliation facts. Do not edit by hand.",
        "-- No source walkthrough prose is combined in this module.",
        "return {",
    ]
    for native, objective, automatic_stages, default_step_id, route_steps in sorted(
        entries, key=lambda item: item[0].key
    ):
        lines.extend(
            [
                f"  [{lua_quote(native.key)}] = {{",
                f"    dynamic_candidate_comparison = {lua_quote(objective.dynamic_candidate_comparison)},",
                f"    dynamic_candidate_grid = {_lua_array(objective.dynamic_candidate_grid)},",
                "    selected_candidate_grid = nil,",
                f"    default_step_id = {lua_quote(default_step_id) if default_step_id else 'nil'},",
                "    automatic_stages = {",
            ]
        )
        for stage_key, step_id in sorted(automatic_stages.items()):
            lines.append(f"      [{lua_quote(stage_key)}] = {lua_quote(step_id)},")
        lines.append("    },")
        lines.append("    steps = {")
        for step in objective.steps:
            step_lines = [
                    "      {",
                    f"        stable_step_id = {lua_quote(step.stable_step_id)},",
                    f"        order = {step.order},",
                    f"        source_orders = {{ {step.source_orders[0]}, {step.source_orders[1]} }},",
                    f"        comparison = {lua_quote(step.comparison)},",
                    f"        agreed_fields = {_lua_array(step.agreed_fields)},",
                    f"        conflicting_fields = {_lua_array(step.conflicting_fields)},",
                    f"        action = {lua_quote(step.action)},",
                    f"        entities = {_lua_array(step.entities)},",
                    f"        items = {_lua_array(step.items)},",
                    f"        key_items = {_lua_array(step.key_items)},",
                    f"        zones = {_lua_array(step.zones)},",
                    f"        grid_coordinates = {_lua_array(step.grid_coordinates)},",
                    f"        alignment_score = {step.alignment_score},",
                    f"        alignment_reason = {lua_quote(step.alignment_reason)},",
                    f"        unpaired_reason = {lua_quote(step.unpaired_reason)},",
                    f"        bg_instruction = {lua_quote(step.bg_instruction)},",
                    f"        ffxiclopedia_instruction = {lua_quote(step.ffxiclopedia_instruction)},",
            ]
            step_lines.extend(
                [
                    f"        route_ready = {'true' if step.stable_step_id in route_steps else 'false'},",
                ]
            )
            target = step.navigation_target
            if target is not None:
                step_lines.extend(
                    [
                        "        navigation_target = {",
                        f"          type = {lua_quote(target.target_type)},",
                        "          reference = {",
                        f"            zone = {target.zone},",
                        f"            zone_name = {lua_quote(target.zone_name)},",
                        f"            name = {lua_quote(target.name)},",
                        f"            kind = {lua_quote(target.kind)},",
                        "          },",
                        f"          arrival_instruction = {lua_quote(target.arrival_instruction)},",
                        "        },",
                    ]
                )
            step_lines.append("      },")
            lines.extend(step_lines)
        lines.extend(["    },", "  },"])
    lines.append("}")
    return "\n".join(lines) + "\n"


def _source_step(page: ParsedObjective | None, order: int) -> SourceStep | None:
    if page is None or order <= 0:
        return None
    return next((step for step in page.steps if step.order == order), None)


def _source_span(step: SourceStep | None, order: int) -> SourceActionSpan | None:
    if step is None or order <= 0:
        return None
    return next((span for span in step.action_spans if span.order == order), None)


def _authoritative_value(bg_value: Any, ffxiclopedia_value: Any) -> tuple[Any, str]:
    def present(value: Any) -> bool:
        if isinstance(value, str):
            return bool(value.strip())
        if isinstance(value, (tuple, list, dict, set)):
            return bool(value)
        return value is not None

    if present(bg_value):
        return bg_value, "bg"
    if present(ffxiclopedia_value):
        return ffxiclopedia_value, "ffxiclopedia"
    return bg_value if bg_value is not None else ffxiclopedia_value, ""


def _progression_catalogue_row(candidate: ObjectiveDestinationCandidate) -> dict[str, Any]:
    return {
        "destination_id": candidate.destination_id,
        "zone_id": candidate.zone,
        "zone_name": candidate.zone_name,
        "target_name": candidate.target_name,
        "target_kind": candidate.target_kind,
        "target_key": normalize_title(candidate.target_name),
        "target_point": list(candidate.target_point),
        "raw_identity": candidate.raw_identity,
        "raw_spawn_ids": list(candidate.raw_spawn_ids),
        "cluster_policy_version": candidate.cluster_policy_version,
        "transport_id": candidate.transport_id,
        "battlefield_id": candidate.battlefield_id,
        "metadata_class": candidate.metadata_class,
        "group_id": candidate.group_id,
        "arrival_instruction": candidate.arrival_instruction,
    }


def progression_objective_payload(
    native: NativeObjective,
    reconciled: ReconciledObjective | None,
    source_pages: Mapping[str, ParsedObjective],
    module_name: str,
) -> dict[str, Any]:
    """Build the one canonical payload used for both revision hashing and Lua emission."""

    expected_module = _progression_module_name(native.kind, native.context) if reconciled else ""
    if module_name != expected_module:
        raise GenerationError(
            f"Progression shard mismatch for {native.key!r}: {module_name!r} != {expected_module!r}."
        )
    if reconciled is not None and reconciled.native_key != native.key:
        raise GenerationError(f"Progression native-key mismatch for {native.key!r}.")
    unknown_sites = set(source_pages).difference(_SOURCE_AUTHORITY.values())
    if unknown_sites:
        raise GenerationError(f"Progression sources contain unsupported sites: {sorted(unknown_sites)!r}.")

    revisions = {
        site: page.revision_id
        for site, page in sorted(source_pages.items())
    }
    for site, revision_id in revisions.items():
        if revision_id <= 0:
            raise GenerationError(f"Progression source {site!r} has no revision pin.")

    ledger_by_id = {
        row.action_id: row
        for row in (reconciled.action_resolution_ledger if reconciled is not None else ())
        if row.material
    }
    candidates_by_action: dict[str, list[ObjectiveDestinationCandidate]] = defaultdict(list)
    for candidate in (
        reconciled.objective_destination_candidates if reconciled is not None else ()
    ):
        candidates_by_action[candidate.action_id].append(candidate)

    actions: list[dict[str, Any]] = []
    for step in reconciled.steps if reconciled is not None else ():
        bg_step = _source_step(source_pages.get("bg"), step.source_orders[0])
        ffxi_step = _source_step(source_pages.get("ffxiclopedia"), step.source_orders[1])
        for claim in step.claims:
            if not claim.material:
                continue
            bg_span = _source_span(bg_step, claim.bg_span_order)
            ffxi_span = _source_span(ffxi_step, claim.ffxiclopedia_span_order)
            if bg_span is None and ffxi_span is None:
                raise GenerationError(f"Material action {claim.stable_claim_id!r} has no source span.")
            source_authority = "bg" if bg_span is not None else "ffxiclopedia"

            bg_key_items = tuple(bg_span.key_item_mentions) if bg_span is not None else ()
            ffxi_key_items = tuple(ffxi_span.key_item_mentions) if ffxi_span is not None else ()
            bg_key_set = {value.casefold() for value in bg_key_items}
            ffxi_key_set = {value.casefold() for value in ffxi_key_items}
            source_values = {
                "action": (bg_span.action if bg_span else "", ffxi_span.action if ffxi_span else ""),
                "relationship": (
                    bg_span.relationship if bg_span else "",
                    ffxi_span.relationship if ffxi_span else "",
                ),
                "target": (bg_span.target if bg_span else "", ffxi_span.target if ffxi_span else ""),
                "target_kind": (
                    bg_span.target_kind if bg_span else "",
                    ffxi_span.target_kind if ffxi_span else "",
                ),
                "npcs": (bg_span.npc_mentions if bg_span else (), ffxi_span.npc_mentions if ffxi_span else ()),
                "objects": (
                    bg_span.object_mentions if bg_span else (),
                    ffxi_span.object_mentions if ffxi_span else (),
                ),
                "enemies": (
                    bg_span.enemy_mentions if bg_span else (),
                    ffxi_span.enemy_mentions if ffxi_span else (),
                ),
                "items": (
                    tuple(value for value in (bg_span.item_mentions if bg_span else ()) if value.casefold() not in bg_key_set),
                    tuple(value for value in (ffxi_span.item_mentions if ffxi_span else ()) if value.casefold() not in ffxi_key_set),
                ),
                "key_items": (bg_key_items, ffxi_key_items),
                "transports": (
                    bg_span.transport_mentions if bg_span else (),
                    ffxi_span.transport_mentions if ffxi_span else (),
                ),
                "zones": (
                    bg_span.zone_mentions if bg_span else (),
                    ffxi_span.zone_mentions if ffxi_span else (),
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
                    bg_step.spoken_text if bg_step else "",
                    ffxi_step.spoken_text if ffxi_step else "",
                ),
                "required_count": (
                    bg_span.required_count if bg_span else None,
                    ffxi_span.required_count if ffxi_span else None,
                ),
                "count_mode": (
                    bg_span.count_mode if bg_span else "",
                    ffxi_span.count_mode if ffxi_span else "",
                ),
                "count_explicit": (
                    bg_span.count_explicit if bg_span else None,
                    ffxi_span.count_explicit if ffxi_span else None,
                ),
            }
            selected: dict[str, Any] = {}
            field_sources: dict[str, str] = {}
            for field, (bg_value, ffxi_value) in source_values.items():
                value, source = _authoritative_value(bg_value, ffxi_value)
                if isinstance(value, tuple):
                    value = list(value)
                selected[field] = value
                field_sources[field] = source
            selected["required_count"] = claim.required_count
            selected["count_mode"] = claim.count_mode
            selected["count_explicit"] = claim.count_explicit
            selected["target_key"] = normalize_title(selected["target"])
            field_sources["target_key"] = field_sources["target"]

            ledger = ledger_by_id.get(claim.stable_claim_id)
            source_span_ids = list(ledger.source_action_span_ids) if ledger is not None else []
            catalogue = [
                _progression_catalogue_row(candidate)
                for candidate in sorted(
                    candidates_by_action.get(claim.stable_claim_id, ()),
                    key=lambda row: row.candidate_id,
                )
            ]
            field_sources["catalogue"] = "catalogue" if catalogue else ""
            actions.append(
                {
                    "step_id": step.stable_step_id,
                    "step_order": step.order,
                    "action_id": claim.stable_claim_id,
                    "action_order": claim.order,
                    "order": len(actions) + 1,
                    "action": selected["action"],
                    "relationship": selected["relationship"],
                    "target": selected["target"],
                    "target_key": selected["target_key"],
                    "target_kind": selected["target_kind"],
                    "npcs": selected["npcs"],
                    "objects": selected["objects"],
                    "enemies": selected["enemies"],
                    "items": selected["items"],
                    "key_items": selected["key_items"],
                    "transports": selected["transports"],
                    "zones": selected["zones"],
                    "grid_coordinates": selected["grid_coordinates"],
                    "result_items": selected["result_items"],
                    "result_relation": selected["result_relation"],
                    "instruction": selected["instruction"],
                    "required_count": selected["required_count"],
                    "count_mode": selected["count_mode"],
                    "count_explicit": selected["count_explicit"],
                    "material": True,
                    "source_authority": source_authority,
                    "field_sources": field_sources,
                    "source_revisions": dict(revisions),
                    "source_action_span_ids": source_span_ids,
                    "catalogue": catalogue,
                }
            )

    action_ids = [row["action_id"] for row in actions]
    if len(action_ids) != len(set(action_ids)):
        raise GenerationError(f"Progression actions for {native.key!r} contain duplicate IDs.")
    if [row["order"] for row in actions] != list(range(1, len(actions) + 1)):
        raise GenerationError(f"Progression actions for {native.key!r} are not contiguous.")

    revision_payload = {
        "progression_schema_version": _PROGRESSION_REVISION_SCHEMA,
        "progression_module": module_name,
        "native_key": native.key,
        "source_authority": dict(_SOURCE_AUTHORITY),
        "progression_actions": actions,
    }
    progression_revision = hashlib.sha256(
        json.dumps(
            revision_payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()
    return {
        "native_key": native.key,
        "progression_schema_version": _PROGRESSION_REVISION_SCHEMA,
        "progression_module": module_name,
        "source_authority": dict(_SOURCE_AUTHORITY),
        "progression_revision": progression_revision,
        "progression_actions": actions,
    }


def _lua_value(value: Any, indent: str = "") -> str:
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return lua_quote(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return format(value, ".17g")
    if isinstance(value, Mapping):
        if not value:
            return "{}"
        rows = ["{"]
        for key, item in value.items():
            key_text = str(key)
            lua_key = key_text if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key_text) else f"[{lua_quote(key_text)}]"
            rows.append(f"{indent}  {lua_key} = {_lua_value(item, indent + '  ')},")
        rows.append(indent + "}")
        return "\n".join(rows)
    if isinstance(value, (list, tuple)):
        if not value:
            return "{}"
        rows = ["{"]
        rows.extend(f"{indent}  {_lua_value(item, indent + '  ')}," for item in value)
        rows.append(indent + "}")
        return "\n".join(rows)
    raise GenerationError(f"Unsupported progression Lua value: {type(value).__name__}.")


def _progression_module_text(module_name: str, payloads: Iterable[Mapping[str, Any]]) -> str:
    objectives = {
        str(payload["native_key"]): payload
        for payload in sorted(payloads, key=lambda row: str(row["native_key"]))
    }
    module = {
        "schema_version": _PROGRESSION_REVISION_SCHEMA,
        "module_name": module_name,
        "source_authority": dict(_SOURCE_AUTHORITY),
        "objectives": objectives,
    }
    return "\n".join(
        (
            "-- Generated AccessXI compact progression facts. Do not edit by hand.",
            "-- Full source spans and review evidence remain in data/mission-quest-guides JSON.",
            "return " + _lua_value(module),
            "",
        )
    )


def _reconciled_claim_lua(claim: ReconciledActionClaim) -> list[str]:
    authoritative: dict[str, list[str]] = {}
    fields = {candidate.field for candidate in claim.candidates}
    for field in fields:
        field_rows = [candidate for candidate in claim.candidates if candidate.field == field]
        primary_rows = [candidate for candidate in field_rows if "bg" in candidate.sources]
        selected_rows = primary_rows or field_rows
        authoritative[field] = list(dict.fromkeys(candidate.value for candidate in selected_rows))
    lines = [
        "          {",
        f"            stable_claim_id = {lua_quote(claim.stable_claim_id)},",
        f"            order = {claim.order},",
        f"            action = {lua_quote(claim.action)},",
        f"            relationship = {lua_quote(claim.relationship)},",
        f"            target = {lua_quote(claim.target)},",
        f"            target_kind = {lua_quote(claim.target_kind)},",
        f"            comparison = {lua_quote(claim.comparison)},",
        f"            alignment_score = {claim.alignment_score},",
        f"            alignment_reason = {lua_quote(claim.alignment_reason)},",
        f"            unpaired_reason = {lua_quote(claim.unpaired_reason)},",
        f"            bg_span_order = {claim.bg_span_order},",
        f"            ffxiclopedia_span_order = {claim.ffxiclopedia_span_order},",
        f"            material = {'true' if claim.material else 'false'},",
        "            matcher = {",
        f"              authority = {lua_quote('bg' if any('bg' in row.sources for row in claim.candidates) else 'ffxiclopedia')},",
        f"              action = {lua_quote(claim.action)},",
        f"              relationship = {lua_quote(claim.relationship)},",
        f"              target = {lua_quote(claim.target)},",
        f"              target_kind = {lua_quote(claim.target_kind)},",
        f"              zones = {_lua_array(authoritative.get('zone', ()))},",
        f"              items = {_lua_array(authoritative.get('item', ()))},",
        f"              key_items = {_lua_array(authoritative.get('key-item', ()))},",
        f"              result_items = {_lua_array(authoritative.get('result-item', ()))},",
        f"              result_relation = {lua_quote(claim.result_relation)},",
        "            },",
        "            candidates = {",
    ]
    for candidate in claim.candidates:
        lines.extend(
            [
                "              {",
                f"                field = {lua_quote(candidate.field)},",
                f"                value = {lua_quote(candidate.value)},",
                f"                comparison = {lua_quote(candidate.comparison)},",
                f"                sources = {_lua_array(candidate.sources)},",
                "              },",
            ]
        )
    lines.extend(["            },", "          },"])
    return lines


def _objective_action_ledger_lua(row: ObjectiveActionLedgerRow) -> list[str]:
    return [
        "      {",
        f"        action_id = {lua_quote(row.action_id)},",
        f"        source_action_span_ids = {_lua_array(row.source_action_span_ids)},",
        f"        action = {lua_quote(row.action)},",
        f"        status = {lua_quote(row.status)},",
        f"        reason = {lua_quote(row.reason)},",
        f"        candidate_ids = {_lua_array(row.candidate_ids)},",
        f"        instruction = {lua_quote(row.instruction)},",
        f"        material = {'true' if row.material else 'false'},",
        "        route_ready = false,",
        "      },",
    ]


def _objective_candidate_lua(candidate: ObjectiveDestinationCandidate) -> list[str]:
    lines = [
        "      {",
        f"        candidate_id = {lua_quote(candidate.candidate_id)},",
        f"        action_id = {lua_quote(candidate.action_id)},",
        f"        source_action_span_ids = {_lua_array(candidate.source_action_span_ids)},",
        f"        source_sites = {_lua_array(candidate.source_sites)},",
        "        source_revisions = {",
    ]
    lines.extend(
        f"          [{lua_quote(site)}] = {revision_id},"
        for site, revision_id in candidate.source_revisions
    )
    lines.extend(
        [
            "        },",
            "        coordinate_support = {",
        ]
    )
    for site, coordinate_kind, value in candidate.coordinate_support:
        lines.extend(
            [
                "          {",
                f"            site = {lua_quote(site)},",
                f"            kind = {lua_quote(coordinate_kind)},",
                f"            value = {lua_quote(value)},",
                "          },",
            ]
        )
    lines.extend(
        [
            "        },",
            f"        coordinate_comparison = {lua_quote(candidate.coordinate_comparison)},",
            f"        action = {lua_quote(candidate.action)},",
            f"        items = {_lua_array(candidate.items)},",
            f"        enemies = {_lua_array(candidate.enemies)},",
            f"        result_relation = {lua_quote(candidate.result_relation)},",
            f"        destination_id = {lua_quote(candidate.destination_id)},",
            f"        zone = {candidate.zone},",
            f"        zone_name = {lua_quote(candidate.zone_name)},",
            f"        target_name = {lua_quote(candidate.target_name)},",
            f"        target_kind = {lua_quote(candidate.target_kind)},",
            "        target_point = { "
            + ", ".join(format(value, ".17g") for value in candidate.target_point)
            + " },",
            f"        raw_identity = {lua_quote(candidate.raw_identity)},",
            f"        raw_spawn_ids = {{ {', '.join(str(value) for value in candidate.raw_spawn_ids)} }},",
            f"        cluster_policy_version = {lua_quote(candidate.cluster_policy_version)},",
            f"        evidence_level = {lua_quote(candidate.evidence_level)},",
            f"        group_id = {lua_quote(candidate.group_id)},",
            f"        metadata_class = {lua_quote(candidate.metadata_class)},",
            f"        transport_id = {lua_quote(candidate.transport_id)},",
            f"        battlefield_id = {lua_quote(candidate.battlefield_id)},",
            f"        label = {lua_quote(candidate.label)},",
            f"        arrival_instruction = {lua_quote(candidate.arrival_instruction)},",
            "        route_ready = false,",
            "      },",
        ]
    )
    return lines


def _objective_group_lua(group: ObjectiveDestinationGroup) -> list[str]:
    return [
        "      {",
        f"        group_id = {lua_quote(group.group_id)},",
        f"        action_id = {lua_quote(group.action_id)},",
        f"        zone = {group.zone},",
        f"        zone_name = {lua_quote(group.zone_name)},",
        f"        candidate_ids = {_lua_array(group.candidate_ids)},",
        f"        evidence_level = {lua_quote(group.evidence_level)},",
        f"        source_action_span_ids = {_lua_array(group.source_action_span_ids)},",
        "        route_ready = false,",
        "      },",
    ]


def _objective_review_item_lua(item: ObjectiveResolutionReviewItem) -> list[str]:
    return [
        "      {",
        f"        review_id = {lua_quote(item.review_id)},",
        f"        action_id = {lua_quote(item.action_id)},",
        f"        target_name = {lua_quote(item.target_name)},",
        f"        zone_name = {lua_quote(item.zone_name)},",
        f"        source_sites = {_lua_array(item.source_sites)},",
        f"        source_action_span_ids = {_lua_array(item.source_action_span_ids)},",
        f"        reason = {lua_quote(item.reason)},",
        "        route_ready = false,",
        "      },",
    ]


def _objective_candidate_review_row(
    native_key: str,
    candidate: ObjectiveDestinationCandidate,
) -> dict[str, Any]:
    return {
        "native_key": native_key,
        "candidate_id": candidate.candidate_id,
        "action_id": candidate.action_id,
        "source_action_span_ids": list(candidate.source_action_span_ids),
        "source_sites": list(candidate.source_sites),
        "source_revisions": dict(candidate.source_revisions),
        "coordinate_support": [
            {"site": site, "kind": coordinate_kind, "value": value}
            for site, coordinate_kind, value in candidate.coordinate_support
        ],
        "coordinate_comparison": candidate.coordinate_comparison,
        "action": candidate.action,
        "items": list(candidate.items),
        "enemies": list(candidate.enemies),
        "result_relation": candidate.result_relation,
        "destination_id": candidate.destination_id,
        "zone": candidate.zone,
        "zone_name": candidate.zone_name,
        "target_name": candidate.target_name,
        "target_kind": candidate.target_kind,
        "target_point": list(candidate.target_point),
        "raw_identity": candidate.raw_identity,
        "raw_spawn_ids": list(candidate.raw_spawn_ids),
        "cluster_policy_version": candidate.cluster_policy_version,
        "evidence_level": candidate.evidence_level,
        "group_id": candidate.group_id,
        "metadata_class": candidate.metadata_class,
        "transport_id": candidate.transport_id,
        "battlefield_id": candidate.battlefield_id,
        "label": candidate.label,
        "arrival_instruction": candidate.arrival_instruction,
        "classification": "catalogue-candidate",
        "route_ready": False,
    }


def _objective_group_review_row(
    native_key: str,
    group: ObjectiveDestinationGroup,
) -> dict[str, Any]:
    return {
        "native_key": native_key,
        "group_id": group.group_id,
        "action_id": group.action_id,
        "zone": group.zone,
        "zone_name": group.zone_name,
        "candidate_ids": list(group.candidate_ids),
        "candidate_count": len(group.candidate_ids),
        "evidence_level": group.evidence_level,
        "source_action_span_ids": list(group.source_action_span_ids),
        "route_ready": False,
    }


def _legacy_destination_outcome_review_row(
    native_key: str,
    outcome: LegacyDestinationOutcome,
) -> dict[str, Any]:
    return {
        "native_key": native_key,
        "legacy_override_id": outcome.legacy_override_id,
        "action_id": outcome.action_id,
        "classification": outcome.classification,
        "reason": outcome.reason,
        "candidate_ids": list(outcome.candidate_ids),
        "candidate_count": len(outcome.candidate_ids),
        "group_ids": list(outcome.group_ids),
        "source_action_span_ids": list(outcome.source_action_span_ids),
        "source_revisions": dict(outcome.source_revisions),
        "legacy_review_metadata": {
            "zone": outcome.zone,
            "zone_name": outcome.zone_name,
            "target_name": outcome.target_name,
            "target_kind": outcome.target_kind,
            "canonical_ingress_edge_id": outcome.canonical_ingress_edge_id,
            "canonical_ingress_from_zone": outcome.canonical_ingress_from_zone,
            "transport_id": outcome.transport_id,
            "route_evidence": outcome.route_evidence,
        },
        "route_ready": False,
    }


def _objective_review_item_row(
    native_key: str,
    item: ObjectiveResolutionReviewItem,
) -> dict[str, Any]:
    return {
        "native_key": native_key,
        "review_id": item.review_id,
        "action_id": item.action_id,
        "target_name": item.target_name,
        "zone_name": item.zone_name,
        "source_sites": list(item.source_sites),
        "source_action_span_ids": list(item.source_action_span_ids),
        "reason": item.reason,
        "route_ready": False,
    }


def _objective_destination_lua(destination: ReviewedObjectiveDestination) -> list[str]:
    lines = [
        "      {",
        f"        stable_id = {lua_quote(destination.stable_id)},",
        f"        source_step_ids = {_lua_array(destination.source_step_ids)},",
        f"        source_claim_ids = {_lua_array(destination.source_claim_ids)},",
        "        source_revisions = {",
        *(
            f"          [{lua_quote(site)}] = {revision_id},"
            for site, revision_id in destination.source_revisions
        ),
        "        },",
        f"        action = {lua_quote(destination.action)},",
        f"        items = {_lua_array(destination.items)},",
        f"        enemies = {_lua_array(destination.enemies)},",
        f"        destination_id = {lua_quote(destination.destination_id)},",
        f"        zone = {destination.zone},",
        f"        zone_name = {lua_quote(destination.zone_name)},",
        f"        label = {lua_quote(destination.label)},",
        "        navigation_target = {",
        '          type = "static-reference",',
        "          reference = {",
        f"            zone = {destination.zone},",
        f"            zone_name = {lua_quote(destination.zone_name)},",
        f"            name = {lua_quote(destination.target_name)},",
        f"            kind = {lua_quote(destination.target_kind)},",
        "          },",
        "        },",
    ]
    if destination.target_point is None:
        lines.append("        target_point = nil,")
    else:
        lines.append(
            "        target_point = { "
            + ", ".join(format(value, ".17g") for value in destination.target_point)
            + " },"
        )
    lines.extend(
        [
        f"        eligibility = {lua_quote(destination.eligibility)},",
        f"        route_contract_id = {lua_quote(destination.route_contract_id)},",
        f"        canonical_ingress_edge_id = {destination.canonical_ingress_edge_id},",
        f"        canonical_ingress_from_zone = {destination.canonical_ingress_from_zone},",
        f"        transport_id = {lua_quote(destination.transport_id)},",
        f"        instruction_only = {'true' if destination.instruction_only else 'false'},",
        f"        arrival_instruction = {lua_quote(destination.arrival_instruction)},",
        "        route_ready = false,",
        "      },",
        ]
    )
    return lines


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


def _expanded_reviewed_page_matches(
    reviewed_overrides: Mapping[str, Any],
) -> dict[str, dict[str, Any]]:
    raw_matches = reviewed_overrides.get("page_matches", {})
    if not isinstance(raw_matches, Mapping):
        raise GenerationError("Reviewed page_matches must be an object.")
    expanded: dict[str, dict[str, Any]] = {}
    for native_key, per_site in raw_matches.items():
        if not isinstance(per_site, Mapping):
            raise GenerationError(f"Reviewed matches for {native_key!r} must be an object.")
        expanded[str(native_key)] = {
            str(site): dict(identity) if isinstance(identity, Mapping) else identity
            for site, identity in per_site.items()
        }

    groups = reviewed_overrides.get("shared_page_groups", [])
    if not isinstance(groups, list):
        raise GenerationError("Reviewed shared_page_groups must be an array.")
    for group in groups:
        if not isinstance(group, Mapping):
            raise GenerationError("Each reviewed shared page group must be an object.")
        site = str(group.get("site", "")).strip()
        native_keys = group.get("native_keys")
        if not site or not isinstance(native_keys, list) or len(native_keys) < 2 or "page_id" not in group:
            raise GenerationError("A reviewed shared page group needs a site, page_id, and two native keys.")
        identity = {
            "page_id": int(group["page_id"]),
            "canonical_title": str(group.get("canonical_title", "")).strip(),
            "allow_shared_page": True,
        }
        for native_key_value in native_keys:
            native_key = str(native_key_value)
            per_site = expanded.setdefault(native_key, {})
            previous = per_site.get(site)
            if previous is not None and (
                not isinstance(previous, Mapping)
                or int(previous.get("page_id", 0)) != identity["page_id"]
                or (
                    str(previous.get("canonical_title", "")).strip()
                    and str(previous.get("canonical_title", "")).strip() != identity["canonical_title"]
                )
            ):
                raise GenerationError(
                    f"Reviewed shared page group conflicts with {native_key!r}/{site!r}."
                )
            merged = dict(previous) if isinstance(previous, Mapping) else {}
            merged.update(identity)
            per_site[site] = merged
    return expanded


def _apply_reviewed_page_matches(
    native_by_key: Mapping[str, NativeObjective],
    pages: tuple[ParsedObjective, ...],
    source_maps: dict[str, dict[str, ParsedObjective]],
    reviewed_overrides: Mapping[str, Any] | None,
) -> None:
    if not reviewed_overrides:
        return
    raw_matches = _expanded_reviewed_page_matches(reviewed_overrides)
    page_lookup = {(page.site, page.page_id): page for page in pages}
    reviewed_assignments: dict[tuple[str, int], list[tuple[str, bool]]] = defaultdict(list)
    for native_key, per_site in raw_matches.items():
        if not isinstance(per_site, Mapping):
            raise GenerationError(f"Reviewed matches for {native_key!r} must be an object.")
        for site, raw_identity in per_site.items():
            if not isinstance(raw_identity, Mapping) or "page_id" not in raw_identity:
                raise GenerationError(f"Reviewed {site} match for {native_key!r} lacks page_id.")
            identity = (str(site), int(raw_identity["page_id"]))
            reviewed_assignments[identity].append(
                (str(native_key), raw_identity.get("allow_shared_page") is True)
            )
    for identity, assignments in reviewed_assignments.items():
        if len(assignments) > 1 and not all(allowed for _native_key, allowed in assignments):
            raise GenerationError(
                f"Reviewed page {identity!r} is shared by multiple objectives without explicit consent."
            )

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
            allow_shared = raw_identity.get("allow_shared_page") is True
            page = page_lookup.get(identity)
            if page is None:
                raise GenerationError(
                    f"Reviewed match {identity[0]} page {identity[1]} for {native_key!r} is absent."
                )
            expected_title = str(raw_identity.get("canonical_title", "")).strip()
            if expected_title and page.canonical_title != expected_title:
                raise GenerationError(
                    f"Reviewed page {identity!r} changed title from {expected_title!r} "
                    f"to {page.canonical_title!r}."
                )
            if page.kind != native.kind:
                raise GenerationError(f"Reviewed page {identity!r} has the wrong objective kind.")
            source_map = source_maps.setdefault(identity[0], {})
            for other_key, other_page in tuple(source_map.items()):
                if other_page.page_id == identity[1] and other_key != native_key and not allow_shared:
                    raise GenerationError(
                        f"Reviewed page {identity!r} is already assigned to {other_key!r}."
                    )
            source_map[str(native_key)] = page


def _has_material_conflict(reconciled: ReconciledObjective) -> bool:
    return reconciled.dynamic_candidate_comparison == "conflict" or any(
        step.comparison == "conflict" for step in reconciled.steps
    )


def _selector_key(value: object) -> str:
    return re.sub(r"[^a-z0-9]+", "", str(value or "").casefold())


def _resolve_stage_selectors(
    native_key: str,
    reconciled: ReconciledObjective,
    reviewed_overrides: Mapping[str, Any] | None,
) -> dict[str, str]:
    if not reviewed_overrides:
        return {}
    all_links = reviewed_overrides.get("automatic_stage_links", {})
    if not isinstance(all_links, Mapping):
        raise GenerationError("Reviewed automatic_stage_links must be an object.")
    stage_links = all_links.get(native_key, {})
    if not isinstance(stage_links, Mapping):
        raise GenerationError(f"Reviewed automatic stages for {native_key!r} must be an object.")

    resolved: dict[str, str] = {}
    for stage_key, raw_stage in stage_links.items():
        if not isinstance(raw_stage, Mapping) or not isinstance(raw_stage.get("step_selector"), Mapping):
            raise GenerationError(f"Reviewed stage {stage_key!r} for {native_key!r} lacks a selector.")
        selector = raw_stage["step_selector"]
        candidates = []
        for step in reconciled.steps:
            searchable = " ".join(
                (
                    *step.entities,
                    *step.zones,
                    *step.grid_coordinates,
                    step.bg_instruction,
                    step.ffxiclopedia_instruction,
                )
            )
            searchable_key = _selector_key(searchable)
            action = str(selector.get("action", "")).strip().casefold()
            entity = _selector_key(selector.get("entity", ""))
            key_item = _selector_key(selector.get("key_item", ""))
            grid = str(selector.get("grid", "")).strip().casefold()
            if action and step.action.casefold() != action:
                continue
            if entity and entity not in searchable_key:
                continue
            if key_item and key_item not in searchable_key:
                continue
            if grid and grid not in {value.casefold() for value in step.grid_coordinates}:
                continue
            candidates.append(step)
        occurrence = str(selector.get("occurrence", "")).strip().casefold()
        if occurrence == "first" and candidates:
            selected = candidates[0]
        elif occurrence == "last" and candidates:
            selected = candidates[-1]
        elif len(candidates) == 1:
            selected = candidates[0]
        else:
            raise GenerationError(
                f"Reviewed stage selector {native_key!r}/{stage_key!r} resolved to "
                f"{len(candidates)} steps; refusing to guess."
            )
        resolved[str(stage_key)] = selected.stable_step_id
    return resolved


def _runtime_objective_key(
    native_key: str,
    reviewed_overrides: Mapping[str, Any] | None,
) -> str:
    if not reviewed_overrides:
        return ""
    values = reviewed_overrides.get("runtime_objective_keys", {})
    if not isinstance(values, Mapping):
        raise GenerationError("Reviewed runtime_objective_keys must be an object.")
    return str(values.get(native_key, "")).strip()


def _casefold_values(values: Iterable[object]) -> set[str]:
    return {str(value or "").strip().casefold() for value in values if str(value or "").strip()}


def _claim_review_row(claim: ReconciledActionClaim) -> dict[str, Any]:
    return {
        "stable_claim_id": claim.stable_claim_id,
        "order": claim.order,
        "action": claim.action,
        "relationship": claim.relationship,
        "target": claim.target,
        "target_kind": claim.target_kind,
        "comparison": claim.comparison,
        "alignment_score": claim.alignment_score,
        "alignment_reason": claim.alignment_reason,
        "unpaired_reason": claim.unpaired_reason,
        "bg_span_order": claim.bg_span_order,
        "ffxiclopedia_span_order": claim.ffxiclopedia_span_order,
        "candidates": [
            {
                "field": candidate.field,
                "value": candidate.value,
                "comparison": candidate.comparison,
                "sources": list(candidate.sources),
            }
            for candidate in claim.candidates
        ],
    }


def _source_step_for_order(page: ParsedObjective | None, order: int) -> SourceStep | None:
    if page is None or order <= 0:
        return None
    return next((step for step in page.steps if step.order == order), None)


def _source_names_zone(step: SourceStep, zone_name: str) -> bool:
    wanted = zone_name.casefold()
    return any(
        wanted in _casefold_values(span.zone_mentions)
        for span in step.action_spans
    )


def _source_directs_talk_to(step: SourceStep, name: str) -> bool:
    if _OBJECT_LIKE_TARGET_NAME.search(name):
        return False
    wanted = name.casefold()
    return any(
        span.action == "talk"
        and span.target_kind == "npc"
        and (
            span.target.casefold() == wanted
            or wanted in _casefold_values(span.npc_mentions)
        )
        for span in step.action_spans
    )


def _propose_named_npc_target(
    step: ReconciledStep,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    navigation_point_index: Mapping[tuple[str, str], tuple[Mapping[str, Any], ...]],
    navigation_zone_names: Mapping[int, str],
) -> ReviewedNavigationTarget | None:
    if step.action.casefold() != "talk" or step.comparison != "corroborated":
        return None
    if "action" not in step.agreed_fields or "entities" not in step.agreed_fields:
        return None
    bg_step = _source_step_for_order(bg, step.source_orders[0])
    ffxi_step = _source_step_for_order(ffxiclopedia, step.source_orders[1])
    if bg_step is None or ffxi_step is None:
        return None
    if bg_step.action.casefold() != "talk" or ffxi_step.action.casefold() != "talk":
        return None
    common_names = _casefold_values(
        value for span in bg_step.action_spans for value in span.npc_mentions
    ).intersection(
        _casefold_values(
            value for span in ffxi_step.action_spans for value in span.npc_mentions
        )
    )
    candidates: list[ReviewedNavigationTarget] = []
    for common_name in common_names:
        for point in navigation_point_index.get((common_name, "npc"), ()):
            name = str(point.get("name", "")).strip()
            if not name or name == "???":
                continue
            if not _source_directs_talk_to(bg_step, name) or not _source_directs_talk_to(ffxi_step, name):
                continue
            zone = int(point.get("zone", 0) or 0)
            zone_name = str(navigation_zone_names.get(zone, "")).strip()
            if not zone_name:
                continue
            if not _source_names_zone(bg_step, zone_name) or not _source_names_zone(ffxi_step, zone_name):
                continue
            candidates.append(
                ReviewedNavigationTarget(
                    target_type="static-reference",
                    zone=zone,
                    zone_name=zone_name,
                    name=name,
                    kind="npc",
                    arrival_instruction=f"Talk to {name}.",
                )
            )
    unique = {
        (candidate.zone, candidate.name.casefold(), candidate.kind): candidate
        for candidate in candidates
    }
    if len(candidates) != 1 or len(unique) != 1:
        return None
    return next(iter(unique.values()))


def _reviewed_target_overrides(reviewed_overrides: Mapping[str, Any] | None) -> Mapping[str, Any]:
    if not reviewed_overrides:
        return {}
    targets = reviewed_overrides.get("target_overrides", {})
    if not isinstance(targets, Mapping):
        raise GenerationError("Reviewed target_overrides must be an object.")
    return targets


def _logical_reviewed_target_points(
    points: Iterable[Mapping[str, Any]],
) -> tuple[Mapping[str, Any], ...]:
    groups: dict[tuple[float, float, float], list[Mapping[str, Any]]] = defaultdict(list)
    for point in points:
        raw_coordinates = (point.get("x"), point.get("z"), point.get("y"))
        if any(value is None or str(value).strip() == "" for value in raw_coordinates):
            raise GenerationError("Reviewed navigation target lacks complete current coordinates.")
        try:
            coordinates = tuple(float(value) for value in raw_coordinates)
        except (TypeError, ValueError) as error:
            raise GenerationError("Reviewed navigation target has malformed current coordinates.") from error
        if not all(math.isfinite(value) for value in coordinates):
            raise GenerationError("Reviewed navigation target has non-finite current coordinates.")
        groups[coordinates].append(point)

    return tuple(
        min(
            groups[coordinates],
            key=lambda point: (
                0 if str(point.get("destination_id", "")).strip() else 1,
                str(point.get("destination_id", "")).strip(),
                str(point.get("raw_identity", "")).strip(),
                str(point.get("source", "")).strip(),
            ),
        )
        for coordinates in sorted(groups)
    )


def _reviewed_target_source_candidate_ids(
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    *,
    name: str,
    zone_name: str,
) -> tuple[str, ...]:
    wanted_name = name.casefold()
    candidates: list[str] = []
    for step in reconciled.steps:
        if (
            step.action.casefold() != "talk"
            or step.comparison == "conflict"
            or "action" not in step.agreed_fields
            or "entities" not in step.agreed_fields
        ):
            continue
        bg_step = _source_step_for_order(bg, step.source_orders[0])
        ffxi_step = _source_step_for_order(ffxiclopedia, step.source_orders[1])
        if bg_step is None or ffxi_step is None:
            continue
        if not _source_directs_talk_to(bg_step, name) or not _source_directs_talk_to(
            ffxi_step, name
        ):
            continue
        bg_names = _casefold_values(
            value for span in bg_step.action_spans for value in span.npc_mentions
        )
        ffxi_names = _casefold_values(
            value for span in ffxi_step.action_spans for value in span.npc_mentions
        )
        if wanted_name not in bg_names or wanted_name not in ffxi_names:
            continue
        if not _source_names_zone(bg_step, zone_name) or not _source_names_zone(
            ffxi_step, zone_name
        ):
            continue
        candidates.append(step.stable_step_id)
    return tuple(candidates)


def _reviewed_target_key_mentions_name(
    step: ReconciledStep,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    name: str,
) -> bool:
    wanted_name = name.casefold()
    source_steps = (
        _source_step_for_order(bg, step.source_orders[0]),
        _source_step_for_order(ffxiclopedia, step.source_orders[1]),
    )
    return all(
        source_step is not None
        and wanted_name
        in f"{source_step.source_text}\n{source_step.spoken_text}".casefold()
        for source_step in source_steps
    )


def _reviewed_target_failure(
    *,
    native_key: str,
    override_step_id: str,
    reason: str,
    candidate_step_ids: tuple[str, ...],
    source_revisions: Mapping[str, Any],
    reference: Mapping[str, Any],
) -> dict[str, Any]:
    return {
        "native_key": native_key,
        "override_step_id": override_step_id,
        "reason": reason,
        "candidate_step_ids": list(candidate_step_ids),
        "source_revisions": {
            str(site): int(revision)
            for site, revision in sorted(source_revisions.items())
        },
        "reference": {
            "zone": int(reference.get("zone", 0) or 0),
            "zone_name": str(reference.get("zone_name", "")).strip(),
            "name": str(reference.get("name", "")).strip(),
            "kind": str(reference.get("kind", "")).strip().casefold(),
        },
        "classification": "unresolved",
        "route_ready": False,
    }


def _resolve_reviewed_navigation_targets(
    native_key: str,
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    reviewed_overrides: Mapping[str, Any] | None,
    navigation_points: tuple[Mapping[str, Any], ...],
    navigation_zone_names: Mapping[int, str],
) -> tuple[ReconciledObjective, tuple[dict[str, Any], ...]]:
    all_targets = _reviewed_target_overrides(reviewed_overrides)
    step_lookup = {step.stable_step_id: step for step in reconciled.steps}
    updates: dict[str, ReconciledStep] = {}
    failures: list[dict[str, Any]] = []
    for stable_step_id, raw_target in all_targets.items():
        stable_step_id = str(stable_step_id)
        if not stable_step_id.startswith(native_key + ":step-"):
            continue
        step = step_lookup.get(stable_step_id)
        if step is None:
            raise GenerationError(f"Reviewed target names unknown step {stable_step_id!r}.")
        if not isinstance(raw_target, Mapping):
            raise GenerationError(f"Reviewed target {stable_step_id!r} must be an object.")
        source_revisions = raw_target.get("source_revisions")
        if not isinstance(source_revisions, Mapping) or bg is None or ffxiclopedia is None:
            raise GenerationError(
                f"Reviewed target {stable_step_id!r} lacks pinned dual-source revisions."
            )
        expected_revisions = {
            "bg": bg.revision_id,
            "ffxiclopedia": ffxiclopedia.revision_id,
        }
        for site, expected_revision in expected_revisions.items():
            if int(source_revisions.get(site, 0) or 0) != expected_revision:
                raise GenerationError(
                    f"Reviewed target {stable_step_id!r} no longer matches its {site} revision."
                )
        reference = raw_target.get("reference")
        if not isinstance(reference, Mapping):
            raise GenerationError(f"Reviewed target {stable_step_id!r} lacks an exact reference.")

        zone = int(reference.get("zone", 0) or 0)
        zone_name = str(reference.get("zone_name", "")).strip()
        name = str(reference.get("name", "")).strip()
        kind = str(reference.get("kind", "")).strip().casefold()
        arrival_instruction = str(raw_target.get("arrival_instruction", "")).strip()
        if zone <= 0 or not zone_name or not name or kind != "npc" or name == "???":
            raise GenerationError(
                f"Reviewed target {stable_step_id!r} is not an exact named NPC reference."
            )
        if not arrival_instruction:
            raise GenerationError(f"Reviewed target {stable_step_id!r} lacks arrival instructions.")
        candidate_step_ids = _reviewed_target_source_candidate_ids(
            reconciled,
            bg,
            ffxiclopedia,
            name=name,
            zone_name=zone_name,
        )
        if stable_step_id not in candidate_step_ids:
            failures.append(
                _reviewed_target_failure(
                    native_key=native_key,
                    override_step_id=stable_step_id,
                    reason=(
                        (
                            "source-claim-evidence-insufficient-at-key"
                            if _reviewed_target_key_mentions_name(
                                step, bg, ffxiclopedia, name
                            )
                            else "source-claim-no-match"
                        )
                        if not candidate_step_ids
                        else "source-claim-step-shift"
                        if len(candidate_step_ids) == 1
                        else "source-claim-ambiguous"
                    ),
                    candidate_step_ids=candidate_step_ids,
                    source_revisions=source_revisions,
                    reference=reference,
                )
            )
            continue

        current_zone_name = str(navigation_zone_names.get(zone, "")).strip()
        if not current_zone_name or current_zone_name.casefold() != zone_name.casefold():
            failures.append(
                _reviewed_target_failure(
                    native_key=native_key,
                    override_step_id=stable_step_id,
                    reason="current-navigation-zone-mismatch",
                    candidate_step_ids=candidate_step_ids,
                    source_revisions=source_revisions,
                    reference=reference,
                )
            )
            continue
        wanted_name = name.casefold()
        matches = [
            point
            for point in navigation_points
            if int(point.get("zone", 0) or 0) == zone
            and str(point.get("name", "")).strip().casefold() == wanted_name
            and str(point.get("kind", "")).strip().casefold() == kind
        ]
        logical_matches = _logical_reviewed_target_points(matches)
        if len(logical_matches) != 1:
            failures.append(
                _reviewed_target_failure(
                    native_key=native_key,
                    override_step_id=stable_step_id,
                    reason=(
                        "current-navigation-missing"
                        if not logical_matches
                        else "current-navigation-ambiguous"
                    ),
                    candidate_step_ids=candidate_step_ids,
                    source_revisions=source_revisions,
                    reference=reference,
                )
            )
            continue
        updates[stable_step_id] = replace(
            step,
            route_ready=True,
            navigation_target=ReviewedNavigationTarget(
                target_type="static-reference",
                zone=zone,
                zone_name=current_zone_name,
                name=name,
                kind=kind,
                arrival_instruction=arrival_instruction,
            ),
        )

    if updates:
        reconciled = replace(
            reconciled,
            steps=tuple(updates.get(step.stable_step_id, step) for step in reconciled.steps),
        )
    return reconciled, tuple(failures)


def _section_heading_key(instruction: str) -> str:
    match = re.match(r"^Section:\s*(.*?)\.?$", str(instruction or "").strip(), re.IGNORECASE)
    if not match:
        return ""
    heading = re.sub(r"^[0-9][0-9A-Za-z-]*:\s*", "", match.group(1)).strip()
    return normalize_title(heading)


def _section_matches_native_title(section_key: str, native_title: str) -> bool:
    if not section_key or not native_title:
        return False
    if section_key == native_title:
        return True
    if not section_key.startswith(native_title):
        return False
    suffix = section_key[len(native_title) :]
    return bool(suffix) and suffix.endswith("path")


def _default_shared_step_id(
    native: NativeObjective,
    reconciled: ReconciledObjective,
    matched: Mapping[str, ParsedObjective],
    assignment_counts: Mapping[tuple[str, int], int],
) -> str:
    if not any(assignment_counts.get((site, page.page_id), 0) > 1 for site, page in matched.items()):
        return ""
    native_title = normalize_title(native.title)
    sections = [
        step
        for step in reconciled.steps
        if native_title
        and any(
            _section_matches_native_title(section_key, native_title)
            for section_key in (
                _section_heading_key(step.bg_instruction),
                _section_heading_key(step.ffxiclopedia_instruction),
            )
        )
    ]
    if sections:
        return sections[0].stable_step_id
    if not sections and reconciled.steps:
        for page in matched.values():
            source_titles = (page.objective_name, page.canonical_title, *page.aliases)
            if native_title in {normalize_title(value) for value in source_titles}:
                return reconciled.steps[0].stable_step_id
    return ""


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


def _progression_revision(reconciled: ReconciledObjective | None) -> str:
    claims = []
    if reconciled is not None:
        for step in reconciled.steps:
            for claim in step.claims:
                if not claim.material:
                    continue
                claims.append(
                    {
                        "stable_claim_id": claim.stable_claim_id,
                        "order": claim.order,
                        "action": claim.action,
                        "relationship": claim.relationship,
                        "target": claim.target,
                        "target_kind": claim.target_kind,
                        "result_relation": claim.result_relation,
                        "bg_span_order": claim.bg_span_order,
                        "ffxiclopedia_span_order": claim.ffxiclopedia_span_order,
                        "matcher_facts": [
                            {
                                "field": candidate.field,
                                "value": candidate.value,
                                "comparison": candidate.comparison,
                                "sources": list(candidate.sources),
                            }
                            for candidate in claim.candidates
                        ],
                        "authoritative_matcher_facts": {
                            field: list(
                                dict.fromkeys(
                                    candidate.value
                                    for candidate in (
                                        [
                                            row for row in claim.candidates
                                            if row.field == field and "bg" in row.sources
                                        ]
                                        or [row for row in claim.candidates if row.field == field]
                                    )
                                )
                            )
                            for field in sorted({row.field for row in claim.candidates})
                        },
                    }
                )
    payload = {
        "schema_version": _PROGRESSION_REVISION_SCHEMA,
        "source_authority": _SOURCE_AUTHORITY,
        "claims": claims,
    }
    return hashlib.sha256(
        json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _source_snapshot_page(page: ParsedObjective | PageRevision) -> dict[str, Any]:
    return {
        "site": page.site,
        "page_id": page.page_id,
        "revision_id": page.revision_id,
        "revision_timestamp": page.revision_timestamp,
        "canonical_title": page.canonical_title,
        "objective_name": str(getattr(page, "objective_name", "")),
        "kind": str(getattr(page, "kind", "")),
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
                f"    progression_schema_version = {record['progression_schema_version']},",
                f"    progression_revision = {lua_quote(record['progression_revision'])},",
                "    source_authority = {",
                f"      primary = {lua_quote(record['source_authority']['primary'])},",
                f"      fallback = {lua_quote(record['source_authority']['fallback'])},",
                "    },",
                "    source_modules = {",
            ]
        )
        for site in sorted(modules):
            lines.append(f"      [{lua_quote(site)}] = {lua_quote(modules[site])},")
        lines.extend(
            [
                "    },",
                f"    reconcile_module = {lua_quote(record['reconcile_module']) if record['reconcile_module'] else 'nil'},",
                f"    progression_module = {lua_quote(record['progression_module']) if record['progression_module'] else 'nil'},",
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
    source_revisions: Iterable[PageRevision] | None = None,
    parse_failures: Iterable[Mapping[str, Any]] = (),
    navigation_points: Iterable[Mapping[str, Any]] = (),
    navigation_zone_names: Mapping[int, str] | None = None,
    navigation_edges: Iterable[Mapping[str, Any]] = (),
) -> dict[str, Any]:
    """Build deterministic, license-separated runtime and coverage artifacts."""

    natives = tuple(sorted(native_objectives, key=lambda row: row.key))
    pages = tuple(sorted(parsed_pages, key=lambda page: (page.site, page.page_id, page.revision_id)))
    revisions = tuple(
        sorted(
            source_revisions or (),
            key=lambda page: (page.site, page.page_id, page.revision_id),
        )
    )
    if not revisions:
        revisions = pages
    nav_points = tuple(navigation_points)
    nav_edges = tuple(navigation_edges)
    nav_point_lists: dict[tuple[str, str], list[Mapping[str, Any]]] = defaultdict(list)
    for point in nav_points:
        key = (
            str(point.get("name", "")).strip().casefold(),
            str(point.get("kind", "")).strip().casefold(),
        )
        nav_point_lists[key].append(point)
    nav_point_index = {key: tuple(values) for key, values in nav_point_lists.items()}
    nav_zone_names = {
        int(zone): str(name)
        for zone, name in (navigation_zone_names or {}).items()
        if int(zone) > 0 and str(name).strip()
    }
    if len({native.key for native in natives}) != len(natives):
        raise GenerationError("Native objective keys must be unique before guide generation.")
    if len({(page.site, page.page_id) for page in pages}) != len(pages):
        raise GenerationError("A source snapshot contains duplicate site/page identities.")
    if len({(page.site, page.page_id) for page in revisions}) != len(revisions):
        raise GenerationError("Raw source revisions contain duplicate site/page identities.")
    revision_lookup = {(page.site, page.page_id): page for page in revisions}
    for page in pages:
        _license_id(page)
        revision = revision_lookup.get((page.site, page.page_id))
        if revision is None or revision.revision_id != page.revision_id:
            raise GenerationError(
                f"Parsed page {page.site}:{page.page_id} has no matching source revision."
            )
        if page.content_sha256 and revision.content_sha256 != page.content_sha256:
            raise GenerationError(
                f"Parsed page {page.site}:{page.page_id} does not match its source content hash."
            )
    for revision in revisions:
        _license_id(revision)

    native_by_key = {native.key: native for native in natives}
    legacy_override_root = (
        reviewed_overrides.get("mission_destination_overrides", {})
        if isinstance(reviewed_overrides, Mapping)
        else {}
    )
    legacy_migration_root = (
        reviewed_overrides.get("legacy_action_migrations", {})
        if isinstance(reviewed_overrides, Mapping)
        else {}
    )
    if not isinstance(legacy_override_root, Mapping) or not isinstance(
        legacy_migration_root, Mapping
    ):
        raise GenerationError("Legacy destination override sections must be objects.")
    unknown_legacy_keys = set(legacy_override_root).difference(native_by_key)
    unknown_migration_keys = set(legacy_migration_root).difference(legacy_override_root)
    if unknown_legacy_keys:
        raise GenerationError(
            "Legacy destination overrides reference unknown native keys: "
            + ", ".join(sorted(unknown_legacy_keys)[:5])
        )
    if unknown_migration_keys:
        raise GenerationError(
            "Legacy action migrations have no matching legacy override rows: "
            + ", ".join(sorted(unknown_migration_keys)[:5])
        )
    empty_migration_keys = sorted(
        native_key
        for native_key in legacy_migration_root
        if not isinstance(legacy_override_root.get(native_key), list)
        or not legacy_override_root[native_key]
    )
    if empty_migration_keys:
        raise GenerationError(
            "Legacy action migrations have empty legacy override lists: "
            + ", ".join(empty_migration_keys[:5])
        )
    expected_legacy_outcome_ids: set[str] = set()
    for native_key, raw_rows in legacy_override_root.items():
        if native_by_key[native_key].kind != "mission" or not isinstance(raw_rows, list):
            raise GenerationError(
                f"Legacy destinations for {native_key!r} must be a mission list."
            )
        for raw in raw_rows:
            if not isinstance(raw, Mapping):
                raise GenerationError(
                    f"Legacy destinations for {native_key!r} must contain objects."
                )
            short_id = str(raw.get("id", "")).strip().casefold()
            stable_id = f"{native_key}:destination:{short_id}"
            if not short_id or stable_id in expected_legacy_outcome_ids:
                raise GenerationError(f"Legacy destination id {stable_id!r} is missing or duplicated.")
            expected_legacy_outcome_ids.add(stable_id)
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
    assignment_counts: dict[tuple[str, int], int] = defaultdict(int)
    for site, source_map in source_maps.items():
        for page in source_map.values():
            assignment_counts[(site, page.page_id)] += 1

    source_groups: dict[tuple[str, str, str], list[tuple[NativeObjective, ParsedObjective]]] = defaultdict(list)
    reconcile_groups: dict[
        tuple[str, str],
        list[tuple[NativeObjective, ReconciledObjective, Mapping[str, str], str, set[str]]],
    ] = defaultdict(list)
    progression_groups: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    coverage_objectives: dict[str, dict[str, Any]] = {}
    target_review_steps: list[dict[str, Any]] = []
    target_review_target_failures: list[dict[str, Any]] = []
    target_review_objective_destinations: list[dict[str, Any]] = []
    target_review_action_ledger: list[dict[str, Any]] = []
    target_review_candidates: list[dict[str, Any]] = []
    target_review_groups: list[dict[str, Any]] = []
    target_review_resolution_items: list[dict[str, Any]] = []
    target_review_legacy_outcomes: list[dict[str, Any]] = []
    resolved_reviewed_target_steps: set[str] = set()

    for native in natives:
        bg = source_maps.get("bg", {}).get(native.key)
        ffxiclopedia = source_maps.get("ffxiclopedia", {}).get(native.key)
        matched = {site: page for site, page in (("bg", bg), ("ffxiclopedia", ffxiclopedia)) if page is not None}
        for site, page in matched.items():
            source_groups[(site, native.kind, native.context)].append((native, page))

        reconciled: ReconciledObjective | None = None
        automatic_stages: dict[str, str] = {}
        default_step_id = ""
        runtime_objective_key = ""
        route_steps: set[str] = set()
        reviewed_target_failures: tuple[dict[str, Any], ...] = ()
        if matched:
            reconciled = reconcile_objectives(native.key, bg, ffxiclopedia)
            reconciled, reviewed_target_failures = _resolve_reviewed_navigation_targets(
                native.key,
                reconciled,
                bg,
                ffxiclopedia,
                reviewed_overrides,
                nav_points,
                nav_zone_names,
            )
            target_review_target_failures.extend(reviewed_target_failures)
            resolved_reviewed_target_steps.update(
                failure["override_step_id"] for failure in reviewed_target_failures
            )
            try:
                action_resolution = resolve_objective_actions(
                    native,
                    reconciled,
                    bg,
                    ffxiclopedia,
                    reviewed_overrides,
                    nav_points,
                    nav_zone_names,
                )
            except ObjectiveDestinationError as error:
                raise GenerationError(str(error)) from error
            route_ledger, route_candidates, route_groups = task3_route_contract_inputs(
                action_resolution
            )
            reconciled = replace(
                reconciled,
                action_resolution_ledger=route_ledger,
                objective_destination_candidates=route_candidates,
                objective_destination_groups=route_groups,
                objective_resolution_review_items=action_resolution.review_items,
            )
            for row in route_ledger:
                target_review_action_ledger.append(
                    {
                        "native_key": native.key,
                        "action_id": row.action_id,
                        "source_action_span_ids": list(row.source_action_span_ids),
                        "action": row.action,
                        "status": row.status,
                        "reason": row.reason,
                        "candidate_ids": list(row.candidate_ids),
                        "candidate_count": len(row.candidate_ids),
                        "instruction": row.instruction,
                        "material": row.material,
                        "route_ready": False,
                    }
                )
            for candidate in route_candidates:
                target_review_candidates.append(_objective_candidate_review_row(native.key, candidate))
            for group in route_groups:
                target_review_groups.append(_objective_group_review_row(native.key, group))
            for item in action_resolution.review_items:
                target_review_resolution_items.append(
                    _objective_review_item_row(native.key, item)
                )
            for outcome in action_resolution.legacy_destination_outcomes:
                target_review_legacy_outcomes.append(
                    _legacy_destination_outcome_review_row(native.key, outcome)
                )
            try:
                objective_destinations = resolve_reviewed_objective_destinations(
                    native,
                    reconciled,
                    bg,
                    ffxiclopedia,
                    reviewed_overrides,
                    nav_points,
                    nav_zone_names,
                    nav_edges,
                )
            except ObjectiveDestinationError as error:
                raise GenerationError(str(error)) from error
            reconciled = replace(reconciled, objective_destinations=objective_destinations)
            for destination in objective_destinations:
                target_review_objective_destinations.append(
                    {
                        "native_key": native.key,
                        "stable_id": destination.stable_id,
                        "source_step_ids": list(destination.source_step_ids),
                        "source_claim_ids": list(destination.source_claim_ids),
                        "source_revisions": dict(destination.source_revisions),
                        "action": destination.action,
                        "items": list(destination.items),
                        "enemies": list(destination.enemies),
                        "destination_id": destination.destination_id,
                        "zone": destination.zone,
                        "zone_name": destination.zone_name,
                        "label": destination.label,
                        "target_point": list(destination.target_point) if destination.target_point else None,
                        "navigation_target": {
                            "type": "static-reference",
                            "reference": {
                                "zone": destination.zone,
                                "zone_name": destination.zone_name,
                                "name": destination.target_name,
                                "kind": destination.target_kind,
                            },
                        },
                        "canonical_ingress_edge_id": destination.canonical_ingress_edge_id,
                        "canonical_ingress_from_zone": destination.canonical_ingress_from_zone,
                        "transport_id": destination.transport_id,
                        "eligibility": destination.eligibility,
                        "route_contract_id": destination.route_contract_id,
                        "instruction_only": destination.instruction_only,
                        "arrival_instruction": destination.arrival_instruction,
                        "classification": (
                            "instruction-only" if destination.instruction_only else "catalogue-candidate"
                        ),
                        "route_ready": False,
                    }
                )
            automatic_stages = _resolve_stage_selectors(native.key, reconciled, reviewed_overrides)
            default_step_id = _default_shared_step_id(
                native,
                reconciled,
                matched,
                assignment_counts,
            )
            runtime_objective_key = _runtime_objective_key(native.key, reviewed_overrides)
            if runtime_objective_key and automatic_stages:
                route_steps = set(automatic_stages.values())
            route_steps.update(
                step.stable_step_id for step in reconciled.steps if step.route_ready
            )
            resolved_reviewed_target_steps.update(
                step.stable_step_id
                for step in reconciled.steps
                if step.navigation_target is not None
            )
            reconcile_groups[(native.kind, native.context)].append(
                (native, reconciled, automatic_stages, default_step_id, route_steps)
            )
            for step in reconciled.steps:
                proposal = _propose_named_npc_target(
                    step,
                    bg,
                    ffxiclopedia,
                    nav_point_index,
                    nav_zone_names,
                )
                if step.stable_step_id in route_steps:
                    review_status = (
                        "verified-reviewed-target"
                        if step.navigation_target is not None
                        else "verified-runtime"
                    )
                elif step.comparison == "conflict":
                    review_status = "source-conflict"
                elif reconciled.dynamic_candidate_grid:
                    review_status = "dynamic-candidate-unresolved"
                elif proposal is not None:
                    review_status = "needs-reviewed-exact-target"
                elif step.action in {"talk", "travel", "examine", "use", "wait"} and (
                    step.entities or step.zones or step.grid_coordinates
                ):
                    review_status = "needs-exact-target-review"
                else:
                    review_status = "guide-only-action"
                if step.stable_step_id in route_steps:
                    classification = "routable"
                elif step.comparison == "conflict":
                    classification = "conflict"
                else:
                    classification = "unresolved"
                review_row: dict[str, Any] = {
                    "native_key": native.key,
                    "stable_step_id": step.stable_step_id,
                    "action": step.action,
                    "comparison": step.comparison,
                    "alignment_score": step.alignment_score,
                    "alignment_reason": step.alignment_reason,
                    "unpaired_reason": step.unpaired_reason,
                    "entities": list(step.entities),
                    "items": list(step.items),
                    "zones": list(step.zones),
                    "grid_coordinates": list(step.grid_coordinates),
                    "typed_claims": [_claim_review_row(claim) for claim in step.claims],
                    "source_orders": list(step.source_orders),
                    "source_revisions": {
                        site: page.revision_id for site, page in sorted(matched.items())
                    },
                    "source_instructions": {
                        "bg": step.bg_instruction,
                        "ffxiclopedia": step.ffxiclopedia_instruction,
                    },
                    "dynamic_candidate_grid": list(reconciled.dynamic_candidate_grid),
                    "review_status": review_status,
                    "classification": classification,
                    "route_ready": step.stable_step_id in route_steps,
                }
                if step.navigation_target is not None:
                    review_row["navigation_target"] = {
                        "type": step.navigation_target.target_type,
                        "zone": step.navigation_target.zone,
                        "zone_name": step.navigation_target.zone_name,
                        "name": step.navigation_target.name,
                        "kind": step.navigation_target.kind,
                    }
                elif proposal is not None:
                    review_row["proposed_navigation_target"] = {
                        "type": proposal.target_type,
                        "zone": proposal.zone,
                        "zone_name": proposal.zone_name,
                        "name": proposal.name,
                        "kind": proposal.kind,
                    }
                if proposal is not None and bg is not None and ffxiclopedia is not None:
                    review_row["proposal_evidence"] = {
                        "bg_revision_id": bg.revision_id,
                        "bg_instruction": step.bg_instruction,
                        "bg_source_url": _source_url(bg),
                        "ffxiclopedia_revision_id": ffxiclopedia.revision_id,
                        "ffxiclopedia_instruction": step.ffxiclopedia_instruction,
                        "ffxiclopedia_source_url": _source_url(ffxiclopedia),
                    }
                target_review_steps.append(review_row)

        has_steps = any(page.steps for page in matched.values())
        ambiguous_sites = sorted(
            site for site, keys in ambiguous_by_site.items() if native.key in keys and site not in matched
        )
        if runtime_objective_key and automatic_stages:
            status = "automatic-stage"
        elif route_steps:
            status = "verified-navigation"
        elif reconciled is not None and _has_material_conflict(reconciled):
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
        progression_module = _progression_module_name(native.kind, native.context) if reconciled else ""
        progression_payload = progression_objective_payload(
            native,
            reconciled,
            matched,
            progression_module,
        )
        if reconciled is not None:
            progression_groups[(native.kind, native.context)].append(progression_payload)
        coverage_objectives[native.key] = {
            "status": status,
            "title": native.title,
            "kind": native.kind,
            "context": native.context,
            "source_authority": dict(_SOURCE_AUTHORITY),
            "progression_schema_version": _PROGRESSION_REVISION_SCHEMA,
            "progression_revision": progression_payload["progression_revision"],
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
            "progression_module": progression_module,
            "ambiguous_sites": ambiguous_sites,
            "dynamic_candidate_comparison": (
                reconciled.dynamic_candidate_comparison if reconciled else "none"
            ),
            "has_source_conflict": reconciled is not None and _has_material_conflict(reconciled),
            "runtime_objective_key": runtime_objective_key,
            "automatic_stages": automatic_stages,
            "default_step_id": default_step_id,
            "route_ready": bool(route_steps),
            "reviewed_target_failures": list(reviewed_target_failures),
            "legacy_destination_outcomes": [
                _legacy_destination_outcome_review_row(native.key, outcome)
                for outcome in (
                    action_resolution.legacy_destination_outcomes if matched else ()
                )
            ],
            "automatic_stage": bool(automatic_stages),
        }

    unresolved_reviewed_targets = set(_reviewed_target_overrides(reviewed_overrides)).difference(
        resolved_reviewed_target_steps
    )
    if unresolved_reviewed_targets:
        sample = ", ".join(sorted(unresolved_reviewed_targets)[:5])
        raise GenerationError(
            f"Reviewed targets no longer resolve to current guide steps: {sample}"
        )
    actual_legacy_outcome_ids = [
        row["legacy_override_id"] for row in target_review_legacy_outcomes
    ]
    if (
        len(actual_legacy_outcome_ids) != len(set(actual_legacy_outcome_ids))
        or set(actual_legacy_outcome_ids) != expected_legacy_outcome_ids
    ):
        missing = sorted(expected_legacy_outcome_ids.difference(actual_legacy_outcome_ids))
        extra = sorted(set(actual_legacy_outcome_ids).difference(expected_legacy_outcome_ids))
        raise GenerationError(
            "Legacy destination outcome accounting mismatch; "
            f"missing={missing[:5]}, extra={extra[:5]}."
        )

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
    for (kind, context), payloads in sorted(progression_groups.items()):
        progression_module_name = _progression_module_name(kind, context)
        progression_path = module_root / f"{progression_module_name}.lua"
        _write_text(
            progression_path,
            _progression_module_text(progression_module_name, payloads),
        )
        generated_module_paths.add(progression_path)

    index_path = module_root / "mission_quest_guide_index.lua"
    _write_text(index_path, _index_text(natives, coverage_objectives))
    generated_module_paths.add(index_path)

    generated_patterns = (
        "mission_quest_bg_*.lua",
        "mission_quest_ffxiclopedia_*.lua",
        "mission_quest_reconcile_*.lua",
        "mission_quest_progression_*.lua",
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
        "verified_navigation": sum(
            1 for record in coverage_objectives.values() if record["route_ready"]
        ),
        "automatic_stage": sum(
            1 for record in coverage_objectives.values() if record["automatic_stage"]
        ),
    }

    native_manifest = {"schema_version": 1, "objectives": [_native_manifest_row(native) for native in natives]}
    source_snapshot = {
        "schema_version": 1,
        "pages": [_source_snapshot_page(page) for page in revisions],
    }
    failure_lookup = {
        (str(failure.get("site", "")), int(failure.get("page_id", 0) or 0)): failure
        for failure in parse_failures
        if isinstance(failure, Mapping)
    }
    matched_keys_by_page: dict[tuple[str, int], list[str]] = defaultdict(list)
    for site, source_map in source_maps.items():
        for native_key, page in source_map.items():
            matched_keys_by_page[(site, page.page_id)].append(native_key)
    parsed_identities = {(page.site, page.page_id) for page in pages}
    source_inventory: dict[str, dict[str, Any]] = {}
    for revision in revisions:
        identity = (revision.site, revision.page_id)
        matched_native_keys = sorted(matched_keys_by_page.get(identity, ()))
        failure = failure_lookup.get(identity)
        if matched_native_keys:
            source_status = "matched"
        elif failure is not None:
            source_status = "parser-failure"
        elif identity in parsed_identities:
            source_status = "source-unmatched"
        else:
            source_status = "source-only"
        source_inventory[f"{revision.site}:{revision.page_id}"] = {
            "status": source_status,
            "title": revision.canonical_title,
            "revision_id": revision.revision_id,
            "source_url": revision.source_url,
            "native_keys": matched_native_keys,
            "failure_reason": str(failure.get("reason", ""))[:500] if failure else "",
        }
    coverage = {
        "schema_version": 1,
        "counts": counts,
        "objectives": coverage_objectives,
        "source_inventory": source_inventory,
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
    _write_json(
        data_root / "target-review.json",
        {
            "schema_version": 1,
            "action_resolution_ledger": sorted(
                target_review_action_ledger,
                key=lambda row: (row["native_key"], row["action_id"]),
            ),
            "objective_destination_candidates": sorted(
                target_review_candidates,
                key=lambda row: (row["native_key"], row["candidate_id"]),
            ),
            "objective_destination_groups": sorted(
                target_review_groups,
                key=lambda row: (row["native_key"], row["group_id"]),
            ),
            "objective_resolution_review_items": sorted(
                target_review_resolution_items,
                key=lambda row: (row["native_key"], row["review_id"]),
            ),
            "legacy_destination_outcomes": sorted(
                target_review_legacy_outcomes,
                key=lambda row: (row["native_key"], row["legacy_override_id"]),
            ),
            "objective_destinations": sorted(
                target_review_objective_destinations,
                key=lambda row: (row["native_key"], row["stable_id"]),
            ),
            "reviewed_target_failures": sorted(
                target_review_target_failures,
                key=lambda row: (row["native_key"], row["override_step_id"]),
            ),
            "steps": sorted(
                target_review_steps,
                key=lambda row: (row["native_key"], row["stable_step_id"]),
            ),
        },
    )
    _write_text(data_root / "coverage.md", _coverage_markdown(counts, pages))

    return {
        "counts": counts,
        "module_files": sorted(path.name for path in generated_module_paths),
        "data_files": [
            "coverage.json",
            "coverage.md",
            "native-manifest.json",
            "source-snapshot.json",
            "target-review.json",
        ],
        "route_inputs": {
            "ledger": tuple(
                sorted(
                    target_review_action_ledger,
                    key=lambda row: (row["native_key"], row["action_id"]),
                )
            ),
            "candidates": tuple(
                sorted(
                    target_review_candidates,
                    key=lambda row: (row["native_key"], row["candidate_id"]),
                )
            ),
            "groups": tuple(
                sorted(
                    target_review_groups,
                    key=lambda row: (row["native_key"], row["group_id"]),
                )
            ),
        },
    }

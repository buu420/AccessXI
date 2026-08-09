from __future__ import annotations

import hashlib
import math
import re
from collections.abc import Iterable, Mapping
from typing import Any

from .model import NativeObjective, ParsedObjective, SourceActionSpan
from .reconcile import (
    ObjectiveActionLedgerRow,
    ObjectiveActionResolution,
    ObjectiveDestinationCandidate,
    ObjectiveDestinationGroup,
    ObjectiveResolutionReviewItem,
    ReconciledActionClaim,
    ReconciledObjective,
    ReconciledStep,
    ReviewedObjectiveDestination,
)


class ObjectiveDestinationError(ValueError):
    """Raised when a reviewed destination no longer proves its typed claims."""


_STABLE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_SUPPORTED_ACTIONS = {"talk", "trade", "examine", "use", "fight", "farm", "obtain", "travel"}
ACTION_KINDS = {
    "talk": ("npc",),
    "trade": ("npc",),
    "examine": ("npc", "object", "area"),
    "use": ("npc", "object", "area"),
    "fight": ("enemy",),
    "obtain": ("enemy",),
    "travel": ("area", "object"),
}
LEDGER_STATUSES = {
    "catalogue-candidate",
    "instruction-only",
    "context-only",
    "conflict",
    "unresolved",
}
INSTRUCTION_ONLY_ACTIONS = {"wait", "select", "choose", "menu", "warning"}
CONTEXT_REASONS = {"heading", "historical-explanation", "reward", "optional-background"}
ENEMY_IDENTITY_SCHEMA_REVISION = "v1"
ENEMY_CLUSTER_POLICY_VERSION = "complete-link-v1-h120-y24"


def _clean(value: object) -> str:
    return " ".join(str(value or "").split())


def _strings(value: object, field: str, *, required: bool = False) -> tuple[str, ...]:
    if not isinstance(value, (list, tuple)):
        raise ObjectiveDestinationError(f"Reviewed objective destination {field} must be a list.")
    result: list[str] = []
    seen: set[str] = set()
    for raw in value:
        item = _clean(raw)
        key = item.casefold()
        if item and key not in seen:
            result.append(item)
            seen.add(key)
    if required and not result:
        raise ObjectiveDestinationError(f"Reviewed objective destination {field} is empty.")
    return tuple(result)


def _override_rows(
    reviewed_overrides: Mapping[str, Any] | None,
    native: NativeObjective,
) -> tuple[tuple[Mapping[str, Any], bool], ...]:
    if not isinstance(reviewed_overrides, Mapping):
        return ()
    shared = reviewed_overrides.get("objective_destination_overrides", {})
    legacy = reviewed_overrides.get("mission_destination_overrides", {})
    rows: list[tuple[Mapping[str, Any], bool]] = []
    if isinstance(shared, Mapping) and native.key in shared:
        raw_rows = shared[native.key]
        if not isinstance(raw_rows, list) or any(not isinstance(row, Mapping) for row in raw_rows):
            raise ObjectiveDestinationError(
                f"Reviewed objective destinations for {native.key!r} must be a list of objects."
            )
        rows.extend((row, False) for row in raw_rows)
    if native.kind == "mission" and isinstance(legacy, Mapping) and native.key in legacy:
        raw_rows = legacy[native.key]
        if not isinstance(raw_rows, list) or any(not isinstance(row, Mapping) for row in raw_rows):
            raise ObjectiveDestinationError(
                f"Legacy mission destinations for {native.key!r} must be a list of objects."
            )
        rows.extend((row, True) for row in raw_rows)
    return tuple(rows)


def _claims_action(span: SourceActionSpan, action: str) -> bool:
    if span.action == action:
        return True
    if action in {"farm", "obtain"} and span.action == "fight" and span.result_relation == "obtain-from":
        return True
    return action == "obtain" and span.action == "obtain"


def _source_claim_rows(
    source_step_ids: tuple[str, ...],
    reconciled: ReconciledObjective,
) -> tuple[tuple[ReconciledStep, ReconciledActionClaim], ...]:
    step_lookup = {step.stable_step_id: step for step in reconciled.steps}
    result: list[tuple[ReconciledStep, ReconciledActionClaim]] = []
    for stable_step_id in source_step_ids:
        step = step_lookup.get(stable_step_id)
        if step is None:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination references unknown step {stable_step_id!r}."
            )
        result.extend((step, claim) for claim in step.claims)
    return tuple(result)


def _claim_source_spans(
    step: ReconciledStep,
    claim: ReconciledActionClaim,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
) -> dict[str, tuple[SourceActionSpan, ...]]:
    source_pages = {"bg": bg, "ffxiclopedia": ffxiclopedia}
    span_orders = {"bg": claim.bg_span_order, "ffxiclopedia": claim.ffxiclopedia_span_order}
    result: dict[str, tuple[SourceActionSpan, ...]] = {}
    for source_index, site in enumerate(("bg", "ffxiclopedia")):
        page = source_pages[site]
        source_order = step.source_orders[source_index]
        span_order = span_orders[site]
        if page is None or source_order <= 0 or span_order <= 0:
            result[site] = ()
            continue
        source_step = next((row for row in page.steps if row.order == source_order), None)
        source_span = (
            next((span for span in source_step.action_spans if span.order == span_order), None)
            if source_step is not None
            else None
        )
        result[site] = (source_span,) if source_span is not None else ()
    return result


def _span_supports_destination(
    span: SourceActionSpan,
    *,
    action: str,
    target_name: str,
    target_kind: str,
    zone_name: str,
    items: tuple[str, ...],
    enemies: tuple[str, ...],
    result_relation: str,
    map_numbers: tuple[str, ...],
    grid_coordinates: tuple[str, ...],
) -> bool:
    if not _claims_action(span, action):
        return False
    compatible_kinds = {target_kind}
    if target_kind == "area":
        compatible_kinds.add("object")
    if span.target_kind not in compatible_kinds:
        return False
    kind_field = {
        "npc": "npc_mentions",
        "object": "object_mentions",
        "area": "object_mentions",
        "enemy": "enemy_mentions",
        "transport": "transport_mentions",
        "question-mark": "object_mentions",
    }.get(target_kind, "")
    typed_mentions = tuple(getattr(span, kind_field)) if kind_field else ()
    if not span.target and len({value.casefold() for value in typed_mentions}) > 1:
        return False
    targets = {span.target.casefold()} if span.target else set()
    if kind_field:
        targets.update(value.casefold() for value in typed_mentions)
    if target_name.casefold() not in targets:
        return False
    if zone_name.casefold() not in {value.casefold() for value in span.zone_mentions}:
        return False
    item_claims = {
        value.casefold()
        for value in (*span.item_mentions, *span.key_item_mentions, *span.result_items)
    }
    enemy_claims = {value.casefold() for value in span.enemy_mentions}
    if any(value.casefold() not in item_claims for value in items):
        return False
    if any(value.casefold() not in enemy_claims for value in enemies):
        return False
    if result_relation and span.result_relation.casefold() != result_relation.casefold():
        return False
    map_claims = {value.casefold() for value in span.map_numbers}
    grid_claims = {value.casefold() for value in span.grid_coordinates}
    if any(value.casefold() not in map_claims for value in map_numbers):
        return False
    if any(value.casefold() not in grid_claims for value in grid_coordinates):
        return False
    return True


def _select_source_claim(
    source_step_ids: tuple[str, ...],
    requested_claim_ids: tuple[str, ...],
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    *,
    action: str,
    target_name: str,
    target_kind: str,
    zone_name: str,
    items: tuple[str, ...],
    enemies: tuple[str, ...],
    result_relation: str,
    map_numbers: tuple[str, ...],
    grid_coordinates: tuple[str, ...],
) -> tuple[tuple[str, ...], dict[str, tuple[SourceActionSpan, ...]]]:
    claim_rows = _source_claim_rows(source_step_ids, reconciled)
    if len(requested_claim_ids) > 1:
        raise ObjectiveDestinationError("Reviewed objective destination must select exactly one source claim.")
    if requested_claim_ids:
        selected = [row for row in claim_rows if row[1].stable_claim_id == requested_claim_ids[0]]
        if len(selected) != 1:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination references unknown claim {requested_claim_ids[0]!r}."
            )
    else:
        selected = list(claim_rows)

    matches: list[
        tuple[ReconciledStep, ReconciledActionClaim, dict[str, tuple[SourceActionSpan, ...]]]
    ] = []
    for step, claim in selected:
        if claim.comparison == "conflict":
            continue
        source_spans = _claim_source_spans(step, claim, bg, ffxiclopedia)
        if any(
            _span_supports_destination(
                span,
                action=action,
                target_name=target_name,
                target_kind=target_kind,
                zone_name=zone_name,
                items=items,
                enemies=enemies,
                result_relation=result_relation,
                map_numbers=map_numbers,
                grid_coordinates=grid_coordinates,
            )
            for spans in source_spans.values()
            for span in spans
        ):
            matches.append((step, claim, source_spans))
    if len(matches) != 1:
        reason = "conflicted or unsupported" if requested_claim_ids else "ambiguous or unsupported"
        raise ObjectiveDestinationError(f"Reviewed objective destination source claim is {reason}.")
    _step, claim, source_spans = matches[0]
    return (claim.stable_claim_id,), source_spans


def _point_tuple(point: Mapping[str, Any]) -> tuple[float, float, float]:
    values = (point.get("x"), point.get("z"), point.get("y"))
    if any(value is None or str(value).strip() == "" for value in values):
        raise ObjectiveDestinationError("Reviewed objective destination lacks complete target coordinates.")
    result = tuple(float(value) for value in values)
    if not all(math.isfinite(value) for value in result):
        raise ObjectiveDestinationError("Reviewed objective destination has non-finite target coordinates.")
    return result  # type: ignore[return-value]


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-") or "target"


def _unique_values(values: Iterable[object]) -> tuple[str, ...]:
    result: list[str] = []
    seen: set[str] = set()
    for raw in values:
        value = _clean(raw)
        key = value.casefold()
        if value and key not in seen:
            seen.add(key)
            result.append(value)
    return tuple(result)


def _point_spawn_ids(point: Mapping[str, Any]) -> tuple[int, ...]:
    raw = point.get("raw_spawn_ids", ())
    if isinstance(raw, str):
        values = tuple(int(value) for value in raw.split(",") if value.strip())
    elif isinstance(raw, (tuple, list)):
        values = tuple(int(value) for value in raw)
    else:
        return ()
    return values


def _enemy_destination_id(
    zone: int,
    raw_identity: str,
    raw_spawn_ids: tuple[int, ...],
    policy_version: str,
) -> str:
    raw_name = raw_identity.split(":mobname:", 1)[-1]
    payload = "\n".join(
        (
            ENEMY_IDENTITY_SCHEMA_REVISION,
            str(zone),
            raw_identity,
            ",".join(str(value) for value in raw_spawn_ids),
            policy_version,
        )
    ).encode("utf-8")
    digest = hashlib.sha256(payload).hexdigest()[:20]
    return f"camp:{ENEMY_IDENTITY_SCHEMA_REVISION}:{zone}:{_slug(raw_name)}:{digest}"


def navigation_point_has_immutable_identity(point: Mapping[str, Any]) -> bool:
    try:
        zone = int(point.get("zone", 0) or 0)
        point_tuple = _point_tuple(point)
    except (ObjectiveDestinationError, TypeError, ValueError):
        return False
    if zone <= 0 or not all(math.isfinite(value) for value in point_tuple):
        return False
    kind = _clean(point.get("kind", "")).casefold()
    destination_id = _clean(point.get("destination_id", ""))
    raw_identity = _clean(point.get("raw_identity", ""))
    if kind not in {"npc", "object", "area", "enemy"} or not destination_id or not raw_identity:
        return False
    if kind == "enemy":
        spawn_ids = _point_spawn_ids(point)
        policy = _clean(point.get("cluster_policy_version", ""))
        if (
            policy != ENEMY_CLUSTER_POLICY_VERSION
            or not re.fullmatch(r"lsb:mob_spawn_points:group:[0-9]+:mobname:.+", raw_identity)
            or not spawn_ids
            or tuple(sorted(spawn_ids)) != spawn_ids
            or len(spawn_ids) != len(set(spawn_ids))
            or any(value <= 0 for value in spawn_ids)
        ):
            return False
        return destination_id == _enemy_destination_id(zone, raw_identity, spawn_ids, policy)
    match = re.fullmatch(r"(npc|object|area):v1:([0-9]+):([0-9]+)", destination_id)
    raw_match = re.fullmatch(r"lsb:(npc_list|zonelines):([0-9]+)", raw_identity)
    return bool(
        match
        and raw_match
        and match.group(1) == kind
        and int(match.group(2)) == zone
        and raw_match.group(2) == match.group(3)
        and (raw_match.group(1) == "npc_list" or kind == "area")
        and not _point_spawn_ids(point)
        and not _clean(point.get("cluster_policy_version", ""))
    )


def _logical_navigation_points(
    points: Iterable[Mapping[str, Any]],
) -> tuple[Mapping[str, Any], ...]:
    """Collapse only rows at exactly the same complete physical coordinates."""

    groups: dict[tuple[float, float, float], list[Mapping[str, Any]]] = {}
    for point in points:
        groups.setdefault(_point_tuple(point), []).append(point)

    def representative(rows: list[Mapping[str, Any]]) -> Mapping[str, Any]:
        return min(
            rows,
            key=lambda point: (
                0 if navigation_point_has_immutable_identity(point) else 1,
                _clean(point.get("destination_id", "")),
                _clean(point.get("raw_identity", "")),
                _clean(point.get("source", "")),
            ),
        )

    return tuple(representative(groups[coordinates]) for coordinates in sorted(groups))


def _source_pages(
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
) -> dict[str, ParsedObjective | None]:
    return {"bg": bg, "ffxiclopedia": ffxiclopedia}


def _validate_action_override_revisions(
    action_id: str,
    raw: Mapping[str, Any],
    pages: Mapping[str, ParsedObjective | None],
) -> None:
    revisions = raw.get("source_revisions")
    if not isinstance(revisions, Mapping):
        raise ObjectiveDestinationError(f"Action override {action_id!r} lacks source revisions.")
    expected = {
        site: page.revision_id
        for site, page in pages.items()
        if page is not None
    }
    actual = {str(site): int(value or 0) for site, value in revisions.items()}
    if actual != expected:
        raise ObjectiveDestinationError(
            f"Action override {action_id!r} no longer matches all applicable source revisions."
        )


def _mapping_row(
    reviewed_overrides: Mapping[str, Any] | None,
    section: str,
    action_id: str,
) -> Mapping[str, Any] | None:
    root = reviewed_overrides.get(section, {}) if isinstance(reviewed_overrides, Mapping) else {}
    if not isinstance(root, Mapping):
        raise ObjectiveDestinationError(f"Reviewed override section {section!r} must be an object.")
    value = root.get(action_id)
    if value is None:
        return None
    if not isinstance(value, Mapping):
        raise ObjectiveDestinationError(f"Reviewed action override {action_id!r} must be an object.")
    return value


def _location_fact_rows(
    *,
    native: NativeObjective,
    action_id: str,
    raw: Mapping[str, Any],
    pages: Mapping[str, ParsedObjective | None],
    target: str,
) -> tuple[tuple[str, str, str, int, tuple[str, ...]], ...]:
    facts = raw.get("location_facts", ())
    if facts in (None, ()):
        return ()
    if not isinstance(facts, list) or any(not isinstance(fact, Mapping) for fact in facts):
        raise ObjectiveDestinationError(f"Single-source zone override {action_id!r} has malformed location facts.")
    result: list[tuple[str, str, str, int, tuple[str, ...]]] = []
    seen_fact_ids: set[str] = set()
    for fact in facts:
        site = _clean(fact.get("source_site", "")).casefold()
        page = pages.get(site)
        source_step_id = _clean(fact.get("source_step_id", ""))
        if site not in {"bg", "ffxiclopedia"} or page is None:
            raise ObjectiveDestinationError(f"Location fact for {action_id!r} names an unavailable source site.")
        source_step = next(
            (
                step
                for step in page.steps
                if source_step_id == f"{native.key}:{site}:step-{step.order:03d}"
            ),
            None,
        )
        configured_target = _clean(fact.get("target", ""))
        configured_zones = _strings(fact.get("zones"), "location_facts.zones", required=True)
        actual_zones = tuple(_clean(value) for value in source_step.zone_candidates) if source_step else ()
        linked_entities = {
            _clean(value).casefold()
            for value in source_step.linked_entities
        } if source_step else set()
        if (
            source_step is None
            or source_step.action != "note"
            or source_step.action_spans
            or _clean(fact.get("relationship", "")).casefold() != "target-location"
            or configured_target.casefold() != target.casefold()
            or configured_target.casefold() not in linked_entities
            or tuple(value.casefold() for value in configured_zones)
            != tuple(value.casefold() for value in actual_zones)
            or re.search(
                rf"\b{re.escape(configured_target)}\b\s+can\s+be\s+found\s+(?:in|at)\b",
                source_step.spoken_text,
                re.IGNORECASE,
            )
            is None
        ):
            raise ObjectiveDestinationError(
                f"Location fact for {action_id!r} no longer matches its exact source step."
            )
        fact_id = f"{source_step_id}:location-fact-01"
        if fact_id in seen_fact_ids:
            raise ObjectiveDestinationError(f"Location fact for {action_id!r} is duplicated.")
        seen_fact_ids.add(fact_id)
        result.append((site, source_step_id, fact_id, page.revision_id, configured_zones))
    return tuple(result)


def _span_rows(
    native: NativeObjective,
    step: ReconciledStep,
    claim: ReconciledActionClaim,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
) -> tuple[tuple[str, SourceActionSpan, str, int], ...]:
    spans = _claim_source_spans(step, claim, bg, ffxiclopedia)
    source_orders = {"bg": step.source_orders[0], "ffxiclopedia": step.source_orders[1]}
    result: list[tuple[str, SourceActionSpan, str, int]] = []
    for site in ("bg", "ffxiclopedia"):
        page = bg if site == "bg" else ffxiclopedia
        for span in spans.get(site, ()):
            span_id = (
                f"{native.key}:{site}:step-{source_orders[site]:03d}:span-{span.order:02d}"
            )
            result.append((site, span, span_id, page.revision_id if page is not None else 0))
    return tuple(result)


def _context_span_ids(native: NativeObjective, step: ReconciledStep) -> tuple[str, ...]:
    result: list[str] = []
    for site, source_order in zip(("bg", "ffxiclopedia"), step.source_orders):
        if source_order > 0:
            result.append(f"{native.key}:{site}:step-{source_order:03d}:context")
    return tuple(result)


def _instruction(step: ReconciledStep) -> str:
    return _clean(step.bg_instruction) or _clean(step.ffxiclopedia_instruction)


def _coordinate_evidence(
    span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...],
) -> tuple[tuple[tuple[str, str, str], ...], str]:
    support: list[tuple[str, str, str]] = []
    per_site: dict[str, set[tuple[str, str]]] = {}
    for site, span, _span_id, _revision in span_rows:
        values = {
            *(('map', value) for value in span.map_numbers),
            *(('grid', value) for value in span.grid_coordinates),
        }
        per_site[site] = values
        support.extend((site, kind, value) for kind, value in sorted(values))
    populated = [values for values in per_site.values() if values]
    if not populated:
        comparison = "none"
    elif len(populated) == 1:
        comparison = "single-source"
    elif populated[0] == populated[1]:
        comparison = "corroborated"
    elif populated[0].intersection(populated[1]):
        comparison = "partial"
    else:
        comparison = "conflict"
    return tuple(support), comparison


def _normalized_action(value: object) -> str:
    action = _clean(value).casefold()
    return "fight" if action == "farm" else action


def _normalized_relationship(value: object) -> str:
    relationship = re.sub(r"[^a-z0-9]+", "-", _clean(value).casefold()).strip("-")
    return {
        "defeat-enemy": "defeat",
        "defeat-target": "defeat",
        "defeat-to-obtain": "defeat",
        "fight-target": "defeat",
        "kill-target": "defeat",
    }.get(relationship, relationship)


def _source_kind_supports_claim(source_kind: str, claim_kind: str, action: str) -> bool:
    source_kind = _clean(source_kind).casefold()
    claim_kind = _clean(claim_kind).casefold()
    if not source_kind or not claim_kind:
        return False
    if source_kind == claim_kind:
        return True
    return action in {"examine", "use", "travel"} and {
        source_kind,
        claim_kind,
    }.issubset({"area", "object"})


def _candidate_id(action_id: str, destination_id: str) -> str:
    digest = hashlib.sha256(f"{action_id}\n{destination_id}".encode("utf-8")).hexdigest()[:20]
    return f"{action_id}:candidate:{digest}"


def _review_item_id(action_id: str, zone_name: str, reason: str) -> str:
    digest = hashlib.sha256(
        f"{action_id}\n{zone_name.casefold()}\n{reason}".encode("utf-8")
    ).hexdigest()[:20]
    return f"{action_id}:review:{digest}"


def _format_items(items: tuple[str, ...]) -> str:
    if len(items) <= 1:
        return items[0] if items else "the required item"
    return ", ".join(items[:-1]) + f", and {items[-1]}"


def _arrival_instruction(
    action: str,
    target: str,
    zone_name: str,
    items: tuple[str, ...],
) -> str:
    if action == "talk":
        return f"Talk to {target} in {zone_name}."
    if action == "trade":
        return f"Trade {_format_items(items)} to {target} in {zone_name}."
    if action == "examine":
        return f"Examine {target} in {zone_name}."
    if action == "use":
        return f"Use {target} in {zone_name}."
    if action == "fight":
        suffix = f" to obtain {_format_items(items)}" if items else ""
        return f"Defeat {target} in {zone_name}{suffix}."
    if action == "obtain":
        return f"Obtain {_format_items(items)} from {target} in {zone_name}."
    if action == "travel":
        return f"Travel through {target} in {zone_name}."
    return f"Use {target} in {zone_name}."


def _claim_items(span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...]) -> tuple[str, ...]:
    return _unique_values(
        value
        for _site, span, _span_id, _revision in span_rows
        for value in (*span.result_items, *span.item_mentions)
    )


def _claim_enemies(span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...]) -> tuple[str, ...]:
    return _unique_values(
        value
        for _site, span, _span_id, _revision in span_rows
        for value in (*span.enemy_mentions, *((span.target,) if span.target_kind == "enemy" else ()))
    )


def _claim_result_relation(span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...]) -> str:
    relations = _unique_values(span.result_relation for _site, span, _span_id, _revision in span_rows)
    return relations[0] if len(relations) == 1 else ""


def _point_candidate(
    *,
    action_id: str,
    action: str,
    point: Mapping[str, Any],
    zone_name: str,
    span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...],
    support_sites: tuple[str, ...],
    evidence_level: str,
    support_span_ids: tuple[str, ...] = (),
    support_revisions: tuple[tuple[str, int], ...] = (),
    group_id: str = "",
    metadata_class: str = "",
    transport_id: str = "",
    battlefield_id: str = "",
) -> ObjectiveDestinationCandidate:
    destination_id = _clean(point.get("destination_id", ""))
    if support_span_ids:
        selected_span_ids = set(support_span_ids)
        source_rows = tuple(row for row in span_rows if row[2] in selected_span_ids)
    else:
        source_rows = tuple(row for row in span_rows if row[0] in support_sites)
    coordinate_support, coordinate_comparison = _coordinate_evidence(source_rows)
    items = _claim_items(source_rows)
    enemies = _claim_enemies(source_rows)
    target_name = _clean(point.get("name", ""))
    return ObjectiveDestinationCandidate(
        candidate_id=_candidate_id(action_id, destination_id),
        action_id=action_id,
        source_action_span_ids=(
            support_span_ids if support_span_ids else tuple(row[2] for row in source_rows)
        ),
        source_sites=support_sites,
        source_revisions=(
            support_revisions
            if support_revisions
            else tuple((row[0], row[3]) for row in source_rows)
        ),
        coordinate_support=coordinate_support,
        coordinate_comparison=coordinate_comparison,
        action=action,
        items=items,
        enemies=enemies,
        result_relation=_claim_result_relation(source_rows),
        destination_id=destination_id,
        zone=int(point.get("zone", 0) or 0),
        zone_name=zone_name,
        target_name=target_name,
        target_kind=_clean(point.get("kind", "")).casefold(),
        target_point=_point_tuple(point),
        raw_identity=_clean(point.get("raw_identity", "")),
        raw_spawn_ids=_point_spawn_ids(point),
        cluster_policy_version=_clean(point.get("cluster_policy_version", "")),
        evidence_level=evidence_level,
        group_id=group_id,
        metadata_class=metadata_class,
        transport_id=transport_id,
        battlefield_id=battlefield_id,
        label=f"{target_name} in {zone_name}",
        arrival_instruction=_arrival_instruction(action, target_name, zone_name, items),
        route_ready=False,
    )


def _reviewed_candidates(
    *,
    native: NativeObjective,
    action_id: str,
    action: str,
    raw: Mapping[str, Any],
    pages: Mapping[str, ParsedObjective | None],
    span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...],
    points_by_id: Mapping[str, tuple[Mapping[str, Any], ...]],
    zone_names: Mapping[int, str],
    metadata_class: str,
) -> tuple[ObjectiveDestinationCandidate, ...]:
    _validate_action_override_revisions(action_id, raw, pages)
    raw_ids = raw.get("destination_ids")
    if not isinstance(raw_ids, list) or not raw_ids:
        raise ObjectiveDestinationError(f"Reviewed action override {action_id!r} lacks destination IDs.")
    destination_ids = _unique_values(raw_ids)
    if len(destination_ids) != len(raw_ids):
        raise ObjectiveDestinationError(f"Reviewed action override {action_id!r} repeats a destination ID.")
    source_sites = tuple(row[0] for row in span_rows)
    result: list[ObjectiveDestinationCandidate] = []
    for destination_id in destination_ids:
        matches = points_by_id.get(destination_id, ())
        if len(matches) != 1 or not navigation_point_has_immutable_identity(matches[0]):
            raise ObjectiveDestinationError(
                f"Reviewed action override {action_id!r} does not resolve one immutable destination {destination_id!r}."
            )
        point = matches[0]
        zone = int(point.get("zone", 0) or 0)
        zone_name = _clean(zone_names.get(zone, ""))
        point_name = _clean(point.get("name", ""))
        point_kind = _clean(point.get("kind", "")).casefold()
        typed_source_spans = tuple(
            span
            for _site, span, _span_id, _revision in span_rows
            if _normalized_action(span.action) == action
        )
        if (
            not typed_source_spans
            or any(
                not span.target or span.target.casefold() != point_name.casefold()
                for span in typed_source_spans
            )
        ):
            raise ObjectiveDestinationError(
                f"Reviewed action override {action_id!r} destination does not match its typed source target."
            )
        if point_kind not in ACTION_KINDS.get(action, ()):
            raise ObjectiveDestinationError(
                f"Reviewed action override {action_id!r} has an incompatible destination kind."
            )
        if any(
            zone_name.casefold()
            not in {value.casefold() for value in span.zone_mentions}
            for span in typed_source_spans
        ):
            raise ObjectiveDestinationError(
                f"Reviewed action override {action_id!r} destination zone is absent from its source zone evidence."
            )
        if metadata_class == "dynamic" and raw.get("target_point") is not None:
            target_point = raw.get("target_point")
            if not isinstance(target_point, (list, tuple)) or len(target_point) != 3:
                raise ObjectiveDestinationError(f"Dynamic action override {action_id!r} has malformed coordinates.")
            if tuple(float(value) for value in target_point) != _point_tuple(point):
                raise ObjectiveDestinationError(
                    f"Dynamic action override {action_id!r} coordinates disagree with its destination identity."
                )
        result.append(
            _point_candidate(
                action_id=action_id,
                action=action,
                point=point,
                zone_name=zone_name,
                span_rows=span_rows,
                support_sites=source_sites,
                evidence_level="reviewed",
                metadata_class=metadata_class,
                transport_id=_clean(raw.get("transport_id", "")),
                battlefield_id=_clean(raw.get("battlefield_id", "")),
            )
        )
    return tuple(result)


def _role_candidates(
    *,
    native: NativeObjective,
    action_id: str,
    action: str,
    raw: Mapping[str, Any],
    pages: Mapping[str, ParsedObjective | None],
    span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...],
    points_by_id: Mapping[str, tuple[Mapping[str, Any], ...]],
    zone_names: Mapping[int, str],
) -> tuple[ObjectiveDestinationCandidate, ...]:
    _validate_action_override_revisions(action_id, raw, pages)
    configured_roles = _strings(raw.get("source_roles"), "source_roles", required=True)
    source_roles = _unique_values(
        span.target
        for _site, span, _span_id, _revision in span_rows
        if span.target
    )
    source_relationships = {
        _normalized_relationship(span.relationship)
        for _site, span, _span_id, _revision in span_rows
        if _normalized_relationship(span.relationship)
    }
    if (
        {_clean(value).casefold() for value in configured_roles}
        != {_clean(value).casefold() for value in source_roles}
        or any(_normalized_action(span.action) != action for _site, span, _span_id, _revision in span_rows)
        or len(source_relationships) != 1
    ):
        raise ObjectiveDestinationError(f"Role override {action_id!r} does not match every typed source role.")
    allowed_zones = {value.casefold() for value in _strings(raw.get("allowed_zones"), "allowed_zones", required=True)}
    members = raw.get("members")
    if not isinstance(members, list) or not members or any(not isinstance(row, Mapping) for row in members):
        raise ObjectiveDestinationError(f"Role override {action_id!r} lacks exact member rows.")
    result: list[ObjectiveDestinationCandidate] = []
    source_sites = tuple(row[0] for row in span_rows)
    action_span_ids = tuple(row[2] for row in span_rows)
    action_revisions = tuple(dict.fromkeys((row[0], row[3]) for row in span_rows))
    for member in members:
        destination_id = _clean(member.get("destination_id", ""))
        matches = points_by_id.get(destination_id, ())
        if len(matches) != 1 or not navigation_point_has_immutable_identity(matches[0]):
            raise ObjectiveDestinationError(
                f"Role override {action_id!r} member {destination_id!r} is not one immutable point."
            )
        point = matches[0]
        zone = int(point.get("zone", 0) or 0)
        zone_name = _clean(zone_names.get(zone, ""))
        if _clean(point.get("kind", "")).casefold() != "npc":
            raise ObjectiveDestinationError(
                f"Role override {action_id!r} member must be an exact NPC destination."
            )
        source_site = _clean(member.get("source_site", "")).casefold()
        source_page = pages.get(source_site)
        source_step_id = _clean(member.get("source_step_id", ""))
        source_step = (
            next(
                (
                    step
                    for step in source_page.steps
                    if source_step_id == f"{native.key}:{source_site}:step-{step.order:03d}"
                ),
                None,
            )
            if source_page is not None
            else None
        )
        member_name = _clean(member.get("name", ""))
        source_entities = {
            _clean(value).casefold() for value in source_step.linked_entities
        } if source_step else set()
        if (
            zone != int(member.get("zone", 0) or 0)
            or _clean(point.get("name", "")).casefold() != member_name.casefold()
            or zone_name.casefold() not in allowed_zones
            or source_page is None
            or source_step is None
            or source_step.action != "note"
            or source_step.action_spans
            or member_name.casefold() not in source_entities
            or tuple(value.casefold() for value in source_step.zone_candidates)
            != (zone_name.casefold(),)
        ):
            raise ObjectiveDestinationError(f"Role override {action_id!r} member metadata is stale.")
        member_fact_id = f"{source_step_id}:role-member-fact-01"
        support_revisions = tuple(
            dict.fromkeys((*action_revisions, (source_site, source_page.revision_id)))
        )
        result.append(
            _point_candidate(
                action_id=action_id,
                action=action,
                point=point,
                zone_name=zone_name,
                span_rows=span_rows,
                support_sites=source_sites,
                support_span_ids=tuple((*action_span_ids, member_fact_id)),
                support_revisions=support_revisions,
                evidence_level="reviewed-role-members",
                metadata_class="role",
            )
        )
    return tuple(result)


def _claim_resolution(
    *,
    native: NativeObjective,
    step: ReconciledStep,
    claim: ReconciledActionClaim,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    reviewed_overrides: Mapping[str, Any] | None,
    points: tuple[Mapping[str, Any], ...],
    points_by_id: Mapping[str, tuple[Mapping[str, Any], ...]],
    zone_names: Mapping[int, str],
) -> tuple[ObjectiveActionLedgerRow, tuple[ObjectiveDestinationCandidate, ...], tuple[ObjectiveDestinationGroup, ...], tuple[ObjectiveResolutionReviewItem, ...]]:
    action_id = claim.stable_claim_id
    span_rows = _span_rows(native, step, claim, bg, ffxiclopedia)
    span_ids = tuple(row[2] for row in span_rows)
    action = "fight" if claim.action == "farm" else claim.action
    instruction = _instruction(step)
    coordinate_support, coordinate_comparison = _coordinate_evidence(span_rows)
    pages = _source_pages(bg, ffxiclopedia)
    role_override = _mapping_row(reviewed_overrides, "role_overrides", action_id)
    if (claim.comparison == "conflict" and role_override is None) or coordinate_comparison == "conflict":
        return (
            ObjectiveActionLedgerRow(
                action_id, span_ids, action, "conflict", "source-conflict", (), "", True
            ),
            (),
            (),
            (),
        )
    if action in INSTRUCTION_ONLY_ACTIONS and instruction:
        return (
            ObjectiveActionLedgerRow(
                action_id,
                span_ids,
                action,
                "instruction-only",
                "complete-instruction",
                (),
                instruction,
                True,
            ),
            (),
            (),
            (),
        )

    instruction = ""

    target_kinds = _unique_values(span.target_kind for _site, span, _span_id, _revision in span_rows)
    targets = _unique_values(span.target for _site, span, _span_id, _revision in span_rows)
    if len(targets) > 1 and role_override is None:
        return (
            ObjectiveActionLedgerRow(
                action_id, span_ids, action, "conflict", "source-conflict", (), instruction, True
            ),
            (),
            (),
            (),
        )
    target = targets[0] if targets else ""
    target_kind = target_kinds[0] if len(target_kinds) == 1 else ""

    if target_kind == "role" or role_override is not None:
        if role_override is None:
            reason = "ambiguous-static-reference"
            candidates: tuple[ObjectiveDestinationCandidate, ...] = ()
        else:
            candidates = _role_candidates(
                native=native,
                action_id=action_id,
                action=action,
                raw=role_override,
                pages=pages,
                span_rows=span_rows,
                points_by_id=points_by_id,
                zone_names=zone_names,
            )
            reason = "reviewed-role-members"
        role_span_ids = tuple(
            dict.fromkeys(
                (
                    *span_ids,
                    *(
                        source_id
                        for candidate in candidates
                        for source_id in candidate.source_action_span_ids
                    ),
                )
            )
        )
        return (
            ObjectiveActionLedgerRow(
                action_id,
                role_span_ids,
                action,
                "catalogue-candidate" if candidates else "unresolved",
                reason,
                tuple(candidate.candidate_id for candidate in candidates),
                instruction,
                True,
            ),
            candidates,
            (),
            (),
        )

    dynamic_override = _mapping_row(reviewed_overrides, "dynamic_target_overrides", action_id)
    if target_kind == "question-mark" or target == "???":
        if dynamic_override is None:
            candidates = ()
            reason = "dynamic-identity-required"
        else:
            candidates = _reviewed_candidates(
                native=native,
                action_id=action_id,
                action=action,
                raw=dynamic_override,
                pages=pages,
                span_rows=span_rows,
                points_by_id=points_by_id,
                zone_names=zone_names,
                metadata_class="dynamic",
            )
            reason = "reviewed-dynamic-target"
        return (
            ObjectiveActionLedgerRow(
                action_id,
                span_ids,
                action,
                "catalogue-candidate" if candidates else "unresolved",
                reason,
                tuple(candidate.candidate_id for candidate in candidates),
                instruction,
                True,
            ),
            candidates,
            (),
            (),
        )

    metadata_override = _mapping_row(reviewed_overrides, "action_metadata_overrides", action_id)
    if target_kind in {"transport", "entrance"}:
        expected_class = "transport" if target_kind == "transport" else "battlefield"
        if metadata_override is None or _clean(metadata_override.get("class", "")).casefold() != expected_class:
            candidates = ()
            reason = "transport-metadata-required" if target_kind == "transport" else "no-exact-catalogue-match"
        else:
            if expected_class == "transport" and not _clean(metadata_override.get("transport_id", "")):
                raise ObjectiveDestinationError(f"Transport override {action_id!r} lacks transport_id.")
            if expected_class == "battlefield" and not _clean(metadata_override.get("battlefield_id", "")):
                raise ObjectiveDestinationError(f"Battlefield override {action_id!r} lacks battlefield_id.")
            candidates = _reviewed_candidates(
                native=native,
                action_id=action_id,
                action=action,
                raw=metadata_override,
                pages=pages,
                span_rows=span_rows,
                points_by_id=points_by_id,
                zone_names=zone_names,
                metadata_class=expected_class,
            )
            reason = (
                "reviewed-transport-metadata"
                if expected_class == "transport"
                else "reviewed-battlefield-metadata"
            )
        return (
            ObjectiveActionLedgerRow(
                action_id,
                span_ids,
                action,
                "catalogue-candidate" if candidates else "unresolved",
                reason,
                tuple(candidate.candidate_id for candidate in candidates),
                instruction,
                True,
            ),
            candidates,
            (),
            (),
        )

    if action not in ACTION_KINDS:
        return (
            ObjectiveActionLedgerRow(
                action_id,
                span_ids,
                action,
                "unresolved",
                "unsupported-target-class",
                (),
                instruction,
                True,
            ),
            (),
            (),
            (),
        )
    if not target:
        return (
            ObjectiveActionLedgerRow(
                action_id, span_ids, action, "unresolved", "missing-action-target", (), instruction, True
            ),
            (),
            (),
            (),
        )

    expected_relationship = _normalized_relationship(claim.relationship)
    if not expected_relationship:
        relationships = {
            _normalized_relationship(span.relationship)
            for _site, span, _span_id, _revision in span_rows
            if _normalized_action(span.action) == action
            and span.target.casefold() == target.casefold()
            and _source_kind_supports_claim(span.target_kind, target_kind, action)
            and _normalized_relationship(span.relationship)
        }
        expected_relationship = next(iter(relationships)) if len(relationships) == 1 else ""

    zone_support: dict[str, list[str]] = {}
    zone_support_ids: dict[str, list[str]] = {}
    zone_support_revisions: dict[str, dict[str, int]] = {}
    typed_span_ids_by_site: dict[str, list[str]] = {}
    zone_display: dict[str, str] = {}
    for site, span, source_span_id, revision in span_rows:
        if (
            not span.target
            or span.target.casefold() != target.casefold()
            or _normalized_action(span.action) != action
            or not _source_kind_supports_claim(span.target_kind, target_kind, action)
            or not expected_relationship
            or _normalized_relationship(span.relationship) != expected_relationship
        ):
            continue
        typed_span_ids_by_site.setdefault(site, []).append(source_span_id)
        for zone_name in span.zone_mentions:
            key = zone_name.casefold()
            zone_display.setdefault(key, zone_name)
            if site not in zone_support.setdefault(key, []):
                zone_support[key].append(site)
            if source_span_id not in zone_support_ids.setdefault(key, []):
                zone_support_ids[key].append(source_span_id)
            zone_support_revisions.setdefault(key, {})[site] = revision

    single_source_override = _mapping_row(
        reviewed_overrides, "single_source_zone_overrides", action_id
    )
    reviewed_single_zones: set[str] = set()
    fact_ids: list[str] = []
    if single_source_override is not None:
        _validate_action_override_revisions(action_id, single_source_override, pages)
        if (
            _clean(single_source_override.get("action", "")).casefold() != action
            or _clean(single_source_override.get("target", "")).casefold() != target.casefold()
        ):
            raise ObjectiveDestinationError(f"Single-source zone override {action_id!r} is stale.")
        reviewed_single_zones = {
            value.casefold()
            for value in _strings(
                single_source_override.get("allowed_zones"), "allowed_zones", required=True
            )
        }
        location_facts = _location_fact_rows(
            native=native,
            action_id=action_id,
            raw=single_source_override,
            pages=pages,
            target=target,
        )
        for site, _source_step_id, fact_id, revision, fact_zones in location_facts:
            fact_ids.append(fact_id)
            for zone_name in fact_zones:
                key = zone_name.casefold()
                zone_display.setdefault(key, zone_name)
                if site not in zone_support.setdefault(key, []):
                    zone_support[key].append(site)
                for source_span_id in typed_span_ids_by_site.get(site, ()):
                    if source_span_id not in zone_support_ids.setdefault(key, []):
                        zone_support_ids[key].append(source_span_id)
                if fact_id not in zone_support_ids.setdefault(key, []):
                    zone_support_ids[key].append(fact_id)
                zone_support_revisions.setdefault(key, {})[site] = revision
        if not reviewed_single_zones.issubset(zone_support):
            raise ObjectiveDestinationError(
                f"Single-source zone override {action_id!r} allows a zone absent from exact source evidence."
            )

    if fact_ids:
        span_ids = tuple((*span_ids, *fact_ids))
    if not zone_support:
        return (
            ObjectiveActionLedgerRow(
                action_id, span_ids, action, "unresolved", "missing-zone", (), instruction, True
            ),
            (),
            (),
            (),
        )

    source_sites_present = tuple(dict.fromkeys(row[0] for row in span_rows))

    canonical_zones: dict[str, tuple[int, str]] = {}
    for zone, name in sorted(zone_names.items()):
        key = name.casefold()
        previous = canonical_zones.get(key)
        if previous is not None and previous[0] != zone:
            raise ObjectiveDestinationError(
                f"Navigation zone name {name!r} maps to both {previous[0]} and {zone}."
            )
        canonical_zones[key] = (zone, name)
    candidates: list[ObjectiveDestinationCandidate] = []
    groups: list[ObjectiveDestinationGroup] = []
    review_items: list[ObjectiveResolutionReviewItem] = []
    identity_missing = False
    exact_match_seen = False
    skipped_single_source = False
    used_reviewed_single = False
    for zone_key in sorted(zone_support):
        support_sites = tuple(zone_support[zone_key])
        dual_zone = len(support_sites) == 2
        single_page_claim = len(source_sites_present) == 1
        reviewed_zone = zone_key in reviewed_single_zones
        if not dual_zone and not single_page_claim and not reviewed_zone:
            skipped_single_source = True
            rejected_span_ids = tuple(zone_support_ids.get(zone_key, ()))
            review_items.append(
                ObjectiveResolutionReviewItem(
                    review_id=_review_item_id(
                        action_id,
                        zone_display.get(zone_key, zone_key),
                        "single-source-needs-independent-corroboration",
                    ),
                    action_id=action_id,
                    target_name=target,
                    zone_name=zone_display.get(zone_key, zone_key),
                    source_sites=support_sites,
                    source_action_span_ids=rejected_span_ids,
                    reason="single-source-needs-independent-corroboration",
                    route_ready=False,
                )
            )
            continue
        canonical = canonical_zones.get(zone_key)
        if canonical is None:
            continue
        zone, zone_name = canonical
        eligible_kinds = ACTION_KINDS[action]
        matches = [
            point
            for point in points
            if int(point.get("zone", 0) or 0) == zone
            and _clean(point.get("name", "")).casefold() == target.casefold()
            and _clean(point.get("kind", "")).casefold() in eligible_kinds
        ]
        if matches:
            exact_match_seen = True
        immutable = [point for point in matches if navigation_point_has_immutable_identity(point)]
        if matches and not immutable:
            identity_missing = True
            continue
        by_destination: dict[str, list[Mapping[str, Any]]] = {}
        for point in immutable:
            by_destination.setdefault(_clean(point.get("destination_id", "")), []).append(point)
        if any(len(rows) != 1 for rows in by_destination.values()):
            continue
        immutable = [rows[0] for _destination_id, rows in sorted(by_destination.items())]
        if action in {"talk", "trade", "examine", "use", "travel"} and len(immutable) != 1:
            continue
        if not immutable:
            continue
        evidence_level = "dual-source" if dual_zone else "single-source+game-data"
        reason_support_sites = support_sites
        group_id = f"{action_id}:zone:{zone}" if action in {"fight", "obtain"} else ""
        zone_candidates = tuple(
            _point_candidate(
                action_id=action_id,
                action=action,
                point=point,
                zone_name=zone_name,
                span_rows=span_rows,
                support_sites=reason_support_sites,
                support_span_ids=tuple(zone_support_ids.get(zone_key, ())),
                support_revisions=tuple(
                    (site, zone_support_revisions[zone_key][site])
                    for site in reason_support_sites
                ),
                evidence_level=evidence_level,
                group_id=group_id,
            )
            for point in immutable
        )
        candidates.extend(zone_candidates)
        if group_id:
            groups.append(
                ObjectiveDestinationGroup(
                    group_id=group_id,
                    action_id=action_id,
                    zone=zone,
                    zone_name=zone_name,
                    candidate_ids=tuple(candidate.candidate_id for candidate in zone_candidates),
                    evidence_level=evidence_level,
                    route_ready=False,
                )
            )
        used_reviewed_single = used_reviewed_single or reviewed_zone

    if candidates:
        reason = (
            "reviewed-single-source-zone"
            if used_reviewed_single
            else "dual-source-exact-catalogue-match"
            if any(len(sites) == 2 for sites in zone_support.values())
            else "single-source-independent-game-data"
        )
        status = "catalogue-candidate"
    elif skipped_single_source:
        reason = "single-source-needs-independent-corroboration"
        status = "unresolved"
    elif identity_missing:
        reason = "dynamic-identity-required"
        status = "unresolved"
    elif exact_match_seen:
        reason = "ambiguous-static-reference"
        status = "unresolved"
    else:
        reason = "no-exact-catalogue-match"
        status = "unresolved"
    candidates_tuple = tuple(candidates)
    groups_tuple = tuple(sorted(groups, key=lambda group: (group.zone_name.casefold(), group.group_id)))
    return (
        ObjectiveActionLedgerRow(
            action_id,
            span_ids,
            action,
            status,
            reason,
            tuple(candidate.candidate_id for candidate in candidates_tuple),
            instruction,
            True,
        ),
        candidates_tuple,
        groups_tuple,
        tuple(sorted(review_items, key=lambda item: (item.zone_name.casefold(), item.review_id))),
    )


def resolve_objective_actions(
    native: NativeObjective,
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    reviewed_overrides: Mapping[str, Any] | None,
    navigation_points: Iterable[Mapping[str, Any]],
    navigation_zone_names: Mapping[int, str],
) -> ObjectiveActionResolution:
    points = tuple(navigation_points)
    points_by_id_lists: dict[str, list[Mapping[str, Any]]] = {}
    for point in points:
        destination_id = _clean(point.get("destination_id", ""))
        if destination_id:
            points_by_id_lists.setdefault(destination_id, []).append(point)
    points_by_id = {key: tuple(rows) for key, rows in points_by_id_lists.items()}
    zone_names = {
        int(zone): _clean(name)
        for zone, name in navigation_zone_names.items()
        if int(zone) > 0 and _clean(name)
    }
    ledger: list[ObjectiveActionLedgerRow] = []
    candidates: list[ObjectiveDestinationCandidate] = []
    groups: list[ObjectiveDestinationGroup] = []
    review_items: list[ObjectiveResolutionReviewItem] = []
    consumed_fact_steps: set[str] = set()
    pages = _source_pages(bg, ffxiclopedia)
    for step in reconciled.steps:
        if step.claims:
            for claim in step.claims:
                ledger_row, action_candidates, action_groups, action_review_items = _claim_resolution(
                    native=native,
                    step=step,
                    claim=claim,
                    bg=bg,
                    ffxiclopedia=ffxiclopedia,
                    reviewed_overrides=reviewed_overrides,
                    points=points,
                    points_by_id=points_by_id,
                    zone_names=zone_names,
                )
                ledger.append(ledger_row)
                candidates.extend(action_candidates)
                groups.extend(action_groups)
                review_items.extend(action_review_items)
                for source_id in ledger_row.source_action_span_ids:
                    for suffix in (":location-fact-01", ":role-member-fact-01"):
                        if source_id.endswith(suffix):
                            consumed_fact_steps.add(source_id.removesuffix(suffix))
            continue

        action_id = f"{step.stable_step_id}:context-01"
        source_span_ids = _context_span_ids(native, step)
        source_step_ids = tuple(
            source_span_id.removesuffix(":context") for source_span_id in source_span_ids
        )
        if source_step_ids and set(source_step_ids).issubset(consumed_fact_steps):
            continue
        context_override = _mapping_row(reviewed_overrides, "context_overrides", action_id)
        if context_override is not None:
            _validate_action_override_revisions(action_id, context_override, pages)
            context_reason = _clean(context_override.get("reason", "")).casefold()
            if context_reason not in CONTEXT_REASONS:
                raise ObjectiveDestinationError(
                    f"Context override {action_id!r} lacks a supported non-material reason."
                )
            status = "context-only"
            reason = "non-material-context-reason"
            action = "context"
            material = False
        else:
            status = "unresolved"
            reason = "missing-action-target"
            action = step.action if step.action != "note" else "context"
            material = True
        ledger.append(
            ObjectiveActionLedgerRow(
                action_id=action_id,
                source_action_span_ids=source_span_ids,
                action=action,
                status=status,
                reason=reason,
                candidate_ids=(),
                instruction=_instruction(step) if status == "context-only" else "",
                material=material,
                route_ready=False,
            )
        )

    action_ids = [row.action_id for row in ledger]
    if len(action_ids) != len(set(action_ids)):
        raise ObjectiveDestinationError("Objective action-resolution ledger contains duplicate action IDs.")
    source_span_ids = [span_id for row in ledger for span_id in row.source_action_span_ids]
    if len(source_span_ids) != len(set(source_span_ids)):
        raise ObjectiveDestinationError("A source action span belongs to more than one reconciled action.")
    candidate_ids = [candidate.candidate_id for candidate in candidates]
    if len(candidate_ids) != len(set(candidate_ids)):
        raise ObjectiveDestinationError("Objective destination candidates contain duplicate candidate IDs.")
    ledger_by_id = {row.action_id: row for row in ledger}
    for candidate in candidates:
        parent = ledger_by_id.get(candidate.action_id)
        if parent is None or candidate.candidate_id not in parent.candidate_ids:
            raise ObjectiveDestinationError("Objective destination candidate has no exact parent ledger row.")
        if not set(candidate.source_action_span_ids).issubset(parent.source_action_span_ids):
            raise ObjectiveDestinationError("Objective destination candidate uses evidence outside its parent action.")
    for row in ledger:
        if row.status not in LEDGER_STATUSES or row.route_ready:
            raise ObjectiveDestinationError("Task 3 emitted an invalid or routable action status.")
        if (row.status == "catalogue-candidate") != bool(row.candidate_ids):
            raise ObjectiveDestinationError("Action ledger child cardinality disagrees with its primary status.")
    group_ids = [group.group_id for group in groups]
    if len(group_ids) != len(set(group_ids)):
        raise ObjectiveDestinationError("Objective destination groups contain duplicate group IDs.")
    candidate_by_id = {candidate.candidate_id: candidate for candidate in candidates}
    grouped_candidate_ids: set[str] = set()
    for group in groups:
        if group.route_ready or group.action_id not in ledger_by_id or not group.candidate_ids:
            raise ObjectiveDestinationError("Objective destination group has an invalid parent or route state.")
        if len(group.candidate_ids) != len(set(group.candidate_ids)):
            raise ObjectiveDestinationError("Objective destination group repeats a candidate.")
        for candidate_id in group.candidate_ids:
            candidate = candidate_by_id.get(candidate_id)
            if (
                candidate is None
                or candidate.group_id != group.group_id
                or candidate.action_id != group.action_id
                or candidate_id in grouped_candidate_ids
            ):
                raise ObjectiveDestinationError("Objective destination group membership is inconsistent.")
            grouped_candidate_ids.add(candidate_id)
    expected_grouped = {candidate.candidate_id for candidate in candidates if candidate.group_id}
    if grouped_candidate_ids != expected_grouped:
        raise ObjectiveDestinationError("Grouped objective candidates are not conserved exactly once.")
    review_ids = [item.review_id for item in review_items]
    if len(review_ids) != len(set(review_ids)):
        raise ObjectiveDestinationError("Objective resolution review items contain duplicate IDs.")
    for item in review_items:
        parent = ledger_by_id.get(item.action_id)
        if (
            item.route_ready
            or parent is None
            or not set(item.source_action_span_ids).issubset(parent.source_action_span_ids)
        ):
            raise ObjectiveDestinationError("Objective resolution review item has invalid provenance.")
    return ObjectiveActionResolution(
        tuple(ledger),
        tuple(candidates),
        tuple(groups),
        tuple(review_items),
    )


def _resolve_reviewed_objective_destinations_strict(
    native: NativeObjective,
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    reviewed_overrides: Mapping[str, Any] | None,
    navigation_points: Iterable[Mapping[str, Any]],
    navigation_zone_names: Mapping[int, str],
    navigation_edges: Iterable[Mapping[str, Any]] = (),
) -> tuple[ReviewedObjectiveDestination, ...]:
    rows = _override_rows(reviewed_overrides, native)
    if not rows:
        return ()
    pages = {"bg": bg, "ffxiclopedia": ffxiclopedia}
    points = tuple(navigation_points)
    edges = tuple(navigation_edges)
    results: list[ReviewedObjectiveDestination] = []
    seen_ids: set[str] = set()
    for raw, legacy in rows:
        short_id = _clean(raw.get("id", "")).casefold()
        if not _STABLE_ID.fullmatch(short_id):
            raise ObjectiveDestinationError(
                f"Reviewed objective destination for {native.key!r} has invalid id {short_id!r}."
            )
        stable_id = f"{native.key}:destination:{short_id}"
        if stable_id in seen_ids:
            raise ObjectiveDestinationError(f"Duplicate reviewed objective destination id {stable_id!r}.")
        seen_ids.add(stable_id)

        revisions = raw.get("source_revisions")
        if not isinstance(revisions, Mapping):
            raise ObjectiveDestinationError(f"Reviewed objective destination {stable_id!r} lacks source revisions.")
        for site in revisions:
            if site not in pages or pages[site] is None:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} pins unavailable source {site!r}."
                )
        for site, page in pages.items():
            if page is not None and int(revisions.get(site, 0) or 0) != page.revision_id:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} no longer matches its {site} revision."
                )

        source_step_ids = _strings(raw.get("source_step_ids"), "source_step_ids", required=True)
        source_claim_ids = _strings(raw.get("source_claim_ids", []), "source_claim_ids")
        action = _clean(raw.get("action", "")).casefold()
        if action not in _SUPPORTED_ACTIONS:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} has unsupported action {action!r}."
            )
        items = _strings(raw.get("items", []), "items")
        enemies = _strings(raw.get("enemies", []), "enemies")
        result_relation = _clean(raw.get("result_relation", "")).casefold()
        map_numbers = _strings(raw.get("map_numbers", []), "map_numbers")
        grid_coordinates = _strings(raw.get("grid_coordinates", []), "grid_coordinates")

        zone = int(raw.get("zone", 0) or 0)
        zone_name = _clean(raw.get("zone_name", ""))
        current_zone_name = _clean(navigation_zone_names.get(zone, ""))
        if zone <= 0 or not zone_name or current_zone_name.casefold() != zone_name.casefold():
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} zone does not match current navigation data."
            )
        reference = raw.get("reference")
        if not isinstance(reference, Mapping):
            raise ObjectiveDestinationError(f"Reviewed objective destination {stable_id!r} lacks a target reference.")
        target_name = _clean(reference.get("name", ""))
        target_kind = _clean(reference.get("kind", "")).casefold()
        if not target_name or not target_kind:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} lacks an exact target identity."
            )
        source_claim_ids, source_spans = _select_source_claim(
            source_step_ids,
            source_claim_ids,
            reconciled,
            bg,
            ffxiclopedia,
            action=action,
            target_name=target_name,
            target_kind=target_kind,
            zone_name=zone_name,
            items=items,
            enemies=enemies,
            result_relation=result_relation,
            map_numbers=map_numbers,
            grid_coordinates=grid_coordinates,
        )
        if not any(source_spans.values()):
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} has no typed source action spans."
            )
        matches = [
            point
            for point in points
            if int(point.get("zone", 0) or 0) == zone
            and _clean(point.get("name", "")).casefold() == target_name.casefold()
            and _clean(point.get("kind", "")).casefold() == target_kind
        ]
        destination_id = _clean(raw.get("destination_id", ""))
        if legacy:
            logical_matches = _logical_navigation_points(matches)
            if len(logical_matches) != 1:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} resolves to "
                    f"{len(logical_matches)} logical current nav points."
                )
            same_point = [
                point
                for point in matches
                if _point_tuple(point) == _point_tuple(logical_matches[0])
                and navigation_point_has_immutable_identity(point)
            ]
            immutable_ids = {
                _clean(point.get("destination_id", "")) for point in same_point
            }
            if len(immutable_ids) != 1:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} lacks one immutable destination."
                )
            selected_id = next(iter(immutable_ids))
            if destination_id and destination_id != selected_id:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} destination_id is stale."
                )
            destination_id = selected_id
            selected_point = min(
                (point for point in same_point if _clean(point.get("destination_id", "")) == selected_id),
                key=lambda point: (
                    _clean(point.get("raw_identity", "")),
                    _clean(point.get("source", "")),
                ),
            )
        else:
            if not destination_id:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} lacks immutable destination_id."
                )
            immutable_matches = [
                point for point in matches if navigation_point_has_immutable_identity(point)
            ]
            if not immutable_matches:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} has no immutable destination."
                )
            exact_id_matches = [
                point
                for point in immutable_matches
                if _clean(point.get("destination_id", "")) == destination_id
            ]
            if len(exact_id_matches) != 1:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} destination_id does not match "
                    "one current immutable point."
                )
            selected_point = exact_id_matches[0]

        target_point = _point_tuple(selected_point)
        raw_point = raw.get("target_point")
        if raw_point is not None:
            if not isinstance(raw_point, (list, tuple)) or len(raw_point) != 3:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} has malformed target_point."
                )
            reviewed_point = tuple(float(value) for value in raw_point)
            if not all(math.isfinite(value) for value in reviewed_point):
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} has non-finite target_point."
                )
            if target_point is not None and reviewed_point != target_point:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} target_point disagrees with its exact reference."
                )
            target_point = reviewed_point  # type: ignore[assignment]
        label = _clean(raw.get("label", "")) or _clean(raw.get("camp_label", ""))
        arrival_instruction = _clean(raw.get("arrival_instruction", ""))
        if not label or not arrival_instruction:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} lacks label or arrival instruction."
            )

        ingress_edge_id = 0
        ingress_from_zone = 0
        ingress = raw.get("canonical_ingress")
        if ingress is not None:
            if not isinstance(ingress, Mapping):
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} has malformed canonical ingress."
                )
            ingress_edge_id = int(ingress.get("edge_id", 0) or 0)
            ingress_from_zone = int(ingress.get("from_zone", 0) or 0)
            matches_edges = [
                edge
                for edge in edges
                if int(edge.get("id", 0) or 0) == ingress_edge_id
                and int(edge.get("from_zone", 0) or 0) == ingress_from_zone
                and int(edge.get("to_zone", 0) or 0) == zone
            ]
            if ingress_edge_id <= 0 or ingress_from_zone <= 0 or len(matches_edges) != 1:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} canonical ingress is not an exact current edge."
                )

        instruction_only = bool(raw.get("instruction_only", False))
        eligibility = "instruction-only" if instruction_only else "catalogue"
        results.append(
            ReviewedObjectiveDestination(
                stable_id=stable_id,
                source_step_ids=source_step_ids,
                source_claim_ids=source_claim_ids,
                action=action,
                items=items,
                enemies=enemies,
                destination_id=destination_id,
                zone=zone,
                zone_name=current_zone_name,
                label=label,
                target_name=target_name,
                target_kind=target_kind,
                target_point=target_point,
                arrival_instruction=arrival_instruction,
                eligibility=eligibility,
                route_contract_id=_clean(raw.get("route_contract_id", "")),
                canonical_ingress_edge_id=ingress_edge_id,
                canonical_ingress_from_zone=ingress_from_zone,
                transport_id=_clean(raw.get("transport_id", "")),
                instruction_only=instruction_only,
                source_revisions=tuple(
                    (site, page.revision_id)
                    for site, page in pages.items()
                    if page is not None
                ),
            )
        )
    return tuple(sorted(results, key=lambda row: row.stable_id))


def resolve_reviewed_objective_destinations(
    native: NativeObjective,
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    reviewed_overrides: Mapping[str, Any] | None,
    navigation_points: Iterable[Mapping[str, Any]],
    navigation_zone_names: Mapping[int, str],
    navigation_edges: Iterable[Mapping[str, Any]] = (),
) -> tuple[ReviewedObjectiveDestination, ...]:
    """Resolve current overrides while treating the legacy table as fail-closed input."""

    rows = _override_rows(reviewed_overrides, native)
    if not rows:
        return ()
    points = tuple(navigation_points)
    edges = tuple(navigation_edges)
    results: list[ReviewedObjectiveDestination] = []
    seen_ids: set[str] = set()
    for raw, legacy in rows:
        isolated_overrides = {
            (
                "mission_destination_overrides"
                if legacy
                else "objective_destination_overrides"
            ): {native.key: [raw]}
        }
        try:
            resolved = _resolve_reviewed_objective_destinations_strict(
                native,
                reconciled,
                bg,
                ffxiclopedia,
                isolated_overrides,
                points,
                navigation_zone_names,
                edges,
            )
        except ObjectiveDestinationError:
            if legacy:
                continue
            raise
        for row in resolved:
            if row.stable_id in seen_ids:
                raise ObjectiveDestinationError(
                    f"Duplicate reviewed objective destination id {row.stable_id!r}."
                )
            seen_ids.add(row.stable_id)
            results.append(row)
    return tuple(sorted(results, key=lambda row: row.stable_id))

from __future__ import annotations

import hashlib
import json
import math
import re
from collections.abc import Iterable, Mapping
from typing import Any

from .model import NativeObjective, ParsedObjective, SourceActionSpan
from .reconcile import (
    ReconciledActionClaim,
    ReconciledObjective,
    ReconciledStep,
    ReviewedObjectiveDestination,
)


class ObjectiveDestinationError(ValueError):
    """Raised when a reviewed destination no longer proves its typed claims."""


_STABLE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
_SUPPORTED_ACTIONS = {"talk", "trade", "examine", "use", "fight", "farm", "obtain", "travel"}


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
    targets = {span.target.casefold()} if span.target else set()
    if kind_field:
        targets.update(value.casefold() for value in getattr(span, kind_field))
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


def _legacy_destination_id(
    zone: int,
    target_name: str,
    target_kind: str,
    point: Mapping[str, Any],
) -> str:
    identity = {
        "kind": target_kind,
        "name": target_name,
        "point": _point_tuple(point),
        "source": _clean(point.get("source", "")),
        "zone": zone,
    }
    digest = hashlib.sha256(
        json.dumps(identity, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()[:16]
    prefix = "camp" if target_kind == "enemy" else "reference"
    return f"{prefix}:{zone}:{_slug(target_name)}:{digest}"


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
        if len(matches) != 1:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} resolves to {len(matches)} current nav points."
            )

        target_point = _point_tuple(matches[0])
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
        destination_id = _clean(raw.get("destination_id", ""))
        if legacy:
            destination_id = destination_id or _legacy_destination_id(
                zone, target_name, target_kind, matches[0]
            )
        if not destination_id:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} lacks immutable destination_id."
            )
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

from __future__ import annotations

import hashlib
import json
import math
import re
from collections.abc import Iterable, Mapping
from typing import Any

from .model import NativeObjective, ParsedObjective, SourceActionSpan
from .reconcile import ReconciledObjective, ReviewedObjectiveDestination


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


def _source_step_spans(
    source_step_ids: tuple[str, ...],
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
) -> dict[str, tuple[SourceActionSpan, ...]]:
    step_lookup = {step.stable_step_id: step for step in reconciled.steps}
    source_pages = {"bg": bg, "ffxiclopedia": ffxiclopedia}
    result: dict[str, list[SourceActionSpan]] = {"bg": [], "ffxiclopedia": []}
    for stable_step_id in source_step_ids:
        step = step_lookup.get(stable_step_id)
        if step is None:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination references unknown step {stable_step_id!r}."
            )
        if step.comparison == "conflict":
            raise ObjectiveDestinationError(
                f"Reviewed objective destination depends on conflicted step {stable_step_id!r}."
            )
        for source_index, site in enumerate(("bg", "ffxiclopedia")):
            source_order = step.source_orders[source_index]
            page = source_pages[site]
            if page is None or source_order <= 0:
                continue
            source_step = next((row for row in page.steps if row.order == source_order), None)
            if source_step is not None:
                result[site].extend(source_step.action_spans)
    return {site: tuple(spans) for site, spans in result.items()}


def _typed_values(spans: Iterable[SourceActionSpan], field: str) -> set[str]:
    values: set[str] = set()
    for span in spans:
        for value in getattr(span, field):
            cleaned = _clean(value)
            if cleaned:
                values.add(cleaned.casefold())
    return values


def _claims_action(span: SourceActionSpan, action: str) -> bool:
    if span.action == action:
        return True
    if action in {"farm", "obtain"} and span.action == "fight" and span.result_relation == "obtain-from":
        return True
    return action == "obtain" and span.action == "obtain"


def _same_source_target_zone(
    source_spans: Mapping[str, tuple[SourceActionSpan, ...]],
    action: str,
    target_name: str,
    target_kind: str,
    zone_name: str,
) -> bool:
    target_key = target_name.casefold()
    zone_key = zone_name.casefold()
    kind_field = {
        "npc": "npc_mentions",
        "object": "object_mentions",
        "area": "object_mentions",
        "enemy": "enemy_mentions",
        "transport": "transport_mentions",
    }.get(target_kind, "")
    for spans in source_spans.values():
        for span in spans:
            if not _claims_action(span, action):
                continue
            targets = {span.target.casefold()} if span.target else set()
            if kind_field:
                targets.update(value.casefold() for value in getattr(span, kind_field))
            zones = {value.casefold() for value in span.zone_mentions}
            if target_key in targets and zone_key in zones:
                return True
    return False


def _point_tuple(point: Mapping[str, Any]) -> tuple[float, float, float] | None:
    values = (point.get("x"), point.get("z"), point.get("y"))
    if any(value is None or str(value).strip() == "" for value in values):
        return None
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
        for site, page in pages.items():
            if page is not None and int(revisions.get(site, 0) or 0) != page.revision_id:
                raise ObjectiveDestinationError(
                    f"Reviewed objective destination {stable_id!r} no longer matches its {site} revision."
                )

        source_step_ids = _strings(raw.get("source_step_ids"), "source_step_ids", required=True)
        source_spans = _source_step_spans(source_step_ids, reconciled, bg, ffxiclopedia)
        if not any(source_spans.values()):
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} has no typed source action spans."
            )
        action = _clean(raw.get("action", "")).casefold()
        if action not in _SUPPORTED_ACTIONS:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} has unsupported action {action!r}."
            )
        items = _strings(raw.get("items", []), "items")
        enemies = _strings(raw.get("enemies", []), "enemies")
        all_spans = tuple(span for spans in source_spans.values() for span in spans)
        item_claims = _typed_values(all_spans, "item_mentions").union(
            _typed_values(all_spans, "result_items")
        )
        enemy_claims = _typed_values(all_spans, "enemy_mentions")
        missing_claims = [
            *[value for value in items if value.casefold() not in item_claims],
            *[value for value in enemies if value.casefold() not in enemy_claims],
        ]
        if missing_claims:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} names absent typed claims: "
                + ", ".join(missing_claims)
            )

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
        matches = [
            point
            for point in points
            if int(point.get("zone", 0) or 0) == zone
            and _clean(point.get("name", "")).casefold() == target_name.casefold()
            and _clean(point.get("kind", "")).casefold() == target_kind
        ]
        if not target_name or not target_kind or len(matches) != 1:
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} resolves to {len(matches)} current nav points."
            )
        if not _same_source_target_zone(source_spans, action, target_name, target_kind, zone_name):
            raise ObjectiveDestinationError(
                f"Reviewed objective destination {stable_id!r} joins target and zone from different source claims."
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

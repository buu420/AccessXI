from __future__ import annotations

import re
from collections.abc import Iterable, Mapping
from typing import Any

from .model import NativeObjective, ParsedObjective
from .reconcile import ReconciledObjective, ReviewedMissionDestination


class MissionDestinationError(ValueError):
    """Raised when a reviewed mission destination no longer proves its claims."""


_SUPPORTED_ACTIONS = {"farm", "fight", "obtain"}
_STABLE_ID = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


def _clean(value: object) -> str:
    return " ".join(str(value or "").split())


def _unique_strings(value: object, field: str) -> tuple[str, ...]:
    if not isinstance(value, (list, tuple)):
        raise MissionDestinationError(f"Reviewed mission destination {field} must be a list.")
    seen: set[str] = set()
    result: list[str] = []
    for raw in value:
        item = _clean(raw)
        key = item.casefold()
        if item and key not in seen:
            seen.add(key)
            result.append(item)
    if not result:
        raise MissionDestinationError(f"Reviewed mission destination {field} is empty.")
    return tuple(result)


def _mission_overrides(
    reviewed_overrides: Mapping[str, Any] | None,
    native_key: str,
) -> tuple[Mapping[str, Any], ...]:
    root = reviewed_overrides.get("mission_destination_overrides", {}) if isinstance(reviewed_overrides, Mapping) else {}
    rows = root.get(native_key) if isinstance(root, Mapping) else None
    if rows is None:
        return ()
    if not isinstance(rows, list):
        raise MissionDestinationError(
            f"Reviewed mission destinations for {native_key!r} must be a list."
        )
    if any(not isinstance(row, Mapping) for row in rows):
        raise MissionDestinationError(
            f"Reviewed mission destinations for {native_key!r} contain a non-object row."
        )
    return tuple(rows)


def resolve_reviewed_mission_destinations(
    native: NativeObjective,
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    reviewed_overrides: Mapping[str, Any] | None,
    navigation_points: Iterable[Mapping[str, Any]],
    navigation_zone_names: Mapping[int, str],
    navigation_edges: Iterable[Mapping[str, Any]] = (),
) -> tuple[ReviewedMissionDestination, ...]:
    rows = _mission_overrides(reviewed_overrides, native.key)
    if not rows:
        return ()
    if native.kind != "mission" or bg is None or ffxiclopedia is None:
        raise MissionDestinationError(
            f"Reviewed mission destinations for {native.key!r} require two matched mission sources."
        )

    steps = {step.stable_step_id: step for step in reconciled.steps}
    points = tuple(navigation_points)
    edges = tuple(navigation_edges)
    results: list[ReviewedMissionDestination] = []
    seen_ids: set[str] = set()
    for raw in rows:
        short_id = _clean(raw.get("id", "")).casefold()
        if not _STABLE_ID.fullmatch(short_id):
            raise MissionDestinationError(
                f"Reviewed mission destination for {native.key!r} has an invalid id {short_id!r}."
            )
        stable_id = f"{native.key}:{short_id}"
        if stable_id in seen_ids:
            raise MissionDestinationError(f"Duplicate reviewed mission destination id {stable_id!r}.")
        seen_ids.add(stable_id)

        revisions = raw.get("source_revisions")
        if not isinstance(revisions, Mapping):
            raise MissionDestinationError(f"Reviewed mission destination {stable_id!r} lacks source revisions.")
        if int(revisions.get("bg", 0) or 0) != bg.revision_id or int(
            revisions.get("ffxiclopedia", 0) or 0
        ) != ffxiclopedia.revision_id:
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} no longer matches its source revisions."
            )

        source_step_ids = _unique_strings(raw.get("source_step_ids"), "source_step_ids")
        selected_steps = []
        for step_id in source_step_ids:
            step = steps.get(step_id)
            if step is None:
                raise MissionDestinationError(
                    f"Reviewed mission destination {stable_id!r} references an unknown step {step_id!r}."
                )
            if step.comparison == "conflict":
                raise MissionDestinationError(
                    f"Reviewed mission destination {stable_id!r} depends on conflicted step {step_id!r}."
                )
            selected_steps.append(step)

        action = _clean(raw.get("action", "")).casefold()
        if action not in _SUPPORTED_ACTIONS:
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} has unsupported action {action!r}."
            )
        items = _unique_strings(raw.get("items"), "items")
        enemies = _unique_strings(raw.get("enemies"), "enemies")
        selected_item_claims = {
            value.casefold()
            for step in selected_steps
            for value in (*step.items, *step.entities)
        }
        missing_items = [item for item in items if item.casefold() not in selected_item_claims]
        missing_enemies = [enemy for enemy in enemies if enemy.casefold() not in selected_item_claims]
        if missing_items or missing_enemies:
            missing = ", ".join((*missing_items, *missing_enemies))
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} names claims absent from its selected steps: {missing}."
            )
        zone = int(raw.get("zone", 0) or 0)
        zone_name = _clean(raw.get("zone_name", ""))
        current_zone_name = _clean(navigation_zone_names.get(zone, ""))
        if zone <= 0 or not zone_name or current_zone_name.casefold() != zone_name.casefold():
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} zone does not match current navigation data."
            )
        selected_zone_claims = {
            value.casefold()
            for step in selected_steps
            for value in (*step.zones, *step.entities)
        }
        if zone_name.casefold() not in selected_zone_claims:
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} zone is absent from its selected steps."
            )

        reference = raw.get("reference")
        if not isinstance(reference, Mapping):
            raise MissionDestinationError(f"Reviewed mission destination {stable_id!r} lacks a target reference.")
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
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} resolves to {len(matches)} current nav points."
            )
        route_evidence = _clean(raw.get("route_evidence", ""))
        confidence = _clean(matches[0].get("confidence", "")).casefold()
        if confidence == "untested" and not route_evidence:
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} needs route evidence for an untested target."
            )
        camp_label = _clean(raw.get("camp_label", ""))
        arrival_instruction = _clean(raw.get("arrival_instruction", ""))
        if not camp_label or not arrival_instruction:
            raise MissionDestinationError(
                f"Reviewed mission destination {stable_id!r} lacks its camp label or arrival instruction."
            )

        canonical_ingress_edge_id = 0
        canonical_ingress_from_zone = 0
        canonical_ingress = raw.get("canonical_ingress")
        if canonical_ingress is not None:
            if not isinstance(canonical_ingress, Mapping):
                raise MissionDestinationError(
                    f"Reviewed mission destination {stable_id!r} has malformed canonical ingress."
                )
            canonical_ingress_edge_id = int(canonical_ingress.get("edge_id", 0) or 0)
            canonical_ingress_from_zone = int(canonical_ingress.get("from_zone", 0) or 0)
            edge_matches = [
                edge
                for edge in edges
                if int(edge.get("id", 0) or 0) == canonical_ingress_edge_id
                and int(edge.get("from_zone", 0) or 0) == canonical_ingress_from_zone
                and int(edge.get("to_zone", 0) or 0) == zone
            ]
            if canonical_ingress_edge_id <= 0 or canonical_ingress_from_zone <= 0 or len(edge_matches) != 1:
                raise MissionDestinationError(
                    f"Reviewed mission destination {stable_id!r} canonical ingress is not an exact current edge."
                )

        results.append(
            ReviewedMissionDestination(
                stable_id=stable_id,
                source_step_ids=source_step_ids,
                action=action,
                items=items,
                enemies=enemies,
                zone=zone,
                zone_name=current_zone_name,
                camp_label=camp_label,
                target_name=target_name,
                target_kind=target_kind,
                arrival_instruction=arrival_instruction,
                canonical_ingress_edge_id=canonical_ingress_edge_id,
                canonical_ingress_from_zone=canonical_ingress_from_zone,
                transport_id=_clean(raw.get("transport_id", "")),
                route_evidence=route_evidence,
            )
        )
    return tuple(results)

from __future__ import annotations

from collections.abc import Iterable, Mapping
from typing import Any

from .model import NativeObjective, ParsedObjective
from .objective_destinations import (
    ObjectiveDestinationError,
    resolve_reviewed_objective_destinations,
)
from .reconcile import ReconciledObjective, ReviewedMissionDestination


class MissionDestinationError(ValueError):
    """Compatibility error for callers of the retired mission-only resolver."""


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
    """Adapt reviewed catalogue context without carrying legacy route authorization."""

    try:
        rows = resolve_reviewed_objective_destinations(
            native,
            reconciled,
            bg,
            ffxiclopedia,
            reviewed_overrides,
            navigation_points,
            navigation_zone_names,
            navigation_edges,
        )
    except ObjectiveDestinationError as error:
        raise MissionDestinationError(str(error)) from error

    return tuple(
        ReviewedMissionDestination(
            stable_id=row.stable_id,
            source_step_ids=row.source_step_ids,
            action=row.action,
            items=row.items,
            enemies=row.enemies,
            zone=row.zone,
            zone_name=row.zone_name,
            camp_label=row.label,
            target_name=row.target_name,
            target_kind=row.target_kind,
            arrival_instruction=row.arrival_instruction,
            canonical_ingress_edge_id=0,
            canonical_ingress_from_zone=0,
            transport_id="",
            route_evidence="",
        )
        for row in rows
    )

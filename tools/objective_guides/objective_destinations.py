from __future__ import annotations

import hashlib
import math
import re
from collections.abc import Iterable, Mapping
from dataclasses import replace
from typing import Any

from .model import NativeObjective, ParsedObjective, SourceActionSpan
from .reconcile import (
    LegacyDestinationOutcome,
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
_ENEMY_REVIEWED_DISPLAY_NAMES = {
    "Alexander_NP": "Alexander",
    "Alexander_WTC": "Alexander",
    "Amnaf_BLU": "Amnaf",
    "Amnaf_Psycheflayer": "Amnaf",
    "Archaic_Rampart_1": "Archaic Rampart",
    "Archaic_Rampart_2": "Archaic Rampart",
    "Archaic_Rampart_3": "Archaic Rampart",
    "Ark_Angel_EV_CP": "Ark Angel EV",
    "Ark_Angel_GK_CP": "Ark Angel GK",
    "Ark_Angel_HM_CP": "Ark Angel HM",
    "Ark_Angel_MR_CP": "Ark Angel MR",
    "Ark_Angel_TT_CP": "Ark Angel TT",
    "Ark_Angels_Adamant_CP": "Ark Angel's Adamantoise",
    "Ark_Angels_Behemoth_CP": "Ark Angel's Behemoth",
    "Ark_Angels_Wyvern_CP": "Ark Angel's Wyvern",
    "Ashu_Talif_Crew_mnk": "Ashu Talif Crew",
    "Ashu_Talif_Crew_rdm": "Ashu Talif Crew",
    "Ashu_Talif_Crew_rng": "Ashu Talif Crew",
    "Atori-Tutori_qm": "Atori-Tutori ???",
    "Awzdei_Fast": "Aw'zdei",
    "Awzdei_Still": "Aw'zdei",
    "Bahamut_bv2": "Bahamut",
    "Bloodsucker_NM": "Bloodsucker",
    "Diabolos_DN": "Diabolos",
    "Diabolos_WD": "Diabolos",
    "Ealdnarche_2": "Eald'narche",
    "Ealdnarche_CP": "Eald'narche",
    "Eoaern_BST": "Eo'aern",
    "Eoaern_DRG": "Eo'aern",
    "Eoaern_SMN": "Eo'aern",
    "Eozdei_Still": "Eo'zdei",
    "Friars_Lantern_Grow": "Friar's Lantern",
    "Garuda_Prime_ASA": "Garuda Prime",
    "Garuda_Prime_TBW": "Garuda Prime",
    "Garuda_Prime_TSTBW": "Garuda Prime",
    "Garuda_Prime_WTB": "Garuda Prime",
    "Ghul-I-Beaban_BLM": "Ghul-I-Beaban",
    "Ghul-I-Beaban_DRK": "Ghul-I-Beaban",
    "Ifrit_Prime_ASA": "Ifrit Prime",
    "Ifrit_Prime_TBF": "Ifrit Prime",
    "Ifrit_Prime_TSTBF": "Ifrit Prime",
    "Ifrit_Prime_WTB": "Ifrit Prime",
    "Imp_Bandsman_Add": "Imp Bandsman",
    "Ixaern_DRG": "Ix'aern",
    "Ixaern_DRGs_Wynav": "Aern's Wynav",
    "Ixaern_DRK": "Ix'aern",
    "Ixaern_MNK": "Ix'aern",
    "Ixzdei_BLM": "Ix'zdei",
    "Ixzdei_RDM": "Ix'zdei",
    "Jormungand_bv2": "Jormungand",
    "Kamlanaut_CP": "Kam'lanaut",
    "Kfghrah_BLM": "Kf'ghrah",
    "Kfghrah_WHM": "Kf'ghrah",
    "Lamia_Exon_BLM": "Lamia Exon",
    "Lamia_Exon_COR": "Lamia Exon",
    "Leviathan_Prime_ASA": "Leviathan Prime",
    "Leviathan_Prime_TBW": "Leviathan Prime",
    "Leviathan_Prime_TSTBW": "Leviathan Prime",
    "Leviathan_Prime_WTB": "Leviathan Prime",
    "Magnes_Quadav_NM": "Magnes Quadav",
    "Memory_Receptacle_Red": "Memory Receptacle",
    "Memory_Receptacle_Shield": "Memory Receptacle",
    "Mountain_Worm_NM": "Mountain Worm",
    "Nickel_Quadav_NM": "Nickel Quadav",
    "Omaern_BST": "Om'aern",
    "Omaern_DRG": "Om'aern",
    "Omaern_SMN": "Om'aern",
    "Orbital_CP": "Orbital",
    "Ouryu_bv2": "Ouryu",
    "Pandemonium_Lamp_Avatar": "Pandemonium Lamp",
    "Pandemonium_Warden_HNM": "Pandemonium Warden",
    "Phantom_Puk_Clone": "Phantom Puk",
    "Promathia_2": "Promathia",
    "Puffer_Pugil_Brigand": "Puffer Pugil",
    "Ramuh_Prime_ASA": "Ramuh Prime",
    "Ramuh_Prime_TBL": "Ramuh Prime",
    "Ramuh_Prime_TSTBL": "Ramuh Prime",
    "Ramuh_Prime_WTB": "Ramuh Prime",
    "Scythe_Victim_blm": "Scythe Victim",
    "Scythe_Victim_war": "Scythe Victim",
    "Shadow_Lord_Phase_1": "Shadow Lord",
    "Shadow_Lord_Phase_2": "Shadow Lord",
    "Shikaree_X_HW": "Shikaree X",
    "Shikaree_X_ROS_TWT": "Shikaree X",
    "Shikaree_Y_HW": "Shikaree Y",
    "Shikaree_Y_ROS_TWT": "Shikaree Y",
    "Shikaree_Z_HW": "Shikaree Z",
    "Shikaree_Z_ROS": "Shikaree Z",
    "Shiva_Prime_ASA": "Shiva Prime",
    "Shiva_Prime_TBI": "Shiva Prime",
    "Shiva_Prime_TSTBI": "Shiva Prime",
    "Shiva_Prime_WTB": "Shiva Prime",
    "Skeleton_Esquire_NM": "Skeleton Esquire",
    "Snow_Devil_blm": "Snow Devil",
    "Snow_Devil_war": "Snow Devil",
    "Tiamat_bv2": "Tiamat",
    "Titan_Prime_ASA": "Titan Prime",
    "Titan_Prime_HTBF": "Titan Prime",
    "Titan_Prime_TBE": "Titan Prime",
    "Titan_Prime_TSTBE": "Titan Prime",
    "Titan_Prime_WTB": "Titan Prime",
    "Vrtra_bv2": "Vrtra",
    "Wanderer_enm": "Wanderer",
    "Zeid_2": "Zeid",
}


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
) -> tuple[Mapping[str, Any], ...]:
    if not isinstance(reviewed_overrides, Mapping):
        return ()
    shared = reviewed_overrides.get("objective_destination_overrides", {})
    rows: list[Mapping[str, Any]] = []
    if isinstance(shared, Mapping) and native.key in shared:
        raw_rows = shared[native.key]
        if not isinstance(raw_rows, list) or any(not isinstance(row, Mapping) for row in raw_rows):
            raise ObjectiveDestinationError(
                f"Reviewed objective destinations for {native.key!r} must be a list of objects."
            )
        rows.extend(raw_rows)
    return tuple(rows)


def _legacy_override_rows(
    reviewed_overrides: Mapping[str, Any] | None,
    native: NativeObjective,
) -> tuple[Mapping[str, Any], ...]:
    if native.kind != "mission" or not isinstance(reviewed_overrides, Mapping):
        return ()
    root = reviewed_overrides.get("mission_destination_overrides", {})
    if not isinstance(root, Mapping):
        raise ObjectiveDestinationError("Legacy mission destination overrides must be an object.")
    raw_rows = root.get(native.key, ())
    if raw_rows in (None, ()):
        return ()
    if not isinstance(raw_rows, list) or any(not isinstance(row, Mapping) for row in raw_rows):
        raise ObjectiveDestinationError(
            f"Legacy mission destinations for {native.key!r} must be a list of objects."
        )
    return tuple(raw_rows)


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


def _source_spans_support_destination(
    source_spans: Mapping[str, tuple[SourceActionSpan, ...]],
    *,
    action: str,
    relationship: str,
    target_name: str,
    target_kind: str,
    zone_name: str,
    items: tuple[str, ...],
    enemies: tuple[str, ...],
    result_relation: str,
    map_numbers: tuple[str, ...],
    grid_coordinates: tuple[str, ...],
) -> bool:
    span_rows = tuple(
        (site, span, "", 0)
        for site in ("bg", "ffxiclopedia")
        for span in source_spans.get(site, ())
    )

    def authoritative(field_value: Any) -> tuple[SourceActionSpan, ...]:
        return tuple(row[1] for row in _authoritative_span_rows(span_rows, field_value))

    if not any(_claims_action(span, action) for span in authoritative(lambda span: span.action)):
        return False
    compatible_kinds = {target_kind}
    if target_kind == "area":
        compatible_kinds.add("object")
    if not any(
        span.target_kind in compatible_kinds
        for span in authoritative(lambda span: span.target_kind)
    ):
        return False
    kind_field = {
        "npc": "npc_mentions",
        "object": "object_mentions",
        "area": "object_mentions",
        "enemy": "enemy_mentions",
        "transport": "transport_mentions",
        "question-mark": "object_mentions",
    }.get(target_kind, "")
    target_spans = authoritative(
        lambda span: tuple(
            value
            for value in (
                span.target,
                *(tuple(getattr(span, kind_field)) if kind_field else ()),
            )
            if value
        )
    )
    for span in target_spans:
        typed_targets = tuple(getattr(span, kind_field)) if kind_field else ()
        if not span.target and len({value.casefold() for value in typed_targets}) > 1:
            return False
    targets = {
        value.casefold()
        for span in target_spans
        for value in (
            span.target,
            *(tuple(getattr(span, kind_field)) if kind_field else ()),
        )
        if value
    }
    if target_name.casefold() not in targets:
        return False
    zones = {
        value.casefold()
        for span in authoritative(lambda span: span.zone_mentions)
        for value in span.zone_mentions
    }
    if zone_name.casefold() not in zones:
        return False
    if relationship:
        relationships = {
            _normalized_relationship(span.relationship)
            for span in authoritative(lambda span: span.relationship)
            if _normalized_relationship(span.relationship)
        }
        if relationships and _normalized_relationship(relationship) not in relationships:
            return False
    item_claims = {
        value.casefold()
        for span in authoritative(
            lambda span: (*span.item_mentions, *span.key_item_mentions, *span.result_items)
        )
        for value in (*span.item_mentions, *span.key_item_mentions, *span.result_items)
    }
    enemy_claims = {
        value.casefold()
        for span in authoritative(lambda span: span.enemy_mentions)
        for value in span.enemy_mentions
    }
    if any(value.casefold() not in item_claims for value in items):
        return False
    if any(value.casefold() not in enemy_claims for value in enemies):
        return False
    result_relations = {
        span.result_relation.casefold()
        for span in authoritative(lambda span: span.result_relation)
        if span.result_relation
    }
    if result_relation and result_relation.casefold() not in result_relations:
        return False
    map_claims = {
        value.casefold()
        for span in authoritative(lambda span: span.map_numbers)
        for value in span.map_numbers
    }
    grid_claims = {
        value.casefold()
        for span in authoritative(lambda span: span.grid_coordinates)
        for value in span.grid_coordinates
    }
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
        source_spans = _claim_source_spans(step, claim, bg, ffxiclopedia)
        if _source_spans_support_destination(
            source_spans,
            action=action,
            relationship=claim.relationship,
            target_name=target_name,
            target_kind=target_kind,
            zone_name=zone_name,
            items=items,
            enemies=enemies,
            result_relation=result_relation,
            map_numbers=map_numbers,
            grid_coordinates=grid_coordinates,
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


def _enemy_name_tokens(value: str) -> tuple[str, ...]:
    result: list[str] = []
    for raw_token in re.split(r"[_\s]+", value.casefold().replace("`", "'")):
        token = "".join(character for character in raw_token if character.isalnum())
        if not token:
            continue
        if token == "s" and result:
            result[-1] += token
        else:
            result.append(token)
    return tuple(result)


def _enemy_display_name_matches_identity(display_name: str, raw_identity: str) -> bool:
    raw_name = raw_identity.split(":mobname:", 1)[-1]
    display_tokens = _enemy_name_tokens(display_name)
    raw_tokens = _enemy_name_tokens(raw_name)
    if display_tokens and display_tokens == raw_tokens:
        return True
    reviewed_display_name = _ENEMY_REVIEWED_DISPLAY_NAMES.get(raw_name)
    return reviewed_display_name is not None and display_tokens == _enemy_name_tokens(
        reviewed_display_name
    )


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
            or not _enemy_display_name_matches_identity(
                _clean(point.get("name", "")), raw_identity
            )
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


def _authoritative_span_rows(
    span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...],
    field_value: Any,
) -> tuple[tuple[str, SourceActionSpan, str, int], ...]:
    def present(value: object) -> bool:
        if isinstance(value, str):
            return bool(value.strip())
        if isinstance(value, (tuple, list, set, dict)):
            return bool(value)
        return value is not None

    for site in ("bg", "ffxiclopedia"):
        rows = tuple(
            row
            for row in span_rows
            if row[0] == site and present(field_value(row[1]))
        )
        if rows:
            return rows
    return ()


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
    if not claim.material:
        return (
            ObjectiveActionLedgerRow(
                action_id,
                span_ids,
                action,
                "context-only",
                "non-material-source-action-span",
                (),
                "",
                False,
            ),
            (),
            (),
            (),
        )
    role_override = _mapping_row(reviewed_overrides, "role_overrides", action_id)
    if coordinate_comparison == "conflict" and not any(site == "bg" for site, *_rest in span_rows):
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

    target_rows = _authoritative_span_rows(span_rows, lambda span: span.target)
    kind_rows = _authoritative_span_rows(span_rows, lambda span: span.target_kind)
    relationship_rows = _authoritative_span_rows(span_rows, lambda span: span.relationship)
    zone_rows = _authoritative_span_rows(span_rows, lambda span: span.zone_mentions)
    target = target_rows[0][1].target if target_rows else ""
    target_kind = kind_rows[0][1].target_kind if kind_rows else ""
    claim_target = target
    acquisition_enemies = _claim_enemies(span_rows)
    acquisition_navigation = bool(
        action == "obtain"
        and target_kind == "item"
        and _claim_result_relation(span_rows) == "obtain-from"
        and len(acquisition_enemies) == 1
    )
    if acquisition_navigation:
        # Reducer ownership remains the exact inventory item; route catalogue
        # ownership points at the one exact enemy method preserved by the same
        # typed source claim.  Kill credit never completes this obtain action.
        target = acquisition_enemies[0]
        target_kind = "enemy"

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

    expected_relationship = (
        _normalized_relationship(relationship_rows[0][1].relationship)
        if relationship_rows
        else ""
    )
    field_support_rows = tuple(
        {
            row[2]: row
            for rows in (target_rows, kind_rows, relationship_rows)
            for row in rows
        }.values()
    )

    zone_support: dict[str, list[str]] = {}
    zone_support_ids: dict[str, list[str]] = {}
    zone_support_revisions: dict[str, dict[str, int]] = {}
    typed_span_ids_by_site: dict[str, list[str]] = {}
    zone_display: dict[str, str] = {}
    matching_span_rows = list(span_rows) if target and target_kind and expected_relationship else []
    authoritative_site = zone_rows[0][0] if zone_rows else ""
    for site, span, source_span_id, revision in matching_span_rows:
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
            or _clean(single_source_override.get("target", "")).casefold()
            != claim_target.casefold()
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
    if any("bg" in sites for sites in zone_support.values()):
        authoritative_site = "bg"
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
        reviewed_zone = zone_key in reviewed_single_zones
        if authoritative_site not in support_sites and not reviewed_zone:
            skipped_single_source = True
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
                    source_action_span_ids=tuple(zone_support_ids.get(zone_key, ())),
                    reason="single-source-needs-independent-corroboration",
                    route_ready=False,
                )
            )
            continue
        canonical = canonical_zones.get(zone_key)
        if canonical is None:
            continue
        zone, zone_name = canonical
        matches = [
            point
            for point in points
            if int(point.get("zone", 0) or 0) == zone
            and _clean(point.get("name", "")).casefold() == target.casefold()
            and _source_kind_supports_claim(
                _clean(point.get("kind", "")).casefold(),
                target_kind,
                action,
            )
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
        zone_span_ids = set(zone_support_ids.get(zone_key, ()))
        candidate_support_rows = tuple(
            row
            for row in span_rows
            if row in field_support_rows or row[2] in zone_span_ids
        )
        candidate_support_sites = tuple(
            dict.fromkeys((*[row[0] for row in candidate_support_rows], *support_sites))
        )
        candidate_support_ids = tuple(
            dict.fromkeys(
                (*[row[2] for row in candidate_support_rows], *zone_support_ids.get(zone_key, ()))
            )
        )
        candidate_support_revisions = tuple(
            dict.fromkeys(
                (
                    *((row[0], row[3]) for row in candidate_support_rows),
                    *(
                        (site, zone_support_revisions[zone_key][site])
                        for site in support_sites
                    ),
                )
            )
        )
        group_id = f"{action_id}:zone:{zone}" if action in {"fight", "obtain"} else ""
        zone_candidates = tuple(
            _point_candidate(
                action_id=action_id,
                action=action,
                point=point,
                zone_name=zone_name,
                span_rows=span_rows,
                support_sites=candidate_support_sites,
                support_span_ids=candidate_support_ids,
                support_revisions=candidate_support_revisions,
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


def _legacy_override_stable_id(native: NativeObjective, raw: Mapping[str, Any]) -> str:
    short_id = _clean(raw.get("id", "")).casefold()
    if not _STABLE_ID.fullmatch(short_id):
        raise ObjectiveDestinationError(
            f"Legacy objective destination for {native.key!r} has invalid id {short_id!r}."
        )
    return f"{native.key}:destination:{short_id}"


def _legacy_review_metadata(
    raw: Mapping[str, Any],
) -> tuple[int, str, str, str, int, int, str, str]:
    reference = raw.get("reference", {})
    if not isinstance(reference, Mapping):
        raise ObjectiveDestinationError("Legacy objective destination reference must be an object.")
    ingress = raw.get("canonical_ingress", {})
    if ingress is None:
        ingress = {}
    if not isinstance(ingress, Mapping):
        raise ObjectiveDestinationError("Legacy objective destination canonical_ingress must be an object.")
    return (
        int(raw.get("zone", 0) or 0),
        _clean(raw.get("zone_name", "")),
        _clean(reference.get("name", "")),
        _clean(reference.get("kind", "")).casefold(),
        int(ingress.get("edge_id", 0) or 0),
        int(ingress.get("from_zone", 0) or 0),
        _clean(raw.get("transport_id", "")),
        _clean(raw.get("route_evidence", "")),
    )


def _legacy_outcome(
    *,
    native: NativeObjective,
    raw: Mapping[str, Any],
    action_id: str,
    classification: str,
    reason: str,
    candidate_ids: tuple[str, ...] = (),
    group_ids: tuple[str, ...] = (),
    source_action_span_ids: tuple[str, ...] = (),
    source_revisions: tuple[tuple[str, int], ...] = (),
) -> LegacyDestinationOutcome:
    (
        zone,
        zone_name,
        target_name,
        target_kind,
        ingress_edge_id,
        ingress_from_zone,
        transport_id,
        route_evidence,
    ) = _legacy_review_metadata(raw)
    return LegacyDestinationOutcome(
        legacy_override_id=_legacy_override_stable_id(native, raw),
        action_id=action_id,
        classification=classification,
        reason=reason,
        candidate_ids=candidate_ids,
        group_ids=group_ids,
        source_action_span_ids=source_action_span_ids,
        source_revisions=source_revisions,
        zone=zone,
        zone_name=zone_name,
        target_name=target_name,
        target_kind=target_kind,
        canonical_ingress_edge_id=ingress_edge_id,
        canonical_ingress_from_zone=ingress_from_zone,
        transport_id=transport_id,
        route_evidence=route_evidence,
        route_ready=False,
    )


def _source_fact_step(
    *,
    native: NativeObjective,
    page: ParsedObjective,
    site: str,
    source_step_id: object,
) -> tuple[Any, str]:
    stable_step_id = _clean(source_step_id)
    source_step = next(
        (
            step
            for step in page.steps
            if stable_step_id == f"{native.key}:{site}:step-{step.order:03d}"
        ),
        None,
    )
    if source_step is None:
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} references stale source step {stable_step_id!r}."
        )
    return source_step, stable_step_id


def _contains_exact_text(text: str, value: str) -> bool:
    return re.search(
        rf"(?<![A-Za-z0-9]){re.escape(value)}(?![A-Za-z0-9])",
        text,
        re.IGNORECASE,
    ) is not None


def _immutable_enemy_instances(
    matches: Iterable[Mapping[str, Any]],
) -> tuple[Mapping[str, Any], ...] | None:
    by_coordinates: dict[tuple[float, float, float], list[Mapping[str, Any]]] = {}
    for point in matches:
        by_coordinates.setdefault(_point_tuple(point), []).append(point)
    selected: list[Mapping[str, Any]] = []
    for coordinates in sorted(by_coordinates):
        rows = by_coordinates[coordinates]
        immutable = [row for row in rows if navigation_point_has_immutable_identity(row)]
        destination_ids = {_clean(row.get("destination_id", "")) for row in immutable}
        if len(destination_ids) != 1:
            return None
        destination_id = next(iter(destination_ids))
        selected.append(
            min(
                (row for row in immutable if _clean(row.get("destination_id", "")) == destination_id),
                key=lambda row: (
                    _clean(row.get("raw_identity", "")),
                    _point_spawn_ids(row),
                    _clean(row.get("source", "")),
                ),
            )
        )
    destination_ids = [_clean(point.get("destination_id", "")) for point in selected]
    if len(destination_ids) != len(set(destination_ids)):
        return None
    return tuple(sorted(selected, key=lambda point: _clean(point.get("destination_id", ""))))


def _legacy_migration_candidate(
    *,
    action_id: str,
    point: Mapping[str, Any],
    zone_name: str,
    enemy: str,
    items: tuple[str, ...],
    group_id: str,
    source_action_span_ids: tuple[str, ...],
    source_revisions: tuple[tuple[str, int], ...],
    span_rows: tuple[tuple[str, SourceActionSpan, str, int], ...],
) -> ObjectiveDestinationCandidate:
    destination_id = _clean(point.get("destination_id", ""))
    coordinate_support, coordinate_comparison = _coordinate_evidence(span_rows)
    return ObjectiveDestinationCandidate(
        candidate_id=_candidate_id(action_id, destination_id),
        action_id=action_id,
        source_action_span_ids=source_action_span_ids,
        source_sites=tuple(site for site, _revision in source_revisions),
        source_revisions=source_revisions,
        coordinate_support=coordinate_support,
        coordinate_comparison=coordinate_comparison,
        action="obtain",
        items=items,
        enemies=(enemy,),
        result_relation="obtain-from",
        destination_id=destination_id,
        zone=int(point.get("zone", 0) or 0),
        zone_name=zone_name,
        target_name=enemy,
        target_kind="enemy",
        target_point=_point_tuple(point),
        raw_identity=_clean(point.get("raw_identity", "")),
        raw_spawn_ids=_point_spawn_ids(point),
        cluster_policy_version=_clean(point.get("cluster_policy_version", "")),
        evidence_level="reviewed-legacy-action-migration",
        group_id=group_id,
        metadata_class="legacy-action-migration",
        transport_id="",
        battlefield_id="",
        label=f"{enemy} in {zone_name}",
        arrival_instruction=(
            f"Defeat {enemy} in {zone_name} to obtain {_format_items(items)}."
        ),
        route_ready=False,
    )


def _apply_legacy_action_migrations(
    *,
    native: NativeObjective,
    reconciled: ReconciledObjective,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
    reviewed_overrides: Mapping[str, Any] | None,
    points: tuple[Mapping[str, Any], ...],
    zone_names: Mapping[int, str],
    ledger: tuple[ObjectiveActionLedgerRow, ...],
    candidates: tuple[ObjectiveDestinationCandidate, ...],
    groups: tuple[ObjectiveDestinationGroup, ...],
) -> tuple[
    tuple[ObjectiveActionLedgerRow, ...],
    tuple[ObjectiveDestinationCandidate, ...],
    tuple[ObjectiveDestinationGroup, ...],
    tuple[LegacyDestinationOutcome, ...],
]:
    legacy_rows = _legacy_override_rows(reviewed_overrides, native)
    if not legacy_rows:
        return ledger, candidates, groups, ()
    stable_rows: dict[str, Mapping[str, Any]] = {}
    for raw in legacy_rows:
        stable_id = _legacy_override_stable_id(native, raw)
        if stable_id in stable_rows:
            raise ObjectiveDestinationError(f"Duplicate legacy objective destination id {stable_id!r}.")
        stable_rows[stable_id] = raw

    migration_root = (
        reviewed_overrides.get("legacy_action_migrations", {})
        if isinstance(reviewed_overrides, Mapping)
        else {}
    )
    if not isinstance(migration_root, Mapping):
        raise ObjectiveDestinationError("legacy_action_migrations must be an object.")
    raw_migration = migration_root.get(native.key)
    if raw_migration is None:
        return (
            ledger,
            candidates,
            groups,
            tuple(
                _legacy_outcome(
                    native=native,
                    raw=raw,
                    action_id="",
                    classification="unresolved",
                    reason="legacy-action-migration-required",
                    source_revisions=tuple(
                        sorted(
                            (str(site), int(revision or 0))
                            for site, revision in (
                                raw.get("source_revisions", {}).items()
                                if isinstance(raw.get("source_revisions"), Mapping)
                                else ()
                            )
                        )
                    ),
                )
                for _stable_id, raw in sorted(stable_rows.items())
            ),
        )
    if not isinstance(raw_migration, Mapping):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} must be an object."
        )

    pages = _source_pages(bg, ffxiclopedia)
    action_id = _clean(raw_migration.get("action_id", ""))
    _validate_action_override_revisions(action_id, raw_migration, pages)
    source_revisions = tuple(
        (site, page.revision_id)
        for site, page in pages.items()
        if page is not None
    )
    if bg is None or ffxiclopedia is None:
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} requires both pinned source pages."
        )
    parent_index = next(
        (index for index, row in enumerate(ledger) if row.action_id == action_id),
        None,
    )
    parent_claim: tuple[ReconciledStep, ReconciledActionClaim] | None = next(
        (
            (step, claim)
            for step in reconciled.steps
            for claim in step.claims
            if claim.stable_claim_id == action_id
        ),
        None,
    )
    if parent_index is None or parent_claim is None:
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} references stale action {action_id!r}."
        )
    parent = ledger[parent_index]
    parent_step, parent_claim_row = parent_claim
    if (
        _normalized_action(parent.action) != "obtain"
        or parent.status != "unresolved"
        or parent.reason != "missing-zone"
        or parent.candidate_ids
        or not parent.material
        or not parent_claim_row.material
        or _normalized_action(parent_claim_row.action) != "obtain"
        or parent_claim_row.relationship != "obtain-item"
        or parent_claim_row.required_count != 4
        or parent_claim_row.count_mode != "inventory-gain"
        or not parent_claim_row.count_explicit
    ):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} no longer matches one exact four-item obtain claim."
        )
    span_rows = _span_rows(native, parent_step, parent_claim_row, bg, ffxiclopedia)

    zone = int(raw_migration.get("zone", 0) or 0)
    zone_name = _clean(raw_migration.get("zone_name", ""))
    if zone <= 0 or _clean(zone_names.get(zone, "")).casefold() != zone_name.casefold():
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} has stale navigation zone metadata."
        )
    items = _strings(raw_migration.get("items"), "items", required=True)
    parent_item_keys = {_clean(value).casefold() for value in parent_step.items}
    if (
        len(items) != 4
        or len(parent_item_keys) != 4
        or {_clean(value).casefold() for value in items} != parent_item_keys
        or _clean(parent_claim_row.target).casefold() not in parent_item_keys
    ):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} no longer owns the exact four-item objective."
        )
    legacy_source_step_ids = _strings(
        raw_migration.get("legacy_source_step_ids"),
        "legacy_source_step_ids",
        required=True,
    )
    legacy_source_claim_ids = _strings(
        raw_migration.get("legacy_source_claim_ids", []),
        "legacy_source_claim_ids",
    )
    reconciled_step_ids = {step.stable_step_id for step in reconciled.steps}
    reconciled_claim_ids = {
        claim.stable_claim_id for step in reconciled.steps for claim in step.claims
    }
    if not set(legacy_source_step_ids).issubset(reconciled_step_ids) or not set(
        legacy_source_claim_ids
    ).issubset(reconciled_claim_ids):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} references stale reconciled evidence."
        )
    source_facts = raw_migration.get("source_facts")
    if not isinstance(source_facts, Mapping) or set(source_facts) != {"bg", "ffxiclopedia"}:
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} lacks exact source fact maps."
        )
    expected_fact_fields = {
        "bg": {"item_step_id", "farming_step_id"},
        "ffxiclopedia": {
            "item_step_id",
            "drop_step_id",
            "enemy_step_id",
            "farming_zone_step_id",
        },
    }
    fact_rows: dict[tuple[str, str], tuple[Any, str, str]] = {}
    fact_suffixes = {
        "item_step_id": "farming-items-fact-01",
        "farming_step_id": "farming-claim-fact-01",
        "drop_step_id": "farming-drop-fact-01",
        "enemy_step_id": "farming-enemies-fact-01",
        "farming_zone_step_id": "farming-zone-fact-01",
    }
    for site, page in (("bg", bg), ("ffxiclopedia", ffxiclopedia)):
        site_facts = source_facts.get(site)
        if not isinstance(site_facts, Mapping) or set(site_facts) != expected_fact_fields[site]:
            raise ObjectiveDestinationError(
                f"Legacy action migration for {native.key!r} has malformed {site} source facts."
            )
        for field in sorted(site_facts):
            step, source_step_id = _source_fact_step(
                native=native,
                page=page,
                site=site,
                source_step_id=site_facts[field],
            )
            fact_rows[(site, field)] = (
                step,
                source_step_id,
                f"{source_step_id}:{fact_suffixes[field]}",
            )

    mappings = raw_migration.get("mappings")
    if not isinstance(mappings, list) or not mappings or any(
        not isinstance(row, Mapping) for row in mappings
    ):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} lacks mapping rows."
        )
    mapping_by_stable_id: dict[str, Mapping[str, Any]] = {}
    configured_groups: list[tuple[str, str, Mapping[str, str]]] = []
    for mapping in mappings:
        short_id = _clean(mapping.get("legacy_override_id", "")).casefold()
        stable_id = f"{native.key}:destination:{short_id}"
        if not _STABLE_ID.fullmatch(short_id) or stable_id in mapping_by_stable_id:
            raise ObjectiveDestinationError(
                f"Legacy action migration for {native.key!r} repeats or malforms an override id."
            )
        mapping_by_stable_id[stable_id] = mapping
        raw_groups = mapping.get("enemy_groups")
        if not isinstance(raw_groups, list) or not raw_groups or any(
            not isinstance(group, Mapping) for group in raw_groups
        ):
            raise ObjectiveDestinationError(
                f"Legacy action migration mapping {short_id!r} lacks enemy groups."
            )
        for raw_group in raw_groups:
            group_short_id = _clean(raw_group.get("id", "")).casefold()
            enemy = _clean(raw_group.get("enemy", ""))
            mentions = raw_group.get("source_mentions")
            if (
                not _STABLE_ID.fullmatch(group_short_id)
                or not enemy
                or not isinstance(mentions, Mapping)
                or set(mentions) != {"bg", "ffxiclopedia"}
            ):
                raise ObjectiveDestinationError(
                    f"Legacy action migration mapping {short_id!r} has a malformed enemy group."
                )
            cleaned_mentions = {
                site: _clean(value) for site, value in mentions.items()
            }
            if (
                not all(cleaned_mentions.values())
                or cleaned_mentions["bg"].casefold() != enemy.casefold()
                or cleaned_mentions["ffxiclopedia"].casefold()
                != re.sub(r"\s+quadav$", "", enemy, flags=re.IGNORECASE).casefold()
            ):
                raise ObjectiveDestinationError(
                    f"Legacy action migration group {group_short_id!r} has stale source aliases."
                )
            configured_groups.append((group_short_id, enemy, cleaned_mentions))
    if set(mapping_by_stable_id).difference(stable_rows):
        unknown = sorted(set(mapping_by_stable_id).difference(stable_rows))[0]
        raise ObjectiveDestinationError(
            f"Legacy action migration references unknown override {unknown!r}."
        )
    group_ids = [row[0] for row in configured_groups]
    enemy_names = [row[1].casefold() for row in configured_groups]
    if len(group_ids) != len(set(group_ids)) or len(enemy_names) != len(set(enemy_names)):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} repeats an enemy group."
        )

    all_enemies = tuple(row[1] for row in configured_groups)
    item_keys = {item.casefold() for item in items}
    bg_item_step = fact_rows[("bg", "item_step_id")][0]
    ffxi_item_step = fact_rows[("ffxiclopedia", "item_step_id")][0]
    if not item_keys.issubset(
        {_clean(value).casefold() for value in (*bg_item_step.items, *bg_item_step.linked_entities)}
    ) or not item_keys.issubset(
        {_clean(value).casefold() for value in (*ffxi_item_step.items, *ffxi_item_step.linked_entities)}
    ):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} item facts no longer match both sources."
        )
    bg_farming_step = fact_rows[("bg", "farming_step_id")][0]
    bg_entities = {_clean(value).casefold() for value in bg_farming_step.linked_entities}
    bg_farming_spans = tuple(
        span for span in bg_farming_step.action_spans if span.action == "fight"
    )
    if (
        bg_farming_step.action != "note"
        or len(bg_farming_spans) != 1
        or bg_farming_spans[0].material
        or tuple(value.casefold() for value in bg_farming_step.zone_candidates)
        != (zone_name.casefold(),)
        or not {enemy.casefold() for enemy in all_enemies}.issubset(bg_entities)
        or re.search(r"\bkill\b.*\bdrop\b.*\bfetich pieces\b", bg_farming_step.spoken_text, re.IGNORECASE)
        is None
    ):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} BG farming fact is stale."
        )
    ffxi_drop_step = fact_rows[("ffxiclopedia", "drop_step_id")][0]
    ffxi_enemy_step = fact_rows[("ffxiclopedia", "enemy_step_id")][0]
    ffxi_zone_step = fact_rows[("ffxiclopedia", "farming_zone_step_id")][0]
    if (
        ffxi_drop_step.action != "note"
        or ffxi_drop_step.action_spans
        or re.search(r"\bdrop from\b.*\bquadav\b", ffxi_drop_step.spoken_text, re.IGNORECASE)
        is None
        or ffxi_enemy_step.action != "note"
        or ffxi_enemy_step.action_spans
        or ffxi_zone_step.action != "note"
        or ffxi_zone_step.action_spans
        or tuple(value.casefold() for value in ffxi_zone_step.zone_candidates)
        != (zone_name.casefold(),)
        or re.search(r"\bgreat place for farming\b.*\bquadav\b", ffxi_zone_step.spoken_text, re.IGNORECASE)
        is None
    ):
        raise ObjectiveDestinationError(
            f"Legacy action migration for {native.key!r} FFXIclopedia facts are stale."
        )
    for _group_short_id, _enemy, mentions in configured_groups:
        if not _contains_exact_text(bg_farming_step.spoken_text, mentions["bg"]) or not _contains_exact_text(
            ffxi_enemy_step.spoken_text, mentions["ffxiclopedia"]
        ):
            raise ObjectiveDestinationError(
                f"Legacy action migration for {native.key!r} enemy facts are stale."
            )

    base_fact_ids = tuple(
        row[2]
        for _key, row in sorted(fact_rows.items())
    )
    support_ids = tuple(dict.fromkeys((*parent.source_action_span_ids, *base_fact_ids)))
    consumed_source_steps = {row[1] for row in fact_rows.values()}
    updated_ledger: list[ObjectiveActionLedgerRow] = []
    for row in ledger:
        if row.action_id == action_id:
            updated_ledger.append(row)
            continue
        retained_source_ids = tuple(
            source_id
            for source_id in row.source_action_span_ids
            if not (
                source_id.endswith(":context")
                and source_id.removesuffix(":context") in consumed_source_steps
            )
        )
        if retained_source_ids:
            updated_ledger.append(replace(row, source_action_span_ids=retained_source_ids))

    new_candidates: list[ObjectiveDestinationCandidate] = []
    new_groups: list[ObjectiveDestinationGroup] = []
    outcomes: list[LegacyDestinationOutcome] = []
    group_rows_by_mapping: dict[str, list[tuple[str, str, Mapping[str, str]]]] = {}
    for stable_id, mapping in mapping_by_stable_id.items():
        group_rows_by_mapping[stable_id] = []
        for raw_group in mapping["enemy_groups"]:
            group_short_id = _clean(raw_group.get("id", "")).casefold()
            group_rows_by_mapping[stable_id].append(
                next(row for row in configured_groups if row[0] == group_short_id)
            )

    for stable_id, raw in sorted(stable_rows.items()):
        mapping = mapping_by_stable_id.get(stable_id)
        if mapping is None:
            outcomes.append(
                _legacy_outcome(
                    native=native,
                    raw=raw,
                    action_id="",
                    classification="unresolved",
                    reason="legacy-action-migration-required",
                    source_revisions=tuple(
                        sorted(
                            (str(site), int(revision or 0))
                            for site, revision in (
                                raw.get("source_revisions", {}).items()
                                if isinstance(raw.get("source_revisions"), Mapping)
                                else ()
                            )
                        )
                    ),
                )
            )
            continue
        mapped_groups = group_rows_by_mapping[stable_id]
        raw_revisions = raw.get("source_revisions")
        raw_source_step_ids = _strings(raw.get("source_step_ids", []), "source_step_ids")
        raw_source_claim_ids = _strings(raw.get("source_claim_ids", []), "source_claim_ids")
        raw_items = _strings(raw.get("items", []), "items")
        raw_enemies = _strings(raw.get("enemies", []), "enemies")
        raw_reference = raw.get("reference")
        if (
            not isinstance(raw_revisions, Mapping)
            or {str(site): int(revision or 0) for site, revision in raw_revisions.items()}
            != dict(source_revisions)
            or _clean(raw.get("action", "")).casefold() != "farm"
            or raw_source_step_ids != legacy_source_step_ids
            or raw_source_claim_ids != legacy_source_claim_ids
            or {value.casefold() for value in raw_items} != item_keys
            or tuple(value.casefold() for value in raw_enemies)
            != tuple(enemy.casefold() for _group_id, enemy, _mentions in mapped_groups)
            or int(raw.get("zone", 0) or 0) != zone
            or _clean(raw.get("zone_name", "")).casefold() != zone_name.casefold()
            or not isinstance(raw_reference, Mapping)
            or _clean(raw_reference.get("kind", "")).casefold() != "enemy"
            or _clean(raw_reference.get("name", "")).casefold()
            not in {enemy.casefold() for _group_id, enemy, _mentions in mapped_groups}
        ):
            raise ObjectiveDestinationError(
                f"Legacy action migration for {stable_id!r} no longer matches its legacy identity."
            )

        pending_candidates: list[ObjectiveDestinationCandidate] = []
        pending_groups: list[ObjectiveDestinationGroup] = []
        ambiguous = False
        for group_short_id, enemy, _mentions in mapped_groups:
            matches = tuple(
                point
                for point in points
                if int(point.get("zone", 0) or 0) == zone
                and _clean(point.get("name", "")).casefold() == enemy.casefold()
                and _clean(point.get("kind", "")).casefold() == "enemy"
            )
            immutable = _immutable_enemy_instances(matches) if matches else ()
            if not matches or immutable is None or not immutable:
                ambiguous = True
                break
            group_id = f"{action_id}:group:{group_short_id}"
            group_candidates = tuple(
                _legacy_migration_candidate(
                    action_id=action_id,
                    point=point,
                    zone_name=zone_name,
                    enemy=enemy,
                    items=items,
                    group_id=group_id,
                    source_action_span_ids=support_ids,
                    source_revisions=source_revisions,
                    span_rows=span_rows,
                )
                for point in immutable
            )
            pending_candidates.extend(group_candidates)
            pending_groups.append(
                ObjectiveDestinationGroup(
                    group_id=group_id,
                    action_id=action_id,
                    zone=zone,
                    zone_name=zone_name,
                    candidate_ids=tuple(candidate.candidate_id for candidate in group_candidates),
                    evidence_level="reviewed-legacy-action-migration",
                    source_action_span_ids=support_ids,
                    route_ready=False,
                )
            )
        if ambiguous:
            outcomes.append(
                _legacy_outcome(
                    native=native,
                    raw=raw,
                    action_id=action_id,
                    classification="unresolved",
                    reason="legacy-action-migration-catalogue-ambiguous",
                    source_action_span_ids=support_ids,
                    source_revisions=source_revisions,
                )
            )
            continue
        new_candidates.extend(pending_candidates)
        new_groups.extend(pending_groups)
        outcomes.append(
            _legacy_outcome(
                native=native,
                raw=raw,
                action_id=action_id,
                classification="catalogue-candidate",
                reason="migrated-to-action-candidates",
                candidate_ids=tuple(candidate.candidate_id for candidate in pending_candidates),
                group_ids=tuple(group.group_id for group in pending_groups),
                source_action_span_ids=support_ids,
                source_revisions=source_revisions,
            )
        )

    all_candidates = tuple((*candidates, *new_candidates))
    all_groups = tuple((*groups, *new_groups))
    migrated_candidate_ids = tuple(candidate.candidate_id for candidate in new_candidates)
    parent_position = next(
        index for index, row in enumerate(updated_ledger) if row.action_id == action_id
    )
    updated_parent = updated_ledger[parent_position]
    if migrated_candidate_ids:
        updated_parent = replace(
            updated_parent,
            source_action_span_ids=support_ids,
            status="catalogue-candidate",
            reason="reviewed-legacy-action-migration",
            candidate_ids=tuple((*updated_parent.candidate_ids, *migrated_candidate_ids)),
        )
    else:
        updated_parent = replace(updated_parent, source_action_span_ids=support_ids)
    updated_ledger[parent_position] = updated_parent
    return (
        tuple(updated_ledger),
        all_candidates,
        tuple(sorted(all_groups, key=lambda group: group.group_id)),
        tuple(sorted(outcomes, key=lambda outcome: outcome.legacy_override_id)),
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
            status = "context-only"
            reason = "no-material-action-span"
            action = "context"
            material = False
        ledger.append(
            ObjectiveActionLedgerRow(
                action_id=action_id,
                source_action_span_ids=source_span_ids,
                action=action,
                status=status,
                reason=reason,
                candidate_ids=(),
                instruction=_instruction(step) if context_override is not None else "",
                material=material,
                route_ready=False,
            )
        )

    (
        migrated_ledger,
        migrated_candidates,
        migrated_groups,
        legacy_destination_outcomes,
    ) = _apply_legacy_action_migrations(
        native=native,
        reconciled=reconciled,
        bg=bg,
        ffxiclopedia=ffxiclopedia,
        reviewed_overrides=reviewed_overrides,
        points=points,
        zone_names=zone_names,
        ledger=tuple(ledger),
        candidates=tuple(candidates),
        groups=tuple(groups),
    )
    ledger = list(migrated_ledger)
    candidates = list(migrated_candidates)
    groups = list(migrated_groups)

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
        if not set(group.source_action_span_ids).issubset(
            ledger_by_id[group.action_id].source_action_span_ids
        ):
            raise ObjectiveDestinationError("Objective destination group uses evidence outside its parent action.")
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
    outcome_ids = [outcome.legacy_override_id for outcome in legacy_destination_outcomes]
    if len(outcome_ids) != len(set(outcome_ids)):
        raise ObjectiveDestinationError("Legacy destination outcomes contain duplicate override IDs.")
    if set(outcome_ids) != {
        _legacy_override_stable_id(native, raw)
        for raw in _legacy_override_rows(reviewed_overrides, native)
    }:
        raise ObjectiveDestinationError("Legacy destination overrides are not accounted exactly once.")
    group_by_id = {group.group_id: group for group in groups}
    for outcome in legacy_destination_outcomes:
        if outcome.route_ready or outcome.classification not in {"catalogue-candidate", "unresolved"}:
            raise ObjectiveDestinationError("Legacy destination outcome has an invalid route state.")
        if outcome.classification == "catalogue-candidate":
            if (
                not outcome.action_id
                or not outcome.candidate_ids
                or not outcome.group_ids
                or any(candidate_id not in candidate_by_id for candidate_id in outcome.candidate_ids)
                or any(group_id not in group_by_id for group_id in outcome.group_ids)
                or not set(outcome.source_action_span_ids).issubset(
                    ledger_by_id[outcome.action_id].source_action_span_ids
                )
            ):
                raise ObjectiveDestinationError("Migrated legacy destination outcome is inconsistent.")
        elif outcome.candidate_ids or outcome.group_ids:
            raise ObjectiveDestinationError("Unresolved legacy destination outcome has movement children.")
    return ObjectiveActionResolution(
        tuple(ledger),
        tuple(candidates),
        tuple(groups),
        tuple(review_items),
        legacy_destination_outcomes,
    )


def task3_route_contract_inputs(
    resolution: ObjectiveActionResolution,
) -> tuple[
    tuple[ObjectiveActionLedgerRow, ...],
    tuple[ObjectiveDestinationCandidate, ...],
    tuple[ObjectiveDestinationGroup, ...],
]:
    """Expose only Task 3's typed, still-nonroutable contract inputs."""

    if any(row.route_ready for row in resolution.ledger):
        raise ObjectiveDestinationError("Task 3 action ledger cannot pre-authorize a route.")
    if any(candidate.route_ready for candidate in resolution.candidates):
        raise ObjectiveDestinationError("Task 3 destination candidate cannot pre-authorize a route.")
    if any(group.route_ready for group in resolution.groups):
        raise ObjectiveDestinationError("Task 3 destination group cannot pre-authorize a route.")
    candidate_ids = {candidate.candidate_id for candidate in resolution.candidates}
    ledger_ids = {row.action_id for row in resolution.ledger}
    if any(candidate.action_id not in ledger_ids for candidate in resolution.candidates):
        raise ObjectiveDestinationError("Route candidate has no typed action-ledger owner.")
    if any(
        candidate_id not in candidate_ids
        for group in resolution.groups
        for candidate_id in group.candidate_ids
    ):
        raise ObjectiveDestinationError("Route group contains an unknown typed candidate.")
    return resolution.ledger, resolution.candidates, resolution.groups


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
    for raw in rows:
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
    """Resolve only immutable shared overrides; legacy rows are audit-only migration input."""

    rows = _override_rows(reviewed_overrides, native)
    if not rows:
        return ()
    points = tuple(navigation_points)
    edges = tuple(navigation_edges)
    results: list[ReviewedObjectiveDestination] = []
    seen_ids: set[str] = set()
    for raw in rows:
        isolated_overrides = {
            "objective_destination_overrides": {native.key: [raw]}
        }
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
        for row in resolved:
            if row.stable_id in seen_ids:
                raise ObjectiveDestinationError(
                    f"Duplicate reviewed objective destination id {row.stable_id!r}."
                )
            seen_ids.add(row.stable_id)
            results.append(row)
    return tuple(sorted(results, key=lambda row: row.stable_id))

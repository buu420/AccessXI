from __future__ import annotations

import re
from dataclasses import dataclass, replace

from .model import ParsedObjective, SourceActionSpan, SourceStep


@dataclass(frozen=True, slots=True)
class ReviewedNavigationTarget:
    target_type: str
    zone: int
    zone_name: str
    name: str
    kind: str
    arrival_instruction: str


@dataclass(frozen=True, slots=True)
class ReviewedMissionDestination:
    stable_id: str
    source_step_ids: tuple[str, ...]
    action: str
    items: tuple[str, ...]
    enemies: tuple[str, ...]
    zone: int
    zone_name: str
    camp_label: str
    target_name: str
    target_kind: str
    arrival_instruction: str
    canonical_ingress_edge_id: int = 0
    canonical_ingress_from_zone: int = 0
    transport_id: str = ""
    route_evidence: str = ""


@dataclass(frozen=True, slots=True)
class ReviewedObjectiveDestination:
    stable_id: str
    source_step_ids: tuple[str, ...]
    action: str
    items: tuple[str, ...]
    enemies: tuple[str, ...]
    destination_id: str
    zone: int
    zone_name: str
    label: str
    target_name: str
    target_kind: str
    target_point: tuple[float, float, float] | None
    arrival_instruction: str
    eligibility: str = "catalogue"
    route_contract_id: str = ""
    canonical_ingress_edge_id: int = 0
    canonical_ingress_from_zone: int = 0
    transport_id: str = ""
    instruction_only: bool = False
    source_revisions: tuple[tuple[str, int], ...] = ()
    source_claim_ids: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class ObjectiveActionLedgerRow:
    action_id: str
    source_action_span_ids: tuple[str, ...]
    action: str
    status: str
    reason: str
    candidate_ids: tuple[str, ...]
    instruction: str
    material: bool
    route_ready: bool = False


@dataclass(frozen=True, slots=True)
class ObjectiveDestinationCandidate:
    candidate_id: str
    action_id: str
    source_action_span_ids: tuple[str, ...]
    source_sites: tuple[str, ...]
    source_revisions: tuple[tuple[str, int], ...]
    coordinate_support: tuple[tuple[str, str, str], ...]
    coordinate_comparison: str
    action: str
    items: tuple[str, ...]
    enemies: tuple[str, ...]
    result_relation: str
    destination_id: str
    zone: int
    zone_name: str
    target_name: str
    target_kind: str
    target_point: tuple[float, float, float]
    raw_identity: str
    raw_spawn_ids: tuple[int, ...]
    cluster_policy_version: str
    evidence_level: str
    group_id: str
    metadata_class: str
    transport_id: str
    battlefield_id: str
    label: str
    arrival_instruction: str
    route_ready: bool = False


@dataclass(frozen=True, slots=True)
class ObjectiveDestinationGroup:
    group_id: str
    action_id: str
    zone: int
    zone_name: str
    candidate_ids: tuple[str, ...]
    evidence_level: str
    route_ready: bool = False


@dataclass(frozen=True, slots=True)
class ObjectiveResolutionReviewItem:
    review_id: str
    action_id: str
    target_name: str
    zone_name: str
    source_sites: tuple[str, ...]
    source_action_span_ids: tuple[str, ...]
    reason: str
    route_ready: bool = False


@dataclass(frozen=True, slots=True)
class ObjectiveActionResolution:
    ledger: tuple[ObjectiveActionLedgerRow, ...]
    candidates: tuple[ObjectiveDestinationCandidate, ...]
    groups: tuple[ObjectiveDestinationGroup, ...]
    review_items: tuple[ObjectiveResolutionReviewItem, ...] = ()


@dataclass(frozen=True, slots=True)
class ReconciledCandidate:
    field: str
    value: str
    comparison: str
    sources: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class ReconciledActionClaim:
    stable_claim_id: str
    order: int
    action: str
    relationship: str
    target: str
    target_kind: str
    comparison: str
    alignment_score: int
    alignment_reason: str
    unpaired_reason: str
    bg_span_order: int
    ffxiclopedia_span_order: int
    candidates: tuple[ReconciledCandidate, ...]


@dataclass(frozen=True, slots=True)
class ReconciledStep:
    stable_step_id: str
    order: int
    source_orders: tuple[int, int]
    comparison: str
    agreed_fields: tuple[str, ...]
    conflicting_fields: tuple[str, ...]
    bg_instruction: str
    ffxiclopedia_instruction: str
    action: str
    entities: tuple[str, ...]
    items: tuple[str, ...]
    zones: tuple[str, ...]
    grid_coordinates: tuple[str, ...]
    claims: tuple[ReconciledActionClaim, ...] = ()
    alignment_score: int = 0
    alignment_reason: str = ""
    unpaired_reason: str = ""
    route_ready: bool = False
    navigation_target: ReviewedNavigationTarget | None = None


@dataclass(frozen=True, slots=True)
class ReconciledObjective:
    native_key: str
    steps: tuple[ReconciledStep, ...]
    dynamic_candidate_grid: tuple[str, ...] = ()
    dynamic_candidate_comparison: str = "none"
    selected_candidate_grid: str | None = None
    action_resolution_ledger: tuple[ObjectiveActionLedgerRow, ...] = ()
    objective_destination_candidates: tuple[ObjectiveDestinationCandidate, ...] = ()
    objective_destination_groups: tuple[ObjectiveDestinationGroup, ...] = ()
    objective_resolution_review_items: tuple[ObjectiveResolutionReviewItem, ...] = ()
    objective_destinations: tuple[ReviewedObjectiveDestination, ...] = ()
    mission_destinations: tuple[ReviewedMissionDestination, ...] = ()


def _unique(values: tuple[str, ...] | list[str]) -> tuple[str, ...]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        value = str(value or "").strip()
        key = value.casefold()
        if value and key not in seen:
            seen.add(key)
            result.append(value)
    return tuple(result)


def _tokens(value: str) -> set[str]:
    return {
        token
        for token in re.findall(r"[a-z0-9?]+", value.casefold())
        if len(token) >= 3 and token not in {"the", "and", "then", "with", "from", "this", "that"}
    }


def _intersection(left: tuple[str, ...], right: tuple[str, ...]) -> set[str]:
    left_keys = {value.casefold() for value in left}
    return left_keys.intersection(value.casefold() for value in right)


def _span_values(span: SourceActionSpan | None) -> dict[str, tuple[str, ...]]:
    if span is None:
        return {}
    key_item_keys = {value.casefold() for value in span.key_item_mentions}
    return {
        "target": (span.target,) if span.target else (),
        "npc": span.npc_mentions,
        "object": span.object_mentions,
        "enemy": span.enemy_mentions,
        "item": tuple(value for value in span.item_mentions if value.casefold() not in key_item_keys),
        "key-item": span.key_item_mentions,
        "transport": span.transport_mentions,
        "zone": span.zone_mentions,
        "map": span.map_numbers,
        "grid": span.grid_coordinates,
        "result-item": span.result_items,
    }


def _candidate_rows(
    left: SourceActionSpan | None,
    right: SourceActionSpan | None,
) -> tuple[ReconciledCandidate, ...]:
    left_values = _span_values(left)
    right_values = _span_values(right)
    rows: list[ReconciledCandidate] = []
    for field in (
        "target", "npc", "object", "enemy", "item", "key-item", "transport", "zone", "map", "grid", "result-item"
    ):
        left_by_key = {value.casefold(): value for value in left_values.get(field, ())}
        right_by_key = {value.casefold(): value for value in right_values.get(field, ())}
        for key in sorted(set(left_by_key).union(right_by_key)):
            sources: tuple[str, ...]
            if key in left_by_key and key in right_by_key:
                value = left_by_key[key]
                comparison = "corroborated"
                sources = ("bg", "ffxiclopedia")
            elif key in left_by_key:
                value = left_by_key[key]
                comparison = "single-source"
                sources = ("bg",)
            else:
                value = right_by_key[key]
                comparison = "single-source"
                sources = ("ffxiclopedia",)
            rows.append(ReconciledCandidate(field, value, comparison, sources))
    return tuple(rows)


def _span_alignment_score(left: SourceActionSpan, right: SourceActionSpan) -> int:
    score = 0
    if left.action == right.action:
        score += 5
    elif {left.action, right.action} == {"fight", "obtain"} and (
        left.result_relation == "obtain-from" or right.result_relation == "obtain-from"
    ):
        score += 4
    if left.relationship == right.relationship:
        score += 3
    if left.target and right.target and left.target.casefold() == right.target.casefold():
        score += 6
    score += 2 * len(_intersection(left.zone_mentions, right.zone_mentions))
    score += 2 * len(_intersection(left.item_mentions, right.item_mentions))
    score += 2 * len(_intersection(left.result_items, right.result_items))
    return score


def _align_spans(
    left: tuple[SourceActionSpan, ...],
    right: tuple[SourceActionSpan, ...],
) -> tuple[tuple[SourceActionSpan | None, SourceActionSpan | None, int], ...]:
    rows = len(left) + 1
    columns = len(right) + 1
    scores = [[0 for _ in range(columns)] for _ in range(rows)]
    choices = [["" for _ in range(columns)] for _ in range(rows)]
    for i in range(1, rows):
        choices[i][0] = "left"
    for j in range(1, columns):
        choices[0][j] = "right"
    for i in range(1, rows):
        for j in range(1, columns):
            pair_score = _span_alignment_score(left[i - 1], right[j - 1])
            diagonal = scores[i - 1][j - 1] + pair_score if pair_score >= 5 else -1
            take_left = scores[i - 1][j]
            take_right = scores[i][j - 1]
            best = max(diagonal, take_left, take_right)
            scores[i][j] = best
            if diagonal == best:
                choices[i][j] = "pair"
            elif take_left == best:
                choices[i][j] = "left"
            else:
                choices[i][j] = "right"
    aligned: list[tuple[SourceActionSpan | None, SourceActionSpan | None, int]] = []
    i, j = len(left), len(right)
    while i > 0 or j > 0:
        choice = choices[i][j]
        if choice == "pair":
            pair_score = _span_alignment_score(left[i - 1], right[j - 1])
            aligned.append((left[i - 1], right[j - 1], pair_score))
            i -= 1
            j -= 1
        elif choice == "left" or j == 0:
            aligned.append((left[i - 1], None, 0))
            i -= 1
        else:
            aligned.append((None, right[j - 1], 0))
            j -= 1
    aligned.reverse()
    return tuple(aligned)


def _alignment_score(left: SourceStep, right: SourceStep) -> int:
    score = 0
    if left.action == right.action:
        score += 1 if left.action == "note" else 4
    if left.depth == right.depth:
        score += 1
    score += min(8, 5 * len(_intersection(left.linked_entities, right.linked_entities)))
    score += min(6, 4 * len(_intersection(left.zone_candidates, right.zone_candidates)))
    score += min(8, 4 * len(_intersection(left.grid_coordinates, right.grid_coordinates)))
    score += min(6, 3 * len(_intersection(left.key_items, right.key_items)))
    score += min(4, 2 * len(_intersection(left.items, right.items)))
    typed_scores = [
        _span_alignment_score(left_span, right_span)
        for left_span in left.action_spans
        for right_span in right.action_spans
    ]
    if typed_scores:
        score += min(12, max(typed_scores))
    left_tokens = _tokens(left.spoken_text)
    right_tokens = _tokens(right.spoken_text)
    if left_tokens and right_tokens:
        overlap = len(left_tokens.intersection(right_tokens)) / len(left_tokens.union(right_tokens))
        if overlap >= 0.15:
            score += min(4, 1 + int(overlap * 6))
    return score


def _align_steps(
    left: tuple[SourceStep, ...],
    right: tuple[SourceStep, ...],
) -> tuple[tuple[SourceStep | None, SourceStep | None, int, str], ...]:
    rows = len(left) + 1
    columns = len(right) + 1
    scores = [[0 for _ in range(columns)] for _ in range(rows)]
    choices = [["" for _ in range(columns)] for _ in range(rows)]
    for i in range(1, rows):
        choices[i][0] = "left"
    for j in range(1, columns):
        choices[0][j] = "right"

    for i in range(1, rows):
        for j in range(1, columns):
            pair_score = _alignment_score(left[i - 1], right[j - 1])
            diagonal = scores[i - 1][j - 1] + pair_score if pair_score >= 4 else -1
            take_left = scores[i - 1][j]
            take_right = scores[i][j - 1]
            best = max(diagonal, take_left, take_right)
            scores[i][j] = best
            if diagonal == best:
                choices[i][j] = "pair"
            elif take_left == best:
                choices[i][j] = "left"
            else:
                choices[i][j] = "right"

    aligned: list[tuple[SourceStep | None, SourceStep | None, int, str]] = []
    i, j = len(left), len(right)
    while i > 0 or j > 0:
        choice = choices[i][j]
        if choice == "pair":
            pair_score = _alignment_score(left[i - 1], right[j - 1])
            aligned.append((left[i - 1], right[j - 1], pair_score, "paired-score"))
            i -= 1
            j -= 1
        elif choice == "left" or j == 0:
            aligned.append((left[i - 1], None, 0, "unpaired-bg"))
            i -= 1
        else:
            aligned.append((None, right[j - 1], 0, "unpaired-ffxiclopedia"))
            j -= 1
    aligned.reverse()
    return tuple(aligned)


def _coordinate_sort(value: str) -> tuple[str, int]:
    match = re.fullmatch(r"([A-P])-([0-9]+)", value, re.IGNORECASE)
    if not match:
        return value.casefold(), 0
    return match.group(1).upper(), int(match.group(2))


def _dynamic_candidates(objective: ParsedObjective) -> tuple[str, ...]:
    candidates: list[str] = []
    dynamic_depth: int | None = None
    for step in objective.steps:
        text = step.source_text
        lower = text.casefold()
        begins_dynamic = "???" in text and any(term in lower for term in ("one of", "four location", "four brazier"))
        if begins_dynamic:
            dynamic_depth = step.depth
        elif dynamic_depth is not None and step.depth <= dynamic_depth:
            dynamic_depth = None
        if not begins_dynamic and dynamic_depth is None:
            continue

        relevant = text
        for separator in (" accessible from", ": near ", " near ", ": from ", " from the batallia"):
            index = relevant.casefold().find(separator)
            if index >= 0:
                relevant = relevant[:index]
                break
        coordinates = tuple(
            match.group(1).upper()
            for match in re.finditer(r"(?<![A-Z0-9])([A-P]-\d{1,2})(?!\d)", relevant, re.IGNORECASE)
        )
        if begins_dynamic and not coordinates:
            continue
        candidates.extend(coordinates)
    return tuple(sorted(_unique(candidates), key=_coordinate_sort))


def _comparison(left: SourceStep | None, right: SourceStep | None) -> tuple[str, tuple[str, ...], tuple[str, ...]]:
    if left is None or right is None:
        return "single-source", (), ()
    agreed: list[str] = []
    conflicts: list[str] = []
    left_actions = {span.action for span in left.action_spans} or {left.action}
    right_actions = {span.action for span in right.action_spans} or {right.action}
    if left_actions.intersection(right_actions):
        agreed.append("action")
    elif (
        not left.action_spans
        and not right.action_spans
        and left.action != "note"
        and right.action != "note"
        and {left.action, right.action} not in (
        {"use", "wait"},
        {"travel", "talk"},
        {"fight", "obtain"},
        )
    ):
        conflicts.append("action")

    for field_name in ("zone_candidates", "map_numbers", "grid_coordinates"):
        left_values = getattr(left, field_name)
        right_values = getattr(right, field_name)
        if left_values and right_values and _intersection(left_values, right_values):
            agreed.append(field_name)
    if _intersection(left.linked_entities, right.linked_entities):
        agreed.append("entities")
    if _intersection(left.key_items, right.key_items):
        agreed.append("key_items")
    if _intersection(left.items, right.items):
        agreed.append("items")

    if conflicts:
        return "conflict", tuple(agreed), tuple(conflicts)
    if agreed:
        return "corroborated", tuple(agreed), ()
    return "compatible", (), ()


def _reconciled_claims(
    stable_step_id: str,
    left: SourceStep | None,
    right: SourceStep | None,
) -> tuple[ReconciledActionClaim, ...]:
    left_spans = left.action_spans if left is not None else ()
    right_spans = right.action_spans if right is not None else ()
    aligned = _align_spans(left_spans, right_spans)
    claims: list[ReconciledActionClaim] = []
    immutable_kinds = {"npc", "object", "enemy", "question-mark", "entrance", "transport"}
    for order, (bg_span, ffxi_span, score) in enumerate(aligned, start=1):
        candidates = _candidate_rows(bg_span, ffxi_span)
        if bg_span is None:
            comparison = "single-source"
            alignment_reason = "unpaired-ffxiclopedia-span"
            unpaired_reason = "no-compatible-bg-action-span"
        elif ffxi_span is None:
            comparison = "single-source"
            alignment_reason = "unpaired-bg-span"
            unpaired_reason = "no-compatible-ffxiclopedia-action-span"
        else:
            immutable_conflict = (
                bg_span.action == ffxi_span.action
                and bg_span.target_kind == ffxi_span.target_kind
                and bg_span.target_kind in immutable_kinds
                and bg_span.target
                and ffxi_span.target
                and bg_span.target.casefold() != ffxi_span.target.casefold()
            )
            if immutable_conflict:
                comparison = "conflict"
            elif any(candidate.comparison == "corroborated" for candidate in candidates):
                comparison = "corroborated"
            else:
                comparison = "compatible"
            alignment_reason = "paired-action-span"
            unpaired_reason = ""
        primary = bg_span or ffxi_span
        assert primary is not None
        target_candidate = next(
            (candidate.value for candidate in candidates if candidate.field == "target" and candidate.comparison == "corroborated"),
            "",
        )
        kind = primary.target_kind
        if bg_span is not None and ffxi_span is not None and bg_span.target_kind != ffxi_span.target_kind:
            kind = ""
        claims.append(
            ReconciledActionClaim(
                stable_claim_id=f"{stable_step_id}:claim-{order:02d}",
                order=order,
                action=primary.action,
                relationship=(
                    bg_span.relationship
                    if bg_span is not None
                    and ffxi_span is not None
                    and bg_span.relationship == ffxi_span.relationship
                    else primary.relationship
                ),
                target=target_candidate,
                target_kind=kind,
                comparison=comparison,
                alignment_score=score,
                alignment_reason=alignment_reason,
                unpaired_reason=unpaired_reason,
                bg_span_order=bg_span.order if bg_span is not None else 0,
                ffxiclopedia_span_order=ffxi_span.order if ffxi_span is not None else 0,
                candidates=candidates,
            )
        )
    return tuple(claims)


def reconcile_objectives(
    native_key: str,
    bg: ParsedObjective | None,
    ffxiclopedia: ParsedObjective | None,
) -> ReconciledObjective:
    left = bg.steps if bg is not None else ()
    right = ffxiclopedia.steps if ffxiclopedia is not None else ()
    aligned = _align_steps(left, right)
    steps: list[ReconciledStep] = []
    for order, (bg_step, ffxi_step, alignment_score, alignment_reason) in enumerate(aligned, start=1):
        stable_step_id = f"{native_key}:step-{order:03d}"
        comparison, agreed, conflicts = _comparison(bg_step, ffxi_step)
        claims = _reconciled_claims(stable_step_id, bg_step, ffxi_step)
        if any(claim.comparison == "conflict" for claim in claims):
            comparison = "conflict"
            conflicts = _unique([*conflicts, "target_identity"])
        elif comparison != "conflict" and any(claim.comparison == "corroborated" for claim in claims):
            comparison = "corroborated"
        entities = _unique(
            [
                *(bg_step.linked_entities if bg_step is not None else ()),
                *(ffxi_step.linked_entities if ffxi_step is not None else ()),
            ]
        )
        zones = _unique(
            [
                *(bg_step.zone_candidates if bg_step is not None else ()),
                *(ffxi_step.zone_candidates if ffxi_step is not None else ()),
            ]
        )
        coordinates = _unique(
            [
                *(bg_step.grid_coordinates if bg_step is not None else ()),
                *(ffxi_step.grid_coordinates if ffxi_step is not None else ()),
            ]
        )
        items = _unique(
            [
                *(bg_step.items if bg_step is not None else ()),
                *(ffxi_step.items if ffxi_step is not None else ()),
                *(
                    value
                    for source_step in (bg_step, ffxi_step)
                    if source_step is not None
                    for span in source_step.action_spans
                    for value in (*span.item_mentions, *span.result_items)
                ),
            ]
        )
        action = bg_step.action if bg_step is not None else ffxi_step.action if ffxi_step is not None else "note"
        unpaired_reason = ""
        if bg_step is None:
            unpaired_reason = "no-compatible-bg-step"
        elif ffxi_step is None:
            unpaired_reason = "no-compatible-ffxiclopedia-step"
        steps.append(
            ReconciledStep(
                stable_step_id=stable_step_id,
                order=order,
                source_orders=(bg_step.order if bg_step is not None else 0, ffxi_step.order if ffxi_step is not None else 0),
                comparison=comparison,
                agreed_fields=agreed,
                conflicting_fields=conflicts,
                bg_instruction=bg_step.spoken_text if bg_step is not None else "",
                ffxiclopedia_instruction=ffxi_step.spoken_text if ffxi_step is not None else "",
                action=action,
                entities=entities,
                items=items,
                zones=zones,
                grid_coordinates=coordinates,
                claims=claims,
                alignment_score=alignment_score,
                alignment_reason=alignment_reason,
                unpaired_reason=unpaired_reason,
            )
        )

    bg_text = " ".join(step.source_text.casefold() for step in left)
    ffxi_text = " ".join(step.source_text.casefold() for step in right)
    result_conflict = "always fail" in bg_text and "rare" in ffxi_text and "success" in ffxi_text
    if result_conflict:
        target_index = next(
            (
                index
                for index, step in enumerate(steps)
                if "always fail" in step.bg_instruction.casefold()
                or ("rare" in step.ffxiclopedia_instruction.casefold() and "success" in step.ffxiclopedia_instruction.casefold())
            ),
            None,
        )
        if target_index is not None:
            step = steps[target_index]
            steps[target_index] = replace(
                step,
                comparison="conflict",
                conflicting_fields=_unique([*step.conflicting_fields, "result"]),
                route_ready=False,
            )

    bg_candidates = _dynamic_candidates(bg) if bg is not None else ()
    ffxi_candidates = _dynamic_candidates(ffxiclopedia) if ffxiclopedia is not None else ()
    if bg_candidates and ffxi_candidates:
        dynamic_comparison = "corroborated" if bg_candidates == ffxi_candidates else "conflict"
        candidates = bg_candidates if dynamic_comparison == "corroborated" else tuple(
            sorted(_unique([*bg_candidates, *ffxi_candidates]), key=_coordinate_sort)
        )
    elif bg_candidates or ffxi_candidates:
        dynamic_comparison = "single-source"
        candidates = bg_candidates or ffxi_candidates
    else:
        dynamic_comparison = "none"
        candidates = ()

    return ReconciledObjective(
        native_key=native_key,
        steps=tuple(steps),
        dynamic_candidate_grid=candidates,
        dynamic_candidate_comparison=dynamic_comparison,
        selected_candidate_grid=None,
    )

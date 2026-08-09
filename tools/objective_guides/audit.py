from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from collections import Counter, defaultdict
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any


MISSION_CONTEXTS = (
    "San d'Oria",
    "Bastok",
    "Windurst",
    "Rise of the Zilart",
    "Chains of Promathia",
    "Assault",
    "Treasures of Aht Urhgan",
    "Campaign",
    "Wings of the Goddess",
    "Seekers of Adoulin",
    "Rhapsodies of Vana'diel",
    "The Voracious Resurgence",
    "A Crystalline Prophecy",
    "A Moogle Kupo d'Etat",
    "A Shantotto Ascension",
)
QUEST_CONTEXTS = (
    "sandoria",
    "bastok",
    "windurst",
    "jeuno",
    "other_areas",
    "outlands",
    "aht_urhgan",
    "crystal_war",
    "abyssea",
    "adoulin",
    "coalition",
)
CONTEXT_REASONS = frozenset(
    {"heading", "historical-explanation", "reward", "optional-background"}
)
ACTION_LIKE_CONTEXT_ACTIONS = frozenset(
    {
        "protect",
        "touch",
        "key-item-loss",
        "lose-key-item",
        "warning",
        "talk",
        "trade",
        "examine",
        "use",
        "fight",
        "farm",
        "obtain",
        "travel",
    }
)
ACTION_STATUSES = frozenset(
    {"catalogue-candidate", "instruction-only", "context-only", "conflict", "unresolved"}
)
INSTRUCTION_ONLY_ACTIONS = frozenset({"wait", "select", "choose", "menu", "warning"})
SOURCE_SITES = frozenset({"bg", "ffxiclopedia"})
CONTRACT_ID = re.compile(r"^route:v2:[0-9a-f]{64}$")
REVIEW_ID = re.compile(r"^review:v1:[0-9a-f]{64}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
MACHINE_REASON = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
STABLE_STEP_ID = re.compile(r"stable_step_id\s*=\s*\"([^\"\r\n]+)\"")
CONTRACT_DESTINATION_FIELDS = frozenset(
    {
        "name",
        "x",
        "z",
        "y",
        "kind",
        "destination_id",
        "raw_identity",
        "raw_spawn_ids",
        "cluster_policy_version",
    }
)
CONTRACT_EXPECTED_INPUT_FIELDS = frozenset(
    {
        "mesh_name",
        "mesh_sha256",
        "ffxinav_sha256",
        "probe_protocol",
        "probe_schema",
        "policy_revision",
        "policy_sha256",
        "transition_registry_sha256",
        "destinations_sha256",
        "graph_sha256",
        "destination_row_sha256",
        "ingress_row_sha256",
        "zone_mesh_name",
    }
)
CONTRACT_HASH_FIELDS = frozenset(
    {
        "mesh_sha256",
        "ffxinav_sha256",
        "policy_sha256",
        "transition_registry_sha256",
        "destinations_sha256",
        "graph_sha256",
        "destination_row_sha256",
        "ingress_row_sha256",
    }
)
MANIFEST_FIXED_KINDS = {
    "data/ffxi-nav-destinations.tsv": "destinations",
    "data/ffxi-nav-zoneline-graph.tsv": "graph",
    "modules/mission_quest_route_contracts.lua": "contracts",
    "modules/mission_quest_route_policy.lua": "policy",
    "modules/mission_quest_route_transitions.lua": "transitions",
    "third_party/FFXI-NavMesh-Builder/FFXINAV.dll": "ffxinav",
}
MANIFEST_RUNTIME_PATH = "modules/mission_quest_route_runtime.lua"
READER_MANIFEST_PIN = re.compile(
    r'^local ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256 = "([0-9a-f]{64})";$',
    re.MULTILINE,
)


class AuditInputError(ValueError):
    """Raised when an audit artifact cannot be parsed without ambiguity."""


@dataclass(frozen=True, order=True)
class AuditIssue:
    code: str
    context: str = ""
    native_key: str = ""
    stable_step_id: str = ""
    message: str = ""

    def to_dict(self) -> dict[str, str]:
        return {
            "code": self.code,
            "context": self.context,
            "native_key": self.native_key,
            "stable_step_id": self.stable_step_id,
            "message": self.message,
        }


@dataclass(frozen=True)
class AuditResult:
    contexts: tuple[dict[str, Any], ...]
    issues: tuple[AuditIssue, ...]

    @property
    def complete(self) -> bool:
        return not self.issues

    def to_dict(self) -> dict[str, Any]:
        return {
            "complete": self.complete,
            "contexts": list(self.contexts),
            "issues": [issue.to_dict() for issue in self.issues],
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2, sort_keys=True) + "\n"


def _mapping(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _rows(value: object) -> list[Mapping[str, Any]]:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        return []
    return [row for row in value if isinstance(row, Mapping)]


def _text(value: object) -> str:
    return value.strip() if isinstance(value, str) else ""


def _positive_integer(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _canonical_sha256(value: object) -> str:
    payload = (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        + "\n"
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _finite_triplet(value: object) -> bool:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)) or len(value) != 3:
        return False
    return all(
        isinstance(item, (int, float))
        and not isinstance(item, bool)
        and math.isfinite(float(item))
        for item in value
    )


def _sorted_unique_strings(value: object) -> bool:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes, bytearray)):
        return False
    rows = list(value)
    return (
        all(isinstance(item, str) and bool(item.strip()) for item in rows)
        and rows == sorted(set(rows))
    )


def _issue(
    issues: list[AuditIssue],
    code: str,
    *,
    context: str = "",
    native_key: str = "",
    stable_step_id: str = "",
    message: str = "",
) -> None:
    issues.append(AuditIssue(code, context, native_key, stable_step_id, message))


def _candidate_is_complete(
    candidate: Mapping[str, Any],
    *,
    native_key: str,
    action_id: str,
    parent_action: str,
    claim_action: str,
    parent_span_ids: set[str],
) -> bool:
    sites = candidate.get("source_sites")
    revisions = candidate.get("source_revisions")
    spans = candidate.get("source_action_span_ids")
    declared_sites = set(sites) if isinstance(sites, list) else set()
    span_sites: list[str] = []
    if isinstance(spans, list):
        for span_id in spans:
            matches = [site for site in SOURCE_SITES if f":{site}:" in str(span_id)]
            if len(matches) != 1:
                return False
            span_sites.append(matches[0])
    if (
        _text(candidate.get("native_key")) != native_key
        or _text(candidate.get("action_id")) != action_id
        or not parent_action
        or parent_action != claim_action
        or _text(candidate.get("action")) != parent_action
        or _text(candidate.get("classification")) != "catalogue-candidate"
        or candidate.get("route_ready") is not False
        or not _text(candidate.get("candidate_id"))
        or not _text(candidate.get("destination_id"))
        or not _positive_integer(candidate.get("zone"))
        or not _text(candidate.get("zone_name"))
        or not _text(candidate.get("target_name"))
        or not _text(candidate.get("target_kind"))
        or not _finite_triplet(candidate.get("target_point"))
        or not _text(candidate.get("raw_identity"))
        or not _text(candidate.get("evidence_level"))
        or not isinstance(sites, list)
        or not sites
        or len(sites) != len(set(sites))
        or not declared_sites.issubset(SOURCE_SITES)
        or not isinstance(revisions, Mapping)
        or set(revisions) != declared_sites
        or any(not _positive_integer(revisions.get(site)) for site in sites)
        or not isinstance(spans, list)
        or not spans
        or len(spans) != len(set(spans))
        or not set(spans).issubset(parent_span_ids)
        or set(span_sites) != declared_sites
    ):
        return False
    return True


def _contract_matches_candidate(
    contract: Mapping[str, Any],
    candidate: Mapping[str, Any],
    current_inputs: Mapping[str, Any],
) -> bool:
    prefix = contract.get("authorized_directed_prefix")
    destination = contract.get("destination")
    expected_inputs = contract.get("expected_inputs")
    local_leg = contract.get("local_leg")
    target_point = candidate.get("target_point")
    if (
        not isinstance(destination, Mapping)
        or set(destination) != CONTRACT_DESTINATION_FIELDS
        or not isinstance(expected_inputs, Mapping)
        or set(expected_inputs) != CONTRACT_EXPECTED_INPUT_FIELDS
        or any(HEX64.fullmatch(_text(expected_inputs.get(field))) is None for field in CONTRACT_HASH_FIELDS)
        or not _text(expected_inputs.get("mesh_name"))
        or expected_inputs.get("mesh_name") != expected_inputs.get("zone_mesh_name")
        or not _text(expected_inputs.get("probe_protocol"))
        or not _positive_integer(expected_inputs.get("probe_schema"))
        or not _text(expected_inputs.get("policy_revision"))
        or not isinstance(local_leg, Mapping)
        or local_leg.get("schema") != 2
        or local_leg.get("status") != "mesh-proven"
        or local_leg.get("inputs") != expected_inputs
        or not isinstance(local_leg.get("leg"), Mapping)
        or not _finite_triplet(target_point)
    ):
        return False
    transition_evidence_ids = contract.get("transition_evidence_ids")
    required_transition_ids = contract.get("required_transition_ids")
    if not _sorted_unique_strings(transition_evidence_ids) or not _sorted_unique_strings(
        required_transition_ids
    ):
        return False
    contract_point = [destination.get(key) for key in ("x", "z", "y")]
    raw_spawn_ids = candidate.get("raw_spawn_ids")
    if (
        destination.get("name") != candidate.get("target_name")
        or destination.get("kind") != candidate.get("target_kind")
        or contract_point != list(target_point)
        or destination.get("destination_id") != candidate.get("destination_id")
        or destination.get("raw_identity") != candidate.get("raw_identity")
        or not isinstance(raw_spawn_ids, list)
        or destination.get("raw_spawn_ids") != raw_spawn_ids
        or destination.get("cluster_policy_version") != candidate.get("cluster_policy_version")
    ):
        return False
    leg = local_leg["leg"]
    zone = str(candidate.get("zone"))
    destination_rows = _mapping(current_inputs.get("destination_row_sha256_by_id"))
    ingress_rows = _mapping(current_inputs.get("ingress_row_sha256_by_id"))
    zone_mesh_names = _mapping(current_inputs.get("zone_mesh_name_by_zone"))
    selected_current_inputs = {
        field: current_inputs.get(field)
        for field in CONTRACT_EXPECTED_INPUT_FIELDS
        if field
        not in {"destination_row_sha256", "ingress_row_sha256", "zone_mesh_name"}
    }
    selected_current_inputs.update(
        {
            "destination_row_sha256": destination_rows.get(_text(candidate.get("destination_id"))),
            "ingress_row_sha256": ingress_rows.get(str(prefix[-1])) if prefix else None,
            "zone_mesh_name": zone_mesh_names.get(zone),
        }
    )
    physical_leg_key = _canonical_sha256(
        {
            "inputs": local_leg.get("inputs"),
            "leg": local_leg.get("leg"),
            "probe_request": local_leg.get("probe_request"),
            "observations": local_leg.get("observations"),
        }
    )
    identity = {
        "candidate_id": candidate.get("candidate_id"),
        "action_id": candidate.get("action_id"),
        "group_id": candidate.get("group_id", ""),
        "physical_leg_key": physical_leg_key,
        "transition_evidence_ids": list(transition_evidence_ids),
    }
    return (
        contract.get("schema") == 2
        and contract.get("route_ready") is True
        and CONTRACT_ID.fullmatch(_text(contract.get("contract_id"))) is not None
        and _text(contract.get("candidate_id")) == _text(candidate.get("candidate_id"))
        and _text(contract.get("action_id")) == _text(candidate.get("action_id"))
        and _text(contract.get("group_id")) == _text(candidate.get("group_id"))
        and _text(contract.get("destination_id")) == _text(candidate.get("destination_id"))
        and contract.get("zone") == candidate.get("zone")
        and expected_inputs == selected_current_inputs
        and local_leg.get("evidence_id") == "mesh:v2:" + physical_leg_key
        and local_leg.get("candidate_id") == candidate.get("candidate_id")
        and local_leg.get("action_id") == candidate.get("action_id")
        and local_leg.get("group_id") == candidate.get("group_id", "")
        and contract.get("contract_id") == "route:v2:" + _canonical_sha256(identity)
        and isinstance(prefix, Sequence)
        and not isinstance(prefix, (str, bytes, bytearray))
        and len(prefix) > 0
        and all(_positive_integer(edge_id) for edge_id in prefix)
        and leg.get("zone") == candidate.get("zone")
        and leg.get("destination_id") == candidate.get("destination_id")
        and leg.get("zoneline_id") == prefix[-1]
    )


def _context_order() -> tuple[tuple[str, str], ...]:
    return tuple(("mission", context) for context in MISSION_CONTEXTS) + tuple(
        ("quest", context) for context in QUEST_CONTEXTS
    )


def _validate_stale_overrides(
    *,
    reviewed_overrides: Mapping[str, Any],
    native_keys: set[str],
    steps_by_id: Mapping[str, Mapping[str, Any]],
    action_ids: set[str],
    issues: list[AuditIssue],
) -> None:
    native_sections = (
        "page_matches",
        "runtime_objective_keys",
        "automatic_stage_links",
        "legacy_action_migrations",
        "mission_destination_overrides",
    )
    action_sections = (
        "single_source_zone_overrides",
        "role_overrides",
        "dynamic_target_overrides",
        "battlefield_target_overrides",
        "transport_target_overrides",
        "context_overrides",
    )
    for section in native_sections:
        for key in _mapping(reviewed_overrides.get(section)).keys():
            if str(key) not in native_keys:
                _issue(
                    issues,
                    "stale-override",
                    native_key=str(key),
                    message=f"{section} references no current native objective.",
                )
    for section in action_sections:
        for key in _mapping(reviewed_overrides.get(section)).keys():
            if str(key) not in action_ids:
                _issue(
                    issues,
                    "stale-override",
                    native_key=str(key),
                    message=f"{section} references no current reconciled action.",
                )
    for key, raw in _mapping(reviewed_overrides.get("target_overrides")).items():
        stable_step_id = str(key)
        step = steps_by_id.get(stable_step_id)
        source_revisions = raw.get("source_revisions") if isinstance(raw, Mapping) else None
        if (
            step is None
            or not isinstance(source_revisions, Mapping)
            or dict(source_revisions) != dict(_mapping(step.get("source_revisions")))
            or any(not _positive_integer(value) for value in source_revisions.values())
        ):
            _issue(
                issues,
                "stale-override",
                native_key=stable_step_id,
                message="target_overrides does not match one current revision-pinned step.",
            )
    groups = reviewed_overrides.get("shared_page_groups", [])
    if isinstance(groups, list):
        for group in groups:
            if not isinstance(group, Mapping):
                continue
            for key in group.get("native_keys", []):
                if str(key) not in native_keys:
                    _issue(
                        issues,
                        "stale-override",
                        native_key=str(key),
                        message="shared_page_groups references no current native objective.",
                    )


def _reference_fields(value: object) -> dict[str, Any]:
    row = _mapping(value)
    return {
        "zone": row.get("zone"),
        "zone_name": _text(row.get("zone_name")),
        "name": _text(row.get("name")),
        "kind": _text(row.get("kind")).casefold(),
    }


def _validate_target_override_accounting(
    *,
    target_review: Mapping[str, Any],
    reviewed_overrides: Mapping[str, Any],
    steps_by_id: Mapping[str, Mapping[str, Any]],
    issues: list[AuditIssue],
) -> None:
    failures = _rows(target_review.get("reviewed_target_failures"))
    failure_counts = Counter(_text(row.get("override_step_id")) for row in failures)
    failure_by_step: dict[str, Mapping[str, Any]] = {}
    for stable_step_id, count in sorted(failure_counts.items()):
        if not stable_step_id or count != 1:
            _issue(
                issues,
                "duplicate-reviewed-target-failure",
                stable_step_id=stable_step_id,
                message=f"Reviewed target failure occurs {count} times.",
            )
    for row in failures:
        stable_step_id = _text(row.get("override_step_id"))
        if not stable_step_id or failure_counts[stable_step_id] != 1:
            continue
        failure_by_step[stable_step_id] = row
        candidate_step_ids = row.get("candidate_step_ids")
        revisions = row.get("source_revisions")
        valid = (
            stable_step_id in steps_by_id
            and _text(row.get("native_key")) == _text(steps_by_id[stable_step_id].get("native_key"))
            and row.get("classification") == "unresolved"
            and row.get("route_ready") is False
            and MACHINE_REASON.fullmatch(_text(row.get("reason"))) is not None
            and isinstance(candidate_step_ids, list)
            and len(candidate_step_ids) == len(set(candidate_step_ids))
            and all(str(value) in steps_by_id for value in candidate_step_ids)
            and isinstance(revisions, Mapping)
            and bool(revisions)
            and all(_positive_integer(value) for value in revisions.values())
            and _positive_integer(_reference_fields(row.get("reference"))["zone"])
            and all(
                _reference_fields(row.get("reference"))[field]
                for field in ("zone_name", "name", "kind")
            )
        )
        if not valid:
            _issue(
                issues,
                "invalid-reviewed-target-failure",
                native_key=_text(row.get("native_key")),
                stable_step_id=stable_step_id,
                message="Reviewed target failure is stale, malformed, or authorizing.",
            )
        _issue(
            issues,
            "reviewed-target-failure",
            native_key=_text(row.get("native_key")),
            stable_step_id=stable_step_id,
            message=f"Reviewed target remains unresolved: {_text(row.get('reason'))}.",
        )

    for stable_step_id, raw in sorted(
        _mapping(reviewed_overrides.get("target_overrides")).items(), key=lambda item: str(item[0])
    ):
        stable_step_id = str(stable_step_id)
        override = _mapping(raw)
        step = steps_by_id.get(stable_step_id, {})
        resolved_reference = step.get("navigation_target")
        resolved = (
            isinstance(resolved_reference, Mapping)
            and step.get("route_ready") is True
            and _text(step.get("review_status")) == "verified-reviewed-target"
            and _reference_fields(resolved_reference) == _reference_fields(override.get("reference"))
        )
        failure = failure_by_step.get(stable_step_id)
        failed = failure is not None
        if failed and (
            dict(_mapping(failure.get("source_revisions")))
            != dict(_mapping(override.get("source_revisions")))
            or _reference_fields(failure.get("reference"))
            != _reference_fields(override.get("reference"))
        ):
            _issue(
                issues,
                "invalid-reviewed-target-failure",
                stable_step_id=stable_step_id,
                message="Reviewed target failure does not bind the exact override evidence.",
            )
        if resolved and failed:
            _issue(
                issues,
                "target-override-overlap",
                stable_step_id=stable_step_id,
                message="Reviewed target override is both resolved and failed.",
            )
        elif not resolved and not failed:
            _issue(
                issues,
                "target-override-unaccounted",
                stable_step_id=stable_step_id,
                message="Reviewed target override has no exact resolved or failed output.",
            )


def _validate_resolution_review_items(
    *,
    target_review: Mapping[str, Any],
    ledger_by_id: Mapping[str, Mapping[str, Any]],
    issues: list[AuditIssue],
) -> None:
    rows = _rows(target_review.get("objective_resolution_review_items"))
    counts = Counter(_text(row.get("review_id")) for row in rows)
    for review_id, count in sorted(counts.items()):
        if not review_id or count != 1:
            _issue(
                issues,
                "duplicate-resolution-review",
                native_key=review_id,
                message=f"Objective resolution review ID occurs {count} times.",
            )
    for row in rows:
        review_id = _text(row.get("review_id"))
        if not review_id or counts[review_id] != 1:
            continue
        action_id = _text(row.get("action_id"))
        parent = ledger_by_id.get(action_id)
        sites = row.get("source_sites")
        spans = row.get("source_action_span_ids")
        if (
            REVIEW_ID.fullmatch(review_id) is None
            or parent is None
            or _text(row.get("native_key")) != _text(parent.get("native_key"))
            or row.get("route_ready") is not False
            or MACHINE_REASON.fullmatch(_text(row.get("reason"))) is None
            or not _text(row.get("target_name"))
            or not _text(row.get("zone_name"))
            or not isinstance(sites, list)
            or not sites
            or len(sites) != len(set(sites))
            or not isinstance(spans, list)
            or not spans
            or len(spans) != len(set(spans))
            or not set(spans).issubset(set(parent.get("source_action_span_ids", [])))
        ):
            _issue(
                issues,
                "invalid-resolution-review",
                native_key=_text(row.get("native_key")),
                message=f"Resolution review {review_id} is stale or malformed.",
            )
        _issue(
            issues,
            "resolution-review-pending",
            native_key=_text(row.get("native_key")),
            message=f"Objective resolution review {review_id} remains pending.",
        )


def _validate_legacy_outcome_accounting(
    *,
    target_review: Mapping[str, Any],
    reviewed_overrides: Mapping[str, Any],
    ledger_by_id: Mapping[str, Mapping[str, Any]],
    candidate_by_id: Mapping[str, Mapping[str, Any]],
    issues: list[AuditIssue],
) -> None:
    expected: dict[str, tuple[str, Mapping[str, Any]]] = {}
    legacy_overrides = reviewed_overrides.get("mission_destination_overrides", {})
    if not isinstance(legacy_overrides, Mapping):
        _issue(issues, "invalid-legacy-overrides", message="Legacy destination overrides are not an object.")
        return
    for native_key, raw_rows in sorted(legacy_overrides.items(), key=lambda item: str(item[0])):
        if not isinstance(raw_rows, list):
            _issue(
                issues,
                "invalid-legacy-overrides",
                native_key=str(native_key),
                message="Legacy destination overrides are not an array.",
            )
            continue
        for raw in raw_rows:
            short_id = _text(raw.get("id")).casefold() if isinstance(raw, Mapping) else ""
            stable_id = f"{native_key}:destination:{short_id}"
            if MACHINE_REASON.fullmatch(short_id) is None or stable_id in expected:
                _issue(
                    issues,
                    "duplicate-legacy-override",
                    native_key=str(native_key),
                    message=f"Legacy override ID {stable_id!r} is malformed or repeated.",
                )
                continue
            expected[stable_id] = (str(native_key), raw)

    outcomes = _rows(target_review.get("legacy_destination_outcomes"))
    counts = Counter(_text(row.get("legacy_override_id")) for row in outcomes)
    outcome_by_id: dict[str, Mapping[str, Any]] = {}
    for legacy_id, count in sorted(counts.items()):
        if not legacy_id or count != 1:
            _issue(
                issues,
                "duplicate-legacy-outcome",
                native_key=legacy_id,
                message=f"Legacy destination outcome occurs {count} times.",
            )
    for row in outcomes:
        legacy_id = _text(row.get("legacy_override_id"))
        if legacy_id and counts[legacy_id] == 1:
            outcome_by_id[legacy_id] = row
    for legacy_id in sorted(set(outcome_by_id).difference(expected)):
        _issue(
            issues,
            "legacy-outcome-extra",
            native_key=_text(outcome_by_id[legacy_id].get("native_key")),
            message=f"Legacy outcome {legacy_id} has no current reviewed override.",
        )
    for legacy_id, (native_key, raw) in sorted(expected.items()):
        row = outcome_by_id.get(legacy_id)
        if row is None:
            _issue(
                issues,
                "legacy-override-unaccounted",
                native_key=native_key,
                message=f"Legacy override {legacy_id} has no exact outcome.",
            )
            continue
        candidate_ids = row.get("candidate_ids")
        group_ids = row.get("group_ids")
        spans = row.get("source_action_span_ids")
        revisions = row.get("source_revisions")
        action_id = _text(row.get("action_id"))
        parent = ledger_by_id.get(action_id)
        base_valid = (
            _text(row.get("native_key")) == native_key
            and row.get("route_ready") is False
            and isinstance(candidate_ids, list)
            and row.get("candidate_count") == len(candidate_ids)
            and len(candidate_ids) == len(set(candidate_ids))
            and isinstance(group_ids, list)
            and len(group_ids) == len(set(group_ids))
            and isinstance(spans, list)
            and len(spans) == len(set(spans))
            and isinstance(revisions, Mapping)
            and dict(revisions) == dict(_mapping(raw.get("source_revisions")))
        )
        classification = _text(row.get("classification"))
        if classification == "catalogue-candidate":
            valid = (
                base_valid
                and _text(row.get("reason")) == "migrated-to-action-candidates"
                and parent is not None
                and _text(parent.get("native_key")) == native_key
                and bool(candidate_ids)
                and all(
                    candidate_id in candidate_by_id
                    and _text(candidate_by_id[candidate_id].get("action_id")) == action_id
                    for candidate_id in candidate_ids
                )
                and bool(spans)
                and set(spans).issubset(set(parent.get("source_action_span_ids", [])))
            )
            if not valid:
                _issue(
                    issues,
                    "invalid-legacy-outcome",
                    native_key=native_key,
                    message=f"Resolved legacy outcome {legacy_id} is stale or malformed.",
                )
        elif classification == "unresolved":
            if not (
                base_valid
                and not action_id
                and not candidate_ids
                and not group_ids
                and not spans
                and MACHINE_REASON.fullmatch(_text(row.get("reason"))) is not None
            ):
                _issue(
                    issues,
                    "invalid-legacy-outcome",
                    native_key=native_key,
                    message=f"Unresolved legacy outcome {legacy_id} is malformed.",
                )
            _issue(
                issues,
                "legacy-override-unresolved",
                native_key=native_key,
                message=f"Legacy override {legacy_id} still requires migration.",
            )
        else:
            _issue(
                issues,
                "invalid-legacy-outcome",
                native_key=native_key,
                message=f"Legacy outcome {legacy_id} has unsupported classification.",
            )


def audit_artifacts(
    *,
    native_manifest: Mapping[str, Any],
    coverage: Mapping[str, Any],
    target_review: Mapping[str, Any],
    reviewed_overrides: Mapping[str, Any],
    reconciled_step_ids: Sequence[str],
    route_contracts: Sequence[Mapping[str, Any]],
    current_route_inputs_by_zone: Mapping[str | int, Mapping[str, Any]] | None = None,
) -> AuditResult:
    issues: list[AuditIssue] = []
    native_rows = _rows(native_manifest.get("objectives"))
    native_key_counts = Counter(_text(row.get("key")) for row in native_rows)
    for key, count in sorted(native_key_counts.items()):
        if not key or count != 1:
            _issue(
                issues,
                "duplicate-native-key",
                native_key=key,
                message=f"Native objective key occurs {count} times.",
            )
    native_by_key = {
        _text(row.get("key")): row for row in native_rows if _text(row.get("key")) and native_key_counts[_text(row.get("key"))] == 1
    }
    native_keys = set(native_by_key)

    expected_contexts = set(_context_order())
    actual_contexts = {
        (_text(row.get("kind")), _text(row.get("context"))) for row in native_by_key.values()
    }
    for kind, context in _context_order():
        if (kind, context) not in actual_contexts:
            _issue(
                issues,
                "missing-context",
                context=context,
                message=f"Required {kind} context is absent.",
            )
    for kind, context in sorted(actual_contexts.difference(expected_contexts)):
        _issue(
            issues,
            "unexpected-context",
            context=context,
            message=f"Unexpected {kind} context is present.",
        )

    classifications = _mapping(reviewed_overrides.get("native_classifications"))
    classification_by_key: dict[str, str] = {}
    for key in sorted(native_keys):
        native = native_by_key[key]
        raw = classifications.get(key)
        if not isinstance(raw, Mapping):
            classification_by_key[key] = "unclassified"
            _issue(
                issues,
                "unclassified-native",
                context=_text(native.get("context")),
                native_key=key,
                message="Native objective has no explicit playable or sentinel classification.",
            )
            continue
        classification = _text(raw.get("classification"))
        if classification == "playable":
            classification_by_key[key] = classification
        elif (
            classification == "sentinel"
            and raw.get("record_offset") == native.get("record_offset")
            and MACHINE_REASON.fullmatch(_text(raw.get("reason"))) is not None
        ):
            classification_by_key[key] = classification
        else:
            classification_by_key[key] = "unclassified"
            _issue(
                issues,
                "invalid-native-classification",
                context=_text(native.get("context")),
                native_key=key,
                message="Sentinel identity/reason or playable classification is malformed.",
            )
    for key in sorted(set(str(value) for value in classifications).difference(native_keys)):
        _issue(
            issues,
            "stale-native-classification",
            native_key=key,
            message="Native classification references no current DAT row.",
        )

    coverage_rows = _mapping(coverage.get("objectives"))
    for key in sorted(set(str(value) for value in coverage_rows).difference(native_keys)):
        _issue(
            issues,
            "coverage-native-unknown",
            native_key=key,
            message="Coverage references no current native objective.",
        )
    source_covered: dict[str, bool] = {}
    valid_source_sites: dict[str, set[str]] = {}
    for key, native in sorted(native_by_key.items()):
        row = coverage_rows.get(key)
        if classification_by_key.get(key) == "playable" and not isinstance(row, Mapping):
            _issue(
                issues,
                "native-coverage-missing",
                context=_text(native.get("context")),
                native_key=key,
                message="Playable native objective has no coverage row.",
            )
            source_covered[key] = False
            valid_source_sites[key] = set()
            continue
        if not isinstance(row, Mapping):
            source_covered[key] = False
            valid_source_sites[key] = set()
            continue
        if _text(row.get("kind")) != _text(native.get("kind")) or _text(row.get("context")) != _text(
            native.get("context")
        ):
            _issue(
                issues,
                "coverage-owner-mismatch",
                context=_text(native.get("context")),
                native_key=key,
                message="Coverage kind/context disagrees with the native row.",
            )
        source_pages = row.get("source_pages")
        valid_sites: set[str] = set()
        if isinstance(source_pages, Mapping):
            for site, raw_page in sorted(source_pages.items(), key=lambda item: str(item[0])):
                page = _mapping(raw_page)
                if (
                    str(site) in SOURCE_SITES
                    and _positive_integer(page.get("page_id"))
                    and _positive_integer(page.get("revision_id"))
                    and bool(_text(page.get("title")))
                    and bool(_text(page.get("source_url")))
                ):
                    valid_sites.add(str(site))
                else:
                    _issue(
                        issues,
                        "invalid-source-page",
                        context=_text(native.get("context")),
                        native_key=key,
                        message=f"Source page {site!r} is not a recognized revision-pinned page.",
                    )
        elif source_pages is not None:
            _issue(
                issues,
                "invalid-source-page",
                context=_text(native.get("context")),
                native_key=key,
                message="Source pages are not an object.",
            )
        valid_source_sites[key] = valid_sites
        source_covered[key] = bool(valid_sites)
        if classification_by_key.get(key) == "playable" and not source_covered[key]:
            _issue(
                issues,
                "source-coverage-missing",
                context=_text(native.get("context")),
                native_key=key,
                message="Playable objective has no pinned source page.",
            )

    authoritative_counts = Counter(str(value) for value in reconciled_step_ids)
    for stable_step_id, count in sorted(authoritative_counts.items()):
        if not stable_step_id or count != 1:
            _issue(
                issues,
                "duplicate-reconciled-step-id",
                stable_step_id=stable_step_id,
                message=f"Generated reconciliation step occurs {count} times.",
            )
    authoritative_steps = {key for key, count in authoritative_counts.items() if key and count == 1}
    step_rows = _rows(target_review.get("steps"))
    audited_counts = Counter(_text(row.get("stable_step_id")) for row in step_rows)
    for stable_step_id, count in sorted(audited_counts.items()):
        if not stable_step_id or count != 1:
            _issue(
                issues,
                "duplicate-audited-step",
                stable_step_id=stable_step_id,
                message=f"Audit review step occurs {count} times.",
            )
    audited_steps = {key for key, count in audited_counts.items() if key and count == 1}
    for stable_step_id in sorted(authoritative_steps.difference(audited_steps)):
        _issue(
            issues,
            "omitted-reconciled-step",
            stable_step_id=stable_step_id,
            message="Generated reconciliation step is absent from target-review.",
        )
    for stable_step_id in sorted(audited_steps.difference(authoritative_steps)):
        _issue(
            issues,
            "audit-step-not-generated",
            stable_step_id=stable_step_id,
            message="Target-review step has no generated reconciliation row.",
        )
    step_by_id = {
        _text(row.get("stable_step_id")): row
        for row in step_rows
        if _text(row.get("stable_step_id")) in authoritative_steps
        and audited_counts[_text(row.get("stable_step_id"))] == 1
    }
    for stable_step_id, step in sorted(step_by_id.items()):
        native_key = _text(step.get("native_key"))
        if native_key not in native_keys or not stable_step_id.startswith(native_key + ":step-"):
            _issue(
                issues,
                "step-owner-mismatch",
                native_key=native_key,
                stable_step_id=stable_step_id,
                message="Audited step does not belong to its current native objective.",
            )

    claim_owner: dict[str, str] = {}
    duplicated_claims: set[str] = set()
    for stable_step_id, step in sorted(step_by_id.items()):
        for claim in _rows(step.get("typed_claims")):
            claim_id = _text(claim.get("stable_claim_id"))
            if not claim_id:
                continue
            if claim_id in claim_owner:
                duplicated_claims.add(claim_id)
            else:
                claim_owner[claim_id] = stable_step_id
    for claim_id in sorted(duplicated_claims):
        _issue(
            issues,
            "duplicate-typed-claim",
            native_key=claim_id,
            message="Typed claim is owned by more than one reconciled step.",
        )

    ledger_rows = _rows(target_review.get("action_resolution_ledger"))
    action_counts = Counter(_text(row.get("action_id")) for row in ledger_rows)
    ledger_by_id: dict[str, Mapping[str, Any]] = {}
    action_step: dict[str, str] = {}
    actions_by_step: dict[str, list[str]] = defaultdict(list)
    for action_id, count in sorted(action_counts.items()):
        if not action_id or count != 1:
            _issue(
                issues,
                "duplicate-action-ledger-row",
                native_key=action_id,
                message=f"Action ledger ID occurs {count} times.",
            )
    for row in ledger_rows:
        action_id = _text(row.get("action_id"))
        if not action_id or action_counts[action_id] != 1:
            continue
        ledger_by_id[action_id] = row
        owner = claim_owner.get(action_id)
        if owner is None:
            context_owners = [
                step_id for step_id in authoritative_steps if action_id.startswith(step_id + ":context-")
            ]
            if len(context_owners) == 1:
                owner = context_owners[0]
        if owner is None:
            _issue(
                issues,
                "orphan-action-ledger-row",
                native_key=_text(row.get("native_key")),
                message=f"Action {action_id} has no exact reconciled step owner.",
            )
            continue
        action_step[action_id] = owner
        actions_by_step[owner].append(action_id)
        if _text(row.get("native_key")) != _text(step_by_id.get(owner, {}).get("native_key")):
            _issue(
                issues,
                "action-owner-mismatch",
                native_key=_text(row.get("native_key")),
                stable_step_id=owner,
                message="Action ledger native owner disagrees with its reconciled step.",
            )
    for stable_step_id in sorted(authoritative_steps):
        if stable_step_id in step_by_id and not actions_by_step.get(stable_step_id):
            _issue(
                issues,
                "step-action-accounting-missing",
                native_key=_text(step_by_id[stable_step_id].get("native_key")),
                stable_step_id=stable_step_id,
                message="Reconciled step has no exact action-ledger classification.",
            )

    candidate_rows = _rows(target_review.get("objective_destination_candidates"))
    candidate_counts = Counter(_text(row.get("candidate_id")) for row in candidate_rows)
    candidate_by_id: dict[str, Mapping[str, Any]] = {}
    for candidate_id, count in sorted(candidate_counts.items()):
        if not candidate_id or count != 1:
            _issue(
                issues,
                "duplicate-candidate",
                native_key=candidate_id,
                message=f"Candidate ID occurs {count} times.",
            )
    for row in candidate_rows:
        candidate_id = _text(row.get("candidate_id"))
        if candidate_id and candidate_counts[candidate_id] == 1:
            candidate_by_id[candidate_id] = row

    contract_rows = _rows(route_contracts)
    current_route_inputs_by_zone = current_route_inputs_by_zone or {}
    contract_counts = Counter(_text(row.get("contract_id")) for row in contract_rows)
    exact_contracts_by_candidate: dict[str, list[Mapping[str, Any]]] = defaultdict(list)
    for contract_id, count in sorted(contract_counts.items()):
        if not contract_id or count != 1:
            _issue(
                issues,
                "duplicate-route-contract",
                native_key=contract_id,
                message=f"Route contract ID occurs {count} times.",
            )
    for contract in contract_rows:
        contract_id = _text(contract.get("contract_id"))
        if not contract_id or contract_counts[contract_id] != 1:
            continue
        candidate_id = _text(contract.get("candidate_id"))
        candidate = candidate_by_id.get(candidate_id)
        zone_matches = [
            value
            for key, value in current_route_inputs_by_zone.items()
            if str(key) == str(contract.get("zone")) and isinstance(value, Mapping)
        ]
        if (
            candidate is None
            or len(zone_matches) != 1
            or not _contract_matches_candidate(contract, candidate, zone_matches[0])
        ):
            _issue(
                issues,
                "stale-route-contract",
                native_key=candidate_id,
                message=f"Contract {contract_id} does not bind one exact current candidate.",
            )
            continue
        exact_contracts_by_candidate[candidate_id].append(contract)

    action_category: dict[str, str] = {}
    valid_actionable: dict[str, bool] = {}
    target_evidence_by_native: Counter[str] = Counter()
    same_zone_by_native: Counter[str] = Counter()
    cross_zone_by_native: Counter[str] = Counter()
    referenced_candidates: set[str] = set()
    for action_id, row in sorted(ledger_by_id.items()):
        stable_step_id = action_step.get(action_id, "")
        step = step_by_id.get(stable_step_id, {})
        native_key = _text(row.get("native_key"))
        status = _text(row.get("status"))
        material = row.get("material")
        candidate_ids = row.get("candidate_ids")
        candidate_ids = candidate_ids if isinstance(candidate_ids, list) else []
        valid_actionable[action_id] = False
        if status not in ACTION_STATUSES:
            action_category[action_id] = "unresolved"
            _issue(
                issues,
                "invalid-action-status",
                native_key=native_key,
                stable_step_id=stable_step_id,
                message=f"Action {action_id} has unsupported status {status!r}.",
            )
            continue
        if row.get("route_ready") is not False or not isinstance(material, bool):
            _issue(
                issues,
                "invalid-action-ledger-state",
                native_key=native_key,
                stable_step_id=stable_step_id,
                message="Task 3 action row has an invalid route/material state.",
            )
        if status == "instruction-only":
            action_category[action_id] = status
            matching_claims = [
                claim
                for claim in _rows(step.get("typed_claims"))
                if _text(claim.get("stable_claim_id")) == action_id
            ]
            span_ids = row.get("source_action_span_ids")
            if (
                material is True
                and _text(row.get("reason")) == "complete-instruction"
                and _text(row.get("action")) in INSTRUCTION_ONLY_ACTIONS
                and not candidate_ids
                and row.get("candidate_count") == 0
                and _text(row.get("instruction"))
                and isinstance(span_ids, list)
                and bool(span_ids)
                and len(span_ids) == len(set(span_ids))
                and len(matching_claims) == 1
                and _text(matching_claims[0].get("action")) == _text(row.get("action"))
            ):
                valid_actionable[action_id] = True
            else:
                _issue(
                    issues,
                    "invalid-instruction-only",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Instruction-only action is incomplete or owns movement children.",
                )
        elif status == "context-only":
            action_category[action_id] = status
            override = _mapping(reviewed_overrides.get("context_overrides")).get(action_id)
            context_reason = _text(override.get("reason")) if isinstance(override, Mapping) else ""
            step_action = _text(step.get("action")).casefold()
            typed_claims = _rows(step.get("typed_claims"))
            if step_action in ACTION_LIKE_CONTEXT_ACTIONS or typed_claims:
                _issue(
                    issues,
                    "action-misclassified-context",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Action-like source evidence was classified as non-material context.",
                )
            if (
                material is not False
                or _text(row.get("action")) != "context"
                or _text(row.get("reason")) != "non-material-context-reason"
                or candidate_ids
                or row.get("candidate_count") != 0
                or context_reason not in CONTEXT_REASONS
            ):
                _issue(
                    issues,
                    "invalid-context-reason",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Context-only action lacks an allowed reviewed non-material reason.",
                )
        elif status == "conflict":
            action_category[action_id] = status
            if (
                candidate_ids
                or row.get("candidate_count") != 0
                or _text(row.get("instruction"))
                or _text(row.get("reason")) != "source-conflict"
                or (material is False and _text(row.get("action")) != "context")
            ):
                _issue(
                    issues,
                    "invalid-nonmaterial-conflict" if material is False else "invalid-conflict-state",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Conflict classification carries hidden movement or instruction state.",
                )
            if material is True:
                _issue(
                    issues,
                    "material-conflict",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Material source conflict blocks a complete release claim.",
                )
        elif status == "unresolved":
            action_category[action_id] = status
            if candidate_ids or row.get("candidate_count") != 0 or _text(row.get("instruction")):
                _issue(
                    issues,
                    "invalid-unresolved-state",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Unresolved action carries hidden movement or instruction state.",
                )
            if material is True:
                _issue(
                    issues,
                    "unresolved-material-step",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Material action remains unresolved.",
                )
        else:
            candidate_complete = True
            all_current = bool(candidate_ids)
            if row.get("candidate_count") != len(candidate_ids):
                candidate_complete = False
                _issue(
                    issues,
                    "invalid-candidate-count",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Catalogue action candidate_count disagrees with its exact child IDs.",
                )
            parent_spans = set(row.get("source_action_span_ids", []))
            matching_claims = [
                claim
                for claim in _rows(step.get("typed_claims"))
                if _text(claim.get("stable_claim_id")) == action_id
            ]
            claim_action = (
                _text(matching_claims[0].get("action")) if len(matching_claims) == 1 else ""
            )
            for candidate_id in candidate_ids:
                candidate_id = str(candidate_id)
                referenced_candidates.add(candidate_id)
                candidate = candidate_by_id.get(candidate_id)
                if candidate is None or not _candidate_is_complete(
                    candidate,
                    native_key=native_key,
                    action_id=action_id,
                    parent_action=_text(row.get("action")),
                    claim_action=claim_action,
                    parent_span_ids=parent_spans,
                ):
                    candidate_complete = False
                    all_current = False
                    _issue(
                        issues,
                        "candidate-evidence-incomplete",
                        native_key=native_key,
                        stable_step_id=stable_step_id,
                        message=f"Candidate {candidate_id} lacks exact typed evidence.",
                    )
                    continue
                target_evidence_by_native[native_key] += 1
                contracts = exact_contracts_by_candidate.get(candidate_id, [])
                if len(contracts) != 1:
                    all_current = False
                    _issue(
                        issues,
                        "candidate-contract-missing",
                        native_key=native_key,
                        stable_step_id=stable_step_id,
                        message=f"Candidate {candidate_id} lacks one exact current runtime contract.",
                    )
                else:
                    same_zone_by_native[native_key] += 1
                    if contracts[0].get("authorized_directed_prefix"):
                        cross_zone_by_native[native_key] += 1
            if material is not True or not candidate_ids or not candidate_complete:
                _issue(
                    issues,
                    "invalid-catalogue-action",
                    native_key=native_key,
                    stable_step_id=stable_step_id,
                    message="Catalogue action does not own complete exact candidates.",
                )
            valid_actionable[action_id] = bool(candidate_ids) and candidate_complete
            action_category[action_id] = "routable" if all_current and candidate_complete else "unresolved"

    for candidate_id in sorted(set(candidate_by_id).difference(referenced_candidates)):
        _issue(
            issues,
            "orphan-candidate",
            native_key=_text(candidate_by_id[candidate_id].get("native_key")),
            message=f"Candidate {candidate_id} is absent from its parent action ledger.",
        )

    for stable_step_id, step in sorted(step_by_id.items()):
        if _text(step.get("comparison")) == "conflict" and not any(
            _text(ledger_by_id.get(action_id, {}).get("status")) == "conflict"
            for action_id in actions_by_step.get(stable_step_id, [])
        ):
            _issue(
                issues,
                "silent-conflict",
                native_key=_text(step.get("native_key")),
                stable_step_id=stable_step_id,
                message="Reconciled conflict is hidden by a non-conflict action classification.",
            )

    automatic_supported_by_native: Counter[str] = Counter()
    for native_key, coverage_row in sorted(coverage_rows.items()):
        if not isinstance(coverage_row, Mapping):
            continue
        automatic_stages = coverage_row.get("automatic_stages")
        if not isinstance(automatic_stages, Mapping):
            continue
        for stage_name, stable_step_id_value in sorted(automatic_stages.items()):
            stable_step_id = _text(stable_step_id_value)
            step = step_by_id.get(stable_step_id)
            if step is None or _text(step.get("native_key")) != str(native_key):
                _issue(
                    issues,
                    "automatic-step-stale",
                    native_key=str(native_key),
                    stable_step_id=stable_step_id,
                    message=f"Automatic stage {stage_name!r} references no current owned step.",
                )
                continue
            action_ids = actions_by_step.get(stable_step_id, [])
            current = bool(action_ids) and all(
                action_category.get(action_id) == "routable" for action_id in action_ids
            )
            if not current:
                _issue(
                    issues,
                    "automatic-contract-missing",
                    native_key=str(native_key),
                    stable_step_id=stable_step_id,
                    message=f"Automatic stage {stage_name!r} has no exact current runtime contract.",
                )
            else:
                automatic_supported_by_native[str(native_key)] += 1

    _validate_stale_overrides(
        reviewed_overrides=reviewed_overrides,
        native_keys=native_keys,
        steps_by_id=step_by_id,
        action_ids=set(ledger_by_id),
        issues=issues,
    )
    _validate_target_override_accounting(
        target_review=target_review,
        reviewed_overrides=reviewed_overrides,
        steps_by_id=step_by_id,
        issues=issues,
    )
    _validate_resolution_review_items(
        target_review=target_review,
        ledger_by_id=ledger_by_id,
        issues=issues,
    )
    _validate_legacy_outcome_accounting(
        target_review=target_review,
        reviewed_overrides=reviewed_overrides,
        ledger_by_id=ledger_by_id,
        candidate_by_id=candidate_by_id,
        issues=issues,
    )

    for native_key, classification in sorted(classification_by_key.items()):
        if classification != "playable":
            continue
        action_ids = [
            action_id for action_id, row in ledger_by_id.items() if _text(row.get("native_key")) == native_key
        ]
        if not any(valid_actionable.get(action_id, False) for action_id in action_ids):
            native = native_by_key[native_key]
            _issue(
                issues,
                "playable-no-actionable",
                context=_text(native.get("context")),
                native_key=native_key,
                message="Playable objective has no validated destination or complete instruction.",
            )

    context_rows: list[dict[str, Any]] = []
    for kind, context in _context_order():
        keys = sorted(
            key
            for key, row in native_by_key.items()
            if _text(row.get("kind")) == kind and _text(row.get("context")) == context
        )
        step_counts = {key: 0 for key in ("routable", "instruction-only", "context-only", "conflict", "unresolved")}
        no_actionable = 0
        for native_key in keys:
            native_actions = [
                action_id
                for action_id, row in ledger_by_id.items()
                if _text(row.get("native_key")) == native_key
            ]
            for action_id in native_actions:
                category = action_category.get(action_id, "unresolved")
                if category in step_counts:
                    step_counts[category] += 1
            if classification_by_key.get(native_key) == "playable" and not any(
                valid_actionable.get(action_id, False) for action_id in native_actions
            ):
                no_actionable += 1
        context_rows.append(
            {
                "kind": kind,
                "context": context,
                "native_classification": {
                    "playable": sum(classification_by_key.get(key) == "playable" for key in keys),
                    "sentinel": sum(classification_by_key.get(key) == "sentinel" for key in keys),
                    "unclassified": sum(classification_by_key.get(key) == "unclassified" for key in keys),
                },
                "source_coverage": {
                    "covered": sum(source_covered.get(key, False) for key in keys),
                    "dual_source": sum(
                        valid_source_sites.get(key, set()) == SOURCE_SITES for key in keys
                    ),
                    "missing": sum(
                        classification_by_key.get(key) == "playable" and not source_covered.get(key, False)
                        for key in keys
                    ),
                },
                "steps": step_counts,
                "target_evidence_complete": sum(target_evidence_by_native[key] for key in keys),
                "same_zone_routable": sum(same_zone_by_native[key] for key in keys),
                "cross_zone_routable": sum(cross_zone_by_native[key] for key in keys),
                "automatic_stage_supported": sum(automatic_supported_by_native[key] for key in keys),
                "no_actionable": no_actionable,
            }
        )

    return AuditResult(tuple(context_rows), tuple(sorted(set(issues))))


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise AuditInputError(f"JSON object repeats key {key!r}.")
        result[key] = value
    return result


def _read_json(path: Path) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError, AuditInputError) as error:
        raise AuditInputError(f"Cannot read {path}: {error}") from error
    if not isinstance(value, Mapping):
        raise AuditInputError(f"{path} must contain one JSON object.")
    return value


class _LuaLiteralParser:
    def __init__(self, text: str) -> None:
        self.text = text
        self.index = 0

    def parse(self) -> Any:
        value = self._value()
        self._space()
        if self.index != len(self.text):
            raise AuditInputError("Generated contract Lua contains trailing syntax.")
        return value

    def _space(self) -> None:
        while self.index < len(self.text) and self.text[self.index].isspace():
            self.index += 1

    def _take(self, expected: str) -> None:
        self._space()
        if not self.text.startswith(expected, self.index):
            raise AuditInputError(f"Generated contract Lua expected {expected!r}.")
        self.index += len(expected)

    def _value(self) -> Any:
        self._space()
        if self.index >= len(self.text):
            raise AuditInputError("Generated contract Lua ended inside a value.")
        if self.text[self.index] == '"':
            return self._string()
        if self.text[self.index] == "{":
            return self._table()
        for literal, value in (("true", True), ("false", False), ("nil", None)):
            if self.text.startswith(literal, self.index):
                self.index += len(literal)
                return value
        match = re.match(r"-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", self.text[self.index :])
        if match is None:
            raise AuditInputError("Generated contract Lua contains an unsupported value.")
        token = match.group(0)
        self.index += len(token)
        return float(token) if any(character in token for character in ".eE") else int(token)

    def _string(self) -> str:
        self._take('"')
        result: list[str] = []
        while self.index < len(self.text):
            character = self.text[self.index]
            self.index += 1
            if character == '"':
                return "".join(result)
            if character == "\\":
                if self.index >= len(self.text):
                    break
                escaped = self.text[self.index]
                self.index += 1
                replacements = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"'}
                if escaped not in replacements:
                    raise AuditInputError("Generated contract Lua uses an unsupported string escape.")
                result.append(replacements[escaped])
            else:
                result.append(character)
        raise AuditInputError("Generated contract Lua has an unterminated string.")

    def _table(self) -> Any:
        self._take("{")
        self._space()
        if self.index < len(self.text) and self.text[self.index] == "}":
            self.index += 1
            return []
        mapping = self.index < len(self.text) and self.text[self.index] == "["
        result_mapping: dict[str, Any] = {}
        result_array: list[Any] = []
        while True:
            self._space()
            if mapping:
                self._take("[")
                key = self._string()
                self._take("]")
                self._take("=")
                if key in result_mapping:
                    raise AuditInputError(f"Generated contract Lua repeats key {key!r}.")
                result_mapping[key] = self._value()
            else:
                result_array.append(self._value())
            self._space()
            if self.index < len(self.text) and self.text[self.index] == "}":
                self.index += 1
                return result_mapping if mapping else result_array
            self._take(",")


def _read_contracts(path: Path) -> list[Mapping[str, Any]]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise AuditInputError(f"Cannot read {path}: {error}") from error
    match = re.fullmatch(
        r"--[^\r\n]*\r?\nlocal contracts = ([\s\S]*?)\r?\nreturn contracts\r?\n?",
        text,
    )
    if match is None:
        raise AuditInputError("Generated route-contract module has an unexpected envelope.")
    value = _LuaLiteralParser(match.group(1)).parse()
    if not isinstance(value, list) or any(not isinstance(row, Mapping) for row in value):
        raise AuditInputError("Generated route-contract module must return an array of objects.")
    return value


def _read_reconciled_step_ids(module_root: Path) -> list[str]:
    paths = sorted(module_root.glob("mission_quest_reconcile_*.lua"), key=lambda path: path.name)
    if not paths:
        raise AuditInputError("No generated reconciliation modules are present.")
    values: list[str] = []
    for path in paths:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            raise AuditInputError(f"Cannot read {path}: {error}") from error
        values.extend(STABLE_STEP_ID.findall(text))
    return values


def _read_current_route_inputs(
    *,
    repo_root: Path,
    addon_root: Path,
    guide_data_root: Path,
    contracts: Sequence[Mapping[str, Any]],
) -> Mapping[str, Mapping[str, Any]]:
    if not contracts:
        return {}
    from tools.objective_guides import route_evidence

    manifest_path = addon_root / "data" / "mission-quest-route-manifest.tsv"
    try:
        manifest_payload = manifest_path.read_bytes()
        manifest_rows = route_evidence.parse_runtime_manifest(manifest_payload)
    except (OSError, route_evidence.RouteEvidenceError) as error:
        raise AuditInputError(f"Cannot verify the current route manifest: {error}") from error
    manifest_by_path = {row["relative_path"]: row for row in manifest_rows}
    missing_fixed = sorted(set(MANIFEST_FIXED_KINDS).difference(manifest_by_path))
    if missing_fixed:
        raise AuditInputError(f"Current route manifest omits required children: {missing_fixed}.")
    if MANIFEST_RUNTIME_PATH not in manifest_by_path:
        raise AuditInputError("Current contracts require the Task 5 route runtime manifest child.")
    mesh_rows: list[dict[str, str]] = []
    for row in manifest_rows:
        relative_path = row["relative_path"]
        expected_kind = MANIFEST_FIXED_KINDS.get(relative_path)
        if expected_kind is not None:
            if row["kind"] != expected_kind or row["zone"] or row["mesh_name"]:
                raise AuditInputError(f"Route manifest metadata is invalid for {relative_path!r}.")
        elif relative_path == MANIFEST_RUNTIME_PATH:
            if row["kind"] != "runtime" or row["zone"] or row["mesh_name"]:
                raise AuditInputError("Route runtime manifest row is malformed.")
        elif relative_path.startswith("third_party/xiNavmeshes/"):
            if (
                row["kind"] != "mesh"
                or not row["zone"].isdigit()
                or int(row["zone"]) <= 0
                or not row["mesh_name"]
                or Path(relative_path).name.casefold() != row["mesh_name"].casefold()
            ):
                raise AuditInputError(f"Route mesh manifest row is malformed: {relative_path!r}.")
            mesh_rows.append(row)
        else:
            raise AuditInputError(f"Route manifest has an unexpected child {relative_path!r}.")
        source = (
            repo_root.joinpath(*relative_path.split("/"))
            if relative_path.startswith("third_party/")
            else addon_root.joinpath(*relative_path.split("/"))
        )
        try:
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
        except OSError as error:
            raise AuditInputError(f"Route manifest child is missing: {source}.") from error
        if digest != row["sha256"]:
            raise AuditInputError(f"Route manifest child hash is stale: {relative_path!r}.")

    try:
        reader_text = (addon_root / "accessxi_reader.lua").read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise AuditInputError(f"Cannot read the objective manifest pin: {error}") from error
    pins = READER_MANIFEST_PIN.findall(reader_text)
    if (
        len(pins) != 1
        or pins[0] != hashlib.sha256(manifest_payload).hexdigest()
    ):
        raise AuditInputError("Reader objective manifest pin is missing, duplicated, or stale.")

    zone_mesh_names: dict[str, str] = {}
    mesh_hashes: dict[str, str] = {}
    for row in mesh_rows:
        zone = row["zone"]
        if zone in zone_mesh_names:
            raise AuditInputError(f"Route manifest maps zone {zone} to multiple meshes.")
        zone_mesh_names[zone] = row["mesh_name"]
        mesh_hashes[zone] = row["sha256"]

    try:
        policy = route_evidence.load_policy(guide_data_root / "route-proof-policy.json")
        transition_payload = (guide_data_root / "route-transitions.json").read_bytes()
        transition_definitions = route_evidence.load_transition_definitions(
            guide_data_root / "route-transitions.json"
        )
        catalogue = route_evidence.load_route_catalogue_files(
            addon_root / "data" / "ffxi-nav-destinations.tsv",
            addon_root / "data" / "ffxi-nav-zoneline-graph.tsv",
        )
    except (OSError, route_evidence.RouteEvidenceError) as error:
        raise AuditInputError(f"Cannot derive current route input roots: {error}") from error

    policy_module = addon_root / "modules" / "mission_quest_route_policy.lua"
    transitions_module = addon_root / "modules" / "mission_quest_route_transitions.lua"
    try:
        policy_payload = policy_module.read_bytes()
        generated_transitions = transitions_module.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise AuditInputError(f"Cannot read generated route semantics: {error}") from error
    if policy_payload != route_evidence.render_policy_lua(policy).encode("utf-8"):
        raise AuditInputError("Generated route policy differs from the current source policy.")
    transition_digest = hashlib.sha256(transition_payload).hexdigest()
    transition_match = re.fullmatch(
        r'-- Generated by tools/objective_guides/route_evidence\.py\. Do not edit\.\r?\n'
        r'local transitions = \{\r?\n'
        r'  schema_version = 2,\r?\n'
        r'  source_registry_sha256 = "([0-9a-f]{64})",\r?\n'
        r'  definitions = ([\s\S]*?),\r?\n'
        r'  authorized = ([\s\S]*?),\r?\n'
        r'\}\r?\nreturn transitions\r?\n?',
        generated_transitions,
    )
    if transition_match is None or transition_match.group(1) != transition_digest:
        raise AuditInputError("Generated route transition metadata is malformed or stale.")
    try:
        generated_definitions = _LuaLiteralParser(transition_match.group(2)).parse()
        generated_authorized = _LuaLiteralParser(transition_match.group(3)).parse()
    except AuditInputError as error:
        raise AuditInputError(f"Generated route transitions are malformed: {error}") from error
    if (
        not isinstance(generated_definitions, list)
        or not isinstance(generated_authorized, list)
        or generated_definitions != [dict(row) for row in transition_definitions]
        or any(not isinstance(row, Mapping) for row in generated_authorized)
    ):
        raise AuditInputError("Generated route transition definitions differ from the current registry.")
    try:
        expected_transitions = route_evidence.render_transitions_lua(
            generated_authorized,
            source_registry_sha256=transition_digest,
            definitions=transition_definitions,
        )
    except route_evidence.RouteEvidenceError as error:
        raise AuditInputError(f"Generated route transition authorization is stale: {error}") from error
    if generated_transitions != expected_transitions:
        raise AuditInputError("Generated route transitions are not the canonical current semantics.")

    destination_hashes = {
        str(row.get("destination_id")): route_evidence.destination_row_sha256(row)
        for row in catalogue["destinations"]
        if str(row.get("destination_id", ""))
    }
    ingress_hashes = {
        str(row["zoneline_id"]): route_evidence.ingress_row_sha256(row)
        for row in catalogue["ingresses"]
    }
    common = {
        "ffxinav_sha256": manifest_by_path[
            "third_party/FFXI-NavMesh-Builder/FFXINAV.dll"
        ]["sha256"],
        "probe_protocol": policy.probe_protocol,
        "probe_schema": policy.probe_schema,
        "policy_revision": policy.policy_revision,
        "policy_sha256": route_evidence.policy_sha256(policy),
        "transition_registry_sha256": transition_digest,
        "destinations_sha256": catalogue["destinations_sha256"],
        "graph_sha256": catalogue["graph_sha256"],
        "destination_row_sha256_by_id": destination_hashes,
        "ingress_row_sha256_by_id": ingress_hashes,
        "zone_mesh_name_by_zone": zone_mesh_names,
    }
    current: dict[str, Mapping[str, Any]] = {}
    for contract in contracts:
        zone = str(contract.get("zone"))
        if zone in current or zone not in zone_mesh_names:
            continue
        current[zone] = {
            **common,
            "mesh_name": zone_mesh_names[zone],
            "mesh_sha256": mesh_hashes[zone],
        }
    return current


def audit_repo(repo_root: Path) -> AuditResult:
    root = Path(repo_root).resolve()
    data = root / "data" / "mission-quest-guides"
    addon = root / "ashita" / "addons" / "accessxi_reader"
    modules = addon / "modules"
    target_review = _read_json(data / "target-review.json")
    contracts = _read_contracts(modules / "mission_quest_route_contracts.lua")
    return audit_artifacts(
        native_manifest=_read_json(data / "native-manifest.json"),
        coverage=_read_json(data / "coverage.json"),
        target_review=target_review,
        reviewed_overrides=_read_json(data / "reviewed-overrides.json"),
        reconciled_step_ids=_read_reconciled_step_ids(modules),
        route_contracts=contracts,
        current_route_inputs_by_zone=_read_current_route_inputs(
            repo_root=root,
            addon_root=addon,
            guide_data_root=data,
            contracts=contracts,
        ),
    )


def _input_error_result(error: Exception) -> AuditResult:
    return AuditResult(
        (),
        (
            AuditIssue(
                "audit-input-error",
                message=str(error),
            ),
        ),
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit mission and quest objective coverage.")
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    args = parser.parse_args(argv)
    try:
        result = audit_repo(args.repo_root)
    except (AuditInputError, OSError, ValueError) as error:
        result = _input_error_result(error)
    print(result.to_json(), end="")
    return 0 if result.complete else 1


if __name__ == "__main__":
    raise SystemExit(main())

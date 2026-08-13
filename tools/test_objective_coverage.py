from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from tools.objective_guides import route_evidence as routes
from tools.objective_guides.audit import (
    MISSION_CONTEXTS,
    QUEST_CONTEXTS,
    audit_artifacts,
    main,
)


EXPECTED_MISSION_CONTEXTS = (
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
EXPECTED_QUEST_CONTEXTS = (
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


def _native_key(kind: str, context: str) -> str:
    return f"{kind}:{context}:1"


def _step_id(native_key: str, order: int = 1) -> str:
    return f"{native_key}:step-{order:03d}"


def _action_id(native_key: str, order: int = 1) -> str:
    return f"{_step_id(native_key, order)}:claim-01"


def _candidate_id(native_key: str, order: int = 1) -> str:
    return f"{_action_id(native_key, order)}:candidate:fixture"


def _destination_id(native_key: str, order: int = 1) -> str:
    safe = native_key.casefold().replace(" ", "-").replace("'", "")
    return f"npc:v1:230:{order}:{safe}"


def _issue_codes(result: object) -> set[str]:
    return {issue.code for issue in result.issues}


def _canonical_sha256(value: object) -> str:
    payload = (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        + "\n"
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _physical_leg_key(local_leg: dict) -> str:
    return _canonical_sha256(
        {
            "inputs": copy.deepcopy(local_leg.get("inputs")),
            "leg": copy.deepcopy(local_leg.get("leg")),
            "probe_request": copy.deepcopy(local_leg.get("probe_request")),
            "observations": copy.deepcopy(local_leg.get("observations")),
        }
    )


def _set_contract_identity(contract: dict) -> None:
    physical_key = _physical_leg_key(contract["local_leg"])
    contract["local_leg"]["evidence_id"] = "mesh:v2:" + physical_key
    contract["contract_id"] = "route:v2:" + _canonical_sha256(
        {
            "candidate_id": contract["candidate_id"],
            "action_id": contract["action_id"],
            "group_id": contract["group_id"],
            "physical_leg_key": physical_key,
            "transition_evidence_ids": contract["transition_evidence_ids"],
        }
    )


class ObjectiveCoverageAuditTests(unittest.TestCase):
    maxDiff = None

    def fixture(self) -> dict:
        native_rows: list[dict] = []
        coverage_rows: dict[str, dict] = {}
        classifications: dict[str, dict] = {}
        steps: list[dict] = []
        ledger: list[dict] = []
        reconciled_step_ids: list[str] = []
        record_offset = 64
        for kind, contexts in (
            ("mission", EXPECTED_MISSION_CONTEXTS),
            ("quest", EXPECTED_QUEST_CONTEXTS),
        ):
            for context in contexts:
                native_key = _native_key(kind, context)
                stable_step_id = _step_id(native_key)
                action_id = _action_id(native_key)
                native_rows.append(
                    {
                        "key": native_key,
                        "kind": kind,
                        "context": context,
                        "title": f"Fixture {context}",
                        "native_id": 1,
                        "progress_id": 1,
                        "record_offset": record_offset,
                        "source_dat": "ROM/fixture.DAT",
                        "details": ["Wait for the fixture signal."],
                    }
                )
                record_offset += 64
                classifications[native_key] = {"classification": "playable"}
                coverage_rows[native_key] = {
                    "kind": kind,
                    "context": context,
                    "title": f"Fixture {context}",
                    "status": "guide",
                    "source_pages": {
                        "bg": {
                            "page_id": record_offset,
                            "revision_id": 1001,
                            "title": f"Fixture {context}",
                            "source_url": f"https://www.bg-wiki.com/ffxi/Fixture_{record_offset}",
                        },
                        "ffxiclopedia": {
                            "page_id": record_offset + 1,
                            "revision_id": 2001,
                            "title": f"Fixture {context}",
                            "source_url": f"https://ffxiclopedia.fandom.com/wiki/Fixture_{record_offset}",
                        },
                    },
                    "reconcile_module": "mission_quest_reconcile_fixture",
                    "automatic_stages": {},
                    "automatic_stage": False,
                    "route_ready": False,
                }
                steps.append(
                    {
                        "native_key": native_key,
                        "stable_step_id": stable_step_id,
                        "action": "wait",
                        "comparison": "corroborated",
                        "classification": "instruction-only",
                        "typed_claims": [
                            {"stable_claim_id": action_id, "action": "wait"}
                        ],
                        "source_instructions": {
                            "bg": "Wait for the fixture signal.",
                            "ffxiclopedia": "Wait for the fixture signal.",
                        },
                        "source_revisions": {"bg": 1001, "ffxiclopedia": 2001},
                        "route_ready": False,
                    }
                )
                ledger.append(
                    {
                        "native_key": native_key,
                        "action_id": action_id,
                        "source_action_span_ids": [
                            f"{stable_step_id}:bg:action-01",
                            f"{stable_step_id}:ffxiclopedia:action-01",
                        ],
                        "action": "wait",
                        "status": "instruction-only",
                        "reason": "complete-instruction",
                        "candidate_ids": [],
                        "candidate_count": 0,
                        "instruction": "Wait for the fixture signal.",
                        "material": True,
                        "route_ready": False,
                    }
                )
                reconciled_step_ids.append(stable_step_id)
        return {
            "native_manifest": {"schema_version": 1, "objectives": native_rows},
            "coverage": {
                "schema_version": 1,
                "objectives": coverage_rows,
                "counts": {},
                "source_inventory": {},
                "matching": {},
            },
            "target_review": {
                "schema_version": 1,
                "steps": steps,
                "action_resolution_ledger": ledger,
                "objective_destination_candidates": [],
                "objective_destination_groups": [],
                "objective_destinations": [],
                "reviewed_target_failures": [],
            },
            "reviewed_overrides": {
                "schema_version": 8,
                "native_classifications": classifications,
                "context_overrides": {},
                "target_overrides": {},
            },
            "reconciled_step_ids": reconciled_step_ids,
            "route_contracts": [],
            "current_route_inputs_by_zone": {},
        }

    def audit(self, fixture: dict):
        return audit_artifacts(**fixture)

    def remove_objective(self, fixture: dict, native_key: str) -> None:
        fixture["native_manifest"]["objectives"] = [
            row for row in fixture["native_manifest"]["objectives"] if row["key"] != native_key
        ]
        fixture["coverage"]["objectives"].pop(native_key)
        fixture["reviewed_overrides"]["native_classifications"].pop(native_key)
        fixture["target_review"]["steps"] = [
            row for row in fixture["target_review"]["steps"] if row["native_key"] != native_key
        ]
        fixture["target_review"]["action_resolution_ledger"] = [
            row
            for row in fixture["target_review"]["action_resolution_ledger"]
            if row["native_key"] != native_key
        ]
        fixture["reconciled_step_ids"] = [
            value for value in fixture["reconciled_step_ids"] if not value.startswith(native_key + ":")
        ]

    def add_context_only(self, fixture: dict, native_key: str, order: int = 2) -> str:
        stable_step_id = _step_id(native_key, order)
        action_id = f"{stable_step_id}:context-01"
        fixture["reconciled_step_ids"].append(stable_step_id)
        fixture["target_review"]["steps"].append(
            {
                "native_key": native_key,
                "stable_step_id": stable_step_id,
                "action": "note",
                "comparison": "single-source",
                "classification": "context-only",
                "typed_claims": [],
                "source_instructions": {"bg": "Historical background.", "ffxiclopedia": ""},
                "route_ready": False,
            }
        )
        fixture["target_review"]["action_resolution_ledger"].append(
            {
                "native_key": native_key,
                "action_id": action_id,
                "source_action_span_ids": [f"{stable_step_id}:bg:context"],
                "action": "context",
                "status": "context-only",
                "reason": "non-material-context-reason",
                "candidate_ids": [],
                "candidate_count": 0,
                "instruction": "Historical background.",
                "material": False,
                "route_ready": False,
            }
        )
        fixture["reviewed_overrides"]["context_overrides"][action_id] = {
            "reason": "historical-explanation"
        }
        return action_id

    def add_nonmaterial_conflict(self, fixture: dict, native_key: str, order: int = 3) -> str:
        stable_step_id = _step_id(native_key, order)
        action_id = f"{stable_step_id}:context-01"
        fixture["reconciled_step_ids"].append(stable_step_id)
        fixture["target_review"]["steps"].append(
            {
                "native_key": native_key,
                "stable_step_id": stable_step_id,
                "action": "note",
                "comparison": "conflict",
                "classification": "conflict",
                "typed_claims": [],
                "source_instructions": {"bg": "Optional lore A.", "ffxiclopedia": "Optional lore B."},
                "route_ready": False,
            }
        )
        fixture["target_review"]["action_resolution_ledger"].append(
            {
                "native_key": native_key,
                "action_id": action_id,
                "source_action_span_ids": [f"{stable_step_id}:bg:context"],
                "action": "context",
                "status": "conflict",
                "reason": "source-conflict",
                "candidate_ids": [],
                "candidate_count": 0,
                "instruction": "",
                "material": False,
                "route_ready": False,
            }
        )
        return action_id

    def make_catalogue_candidate(
        self, fixture: dict, native_key: str, *, automatic: bool = False, contract: bool = True
    ) -> dict:
        step_id = _step_id(native_key)
        action_id = _action_id(native_key)
        candidate_id = _candidate_id(native_key)
        destination_id = _destination_id(native_key)
        step = next(row for row in fixture["target_review"]["steps"] if row["native_key"] == native_key)
        step.update(
            {
                "action": "talk",
                "classification": "routable",
                "typed_claims": [{"stable_claim_id": action_id, "action": "talk"}],
                "source_instructions": {
                    "bg": "Talk to the Fixture NPC.",
                    "ffxiclopedia": "Talk to the Fixture NPC.",
                },
            }
        )
        ledger = next(
            row
            for row in fixture["target_review"]["action_resolution_ledger"]
            if row["native_key"] == native_key
        )
        ledger.update(
            {
                "action_id": action_id,
                "action": "talk",
                "status": "catalogue-candidate",
                "reason": "dual-source-exact-catalogue-match",
                "candidate_ids": [candidate_id],
                "candidate_count": 1,
                "instruction": "",
                "material": True,
                "route_ready": False,
            }
        )
        candidate = {
            "native_key": native_key,
            "candidate_id": candidate_id,
            "action_id": action_id,
            "source_action_span_ids": ledger["source_action_span_ids"],
            "source_sites": ["bg", "ffxiclopedia"],
            "source_revisions": {"bg": 1001, "ffxiclopedia": 2001},
            "coordinate_support": [],
            "coordinate_comparison": "corroborated",
            "action": "talk",
            "items": [],
            "enemies": [],
            "result_relation": "",
            "destination_id": destination_id,
            "zone": 230,
            "zone_name": "Southern San d'Oria",
            "target_name": "Fixture NPC",
            "target_kind": "npc",
            "target_point": [1.0, 2.0, 3.0],
            "raw_identity": "lsb:npc_list:1",
            "raw_spawn_ids": [],
            "cluster_policy_version": "",
            "evidence_level": "dual-source-exact",
            "group_id": "",
            "metadata_class": "",
            "transport_id": "",
            "battlefield_id": "",
            "label": "Fixture NPC",
            "arrival_instruction": "Talk to the Fixture NPC.",
            "classification": "catalogue-candidate",
            "route_ready": False,
        }
        fixture["target_review"]["objective_destination_candidates"].append(candidate)
        if automatic:
            fixture["coverage"]["objectives"][native_key]["automatic_stages"] = {
                "fixture-stage": step_id
            }
            fixture["coverage"]["objectives"][native_key]["automatic_stage"] = True
        expected_inputs = {
            "mesh_name": "Southern_San_dOria.nav",
            "mesh_sha256": "1" * 64,
            "ffxinav_sha256": "2" * 64,
            "probe_protocol": "accessxi-navprobe-findpath-v1",
            "probe_schema": 1,
            "policy_revision": "route-proof-policy-v1",
            "policy_sha256": "3" * 64,
            "transition_registry_sha256": "4" * 64,
            "destinations_sha256": "5" * 64,
            "graph_sha256": "6" * 64,
            "destination_row_sha256": "7" * 64,
            "ingress_row_sha256": "8" * 64,
            "zone_mesh_name": "Southern_San_dOria.nav",
        }
        route_contract = {
            "schema": 2,
            "contract_id": "route:v2:" + "a" * 64,
            "candidate_id": candidate_id,
            "action_id": action_id,
            "group_id": "",
            "destination_id": destination_id,
            "zone": 230,
            "destination": {
                "name": candidate["target_name"],
                "x": candidate["target_point"][0],
                "z": candidate["target_point"][1],
                "y": candidate["target_point"][2],
                "kind": candidate["target_kind"],
                "destination_id": candidate["destination_id"],
                "raw_identity": candidate["raw_identity"],
                "raw_spawn_ids": copy.deepcopy(candidate["raw_spawn_ids"]),
                "cluster_policy_version": candidate["cluster_policy_version"],
            },
            "authorized_directed_prefix": [912930426],
            "local_leg": {
                "schema": 2,
                "evidence_id": "mesh:v2:" + "b" * 64,
                "candidate_id": candidate_id,
                "action_id": action_id,
                "group_id": "",
                "status": "mesh-proven",
                "reason": "mesh-proven",
                "leg": {
                    "zone": 230,
                    "destination_id": destination_id,
                    "zoneline_id": 912930426,
                },
                "inputs": copy.deepcopy(expected_inputs),
            },
            "required_transition_ids": [],
            "transition_evidence_ids": [],
            "expected_inputs": expected_inputs,
            "route_ready": True,
        }
        _set_contract_identity(route_contract)
        if contract:
            fixture["route_contracts"].append(route_contract)
            current = fixture["current_route_inputs_by_zone"].setdefault(
                "230",
                {
                    "mesh_name": "Southern_San_dOria.nav",
                    "mesh_sha256": "1" * 64,
                    "ffxinav_sha256": "2" * 64,
                    "probe_protocol": "accessxi-navprobe-findpath-v1",
                    "probe_schema": 1,
                    "policy_revision": "route-proof-policy-v1",
                    "policy_sha256": "3" * 64,
                    "transition_registry_sha256": "4" * 64,
                    "destinations_sha256": "5" * 64,
                    "graph_sha256": "6" * 64,
                    "destination_row_sha256_by_id": {},
                    "ingress_row_sha256_by_id": {"912930426": "8" * 64},
                    "zone_mesh_name_by_zone": {"230": "Southern_San_dOria.nav"},
                },
            )
            current["destination_row_sha256_by_id"][destination_id] = "7" * 64
        return route_contract

    def test_runtime_contract_binds_exact_immutable_destination_and_hash_inputs(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        self.make_catalogue_candidate(fixture, native_key)
        self.assertTrue(self.audit(fixture).complete)

        for field, stale_value in (
            ("target_name", "Different Fixture NPC"),
            ("target_kind", "object"),
            ("target_point", [9.0, 8.0, 7.0]),
            ("raw_identity", "lsb:npc_list:999"),
            ("raw_spawn_ids", [999]),
            ("cluster_policy_version", "complete-link-v999"),
        ):
            with self.subTest(field=field):
                stale = copy.deepcopy(fixture)
                stale["target_review"]["objective_destination_candidates"][0][field] = stale_value
                self.assertIn("stale-route-contract", _issue_codes(self.audit(stale)))

        missing_inputs = copy.deepcopy(fixture)
        missing_inputs["route_contracts"][0]["expected_inputs"].pop("graph_sha256")
        self.assertIn("stale-route-contract", _issue_codes(self.audit(missing_inputs)))

        invalid_hash = copy.deepcopy(fixture)
        invalid_hash["route_contracts"][0]["expected_inputs"]["mesh_sha256"] = "X" * 64
        self.assertIn("stale-route-contract", _issue_codes(self.audit(invalid_hash)))

        inconsistent_local_leg = copy.deepcopy(fixture)
        inconsistent_local_leg["route_contracts"][0]["local_leg"]["inputs"][
            "destination_row_sha256"
        ] = "9" * 64
        self.assertIn("stale-route-contract", _issue_codes(self.audit(inconsistent_local_leg)))

        malformed_transition_ids = copy.deepcopy(fixture)
        malformed_transition_ids["route_contracts"][0]["transition_evidence_ids"] = [{}]
        self.assertIn(
            "stale-route-contract", _issue_codes(self.audit(malformed_transition_ids))
        )

    def test_coordinated_contract_hash_and_identity_replacement_cannot_self_authorize(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        contract = self.make_catalogue_candidate(fixture, native_key)
        destination_id = contract["destination_id"]
        current_route_inputs = {
            "230": {
                "mesh_name": "Southern_San_dOria.nav",
                "mesh_sha256": "1" * 64,
                "ffxinav_sha256": "2" * 64,
                "probe_protocol": "accessxi-navprobe-findpath-v1",
                "probe_schema": 1,
                "policy_revision": "route-proof-policy-v1",
                "policy_sha256": "3" * 64,
                "transition_registry_sha256": "4" * 64,
                "destinations_sha256": "5" * 64,
                "graph_sha256": "6" * 64,
                "destination_row_sha256_by_id": {destination_id: "7" * 64},
                "ingress_row_sha256_by_id": {"912930426": "8" * 64},
                "zone_mesh_name_by_zone": {"230": "Southern_San_dOria.nav"},
            }
        }
        fixture["current_route_inputs_by_zone"] = current_route_inputs
        current = audit_artifacts(**fixture)
        self.assertTrue(current.complete, current.issues)

        stale = copy.deepcopy(fixture)
        stale_contract = stale["route_contracts"][0]
        for field in (
            "mesh_sha256",
            "ffxinav_sha256",
            "policy_sha256",
            "transition_registry_sha256",
            "destinations_sha256",
            "graph_sha256",
            "destination_row_sha256",
            "ingress_row_sha256",
        ):
            stale_contract["expected_inputs"][field] = "9" * 64
            stale_contract["local_leg"]["inputs"][field] = "9" * 64
        _set_contract_identity(stale_contract)
        stale["current_route_inputs_by_zone"] = current_route_inputs
        result = audit_artifacts(**stale)
        self.assertIn("stale-route-contract", _issue_codes(result))

    def test_candidate_action_and_declared_source_sites_match_exact_parent_claim(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        self.make_catalogue_candidate(fixture, native_key)
        self.assertTrue(self.audit(fixture).complete)

        stale_action = copy.deepcopy(fixture)
        stale_action["target_review"]["objective_destination_candidates"][0]["action"] = "fight"
        self.assertIn("candidate-evidence-incomplete", _issue_codes(self.audit(stale_action)))

        undeclared_site = copy.deepcopy(fixture)
        candidate = undeclared_site["target_review"]["objective_destination_candidates"][0]
        candidate["source_sites"] = ["bg"]
        candidate["source_revisions"] = {"bg": 1001}
        self.assertIn("candidate-evidence-incomplete", _issue_codes(self.audit(undeclared_site)))

        missing_site_span = copy.deepcopy(fixture)
        candidate = missing_site_span["target_review"]["objective_destination_candidates"][0]
        candidate["source_action_span_ids"] = [candidate["source_action_span_ids"][0]]
        self.assertIn("candidate-evidence-incomplete", _issue_codes(self.audit(missing_site_span)))

        revision_mismatch = copy.deepcopy(fixture)
        candidate = revision_mismatch["target_review"]["objective_destination_candidates"][0]
        candidate["source_revisions"].pop("ffxiclopedia")
        self.assertIn("candidate-evidence-incomplete", _issue_codes(self.audit(revision_mismatch)))

    def test_target_override_is_accounted_as_exact_resolved_xor_blocking_failure(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        self.make_catalogue_candidate(fixture, native_key)
        stable_step_id = _step_id(native_key)
        override = {
            "source_revisions": {"bg": 1001, "ffxiclopedia": 2001},
            "reference": {
                "zone": 230,
                "zone_name": "Southern San d'Oria",
                "name": "Fixture NPC",
                "kind": "npc",
            },
            "arrival_instruction": "Talk to the Fixture NPC.",
        }
        fixture["reviewed_overrides"]["target_overrides"][stable_step_id] = override
        self.assertIn("target-override-unaccounted", _issue_codes(self.audit(fixture)))

        resolved = copy.deepcopy(fixture)
        step = next(
            row
            for row in resolved["target_review"]["steps"]
            if row["stable_step_id"] == stable_step_id
        )
        step["navigation_target"] = copy.deepcopy(override["reference"])
        step["review_status"] = "verified-reviewed-target"
        step["route_ready"] = True
        self.assertTrue(self.audit(resolved).complete)

        failed = copy.deepcopy(fixture)
        failed_override = failed["reviewed_overrides"]["target_overrides"][stable_step_id]
        failed_override["source_revisions"]["bg"] = 9999
        failed["target_review"]["reviewed_target_failures"] = [
            {
                "native_key": native_key,
                "override_step_id": stable_step_id,
                "reason": "source-revision-mismatch",
                "candidate_step_ids": [],
                "source_revisions": copy.deepcopy(failed_override["source_revisions"]),
                "reference": copy.deepcopy(failed_override["reference"]),
                "classification": "unresolved",
                "route_ready": False,
            }
        ]
        failed_codes = _issue_codes(self.audit(failed))
        self.assertIn("reviewed-target-failure", failed_codes)
        self.assertIn("stale-override", failed_codes)
        self.assertNotIn("target-override-unaccounted", failed_codes)

        overlap = copy.deepcopy(resolved)
        overlap["target_review"]["reviewed_target_failures"] = copy.deepcopy(
            failed["target_review"]["reviewed_target_failures"]
        )
        self.assertIn("target-override-overlap", _issue_codes(self.audit(overlap)))

    def test_resolution_review_items_are_unique_current_and_block_fixed_point(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        action_id = _action_id(native_key)
        fixture["target_review"]["objective_resolution_review_items"] = [
            {
                "native_key": native_key,
                "review_id": "review:v1:" + "a" * 64,
                "action_id": action_id,
                "target_name": "Fixture NPC",
                "zone_name": "Southern San d'Oria",
                "source_sites": ["bg"],
                "source_action_span_ids": [_step_id(native_key) + ":bg:action-01"],
                "reason": "single-source-needs-independent-corroboration",
                "route_ready": False,
            }
        ]
        self.assertIn("resolution-review-pending", _issue_codes(self.audit(fixture)))

        duplicate = copy.deepcopy(fixture)
        duplicate["target_review"]["objective_resolution_review_items"].append(
            copy.deepcopy(duplicate["target_review"]["objective_resolution_review_items"][0])
        )
        self.assertIn("duplicate-resolution-review", _issue_codes(self.audit(duplicate)))

    def test_every_nested_legacy_override_has_one_current_nonroutable_outcome(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        self.make_catalogue_candidate(fixture, native_key)
        candidate = fixture["target_review"]["objective_destination_candidates"][0]
        ledger = next(
            row
            for row in fixture["target_review"]["action_resolution_ledger"]
            if row["action_id"] == candidate["action_id"]
        )
        fixture["reviewed_overrides"]["mission_destination_overrides"] = {
            native_key: [
                {
                    "id": "fixture-legacy",
                    "source_revisions": {"bg": 1001, "ffxiclopedia": 2001},
                }
            ]
        }
        self.assertIn("legacy-override-unaccounted", _issue_codes(self.audit(fixture)))

        resolved = copy.deepcopy(fixture)
        resolved["target_review"]["legacy_destination_outcomes"] = [
            {
                "native_key": native_key,
                "legacy_override_id": native_key + ":destination:fixture-legacy",
                "action_id": candidate["action_id"],
                "classification": "catalogue-candidate",
                "reason": "migrated-to-action-candidates",
                "candidate_ids": [candidate["candidate_id"]],
                "candidate_count": 1,
                "group_ids": [],
                "source_action_span_ids": copy.deepcopy(ledger["source_action_span_ids"]),
                "source_revisions": {"bg": 1001, "ffxiclopedia": 2001},
                "legacy_review_metadata": {},
                "route_ready": False,
            }
        ]
        self.assertTrue(self.audit(resolved).complete)

        unresolved = copy.deepcopy(resolved)
        outcome = unresolved["target_review"]["legacy_destination_outcomes"][0]
        outcome.update(
            {
                "action_id": "",
                "classification": "unresolved",
                "reason": "legacy-action-migration-required",
                "candidate_ids": [],
                "candidate_count": 0,
                "source_action_span_ids": [],
            }
        )
        self.assertIn("legacy-override-unresolved", _issue_codes(self.audit(unresolved)))

        duplicate = copy.deepcopy(resolved)
        duplicate["target_review"]["legacy_destination_outcomes"].append(
            copy.deepcopy(duplicate["target_review"]["legacy_destination_outcomes"][0])
        )
        self.assertIn("duplicate-legacy-outcome", _issue_codes(self.audit(duplicate)))

        extra = copy.deepcopy(resolved)
        extra["target_review"]["legacy_destination_outcomes"][0][
            "legacy_override_id"
        ] = native_key + ":destination:extra"
        self.assertIn("legacy-outcome-extra", _issue_codes(self.audit(extra)))

    def test_matrix_is_exact_and_complete_fixture_is_green(self) -> None:
        self.assertEqual(MISSION_CONTEXTS, EXPECTED_MISSION_CONTEXTS)
        self.assertEqual(QUEST_CONTEXTS, EXPECTED_QUEST_CONTEXTS)
        result = self.audit(self.fixture())
        self.assertTrue(result.complete, result.issues)
        self.assertEqual([row["context"] for row in result.contexts[:15]], list(EXPECTED_MISSION_CONTEXTS))
        self.assertEqual([row["context"] for row in result.contexts[15:]], list(EXPECTED_QUEST_CONTEXTS))

    def test_explicit_instruction_context_and_nonmaterial_conflict_are_not_routes(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        self.add_context_only(fixture, native_key)
        self.add_nonmaterial_conflict(fixture, native_key)
        result = self.audit(fixture)
        self.assertTrue(result.complete, result.issues)
        row = next(item for item in result.contexts if item["kind"] == "mission" and item["context"] == "Bastok")
        self.assertEqual(row["steps"]["instruction-only"], 1)
        self.assertEqual(row["steps"]["context-only"], 1)
        self.assertEqual(row["steps"]["conflict"], 1)
        self.assertEqual(row["steps"]["routable"], 0)
        self.assertEqual(row["same_zone_routable"], 0)
        self.assertEqual(row["cross_zone_routable"], 0)

    def test_instruction_and_nonmaterial_conflict_must_be_explicit_nonmovement_rows(self) -> None:
        instruction = self.fixture()
        row = instruction["target_review"]["action_resolution_ledger"][0]
        row["action"] = "talk"
        self.assertIn("invalid-instruction-only", _issue_codes(self.audit(instruction)))

        conflict = self.fixture()
        native_key = "mission:Bastok:1"
        action_id = self.add_nonmaterial_conflict(conflict, native_key)
        row = next(
            item
            for item in conflict["target_review"]["action_resolution_ledger"]
            if item["action_id"] == action_id
        )
        row["candidate_ids"] = ["invented-candidate"]
        row["candidate_count"] = 1
        self.assertIn("invalid-nonmaterial-conflict", _issue_codes(self.audit(conflict)))

    def test_missing_required_context_fails(self) -> None:
        fixture = self.fixture()
        self.remove_objective(fixture, "mission:Campaign:1")
        result = self.audit(fixture)
        self.assertIn("missing-context", _issue_codes(result))

    def test_source_coverage_requires_recognized_revision_pinned_page_schema(self) -> None:
        fixture = self.fixture()
        result = self.audit(fixture)
        bastok = next(
            row
            for row in result.contexts
            if row["kind"] == "mission" and row["context"] == "Bastok"
        )
        self.assertEqual(bastok["source_coverage"].get("dual_source"), 1)

        for label, source_pages in (
            ("empty-row", {"bg": {}}),
            (
                "unknown-site",
                {
                    "not-reviewed": {
                        "page_id": 1,
                        "revision_id": 2,
                        "title": "Unknown",
                        "source_url": "https://example.invalid/unknown",
                    }
                },
            ),
            (
                "missing-title",
                {
                    "bg": {
                        "page_id": 1,
                        "revision_id": 2,
                        "title": "",
                        "source_url": "https://www.bg-wiki.com/ffxi/Fixture",
                    }
                },
            ),
            (
                "missing-url",
                {"bg": {"page_id": 1, "revision_id": 2, "title": "Fixture", "source_url": ""}},
            ),
            (
                "nonpositive-revision",
                {
                    "bg": {
                        "page_id": 1,
                        "revision_id": 0,
                        "title": "Fixture",
                        "source_url": "https://www.bg-wiki.com/ffxi/Fixture",
                    }
                },
            ),
        ):
            with self.subTest(label=label):
                stale = self.fixture()
                stale["coverage"]["objectives"]["mission:Bastok:1"][
                    "source_pages"
                ] = source_pages
                self.assertIn("invalid-source-page", _issue_codes(self.audit(stale)))

    def test_unclassified_native_and_stale_classification_fail(self) -> None:
        fixture = self.fixture()
        fixture["reviewed_overrides"]["native_classifications"].pop("mission:Bastok:1")
        fixture["reviewed_overrides"]["native_classifications"]["mission:Missing:999"] = {
            "classification": "sentinel",
            "record_offset": 999,
            "reason": "client-sentinel",
        }
        result = self.audit(fixture)
        self.assertIn("unclassified-native", _issue_codes(result))
        self.assertIn("stale-native-classification", _issue_codes(result))

    def test_sentinel_requires_exact_record_offset_and_exclusion_reason(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        native = next(row for row in fixture["native_manifest"]["objectives"] if row["key"] == native_key)
        fixture["reviewed_overrides"]["native_classifications"][native_key] = {
            "classification": "sentinel",
            "record_offset": native["record_offset"],
            "reason": "client-title-sentinel",
        }
        fixture["coverage"]["objectives"].pop(native_key)
        fixture["target_review"]["steps"] = [
            row for row in fixture["target_review"]["steps"] if row["native_key"] != native_key
        ]
        fixture["target_review"]["action_resolution_ledger"] = [
            row for row in fixture["target_review"]["action_resolution_ledger"] if row["native_key"] != native_key
        ]
        fixture["reconciled_step_ids"] = [
            value for value in fixture["reconciled_step_ids"] if not value.startswith(native_key + ":")
        ]
        self.assertTrue(self.audit(fixture).complete)
        for changed in (
            {"classification": "sentinel", "record_offset": native["record_offset"] + 1, "reason": "client-title-sentinel"},
            {"classification": "sentinel", "record_offset": native["record_offset"], "reason": ""},
        ):
            with self.subTest(changed=changed):
                broken = copy.deepcopy(fixture)
                broken["reviewed_overrides"]["native_classifications"][native_key] = changed
                self.assertIn("invalid-native-classification", _issue_codes(self.audit(broken)))

    def test_every_reconciled_step_is_audited_exactly_once(self) -> None:
        fixture = self.fixture()
        omitted = "mission:Bastok:1:step-999"
        fixture["reconciled_step_ids"].append(omitted)
        self.assertIn("omitted-reconciled-step", _issue_codes(self.audit(fixture)))
        duplicated = self.fixture()
        duplicated["target_review"]["steps"].append(
            copy.deepcopy(duplicated["target_review"]["steps"][0])
        )
        self.assertIn("duplicate-audited-step", _issue_codes(self.audit(duplicated)))

    def test_stale_override_fails(self) -> None:
        fixture = self.fixture()
        fixture["reviewed_overrides"]["target_overrides"]["quest:outlands:99:step-999"] = {
            "destination_id": "npc:v1:1:999"
        }
        self.assertIn("stale-override", _issue_codes(self.audit(fixture)))

    def test_silent_and_material_conflicts_fail(self) -> None:
        fixture = self.fixture()
        step = fixture["target_review"]["steps"][0]
        step["comparison"] = "conflict"
        step["classification"] = "routable"
        self.assertIn("silent-conflict", _issue_codes(self.audit(fixture)))

        material = self.fixture()
        ledger = material["target_review"]["action_resolution_ledger"][0]
        ledger.update(
            {
                "status": "conflict",
                "reason": "source-conflict",
                "instruction": "",
                "material": True,
            }
        )
        step = material["target_review"]["steps"][0]
        step["comparison"] = "conflict"
        step["classification"] = "conflict"
        self.assertIn("material-conflict", _issue_codes(self.audit(material)))

    def test_one_actionable_row_cannot_hide_unresolved_material_sibling(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        step_id = _step_id(native_key, 2)
        action_id = _action_id(native_key, 2)
        fixture["reconciled_step_ids"].append(step_id)
        fixture["target_review"]["steps"].append(
            {
                "native_key": native_key,
                "stable_step_id": step_id,
                "action": "touch",
                "comparison": "corroborated",
                "classification": "unresolved",
                "typed_claims": [{"stable_claim_id": action_id, "action": "touch"}],
                "source_instructions": {"bg": "Touch the seal.", "ffxiclopedia": "Touch the seal."},
                "route_ready": False,
            }
        )
        fixture["target_review"]["action_resolution_ledger"].append(
            {
                "native_key": native_key,
                "action_id": action_id,
                "source_action_span_ids": [f"{step_id}:bg:action-01"],
                "action": "touch",
                "status": "unresolved",
                "reason": "unsupported-action-class",
                "candidate_ids": [],
                "candidate_count": 0,
                "instruction": "",
                "material": True,
                "route_ready": False,
            }
        )
        self.assertIn("unresolved-material-step", _issue_codes(self.audit(fixture)))

    def test_context_and_guide_only_rows_do_not_satisfy_playable_actionability(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        step = next(row for row in fixture["target_review"]["steps"] if row["native_key"] == native_key)
        ledger = next(
            row for row in fixture["target_review"]["action_resolution_ledger"] if row["native_key"] == native_key
        )
        action_id = f"{step['stable_step_id']}:context-01"
        step.update({"action": "note", "typed_claims": [], "classification": "context-only"})
        ledger.update(
            {
                "action_id": action_id,
                "action": "context",
                "status": "context-only",
                "reason": "non-material-context-reason",
                "instruction": "Background.",
                "material": False,
            }
        )
        fixture["reviewed_overrides"]["context_overrides"][action_id] = {
            "reason": "optional-background"
        }
        coverage = fixture["coverage"]["objectives"][native_key]
        coverage.update({"status": "verified-navigation", "route_ready": True})
        result = self.audit(fixture)
        self.assertIn("playable-no-actionable", _issue_codes(result))

    def test_automatic_stage_requires_current_exact_contract(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        expected_contract = self.make_catalogue_candidate(fixture, native_key, automatic=True)
        self.assertTrue(self.audit(fixture).complete)

        missing = copy.deepcopy(fixture)
        missing["route_contracts"] = []
        self.assertIn("automatic-contract-missing", _issue_codes(self.audit(missing)))

        stale = copy.deepcopy(fixture)
        stale["route_contracts"][0]["destination_id"] = "npc:v1:230:other"
        codes = _issue_codes(self.audit(stale))
        self.assertIn("stale-route-contract", codes)
        self.assertIn("automatic-contract-missing", codes)

        stale_step = copy.deepcopy(fixture)
        stale_step["coverage"]["objectives"][native_key]["automatic_stages"] = {
            "fixture-stage": native_key + ":step-999"
        }
        self.assertIn("automatic-step-stale", _issue_codes(self.audit(stale_step)))
        self.assertEqual(expected_contract["candidate_id"], _candidate_id(native_key))

    def test_bad_context_reason_and_action_like_context_fail(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        action_id = self.add_context_only(fixture, native_key)
        fixture["reviewed_overrides"]["context_overrides"][action_id]["reason"] = "just-ignore-it"
        self.assertIn("invalid-context-reason", _issue_codes(self.audit(fixture)))

        for action in ("protect", "touch", "key-item-loss"):
            with self.subTest(action=action):
                broken = self.fixture()
                context_action_id = self.add_context_only(broken, native_key)
                step = next(
                    row
                    for row in broken["target_review"]["steps"]
                    if row["stable_step_id"] == _step_id(native_key, 2)
                )
                step["action"] = action
                step["typed_claims"] = [
                    {"stable_claim_id": context_action_id, "action": action}
                ]
                self.assertIn("action-misclassified-context", _issue_codes(self.audit(broken)))

    def test_routable_metrics_require_exact_candidate_and_contract_ownership(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        self.make_catalogue_candidate(fixture, native_key)
        result = self.audit(fixture)
        self.assertTrue(result.complete, result.issues)
        row = next(item for item in result.contexts if item["kind"] == "mission" and item["context"] == "Bastok")
        self.assertEqual(row["target_evidence_complete"], 1)
        self.assertEqual(row["same_zone_routable"], 1)
        self.assertEqual(row["cross_zone_routable"], 1)
        self.assertEqual(row["steps"]["routable"], 1)

    def test_report_is_byte_deterministic_under_shuffled_artifact_rows(self) -> None:
        fixture = self.fixture()
        baseline = self.audit(fixture).to_json()
        shuffled = copy.deepcopy(fixture)
        shuffled["native_manifest"]["objectives"].reverse()
        shuffled["target_review"]["steps"].reverse()
        shuffled["target_review"]["action_resolution_ledger"].reverse()
        shuffled["reconciled_step_ids"].reverse()
        self.assertEqual(self.audit(shuffled).to_json(), baseline)

    def test_repo_cli_reads_generated_reconciliation_and_exits_nonzero_on_drift(self) -> None:
        fixture = self.fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = root / "data" / "mission-quest-guides"
            modules = root / "ashita" / "addons" / "accessxi_reader" / "modules"
            data.mkdir(parents=True)
            modules.mkdir(parents=True)
            for name, value in (
                ("native-manifest.json", fixture["native_manifest"]),
                ("coverage.json", fixture["coverage"]),
                ("target-review.json", fixture["target_review"]),
                ("reviewed-overrides.json", fixture["reviewed_overrides"]),
            ):
                (data / name).write_text(
                    json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
                )
            reconcile = ["-- fixture", "return {", "  steps = {"]
            reconcile.extend(
                f'    {{ stable_step_id = "{stable_step_id}" }},'
                for stable_step_id in fixture["reconciled_step_ids"]
            )
            reconcile.extend(("  },", "}", ""))
            (modules / "mission_quest_reconcile_fixture.lua").write_text(
                "\n".join(reconcile), encoding="utf-8", newline="\n"
            )
            addon = modules.parent
            addon_data = addon / "data"
            addon_data.mkdir()
            (addon_data / "ffxi-nav-destinations.tsv").write_bytes(b"")
            (addon_data / "ffxi-nav-zoneline-graph.tsv").write_text(
                "zoneline_id\tfrom_zone\tfrom_name\tfrom_code\tfrom_x\tfrom_z\tfrom_y\t"
                "to_zone\tto_name\tto_code\tto_x\tto_z\tto_y\tsource\tconfidence\tnote\n",
                encoding="utf-8",
                newline="\n",
            )
            policy = {
                "schema_version": 2,
                "policy_revision": "route-proof-policy-v1",
                "probe_protocol": "accessxi-navprobe-findpath-v1",
                "probe_schema": 1,
                "thresholds": {
                    "endpoint_epsilon_yalms": 0.75,
                    "minimum_endpoint_clearance_yalms": 0.5,
                    "minimum_waypoint_clearance_yalms": 0.25,
                    "maximum_segment_length_yalms": 80.0,
                    "maximum_waypoint_count": 65536,
                    "transition_corridor_radius_yalms": 3.0,
                },
                "fixtures": [],
            }
            (data / "route-proof-policy.json").write_text(
                json.dumps(policy, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
                newline="\n",
            )
            (data / "route-transitions.json").write_bytes(
                b'{"schema_version":2,"transitions":[]}\n'
            )
            (data / "route-transition-evidence-v2.jsonl").write_bytes(b"")
            dependencies = root / "third_party"
            (dependencies / "FFXI-NavMesh-Builder").mkdir(parents=True)
            (dependencies / "xiNavmeshes").mkdir()
            (dependencies / "FFXI-NavMesh-Builder" / "FFXINAV.dll").write_bytes(
                b"fixture-ffxinav"
            )
            (modules / "mission_quest_route_runtime.lua").write_text(
                "return { schema = 2 }\n", encoding="utf-8", newline="\n"
            )
            runtime_root = routes.write_route_runtime_artifacts(
                repo_root=root,
                third_party_root=dependencies,
                policy=routes.parse_policy(policy),
                contracts=(),
                transitions=(),
                runtime_ready=True,
            )
            (addon / "accessxi_reader.lua").write_text(
                'local ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256 = "'
                + runtime_root["manifest_sha256"]
                + '";\nreturn ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256;\n',
                encoding="utf-8",
                newline="\n",
            )
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["--repo-root", str(root)]), 0)
            first = stdout.getvalue()
            self.assertTrue(json.loads(first)["complete"])
            fixture["reviewed_overrides"]["native_classifications"].pop("mission:Bastok:1")
            (data / "reviewed-overrides.json").write_text(
                json.dumps(fixture["reviewed_overrides"], indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
                newline="\n",
            )
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["--repo-root", str(root)]), 1)
            self.assertIn("unclassified-native", {row["code"] for row in json.loads(stdout.getvalue())["issues"]})

    def test_repo_cli_derives_current_contract_roots_from_manifest_and_source_bytes(self) -> None:
        fixture = self.fixture()
        native_key = "mission:Bastok:1"
        contract = self.make_catalogue_candidate(fixture, native_key)
        destination_id = contract["destination_id"]
        destination_line = (
            "230\tFixture NPC\t1.0\t2.0\t3.0\tnpc\tlsb-npc-list-all\tuntested\t\t"
            + destination_id
            + "\tlsb:npc_list:1\t\t\n"
        ).encode("utf-8")
        graph_header = (
            "zoneline_id\tfrom_zone\tfrom_name\tfrom_code\tfrom_x\tfrom_z\tfrom_y\t"
            "to_zone\tto_name\tto_code\tto_x\tto_z\tto_y\tsource\tconfidence\tnote\n"
        ).encode("utf-8")
        ingress_line = (
            "912930426\t100\tWest Ronfaure\tz1\t0\t0\t0\t230\tSouthern San d'Oria\t"
            "z2\t0\t0\t0\tfixture\tproven\t\n"
        ).encode("utf-8")
        predecessor_lines = (
            "912930419\t90\tTwo Hop Start\tz0\t9\t19\t29\t91\tDeep Start\t"
            "z1\t0\t0\t0\tfixture\tproven\t\n"
            "912930420\t90\tTwo Hop Start\tz0\t10\t20\t30\t100\tWest Ronfaure\t"
            "z1\t0\t0\t0\tfixture\tproven\t\n"
            "912930421\t91\tDeep Start\tz0\t11\t21\t31\t90\tTwo Hop Start\t"
            "z1\t0\t0\t0\tfixture\tproven\t\n"
            "912930422\t92\tAlternate Start\tz0\t12\t22\t32\t100\tWest Ronfaure\t"
            "z1\t0\t0\t0\tfixture\tproven\t\n"
            "912930423\t80\tUnproven Start\tz0\t13\t23\t33\t100\tWest Ronfaure\t"
            "z1\t0\t0\t0\tfixture\tuntested\t\n"
            "912930424\t81\tObserved Start\tz0\t14\t24\t34\t100\tWest Ronfaure\t"
            "z1\t0\t0\t0\tfixture\tobserved\t\n"
            "912930425\t82\tUnselected Target\tz0\t15\t25\t35\t230\tSouthern San d'Oria\t"
            "z2\t0\t0\t0\tfixture\tproven\t\n"
        ).encode("utf-8")
        second_ingress_line = (
            "912930427\t101\tEast Ronfaure\tz1\t16\t26\t36\t230\tSouthern San d'Oria\t"
            "z2\t0\t0\t0\tfixture\tproven\t\n"
        ).encode("utf-8")
        second_predecessor_line = (
            "912930428\t93\tSecond Contract Start\tz0\t17\t27\t37\t101\tEast Ronfaure\t"
            "z1\t0\t0\t0\tfixture\tproven\t\n"
        ).encode("utf-8")
        second_observed_line = (
            "912930429\t83\tSecond Observed Start\tz0\t18\t28\t38\t101\tEast Ronfaure\t"
            "z1\t0\t0\t0\tfixture\tobserved\t\n"
        ).encode("utf-8")
        graph_payload = (
            graph_header
            + predecessor_lines
            + second_predecessor_line
            + second_observed_line
            + ingress_line
            + second_ingress_line
        )
        policy = {
            "schema_version": 2,
            "policy_revision": "route-proof-policy-v1",
            "probe_protocol": "accessxi-navprobe-findpath-v1",
            "probe_schema": 1,
            "thresholds": {
                "endpoint_epsilon_yalms": 0.75,
                "minimum_endpoint_clearance_yalms": 0.5,
                "minimum_waypoint_clearance_yalms": 0.25,
                "maximum_segment_length_yalms": 80.0,
                "maximum_waypoint_count": 65536,
                "transition_corridor_radius_yalms": 3.0,
            },
            "fixtures": [],
        }
        transition_payload = b'{"schema_version":2,"transitions":[]}\n'
        dll_payload = b"fixture-ffxinav"
        mesh_payload = b"fixture-navmesh"
        required_meshes = {
            "third_party/xiNavmeshes/Two_Hop_Start.nav": ("90", "Two_Hop_Start.nav", b"zone-90"),
            "third_party/xiNavmeshes/Deep_Start.nav": ("91", "Deep_Start.nav", b"zone-91"),
            "third_party/xiNavmeshes/Alternate_Start.nav": ("92", "Alternate_Start.nav", b"zone-92"),
            "third_party/xiNavmeshes/Second_Contract_Start.nav": (
                "93",
                "Second_Contract_Start.nav",
                b"zone-93",
            ),
            "third_party/xiNavmeshes/West_Ronfaure.nav": ("100", "West_Ronfaure.nav", b"zone-100"),
            "third_party/xiNavmeshes/East_Ronfaure.nav": ("101", "East_Ronfaure.nav", b"zone-101"),
            "third_party/xiNavmeshes/Southern_San_dOria.nav": (
                "230",
                "Southern_San_dOria.nav",
                mesh_payload,
            ),
        }
        excluded_meshes = {
            "third_party/xiNavmeshes/Unproven_Start.nav": ("80", "Unproven_Start.nav", b"zone-80"),
            "third_party/xiNavmeshes/Observed_Start.nav": ("81", "Observed_Start.nav", b"zone-81"),
            "third_party/xiNavmeshes/Second_Observed_Start.nav": (
                "83",
                "Second_Observed_Start.nav",
                b"zone-83",
            ),
            "third_party/xiNavmeshes/Unselected_Target.nav": ("82", "Unselected_Target.nav", b"zone-82"),
        }
        expected_inputs = {
            "mesh_name": "Southern_San_dOria.nav",
            "mesh_sha256": hashlib.sha256(mesh_payload).hexdigest(),
            "ffxinav_sha256": hashlib.sha256(dll_payload).hexdigest(),
            "probe_protocol": policy["probe_protocol"],
            "probe_schema": policy["probe_schema"],
            "policy_revision": policy["policy_revision"],
            "policy_sha256": _canonical_sha256(policy),
            "transition_registry_sha256": hashlib.sha256(transition_payload).hexdigest(),
            "destinations_sha256": hashlib.sha256(destination_line).hexdigest(),
            "graph_sha256": hashlib.sha256(graph_payload).hexdigest(),
            "destination_row_sha256": hashlib.sha256(destination_line).hexdigest(),
            "ingress_row_sha256": hashlib.sha256(ingress_line).hexdigest(),
            "zone_mesh_name": "Southern_San_dOria.nav",
        }
        contract["expected_inputs"] = copy.deepcopy(expected_inputs)
        contract["local_leg"]["inputs"] = copy.deepcopy(expected_inputs)
        _set_contract_identity(contract)
        second_contract = copy.deepcopy(contract)
        second_contract["authorized_directed_prefix"] = [912930427]
        second_contract["local_leg"]["leg"]["zoneline_id"] = 912930427
        second_ingress_digest = hashlib.sha256(second_ingress_line).hexdigest()
        second_contract["expected_inputs"]["ingress_row_sha256"] = (
            second_ingress_digest
        )
        second_contract["local_leg"]["inputs"]["ingress_row_sha256"] = (
            second_ingress_digest
        )
        _set_contract_identity(second_contract)

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            guide_data = root / "data" / "mission-quest-guides"
            addon = root / "ashita" / "addons" / "accessxi_reader"
            modules = addon / "modules"
            addon_data = addon / "data"
            dependencies = root / "third_party"
            guide_data.mkdir(parents=True)
            modules.mkdir(parents=True)
            addon_data.mkdir(parents=True)
            (dependencies / "FFXI-NavMesh-Builder").mkdir(parents=True)
            (dependencies / "xiNavmeshes").mkdir(parents=True)
            for name, value in (
                ("native-manifest.json", fixture["native_manifest"]),
                ("coverage.json", fixture["coverage"]),
                ("target-review.json", fixture["target_review"]),
                ("reviewed-overrides.json", fixture["reviewed_overrides"]),
                ("route-proof-policy.json", policy),
            ):
                (guide_data / name).write_text(
                    json.dumps(value, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                    newline="\n",
                )
            (guide_data / "route-transitions.json").write_bytes(transition_payload)
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(b"")
            reconcile = ["-- fixture", "return {", "  steps = {"]
            reconcile.extend(
                f'    {{ stable_step_id = "{stable_step_id}" }},'
                for stable_step_id in fixture["reconciled_step_ids"]
            )
            reconcile.extend(("  },", "}", ""))
            (modules / "mission_quest_reconcile_fixture.lua").write_text(
                "\n".join(reconcile), encoding="utf-8", newline="\n"
            )
            contract_payload = routes.render_contracts_lua((contract,)).encode("utf-8")
            parsed_policy = routes.parse_policy(policy)
            child_payloads = {
                "data/ffxi-nav-destinations.tsv": destination_line,
                "data/ffxi-nav-zoneline-graph.tsv": graph_payload,
                "modules/mission_quest_route_contracts.lua": contract_payload,
                "modules/mission_quest_route_policy.lua": routes.render_policy_lua(
                    parsed_policy
                ).encode("utf-8"),
                "modules/mission_quest_route_runtime.lua": b"return { schema = 2 }\n",
                "modules/mission_quest_route_transitions.lua": routes.render_transitions_lua(
                    (),
                    source_registry_sha256=hashlib.sha256(transition_payload).hexdigest(),
                    definitions=(),
                ).encode("utf-8"),
                "third_party/FFXI-NavMesh-Builder/FFXINAV.dll": dll_payload,
            }
            second_contract_mesh_paths = {
                "third_party/xiNavmeshes/Second_Contract_Start.nav",
                "third_party/xiNavmeshes/East_Ronfaure.nav",
            }
            child_payloads.update(
                {
                    path: binding[2]
                    for path, binding in required_meshes.items()
                    if path not in second_contract_mesh_paths
                }
            )
            mesh_bindings = {
                path: binding[:2]
                for path, binding in {**required_meshes, **excluded_meshes}.items()
            }

            def write_runtime_root(
                payloads: dict[str, bytes],
                *,
                pin: str | None = None,
                bindings: dict[str, tuple[str, str]] | None = None,
            ) -> str:
                bindings = bindings or mesh_bindings
                for mesh_root in (
                    dependencies / "xiNavmeshes",
                    addon / "third_party" / "xiNavmeshes",
                ):
                    if mesh_root.is_dir():
                        for stale_mesh in mesh_root.glob("*.nav"):
                            stale_mesh.unlink()
                manifest_rows = []
                for relative_path, payload in payloads.items():
                    target = (
                        root / relative_path
                        if relative_path.startswith("third_party/")
                        else addon / relative_path
                    )
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(payload)
                    if relative_path.endswith(".nav"):
                        zone, mesh_name = bindings[relative_path]
                        kind = "mesh"
                    elif relative_path.endswith("FFXINAV.dll"):
                        kind, zone, mesh_name = "ffxinav", "", ""
                    elif relative_path.endswith("ffxi-nav-destinations.tsv"):
                        kind, zone, mesh_name = "destinations", "", ""
                    elif relative_path.endswith("ffxi-nav-zoneline-graph.tsv"):
                        kind, zone, mesh_name = "graph", "", ""
                    elif relative_path.endswith("route_contracts.lua"):
                        kind, zone, mesh_name = "contracts", "", ""
                    elif relative_path.endswith("route_policy.lua"):
                        kind, zone, mesh_name = "policy", "", ""
                    elif relative_path.endswith("route_runtime.lua"):
                        kind, zone, mesh_name = "runtime", "", ""
                    else:
                        kind, zone, mesh_name = "transitions", "", ""
                    manifest_rows.append(
                        (
                            relative_path,
                            hashlib.sha256(payload).hexdigest(),
                            kind,
                            zone,
                            mesh_name,
                        )
                    )
                manifest = "relative_path\tsha256\tkind\tzone\tmesh_name\n" + "".join(
                    "\t".join(row) + "\n"
                    for row in sorted(manifest_rows, key=lambda row: (row[0].casefold(), row[0]))
                )
                manifest_payload = manifest.encode("utf-8")
                (addon_data / "mission-quest-route-manifest.tsv").write_bytes(manifest_payload)
                manifest_pin = pin or hashlib.sha256(manifest_payload).hexdigest()
                (addon / "accessxi_reader.lua").write_text(
                    'local ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256 = "'
                    + manifest_pin
                    + '";\n'
                    + "local expected_manifest_sha256 = "
                    + "ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256;\n"
                    + "return ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256;\n",
                    encoding="utf-8",
                    newline="\n",
                )
                return hashlib.sha256(manifest_payload).hexdigest()

            def run_current() -> tuple[int, dict]:
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    exit_code = main(["--repo-root", str(root)])
                return exit_code, json.loads(output.getvalue())

            def assert_transition_failure(result: dict, reason_fragment: str) -> None:
                messages = [
                    str(row.get("message", ""))
                    for row in result.get("issues", ())
                    if row.get("code") == "audit-input-error"
                ]
                self.assertTrue(
                    any(reason_fragment in message for message in messages),
                    result,
                )
                self.assertFalse(
                    any("manifest mesh set differs" in message.casefold() for message in messages),
                    result,
                )

            write_runtime_root(child_payloads)
            exit_code, result = run_current()
            self.assertEqual(exit_code, 0, result)
            self.assertTrue(result["complete"])

            multi_contract_payloads = copy.deepcopy(child_payloads)
            multi_contract_payloads["modules/mission_quest_route_contracts.lua"] = (
                routes.render_contracts_lua((contract, second_contract)).encode("utf-8")
            )
            for path in second_contract_mesh_paths:
                multi_contract_payloads[path] = required_meshes[path][2]
            with self.subTest(failure="multi-contract-exact-mesh-union"):
                write_runtime_root(multi_contract_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                self.assertTrue(result["complete"])
                bastok = next(
                    row
                    for row in result["contexts"]
                    if row["kind"] == "mission" and row["context"] == "Bastok"
                )
                self.assertEqual(bastok["same_zone_routable"], 1)
                self.assertEqual(bastok["cross_zone_routable"], 1)
                self.assertEqual(bastok["target_evidence_complete"], 1)
            with self.subTest(failure="missing-second-contract-prefix-mesh"):
                incomplete_multi_contract = {
                    path: payload
                    for path, payload in multi_contract_payloads.items()
                    if path
                    != "third_party/xiNavmeshes/Second_Contract_Start.nav"
                }
                write_runtime_root(incomplete_multi_contract)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )
            for failure, sibling_mutation in (
                ("stale-sibling", "stale-input"),
                ("unowned-sibling", "unowned"),
            ):
                with self.subTest(failure=failure):
                    sibling = copy.deepcopy(second_contract)
                    if sibling_mutation == "stale-input":
                        for inputs in (
                            sibling["expected_inputs"],
                            sibling["local_leg"]["inputs"],
                        ):
                            inputs["ingress_row_sha256"] = "f" * 64
                    else:
                        sibling["candidate_id"] = "unowned:candidate"
                        sibling["local_leg"]["candidate_id"] = "unowned:candidate"
                    _set_contract_identity(sibling)
                    stale_sibling_payloads = copy.deepcopy(multi_contract_payloads)
                    stale_sibling_payloads[
                        "modules/mission_quest_route_contracts.lua"
                    ] = routes.render_contracts_lua((contract, sibling)).encode(
                        "utf-8"
                    )
                    write_runtime_root(stale_sibling_payloads)
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1)
                    self.assertIn(
                        "stale-route-contract",
                        {row["code"] for row in result["issues"]},
                    )

            missing_prefix = {
                path: payload
                for path, payload in child_payloads.items()
                if path != "third_party/xiNavmeshes/Deep_Start.nav"
            }
            extra_mesh = copy.deepcopy(child_payloads)
            extra_mesh["third_party/xiNavmeshes/Unselected_Target.nav"] = excluded_meshes[
                "third_party/xiNavmeshes/Unselected_Target.nav"
            ][2]
            duplicate_zone = copy.deepcopy(child_payloads)
            duplicate_zone["third_party/xiNavmeshes/100.nav"] = b"duplicate-zone-100"
            duplicate_bindings = dict(mesh_bindings)
            duplicate_bindings["third_party/xiNavmeshes/100.nav"] = (
                "100",
                "100.nav",
            )
            leading_zero_zone = copy.deepcopy(child_payloads)
            leading_zero_zone["third_party/xiNavmeshes/000.nav"] = (
                b"leading-zero-zone-alias"
            )
            leading_zero_bindings = dict(mesh_bindings)
            leading_zero_bindings["third_party/xiNavmeshes/000.nav"] = (
                "0230",
                "000.nav",
            )
            unicode_zone = copy.deepcopy(child_payloads)
            unicode_zone["third_party/xiNavmeshes/001.nav"] = b"unicode-zone-alias"
            unicode_bindings = dict(mesh_bindings)
            unicode_bindings["third_party/xiNavmeshes/001.nav"] = (
                "٠٢٣٠",
                "001.nav",
            )
            for failure, payloads, bindings in (
                ("missing-prefix-mesh", missing_prefix, mesh_bindings),
                ("extra-unselected-mesh", extra_mesh, mesh_bindings),
                ("duplicate-zone", duplicate_zone, duplicate_bindings),
                (
                    "leading-zero-zone-alias",
                    leading_zero_zone,
                    leading_zero_bindings,
                ),
                ("unicode-zone-alias", unicode_zone, unicode_bindings),
            ):
                with self.subTest(failure=failure):
                    write_runtime_root(payloads, bindings=bindings)
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1)
                    self.assertIn(
                        "audit-input-error", {row["code"] for row in result["issues"]}
                    )

            wrong_prefix_path = "third_party/xiNavmeshes/Wrong_Prefix.nav"
            wrong_prefix_payloads = {
                path: payload
                for path, payload in child_payloads.items()
                if path != "third_party/xiNavmeshes/Deep_Start.nav"
            }
            wrong_prefix_payloads[wrong_prefix_path] = b"coordinated-wrong-zone-91"
            wrong_prefix_bindings = dict(mesh_bindings)
            wrong_prefix_bindings[wrong_prefix_path] = ("91", "Wrong_Prefix.nav")
            with self.subTest(failure="coordinated-wrong-prefix-mesh"):
                write_runtime_root(
                    wrong_prefix_payloads, bindings=wrong_prefix_bindings
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )

            wrong_target_contracts = copy.deepcopy((contract,))
            wrong_target_path = "third_party/xiNavmeshes/Unselected_Target.nav"
            wrong_target_name = "Unselected_Target.nav"
            wrong_target_payload = b"wrong-target-zone-230"
            wrong_target_hash = hashlib.sha256(wrong_target_payload).hexdigest()
            for wrong_target_contract in wrong_target_contracts:
                for inputs in (
                    wrong_target_contract["expected_inputs"],
                    wrong_target_contract["local_leg"]["inputs"],
                ):
                    inputs["mesh_name"] = wrong_target_name
                    inputs["zone_mesh_name"] = wrong_target_name
                    inputs["mesh_sha256"] = wrong_target_hash
                _set_contract_identity(wrong_target_contract)
            wrong_target_payloads = {
                path: payload
                for path, payload in child_payloads.items()
                if path
                not in {
                    "modules/mission_quest_route_contracts.lua",
                    "third_party/xiNavmeshes/Southern_San_dOria.nav",
                }
            }
            wrong_target_payloads["modules/mission_quest_route_contracts.lua"] = (
                routes.render_contracts_lua(wrong_target_contracts).encode("utf-8")
            )
            wrong_target_payloads[wrong_target_path] = wrong_target_payload
            wrong_target_bindings = dict(mesh_bindings)
            wrong_target_bindings[wrong_target_path] = ("230", wrong_target_name)
            with self.subTest(failure="coordinated-wrong-target-mesh"):
                write_runtime_root(
                    wrong_target_payloads, bindings=wrong_target_bindings
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )

            conflicting_name_line = (
                "912930429\t100\tWrong West Name\tz1\t18\t28\t38\t92\tAlternate Start\t"
                "z2\t0\t0\t0\tfixture\tobserved\t\n"
            ).encode("utf-8")
            conflicting_graph = graph_payload + conflicting_name_line
            conflicting_graph_digest = hashlib.sha256(conflicting_graph).hexdigest()
            conflicting_contracts = copy.deepcopy((contract,))
            for conflicting_contract in conflicting_contracts:
                conflicting_contract["expected_inputs"]["graph_sha256"] = (
                    conflicting_graph_digest
                )
                conflicting_contract["local_leg"]["inputs"]["graph_sha256"] = (
                    conflicting_graph_digest
                )
                _set_contract_identity(conflicting_contract)
            conflicting_payloads = copy.deepcopy(child_payloads)
            conflicting_payloads["data/ffxi-nav-zoneline-graph.tsv"] = (
                conflicting_graph
            )
            conflicting_payloads["modules/mission_quest_route_contracts.lua"] = (
                routes.render_contracts_lua(conflicting_contracts).encode("utf-8")
            )
            with self.subTest(failure="conflicting-required-zone-names"):
                write_runtime_root(conflicting_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )

            for failure, prefix in (
                ("empty-prefix", []),
                ("multi-prefix", [912930420, 912930426]),
                ("wrong-singleton-prefix", [912930420]),
            ):
                with self.subTest(failure=failure):
                    stale_contract = copy.deepcopy(contract)
                    stale_contract["authorized_directed_prefix"] = prefix
                    stale_payloads = copy.deepcopy(child_payloads)
                    stale_payloads["modules/mission_quest_route_contracts.lua"] = (
                        routes.render_contracts_lua((stale_contract,)).encode("utf-8")
                    )
                    write_runtime_root(stale_payloads)
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1, result)
                    self.assertFalse(result["complete"])

            with self.subTest(failure="prefix-mesh-child-drift"):
                write_runtime_root(child_payloads)
                (dependencies / "xiNavmeshes" / "Deep_Start.nav").write_bytes(
                    b"changed-prefix-navmesh"
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )

            with self.subTest(failure="prefix-mesh-source-shadow"):
                write_runtime_root(child_payloads)
                (dependencies / "xiNavmeshes" / "Deep_Start.nav").unlink()
                shadow = addon / "third_party" / "xiNavmeshes" / "Deep_Start.nav"
                shadow.parent.mkdir(parents=True, exist_ok=True)
                shadow.write_bytes(required_meshes[
                    "third_party/xiNavmeshes/Deep_Start.nav"
                ][2])
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )

            with self.subTest(failure="updated-manifest-old-reader-pin"):
                original_pin = write_runtime_root(child_payloads)
                updated_payloads = copy.deepcopy(child_payloads)
                updated_payloads["modules/mission_quest_route_runtime.lua"] = (
                    b"return { schema = 2, revision = 2 }\n"
                )
                write_runtime_root(updated_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                write_runtime_root(updated_payloads, pin=original_pin)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )

            missing_runtime = {
                path: payload
                for path, payload in child_payloads.items()
                if path != "modules/mission_quest_route_runtime.lua"
            }
            write_runtime_root(missing_runtime)
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["--repo-root", str(root)]), 1)
            self.assertIn(
                "audit-input-error",
                {row["code"] for row in json.loads(stdout.getvalue())["issues"]},
            )

            write_runtime_root(child_payloads, pin="f" * 64)
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["--repo-root", str(root)]), 1)
            self.assertIn(
                "audit-input-error",
                {row["code"] for row in json.loads(stdout.getvalue())["issues"]},
            )

            stale_generated = copy.deepcopy(child_payloads)
            stale_generated["modules/mission_quest_route_policy.lua"] = b"return { stale = true }\n"
            stale_generated["modules/mission_quest_route_transitions.lua"] = (
                b"return { stale = true }\n"
            )
            write_runtime_root(stale_generated)
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["--repo-root", str(root)]), 1)
            self.assertIn(
                "audit-input-error",
                {row["code"] for row in json.loads(stdout.getvalue())["issues"]},
            )

            write_runtime_root(child_payloads)
            (dependencies / "xiNavmeshes" / "Southern_San_dOria.nav").write_bytes(
                b"changed-navmesh"
            )
            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["--repo-root", str(root)]), 1)
            self.assertIn(
                "audit-input-error",
                {row["code"] for row in json.loads(stdout.getvalue())["issues"]},
            )

            transition_definition = {
                "transition_id": "observed-prefix:forward",
                "base_id": "observed-prefix",
                "zone": 81,
                "direction": "forward",
                "from_zone": 81,
                "to_zone": 100,
                "equivalent_zoneline_id": 912930424,
                "reviewed": True,
                "pre_anchor": {"x": 14.0, "z": 24.0, "y": 34.0},
                "post_anchor": {"x": 0.0, "z": 0.0, "y": 0.0},
                "interaction": {"kind": "fixture", "identity": "observed-prefix"},
                "expected_live_state": "fixture-zone-change",
                "timeout_seconds": 45,
                "cancellation": ["timeout", "player-left-zone"],
                "required_destination_ids": [],
            }
            transition_payload = (
                json.dumps(
                    {
                        "schema_version": 2,
                        "transitions": [transition_definition],
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n"
            ).encode("utf-8")
            transition_digest = hashlib.sha256(transition_payload).hexdigest()

            def current_transition_proof(
                definition: dict,
                *,
                registry_digest: str,
                mesh_runtime_path: str,
            ) -> dict:
                evidence = {
                    "schema": 2,
                    "transition_evidence_id": "",
                    "transition_id": definition["transition_id"],
                    "status": "transition-proven",
                    "direction": definition["direction"],
                    "zone": definition["zone"],
                    "pre_anchor": copy.deepcopy(definition["pre_anchor"]),
                    "post_anchor": copy.deepcopy(definition["post_anchor"]),
                    "interaction": copy.deepcopy(definition["interaction"]),
                    "observed_live_state": definition["expected_live_state"],
                    "timeout_seconds": definition["timeout_seconds"],
                    "timeout_result": "bounded-success",
                    "cancellation_observed": copy.deepcopy(
                        definition["cancellation"]
                    ),
                    "trace": {"source": "fixture.log:1-2", "sha256": "d" * 64},
                    "inputs": {
                        "policy_sha256": _canonical_sha256(policy),
                        "transition_registry_sha256": registry_digest,
                        "mesh_sha256": hashlib.sha256(
                            excluded_meshes[mesh_runtime_path][2]
                        ).hexdigest(),
                        "ffxinav_sha256": hashlib.sha256(dll_payload).hexdigest(),
                        "destinations_sha256": hashlib.sha256(
                            destination_line
                        ).hexdigest(),
                        "graph_sha256": hashlib.sha256(graph_payload).hexdigest(),
                    },
                }
                evidence["transition_evidence_id"] = (
                    routes.transition_evidence_id(evidence)
                )
                return evidence

            transition_proof = current_transition_proof(
                transition_definition,
                registry_digest=transition_digest,
                mesh_runtime_path="third_party/xiNavmeshes/Observed_Start.nav",
            )

            def transition_contract(
                *, required: bool, proof_ids: tuple[str, ...] | None = None
            ) -> dict:
                row = copy.deepcopy(contract)
                for inputs in (
                    row["expected_inputs"],
                    row["local_leg"]["inputs"],
                ):
                    inputs["transition_registry_sha256"] = transition_digest
                row["required_transition_ids"] = (
                    [transition_definition["transition_id"]] if required else []
                )
                row["transition_evidence_ids"] = list(
                    proof_ids
                    if proof_ids is not None
                    else (
                        (transition_proof["transition_evidence_id"],)
                        if required
                        else ()
                    )
                )
                _set_contract_identity(row)
                return row

            def transition_payloads(
                route_contract: dict,
                *,
                authorized: bool,
                include_observed_mesh: bool,
            ) -> dict[str, bytes]:
                payloads = copy.deepcopy(child_payloads)
                payloads["modules/mission_quest_route_contracts.lua"] = (
                    routes.render_contracts_lua((route_contract,)).encode("utf-8")
                )
                payloads["modules/mission_quest_route_transitions.lua"] = (
                    routes.render_transitions_lua(
                        (transition_definition,) if authorized else (),
                        source_registry_sha256=transition_digest,
                        definitions=(transition_definition,),
                    ).encode("utf-8")
                )
                if include_observed_mesh:
                    payloads["third_party/xiNavmeshes/Observed_Start.nav"] = (
                        excluded_meshes[
                            "third_party/xiNavmeshes/Observed_Start.nav"
                        ][2]
                    )
                return payloads

            (guide_data / "route-transitions.json").write_bytes(transition_payload)
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                routes._canonical_json(transition_proof)
            )
            rooted_transition_contract = transition_contract(required=True)
            with self.subTest(failure="transition-equivalent-exact-current-root"):
                write_runtime_root(
                    transition_payloads(
                        rooted_transition_contract,
                        authorized=True,
                        include_observed_mesh=True,
                    )
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                self.assertTrue(result["complete"])

            second_transition_definition = {
                "transition_id": "second-observed-prefix:forward",
                "base_id": "second-observed-prefix",
                "zone": 83,
                "direction": "forward",
                "from_zone": 83,
                "to_zone": 101,
                "equivalent_zoneline_id": 912930429,
                "reviewed": True,
                "pre_anchor": {"x": 18.0, "z": 28.0, "y": 38.0},
                "post_anchor": {"x": 0.0, "z": 0.0, "y": 0.0},
                "interaction": {
                    "kind": "fixture",
                    "identity": "second-observed-prefix",
                },
                "expected_live_state": "fixture-zone-change",
                "timeout_seconds": 45,
                "cancellation": ["timeout", "player-left-zone"],
                "required_destination_ids": [],
            }
            paired_definitions = (
                transition_definition,
                second_transition_definition,
            )
            paired_registry = (
                json.dumps(
                    {
                        "schema_version": 2,
                        "transitions": list(paired_definitions),
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n"
            ).encode("utf-8")
            paired_digest = hashlib.sha256(paired_registry).hexdigest()
            paired_proofs = (
                current_transition_proof(
                    transition_definition,
                    registry_digest=paired_digest,
                    mesh_runtime_path="third_party/xiNavmeshes/Observed_Start.nav",
                ),
                current_transition_proof(
                    second_transition_definition,
                    registry_digest=paired_digest,
                    mesh_runtime_path=(
                        "third_party/xiNavmeshes/Second_Observed_Start.nav"
                    ),
                ),
            )

            def enrich_contract(
                base_contract: dict, definition: dict, evidence: dict, digest: str
            ) -> dict:
                row = copy.deepcopy(base_contract)
                for inputs in (
                    row["expected_inputs"],
                    row["local_leg"]["inputs"],
                ):
                    inputs["transition_registry_sha256"] = digest
                row["required_transition_ids"] = [definition["transition_id"]]
                row["transition_evidence_ids"] = [
                    evidence["transition_evidence_id"]
                ]
                _set_contract_identity(row)
                return row

            paired_contracts = (
                enrich_contract(
                    contract,
                    transition_definition,
                    paired_proofs[0],
                    paired_digest,
                ),
                enrich_contract(
                    second_contract,
                    second_transition_definition,
                    paired_proofs[1],
                    paired_digest,
                ),
            )
            paired_payloads = copy.deepcopy(multi_contract_payloads)
            paired_payloads["modules/mission_quest_route_contracts.lua"] = (
                routes.render_contracts_lua(paired_contracts).encode("utf-8")
            )
            paired_payloads["modules/mission_quest_route_transitions.lua"] = (
                routes.render_transitions_lua(
                    paired_definitions,
                    source_registry_sha256=paired_digest,
                    definitions=paired_definitions,
                ).encode("utf-8")
            )
            for runtime_path in (
                "third_party/xiNavmeshes/Observed_Start.nav",
                "third_party/xiNavmeshes/Second_Observed_Start.nav",
            ):
                paired_payloads[runtime_path] = excluded_meshes[runtime_path][2]
            (guide_data / "route-transitions.json").write_bytes(paired_registry)
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                b"".join(routes._canonical_json(row) for row in paired_proofs)
            )
            with self.subTest(failure="transition-equivalent-two-owner-isolation"):
                write_runtime_root(paired_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                self.assertTrue(result["complete"])
                bastok = next(
                    row
                    for row in result["contexts"]
                    if row["kind"] == "mission" and row["context"] == "Bastok"
                )
                self.assertEqual(bastok["same_zone_routable"], 1)
                self.assertEqual(bastok["cross_zone_routable"], 1)
                self.assertEqual(bastok["target_evidence_complete"], 1)

            for failure, mutated_contracts in (
                (
                    "transition-equivalent-owner-swap",
                    (
                        enrich_contract(
                            contract,
                            second_transition_definition,
                            paired_proofs[1],
                            paired_digest,
                        ),
                        enrich_contract(
                            second_contract,
                            transition_definition,
                            paired_proofs[0],
                            paired_digest,
                        ),
                    ),
                ),
                (
                    "transition-equivalent-disconnected-required",
                    (
                        enrich_contract(
                            contract,
                            second_transition_definition,
                            paired_proofs[1],
                            paired_digest,
                        ),
                        paired_contracts[1],
                    ),
                ),
            ):
                with self.subTest(failure=failure):
                    broken = copy.deepcopy(paired_payloads)
                    broken["modules/mission_quest_route_contracts.lua"] = (
                        routes.render_contracts_lua(mutated_contracts).encode("utf-8")
                    )
                    write_runtime_root(broken)
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1, result)
                    assert_transition_failure(
                        result, "contract transition ownership"
                    )

            (guide_data / "route-transitions.json").write_bytes(transition_payload)
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                routes._canonical_json(transition_proof)
            )

            with self.subTest(failure="transition-equivalent-missing-mesh"):
                write_runtime_root(
                    transition_payloads(
                        rooted_transition_contract,
                        authorized=True,
                        include_observed_mesh=False,
                    )
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1, result)
                self.assertTrue(
                    any(
                        "missing=[81]" in str(row.get("message", ""))
                        for row in result.get("issues", ())
                        if row.get("code") == "audit-input-error"
                    ),
                    result,
                )

            for failure, evidence_bytes, authorized in (
                ("forged-authorized-no-proof", b"", True),
                (
                    "definition-only-not-authorized",
                    routes._canonical_json(transition_proof),
                    False,
                ),
                (
                    "duplicate-current-proof",
                    routes._canonical_json(transition_proof)
                    + routes._canonical_json(transition_proof),
                    True,
                ),
            ):
                with self.subTest(failure=failure):
                    (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                        evidence_bytes
                    )
                    write_runtime_root(
                        transition_payloads(
                            rooted_transition_contract,
                            authorized=authorized,
                            include_observed_mesh=True,
                        )
                    )
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1, result)
                    assert_transition_failure(result, "transition trust root")

            for failure, proof_ids in (
                ("missing-contract-proof-ref", ()),
                ("wrong-contract-proof-ref", ("transition:v2:" + "f" * 64,)),
                (
                    "duplicate-contract-proof-ref",
                    (
                        transition_proof["transition_evidence_id"],
                        transition_proof["transition_evidence_id"],
                    ),
                ),
                (
                    "extra-contract-proof-ref",
                    (
                        transition_proof["transition_evidence_id"],
                        "transition:v2:" + "e" * 64,
                    ),
                ),
            ):
                with self.subTest(failure=failure):
                    (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                        routes._canonical_json(transition_proof)
                    )
                    mismatched = transition_contract(
                        required=True, proof_ids=proof_ids
                    )
                    write_runtime_root(
                        transition_payloads(
                            mismatched,
                            authorized=True,
                            include_observed_mesh=True,
                        )
                    )
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1, result)
                    assert_transition_failure(result, "transition trust root")

            for field in (
                "policy_sha256",
                "transition_registry_sha256",
                "mesh_sha256",
                "ffxinav_sha256",
                "destinations_sha256",
                "graph_sha256",
            ):
                with self.subTest(failure="stale-transition-proof-" + field):
                    stale_proof = copy.deepcopy(transition_proof)
                    stale_proof["inputs"][field] = "f" * 64
                    stale_proof["transition_evidence_id"] = (
                        routes.transition_evidence_id(stale_proof)
                    )
                    stale_contract = transition_contract(
                        required=True,
                        proof_ids=(stale_proof["transition_evidence_id"],),
                    )
                    (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                        routes._canonical_json(stale_proof)
                    )
                    write_runtime_root(
                        transition_payloads(
                            stale_contract,
                            authorized=True,
                            include_observed_mesh=True,
                        )
                    )
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1, result)
                    assert_transition_failure(result, "transition trust root")

            with self.subTest(failure="transition-proof-real-other-zone-mesh"):
                wrong_mesh_proof = copy.deepcopy(transition_proof)
                wrong_mesh_proof["inputs"]["mesh_sha256"] = hashlib.sha256(
                    excluded_meshes[
                        "third_party/xiNavmeshes/Second_Observed_Start.nav"
                    ][2]
                ).hexdigest()
                wrong_mesh_proof["transition_evidence_id"] = (
                    routes.transition_evidence_id(wrong_mesh_proof)
                )
                wrong_mesh_contract = transition_contract(
                    required=True,
                    proof_ids=(wrong_mesh_proof["transition_evidence_id"],),
                )
                (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                    routes._canonical_json(wrong_mesh_proof)
                )
                wrong_mesh_payloads = transition_payloads(
                    wrong_mesh_contract,
                    authorized=True,
                    include_observed_mesh=True,
                )
                write_runtime_root(wrong_mesh_payloads)
                (
                    dependencies
                    / "xiNavmeshes"
                    / "Second_Observed_Start.nav"
                ).write_bytes(
                    excluded_meshes[
                        "third_party/xiNavmeshes/Second_Observed_Start.nav"
                    ][2]
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1, result)
                assert_transition_failure(result, "transition trust root")

            definition_mutations = (
                ("not-reviewed", {"reviewed": False}),
                ("direction-id-mismatch", {"direction": "reverse"}),
                ("base-id-mismatch", {"base_id": "wrong-base"}),
                ("wrong-equivalent-edge", {"equivalent_zoneline_id": 999}),
                ("wrong-from-zone", {"from_zone": 999}),
                ("wrong-to-zone", {"to_zone": 999}),
                ("wrong-definition-zone", {"zone": 83}),
                ("wrong-pre-anchor", {"pre_anchor": {"x": 999.0, "z": 24.0, "y": 34.0}}),
                ("wrong-post-anchor", {"post_anchor": {"x": 999.0, "z": 0.0, "y": 0.0}}),
            )
            for failure, mutation in definition_mutations:
                with self.subTest(failure="transition-definition-" + failure):
                    mutated_definition = copy.deepcopy(transition_definition)
                    mutated_definition.update(copy.deepcopy(mutation))
                    mutated_registry = (
                        json.dumps(
                            {
                                "schema_version": 2,
                                "transitions": [mutated_definition],
                            },
                            sort_keys=True,
                            separators=(",", ":"),
                        )
                        + "\n"
                    ).encode("utf-8")
                    mutated_digest = hashlib.sha256(mutated_registry).hexdigest()
                    source_mesh_path = (
                        "third_party/xiNavmeshes/Second_Observed_Start.nav"
                        if mutated_definition["zone"] == 83
                        else "third_party/xiNavmeshes/Observed_Start.nav"
                    )
                    mutated_proof = current_transition_proof(
                        mutated_definition,
                        registry_digest=mutated_digest,
                        mesh_runtime_path=source_mesh_path,
                    )
                    mutated_contract = enrich_contract(
                        contract,
                        mutated_definition,
                        mutated_proof,
                        mutated_digest,
                    )
                    mutated_payloads = copy.deepcopy(child_payloads)
                    mutated_payloads[
                        "modules/mission_quest_route_contracts.lua"
                    ] = routes.render_contracts_lua((mutated_contract,)).encode(
                        "utf-8"
                    )
                    mutated_payloads[
                        "modules/mission_quest_route_transitions.lua"
                    ] = routes.render_transitions_lua(
                        (mutated_definition,),
                        source_registry_sha256=mutated_digest,
                        definitions=(mutated_definition,),
                    ).encode("utf-8")
                    mutated_payloads[source_mesh_path] = excluded_meshes[
                        source_mesh_path
                    ][2]
                    (guide_data / "route-transitions.json").write_bytes(
                        mutated_registry
                    )
                    (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                        routes._canonical_json(mutated_proof)
                    )
                    write_runtime_root(mutated_payloads)
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1, result)
                    assert_transition_failure(result, "transition equivalence")

            untested_definition = {
                **copy.deepcopy(transition_definition),
                "transition_id": "untested-prefix:forward",
                "base_id": "untested-prefix",
                "zone": 80,
                "from_zone": 80,
                "to_zone": 100,
                "equivalent_zoneline_id": 912930423,
                "pre_anchor": {"x": 13.0, "z": 23.0, "y": 33.0},
            }
            untested_registry = (
                json.dumps(
                    {
                        "schema_version": 2,
                        "transitions": [untested_definition],
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n"
            ).encode("utf-8")
            untested_digest = hashlib.sha256(untested_registry).hexdigest()
            untested_proof = current_transition_proof(
                untested_definition,
                registry_digest=untested_digest,
                mesh_runtime_path="third_party/xiNavmeshes/Unproven_Start.nav",
            )
            untested_contract = enrich_contract(
                contract,
                untested_definition,
                untested_proof,
                untested_digest,
            )
            untested_payloads = copy.deepcopy(child_payloads)
            untested_payloads["modules/mission_quest_route_contracts.lua"] = (
                routes.render_contracts_lua((untested_contract,)).encode("utf-8")
            )
            untested_payloads["modules/mission_quest_route_transitions.lua"] = (
                routes.render_transitions_lua(
                    (untested_definition,),
                    source_registry_sha256=untested_digest,
                    definitions=(untested_definition,),
                ).encode("utf-8")
            )
            untested_payloads[
                "third_party/xiNavmeshes/Unproven_Start.nav"
            ] = excluded_meshes[
                "third_party/xiNavmeshes/Unproven_Start.nav"
            ][2]
            (guide_data / "route-transitions.json").write_bytes(untested_registry)
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                routes._canonical_json(untested_proof)
            )
            inert_untested_contract = copy.deepcopy(contract)
            for inputs in (
                inert_untested_contract["expected_inputs"],
                inert_untested_contract["local_leg"]["inputs"],
            ):
                inputs["transition_registry_sha256"] = untested_digest
            inert_untested_contract["required_transition_ids"] = []
            inert_untested_contract["transition_evidence_ids"] = []
            _set_contract_identity(inert_untested_contract)
            inert_untested_payloads = copy.deepcopy(child_payloads)
            inert_untested_payloads[
                "modules/mission_quest_route_contracts.lua"
            ] = routes.render_contracts_lua(
                (inert_untested_contract,)
            ).encode("utf-8")
            inert_untested_payloads[
                "modules/mission_quest_route_transitions.lua"
            ] = routes.render_transitions_lua(
                (untested_definition,),
                source_registry_sha256=untested_digest,
                definitions=(untested_definition,),
            ).encode("utf-8")
            with self.subTest(failure="transition-equivalent-untested-inert"):
                write_runtime_root(inert_untested_payloads)
                (
                    dependencies / "xiNavmeshes" / "Unproven_Start.nav"
                ).write_bytes(
                    excluded_meshes[
                        "third_party/xiNavmeshes/Unproven_Start.nav"
                    ][2]
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                self.assertTrue(result["complete"])
            with self.subTest(failure="transition-equivalent-untested-edge"):
                write_runtime_root(untested_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1, result)
                assert_transition_failure(result, "transition equivalence")

            ambiguous_definition = {
                **copy.deepcopy(transition_definition),
                "transition_id": "observed-prefix-alternate:forward",
                "base_id": "observed-prefix-alternate",
                "interaction": {
                    "kind": "fixture",
                    "identity": "observed-prefix-alternate",
                },
            }
            ambiguous_definitions = (
                transition_definition,
                ambiguous_definition,
            )
            ambiguous_registry = (
                json.dumps(
                    {
                        "schema_version": 2,
                        "transitions": list(ambiguous_definitions),
                    },
                    sort_keys=True,
                    separators=(",", ":"),
                )
                + "\n"
            ).encode("utf-8")
            ambiguous_digest = hashlib.sha256(ambiguous_registry).hexdigest()
            ambiguous_proofs = tuple(
                current_transition_proof(
                    definition,
                    registry_digest=ambiguous_digest,
                    mesh_runtime_path="third_party/xiNavmeshes/Observed_Start.nav",
                )
                for definition in ambiguous_definitions
            )
            ambiguous_contract = copy.deepcopy(contract)
            for inputs in (
                ambiguous_contract["expected_inputs"],
                ambiguous_contract["local_leg"]["inputs"],
            ):
                inputs["transition_registry_sha256"] = ambiguous_digest
            ambiguous_contract["required_transition_ids"] = sorted(
                definition["transition_id"] for definition in ambiguous_definitions
            )
            ambiguous_contract["transition_evidence_ids"] = sorted(
                row["transition_evidence_id"] for row in ambiguous_proofs
            )
            _set_contract_identity(ambiguous_contract)
            ambiguous_payloads = copy.deepcopy(child_payloads)
            ambiguous_payloads["modules/mission_quest_route_contracts.lua"] = (
                routes.render_contracts_lua((ambiguous_contract,)).encode("utf-8")
            )
            ambiguous_payloads["modules/mission_quest_route_transitions.lua"] = (
                routes.render_transitions_lua(
                    ambiguous_definitions,
                    source_registry_sha256=ambiguous_digest,
                    definitions=ambiguous_definitions,
                ).encode("utf-8")
            )
            ambiguous_payloads["third_party/xiNavmeshes/Observed_Start.nav"] = (
                excluded_meshes[
                    "third_party/xiNavmeshes/Observed_Start.nav"
                ][2]
            )
            (guide_data / "route-transitions.json").write_bytes(ambiguous_registry)
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                b"".join(routes._canonical_json(row) for row in ambiguous_proofs)
            )
            with self.subTest(failure="transition-equivalent-ambiguous-current-mapping"):
                write_runtime_root(ambiguous_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1, result)
                assert_transition_failure(
                    result, "ambiguous transition equivalence"
                )

            (guide_data / "route-transitions.json").write_bytes(transition_payload)
            with self.subTest(failure="authorized-transition-not-required"):
                (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(
                    routes._canonical_json(transition_proof)
                )
                not_required = transition_contract(required=False)
                write_runtime_root(
                    transition_payloads(
                        not_required,
                        authorized=True,
                        include_observed_mesh=False,
                    )
                )
                (
                    dependencies / "xiNavmeshes" / "Observed_Start.nav"
                ).write_bytes(
                    excluded_meshes[
                        "third_party/xiNavmeshes/Observed_Start.nav"
                    ][2]
                )
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                self.assertTrue(result["complete"])

            (guide_data / "route-transitions.json").write_bytes(
                b'{"schema_version":2,"transitions":[]}\n'
            )
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(b"")

            zero_fixture = self.fixture()
            for name, value in (
                ("native-manifest.json", zero_fixture["native_manifest"]),
                ("coverage.json", zero_fixture["coverage"]),
                ("target-review.json", zero_fixture["target_review"]),
                ("reviewed-overrides.json", zero_fixture["reviewed_overrides"]),
            ):
                (guide_data / name).write_text(
                    json.dumps(value, indent=2, sort_keys=True) + "\n",
                    encoding="utf-8",
                    newline="\n",
                )
            zero_payloads = {
                path: payload
                for path, payload in child_payloads.items()
                if not path.endswith(".nav")
            }
            zero_payloads["modules/mission_quest_route_contracts.lua"] = (
                routes.render_contracts_lua(()).encode("utf-8")
            )
            with self.subTest(failure="zero-contract-exact-zero-mesh-baseline"):
                write_runtime_root(zero_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                self.assertTrue(result["complete"])

            zero_extra_mesh = copy.deepcopy(zero_payloads)
            zero_extra_mesh["third_party/xiNavmeshes/Deep_Start.nav"] = required_meshes[
                "third_party/xiNavmeshes/Deep_Start.nav"
            ][2]
            zero_missing_runtime = {
                path: payload
                for path, payload in zero_payloads.items()
                if path != "modules/mission_quest_route_runtime.lua"
            }
            zero_missing_fixed = {
                path: payload
                for path, payload in zero_payloads.items()
                if path != "data/ffxi-nav-destinations.tsv"
            }
            zero_stale_policy = copy.deepcopy(zero_payloads)
            zero_stale_policy["modules/mission_quest_route_policy.lua"] = (
                b"return { stale = true }\n"
            )
            zero_stale_transitions = copy.deepcopy(zero_payloads)
            zero_stale_transitions["modules/mission_quest_route_transitions.lua"] = (
                b"return { stale = true }\n"
            )
            for failure, payloads in (
                ("zero-contract-extra-mesh", zero_extra_mesh),
                ("zero-contract-missing-runtime", zero_missing_runtime),
                ("zero-contract-missing-fixed-child", zero_missing_fixed),
                ("zero-contract-stale-policy-semantics", zero_stale_policy),
                ("zero-contract-stale-transition-semantics", zero_stale_transitions),
            ):
                with self.subTest(failure=failure):
                    write_runtime_root(payloads)
                    exit_code, result = run_current()
                    self.assertEqual(exit_code, 1)
                    self.assertIn(
                        "audit-input-error", {row["code"] for row in result["issues"]}
                    )

            with self.subTest(failure="zero-contract-updated-manifest-old-pin"):
                old_zero_pin = write_runtime_root(zero_payloads)
                changed_zero_payloads = copy.deepcopy(zero_payloads)
                changed_zero_payloads["modules/mission_quest_route_runtime.lua"] = (
                    b"return { schema = 2, zero_revision = 2 }\n"
                )
                write_runtime_root(changed_zero_payloads)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 0, result)
                write_runtime_root(changed_zero_payloads, pin=old_zero_pin)
                exit_code, result = run_current()
                self.assertEqual(exit_code, 1)
                self.assertIn(
                    "audit-input-error", {row["code"] for row in result["issues"]}
                )


if __name__ == "__main__":
    unittest.main()

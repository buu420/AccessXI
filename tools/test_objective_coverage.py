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
            (modules / "mission_quest_route_contracts.lua").write_text(
                "-- Generated by fixture.\nlocal contracts = {  }\nreturn contracts\n",
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
        graph_payload = graph_header + ingress_line
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
                "third_party/xiNavmeshes/Southern_San_dOria.nav": mesh_payload,
            }

            def write_runtime_root(payloads: dict[str, bytes], *, pin: str | None = None) -> None:
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
                        kind, zone, mesh_name = "mesh", "230", "Southern_San_dOria.nav"
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

            write_runtime_root(child_payloads)

            stdout = io.StringIO()
            with contextlib.redirect_stdout(stdout):
                self.assertEqual(main(["--repo-root", str(root)]), 0)
            self.assertTrue(json.loads(stdout.getvalue())["complete"])

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


if __name__ == "__main__":
    unittest.main()

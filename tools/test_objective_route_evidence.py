from __future__ import annotations

import copy
import hashlib
import importlib
import json
import math
import os
import random
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
POLICY_PATH = REPO_ROOT / "data" / "mission-quest-guides" / "route-proof-policy.json"

def _policy_case(
    fixture_id: str,
    expect: str,
    *,
    request_end: tuple[float, float, float] = (1.0, 0.0, 0.0),
    **updates: object,
) -> dict:
    observation = {
        "status": "exact-path",
        "start_valid": True,
        "end_valid": True,
        "fallback_used": False,
        "waypoint_count": 2,
        "waypoints": [
            {"x": 0.0, "z": 0.0, "y": 0.0, "clearance": 1.0},
            {
                "x": request_end[0], "z": request_end[1], "y": request_end[2],
                "clearance": 1.0,
            },
        ],
        "first_endpoint_error": 0.0,
        "last_endpoint_error": 0.0,
        "start_clearance": 1.0,
        "end_clearance": 1.0,
        "minimum_waypoint_clearance": 1.0,
        "path_length": math.sqrt(sum(value * value for value in request_end)),
    }
    observation.update(updates)
    return {
        "id": fixture_id,
        "expect": expect,
        "request": {
            "start": {"x": 0.0, "z": 0.0, "y": 0.0},
            "end": {"x": request_end[0], "z": request_end[1], "y": request_end[2]},
        },
        "observation": observation,
    }


POLICY_LITERAL = {
    "schema_version": 2,
    "policy_revision": "objective-route-proof-v2.1",
    "probe_protocol": "accessxi-navprobe-jsonl-v2",
    "probe_schema": 2,
    "thresholds": {
        "endpoint_epsilon_yalms": 0.75,
        "minimum_endpoint_clearance_yalms": 0.5,
        "minimum_waypoint_clearance_yalms": 0.25,
        "maximum_segment_length_yalms": 80.0,
        "maximum_waypoint_count": 65536,
        "transition_corridor_radius_yalms": 3.0,
    },
    "fixtures": [
        _policy_case("exact-two-point", "mesh-proven"),
        _policy_case(
            "invalid-end-exit-zero", "end-invalid", end_valid=False,
            waypoint_count=1,
            waypoints=[{"x": 0.0, "z": 0.0, "y": 0.0, "clearance": 1.0}],
            path_length=0.0,
        ),
        _policy_case(
            "one-waypoint", "too-few-waypoints", waypoint_count=1,
            waypoints=[{"x": 0.0, "z": 0.0, "y": 0.0, "clearance": 1.0}],
            path_length=0.0,
        ),
        _policy_case("closest-fallback", "closest-path-forbidden", fallback_used=True),
        _policy_case(
            "snapped-end", "endpoint-error",
            waypoints=[
                {"x": 0.0, "z": 0.0, "y": 0.0, "clearance": 1.0},
                {"x": 2.0, "z": 0.0, "y": 0.0, "clearance": 1.0},
            ],
            path_length=2.0,
        ),
        _policy_case(
            "low-clearance", "waypoint-clearance",
            waypoints=[
                {"x": 0.0, "z": 0.0, "y": 0.0, "clearance": 1.0},
                {"x": 0.5, "z": 0.0, "y": 0.0, "clearance": 0.1},
                {"x": 1.0, "z": 0.0, "y": 0.0, "clearance": 1.0},
            ],
            waypoint_count=3,
            minimum_waypoint_clearance=0.1,
        ),
        _policy_case("long-segment", "segment-too-long", request_end=(100.0, 0.0, 0.0)),
    ],
}

DLL_HASH = "beff93f959e4b7e5024b4c3c67edbeedf3c5e409e4375bcb83830511176437b3"
MESH_HASH = "2f279fabe671bd84de510001392e2815fd0da54b5cadd80de80b9c747ca3fe85"
REAL_DESTINATIONS_HASH = "842b4242d82754b2cb87a1fbcbcee3e05ad4028aa274c1ef807b07b1d579b8dd"
REAL_GRAPH_HASH = "4f4bf42553912a6828f664a8c8e313ee8e94838f655b3eef23631f3228659e8e"
TRANSITIONS_HASH = "1" * 64

DESTINATION_HEADER = b"# AccessXI route-evidence fixture.\n"
DESTINATION_ROW = (
    b"143\tAmber Quadav\t142.000\t154.000\t-0.076\tenemy\tgenerated-lsb-enemy-camp\t"
    b"untested\t\tcamp:v1:143:amber-quadav:aaaaaaaaaaaaaaaaaaaa\t"
    b"lsb:mob_spawn_points:group:12:mobname:Amber_Quadav\t17362953,17362954\t"
    b"complete-link-v1-h120-y24\n"
)
SECOND_DESTINATION_ROW = (
    b"143\tAmber Quadav\t142.000\t154.000\t20.000\tenemy\tgenerated-lsb-enemy-camp\t"
    b"untested\t\tcamp:v1:143:amber-quadav:bbbbbbbbbbbbbbbbbbbb\t"
    b"lsb:mob_spawn_points:group:13:mobname:Amber_Quadav\t17362955\t"
    b"complete-link-v1-h120-y24\n"
)
DESTINATION_TSV = DESTINATION_HEADER + DESTINATION_ROW + SECOND_DESTINATION_ROW
GRAPH_HEADER = (
    b"zoneline_id\tfrom_zone\tfrom_name\tfrom_code\tfrom_x\tfrom_z\tfrom_y\t"
    b"to_zone\tto_name\tto_code\tto_x\tto_z\tto_y\tsource\tconfidence\tnote\n"
)
INGRESS_ROW = (
    b"947466874\t106\tNorth Gustaberg\tz2y8\t497.899\t1174.924\t-37.517\t143\t"
    b"Palborough Mines\tz3z1\t4.923\t59.551\t-2.383\tfixture-live-walk\tproven\t\n"
)
SECOND_INGRESS_ROW = (
    b"999\t107\tSouth Gustaberg\tfixture\t100.000\t130.000\t-0.500\t143\t"
    b"Palborough Mines\tfixture\t100.000\t130.000\t-0.500\tfixture-live-walk\tproven\t\n"
)
GRAPH_TSV = GRAPH_HEADER + INGRESS_ROW + SECOND_INGRESS_ROW
DESTINATIONS_HASH = hashlib.sha256(DESTINATION_TSV).hexdigest()
GRAPH_HASH = hashlib.sha256(GRAPH_TSV).hexdigest()

DESTINATION_LITERAL = {
    "zone": 143,
    "name": "Amber Quadav",
    "x": 142.0,
    "z": 154.0,
    "y": -0.076,
    "kind": "enemy",
    "source": "generated-lsb-enemy-camp",
    "confidence": "untested",
    "section": "",
    "destination_id": "camp:v1:143:amber-quadav:aaaaaaaaaaaaaaaaaaaa",
    "raw_identity": "lsb:mob_spawn_points:group:12:mobname:Amber_Quadav",
    "raw_spawn_ids": (17362953, 17362954),
    "cluster_policy_version": "complete-link-v1-h120-y24",
}

INGRESS_LITERAL = {
    "zoneline_id": 947466874,
    "from_zone": 106,
    "from_name": "North Gustaberg",
    "from_code": "z2y8",
    "from_x": 497.899,
    "from_z": 1174.924,
    "from_y": -37.517,
    "to_zone": 143,
    "to_name": "Palborough Mines",
    "to_code": "z3z1",
    "to_x": 4.923,
    "to_z": 59.551,
    "to_y": -2.383,
    "source": "fixture-live-walk",
    "confidence": "proven",
    "note": "",
}

SECOND_INGRESS_LITERAL = {
    "zoneline_id": 999,
    "from_zone": 107,
    "from_name": "South Gustaberg",
    "from_code": "fixture",
    "from_x": 100.0,
    "from_z": 130.0,
    "from_y": -0.5,
    "to_zone": 143,
    "to_name": "Palborough Mines",
    "to_code": "fixture",
    "to_x": 100.0,
    "to_z": 130.0,
    "to_y": -0.5,
    "source": "fixture-live-walk",
    "confidence": "proven",
    "note": "",
}

CANDIDATE = {
    "candidate_id": "mission:Bastok:3:step-006:claim-01:candidate:amber-a",
    "action_id": "mission:Bastok:3:step-006:claim-01",
    "group_id": "mission:Bastok:3:step-006:claim-01:group:amber-quadav",
    "destination_id": DESTINATION_LITERAL["destination_id"],
    "zone": 143,
    "zone_name": "Palborough Mines",
    "target_name": "Amber Quadav",
    "target_kind": "enemy",
    "target_point": [142.0, 154.0, -0.076],
    "raw_identity": DESTINATION_LITERAL["raw_identity"],
    "raw_spawn_ids": [17362953, 17362954],
    "cluster_policy_version": "complete-link-v1-h120-y24",
    "route_ready": False,
}


def _response(request_id: str = "leg-1", **updates: object) -> dict:
    row = {
        "schema": 2,
        "protocol": "accessxi-navprobe-jsonl-v2",
        "request_id": request_id,
        "status": "exact-path",
        "start_valid": True,
        "end_valid": True,
        "fallback_used": False,
        "waypoint_count": 4,
        "waypoints": [
            {"x": 4.923, "z": 59.551, "y": -2.383, "clearance": 1.5},
            {"x": 70.0, "z": 100.0, "y": -1.5, "clearance": 1.25},
            {"x": 110.0, "z": 130.0, "y": -0.5, "clearance": 1.25},
            {"x": 142.0, "z": 154.0, "y": -0.076, "clearance": 1.25},
        ],
        "first_endpoint_error": 0.0,
        "last_endpoint_error": 0.0,
        "start_clearance": 1.5,
        "end_clearance": 1.25,
        "minimum_waypoint_clearance": 1.25,
        "path_length": 166.64068223621976,
        "mesh_relative_path": "xiNavmeshes/Palborough_Mines.nav",
        "mesh_sha256": MESH_HASH,
        "mesh_sha256_before": MESH_HASH,
        "mesh_sha256_after": MESH_HASH,
        "ffxinav_relative_path": "FFXI-NavMesh-Builder/FFXINAV.dll",
        "ffxinav_sha256": DLL_HASH,
        "ffxinav_sha256_before": DLL_HASH,
        "ffxinav_sha256_after": DLL_HASH,
        "loaded_dll_path": "C:/fixture/third_party/FFXI-NavMesh-Builder/FFXINAV.dll",
        "loaded_mesh_path": "C:/fixture/third_party/xiNavmeshes/Palborough_Mines.nav",
        "native_calls": {"FindPath": 1, "FindClosestPath": 0, "Get_WayPoints": 1},
    }
    row.update(updates)
    return row


class RouteEvidenceTestCase(unittest.TestCase):
    def routes(self):
        return importlib.import_module("tools.objective_guides.route_evidence")

    def policy(self):
        return self.routes().parse_policy(copy.deepcopy(POLICY_LITERAL))

    def catalogue(self):
        return self.routes().load_route_catalogue_bytes(
            DESTINATION_TSV,
            GRAPH_TSV,
            destination_source="fixture/destinations.tsv",
            graph_source="fixture/graph.tsv",
        )

    def destination(self) -> dict:
        row = self.catalogue()["destinations"][0]
        for key, value in DESTINATION_LITERAL.items():
            self.assertEqual(row[key], value)
        self.assertEqual(row["_raw_tsv_line"].encode("utf-8"), DESTINATION_ROW)
        self.assertEqual(row["_row_sha256"], hashlib.sha256(DESTINATION_ROW).hexdigest())
        self.assertEqual(row["_catalog_sha256"], DESTINATIONS_HASH)
        return row

    def ingress(self, zoneline_id: int = 947466874) -> dict:
        rows = {
            row["zoneline_id"]: row for row in self.catalogue()["ingresses"]
        }
        row = rows[zoneline_id]
        expected = INGRESS_LITERAL if zoneline_id == 947466874 else SECOND_INGRESS_LITERAL
        expected_bytes = INGRESS_ROW if zoneline_id == 947466874 else SECOND_INGRESS_ROW
        for key, value in expected.items():
            self.assertEqual(row[key], value)
        self.assertEqual(row["_raw_tsv_line"].encode("utf-8"), expected_bytes)
        self.assertEqual(row["_row_sha256"], hashlib.sha256(expected_bytes).hexdigest())
        self.assertEqual(row["_catalog_sha256"], GRAPH_HASH)
        return row

    def request(self, request_id: str = "leg-1", **updates: object) -> dict:
        routes = self.routes()
        start = updates.pop("start", {"x": 4.923, "z": 59.551, "y": -2.383})
        end = updates.pop("end", {"x": 142.0, "z": 154.0, "y": -0.076})
        row = routes.build_probe_request(
            request_id=request_id,
            zone=143,
            mesh_relative_path="xiNavmeshes/Palborough_Mines.nav",
            start=start,
            end=end,
            mesh_sha256=MESH_HASH,
            ffxinav_sha256=DLL_HASH,
            policy=self.policy(),
            third_party_root=r"C:\fixture\third_party",
            zone_mesh_names={143: "Palborough_Mines.nav"},
        )
        row.update(updates)
        return row

    def current_inputs(self) -> dict:
        routes = self.routes()
        catalogue = self.catalogue()
        return {
            "mesh_name": "Palborough_Mines.nav",
            "mesh_sha256": MESH_HASH,
            "ffxinav_sha256": DLL_HASH,
            "probe_protocol": "accessxi-navprobe-jsonl-v2",
            "probe_schema": 2,
            "policy_revision": "objective-route-proof-v2.1",
            "policy_sha256": routes.policy_sha256(self.policy()),
            "destination_row_sha256_by_id": {
                row["destination_id"]: routes.destination_row_sha256(row)
                for row in catalogue["destinations"]
            },
            "ingress_row_sha256_by_id": {
                str(row["zoneline_id"]): routes.ingress_row_sha256(row)
                for row in catalogue["ingresses"]
            },
            "transition_registry_sha256": TRANSITIONS_HASH,
            "destinations_sha256": DESTINATIONS_HASH,
            "graph_sha256": GRAPH_HASH,
            "zone_mesh_name_by_zone": {"143": "Palborough_Mines.nav"},
        }


class ProbeProtocolTests(RouteEvidenceTestCase):
    def test_committed_policy_owns_literal_python_and_lua_fixtures(self) -> None:
        routes = self.routes()
        policy = routes.load_policy(POLICY_PATH)
        self.assertEqual(routes.policy_to_mapping(policy), POLICY_LITERAL)
        results = {
            fixture["id"]: routes.classify_policy_fixture(policy, fixture["id"])
            for fixture in POLICY_LITERAL["fixtures"]
        }
        self.assertEqual(
            results,
            {fixture["id"]: fixture["expect"] for fixture in POLICY_LITERAL["fixtures"]},
        )
        for fixture in POLICY_LITERAL["fixtures"]:
            with self.subTest(fixture=fixture["id"]):
                self.assertEqual(
                    routes.classify_policy_case(
                        policy, fixture["request"], fixture["observation"]
                    ),
                    fixture["expect"],
                )
                renamed = dict(fixture, id="renamed-fixture")
                self.assertEqual(
                    routes.classify_policy_case(
                        policy, renamed["request"], renamed["observation"]
                    ),
                    fixture["expect"],
                )
        lua = routes.render_policy_lua(policy)
        for fixture in POLICY_LITERAL["fixtures"]:
            self.assertIn(fixture["id"], lua)
            self.assertIn(fixture["expect"], lua)
        self.assertEqual(
            routes.exercise_policy_lua_fixtures(
                lua,
                REPO_ROOT / "tools" / "lua51" / "lua5.1.exe",
            ),
            {fixture["id"]: fixture["expect"] for fixture in POLICY_LITERAL["fixtures"]},
        )
        tampered_mapping = copy.deepcopy(POLICY_LITERAL)
        tampered_mapping["fixtures"][0]["expect"] = "trust-the-label"
        tampered_policy = routes.parse_policy(tampered_mapping)
        self.assertEqual(
            routes.classify_policy_fixture(tampered_policy, "exact-two-point"),
            "mesh-proven",
        )
        self.assertEqual(
            routes.exercise_policy_lua_fixtures(
                routes.render_policy_lua(tampered_policy),
                REPO_ROOT / "tools" / "lua51" / "lua5.1.exe",
            )["exact-two-point"],
            "mesh-proven",
        )

    def test_probe_request_pins_every_input_and_maps_asymmetric_axes_exactly(self) -> None:
        routes = self.routes()
        request = routes.build_probe_request(
            request_id="axes",
            zone=237,
            mesh_relative_path="xiNavmeshes/Metalworks.nav",
            start={"x": 11.0, "z": 22.0, "y": -33.0},
            end={"x": 44.0, "z": 55.0, "y": -66.0},
            mesh_sha256="2" * 64,
            ffxinav_sha256=DLL_HASH,
            policy=self.policy(),
            third_party_root=r"C:\fixture\third_party",
            zone_mesh_names={237: "Metalworks.nav"},
        )
        self.assertEqual(request["op"], "FindPath")
        self.assertEqual(request["start"], {"x": 11.0, "z": 22.0, "y": -33.0})
        self.assertEqual(
            routes.accessxi_to_native_xyz(request["start"]),
            {"X": 11.0, "Y": -33.0, "Z": 22.0},
        )
        self.assertEqual(
            routes.native_xyz_to_accessxi({"X": 44.0, "Y": -66.0, "Z": 55.0}),
            request["end"],
        )
        self.assertEqual(request["mesh_sha256"], "2" * 64)
        self.assertEqual(request["ffxinav_sha256"], DLL_HASH)
        self.assertEqual(request["policy_revision"], "objective-route-proof-v2.1")
        self.assertEqual(request["protocol"], "accessxi-navprobe-jsonl-v2")
        self.assertEqual(
            request["expected_loaded_dll_path"],
            "C:/fixture/third_party/FFXI-NavMesh-Builder/FFXINAV.dll",
        )
        self.assertEqual(
            request["expected_loaded_mesh_path"],
            "C:/fixture/third_party/xiNavmeshes/Metalworks.nav",
        )

    def test_request_jsonl_is_strict_findpath_only_and_binds_zone_to_mesh(self) -> None:
        routes = self.routes()
        request = self.request()
        exact_fields = set(request)
        bad_mappings = {
            "missing": {key: value for key, value in request.items() if key != "end"},
            "extra": dict(request, invented=True),
            "wrong-op": dict(request, op="FindClosestPath"),
            "schema": dict(request, schema=3),
            "protocol": dict(request, protocol="other"),
            "policy-revision": dict(request, policy_revision="other"),
            "policy-hash": dict(request, policy_sha256="f" * 64),
            "threshold": dict(
                request,
                thresholds=dict(request["thresholds"], maximum_segment_length_yalms=999.0),
            ),
            "hash": dict(request, mesh_sha256="ABC"),
            "type": dict(request, zone="143"),
            "nonfinite": dict(request, start=dict(request["start"], x=math.inf)),
            "zone-mesh": dict(
                request,
                zone=237,
                mesh_relative_path="xiNavmeshes/Metalworks.nav",
                expected_loaded_mesh_path="C:/fixture/third_party/xiNavmeshes/Metalworks.nav",
            ),
        }
        for label, mapping in bad_mappings.items():
            with self.subTest(label=label), self.assertRaises(routes.RouteEvidenceError):
                routes.validate_probe_request_mapping(
                    mapping,
                    policy=self.policy(),
                    third_party_root=Path(r"C:\fixture\third_party"),
                    zone_mesh_names={143: "Palborough_Mines.nav"},
                    exact_fields=exact_fields,
                )
        valid_line = json.dumps(request, allow_nan=False, separators=(",", ":"))
        bad_lines = {
            "duplicate": valid_line.replace('"schema":2', '"schema":2,"schema":2', 1),
            "junk": "not json",
            "nonfinite-json": valid_line.replace('"x":4.923', '"x":NaN', 1),
        }
        for label, line in bad_lines.items():
            with self.subTest(label=label), self.assertRaises(routes.RouteEvidenceError):
                routes.parse_probe_request_jsonl(
                    line + "\n",
                    policy=self.policy(),
                    third_party_root=Path(r"C:\fixture\third_party"),
                    zone_mesh_names={143: "Palborough_Mines.nav"},
                )

    def test_jsonl_response_correlation_rejects_missing_duplicate_unexpected_and_junk(self) -> None:
        routes = self.routes()
        requests = (self.request("a"), self.request("b"))
        valid_a = json.dumps(_response("a"), allow_nan=False)
        valid_b = json.dumps(_response("b"), allow_nan=False)
        invalid_streams = {
            "missing": valid_a + "\n",
            "duplicate": valid_a + "\n" + valid_a + "\n",
            "unexpected": valid_a + "\n" + json.dumps(_response("c")) + "\n",
            "junk": valid_a + "\nnot json\n" + valid_b + "\n",
        }
        for label, stdout in invalid_streams.items():
            with self.subTest(label=label), self.assertRaises(routes.RouteEvidenceError):
                routes.parse_probe_jsonl(requests, stdout, exit_code=0)

    def test_jsonl_rejects_duplicate_keys_schema_protocol_types_and_nonfinite(self) -> None:
        routes = self.routes()
        request = self.request()
        bad_rows = {
            "duplicate-key": '{"schema":2,"schema":2,"protocol":"accessxi-navprobe-jsonl-v2","request_id":"leg-1"}',
            "schema": json.dumps(_response(schema=3)),
            "protocol": json.dumps(_response(protocol="other")),
            "boolean-type": json.dumps(_response(start_valid=1)),
            "waypoint-count-type": json.dumps(_response(waypoint_count="2")),
            "nan": json.dumps(_response(path_length=math.nan)),
            "infinity": json.dumps(_response(path_length=math.inf)),
            "missing-field": json.dumps({key: value for key, value in _response().items() if key != "end_valid"}),
            "extra-field": json.dumps(dict(_response(), invented=True)),
            "nested-extra-field": json.dumps(
                _response(waypoints=[dict(_response()["waypoints"][0], invented=True), *_response()["waypoints"][1:]])
            ),
            "nested-missing-field": json.dumps(
                _response(waypoints=[{key: value for key, value in _response()["waypoints"][0].items() if key != "y"}, *_response()["waypoints"][1:]])
            ),
            "coordinate-type": json.dumps(
                _response(waypoints=[dict(_response()["waypoints"][0], x="4.923"), *_response()["waypoints"][1:]])
            ),
            "waypoint-count-mismatch": json.dumps(_response(waypoint_count=99)),
            "mesh-hash-mismatch": json.dumps(_response(mesh_sha256="f" * 64)),
            "dll-hash-mismatch": json.dumps(_response(ffxinav_sha256="f" * 64)),
            "loaded-mesh-path-mismatch": json.dumps(_response(loaded_mesh_path="C:/shadow/Palborough_Mines.nav")),
            "loaded-dll-path-mismatch": json.dumps(_response(loaded_dll_path="C:/shadow/FFXINAV.dll")),
            "mesh-relative-path-mismatch": json.dumps(_response(mesh_relative_path="xiNavmeshes/Other.nav")),
            "dll-relative-path-mismatch": json.dumps(_response(ffxinav_relative_path="Other/FFXINAV.dll")),
            "mesh-post-hash-mismatch": json.dumps(_response(mesh_sha256_after="f" * 64)),
            "dll-post-hash-mismatch": json.dumps(_response(ffxinav_sha256_after="f" * 64)),
            "invalid-status": json.dumps(_response(status="verified")),
            "renamed-fallback-field": json.dumps(
                dict(
                    {key: value for key, value in _response().items() if key != "fallback_used"},
                    used_closest_path=False,
                )
            ),
            "native-calls-extra": json.dumps(
                _response(native_calls={"FindPath": 1, "FindClosestPath": 0, "Get_WayPoints": 1, "LoadMesh": 1})
            ),
            "native-calls-type": json.dumps(
                _response(native_calls={"FindPath": True, "FindClosestPath": 0, "Get_WayPoints": 1})
            ),
            "exact-path-without-native-call": json.dumps(
                _response(native_calls={"FindPath": 0, "FindClosestPath": 0, "Get_WayPoints": 0})
            ),
            "no-path-without-immediate-waypoint-read": json.dumps(
                _response(
                    status="no-exact-path", waypoint_count=0, waypoints=[], path_length=0.0,
                    native_calls={"FindPath": 1, "FindClosestPath": 0, "Get_WayPoints": 0},
                )
            ),
            "invalid-end-after-findpath": json.dumps(
                _response(
                    status="end-invalid", end_valid=False, waypoint_count=0, waypoints=[], path_length=0.0,
                    native_calls={"FindPath": 1, "FindClosestPath": 0, "Get_WayPoints": 1},
                )
            ),
            "nested-duplicate-key": json.dumps(_response()).replace(
                '"clearance": 1.5', '"clearance": 1.5,"clearance": 1.5', 1
            ),
        }
        for label, stdout in bad_rows.items():
            with self.subTest(label=label), self.assertRaises(routes.RouteEvidenceError):
                routes.parse_probe_jsonl((request,), stdout + "\n", exit_code=0)
        with self.assertRaises(routes.RouteEvidenceError):
            routes.parse_probe_jsonl(
                (request,), json.dumps(_response(), allow_nan=False) + "\n", exit_code=9
            )

    def test_exit_zero_never_promotes_invalid_end_or_one_fallback_waypoint(self) -> None:
        routes = self.routes()
        request = self.request()
        response = _response(
            status="end-invalid",
            end_valid=False,
            fallback_used=False,
            waypoint_count=1,
            waypoints=[{"x": 4.923, "z": 59.551, "y": -2.383, "clearance": 1.5}],
            path_length=0.0,
            native_calls={"FindPath": 0, "FindClosestPath": 0, "Get_WayPoints": 0},
        )
        parsed = routes.parse_probe_jsonl(
            (request,), json.dumps(response, allow_nan=False) + "\n", exit_code=0
        )[0]
        evidence = routes.classify_probe_observation(request, parsed, self.policy())
        self.assertEqual(evidence["status"], "rejected")
        self.assertEqual(evidence["reason"], "end-invalid")

    def test_python_recomputes_acceptance_and_ignores_claimed_success(self) -> None:
        routes = self.routes()
        request = self.request()
        mutations = {
            "start-invalid": {"start_valid": False},
            "end-invalid": {"end_valid": False},
            "closest-path-forbidden": {"fallback_used": True},
            "too-few-waypoints": {"waypoint_count": 1, "waypoints": [_response()["waypoints"][0]]},
            "endpoint-error": {"last_endpoint_error": 1.0},
            "endpoint-clearance": {"end_clearance": 0.1},
            "waypoint-clearance": {
                "waypoints": [
                    _response()["waypoints"][0],
                    dict(_response()["waypoints"][1], clearance=0.1),
                    *_response()["waypoints"][2:],
                ],
                "minimum_waypoint_clearance": 0.1,
            },
            "segment-too-long": {
                "waypoints": [
                    {"x": 4.923, "z": 59.551, "y": -2.383, "clearance": 1.5},
                    {"x": 100.0, "z": 59.551, "y": -2.383, "clearance": 1.5},
                    {"x": 142.0, "z": 154.0, "y": -0.076, "clearance": 1.25},
                ],
                "waypoint_count": 3,
            },
            "endpoint-error-recomputed": {
                "waypoints": [
                    *_response()["waypoints"][:-1],
                    {"x": 141.5, "z": 154.0, "y": -0.076, "clearance": 1.25},
                ],
                "last_endpoint_error": 0.0,
            },
            "waypoint-clearance-recomputed": {
                "waypoints": [
                    *_response()["waypoints"][:-1],
                    {"x": 142.0, "z": 154.0, "y": -0.076, "clearance": 0.1},
                ],
                "minimum_waypoint_clearance": 1.25,
            },
            "path-length-mismatch": {"path_length": 1.0},
            "waypoint-count-excessive": {
                "waypoint_count": POLICY_LITERAL["thresholds"]["maximum_waypoint_count"] + 1,
            },
        }
        for expected_reason, update in mutations.items():
            with self.subTest(expected_reason=expected_reason):
                row = _response(**update)
                result = routes.classify_probe_observation(request, row, self.policy())
                self.assertEqual(result["status"], "rejected")
                self.assertEqual(result["reason"], expected_reason)

    def test_endpoint_clearance_is_an_independent_native_query_not_waypoint_clearance(self) -> None:
        routes = self.routes()
        request = self.request()
        response = _response(start_clearance=0.75, end_clearance=0.8)
        result = routes.classify_probe_observation(request, response, self.policy())
        self.assertEqual((result["status"], result["reason"]), ("mesh-proven", "mesh-proven"))

    def test_worker_sequence_cannot_reuse_stale_waypoints(self) -> None:
        routes = self.routes()
        requests = tuple(self.request(value) for value in ("reachable-1", "unreachable", "reachable-2"))
        rows = (
            _response("reachable-1"),
            _response("unreachable", status="no-exact-path", waypoint_count=0, waypoints=[]),
            _response("reachable-2"),
        )
        parsed = routes.parse_probe_jsonl(
            requests,
            "".join(json.dumps(row, allow_nan=False) + "\n" for row in rows),
            exit_code=0,
        )
        self.assertEqual([row["waypoint_count"] for row in parsed], [4, 0, 4])
        self.assertEqual(parsed[1]["waypoints"], [])
        self.assertEqual(
            [routes.classify_probe_observation(req, row, self.policy())["status"] for req, row in zip(requests, parsed)],
            ["mesh-proven", "rejected", "mesh-proven"],
        )


@unittest.skipUnless(os.name == "nt", "the native proof worker is Windows x86")
class NativeProbeIntegrationTests(RouteEvidenceTestCase):
    def test_injected_native_spy_proves_one_findpath_immediate_copy_no_fallback_and_axis_mapping(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            executable = routes.publish_navprobe(REPO_ROOT, Path(temporary) / "publish")
            result = subprocess.run(
                [str(executable), "--proof-native-self-test"],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report["statuses"], ["exact-path", "no-exact-path", "exact-path"])
        self.assertEqual(report["waypoint_counts"], [2, 0, 2])
        self.assertEqual(report["calls"], {"FindPath": 3, "FindClosestPath": 0, "Get_WayPoints": 3})
        self.assertEqual(report["native_starts"][0], {"X": 11.0, "Y": -33.0, "Z": 22.0})
        self.assertEqual(report["native_ends"][0], {"X": 44.0, "Y": -66.0, "Z": 55.0})
        self.assertEqual(report["copy_order"], ["FindPath", "Get_WayPoints", "copy", "next-request"] * 3)
        self.assertNotIn("FindClosestPath", report["loaded_exports"])

    def test_exact_worker_binds_canonical_bytes_never_falls_back_and_clears_stale_waypoints(self) -> None:
        routes = self.routes()
        third_party_root = (REPO_ROOT / "third_party").resolve()
        dll_path = (third_party_root / "FFXI-NavMesh-Builder" / "FFXINAV.dll").resolve()
        mesh_path = (third_party_root / "xiNavmeshes" / "Metalworks.nav").resolve()
        self.assertTrue(dll_path.is_file())
        self.assertTrue(mesh_path.is_file())
        mesh_hash = hashlib.sha256(mesh_path.read_bytes()).hexdigest()
        with tempfile.TemporaryDirectory() as temporary:
            publish_root = Path(temporary) / "publish"
            executable = routes.publish_navprobe(REPO_ROOT, publish_root)
            (publish_root / "FFXINAV.dll").write_bytes(b"shadow dll must never load")
            vectors = (
                (
                    "reachable-1",
                    {"x": -30.567219, "z": 2.230664, "y": -0.048058},
                    {"x": -58.850000, "z": -11.914000, "y": 2.173604},
                ),
                (
                    "unreachable",
                    {"x": -30.567219, "z": 2.230664, "y": -0.048058},
                    {"x": 66.865000, "z": -4.562000, "y": -14.048058},
                ),
                (
                    "reachable-2",
                    {"x": -52.975567, "z": -11.875000, "y": -10.048058},
                    {"x": 66.865000, "z": -4.562000, "y": -14.048058},
                ),
            )
            requests = tuple(
                routes.build_probe_request(
                    request_id=request_id,
                    zone=237,
                    mesh_relative_path="xiNavmeshes/Metalworks.nav",
                    start=start,
                    end=end,
                    mesh_sha256=mesh_hash,
                    ffxinav_sha256=DLL_HASH,
                    policy=self.policy(),
                    third_party_root=str(third_party_root),
                    zone_mesh_names={237: "Metalworks.nav"},
                )
                for request_id, start, end in vectors
            )
            process = routes.run_native_probe_worker(
                executable,
                third_party_root=third_party_root,
                requests=requests,
                timeout_seconds=30,
            )
            self.assertEqual(process.exit_code, 0, process.stderr)
            responses = routes.parse_probe_jsonl(requests, process.stdout, process.exit_code)
            self.assertEqual(
                [(row["status"], row["waypoint_count"]) for row in responses],
                [("exact-path", responses[0]["waypoint_count"]), ("no-exact-path", 0), ("exact-path", responses[2]["waypoint_count"])],
            )
            self.assertGreaterEqual(responses[0]["waypoint_count"], 2)
            self.assertGreaterEqual(responses[2]["waypoint_count"], 2)
            self.assertEqual(responses[1]["waypoints"], [])
            for row in responses:
                self.assertEqual(row["native_calls"], {"FindPath": 1, "FindClosestPath": 0, "Get_WayPoints": 1})
                self.assertEqual(Path(row["loaded_dll_path"]).resolve(), dll_path)
                self.assertEqual(Path(row["loaded_mesh_path"]).resolve(), mesh_path)
                self.assertEqual(row["ffxinav_sha256_before"], DLL_HASH)
                self.assertEqual(row["ffxinav_sha256_after"], DLL_HASH)
                self.assertEqual(row["mesh_sha256_before"], mesh_hash)
                self.assertEqual(row["mesh_sha256_after"], mesh_hash)
            for request, row in ((requests[0], responses[0]), (requests[2], responses[2])):
                for axis in ("x", "z", "y"):
                    self.assertAlmostEqual(row["waypoints"][0][axis], request["start"][axis], delta=0.75)
                    self.assertAlmostEqual(row["waypoints"][-1][axis], request["end"][axis], delta=0.75)

    def test_native_worker_rejects_malformed_requests_before_any_native_call(self) -> None:
        routes = self.routes()
        third_party_root = (REPO_ROOT / "third_party").resolve()
        valid = routes.build_probe_request(
            request_id="raw",
            zone=237,
            mesh_relative_path="xiNavmeshes/Metalworks.nav",
            start={"x": -30.805, "z": 2.409, "y": 0.0},
            end={"x": -58.850, "z": -11.914, "y": 0.0},
            mesh_sha256=hashlib.sha256(
                (third_party_root / "xiNavmeshes" / "Metalworks.nav").read_bytes()
            ).hexdigest(),
            ffxinav_sha256=DLL_HASH,
            policy=self.policy(),
            third_party_root=third_party_root,
            zone_mesh_names={237: "Metalworks.nav"},
        )
        mappings = (
            {key: value for key, value in valid.items() if key != "end"},
            dict(valid, request_id="extra", invented=True),
            dict(valid, request_id="op", op="FindClosestPath"),
            dict(valid, request_id="schema", schema=3),
            dict(valid, request_id="protocol", protocol="other"),
            dict(valid, request_id="hash", mesh_sha256="f" * 64),
            dict(valid, request_id="type", zone="237"),
            dict(valid, request_id="threshold", thresholds=dict(valid["thresholds"], maximum_segment_length_yalms="bad")),
        )
        lines = [json.dumps(row, allow_nan=False, separators=(",", ":")) for row in mappings]
        duplicate = json.dumps(dict(valid, request_id="duplicate"), separators=(",", ":")).replace(
            '"schema":2', '"schema":2,"schema":2', 1
        )
        nonfinite = json.dumps(dict(valid, request_id="nonfinite"), separators=(",", ":")).replace(
            '"x":-30.805', '"x":NaN', 1
        )
        lines.extend((duplicate, nonfinite, "not json"))
        with tempfile.TemporaryDirectory() as temporary:
            executable = routes.publish_navprobe(REPO_ROOT, Path(temporary) / "publish")
            results = [
                subprocess.run(
                    [str(executable), "--proof-jsonl", "--third-party-root", str(third_party_root)],
                    input=line + "\n",
                    capture_output=True,
                    text=True,
                    timeout=30,
                    check=False,
                )
                for line in lines
            ]
        for result in results:
            with self.subTest(stderr=result.stderr):
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("native_calls=FindPath:0,FindClosestPath:0,Get_WayPoints:0", result.stderr)

    def test_native_invalid_end_exits_zero_without_findpath_or_fallback(self) -> None:
        routes = self.routes()
        third_party_root = (REPO_ROOT / "third_party").resolve()
        mesh_path = (third_party_root / "xiNavmeshes" / "Port_Windurst.nav").resolve()
        mesh_hash = hashlib.sha256(mesh_path.read_bytes()).hexdigest()
        request = routes.build_probe_request(
            request_id="invalid-end",
            zone=240,
            mesh_relative_path="xiNavmeshes/Port_Windurst.nav",
            start={"x": -161.728, "z": 97.883, "y": -4.0},
            end={"x": 100000.0, "z": 100000.0, "y": 100000.0},
            mesh_sha256=mesh_hash,
            ffxinav_sha256=DLL_HASH,
            policy=self.policy(),
            third_party_root=str(third_party_root),
            zone_mesh_names={240: "Port_Windurst.nav"},
        )
        with tempfile.TemporaryDirectory() as temporary:
            executable = routes.publish_navprobe(REPO_ROOT, Path(temporary) / "publish")
            process = routes.run_native_probe_worker(
                executable,
                third_party_root=third_party_root,
                requests=(request,),
                timeout_seconds=30,
            )
        self.assertEqual(process.exit_code, 0, process.stderr)
        row = routes.parse_probe_jsonl((request,), process.stdout, process.exit_code)[0]
        self.assertEqual(row["status"], "end-invalid")
        self.assertTrue(row["start_valid"])
        self.assertFalse(row["end_valid"])
        self.assertEqual(row["waypoint_count"], 0)
        self.assertEqual(row["waypoints"], [])
        self.assertEqual(
            row["native_calls"],
            {"FindPath": 0, "FindClosestPath": 0, "Get_WayPoints": 0},
        )

    def test_native_worker_rejects_path_aliases_root_mismatch_mesh_switch_and_reparse_escape(self) -> None:
        routes = self.routes()
        source_root = (REPO_ROOT / "third_party").resolve()
        mesh_hash = hashlib.sha256(
            (source_root / "xiNavmeshes" / "Metalworks.nav").read_bytes()
        ).hexdigest()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = routes.publish_navprobe(REPO_ROOT, root / "publish")
            base = routes.build_probe_request(
                request_id="path",
                zone=237,
                mesh_relative_path="xiNavmeshes/Metalworks.nav",
                start={"x": -30.805, "z": 2.409, "y": 0.0},
                end={"x": -58.850, "z": -11.914, "y": 0.0},
                mesh_sha256=mesh_hash,
                ffxinav_sha256=DLL_HASH,
                policy=self.policy(),
                third_party_root=str(source_root),
                zone_mesh_names={237: "Metalworks.nav"},
            )
            invalid = (
                dict(base, request_id="rooted", mesh_relative_path=r"C:\shadow\Metalworks.nav"),
                dict(base, request_id="drive-relative", mesh_relative_path=r"C:Metalworks.nav"),
                dict(base, request_id="unc", mesh_relative_path=r"\\server\share\Metalworks.nav"),
                dict(base, request_id="parent", mesh_relative_path="xiNavmeshes/../Metalworks.nav"),
                dict(base, request_id="sibling-prefix", expected_loaded_mesh_path=str(source_root) + "_evil/Metalworks.nav"),
                dict(base, request_id="root-mismatch", expected_loaded_dll_path="C:/shadow/FFXINAV.dll"),
            )
            raw = subprocess.run(
                [str(executable), "--proof-jsonl", "--third-party-root", str(source_root)],
                input="".join(json.dumps(row, allow_nan=False) + "\n" for row in invalid),
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertNotEqual(raw.returncode, 0)
            self.assertEqual(raw.stdout, "")
            self.assertIn(
                "native_calls=FindPath:0,FindClosestPath:0,Get_WayPoints:0",
                raw.stderr,
            )

            port_mesh = source_root / "xiNavmeshes" / "Port_Windurst.nav"
            switched_request = routes.build_probe_request(
                request_id="switch",
                zone=240,
                mesh_relative_path="xiNavmeshes/Port_Windurst.nav",
                start={"x": -161.728, "z": 97.883, "y": -4.0},
                end={"x": 18.629, "z": 76.404, "y": -3.326},
                mesh_sha256=hashlib.sha256(port_mesh.read_bytes()).hexdigest(),
                ffxinav_sha256=DLL_HASH,
                policy=self.policy(),
                third_party_root=str(source_root),
                zone_mesh_names={240: "Port_Windurst.nav"},
            )
            switched = (dict(base, request_id="first"), switched_request)
            raw_switch = subprocess.run(
                [str(executable), "--proof-jsonl", "--third-party-root", str(source_root)],
                input="".join(json.dumps(row, allow_nan=False) + "\n" for row in switched),
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertNotEqual(raw_switch.returncode, 0)
            self.assertEqual(raw_switch.stdout, "")
            self.assertIn(
                "native_calls=FindPath:0,FindClosestPath:0,Get_WayPoints:0",
                raw_switch.stderr,
            )

            staged = root / "third_party"
            (staged / "FFXI-NavMesh-Builder").mkdir(parents=True)
            (staged / "FFXI-NavMesh-Builder" / "FFXINAV.dll").write_bytes(
                (source_root / "FFXI-NavMesh-Builder" / "FFXINAV.dll").read_bytes()
            )
            outside = root / "outside"
            outside.mkdir()
            (outside / "Metalworks.nav").write_bytes(
                (source_root / "xiNavmeshes" / "Metalworks.nav").read_bytes()
            )
            link = staged / "xiNavmeshes"
            junction = subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(link), str(outside)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(junction.returncode, 0, junction.stderr or junction.stdout)
            reparse_request = dict(
                base,
                request_id="reparse",
                expected_loaded_dll_path=str(
                    staged / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
                ),
                expected_loaded_mesh_path=str(staged / "xiNavmeshes" / "Metalworks.nav"),
            )
            raw_reparse = subprocess.run(
                [str(executable), "--proof-jsonl", "--third-party-root", str(staged)],
                input=json.dumps(reparse_request, allow_nan=False) + "\n",
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertNotEqual(raw_reparse.returncode, 0)
            self.assertEqual(raw_reparse.stdout, "")
            self.assertIn(
                "native_calls=FindPath:0,FindClosestPath:0,Get_WayPoints:0",
                raw_reparse.stderr,
            )

    def test_native_hash_gate_precedes_dll_load_and_root_reparse_aliases_reject(self) -> None:
        routes = self.routes()
        source_root = (REPO_ROOT / "third_party").resolve()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = routes.publish_navprobe(REPO_ROOT, root / "publish")
            staged = root / "staged"
            (staged / "FFXI-NavMesh-Builder").mkdir(parents=True)
            (staged / "xiNavmeshes").mkdir()
            (staged / "FFXI-NavMesh-Builder" / "FFXINAV.dll").write_bytes(
                b"not a portable executable"
            )
            mesh_bytes = (source_root / "xiNavmeshes" / "Metalworks.nav").read_bytes()
            (staged / "xiNavmeshes" / "Metalworks.nav").write_bytes(mesh_bytes)
            request = routes.build_probe_request(
                request_id="hash-before-load",
                zone=237,
                mesh_relative_path="xiNavmeshes/Metalworks.nav",
                start={"x": -30.567219, "z": 2.230664, "y": -0.048058},
                end={"x": -58.85, "z": -11.914, "y": 2.173604},
                mesh_sha256=hashlib.sha256(mesh_bytes).hexdigest(),
                ffxinav_sha256="f" * 64,
                policy=self.policy(),
                third_party_root=staged,
                zone_mesh_names={237: "Metalworks.nav"},
            )
            result = subprocess.run(
                [str(executable), "--proof-jsonl", "--third-party-root", str(staged)],
                input=json.dumps(request, allow_nan=False) + "\n",
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "")
            self.assertIn("hash", result.stderr.casefold())
            self.assertNotIn("badimage", result.stderr.casefold())
            self.assertIn(
                "native_calls=FindPath:0,FindClosestPath:0,Get_WayPoints:0",
                result.stderr,
            )

            alias = root / "root-alias"
            junction = subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(alias), str(source_root)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(junction.returncode, 0, junction.stderr or junction.stdout)
            canonical = routes.build_probe_request(
                request_id="root-reparse",
                zone=237,
                mesh_relative_path="xiNavmeshes/Metalworks.nav",
                start={"x": -30.567219, "z": 2.230664, "y": -0.048058},
                end={"x": -58.85, "z": -11.914, "y": 2.173604},
                mesh_sha256=hashlib.sha256(mesh_bytes).hexdigest(),
                ffxinav_sha256=DLL_HASH,
                policy=self.policy(),
                third_party_root=source_root,
                zone_mesh_names={237: "Metalworks.nav"},
            )
            aliased = dict(
                canonical,
                expected_loaded_dll_path=str(
                    alias / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
                ),
                expected_loaded_mesh_path=str(alias / "xiNavmeshes" / "Metalworks.nav"),
            )
            alias_result = subprocess.run(
                [str(executable), "--proof-jsonl", "--third-party-root", str(alias)],
                input=json.dumps(aliased, allow_nan=False) + "\n",
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertNotEqual(alias_result.returncode, 0)
            self.assertEqual(alias_result.stdout, "")
            self.assertIn("reparse", alias_result.stderr.casefold())
            self.assertIn(
                "native_calls=FindPath:0,FindClosestPath:0,Get_WayPoints:0",
                alias_result.stderr,
            )

    def test_diagnostic_cli_preserves_closest_path_fallback_outside_proof_mode(self) -> None:
        routes = self.routes()
        third_party_root = (REPO_ROOT / "third_party").resolve()
        with tempfile.TemporaryDirectory() as temporary:
            publish = Path(temporary) / "publish"
            executable = routes.publish_navprobe(REPO_ROOT, publish)
            (publish / "FFXINAV.dll").write_bytes(
                (third_party_root / "FFXI-NavMesh-Builder" / "FFXINAV.dll").read_bytes()
            )
            result = subprocess.run(
                [
                    str(executable),
                    str(third_party_root / "xiNavmeshes" / "Metalworks.nav"),
                    "-30.567219", "-0.048058", "2.230664",
                    "66.865", "-14.048058", "-4.562",
                ],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        waypoint_line = next(
            line for line in result.stdout.splitlines() if line.startswith("waypoints\t")
        )
        self.assertEqual(waypoint_line, "waypoints\t1")


class EvidenceAndContractTests(RouteEvidenceTestCase):
    def accepted_evidence(self, **updates: object) -> dict:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        row = routes.bind_local_leg_evidence(
            candidate=CANDIDATE,
            destination=destination,
            ingress=ingress,
            request=self.request(),
            observation=routes.classify_probe_observation(
                self.request(), _response(), self.policy()
            ),
            current_inputs=self.current_inputs(),
            required_transition_ids=(),
            policy=self.policy(),
        )
        row.update(updates)
        return row

    def test_row_hashes_cover_exact_canonical_destination_and_full_directed_graph_row(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        destination_hash = routes.destination_row_sha256(destination)
        ingress_hash = routes.ingress_row_sha256(ingress)
        with self.assertRaises(routes.RouteEvidenceError):
            routes.destination_row_sha256(dict(destination, x=142.001))
        with self.assertRaises(routes.RouteEvidenceError):
            routes.ingress_row_sha256(dict(ingress, to_y=-1.595))
        changed_destination_bytes = DESTINATION_TSV.replace(b"142.000", b"142.001", 1)
        changed_graph_bytes = GRAPH_TSV.replace(b"4.923", b"4.9230", 1)
        changed_destination = routes.load_route_catalogue_bytes(
            changed_destination_bytes, GRAPH_TSV,
            destination_source="fixture/changed-destinations.tsv", graph_source="fixture/graph.tsv"
        )["destinations"][0]
        changed_ingress = routes.load_route_catalogue_bytes(
            DESTINATION_TSV, changed_graph_bytes,
            destination_source="fixture/destinations.tsv", graph_source="fixture/changed-graph.tsv"
        )["ingresses"][0]
        self.assertNotEqual(destination_hash, routes.destination_row_sha256(changed_destination))
        self.assertNotEqual(ingress_hash, routes.ingress_row_sha256(changed_ingress))
        self.assertNotEqual(changed_destination["_catalog_sha256"], DESTINATIONS_HASH)
        self.assertNotEqual(changed_ingress["_catalog_sha256"], GRAPH_HASH)
        self.assertEqual(routes.ingress_row_fields()[0], "zoneline_id")
        self.assertNotIn("edge_id", routes.ingress_row_fields())

    def test_full_file_digest_and_exact_row_membership_come_from_the_same_bytes(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        evidence = self.accepted_evidence()
        absent_destination = dict(destination, destination_id="camp:v1:143:absent:x")
        absent_ingress = dict(ingress, zoneline_id=123456789)
        for label, changed_destination, changed_ingress in (
            ("absent-destination", absent_destination, ingress),
            ("absent-ingress", destination, absent_ingress),
        ):
            with self.subTest(label=label):
                self.assertFalse(
                    routes.validate_local_leg_evidence(
                        evidence,
                        candidate=CANDIDATE,
                        destination=changed_destination,
                        ingress=changed_ingress,
                        current_inputs=self.current_inputs(),
                        policy=self.policy(),
                    )[0]
                )

    def test_candidate_instance_rejects_ambiguous_names_and_invalid_camp_geometry(self) -> None:
        routes = self.routes()
        catalogue = self.catalogue()
        destination = self.destination()
        ambiguous = dict(CANDIDATE, destination_id="")
        with self.assertRaises(routes.RouteEvidenceError):
            routes.validate_candidate_instance(
                ambiguous,
                catalogue["destinations"],
                camp_members=((142.0, 154.0, -0.076),),
            )
        self.assertEqual(
            routes.validate_candidate_instance(
                CANDIDATE,
                catalogue["destinations"],
                camp_members=((142.0, 154.0, -0.076), (160.0, 160.0, -1.0)),
            )["destination_id"],
            destination["destination_id"],
        )
        invalid_members = {
            "floor-span": ((142.0, 154.0, -20.0), (142.0, 154.0, 20.0)),
            "diameter": ((0.0, 0.0, 0.0), (121.0, 0.0, 0.0)),
        }
        for label, members in invalid_members.items():
            with self.subTest(label=label), self.assertRaises(routes.RouteEvidenceError):
                routes.validate_candidate_instance(
                    CANDIDATE,
                    catalogue["destinations"],
                    camp_members=members,
                )

    def test_every_directed_prefix_edge_must_be_proven_in_its_forward_direction(self) -> None:
        routes = self.routes()
        ingress = self.ingress()
        proven = dict(ingress, zoneline_id=1, from_zone=100, to_zone=106, confidence="proven")
        final = dict(ingress, confidence="proven")
        self.assertEqual(routes.validate_directed_prefix((proven, final), target_zone=143), (True, "proven"))
        for changed in (
            (dict(proven, confidence="observed"), final),
            (dict(proven, confidence="untested"), final),
            (dict(proven, from_zone=106, to_zone=100), final),
            (proven, dict(final, from_zone=143, to_zone=106)),
            (dict(proven, to_zone=105), final),
        ):
            with self.subTest(changed=changed):
                self.assertFalse(routes.validate_directed_prefix(changed, target_zone=143)[0])

    def test_current_palborough_ingress_is_untested_and_cannot_be_backfilled_as_proven(self) -> None:
        routes = self.routes()
        catalogue = routes.load_route_catalogue_files(
            REPO_ROOT / "data" / "ffxi-nav-destinations.tsv",
            REPO_ROOT / "data" / "ffxi-nav-zoneline-graph.tsv",
        )
        row = next(
            edge for edge in catalogue["ingresses"]
            if edge["zoneline_id"] == 947466874
        )
        self.assertEqual(catalogue["destinations_sha256"], REAL_DESTINATIONS_HASH)
        self.assertEqual(catalogue["graph_sha256"], REAL_GRAPH_HASH)
        self.assertEqual(row["confidence"], "untested")
        self.assertEqual(row["to_zone"], 143)
        self.assertEqual((row["to_x"], row["to_z"], row["to_y"]), (4.923, 59.551, -2.383))
        self.assertFalse(routes.validate_directed_prefix((row,), target_zone=143)[0])

    def test_evidence_binds_immutable_destination_and_exact_directed_ingress(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        evidence = self.accepted_evidence()
        accepted, reason = routes.validate_local_leg_evidence(
            evidence,
            candidate=CANDIDATE,
            destination=destination,
            ingress=ingress,
            current_inputs=self.current_inputs(),
            policy=self.policy(),
        )
        self.assertTrue(accepted, reason)
        mutations = {
            "destination-id": (CANDIDATE, dict(destination, destination_id="camp:v1:143:other:x"), ingress),
            "destination-coordinate": (CANDIDATE, dict(destination, x=141.0), ingress),
            "destination-identity": (CANDIDATE, dict(destination, raw_identity="lsb:other"), ingress),
            "reverse-ingress": (CANDIDATE, destination, dict(ingress, from_zone=143, to_zone=106)),
            "wrong-ingress-zone": (CANDIDATE, destination, dict(ingress, to_zone=142)),
            "wrong-ingress-end": (CANDIDATE, destination, dict(ingress, to_x=5.923)),
            "observed-ingress": (CANDIDATE, destination, dict(ingress, confidence="observed")),
            "untested-ingress": (CANDIDATE, destination, dict(ingress, confidence="untested")),
        }
        for label, (candidate, destination, ingress) in mutations.items():
            with self.subTest(label=label):
                self.assertFalse(
                    routes.validate_local_leg_evidence(
                        evidence,
                        candidate=candidate,
                        destination=destination,
                        ingress=ingress,
                        current_inputs=self.current_inputs(),
                        policy=self.policy(),
                    )[0]
                )
        same_zone = dict(self.ingress(), from_zone=143, to_zone=143)
        accepted, reason = routes.validate_local_leg_evidence(
            evidence,
            candidate=CANDIDATE,
            destination=destination,
            ingress=same_zone,
            current_inputs=self.current_inputs(),
            policy=self.policy(),
        )
        self.assertFalse(accepted)
        self.assertEqual(reason, "invalid-directed-edge")

    def test_hash_or_policy_drift_makes_evidence_stale_not_verified(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        evidence = self.accepted_evidence()
        for field in (
            "mesh_sha256",
            "ffxinav_sha256",
            "policy_sha256",
            "transition_registry_sha256",
            "destinations_sha256",
            "graph_sha256",
        ):
            with self.subTest(field=field):
                inputs = self.current_inputs()
                inputs[field] = "f" * 64
                accepted, reason = routes.validate_local_leg_evidence(
                    evidence,
                    candidate=CANDIDATE,
                    destination=destination,
                    ingress=ingress,
                    current_inputs=inputs,
                    policy=self.policy(),
                )
                self.assertFalse(accepted)
                self.assertEqual(reason, f"stale-{field.replace('_sha256', '').replace('_', '-')}")
        row_hash_mutations = (
            ("destination", "destination_row_sha256_by_id", destination["destination_id"]),
            ("ingress", "ingress_row_sha256_by_id", str(ingress["zoneline_id"])),
        )
        for label, map_name, key in row_hash_mutations:
            with self.subTest(row_hash=label):
                inputs = self.current_inputs()
                inputs[map_name][key] = "f" * 64
                accepted, reason = routes.validate_local_leg_evidence(
                    evidence, candidate=CANDIDATE, destination=destination, ingress=ingress,
                    current_inputs=inputs, policy=self.policy()
                )
                self.assertFalse(accepted)
                self.assertEqual(reason, f"stale-{label}-row")
        wrong_topology = self.current_inputs()
        wrong_topology["zone_mesh_name_by_zone"]["143"] = "Metalworks.nav"
        accepted, reason = routes.validate_local_leg_evidence(
            evidence, candidate=CANDIDATE, destination=destination, ingress=ingress,
            current_inputs=wrong_topology, policy=self.policy()
        )
        self.assertFalse(accepted)
        self.assertEqual(reason, "zone-mesh-mismatch")

    def test_reuse_key_pins_every_physical_input_but_not_objective_owner(self) -> None:
        routes = self.routes()
        evidence = self.accepted_evidence()
        base = routes.physical_leg_reuse_key(evidence)
        for field in evidence["inputs"]:
            with self.subTest(input_field=field):
                changed = copy.deepcopy(evidence)
                value = changed["inputs"][field]
                changed["inputs"][field] = value + 1 if isinstance(value, int) else "changed"
                self.assertNotEqual(routes.physical_leg_reuse_key(changed), base)
        for field in evidence["leg"]:
            with self.subTest(leg_field=field):
                changed = copy.deepcopy(evidence)
                value = changed["leg"][field]
                changed["leg"][field] = value + 1 if isinstance(value, int) else "changed"
                self.assertNotEqual(routes.physical_leg_reuse_key(changed), base)
        other_owner = copy.deepcopy(evidence)
        other_owner["candidate_id"] = "other-candidate"
        other_owner["action_id"] = "other-action"
        self.assertEqual(routes.physical_leg_reuse_key(other_owner), base)

    def test_identical_duplicate_evidence_coalesces_but_conflict_rejects(self) -> None:
        routes = self.routes()
        evidence = self.accepted_evidence()
        self.assertEqual(routes.merge_evidence((evidence, copy.deepcopy(evidence))), (evidence,))
        conflict = copy.deepcopy(evidence)
        conflict["observations"]["path_length"] += 1
        with self.assertRaises(routes.RouteEvidenceError):
            routes.merge_evidence((evidence, conflict))
        stale = copy.deepcopy(evidence)
        stale["status"] = "stale"
        stale["reason"] = "stale-mesh"
        with self.assertRaises(routes.RouteEvidenceError):
            routes.merge_evidence((evidence, stale))

    def test_persisted_evidence_revalidates_exact_probe_observations(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        base = self.accepted_evidence()
        mutations = (
            {
                "waypoint_count": 0,
                "waypoints": [],
                "path_length": 0.0,
            },
            {"path_length": -999.0},
            {
                "native_calls": {
                    "FindPath": 0,
                    "FindClosestPath": 0,
                    "Get_WayPoints": 0,
                }
            },
        )
        for update in mutations:
            with self.subTest(update=update):
                changed = copy.deepcopy(base)
                changed["observations"].update(update)
                changed["evidence_id"] = "mesh:v2:" + routes.physical_leg_reuse_key(changed)
                accepted, _reason = routes.validate_local_leg_evidence(
                    changed,
                    candidate=CANDIDATE,
                    destination=destination,
                    ingress=ingress,
                    current_inputs=self.current_inputs(),
                    policy=self.policy(),
                )
                self.assertFalse(accepted)

    def test_persisted_local_evidence_requires_exact_top_level_schema(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        base = self.accepted_evidence()
        for changed in (dict(base, schema=999), dict(base, invented="junk")):
            with self.subTest(changed=changed):
                changed["evidence_id"] = "mesh:v2:" + routes.physical_leg_reuse_key(changed)
                self.assertFalse(
                    routes.validate_local_leg_evidence(
                        changed,
                        candidate=CANDIDATE,
                        destination=destination,
                        ingress=ingress,
                        current_inputs=self.current_inputs(),
                        policy=self.policy(),
                    )[0]
                )

    def test_contracts_reuse_physical_proof_but_bind_each_typed_owner_and_choose_shortest(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        evidence = self.accepted_evidence()
        other_candidate = dict(
            CANDIDATE,
            candidate_id="mission:Bastok:99:step-001:claim-01:candidate:amber-a",
            action_id="mission:Bastok:99:step-001:claim-01",
            group_id="mission:Bastok:99:step-001:claim-01:group:amber",
        )
        second_ingress = self.ingress(999)
        second_request = self.request(
            "leg-2",
            start={"x": 100.0, "z": 130.0, "y": -0.5},
        )
        second_response = _response(
            "leg-2",
            waypoints=[
                {"x": 100.0, "z": 130.0, "y": -0.5, "clearance": 1.5},
                {"x": 121.0, "z": 142.0, "y": -0.2, "clearance": 1.25},
                {"x": 142.0, "z": 154.0, "y": -0.076, "clearance": 1.25},
            ],
            waypoint_count=3,
            path_length=48.3757247968484,
        )
        second = routes.bind_local_leg_evidence(
            candidate=CANDIDATE,
            destination=destination,
            ingress=second_ingress,
            request=second_request,
            observation=routes.classify_probe_observation(
                second_request, second_response, self.policy()
            ),
            current_inputs=self.current_inputs(),
            required_transition_ids=(),
            policy=self.policy(),
        )
        contracts, unresolved = routes.build_route_contracts(
            candidates=(CANDIDATE, other_candidate),
            destinations=(destination,),
            ingresses=(ingress, second_ingress),
            evidence=(evidence, second),
            transition_definitions=(),
            transition_evidence=(),
            current_inputs=self.current_inputs(),
            policy=self.policy(),
        )
        self.assertEqual(unresolved, ())
        self.assertEqual(len(contracts), 4)
        self.assertEqual({row["candidate_id"] for row in contracts}, {CANDIDATE["candidate_id"], other_candidate["candidate_id"]})
        chosen = routes.select_shortest_contract(contracts, CANDIDATE["candidate_id"])
        self.assertEqual(chosen["local_leg"]["observations"]["path_length"], 48.3757247968484)
        self.assertEqual(chosen["candidate_id"], CANDIDATE["candidate_id"])
        self.assertEqual(chosen["action_id"], CANDIDATE["action_id"])
        tied = copy.deepcopy(contracts)
        for row in tied:
            row["local_leg"]["observations"]["path_length"] = 100.0
        expected_id = min(row["contract_id"] for row in tied if row["candidate_id"] == CANDIDATE["candidate_id"])
        self.assertEqual(routes.select_shortest_contract(tied, CANDIDATE["candidate_id"])["contract_id"], expected_id)
        shuffled = list(contracts)
        random.Random(7).shuffle(shuffled)
        self.assertEqual(
            routes.render_contracts_lua(contracts),
            routes.render_contracts_lua(shuffled),
        )

    def test_legacy_free_text_and_route_flags_never_authorize(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        legacy = dict(
            CANDIDATE,
            route_ready=True,
            route_evidence="navprobe:trust-me",
            confidence="proven",
            status="verified-navigation",
            evidence_level="live-proven",
            navigation_target={"destination_id": destination["destination_id"]},
            objective_destinations=[{"route_ready": True}],
        )
        contracts, unresolved = routes.build_route_contracts(
            candidates=(legacy,),
            destinations=(destination,),
            ingresses=(ingress,),
            evidence=(),
            transition_definitions=(),
            transition_evidence=(),
            current_inputs=self.current_inputs(),
            policy=self.policy(),
        )
        self.assertEqual(contracts, ())
        self.assertEqual(unresolved[0]["reason"], "missing-current-local-leg-evidence")

    def test_contract_derives_required_transition_from_trusted_registry_ownership(self) -> None:
        routes = self.routes()
        destination = self.destination()
        ingress = self.ingress()
        local_leg = self.accepted_evidence()
        transport_candidate = dict(
            CANDIDATE, transport_id="fixture-palborough-platform"
        )
        definition = {
            "transition_id": "fixture-palborough-platform:up",
            "base_id": "fixture-palborough-platform",
            "zone": 143,
            "direction": "up",
            "pre_anchor": {"x": 500.0, "z": 500.0, "y": -1.5},
            "post_anchor": {"x": 500.0, "z": 500.0, "y": -32.5},
            "interaction": {"kind": "automatic-platform", "identity": "fixture:platform:2"},
            "expected_live_state": "same-zone-floor-change-and-continuation",
            "timeout_seconds": 45,
            "cancellation": ["timeout", "player-left-zone", "destination-changed"],
            "required_transport_id": "fixture-palborough-platform",
            "required_destination_ids": [],
        }
        transition_inputs = {
            "policy_sha256": routes.policy_sha256(self.policy()),
            "transition_registry_sha256": TRANSITIONS_HASH,
            "mesh_sha256": MESH_HASH,
            "ffxinav_sha256": DLL_HASH,
            "destinations_sha256": DESTINATIONS_HASH,
            "graph_sha256": GRAPH_HASH,
        }
        proven = {
            "schema": 2,
            "transition_evidence_id": "",
            "transition_id": definition["transition_id"],
            "status": "transition-proven",
            "direction": "up",
            "zone": 143,
            "pre_anchor": copy.deepcopy(definition["pre_anchor"]),
            "post_anchor": copy.deepcopy(definition["post_anchor"]),
            "interaction": copy.deepcopy(definition["interaction"]),
            "observed_live_state": definition["expected_live_state"],
            "timeout_seconds": 45,
            "timeout_result": "bounded-success",
            "cancellation_observed": list(definition["cancellation"]),
            "trace": {"source": "fixture.log", "sha256": "6" * 64},
            "inputs": transition_inputs,
        }
        proven["transition_evidence_id"] = routes.transition_evidence_id(proven)

        def build(rows: tuple[dict, ...]):
            return routes.build_route_contracts(
                candidates=(transport_candidate,), destinations=(destination,), ingresses=(ingress,),
                evidence=(local_leg,), transition_definitions=(definition,),
                transition_evidence=rows, current_inputs=self.current_inputs(),
                policy=self.policy(),
            )

        for label, rows in (
            ("missing", ()),
            ("rejected", (dict(proven, status="rejected"),)),
            ("reverse", (dict(proven, direction="down"),)),
            ("stale", (dict(proven, inputs=dict(transition_inputs, mesh_sha256="f" * 64)),)),
        ):
            with self.subTest(label=label):
                contracts, unresolved = build(rows)
                self.assertEqual(contracts, ())
                self.assertEqual(unresolved[0]["reason"], "missing-current-transition-evidence")
        contracts, unresolved = build((proven,))
        self.assertEqual(unresolved, ())
        self.assertEqual(len(contracts), 1)
        self.assertEqual(contracts[0]["transition_evidence_ids"], (proven["transition_evidence_id"],))
        self.assertEqual(contracts[0]["required_transition_ids"], (definition["transition_id"],))
        self.assertEqual(local_leg["required_transition_ids"], ())

    def test_shuffled_inputs_are_byte_stable_and_one_worker_failure_is_local(self) -> None:
        routes = self.routes()
        requests = [self.request("a"), self.request("b"), self.request("c")]
        observations = [_response("a"), _response("b", status="tool-error", waypoint_count=0, waypoints=[]), _response("c")]
        first = routes.render_probe_results(requests, observations, self.policy())
        random.Random(42).shuffle(requests)
        random.Random(91).shuffle(observations)
        second = routes.render_probe_results(requests, observations, self.policy())
        self.assertEqual(first, second)
        rows = [json.loads(line) for line in first.decode("utf-8").splitlines()]
        self.assertEqual(
            [row["request_id"] for row in rows if row["reason"] == "tool-error"],
            ["b"],
        )
        self.assertEqual(
            [row["status"] for row in rows if row["request_id"] == "b"],
            ["rejected"],
        )


class CliRouteWorkflowTests(RouteEvidenceTestCase):
    def leg(
        self,
        request_id: str = "leg-1",
        *,
        ingress_id: int = 947466874,
        **request_updates: object,
    ) -> dict:
        ingress = self.ingress(ingress_id)
        if ingress_id == 999:
            request_updates.setdefault("start", {"x": 100.0, "z": 130.0, "y": -0.5})
        return {
            "candidate": copy.deepcopy(CANDIDATE),
            "destination": self.destination(),
            "ingress": ingress,
            "request": self.request(request_id, **request_updates),
            "required_transition_ids": (),
        }

    def evidence(self) -> dict:
        routes = self.routes()
        leg = self.leg()
        return routes.bind_local_leg_evidence(
            candidate=leg["candidate"], destination=leg["destination"],
            ingress=leg["ingress"], request=leg["request"],
            observation=routes.classify_probe_observation(
                leg["request"], _response(), self.policy()
            ),
            current_inputs=self.current_inputs(), required_transition_ids=(),
            policy=self.policy(),
        )

    def test_cli_exposes_routes_refresh_explicit_dependency_root_and_runtime_gates(self) -> None:
        cli = importlib.import_module("tools.objective_guides.cli")
        parsed = cli._parser().parse_args(
            [
                "routes", "--refresh", "--third-party-root", r"C:\fixture\third_party",
                "--update-runtime-pin", r"C:\fixture\reader.lua",
            ]
        )
        self.assertEqual(parsed.command, "routes")
        self.assertTrue(parsed.refresh)
        self.assertEqual(parsed.third_party_root, Path(r"C:\fixture\third_party"))
        self.assertEqual(parsed.update_runtime_pin, Path(r"C:\fixture\reader.lua"))
        runtime = cli._parser().parse_args(["build", "--offline", "--runtime-ready"])
        self.assertTrue(runtime.offline)
        self.assertTrue(runtime.runtime_ready)

    def test_routes_refresh_reuses_pinned_sources_and_never_opens_mediawiki(self) -> None:
        cli = importlib.import_module("tools.objective_guides.cli")
        route_refresh, source_refresh, source_offline = cli._refresh_modes(
            command="routes", refresh=True, offline=False
        )
        self.assertTrue(route_refresh)
        self.assertFalse(source_refresh)
        self.assertTrue(source_offline)
        original_client = cli.MediaWikiClient
        cli.MediaWikiClient = lambda *_args, **_kwargs: (_ for _ in ()).throw(
            AssertionError("routes --refresh attempted MediaWiki access")
        )
        try:
            with tempfile.TemporaryDirectory() as temporary:
                with self.assertRaisesRegex(cli.MediaWikiError, "snapshot is missing"):
                    cli._source_pages(
                        (),
                        cache_root=Path(temporary),
                        offline=source_offline,
                        refresh=source_refresh,
                        sites=(next(iter(cli.SITE_CONFIG)),),
                    )
        finally:
            cli.MediaWikiClient = original_client

    def test_cli_route_dependency_root_rejects_junction_before_resolution(self) -> None:
        if os.name != "nt":
            self.skipTest("Windows junction semantics are required.")
        cli = importlib.import_module("tools.objective_guides.cli")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            real = root / "real-third-party"
            real.mkdir()
            alias = root / "third-party-alias"
            junction = subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(alias), str(real)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(junction.returncode, 0, junction.stderr or junction.stdout)
            with self.assertRaises(cli.route_evidence.RouteEvidenceError):
                cli._route_dependency_root(root, alias)

    def test_cli_route_build_consumes_in_memory_task3_candidates_and_writes_review_only_artifacts(self) -> None:
        cli = importlib.import_module("tools.objective_guides.cli")
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / "repo"
            guide_data = repo / "data" / "mission-quest-guides"
            addon_data = repo / "ashita" / "addons" / "accessxi_reader" / "data"
            guide_data.mkdir(parents=True)
            addon_data.mkdir(parents=True)
            (guide_data / "route-proof-policy.json").write_text(
                json.dumps(POLICY_LITERAL, ensure_ascii=False, sort_keys=True) + "\n",
                encoding="utf-8",
                newline="\n",
            )
            (guide_data / "route-transitions.json").write_text(
                '{"schema_version":2,"transitions":[]}\n', encoding="utf-8", newline="\n"
            )
            (guide_data / "route-transition-evidence-v2.jsonl").write_bytes(b"")
            (guide_data / "route-evidence-v2.jsonl").write_bytes(b"")
            (addon_data / "ffxi-nav-destinations.tsv").write_bytes(DESTINATION_TSV)
            (addon_data / "ffxi-nav-zoneline-graph.tsv").write_bytes(GRAPH_TSV)
            third_party = repo / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            mesh = third_party / "xiNavmeshes" / "Palborough_Mines.nav"
            dll.parent.mkdir(parents=True)
            mesh.parent.mkdir(parents=True)
            dll.write_bytes(b"fixture dll")
            mesh.write_bytes(b"fixture mesh")

            result = cli._build_route_artifacts(
                repo_root=repo,
                data_root=guide_data,
                route_inputs={"candidates": (copy.deepcopy(CANDIDATE),)},
                third_party_root=third_party,
                refresh=False,
                runtime_ready=False,
                update_runtime_pin_path=None,
            )
            self.assertEqual(result["contract_count"], 0)
            self.assertEqual(result["transition_count"], 0)
            self.assertEqual(result["unresolved_count"], 1)
            rows = cli.route_evidence.load_jsonl(
                guide_data / "route-evidence-v2.jsonl"
            )
            self.assertEqual(len(rows), 2)
            self.assertTrue(all(row["status"] == "rejected" for row in rows))
            self.assertTrue(
                (repo / "ashita" / "addons" / "accessxi_reader" / "data" /
                 "mission-quest-route-manifest.tsv").is_file()
            )

    def test_offline_reuses_only_exact_evidence_without_probe_and_keeps_stale_review_rows(self) -> None:
        routes = self.routes()
        changed = self.leg(mesh_sha256="f" * 64)
        current = self.current_inputs()
        current["mesh_sha256"] = "f" * 64
        probe_called = False

        def forbidden_probe(_requests):
            nonlocal probe_called
            probe_called = True
            raise AssertionError("offline workflow invoked the native probe")

        result = routes.execute_route_evidence_workflow(
            legs=(changed,), existing_evidence=(self.evidence(),),
            current_inputs=current, policy=self.policy(),
            refresh=False, offline=True, probe_runner=forbidden_probe,
        )
        self.assertFalse(probe_called)
        self.assertEqual(result["accepted"], ())
        self.assertEqual(
            [(row["request_id"], row["reason"]) for row in result["review"]],
            [("leg-1", "stale-mesh")],
        )

    def test_refresh_probes_only_changed_hash_keys_and_persists_rejections_for_review(self) -> None:
        routes = self.routes()
        changed = self.leg(mesh_sha256="f" * 64)
        current = self.current_inputs()
        current["mesh_sha256"] = "f" * 64
        seen = []

        def probe_runner(requests):
            seen.extend(request["request_id"] for request in requests)
            return tuple(
                _response(
                    request["request_id"], status="no-exact-path",
                    waypoint_count=0, waypoints=[], path_length=0.0,
                    mesh_sha256="f" * 64,
                    mesh_sha256_before="f" * 64,
                    mesh_sha256_after="f" * 64,
                )
                for request in requests
            )

        result = routes.execute_route_evidence_workflow(
            legs=(changed,), existing_evidence=(self.evidence(),),
            current_inputs=current, policy=self.policy(),
            refresh=True, offline=False, probe_runner=probe_runner,
        )
        self.assertEqual(seen, ["leg-1"])
        self.assertEqual(result["accepted"], ())
        self.assertEqual(
            {(row["request_id"], row["reason"]) for row in result["review"]},
            {("leg-1", "stale-mesh"), ("leg-1", "no-exact-path")},
        )
        rendered = routes.render_route_evidence_jsonl(
            (*result["accepted"], *result["review"])
        )
        self.assertIn(b'"request_id":"leg-1"', rendered)
        self.assertIn(b'"status":"rejected"', rendered)

    def test_refresh_rejects_a_mesh_path_crossing_a_trusted_transition_corridor(self) -> None:
        routes = self.routes()
        leg = self.leg()
        corridor = {
            "transition_id": "fixture-palborough-lift:up",
            "zone": 143,
            "pre_anchor": {"x": 182.401, "z": 64.408, "y": 0.902},
            "post_anchor": {"x": 182.401, "z": 64.408, "y": -32.207},
        }
        waypoints = [
            {"x": 4.923, "z": 59.551, "y": -2.383, "clearance": 1.5},
            {"x": 60.0, "z": 60.0, "y": -3.0, "clearance": 1.2},
            {"x": 120.0, "z": 62.0, "y": -8.0, "clearance": 1.2},
            {"x": 182.2, "z": 64.2, "y": -15.0, "clearance": 1.2},
            {"x": 160.0, "z": 100.0, "y": -10.0, "clearance": 1.2},
            {"x": 142.0, "z": 154.0, "y": -0.076, "clearance": 1.25},
        ]

        def probe_runner(requests):
            return (
                _response(
                    requests[0]["request_id"],
                    waypoints=waypoints,
                    waypoint_count=len(waypoints),
                    minimum_waypoint_clearance=1.2,
                    path_length=routes.polyline_length(waypoints),
                ),
            )

        result = routes.execute_route_evidence_workflow(
            legs=(leg,),
            existing_evidence=(),
            current_inputs=self.current_inputs(),
            policy=self.policy(),
            transition_definitions=(corridor,),
            refresh=True,
            offline=False,
            probe_runner=probe_runner,
        )
        self.assertEqual(result["accepted"], ())
        self.assertEqual(
            [(row["request_id"], row["reason"]) for row in result["review"]],
            [("leg-1", "requires-transition")],
        )

        classified_without_registry = routes.classify_probe_observation(
            leg["request"], probe_runner((leg["request"],))[0], self.policy()
        )
        self.assertEqual(classified_without_registry["status"], "mesh-proven")
        formerly_bound = routes.bind_local_leg_evidence(
            candidate=leg["candidate"],
            destination=leg["destination"],
            ingress=leg["ingress"],
            request=leg["request"],
            observation=classified_without_registry,
            current_inputs=self.current_inputs(),
            required_transition_ids=(),
            policy=self.policy(),
        )
        self.assertFalse(
            routes.validate_local_leg_evidence(
                formerly_bound,
                candidate=leg["candidate"],
                destination=leg["destination"],
                ingress=leg["ingress"],
                current_inputs=self.current_inputs(),
                policy=self.policy(),
                transition_definitions=(corridor,),
            )[0]
        )
        contracts, unresolved = routes.build_route_contracts(
            candidates=(leg["candidate"],),
            destinations=(leg["destination"],),
            ingresses=(leg["ingress"],),
            evidence=(formerly_bound,),
            transition_definitions=(corridor,),
            transition_evidence=(),
            current_inputs=self.current_inputs(),
            policy=self.policy(),
        )
        self.assertEqual(contracts, ())
        self.assertEqual(
            [(row["candidate_id"], row["reason"]) for row in unresolved],
            [(leg["candidate"]["candidate_id"], "missing-current-local-leg-evidence")],
        )


class TransitionEvidenceTests(RouteEvidenceTestCase):
    def definition(self) -> dict:
        return {
            "transition_id": "fixture-elevator:up",
            "base_id": "fixture-elevator",
            "zone": 237,
            "direction": "up",
            "pre_anchor": {"x": -58.850, "z": -11.914, "y": 0.0},
            "post_anchor": {"x": -53.126, "z": -11.875, "y": -12.098},
            "interaction": {"kind": "automatic-platform", "identity": "fixture:platform:1"},
            "expected_live_state": "same-zone-floor-change-and-continuation",
            "timeout_seconds": 45,
            "cancellation": ["timeout", "player-left-zone", "destination-changed"],
        }

    def observed(self) -> dict:
        routes = self.routes()
        definition = self.definition()
        row = {
            "schema": 2,
            "transition_evidence_id": "",
            "transition_id": definition["transition_id"],
            "status": "transition-proven",
            "direction": "up",
            "zone": 237,
            "pre_anchor": copy.deepcopy(definition["pre_anchor"]),
            "post_anchor": copy.deepcopy(definition["post_anchor"]),
            "interaction": copy.deepcopy(definition["interaction"]),
            "observed_live_state": definition["expected_live_state"],
            "timeout_seconds": 45,
            "timeout_result": "bounded-success",
            "cancellation_observed": ["timeout", "player-left-zone", "destination-changed"],
            "trace": {"source": "ffxi-menu-reader.log", "sha256": "6" * 64},
            "inputs": {
                "policy_sha256": routes.policy_sha256(self.policy()),
                "transition_registry_sha256": TRANSITIONS_HASH,
                "mesh_sha256": "2" * 64,
                "ffxinav_sha256": DLL_HASH,
                "destinations_sha256": DESTINATIONS_HASH,
                "graph_sha256": GRAPH_HASH,
            },
        }
        row["transition_evidence_id"] = routes.transition_evidence_id(row)
        return row

    def test_transition_proof_binds_direction_anchors_interaction_state_timeout_and_hashes(self) -> None:
        routes = self.routes()
        definition = self.definition()
        observed = self.observed()
        current = copy.deepcopy(observed["inputs"])
        self.assertEqual(routes.validate_transition_evidence(definition, observed, current), (True, "transition-proven"))
        mutations = {
            "reverse-only": ("direction", "down"),
            "wrong-pre": ("pre_anchor", {"x": -53.126, "z": -11.875, "y": -12.098}),
            "wrong-post": ("post_anchor", {"x": -58.850, "z": -11.914, "y": 0.0}),
            "wrong-interaction": ("interaction", {"kind": "lever", "identity": "other"}),
            "wrong-post-state": ("observed_live_state", "platform-moved"),
            "timeout": ("timeout_result", "timed-out"),
        }
        for reason, (field, value) in mutations.items():
            with self.subTest(reason=reason):
                changed = copy.deepcopy(observed)
                changed[field] = value
                self.assertFalse(routes.validate_transition_evidence(definition, changed, current)[0])
        for field in current:
            with self.subTest(stale_hash=field):
                changed_current = copy.deepcopy(current)
                changed_current[field] = "f" * 64
                self.assertFalse(routes.validate_transition_evidence(definition, observed, changed_current)[0])

    def test_transition_contract_selection_uses_independent_current_inputs(self) -> None:
        routes = self.routes()
        definition = self.definition()
        observed = self.observed()
        current = copy.deepcopy(observed["inputs"])
        self.assertEqual(
            routes.current_transition_contracts(
                (definition,), (observed,), self.policy(), current_inputs=current
            ),
            (definition,),
        )
        stale = copy.deepcopy(observed)
        stale["inputs"] = {key: "f" * 64 for key in stale["inputs"]}
        self.assertEqual(
            routes.current_transition_contracts(
                (definition,), (stale,), self.policy(), current_inputs=current
            ),
            (),
        )

    def test_transition_evidence_requires_exact_schema_identity_and_cancellation_sequence(self) -> None:
        routes = self.routes()
        definition = self.definition()
        observed = self.observed()
        current = copy.deepcopy(observed["inputs"])
        mutations = []
        missing_id = copy.deepcopy(observed)
        missing_id.pop("transition_evidence_id")
        mutations.append(missing_id)
        mutations.extend(
            (
                dict(observed, transition_evidence_id=""),
                dict(observed, transition_evidence_id="transition:v2:" + "f" * 64),
                dict(observed, schema=999),
                dict(observed, invented="junk"),
                dict(
                    observed,
                    cancellation_observed=[
                        *observed["cancellation_observed"],
                        observed["cancellation_observed"][0],
                    ],
                ),
                dict(
                    observed,
                    cancellation_observed=list(
                        reversed(observed["cancellation_observed"])
                    ),
                ),
            )
        )
        for changed in mutations:
            with self.subTest(changed=changed):
                self.assertFalse(
                    routes.validate_transition_evidence(
                        definition, changed, current
                    )[0]
                )

    def test_observed_floor_change_without_timeout_and_cancel_evidence_stays_blocked(self) -> None:
        routes = self.routes()
        observed = self.observed()
        observed["status"] = "observed-only"
        observed["timeout_result"] = "not-observed"
        observed["cancellation_observed"] = []
        observed["transition_evidence_id"] = routes.transition_evidence_id(observed)
        accepted, reason = routes.validate_transition_evidence(
            self.definition(), observed, observed["inputs"]
        )
        self.assertFalse(accepted)
        self.assertEqual(reason, "transition-timeout-policy-unproven")
        substituted = copy.deepcopy(observed)
        substituted["status"] = "transition-proven"
        substituted["timeout_result"] = "bounded-success"
        substituted["inputs"]["destinations_sha256"] = REAL_DESTINATIONS_HASH
        self.assertFalse(
            routes.validate_transition_evidence(
                self.definition(), substituted, observed["inputs"]
            )[0]
        )
        incidental = copy.deepcopy(self.definition())
        incidental["interaction"] = {"kind": "npc", "identity": "Helmut"}
        self.assertFalse(
            routes.validate_transition_evidence(
                incidental, self.observed(), self.observed()["inputs"]
            )[0]
        )

    def test_checked_transition_registry_retains_traces_but_authorizes_no_current_direction(self) -> None:
        routes = self.routes()
        definitions = routes.load_transition_definitions(
            REPO_ROOT / "data" / "mission-quest-guides" / "route-transitions.json"
        )
        evidence = routes.load_jsonl(
            REPO_ROOT / "data" / "mission-quest-guides" / "route-transition-evidence-v2.jsonl"
        )
        self.assertEqual(
            {row["transition_id"] for row in definitions},
            {
                "metalworks-south-elevator:up",
                "metalworks-south-elevator:down",
                "metalworks-north-elevator:up",
                "metalworks-north-elevator:down",
                "palborough-mines-lift:up",
                "palborough-mines-lift:down",
            },
        )
        self.assertEqual(
            {(row["transition_id"], row["status"], row["reason"]) for row in evidence},
            {
                (
                    "metalworks-south-elevator:up",
                    "rejected",
                    "missing-policy-bound-timeout-evidence",
                ),
                (
                    "metalworks-south-elevator:down",
                    "rejected",
                    "missing-policy-bound-timeout-evidence",
                ),
            },
        )
        by_id = {row["transition_id"]: row for row in evidence}
        self.assertEqual(
            by_id["metalworks-south-elevator:up"]["trace"]["sha256"],
            "6748f32cd43ba47020d8635bffbab90627683e8d1ec0a947d1d884ee2c0be331",
        )
        self.assertEqual(
            by_id["metalworks-south-elevator:down"]["trace"]["sha256"],
            "fe7bd807fd9b4797c6701131d29bfa84030e90ff13c5744ed2a6f909c1d89179",
        )
        self.assertNotIn("Helmut", json.dumps(definitions + evidence))
        self.assertNotIn("Remus", json.dumps(definitions + evidence))
        self.assertEqual(
            routes.current_transition_contracts(
                definitions,
                evidence,
                self.policy(),
                current_inputs=self.observed()["inputs"],
            ),
            (),
        )

    def test_raw_mesh_leg_cannot_bypass_a_declared_transition_corridor(self) -> None:
        routes = self.routes()
        request = self.request()
        response = _response(
            waypoints=[
                {"x": 4.923, "z": 59.551, "y": -2.383, "clearance": 1.5},
                {"x": 60.0, "z": 60.0, "y": 0.0, "clearance": 1.2},
                {"x": 120.0, "z": 64.0, "y": 0.0, "clearance": 1.2},
                {"x": 182.401, "z": 64.408, "y": 0.902, "clearance": 1.2},
                {"x": 182.401, "z": 64.408, "y": -32.207, "clearance": 1.2},
                {"x": 150.0, "z": 100.0, "y": -20.0, "clearance": 1.2},
                {"x": 142.0, "z": 154.0, "y": -0.076, "clearance": 1.25},
            ],
            waypoint_count=7,
            start_clearance=1.5,
            end_clearance=1.25,
            minimum_waypoint_clearance=1.2,
            path_length=318.5481324227196,
        )
        corridor = {
            "transition_id": "palborough-mines-lift:up",
            "zone": 143,
            "pre_anchor": {"x": 182.401, "z": 64.408, "y": 0.902},
            "post_anchor": {"x": 182.401, "z": 64.408, "y": -32.207},
        }
        result = routes.classify_probe_observation(
            request, response, self.policy(), declared_transitions=(corridor,)
        )
        self.assertEqual((result["status"], result["reason"]), ("rejected", "requires-transition"))
        reverse = dict(corridor, pre_anchor=corridor["post_anchor"], post_anchor=corridor["pre_anchor"])
        reverse_result = routes.classify_probe_observation(
            request, response, self.policy(), declared_transitions=(reverse,)
        )
        self.assertEqual(reverse_result["status"], "rejected")
        crossing_without_anchors = copy.deepcopy(response)
        crossing_without_anchors["waypoints"] = [
            {"x": 4.923, "z": 59.551, "y": -2.383, "clearance": 1.5},
            {"x": 60.0, "z": 60.0, "y": -3.0, "clearance": 1.2},
            {"x": 120.0, "z": 62.0, "y": -8.0, "clearance": 1.2},
            {"x": 182.2, "z": 64.2, "y": -15.0, "clearance": 1.2},
            {"x": 160.0, "z": 100.0, "y": -10.0, "clearance": 1.2},
            {"x": 142.0, "z": 154.0, "y": -0.076, "clearance": 1.25},
        ]
        crossing_without_anchors["waypoint_count"] = 6
        crossing_without_anchors["path_length"] = routes.polyline_length(
            crossing_without_anchors["waypoints"]
        )
        crossing_result = routes.classify_probe_observation(
            request, crossing_without_anchors, self.policy(), declared_transitions=(corridor,)
        )
        self.assertEqual((crossing_result["status"], crossing_result["reason"]), ("rejected", "requires-transition"))


class RuntimeManifestTests(RouteEvidenceTestCase):
    def artifact_fixture(self, root: Path) -> list[dict]:
        sources = root / "sources"
        sources.mkdir()
        rows = []
        for relative_path, source_name, content, kind in (
            ("modules/mission_quest_route_policy.lua", "policy.lua", b"return { revision = 'v2' }\n", "policy"),
            ("modules/mission_quest_route_transitions.lua", "transitions.lua", b"return { transitions = {} }\n", "transitions"),
            ("modules/mission_quest_route_contracts.lua", "contracts.lua", b"return { contracts = {} }\n", "contracts"),
            ("data/ffxi-nav-destinations.tsv", "destinations.tsv", b"fixture destinations\n", "destinations"),
            ("data/ffxi-nav-zoneline-graph.tsv", "graph.tsv", b"fixture graph\n", "graph"),
            ("third_party/FFXI-NavMesh-Builder/FFXINAV.dll", "FFXINAV.dll", b"fixture dll", "ffxinav"),
            ("third_party/xiNavmeshes/Palborough_Mines.nav", "Palborough_Mines.nav", b"fixture mesh", "mesh"),
        ):
            source_path = sources / source_name
            source_path.write_bytes(content)
            row = {"runtime_path": relative_path, "source_path": source_path, "kind": kind}
            if kind == "mesh":
                row.update({"zone": 143, "mesh_name": "Palborough_Mines.nav"})
            rows.append(row)
        return rows

    def test_manifest_maps_repo_sources_to_addon_relative_runtime_shape_and_verifies_staged_bytes(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.artifact_fixture(root)
            expected = tuple(row["runtime_path"] for row in artifacts)
            manifest, digest = routes.render_runtime_manifest(
                artifacts,
                required_runtime_paths=expected,
                manifest_relative_path="data/mission-quest-route-manifest.tsv",
                runtime_ready=False,
                referenced_mesh_names=("Palborough_Mines.nav",),
            )
            self.assertFalse(manifest.startswith(b"\xef\xbb\xbf"))
            self.assertTrue(manifest.endswith(b"\n"))
            self.assertEqual(digest, hashlib.sha256(manifest).hexdigest())
            self.assertNotIn(b"mission-quest-route-manifest.tsv", manifest)
            addon_root = root / "addon"
            for row in artifacts:
                target = addon_root.joinpath(*row["runtime_path"].split("/"))
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(Path(row["source_path"]).read_bytes())
            verified = routes.verify_runtime_manifest(
                manifest,
                addon_root=addon_root,
                expected_root_digest=digest,
                required_runtime_paths=expected,
                runtime_ready=False,
            )
            self.assertEqual(verified["root_digest"], digest)
            first_child = addon_root.joinpath(*artifacts[0]["runtime_path"].split("/"))
            first_child.write_bytes(b"coordinated drift\n")
            with self.assertRaises(routes.RouteEvidenceError):
                routes.verify_runtime_manifest(
                    manifest,
                    addon_root=addon_root,
                    expected_root_digest=digest,
                    required_runtime_paths=expected,
                    runtime_ready=False,
                )

    def test_manifest_internal_required_set_rejects_coordinated_child_or_mesh_omission(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.artifact_fixture(root)
            for missing_path in (
                "modules/mission_quest_route_policy.lua",
                "modules/mission_quest_route_transitions.lua",
                "modules/mission_quest_route_contracts.lua",
                "third_party/FFXI-NavMesh-Builder/FFXINAV.dll",
            ):
                retained = tuple(row for row in artifacts if row["runtime_path"] != missing_path)
                caller_required = tuple(row["runtime_path"] for row in retained)
                with self.subTest(missing_path=missing_path), self.assertRaises(routes.RouteEvidenceError):
                    routes.render_runtime_manifest(
                        retained,
                        required_runtime_paths=caller_required,
                        manifest_relative_path="data/mission-quest-route-manifest.tsv",
                        runtime_ready=False,
                        referenced_mesh_names=("Palborough_Mines.nav",),
                    )
            retained = tuple(row for row in artifacts if row["kind"] != "mesh")
            with self.assertRaises(routes.RouteEvidenceError):
                routes.render_runtime_manifest(
                    retained,
                    required_runtime_paths=tuple(row["runtime_path"] for row in retained),
                    manifest_relative_path="data/mission-quest-route-manifest.tsv",
                    runtime_ready=False,
                    referenced_mesh_names=("Palborough_Mines.nav",),
                )

    def test_manifest_rejects_mesh_name_or_zone_mapping_mismatch(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            mesh = root / "Palborough_Mines.nav"
            mesh.write_bytes(b"fixture mesh")
            valid = {
                "runtime_path": "third_party/xiNavmeshes/Palborough_Mines.nav",
                "source_path": mesh,
                "kind": "mesh",
                "zone": 143,
                "mesh_name": "Palborough_Mines.nav",
            }
            self.assertEqual(
                routes.validate_mesh_artifact(
                    valid, zone_mesh_names={143: "Palborough_Mines.nav"}
                )["zone"],
                143,
            )
            for changed in (
                dict(valid, mesh_name="Metalworks.nav"),
                dict(valid, zone=237),
                dict(valid, runtime_path="third_party/xiNavmeshes/Metalworks.nav"),
            ):
                with self.subTest(changed=changed), self.assertRaises(routes.RouteEvidenceError):
                    routes.validate_mesh_artifact(
                        changed, zone_mesh_names={143: "Palborough_Mines.nav"}
                    )

    def test_manifest_rejects_windows_alias_traversal_ads_controls_and_case_duplicates(self) -> None:
        routes = self.routes()
        invalid_paths = (
            "C:\\rooted\\file",
            "C:drive-relative",
            "\\\\server\\share\\file",
            "/rooted/file",
            "modules/../escape.lua",
            "modules\\..\\escape.lua",
            "modules/mixed\\..\\escape.lua",
            "modules/file.lua:stream",
            "modules/file\tname.lua",
            "modules/file\nname.lua",
        )
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "file"
            source.write_bytes(b"x")
            for runtime_path in invalid_paths:
                with self.subTest(runtime_path=runtime_path), self.assertRaises(routes.RouteEvidenceError):
                    routes.render_runtime_manifest(
                        ({"runtime_path": runtime_path, "source_path": source, "kind": "fixture"},),
                        required_runtime_paths=(runtime_path,),
                        manifest_relative_path="data/mission-quest-route-manifest.tsv",
                        runtime_ready=False,
                    )
            with self.assertRaises(routes.RouteEvidenceError):
                routes.render_runtime_manifest(
                    (
                        {"runtime_path": "Modules/A.lua", "source_path": source, "kind": "fixture"},
                        {"runtime_path": "modules/a.lua", "source_path": source, "kind": "fixture"},
                    ),
                    required_runtime_paths=("Modules/A.lua", "modules/a.lua"),
                    manifest_relative_path="data/mission-quest-route-manifest.tsv",
                    runtime_ready=False,
                )

    def test_manifest_requires_exact_child_set_and_rejects_self_extras_and_bad_digests(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "file"
            source.write_bytes(b"x")
            artifact = {"runtime_path": "modules/a.lua", "source_path": source, "kind": "fixture"}
            cases = (
                ((artifact,), ("modules/a.lua", "modules/missing.lua")),
                ((artifact,), ()),
                ((dict(artifact, runtime_path="data/mission-quest-route-manifest.tsv"),), ("data/mission-quest-route-manifest.tsv",)),
                ((dict(artifact, sha256="ABC"),), ("modules/a.lua",)),
            )
            for artifacts, required in cases:
                with self.subTest(required=required), self.assertRaises(routes.RouteEvidenceError):
                    routes.render_runtime_manifest(
                        artifacts,
                        required_runtime_paths=required,
                        manifest_relative_path="data/mission-quest-route-manifest.tsv",
                        runtime_ready=False,
                    )

    def test_manifest_parser_rejects_malformed_unsorted_and_duplicate_rows(self) -> None:
        routes = self.routes()
        header = b"relative_path\tsha256\tkind\tzone\tmesh_name\n"
        valid_a = b"modules/a.lua\t" + (b"a" * 64) + b"\tmodule\t\t\n"
        valid_b = b"modules/b.lua\t" + (b"b" * 64) + b"\tmodule\t\t\n"
        malformed = (
            header + valid_b + valid_a,
            header + valid_a + valid_a,
            header + b"modules/a.lua\tABC\tmodule\t\t\n",
            header + b"modules/a.lua\t" + (b"a" * 64) + b"\tmodule\textra\tfields\textra\n",
            b"\xef\xbb\xbf" + header + valid_a,
            header + valid_a.rstrip(b"\n"),
        )
        for payload in malformed:
            with self.subTest(payload=payload), self.assertRaises(routes.RouteEvidenceError):
                routes.parse_runtime_manifest(payload)

    def test_manifest_root_digest_and_every_child_byte_are_independent_trust_inputs(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.artifact_fixture(root)
            required = tuple(row["runtime_path"] for row in artifacts)
            manifest, digest = routes.render_runtime_manifest(
                artifacts, required_runtime_paths=required,
                manifest_relative_path="data/mission-quest-route-manifest.tsv", runtime_ready=False
            )
            changed_artifacts = copy.deepcopy(artifacts)
            Path(changed_artifacts[0]["source_path"]).write_bytes(b"changed policy\n")
            changed_manifest, changed_digest = routes.render_runtime_manifest(
                changed_artifacts, required_runtime_paths=required,
                manifest_relative_path="data/mission-quest-route-manifest.tsv", runtime_ready=False
            )
            self.assertNotEqual(manifest, changed_manifest)
            self.assertNotEqual(digest, changed_digest)
            with self.assertRaises(routes.RouteEvidenceError):
                routes.verify_manifest_root(changed_manifest, expected_root_digest=digest)

    @unittest.skipUnless(os.name == "nt", "junction containment is a Windows runtime contract")
    def test_manifest_verifier_rejects_a_junction_child_that_escapes_addon_root(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outside = root / "outside"
            outside.mkdir()
            (outside / "escaped.lua").write_bytes(b"return {}\n")
            source = root / "source.lua"
            source.write_bytes(b"return {}\n")
            artifact = {
                "runtime_path": "modules/escaped.lua",
                "source_path": source,
                "kind": "fixture",
            }
            manifest, digest = routes.render_runtime_manifest(
                (artifact,),
                required_runtime_paths=("modules/escaped.lua",),
                manifest_relative_path="data/mission-quest-route-manifest.tsv",
                runtime_ready=False,
                enforce_task4_required=False,
            )
            addon_root = root / "addon"
            addon_root.mkdir()
            result = subprocess.run(
                ["cmd", "/c", "mklink", "/J", str(addon_root / "modules"), str(outside)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            with self.assertRaises(routes.RouteEvidenceError):
                routes.verify_runtime_manifest(
                    manifest,
                    addon_root=addon_root,
                    expected_root_digest=digest,
                    required_runtime_paths=("modules/escaped.lua",),
                    runtime_ready=False,
                )

    def test_runtime_ready_requires_task5_runtime_child_and_task4_digest_stays_not_ready(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifacts = self.artifact_fixture(root)
            required = tuple(row["runtime_path"] for row in artifacts)
            manifest, digest = routes.render_runtime_manifest(
                artifacts, required_runtime_paths=required,
                manifest_relative_path="data/mission-quest-route-manifest.tsv", runtime_ready=False
            )
            self.assertFalse(routes.manifest_is_runtime_ready(manifest))
            with self.assertRaises(routes.RouteEvidenceError):
                routes.render_runtime_manifest(
                    artifacts, required_runtime_paths=required,
                    manifest_relative_path="data/mission-quest-route-manifest.tsv", runtime_ready=True
                )
            self.assertEqual(digest, hashlib.sha256(manifest).hexdigest())
            runtime = root / "sources" / "runtime.lua"
            runtime.write_bytes(b"return {}\n")
            runtime_artifacts = [
                *artifacts,
                {
                    "runtime_path": "modules/mission_quest_route_runtime.lua",
                    "source_path": runtime,
                    "kind": "runtime",
                },
            ]
            runtime_required = (*required, "modules/mission_quest_route_runtime.lua")
            runtime_manifest, _runtime_digest = routes.render_runtime_manifest(
                runtime_artifacts,
                required_runtime_paths=runtime_required,
                manifest_relative_path="data/mission-quest-route-manifest.tsv",
                runtime_ready=True,
            )
            self.assertTrue(routes.manifest_is_runtime_ready(runtime_manifest))

    def test_runtime_pin_update_requires_exactly_one_marker_and_is_atomic(self) -> None:
        routes = self.routes()
        digest = "a" * 64
        marker = "ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256"
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "reader.lua"
            for source in ("return {}\n", f'{marker} = "0"\n{marker} = "1"\n'):
                with self.subTest(source=source):
                    path.write_text(source, encoding="utf-8")
                    before = path.read_bytes()
                    with self.assertRaises(routes.RouteEvidenceError):
                        routes.update_runtime_pin(path, digest, marker=marker)
                    self.assertEqual(path.read_bytes(), before)
            path.write_text(f'local {marker} = "{'0' * 64}"\n', encoding="utf-8")
            routes.update_runtime_pin(path, digest, marker=marker)
            self.assertEqual(path.read_text(encoding="utf-8"), f'local {marker} = "{digest}"\n')


class RouteArtifactGenerationTests(RouteEvidenceTestCase):
    def test_zone_mesh_discovery_rejects_fuzzy_and_ambiguous_matches(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            third_party = Path(temporary) / "third_party"
            meshes = third_party / "xiNavmeshes"
            meshes.mkdir(parents=True)
            (meshes / "AB.nav").write_bytes(b"fuzzy")
            with self.assertRaises(routes.RouteEvidenceError):
                routes._discover_zone_mesh_name(999, "A-B", third_party)

            (meshes / "Test_Zone.nav").write_bytes(b"named")
            (meshes / "998.nav").write_bytes(b"numeric")
            with self.assertRaises(routes.RouteEvidenceError):
                routes._discover_zone_mesh_name(998, "Test Zone", third_party)

            (meshes / "998.nav").unlink()
            self.assertEqual(
                routes._discover_zone_mesh_name(998, "Test Zone", third_party),
                "Test_Zone.nav",
            )

    def test_reviewed_san_doria_zone_ids_bind_exact_mesh_basenames(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            third_party = Path(temporary) / "third_party"
            meshes = third_party / "xiNavmeshes"
            meshes.mkdir(parents=True)
            (meshes / "Southern_San_dOria.nav").write_bytes(b"south")
            (meshes / "Northern_San_dOria.nav").write_bytes(b"north")
            self.assertEqual(
                routes._discover_zone_mesh_name(
                    230, "Southern San d'Oria", third_party
                ),
                "Southern_San_dOria.nav",
            )
            self.assertEqual(
                routes._discover_zone_mesh_name(
                    231, "Northern San d'Oria", third_party
                ),
                "Northern_San_dOria.nav",
            )

    def test_route_batches_derive_exact_catalogue_rows_meshes_and_stable_requests(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            third_party = Path(temporary) / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            mesh = third_party / "xiNavmeshes" / "Palborough_Mines.nav"
            dll.parent.mkdir(parents=True)
            mesh.parent.mkdir(parents=True)
            dll.write_bytes(b"fixture dll")
            mesh.write_bytes(b"fixture mesh")
            first = routes.prepare_route_proof_batches(
                candidates=(copy.deepcopy(CANDIDATE),),
                catalogue=self.catalogue(),
                policy=self.policy(),
                third_party_root=third_party,
                transition_registry_sha256="1" * 64,
                transition_definitions=(),
            )
            second = routes.prepare_route_proof_batches(
                candidates=(copy.deepcopy(CANDIDATE),),
                catalogue=self.catalogue(),
                policy=self.policy(),
                third_party_root=third_party,
                transition_registry_sha256="1" * 64,
                transition_definitions=(),
            )
            self.assertEqual(first, second)
            self.assertEqual(first["unresolved"], ())
            self.assertEqual(tuple(first["legs_by_zone"]), ("143",))
            self.assertEqual(len(first["legs_by_zone"]["143"]), 2)
            current = first["current_inputs_by_zone"]["143"]
            self.assertEqual(current["mesh_name"], "Palborough_Mines.nav")
            self.assertEqual(current["mesh_sha256"], hashlib.sha256(b"fixture mesh").hexdigest())
            self.assertEqual(current["ffxinav_sha256"], hashlib.sha256(b"fixture dll").hexdigest())
            for leg in first["legs_by_zone"]["143"]:
                self.assertEqual(leg["request"]["op"], "FindPath")
                self.assertEqual(leg["request"]["zone"], 143)
                self.assertEqual(
                    leg["request"]["start"],
                    {
                        "x": leg["ingress"]["to_x"],
                        "z": leg["ingress"]["to_z"],
                        "y": leg["ingress"]["to_y"],
                    },
                )
                self.assertEqual(
                    leg["request"]["end"], {"x": 142.0, "z": 154.0, "y": -0.076}
                )

    def test_physical_request_and_proof_survive_owner_removal_or_reordering(self) -> None:
        routes = self.routes()
        other = dict(
            CANDIDATE,
            candidate_id="mission:Bastok:99:step-001:claim-01:candidate:amber",
            action_id="mission:Bastok:99:step-001:claim-01",
            group_id="mission:Bastok:99:step-001:claim-01:group:amber",
        )
        with tempfile.TemporaryDirectory() as temporary:
            third_party = Path(temporary) / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            mesh = third_party / "xiNavmeshes" / "Palborough_Mines.nav"
            dll.parent.mkdir(parents=True)
            mesh.parent.mkdir(parents=True)
            dll.write_bytes(b"fixture dll")
            mesh.write_bytes(b"fixture mesh")
            both = routes.prepare_route_proof_batches(
                candidates=(copy.deepcopy(CANDIDATE), other),
                catalogue=self.catalogue(), policy=self.policy(),
                third_party_root=third_party, transition_registry_sha256="1" * 64,
                transition_definitions=(),
            )
            remaining = routes.prepare_route_proof_batches(
                candidates=(other,), catalogue=self.catalogue(), policy=self.policy(),
                third_party_root=third_party, transition_registry_sha256="1" * 64,
                transition_definitions=(),
            )
        self.assertEqual(
            [leg["request"]["request_id"] for leg in both["legs_by_zone"]["143"]],
            [leg["request"]["request_id"] for leg in remaining["legs_by_zone"]["143"]],
        )
        old = routes.bind_local_leg_evidence(
            candidate=copy.deepcopy(CANDIDATE),
            destination=self.destination(),
            ingress=self.ingress(),
            request=self.request(),
            observation=routes.classify_probe_observation(
                self.request(), _response(), self.policy()
            ),
            current_inputs=self.current_inputs(),
            required_transition_ids=(),
            policy=self.policy(),
        )
        accepted, reason = routes.validate_local_leg_evidence(
            old,
            candidate=other,
            destination=self.destination(),
            ingress=self.ingress(),
            current_inputs=self.current_inputs(),
            policy=self.policy(),
        )
        self.assertTrue(accepted, reason)

    def test_offline_route_pipeline_keeps_every_candidate_nonroutable_without_current_proof(self) -> None:
        routes = self.routes()
        with tempfile.TemporaryDirectory() as temporary:
            third_party = Path(temporary) / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            mesh = third_party / "xiNavmeshes" / "Palborough_Mines.nav"
            dll.parent.mkdir(parents=True)
            mesh.parent.mkdir(parents=True)
            dll.write_bytes(b"fixture dll")
            mesh.write_bytes(b"fixture mesh")
            result = routes.execute_compiled_route_pipeline(
                candidates=(copy.deepcopy(CANDIDATE),),
                catalogue=self.catalogue(),
                policy=self.policy(),
                third_party_root=third_party,
                transition_registry_sha256="1" * 64,
                transition_definitions=(),
                transition_evidence=(),
                existing_evidence=(),
                refresh=False,
                offline=True,
                probe_runner=lambda _zone, _requests: (_ for _ in ()).throw(
                    AssertionError("offline pipeline invoked probe")
                ),
            )
            self.assertEqual(result["contracts"], ())
            self.assertEqual(result["accepted_evidence"], ())
            self.assertEqual(result["current_transitions"], ())
            self.assertEqual(
                [(row["candidate_id"], row["reason"]) for row in result["unresolved"]],
                [(CANDIDATE["candidate_id"], "missing-current-local-leg-evidence")],
            )
            self.assertEqual(
                {row["reason"] for row in result["review"]},
                {"missing-current-local-leg-evidence"},
            )

    def test_old_local_proof_becomes_one_review_row_when_zone_is_no_longer_preparable(self) -> None:
        routes = self.routes()
        old = routes.bind_local_leg_evidence(
            candidate=copy.deepcopy(CANDIDATE),
            destination=self.destination(),
            ingress=self.ingress(),
            request=self.request(),
            observation=routes.classify_probe_observation(
                self.request(), _response(), self.policy()
            ),
            current_inputs=self.current_inputs(),
            required_transition_ids=(),
            policy=self.policy(),
        )
        untested_graph = GRAPH_TSV.replace(b"\tproven\t", b"\tuntested\t")
        changed_catalogue = routes.load_route_catalogue_bytes(
            DESTINATION_TSV,
            untested_graph,
            destination_source="fixture/destinations.tsv",
            graph_source="fixture/untested-graph.tsv",
        )
        with tempfile.TemporaryDirectory() as temporary:
            third_party = Path(temporary) / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            mesh = third_party / "xiNavmeshes" / "Palborough_Mines.nav"
            dll.parent.mkdir(parents=True)
            mesh.parent.mkdir(parents=True)
            dll.write_bytes(b"fixture dll")
            mesh.write_bytes(b"fixture mesh")
            result = routes.execute_compiled_route_pipeline(
                candidates=(copy.deepcopy(CANDIDATE),),
                catalogue=changed_catalogue,
                policy=self.policy(),
                third_party_root=third_party,
                transition_registry_sha256="1" * 64,
                transition_definitions=(),
                transition_evidence=(),
                existing_evidence=(old,),
                refresh=False,
                offline=True,
                probe_runner=lambda _zone, _requests: (),
            )
        self.assertEqual(result["accepted_evidence"], ())
        reviews = [
            row for row in result["review"]
            if row.get("source_evidence_id") == old["evidence_id"]
        ]
        self.assertEqual(len(reviews), 1)
        self.assertEqual(reviews[0]["reason"], "no-proven-directed-ingress")

    def test_one_failed_zone_worker_rejects_only_its_requests_and_other_zone_continues(self) -> None:
        routes = self.routes()
        zone_144_destination = (
            b"144\tTest Beetle\t10.000\t0.000\t0.000\tenemy\tgenerated-lsb-enemy-camp\t"
            b"untested\t\tcamp:v1:144:test-beetle:cccccccccccccccccccc\t"
            b"lsb:mob_spawn_points:group:14:mobname:Test_Beetle\t17362956\t"
            b"complete-link-v1-h120-y24\n"
        )
        zone_144_ingress = (
            b"1000\t108\tTest Approach\tfixture\t-1.000\t0.000\t0.000\t144\t"
            b"Test Zone\tfixture\t0.000\t0.000\t0.000\tfixture-live-walk\tproven\t\n"
        )
        catalogue = routes.load_route_catalogue_bytes(
            DESTINATION_HEADER + DESTINATION_ROW + zone_144_destination,
            GRAPH_HEADER + INGRESS_ROW + zone_144_ingress,
            destination_source="fixture/two-zone-destinations.tsv",
            graph_source="fixture/two-zone-graph.tsv",
        )
        second_candidate = {
            **copy.deepcopy(CANDIDATE),
            "candidate_id": "mission:fixture:1:step-001:claim-01:candidate:test-beetle",
            "action_id": "mission:fixture:1:step-001:claim-01",
            "group_id": "mission:fixture:1:step-001:claim-01:group:test-beetle",
            "destination_id": "camp:v1:144:test-beetle:cccccccccccccccccccc",
            "zone": 144,
            "zone_name": "Test Zone",
            "target_name": "Test Beetle",
            "target_point": [10.0, 0.0, 0.0],
            "raw_identity": "lsb:mob_spawn_points:group:14:mobname:Test_Beetle",
            "raw_spawn_ids": [17362956],
        }
        with tempfile.TemporaryDirectory() as temporary:
            third_party = Path(temporary) / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            meshes = third_party / "xiNavmeshes"
            dll.parent.mkdir(parents=True)
            meshes.mkdir(parents=True)
            dll.write_bytes(b"fixture dll")
            (meshes / "Palborough_Mines.nav").write_bytes(b"zone 143 mesh")
            (meshes / "Test_Zone.nav").write_bytes(b"zone 144 mesh")

            def probe_runner(zone, requests):
                if zone == 143:
                    raise routes.RouteEvidenceError("worker 143 secret diagnostics")
                responses = []
                for request in requests:
                    start = request["start"]
                    end = request["end"]
                    waypoints = [
                        {**start, "clearance": 1.0},
                        {**end, "clearance": 1.0},
                    ]
                    responses.append(
                        _response(
                            request["request_id"],
                            waypoints=waypoints,
                            waypoint_count=2,
                            path_length=routes.polyline_length(waypoints),
                            minimum_waypoint_clearance=1.0,
                            mesh_relative_path=request["mesh_relative_path"],
                            mesh_sha256=request["mesh_sha256"],
                            mesh_sha256_before=request["mesh_sha256"],
                            mesh_sha256_after=request["mesh_sha256"],
                            ffxinav_sha256=request["ffxinav_sha256"],
                            ffxinav_sha256_before=request["ffxinav_sha256"],
                            ffxinav_sha256_after=request["ffxinav_sha256"],
                            loaded_dll_path=request["expected_loaded_dll_path"],
                            loaded_mesh_path=request["expected_loaded_mesh_path"],
                        )
                    )
                return tuple(responses)

            result = routes.execute_compiled_route_pipeline(
                candidates=(copy.deepcopy(CANDIDATE), second_candidate),
                catalogue=catalogue,
                policy=self.policy(),
                third_party_root=third_party,
                transition_registry_sha256="1" * 64,
                transition_definitions=(),
                transition_evidence=(),
                existing_evidence=(),
                refresh=True,
                offline=False,
                probe_runner=probe_runner,
            )
        self.assertEqual(len(result["accepted_evidence"]), 1)
        self.assertEqual(result["accepted_evidence"][0]["leg"]["zone"], 144)
        failed = [row for row in result["review"] if row["reason"] == "probe-worker-failed"]
        self.assertEqual(len(failed), 1)
        self.assertNotIn("secret", json.dumps(failed))
        self.assertEqual(len(result["contracts"]), 1)
        self.assertEqual(result["contracts"][0]["candidate_id"], second_candidate["candidate_id"])

    def test_contract_compilation_is_zone_scoped_and_never_promotes_without_current_inputs(self) -> None:
        routes = self.routes()
        candidate = copy.deepcopy(CANDIDATE)
        destination = self.destination()
        ingress = self.ingress()
        evidence = routes.bind_local_leg_evidence(
            candidate=candidate,
            destination=destination,
            ingress=ingress,
            request=self.request(),
            observation=routes.classify_probe_observation(
                self.request(), _response(), self.policy()
            ),
            current_inputs=self.current_inputs(),
            required_transition_ids=(),
            policy=self.policy(),
        )
        missing = routes.compile_route_contracts_by_zone(
            candidates=(candidate,),
            destinations=(destination,),
            ingresses=(ingress,),
            evidence=(evidence,),
            transition_definitions=(),
            transition_evidence=(),
            current_inputs_by_zone={},
            policy=self.policy(),
        )
        self.assertEqual(missing["contracts"], ())
        self.assertEqual(missing["unresolved"][0]["reason"], "zone-proof-inputs-unavailable")
        compiled = routes.compile_route_contracts_by_zone(
            candidates=(candidate,),
            destinations=(destination,),
            ingresses=(ingress,),
            evidence=(evidence,),
            transition_definitions=(),
            transition_evidence=(),
            current_inputs_by_zone={"143": self.current_inputs()},
            policy=self.policy(),
        )
        self.assertEqual(len(compiled["contracts"]), 1)
        self.assertEqual(compiled["unresolved"], ())
        self.assertTrue(compiled["contracts"][0]["route_ready"])

    def test_checked_task4_artifacts_are_deterministic_empty_and_not_runtime_ready(self) -> None:
        routes = self.routes()
        policy = self.policy()
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / "repo"
            addon = repo / "ashita" / "addons" / "accessxi_reader"
            module_root = addon / "modules"
            addon_data = addon / "data"
            module_root.mkdir(parents=True)
            addon_data.mkdir()
            (addon_data / "ffxi-nav-destinations.tsv").write_bytes(DESTINATION_TSV)
            (addon_data / "ffxi-nav-zoneline-graph.tsv").write_bytes(GRAPH_TSV)
            third_party = repo / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            dll.parent.mkdir(parents=True)
            dll.write_bytes(b"fixture dll")
            reader = addon / "accessxi_reader.lua"
            reader.write_text("return {}\n", encoding="utf-8", newline="\n")
            before_reader = reader.read_bytes()

            first = routes.write_route_runtime_artifacts(
                repo_root=repo,
                third_party_root=third_party,
                policy=policy,
                contracts=(),
                transitions=(),
                runtime_ready=False,
            )
            paths = {
                "policy": module_root / "mission_quest_route_policy.lua",
                "transitions": module_root / "mission_quest_route_transitions.lua",
                "contracts": module_root / "mission_quest_route_contracts.lua",
                "manifest": addon_data / "mission-quest-route-manifest.tsv",
            }
            first_bytes = {name: path.read_bytes() for name, path in paths.items()}
            second = routes.write_route_runtime_artifacts(
                repo_root=repo,
                third_party_root=third_party,
                policy=policy,
                contracts=(),
                transitions=(),
                runtime_ready=False,
            )
            self.assertEqual(first, second)
            self.assertEqual(
                first_bytes, {name: path.read_bytes() for name, path in paths.items()}
            )
            self.assertEqual(reader.read_bytes(), before_reader)
            self.assertFalse(first["runtime_ready"])
            self.assertEqual(first["contract_count"], 0)
            self.assertEqual(first["transition_count"], 0)
            manifest = paths["manifest"].read_bytes()
            self.assertEqual(first["manifest_sha256"], hashlib.sha256(manifest).hexdigest())
            rows = routes.parse_runtime_manifest(manifest)
            self.assertEqual(
                {row["relative_path"] for row in rows},
                {
                    "modules/mission_quest_route_policy.lua",
                    "modules/mission_quest_route_transitions.lua",
                    "modules/mission_quest_route_contracts.lua",
                    "data/ffxi-nav-destinations.tsv",
                    "data/ffxi-nav-zoneline-graph.tsv",
                    "third_party/FFXI-NavMesh-Builder/FFXINAV.dll",
                },
            )
            contracts_lua = paths["contracts"].read_text(encoding="utf-8")
            transitions_lua = paths["transitions"].read_text(encoding="utf-8")
            self.assertNotIn("route_ready = true", contracts_lua)
            self.assertIn("local contracts = {  }", contracts_lua)
            self.assertIn("local transitions = {  }", transitions_lua)

            with self.assertRaises(routes.RouteEvidenceError):
                routes.write_route_runtime_artifacts(
                    repo_root=repo,
                    third_party_root=third_party,
                    policy=policy,
                    contracts=(),
                    transitions=(),
                    runtime_ready=True,
                )

    def test_writer_rejects_stale_contract_hashes_before_mutating_outputs(self) -> None:
        routes = self.routes()
        evidence = routes.bind_local_leg_evidence(
            candidate=copy.deepcopy(CANDIDATE),
            destination=self.destination(),
            ingress=self.ingress(),
            request=self.request(),
            observation=routes.classify_probe_observation(
                self.request(), _response(), self.policy()
            ),
            current_inputs=self.current_inputs(),
            required_transition_ids=(),
            policy=self.policy(),
        )
        stale_contract = {
            "schema": 2,
            "contract_id": "route:v2:" + "a" * 64,
            "candidate_id": CANDIDATE["candidate_id"],
            "action_id": CANDIDATE["action_id"],
            "group_id": CANDIDATE["group_id"],
            "destination_id": CANDIDATE["destination_id"],
            "zone": 143,
            "authorized_directed_prefix": (947466874,),
            "expected_inputs": copy.deepcopy(evidence["inputs"]),
            "route_ready": True,
        }
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / "repo"
            addon = repo / "ashita" / "addons" / "accessxi_reader"
            modules = addon / "modules"
            addon_data = addon / "data"
            modules.mkdir(parents=True)
            addon_data.mkdir()
            (addon_data / "ffxi-nav-destinations.tsv").write_bytes(DESTINATION_TSV)
            (addon_data / "ffxi-nav-zoneline-graph.tsv").write_bytes(GRAPH_TSV)
            transition_source = repo / "data" / "mission-quest-guides"
            transition_source.mkdir(parents=True)
            (transition_source / "route-transitions.json").write_text(
                '{"schema_version":2,"transitions":[]}\n',
                encoding="utf-8",
                newline="\n",
            )
            third_party = repo / "third_party"
            dll = third_party / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
            mesh = third_party / "xiNavmeshes" / "Palborough_Mines.nav"
            dll.parent.mkdir(parents=True)
            mesh.parent.mkdir(parents=True)
            dll.write_bytes(b"new dll bytes")
            mesh.write_bytes(b"new mesh bytes")
            sentinels = {
                modules / "mission_quest_route_policy.lua": b"old policy\n",
                modules / "mission_quest_route_transitions.lua": b"old transitions\n",
                modules / "mission_quest_route_contracts.lua": b"old contracts\n",
                addon_data / "mission-quest-route-manifest.tsv": b"old manifest\n",
            }
            for path, payload in sentinels.items():
                path.write_bytes(payload)
            with self.assertRaises(routes.RouteEvidenceError):
                routes.write_route_runtime_artifacts(
                    repo_root=repo,
                    third_party_root=third_party,
                    policy=self.policy(),
                    contracts=(stale_contract,),
                    transitions=(),
                    runtime_ready=False,
                )
            self.assertEqual(
                {path: path.read_bytes() for path in sentinels}, sentinels
            )


if __name__ == "__main__":
    unittest.main()

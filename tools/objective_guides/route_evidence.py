from __future__ import annotations

import copy
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, Callable, Iterable, Mapping, Sequence


class RouteEvidenceError(ValueError):
    pass


_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_CONTROL = re.compile(r"[\x00-\x1f\x7f]")
_RESPONSE_FIELDS = {
    "schema",
    "protocol",
    "request_id",
    "status",
    "start_valid",
    "end_valid",
    "fallback_used",
    "waypoint_count",
    "waypoints",
    "first_endpoint_error",
    "last_endpoint_error",
    "start_clearance",
    "end_clearance",
    "minimum_waypoint_clearance",
    "path_length",
    "mesh_relative_path",
    "mesh_sha256",
    "mesh_sha256_before",
    "mesh_sha256_after",
    "ffxinav_relative_path",
    "ffxinav_sha256",
    "ffxinav_sha256_before",
    "ffxinav_sha256_after",
    "loaded_dll_path",
    "loaded_mesh_path",
    "native_calls",
}
_REQUEST_FIELDS = {
    "schema",
    "protocol",
    "op",
    "request_id",
    "zone",
    "mesh_relative_path",
    "mesh_sha256",
    "ffxinav_relative_path",
    "ffxinav_sha256",
    "policy_revision",
    "policy_sha256",
    "thresholds",
    "start",
    "end",
    "expected_loaded_dll_path",
    "expected_loaded_mesh_path",
}
_WAYPOINT_FIELDS = {"x", "z", "y", "clearance"}
_NATIVE_CALL_FIELDS = {"FindPath", "FindClosestPath", "Get_WayPoints"}
_PROBE_STATUSES = {
    "exact-path",
    "no-exact-path",
    "start-invalid",
    "end-invalid",
    "tool-error",
}
_GLOBAL_INPUT_FIELDS = (
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
)


@dataclass(frozen=True)
class RouteProofPolicy:
    schema_version: int
    policy_revision: str
    probe_protocol: str
    probe_schema: int
    thresholds: Mapping[str, float | int]
    fixtures: tuple[Mapping[str, Any], ...]


@dataclass(frozen=True)
class ProbeProcessResult:
    exit_code: int
    stdout: str
    stderr: str


def validate_dependency_root(path: str | Path) -> Path:
    """Return a fully-qualified lexical root after rejecting every reparse alias."""

    lexical = Path(os.path.abspath(os.fspath(path)))
    try:
        if not lexical.is_dir():
            raise RouteEvidenceError(f"Dependency root is missing: {lexical}")
        parts = lexical.parts
        current = Path(parts[0])
        for part in parts[1:]:
            current = current / part
            metadata = os.lstat(current)
            attributes = int(getattr(metadata, "st_file_attributes", 0))
            if stat.S_ISLNK(metadata.st_mode) or attributes & 0x400:
                raise RouteEvidenceError(
                    f"Dependency root contains a reparse or symbolic-link component: {current}"
                )
    except OSError as error:
        raise RouteEvidenceError(f"Could not validate dependency root {lexical}: {error}") from error
    return lexical


def publish_navprobe(repo_root: Path, publish_root: Path) -> Path:
    """Publish the worktree's x86 probe without copying any native dependency."""
    repository = Path(repo_root).resolve()
    project = repository / "tools" / "navprobe" / "navprobe.csproj"
    if not project.is_file():
        raise RouteEvidenceError(f"navprobe project is missing: {project}")
    dotnet = shutil.which("dotnet")
    if not dotnet:
        raise RouteEvidenceError("The dotnet SDK is unavailable.")
    output = Path(publish_root).resolve()
    output.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [
            dotnet,
            "publish",
            str(project),
            "-c",
            "Release",
            "-r",
            "win-x86",
            "--self-contained",
            "false",
            "-o",
            str(output),
        ],
        cwd=repository,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RouteEvidenceError(
            "navprobe publish failed:\n" + (result.stdout + result.stderr).strip()
        )
    executable = output / "navprobe.exe"
    if not executable.is_file():
        raise RouteEvidenceError(f"Published navprobe executable is missing: {executable}")
    return executable


def run_native_probe_worker(
    executable: Path,
    *,
    third_party_root: Path,
    requests: Sequence[Mapping[str, Any]],
    timeout_seconds: float,
) -> ProbeProcessResult:
    if not requests:
        raise RouteEvidenceError("Native probe worker requires at least one request.")
    dependency_root = validate_dependency_root(third_party_root)
    payload = b"".join(_canonical_json(dict(row)) for row in requests).decode("utf-8")
    try:
        result = subprocess.run(
            [
                str(Path(executable).resolve()),
                "--proof-jsonl",
                "--third-party-root",
                str(dependency_root),
            ],
            input=payload,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise RouteEvidenceError(f"Native probe worker failed: {error}") from error
    return ProbeProcessResult(result.returncode, result.stdout, result.stderr)


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise RouteEvidenceError(f"Duplicate JSON key {key!r}.")
        result[key] = value
    return result


def _strict_json(text: str) -> Any:
    try:
        return json.loads(
            text,
            object_pairs_hook=_strict_object,
            parse_constant=lambda token: (_ for _ in ()).throw(
                RouteEvidenceError(f"Non-finite JSON number {token!r}.")
            ),
        )
    except RouteEvidenceError:
        raise
    except (TypeError, ValueError, json.JSONDecodeError) as error:
        raise RouteEvidenceError(f"Malformed JSON: {error}") from error


def _canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        + "\n"
    ).encode("utf-8")


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _require_object(value: Any, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise RouteEvidenceError(f"{label} must be an object.")
    return value


def _require_exact_fields(value: Mapping[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise RouteEvidenceError(f"{label} fields mismatch; missing={missing}, extra={extra}.")


def _require_string(value: Any, label: str, *, nonempty: bool = True) -> str:
    if not isinstance(value, str) or (nonempty and not value):
        raise RouteEvidenceError(f"{label} must be a{' nonempty' if nonempty else ''} string.")
    if _CONTROL.search(value):
        raise RouteEvidenceError(f"{label} contains control characters.")
    return value


def _require_bool(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise RouteEvidenceError(f"{label} must be a boolean.")
    return value


def _require_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise RouteEvidenceError(f"{label} must be an integer.")
    if minimum is not None and value < minimum:
        raise RouteEvidenceError(f"{label} is below {minimum}.")
    return value


def _require_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise RouteEvidenceError(f"{label} must be numeric.")
    result = float(value)
    if not math.isfinite(result):
        raise RouteEvidenceError(f"{label} must be finite.")
    return result


def _require_sha256(value: Any, label: str) -> str:
    result = _require_string(value, label)
    if not _HEX64.fullmatch(result):
        raise RouteEvidenceError(f"{label} must be 64 lowercase hexadecimal characters.")
    return result


def parse_policy(value: Mapping[str, Any]) -> RouteProofPolicy:
    root = _require_object(value, "route-proof policy")
    _require_exact_fields(
        root,
        {"schema_version", "policy_revision", "probe_protocol", "probe_schema", "thresholds", "fixtures"},
        "route-proof policy",
    )
    thresholds = _require_object(root["thresholds"], "route-proof thresholds")
    expected_thresholds = {
        "endpoint_epsilon_yalms",
        "minimum_endpoint_clearance_yalms",
        "minimum_waypoint_clearance_yalms",
        "maximum_segment_length_yalms",
        "maximum_waypoint_count",
        "transition_corridor_radius_yalms",
    }
    _require_exact_fields(thresholds, expected_thresholds, "route-proof thresholds")
    parsed_thresholds: dict[str, float | int] = {}
    for key in sorted(expected_thresholds):
        if key == "maximum_waypoint_count":
            parsed_thresholds[key] = _require_int(thresholds[key], key, minimum=2)
        else:
            number = _require_number(thresholds[key], key)
            if number <= 0:
                raise RouteEvidenceError(f"{key} must be positive.")
            parsed_thresholds[key] = number
    raw_fixtures = root["fixtures"]
    if not isinstance(raw_fixtures, list):
        raise RouteEvidenceError("route-proof fixtures must be a list.")
    fixtures: list[Mapping[str, Any]] = []
    fixture_ids: set[str] = set()
    for index, raw in enumerate(raw_fixtures):
        row = _require_object(raw, f"fixture {index}")
        _require_exact_fields(row, {"id", "expect", "request", "observation"}, f"fixture {index}")
        fixture_id = _require_string(row["id"], f"fixture {index} id")
        expect = _require_string(row["expect"], f"fixture {index} expect")
        if fixture_id in fixture_ids:
            raise RouteEvidenceError(f"Duplicate policy fixture {fixture_id!r}.")
        fixture_ids.add(fixture_id)
        request = copy.deepcopy(dict(_require_object(row["request"], f"fixture {index} request")))
        observation = copy.deepcopy(
            dict(_require_object(row["observation"], f"fixture {index} observation"))
        )
        fixtures.append(
            {"id": fixture_id, "expect": expect, "request": request, "observation": observation}
        )
    return RouteProofPolicy(
        schema_version=_require_int(root["schema_version"], "schema_version", minimum=1),
        policy_revision=_require_string(root["policy_revision"], "policy_revision"),
        probe_protocol=_require_string(root["probe_protocol"], "probe_protocol"),
        probe_schema=_require_int(root["probe_schema"], "probe_schema", minimum=1),
        thresholds=parsed_thresholds,
        fixtures=tuple(fixtures),
    )


def policy_to_mapping(policy: RouteProofPolicy) -> dict[str, Any]:
    return {
        "schema_version": policy.schema_version,
        "policy_revision": policy.policy_revision,
        "probe_protocol": policy.probe_protocol,
        "probe_schema": policy.probe_schema,
        "thresholds": dict(policy.thresholds),
        "fixtures": [dict(row) for row in policy.fixtures],
    }


def load_policy(path: Path) -> RouteProofPolicy:
    try:
        value = _strict_json(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise RouteEvidenceError(f"Could not read route-proof policy {path}: {error}") from error
    return parse_policy(_require_object(value, "route-proof policy"))


def policy_sha256(policy: RouteProofPolicy) -> str:
    return _sha256_bytes(_canonical_json(policy_to_mapping(policy)))


def classify_policy_fixture(policy: RouteProofPolicy, fixture_id: str) -> str:
    for row in policy.fixtures:
        if row["id"] == fixture_id:
            return classify_policy_case(policy, row["request"], row["observation"])
    raise RouteEvidenceError(f"Unknown policy fixture {fixture_id!r}.")


def classify_policy_case(
    policy: RouteProofPolicy,
    request: Mapping[str, Any],
    observation: Mapping[str, Any],
) -> str:
    return classify_probe_observation(request, observation, policy)["reason"]


def _lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def _lua_value(value: Any, indent: str = "") -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if not math.isfinite(float(value)):
            raise RouteEvidenceError("Lua output cannot contain non-finite numbers.")
        return repr(value)
    if isinstance(value, str):
        return _lua_quote(value)
    if isinstance(value, (list, tuple)):
        return "{ " + ", ".join(_lua_value(item, indent + "  ") for item in value) + " }"
    if isinstance(value, Mapping):
        return "{ " + ", ".join(
            f"[{_lua_quote(str(key))}] = {_lua_value(item, indent + '  ')}"
            for key, item in sorted(value.items(), key=lambda pair: str(pair[0]))
        ) + " }"
    raise RouteEvidenceError(f"Cannot render {type(value).__name__} as Lua.")


def render_policy_lua(policy: RouteProofPolicy) -> str:
    lines = [
        "-- Generated by tools/objective_guides/route_evidence.py. Do not edit.",
        "local policy = {",
        f"  schema_version = {policy.schema_version},",
        f"  policy_revision = {_lua_quote(policy.policy_revision)},",
        f"  policy_sha256 = {_lua_quote(policy_sha256(policy))},",
        f"  probe_protocol = {_lua_quote(policy.probe_protocol)},",
        f"  probe_schema = {policy.probe_schema},",
        "  thresholds = {",
    ]
    for key, value in sorted(policy.thresholds.items()):
        lines.append(f"    {key} = {value},")
    lines.extend(("  },", "  fixtures = {"))
    for row in policy.fixtures:
        lines.append(f"    [{_lua_quote(row['id'])}] = {_lua_value(row)},")
    lines.extend(
        (
            "  },",
            "}",
            "local function distance(a, b)",
            "  local dx, dz, dy = a.x - b.x, a.z - b.z, a.y - b.y",
            "  return math.sqrt(dx * dx + dz * dz + dy * dy)",
            "end",
            "local function classify_case(request, row)",
            "  if not row.start_valid then return 'start-invalid' end",
            "  if not row.end_valid then return 'end-invalid' end",
            "  if row.fallback_used then return 'closest-path-forbidden' end",
            "  if row.status ~= 'exact-path' then return 'no-exact-path' end",
            "  if row.waypoint_count > policy.thresholds.maximum_waypoint_count then return 'waypoint-count-excessive' end",
            "  if row.waypoint_count ~= #row.waypoints then return 'waypoint-count-mismatch' end",
            "  if #row.waypoints < 2 then return 'too-few-waypoints' end",
            "  local first, last = row.waypoints[1], row.waypoints[#row.waypoints]",
            "  local actual_first, actual_last = distance(request.start, first), distance(request['end'], last)",
            "  if math.max(actual_first, actual_last, row.first_endpoint_error, row.last_endpoint_error) > policy.thresholds.endpoint_epsilon_yalms then return 'endpoint-error' end",
            "  if math.abs(actual_first - row.first_endpoint_error) > 0.000001 or math.abs(actual_last - row.last_endpoint_error) > 0.000001 then return 'endpoint-error-recomputed' end",
            "  local minimum = first.clearance",
            "  for _, waypoint in ipairs(row.waypoints) do if waypoint.clearance < minimum then minimum = waypoint.clearance end end",
            "  if math.abs(minimum - row.minimum_waypoint_clearance) > 0.000001 then return 'waypoint-clearance-recomputed' end",
            "  if minimum < policy.thresholds.minimum_waypoint_clearance_yalms then return 'waypoint-clearance' end",
            "  if math.min(row.start_clearance, row.end_clearance, first.clearance, last.clearance) < policy.thresholds.minimum_endpoint_clearance_yalms then return 'endpoint-clearance' end",
            "  local length = 0",
            "  for index = 2, #row.waypoints do",
            "    local segment = distance(row.waypoints[index - 1], row.waypoints[index])",
            "    if segment > policy.thresholds.maximum_segment_length_yalms then return 'segment-too-long' end",
            "    length = length + segment",
            "  end",
            "  if math.abs(length - row.path_length) > 0.000000001 then return 'path-length-mismatch' end",
            "  return 'mesh-proven'",
            "end",
            "policy.classify_case = classify_case",
            "function policy.classify_fixture(id)",
            "  local fixture = policy.fixtures[id]",
            "  if fixture == nil then return nil end",
            "  return classify_case(fixture.request, fixture.observation)",
            "end",
            "return policy",
            "",
        )
    )
    return "\n".join(lines)


def exercise_policy_lua_fixtures(lua: str, executable: Path) -> dict[str, str]:
    if not executable.is_file():
        raise RouteEvidenceError(f"Lua 5.1 executable is missing: {executable}")
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        module_path = root / "policy.lua"
        script_path = root / "exercise.lua"
        module_path.write_text(lua, encoding="utf-8", newline="\n")
        script_path.write_text(
            "local policy = assert(loadfile(arg[1]))()\n"
            "local ids = {}\n"
            "for id, _ in pairs(policy.fixtures) do table.insert(ids, id) end\n"
            "table.sort(ids)\n"
            "for _, id in ipairs(ids) do io.write(id, '\\t', policy.classify_fixture(id), '\\n') end\n",
            encoding="utf-8",
            newline="\n",
        )
        result = subprocess.run(
            [str(executable), str(script_path), str(module_path)],
            capture_output=True,
            text=True,
            check=False,
        )
    if result.returncode != 0:
        raise RouteEvidenceError(f"Lua policy fixture exercise failed: {result.stderr}")
    rows: dict[str, str] = {}
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 2 or fields[0] in rows:
            raise RouteEvidenceError("Lua policy fixture output was malformed.")
        rows[fields[0]] = fields[1]
    return rows


def accessxi_to_native_xyz(point: Mapping[str, Any]) -> dict[str, float]:
    return {
        "X": _require_number(point.get("x"), "AccessXI x"),
        "Y": _require_number(point.get("y"), "AccessXI y"),
        "Z": _require_number(point.get("z"), "AccessXI z"),
    }


def native_xyz_to_accessxi(point: Mapping[str, Any]) -> dict[str, float]:
    return {
        "x": _require_number(point.get("X"), "native X"),
        "z": _require_number(point.get("Z"), "native Z"),
        "y": _require_number(point.get("Y"), "native Y"),
    }


def _validate_relative_dependency_path(value: str, label: str) -> str:
    text = _require_string(value, label).replace("\\", "/")
    windows = PureWindowsPath(value)
    if windows.is_absolute() or windows.drive or text.startswith("/"):
        raise RouteEvidenceError(f"{label} must be relative.")
    parts = text.split("/")
    if any(part in {"", ".", ".."} for part in parts) or ":" in text:
        raise RouteEvidenceError(f"{label} is not a canonical child path.")
    return "/".join(parts)


def _canonical_display_path(path: Path) -> str:
    return str(path.resolve()).replace("\\", "/")


def _contained_path(root: Path, relative: str, label: str, *, must_exist: bool = False) -> Path:
    canonical_root = root.resolve()
    relative = _validate_relative_dependency_path(relative, label)
    candidate = canonical_root.joinpath(*relative.split("/"))
    try:
        resolved = candidate.resolve(strict=must_exist)
    except OSError as error:
        raise RouteEvidenceError(f"Could not resolve {label}: {error}") from error
    try:
        common = os.path.commonpath((str(canonical_root), str(resolved)))
    except ValueError as error:
        raise RouteEvidenceError(f"{label} escapes its root.") from error
    if os.path.normcase(common) != os.path.normcase(str(canonical_root)):
        raise RouteEvidenceError(f"{label} escapes its root.")
    return resolved


def build_probe_request(
    *,
    request_id: str,
    zone: int,
    mesh_relative_path: str,
    start: Mapping[str, Any],
    end: Mapping[str, Any],
    mesh_sha256: str,
    ffxinav_sha256: str,
    policy: RouteProofPolicy,
    third_party_root: str | Path,
    zone_mesh_names: Mapping[int | str, str],
) -> dict[str, Any]:
    mesh_relative = _validate_relative_dependency_path(mesh_relative_path, "mesh_relative_path")
    dll_relative = "FFXI-NavMesh-Builder/FFXINAV.dll"
    root = Path(third_party_root)
    mesh_path = _contained_path(root, mesh_relative, "mesh_relative_path", must_exist=False)
    dll_path = _contained_path(root, dll_relative, "ffxinav_relative_path", must_exist=False)
    start_value = {
        key: _require_number(start.get(key), f"start {key}") for key in ("x", "z", "y")
    }
    end_value = {
        key: _require_number(end.get(key), f"end {key}") for key in ("x", "z", "y")
    }
    result = {
        "schema": policy.probe_schema,
        "protocol": policy.probe_protocol,
        "op": "FindPath",
        "request_id": _require_string(request_id, "request_id"),
        "zone": _require_int(zone, "zone", minimum=0),
        "mesh_relative_path": mesh_relative,
        "mesh_sha256": _require_sha256(mesh_sha256, "mesh_sha256"),
        "ffxinav_relative_path": dll_relative,
        "ffxinav_sha256": _require_sha256(ffxinav_sha256, "ffxinav_sha256"),
        "policy_revision": policy.policy_revision,
        "policy_sha256": policy_sha256(policy),
        "thresholds": dict(policy.thresholds),
        "start": start_value,
        "end": end_value,
        "expected_loaded_dll_path": _canonical_display_path(dll_path),
        "expected_loaded_mesh_path": _canonical_display_path(mesh_path),
    }
    validate_probe_request_mapping(
        result,
        policy=policy,
        third_party_root=root,
        zone_mesh_names=zone_mesh_names,
    )
    return result


def _zone_mesh_name(zone_mesh_names: Mapping[int | str, str], zone: int) -> str:
    values = [
        value for key, value in zone_mesh_names.items()
        if str(key) == str(zone)
    ]
    if len(values) != 1:
        raise RouteEvidenceError(f"Zone {zone} does not have one canonical mesh mapping.")
    return _require_string(values[0], f"zone {zone} mesh name")


def validate_probe_request_mapping(
    raw: Mapping[str, Any],
    *,
    policy: RouteProofPolicy,
    third_party_root: Path,
    zone_mesh_names: Mapping[int | str, str],
    exact_fields: set[str] | None = None,
) -> dict[str, Any]:
    row = dict(_require_object(raw, "probe request"))
    _require_exact_fields(row, exact_fields or _REQUEST_FIELDS, "probe request")
    if _require_int(row["schema"], "request schema") != policy.probe_schema:
        raise RouteEvidenceError("Probe request schema does not match the selected policy.")
    if _require_string(row["protocol"], "request protocol") != policy.probe_protocol:
        raise RouteEvidenceError("Probe request protocol does not match the selected policy.")
    if _require_string(row["op"], "request op") != "FindPath":
        raise RouteEvidenceError("Proof mode accepts only FindPath.")
    _require_string(row["request_id"], "request_id")
    zone = _require_int(row["zone"], "zone", minimum=0)
    mesh_relative = _validate_relative_dependency_path(row["mesh_relative_path"], "mesh_relative_path")
    dll_relative = _validate_relative_dependency_path(row["ffxinav_relative_path"], "ffxinav_relative_path")
    if dll_relative != "FFXI-NavMesh-Builder/FFXINAV.dll":
        raise RouteEvidenceError("Probe request names an unexpected FFXINAV location.")
    expected_mesh_name = _zone_mesh_name(zone_mesh_names, zone)
    if PurePosixPath(mesh_relative).name.casefold() != expected_mesh_name.casefold():
        raise RouteEvidenceError("Probe request zone and mesh mapping disagree.")
    _require_sha256(row["mesh_sha256"], "mesh_sha256")
    _require_sha256(row["ffxinav_sha256"], "ffxinav_sha256")
    if _require_string(row["policy_revision"], "policy_revision") != policy.policy_revision:
        raise RouteEvidenceError("Probe request policy revision mismatch.")
    if _require_sha256(row["policy_sha256"], "policy_sha256") != policy_sha256(policy):
        raise RouteEvidenceError("Probe request policy hash mismatch.")
    thresholds = _require_object(row["thresholds"], "request thresholds")
    if dict(thresholds) != dict(policy.thresholds):
        raise RouteEvidenceError("Probe request thresholds do not exactly match the selected policy.")
    for label in ("start", "end"):
        point = _require_object(row[label], label)
        _require_exact_fields(point, {"x", "z", "y"}, label)
        for field in ("x", "z", "y"):
            _require_number(point[field], f"{label} {field}")
    mesh_path = _contained_path(third_party_root, mesh_relative, "mesh_relative_path", must_exist=False)
    dll_path = _contained_path(third_party_root, dll_relative, "ffxinav_relative_path", must_exist=False)
    if _normalized_path_text(_require_string(row["expected_loaded_mesh_path"], "expected_loaded_mesh_path")) != _normalized_path_text(_canonical_display_path(mesh_path)):
        raise RouteEvidenceError("Probe request expected mesh path mismatch.")
    if _normalized_path_text(_require_string(row["expected_loaded_dll_path"], "expected_loaded_dll_path")) != _normalized_path_text(_canonical_display_path(dll_path)):
        raise RouteEvidenceError("Probe request expected FFXINAV path mismatch.")
    return row


def parse_probe_request_jsonl(
    payload: str,
    *,
    policy: RouteProofPolicy,
    third_party_root: Path,
    zone_mesh_names: Mapping[int | str, str],
) -> tuple[dict[str, Any], ...]:
    lines = payload.splitlines()
    if not lines or any(not line.strip() for line in lines):
        raise RouteEvidenceError("Probe request JSONL is empty or contains a blank line.")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    for line in lines:
        row = validate_probe_request_mapping(
            _require_object(_strict_json(line), "probe request"),
            policy=policy,
            third_party_root=third_party_root,
            zone_mesh_names=zone_mesh_names,
        )
        if row["request_id"] in seen:
            raise RouteEvidenceError(f"Duplicate probe request_id {row['request_id']!r}.")
        seen.add(row["request_id"])
        result.append(row)
    return tuple(result)


def _normalized_path_text(value: str) -> str:
    return os.path.normcase(os.path.normpath(value.replace("/", os.sep).replace("\\", os.sep)))


def _validate_probe_response(request: Mapping[str, Any], raw: Mapping[str, Any]) -> dict[str, Any]:
    row = dict(raw)
    _require_exact_fields(row, _RESPONSE_FIELDS, "probe response")
    if _require_int(row["schema"], "response schema") != request["schema"]:
        raise RouteEvidenceError("Probe response schema mismatch.")
    if _require_string(row["protocol"], "response protocol") != request["protocol"]:
        raise RouteEvidenceError("Probe response protocol mismatch.")
    if _require_string(row["request_id"], "response request_id") != request["request_id"]:
        raise RouteEvidenceError("Probe response request_id mismatch.")
    status = _require_string(row["status"], "response status")
    if status not in _PROBE_STATUSES:
        raise RouteEvidenceError(f"Unknown probe response status {status!r}.")
    for field in ("start_valid", "end_valid", "fallback_used"):
        _require_bool(row[field], field)
    count = _require_int(row["waypoint_count"], "waypoint_count", minimum=0)
    maximum = _require_int(request["thresholds"]["maximum_waypoint_count"], "maximum_waypoint_count")
    if count > maximum:
        raise RouteEvidenceError("Probe response has an excessive waypoint count.")
    if not isinstance(row["waypoints"], list) or len(row["waypoints"]) != count:
        raise RouteEvidenceError("Probe response waypoint count does not match its array.")
    for index, waypoint in enumerate(row["waypoints"]):
        item = _require_object(waypoint, f"waypoint {index}")
        _require_exact_fields(item, _WAYPOINT_FIELDS, f"waypoint {index}")
        for field in _WAYPOINT_FIELDS:
            _require_number(item[field], f"waypoint {index} {field}")
    for field in (
        "first_endpoint_error",
        "last_endpoint_error",
        "start_clearance",
        "end_clearance",
        "minimum_waypoint_clearance",
        "path_length",
    ):
        _require_number(row[field], field)
    for field in (
        "mesh_relative_path",
        "ffxinav_relative_path",
        "loaded_dll_path",
        "loaded_mesh_path",
    ):
        _require_string(row[field], field)
    for field in (
        "mesh_sha256",
        "mesh_sha256_before",
        "mesh_sha256_after",
        "ffxinav_sha256",
        "ffxinav_sha256_before",
        "ffxinav_sha256_after",
    ):
        _require_sha256(row[field], field)
    if row["mesh_relative_path"] != request["mesh_relative_path"]:
        raise RouteEvidenceError("Probe response mesh relative path mismatch.")
    if row["ffxinav_relative_path"] != request["ffxinav_relative_path"]:
        raise RouteEvidenceError("Probe response FFXINAV relative path mismatch.")
    if any(row[field] != request["mesh_sha256"] for field in ("mesh_sha256", "mesh_sha256_before", "mesh_sha256_after")):
        raise RouteEvidenceError("Probe response mesh hash mismatch.")
    if any(row[field] != request["ffxinav_sha256"] for field in ("ffxinav_sha256", "ffxinav_sha256_before", "ffxinav_sha256_after")):
        raise RouteEvidenceError("Probe response FFXINAV hash mismatch.")
    if _normalized_path_text(row["loaded_mesh_path"]) != _normalized_path_text(request["expected_loaded_mesh_path"]):
        raise RouteEvidenceError("Probe loaded a different mesh path.")
    if _normalized_path_text(row["loaded_dll_path"]) != _normalized_path_text(request["expected_loaded_dll_path"]):
        raise RouteEvidenceError("Probe loaded a different FFXINAV path.")
    calls = _require_object(row["native_calls"], "native_calls")
    _require_exact_fields(calls, _NATIVE_CALL_FIELDS, "native_calls")
    for field in _NATIVE_CALL_FIELDS:
        _require_int(calls[field], f"native_calls.{field}", minimum=0)
    if calls["FindClosestPath"] != 0:
        raise RouteEvidenceError("FindClosestPath is forbidden in proof mode.")
    expected_calls = (
        {"FindPath": 0, "FindClosestPath": 0, "Get_WayPoints": 0}
        if status in {"start-invalid", "end-invalid", "tool-error"}
        else {"FindPath": 1, "FindClosestPath": 0, "Get_WayPoints": 1}
    )
    if dict(calls) != expected_calls:
        raise RouteEvidenceError(
            f"Probe response native call shape is invalid for status {status!r}."
        )
    return row


def parse_probe_jsonl(
    requests: Sequence[Mapping[str, Any]], stdout: str, exit_code: int
) -> tuple[dict[str, Any], ...]:
    if exit_code != 0:
        raise RouteEvidenceError(f"Probe process failed with exit code {exit_code}.")
    request_by_id: dict[str, Mapping[str, Any]] = {}
    for request in requests:
        request_id = _require_string(request.get("request_id"), "request_id")
        if request_id in request_by_id:
            raise RouteEvidenceError(f"Duplicate probe request_id {request_id!r}.")
        request_by_id[request_id] = request
    rows: dict[str, dict[str, Any]] = {}
    lines = stdout.splitlines()
    if any(not line.strip() for line in lines):
        raise RouteEvidenceError("Probe JSONL contains a blank line.")
    for line in lines:
        raw = _require_object(_strict_json(line), "probe response")
        request_id = raw.get("request_id")
        if not isinstance(request_id, str) or request_id not in request_by_id:
            raise RouteEvidenceError(f"Unexpected probe response request_id {request_id!r}.")
        if request_id in rows:
            raise RouteEvidenceError(f"Duplicate probe response request_id {request_id!r}.")
        rows[request_id] = _validate_probe_response(request_by_id[request_id], raw)
    missing = sorted(set(request_by_id) - set(rows))
    if missing:
        raise RouteEvidenceError(f"Missing probe responses: {missing}.")
    return tuple(rows[request["request_id"]] for request in requests)


def _distance(a: Mapping[str, Any], b: Mapping[str, Any]) -> float:
    return math.sqrt(sum((_require_number(a[key], key) - _require_number(b[key], key)) ** 2 for key in ("x", "z", "y")))


def polyline_length(waypoints: Sequence[Mapping[str, Any]]) -> float:
    return sum(_distance(first, second) for first, second in zip(waypoints, waypoints[1:]))


def _point_segment_distance_2d(
    point: Mapping[str, Any], first: Mapping[str, Any], second: Mapping[str, Any]
) -> float:
    px, pz = float(point["x"]), float(point["z"])
    ax, az = float(first["x"]), float(first["z"])
    bx, bz = float(second["x"]), float(second["z"])
    dx, dz = bx - ax, bz - az
    denominator = dx * dx + dz * dz
    if denominator == 0:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / denominator))
    return math.hypot(px - (ax + t * dx), pz - (az + t * dz))


def _crosses_transition(
    waypoints: Sequence[Mapping[str, Any]], transition: Mapping[str, Any], radius: float
) -> bool:
    pre = _require_object(transition.get("pre_anchor"), "transition pre_anchor")
    post = _require_object(transition.get("post_anchor"), "transition post_anchor")
    lower, upper = sorted((_require_number(pre.get("y"), "pre y"), _require_number(post.get("y"), "post y")))
    center = {"x": (float(pre["x"]) + float(post["x"])) / 2, "z": (float(pre["z"]) + float(post["z"])) / 2}
    for first, second in zip(waypoints, waypoints[1:]):
        segment_lower, segment_upper = sorted((float(first["y"]), float(second["y"])))
        if segment_upper < lower or segment_lower > upper:
            continue
        if _point_segment_distance_2d(center, first, second) <= radius:
            return True
    return False


def classify_probe_observation(
    request: Mapping[str, Any],
    response: Mapping[str, Any],
    policy: RouteProofPolicy,
    *,
    declared_transitions: Sequence[Mapping[str, Any]] = (),
) -> dict[str, Any]:
    row = copy.deepcopy(dict(response))
    row["probe_status"] = row.get("status", "")

    def rejected(reason: str) -> dict[str, Any]:
        row["status"] = "rejected"
        row["reason"] = reason
        return row

    try:
        if row.get("status") == "tool-error":
            return rejected("tool-error")
        if not _require_bool(row.get("start_valid"), "start_valid"):
            return rejected("start-invalid")
        if not _require_bool(row.get("end_valid"), "end_valid"):
            return rejected("end-invalid")
        if _require_bool(row.get("fallback_used"), "fallback_used"):
            return rejected("closest-path-forbidden")
        if row.get("status") != "exact-path":
            return rejected("no-exact-path")
        count = _require_int(row.get("waypoint_count"), "waypoint_count", minimum=0)
        maximum = int(policy.thresholds["maximum_waypoint_count"])
        if count > maximum:
            return rejected("waypoint-count-excessive")
        waypoints = row.get("waypoints")
        if not isinstance(waypoints, list) or len(waypoints) != count:
            return rejected("waypoint-count-mismatch")
        if count < 2:
            return rejected("too-few-waypoints")
        for index, waypoint in enumerate(waypoints):
            item = _require_object(waypoint, f"waypoint {index}")
            for field in _WAYPOINT_FIELDS:
                _require_number(item.get(field), f"waypoint {index} {field}")
        endpoint_limit = float(policy.thresholds["endpoint_epsilon_yalms"])
        actual_first = _distance(request["start"], waypoints[0])
        actual_last = _distance(request["end"], waypoints[-1])
        claimed_first = _require_number(row.get("first_endpoint_error"), "first_endpoint_error")
        claimed_last = _require_number(row.get("last_endpoint_error"), "last_endpoint_error")
        if max(actual_first, actual_last, claimed_first, claimed_last) > endpoint_limit:
            return rejected("endpoint-error")
        if abs(actual_first - claimed_first) > 1e-6 or abs(actual_last - claimed_last) > 1e-6:
            return rejected("endpoint-error-recomputed")
        actual_minimum = min(float(waypoint["clearance"]) for waypoint in waypoints)
        claimed_minimum = _require_number(row.get("minimum_waypoint_clearance"), "minimum_waypoint_clearance")
        if abs(actual_minimum - claimed_minimum) > 1e-6:
            return rejected("waypoint-clearance-recomputed")
        waypoint_limit = float(policy.thresholds["minimum_waypoint_clearance_yalms"])
        if claimed_minimum < waypoint_limit:
            return rejected("waypoint-clearance")
        claimed_start = _require_number(row.get("start_clearance"), "start_clearance")
        claimed_end = _require_number(row.get("end_clearance"), "end_clearance")
        endpoint_clearance = float(policy.thresholds["minimum_endpoint_clearance_yalms"])
        if min(claimed_start, claimed_end, float(waypoints[0]["clearance"]), float(waypoints[-1]["clearance"])) < endpoint_clearance:
            return rejected("endpoint-clearance")
        maximum_segment = float(policy.thresholds["maximum_segment_length_yalms"])
        if any(_distance(first, second) > maximum_segment for first, second in zip(waypoints, waypoints[1:])):
            return rejected("segment-too-long")
        actual_length = polyline_length(waypoints)
        claimed_length = _require_number(row.get("path_length"), "path_length")
        if abs(actual_length - claimed_length) > 1e-9:
            return rejected("path-length-mismatch")
        radius = float(policy.thresholds["transition_corridor_radius_yalms"])
        if any(_crosses_transition(waypoints, transition, radius) for transition in declared_transitions):
            return rejected("requires-transition")
    except RouteEvidenceError as error:
        return rejected(str(error))
    row["status"] = "mesh-proven"
    row["reason"] = "mesh-proven"
    row["recomputed_path_length"] = polyline_length(row["waypoints"])
    return row


_DESTINATION_PUBLIC_FIELDS = (
    "zone",
    "name",
    "x",
    "z",
    "y",
    "kind",
    "source",
    "confidence",
    "section",
    "destination_id",
    "raw_identity",
    "raw_spawn_ids",
    "cluster_policy_version",
)
_INGRESS_PUBLIC_FIELDS = (
    "zoneline_id",
    "from_zone",
    "from_name",
    "from_code",
    "from_x",
    "from_z",
    "from_y",
    "to_zone",
    "to_name",
    "to_code",
    "to_x",
    "to_z",
    "to_y",
    "source",
    "confidence",
    "note",
)


def _decode_line(line: bytes, label: str) -> str:
    try:
        return line.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RouteEvidenceError(f"{label} is not UTF-8.") from error


def _parse_destination_line(line: bytes) -> dict[str, Any]:
    text = _decode_line(line, "destination row")
    body = text.rstrip("\r\n")
    fields = body.split("\t")
    if len(fields) not in {7, 9, 13}:
        raise RouteEvidenceError(f"Destination row must have 7, 9, or 13 columns: {body!r}")
    try:
        zone = int(fields[0])
        x, z, y = (float(fields[index]) for index in (2, 3, 4))
        if not all(math.isfinite(value) for value in (x, z, y)):
            raise ValueError("non-finite coordinate")
        spawn_ids = (
            tuple(int(value) for value in fields[11].split(","))
            if len(fields) == 13 and fields[11]
            else ()
        )
    except ValueError as error:
        raise RouteEvidenceError(f"Malformed destination row: {body!r}") from error
    if spawn_ids != tuple(sorted(set(spawn_ids))):
        raise RouteEvidenceError(f"Destination spawn IDs are not unique and sorted: {body!r}")
    return {
        "zone": zone,
        "name": fields[1].strip(),
        "x": x,
        "z": z,
        "y": y,
        "kind": fields[5].strip(),
        "source": fields[6].strip(),
        "confidence": fields[7].strip() if len(fields) >= 9 else "",
        "section": fields[8].strip() if len(fields) >= 9 else "",
        "destination_id": fields[9].strip() if len(fields) == 13 else "",
        "raw_identity": fields[10].strip() if len(fields) == 13 else "",
        "raw_spawn_ids": spawn_ids,
        "cluster_policy_version": fields[12].strip() if len(fields) == 13 else "",
    }


def _parse_ingress_line(line: bytes) -> dict[str, Any]:
    text = _decode_line(line, "graph row")
    body = text.rstrip("\r\n")
    fields = body.split("\t")
    if len(fields) not in {15, 16}:
        raise RouteEvidenceError(f"Graph row must have 15 or 16 columns: {body!r}")
    try:
        integers = [int(fields[index]) for index in (0, 1, 7)]
        numbers = [float(fields[index]) for index in (4, 5, 6, 10, 11, 12)]
        if not all(math.isfinite(value) for value in numbers):
            raise ValueError("non-finite coordinate")
    except ValueError as error:
        raise RouteEvidenceError(f"Malformed graph row: {body!r}") from error
    return {
        "zoneline_id": integers[0],
        "from_zone": integers[1],
        "from_name": fields[2].strip(),
        "from_code": fields[3].strip(),
        "from_x": numbers[0],
        "from_z": numbers[1],
        "from_y": numbers[2],
        "to_zone": integers[2],
        "to_name": fields[8].strip(),
        "to_code": fields[9].strip(),
        "to_x": numbers[3],
        "to_z": numbers[4],
        "to_y": numbers[5],
        "source": fields[13].strip(),
        "confidence": fields[14].strip(),
        "note": fields[15].strip() if len(fields) == 16 else "",
    }


def load_route_catalogue_bytes(
    destination_bytes: bytes,
    graph_bytes: bytes,
    *,
    destination_source: str,
    graph_source: str,
) -> dict[str, Any]:
    if destination_bytes.startswith(b"\xef\xbb\xbf") or graph_bytes.startswith(b"\xef\xbb\xbf"):
        raise RouteEvidenceError("Navigation catalogues must be UTF-8 without BOM.")
    destination_digest = _sha256_bytes(destination_bytes)
    graph_digest = _sha256_bytes(graph_bytes)
    destinations: list[dict[str, Any]] = []
    identity_ids: set[str] = set()
    for line in destination_bytes.splitlines(keepends=True):
        if not line.strip() or line.lstrip().startswith(b"#"):
            continue
        row = _parse_destination_line(line)
        destination_id = row["destination_id"]
        if destination_id and destination_id in identity_ids:
            raise RouteEvidenceError(f"Duplicate immutable destination ID {destination_id!r}.")
        if destination_id:
            identity_ids.add(destination_id)
        row.update(
            {
                "_raw_tsv_line": _decode_line(line, "destination row"),
                "_row_sha256": _sha256_bytes(line),
                "_catalog_sha256": destination_digest,
                "_catalog_source": destination_source,
            }
        )
        destinations.append(row)
    graph_lines = graph_bytes.splitlines(keepends=True)
    if not graph_lines:
        raise RouteEvidenceError("Navigation graph is empty.")
    expected_header = "\t".join(_INGRESS_PUBLIC_FIELDS).replace("note", "note")
    actual_header = _decode_line(graph_lines[0], "graph header").rstrip("\r\n")
    if actual_header != expected_header:
        raise RouteEvidenceError(f"Navigation graph header mismatch: {actual_header!r}")
    ingresses: list[dict[str, Any]] = []
    edge_ids: set[int] = set()
    for line in graph_lines[1:]:
        if not line.strip():
            continue
        row = _parse_ingress_line(line)
        edge_id = row["zoneline_id"]
        if edge_id in edge_ids:
            raise RouteEvidenceError(f"Duplicate zoneline ID {edge_id}.")
        edge_ids.add(edge_id)
        row.update(
            {
                "_raw_tsv_line": _decode_line(line, "graph row"),
                "_row_sha256": _sha256_bytes(line),
                "_catalog_sha256": graph_digest,
                "_catalog_source": graph_source,
            }
        )
        ingresses.append(row)
    return {
        "destinations": tuple(destinations),
        "ingresses": tuple(ingresses),
        "destinations_sha256": destination_digest,
        "graph_sha256": graph_digest,
        "destination_source": destination_source,
        "graph_source": graph_source,
    }


def load_route_catalogue_files(destination_path: Path, graph_path: Path) -> dict[str, Any]:
    try:
        destination_bytes = destination_path.read_bytes()
        graph_bytes = graph_path.read_bytes()
    except OSError as error:
        raise RouteEvidenceError(f"Could not read navigation catalogue: {error}") from error
    return load_route_catalogue_bytes(
        destination_bytes,
        graph_bytes,
        destination_source=str(destination_path),
        graph_source=str(graph_path),
    )


def destination_row_sha256(row: Mapping[str, Any]) -> str:
    raw = row.get("_raw_tsv_line")
    if not isinstance(raw, str):
        raise RouteEvidenceError("Destination row lacks exact raw TSV provenance.")
    parsed = _parse_destination_line(raw.encode("utf-8"))
    if any(parsed[field] != row.get(field) for field in _DESTINATION_PUBLIC_FIELDS):
        raise RouteEvidenceError("Parsed destination fields disagree with the exact raw TSV row.")
    digest = _sha256_bytes(raw.encode("utf-8"))
    if row.get("_row_sha256") != digest:
        raise RouteEvidenceError("Destination row digest disagrees with its exact bytes.")
    return digest


def ingress_row_sha256(row: Mapping[str, Any]) -> str:
    raw = row.get("_raw_tsv_line")
    if not isinstance(raw, str):
        raise RouteEvidenceError("Ingress row lacks exact raw TSV provenance.")
    parsed = _parse_ingress_line(raw.encode("utf-8"))
    if any(parsed[field] != row.get(field) for field in _INGRESS_PUBLIC_FIELDS):
        raise RouteEvidenceError("Parsed ingress fields disagree with the exact raw TSV row.")
    digest = _sha256_bytes(raw.encode("utf-8"))
    if row.get("_row_sha256") != digest:
        raise RouteEvidenceError("Ingress row digest disagrees with its exact bytes.")
    return digest


def ingress_row_fields() -> tuple[str, ...]:
    return _INGRESS_PUBLIC_FIELDS


def _point_tuple(row: Mapping[str, Any], prefix: str = "") -> tuple[float, float, float]:
    return tuple(float(row[f"{prefix}{field}"]) for field in ("x", "z", "y"))


def validate_candidate_instance(
    candidate: Mapping[str, Any],
    destinations: Sequence[Mapping[str, Any]],
    *,
    camp_members: Sequence[Sequence[float]],
) -> Mapping[str, Any]:
    destination_id = str(candidate.get("destination_id", "")).strip()
    if not destination_id:
        matches = [
            row for row in destinations
            if int(row.get("zone", -1)) == int(candidate.get("zone", -2))
            and str(row.get("name", "")).casefold() == str(candidate.get("target_name", "")).casefold()
            and str(row.get("kind", "")).casefold() == str(candidate.get("target_kind", "")).casefold()
        ]
        raise RouteEvidenceError(
            f"Candidate lacks immutable destination ID; presentation match count={len(matches)}."
        )
    matches = [row for row in destinations if row.get("destination_id") == destination_id]
    if len(matches) != 1:
        raise RouteEvidenceError(f"Candidate destination ID has {len(matches)} catalogue matches.")
    destination = matches[0]
    expected = {
        "zone": int(destination["zone"]),
        "target_name": destination["name"],
        "target_kind": destination["kind"],
        "target_point": [destination["x"], destination["z"], destination["y"]],
        "raw_identity": destination["raw_identity"],
        "raw_spawn_ids": list(destination["raw_spawn_ids"]),
        "cluster_policy_version": destination["cluster_policy_version"],
    }
    for field, value in expected.items():
        candidate_value = candidate.get(field)
        if field in {"target_name", "target_kind"}:
            if str(candidate_value).casefold() != str(value).casefold():
                raise RouteEvidenceError(f"Candidate {field} does not match immutable destination.")
        elif candidate_value != value:
            raise RouteEvidenceError(f"Candidate {field} does not match immutable destination.")
    if destination["kind"].casefold() == "enemy":
        if not camp_members:
            raise RouteEvidenceError("Enemy camp geometry is missing.")
        points = [tuple(float(value) for value in point) for point in camp_members]
        if any(len(point) != 3 or not all(math.isfinite(value) for value in point) for point in points):
            raise RouteEvidenceError("Enemy camp geometry is malformed.")
        if max(point[2] for point in points) - min(point[2] for point in points) > 24.0:
            raise RouteEvidenceError("Enemy camp spans more than one allowed floor band.")
        for first in points:
            for second in points:
                if math.hypot(first[0] - second[0], first[1] - second[1]) > 120.0:
                    raise RouteEvidenceError("Enemy camp exceeds its complete-link diameter.")
    return destination


def validate_directed_prefix(
    edges: Sequence[Mapping[str, Any]], *, target_zone: int
) -> tuple[bool, str]:
    if not edges:
        return False, "missing-directed-prefix"
    previous_to: int | None = None
    for edge in edges:
        if str(edge.get("confidence", "")).casefold() != "proven":
            return False, "unproven-directed-edge"
        from_zone = int(edge.get("from_zone", -1))
        to_zone = int(edge.get("to_zone", -1))
        if previous_to is not None and from_zone != previous_to:
            return False, "discontinuous-directed-prefix"
        if from_zone == to_zone:
            return False, "invalid-directed-edge"
        previous_to = to_zone
    if previous_to != int(target_zone):
        return False, "wrong-target-zone"
    return True, "proven"


def _candidate_matches_destination(
    candidate: Mapping[str, Any], destination: Mapping[str, Any]
) -> tuple[bool, str]:
    comparisons = (
        ("destination_id", candidate.get("destination_id"), destination.get("destination_id")),
        ("zone", candidate.get("zone"), destination.get("zone")),
        ("target_name", str(candidate.get("target_name", "")).casefold(), str(destination.get("name", "")).casefold()),
        ("target_kind", str(candidate.get("target_kind", "")).casefold(), str(destination.get("kind", "")).casefold()),
        ("target_point", candidate.get("target_point"), [destination.get("x"), destination.get("z"), destination.get("y")]),
        ("raw_identity", candidate.get("raw_identity"), destination.get("raw_identity")),
        ("raw_spawn_ids", list(candidate.get("raw_spawn_ids", ())), list(destination.get("raw_spawn_ids", ()))),
        ("cluster_policy_version", candidate.get("cluster_policy_version"), destination.get("cluster_policy_version")),
    )
    for field, actual, expected in comparisons:
        if actual != expected:
            return False, f"candidate-{field.replace('_', '-')}-mismatch"
    return True, "candidate-matches"


def _selected_evidence_inputs(
    *,
    candidate: Mapping[str, Any],
    destination: Mapping[str, Any],
    ingress: Mapping[str, Any],
    current_inputs: Mapping[str, Any],
) -> dict[str, Any]:
    zone = str(int(candidate["zone"]))
    zone_mesh_names = _require_object(
        current_inputs.get("zone_mesh_name_by_zone"), "zone_mesh_name_by_zone"
    )
    mesh_name = zone_mesh_names.get(zone)
    if mesh_name != current_inputs.get("mesh_name"):
        raise RouteEvidenceError("zone-mesh-mismatch")
    destination_rows = _require_object(
        current_inputs.get("destination_row_sha256_by_id"),
        "destination_row_sha256_by_id",
    )
    ingress_rows = _require_object(
        current_inputs.get("ingress_row_sha256_by_id"),
        "ingress_row_sha256_by_id",
    )
    destination_id = str(destination["destination_id"])
    ingress_id = str(ingress["zoneline_id"])
    destination_hash = destination_row_sha256(destination)
    ingress_hash = ingress_row_sha256(ingress)
    if destination_rows.get(destination_id) != destination_hash:
        raise RouteEvidenceError("stale-destination-row")
    if ingress_rows.get(ingress_id) != ingress_hash:
        raise RouteEvidenceError("stale-ingress-row")
    result = {field: current_inputs.get(field) for field in _GLOBAL_INPUT_FIELDS}
    for field in (
        "mesh_sha256",
        "ffxinav_sha256",
        "policy_sha256",
        "transition_registry_sha256",
        "destinations_sha256",
        "graph_sha256",
    ):
        _require_sha256(result[field], field)
    _require_int(result["probe_schema"], "probe_schema", minimum=1)
    for field in ("mesh_name", "probe_protocol", "policy_revision"):
        _require_string(result[field], field)
    if destination.get("_catalog_sha256") != result["destinations_sha256"]:
        raise RouteEvidenceError("stale-destinations")
    if ingress.get("_catalog_sha256") != result["graph_sha256"]:
        raise RouteEvidenceError("stale-graph")
    result["destination_row_sha256"] = destination_hash
    result["ingress_row_sha256"] = ingress_hash
    result["zone_mesh_name"] = mesh_name
    return result


def _validate_leg_geometry(
    candidate: Mapping[str, Any],
    destination: Mapping[str, Any],
    ingress: Mapping[str, Any],
    request: Mapping[str, Any],
) -> tuple[bool, str]:
    matched, reason = _candidate_matches_destination(candidate, destination)
    if not matched:
        return False, reason
    directed, reason = validate_directed_prefix(
        (ingress,), target_zone=int(candidate.get("zone", -2))
    )
    if not directed:
        return False, reason
    ingress_end = [ingress.get("to_x"), ingress.get("to_z"), ingress.get("to_y")]
    request_start = [request.get("start", {}).get(key) for key in ("x", "z", "y")]
    destination_point = [destination.get(key) for key in ("x", "z", "y")]
    request_end = [request.get("end", {}).get(key) for key in ("x", "z", "y")]
    if ingress_end != request_start:
        return False, "ingress-endpoint-mismatch"
    if destination_point != request_end:
        return False, "destination-endpoint-mismatch"
    return True, "bound"


def physical_leg_reuse_key(evidence: Mapping[str, Any]) -> str:
    root = {
        "inputs": copy.deepcopy(evidence.get("inputs")),
        "leg": copy.deepcopy(evidence.get("leg")),
        "probe_request": copy.deepcopy(evidence.get("probe_request")),
        "observations": copy.deepcopy(evidence.get("observations")),
    }
    return _sha256_bytes(_canonical_json(root))


_LOCAL_EVIDENCE_FIELDS = {
    "schema",
    "evidence_id",
    "request_id",
    "candidate_id",
    "action_id",
    "group_id",
    "status",
    "reason",
    "leg",
    "inputs",
    "probe_request",
    "observations",
    "required_transition_ids",
}


def _raw_probe_response(observation: Mapping[str, Any]) -> dict[str, Any]:
    row = copy.deepcopy(dict(observation))
    if row.get("status") != "mesh-proven":
        raise RouteEvidenceError("Only a current mesh-proven observation can be bound.")
    probe_status = row.pop("probe_status", None)
    if probe_status not in _PROBE_STATUSES:
        raise RouteEvidenceError("Classified observation lacks its exact native probe status.")
    row["status"] = probe_status
    row.pop("reason", None)
    row.pop("recomputed_path_length", None)
    return row


def bind_local_leg_evidence(
    *,
    candidate: Mapping[str, Any],
    destination: Mapping[str, Any],
    ingress: Mapping[str, Any],
    request: Mapping[str, Any],
    observation: Mapping[str, Any],
    current_inputs: Mapping[str, Any],
    required_transition_ids: Sequence[str],
    policy: RouteProofPolicy,
    transition_definitions: Sequence[Mapping[str, Any]] = (),
) -> dict[str, Any]:
    raw_observation = _raw_probe_response(observation)
    validated_observation = _validate_probe_response(request, raw_observation)
    reclassified = classify_probe_observation(
        request,
        validated_observation,
        policy,
        declared_transitions=tuple(
            definition
            for definition in transition_definitions
            if int(definition.get("zone", -1)) == int(candidate.get("zone", -2))
        ),
    )
    if reclassified.get("status") != "mesh-proven":
        raise RouteEvidenceError(str(reclassified.get("reason") or "probe-observation-rejected"))
    bound, reason = _validate_leg_geometry(candidate, destination, ingress, request)
    if not bound:
        raise RouteEvidenceError(reason)
    inputs = _selected_evidence_inputs(
        candidate=candidate,
        destination=destination,
        ingress=ingress,
        current_inputs=current_inputs,
    )
    if request.get("mesh_sha256") != inputs["mesh_sha256"]:
        raise RouteEvidenceError("stale-mesh")
    if request.get("ffxinav_sha256") != inputs["ffxinav_sha256"]:
        raise RouteEvidenceError("stale-ffxinav")
    if request.get("policy_sha256") != inputs["policy_sha256"]:
        raise RouteEvidenceError("stale-policy")
    if inputs["policy_sha256"] != policy_sha256(policy):
        raise RouteEvidenceError("stale-policy")
    if request.get("protocol") != inputs["probe_protocol"] or request.get("schema") != inputs["probe_schema"]:
        raise RouteEvidenceError("stale-probe-protocol")
    if request.get("policy_revision") != inputs["policy_revision"]:
        raise RouteEvidenceError("stale-policy-revision")
    if PurePosixPath(str(request.get("mesh_relative_path", ""))).name != inputs["mesh_name"]:
        raise RouteEvidenceError("zone-mesh-mismatch")
    evidence: dict[str, Any] = {
        "schema": 2,
        "evidence_id": "",
        "request_id": str(request["request_id"]),
        "candidate_id": str(candidate["candidate_id"]),
        "action_id": str(candidate["action_id"]),
        "group_id": str(candidate.get("group_id", "")),
        "status": "mesh-proven",
        "reason": "mesh-proven",
        "leg": {
            "zone": int(candidate["zone"]),
            "destination_id": str(destination["destination_id"]),
            "zoneline_id": int(ingress["zoneline_id"]),
            "from": [
                int(ingress["from_zone"]),
                float(ingress["from_x"]),
                float(ingress["from_z"]),
                float(ingress["from_y"]),
            ],
            "to": [
                int(ingress["to_zone"]),
                float(ingress["to_x"]),
                float(ingress["to_z"]),
                float(ingress["to_y"]),
            ],
            "destination": [float(destination[key]) for key in ("x", "z", "y")],
        },
        "inputs": inputs,
        "probe_request": copy.deepcopy(dict(request)),
        "observations": validated_observation,
        "required_transition_ids": tuple(sorted(set(required_transition_ids))),
    }
    evidence["evidence_id"] = "mesh:v2:" + physical_leg_reuse_key(evidence)
    return evidence


def _stale_reason(field: str) -> str:
    return f"stale-{field.removesuffix('_sha256').replace('_', '-')}"


def validate_local_leg_evidence(
    evidence: Mapping[str, Any],
    *,
    candidate: Mapping[str, Any],
    destination: Mapping[str, Any],
    ingress: Mapping[str, Any],
    current_inputs: Mapping[str, Any],
    policy: RouteProofPolicy,
    transition_definitions: Sequence[Mapping[str, Any]] = (),
) -> tuple[bool, str]:
    try:
        row = _require_object(evidence, "local-leg evidence")
        _require_exact_fields(row, _LOCAL_EVIDENCE_FIELDS, "local-leg evidence")
        if _require_int(row.get("schema"), "local-leg evidence schema") != 2:
            return False, "local-evidence-schema-mismatch"
        if evidence.get("status") != "mesh-proven":
            return False, str(evidence.get("reason") or "not-mesh-proven")
        _require_string(evidence.get("candidate_id"), "origin candidate_id")
        _require_string(evidence.get("action_id"), "origin action_id")
        if not isinstance(evidence.get("group_id"), str):
            return False, "origin-group-id-malformed"
        probe_request = _require_object(evidence.get("probe_request"), "probe_request")
        if probe_request.get("request_id") != evidence.get("request_id"):
            return False, "request-id-mismatch"
        bound, reason = _validate_leg_geometry(
            candidate, destination, ingress, probe_request
        )
        if not bound:
            return False, reason
        if evidence["leg"].get("zone") != candidate.get("zone"):
            return False, "leg-zone-mismatch"
        if evidence["leg"].get("destination_id") != destination.get("destination_id"):
            return False, "leg-destination-mismatch"
        if evidence["leg"].get("zoneline_id") != ingress.get("zoneline_id"):
            return False, "leg-ingress-mismatch"
        expected_inputs = _selected_evidence_inputs(
            candidate=candidate,
            destination=destination,
            ingress=ingress,
            current_inputs=current_inputs,
        )
        if expected_inputs["policy_sha256"] != policy_sha256(policy):
            return False, "stale-policy"
        if set(_require_object(evidence.get("inputs"), "evidence inputs")) != set(expected_inputs):
            return False, "evidence-input-set-mismatch"
        for field, expected in expected_inputs.items():
            if evidence.get("inputs", {}).get(field) != expected:
                return False, _stale_reason(field)
        request_checks = (
            ("mesh_sha256", expected_inputs["mesh_sha256"]),
            ("ffxinav_sha256", expected_inputs["ffxinav_sha256"]),
            ("protocol", expected_inputs["probe_protocol"]),
            ("schema", expected_inputs["probe_schema"]),
            ("policy_revision", expected_inputs["policy_revision"]),
            ("policy_sha256", expected_inputs["policy_sha256"]),
        )
        _require_exact_fields(probe_request, _REQUEST_FIELDS, "persisted probe request")
        for field, expected in request_checks:
            if probe_request.get(field) != expected:
                return False, _stale_reason(field)
        if PurePosixPath(str(probe_request.get("mesh_relative_path", ""))).name != expected_inputs["mesh_name"]:
            return False, "zone-mesh-mismatch"
        if probe_request.get("op") != "FindPath":
            return False, "probe-op-mismatch"
        if probe_request.get("zone") != candidate.get("zone"):
            return False, "probe-zone-mismatch"
        if probe_request.get("thresholds") != dict(policy.thresholds):
            return False, "probe-thresholds-mismatch"
        validated_observation = _validate_probe_response(
            probe_request,
            _require_object(evidence.get("observations"), "observations"),
        )
        classification = classify_probe_observation(
            probe_request,
            validated_observation,
            policy,
            declared_transitions=tuple(
                definition
                for definition in transition_definitions
                if int(definition.get("zone", -1)) == int(candidate.get("zone", -2))
            ),
        )
        if classification.get("status") != "mesh-proven":
            return False, str(classification.get("reason") or "observation-not-mesh-proven")
        if evidence.get("evidence_id") != "mesh:v2:" + physical_leg_reuse_key(evidence):
            return False, "evidence-id-mismatch"
    except (KeyError, TypeError, ValueError, RouteEvidenceError) as error:
        reason = str(error)
        return False, reason if reason else "malformed-evidence"
    return True, "mesh-proven"


def merge_evidence(rows: Sequence[Mapping[str, Any]]) -> tuple[dict[str, Any], ...]:
    by_id: dict[str, dict[str, Any]] = {}
    for raw in rows:
        row = copy.deepcopy(dict(raw))
        evidence_id = _require_string(row.get("evidence_id"), "evidence_id")
        previous = by_id.get(evidence_id)
        if previous is not None and previous != row:
            raise RouteEvidenceError(f"Conflicting evidence rows share {evidence_id!r}.")
        by_id[evidence_id] = row
    return tuple(by_id[key] for key in sorted(by_id))


def select_shortest_contract(
    contracts: Sequence[Mapping[str, Any]], candidate_id: str
) -> Mapping[str, Any]:
    matches = [row for row in contracts if row.get("candidate_id") == candidate_id]
    if not matches:
        raise RouteEvidenceError(f"No route contract exists for {candidate_id!r}.")
    return min(
        matches,
        key=lambda row: (
            float(row["local_leg"]["observations"]["path_length"]),
            str(row["contract_id"]),
        ),
    )


def _lua_module(name: str, rows: Sequence[Mapping[str, Any]], field: str) -> str:
    ordered = sorted((copy.deepcopy(dict(row)) for row in rows), key=lambda row: str(row[field]))
    lines = [
        "-- Generated by tools/objective_guides/route_evidence.py. Do not edit.",
        f"local {name} = {_lua_value(ordered)}",
        f"return {name}",
        "",
    ]
    return "\n".join(lines)


def render_contracts_lua(contracts: Sequence[Mapping[str, Any]]) -> str:
    ids = [str(row.get("contract_id", "")) for row in contracts]
    if any(not value for value in ids) or len(ids) != len(set(ids)):
        raise RouteEvidenceError("Route contract IDs must be nonempty and unique.")
    return _lua_module("contracts", contracts, "contract_id")


def render_transitions_lua(
    transitions: Sequence[Mapping[str, Any]],
    *,
    source_registry_sha256: str,
    definitions: Sequence[Mapping[str, Any]] | None = None,
) -> str:
    authorized_ids = [str(row.get("transition_id", "")) for row in transitions]
    if any(not value for value in authorized_ids) or len(authorized_ids) != len(set(authorized_ids)):
        raise RouteEvidenceError("Authorized transition IDs must be nonempty and unique.")
    definition_rows = transitions if definitions is None else definitions
    definition_ids = [str(row.get("transition_id", "")) for row in definition_rows]
    if any(not value for value in definition_ids) or len(definition_ids) != len(set(definition_ids)):
        raise RouteEvidenceError("Transition definition IDs must be nonempty and unique.")
    definition_by_id = {
        str(row["transition_id"]): copy.deepcopy(dict(row)) for row in definition_rows
    }
    for row in transitions:
        transition_id = str(row["transition_id"])
        if definition_by_id.get(transition_id) != dict(row):
            raise RouteEvidenceError(
                f"Authorized transition {transition_id!r} differs from its rooted definition."
            )
    digest = _require_sha256(source_registry_sha256, "transition source registry sha256")
    ordered_definitions = sorted(
        definition_by_id.values(), key=lambda row: str(row["transition_id"])
    )
    ordered_authorized = sorted(
        (copy.deepcopy(dict(row)) for row in transitions),
        key=lambda row: str(row["transition_id"]),
    )
    return "\n".join(
        (
            "-- Generated by tools/objective_guides/route_evidence.py. Do not edit.",
            "local transitions = {",
            "  schema_version = 2,",
            f"  source_registry_sha256 = {_lua_quote(digest)},",
            f"  definitions = {_lua_value(ordered_definitions)},",
            f"  authorized = {_lua_value(ordered_authorized)},",
            "}",
            "return transitions",
            "",
        )
    )


def render_probe_results(
    requests: Sequence[Mapping[str, Any]],
    observations: Sequence[Mapping[str, Any]],
    policy: RouteProofPolicy,
) -> bytes:
    request_by_id = {str(row["request_id"]): row for row in requests}
    observation_by_id = {str(row["request_id"]): row for row in observations}
    if len(request_by_id) != len(requests) or len(observation_by_id) != len(observations):
        raise RouteEvidenceError("Duplicate request IDs in probe result rendering.")
    if set(request_by_id) != set(observation_by_id):
        raise RouteEvidenceError("Probe result rendering has missing or unexpected rows.")
    result = [
        classify_probe_observation(request_by_id[key], observation_by_id[key], policy)
        for key in sorted(request_by_id)
    ]
    return b"".join(_canonical_json(row) for row in result)


def load_jsonl(path: Path) -> tuple[dict[str, Any], ...]:
    try:
        payload = path.read_text(encoding="utf-8")
    except OSError as error:
        raise RouteEvidenceError(f"Could not read JSONL {path}: {error}") from error
    rows: list[dict[str, Any]] = []
    for index, line in enumerate(payload.splitlines(), start=1):
        if not line.strip():
            raise RouteEvidenceError(f"Blank JSONL row at {path}:{index}.")
        rows.append(dict(_require_object(_strict_json(line), f"{path}:{index}")))
    return tuple(rows)


def _parse_transition_definitions(
    payload: bytes, *, source: str
) -> tuple[dict[str, Any], ...]:
    try:
        root = _strict_json(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RouteEvidenceError(f"Could not parse transition definitions {source}: {error}") from error
    if isinstance(root, Mapping):
        rows = root.get("transitions")
    else:
        rows = root
    if not isinstance(rows, list) or any(not isinstance(row, Mapping) for row in rows):
        raise RouteEvidenceError("Transition definition file must contain a transitions array.")
    result = tuple(copy.deepcopy(dict(row)) for row in rows)
    ids = [str(row.get("transition_id", "")) for row in result]
    if any(not value for value in ids) or len(ids) != len(set(ids)):
        raise RouteEvidenceError("Transition definition IDs must be nonempty and unique.")
    return tuple(sorted(result, key=lambda row: row["transition_id"]))


def load_transition_definitions(path: Path) -> tuple[dict[str, Any], ...]:
    try:
        payload = path.read_bytes()
    except OSError as error:
        raise RouteEvidenceError(f"Could not read transition definitions {path}: {error}") from error
    return _parse_transition_definitions(payload, source=str(path))


_TRANSITION_EVIDENCE_FIELDS = {
    "schema",
    "transition_evidence_id",
    "transition_id",
    "status",
    "direction",
    "zone",
    "pre_anchor",
    "post_anchor",
    "interaction",
    "observed_live_state",
    "timeout_seconds",
    "timeout_result",
    "cancellation_observed",
    "trace",
    "inputs",
}


def transition_evidence_id(evidence: Mapping[str, Any]) -> str:
    payload = copy.deepcopy(dict(evidence))
    payload.pop("transition_evidence_id", None)
    return "transition:v2:" + _sha256_bytes(_canonical_json(payload))


def validate_transition_evidence(
    definition: Mapping[str, Any],
    evidence: Mapping[str, Any],
    current_inputs: Mapping[str, Any],
) -> tuple[bool, str]:
    try:
        row = _require_object(evidence, "transition evidence")
        _require_exact_fields(row, _TRANSITION_EVIDENCE_FIELDS, "transition evidence")
        if _require_int(row.get("schema"), "transition schema") != 2:
            return False, "transition-schema-mismatch"
        evidence_id = _require_string(
            row.get("transition_evidence_id"), "transition_evidence_id"
        )
        if evidence_id != transition_evidence_id(row):
            return False, "transition-evidence-id-mismatch"
        cancellation = row.get("cancellation_observed")
        expected_cancellation = definition.get("cancellation")
        if (
            not isinstance(cancellation, list)
            or not isinstance(expected_cancellation, list)
            or cancellation != expected_cancellation
            or len(cancellation) != len(set(cancellation))
        ):
            return False, "transition-timeout-policy-unproven"
        if row.get("timeout_result") != "bounded-success":
            return False, "transition-timeout-policy-unproven"
        if row.get("status") != "transition-proven":
            return False, "transition-not-proven"
        comparisons = (
            ("transition_id", row.get("transition_id"), definition.get("transition_id")),
            ("direction", row.get("direction"), definition.get("direction")),
            ("zone", row.get("zone"), definition.get("zone")),
            ("pre_anchor", row.get("pre_anchor"), definition.get("pre_anchor")),
            ("post_anchor", row.get("post_anchor"), definition.get("post_anchor")),
            ("interaction", row.get("interaction"), definition.get("interaction")),
            (
                "observed_live_state",
                row.get("observed_live_state"),
                definition.get("expected_live_state"),
            ),
            ("timeout_seconds", row.get("timeout_seconds"), definition.get("timeout_seconds")),
        )
        for field, actual, expected in comparisons:
            if actual != expected:
                return False, f"transition-{field.replace('_', '-')}-mismatch"
        trace = _require_object(row.get("trace"), "transition trace")
        _require_exact_fields(trace, {"source", "sha256"}, "transition trace")
        _require_string(trace.get("source"), "transition trace source")
        _require_sha256(trace.get("sha256"), "transition trace sha256")
        inputs = _require_object(row.get("inputs"), "transition inputs")
        if set(inputs) != set(current_inputs):
            return False, "transition-input-set-mismatch"
        for field, expected in current_inputs.items():
            if inputs.get(field) != expected:
                return False, _stale_reason(field)
    except (RouteEvidenceError, TypeError, ValueError) as error:
        return False, str(error) or "malformed-transition-evidence"
    return True, "transition-proven"


def current_transition_contracts(
    definitions: Sequence[Mapping[str, Any]],
    evidence_rows: Sequence[Mapping[str, Any]],
    policy: RouteProofPolicy,
    *,
    current_inputs: Mapping[str, Any],
) -> tuple[dict[str, Any], ...]:
    if current_inputs.get("policy_sha256") != policy_sha256(policy):
        raise RouteEvidenceError("Independent transition inputs do not match the route policy.")
    evidence_by_transition: dict[str, list[Mapping[str, Any]]] = {}
    for row in evidence_rows:
        evidence_by_transition.setdefault(str(row.get("transition_id", "")), []).append(row)
    accepted: list[dict[str, Any]] = []
    for definition in definitions:
        matches = []
        for evidence in evidence_by_transition.get(str(definition.get("transition_id", "")), ()):
            if validate_transition_evidence(definition, evidence, current_inputs)[0]:
                matches.append(evidence)
        if len(matches) == 1:
            accepted.append(copy.deepcopy(dict(definition)))
        elif len(matches) > 1:
            raise RouteEvidenceError(
                f"Transition {definition.get('transition_id')!r} has multiple current proofs."
            )
    return tuple(sorted(accepted, key=lambda row: str(row["transition_id"])))


def _transition_current_inputs(current_inputs: Mapping[str, Any]) -> dict[str, Any]:
    return {
        key: current_inputs[key]
        for key in (
            "policy_sha256",
            "transition_registry_sha256",
            "mesh_sha256",
            "ffxinav_sha256",
            "destinations_sha256",
            "graph_sha256",
        )
    }


def _required_transition_definitions(
    candidate: Mapping[str, Any],
    destination: Mapping[str, Any],
    definitions: Sequence[Mapping[str, Any]],
) -> tuple[Mapping[str, Any], ...]:
    destination_id = str(destination.get("destination_id", ""))
    transport_id = str(candidate.get("transport_id", "")).strip()
    zone = int(candidate.get("zone", -1))
    result = []
    for definition in definitions:
        if int(definition.get("zone", -2)) != zone:
            continue
        destination_owned = destination_id in tuple(
            str(value) for value in definition.get("required_destination_ids", ())
        )
        required_transport = str(definition.get("required_transport_id", "")).strip()
        transport_owned = bool(
            transport_id
            and required_transport
            and transport_id == required_transport
        )
        if destination_owned or transport_owned:
            result.append(definition)
    return tuple(sorted(result, key=lambda row: str(row.get("transition_id", ""))))


def build_route_contracts(
    *,
    candidates: Sequence[Mapping[str, Any]],
    destinations: Sequence[Mapping[str, Any]],
    ingresses: Sequence[Mapping[str, Any]],
    evidence: Sequence[Mapping[str, Any]],
    transition_definitions: Sequence[Mapping[str, Any]],
    transition_evidence: Sequence[Mapping[str, Any]],
    current_inputs: Mapping[str, Any],
    policy: RouteProofPolicy,
) -> tuple[tuple[dict[str, Any], ...], tuple[dict[str, Any], ...]]:
    candidate_by_id = {str(row.get("candidate_id", "")): row for row in candidates}
    if len(candidate_by_id) != len(candidates) or "" in candidate_by_id:
        raise RouteEvidenceError("Typed candidate IDs must be nonempty and unique.")
    destination_by_id: dict[str, Mapping[str, Any]] = {}
    for row in destinations:
        destination_id = str(row.get("destination_id", ""))
        if not destination_id:
            continue
        if destination_id in destination_by_id:
            raise RouteEvidenceError(f"Duplicate destination ID {destination_id!r}.")
        destination_by_id[destination_id] = row
    ingress_by_id = {int(row["zoneline_id"]): row for row in ingresses}
    if len(ingress_by_id) != len(ingresses):
        raise RouteEvidenceError("Duplicate directed ingress IDs.")
    trusted_physical: list[Mapping[str, Any]] = []
    for row in merge_evidence(evidence):
        destination = destination_by_id.get(str(row.get("leg", {}).get("destination_id", "")))
        ingress = ingress_by_id.get(int(row.get("leg", {}).get("zoneline_id", -1)))
        if destination is None or ingress is None:
            continue
        current_owners = sorted(
            (
                candidate
                for candidate in candidates
                if str(candidate.get("destination_id", ""))
                == str(destination.get("destination_id", ""))
            ),
            key=lambda candidate: str(candidate.get("candidate_id", "")),
        )
        if any(
            validate_local_leg_evidence(
                row,
                candidate=owner,
                destination=destination,
                ingress=ingress,
                current_inputs=current_inputs,
                policy=policy,
                transition_definitions=transition_definitions,
            )[0]
            for owner in current_owners
        ):
            trusted_physical.append(row)
    transition_by_id = {
        str(row.get("transition_id", "")): row for row in transition_definitions
    }
    if len(transition_by_id) != len(transition_definitions) or "" in transition_by_id:
        raise RouteEvidenceError("Transition definition IDs must be nonempty and unique.")
    transition_rows_by_id: dict[str, list[Mapping[str, Any]]] = {}
    for row in transition_evidence:
        transition_rows_by_id.setdefault(str(row.get("transition_id", "")), []).append(row)
    transition_current = _transition_current_inputs(current_inputs)
    contracts: list[dict[str, Any]] = []
    unresolved: list[dict[str, Any]] = []
    for candidate in sorted(candidates, key=lambda row: str(row["candidate_id"])):
        destination = destination_by_id.get(str(candidate.get("destination_id", "")))
        if destination is None or not _candidate_matches_destination(candidate, destination)[0]:
            unresolved.append(
                {
                    "candidate_id": candidate["candidate_id"],
                    "action_id": candidate["action_id"],
                    "status": "unresolved",
                    "reason": "immutable-destination-unavailable",
                }
            )
            continue
        required_definitions = _required_transition_definitions(
            candidate, destination, transition_definitions
        )
        transition_proofs: list[Mapping[str, Any]] = []
        missing_transition = False
        for definition in required_definitions:
            matches = [
                row for row in transition_rows_by_id.get(definition["transition_id"], ())
                if validate_transition_evidence(definition, row, transition_current)[0]
            ]
            if len(matches) != 1:
                missing_transition = True
                break
            transition_proofs.append(matches[0])
        if missing_transition:
            unresolved.append(
                {
                    "candidate_id": candidate["candidate_id"],
                    "action_id": candidate["action_id"],
                    "status": "unresolved",
                    "reason": "missing-current-transition-evidence",
                }
            )
            continue
        candidate_legs = [
            row for row in trusted_physical
            if row["leg"]["destination_id"] == destination["destination_id"]
        ]
        if not candidate_legs:
            unresolved.append(
                {
                    "candidate_id": candidate["candidate_id"],
                    "action_id": candidate["action_id"],
                    "status": "unresolved",
                    "reason": "missing-current-local-leg-evidence",
                }
            )
            continue
        transition_ids = tuple(sorted(definition["transition_id"] for definition in required_definitions))
        transition_evidence_ids = tuple(
            sorted(row["transition_evidence_id"] for row in transition_proofs)
        )
        for local_leg in candidate_legs:
            identity = {
                "candidate_id": candidate["candidate_id"],
                "action_id": candidate["action_id"],
                "group_id": candidate.get("group_id", ""),
                "physical_leg_key": physical_leg_reuse_key(local_leg),
                "transition_evidence_ids": transition_evidence_ids,
            }
            contracts.append(
                {
                    "schema": 2,
                    "contract_id": "route:v2:" + _sha256_bytes(_canonical_json(identity)),
                    "candidate_id": candidate["candidate_id"],
                    "action_id": candidate["action_id"],
                    "group_id": candidate.get("group_id", ""),
                    "destination_id": destination["destination_id"],
                    "zone": int(destination["zone"]),
                    "destination": {
                        key: destination[key]
                        for key in (
                            "name",
                            "x",
                            "z",
                            "y",
                            "kind",
                            "destination_id",
                            "raw_identity",
                            "raw_spawn_ids",
                            "cluster_policy_version",
                        )
                    },
                    "authorized_directed_prefix": (int(local_leg["leg"]["zoneline_id"]),),
                    "local_leg": copy.deepcopy(dict(local_leg)),
                    "required_transition_ids": transition_ids,
                    "transition_evidence_ids": transition_evidence_ids,
                    "expected_inputs": copy.deepcopy(dict(local_leg["inputs"])),
                    "route_ready": True,
                }
            )
    contract_ids = [row["contract_id"] for row in contracts]
    if len(contract_ids) != len(set(contract_ids)):
        raise RouteEvidenceError("Duplicate generated route contract ID.")
    return (
        tuple(sorted(contracts, key=lambda row: row["contract_id"])),
        tuple(sorted(unresolved, key=lambda row: (row["candidate_id"], row["reason"]))),
    )


def compile_route_contracts_by_zone(
    *,
    candidates: Sequence[Mapping[str, Any]],
    destinations: Sequence[Mapping[str, Any]],
    ingresses: Sequence[Mapping[str, Any]],
    evidence: Sequence[Mapping[str, Any]],
    transition_definitions: Sequence[Mapping[str, Any]],
    transition_evidence: Sequence[Mapping[str, Any]],
    current_inputs_by_zone: Mapping[int | str, Mapping[str, Any]],
    policy: RouteProofPolicy,
) -> dict[str, tuple[dict[str, Any], ...]]:
    """Compile independently hash-bound zone batches into one deterministic result."""

    candidate_rows = tuple(copy.deepcopy(dict(row)) for row in candidates)
    candidate_ids = [str(row.get("candidate_id", "")) for row in candidate_rows]
    if any(not candidate_id for candidate_id in candidate_ids) or len(candidate_ids) != len(set(candidate_ids)):
        raise RouteEvidenceError("Typed route candidates must have nonempty unique IDs.")
    contracts: list[dict[str, Any]] = []
    unresolved: list[dict[str, Any]] = []
    zones = sorted({int(row.get("zone", -1)) for row in candidate_rows})
    for zone in zones:
        zone_candidates = tuple(row for row in candidate_rows if int(row.get("zone", -1)) == zone)
        matches = [value for key, value in current_inputs_by_zone.items() if str(key) == str(zone)]
        if len(matches) != 1:
            unresolved.extend(
                {
                    "candidate_id": row["candidate_id"],
                    "action_id": row["action_id"],
                    "status": "unresolved",
                    "reason": "zone-proof-inputs-unavailable",
                }
                for row in zone_candidates
            )
            continue
        zone_transition_definitions = tuple(
            row for row in transition_definitions if int(row.get("zone", -1)) == zone
        )
        zone_transition_ids = {
            str(row.get("transition_id", "")) for row in zone_transition_definitions
        }
        zone_contracts, zone_unresolved = build_route_contracts(
            candidates=zone_candidates,
            destinations=tuple(row for row in destinations if int(row.get("zone", -1)) == zone),
            ingresses=tuple(row for row in ingresses if int(row.get("to_zone", -1)) == zone),
            evidence=tuple(row for row in evidence if int(row.get("leg", {}).get("zone", -1)) == zone),
            transition_definitions=zone_transition_definitions,
            transition_evidence=tuple(
                row
                for row in transition_evidence
                if str(row.get("transition_id", "")) in zone_transition_ids
            ),
            current_inputs=matches[0],
            policy=policy,
        )
        contracts.extend(zone_contracts)
        unresolved.extend(zone_unresolved)
    contract_ids = [row["contract_id"] for row in contracts]
    if len(contract_ids) != len(set(contract_ids)):
        raise RouteEvidenceError("Zone compilation produced duplicate route contract IDs.")
    return {
        "contracts": tuple(sorted(contracts, key=lambda row: row["contract_id"])),
        "unresolved": tuple(
            sorted(unresolved, key=lambda row: (row["candidate_id"], row["reason"]))
        ),
    }


def _review_row(
    request_id: str,
    reason: str,
    *,
    source: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    root = {
        "schema": 2,
        "evidence_id": "",
        "request_id": request_id,
        "status": "rejected" if not reason.startswith("stale-") else "stale",
        "reason": reason,
    }
    if source is not None:
        root["source_evidence_id"] = source.get("evidence_id", "")
    root["evidence_id"] = "review:v2:" + _sha256_bytes(_canonical_json(root))
    return root


_REVIEWED_ZONE_MESH_NAMES = {
    # Exact addon-owned bindings mirrored from modules/navigation_data.lua.
    105: "Batallia_Downs.nav",
    110: "Rolanberry_Fields.nav",
    120: "Sauromugue_Champaign.nav",
    126: "Qufim_Island.nav",
    195: "The_Eldieme_Necropolis.nav",
    230: "Southern_San_dOria.nav",
    231: "Northern_San_dOria.nav",
    232: "Port_San_dOria.nav",
    243: "RuLude_Gardens.nav",
    244: "Upper_Jeuno.nav",
    245: "Lower_Jeuno.nav",
    246: "Port_Jeuno.nav",
}


def _discover_zone_mesh_name(
    zone: int, zone_name: str, third_party_root: Path
) -> str:
    mesh_root = Path(third_party_root) / "xiNavmeshes"
    if not mesh_root.is_dir():
        raise RouteEvidenceError(f"Zone mesh directory is missing: {mesh_root}")
    reviewed_name = _REVIEWED_ZONE_MESH_NAMES.get(int(zone))
    if reviewed_name is None:
        reviewed_name = _require_string(zone_name, "zone name").replace(" ", "_") + ".nav"
    _validate_relative_dependency_path(
        f"xiNavmeshes/{reviewed_name}", "zone-derived mesh path"
    )
    allowed = {reviewed_name.casefold(), f"{int(zone)}.nav".casefold()}
    matches = sorted(
        path.name for path in mesh_root.glob("*.nav") if path.name.casefold() in allowed
    )
    if len(matches) != 1:
        raise RouteEvidenceError(
            f"Zone {zone} {zone_name!r} has {len(matches)} exact allowed mesh matches."
        )
    return matches[0]


def prepare_route_proof_batches(
    *,
    candidates: Sequence[Mapping[str, Any]],
    catalogue: Mapping[str, Any],
    policy: RouteProofPolicy,
    third_party_root: Path,
    transition_registry_sha256: str,
    transition_definitions: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    """Create deterministic target-zone FindPath batches from typed Task 3 rows."""

    dependency_root = validate_dependency_root(third_party_root)
    dll = dependency_root / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
    if not dll.is_file():
        raise RouteEvidenceError(f"Pinned FFXINAV DLL is missing: {dll}")
    ffxinav_sha256 = _sha256_bytes(dll.read_bytes())
    transition_digest = _require_sha256(
        transition_registry_sha256, "transition_registry_sha256"
    )
    destinations = tuple(
        dict(_require_object(row, "route destination"))
        for row in catalogue.get("destinations", ())
    )
    ingresses = tuple(
        dict(_require_object(row, "directed ingress"))
        for row in catalogue.get("ingresses", ())
    )
    destinations_sha256 = _require_sha256(
        catalogue.get("destinations_sha256"), "destinations catalogue hash"
    )
    graph_sha256 = _require_sha256(
        catalogue.get("graph_sha256"), "directed graph hash"
    )
    destination_by_id = {
        str(row.get("destination_id", "")): row
        for row in destinations
        if str(row.get("destination_id", ""))
    }
    if len(destination_by_id) != sum(
        bool(str(row.get("destination_id", ""))) for row in destinations
    ):
        raise RouteEvidenceError("Route catalogue contains duplicate destination IDs.")
    candidate_rows = tuple(
        sorted(
            (copy.deepcopy(dict(row)) for row in candidates),
            key=lambda row: str(row.get("candidate_id", "")),
        )
    )
    candidate_ids = [str(row.get("candidate_id", "")) for row in candidate_rows]
    if any(not value for value in candidate_ids) or len(candidate_ids) != len(set(candidate_ids)):
        raise RouteEvidenceError("Typed route candidate IDs must be nonempty and unique.")

    eligible_by_zone: dict[int, list[tuple[dict[str, Any], dict[str, Any]]]] = {}
    unresolved: list[dict[str, Any]] = []
    for candidate in candidate_rows:
        reason = ""
        if candidate.get("route_ready") is not False:
            reason = "typed-candidate-route-state-invalid"
        destination = destination_by_id.get(str(candidate.get("destination_id", "")))
        if not reason and destination is None:
            reason = "immutable-destination-unavailable"
        if not reason and not _candidate_matches_destination(candidate, destination)[0]:
            reason = "immutable-destination-mismatch"
        if reason:
            unresolved.append(
                {
                    "candidate_id": candidate["candidate_id"],
                    "action_id": candidate.get("action_id", ""),
                    "status": "unresolved",
                    "reason": reason,
                }
            )
            continue
        eligible_by_zone.setdefault(int(candidate["zone"]), []).append(
            (candidate, destination)
        )

    zone_mesh_names: dict[int, str] = {}
    prepared_zones: set[int] = set()
    for zone, pairs in sorted(eligible_by_zone.items()):
        zone_names = {str(candidate.get("zone_name", "")).strip() for candidate, _ in pairs}
        if len(zone_names) != 1 or not next(iter(zone_names), ""):
            for candidate, _destination in pairs:
                unresolved.append(
                    {
                        "candidate_id": candidate["candidate_id"],
                        "action_id": candidate.get("action_id", ""),
                        "status": "unresolved",
                        "reason": "zone-mesh-unavailable",
                    }
                )
            continue
        try:
            zone_mesh_names[zone] = _discover_zone_mesh_name(
                zone, next(iter(zone_names)), dependency_root
            )
        except RouteEvidenceError:
            for candidate, _destination in pairs:
                unresolved.append(
                    {
                        "candidate_id": candidate["candidate_id"],
                        "action_id": candidate.get("action_id", ""),
                        "status": "unresolved",
                        "reason": "zone-mesh-unavailable",
                    }
                )
            continue
        proven_ingresses = tuple(
            row
            for row in ingresses
            if int(row.get("to_zone", -1)) == zone
            and str(row.get("confidence", "")).casefold() == "proven"
            and validate_directed_prefix((row,), target_zone=zone)[0]
        )
        if not proven_ingresses:
            for candidate, _destination in pairs:
                unresolved.append(
                    {
                        "candidate_id": candidate["candidate_id"],
                        "action_id": candidate.get("action_id", ""),
                        "status": "unresolved",
                        "reason": "no-proven-directed-ingress",
                    }
                )
            zone_mesh_names.pop(zone, None)
            continue
        prepared_zones.add(zone)

    destination_hashes = {
        destination_id: destination_row_sha256(row)
        for destination_id, row in destination_by_id.items()
    }
    ingress_hashes = {
        str(row["zoneline_id"]): ingress_row_sha256(row) for row in ingresses
    }
    current_inputs_by_zone: dict[str, dict[str, Any]] = {}
    legs_by_zone: dict[str, tuple[dict[str, Any], ...]] = {}
    for zone in sorted(prepared_zones):
        mesh_name = zone_mesh_names[zone]
        mesh = dependency_root / "xiNavmeshes" / mesh_name
        mesh_sha256 = _sha256_bytes(mesh.read_bytes())
        current = {
            "mesh_name": mesh_name,
            "mesh_sha256": mesh_sha256,
            "ffxinav_sha256": ffxinav_sha256,
            "probe_protocol": policy.probe_protocol,
            "probe_schema": policy.probe_schema,
            "policy_revision": policy.policy_revision,
            "policy_sha256": policy_sha256(policy),
            "destination_row_sha256_by_id": destination_hashes,
            "ingress_row_sha256_by_id": ingress_hashes,
            "transition_registry_sha256": transition_digest,
            "destinations_sha256": destinations_sha256,
            "graph_sha256": graph_sha256,
            "zone_mesh_name_by_zone": {
                str(key): value for key, value in sorted(zone_mesh_names.items())
            },
        }
        current_inputs_by_zone[str(zone)] = current
        proven_ingresses = tuple(
            row
            for row in ingresses
            if int(row.get("to_zone", -1)) == zone
            and str(row.get("confidence", "")).casefold() == "proven"
            and validate_directed_prefix((row,), target_zone=zone)[0]
        )
        legs: list[dict[str, Any]] = []
        seen_physical_legs: set[tuple[str, int]] = set()
        for candidate, destination in eligible_by_zone[zone]:
            required = _required_transition_definitions(
                candidate, destination, transition_definitions
            )
            for ingress in proven_ingresses:
                physical_key = (
                    str(destination["destination_id"]),
                    int(ingress["zoneline_id"]),
                )
                if physical_key in seen_physical_legs:
                    continue
                seen_physical_legs.add(physical_key)
                identity = {
                    "destination_id": destination["destination_id"],
                    "zoneline_id": ingress["zoneline_id"],
                    "mesh_sha256": mesh_sha256,
                    "ffxinav_sha256": ffxinav_sha256,
                    "policy_sha256": current["policy_sha256"],
                    "transition_registry_sha256": transition_digest,
                    "destinations_sha256": destinations_sha256,
                    "graph_sha256": graph_sha256,
                }
                request_id = "route-leg:v2:" + _sha256_bytes(_canonical_json(identity))
                request = build_probe_request(
                    request_id=request_id,
                    zone=zone,
                    mesh_relative_path=f"xiNavmeshes/{mesh_name}",
                    start={
                        "x": ingress["to_x"],
                        "z": ingress["to_z"],
                        "y": ingress["to_y"],
                    },
                    end={
                        "x": destination["x"],
                        "z": destination["z"],
                        "y": destination["y"],
                    },
                    mesh_sha256=mesh_sha256,
                    ffxinav_sha256=ffxinav_sha256,
                    policy=policy,
                    third_party_root=dependency_root,
                    zone_mesh_names=zone_mesh_names,
                )
                legs.append(
                    {
                        "candidate": copy.deepcopy(candidate),
                        "destination": copy.deepcopy(destination),
                        "ingress": copy.deepcopy(ingress),
                        "request": request,
                        "required_transition_ids": tuple(
                            definition["transition_id"] for definition in required
                        ),
                    }
                )
        legs_by_zone[str(zone)] = tuple(
            sorted(legs, key=lambda row: row["request"]["request_id"])
        )
    return {
        "current_inputs_by_zone": current_inputs_by_zone,
        "legs_by_zone": legs_by_zone,
        "unresolved": tuple(
            sorted(unresolved, key=lambda row: (row["candidate_id"], row["reason"]))
        ),
        "zone_mesh_names": {
            str(key): value for key, value in sorted(zone_mesh_names.items())
        },
    }


def execute_compiled_route_pipeline(
    *,
    candidates: Sequence[Mapping[str, Any]],
    catalogue: Mapping[str, Any],
    policy: RouteProofPolicy,
    third_party_root: Path,
    transition_registry_sha256: str,
    transition_definitions: Sequence[Mapping[str, Any]],
    transition_evidence: Sequence[Mapping[str, Any]],
    existing_evidence: Sequence[Mapping[str, Any]],
    refresh: bool,
    offline: bool,
    probe_runner: Callable[
        [int, Sequence[Mapping[str, Any]]], Sequence[Mapping[str, Any]]
    ],
) -> dict[str, tuple[dict[str, Any], ...]]:
    prepared = prepare_route_proof_batches(
        candidates=candidates,
        catalogue=catalogue,
        policy=policy,
        third_party_root=third_party_root,
        transition_registry_sha256=transition_registry_sha256,
        transition_definitions=transition_definitions,
    )
    existing_local = tuple(
        row
        for row in existing_evidence
        if str(row.get("status", "")) == "mesh-proven" and isinstance(row.get("leg"), Mapping)
    )
    preserved_review = [
        copy.deepcopy(dict(row))
        for row in existing_evidence
        if row not in existing_local
    ]
    accepted: list[dict[str, Any]] = []
    review: list[dict[str, Any]] = preserved_review
    for zone_text, legs in prepared["legs_by_zone"].items():
        zone = int(zone_text)
        zone_existing = tuple(
            row for row in existing_local if int(row.get("leg", {}).get("zone", -1)) == zone
        )
        result = execute_route_evidence_workflow(
            legs=legs,
            existing_evidence=zone_existing,
            current_inputs=prepared["current_inputs_by_zone"][zone_text],
            policy=policy,
            refresh=refresh,
            offline=offline,
            probe_runner=lambda requests, zone=zone: probe_runner(zone, requests),
            transition_definitions=tuple(
                row for row in transition_definitions if int(row.get("zone", -1)) == zone
            ),
        )
        accepted.extend(result["accepted"])
        review.extend(result["review"])
    accepted_rows = merge_evidence(accepted) if accepted else ()
    accepted_ids = {row["evidence_id"] for row in accepted_rows}
    review_source_ids = {
        str(row.get("source_evidence_id", ""))
        for row in review
        if str(row.get("source_evidence_id", ""))
    }
    unavailable_reason = {
        str(row["candidate_id"]): str(row["reason"])
        for row in prepared["unresolved"]
    }
    for row in existing_local:
        evidence_id = str(row.get("evidence_id", ""))
        if evidence_id in accepted_ids or evidence_id in review_source_ids:
            continue
        reason = unavailable_reason.get(
            str(row.get("candidate_id", "")), "orphaned-local-evidence"
        )
        review.append(
            _review_row(
                str(row.get("request_id", "unknown-local-evidence")),
                reason,
                source=row,
            )
        )
        review_source_ids.add(evidence_id)
    unavailable = {row["candidate_id"] for row in prepared["unresolved"]}
    compilable_candidates = tuple(
        row for row in candidates if str(row.get("candidate_id", "")) not in unavailable
    )
    compiled = compile_route_contracts_by_zone(
        candidates=compilable_candidates,
        destinations=tuple(catalogue.get("destinations", ())),
        ingresses=tuple(catalogue.get("ingresses", ())),
        evidence=accepted_rows,
        transition_definitions=transition_definitions,
        transition_evidence=transition_evidence,
        current_inputs_by_zone=prepared["current_inputs_by_zone"],
        policy=policy,
    )
    unresolved = tuple(
        sorted(
            (*prepared["unresolved"], *compiled["unresolved"]),
            key=lambda row: (row["candidate_id"], row["reason"]),
        )
    )
    current_transitions: list[dict[str, Any]] = []
    for zone_text, current in prepared["current_inputs_by_zone"].items():
        zone = int(zone_text)
        definitions = tuple(
            row for row in transition_definitions if int(row.get("zone", -1)) == zone
        )
        if not definitions:
            continue
        ids = {str(row.get("transition_id", "")) for row in definitions}
        rows = tuple(
            row for row in transition_evidence if str(row.get("transition_id", "")) in ids
        )
        current_transitions.extend(
            current_transition_contracts(
                definitions,
                rows,
                policy,
                current_inputs=_transition_current_inputs(current),
            )
        )
    review_by_id: dict[str, dict[str, Any]] = {}
    for row in review:
        evidence_id = _require_string(row.get("evidence_id"), "review evidence_id")
        previous = review_by_id.get(evidence_id)
        if previous is not None and previous != row:
            raise RouteEvidenceError(f"Conflicting review rows share {evidence_id!r}.")
        review_by_id[evidence_id] = copy.deepcopy(dict(row))
    for source in existing_local:
        source_id = str(source.get("evidence_id", ""))
        outcomes = int(source_id in accepted_ids) + sum(
            1
            for row in review_by_id.values()
            if str(row.get("source_evidence_id", "")) == source_id
        )
        if outcomes != 1:
            raise RouteEvidenceError(
                f"Prior local evidence {source_id!r} has {outcomes} current outcomes."
            )
    return {
        "accepted_evidence": accepted_rows,
        "review": tuple(review_by_id[key] for key in sorted(review_by_id)),
        "contracts": compiled["contracts"],
        "unresolved": unresolved,
        "current_transitions": tuple(
            sorted(current_transitions, key=lambda row: str(row["transition_id"]))
        ),
    }


def execute_route_evidence_workflow(
    *,
    legs: Sequence[Mapping[str, Any]],
    existing_evidence: Sequence[Mapping[str, Any]],
    current_inputs: Mapping[str, Any],
    policy: RouteProofPolicy,
    refresh: bool,
    offline: bool,
    probe_runner: Callable[[Sequence[Mapping[str, Any]]], Sequence[Mapping[str, Any]]],
    transition_definitions: Sequence[Mapping[str, Any]] = (),
) -> dict[str, tuple[dict[str, Any], ...]]:
    if refresh and offline:
        raise RouteEvidenceError("Offline route evidence workflow cannot refresh probes.")
    ordered_legs = sorted(legs, key=lambda row: str(row["request"]["request_id"]))
    accepted: list[dict[str, Any]] = []
    review: list[dict[str, Any]] = []
    pending: list[Mapping[str, Any]] = []
    existing = merge_evidence(existing_evidence)
    for leg in ordered_legs:
        candidate = leg["candidate"]
        destination = leg["destination"]
        ingress = leg["ingress"]
        request = leg["request"]
        matching = [
            row for row in existing
            if row.get("leg", {}).get("destination_id") == destination.get("destination_id")
            and row.get("leg", {}).get("zoneline_id") == ingress.get("zoneline_id")
        ]
        current: list[dict[str, Any]] = []
        stale_for_leg = False
        for row in matching:
            valid, reason = validate_local_leg_evidence(
                row,
                candidate=candidate,
                destination=destination,
                ingress=ingress,
                current_inputs=current_inputs,
                policy=policy,
                transition_definitions=transition_definitions,
            )
            if valid:
                current.append(copy.deepcopy(dict(row)))
            else:
                stale_for_leg = True
                review.append(_review_row(str(request["request_id"]), reason, source=row))
        if current:
            accepted.extend(current)
        else:
            pending.append(leg)
            if offline and not stale_for_leg:
                review.append(
                    _review_row(str(request["request_id"]), "missing-current-local-leg-evidence")
                )
    if pending and refresh:
        requests = tuple(leg["request"] for leg in pending)
        batch_accepted: list[dict[str, Any]] = []
        batch_review: list[dict[str, Any]] = []
        try:
            observations = tuple(probe_runner(requests))
            if len(observations) != len(requests):
                raise RouteEvidenceError("Probe runner returned the wrong number of observations.")
            observation_by_id = {
                str(row.get("request_id", "")): row for row in observations
            }
            if len(observation_by_id) != len(observations):
                raise RouteEvidenceError("Probe runner returned duplicate request IDs.")
            for leg in pending:
                request = leg["request"]
                request_id = str(request["request_id"])
                raw_observation = observation_by_id.get(request_id)
                if raw_observation is None:
                    raise RouteEvidenceError(f"Probe runner omitted {request_id!r}.")
                validated = _validate_probe_response(request, raw_observation)
                zone = int(leg["candidate"]["zone"])
                declared_transitions = tuple(
                    definition
                    for definition in transition_definitions
                    if int(definition.get("zone", -1)) == zone
                )
                classified = classify_probe_observation(
                    request,
                    validated,
                    policy,
                    declared_transitions=declared_transitions,
                )
                if classified["status"] == "mesh-proven":
                    batch_accepted.append(
                        bind_local_leg_evidence(
                            candidate=leg["candidate"],
                            destination=leg["destination"],
                            ingress=leg["ingress"],
                            request=request,
                            observation=classified,
                            current_inputs=current_inputs,
                            required_transition_ids=leg.get("required_transition_ids", ()),
                            policy=policy,
                            transition_definitions=transition_definitions,
                        )
                    )
                else:
                    batch_review.append(_review_row(request_id, str(classified["reason"])))
        except RouteEvidenceError:
            batch_accepted = []
            batch_review = [
                _review_row(str(leg["request"]["request_id"]), "probe-worker-failed")
                for leg in pending
            ]
        accepted.extend(batch_accepted)
        review.extend(batch_review)
    return {
        "accepted": merge_evidence(accepted),
        "review": tuple(
            sorted(
                (copy.deepcopy(dict(row)) for row in review),
                key=lambda row: (row["request_id"], row["reason"], row["evidence_id"]),
            )
        ),
    }


def render_route_evidence_jsonl(rows: Sequence[Mapping[str, Any]]) -> bytes:
    ids: set[str] = set()
    output: list[bytes] = []
    for row in sorted(rows, key=lambda item: str(item.get("evidence_id", ""))):
        evidence_id = _require_string(row.get("evidence_id"), "evidence_id")
        if evidence_id in ids:
            raise RouteEvidenceError(f"Duplicate route evidence ID {evidence_id!r}.")
        ids.add(evidence_id)
        output.append(_canonical_json(row))
    return b"".join(output)


_MANIFEST_HEADER = "relative_path\tsha256\tkind\tzone\tmesh_name\n"
_TASK4_FIXED_RUNTIME_PATHS = frozenset(
    {
        "modules/mission_quest_route_policy.lua",
        "modules/mission_quest_route_transitions.lua",
        "modules/mission_quest_route_contracts.lua",
        "data/ffxi-nav-destinations.tsv",
        "data/ffxi-nav-zoneline-graph.tsv",
        "third_party/FFXI-NavMesh-Builder/FFXINAV.dll",
    }
)
_TASK5_RUNTIME_PATH = "modules/mission_quest_route_runtime.lua"


def _canonical_runtime_path(value: Any, label: str = "runtime path") -> str:
    raw = _require_string(value, label)
    if _CONTROL.search(raw):
        raise RouteEvidenceError(f"{label} contains control characters.")
    windows = PureWindowsPath(raw)
    normalized = raw.replace("\\", "/")
    if windows.drive or windows.is_absolute() or normalized.startswith("/") or ":" in normalized:
        raise RouteEvidenceError(f"{label} must be addon-relative and cannot use ADS syntax.")
    parts = normalized.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise RouteEvidenceError(f"{label} contains an empty or traversal component.")
    return "/".join(parts)


def validate_mesh_artifact(
    artifact: Mapping[str, Any], *, zone_mesh_names: Mapping[int | str, str]
) -> dict[str, Any]:
    row = dict(artifact)
    runtime_path = _canonical_runtime_path(row.get("runtime_path"))
    zone = _require_int(row.get("zone"), "mesh zone", minimum=0)
    mesh_name = _require_string(row.get("mesh_name"), "mesh_name")
    expected = _zone_mesh_name(zone_mesh_names, zone)
    if mesh_name.casefold() != expected.casefold():
        raise RouteEvidenceError("Mesh artifact zone and mesh name disagree.")
    if PurePosixPath(runtime_path).name.casefold() != mesh_name.casefold():
        raise RouteEvidenceError("Mesh artifact runtime path and mesh name disagree.")
    source = Path(row.get("source_path", ""))
    if source.name.casefold() != mesh_name.casefold():
        raise RouteEvidenceError("Mesh artifact source path and mesh name disagree.")
    row["runtime_path"] = runtime_path
    row["zone"] = zone
    row["mesh_name"] = mesh_name
    return row


def render_runtime_manifest(
    artifacts: Sequence[Mapping[str, Any]],
    *,
    required_runtime_paths: Sequence[str],
    manifest_relative_path: str,
    runtime_ready: bool,
    referenced_mesh_names: Sequence[str] = (),
    zone_mesh_names: Mapping[int | str, str] | None = None,
    enforce_task4_required: bool = True,
) -> tuple[bytes, str]:
    manifest_path = _canonical_runtime_path(manifest_relative_path, "manifest path")
    rows: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, raw in enumerate(artifacts):
        row = dict(_require_object(raw, f"manifest artifact {index}"))
        runtime_path = _canonical_runtime_path(row.get("runtime_path"))
        alias = runtime_path.casefold()
        if alias in seen:
            raise RouteEvidenceError(f"Duplicate case-insensitive runtime path {runtime_path!r}.")
        seen.add(alias)
        if runtime_path.casefold() == manifest_path.casefold():
            raise RouteEvidenceError("Runtime manifest cannot contain itself.")
        source = Path(row.get("source_path", ""))
        if not source.is_file():
            raise RouteEvidenceError(f"Manifest source is missing: {source}")
        kind = _require_string(row.get("kind"), "manifest kind")
        supplied_digest = row.get("sha256")
        if supplied_digest is not None:
            supplied_digest = _require_sha256(supplied_digest, "artifact sha256")
        digest = _sha256_bytes(source.read_bytes())
        if supplied_digest is not None and supplied_digest != digest:
            raise RouteEvidenceError(f"Supplied artifact hash is stale for {runtime_path!r}.")
        zone = ""
        mesh_name = ""
        if kind == "mesh":
            if zone_mesh_names is not None:
                row = validate_mesh_artifact(row, zone_mesh_names=zone_mesh_names)
            else:
                zone_value = _require_int(row.get("zone"), "mesh zone", minimum=0)
                mesh_value = _require_string(row.get("mesh_name"), "mesh name")
                if PurePosixPath(runtime_path).name.casefold() != mesh_value.casefold() or source.name.casefold() != mesh_value.casefold():
                    raise RouteEvidenceError("Mesh artifact path/name mapping disagrees.")
                row["zone"] = zone_value
                row["mesh_name"] = mesh_value
            zone = str(row["zone"])
            mesh_name = str(row["mesh_name"])
        elif row.get("zone") not in (None, "") or row.get("mesh_name") not in (None, ""):
            raise RouteEvidenceError("Only mesh manifest rows may carry zone metadata.")
        rows.append(
            {
                "relative_path": runtime_path,
                "sha256": digest,
                "kind": kind,
                "zone": zone,
                "mesh_name": mesh_name,
            }
        )
    actual_paths = {row["relative_path"] for row in rows}
    caller_required = {_canonical_runtime_path(path, "required runtime path") for path in required_runtime_paths}
    if actual_paths != caller_required:
        raise RouteEvidenceError(
            f"Manifest artifact set differs from caller required set; missing={sorted(caller_required - actual_paths)}, extra={sorted(actual_paths - caller_required)}."
        )
    if enforce_task4_required:
        internally_required = set(_TASK4_FIXED_RUNTIME_PATHS)
        internally_required.update(
            f"third_party/xiNavmeshes/{_require_string(name, 'referenced mesh name')}"
            for name in referenced_mesh_names
        )
        if runtime_ready:
            internally_required.add(_TASK5_RUNTIME_PATH)
        if not internally_required.issubset(actual_paths):
            raise RouteEvidenceError(
                f"Manifest omits internally required children: {sorted(internally_required - actual_paths)}."
            )
    if runtime_ready and _TASK5_RUNTIME_PATH not in actual_paths:
        raise RouteEvidenceError("Runtime-ready manifest requires the Task 5 route runtime child.")
    if not runtime_ready and _TASK5_RUNTIME_PATH in actual_paths:
        raise RouteEvidenceError("A Task 4 manifest containing the route runtime must use runtime_ready.")
    ordered = sorted(rows, key=lambda row: (row["relative_path"].casefold(), row["relative_path"]))
    payload = _MANIFEST_HEADER + "".join(
        "\t".join(
            (row["relative_path"], row["sha256"], row["kind"], row["zone"], row["mesh_name"])
        )
        + "\n"
        for row in ordered
    )
    encoded = payload.encode("utf-8")
    return encoded, _sha256_bytes(encoded)


def parse_runtime_manifest(payload: bytes) -> tuple[dict[str, str], ...]:
    if payload.startswith(b"\xef\xbb\xbf") or not payload.endswith(b"\n"):
        raise RouteEvidenceError("Runtime manifest must be UTF-8 without BOM and end in LF.")
    try:
        text = payload.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RouteEvidenceError("Runtime manifest is not UTF-8.") from error
    lines = text.splitlines()
    if not lines or lines[0] + "\n" != _MANIFEST_HEADER:
        raise RouteEvidenceError("Runtime manifest header mismatch.")
    rows: list[dict[str, str]] = []
    aliases: set[str] = set()
    previous: tuple[str, str] | None = None
    for index, line in enumerate(lines[1:], start=2):
        fields = line.split("\t")
        if len(fields) != 5:
            raise RouteEvidenceError(f"Malformed manifest row {index}.")
        relative_path = _canonical_runtime_path(fields[0])
        alias = relative_path.casefold()
        if alias in aliases:
            raise RouteEvidenceError(f"Duplicate manifest path {relative_path!r}.")
        aliases.add(alias)
        digest = _require_sha256(fields[1], f"manifest row {index} sha256")
        kind = _require_string(fields[2], f"manifest row {index} kind")
        if any(_CONTROL.search(value) for value in fields):
            raise RouteEvidenceError(f"Manifest row {index} contains control characters.")
        sort_key = (alias, relative_path)
        if previous is not None and sort_key <= previous:
            raise RouteEvidenceError("Runtime manifest rows are not canonically sorted.")
        previous = sort_key
        rows.append(
            {
                "relative_path": relative_path,
                "sha256": digest,
                "kind": kind,
                "zone": fields[3],
                "mesh_name": fields[4],
            }
        )
    return tuple(rows)


def verify_manifest_root(payload: bytes, *, expected_root_digest: str) -> None:
    expected = _require_sha256(expected_root_digest, "expected manifest root digest")
    if _sha256_bytes(payload) != expected:
        raise RouteEvidenceError("Runtime manifest root digest mismatch.")
    parse_runtime_manifest(payload)


def manifest_is_runtime_ready(payload: bytes) -> bool:
    return any(row["relative_path"] == _TASK5_RUNTIME_PATH for row in parse_runtime_manifest(payload))


def verify_runtime_manifest(
    payload: bytes,
    *,
    addon_root: Path,
    expected_root_digest: str,
    required_runtime_paths: Sequence[str],
    runtime_ready: bool,
) -> dict[str, Any]:
    verify_manifest_root(payload, expected_root_digest=expected_root_digest)
    rows = parse_runtime_manifest(payload)
    actual = {row["relative_path"] for row in rows}
    required = {_canonical_runtime_path(path, "required runtime path") for path in required_runtime_paths}
    if actual != required:
        raise RouteEvidenceError("Runtime manifest child set does not match the independently required set.")
    if manifest_is_runtime_ready(payload) != runtime_ready:
        raise RouteEvidenceError("Runtime-ready state does not match the independently required state.")
    canonical_root = addon_root.resolve(strict=True)
    for row in rows:
        candidate = canonical_root.joinpath(*row["relative_path"].split("/"))
        try:
            resolved = candidate.resolve(strict=True)
        except OSError as error:
            raise RouteEvidenceError(f"Manifest child is missing: {candidate}") from error
        try:
            common = os.path.commonpath((str(canonical_root), str(resolved)))
        except ValueError as error:
            raise RouteEvidenceError("Manifest child escapes addon root.") from error
        if os.path.normcase(common) != os.path.normcase(str(canonical_root)):
            raise RouteEvidenceError("Manifest child escapes addon root through an alias or reparse point.")
        if not resolved.is_file() or _sha256_bytes(resolved.read_bytes()) != row["sha256"]:
            raise RouteEvidenceError(f"Manifest child hash mismatch: {row['relative_path']}")
    return {"root_digest": expected_root_digest, "rows": rows, "runtime_ready": runtime_ready}


def update_runtime_pin(path: Path, digest: str, *, marker: str) -> None:
    digest = _require_sha256(digest, "runtime manifest digest")
    marker = _require_string(marker, "runtime pin marker")
    try:
        original = path.read_bytes()
        text = original.decode("utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise RouteEvidenceError(f"Could not read runtime pin file {path}: {error}") from error
    pattern = re.compile(rf'(?m)(\b{re.escape(marker)}\s*=\s*")[0-9a-f]{{64}}(")')
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        raise RouteEvidenceError("Runtime pin marker does not own exactly one canonical digest literal.")
    updated = pattern.sub(rf"\g<1>{digest}\g<2>", text, count=1).encode("utf-8")
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(updated)
        temporary.replace(path)
    except OSError as error:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise RouteEvidenceError(f"Could not update runtime pin atomically: {error}") from error


def _atomic_write_bytes(path: Path, payload: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    try:
        temporary.write_bytes(payload)
        temporary.replace(path)
    except OSError as error:
        try:
            temporary.unlink(missing_ok=True)
        except OSError:
            pass
        raise RouteEvidenceError(f"Could not atomically write {path}: {error}") from error


_CONTRACT_EXPECTED_INPUT_FIELDS = frozenset(
    (*_GLOBAL_INPUT_FIELDS, "destination_row_sha256", "ingress_row_sha256", "zone_mesh_name")
)


def _validate_contract_source_bindings(
    *,
    contracts: Sequence[Mapping[str, Any]],
    transitions: Sequence[Mapping[str, Any]],
    policy: RouteProofPolicy,
    destination_payload: bytes,
    graph_payload: bytes,
    dll_payload: bytes,
    mesh_payload_by_name: Mapping[str, bytes],
    transition_registry_payload: bytes | None,
) -> None:
    if not contracts and not transitions:
        return
    if transition_registry_payload is None:
        raise RouteEvidenceError("Route contracts require the exact transition registry bytes.")
    registry_rows = _parse_transition_definitions(
        transition_registry_payload, source="route-transitions.json snapshot"
    )
    registry_by_id = {str(row["transition_id"]): row for row in registry_rows}
    transition_by_id: dict[str, dict[str, Any]] = {}
    for transition in transitions:
        row = copy.deepcopy(dict(transition))
        transition_id = _require_string(row.get("transition_id"), "transition_id")
        if transition_id in transition_by_id:
            raise RouteEvidenceError("Generated transition rows contain duplicate IDs.")
        if registry_by_id.get(transition_id) != row:
            raise RouteEvidenceError(
                f"Generated transition {transition_id!r} differs from the exact registry snapshot."
            )
        transition_by_id[transition_id] = row

    catalogue = load_route_catalogue_bytes(
        destination_payload,
        graph_payload,
        destination_source="writer destination snapshot",
        graph_source="writer graph snapshot",
    )
    destination_by_id = {
        str(row.get("destination_id", "")): row
        for row in catalogue["destinations"]
        if str(row.get("destination_id", ""))
    }
    ingress_by_id = {
        int(row["zoneline_id"]): row for row in catalogue["ingresses"]
    }
    actual_common = {
        "ffxinav_sha256": _sha256_bytes(dll_payload),
        "probe_protocol": policy.probe_protocol,
        "probe_schema": policy.probe_schema,
        "policy_revision": policy.policy_revision,
        "policy_sha256": policy_sha256(policy),
        "transition_registry_sha256": _sha256_bytes(transition_registry_payload),
        "destinations_sha256": _sha256_bytes(destination_payload),
        "graph_sha256": _sha256_bytes(graph_payload),
    }
    for contract in contracts:
        if contract.get("route_ready") is not True:
            raise RouteEvidenceError("Only route-ready contracts may enter runtime artifacts.")
        zone = _require_int(contract.get("zone"), "contract zone", minimum=0)
        destination_id = _require_string(
            contract.get("destination_id"), "contract destination_id"
        )
        destination = destination_by_id.get(destination_id)
        if destination is None or int(destination.get("zone", -1)) != zone:
            raise RouteEvidenceError("Contract destination is absent from the rooted catalogue.")
        expected = _require_object(
            contract.get("expected_inputs"), "contract expected_inputs"
        )
        if set(expected) != _CONTRACT_EXPECTED_INPUT_FIELDS:
            raise RouteEvidenceError("Contract expected input fields are not exact.")
        for field, actual in actual_common.items():
            if expected.get(field) != actual:
                raise RouteEvidenceError(f"Contract {field} differs from rooted source bytes.")
        mesh_name = _require_string(expected.get("mesh_name"), "contract mesh_name")
        if expected.get("zone_mesh_name") != mesh_name:
            raise RouteEvidenceError("Contract zone mesh binding is inconsistent.")
        mesh_payload = mesh_payload_by_name.get(mesh_name)
        if mesh_payload is None or expected.get("mesh_sha256") != _sha256_bytes(mesh_payload):
            raise RouteEvidenceError("Contract mesh hash differs from rooted source bytes.")
        if expected.get("destination_row_sha256") != destination_row_sha256(destination):
            raise RouteEvidenceError("Contract destination row hash is stale.")
        prefix = contract.get("authorized_directed_prefix")
        if not isinstance(prefix, (list, tuple)) or not prefix:
            raise RouteEvidenceError("Contract directed prefix is missing.")
        try:
            prefix_rows = tuple(ingress_by_id[int(value)] for value in prefix)
        except (KeyError, TypeError, ValueError) as error:
            raise RouteEvidenceError("Contract directed prefix is absent from the rooted graph.") from error
        valid_prefix, reason = validate_directed_prefix(prefix_rows, target_zone=zone)
        if not valid_prefix:
            raise RouteEvidenceError(f"Contract directed prefix is invalid: {reason}")
        if expected.get("ingress_row_sha256") != ingress_row_sha256(prefix_rows[-1]):
            raise RouteEvidenceError("Contract ingress row hash is stale.")
        required = contract.get("required_transition_ids", ())
        if not isinstance(required, (list, tuple)):
            raise RouteEvidenceError("Contract required transitions must be a sequence.")
        required_ids = tuple(_require_string(value, "required transition ID") for value in required)
        if len(required_ids) != len(set(required_ids)) or any(
            value not in transition_by_id for value in required_ids
        ):
            raise RouteEvidenceError("Contract transition references are not rooted.")


def write_route_runtime_artifacts(
    *,
    repo_root: Path,
    third_party_root: Path,
    policy: RouteProofPolicy,
    contracts: Sequence[Mapping[str, Any]],
    transitions: Sequence[Mapping[str, Any]],
    runtime_ready: bool,
) -> dict[str, Any]:
    """Render Task 4's addon-owned route trust root without touching live code."""

    repository = Path(repo_root).resolve(strict=True)
    dependencies = validate_dependency_root(third_party_root)
    addon_root = repository / "ashita" / "addons" / "accessxi_reader"
    module_root = addon_root / "modules"
    data_root = addon_root / "data"
    destinations = data_root / "ffxi-nav-destinations.tsv"
    graph = data_root / "ffxi-nav-zoneline-graph.tsv"
    dll = dependencies / "FFXI-NavMesh-Builder" / "FFXINAV.dll"
    for label, path in (
        ("addon destination catalogue", destinations),
        ("addon directed graph", graph),
        ("pinned FFXINAV DLL", dll),
    ):
        if not path.is_file():
            raise RouteEvidenceError(f"{label} is missing: {path}")

    contract_rows = tuple(copy.deepcopy(dict(row)) for row in contracts)
    transition_rows = tuple(copy.deepcopy(dict(row)) for row in transitions)
    policy_path = module_root / "mission_quest_route_policy.lua"
    transitions_path = module_root / "mission_quest_route_transitions.lua"
    contracts_path = module_root / "mission_quest_route_contracts.lua"
    manifest_path = data_root / "mission-quest-route-manifest.tsv"

    zone_mesh_names: dict[int, str] = {}
    for contract in contract_rows:
        zone = _require_int(contract.get("zone"), "contract zone", minimum=0)
        inputs = _require_object(contract.get("expected_inputs"), "contract expected_inputs")
        mesh_name = _require_string(inputs.get("mesh_name"), "contract mesh_name")
        previous = zone_mesh_names.get(zone)
        if previous is not None and previous.casefold() != mesh_name.casefold():
            raise RouteEvidenceError(f"Zone {zone} has conflicting contract mesh names.")
        zone_mesh_names[zone] = mesh_name

    source_paths: dict[str, Path] = {
        "destinations": destinations,
        "graph": graph,
        "ffxinav": dll,
    }
    for zone, mesh_name in sorted(zone_mesh_names.items()):
        mesh = dependencies / "xiNavmeshes" / mesh_name
        if not mesh.is_file():
            raise RouteEvidenceError(f"Contract mesh is missing for zone {zone}: {mesh}")
        source_paths[f"mesh:{mesh_name}"] = mesh
    transition_registry_path = (
        repository / "data" / "mission-quest-guides" / "route-transitions.json"
    )
    if not transition_registry_path.is_file():
        raise RouteEvidenceError(
            f"Transition registry is missing: {transition_registry_path}"
        )
    source_paths["transition-registry"] = transition_registry_path
    source_payloads = {key: path.read_bytes() for key, path in source_paths.items()}
    transition_registry_payload = source_payloads["transition-registry"]
    transition_definitions = _parse_transition_definitions(
        transition_registry_payload, source="route-transitions.json snapshot"
    )
    policy_bytes = render_policy_lua(policy).encode("utf-8")
    transitions_bytes = render_transitions_lua(
        transition_rows,
        source_registry_sha256=_sha256_bytes(transition_registry_payload),
        definitions=transition_definitions,
    ).encode("utf-8")
    contracts_bytes = render_contracts_lua(contract_rows).encode("utf-8")
    _validate_contract_source_bindings(
        contracts=contract_rows,
        transitions=transition_rows,
        policy=policy,
        destination_payload=source_payloads["destinations"],
        graph_payload=source_payloads["graph"],
        dll_payload=source_payloads["ffxinav"],
        mesh_payload_by_name={
            key.removeprefix("mesh:"): payload
            for key, payload in source_payloads.items()
            if key.startswith("mesh:")
        },
        transition_registry_payload=transition_registry_payload,
    )

    with tempfile.TemporaryDirectory(prefix="route-artifacts-", dir=repository) as temporary:
        stage = Path(temporary)
        staged_policy = stage / "mission_quest_route_policy.lua"
        staged_transitions = stage / "mission_quest_route_transitions.lua"
        staged_contracts = stage / "mission_quest_route_contracts.lua"
        staged_policy.write_bytes(policy_bytes)
        staged_transitions.write_bytes(transitions_bytes)
        staged_contracts.write_bytes(contracts_bytes)
        staged_destinations = stage / "ffxi-nav-destinations.tsv"
        staged_graph = stage / "ffxi-nav-zoneline-graph.tsv"
        staged_dll = stage / "FFXINAV.dll"
        staged_destinations.write_bytes(source_payloads["destinations"])
        staged_graph.write_bytes(source_payloads["graph"])
        staged_dll.write_bytes(source_payloads["ffxinav"])
        artifacts: list[dict[str, Any]] = [
            {
                "runtime_path": "modules/mission_quest_route_policy.lua",
                "source_path": staged_policy,
                "kind": "policy",
            },
            {
                "runtime_path": "modules/mission_quest_route_transitions.lua",
                "source_path": staged_transitions,
                "kind": "transitions",
            },
            {
                "runtime_path": "modules/mission_quest_route_contracts.lua",
                "source_path": staged_contracts,
                "kind": "contracts",
            },
            {
                "runtime_path": "data/ffxi-nav-destinations.tsv",
                "source_path": staged_destinations,
                "kind": "destinations",
            },
            {
                "runtime_path": "data/ffxi-nav-zoneline-graph.tsv",
                "source_path": staged_graph,
                "kind": "graph",
            },
            {
                "runtime_path": "third_party/FFXI-NavMesh-Builder/FFXINAV.dll",
                "source_path": staged_dll,
                "kind": "ffxinav",
            },
        ]
        for zone, mesh_name in sorted(zone_mesh_names.items()):
            mesh = stage / "meshes" / str(zone) / mesh_name
            mesh.parent.mkdir(parents=True, exist_ok=True)
            mesh.write_bytes(source_payloads[f"mesh:{mesh_name}"])
            artifacts.append(
                {
                    "runtime_path": f"third_party/xiNavmeshes/{mesh_name}",
                    "source_path": mesh,
                    "kind": "mesh",
                    "zone": zone,
                    "mesh_name": mesh_name,
                }
            )
        if runtime_ready:
            runtime = module_root / "mission_quest_route_runtime.lua"
            if not runtime.is_file():
                raise RouteEvidenceError(f"Task 5 route runtime is missing: {runtime}")
            runtime_payload = runtime.read_bytes()
            source_paths["runtime"] = runtime
            source_payloads["runtime"] = runtime_payload
            staged_runtime = stage / "mission_quest_route_runtime.lua"
            staged_runtime.write_bytes(runtime_payload)
            artifacts.append(
                {
                    "runtime_path": _TASK5_RUNTIME_PATH,
                    "source_path": staged_runtime,
                    "kind": "runtime",
                }
            )
        required = tuple(str(row["runtime_path"]) for row in artifacts)
        manifest, manifest_digest = render_runtime_manifest(
            artifacts,
            required_runtime_paths=required,
            manifest_relative_path="data/mission-quest-route-manifest.tsv",
            runtime_ready=runtime_ready,
            referenced_mesh_names=tuple(zone_mesh_names.values()),
            zone_mesh_names=zone_mesh_names,
        )

        for key, path in source_paths.items():
            if path.read_bytes() != source_payloads[key]:
                raise RouteEvidenceError(
                    f"Route artifact source changed during generation: {key}"
                )

    _atomic_write_bytes(policy_path, policy_bytes)
    _atomic_write_bytes(transitions_path, transitions_bytes)
    _atomic_write_bytes(contracts_path, contracts_bytes)
    _atomic_write_bytes(manifest_path, manifest)
    return {
        "manifest_sha256": manifest_digest,
        "runtime_ready": runtime_ready,
        "contract_count": len(contract_rows),
        "transition_count": len(transition_rows),
        "referenced_meshes": tuple(
            {"zone": zone, "mesh_name": name}
            for zone, name in sorted(zone_mesh_names.items())
        ),
    }

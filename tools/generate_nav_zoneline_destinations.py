#!/usr/bin/env python3
"""Generate AXI nav destinations from LandSandBoat zoneline data.

The live addon stores navigation destinations as:

    zone_id, name, x, z, y, kind, source, confidence, section

LandSandBoat zonelines are stored as x, y, z, so this tool deliberately swaps
the final two coordinate fields when writing AXI rows.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

GENERATED_SOURCE = "lsb-zoneline-all"
GENERATED_NPC_SOURCE = "lsb-npc-list-all"
GENERATED_ENEMY_SOURCE = "lsb-mob-spawn-camps"
GENERATED_SOURCES = (GENERATED_SOURCE, GENERATED_NPC_SOURCE, GENERATED_ENEMY_SOURCE)
GENERATED_SECTION = "world-zonelines-2026-06-20"
GENERATED_NPC_SECTION = "world-npcs-2026-06-20"
GENERATED_ENEMY_SECTION = "world-enemy-camps-2026-07-01"
MOB_CLUSTER_DISTANCE_YALMS = 120.0
MOB_CLUSTER_Y_DISTANCE_YALMS = 24.0
STATIC_IDENTITY_SCHEMA_REVISION = "v1"
ENEMY_IDENTITY_SCHEMA_REVISION = "v1"
ENEMY_CLUSTER_POLICY_VERSION = "complete-link-v1-h120-y24"

GRAPH_EDGE_OVERRIDES = {
    # Live /axi pos evidence for the Port San d'Oria -> Northern San d'Oria
    # trigger.  The raw LSB endpoint is close but steers into the wall.
    812070522: {
        "from_x": -108.899,
        "from_z": -132.949,
        "from_y": -8.500,
        "to_y": 11.949,
        "source": "live-verified-axi-pos",
        "confidence": "proven",
        "note": "port-to-northern-2026-06-28",
    },
    # The La Theine-side Valkurm trigger was captured with /axi pos after the
    # recorded survey mark proved to be too far back from the zone boundary.
    880095866: {
        "from_x": 159.989,
        "from_z": -760.190,
        "from_y": 31.950,
        "source": "live-axi-pos-lathine-valkurm-20260713",
        "confidence": "observed",
        "note": "La Theine-side trigger boundary recorded after Valkurm crossing",
    },
    846606970: {
        "to_x": 159.989,
        "to_z": -760.190,
        "to_y": 31.950,
        "source": "live-axi-pos-lathine-valkurm-20260713",
        "confidence": "observed",
        "note": "La Theine-side trigger boundary recorded after Valkurm crossing",
    },
    # These are the two Ordelle exits confirmed by the user's walked survey
    # and aligned with the existing navmesh/zoneline endpoints.
    913650298: {
        "source": "live-mark-aligned-navmesh-20260713",
        "confidence": "proven",
        "note": "user-confirmed-ordelle-line-2026-07-13",
    },
    947204730: {
        "source": "live-mark-aligned-navmesh-20260713",
        "confidence": "proven",
        "note": "user-confirmed-ordelle-line-2026-07-13",
    },
}

# The third LSB Ordelle pair is not reachable from the surveyed La Theine
# component. Keeping either direction would let world routing advertise a
# transition the player cannot safely use.
GRAPH_EDGE_EXCLUSIONS = {
    1635070586,
    878982522,
}


@dataclass(frozen=True)
class ZoneLine:
    zoneline_id: int
    from_zone: int
    from_x: float
    from_y: float
    from_z: float
    to_zone: int
    to_x: float
    to_y: float
    to_z: float
    from_label: str
    from_code: str
    to_label: str
    to_code: str
    note: str
    comment: str


@dataclass(frozen=True)
class Destination:
    zone: int
    name: str
    x: float
    z: float
    y: float
    kind: str
    source: str
    confidence: str
    section: str
    destination_id: str = ""
    raw_identity: str = ""
    raw_spawn_ids: tuple[int, ...] = ()
    cluster_policy_version: str = ""


@dataclass(frozen=True)
class MobSpawn:
    zone: int
    name: str
    x: float
    z: float
    y: float
    min_level: int
    max_level: int
    mobid: int
    raw_identity: str


@dataclass(frozen=True)
class MobSpawnExclusion:
    line_number: int
    mobid: int
    reason: str


@dataclass(frozen=True)
class MobSpawnParseAudit:
    active_insert_count: int
    spawns: tuple[MobSpawn, ...]
    exclusions: tuple[MobSpawnExclusion, ...]


OBJECT_NAME_PARTS = (
    "???",
    "auction",
    "casket",
    "cavernous maw",
    "coffer",
    "door",
    "fount",
    "gate",
    "grounds tome",
    "home point",
    "manual",
    "planar rift",
    "proto-waypoint",
    "survival guide",
    "waypoint",
)


def clean_label(value: str) -> str:
    value = value.replace("_", " ").replace("`", "'").strip()
    value = re.sub(r"\s+", " ", value)
    return value


def _identity_tail(raw_identity: str) -> str:
    value = str(raw_identity or "").strip()
    tail = value.rsplit(":", 1)[-1]
    if not value or not re.fullmatch(r"[0-9]+", tail):
        raise ValueError(f"Static navigation identity is not an exact numeric source record: {value!r}")
    return tail


def static_destination_id(
    kind: str,
    zone: int,
    raw_identity: str,
    *,
    schema_revision: str = STATIC_IDENTITY_SCHEMA_REVISION,
) -> str:
    normalized_kind = clean_label(kind).casefold()
    normalized_revision = clean_label(schema_revision).casefold()
    if normalized_kind not in {"npc", "object", "area"}:
        raise ValueError(f"Static navigation identity has unsupported kind {kind!r}.")
    if int(zone) <= 0 or not re.fullmatch(r"v[0-9]+", normalized_revision):
        raise ValueError("Static navigation identity needs a positive zone and versioned schema.")
    return f"{normalized_kind}:{normalized_revision}:{int(zone)}:{_identity_tail(raw_identity)}"


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", clean_label(value).casefold()).strip("-") or "target"


def enemy_destination_id(
    *,
    zone: int,
    raw_identity: str,
    raw_spawn_ids: tuple[int, ...],
    policy_version: str,
) -> str:
    ids = tuple(sorted(int(value) for value in raw_spawn_ids))
    if int(zone) <= 0 or not raw_identity or not ids or len(ids) != len(set(ids)):
        raise ValueError("Enemy camp identity needs one zone, one raw identity, and unique spawn IDs.")
    raw_name = raw_identity.split(":mobname:", 1)[-1]
    payload = "\n".join(
        (
            ENEMY_IDENTITY_SCHEMA_REVISION,
            str(int(zone)),
            raw_identity,
            ",".join(str(value) for value in ids),
            policy_version,
        )
    ).encode("utf-8")
    digest = hashlib.sha256(payload).hexdigest()[:20]
    return f"camp:{ENEMY_IDENTITY_SCHEMA_REVISION}:{int(zone)}:{_slug(raw_name)}:{digest}"


def parse_zone_ids(path: Path) -> dict[int, str]:
    names: dict[int, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"\s*(\d+)\s+-\s+[0-9A-Fa-f]{2}\s+-\s+(.+?)\s*$", line)
        if match:
            names[int(match.group(1))] = clean_label(match.group(2))
    return names


def parse_comment(comment: str) -> tuple[str, str, str, str, str]:
    match = re.match(r"(.+?)\s+\(([^()]*)\)\s*->\s*(?:(.+?)\s+)?\(([^()]*)\)(?:\s+\(([^()]*)\))?\s*$", comment)
    if not match:
        return "", "", "", "", ""
    from_label = clean_label(match.group(1) or "")
    from_code = clean_label(match.group(2) or "")
    to_label = clean_label(match.group(3) or "")
    to_code = clean_label(match.group(4) or "")
    note = clean_label(match.group(5) or "")
    return from_label, from_code, to_label, to_code, note


def parse_zonelines(path: Path) -> list[ZoneLine]:
    rows: list[ZoneLine] = []
    pattern = re.compile(r"INSERT INTO `zonelines` VALUES \(([^)]*)\);\s*--\s*(.*)$")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.search(line)
        if not match:
            continue
        raw_values = [part.strip() for part in match.group(1).split(",")]
        if len(raw_values) < 12:
            continue
        from_label, from_code, to_label, to_code, note = parse_comment(match.group(2))
        rows.append(
            ZoneLine(
                zoneline_id=int(raw_values[0]),
                from_zone=int(raw_values[1]),
                from_x=float(raw_values[2]),
                from_y=float(raw_values[3]),
                from_z=float(raw_values[4]),
                to_zone=int(raw_values[5]),
                to_x=float(raw_values[6]),
                to_y=float(raw_values[7]),
                to_z=float(raw_values[8]),
                from_label=from_label,
                from_code=from_code,
                to_label=to_label,
                to_code=to_code,
                note=note,
                comment=clean_label(match.group(2)),
            )
        )
    return rows


def parse_npc_list(path: Path) -> list[Destination]:
    rows: list[Destination] = []
    pattern = re.compile(r"^\s*INSERT INTO `npc_list` VALUES \((.*)\);\s*(?:--.*)?$")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.match(line)
        if not match:
            continue
        values = next(csv.reader([match.group(1)], quotechar="'", escapechar="\\"))
        if len(values) < 19:
            continue
        try:
            npcid = int(values[0])
            x = float(values[4])
            y = float(values[5])
            z = float(values[6])
        except ValueError:
            continue
        raw_name = clean_label(values[1].replace("_", " "))
        display_name = clean_label(values[2] or raw_name)
        lower_name = display_name.lower()
        if (
            display_name == ""
            or lower_name == "blank"
            or display_name.startswith("NPC[")
            or lower_name == "fxtest"
            or lower_name.startswith("npc[")
            or re.match(r"^0x[0-9a-f]+$", lower_name) is not None
            or re.match(r"^[a-z]\d+[a-z]$", lower_name) is not None
            or lower_name.startswith("sdoor")
            or raw_name.startswith("_")
            or (abs(x) < 0.001 and abs(z) < 0.001)
        ):
            continue
        zone = (npcid >> 12) & 0x0FFF
        kind = "object" if any(part in lower_name for part in OBJECT_NAME_PARTS) else "npc"
        raw_identity = f"lsb:npc_list:{npcid}"
        rows.append(
            Destination(
                zone=zone,
                name=display_name,
                x=x,
                z=z,
                y=y,
                kind=kind,
                source=GENERATED_NPC_SOURCE,
                confidence="untested",
                section=GENERATED_NPC_SECTION,
                destination_id=static_destination_id(kind, zone, raw_identity),
                raw_identity=raw_identity,
            )
        )
    return rows


def mob_name_is_placeholder(name: str) -> bool:
    lower_name = clean_label(name).lower()
    if lower_name == "" or lower_name == "blank" or lower_name == "fxtest":
        return True
    if lower_name.startswith("npc[") or lower_name.startswith("sdoor"):
        return True
    return re.match(r"^0x[0-9a-f]+$", lower_name) is not None


def mob_position_is_placeholder(x: float, y: float, z: float) -> bool:
    if abs(x) < 0.001 and abs(z) < 0.001:
        return True
    return abs(x - 1.0) < 0.001 and abs(y - 1.0) < 0.001 and abs(z - 1.0) < 0.001


_MOB_INSERT_PREFIX = re.compile(r"^\s*INSERT\s+INTO\s+`mob_spawn_points`", re.IGNORECASE)
_MOB_INSERT_ROW = re.compile(
    r"^\s*INSERT\s+INTO\s+`mob_spawn_points`\s+VALUES\s*\((.*)\);\s*(?:--.*)?$",
    re.IGNORECASE,
)
_ADDITIVE_NUMBER_TOKEN = re.compile(
    r"[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?"
)


def _parse_additive_number(value: str, *, line_number: int, field_name: str) -> float:
    expression = re.sub(r"\s+", "", str(value or ""))
    cursor = 0
    total = 0.0
    tokens = 0
    while cursor < len(expression):
        match = _ADDITIVE_NUMBER_TOKEN.match(expression, cursor)
        if match is None:
            raise ValueError(
                f"mob_spawn_points line {line_number} has unsupported numeric expression "
                f"for {field_name}: {value!r}"
            )
        total += float(match.group(0))
        cursor = match.end()
        tokens += 1
    if tokens == 0:
        raise ValueError(
            f"mob_spawn_points line {line_number} has unsupported numeric expression "
            f"for {field_name}: {value!r}"
        )
    if not math.isfinite(total):
        raise ValueError(
            f"mob_spawn_points line {line_number} has non-finite numeric expression "
            f"for {field_name}: {value!r}"
        )
    return total


def _parse_mob_integer(value: str, *, line_number: int, field_name: str) -> int:
    try:
        return int(str(value or "0").strip())
    except ValueError as error:
        raise ValueError(
            f"mob_spawn_points line {line_number} has invalid integer for {field_name}: {value!r}"
        ) from error


def audit_mob_spawn_points(path: Path) -> MobSpawnParseAudit:
    rows: list[MobSpawn] = []
    exclusions: list[MobSpawnExclusion] = []
    active_insert_count = 0
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8", errors="replace").splitlines(),
        start=1,
    ):
        if _MOB_INSERT_PREFIX.match(line) is None:
            continue
        active_insert_count += 1
        match = _MOB_INSERT_ROW.match(line)
        if match is None:
            raise ValueError(f"Malformed active mob_spawn_points INSERT on line {line_number}.")
        try:
            values = next(csv.reader([match.group(1)], quotechar="'", escapechar="\\"))
        except csv.Error as error:
            raise ValueError(f"Malformed active mob_spawn_points values on line {line_number}.") from error
        if len(values) < 10:
            raise ValueError(
                f"Active mob_spawn_points INSERT on line {line_number} has only {len(values)} fields."
            )
        mobid = _parse_mob_integer(values[0], line_number=line_number, field_name="mobid")
        groupid = _parse_mob_integer(values[4], line_number=line_number, field_name="groupid")
        min_level = _parse_mob_integer(values[5], line_number=line_number, field_name="minLevel")
        max_level = _parse_mob_integer(values[6], line_number=line_number, field_name="maxLevel")
        x = _parse_additive_number(values[7], line_number=line_number, field_name="pos_x")
        y = _parse_additive_number(values[8], line_number=line_number, field_name="pos_y")
        z = _parse_additive_number(values[9], line_number=line_number, field_name="pos_z")
        raw_mobname = str(values[2] or "").strip()
        name = clean_label((values[3] or raw_mobname or "").replace("_", " "))
        if mob_name_is_placeholder(name):
            exclusions.append(MobSpawnExclusion(line_number, mobid, "placeholder-name"))
            continue
        if mob_position_is_placeholder(x, y, z):
            exclusions.append(MobSpawnExclusion(line_number, mobid, "placeholder-position"))
            continue
        raw_identity = f"lsb:mob_spawn_points:group:{groupid}:mobname:{raw_mobname}"
        rows.append(
            MobSpawn(
                zone=(mobid >> 12) & 0x0FFF,
                name=name,
                x=x,
                z=z,
                y=y,
                min_level=min_level,
                max_level=max_level,
                mobid=mobid,
                raw_identity=raw_identity,
            )
        )
    if active_insert_count != len(rows) + len(exclusions):
        raise ValueError("mob_spawn_points parsing did not account for every active INSERT exactly once.")
    return MobSpawnParseAudit(active_insert_count, tuple(rows), tuple(exclusions))


def parse_mob_spawn_points(path: Path) -> list[MobSpawn]:
    return list(audit_mob_spawn_points(path).spawns)


def enemy_camp_destination(
    spawns: list[MobSpawn],
    *,
    policy_version: str = ENEMY_CLUSTER_POLICY_VERSION,
) -> Destination:
    if not spawns:
        raise ValueError("Enemy camp cannot be empty.")
    ordered = sorted(spawns, key=lambda spawn: spawn.mobid)
    zones = {spawn.zone for spawn in ordered}
    identities = {spawn.raw_identity for spawn in ordered}
    raw_spawn_ids = tuple(spawn.mobid for spawn in ordered)
    if len(zones) != 1 or len(identities) != 1 or len(raw_spawn_ids) != len(set(raw_spawn_ids)):
        raise ValueError("Enemy camp members must share one raw identity and have unique spawn IDs.")
    avg_x = sum(spawn.x for spawn in ordered) / len(ordered)
    avg_z = sum(spawn.z for spawn in ordered) / len(ordered)
    avg_y = sum(spawn.y for spawn in ordered) / len(ordered)
    best = min(
        ordered,
        key=lambda spawn: (
            ((spawn.x - avg_x) ** 2) + ((spawn.z - avg_z) ** 2) + (((spawn.y - avg_y) * 2.0) ** 2),
            spawn.mobid,
        ),
    )
    min_level = min(spawn.min_level for spawn in ordered)
    max_level = max(spawn.max_level for spawn in ordered)
    section = f"{GENERATED_ENEMY_SECTION}; spawns={len(ordered)}; levels={min_level}-{max_level}"
    raw_identity = ordered[0].raw_identity
    return Destination(
        zone=best.zone,
        name=best.name,
        x=best.x,
        z=best.z,
        y=best.y,
        kind="enemy",
        source=GENERATED_ENEMY_SOURCE,
        confidence="untested",
        section=section,
        destination_id=enemy_destination_id(
            zone=best.zone,
            raw_identity=raw_identity,
            raw_spawn_ids=raw_spawn_ids,
            policy_version=policy_version,
        ),
        raw_identity=raw_identity,
        raw_spawn_ids=raw_spawn_ids,
        cluster_policy_version=policy_version,
    )


def _complete_link_member(cluster: list[MobSpawn], candidate: MobSpawn) -> bool:
    distance_sq = MOB_CLUSTER_DISTANCE_YALMS * MOB_CLUSTER_DISTANCE_YALMS
    return all(
        ((spawn.x - candidate.x) ** 2) + ((spawn.z - candidate.z) ** 2) <= distance_sq
        and abs(spawn.y - candidate.y) <= MOB_CLUSTER_Y_DISTANCE_YALMS
        for spawn in cluster
    )


def cluster_enemy_camps(
    spawns: list[MobSpawn],
    *,
    policy_version: str = ENEMY_CLUSTER_POLICY_VERSION,
) -> list[Destination]:
    if policy_version != ENEMY_CLUSTER_POLICY_VERSION:
        raise ValueError(
            f"Enemy cluster policy {policy_version!r} has no matching geometry implementation."
        )
    grouped: dict[tuple[int, str], list[MobSpawn]] = defaultdict(list)
    all_ids = [spawn.mobid for spawn in spawns]
    if len(all_ids) != len(set(all_ids)):
        raise ValueError("Enemy spawn input contains duplicate raw mob IDs.")
    for spawn in spawns:
        grouped[(spawn.zone, spawn.raw_identity)].append(spawn)

    camps: list[Destination] = []
    for group_key in sorted(grouped):
        clusters: list[list[MobSpawn]] = []
        for spawn in sorted(grouped[group_key], key=lambda value: value.mobid):
            target = next((cluster for cluster in clusters if _complete_link_member(cluster, spawn)), None)
            if target is None:
                clusters.append([spawn])
            else:
                target.append(spawn)
        camps.extend(enemy_camp_destination(cluster, policy_version=policy_version) for cluster in clusters)

    emitted_ids = sorted(raw_id for camp in camps for raw_id in camp.raw_spawn_ids)
    if emitted_ids != sorted(all_ids):
        raise ValueError("Enemy complete-link clustering did not conserve every raw spawn ID exactly once.")
    return sorted(camps, key=lambda camp: (camp.zone, camp.name.casefold(), camp.destination_id))


def read_destinations(path: Path) -> tuple[list[str], list[Destination]]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    destinations: list[Destination] = []
    for line in lines:
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 7:
            raise ValueError(f"Malformed navigation destination row in {path}: {line!r}")
        try:
            raw_spawn_ids: tuple[int, ...] = ()
            if len(parts) >= 12 and parts[11].strip():
                raw_spawn_ids = tuple(int(value) for value in parts[11].split(","))
            destinations.append(
                Destination(
                    zone=int(parts[0]),
                    name=parts[1],
                    x=float(parts[2]),
                    z=float(parts[3]),
                    y=float(parts[4]),
                    kind=parts[5],
                    source=parts[6],
                    confidence=parts[7] if len(parts) >= 8 else "",
                    section=parts[8] if len(parts) >= 9 else "",
                    destination_id=parts[9].strip() if len(parts) >= 10 else "",
                    raw_identity=parts[10].strip() if len(parts) >= 11 else "",
                    raw_spawn_ids=raw_spawn_ids,
                    cluster_policy_version=parts[12].strip() if len(parts) >= 13 else "",
                )
            )
        except ValueError as error:
            raise ValueError(f"Malformed navigation destination row in {path}: {line!r}") from error
    return lines, destinations


def distance_2d(a: Destination, b: Destination) -> float:
    return ((a.x - b.x) ** 2 + (a.z - b.z) ** 2) ** 0.5


def destination_duplicate_shadowed(destination: Destination, existing: list[Destination], max_distance: float, max_y_distance: float) -> bool:
    destination_name = clean_label(destination.name).lower()
    destination_kind = clean_label(destination.kind).lower()
    for old in existing:
        if destination.destination_id and old.destination_id != destination.destination_id:
            continue
        if old.zone != destination.zone:
            continue
        if clean_label(old.name).lower() != destination_name:
            continue
        if clean_label(old.kind).lower() != destination_kind:
            continue
        if distance_2d(old, destination) <= max_distance and abs(old.y - destination.y) <= max_y_distance:
            return True
    return False


def filter_generated_destinations(generated: list[Destination], existing: list[Destination], max_distance: float, max_y_distance: float) -> list[Destination]:
    return [
        destination
        for destination in generated
        if not destination_duplicate_shadowed(destination, existing, max_distance, max_y_distance)
    ]


def base_name(edge: ZoneLine, zone_names: dict[int, str]) -> str:
    if edge.note.lower() == "mog house":
        return "Mog House entrance"
    label = zone_names.get(edge.to_zone, "") or edge.to_label
    if label:
        if edge.to_zone == edge.from_zone:
            return f"{label} local transition"
        return f"{label} zone line"
    if edge.note:
        return f"{edge.note} transition"
    return f"Zone {edge.to_zone} zone line"


def destination_section(edge: ZoneLine) -> str:
    if edge.from_zone == 192 and edge.to_zone == 169:
        return "requires: Three Mage Gate access; party circles, Portal charm, or Toraimarai Home Point/Survival Guide"
    return GENERATED_SECTION


def generated_destination(edge: ZoneLine, name: str) -> Destination:
    override = GRAPH_EDGE_OVERRIDES.get(edge.zoneline_id, {})
    raw_identity = f"lsb:zonelines:{edge.zoneline_id}"
    return Destination(
        zone=edge.from_zone,
        name=name,
        x=override.get("from_x", edge.from_x),
        z=override.get("from_z", edge.from_z),
        y=override.get("from_y", edge.from_y),
        kind="area",
        source=override.get("source", GENERATED_SOURCE),
        confidence=override.get("confidence", "untested"),
        section=override.get("note", destination_section(edge)),
        destination_id=static_destination_id("area", edge.from_zone, raw_identity),
        raw_identity=raw_identity,
    )


def apply_edge_policy(edges: list[ZoneLine]) -> list[ZoneLine]:
    return [edge for edge in edges if edge.zoneline_id not in GRAPH_EDGE_EXCLUSIONS]


def generate_destinations(edges: list[ZoneLine], zone_names: dict[int, str], existing: list[Destination]) -> list[Destination]:
    base_counts = Counter((edge.from_zone, base_name(edge, zone_names)) for edge in edges)
    generated: list[Destination] = []
    for edge in edges:
        name = base_name(edge, zone_names)
        if base_counts[(edge.from_zone, name)] > 1 and edge.from_code:
            name = f"{name} {edge.from_code}"
        generated.append(generated_destination(edge, name))
    expected_ids = [static_destination_id("area", edge.from_zone, f"lsb:zonelines:{edge.zoneline_id}") for edge in edges]
    actual_ids = [destination.destination_id for destination in generated]
    if len(actual_ids) != len(set(actual_ids)) or sorted(actual_ids) != sorted(expected_ids):
        raise ValueError("Zoneline destination generation did not conserve every active raw identity exactly once.")
    return generated


def _render_destination_file(lines: list[str], generated: list[Destination]) -> bytes:
    generated_ids = [row.destination_id for row in generated if row.destination_id]
    if len(generated_ids) != len(set(generated_ids)):
        raise ValueError("Generated navigation destinations contain duplicate immutable IDs.")
    generated_id_set = set(generated_ids)

    def generated_owned(line: str) -> bool:
        if not line or line.startswith("#"):
            return False
        fields = line.split("\t")
        return (
            (len(fields) >= 7 and fields[6] in GENERATED_SOURCES)
            or (len(fields) >= 10 and bool(fields[9]) and fields[9] in generated_id_set)
        )

    retained = [
        line
        for line in lines
        if not (
            (line.startswith("# Generated from ") or line.startswith("# Generated rows are "))
            or generated_owned(line)
        )
    ]
    if retained and retained[-1] != "":
        retained.append("")
    retained.append(
        "# Generated from LandSandBoat zonelines, npc_list, and mob_spawn_points "
        "by tools/generate_nav_zoneline_destinations.py."
    )
    retained.append("# Generated rows are untested until route evidence proves them.")
    for row in sorted(generated, key=lambda d: (d.zone, d.kind, d.name.lower(), d.x, d.z)):
        retained.append(
            "\t".join(
                (
                    str(row.zone),
                    row.name,
                    f"{row.x:.3f}",
                    f"{row.z:.3f}",
                    f"{row.y:.3f}",
                    row.kind,
                    row.source,
                    row.confidence,
                    row.section,
                    row.destination_id,
                    row.raw_identity,
                    ",".join(str(value) for value in row.raw_spawn_ids),
                    row.cluster_policy_version,
                )
            )
        )
    final_ids = [
        fields[9]
        for line in retained
        if line and not line.startswith("#")
        for fields in [line.split("\t")]
        if len(fields) >= 10 and fields[9]
    ]
    if len(final_ids) != len(set(final_ids)):
        raise ValueError("Rendered navigation destinations contain duplicate immutable IDs.")
    return ("\n".join(retained) + "\n").encode("utf-8")


def _atomic_write_bytes(path: Path, content: bytes) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(content)
    temporary.replace(path)


def _repo_destination_paths(repo_root: Path) -> tuple[Path, Path, Path, Path]:
    root = repo_root.resolve()
    paths = (
        root / "data" / "ffxi-nav-destinations.tsv",
        root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-destinations.tsv",
        root / "data" / "ffxi-nav-zoneline-graph.tsv",
        root / "ashita" / "addons" / "accessxi_reader" / "data" / "ffxi-nav-zoneline-graph.tsv",
    )
    for path in paths:
        try:
            path.resolve().relative_to(root)
        except ValueError as error:
            raise ValueError(f"Navigation output escapes selected repository root: {path}") from error
    return paths


def write_destination_copies(
    repo_root: Path,
    lines: list[str],
    generated: list[Destination],
) -> str:
    root_path, addon_path, root_graph, addon_graph = _repo_destination_paths(Path(repo_root))
    required = (root_path, addon_path, root_graph, addon_graph)
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise ValueError(
            "Selected repository root lacks the expected navigation data shape: " + ", ".join(missing)
        )
    if root_path.read_bytes() != addon_path.read_bytes():
        raise ValueError(
            "Repository and addon destination copies differ; refusing to discard one side during refresh."
        )
    graph_content = root_graph.read_bytes()
    if addon_graph.read_bytes() != graph_content:
        raise ValueError(
            "Repository and addon graph copies differ; refusing a destination refresh with ambiguous route evidence."
        )

    content = _render_destination_file(lines, generated)
    old_content = {path: path.read_bytes() for path in (root_path, addon_path)}
    staged = [path.with_name(path.name + ".tmp") for path in (root_path, addon_path)]
    try:
        for temporary in staged:
            temporary.write_bytes(content)
        staged[0].replace(root_path)
        staged[1].replace(addon_path)
    except Exception:
        for path, previous in old_content.items():
            _atomic_write_bytes(path, previous)
        raise
    finally:
        for temporary in staged:
            temporary.unlink(missing_ok=True)

    if root_path.read_bytes() != content or addon_path.read_bytes() != content:
        raise OSError("Paired navigation destination outputs are not byte-identical after replacement.")
    if root_graph.read_bytes() != graph_content or addon_graph.read_bytes() != graph_content:
        raise OSError("Navigation graph evidence changed during destination-only replacement.")
    return hashlib.sha256(content).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=ROOT, help="Selected AccessXI checkout for inputs and outputs.")
    parser.add_argument(
        "--third-party-root",
        type=Path,
        help="Read-only LandSandBoat checkout containing sql/ and documentation/.",
    )
    parser.add_argument("--zonelines", type=Path, help="Explicit read-only zonelines SQL input.")
    parser.add_argument("--npc-list", type=Path, help="Explicit read-only npc_list SQL input.")
    parser.add_argument("--mob-spawn-points", type=Path, help="Explicit read-only mob_spawn_points SQL input.")
    parser.add_argument("--zone-ids", type=Path, help="Explicit read-only ZoneIDs input.")
    parser.add_argument("--dry-run", action="store_true", help="Report counts without writing files.")
    parser.add_argument(
        "--write",
        action="store_true",
        help="Atomically write only the repository and addon destination TSV copies; graph files are untouched.",
    )
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    if repo_root != ROOT.resolve():
        raise ValueError(
            "Navigation CLI output root must be the checkout containing this generator."
        )
    third_party_root = (
        args.third_party_root.resolve()
        if args.third_party_root is not None
        else repo_root / "third_party" / "LandSandBoat-server"
    )
    destinations_path = repo_root / "data" / "ffxi-nav-destinations.tsv"
    zonelines_path = (args.zonelines or repo_root / "data" / "lsb_zonelines.sql").resolve()
    npc_list_path = (args.npc_list or repo_root / "data" / "lsb_npc_list.sql").resolve()
    mob_spawn_points_path = (
        args.mob_spawn_points or third_party_root / "sql" / "mob_spawn_points.sql"
    ).resolve()
    zone_ids_path = (args.zone_ids or third_party_root / "documentation" / "ZoneIDs.txt").resolve()
    required_inputs = (
        destinations_path,
        zonelines_path,
        npc_list_path,
        mob_spawn_points_path,
        zone_ids_path,
    )
    missing_inputs = [str(path) for path in required_inputs if not path.is_file()]
    if missing_inputs:
        raise FileNotFoundError("Navigation generator input is missing: " + ", ".join(missing_inputs))

    zone_names = parse_zone_ids(zone_ids_path)
    parsed_edges = parse_zonelines(zonelines_path)
    edges = apply_edge_policy(parsed_edges)
    lines, existing = read_destinations(destinations_path)
    stable_existing = [row for row in existing if row.source not in GENERATED_SOURCES]
    generated_zonelines = generate_destinations(edges, zone_names, stable_existing)
    generated_npcs_raw = parse_npc_list(npc_list_path)
    generated_npcs = filter_generated_destinations(generated_npcs_raw, stable_existing, 8.0, 8.0)
    mob_spawns = parse_mob_spawn_points(mob_spawn_points_path)
    generated_enemy_camps = cluster_enemy_camps(mob_spawns)
    generated = generated_zonelines + generated_npcs + generated_enemy_camps

    existing_zones = {row.zone for row in stable_existing}
    generated_zones = {row.zone for row in generated}
    print(f"parsed_zonelines={len(parsed_edges)} active_zonelines={len(edges)}")
    print(f"parsed_npc_destinations={len(generated_npcs_raw)} generated_npc_destinations={len(generated_npcs)}")
    print(f"parsed_mob_spawns={len(mob_spawns)} generated_enemy_camps={len(generated_enemy_camps)}")
    print(f"existing_destinations={len(stable_existing)} existing_zones={len(existing_zones)}")
    print(f"generated_missing_zonelines={len(generated_zonelines)} generated_total={len(generated)} generated_zones={len(generated_zones)}")
    print(f"post_write_zone_coverage={len(existing_zones | generated_zones)}")

    if args.write:
        digest = write_destination_copies(repo_root, lines, generated)
        print(f"wrote={repo_root / 'data' / 'ffxi-nav-destinations.tsv'}")
        print(
            "wrote="
            f"{repo_root / 'ashita' / 'addons' / 'accessxi_reader' / 'data' / 'ffxi-nav-destinations.tsv'}"
        )
        print(f"destination_sha256={digest}")
        print("graph_files=unchanged")
    elif not args.dry_run:
        print("No files written. Use --write to update nav data.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

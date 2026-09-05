"""Generate the four-zone Promyvion transition topology from LandSandBoat source.

WHY THIS FILE EXISTS
--------------------
The four Promyvions are floor-islands joined only by Memory Streams. LandSandBoat's
scripts/globals/promyvion.lua is the whole mechanism: eleven Memory Receptacles per zone,
each bound 1:1 to a Memory Stream; streams grouped per branch; ONE stream per group chosen
server-side at random ([Portal]Chosen -- invisible to every client, so deliberately NOT in
this data); a receptacle despawn opens its stream for 180 seconds (openDoor(180)) if and only
if that stream is the chosen one, then the choice re-randomizes. Returns and the exit are
plain trigger areas, always available.

WHAT IS PARSED VS WHAT IS REVIEWED CONFIG
-----------------------------------------
Parsed from the local checkout at third_party/LandSandBoat-server (no network, ever):
  - receptacleInfoTable per zone: receptacle index -> (portal group, stream offset).
  - npc_list.sql: the eleven consecutive stream NPC ids from each zone's marker name
    (_0g1 / _0i1 / _0k1 / _0m1, exactly what each IDs.lua GetFirstID resolves), with
    positions. Frame: game (x, z, y) = (pos_x, pos_z, pos_y); proven by _0g1 sitting
    0.07 yalms from its Zone.lua trigger circle.
  - mob_spawn_points.sql: Memory_Receptacle rows per zone id range, first eleven ascending
    -- the exact order GetTableOfIDs returns and receptacleInfoTable indexes.

Reviewed config, transcribed by hand from each Zone.lua (trigger registrations are numbers in
comments-adjacent code; their island/destination MEANING lives in comments, which are prose
and not safely machine-parseable). Every transcription is cross-checked at generation time:
each forward trigger's stream NPC must sit within SANITY_XZ of its trigger circle, and each
stream offset must appear exactly once across the zone's receptacle table.

DECOMPOSITION NOTE (deviation declared): Holla/Dem/Mea floor 4 returns to EITHER third-floor
island depending on a charvar no client can read, so the branch return is emitted as TWO rows,
one per destination. The column contract is unchanged.

DETERMINISM: sorted rows, LF endings, %.3f floats, no timestamps. Run twice, byte-identical.

  py tools/generate_promyvion_navigation.py
"""

from __future__ import annotations

import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LSB = ROOT / "third_party" / "LandSandBoat-server"
OUT = ROOT / "data" / "ffxi-nav-promyvion-transitions.tsv"

SANITY_XZ = 1.0
ENTITY_BLOCK = 0x1000  # ids per zone: 0x1000000 | (zone << 12) | index

COLUMNS = [
    "record_id", "zone", "island_id", "kind", "group_id", "name",
    "anchor_x", "anchor_z", "anchor_y", "radius",
    "entity_server_id", "paired_server_id",
    "destination_island", "landing_x", "landing_z", "landing_y",
    "availability", "window_seconds", "source", "confidence", "note",
]

# ---------------------------------------------------------------------------
# Reviewed per-zone config. Trigger ids, circles and event ids are copied from
# each scripts/zones/<zone>/Zone.lua registerCylindricalTriggerArea /
# onTriggerAreaEnter block; island names follow the Zone.lua comments; exits are
# the onEventFinish setPos calls (LSB setPos(x, y, z, rot[, zone]) -- y vertical).
# ---------------------------------------------------------------------------
ZONES = [
    {
        "zone": 16, "label": "Promyvion - Holla", "marker": "_0g1",
        "zone_in": (92.033, 80.380, 0.000),
        "islands": ["floor-1", "floor-2", "floor-3-west", "floor-3-east", "floor-4"],
        "exit": {"trigger": 1, "island": "floor-1", "x": 80.0, "z": 80.0,
                 "dest_zone": 14, "dest_name": "Hall of Transference",
                 "land": (-225.682, 280.002, -6.459), "event": 46},
        "returns": [
            {"trigger": 2, "island": "floor-2", "x": -120.0, "z": 0.0, "dest": ["floor-1"], "event": 41},
            {"trigger": 3, "island": "floor-3-west", "x": -160.0, "z": 120.0, "dest": ["floor-2"], "event": 42},
            {"trigger": 4, "island": "floor-3-east", "x": 160.0, "z": 240.0, "dest": ["floor-2"], "event": 45},
            {"trigger": 5, "island": "floor-4", "x": 120.0, "z": -320.0,
             "dest": ["floor-3-east", "floor-3-west"], "event": 43,
             "note": "destination follows charvar [Holla]ReturnWest; both rows emitted"},
        ],
        "forwards": [
            {"trigger": 6, "island": "floor-1", "x": -40.0, "z": 200.0, "offset": 7, "dest": "floor-2", "event": 37, "name": "Floor 1: Portal"},
            {"trigger": 7, "island": "floor-2", "x": -240.0, "z": 40.0, "offset": 3, "dest": "floor-3-east", "event": 33, "name": "Floor 2: Portal NW - Destination: East"},
            {"trigger": 8, "island": "floor-2", "x": -280.0, "z": -40.0, "offset": 4, "dest": "floor-3-west", "event": 34, "name": "Floor 2: Portal SW - Destination: West"},
            {"trigger": 9, "island": "floor-2", "x": -160.0, "z": -200.0, "offset": 5, "dest": "floor-3-east", "event": 35, "name": "Floor 2: Portal SE - Destination: East"},
            {"trigger": 10, "island": "floor-2", "x": 0.0, "z": -40.0, "offset": 6, "dest": "floor-3-west", "event": 36, "name": "Floor 2: Portal NE - Destination: West"},
            {"trigger": 11, "island": "floor-3-west", "x": -280.0, "z": 280.0, "offset": 0, "dest": "floor-4", "event": 30, "name": "Floor 3 (West): Portal NE"},
            {"trigger": 12, "island": "floor-3-west", "x": -360.0, "z": 240.0, "offset": 1, "dest": "floor-4", "event": 31, "name": "Floor 3 (West): Portal NW"},
            {"trigger": 13, "island": "floor-3-west", "x": -360.0, "z": 120.0, "offset": 2, "dest": "floor-4", "event": 32, "name": "Floor 3 (West): Portal SW"},
            {"trigger": 14, "island": "floor-3-east", "x": 40.0, "z": 320.0, "offset": 8, "dest": "floor-4", "event": 38, "name": "Floor 3 (East): Portal NW"},
            {"trigger": 15, "island": "floor-3-east", "x": 160.0, "z": 360.0, "offset": 9, "dest": "floor-4", "event": 39, "name": "Floor 3 (East): Portal NE"},
            {"trigger": 16, "island": "floor-3-east", "x": 280.0, "z": 200.0, "offset": 10, "dest": "floor-4", "event": 40, "name": "Floor 3 (East): Portal SE"},
        ],
    },
    {
        "zone": 18, "label": "Promyvion - Dem", "marker": "_0i1",
        "zone_in": (185.891, -52.331, 0.000),
        "islands": ["floor-1", "floor-2", "floor-3-north", "floor-3-south", "floor-4"],
        "exit": {"trigger": 1, "island": "floor-1", "x": 160.0, "z": -80.0,
                 "dest_zone": 14, "dest_name": "Hall of Transference",
                 "land": (-226.193, -280.046, -46.459), "event": 46},
        "returns": [
            {"trigger": 2, "island": "floor-2", "x": -280.0, "z": 0.0, "dest": ["floor-1"], "event": 41},
            {"trigger": 3, "island": "floor-3-north", "x": -160.0, "z": 440.0, "dest": ["floor-2"], "event": 43},
            {"trigger": 4, "island": "floor-3-south", "x": 0.0, "z": -320.0, "dest": ["floor-2"], "event": 42},
            {"trigger": 5, "island": "floor-4", "x": 360.0, "z": 240.0,
             "dest": ["floor-3-north", "floor-3-south"], "event": 44,
             "note": "destination follows charvar [Dem]ReturnNorth; both rows emitted"},
        ],
        "forwards": [
            {"trigger": 6, "island": "floor-1", "x": 120.0, "z": -280.0, "offset": 0, "dest": "floor-2", "event": 30, "name": "Floor 1: Portal"},
            {"trigger": 7, "island": "floor-2", "x": -80.0, "z": -80.0, "offset": 4, "dest": "floor-3-north", "event": 36, "name": "Floor 2: Portal SE - Destination: North"},
            {"trigger": 8, "island": "floor-2", "x": -80.0, "z": 80.0, "offset": 5, "dest": "floor-3-south", "event": 37, "name": "Floor 2: Portal NE - Destination: South"},
            {"trigger": 9, "island": "floor-2", "x": -280.0, "z": -200.0, "offset": 6, "dest": "floor-3-south", "event": 34, "name": "Floor 2: Portal SW - Destination: South"},
            {"trigger": 10, "island": "floor-2", "x": -360.0, "z": 40.0, "offset": 7, "dest": "floor-3-north", "event": 35, "name": "Floor 2: Portal NW - Destination: North"},
            {"trigger": 11, "island": "floor-3-south", "x": 40.0, "z": -200.0, "offset": 1, "dest": "floor-4", "event": 31, "name": "Floor 3 (South): Portal NE"},
            {"trigger": 12, "island": "floor-3-south", "x": -120.0, "z": -240.0, "offset": 2, "dest": "floor-4", "event": 32, "name": "Floor 3 (South): Portal NW"},
            {"trigger": 13, "island": "floor-3-south", "x": -120.0, "z": -400.0, "offset": 3, "dest": "floor-4", "event": 33, "name": "Floor 3 (South): Portal SW"},
            {"trigger": 14, "island": "floor-3-north", "x": -320.0, "z": 160.0, "offset": 8, "dest": "floor-4", "event": 38, "name": "Floor 3 (North): Portal SW"},
            {"trigger": 15, "island": "floor-3-north", "x": -40.0, "z": 320.0, "offset": 9, "dest": "floor-4", "event": 39, "name": "Floor 3 (North): Portal NE"},
            {"trigger": 16, "island": "floor-3-north", "x": -120.0, "z": 160.0, "offset": 10, "dest": "floor-4", "event": 40, "name": "Floor 3 (North): Portal SE"},
        ],
    },
    {
        "zone": 20, "label": "Promyvion - Mea", "marker": "_0k1",
        "zone_in": (-93.268, 170.749, 0.000),
        "islands": ["floor-1", "floor-2", "floor-3-west", "floor-3-east", "floor-4"],
        "exit": {"trigger": 1, "island": "floor-1", "x": -120.0, "z": 200.0,
                 "dest_zone": 14, "dest_name": "Hall of Transference",
                 "land": (279.988, -25.994, -86.459), "event": 46},
        "returns": [
            {"trigger": 2, "island": "floor-2", "x": 0.0, "z": -120.0, "dest": ["floor-1"], "event": 41},
            {"trigger": 3, "island": "floor-3-west", "x": -160.0, "z": 160.0, "dest": ["floor-2"], "event": 42},
            {"trigger": 4, "island": "floor-3-east", "x": 160.0, "z": -280.0, "dest": ["floor-2"], "event": 43},
            {"trigger": 5, "island": "floor-4", "x": -80.0, "z": 360.0,
             "dest": ["floor-3-west", "floor-3-east"], "event": 44,
             "note": "destination follows charvar [Mea]ReturnEast; both rows emitted"},
        ],
        "forwards": [
            {"trigger": 6, "island": "floor-1", "x": -280.0, "z": 240.0, "offset": 0, "dest": "floor-2", "event": 30, "name": "Floor 1: Portal"},
            {"trigger": 7, "island": "floor-2", "x": -80.0, "z": -40.0, "offset": 3, "dest": "floor-3-east", "event": 33, "name": "Floor 2: Portal N - Destination: East"},
            {"trigger": 8, "island": "floor-2", "x": -320.0, "z": -360.0, "offset": 7, "dest": "floor-3-west", "event": 37, "name": "Floor 2: Portal SW - Destination: West"},
            {"trigger": 9, "island": "floor-2", "x": -40.0, "z": -320.0, "offset": 8, "dest": "floor-3-west", "event": 38, "name": "Floor 2: Portal S - Destination: West"},
            {"trigger": 10, "island": "floor-2", "x": 80.0, "z": -240.0, "offset": 9, "dest": "floor-3-east", "event": 39, "name": "Floor 2: Portal SE - Destination: East"},
            {"trigger": 11, "island": "floor-3-west", "x": -320.0, "z": -40.0, "offset": 1, "dest": "floor-4", "event": 31, "name": "Floor 3 (West): Portal SW"},
            {"trigger": 12, "island": "floor-3-west", "x": -240.0, "z": -40.0, "offset": 2, "dest": "floor-4", "event": 32, "name": "Floor 3 (West): Portal S"},
            {"trigger": 13, "island": "floor-3-west", "x": -40.0, "z": 0.0, "offset": 4, "dest": "floor-4", "event": 34, "name": "Floor 3 (West): Portal SE"},
            {"trigger": 14, "island": "floor-3-east", "x": 200.0, "z": 0.0, "offset": 5, "dest": "floor-4", "event": 35, "name": "Floor 3 (East): Portal NW"},
            {"trigger": 15, "island": "floor-3-east", "x": 360.0, "z": -40.0, "offset": 6, "dest": "floor-4", "event": 36, "name": "Floor 3 (East): Portal NE"},
            {"trigger": 16, "island": "floor-3-east", "x": 240.0, "z": -320.0, "offset": 10, "dest": "floor-4", "event": 40, "name": "Floor 3 (East): Portal SW"},
        ],
    },
    {
        "zone": 22, "label": "Promyvion - Vahzl", "marker": "_0m1",
        "zone_in": (-14.744, -119.736, 0.036),
        "islands": ["floor-1", "floor-2", "floor-3", "floor-4", "floor-5"],
        "exit": {"trigger": 1, "island": "floor-1", "x": 0.0, "z": -120.0,
                 "dest_zone": 9, "dest_name": "Pso'Xja",
                 "land": (-379.947, 334.059, 48.045), "event": 45},
        "returns": [
            {"trigger": 2, "island": "floor-2", "x": -40.0, "z": 200.0, "dest": ["floor-1"], "event": 41},
            {"trigger": 3, "island": "floor-3", "x": 320.0, "z": -280.0, "dest": ["floor-2"], "event": 42},
            {"trigger": 4, "island": "floor-4", "x": 280.0, "z": 40.0, "dest": ["floor-3"], "event": 43},
            {"trigger": 5, "island": "floor-5", "x": -40.0, "z": 0.0, "dest": ["floor-4"], "event": 44},
        ],
        "forwards": [
            {"trigger": 6, "island": "floor-1", "x": -40.0, "z": -360.0, "offset": 2, "dest": "floor-2", "event": 32, "name": "Floor 1: Portal S"},
            {"trigger": 7, "island": "floor-1", "x": 80.0, "z": -40.0, "offset": 3, "dest": "floor-2", "event": 33, "name": "Floor 1: Portal N"},
            {"trigger": 8, "island": "floor-2", "x": -160.0, "z": 200.0, "offset": 0, "dest": "floor-3", "event": 30, "name": "Floor 2: Portal N"},
            {"trigger": 9, "island": "floor-2", "x": -160.0, "z": 120.0, "offset": 1, "dest": "floor-3", "event": 31, "name": "Floor 2: Portal S"},
            {"trigger": 10, "island": "floor-3", "x": 160.0, "z": -160.0, "offset": 5, "dest": "floor-4", "event": 35, "name": "Floor 3: Portal W"},
            {"trigger": 11, "island": "floor-3", "x": 240.0, "z": -40.0, "offset": 6, "dest": "floor-4", "event": 36, "name": "Floor 3: Portal N"},
            {"trigger": 12, "island": "floor-3", "x": 240.0, "z": -240.0, "offset": 7, "dest": "floor-4", "event": 37, "name": "Floor 3: Portal S"},
            {"trigger": 13, "island": "floor-3", "x": 360.0, "z": -80.0, "offset": 8, "dest": "floor-4", "event": 38, "name": "Floor 3: Portal E"},
            {"trigger": 14, "island": "floor-4", "x": 120.0, "z": 40.0, "offset": 4, "dest": "floor-5", "event": 34, "name": "Floor 4: Portal SW"},
            {"trigger": 15, "island": "floor-4", "x": 440.0, "z": 40.0, "offset": 9, "dest": "floor-5", "event": 39, "name": "Floor 4: Portal SE"},
            {"trigger": 16, "island": "floor-4", "x": 440.0, "z": 279.0, "offset": 10, "dest": "floor-5", "event": 40, "name": "Floor 4: Portal NE"},
        ],
    },
]

ZONE_KEYS = {16: "PROMYVION_HOLLA", 18: "PROMYVION_DEM", 20: "PROMYVION_MEA", 22: "PROMYVION_VAHZL"}


def fail(message):
    print("GENERATION FAILED: " + message)
    sys.exit(1)


def zone_id_range(zone):
    base = 0x1000000 | (zone << 12)
    return base, base + ENTITY_BLOCK


def parse_receptacle_table(text, zone):
    """receptacle index -> (group, stream offset), from receptacleInfoTable."""
    key = ZONE_KEYS[zone]
    block_re = re.compile(
        r"\[xi\.zone\." + key + r"\]\s*=\s*\{(.*?)\n\s*\},", re.S)
    blocks = block_re.findall(text)
    # The file contains two per-zone tables (receptacleInfoTable, portalGroupTable);
    # the receptacle one is the one keyed by MEMORY_RECEPTACLE_TABLE.
    block = None
    for candidate in blocks:
        if "MEMORY_RECEPTACLE_TABLE" in candidate:
            block = candidate
            break
    if block is None:
        fail("receptacleInfoTable block not found for zone %d" % zone)
    row_re = re.compile(
        r"MEMORY_RECEPTACLE_TABLE\[(\d+)\]\s*\]\s*=\s*\{\s*(\d+)\s*,\s*\d+\s*,"
        r"\s*\w+ID\.npc\.MEMORY_STREAM_OFFSET(?:\s*\+\s*(\d+))?\s*\}")
    mapping = {}
    for index, group, offset in row_re.findall(block):
        mapping[int(index)] = (int(group), int(offset or 0))
    if len(mapping) != 11:
        fail("zone %d receptacle mapping has %d rows, wanted 11" % (zone, len(mapping)))
    offsets = sorted(offset for _, offset in mapping.values())
    if offsets != list(range(11)):
        fail("zone %d stream offsets are not exactly 0..10: %s" % (zone, offsets))
    return mapping


def parse_streams(npc_sql, zone, marker):
    """Eleven consecutive stream NPCs from the zone's marker name."""
    low, high = zone_id_range(zone)
    row_re = re.compile(
        r"VALUES\s*\((\d+),'([^']*)','([^']*)',[-\d.]+,([-\d.]+),([-\d.]+),([-\d.]+),")
    rows = {}
    first = None
    for npc_id, name, polutils, x, y, z in row_re.findall(npc_sql):
        npc_id = int(npc_id)
        if low <= npc_id < high:
            rows[npc_id] = {
                "id": npc_id, "name": name, "polutils": polutils,
                "x": float(x), "y": float(y), "z": float(z),
            }
            if name == marker:
                first = npc_id
    if first is None:
        fail("zone %d stream marker %s not found in npc_list" % (zone, marker))
    streams = {}
    for offset in range(11):
        row = rows.get(first + offset)
        if row is None:
            fail("zone %d stream offset %d (id %d) missing from npc_list"
                 % (zone, offset, first + offset))
        streams[offset] = row
    return streams


def parse_receptacles(mob_sql, zone):
    """First eleven Memory_Receptacle spawn rows ascending -- GetTableOfIDs order."""
    low, high = zone_id_range(zone)
    row_re = re.compile(
        r"VALUES\s*\((\d+),\d+,'Memory_Receptacle','[^']*',\d+,\d+,\d+,"
        r"([-\d.]+),([-\d.]+),([-\d.]+),")
    rows = []
    for mob_id, x, y, z in row_re.findall(mob_sql):
        mob_id = int(mob_id)
        if low <= mob_id < high:
            rows.append({"id": mob_id, "x": float(x), "y": float(y), "z": float(z)})
    rows.sort(key=lambda row: row["id"])
    if len(rows) < 11:
        fail("zone %d has %d Memory_Receptacle spawns, wanted at least 11" % (zone, len(rows)))
    return {index + 1: row for index, row in enumerate(rows[:11])}


def fmt(value):
    return "%.3f" % value


def main():
    promyvion = io.open(
        LSB / "scripts" / "globals" / "promyvion.lua", encoding="utf-8").read()
    npc_sql = io.open(LSB / "sql" / "npc_list.sql", encoding="utf-8", errors="replace").read()
    mob_sql = io.open(
        LSB / "sql" / "mob_spawn_points.sql", encoding="utf-8", errors="replace").read()

    out_rows = []
    for config in ZONES:
        zone = config["zone"]
        mapping = parse_receptacle_table(promyvion, zone)
        streams = parse_streams(npc_sql, zone, config["marker"])
        receptacles = parse_receptacles(mob_sql, zone)

        # Bind offset -> (receptacle index, group). Exactly one receptacle per stream.
        offset_to_receptacle = {}
        for index, (group, offset) in mapping.items():
            if offset in offset_to_receptacle:
                fail("zone %d stream offset %d bound twice" % (zone, offset))
            offset_to_receptacle[offset] = (index, group)

        # Island anchors: floor-1 is the zone-in point (from Zone.lua onZoneIn);
        # others use their return trigger circle. Anchor height is the mean of the
        # island's stream NPC heights -- real parsed data -- or inferred 0 for an
        # island with no streams (Vahzl floor-5, the boss floor).
        island_streams = {}
        for forward in config["forwards"]:
            island_streams.setdefault(forward["island"], []).append(
                streams[forward["offset"]]["y"])
        island_anchor = {}
        first_island = config["islands"][0]
        island_anchor[first_island] = (
            config["zone_in"][0], config["zone_in"][1], config["zone_in"][2], "lsb")
        for entry in config["returns"]:
            heights = island_streams.get(entry["island"])
            if heights:
                height = sum(heights) / len(heights)
                confidence = "lsb"
            else:
                height = 0.0
                confidence = "inferred"
            island_anchor[entry["island"]] = (entry["x"], entry["z"], height, confidence)
        for island in config["islands"]:
            if island not in island_anchor:
                fail("zone %d island %s has no anchor source" % (zone, island))

        source = ("lsb:scripts/globals/promyvion.lua+scripts/zones/%s/Zone.lua"
                  "+sql/npc_list.sql+sql/mob_spawn_points.sql"
                  % config["label"].replace(" - ", "-").replace(" ", "_"))

        # Island rows. Entity ids deliberately blank.
        for island in config["islands"]:
            x, z, y, confidence = island_anchor[island]
            out_rows.append({
                "record_id": "%d:island:%s" % (zone, island),
                "zone": str(zone), "island_id": island, "kind": "island",
                "group_id": "", "name": "%s %s" % (config["label"], island.replace("-", " ")),
                "anchor_x": fmt(x), "anchor_z": fmt(z), "anchor_y": fmt(y), "radius": "",
                "entity_server_id": "", "paired_server_id": "",
                "destination_island": "", "landing_x": "", "landing_z": "", "landing_y": "",
                "availability": "", "window_seconds": "0",
                "source": source, "confidence": confidence,
                "note": "anchor is the zone-in point" if island == first_island
                        else ("anchor is the return trigger; height from island stream NPCs"
                              if island_streams.get(island) else
                              "anchor is the return trigger; no streams on this island, height inferred"),
            })

        # Forward rows: the receptacle/stream pair, anchored on the walk-in
        # trigger circle. The landing is the destination island's anchor,
        # inferred until walked. NEVER records which stream is chosen -- that is
        # server-side random and unknowable by any client.
        for forward in config["forwards"]:
            stream = streams[forward["offset"]]
            index, group = offset_to_receptacle[forward["offset"]]
            receptacle = receptacles[index]
            drift = ((stream["x"] - forward["x"]) ** 2 + (stream["z"] - forward["z"]) ** 2) ** 0.5
            if drift > SANITY_XZ:
                fail("zone %d trigger %d: stream %s sits %.2f yalms from its circle"
                     % (zone, forward["trigger"], stream["name"], drift))
            dest = forward["dest"]
            land_x, land_z, land_y, _ = island_anchor[dest]
            out_rows.append({
                "record_id": "%d:forward:%02d" % (zone, forward["trigger"]),
                "zone": str(zone), "island_id": forward["island"], "kind": "forward",
                "group_id": str(group), "name": forward["name"],
                "anchor_x": fmt(forward["x"]), "anchor_z": fmt(forward["z"]),
                "anchor_y": fmt(stream["y"]), "radius": "3",
                "entity_server_id": str(stream["id"]),
                "paired_server_id": str(receptacle["id"]),
                "destination_island": dest,
                "landing_x": fmt(land_x), "landing_z": fmt(land_z), "landing_y": fmt(land_y),
                "availability": "stream-open-evidence", "window_seconds": "180",
                "source": source, "confidence": "lsb",
                "note": ("stream npc %s/%s; receptacle at (%s, %s, %s); event %d; "
                         "landing inferred from destination anchor, unwalked")
                        % (stream["name"], stream["polutils"],
                           fmt(receptacle["x"]), fmt(receptacle["z"]), fmt(receptacle["y"]),
                           forward["event"]),
            })

        # Return rows: always available. A branch return (floor 4 of Holla, Dem
        # and Mea) is one trigger with a charvar-selected destination no client
        # can read, so one row per destination is the only honest decomposition.
        for entry in config["returns"]:
            branch = len(entry["dest"]) > 1
            for dest in entry["dest"]:
                record_id = "%d:return:%02d" % (zone, entry["trigger"])
                if branch:
                    record_id += ":" + dest
                land_x, land_z, land_y, _ = island_anchor[dest]
                out_rows.append({
                    "record_id": record_id,
                    "zone": str(zone), "island_id": entry["island"], "kind": "return",
                    "group_id": "", "name": "%s: Return to %s"
                        % (entry["island"].replace("-", " "), dest.replace("-", " ")),
                    "anchor_x": fmt(entry["x"]), "anchor_z": fmt(entry["z"]),
                    "anchor_y": fmt(island_anchor[entry["island"]][2]), "radius": "3",
                    "entity_server_id": "", "paired_server_id": "",
                    "destination_island": dest,
                    "landing_x": fmt(land_x), "landing_z": fmt(land_z), "landing_y": fmt(land_y),
                    "availability": "always", "window_seconds": "0",
                    "source": source, "confidence": "lsb",
                    "note": (entry.get("note", "") + ("; " if entry.get("note") else "")
                             + "event %d; landing inferred from destination anchor, unwalked"
                             % entry["event"]),
                })

        # The exit: a scripted teleport out of the zone, landing exact from
        # Zone.lua's own setPos.
        exit_config = config["exit"]
        out_rows.append({
            "record_id": "%d:exit:%02d" % (zone, exit_config["trigger"]),
            "zone": str(zone), "island_id": exit_config["island"], "kind": "exit",
            "group_id": "", "name": "Exit to %s" % exit_config["dest_name"],
            "anchor_x": fmt(exit_config["x"]), "anchor_z": fmt(exit_config["z"]),
            "anchor_y": fmt(island_anchor[exit_config["island"]][2]), "radius": "3",
            "entity_server_id": "", "paired_server_id": "",
            "destination_island": "zone:%d" % exit_config["dest_zone"],
            "landing_x": fmt(exit_config["land"][0]), "landing_z": fmt(exit_config["land"][1]),
            "landing_y": fmt(exit_config["land"][2]),
            "availability": "always", "window_seconds": "0",
            "source": source, "confidence": "lsb",
            "note": "event %d; landing is Zone.lua's own setPos" % exit_config["event"],
        })

    kind_rank = {"island": 0, "forward": 1, "return": 2, "exit": 3}
    out_rows.sort(key=lambda row: (int(row["zone"]), kind_rank[row["kind"]], row["record_id"]))

    lines = [
        "# Promyvion same-zone transition topology for zones 16 (Holla), 18 (Dem), 20 (Mea), 22 (Vahzl).",
        "# Generated by tools/generate_promyvion_navigation.py from the local LandSandBoat checkout;",
        "# regenerate rather than hand-edit. One row per island, forward receptacle/stream pair,",
        "# return trigger and exit. forward availability is stream-open-evidence: a Memory Stream is",
        "# OPEN only while live entity evidence says so (LSB opens the chosen stream for 180 seconds",
        "# after its receptacle dies, then re-randomizes the choice; the choice itself is server-side",
        "# and deliberately NOT recorded here). entity_server_id is the stream NPC to watch;",
        "# paired_server_id is the receptacle whose death opens it. Landings marked unwalked are",
        "# inferred from destination anchors and must not be spoken as verified.",
        "\t".join(COLUMNS),
    ]
    for row in out_rows:
        lines.append("\t".join(row[column] for column in COLUMNS))
    payload = "\n".join(lines) + "\n"
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)
    print("wrote %s (%d rows)" % (OUT, len(out_rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

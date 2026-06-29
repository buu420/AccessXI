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
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(r"C:\Users\buu42\AccessXI")
DESTINATIONS = ROOT / "data" / "ffxi-nav-destinations.tsv"
GRAPH = ROOT / "data" / "ffxi-nav-zoneline-graph.tsv"
ZONELINES = ROOT / "data" / "lsb_zonelines.sql"
NPC_LIST = ROOT / "data" / "lsb_npc_list.sql"
ZONE_IDS = ROOT / "third_party" / "LandSandBoat-server" / "documentation" / "ZoneIDs.txt"

GENERATED_SOURCE = "lsb-zoneline-all"
GENERATED_NPC_SOURCE = "lsb-npc-list-all"
GENERATED_SECTION = "world-zonelines-2026-06-20"
GENERATED_NPC_SECTION = "world-npcs-2026-06-20"
SKIP_DISTANCE_YALMS = 2.0


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
    pattern = re.compile(r"INSERT INTO `npc_list` VALUES \((.*)\);")
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = pattern.search(line)
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
            )
        )
    return rows


def read_destinations(path: Path) -> tuple[list[str], list[Destination]]:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    destinations: list[Destination] = []
    for line in lines:
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 7:
            continue
        try:
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
                )
            )
        except ValueError:
            continue
    return lines, destinations


def distance_2d(a: Destination, b: Destination) -> float:
    return ((a.x - b.x) ** 2 + (a.z - b.z) ** 2) ** 0.5


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
    return Destination(
        zone=edge.from_zone,
        name=name,
        x=edge.from_x,
        z=edge.from_z,
        y=edge.from_y,
        kind="area",
        source=GENERATED_SOURCE,
        confidence="untested",
        section=destination_section(edge),
    )


def existing_nearby(destination: Destination, existing: list[Destination]) -> bool:
    for old in existing:
        if old.zone != destination.zone:
            continue
        if old.kind.lower() != "area":
            continue
        if distance_2d(old, destination) <= SKIP_DISTANCE_YALMS and abs(old.y - destination.y) <= 8.0:
            return True
    return False


def generate_destinations(edges: list[ZoneLine], zone_names: dict[int, str], existing: list[Destination]) -> list[Destination]:
    base_counts = Counter((edge.from_zone, base_name(edge, zone_names)) for edge in edges)
    generated: list[Destination] = []
    for edge in edges:
        name = base_name(edge, zone_names)
        if base_counts[(edge.from_zone, name)] > 1 and edge.from_code:
            name = f"{name} {edge.from_code}"
        destination = generated_destination(edge, name)
        if not existing_nearby(destination, existing):
            generated.append(destination)
    return generated


def write_destination_file(path: Path, lines: list[str], generated: list[Destination]) -> None:
    retained = [
        line
        for line in lines
        if not (
            (line.startswith("# Generated from ") or line.startswith("# Generated rows are "))
            or (
                line
                and not line.startswith("#")
                and (
                    f"\t{GENERATED_SOURCE}\t" in f"\t{line}\t"
                    or f"\t{GENERATED_NPC_SOURCE}\t" in f"\t{line}\t"
                )
            )
        )
    ]
    if retained and retained[-1] != "":
        retained.append("")
    retained.append(f"# Generated from {ZONELINES} by tools/generate_nav_zoneline_destinations.py.")
    retained.append("# Generated rows are untested until route evidence proves them.")
    for row in sorted(generated, key=lambda d: (d.zone, d.kind, d.name.lower(), d.x, d.z)):
        retained.append(
            f"{row.zone}\t{row.name}\t{row.x:.3f}\t{row.z:.3f}\t{row.y:.3f}\t"
            f"{row.kind}\t{row.source}\t{row.confidence}\t{row.section}"
        )
    path.write_text("\n".join(retained) + "\n", encoding="utf-8")


def write_graph(path: Path, edges: list[ZoneLine], zone_names: dict[int, str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(
            [
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
            ]
        )
        for edge in sorted(edges, key=lambda e: (e.from_zone, e.to_zone, e.from_code, e.to_code, e.zoneline_id)):
            writer.writerow(
                [
                    edge.zoneline_id,
                    edge.from_zone,
                    zone_names.get(edge.from_zone, edge.from_label or f"Zone {edge.from_zone}"),
                    edge.from_code,
                    f"{edge.from_x:.3f}",
                    f"{edge.from_z:.3f}",
                    f"{edge.from_y:.3f}",
                    edge.to_zone,
                    zone_names.get(edge.to_zone, edge.to_label or f"Zone {edge.to_zone}"),
                    edge.to_code,
                    f"{edge.to_x:.3f}",
                    f"{edge.to_z:.3f}",
                    f"{edge.to_y:.3f}",
                    "lsb-zonelines",
                    "untested",
                    edge.note,
                ]
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Report counts without writing files.")
    parser.add_argument("--write", action="store_true", help="Write generated destination and graph files.")
    args = parser.parse_args()

    zone_names = parse_zone_ids(ZONE_IDS)
    edges = parse_zonelines(ZONELINES)
    lines, existing = read_destinations(DESTINATIONS)
    stable_existing = [row for row in existing if row.source not in (GENERATED_SOURCE, GENERATED_NPC_SOURCE)]
    generated_zonelines = generate_destinations(edges, zone_names, stable_existing)
    generated_npcs = parse_npc_list(NPC_LIST)
    generated = generated_zonelines + generated_npcs

    existing_zones = {row.zone for row in stable_existing}
    generated_zones = {row.zone for row in generated}
    print(f"parsed_zonelines={len(edges)}")
    print(f"parsed_npc_destinations={len(generated_npcs)}")
    print(f"existing_destinations={len(stable_existing)} existing_zones={len(existing_zones)}")
    print(f"generated_missing_zonelines={len(generated_zonelines)} generated_total={len(generated)} generated_zones={len(generated_zones)}")
    print(f"post_write_zone_coverage={len(existing_zones | generated_zones)}")

    if args.write:
        write_destination_file(DESTINATIONS, lines, generated)
        write_graph(GRAPH, edges, zone_names)
        print(f"wrote={DESTINATIONS}")
        print(f"wrote={GRAPH}")
    elif not args.dry_run:
        print("No files written. Use --write to update nav data.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

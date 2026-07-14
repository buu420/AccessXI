#!/usr/bin/env python3
"""Build the proven directional West route from two live recordings."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


FRIEND_SESSION_ID = "20260712-170700-z102"
ESCAPE_SESSION_ID = "20260712-143554-z102"
ROUTE_ID = "lathine-recorded-corridor-20260712-west-via-ravine-01"
RECOVERY_ROUTE_ID = "lathine-recorded-corridor-20260712-west-via-ravine-01-recovery"
FULL_SURVEY_ROUTE_ID = "lathine-recorded-corridor-20260712-west-via-cliff-path-03"
FRIEND_START = 3985
FRIEND_END = 4006
ESCAPE_START = 2
ESCAPE_END = 323
HANDOFF_LIMIT = 1.0
SIMPLIFICATION_TOLERANCE = 0.25
DELICATE_ESCAPE_START = 85
DELICATE_ESCAPE_END = 140


def load_session(path: Path, session_id: str) -> list[dict[str, object]]:
    with path.open("r", encoding="utf-8", newline="") as stream:
        rows = [
            row
            for row in csv.DictReader(stream, delimiter="\t")
            if row["session"] == session_id
        ]
    for row in rows:
        row["seq"] = int(row["seq"])
        row["x"] = float(row["x"])
        row["z"] = float(row["z"])
        row["y"] = float(row["y"])
    return rows


def selected_rows(recording: Path) -> list[tuple[str, dict[str, object]]]:
    friend = load_session(recording, FRIEND_SESSION_ID)
    escape = load_session(recording, ESCAPE_SESSION_ID)
    friend_segment = [
        ("friend walk", row)
        for row in friend
        if FRIEND_START <= int(row["seq"]) <= FRIEND_END
    ]
    escape_segment = [
        ("ravine escape", row)
        for row in escape
        if ESCAPE_START <= int(row["seq"]) <= ESCAPE_END
    ]
    if len(friend_segment) != 22:
        raise RuntimeError(f"Expected 22 friend-walk rows; found {len(friend_segment)}")
    if len(escape_segment) != 322:
        raise RuntimeError(f"Expected 322 ravine-escape rows; found {len(escape_segment)}")

    left = friend_segment[-1][1]
    right = escape_segment[0][1]
    handoff = math.sqrt(
        (float(left["x"]) - float(right["x"])) ** 2
        + (float(left["z"]) - float(right["z"])) ** 2
        + (float(left["y"]) - float(right["y"])) ** 2
    )
    if handoff > HANDOFF_LIMIT:
        raise RuntimeError(f"Recorded handoff is {handoff:.3f} yalms; limit is {HANDOFF_LIMIT:.1f}")
    return friend_segment + escape_segment


def recovery_rows(recording: Path) -> list[tuple[str, dict[str, object]]]:
    friend = load_session(recording, FRIEND_SESSION_ID)
    escape = load_session(recording, ESCAPE_SESSION_ID)
    friend_by_seq = {int(row["seq"]): row for row in friend}
    escape_segment = [
        ("ravine escape", row)
        for row in escape
        if ESCAPE_START <= int(row["seq"]) <= ESCAPE_END
    ]
    shelf_segment = [
        ("upper shelf recovery", friend_by_seq[seq])
        for seq in range(4012, 4005, -1)
    ]
    left = shelf_segment[-1][1]
    right = escape_segment[0][1]
    handoff = math.sqrt(
        (float(left["x"]) - float(right["x"])) ** 2
        + (float(left["z"]) - float(right["z"])) ** 2
        + (float(left["y"]) - float(right["y"])) ** 2
    )
    if handoff > HANDOFF_LIMIT:
        raise RuntimeError(f"Recovery handoff is {handoff:.3f} yalms; limit is {HANDOFF_LIMIT:.1f}")
    return shelf_segment + escape_segment


def full_survey_west_rows(recording: Path) -> list[tuple[str, dict[str, object]]]:
    friend = load_session(recording, FRIEND_SESSION_ID)
    escape = load_session(recording, ESCAPE_SESSION_ID)
    friend_by_seq = {int(row["seq"]): row for row in friend}
    escape_by_seq = {int(row["seq"]): row for row in escape}

    cliff_path = [
        ("cliff path 3 forward exit", friend_by_seq[seq])
        for seq in range(4479, 4489)
    ]
    escape_segment = [
        ("ravine escape", escape_by_seq[seq])
        for seq in range(86, 324)
    ]

    distance = math.dist(point(cliff_path[-1][1]), point(escape_segment[0][1]))
    if distance > HANDOFF_LIMIT:
        raise RuntimeError(
            f"forward survey to ravine escape handoff is {distance:.3f} yalms; "
            f"limit is {HANDOFF_LIMIT:.1f}"
        )

    selected = cliff_path + escape_segment
    if len(selected) != 248:
        raise RuntimeError(f"Expected 248 complete forward-walked rows; found {len(selected)}")
    return selected


def point(record: dict[str, object]) -> tuple[float, float, float]:
    return float(record["x"]), float(record["z"]), float(record["y"])


def point_segment_distance(
    value: tuple[float, float, float],
    left: tuple[float, float, float],
    right: tuple[float, float, float],
) -> float:
    vector = tuple(right[index] - left[index] for index in range(3))
    offset = tuple(value[index] - left[index] for index in range(3))
    length2 = sum(component * component for component in vector)
    ratio = max(0.0, min(1.0, sum(offset[index] * vector[index] for index in range(3)) / length2)) if length2 else 0.0
    projected = tuple(left[index] + ratio * vector[index] for index in range(3))
    return math.dist(value, projected)


def simplify_section(
    selected: list[tuple[str, dict[str, object]]],
    start: int,
    end: int,
    retained: set[int],
) -> None:
    best_distance = -1.0
    best_index = -1
    left = point(selected[start][1])
    right = point(selected[end][1])
    for index in range(start + 1, end):
        distance = point_segment_distance(point(selected[index][1]), left, right)
        if distance > best_distance:
            best_distance = distance
            best_index = index
    if best_distance > SIMPLIFICATION_TOLERANCE:
        simplify_section(selected, start, best_index, retained)
        simplify_section(selected, best_index, end, retained)
    else:
        retained.add(start)
        retained.add(end)


def simplify_recorded_sections(
    selected: list[tuple[str, dict[str, object]]],
) -> list[tuple[str, dict[str, object]]]:
    retained: set[int] = set()
    start = 0
    while start < len(selected):
        label = selected[start][0]
        end = start
        while end + 1 < len(selected) and selected[end + 1][0] == label:
            end += 1
        if end == start:
            retained.add(start)
        else:
            simplify_section(selected, start, end, retained)
        start = end + 1
    for index, (label, row) in enumerate(selected):
        if (
            label == "ravine escape"
            and DELICATE_ESCAPE_START <= int(row["seq"]) <= DELICATE_ESCAPE_END
        ):
            retained.add(index)
    return [selected[index] for index in sorted(retained)]


def format_rows(selected: list[tuple[str, dict[str, object]]], route_id: str) -> list[str]:
    min_x = min(float(row["x"]) for _, row in selected)
    max_x = max(float(row["x"]) for _, row in selected)
    min_z = min(float(row["z"]) for _, row in selected)
    max_z = max(float(row["z"]) for _, row in selected)
    destination = selected[-1][1]
    output = []
    for sequence, (label, row) in enumerate(selected, 1):
        output.append(
            "\t".join(
                (
                    route_id,
                    "102",
                    "Recorded directional West escape handoff",
                    f'{float(destination["x"]):.3f}',
                    f'{float(destination["z"]):.3f}',
                    f'{float(destination["y"]):.3f}',
                    "2.0",
                    f"{min_x:.3f}",
                    f"{max_x:.3f}",
                    f"{min_z:.3f}",
                    f"{max_z:.3f}",
                    str(sequence),
                    f'{float(row["x"]):.3f}',
                    f'{float(row["z"]):.3f}',
                    f'{float(row["y"]):.3f}',
                    "live-route-recordings-directional-20260712",
                    "proven",
                    f'{label} sample {int(row["seq"])}',
                )
            )
        )
    return output


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("recording", type=Path)
    args = parser.parse_args()
    routes = (
        (ROUTE_ID, simplify_recorded_sections(selected_rows(args.recording))),
        (RECOVERY_ROUTE_ID, simplify_recorded_sections(recovery_rows(args.recording))),
        (FULL_SURVEY_ROUTE_ID, full_survey_west_rows(args.recording)),
    )
    for route_id, selected in routes:
        for row in format_rows(selected, route_id):
            print(row)


if __name__ == "__main__":
    main()

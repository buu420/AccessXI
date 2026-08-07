$ErrorActionPreference = 'Stop'

$python = 'C:\Users\buu42\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$data = 'C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv'
$recording = 'C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv'

$script = @'
import csv
import math
import sys

data_path, recording_path = sys.argv[1:]
headers = [
    'route_id', 'zone', 'destination_name', 'destination_x', 'destination_z', 'destination_y',
    'match_radius', 'min_x', 'max_x', 'min_z', 'max_z', 'sequence',
    'waypoint_x', 'waypoint_z', 'waypoint_y', 'source', 'confidence', 'note'
]
with open(data_path, encoding='utf-8', newline='') as stream:
    data = list(csv.DictReader(stream, delimiter='\t', fieldnames=headers))
with open(recording_path, encoding='utf-8', newline='') as stream:
    recorded = list(csv.DictReader(stream, delimiter='\t'))

sessions = {}
for row in recorded:
    sessions.setdefault(row['session'], {})[int(row['seq'])] = (
        float(row['x']), float(row['z']), float(row['y'])
    )

def point_segment_distance(point, left, right):
    vector = tuple(right[i] - left[i] for i in range(3))
    offset = tuple(point[i] - left[i] for i in range(3))
    length2 = sum(value * value for value in vector)
    t = max(0.0, min(1.0, sum(offset[i] * vector[i] for i in range(3)) / length2)) if length2 else 0.0
    projected = tuple(left[i] + t * vector[i] for i in range(3))
    return math.dist(point, projected)

def check_section(route, prefix, session, raw_start, raw_end, expected_first, expected_last):
    retained = []
    for row in route:
        if row['note'].startswith(prefix + ' sample '):
            retained.append((int(row['note'].split()[-1]), (
                float(row['waypoint_x']), float(row['waypoint_z']), float(row['waypoint_y'])
            )))
    assert retained[0][0] == expected_first, (prefix, 'first', retained[0][0], expected_first)
    assert retained[-1][0] == expected_last, (prefix, 'last', retained[-1][0], expected_last)
    raw = sessions[session]
    for (left_seq, left), (right_seq, right) in zip(retained, retained[1:]):
        step = 1 if right_seq >= left_seq else -1
        for seq in range(left_seq, right_seq + step, step):
            deviation = point_segment_distance(raw[seq], left, right)
            assert deviation <= 0.251, (prefix, left_seq, right_seq, seq, deviation)

routes = (
    ('lathine-recorded-corridor-20260712-west-via-ravine-01', 164, 'friend walk', 3985, 4006),
    ('lathine-recorded-corridor-20260712-west-via-ravine-01-recovery', 157, 'upper shelf recovery', 4012, 4006),
)
for route_id, expected_count, prefix, first, last in routes:
    route = sorted((row for row in data if row['route_id'] == route_id), key=lambda row: int(row['sequence']))
    assert len(route) == expected_count, (route_id, len(route), expected_count)
    check_section(route, prefix, '20260712-170700-z102', first, last, first, last)
    check_section(route, 'ravine escape', '20260712-143554-z102', 2, 323, 2, 323)
    handoff_index = next(i for i, row in enumerate(route) if row['note'] == 'ravine escape sample 2')
    handoff = math.dist(
        tuple(float(route[handoff_index - 1][key]) for key in ('waypoint_x', 'waypoint_z', 'waypoint_y')),
        tuple(float(route[handoff_index][key]) for key in ('waypoint_x', 'waypoint_z', 'waypoint_y')),
    )
    assert handoff <= 1.0, (route_id, 'handoff', handoff)

print('directional route simplification stays within 0.25 yalms of raw recordings')
'@

$output = $script | & $python - $data $recording
if ($LASTEXITCODE -ne 0) { throw "Directional route simplification regression failed: $output" }
Write-Host $output

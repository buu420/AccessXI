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
    recordings = list(csv.DictReader(stream, delimiter='\t'))

raw = {
    int(row['seq']): (float(row['x']), float(row['z']), float(row['y']))
    for row in recordings
    if row['session'] == '20260712-143554-z102'
}

route_ids = (
    'lathine-recorded-corridor-20260712-west-via-ravine-01',
    'lathine-recorded-corridor-20260712-west-via-ravine-01-recovery',
)
for route_id in route_ids:
    route = sorted(
        (row for row in data if row['route_id'] == route_id),
        key=lambda row: int(row['sequence']),
    )
    by_sample = {
        int(row['note'].split()[-1]): row
        for row in route
        if row['note'].startswith('ravine escape sample ')
    }
    for sample in range(85, 141):
        assert sample in by_sample, (route_id, 'missing delicate raw sample', sample)
        row = by_sample[sample]
        actual = tuple(float(row[key]) for key in ('waypoint_x', 'waypoint_z', 'waypoint_y'))
        assert math.dist(actual, raw[sample]) <= 0.001, (route_id, sample, actual, raw[sample])

print('La Theine delicate curve retains every raw walked sample')
'@

$output = $script | & $python - $data $recording
if ($LASTEXITCODE -ne 0) { throw "La Theine delicate-curve sample regression failed: $output" }
Write-Host $output

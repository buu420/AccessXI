$ErrorActionPreference = 'Stop'

$routeId = 'lathine-recorded-corridor-20260712-west-via-cliff-path-03'
$recordingPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv'
$overridePaths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
)
$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'

$headers = @(
    'route_id', 'zone', 'destination_name', 'destination_x', 'destination_z', 'destination_y',
    'match_radius', 'min_x', 'max_x', 'min_z', 'max_z', 'sequence',
    'waypoint_x', 'waypoint_z', 'waypoint_y', 'source', 'confidence', 'note'
)

function Distance3($Left, $Right) {
    $dx = [double]$Left.x - [double]$Right.x
    $dz = [double]$Left.z - [double]$Right.z
    $dy = [double]$Left.y - [double]$Right.y
    return [math]::Sqrt(($dx * $dx) + ($dz * $dz) + ($dy * $dy))
}

$recorded = @(Import-Csv -LiteralPath $recordingPath -Delimiter "`t")
$friend = @($recorded | Where-Object { $_.session -eq '20260712-170700-z102' })
$escape = @($recorded | Where-Object { $_.session -eq '20260712-143554-z102' })
$friendBySeq = @{}
foreach ($row in $friend) { $friendBySeq[[int]$row.seq] = $row }
$escapeBySeq = @{}
foreach ($row in $escape) { $escapeBySeq[[int]$row.seq] = $row }

$expected = @()
for ($seq = 4479; $seq -le 4488; $seq++) { $expected += $friendBySeq[$seq] }
for ($seq = 86; $seq -le 323; $seq++) { $expected += $escapeBySeq[$seq] }
if ($expected.Count -ne 248) { throw "Expected 248 complete forward-walked samples, found $($expected.Count)." }

if ((Distance3 $friendBySeq[4488] $escapeBySeq[86]) -gt 1.0) {
    throw 'The forward survey to ravine-escape handoff is not recorded-close.'
}

foreach ($path in $overridePaths) {
    $route = @(Import-Csv -LiteralPath $path -Delimiter "`t" -Header $headers |
        Where-Object { $_.route_id -eq $routeId } |
        Sort-Object { [int]$_.sequence })
    if ($route.Count -ne 248) { throw "Complete 248-sample forward survey route missing from $path." }
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($route[$i].waypoint_x -ne ([double]$expected[$i].x).ToString('0.000') -or
            $route[$i].waypoint_z -ne ([double]$expected[$i].z).ToString('0.000') -or
            $route[$i].waypoint_y -ne ([double]$expected[$i].y).ToString('0.000')) {
            throw "Recorded sample mismatch at route sequence $($i + 1) in $path."
        }
        if ($route[$i].confidence -ne 'proven') { throw "Unproven route row in $path." }
    }
}

$hashes = @($overridePaths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } | Select-Object -Unique)
if ($hashes.Count -ne 1) { throw 'Route override copies are not byte-identical.' }

$lua = Get-Content -LiteralPath $sourceLuaPath -Raw
if ($lua -notmatch "west_safe\s*=\s*route_id:startswith\('lathine-recorded-corridor-20260712-west-via-'\)") {
    throw 'Directional West classification does not include every recorded west-via route.'
}
if ($lua -notmatch 'nav_distance\(candidate\[candidate:len\(\)\], waypoint\) > 0\.05') {
    throw 'Live corridor construction still drops closely spaced raw walk samples.'
}

Write-Host 'La Theine forward survey West escape checks passed'

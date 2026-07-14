$ErrorActionPreference = 'Stop'

$sessionId = '20260712-143554-z102'
$routeId = 'lathine-recorded-ravine-escape-20260712'
$recordingPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\logs\ffxi-nav-route-recordings.tsv'
$sourceOverridesPath = 'C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv'
$sourceAddonOverridesPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$liveOverridesPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'

$overrideHeaders = @(
    'route_id', 'zone', 'destination_name', 'destination_x', 'destination_z', 'destination_y',
    'match_radius', 'min_x', 'max_x', 'min_z', 'max_z', 'sequence',
    'waypoint_x', 'waypoint_z', 'waypoint_y', 'source', 'confidence', 'note'
)

function Assert-Equal {
    param(
        $Actual,
        $Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected'; found '$Actual'."
    }
}

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Get-RouteRows {
    param([Parameter(Mandatory = $true)][string]$Path)

    return @(Import-Csv -LiteralPath $Path -Delimiter "`t" -Header $overrideHeaders |
        Where-Object { $_.route_id -eq $routeId } |
        Sort-Object { [int]$_.sequence })
}

$recorded = @(Import-Csv -LiteralPath $recordingPath -Delimiter "`t" |
    Where-Object { $_.session -eq $sessionId } |
    Sort-Object { [int]$_.seq })

Assert-Equal $recorded.Count 323 'Recorded session row count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'start').Count 1 'Recorded start count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'point').Count 321 'Recorded movement-point count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'stop').Count 1 'Recorded stop count mismatch.'
Assert-Equal $recorded[0].zone '102' 'Recorded zone mismatch.'
Assert-Equal $recorded[0].x '-339.820' 'Recorded start x mismatch.'
Assert-Equal $recorded[0].z '375.467' 'Recorded start z mismatch.'
Assert-Equal $recorded[0].y '7.988' 'Recorded start y mismatch.'
Assert-Equal $recorded[-1].x '-563.557' 'Recorded stop x mismatch.'
Assert-Equal $recorded[-1].z '663.512' 'Recorded stop z mismatch.'
Assert-Equal $recorded[-1].y '0.823' 'Recorded stop y mismatch.'

$sourceRows = Get-RouteRows -Path $sourceOverridesPath
if ($sourceRows.Count -eq 0) {
    throw "Missing route override '$routeId'."
}
Assert-Equal $sourceRows.Count $recorded.Count 'Complete recorded coordinate sequence was not preserved.'

for ($i = 0; $i -lt $recorded.Count; $i++) {
    $expectedSequence = [string]($i + 1)
    Assert-Equal $sourceRows[$i].sequence $expectedSequence "Route sequence mismatch at row $expectedSequence."
    Assert-Equal $sourceRows[$i].waypoint_x $recorded[$i].x "Recorded x mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].waypoint_z $recorded[$i].z "Recorded z mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].waypoint_y $recorded[$i].y "Recorded y mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].zone '102' "Route zone mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].destination_name 'Recorded ravine escape handoff' "Route handoff name mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].destination_x '-563.557' "Route handoff x mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].destination_z '663.512' "Route handoff z mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].destination_y '0.823' "Route handoff y mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].min_x '-344.820' "Route minimum x mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].max_x '-334.820' "Route maximum x mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].min_z '370.467' "Route minimum z mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].max_z '380.467' "Route maximum z mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].source 'live-route-recording-20260712-143554-z102' "Route provenance mismatch at sequence $expectedSequence."
    Assert-Equal $sourceRows[$i].confidence 'proven' "Route confidence mismatch at sequence $expectedSequence."
}

$overrideHashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceOverridesPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceAddonOverridesPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveOverridesPath).Hash
) | Select-Object -Unique
Assert-Equal $overrideHashes.Count 1 'Route-override data copies are not byte-identical.'

$luaHashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
Assert-Equal $luaHashes.Count 1 'Source and live Lua copies are not byte-identical.'

$lua = Get-Content -LiteralPath $sourceLuaPath -Raw
Assert-Match $lua 'function accessxi\.nav_lathine_recorded_ravine_escape_route\(player, point\)' 'Missing universal recorded-ravine escape builder.'
Assert-Match $lua 'nav_route_override_points\(handoff, point\)' 'Expected the escape handoff to try current destination-specific overrides.'
Assert-Match $lua 'nav_compute_mesh_route\(handoff, point\)' 'Expected the escape handoff to use current navmesh data when no override matches.'
Assert-Match $lua 'nav_zoneline_approach_candidates\(point\)' 'Expected the escape handoff to use current zone-line approach data.'
Assert-Match $lua 'nav_route_quarantine_reason\(points, point\)' 'Expected the combined route to retain quarantine checks.'
Assert-Match $lua 'local recorded_ravine_escape = accessxi\.nav_lathine_recorded_ravine_escape_route\(player, point\)' 'Expected normal route planning to try the recorded escape prefix first.'
Assert-Match $lua 'recorded_ravine_escape:len\(\) > 1[\s\S]*?return recorded_ravine_escape, nil;[\s\S]*?nav_lathine_recorded_ravine_escape_required\(player, point\)[\s\S]*?return T\{\}, nil;' 'Expected a failed required escape to stop normal route fallback.'
Assert-Match $lua 'function accessxi\.nav_route_direct_fallback_block_reason\(player, point\)[\s\S]*?nav_lathine_recorded_ravine_escape_required\(player, point\)' 'Expected failed recorded escapes to block direct guidance for every destination.'
Assert-Match $lua "route_id:startswith\('lathine-recorded-ravine-escape-'\)" 'Expected every complete recorded escape to stay in precise-route mode.'
Assert-Match $lua 'point_x >= min_x and point_x <= max_x[\s\S]*?point_z >= min_z and point_z <= max_z[\s\S]*?return points' 'Expected only destinations inside the start pocket to bypass the universal escape.'

Write-Host 'nav La Theine recorded ravine escape checks passed'

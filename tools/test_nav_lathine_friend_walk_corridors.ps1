$ErrorActionPreference = 'Stop'

$sessionId = '20260712-170700-z102'
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

$corridors = @(
    [pscustomobject]@{ Id = 'lathine-recorded-corridor-20260712-01'; Start = 2220; End = 2267 },
    [pscustomobject]@{ Id = 'lathine-recorded-corridor-20260712-02'; Start = 3052; End = 3114 },
    [pscustomobject]@{ Id = 'lathine-recorded-corridor-20260712-03'; Start = 3810; End = 3846 },
    [pscustomobject]@{ Id = 'lathine-recorded-corridor-20260712-04'; Start = 4411; End = 4462 },
    [pscustomobject]@{ Id = 'lathine-recorded-corridor-20260712-05'; Start = 4584; End = 4623 },
    [pscustomobject]@{ Id = 'lathine-recorded-corridor-20260712-06'; Start = 5421; End = 5466 },
    [pscustomobject]@{ Id = 'lathine-recorded-corridor-20260712-07'; Start = 6446; End = 6498 }
)

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory = $true)][string]$Message)
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

$recorded = @(Import-Csv -LiteralPath $recordingPath -Delimiter "`t" |
    Where-Object { $_.session -eq $sessionId } |
    Sort-Object { [int]$_.seq })

Assert-Equal $recorded.Count 6499 'Friend-guided recording row count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'start').Count 1 'Friend-guided recording start count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'point').Count 6469 'Friend-guided movement-point count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'mark').Count 28 'Friend-guided mark count mismatch.'
Assert-Equal @($recorded | Where-Object event -eq 'stop').Count 1 'Friend-guided recording stop count mismatch.'
Assert-Equal @($recorded.zone | Select-Object -Unique).Count 1 'Friend-guided recording must not contain a zone discontinuity.'
Assert-Equal $recorded[0].zone '102' 'Friend-guided recording zone mismatch.'

$maxHorizontalStep = 0.0
$maxThreeDimensionalStep = 0.0
for ($i = 1; $i -lt $recorded.Count; $i++) {
    $dx = [double]$recorded[$i].x - [double]$recorded[$i - 1].x
    $dz = [double]$recorded[$i].z - [double]$recorded[$i - 1].z
    $dy = [double]$recorded[$i].y - [double]$recorded[$i - 1].y
    $horizontal = [Math]::Sqrt(($dx * $dx) + ($dz * $dz))
    $threeDimensional = [Math]::Sqrt(($horizontal * $horizontal) + ($dy * $dy))
    $maxHorizontalStep = [Math]::Max($maxHorizontalStep, $horizontal)
    $maxThreeDimensionalStep = [Math]::Max($maxThreeDimensionalStep, $threeDimensional)
}
if ($maxHorizontalStep -gt 4.0) {
    throw "Friend-guided recording has an unsafe horizontal discontinuity: $maxHorizontalStep."
}
if ($maxThreeDimensionalStep -gt 6.0) {
    throw "Friend-guided recording has an unsafe 3D discontinuity: $maxThreeDimensionalStep."
}

$overrideFiles = @($sourceOverridesPath, $sourceAddonOverridesPath, $liveOverridesPath)
foreach ($corridor in $corridors) {
    $segment = @($recorded | Where-Object {
        [int]$_.seq -ge $corridor.Start -and [int]$_.seq -le $corridor.End
    })
    $expectedCount = $corridor.End - $corridor.Start + 1
    Assert-Equal $segment.Count $expectedCount "Recorded segment count mismatch for $($corridor.Id)."

    foreach ($path in $overrideFiles) {
        $rows = @(Import-Csv -LiteralPath $path -Delimiter "`t" -Header $overrideHeaders |
            Where-Object { $_.route_id -eq $corridor.Id } |
            Sort-Object { [int]$_.sequence })
        Assert-Equal $rows.Count $segment.Count "Complete corridor was not preserved in $path for $($corridor.Id)."

        for ($i = 0; $i -lt $segment.Count; $i++) {
            Assert-Equal $rows[$i].sequence ([string]($i + 1)) "Route sequence mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].waypoint_x $segment[$i].x "Recorded x mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].waypoint_z $segment[$i].z "Recorded z mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].waypoint_y $segment[$i].y "Recorded y mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].zone '102' "Route zone mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].destination_name 'Recorded La Theine corridor handoff' "Route handoff name mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].destination_x $segment[-1].x "Route handoff x mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].destination_z $segment[-1].z "Route handoff z mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].destination_y $segment[-1].y "Route handoff y mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].source 'live-route-recording-20260712-170700-z102' "Route provenance mismatch for $($corridor.Id)."
            Assert-Equal $rows[$i].confidence 'proven' "Route confidence mismatch for $($corridor.Id)."
        }
    }
}

$expectedCorridorRows = ($corridors | ForEach-Object { $_.End - $_.Start + 1 } | Measure-Object -Sum).Sum
Assert-Equal $expectedCorridorRows 339 'Expected seven complete recorded corridors totaling 339 samples.'

$overrideHashes = @($overrideFiles | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash }) |
    Select-Object -Unique
Assert-Equal $overrideHashes.Count 1 'Route-override data copies are not byte-identical.'

$luaHashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
Assert-Equal $luaHashes.Count 1 'Source and live Lua copies are not byte-identical.'

$lua = Get-Content -LiteralPath $sourceLuaPath -Raw
Assert-Match $lua 'function accessxi\.nav_lathine_recorded_corridor_nearest\(pos, corridor\)' 'Missing 3D recorded-corridor proximity selector.'
Assert-Match $lua 'player_horizontal_limit\s*=\s*6\.0[\s\S]*player_vertical_limit\s*=\s*4\.5[\s\S]*horizontal_distance <= player_horizontal_limit[\s\S]*vertical_distance <= player_vertical_limit' 'Recorded corridors must retain tight 6.0 horizontal and 4.5 vertical proximity.'
Assert-Match $lua 'function accessxi\.nav_lathine_recorded_corridor_route\(player, point\)' 'Missing bidirectional recorded-corridor route builder.'
Assert-Match $lua 'for i = player_index, 1, -1 do[\s\S]*for i = player_index, corridor\.waypoints:len\(\) do' 'Recorded corridor must be evaluated in both walked directions.'
Assert-Match $lua 'nav_compute_mesh_route\(handoff, point\)' 'Recorded corridor endpoints must hand off to current nav data.'
Assert-Match $lua 'nav_route_quarantine_reason\(candidate, point\)' 'Recorded corridor tails must retain quarantine checks.'
Assert-Match $lua "route_id:startswith\('lathine-recorded-corridor-'\)" 'Recorded corridors must stay in precise-route mode.'
Assert-Match $lua 'local recorded_corridor, corridor_required = accessxi\.nav_lathine_recorded_corridor_route\(player, point\)[\s\S]*recorded_corridor:len\(\) > 1[\s\S]*return recorded_corridor, nil;[\s\S]*if \(corridor_required\)[\s\S]*return T\{\}, nil;' 'Route planning must prefer a matching walked corridor and block an unsafe fallback when its tail fails.'
Assert-Match $lua 'function accessxi\.nav_route_direct_fallback_block_reason\(player, point\)[\s\S]*nav_lathine_recorded_corridor_required\(player, point\)' 'Direct guidance must remain blocked when a required walked corridor has no safe tail.'

Write-Host 'La Theine friend-walk corridor checks passed'

param(
    [string]$Addon = 'C:\Users\buu42\Ashita\addons\accessxi_reader'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$probe = Join-Path $root 'tools\navprobe\navprobe.exe'
$dll = Join-Path $root 'third_party\FFXI-NavMesh-Builder\FFXINAV.dll'
$meshRoot = Join-Path $root 'third_party\xiNavmeshes'
$topology = Join-Path $root 'data\ffxi-nav-promyvion-transitions.tsv'
$zoneGraph = Join-Path $root 'data\ffxi-nav-zoneline-graph.tsv'
$survey = Join-Path $Addon 'data\ffxi-nav-recorded-survey.tsv'

foreach ($path in @($probe, $dll, $topology, $zoneGraph, $survey)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "required Promyvion test input is missing: $path"
    }
}

$meshNames = @{
    16 = 'Promyvion-Holla.nav'
    18 = 'Promyvion-Dem.nav'
    20 = 'Promyvion-Mea.nav'
    22 = 'Promyvion-Vahzl.nav'
}
# Windows PowerShell 5.1 treats the leading provenance comments as the CSV
# header; PowerShell 7 skips them. Strip them explicitly so the release check
# measures the same 87/842 records under both shells.
$rows = Get-Content -LiteralPath $topology |
    Where-Object { $_ -notmatch '^#' -and $_ -match '\S' } |
    ConvertFrom-Csv -Delimiter "`t"
$roads = Get-Content -LiteralPath $zoneGraph |
    Where-Object { $_ -notmatch '^#' -and $_ -match '\S' } |
    ConvertFrom-Csv -Delimiter "`t"
$islands = @{}
foreach ($row in $rows) {
    if ($row.kind -eq 'island') {
        $islands["$($row.zone):$($row.island_id)"] = $row
    }
}

$checks = [System.Collections.Generic.List[object]]::new()
function Test-Route {
    param($Zone, $Record, $Start, $TargetX, $TargetZ, $TargetY)

    $mesh = Join-Path $meshRoot $meshNames[[int]$Zone]
    if (-not (Test-Path -LiteralPath $mesh -PathType Leaf)) {
        throw "Promyvion mesh is missing: $mesh"
    }
    $output = & $probe $dll $mesh $survey repair `
        $Start.anchor_x $Start.anchor_z $Start.anchor_y `
        $TargetX $TargetZ $TargetY
    if ($LASTEXITCODE -ne 0) {
        throw "navprobe failed for $Record with exit $LASTEXITCODE"
    }
    $text = $output -join "`n"
    $before = if ($text -match 'BEFORE\s+waypoints=(\d+)') { [int]$Matches[1] } else { -1 }
    $blind = if ($text -match 'remaining blind=(\d+)') { [int]$Matches[1] } else { -1 }
    $longLegs = if ($text -match 'AFTER\s+waypoints=\d+.*legs>6\.0y=(\d+)') {
        [int]$Matches[1]
    } else { -1 }
    $milliseconds = if ($text -match 'repair cost: ([0-9.]+) ms') { [double]$Matches[1] } else { -1 }
    $last = $output | Where-Object { $_ -match '^\d+\t' } | Select-Object -Last 1
    $snap = [double]::PositiveInfinity
    if ($null -ne $last) {
        $field = $last -split "`t"
        $dx = [double]$field[1] - [double]$TargetX
        $dz = [double]$field[2] - [double]$TargetZ
        $dy = [double]$field[3] - [double]$TargetY
        $snap = [Math]::Sqrt(($dx * $dx) + ($dz * $dz) + ($dy * $dy))
    }
    $checks.Add([pscustomobject]@{
        zone = [int]$Zone
        record = [string]$Record
        raw_waypoints = $before
        remaining_blind = $blind
        legs_over_six = $longLegs
        endpoint_snap = [Math]::Round($snap, 2)
        repair_ms = $milliseconds
        passed = $before -gt 1 -and $blind -eq 0 -and $longLegs -eq 0 -and $snap -le 2.0
    })
}

# Every reviewed same-zone transport must be reachable from its own island.
# This is the native FFXINAV path plus the addon's repair algorithm, not a
# synthetic graph claim. A disconnected result, a remaining blind leg, a leg
# longer than the runtime's 6.25-yalm cap, or an endpoint more than two yalms
# away fails the release check.  navprobe's six-yalm repair cap is deliberately
# stricter than the addon's acceptance limit.
foreach ($row in $rows | Where-Object { $_.kind -in @('forward', 'return') }) {
    $start = $islands["$($row.zone):$($row.island_id)"]
    if ($null -eq $start) { throw "missing island anchor for $($row.record_id)" }
    Test-Route $row.zone $row.record_id $start $row.anchor_x $row.anchor_z $row.anchor_y
}

# The last island must also reach the actual Spire zone line. Exit rows in the
# topology are floor-one returns to the Hall of Transference; they are not the
# mission's final Spire approach and cannot stand in for this check.
foreach ($zoneId in 16, 18, 20, 22) {
    $forward = @{}
    foreach ($row in $rows | Where-Object { [int]$_.zone -eq $zoneId -and $_.kind -eq 'forward' }) {
        $forward[$row.island_id] = $true
    }
    $terminal = $rows | Where-Object {
        [int]$_.zone -eq $zoneId -and $_.kind -eq 'island' -and -not $forward.ContainsKey($_.island_id)
    } | Select-Object -First 1
    $spire = $roads | Where-Object {
        [int]$_.from_zone -eq $zoneId -and $_.to_name -like 'Spire of *'
    } | Select-Object -First 1
    if ($null -eq $terminal -or $null -eq $spire) {
        throw "terminal island or Spire road is missing for zone $zoneId"
    }
    Test-Route $zoneId "${zoneId}:spire" $terminal $spire.from_x $spire.from_z $spire.from_y
}

$bad = @($checks | Where-Object { -not $_.passed })
$checks | Group-Object zone | ForEach-Object {
    [pscustomobject]@{
        zone = $_.Name
        routes = $_.Count
        max_repair_ms = ($_.Group.repair_ms | Measure-Object -Maximum).Maximum
        max_endpoint_snap = ($_.Group.endpoint_snap | Measure-Object -Maximum).Maximum
        failed = @($_.Group | Where-Object { -not $_.passed }).Count
    }
} | Format-Table -AutoSize

if ($bad.Count -gt 0) {
    $bad | Format-Table -AutoSize
    Write-Host "Promyvion navmesh routes: $($checks.Count - $bad.Count) passed, $($bad.Count) failed"
    exit 1
}
Write-Host "Promyvion navmesh routes: $($checks.Count) passed, 0 failed"
exit 0

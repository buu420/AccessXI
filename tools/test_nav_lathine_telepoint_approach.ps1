$ErrorActionPreference = 'Stop'

$paths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
)

$routeOverridePaths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-route-overrides.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-route-overrides.tsv'
)

$luaPaths = @(
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
)

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-NavRows {
    param(
        [string]$Path,
        [string]$Name
    )

    Assert-True (Test-Path -LiteralPath $Path) "Missing nav destinations file: $Path"
    $rows = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $fields = $line -split "`t"
        if ($fields.Count -lt 8) {
            continue
        }

        if ($fields[0] -eq '102' -and $fields[1] -eq $Name) {
            $rows += [pscustomobject]@{
                Zone = [int]$fields[0]
                Name = $fields[1]
                X = [double]$fields[2]
                Z = [double]$fields[3]
                Y = [double]$fields[4]
                Kind = $fields[5]
                Source = $fields[6]
                Confidence = $fields[7]
                Path = $Path
            }
        }
    }

    return $rows
}

function Get-RouteRows {
    param(
        [string]$Path,
        [string]$RouteId
    )

    Assert-True (Test-Path -LiteralPath $Path) "Missing nav route overrides file: $Path"
    $rows = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
            continue
        }

        $fields = $line -split "`t"
        if ($fields.Count -lt 18) {
            continue
        }

        if ($fields[0] -eq $RouteId) {
            $rows += [pscustomobject]@{
                RouteId = $fields[0]
                Zone = [int]$fields[1]
                DestinationName = $fields[2]
                DestinationX = [double]$fields[3]
                DestinationZ = [double]$fields[4]
                DestinationY = [double]$fields[5]
                MatchRadius = [double]$fields[6]
                MinX = [double]$fields[7]
                MaxX = [double]$fields[8]
                MinZ = [double]$fields[9]
                MaxZ = [double]$fields[10]
                Sequence = [int]$fields[11]
                WaypointX = [double]$fields[12]
                WaypointZ = [double]$fields[13]
                WaypointY = [double]$fields[14]
                Source = $fields[15]
                Confidence = $fields[16]
                Note = $fields[17]
                Path = $Path
            }
        }
    }

    return @($rows | Sort-Object Sequence)
}

foreach ($path in $paths) {
    $telepointRows = @(Get-NavRows -Path $path -Name 'Telepoint')
    Assert-True ($telepointRows.Count -eq 1) "Expected one La Theine Telepoint row in $path; found $($telepointRows.Count)."
    $telepoint = $telepointRows[0]
    Assert-True ([math]::Abs($telepoint.X - 420.0) -le 0.1 -and [math]::Abs($telepoint.Z - 20.2) -le 0.1 -and [math]::Abs($telepoint.Y - 19.1) -le 0.1) "La Theine Telepoint should route to the live-recorded Holla gate crystal interaction point: x=$($telepoint.X) z=$($telepoint.Z) y=$($telepoint.Y) in $path."
    Assert-True ($telepoint.Source -match 'live-axi-pos-lathine-holla-gate-crystal-20260629') "La Theine Telepoint source should record the live gate crystal /axi pos evidence in $path."
    Assert-True ($telepoint.Confidence -eq 'observed') "La Theine Telepoint correction should be marked observed until live-tested: $($telepoint.Confidence) in $path."

    $shatteredRows = @(Get-NavRows -Path $path -Name 'Shattered Telepoint')
    Assert-True ($shatteredRows.Count -eq 1) "Expected one La Theine Shattered Telepoint row in $path; found $($shatteredRows.Count)."
    $shattered = $shatteredRows[0]
    Assert-True ($shattered.Y -ge 23.5 -and $shattered.Y -le 24.8) "La Theine Shattered Telepoint should use the walkable floor height near y=24, not the lower object center: $($shattered.Y) in $path."
    Assert-True ($shattered.Source -match 'live-screenshot-lathine-telepoint-20260628') "La Theine Shattered Telepoint source should record the live screenshot/evidence correction in $path."
    Assert-True ($shattered.Confidence -eq 'observed') "La Theine Shattered Telepoint correction should be marked observed until live-tested: $($shattered.Confidence) in $path."
}

foreach ($path in $routeOverridePaths) {
    $rows = @(Get-RouteRows -Path $path -RouteId 'lathine-crag-to-telepoint')
    Assert-True ($rows.Count -eq 5) "Expected five live-recorded descent waypoints for La Theine Telepoint in $path; found $($rows.Count)."

    foreach ($row in $rows) {
        Assert-True ($row.Zone -eq 102) "La Theine Telepoint route override should be zone 102 in $path."
        Assert-True ($row.DestinationName -eq 'Telepoint') "La Theine Telepoint route override should target Telepoint in $path."
        Assert-True ([math]::Abs($row.DestinationX - 420.0) -lt 0.001 -and [math]::Abs($row.DestinationZ - 20.2) -lt 0.001 -and [math]::Abs($row.DestinationY - 19.1) -lt 0.001) "La Theine Telepoint override destination should be the live-recorded Holla gate crystal point in $path."
        Assert-True ($row.MatchRadius -eq 4.0) "La Theine Telepoint override should match only the observed Telepoint row in $path."
        Assert-True ($row.MinX -eq 400.0 -and $row.MaxX -eq 465.0 -and $row.MinZ -eq 10.0 -and $row.MaxZ -eq 55.0) "La Theine Telepoint override should only apply near the Holla crag and stair approach in $path."
        Assert-True ($row.Source -eq 'live-axi-pos-lathine-holla-stairs-20260629') "La Theine Telepoint override should record the live stair /axi pos evidence in $path."
        Assert-True ($row.Confidence -eq 'observed') "La Theine Telepoint override should remain observed until live-tested in $path."
        Assert-True ($row.WaypointX -ge 418.8 -and $row.WaypointX -le 420.2) "La Theine Telepoint override should follow the live x=419 descent path instead of crossing the upper platform: x=$($row.WaypointX) in $path."
    }

    Assert-True ([math]::Abs($rows[0].WaypointX - 419.6) -le 0.1 -and [math]::Abs($rows[0].WaypointZ - 41.2) -le 0.1 -and [math]::Abs($rows[0].WaypointY - 25.0) -le 0.1) "First La Theine Telepoint waypoint should be the live-recorded stair entry at X 419.6 Z 41.2 Y 25.0 in $path."
    Assert-True ([math]::Abs($rows[1].WaypointX - 419.511) -le 0.1 -and [math]::Abs($rows[1].WaypointZ - 37.443) -le 0.1 -and [math]::Abs($rows[1].WaypointY - 23.354) -le 0.1) "Second La Theine Telepoint waypoint should start the confirmed stair descent at X 419.511 Z 37.443 Y 23.354 in $path."
    Assert-True ([math]::Abs($rows[2].WaypointX - 419.296) -le 0.1 -and [math]::Abs($rows[2].WaypointZ - 29.197) -le 0.1 -and [math]::Abs($rows[2].WaypointY - 19.604) -le 0.1) "Third La Theine Telepoint waypoint should stay on the lower descent corridor at X 419.296 Z 29.197 Y 19.604 in $path."
    Assert-True ([math]::Abs($rows[3].WaypointX - 419.272) -le 0.1 -and [math]::Abs($rows[3].WaypointZ - 27.468) -le 0.1 -and [math]::Abs($rows[3].WaypointY - 19.477) -le 0.1) "Fourth La Theine Telepoint waypoint should keep the short lower approach at X 419.272 Z 27.468 Y 19.477 in $path."
    Assert-True ([math]::Abs($rows[-1].WaypointX - 420.0) -le 0.1 -and [math]::Abs($rows[-1].WaypointZ - 20.2) -le 0.1 -and [math]::Abs($rows[-1].WaypointY - 19.1) -le 0.1) "Final La Theine Telepoint approach should stop at the live-recorded Holla gate crystal point in $path."
}

foreach ($path in $luaPaths) {
    Assert-True (Test-Path -LiteralPath $path) "Missing addon Lua file: $path"
    $source = Get-Content -LiteralPath $path -Raw
    Assert-True ($source -match "name\s*==\s*'telepoint'[\s\S]*?tonumber\(destination\.zone\)[\s\S]*?==\s*102[\s\S]*?return\s+3") "La Theine Telepoint should use a tighter arrival radius so nav does not stop under the crag in $path."
    Assert-True ($source -match "function accessxi\.nav_route_override_requires_full_start\(points\)[\s\S]*?lathine-crag-to-telepoint[\s\S]*?function accessxi\.nav_route_override_start_index") "La Theine Telepoint stair override should force the route to start at the stair entry instead of skipping ahead by flat X/Z proximity in $path."
}

Write-Host 'La Theine telepoint approach checks ok'

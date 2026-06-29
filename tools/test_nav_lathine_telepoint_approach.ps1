$ErrorActionPreference = 'Stop'

$paths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
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

foreach ($path in $paths) {
    $telepointRows = @(Get-NavRows -Path $path -Name 'Telepoint')
    Assert-True ($telepointRows.Count -eq 1) "Expected one La Theine Telepoint row in $path; found $($telepointRows.Count)."
    $telepoint = $telepointRows[0]
    Assert-True ($telepoint.Y -ge 23.5 -and $telepoint.Y -le 24.8) "La Theine Telepoint should use the walkable floor height near y=24, not the lower object center: $($telepoint.Y) in $path."
    Assert-True ($telepoint.X -ge 414.0 -and $telepoint.X -le 418.5 -and $telepoint.Z -ge 24.0 -and $telepoint.Z -le 28.0) "La Theine Telepoint should route to the observed reachable edge, not the column center: x=$($telepoint.X) z=$($telepoint.Z) in $path."
    Assert-True ($telepoint.Source -match 'live-screenshot-lathine-telepoint-20260628') "La Theine Telepoint source should record the live screenshot/evidence correction in $path."
    Assert-True ($telepoint.Confidence -eq 'observed') "La Theine Telepoint correction should be marked observed until live-tested: $($telepoint.Confidence) in $path."

    $shatteredRows = @(Get-NavRows -Path $path -Name 'Shattered Telepoint')
    Assert-True ($shatteredRows.Count -eq 1) "Expected one La Theine Shattered Telepoint row in $path; found $($shatteredRows.Count)."
    $shattered = $shatteredRows[0]
    Assert-True ($shattered.Y -ge 23.5 -and $shattered.Y -le 24.8) "La Theine Shattered Telepoint should use the walkable floor height near y=24, not the lower object center: $($shattered.Y) in $path."
    Assert-True ($shattered.Source -match 'live-screenshot-lathine-telepoint-20260628') "La Theine Shattered Telepoint source should record the live screenshot/evidence correction in $path."
    Assert-True ($shattered.Confidence -eq 'observed') "La Theine Shattered Telepoint correction should be marked observed until live-tested: $($shattered.Confidence) in $path."
}

Write-Host 'La Theine telepoint approach checks ok'

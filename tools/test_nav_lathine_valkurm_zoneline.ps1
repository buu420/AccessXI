$ErrorActionPreference = 'Stop'

$destinationPaths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
)

$graphPaths = @(
    'C:\Users\buu42\AccessXI\data\ffxi-nav-zoneline-graph.tsv',
    'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv',
    'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv'
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

$expectedX = 159.989
$expectedZ = -760.190
$expectedY = 31.950
$expectedSource = 'live-axi-pos-lathine-valkurm-20260713'

foreach ($path in $destinationPaths) {
    $rows = @(Get-Content -LiteralPath $path | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or $_.StartsWith('#')) {
            return
        }
        $fields = $_ -split "`t"
        if ($fields.Count -ge 8 -and $fields[0] -eq '102' -and $fields[1] -eq 'Valkurm Dunes zone line') {
            [pscustomobject]@{
                x = $fields[2]
                z = $fields[3]
                y = $fields[4]
                source = $fields[6]
                confidence = $fields[7]
            }
        }
    })
    Assert-True ($rows.Count -eq 1) "Expected one La Theine-side Valkurm Dunes zone line in $path; found $($rows.Count)."
    $row = $rows[0]
    Assert-True ([math]::Abs(([double]$row.x) - $expectedX) -lt 0.001) "Valkurm zone line X should use the live /axi pos in $path."
    Assert-True ([math]::Abs(([double]$row.z) - $expectedZ) -lt 0.001) "Valkurm zone line Z should use the live trigger boundary instead of the unreachable point beyond it in $path."
    Assert-True ([math]::Abs(([double]$row.y) - $expectedY) -lt 0.001) "Valkurm zone line Y should use the live walkable floor height in $path."
    Assert-True ($row.source -eq $expectedSource) "Valkurm zone line should retain the live /axi pos provenance in $path."
    Assert-True ($row.confidence -eq 'observed') "Valkurm zone line should remain observed until the corrected route is tested in $path."
}

foreach ($path in $graphPaths) {
    $rows = @(Import-Csv -Delimiter "`t" -LiteralPath $path | Where-Object {
        ($_.from_zone -eq '102' -and $_.to_zone -eq '103') -or
        ($_.from_zone -eq '103' -and $_.to_zone -eq '102')
    })
    Assert-True ($rows.Count -eq 2) "Expected both La Theine/Valkurm graph directions in $path; found $($rows.Count)."

    foreach ($row in $rows) {
        if ($row.from_zone -eq '102') {
            $x = [double]$row.from_x
            $z = [double]$row.from_z
            $y = [double]$row.from_y
        } else {
            $x = [double]$row.to_x
            $z = [double]$row.to_z
            $y = [double]$row.to_y
        }

        Assert-True ([math]::Abs($x - $expectedX) -lt 0.001 -and [math]::Abs($z - $expectedZ) -lt 0.001 -and [math]::Abs($y - $expectedY) -lt 0.001) "Both graph directions should use the same live-observed La Theine boundary in $path."
        Assert-True ($row.source -eq $expectedSource) "Both graph directions should retain the live /axi pos provenance in $path."
        Assert-True ($row.confidence -eq 'observed') "Both graph directions should remain observed until live-tested in $path."
    }
}

$destinationHashes = $destinationPaths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash }
Assert-True (($destinationHashes | Sort-Object -Unique).Count -eq 1) 'Destination data copies are not synchronized.'

$graphHashes = $graphPaths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash }
Assert-True (($graphHashes | Sort-Object -Unique).Count -eq 1) 'Zoneline graph copies are not synchronized.'

Write-Host 'La Theine/Valkurm live zoneline checks ok'

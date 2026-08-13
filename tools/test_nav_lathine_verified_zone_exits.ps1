param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$LiveAddonRoot = ''
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $Root).Path
$destinationPaths = @(
    "$root\data\ffxi-nav-destinations.tsv",
    "$root\ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv"
)
$graphPaths = @(
    "$root\data\ffxi-nav-zoneline-graph.tsv",
    "$root\ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv"
)
$markPaths = @(
    "$root\data\ffxi-nav-recorded-marks.tsv",
    "$root\ashita\addons\accessxi_reader\data\ffxi-nav-recorded-marks.tsv"
)
$surveyPaths = @(
    "$root\data\ffxi-nav-recorded-survey.tsv",
    "$root\ashita\addons\accessxi_reader\data\ffxi-nav-recorded-survey.tsv"
)
if (-not [string]::IsNullOrWhiteSpace($LiveAddonRoot)) {
    $destinationPaths += Join-Path $LiveAddonRoot 'data\ffxi-nav-destinations.tsv'
    $graphPaths += Join-Path $LiveAddonRoot 'data\ffxi-nav-zoneline-graph.tsv'
    $markPaths += Join-Path $LiveAddonRoot 'data\ffxi-nav-recorded-marks.tsv'
    $surveyPaths += Join-Path $LiveAddonRoot 'data\ffxi-nav-recorded-survey.tsv'
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Read-Destinations {
    param([string]$Path)
    return @(Get-Content -LiteralPath $Path | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_) -or $_.StartsWith('#')) {
            return
        }
        $fields = $_ -split "`t"
        if ($fields.Count -ge 7) {
            [pscustomobject]@{
                zone = $fields[0]
                name = $fields[1]
                x = $fields[2]
                z = $fields[3]
                y = $fields[4]
                kind = $fields[5]
                source = $fields[6]
                confidence = if ($fields.Count -ge 8) { $fields[7] } else { '' }
                section = if ($fields.Count -ge 9) { $fields[8] } else { '' }
                destination_id = if ($fields.Count -ge 10) { $fields[9] } else { '' }
                raw_identity = if ($fields.Count -ge 11) { $fields[10] } else { '' }
                field_count = $fields.Count
            }
        }
    })
}

$expectedDestinationNames = @(
    'Jugner Forest zone line',
    "Ordelle's Caves zone line z2u6",
    "Ordelle's Caves zone line z2u8",
    'Valkurm Dunes zone line',
    'West Ronfaure zone line'
)
$expectedGraphKeys = @(
    '100:z2u0:West Ronfaure',
    '103:z2u4:Valkurm Dunes',
    '104:z2u2:Jugner Forest',
    "193:z2u6:Ordelle's Caves",
    "193:z2u8:Ordelle's Caves"
)
$proofSource = 'live-mark-aligned-navmesh-20260713'
$proofNote = 'user-confirmed-ordelle-line-2026-07-13'
$expectedActiveEdgeIds = @(846541434, 880095866, 812987002, 913650298, 947204730)
$forbiddenEdgeIds = @(878982522, 1635070586)

function Get-PresentationRank {
    param($Row)
    switch ([string]$Row.confidence) {
        'proven' { return 0 }
        'observed' { return 1 }
        'bad' { return 9 }
        default { return 4 }
    }
}

foreach ($path in $destinationPaths) {
    $areas = @(Read-Destinations -Path $path | Where-Object { $_.zone -eq '102' -and $_.kind -eq 'area' })

    foreach ($edgeId in $expectedActiveEdgeIds) {
        $identity = "area:v1:102:$edgeId"
        $matches = @($areas | Where-Object { $_.destination_id -eq $identity })
        Assert-True ($matches.Count -eq 1) "Expected exactly one immutable La Theine identity $identity in $path; found $($matches.Count)."
        Assert-True ($matches[0].field_count -eq 13) "La Theine identity $identity is not a 13-column row in $path."
        Assert-True ($matches[0].raw_identity -eq "lsb:zonelines:$edgeId") "La Theine identity $identity lost its exact raw zoneline identity in $path."
    }
    foreach ($edgeId in $forbiddenEdgeIds) {
        Assert-True (@($areas | Where-Object { $_.raw_identity -eq "lsb:zonelines:$edgeId" }).Count -eq 0) "Unverified z2ua identity $edgeId remains in $path."
    }

    $presentationGroups = @($areas | Group-Object -Property {
        $normalizedName = ([string]$_.name).ToLowerInvariant() -replace '\s+', ' '
        "$($_.zone)|$(([string]$_.kind).ToLowerInvariant())|$($normalizedName.Trim())"
    })
    $presented = @($presentationGroups | ForEach-Object {
        @($_.Group | Sort-Object `
            @{ Expression = { Get-PresentationRank $_ }; Ascending = $true }, `
            @{ Expression = { [string]$_.destination_id }; Ascending = $true }, `
            @{ Expression = { [string]$_.raw_identity }; Ascending = $true })[0]
    })
    Assert-True ($presented.Count -eq 5) "Expected five projected La Theine area exits in $path; found $($presented.Count) from $($areas.Count) raw rows."
    $actualNames = @($presented.name | Sort-Object)
    Assert-True (($actualNames -join "`n") -eq (($expectedDestinationNames | Sort-Object) -join "`n")) "La Theine visible exits do not match the verified five in $path."

    $ordelle = @($presented | Where-Object { $_.name -like "Ordelle's Caves zone line*" })
    Assert-True ($ordelle.Count -eq 2) "Expected exactly two Ordelle's Caves exits in $path; found $($ordelle.Count)."
    foreach ($row in $ordelle) {
        Assert-True ($row.source -eq $proofSource) "Ordelle exit $($row.name) lacks aligned live-mark provenance in $path."
        Assert-True ($row.confidence -eq 'proven') "Ordelle exit $($row.name) is not proven in $path."
        Assert-True ($row.section -eq $proofNote) "Ordelle exit $($row.name) lacks the confirmation note in $path."
    }
}

foreach ($path in $graphPaths) {
    $rows = @(Import-Csv -LiteralPath $path -Delimiter "`t")
    $external = @($rows | Where-Object { $_.from_zone -eq '102' -and $_.to_zone -ne '102' })
    Assert-True ($external.Count -eq 5) "Expected exactly five La Theine graph exits in $path; found $($external.Count)."
    $actualKeys = @($external | ForEach-Object { "$($_.to_zone):$($_.from_code):$($_.to_name)" } | Sort-Object)
    Assert-True (($actualKeys -join "`n") -eq (($expectedGraphKeys | Sort-Object) -join "`n")) "La Theine graph exits do not match the verified five in $path."

    $ordelle = @($external | Where-Object { $_.to_zone -eq '193' })
    foreach ($row in $ordelle) {
        Assert-True ($row.source -eq $proofSource) "Ordelle graph edge $($row.zoneline_id) lacks aligned live-mark provenance in $path."
        Assert-True ($row.confidence -eq 'proven') "Ordelle graph edge $($row.zoneline_id) is not proven in $path."
        Assert-True ($row.note -eq $proofNote) "Ordelle graph edge $($row.zoneline_id) lacks the confirmation note in $path."
    }

    Assert-True (@($rows | Where-Object { $_.zoneline_id -eq '1635070586' }).Count -eq 0) "Unverified La Theine z2ua edge remains in $path."
    Assert-True (@($rows | Where-Object { $_.zoneline_id -eq '878982522' }).Count -eq 0) "Reverse edge for the unverified z2ua transition remains in $path."
}

foreach ($path in $markPaths) {
    $rows = @(Get-Content -LiteralPath $path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#') })
    Assert-True ($rows.Count -eq 24) "Expected 24 non-area recorded landmark destinations in $path; found $($rows.Count)."
    foreach ($line in $rows) {
        $fields = $line -split "`t"
        Assert-True ($fields.Count -ge 6 -and $fields[5] -ne 'area') "Survey area anchor was incorrectly exported as a destination in ${path}: $line"
        Assert-True ($fields[1] -ne "Ordelle's Caves ravine approach") "The survey-only ravine approach remains a destination in $path."
    }
}

$preservedSurveyMarks = @(800, 845, 1288, 1969)
foreach ($path in $surveyPaths) {
    $rows = @(Import-Csv -LiteralPath $path -Delimiter "`t")
    Assert-True ($rows.Count -eq 6499) "Recorded survey node count changed in $path; found $($rows.Count)."
    foreach ($sequence in $preservedSurveyMarks) {
        $matches = @($rows | Where-Object { $_.sequence -eq [string]$sequence -and $_.event -eq 'mark' })
        Assert-True ($matches.Count -eq 1) "Survey mark sequence $sequence was not preserved exactly once in $path."
    }
}

$python = @'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("nav_zoneline_generator", path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

edges = module.apply_edge_policy(module.parse_zonelines(Path(sys.argv[2])))
by_id = {edge.zoneline_id: edge for edge in edges}
assert 1635070586 not in by_id
assert 878982522 not in by_id
for edge_id in (846541434, 880095866, 812987002, 913650298, 947204730):
    assert edge_id in by_id
for edge_id in (913650298, 947204730):
    destination = module.generated_destination(by_id[edge_id], "test")
    assert destination.source == "live-mark-aligned-navmesh-20260713"
    assert destination.confidence == "proven"
    assert destination.section == "user-confirmed-ordelle-line-2026-07-13"
print("generator policy ok")
'@
$pythonPath = Join-Path $root 'tools\.objective-guides-venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
    $pythonPath = 'py'
}
$generatorPath = Join-Path $root 'tools\generate_nav_zoneline_destinations.py'
$zonelinesPath = Join-Path $root 'data\lsb_zonelines.sql'
if ($pythonPath -eq 'py') {
    $generatorResult = $python | & $pythonPath -3 - $generatorPath $zonelinesPath
}
else {
    $generatorResult = $python | & $pythonPath - $generatorPath $zonelinesPath
}
Assert-True ($LASTEXITCODE -eq 0) "Zoneline generator policy check failed: $generatorResult"

foreach ($paths in @($destinationPaths, $graphPaths, $markPaths, $surveyPaths)) {
    $hashes = @($paths | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_).Hash } | Sort-Object -Unique)
    Assert-True ($hashes.Count -eq 1) "Navigation data copies are not byte-identical: $($paths -join ', ')"
}

Write-Host 'La Theine verified zone exit checks ok'

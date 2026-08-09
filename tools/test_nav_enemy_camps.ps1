param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$LiveAddonRoot = ''
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $Root).Path
$generatorPath = Join-Path $root 'tools\generate_nav_zoneline_destinations.py'
$sourceDataPath = Join-Path $root 'data\ffxi-nav-destinations.tsv'
$addonDataPath = Join-Path $root 'ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
$dataPaths = @($sourceDataPath, $addonDataPath)
if (-not [string]::IsNullOrWhiteSpace($LiveAddonRoot)) {
    $dataPaths += Join-Path $LiveAddonRoot 'data\ffxi-nav-destinations.tsv'
}

$generator = Get-Content -LiteralPath $generatorPath -Raw
$sourceData = Get-Content -LiteralPath $sourceDataPath -Raw
$addonData = Get-Content -LiteralPath $addonDataPath -Raw

function Assert-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [string]$Actual,
        [string]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw $Message
    }
}

Assert-Match `
    -Text $generator `
    -Pattern 'GENERATED_ENEMY_SOURCE\s*=\s*"lsb-mob-spawn-camps"' `
    -Message 'Generated enemy camp rows should have a dedicated source marker.'

Assert-Match `
    -Text $generator `
    -Pattern 'def parse_mob_spawn_points\(path: Path\) -> list\[MobSpawn\]' `
    -Message 'Generator should parse LSB mob spawn rows separately from NPC rows.'

$python = Join-Path $root 'tools\.objective-guides-venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    throw "Objective guide Python environment is missing: $python"
}

function Get-Sha256 {
    param([string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [System.BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '')
        }
        finally {
            $hasher.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

Push-Location -LiteralPath $root
try {
    & $python -m unittest `
        'tools.test_nav_destination_generator.NavDestinationGeneratorTests.test_complete_link_clustering_conserves_ids_splits_chains_and_floors' `
        'tools.test_nav_destination_generator.NavDestinationGeneratorTests.test_clustering_rejects_a_policy_version_without_matching_geometry'
    if ($LASTEXITCODE -ne 0) {
        throw 'Generator enemy-camp behavior tests failed.'
    }
}
finally {
    Pop-Location
}

Assert-Match `
    -Text $generator `
    -Pattern 'GENERATED_ENEMY_SOURCE' `
    -Message 'Generator should remove and refresh previously generated enemy camp rows.'

foreach ($path in $dataPaths) {
    $data = Get-Content -LiteralPath $path -Raw
    Assert-Match `
        -Text $data `
        -Pattern '(?m)^102\tHuge Wasp\t[-0-9.]+\t[-0-9.]+\t[-0-9.]+\tenemy\tlsb-mob-spawn-camps\tuntested\tworld-enemy-camps-2026-07-01' `
        -Message 'La Theine Huge Wasp should exist as a zone-wide enemy camp destination.'

    Assert-Match `
        -Text $data `
        -Pattern '(?m)^100\tForest Hare\t[-0-9.]+\t[-0-9.]+\t[-0-9.]+\tenemy\tlsb-mob-spawn-camps\tuntested\tworld-enemy-camps-2026-07-01' `
        -Message 'West Ronfaure Forest Hare should exist as a zone-wide enemy camp destination.'

    Assert-Match `
        -Text $data `
        -Pattern '(?m)^100\tOrcish Fodder\t[-0-9.]+\t[-0-9.]+\t[-0-9.]+\tenemy\tlsb-mob-spawn-camps\tuntested\tworld-enemy-camps-2026-07-01' `
        -Message 'West Ronfaure Orcish Fodder should exist as a zone-wide enemy camp destination.'
}

$sourceHash = Get-Sha256 -Path $sourceDataPath
$addonHash = Get-Sha256 -Path $addonDataPath
Assert-Equal -Actual $addonHash -Expected $sourceHash -Message 'Source addon nav destination data should match root nav destination data.'
if (-not [string]::IsNullOrWhiteSpace($LiveAddonRoot)) {
    $liveDataPath = Join-Path $LiveAddonRoot 'data\ffxi-nav-destinations.tsv'
    $liveHash = Get-Sha256 -Path $liveDataPath
    Assert-Equal -Actual $liveHash -Expected $sourceHash -Message 'Explicit live Ashita nav destination data should match root nav destination data.'
}

Write-Host 'nav enemy camp checks ok'

$ErrorActionPreference = 'Stop'

$root = 'C:\Users\buu42\AccessXI'
$generatorPath = Join-Path $root 'tools\generate_nav_zoneline_destinations.py'
$sourceDataPath = Join-Path $root 'data\ffxi-nav-destinations.tsv'
$addonDataPath = Join-Path $root 'ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
$liveDataPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'

$generator = Get-Content -LiteralPath $generatorPath -Raw
$sourceData = Get-Content -LiteralPath $sourceDataPath -Raw
$addonData = Get-Content -LiteralPath $addonDataPath -Raw
$liveData = Get-Content -LiteralPath $liveDataPath -Raw

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
    -Pattern 'MOB_SPAWN_POINTS\s*=\s*ROOT\s*/\s*"third_party"\s*/\s*"LandSandBoat-server"\s*/\s*"sql"\s*/\s*"mob_spawn_points\.sql"' `
    -Message 'Nav destination generator should read local LSB mob_spawn_points.sql.'

Assert-Match `
    -Text $generator `
    -Pattern 'GENERATED_ENEMY_SOURCE\s*=\s*"lsb-mob-spawn-camps"' `
    -Message 'Generated enemy camp rows should have a dedicated source marker.'

Assert-Match `
    -Text $generator `
    -Pattern 'def parse_mob_spawn_points\(path: Path\) -> list\[MobSpawn\]' `
    -Message 'Generator should parse LSB mob spawn rows separately from NPC rows.'

Assert-Match `
    -Text $generator `
    -Pattern 'def cluster_enemy_camps\(spawns: list\[MobSpawn\]\) -> list\[Destination\]' `
    -Message 'Generator should cluster raw spawn slots into usable camp destinations.'

Assert-Match `
    -Text $generator `
    -Pattern 'GENERATED_ENEMY_SOURCE' `
    -Message 'Generator should remove and refresh previously generated enemy camp rows.'

foreach ($data in @($sourceData, $addonData, $liveData)) {
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

$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceDataPath).Hash
$addonHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $addonDataPath).Hash
$liveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $liveDataPath).Hash
Assert-Equal -Actual $addonHash -Expected $sourceHash -Message 'Source addon nav destination data should match root nav destination data.'
Assert-Equal -Actual $liveHash -Expected $sourceHash -Message 'Live Ashita nav destination data should match root nav destination data.'

Write-Host 'nav enemy camp checks ok'

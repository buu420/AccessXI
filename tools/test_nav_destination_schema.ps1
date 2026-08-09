param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$addonPath = Join-Path $Root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$rootDestinations = Join-Path $Root 'data\ffxi-nav-destinations.tsv'
$addonDestinations = Join-Path $Root 'ashita\addons\accessxi_reader\data\ffxi-nav-destinations.tsv'
$rootGraph = Join-Path $Root 'data\ffxi-nav-zoneline-graph.tsv'
$addonGraph = Join-Path $Root 'ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv'
$harnessPath = Join-Path $Root 'tools\lua_tests\test_nav_destination_schema.lua'
$luaPath = Join-Path $Root 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) {
    $luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
}

foreach ($path in @($addonPath, $rootDestinations, $addonDestinations, $rootGraph, $addonGraph, $harnessPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing navigation schema test dependency: $path"
    }
}

$protectedPaths = @($rootDestinations, $addonDestinations, $rootGraph, $addonGraph)
$before = @{}
foreach ($path in $protectedPaths) {
    $before[$path] = @{
        Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Bytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
    }
}

$fixturePath = Join-Path ([System.IO.Path]::GetTempPath()) (
    'accessxi-nav-schema-{0}.tsv' -f [guid]::NewGuid().ToString('N')
)
try {
    $fixture = @(
        '# comment'
        "zone_id`tname`tx`tz`ty`tkind`tsource`tconfidence`tsection"
        'malformed'
        "101`tLegacy`t1`t2`t3`tnpc`tmanual"
        "101`tCurrent`t4`t5`t6`tobject`tmanual`tobserved`treview note"
        "101`tEmpty confidence`t4`t5`t6`tarea`tmanual`t`tsection survives"
        "101`tAppended`t7`t8`t9`tarea`tlsb-zoneline-all`tuntested`tgenerated section`tarea:v1:101:987`tlsb:zonelines:987`t`t"
        "101`tAppended`t7`t8`t9`tarea`tlsb-zoneline-all`tuntested`tgenerated section`tarea:v1:101:988`tlsb:zonelines:988`t`t"
        "101`tOrcish Fodder`t10`t11`t12`tenemy`tlsb-mob-spawn-camps`tuntested`tcamp 1`t" +
            "camp:v1:101:orcish-fodder:abc`tlsb:mob_spawn_points:group:34:mobname:Orcish_Fodder`t" +
            "413697,413698`tcomplete-link-v1-h120-y24"
    ) -join "`n"
    [System.IO.File]::WriteAllText(
        $fixturePath,
        $fixture + "`n",
        [System.Text.UTF8Encoding]::new($false)
    )

    & $luaPath $harnessPath $addonPath $fixturePath
    if ($LASTEXITCODE -ne 0) {
        throw "Navigation destination Lua schema harness failed with exit code $LASTEXITCODE."
    }
}
finally {
    Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
}

$rootHash = (Get-FileHash -LiteralPath $rootDestinations -Algorithm SHA256).Hash
$addonHash = (Get-FileHash -LiteralPath $addonDestinations -Algorithm SHA256).Hash
if ($rootHash -ne $addonHash) {
    throw "Repository and addon navigation destination copies differ."
}
foreach ($path in $protectedPaths) {
    $afterHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    $afterBytes = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($path))
    if ($afterHash -ne $before[$path].Hash -or $afterBytes -ne $before[$path].Bytes) {
        throw "Navigation schema harness modified protected data: $path"
    }
}

Write-Host 'navigation destination schema tests passed'

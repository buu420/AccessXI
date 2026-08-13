param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $Root).Path
$addonPath = Join-Path $root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$graphPath = Join-Path $root 'data\ffxi-nav-zoneline-graph.tsv'
$harnessPath = Join-Path $root 'tools\lua_tests\test_nav_capital_zone_visibility.lua'
$luaPath = Join-Path $root 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) {
    $luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
}
foreach ($path in @($addonPath, $graphPath, $harnessPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing capital zone visibility test dependency: $path"
    }
}

& $luaPath $harnessPath $addonPath $graphPath
if ($LASTEXITCODE -ne 0) {
    throw "Capital zone graph visibility failed with exit code $LASTEXITCODE."
}

Write-Host 'capital zone graph visibility checks ok'

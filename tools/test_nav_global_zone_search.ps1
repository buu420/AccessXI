param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $Root).Path
$addonPath = Join-Path $root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$harnessPath = Join-Path $root 'tools\lua_tests\test_nav_global_zone_search.lua'
$luaPath = Join-Path $root 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) {
    $luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
}
foreach ($path in @($addonPath, $harnessPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing global zone-search test dependency: $path"
    }
}

& $luaPath $harnessPath $addonPath
if ($LASTEXITCODE -ne 0) {
    throw "Global zone-name search behavior failed with exit code $LASTEXITCODE."
}

Write-Host 'global zone-name search checks ok'

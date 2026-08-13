param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $Root).Path
$addonPath = Join-Path $root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$graphPath = Join-Path $root 'ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv'
$harnessPath = Join-Path $root 'tools\lua_tests\test_chateau_zoneline_graph.lua'
$luaPath = Join-Path $root 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) {
    $luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
}
foreach ($path in @($addonPath, $graphPath, $harnessPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Chateau graph test dependency: $path"
    }
}

& $luaPath $harnessPath $addonPath $graphPath
if ($LASTEXITCODE -ne 0) {
    throw "Chateau zoneline graph behavior failed with exit code $LASTEXITCODE."
}

Write-Host 'Chateau zoneline graph checks ok'

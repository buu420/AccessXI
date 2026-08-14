$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Lua = Join-Path $PSScriptRoot 'lua51\lua5.1.exe'
$Module = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\collision_navigation.lua'
$Manifest = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\data\collision-native-manifest.tsv'
$Test = Join-Path $PSScriptRoot 'lua_tests\test_collision_navigation.lua'

if (-not (Test-Path -LiteralPath $Lua)) {
    throw "Lua 5.1 is missing: $Lua"
}

& $Lua $Test $Module $Manifest
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

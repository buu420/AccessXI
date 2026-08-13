param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $Root 'ashita\addons\accessxi_reader\modules\accessxi_sha256.lua'
$harnessPath = Join-Path $Root 'tools\lua_tests\test_accessxi_sha256.lua'
$luaPath = Join-Path $Root 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) {
    $luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
}

foreach ($path in @($modulePath, $harnessPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing SHA-256 test dependency: $path"
    }
}

& $luaPath $harnessPath $modulePath
if ($LASTEXITCODE -ne 0) {
    throw "AccessXI SHA-256 Lua behavior harness failed with exit code $LASTEXITCODE."
}

Write-Host 'accessxi SHA-256 wrapper tests passed'

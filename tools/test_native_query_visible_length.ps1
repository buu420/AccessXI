param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$readerPath = Join-Path $Root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaPath = Join-Path $Root 'tools\lua51\lua5.1.exe'
$harnessPath = Join-Path $Root 'tools\lua_tests\test_native_query_visible_length.lua'

foreach ($path in @($readerPath, $luaPath, $harnessPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required native query visible-length test path is missing: $path"
    }
}

& $luaPath $harnessPath $readerPath
if ($LASTEXITCODE -ne 0) {
    throw "Native query visible-length Lua harness failed with exit code $LASTEXITCODE."
}

Write-Host 'native query visible-length test passed'

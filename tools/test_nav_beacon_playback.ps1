$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ReaderPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$LuaPath = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'
$HarnessPath = Join-Path $RepoRoot 'tools\lua_tests\test_nav_beacon_playback.lua'

& $LuaPath $HarnessPath $ReaderPath
if ($LASTEXITCODE -ne 0) {
    throw "Navigation beacon playback harness failed with exit code $LASTEXITCODE."
}

Write-Output 'navigation beacon playback test passed'

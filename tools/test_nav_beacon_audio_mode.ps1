$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$LuaPath = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'
$Harness = Join-Path $RepoRoot 'tools\lua_tests\test_nav_beacon_audio_mode.lua'
$ReaderPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$CompatibilityDir = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\sounds\nav_beacon'
$HrtfDir = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\sounds\nav_beacon_hrtf'
$PreferencePath = [System.IO.Path]::GetTempFileName()

try {
    & $LuaPath $Harness $ReaderPath $CompatibilityDir $HrtfDir $PreferencePath
    if ($LASTEXITCODE -ne 0) {
        throw "Navigation beacon audio-mode harness failed with exit code $LASTEXITCODE."
    }
} finally {
    Remove-Item -LiteralPath $PreferencePath -Force -ErrorAction SilentlyContinue
}

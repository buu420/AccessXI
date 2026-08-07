param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$lua = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'
$test = Join-Path $RepoRoot 'tools\test_quick_status_hotkeys.lua'
$module = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\quick_status_hotkeys.lua'

& $lua $test $module
if ($LASTEXITCODE -ne 0) {
    throw "Quick status hotkey checks failed with exit code $LASTEXITCODE."
}

Write-Host 'Quick status hotkey focused checks passed'

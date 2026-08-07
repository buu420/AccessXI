param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$lua = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'
$test = Join-Path $RepoRoot 'tools\test_detail_summary_navigation.lua'
$module = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\menus\detail_summary_navigation.lua'

& $lua $test $module
if ($LASTEXITCODE -ne 0) {
    throw "Scrollable detail summary navigation checks failed with exit code $LASTEXITCODE."
}

Write-Host 'Scrollable detail summary navigation focused checks passed'

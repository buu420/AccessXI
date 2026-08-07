param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$lua = Join-Path $RepoRoot 'tools\lua51\lua5.1.exe'
$test = Join-Path $RepoRoot 'tools\test_records_of_eminence_detail_navigation.lua'
$module = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\menus\records_of_eminence_detail_navigation.lua'

& $lua $test $module
if ($LASTEXITCODE -ne 0) {
    throw "Records of Eminence detail navigation checks failed with exit code $LASTEXITCODE."
}

Write-Host 'Records of Eminence detail navigation focused checks passed'

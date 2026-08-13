$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TestPath = Join-Path $RepoRoot 'tools\test_nav_beacon_hrtf_assets.py'
$GeneratorPath = Join-Path $RepoRoot 'tools\generate_nav_beacon_hrtf.py'
$BankPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\sounds\nav_beacon_hrtf'

$Python = Get-Command py -ErrorAction SilentlyContinue
if ($null -ne $Python) {
    & $Python.Source -3 $TestPath $BankPath $GeneratorPath
} else {
    $Python = Get-Command python -ErrorAction Stop
    & $Python.Source $TestPath $BankPath $GeneratorPath
}
if ($LASTEXITCODE -ne 0) {
    throw "Navigation beacon HRTF asset checks failed with exit code $LASTEXITCODE."
}

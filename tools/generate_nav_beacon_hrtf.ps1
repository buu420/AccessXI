param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Requirements = Join-Path $RepoRoot 'tools\requirements-nav-beacon-hrtf.txt'
$Generator = Join-Path $RepoRoot 'tools\generate_nav_beacon_hrtf.py'
$AssetTest = Join-Path $RepoRoot 'tools\test_nav_beacon_hrtf_assets.py'
$Bank = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\sounds\nav_beacon_hrtf'

if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    $VenvRoot = Join-Path $RepoRoot 'build\nav-beacon-hrtf-python'
    $PythonPath = Join-Path $VenvRoot 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
        $Launcher = Get-Command py -ErrorAction SilentlyContinue
        if ($null -ne $Launcher) {
            & $Launcher.Source -3 -m venv $VenvRoot
        } else {
            $Launcher = Get-Command python -ErrorAction Stop
            & $Launcher.Source -m venv $VenvRoot
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Could not create the HRTF build environment: $LASTEXITCODE"
        }
    }
    & $PythonPath -m pip install --disable-pip-version-check --requirement $Requirements
    if ($LASTEXITCODE -ne 0) {
        throw "Could not install pinned HRTF build dependencies: $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) {
    throw "HRTF Python is unavailable: $PythonPath"
}

& $PythonPath $Generator
if ($LASTEXITCODE -ne 0) {
    throw "HRTF beacon generation failed: $LASTEXITCODE"
}
& $PythonPath $AssetTest $Bank $Generator
if ($LASTEXITCODE -ne 0) {
    throw "Generated HRTF beacon asset validation failed: $LASTEXITCODE"
}

Write-Output "Generated and validated the navigation beacon HRTF bank: $Bank"

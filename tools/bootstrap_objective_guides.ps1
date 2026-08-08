param(
    [string]$Python = $env:ACCESSXI_PYTHON,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Resolve-Python {
    param([string]$Requested)

    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        if (-not (Test-Path -LiteralPath $Requested)) {
            throw "Requested Python executable does not exist: $Requested"
        }
        return (Resolve-Path -LiteralPath $Requested).Path
    }

    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) {
        return $pythonCommand.Source
    }

    $pyCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($null -ne $pyCommand) {
        return $pyCommand.Source
    }

    throw 'Python 3.9 or newer is required to bootstrap the objective guide importer.'
}

$basePython = Resolve-Python -Requested $Python
$venvRoot = Join-Path $RepoRoot 'tools\.objective-guides-venv'
$venvPython = Join-Path $venvRoot 'Scripts\python.exe'
$requirements = Join-Path $RepoRoot 'tools\requirements-objective-guides.txt'

if (-not (Test-Path -LiteralPath $venvPython)) {
    if ([System.IO.Path]::GetFileName($basePython) -ieq 'py.exe') {
        & $basePython -3 -m venv $venvRoot
    }
    else {
        & $basePython -m venv $venvRoot
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Objective guide Python virtual environment creation failed with exit code $LASTEXITCODE."
    }
}

& $venvPython -m pip install --disable-pip-version-check --requirement $requirements
if ($LASTEXITCODE -ne 0) {
    throw "Objective guide Python dependency installation failed with exit code $LASTEXITCODE."
}

Write-Host "Objective guide Python ready: $venvPython"

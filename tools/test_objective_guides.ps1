param(
    [string]$Python,
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Python)) {
    $Python = Join-Path $RepoRoot 'tools\.objective-guides-venv\Scripts\python.exe'
}
if (-not (Test-Path -LiteralPath $Python)) {
    throw "Objective guide Python is unavailable: $Python. Run tools\bootstrap_objective_guides.ps1 first."
}

Push-Location $RepoRoot
try {
    & $Python -m unittest tools.test_objective_guides
    if ($LASTEXITCODE -ne 0) {
        throw "Objective guide tests failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

Write-Host 'Objective guide tests passed'

param(
    [ValidateSet('manifest', 'fetch', 'build', 'report', 'all')]
    [string]$Command = 'all',
    [string]$FfxiRoot = 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI',
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$Offline,
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
$python = Join-Path $RepoRoot 'tools\.objective-guides-venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    throw "Objective guide Python is unavailable: $python. Run tools\bootstrap_objective_guides.ps1 first."
}
if ($Offline -and $Refresh) {
    throw 'Offline builds cannot refresh wiki source snapshots.'
}

$arguments = @(
    '-m', 'tools.objective_guides.cli', $Command,
    '--repo-root', $RepoRoot,
    '--ffxi-root', $FfxiRoot
)
if ($Offline) {
    $arguments += '--offline'
}
if ($Refresh) {
    $arguments += '--refresh'
}

Push-Location $RepoRoot
try {
    & $python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Objective guide $Command failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

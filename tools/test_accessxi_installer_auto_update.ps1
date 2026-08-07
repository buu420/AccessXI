param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'

$project = Join-Path $RepoRoot 'installer\AccessXIInstaller.UpdaterTests\AccessXIInstaller.UpdaterTests.csproj'
if (-not (Test-Path -LiteralPath $project)) {
    throw "Missing installer updater test project: $project"
}

& dotnet run --project $project --configuration Release
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

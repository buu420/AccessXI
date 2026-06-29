param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$PolExe = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe',
    [switch]$NoBuild,
    [switch]$NoDeploy
)

$ErrorActionPreference = 'Stop'

$activeAshitaPolPlugin = 'C:\Users\buu42\Ashita\polplugins\accessxi_pol_nvda.dll'
$reloadedRoot = Join-Path $RepoRoot 'external\Reloaded-II'

if (Test-Path -LiteralPath $activeAshitaPolPlugin) {
    throw "Refusing to launch: old Ashita POL plugin is active at $activeAshitaPolPlugin"
}
if (-not (Test-Path -LiteralPath "$activeAshitaPolPlugin.disabled")) {
    throw "Disabled Ashita POL plugin marker is missing: $activeAshitaPolPlugin.disabled"
}
if (-not (Test-Path -LiteralPath (Join-Path $reloadedRoot 'Reloaded-II.exe'))) {
    throw "Reloaded-II is missing: $reloadedRoot"
}
if (-not (Test-Path -LiteralPath $PolExe)) {
    throw "PlayOnlineViewer\pol.exe is missing: $PolExe"
}

if (-not $NoDeploy) {
    $deployArgs = @{
        RepoRoot = $RepoRoot
        PolExe = $PolExe
    }
    if ($NoBuild) {
        $deployArgs.NoBuild = $true
    }

    & (Join-Path $RepoRoot 'tools\deploy_pol_reloaded_bootloader.ps1') @deployArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
} elseif (-not $NoBuild) {
    & (Join-Path $RepoRoot 'tools\build_pol_reloaded.ps1') -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Start-Process -FilePath $PolExe -WorkingDirectory (Split-Path -Parent $PolExe)

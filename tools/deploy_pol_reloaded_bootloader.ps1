param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$PolExe = 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer\pol.exe',
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

function Backup-ExistingFile {
    param(
        [string]$Path,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $item = Get-Item -LiteralPath $Path
    if ($item.PSIsContainer) {
        throw "Refusing to replace directory: $Path"
    }

    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupRoot $item.Name) -Force
}

function Copy-WithBackup {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source file is missing: $Source"
    }

    $destinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

    if (Test-Path -LiteralPath $Destination) {
        $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
        if ($sourceHash -eq $destinationHash) {
            return
        }
    }

    Backup-ExistingFile -Path $Destination -BackupRoot $BackupRoot
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Remove-WithBackup {
    param(
        [string]$Path,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Backup-ExistingFile -Path $Path -BackupRoot $BackupRoot
    Remove-Item -LiteralPath $Path -Force
}

function Set-ReloadedConsoleHidden {
    param(
        [string]$Path,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Reloaded-II loader config is missing: $Path"
    }

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($config.PSObject.Properties.Name -contains 'ShowConsole') {
        $config.ShowConsole = $false
    } else {
        $config | Add-Member -NotePropertyName 'ShowConsole' -NotePropertyValue $false
    }

    Backup-ExistingFile -Path $Path -BackupRoot $BackupRoot
    $config | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$activeAshitaPolPlugin = 'C:\Users\buu42\Ashita\polplugins\accessxi_pol_nvda.dll'
$reloadedRoot = Join-Path $RepoRoot 'external\Reloaded-II'
$loaderConfigPath = Join-Path $env:APPDATA 'Reloaded-Mod-Loader-II\ReloadedII.json'
$modsRoot = Join-Path $reloadedRoot 'Mods'
$polDirectory = Split-Path -Parent $PolExe
$asiArchive = Join-Path $reloadedRoot 'Loader\Asi\UltimateAsiLoader.7z'
$asiExtractRoot = Join-Path $reloadedRoot '_asi_extract'
$asiLoader32 = Join-Path $asiExtractRoot 'ASILoader32.dll'
$bootloaderSource = Join-Path $RepoRoot 'tools\pol_asi_probe\AccessXI.PolReloadedBootstrap.asi'
$bootstrapperSource = Join-Path $reloadedRoot 'Loader\X86\Bootstrapper\Reloaded.Mod.Loader.Bootstrapper.dll'
$deployedAsiProxy = Join-Path $polDirectory 'ddraw.dll'
$staleWinmmProxy = Join-Path $polDirectory 'winmm.dll'
$scriptsDirectory = Join-Path $polDirectory 'scripts'
$deployedBootloader = Join-Path $scriptsDirectory 'AccessXI.PolReloadedBootstrap.asi'
$deployedBootstrapper = Join-Path $scriptsDirectory 'Reloaded.Mod.Loader.Bootstrapper.dll'
$directBootstrapperAsi = Join-Path $scriptsDirectory 'Reloaded.Mod.Loader.Bootstrapper.asi'
$staleProbeAsi = Join-Path $scriptsDirectory 'AccessXI.PolAsiProbe.asi'
$portableMarker = Join-Path $scriptsDirectory 'ReloadedPortable.txt'
$appConfigDirectory = Join-Path $reloadedRoot 'Apps\AccessXI.PolPreLogin'
$appConfigPath = Join-Path $appConfigDirectory 'AppConfig.json'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $RepoRoot "backups\pol_bootloader\$timestamp"

if (Test-Path -LiteralPath $activeAshitaPolPlugin) {
    throw "Refusing to deploy: old Ashita POL plugin is active at $activeAshitaPolPlugin"
}
if (-not (Test-Path -LiteralPath "$activeAshitaPolPlugin.disabled")) {
    throw "Disabled Ashita POL plugin marker is missing: $activeAshitaPolPlugin.disabled"
}
if (-not (Test-Path -LiteralPath (Join-Path $reloadedRoot 'Reloaded-II.exe'))) {
    throw "Reloaded-II is missing from $reloadedRoot"
}
if (-not (Test-Path -LiteralPath $loaderConfigPath)) {
    throw "Reloaded-II loader config is missing: $loaderConfigPath"
}
if (-not (Test-Path -LiteralPath $PolExe)) {
    throw "PlayOnline Viewer target is missing: $PolExe"
}

if (-not $NoBuild) {
    & (Join-Path $RepoRoot 'tools\build_pol_reloaded.ps1') -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & (Join-Path $RepoRoot 'tools\build_pol_reloaded_bootloader.ps1') -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $modsRoot 'AccessXI.PolReloaded\AccessXI.PolReloaded.dll'))) {
    throw "Built Reloaded mod is missing from $modsRoot"
}

if (-not (Test-Path -LiteralPath $asiLoader32)) {
    if (-not (Test-Path -LiteralPath $asiArchive)) {
        throw "Ultimate ASI Loader archive is missing: $asiArchive"
    }
    New-Item -ItemType Directory -Force -Path $asiExtractRoot | Out-Null
    tar -xf $asiArchive -C $asiExtractRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Copy-WithBackup -Source $asiLoader32 -Destination $deployedAsiProxy -BackupRoot $backupRoot
Copy-WithBackup -Source $bootloaderSource -Destination $deployedBootloader -BackupRoot $backupRoot
Copy-WithBackup -Source $bootstrapperSource -Destination $deployedBootstrapper -BackupRoot $backupRoot

Remove-WithBackup -Path $staleWinmmProxy -BackupRoot $backupRoot
Remove-WithBackup -Path $directBootstrapperAsi -BackupRoot $backupRoot
Remove-WithBackup -Path $staleProbeAsi -BackupRoot $backupRoot
if (Test-Path -LiteralPath $portableMarker) {
    Remove-WithBackup -Path $portableMarker -BackupRoot $backupRoot
}

Set-ReloadedConsoleHidden -Path $loaderConfigPath -BackupRoot $backupRoot

New-Item -ItemType Directory -Force -Path $appConfigDirectory | Out-Null
$appConfig = [ordered]@{
    AppId = 'pol.exe'
    AppName = 'PlayOnline Viewer'
    AppLocation = $PolExe
    AppArguments = ''
    AppIcon = 'Icon.png'
    AutoInject = $false
    EnabledMods = @('accessxi.pol.prelogin')
    WorkingDirectory = $polDirectory
    PluginData = @{}
    SortedMods = @('accessxi.pol.prelogin')
    PreserveDisabledModOrder = $true
    DontInject = $false
    IsMsStore = $false
}
$appConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $appConfigPath -Encoding UTF8

$result = [ordered]@{
    AppConfig = $appConfigPath
    LoaderConfig = $loaderConfigPath
    AsiProxy = $deployedAsiProxy
    Bootloader = $deployedBootloader
    Bootstrapper = $deployedBootstrapper
    AsiProxyHash = (Get-FileHash -LiteralPath $deployedAsiProxy -Algorithm SHA256).Hash
    BootloaderHash = (Get-FileHash -LiteralPath $deployedBootloader -Algorithm SHA256).Hash
    BootstrapperHash = (Get-FileHash -LiteralPath $deployedBootstrapper -Algorithm SHA256).Hash
}

$result

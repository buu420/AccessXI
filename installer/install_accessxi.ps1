param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'AccessXI'),
    [string]$PolExe = '',
    [string]$ReloadedConfigRoot = '',
    [switch]$SkipPolBootloader,
    [switch]$SkipVisualCppRedistributables,
    [switch]$SkipDotNetDesktopRuntimes,
    [switch]$NoDesktopShortcut
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Join-PathParts {
    param(
        [string]$Root,
        [string[]]$Parts
    )

    $path = $Root
    foreach ($part in $Parts) {
        $path = Join-Path $path $part
    }
    return $path
}

function Get-DefaultProgramFilesRoots {
    $roots = @(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86),
        $env:ProgramW6432,
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    )

    $seen = @{}
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        $resolved = Resolve-FullPath $root
        $key = $resolved.TrimEnd('\').ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $resolved
        }
    }
}

function Find-DefaultPolExe {
    $relativeCandidates = @(
        @('PlayOnline', 'SquareEnix', 'PlayOnlineViewer', 'pol.exe'),
        @('SquareEnix', 'PlayOnlineViewer', 'pol.exe')
    )

    foreach ($root in Get-DefaultProgramFilesRoots) {
        foreach ($relativeCandidate in $relativeCandidates) {
            $candidate = Join-PathParts -Root $root -Parts $relativeCandidate
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return ''
}

function Get-FfxiInstallRootFromPolExe {
    param([string]$PolExe)

    $polDirectory = Split-Path -Parent (Resolve-FullPath $PolExe)
    if ($polDirectory -eq '') {
        return ''
    }

    $squareEnixRoot = Split-Path -Parent $polDirectory
    if ($squareEnixRoot -eq '') {
        return ''
    }

    return Join-Path $squareEnixRoot 'FINAL FANTASY XI'
}

function Set-AshitaCliFfxiInstallPath {
    param(
        [string]$AshitaRoot,
        [string]$PolExe
    )

    $profilePath = Join-Path $AshitaRoot 'config\boot\accessxi-retail.ini'
    if (-not (Test-Path -LiteralPath $profilePath)) {
        throw "Ashita CLI profile is missing: $profilePath"
    }

    $ffxiRoot = Get-FfxiInstallRootFromPolExe -PolExe $PolExe
    if ($ffxiRoot -eq '') {
        return ''
    }

    $content = Get-Content -LiteralPath $profilePath -Raw
    if ($content -match '(?m)^0042\s*=') {
        $content = [regex]::Replace($content, '(?m)^0042\s*=.*$', "0042 = $ffxiRoot")
    } else {
        $content = $content.TrimEnd() + "`r`n0042 = $ffxiRoot`r`n"
    }

    Set-Content -LiteralPath $profilePath -Value $content -Encoding ASCII
    return $ffxiRoot
}

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

function Copy-PayloadDirectory {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Payload directory is missing: $Source"
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
}

function Remove-StaleAccessXiReloadedMod {
    param([string]$ReloadedRoot)

    $modDirectory = Join-Path $ReloadedRoot 'Mods\AccessXI.PolReloaded'
    if (-not (Test-Path -LiteralPath $modDirectory)) {
        return
    }

    Remove-Item -LiteralPath $modDirectory -Recurse -Force
}

function Assert-DeployedFileHash {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Cannot verify deployed file because source is missing: $Source"
    }
    if (-not (Test-Path -LiteralPath $Destination)) {
        throw "Cannot verify deployed file because destination is missing: $Destination"
    }

    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "Deployed file hash mismatch for $Name. Source=$sourceHash Destination=$destinationHash Path=$Destination"
    }

    return [ordered]@{
        Source = $Source
        Destination = $Destination
        Hash = $destinationHash
    }
}

function Disable-OldAshitaPolPlugin {
    param([string]$AshitaRoot)

    $active = Join-Path $AshitaRoot 'polplugins\accessxi_pol_nvda.dll'
    if (-not (Test-Path -LiteralPath $active)) {
        return
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $disabled = "$active.disabled"
    if (-not (Test-Path -LiteralPath $disabled)) {
        Move-Item -LiteralPath $active -Destination $disabled -Force
        return
    }

    Move-Item -LiteralPath $active -Destination "$disabled.installer-$timestamp" -Force
}

function Write-ReloadedLoaderConfig {
    param(
        [string]$ReloadedRoot,
        [string]$ReloadedConfigRoot,
        [string]$BackupRoot
    )

    if ([string]::IsNullOrWhiteSpace($ReloadedConfigRoot)) {
        $configRoot = Join-Path $env:APPDATA 'Reloaded-Mod-Loader-II'
    } else {
        $configRoot = Resolve-FullPath $ReloadedConfigRoot
    }
    $configPath = Join-Path $configRoot 'ReloadedII.json'
    New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
    if (Test-Path -LiteralPath $configPath) {
        Backup-ExistingFile -Path $configPath -BackupRoot $BackupRoot
    }

    $config = [ordered]@{
        LoaderPath32 = Join-Path $ReloadedRoot 'Loader\x86\Reloaded.Mod.Loader.dll'
        LoaderPath64 = Join-Path $ReloadedRoot 'Loader\x64\Reloaded.Mod.Loader.dll'
        LauncherPath = Join-Path $ReloadedRoot 'Reloaded-II.exe'
        Bootstrapper32Path = Join-Path $ReloadedRoot 'Loader\x86\Bootstrapper\Reloaded.Mod.Loader.Bootstrapper.dll'
        Bootstrapper64Path = Join-Path $ReloadedRoot 'Loader\x64\Bootstrapper\Reloaded.Mod.Loader.Bootstrapper.dll'
        ApplicationConfigDirectory = Join-Path $ReloadedRoot 'Apps'
        ModUserConfigDirectory = Join-Path $ReloadedRoot 'User\Mods'
        MiscConfigDirectory = Join-Path $ReloadedRoot 'User\Misc'
        PluginConfigDirectory = Join-Path $ReloadedRoot 'Plugins'
        ModConfigDirectory = Join-Path $ReloadedRoot 'Mods'
        EnabledPlugins = @()
        LanguageFile = 'en-GB.xaml'
        ThemeFile = 'Default.xaml'
        FirstLaunch = $false
        ShowConsole = $false
        LogFileCompressTimeHours = 6
        LogFileDeleteHours = 336
        CrashDumpDeleteHours = 24
        NuGetFeeds = @(
            [ordered]@{
                Name = 'Official Repository'
                URL = 'https://packages.sewer56.moe/v3/index.json'
                Description = 'Package repository of Sewer56, the developer of Reloaded. Contains personal and popular community packages.'
            }
        )
        ForceModPrereleases = $false
        ReloadedProcessListRefreshInterval = 1000
        LoaderSetupTimeout = 30000
        LoaderSetupSleeptime = 32
        ProcessRefreshInterval = 200
        SkipWineLaunchWarning = $false
        DisableDInput = $false
    }

    $config | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $configPath -Encoding UTF8
    return $configPath
}

function Write-ReloadedPolAppConfig {
    param(
        [string]$ReloadedRoot,
        [string]$PolExe
    )

    $polDirectory = Split-Path -Parent $PolExe
    $appConfigDirectory = Join-Path $ReloadedRoot 'Apps\AccessXI.PolPreLogin'
    $appConfigPath = Join-Path $appConfigDirectory 'AppConfig.json'
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
    return $appConfigPath
}

function Repair-PolUrlFiles {
    param([string]$PolExe)

    $polDirectory = Split-Path -Parent $PolExe
    $sourceDirectory = Join-Path $polDirectory 'default\usr\all\url'
    $destinationDirectory = Join-Path $polDirectory 'usr\all\url'
    $knownInstallerKeyPaths = @('cert.db', 'rdthosts.bin', 'cache\dcfat0.bin')
    $repairedFiles = @()

    if (-not (Test-Path -LiteralPath $sourceDirectory)) {
        return $repairedFiles
    }

    foreach ($relativePath in $knownInstallerKeyPaths) {
        $source = Join-Path $sourceDirectory $relativePath
        if (-not (Test-Path -LiteralPath $source)) {
            throw "PlayOnline Viewer is missing the default URL source: $source"
        }
    }

    $resolvedSourceDirectory = ([System.IO.Path]::GetFullPath($sourceDirectory)).TrimEnd('\')
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

    foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse -Force) {
        $relativePath = $sourceFile.FullName.Substring($resolvedSourceDirectory.Length).TrimStart('\')
        if ($relativePath -eq '') {
            continue
        }

        $destination = Join-Path $destinationDirectory $relativePath
        if (Test-Path -LiteralPath $destination) {
            continue
        }

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destination -Force
        $repairedFiles += $relativePath
    }

    return $repairedFiles
}

function Install-VisualCppRedistributable {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Visual C++ redistributable prerequisite is missing: $Path"
    }

    Write-Output "Installing Microsoft Visual C++ runtime prerequisite: $Name"
    $process = Start-Process -FilePath $Path -ArgumentList @('/install', '/quiet', '/norestart') -Wait -PassThru
    $exitCode = $process.ExitCode
    $allowedExitCodes = @(0, 3010, 1638)
    if ($allowedExitCodes -notcontains $exitCode) {
        throw "Visual C++ redistributable prerequisite failed: $Name exited with code $exitCode."
    }

    $status = switch ($exitCode) {
        0 { 'installed-or-current'; break }
        3010 { 'installed-reboot-required'; break }
        1638 { 'already-installed-or-newer'; break }
        default { 'accepted' }
    }

    Write-Output "Visual C++ runtime prerequisite result: $Name, exit code $exitCode, $status"
    return [pscustomobject]([ordered]@{
        Name = $Name
        Path = $Path
        ExitCode = $exitCode
        Status = $status
    })
}

function Install-VisualCppRedistributables {
    param([string]$PayloadRoot)

    $prerequisitesRoot = Join-Path $PayloadRoot 'Prerequisites'
    $results = @()
    $results += Install-VisualCppRedistributable -Name 'vc_redist.x86.exe' -Path (Join-Path $prerequisitesRoot 'vc_redist.x86.exe')
    $results += Install-VisualCppRedistributable -Name 'vc_redist.x64.exe' -Path (Join-Path $prerequisitesRoot 'vc_redist.x64.exe')
    return $results
}

function Install-DotNetDesktopRuntime {
    param(
        [string]$Path,
        [string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ".NET Desktop Runtime prerequisite is missing: $Path"
    }

    Write-Output "Installing Microsoft .NET Desktop Runtime prerequisite: $Name"
    $process = Start-Process -FilePath $Path -ArgumentList @('/install', '/quiet', '/norestart') -Wait -PassThru
    $exitCode = $process.ExitCode
    $allowedExitCodes = @(0, 3010, 1638)
    if ($allowedExitCodes -notcontains $exitCode) {
        throw ".NET Desktop Runtime prerequisite failed: $Name exited with code $exitCode."
    }

    $status = switch ($exitCode) {
        0 { 'installed-or-current'; break }
        3010 { 'installed-reboot-required'; break }
        1638 { 'already-installed-or-newer'; break }
        default { 'accepted' }
    }

    Write-Output ".NET Desktop Runtime prerequisite result: $Name, exit code $exitCode, $status"
    return [pscustomobject]([ordered]@{
        Name = $Name
        Path = $Path
        ExitCode = $exitCode
        Status = $status
    })
}

function Install-DotNetDesktopRuntimes {
    param([string]$PayloadRoot)

    $prerequisitesRoot = Join-Path $PayloadRoot 'Prerequisites'
    $results = @()
    $results += Install-DotNetDesktopRuntime -Name 'windowsdesktop-runtime-9.0.17-win-x86.exe' -Path (Join-Path $prerequisitesRoot 'windowsdesktop-runtime-9.0.17-win-x86.exe')
    $results += Install-DotNetDesktopRuntime -Name 'windowsdesktop-runtime-9.0.17-win-x64.exe' -Path (Join-Path $prerequisitesRoot 'windowsdesktop-runtime-9.0.17-win-x64.exe')
    return $results
}

function Deploy-PolBootloader {
    param(
        [string]$PayloadRoot,
        [string]$ReloadedRoot,
        [string]$PolExe,
        [string]$BackupRoot
    )

    $polDirectory = Split-Path -Parent $PolExe
    $scriptsDirectory = Join-Path $polDirectory 'scripts'
    $asiLoader32 = Join-Path $ReloadedRoot '_asi_extract\ASILoader32.dll'
    if (-not (Test-Path -LiteralPath $asiLoader32)) {
        $asiArchive = Join-Path $ReloadedRoot 'Loader\Asi\UltimateAsiLoader.7z'
        if (-not (Test-Path -LiteralPath $asiArchive)) {
            throw "Missing x86 ASI loader and archive: $asiLoader32"
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $asiLoader32) | Out-Null
        tar -xf $asiArchive -C (Split-Path -Parent $asiLoader32)
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    $bootloaderSource = Join-Path $PayloadRoot 'pol_bootloader\AccessXI.PolReloadedBootstrap.asi'
    $bootstrapperSource = Join-Path $ReloadedRoot 'Loader\x86\Bootstrapper\Reloaded.Mod.Loader.Bootstrapper.dll'
    Copy-WithBackup -Source $asiLoader32 -Destination (Join-Path $polDirectory 'ddraw.dll') -BackupRoot $BackupRoot
    Copy-WithBackup -Source $bootloaderSource -Destination (Join-Path $scriptsDirectory 'AccessXI.PolReloadedBootstrap.asi') -BackupRoot $BackupRoot
    Copy-WithBackup -Source $bootstrapperSource -Destination (Join-Path $scriptsDirectory 'Reloaded.Mod.Loader.Bootstrapper.dll') -BackupRoot $BackupRoot

    Remove-WithBackup -Path (Join-Path $polDirectory 'winmm.dll') -BackupRoot $BackupRoot
    Remove-WithBackup -Path (Join-Path $scriptsDirectory 'Reloaded.Mod.Loader.Bootstrapper.asi') -BackupRoot $BackupRoot
    Remove-WithBackup -Path (Join-Path $scriptsDirectory 'AccessXI.PolAsiProbe.asi') -BackupRoot $BackupRoot
    Remove-WithBackup -Path (Join-Path $scriptsDirectory 'ReloadedPortable.txt') -BackupRoot $BackupRoot
}

function New-AshitaShortcut {
    param([string]$AshitaRoot)

    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $shortcutPath = Join-Path $desktop 'AccessXI Ashita.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $AshitaRoot 'Ashita-cli.exe'
    $shortcut.Arguments = 'accessxi-retail.ini'
    $shortcut.WorkingDirectory = $AshitaRoot
    $shortcut.WindowStyle = 1
    $shortcut.Description = 'Launch Ashita v4 with the AccessXI Retail profile.'
    $shortcut.Save()
    return $shortcutPath
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$payloadRoot = Join-Path $scriptRoot 'payload'
$setupGuideSource = Join-Path $scriptRoot 'setup-guide.md'
$ashitaSource = Join-Path $payloadRoot 'Ashita'
$reloadedSource = Join-Path $payloadRoot 'Reloaded-II'
$prerequisitesSource = Join-Path $payloadRoot 'Prerequisites'
$packageManifestPath = Join-Path $scriptRoot 'manifest.json'
$packageManifest = $null
if (Test-Path -LiteralPath $packageManifestPath) {
    $packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
}

if ($PolExe -eq '') {
    $PolExe = Find-DefaultPolExe
}
if ($PolExe -eq '' -or -not (Test-Path -LiteralPath $PolExe)) {
    throw 'PlayOnline Viewer pol.exe was not found. Re-run with -PolExe "C:\Path\To\PlayOnlineViewer\pol.exe".'
}

$InstallRoot = Resolve-FullPath $InstallRoot
$ashitaDest = Join-Path $InstallRoot 'Ashita'
$reloadedDest = Join-Path $InstallRoot 'Reloaded-II'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $InstallRoot "backups\installer\$timestamp"

if (-not (Test-Path -LiteralPath (Join-Path $ashitaSource 'Ashita-cli.exe'))) {
    throw "Ashita-cli.exe is missing from installer payload: $ashitaSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $ashitaSource 'AccessXI.cmd'))) {
    throw "AccessXI.cmd is missing from installer payload: $ashitaSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $ashitaSource 'config\boot\accessxi-retail.ini'))) {
    throw "accessxi-retail.ini is missing from installer payload: $ashitaSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $ashitaSource 'addons\accessxi_reader\accessxi_reader.lua'))) {
    throw "accessxi_reader addon is missing from installer payload: $ashitaSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $reloadedSource 'Reloaded-II.exe'))) {
    throw "Reloaded-II.exe is missing from installer payload: $reloadedSource"
}
if (-not (Test-Path -LiteralPath (Join-Path $reloadedSource 'Mods\AccessXI.PolReloaded\prism.dll'))) {
    throw "Packaged prism.dll is missing beside the Reloaded POL mod."
}
if (-not (Test-Path -LiteralPath $setupGuideSource)) {
    throw "Packaged setup-guide.md is missing."
}
if (-not (Test-Path -LiteralPath (Join-Path $prerequisitesSource 'vc_redist.x86.exe'))) {
    throw "Packaged x86 Visual C++ redistributable prerequisite is missing."
}
if (-not (Test-Path -LiteralPath (Join-Path $prerequisitesSource 'vc_redist.x64.exe'))) {
    throw "Packaged x64 Visual C++ redistributable prerequisite is missing."
}
if (-not (Test-Path -LiteralPath (Join-Path $prerequisitesSource 'windowsdesktop-runtime-9.0.17-win-x86.exe'))) {
    throw "Packaged x86 .NET Desktop Runtime prerequisite is missing."
}
if (-not (Test-Path -LiteralPath (Join-Path $prerequisitesSource 'windowsdesktop-runtime-9.0.17-win-x64.exe'))) {
    throw "Packaged x64 .NET Desktop Runtime prerequisite is missing."
}

if ($SkipVisualCppRedistributables) {
    Write-Output 'Skipping Visual C++ runtime prerequisite installation because the installer wrapper already handled or skipped dependency installation.'
    $visualCppRedistributables = @(
        [pscustomobject]([ordered]@{
            Name = 'Visual C++ Redistributables'
            Path = ''
            ExitCode = $null
            Status = 'skipped-by-wrapper'
        })
    )
} else {
    $visualCppRedistributables = Install-VisualCppRedistributables -PayloadRoot $payloadRoot
}

if ($SkipDotNetDesktopRuntimes) {
    Write-Output 'Skipping .NET Desktop Runtime prerequisite installation because the installer wrapper already handled or skipped dependency installation.'
    $dotNetDesktopRuntimes = @(
        [pscustomobject]([ordered]@{
            Name = '.NET Desktop Runtimes'
            Path = ''
            ExitCode = $null
            Status = 'skipped-by-wrapper'
        })
    )
} else {
    $dotNetDesktopRuntimes = Install-DotNetDesktopRuntimes -PayloadRoot $payloadRoot
}
Copy-PayloadDirectory -Source $ashitaSource -Destination $ashitaDest
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
Copy-Item -LiteralPath $setupGuideSource -Destination (Join-Path $InstallRoot 'setup-guide.md') -Force
$ffxiInstallRoot = Set-AshitaCliFfxiInstallPath -AshitaRoot $ashitaDest -PolExe $PolExe
Remove-StaleAccessXiReloadedMod -ReloadedRoot $reloadedDest
Copy-PayloadDirectory -Source $reloadedSource -Destination $reloadedDest
Disable-OldAshitaPolPlugin -AshitaRoot $ashitaDest

$loaderConfigPath = Write-ReloadedLoaderConfig -ReloadedRoot $reloadedDest -ReloadedConfigRoot $ReloadedConfigRoot -BackupRoot $backupRoot
$appConfigPath = Write-ReloadedPolAppConfig -ReloadedRoot $reloadedDest -PolExe $PolExe
$polUrlFilesRepaired = @()

if (-not $SkipPolBootloader) {
    $polUrlFilesRepaired = Repair-PolUrlFiles -PolExe $PolExe
    Deploy-PolBootloader -PayloadRoot $payloadRoot -ReloadedRoot $reloadedDest -PolExe $PolExe -BackupRoot $backupRoot
}

$shortcutPath = ''
if (-not $NoDesktopShortcut) {
    $shortcutPath = New-AshitaShortcut -AshitaRoot $ashitaDest
}

$deployedHashes = [ordered]@{
    PolReloadedMod = Assert-DeployedFileHash -Name 'PolReloadedMod' -Source (Join-Path $reloadedSource 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll') -Destination (Join-Path $reloadedDest 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll')
    PolReloadedNative = Assert-DeployedFileHash -Name 'PolReloadedNative' -Source (Join-Path $reloadedSource 'Mods\AccessXI.PolReloaded\accessxi_pol_native.dll') -Destination (Join-Path $reloadedDest 'Mods\AccessXI.PolReloaded\accessxi_pol_native.dll')
    PolReloadedPrism = Assert-DeployedFileHash -Name 'PolReloadedPrism' -Source (Join-Path $reloadedSource 'Mods\AccessXI.PolReloaded\prism.dll') -Destination (Join-Path $reloadedDest 'Mods\AccessXI.PolReloaded\prism.dll')
}
if (-not $SkipPolBootloader) {
    $deployedHashes['PolBootloader'] = Assert-DeployedFileHash -Name 'PolBootloader' -Source (Join-Path $payloadRoot 'pol_bootloader\AccessXI.PolReloadedBootstrap.asi') -Destination (Join-Path (Split-Path -Parent $PolExe) 'scripts\AccessXI.PolReloadedBootstrap.asi')
}

$summary = [ordered]@{
    InstallRoot = $InstallRoot
    AshitaCli = Join-Path $ashitaDest 'Ashita-cli.exe'
    AccessXILauncher = Join-Path $ashitaDest 'Ashita-cli.exe'
    AccessXILauncherArguments = 'accessxi-retail.ini'
    AccessXIBatchLauncher = Join-Path $ashitaDest 'AccessXI.cmd'
    SetupGuide = Join-Path $InstallRoot 'setup-guide.md'
    AshitaCliProfile = Join-Path $ashitaDest 'config\boot\accessxi-retail.ini'
    AshitaGuiProfile = Join-Path $ashitaDest 'config\boot\AccessXI Retail.xml'
    ReloadedRoot = $reloadedDest
    ReloadedLoaderConfig = $loaderConfigPath
    ReloadedPolAppConfig = $appConfigPath
    PolExe = $PolExe
    FfxiInstallRoot = $ffxiInstallRoot
    PolBootloaderDeployed = (-not $SkipPolBootloader)
    PolUrlFilesRepaired = $polUrlFilesRepaired
    VisualCppRedistributables = $visualCppRedistributables
    DotNetDesktopRuntimes = $dotNetDesktopRuntimes
    Shortcut = $shortcutPath
    BackupRoot = $backupRoot
    PackageManifestCreatedAt = if ($null -ne $packageManifest) { $packageManifest.CreatedAt } else { '' }
    PackagePolReloadedModHash = if ($null -ne $packageManifest) { $packageManifest.PolReloadedModHash } else { '' }
    PackagePolBootloaderHash = if ($null -ne $packageManifest) { $packageManifest.PolBootloaderHash } else { '' }
    DeployedHashes = $deployedHashes
    DiagnosticLogDirectory = Join-Path $env:USERPROFILE 'AccessXI\logs'
    DiagnosticLogs = [ordered]@{
        ReloadedStartup = Join-Path $env:USERPROFILE 'AccessXI\logs\pol-reloaded-startup.log'
        ReloadedSpeech = Join-Path $env:USERPROFILE 'AccessXI\logs\pol-reloaded-speech.log'
        NativePolMonitor = Join-Path $env:USERPROFILE 'AccessXI\logs\pol-monitor.log'
        NativeSpeechQueue = Join-Path $env:USERPROFILE 'AccessXI\logs\pol-reloaded-native-speech.queue'
    }
}

$summaryPath = Join-Path $InstallRoot 'install_summary.json'
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]$summary

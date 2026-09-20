param(
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'AccessXI'),
    [string]$PolExe = '',
    [string]$LegacyAccessXiConfigRoot = '',
    [Alias('SkipPolBootloader')]
    [switch]$SkipPolNativeDeployment,
    [switch]$SkipVisualCppRedistributables,
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

    # [System.IO.Path]::Combine instead of Join-Path: candidate paths are built before anything is
    # known to exist, and Join-Path fails outright on a drive letter that is not currently mounted
    # (for example a Steam library on a disconnected drive).
    $path = $Root
    foreach ($part in $Parts) {
        $path = [System.IO.Path]::Combine($path, $part)
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

function Get-PlayOnlineViewerRootsFromRegistry {
    # The PlayOnline installer records the viewer folder under InstallFolder\1000 whether it ran
    # from the Square Enix download or from the Steam depot, so this is the one probe that covers
    # both. FFXI is 32-bit, so the value normally lives in the WOW6432Node view.
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
        $baseKey = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        } catch {
            continue
        }

        try {
            foreach ($product in @('PlayOnlineUS', 'PlayOnlineEU', 'PlayOnlineJP', 'PlayOnline')) {
                $installFolderKey = $baseKey.OpenSubKey("SOFTWARE\$product\InstallFolder")
                if ($null -eq $installFolderKey) {
                    continue
                }

                try {
                    $viewerRoot = $installFolderKey.GetValue('1000')
                    if ($viewerRoot -is [string] -and -not [string]::IsNullOrWhiteSpace($viewerRoot)) {
                        $viewerRoot.Trim()
                    }
                } finally {
                    $installFolderKey.Dispose()
                }
            }
        } finally {
            $baseKey.Dispose()
        }
    }
}

function Get-SteamInstallRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    $currentUserKey = $null
    try {
        $currentUserKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Valve\Steam')
        if ($null -ne $currentUserKey) {
            $steamPath = $currentUserKey.GetValue('SteamPath')
            if ($steamPath -is [string] -and -not [string]::IsNullOrWhiteSpace($steamPath)) {
                # HKCU stores the Steam path with forward slashes.
                $roots.Add($steamPath.Trim().Replace('/', '\'))
            }
        }
    } catch {
    } finally {
        if ($null -ne $currentUserKey) {
            $currentUserKey.Dispose()
        }
    }

    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry32, [Microsoft.Win32.RegistryView]::Registry64)) {
        $baseKey = $null
        try {
            $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        } catch {
            continue
        }

        try {
            $steamKey = $baseKey.OpenSubKey('SOFTWARE\Valve\Steam')
            if ($null -ne $steamKey) {
                try {
                    $installPath = $steamKey.GetValue('InstallPath')
                    if ($installPath -is [string] -and -not [string]::IsNullOrWhiteSpace($installPath)) {
                        $roots.Add($installPath.Trim().Replace('/', '\'))
                    }
                } finally {
                    $steamKey.Dispose()
                }
            }
        } finally {
            $baseKey.Dispose()
        }
    }

    foreach ($programFilesRoot in Get-DefaultProgramFilesRoots) {
        $roots.Add((Join-PathParts -Root $programFilesRoot -Parts @('Steam')))
    }

    return $roots.ToArray()
}

function Get-SteamLibraryRootsFromVdf {
    param([string]$LibraryFoldersVdf)

    $roots = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($LibraryFoldersVdf)) {
        return $roots.ToArray()
    }

    $seen = @{}
    foreach ($match in [regex]::Matches($LibraryFoldersVdf, '"path"\s*"([^"]*)"', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
        # Steam escapes path separators inside VDF, so "D:\\Games" means D:\Games.
        $libraryRoot = $match.Groups[1].Value.Replace('\\', '\').Trim()
        if ($libraryRoot -eq '') {
            continue
        }

        $key = $libraryRoot.TrimEnd('\').ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $roots.Add($libraryRoot)
        }
    }

    return $roots.ToArray()
}

function Get-SteamLibraryRoots {
    param([string[]]$SteamInstallRoots = @())

    $roots = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($steamRoot in $SteamInstallRoots) {
        if ([string]::IsNullOrWhiteSpace($steamRoot)) {
            continue
        }

        $key = $steamRoot.TrimEnd('\').ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $roots.Add($steamRoot)
        }

        $libraryFoldersPath = Join-PathParts -Root $steamRoot -Parts @('steamapps', 'libraryfolders.vdf')
        if (-not (Test-Path -LiteralPath $libraryFoldersPath -PathType Leaf)) {
            continue
        }

        try {
            $libraryFoldersVdf = Get-Content -LiteralPath $libraryFoldersPath -Raw
        } catch {
            continue
        }

        foreach ($libraryRoot in (Get-SteamLibraryRootsFromVdf -LibraryFoldersVdf $libraryFoldersVdf)) {
            $libraryKey = $libraryRoot.TrimEnd('\').ToLowerInvariant()
            if (-not $seen.ContainsKey($libraryKey)) {
                $seen[$libraryKey] = $true
                $roots.Add($libraryRoot)
            }
        }
    }

    return $roots.ToArray()
}

function Get-DefaultPolExeCandidates {
    param(
        [string[]]$RegistryViewerRoots = @(),
        [string[]]$SteamLibraryRoots = @(),
        [string[]]$ProgramFilesRoots = @()
    )

    # Depot folder names Steam uses for the regional FFXI releases.
    $steamGameFolders = @('FFXINA', 'FFXIEU', 'FFXIJP')
    $programFilesRelativeCandidates = @(
        @('PlayOnline', 'SquareEnix', 'PlayOnlineViewer', 'pol.exe'),
        @('SquareEnix', 'PlayOnlineViewer', 'pol.exe')
    )

    $candidates = New-Object System.Collections.Generic.List[string]

    foreach ($viewerRoot in $RegistryViewerRoots) {
        if ([string]::IsNullOrWhiteSpace($viewerRoot)) {
            continue
        }
        $candidates.Add((Join-PathParts -Root $viewerRoot.Trim() -Parts @('pol.exe')))
    }

    foreach ($libraryRoot in $SteamLibraryRoots) {
        if ([string]::IsNullOrWhiteSpace($libraryRoot)) {
            continue
        }
        foreach ($gameFolder in $steamGameFolders) {
            $candidates.Add((Join-PathParts -Root $libraryRoot.Trim() -Parts @('steamapps', 'common', $gameFolder, 'SquareEnix', 'PlayOnlineViewer', 'pol.exe')))
        }
    }

    foreach ($programFilesRoot in $ProgramFilesRoots) {
        if ([string]::IsNullOrWhiteSpace($programFilesRoot)) {
            continue
        }
        foreach ($relativeCandidate in $programFilesRelativeCandidates) {
            $candidates.Add((Join-PathParts -Root $programFilesRoot.Trim() -Parts $relativeCandidate))
        }
    }

    $seen = @{}
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $candidates) {
        $key = $candidate.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $ordered.Add($candidate)
        }
    }

    return $ordered.ToArray()
}

function Get-SteamCommonPolExe {
    param([string[]]$SteamLibraryRoots = @())

    foreach ($libraryRoot in $SteamLibraryRoots) {
        if ([string]::IsNullOrWhiteSpace($libraryRoot)) {
            continue
        }

        $commonRoot = Join-PathParts -Root $libraryRoot.Trim() -Parts @('steamapps', 'common')
        if (-not (Test-Path -LiteralPath $commonRoot -PathType Container)) {
            continue
        }

        foreach ($gameFolder in (Get-ChildItem -LiteralPath $commonRoot -Directory -ErrorAction SilentlyContinue)) {
            $candidate = Join-PathParts -Root $gameFolder.FullName -Parts @('SquareEnix', 'PlayOnlineViewer', 'pol.exe')
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $candidate
            }
        }
    }
}

function Find-DefaultPolExe {
    param(
        [string[]]$RegistryViewerRoots,
        [string[]]$SteamLibraryRoots,
        [string[]]$ProgramFilesRoots
    )

    if ($null -eq $RegistryViewerRoots) {
        $RegistryViewerRoots = @(Get-PlayOnlineViewerRootsFromRegistry)
    }
    if ($null -eq $SteamLibraryRoots) {
        $SteamLibraryRoots = @(Get-SteamLibraryRoots -SteamInstallRoots (Get-SteamInstallRoots))
    }
    if ($null -eq $ProgramFilesRoots) {
        $ProgramFilesRoots = @(Get-DefaultProgramFilesRoots)
    }

    $candidates = Get-DefaultPolExeCandidates `
        -RegistryViewerRoots $RegistryViewerRoots `
        -SteamLibraryRoots $SteamLibraryRoots `
        -ProgramFilesRoots $ProgramFilesRoots
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    # Last resort for a Steam depot folder name we do not know about.
    foreach ($candidate in (Get-SteamCommonPolExe -SteamLibraryRoots $SteamLibraryRoots)) {
        return $candidate
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

function Backup-ExistingDirectory {
    param(
        [string]$Path,
        [string]$BackupRoot
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $item = Get-Item -LiteralPath $Path
    $destination = Join-Path $BackupRoot $item.Name
    if (Test-Path -LiteralPath $destination) {
        $destination = Join-Path $BackupRoot ($item.Name + '.previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    }
    Copy-Item -LiteralPath $Path -Destination $destination -Recurse -Force
}

function Assert-InstallerChildPath {
    param(
        [string]$Path,
        [string]$Parent,
        [string]$Description
    )

    $resolvedPath = (Resolve-FullPath $Path).TrimEnd('\')
    $resolvedParent = (Resolve-FullPath $Parent).TrimEnd('\')
    if ($resolvedPath -eq $resolvedParent -or
        -not $resolvedPath.StartsWith($resolvedParent + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Description escapes its intended parent: $resolvedPath"
    }
    return $resolvedPath
}

function Deploy-PolNative {
    param(
        [string]$PayloadRoot,
        [string]$PolExe,
        [string]$BackupRoot
    )

    $polDirectory = (Resolve-FullPath (Split-Path -Parent $PolExe)).TrimEnd('\')
    $scriptsDirectory = Join-Path $polDirectory 'scripts'
    $nativeSource = Join-Path $PayloadRoot 'PlayOnlineNative'
    $asiLoaderSource = Join-Path $nativeSource 'ddraw.dll'
    $nativeAsiSource = Join-Path $nativeSource 'AccessXI.PolNative.asi'
    $nativeHookSource = Join-Path $nativeSource 'AccessXI.PolNative\accessxi_pol_native.dll'
    $nativePrismSource = Join-Path $nativeSource 'AccessXI.PolNative\prism.dll'
    $appDll = Join-Path $polDirectory 'viewer\com\app.dll'

    foreach ($required in @($PolExe, $appDll, $asiLoaderSource, $nativeAsiSource, $nativeHookSource, $nativePrismSource)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required native PlayOnline deployment file is missing: $required"
        }
    }

    $polHashBefore = (Get-FileHash -LiteralPath $PolExe -Algorithm SHA256).Hash
    $appHashBefore = (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash
    $nativeAsiDestination = Assert-InstallerChildPath `
        -Path (Join-Path $scriptsDirectory 'AccessXI.PolNative.asi') `
        -Parent $scriptsDirectory `
        -Description 'Native PlayOnline ASI destination'
    $nativeDependencyDestination = Assert-InstallerChildPath `
        -Path (Join-Path $scriptsDirectory 'AccessXI.PolNative') `
        -Parent $scriptsDirectory `
        -Description 'Native PlayOnline dependency destination'

    Copy-WithBackup -Source $asiLoaderSource -Destination (Join-Path $polDirectory 'ddraw.dll') -BackupRoot $BackupRoot
    Copy-WithBackup -Source $nativeAsiSource -Destination $nativeAsiDestination -BackupRoot $BackupRoot
    if (Test-Path -LiteralPath $nativeDependencyDestination -PathType Container) {
        Backup-ExistingDirectory -Path $nativeDependencyDestination -BackupRoot $BackupRoot
        Remove-Item -LiteralPath $nativeDependencyDestination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $nativeDependencyDestination | Out-Null
    Copy-Item -LiteralPath $nativeHookSource -Destination (Join-Path $nativeDependencyDestination 'accessxi_pol_native.dll') -Force
    Copy-Item -LiteralPath $nativePrismSource -Destination (Join-Path $nativeDependencyDestination 'prism.dll') -Force
    Remove-WithBackup -Path (Join-Path $scriptsDirectory 'AccessXI.PolAsiProbe.asi') -BackupRoot $BackupRoot

    if ((Get-FileHash -LiteralPath $PolExe -Algorithm SHA256).Hash -ne $polHashBefore -or
        (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash -ne $appHashBefore) {
        throw 'Native PlayOnline deployment changed a Square Enix binary.'
    }

    return [pscustomobject]([ordered]@{
        AsiLoader = Join-Path $polDirectory 'ddraw.dll'
        NativeAsi = $nativeAsiDestination
        NativeHook = Join-Path $nativeDependencyDestination 'accessxi_pol_native.dll'
        NativePrism = Join-Path $nativeDependencyDestination 'prism.dll'
        PolSha256 = $polHashBefore
        AppSha256 = $appHashBefore
    })
}

function Assert-PlayOnlineClosed {
    $running = @(Get-Process -Name 'pol' -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw 'Close PlayOnline Viewer before installing AccessXI so the old loader can be removed and the native accessibility files can be replaced safely.'
    }
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
$nativeSource = Join-Path $payloadRoot 'PlayOnlineNative'
$prerequisitesSource = Join-Path $payloadRoot 'Prerequisites'
$legacyCleanupSource = Join-Path $scriptRoot 'legacy_accessxi_cleanup.ps1'
$packageManifestPath = Join-Path $scriptRoot 'manifest.json'
$packageManifest = $null
if (Test-Path -LiteralPath $packageManifestPath) {
    $packageManifest = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
}
if (-not (Test-Path -LiteralPath $legacyCleanupSource -PathType Leaf)) {
    throw "Legacy AccessXI cleanup library is missing from installer payload: $legacyCleanupSource"
}
. $legacyCleanupSource

if ($PolExe -eq '') {
    $PolExe = Find-DefaultPolExe
}
if ($PolExe -eq '' -or -not (Test-Path -LiteralPath $PolExe)) {
    throw 'PlayOnline Viewer pol.exe was not found. Re-run with -PolExe "C:\Path\To\PlayOnlineViewer\pol.exe".'
}

$InstallRoot = Resolve-FullPath $InstallRoot
$ashitaDest = Join-Path $InstallRoot 'Ashita'
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
foreach ($requiredNativePath in @(
    (Join-Path $nativeSource 'ddraw.dll'),
    (Join-Path $nativeSource 'AccessXI.PolNative.asi'),
    (Join-Path $nativeSource 'AccessXI.PolNative\accessxi_pol_native.dll'),
    (Join-Path $nativeSource 'AccessXI.PolNative\prism.dll')
)) {
    if (-not (Test-Path -LiteralPath $requiredNativePath -PathType Leaf)) {
        throw "Native PlayOnline accessibility payload is missing: $requiredNativePath"
    }
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

Copy-PayloadDirectory -Source $ashitaSource -Destination $ashitaDest
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
Copy-Item -LiteralPath $setupGuideSource -Destination (Join-Path $InstallRoot 'setup-guide.md') -Force
$ffxiInstallRoot = Set-AshitaCliFfxiInstallPath -AshitaRoot $ashitaDest -PolExe $PolExe
Disable-OldAshitaPolPlugin -AshitaRoot $ashitaDest

Assert-PlayOnlineClosed
$legacyAccessXiCleanup = Remove-LegacyAccessXiInstall `
    -InstallRoot $InstallRoot `
    -PolExe $PolExe `
    -LegacyAccessXiConfigRoot $LegacyAccessXiConfigRoot `
    -BackupRoot $backupRoot
$polUrlFilesRepaired = @()
$nativeDeployment = $null

if (-not $SkipPolNativeDeployment) {
    $polUrlFilesRepaired = Repair-PolUrlFiles -PolExe $PolExe
    $nativeDeployment = Deploy-PolNative `
        -PayloadRoot $payloadRoot `
        -PolExe $PolExe `
        -BackupRoot $backupRoot
}

$shortcutPath = ''
if (-not $NoDesktopShortcut) {
    $shortcutPath = New-AshitaShortcut -AshitaRoot $ashitaDest
}

$deployedHashes = [ordered]@{}
if (-not $SkipPolNativeDeployment) {
    $deployedHashes['PolAsiLoader'] = Assert-DeployedFileHash `
        -Name 'PolAsiLoader' `
        -Source (Join-Path $nativeSource 'ddraw.dll') `
        -Destination $nativeDeployment.AsiLoader
    $deployedHashes['PolNativeAsi'] = Assert-DeployedFileHash `
        -Name 'PolNativeAsi' `
        -Source (Join-Path $nativeSource 'AccessXI.PolNative.asi') `
        -Destination $nativeDeployment.NativeAsi
    $deployedHashes['PolNativeHook'] = Assert-DeployedFileHash `
        -Name 'PolNativeHook' `
        -Source (Join-Path $nativeSource 'AccessXI.PolNative\accessxi_pol_native.dll') `
        -Destination $nativeDeployment.NativeHook
    $deployedHashes['PolNativePrism'] = Assert-DeployedFileHash `
        -Name 'PolNativePrism' `
        -Source (Join-Path $nativeSource 'AccessXI.PolNative\prism.dll') `
        -Destination $nativeDeployment.NativePrism
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
    PolExe = $PolExe
    FfxiInstallRoot = $ffxiInstallRoot
    LegacyAccessXiCleanup = $legacyAccessXiCleanup
    PolNativeDeployed = (-not $SkipPolNativeDeployment)
    PolNativeDeployment = $nativeDeployment
    PolUrlFilesRepaired = $polUrlFilesRepaired
    VisualCppRedistributables = $visualCppRedistributables
    Shortcut = $shortcutPath
    BackupRoot = $backupRoot
    PackageManifestCreatedAt = if ($null -ne $packageManifest) { $packageManifest.CreatedAt } else { '' }
    PackagePolAsiLoaderHash = if ($null -ne $packageManifest) { $packageManifest.PolAsiLoaderHash } else { '' }
    PackagePolNativeAsiHash = if ($null -ne $packageManifest) { $packageManifest.PolNativeAsiHash } else { '' }
    PackagePolNativeHookHash = if ($null -ne $packageManifest) { $packageManifest.PolNativeHookHash } else { '' }
    PackagePolNativePrismHash = if ($null -ne $packageManifest) { $packageManifest.PolNativePrismHash } else { '' }
    DeployedHashes = $deployedHashes
    DiagnosticLogDirectory = Join-Path $env:USERPROFILE 'AccessXI\logs'
    DiagnosticLogs = [ordered]@{
        NativeStartup = Join-Path $env:USERPROFILE 'AccessXI\logs\pol-native-startup.log'
        NativeSpeech = Join-Path $env:USERPROFILE 'AccessXI\logs\pol-native-speech.log'
    }
}

$summaryPath = Join-Path $InstallRoot 'install_summary.json'
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

[pscustomobject]$summary

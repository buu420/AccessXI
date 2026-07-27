$ErrorActionPreference = 'Stop'

function Resolve-AccessXiCleanupPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Cleanup path must not be empty.'
    }
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-AccessXiCleanupChildPath {
    param(
        [string]$Path,
        [string]$Parent
    )

    $resolvedPath = Resolve-AccessXiCleanupPath $Path
    $resolvedParent = Resolve-AccessXiCleanupPath $Parent
    return $resolvedPath.StartsWith(
        $resolvedParent + '\',
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-AccessXiCleanupChildPath {
    param(
        [string]$Path,
        [string]$Parent,
        [string]$Description
    )

    $resolvedPath = Resolve-AccessXiCleanupPath $Path
    if (-not (Test-AccessXiCleanupChildPath -Path $resolvedPath -Parent $Parent)) {
        throw "$Description escapes its intended parent: $resolvedPath"
    }
    return $resolvedPath
}

function Backup-AccessXiLegacyFile {
    param(
        [string]$Path,
        [string]$BackupRoot,
        [System.Collections.Generic.List[string]]$BackupPaths
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    $resolvedBackupRoot = Resolve-AccessXiCleanupPath $BackupRoot
    $filesRoot = Join-Path $resolvedBackupRoot 'legacy-reloaded'
    New-Item -ItemType Directory -Force -Path $filesRoot | Out-Null
    $leaf = [System.IO.Path]::GetFileName($Path)
    $backupName = '{0:D3}-{1}-{2}' -f ($BackupPaths.Count + 1), ([Guid]::NewGuid().ToString('N').Substring(0, 8)), $leaf
    $destination = Assert-AccessXiCleanupChildPath `
        -Path (Join-Path $filesRoot $backupName) `
        -Parent $resolvedBackupRoot `
        -Description 'Legacy backup destination'
    Copy-Item -LiteralPath $Path -Destination $destination -Force
    $BackupPaths.Add($destination)
    return $destination
}

function Remove-AccessXiLegacyFile {
    param(
        [string]$Path,
        [string]$BackupRoot,
        [System.Collections.Generic.List[string]]$RemovedPaths,
        [System.Collections.Generic.List[string]]$BackupPaths
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $null = Backup-AccessXiLegacyFile -Path $Path -BackupRoot $BackupRoot -BackupPaths $BackupPaths
    Remove-Item -LiteralPath $Path -Force
    $RemovedPaths.Add((Resolve-AccessXiCleanupPath $Path))
}

function Test-AccessXiReloadedConfigTargetsRoot {
    param(
        [string]$ConfigPath,
        [string]$ReloadedRoot
    )

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $false
    }

    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    }
    catch {
        return $false
    }

    foreach ($propertyName in @(
        'LoaderPath32',
        'LoaderPath64',
        'LauncherPath',
        'Bootstrapper32Path',
        'Bootstrapper64Path',
        'ApplicationConfigDirectory',
        'ModUserConfigDirectory',
        'MiscConfigDirectory',
        'PluginConfigDirectory',
        'ModConfigDirectory'
    )) {
        $value = $config.$propertyName
        if ([string]::IsNullOrWhiteSpace([string]$value)) {
            return $false
        }
        try {
            if (-not (Test-AccessXiCleanupChildPath -Path ([string]$value) -Parent $ReloadedRoot)) {
                return $false
            }
        }
        catch {
            return $false
        }
    }

    return $true
}

function Remove-AccessXiLegacyMarkerDirectory {
    param(
        [string]$Path,
        [string]$ReloadedRoot,
        [System.Collections.Generic.List[string]]$RemovedPaths
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    $resolved = Assert-AccessXiCleanupChildPath `
        -Path $Path `
        -Parent $ReloadedRoot `
        -Description 'Legacy AccessXI marker directory'
    Remove-Item -LiteralPath $resolved -Recurse -Force
    $RemovedPaths.Add($resolved)
}

function Remove-LegacyAccessXiReloaded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallRoot,
        [Parameter(Mandatory = $true)]
        [string]$PolExe,
        [string]$ReloadedConfigRoot = '',
        [Parameter(Mandatory = $true)]
        [string]$BackupRoot
    )

    $resolvedInstallRoot = Resolve-AccessXiCleanupPath $InstallRoot
    $resolvedPolExe = Resolve-AccessXiCleanupPath $PolExe
    $polDirectory = Resolve-AccessXiCleanupPath (Split-Path -Parent $resolvedPolExe)
    $scriptsDirectory = Join-Path $polDirectory 'scripts'
    $reloadedRoot = Assert-AccessXiCleanupChildPath `
        -Path (Join-Path $resolvedInstallRoot 'Reloaded-II') `
        -Parent $resolvedInstallRoot `
        -Description 'Legacy Reloaded root'
    $modMarker = Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded'
    $appMarker = Join-Path $reloadedRoot 'Apps\AccessXI.PolPreLogin'
    $hasModMarker = Test-Path -LiteralPath $modMarker -PathType Container
    $hasAppMarker = Test-Path -LiteralPath $appMarker -PathType Container

    $legacyPolPaths = @(
        (Join-Path $scriptsDirectory 'AccessXI.PolReloadedBootstrap.asi'),
        (Join-Path $scriptsDirectory 'AccessXI.PolReloadedBootstrap.asi.disabled'),
        (Join-Path $scriptsDirectory 'Reloaded.Mod.Loader.Bootstrapper.dll'),
        (Join-Path $scriptsDirectory 'Reloaded.Mod.Loader.Bootstrapper.asi'),
        (Join-Path $scriptsDirectory 'Reloaded.Mod.Loader.Bootstrapper.asi.direct-disabled'),
        (Join-Path $scriptsDirectory 'ReloadedPortable.txt')
    )
    $hasAccessXiPolMarker =
        (Test-Path -LiteralPath $legacyPolPaths[0] -PathType Leaf) -or
        (Test-Path -LiteralPath $legacyPolPaths[1] -PathType Leaf)
    $detected = $hasModMarker -or $hasAppMarker -or $hasAccessXiPolMarker

    $removedPaths = New-Object 'System.Collections.Generic.List[string]'
    $preservedPaths = New-Object 'System.Collections.Generic.List[string]'
    $backupPaths = New-Object 'System.Collections.Generic.List[string]'
    $configRemoved = $false
    $fullReloadedRootRemoved = $false

    if ([string]::IsNullOrWhiteSpace($ReloadedConfigRoot)) {
        $ReloadedConfigRoot = Join-Path $env:APPDATA 'Reloaded-Mod-Loader-II'
    }
    $configRoot = Resolve-AccessXiCleanupPath $ReloadedConfigRoot
    $configPath = Join-Path $configRoot 'ReloadedII.json'

    if (-not $detected) {
        if (Test-Path -LiteralPath $reloadedRoot) {
            $preservedPaths.Add($reloadedRoot)
        }
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            $preservedPaths.Add((Resolve-AccessXiCleanupPath $configPath))
        }
        return [pscustomobject]([ordered]@{
            Detected = $false
            RemovedPaths = @($removedPaths)
            PreservedPaths = @($preservedPaths)
            BackupPaths = @($backupPaths)
            ConfigRemoved = $false
            FullReloadedRootRemoved = $false
        })
    }

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        if (Test-AccessXiReloadedConfigTargetsRoot -ConfigPath $configPath -ReloadedRoot $reloadedRoot) {
            Remove-AccessXiLegacyFile `
                -Path $configPath `
                -BackupRoot $BackupRoot `
                -RemovedPaths $removedPaths `
                -BackupPaths $backupPaths
            $configRemoved = $true
        }
        else {
            $preservedPaths.Add((Resolve-AccessXiCleanupPath $configPath))
        }
    }

    foreach ($legacyPath in $legacyPolPaths) {
        $resolvedLegacyPath = Assert-AccessXiCleanupChildPath `
            -Path $legacyPath `
            -Parent $scriptsDirectory `
            -Description 'Legacy POL script file'
        Remove-AccessXiLegacyFile `
            -Path $resolvedLegacyPath `
            -BackupRoot $BackupRoot `
            -RemovedPaths $removedPaths `
            -BackupPaths $backupPaths
    }

    if ($hasModMarker -and $hasAppMarker) {
        $expectedReloadedRoot = Resolve-AccessXiCleanupPath (Join-Path $resolvedInstallRoot 'Reloaded-II')
        if ($reloadedRoot -ine $expectedReloadedRoot) {
            throw "Legacy Reloaded root changed unexpectedly: $reloadedRoot"
        }
        if (Test-Path -LiteralPath $reloadedRoot -PathType Container) {
            Remove-Item -LiteralPath $reloadedRoot -Recurse -Force
            $removedPaths.Add($reloadedRoot)
            $fullReloadedRootRemoved = $true
        }
    }
    else {
        if ($hasModMarker) {
            Remove-AccessXiLegacyMarkerDirectory `
                -Path $modMarker `
                -ReloadedRoot $reloadedRoot `
                -RemovedPaths $removedPaths
        }
        if ($hasAppMarker) {
            Remove-AccessXiLegacyMarkerDirectory `
                -Path $appMarker `
                -ReloadedRoot $reloadedRoot `
                -RemovedPaths $removedPaths
        }
        if (Test-Path -LiteralPath $reloadedRoot -PathType Container) {
            $preservedPaths.Add($reloadedRoot)
        }
    }

    return [pscustomobject]([ordered]@{
        Detected = [bool]$detected
        RemovedPaths = @($removedPaths)
        PreservedPaths = @($preservedPaths)
        BackupPaths = @($backupPaths)
        ConfigRemoved = [bool]$configRemoved
        FullReloadedRootRemoved = [bool]$fullReloadedRootRemoved
    })
}

param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

$cleanupScript = Join-Path $RepoRoot 'installer\legacy_reloaded_cleanup.ps1'
if (-not (Test-Path -LiteralPath $cleanupScript -PathType Leaf)) {
    throw "Legacy Reloaded cleanup library is missing: $cleanupScript"
}
. $cleanupScript

if (-not (Get-Command Remove-LegacyAccessXiReloaded -ErrorAction SilentlyContinue)) {
    throw 'Legacy Reloaded cleanup library must export Remove-LegacyAccessXiReloaded.'
}

$testRoot = Join-Path $env:TEMP "accessxi-legacy-reloaded-cleanup-$PID"
if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

function New-FakePolTree {
    param([string]$Name)

    $root = Join-Path $testRoot $Name
    $scripts = Join-Path $root 'scripts'
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'viewer\com'), $scripts | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $root 'pol.exe'), "pol-$Name")
    [System.IO.File]::WriteAllText((Join-Path $root 'viewer\com\app.dll'), "app-$Name")
    [System.IO.File]::WriteAllText((Join-Path $root 'ddraw.dll'), 'keep-native-asi-loader')
    [System.IO.File]::WriteAllText((Join-Path $scripts 'AccessXI.PolNative.asi'), 'keep-native-asi')
    New-Item -ItemType Directory -Force -Path (Join-Path $scripts 'AccessXI.PolNative') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $scripts 'AccessXI.PolNative\prism.dll'), 'keep-native-prism')
    [System.IO.File]::WriteAllText((Join-Path $scripts 'OtherAccessibilityMod.asi'), 'keep-unrelated-asi')
    return $root
}

function Add-LegacyPolFiles {
    param([string]$PolRoot)

    $scripts = Join-Path $PolRoot 'scripts'
    foreach ($name in @(
        'AccessXI.PolReloadedBootstrap.asi',
        'AccessXI.PolReloadedBootstrap.asi.disabled',
        'Reloaded.Mod.Loader.Bootstrapper.dll',
        'Reloaded.Mod.Loader.Bootstrapper.asi',
        'Reloaded.Mod.Loader.Bootstrapper.asi.direct-disabled',
        'ReloadedPortable.txt'
    )) {
        [System.IO.File]::WriteAllText((Join-Path $scripts $name), "legacy-$name")
    }
}

function New-OwnedReloadedRoot {
    param([string]$InstallRoot)

    $reloadedRoot = Join-Path $InstallRoot 'Reloaded-II'
    New-Item -ItemType Directory -Force -Path `
        (Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded'), `
        (Join-Path $reloadedRoot 'Apps\AccessXI.PolPreLogin') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $reloadedRoot 'Reloaded-II.exe'), 'legacy-reloaded')
    [System.IO.File]::WriteAllText((Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll'), 'legacy-mod')
    [System.IO.File]::WriteAllText((Join-Path $reloadedRoot 'Apps\AccessXI.PolPreLogin\AppConfig.json'), '{}')
    return $reloadedRoot
}

function Write-TargetedReloadedConfig {
    param([string]$ConfigRoot, [string]$ReloadedRoot)

    New-Item -ItemType Directory -Force -Path $ConfigRoot | Out-Null
    [ordered]@{
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
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $ConfigRoot 'ReloadedII.json') -Encoding UTF8
}

try {
    $ownedInstallRoot = Join-Path $testRoot 'owned-install'
    $ownedPolRoot = New-FakePolTree 'owned-pol'
    $ownedPolExe = Join-Path $ownedPolRoot 'pol.exe'
    $ownedReloadedRoot = New-OwnedReloadedRoot $ownedInstallRoot
    $ownedConfigRoot = Join-Path $testRoot 'owned-config'
    $ownedBackupRoot = Join-Path $testRoot 'owned-backup'
    Write-TargetedReloadedConfig -ConfigRoot $ownedConfigRoot -ReloadedRoot $ownedReloadedRoot
    Add-LegacyPolFiles -PolRoot $ownedPolRoot

    $ownedPolHash = (Get-FileHash -LiteralPath $ownedPolExe -Algorithm SHA256).Hash
    $ownedAppHash = (Get-FileHash -LiteralPath (Join-Path $ownedPolRoot 'viewer\com\app.dll') -Algorithm SHA256).Hash
    $ownedResult = Remove-LegacyAccessXiReloaded `
        -InstallRoot $ownedInstallRoot `
        -PolExe $ownedPolExe `
        -ReloadedConfigRoot $ownedConfigRoot `
        -BackupRoot $ownedBackupRoot

    Assert-True $ownedResult.Detected 'Owned AccessXI Reloaded installation was not detected.'
    Assert-True (-not (Test-Path -LiteralPath $ownedReloadedRoot)) 'Owned AccessXI Reloaded directory was not removed.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $ownedConfigRoot 'ReloadedII.json'))) 'Owned Reloaded loader config was not removed.'
    foreach ($name in @(
        'AccessXI.PolReloadedBootstrap.asi',
        'AccessXI.PolReloadedBootstrap.asi.disabled',
        'Reloaded.Mod.Loader.Bootstrapper.dll',
        'Reloaded.Mod.Loader.Bootstrapper.asi',
        'Reloaded.Mod.Loader.Bootstrapper.asi.direct-disabled',
        'ReloadedPortable.txt'
    )) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $ownedPolRoot "scripts\$name"))) "Legacy POL file survived cleanup: $name"
    }
    Assert-Equal (Get-Content -LiteralPath (Join-Path $ownedPolRoot 'ddraw.dll') -Raw) 'keep-native-asi-loader' 'Cleanup changed the required native ASI loader.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $ownedPolRoot 'scripts\AccessXI.PolNative.asi') -Raw) 'keep-native-asi' 'Cleanup changed the native AccessXI ASI.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $ownedPolRoot 'scripts\OtherAccessibilityMod.asi') -Raw) 'keep-unrelated-asi' 'Cleanup changed an unrelated ASI.'
    Assert-Equal (Get-FileHash -LiteralPath $ownedPolExe -Algorithm SHA256).Hash $ownedPolHash 'Cleanup changed pol.exe.'
    Assert-Equal (Get-FileHash -LiteralPath (Join-Path $ownedPolRoot 'viewer\com\app.dll') -Algorithm SHA256).Hash $ownedAppHash 'Cleanup changed app.dll.'
    Assert-True $ownedResult.ConfigRemoved 'Cleanup result did not record removal of the owned Reloaded config.'
    Assert-True (@($ownedResult.RemovedPaths).Count -ge 8) 'Cleanup result did not report the removed legacy artifacts.'
    Assert-True (@(Get-ChildItem -LiteralPath $ownedBackupRoot -Recurse -File).Count -ge 7) 'Cleanup did not back up the global config and POL-side legacy files.'

    $secondResult = Remove-LegacyAccessXiReloaded `
        -InstallRoot $ownedInstallRoot `
        -PolExe $ownedPolExe `
        -ReloadedConfigRoot $ownedConfigRoot `
        -BackupRoot (Join-Path $testRoot 'second-backup')
    Assert-True (-not $secondResult.Detected) 'A second cleanup falsely detected an already-removed legacy installation.'
    Assert-True (@($secondResult.RemovedPaths).Count -eq 0) 'A second cleanup reported removals that did not occur.'

    $partialInstallRoot = Join-Path $testRoot 'partial-install'
    $partialReloadedRoot = Join-Path $partialInstallRoot 'Reloaded-II'
    New-Item -ItemType Directory -Force -Path `
        (Join-Path $partialReloadedRoot 'Mods\AccessXI.PolReloaded'), `
        (Join-Path $partialReloadedRoot 'Mods\Unrelated.Mod') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $partialReloadedRoot 'Mods\AccessXI.PolReloaded\old.dll'), 'old')
    [System.IO.File]::WriteAllText((Join-Path $partialReloadedRoot 'Mods\Unrelated.Mod\keep.dll'), 'keep')
    $partialPolRoot = New-FakePolTree 'partial-pol'
    Add-LegacyPolFiles -PolRoot $partialPolRoot
    $partialResult = Remove-LegacyAccessXiReloaded `
        -InstallRoot $partialInstallRoot `
        -PolExe (Join-Path $partialPolRoot 'pol.exe') `
        -ReloadedConfigRoot (Join-Path $testRoot 'partial-config') `
        -BackupRoot (Join-Path $testRoot 'partial-backup')
    Assert-True $partialResult.Detected 'A partial AccessXI legacy marker was not detected.'
    Assert-True (Test-Path -LiteralPath $partialReloadedRoot) 'Partial ownership caused the entire Reloaded root to be deleted.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $partialReloadedRoot 'Mods\AccessXI.PolReloaded'))) 'Exact partial AccessXI mod marker was not removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $partialReloadedRoot 'Mods\Unrelated.Mod\keep.dll')) 'Partial cleanup removed an unrelated Reloaded mod.'

    $unrelatedInstallRoot = Join-Path $testRoot 'unrelated-install'
    $unrelatedReloadedRoot = Join-Path $unrelatedInstallRoot 'Reloaded-II'
    New-Item -ItemType Directory -Force -Path (Join-Path $unrelatedReloadedRoot 'Mods\Unrelated.Mod') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $unrelatedReloadedRoot 'Mods\Unrelated.Mod\keep.dll'), 'keep')
    $unrelatedPolRoot = New-FakePolTree 'unrelated-pol'
    [System.IO.File]::WriteAllText((Join-Path $unrelatedPolRoot 'scripts\Reloaded.Mod.Loader.Bootstrapper.dll'), 'unrelated-loader')
    $unrelatedConfigRoot = Join-Path $testRoot 'unrelated-config'
    Write-TargetedReloadedConfig -ConfigRoot $unrelatedConfigRoot -ReloadedRoot $unrelatedReloadedRoot
    $unrelatedResult = Remove-LegacyAccessXiReloaded `
        -InstallRoot $unrelatedInstallRoot `
        -PolExe (Join-Path $unrelatedPolRoot 'pol.exe') `
        -ReloadedConfigRoot $unrelatedConfigRoot `
        -BackupRoot (Join-Path $testRoot 'unrelated-backup')
    Assert-True (-not $unrelatedResult.Detected) 'Unrelated Reloaded installation was falsely classified as AccessXI-owned.'
    Assert-True (Test-Path -LiteralPath $unrelatedReloadedRoot) 'Unrelated Reloaded installation was removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $unrelatedConfigRoot 'ReloadedII.json')) 'Unrelated Reloaded config was removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $unrelatedPolRoot 'scripts\Reloaded.Mod.Loader.Bootstrapper.dll')) 'Generic Reloaded bootstrapper was removed without an AccessXI marker.'

    $mismatchInstallRoot = Join-Path $testRoot 'mismatch-install'
    $mismatchReloadedRoot = New-OwnedReloadedRoot $mismatchInstallRoot
    $mismatchPolRoot = New-FakePolTree 'mismatch-pol'
    Add-LegacyPolFiles -PolRoot $mismatchPolRoot
    $mismatchConfigRoot = Join-Path $testRoot 'mismatch-config'
    Write-TargetedReloadedConfig -ConfigRoot $mismatchConfigRoot -ReloadedRoot (Join-Path $testRoot 'different-reloaded-root')
    $mismatchResult = Remove-LegacyAccessXiReloaded `
        -InstallRoot $mismatchInstallRoot `
        -PolExe (Join-Path $mismatchPolRoot 'pol.exe') `
        -ReloadedConfigRoot $mismatchConfigRoot `
        -BackupRoot (Join-Path $testRoot 'mismatch-backup')
    Assert-True $mismatchResult.Detected 'Owned root with mismatched config was not detected.'
    Assert-True (-not (Test-Path -LiteralPath $mismatchReloadedRoot)) 'Owned root with mismatched config was not removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $mismatchConfigRoot 'ReloadedII.json')) 'Mismatched Reloaded config was removed.'
    Assert-True (-not $mismatchResult.ConfigRemoved) 'Cleanup result falsely reported removal of a mismatched config.'

    $malformedInstallRoot = Join-Path $testRoot 'malformed-install'
    $null = New-OwnedReloadedRoot $malformedInstallRoot
    $malformedPolRoot = New-FakePolTree 'malformed-pol'
    Add-LegacyPolFiles -PolRoot $malformedPolRoot
    $malformedConfigRoot = Join-Path $testRoot 'malformed-config'
    New-Item -ItemType Directory -Force -Path $malformedConfigRoot | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $malformedConfigRoot 'ReloadedII.json'), '{not valid json')
    $malformedResult = Remove-LegacyAccessXiReloaded `
        -InstallRoot $malformedInstallRoot `
        -PolExe (Join-Path $malformedPolRoot 'pol.exe') `
        -ReloadedConfigRoot $malformedConfigRoot `
        -BackupRoot (Join-Path $testRoot 'malformed-backup')
    Assert-True $malformedResult.Detected 'Owned root with malformed config was not detected.'
    Assert-True (Test-Path -LiteralPath (Join-Path $malformedConfigRoot 'ReloadedII.json')) 'Malformed Reloaded config was removed without proof of ownership.'
    Assert-True (@($malformedResult.PreservedPaths) -contains (Join-Path $malformedConfigRoot 'ReloadedII.json')) 'Malformed config preservation was not reported.'

    'ok: legacy AccessXI Reloaded cleanup removes owned artifacts, preserves ambiguous and unrelated state, and is idempotent.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

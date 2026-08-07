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

function Write-TestFile {
    param([string]$Path, [string]$Content)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [System.IO.File]::WriteAllText($Path, $Content)
}

$sourceInstaller = Join-Path $RepoRoot 'installer\install_accessxi.ps1'
$sourceCleanup = Join-Path $RepoRoot 'installer\legacy_accessxi_cleanup.ps1'
Assert-True (Test-Path -LiteralPath $sourceInstaller -PathType Leaf) "Installer source is missing: $sourceInstaller"
Assert-True (Test-Path -LiteralPath $sourceCleanup -PathType Leaf) "Cleanup source is missing: $sourceCleanup"

$testRoot = Join-Path $env:TEMP "accessxi-installer-native-migration-$PID"
$resolvedTemp = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
$resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot).TrimEnd('\')
if (-not $resolvedTestRoot.StartsWith($resolvedTemp + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use test root outside TEMP: $resolvedTestRoot"
}
if (Test-Path -LiteralPath $resolvedTestRoot) {
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

try {
    $packageRoot = Join-Path $resolvedTestRoot 'package'
    $payloadRoot = Join-Path $packageRoot 'payload'
    $payloadAshita = Join-Path $payloadRoot 'Ashita'
    $payloadNative = Join-Path $payloadRoot 'PlayOnlineNative'
    $installRoot = Join-Path $resolvedTestRoot 'installed'
    $polRoot = Join-Path $resolvedTestRoot 'PlayOnlineViewer'
    $polExe = Join-Path $polRoot 'pol.exe'
    $appDll = Join-Path $polRoot 'viewer\com\app.dll'
    $scriptsRoot = Join-Path $polRoot 'scripts'
    $configRoot = Join-Path $resolvedTestRoot 'roaming\Reloaded-Mod-Loader-II'

    New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
    Copy-Item -LiteralPath $sourceInstaller -Destination (Join-Path $packageRoot 'install_accessxi.ps1') -Force
    Copy-Item -LiteralPath $sourceCleanup -Destination (Join-Path $packageRoot 'legacy_accessxi_cleanup.ps1') -Force
    Write-TestFile -Path (Join-Path $packageRoot 'setup-guide.md') -Content 'test setup guide'
    Write-TestFile -Path (Join-Path $payloadAshita 'Ashita-cli.exe') -Content 'ashita-cli'
    Write-TestFile -Path (Join-Path $payloadAshita 'AccessXI.cmd') -Content 'launcher'
    Write-TestFile -Path (Join-Path $payloadAshita 'config\boot\accessxi-retail.ini') -Content "command = /game eAZcFcB`r`n0042 =`r`n"
    Write-TestFile -Path (Join-Path $payloadAshita 'addons\accessxi_reader\accessxi_reader.lua') -Content 'return true'
    Write-TestFile -Path (Join-Path $payloadRoot 'Prerequisites\vc_redist.x86.exe') -Content 'x86'
    Write-TestFile -Path (Join-Path $payloadRoot 'Prerequisites\vc_redist.x64.exe') -Content 'x64'
    Write-TestFile -Path (Join-Path $payloadNative 'ddraw.dll') -Content 'new-asi-loader'
    Write-TestFile -Path (Join-Path $payloadNative 'AccessXI.PolNative.asi') -Content 'new-native-asi'
    Write-TestFile -Path (Join-Path $payloadNative 'AccessXI.PolNative\accessxi_pol_native.dll') -Content 'new-native-hook'
    Write-TestFile -Path (Join-Path $payloadNative 'AccessXI.PolNative\prism.dll') -Content 'new-native-prism'

    Write-TestFile -Path $polExe -Content 'square-enix-pol'
    Write-TestFile -Path $appDll -Content 'square-enix-app'
    Write-TestFile -Path (Join-Path $polRoot 'ddraw.dll') -Content 'previous-loader'
    Write-TestFile -Path (Join-Path $scriptsRoot 'AccessXI.PolReloadedBootstrap.asi.disabled') -Content 'old-accessxi-bootstrap'
    Write-TestFile -Path (Join-Path $scriptsRoot 'Reloaded.Mod.Loader.Bootstrapper.dll') -Content 'old-reloaded-bootstrapper'
    Write-TestFile -Path (Join-Path $scriptsRoot 'UnrelatedAccessibility.asi') -Content 'preserve-me'

    $legacyRoot = Join-Path $installRoot 'Reloaded-II'
    Write-TestFile -Path (Join-Path $legacyRoot 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll') -Content 'old-mod'
    Write-TestFile -Path (Join-Path $legacyRoot 'Apps\AccessXI.PolPreLogin\AppConfig.json') -Content '{}'
    New-Item -ItemType Directory -Force -Path $configRoot | Out-Null
    [ordered]@{
        LoaderPath32 = Join-Path $legacyRoot 'Loader\x86\Reloaded.Mod.Loader.dll'
        LoaderPath64 = Join-Path $legacyRoot 'Loader\x64\Reloaded.Mod.Loader.dll'
        LauncherPath = Join-Path $legacyRoot 'Reloaded-II.exe'
        Bootstrapper32Path = Join-Path $legacyRoot 'Loader\x86\Bootstrapper\Reloaded.Mod.Loader.Bootstrapper.dll'
        Bootstrapper64Path = Join-Path $legacyRoot 'Loader\x64\Bootstrapper\Reloaded.Mod.Loader.Bootstrapper.dll'
        ApplicationConfigDirectory = Join-Path $legacyRoot 'Apps'
        ModUserConfigDirectory = Join-Path $legacyRoot 'User\Mods'
        MiscConfigDirectory = Join-Path $legacyRoot 'User\Misc'
        PluginConfigDirectory = Join-Path $legacyRoot 'Plugins'
        ModConfigDirectory = Join-Path $legacyRoot 'Mods'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $configRoot 'ReloadedII.json') -Encoding UTF8

    $polHashBefore = (Get-FileHash -LiteralPath $polExe -Algorithm SHA256).Hash
    $appHashBefore = (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash
    $packagedInstaller = Join-Path $packageRoot 'install_accessxi.ps1'
    & $packagedInstaller `
        -InstallRoot $installRoot `
        -PolExe $polExe `
        -LegacyAccessXiConfigRoot $configRoot `
        -SkipVisualCppRedistributables `
        -NoDesktopShortcut | Out-Null

    Assert-True (-not (Test-Path -LiteralPath $legacyRoot)) 'Installer did not remove the fully AccessXI-owned Reloaded root.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $configRoot 'ReloadedII.json'))) 'Installer did not remove the AccessXI-targeted global Reloaded config.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scriptsRoot 'AccessXI.PolReloadedBootstrap.asi.disabled'))) 'Installer left the old AccessXI Reloaded bootstrap marker.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $scriptsRoot 'Reloaded.Mod.Loader.Bootstrapper.dll'))) 'Installer left the old Reloaded bootstrapper beside PlayOnline.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $scriptsRoot 'UnrelatedAccessibility.asi') -Raw) 'preserve-me' 'Installer changed an unrelated ASI.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $polRoot 'ddraw.dll') -Raw) 'new-asi-loader' 'Installer did not deploy the current ASI loader.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $scriptsRoot 'AccessXI.PolNative.asi') -Raw) 'new-native-asi' 'Installer did not deploy the native AccessXI ASI.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $scriptsRoot 'AccessXI.PolNative\accessxi_pol_native.dll') -Raw) 'new-native-hook' 'Installer did not deploy the native hook.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $scriptsRoot 'AccessXI.PolNative\prism.dll') -Raw) 'new-native-prism' 'Installer did not deploy Prism.'
    Assert-Equal (Get-FileHash -LiteralPath $polExe -Algorithm SHA256).Hash $polHashBefore 'Installer changed pol.exe.'
    Assert-Equal (Get-FileHash -LiteralPath $appDll -Algorithm SHA256).Hash $appHashBefore 'Installer changed app.dll.'

    $summaryPath = Join-Path $installRoot 'install_summary.json'
    Assert-True (Test-Path -LiteralPath $summaryPath -PathType Leaf) 'Installer did not write install_summary.json.'
    $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    Assert-True $summary.LegacyAccessXiCleanup.Detected 'Install summary did not report the detected legacy AccessXI installation.'
    Assert-True $summary.LegacyAccessXiCleanup.FullLegacyRootRemoved 'Install summary did not report full removal of the owned Reloaded root.'
    Assert-True $summary.PolNativeDeployed 'Install summary did not report native PlayOnline deployment.'

    & $packagedInstaller `
        -InstallRoot $installRoot `
        -PolExe $polExe `
        -LegacyAccessXiConfigRoot $configRoot `
        -SkipVisualCppRedistributables `
        -NoDesktopShortcut | Out-Null
    $secondSummary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    Assert-True (-not $secondSummary.LegacyAccessXiCleanup.Detected) 'Second install falsely detected already-removed legacy Reloaded state.'
    Assert-Equal (Get-Content -LiteralPath (Join-Path $scriptsRoot 'UnrelatedAccessibility.asi') -Raw) 'preserve-me' 'Second install changed an unrelated ASI.'

    'ok: installer migrates an owned AccessXI Reloaded install to native PlayOnline accessibility and is idempotent.'
}
finally {
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}

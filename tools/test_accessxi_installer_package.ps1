param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$PackageRoot = 'C:\Users\buu42\AccessXI\dist\AccessXI-Ashita-Installer'
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -match $Pattern) {
        throw $Message
    }
}

function Assert-NotContainsLiteral {
    param(
        [string]$Text,
        [string]$Needle,
        [string]$Message
    )
    if ($Text.Contains($Needle)) {
        throw $Message
    }
}

$packageScript = Join-Path $RepoRoot 'tools\package_accessxi_installer.ps1'
$installerScript = Join-Path $RepoRoot 'installer\install_accessxi.ps1'
$legacyCleanupScript = Join-Path $RepoRoot 'installer\legacy_accessxi_cleanup.ps1'
$setupGuide = Join-Path $RepoRoot 'setup-guide.md'
$polUrlRepairScript = Join-Path $RepoRoot 'tools\repair_pol_url_cert_db.ps1'
$ashitaGuiProfile = Join-Path $RepoRoot 'installer\ashita_boot\AccessXI Retail.xml'
$ashitaCliProfile = Join-Path $RepoRoot 'installer\ashita_boot\accessxi-retail.ini'
$ashitaLauncher = Join-Path $RepoRoot 'installer\ashita_launcher\AccessXI.cmd'
$ashitaStartupScript = Join-Path $RepoRoot 'installer\ashita_scripts\default.txt'
$vcRedistX86 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x86.exe'
$vcRedistX64 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x64.exe'
$nativeStage = Join-Path $RepoRoot 'stage\pol-native'

Assert-True (Test-Path -LiteralPath $packageScript) "Missing package builder: $packageScript"
Assert-True (Test-Path -LiteralPath $installerScript) "Missing installer script: $installerScript"
Assert-True (Test-Path -LiteralPath $legacyCleanupScript) "Missing legacy cleanup library: $legacyCleanupScript"
Assert-True (Test-Path -LiteralPath $setupGuide) "Missing root setup guide: $setupGuide"
Assert-True (Test-Path -LiteralPath $polUrlRepairScript) "Missing POL URL repair helper: $polUrlRepairScript"
Assert-True (Test-Path -LiteralPath $ashitaGuiProfile) "Missing AccessXI Ashita GUI boot profile: $ashitaGuiProfile"
Assert-True (Test-Path -LiteralPath $ashitaCliProfile) "Missing AccessXI Ashita CLI boot profile: $ashitaCliProfile"
Assert-True (Test-Path -LiteralPath $ashitaLauncher) "Missing AccessXI Ashita CLI launcher: $ashitaLauncher"
Assert-True (Test-Path -LiteralPath $ashitaStartupScript) "Missing AccessXI Ashita startup script: $ashitaStartupScript"
Assert-True (Test-Path -LiteralPath $vcRedistX86) "Missing x86 Visual C++ redistributable prerequisite: $vcRedistX86"
Assert-True (Test-Path -LiteralPath $vcRedistX64) "Missing x64 Visual C++ redistributable prerequisite: $vcRedistX64"
Assert-True (Test-Path -LiteralPath (Join-Path $nativeStage 'AccessXI.PolNative.asi')) 'Missing staged native PlayOnline ASI.'
Assert-True (Test-Path -LiteralPath (Join-Path $nativeStage 'AccessXI.PolNative\accessxi_pol_native.dll')) 'Missing staged native PlayOnline hook DLL.'
Assert-True (Test-Path -LiteralPath (Join-Path $nativeStage 'AccessXI.PolNative\prism.dll')) 'Missing staged native PlayOnline Prism DLL.'

$packageSource = Get-Content -LiteralPath $packageScript -Raw
$installerSource = Get-Content -LiteralPath $installerScript -Raw
$legacyCleanupSource = Get-Content -LiteralPath $legacyCleanupScript -Raw
$polUrlRepairSource = Get-Content -LiteralPath $polUrlRepairScript -Raw
$profileSource = Get-Content -LiteralPath $ashitaGuiProfile -Raw
$cliProfileSource = Get-Content -LiteralPath $ashitaCliProfile -Raw
$launcherSource = Get-Content -LiteralPath $ashitaLauncher -Raw
$startupScriptSource = Get-Content -LiteralPath $ashitaStartupScript -Raw

Assert-Contains $profileSource '<setting name="config_name">AccessXI Retail</setting>' 'Ashita GUI profile must have a stable AccessXI Retail name.'
Assert-Contains $profileSource '<setting name="boot_command">/game eAZcFcB</setting>' 'Ashita GUI profile must use the working retail boot command.'
Assert-Contains $profileSource '<setting name="startup_script">default.txt</setting>' 'Ashita GUI profile must load the script that starts accessxi_reader.'
Assert-Contains $cliProfileSource 'command\s*=\s*/game eAZcFcB' 'Ashita CLI profile must use the working retail boot command.'
Assert-Contains $cliProfileSource 'script\s*=\s*default\.txt' 'Ashita CLI profile must load the script that starts accessxi_reader.'
Assert-Contains $cliProfileSource '(?m)^0042\s*=\s*$' 'Ashita CLI profile template must leave the FFXI install path blank for the installer to fill per machine.'
Assert-NotContainsLiteral $cliProfileSource 'C:\Program Files' 'Ashita CLI profile template must not ship a hard-coded Program Files FFXI path.'
Assert-Contains $launcherSource 'Ashita-cli\.exe' 'AccessXI launcher must use the Ashita v4 CLI instead of the v3 GUI updater.'
Assert-Contains $launcherSource 'ACCESSXI_PROFILE_NAME=accessxi-retail\.ini' 'AccessXI launcher must pass only the boot profile file name to Ashita-cli.exe.'
Assert-NotContains $launcherSource 'start[^\r\n]*config\\boot\\accessxi-retail\.ini' 'AccessXI launcher must not pass a config\boot path to Ashita-cli.exe.'
Assert-NotContains $launcherSource '(?m)^\s*start\s+' 'AccessXI launcher must not detach Ashita-cli.exe with start, because that can hand focus back to the caller while POL is opening.'
Assert-Contains $startupScriptSource '/addon load accessxi_reader' 'AccessXI startup script must load the in-game reader addon.'
Assert-Contains $startupScriptSource '/bind \^\+r /addon reload accessxi_reader' 'AccessXI startup script must preserve the reader reload hotkey.'

Assert-Contains $packageSource 'build_pol_native_asi\.ps1' 'Package builder must refresh the native PlayOnline ASI before packaging.'
Assert-Contains $packageSource 'test_pol_native_asi_structure\.ps1' 'Package builder must validate the native PlayOnline stage before packaging.'
Assert-Contains $packageSource 'setup-guide\.md' 'Package builder must stage the root setup guide beside the installer script.'
Assert-Contains $packageSource 'AccessXI Retail\.xml' 'Package builder must stage the AccessXI Ashita GUI profile.'
Assert-Contains $packageSource 'accessxi-retail\.ini' 'Package builder must stage the AccessXI Ashita CLI profile.'
Assert-Contains $packageSource 'AccessXI\.cmd' 'Package builder must stage the AccessXI Ashita CLI launcher.'
Assert-Contains $packageSource 'ashitaStartupScript' 'Package builder must stage the controlled AccessXI Ashita startup script.'
Assert-Contains $packageSource 'Ashita\.exe\*' 'Package builder must explicitly exclude the v3 Ashita GUI updater and disabled updater leftovers from v4 packages.'
Assert-Contains $packageSource 'config\\boot\\\*\.ini' 'Package builder must exclude machine-specific Ashita boot profiles before staging AccessXI profiles.'
Assert-Contains $packageSource 'config\\boot\\\*\.xml' 'Package builder must exclude machine-specific Ashita GUI profiles before staging AccessXI profiles.'
Assert-Contains $packageSource 'addons\\accessxi_reader\\logs\\\*' 'Package builder must exclude nested AccessXI addon runtime logs.'
Assert-Contains $packageSource 'ffxi-menu-reader\.boot\.log' 'Package builder must exclude AccessXI addon boot logs.'
Assert-Contains $packageSource 'PlayOnlineNative' 'Package builder must stage the native PlayOnline payload.'
Assert-Contains $packageSource 'AccessXI\.PolNative\.asi' 'Package builder must stage the native PlayOnline ASI.'
Assert-Contains $packageSource 'accessxi_pol_native\.dll' 'Package builder must stage the native PlayOnline hook DLL.'
Assert-Contains $packageSource 'prism\.dll' 'Package builder must stage Prism beside the native hook DLL.'
Assert-Contains $packageSource 'ddraw\.dll' 'Package builder must stage the x86 Ultimate ASI Loader for the native ASI.'
Assert-Contains $packageSource 'legacy_accessxi_cleanup\.ps1' 'Package builder must stage the ownership-bounded legacy cleanup library.'
Assert-Contains $packageSource 'Compress-Archive' 'Package builder must produce a redistributable zip package.'
Assert-Contains $packageSource 'vc_redist\.x86\.exe' 'Package builder must stage the x86 Visual C++ redistributable required by native PlayOnline support.'
Assert-Contains $packageSource 'vc_redist\.x64\.exe' 'Package builder must stage the x64 Visual C++ redistributable used by packaged 64-bit helper components.'
Assert-NotContains $packageSource 'windowsdesktop-runtime-' 'Native installer package must not ship obsolete Reloaded .NET Desktop Runtime installers.'
Assert-Contains $packageSource 'payloadPrerequisites' 'Package builder must keep prerequisites in a predictable payload folder.'
Assert-Contains $packageSource 'VisualCppRedistX86Hash' 'Package manifest must include the x86 Visual C++ redistributable hash.'
Assert-Contains $packageSource 'VisualCppRedistX64Hash' 'Package manifest must include the x64 Visual C++ redistributable hash.'
Assert-Contains $packageSource 'PolNativeAsiHash' 'Package manifest must include the native PlayOnline ASI hash.'
Assert-Contains $packageSource 'PolNativeHookHash' 'Package manifest must include the native PlayOnline hook hash.'
Assert-Contains $packageSource 'PolNativePrismHash' 'Package manifest must include the native PlayOnline Prism hash.'
Assert-Contains $packageSource 'PolAsiLoaderHash' 'Package manifest must include the PlayOnline ASI loader hash.'
Assert-Contains $packageSource '\*\.bak\*' 'Package builder must exclude all addon backup files, including .bak-before-* style names.'
Assert-Contains $packageSource 'ffxi_dat_strings\.tsv' 'Package builder must stage the DAT string index used by native-backed menu text.'
Assert-Contains $packageSource 'resources\\windower' 'Package builder must stage local Windower resource tables under the addon payload.'
Assert-Contains $packageSource 'LandSandBoat-server' 'Package builder must stage local SQL metadata used by job ability and gift speech.'
Assert-Contains $packageSource 'xiNavmeshes' 'Package builder must stage local nav meshes used by AccessXI nav.'
Assert-Contains $packageSource 'FFXINAV\.dll' 'Package builder must stage the FFXI navmesh DLL used by AccessXI nav.'
Assert-Contains $packageSource 'sounds' 'Package builder must stage AccessXI sounds locally instead of pointing at a developer folder.'

Assert-Contains $installerSource 'param\(' 'Installer must accept parameters instead of hardcoding this machine only.'
Assert-Contains $installerSource '\$InstallRoot' 'Installer must install Ashita under a caller-selected install root.'
Assert-Contains $installerSource '\$PolExe' 'Installer must let the user provide the PlayOnline Viewer target.'
Assert-Contains $installerSource '\$LegacyAccessXiConfigRoot' 'Installer must let cleanup tests isolate the old Reloaded config root.'
Assert-Contains $installerSource 'Get-DefaultProgramFilesRoots' 'Installer must derive default PlayOnline paths from this machine instead of hard-coding C:\Program Files.'
Assert-Contains $installerSource 'Set-AshitaCliFfxiInstallPath' 'Installer must write the selected machine FFXI install path into the copied Ashita CLI profile.'
Assert-Contains $installerSource 'Get-FfxiInstallRootFromPolExe' 'Installer must derive the FFXI root from the selected PlayOnline pol.exe path.'
Assert-NotContains $installerSource "'C:\\Program Files" 'Installer script must not hard-code Program Files PlayOnline candidates.'
Assert-Contains $installerSource 'ddraw\.dll' 'Installer must deploy the x86 ASI loader through the verified POL ddraw proxy.'
Assert-Contains $installerSource 'Backup-ExistingFile' 'Installer must back up existing POL-side files before replacing them.'
Assert-Contains $installerSource 'AccessXI\.PolNative\.asi' 'Installer must deploy the native AccessXI PlayOnline ASI.'
Assert-Contains $installerSource 'Remove-LegacyAccessXiInstall' 'Installer must run ownership-bounded cleanup for old AccessXI Reloaded files.'
Assert-Contains $legacyCleanupSource 'SharedLegacyRootPreserved' 'Installer cleanup results must report when another game causes a Reloaded root to be preserved.'
Assert-Contains $legacyCleanupSource 'allowedOwnedAppNames' 'Cleanup must distinguish AccessXI app markers from another game registered in Reloaded.'
Assert-Contains $legacyCleanupSource 'allowedOwnedModNames' 'Cleanup must distinguish AccessXI mod markers from another game mod registered in Reloaded.'
Assert-Contains $installerSource 'Assert-PlayOnlineClosed' 'Installer must refuse POL-side cleanup and native replacement while PlayOnline is running.'
Assert-Contains $installerSource 'Get-Process\s+-Name\s+''pol''' 'Installer must detect a running PlayOnline Viewer before changing its files.'
Assert-Contains $installerSource 'Repair-PolUrlFiles' 'Installer must repair missing PlayOnline Viewer URL key-path files before POL self-repair can pop Windows Installer.'
Assert-Contains $installerSource 'default\\usr\\all\\url' 'Installer must copy known-good default PlayOnline URL key-path sources.'
Assert-Contains $installerSource 'usr\\all\\url' 'Installer must restore the PlayOnline URL key-path folder Windows Installer demands.'
Assert-Contains $installerSource 'cert\.db' 'Installer must restore the PlayOnline cert.db key-path Windows Installer demands.'
Assert-Contains $installerSource 'rdthosts\.bin' 'Installer must restore the PlayOnline rdthosts.bin key-path Windows Installer demands.'
Assert-Contains $installerSource 'dcfat0\.bin' 'Installer must guard the PlayOnline URL cache key-path that Windows Installer demands.'
Assert-Contains $installerSource 'Get-ChildItem[^\r\n]*-Recurse' 'Installer POL URL repair must recurse through the default URL tree instead of copying only a fixed top-level list.'
Assert-Contains $polUrlRepairSource 'Get-ChildItem[^\r\n]*-Recurse' 'Standalone POL URL repair helper must recurse through the default URL tree.'
Assert-Contains $polUrlRepairSource 'dcfat0\.bin' 'Standalone POL URL repair helper must guard the PlayOnline URL cache key-path.'
Assert-Contains $installerSource 'TargetPath\s*=\s*Join-Path\s+\$AshitaRoot\s+''Ashita-cli\.exe''' 'Installer shortcut must target Ashita-cli.exe directly so the desktop shortcut does not detach through AccessXI.cmd and lose focus.'
Assert-Contains $installerSource 'Arguments\s*=\s*''accessxi-retail\.ini''' 'Installer shortcut must pass the AccessXI retail CLI profile directly to Ashita-cli.exe.'
Assert-NotContains $installerSource 'TargetPath\s*=\s*Join-Path\s+\$AshitaRoot\s+''AccessXI\.cmd''' 'Installer shortcut must not target AccessXI.cmd because the batch wrapper can hand focus back to the caller during POL startup.'
Assert-Contains $installerSource 'AshitaCli\s*=\s*Join-Path\s+\$ashitaDest\s+''Ashita-cli\.exe''' 'Installer summary must point at the Ashita v4 CLI.'
Assert-Contains $installerSource 'AccessXI\.cmd' 'Installer must install and expose the AccessXI CLI launcher.'
Assert-Contains $installerSource 'accessxi-retail\.ini' 'Installer summary must point at the AccessXI Ashita CLI profile.'
Assert-Contains $installerSource 'CreateShortcut' 'Installer must create an AccessXI Ashita GUI launch shortcut.'
Assert-Contains $installerSource 'accessxi_pol_nvda\.dll' 'Installer must keep the old Ashita POL plugin disabled.'
Assert-Contains $installerSource 'prism\.dll' 'Installer must verify packaged Prism is available beside the native PlayOnline hook.'
Assert-Contains $installerSource 'accessxi_reader' 'Installer must verify the in-game AccessXI Ashita addon payload.'
Assert-Contains $installerSource 'Install-VisualCppRedistributables' 'Installer must install the packaged Visual C++ redistributables before native PlayOnline support loads.'
Assert-Contains $installerSource '\$SkipVisualCppRedistributables' 'Installer must let the GUI skip Visual C++ redist installation after dependency detection succeeds.'
Assert-Contains $installerSource 'Skipping Visual C\+\+ runtime prerequisite installation' 'Installer must log when dependency detection lets it skip redist installation.'
Assert-Contains $installerSource 'vc_redist\.x86\.exe' 'Installer must run the x86 Visual C++ redistributable required by native PlayOnline support.'
Assert-Contains $installerSource 'vc_redist\.x64\.exe' 'Installer must run the x64 Visual C++ redistributable for packaged helper components.'
Assert-NotContains $installerSource 'Install-DotNetDesktopRuntime|windowsdesktop-runtime-' 'Native installer must not install obsolete Reloaded .NET Desktop Runtimes.'
Assert-Contains $installerSource '/install' 'Installer must invoke Visual C++ redistributables in install mode.'
Assert-Contains $installerSource '/quiet' 'Installer must invoke Visual C++ redistributables without prompting inside the wrapper.'
Assert-Contains $installerSource '/norestart' 'Installer must prevent prerequisite installers from restarting Windows unexpectedly.'
Assert-Contains $installerSource '3010' 'Installer must tolerate the Visual C++ redistributable reboot-required success code.'
Assert-Contains $installerSource '1638' 'Installer must tolerate an already-installed or newer Visual C++ redistributable.'
Assert-Contains $installerSource 'VisualCppRedistributables' 'Installer summary must record Visual C++ prerequisite installation results.'
Assert-Contains $installerSource 'DiagnosticLogDirectory' 'Installer summary must include the AccessXI diagnostic log directory for support.'
Assert-Contains $installerSource 'pol-native-startup\.log' 'Installer summary must point to the native PlayOnline startup diagnostic log.'
Assert-Contains $installerSource 'pol-native-speech\.log' 'Installer summary must point to the native PlayOnline speech diagnostic log.'
Assert-Contains $installerSource 'Assert-DeployedFileHash' 'Installer must hash-verify deployed native files so stale DLLs cannot silently survive installation.'
Assert-Contains $installerSource 'DeployedHashes' 'Installer summary must record deployed file hashes for support logs.'
Assert-Contains $installerSource 'PackageManifestCreatedAt' 'Installer summary must record the packaged payload timestamp for stale-installer diagnosis.'
Assert-Contains $installerSource 'PolNativeAsi' 'Installer summary must include the native PlayOnline ASI hash.'
Assert-Contains $installerSource 'PolNativeHook' 'Installer summary must include the native PlayOnline hook DLL hash.'
Assert-Contains $installerSource 'LegacyAccessXiCleanup' 'Installer summary must record legacy cleanup decisions.'

if (Test-Path -LiteralPath $PackageRoot) {
    $payloadAshita = Join-Path $PackageRoot 'payload\Ashita'
    $payloadNative = Join-Path $PackageRoot 'payload\PlayOnlineNative'
    $payloadPrerequisites = Join-Path $PackageRoot 'payload\Prerequisites'
    $payloadAddon = Join-Path $payloadAshita 'addons\accessxi_reader'
    $payloadWin32Types = Join-Path $payloadAshita 'addons\libs\win32types.lua'
    Assert-True (Test-Path -LiteralPath (Join-Path $PackageRoot 'install_accessxi.ps1')) 'Package must contain the installer entry script.'
    Assert-True (Test-Path -LiteralPath (Join-Path $PackageRoot 'legacy_accessxi_cleanup.ps1')) 'Package must contain the legacy Reloaded cleanup library.'
    Assert-True (Test-Path -LiteralPath (Join-Path $PackageRoot 'setup-guide.md')) 'Package must contain setup-guide.md at the root.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAshita 'Ashita-cli.exe')) 'Package must contain the Ashita v4 CLI.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'Ashita.exe'))) 'Package must not contain the v3 Ashita GUI updater.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'Ashita.exe.v3-updater.disabled'))) 'Package must not contain disabled v3 Ashita updater leftovers.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAshita 'AccessXI.cmd')) 'Package must contain the AccessXI CLI launcher.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAshita 'config\boot\AccessXI Retail.xml')) 'Package must contain the AccessXI Ashita GUI profile.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAshita 'config\boot\accessxi-retail.ini')) 'Package must contain the AccessXI Ashita CLI profile.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'config\boot\example.ini'))) 'Package must not contain generic Ashita example profiles with machine paths.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'config\boot\example-retail.ini'))) 'Package must not contain generic Ashita retail example profiles with machine paths.'
    $payloadCliProfile = Get-Content -LiteralPath (Join-Path $payloadAshita 'config\boot\accessxi-retail.ini') -Raw
    Assert-Contains $payloadCliProfile '(?m)^0042\s*=\s*$' 'Packaged Ashita CLI profile must leave the FFXI install path blank until install time.'
    Assert-NotContainsLiteral $payloadCliProfile 'C:\Program Files' 'Packaged Ashita CLI profile must not hard-code a Program Files FFXI path.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAshita 'scripts\default.txt')) 'Package must contain the controlled AccessXI startup script.'
    $payloadStartupScript = Get-Content -LiteralPath (Join-Path $payloadAshita 'scripts\default.txt') -Raw
    Assert-Contains $payloadStartupScript '/addon load accessxi_reader' 'Packaged startup script must load the in-game reader addon.'
    Assert-Contains $payloadStartupScript '/bind \^\+r /addon reload accessxi_reader' 'Packaged startup script must preserve the reader reload hotkey.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'config\boot\New Configuration 1.xml'))) 'Package must not contain the throwaway Ashita GUI profile.'
    Assert-True (Test-Path -LiteralPath $payloadWin32Types) 'Package must contain Ashita win32types.lua.'
    $payloadWin32TypesSource = Get-Content -LiteralPath $payloadWin32Types -Raw
    Assert-True ($payloadWin32TypesSource -notmatch 'typedef\s+const\s+IID\s*&\s*REFIID') 'Packaged win32types.lua must not use a C++ REFIID reference inside LuaJIT ffi.cdef.'
    Assert-True ($payloadWin32TypesSource -notmatch 'typedef\s+const\s+GUID\s*&\s*REFGUID') 'Packaged win32types.lua must not use a C++ REFGUID reference inside LuaJIT ffi.cdef.'
    Assert-True ($payloadWin32TypesSource -match 'typedef\s+const\s+IID\s*\*\s*REFIID') 'Packaged win32types.lua must expose REFIID as a C pointer typedef.'
    Assert-True ($payloadWin32TypesSource -match 'typedef\s+const\s+GUID\s*\*\s*REFGUID') 'Packaged win32types.lua must expose REFGUID as a C pointer typedef.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'accessxi_reader.lua')) 'Package must contain the AccessXI Ashita addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'data\ffxi-nav-destinations.tsv')) 'Package must contain AccessXI nav destinations beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'data\ffxi-nav-zoneline-graph.tsv')) 'Package must contain AccessXI nav zoneline graph beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\dat_index\ffxi_dat_strings.tsv')) 'Package must contain the DAT string index beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\windower\items.lua')) 'Package must contain Windower item names beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\windower\item_descriptions.lua')) 'Package must contain Windower item descriptions beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\windower\merit_points.lua')) 'Package must contain Windower merit resources beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\windower\job_points.lua')) 'Package must contain Windower job point resources beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\windower\key_items.lua')) 'Package must contain Windower key item resources beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\windower\job_traits.lua')) 'Package must contain Windower job trait resources beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'resources\windower\auto_translates.lua')) 'Package must contain Windower auto-translate resources beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'third_party\LandSandBoat-server\sql\abilities.sql')) 'Package must contain job ability SQL metadata beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'third_party\LandSandBoat-server\sql\job_point_gifts.sql')) 'Package must contain job point gift SQL metadata beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'third_party\FFXI-NavMesh-Builder\FFXINAV.dll')) 'Package must contain the navmesh DLL beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'third_party\xiNavmeshes')) 'Package must contain nav meshes beside the addon.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadAddon 'sounds\nav_collision')) 'Package must contain the collision sound folder beside the addon.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAddon 'ffxi-menu-reader.boot.log'))) 'Package must not contain AccessXI addon boot logs.'
    $packagedAddonLogFiles = @()
    if (Test-Path -LiteralPath (Join-Path $payloadAddon 'logs')) {
        $packagedAddonLogFiles = @(Get-ChildItem -LiteralPath (Join-Path $payloadAddon 'logs') -Force -Recurse -File)
    }
    Assert-True ($packagedAddonLogFiles.Count -eq 0) "Package must not contain AccessXI addon runtime log files; found $($packagedAddonLogFiles.Count)."
    $packagedBackupFiles = @(Get-ChildItem -LiteralPath $payloadAddon -Force -Recurse -File | Where-Object { $_.Name -like '*.bak*' -or $_.FullName -like '*.bak*' })
    Assert-True ($packagedBackupFiles.Count -eq 0) "Package must not contain addon backup files; found $($packagedBackupFiles.Count)."
    $packagedRuntimeLuaFiles = @(Get-ChildItem -LiteralPath $payloadAddon -Force -Recurse -File | Where-Object { $_.Extension -ieq '.lua' -and $_.Name -notlike '*.bak*' })
    foreach ($luaFile in $packagedRuntimeLuaFiles) {
        $luaSource = Get-Content -LiteralPath $luaFile.FullName -Raw
        Assert-NotContainsLiteral $luaSource 'C:\Users\buu42' "Packaged Lua must not contain this machine's user path: $($luaFile.FullName)"
        Assert-NotContainsLiteral $luaSource 'C:\\Users\\buu42' "Packaged Lua must not contain escaped developer user paths: $($luaFile.FullName)"
        Assert-NotContainsLiteral $luaSource 'C:/Users/buu42' "Packaged Lua must not contain slash-normalized developer user paths: $($luaFile.FullName)"
        Assert-NotContainsLiteral $luaSource 'C:\Program Files (x86)\PlayOnline\SquareEnix' "Packaged Lua must not hardcode the PlayOnline install root: $($luaFile.FullName)"
        Assert-NotContainsLiteral $luaSource 'C:\\Program Files (x86)\\PlayOnline\\SquareEnix' "Packaged Lua must not hardcode escaped PlayOnline install roots: $($luaFile.FullName)"
    }
    $packagedAddonTextFiles = @(Get-ChildItem -LiteralPath $payloadAddon -Force -Recurse -File | Where-Object {
        $_.Extension -in @('.lua', '.tsv', '.txt', '.ini', '.json', '.xml', '.cmd', '.ps1') -and $_.Name -notlike '*.bak*'
    })
    foreach ($textFile in $packagedAddonTextFiles) {
        $textSource = Get-Content -LiteralPath $textFile.FullName -Raw
        Assert-NotContainsLiteral $textSource 'C:\Users\buu42' "Packaged addon text must not contain this machine's user path: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:\\Users\\buu42' "Packaged addon text must not contain escaped developer user paths: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:/Users/buu42' "Packaged addon text must not contain slash-normalized developer user paths: $($textFile.FullName)"
    }
    $packagedAshitaTextFiles = @(Get-ChildItem -LiteralPath $payloadAshita -Force -Recurse -File | Where-Object {
        $_.Extension -in @('.json', '.xml', '.txt', '.ini', '.config', '.toml', '.md', '.cmd', '.ps1', '.log')
    })
    foreach ($textFile in $packagedAshitaTextFiles) {
        $textSource = Get-Content -LiteralPath $textFile.FullName -Raw
        Assert-NotContainsLiteral $textSource 'C:\Users\buu42' "Packaged Ashita text must not contain this machine's user path: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:\\Users\\buu42' "Packaged Ashita text must not contain escaped developer user paths: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:/Users/buu42' "Packaged Ashita text must not contain slash-normalized developer user paths: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:\Program Files (x86)\SquareEnix\FINAL FANTASY XI' "Packaged Ashita text must not contain stale FFXI install paths: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:\Program Files (x86)\PlayOnline\SquareEnix' "Packaged Ashita text must not contain stale PlayOnline paths: $($textFile.FullName)"
    }
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'payload\Reloaded-II'))) 'Package must not contain Reloaded-II.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'payload\pol_bootloader'))) 'Package must not contain the old Reloaded bootstrap payload.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadNative 'ddraw.dll')) 'Package must contain the x86 Ultimate ASI Loader.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadNative 'AccessXI.PolNative.asi')) 'Package must contain the native PlayOnline ASI.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadNative 'AccessXI.PolNative\accessxi_pol_native.dll')) 'Package must contain the native PlayOnline hook DLL.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadNative 'AccessXI.PolNative\prism.dll')) 'Package must contain native PlayOnline Prism.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $payloadNative 'AccessXI.PolNative.asi') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $nativeStage 'AccessXI.PolNative.asi') -Algorithm SHA256).Hash) 'Packaged native PlayOnline ASI hash mismatch.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $payloadNative 'AccessXI.PolNative\accessxi_pol_native.dll') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $nativeStage 'AccessXI.PolNative\accessxi_pol_native.dll') -Algorithm SHA256).Hash) 'Packaged native PlayOnline hook hash mismatch.'
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $payloadNative 'AccessXI.PolNative\prism.dll') -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath (Join-Path $nativeStage 'AccessXI.PolNative\prism.dll') -Algorithm SHA256).Hash) 'Packaged native PlayOnline Prism hash mismatch.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'vc_redist.x86.exe')) 'Package must contain the x86 Visual C++ redistributable prerequisite.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'vc_redist.x64.exe')) 'Package must contain the x64 Visual C++ redistributable prerequisite.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x86.exe'))) 'Package must not contain the obsolete x86 .NET Desktop Runtime.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x64.exe'))) 'Package must not contain the obsolete x64 .NET Desktop Runtime.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'logs'))) 'Package must not include Ashita runtime logs.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'screenshots'))) 'Package must not include Ashita screenshots.'
}

'ok: AccessXI installer/package structure is guarded.'

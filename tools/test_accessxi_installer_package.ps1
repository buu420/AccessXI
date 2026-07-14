param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$PackageRoot = 'C:\Users\buu42\AccessXI\dist\AccessXI-Ashita-Reloaded-Installer'
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
$setupGuide = Join-Path $RepoRoot 'setup-guide.md'
$polUrlRepairScript = Join-Path $RepoRoot 'tools\repair_pol_url_cert_db.ps1'
$ashitaGuiProfile = Join-Path $RepoRoot 'installer\ashita_boot\AccessXI Retail.xml'
$ashitaCliProfile = Join-Path $RepoRoot 'installer\ashita_boot\accessxi-retail.ini'
$ashitaLauncher = Join-Path $RepoRoot 'installer\ashita_launcher\AccessXI.cmd'
$ashitaStartupScript = Join-Path $RepoRoot 'installer\ashita_scripts\default.txt'
$vcRedistX86 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x86.exe'
$vcRedistX64 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x64.exe'
$dotNetDesktopRuntimeX86 = Join-Path $RepoRoot 'installer\prerequisites\windowsdesktop-runtime-9.0.17-win-x86.exe'
$dotNetDesktopRuntimeX64 = Join-Path $RepoRoot 'installer\prerequisites\windowsdesktop-runtime-9.0.17-win-x64.exe'

Assert-True (Test-Path -LiteralPath $packageScript) "Missing package builder: $packageScript"
Assert-True (Test-Path -LiteralPath $installerScript) "Missing installer script: $installerScript"
Assert-True (Test-Path -LiteralPath $setupGuide) "Missing root setup guide: $setupGuide"
Assert-True (Test-Path -LiteralPath $polUrlRepairScript) "Missing POL URL repair helper: $polUrlRepairScript"
Assert-True (Test-Path -LiteralPath $ashitaGuiProfile) "Missing AccessXI Ashita GUI boot profile: $ashitaGuiProfile"
Assert-True (Test-Path -LiteralPath $ashitaCliProfile) "Missing AccessXI Ashita CLI boot profile: $ashitaCliProfile"
Assert-True (Test-Path -LiteralPath $ashitaLauncher) "Missing AccessXI Ashita CLI launcher: $ashitaLauncher"
Assert-True (Test-Path -LiteralPath $ashitaStartupScript) "Missing AccessXI Ashita startup script: $ashitaStartupScript"
Assert-True (Test-Path -LiteralPath $vcRedistX86) "Missing x86 Visual C++ redistributable prerequisite: $vcRedistX86"
Assert-True (Test-Path -LiteralPath $vcRedistX64) "Missing x64 Visual C++ redistributable prerequisite: $vcRedistX64"
Assert-True (Test-Path -LiteralPath $dotNetDesktopRuntimeX86) "Missing x86 .NET Desktop Runtime prerequisite: $dotNetDesktopRuntimeX86"
Assert-True (Test-Path -LiteralPath $dotNetDesktopRuntimeX64) "Missing x64 .NET Desktop Runtime prerequisite: $dotNetDesktopRuntimeX64"

$packageSource = Get-Content -LiteralPath $packageScript -Raw
$installerSource = Get-Content -LiteralPath $installerScript -Raw
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

Assert-Contains $packageSource 'build_pol_reloaded\.ps1' 'Package builder must refresh the Reloaded POL mod before packaging.'
Assert-Contains $packageSource 'build_pol_reloaded_bootloader\.ps1' 'Package builder must refresh the delayed POL bootloader before packaging.'
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
Assert-Contains $packageSource 'pol-reloaded-native-speech\.queue|pol-reloaded-speech\.log|pol-monitor\.log' 'Package builder must know to exclude runtime logs from the installer payload.'
Assert-Contains $packageSource 'Apps\\AccessXI\.PolPreLogin\\AppConfig\.json' 'Package builder must exclude Reloaded app configs that are generated per installed machine.'
Assert-Contains $packageSource 'AccessXI\.PolReloadedBootstrap\.asi' 'Package builder must stage the AccessXI delayed Reloaded POL bootloader.'
Assert-Contains $packageSource 'Compress-Archive' 'Package builder must produce a redistributable zip package.'
Assert-Contains $packageSource 'vc_redist\.x86\.exe' 'Package builder must stage the x86 Visual C++ redistributable required by the POL x86 bootstrapper.'
Assert-Contains $packageSource 'vc_redist\.x64\.exe' 'Package builder must stage the x64 Visual C++ redistributable used by packaged 64-bit helper components.'
Assert-Contains $packageSource 'windowsdesktop-runtime-9\.0\.17-win-x86\.exe' 'Package builder must stage the x86 .NET Desktop Runtime required by the Reloaded POL x86 loader.'
Assert-Contains $packageSource 'windowsdesktop-runtime-9\.0\.17-win-x64\.exe' 'Package builder must stage the x64 .NET Desktop Runtime required by the Reloaded launcher.'
Assert-Contains $packageSource 'payloadPrerequisites' 'Package builder must keep prerequisites in a predictable payload folder.'
Assert-Contains $packageSource 'VisualCppRedistX86Hash' 'Package manifest must include the x86 Visual C++ redistributable hash.'
Assert-Contains $packageSource 'VisualCppRedistX64Hash' 'Package manifest must include the x64 Visual C++ redistributable hash.'
Assert-Contains $packageSource 'DotNetDesktopRuntimeX86Hash' 'Package manifest must include the x86 .NET Desktop Runtime hash.'
Assert-Contains $packageSource 'DotNetDesktopRuntimeX64Hash' 'Package manifest must include the x64 .NET Desktop Runtime hash.'
Assert-Contains $packageSource '\*\.bak\*' 'Package builder must exclude all addon backup files, including .bak-before-* style names.'
Assert-Contains $packageSource 'ffxi_dat_strings\.tsv' 'Package builder must stage the DAT string index used by native-backed menu text.'
Assert-Contains $packageSource 'resources\\windower' 'Package builder must stage local Windower resource tables under the addon payload.'
Assert-Contains $packageSource 'LandSandBoat-server' 'Package builder must stage local SQL metadata used by job ability and gift speech.'
Assert-Contains $packageSource 'xiNavmeshes' 'Package builder must stage local nav meshes used by AccessXI nav.'
Assert-Contains $packageSource 'FFXINAV\.dll' 'Package builder must stage the FFXI navmesh DLL used by AccessXI nav.'
Assert-Contains $packageSource 'sounds' 'Package builder must stage AccessXI sounds locally instead of pointing at a developer folder.'

Assert-Contains $installerSource 'param\(' 'Installer must accept parameters instead of hardcoding this machine only.'
Assert-Contains $installerSource '\$InstallRoot' 'Installer must install Ashita and Reloaded under a caller-selected install root.'
Assert-Contains $installerSource '\$PolExe' 'Installer must let the user provide the PlayOnline Viewer target.'
Assert-Contains $installerSource '\$ReloadedConfigRoot' 'Installer must let smoke tests isolate Reloaded-II user config instead of mutating the real APPDATA loader config.'
Assert-Contains $installerSource 'Get-DefaultProgramFilesRoots' 'Installer must derive default PlayOnline paths from this machine instead of hard-coding C:\Program Files.'
Assert-Contains $installerSource 'Set-AshitaCliFfxiInstallPath' 'Installer must write the selected machine FFXI install path into the copied Ashita CLI profile.'
Assert-Contains $installerSource 'Get-FfxiInstallRootFromPolExe' 'Installer must derive the FFXI root from the selected PlayOnline pol.exe path.'
Assert-NotContains $installerSource "'C:\\Program Files" 'Installer script must not hard-code Program Files PlayOnline candidates.'
Assert-Contains $installerSource 'ReloadedII\.json' 'Installer must write Reloaded-II loader paths for the installed machine.'
Assert-Contains $installerSource 'AppConfig\.json' 'Installer must write the POL app config for the installed machine.'
Assert-Contains $installerSource 'ShowConsole\s*=\s*\$false' 'Installer must hide the Reloaded console for normal POL startup.'
Assert-Contains $installerSource 'ddraw\.dll' 'Installer must deploy the x86 ASI loader through the verified POL ddraw proxy.'
Assert-Contains $installerSource 'Backup-ExistingFile' 'Installer must back up existing POL-side files before replacing them.'
Assert-Contains $installerSource 'AccessXI\.PolReloadedBootstrap\.asi' 'Installer must deploy the delayed AccessXI POL bootloader.'
Assert-Contains $installerSource 'Reloaded\.Mod\.Loader\.Bootstrapper\.dll' 'Installer must stage the x86 Reloaded bootstrapper beside the POL bootloader.'
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
Assert-Contains $installerSource 'prism\.dll' 'Installer must verify packaged Prism is available beside the Reloaded POL mod.'
Assert-Contains $installerSource 'accessxi_reader' 'Installer must verify the in-game AccessXI Ashita addon payload.'
Assert-Contains $installerSource 'Install-VisualCppRedistributables' 'Installer must install the packaged Visual C++ redistributables before POL loads Reloaded.'
Assert-Contains $installerSource '\$SkipVisualCppRedistributables' 'Installer must let the GUI skip Visual C++ redist installation after dependency detection succeeds.'
Assert-Contains $installerSource 'Skipping Visual C\+\+ runtime prerequisite installation' 'Installer must log when dependency detection lets it skip redist installation.'
Assert-Contains $installerSource 'vc_redist\.x86\.exe' 'Installer must run the x86 Visual C++ redistributable required by the POL x86 bootstrapper.'
Assert-Contains $installerSource 'vc_redist\.x64\.exe' 'Installer must run the x64 Visual C++ redistributable for packaged helper components.'
Assert-Contains $installerSource 'Install-DotNetDesktopRuntimes' 'Installer must install the packaged .NET Desktop Runtime prerequisites before POL loads Reloaded.'
Assert-Contains $installerSource '\$SkipDotNetDesktopRuntimes' 'Installer must let the GUI skip .NET Desktop Runtime installation after dependency detection succeeds.'
Assert-Contains $installerSource 'Skipping \.NET Desktop Runtime prerequisite installation' 'Installer must log when dependency detection lets it skip .NET Desktop Runtime installation.'
Assert-Contains $installerSource 'windowsdesktop-runtime-9\.0\.17-win-x86\.exe' 'Installer must run the x86 .NET Desktop Runtime required by the Reloaded POL x86 loader.'
Assert-Contains $installerSource 'windowsdesktop-runtime-9\.0\.17-win-x64\.exe' 'Installer must run the x64 .NET Desktop Runtime required by the Reloaded launcher.'
Assert-Contains $installerSource '/install' 'Installer must invoke Visual C++ redistributables in install mode.'
Assert-Contains $installerSource '/quiet' 'Installer must invoke Visual C++ redistributables without prompting inside the wrapper.'
Assert-Contains $installerSource '/norestart' 'Installer must prevent prerequisite installers from restarting Windows unexpectedly.'
Assert-Contains $installerSource '3010' 'Installer must tolerate the Visual C++ redistributable reboot-required success code.'
Assert-Contains $installerSource '1638' 'Installer must tolerate an already-installed or newer Visual C++ redistributable.'
Assert-Contains $installerSource 'VisualCppRedistributables' 'Installer summary must record Visual C++ prerequisite installation results.'
Assert-Contains $installerSource 'DotNetDesktopRuntimes' 'Installer summary must record .NET Desktop Runtime prerequisite installation results.'
Assert-Contains $installerSource 'DiagnosticLogDirectory' 'Installer summary must include the AccessXI diagnostic log directory for support.'
Assert-Contains $installerSource 'pol-reloaded-startup\.log' 'Installer summary must point to the Reloaded startup diagnostic log.'
Assert-Contains $installerSource 'pol-reloaded-speech\.log' 'Installer summary must point to the Reloaded speech diagnostic log.'
Assert-Contains $installerSource 'pol-monitor\.log' 'Installer summary must point to the native POL monitor diagnostic log.'
Assert-Contains $installerSource 'pol-reloaded-native-speech\.queue' 'Installer summary must point to the native speech queue diagnostic file.'
Assert-Contains $installerSource 'Assert-DeployedFileHash' 'Installer must hash-verify deployed Reloaded files so stale mod DLLs cannot silently survive installation.'
Assert-Contains $installerSource 'DeployedHashes' 'Installer summary must record deployed file hashes for support logs.'
Assert-Contains $installerSource 'PackageManifestCreatedAt' 'Installer summary must record the packaged payload timestamp for stale-installer diagnosis.'
Assert-Contains $installerSource 'PolReloadedMod' 'Installer summary must include the managed POL Reloaded mod hash.'
Assert-Contains $installerSource 'PolReloadedNative' 'Installer summary must include the native POL hook DLL hash.'

if (Test-Path -LiteralPath $PackageRoot) {
    $payloadAshita = Join-Path $PackageRoot 'payload\Ashita'
    $payloadReloaded = Join-Path $PackageRoot 'payload\Reloaded-II'
    $payloadBootloader = Join-Path $PackageRoot 'payload\pol_bootloader'
    $payloadPrerequisites = Join-Path $PackageRoot 'payload\Prerequisites'
    $payloadAddon = Join-Path $payloadAshita 'addons\accessxi_reader'
    $payloadWin32Types = Join-Path $payloadAshita 'addons\libs\win32types.lua'
    Assert-True (Test-Path -LiteralPath (Join-Path $PackageRoot 'install_accessxi.ps1')) 'Package must contain the installer entry script.'
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
    $packagedReloadedTextFiles = @(Get-ChildItem -LiteralPath $payloadReloaded -Force -Recurse -File | Where-Object {
        $_.Extension -in @('.json', '.xml', '.txt', '.ini', '.config', '.toml', '.md')
    })
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadReloaded 'Apps\AccessXI.PolPreLogin\AppConfig.json'))) 'Package must not contain Reloaded AppConfig.json because install_accessxi.ps1 generates it from the selected pol.exe.'
    foreach ($textFile in $packagedReloadedTextFiles) {
        $textSource = Get-Content -LiteralPath $textFile.FullName -Raw
        Assert-NotContainsLiteral $textSource 'C:\Users\buu42' "Packaged Reloaded config must not contain this machine's user path: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:\\Users\\buu42' "Packaged Reloaded config must not contain escaped developer user paths: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:/Users/buu42' "Packaged Reloaded config must not contain slash-normalized developer user paths: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:\Program Files (x86)\PlayOnline\SquareEnix' "Packaged Reloaded config must not contain stale PlayOnline paths: $($textFile.FullName)"
        Assert-NotContainsLiteral $textSource 'C:\\Program Files (x86)\\PlayOnline\\SquareEnix' "Packaged Reloaded config must not contain escaped stale PlayOnline paths: $($textFile.FullName)"
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
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadReloaded 'Reloaded-II.exe')) 'Package must contain Reloaded-II.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadReloaded 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll')) 'Package must contain the AccessXI Reloaded POL mod.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadReloaded 'Mods\AccessXI.PolReloaded\prism.dll')) 'Package must contain package-local Prism for POL speech.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadReloaded 'Mods\reloaded.sharedlib.hooks\ModConfig.json')) 'Package must contain Reloaded shared hooks dependency.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadBootloader 'AccessXI.PolReloadedBootstrap.asi')) 'Package must contain the delayed POL bootloader ASI.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'vc_redist.x86.exe')) 'Package must contain the x86 Visual C++ redistributable prerequisite.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'vc_redist.x64.exe')) 'Package must contain the x64 Visual C++ redistributable prerequisite.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x86.exe')) 'Package must contain the x86 .NET Desktop Runtime prerequisite.'
    Assert-True (Test-Path -LiteralPath (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x64.exe')) 'Package must contain the x64 .NET Desktop Runtime prerequisite.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'logs'))) 'Package must not include Ashita runtime logs.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadAshita 'screenshots'))) 'Package must not include Ashita screenshots.'
}

'ok: AccessXI installer/package structure is guarded.'

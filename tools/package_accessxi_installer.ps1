param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$AshitaRoot = 'C:\Users\buu42\Ashita',
    [string]$OutputDirectory = '',
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-UnderDirectory {
    param(
        [string]$Path,
        [string]$Parent,
        [string]$Message
    )

    $resolvedPath = Resolve-FullPath $Path
    $resolvedParent = (Resolve-FullPath $Parent).TrimEnd('\')
    $parentWithSeparator = $resolvedParent + '\'
    if ($resolvedPath -ieq $resolvedParent -or $resolvedPath.StartsWith($parentWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    throw $Message
}

function Test-ExcludedRelativePath {
    param(
        [string]$RelativePath,
        [string[]]$ExcludePatterns
    )

    foreach ($pattern in $ExcludePatterns) {
        if ($RelativePath -like $pattern) {
            return $true
        }
    }
    return $false
}

function Copy-FilteredTree {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludePatterns = @()
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source directory is missing: $Source"
    }

    $resolvedSource = (Resolve-FullPath $Source).TrimEnd('\')
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Get-ChildItem -LiteralPath $Source -Force -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($resolvedSource.Length).TrimStart('\')
        if (Test-ExcludedRelativePath -RelativePath $relativePath -ExcludePatterns $ExcludePatterns) {
            return
        }

        $target = Join-Path $Destination $relativePath
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            return
        }

        $targetDirectory = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}

function Copy-RequiredFile {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Required file is missing: $Source"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Get-OptionalFileHash {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ''
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$RepoRoot = Resolve-FullPath $RepoRoot
$AshitaRoot = Resolve-FullPath $AshitaRoot
if ($OutputDirectory -eq '') {
    $OutputDirectory = Join-Path $RepoRoot 'dist'
}
$OutputDirectory = Resolve-FullPath $OutputDirectory

$reloadedRoot = Join-Path $RepoRoot 'external\Reloaded-II'
$buildReloadedScript = Join-Path $RepoRoot 'tools\build_pol_reloaded.ps1'
$buildBootloaderScript = Join-Path $RepoRoot 'tools\build_pol_reloaded_bootloader.ps1'
$installerScript = Join-Path $RepoRoot 'installer\install_accessxi.ps1'
$setupGuide = Join-Path $RepoRoot 'setup-guide.md'
$ashitaGuiProfile = Join-Path $RepoRoot 'installer\ashita_boot\AccessXI Retail.xml'
$ashitaCliProfile = Join-Path $RepoRoot 'installer\ashita_boot\accessxi-retail.ini'
$ashitaLauncher = Join-Path $RepoRoot 'installer\ashita_launcher\AccessXI.cmd'
$ashitaStartupScript = Join-Path $RepoRoot 'installer\ashita_scripts\default.txt'
$vcRedistX86 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x86.exe'
$vcRedistX64 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x64.exe'
$dotNetDesktopRuntimeX86 = Join-Path $RepoRoot 'installer\prerequisites\windowsdesktop-runtime-9.0.17-win-x86.exe'
$dotNetDesktopRuntimeX64 = Join-Path $RepoRoot 'installer\prerequisites\windowsdesktop-runtime-9.0.17-win-x64.exe'
$repoDataRoot = Join-Path $RepoRoot 'data'
$repoSoundsRoot = Join-Path $RepoRoot 'sounds'
$repoDatIndex = Join-Path $RepoRoot 'pol_re\out\dat_index\ffxi_dat_strings.tsv'
$repoNavMeshDll = Join-Path $RepoRoot 'third_party\FFXI-NavMesh-Builder\FFXINAV.dll'
$repoNavMeshesRoot = Join-Path $RepoRoot 'third_party\xiNavmeshes'
$repoLsbSqlRoot = Join-Path $RepoRoot 'third_party\LandSandBoat-server\sql'
$windowerResourcesRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'windower\res'
$builtBootloaderAsi = Join-Path $RepoRoot 'tools\pol_asi_probe\AccessXI.PolReloadedBootstrap.asi'
$packageRoot = Join-Path $OutputDirectory 'AccessXI-Ashita-Reloaded-Installer'
$zipPath = Join-Path $OutputDirectory 'AccessXI-Ashita-Reloaded-Installer.zip'

if (-not (Test-Path -LiteralPath (Join-Path $AshitaRoot 'Ashita-cli.exe'))) {
    throw "Ashita-cli.exe is missing from AshitaRoot: $AshitaRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $AshitaRoot 'addons\accessxi_reader\accessxi_reader.lua'))) {
    throw "AccessXI Ashita addon is missing from AshitaRoot: $AshitaRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $reloadedRoot 'Reloaded-II.exe'))) {
    throw "Reloaded-II is missing from repo external folder: $reloadedRoot"
}
if (-not (Test-Path -LiteralPath $installerScript)) {
    throw "Installer script is missing: $installerScript"
}
if (-not (Test-Path -LiteralPath $setupGuide)) {
    throw "Setup guide is missing: $setupGuide"
}
if (-not (Test-Path -LiteralPath $ashitaGuiProfile)) {
    throw "Clean Ashita GUI profile is missing: $ashitaGuiProfile"
}
if (-not (Test-Path -LiteralPath $ashitaCliProfile)) {
    throw "Clean Ashita CLI profile is missing: $ashitaCliProfile"
}
if (-not (Test-Path -LiteralPath $ashitaLauncher)) {
    throw "AccessXI Ashita CLI launcher is missing: $ashitaLauncher"
}
if (-not (Test-Path -LiteralPath $ashitaStartupScript)) {
    throw "AccessXI Ashita startup script is missing: $ashitaStartupScript"
}
if (-not (Test-Path -LiteralPath $vcRedistX86)) {
    throw "x86 Visual C++ redistributable prerequisite is missing: $vcRedistX86"
}
if (-not (Test-Path -LiteralPath $vcRedistX64)) {
    throw "x64 Visual C++ redistributable prerequisite is missing: $vcRedistX64"
}
if (-not (Test-Path -LiteralPath $dotNetDesktopRuntimeX86)) {
    throw "x86 .NET Desktop Runtime prerequisite is missing: $dotNetDesktopRuntimeX86"
}
if (-not (Test-Path -LiteralPath $dotNetDesktopRuntimeX64)) {
    throw "x64 .NET Desktop Runtime prerequisite is missing: $dotNetDesktopRuntimeX64"
}
if (-not (Test-Path -LiteralPath $repoDataRoot)) {
    throw "AccessXI data folder is missing: $repoDataRoot"
}
if (-not (Test-Path -LiteralPath $repoSoundsRoot)) {
    throw "AccessXI sounds folder is missing: $repoSoundsRoot"
}
if (-not (Test-Path -LiteralPath $repoDatIndex)) {
    throw "DAT string index is missing: $repoDatIndex"
}
if (-not (Test-Path -LiteralPath $repoNavMeshDll)) {
    throw "FFXINAV.dll is missing: $repoNavMeshDll"
}
if (-not (Test-Path -LiteralPath $repoNavMeshesRoot)) {
    throw "Nav mesh directory is missing: $repoNavMeshesRoot"
}
if (-not (Test-Path -LiteralPath $repoLsbSqlRoot)) {
    throw "LandSandBoat SQL folder is missing: $repoLsbSqlRoot"
}
if (-not (Test-Path -LiteralPath $windowerResourcesRoot)) {
    throw "Windower resource folder is missing: $windowerResourcesRoot"
}

if (-not $NoBuild) {
    & $buildReloadedScript -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    & $buildBootloaderScript -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll'))) {
    throw 'Built AccessXI Reloaded POL mod is missing. Run build_pol_reloaded.ps1 first.'
}
if (-not (Test-Path -LiteralPath (Join-Path $reloadedRoot 'Mods\AccessXI.PolReloaded\prism.dll'))) {
    throw 'Built AccessXI Reloaded POL mod is missing package-local prism.dll. Run build_pol_reloaded.ps1 first.'
}
if (-not (Test-Path -LiteralPath (Join-Path $reloadedRoot 'Mods\reloaded.sharedlib.hooks\ModConfig.json'))) {
    throw 'Reloaded shared hooks dependency is missing from the portable Reloaded-II Mods folder.'
}
if (-not (Test-Path -LiteralPath $builtBootloaderAsi)) {
    throw 'Built AccessXI delayed POL bootloader is missing. Run build_pol_reloaded_bootloader.ps1 first.'
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
Assert-UnderDirectory -Path $packageRoot -Parent $OutputDirectory -Message "Refusing to clean package root outside output directory: $packageRoot"
if (Test-Path -LiteralPath $packageRoot) {
    Remove-Item -LiteralPath $packageRoot -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

$payloadRoot = Join-Path $packageRoot 'payload'
$payloadAshita = Join-Path $payloadRoot 'Ashita'
$payloadReloaded = Join-Path $payloadRoot 'Reloaded-II'
$payloadBootloader = Join-Path $payloadRoot 'pol_bootloader'
$payloadPrerequisites = Join-Path $payloadRoot 'Prerequisites'
$payloadAddon = Join-Path $payloadAshita 'addons\accessxi_reader'

New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null

$ashitaExcludePatterns = @(
    'Ashita.exe*',
    'logs',
    'logs\*',
    'screenshots',
    'screenshots\*',
    'updates',
    'updates\*',
    'docs',
    'docs\*',
    'config\boot\*.ini',
    'config\boot\*.xml',
    'config\boot\New Configuration *.xml',
    'addons\accessxi_reader\logs',
    'addons\accessxi_reader\logs\*',
    'addons\accessxi_reader\ffxi-menu-reader.boot.log',
    'addons\accessxi_reader\*.boot.log',
    'polplugins\accessxi_pol_nvda.dll',
    'polplugins\accessxi_pol_nvda.dll*',
    '*.bak',
    '*.bak.*',
    '*.bak*',
    '*~'
)
$reloadedExcludePatterns = @(
    'User\Logs',
    'User\Logs\*',
    'Logs',
    'Logs\*',
    'pol-reloaded-native-speech.queue',
    'pol-reloaded-speech.log',
    'pol-monitor.log',
    'Apps\AccessXI.PolPreLogin\AppConfig.json',
    '*.log',
    '*.queue',
    '*.dmp'
)

Copy-FilteredTree -Source $AshitaRoot -Destination $payloadAshita -ExcludePatterns $ashitaExcludePatterns
$payloadWin32Types = Join-Path $payloadAshita 'addons\libs\win32types.lua'
if (-not (Test-Path -LiteralPath $payloadWin32Types)) {
    throw "Ashita win32types.lua is missing from the packaged payload: $payloadWin32Types"
}
$win32TypesSource = [System.IO.File]::ReadAllText($payloadWin32Types)
$win32TypesRepaired = $win32TypesSource `
    -replace 'typedef\s+const\s+IID\s*&\s*REFIID\s*;', 'typedef const IID* REFIID;' `
    -replace 'typedef\s+const\s+GUID\s*&\s*REFGUID\s*;', 'typedef const GUID* REFGUID;'
if ($win32TypesRepaired -notmatch 'typedef\s+const\s+IID\s*\*\s*REFIID' -or
    $win32TypesRepaired -notmatch 'typedef\s+const\s+GUID\s*\*\s*REFGUID') {
    throw "Unable to make packaged Ashita win32types.lua C-compatible for LuaJIT ffi.cdef: $payloadWin32Types"
}
if ($win32TypesRepaired -cne $win32TypesSource) {
    [System.IO.File]::WriteAllText($payloadWin32Types, $win32TypesRepaired, (New-Object System.Text.UTF8Encoding($false)))
}
Copy-FilteredTree -Source $reloadedRoot -Destination $payloadReloaded -ExcludePatterns $reloadedExcludePatterns
$payloadAshitaAddons = Join-Path $payloadAshita 'addons'
if (Test-Path -LiteralPath $payloadAshitaAddons) {
    Get-ChildItem -LiteralPath $payloadAshitaAddons -Directory | Where-Object {
        $_.Name -notin @('accessxi_reader', 'libs')
    } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}
Copy-FilteredTree -Source $repoDataRoot -Destination (Join-Path $payloadAddon 'data')
Copy-FilteredTree -Source $repoSoundsRoot -Destination (Join-Path $payloadAddon 'sounds') -ExcludePatterns @('*.bak*', '*.log', '*.tmp')
Copy-FilteredTree -Source $repoNavMeshesRoot -Destination (Join-Path $payloadAddon 'third_party\xiNavmeshes')
Copy-RequiredFile -Source $repoDatIndex -Destination (Join-Path $payloadAddon 'resources\dat_index\ffxi_dat_strings.tsv')
Copy-RequiredFile -Source $repoNavMeshDll -Destination (Join-Path $payloadAddon 'third_party\FFXI-NavMesh-Builder\FFXINAV.dll')
Copy-RequiredFile -Source (Join-Path $repoLsbSqlRoot 'abilities.sql') -Destination (Join-Path $payloadAddon 'third_party\LandSandBoat-server\sql\abilities.sql')
Copy-RequiredFile -Source (Join-Path $repoLsbSqlRoot 'job_point_gifts.sql') -Destination (Join-Path $payloadAddon 'third_party\LandSandBoat-server\sql\job_point_gifts.sql')
foreach ($resourceName in @('items.lua', 'item_descriptions.lua', 'merit_points.lua', 'job_points.lua', 'key_items.lua', 'job_traits.lua', 'auto_translates.lua')) {
    Copy-RequiredFile -Source (Join-Path $windowerResourcesRoot $resourceName) -Destination (Join-Path $payloadAddon "resources\windower\$resourceName")
}
New-Item -ItemType Directory -Force -Path (Join-Path $payloadAddon 'logs\searchhook') | Out-Null
Copy-RequiredFile -Source $ashitaGuiProfile -Destination (Join-Path $payloadAshita 'config\boot\AccessXI Retail.xml')
Copy-RequiredFile -Source $ashitaCliProfile -Destination (Join-Path $payloadAshita 'config\boot\accessxi-retail.ini')
Copy-RequiredFile -Source $ashitaLauncher -Destination (Join-Path $payloadAshita 'AccessXI.cmd')
Copy-RequiredFile -Source $ashitaStartupScript -Destination (Join-Path $payloadAshita 'scripts\default.txt')
Copy-RequiredFile -Source $installerScript -Destination (Join-Path $packageRoot 'install_accessxi.ps1')
Copy-RequiredFile -Source $setupGuide -Destination (Join-Path $packageRoot 'setup-guide.md')
Copy-RequiredFile -Source $builtBootloaderAsi -Destination (Join-Path $payloadBootloader 'AccessXI.PolReloadedBootstrap.asi')
Copy-RequiredFile -Source $vcRedistX86 -Destination (Join-Path $payloadPrerequisites 'vc_redist.x86.exe')
Copy-RequiredFile -Source $vcRedistX64 -Destination (Join-Path $payloadPrerequisites 'vc_redist.x64.exe')
Copy-RequiredFile -Source $dotNetDesktopRuntimeX86 -Destination (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x86.exe')
Copy-RequiredFile -Source $dotNetDesktopRuntimeX64 -Destination (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x64.exe')

$manifest = [ordered]@{
    CreatedAt = (Get-Date).ToString('o')
    AshitaCliHash = Get-OptionalFileHash (Join-Path $payloadAshita 'Ashita-cli.exe')
    AccessXILauncherHash = Get-OptionalFileHash (Join-Path $payloadAshita 'AccessXI.cmd')
    AccessXICliProfileHash = Get-OptionalFileHash (Join-Path $payloadAshita 'config\boot\accessxi-retail.ini')
    AccessXIStartupScriptHash = Get-OptionalFileHash (Join-Path $payloadAshita 'scripts\default.txt')
    AccessXIReaderHash = Get-OptionalFileHash (Join-Path $payloadAshita 'addons\accessxi_reader\accessxi_reader.lua')
    AccessXIDataHash = Get-OptionalFileHash (Join-Path $payloadAddon 'data\ffxi-nav-destinations.tsv')
    AccessXIDatIndexHash = Get-OptionalFileHash (Join-Path $payloadAddon 'resources\dat_index\ffxi_dat_strings.tsv')
    ReloadedExeHash = Get-OptionalFileHash (Join-Path $payloadReloaded 'Reloaded-II.exe')
    PolReloadedModHash = Get-OptionalFileHash (Join-Path $payloadReloaded 'Mods\AccessXI.PolReloaded\AccessXI.PolReloaded.dll')
    PolReloadedPrismHash = Get-OptionalFileHash (Join-Path $payloadReloaded 'Mods\AccessXI.PolReloaded\prism.dll')
    PolBootloaderHash = Get-OptionalFileHash (Join-Path $payloadBootloader 'AccessXI.PolReloadedBootstrap.asi')
    VisualCppRedistX86Hash = Get-OptionalFileHash (Join-Path $payloadPrerequisites 'vc_redist.x86.exe')
    VisualCppRedistX64Hash = Get-OptionalFileHash (Join-Path $payloadPrerequisites 'vc_redist.x64.exe')
    DotNetDesktopRuntimeX86Hash = Get-OptionalFileHash (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x86.exe')
    DotNetDesktopRuntimeX64Hash = Get-OptionalFileHash (Join-Path $payloadPrerequisites 'windowsdesktop-runtime-9.0.17-win-x64.exe')
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding UTF8

Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -Force

[pscustomobject]@{
    PackageRoot = $packageRoot
    ZipPath = $zipPath
    Manifest = Join-Path $packageRoot 'manifest.json'
}

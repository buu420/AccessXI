param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$AshitaRoot = 'C:\Users\buu42\Ashita',
    [string]$WindowerResourcesRoot = '',
    [string]$SharedAssetsRoot = '',
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

    foreach ($component in ($RelativePath -split '[\\/]')) {
        if ($component -in @('.git', '.hg', '.svn')) {
            return $true
        }
    }

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
if ($SharedAssetsRoot -eq '') { $SharedAssetsRoot = $RepoRoot }
$SharedAssetsRoot = Resolve-FullPath $SharedAssetsRoot
if ($OutputDirectory -eq '') {
    $OutputDirectory = Join-Path $RepoRoot 'dist'
}
$OutputDirectory = Resolve-FullPath $OutputDirectory

$buildNativeScript = Join-Path $RepoRoot 'tools\build_pol_native_asi.ps1'
$testNativeStructureScript = Join-Path $RepoRoot 'tools\test_pol_native_asi_structure.ps1'
$nativeStage = Join-Path $RepoRoot 'stage\pol-native'
$buildCollisionScript = Join-Path $RepoRoot 'tools\build_collision_native.ps1'
$collisionStage = Join-Path $RepoRoot 'stage\collision-native'
$stagedCollisionNative = Join-Path $collisionStage 'accessxi_collision_native.dll'
$collisionManifest = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\data\collision-native-manifest.tsv'
$fetchAsiLoaderScript = Join-Path $RepoRoot 'tools\fetch_ultimate_asi_loader.ps1'
$ultimateAsiLoaderVersion = 'v9.7.2'
$ultimateAsiLoaderArchiveSha256 = '0F34758B30EAA0EFB59F7AE04100DB789914E1A08891B89878B8FDB189C2A7C5'
$ultimateAsiLoaderDllSha256 = 'C7277E832F6F07AF64903A99ECEBAB2936260CBF55EDA70787C5D7B2D5B9FE60'
$asiLoaderSource = Join-Path $SharedAssetsRoot "third_party\Ultimate-ASI-Loader\$ultimateAsiLoaderVersion\x86\dinput8.dll"
$sourcePrism = Join-Path $SharedAssetsRoot 'third_party\prism\build-win32\Release\prism.dll'
$asiLoaderLicense = Join-Path $RepoRoot 'third-party-notices\Ultimate-ASI-Loader-LICENSE.txt'
$bgWikiGuideNotice = Join-Path $RepoRoot 'third-party-notices\BG-Wiki-objective-guides-CC-BY-NC-SA-3.0.txt'
$ffxiclopediaGuideNotice = Join-Path $RepoRoot 'third-party-notices\FFXIclopedia-objective-guides-CC-BY-SA-3.0.txt'
$installerScript = Join-Path $RepoRoot 'installer\install_accessxi.ps1'
$legacyCleanupScript = Join-Path $RepoRoot 'installer\legacy_accessxi_cleanup.ps1'
$publicGuide = Join-Path $RepoRoot 'README.md'
$ashitaGuiProfile = Join-Path $RepoRoot 'installer\ashita_boot\AccessXI Retail.xml'
$ashitaCliProfile = Join-Path $RepoRoot 'installer\ashita_boot\accessxi-retail.ini'
$ashitaLauncher = Join-Path $RepoRoot 'installer\ashita_launcher\AccessXI.cmd'
$ashitaStartupScript = Join-Path $RepoRoot 'installer\ashita_scripts\default.txt'
$vcRedistX86 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x86.exe'
$vcRedistX64 = Join-Path $RepoRoot 'installer\prerequisites\vc_redist.x64.exe'
$repoAddonRoot = Join-Path $RepoRoot 'ashita\addons\accessxi_reader'
$repoDataRoot = Join-Path $RepoRoot 'data'
$repoSoundsRoot = Join-Path $RepoRoot 'sounds'
$repoDatIndex = Join-Path $SharedAssetsRoot 'pol_re\out\dat_index\ffxi_dat_strings.tsv'
$repoNavMeshDll = Join-Path $SharedAssetsRoot 'third_party\FFXI-NavMesh-Builder\FFXINAV.dll'
$repoNavMeshesRoot = Join-Path $SharedAssetsRoot 'third_party\xiNavmeshes'
$repoLsbSqlRoot = Join-Path $SharedAssetsRoot 'third_party\LandSandBoat-server\sql'
if ($WindowerResourcesRoot -eq '') {
    $WindowerResourcesRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'windower\res'
}
$windowerResourcesRoot = Resolve-FullPath $WindowerResourcesRoot
$packageRoot = Join-Path $OutputDirectory 'AccessXI-Ashita-Installer'
$zipPath = Join-Path $OutputDirectory 'AccessXI-Ashita-Installer.zip'

if (-not (Test-Path -LiteralPath (Join-Path $AshitaRoot 'Ashita-cli.exe'))) {
    throw "Ashita-cli.exe is missing from AshitaRoot: $AshitaRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $AshitaRoot 'addons\accessxi_reader\accessxi_reader.lua'))) {
    throw "AccessXI Ashita addon is missing from AshitaRoot: $AshitaRoot"
}
if (-not (Test-Path -LiteralPath $installerScript)) {
    throw "Installer script is missing: $installerScript"
}
if (-not (Test-Path -LiteralPath $legacyCleanupScript)) {
    throw "Legacy AccessXI cleanup library is missing: $legacyCleanupScript"
}
if (-not (Test-Path -LiteralPath $buildNativeScript)) {
    throw "Native PlayOnline build script is missing: $buildNativeScript"
}
if (-not (Test-Path -LiteralPath $testNativeStructureScript)) {
    throw "Native PlayOnline structure test is missing: $testNativeStructureScript"
}
if (-not (Test-Path -LiteralPath $buildCollisionScript -PathType Leaf)) {
    throw "Collision navigation native build script is missing: $buildCollisionScript"
}
if (-not (Test-Path -LiteralPath $collisionManifest -PathType Leaf)) {
    throw "Collision navigation native manifest is missing: $collisionManifest"
}
if (-not (Test-Path -LiteralPath $fetchAsiLoaderScript -PathType Leaf)) {
    throw "Ultimate ASI Loader fetch script is missing: $fetchAsiLoaderScript"
}
if (-not (Test-Path -LiteralPath $asiLoaderLicense -PathType Leaf)) {
    throw "Ultimate ASI Loader license notice is missing: $asiLoaderLicense"
}
foreach ($guideNotice in @($bgWikiGuideNotice, $ffxiclopediaGuideNotice)) {
    if (-not (Test-Path -LiteralPath $guideNotice -PathType Leaf)) {
        throw "Objective guide source license notice is missing: $guideNotice"
    }
}
if (-not (Test-Path -LiteralPath $asiLoaderSource -PathType Leaf)) {
    & $fetchAsiLoaderScript -RepoRoot $SharedAssetsRoot -Version $ultimateAsiLoaderVersion -ArchiveSha256 $ultimateAsiLoaderArchiveSha256 -DllSha256 $ultimateAsiLoaderDllSha256
    if (-not $?) { throw 'Unable to fetch the pinned official x86 Ultimate ASI Loader.' }
}
$actualAsiLoaderHash = (Get-FileHash -LiteralPath $asiLoaderSource -Algorithm SHA256).Hash
if ($actualAsiLoaderHash -ne $ultimateAsiLoaderDllSha256) {
    throw "Ultimate ASI Loader cache hash mismatch. Expected $ultimateAsiLoaderDllSha256, got $actualAsiLoaderHash."
}
if (-not (Test-Path -LiteralPath $repoAddonRoot)) {
    throw "Canonical AccessXI addon source is missing: $repoAddonRoot"
}
if (-not (Test-Path -LiteralPath $publicGuide)) {
    throw "Public setup guide is missing: $publicGuide"
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
    & $buildNativeScript -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    & $buildCollisionScript -RepoRoot $RepoRoot -StageRoot $collisionStage
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

& $testNativeStructureScript -RepoRoot $RepoRoot -StageRoot $nativeStage -PrismDll $sourcePrism
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$collisionManifestRows = @(Import-Csv -LiteralPath $collisionManifest -Delimiter "`t")
if ($collisionManifestRows.Count -ne 1) {
    throw "Collision navigation manifest must contain exactly one payload row: $collisionManifest"
}
$expectedCollisionHash = ([string]$collisionManifestRows[0].sha256).ToUpperInvariant()
if (-not (Test-Path -LiteralPath $stagedCollisionNative -PathType Leaf)) {
    throw "Staged collision navigation native DLL is missing: $stagedCollisionNative"
}
$actualCollisionHash = (Get-FileHash -LiteralPath $stagedCollisionNative -Algorithm SHA256).Hash
if ($actualCollisionHash -ne $expectedCollisionHash) {
    throw "Staged collision navigation native DLL hash mismatch. Expected $expectedCollisionHash, got $actualCollisionHash."
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
foreach ($directoryToClean in @($packageRoot)) {
    Assert-UnderDirectory -Path $directoryToClean -Parent $OutputDirectory -Message "Refusing to clean package root outside output directory: $directoryToClean"
    if (Test-Path -LiteralPath $directoryToClean) {
        Remove-Item -LiteralPath $directoryToClean -Recurse -Force
    }
}
foreach ($archiveToClean in @($zipPath)) {
    Assert-UnderDirectory -Path $archiveToClean -Parent $OutputDirectory -Message "Refusing to clean package archive outside output directory: $archiveToClean"
    if (Test-Path -LiteralPath $archiveToClean) {
        Remove-Item -LiteralPath $archiveToClean -Force
    }
}

$payloadRoot = Join-Path $packageRoot 'payload'
$payloadAshita = Join-Path $payloadRoot 'Ashita'
$payloadNative = Join-Path $payloadRoot 'PlayOnlineNative'
$payloadPrerequisites = Join-Path $payloadRoot 'Prerequisites'

# FILES THE ADDON WRITES AT RUNTIME NEVER SHIP.
#
# Each of these is declared in the reader as a *_cache_path / *_evidence_path /
# *_mode_path and opened with io.open(..., 'w') or 'a'. They are per-character
# state, not product data: the shipped copies carried real character names and
# their mission, quest, key-item, merit and Records of Eminence progress, which
# both leaks the packager's account and seeds every tester's install with
# somebody else's progression. Every read site guards a nil handle, so a fresh
# install simply recreates them.
$runtimeStateFiles = @(
    'ffxi-job-abilities-bits.txt',
    'ffxi-job-traits-bits.txt',
    'ffxi-key-items-packet.tsv',
    'ffxi-merits-packet.tsv',
    'ffxi-mission-main-packet.txt',
    'ffxi-nav-route-evidence.tsv',
    'ffxi-objective-interaction-progress.tsv',
    'ffxi-quest-packets.tsv',
    'ffxi-roe-active-packet.tsv',
    'nav-beacon-audio-mode.txt',
    'survival-guide-last-packet.tsv'
)
$runtimeStateExcludePatterns = @($runtimeStateFiles) + @($runtimeStateFiles | ForEach-Object { "data\$_" })
$addonExcludePatterns = @(
    'logs',
    'logs\*',
    'cache',
    'cache\*',
    'backups',
    'backups\*',
    '*.boot.log',
    '*.bak*',
    '*.tmp'
) + $runtimeStateExcludePatterns

$payloadAddon = Join-Path $payloadAshita 'addons\accessxi_reader'

New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null

$ashitaExcludePatterns = @(
    # Addons are assembled from Ashita's libraries and the reviewed repository
    # below. Avoid staging personal addons and then deleting them under sync.
    'addons',
    'addons\*',
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
    'polplugins\accessxi_pol*.dll*',
    # PERSONAL ASHITA STATE.
    #
    # config\addons holds per-character settings directories named
    # <Character>_<id>; config\sandbox and config\imgui.ini are machine state;
    # config\ashita\custom.* are this machine's signature overrides and can
    # break a tester whose client differs. The stock config\ashita\ashita.*.ini
    # signature files are deliberately kept, and the controlled AccessXI boot
    # profiles excluded by the config\boot rules above are copied back below.
    'config\addons',
    'config\addons\*',
    'config\sandbox',
    'config\sandbox\*',
    'config\imgui.ini',
    'config\ashita\custom.*',
    'addons\accessxi_reader\backups',
    'addons\accessxi_reader\backups\*',
    'addons\accessxi_reader\cache',
    'addons\accessxi_reader\cache\*',
    '*.bak',
    '*.bak.*',
    '*.bak*',
    '*~'
)
Copy-FilteredTree -Source $AshitaRoot -Destination $payloadAshita -ExcludePatterns $ashitaExcludePatterns
Copy-FilteredTree -Source (Join-Path $AshitaRoot 'addons\libs') -Destination (Join-Path $payloadAshita 'addons\libs') -ExcludePatterns @('*.bak*', '*.tmp', '*~')
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
$payloadAshitaAddons = Join-Path $payloadAshita 'addons'
if (Test-Path -LiteralPath $payloadAshitaAddons) {
    Get-ChildItem -LiteralPath $payloadAshitaAddons -Directory | Where-Object {
        $_.Name -notin @('accessxi_reader', 'libs')
    } | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force
    }
}
if (Test-Path -LiteralPath $payloadAddon) {
    Assert-UnderDirectory -Path $payloadAddon -Parent $payloadAshita -Message "Refusing to replace addon outside packaged Ashita: $payloadAddon"
    Remove-Item -LiteralPath $payloadAddon -Recurse -Force
}
Copy-FilteredTree -Source $repoAddonRoot -Destination $payloadAddon -ExcludePatterns $addonExcludePatterns
Copy-FilteredTree -Source $repoDataRoot -Destination (Join-Path $payloadAddon 'data') -ExcludePatterns $runtimeStateFiles
Copy-FilteredTree -Source $repoSoundsRoot -Destination (Join-Path $payloadAddon 'sounds') -ExcludePatterns @('*.bak*', '*.log', '*.tmp')
Copy-RequiredFile -Source $stagedCollisionNative -Destination (Join-Path $payloadAddon 'third_party\collision\accessxi_collision_native.dll')
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
Copy-RequiredFile -Source $legacyCleanupScript -Destination (Join-Path $packageRoot 'legacy_accessxi_cleanup.ps1')
Copy-RequiredFile -Source $publicGuide -Destination (Join-Path $packageRoot 'setup-guide.md')
Copy-RequiredFile -Source $asiLoaderLicense -Destination (Join-Path $packageRoot 'third-party-notices\Ultimate-ASI-Loader-LICENSE.txt')
Copy-RequiredFile -Source $bgWikiGuideNotice -Destination (Join-Path $packageRoot 'third-party-notices\BG-Wiki-objective-guides-CC-BY-NC-SA-3.0.txt')
Copy-RequiredFile -Source $ffxiclopediaGuideNotice -Destination (Join-Path $packageRoot 'third-party-notices\FFXIclopedia-objective-guides-CC-BY-SA-3.0.txt')
Copy-RequiredFile -Source $asiLoaderSource -Destination (Join-Path $payloadNative 'ddraw.dll')
Copy-RequiredFile -Source (Join-Path $nativeStage 'AccessXI.PolNative.asi') -Destination (Join-Path $payloadNative 'AccessXI.PolNative.asi')
Copy-RequiredFile -Source (Join-Path $nativeStage 'AccessXI.PolNative\accessxi_pol_native.dll') -Destination (Join-Path $payloadNative 'AccessXI.PolNative\accessxi_pol_native.dll')
Copy-RequiredFile -Source (Join-Path $nativeStage 'AccessXI.PolNative\prism.dll') -Destination (Join-Path $payloadNative 'AccessXI.PolNative\prism.dll')
Copy-RequiredFile -Source $vcRedistX86 -Destination (Join-Path $payloadPrerequisites 'vc_redist.x86.exe')
Copy-RequiredFile -Source $vcRedistX64 -Destination (Join-Path $payloadPrerequisites 'vc_redist.x64.exe')

# ---------------------------------------------------------------------------
# RELEASE GATE: every module the packaged reader loads must be in the payload.
#
# accessxi.load_code_module logs "module code load failed" and returns false
# when a module file is missing -- it does not raise. A payload assembled from
# a source tree that has fallen behind the reader therefore installs cleanly
# and runs with whole subsystems silently absent, which for a screen-reader
# addon is worse than a crash. This gate reads the module names out of the
# packaged main and proves each one resolves inside the payload.
function Assert-PackagedModuleReferences {
    param(
        [string]$PayloadAddonRoot
    )

    $mainPath = Join-Path $PayloadAddonRoot 'accessxi_reader.lua'
    if (-not (Test-Path -LiteralPath $mainPath -PathType Leaf)) {
        throw "Packaged addon is missing its main reader: $mainPath"
    }

    $mainSource = [System.IO.File]::ReadAllText($mainPath)
    $missing = [System.Collections.Generic.List[string]]::new()
    $checked = 0

    # load_code_module('x') and load_module_table('x') resolve to modules\x.lua;
    # load_menu_module_table('x') and load_menu_code_module('x') resolve to
    # modules\menus\x.lua. Both data tables and executable readers are required.
    $loaders = @(
        @{ Pattern = "load_code_module\('([A-Za-z0-9_%-]+)'"; Relative = 'modules' },
        @{ Pattern = "load_module_table\('([A-Za-z0-9_%-]+)'"; Relative = 'modules' },
        @{ Pattern = "load_menu_module_table\('([A-Za-z0-9_%-]+)'"; Relative = 'modules\menus' },
        @{ Pattern = "load_menu_code_module\('([A-Za-z0-9_%-]+)'"; Relative = 'modules\menus' }
    )
    foreach ($loader in $loaders) {
        $names = [regex]::Matches($mainSource, $loader.Pattern) |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
        foreach ($name in $names) {
            $checked++
            $modulePath = Join-Path (Join-Path $PayloadAddonRoot $loader.Relative) ($name + '.lua')
            if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
                $missing.Add("$($loader.Relative)\$name.lua")
            }
        }
    }

    if ($missing.Count -gt 0) {
        throw ("Packaged reader loads modules that are not in the payload: " +
            ($missing -join ', ') +
            ". The canonical addon source is behind the reader; sync it forward before packaging.")
    }
    if ($checked -eq 0) {
        throw "Packaged reader declares no module references; the module gate cannot be trusted."
    }

    # Navigation runtime inputs whose absence stops routing outright. Asserted
    # only when the packaged reader actually references the file, so optional
    # navigation data (discoveries, manual steps, recorded marks) is not turned
    # into a false release blocker.
    $requiredNavigationData = @(
        'ffxi-nav-destinations.tsv',
        'ffxi-nav-points.tsv',
        'ffxi-nav-zoneline-graph.tsv'
    )
    foreach ($dataFile in $requiredNavigationData) {
        if ($mainSource -notmatch [regex]::Escape($dataFile)) {
            continue
        }
        $dataPath = Join-Path (Join-Path $PayloadAddonRoot 'data') $dataFile
        if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
            throw "Packaged reader loads navigation data that is not in the payload: data\$dataFile"
        }
    }

    # Reviewed mission targets and measured entrance connectivity are read by
    # modules, so scanning only the main Lua file cannot detect their absence.
    foreach ($dataFile in @('ffxi-objective-step-targets.tsv', 'ffxi-nav-destination-ingress.tsv')) {
        if (-not (Test-Path -LiteralPath (Join-Path $PayloadAddonRoot "data\$dataFile") -PathType Leaf)) {
            throw "Packaged mission navigation is missing required data: data\$dataFile"
        }
    }

    $navMeshDll = Join-Path $PayloadAddonRoot 'third_party\FFXI-NavMesh-Builder\FFXINAV.dll'
    if (-not (Test-Path -LiteralPath $navMeshDll -PathType Leaf)) {
        throw "Packaged addon is missing the navigation mesh native: $navMeshDll"
    }
    $navMeshRoot = Join-Path $PayloadAddonRoot 'third_party\xiNavmeshes'
    if (@(Get-ChildItem -LiteralPath $navMeshRoot -File -ErrorAction SilentlyContinue).Count -eq 0) {
        throw "Packaged addon has no navigation meshes: $navMeshRoot"
    }

    # The walk graph is a separate runtime input: the reader consults it only
    # when the walk-graph modules are loaded, so it is required exactly when
    # they are packaged and is not asserted otherwise.
    $loadsWalkGraph = $false
    foreach ($walkGraphModule in @('walk_graph', 'walk_graph_route')) {
        if ($mainSource -match ("load_code_module\('" + [regex]::Escape($walkGraphModule) + "'")) {
            $loadsWalkGraph = $true
        }
    }
    if ($loadsWalkGraph) {
        $walkGraphRoot = Join-Path (Join-Path $PayloadAddonRoot 'data') 'walkgraph'
        if (@(Get-ChildItem -LiteralPath $walkGraphRoot -File -Filter '*.axwg' -ErrorAction SilentlyContinue).Count -eq 0) {
            throw "Packaged reader loads the walk graph but the payload has no data\walkgraph\*.axwg files."
        }
    }

    return $checked
}

$moduleReferenceCount = Assert-PackagedModuleReferences -PayloadAddonRoot $payloadAddon
Write-Host "ok: packaged reader resolves $moduleReferenceCount module references and its required navigation inputs."

$manifest = [ordered]@{
    CreatedAt = (Get-Date).ToString('o')
    AshitaCliHash = Get-OptionalFileHash (Join-Path $payloadAshita 'Ashita-cli.exe')
    AccessXILauncherHash = Get-OptionalFileHash (Join-Path $payloadAshita 'AccessXI.cmd')
    AccessXICliProfileHash = Get-OptionalFileHash (Join-Path $payloadAshita 'config\boot\accessxi-retail.ini')
    AccessXIStartupScriptHash = Get-OptionalFileHash (Join-Path $payloadAshita 'scripts\default.txt')
    AccessXIReaderHash = Get-OptionalFileHash (Join-Path $payloadAshita 'addons\accessxi_reader\accessxi_reader.lua')
    AccessXIDataHash = Get-OptionalFileHash (Join-Path $payloadAddon 'data\ffxi-nav-destinations.tsv')
    CollisionNativeHash = Get-OptionalFileHash (Join-Path $payloadAddon 'third_party\collision\accessxi_collision_native.dll')
    CollisionNativeManifestHash = Get-OptionalFileHash (Join-Path $payloadAddon 'data\collision-native-manifest.tsv')
    AccessXIDatIndexHash = Get-OptionalFileHash (Join-Path $payloadAddon 'resources\dat_index\ffxi_dat_strings.tsv')
    UltimateAsiLoaderVersion = $ultimateAsiLoaderVersion
    PolAsiLoaderHash = Get-OptionalFileHash (Join-Path $payloadNative 'ddraw.dll')
    PolAsiLoaderLicenseHash = Get-OptionalFileHash (Join-Path $packageRoot 'third-party-notices\Ultimate-ASI-Loader-LICENSE.txt')
    BgWikiObjectiveGuideNoticeHash = Get-OptionalFileHash (Join-Path $packageRoot 'third-party-notices\BG-Wiki-objective-guides-CC-BY-NC-SA-3.0.txt')
    FFXIclopediaObjectiveGuideNoticeHash = Get-OptionalFileHash (Join-Path $packageRoot 'third-party-notices\FFXIclopedia-objective-guides-CC-BY-SA-3.0.txt')
    PolNativeAsiHash = Get-OptionalFileHash (Join-Path $payloadNative 'AccessXI.PolNative.asi')
    PolNativeHookHash = Get-OptionalFileHash (Join-Path $payloadNative 'AccessXI.PolNative\accessxi_pol_native.dll')
    PolNativePrismHash = Get-OptionalFileHash (Join-Path $payloadNative 'AccessXI.PolNative\prism.dll')
    VisualCppRedistX86Hash = Get-OptionalFileHash (Join-Path $payloadPrerequisites 'vc_redist.x86.exe')
    VisualCppRedistX64Hash = Get-OptionalFileHash (Join-Path $payloadPrerequisites 'vc_redist.x64.exe')
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'manifest.json') -Encoding UTF8

Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -Force

[pscustomobject]@{
    PackageRoot = $packageRoot
    ZipPath = $zipPath
    Manifest = Join-Path $packageRoot 'manifest.json'
}

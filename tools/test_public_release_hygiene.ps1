param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$PackageRoot = ''
)

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        throw $Message
    }
}

$root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
$forbiddenPaths = @(
    'src\AccessXI.PolReloaded',
    'src\AccessXI.PolSpeechBridge',
    'tools\build_pol_reloaded.ps1',
    'tools\build_pol_reloaded_bootloader.ps1',
    'tools\deploy_pol_reloaded_bootloader.ps1',
    'tools\launch_pol_reloaded.ps1',
    'tools\pol_asi_probe',
    'tools\test_pol_reloaded_no_managed_log_tail.ps1',
    'tools\test_pol_reloaded_portable_diagnostics.ps1',
    'tools\test_pol_reloaded_split.ps1'
)
$trackedPaths = @(& git -C $root ls-files)
Assert-True ($LASTEXITCODE -eq 0) 'Unable to enumerate tracked repository paths.'
foreach ($relativePath in $forbiddenPaths) {
    $normalized = $relativePath.Replace('\', '/')
    $tracked = @($trackedPaths | Where-Object {
        $_ -eq $normalized -or $_.StartsWith($normalized + '/', [System.StringComparison]::OrdinalIgnoreCase)
    })
    Assert-True ($tracked.Count -eq 0) `
        "Obsolete Reloaded runtime artifact is still tracked: $relativePath"
}

$productionFiles = @($trackedPaths | Where-Object {
    $_.StartsWith('src/', [System.StringComparison]::OrdinalIgnoreCase) -or
    $_ -eq 'CMakeLists.txt' -or
    $_ -eq 'tools/build_pol_native_asi.ps1' -or
    $_ -eq 'tools/package_accessxi_installer.ps1' -or
    $_ -eq 'installer/AccessXIInstaller/Program.cs' -or
    $_ -eq 'README.md' -or
    $_ -eq 'setup-guide.md'
})
$productionSource = foreach ($relativePath in $productionFiles) {
    $path = Join-Path $root $relativePath.Replace('/', '\')
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $extension = [System.IO.Path]::GetExtension($path)
        if ($extension -in @('.cpp', '.h', '.cs', '.json', '.ps1', '.md', '.txt', '.def', '.csproj', '.targets', '.yml')) {
            Get-Content -LiteralPath $path -Raw
        }
    }
}
$productionText = $productionSource | Out-String
foreach ($pattern in @(
    'Reloaded\.Mod\.',
    'Reloaded\.Hooks',
    'Reloaded\.SharedLib',
    'RELOADEDIIMODS',
    'AccessXI_POL_ReloadedInitialize',
    'pol-reloaded-native-speech\.queue',
    'g_reloaded_',
    'append_reloaded_',
    'external\\Reloaded-II'
)) {
    Assert-NotContains $productionText $pattern "Production or release source still contains obsolete Reloaded runtime pattern: $pattern"
}

$packageScriptPath = Join-Path $root 'tools\package_accessxi_installer.ps1'
$packageSource = Get-Content -LiteralPath $packageScriptPath -Raw
Assert-True ($packageSource -match 'Ultimate-ASI-Loader') `
    'Package builder must obtain the ASI loader from the official Ultimate ASI Loader project.'
Assert-True ($packageSource -match 'repoAddonRoot') `
    'Package builder must stage the checked-in addon as the canonical latest addon source.'
Assert-True ($packageSource -match 'Ultimate-ASI-Loader-LICENSE\.txt') `
    'Package builder must ship the upstream ASI loader license.'
Assert-True ($packageSource -match 'BG-Wiki-objective-guides-CC-BY-NC-SA-3\.0\.txt') `
    'Package builder must ship the BG Wiki objective-guide source notice.'
Assert-True ($packageSource -match 'FFXIclopedia-objective-guides-CC-BY-SA-3\.0\.txt') `
    'Package builder must ship the FFXIclopedia objective-guide source notice.'

$licensePath = Join-Path $root 'third-party-notices\Ultimate-ASI-Loader-LICENSE.txt'
Assert-True (Test-Path -LiteralPath $licensePath -PathType Leaf) `
    'Ultimate ASI Loader license notice is missing.'

if (-not [string]::IsNullOrWhiteSpace($PackageRoot)) {
    $package = [System.IO.Path]::GetFullPath($PackageRoot)
    $packagedAddon = Join-Path $package 'payload\Ashita\addons\accessxi_reader'
    $sourceAddon = Join-Path $root 'ashita\addons\accessxi_reader'
    $sourceFiles = Get-ChildItem -LiteralPath $sourceAddon -Recurse -File |
        Where-Object {
            $_.FullName -notmatch '[\/]logs[\/]' -and
            $_.Name -notlike '*.bak*' -and
            $_.FullName.Substring($sourceAddon.Length).TrimStart('\') -notmatch '^(data|sounds|resources|third_party)[\\/]'
        }
    foreach ($sourceFile in $sourceFiles) {
        $relative = $sourceFile.FullName.Substring($sourceAddon.Length).TrimStart('\')
        $packagedFile = Join-Path $packagedAddon $relative
        Assert-True (Test-Path -LiteralPath $packagedFile -PathType Leaf) `
            "Packaged addon is missing current canonical source file: $relative"
        Assert-True ((Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash -eq `
            (Get-FileHash -LiteralPath $packagedFile -Algorithm SHA256).Hash) `
            "Packaged canonical addon file is stale: $relative"
    }
    # Independently re-derive the module gate against the produced package, so a
    # defect in the packager's own copy of this rule cannot blind both checks.
    $packagedMain = Join-Path $packagedAddon 'accessxi_reader.lua'
    Assert-True (Test-Path -LiteralPath $packagedMain -PathType Leaf) `
        'Packaged addon is missing accessxi_reader.lua.'
    $packagedMainSource = [System.IO.File]::ReadAllText($packagedMain)
    $moduleChecks = @(
        @{ Pattern = "load_code_module\('([A-Za-z0-9_%-]+)'"; Relative = 'modules' },
        @{ Pattern = "load_module_table\('([A-Za-z0-9_%-]+)'"; Relative = 'modules' },
        @{ Pattern = "load_menu_module_table\('([A-Za-z0-9_%-]+)'"; Relative = 'modules\menus' }
    )
    $referenced = 0
    foreach ($moduleCheck in $moduleChecks) {
        $names = [regex]::Matches($packagedMainSource, $moduleCheck.Pattern) |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique
        foreach ($name in $names) {
            $referenced++
            Assert-True (Test-Path -LiteralPath (Join-Path (Join-Path $packagedAddon $moduleCheck.Relative) ($name + '.lua')) -PathType Leaf) `
                "Packaged reader loads a module that is not in the package: $($moduleCheck.Relative)\$name.lua"
        }
    }
    Assert-True ($referenced -gt 0) `
        'Packaged reader declares no module references; the module gate cannot be trusted.'

    # Per-character runtime state must never reach a tester's install.
    foreach ($stateFile in @(
        'ffxi-job-abilities-bits.txt', 'ffxi-job-traits-bits.txt',
        'ffxi-key-items-packet.tsv', 'ffxi-merits-packet.tsv',
        'ffxi-mission-main-packet.txt', 'ffxi-nav-route-evidence.tsv',
        'ffxi-objective-interaction-progress.tsv', 'ffxi-quest-packets.tsv',
        'ffxi-roe-active-packet.tsv', 'nav-beacon-audio-mode.txt',
        'survival-guide-last-packet.tsv')) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path $packagedAddon 'data') $stateFile))) `
            "Packaged addon ships per-character runtime state: data\$stateFile"
    }
    foreach ($personalPath in @('config\addons', 'config\sandbox', 'config\imgui.ini',
        'addons\accessxi_reader\cache', 'addons\accessxi_reader\backups')) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path $package 'payload\Ashita') $personalPath))) `
            "Packaged payload ships personal Ashita state: $personalPath"
    }
    Assert-True (@(Get-ChildItem -LiteralPath (Join-Path (Join-Path $package 'payload\Ashita') 'config\ashita') -Filter 'custom.*' -ErrorAction SilentlyContinue).Count -eq 0) `
        'Packaged payload ships this machine''s custom Ashita signature overrides.'

    foreach ($overlayName in @('data', 'sounds')) {
        $overlayRoot = Join-Path $root $overlayName
        $overlayFiles = Get-ChildItem -LiteralPath $overlayRoot -Recurse -File |
            Where-Object { $_.Name -notlike '*.bak*' -and $_.Name -notlike '*.log' -and $_.Name -notlike '*.tmp' }
        foreach ($overlayFile in $overlayFiles) {
            $relative = $overlayFile.FullName.Substring($overlayRoot.Length).TrimStart('\')
            $packagedFile = Join-Path (Join-Path $packagedAddon $overlayName) $relative
            Assert-True (Test-Path -LiteralPath $packagedFile -PathType Leaf) `
                "Packaged addon is missing authoritative $overlayName file: $relative"
            Assert-True ((Get-FileHash -LiteralPath $overlayFile.FullName -Algorithm SHA256).Hash -eq `
                (Get-FileHash -LiteralPath $packagedFile -Algorithm SHA256).Hash) `
                "Packaged authoritative $overlayName file is stale: $relative"
        }
    }    Assert-True (Test-Path -LiteralPath (Join-Path $package 'third-party-notices\Ultimate-ASI-Loader-LICENSE.txt')) `
        'Packaged installer is missing the Ultimate ASI Loader license notice.'
    Assert-True (Test-Path -LiteralPath (Join-Path $package 'third-party-notices\BG-Wiki-objective-guides-CC-BY-NC-SA-3.0.txt')) `
        'Packaged installer is missing the BG Wiki objective-guide notice.'
    Assert-True (Test-Path -LiteralPath (Join-Path $package 'third-party-notices\FFXIclopedia-objective-guides-CC-BY-SA-3.0.txt')) `
        'Packaged installer is missing the FFXIclopedia objective-guide notice.'
    $runtimeRemnants = Get-ChildItem -LiteralPath $package -Recurse -Force |
        Where-Object { $_.FullName -match '(?i)AccessXI\.PolReloaded|Reloaded\.Mod\.Loader|Reloaded-II' }
    Assert-True (@($runtimeRemnants).Count -eq 0) `
        'Packaged installer contains an obsolete Reloaded runtime artifact.'
}

'ok: public release contains the current addon and no obsolete Reloaded runtime.'

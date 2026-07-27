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

$programPath = Join-Path $RepoRoot 'installer\AccessXIInstaller\Program.cs'
$packageScriptPath = Join-Path $RepoRoot 'tools\package_accessxi_installer.ps1'
$installerScriptPath = Join-Path $RepoRoot 'installer\install_accessxi.ps1'
$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$setupGuidePath = Join-Path $RepoRoot 'setup-guide.md'

Assert-True (Test-Path -LiteralPath $setupGuidePath) "Setup guide must live at the AccessXI root: $setupGuidePath"
Assert-True (Test-Path -LiteralPath $programPath) "Missing installer Program.cs: $programPath"
Assert-True (Test-Path -LiteralPath $packageScriptPath) "Missing package script: $packageScriptPath"
Assert-True (Test-Path -LiteralPath $installerScriptPath) "Missing installer script: $installerScriptPath"
Assert-True (Test-Path -LiteralPath $addonPath) "Missing live addon: $addonPath"

$programSource = Get-Content -LiteralPath $programPath -Raw
$packageSource = Get-Content -LiteralPath $packageScriptPath -Raw
$installerSource = Get-Content -LiteralPath $installerScriptPath -Raw
$addonSource = Get-Content -LiteralPath $addonPath -Raw
$setupGuideSource = Get-Content -LiteralPath $setupGuidePath -Raw

Assert-Contains $packageSource 'setup-guide\.md' 'Package builder must stage setup-guide.md at the package root.'
Assert-Contains $installerSource 'setup-guide\.md' 'Installer script must copy setup-guide.md into the installed AccessXI root.'
Assert-Contains $programSource 'openSetupGuideCheckBox' 'Installer finish screen must include an open-setup-guide checkbox.'
Assert-Contains $programSource 'Checked\s*=\s*true' 'Setup guide checkbox must be checked by default.'
Assert-Contains $programSource 'OpenSetupGuideAfterFinish' 'Finish button must open the setup guide when the checkbox is checked.'
Assert-Contains $programSource 'setup-guide\.md' 'Installer exe must know the installed setup-guide.md path.'
Assert-Contains $programSource 'AskPrerequisiteInstallChoice' 'Installer must ask to run missing dependency installers after Install is clicked.'
Assert-Contains $programSource 'RunPrerequisiteInstallers' 'Installer must run bundled dependency installers before install_accessxi.ps1.'
Assert-Contains $programSource 'RunInstaller\(installRoot,\s*polExe,\s*installMissingPrerequisites,\s*missingVisualCppRedistributables,\s*missingDotNetDesktopRuntimes\)' 'Installer must pass missing dependency information into the actual install run.'
Assert-NotContains $programSource 'HttpClient' 'Installer must not download dependencies during setup; it should run bundled installers.'
Assert-NotContains $programSource 'DownloadPrerequisitesAsync|CopyDownloadedPrerequisites|Use bundled offline installers' 'Installer must not ask users to choose between downloading and bundled dependencies.'

$presentStart = $addonSource.IndexOf("ashita.events.register('d3d_present'")
if ($presentStart -lt 0) {
    throw 'Could not locate d3d_present callback.'
}
$presentBody = $addonSource.Substring($presentStart)
foreach ($forbiddenProbePoll in @(
    'poll_equipment_probe_hotkey()',
    'poll_help_desk_shape_probe()',
    'poll_config_chat_filter_enter_probe()',
    'poll_meritcat_shape_key_probe()',
    'poll_meritcat_native_action_probe()',
    "log_chat_log_selection_probe('poll', false)"
)) {
    Assert-NotContains $presentBody ([regex]::Escape($forbiddenProbePoll)) "Frame loop must not run dormant probe poller: $forbiddenProbePoll"
}
$loadStart = $addonSource.IndexOf('function accessxi.run_load_startup')
if ($loadStart -lt 0) {
    throw 'Could not locate load startup function.'
}
$loadEnd = $addonSource.IndexOf("ashita.events.register('load'", $loadStart)
if ($loadEnd -lt 0) {
    throw 'Could not locate load event registration after load startup function.'
}
$loadBody = $addonSource.Substring($loadStart, $loadEnd - $loadStart)
Assert-NotContains $loadBody 'log_magic_shortcut_target_probe\(\)' 'Addon load must not run magic shortcut target probes in packaged builds.'
Assert-NotContains $loadBody "loaded probe=" 'Addon load log should not advertise active probe builds.'

if (Test-Path -LiteralPath $PackageRoot) {
    $packagedSetupGuide = Join-Path $PackageRoot 'setup-guide.md'
    Assert-True (Test-Path -LiteralPath $packagedSetupGuide) 'Packaged installer root must contain setup-guide.md.'
    Assert-True (
        (Get-FileHash -LiteralPath $packagedSetupGuide -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $setupGuidePath -Algorithm SHA256).Hash
    ) 'Packaged setup guide must exactly match the reviewed root setup-guide.md.'
    $payloadRoot = Join-Path $PackageRoot 'payload'
    foreach ($unneededDirectory in @('tools', 'ffxi_re', 'pol_re', 'tmp', 'scratch', 'video_frames')) {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $payloadRoot $unneededDirectory))) "Package payload must not contain repo-only directory: $unneededDirectory"
    }
    $payloadAshitaAddons = Join-Path $payloadRoot 'Ashita\addons'
    if (Test-Path -LiteralPath $payloadAshitaAddons) {
        $addonDirs = @(Get-ChildItem -LiteralPath $payloadAshitaAddons -Directory | Select-Object -ExpandProperty Name)
        $unexpected = @($addonDirs | Where-Object { $_ -notin @('accessxi_reader', 'libs') })
        Assert-True ($unexpected.Count -eq 0) "Package must not include unrelated Ashita addons: $($unexpected -join ', ')"
    }
    $ghidraItems = @(Get-ChildItem -LiteralPath $PackageRoot -Force -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'ghidra' -or $_.FullName -match '\\ghidra' })
    Assert-True ($ghidraItems.Count -eq 0) "Package must not contain Ghidra or reverse-engineering tool output; found $($ghidraItems.Count)."
}

'ok: AccessXI installer setup guide, dependency prompt, and cleanup checks passed.'

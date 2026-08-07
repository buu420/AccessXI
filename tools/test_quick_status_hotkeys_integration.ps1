param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$readerPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$reader = Get-Content -LiteralPath $readerPath -Raw

function Assert-Contains {
    param([string]$Needle, [string]$Message)
    if (-not $reader.Contains($Needle)) {
        throw $Message
    }
}

function Assert-NotContains {
    param([string]$Needle, [string]$Message)
    if ($reader.Contains($Needle)) {
        throw $Message
    }
}

Assert-Contains "accessxi.quick_status_hotkeys = accessxi.load_module_table('quick_status_hotkeys'" `
    'Reader does not load the quick-status hotkey module.'
Assert-Contains 'function accessxi.poll_quick_status_hotkeys()' `
    'Reader does not expose the quick-status polling adapter.'
Assert-Contains 'player:GetBuffs()' `
    'Reader does not consume the live player status array.'
Assert-Contains "GetString('buffs.names'" `
    'Reader does not resolve native localized status names.'
Assert-Contains 'GetStatusIconById' `
    'Reader does not consume native status cancelability metadata.'
Assert-Contains 'accessxi.is_foreground_process()' `
    'Quick-status handling is not guarded by foreground process state.'
Assert-Contains 'is_chat_input_open()' `
    'Quick-status handling is not guarded by chat-input state.'
Assert-Contains 'accessxi.poll_quick_status_hotkeys()' `
    'Presentation polling does not invoke the quick-status reader.'
Assert-Contains 'modifier_down = accessxi.accessibility_hotkey_modifier_held()' `
    'Quick-status polling does not reject modified letter presses.'
Assert-Contains "ashita.events.register('key_data', 'accessxi_accessibility_hotkeys_key_data_cb'" `
    'Initial DirectInput key presses are not routed through accessibility hotkey suppression.'
Assert-Contains "ashita.events.register('key_state', 'accessxi_accessibility_hotkeys_key_state_cb'" `
    'Held DirectInput key state is not routed through accessibility hotkey suppression.'
Assert-Contains 'accessxi.accessibility_hotkey_owns_vk' `
    'Status and navigation suppression do not share a guarded ownership predicate.'
Assert-Contains 'GetKeyboard():V2D(vk)' `
    'Accessibility hotkeys do not resolve virtual keys through Ashita DirectInput mapping.'
Assert-Contains 'ptr[dik] = 0;' `
    'Held accessibility keys are not removed from the DirectInput state seen by FFXI.'
$keyCallback = [regex]::Match(
    $reader,
    "(?s)ashita\.events\.register\('key',\s*'accessxi_reader_key_cb'.*?^end\);",
    [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $keyCallback.Success) {
    throw 'Could not locate the Ashita WNDPROC key callback.'
}
if ($keyCallback.Value.Contains('e.message')) {
    throw 'Ashita v4 key callback still reads the nonexistent e.message field.'
}
if (-not $keyCallback.Value.Contains('e.lparam')) {
    throw 'Ashita v4 key callback does not derive press/release state from lparam.'
}
$compactKeyCallback = $keyCallback.Value.Replace([string][char]13, '').
    Replace([string][char]10, '').Replace([string][char]9, '').Replace(' ', '')
if (-not $compactKeyCallback.Contains(
        'accessxi.accessibility_hotkey_owns_vk(key,accessxi.accessibility_hotkey_snapshot())')) {
    throw 'Owned accessibility letters are not blocked from FFXI chat through the WNDPROC key path.'
}

$presentIndex = $reader.IndexOf('accessxi.poll_quick_status_hotkeys()',
    $reader.IndexOf("ashita.events.register('d3d_present'"))
$statusIndex = $reader.IndexOf('accessxi.poll_status_hotkeys()',
    $reader.IndexOf("ashita.events.register('d3d_present'"))
if ($presentIndex -lt 0 -or $statusIndex -lt 0 -or $presentIndex -gt $statusIndex) {
    throw 'Quick-status polling must run before the existing menu-specific status hotkey poll.'
}

foreach ($virtualKey in @('0x44', '0x42', '0x48', '0x4D', '0x58')) {
    Assert-Contains $virtualKey "Reader does not contain required virtual key $virtualKey."
}

Write-Host 'Quick status hotkey integration checks passed'

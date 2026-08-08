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

Assert-Contains "accessxi.navigation_hotkeys = accessxi.load_module_table('navigation_hotkeys'" `
    'Reader does not load the navigation hotkey module.'
Assert-Contains 'accessxi.navigation_hotkey_state = accessxi.navigation_hotkeys.new_state()' `
    'Reader does not create shared navigation hotkey state.'
Assert-Contains 'accessxi.navigation_hotkeys.poll(' `
    'Navigation polling does not consume the tested I/U/O/J/K/L behavior.'
Assert-Contains "action == 'previous_category'" `
    'U is not dispatched to the previous navigation category.'
Assert-Contains "action == 'next_category'" `
    'O is not dispatched to the next navigation category.'
Assert-Contains "action == 'previous_item'" `
    'J is not dispatched to the previous item.'
Assert-Contains "action == 'repeat_item'" `
    'K is not dispatched to repeat the current item.'
Assert-Contains "action == 'next_item'" `
    'L is not dispatched to the next item.'
Assert-Contains "action == 'start_route'" `
    'I is not dispatched to start the selected route.'
Assert-Contains "action == 'stop_route'" `
    'I is not dispatched to stop active navigation.'
Assert-Contains 'route_active = accessxi.nav_active == true' `
    'I route action does not consume current active-route state.'
Assert-Contains 'route_pending = accessxi.nav_zone_search_target ~= nil' `
    'I cannot stop pending cross-zone navigation between route legs.'
Assert-Contains 'accessxi.navigation_hotkeys.should_claim_vk(' `
    'DirectInput suppression does not use the navigation ownership policy.'
Assert-Contains "accessxi.mission_quest_guide_index = accessxi.load_module_table('mission_quest_guide_index'" `
    'Reader does not load the complete native objective guide index.'
Assert-Contains "accessxi.mission_quest_guides_module = accessxi.load_module_table('mission_quest_guides'" `
    'Reader does not load the lazy objective step browser.'
Assert-Contains 'accessxi.objective_guides:is_open()' `
    'Navigation actions do not distinguish objective step view from the objective list.'
Assert-Contains "action == 'previous_category'" `
    'U does not exit objective step view to the same objective.'
Assert-Contains "action == 'next_category'" `
    'O does not exit objective step view and advance a category.'
Assert-Contains 'accessxi.objective_guides:move(-1)' `
    'J does not move to the previous objective step.'
Assert-Contains 'accessxi.objective_guides:repeat_step()' `
    'K does not repeat the current objective step.'
Assert-Contains 'accessxi.objective_guides:move(1)' `
    'L does not move to the next objective step.'

$pollBlock = [regex]::Match(
    $reader,
    '(?s)accessxi\.poll_nav_browser_hotkeys\s*=\s*function\s*\(\).*?^end',
    [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $pollBlock.Success) {
    throw 'Could not locate navigation browser polling.'
}
foreach ($oldKey in @('VK_NUMPAD7', 'VK_NUMPAD9', 'VK_NUMPAD1', 'VK_NUMPAD3')) {
    if ($pollBlock.Value.Contains($oldKey)) {
        throw "Navigation browser still polls obsolete category/item key $oldKey."
    }
}
if ($pollBlock.Value.Contains('VK_ADD') -or $pollBlock.Value.Contains('nav_keypad_control_down')) {
    throw 'Navigation browser still polls Ctrl+Numpad Plus as a duplicate route-start key.'
}

Write-Host 'Navigation hotkey integration checks passed'

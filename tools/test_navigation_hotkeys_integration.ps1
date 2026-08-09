param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$readerPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$reader = Get-Content -LiteralPath $readerPath -Raw
$navigationDataPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\navigation_data.lua'
$navigationData = Get-Content -LiteralPath $navigationDataPath -Raw

function Assert-Contains {
    param([string]$Needle, [string]$Message)
    if (-not $reader.Contains($Needle)) {
        throw $Message
    }
}

function Assert-NotContains {
    param([string]$Haystack, [string]$Needle, [string]$Message)
    if ($Haystack.Contains($Needle)) {
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
Assert-Contains 'route_resolver = function(native_key, guide_step_id, step)' `
    'The live guide resolver drops the selected step target before navigation.'
Assert-Contains 'accessxi.nav_mission_quest_guide_route_descriptor(native_key, guide_step_id, step)' `
    'The live guide resolver does not forward the selected step target to navigation.'
Assert-Contains 'packet_port == 0x00D0' `
    'The reader does not capture native nation mission completion state.'
Assert-Contains 'accessxi.mission_packet_nations_complete_player = mission_player' `
    'Nation mission completion state is not owned by the current player name.'
Assert-Contains 'accessxi.mission_packet_nations_complete_identity = mission_identity' `
    'Nation mission completion state is not owned by the World-qualified native identity.'
Assert-Contains "accessxi.mission_packet_nations_complete_source = 'packet_in_056'" `
    'Nation mission completion state is not marked as live packet evidence.'
Assert-Contains 'GetRankPoints()' `
    'Available nation mission detection does not read native rank points.'
if ($navigationData -notmatch "(?s)key\s*=\s*'mission'.*?label\s*=\s*'Missions'\s*\},\s*T\{\s*key\s*=\s*'quest'.*?label\s*=\s*'Quests'") {
    throw 'O category order must place Quests immediately after Missions.'
}

$startBlock = [regex]::Match(
    $reader,
    '(?s)local function nav_menu_start_route\(\).*?^end',
    [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $startBlock.Success) {
    throw 'Could not locate navigation route start handling.'
}
if (-not $startBlock.Value.Contains('accessxi.nav_mission_quest_prepare_route(item, objective_player)')) {
    throw 'I does not prepare the highlighted mission or quest directly for GPS.'
}
Assert-NotContains $startBlock.Value 'nav_mission_quest_open_guide' `
    'I still opens an objective guide instead of starting GPS directly.'
Assert-NotContains $startBlock.Value 'nav_mission_quest_prepare_guide_route' `
    'I still starts a manually selected guide step instead of the highlighted objective.'

$actionBlock = [regex]::Match(
    $reader,
    '(?s)local function nav_menu_handle_action\(action\).*?^end',
    [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $actionBlock.Success) {
    throw 'Could not locate navigation action dispatch.'
}
Assert-NotContains $actionBlock.Value 'objective_guides:move' `
    'J or L still browses guide steps instead of mission or quest rows.'
Assert-NotContains $actionBlock.Value 'objective_guides:repeat_step' `
    'K still repeats a guide step instead of the highlighted mission or quest.'

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

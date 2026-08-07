$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-Match `
    -Text $source `
    -Pattern "U selects the previous category\..*?O selects the next category\..*?J selects the previous destination\..*?K repeats\..*?L selects the next destination\..*?I starts the selected route or stops active navigation\." `
    -Message 'Nav browser prompt should describe the bare-letter controls with I as the only route start and stop key.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_menu_search_results\s*=\s*T\{\}' `
    -Message 'Nav browser should keep transient search results for the Search Results category.'

Assert-Match `
    -Text $source `
    -Pattern "key\s*=\s*'search-results'.*?label\s*=\s*'Search Results'" `
    -Message 'Nav browser should expose a transient Search Results category when search hits exist.'

Assert-NotMatch `
    -Text (Get-Content -LiteralPath 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\navigation_data.lua' -Raw) `
    -Pattern "Search Results" `
    -Message 'Search Results should not be a permanent navigation category.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_menu_categories\(\)' `
    -Message 'Nav browser should compute visible categories dynamically.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_search_category_index\(\)' `
    -Message 'Nav browser should be able to select the transient Search Results category.'

Assert-NotMatch `
    -Text $source `
    -Pattern "function accessxi\.nav_menu_control_key" `
    -Message 'AXI nav should not expose a native-menu-style key callback control helper.'

$navHandleStart = $source.IndexOf('local function nav_menu_handle_action')
$navHandleEnd = $source.IndexOf('accessxi.poll_nav_browser_hotkeys', $navHandleStart)
if ($navHandleStart -lt 0 -or $navHandleEnd -lt 0) {
    throw 'Could not locate nav browser key handler.'
}
$navHandleBody = $source.Substring($navHandleStart, $navHandleEnd - $navHandleStart)

Assert-NotMatch `
    -Text $navHandleBody `
    -Pattern "VK_RETURN|VK_LEFT|VK_RIGHT|VK_UP|VK_DOWN|VK_N(?!UMPAD)" `
    -Message 'Nav browser handler should not use FFXI menu keys or Control+N.'

Assert-Match -Text $navHandleBody -Pattern "(?s)action == 'previous_category'.*?nav_menu_category_move\(-1\)" -Message 'U should move nav categories backward.'
Assert-Match -Text $navHandleBody -Pattern "(?s)action == 'next_category'.*?nav_menu_category_move\(1\)" -Message 'O should move nav categories forward.'
Assert-Match -Text $navHandleBody -Pattern "(?s)action == 'previous_item'.*?nav_menu_move\(-1\)" -Message 'J should move nav destinations backward.'
Assert-Match -Text $navHandleBody -Pattern "(?s)action == 'repeat_item'.*?nav_menu_move\(0\)" -Message 'K should repeat the current nav destination.'
Assert-Match -Text $navHandleBody -Pattern "(?s)action == 'next_item'.*?nav_menu_move\(1\)" -Message 'L should move nav destinations forward.'
Assert-Match -Text $navHandleBody -Pattern "(?s)action == 'start_route'.*?nav_menu_start_route\(\)" -Message 'I should start the selected route when navigation is inactive.'
Assert-Match -Text $navHandleBody -Pattern "(?s)action == 'stop_route'.*?nav_route_stop\(\)" -Message 'I should stop active or pending navigation.'

$navPollStart = $source.IndexOf('accessxi.poll_nav_browser_hotkeys')
$navPollEnd = $source.IndexOf('local function nav_find_point', $navPollStart)
if ($navPollStart -lt 0 -or $navPollEnd -lt 0) {
    throw 'Could not locate nav browser polling helper.'
}
$navPollBody = $source.Substring($navPollStart, $navPollEnd - $navPollStart)

Assert-NotMatch `
    -Text $navPollBody `
    -Pattern "VK_RETURN|VK_LEFT|VK_RIGHT|VK_UP|VK_DOWN|VK_N(?!UMPAD)" `
    -Message 'Nav browser polling should not watch Enter, arrows, or Control+N.'

Assert-Match -Text $navPollBody -Pattern "navigation_hotkeys\.poll" -Message 'Nav browser should poll the tested bare-letter input policy.'
Assert-NotMatch -Text $navPollBody -Pattern "VK_NUMPAD1|VK_NUMPAD3|VK_NUMPAD7|VK_NUMPAD9|VK_ADD|nav_keypad_control_down" -Message 'All old numpad navigation controls, including duplicate route start, should be removed.'

$navOpenStart = $source.IndexOf('local function nav_open_menu')
$navOpenEnd = $source.IndexOf('local function nav_close_menu', $navOpenStart)
if ($navOpenStart -lt 0 -or $navOpenEnd -lt 0) {
    throw 'Could not locate nav browser open helper.'
}
$navOpenBody = $source.Substring($navOpenStart, $navOpenEnd - $navOpenStart)

Assert-NotMatch `
    -Text $navOpenBody `
    -Pattern "nav_menu_open\s*=\s*true" `
    -Message '/axi nav should load the nav browser, not open a nav menu mode.'

Assert-Match `
    -Text $navOpenBody `
    -Pattern 'nav_refresh_search_results\(\)' `
    -Message '/axi nav search should populate transient search results before opening the browser.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.note_axi_command_input_transition\(previous_state,\s*state,\s*menu_name,\s*now\)' `
    -Message 'AXI commands visible in the chat input should queue a narrow replay when input clears without an Ashita command event.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.poll_pending_axi_command_replay\(\)' `
    -Message 'Queued AXI command replay should be polled after chat input state settles.'

Assert-Match `
    -Text $source `
    -Pattern 'axi_command_last_event_text' `
    -Message 'Real Ashita command events should stamp handled AXI commands so input replay cannot double-fire.'

Assert-Match `
    -Text $source `
    -Pattern "queue_axi_command_replay\(previous_raw,\s*'chat-input-clear'" `
    -Message 'AXI command replay should be limited to the clear-input transition observed in the live log.'

Assert-Match `
    -Text $navOpenBody `
    -Pattern 'accessxi\.nav_search_category_index\(\)' `
    -Message '/axi nav search should open directly on Search Results when there are hits.'

$navBuildStart = $source.IndexOf('local function nav_build_menu_items')
$navBuildEnd = $source.IndexOf('local function nav_menu_item_speech', $navBuildStart)
if ($navBuildStart -lt 0 -or $navBuildEnd -lt 0) {
    throw 'Could not locate nav menu item builder.'
}
$navBuildBody = $source.Substring($navBuildStart, $navBuildEnd - $navBuildStart)

Assert-Match `
    -Text $navBuildBody `
    -Pattern "category_key\s*==\s*'search-results'" `
    -Message 'Search Results category should be backed by the cached search result list.'

Assert-Match `
    -Text $navBuildBody `
    -Pattern 'nav_menu_search_results' `
    -Message 'Search Results category should return cached results rather than filtering the current category.'

$navStartStart = $source.IndexOf('local function nav_menu_start_route')
$navStartEnd = $source.IndexOf('local function nav_menu_handle_action', $navStartStart)
if ($navStartStart -lt 0 -or $navStartEnd -lt 0) {
    throw 'Could not locate nav selected-route start helper.'
}
$navStartBody = $source.Substring($navStartStart, $navStartEnd - $navStartStart)

Assert-NotMatch `
    -Text $navStartBody `
    -Pattern "not accessxi\.nav_menu_open|nav_menu_items:clear\(\)" `
    -Message 'Starting a selected nav route should not depend on or clear a nav menu.'

$keyCallbackStart = $source.IndexOf("ashita.events.register('key'")
$keyCallbackEnd = $source.IndexOf("ashita.events.register('d3d_present'", $keyCallbackStart)
if ($keyCallbackStart -lt 0 -or $keyCallbackEnd -lt 0) {
    throw 'Could not locate key callback body.'
}
$keyCallbackBody = $source.Substring($keyCallbackStart, $keyCallbackEnd - $keyCallbackStart)

Assert-NotMatch `
    -Text $keyCallbackBody `
    -Pattern "nav_menu_control_key|nav_menu_handle_key|nav_control_key|VK_LEFT|VK_RIGHT|VK_UP|VK_DOWN|VK_N(?!UMPAD)" `
    -Message 'Key callback should not try to own AXI nav browser keys; nav browsing is polled like chat.'

Assert-Match `
    -Text $keyCallbackBody `
    -Pattern "chat_input_last_enter_tick" `
    -Message 'Key callback should only use Enter to timestamp chat-input command submission for narrow AXI replay.'

$presentStart = $source.IndexOf("ashita.events.register('d3d_present'")
if ($presentStart -lt 0) {
    throw 'Could not locate d3d_present callback.'
}
$presentBody = $source.Substring($presentStart)

Assert-Match -Text $presentBody -Pattern "accessxi\.poll_nav_browser_hotkeys\(\);" -Message 'Present loop should poll nav browser hotkeys.'
Assert-Match -Text $presentBody -Pattern "accessxi\.poll_pending_axi_command_replay\(\)" -Message 'Present loop should poll narrow AXI command replay after chat input polling.'
Assert-NotMatch -Text $presentBody -Pattern "nav_menu_poll_key\(\);" -Message 'Present loop should not poll the old nav menu key loop.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.nav_reset_zone_state\(reason,\s*old_zone,\s*new_zone\)" `
    -Message 'Expected explicit nav zone-state reset helper.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local function nav_cached_player_position\(\).*?local zone = nav_zone_id\(\).*?accessxi\.nav_current_position\.zone.*?~= zone.*?accessxi\.nav_current_position = nil.*?return nav_player_position\(\)" `
    -Message 'Cached nav position should be discarded when it belongs to a different zone.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local function poll_nav_position\(\).*?local zone = nav_zone_id\(\).*?accessxi\.nav_last_seen_zone.*?~= zone.*?accessxi\.nav_reset_zone_state\('poll-zone-change'" `
    -Message 'Polling should reset nav route/mesh/menu state when the observed zone changes.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_begin_zoning_watch\(reason,\s*player,\s*destination,\s*now\)' `
    -Message 'Zone-line route arrivals should start a short zoning watch before the client loading handoff.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_zoning_watch_active\(now\)' `
    -Message 'Present-loop polling should have a zoning-watch guard.'

$zoneResetStart = $source.IndexOf('function accessxi.nav_reset_zone_state')
$pollPositionStart = $source.IndexOf('local function poll_nav_position', $zoneResetStart)
if ($zoneResetStart -lt 0 -or $pollPositionStart -lt 0) {
    throw 'Could not locate nav zone reset block.'
}
$zoneResetBody = $source.Substring($zoneResetStart, $pollPositionStart - $zoneResetStart)

Assert-Match `
    -Text $zoneResetBody `
    -Pattern "nav_clear_zoning_watch\('zone-change'" `
    -Message 'Observed zone changes should clear the zoning watch.'

Assert-Match `
    -Text $presentBody `
    -Pattern "(?s)if \(accessxi\.nav_zoning_watch_active\(now\) or accessxi\.nav_zone_load_settle_active\(now\)\) then\s*accessxi\.nav_poll_zone_transition_only\(now\);\s*accessxi\.nav_route_recorder_poll\(now\);\s*return;\s*end\s*poll_nav_position\(\);.*?accessxi\.poll_compass_hotkey\(\)" `
    -Message 'Present loop should preserve explicit route recording but stop normal addon polling while a zone-line loading handoff or post-zone settle is pending.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.nav_begin_zoning_watch\('zone-search-zoneline-arrival',\s*player,\s*destination,\s*now\)" `
    -Message 'Zone-search zone-line arrivals should quiet addon polling until the new zone is observed.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.nav_begin_zoning_watch\('zone-line-arrival',\s*player,\s*destination,\s*now\)" `
    -Message 'Normal zone-line arrivals should quiet addon polling until the new zone is observed.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)local function nav_player_position\(\).*?if \(pos == nil or \(pos\.x == 0 and pos\.z == 0\)\) then.*?if \(fallback ~= nil and not \(fallback\.x == 0 and fallback\.z == 0\)\) then.*?pos = fallback" `
    -Message 'Player position should not cache transient zero-zero zoning samples.'

Write-Host 'nav zoning and key blocking checks ok'

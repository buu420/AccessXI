$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$nativeMenusPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\native_menus.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$nativeMenus = Get-Content -LiteralPath $nativeMenusPath -Raw

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-Match `
    -Text $nativeMenus `
    -Pattern "'menu    cfilter'" `
    -Message 'Chat Filters should remain registered as a config-family native menu.'

$nativeLabelStart = $source.IndexOf('function accessxi.config_menu_native_label_speech')
if ($nativeLabelStart -lt 0) {
    throw 'Missing config_menu_native_label_speech helper.'
}
$nativeLabelEnd = $source.IndexOf("`nfunction accessxi.config_volume_slider_help_repeat", $nativeLabelStart)
if ($nativeLabelEnd -lt 0) {
    throw 'Could not locate end of config_menu_native_label_speech helper.'
}
$nativeLabelBody = $source.Substring($nativeLabelStart, $nativeLabelEnd - $nativeLabelStart)

Assert-Match `
    -Text $nativeLabelBody `
    -Pattern "(?s)tostring\(menu_name or ''\):eq\('menu    cfilter', true\).*?return nil" `
    -Message 'Chat Filters should not use the generic native child walker; live logs showed that path accepts junk labels.'

Assert-Match `
    -Text $nativeLabelBody `
    -Pattern "native_query_label_for_selection\(ptr,\s*selected,\s*count,\s*'config-visible'\)" `
    -Message 'Config native label speech should use a config-visible query context for native row text.'

Assert-Match `
    -Text $nativeLabelBody `
    -Pattern 'state config native-label' `
    -Message 'Config native label logs should identify the native-visible source path.'

$speechStart = $source.IndexOf('function accessxi.config_menu_speech')
if ($speechStart -lt 0) {
    throw 'Missing config_menu_speech handler.'
}
$speechEnd = $source.IndexOf("`nfunction accessxi.status_menu_probe_desc_table", $speechStart)
if ($speechEnd -lt 0) {
    throw 'Could not locate end of config_menu_speech handler.'
}
$speechBody = $source.Substring($speechStart, $speechEnd - $speechStart)

$nativeIndex = $speechBody.IndexOf('accessxi.config_menu_native_label_speech')
$descriptorIndex = $speechBody.IndexOf('accessxi.config_menu_descriptor_resource_speech')
if ($nativeIndex -lt 0) {
    throw 'config_menu_speech should try native visible-label speech.'
}
if ($descriptorIndex -lt 0) {
    throw 'config_menu_speech should keep descriptor-resource fallback speech.'
}
if ($nativeIndex -gt $descriptorIndex) {
    throw 'Chat Filters should try native visible row text before descriptor-resource fallback.'
}

$nativeCall = 'local label_speech = accessxi.config_menu_native_label_speech(menu_name, title, selected, count, obj, child);'
$nativeCallIndex = $speechBody.IndexOf($nativeCall)
if ($nativeCallIndex -lt 0) {
    throw 'config_menu_speech should store native visible-row speech before descriptor fallback.'
}
$nativeReturnIndex = $speechBody.IndexOf('return label_speech;', $nativeCallIndex)
if ($nativeReturnIndex -lt 0) {
    throw 'Config speech should return native visible row speech as soon as it is available.'
}
if ($nativeReturnIndex -gt $descriptorIndex) {
    throw 'Config speech should return native visible row speech before descriptor-resource fallback.'
}

$chatFilterRowStart = $source.IndexOf('function accessxi.config_chat_filter_resource_row_id')
if ($chatFilterRowStart -lt 0) {
    throw 'Missing Chat Filters native resource row-id mapper.'
}
$chatFilterRowEnd = $source.IndexOf("`nfunction accessxi.config_menu_descriptor_resource_row", $chatFilterRowStart)
if ($chatFilterRowEnd -lt 0) {
    throw 'Could not locate end of Chat Filters native resource row-id mapper.'
}
$chatFilterRowBody = $source.Substring($chatFilterRowStart, $chatFilterRowEnd - $chatFilterRowStart)

foreach ($expected in @(
    '[1] = 0',
    '[2] = 2',
    '[5] = 5',
    '[10] = 1',
    '[11] = 195',
    '[18] = 30',
    '[19] = 20',
    '[62] = 61'
)) {
    if ($chatFilterRowBody.IndexOf($expected) -lt 0) {
        throw "Chat Filters native row-id mapper is missing expected resource mapping: $expected"
    }
}

$logWindowRowsStart = $source.IndexOf('function accessxi.config_log_window_designation_row_ids')
if ($logWindowRowsStart -lt 0) {
    throw 'Missing Log Window designation native resource row-id mapper.'
}
$logWindowRowsEnd = $source.IndexOf("`nfunction accessxi.native_known_menu_title", $logWindowRowsStart)
if ($logWindowRowsEnd -lt 0) {
    throw 'Could not locate end of Log Window designation native resource row-id mapper.'
}
$logWindowRowsBody = $source.Substring($logWindowRowsStart, $logWindowRowsEnd - $logWindowRowsStart)
$expectedChatLogWindowOrder = 'return T{ 36, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 37, 196 };'
if ($logWindowRowsBody.IndexOf($expectedChatLogWindowOrder) -lt 0) {
    throw 'Log Settings chat-related window designation rows should follow the visible order: Say, Tell, Party, Linkshell, Linkshell 2, Assist J, Assist E, Unity, Emotes, Message, NPC, Shout, Yell.'
}
foreach ($expected in @(
    'function accessxi.config_log_window_designation_pending_key(category, logical)',
    'function accessxi.config_log_window_designation_pending_state(category, logical)',
    'function accessxi.config_log_window_designation_set_pending_state(category, logical, state, source)',
    'function accessxi.config_log_window_designation_note_confirm_key(key)',
    'function accessxi.poll_config_log_window_designation_confirm_key()',
    'function accessxi.config_log_window_designation_state(raw, category, logical)',
    'local pending = accessxi.config_log_window_designation_pending_state(category, logical);',
    'local mask = bit.lshift(1, logical - 1);',
    'state = accessxi.config_log_window_designation_state(raw, category, logical);',
    'accessxi.config_log_window_designation_current_category = tonumber(category) or 0;',
    'accessxi.config_log_window_designation_current_state = state;',
    "accessxi.config_log_window_designation_set_pending_state(category, logical, next_state, 'confirm-key');",
    'accessxi.config_log_window_designation_note_confirm_key_up(key);',
    'accessxi.config_log_window_designation_note_confirm_key(key);',
    'accessxi.poll_config_log_window_designation_confirm_key();',
    'state="%s"',
    'row_id,',
    'state,',
    "return ('%s. %s %s'):fmt(tostring(title or 'Config'), accessxi.sentence_fragment(state), accessxi.sentence_fragment(text));"
)) {
    if ($logWindowRowsBody.IndexOf($expected) -lt 0 -and $source.IndexOf($expected) -lt 0) {
        throw "Log Settings window designation should speak dynamic On/Off state from the native raw bitmask; missing fragment: $expected"
    }
}
foreach ($probeFragment in @(
    'state config log-window-designation-pending-toggle',
    'state config log-window-designation-confirm-poll',
    'config_log_window_designation_confirm_source'
)) {
    if ($source.IndexOf($probeFragment) -ge 0) {
        throw "Log Settings window designation should not retain temporary toggle probe fragment: $probeFragment"
    }
}

$descriptorRowStart = $source.IndexOf('function accessxi.config_menu_descriptor_resource_row')
if ($descriptorRowStart -lt 0) {
    throw 'Missing config_menu_descriptor_resource_row helper.'
}
$descriptorRowEnd = $source.IndexOf("`nfunction accessxi.config_fxfilter_state", $descriptorRowStart)
if ($descriptorRowEnd -lt 0) {
    throw 'Could not locate end of config_menu_descriptor_resource_row helper.'
}
$descriptorRowBody = $source.Substring($descriptorRowStart, $descriptorRowEnd - $descriptorRowStart)

foreach ($expected in @(
    "if (menu_name:eq('menu    cfilter', true)) then",
    'local row_id = accessxi.config_chat_filter_resource_row_id(logical);',
    "return 'label', row_id, 'ROM\\165\\74.DAT'"
)) {
    if ($descriptorRowBody.IndexOf($expected) -lt 0) {
        throw "Chat Filters should read labels from the modern native ChatFilterTypes resource; missing fragment: $expected"
    }
}

if ($descriptorRowBody.IndexOf("return 'chat_filter_label', logical - 1, 'ROM\\97\\39.DAT'") -ge 0) {
    throw 'Chat Filters should not use the old ROM\\97\\39.DAT sequence; it puts rows in the wrong order and misses Yell.'
}

$chatFilterStateStart = $source.IndexOf('function accessxi.config_chat_filter_state')
if ($chatFilterStateStart -lt 0) {
    throw 'Missing Chat Filters On/Off state helper.'
}
$chatFilterStateEnd = $source.IndexOf("`nfunction accessxi.config_fxfilter_state", $chatFilterStateStart)
if ($chatFilterStateEnd -lt 0) {
    throw 'Could not locate end of Chat Filters On/Off state helper.'
}
$chatFilterStateBody = $source.Substring($chatFilterStateStart, $chatFilterStateEnd - $chatFilterStateStart)

foreach ($expected in @(
    "ashita.memory.find(0, 0, 'C3C74004000000008B0D????????81C1', 0x0A, 0)",
    "ffi.cast('uint32_t**'",
    "ffi.cast('uint32_t*'",
    'local pending = accessxi.config_chat_filter_pending_state(logical);',
    'data[0]',
    'data[1]',
    'data[2]',
    'local bit_index = logical - 1;',
    "return 'On';",
    "return 'Off';"
)) {
    if ($chatFilterStateBody.IndexOf($expected) -lt 0) {
        throw "Chat Filters On/Off state should be read from the native chat-filter masks; missing fragment: $expected"
    }
}

foreach ($expected in @(
    'function accessxi.config_chat_filter_pending_state(logical)',
    'function accessxi.config_chat_filter_enter_probe_snapshot(logical, current_state, next_state)',
    'function accessxi.poll_config_chat_filter_confirm_key()',
    'function accessxi.config_chat_filter_note_confirm_key(key)',
    'function accessxi.config_chat_filter_note_confirm_key_up(key)',
    'accessxi.config_chat_filter_enter_probe_snapshot(logical, current, next_state);',
    'kernel32.GetAsyncKeyState(VK_RETURN)',
    'accessxi.config_chat_filter_confirm_source = ''poll-keydown'';',
    "accessxi.config_chat_filter_set_pending_state(logical, next_state, 'confirm-key')"
)) {
    if ($source.IndexOf($expected) -lt 0) {
        throw "Chat Filters should track an in-menu pending On/Off state after Enter toggles; missing fragment: $expected"
    }
}

Assert-Match `
    -Text $source `
    -Pattern 'state config chat-filter-enter-probe' `
    -Message 'Chat Filters Enter probe should log a dedicated marker when Confirm is pressed.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.config_menu_descriptor_resource_speech' `
    -Message 'Descriptor-resource speech should remain as a fallback for config menus whose native labels are blank.'

$descriptorSpeechStart = $source.IndexOf('function accessxi.config_menu_descriptor_resource_speech')
if ($descriptorSpeechStart -lt 0) {
    throw 'Missing config_menu_descriptor_resource_speech helper.'
}
$descriptorSpeechEnd = $source.IndexOf("`nfunction accessxi.config_log_window_designation_speech", $descriptorSpeechStart)
if ($descriptorSpeechEnd -lt 0) {
    throw 'Could not locate end of config_menu_descriptor_resource_speech helper.'
}
$descriptorSpeechBody = $source.Substring($descriptorSpeechStart, $descriptorSpeechEnd - $descriptorSpeechStart)

Assert-NotMatch `
    -Text $descriptorSpeechBody `
    -Pattern "row_id == 0 and kind ~= 'chat_filter_label'" `
    -Message 'Descriptor-resource speech must allow Chat Filters label row 0; it is the native Say row.'

foreach ($expected in @(
    "if (menu_name:eq('menu    cfilter', true)) then",
    'state = accessxi.config_chat_filter_state(logical);',
    'accessxi.config_chat_filter_current_logical = tonumber(logical) or 0;',
    'accessxi.config_chat_filter_current_state = state;',
    'accessxi.config_chat_filter_current_text = text;',
    'accessxi.config_chat_filter_current_tick = tick();',
    'accessxi.config_chat_filter_current_probe_context = T{',
    'desc0c = tonumber(desc0c) or 0;',
    'record = tonumber(record) or 0;',
    'entry = tonumber(entry) or 0;',
    "elseif (menu_name:eq('menu    fxfilter', true)) then"
)) {
    if ($descriptorSpeechBody.IndexOf($expected) -lt 0) {
        throw "Chat Filters descriptor speech should include native On/Off state; missing fragment: $expected"
    }
}

$packetInStart = $source.IndexOf('function accessxi.capture_party_config_incoming_packet')
if ($packetInStart -lt 0) {
    throw 'Missing incoming party/config packet capture helper.'
}
$packetInEnd = $source.IndexOf("`nfunction accessxi.log_party_toggle_probe_snapshot", $packetInStart)
if ($packetInEnd -lt 0) {
    throw 'Could not locate end of incoming party/config packet capture helper.'
}
$packetInBody = $source.Substring($packetInStart, $packetInEnd - $packetInStart)

if ($packetInBody.IndexOf("accessxi.config_chat_filter_clear_pending_states('packet_in_0b4')") -lt 0) {
    throw 'Incoming 0xB4 config packets should clear pending Chat Filters state once saved native masks refresh.'
}

$keyHandlerStart = $source.IndexOf("ashita.events.register('key', 'accessxi_reader_key_cb'")
if ($keyHandlerStart -lt 0) {
    throw 'Missing Ashita key callback.'
}
$keyHandlerEnd = $source.IndexOf("`nend);", $keyHandlerStart)
if ($keyHandlerEnd -lt 0) {
    throw 'Could not locate end of Ashita key callback.'
}
$keyHandlerBody = $source.Substring($keyHandlerStart, $keyHandlerEnd - $keyHandlerStart)

foreach ($expected in @(
    'accessxi.config_chat_filter_note_confirm_key_up(key);',
    'accessxi.config_chat_filter_note_confirm_key(key);'
)) {
    if ($keyHandlerBody.IndexOf($expected) -lt 0) {
        throw "Ashita key callback should feed Chat Filters pending toggle tracking; missing fragment: $expected"
    }
}

if ($source.IndexOf('accessxi.poll_config_chat_filter_confirm_key();') -lt 0) {
    throw 'd3d_present should poll Enter while Chat Filters is open because Ashita key events may not fire for this confirm path.'
}

Write-Host 'config chat filters native checks passed'

$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$menusPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\native_menus.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$menus = Get-Content -LiteralPath $menusPath -Raw

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
    -Text $menus `
    -Pattern "menu\s+bluequip'.*title\s*=\s*'Blue Magic'" `
    -Message 'Set Blue Magic menu should be registered as native menu    bluequip with the Blue Magic title.'

Assert-Match `
    -Text $menus `
    -Pattern "menu\s+bluinven'.*title\s*=\s*'Blue Magic'" `
    -Message 'Set Blue Magic replacement list should be registered as native menu    bluinven with the Blue Magic title.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_set_menu_speech' `
    -Message 'Missing dedicated Set Blue Magic native handler.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_menu_speech' `
    -Message 'Missing dedicated Set Blue Magic replacement-list native handler.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.magic_mix_category_spell_list' `
    -Message 'Set Blue Magic replacement-list anchor fallback should share the current client mix.dat category order.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_mix_spell_list' `
    -Message 'Set Blue Magic replacement-list diagnostics should have a Blue Magic-specific mix.dat order helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_mix_spell_list[\s\S]{0,1800}\+\s*512' `
    -Message 'Blue Magic mix.dat values should be decoded as raw Blue Magic ids by adding 512, without changing normal magic mix order.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_mix_spell_list[\s\S]{0,2200}player:HasSpell\(id\)' `
    -Message 'Blue Magic mix.dat diagnostics should only include spells actually known by the player.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_mix_spell_list[\s\S]{0,2200}tonumber\(info\.type\)\s*==\s*6' `
    -Message 'Blue Magic mix.dat diagnostics should restrict decoded raw+512 entries to Blue Magic resources.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_mix_spell_list[\s\S]{0,2400}mix_index\s*=\s*mix_index\s*\+\s*1' `
    -Message 'Blue Magic mix.dat diagnostics should preserve sparse mix.dat word positions while scanning.'

$blueMixStart = $source.IndexOf('function accessxi.blue_magic_mix_spell_list')
if ($blueMixStart -lt 0) {
    throw 'Could not locate Blue Magic mix.dat helper.'
}
$blueMixEnd = $source.IndexOf("`nfunction accessxi.magic_mix_category_spell_for_selected", $blueMixStart)
if ($blueMixEnd -lt 0) {
    throw 'Could not locate end of Blue Magic mix.dat helper.'
}
$blueMixBody = $source.Substring($blueMixStart, $blueMixEnd - $blueMixStart)

Assert-NotMatch `
    -Text $blueMixBody `
    -Pattern 'zero_run|zeroRun' `
    -Message 'Blue Magic mix.dat diagnostics must scan sparse entries and must not stop at zero runs like normal magic.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.log_blue_magic_inventory_probe' `
    -Message 'Missing bounded diagnostic probe for the Set Blue Magic replacement list.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_set_current_spell_for_slot' `
    -Message 'Set Blue Magic handler should read currently set spells from the native BLU set buffer.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_set_point_cost' `
    -Message 'Set Blue Magic handler should expose set-point costs by selected spell id.'

$costsPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\blue_magic_set_points.lua'
if (-not (Test-Path -LiteralPath $costsPath)) {
    throw 'Missing Blue Magic set-point cost data module.'
}
$costs = Get-Content -LiteralPath $costsPath -Raw

Assert-Match `
    -Text $costs `
    -Pattern '\[547\]\s*=\s*1' `
    -Message 'Set-point data should include Cocoon by spell id from blue_spell_list.'

Assert-Match `
    -Text $costs `
    -Pattern '\[662\]\s*=\s*3' `
    -Message 'Set-point data should include Battery Charge by spell id from blue_spell_list.'

Assert-NotMatch `
    -Text $costs `
    -Pattern 'Cocoon|Battery Charge|Charged Whisker|Entomb|Blazing Bound|Foot Kick|Power Attack' `
    -Message 'Set-point data module should map numeric spell ids to costs without hardcoded visible labels.'

$slotStart = $source.IndexOf('function accessxi.blue_magic_set_native_offset')
if ($slotStart -lt 0) {
    throw 'Could not locate native BLU set slot reader block.'
}
$slotEnd = $source.IndexOf("`nfunction accessxi.blue_magic_set_menu_speech", $slotStart)
if ($slotEnd -lt 0) {
    throw 'Could not locate end of native BLU set slot reader block.'
}
$slotBody = $source.Substring($slotStart, $slotEnd - $slotStart)

Assert-Match `
    -Text $slotBody `
    -Pattern "GetPointerManager\(\):Get\('inventory'\)" `
    -Message 'Set Blue Magic slot reader should use the native inventory pointer, matching the Ashita blusets path.'

Assert-Match `
    -Text $slotBody `
    -Pattern 'ashita\.memory\.find' `
    -Message 'Set Blue Magic slot reader should find the client BLU buffer offset from the native signature.'

Assert-Match `
    -Text $slotBody `
    -Pattern 'read_u8\(.*slot\s*-\s*1' `
    -Message 'Set Blue Magic slot reader should read one byte per native BLU spell slot.'

Assert-Match `
    -Text $slotBody `
    -Pattern 'child_visible_a\s*==\s*0|child_visible_a\s*<=\s*0|child_visible_a\s*<\s*=\s*0' `
    -Message 'Set Blue Magic current-set pane detection should tolerate native child visible counters dropping to zero while arrowing upward.'

Assert-Match `
    -Text $slotBody `
    -Pattern 'child_packed' `
    -Message 'Set Blue Magic current-set pane detection should decode the native packed child scroll value used after visible slot 10.'

Assert-Match `
    -Text $slotBody `
    -Pattern '\+\s*512' `
    -Message 'Set Blue Magic slot ids should be converted to spell resource ids by adding 512.'

Assert-Match `
    -Text $slotBody `
    -Pattern 'A1\?\?\?\?\?\?\?\?33C98A4E5E33D28A565D5F5E8950148948185B83C414C20400' `
    -Message 'Set Blue Magic speech should read BLU point totals from the native client points signature.'

Assert-Match `
    -Text $slotBody `
    -Pattern '0x14' `
    -Message 'Set Blue Magic points reader should read spent BLU points from the native points block.'

Assert-Match `
    -Text $slotBody `
    -Pattern '0x18' `
    -Message 'Set Blue Magic points reader should read maximum BLU points from the native points block.'

Assert-NotMatch `
    -Text $slotBody `
    -Pattern 'blue_magic_set_points_base_cache' `
    -Message 'Set Blue Magic points reader should not cache the live points block; it should dereference the native pointer chain each read.'

Assert-NotMatch `
    -Text $slotBody `
    -Pattern 'Cocoon|Battery Charge|Charged Whisker|Entomb|Blazing Bound|Foot Kick|Power Attack|T\{\s*\d+\s*,' `
    -Message 'Set Blue Magic native slot reader must not hardcode spell names or spell slot ids.'

$handlerStart = $source.IndexOf('function accessxi.blue_magic_set_menu_speech')
if ($handlerStart -lt 0) {
    throw 'Could not locate Set Blue Magic native handler.'
}
$handlerEnd = $source.IndexOf("`nfunction accessxi.blue_magic_inventory_log_missing", $handlerStart)
if ($handlerEnd -lt 0) {
    throw 'Could not locate end of Set Blue Magic native handler block.'
}
$handlerBody = $source.Substring($handlerStart, $handlerEnd - $handlerStart)

Assert-Match `
    -Text $handlerBody `
    -Pattern 'magic_rendered_row_text\(entry,\s*selected\)|native_query_label_for_selection' `
    -Message 'Set Blue Magic handler should derive row labels from the live native row surface.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'magic_spell_from_exact_label_any|magic_spell_from_window_help' `
    -Message 'Set Blue Magic handler should exact-match native text against spell resources.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'blue_magic_set_current_spell_for_slot' `
    -Message 'Set Blue Magic handler should use the native BLU set buffer for currently set spell slots.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'blue_magic_set_points_info' `
    -Message 'Set Blue Magic handler should include native BLU point totals in set-slot speech.'

Assert-Match `
    -Text $source `
    -Pattern 'Blue Magic Points' `
    -Message 'Set Blue Magic speech should include visible Blue Magic point totals.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'blue_magic_set_append_spell_details' `
    -Message 'Set Blue Magic handler should route spell rows through the shared points/details formatter.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'blue_magic_set_point_cost' `
    -Message 'Set Blue Magic handler should speak known per-spell set-point costs by spell id.'

Assert-Match `
    -Text $source `
    -Pattern 'Set point cost' `
    -Message 'Set Blue Magic handler should include set-point cost text when known.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'player:HasSpell\(spell\.id\)' `
    -Message 'Set Blue Magic handler should only speak spells known by the player.'

Assert-Match `
    -Text $handlerBody `
    -Pattern "type\)\s*==\s*6|spell\.type\)\s*==\s*6" `
    -Message 'Set Blue Magic handler should restrict spell rows to Blue Magic resource type.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'blue-magic-set-(missing|quiet|native-row)' `
    -Message 'Set Blue Magic handler should log misses instead of falling back to guessed rows.'

Assert-NotMatch `
    -Text $handlerBody `
    -Pattern 'magic_mix_category_spell_for_selected|magic_category_spell_for_selected|magic_known_spell_list_for_category|for id = 0,\s*2048|for id = 1,\s*2048' `
    -Message 'Set Blue Magic handler must not use ordinal/fixed Blue Magic lists for this dynamic set screen.'

Assert-NotMatch `
    -Text $handlerBody `
    -Pattern 'Cocoon|Battery Charge|Charged Whisker|Entomb|Blazing Bound|Foot Kick|Power Attack' `
    -Message 'Set Blue Magic handler must not hardcode screenshot spell names.'

Assert-Match `
    -Text $source `
    -Pattern "menu_name:eq\('menu    bluinven', true\)" `
    -Message 'Set Blue Magic native dispatcher should include the menu    bluinven replacement list.'

$inventoryStart = $source.IndexOf('function accessxi.blue_magic_inventory_menu_speech')
if ($inventoryStart -lt 0) {
    throw 'Could not locate Set Blue Magic replacement-list handler.'
}
$inventoryEnd = $source.IndexOf("`nfunction accessxi.current_item_sort_confirmation_context", $inventoryStart)
if ($inventoryEnd -lt 0) {
    throw 'Could not locate end of Set Blue Magic replacement-list handler block.'
}
$inventoryBody = $source.Substring($inventoryStart, $inventoryEnd - $inventoryStart)

Assert-Match `
    -Text $inventoryBody `
    -Pattern "menu_name:eq\('menu    bluinven', true\)" `
    -Message 'Set Blue Magic replacement-list handler should only handle menu    bluinven.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'magic_rendered_row_text\(entry,\s*selected\)' `
    -Message 'Set Blue Magic replacement-list handler should derive candidate row labels from the rendered native row surface.'

Assert-NotMatch `
    -Text $inventoryBody `
    -Pattern 'native_query_label_for_selection' `
    -Message 'Set Blue Magic replacement-list handler should not run the noisy generic native query scanner on menu    bluinven.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue_magic_spell_from_exact_label|magic_spell_from_window_help' `
    -Message 'Set Blue Magic replacement-list handler should exact-match native text/help against spell resources.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_native_entry_segments' `
    -Message 'Set Blue Magic replacement-list handler should have a native selected-entry detail scanner.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_spell_from_native_entry' `
    -Message 'Set Blue Magic replacement-list handler should match selected-entry detail text against Blue Magic resources.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue_magic_inventory_spell_from_native_entry\(entry,\s*selected' `
    -Message 'Set Blue Magic replacement-list handler should probe native selected-entry detail text before the miss path.'

Assert-NotMatch `
    -Text $inventoryBody `
    -Pattern 'native-blue-inventory-entry:' `
    -Message 'Set Blue Magic replacement-list native-entry detail matches are polluted by neighboring rows and must not speak.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_record_anchor' `
    -Message 'Set Blue Magic replacement-list handler should record the native set-slot spell used to open the replacement list.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_spell_from_anchor' `
    -Message 'Set Blue Magic replacement-list handler should resolve rows from the native set-slot anchor plus current client spell order.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.blue_magic_inventory_spell_from_anchor[\s\S]{0,2600}magic_mix_category_spell_list\('Blue Magic'\)" `
    -Message 'Set Blue Magic replacement-list anchor resolver should use the normal client Blue Magic mix.dat category order; raw+512 order is diagnostic-only and omits valid anchors like Cocoon.'

$anchorStart = $source.IndexOf('function accessxi.blue_magic_inventory_spell_from_anchor')
if ($anchorStart -lt 0) {
    throw 'Could not locate Set Blue Magic replacement-list anchor resolver.'
}
$anchorEnd = $source.IndexOf("`nfunction accessxi.blue_magic_set_menu_speech", $anchorStart)
if ($anchorEnd -lt 0) {
    throw 'Could not locate end of Set Blue Magic replacement-list anchor resolver.'
}
$anchorBody = $source.Substring($anchorStart, $anchorEnd - $anchorStart)

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'at_edge[\s\S]{0,360}seen_non_anchor[\s\S]{0,360}anchor\.unsafe' `
    -Message 'Set Blue Magic replacement-list anchor must not mark itself unsafe merely because the cursor returned to a visible edge row.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'row_entry_shifted|entry_shifted' `
    -Message 'Set Blue Magic replacement-list anchor should detect when the same visual row changes native entries.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'last_global_index' `
    -Message 'Set Blue Magic replacement-list anchor should remember the last spoken global spell index.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'blue_magic_inventory_native_scroll_selected\(child,\s*selected\)' `
    -Message 'Set Blue Magic replacement-list anchor should read the validated native scroll-window index for stationary edge rows.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'native-set-slot-cursor-motion' `
    -Message 'Set Blue Magic replacement-list anchor should resolve movement from native cursor/window deltas, not from absolute scroll-window indices.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'last_scroll_window_start|window_delta' `
    -Message 'Set Blue Magic replacement-list anchor should track native scroll-window movement as a delta.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'scroll_selected\s*==\s*last_global_index\s*[-+]\s*1' `
    -Message 'Set Blue Magic replacement-list anchor must not infer pinned-edge rows from the last spoken spell; that poisons later down-arrow reads.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'native-set-slot-mix-order-edge-scroll-window|native-set-slot-calibrated-scroll-window' `
    -Message 'Set Blue Magic replacement-list anchor must not speak from absolute native scroll-window indices; they are one row stale on open.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'motion_delta' `
    -Message 'Set Blue Magic replacement-list anchor should keep native movement separate from the current global spell index.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'window_motion_limit|page_motion_limit' `
    -Message 'Set Blue Magic replacement-list anchor should allow validated native page-sized scroll-window movement for left/right navigation.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'window_delta\s*~=\s*0\s*and\s*math\.abs\(window_delta\)\s*<=\s*math\.max\(visible_count,\s*1\)' `
    -Message 'Set Blue Magic replacement-list anchor must not reject left/right page movement by limiting native window deltas to only the visible row count.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'native_motion_delta|combined_motion_delta' `
    -Message 'Set Blue Magic replacement-list anchor should combine native scroll-window movement with visible-row movement for left/right page navigation.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'window_delta\s*\+\s*selected_delta' `
    -Message 'Set Blue Magic replacement-list anchor should calculate page motion as window delta plus visible selected-row delta.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'math\.abs\(window_delta\)\s*>\s*math\.abs\(selected_delta\)' `
    -Message 'Set Blue Magic replacement-list anchor should prefer a larger native window movement over a small visible-row delta.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'anchor-scroll-window-not-calibrated' `
    -Message 'Set Blue Magic replacement-list anchor must not consume the first up-arrow while waiting for absolute scroll calibration.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'anchor-edge-scroll-window-debounce|return nil,[^\r\n]*anchor-edge-scroll-window' `
    -Message 'Set Blue Magic replacement-list anchor must not silence real native edge-scroll movement; this caused upward scrolling to go quiet.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'selected\s*<=\s*1[\s\S]{0,420}last_global_index\s*-\s*1' `
    -Message 'Set Blue Magic replacement-list anchor must not guess the previous spell from a top-edge row shift.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'selected\s*>=\s*visible_count[\s\S]{0,420}last_global_index\s*\+\s*1' `
    -Message 'Set Blue Magic replacement-list anchor must not guess the next spell from a bottom-edge row shift.'

Assert-Match `
    -Text $anchorBody `
    -Pattern 'anchor\.spell_id\s*=\s*tonumber\(spell\.id\)' `
    -Message 'Set Blue Magic replacement-list anchor should only re-anchor itself from the final selected spell.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern 'native-set-slot-mix-order-edge-shift' `
    -Message 'Set Blue Magic replacement-list anchor must not speak from inferred edge-shift rows.'

Assert-NotMatch `
    -Text $anchorBody `
    -Pattern "anchor\.unsafe_reason\s*=\s*'anchor-visual-row-entry-shifted'" `
    -Message 'Set Blue Magic replacement-list anchor must not permanently disable itself for a handled native edge-row shift.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_anchor_visible_count' `
    -Message 'Set Blue Magic replacement-list anchor fallback should read native visible-row count before trusting visual row offsets.'

Assert-Match `
    -Text $handlerBody `
    -Pattern 'blue_magic_inventory_record_anchor\(native_slot,\s*selected,\s*slot_spell' `
    -Message 'Set Blue Magic current-slot handler should seed the replacement-list anchor from the native selected BLU slot.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue_magic_inventory_spell_from_anchor\(obj,\s*child,\s*entry,\s*selected\)' `
    -Message 'Set Blue Magic replacement-list handler should probe the native set-slot anchor before the miss path.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'native-blue-inventory-anchor:' `
    -Message 'Set Blue Magic replacement-list handler should speak from the native set-slot anchor before the scroll window settles.'

$anchorCallIndex = $inventoryBody.IndexOf('blue_magic_inventory_spell_from_anchor(obj, child, entry, selected)')
$scrollCallIndex = $inventoryBody.IndexOf('blue_magic_inventory_spell_from_native_scroll(obj, child, selected)')
if ($anchorCallIndex -lt 0 -or $scrollCallIndex -lt 0 -or $anchorCallIndex -gt $scrollCallIndex) {
    throw 'Set Blue Magic replacement-list anchor resolver must run before the native scroll-window resolver because the scroll window can be one row stale on open.'
}

Assert-Match `
    -Text $source `
    -Pattern 'anchor-edge-scroll-unsafe|anchor\.unsafe' `
    -Message 'Set Blue Magic replacement-list anchor fallback should stop speaking once edge scrolling makes the visual row offset unsafe.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue-magic-inventory-anchor' `
    -Message 'Set Blue Magic replacement-list anchor fallback should log its native anchor evidence source.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue_magic_set_append_spell_details' `
    -Message 'Set Blue Magic replacement-list handler should include spell details, costs, and Blue Magic point totals.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'player:HasSpell\(spell\.id\)' `
    -Message 'Set Blue Magic replacement-list handler should only speak spells known by the player.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'spell\.type\)\s*==\s*6|type\)\s*==\s*6' `
    -Message 'Set Blue Magic replacement-list handler should restrict rows to Blue Magic resource type.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue-magic-inventory-(missing|native-row|window-help)' `
    -Message 'Set Blue Magic replacement-list handler should log misses instead of falling back to guessed rows.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'native-entry-details|blue-magic-inventory-native-entry' `
    -Message 'Set Blue Magic replacement-list handler should log native-entry detail matches as their own evidence source.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue_magic_inventory_log_missing[\s\S]{0,240}blue_magic_inventory_probe|blue_magic_inventory_probe[\s\S]{0,240}blue_magic_inventory_log_missing' `
    -Message 'Set Blue Magic replacement-list miss path should run the bounded probe alongside the miss log.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_native_scroll_selected' `
    -Message 'Set Blue Magic replacement-list handler should have a native scroll-window selected-index resolver.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_native_scroll_selected[\s\S]{0,2200}read_u32\(child \+ 0x18\)[\s\S]{0,2200}read_u32\(child \+ 0x1C\)[\s\S]{0,2200}window_start \+ visible_count' `
    -Message 'Set Blue Magic replacement-list selected-index resolver should require the native child+18/child+1C scroll-window pair.'

Assert-Match `
    -Text $source `
    -Pattern "function accessxi\.blue_magic_inventory_spell_from_native_scroll[\s\S]{0,2200}magic_mix_category_spell_for_selected\('Blue Magic',\s*scroll_selected\)" `
    -Message 'Set Blue Magic replacement-list native scroll resolver should use the normal client Blue Magic mix.dat category order after native scroll-window verification.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue_magic_inventory_spell_from_native_scroll\(obj,\s*child,\s*selected\)' `
    -Message 'Set Blue Magic replacement-list handler should use the native scroll-window resolver before falling back to diagnostic probes.'

Assert-Match `
    -Text $inventoryBody `
    -Pattern 'blue-magic-inventory-native-scroll-(candidate|quiet)' `
    -Message 'Set Blue Magic replacement-list handler should keep native scroll-window matches as probe-only evidence.'

Assert-NotMatch `
    -Text $inventoryBody `
    -Pattern 'native-blue-inventory-scroll:|blue-magic-inventory-native-scroll-row' `
    -Message 'Set Blue Magic replacement-list handler must not speak from native scroll-window matches because the window can be one row stale.'

Assert-NotMatch `
    -Text $inventoryBody `
    -Pattern "blue_magic_inventory_mix_spell_for_selected|blue-magic-inventory-mix|magic_mix_category_spell_for_selected\('Blue Magic',\s*selected\)|magic_category_spell_for_selected|magic_known_type_auto_spell_for_selected|for id = 0,\s*2048|for id = 1,\s*2048|Cocoon|Battery Charge|Charged Whisker|Entomb|Blazing Bound|Foot Kick|Power Attack" `
    -Message 'Set Blue Magic replacement-list handler must not use visible selected-index mix.dat/order rows, ordinal/fixed lists, or screenshot spell names.'

$nativeEntryStart = $source.IndexOf('function accessxi.blue_magic_inventory_native_entry_segments')
if ($nativeEntryStart -lt 0) {
    throw 'Could not locate Set Blue Magic replacement-list native-entry helpers.'
}
$nativeEntryEnd = $source.IndexOf("`nfunction accessxi.blue_magic_set_log_missing", $nativeEntryStart)
if ($nativeEntryEnd -lt 0) {
    throw 'Could not locate end of Set Blue Magic replacement-list native-entry helpers.'
}
$nativeEntryBody = $source.Substring($nativeEntryStart, $nativeEntryEnd - $nativeEntryStart)

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern 'magic_rendered_row_cells\(entry,\s*selected,\s*16,\s*true\)' `
    -Message 'Set Blue Magic native-entry matcher should scan only selected-row native cells.'

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern 'collect_probe_ascii_runs|collect_probe_ffxi_utf16_entries' `
    -Message 'Set Blue Magic native-entry matcher should collect bounded native detail strings from the selected entry.'

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern 'magic_spell_description_text' `
    -Message 'Set Blue Magic native-entry matcher should normalize native detail strings as spell descriptions.'

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern "magic_known_spell_list_for_category\('Blue Magic'\)" `
    -Message 'Set Blue Magic native-entry matcher should compare against the known Blue Magic resource set, not a fixed row list.'

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern 'player:HasSpell\(spell\.id\)' `
    -Message 'Set Blue Magic native-entry matcher should verify the resource spell is known by the player.'

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern 'match_count\s*==\s*1|matches:len\(\)\s*==\s*1|best_count\s*==\s*1' `
    -Message 'Set Blue Magic native-entry matcher should only return a spell when the native detail match is unique.'

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern 'second_score\s*==\s*0' `
    -Message 'Set Blue Magic native-entry matcher should stay silent when another spell description is also present in the selected native entry.'

Assert-NotMatch `
    -Text $nativeEntryBody `
    -Pattern 'second_score\s*==\s*0\s+or' `
    -Message 'Set Blue Magic native-entry matcher must not accept a second matching spell just because the best score is higher.'

Assert-Match `
    -Text $nativeEntryBody `
    -Pattern 'ambiguous-native-entry|native-entry-ambiguous|match_count\s*>\s*1|matches:len\(\)\s*>\s*1' `
    -Message 'Set Blue Magic native-entry matcher should preserve silence for ambiguous native detail text.'

Assert-NotMatch `
    -Text $nativeEntryBody `
    -Pattern 'entry\s*\+\s*0x24[\s\S]{0,120}\+\s*512|read_u32\(entry\s*\+\s*0x24\)[\s\S]{0,160}spell|Cocoon|Battery Charge|Charged Whisker|Entomb|Blazing Bound|Foot Kick|Power Attack' `
    -Message 'Set Blue Magic native-entry matcher must not treat entry geometry/raw row fields or screenshot names as spell ids.'

$probeStart = $source.IndexOf('function accessxi.log_blue_magic_inventory_probe')
if ($probeStart -lt 0) {
    throw 'Could not locate Set Blue Magic replacement-list diagnostic probe.'
}
$probeEnd = $source.IndexOf("`nfunction accessxi.blue_magic_inventory_menu_speech", $probeStart)
if ($probeEnd -lt 0) {
    throw 'Could not locate end of Set Blue Magic replacement-list diagnostic probe block.'
}
$probeBody = $source.Substring($probeStart, $probeEnd - $probeStart)

Assert-Match `
    -Text $probeBody `
    -Pattern 'blue_magic_inventory_probe_count|last_blue_magic_inventory_probe_key' `
    -Message 'Set Blue Magic replacement-list probe should be capped/throttled to avoid arrowing lag.'

Assert-Match `
    -Text $probeBody `
    -Pattern 'blue-magic-inventory-probe' `
    -Message 'Set Blue Magic replacement-list probe should emit searchable blue-magic-inventory-probe log lines.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_offset_probe' `
    -Message 'Set Blue Magic replacement-list probe should have a focused native start/scroll offset diagnostic.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_blue_mix_probe' `
    -Message 'Set Blue Magic replacement-list probe should have a compact raw+512 Blue Magic mix diagnostic.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_scroll_probe' `
    -Message 'Set Blue Magic replacement-list probe should have a compact native scroll/index diagnostic.'

Assert-Match `
    -Text $source `
    -Pattern 'bluinven-edge-scroll-watch-v1' `
    -Message 'Set Blue Magic replacement-list diagnostics should have a distinct live build marker for the pinned-edge scroll watch.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.blue_magic_inventory_edge_scroll_probe' `
    -Message 'Set Blue Magic replacement-list diagnostics should have a lightweight pinned-edge scroll watch.'

Assert-Match `
    -Text $probeBody `
    -Pattern 'blue_magic_inventory_edge_scroll_probe\(obj,\s*child,\s*entry,\s*selected,\s*count,\s*page,\s*raw\)' `
    -Message 'Set Blue Magic replacement-list duplicate throttle should still sample pinned-edge scroll state.'

$duplicateGateIndex = $probeBody.IndexOf("if (key == tostring(accessxi.last_blue_magic_inventory_probe_key or ''))")
$edgeWatchIndex = $probeBody.IndexOf('blue_magic_inventory_edge_scroll_probe')
if ($duplicateGateIndex -lt 0 -or $edgeWatchIndex -lt 0 -or $edgeWatchIndex -gt $duplicateGateIndex) {
    throw 'Set Blue Magic pinned-edge scroll watch must run before duplicate-key suppression so row-10 scrolling can still be observed.'
}

Assert-Match `
    -Text $probeBody `
    -Pattern 'probe_count\s*>=\s*(64|80)' `
    -Message 'Set Blue Magic replacement-list compact probe should allow enough rows to cross visible-page boundaries.'

Assert-NotMatch `
    -Text $probeBody `
    -Pattern 'blue_magic_inventory_rendered_cell_scan_probe\(obj,\s*child,\s*entry,\s*selected,\s*count,\s*probe_count\)|GetWindowAnkShape|magic_compact_text_probe|magic_pointer_text_targets|log_probe_ptr' `
    -Message 'Set Blue Magic replacement-list miss path should not run heavyweight pointer/shape probes while arrowing.'

Assert-Match `
    -Text $probeBody `
    -Pattern 'blue_magic_inventory_offset_probe\(obj,\s*child,\s*entry,\s*selected,\s*count,\s*probe_count\)' `
    -Message 'Set Blue Magic replacement-list probe should run the focused offset diagnostic on miss.'

Assert-Match `
    -Text $probeBody `
    -Pattern 'blue_magic_inventory_blue_mix_probe\(obj,\s*child,\s*entry,\s*selected,\s*count,\s*probe_count\)' `
    -Message 'Set Blue Magic replacement-list probe should run the compact Blue Magic raw+512 mix diagnostic on miss.'

Assert-Match `
    -Text $probeBody `
    -Pattern 'blue_magic_inventory_scroll_probe\(obj,\s*child,\s*entry,\s*selected,\s*count,\s*probe_count\)' `
    -Message 'Set Blue Magic replacement-list probe should run the compact native scroll/index diagnostic on miss.'

Assert-NotMatch `
    -Text $probeBody `
    -Pattern 'blue-magic-inventory-cell-probe' `
    -Message 'Set Blue Magic replacement-list miss path should not emit heavyweight per-cell probes while arrowing.'

Assert-Match `
    -Text $probeBody `
    -Pattern 'blue-magic-inventory-offset-probe' `
    -Message 'Set Blue Magic replacement-list probe should emit compact native start/scroll offset evidence lines.'

Assert-Match `
    -Text $source `
    -Pattern 'blue-magic-inventory-blue-mix-probe' `
    -Message 'Set Blue Magic replacement-list probe should emit compact raw+512 Blue Magic mix evidence lines.'

Assert-Match `
    -Text $source `
    -Pattern 'blue-magic-inventory-scroll-probe' `
    -Message 'Set Blue Magic replacement-list probe should emit compact native scroll/index evidence lines.'

Assert-Match `
    -Text $source `
    -Pattern 'objStartCandidate|childPackedSelected' `
    -Message 'Set Blue Magic replacement-list offset probe should label native start and packed-selection candidates.'

Assert-Match `
    -Text $source `
    -Pattern "menu_name:eq\('menu    bluequip', true\)[\s\S]{0,220}blue_magic_set_menu_speech" `
    -Message 'Native menu dispatcher should route menu    bluequip to the Set Blue Magic handler.'

Assert-Match `
    -Text $source `
    -Pattern "menu_name:eq\('menu    bluinven', true\)[\s\S]{0,220}blue_magic_inventory_menu_speech" `
    -Message 'Native menu dispatcher should route menu    bluinven to the Set Blue Magic replacement-list handler.'

Write-Host 'set blue magic native static checks ok'

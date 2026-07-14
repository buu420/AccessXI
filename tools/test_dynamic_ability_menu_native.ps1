$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$liveAbilityMetadataPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\third_party\LandSandBoat-server\sql\abilities.sql'

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

$abilityStart = $source.IndexOf('local current_category, category_source = accessxi.ability_effective_category_label();')
if ($abilityStart -lt 0) {
    throw 'Could not locate ability menu speech block.'
}
$abilityEnd = $source.IndexOf("if (menu_name:eq('menu    statcom2'", $abilityStart)
if ($abilityEnd -lt 0) {
    throw 'Could not locate end of ability menu speech block.'
}
$abilityBlock = $source.Substring($abilityStart, $abilityEnd - $abilityStart)

$directStart = $abilityBlock.IndexOf("if (tostring(current_category or '') == '') then")
if ($directStart -lt 0) {
    throw 'Could not locate direct ability shortcut block.'
}
$directEnd = $abilityBlock.IndexOf("local missing_key = ('%s:%s:%d:%d:0x%08X'):fmt(", $directStart)
if ($directEnd -lt 0) {
    throw 'Could not locate end of direct ability shortcut block.'
}
$directBlock = $abilityBlock.Substring($directStart, $directEnd - $directStart)

Assert-Match `
    -Text $abilityBlock `
    -Pattern 'ability_from_backing_model\(obj,\s*child,\s*entry,\s*selected,\s*current_category\)' `
    -Message 'Dynamic Job Abilities and Weapon Skills should use native backing IDs when the current category is known.'

Assert-NotMatch `
    -Text $abilityBlock `
    -Pattern "job_ability_from_known_list\(selected,\s*'Weapon Skills'\)|player-has-weaponskill|player known weapon-skill index" `
    -Message 'Dynamic Weapon Skills must not fall back to row numbers in the sorted player-known list.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_from_native_row_label\(entry,\s*child,\s*selected,\s*count,\s*category\)' `
    -Message 'Expected a shared exact native row-label resolver for dynamic ability rows.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_from_window_help\(category\)' `
    -Message 'Expected a shared native help-window resolver for dynamic ability rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_current_window_help_text.*?GetWindowHelpTitle\(\).*?GetWindowHelpString\(\)" `
    -Message 'Ability help-window resolver should read native help title/help pointers from the target manager.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_from_window_help.*?ability_current_window_help_text\(\).*?ability_exact_info_from_label\(title,\s*category\).*?ability_known_list_for_category" `
    -Message 'Ability help-window resolver should use native help title/help text and exact known resource matching.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_from_native_row_label.*?magic_rendered_row_text\(entry,\s*selected\).*?native_query_label_for_selection\(child,\s*selected,\s*count,\s*'plain'\).*?ability_exact_info_from_label\(rendered_label,\s*category\)" `
    -Message 'Native row-label resolver should use only exact rendered/native query text before resource matching.'

Assert-Match `
    -Text $directBlock `
    -Pattern "(?s)if \(direct_category ~= ''\) then.*?if \(direct_category:eq\('Weapon Skills', true\)\) then\s*local aix_ability, aix_summary, aix_known_total, aix_reason = accessxi\.ability_aix_weapon_skill_for_selected\(selected,\s*child\).*?ability_row_speech\(menu_name,\s*title,\s*direct_category,\s*'direct-native-aix-fast'.*?ability_from_native_row_label\(entry,\s*child,\s*selected,\s*count,\s*direct_category\)" `
    -Message 'Direct Weapon Skills should prefer the proved local AIX order before slower row/help/backing probes.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_aix_read_weapon_order\(\).*?local cache_key = \('%d:%d:%d:%d'\):fmt\(main_job,\s*main_level,\s*sub_job,\s*sub_level\).*?tostring\(cache\.key or ''\) == cache_key.*?< 1000" `
    -Message 'Weapon Skill AIX order cache should be short-lived and keyed by current main/sub job state so job changes cannot reuse stale rows.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_aix_weapon_skill_for_selected\(selected,\s*child\)' `
    -Message 'Weapon Skill AIX selected-row helper is missing.'

$weaponAixStart = $source.IndexOf('function accessxi.ability_aix_weapon_skill_for_selected')
if ($weaponAixStart -lt 0) {
    throw 'Missing Weapon Skill AIX selected-row helper.'
}
$weaponAixEnd = $source.IndexOf("`nfunction accessxi.load_job_ability_metadata", $weaponAixStart)
if ($weaponAixEnd -lt 0) {
    throw 'Could not locate end of Weapon Skill AIX selected-row helper.'
}
$weaponAixBody = $source.Substring($weaponAixStart, $weaponAixEnd - $weaponAixStart)

Assert-Match `
    -Text $weaponAixBody `
    -Pattern "(?s)local\s+live_count,\s*count_source\s*=\s*accessxi\.ability_direct_live_count\(0,\s*child\).*?order\.ids:len\(\)\s*~=\s*live_count" `
    -Message 'Weapon Skill AIX order must match the live ability-specific child count before it can speak.'

Assert-Match `
    -Text $weaponAixBody `
    -Pattern "(?s)local\s+known_list\s*=\s*accessxi\.ability_known_list_for_category\('Weapon Skills'\).*?known_list:len\(\)\s*~=\s*order\.ids:len\(\)" `
    -Message 'Weapon Skill AIX order must cover the current character known Weapon Skill set exactly.'

Assert-Match `
    -Text $weaponAixBody `
    -Pattern "anchor\s*==\s*0\s+or\s+anchor\s*==\s*0xFFFF" `
    -Message 'An unset native Weapon Skill anchor should be accepted only after live-count and current-known-set validation.'

Assert-NotMatch `
    -Text $source `
    -Pattern "ids:len\(\) >= 2(?!\d)|order\.ids:len\(\) < 2(?!\d)" `
    -Message 'Weapon Skill AIX lookup must support a one-row native Weapon Skills menu; low-level characters may only know one weapon skill.'

Assert-Match `
    -Text $directBlock `
    -Pattern "(?s)if \(not direct_category:eq\('Weapon Skills', true\)\) then\s*local backing_ability, backing_category, backing_summary, backing_known_total = accessxi\.ability_from_backing_model\(obj,\s*child,\s*entry,\s*selected,\s*direct_category\)" `
    -Message 'Direct Weapon Skills should not run the backing-model probe, which can lag and produce false positives.'

Assert-Match `
    -Text $abilityBlock `
    -Pattern "(?s)if \(tostring\(current_category or ''\):eq\('Job Abilities', true\) or tostring\(current_category or ''\):eq\('Weapon Skills', true\)\) then.*?ability_from_window_help\(current_category\).*?ability_aix_weapon_skill_for_selected\(selected,\s*child\)" `
    -Message 'Known dynamic ability categories should prefer native help title/help; Weapon Skills may use the proved local AIX order.'

Assert-NotMatch `
    -Text $abilityBlock `
    -Pattern "ability_aix_known_ability_for_selected\(selected,\s*'Job Abilities'\)" `
    -Message 'Dynamic Job Abilities must not speak from local AIX ordinal order until the order signal is proved.'

Assert-Match `
    -Text $directBlock `
    -Pattern "ability_row_speech\(menu_name,\s*title,\s*direct_category,\s*'direct-native-aix-fast'" `
    -Message 'Direct Weapon Skill AIX fast path should speak the resolved dynamic category, not a fixed title.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_is_job_command_type\(ability_type\)' `
    -Message 'Job Ability matching should include state-backed command-like ability types, not only legacy type 1.'

Assert-Match `
    -Text $source `
    -Pattern "job_abilities_packet_bits\s*=\s*''" `
    -Message 'Job Abilities should retain the native 0x0AC JobAbilities bitset, separate from traits.'

Assert-Match `
    -Text $source `
    -Pattern "job_abilities_packet_cache_path\s*=\s*accessxi_paths\.addon_path\('data',\s*'ffxi-job-abilities-bits\.txt'\)" `
    -Message 'Job Ability 0x0AC packet bits should be cached through the addon-relative data path for restart-safe direct menu speech.'

$aixPathStart = $source.IndexOf('function accessxi.ability_aix_order_paths()')
if ($aixPathStart -lt 0) {
    throw 'Missing Weapon Skill AIX profile path helper.'
}
$aixPathEnd = $source.IndexOf("`nfunction accessxi.ability_aix_parse_weapon_order", $aixPathStart)
if ($aixPathEnd -lt 0) {
    throw 'Could not locate end of Weapon Skill AIX profile path helper.'
}
$aixPathBlock = $source.Substring($aixPathStart, $aixPathEnd - $aixPathStart)

Assert-Match `
    -Text $aixPathBlock `
    -Pattern 'macro_active_profile\(\)' `
    -Message 'Weapon Skill AIX lookup should use the current active USER profile.'

Assert-NotMatch `
    -Text $aixPathBlock `
    -Pattern 'fb6a14|1015026|user_root\s*\.\.\s*''\\[0-9a-f]+\\aix\.dat''' `
    -Message 'Weapon Skill AIX lookup must not include fixed USER profile folders from a previous character.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.capture_job_traits_packet\(e\).*?data:sub\(0x44 \+ 1,\s*0x44 \+ 0x40\).*?data:sub\(0xC4 \+ 1,\s*0xC4 \+ 0x20\)" `
    -Message '0x0AC capture should read the JobAbilities block at 0x44 before the existing Traits block at 0xC4.'

Assert-Match `
    -Text $source `
    -Pattern "restore_job_abilities_packet_cache_if_needed\(\)" `
    -Message 'Job Ability 0x0AC packet cache should be restored on addon load.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_direct_live_count\(count,\s*child\)' `
    -Message 'Direct ability menus should derive their live row count from the ability child object when the generic menu count is stale.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_job_ability_for_selected\(selected,\s*count,\s*child\)' `
    -Message 'Direct Job Abilities should resolve through a packet-backed selected-row helper with the native ability child object.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_job_ability_for_selected\(selected,\s*count,\s*child\).*?local live_count, count_source = accessxi\.ability_direct_live_count\(count,\s*child\).*?if \(live_count > 0 and order\.ids:len\(\) ~= live_count\) then.*?return nil,.*?'count'" `
    -Message 'Packet-backed Job Abilities must guard against count mismatches using the ability-specific native child count, not the stale generic count.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_record_menu_category_ok\(record,\s*info\).*?return \(tonumber\(info\.category\)\s*or\s*0\)\s*==\s*0" `
    -Message 'Packet-backed top-level Job Abilities should keep MenuCategoryId 0 as the default top-level rule.'

Assert-Match `
    -Text $source `
    -Pattern "recast_time\s*=\s*tonumber\(recast_time\)\s*or\s*0" `
    -Message 'Job Ability packet metadata should retain SQL recast_time so grouped command children can be distinguished from top-level rows.'

if (-not (Test-Path -LiteralPath $liveAbilityMetadataPath)) {
    throw 'Live addon must include third_party\LandSandBoat-server\sql\abilities.sql so Job Abilities can resolve packet-backed native rows.'
}

Assert-Match `
    -Text $source `
    -Pattern 'job_ability_metadata_by_resource\s*=\s*nil' `
    -Message 'Job Ability metadata should maintain a resource-id map so spoken recast times come from native SQL metadata, not row guesses.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.job_ability_metadata_record_for_resource_id\(resource_id\)' `
    -Message 'Job Ability speech should resolve native metadata by resource id for base recast timing.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_base_recast_seconds\(ability\)' `
    -Message 'Job Ability speech should expose the base recast seconds from native ability metadata.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_base_recast_seconds\(ability\).*?job_ability_metadata_record_for_resource_id\(tonumber\(ability\.id\) or 0\).*?tonumber\(record\.recast_time\) or 0" `
    -Message 'Base recast should come from abilities.sql recast_time for the selected ability resource id.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_recast_speech\(ability,\s*category\)' `
    -Message 'Job Ability row speech should have one helper for current cooldown and base recast text.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_recast_speech\(ability,\s*category\).*?category:eq\('Weapon Skills', true\).*?ability_base_recast_seconds\(ability\).*?ability_current_recast_seconds\(ability\).*?Ready in %s.*?Recast %s" `
    -Message 'Recast speech should skip Weapon Skills, include current remaining cooldown when active, and include the base recast duration.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_is_top_level_job_record\(record,\s*info\)' `
    -Message 'Packet-backed Job Abilities should use an explicit top-level row predicate before trusting 0x0AC order.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_is_top_level_job_record\(record,\s*info\).*?job == 19 and recast_time > 0.*?return false" `
    -Message 'Direct Job Abilities should exclude Dancer child command rows; the live top-level menu only shows Dancer grouped command headings.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_job_record_available\(player,\s*record,\s*info\)' `
    -Message 'Packet-backed Job Abilities should centralize availability checks so grouped command headings can use the native packet bit.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_job_record_available\(player,\s*record,\s*info\).*?job == 19 and recast_time == 0.*?return true" `
    -Message 'Dancer grouped command headings should be accepted from the native 0x0AC bitset even when player:HasAbility does not expose them as regular commands.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_record_menu_category_ok\(record,\s*info\)' `
    -Message 'Packet-backed Job Abilities should centralize the MenuCategoryId gate so Dancer headings can stay top-level without admitting child rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_record_menu_category_ok\(record,\s*info\).*?job == 19 and recast_time == 0.*?return true" `
    -Message 'Dancer grouped command headings should pass the packet top-level MenuCategoryId gate; screenshots show them as top-level direct rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_append_job_records\(.*?ability_packet_is_top_level_job_record\(record,\s*info\)" `
    -Message 'Packet-backed Job Abilities should apply the grouped-command top-level predicate before accepting a row.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_append_job_records\(.*?ability_packet_record_menu_category_ok\(record,\s*info\)" `
    -Message 'Packet-backed Job Abilities should apply the centralized MenuCategoryId gate before accepting a row.'

Assert-Match `
    -Text $source `
    -Pattern "order\s*=\s*tonumber\(record\.order\)\s*or\s*0" `
    -Message 'Accepted packet-backed Job Ability rows should retain metadata order for final native menu ordering.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_sort_order_by_metadata\(order\)' `
    -Message 'Packet-backed Job Abilities should sort accepted main/sub rows by native metadata order, not by job bucket or level.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_job_ability_order\(\).*?ability_packet_append_job_records\(order,.*?'main'.*?ability_packet_append_job_records\(order,.*?'sub'.*?ability_packet_sort_order_by_metadata\(order\)" `
    -Message 'Direct Job Abilities should merge main/sub packet rows, then sort once by metadata order.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_dancer_category_label_is_supported\(label\)' `
    -Message 'Dancer grouped command headings should be recognized as ability subcategory labels.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_note_dancer_heading\(ability,\s*record\).*?ability_dancer_category_label_is_supported\(.*?ability\.name" `
    -Message 'Selecting a top-level Dancer heading should remember its native resource category for the child submenu.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_clear_dancer_heading\(\)' `
    -Message 'Dancer submenu context should have one shared clear path so stale headings cannot drive later speech.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_dancer_heading_is_fresh\(\)' `
    -Message 'Remembered Dancer submenu context should expire instead of persisting across unrelated ability menus.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_ability_dancer_state_probe\(menu_name,\s*title,\s*obj,\s*child,\s*entry,\s*selected,\s*count,\s*page,\s*raw,\s*ability,\s*reason\)' `
    -Message 'Dancer Job Ability debugging should log native child-state changes while category rows are highlighted, without speaking guessed rows.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.log_ability_dancer_state_probe\(.*?ability_direct_child_state\(child\).*?ability_aix_read_known_order\('Job Abilities'\).*?state nativemenu dancer-state-probe" `
    -Message 'Dancer state probe should include hidden child cursor fields and the local AIX order window.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_dancer_probe_dnc_candidate_summary\(order\)' `
    -Message 'Dancer signal finding should log the native DNC candidate rows and their Ashita ability types before attempting child submenu speech.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_row_speech\(.*?ability_recast_speech\(ability,\s*category\).*?spoken_parts:append\(accessxi\.sentence_fragment\(recast_text\)\)" `
    -Message 'Ability row speech should include native-backed recast timing in the spoken row before the description.'

Assert-Match `
    -Text $source `
    -Pattern '(?s)function\s+accessxi\.log_ability_dancer_state_probe\(.*?childD20="%s".*?childD60="%s".*?childDA0="%s".*?dncCandidates="%s"' `
    -Message 'Dancer state probe should log full child-object dword windows and DNC type candidates so the real child selection signal can be identified.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_job_ability_for_selected\(selected,\s*count,\s*child\).*?local record = order\.records ~= nil and order\.records\[selected\] or nil.*?ability_packet_note_dancer_heading\(ability,\s*record\).*?ability_packet_clear_dancer_heading\(\)" `
    -Message 'Packet-backed top-level Job Abilities should remember Dancer headings and clear stale heading context on normal rows.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_dancer_category_order\(label,\s*category_id\)' `
    -Message 'Dancer child ability submenus should derive rows from native packet, SQL metadata, and resource category.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_dancer_resource_matches_heading\(info,\s*label,\s*category_id\)' `
    -Message 'Dancer child submenu row filtering should use the Ashita ability Type signal for the selected native heading.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_dancer_resource_matches_heading\(info,\s*label,\s*category_id\).*?ability_dancer_category_label_is_supported\(label\).*?tonumber\(info\.type\) or 0\) == category_id" `
    -Message 'Dancer child submenu rows should match the selected native heading by Ashita ability Type, not MenuCategoryId.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_dancer_anchor_from_child\(child\)' `
    -Message 'Dancer grouped command probing should read the native selected heading anchor from the live child menu object.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_dancer_anchor_from_child\(child\).*?read_u16\(child \+ 0x74\).*?ability_dancer_category_label_is_supported\(info\.name\)" `
    -Message 'Dancer heading anchor should use child+0x74 and verify it against native ability resources before trusting it.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.log_ability_dancer_anchor_signal_probe\(menu_name,\s*title,\s*obj,\s*child,\s*entry,\s*selected,\s*count,\s*page,\s*raw,\s*reason\)' `
    -Message 'Dancer category signal finding should have a bounded native anchor probe that is independent of speaking rows.'

Assert-Match `
    -Text $source `
    -Pattern '(?s)function\s+accessxi\.log_ability_dancer_anchor_signal_probe\(.*?state nativemenu dancer-anchor-probe.*?anchorId=%d.*?anchorLabel="%s".*?childD00="%s".*?childD40="%s".*?childD80="%s".*?childDC0="%s".*?objD00="%s".*?entryD00="%s".*?categoryRows="%s".*?note="diagnostic only; no guessed speech"' `
    -Message 'Dancer anchor probe should log enough native object windows to find the child cursor without guessed speech.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_dancer_category_for_anchor_child\(child\)' `
    -Message 'Dancer child submenus should resolve from the native anchor child object instead of the parent selected/count fields.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_dancer_category_for_anchor_child\(child\).*?ability_dancer_anchor_from_child\(child\).*?read_u32\(child \+ 0x40\).*?read_u32\(child \+ 0x30\).*?read_u32\(child \+ 0x64\).*?category_signal ~= \(tonumber\(anchor\.category\) or 0\).*?ability_packet_dancer_category_for_selected\(child_selected,\s*child_count,\s*anchor\.name\)" `
    -Message 'Dancer child submenu speech should use child+0x74 for category, child+0x40 for count, child+0x30 for zero-based row, and child+0x64 as the active category guard.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_dancer_category_order\(label,\s*category_id\).*?record\.job\) or 0\) == 19.*?recast_time > 0.*?ability_dancer_resource_matches_heading\(info,\s*label,\s*category_id\).*?player_has_job_command" `
    -Message 'Dancer child submenu rows should be DNC child command records matching the selected native heading type, not top-level headings.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.ability_packet_dancer_category_for_selected\(selected,\s*count,\s*label\)' `
    -Message 'Dancer child ability submenus should resolve selected rows through a count-guarded helper.'

Assert-Match `
    -Text $source `
    -Pattern '(?s)function\s+accessxi\.ability_packet_dancer_category_for_selected\(selected,\s*count,\s*label\).*?ability_packet_dancer_heading_is_fresh\(\).*?ability_packet_top_level_job_ability_count\(\).*?reason="top-level"' `
    -Message 'Remembered Dancer child rows must not speak while the live menu still has the top-level Job Abilities row count.'

Assert-Match `
    -Text $source `
    -Pattern "(?s)function\s+accessxi\.ability_packet_dancer_category_for_selected\(selected,\s*count,\s*label\).*?if \(count > 0 and order\.ids:len\(\) ~= count\) then.*?return nil,.*?'count'" `
    -Message 'Dancer child submenu packet order must refuse speech unless derived rows match the live submenu count.'

Assert-Match `
    -Text $abilityBlock `
    -Pattern "(?s)ability_dancer_category_label_is_supported\(current_category\).*?ability_packet_dancer_category_for_selected\(selected,\s*count,\s*current_category\).*?ability_row_speech" `
    -Message 'Known Dancer subcategory menus should speak from the packet-backed category child order.'

Assert-Match `
    -Text $directBlock `
    -Pattern "(?s)if \(direct_category:eq\('Job Abilities', true\)\) then.*?ability_packet_dancer_category_for_selected\(selected,\s*count,\s*''\).*?direct-native-dancer-category.*?ability_packet_job_ability_for_selected\(selected,\s*count,\s*child\)" `
    -Message 'Direct Job Abilities should try remembered Dancer child submenu rows before the top-level packet order.'

Assert-Match `
    -Text $directBlock `
    -Pattern "(?s)if \(packet_ability ~= nil\) then.*?log_ability_dancer_state_probe\(menu_name,\s*title,\s*obj,\s*child,\s*entry,\s*selected,\s*count,\s*tonumber\(page\) or 0,\s*tonumber\(raw\) or 0,\s*packet_ability,\s*'direct-native-packet'\)" `
    -Message 'Direct packet-backed Job Ability rows should log Dancer native child-state when a grouped Dancer heading is selected.'

Assert-Match `
    -Text $abilityBlock `
    -Pattern "(?s)if \(tostring\(current_category or ''\):eq\('Job Abilities', true\).*?ability_from_window_help\(current_category\).*?ability_packet_job_ability_for_selected\(selected,\s*count,\s*child\).*?ability_from_backing_model\(obj,\s*child,\s*entry,\s*selected,\s*current_category\)" `
    -Message 'Known Job Abilities should try native 0x0AC packet order before backing-model diagnostics.'

Assert-NotMatch `
    -Text $directBlock `
    -Pattern "ability_aix_known_ability_for_selected\(selected,\s*'Job Abilities'\)" `
    -Message 'Direct Job Abilities must not speak from local AIX ordinal order until the order signal is proved.'

Assert-Match `
    -Text $directBlock `
    -Pattern "(?s)local child_menu_type = accessxi\.ability_child_menu_type\(child\).*?if \(child_menu_type == 3\) then\s*direct_category = 'Weapon Skills'.*?elseif \(title_category:eq\('Job Abilities', true\)\)" `
    -Message 'Child menu type 3 should override the misleading Job Abilities title for direct Weapon Skills.'

Assert-Match `
    -Text $directBlock `
    -Pattern "if \(direct_category ~= ''\) then" `
    -Message 'Direct ability shortcut handling should run from the resolved dynamic category, not a fixed title.'

Assert-Match `
    -Text $directBlock `
    -Pattern "(?s)if \(direct_category:eq\('Job Abilities', true\)\) then.*?ability_packet_dancer_category_for_selected\(selected,\s*count,\s*''\).*?local packet_ability, packet_summary, packet_known_total, packet_reason = accessxi\.ability_packet_job_ability_for_selected\(selected,\s*count,\s*child\).*?ability_row_speech\(menu_name,\s*title,\s*direct_category,\s*'direct-native-packet'" `
    -Message 'Direct Job Abilities should speak Dancer child submenus from packet-backed category order, then top-level rows from native 0x0AC order.'

Assert-Match `
    -Text $directBlock `
    -Pattern "log_ability_dancer_anchor_signal_probe\(menu_name,\s*title,\s*obj,\s*child,\s*entry,\s*selected,\s*count,\s*tonumber\(page\)\s*or\s*0,\s*tonumber\(raw\)\s*or\s*0,\s*'direct-job-abilities'\)" `
    -Message 'Direct Job Abilities should continuously log the native Dancer anchor signal while searching for the child cursor.'

Assert-Match `
    -Text $directBlock `
    -Pattern "(?s)if \(direct_category:eq\('Job Abilities', true\)\) then.*?ability_packet_dancer_category_for_anchor_child\(child\).*?direct-native-dancer-category-child.*?ability_packet_dancer_category_for_selected\(selected,\s*count,\s*''\)" `
    -Message 'Direct Job Abilities should prefer the native Dancer child-object selected/count before falling back to remembered heading context.'

Assert-Match `
    -Text $abilityBlock `
    -Pattern "log_ability_dancer_anchor_signal_probe\(menu_name,\s*title,\s*obj,\s*child,\s*entry,\s*selected,\s*count,\s*tonumber\(page\)\s*or\s*0,\s*tonumber\(raw\)\s*or\s*0,\s*'category-job-abilities'\)" `
    -Message 'Known Job Abilities should log the native Dancer anchor signal while searching for the child cursor.'

Assert-Match `
    -Text $abilityBlock `
    -Pattern "(?s)tostring\(current_category or ''\):eq\('Job Abilities', true\).*?ability_packet_dancer_category_for_anchor_child\(child\).*?native-dancer-category-child.*?ability_packet_dancer_category_for_selected\(selected,\s*count,\s*''\)" `
    -Message 'Known Job Abilities should prefer the native Dancer child-object selected/count before falling back to remembered heading context.'

Assert-Match `
    -Text $directBlock `
    -Pattern "log_ability_direct_state_probe\(menu_name,\s*title,\s*obj,\s*child,\s*entry,\s*selected,\s*count,\s*tonumber\(page\)\s*or\s*0,\s*tonumber\(raw\)\s*or\s*0,\s*direct_category,\s*child_menu_type,\s*tostring\(aix_reason or ''\),\s*tostring\(native_label or ''\)\)" `
    -Message 'Direct ability quiet path should capture compact native/state diagnostics before staying silent.'

Assert-NotMatch `
    -Text $directBlock `
    -Pattern "log_ability_direct_raw_probe\(" `
    -Message 'Direct ability quiet path should not run the heavy raw dump while the user arrows through dynamic rows.'

Assert-Match `
    -Text $directBlock `
    -Pattern '(?s)windowHelp="%s".*last_ability_window_help_probe' `
    -Message 'Direct ability quiet path should log the native help-window probe result before staying silent.'

Assert-Match `
    -Text $abilityBlock `
    -Pattern '(?s)windowHelp="%s".*last_ability_window_help_probe' `
    -Message 'Dynamic ability missing path should log the native help-window probe result before staying silent.'

Assert-Match `
    -Text $abilityBlock `
    -Pattern 'usable ability list is dynamic; no known-list fallback' `
    -Message 'Ability menu missing path should document that silence is preferred over ordinal guessing.'

Write-Host 'dynamic ability menu native checks ok'

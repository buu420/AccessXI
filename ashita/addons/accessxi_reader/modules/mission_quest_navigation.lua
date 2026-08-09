local objectives = accessxi.mission_quest_objectives or { missions = {}, quests = {} };

local function clean(value)
    return tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '');
end

local function meaningful_native_details(value)
    value = clean(value);
    local lower = value:lower():gsub('[^a-z0-9]+', '');
    if (lower == '' or lower == 'client' or lower == 'clients'
        or lower == 'summary' or lower == 'missionorders') then
        return '';
    end
    return value;
end

local function player_name()
    if (type(accessxi.current_player_name) ~= 'function') then
        return '';
    end
    return clean(accessxi.current_player_name());
end

local function character_identity()
    if (type(accessxi.current_player_identity) ~= 'function') then
        return '';
    end
    return clean(accessxi.current_player_identity()):lower();
end

local function has_entries(value)
    return type(value) == 'table' and next(value) ~= nil;
end

local function sanitize_navigation_failure_reason(reason)
    local value = clean(reason):match('^[^\r\n]*') or '';
    value = value:match('^.+%.lua:%d+:%s*(.*)$') or value;
    if (value == '') then
        return '';
    end
    value = value:gsub('"', "'");
    if (#value > 96) then
        value = value:sub(1, 96) .. '...';
    end
    return value;
end

local function report_navigation_failure(context, error_message)
    if (type(log_line) ~= 'function' or context == '') then
        return;
    end
    local message = sanitize_navigation_failure_reason(error_message);
    log_line(('mission active context failure context="%s" reason="%s"'):fmt(clean(context), message));
end

local function report_navigation_trace(context, phase)
    if (type(log_line) == 'function' and context ~= '') then
        log_line(('mission active context %s context="%s"'):fmt(phase, clean(context)));
    end
end

local function point_copy(point)
    if (type(point) ~= 'table') then
        return nil;
    end
    return T{
        zone = tonumber(point.zone) or 0,
        name = clean(point.name),
        x = tonumber(point.x) or 0,
        z = tonumber(point.z) or 0,
        y = tonumber(point.y) or 0,
        kind = clean(point.kind),
        source = clean(point.source),
        confidence = clean(point.confidence),
        section = clean(point.section),
        arrival_radius = tonumber(point.arrival_radius),
        objective_kind = clean(point.objective_kind),
        objective_context = clean(point.objective_context),
        objective_area = clean(point.objective_area),
        objective_id = tonumber(point.objective_id),
        objective_stage = clean(point.objective_stage),
        objective_title = clean(point.objective_title),
        objective_instruction = clean(point.objective_instruction),
        arrival_instruction = clean(point.arrival_instruction),
        objective_source = clean(point.objective_source),
        objective_character_identity = clean(point.objective_character_identity),
        objective_native_key = clean(point.objective_native_key),
        guide_step_id = clean(point.guide_step_id),
        verified = point.verified == true,
        route_context_label = clean(point.route_context_label),
    };
end

local function clear_character_state(reason)
    if (type(accessxi.nav_cancel_mission_quest_route) == 'function') then
        accessxi.nav_cancel_mission_quest_route(reason or 'character-state-cleared');
    end
    accessxi.mission_packet_main = {};
    accessxi.mission_packet_tick = 0;
    accessxi.mission_packet_hex = '';
    accessxi.mission_packet_ahturghan = {};
    accessxi.mission_packet_ahturghan_tick = 0;
    accessxi.mission_packet_ahturghan_complete = {};
    accessxi.mission_packet_ahturghan_complete_tick = 0;
    accessxi.mission_packet_cache_loaded = false;
    accessxi.mission_packet_player = '';
    accessxi.mission_packet_identity = '';
    accessxi.mission_packet_source = '';
    accessxi.mission_packet_ahturghan_identity = '';
    accessxi.mission_packet_ahturghan_source = '';
    accessxi.mission_packet_ahturghan_complete_identity = '';
    accessxi.mission_packet_ahturghan_complete_source = '';
    accessxi.last_mission_packet_key = '';

    accessxi.quest_packet_logs = {};
    accessxi.quest_packet_tick = 0;
    accessxi.quest_packet_key = '';
    accessxi.quest_packet_cache_loaded = false;
    accessxi.quest_packet_player = '';
    accessxi.quest_packet_identity = '';
    accessxi.quest_packet_source = '';
    accessxi.last_quest_packet_key = '';

    -- Key-item state already has character ownership. Clear it at the same
    -- boundary so a stale tester bit cannot choose an objective stage.
    accessxi.key_items_packet_tables = {};
    accessxi.key_items_packet_key = '';
    accessxi.key_items_packet_cache_loaded = false;
    accessxi.key_items_packet_player = '';
    accessxi.key_items_packet_identity = '';
    accessxi.key_items_packet_source = '';
    accessxi.key_items_owned_cache = {};

    if (type(accessxi.objective_guides) == 'table'
        and type(accessxi.objective_guides.close) == 'function') then
        accessxi.objective_guides:close(reason or 'character-state-cleared');
    end

    if (type(log_line) == 'function') then
        log_line(('mission quest nav state cleared reason="%s"'):fmt(clean(reason)));
    end
end

function accessxi.nav_mission_quest_sync_character(reason)
    local current_player = player_name();
    local current_identity = character_identity();
    if (current_player == '' or current_identity == '') then
        return false;
    end

    local tracked_identity = clean(accessxi.mission_quest_nav_identity):lower();
    if (tracked_identity == '') then
        local mission_owner = clean(accessxi.mission_packet_identity):lower();
        local quest_owner = clean(accessxi.quest_packet_identity):lower();
        local key_item_owner = clean(accessxi.key_items_packet_identity):lower();
        local stale = (has_entries(accessxi.mission_packet_main) and mission_owner ~= current_identity)
            or (has_entries(accessxi.quest_packet_logs) and quest_owner ~= current_identity)
            or (has_entries(accessxi.key_items_packet_tables) and key_item_owner ~= current_identity);
        if (stale) then
            clear_character_state(reason or 'initial-owner-mismatch');
        end
        accessxi.mission_quest_nav_player = current_player;
        accessxi.mission_quest_nav_identity = current_identity;
        return stale;
    end

    if (tracked_identity == current_identity) then
        accessxi.mission_quest_nav_player = current_player;
        return false;
    end

    clear_character_state(reason or 'character-changed');
    accessxi.mission_quest_nav_player = current_player;
    accessxi.mission_quest_nav_identity = current_identity;
    return true;
end

local function mission_state_ready()
    accessxi.nav_mission_quest_sync_character('mission-category');
    local current_player = player_name();
    local current_identity = character_identity();
    if (current_player == '' or current_identity == '') then
        return false;
    end
    if (type(accessxi.restore_mission_packet_cache_if_needed) == 'function') then
        accessxi.restore_mission_packet_cache_if_needed();
    end
    local packet = accessxi.mission_packet_main or {};
    local source = clean(accessxi.mission_packet_source);
    return clean(accessxi.mission_packet_player) == current_player
        and clean(accessxi.mission_packet_identity):lower() == current_identity
        and (source == 'packet_in_056' or source == 'cache')
        and (tonumber(packet.port) or 0) == 0xFFFF;
end

local function auxiliary_mission_state_ready(context)
    context = clean(context);
    if (context ~= 'Assault' and context ~= 'Treasures of Aht Urhgan'
        and context ~= 'Campaign' and context ~= 'Wings of the Goddess') then
        return true;
    end
    local current_identity = character_identity();
    local source = clean(accessxi.mission_packet_ahturghan_source);
    return current_identity ~= ''
        and clean(accessxi.mission_packet_ahturghan_identity):lower() == current_identity
        and (source == 'packet_in_056' or source == 'cache');
end

local function quest_state_ready()
    accessxi.nav_mission_quest_sync_character('quest-category');
    local current_player = player_name();
    local current_identity = character_identity();
    if (current_player == '' or current_identity == '') then
        return false;
    end
    if (type(accessxi.restore_quest_packet_cache_if_needed) == 'function') then
        accessxi.restore_quest_packet_cache_if_needed();
    end
    local source = clean(accessxi.quest_packet_source);
    if (clean(accessxi.quest_packet_player) ~= current_player
        or clean(accessxi.quest_packet_identity):lower() ~= current_identity
        or (source ~= 'packet_in_056' and source ~= 'cache')) then
        return false;
    end
    for _, area_key in ipairs((accessxi.quests_menu_data or {}).quest_log_order or T{}) do
        local entry = type(accessxi.quest_packet_entry) == 'function'
            and accessxi.quest_packet_entry(area_key, 'current') or nil;
        local entry_source = clean(type(entry) == 'table' and entry.source or '');
        if (type(entry) ~= 'table'
            or (entry_source ~= 'packet_in_056' and entry_source ~= 'cache')
            or clean(entry.identity):lower() ~= current_identity) then
            return false;
        end
    end
    return true;
end

local function mission_route_state_ready(item)
    local current_player = player_name();
    local current_identity = character_identity();
    local packet = accessxi.mission_packet_main or {};
    if (current_player == '' or current_identity == ''
        or clean(accessxi.mission_packet_player) ~= current_player
        or clean(accessxi.mission_packet_identity):lower() ~= current_identity
        or clean(accessxi.mission_packet_source) ~= 'packet_in_056'
        or (tonumber(packet.port) or 0) ~= 0xFFFF) then
        return false;
    end

    local context = clean(type(item) == 'table' and item.mission_context or '');
    if (context == 'Assault' or context == 'Treasures of Aht Urhgan'
        or context == 'Campaign' or context == 'Wings of the Goddess') then
        return clean(accessxi.mission_packet_ahturghan_identity):lower() == current_identity
            and clean(accessxi.mission_packet_ahturghan_source) == 'packet_in_056';
    end
    return true;
end

local function quest_route_state_ready(item)
    local current_player = player_name();
    local current_identity = character_identity();
    if (current_player == '' or current_identity == ''
        or clean(accessxi.quest_packet_player) ~= current_player
        or clean(accessxi.quest_packet_identity):lower() ~= current_identity
        or clean(accessxi.quest_packet_source) ~= 'packet_in_056') then
        return false;
    end

    local area_key = clean(type(item) == 'table' and item.quest_area_key or '');
    local entry = area_key ~= '' and type(accessxi.quest_packet_entry) == 'function'
        and accessxi.quest_packet_entry(area_key, 'current') or nil;
    return type(entry) == 'table'
        and clean(entry.source) == 'packet_in_056'
        and clean(entry.identity):lower() == current_identity;
end

local function key_item_state_available(id)
    if (type(accessxi.restore_key_items_packet_cache_if_needed) == 'function') then
        accessxi.restore_key_items_packet_cache_if_needed();
    end
    local current_player = player_name();
    local current_identity = character_identity();
    if (current_player == '' or current_identity == ''
        or clean(accessxi.key_items_packet_player) ~= current_player
        or clean(accessxi.key_items_packet_identity):lower() ~= current_identity) then
        return false;
    end
    id = tonumber(id) or -1;
    local table_index = math.floor(id / 512);
    local entry = (accessxi.key_items_packet_tables or {})[table_index];
    return type(entry) == 'table'
        and #tostring(entry.flags or '') >= 64
        and clean(entry.source) == 'packet_in_055'
        and clean(entry.identity):lower() == current_identity;
end

local function owns_key_item(id)
    return type(accessxi.key_items_packet_has_id) == 'function'
        and accessxi.key_items_packet_has_id(id) == true;
end

local function effective_kind(point)
    if (type(accessxi.nav_point_effective_kind) == 'function') then
        return clean(accessxi.nav_point_effective_kind(point)):lower();
    end
    return clean(point ~= nil and point.kind or ''):lower();
end

local function referenced_target(reference)
    if (type(reference) ~= 'table') then
        return nil;
    end
    local wanted_zone = tonumber(reference.zone) or 0;
    local wanted_name = clean(reference.name):lower();
    local wanted_kind = clean(reference.kind):lower();
    if (wanted_zone <= 0 or wanted_name == '') then
        return nil;
    end
    local match = nil;
    local match_count = 0;
    for _, point in ipairs(accessxi.nav_points or T{}) do
        if ((tonumber(point.zone) or 0) == wanted_zone
            and clean(point.name):lower() == wanted_name
            and (wanted_kind == '' or effective_kind(point) == wanted_kind)) then
            match = point;
            match_count = match_count + 1;
        end
    end
    if (match_count ~= 1) then
        return nil;
    end
    return point_copy(match);
end

local function objective_target(definition, stage, item)
    local target_info = stage ~= nil and stage.target or nil;
    if (type(target_info) ~= 'table') then
        return nil;
    end
    local target = nil;
    if (type(target_info.reference) == 'table') then
        target = referenced_target(target_info.reference);
    elseif (type(target_info.point) == 'table') then
        target = point_copy(target_info.point);
    end
    if (target == nil or (tonumber(target.zone) or 0) <= 0 or clean(target.name) == '') then
        return nil;
    end

    target.objective_kind = clean(item.objective_kind or item.kind);
    target.objective_context = clean(item.mission_context);
    target.objective_area = clean(item.quest_area);
    target.objective_id = tonumber(item.mission_id or item.quest_id);
    target.objective_stage = clean(stage.key);
    target.objective_title = clean(item.name);
    target.objective_instruction = clean(stage.instruction);
    target.arrival_instruction = clean(stage.arrival_instruction or stage.instruction);
    target.objective_source = clean(definition.source);
    target.objective_character_identity = character_identity();
    if (target.objective_character_identity == '') then
        return nil;
    end
    target.route_context_label = target.objective_kind == 'quest' and 'Quest objective' or 'Mission objective';
    target.section = target.objective_instruction;
    return target;
end

local function set_unavailable(item, status)
    item.objective_available = false;
    item.objective_status = clean(status ~= '' and status or 'unsupported');
    item.objective_stage = '';
    item.objective_instruction = '';
    item.objective_target = nil;
end

local function apply_objective(item)
    local kind = clean(item.objective_kind or item.kind):lower();
    local registry = kind == 'quest' and objectives.quests or objectives.missions;
    local context = kind == 'quest' and clean(item.quest_area_key) or clean(item.mission_context);
    local id = tonumber(item.quest_id or item.mission_id) or -1;
    local definition = type(registry) == 'table' and registry[context .. ':' .. tostring(id)] or nil;
    if (type(definition) ~= 'table') then
        set_unavailable(item, 'unsupported');
        return item;
    end

    local required = definition.required_key_items or T{};
    for _, key_item_id in ipairs(required) do
        if (not key_item_state_available(key_item_id)) then
            set_unavailable(item, 'stage-unverified');
            return item;
        end
    end

    local owned_count = 0;
    for _, key_item_id in ipairs(required) do
        if (owns_key_item(key_item_id)) then
            owned_count = owned_count + 1;
        end
    end
    if (#required > 1 and owned_count > 1) then
        set_unavailable(item, 'stage-unverified');
        return item;
    end

    local stage = nil;
    for _, candidate in ipairs(definition.stages or T{}) do
        local condition = clean(candidate.when):lower();
        if (condition == 'owns' and owns_key_item(candidate.key_item)) then
            stage = candidate;
            break;
        elseif (condition == 'owns-none' and owned_count == 0) then
            stage = candidate;
            break;
        end
    end
    if (stage == nil) then
        set_unavailable(item, 'stage-unverified');
        return item;
    end

    local target = objective_target(definition, stage, item);
    if (target == nil) then
        set_unavailable(item, 'destination-unavailable');
        return item;
    end

    item.objective_available = true;
    item.objective_status = 'verified';
    item.objective_stage = clean(stage.key);
    item.objective_instruction = clean(stage.instruction);
    item.objective_source = clean(definition.source);
    item.objective_target = target;
    return item;
end

local function apply_guide_metadata(item)
    local native_key = clean(type(item) == 'table' and item.objective_native_key or '');
    local entry = native_key ~= '' and type(accessxi.mission_quest_guide_index) == 'table'
        and accessxi.mission_quest_guide_index[native_key] or nil;
    local status = clean(type(entry) == 'table' and entry.status or 'source-missing');
    item.guide_status = status;
    item.guide_available = type(entry) == 'table'
        and status ~= 'source-missing'
        and status ~= 'ambiguous-match';
    return item;
end

local function exact_mission_row(rows, value)
    if (type(rows) ~= 'table') then
        return nil;
    end
    value = tonumber(value);
    if (value == nil) then
        return nil;
    end
    if (type(rows.by_mission_id) == 'table' and rows.by_mission_id[value] ~= nil) then
        return rows.by_mission_id[value];
    end
    for index = 1, tonumber(rows.count) or #rows do
        local row = rows[index];
        if (type(row) == 'table' and tonumber(row.mission_id) == value) then
            return row;
        end
    end
    return nil;
end

local function valid_mission_row(row)
    if (type(row) ~= 'table' or clean(row.label) == '') then
        return false;
    end
    if (type(accessxi.missions_menu_rom_placeholder_label) == 'function'
        and accessxi.missions_menu_rom_placeholder_label(row.label)) then
        return false;
    end
    return true;
end

local function mission_row_for_context(context, value)
    if (type(accessxi.load_mission_rom_rows) ~= 'function') then
        return nil;
    end
    local rows = accessxi.load_mission_rom_rows(context);
    local row = exact_mission_row(rows, value);
    if (row == nil and context == 'Chains of Promathia'
        and type(accessxi.cop_mission_rom_current_row) == 'function') then
        row = accessxi.cop_mission_rom_current_row(rows, value);
    elseif (row == nil and type(accessxi.mission_rom_current_row) == 'function') then
        row = accessxi.mission_rom_current_row(rows, value);
    end
    return valid_mission_row(row) and row or nil;
end

local function append_mission(items, context, value)
    local row = mission_row_for_context(context, value);
    if (row == nil) then
        return;
    end
    local item = T{
        zone = 0,
        name = clean(row.label),
        kind = 'mission',
        objective_kind = 'mission',
        mission_context = clean(context),
        mission_id = tonumber(row.mission_id) or 0,
        objective_native_key = ('mission:%s:%d'):fmt(clean(context), tonumber(row.rom_ordinal) or 0),
        mission_current_value = tonumber(value) or 0,
        source = ('native-active-mission:%s:%d:%s'):fmt(clean(context), tonumber(value) or 0, clean(row.source)),
        confidence = 'native',
        section = clean(context),
        objective_native_details = meaningful_native_details(row.orders),
    };
    items:append(apply_guide_metadata(apply_objective(item)));
end

local function run_safe_mission_context(items, context, build_fn)
    report_navigation_trace(context, 'begin');
    local before_count = #items;
    local ok, err = xpcall(build_fn, function(err)
        return clean(err):match('^[^\r\n]*') or '';
    end);
    if (not ok) then
        report_navigation_failure(context, ('%s'):fmt(err));
        return;
    end
    local added = #items - before_count;
    report_navigation_trace(context, ('done added=%d'):fmt(added >= 0 and added or 0));
end

local function active_missions()
    local items = T{};
    if (not mission_state_ready()) then
        return items;
    end
    local attempted_contexts = 0;
    local packet = accessxi.mission_packet_main or {};
    local nation = tonumber(packet.nation);
    local nation_contexts = T{ [0] = "San d'Oria", [1] = 'Bastok', [2] = 'Windurst' };
    local nation_context = nation_contexts[nation];
    local nation_value = tonumber(packet.nation_mission);
    if (nation_context ~= nil and nation_value ~= nil and nation_value ~= 65535) then
        attempted_contexts = attempted_contexts + 1;
        run_safe_mission_context(items, nation_context, function()
            append_mission(items, nation_context, nation_value);
        end);
    end

    for _, context in ipairs(accessxi.missions_menu_category_labels or T{}) do
        attempted_contexts = attempted_contexts + 1;
        run_safe_mission_context(items, context, function()
            local context_id = type(accessxi.missions_menu_nation_context_id) == 'function'
                and accessxi.missions_menu_nation_context_id(context) or nil;
            local info = type(accessxi.mission_rom_table_for_context) == 'function'
                and accessxi.mission_rom_table_for_context(context) or nil;
            local packet_key = type(info) == 'table' and clean(info.packet) or '';
            -- The main packet's `tales` byte is the TalesBeginning expansion-start
            -- bitfield, not the current Voracious Resurgence mission. TVR stays
            -- silent until its separate native mission packet is captured.
            if (context_id == nil and clean(context) ~= 'Campaign'
                and packet_key ~= '' and packet_key ~= 'tales'
                and auxiliary_mission_state_ready(context)
                and type(accessxi.current_mission_value_for_context) == 'function') then
                local value = tonumber(accessxi.current_mission_value_for_context(context));
                local terminal = value == nil or value <= 0 or value == 65535
                    or ((packet_key == 'acp' or packet_key == 'mkd' or packet_key == 'asa') and value >= 15);
                if (not terminal) then
                    append_mission(items, context, value);
                end
            end
        end);
    end
    if (type(log_line) == 'function') then
        log_line(('mission active context complete attempts=%d results=%d'):fmt(attempted_contexts, #items));
    end
    return items;
end

local function valid_quest_row(row)
    local label = clean(type(row) == 'table' and row.label or '');
    if (label == '' or label:lower():find('^client:') ~= nil
        or label:lower():find('^summary:') ~= nil) then
        return false;
    end
    return true;
end

local function active_quests()
    local items = T{};
    if (not quest_state_ready()) then
        return items;
    end
    for _, area_key in ipairs((accessxi.quests_menu_data or {}).quest_log_order or T{}) do
        local entry = type(accessxi.quest_packet_entry) == 'function'
            and accessxi.quest_packet_entry(area_key, 'current') or nil;
        local rows = type(accessxi.quest_rom_rows_for_area) == 'function'
            and accessxi.quest_rom_rows_for_area(area_key) or nil;
        local resource = ((accessxi.quests_menu_data or {}).quest_log_resources or {})[area_key] or {};
        local max_id = clean(area_key) == 'aht_urhgan' and 127 or 255;
        if (type(entry) == 'table' and type(rows) == 'table') then
            for quest_id = 0, max_id do
                if (type(accessxi.quest_packet_has_id) == 'function'
                    and accessxi.quest_packet_has_id(entry, quest_id)) then
                    local row = rows[quest_id];
                    if (valid_quest_row(row)) then
                        local native_details = '';
                        if (type(accessxi.quest_rom_detail_for_row) == 'function') then
                            local ok, details = pcall(accessxi.quest_rom_detail_for_row, row);
                            if (ok) then
                                native_details = meaningful_native_details(details);
                            end
                        end
                        local item = T{
                            zone = 0,
                            name = clean(row.label),
                            kind = 'quest',
                            objective_kind = 'quest',
                            quest_area_key = clean(area_key),
                            quest_area = clean(resource.label or row.area or area_key),
                            quest_id = quest_id,
                            objective_native_key = ('quest:%s:%d'):fmt(clean(area_key), quest_id),
                            source = ('native-active-quest:%s:%d:%s'):fmt(clean(area_key), quest_id, clean(row.source)),
                            confidence = 'native',
                            section = clean(resource.label or row.area or area_key),
                            objective_native_details = native_details,
                        };
                        items:append(apply_guide_metadata(apply_objective(item)));
                    end
                end
            end
        end
    end
    return items;
end

function accessxi.nav_mission_quest_active_items(category_key)
    category_key = clean(category_key):lower();
    if (category_key == 'mission') then
        return active_missions();
    elseif (category_key == 'quest') then
        return active_quests();
    end
    return T{};
end

function accessxi.nav_mission_quest_item_speech(item, index, total)
    if (type(item) ~= 'table') then
        return '';
    end
    local title = clean(item.name);
    local kind = clean(item.objective_kind or item.kind):lower();
    local location = kind == 'quest' and clean(item.quest_area) or clean(item.mission_context);
    local status = kind == 'quest' and 'Active quest.' or 'Active mission.';
    local prefix = ('%s. %d of %d. %s'):fmt(title ~= '' and title or 'Objective', tonumber(index) or 1, tonumber(total) or 1, status);
    if (location ~= '') then
        prefix = prefix .. ' ' .. location .. '.';
    end
    if (item.objective_available == true and clean(item.objective_instruction) ~= '') then
        prefix = prefix .. ' Current objective: ' .. clean(item.objective_instruction);
    else
        prefix = prefix .. ' No verified route objective is available for this stage.';
    end
    if (item.guide_available == true) then
        return prefix .. ' Guide available. Press I to open steps.';
    end
    local native_details = meaningful_native_details(item.objective_native_details);
    if (native_details ~= '') then
        local detail_label = kind == 'quest' and ' Native quest details: ' or ' Native mission orders: ';
        prefix = prefix .. detail_label .. native_details;
    end
    if (clean(item.guide_status) == 'ambiguous-match') then
        return prefix .. ' Guide match is ambiguous.';
    end
    return prefix .. ' No source-backed guide is available.';
end

local function same_item(a, b)
    local kind = clean(a ~= nil and (a.objective_kind or a.kind) or ''):lower();
    if (kind ~= clean(b ~= nil and (b.objective_kind or b.kind) or ''):lower()) then
        return false;
    end
    if (kind == 'mission') then
        return clean(a.mission_context) == clean(b.mission_context)
            and tonumber(a.mission_id) == tonumber(b.mission_id);
    elseif (kind == 'quest') then
        return clean(a.quest_area_key) == clean(b.quest_area_key)
            and tonumber(a.quest_id) == tonumber(b.quest_id);
    end
    return false;
end

function accessxi.nav_mission_quest_prepare_route(item, player)
    local kind = clean(item ~= nil and (item.objective_kind or item.kind) or ''):lower();
    if (kind ~= 'mission' and kind ~= 'quest') then
        return nil, '', 'not-objective';
    end

    local fresh = nil;
    for _, candidate in ipairs(accessxi.nav_mission_quest_active_items(kind)) do
        if (same_item(item, candidate)) then
            fresh = candidate;
            break;
        end
    end
    local title = clean(item ~= nil and item.name or 'objective');
    if (fresh == nil) then
        return nil, ('%s is no longer present in the current character\'s active %s list.'):fmt(title, kind == 'quest' and 'quest' or 'mission'), 'blocked';
    end
    local route_state_ready = false;
    if (kind == 'mission') then
        route_state_ready = mission_route_state_ready(fresh);
    else
        route_state_ready = quest_route_state_ready(fresh);
    end
    if (not route_state_ready) then
        return nil, ('Current-session packet evidence is not yet available for %s.'):fmt(title), 'blocked';
    end
    if (fresh.objective_available ~= true or type(fresh.objective_target) ~= 'table') then
        return nil, ('No verified route objective is available for this stage of %s.'):fmt(title), 'blocked';
    end
    return point_copy(fresh.objective_target), '', 'ready';
end

local function reviewed_guide_target(item, native_key, guide_step_id, step)
    if (type(step) ~= 'table' or step.route_ready ~= true
        or clean(step.comparison):lower() == 'conflict'
        or clean(step.action):lower() ~= 'talk') then
        return nil;
    end
    local target_info = step.navigation_target;
    if (type(target_info) ~= 'table'
        or clean(target_info.type):lower() ~= 'static-reference'
        or type(target_info.reference) ~= 'table') then
        return nil;
    end
    local target = referenced_target(target_info.reference);
    if (target == nil) then
        return nil;
    end
    local kind = clean(item.objective_kind or item.kind):lower();
    target.objective_kind = kind;
    target.objective_context = clean(item.mission_context);
    target.objective_area = clean(item.quest_area);
    target.objective_id = tonumber(item.mission_id or item.quest_id);
    target.objective_stage = 'manual-guide-step';
    target.objective_title = clean(item.name);
    target.objective_instruction = clean(step.primary_instruction);
    target.arrival_instruction = clean(target_info.arrival_instruction);
    if (target.arrival_instruction == '') then
        return nil;
    end
    target.objective_source = 'reviewed-objective-guide';
    target.objective_character_identity = character_identity();
    target.objective_native_key = native_key;
    target.guide_step_id = guide_step_id;
    target.verified = true;
    target.route_context_label = kind == 'quest' and 'Quest objective' or 'Mission objective';
    return target;
end

function accessxi.nav_mission_quest_guide_route_descriptor(native_key, guide_step_id, step)
    native_key = clean(native_key);
    guide_step_id = clean(guide_step_id);
    local kind = native_key:match('^(mission):') or native_key:match('^(quest):') or '';
    if (kind == '' or guide_step_id == '') then
        return nil;
    end
    for _, item in ipairs(accessxi.nav_mission_quest_active_items(kind)) do
        if (clean(item.objective_native_key) == native_key) then
            local expected_step = clean(item.objective_guide_step_id);
            if (expected_step == '' and type(accessxi.objective_guides) == 'table'
                and type(accessxi.objective_guides.automatic_step_id) == 'function') then
                expected_step = accessxi.objective_guides:automatic_step_id(
                    native_key,
                    clean(item.objective_stage));
            end
            local state_ready = false;
            if (kind == 'mission') then
                state_ready = mission_route_state_ready(item);
            elseif (kind == 'quest') then
                state_ready = quest_route_state_ready(item);
            end
            if (state_ready) then
                local reviewed = reviewed_guide_target(
                    item,
                    native_key,
                    guide_step_id,
                    step);
                if (reviewed ~= nil) then
                    return reviewed;
                end
            end
            if (expected_step == guide_step_id and state_ready and item.objective_available == true
                and type(item.objective_target) == 'table') then
                local descriptor = point_copy(item.objective_target);
                descriptor.verified = true;
                descriptor.guide_step_id = guide_step_id;
                descriptor.objective_native_key = native_key;
                return descriptor;
            end
        end
    end
    return nil;
end

function accessxi.nav_mission_quest_open_guide(item)
    if (type(item) ~= 'table' or item.guide_available ~= true
        or type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.open) ~= 'function') then
        return nil, 'No source-backed guide is available for this objective.';
    end
    local native_key = clean(item.objective_native_key);
    local automatic_step = '';
    local kind = clean(item.objective_kind or item.kind):lower();
    local state_ready = kind == 'mission'
        and mission_route_state_ready(item)
        or (kind == 'quest' and quest_route_state_ready(item));
    if (state_ready and item.objective_available == true) then
        automatic_step = clean(item.objective_guide_step_id);
        if (automatic_step == '' and type(accessxi.objective_guides.automatic_step_id) == 'function') then
            automatic_step = accessxi.objective_guides:automatic_step_id(
                native_key,
                clean(item.objective_stage));
        end
    end
    local objective, reason = accessxi.objective_guides:open(native_key, automatic_step);
    if (objective == nil) then
        return nil, clean(reason);
    end
    return accessxi.objective_guides:repeat_step(), '';
end

function accessxi.nav_mission_quest_prepare_guide_route()
    if (type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.is_open) ~= 'function'
        or not accessxi.objective_guides:is_open()) then
        return nil, 'No objective step is selected.', 'blocked';
    end
    local descriptor = accessxi.objective_guides:route_descriptor();
    if (type(descriptor) ~= 'table') then
        return nil, accessxi.objective_guides:repeat_step(), 'blocked';
    end
    return point_copy(descriptor), '', 'ready';
end

function accessxi.nav_mission_quest_guide_selection_present()
    if (type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.current_native_key) ~= 'function') then
        return false;
    end
    local native_key = clean(accessxi.objective_guides:current_native_key());
    local kind = native_key:match('^(mission):') or native_key:match('^(quest):') or '';
    if (native_key == '' or kind == '') then
        return false;
    end
    for _, item in ipairs(accessxi.nav_mission_quest_active_items(kind)) do
        if (clean(item.objective_native_key) == native_key) then
            return true;
        end
    end
    if (type(accessxi.objective_guides.close) == 'function') then
        accessxi.objective_guides:close('objective-no-longer-active');
    end
    return false;
end

function accessxi.nav_mission_quest_start_suffix(point)
    local instruction = clean(point ~= nil and point.objective_instruction or '');
    return instruction ~= '' and (' Objective: ' .. instruction) or '';
end

function accessxi.nav_mission_quest_arrival_suffix(point)
    local instruction = clean(point ~= nil and point.arrival_instruction or '');
    return instruction ~= '' and (' ' .. instruction) or '';
end

function accessxi.nav_mission_quest_route_context(point)
    return clean(point ~= nil and point.route_context_label or '');
end

local function route_point_owner_mismatch(point, current_identity)
    local kind = clean(type(point) == 'table' and (point.objective_kind or point.kind) or ''):lower();
    if (kind ~= 'mission' and kind ~= 'quest') then
        return false;
    end
    local owner = clean(point.objective_character_identity):lower();
    return owner == '' or owner ~= current_identity;
end

function accessxi.nav_mission_quest_route_owner_mismatch()
    local current_identity = character_identity();
    if (current_identity == '') then
        return false;
    end
    return route_point_owner_mismatch(accessxi.nav_destination, current_identity)
        or route_point_owner_mismatch(accessxi.nav_zone_search_target, current_identity);
end

return true;

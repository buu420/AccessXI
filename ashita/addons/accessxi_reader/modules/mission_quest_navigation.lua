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

local function player_world_id()
    if (type(accessxi.current_player_world_id) ~= 'function') then
        return 0;
    end
    return tonumber(accessxi.current_player_world_id()) or 0;
end

local function objective_session_epoch()
    if (type(accessxi.current_objective_session_epoch) ~= 'function') then
        return 0;
    end
    return tonumber(accessxi.current_objective_session_epoch()) or 0;
end

local function deep_copy(value, seen)
    if (type(value) ~= 'table') then
        return value;
    end
    seen = seen or {};
    if (seen[value] ~= nil) then
        return seen[value];
    end
    local result = {};
    seen[value] = result;
    for key, item in pairs(value) do
        result[deep_copy(key, seen)] = deep_copy(item, seen);
    end
    return result;
end

local objective_progress_loaded = false;
local objective_progress = {};
local pending_objective_interaction = nil;
local active_row_cache = {};
local active_row_cache_owner = '';
local active_build_guide_failed = false;
local source_derivation_cache = {
    revision = nil,
    source_steps = {},
    source_routes = {},
};
local ensure_catalog_index;
local objective_source_steps;
local objective_event_menus = {
    ['menu rem4line'] = true,
    ['menu rem4li2'] = true,
    ['menu spoolmsg'] = true,
    ['menu splmsg2'] = true,
};

local function objective_progress_key(identity, native_key)
    return clean(identity):lower() .. '\t' .. clean(native_key);
end

local function increment_objective_progress_revision()
    accessxi.objective_progress_revision = (tonumber(accessxi.objective_progress_revision) or 0) + 1;
end

local function load_objective_progress()
    if (objective_progress_loaded) then return; end
    objective_progress_loaded = true;
    local path = clean(accessxi.objective_interaction_progress_path);
    if (path == '') then return; end
    local file = io.open(path, 'r');
    if (file == nil) then return; end
    for line in file:lines() do
        local identity, native_key, step_id, order = tostring(line or ''):match(
            '^([^\t]+)\t([^\t]+)\t([^\t]+)\t(%d+)$');
        identity = clean(identity):lower();
        native_key = clean(native_key);
        step_id = clean(step_id);
        order = tonumber(order) or 0;
        if (identity ~= '' and native_key ~= '') then
            local key = objective_progress_key(identity, native_key);
            if (step_id == '-' or order < 1) then
                objective_progress[key] = nil;
            elseif (step_id ~= '') then
                objective_progress[key] = {
                    identity = identity,
                    native_key = native_key,
                    step_id = step_id,
                    order = order,
                };
            end
        end
    end
    file:close();
end

local function append_objective_progress(identity, native_key, step_id, order)
    local path = clean(accessxi.objective_interaction_progress_path);
    if (path == '') then return true; end
    local file = io.open(path, 'a');
    if (file == nil) then
        if (type(log_line) == 'function') then
            log_line(('objective interaction progress write failed path="%s"'):fmt(path));
        end
        return false;
    end
    file:write(clean(identity):lower(), '\t', clean(native_key), '\t',
        clean(step_id), '\t', tostring(tonumber(order) or 0), '\n');
    file:close();
    return true;
end

local function save_objective_progress(identity, native_key, step_id, order)
    load_objective_progress();
    local key = objective_progress_key(identity, native_key);
    local existing = objective_progress[key];
    order = tonumber(order) or 0;
    if (type(existing) == 'table' and (tonumber(existing.order) or 0) >= order) then
        return true;
    end
    if (not append_objective_progress(identity, native_key, step_id, order)) then
        return false;
    end
    objective_progress[key] = {
        identity = clean(identity):lower(),
        native_key = clean(native_key),
        step_id = clean(step_id),
        order = order,
    };
    increment_objective_progress_revision();
    return true;
end

local function clear_objective_progress(identity, native_key)
    load_objective_progress();
    local key = objective_progress_key(identity, native_key);
    if (objective_progress[key] == nil) then return; end
    if (not append_objective_progress(identity, native_key, '-', 0)) then return false; end
    objective_progress[key] = nil;
    increment_objective_progress_revision();
    return true;
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

local function point_copy(point)
    if (type(point) ~= 'table') then
        return nil;
    end
    return T{
        zone = tonumber(point.zone) or 0,
        zone_name = clean(point.zone_name),
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
        objective_instruction = clean(point.objective_action_instruction or point.objective_instruction),
        objective_action_instruction = clean(point.objective_action_instruction or point.objective_instruction),
        objective_route_recommendation = clean(point.objective_route_recommendation),
        objective_classification = clean(point.objective_classification),
        arrival_instruction = clean(point.arrival_instruction or point.objective_action_instruction),
        objective_source = clean(point.objective_source),
        objective_character_identity = clean(point.objective_character_identity),
        objective_world_id = tonumber(point.objective_world_id),
        objective_session_epoch = tonumber(point.objective_session_epoch),
        objective_native_key = clean(point.objective_native_key),
        guide_step_id = clean(point.guide_step_id or point.objective_guide_step_id),
        objective_guide_step_id = clean(point.objective_guide_step_id or point.guide_step_id),
        objective_candidate_id = clean(point.objective_candidate_id),
        objective_action_id = clean(point.objective_action_id),
        objective_group_id = clean(point.objective_group_id),
        objective_destination_id = clean(point.objective_destination_id),
        objective_route_contract_id = clean(point.objective_route_contract_id),
        objective_contract_snapshot = deep_copy(point.objective_contract_snapshot),
        objective_test_route = point.objective_test_route == true,
        objective_active_state_signature = clean(point.objective_active_state_signature),
        objective_active_owner_key = clean(point.objective_active_owner_key),
        destination_id = clean(point.destination_id),
        raw_identity = clean(point.raw_identity),
        raw_spawn_ids = deep_copy(point.raw_spawn_ids),
        cluster_policy_version = clean(point.cluster_policy_version),
        objective_action = clean(point.objective_action),
        objective_items_text = clean(point.objective_items_text),
        objective_enemies_text = clean(point.objective_enemies_text),
        objective_camp_label = clean(point.objective_camp_label),
        objective_destination_zone_name = clean(point.objective_destination_zone_name),
        objective_canonical_edge_id = tonumber(point.objective_canonical_edge_id),
        objective_canonical_from_zone = tonumber(point.objective_canonical_from_zone),
        objective_transport_id = clean(point.objective_transport_id),
        objective_route_evidence = clean(point.objective_route_evidence),
        objective_completion_items = deep_copy(point.objective_completion_items),
        objective_completion_key_items = deep_copy(point.objective_completion_key_items),
        verified = point.verified == true,
        route_context_label = clean(point.route_context_label),
    };
end

local function spoken_list(values)
    local entries = T{};
    local seen = {};
    for _, value in ipairs(type(values) == 'table' and values or T{}) do
        local entry = clean(value);
        local key = entry:lower();
        if (entry ~= '' and seen[key] ~= true) then
            seen[key] = true;
            entries:append(entry);
        end
    end
    if (#entries == 0) then
        return '';
    elseif (#entries == 1) then
        return entries[1];
    elseif (#entries == 2) then
        return entries[1] .. ' and ' .. entries[2];
    end
    return table.concat(entries, ', ', 1, #entries - 1) .. ', and ' .. entries[#entries];
end

local function clear_character_state(reason)
    pending_objective_interaction = nil;
    active_row_cache = {};
    active_row_cache_owner = '';
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
    accessxi.mission_packet_nations_complete = {};
    accessxi.mission_packet_nations_complete_tick = 0;
    accessxi.mission_packet_nations_complete_player = '';
    accessxi.mission_packet_nations_complete_identity = '';
    accessxi.mission_packet_nations_complete_source = '';
    accessxi.mission_packet_cache_loaded = false;
    accessxi.mission_packet_player = '';
    accessxi.mission_packet_identity = '';
    accessxi.mission_packet_source = '';
    accessxi.mission_packet_session_epoch = 0;
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
    accessxi.quest_packet_session_epoch = 0;
    accessxi.last_quest_packet_key = '';

    -- Key-item state already has character ownership. Clear it at the same
    -- boundary so a stale tester bit cannot choose an objective stage.
    accessxi.key_items_packet_tables = {};
    accessxi.key_items_packet_key = '';
    accessxi.key_items_packet_cache_loaded = false;
    accessxi.key_items_packet_player = '';
    accessxi.key_items_packet_identity = '';
    accessxi.key_items_packet_source = '';
    accessxi.key_items_packet_session_epoch = 0;
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
        local nation_complete_owner = clean(accessxi.mission_packet_nations_complete_identity):lower();
        local quest_owner = clean(accessxi.quest_packet_identity):lower();
        local key_item_owner = clean(accessxi.key_items_packet_identity):lower();
        local stale = (has_entries(accessxi.mission_packet_main) and mission_owner ~= current_identity)
            or (has_entries(accessxi.mission_packet_nations_complete) and nation_complete_owner ~= current_identity)
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
        or tonumber(accessxi.mission_packet_session_epoch) ~= objective_session_epoch()
        or (tonumber(packet.port) or 0) ~= 0xFFFF) then
        return false;
    end

    local context = clean(type(item) == 'table' and item.mission_context or '');
    local nation_context = type(accessxi.missions_menu_nation_context_id) == 'function'
        and accessxi.missions_menu_nation_context_id(context) or nil;
    if (clean(type(item) == 'table' and item.mission_availability or '') == 'available-to-start'
        and nation_context ~= nil) then
        local words = accessxi.mission_packet_nations_complete or {};
        if (clean(accessxi.mission_packet_nations_complete_player) ~= current_player
            or clean(accessxi.mission_packet_nations_complete_identity):lower() ~= current_identity
            or clean(accessxi.mission_packet_nations_complete_source) ~= 'packet_in_056'
            or type(words) ~= 'table' or #words < 8) then
            return false;
        end
        if (type(accessxi.current_nation_mission_rank_state) ~= 'function') then
            return false;
        end
        local ok, state = pcall(accessxi.current_nation_mission_rank_state);
        local state_rank = type(state) == 'table' and tonumber(state.rank) or nil;
        local state_rank_points = type(state) == 'table' and tonumber(state.rank_points) or nil;
        if (not ok or type(state) ~= 'table'
            or clean(state.identity):lower() ~= current_identity
            or tonumber(state.nation) ~= tonumber(packet.nation)
            or state_rank == nil or state_rank < 1 or state_rank > 10
            or state_rank_points == nil or state_rank_points < 0 or state_rank_points >= 65535) then
            return false;
        end
    end

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
        or clean(accessxi.quest_packet_source) ~= 'packet_in_056'
        or tonumber(accessxi.quest_packet_session_epoch) ~= objective_session_epoch()) then
        return false;
    end

    local area_key = clean(type(item) == 'table' and item.quest_area_key or '');
    local entry = area_key ~= '' and type(accessxi.quest_packet_entry) == 'function'
        and accessxi.quest_packet_entry(area_key, 'current') or nil;
    return type(entry) == 'table'
        and clean(entry.source) == 'packet_in_056'
        and clean(entry.identity):lower() == current_identity
        and tonumber(entry.session_epoch) == objective_session_epoch();
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
        and clean(entry.identity):lower() == current_identity
        and tonumber(entry.session_epoch) == objective_session_epoch();
end

local function objective_auxiliary_state_ready()
    local current_player = player_name();
    local current_identity = character_identity();
    local epoch = objective_session_epoch();
    if (current_player == '' or current_identity == '' or epoch <= 0
        or clean(accessxi.key_items_packet_player) ~= current_player
        or clean(accessxi.key_items_packet_identity):lower() ~= current_identity
        or (clean(accessxi.inventory_packet_source) ~= 'packet_in_inventory'
            and clean(accessxi.inventory_packet_source) ~= 'native-inventory')
        or clean(accessxi.inventory_packet_identity):lower() ~= current_identity
        or tonumber(accessxi.inventory_packet_session_epoch) ~= epoch) then
        return false;
    end
    local found_key_item_table = false;
    for _, entry in pairs(type(accessxi.key_items_packet_tables) == 'table'
        and accessxi.key_items_packet_tables or {}) do
        if (type(entry) == 'table') then
            found_key_item_table = true;
            if (clean(entry.source) ~= 'packet_in_055'
                or clean(entry.identity):lower() ~= current_identity
                or tonumber(entry.session_epoch) ~= epoch) then
                return false;
            end
        end
    end
    return found_key_item_table;
end

local function objective_inventory_state_ready()
    local current_player = player_name();
    local current_identity = character_identity();
    local epoch = objective_session_epoch();
    local source = clean(accessxi.inventory_packet_source);
    return current_player ~= '' and current_identity ~= ''
        and (source == 'native-inventory' or source == 'packet_in_inventory')
        and clean(accessxi.inventory_packet_player or current_player) == current_player
        and clean(accessxi.inventory_packet_identity):lower() == current_identity
        and tonumber(accessxi.inventory_packet_session_epoch) == epoch;
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

local function same_exact_physical_point(left, right)
    local left_x = tonumber(type(left) == 'table' and left.x or nil);
    local left_z = tonumber(type(left) == 'table' and left.z or nil);
    local left_y = tonumber(type(left) == 'table' and left.y or nil);
    local right_x = tonumber(type(right) == 'table' and right.x or nil);
    local right_z = tonumber(type(right) == 'table' and right.z or nil);
    local right_y = tonumber(type(right) == 'table' and right.y or nil);
    return left_x ~= nil and left_z ~= nil and left_y ~= nil
        and right_x ~= nil and right_z ~= nil and right_y ~= nil
        and left_x == right_x and left_z == right_z and left_y == right_y;
end

local function referenced_target_rank(point)
    return table.concat({
        clean(point ~= nil and point.destination_id or ''),
        clean(point ~= nil and point.raw_identity or ''),
        clean(point ~= nil and point.source or ''),
    }, '\t');
end

local function referenced_target(reference)
    if (type(reference) ~= 'table') then
        return nil;
    end
    local wanted_zone = tonumber(reference.zone) or 0;
    local wanted_name = clean(reference.name):lower();
    local wanted_kind = clean(reference.kind):lower();
    local wanted_destination_id = clean(reference.destination_id);
    if (wanted_zone <= 0 or wanted_name == '') then
        return nil;
    end
    local index = ensure_catalog_index ~= nil and ensure_catalog_index() or nil;
    local reference_key = table.concat({
        tostring(wanted_zone), wanted_name, wanted_kind, wanted_destination_id,
    }, '\t');
    local candidates = accessxi.nav_points or T{};
    if (type(index) == 'table') then
        candidates = wanted_kind ~= '' and wanted_destination_id ~= ''
            and index.referenced_targets[reference_key] or nil;
        if (candidates == nil) then
            candidates = index.points_by_zone_entity[
                ('%d\t%s'):fmt(wanted_zone, wanted_name)] or T{};
        end
    end
    local match = nil;
    local match_count = 0;
    for _, point in ipairs(candidates) do
        if ((tonumber(point.zone) or 0) == wanted_zone
            and clean(point.name):lower() == wanted_name
            and (wanted_kind == '' or effective_kind(point) == wanted_kind)
            and (wanted_destination_id == ''
                or clean(point.destination_id) == wanted_destination_id)) then
            if (match == nil) then
                match = point;
                match_count = 1;
            elseif (same_exact_physical_point(match, point)) then
                if (referenced_target_rank(point) < referenced_target_rank(match)) then
                    match = point;
                end
            else
                match_count = match_count + 1;
            end
        end
    end
    if (match_count ~= 1) then
        return nil;
    end
    return point_copy(match);
end

local function finite_number(value)
    value = tonumber(value);
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge;
end

local function exact_objective_guide_row(row)
    if (type(row) ~= 'table' or row.route_ready == true
        or clean(row.objective_route_contract_id or row.route_contract_id) ~= '') then
        return nil;
    end
    local action_id = clean(row.action_id);
    local guide_step_id = clean(row.guide_step_id);
    local instruction = clean(row.action_instruction);
    if (action_id == '' or guide_step_id == '' or instruction == '') then
        return nil;
    end
    local instruction_only = row.instruction_only == true;
    if (instruction_only) then
        if (clean(row.classification) ~= 'instruction-only'
            or clean(row.status) ~= 'instruction-only'
            or clean(row.reason) ~= 'complete-instruction'
            or row.material ~= true
            or clean(row.candidate_id) ~= ''
            or clean(row.group_id) ~= ''
            or clean(row.destination_id) ~= '') then
            return nil;
        end
        return {
            instruction_only = true,
            action_id = action_id,
            guide_step_id = guide_step_id,
            guide_step_order = tonumber(row.guide_step_order) or 0,
            action = clean(row.action),
            instruction = instruction,
        };
    end

    if (clean(row.classification) ~= 'catalogue-candidate') then
        return nil;
    end

    local candidate_id = clean(row.candidate_id);
    local group_id = clean(row.group_id);
    local destination_id = clean(row.destination_id);
    local action = clean(row.action);
    local zone = tonumber(row.zone) or 0;
    local point = row.target_point;
    if (candidate_id == '' or destination_id == '' or action == ''
        or zone <= 0 or clean(row.zone_name) == '' or clean(row.target_name) == ''
        or clean(row.target_kind) == '' or clean(row.raw_identity) == ''
        or type(point) ~= 'table' or not finite_number(point[1])
        or not finite_number(point[2]) or not finite_number(point[3])) then
        return nil;
    end
    return {
        instruction_only = false,
        candidate_id = candidate_id,
        action_id = action_id,
        group_id = group_id,
        destination_id = destination_id,
        guide_step_id = guide_step_id,
        guide_step_order = tonumber(row.guide_step_order) or 0,
        action = action,
        instruction = instruction,
        zone = zone,
        zone_name = clean(row.zone_name),
        target_name = clean(row.target_name),
        target_kind = clean(row.target_kind),
        target_point = { tonumber(point[1]), tonumber(point[2]), tonumber(point[3]) },
        raw_identity = clean(row.raw_identity),
        raw_spawn_ids = deep_copy(row.raw_spawn_ids),
        cluster_policy_version = clean(row.cluster_policy_version),
        arrival_radius = tonumber(row.arrival_radius),
        source_route_entry_distance2 = tonumber(row.source_route_entry_distance2),
        label = clean(row.label),
        items = deep_copy(row.items),
        key_items = deep_copy(row.key_items),
        completion_items = deep_copy(row.completion_items),
        completion_key_items = deep_copy(row.completion_key_items),
        enemies = deep_copy(row.enemies),
        transport_id = clean(row.transport_id),
    };
end

local function objective_route_recommendation(native_key, through_order)
    if (type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.route_recommendations) ~= 'function') then
        return '';
    end
    local ok, recommendations = pcall(
        accessxi.objective_guides.route_recommendations,
        accessxi.objective_guides,
        native_key,
        through_order);
    if (not ok or type(recommendations) ~= 'table') then return ''; end
    local parts, seen = T{}, {};
    for _, recommendation in ipairs(recommendations) do
        local instruction = clean(type(recommendation) == 'table'
            and recommendation.instruction or '');
        if (instruction ~= '' and seen[instruction] ~= true) then
            seen[instruction] = true;
            parts:append(instruction);
        end
    end
    return table.concat(parts, ' ');
end

local function expanded_objective_row(item, row)
    local reviewed = exact_objective_guide_row(row);
    local identity = character_identity();
    local world_id = player_world_id();
    local session_epoch = objective_session_epoch();
    if (reviewed == nil or identity == '') then
        return nil;
    end
    local result = T{};
    for key, value in pairs(item) do
        result[key] = deep_copy(value);
    end
    result.objective_available = true;
    result.objective_status = reviewed.instruction_only and 'instruction-only' or 'catalogue-candidate';
    result.objective_classification = result.objective_status;
    result.objective_instruction_only = reviewed.instruction_only;
    result.objective_instruction = reviewed.instruction;
    result.objective_action_instruction = reviewed.instruction;
    result.objective_guide_step_id = reviewed.guide_step_id;
    result.objective_guide_step_order = reviewed.guide_step_order;
    result.objective_source_route_entry_distance2 = reviewed.source_route_entry_distance2;
    result.objective_action_id = reviewed.action_id;
    result.objective_candidate_id = reviewed.candidate_id or '';
    result.objective_group_id = reviewed.group_id or '';
    result.objective_destination_id = reviewed.destination_id or '';
    result.objective_route_contract_id = nil;
    result.objective_character_identity = identity;
    result.objective_world_id = world_id;
    result.objective_session_epoch = session_epoch;
    result.objective_action = reviewed.action;
    if (clean(item.mission_availability) ~= 'available-to-start') then
        result.objective_route_recommendation = objective_route_recommendation(
            clean(item.objective_native_key), reviewed.guide_step_order);
    else
        result.objective_route_recommendation = '';
    end
    result.objective_completion_items = deep_copy(reviewed.completion_items);
    result.objective_completion_key_items = deep_copy(reviewed.completion_key_items);
    result.objective_target = nil;
    if (not reviewed.instruction_only) then
        local point = reviewed.target_point;
        result.objective_destination_label = reviewed.label;
        result.objective_destination_zone_name = reviewed.zone_name;
        result.objective_items_text = spoken_list(reviewed.items);
        result.objective_enemies_text = spoken_list(reviewed.enemies);
        result.objective_transport_id = reviewed.transport_id;
        result.objective_target = T{
            zone = reviewed.zone,
            name = reviewed.target_name,
            x = point[1],
            z = point[2],
            y = point[3],
            kind = reviewed.target_kind,
            source = 'typed-objective-candidate',
            confidence = 'untested',
            section = reviewed.instruction,
            destination_id = reviewed.destination_id,
            raw_identity = reviewed.raw_identity,
            raw_spawn_ids = deep_copy(reviewed.raw_spawn_ids),
            cluster_policy_version = reviewed.cluster_policy_version,
            arrival_radius = reviewed.arrival_radius,
            objective_completion_items = deep_copy(reviewed.completion_items),
            objective_completion_key_items = deep_copy(reviewed.completion_key_items),
            objective_route_recommendation = result.objective_route_recommendation,
        };
    end
    return result;
end

local function objective_row_less(left, right)
    local left_order = tonumber(left.objective_guide_step_order) or 0;
    local right_order = tonumber(right.objective_guide_step_order) or 0;
    if (left_order ~= right_order) then
        return left_order < right_order;
    end
    local left_entry_distance = tonumber(left.objective_source_route_entry_distance2);
    local right_entry_distance = tonumber(right.objective_source_route_entry_distance2);
    if (left_entry_distance ~= nil or right_entry_distance ~= nil) then
        left_entry_distance = left_entry_distance or math.huge;
        right_entry_distance = right_entry_distance or math.huge;
        if (left_entry_distance ~= right_entry_distance) then
            return left_entry_distance < right_entry_distance;
        end
    end
    for _, field in ipairs({
        'objective_action_id', 'objective_group_id', 'objective_candidate_id',
    }) do
        local left_value = clean(left[field]);
        local right_value = clean(right[field]);
        if (left_value ~= right_value) then
            return left_value < right_value;
        end
    end
    return false;
end

local function source_name_key(value)
    return clean(value):lower();
end

local source_zone_names = {};
local objective_catalog_index = { revision = nil };

local function current_nav_catalog_revision()
    return tostring(tonumber(accessxi.nav_catalog_revision) or 0);
end

local function reset_source_derivation_cache_if_needed()
    local revision = current_nav_catalog_revision();
    if (source_derivation_cache.revision ~= revision) then
        source_derivation_cache.revision = revision;
        source_derivation_cache.source_steps = {};
        source_derivation_cache.source_routes = {};
    end
    return revision;
end

local function source_point_zone_name(point)
    local zone = tonumber(type(point) == 'table' and point.zone or nil) or 0;
    local explicit = clean(type(point) == 'table' and point.zone_name or '');
    if (explicit ~= '') then
        source_zone_names[zone] = explicit;
        return explicit;
    end
    if (source_zone_names[zone] ~= nil) then
        return source_zone_names[zone];
    end
    local value = '';
    if (zone > 0 and type(accessxi.nav_graph_zone_name) == 'function') then
        local ok, name = pcall(accessxi.nav_graph_zone_name, zone);
        if (ok) then value = clean(name); end
    end
    source_zone_names[zone] = value;
    return value;
end

ensure_catalog_index = function()
    local revision = current_nav_catalog_revision();
    if (objective_catalog_index.revision == revision) then
        return objective_catalog_index;
    end

    source_zone_names = {};
    local index = {
        revision = revision,
        zone_ids_by_name = {},
        points_by_zone_entity = {},
        referenced_targets = {},
        zone_lines = {},
    };
    local point_visits = 0;
    for _, point in ipairs(accessxi.nav_points or T{}) do
        point_visits = point_visits + 1;
        local zone = tonumber(point.zone) or 0;
        if (zone > 0) then
            local zone_name = source_point_zone_name(point);
            if (zone_name ~= '') then
                local zone_key = source_name_key(zone_name);
                index.zone_ids_by_name[zone_key] = index.zone_ids_by_name[zone_key] or {};
                index.zone_ids_by_name[zone_key][zone] = true;
            end

            local name_key = source_name_key(point.name);
            if (name_key ~= '') then
                local entity_key = ('%d\t%s'):fmt(zone, name_key);
                index.points_by_zone_entity[entity_key] = index.points_by_zone_entity[entity_key] or T{};
                index.points_by_zone_entity[entity_key]:append(point);
                local reference_key = table.concat({
                    tostring(zone), name_key, effective_kind(point), clean(point.destination_id),
                }, '\t');
                index.referenced_targets[reference_key] = index.referenced_targets[reference_key] or T{};
                index.referenced_targets[reference_key]:append(point);
            end

            if (effective_kind(point) == 'area'
                and source_name_key(point.name):find('zone line', 1, true) ~= nil) then
                index.zone_lines[zone] = index.zone_lines[zone] or T{};
                index.zone_lines[zone]:append(point);
            end
        end
    end
    objective_catalog_index = index;
    accessxi.nav_objective_catalog_index_build_count =
        (tonumber(accessxi.nav_objective_catalog_index_build_count) or 0) + 1;
    accessxi.nav_objective_catalog_index_point_visit_count =
        (tonumber(accessxi.nav_objective_catalog_index_point_visit_count) or 0) + point_visits;
    return objective_catalog_index;
end

local function source_route_kind_allowed(action, kind)
    action = clean(action):lower();
    kind = clean(kind):lower();
    if (action == 'fight') then
        return kind == 'enemy' or kind == 'nm' or kind == 'live-nm';
    elseif (action == 'talk' or action == 'trade') then
        return kind == 'npc';
    elseif (action == 'examine' or action == 'use') then
        return kind == 'npc' or kind == 'object' or kind == 'area';
    elseif (action == 'obtain') then
        return kind == 'enemy' or kind == 'nm' or kind == 'npc' or kind == 'object';
    end
    return kind == 'npc' or kind == 'object' or kind == 'enemy' or kind == 'nm';
end

-- The two Tombstone spawns share a display name.  LandSandBoat's Bat Hunt
-- mission script binds its cutscene to Tombstone_Upper, whose exact catalogue
-- identity is npc:v1:190:17555989.  Keep this reviewed identity separate from
-- the conflicting wiki grid labels so inventory progression cannot first-match
-- the unrelated lower tombstone.
local reviewed_inventory_followup_targets = {
    ["mission:San d'Oria:2:step-009"] = {
        zone = 190,
        name = 'Tombstone',
        kind = 'npc',
        destination_id = 'npc:v1:190:17555989',
    },
};

-- Nation mission packets retain the same mission ID across internal steps.
-- These exact game-data identities let a completed source-backed interaction
-- advance to the next destination described by the reconciled guide.
local reviewed_interaction_followup_targets = {
    ["mission:San d'Oria:3:step-015"] = {
        zone = 140,
        name = 'Hut Door',
        kind = 'object',
        destination_id = 'object:v1:140:17350951',
    },
};

local function interaction_completion_state_ready(point)
    point = type(point) == 'table' and point or {};
    local required_items = type(point.objective_completion_items) == 'table'
        and point.objective_completion_items or T{};
    local required_key_items = type(point.objective_completion_key_items) == 'table'
        and point.objective_completion_key_items or T{};
    if (#required_items > 0) then
        if (not objective_inventory_state_ready()
            or type(accessxi.objective_inventory_count_by_name) ~= 'function') then
            return false;
        end
        for _, entry in ipairs(required_items) do
            local name = clean(type(entry) == 'table' and (entry.name or entry.item) or entry);
            local count = math.max(1, tonumber(type(entry) == 'table'
                and (entry.count or entry.quantity) or nil) or 1);
            local ok, owned_count, item_id = pcall(accessxi.objective_inventory_count_by_name, name);
            if (name == '' or not ok or tonumber(item_id) == nil
                or (tonumber(owned_count) or 0) < count) then
                return false;
            end
        end
    end
    if (#required_key_items > 0) then
        if (type(accessxi.objective_key_item_owned_by_name) ~= 'function') then
            return false;
        end
        for _, entry in ipairs(required_key_items) do
            local name = clean(type(entry) == 'table' and (entry.name or entry.key_item) or entry);
            local ok, owned, key_item_id = pcall(accessxi.objective_key_item_owned_by_name, name);
            if (name == '' or not ok or tonumber(key_item_id) == nil
                or not key_item_state_available(key_item_id) or owned ~= true) then
                return false;
            end
        end
    end
    return true;
end

local function reviewed_inventory_followup_target(step)
    local step_id = clean(type(step) == 'table' and step.stable_step_id or '');
    local reference = reviewed_inventory_followup_targets[step_id]
        or reviewed_interaction_followup_targets[step_id];
    return reference ~= nil and referenced_target(reference) or nil;
end

local function source_route_point_less(left, right)
    local left_entry_distance = tonumber(left._source_route_entry_distance2);
    local right_entry_distance = tonumber(right._source_route_entry_distance2);
    if (left_entry_distance ~= nil or right_entry_distance ~= nil) then
        left_entry_distance = left_entry_distance or math.huge;
        right_entry_distance = right_entry_distance or math.huge;
        if (left_entry_distance ~= right_entry_distance) then
            return left_entry_distance < right_entry_distance;
        end
    end
    for _, field in ipairs({ 'destination_id', 'raw_identity', 'source', 'name' }) do
        local a = clean(left[field]);
        local b = clean(right[field]);
        if (a ~= b) then return a < b; end
    end
    for _, field in ipairs({ 'zone', 'x', 'z', 'y' }) do
        local a = tonumber(left[field]) or 0;
        local b = tonumber(right[field]) or 0;
        if (a ~= b) then return a < b; end
    end
    return false;
end

local function source_route_entry_distance2(point, zone_entries)
    if (type(point) ~= 'table' or type(zone_entries) ~= 'table') then return nil; end
    local zone = tonumber(point.zone) or 0;
    local x, z = tonumber(point.x), tonumber(point.z);
    if (zone <= 0 or not finite_number(x) or not finite_number(z)) then return nil; end
    local best = nil;
    for _, entry in ipairs(zone_entries[zone] or {}) do
        local entry_x, entry_z = tonumber(entry.x), tonumber(entry.z);
        if (finite_number(entry_x) and finite_number(entry_z)) then
            local dx, dz = x - entry_x, z - entry_z;
            local distance2 = dx * dx + dz * dz;
            if (best == nil or distance2 < best) then best = distance2; end
        end
    end
    return best;
end

local function source_route_candidate(native_key, step, point)
    local step_id = clean(step.stable_step_id);
    local instruction = clean(step.primary_instruction);
    local action = clean(step.action);
    local zone = tonumber(point.zone) or 0;
    local name = clean(point.name);
    local kind = effective_kind(point);
    local x, z, y = tonumber(point.x), tonumber(point.z), tonumber(point.y);
    if (step_id == '' or instruction == '' or action == '' or zone <= 0
        or name == '' or kind == '' or not finite_number(x)
        or not finite_number(z) or not finite_number(y)) then
        return nil;
    end
    local destination_id = clean(point.destination_id);
    if (destination_id == '') then
        destination_id = ('source-point:%d:%s:%.3f:%.3f:%.3f'):fmt(
            zone, source_name_key(name):gsub('[^a-z0-9]+', '-'), x, z, y);
    end
    local raw_identity = clean(point.raw_identity);
    if (raw_identity == '') then
        raw_identity = ('%s:%s'):fmt(clean(point.source) ~= '' and clean(point.source) or 'source-guide', destination_id);
    end
    local action_id = step_id .. ':source-route';
    local zone_name = source_point_zone_name(point);
    local enemies = T{};
    if (kind == 'enemy' or kind == 'nm' or kind == 'live-nm') then
        enemies:append(name);
    end
    return T{
        candidate_id = action_id .. ':candidate:' .. destination_id,
        action_id = action_id,
        group_id = action_id .. ':group:' .. tostring(zone),
        destination_id = destination_id,
        guide_step_id = step_id,
        guide_step_order = tonumber(step.order) or 0,
        action = action,
        action_instruction = instruction,
        arrival_instruction = instruction,
        classification = 'catalogue-candidate',
        route_ready = false,
        zone = zone,
        zone_name = zone_name ~= '' and zone_name or ('zone %d'):fmt(zone),
        target_name = name,
        target_kind = kind,
        target_point = T{ x, z, y },
        raw_identity = raw_identity,
        raw_spawn_ids = deep_copy(point.raw_spawn_ids),
        cluster_policy_version = clean(point.cluster_policy_version),
        arrival_radius = tonumber(point.arrival_radius),
        source_route_entry_distance2 = tonumber(point._source_route_entry_distance2),
        label = ('%s in %s'):fmt(name, zone_name ~= '' and zone_name or ('zone %d'):fmt(zone)),
        items = type(step.items) == 'table' and deep_copy(step.items) or T{},
        key_items = type(step.key_items) == 'table' and deep_copy(step.key_items) or T{},
        enemies = enemies,
    };
end

local function source_route_rows(native_key)
    reset_source_derivation_cache_if_needed();
    native_key = clean(native_key);
    if (source_derivation_cache.source_routes[native_key] ~= nil) then
        return source_derivation_cache.source_routes[native_key];
    end
    local explicit = type(objectives.source_verified_candidates) == 'table'
        and objectives.source_verified_candidates[native_key] or nil;
    if (type(explicit) == 'table' and #explicit > 0) then
        source_derivation_cache.source_routes[native_key] = deep_copy(explicit);
        return source_derivation_cache.source_routes[native_key];
    end
    if (type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.source_route_steps) ~= 'function') then
        active_build_guide_failed = true;
        return T{};
    end
    local steps, steps_ready = objective_source_steps(native_key);
    if (steps_ready == false) then return T{}; end
    local catalog = ensure_catalog_index();
    local known_zones = catalog.zone_ids_by_name;
    local zone_entries = catalog.zone_lines;

    local rows = T{};
    local seen = {};
    for _, step in ipairs(steps) do
        if (type(step) == 'table' and clean(step.comparison):lower() ~= 'conflict'
            and step.optional_nonessential ~= true
            and step.route_recommendation ~= true) then
            local targets = {};
            local navigation_target = step.navigation_target;
            if (type(navigation_target) == 'table') then
                local target = nil;
                if (type(navigation_target.reference) == 'table') then
                    target = referenced_target(navigation_target.reference);
                elseif (type(navigation_target.point) == 'table') then
                    target = point_copy(navigation_target.point);
                end
                if (target ~= nil) then targets[#targets + 1] = target; end
            end

            if (#targets == 0) then
                local allowed_zones = {};
                local entity_names = {};
                for _, value in ipairs(type(step.zones) == 'table' and step.zones or T{}) do
                    local key = source_name_key(value);
                    for zone in pairs(known_zones[key] or {}) do allowed_zones[zone] = true; end
                end
                for _, value in ipairs(type(step.entities) == 'table' and step.entities or T{}) do
                    local key = source_name_key(value);
                    local zone_matches = known_zones[key];
                    if (zone_matches ~= nil) then
                        for zone in pairs(zone_matches) do allowed_zones[zone] = true; end
                    elseif (key ~= '') then
                        entity_names[key] = true;
                    end
                end
                if (next(allowed_zones) ~= nil and next(entity_names) ~= nil) then
                    for zone in pairs(allowed_zones) do
                        for entity_name in pairs(entity_names) do
                            for _, point in ipairs(catalog.points_by_zone_entity[
                                ('%d\t%s'):fmt(zone, entity_name)] or T{}) do
                                if (source_route_kind_allowed(step.action, effective_kind(point))) then
                                    targets[#targets + 1] = point_copy(point);
                                end
                            end
                        end
                    end
                end
            end

            local action = clean(step.action):lower();
            if (action == 'fight' or action == 'obtain') then
                for _, point in ipairs(targets) do
                    local kind = effective_kind(point);
                    if (kind == 'enemy' or kind == 'nm' or kind == 'live-nm') then
                        point._source_route_entry_distance2 = source_route_entry_distance2(point, zone_entries);
                    end
                end
            end
            table.sort(targets, source_route_point_less);
            local per_name_zone = {};
            for _, point in ipairs(targets) do
                local bucket = ('%d\t%s'):fmt(tonumber(point.zone) or 0, source_name_key(point.name));
                per_name_zone[bucket] = (per_name_zone[bucket] or 0) + 1;
                if (per_name_zone[bucket] <= 4) then
                    local row = source_route_candidate(native_key, step, point);
                    local key = row ~= nil and clean(row.destination_id) or '';
                    if (row ~= nil and key ~= '' and seen[key] ~= true) then
                        seen[key] = true;
                        rows:append(row);
                    end
                end
            end
        end
    end
    source_derivation_cache.source_routes[native_key] = rows;
    accessxi.nav_objective_source_route_compute_count =
        (tonumber(accessxi.nav_objective_source_route_compute_count) or 0) + 1;
    return rows;
end

local function objective_required_item(entry)
    if (type(entry) == 'table') then
        return clean(entry.name or entry.item), math.max(1, tonumber(entry.count or entry.quantity) or 1);
    end
    return clean(entry), 1;
end

local function acquisition_row_items_owned(row)
    local action = clean(type(row) == 'table' and row.action or ''):lower();
    local items = type(row) == 'table' and row.items or nil;
    local key_items = type(row) == 'table' and row.key_items or nil;
    if ((action ~= 'fight' and action ~= 'obtain' and action ~= 'farm'
            and action ~= 'trade' and action ~= 'use' and action ~= 'examine')
        or ((type(items) ~= 'table' or #items == 0)
            and (type(key_items) ~= 'table' or #key_items == 0))) then
        return false;
    end
    if (type(items) == 'table' and #items > 0
        and type(accessxi.objective_inventory_count_by_name) ~= 'function') then
        return false;
    end
    for _, entry in ipairs(type(items) == 'table' and items or T{}) do
        local name, required = objective_required_item(entry);
        if (name == '') then
            return false;
        end
        local ok, count, item_id = pcall(accessxi.objective_inventory_count_by_name, name);
        if (not ok or tonumber(item_id) == nil or (tonumber(count) or 0) < required) then
            return false;
        end
    end
    if (type(key_items) == 'table' and #key_items > 0
        and type(accessxi.objective_key_item_owned_by_name) ~= 'function') then
        return false;
    end
    for _, entry in ipairs(type(key_items) == 'table' and key_items or T{}) do
        local name = clean(type(entry) == 'table' and (entry.name or entry.key_item) or entry);
        local ok, owned, key_item_id = pcall(accessxi.objective_key_item_owned_by_name, name);
        if (name == '' or not ok or tonumber(key_item_id) == nil
            or not key_item_state_available(key_item_id) or owned ~= true) then
            return false;
        end
    end
    return true;
end

objective_source_steps = function(native_key)
    reset_source_derivation_cache_if_needed();
    native_key = clean(native_key);
    if (source_derivation_cache.source_steps[native_key] ~= nil) then
        return source_derivation_cache.source_steps[native_key], true;
    end
    if (type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.source_route_steps) ~= 'function') then
        active_build_guide_failed = true;
        return T{}, false;
    end
    local ok, steps = pcall(
        accessxi.objective_guides.source_route_steps,
        accessxi.objective_guides,
        native_key);
    if (not ok or type(steps) ~= 'table') then
        active_build_guide_failed = true;
        return T{}, false;
    end
    local result = T{};
    for _, step in ipairs(steps) do
        if (type(step) == 'table') then result:append(deep_copy(step)); end
    end
    table.sort(result, function(left, right)
        local left_order = tonumber(left.order) or 0;
        local right_order = tonumber(right.order) or 0;
        if (left_order ~= right_order) then return left_order < right_order; end
        return clean(left.stable_step_id) < clean(right.stable_step_id);
    end);
    source_derivation_cache.source_steps[native_key] = result;
    return result, true;
end;

local current_objective_progress;

local function inventory_selected_next_step(native_key, destinations)
    local acquisition = nil;
    local completed = current_objective_progress(native_key);
    local completed_order = tonumber(type(completed) == 'table' and completed.order or nil) or 0;
    local function consider(row, order, step_id)
        order = tonumber(order) or 0;
        step_id = clean(step_id);
        if (order > completed_order and step_id ~= '' and acquisition_row_items_owned(row)
            and (acquisition == nil or order < acquisition.order)) then
            acquisition = { order = order, step_id = step_id };
        end
    end
    for _, step in ipairs(objective_source_steps(native_key)) do
        if (step.optional_nonessential ~= true and step.route_recommendation ~= true) then
            consider(step, step.order, step.stable_step_id);
        end
    end
    for _, row in ipairs(type(destinations) == 'table' and destinations or T{}) do
        consider(row, row.guide_step_order, row.guide_step_id);
    end
    if (acquisition == nil or acquisition.step_id == '') then
        return nil;
    end
    for _, step in ipairs(objective_source_steps(native_key)) do
        local action = clean(step.action):lower();
        local comparison = clean(step.comparison):lower();
        local reviewed_conflict = comparison == 'conflict'
            and reviewed_inventory_followup_target(step) ~= nil;
        if ((tonumber(step.order) or 0) > acquisition.order
            and action ~= '' and action ~= 'note'
            and (comparison ~= 'conflict' or reviewed_conflict)
            and clean(step.stable_step_id) ~= ''
            and clean(step.primary_instruction) ~= '') then
            return step;
        end
    end
    return nil;
end

local function exact_gate_guard_role(step)
    local aliases = {
        ['gate guard'] = true,
        ["san d'orian gate guard"] = true,
        ['bastok gate guard'] = true,
        ['bastokan gate guard'] = true,
        ['windurst gate guard'] = true,
    };
    for _, entity in ipairs(type(step) == 'table' and step.entities or T{}) do
        if (aliases[source_name_key(entity)] == true) then
            return true;
        end
    end
    return false;
end

-- A nation mission cannot be present in the live 0x056 active slot until its
-- Gate Guard acceptance interaction has completed.  The first Gate Guard talk
-- whose source instruction explicitly says to accept, begin, start, receive,
-- get, activate, or select the mission is that boundary.
-- Preparation advice such as Silent Oil or rank-bar crystal trades may
-- legitimately precede it, while later Gate Guard turn-ins must not match.
local function mission_acceptance_instruction(step)
    local instruction = table.concat({
        clean(type(step) == 'table' and step.primary_instruction or ''),
        clean(type(step) == 'table' and step.bg_instruction or ''),
        clean(type(step) == 'table' and step.ffxiclopedia_instruction or ''),
    }, ' '):lower();
    if (instruction:find('accept', 1, true) ~= nil
        or instruction:find('begin this mission', 1, true) ~= nil
        or instruction:find('begin the mission', 1, true) ~= nil
        or instruction:find('start the mission', 1, true) ~= nil
        or instruction:find('activate this mission', 1, true) ~= nil
        or instruction:find('receive the mission', 1, true) ~= nil
        or instruction:find('get the mission', 1, true) ~= nil
        or instruction:find('receive the actual mission', 1, true) ~= nil) then
        return true;
    end
    return instruction:find('select', 1, true) ~= nil
        and instruction:find('mission', 1, true) ~= nil;
end

local function nation_mission_acceptance_step(native_key)
    for _, step in ipairs(objective_source_steps(native_key)) do
        local action = clean(step.action):lower();
        if (action == 'talk' and exact_gate_guard_role(step)
            and mission_acceptance_instruction(step)) then
            return step;
        end
    end
    return nil;
end

current_objective_progress = function(native_key)
    load_objective_progress();
    local identity = character_identity();
    if (identity == '' or clean(native_key) == '') then return nil; end
    local record = objective_progress[objective_progress_key(identity, native_key)];
    if (type(record) ~= 'table') then return nil; end
    for _, step in ipairs(objective_source_steps(native_key)) do
        if (clean(step.stable_step_id) == clean(record.step_id)
            and (tonumber(step.order) or 0) == (tonumber(record.order) or 0)) then
            return record;
        end
    end
    return nil;
end;

local function ensure_active_nation_mission_acceptance(native_key)
    local identity = character_identity();
    local step = nation_mission_acceptance_step(native_key);
    local step_id = clean(type(step) == 'table' and step.stable_step_id or '');
    local order = tonumber(type(step) == 'table' and step.order or nil) or 0;
    if (identity == '' or step_id == '' or order < 1) then
        return false;
    end
    local completed = current_objective_progress(native_key);
    if ((tonumber(type(completed) == 'table' and completed.order or nil) or 0) >= order) then
        return true;
    end
    local saved = save_objective_progress(identity, native_key, step_id, order);
    if (saved and type(log_line) == 'function') then
        log_line(('objective mission activation completed native="%s" step="%s" order=%d'):fmt(
            clean(native_key), step_id, order));
    end
    return saved;
end

local function next_routable_progress_step(native_key, destinations)
    local completed = current_objective_progress(native_key);
    local completed_order = tonumber(type(completed) == 'table' and completed.order or nil) or 0;
    local routable = {};
    local first_material = nil;
    for _, row in ipairs(type(destinations) == 'table' and destinations or T{}) do
        local step_id = clean(row.guide_step_id or row.objective_guide_step_id);
        if (step_id ~= '') then routable[step_id] = true; end
    end
    for _, row in ipairs(source_route_rows(native_key)) do
        local step_id = clean(row.guide_step_id);
        if (step_id ~= '') then routable[step_id] = true; end
    end
    for _, step in ipairs(objective_source_steps(native_key)) do
        local step_id = clean(step.stable_step_id);
        local action = clean(step.action):lower();
        local order = tonumber(step.order) or 0;
        if (order > completed_order
            and step_id ~= '' and action ~= '' and action ~= 'note'
            and step.optional_nonessential ~= true
            and step.route_recommendation ~= true
            and clean(step.primary_instruction) ~= '') then
            first_material = first_material or step;
            if (routable[step_id] == true
                or reviewed_inventory_followup_target(step) ~= nil
                or exact_gate_guard_role(step)) then
                return step;
            end
        end
    end
    return first_material;
end

local function objective_step_by_id(native_key, step_id)
    step_id = clean(step_id);
    if (step_id == '') then return nil; end
    for _, step in ipairs(objective_source_steps(native_key)) do
        if (clean(step.stable_step_id) == step_id) then return step; end
    end
    return nil;
end

local function progression_completion_requirements(native_key, selected_step)
    local selected_order = tonumber(type(selected_step) == 'table' and selected_step.order or nil) or 0;
    local completed = current_objective_progress(native_key);
    local completed_order = tonumber(type(completed) == 'table' and completed.order or nil) or 0;
    local items, key_items = T{}, T{};
    local seen_items, seen_key_items = {}, {};
    local requirement_actions = {
        fight = true,
        obtain = true,
        farm = true,
        trade = true,
        use = true,
        examine = true,
    };
    if (selected_order <= completed_order) then return items, key_items; end
    for _, step in ipairs(objective_source_steps(native_key)) do
        local order = tonumber(step.order) or 0;
        local action = clean(step.action):lower();
        if (order > completed_order and order <= selected_order
            and requirement_actions[action] == true
            and step.optional_nonessential ~= true
            and step.route_recommendation ~= true) then
            for _, entry in ipairs(type(step.items) == 'table' and step.items or T{}) do
                local key = clean(type(entry) == 'table' and (entry.name or entry.item) or entry):lower();
                if (key ~= '' and seen_items[key] ~= true) then
                    seen_items[key] = true;
                    items:append(deep_copy(entry));
                end
            end
            for _, entry in ipairs(type(step.key_items) == 'table' and step.key_items or T{}) do
                local key = clean(type(entry) == 'table' and (entry.name or entry.key_item) or entry):lower();
                if (key ~= '' and seen_key_items[key] ~= true) then
                    seen_key_items[key] = true;
                    key_items:append(deep_copy(entry));
                end
            end
        end
    end
    return items, key_items;
end

local function objective_target_server_ids(point)
    local ids = {};
    for _, value in ipairs(type(point) == 'table' and point.raw_spawn_ids or T{}) do
        local id = tonumber(value) or 0;
        if (id > 0) then ids[id] = true; end
    end
    local destination_id = clean(type(point) == 'table' and
        (point.destination_id or point.objective_destination_id) or '');
    local id = tonumber(destination_id:match(':(%d+)$')) or 0;
    if (id > 0) then ids[id] = true; end
    return ids;
end

function accessxi.nav_mission_quest_record_step_completion(point, reason)
    if (type(point) ~= 'table') then return false; end
    local kind = clean(point.objective_kind or point.kind):lower();
    local identity = character_identity();
    local native_key = clean(point.objective_native_key);
    local step_id = clean(point.objective_guide_step_id or point.guide_step_id);
    if ((kind ~= 'mission' and kind ~= 'quest') or identity == ''
        or clean(point.objective_character_identity):lower() ~= identity
        or native_key == '' or step_id == '') then
        return false;
    end
    local expected_world = tonumber(point.objective_world_id) or 0;
    local expected_session = tonumber(point.objective_session_epoch) or 0;
    if ((expected_world > 0 and player_world_id() > 0 and expected_world ~= player_world_id())
        or (expected_session > 0 and objective_session_epoch() > 0
            and expected_session ~= objective_session_epoch())) then
        return false;
    end
    local step = objective_step_by_id(native_key, step_id);
    local order = tonumber(type(step) == 'table' and step.order or nil) or 0;
    if (step == nil or order < 1
        or not save_objective_progress(identity, native_key, step_id, order)) then
        return false;
    end
    local cancelled = false;
    if (type(accessxi.nav_cancel_mission_quest_route) == 'function') then
        local ok, result = pcall(
            accessxi.nav_cancel_mission_quest_route,
            'objective-interaction-completed');
        cancelled = ok and result == true;
    end
    if (type(accessxi.on_objective_interaction_progress_changed) == 'function') then
        pcall(accessxi.on_objective_interaction_progress_changed, kind, cancelled);
    end
    if (type(log_line) == 'function') then
        log_line(('objective interaction completed kind=%s native="%s" step="%s" order=%d reason="%s"'):fmt(
            kind, native_key, step_id, order, clean(reason)));
    end
    return true;
end

function accessxi.nav_mission_quest_remember_arrival(point, now)
    if (type(point) ~= 'table') then return false; end
    local kind = clean(point.objective_kind or point.kind):lower();
    local identity = character_identity();
    local native_key = clean(point.objective_native_key);
    local step_id = clean(point.objective_guide_step_id or point.guide_step_id);
    if ((kind ~= 'mission' and kind ~= 'quest') or identity == ''
        or clean(point.objective_character_identity):lower() ~= identity
        or native_key == '' or step_id == ''
        or objective_step_by_id(native_key, step_id) == nil) then
        return false;
    end
    pending_objective_interaction = {
        point = deep_copy(point),
        arrived_at = tonumber(now) or 0,
        target_name = clean(point.name),
        target_server_ids = objective_target_server_ids(point),
        event_started = false,
        text_seen = false,
    };
    return true;
end

local function pending_interaction_owner_current(pending)
    if (type(pending) ~= 'table' or type(pending.point) ~= 'table') then
        return false;
    end
    local point = pending.point;
    local current_identity = character_identity();
    if (current_identity == ''
        or clean(point.objective_character_identity):lower() ~= current_identity) then
        return false;
    end
    local expected_world = tonumber(point.objective_world_id) or 0;
    local expected_session = tonumber(point.objective_session_epoch) or 0;
    local current_world = player_world_id();
    local current_session = objective_session_epoch();
    return not (expected_world > 0 and current_world > 0 and expected_world ~= current_world)
        and not (expected_session > 0 and current_session > 0
            and expected_session ~= current_session);
end

function accessxi.nav_mission_quest_clear_pending_interaction(reason)
    local had_pending = pending_objective_interaction ~= nil;
    pending_objective_interaction = nil;
    if (had_pending and type(log_line) == 'function') then
        log_line(('objective interaction cleared reason="%s"'):fmt(clean(reason)));
    end
    return had_pending;
end

function accessxi.nav_mission_quest_observe_interaction_text(
    menu_name, target_name, target_server_id, text, now)
    local pending = pending_objective_interaction;
    now = tonumber(now) or 0;
    if (type(pending) ~= 'table'
        or now < (tonumber(pending.arrived_at) or 0)
        or (now - (tonumber(pending.arrived_at) or 0)) > 1200000
        or clean(text) == '') then
        return false;
    end
    if (not pending_interaction_owner_current(pending)) then
        pending_objective_interaction = nil;
        return false;
    end
    local expected_ids = pending.target_server_ids or {};
    local actual_id = tonumber(target_server_id) or 0;
    local id_matched = actual_id > 0 and expected_ids[actual_id] == true;
    local has_expected_id = next(expected_ids) ~= nil;
    local name_matched = clean(target_name):lower() ~= ''
        and clean(target_name):lower() == clean(pending.target_name):lower();
    if ((has_expected_id and actual_id > 0 and not id_matched)
        or (not id_matched and not name_matched)) then
        return false;
    end
    if (not interaction_completion_state_ready(pending.point)) then
        return false;
    end
    pending.text_seen = true;
    local normalized_menu = clean(menu_name):lower();
    if (objective_event_menus[normalized_menu] == true) then
        pending.event_started = true;
        pending.menu_name = normalized_menu;
    end
    return true;
end

function accessxi.nav_mission_quest_observe_event_menu(menu_name, now)
    local pending = pending_objective_interaction;
    if (type(pending) ~= 'table' or not pending_interaction_owner_current(pending)) then
        pending_objective_interaction = nil;
        return false;
    end
    local normalized_menu = clean(menu_name):lower();
    if (objective_event_menus[normalized_menu] == true) then
        pending.event_started = true;
        pending.menu_name = normalized_menu;
        return false;
    end
    if (pending.event_started ~= true or pending.text_seen ~= true) then
        return false;
    end
    pending_objective_interaction = nil;
    return accessxi.nav_mission_quest_record_step_completion(
        pending.point,
        'completed-interaction-menu');
end

function accessxi.nav_mission_quest_observe_event_packet(
    phase, target_server_id, zone_id, event_id, now)
    local pending = pending_objective_interaction;
    now = tonumber(now) or 0;
    if (type(pending) ~= 'table'
        or now < (tonumber(pending.arrived_at) or 0)
        or (now - (tonumber(pending.arrived_at) or 0)) > 1200000) then
        return false;
    end
    if (not pending_interaction_owner_current(pending)) then
        pending_objective_interaction = nil;
        return false;
    end

    phase = clean(phase):lower();
    local actual_target = tonumber(target_server_id) or 0;
    local actual_zone = tonumber(zone_id) or 0;
    local actual_event = tonumber(event_id) or 0;
    local expected_ids = pending.target_server_ids or {};
    local expected_zone = tonumber(pending.point.zone
        or pending.point.objective_destination_zone
        or (type(pending.point.objective_target) == 'table'
            and pending.point.objective_target.zone or nil)) or 0;
    if (actual_target <= 0 or expected_ids[actual_target] ~= true
        or actual_zone <= 0 or expected_zone <= 0 or actual_zone ~= expected_zone
        or actual_event <= 0) then
        return false;
    end

    if (phase == 'start') then
        if (not interaction_completion_state_ready(pending.point)) then
            return false;
        end
        pending.packet_event_started = true;
        pending.packet_event_target = actual_target;
        pending.packet_event_zone = actual_zone;
        pending.packet_event_id = actual_event;
        pending.packet_event_started_at = now;
        pending.event_started = true;
        return true;
    end
    if (phase ~= 'finish'
        or pending.packet_event_started ~= true
        or actual_target ~= (tonumber(pending.packet_event_target) or 0)
        or actual_zone ~= (tonumber(pending.packet_event_zone) or 0)
        or actual_event ~= (tonumber(pending.packet_event_id) or 0)
        or now < (tonumber(pending.packet_event_started_at) or 0)) then
        return false;
    end

    pending_objective_interaction = nil;
    return accessxi.nav_mission_quest_record_step_completion(
        pending.point,
        'completed-interaction-packet');
end

local function prune_objective_progress(category, active_items)
    load_objective_progress();
    local identity = character_identity();
    if (identity == '') then return; end
    local active = {};
    for _, item in ipairs(active_items or T{}) do
        local native_key = clean(item.objective_native_key);
        if (native_key ~= '') then active[native_key] = true; end
    end
    local stale = {};
    local prefix = clean(category):lower() .. ':';
    for _, record in pairs(objective_progress) do
        if (type(record) == 'table' and clean(record.identity):lower() == identity
            and clean(record.native_key):lower():sub(1, #prefix) == prefix
            and active[clean(record.native_key)] ~= true) then
            stale[#stale + 1] = clean(record.native_key);
        end
    end
    for _, native_key in ipairs(stale) do
        clear_objective_progress(identity, native_key);
    end
end

local nation_gate_guards;

local function append_gate_guard_step_rows(item, step, replacements)
    if (not exact_gate_guard_role(step)
        or type(accessxi.missions_menu_nation_context_id) ~= 'function') then
        return;
    end
    local nation = accessxi.missions_menu_nation_context_id(clean(item.mission_context));
    for _, reference in ipairs(nation_gate_guards[tonumber(nation) or -1] or T{}) do
        local point = referenced_target(reference);
        local row = point ~= nil and source_route_candidate(
            clean(item.objective_native_key), step, point) or nil;
        local replacement = row ~= nil and expanded_objective_row(item, row) or nil;
        if (replacement ~= nil) then replacements:append(replacement); end
    end
end

local function append_reviewed_inventory_followup_row(item, step, replacements)
    local point = reviewed_inventory_followup_target(step);
    if (point == nil) then
        return;
    end
    local row = source_route_candidate(clean(item.objective_native_key), step, point);
    local replacement = row ~= nil and expanded_objective_row(item, row) or nil;
    if (replacement ~= nil) then
        replacements:append(replacement);
    end
end

local function append_source_route_replacements(item, replacements, selected_step)
    if (#replacements > 0) then
        return;
    end
    local native_key = clean(item.objective_native_key);
    local selected_step_id = clean(type(selected_step) == 'table' and selected_step.stable_step_id or '');
    if (item.objective_available == true and type(item.objective_target) == 'table'
        and clean(item.objective_instruction) ~= '' and selected_step_id == '') then
        local stage = clean(item.objective_stage);
        local row = source_route_candidate(native_key, T{
            stable_step_id = native_key .. ':stage:' .. (stage ~= '' and stage or 'current'),
            order = 0,
            comparison = 'source-backed',
            action = 'navigate',
            primary_instruction = clean(item.objective_instruction),
        }, item.objective_target);
        local replacement = expanded_objective_row(item, row);
        if (replacement ~= nil) then replacements:append(replacement); end
        return;
    end
    if (clean(item.objective_stage) ~= '' and selected_step_id == '') then return; end
    for _, destination in ipairs(source_route_rows(native_key)) do
        if (selected_step_id == '' or clean(destination.guide_step_id) == selected_step_id) then
            local replacement = expanded_objective_row(item, destination);
            if (replacement ~= nil) then replacements:append(replacement); end
        end
    end
    if (#replacements == 0 and selected_step_id ~= '') then
        local instruction = clean(selected_step.primary_instruction);
        local action = clean(selected_step.action);
        local row = T{
            candidate_id = '',
            action_id = selected_step_id .. ':cursor',
            group_id = '',
            destination_id = '',
            guide_step_id = selected_step_id,
            guide_step_order = tonumber(selected_step.order) or 0,
            action = action,
            action_instruction = instruction,
            instruction_only = true,
            classification = 'instruction-only',
            status = 'instruction-only',
            reason = 'complete-instruction',
            material = true,
            route_ready = false,
        };
        local replacement = expanded_objective_row(item, row);
        if (replacement ~= nil) then replacements:append(replacement); end
    end
end

local function stamp_progression_requirements(native_key, selected_step, replacements)
    if (type(selected_step) ~= 'table') then return; end
    local items, key_items = progression_completion_requirements(native_key, selected_step);
    for _, replacement in ipairs(replacements or T{}) do
        replacement.objective_completion_items = deep_copy(items);
        replacement.objective_completion_key_items = deep_copy(key_items);
        if (type(replacement.objective_target) == 'table') then
            replacement.objective_target.objective_completion_items = deep_copy(items);
            replacement.objective_target.objective_completion_key_items = deep_copy(key_items);
        end
    end
end

local function objective_guide_destinations(native_key)
    native_key = clean(native_key);
    if (type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.objective_destinations) ~= 'function') then
        active_build_guide_failed = true;
        return T{};
    end
    local ok, destinations = pcall(
        accessxi.objective_guides.objective_destinations,
        accessxi.objective_guides,
        native_key);
    local snapshot = T{};
    if (ok and type(destinations) == 'table') then
        for _, destination in ipairs(destinations) do
            if (type(destination) == 'table') then
                snapshot:append(deep_copy(destination));
            end
        end
    else
        active_build_guide_failed = true;
    end
    return snapshot;
end

local function expand_active_mission_destinations(items)
    local expanded = T{};
    for _, item in ipairs(items or T{}) do
        local replacements = T{};
        local selected_step = nil;
        local availability = clean(item.mission_availability);
        if (availability == 'available-to-start') then
            local start_step_id = clean(item.objective_start_step_id);
            if (start_step_id ~= '' and type(item.objective_target) == 'table') then
                selected_step = objective_step_by_id(clean(item.objective_native_key), start_step_id);
                local row = selected_step ~= nil and source_route_candidate(
                    clean(item.objective_native_key), selected_step, item.objective_target) or nil;
                local replacement = row ~= nil and expanded_objective_row(item, row) or nil;
                if (replacement ~= nil) then replacements:append(replacement); end
            else
                selected_step = nation_mission_acceptance_step(clean(item.objective_native_key));
                if (selected_step ~= nil) then
                    append_gate_guard_step_rows(item, selected_step, replacements);
                end
            end
        elseif (availability == 'active') then
            local destinations = objective_guide_destinations(clean(item.objective_native_key));
            if (type(destinations) == 'table') then
                local expected_step = '';
                local stage_filter_ready = clean(item.objective_stage) == '';
                local inventory_step = nil;
                local progress_step = next_routable_progress_step(
                    clean(item.objective_native_key), destinations);
                if (clean(item.objective_stage) ~= ''
                    and type(accessxi.objective_guides.automatic_step_id) == 'function') then
                    local step_ok, step_id = pcall(
                        accessxi.objective_guides.automatic_step_id,
                        accessxi.objective_guides,
                        clean(item.objective_native_key),
                        clean(item.objective_stage));
                    if (step_ok) then
                        expected_step = clean(step_id);
                        stage_filter_ready = expected_step ~= '';
                    end
                elseif (clean(item.objective_stage) == '') then
                    local inventory_destinations = destinations;
                    if (#inventory_destinations == 0) then
                        inventory_destinations = source_route_rows(
                            clean(item.objective_native_key));
                    end
                    inventory_step = inventory_selected_next_step(
                        clean(item.objective_native_key), inventory_destinations);
                    if (inventory_step ~= nil) then
                        expected_step = clean(inventory_step.stable_step_id);
                        stage_filter_ready = expected_step ~= '';
                    end
                end
                if (progress_step ~= nil) then
                    local expected = objective_step_by_id(
                        clean(item.objective_native_key), expected_step);
                    if (expected == nil
                        or (tonumber(progress_step.order) or 0) > (tonumber(expected.order) or 0)) then
                        inventory_step = progress_step;
                        expected_step = clean(progress_step.stable_step_id);
                        stage_filter_ready = expected_step ~= '';
                    end
                end
                if (expected_step ~= '') then
                    selected_step = objective_step_by_id(clean(item.objective_native_key), expected_step);
                end
                if (stage_filter_ready) then
                    for _, destination in ipairs(destinations) do
                        local replacement = expanded_objective_row(item, destination);
                        if (replacement ~= nil and (expected_step == ''
                            or clean(replacement.objective_guide_step_id) == expected_step)) then
                            replacements:append(replacement);
                        end
                    end
                    if (#replacements == 0 and inventory_step ~= nil) then
                        append_reviewed_inventory_followup_row(item, inventory_step, replacements);
                    end
                    if (#replacements == 0 and inventory_step ~= nil) then
                        append_gate_guard_step_rows(item, inventory_step, replacements);
                    end
                end
            end
        end
        if (#replacements == 0) then
            append_source_route_replacements(item, replacements, selected_step);
        end
        if (#replacements > 0) then
            stamp_progression_requirements(clean(item.objective_native_key), selected_step, replacements);
            table.sort(replacements, objective_row_less);
            for _, replacement in ipairs(replacements) do
                expanded:append(replacement);
            end
        else
            expanded:append(item);
        end
    end
    return expanded;
end

local function expand_active_quest_destinations(items)
    local expanded = T{};
    for _, item in ipairs(items or T{}) do
        local replacements = T{};
        local selected_step = nil;
        do
            local destinations = objective_guide_destinations(clean(item.objective_native_key));
            if (type(destinations) == 'table') then
                local expected_step = '';
                local stage_filter_ready = clean(item.objective_stage) == '';
                local state_step = inventory_selected_next_step(
                    clean(item.objective_native_key),
                    #destinations > 0 and destinations
                        or source_route_rows(clean(item.objective_native_key)));
                if (clean(item.objective_stage) ~= ''
                    and type(accessxi.objective_guides.automatic_step_id) == 'function') then
                    local step_ok, step_id = pcall(
                        accessxi.objective_guides.automatic_step_id,
                        accessxi.objective_guides,
                        clean(item.objective_native_key),
                        clean(item.objective_stage));
                    if (step_ok) then
                        expected_step = clean(step_id);
                        stage_filter_ready = expected_step ~= '';
                    end
                end
                local progress_step = next_routable_progress_step(
                    clean(item.objective_native_key), destinations);
                if (state_step ~= nil) then
                    expected_step = clean(state_step.stable_step_id);
                    stage_filter_ready = expected_step ~= '';
                end
                if (progress_step ~= nil) then
                    local expected = objective_step_by_id(
                        clean(item.objective_native_key), expected_step);
                    if (expected == nil
                        or (tonumber(progress_step.order) or 0)
                            > (tonumber(expected.order) or 0)) then
                        expected_step = clean(progress_step.stable_step_id);
                        stage_filter_ready = expected_step ~= '';
                    end
                end
                selected_step = objective_step_by_id(
                    clean(item.objective_native_key), expected_step);
                if (stage_filter_ready) then
                    for _, destination in ipairs(destinations) do
                        local replacement = expanded_objective_row(item, destination);
                        if (replacement ~= nil and (expected_step == ''
                            or clean(replacement.objective_guide_step_id) == expected_step)) then
                            replacements:append(replacement);
                        end
                    end
                end
            end
        end
        if (#replacements == 0) then
            append_source_route_replacements(item, replacements, selected_step);
        end
        if (#replacements > 0) then
            stamp_progression_requirements(
                clean(item.objective_native_key), selected_step, replacements);
            table.sort(replacements, objective_row_less);
            for _, replacement in ipairs(replacements) do expanded:append(replacement); end
        else
            expanded:append(item);
        end
    end
    return expanded;
end

nation_gate_guards = {
    [0] = T{
        T{ zone = 230, name = 'Ambrotien', kind = 'npc' },
        T{ zone = 230, name = 'Endracion', kind = 'npc' },
        T{ zone = 231, name = 'Grilau', kind = 'npc' },
    },
    [1] = T{
        T{ zone = 234, name = 'Rashid', kind = 'npc' },
        T{ zone = 235, name = 'Cleades', kind = 'npc' },
        T{ zone = 236, name = 'Argus', kind = 'npc' },
        T{ zone = 237, name = 'Malduc', kind = 'npc' },
    },
    [2] = T{
        T{ zone = 240, name = 'Janshura-Rashura', kind = 'npc' },
        T{ zone = 238, name = 'Mokyokyo', kind = 'npc' },
        T{ zone = 239, name = 'Zokima-Rokima', kind = 'npc' },
        T{ zone = 241, name = 'Rakoh Buuma', kind = 'npc' },
    },
};

local function nation_gate_guard_target(nation, player)
    local candidates = nation_gate_guards[tonumber(nation) or -1] or T{};
    local resolved = T{};
    for _, reference in ipairs(candidates) do
        local target = referenced_target(reference);
        if (target ~= nil) then
            resolved:append(target);
        end
    end
    if (#resolved == 0) then
        return nil;
    end

    local player_zone = tonumber(type(player) == 'table' and player.zone or 0) or 0;
    local player_x = tonumber(type(player) == 'table' and player.x or nil);
    local player_z = tonumber(type(player) == 'table' and player.z or nil);
    local best = nil;
    local best_distance = nil;
    for _, target in ipairs(resolved) do
        if ((tonumber(target.zone) or 0) == player_zone) then
            local distance = 0;
            if (player_x ~= nil and player_z ~= nil) then
                local dx = (tonumber(target.x) or 0) - player_x;
                local dz = (tonumber(target.z) or 0) - player_z;
                distance = (dx * dx) + (dz * dz);
            end
            if (best == nil or distance < best_distance) then
                best = target;
                best_distance = distance;
            end
        end
    end
    return best or resolved[1];
end

local function available_mission_target(item, nation, player)
    local target = nation_gate_guard_target(nation, player);
    if (target == nil) then
        return nil;
    end
    local title = clean(item.name);
    local instruction = ('Talk to a gate guard to accept %s.'):fmt(title ~= '' and title or 'this mission');
    target.objective_kind = 'mission';
    target.objective_context = clean(item.mission_context);
    target.objective_id = tonumber(item.mission_id);
    target.objective_stage = 'accept-mission';
    target.objective_title = title;
    target.objective_instruction = instruction;
    target.arrival_instruction = instruction;
    target.objective_source = 'native-nation-mission-availability';
    target.objective_character_identity = character_identity();
    target.objective_native_key = clean(item.objective_native_key);
    target.route_context_label = 'Mission objective';
    target.section = instruction;
    return target;
end

local rhapsodies_start_zones = T{ 230, 231, 232, 234, 235, 236, 238, 239, 240, 241 };

local function rhapsodies_start_step(native_key)
    for _, step in ipairs(objective_source_steps(native_key)) do
        for _, entity in ipairs(type(step.entities) == 'table' and step.entities or T{}) do
            if (source_name_key(entity) == "tales' beginning") then
                return step;
            end
        end
    end
    return nil;
end

local function rhapsodies_start_target(item, step)
    local player_zone = tonumber(type(accessxi.nav_current_position) == 'table'
        and accessxi.nav_current_position.zone or nil) or 0;
    local zones = T{};
    if (player_zone > 0) then zones:append(player_zone); end
    for _, zone in ipairs(rhapsodies_start_zones) do
        if (zone ~= player_zone) then zones:append(zone); end
    end
    local target = nil;
    for _, zone in ipairs(zones) do
        target = referenced_target(T{ zone = zone, name = "Tales' Beginning", kind = 'npc' });
        if (target ~= nil) then break; end
    end
    if (target == nil) then return nil; end
    local instruction = clean(type(step) == 'table' and step.primary_instruction or '');
    target.objective_kind = 'mission';
    target.objective_context = clean(item.mission_context);
    target.objective_id = tonumber(item.mission_id);
    target.objective_stage = 'start-mission';
    target.objective_title = clean(item.name);
    target.objective_instruction = instruction;
    target.arrival_instruction = instruction;
    target.objective_source = 'native-rhapsodies-postponed-start';
    target.objective_character_identity = character_identity();
    target.objective_native_key = clean(item.objective_native_key);
    target.route_context_label = 'Mission objective';
    target.section = instruction;
    return target;
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
        mission_availability = 'active',
        objective_character_identity = character_identity(),
        objective_world_id = player_world_id(),
        objective_session_epoch = objective_session_epoch(),
        objective_native_key = ('mission:%s:%d'):fmt(clean(context), tonumber(row.rom_ordinal) or 0),
        mission_current_value = tonumber(value) or 0,
        source = ('native-active-mission:%s:%d:%s'):fmt(clean(context), tonumber(value) or 0, clean(row.source)),
        confidence = 'native',
        section = clean(context),
        objective_native_details = meaningful_native_details(row.orders),
    };
    if (type(accessxi.missions_menu_nation_context_id) == 'function'
        and accessxi.missions_menu_nation_context_id(context) ~= nil) then
        ensure_active_nation_mission_acceptance(clean(item.objective_native_key));
    end
    items:append(apply_guide_metadata(apply_objective(item)));
end

local nation_mission_types = {
    [0] = T{ 1, 3, 1, 0, 1, 0, 2, 2, 2, 2, 3, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    [1] = T{ 2, 0, 1, 0, 1, 0, 2, 2, 2, 2, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    [2] = T{ 2, 0, 0, 0, 1, 0, 2, 2, 2, 2, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
};

local nation_mission_crystals = {
    [3] = 9, [4] = 17, [5] = 42, [10] = 12, [11] = 30, [12] = 48,
    [13] = 36, [15] = 44, [16] = 36, [17] = 93, [18] = 45, [19] = 119,
    [20] = 57, [21] = 148, [22] = 96, [23] = 228,
};

local function required_nation_rank(mission_id)
    if (mission_id <= 2) then
        return 1;
    elseif (mission_id >= 10 and mission_id <= 12) then
        return 3;
    elseif (mission_id == 13) then
        return 4;
    elseif (mission_id >= 14) then
        return math.floor((mission_id - 14) / 2) + 5;
    end
    return 2;
end

local function nation_mission_rank_points_ready(rank, rank_points, mission_id)
    local crystals = tonumber(nation_mission_crystals[mission_id]) or 0;
    local rank_factor = (0.372 * rank * rank) - (1.62 * rank) + 6.2;
    if (rank_factor <= 0) then
        return false;
    end
    local points_needed = 1024 * (crystals - 0.25) / (3 * rank_factor);
    return rank_points >= points_needed;
end

local function completed_nation_mission(nation, mission_id)
    local words = accessxi.mission_packet_nations_complete or {};
    local word_index = (nation * 2) + math.floor(mission_id / 32) + 1;
    local word = tonumber(words[word_index]) or 0;
    return bit.band(word, 2 ^ (mission_id % 32)) ~= 0;
end

local function available_nation_mission_ids(nation, rank, rank_points)
    local available = T{};
    local types = nation_mission_types[nation];
    if (type(types) ~= 'table') then
        return available;
    end
    -- Bastok and Windurst 1-1 use dedicated gate-guard events instead of the
    -- ordinary mission mask. Their scripts require only the matching nation,
    -- no active mission, and a not-completed 1-1 bit.
    if ((nation == 1 or nation == 2) and not completed_nation_mission(nation, 0)) then
        available:append(0);
        return available;
    end
    local last_required = -1;
    for index = 1, #types do
        local mission_id = index - 1;
        local required_rank = required_nation_rank(mission_id);
        local rank_ready = rank > required_rank
            or (rank == required_rank and nation_mission_rank_points_ready(rank, rank_points, mission_id));
        local prerequisite_ready = last_required < 0 or completed_nation_mission(nation, last_required);
        if (not rank_ready or not prerequisite_ready) then
            break;
        end

        local mission_type = tonumber(types[index]) or 2;
        local completed = completed_nation_mission(nation, mission_id);
        -- Retail requires a nation mission-status value before offering 5-1,
        -- but that value is not present in the client packet. Stay silent at
        -- that boundary instead of inferring it from rank alone.
        if (mission_id == 14 and rank == 5 and not completed) then
            break;
        elseif (mission_type == 0) then
            if (not completed) then
                available:append(mission_id);
                last_required = mission_id;
            end
        elseif (mission_type == 1) then
            available:append(mission_id);
        elseif (mission_type == 3) then
            available:append(mission_id);
            last_required = mission_id;
        end
    end
    return available;
end

local function append_available_nation_mission(items, context, nation, mission_id)
    local row = mission_row_for_context(context, mission_id);
    if (row == nil) then
        return;
    end
    local item = T{
        zone = 0,
        name = clean(row.label),
        kind = 'mission',
        objective_kind = 'mission',
        mission_context = clean(context),
        mission_id = tonumber(row.mission_id) or mission_id,
        mission_nation = nation,
        mission_availability = 'available-to-start',
        objective_character_identity = character_identity(),
        objective_world_id = player_world_id(),
        objective_session_epoch = objective_session_epoch(),
        objective_native_key = ('mission:%s:%d'):fmt(clean(context), tonumber(row.rom_ordinal) or 0),
        source = ('native-available-mission:%s:%d:%s'):fmt(clean(context), mission_id, clean(row.source)),
        confidence = 'native',
        section = clean(context),
        objective_native_details = meaningful_native_details(row.orders),
    };
    local target = available_mission_target(item, nation, nil);
    if (target ~= nil) then
        item.objective_available = true;
        item.objective_status = 'verified';
        item.objective_stage = 'accept-mission';
        item.objective_instruction = clean(target.objective_instruction);
        item.objective_source = clean(target.objective_source);
        item.objective_target = target;
    else
        set_unavailable(item, 'destination-unavailable');
    end
    items:append(apply_guide_metadata(item));
end

local function append_available_rhapsodies_mission(items)
    local context = "Rhapsodies of Vana'diel";
    if (type(accessxi.load_mission_rom_rows) ~= 'function') then return; end
    local rows = accessxi.load_mission_rom_rows(context);
    local row = nil;
    for index = 1, tonumber(type(rows) == 'table' and rows.count or nil)
        or (type(rows) == 'table' and #rows or 0) do
        if (valid_mission_row(rows[index])) then
            row = rows[index];
            break;
        end
    end
    if (row == nil) then return; end
    local native_key = ('mission:%s:%d'):fmt(context, tonumber(row.rom_ordinal) or 0);
    local step = rhapsodies_start_step(native_key);
    local item = T{
        zone = 0,
        name = clean(row.label),
        kind = 'mission',
        objective_kind = 'mission',
        mission_context = context,
        mission_id = tonumber(row.mission_id) or 0,
        mission_availability = 'available-to-start',
        objective_character_identity = character_identity(),
        objective_world_id = player_world_id(),
        objective_session_epoch = objective_session_epoch(),
        objective_native_key = native_key,
        objective_start_step_id = clean(type(step) == 'table' and step.stable_step_id or ''),
        source = ('native-available-rhapsodies:%s'):fmt(clean(row.source)),
        confidence = 'native',
        section = context,
        objective_native_details = meaningful_native_details(row.orders),
    };
    local target = step ~= nil and rhapsodies_start_target(item, step) or nil;
    if (target ~= nil and item.objective_start_step_id ~= '') then
        item.objective_available = true;
        item.objective_status = 'source-backed';
        item.objective_stage = 'start-mission';
        item.objective_instruction = clean(target.objective_instruction);
        item.objective_source = clean(target.objective_source);
        item.objective_target = target;
    else
        set_unavailable(item, 'destination-unavailable');
    end
    items:append(apply_guide_metadata(item));
end

local function run_safe_mission_context(items, context, build_fn)
    local ok, err = xpcall(build_fn, function(err)
        return clean(err):match('^[^\r\n]*') or '';
    end);
    if (not ok) then
        report_navigation_failure(context, ('%s'):fmt(err));
        return;
    end
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
    elseif (nation_context ~= nil and nation_value == 65535
        and mission_route_state_ready(T{
            mission_context = nation_context,
            mission_availability = 'available-to-start',
        })) then
        local ok, rank_state = pcall(accessxi.current_nation_mission_rank_state);
        if (ok and type(rank_state) == 'table'
            and tonumber(rank_state.nation) == nation
            and clean(rank_state.identity):lower() == character_identity()) then
            for _, mission_id in ipairs(available_nation_mission_ids(
                nation,
                tonumber(rank_state.rank) or 0,
                tonumber(rank_state.rank_points) or 0)) do
                append_available_nation_mission(items, nation_context, nation, mission_id);
            end
        end
    end


    local rov_value = tonumber(packet.rov);
    local tales = tonumber(packet.tales) or 0;
    if ((rov_value == nil or rov_value <= 0 or rov_value == 65535)
        and bit.band(tales, 0x0040) ~= 0) then
        attempted_contexts = attempted_contexts + 1;
        run_safe_mission_context(items, "Rhapsodies of Vana'diel", function()
            append_available_rhapsodies_mission(items);
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
                local raw_value = accessxi.current_mission_value_for_context(context);
                local value = tonumber(raw_value);
                local terminal = value == nil or value <= 0 or value == 65535
                    or ((packet_key == 'acp' or packet_key == 'mkd' or packet_key == 'asa') and value >= 15);
                if (not terminal) then
                    append_mission(items, context, value);
                end
            end
        end);
    end
    prune_objective_progress('mission', items);
    local expanded = expand_active_mission_destinations(items);
    if (type(log_line) == 'function') then
        log_line(('mission active context complete attempts=%d results=%d'):fmt(attempted_contexts, #expanded));
    end
    return expanded;
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
    local current_identity = character_identity();
    for _, area_key in ipairs((accessxi.quests_menu_data or {}).quest_log_order or T{}) do
        local entry = type(accessxi.quest_packet_entry) == 'function'
            and accessxi.quest_packet_entry(area_key, 'current') or nil;
        local completed_entry = type(accessxi.quest_packet_entry) == 'function'
            and accessxi.quest_packet_entry(area_key, 'completed') or nil;
        local completed_source = clean(type(completed_entry) == 'table'
            and completed_entry.source or '');
        local completed_entry_ready = type(completed_entry) == 'table'
            and (completed_source == 'packet_in_056' or completed_source == 'cache')
            and clean(completed_entry.identity):lower() == current_identity;
        local rows = type(accessxi.quest_rom_rows_for_area) == 'function'
            and accessxi.quest_rom_rows_for_area(area_key) or nil;
        local resource = ((accessxi.quests_menu_data or {}).quest_log_resources or {})[area_key] or {};
        local max_id = clean(area_key) == 'aht_urhgan' and 127 or 255;
        if (type(entry) == 'table' and type(rows) == 'table') then
            for quest_id = 0, max_id do
                if (type(accessxi.quest_packet_has_id) == 'function'
                    and accessxi.quest_packet_has_id(entry, quest_id)
                    and not (completed_entry_ready
                        and accessxi.quest_packet_has_id(completed_entry, quest_id))) then
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
                            objective_character_identity = character_identity(),
                            objective_world_id = player_world_id(),
                            objective_session_epoch = objective_session_epoch(),
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
    prune_objective_progress('quest', items);
    return expand_active_quest_destinations(items);
end

local function stable_word_signature(words)
    local values = {};
    for _, value in ipairs(type(words) == 'table' and words or T{}) do
        values[#values + 1] = tostring(tonumber(value) or 0);
    end
    return table.concat(values, ',');
end

local function mission_packet_content_signature()
    local packet = accessxi.mission_packet_main or {};
    local ahturghan = accessxi.mission_packet_ahturghan or {};
    return table.concat({
        clean(accessxi.mission_packet_source),
        clean(accessxi.mission_packet_player),
        clean(accessxi.mission_packet_identity):lower(),
        tostring(tonumber(accessxi.mission_packet_session_epoch) or 0),
        clean(accessxi.mission_packet_hex),
        clean(packet.port), clean(packet.nation), clean(packet.nation_mission),
        clean(packet.zilart), clean(packet.cop), clean(packet.cop_status),
        clean(packet.addons), clean(packet.tales), clean(packet.soa), clean(packet.rov),
        clean(accessxi.mission_packet_ahturghan_source),
        clean(accessxi.mission_packet_ahturghan_identity):lower(),
        clean(ahturghan.assault), clean(ahturghan.toau), clean(ahturghan.wotg),
        clean(ahturghan.campaign),
        clean(accessxi.mission_packet_ahturghan_complete_source),
        clean(accessxi.mission_packet_ahturghan_complete_identity):lower(),
        stable_word_signature(accessxi.mission_packet_ahturghan_complete),
        clean(accessxi.mission_packet_nations_complete_source),
        clean(accessxi.mission_packet_nations_complete_identity):lower(),
        stable_word_signature(accessxi.mission_packet_nations_complete),
    }, '\t');
end

local function quest_packet_content_signature()
    local values = {
        clean(accessxi.quest_packet_source),
        clean(accessxi.quest_packet_player),
        clean(accessxi.quest_packet_identity):lower(),
        tostring(tonumber(accessxi.quest_packet_session_epoch) or 0),
        clean(accessxi.quest_packet_key),
    };
    local logs = accessxi.quest_packet_logs or {};
    for _, area_key in ipairs((accessxi.quests_menu_data or {}).quest_log_order or T{}) do
        for _, mode in ipairs(T{ 'current', 'completed' }) do
            local entry = logs[clean(area_key) .. ':' .. mode] or {};
            values[#values + 1] = table.concat({
                clean(area_key), mode, clean(entry.source), clean(entry.identity):lower(),
                tostring(tonumber(entry.session_epoch) or 0), tostring(tonumber(entry.port) or 0),
                stable_word_signature(entry.words),
            }, ',');
        end
    end
    return table.concat(values, '\t');
end

local function mission_rank_state_signature()
    if (type(accessxi.current_nation_mission_rank_state) ~= 'function') then return ''; end
    local ok, state = pcall(accessxi.current_nation_mission_rank_state);
    if (not ok or type(state) ~= 'table') then return ''; end
    return table.concat({
        tostring(tonumber(state.nation) or -1),
        tostring(tonumber(state.rank) or 0),
        tostring(tonumber(state.rank_points) or 0),
        clean(state.identity):lower(),
    }, ',');
end

local function key_item_freshness_signature()
    local values = {
        clean(accessxi.key_items_packet_source),
        clean(accessxi.key_items_packet_player),
        clean(accessxi.key_items_packet_identity):lower(),
        tostring(tonumber(accessxi.key_items_packet_session_epoch) or 0),
    };
    local indices = {};
    for table_index in pairs(accessxi.key_items_packet_tables or {}) do
        indices[#indices + 1] = tonumber(table_index) or -1;
    end
    table.sort(indices);
    for _, table_index in ipairs(indices) do
        local entry = (accessxi.key_items_packet_tables or {})[table_index] or {};
        values[#values + 1] = table.concat({
            tostring(table_index), clean(entry.source), clean(entry.identity):lower(),
            tostring(tonumber(entry.session_epoch) or 0),
        }, ',');
    end
    return table.concat(values, '|');
end

local function active_state_signature(category_key)
    category_key = clean(category_key):lower();
    local values = {
        category_key,
        player_name():lower(),
        character_identity(),
        tostring(player_world_id()),
        tostring(objective_session_epoch()),
        clean(accessxi.key_items_packet_key),
        key_item_freshness_signature(),
        clean(accessxi.inventory_packet_key),
        tostring(tonumber(accessxi.objective_progress_revision) or 0),
        current_nav_catalog_revision(),
    };
    if (category_key == 'mission') then
        values[#values + 1] = mission_packet_content_signature();
        values[#values + 1] = mission_rank_state_signature();
        values[#values + 1] = tostring(tonumber(type(accessxi.nav_current_position) == 'table'
            and accessxi.nav_current_position.zone or nil) or 0);
    elseif (category_key == 'quest') then
        values[#values + 1] = quest_packet_content_signature();
    end
    return table.concat(values, '\t');
end

local function active_owner_key(point)
    point = type(point) == 'table' and point or {};
    local target = type(point.objective_target) == 'table' and point.objective_target or point;
    return table.concat({
        clean(point.objective_kind or point.kind):lower(),
        clean(point.objective_native_key),
        clean(point.objective_guide_step_id or point.guide_step_id),
        clean(point.objective_candidate_id),
        clean(point.objective_action_id),
        clean(point.objective_group_id),
        clean(point.objective_destination_id),
        tostring(tonumber(target.zone) or 0),
        tostring(tonumber(target.x) or 0),
        tostring(tonumber(target.z) or 0),
        tostring(tonumber(target.y) or 0),
        clean(target.destination_id),
    }, '\t');
end

local function stamp_active_items(category_key, items)
    local state_signature = active_state_signature(category_key);
    for _, item in ipairs(items or T{}) do
        item.objective_active_state_signature = state_signature;
        item.objective_active_owner_key = active_owner_key(item);
    end
    return items;
end

function accessxi.nav_mission_quest_active_items(category_key)
    category_key = clean(category_key):lower();
    if (category_key ~= 'mission' and category_key ~= 'quest') then return T{}; end
    if (type(accessxi.refresh_objective_inventory_state) == 'function') then
        pcall(accessxi.refresh_objective_inventory_state, category_key .. '-category');
    end

    local owner = table.concat({
        character_identity(), tostring(player_world_id()), tostring(objective_session_epoch()),
    }, '\t');
    if (active_row_cache_owner ~= owner) then
        active_row_cache = {};
        active_row_cache_owner = owner;
    end
    local signature = active_state_signature(category_key);
    local cached = active_row_cache[category_key];
    if (type(cached) == 'table' and cached.signature == signature) then
        return cached.rows;
    end

    ensure_catalog_index();
    active_build_guide_failed = false;
    local rows = category_key == 'mission' and active_missions() or active_quests();
    owner = table.concat({
        character_identity(), tostring(player_world_id()), tostring(objective_session_epoch()),
    }, '\t');
    if (active_row_cache_owner ~= owner) then
        active_row_cache = {};
        active_row_cache_owner = owner;
    end
    signature = active_state_signature(category_key);
    rows = stamp_active_items(category_key, rows);
    if (active_build_guide_failed) then
        active_row_cache[category_key] = nil;
    else
        active_row_cache[category_key] = { signature = signature, rows = rows };
    end
    return rows;
end

function accessxi.nav_mission_quest_item_speech(item, index, total)
    if (type(item) ~= 'table') then
        return '';
    end
    local title = clean(item.name);
    local kind = clean(item.objective_kind or item.kind):lower();
    local location = kind == 'quest' and clean(item.quest_area) or clean(item.mission_context);
    local status = kind == 'quest' and 'Active quest.'
        or (clean(item.mission_availability) == 'available-to-start' and 'Available mission.' or 'Active mission.');
    if (item.objective_instruction_only == true) then
        local speech = ('%s. %s'):fmt(title ~= '' and title or 'Objective', status);
        if (location ~= '') then
            speech = speech .. ' ' .. location .. '.';
        end
        speech = speech .. ' Current instruction: ' .. clean(item.objective_instruction);
        local native_details = meaningful_native_details(item.objective_native_details);
        if (native_details ~= '') then
            speech = speech .. (kind == 'quest' and ' Native quest details: ' or ' Native mission orders: ')
                .. native_details;
        end
        return speech .. ' Press I to repeat instructions.'
            .. (' %d of %d.'):fmt(tonumber(index) or 1, tonumber(total) or 1);
    end
    if (clean(item.objective_candidate_id) ~= '') then
        local speech = ('%s. %s'):fmt(title ~= '' and title or 'Objective', status);
        if (location ~= '') then
            speech = speech .. ' ' .. location .. '.';
        end
        speech = speech .. ' Objective choice: ' .. clean(item.objective_instruction);
        local destination_location = clean(item.objective_destination_zone_name);
        local destination_label = clean(item.objective_destination_label);
        if (destination_location ~= '' or destination_label ~= '') then
            speech = speech .. ' Destination: ' .. clean(destination_location .. ' ' .. destination_label) .. '.';
        end
        local native_details = meaningful_native_details(item.objective_native_details);
        if (native_details ~= '') then
            speech = speech .. (kind == 'quest' and ' Native quest details: ' or ' Native mission orders: ')
                .. native_details;
        end
        speech = speech .. ' Press I to start navigation.';
        return speech .. (' %d of %d.'):fmt(tonumber(index) or 1, tonumber(total) or 1);
    end
    local prefix = ('%s. %d of %d. %s'):fmt(title ~= '' and title or 'Objective', tonumber(index) or 1, tonumber(total) or 1, status);
    if (location ~= '') then
        prefix = prefix .. ' ' .. location .. '.';
    end
    if (item.objective_available == true and clean(item.objective_instruction) ~= '') then
        local objective_label = clean(item.mission_availability) == 'available-to-start'
            and ' Start destination: ' or ' Current objective: ';
        prefix = prefix .. objective_label .. clean(item.objective_instruction);
    else
        prefix = prefix .. ' No exact source-backed destination is available.';
    end
    local native_details = meaningful_native_details(item.objective_native_details);
    if (native_details ~= '') then
        local detail_label = kind == 'quest' and ' Native quest details: ' or ' Native mission orders: ';
        prefix = prefix .. detail_label .. native_details;
    end
    return prefix .. ' Press G for the source guide.';
end

local function same_item(a, b)
    local kind = clean(a ~= nil and (a.objective_kind or a.kind) or ''):lower();
    if (kind ~= clean(b ~= nil and (b.objective_kind or b.kind) or ''):lower()) then
        return false;
    end
    if (clean(a ~= nil and a.objective_character_identity or ''):lower()
        ~= clean(b ~= nil and b.objective_character_identity or ''):lower()) then
        return false;
    end
    if (tonumber(a ~= nil and a.objective_world_id or nil)
        ~= tonumber(b ~= nil and b.objective_world_id or nil)
        or tonumber(a ~= nil and a.objective_session_epoch or nil)
            ~= tonumber(b ~= nil and b.objective_session_epoch or nil)
        or clean(a ~= nil and a.objective_native_key or '')
            ~= clean(b ~= nil and b.objective_native_key or '')) then
        return false;
    end
    local exact_fields = {
        'objective_guide_step_id', 'objective_action_id', 'objective_candidate_id',
        'objective_group_id', 'objective_destination_id',
    };
    local typed = a.objective_instruction_only == true or b.objective_instruction_only == true;
    for _, field in ipairs(exact_fields) do
        if (clean(a ~= nil and a[field] or '') ~= clean(b ~= nil and b[field] or '')) then
            return false;
        end
        typed = typed or clean(a ~= nil and a[field] or '') ~= ''
            or clean(b ~= nil and b[field] or '') ~= '';
    end
    if (typed) then
        return (a.objective_instruction_only == true) == (b.objective_instruction_only == true)
            and clean(a.objective_status) == clean(b.objective_status)
            and clean(a.objective_classification) == clean(b.objective_classification)
            and clean(a.objective_action_instruction) == clean(b.objective_action_instruction);
    end
    if (kind == 'mission') then
        local a_destination = clean(a.objective_destination_id);
        local b_destination = clean(b.objective_destination_id);
        if (a_destination ~= '' or b_destination ~= '') then
            return a_destination ~= '' and a_destination == b_destination
                and clean(a.mission_context) == clean(b.mission_context)
                and tonumber(a.mission_id) == tonumber(b.mission_id)
                and clean(a.mission_availability or 'active') == clean(b.mission_availability or 'active');
        end
        return clean(a.mission_context) == clean(b.mission_context)
            and tonumber(a.mission_id) == tonumber(b.mission_id)
            and clean(a.mission_availability or 'active') == clean(b.mission_availability or 'active');
    elseif (kind == 'quest') then
        return clean(a.quest_area_key) == clean(b.quest_area_key)
            and tonumber(a.quest_id) == tonumber(b.quest_id);
    end
    return false;
end

local function exact_array(left, right)
    left = type(left) == 'table' and left or {};
    right = type(right) == 'table' and right or {};
    if (#left ~= #right) then
        return false;
    end
    for index = 1, #left do
        if (tonumber(left[index]) ~= tonumber(right[index])) then
            return false;
        end
    end
    return true;
end

local function exact_ready_payload(payload, fresh)
    if (type(payload) ~= 'table' or type(fresh.objective_target) ~= 'table'
        or clean(fresh.objective_candidate_id) == ''
        or clean(payload.objective_route_contract_id) == ''
        or type(payload.objective_contract_snapshot) ~= 'table'
        or clean(payload.objective_contract_snapshot.contract_id)
            ~= clean(payload.objective_route_contract_id)
        or payload.objective_contract_snapshot.route_ready ~= true) then
        return false;
    end
    for _, field in ipairs({
        'objective_kind', 'objective_native_key', 'objective_guide_step_id',
        'objective_candidate_id', 'objective_action_id', 'objective_group_id',
        'objective_destination_id', 'objective_character_identity',
        'objective_classification', 'objective_action_instruction',
    }) do
        if (clean(payload[field]) ~= clean(fresh[field])) then
            return false;
        end
    end
    if (tonumber(payload.objective_world_id) ~= tonumber(fresh.objective_world_id)
        or tonumber(payload.objective_session_epoch) ~= tonumber(fresh.objective_session_epoch)) then
        return false;
    end
    local contract = payload.objective_contract_snapshot;
    if (clean(contract.candidate_id) ~= clean(fresh.objective_candidate_id)
        or clean(contract.action_id) ~= clean(fresh.objective_action_id)
        or clean(contract.group_id) ~= clean(fresh.objective_group_id)
        or clean(contract.destination_id) ~= clean(fresh.objective_destination_id)) then
        return false;
    end
    local expected = fresh.objective_target;
    if (tonumber(payload.zone) ~= tonumber(expected.zone)
        or clean(payload.name) ~= clean(expected.name)
        or tonumber(payload.x) ~= tonumber(expected.x)
        or tonumber(payload.z) ~= tonumber(expected.z)
        or tonumber(payload.y) ~= tonumber(expected.y)
        or clean(payload.kind) ~= clean(expected.kind)
        or clean(payload.destination_id) ~= clean(expected.destination_id)
        or clean(payload.raw_identity) ~= clean(expected.raw_identity)
        or clean(payload.cluster_policy_version) ~= clean(expected.cluster_policy_version)
        or not exact_array(payload.raw_spawn_ids, expected.raw_spawn_ids)) then
        return false;
    end
    return true;
end

local function source_route_payload(fresh)
    if (type(fresh) ~= 'table' or fresh.objective_instruction_only ~= false
        or clean(fresh.objective_classification) ~= 'catalogue-candidate'
        or clean(fresh.objective_kind) == ''
        or clean(fresh.objective_native_key) == ''
        or clean(fresh.objective_guide_step_id) == ''
        or clean(fresh.objective_candidate_id) == ''
        or clean(fresh.objective_action_id) == ''
        or type(fresh.objective_group_id) ~= 'string'
        or clean(fresh.objective_destination_id) == ''
        or clean(fresh.objective_character_identity) == ''
        or tonumber(fresh.objective_world_id) == nil
        or tonumber(fresh.objective_session_epoch) == nil
        or clean(fresh.objective_action_instruction) == '') then
        return nil;
    end
    local source = fresh.objective_target;
    local x = type(source) == 'table' and tonumber(source.x) or nil;
    local z = type(source) == 'table' and tonumber(source.z) or nil;
    local y = type(source) == 'table' and tonumber(source.y) or nil;
    if (type(source) ~= 'table' or (tonumber(source.zone) or 0) <= 0
        or clean(source.name) == ''
        or x == nil or z == nil or y == nil
        or x ~= x or z ~= z or y ~= y
        or x == math.huge or x == -math.huge
        or z == math.huge or z == -math.huge
        or y == math.huge or y == -math.huge
        or clean(source.destination_id) ~= clean(fresh.objective_destination_id)) then
        return nil;
    end
    local payload = point_copy(source);
    payload.objective_kind = clean(fresh.objective_kind);
    payload.objective_native_key = clean(fresh.objective_native_key);
    payload.objective_guide_step_id = clean(fresh.objective_guide_step_id);
    payload.guide_step_id = payload.objective_guide_step_id;
    payload.objective_candidate_id = clean(fresh.objective_candidate_id);
    payload.objective_action_id = clean(fresh.objective_action_id);
    payload.objective_group_id = fresh.objective_group_id;
    payload.objective_destination_id = clean(fresh.objective_destination_id);
    payload.objective_character_identity = clean(fresh.objective_character_identity);
    payload.objective_world_id = tonumber(fresh.objective_world_id);
    payload.objective_session_epoch = tonumber(fresh.objective_session_epoch);
    payload.objective_classification = 'catalogue-candidate';
    payload.objective_action_instruction = clean(fresh.objective_action_instruction);
    payload.objective_instruction = payload.objective_action_instruction;
    payload.arrival_instruction = payload.objective_action_instruction;
    payload.objective_route_recommendation = clean(fresh.objective_route_recommendation);
    payload.objective_instruction_only = false;
    payload.objective_route_contract_id = nil;
    payload.objective_contract_snapshot = nil;
    payload.objective_test_route = true;
    payload.objective_active_state_signature = clean(fresh.objective_active_state_signature);
    payload.objective_active_owner_key = clean(fresh.objective_active_owner_key);
    payload.verified = false;
    payload.route_context_label = payload.objective_kind == 'quest'
        and 'Source-verified quest objective' or 'Source-verified mission objective';
    return payload;
end

function accessxi.nav_mission_quest_prepare_route(item, player)
    local kind = clean(item ~= nil and (item.objective_kind or item.kind) or ''):lower();
    if (kind ~= 'mission' and kind ~= 'quest') then
        return nil, '', 'not-objective';
    end

    local title = clean(item ~= nil and item.name or 'objective');
    local selected_identity = clean(item ~= nil and item.objective_character_identity or ''):lower();
    local current_identity = character_identity();
    if (selected_identity == '' or current_identity == '' or selected_identity ~= current_identity) then
        return nil, ('%s belongs to another character. Move or repeat the item to refresh the list.'):fmt(title), 'blocked';
    end
    if (tonumber(item.objective_world_id) ~= player_world_id()
        or tonumber(item.objective_session_epoch) ~= objective_session_epoch()) then
        return nil, ('%s belongs to stale world or session state. Refresh the list.'):fmt(title), 'blocked';
    end

    local fresh = nil;
    for _, candidate in ipairs(accessxi.nav_mission_quest_active_items(kind)) do
        if (same_item(item, candidate)) then
            fresh = candidate;
            break;
        end
    end
    if (fresh == nil) then
        return nil, ('%s is no longer present in the current character\'s active %s list.'):fmt(title, kind == 'quest' and 'quest' or 'mission'), 'blocked';
    end
    local test_payload = source_route_payload(fresh);
    local route_state_ready = false;
    if (kind == 'mission') then
        route_state_ready = mission_route_state_ready(fresh);
    else
        route_state_ready = quest_route_state_ready(fresh);
    end
    if (not route_state_ready) then
        if (fresh.objective_instruction_only == true
            and clean(fresh.objective_action_instruction) ~= '') then
            return clean(fresh.objective_action_instruction), '', 'instruction';
        end
        if (test_payload ~= nil) then
            return test_payload, '', 'test-ready';
        end
        return nil, ('No exact source-backed destination is available for %s. Press G for the source guide.'):fmt(title), 'blocked';
    end
    if (fresh.objective_instruction_only ~= true and not objective_auxiliary_state_ready()) then
        if (test_payload ~= nil) then
            return test_payload, '', 'test-ready';
        end
        return nil, ('No exact source-backed destination is available for %s. Press G for the source guide.'):fmt(title), 'blocked';
    end
    local runtime = accessxi.objective_route_runtime;
    if (type(runtime) ~= 'table' or type(runtime.authorize_start) ~= 'function') then
        if (fresh.objective_instruction_only == true
            and clean(fresh.objective_action_instruction) ~= '') then
            return clean(fresh.objective_action_instruction), '', 'instruction';
        end
        if (test_payload ~= nil) then return test_payload, '', 'test-ready'; end
        return nil, 'Objective route verification is unavailable.', 'blocked';
    end
    local ok, payload, message, mode = pcall(runtime.authorize_start, runtime, item, fresh, player);
    if (not ok) then
        if (fresh.objective_instruction_only == true
            and clean(fresh.objective_action_instruction) ~= '') then
            return clean(fresh.objective_action_instruction), '', 'instruction';
        end
        if (test_payload ~= nil) then return test_payload, '', 'test-ready'; end
        return nil, 'Objective route verification failed safely.', 'blocked';
    end
    mode = clean(mode):lower();
    message = clean(message);
    if (mode == 'blocked') then
        if (fresh.objective_instruction_only == true
            and clean(fresh.objective_action_instruction) ~= '') then
            return clean(fresh.objective_action_instruction), '', 'instruction';
        end
        if (test_payload ~= nil) then return test_payload, '', 'test-ready'; end
        return nil, message ~= '' and message or 'No rooted route contract is available for this objective.', 'blocked';
    elseif (mode == 'instruction') then
        if (fresh.objective_instruction_only ~= true or type(payload) ~= 'string'
            or clean(payload) == '' or clean(payload) ~= clean(fresh.objective_action_instruction)) then
            return nil, 'Objective route verification returned an invalid instruction.', 'blocked';
        end
        return clean(payload), message, 'instruction';
    elseif (mode == 'ready') then
        if (fresh.objective_instruction_only == true or not exact_ready_payload(payload, fresh)) then
            return nil, 'Objective route verification returned an invalid destination.', 'blocked';
        end
        local ready_payload = point_copy(payload);
        ready_payload.objective_route_recommendation = clean(fresh.objective_route_recommendation);
        return ready_payload, message, 'ready';
    end
    if (test_payload ~= nil) then return test_payload, '', 'test-ready'; end
    return nil, 'Objective route verification returned an unsupported result.', 'blocked';
end

function accessxi.nav_mission_quest_guide_route_descriptor(native_key, guide_step_id, step)
    -- Legacy guide route_ready/navigation_target fields are display-only.
    -- Rooted objective contracts are the sole movement authority.
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
    return nil, accessxi.objective_guides:repeat_step(), 'blocked';
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
    local recommendation = clean(point ~= nil and point.objective_route_recommendation or '');
    local suffix = instruction ~= '' and (' Objective: ' .. instruction) or '';
    if (recommendation ~= '') then
        suffix = suffix .. ' ' .. recommendation;
    end
    return suffix;
end

function accessxi.nav_mission_quest_arrival_suffix(point)
    local instruction = clean(point ~= nil and point.arrival_instruction or '');
    return instruction ~= '' and (' ' .. instruction) or '';
end

function accessxi.nav_mission_quest_route_context(point)
    return clean(point ~= nil and point.route_context_label or '');
end

local function route_point_owner_mismatch(point, current_identity, current_world, current_epoch)
    local kind = clean(type(point) == 'table' and (point.objective_kind or point.kind) or ''):lower();
    if (kind ~= 'mission' and kind ~= 'quest') then
        return false;
    end
    local owner = clean(point.objective_character_identity):lower();
    local basic_mismatch = owner == '' or owner ~= current_identity
        or tonumber(point.objective_world_id) ~= current_world
        or tonumber(point.objective_session_epoch) ~= current_epoch
        or clean(point.objective_native_key) == ''
        or clean(point.objective_guide_step_id or point.guide_step_id) == ''
        or clean(point.objective_candidate_id) == ''
        or clean(point.objective_action_id) == ''
        or type(point.objective_group_id) ~= 'string'
        or clean(point.objective_destination_id) == '';
    if (basic_mismatch) then
        return true;
    end
    if (point.objective_test_route == true) then
        if (clean(point.objective_route_contract_id) ~= ''
            or point.objective_contract_snapshot ~= nil
            or clean(point.objective_classification) ~= 'catalogue-candidate') then
            return true;
        end
        local saved_owner_key = clean(point.objective_active_owner_key);
        if (saved_owner_key == '' or saved_owner_key ~= clean(active_owner_key(point))) then
            return true;
        end
        local saved_state_signature = clean(point.objective_active_state_signature);
        if (saved_state_signature ~= ''
            and saved_state_signature == clean(active_state_signature(kind))) then
            return false;
        end
        for _, fresh in ipairs(accessxi.nav_mission_quest_active_items(kind)) do
            local target = type(fresh) == 'table' and fresh.objective_target or nil;
            if (fresh.objective_instruction_only == false
                and clean(fresh.objective_classification) == 'catalogue-candidate'
                and clean(fresh.objective_native_key) == clean(point.objective_native_key)
                and clean(fresh.objective_guide_step_id) == clean(point.objective_guide_step_id)
                and clean(fresh.objective_candidate_id) == clean(point.objective_candidate_id)
                and clean(fresh.objective_action_id) == clean(point.objective_action_id)
                and clean(fresh.objective_group_id) == clean(point.objective_group_id)
                and clean(fresh.objective_destination_id) == clean(point.objective_destination_id)
                and clean(fresh.objective_character_identity):lower() == owner
                and tonumber(fresh.objective_world_id) == current_world
                and tonumber(fresh.objective_session_epoch) == current_epoch
                and type(target) == 'table'
                and tonumber(target.zone) == tonumber(point.zone)
                and tonumber(target.x) == tonumber(point.x)
                and tonumber(target.z) == tonumber(point.z)
                and tonumber(target.y) == tonumber(point.y)
                and clean(target.destination_id) == clean(point.objective_destination_id)) then
                point.objective_active_state_signature = clean(fresh.objective_active_state_signature);
                point.objective_active_owner_key = clean(fresh.objective_active_owner_key);
                return false;
            end
        end
        return true;
    end
    local contract = point.objective_contract_snapshot;
    return clean(point.objective_route_contract_id) == ''
        or type(contract) ~= 'table'
        or contract.route_ready ~= true
        or clean(contract.contract_id) ~= clean(point.objective_route_contract_id)
        or clean(contract.candidate_id) ~= clean(point.objective_candidate_id)
        or clean(contract.action_id) ~= clean(point.objective_action_id)
        or clean(contract.group_id) ~= clean(point.objective_group_id)
        or clean(contract.destination_id) ~= clean(point.objective_destination_id);
end

function accessxi.nav_mission_quest_route_point_is_current(point)
    local kind = clean(type(point) == 'table' and (point.objective_kind or point.kind) or ''):lower();
    if (kind ~= 'mission' and kind ~= 'quest') then
        return true;
    end

    local current_identity = character_identity();
    local current_world = player_world_id();
    local current_epoch = objective_session_epoch();
    if (current_identity == ''
        or clean(point.objective_character_identity):lower() ~= current_identity
        or tonumber(point.objective_world_id) ~= current_world
        or tonumber(point.objective_session_epoch) ~= current_epoch) then
        return false;
    end

    local saved_state_signature = clean(point.objective_active_state_signature);
    if (saved_state_signature ~= '' and saved_state_signature == active_state_signature(kind)) then
        return true;
    end

    local saved_owner_key = clean(point.objective_active_owner_key);
    if (saved_owner_key == '') then
        saved_owner_key = active_owner_key(point);
    end
    local items = accessxi.nav_mission_quest_active_items(kind);
    for _, fresh in ipairs(items) do
        if (clean(fresh.objective_active_owner_key) == saved_owner_key) then
            point.objective_active_state_signature = clean(fresh.objective_active_state_signature);
            point.objective_active_owner_key = clean(fresh.objective_active_owner_key);
            return true;
        end
    end
    return false;
end

function accessxi.nav_mission_quest_route_owner_mismatch()
    local current_identity = character_identity();
    local current_world = player_world_id();
    local current_epoch = objective_session_epoch();
    return route_point_owner_mismatch(accessxi.nav_destination, current_identity, current_world, current_epoch)
        or route_point_owner_mismatch(accessxi.nav_zone_search_target, current_identity, current_world, current_epoch);
end

return true;

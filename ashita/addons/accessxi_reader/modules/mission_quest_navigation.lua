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
        objective_instruction = clean(point.objective_action_instruction or point.objective_instruction),
        objective_action_instruction = clean(point.objective_action_instruction or point.objective_instruction),
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

    if (clean(type(item) == 'table' and item.mission_availability or '') == 'available-to-start') then
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
        or clean(accessxi.inventory_packet_source) ~= 'packet_in_inventory'
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
    if (wanted_zone <= 0 or wanted_name == '') then
        return nil;
    end
    local match = nil;
    local match_count = 0;
    for _, point in ipairs(accessxi.nav_points or T{}) do
        if ((tonumber(point.zone) or 0) == wanted_zone
            and clean(point.name):lower() == wanted_name
            and (wanted_kind == '' or effective_kind(point) == wanted_kind)) then
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
        label = clean(row.label),
        items = deep_copy(row.items),
        enemies = deep_copy(row.enemies),
        transport_id = clean(row.transport_id),
    };
end

local function expanded_objective_row(item, row)
    local reviewed = exact_objective_guide_row(row);
    local identity = character_identity();
    local world_id = player_world_id();
    local session_epoch = objective_session_epoch();
    if (reviewed == nil or identity == '' or world_id <= 0 or session_epoch <= 0) then
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
    result.objective_action_id = reviewed.action_id;
    result.objective_candidate_id = reviewed.candidate_id or '';
    result.objective_group_id = reviewed.group_id or '';
    result.objective_destination_id = reviewed.destination_id or '';
    result.objective_route_contract_id = nil;
    result.objective_character_identity = identity;
    result.objective_world_id = world_id;
    result.objective_session_epoch = session_epoch;
    result.objective_action = reviewed.action;
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

local function expand_active_mission_destinations(items)
    local expanded = T{};
    for _, item in ipairs(items or T{}) do
        local replacements = T{};
        if (clean(item.mission_availability) == 'active'
            and type(accessxi.objective_guides) == 'table'
            and type(accessxi.objective_guides.objective_destinations) == 'function') then
            local ok, destinations = pcall(
                accessxi.objective_guides.objective_destinations,
                accessxi.objective_guides,
                clean(item.objective_native_key));
            if (ok and type(destinations) == 'table') then
                local expected_step = '';
                local stage_filter_ready = clean(item.objective_stage) == '';
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
        if (#replacements > 0) then
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
        if (type(accessxi.objective_guides) == 'table'
            and type(accessxi.objective_guides.objective_destinations) == 'function') then
            local ok, destinations = pcall(
                accessxi.objective_guides.objective_destinations,
                accessxi.objective_guides,
                clean(item.objective_native_key));
            if (ok and type(destinations) == 'table') then
                local expected_step = '';
                local stage_filter_ready = clean(item.objective_stage) == '';
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
        if (#replacements > 0) then
            table.sort(replacements, objective_row_less);
            for _, replacement in ipairs(replacements) do expanded:append(replacement); end
        else
            expanded:append(item);
        end
    end
    return expanded;
end

local nation_gate_guards = {
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
    return expand_active_quest_destinations(items);
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
        speech = speech .. ' Press I to check navigation.';
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
        prefix = prefix .. ' No verified current destination is available.';
    end
    local native_details = meaningful_native_details(item.objective_native_details);
    if (native_details ~= '') then
        local detail_label = kind == 'quest' and ' Native quest details: ' or ' Native mission orders: ';
        prefix = prefix .. detail_label .. native_details;
    end
    return prefix .. ' No rooted objective route contract is available.';
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
    local route_state_ready = false;
    if (kind == 'mission') then
        route_state_ready = mission_route_state_ready(fresh);
    else
        route_state_ready = quest_route_state_ready(fresh);
    end
    if (not route_state_ready) then
        return nil, ('Current-session packet evidence is not yet available for %s.'):fmt(title), 'blocked';
    end
    if (fresh.objective_instruction_only ~= true and not objective_auxiliary_state_ready()) then
        return nil, ('Current-session key-item or inventory evidence is not yet available for %s.'):fmt(title), 'blocked';
    end
    local runtime = accessxi.objective_route_runtime;
    if (type(runtime) ~= 'table' or type(runtime.authorize_start) ~= 'function') then
        return nil, 'Objective route verification is unavailable.', 'blocked';
    end
    local ok, payload, message, mode = pcall(runtime.authorize_start, runtime, item, fresh, player);
    if (not ok) then
        return nil, 'Objective route verification failed safely.', 'blocked';
    end
    mode = clean(mode):lower();
    message = clean(message);
    if (mode == 'blocked') then
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
        return point_copy(payload), message, 'ready';
    end
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
    return instruction ~= '' and (' Objective: ' .. instruction) or '';
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
    local contract = point.objective_contract_snapshot;
    return owner == '' or owner ~= current_identity
        or tonumber(point.objective_world_id) ~= current_world
        or tonumber(point.objective_session_epoch) ~= current_epoch
        or clean(point.objective_native_key) == ''
        or clean(point.objective_guide_step_id or point.guide_step_id) == ''
        or clean(point.objective_candidate_id) == ''
        or clean(point.objective_action_id) == ''
        or clean(point.objective_destination_id) == ''
        or clean(point.objective_route_contract_id) == ''
        or type(contract) ~= 'table'
        or contract.route_ready ~= true
        or clean(contract.contract_id) ~= clean(point.objective_route_contract_id)
        or clean(contract.candidate_id) ~= clean(point.objective_candidate_id)
        or clean(contract.action_id) ~= clean(point.objective_action_id)
        or clean(contract.group_id) ~= clean(point.objective_group_id)
        or clean(contract.destination_id) ~= clean(point.objective_destination_id);
end

function accessxi.nav_mission_quest_route_owner_mismatch()
    local current_identity = character_identity();
    local current_world = player_world_id();
    local current_epoch = objective_session_epoch();
    return route_point_owner_mismatch(accessxi.nav_destination, current_identity, current_world, current_epoch)
        or route_point_owner_mismatch(accessxi.nav_zone_search_target, current_identity, current_world, current_epoch);
end

return true;

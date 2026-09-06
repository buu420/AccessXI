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
local objective_progress_history = {};
local objective_progress_legacy = {};
local objective_progress_marks = {};
local objective_progress_undone = {};
local pending_objective_interaction = nil;
local pending_objective_events = {};
local pending_objective_event_order = {};
local pending_objective_transport = nil;
local accepted_objective_causes = {};
local accepted_objective_cause_order = {};
local last_objective_battle_sequence = 0;
local objective_event_arm_limit = 64;
local objective_cause_limit = 2048;
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
local advance_objective_match;
local notify_objective_progress;
local objective_event_menus = {
    ['menu rem4line'] = true,
    ['menu rem4li2'] = true,
    ['menu spoolmsg'] = true,
    ['menu splmsg2'] = true,
};

local function objective_progress_key(identity, world_id, native_key)
    return table.concat({
        clean(identity):lower(),
        tostring(tonumber(world_id) or 0),
        clean(native_key),
    }, '\t');
end

local function increment_objective_progress_revision()
    accessxi.objective_progress_revision = (tonumber(accessxi.objective_progress_revision) or 0) + 1;
end

-- A ROW'S REVISION AND ITS STEP ID MUST AGREE ABOUT WHICH DATASET THEY CAME FROM.
--
-- The progress file is append-only and outlives any change to the guide data.
-- On 2026-08-25 a cursor saved against the collapsed wiki page migrated onto a
-- reviewed override that happened to use the same step-id namespace, and the
-- player was walked past Pius, Grohm and the Mythril Seam to the Refiner Lid.
-- Override ids are namespaced now and the migration refuses to cross an
-- override boundary, but the poisoned row is still sitting in the file --
-- revision "override:lsb:2_3_1_Journey_to_Bastok" against the scraped id
-- "mission:San d'Oria:7:step-004" -- and rows are never rewritten, so it will
-- sit there forever. Drop such rows on the way in rather than trusting every
-- downstream matcher to keep rejecting them.
--
-- The test is cheap and purely structural: an 'override:' revision must name an
-- id carrying ':reviewed:', and a scraped revision must not.
local function progress_row_crosses_datasets(native_key, revision, step_id)
    if (clean(native_key) == '' or clean(revision) == '' or clean(step_id) == '') then
        return false;
    end
    local revision_is_override = clean(revision):sub(1, 9) == 'override:';
    local step_is_override = clean(step_id):find(':reviewed:', 1, true) ~= nil;
    return revision_is_override ~= step_is_override;
end

local function load_objective_progress()
    if (objective_progress_loaded) then return; end
    objective_progress_loaded = true;
    local path = clean(accessxi.objective_interaction_progress_path);
    if (path == '') then return; end
    local file = io.open(path, 'r');
    if (file == nil) then return; end
    for line in file:lines() do
        local fields = {};
        local value = tostring(line or '') .. '\t';
        for field in value:gmatch('([^\t]*)\t') do
            fields[#fields + 1] = field;
        end
        if (#fields == 10 and fields[1] == 'v2'
            and not progress_row_crosses_datasets(clean(fields[4]), clean(fields[5]), clean(fields[6]))) then
            local identity = clean(fields[2]):lower();
            local world_id = tonumber(fields[3]) or 0;
            local native_key = clean(fields[4]);
            local key = objective_progress_key(identity, world_id, native_key);
            objective_progress_history[key] = objective_progress_history[key] or {};
            objective_progress_history[key][#objective_progress_history[key] + 1] = {
                version = 'v2',
                identity = identity,
                world_id = world_id,
                native_key = native_key,
                progression_revision = clean(fields[5]),
                step_id = clean(fields[6]),
                step_order = tonumber(fields[7]),
                action_id = clean(fields[8]),
                action_order = tonumber(fields[9]),
                progress_count = tonumber(fields[10]),
                raw_step_order = fields[7],
                raw_action_order = fields[9],
                raw_progress_count = fields[10],
            };
        elseif (#fields == 9 and fields[1] == 'v3-mark') then
            -- A cursor move the PLAYER made, with the state it moved from.
            objective_progress_marks[#objective_progress_marks + 1] = {
                identity = clean(fields[2]):lower(),
                world_id = tonumber(fields[3]) or 0,
                native_key = clean(fields[4]),
                event_id = clean(fields[5]),
                after_step_id = clean(fields[6]),
                after_action_id = clean(fields[7]),
                before_step_id = clean(fields[8]),
                before_action_id = clean(fields[9]),
            };
        elseif (#fields == 5 and fields[1] == 'v3-undo') then
            objective_progress_undone[clean(fields[5])] = true;
        elseif (#fields == 4) then
            local identity = clean(fields[1]):lower();
            local native_key = clean(fields[2]);
            local step_id = clean(fields[3]);
            local order = tonumber(fields[4]) or 0;
            if (identity ~= '' and native_key ~= '') then
                local key = identity .. '\t' .. native_key;
                if (step_id == '-' and fields[4] == '0') then
                    objective_progress_legacy[key] = {
                        identity = identity,
                        native_key = native_key,
                        tombstoned = true,
                    };
                elseif (step_id ~= '' and step_id ~= '-' and order > 0
                    and fields[4] == tostring(order)) then
                    objective_progress_legacy[key] = {
                        identity = identity,
                        native_key = native_key,
                        step_id = step_id,
                        order = order,
                        tombstoned = false,
                    };
                end
            end
        end
    end
    file:close();

    -- An undone mark's cursor row must not survive, or "farthest wins" keeps it
    -- forever. Applied after the whole file is read because an undo row is
    -- always appended AFTER the row it reverses.
    for _, mark in ipairs(objective_progress_marks) do
        if (objective_progress_undone[mark.event_id] == true) then
            local key = objective_progress_key(mark.identity, mark.world_id, mark.native_key);
            local before = #(objective_progress_history[key] or {});
            local kept = {};
            for _, candidate in ipairs(objective_progress_history[key] or {}) do
                if (clean(candidate.step_id) ~= mark.after_step_id
                    or clean(candidate.action_id) ~= mark.after_action_id) then
                    kept[#kept + 1] = candidate;
                end
            end
            objective_progress_history[key] = kept;
            -- A repair nobody can see is a repair nobody can confirm. The
            -- player could not tell whether their cursor had been put back,
            -- and neither could the log.
            if (type(log_line) == 'function' and #kept < before) then
                log_line(('objective cursor REVERSED native="%s" event="%s" dropped=%d back-to step="%s" action="%s"'):fmt(
                    clean(mark.native_key), clean(mark.event_id), before - #kept,
                    clean(mark.before_step_id), clean(mark.before_action_id)));
            end
        end
    end
end

local function append_objective_progress(record)
    local path = clean(accessxi.objective_interaction_progress_path);
    if (path == '') then return true; end
    local file = io.open(path, 'ab');
    if (file == nil) then
        if (type(log_line) == 'function') then
            log_line(('objective interaction progress write failed path="%s"'):fmt(path));
        end
        return false;
    end
    local encoded = table.concat({
        'v2',
        clean(record.identity):lower(),
        tostring(tonumber(record.world_id) or 0),
        clean(record.native_key),
        clean(record.progression_revision),
        clean(record.step_id),
        tostring(tonumber(record.step_order) or 0),
        clean(record.action_id),
        tostring(tonumber(record.action_order) or 0),
        tostring(tonumber(record.progress_count) or 0),
    }, '\t');
    file:write(encoded, '\n');
    file:close();
    return true;
end

-- Append one raw row to the progress file. The file is strictly append-only
-- (io.open 'ab'), which is what makes an undo durable: nothing is ever
-- rewritten, so a reversal is recorded rather than a record erased.
function accessxi.objective_progress_append_row(fields)
    local path = clean(accessxi.objective_interaction_progress_path);
    if (path == '' or type(fields) ~= 'table') then return false; end
    local file = io.open(path, 'ab');
    if (file == nil) then
        if (type(log_line) == 'function') then
            log_line(('objective interaction progress write failed path="%s"'):fmt(path));
        end
        return false;
    end
    file:write(table.concat(fields, '\t'), '\n');
    file:close();
    return true;
end

local function save_objective_progress(record)
    load_objective_progress();
    if (type(record) ~= 'table') then return false; end
    local identity = clean(record.identity):lower();
    local world_id = tonumber(record.world_id) or 0;
    local native_key = clean(record.native_key);
    local key = objective_progress_key(identity, world_id, native_key);
    local existing = objective_progress[key];
    if (identity == '' or world_id <= 0 or native_key == ''
        or clean(record.progression_revision) == ''
        or clean(record.step_id) == '' or (tonumber(record.step_order) or 0) < 1
        or clean(record.action_id) == '' or (tonumber(record.action_order) or 0) < 1
        or (tonumber(record.progress_count) or -1) < 0) then
        return false;
    end
    if (type(existing) == 'table'
        and clean(existing.progression_revision) == clean(record.progression_revision)
        and clean(existing.step_id) == clean(record.step_id)
        and tonumber(existing.step_order) == tonumber(record.step_order)
        and clean(existing.action_id) == clean(record.action_id)
        and tonumber(existing.action_order) == tonumber(record.action_order)
        and tonumber(existing.progress_count) == tonumber(record.progress_count)) then
        return true;
    end
    local saved = {
        version = 'v2', identity = identity, world_id = world_id,
        native_key = native_key,
        progression_revision = clean(record.progression_revision),
        step_id = clean(record.step_id), step_order = tonumber(record.step_order),
        action_id = clean(record.action_id), action_order = tonumber(record.action_order),
        progress_count = tonumber(record.progress_count) or 0,
    };
    if (not append_objective_progress(saved)) then
        return false;
    end
    objective_progress[key] = saved;
    objective_progress_history[key] = objective_progress_history[key] or {};
    objective_progress_history[key][#objective_progress_history[key] + 1] = deep_copy(saved);
    increment_objective_progress_revision();
    return true;
end

local function clear_objective_progress(identity, native_key)
    -- v2 history is append-only and has no deletion/tombstone grammar. Native
    -- completion is represented by the terminal action at required_count.
    return false;
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
        objective_via_zones = point.objective_via_zones,
        objective_candidate_id = clean(point.objective_candidate_id),
        objective_action_id = clean(point.objective_action_id),
        objective_cursor_action_id = clean(point.objective_cursor_action_id),
        objective_progression_revision = clean(point.objective_progression_revision),
        objective_group_id = clean(point.objective_group_id),
        objective_destination_id = clean(point.objective_destination_id),
        objective_route_contract_id = clean(point.objective_route_contract_id),
        objective_contract_snapshot = deep_copy(point.objective_contract_snapshot),
        objective_test_route = point.objective_test_route == true,
        objective_wiki_route = point.objective_wiki_route == true,
        wiki_authoritative = point.wiki_authoritative == true,
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
    pending_objective_events = {};
    pending_objective_event_order = {};
    pending_objective_transport = nil;
    accepted_objective_causes = {};
    accepted_objective_cause_order = {};
    last_objective_battle_sequence = 0;
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
        canonical_edge_id = tonumber(row.canonical_edge_id),
        canonical_from_zone = tonumber(row.canonical_from_zone),
        -- The road the guide named for this step. Dropping it here is what
        -- silently reverted every route to "any shortest chain": the resolver
        -- computed the right road and the target that actually got routed to
        -- had never heard of it (live 2026-08-22, `NO GUIDE ROAD given=nil`).
        via_zones = row.objective_via_zones,
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
    result.objective_via_zones = deep_copy(reviewed.via_zones);
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
            objective_canonical_edge_id = reviewed.canonical_edge_id,
            objective_canonical_from_zone = reviewed.canonical_from_zone,
            objective_via_zones = deep_copy(reviewed.via_zones),
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

-- THE GUIDE AND THE CATALOGUE SPELL THE SAME DOOR DIFFERENTLY.
--
-- Live 2026-08-24, The Davoi Report step-016. The guide names
-- "Door: Papal Chambers" and the catalogue row is "Door:Papal Chambers" --
-- one space after the colon. The keys were compared exactly, so the lookup
-- returned 0 rows instead of 3 and the step refused with "you are already in
-- Northern San d'Oria" while the door stood at (130.3, 122.3).
--
-- The catalogue is not even consistent with itself: of 155 names carrying a
-- colon, 21 use colon-space. Two names that differ ONLY by spacing around
-- punctuation are the same name written twice, so collapsing that is safe --
-- and because the catalogue INDEX is built through this same function, both
-- sides of every comparison normalise together.
local function source_name_key(value)
    local key = clean(value):lower();
    key = key:gsub('%s*([:,])%s*', '%1');
    key = key:gsub('%s+', ' ');
    return key;
end

local source_zone_names = {};
local objective_catalog_index = { revision = nil };

local function current_nav_catalog_revision()
    return tostring(tonumber(accessxi.nav_catalog_revision) or 0);
end

-- A HOLDING CHANGES WHERE YOU STILL HAVE TO GO.
--
-- The rollup decides which children a barren parent inherits, and it now skips
-- the ones whose item is already in the bag -- so "Collect the following 3
-- items" stops offering Jugner Forest the moment the Seedspall Lux from Jugner
-- Forest is picked up. That decision is baked into the cached step list, so
-- without this the list would keep naming a place the player has finished with
-- until the addon was reloaded. Clearing it on an inventory change costs one
-- rebuild and keeps the destination honest.
function accessxi.nav_mission_quest_forget_source_steps(reason)
    if (type(source_derivation_cache) ~= 'table') then
        return false;
    end
    local had = false;
    if (type(source_derivation_cache.source_steps) == 'table'
        and next(source_derivation_cache.source_steps) ~= nil) then
        had = true;
    end
    source_derivation_cache.source_steps = {};
    source_derivation_cache.source_routes = {};
    if (had and type(log_line) == 'function') then
        log_line(('objective source steps rebuilt reason="%s"'):fmt(tostring(reason or '')));
    end
    return had;
end

local function reset_source_derivation_cache_if_needed()
    local revision = current_nav_catalog_revision();
    if (source_derivation_cache.revision ~= revision) then
        source_derivation_cache.revision = revision;
        source_derivation_cache.source_steps = {};
        source_derivation_cache.source_routes = {};
        source_derivation_cache.source_route_refusals = {};
        source_derivation_cache.prerequisite_refusals = {};
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

-- Roles the guide names instead of people, with the members it named for them.
local objective_role_members = nil;
local function role_members_for(key)
    if (objective_role_members == nil) then
        objective_role_members = accessxi.load_module_table ~= nil
            and accessxi.load_module_table('objective_role_members', T{}) or T{};
    end
    return objective_role_members[clean(key):lower()];
end

local function point_for_destination_id(destination_id)
    destination_id = clean(destination_id);
    if (destination_id == '') then return nil; end
    for _, point in ipairs(accessxi.nav_points or T{}) do
        if (clean(point.destination_id) == destination_id) then
            return point_copy(point);
        end
    end
    return nil;
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
        points_by_entity = {},
        points_by_zone_base = {},
        points_by_base = {},
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
                index.points_by_entity[name_key] = index.points_by_entity[name_key] or T{};
                index.points_by_entity[name_key]:append(point);
                local base_key = name_key:match('^(.-)%s*#%d+$');
                if (base_key ~= nil and base_key ~= '') then
                    local base_entity_key = ('%d	%s'):fmt(zone, base_key);
                    index.points_by_zone_base[base_entity_key] = index.points_by_zone_base[base_entity_key] or T{};
                    index.points_by_zone_base[base_entity_key]:append(point);
                    -- ...and without a zone, so a step that says only "a Home
                    -- Point" has candidates to offer instead of being called
                    -- absent because every real one is numbered.
                    index.points_by_base[base_key] = index.points_by_base[base_key] or T{};
                    index.points_by_base[base_key]:append(point);
                end
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
    elseif (action == 'talk') then
        -- YOU TALK TO DOORS IN THIS GAME. The guide says "Talk to the Oaken
        -- Door at (K-8) in Norg to Gilgamesh's room", and FFXI catalogues doors
        -- as objects, so requiring npc filtered both Oaken Doors out and the
        -- step fell through to "you are already in Norg" -- live 2026-08-23,
        -- with the player standing in Norg and no route to the thing the guide
        -- named. 16 entity references across 1,195 talk/trade steps are
        -- catalogued only as objects: Oaken Door, Inconspicuous Door,
        -- ??? Warmachine.
        --
        -- TRADE is deliberately NOT widened: "trade to ???" would admit 1,267
        -- object rows, and a marker that matches everything names nothing.
        return kind == 'npc' or kind == 'object';
    elseif (action == 'trade') then
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

local function point_copy_with_identity(point)
    local copy = T{};
    for key, value in pairs(point) do
        copy[key] = value;
    end
    return copy;
end

-- A PARENT WITH NOTHING OF ITS OWN INHERITS ITS CHILDREN'S PLACES.
--
-- "Collect the following 3 items:" carries entities = {} and zones = {}, so it
-- refuses with "this step has no destination in the guide" -- while the three
-- rows beneath it name Jugner Forest, Pashhow Marshlands and Meriphataud
-- Mountains. Speaking those lines was only half the job: the player asked the
-- obvious next question, "when people try to make a path to these, are they
-- going to be able to", and the answer was no. The cursor sits on the parent,
-- the parent has no target, and pressing I does nothing.
--
-- The children are `note` steps, which the router will never walk to on their
-- own -- a note is read, not walked. So give the parent their places. It then
-- resolves like any other multi-target step: one destination becomes a route,
-- several become the choice the player already gets for a duplicated name,
-- which is exactly what a sighted player does with a three-item list.
--
-- Only barren parents inherit. A step that named its own target keeps it, so
-- this can never pull a route away from somewhere the guide was specific about.
function accessxi.objective_roll_up_child_targets(steps)
    if (type(steps) ~= 'table') then
        return 0;
    end
    local changed = 0;
    for index, step in ipairs(steps) do
        local own_entities = type(step.entities) == 'table' and #step.entities or 0;
        local own_zones = type(step.zones) == 'table' and #step.zones or 0;
        if (own_entities == 0 and own_zones == 0
            and clean(step.action):lower() ~= 'note'
            and clean(step.stable_step_id) ~= '') then
            -- INHERIT WHAT IS STILL TO BE DONE, NOT EVERY PLACE MENTIONED.
            --
            -- The first version took every child's entities, which put three
            -- kinds of noise into the destination list. Live 2026-08-27:
            --
            --   * the zone of an item the player was already carrying, so
            --     "Collect the following 3 items" offered Jugner Forest as the
            --     destination when the Seedspall Lux from Jugner Forest was in
            --     their bag;
            --   * "Closest Survival Guide is Davoi", a convenience note, which
            --     outranked the place the item actually drops;
            --   * "It's close to the Qufim Home Point" under At the Heavens'
            --     Door, which made a Home Point look like a second copy of the
            --     objective -- the player reported it as the mission being
            --     "listed twice".
            --
            -- A child that names an ITEM is where you go to get that item, and
            -- that is a destination. A child that names only a landmark is a
            -- hint about a destination someone else already gave. So when any
            -- child names an item, inherit from those children alone; when none
            -- does, fall back to inheriting everything, because then the hints
            -- are all there is.
            --
            -- And a child whose item is CONFIRMED held contributes nothing --
            -- there is nowhere left to go for it. Confirmed only: an item we
            -- could not check keeps its place in the list, because dropping a
            -- destination on a guess is how a player ends up stranded.
            local function child_item(child)
                if (type(accessxi.objective_inventory_named_state) ~= 'function') then
                    return nil, 'unknown';
                end
                for _, value in ipairs(type(child.entities) == 'table' and child.entities or {}) do
                    local name = clean(value);
                    if (name ~= '') then
                        local ok, _, item_id, state = pcall(
                            accessxi.objective_inventory_named_state, name);
                        if (ok and tonumber(item_id) ~= nil and (tonumber(item_id) or 0) > 0) then
                            return name, state;
                        end
                    end
                end
                return nil, 'unknown';
            end

            local children, any_item = {}, false;
            for next_index = index + 1, #steps do
                local child = steps[next_index];
                if (type(child) ~= 'table'
                    or clean(child.action):lower() ~= 'note') then
                    break;
                end
                local item_name, item_state = child_item(child);
                children[#children + 1] = {
                    step = child, item = item_name, state = item_state };
                if (item_name ~= nil) then any_item = true; end
            end

            local entities, zones, items, seen = {}, {}, {}, {};
            for _, entry in ipairs(children) do
                local child = entry.step;
                local usable = true;
                if (any_item and entry.item == nil) then
                    usable = false;          -- a hint beside real destinations
                elseif (entry.item ~= nil and entry.state == 'held') then
                    usable = false;          -- already in the bag
                end
                if (usable) then
                for _, value in ipairs(type(child.entities) == 'table' and child.entities or {}) do
                    local key = 'e:' .. tostring(value):lower();
                    if (clean(value) ~= '' and not seen[key]) then
                        seen[key] = true;
                        entities[#entities + 1] = value;
                    end
                end
                for _, value in ipairs(type(child.zones) == 'table' and child.zones or {}) do
                    local key = 'z:' .. tostring(value):lower();
                    if (clean(value) ~= '' and not seen[key]) then
                        seen[key] = true;
                        zones[#zones + 1] = value;
                    end
                end
                for _, value in ipairs(type(child.items) == 'table' and child.items or {}) do
                    local key = 'i:' .. tostring(value):lower();
                    if (clean(value) ~= '' and not seen[key]) then
                        seen[key] = true;
                        items[#items + 1] = value;
                    end
                end
                end
            end
            if (#entities > 0 or #zones > 0) then
                step.entities = entities;
                step.zones = zones;
                if (#items > 0 and (type(step.items) ~= 'table' or #step.items == 0)) then
                    step.items = items;
                end
                step.inherited_from_children = true;
                changed = changed + 1;
            end
        end
    end
    return changed;
end

-- DO NOT SEND SOMEONE SOMEWHERE THEY NO LONGER NEED TO GO.
--
-- "Collect the following 3 items" reads out where each one drops. Once the
-- player is carrying one, its directions are not information any more, they are
-- three zones and a grid reference of noise between them and the two they still
-- need. The player asked for exactly this: "I figured they would get removed
-- when they showed in my inventory."
--
-- The guide's rows are a tree we store flat, so a line naming one of the
-- required things OPENS that thing's group and every following line that names
-- none of them belongs to it -- which is how "Closest Survival Guide is Davoi"
-- leaves with the Seedspall Lux line it was written under, instead of being
-- left behind as an orphan pointing at a zone nobody is going to.
--
-- ONLY A CONFIRMED HOLDING REMOVES ANYTHING. An item we could not check stays
-- on screen with its directions intact: withholding a location because we were
-- unsure is the failure this addon exists to prevent, and it is much worse than
-- a line the player does not need.
function accessxi.objective_detail_lines_without_held(lines, progress)
    lines = type(lines) == 'table' and lines or {};
    -- This used to bail when nothing was held, back when dropping held items
    -- was its only job. It also collapses a repeated telling now, which has to
    -- happen whether the player is carrying anything or not.
    if (type(progress) ~= 'table') then
        return lines, 0;
    end

    local held = {};
    for _, name in ipairs(progress.held) do
        local key = clean(name):lower();
        if (key ~= '') then held[key] = true; end
    end
    local required = {};
    for _, bucket in ipairs({ progress.held, progress.needed, progress.unknown }) do
        for _, name in ipairs(type(bucket) == 'table' and bucket or {}) do
            local key = clean(name):lower();
            if (key ~= '') then required[#required + 1] = key; end
        end
    end
    if (#required == 0) then
        return lines, 0;
    end

    local kept, dropped, dropping = {}, 0, false;
    local seen = {};
    for _, line in ipairs(lines) do
        local lowered = clean(line):lower();
        local opened = nil;
        for _, key in ipairs(required) do
            if (lowered:find(key, 1, true) ~= nil) then
                opened = key;
                break;
            end
        end
        if (opened ~= nil) then
            -- ONE LINE PER THING. The reconciled list interleaves BOTH wikis,
            -- so the same item is described twice in different words --
            -- "Seedspall Luna from Quadavs in Pashhow Marshlands around (K-10)"
            -- and then "Seedspall Luna is dropped by Quadav in Pashhow
            -- Marshlands". Reading both says everything twice and pushes the
            -- third item past any sensible length. The first telling wins,
            -- because the sources are gathered in guide order.
            dropping = (held[opened] == true) or (seen[opened] == true);
            seen[opened] = true;
        end
        if (dropping) then
            dropped = dropped + 1;
        else
            kept[#kept + 1] = line;
        end
    end
    return kept, dropped;
end

-- EVERYTHING A STEP CAN TELL THE PLAYER BEYOND ITS OWN SENTENCE.
--
-- The rows written underneath it, and what of them the player already carries.
-- This exists as ONE function because the objective speech has SEVERAL return
-- paths -- an instruction-only branch, a candidate-choice branch, and a plain
-- one -- and wiring a feature into a single branch reaches only the players
-- whose current step happens to take it. Live 2026-08-27 the item progress went
-- into the instruction-only branch alone; every objective the player was
-- actually looking at came out of the candidate-choice branch, and the line
-- never once appeared in the log.
-- A VERIFIED INSTRUCTION THE GUIDE PROSE LEFT OUT.
--
-- Keyed by native key and guide step id. Additive speech only -- it never
-- touches the cursor, which is what makes it safe to add to a mission somebody
-- is already halfway through. An override would re-namespace the step ids and
-- the cursor cannot cross that boundary.
function accessxi.objective_step_note(native_key, step_id)
    native_key, step_id = clean(native_key), clean(step_id);
    if (native_key == '' or step_id == ''
        or type(accessxi.mission_quest_step_notes) ~= 'table') then
        return '';
    end
    local record = accessxi.mission_quest_step_notes[native_key];
    if (type(record) ~= 'table') then
        return '';
    end
    return clean(record[step_id]);
end

function accessxi.objective_step_supplement(item)
    if (type(item) ~= 'table') then
        return '';
    end
    local native_key = clean(item.objective_native_key);
    local step_id = clean(item.objective_guide_step_id);
    if (native_key == '' or step_id == '') then
        return '';
    end
    local step = accessxi.objective_step_for_guide_id(native_key, step_id);
    local ok, progress = pcall(accessxi.objective_item_progress, step);
    progress = ok and progress or nil;

    -- The rows under this step, minus the ones the player has finished with.
    local lines = accessxi.objective_step_detail_lines(native_key, step_id);
    local dropped = 0;
    lines, dropped = accessxi.objective_detail_lines_without_held(lines, progress);

    local parts = {};
    local detail = accessxi.objective_detail_text_from_lines(lines);
    if (clean(detail) ~= '') then
        parts[#parts + 1] = detail;
    end
    if (type(progress) == 'table' and clean(progress.speech) ~= '') then
        parts[#parts + 1] = progress.speech;
    end
    if (dropped > 0) then
        log_line(('objective detail dropped %d line(s) for held items step="%s"'):fmt(
            dropped, accessxi.escape_probe_log_text(step_id)));
    end
    -- Last, so it reads as the addition it is rather than displacing the
    -- guide's own words.
    local note = accessxi.objective_step_note(native_key, step_id);
    if (note ~= '') then
        parts[#parts + 1] = note;
    end
    return table.concat(parts, ' ');
end

-- The source step behind a guide step id, so the speech can ask what the step
-- requires without the caller having to carry the whole step around.
function accessxi.objective_step_for_guide_id(native_key, step_id)
    step_id = clean(step_id);
    if (step_id == '' or type(objective_source_steps) ~= 'function') then
        return nil;
    end
    local ok, steps = pcall(objective_source_steps, native_key);
    if (not ok or type(steps) ~= 'table') then
        return nil;
    end
    for _, step in ipairs(steps) do
        if (clean(step.stable_step_id) == step_id) then
            return step;
        end
    end
    return nil;
end

-- WHAT THE PLAYER ALREADY HAS.
--
-- Written with sol. The requirement model, the per-store deduplication, the
-- max-of-duplicate-quantities rule and the shape of the speech are its design;
-- I changed three things and the reasons matter.
--
--  1. It reached for objective_inventory_state_ready(), which accepts a source
--     string 'packet_in_inventory' that is assigned NOWHERE in the tree. This
--     uses accessxi.objective_inventory_state_available(), which additionally
--     requires the snapshot to have actually seen a container -- 199 of 601
--     snapshots in the live log recorded zero items while still being stamped
--     'native-inventory'.
--  2. It hedged ordinary items as "Not in your inventory", because at the time
--     the scan read container 0 only and an item in a satchel or Mog Storage
--     was invisible. That is fixed: the scan now walks every loaded container,
--     so absence is now a real finding and says so.
--  3. Ownership goes through accessxi.objective_inventory_named_state, which
--     returns the three states directly rather than reconstructing them from a
--     count and an id.
--
-- THE RULE THROUGHOUT: a thing we cannot check is 'unknown', never 'needed'.
-- Telling a player to go and farm a Seedspall they are carrying is worse than
-- telling them nothing, and this addon has already lost twelve days to a false
-- that meant both "no" and "no data".
function accessxi.objective_item_progress(step)
    local result = {
        total = 0, held = {}, needed = {}, unknown = {},
        kind = 'item', speech = '',
    };
    if (type(step) ~= 'table') then
        return result;
    end

    local requirements, order = {}, {};
    local has_items, has_key_items = false, false;

    local function add_requirement(requirement_kind, entry)
        local name, required = '', 1;
        if (type(entry) == 'table') then
            if (requirement_kind == 'key-item') then
                name = clean(entry.name or entry.key_item or '');
            else
                name = clean(entry.name or entry.item or '');
                required = math.max(1, tonumber(entry.count or entry.quantity) or 1);
            end
        else
            name = clean(entry);
        end
        if (name == '') then
            return;
        end
        -- Keyed by STORE as well as name: an item and a key item may share a
        -- label and are two different ownership questions.
        local key = requirement_kind .. '\t' .. name:lower();
        if (requirements[key] == nil) then
            requirements[key] = { kind = requirement_kind, name = name, required = required };
            order[#order + 1] = key;
        else
            requirements[key].required = math.max(
                tonumber(requirements[key].required) or 1, required);
        end
        if (requirement_kind == 'key-item') then has_key_items = true;
        else has_items = true; end
    end

    for _, entry in ipairs(type(step.items) == 'table' and step.items or {}) do
        add_requirement('item', entry);
    end
    for _, entry in ipairs(type(step.key_items) == 'table' and step.key_items or {}) do
        add_requirement('key-item', entry);
    end

    -- THE ITEM NAMES ARE IN ENTITIES, NOT ITEMS.
    --
    -- The reconciled corpus carries no `items` field on these steps at all --
    -- "Collect the following 3 items:" and each Seedspall row beneath it list
    -- their names in `entities` beside the zone they drop in. So this asked for
    -- zero requirements and stayed silent, and live 2026-08-27 the player saw
    -- the Jugner Forest directions for a Seedspall they were already carrying.
    --
    -- An entity IS an item when the game's own resources resolve it to an item
    -- id. That is the same test the ownership reader applies, so a name we
    -- cannot resolve simply never becomes a requirement -- a zone, an NPC or a
    -- mob family resolves to nothing and is skipped. Only used when the step
    -- named no items of its own, so declared data always wins.
    if (not has_items and type(accessxi.objective_inventory_named_state) == 'function') then
        for _, entry in ipairs(type(step.entities) == 'table' and step.entities or {}) do
            local name = clean(type(entry) == 'table' and (entry.name or entry.item) or entry);
            if (name ~= '') then
                local ok, _, item_id = pcall(accessxi.objective_inventory_named_state, name);
                if (ok and tonumber(item_id) ~= nil and (tonumber(item_id) or 0) > 0) then
                    add_requirement('item', name);
                end
            end
        end
    end

    result.total = #order;
    if (has_items and has_key_items) then result.kind = 'mixed';
    elseif (has_key_items) then result.kind = 'key-item'; end
    if (result.total == 0) then
        return result;
    end

    local ordinary_needed, key_item_needed = {}, {};
    for _, key in ipairs(order) do
        local requirement = requirements[key];
        local state = 'unknown';
        if (requirement.kind == 'item') then
            if (type(accessxi.objective_inventory_named_state) == 'function') then
                local ok, count, _, named_state = pcall(
                    accessxi.objective_inventory_named_state, requirement.name);
                if (ok and named_state == 'held') then
                    state = ((tonumber(count) or 0) >= requirement.required)
                        and 'held' or 'needed';
                elseif (ok and named_state == 'absent') then
                    state = 'needed';
                end
            end
        elseif (type(accessxi.objective_key_item_owned_by_name) == 'function'
            and type(accessxi.mission_quest_key_item_state) == 'function') then
            local id_ok, _, key_item_id = pcall(
                accessxi.objective_key_item_owned_by_name, requirement.name);
            if (id_ok and tonumber(key_item_id) ~= nil) then
                local state_ok, key_item_state = pcall(
                    accessxi.mission_quest_key_item_state, key_item_id);
                if (state_ok and key_item_state == 'held') then state = 'held';
                elseif (state_ok and key_item_state == 'absent') then state = 'needed'; end
            end
        end
        result[state][#result[state] + 1] = requirement.name;
        if (state == 'needed') then
            if (requirement.kind == 'key-item') then
                key_item_needed[#key_item_needed + 1] = requirement.name;
            else
                ordinary_needed[#ordinary_needed + 1] = requirement.name;
            end
        end
    end

    -- Nothing checkable means nothing worth saying. A row of "could not check"
    -- is noise, and the player still has the guide's own words.
    if (#result.unknown == result.total) then
        return result;
    end

    local parts = {};
    if (#result.unknown > 0) then
        parts[#parts + 1] = ('Confirmed held: %d of %d.'):fmt(#result.held, result.total);
    else
        parts[#parts + 1] = ('You have %d of %d.'):fmt(#result.held, result.total);
    end
    if (#result.held > 0) then
        parts[#parts + 1] = ('Held: %s.'):fmt(table.concat(result.held, ', '));
    end
    if (#ordinary_needed > 0) then
        parts[#parts + 1] = ('Still needed: %s.'):fmt(table.concat(ordinary_needed, ', '));
    end
    if (#key_item_needed > 0) then
        local label = result.kind == 'key-item' and 'Still needed' or 'Key items still needed';
        parts[#parts + 1] = ('%s: %s.'):fmt(label, table.concat(key_item_needed, ', '));
    end
    if (#result.unknown > 0) then
        parts[#parts + 1] = ('Could not check: %s.'):fmt(table.concat(result.unknown, ', '));
    end
    result.speech = table.concat(parts, ' ');
    return result;
end

-- THE LINES UNDER THE LINE.
--
-- The guides are written as a TREE and we store them as a flat list. A step
-- like "Collect the following 3 items:" carries no target of its own, because
-- everything that answers the question is in the rows beneath it:
--
--     Collect the following 3 items:                        <- what we spoke
--       Seedspall Lux    from Orcs    in Jugner Forest (G-11)
--         Closest Survival Guide is Davoi.
--       Seedspall Luna   from Quadavs in Pashhow Marshlands (K-10)
--         Closest Survival Guide is Beadeaux.
--       Seedspall Astrum from Yagudos in Meriphataud Mountains (K-8)
--         Closest Survival Guide is Castle Oztroja.
--
-- Live 2026-08-27 the player heard "Current instruction: Collect the following
-- 3 items:" and then the mission's flavour text. Three items, three zones,
-- three mob families and three nearby Survival Guides -- every word of it
-- already in our data, none of it spoken. They said it plainly: "it doesn't
-- track the mission, or the items. Where do I go, who do I talk to what do I
-- get." A sighted player reads the next three lines off the page. Ending on a
-- colon and saying nothing is the exact failure this addon exists to prevent.
--
-- The reconciled list drops the depth field but keeps the rows in order, and a
-- child is always an `action = "note"` step following its parent. So the
-- subtree is simply the run of notes up to the next real step. No tree needed.
function accessxi.objective_step_detail_lines(native_key, step_id)
    local lines = {};
    if (type(objective_source_steps) ~= 'function') then
        return lines;
    end
    step_id = clean(step_id);
    if (step_id == '') then
        return lines;
    end
    local ok, steps = pcall(objective_source_steps, native_key);
    if (not ok or type(steps) ~= 'table') then
        return lines;
    end
    -- ONE AUTHOR, NOT TWO.
    --
    -- The reconciled list interleaves both sources: rows 002-007 are BG Wiki's
    -- three items with their zones and grid references, and rows 008-011 are
    -- FFXIclopedia describing the SAME three items in different words. Reading
    -- straight through says every item twice -- "Seedspall Lux from Orcs in
    -- Jugner Forest around (G-11)" and then "Seedspall Lux is dropped by Orc in
    -- Jugner Forest" -- and, with any cap on length, risks spending the budget
    -- on the repeat and never reaching the third item. So gather the subtree
    -- once per source and speak whichever is more complete.
    local subtree = {};
    local found = false;
    for _, step in ipairs(steps) do
        if (found) then
            if (clean(step.action):lower() ~= 'note') then
                break;      -- the next real step ends the subtree
            end
            subtree[#subtree + 1] = step;
        elseif (clean(step.stable_step_id) == step_id) then
            found = true;
        end
    end

    local function gather(field)
        local out = {};
        for _, step in ipairs(subtree) do
            local text = clean(step[field]);
            -- "Section: Repeats." and friends are the scraper's structural
            -- markers, not anything the player does.
            if (text ~= '' and text:sub(1, 8):lower() ~= 'section:') then
                out[#out + 1] = text;
                if (#out >= 8) then
                    break;  -- a wall of speech helps nobody
                end
            end
        end
        return out;
    end

    -- THE PRIMARY SOURCE, NOT THE LONGEST ONE.
    --
    -- Choosing whichever source had more lines picked verbosity over relevance:
    -- for the Seedspall trade it dropped BG Wiki's "Mid-east section of (G-6),
    -- near 2 rock columns" in favour of four FFXIclopedia lines that wandered
    -- into a repeatable key-item aside. The guide index already declares which
    -- source is authoritative for each objective -- primary "bg", fallback
    -- "ffxiclopedia" -- so follow that and fall back only when the primary
    -- wrote nothing at all.
    lines = gather('primary_instruction');
    if (#lines == 0) then lines = gather('bg_instruction'); end
    if (#lines == 0) then lines = gather('ffxiclopedia_instruction'); end
    return lines;
end

function accessxi.objective_step_detail_text(native_key, step_id)
    return accessxi.objective_detail_text_from_lines(
        accessxi.objective_step_detail_lines(native_key, step_id));
end

function accessxi.objective_detail_text_from_lines(lines)
    lines = type(lines) == 'table' and lines or {};
    if (#lines == 0) then
        return '';
    end
    local out = {};
    for _, line in ipairs(lines) do
        -- Each detail is its own sentence so a screen reader pauses between
        -- them; without that, three item lines run together into one breath.
        if (line:sub(-1) ~= '.' and line:sub(-1) ~= '!' and line:sub(-1) ~= '?') then
            line = line .. '.';
        end
        out[#out + 1] = line;
    end
    return table.concat(out, ' ');
end

local function source_route_candidate(native_key, step, point)
    local step_id = clean(step.stable_step_id);
    -- A step with no primary_instruction still has the sentence one of the two
    -- sources wrote, and source_route_candidate refuses to build a row without
    -- one -- so the guide's own words decide whether the player gets a target.
    local instruction = clean(step.primary_instruction);
    if (instruction == '') then instruction = clean(step.bg_instruction); end
    if (instruction == '') then instruction = clean(step.ffxiclopedia_instruction); end
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
    -- The guide's own words stay in speech ("Prince Trion"); the catalogue
    -- name stays the routing identity. A choice note (an unbound map square)
    -- rides on the instruction so the limitation is spoken with the choice.
    local spoken = clean(point.spoken_name) ~= '' and clean(point.spoken_name) or name;
    local choice_note = clean(point.choice_note);
    if (choice_note ~= '') then
        instruction = instruction .. ' ' .. choice_note;
    end
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
        canonical_edge_id = tonumber(point.canonical_edge_id),
        canonical_from_zone = tonumber(point.canonical_from_zone),
        objective_via_zones = deep_copy(point.objective_via_zones),
        source_route_entry_distance2 = tonumber(point._source_route_entry_distance2),
        label = ('%s in %s'):fmt(spoken, zone_name ~= '' and zone_name or ('zone %d'):fmt(zone)),
        items = type(step.items) == 'table' and deep_copy(step.items) or T{},
        key_items = type(step.key_items) == 'table' and deep_copy(step.key_items) or T{},
        enemies = enemies,
    };
end

-- FORWARD DECLARED, because two callers below need it and it is defined 500
-- lines further down. In Lua 5.1 a local's scope starts AFTER its declaration,
-- so `local function progression_actions` at its definition site was invisible
-- here and both callers compiled to a GLOBAL read -- nil at runtime, raising
-- rather than silently returning nothing. Verified in the bytecode: two GGET
-- "progression_actions" instructions, now none. Same trap that made
-- nav_objective_travel_destination_zones reach a nil progression_revision.
local progression_actions;
local progression_revision;

local function source_route_rows(native_key)
    reset_source_derivation_cache_if_needed();
    native_key = clean(native_key);
    -- Zone-travel rows depend on where the player stands (which zone-line
    -- chain reaches the destination), so a cached answer is only good while
    -- the player is still in the zone it was computed for.
    local player_zone = tonumber(type(accessxi.current_zone_id) == 'function'
        and accessxi.current_zone_id() or 0) or 0;
    local cached_rows = source_derivation_cache.source_routes[native_key];
    if (cached_rows ~= nil and (cached_rows.player_zone == nil or cached_rows.player_zone == player_zone)) then
        return cached_rows;
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
    local resolver = accessxi.mission_step_resolver;
    local refusals = {};
    -- What a step resolved TO, so an announcement can say whether pressing I
    -- will actually take the player somewhere. sol's guard: never promise a key
    -- that cannot deliver -- the same false instruction as "Press G for the
    -- source guide" while nothing read G.
    local resolutions = {};
    -- THIS OBJECTIVE'S COMPACT ACTIONS, keyed by the id the reconciled rows
    -- call stable_step_id and the compact rows call step_id. Built from the
    -- VALIDATED helper rather than the raw guide call, so the same field
    -- checks, deep copy and ordering apply -- and built once, because both the
    -- declared-result join and the primary-target lookup read it per step.
    local resolver_actions_by_step = {};
    for _, compact in ipairs(progression_actions(native_key) or T{}) do
        local compact_step_id = clean(compact.step_id);
        if (compact_step_id ~= '') then
            resolver_actions_by_step[compact_step_id] =
                resolver_actions_by_step[compact_step_id] or T{};
            resolver_actions_by_step[compact_step_id]:append(compact);
        end
    end
    local resolver_ctx = nil;
    if (type(resolver) == 'table') then
        local zone_name_cache = {};
        local incoming_by_zone = nil;
        local entry_edge_workspace = nil;
        local entry_edge_trees = {};

        local function load_resolver_zoneline_index()
            if (incoming_by_zone ~= nil) then
                return true;
            end

            if (type(accessxi.nav_load_zoneline_graph)
                == 'function') then
                local ok = pcall(
                    accessxi.nav_load_zoneline_graph);

                if (not ok) then return false; end
            end

            if (type(accessxi.nav_zoneline_edges)
                ~= 'table') then
                return false;
            end

            incoming_by_zone = {};

            for _, edge in ipairs(
                accessxi.nav_zoneline_edges) do
                local to_zone =
                    tonumber(edge.to_zone) or 0;

                incoming_by_zone[to_zone] =
                    incoming_by_zone[to_zone] or T{};
                incoming_by_zone[to_zone]:append(edge);
            end

            return true;
        end

        local function resolver_incoming_edges(zone)
            zone = tonumber(zone) or 0;

            if (not load_resolver_zoneline_index()) then
                return T{};
            end

            return incoming_by_zone[zone] or T{};
        end

        local function resolver_entry_edge_candidates(
            from_zone,
            destination_zones,
            preferred_zones)

            if (type(preferred_zones) == 'table'
                and next(preferred_zones) ~= nil) then
                return nil;
            end

            if (not load_resolver_zoneline_index()
                or type(accessxi.nav_zoneline_entry_edge_workspace)
                    ~= 'function'
                or type(accessxi.nav_zoneline_entry_edge_shortest_tree)
                    ~= 'function'
                or type(accessxi.nav_zoneline_entry_edge_candidates)
                    ~= 'function'
                or type(accessxi.nav_transport_edge_available)
                    ~= 'function') then
                return nil;
            end

            if (entry_edge_workspace == nil) then
                entry_edge_workspace =
                    accessxi.nav_zoneline_entry_edge_workspace(
                        accessxi.nav_zoneline_edges,
                        function(edge)
                            return accessxi
                                .nav_transport_edge_available(edge);
                        end,
                        function(edge)
                            if (type(accessxi.nav_zoneline_edge_rank)
                                ~= 'function') then
                                return 50;
                            end

                            return accessxi.nav_zoneline_edge_rank(
                                edge,
                                nil);
                        end);
            end

            from_zone = tonumber(from_zone) or 0;
            local tree = entry_edge_trees[from_zone];

            if (tree == nil) then
                tree =
                    accessxi.nav_zoneline_entry_edge_shortest_tree(
                        entry_edge_workspace,
                        from_zone);
                entry_edge_trees[from_zone] = tree;
            end

            return accessxi.nav_zoneline_entry_edge_candidates(
                entry_edge_workspace,
                tree,
                destination_zones,
                resolver_incoming_edges);
        end
        resolver_ctx = {
            player_zone = player_zone,
            destination_ingress = accessxi.nav_destination_ingress,
            select_destination_ingress = type(accessxi.destination_ingress) == 'table'
                and accessxi.destination_ingress.select or nil,
            name_key = source_name_key,
            zone_ids_for_name = function (value)
                return known_zones[source_name_key(value)];
            end,
            points_for_zone_entity = function (zone, key)
                return catalog.points_by_zone_entity[('%d\t%s'):fmt(tonumber(zone) or 0, key)];
            end,
            points_for_entity = function (key)
                return catalog.points_by_entity[key];
            end,
            points_for_zone_base = function (zone, key)
                return catalog.points_by_zone_base[('%d	%s'):fmt(tonumber(zone) or 0, key)];
            end,
            points_for_entity_base = function (key)
                return catalog.points_by_base[key];
            end,
            -- Authoritative city groups: ordinary districts only. Chateau
            -- d'Oraguille, Metalworks and Heavens Tower appear only when named.
            nation_zones = function (value)
                return accessxi.nav_nation_district_zones(value);
            end,
            nation_of_zone = function (zone)
                return accessxi.nav_nation_of_zone(zone);
            end,
            step_target_binding = function (step_id)
                return accessxi.nav_step_target_binding(step_id);
            end,
            default_zone_group = accessxi.nav_nation_zone_group(native_key),
            effective_kind = effective_kind,
            kind_allowed = source_route_kind_allowed,
            -- What the guide DECLARES this step yields, so a reward is never
            -- mistaken for a destination. Read from the compact progression
            -- action, which is where these fields are populated -- the
            -- reconciled step's own are empty throughout.
            declared_result_names = function (step_id)
                local names = {};
                step_id = clean(step_id);
                if (step_id == '') then return names; end
                for _, action in ipairs(
                    resolver_actions_by_step[step_id] or T{}) do
                    if (clean(action.step_id) == step_id) then
                        for _, field in ipairs({ 'items', 'key_items', 'result_items' }) do
                            for _, entry in ipairs(type(action[field]) == 'table' and action[field] or T{}) do
                                local name = clean(type(entry) == 'table'
                                    and (entry.name or entry.item or entry.key_item) or entry);
                                if (name ~= '') then names[name:lower()] = true; end
                            end
                        end
                    end
                end
                return names;
            end,
            -- EACH PAGE'S OWN READING of a step the sources word differently.
            -- The merged entities-by-zones list can name a place neither page
            -- stated, so a conflicted step is resolved from the two readings
            -- separately and never from the union (sol).
            source_readings = function (step_id)
                if (type(accessxi.objective_guides) ~= 'table'
                    or type(accessxi.objective_guides.source_step_readings) ~= 'function') then
                    return {};
                end
                local ok, value = pcall(
                    accessxi.objective_guides.source_step_readings,
                    accessxi.objective_guides, native_key, clean(step_id));
                return (ok and type(value) == 'table') and value or {};
            end,
            -- WHAT THIS STEP PROVES IT IS ABOUT. The compact action's
            -- relationship and exact target, joined on the step id -- the
            -- guide naming one target for this step, which an inherited zone
            -- was never evidence about.
            primary_actions_for_step = function (step_id)
                return resolver_actions_by_step[clean(step_id)] or T{};
            end,
            -- Who fills a role the guide names instead of a person.
            role_members = role_members_for,
            point_for_destination_id = point_for_destination_id,
            zone_name = function (zone)
                zone = tonumber(zone) or 0;
                if (zone_name_cache[zone] == nil) then
                    zone_name_cache[zone] = source_point_zone_name({ zone = zone });
                end
                return zone_name_cache[zone];
            end,
            -- Indexed once per pass, and answered for every destination at
            -- once when no road is named. A named road is scored per
            -- destination, so it keeps the per-entrance search (sol).
            incoming_edges = resolver_incoming_edges,
            entry_edge_candidates = resolver_entry_edge_candidates,
            zone_path = function (from_zone, to_zone, edge_id, preferred_zones)
                if (type(accessxi.nav_zoneline_path) ~= 'function') then
                    return T{};
                end
                local ok, path = pcall(accessxi.nav_zoneline_path,
                    from_zone, to_zone, edge_id, preferred_zones);
                return ok and path or T{};
            end,
            zone_id_for_name = function (name)
                if (type(accessxi.nav_zone_id_for_name) ~= 'function') then
                    return 0;
                end
                local ok, zone = pcall(accessxi.nav_zone_id_for_name, name);
                return ok and (tonumber(zone) or 0) or 0;
            end,
            edge_rank = function (edge)
                if (type(accessxi.nav_zoneline_edge_rank) ~= 'function') then
                    return 50;
                end
                local ok, rank = pcall(accessxi.nav_zoneline_edge_rank, edge, nil);
                return ok and tonumber(rank) or 50;
            end,
            destination_zone_for_step = function (step_id)
                if (type(accessxi.objective_guides) ~= 'table'
                    or type(accessxi.objective_guides.progression_actions) ~= 'function') then
                    return 0;
                end
                local ok, actions = pcall(accessxi.objective_guides.progression_actions,
                    accessxi.objective_guides, native_key);
                if (not ok or type(actions) ~= 'table') then
                    return 0;
                end
                for _, action in ipairs(actions) do
                    if (clean(action.step_id) == step_id
                        and (tonumber(action.destination_zone_id) or 0) > 0) then
                        return tonumber(action.destination_zone_id);
                    end
                end
                return 0;
            end,
        };
    end
    -- Advice the guide wrote as its own note but that belongs to another
    -- step: spoken WITH that step rather than routed to on its own.
    local attached_notes = type(resolver) == 'table'
        and type(resolver.note_attachments) == 'function'
        and resolver.note_attachments(steps) or {};
    for step_index, step in ipairs(steps) do
        -- A CONFLICT IS NO LONGER SKIPPED. It used to be dropped here AND
        -- refused by the resolver, so a step both pages describe -- in
        -- different words -- produced no row at all and the player was told no
        -- route existed. The resolver now reads each page separately and
        -- offers what they name; if it still cannot, it says so like any other
        -- refusal, with the guide's sentence attached.
        if (type(step) == 'table'
            and step.optional_nonessential ~= true
            and step.route_recommendation ~= true) then
            local targets = {};
            -- WHAT MAY ANSWER FOR THIS STEP. A note is information unless the
            -- guide carries an explicit route binding for it; the flattened
            -- entities-by-zones cross-product is never one, however few
            -- candidates it happens to yield (sol).
            local action = clean(step.action):lower();
            local source_mode = 'ordinary';
            if (type(resolver) == 'table'
                and type(resolver.note_source_mode) == 'function') then
                source_mode = resolver.note_source_mode(step);
            elseif (action == 'note') then
                if (clean(step.note_attach_to_step_id) ~= '') then
                    source_mode = 'attachment';
                elseif (step.navigation_target ~= nil) then
                    source_mode = 'verified';
                else
                    source_mode = 'information';
                end
            end
            local allow_verified_target = source_mode == 'ordinary'
                or source_mode == 'verified';
            local allow_resolver = source_mode == 'ordinary'
                or source_mode == 'explicit'
                or source_mode == 'information';
            local navigation_target = allow_verified_target
                and step.navigation_target or nil;
            if (type(navigation_target) == 'table') then
                local target = nil;
                if (type(navigation_target.reference) == 'table') then
                    target = referenced_target(navigation_target.reference);
                elseif (type(navigation_target.point) == 'table') then
                    target = point_copy(navigation_target.point);
                end
                if (target ~= nil) then targets[#targets + 1] = target; end
            end

            -- LEGACY ONLY. This zone-and-entity lookup answers before the
            -- resolver can, and it neither deduplicates nor records what it
            -- chose -- so a same-zone Qufim ??? or a numbered Home Point took
            -- this path and never reached the shared candidate finalizer
            -- (sol). It stays as the fallback for a context the resolver
            -- cannot be given.
            if (#targets == 0 and resolver_ctx == nil
                and source_mode == 'ordinary') then
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

            -- The old rule above needs zone AND entity on the same step. What
            -- it leaves empty goes to the resolver: inherited zone context,
            -- unique-catalogue fallback, zone-travel through the zone-line
            -- graph -- or a named refusal recorded for this step.
            if (#targets == 0 and resolver_ctx ~= nil and allow_resolver) then
                local resolved, info = resolver.resolve_step(steps, step_index, resolver_ctx);
                if (type(resolved) == 'table' and #resolved > 0) then
                    info = type(info) == 'table' and info or {};
                    if (type(step.search_set) == 'table') then
                        info.kind = 'search-set';
                        info.choice_stage = 'search';
                        info.unbound_square = '';
                        info.ambiguity = '';
                        info.equivalent_choices = true;
                    end
                    for _, point in ipairs(resolved) do
                        targets[#targets + 1] = point_copy_with_identity(point);
                    end
                    resolutions[clean(step.stable_step_id)] = {
                        kind = clean(info.kind),
                        partial = clean(info.partial),
                        ambiguity = clean(info.ambiguity),
                        choice_stage = clean(info.choice_stage),
                        completion_item = type(step.search_set) == 'table'
                            and clean(step.search_set.completion_item) or '',
                        choice_count = tonumber(info.choice_count) or #resolved,
                        equivalent_choices = info.equivalent_choices,
                        choice_origin = clean(info.choice_origin),
                        narrowed_by = clean(info.narrowed_by),
                        unbound_square = clean(info.unbound_square),
                        unreachable_choices = type(info.unreachable_choices) == 'table'
                            and deep_copy(info.unreachable_choices) or T{},
                        inherited_context_conflict =
                            info.inherited_context_conflict == true,
                        overridden_inherited_zone =
                            tonumber(info.overridden_inherited_zone),
                        inherited_from = clean(info.inherited_from),
                        review_basis = clean(info.review_basis),
                        primary_target_source = clean(info.primary_target_source),
                        zone_name = clean(type(resolved[1]) == 'table' and resolved[1].zone_name or ''),
                    };
                    -- AND KEEP THE DESTINATION ZONES SOMEWHERE A ZONE CHANGE
                    -- CANNOT WIPE. source_derivation_cache is invalidated the
                    -- moment the player moves zone -- which is precisely when a
                    -- travel step completes -- so the answer has to be recorded
                    -- while they are still on their way. Written per step id,
                    -- carrying the revision it was computed against.
                    if (resolver.is_zone_changing_action(clean(step.action))) then
                        local zones = {};
                        for _, point in ipairs(resolved) do
                            local zone = tonumber(point.zone) or 0;
                            if (zone > 0) then zones[zone] = true; end
                        end
                        if (next(zones) ~= nil) then
                            accessxi.nav_objective_travel_zones =
                                accessxi.nav_objective_travel_zones or {};
                            accessxi.nav_objective_travel_zones[native_key] =
                                accessxi.nav_objective_travel_zones[native_key] or {};
                            accessxi.nav_objective_travel_zones[native_key][clean(step.stable_step_id)] = {
                                zones = zones,
                                revision = clean(progression_revision(native_key)),
                            };
                        end
                    end
                    log_line(('objective step resolved native="%s" step="%s" kind=%s zone=%s count=%d'):fmt(
                        native_key, clean(step.stable_step_id), tostring(info.kind),
                        tostring(info.inherited_zone or info.destination_zone or ''), #resolved));
                elseif (type(info) == 'table' and info.reason ~= nil) then
                    -- THE GUIDE'S OWN SENTENCE TRAVELS WITH THE REFUSAL.
                    -- Not being able to route somewhere is no reason to
                    -- withhold what the page says to do there. A sighted
                    -- player reading the same wiki line still knows the
                    -- objective; today ours heard "No route" and nothing else,
                    -- 547 times in one session (sol: information may be
                    -- guide-backed, movement must be evidence-backed, and a
                    -- routing failure must never suppress the instruction).
                    if (clean(info.instruction) == '') then
                        info.instruction = clean(step.primary_instruction);
                        if (info.instruction == '') then
                            info.instruction = clean(step.bg_instruction);
                        end
                        if (info.instruction == '') then
                            info.instruction = clean(step.ffxiclopedia_instruction);
                        end
                    end
                    refusals[clean(step.stable_step_id)] = info;
                    log_line(('objective step refused native="%s" step="%s" reason=%s detail="%s" instruction="%s"'):fmt(
                        native_key, clean(step.stable_step_id), tostring(info.reason),
                        tostring(info.detail or ''), clean(step.primary_instruction)));
                end
            end

            -- THE ROAD THE GUIDE NAMED TRAVELS WITH THE TARGET. Threading it
            -- through the resolver alone was not enough: the zone SEARCH path
            -- builds its own chain, and that is what routed a level-14 player
            -- into King Ranperre's Tomb on 2026-08-22 while step-009 said
            -- "zone into Jugner Forest from La Theine Plateau". Carrying it on
            -- the target means every builder sees the same preference.
            if (resolver_ctx ~= nil and type(resolver.named_via_zones) == 'function') then
                local via = resolver.named_via_zones(step, resolver_ctx);
                if type(targets[1]) == 'table' and type(targets[1].objective_via_zones) == 'table' then
                    via = targets[1].objective_via_zones;
                end
                if (via ~= nil) then
                    for _, point in ipairs(targets) do
                        if type(point.objective_via_zones) ~= 'table' then point.objective_via_zones = via; end
                    end
                    -- AND PUBLISH IT AGAINST THE STEP ID. Carrying the road on
                    -- the point failed three times: the object that actually
                    -- gets routed to is rebuilt from explicit field lists in
                    -- several places, and every one of them silently dropped a
                    -- key it had never heard of -- `NO GUIDE ROAD given=nil` at
                    -- the moment of route start, while the correct road had
                    -- been computed eight seconds earlier. The step id is
                    -- carried by every one of those lists (the spoken
                    -- instruction depends on it), so a registry keyed on it
                    -- cannot be dropped by a copy that does not know about it.
                    local roads = accessxi.nav_guide_road_by_step;
                    if (type(roads) ~= 'table') then
                        roads = {};
                        accessxi.nav_guide_road_by_step = roads;
                    end
                    roads[clean(step.stable_step_id)] = via;
                end
            end

            if (action == 'fight' or action == 'obtain') then
                for _, point in ipairs(targets) do
                    local kind = effective_kind(point);
                    if (kind == 'enemy' or kind == 'nm' or kind == 'live-nm') then
                        point._source_route_entry_distance2 = source_route_entry_distance2(point, zone_entries);
                    end
                end
            end
            table.sort(targets, source_route_point_less);
            -- EVERY CHOICE IS OFFERED. A cap of four per name and zone
            -- silently dropped the fifth Home Point and the fifth ??? -- which
            -- made "nothing is chosen for the player" false in exactly the
            -- cases the resolver works hardest to keep open, and did it without
            -- saying so. The list cursor already scrolls, so there is nothing
            -- to page (sol).
            for _, point in ipairs(targets) do
                local emitted_point = point;
                if (type(resolver) == 'table'
                    and type(resolver.point_with_attached_notes) == 'function') then
                    emitted_point = resolver.point_with_attached_notes(
                        point, attached_notes[clean(step.stable_step_id)]);
                end
                local row = source_route_candidate(native_key, step, emitted_point);
                -- A later return to the same contact is a different objective.
                -- Deduplicate within a step so its destination is still present
                -- when the cursor advances past the first visit.
                local key = row ~= nil and clean(row.destination_id) ~= ''
                    and (clean(step.stable_step_id) .. '\t' .. clean(row.destination_id)) or '';
                if (row ~= nil and key ~= '' and seen[key] ~= true) then
                    seen[key] = true;
                    rows:append(row);
                end
            end
        end
    end
    rows.player_zone = player_zone;
    source_derivation_cache.source_routes[native_key] = rows;
    source_derivation_cache.source_route_refusals = source_derivation_cache.source_route_refusals or {};
    source_derivation_cache.source_route_refusals[native_key] = refusals;
    source_derivation_cache.source_route_resolutions = source_derivation_cache.source_route_resolutions or {};
    source_derivation_cache.source_route_resolutions[native_key] = resolutions;
    accessxi.nav_objective_source_route_compute_count =
        (tonumber(accessxi.nav_objective_source_route_compute_count) or 0) + 1;
    return rows;
end

-- The recorded refusal for one guide step, or nil when the step resolved
-- (or was never examined). A prerequisite block (ruling 4) outranks the
-- resolver's own reason: "obtain the oil first" is the answer, not "Silent
-- Oil is not in the catalogue".
-- The step a mission opens on, for the sentence that announces it. Nothing here
-- moves a cursor or claims progress -- it reads the guide's first action.
function accessxi.nav_mission_quest_first_objective(native_key)
    local actions = progression_actions(clean(native_key));
    local first = type(actions) == 'table' and actions[1] or nil;
    if (type(first) ~= 'table') then return '', ''; end
    return clean(first.instruction), clean(first.step_id);
end

-- Can the player actually be taken to this step, and how far? Three answers
-- only: the endpoint, the zone the guide named, or nowhere.
-- The resolver kinds that mean "the player still has to pick".
local CHOICE_RESOLUTION_KINDS = {
    ['search-set'] = true,
    ['entity-choice'] = true,
    ['entity-zone-choice'] = true,
    ['return-to-prior-choice'] = true,
    ['note-route-choice'] = true,
};

function accessxi.nav_mission_quest_step_route_capability(native_key, step_id)
    local announcer = accessxi.objective_announcer;
    if (type(announcer) ~= 'table') then return 'unavailable', ''; end
    native_key = clean(native_key);
    step_id = clean(step_id);
    if (step_id == '') then return announcer.ROUTE.UNAVAILABLE, ''; end
    -- NOT YET COMPUTED IS NOT THE SAME AS NO ROUTE.
    --
    -- This reads a cache that source_route_rows fills, and a mission that has
    -- only just become active has nothing in it. Live 2026-08-23, arriving in
    -- Mhaura finished Rhapsodies 3 and accepted "Emissary from the Seas"; the
    -- announcement asked for the route at 17:21:31 and was told there was
    -- none, and the routes for that mission were computed five seconds later
    -- at 17:21:36 -- kind=zone-travel, zone 249. The player heard "No route is
    -- available for this objective" about a step that had one all along, and
    -- the same race silenced the previous mission's "Mhaura or Selbina" step.
    --
    -- So compute them. It is cached per mission and per player zone, so this
    -- costs nothing when the answer is already known and only moves the work
    -- earlier when it is not.
    pcall(source_route_rows, native_key);
    if (accessxi.nav_mission_quest_step_refusal(native_key, step_id) ~= nil) then
        return announcer.ROUTE.UNAVAILABLE, '';
    end
    local per_key = type(source_derivation_cache.source_route_resolutions) == 'table'
        and source_derivation_cache.source_route_resolutions[native_key] or nil;
    local resolution = type(per_key) == 'table' and per_key[step_id] or nil;
    if (type(resolution) ~= 'table') then
        -- Nothing recorded either way: the step was never resolved this pass,
        -- so we cannot claim a route for it.
        return announcer.ROUTE.UNAVAILABLE, '';
    end
    -- A CHOICE IS NOT A ROUTE, AND NOT A REFUSAL EITHER. The three answers
    -- full / zone-only / unavailable had nowhere to put "several places fit
    -- this and the guide does not say which", so a two-stage choice would have
    -- been announced as "Press I to start navigation" -- a promise that one of
    -- them had been picked. It has not been, and it never will be by us.
    local kind = clean(resolution.kind);
    local unreachable = 0;
    for _, entry in ipairs(type(resolution.unreachable_choices) == 'table'
        and resolution.unreachable_choices or T{}) do
        unreachable = unreachable + (tonumber(entry.count) or 1);
    end
    if (CHOICE_RESOLUTION_KINDS[kind] == true or unreachable > 0) then
        return announcer.ROUTE.CHOICE, clean(resolution.zone_name), {
            count = tonumber(resolution.choice_count) or 0,
            stage = clean(resolution.choice_stage),
            completion_item = clean(resolution.completion_item),
            unbound_square = clean(resolution.unbound_square),
            unreachable = unreachable,
        };
    end
    if (clean(resolution.partial) ~= '') then
        return announcer.ROUTE.ZONE_ONLY, clean(resolution.zone_name);
    end
    return announcer.ROUTE.FULL, clean(resolution.zone_name);
end

function accessxi.nav_mission_quest_step_refusal(native_key, step_id)
    native_key = clean(native_key);
    step_id = clean(step_id);
    local blocks = source_derivation_cache.prerequisite_refusals;
    if (type(blocks) == 'table' and type(blocks[native_key]) == 'table'
        and blocks[native_key][step_id] ~= nil
        and blocks[native_key][step_id].advisory ~= true) then
        -- An advisory carries the same sentence but is NOT a refusal: reporting
        -- it here would block the route through the back door.
        return blocks[native_key][step_id];
    end
    local refusals = source_derivation_cache.source_route_refusals;
    if (type(refusals) ~= 'table') then
        return nil;
    end
    local per_key = refusals[native_key];
    if (type(per_key) ~= 'table') then
        return nil;
    end
    return per_key[step_id];
end

local NATION_DISTRICT_ZONES = {
    ["san d'oria"] = { 230, 231, 232 },
    ["sandoria"] = { 230, 231, 232 },
    ["san d'oria (s)"] = { 80 },
    ["bastok"] = { 234, 235, 236 },
    ["bastok (s)"] = { 87 },
    ["windurst"] = { 238, 239, 240, 241 },
    ["windurst (s)"] = { 94 },
};

-- The zones a nation mission may assume without being told: the ordinary
-- districts plus the palace. Keyed by the native key's nation ("mission:San
-- d'Oria:5"); anything else gets no group.
local NATION_ZONE_GROUPS = {
    ["san d'oria"] = { 230, 231, 232, 233 },
    ["bastok"] = { 234, 235, 236, 237 },
    ["windurst"] = { 238, 239, 240, 241, 242 },
};

function accessxi.nav_nation_zone_group(native_key)
    local context = clean(native_key):match('^[a-z]+:([^:]+):');
    local group = context ~= nil and NATION_ZONE_GROUPS[source_name_key(context)] or nil;
    if (group == nil) then
        return nil;
    end
    return deep_copy(group);
end

-- Which nation a zone belongs to, or '' for anywhere that is not a city
-- district. Built once from NATION_DISTRICT_ZONES, which is already the
-- authoritative grouping.
local NATION_BY_ZONE = nil;

-- THE GUIDE DOES NOT ALWAYS NAME THE TARGET.
--
-- "Journey Abroad" says "visit your nation's embassies" and never names anyone.
-- The step could therefore only degrade to "go to this nation", which is how the
-- player ended up cycling city entrances in Bastok saying "I still haven't even
-- talked to the npc I need to talk to here."
--
-- A binding says which CATALOGUED place the guide meant. It never invents a
-- place: the name must already exist in ffxi-nav-destinations.tsv, and every row
-- carries its evidence.
local STEP_TARGET_BINDINGS = nil;

function accessxi.nav_step_target_binding(step_id)
    step_id = clean(step_id);
    if (step_id == '') then return nil; end
    if (STEP_TARGET_BINDINGS == nil) then
        STEP_TARGET_BINDINGS = {};
        local path = accessxi_paths.addon_path('data', 'ffxi-objective-step-targets.tsv');
        local handle = io.open(path, 'r');
        if (handle ~= nil) then
            for line in handle:lines() do
                if (line ~= nil and line ~= '' and line:sub(1, 1) ~= '#') then
                    local fields = {};
                    for field in (line .. '\t'):gmatch('([^\t]*)\t') do
                        fields[#fields + 1] = field;
                    end
                    local id = clean(fields[1] or '');
                    local zone = tonumber(fields[2]) or 0;
                    local target = clean(fields[3] or '');
                    if (id ~= '' and zone > 0 and target ~= '') then
                        STEP_TARGET_BINDINGS[id] = {
                            zone = zone,
                            target = target,
                            source = clean(fields[4] or ''),
                            note = clean(fields[5] or ''),
                            destination_id = clean(fields[6] or ''),
                        };
                    end
                end
            end
            handle:close();
        end
    end
    local row = STEP_TARGET_BINDINGS[step_id];
    if (row == nil) then return nil; end
    return { zone = row.zone, target = row.target, source = row.source, note = row.note,
        destination_id = row.destination_id };
end

function accessxi.nav_nation_of_zone(zone)
    zone = tonumber(zone) or 0;
    if (zone <= 0) then return ''; end
    if (NATION_BY_ZONE == nil) then
        NATION_BY_ZONE = {};
        for name, ids in pairs(NATION_DISTRICT_ZONES) do
            -- Skip the past-era aliases: "san d'oria (s)" is a different place
            -- from "san d'oria" and must never merge with it.
            if (name:find('(s)', 1, true) == nil) then
                for _, id in ipairs(ids) do
                    NATION_BY_ZONE[id] = NATION_BY_ZONE[id] or name;
                end
            end
        end
    end
    return NATION_BY_ZONE[zone] or '';
end

function accessxi.nav_nation_district_zones(value)
    local ids = NATION_DISTRICT_ZONES[source_name_key(value)];
    if (ids == nil) then
        return nil;
    end
    return deep_copy(ids);
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
    -- A REVIEWED OVERRIDE REPLACES A COLLAPSED PAGE.
    --
    -- Eight pages in the scraped corpus collapse two or more genuinely
    -- different missions through wiki redirects -- "Journey Abroad" carries
    -- "Journey to Bastok" and "Journey to Windurst" as aliases, so five native
    -- ids share one set of fifteen steps. Where that has been reviewed and the
    -- real sequence written down, it wins outright: binding correct targets onto
    -- the collapsed text would route the player to Pius while reading them
    -- "Halver will instruct you to visit two other Nations".
    local override_steps = accessxi.mission_quest_override_steps(clean(native_key));
    if (type(override_steps) == 'table' and #override_steps > 0) then
        local overridden = T{};
        for _, entry in ipairs(override_steps) do
            if (type(entry) == 'table') then overridden:append(deep_copy(entry)); end
        end
        source_derivation_cache.source_steps[native_key] = overridden;
        return overridden, true;
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
    accessxi.objective_roll_up_child_targets(result);
    local searches = accessxi.mission_quest_search_steps;
    if (type(searches) == 'table') then
        local catalog = ensure_catalog_index();
        result = searches.normalize_steps(result, function(zone,name)
            return catalog.points_by_zone_entity[('%d\t%s'):fmt(zone,source_name_key(name))] or {};
        end, function(name)
            local zones = catalog.zone_ids_by_name[source_name_key(name)] or {};
            local found = {};
            for zone in pairs(zones) do
                found[#found+1] = tonumber(zone);
            end
            return found;
        end);
        for _,step in ipairs(result) do
            if (type(step.search_refusal) == 'table') then
                log_line(('objective search refused native="%s" step="%s" reason="%s" detail="%s"'):fmt(
                    clean(native_key), clean(step.stable_step_id),
                    clean(step.search_refusal.reason), clean(step.search_refusal.detail)));
            end
        end
    end
    source_derivation_cache.source_steps[native_key] = result;
    return result, true;
end;

local current_objective_progress;
local nation_mission_acceptance_step;

function progression_revision(native_key)
    local entry = type(accessxi.mission_quest_guide_index) == 'table'
        and accessxi.mission_quest_guide_index[clean(native_key)] or nil;
    return clean(type(entry) == 'table' and entry.progression_revision or '');
end

function progression_actions(native_key)
    native_key = clean(native_key);
    if (native_key == '' or type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.progression_actions) ~= 'function') then
        return nil, '';
    end

    -- THE CURSOR RUNS ON ACTIONS, NOT ON STEPS.
    --
    -- Overriding the reconciled STEPS for a collapsed mission is only half the
    -- job: the progression cursor walks the compact ACTIONS, and those were
    -- still the ones cloned from "Journey Abroad" -- step-003 Halver, step-004,
    -- step-007, step-008. Live 2026-08-25 the cursor sat on "step-004", which in
    -- the OVERRIDE happens to be "trade the gravel to the Refiner Lid", so the
    -- player was sent straight there and never taken to Grohm for the pickaxes.
    -- A step id that means two different things in two different tables is worse
    -- than no override at all.
    --
    -- So an overridden mission derives its actions from its OWN steps, one per
    -- step, in order. The revision is namespaced so a cursor saved against the
    -- cloned data cannot be mistaken for one saved against these.
    local override_steps, override_source = accessxi.mission_quest_override_steps(native_key);
    if (type(override_steps) == 'table' and #override_steps > 0) then
        local built = T{};
        for index, entry in ipairs(override_steps) do
            local step_id = clean(entry.stable_step_id);
            local entities = type(entry.entities) == 'table' and entry.entities or {};

            -- SPEAK THE CORPUS'S OWN VOCABULARY, NOT AN INVENTED ONE.
            --
            -- This builder used to emit relationship = action .. '-target', so
            -- 'fight-target', 'talk-target', 'obtain-target'. None of those
            -- strings exists anywhere in the shipped corpus, where all 633 fight
            -- actions say 'defeat-enemy' and all 652 obtain actions say
            -- 'obtain-item'. Two completion paths test that field exactly --
            -- the kill-credit reducer wants a relationship containing 'defeat'
            -- and the inventory reducer wants exactly 'obtain-item' -- so every
            -- overridden fight and obtain step was structurally unable to
            -- complete. Live 2026-08-26 the player killed the Black Dragon and
            -- the Searcher and had to press N.
            --
            -- The typed lists matter for the same reason: enemy matching tests
            -- action.enemies, and an empty list means a second named target --
            -- the Searcher beside the Black Dragon -- can never be recognised.
            -- The entity list also carries the step's ZONE as its last element,
            -- which is a place and not a target, so it is filtered out here.
            local action_name = clean(entry.action):lower();
            local RELATIONSHIP = {
                talk = 'talk-to', trade = 'trade-to', examine = 'examine-object',
                fight = 'defeat-enemy', obtain = 'obtain-item', travel = 'travel-to',
                use = 'use-object', select = 'menu-choice', wait = 'wait-for',
                protect = 'protect-role',
            };
            local TARGET_KIND = {
                talk = 'npc', trade = 'npc', examine = 'object', fight = 'enemy',
                obtain = 'item', travel = 'zone', use = 'object',
            };
            local relationship = clean(entry.relationship) ~= ''
                and clean(entry.relationship) or (RELATIONSHIP[action_name] or action_name);
            local target_kind = clean(entry.target_kind) ~= ''
                and clean(entry.target_kind) or (TARGET_KIND[action_name] or '');

            local zone_keys = {};
            for _, zone in ipairs(type(entry.zones) == 'table' and entry.zones or {}) do
                zone_keys[source_name_key(zone)] = true;
            end
            local targets = {};
            for _, name in ipairs(entities) do
                if (clean(name) ~= '' and zone_keys[source_name_key(name)] ~= true) then
                    targets[#targets + 1] = clean(name);
                end
            end
            if (#targets == 0 and clean(entities[1] or '') ~= '') then
                targets[1] = clean(entities[1]);
            end

            local typed = { npcs = {}, objects = {}, enemies = {}, items = {} };
            local bucket = (target_kind == 'npc' and typed.npcs)
                or (target_kind == 'object' and typed.objects)
                or (target_kind == 'enemy' and typed.enemies)
                or (target_kind == 'item' and typed.items) or nil;
            if (bucket ~= nil) then
                for _, name in ipairs(targets) do bucket[#bucket + 1] = name; end
            end

            -- 'credited-defeat' IS ONLY LEGAL ABOVE A COUNT OF ONE.
            --
            -- mission_quest_guides.lua:133-137 rejects the pair outright:
            -- credited-defeat demands count_explicit and required_count > 1.
            -- A single-enemy fight is 'single' with a count of one, which is
            -- what 551 of the corpus's 633 fight actions use.
            --
            -- For two enemies this asks for two credited defeats, which is
            -- schema-legal but weaker than it looks: the count cannot tell one
            -- enemy from another, so two deaths of the SAME name would satisfy
            -- it, and a kill before a wipe could combine with a kill in a later
            -- attempt. The honest model is a set of distinct required targets --
            -- exactly what distinct_inventory_set_count already does for items,
            -- where "a counted action whose required count equals its distinct
            -- item list represents a collective set, not interchangeable
            -- copies". Defeats have no equivalent yet, and the journal stores a
            -- scalar rather than which members are proven, so this is not
            -- something to bolt on here. What makes the gap safe meanwhile is
            -- the step that follows: the battlefield's reward key item cannot
            -- arrive unless every essential mob really died, so a fight step
            -- that advances early is caught before the player is told to leave.
            local required_count, count_mode = 1, 'single';
            if (action_name == 'fight' and #typed.enemies > 1) then
                required_count = #typed.enemies;
                count_mode = 'credited-defeat';
            end
            built:append(T{
                step_id = step_id,
                step_order = index,
                action_id = step_id .. ':claim-01',
                action_order = 1,
                order = index,
                action = action_name,
                relationship = relationship,
                target = clean(targets[1] or ''),
                target_key = source_name_key(targets[1] or ''),
                target_kind = target_kind,
                npcs = typed.npcs, objects = typed.objects,
                enemies = typed.enemies, items = typed.items,
                key_items = {}, transports = {},
                zones = type(entry.zones) == 'table' and entry.zones or {},
                destination_zone_name = '',
                destination_zone_id = 0,
                grid_coordinates = {},
                result_items = {}, result_relation = '',
                instruction = clean(entry.bg_instruction),
                required_count = required_count,
                count_mode = count_mode,
                count_explicit = required_count > 1,
                completion_evidence = clean(entry.completion_evidence),
                material = true,
                source_authority = 'reviewed-override',
                field_sources = {},
                source_revisions = {},
                source_action_span_ids = {},
                catalogue = {},
            });
        end
        return built, 'override:' .. clean(override_source);
    end

    local revision = progression_revision(native_key);
    if (revision == '') then return nil, ''; end
    local ok, rows = pcall(
        accessxi.objective_guides.progression_actions,
        accessxi.objective_guides,
        native_key);
    if (not ok or type(rows) ~= 'table') then
        return nil, revision;
    end
    if (#rows == 0) then return T{}, revision; end
    local actions = T{};
    for _, row in ipairs(rows) do
        if (type(row) ~= 'table' or clean(row.step_id) == ''
            or (tonumber(row.step_order) or 0) < 1 or clean(row.action_id) == ''
            or (tonumber(row.action_order) or 0) < 1
            or (tonumber(row.required_count) or 0) < 1
            or clean(row.count_mode) == '') then
            return nil, revision;
        end
        actions:append(deep_copy(row));
    end
    table.sort(actions, function(left, right)
        local left_order = tonumber(left.order) or 0;
        local right_order = tonumber(right.order) or 0;
        if (left_order ~= right_order) then return left_order < right_order; end
        if (tonumber(left.step_order) ~= tonumber(right.step_order)) then
            return (tonumber(left.step_order) or 0) < (tonumber(right.step_order) or 0);
        end
        return (tonumber(left.action_order) or 0) < (tonumber(right.action_order) or 0);
    end);
    local searches = accessxi.mission_quest_search_steps;
    if (type(searches) == 'table') then
        local normalized = objective_source_steps(native_key);
        actions = searches.augment_actions(actions, normalized);
        for _,action in ipairs(actions) do
            if (type(action.search_set) == 'table') then
                revision = revision .. ':search-v1';
                break;
            end
        end
    end
    return actions, revision;
end

local function action_index_by_identity(actions, step_id, step_order, action_id, action_order)
    for index, action in ipairs(type(actions) == 'table' and actions or T{}) do
        if (clean(action.step_id) == clean(step_id)
            and tonumber(action.step_order) == tonumber(step_order)
            and clean(action.action_id) == clean(action_id)
            and tonumber(action.action_order) == tonumber(action_order)) then
            return index;
        end
    end
    return nil;
end

local function action_index_by_stable_identity(actions, step_id, action_id)
    local result = nil;
    for index, action in ipairs(type(actions) == 'table' and actions or T{}) do
        if (clean(action.step_id) == clean(step_id)
            and clean(action.action_id) == clean(action_id)) then
            if (result ~= nil) then return nil; end
            result = index;
        end
    end
    return result;
end

local function progress_count_is_valid(record, action, index, action_count)
    local count = tonumber(type(record) == 'table' and record.progress_count or nil);
    local required = tonumber(type(action) == 'table' and action.required_count or nil) or 0;
    return count ~= nil and count >= 0 and count == math.floor(count)
        and count <= required and not (count == required and index < action_count);
end

local function valid_progress_record(record, actions, revision)
    if (type(record) ~= 'table' or record.version ~= 'v2'
        or clean(record.identity) == '' or (tonumber(record.world_id) or 0) <= 0
        or clean(record.native_key) == ''
        or clean(record.progression_revision) ~= clean(revision)
        or clean(record.step_id) == '' or clean(record.action_id) == ''
        or tonumber(record.step_order) == nil or tonumber(record.action_order) == nil
        or tonumber(record.progress_count) == nil
        or record.raw_step_order ~= nil
            and record.raw_step_order ~= tostring(tonumber(record.step_order))
        or record.raw_action_order ~= nil
            and record.raw_action_order ~= tostring(tonumber(record.action_order))
        or record.raw_progress_count ~= nil
            and record.raw_progress_count ~= tostring(tonumber(record.progress_count))) then
        return nil;
    end
    local index = action_index_by_identity(
        actions, record.step_id, record.step_order, record.action_id, record.action_order);
    local action = index ~= nil and actions[index] or nil;
    if (index == nil or not progress_count_is_valid(record, action, index, #actions)) then
        return nil;
    end
    local result = deep_copy(record);
    result.index = index;
    return result;
end

-- A CURSOR MUST NOT CROSS AN OVERRIDE BOUNDARY.
--
-- This function carries a saved cursor onto a NEW revision by matching step_id
-- and action_id as strings (see action_index_by_stable_identity below). That is
-- right when a guide page is merely re-scraped and the steps keep their
-- meaning. It is catastrophic when the step LIST was replaced: live 2026-08-25
-- the player's cursor sat on the collapsed "Journey Abroad" page's step-004,
-- "Halver will instruct you to visit two other Nations". The reviewed override
-- for Journey to Bastok happened to name its own fourth step step-004 as well,
-- so the cursor migrated onto "trade the gravel to the Refiner Lid" and the
-- addon skipped Pius, Grohm and the Mythril Seam. The player found Pius by
-- typing /axi zonesearch themselves.
--
-- Reviewed override ids are namespaced now, so the strings can no longer
-- collide. This is the second lock: an override revision names a DIFFERENT
-- SEQUENCE, not a newer rendering of the same one, so no position in one is a
-- position in the other. Reset to the start and let progress detection catch
-- up -- a cursor that is merely behind speaks a step you have already done,
-- while one that is ahead silently swallows the steps in between.
local function progression_revision_is_override(revision)
    return clean(revision):sub(1, 9) == 'override:';
end

local function mapped_previous_progress_record(
    record, actions, revision, identity, world_id, native_key)
    local step_order = tonumber(type(record) == 'table' and record.step_order or nil);
    local action_order = tonumber(type(record) == 'table' and record.action_order or nil);
    if (progression_revision_is_override(revision)
        or progression_revision_is_override(
            type(record) == 'table' and record.progression_revision or '')) then
        return nil;
    end
    if (type(record) ~= 'table' or record.version ~= 'v2'
        or clean(record.identity) == '' or (tonumber(record.world_id) or 0) <= 0
        or clean(record.native_key) == '' or clean(record.progression_revision) == ''
        or clean(record.identity):lower() ~= clean(identity):lower()
        or tonumber(record.world_id) ~= tonumber(world_id)
        or clean(record.native_key) ~= clean(native_key)
        or clean(record.progression_revision) == clean(revision)
        or clean(record.step_id) == '' or clean(record.action_id) == ''
        or step_order == nil or step_order < 1 or step_order ~= math.floor(step_order)
        or action_order == nil or action_order < 1 or action_order ~= math.floor(action_order)
        or tonumber(record.progress_count) == nil
        or record.raw_step_order ~= nil
            and record.raw_step_order ~= tostring(step_order)
        or record.raw_action_order ~= nil
            and record.raw_action_order ~= tostring(action_order)
        or record.raw_progress_count ~= nil
            and record.raw_progress_count ~= tostring(tonumber(record.progress_count))) then
        return nil;
    end
    local index = action_index_by_stable_identity(actions, record.step_id, record.action_id);
    local action = index ~= nil and actions[index] or nil;
    if (index == nil or not progress_count_is_valid(record, action, index, #actions)) then
        return nil;
    end
    return {
        version = 'v2',
        identity = clean(record.identity):lower(),
        world_id = tonumber(record.world_id),
        native_key = clean(record.native_key),
        progression_revision = clean(revision),
        -- Where it came FROM, so the log line can name both ends. Not written
        -- to the file; save_cursor_action only reads the fields above.
        source_revision = clean(record.progression_revision),
        step_id = clean(action.step_id),
        step_order = tonumber(action.step_order),
        action_id = clean(action.action_id),
        action_order = tonumber(action.action_order),
        progress_count = tonumber(record.progress_count),
        index = index,
    };
end

-- WHICH ZONES SATISFY THIS TRAVEL STEP.
--
-- Every zone the guide named for it, not merely the one that survived
-- extraction into a single field. Live 2026-08-22 the player was stuck on
-- "mission:Rhapsodies of Vana'diel:3:step-001", "Zone into any area connecting
-- to a Mog House in San d'Oria, Windurst, or Bastok", which carries
-- `zones = {}` and `destination_zone_id = 0` -- so the completion test compared
-- the zone they entered against 0 and never matched, however many times they
-- zoned. 1,563 of the 2,940 travel-shaped actions in the shipped modules --
-- 53.2% -- have no single destination id and could never complete this way.
--
-- The next step is the same bug wearing a different hat: step-002 says "zone
-- into Mhaura or Selbina" and carries `destination_zone_id = 249`, Mhaura. Walk
-- into Selbina, as the guide expressly permits, and nothing happens.
--
-- Three sources, all of them the guide's own words for THIS step: the single
-- extracted id, every zone name written on the step, and the destinations the
-- router resolved for it while the player was still travelling.
function accessxi.nav_objective_travel_destination_zones(native_key, action)
    local zones = {};
    if (type(action) ~= 'table') then return zones; end
    local single = tonumber(action.destination_zone_id) or 0;
    if (single > 0) then zones[single] = true; end
    local index = ensure_catalog_index ~= nil and ensure_catalog_index() or nil;
    if (type(index) == 'table' and type(index.zone_ids_by_name) == 'table') then
        for _, name in ipairs(type(action.zones) == 'table' and action.zones or T{}) do
            local set = index.zone_ids_by_name[source_name_key(name)];
            if (type(set) == 'table') then
                for zone in pairs(set) do
                    if ((tonumber(zone) or 0) > 0) then zones[tonumber(zone)] = true; end
                end
            end
        end
    end
    -- AN ENTRANCE NAMES ITS ZONE IN target, AND NOWHERE ELSE.
    --
    -- This merged three sources -- destination_zone_id, zones, and the recorded
    -- per-step table -- and never looked at action.target. For an enter-through
    -- action the target IS the place:
    --
    --   mission:Chains of Promathia:3:step-009
    --     action=travel relationship=enter-through target_kind=entrance
    --     target="Hall of Transference"
    --     destination_zone_id=0  destination_zone_name=""  zones={}
    --
    -- so it accepted NO zone and could never complete however many times the
    -- player walked in. Live 2026-08-29 they entered the Hall, went on into
    -- Promyvion, and the mission did not move: "the mission didn't update".
    --
    -- Eleven actions in the whole corpus are in this state, ten after excluding
    -- the transport below -- 0.4% of travel actions. Small, but it is the only
    -- thing standing between this step and completing, and the same two words
    -- block Chains of Promathia 4 next.
    --
    -- Transport relationships are excluded deliberately. quest:outlands:200
    -- step-007 is board-transport target="Manaclipper", and Manaclipper happens
    -- to collide with a zone name -- boarding a boat is not arriving anywhere,
    -- and completing that step on a zone change would be wrong.
    local relationship = clean(action.relationship):lower();
    if (relationship ~= 'use-transport' and relationship ~= 'board-transport'
        and clean(action.target) ~= ''
        and type(accessxi.nav_zone_id_for_name) == 'function') then
        local ok_target, id = pcall(accessxi.nav_zone_id_for_name, clean(action.target));
        id = ok_target and (tonumber(id) or 0) or 0;
        if (id > 0) then zones[id] = true; end
    end

    local per_key = type(accessxi.nav_objective_travel_zones) == 'table'
        and accessxi.nav_objective_travel_zones[clean(native_key)] or nil;
    local recorded = type(per_key) == 'table' and per_key[clean(action.step_id)] or nil;
    if (type(recorded) == 'table' and type(recorded.zones) == 'table'
        and clean(recorded.revision) == clean(progression_revision(native_key))) then
        for zone in pairs(recorded.zones) do
            if ((tonumber(zone) or 0) > 0) then zones[tonumber(zone)] = true; end
        end
    end
    return zones;
end

local function save_cursor_action(native_key, action, progress_count, revision)
    if (type(action) ~= 'table') then return false; end
    return save_objective_progress({
        identity = character_identity(),
        world_id = player_world_id(),
        native_key = clean(native_key),
        progression_revision = clean(revision),
        step_id = clean(action.step_id),
        step_order = tonumber(action.step_order),
        action_id = clean(action.action_id),
        action_order = tonumber(action.action_order),
        progress_count = tonumber(progress_count) or 0,
    });
end

local function legacy_owner_name(identity)
    local name, suffix = clean(identity):lower():match('^([^:]+):([1-9]%d*)$');
    if (name == nil or tonumber(suffix) == nil) then return ''; end
    return clean(name):lower();
end

local function resolved_legacy_progress(native_key)
    local identity = character_identity();
    native_key = clean(native_key);
    local exact = objective_progress_legacy[identity .. '\t' .. native_key];
    if (type(exact) == 'table') then
        if (exact.tombstoned == true) then return nil; end
        return exact;
    end

    local owner_name = legacy_owner_name(identity);
    if (owner_name == '') then return nil; end
    local result = nil;
    for _, candidate in pairs(objective_progress_legacy) do
        if (type(candidate) == 'table' and candidate.tombstoned ~= true
            and clean(candidate.native_key) == native_key
            and legacy_owner_name(candidate.identity) == owner_name) then
            if (result ~= nil) then return nil; end
            result = candidate;
        end
    end
    return result;
end

local function mapped_legacy_progress_record(native_key, actions, revision)
    local legacy = resolved_legacy_progress(native_key);
    if (type(legacy) ~= 'table' or #actions == 0) then return nil; end
    local first, last, matches = nil, nil, 0;
    for index, action in ipairs(actions) do
        if (clean(action.step_id) == clean(legacy.step_id)
            and tonumber(action.step_order) == tonumber(legacy.order)) then
            first = first or index;
            last = index;
            matches = matches + 1;
        end
    end
    if (last == nil) then return nil; end
    -- A legacy step flag cannot prove completion of multiple material actions.
    -- Resume an ambiguous step at its first action instead of skipping them all.
    local target_index = matches > 1 and first or (last + 1);
    local progress_count = 0;
    if (target_index > #actions) then
        target_index = #actions;
        progress_count = tonumber(actions[target_index].required_count) or 1;
    end
    local action = actions[target_index];
    return {
        version = 'v2',
        identity = character_identity(),
        world_id = player_world_id(),
        native_key = clean(native_key),
        progression_revision = clean(revision),
        step_id = clean(action.step_id),
        step_order = tonumber(action.step_order),
        action_id = clean(action.action_id),
        action_order = tonumber(action.action_order),
        progress_count = progress_count,
        index = target_index,
    };
end

local function progress_record_is_farther(candidate, current)
    if (type(candidate) ~= 'table') then return false; end
    if (type(current) ~= 'table') then return true; end
    local candidate_index = tonumber(candidate.index) or 0;
    local current_index = tonumber(current.index) or 0;
    if (candidate_index ~= current_index) then return candidate_index > current_index; end
    return (tonumber(candidate.progress_count) or 0)
        > (tonumber(current.progress_count) or 0);
end

local function resolved_progress_record(native_key, actions, revision)
    load_objective_progress();
    local identity = character_identity();
    local world_id = player_world_id();
    if (identity == '' or world_id <= 0) then return nil; end
    local key = objective_progress_key(identity, world_id, native_key);
    local current = nil;
    local migration = nil;
    for _, candidate in ipairs(objective_progress_history[key] or {}) do
        local valid = valid_progress_record(candidate, actions, revision);
        if (progress_record_is_farther(valid, current)) then current = valid; end
        local previous = mapped_previous_progress_record(
            candidate, actions, revision, identity, world_id, native_key);
        if (progress_record_is_farther(previous, migration)) then migration = previous; end
    end
    local legacy = mapped_legacy_progress_record(native_key, actions, revision);
    if (progress_record_is_farther(legacy, migration)) then migration = legacy; end

    objective_progress[key] = current;
    if (progress_record_is_farther(migration, current)) then
        local index = tonumber(migration.index) or 0;
        if (index > 0 and type(actions[index]) == 'table'
            and save_cursor_action(
                native_key, actions[index], migration.progress_count, revision)) then
            -- SAY WHEN A CURSOR MOVES ON ITS OWN.
            --
            -- Of every writer that can put a row in the progress file this is
            -- the only one that fires without the player doing anything, and
            -- until now it was also the only one that said nothing. Live
            -- 2026-08-25 it silently advanced Journey to Bastok to step-004 and
            -- the player was sent to Palborough Mines having never met Pius;
            -- the log recorded two progression events for that mission, both
            -- under the old revision, and a third row that no event explains.
            -- A move nobody can see is a move nobody can debug.
            if (type(log_line) == 'function') then
                log_line(('objective cursor MIGRATED native="%s" step="%s" index=%d count=%d from-revision="%s" to-revision="%s"'):fmt(
                    clean(native_key),
                    clean(actions[index].step_id),
                    index,
                    tonumber(migration.progress_count) or 0,
                    clean(migration.source_revision),
                    clean(revision)));
            end
            local saved = objective_progress[key];
            if (type(saved) == 'table') then saved.index = index; end
            return saved;
        end
    end
    return current;
end

local function initial_progression_index(native_key, actions, item)
    local automatic_step = '';
    if (type(item) == 'table' and clean(item.objective_stage) ~= ''
        and type(accessxi.objective_guides) == 'table'
        and type(accessxi.objective_guides.automatic_step_id) == 'function') then
        local ok, step_id = pcall(
            accessxi.objective_guides.automatic_step_id,
            accessxi.objective_guides,
            native_key,
            clean(item.objective_stage));
        if (ok) then automatic_step = clean(step_id); end
    end
    if (automatic_step ~= '') then
        for index, action in ipairs(actions) do
            if (clean(action.step_id) == automatic_step) then return index; end
        end
    end
    if (type(item) == 'table' and clean(item.objective_kind or item.kind):lower() == 'mission'
        and clean(item.mission_availability) == 'active') then
        local acceptance = nation_mission_acceptance_step(native_key);
        local acceptance_order = tonumber(type(acceptance) == 'table'
            and acceptance.order or nil) or 0;
        if (acceptance_order > 0) then
            -- BY ORDER, NOT BY ID.
            --
            -- Matching the acceptance step's id among the ACTIONS assumes that
            -- step owns one, and the whole reason this branch was unreachable is
            -- that it usually does not. Worse, in 32 of the 34 affected missions
            -- BG fuses the precondition and the acceptance into ONE step, so an
            -- id match cannot separate "unlock it" from "accept it" even when
            -- there is an action to match.
            --
            -- The order can. Anything ordered at or before acceptance happened
            -- before the mission existed, and the game saying the mission is
            -- active is proof it is done.
            for index, action in ipairs(actions) do
                if ((tonumber(action.step_order) or 0) > acceptance_order) then
                    return index;
                end
            end
        end
    end
    return 1;
end

-- ADVANCE ONE STEP ON THE GAME'S OWN SAY-SO.
--
-- Called when a storyline's progress counter rises while the mission stays the
-- same. The server does not move that counter for nothing, so the step the
-- cursor is sitting on is finished, whether or not we managed to observe the
-- thing that finished it. Cutscenes are the common case: they complete steps
-- and emit no signal this addon can see.
--
-- Exactly one step per rise. The counter reports that something happened, not
-- how much, and a cursor that overshoots silently swallows steps the player
-- still has to do -- strictly worse than one that lags, since a lagging cursor
-- only repeats an instruction they have already followed.
function accessxi.nav_mission_quest_advance_within_mission(native_key, reason)
    native_key = clean(native_key);
    if (native_key == '') then
        return false;
    end
    local actions, revision = progression_actions(native_key);
    if (type(actions) ~= 'table' or #actions == 0) then
        return false;
    end
    local record = resolved_progress_record(native_key, actions, revision);
    local index = tonumber(type(record) == 'table' and record.index or nil) or 1;
    if (index >= #actions) then
        log_line(('objective progress advance declined native="%s" reason="%s" -- already at the last step'):fmt(
            native_key, tostring(reason or '')));
        return false;
    end
    local next_action = actions[index + 1];
    if (type(next_action) ~= 'table') then
        return false;
    end
    if (not save_cursor_action(native_key, next_action, 0, revision)) then
        return false;
    end
    log_line(('objective progress ADVANCED native="%s" %d -> %d step="%s" reason="%s"'):fmt(
        native_key, index, index + 1, clean(next_action.step_id), tostring(reason or '')));

    -- CATCH UP ON EVIDENCE ALREADY SEEN.
    --
    -- One step per counter rise is the right default -- the counter says
    -- something finished, not how much -- but it under-shoots when the player
    -- did two things between two samples. Live 2026-08-29 the counter went
    -- 118 -> 120 across examining the Shattered Telepoint AND entering the Hall
    -- of Transference, and the cursor landed one behind.
    --
    -- Where the step the cursor NOW sits on is a travel into somewhere the
    -- player has already been this session, that is not a guess: the arrival
    -- was observed, it was simply tested against the wrong action at the time.
    -- Only travel steps, only zones actually visited, and bounded -- an
    -- unbounded catch-up is how a cursor runs away and swallows steps.
    local caught = 0;
    while (caught < 4) do
        local record_now = resolved_progress_record(native_key, actions, revision);
        local at = tonumber(type(record_now) == 'table' and record_now.index or nil) or 1;
        local current = actions[at];
        if (type(current) ~= 'table' or at >= #actions) then break; end
        if (clean(current.action):lower() ~= 'travel'
            or clean(current.relationship):lower() == 'use-transport'
            or clean(current.relationship):lower() == 'board-transport') then
            break;
        end
        local visited = type(accessxi.objective_zones_visited) == 'table'
            and accessxi.objective_zones_visited or {};
        local accepted = accessxi.nav_objective_travel_destination_zones(native_key, current);
        local satisfied = false;
        for zone in pairs(type(accepted) == 'table' and accepted or {}) do
            if (visited[tonumber(zone) or 0] ~= nil) then satisfied = true; end
        end
        if (not satisfied) then break; end
        local follow = actions[at + 1];
        if (type(follow) ~= 'table' or not save_cursor_action(native_key, follow, 0, revision)) then
            break;
        end
        caught = caught + 1;
        log_line(('objective progress CAUGHT UP native="%s" %d -> %d step="%s" -- already arrived'):fmt(
            native_key, at, at + 1, clean(follow.step_id)));
    end
    return true;
end

-- FOUR STATES, AND THREE OF THEM USED TO LOOK IDENTICAL.
--
-- This returned a nil action for two completely different reasons -- the cursor
-- finished, or the saved index does not name an action in this list -- and the
-- caller could not tell either from "there is no progression data at all". All
-- three fell into the whole-mission fallback, which recites finished steps.
--
--   unavailable  no compact actions exist. The only view is the whole guide,
--                and the legacy fallback is right.
--   exhausted    the last action is complete on its own terminal proof. The
--                guide may still have plenty to say; a postlude says it.
--   invalid      an action list exists but the index does not name a row in it.
--                Neither a dump nor a postlude: both would walk the player past
--                whatever they are actually on (sol).
--   active       the ordinary case.
local function progression_cursor(native_key, item)
    local actions, revision = progression_actions(native_key);
    if (type(actions) ~= 'table' or #actions == 0) then
        return nil, nil, revision, nil, 'unavailable';
    end
    local record = resolved_progress_record(native_key, actions, revision);
    local index = tonumber(type(record) == 'table' and record.index or nil)
        or initial_progression_index(native_key, actions, item);
    local action = actions[index];
    if (type(action) == 'table' and index == #actions
        and type(record) == 'table'
        and tonumber(record.progress_count) == tonumber(action.required_count)) then
        return nil, actions, revision, record, 'exhausted';
    end
    if (type(action) ~= 'table') then
        if (type(log_line) == 'function') then
            log_line(('objective cursor INVALID native="%s" index=%s actions=%d saved-step="%s" saved-action="%s" saved-revision="%s" guide-revision="%s"'):fmt(
                clean(native_key), tostring(index), #actions,
                clean(type(record) == 'table' and record.step_id or ''),
                clean(type(record) == 'table' and record.action_id or ''),
                clean(type(record) == 'table' and record.progression_revision or ''),
                clean(revision)));
        end
        return nil, actions, revision, record, 'invalid';
    end
    return action, actions, revision, record, 'active';
end

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

-- THE ACCEPTANCE STEP IS USUALLY PROSE, NOT A TALK.
--
-- This required action == 'talk', and nation-mission acceptance steps are
-- written as prose -- "Accept the mission Infiltrate Davoi from the Gate Guard."
-- carries action = 'note'. So it returned nil for 55 of 72 nation missions, and
-- initial_progression_index, which uses this to start an active mission AFTER
-- acceptance, fell back to index 1 instead: the step that UNLOCKS the mission.
-- Live 2026-08-29 that parked Infiltrate Davoi on "Trade enough Crystals to the
-- Conquest NPC" -- a precondition the game had already proved satisfied -- and
-- it sat there for two days refusing, because no catalogue has a Conquest NPC.
--
-- Strict first, so nothing that resolves today changes. The relaxed pass takes
-- the LAST match rather than the first: mission:Windurst:17 has an earlier
-- 'travel' step reading "Go to any Windurst Gate Guard to start the mission",
-- which is acceptance-shaped wording on a step that is not the acceptance, and
-- taking the first would have moved that cursor onto the rank trade -- the same
-- defect wearing a different face.
nation_mission_acceptance_step = function(native_key)
    local steps = objective_source_steps(native_key);
    for _, step in ipairs(steps) do
        local action = clean(step.action):lower();
        if (action == 'talk' and exact_gate_guard_role(step)
            and mission_acceptance_instruction(step)) then
            return step;
        end
    end
    local relaxed = nil;
    for _, step in ipairs(steps) do
        local action = clean(step.action):lower();
        -- 'travel' excluded: "go to a Gate Guard to start the mission" is the
        -- journey to acceptance, not the acceptance.
        if (action ~= 'travel' and exact_gate_guard_role(step)
            and mission_acceptance_instruction(step)) then
            relaxed = step;
        end
    end
    return relaxed;
end;

current_objective_progress = function(native_key)
    local actions, revision = progression_actions(native_key);
    if (type(actions) ~= 'table') then return nil; end
    local record = resolved_progress_record(native_key, actions, revision);
    if (type(record) == 'table') then
        record.order = tonumber(record.step_order) or 0;
    end
    return record;
end;

local function ensure_active_nation_mission_acceptance(native_key)
    local step = nation_mission_acceptance_step(native_key);
    local step_id = clean(type(step) == 'table' and step.stable_step_id or '');
    local order = tonumber(type(step) == 'table' and step.order or nil) or 0;
    -- The current native mission slot itself proves acceptance.  The initial
    -- in-memory cursor starts immediately after this step, but viewing an
    -- active mission must not mutate the append-only progression history.
    return step_id ~= '' and order > 0;
end

local objective_step_by_id;
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
    local resolver = accessxi.mission_step_resolver;
    source_derivation_cache.prerequisite_refusals = source_derivation_cache.prerequisite_refusals or {};
    source_derivation_cache.prerequisite_refusals[native_key] = {};
    local actions = nil;
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
                -- A PREREQUISITE IS SOMETHING TO SAY, NOT A WALL.
                --
                -- This used to `return nil`: an acquisition the player had not
                -- made selected NO step at all, so the objective went dark and
                -- nothing could be routed. The user's rule, 2026-08-22: "The
                -- only thing that should ever block you is if you don't meet
                -- the requirements to see the mission, which means it doesn't
                -- even show up on your list."
                --
                -- The detection was never the problem -- "the guide says to
                -- obtain X before travelling to Y" is exactly the sentence a
                -- sighted player reads off the page. So it is carried on the
                -- step and spoken, and the route proceeds. Getting there
                -- without the item wastes a walk; being told nothing and going
                -- nowhere wastes the evening (sol's contract: a routing
                -- concern downgrades neither the information nor the route).
                if (type(resolver) == 'table' and resolver.is_zone_changing_action(action)) then
                    if (actions == nil) then
                        actions = progression_actions(native_key) or T{};
                    end
                    local blocking = resolver.blocking_prerequisite(
                        actions, completed_order, step_id, acquisition_row_items_owned);
                    if (blocking ~= nil) then
                        local advisory = resolver.prerequisite_refusal(blocking, step);
                        advisory.reason = nil;
                        advisory.advisory = true;
                        local held = source_derivation_cache.prerequisite_refusals[native_key];
                        held[step_id] = advisory;
                        log_line(('objective prerequisite noted native="%s" travel="%s" prerequisite="%s" detail="%s"'):fmt(
                            native_key, step_id, clean(blocking.step_id), tostring(advisory.detail)));
                    end
                end
                return step;
            end
        end
    end
    return first_material;
end

objective_step_by_id = function(native_key, step_id)
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
    if (selected_order < completed_order) then return items, key_items; end
    for _, step in ipairs(objective_source_steps(native_key)) do
        local order = tonumber(step.order) or 0;
        local action = clean(step.action):lower();
        if (order >= completed_order and order <= selected_order
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
    local action, actions, revision, record = progression_cursor(native_key, point);
    local action_id = clean(point.objective_action_id);
    local cursor_index = type(action) == 'table' and action_index_by_identity(
        actions, action.step_id, action.step_order, action.action_id, action.action_order) or nil;
    local index = cursor_index;
    if (type(action) == 'table' and action_id ~= ''
        and action_id ~= clean(action.action_id)) then
        index = nil;
        for candidate_index = cursor_index or 1, #actions do
            local candidate = actions[candidate_index];
            if (clean(candidate.action_id) == action_id
                and clean(candidate.step_id) == step_id) then
                index = candidate_index;
                break;
            end
        end
    end
    local future_match = index ~= nil and cursor_index ~= nil and index > cursor_index;
    if (type(action) ~= 'table' or index == nil
        or clean(point.objective_progression_revision) ~= ''
            and clean(point.objective_progression_revision) ~= revision
        or future_match and (clean(point.objective_cursor_action_id)
                ~= clean(action.action_id)
            or not interaction_completion_state_ready(point))) then
        return false;
    end
    local matched_action = actions[index];
    local objective = {
        category = kind, native_key = native_key, action = matched_action,
        actions = actions, revision = revision, record = record, index = index,
    };
    if (type(advance_objective_match) ~= 'function'
        or not advance_objective_match(objective, index, 1)) then return false; end
    if (type(notify_objective_progress) == 'function') then
        notify_objective_progress(T{ objective });
    end
    if (type(log_line) == 'function') then
        log_line(('objective interaction completed kind=%s native="%s" step="%s" action="%s" reason="%s"'):fmt(
            kind, native_key, step_id, clean(matched_action.action_id), clean(reason)));
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
    phase = clean(phase):lower();
    now = tonumber(now) or 0;
    if ((phase == 'start' or phase == 'finish')
        and type(accessxi.nav_mission_quest_reduce_signal) == 'function') then
        local ok, accepted = pcall(accessxi.nav_mission_quest_reduce_signal, {
            kind = phase == 'start' and 'interaction-start' or 'interaction-finish',
            character_identity = character_identity(),
            world_id = player_world_id(),
            session_epoch = objective_session_epoch(),
            sequence = now,
            tick = now,
            corpus_revision = tonumber(accessxi.nav_catalog_revision) or 0,
            progression_revision = '',
            target_server_id = tonumber(target_server_id) or 0,
            zone_id = tonumber(zone_id) or 0,
            event_id = tonumber(event_id) or 0,
            menu_id = tonumber(event_id) or 0,
        });
        if (ok and accepted == true) then return true; end
    end

    local pending = pending_objective_interaction;
    if (type(pending) ~= 'table'
        or now < (tonumber(pending.arrived_at) or 0)
        or (now - (tonumber(pending.arrived_at) or 0)) > 1200000) then
        return false;
    end
    if (not pending_interaction_owner_current(pending)) then
        pending_objective_interaction = nil;
        return false;
    end

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

local function gate_guard_step_rows(item, step, action)
    local rows = T{};
    if (not exact_gate_guard_role(step)
        or type(accessxi.missions_menu_nation_context_id) ~= 'function') then
        return rows;
    end
    local nation = accessxi.missions_menu_nation_context_id(clean(item.mission_context));
    for _, reference in ipairs(nation_gate_guards[tonumber(nation) or -1] or T{}) do
        local point = referenced_target(reference);
        local row = point ~= nil and source_route_candidate(
            clean(item.objective_native_key), step, point) or nil;
        if (row ~= nil and type(action) == 'table') then
            row.action_id = clean(action.action_id);
            row.action = clean(action.action);
            row.action_instruction = clean(action.instruction);
            row.arrival_instruction = clean(action.instruction);
            row.items = deep_copy(action.items);
            row.key_items = deep_copy(action.key_items);
            row.enemies = deep_copy(action.enemies);
        end
        if (row ~= nil) then rows:append(row); end
    end
    return rows;
end

local function append_gate_guard_step_rows(item, step, replacements)
    for _, row in ipairs(gate_guard_step_rows(item, step)) do
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

local function compact_action_destination_row(action, point)
    if (type(action) ~= 'table' or type(point) ~= 'table') then return nil; end
    local destination_id = clean(point.destination_id);
    local step_id = clean(action.step_id);
    local action_id = clean(action.action_id);
    if (destination_id == '' or step_id == '' or action_id == '') then return nil; end
    return T{
        candidate_id = clean(point.candidate_id) ~= '' and clean(point.candidate_id)
            or action_id .. ':candidate:' .. destination_id,
        action_id = action_id,
        group_id = clean(point.group_id),
        destination_id = destination_id,
        guide_step_id = step_id,
        guide_step_order = tonumber(action.step_order) or 0,
        action = clean(action.action),
        action_instruction = clean(point.arrival_instruction) ~= ''
            and clean(point.arrival_instruction) or clean(action.instruction),
        arrival_instruction = clean(point.arrival_instruction) ~= ''
            and clean(point.arrival_instruction) or clean(action.instruction),
        classification = 'catalogue-candidate',
        material = true,
        route_ready = false,
        zone = tonumber(point.zone_id) or 0,
        zone_name = clean(point.zone_name),
        target_name = clean(point.target_name),
        target_kind = clean(point.target_kind),
        target_point = deep_copy(point.target_point),
        raw_identity = clean(point.raw_identity),
        raw_spawn_ids = deep_copy(point.raw_spawn_ids),
        cluster_policy_version = clean(point.cluster_policy_version),
        transport_id = clean(point.transport_id),
        battlefield_id = clean(point.battlefield_id),
        metadata_class = clean(point.metadata_class),
        items = deep_copy(action.items),
        key_items = deep_copy(action.key_items),
        enemies = deep_copy(action.enemies),
        destination_zone_name = clean(action.destination_zone_name),
        destination_zone_id = tonumber(action.destination_zone_id) or 0,
    };
end

-- WHAT A GUIDE PAGE STILL SAYS AFTER THE LAST STEP IT CAN ROUTE.
--
-- A wiki page does not stop where the compact actions stop. Below the Arks has
-- five compact actions, ending at "enter the Hall of Transference"; BG Wiki's
-- page then says "You must now complete each of the three Promyvions, which can
-- be done in any order" and "The walkthrough for completing each Promyvion is
-- located in the next mission, The Mothercrystals". Those are the answer to the
-- question the player asked, and until now nothing could reach them.
--
-- A line is one of four things. A TERMINATOR ends the useful part of a page --
-- everything under "See Also" is navigation, and the entry beneath it
-- ("Promyvion Guide") is a link, not guidance. A HEADING is a structural marker
-- with nothing under it yet; skip the line and keep reading. Anything else is
-- PROSE and the player gets it verbatim.
--
-- Deliberately NOT filtered: "(Optional)". The guide says optional in its own
-- words, and a sighted reader sees both that the line exists and that it is
-- optional. Dropping it because it might already be done is guessing on the
-- player's behalf.
function accessxi.objective_guide_line_role(text)
    text = clean(text);
    if (text == '') then return 'empty'; end
    local key = text:lower():gsub('[%s%.:;]+$', '');
    if (key == 'see also' or key == 'references' or key == 'external links'
        or key == 'external link' or key == 'sources' or key == 'see') then
        return 'terminator';
    end
    if (key == 'notes' or key == 'note' or key == 'walkthrough'
        or key == 'rewards' or key == 'reward' or key == 'objectives'
        or key == 'other information' or key == 'game description') then
        return 'heading';
    end
    if (text:sub(1, 8):lower() == 'section:') then return 'heading'; end
    return 'prose';
end

-- WHICH STEP OF EACH PAGE THE CURSOR ACTUALLY REACHED.
--
-- Not the merged order. The reconciled list interleaves the two pages BY
-- ORDINAL POSITION, so a short page's remainder sorts EARLIER than a long
-- page's cursor: BG has 5 steps and FFXIclopedia 13, and BG's answer lands at
-- merged row 4 while the last actioned step is merged row 9. Anything keyed on
-- merged order reads the wrong half of the page.
--
-- Not "the merged step owns an action" either, because a merged step can carry
-- both pages while its compact action came from only one of them (sol). The
-- action itself records the provenance: source_action_span_ids reads
-- "mission:Chains of Promathia:3:ffxiclopedia:step-007:span-02" -- the page,
-- and that page's OWN step number. Take the greatest number each page proves.
--
-- A page that proves nothing is omitted rather than guessed at. Across the
-- 1739 shipped objectives that have compact actions, none is in that state
-- today; the branch exists because generated data changes.
function accessxi.objective_guide_page_boundaries(actions, native_key)
    local boundaries = {};
    for _, action in ipairs(type(actions) == 'table' and actions or T{}) do
        local spans = type(action) == 'table' and action.source_action_span_ids or nil;
        for _, span in ipairs(type(spans) == 'table' and spans or T{}) do
            local page, number = tostring(span):match(':(%a[%a_]*):step%-(%d+):');
            number = tonumber(number);
            if (page ~= nil and number ~= nil
                and (boundaries[page] == nil or number > boundaries[page])) then
                boundaries[page] = number;
            end
        end
    end
    if (next(boundaries) == nil and type(log_line) == 'function'
        and clean(native_key) ~= '') then
        log_line(('objective postlude boundary unproven native="%s" actions=%d'):fmt(
            clean(native_key), type(actions) == 'table' and #actions or 0));
    end
    return boundaries;
end

-- ONE READING PER PAGE, IN THE ORDER THAT PAGE WROTE IT.
--
-- Never combined. Two short attributable readings are safer than one synthetic
-- reading neither page wrote (sol), and this project's standing rule on a
-- disagreement is to read each page alone rather than the merge.
-- Second return value: what the reading LEFT OUT, which the player is owed.
--   material_tail  distinct steps after a page's boundary whose action is not
--                  'note' -- travel, talk, examine, trade, fight, obtain, use,
--                  select, wait, protect. Those are the ten verbs the compact
--                  builder itself turns into actions, so a page with any of
--                  them left has not run out of steps: THIS ADDON has run out
--                  of tracking for them. Different fact, different sentence.
--   truncated      a page had more prose than the six-line cap. 295 pages hit
--                  that cap across the shipped corpus
--                  (tools/measure_postlude_output.lua), so staying quiet about
--                  it would drop real guidance on the floor without a word.
function accessxi.objective_guide_postlude_pages(native_key, actions)
    local pages = T{};
    local summary = { material_tail = 0, truncated = false };
    native_key = clean(native_key);
    if (native_key == '' or type(objective_source_steps) ~= 'function') then
        return pages, summary;
    end
    local ok, steps = pcall(objective_source_steps, native_key);
    if (not ok or type(steps) ~= 'table' or #steps == 0) then return pages, summary; end

    local boundaries = accessxi.objective_guide_page_boundaries(actions, native_key);
    local entry = type(accessxi.mission_quest_guide_index) == 'table'
        and accessxi.mission_quest_guide_index[native_key] or nil;
    local authority = type(entry) == 'table' and type(entry.source_authority) == 'table'
        and entry.source_authority or {};
    local primary = clean(authority.primary);

    -- source_orders slot 1 is BG Wiki and slot 2 is FFXIclopedia. That is
    -- generated data, so it is checked rather than assumed:
    -- tools/measure_exhausted_cursor_reach.lua finds 40549 rows where a slot
    -- carries an order and 0 where the matching instruction field is empty.
    local readings = T{
        T{ key = 'bg', slot = 1, field = 'bg_instruction', name = 'BG Wiki' },
        T{ key = 'ffxiclopedia', slot = 2, field = 'ffxiclopedia_instruction',
           name = 'FFXIclopedia' },
    };
    -- The declared primary source is read first; the player hears the page the
    -- guide index says is authoritative before the one it says is a fallback.
    if (primary == 'ffxiclopedia') then
        readings = T{ readings[2], readings[1] };
    end

    local said, material = {}, {};
    for _, reading in ipairs(readings) do
        local boundary = tonumber(boundaries[reading.key]) or 0;
        if (boundary > 0) then
            local ordered = T{};
            for _, step in ipairs(steps) do
                local orders = type(step.source_orders) == 'table' and step.source_orders or {};
                local order = tonumber(orders[reading.slot]) or 0;
                if (order > boundary) then
                    ordered:append(T{ order = order, step = step });
                    -- Counted on THIS page's boundary, in THIS page's order.
                    -- The first version of this counted from the merged list
                    -- after the last actioned step, which is precisely the
                    -- ordering this whole function exists to avoid (sol).
                    local verb = clean(step.action):lower();
                    if (verb ~= '' and verb ~= 'note') then
                        material[clean(step.stable_step_id)] = true;
                    end
                end
            end
            table.sort(ordered, function (left, right) return left.order < right.order; end);
            local lines = T{};
            for _, row in ipairs(ordered) do
                local text = clean(row.step[reading.field]);
                local role = accessxi.objective_guide_line_role(text);
                if (role == 'terminator') then break; end
                if (role == 'prose' and said[text:lower()] ~= true) then
                    if (#lines < 6) then
                        said[text:lower()] = true;
                        lines:append(text);
                    else
                        summary.truncated = true;
                    end
                end
            end
            if (#lines > 0) then
                pages:append(T{ key = reading.key, name = reading.name, lines = lines });
            end
        end
    end
    for _ in pairs(material) do summary.material_tail = summary.material_tail + 1; end
    return pages, summary;
end

-- THE PLACES A FINISHED STEP STILL POINTS AT.
--
-- The reconciled step carries the zones its own sentence names -- for Below the
-- Arks' last tracked step that is Tahrongi Canyon, Konschtat Highlands and La
-- Theine Plateau, the three crags. Once the cursor is exhausted nothing else
-- will ever say them, because a postlude row is instruction-only and has no
-- destination of its own.
--
-- Only when there is MORE THAN ONE. A single zone is either already where the
-- player is or was the thing they just did, and naming it reads as an
-- instruction to go back. Two or more is a genuine open choice, which is the
-- case the player asked about and the case 95 objectives are in.
--
-- This states where, never how many are done. The mod cannot observe which
-- crags have been used, and a count it cannot see is a count it must not claim.
function accessxi.objective_step_open_places(native_key, step_id)
    native_key = clean(native_key);
    step_id = clean(step_id);
    if (native_key == '' or step_id == '' or type(objective_step_by_id) ~= 'function') then
        return '';
    end
    local ok, step = pcall(objective_step_by_id, native_key, step_id);
    if (not ok or type(step) ~= 'table') then return ''; end
    local seen, names = {}, T{};
    for _, zone in ipairs(type(step.zones) == 'table' and step.zones or T{}) do
        local name = clean(zone);
        if (name ~= '' and seen[name:lower()] ~= true) then
            seen[name:lower()] = true;
            names:append(name);
        end
    end
    if (#names < 2) then return ''; end
    return spoken_list(names);
end

-- The same thing as one sentence, for the places that speak rather than list:
-- the announcement when the last step completes, and N's own confirmation.
function accessxi.objective_guide_postlude_text(native_key, actions)
    local parts = T{};
    local pages, summary = accessxi.objective_guide_postlude_pages(native_key, actions);
    summary = type(summary) == 'table' and summary or { material_tail = 0, truncated = false };
    if ((tonumber(summary.material_tail) or 0) > 0) then
        parts:append('Automatic tracking ends here, and the guide still has steps it does not track.');
    end
    for _, page in ipairs(pages) do
        parts:append(('%s continues: %s'):fmt(clean(page.name),
            accessxi.objective_detail_text_from_lines(page.lines)));
    end
    if (summary.truncated == true and #pages > 0) then
        parts:append('More guide text follows. Press G to read it.');
    end
    return table.concat(parts, ' '), summary;
end

-- THE ROW THE BROWSE READS WHEN THERE IS NOTHING LEFT TO ROUTE.
--
-- Always at least one row. An objective that vanishes from the list, or that
-- occupies a row saying nothing, leaves the player unable to tell whether the
-- addon has lost track of them -- and in this project being told nothing is
-- worse than being told something wrong, because nothing cannot be argued with.
function accessxi.objective_append_guide_postlude_rows(item, replacements, actions, state)
    if (type(item) ~= 'table' or type(replacements) ~= 'table') then return 0; end
    local native_key = clean(item.objective_native_key);
    local last = type(actions) == 'table' and actions[#actions] or nil;
    local last_step = clean(type(last) == 'table' and last.step_id or '');
    local last_order = tonumber(type(last) == 'table' and last.step_order or nil) or 0;
    if (last_step == '') then return 0; end
    state = clean(state) ~= '' and clean(state) or 'exhausted';

    -- A CURSOR THAT LOST ITS PLACE IS NOT A CURSOR THAT FINISHED.
    --
    -- Reading the end of the guide to somebody whose saved position no longer
    -- matches the guide walks them past the step they are actually on. Say what
    -- happened instead, and hand them the guide.
    if (state == 'invalid') then
        local row = T{
            candidate_id = '', action_id = last_step .. ':progress-mismatch',
            group_id = '', destination_id = '',
            guide_step_id = last_step, guide_step_order = last_order,
            action = 'note',
            action_instruction = 'Saved progress for this objective does not match the guide '
                .. 'this addon has, so no step was chosen. Press G to read the guide yourself.',
            instruction_only = true, classification = 'instruction-only',
            status = 'instruction-only', reason = 'complete-instruction',
            material = true, route_ready = false,
        };
        local replacement = expanded_objective_row(item, row);
        if (replacement ~= nil) then
            replacement.objective_guide_postlude = true;
            replacement.objective_guide_postlude_kind = 'invalid';
            replacement.objective_guide_postlude_source = '';
            replacements:append(replacement);
        end
        return replacement ~= nil and 1 or 0;
    end

    local pages, summary = accessxi.objective_guide_postlude_pages(native_key, actions);
    summary = type(summary) == 'table' and summary or { material_tail = 0, truncated = false };
    -- WHERE THE WORK STILL IS.
    --
    -- A postlude row is instruction-only, so an exhausted objective loses every
    -- destination it had -- and for a last tracked step that names more than one
    -- place, that is the whole answer walking out of the door. Below the Arks'
    -- last tracked step names three crags; the player asked for exactly this:
    -- "at least mention you need to zone to the 3 destinations where the
    -- shattered telepoints are".
    --
    -- The ZONES, not the instruction. Re-offering "Examine the Shattered
    -- Telepoint" as a choice is the completed-step recital this postlude was
    -- built to stop, and tools/test_exhausted_cursor_row.lua forbids it by name.
    local places = accessxi.objective_step_open_places(native_key, last_step);
    local added = 0;
    for index = 1, math.max(1, #pages) do
        local page = pages[index];
        local instruction = page ~= nil
            and accessxi.objective_detail_text_from_lines(page.lines)
            or 'The guide records nothing further for this objective.';
        local row = T{
            candidate_id = '',
            -- Ordered so the declared primary page sorts first: objective_row_less
            -- falls through to a lexical compare on the action id.
            action_id = ('%s:postlude-%d'):fmt(last_step, index),
            group_id = '', destination_id = '',
            guide_step_id = last_step,
            guide_step_order = last_order,
            action = 'note',
            action_instruction = instruction,
            instruction_only = true,
            classification = 'instruction-only',
            status = 'instruction-only',
            reason = 'complete-instruction',
            material = true,
            route_ready = false,
        };
        local replacement = expanded_objective_row(item, row);
        if (replacement ~= nil) then
            replacement.objective_guide_postlude = true;
            replacement.objective_guide_postlude_kind = 'exhausted';
            replacement.objective_guide_postlude_source = page ~= nil and clean(page.name) or '';
            replacement.objective_guide_postlude_material_tail =
                tonumber(summary.material_tail) or 0;
            replacement.objective_guide_postlude_truncated = summary.truncated == true;
            replacement.objective_guide_postlude_places = places;
            replacements:append(replacement);
            added = added + 1;
        end
    end
    if (type(log_line) == 'function') then
        -- MATERIAL STEPS AFTER THE LAST ACTION ARE A TRACKING GAP, NOT A
        -- FINISHED PAGE. The count comes from the pages themselves, on their
        -- own boundaries -- an earlier version of this line recomputed it from
        -- the merged list, which is the exact ordering mistake this whole
        -- function exists to avoid.
        log_line(('objective progression exhausted native="%s" last-step="%s" pages=%d rows=%d tail-material=%d truncated=%s places="%s"'):fmt(
            native_key, last_step, #pages, added,
            tonumber(summary.material_tail) or 0, tostring(summary.truncated == true),
            clean(places)));
    end
    return added;
end

local function instruction_row_for_action(action)
    return T{
        candidate_id = '', action_id = clean(action.action_id), group_id = '',
        destination_id = '', guide_step_id = clean(action.step_id),
        guide_step_order = tonumber(action.step_order) or 0,
        action = clean(action.action),
        action_instruction = clean(action.instruction),
        instruction_only = true, classification = 'instruction-only',
        status = 'instruction-only', reason = 'complete-instruction',
        material = true, route_ready = false,
    };
end

local function action_for_source_destination(actions, first_index, step, row)
    local step_id = clean(type(step) == 'table' and step.stable_step_id or '');
    local destination_id = clean(type(row) == 'table' and row.destination_id or '');
    local target_key = source_name_key(type(row) == 'table'
        and (row.target_name or row.name) or '');
    local target_kind = clean(type(row) == 'table'
        and (row.target_kind or row.kind) or ''):lower();
    local fallback = nil;
    local only_candidate = nil;
    local candidate_count = 0;
    for index = math.max(1, tonumber(first_index) or 1), #actions do
        local candidate = actions[index];
        if (clean(candidate.step_id) == step_id) then
            candidate_count = candidate_count + 1;
            only_candidate = candidate;
            for _, point in ipairs(type(candidate.catalogue) == 'table'
                and candidate.catalogue or T{}) do
                if (destination_id ~= '' and clean(point.destination_id) == destination_id) then
                    return candidate;
                end
            end
            local candidate_key = source_name_key(candidate.target);
            if (target_key ~= '' and candidate_key ~= ''
                and (candidate_key == target_key
                    or candidate_key:sub(1, #target_key) == target_key
                    or target_key:sub(1, #candidate_key) == candidate_key)) then
                return candidate;
            end
            local action_name = clean(candidate.action):lower();
            local kind_compatible = (target_kind == 'object'
                    and (action_name == 'examine' or action_name == 'use'))
                or (target_kind == 'npc'
                    and (action_name == 'talk' or action_name == 'trade'
                        or action_name == 'deliver' or action_name == 'use'))
                or ((target_kind == 'enemy' or target_kind == 'nm'
                        or target_kind == 'live-nm')
                    and (action_name == 'fight' or action_name == 'obtain'
                        or action_name == 'farm'))
                or (target_kind == 'transport'
                    and (action_name == 'travel' or action_name == 'use'));
            if (kind_compatible and fallback == nil) then fallback = candidate; end
        end
    end
    return fallback or (candidate_count == 1 and only_candidate or nil);
end

local function append_current_progression_rows(item, replacements)
    local native_key = clean(item.objective_native_key);
    local action, actions, revision, record, state = progression_cursor(native_key, item);
    -- EXHAUSTED IS NOT THE SAME AS NEVER HAVING HAD A CURSOR.
    --
    -- Both used to answer (handled, nil), and the caller read that as "nothing
    -- to add" and dumped every route row the mission owns. For an objective
    -- with no compact actions at all that is the only view there is; for one
    -- whose cursor has reached the end it is a recital of finished work. Live
    -- 2026-08-29 Below the Arks read back three completed steps and nothing
    -- else -- "I don't even know what I'm supposed to do".
    if (type(actions) ~= 'table') then return false, nil, 'unavailable', nil; end
    if (type(action) ~= 'table') then
        return true, nil, clean(state) ~= '' and clean(state) or 'exhausted', actions;
    end

    local cursor_action = action;
    local cursor_index = action_index_by_identity(actions, action.step_id,
        action.step_order, action.action_id, action.action_order) or 1;
    local guide_destinations = objective_guide_destinations(native_key);
    local rows, seen = T{}, {};
    local action_name = clean(action.action):lower();
    local instruction_barrier = action_name == 'wait' or action_name == 'select';
    for _, row in ipairs(guide_destinations) do
        -- Empty compact catalogues are still useful K-key instructions, but
        -- they are not destinations. Do not let their synthetic instruction
        -- rows preempt source-route and later-action lookup. Explicit waits
        -- and menu selections remain barriers and cannot be routed around.
        if (clean(row.action_id) == clean(action.action_id)
            and (row.instruction_only ~= true or instruction_barrier)) then
            local destination_id = clean(row.destination_id);
            local key = destination_id ~= '' and destination_id
                or clean(row.candidate_id) .. '\t' .. clean(row.action_id);
            if (key ~= '' and not seen[key]) then
                seen[key] = true;
                rows:append(deep_copy(row));
            end
        end
    end
    for _, point in ipairs(type(action.catalogue) == 'table' and action.catalogue or T{}) do
        local row = compact_action_destination_row(action, point);
        local key = row ~= nil and clean(row.destination_id) or '';
        if (row ~= nil and key ~= '' and not seen[key]) then
            seen[key] = true;
            rows:append(row);
        end
    end

    -- Wiki steps commonly split "travel to zone and talk to NPC" into two
    -- compact actions. The travel action has no finite point, while the
    -- immediately following action owns the exact NPC catalogue. Route to
    -- that point only when it is the next action in the same step and its
    -- exact zone matches the travel destination; keep the durable cursor on
    -- the travel prerequisite until native evidence advances it.
    if (#rows == 0 and action_name == 'travel') then
        local expected_zone = tonumber(action.destination_zone_id) or 0;
        local next_action = actions[cursor_index + 1];
        if (expected_zone > 0 and type(next_action) == 'table'
            and clean(next_action.step_id) == clean(action.step_id)
            and (tonumber(next_action.order) or 0) > (tonumber(action.order) or 0)) then
            local projected_rows, projected_seen = T{}, {};
            for _, row in ipairs(guide_destinations) do
                local destination_id = clean(row.destination_id);
                if (row.instruction_only ~= true
                    and clean(row.action_id) == clean(next_action.action_id)
                    and (tonumber(row.zone) or 0) == expected_zone
                    and destination_id ~= '' and not projected_seen[destination_id]) then
                    projected_seen[destination_id] = true;
                    projected_rows:append(deep_copy(row));
                end
            end
            for _, point in ipairs(type(next_action.catalogue) == 'table'
                and next_action.catalogue or T{}) do
                local row = compact_action_destination_row(next_action, point);
                local destination_id = row ~= nil and clean(row.destination_id) or '';
                if (row ~= nil and (tonumber(row.zone) or 0) == expected_zone
                    and destination_id ~= '' and not projected_seen[destination_id]) then
                    projected_seen[destination_id] = true;
                    projected_rows:append(row);
                end
            end
            if (#projected_rows > 0) then
                rows = projected_rows;
                seen = projected_seen;
                action = next_action;
            end
        end
    end

    if (#rows == 0) then
        local source_step = objective_step_by_id(native_key, clean(action.step_id));
        local reviewed_point = reviewed_inventory_followup_target(source_step);
        local row = reviewed_point ~= nil and source_route_candidate(
            native_key, source_step, reviewed_point) or nil;
        if (row ~= nil) then
            row.action_id = clean(action.action_id);
            row.action = clean(action.action);
            row.action_instruction = clean(action.instruction);
            row.arrival_instruction = clean(action.instruction);
            rows:append(row);
            seen[clean(row.destination_id)] = true;
        end
    end

    if (#rows == 0) then
        local source_step = objective_step_by_id(native_key, clean(action.step_id));
        for _, row in ipairs(gate_guard_step_rows(item, source_step, action)) do
            local key = clean(row.destination_id);
            if (key ~= '' and not seen[key]) then
                seen[key] = true;
                rows:append(row);
            end
        end
    end

    if (#rows == 0) then
        for _, row in ipairs(source_route_rows(native_key)) do
            if (clean(row.guide_step_id) == clean(action.step_id)) then
                local copied = deep_copy(row);
                copied.action_id = clean(action.action_id);
                copied.action = clean(action.action);
                copied.action_instruction = clean(action.instruction);
                copied.arrival_instruction = clean(action.instruction);
                copied.items = deep_copy(action.items);
                copied.key_items = deep_copy(action.key_items);
                copied.enemies = deep_copy(action.enemies);
                local key = clean(copied.destination_id);
                if (key ~= '' and not seen[key]) then
                    seen[key] = true;
                    rows:append(copied);
                end
            end
        end
    end

    -- Preserve the established route view for exact later destinations while
    -- the v2 cursor remains on an earlier wiki prerequisite.  The selected
    -- later action is still completed only by its exact owned interaction and
    -- the accumulated item/key-item prerequisites stamped below.
    if (#rows == 0) then
        local projected_step = next_routable_progress_step(native_key, guide_destinations);
        if (type(projected_step) == 'table'
            and (tonumber(projected_step.order) or 0)
                > (tonumber(cursor_action.step_order) or 0)) then
            local projected_rows = T{};
            local reviewed_point = reviewed_inventory_followup_target(projected_step);
            local reviewed_row = reviewed_point ~= nil and source_route_candidate(
                native_key, projected_step, reviewed_point) or nil;
            if (reviewed_row ~= nil) then projected_rows:append(reviewed_row); end
            if (#projected_rows == 0) then
                for _, row in ipairs(source_route_rows(native_key)) do
                    if (clean(row.guide_step_id) == clean(projected_step.stable_step_id)) then
                        projected_rows:append(deep_copy(row));
                    end
                end
            end
            if (#projected_rows == 0 and exact_gate_guard_role(projected_step)) then
                projected_rows = gate_guard_step_rows(item, projected_step);
            end
            local projected_action = #projected_rows > 0
                and action_for_source_destination(actions, cursor_index,
                    projected_step, projected_rows[1]) or nil;
            if (type(projected_action) == 'table') then
                action = projected_action;
                for _, row in ipairs(projected_rows) do
                    row.action_id = clean(action.action_id);
                    row.action = clean(action.action);
                    row.action_instruction = clean(action.instruction);
                    row.arrival_instruction = clean(action.instruction);
                    row.items = deep_copy(action.items);
                    row.key_items = deep_copy(action.key_items);
                    row.enemies = deep_copy(action.enemies);
                    local key = clean(row.destination_id);
                    if (key ~= '' and not seen[key]) then
                        seen[key] = true;
                        rows:append(row);
                    end
                end
            end
        end
    end
    if (#rows == 0) then rows:append(instruction_row_for_action(action)); end

    local progress_count = type(record) == 'table'
        and clean(record.action_id) == clean(action.action_id)
        and (tonumber(record.progress_count) or 0) or 0;
    for _, row in ipairs(rows) do
        local replacement = expanded_objective_row(item, row);
        if (replacement ~= nil) then
            replacement.objective_progression_revision = revision;
            replacement.objective_cursor_action_id = clean(cursor_action.action_id);
            replacement.objective_progress_count = progress_count;
            replacement.objective_required_count = tonumber(action.required_count) or 1;
            replacement.objective_count_mode = clean(action.count_mode);
            replacement.objective_destination_zone_name =
                clean(action.destination_zone_name) ~= ''
                and clean(action.destination_zone_name)
                or clean(replacement.objective_destination_zone_name);
            replacement.objective_destination_zone_id =
                (tonumber(action.destination_zone_id) or 0) > 0
                and tonumber(action.destination_zone_id)
                or tonumber(replacement.objective_destination_zone_id);
            if (type(replacement.objective_target) == 'table') then
                replacement.objective_target.objective_progression_revision = revision;
                replacement.objective_target.objective_cursor_action_id =
                    clean(cursor_action.action_id);
                replacement.objective_target.objective_destination_zone_name =
                    replacement.objective_destination_zone_name;
                replacement.objective_target.objective_destination_zone_id =
                    replacement.objective_destination_zone_id;
            end
            replacements:append(replacement);
        end
    end
    return true, action, 'active', actions;
end

-- THE LIST MUST OPEN ON THE MISSION THEY ARE ACTUALLY DOING.
--
-- Live 2026-08-24 the player had NINE active mission destinations across San
-- d'Oria, Rhapsodies, Zilart, CoP, Aht Urhgan, WotG, Adoulin, Moogle Kupo
-- d'Etat and Shantotto. active_missions() appends the nation mission first and
-- always has, so the Missions category opened on "The Davoi Report" every time.
-- They were working Rhapsodies 8, pressed route on the first entry, and were
-- sent toward Davoi -- whose road out of East Ronfaure runs through King
-- Ranperre's Tomb, which is where they were standing when they said "it's
-- trying to lead me the wrong way on this mission again".
--
-- A sighted player sees nine rows and picks. This player hears ONE row and has
-- to arrow past eight to reach the one they want, every single time. So the
-- mission they last routed comes first from then on. This is remembered rather
-- than guessed: it is their own choice played back, which is the only ordering
-- signal that cannot be wrong about what they are working on.
local function mission_order_recent_key()
    return clean(accessxi.nav_objective_recent_mission_key or '');
end

function accessxi.nav_objective_remember_mission(native_key)
    native_key = clean(native_key);
    if (native_key == '') then return false; end
    if (clean(accessxi.nav_objective_recent_mission_key or '') == native_key) then
        return false;
    end
    accessxi.nav_objective_recent_mission_key = native_key;
    if (type(log_line) == 'function') then
        log_line(('objective recent mission set native="%s"'):fmt(native_key));
    end
    return true;
end

local function expand_active_mission_destinations(items)
    local expanded = T{};
    for _, item in ipairs(items or T{}) do
        local replacements = T{};
        local selected_step = nil;
        -- An exhausted cursor forfeits the whole-mission fallback below,
        -- whether or not the postlude found anything to say.
        local cursor_exhausted = false;
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
            local handled, progression_action, progression_state, progression_list =
                append_current_progression_rows(item, replacements);
            if (handled) then
                selected_step = progression_action ~= nil
                    and objective_step_by_id(clean(item.objective_native_key),
                        clean(progression_action.step_id)) or nil;
                -- The cursor finished. Say what the guide still says rather
                -- than falling through to the whole-mission fallback below.
                if (progression_state == 'exhausted' or progression_state == 'invalid') then
                    cursor_exhausted = true;
                    accessxi.objective_append_guide_postlude_rows(
                        item, replacements, progression_list, progression_state);
                end
            else
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
        end
        if (#replacements == 0 and not cursor_exhausted) then
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
        local cursor_exhausted = false;
        local handled, progression_action, progression_state, progression_list =
            append_current_progression_rows(item, replacements);
        if (handled) then
            selected_step = progression_action ~= nil
                and objective_step_by_id(clean(item.objective_native_key),
                    clean(progression_action.step_id)) or nil;
            if (progression_state == 'exhausted' or progression_state == 'invalid') then
                cursor_exhausted = true;
                accessxi.objective_append_guide_postlude_rows(
                    item, replacements, progression_list, progression_state);
            end
        else
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
        if (#replacements == 0 and not cursor_exhausted) then
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
    -- Stable: only the remembered mission is lifted, and rows inside it keep
    -- the order expand_active_mission_destinations gave them. Nothing else
    -- moves, so the list a player has learned stays learned.
    local recent = mission_order_recent_key();
    if (recent ~= '' and type(expanded) == 'table' and #expanded > 1) then
        local first, rest = T{}, T{};
        for _, row in ipairs(expanded) do
            if (clean(type(row) == 'table' and row.objective_native_key or '') == recent) then
                first:append(row);
            else
                rest:append(row);
            end
        end
        if (#first > 0 and #rest > 0) then
            local merged = T{};
            for _, row in ipairs(first) do merged:append(row); end
            for _, row in ipairs(rest) do merged:append(row); end
            expanded = merged;
        end
    end
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

local function retain_active_progression_keys(items)
    if (type(accessxi.objective_guides) ~= 'table'
        or type(accessxi.objective_guides.retain_progression_keys) ~= 'function') then
        return false;
    end
    local keys = {};
    for _, item in ipairs(type(items) == 'table' and items or T{}) do
        local native_key = clean(item.objective_native_key);
        if (native_key ~= '') then keys[native_key] = true; end
    end
    local ok = pcall(
        accessxi.objective_guides.retain_progression_keys,
        accessxi.objective_guides,
        keys);
    return ok;
end

function accessxi.nav_mission_quest_active_items(category_key)
    category_key = clean(category_key):lower();
    if (category_key ~= 'mission' and category_key ~= 'quest') then return T{}; end
    if (character_identity() == '' or player_world_id() <= 0
        or objective_session_epoch() <= 0) then
        return T{};
    end
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
        retain_active_progression_keys(cached.rows);
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
    retain_active_progression_keys(rows);
    if (active_build_guide_failed) then
        active_row_cache[category_key] = nil;
    else
        active_row_cache[category_key] = { signature = signature, rows = rows };
    end
    return rows;
end

local function signal_owner_current(signal)
    if (type(signal) ~= 'table') then return false; end
    local identity = character_identity();
    local world_id = player_world_id();
    local session_epoch = objective_session_epoch();
    return identity ~= '' and world_id > 0 and session_epoch > 0
        and clean(signal.character_identity):lower() == identity
        and tonumber(signal.world_id) == world_id
        and tonumber(signal.session_epoch) == session_epoch
        and (tonumber(signal.sequence) or 0) > 0
        and (tonumber(signal.tick) or 0) > 0
        and tonumber(signal.corpus_revision)
            == (tonumber(accessxi.nav_catalog_revision) or 0);
end

local function action_name_matches(values, wanted)
    wanted = clean(wanted):lower();
    if (wanted == '') then return false; end
    for _, value in ipairs(type(values) == 'table' and values or T{}) do
        local name = clean(type(value) == 'table'
            and (value.name or value.item or value.key_item) or value):lower();
        if (name == wanted) then return true; end
    end
    return false;
end

local function catalogue_server_ids(point)
    local ids = {};
    for _, value in ipairs(type(point) == 'table' and point.raw_spawn_ids or T{}) do
        local id = tonumber(value) or 0;
        if (id > 0) then ids[id] = true; end
    end
    local destination_id = clean(type(point) == 'table' and point.destination_id or '');
    local suffix = tonumber(destination_id:match(':(%d+)$')) or 0;
    if (suffix > 0) then ids[suffix] = true; end
    return ids;
end

local function action_catalogue(native_key, action)
    local points, seen = T{}, {};
    for _, point in ipairs(type(action) == 'table'
        and type(action.catalogue) == 'table' and action.catalogue or T{}) do
        local key = clean(point.destination_id);
        if (key ~= '' and not seen[key]) then
            seen[key] = true;
            points:append(deep_copy(point));
        end
    end
    -- Compact-v2 actions carry their complete catalogue snapshot.  An empty
    -- table is authoritative instruction-only state; never repopulate it from
    -- the independently cached legacy objective-destination graph.
    return points;
end

-- WHERE THE ROUTER'S OWN KNOWLEDGE LIVES.
--
-- A compact action carries a catalogue snapshot only when the builder could
-- resolve the target from that step alone. Usually it could not: 5,965 of the
-- 7,230 talk/trade/deliver/examine/use actions in the shipped progression
-- modules -- 82.5% -- carry `catalogue = {}`. Among them is
-- "mission:San d'Oria:5:step-011", Talk to Zantaviat, whose zone is implied by
-- the step before it rather than written on it. Identity matching consulted
-- only that snapshot, so for five of every six interaction steps in the game
-- the addon could not recognise the player interacting with the very target it
-- had just walked them to, and the step could never complete on its own.
--
-- The runtime has no such gap. It resolved Zantaviat to npc:v1:149:17388006
-- and routed the player to him; live 2026-08-22 `nav arrived name="Zantaviat"
-- zone=149`. This reads that same answer out of the same index the router
-- used. It never leaves the zone the signal came from, never accepts a name
-- the guide did not write on the step, and the caller still demands the exact
-- server id -- so it widens where identity is looked up, never what counts as
-- identity.
local function action_identity_points(action, zone_id)
    zone_id = tonumber(zone_id) or 0;
    if (type(action) ~= 'table' or zone_id <= 0) then return T{}; end
    local index = ensure_catalog_index ~= nil and ensure_catalog_index() or nil;
    if (type(index) ~= 'table' or type(index.points_by_zone_entity) ~= 'table') then
        return T{};
    end
    local names, seen, points = T{}, {}, T{};
    local function consider(value)
        local key = source_name_key(type(value) == 'table' and (value.name or value.target) or value);
        if (key ~= '' and seen[key] ~= true) then
            seen[key] = true;
            names:append(key);
        end
    end
    consider(action.target);
    for _, entry in ipairs(type(action.npcs) == 'table' and action.npcs or T{}) do consider(entry); end
    for _, entry in ipairs(type(action.objects) == 'table' and action.objects or T{}) do consider(entry); end
    -- Enemies too. Only fight actions carry any, so this is inert elsewhere,
    -- and it is what lets a step naming two enemies recognise the second one.
    for _, entry in ipairs(type(action.enemies) == 'table' and action.enemies or T{}) do consider(entry); end
    for _, name_key in ipairs(names) do
        for _, point in ipairs(index.points_by_zone_entity[('%d	%s'):fmt(zone_id, name_key)] or T{}) do
            points:append(point);
        end
    end
    return points;
end

local function point_matches_signal(point, signal, require_server_id)
    local expected_zone = tonumber(point.zone_id or point.zone) or 0;
    local actual_zone = tonumber(signal.zone_id) or 0;
    if (expected_zone <= 0 or actual_zone <= 0 or expected_zone ~= actual_zone) then
        return false;
    end
    local actual_id = tonumber(signal.target_server_id) or 0;
    local ids = catalogue_server_ids(point);
    local has_ids = next(ids) ~= nil;
    if (require_server_id and (actual_id <= 0 or not ids[actual_id])) then
        return false;
    end
    if (actual_id > 0 and has_ids and not ids[actual_id]) then return false; end
    local actual_name = clean(signal.target_name):lower();
    local expected_name = clean(point.target_name or point.name):lower();
    if (actual_name ~= '' and expected_name ~= '' and actual_name ~= expected_name) then
        return false;
    end
    return (not require_server_id) or actual_id > 0;
end

local function action_target_matches(native_key, action, signal, require_server_id)
    -- Use the same reviewed identity as routing. Some guide steps refer to a
    -- previous contact as "him", and some names belong to several actors.
    local binding = accessxi.nav_step_target_binding(action.step_id);
    if (binding ~= nil and clean(binding.destination_id) ~= '') then
        local index = ensure_catalog_index();
        local key = ('%d\t%s'):fmt(binding.zone, source_name_key(binding.target));
        for _, point in ipairs(index.points_by_zone_entity[key] or T{}) do
            if (clean(point.destination_id) == binding.destination_id
                and point_matches_signal(point, signal, require_server_id)) then
                return true, point;
            end
        end
        return false, nil;
    end
    local catalogue = action_catalogue(native_key, action);
    for _, point in ipairs(catalogue) do
        if (point_matches_signal(point, signal, require_server_id)) then
            return true, point;
        end
    end
    -- A populated snapshot stays authoritative: if it lists points and none of
    -- them is what the player touched, that is a real mismatch and the answer
    -- is no. Only the empty case -- the overwhelming majority -- falls through
    -- to the router's index.
    if (#catalogue == 0) then
        for _, point in ipairs(action_identity_points(action, signal.zone_id)) do
            if (point_matches_signal(point, signal, require_server_id)) then
                return true, point;
            end
        end
    end
    return false, nil;
end

local function enemy_action_matches(native_key, action, signal)
    local actual_name = clean(signal.target_name):lower();
    local actual_zone = tonumber(signal.zone_id) or 0;
    if ((tonumber(signal.target_server_id) or 0) <= 0
        or actual_name == '' or actual_zone <= 0) then return false; end
    local named = clean(action.target):lower() == actual_name
        or action_name_matches(action.enemies, actual_name);
    if (not named) then return false; end
    -- Enemy server IDs are individual live spawns; the rooted catalogue may
    -- contain only the sampled members of the exact named camp.  Native 0x029
    -- credit therefore proves the current enemy by exact name plus an exact
    -- catalogue zone, while NPC/object interactions still require a listed
    -- server ID.
    local catalogue = action_catalogue(native_key, action);
    for _, point in ipairs(catalogue) do
        if ((tonumber(point.zone_id or point.zone) or 0) == actual_zone
            and clean(point.target_name or point.name):lower() == actual_name) then
            return true;
        end
    end
    -- AN EMPTY SNAPSHOT IS NOT A DENIAL.
    --
    -- action_target_matches has fallen through to the router's index since the
    -- Zantaviat fix; this did not, and a fight action almost never carries a
    -- catalogue -- the shipped Assault kill steps ship catalogue = {} exactly as
    -- the reviewed overrides do. So enemy matching answered "no" for every kill
    -- objective it was ever asked about. The safety here is stronger than for
    -- interactions, not weaker: the caller has already required the signal's
    -- name to be one the guide wrote on this step, and the point must still
    -- carry the signal's exact zone and exact name.
    if (#catalogue == 0) then
        for _, point in ipairs(action_identity_points(action, actual_zone)) do
            if ((tonumber(point.zone_id or point.zone) or 0) == actual_zone
                and clean(point.target_name or point.name):lower() == actual_name) then
                return true;
            end
        end
    end
    return false;
end

local function action_future_boundary(native_key, action)
    local kind = clean(action.target_kind):lower();
    local relationship = clean(action.relationship):lower();
    local action_name = clean(action.action):lower();
    if (action_name == 'wait' or clean(action.target) == ''
        or kind == 'transport' or relationship == 'use-transport') then
        return true;
    end
    local groups, destinations, count = {}, {}, 0;
    for _, point in ipairs(action_catalogue(native_key, action)) do
        count = count + 1;
        groups[clean(point.group_id)] = true;
        destinations[clean(point.destination_id)] = true;
        if (clean(point.transport_id) ~= '' or clean(point.battlefield_id) ~= '') then
            return true;
        end
    end
    local group_count = 0;
    for group in pairs(groups) do if group ~= '' then group_count = group_count + 1; end end
    local destination_count = 0;
    for destination in pairs(destinations) do
        if (destination ~= '') then destination_count = destination_count + 1; end
    end
    return count == 0 or group_count > 1 or destination_count > 1;
end

local function reducer_active_objectives()
    local result, seen = T{}, {};
    for _, category in ipairs(T{ 'mission', 'quest' }) do
        for _, item in ipairs(accessxi.nav_mission_quest_active_items(category)) do
            local native_key = clean(item.objective_native_key);
            if (native_key ~= '' and not seen[native_key]) then
                local action, actions, revision, record = progression_cursor(native_key, item);
                if (type(actions) == 'table' and type(action) == 'table') then
                    local index = action_index_by_identity(actions, action.step_id,
                        action.step_order, action.action_id, action.action_order);
                    if (index ~= nil) then
                        seen[native_key] = true;
                        result:append({
                            category = category, native_key = native_key, item = item,
                            action = action, actions = actions, revision = revision,
                            record = record, index = index,
                        });
                    end
                end
            end
        end
    end
    return result;
end

local function objective_current_count(objective)
    local action = type(objective) == 'table'
        and type(objective.actions) == 'table'
        and objective.actions[tonumber(objective.index) or 0] or nil;
    if (type(action) == 'table' and type(objective.record) == 'table'
        and clean(objective.record.action_id) == clean(action.action_id)) then
        return tonumber(objective.record.progress_count) or 0;
    end
    return 0;
end

local function objective_match_snapshot(match)
    local objective = type(match) == 'table' and match.objective or nil;
    local current = type(objective) == 'table'
        and objective.actions[tonumber(objective.index) or 0] or nil;
    local matched = type(objective) == 'table'
        and objective.actions[tonumber(match.index) or 0] or nil;
    if (type(current) ~= 'table' or type(matched) ~= 'table') then return nil; end
    return {
        category = clean(objective.category):lower(),
        native_key = clean(objective.native_key),
        revision = clean(objective.revision),
        current_index = tonumber(objective.index),
        current_step_id = clean(current.step_id),
        current_action_id = clean(current.action_id),
        current_count = objective_current_count(objective),
        match_index = tonumber(match.index),
        match_step_id = clean(matched.step_id),
        match_action_id = clean(matched.action_id),
    };
end

local function revalidated_objective_match(snapshot, objectives)
    if (type(snapshot) ~= 'table') then return nil; end
    for _, objective in ipairs(type(objectives) == 'table' and objectives or T{}) do
        local current = objective.actions[objective.index];
        local matched = objective.actions[tonumber(snapshot.match_index) or 0];
        if (clean(objective.category):lower() == clean(snapshot.category):lower()
            and clean(objective.native_key) == clean(snapshot.native_key)
            and clean(objective.revision) == clean(snapshot.revision)
            and tonumber(objective.index) == tonumber(snapshot.current_index)
            and type(current) == 'table'
            and clean(current.step_id) == clean(snapshot.current_step_id)
            and clean(current.action_id) == clean(snapshot.current_action_id)
            and objective_current_count(objective) == tonumber(snapshot.current_count)
            and type(matched) == 'table'
            and clean(matched.step_id) == clean(snapshot.match_step_id)
            and clean(matched.action_id) == clean(snapshot.match_action_id)) then
            return { objective = objective, index = tonumber(snapshot.match_index) };
        end
    end
    return nil;
end

local function objective_signal_revision_matches(signal, objective)
    local supplied = clean(signal.progression_revision);
    return supplied == '' or supplied == clean(objective.revision);
end

local function objective_cause_id(signal)
    local explicit = clean(signal.causal_id);
    if (explicit ~= '') then return clean(signal.kind) .. ':' .. explicit; end
    local kind = clean(signal.kind):lower();
    if (kind == 'kill-credit') then
        return table.concat({ kind, tostring(tonumber(signal.message_id) or 0),
            tostring(tonumber(signal.target_server_id) or 0),
            tostring(tonumber(signal.battle_sequence) or 0) }, ':');
    elseif (kind == 'inventory-delta') then
        return table.concat({ kind, tostring(tonumber(signal.inventory_sequence) or 0),
            clean(signal.item_name):lower(), tostring(tonumber(signal.before_count) or 0),
            tostring(tonumber(signal.after_count) or 0) }, ':');
    elseif (kind == 'key-item-delta') then
        return table.concat({ kind, tostring(tonumber(signal.sequence) or 0),
            tostring(tonumber(signal.key_item_id) or 0),
            tostring(signal.before_owned == true), tostring(signal.after_owned == true) }, ':');
    end
    return table.concat({ kind, tostring(tonumber(signal.sequence) or 0),
        tostring(tonumber(signal.target_server_id) or 0),
        tostring(tonumber(signal.event_id or signal.menu_id) or 0) }, ':');
end

local function remember_objective_cause(cause)
    if (cause == '' or accepted_objective_causes[cause]) then return false; end
    accepted_objective_causes[cause] = true;
    accepted_objective_cause_order[#accepted_objective_cause_order + 1] = cause;
    while #accepted_objective_cause_order > objective_cause_limit do
        local expired = table.remove(accepted_objective_cause_order, 1);
        accepted_objective_causes[expired] = nil;
    end
    return true;
end

local function remember_pending_objective_event(arm_key, arm)
    if (arm_key == '' or type(arm) ~= 'table'
        or pending_objective_events[arm_key] ~= nil) then return false; end
    pending_objective_events[arm_key] = arm;
    pending_objective_event_order[#pending_objective_event_order + 1] = arm_key;
    while #pending_objective_event_order > objective_event_arm_limit do
        local expired = table.remove(pending_objective_event_order, 1);
        pending_objective_events[expired] = nil;
    end
    return true;
end

local function remove_pending_objective_event(arm_key)
    pending_objective_events[arm_key] = nil;
    for index = #pending_objective_event_order, 1, -1 do
        if pending_objective_event_order[index] == arm_key then
            table.remove(pending_objective_event_order, index);
        end
    end
end

local function purge_objective_arms(native_key)
    native_key = clean(native_key);
    if (native_key == '') then return; end
    local remove_keys = T{};
    for arm_key, arm in pairs(pending_objective_events) do
        for _, snapshot in ipairs(type(arm) == 'table'
            and type(arm.matches) == 'table' and arm.matches or T{}) do
            if (clean(snapshot.native_key) == native_key) then
                remove_keys:append(arm_key);
                break;
            end
        end
    end
    for _, arm_key in ipairs(remove_keys) do remove_pending_objective_event(arm_key); end
    if (type(pending_objective_transport) == 'table'
        and type(pending_objective_transport.match) == 'table'
        and clean(pending_objective_transport.match.native_key) == native_key) then
        pending_objective_transport = nil;
    end
end

local function cancel_completed_objective_route(objective, through_index)
    local point = type(accessxi.nav_destination) == 'table' and accessxi.nav_destination
        or (type(accessxi.nav_zone_search_target) == 'table'
            and accessxi.nav_zone_search_target or nil);
    if (type(point) ~= 'table'
        or clean(point.objective_native_key) ~= clean(objective.native_key)) then
        return false;
    end
    local route_action = clean(point.objective_action_id);
    local route_index = nil;
    for index, action in ipairs(objective.actions) do
        if (clean(action.action_id) == route_action) then route_index = index; break; end
    end
    if (route_index == nil or route_index > through_index
        or type(accessxi.nav_cancel_mission_quest_route) ~= 'function') then
        return false;
    end
    local ok, cancelled = pcall(
        accessxi.nav_cancel_mission_quest_route,
        'objective-progression-completed');
    return ok and cancelled == true;
end

-- THE PLAYER IS THE AUTHORITY ON WHAT THEY HAVE DONE.
--
-- Automatic completion is evidence-based and will sometimes miss: live
-- 2026-08-22 the player talked to Zantaviat -- catalogue id and live server id
-- both 17388006 -- and nothing fired, so two minutes later the objective still
-- read "Talk to the NPC Zantaviat just inside the zone" for a step already
-- finished. With no way to say "I did that", the mission was simply stuck:
-- every route led back to an NPC with nothing left to say.
--
-- A miss in the detector must never become a dead end. This marks the current
-- step done on the player's word and moves to the next one, which is the same
-- advance the detector performs -- no shortcut, no state the game does not
-- already have, and nothing walked for them.
-- WHICH OBJECTIVE DOES THE PLAYER MEAN.
--
-- Live 2026-08-28: the player scrolled the mission list to "The Rites of Life"
-- (Chains of Promathia), pressed N, and the addon advanced "Smash the Orcish
-- Scouts" instead. Twice. Their words: "I press n but I don't know if it
-- updated the right mission or not."
--
-- The old code read the selected row, kept only its objective_kind -- the
-- string "mission" -- and handed THAT to mark_step_done, which then walked the
-- active list and took the first entry of that kind. The identity was in hand
-- one line before it was needed and was thrown away, so a player on row 13
-- moved row 1. Because the reducer lists missions before quests, an empty kind
-- could only ever hit a mission; a quest was unreachable by that path.
--
-- One resolver, so this decision is made in exactly one place and can be tested
-- on its own (sol). Order is most-explicit-first:
--   guide   -- the guide is open on a specific objective; that is unambiguous
--   browser -- the highlighted row, which is what the player is listening to
--   sole    -- only one objective is active, so there is nothing to confuse
-- and otherwise a refusal that says what to do, never a guess. A wrong guess is
-- unrecoverable in a way a refusal is not: the cursor only moves forward.
--
-- NOTE the browse list has no close. accessxi.nav_menu_open is never assigned
-- true anywhere in the tree and nav_close_menu has no callers, so the row the
-- player last moved to persists until they zone. That makes the browser tier
-- reliable rather than stale -- it is the real UI state, not a memory of one.
function accessxi.nav_objective_intent(operation)
    operation = clean(operation);
    local guides = accessxi.objective_guides;
    if (type(guides) == 'table' and type(guides.current_native_key) == 'function') then
        local ok, key = pcall(guides.current_native_key, guides);
        if (ok and clean(key) ~= '') then
            return clean(key), 'guide', '';
        end
    end

    local items = accessxi.nav_menu_items;
    local index = tonumber(accessxi.nav_menu_index) or 0;
    if (type(items) == 'table' and index >= 1) then
        local selected = items[index];
        if (type(selected) == 'table') then
            local kind = clean(selected.objective_kind or selected.kind):lower();
            local key = clean(selected.objective_native_key);
            if (kind == 'mission' or kind == 'quest') then
                if (key ~= '') then
                    return key, 'browser', '';
                end
            else
                -- A destination or camp row is highlighted. Refusing is right:
                -- falling through to "the only active objective" would move a
                -- mission the player is demonstrably not looking at.
                return '', '', 'The selected row is not a mission or quest. Open Missions or Quests, select one, then try again.';
            end
        end
    end

    local objectives = reducer_active_objectives();
    if (#objectives == 1) then
        return clean(objectives[1].native_key), 'sole-active', '';
    end
    if (#objectives == 0) then
        return '', '', 'No active mission or quest step to mark.';
    end
    return '', '', 'I cannot tell which objective you mean. Open Missions or Quests, select it, then try again.';
end

-- How an objective should be named out loud. A sighted player sees the
-- highlighted row; this is that row rendered in speech.
function accessxi.nav_objective_spoken_title(objective)
    if (type(objective) ~= 'table') then return ''; end
    local item = type(objective.item) == 'table' and objective.item or {};
    local title = clean(item.name);
    if (title == '') then
        title = clean(accessxi.objective_title_for_native_key ~= nil
            and accessxi.objective_title_for_native_key(objective.native_key) or '');
    end
    local context = clean(item.mission_context);
    if (context == '') then context = clean(item.quest_area); end
    if (context ~= '' and title ~= '' and context ~= title) then
        return ('%s. %s'):fmt(context, title);
    end
    return title ~= '' and title or clean(objective.native_key);
end

function accessxi.nav_mission_quest_mark_step_done(category, native_key)
    category = clean(category):lower();
    native_key = clean(native_key);

    -- The caller is expected to say WHICH objective. When it does not, resolve
    -- the player's intent here rather than taking the head of the list.
    local source = 'caller';
    if (native_key == '') then
        local explanation;
        native_key, source, explanation = accessxi.nav_objective_intent('mark-step-done');
        native_key = clean(native_key);
        if (native_key == '') then
            log_line(('objective mark refused reason="%s"'):fmt(clean(explanation)));
            return false, clean(explanation) ~= '' and clean(explanation)
                or 'I cannot tell which objective you mean.';
        end
    end

    local objectives = reducer_active_objectives();
    if (#objectives == 0) then
        return false, 'No active mission or quest step to mark.';
    end

    -- Re-resolve the key against the live list; never act on a remembered
    -- objective table, which may have advanced since it was captured (sol).
    local chosen = nil;
    for _, objective in ipairs(objectives) do
        if (clean(objective.native_key) == native_key) then
            chosen = objective;
            break;
        end
    end
    if (chosen == nil) then
        log_line(('objective mark refused native="%s" source="%s" reason=not-active'):fmt(
            native_key, source));
        return false, 'That objective has no step to mark right now.';
    end

    -- A MISSION YOU HAVE NOT ACCEPTED HAS NO STEP TO MARK.
    --
    -- The active list carries missions that are merely AVAILABLE TO START as
    -- well as the one the player is on -- that is right for browsing, because
    -- finding a mission to begin is the reason to open the list. It is wrong
    -- for marking progress: there is no progress on a mission the game does not
    -- think you have started.
    --
    -- Live 2026-08-28 this is what made the damage invisible. N advanced
    -- "Smash the Orcish Scouts" twice; the player had never accepted it, and an
    -- available mission's row always speaks its acceptance step -- "Speak to any
    -- San d'Orian Gate Guard to begin this Mission" -- whatever the saved cursor
    -- says. So the store moved to step-007 and the row never changed a word.
    -- The player: "I never started the mission so I noticed it didn't actually
    -- update the steps even when I pressed n."
    --
    -- A cursor written here would have surfaced later, the moment they accepted
    -- the mission, as a jump into the middle of it.
    if (clean(type(chosen.item) == 'table'
        and chosen.item.mission_availability or '') == 'available-to-start') then
        local unstarted = accessxi.nav_objective_spoken_title(chosen);
        log_line(('objective mark refused native="%s" source="%s" reason=not-accepted'):fmt(
            native_key, source));
        -- Named first, the same shape as a successful mark, so the two are
        -- heard the same way round.
        return false, unstarted ~= ''
            and ('%s. You have not started this yet, so there is no step to mark.'):fmt(unstarted)
            or 'You have not started that mission yet, so there is no step to mark.';
    end
    local action = chosen.actions[chosen.index];
    if (type(action) ~= 'table') then
        return false, 'That objective has no current step.';
    end
    local finished = clean(action.instruction);
    if (not advance_objective_match(chosen, chosen.index, 1, 'player')) then
        return false, 'That step could not be marked done.';
    end
    if (type(notify_objective_progress) == 'function') then
        notify_objective_progress(T{ chosen });
    end
    local following = chosen.actions[chosen.index + 1];

    -- RECORD THE MOVE SO IT CAN BE TAKEN BACK.
    --
    -- This is the only cursor write a player makes by hand, and the only one
    -- that can be wrong about WHICH objective it moved. Everything else is
    -- driven by evidence from the game. The journal row carries the state
    -- before and after, because the cursor is monotonic -- resolved_progress_record
    -- keeps the FARTHEST record it can find, so a reversal has to remove the
    -- history entry rather than write an earlier one.
    accessxi.objective_progress_mark_serial =
        (tonumber(accessxi.objective_progress_mark_serial) or 0) + 1;
    local event_id = ('%d-%d'):fmt(os.time(), accessxi.objective_progress_mark_serial);
    if (type(following) == 'table') then
        objective_progress_marks[#objective_progress_marks + 1] = {
            identity = character_identity(),
            world_id = player_world_id(),
            native_key = clean(chosen.native_key),
            event_id = event_id,
            after_step_id = clean(following.step_id),
            after_action_id = clean(following.action_id),
            before_step_id = clean(action.step_id),
            before_action_id = clean(action.action_id),
        };
        accessxi.objective_progress_append_row({
            'v3-mark', character_identity(), tostring(player_world_id()),
            clean(chosen.native_key), event_id,
            clean(following.step_id), clean(following.action_id),
            clean(action.step_id), clean(action.action_id),
        });
    end

    log_line(('objective step marked done by player native="%s" source="%s" step="%s" action="%s" event="%s"'):fmt(
        clean(chosen.native_key), source, clean(action.step_id),
        clean(action.action_id), event_id));

    local next_text = type(following) == 'table' and clean(following.instruction) or '';

    -- NAME THE OBJECTIVE, ALWAYS.
    --
    -- The player pressed N on the Chains of Promathia row, the addon moved
    -- Smash the Orcish Scouts, and said only "Marked done: <step>." -- a
    -- sentence with no owner. They could not tell it had gone to the wrong
    -- mission, and said so: "I don't know if it updated the right mission or
    -- not." A sighted player sees which row is highlighted; naming it is that
    -- row rendered in speech. Unconditional, even when unambiguous: N is a
    -- rare, state-changing recovery action and being able to audit it matters
    -- more than the words it costs (sol).
    local title = accessxi.nav_objective_spoken_title(chosen);
    local spoken = finished ~= '' and ('Marked done: %s.'):fmt(finished) or 'Step marked done.';
    if (title ~= '') then
        spoken = ('%s. %s'):fmt(title, spoken);
    end
    if (next_text ~= '') then
        spoken = spoken .. (' Next: %s. Press I when ready.'):fmt(next_text);
    else
        spoken = spoken .. ' That was the last step recorded for this objective.';
        -- And what the guide says past that point, which is where the answer
        -- lives for any mission whose compact actions stop early. Below the
        -- Arks stops at the Hall of Transference; BG Wiki goes on to say the
        -- three Promyvions still have to be cleared.
        local continuation = accessxi.objective_guide_postlude_text(
            clean(chosen.native_key), chosen.actions);
        if (clean(continuation) ~= '') then
            spoken = ('%s %s'):fmt(spoken, clean(continuation));
        end
    end
    spoken = spoken .. ' Say slash axi undo to take that back.';
    return true, spoken;
end

-- TAKE BACK THE LAST STEP THE PLAYER MARKED DONE.
--
-- Necessary because the cursor is monotonic and nothing else can move one
-- backwards. resolved_progress_record scans the whole saved history and keeps
-- the farthest valid record; save_objective_progress has no ordering guard but
-- writing an earlier row changes nothing, because the later row is still in the
-- history and still wins. advance_objective_match(-1) is worse than useless --
-- for a single-count step it discards the delta and advances FORWARD.
--
-- So the reversal is recorded, not erased: an undo row names the mark it
-- reverses, and the loader drops that mark's cursor row from the history it
-- builds. "Farthest wins" then falls back to the truth on its own, and it
-- survives a reload because the progress file is append-only.
--
-- Global rather than per-objective, deliberately. The failure this exists for
-- moved an objective the player was NOT looking at, so "undo on the selected
-- objective" could not have repaired it (sol).
function accessxi.nav_objective_undo_last_mark()
    load_objective_progress();
    local identity = character_identity();
    local world_id = player_world_id();
    if (identity == '' or world_id <= 0) then
        return false, 'I cannot tell which character this is yet.';
    end
    local mark = nil;
    for index = #objective_progress_marks, 1, -1 do
        local candidate = objective_progress_marks[index];
        if (type(candidate) == 'table'
            and clean(candidate.identity):lower() == clean(identity):lower()
            and (tonumber(candidate.world_id) or 0) == world_id
            and objective_progress_undone[candidate.event_id] ~= true) then
            mark = candidate;
            break;
        end
    end
    if (mark == nil) then
        return false, 'There is nothing to undo. No step has been marked done by hand.';
    end

    if (not accessxi.objective_progress_append_row({
        'v3-undo', clean(mark.identity), tostring(mark.world_id),
        clean(mark.native_key), clean(mark.event_id),
    })) then
        return false, 'That could not be undone; the progress file could not be written.';
    end
    objective_progress_undone[mark.event_id] = true;

    -- Drop the row the mark wrote, in memory as well as on disk, or the
    -- farthest-wins scan keeps returning it until the next reload.
    local key = objective_progress_key(clean(mark.identity):lower(),
        mark.world_id, clean(mark.native_key));
    local kept = {};
    for _, candidate in ipairs(objective_progress_history[key] or {}) do
        if (clean(candidate.step_id) ~= clean(mark.after_step_id)
            or clean(candidate.action_id) ~= clean(mark.after_action_id)) then
            kept[#kept + 1] = candidate;
        end
    end
    objective_progress_history[key] = kept;
    objective_progress[key] = nil;
    increment_objective_progress_revision();

    local title = clean(accessxi.objective_title_for_native_key ~= nil
        and accessxi.objective_title_for_native_key(mark.native_key) or '');
    if (title == '') then title = clean(mark.native_key); end
    log_line(('objective mark UNDONE native="%s" event="%s" back-to step="%s" action="%s"'):fmt(
        clean(mark.native_key), clean(mark.event_id),
        clean(mark.before_step_id), clean(mark.before_action_id)));
    return true, ('Undone. %s is back on the step before it.'):fmt(title);
end

-- TALKING TO AN NPC THAT HAS NO MENU.
--
-- Live 2026-08-22: the player talked to Zantaviat -- catalogue id and live
-- server id both 17388006, an exact match -- and nothing completed, so two
-- minutes later the objective still read "Talk to the NPC Zantaviat just
-- inside the zone" for a step already finished and every route led back to an
-- NPC with nothing left to say. The existing completion path keys on an event
-- menu closing; a one-line dialogue never opens one.
--
-- sol's ruling for this case, and the bar these two functions meet: require an
-- OUTGOING interaction aimed at the exact server id, then an attributable NPC
-- response shortly after. Never complete from rendered chat text, or from an
-- NPC's name, alone -- either by itself would fire on someone else's
-- conversation or on ambient dialogue the player walked past.

-- The player pressed enter on something. If the step they are on is a talk at
-- exactly that creature, remember it; nothing completes yet.
function accessxi.nav_mission_quest_note_talk_intent(target_server_id, zone_id, now)
    target_server_id = tonumber(target_server_id) or 0;
    zone_id = tonumber(zone_id) or 0;
    -- An identity signal missing its zone matches NOTHING, silently, forever --
    -- and that is observationally identical in the log to the packet never
    -- arriving. Live 2026-08-22 those two readings cost a whole iteration, so
    -- say which one it is (sol).
    if (target_server_id > 0 and zone_id <= 0) then
        log_line(('objective talk arm rejected reason=missing-zone target=%d'):fmt(
            target_server_id));
        return false;
    end
    if (target_server_id <= 0 or zone_id <= 0) then
        return false;
    end
    now = tonumber(now) or 0;
    for _, objective in ipairs(reducer_active_objectives()) do
        local action = objective.actions[objective.index];
        -- The interaction test is inlined: `interaction_action` is a local
        -- declared further down this file, so referencing it from here would
        -- silently resolve to a nil global and throw on the first NPC talk.
        local verb = type(action) == 'table' and clean(action.action):lower() or '';
        local is_interaction = verb == 'talk' or verb == 'trade' or verb == 'deliver'
            or verb == 'examine' or verb == 'use';
        if (is_interaction) then
            local matched, point = action_target_matches(objective.native_key, action,
                { target_server_id = target_server_id, zone_id = zone_id }, true);
            if (matched) then
                -- `target_name` on a snapshot point, `name` on a catalogue
                -- point -- the same field under two names, and the matcher
                -- already reads both. Reading only the first left the armed
                -- name blank, and completion compares the speaker against it,
                -- so the reply could never be attributed and the step could
                -- never close.
                local name = clean(type(point) == 'table'
                    and (point.target_name or point.name) or '');
                if (name == '') then name = clean(action.target); end
                -- Count how many indexed places carry the names this
                -- action gives, so an unanswered attempt can say whether
                -- there is anywhere else to try.
                local siblings = 0;
                for _ in ipairs(action_identity_points(action, zone_id)) do
                    siblings = siblings + 1;
                end
                local previous = accessxi.nav_objective_talk_intent;
                local attempts = 1;
                if (type(previous) == 'table'
                    and tonumber(previous.target_server_id) == target_server_id
                    and previous.answered ~= true) then
                    attempts = (tonumber(previous.attempts) or 1) + 1;
                end
                accessxi.nav_objective_talk_intent = {
                    target_server_id = target_server_id,
                    name = name,
                    native_key = objective.native_key,
                    action_id = clean(action.action_id),
                    tick = now,
                    attempts = attempts,
                    siblings = siblings,
                    answered = false,
                    spoken_attempt = 0,
                };
                log_line(('objective talk armed target=%d zone=%d name="%s" step="%s"'):fmt(
                    target_server_id, zone_id, name, clean(action.step_id)));
                return true;
            end
        end
    end
    return false;
end

-- A TARGET THAT DOES NOT ANSWER MUST BE REPORTED.
--
-- Live 2026-08-23 in Norg the player pressed enter on an Oaken Door three
-- times over eleven seconds. Three 0x001A triggers went out; no 0x0032 or
-- 0x0034 ever came back, so the door did nothing at all. A sighted player sees
-- that plainly -- no cutscene, no dialogue, nothing. We said NOTHING, and went
-- on repeating "examine the Oaken Door", which is why the player concluded the
-- step had not updated. Not receiving the information is the failure here.
--
-- Response is NOT completion (sol): 0x0032/0x0034 open an event, menu or
-- cutscene, and shops, repeatable dialogue and cancelled events all produce
-- them. So this reports silence and nothing else -- it never advances a step,
-- and it never switches target on the player's behalf.
function accessxi.nav_mission_quest_note_interaction_response(target_server_id, now)
    local armed = accessxi.nav_objective_talk_intent;
    if (type(armed) ~= 'table'
        or tonumber(armed.target_server_id) ~= (tonumber(target_server_id) or 0)) then
        return false;
    end
    armed.answered = true;
    return true;
end

-- Returns the text to speak once a triggered target has stayed silent, or nil.
-- Four seconds: a working reply lands in about one (measured against Pacomart,
-- Naillina and Zantaviat, all of whom answered within 1-3 seconds).
function accessxi.nav_mission_quest_unanswered_talk(now)
    local armed = accessxi.nav_objective_talk_intent;
    now = tonumber(now) or 0;
    if (type(armed) ~= 'table' or armed.answered == true) then return nil; end
    local attempts = tonumber(armed.attempts) or 1;
    if ((now - (tonumber(armed.tick) or 0)) < 4000
        or (tonumber(armed.spoken_attempt) or 0) >= attempts) then
        return nil;
    end
    armed.spoken_attempt = attempts;
    local name = clean(armed.name);
    if (name == '') then name = 'That target'; end
    local siblings = tonumber(armed.siblings) or 0;
    if (attempts <= 1) then
        return ('%s did not respond.'):fmt(name);
    end
    if (siblings > 1) then
        -- OFFER, NEVER SWITCH (sol). Choosing for them is how they spent the
        -- last three minutes on a door that was never going to answer.
        return ('%s still has not responded. %d places with that name are indexed here. Press I to choose another.')
            :fmt(name, siblings);
    end
    return ('%s still has not responded.'):fmt(name);
end

-- NPC DIALOGUE ARRIVES ON MORE THAN ONE CHANNEL, AND WE ONLY WATCHED ONE.
--
-- Live 2026-08-23, The Davoi Report: the player routed to Zantaviat, pressed
-- enter, the talk armed against step-011, and one second later he answered --
--
--   chat text mode=144 "Zantaviat : According to our man, the page lies
--   somewhere near the platform on the small pond up ahead."
--
-- The step did not advance. They talked to him five more times; the same line
-- arrived five more times. The completion path is only ever reached for modes
-- 150 and 151, so an attributable reply on 144 was discarded before it got
-- there. The day before, the same NPC's FIRST conversation came through on 150
-- and completed normally -- event dialogue and ordinary NPC speech are
-- different channels, and a step can be answered on either.
--
-- 144 and 150 are the speaker-attributed NPC channels: every 144 line in the
-- log is an NPC ("Ju Kamja : We can deliver goods...", "Moogle : Is my
-- assistance reaching you, Master?"), never a player. 148 and 151 carry system
-- text with no speaker and are deliberately absent, as are the player channels
-- -- say, shout, tell -- where a person could be named after an NPC.
--
-- The rule lives here rather than in the reader so it can be tested at all.
local NPC_DIALOGUE_MODES = { [144] = true, [150] = true };

function accessxi.nav_mission_quest_dialogue_mode(mode)
    return NPC_DIALOGUE_MODES[tonumber(mode) or -1] == true;
end

-- An NPC said something. Only the creature the player just pressed enter on,
-- only within a few seconds, and only while that step is still the current one.
function accessxi.nav_mission_quest_note_talk_response(speaker, now)
    local armed = accessxi.nav_objective_talk_intent;
    if (type(armed) ~= 'table') then
        return false;
    end
    now = tonumber(now) or 0;
    if ((now - (tonumber(armed.tick) or 0)) > 10000) then
        accessxi.nav_objective_talk_intent = nil;
        return false;
    end
    speaker = clean(speaker);
    if (speaker == '' or clean(armed.name) == ''
        or speaker:lower() ~= clean(armed.name):lower()) then
        return false;
    end
    for _, objective in ipairs(reducer_active_objectives()) do
        if (objective.native_key == armed.native_key) then
            local action = objective.actions[objective.index];
            if (type(action) == 'table' and clean(action.action_id) == armed.action_id) then
                -- Consume the evidence only once it has actually been spent.
                -- Clearing first threw the arm away whenever the advance could
                -- not be saved, so a talk that failed to record was gone for
                -- good and the player had no second chance at it.
                if (not advance_objective_match(objective, objective.index, 1)) then
                    return false;
                end
                accessxi.nav_objective_talk_intent = nil;
                if (type(notify_objective_progress) == 'function') then
                    notify_objective_progress(T{ objective });
                end
                log_line(('objective interaction completed kind=%s native="%s" step="%s" action="%s" reason="%s"'):fmt(
                    clean(objective.category), clean(objective.native_key),
                    clean(action.step_id), clean(action.action_id), 'talk-response'));
                return true;
            end
        end
    end
    return false;
end

advance_objective_match = function(objective, match_index, causal_units, proof)
    local action = objective.actions[match_index];
    if (type(action) ~= 'table' or match_index < objective.index) then return false; end
    if (clean(action.completion_evidence) ~= '' and proof ~= 'acquisition'
        and proof ~= 'player') then return false; end
    local required = tonumber(action.required_count) or 1;
    local mode = clean(action.count_mode):lower();
    local current_count = 0;
    if (match_index == objective.index and type(objective.record) == 'table'
        and clean(objective.record.action_id) == clean(action.action_id)) then
        current_count = tonumber(objective.record.progress_count) or 0;
    end
    local added = mode == 'single' and required or math.max(0, tonumber(causal_units) or 0);
    if (added <= 0) then return false; end
    local count = math.min(required, current_count + added);
    local saved = false;
    if (count >= required and match_index < #objective.actions) then
        saved = save_cursor_action(
            objective.native_key, objective.actions[match_index + 1], 0, objective.revision);
    else
        saved = save_cursor_action(objective.native_key, action, count, objective.revision);
    end
    if (not saved) then return false; end
    objective.completed_index = match_index;
    purge_objective_arms(objective.native_key);
    -- Remember whether the route we stopped was THIS objective's, so the
    -- announcement can say "Navigation stopped" only when it truly was --
    -- cancel_completed_objective_route already refuses to touch an unrelated
    -- route, and its answer is the one the sentence needs.
    accessxi.nav_objective_route_stopped =
        cancel_completed_objective_route(objective, match_index);
    return true;
end;

-- A STEP THAT COMPLETES IS AN EVENT, AND EVENTS ARE SPOKEN.
--
-- This function used to mark the menu dirty and stop. The whole mission chain
-- moved in silence: the row changed underneath the player and the only way to
-- learn anything was to open the menu and arrow to it.
notify_objective_progress = function(objectives)
    local first = objectives[1];
    if (type(first) ~= 'table') then return; end
    if (type(accessxi.objective_announce) == 'function'
        and type(accessxi.objective_announcer) == 'table') then
        pcall(function ()
            local announcer = accessxi.objective_announcer;
            local completed_index = tonumber(first.completed_index) or first.index;
            local completed = first.actions[completed_index];
            local following = first.actions[completed_index + 1];
            local final = type(following) ~= 'table';
            local step_id = clean(type(following) == 'table' and following.step_id or '');
            local capability, zone_name, route_choice = accessxi.nav_mission_quest_step_route_capability(
                first.native_key, step_id);
            accessxi.objective_announce({
                type = final and announcer.TRANSITIONS.FINAL_OBJECTIVE
                    or announcer.TRANSITIONS.OBJECTIVE,
                -- What the guide still says once the compact actions run out.
                -- Empty for every other transition, and empty for an objective
                -- whose page really does end where its actions do.
                continuation = final and (accessxi.objective_guide_postlude_text(
                    clean(first.native_key), first.actions)) or '',
                category = clean(first.category),
                identity = character_identity(),
                mission_epoch = objective_session_epoch(),
                mission = clean(first.native_key),
                previous_mission = clean(first.native_key),
                step_id = step_id,
                previous_step_id = clean(type(completed) == 'table' and completed.step_id or ''),
                instruction = clean(type(following) == 'table' and following.instruction or ''),
                route = capability,
                zone_name = zone_name,
                route_choice = route_choice,
                -- Only a route that belonged to the step that just completed is
                -- stopped; an unrelated manual route survives untouched (sol).
                route_stopped = accessxi.nav_objective_route_stopped == true,
            });
        end);
    end
    accessxi.nav_objective_route_stopped = nil;
    if (type(accessxi.on_objective_interaction_progress_changed) == 'function') then
        pcall(accessxi.on_objective_interaction_progress_changed, first.category, false);
    end
end;

function accessxi.nav_mission_quest_recover_event_history(paths)
    local evidence = accessxi.objective_event_evidence;
    local identity = character_identity();
    local owner = identity .. ':' .. tostring(objective_session_epoch());
    if (type(evidence) ~= 'table' or identity == '' or player_world_id() <= 0
        or objective_session_epoch() <= 0
        or accessxi.nav_objective_history_owner == owner) then return 0; end
    local current = reducer_active_objectives();
    local relevant = false;
    for _,objective in ipairs(current) do
        if (evidence.get(objective.native_key)
            and clean(objective.item.mission_availability) == 'active') then
            relevant = true;
        end
    end
    if (not relevant) then return 0; end
    if (paths == nil) then
        local writer = accessxi.support_log;
        if (type(writer) ~= 'table' or clean(writer.path) == '') then return 0; end
        paths = { writer.previous, writer.path };
    end
    local proofs, scan = evidence.read_history(paths, identity);
    scan = type(scan) == 'table' and scan or {};
    log_line(('objective event history scan files=%d bytes=%d unreadable=%d truncated=%d proofs=%d'):fmt(
        tonumber(scan.files) or 0, tonumber(scan.bytes) or 0,
        tonumber(scan.unreadable) or 0, tonumber(scan.truncated) or 0, #proofs));
    local changed = T{};
    for _,proof in ipairs(proofs) do
        for _,objective in ipairs(current) do
            if (objective.native_key == proof.native_key
                and clean(objective.item.mission_availability) == 'active') then
                for index = objective.index, #objective.actions do
                    if (clean(objective.actions[index].action_id) == proof.action_id
                        and advance_objective_match(objective, index, 1, 'history')) then
                        changed:append(objective);
                        log_line(('objective event history recovered native="%s" step="%s" from="%s" target=%d event=%d'):fmt(
                            proof.native_key, proof.step_id, clean(objective.action.step_id),
                            proof.target_server_id, proof.event_id));
                    end
                end
            end
        end
    end
    accessxi.nav_objective_history_owner = owner;
    if (#changed > 0) then notify_objective_progress(changed); end
    return #changed;
end

local function interaction_action(action)
    local value = clean(action.action):lower();
    return value == 'talk' or value == 'trade' or value == 'deliver'
        or value == 'examine' or value == 'use';
end

local function interaction_matches(objectives, signal)
    local all, current = T{}, T{};
    for _, objective in ipairs(objectives) do
        if (objective_signal_revision_matches(signal, objective)) then
            for index = objective.index, #objective.actions do
                local action = objective.actions[index];
                if (interaction_action(action)) then
                    local evidence = accessxi.objective_event_evidence;
                    local reviewed = type(evidence) == 'table' and evidence.get(
                        objective.native_key, clean(action.action_id));
                    local reviewed_match = reviewed and evidence.match(
                        objective.native_key, clean(action.action_id), signal);
                    local matched, point = action_target_matches(
                        objective.native_key, action, signal, true);
                    if (matched and (not reviewed or reviewed_match)) then
                        local candidate = { objective = objective, index = index,
                            point = point, reviewed_event = type(reviewed_match) == 'table' };
                        all:append(candidate);
                        if (index == objective.index) then current:append(candidate); end
                    end
                end
            end
        end
    end
    if (#current > 0) then return current; end
    if (#all ~= 1) then return T{}; end
    local match = all[1];
    -- A reviewed stage event identifies the step the server is actually
    -- running, including when an earlier approach instruction had no signal.
    if (match.reviewed_event) then return T{ match }; end
    for index = match.objective.index, match.index - 1 do
        if (action_future_boundary(match.objective.native_key,
            match.objective.actions[index])) then
            return T{};
        end
    end
    return T{ match };
end

local function acquisition_action_matches(action, wanted, key_item)
    if (type(action) ~= 'table') then
        return false;
    end
    -- A step may name the acquisition that proves it, whatever its own action
    -- is. A battlefield fight is proved by the crest the battlefield grants,
    -- and that is the only evidence that cannot be satisfied by killing the
    -- wrong thing twice or by combining two separate attempts.
    local evidence = clean(action.completion_evidence):lower();
    if (evidence ~= '') then
        local prefix = key_item and 'key-item:' or 'item:';
        return evidence:sub(1, #prefix) == prefix
            and evidence:sub(#prefix + 1) == clean(wanted):lower();
    end
    if (clean(action.action):lower() ~= 'obtain'
        or clean(action.relationship):lower() ~= 'obtain-item') then
        return false;
    end
    local kind = clean(action.target_kind):lower();
    local values = key_item and action.key_items or action.items;
    if (action_name_matches(values, wanted)) then return true; end
    if (not key_item and action_name_matches(action.result_items, wanted)
        and clean(action.result_relation):lower():find('obtain', 1, true) ~= nil) then
        return true;
    end
    return clean(action.target):lower() == wanted
        and kind == (key_item and 'key-item' or 'item');
end

-- A counted action whose required count exactly equals its distinct item list
-- represents a collective set (for example the four Fetich pieces), not four
-- interchangeable copies.  The append-only cursor can safely persist the
-- number of distinct members proven by a complete native Inventory snapshot;
-- it must never derive that number from repeated positive deltas alone.
local function distinct_inventory_set_count(action)
    if (type(action) ~= 'table'
        or clean(action.count_mode):lower() ~= 'inventory-gain') then
        return nil, false;
    end
    local requirements, order = {}, T{};
    for _, entry in ipairs(type(action.items) == 'table' and action.items or T{}) do
        local name, count = objective_required_item(entry);
        local key = name:lower();
        if (key == '') then return nil, true; end
        if (requirements[key] == nil) then order:append(key); end
        requirements[key] = math.max(tonumber(requirements[key]) or 0, count);
    end
    if (#order <= 1) then return nil, false; end
    if ((tonumber(action.required_count) or 0) ~= #order
        or not objective_inventory_state_ready()
        or type(accessxi.objective_inventory_count_by_name) ~= 'function') then
        return nil, true;
    end
    local owned = 0;
    for _, key in ipairs(order) do
        local ok, count, item_id = pcall(accessxi.objective_inventory_count_by_name, key);
        if (not ok or tonumber(item_id) == nil or tonumber(count) == nil) then
            return nil, true;
        end
        if tonumber(count) >= requirements[key] then owned = owned + 1; end
    end
    return owned, true;
end

local function inventory_matches(objectives, signal, key_item)
    local all = T{};
    local wanted = clean(key_item and signal.key_item_name or signal.item_name):lower();
    if (wanted == '') then return T{}; end
    for _, objective in ipairs(objectives) do
        if (objective_signal_revision_matches(signal, objective)) then
            for index = objective.index, #objective.actions do
                if (acquisition_action_matches(objective.actions[index], wanted, key_item)) then
                    local candidate = { objective = objective, index = index };
                    all:append(candidate);
                end
            end
        end
    end
    -- Inventory and key-item evidence has no objective identity of its own.
    -- Even an exact current action is unsafe when the same canonical evidence
    -- also names a future action in this or another active objective.
    if (#all ~= 1) then return T{}; end
    local match = all[1];
    if (match.index == match.objective.index) then return T{ match }; end
    for index = match.objective.index, match.index - 1 do
        if (action_future_boundary(match.objective.native_key,
            match.objective.actions[index])) then
            return T{};
        end
    end
    return T{ match };
end

function accessxi.nav_mission_quest_reduce_signal(signal)
    local kind = clean(type(signal) == 'table' and signal.kind or ''):lower();
    if (kind == 'identity-loss') then
        pending_objective_events = {};
        pending_objective_event_order = {};
        pending_objective_transport = nil;
        pending_objective_interaction = nil;
        accepted_objective_causes = {};
        accepted_objective_cause_order = {};
        last_objective_battle_sequence = 0;
        return false;
    end
    if (not signal_owner_current(signal)) then return false; end
    local cause = objective_cause_id(signal);
    if (cause == '' or accepted_objective_causes[cause]) then return false; end

    if (kind == 'native-objective-state') then
        if (signal.scope_complete ~= true or clean(signal.previous_state):lower() ~= 'active'
            or (clean(signal.category):lower() ~= 'mission'
                and clean(signal.category):lower() ~= 'quest')) then
            return false;
        end
        local previous_key = clean(signal.previous_native_key);
        local current_key = clean(signal.current_native_key);
        local previous_actions, previous_revision = progression_actions(previous_key);
        if (type(previous_actions) ~= 'table') then return false; end
        local current_actions, current_revision = nil, '';
        if (clean(signal.current_state):lower() == 'replaced') then
            current_actions, current_revision = progression_actions(current_key);
            if (type(current_actions) ~= 'table') then return false; end
        elseif (clean(signal.current_state):lower() ~= 'completed') then
            return false;
        end
        local supplied = clean(signal.progression_revision);
        if (supplied ~= '' and supplied ~= previous_revision) then return false; end
        local previous_record = #previous_actions > 0 and resolved_progress_record(
            previous_key, previous_actions, previous_revision) or nil;
        local previous_index = #previous_actions > 0 and (tonumber(
            type(previous_record) == 'table' and previous_record.index or nil) or 1) or 0;
        local previous = {
            category = clean(signal.category):lower(), native_key = previous_key,
            actions = previous_actions, revision = previous_revision,
            record = previous_record, index = previous_index,
        };
        if (#previous_actions > 0) then
            local terminal = previous_actions[#previous_actions];
            if (not save_cursor_action(previous_key, terminal,
                tonumber(terminal.required_count) or 1, previous_revision)) then
                return false;
            end
        end
        if (type(current_actions) == 'table' and #current_actions > 0) then
            if (not save_cursor_action(current_key, current_actions[1], 0, current_revision)) then
                return false;
            end
        end
        purge_objective_arms(previous_key);
        remember_objective_cause(cause);
        cancel_completed_objective_route(previous, #previous_actions);
        notify_objective_progress(T{ previous });
        return true;
    end

    local objectives = reducer_active_objectives();
    if (#objectives == 0) then return false; end

    if (kind == 'interaction-start') then
        local matches = interaction_matches(objectives, signal);
        if (#matches == 0 or (tonumber(signal.target_server_id) or 0) <= 0
            or (tonumber(signal.zone_id) or 0) <= 0
            or (tonumber(signal.event_id) or 0) <= 0
            or (tonumber(signal.menu_id) or 0) <= 0) then
            return false;
        end
        local arm_key = table.concat({ tostring(tonumber(signal.target_server_id)),
            tostring(tonumber(signal.zone_id)), tostring(tonumber(signal.event_id)),
            tostring(tonumber(signal.menu_id)) }, ':');
        local snapshots = T{};
        for _, match in ipairs(matches) do
            local snapshot = objective_match_snapshot(match);
            if (snapshot == nil) then return false; end
            snapshots:append(snapshot);
        end
        if (not remember_pending_objective_event(arm_key, {
            identity = clean(signal.character_identity):lower(),
            world_id = tonumber(signal.world_id), session_epoch = tonumber(signal.session_epoch),
            target_server_id = tonumber(signal.target_server_id),
            zone_id = tonumber(signal.zone_id), event_id = tonumber(signal.event_id),
            menu_id = tonumber(signal.menu_id), progression_revision = clean(signal.progression_revision),
            matches = snapshots, sequence = tonumber(signal.sequence), tick = tonumber(signal.tick),
        })) then return false; end
        remember_objective_cause(cause);
        return true;
    elseif (kind == 'interaction-finish') then
        local arm_key = table.concat({ tostring(tonumber(signal.target_server_id)),
            tostring(tonumber(signal.zone_id)), tostring(tonumber(signal.event_id)),
            tostring(tonumber(signal.menu_id)) }, ':');
        local arm = pending_objective_events[arm_key];
        if (type(arm) ~= 'table'
            or arm.identity ~= clean(signal.character_identity):lower()
            or arm.world_id ~= tonumber(signal.world_id)
            or arm.session_epoch ~= tonumber(signal.session_epoch)
            or (tonumber(signal.sequence) or 0) <= (tonumber(arm.sequence) or 0)
            or (tonumber(signal.tick) or 0) < (tonumber(arm.tick) or 0)
            or (tonumber(signal.tick) or 0) - (tonumber(arm.tick) or 0) > 1200000
            or signal.automated == true
            or clean(signal.progression_revision) ~= clean(arm.progression_revision)) then
            return false;
        end
        remove_pending_objective_event(arm_key);
        local fresh_objectives = reducer_active_objectives();
        local changed = T{};
        for _, snapshot in ipairs(arm.matches) do
            local match = revalidated_objective_match(snapshot, fresh_objectives);
            if (type(match) == 'table'
                and objective_signal_revision_matches(signal, match.objective)
                and advance_objective_match(match.objective, match.index, 1)) then
                changed:append(match.objective);
            end
        end
        if (#changed == 0) then return false; end
        remember_objective_cause(cause);
        notify_objective_progress(changed);
        return true;
    elseif (kind == 'inventory-delta') then
        local before = tonumber(signal.before_count);
        local after = tonumber(signal.after_count);
        if (signal.snapshot_complete ~= true or before == nil or after == nil
            or after <= before or clean(signal.item_name) == '') then return false; end
        local matches = inventory_matches(objectives, signal, false);
        local changed = T{};
        for _, match in ipairs(matches) do
            local action = match.objective.actions[match.index];
            local units = 1;
            if (clean(action.count_mode):lower() == 'inventory-gain') then
                local distinct_count, is_distinct_set = distinct_inventory_set_count(action);
                if (is_distinct_set) then
                    local current_count = 0;
                    if (match.index == match.objective.index
                        and type(match.objective.record) == 'table'
                        and clean(match.objective.record.action_id) == clean(action.action_id)) then
                        current_count = tonumber(match.objective.record.progress_count) or 0;
                    end
                    units = distinct_count ~= nil and (distinct_count - current_count) or 0;
                else
                    units = after - before;
                end
            end
            if (advance_objective_match(match.objective, match.index, units, 'acquisition')) then
                changed:append(match.objective);
            end
        end
        if (#changed == 0) then return false; end
        remember_objective_cause(cause);
        notify_objective_progress(changed);
        return true;
    elseif (kind == 'key-item-delta') then
        if (signal.snapshot_complete ~= true or signal.before_owned == true
            or signal.after_owned ~= true or clean(signal.key_item_name) == '') then
            return false;
        end
        local matches = inventory_matches(objectives, signal, true);
        local changed = T{};
        for _, match in ipairs(matches) do
            if (advance_objective_match(match.objective, match.index, 1, 'acquisition')) then
                changed:append(match.objective);
            end
        end
        if (#changed == 0) then return false; end
        remember_objective_cause(cause);
        notify_objective_progress(changed);
        return true;
    elseif (kind == 'kill-credit') then
        local message_id = tonumber(signal.message_id) or 0;
        local battle_sequence = tonumber(signal.battle_sequence) or 0;
        if tonumber(signal.packet_id) ~= 0x029 or (message_id ~= 6 and message_id ~= 97)
            or (signal.actor_is_local ~= true and signal.actor_is_party ~= true)
            or battle_sequence <= 0 or battle_sequence <= last_objective_battle_sequence then
            return false;
        end
        local matches = T{};
        for _, objective in ipairs(objectives) do
            if (objective_signal_revision_matches(signal, objective)) then
                local action = objective.action;
                -- A step that names its own proof is not completed by kills.
                -- Counting defeats cannot tell two enemies apart, so it would
                -- announce the battlefield finished while the second one lived.
                if (clean(action.action):lower() == 'fight'
                    and clean(action.completion_evidence) == ''
                    and clean(action.relationship):lower():find('defeat', 1, true) ~= nil
                    and enemy_action_matches(objective.native_key, action, signal)) then
                    matches:append({ objective = objective, index = objective.index });
                end
            end
        end
        if (#matches == 0) then return false; end
        local changed = T{};
        for _, match in ipairs(matches) do
            if (advance_objective_match(match.objective, match.index, 1)) then
                changed:append(match.objective);
            end
        end
        if (#changed == 0) then return false; end
        last_objective_battle_sequence = battle_sequence;
        remember_objective_cause(cause);
        notify_objective_progress(changed);
        return true;
    elseif (kind == 'transport-request') then
        if ((tonumber(signal.target_server_id) or 0) <= 0
            or (tonumber(signal.zone_id) or 0) <= 0
            or (tonumber(signal.menu_id) or 0) <= 0) then return false; end
        local match = nil;
        for _, objective in ipairs(objectives) do
            local action = objective.action;
            if (objective_signal_revision_matches(signal, objective)
                and (clean(action.target_kind):lower() == 'transport'
                    or clean(action.relationship):lower() == 'use-transport')
                and action_target_matches(objective.native_key, action, signal, true)) then
                if (match ~= nil) then return false; end
                match = { objective = objective, index = objective.index };
            end
        end
        if (match == nil) then return false; end
        local snapshot = objective_match_snapshot(match);
        local action = match.objective.actions[match.index];
        local destination_zone_id = tonumber(action.destination_zone_id) or 0;
        if (snapshot == nil or destination_zone_id <= 0) then return false; end
        local previous = pending_objective_transport;
        if (type(previous) == 'table') then
            local previous_match = previous.match;
            local exact_replacement = type(previous_match) == 'table'
                and previous.identity == clean(signal.character_identity):lower()
                and previous.world_id == tonumber(signal.world_id)
                and previous.session_epoch == tonumber(signal.session_epoch)
                and previous.target_server_id == tonumber(signal.target_server_id)
                and previous.zone_id == tonumber(signal.zone_id)
                and previous.menu_id == tonumber(signal.menu_id)
                and clean(previous.progression_revision) == clean(signal.progression_revision)
                and clean(previous_match.native_key) == clean(snapshot.native_key)
                and clean(previous_match.match_action_id) == clean(snapshot.match_action_id)
                and (tonumber(signal.tick) or 0) > (tonumber(previous.tick) or 0)
                and (tonumber(signal.sequence) or 0) > (tonumber(previous.sequence) or 0);
            if (not exact_replacement) then return false; end
        end
        pending_objective_transport = {
            match = snapshot, identity = clean(signal.character_identity):lower(),
            world_id = tonumber(signal.world_id), session_epoch = tonumber(signal.session_epoch),
            target_server_id = tonumber(signal.target_server_id), zone_id = tonumber(signal.zone_id),
            menu_id = tonumber(signal.menu_id), sequence = tonumber(signal.sequence),
            tick = tonumber(signal.tick), destination_zone_id = destination_zone_id,
            progression_revision = clean(signal.progression_revision),
        };
        remember_objective_cause(cause);
        return true;
    elseif (kind == 'committed-zone') then
        local changed = T{};
        local destination = tonumber(signal.zone_id) or 0;
        -- REMEMBER WHERE THE PLAYER HAS BEEN.
        --
        -- An arrival is tested against the action the cursor happens to be on
        -- AT THAT MOMENT, and if the cursor is behind, the evidence is thrown
        -- away. Live 2026-08-29 the player zoned into the Hall of Transference
        -- while the cursor still sat two actions back on a talk, so
        -- "enter the Hall of Transference" -- which is literally that arrival --
        -- was tested against a talk step and rejected. Keeping the arrival lets
        -- the cursor catch up when it does move.
        if (destination > 0) then
            if (type(accessxi.objective_zones_visited) ~= 'table') then
                accessxi.objective_zones_visited = {};
            end
            accessxi.objective_zones_visited[destination] = tonumber(signal.tick) or 0;
        end
        local arm = pending_objective_transport;
        if (type(arm) == 'table') then
            if (destination > 0 and destination ~= tonumber(arm.destination_zone_id)) then
                pending_objective_transport = nil;
                return false;
            end
            if (arm.identity == clean(signal.character_identity):lower()
                and arm.world_id == tonumber(signal.world_id)
                and arm.session_epoch == tonumber(signal.session_epoch)
                and arm.target_server_id == tonumber(signal.target_server_id)
                and arm.menu_id == tonumber(signal.menu_id)
                and arm.sequence == tonumber(signal.transport_sequence)
                and (tonumber(signal.sequence) or 0) > (tonumber(arm.sequence) or 0)
                and (tonumber(signal.tick) or 0) >= (tonumber(arm.tick) or 0)
                and clean(arm.progression_revision) == clean(signal.progression_revision)
                and destination > 0) then
                local match = revalidated_objective_match(arm.match, objectives);
                pending_objective_transport = nil;
                if (type(match) == 'table'
                    and objective_signal_revision_matches(signal, match.objective)
                    and advance_objective_match(match.objective, match.index, 1)) then
                    changed:append(match.objective);
                end
            end
        else
            -- WHY A TRAVEL STEP DID NOT COMPLETE ON ARRIVAL.
            --
            -- Live 2026-08-27, Chains of Promathia mission 2: the player
            -- entered Lower Delkfutt's Tower (zone 184) and later Upper Jeuno
            -- (244); both are travel steps naming exactly those zones with
            -- matching destination ids, and neither completed. Nine other
            -- travel arrivals across five missions worked in the same log, so
            -- the mechanism is sound and something about these two was not --
            -- and nothing recorded which gate turned them away.
            --
            -- One line per zone change naming every candidate and the first
            -- test it failed. A silent refusal is a bug that has to be guessed
            -- at; this one can be read.
            local diag = T{};
            for _, objective in ipairs(objectives) do
                local action = objective.action;
                local why = '';
                if (not objective_signal_revision_matches(signal, objective)) then
                    why = 'revision';
                elseif (clean(action.action):lower() ~= 'travel') then
                    why = 'action=' .. clean(action.action);
                elseif (clean(action.relationship):lower() == 'use-transport') then
                    why = 'transport';
                elseif (destination <= 0) then
                    why = 'no-destination';
                end
                if (why ~= '') then
                    diag:append(('%s/%s:%s'):fmt(
                        clean(objective.native_key), clean(action.step_id), why));
                end
            end
            if (diag:len() > 0) then
                log_line(('objective travel arrival zone=%d rejected %s'):fmt(
                    destination, accessxi.escape_probe_log_text(diag:concat(' '))));
            elseif (#objectives == 0) then
                log_line(('objective travel arrival zone=%d has NO active objectives to match'):fmt(
                    destination));
            end
            for _, objective in ipairs(objectives) do
                local action = objective.action;
                if (objective_signal_revision_matches(signal, objective)
                    and clean(action.action):lower() == 'travel'
                    and clean(action.relationship):lower() ~= 'use-transport'
                    and destination > 0) then
                    local accepted = accessxi.nav_objective_travel_destination_zones(
                        objective.native_key, action);
                    -- A BOUND STEP IS NOT FINISHED BY ARRIVING.
                    --
                    -- Live 2026-08-25, "Journey Abroad" step-007 "Go to Bastok
                    -- first and then to Windurst". The player zoned into the
                    -- Metalworks and this completed the step on the spot --
                    -- "objective travel arrived ... zone=237" -- and the cursor
                    -- moved to step-008, which is the WINDURST branch. They had
                    -- not spoken to anyone: "it got me to metal works but then
                    -- tried to update to windurst right away."
                    --
                    -- A step with a reviewed binding names someone to TALK TO.
                    -- Reaching their zone is how you get to them, not the doing
                    -- of it, so arrival must not advance the cursor past them.
                    local bound = nil;
                    if (type(accessxi.nav_step_target_binding) == 'function') then
                        local ok_bound, row = pcall(accessxi.nav_step_target_binding,
                            clean(action.step_id));
                        if (ok_bound and type(row) == 'table') then bound = row; end
                    end
                    if (bound ~= nil) then
                        log_line(('objective travel arrived but step is bound native="%s" step="%s" zone=%d target="%s"'):fmt(
                            clean(objective.native_key), clean(action.step_id),
                            destination, clean(bound.target)));
                    elseif (accepted[destination] ~= true) then
                        local names = T{};
                        for zone_id in pairs(accepted) do names:append(tostring(zone_id)); end
                        log_line(('objective travel arrival zone=%d not accepted by native="%s" step="%s" accepts={%s}'):fmt(
                            destination, clean(objective.native_key),
                            clean(action.step_id), names:concat(',')));
                    elseif (accepted[destination] == true) then
                        log_line(('objective travel arrived native="%s" step="%s" zone=%d'):fmt(
                            clean(objective.native_key), clean(action.step_id), destination));
                        if (advance_objective_match(objective, objective.index, 1)) then
                            changed:append(objective);
                        end
                    end
                end
            end
        end
        if (#changed == 0) then return false; end
        remember_objective_cause(cause);
        notify_objective_progress(changed);
        return true;
    elseif (kind == 'route-arrival') then
        local destination = type(accessxi.nav_destination) == 'table'
            and accessxi.nav_destination or nil;
        if (type(destination) ~= 'table'
            or clean(destination.objective_character_identity):lower() ~= character_identity()
            or tonumber(destination.objective_world_id) ~= player_world_id()
            or tonumber(destination.objective_session_epoch) ~= objective_session_epoch()
            or clean(destination.objective_native_key) ~= clean(signal.objective_native_key)
            or clean(destination.objective_action_id) ~= clean(signal.action_id)
            or clean(destination.objective_destination_id) ~= clean(signal.destination_id)) then
            return false;
        end
        for _, objective in ipairs(objectives) do
            local action = objective.action;
            if (clean(objective.native_key) == clean(signal.objective_native_key)
                and clean(action.action_id) == clean(signal.action_id)
                and clean(action.action):lower() == 'travel'
                and objective_signal_revision_matches(signal, objective)
                and advance_objective_match(objective, objective.index, 1)) then
                remember_objective_cause(cause);
                notify_objective_progress(T{ objective });
                return true;
            end
        end
    end
    return false;
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
    if (item.objective_guide_postlude == true) then
        -- NOTHING LEFT TO ROUTE IS A THING TO SAY, NOT A THING TO GO QUIET ON.
        --
        -- "No further recorded step" was the wrong words even so: what ran out
        -- is what this addon TRACKS, and the guide frequently has not run out at
        -- all. Where it still has material steps -- travel, talk, examine,
        -- fight -- say that plainly rather than implying the objective is done
        -- being described.
        local speech = ('%s. %s'):fmt(title ~= '' and title or 'Objective', status);
        if (location ~= '') then
            speech = speech .. ' ' .. location .. '.';
        end
        local continuation = clean(item.objective_instruction);
        if (clean(item.objective_guide_postlude_kind) == 'invalid') then
            return ('%s %s'):fmt(speech, continuation)
                .. (' %d of %d.'):fmt(tonumber(index) or 1, tonumber(total) or 1);
        end
        if ((tonumber(item.objective_guide_postlude_material_tail) or 0) > 0) then
            speech = speech .. ' Automatic tracking ends here, and the guide still has'
                .. ' steps it does not track.';
        else
            speech = speech .. ' No further automatically tracked step.';
        end
        local source = clean(item.objective_guide_postlude_source);
        if (source ~= '' and continuation ~= '') then
            speech = ('%s %s continues: %s'):fmt(speech, source, continuation);
        elseif (continuation ~= '') then
            speech = speech .. ' ' .. continuation;
        end
        if (item.objective_guide_postlude_truncated == true) then
            speech = speech .. ' More guide text follows. Press G to read it.';
        end
        -- WHERE, WITHOUT CLAIMING HOW MANY.
        local places = clean(item.objective_guide_postlude_places);
        if (places ~= '') then
            speech = ('%s Places for this step: %s.'):fmt(speech, places);
        end
        -- AND THE NOTE WE WROTE FOR THIS EXACT STEP.
        --
        -- modules/mission_quest_step_notes.lua holds hand-written, source-checked
        -- instructions the guide omits -- today, that the Large Apparatus to
        -- examine is the one on the LEFT, because the one on the right goes to
        -- Ru'Aun Gardens and costs a Clear Chip to find out. Nothing spoke it
        -- once a cursor exhausted, which is exactly when the player is standing
        -- in front of both.
        --
        -- The NOTE alone, not objective_step_supplement. The supplement also
        -- reads the lines written UNDER the step, and in a postlude those are
        -- the same lines the page continuation just read -- it doubled this row
        -- to eighteen hundred characters of the same paragraph twice.
        local postlude_note = accessxi.objective_step_note(
            clean(item.objective_native_key), clean(item.objective_guide_step_id));
        if (postlude_note ~= '') then
            speech = speech .. ' ' .. postlude_note;
        end
        local postlude_details = meaningful_native_details(item.objective_native_details);
        if (postlude_details ~= '') then
            speech = speech .. (kind == 'quest' and ' Native quest details: ' or ' Native mission orders: ')
                .. postlude_details;
        end
        return speech .. ' Press K to repeat instructions.'
            .. (' %d of %d.'):fmt(tonumber(index) or 1, tonumber(total) or 1);
    end
    if (item.objective_instruction_only == true) then
        local speech = ('%s. %s'):fmt(title ~= '' and title or 'Objective', status);
        if (location ~= '') then
            speech = speech .. ' ' .. location .. '.';
        end
        speech = speech .. ' Current instruction: ' .. clean(item.objective_instruction);
        -- Everything written UNDER this instruction. For a step that ends on a
        -- colon this is the whole answer, and without it the player is told a
        -- list is coming and then never told what is in it.
        local supplement = accessxi.objective_step_supplement(item);
        if (supplement ~= '') then
            speech = speech .. ' ' .. supplement;
        end
        local native_details = meaningful_native_details(item.objective_native_details);
        if (native_details ~= '') then
            speech = speech .. (kind == 'quest' and ' Native quest details: ' or ' Native mission orders: ')
                .. native_details;
        end
        return speech .. ' Press K to repeat instructions.'
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
        -- The same supplement as every other branch: the rows written under
        -- this step, and what of them the player is already carrying.
        local supplement = accessxi.objective_step_supplement(item);
        if (supplement ~= '') then
            speech = speech .. ' ' .. supplement;
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
        or (tonumber(fresh.objective_world_id) or 0) <= 0
        or (tonumber(fresh.objective_session_epoch) or 0) <= 0
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
    payload.objective_test_route = false;
    payload.objective_wiki_route = true;
    payload.wiki_authoritative = true;
    payload.objective_active_state_signature = clean(fresh.objective_active_state_signature);
    payload.objective_active_owner_key = clean(fresh.objective_active_owner_key);
    payload.verified = false;
    payload.route_context_label = payload.objective_kind == 'quest'
        and 'Wiki-authoritative quest objective' or 'Wiki-authoritative mission objective';
    return payload;
end

function accessxi.nav_mission_quest_prepare_route(item, player)
    local kind = clean(item ~= nil and (item.objective_kind or item.kind) or ''):lower();
    if (kind ~= 'mission' and kind ~= 'quest') then
        return nil, '', 'not-objective';
    end

    local title = clean(item ~= nil and item.name or 'objective');
    local instruction_route_message =
        ('No exact source-backed route is available for %s. Press K for instructions.'):fmt(title);
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
    -- A refusal names its failure class. "No exact source-backed route" told
    -- the player nothing they could act on; "the guide does not say which
    -- zone Zantaviat is in" tells them, and tells us what to fix.
    local step_refusal = accessxi.nav_mission_quest_step_refusal(
        clean(fresh.objective_native_key), clean(fresh.objective_guide_step_id));
    -- Whatever answer this function ends up giving, the guide's sentence goes
    -- with it. Every "no route" branch below used to end the player's evening.
    local guide_instruction = clean(fresh.objective_action_instruction);
    if (guide_instruction == '' and type(step_refusal) == 'table') then
        guide_instruction = clean(step_refusal.instruction);
    end
    local function with_guide(message)
        local guide = type(accessxi.mission_step_resolver) == 'table'
            and accessxi.mission_step_resolver.guide_sentence(guide_instruction) or '';
        if (guide == '') then return message; end
        return ('%s %s'):fmt(message, guide);
    end
    if (step_refusal ~= nil and type(accessxi.mission_step_resolver) == 'table') then
        instruction_route_message = accessxi.mission_step_resolver.refusal_speech(
            title, step_refusal, guide_instruction);
    else
        instruction_route_message = with_guide(instruction_route_message);
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
            return nil, instruction_route_message, 'blocked';
        end
        if (test_payload ~= nil) then
            return test_payload, '', 'wiki-ready';
        end
        -- The named refusal was built above and then thrown away here: it was
        -- only ever RETURNED on the instruction-only branches, and these are
        -- the branches a routed objective actually reaches. What the player
        -- heard live was "No exact source-backed route is available for The
        -- Davoi Report" -- the addon's own vocabulary, with the reason and the
        -- guide's sentence both discarded.
        return nil, (step_refusal ~= nil and instruction_route_message or with_guide(
            ('No exact source-backed destination is available for %s. Press G for the source guide.'):fmt(title))), 'blocked';
    end
    if (fresh.objective_instruction_only ~= true and not objective_auxiliary_state_ready()) then
        if (test_payload ~= nil) then
            return test_payload, '', 'wiki-ready';
        end
        -- The named refusal was built above and then thrown away here: it was
        -- only ever RETURNED on the instruction-only branches, and these are
        -- the branches a routed objective actually reaches. What the player
        -- heard live was "No exact source-backed route is available for The
        -- Davoi Report" -- the addon's own vocabulary, with the reason and the
        -- guide's sentence both discarded.
        return nil, (step_refusal ~= nil and instruction_route_message or with_guide(
            ('No exact source-backed destination is available for %s. Press G for the source guide.'):fmt(title))), 'blocked';
    end
    local runtime = accessxi.objective_route_runtime;
    if (type(runtime) ~= 'table' or type(runtime.authorize_start) ~= 'function') then
        if (fresh.objective_instruction_only == true
            and clean(fresh.objective_action_instruction) ~= '') then
            return nil, instruction_route_message, 'blocked';
        end
        if (test_payload ~= nil) then return test_payload, '', 'wiki-ready'; end
        return nil, (step_refusal ~= nil and instruction_route_message
            or with_guide('Objective route verification is unavailable.')), 'blocked';
    end
    local ok, payload, message, mode = pcall(runtime.authorize_start, runtime, item, fresh, player);
    if (not ok) then
        if (fresh.objective_instruction_only == true
            and clean(fresh.objective_action_instruction) ~= '') then
            return nil, instruction_route_message, 'blocked';
        end
        if (test_payload ~= nil) then return test_payload, '', 'wiki-ready'; end
        return nil, 'Objective route verification failed safely.', 'blocked';
    end
    mode = clean(mode):lower();
    message = clean(message);
    if (mode == 'blocked') then
        if (fresh.objective_instruction_only == true
            and clean(fresh.objective_action_instruction) ~= '') then
            return nil, instruction_route_message, 'blocked';
        end
        if (test_payload ~= nil) then return test_payload, '', 'wiki-ready'; end
        return nil, message ~= '' and message or 'No rooted route contract is available for this objective.', 'blocked';
    elseif (mode == 'instruction') then
        if (fresh.objective_instruction_only ~= true or type(payload) ~= 'string'
            or clean(payload) == '' or clean(payload) ~= clean(fresh.objective_action_instruction)) then
            return nil, 'Objective route verification returned an invalid instruction.', 'blocked';
        end
        return nil, instruction_route_message, 'blocked';
    elseif (mode == 'ready') then
        if (fresh.objective_instruction_only == true or not exact_ready_payload(payload, fresh)) then
            return nil, 'Objective route verification returned an invalid destination.', 'blocked';
        end
        local ready_payload = point_copy(payload);
        ready_payload.objective_route_recommendation = clean(fresh.objective_route_recommendation);
        return ready_payload, message, 'ready';
    end
    if (test_payload ~= nil) then return test_payload, '', 'wiki-ready'; end
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

-- What the guide says you should have before going. Advice, spoken when the
-- route starts, never a reason not to start it -- the player decides whether
-- to fetch the thing first or walk it now and come back.
function accessxi.nav_mission_quest_step_advisory(native_key, step_id)
    local blocks = source_derivation_cache.prerequisite_refusals;
    local per_key = type(blocks) == 'table' and blocks[clean(native_key)] or nil;
    local record = type(per_key) == 'table' and per_key[clean(step_id)] or nil;
    if (type(record) ~= 'table' or record.advisory ~= true) then
        return '';
    end
    return clean(record.detail);
end

function accessxi.nav_mission_quest_start_suffix(point)
    local instruction = clean(point ~= nil and point.objective_instruction or '');
    local recommendation = clean(point ~= nil and point.objective_route_recommendation or '');
    local suffix = instruction ~= '' and (' Objective: ' .. instruction) or '';
    if (recommendation ~= '') then
        suffix = suffix .. ' ' .. recommendation;
    end
    local advisory = accessxi.nav_mission_quest_step_advisory(
        type(point) == 'table' and point.objective_native_key or '',
        type(point) == 'table' and (point.objective_guide_step_id or point.guide_step_id) or '');
    if (advisory ~= '') then
        suffix = suffix .. (' Note: %s.'):fmt(advisory:gsub('%.$', ''));
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
    local wiki_route = point.objective_wiki_route == true
        and point.wiki_authoritative == true and point.verified ~= true;
    if (point.objective_test_route == true or wiki_route) then
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

-- WHICH "JOURNEY ABROAD" IS THIS?
--
-- Retail's 0x056 carries NO mission status for nation missions -- only `nation`
-- and `nation_mission`. Verified live 2026-08-25 against this player's own
-- history: the field walks 4 -> 5 -> 6 (The Davoi Report -> Journey Abroad ->
-- Journey to Bastok), so committing to a BRANCH is directly observable. A
-- RETURN to Journey Abroad is not: the field reads 5 whether you have chosen no
-- nation, finished one half, or finished both.
--
-- Key items settle it with no saved history, and history is exactly what the
-- release case lacks -- a player installing this mod halfway through the
-- mission has none for us to read. From the mission scripts: Halver grants
-- Letter to the Consuls (5) and committing to a nation deletes it; finishing
-- the second half grants Kindred Report (29), which Halver then takes back.
--
--     Letter held           -> neither half started, pick a nation
--     Kindred Report held   -> both halves done, report to Halver
--     both absent, KNOWN    -> exactly one half done
--
-- Returns 'held', 'absent' or 'unknown'. THE THIRD VALUE IS THE POINT:
-- key_items_packet_has_id answers false both for "you do not have it" and for
-- "no 0x055 has arrived yet", and collapsing those would tell a player who has
-- chosen nothing at all that they are half finished.
function accessxi.mission_quest_key_item_state(id)
    id = tonumber(id) or -1;
    if (id < 0) then
        return 'unknown';
    end
    if (type(accessxi.restore_key_items_packet_cache_if_needed) == 'function') then
        pcall(accessxi.restore_key_items_packet_cache_if_needed);
    end
    local tables = accessxi.key_items_packet_tables;
    if (type(tables) ~= 'table') then
        return 'unknown';
    end
    local entry = tables[math.floor(id / 512)];
    if (type(entry) ~= 'table' or #(tostring(entry.flags or '')) < 64) then
        return 'unknown';
    end
    local ok, held = pcall(accessxi.key_items_packet_has_id, id);
    if (not ok) then
        return 'unknown';
    end
    return held and 'held' or 'absent';
end

-- HAS THIS NATION MISSION BEEN COMPLETED?
--
-- 0x056 at port 0x00D0 is a per-nation bitmap of COMPLETED nation missions --
-- one u32 per nation, bit N meaning packet mission id N. The reader already
-- keeps it as mission_packet_nations_complete; nothing read it. Verified live
-- 2026-08-25: this player's San d'Oria word was 31 (0b11111), missions 0-4 done
-- through The Davoi Report, while they were part-way through mission 6.
--
-- MIND THE NUMBERING. This takes the PACKET id, which runs one below the
-- guide's native id: guide "mission:San d'Oria:7" is packet mission 6.
--
-- Returns true, false, or nil when no 0x00D0 has arrived yet. The bits are
-- permanent -- a character who ran this chain under a previous allegiance keeps
-- them -- so callers must use this to ANNOTATE a choice, never to remove one.
function accessxi.mission_quest_nation_mission_complete(nation_index, packet_mission_id)
    nation_index = tonumber(nation_index) or -1;
    packet_mission_id = tonumber(packet_mission_id) or -1;
    if (nation_index < 0 or nation_index > 2
        or packet_mission_id < 0 or packet_mission_id > 31) then
        return nil;
    end
    local words = accessxi.mission_packet_nations_complete;
    if (type(words) ~= 'table') then
        return nil;
    end
    local word = tonumber(words[nation_index + 1]);
    if (word == nil) then
        return nil;
    end
    return math.floor(word / (2 ^ packet_mission_id)) % 2 == 1;
end

-- A `when` clause is met only on POSITIVE evidence. An unreadable key-item
-- table satisfies nothing, and an empty clause satisfies nothing either, so a
-- record with no matching variant falls through to its default -- which by
-- construction offers every branch rather than picking one on a guess.
function accessxi.mission_quest_override_when_met(when)
    if (type(when) ~= 'table') then
        return false;
    end
    local checked = false;
    local wanted = when.key_item_held;
    if (wanted ~= nil) then
        local ids = type(wanted) == 'table' and wanted or { wanted };
        for _, id in ipairs(ids) do
            if (accessxi.mission_quest_key_item_state(id) ~= 'held') then
                return false;
            end
            checked = true;
        end
    end
    local unwanted = when.key_item_absent;
    if (unwanted ~= nil) then
        local ids = type(unwanted) == 'table' and unwanted or { unwanted };
        for _, id in ipairs(ids) do
            if (accessxi.mission_quest_key_item_state(id) ~= 'absent') then
                return false;
            end
            checked = true;
        end
    end
    -- Completed-mission bits. `nil` -- no 0x00D0 seen -- never satisfies a
    -- clause in either direction, so an unread bitmap falls through to the
    -- record's default rather than asserting a mission is unfinished.
    local done = when.nation_mission_complete;
    if (done ~= nil) then
        for _, entry in ipairs(done) do
            if (accessxi.mission_quest_nation_mission_complete(entry[1], entry[2]) ~= true) then
                return false;
            end
            checked = true;
        end
    end
    local not_done = when.nation_mission_incomplete;
    if (not_done ~= nil) then
        for _, entry in ipairs(not_done) do
            if (accessxi.mission_quest_nation_mission_complete(entry[1], entry[2]) ~= false) then
                return false;
            end
            checked = true;
        end
    end
    local any = when.nation_mission_any_complete;
    if (any ~= nil) then
        local hit = false;
        for _, entry in ipairs(any) do
            if (accessxi.mission_quest_nation_mission_complete(entry[1], entry[2]) == true) then
                hit = true;
            end
        end
        if (not hit) then
            return false;
        end
        checked = true;
    end
    return checked;
end

-- Resolve a reviewed override to the step list that fits what we can observe.
-- A record carries either `steps` (one fixed sequence) or `variants` (ordered,
-- first match wins) plus a `steps` default. The second return value is the
-- source label, which carries the variant name so a progression cursor saved
-- in one state can never be mistaken for one saved in another.
function accessxi.mission_quest_override_steps(native_key)
    native_key = tostring(native_key or ''):gsub('^%s+', ''):gsub('%s+$', '');
    if (native_key == '' or type(accessxi.mission_quest_step_overrides) ~= 'table') then
        return nil, '', '';
    end
    local record = accessxi.mission_quest_step_overrides[native_key];
    if (type(record) ~= 'table') then
        return nil, '', '';
    end
    local source = tostring(record.source or '');
    if (type(record.variants) == 'table') then
        for _, variant in ipairs(record.variants) do
            if (type(variant) == 'table' and type(variant.steps) == 'table'
                and #variant.steps > 0
                and accessxi.mission_quest_override_when_met(variant.when)) then
                local state = tostring(variant.state or 'variant');
                return variant.steps, source .. ':' .. state, state;
            end
        end
    end
    if (type(record.steps) == 'table' and #record.steps > 0) then
        return record.steps, source, tostring(record.state or '');
    end
    return nil, '', '';
end

return true;

local reader_path = assert(arg[1], 'reader source path is required')

local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

-- The live reader, rather than only the navigation test fixture, must own one
-- positive process-session epoch and stamp every packet source that the
-- mission/quest availability gates consume.
assert(source:find('function accessxi.current_objective_session_epoch()', 1, true),
    'reader objective session epoch provider is missing')
local quest_capture_source = assert(source:match(
    '(function accessxi%.capture_quest_packet%(e%).-\nend)\n\nfunction accessxi%.save_roe_active_packet_cache'))
assert(quest_capture_source:find('accessxi.quest_packet_session_epoch = quest_session_epoch;', 1, true),
    'fresh quest packets do not publish their objective session epoch')
assert(quest_capture_source:find('session_epoch = quest_session_epoch,', 1, true),
    'fresh quest packet rows do not retain their objective session epoch')
local mission_capture_source = assert(source:match(
    '(function accessxi%.capture_mission_packet%(e%).-\nend)\n\naccessxi%.missions_menu_descriptor_rows'))
assert(mission_capture_source:find('accessxi.mission_packet_session_epoch = mission_session_epoch;', 1, true),
    'fresh mission packets do not publish their objective session epoch')
local key_item_capture_source = assert(source:match(
    '(function accessxi%.capture_key_items_packet%(e%).-\nend)\n\nfunction accessxi%.merit_packet_preview'))
assert(key_item_capture_source:find('accessxi.key_items_packet_session_epoch = key_item_session_epoch;', 1, true),
    'fresh key-item packets do not publish their objective session epoch')
assert(key_item_capture_source:find('session_epoch = key_item_session_epoch,', 1, true),
    'fresh key-item packet rows do not retain their objective session epoch')
assert(source:find('packet_id == 0x001E', 1, true)
    and source:find('packet_id == 0x0020', 1, true),
    'canonical item-slot and item-count packets do not refresh objective inventory state')
assert(source:find("accessxi.nav_mission_quest_clear_pending_interaction('zone-change')", 1, true),
    'zoning does not clear the pending mission interaction correlation')
assert(mission_capture_source:find('if (mission_state_packet', 1, true)
    and mission_capture_source:find("'mission', ('packet-0x056-%04X')", 1, true),
    'quest-log 0x056 pages can still trigger full mission rescans')
assert(source:find('function accessxi.capture_mission_quest_event_packet(e, direction)', 1, true),
    'reader does not publish exact event packet lifecycle evidence')
assert(source:find("accessxi.capture_mission_quest_event_packet(e, 'in')", 1, true)
    and source:find("accessxi.capture_mission_quest_event_packet(e, 'out')", 1, true),
    'incoming and outgoing packet callbacks do not feed mission event correlation')
assert(source:find('accessxi.nav_mission_quest_observe_event_packet,', 1, true),
    'reader event bridge does not call the shared mission progression engine')

function string:fmt(...)
    return string.format(self, ...)
end

function string:startswith(prefix)
    return self:sub(1, #prefix) == prefix
end

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear()
    for index = #self, 1, -1 do self[index] = nil end
end

local function T(value)
    return setmetatable(value or {}, { __index = list_methods })
end

local function clean(value)
    return tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
end

local function extract(first_literal, after_literal)
    local first = assert(source:find(first_literal, 1, true), 'reader block start is missing: ' .. first_literal)
    local after = assert(source:find(after_literal, first + #first_literal, true),
        'reader block end is missing: ' .. after_literal)
    return source:sub(first, after - 1)
end

-- Main 0x056 uses two packed uint16 fields before the final SoA/RoV uint32s.
-- RoV must never alias the uint16 packet port at absolute offset 0x24.
local mission_bytes = {}
for index = 1, 0x2C do mission_bytes[index] = 0 end
local function put_le(offset, value, width)
    for index = 0, width - 1 do
        mission_bytes[offset + index + 1] = math.floor(value / (2 ^ (8 * index))) % 256
    end
end
put_le(0x04, 0, 4)
put_le(0x08, 3, 4)
put_le(0x0C, 4, 4)
put_le(0x10, 5, 4)
put_le(0x14, 0x11223344, 4)
put_le(0x18, 0x0010, 2)
put_le(0x1A, 0x0040, 2)
put_le(0x1C, 0x55667788, 4)
put_le(0x20, 110, 4)
put_le(0x24, 0xFFFF, 2)
local mission_data = string.char(unpack(mission_bytes))
local mission_queue_calls = 0
local decoder_accessxi = {
    mission_packet_main = {},
    packet_event_string = function(e) return e.data or '' end,
    packet_u16 = function(data, index)
        local a, b = data:byte(index, index + 1)
        return (a or 0) + ((b or 0) * 256)
    end,
    packet_u32 = function(data, index)
        local a, b, c, d = data:byte(index, index + 3)
        return (a or 0) + ((b or 0) * 256) + ((c or 0) * 65536) + ((d or 0) * 16777216)
    end,
    packet_hex_limit = function() return 'fixture' end,
    nav_mission_quest_sync_character = function() end,
    current_player_name = function() return 'Alpha' end,
    current_player_identity = function() return 'alpha:1001' end,
    current_objective_session_epoch = function() return 77 end,
    save_mission_packet_cache = function() end,
    queue_mission_quest_state_change = function(kind)
        assert(kind == 'mission')
        mission_queue_calls = mission_queue_calls + 1
    end,
    escape_probe_log_text = function(value) return tostring(value or '') end,
}
local decoder_chunk = assert(loadstring(mission_capture_source, '@reader-mission-056-decoder'))
setfenv(decoder_chunk, setmetatable({
    accessxi = decoder_accessxi,
    tick = function() return 500 end,
    log_line = function() end,
}, { __index = _G }))
decoder_chunk()
decoder_accessxi.capture_mission_packet({ id = 0x056, data = mission_data, size = #mission_data })
assert(decoder_accessxi.mission_packet_main.addons == 0x0010)
assert(decoder_accessxi.mission_packet_main.tales == 0x0040)
assert(decoder_accessxi.mission_packet_main.soa == 0x55667788)
assert(decoder_accessxi.mission_packet_main.rov == 110,
    'RoV current mission was decoded from the 0xFFFF packet port')
assert(decoder_accessxi.mission_packet_main.port == 0xFFFF
    and decoder_accessxi.mission_packet_main.port_raw == 0xFFFF)
assert(mission_queue_calls == 1)

-- A complete zone-load packet burst must publish at most one refresh per
-- affected category, and no expensive active-objective scan may run while the
-- post-zone quiescence barrier is active.
local queued_state_source = extract(
    'function accessxi.queue_mission_quest_state_change(kind, reason, now)',
    'function accessxi.on_mission_quest_state_changed(kind, reason)')
local queued_calls = {}
local zone_settle_active = true
local queue_accessxi = {
    mission_quest_state_pending = {},
    mission_quest_state_pending_tick = 0,
    mission_quest_state_debounce_ms = 250,
    nav_zoning_watch_active = function() return false end,
    nav_zone_load_settle_active = function() return zone_settle_active end,
    on_mission_quest_state_changed = function(kind, reason)
        queued_calls[#queued_calls + 1] = { kind = kind, reason = reason }
        return false, false
    end,
}
local queue_chunk = assert(loadstring(queued_state_source, '@reader-objective-state-queue'))
setfenv(queue_chunk, setmetatable({
    accessxi = queue_accessxi,
    T = T,
    nav_clean_field = clean,
    tick = function() return 1000 end,
    log_line = function() end,
}, { __index = _G }))
queue_chunk()
for index = 1, 28 do
    assert(queue_accessxi.queue_mission_quest_state_change(
        'mission', ('packet-%d'):format(index), 1000))
    assert(queue_accessxi.queue_mission_quest_state_change(
        'quest', ('packet-%d'):format(index), 1000))
end
assert(queue_accessxi.poll_mission_quest_state_changes(2000) == false
    and #queued_calls == 0,
    'zone-load packets ran objective scans inside the settle barrier')
zone_settle_active = false
assert(queue_accessxi.poll_mission_quest_state_changes(1249) == false
    and #queued_calls == 0,
    'the zone packet burst was drained before its debounce boundary')
assert(queue_accessxi.poll_mission_quest_state_changes(1250) == true)
assert(#queued_calls == 2
    and queued_calls[1].kind == 'mission'
    and queued_calls[2].kind == 'quest',
    'the zone packet burst was not coalesced to one refresh per category')
assert(queue_accessxi.poll_mission_quest_state_changes(2000) == false
    and #queued_calls == 2,
    'a drained packet burst was scanned more than once')

-- Incoming 0x00A is the native Zone In packet.  It can release the conservative
-- settle barrier after a short safety floor instead of freezing every addon
-- hotkey for the full eight-second fallback window.
local settle_ready_source = extract(
    'function accessxi.nav_observe_zone_load_packet(e, now)',
    'function accessxi.nav_reset_zone_state(reason, old_zone, new_zone)')
local settle_clear_reason = nil
local settle_accessxi
settle_accessxi = {
    nav_zone_load_packet_tick = 0,
    nav_zone_load_settle_start_tick = 1000,
    nav_zone_load_settle_until = 9000,
    nav_zone_load_settle_min_ms = 750,
    nav_clear_zone_load_settle = function(reason)
        settle_clear_reason = reason
        settle_accessxi.nav_zone_load_settle_until = 0
    end,
}
local settle_chunk = assert(loadstring(settle_ready_source, '@reader-zone-settle-ready'))
setfenv(settle_chunk, setmetatable({
    accessxi = settle_accessxi,
    tick = function() return 1000 end,
}, { __index = _G }))
settle_chunk()
assert(settle_accessxi.nav_observe_zone_load_packet({ id = 0x00D }, 1050) == false)
assert(settle_accessxi.nav_observe_zone_load_packet({ id = 0x00A }, 1100) == true)
assert(settle_accessxi.nav_zone_load_settle_active(1749) == true
    and settle_clear_reason == nil,
    'the native Zone In packet bypassed the minimum memory-safety floor')
assert(settle_accessxi.nav_zone_load_settle_active(1750) == false
    and settle_clear_reason == 'zone-in-ready',
    'the native Zone In packet did not release the fixed eight-second freeze')

local accessxi = {}
local copy_environment = setmetatable({
    accessxi = accessxi,
    T = T,
    nav_clean_field = clean,
}, { __index = _G })
local copy_chunk = assert(loadstring(
    extract('function accessxi.nav_copy_point(point)', "accessxi.load_code_module('same_zone_reentry_navigation'"),
    '@reader-nav-copy-point'))
setfenv(copy_chunk, copy_environment)
copy_chunk()

local snapshot = {
    contract_id = 'route:v2:' .. string.rep('a', 64),
    candidate_id = 'candidate:one',
    action_id = 'action:one',
    group_id = '',
    destination_id = 'destination:one',
    route_ready = true,
    nested = { immutable = true },
}
local copied = assert(accessxi.nav_copy_point({
    zone = 143,
    name = 'Fixture target',
    x = 1,
    z = 2,
    y = 3,
    kind = 'mission',
    objective_kind = 'mission',
    objective_native_key = 'mission:Bastok:3',
    objective_guide_step_id = 'mission:Bastok:3:step-006',
    objective_character_identity = 'alpha:1001',
    objective_world_id = 1001,
    objective_session_epoch = 77,
    objective_candidate_id = 'candidate:one',
    objective_action_id = 'action:one',
    objective_group_id = '',
    objective_destination_id = 'destination:one',
    destination_id = 'destination:one',
    objective_classification = 'catalogue-candidate',
    objective_action_instruction = 'Travel to the fixture target.',
    objective_route_recommendation = 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
    objective_instruction_only = false,
    objective_route_contract_id = snapshot.contract_id,
    objective_contract_snapshot = snapshot,
    objective_active_state_signature = 'mission-state:one',
    objective_active_owner_key = 'mission-owner:one',
    objective_completion_items = { { name = 'Orcish Axe', count = 1 } },
    objective_completion_key_items = { 'Orcish hut key' },
    to_zone = 100,
    to_zone_name = 'West Ronfaure',
    final_zone = 140,
    final_name = 'Hut Door',
    same_zone_reentry_step = 1,
    same_zone_reentry_edge_id = 123,
}))
for field, expected in pairs({
    objective_native_key = 'mission:Bastok:3',
    objective_guide_step_id = 'mission:Bastok:3:step-006',
    objective_character_identity = 'alpha:1001',
    objective_world_id = 1001,
    objective_session_epoch = 77,
    objective_candidate_id = 'candidate:one',
    objective_action_id = 'action:one',
    objective_group_id = '',
    objective_destination_id = 'destination:one',
    destination_id = 'destination:one',
    objective_classification = 'catalogue-candidate',
    objective_action_instruction = 'Travel to the fixture target.',
    objective_route_recommendation = 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
    objective_instruction_only = false,
    objective_route_contract_id = snapshot.contract_id,
    objective_active_state_signature = 'mission-state:one',
    objective_active_owner_key = 'mission-owner:one',
    to_zone = 100,
    to_zone_name = 'West Ronfaure',
    final_zone = 140,
    final_name = 'Hut Door',
    same_zone_reentry_step = 1,
    same_zone_reentry_edge_id = 123,
}) do
    assert(copied[field] == expected, 'nav_copy_point dropped objective field ' .. field)
end
assert(type(copied.objective_contract_snapshot) == 'table'
    and copied.objective_contract_snapshot.contract_id == snapshot.contract_id)
assert(copied.objective_contract_snapshot ~= snapshot
    and copied.objective_contract_snapshot.nested ~= snapshot.nested,
    'nav_copy_point must deep-copy the immutable contract snapshot')
assert(copied.objective_completion_items[1].name == 'Orcish Axe'
    and copied.objective_completion_key_items[1] == 'Orcish hut key',
    'nav_copy_point dropped generic mission completion prerequisites')
copied.objective_completion_items[1].name = 'caller mutation'
assert(copied.objective_completion_items[1].name ~= 'Orcish Axe'
    and snapshot.contract_id ~= '', 'completion prerequisites are not writable copies')

assert(source:find('accessxi.nav_mission_quest_remember_arrival(destination, now)', 1, true),
    'reader arrival handling does not retain the exact selected objective interaction')
assert(source:find('accessxi.nav_mission_quest_observe_interaction_text(', 1, true),
    'reader NPC text handling does not publish interaction evidence')
assert(source:find("accessxi.nav_mission_quest_observe_event_menu(name or '', tick())", 1, true),
    'reader menu lifecycle does not finalize completed objective interactions')

-- The native rem4li2 event can close without another menu-speech hotkey.
-- The always-polled movement-control edge must publish that real close rather
-- than leaving a completed NPC interaction pending forever.
local menu_close_calls = 0
local close_accessxi = {
    nav_collision_control_interrupt_active = true,
    nav_collision_control_interrupt_reason = 'target-menu:2',
    nav_collision_control_last_log_key = '',
    nav_collision_control_return_quiet_ms = 6500,
    nav_collision_control_interrupt_state = function() return false, '' end,
    nav_collision_quiet = function() end,
    escape_probe_log_text = function(value) return tostring(value or '') end,
    nav_mission_quest_observe_event_menu = function(menu_name, now)
        assert(menu_name == '' and now == 2000,
            'the actual target-menu close published the wrong lifecycle state')
        menu_close_calls = menu_close_calls + 1
        return true
    end,
}
local close_chunk = assert(loadstring(extract(
    'function accessxi.nav_collision_update_control_interrupt(now)',
    'function accessxi.nav_player_moving()'),
    '@reader-objective-menu-close'))
setfenv(close_chunk, setmetatable({
    accessxi = close_accessxi,
    tick = function() return 2000 end,
    log_line = function() end,
}, { __index = _G }))
close_chunk()
assert(close_accessxi.nav_collision_update_control_interrupt(2000) == true,
    'the native target-menu close edge was not observed')
assert(menu_close_calls == 1,
    'the native target-menu close did not finalize the pending objective interaction')

-- A collision path can fold back close to an earlier corridor. Progress must
-- stay local instead of jumping to the globally nearest later corridor.
local folded_accessxi = {
    nav_route_point_index = 4,
    nav_route_points = T{
        T{ x = -55.515, z = -134.245, y = 0, source = 'dat-collision' },
        T{ x = -37.542, z = -126.752, y = 0, source = 'dat-collision' },
        T{ x = -16.382, z = -136.912, y = 0, source = 'dat-collision' },
        T{ x = -5.349, z = -134.045, y = 0, source = 'dat-collision' },
        T{ x = 7.898, z = -134.272, y = 0, source = 'dat-collision' },
        T{ x = 21.018, z = -128.712, y = 0, source = 'dat-collision' },
        T{ x = 10.685, z = -124.845, y = 0, source = 'dat-collision' },
        T{ x = -2.582, z = -122.512, y = 0, source = 'dat-collision' },
        T{ x = -11.702, z = -125.272, y = 0, source = 'dat-collision' },
        T{ x = -20.582, z = -119.962, y = 0, source = 'dat-collision' },
    },
}
function folded_accessxi.nav_distance_to_segment(pos, first, second)
    local ax, az = tonumber(first.x) or 0, tonumber(first.z) or 0
    local bx, bz = tonumber(second.x) or 0, tonumber(second.z) or 0
    local px, pz = tonumber(pos.x) or 0, tonumber(pos.z) or 0
    local dx, dz = bx - ax, bz - az
    local length2 = dx * dx + dz * dz
    local t = length2 > 0 and (((px - ax) * dx + (pz - az) * dz) / length2) or 0
    t = math.max(0, math.min(1, t))
    local cx, cz = ax + t * dx, az + t * dz
    local ox, oz = px - cx, pz - cz
    return math.sqrt(ox * ox + oz * oz)
end
folded_accessxi.nav_route_precise_override_active = function() return false end
folded_accessxi.nav_route_points_are_override = function() return false end
folded_accessxi.nav_route_points_are_collision = function(points)
    return type(points) == 'table' and points[1] ~= nil
        and points[1].source == 'dat-collision'
end
local folded_environment = setmetatable({ accessxi = folded_accessxi }, { __index = _G })
local folded_nearest_chunk = assert(loadstring(extract(
    'function accessxi.nav_nearest_route_segment(pos, points, first_segment, last_segment)',
    'function accessxi.nav_lookahead_target(pos, points, lookahead)'),
    '@reader-folded-nearest'))
setfenv(folded_nearest_chunk, folded_environment)
folded_nearest_chunk()
local folded_sync_chunk = assert(loadstring(extract(
    'function accessxi.nav_sync_route_index(pos)',
    'local function nav_route_phrase(from_pos, to_pos)'),
    '@reader-folded-sync'))
setfenv(folded_sync_chunk, folded_environment)
folded_sync_chunk()
folded_accessxi.nav_sync_route_index(T{ x = -11.643, z = -130.031, y = 0 })
assert(folded_accessxi.nav_route_point_index <= 6,
    'collision route progress jumped across a nearby folded corridor')

local obstacle_calls = 0
folded_accessxi.nav_obstacle_avoidance_target = function()
    obstacle_calls = obstacle_calls + 1
    return T{ x = 999, z = 999, y = 0, source = 'dynamic-obstacle' },
        { entity = { name = 'Tombstone' }, ahead = 3, side = 0, radius = 4, warn = true }
end
local obstacle_environment = setmetatable({
    accessxi = folded_accessxi,
    tick = function() return 1000 end,
    log_line = function() end,
}, { __index = _G })
local obstacle_chunk = assert(loadstring(extract(
    'function accessxi.nav_apply_dynamic_obstacle(player, route_target)',
    'function accessxi.nav_recent_live_obstacle(now)'),
    '@reader-collision-obstacle'))
setfenv(obstacle_chunk, obstacle_environment)
obstacle_chunk()
local collision_target = folded_accessxi.nav_route_points[4]
assert(folded_accessxi.nav_apply_dynamic_obstacle(
    T{ x = -11.643, z = -130.031, y = 0 }, collision_target) == collision_target,
    'collision-backed terrain route was replaced by a live entity detour')
assert(obstacle_calls == 0,
    'collision-backed terrain route still scanned dynamic entities')

local state_source = extract(
    'function accessxi.nav_objective_route_state_current(player)',
    'function accessxi.nav_start_authorized_objective_route(target, player)')
local state_chunk = assert(loadstring(state_source, '@reader-objective-active-state'))
setfenv(state_chunk, setmetatable({
    accessxi = accessxi,
    nav_clean_field = clean,
}, { __index = _G }))
state_chunk()

local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local active_cancel_count = 0
accessxi.nav_cancel_mission_quest_route = function()
    active_cancel_count = active_cancel_count + 1
    accessxi.nav_objective_route_state = nil
    return true
end
local function active_state_case(mutator, mode, message)
    local saved = clone(copied)
    saved.objective_contract_snapshot.route_ready = true
    accessxi.nav_objective_route_state = saved
    local fresh = clone(saved)
    if mutator ~= nil then mutator(fresh) end
    accessxi.nav_mission_quest_prepare_route = function()
        return mode == 'blocked' and nil or fresh, message or '', mode or 'ready'
    end
    local before = active_cancel_count
    local current, reason = accessxi.nav_objective_route_revalidate_or_cancel({ zone = 143 })
    return current, reason, active_cancel_count - before
end

assert(select(1, active_state_case(nil)) == true)
for _, drift in ipairs({
    function(value) value.objective_character_identity = 'other:1001' end,
    function(value) value.objective_world_id = 1002 end,
    function(value) value.objective_session_epoch = 78 end,
    function(value) value.objective_native_key = 'mission:Bastok:changed' end,
    function(value) value.objective_candidate_id = 'candidate:changed' end,
    function(value) value.objective_action_id = 'action:changed' end,
    function(value) value.objective_destination_id = 'destination:changed' end,
    function(value) value.objective_route_contract_id = 'route:v2:' .. string.rep('b', 64) end,
    function(value) value.objective_contract_snapshot.contract_id = 'route:v2:' .. string.rep('b', 64) end,
    function(value) value.x = value.x + 1 end,
}) do
    local current, reason, cancelled = active_state_case(drift)
    assert(current == false and tostring(reason or '') ~= '' and cancelled == 1,
        'active objective state drift did not cancel only its route')
end
local current, reason, cancelled = active_state_case(nil, 'blocked', 'Objective is no longer active.')
assert(current == false and reason == 'Objective is no longer active.' and cancelled == 1)

local spoken = {}
local logged = {}
local ordinary_route_calls = 0
local objective_start_calls = 0
local test_start_calls = 0
local menu_environment = setmetatable({
    accessxi = accessxi,
    T = T,
    nav_clean_field = clean,
    nav_cached_player_position = function() return { zone = 143, x = 0, z = 0, y = 0 } end,
    nav_current_category = function() return { key = 'mission' } end,
    nav_menu_rebuild = function() end,
    speak = function(text) spoken[#spoken + 1] = text end,
    log_line = function(text) logged[#logged + 1] = text end,
    tick = function() return 1000 end,
    nav_write_route_evidence = function() end,
}, { __index = _G })
local menu_source = extract('local function nav_menu_start_route()', '\nlocal nav_route_stop;')
local beacon_reset_source = extract(
    'function accessxi.nav_beacon_reset_direction_state()',
    'function accessxi.nav_beacon_direction_delta')
local menu_chunk = assert(loadstring(
    beacon_reset_source .. '\n' .. menu_source .. '\nreturn nav_menu_start_route',
    '@reader-nav-menu-start'))
setfenv(menu_chunk, menu_environment)
local nav_menu_start_route = assert(menu_chunk())

local function reset_menu(item, result_payload, result_message, result_mode)
    spoken = {}
    logged = {}
    ordinary_route_calls = 0
    objective_start_calls = 0
    test_start_calls = 0
    accessxi.nav_menu_items = T{ item }
    accessxi.nav_menu_index = 1
    accessxi.nav_active = false
    accessxi.nav_destination = nil
    accessxi.nav_route_points = T{}
    accessxi.nav_dat_collision_pending = nil
    accessxi.nav_zone_search_target = nil
    accessxi.nav_mission_quest_prepare_route = function()
        return result_payload, result_message, result_mode
    end
    accessxi.nav_clear_zone_search = function() end
    accessxi.nav_transport_clear = function() end
    accessxi.nav_dangruf_fount_drop_clear = function() end
    accessxi.nav_resolve_live_entity_point = function() return nil end
    accessxi.nav_compute_route_with_zoneline_approach = function()
        ordinary_route_calls = ordinary_route_calls + 1
        error('ordinary route computation is forbidden for an authorized objective')
    end
    accessxi.nav_zone_search_start_next_leg = function()
        ordinary_route_calls = ordinary_route_calls + 1
        error('ordinary zone search is forbidden for an authorized objective')
    end
    accessxi.nav_start_authorized_objective_route = function(target, player)
        objective_start_calls = objective_start_calls + 1
        assert(target == result_payload)
        assert(player.zone == 143)
        accessxi.nav_active = true
        accessxi.nav_destination = target
        return 'Starting verified objective route.', true
    end
    accessxi.nav_start_test_objective_route = function(target, player)
        test_start_calls = test_start_calls + 1
        assert(target == result_payload and target.objective_test_route == true)
        assert(player.zone == 143)
        accessxi.nav_active = true
        accessxi.nav_destination = target
        return 'Source-verified mission objective. Starting ordinary route.', true
    end
end

local objective_item = {
    zone = 143,
    name = 'Fixture objective',
    kind = 'mission',
    objective_kind = 'mission',
}

for _, broken_prepare in ipairs({
    function() accessxi.nav_mission_quest_prepare_route = nil end,
    function()
        accessxi.nav_mission_quest_prepare_route = function()
            error('synthetic objective prepare failure')
        end
    end,
}) do
    reset_menu(objective_item, nil, '', 'blocked')
    broken_prepare()
    local ok, reason = pcall(nav_menu_start_route)
    assert(ok, 'objective prepare failure escaped the I handler: ' .. tostring(reason))
    assert(accessxi.nav_active == false and objective_start_calls == 0 and ordinary_route_calls == 0,
        'missing or throwing objective prepare seam fell through to ordinary navigation')
    assert(#spoken == 1 and spoken[1] == 'Objective route preparation is unavailable.')
end

reset_menu(objective_item, 'Open the marked door, then speak to the guard.', '', 'instruction')
nav_menu_start_route()
assert(#spoken == 1 and spoken[1] == 'Open the marked door, then speak to the guard.',
    'instruction mode must speak the complete action')
assert(accessxi.nav_active == false and objective_start_calls == 0 and ordinary_route_calls == 0,
    'instruction mode must start zero routes')

reset_menu(objective_item, nil, 'No rooted route contract matches this objective destination.', 'blocked')
nav_menu_start_route()
assert(#spoken == 1 and spoken[1] == 'No rooted route contract matches this objective destination.')
assert(accessxi.nav_active == false and objective_start_calls == 0 and ordinary_route_calls == 0,
    'blocked mode must start zero routes')

local ready_payload = {
    zone = 143,
    name = 'Fixture target',
    x = 1,
    z = 2,
    y = 3,
    kind = 'mission',
    objective_kind = 'mission',
    objective_native_key = 'mission:Bastok:3',
    objective_guide_step_id = 'mission:Bastok:3:step-006',
    objective_character_identity = 'alpha:1001',
    objective_world_id = 1001,
    objective_session_epoch = 77,
    objective_candidate_id = 'candidate:one',
    objective_action_id = 'action:one',
    objective_group_id = '',
    objective_destination_id = 'destination:one',
    objective_classification = 'catalogue-candidate',
    objective_action_instruction = 'Travel to the fixture target.',
    objective_instruction_only = false,
    objective_route_contract_id = snapshot.contract_id,
    objective_contract_snapshot = snapshot,
}
reset_menu(objective_item, ready_payload, '', 'ready')
nav_menu_start_route()
assert(#spoken == 1 and spoken[1] == 'Starting verified objective route.')
assert(accessxi.nav_active == true and accessxi.nav_destination == ready_payload)
assert(objective_start_calls == 1 and ordinary_route_calls == 0,
    'ready mode must dispatch only to the rooted objective route seam')

local test_payload = {
    zone = 144,
    name = 'Source-backed fixture target',
    x = 4,
    z = 5,
    y = 6,
    kind = 'mission',
    objective_kind = 'mission',
    objective_native_key = 'mission:Bastok:3',
    objective_guide_step_id = 'mission:Bastok:3:step-006',
    objective_character_identity = 'alpha:1001',
    objective_world_id = 1001,
    objective_session_epoch = 77,
    objective_candidate_id = 'candidate:source-backed',
    objective_action_id = 'action:source-backed',
    objective_group_id = '',
    objective_destination_id = 'destination:source-backed',
    objective_classification = 'catalogue-candidate',
    objective_action_instruction = 'Travel to the source-backed fixture target.',
    objective_route_recommendation = 'Recommended: carry Silent Oil. Use it before entering areas with sound-detecting enemies to avoid aggro.',
    objective_instruction_only = false,
    objective_test_route = true,
    verified = false,
}
reset_menu(objective_item, test_payload, '', 'test-ready')
nav_menu_start_route()
assert(test_start_calls == 1 and objective_start_calls == 0 and ordinary_route_calls == 0,
    'test-ready mode must dispatch only to the explicit test-route seam')
assert(#spoken == 1 and spoken[1] == 'Source-verified mission objective. Starting ordinary route.',
    'the explicit route must identify the source-verified mission objective')
assert(#logged == 1 and logged[1]:lower():find('source route', 1, true) ~= nil,
    'the explicit route must be logged as a source route')

reset_menu(objective_item, test_payload, '', 'test-ready')
nav_menu_start_route()
assert(test_start_calls == 1 and objective_start_calls == 0 and ordinary_route_calls == 0,
    'source-ready mode must still dispatch only to the explicit ordinary-route seam')
assert(#spoken == 1 and spoken[1] == 'Source-verified mission objective. Starting ordinary route.',
    'packet freshness must not be announced as a source-route blocker')

ready_payload.zone = 144
reset_menu(objective_item, ready_payload, '', 'ready')
accessxi.nav_start_authorized_objective_route = function(target, player)
    objective_start_calls = objective_start_calls + 1
    assert(target.zone == 144 and player.zone == 143)
    return 'No exact current objective leg is proven from this zone.', false
end
nav_menu_start_route()
assert(objective_start_calls == 1 and ordinary_route_calls == 0 and accessxi.nav_active == false,
    'cross-zone ready mode must block rather than enter ordinary zone search')
assert(#spoken == 1 and spoken[1] == 'No exact current objective leg is proven from this zone.')

for _, failure in ipairs({
    {
        expected = 'Verified objective route execution is unavailable.',
        install = function() accessxi.nav_start_authorized_objective_route = nil end,
    },
    {
        expected = 'Verified objective route execution failed safely.',
        install = function()
            accessxi.nav_start_authorized_objective_route = function()
                error('synthetic objective start failure')
            end
        end,
    },
    {
        expected = 'Current objective route changed.',
        install = function()
            accessxi.nav_start_authorized_objective_route = function()
                return 'Current objective route changed.', false
            end
        end,
    },
}) do
    reset_menu(objective_item, ready_payload, '', 'ready')
    failure.install()
    local ok, reason = pcall(nav_menu_start_route)
    assert(ok, 'objective start failure escaped: ' .. tostring(reason))
    assert(#spoken == 1 and spoken[1] == failure.expected)
    assert(accessxi.nav_active == false and ordinary_route_calls == 0,
        'objective start failure fell back to ordinary navigation')
end

for _, corrupt in ipairs({
    function(payload) payload.objective_route_contract_id = '' end,
    function(payload) payload.objective_contract_snapshot = nil end,
    function(payload) payload.objective_world_id = nil end,
    function(payload) payload.objective_session_epoch = nil end,
    function(payload) payload.objective_candidate_id = nil end,
    function(payload) payload.objective_action_id = nil end,
    function(payload) payload.objective_group_id = nil end,
    function(payload) payload.objective_destination_id = nil end,
    function(payload) payload.objective_native_key = nil end,
    function(payload) payload.objective_guide_step_id = nil end,
    function(payload) payload.objective_character_identity = nil end,
    function(payload) payload.objective_classification = nil end,
    function(payload) payload.objective_action_instruction = nil end,
    function(payload) payload.objective_contract_snapshot.contract_id = 'route:v2:' .. string.rep('b', 64) end,
    function(payload) payload.objective_contract_snapshot.candidate_id = 'candidate:other' end,
    function(payload) payload.objective_contract_snapshot.action_id = 'action:other' end,
    function(payload) payload.objective_contract_snapshot.group_id = 'group:other' end,
    function(payload) payload.objective_contract_snapshot.destination_id = 'destination:other' end,
    function(payload) payload.objective_contract_snapshot.route_ready = false end,
}) do
    local payload = {
        zone = 143,
        name = 'Fixture target',
        x = 1,
        z = 2,
        y = 3,
        kind = 'mission',
        objective_kind = 'mission',
        objective_native_key = 'mission:Bastok:3',
        objective_guide_step_id = 'mission:Bastok:3:step-006',
        objective_character_identity = 'alpha:1001',
        objective_world_id = 1001,
        objective_session_epoch = 77,
        objective_candidate_id = 'candidate:one',
        objective_action_id = 'action:one',
        objective_group_id = '',
        objective_destination_id = 'destination:one',
        objective_classification = 'catalogue-candidate',
        objective_action_instruction = 'Travel to the fixture target.',
        objective_route_contract_id = snapshot.contract_id,
        objective_contract_snapshot = {
            contract_id = snapshot.contract_id,
            candidate_id = snapshot.candidate_id,
            action_id = snapshot.action_id,
            group_id = snapshot.group_id,
            destination_id = snapshot.destination_id,
            route_ready = true,
        },
    }
    corrupt(payload)
    reset_menu(objective_item, payload, '', 'ready')
    nav_menu_start_route()
    assert(accessxi.nav_active == false and objective_start_calls == 0 and ordinary_route_calls == 0,
        'corrupt objective-ready schema reached a route engine')
    assert(#spoken == 1 and spoken[1] == 'Verified objective route authorization is incomplete.')
end

local ordinary_item = {
    zone = 143,
    name = 'Ordinary destination',
    x = 10,
    z = 0,
    y = 0,
    kind = 'area',
}
reset_menu(ordinary_item, nil, '', 'not-objective')
accessxi.nav_compute_route_with_zoneline_approach = function(player, target)
    ordinary_route_calls = ordinary_route_calls + 1
    return T{ player, target }
end
accessxi.nav_point_effective_kind = function(point) return point.kind end
accessxi.nav_route_direct_fallback_block_reason = function() return '' end
accessxi.nav_area_point_direct_route_allowed = function() return true end
accessxi.nav_area_point_reachable = function() return true end
accessxi.nav_guidance_phrase = function() return 'Go straight.' end
accessxi.nav_first_route_index = function() return 1 end
accessxi.nav_beacon_enabled = false
nav_menu_start_route()
assert(ordinary_route_calls == 1 and objective_start_calls == 0,
    'ordinary navigation no longer uses its existing route engine')
assert(accessxi.nav_active == true and accessxi.nav_destination == ordinary_item,
    'ordinary route start behavior changed')

-- A menu route selected before its silent terrain preload finishes must keep
-- the safe asynchronous start, but it cannot claim a beacon is active while
-- there are no usable route points or audible guidance.
reset_menu(ordinary_item, nil, '', 'not-objective')
accessxi.nav_compute_route_with_zoneline_approach = function(player, target)
    ordinary_route_calls = ordinary_route_calls + 1
    accessxi.nav_dat_collision_pending = T{
        destination = target,
        message = 'Mapping terrain for this area. Navigation will start automatically.',
    }
    return T{}
end
accessxi.nav_point_effective_kind = function(point) return point.kind end
accessxi.nav_route_direct_fallback_block_reason = function() return '' end
accessxi.nav_area_point_direct_route_allowed = function() return false end
accessxi.nav_area_point_reachable = function() return true end
accessxi.nav_beacon_enabled = true
nav_menu_start_route()
assert(ordinary_route_calls == 1 and accessxi.nav_dat_collision_pending ~= nil,
    'pending collision route did not retain its automatic-start state')
assert(accessxi.nav_active == true and accessxi.nav_route_points:len() == 0,
    'pending collision route was not held for its automatic safe start')
assert(#spoken == 1
    and spoken[1] == 'Safe route is still preparing. Navigation will start automatically.'
    and not spoken[1]:find('Beacon active', 1, true),
    'pending menu route falsely claimed an active beacon')

local test_start_source = extract(
    'function accessxi.nav_start_test_objective_route(target, player)',
    'function accessxi.nav_start_authorized_objective_route(target, player)')
local test_start_chunk = assert(loadstring(test_start_source, '@reader-objective-test-start'))
setfenv(test_start_chunk, setmetatable({
    accessxi = accessxi,
    T = T,
    nav_clean_field = clean,
}, { __index = _G }))
test_start_chunk()

local same_zone_calls = 0
local cross_zone_calls = 0
accessxi.nav_clear_zone_search = function()
    accessxi.nav_zone_search_target = nil
end
accessxi.nav_start_route_to_point = function(target, reason)
    same_zone_calls = same_zone_calls + 1
    assert(target.objective_test_route == true and reason == 'objective-test-route')
    accessxi.nav_active = true
    accessxi.nav_destination = target
    return 'Starting same-zone route.'
end
accessxi.nav_zone_search_start_next_leg = function(reason)
    cross_zone_calls = cross_zone_calls + 1
    assert(reason == 'objective-test-route')
    assert(accessxi.nav_zone_search_target.objective_test_route == true)
    accessxi.nav_active = true
    return 'Starting cross-zone route.'
end

local same_target = clone(test_payload)
same_target.zone = 143
local text, started = accessxi.nav_start_test_objective_route(same_target, { zone = 143 })
assert(started == true and text == 'Source-verified mission objective. Starting same-zone route.')
assert(same_zone_calls == 1 and cross_zone_calls == 0
    and accessxi.nav_objective_route_state == nil,
    'same-zone test route did not use ordinary point navigation')

accessxi.nav_active = false
local cross_target = clone(test_payload)
text, started = accessxi.nav_start_test_objective_route(cross_target, { zone = 143 })
assert(started == true and text == 'Source-verified mission objective. Starting cross-zone route.')
assert(same_zone_calls == 1 and cross_zone_calls == 1
    and accessxi.nav_zone_search_target.objective_test_route == true
    and accessxi.nav_objective_route_state == nil,
    'cross-zone test route did not use ordinary zone-search navigation')

-- Mission rows can share their title and native source while representing
-- distinct exact destinations. Rebuilding must preserve the exact row, and L
-- must advance the existing mission snapshot without recomputing every active
-- mission context.
local east = {
    name = 'Smash the Orcish Scouts', source = 'native-active-mission:San d\'Oria:0',
    objective_kind = 'mission', objective_native_key = 'mission:San d\'Oria:1',
    objective_guide_step_id = 'mission:San d\'Oria:1:step-005',
    objective_candidate_id = 'candidate:east', objective_action_id = 'action:axe',
    objective_group_id = 'group:east', objective_destination_id = 'destination:east',
}
local west = clone(east)
west.objective_candidate_id = 'candidate:west'
west.objective_group_id = 'group:west'
west.objective_destination_id = 'destination:west'
local next_mission = {
    name = 'Rumors from the West', source = 'native-active-mission:Seekers of Adoulin:1',
    objective_kind = 'mission', objective_native_key = 'mission:Seekers of Adoulin:1',
    objective_guide_step_id = 'mission:Seekers of Adoulin:1:step-001',
    objective_candidate_id = 'candidate:rumors', objective_action_id = 'action:darcia',
    objective_group_id = '', objective_destination_id = 'destination:darcia',
}
local move_accessxi = {
    nav_menu_items = T{ east, west, next_mission },
    nav_menu_index = 2,
    nav_live_category = function(category_key) return category_key == 'mission' end,
}
local rebuild_calls = 0
local move_spoken = {}
local move_source = extract('accessxi.nav_menu_selection_key = function (item)',
    '\nlocal function nav_menu_category_move(delta)')
local move_chunk = assert(loadstring(move_source
    .. '\nreturn nav_menu_rebuild, nav_menu_move', '@reader-nav-menu-move'))
setfenv(move_chunk, setmetatable({
    accessxi = move_accessxi,
    T = T,
    nav_clean_field = clean,
    nav_current_category = function() return { key = 'mission' } end,
    nav_build_menu_items = function()
        rebuild_calls = rebuild_calls + 1
        return T{ clone(east), clone(west), clone(next_mission) }
    end,
    nav_menu_item_speech = function()
        return move_accessxi.nav_menu_items[move_accessxi.nav_menu_index].objective_destination_id
    end,
    speak = function(text) move_spoken[#move_spoken + 1] = text end,
    log_line = function() end,
}, { __index = _G }))
local nav_menu_rebuild_exact, nav_menu_move_next = move_chunk()

nav_menu_rebuild_exact(true)
assert(move_accessxi.nav_menu_index == 2,
    'mission rebuild collapsed distinct same-name destinations onto the first row')
local rebuilds_before_l = rebuild_calls
nav_menu_move_next(1)
assert(rebuild_calls == rebuilds_before_l,
    'L rebuilt the unchanged mission list instead of advancing its current snapshot')
assert(move_accessxi.nav_menu_index == 3
    and move_spoken[#move_spoken] == 'destination:darcia',
    'L did not advance from the selected mission destination to the next row')

-- Completing a source-backed interaction changes the objective cursor without
-- changing the native mission packet.  The live Rescue Drill trace proved the
-- fresh list rejected Galaihaurat while K still repeated that stale row. Route
-- start leaves this speech browser snapshot closed but populated, so the event
-- callback must mark it dirty and the next Missions hotkey must rebuild it.
local completed_galaihaurat = {
    name = 'The Rescue Drill', source = 'native-active-mission:San d\'Oria:3',
    objective_kind = 'mission', objective_native_key = 'mission:San d\'Oria:4',
    objective_guide_step_id = 'mission:San d\'Oria:4:step-006',
    objective_candidate_id = 'candidate:galaihaurat',
    objective_action_id = 'action:galaihaurat',
    objective_group_id = '', objective_destination_id = 'destination:galaihaurat',
}
local next_rescue_objective = clone(completed_galaihaurat)
next_rescue_objective.objective_guide_step_id = 'mission:San d\'Oria:4:step-014'
next_rescue_objective.objective_candidate_id = 'candidate:next-rescue-objective'
next_rescue_objective.objective_action_id = 'action:next-rescue-objective'
next_rescue_objective.objective_destination_id = 'destination:next-rescue-objective'
local refresh_accessxi = {
    nav_menu_open = false,
    nav_menu_poll_key = 999,
    nav_menu_items = T{ completed_galaihaurat, next_mission },
    nav_menu_index = 1,
    nav_live_category = function(category_key) return category_key == 'mission' end,
}
local refresh_rebuilds = 0
local refresh_spoken = {}
local refresh_chunk = assert(loadstring(move_source
    .. '\nreturn nav_menu_move', '@reader-objective-progress-refresh'))
setfenv(refresh_chunk, setmetatable({
    accessxi = refresh_accessxi,
    T = T,
    nav_clean_field = clean,
    nav_current_category = function() return { key = 'mission' } end,
    nav_build_menu_items = function()
        refresh_rebuilds = refresh_rebuilds + 1
        return T{ clone(next_rescue_objective), clone(next_mission) }
    end,
    nav_menu_item_speech = function()
        return refresh_accessxi.nav_menu_items[refresh_accessxi.nav_menu_index]
            .objective_guide_step_id
    end,
    speak = function(text) refresh_spoken[#refresh_spoken + 1] = text end,
    log_line = function() end,
}, { __index = _G }))
local refresh_menu_repeat = refresh_chunk()

refresh_accessxi.on_objective_interaction_progress_changed('mission', false)
assert(refresh_rebuilds == 0,
    'the event callback synchronously rebuilt Missions during NPC interaction')
assert(refresh_accessxi.nav_menu_poll_key == 0,
    'a completed interaction left the old Missions polling snapshot current')
refresh_menu_repeat(0)
assert(refresh_rebuilds == 1,
    'the first Missions hotkey did not rebuild after a completed interaction')
assert(refresh_accessxi.nav_menu_items[refresh_accessxi.nav_menu_index].objective_guide_step_id
        == 'mission:San d\'Oria:4:step-014'
    and refresh_spoken[#refresh_spoken] == 'mission:San d\'Oria:4:step-014',
    'K repeated the completed objective instead of the fresh mission cursor')

-- The live log reproduced an Enemies-list loop when two static camps shared
-- the same source/name identity. Rebuilding before L remapped the selected
-- second camp onto the first one, then advanced to an earlier row. Browsing
-- must advance through the snapshot that was spoken to the player.
local first_orc_camp = {
    name = 'Orcish Fodder', source = 'generated-enemy-camp', x = 1, z = 1,
    test_row_id = 'first-orc-camp',
}
local row_between_camps = {
    name = 'Ding Bats', source = 'generated-enemy-camp', x = 2, z = 2,
    test_row_id = 'row-between-camps',
}
local selected_orc_camp = clone(first_orc_camp)
selected_orc_camp.x = 3
selected_orc_camp.z = 3
selected_orc_camp.test_row_id = 'selected-orc-camp'
local row_after_selection = {
    name = 'Mouse Bat', source = 'generated-enemy-camp', x = 4, z = 4,
    test_row_id = 'row-after-selection',
}
local enemy_accessxi = {
    nav_menu_items = T{
        first_orc_camp,
        row_between_camps,
        selected_orc_camp,
        row_after_selection,
    },
    nav_menu_index = 3,
    nav_live_category = function(category_key) return category_key == 'enemy' end,
}
local enemy_spoken = {}
local enemy_move_chunk = assert(loadstring(move_source
    .. '\nreturn nav_menu_move', '@reader-enemy-menu-move'))
setfenv(enemy_move_chunk, setmetatable({
    accessxi = enemy_accessxi,
    T = T,
    nav_clean_field = clean,
    nav_current_category = function() return { key = 'enemy' } end,
    nav_build_menu_items = function()
        return T{
            clone(first_orc_camp),
            clone(row_between_camps),
            clone(selected_orc_camp),
            clone(row_after_selection),
        }
    end,
    nav_menu_item_speech = function()
        return enemy_accessxi.nav_menu_items[enemy_accessxi.nav_menu_index].test_row_id
    end,
    speak = function(text) enemy_spoken[#enemy_spoken + 1] = text end,
    log_line = function() end,
}, { __index = _G }))
local enemy_menu_move_next = enemy_move_chunk()

enemy_menu_move_next(1)
assert(enemy_accessxi.nav_menu_index == 4
    and enemy_spoken[#enemy_spoken] == 'row-after-selection',
    'L rebuilt the Enemies list and bounced a duplicate camp selection backward')

-- Mission key-item progression resolves exact guide names lazily against the
-- immutable Windower resource, then trusts only this character/session's live
-- 0x055 ownership rows. Similar names may not be guessed.
assert(source:find('function accessxi.objective_key_item_owned_by_name(name)', 1, true),
    'reader exact objective key-item resolver is missing')
local key_item_resolver_source = extract(
    'function accessxi.objective_key_item_name_key(value)',
    'function accessxi.key_items_resource_row_for_id(id, category, resource)')

local function packet_flags_with_ids(ids)
    local bytes = {}
    for index = 1, 64 do bytes[index] = 0 end
    for _, id in ipairs(ids or {}) do
        local bit_index = tonumber(id) % 512
        local byte_index = math.floor(bit_index / 8) + 1
        bytes[byte_index] = bytes[byte_index] + (2 ^ (bit_index % 8))
    end
    local chars = {}
    for index = 1, 64 do chars[index] = string.char(bytes[index]) end
    return table.concat(chars)
end

local key_item_resource_loads = 0
local key_item_resource = {
    [5] = { id = 5, en = 'letter to the consuls' },
    [6] = { id = 6, en = 'letter to the consuls' },
    [157] = { id = 157, en = 'Orcish hut key' },
    [391] = { id = 391, en = [=[map of King Ranperre's Tomb]=] },
}

local key_item_accessxi = {
    objective_key_item_name_index_cache = nil,
    key_items_packet_identity = 'alpha:1001',
    key_items_packet_session_epoch = 77,
    key_items_packet_source = 'packet_in_055',
    key_items_packet_tables = {
        [0] = {
            flags = packet_flags_with_ids({ 157 }),
            identity = 'alpha:1001',
            session_epoch = 77,
            source = 'packet_in_055',
        },
    },
    current_player_identity = function() return 'alpha:1001' end,
    current_objective_session_epoch = function() return 77 end,
    load_key_items_resource = function()
        key_item_resource_loads = key_item_resource_loads + 1
        return key_item_resource
    end,
    packet_has_bit = function(flags, bit_index)
        local byte = flags:byte(math.floor(bit_index / 8) + 1) or 0
        return math.floor(byte / (2 ^ (bit_index % 8))) % 2 == 1
    end,
}
local key_item_chunk = assert(loadstring(key_item_resolver_source, '@reader-objective-key-items'))
setfenv(key_item_chunk, setmetatable({ accessxi = key_item_accessxi }, { __index = _G }))
key_item_chunk()

assert(key_item_resource_loads == 0,
    'the exact key-item resource index was scanned during reader startup')
local hut_key_owned, hut_key_id =
    key_item_accessxi.objective_key_item_owned_by_name('  ORCISH--hut, key!  ')
assert(hut_key_owned == true and hut_key_id == 157,
    'punctuation and spacing normalization lost the exact owned Orcish hut key')
assert(key_item_resource_loads == 1,
    'the exact key-item resource was not loaded lazily on first use')
local tomb_map_owned, tomb_map_id = key_item_accessxi.objective_key_item_owned_by_name(
    'map of King Ranperre\226\128\153s Tomb')
assert(tomb_map_owned == false and tomb_map_id == 391,
    'apostrophe normalization did not retain the exact unowned tomb-map ID')
assert(key_item_resource_loads == 1,
    'the immutable exact key-item name index was rebuilt after first use')

local duplicate_owned, duplicate_id =
    key_item_accessxi.objective_key_item_owned_by_name('letter to the consuls')
assert(duplicate_owned == false and duplicate_id == nil,
    'an ambiguous key-item name guessed one of multiple IDs')
local missing_owned, missing_id =
    key_item_accessxi.objective_key_item_owned_by_name('key item that does not exist')
assert(missing_owned == false and missing_id == nil,
    'a missing key-item name returned a synthetic ID')

key_item_accessxi.key_items_packet_identity = 'other:2002'
local stale_identity_owned, stale_identity_id =
    key_item_accessxi.objective_key_item_owned_by_name('Orcish hut key')
assert(stale_identity_owned == false and stale_identity_id == 157,
    'another character 0x055 state was trusted or hid the exact resource ID')
key_item_accessxi.key_items_packet_identity = 'alpha:1001'
key_item_accessxi.key_items_packet_session_epoch = 76
local stale_session_owned, stale_session_id =
    key_item_accessxi.objective_key_item_owned_by_name('Orcish hut key')
assert(stale_session_owned == false and stale_session_id == 157,
    'a previous session 0x055 state was trusted or hid the exact resource ID')

key_item_accessxi.objective_key_item_name_index_cache = nil
key_item_accessxi.load_key_items_resource = function()
    key_item_resource_loads = key_item_resource_loads + 1
    return nil
end
local unavailable_owned, unavailable_id =
    key_item_accessxi.objective_key_item_owned_by_name('Orcish hut key')
assert(unavailable_owned == false and unavailable_id == nil,
    'an unavailable key-item resource returned an ID')

-- Mission item progression must use a complete native carried-Inventory scan.
-- Item packets only wake this scan; their payload is never the ownership source.
assert(source:find('function accessxi.refresh_objective_inventory_state(reason)', 1, true),
    'reader native objective Inventory snapshot is missing')
local objective_state_change_source = extract(
    'function accessxi.on_mission_quest_state_changed(kind, reason)',
    'function accessxi.on_objective_interaction_progress_changed(kind, cancelled)')
local inventory_source = extract(
    'function accessxi.refresh_objective_inventory_state(reason)',
    'function accessxi.current_inventory_gil()')
local inventory_accessxi = {
    objective_inventory_counts = {},
    nav_menu_items = T{},
    nav_menu_index = 1,
    nav_menu_selection_key = function(item)
        return tostring(type(item) == 'table' and item.objective_native_key or '')
    end,

    inventory_packet_key = '',
    current_player_name = function() return 'Alpha' end,
    current_player_identity = function() return 'alpha:1001' end,
    current_objective_session_epoch = function() return 77 end,
    escape_probe_log_text = function(value) return tostring(value or '') end,
    resource_item_info_by_name = function(name)
        if clean(name):lower() == 'orcish axe' then
            return { id = 16656, name = 'Orcish Axe' }
        end
        return nil
    end,
}
local function native_inventory_item(id, count)
    local state = { Id = id, Count = count }
    local item = newproxy(true)
    local meta = getmetatable(item)
    meta.__index = state
    meta.__newindex = state
    return item
end
local inventory_items = {
    [1] = native_inventory_item(16656, 1),
    [2] = native_inventory_item(0, 0),
}
assert(type(inventory_items[1]) == 'userdata',
    'the native Inventory fixture must not accidentally behave like a Lua table')
local inventory_failure = false
local inventory_cancel_count = 0
local inventory_route_start_count = 0
local inventory_menu_rebuild_count = 0
local inventory_spoken = {}
local inventory = {
    GetContainerCountMax = function(_, container)
        assert(container == 0, 'objective scan read a remote inventory container')
        if inventory_failure then error('synthetic native Inventory failure') end
        return 2
    end,
    GetContainerItem = function(_, container, slot)
        assert(container == 0, 'objective scan read a remote inventory container')
        return inventory_items[slot]
    end,
}
local inventory_environment = setmetatable({
    accessxi = inventory_accessxi,
    AshitaCore = {
        GetMemoryManager = function()
            return { GetInventory = function() return inventory end }
        end,
    },
    safe_call = function(callback, fallback)
        local ok, value = pcall(callback)
        if ok then return value end
        return fallback
    end,
    nav_clean_field = clean,
    inventory_item_count = function(item) return tonumber(item and item.Count) or 0 end,
    tick = function() return 1000 end,
    log_line = function() end,
    speak = function(text) inventory_spoken[#inventory_spoken + 1] = text end,
    nav_current_category = function() return { key = 'mission' } end,
    nav_menu_rebuild = function()
        inventory_menu_rebuild_count = inventory_menu_rebuild_count + 1
    end,
}, { __index = _G })
local inventory_chunk = assert(loadstring(
    objective_state_change_source .. '\n' .. inventory_source, '@reader-objective-inventory'))
setfenv(inventory_chunk, inventory_environment)
inventory_chunk()

local inventory_changed, inventory_available =
    inventory_accessxi.refresh_objective_inventory_state('test-first-scan')
assert(inventory_changed == true and inventory_available == true,
    'first complete native Inventory scan was not published')
assert(inventory_accessxi.objective_inventory_count(16656) == 1,
    'published native Inventory snapshot lost the Orcish Axe count')
local axe_count, axe_id = inventory_accessxi.objective_inventory_count_by_name('Orcish Axe')
assert(axe_count == 1 and axe_id == 16656,
    'native item name did not resolve to the exact carried item ID')

inventory_changed, inventory_available =
    inventory_accessxi.refresh_objective_inventory_state('test-identical-scan')
assert(inventory_changed == false and inventory_available == true,
    'an unchanged native Inventory scan was republished as a change')

inventory_failure = true
inventory_changed, inventory_available =
    inventory_accessxi.refresh_objective_inventory_state('test-failed-scan')
assert(inventory_changed == false and inventory_available == false,
    'a failed native Inventory scan was treated as complete')
assert(inventory_accessxi.objective_inventory_count(16656) == 1,
    'a failed scan destroyed the last complete native Inventory snapshot')

inventory_accessxi.nav_is_mission_quest_point = function(point)
    return type(point) == 'table' and point.objective_kind == 'mission'
end
inventory_accessxi.nav_mission_quest_route_point_is_current = function()
    return false
end
inventory_accessxi.nav_cancel_mission_quest_route = function()
    inventory_cancel_count = inventory_cancel_count + 1
    inventory_accessxi.nav_destination = nil
    return true
end
inventory_accessxi.nav_start_test_objective_route = function()
    inventory_route_start_count = inventory_route_start_count + 1
end

inventory_failure = false
inventory_accessxi.nav_destination = { objective_kind = 'mission' }
inventory_items[1].Count = 2
inventory_accessxi.schedule_objective_inventory_refresh('test-required-item', 0)
assert(inventory_accessxi.poll_objective_inventory_refresh(1000) == true,
    'a completed changed Inventory scan did not publish its event')
assert(inventory_cancel_count == 1,
    'an active route to the superseded mission step was not cancelled')
assert(inventory_route_start_count == 0,
    'the Inventory transition started another route without an I press')
assert(#inventory_spoken == 1 and inventory_spoken[1]:find('Mission updated', 1, true) ~= nil,
    'route cancellation did not announce the mission update')

inventory_accessxi.nav_destination = nil
inventory_accessxi.nav_menu_open = true
inventory_items[1].Count = 3
inventory_accessxi.schedule_objective_inventory_refresh('test-no-route', 0)
assert(inventory_accessxi.poll_objective_inventory_refresh(1000) == true)
assert(inventory_cancel_count == 1 and inventory_route_start_count == 0,
    'an Inventory-only mission update cancelled or started navigation without a route')
assert(inventory_menu_rebuild_count == 1,
    'an open Missions list did not rebuild after the Inventory transition')
assert(#inventory_spoken == 1,
    'an Inventory-only mission update spoke despite having no route to cancel')

inventory_accessxi.nav_menu_open = false
inventory_accessxi.nav_destination = { objective_kind = 'mission' }
inventory_accessxi.nav_mission_quest_route_point_is_current = function()
    return true
end
inventory_items[1].Count = 4
inventory_accessxi.schedule_objective_inventory_refresh('test-unrelated-item', 0)
assert(inventory_accessxi.poll_objective_inventory_refresh(1000) == true)
assert(inventory_cancel_count == 1,
    'an unrelated Inventory change cancelled a still-current mission route')

inventory_accessxi.nav_destination = { kind = 'area' }
inventory_items[1].Count = 5
inventory_accessxi.schedule_objective_inventory_refresh('test-ordinary-route', 0)
assert(inventory_accessxi.poll_objective_inventory_refresh(1000) == true)
assert(inventory_cancel_count == 1,
    'a mission Inventory change cancelled an ordinary non-mission route')

print('mission and quest reader I-handler integration tests passed')

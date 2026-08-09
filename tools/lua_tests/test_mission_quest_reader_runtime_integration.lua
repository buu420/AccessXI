local reader_path = assert(arg[1], 'reader source path is required')

local file = assert(io.open(reader_path, 'rb'))
local source = assert(file:read('*a'))
file:close()

function string:fmt(...)
    return string.format(self, ...)
end

function string:startswith(prefix)
    return self:sub(1, #prefix) == prefix
end

local list_methods = {}
function list_methods:len() return #self end
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
    objective_classification = 'catalogue-candidate',
    objective_action_instruction = 'Travel to the fixture target.',
    objective_instruction_only = false,
    objective_route_contract_id = snapshot.contract_id,
    objective_contract_snapshot = snapshot,
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
    objective_classification = 'catalogue-candidate',
    objective_action_instruction = 'Travel to the fixture target.',
    objective_instruction_only = false,
    objective_route_contract_id = snapshot.contract_id,
}) do
    assert(copied[field] == expected, 'nav_copy_point dropped objective field ' .. field)
end
assert(type(copied.objective_contract_snapshot) == 'table'
    and copied.objective_contract_snapshot.contract_id == snapshot.contract_id)
assert(copied.objective_contract_snapshot ~= snapshot
    and copied.objective_contract_snapshot.nested ~= snapshot.nested,
    'nav_copy_point must deep-copy the immutable contract snapshot')

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
local ordinary_route_calls = 0
local objective_start_calls = 0
local menu_environment = setmetatable({
    accessxi = accessxi,
    T = T,
    nav_clean_field = clean,
    nav_cached_player_position = function() return { zone = 143, x = 0, z = 0, y = 0 } end,
    nav_menu_rebuild = function() end,
    speak = function(text) spoken[#spoken + 1] = text end,
    log_line = function() end,
    tick = function() return 1000 end,
    nav_write_route_evidence = function() end,
}, { __index = _G })
local menu_source = extract('local function nav_menu_start_route()', '\nlocal nav_route_stop;')
local menu_chunk = assert(loadstring(menu_source .. '\nreturn nav_menu_start_route', '@reader-nav-menu-start'))
setfenv(menu_chunk, menu_environment)
local nav_menu_start_route = assert(menu_chunk())

local function reset_menu(item, result_payload, result_message, result_mode)
    spoken = {}
    ordinary_route_calls = 0
    objective_start_calls = 0
    accessxi.nav_menu_items = T{ item }
    accessxi.nav_menu_index = 1
    accessxi.nav_active = false
    accessxi.nav_destination = nil
    accessxi.nav_route_points = T{}
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
    assert(#spoken == 1 and spoken[1] == 'Verified objective route preparation is unavailable.')
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

print('mission and quest reader I-handler integration tests passed')

-- Promyvion live evidence must survive the real reader seams.
--
-- The 2026-09-01 Holla trace routed to a catalogue Receptacle platform while a
-- different, rendered Receptacle was standing nearby.  The same trace showed a
-- Stream retain status 8 after its entity slot despawned.  These checks lift the
-- production helpers from the deployed reader so a faithful replacement in the
-- harness cannot make a broken seam look green.

local addon_path = (os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader') .. '/accessxi_reader.lua'
local file = assert(io.open(addon_path, 'rb'))
local source = file:read('*a')
file:close()

local passed, failed = 0, 0

local function claim(name, condition, detail)
    if condition then
        passed = passed + 1
        print(('PASS %s'):format(name))
    else
        failed = failed + 1
        print(('FAIL %s%s'):format(name, detail and (': ' .. tostring(detail)) or ''))
    end
end

local function extract(marker, next_marker)
    local first = assert(source:find(marker, 1, true), 'missing production marker: ' .. marker)
    local last = assert(source:find(next_marker, first + #marker, true),
        'missing production end marker after: ' .. marker)
    return source:sub(first, last - 1)
end

local function load_production(marker, next_marker)
    local chunk, err = loadstring(extract(marker, next_marker))
    assert(chunk, err)
    chunk()
end

accessxi = {}

function string.startswith(value, prefix)
    return value:sub(1, #prefix) == prefix
end

function string.trim(value)
    return value:match('^%s*(.-)%s*$')
end

function string.contains(value, needle)
    return value:find(needle, 1, true) ~= nil
end

function string.fmt(value, ...)
    return value:format(...)
end

bit = bit or {}
if type(bit.band) ~= 'function' then
    function bit.band(left, right)
        left, right = tonumber(left) or 0, tonumber(right) or 0
        local result, place = 0, 1
        while left > 0 or right > 0 do
            local a, b = left % 2, right % 2
            if a == 1 and b == 1 then result = result + place end
            left, right, place = math.floor(left / 2), math.floor(right / 2), place * 2
        end
        return result
    end
end

function nav_clean_field(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function nav_zone_id()
    return 16
end

nav_point_key = function(point)
    return ('%d:%s:%d:%d'):format(
        tonumber(point.zone) or 0,
        tostring(point.name or ''):lower(),
        math.floor((tonumber(point.x) or 0) * 10 + 0.5),
        math.floor((tonumber(point.z) or 0) * 10 + 0.5))
end

accessxi.nav_point_is_live_entity = function(point)
    return tostring(point and point.source or ''):lower():sub(1, 12) == 'live-entity:'
        or (point and (point.live_kind == 'enemy' or point.live_kind == 'live-nm'))
end

accessxi.nav_point_effective_kind = function(point)
    return tostring(point and (point.live_kind or point.kind) or ''):lower()
end

accessxi.nav_entity_is_enemy = function(point)
    return point ~= nil and (point.live_kind == 'enemy' or point.kind == 'enemy'
        or tonumber(point.type) == 2)
end

-- A retained entity slot is not live evidence.  This is deliberately the first
-- claim: the old reader accepted the stale status-8 slot that prompted this fix.
load_production('function accessxi.nav_live_entity_valid(pos)',
    'function accessxi.nav_live_entity_search_range()')
claim('rendered enemy is valid live evidence', accessxi.nav_live_entity_valid({
    name = 'Memory Receptacle', zone = 16, x = -40, z = 200,
    hp = 100, status = 1, type = 2, render_flags_1 = 0,
}) == true)
claim('despawned alive-looking slot is not live evidence', accessxi.nav_live_entity_valid({
    name = 'Memory Receptacle', zone = 16, x = -40, z = 200,
    hp = 100, status = 1, type = 2, render_flags_1 = 0x1000,
}) == false)
claim('enemy without render evidence is unknown, not live', accessxi.nav_live_entity_valid({
    name = 'Memory Receptacle', zone = 16, x = -40, z = 200,
    hp = 100, status = 1, type = 2,
}) == false)
claim('rendered corpse is not a live enemy row', accessxi.nav_live_entity_valid({
    name = 'Memory Receptacle', zone = 16, x = -40, z = 200,
    hp = 0, status = 1, type = 2, render_flags_1 = 0,
}) == false)

local entity_position = extract('local function nav_entity_position(index, want_stream_evidence)',
    'function accessxi.nav_entity_snapshot_for_server_id(server_id)')
local render_assignment = assert(entity_position:find('render_flags_1%s*='),
    'nav_entity_position no longer records render_flags_1')
local stream_only = assert(entity_position:find('if %(want_stream_evidence == true%) then'),
    'nav_entity_position stream-evidence branch missing')
claim('ordinary live scans capture the despawn bit', render_assignment < stream_only)
claim('an unreadable render flag is preserved as unknown',
    entity_position:find('GetRenderFlags1%(index%); end, nil%)') ~= nil)
claim('an unreadable Stream render flag is preserved as unknown',
    entity_position:find('GetRenderFlags0%(index%); end, nil%)') ~= nil)

-- The production merge helper is the observable contract: a rendered enemy at
-- the same browse point replaces the catalogue row, while a static-only point
-- remains available and a non-enemy duplicate keeps the established behavior.
load_production('function accessxi.nav_merge_live_menu_point(items, seen, point)',
    'function accessxi.nav_menu_point_speech_name(point)')
load_production('function accessxi.nav_menu_point_speech_name(point)',
    'accessxi.nav_search_text = function (value)')

local static = {
    zone = 16, name = 'Memory Receptacle', x = -40.04, z = 200.04, y = -1,
    kind = 'enemy', source = 'lsb-mob-spawn-camps', confidence = 'untested',
}
local live = {
    zone = 16, name = 'Memory Receptacle', x = -40.03, z = 200.03, y = -0.5,
    kind = 'enemy', live_kind = 'enemy', source = 'live-entity:29:16842781',
    index = 29, server_id = 16842781, distance = 2.4,
}
local items = { static }
local seen = { [nav_point_key(static)] = 1 }
local changed, mode = accessxi.nav_merge_live_menu_point(items, seen, live)
claim('overlapping live Receptacle replaces static platform', changed == true and mode == 'replaced')
claim('overlap produces one browse row', #items == 1)
claim('replacement carries exact live identity', items[1] == live
    and items[1].server_id == 16842781 and items[1].index == 29)
claim('replacement carries current live coordinates', items[1].x == -40.03
    and items[1].z == 200.03 and items[1].y == -0.5)
claim('live row is audibly current',
    accessxi.nav_menu_point_speech_name(items[1]) == 'Memory Receptacle, visible now')
claim('static-only row is audibly a search platform',
    accessxi.nav_menu_point_speech_name(static) == 'Memory Receptacle search platform')
claim('static-only row is never called present',
    not accessxi.nav_menu_point_speech_name(static):lower():find('present', 1, true))

-- The evidence-bearing name must survive the keypress.  The old implementation
-- used it only in the browse row, then reverted to raw point.name for both the
-- route-start and arrival speech, recreating the original false claim.
local menu_start = extract('local function nav_menu_start_route()',
    'local function nav_menu_handle_action(action)')
claim('menu route start keeps the Receptacle evidence label',
    menu_start:find('nav_menu_point_speech_name%(item%)') ~= nil)
local point_start = extract('function accessxi.nav_start_route_to_point(point, reason)',
    'function accessxi.nav_zone_search_npc_results(query, player)')
claim('programmatic route start keeps the Receptacle evidence label',
    point_start:find('nav_menu_point_speech_name%(point%)') ~= nil)
local route_poll = extract('local function poll_nav_route()',
    'local function load_step(name, fn)')
claim('arrival keeps the Receptacle evidence label',
    route_poll:find('nav_menu_point_speech_name%(destination%)') ~= nil)

local other_live = {
    zone = 16, name = 'Memory Receptacle', x = 40, z = 320, y = 0,
    kind = 'enemy', live_kind = 'enemy', source = 'live-entity:30:16842782',
    index = 30, server_id = 16842782,
}
changed, mode = accessxi.nav_merge_live_menu_point(items, seen, other_live)
claim('non-overlapping live Receptacle remains a separate exact row',
    changed == true and mode == 'added' and #items == 2 and items[2] == other_live)

local static_npc = { zone = 16, name = 'Moogle', x = 10, z = 10,
    kind = 'npc', source = 'database' }
local live_npc = { zone = 16, name = 'Moogle', x = 10, z = 10,
    kind = 'npc', live_kind = 'npc', source = 'live-entity:7:123', server_id = 123 }
local npc_items = { static_npc }
local npc_seen = { [nav_point_key(static_npc)] = 1 }
changed, mode = accessxi.nav_merge_live_menu_point(npc_items, npc_seen, live_npc)
claim('non-enemy duplicate behavior is unchanged',
    changed == false and mode == 'duplicate' and #npc_items == 1 and npc_items[1] == static_npc)

-- The packet seam must notify navigation before objective-credit actor checks.
-- Tenzen landed the witnessed retail kill; whether Ashita classifies that Trust
-- as a party actor must not decide whether the Stream observer starts.
--
-- Do not leave the harness's nav_clean_field surrogate in scope here.  The
-- deployed helper used that name 6,000 lines before its local declaration, so
-- Lua compiled the call as a nil global.  Keeping this surrogate installed made
-- every offline claim green while every real 0x029 defeat crashed the addon.
local harness_nav_clean_field = nav_clean_field
nav_clean_field = nil
load_production('function accessxi.nav_promyvion_note_defeat_message(',
    'function accessxi.capture_combat_action_packet(e)')
local defeats = {}
accessxi.nav_promyvion_receptacle_defeated = function(server_id, now)
    if server_id ~= 16842781 then return false end
    defeats[#defeats + 1] = { server_id = server_id, now = now }
    return true
end
local exact_ok, exact_result = pcall(accessxi.nav_promyvion_note_defeat_message,
    16842781, 6, 1000)
claim('exact Receptacle defeat needs no later-declared name cleaner',
    exact_ok and exact_result == true and #defeats == 1
        and defeats[1].server_id == 16842781)
claim('non-defeat message cannot arm observation',
    accessxi.nav_promyvion_note_defeat_message(16842781, 1, 1001) == false
        and #defeats == 1)
claim('another enemy cannot arm Receptacle observation',
    accessxi.nav_promyvion_note_defeat_message(16842782, 6, 1002) == false
        and #defeats == 1)
nav_clean_field = harness_nav_clean_field

local combat = extract('function accessxi.capture_combat_action_packet(e)',
    'accessxi.handle_chat_text = function (mode, text, injected)')
local defeat_packet = combat:sub(1, assert(combat:find("if %(packet_id ~= 0x028%) then return; end"),
    '0x029 battle-message branch missing'))
claim('0x029 defeat evidence uses the pointer-safe packet reader',
    defeat_packet:find("packet_event_string%(e, 'data_modified', 'size'%)") ~= nil
        and defeat_packet:find('local data = e.data_modified or e.data', 1, true) == nil)
claim('Promyvion defeat observer cannot unwind the shared packet callback',
    defeat_packet:find('pcall%(accessxi%.nav_promyvion_note_defeat_message') ~= nil)
local notify_at = assert(combat:find('nav_promyvion_note_defeat_message', 1, true),
    '0x029 handler does not notify Promyvion navigation')
local dying_entity_lookup_at = assert(combat:find('combat_entity_hp_summary_for_server', 1, true),
    '0x029 objective target-name lookup missing')
local actor_gate_at = assert(combat:find('if (actor_ok ~= true) then return; end', 1, true),
    '0x029 objective actor gate missing')
claim('exact-id Promyvion evidence precedes the dying-entity name lookup',
    notify_at < dying_entity_lookup_at)
claim('Trust kill evidence is consumed before objective actor credit', notify_at < actor_gate_at)

-- A waiting Promyvion phase used to return before moving live targets could be
-- refreshed.  Assert the order inside the deployed route poll, not a surrogate.
local poll = extract('local function poll_nav_route()',
    'local function load_step(name, fn)')
local refresh_at = assert(poll:find('nav_refresh_live_route_destination(player, now)', 1, true),
    'route poll does not refresh live destinations')
local promyvion_at = assert(poll:find('nav_promyvion_poll(player, destination, now)', 1, true),
    'route poll does not invoke Promyvion navigation')
claim('live target refresh precedes Promyvion early return', refresh_at < promyvion_at)

print(('promyvion live integration: %d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)

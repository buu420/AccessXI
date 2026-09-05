-- Structural mission and quest coverage census: route and completion evidence.
--
-- Uses the deployed reconciled guide, destination catalogue, zone-line graph,
-- resolver, and progression actions. Low coverage is a measurement, not a test
-- failure; only an inability to compute exits non-zero.
--
--   luajit tools/test_mission_completion_coverage.lua

local ADDON = os.getenv('ACCESSXI_ADDON')
    or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

accessxi = {};
T = function (value)
    value = value or {};
    value.len = function (self) return #self; end;
    value.append = function (self, item) self[#self + 1] = item; end;
    return value;
end;
string.fmt = string.format;

local tool_dir = (arg[0] or ''):match('^(.*)[/\\]');
if (tool_dir == nil or tool_dir == '' or tool_dir == '.') then
    tool_dir = os.getenv('ACCESSXI_TOOLS') or 'C:/Users/buu42/AccessXI/tools';
end

-- Reusing this harness keeps role members, destination-id lookup, graph
-- semantics, and future catalogue changes in one production-shaped bootstrap.
local saved_embed = WALKTHROUGH_EMBED;
WALKTHROUGH_EMBED = true;
local env = dofile(tool_dir .. '/test_mission_step_resolver.lua');
WALKTHROUGH_EMBED = saved_embed;

local resolver = assert(env.resolver);
local make_ctx = assert(env.make_ctx);
local zone_names = assert(env.zone_names);
local progression_destinations = assert(env.progression_destinations);
local progression_info = assert(env.progression_info);
local name_key = assert(env.name_key);
local guide_index = assert(dofile(
    ADDON .. '/modules/mission_quest_guide_index.lua'));
local progress_tracker = assert(dofile(
    ADDON .. '/modules/mission_progress_tracker.lua'));

local function clean(value)
    return (tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('%s+', ' ')
        :gsub('^%s+', ''):gsub('%s+$', ''));
end

local function lower(value)
    return clean(value):lower();
end

local function rows(value)
    return type(value) == 'table' and value or {};
end

local function value_name(value)
    if (type(value) == 'table') then
        return clean(value.name or value.target or value.item or value.key_item);
    end
    return clean(value);
end

local NON_POSITIONAL = {
    note = true,
    wait = true,
    select = true,
    choose = true,
};

local ACQUISITION = {
    obtain = true,
    trade = true,
    use = true,
    farm = true,
};

local INTERACTION = {
    talk = true,
    trade = true,
    deliver = true,
    examine = true,
    use = true,
};

local START_ZONE = {
    mission_san_doria = 230,
    mission_bastok = 234,
    mission_windurst = 238,
};

local lower_jeuno = 245;
for zone, label in pairs(zone_names) do
    if (name_key(label) == 'lower jeuno') then
        lower_jeuno = zone;
    end
end

local function discover_modules()
    local modules = {};
    local command = 'dir /b "' .. ADDON:gsub('/', '\\')
        .. '\\modules\\mission_quest_reconcile_mission_*.lua"';
    local pipe = io.popen(command);
    if (pipe == nil) then
        return nil, 'could not enumerate mission reconcile modules';
    end
    for line in pipe:lines() do
        modules[#modules + 1] = line:gsub('%.lua$', '');
    end
    pipe:close();
    table.sort(modules);
    if (#modules == 0) then
        return nil, 'no mission reconcile modules found';
    end
    return modules;
end

local function discover_quest_modules()
    local modules = {};
    local command = 'dir /b "' .. ADDON:gsub('/', '\\')
        .. '\\modules\\mission_quest_reconcile_quest_*.lua"';
    local pipe = io.popen(command);
    if (pipe == nil) then
        return nil, 'could not enumerate quest reconcile modules';
    end
    for line in pipe:lines() do
        modules[#modules + 1] = line:gsub('%.lua$', '');
    end
    pipe:close();
    table.sort(modules);
    if (#modules == 0) then
        return nil, 'no quest reconcile modules found';
    end
    return modules;
end

local function mission_keys(reconciled)
    local result = {};
    for native_key, entry in pairs(reconciled) do
        if (type(entry) == 'table' and type(entry.steps) == 'table') then
            result[#result + 1] = native_key;
        end
    end
    table.sort(result, function (left, right)
        local left_number = tonumber(tostring(left):match(':(%d+)$'));
        local right_number = tonumber(tostring(right):match(':(%d+)$'));
        if (left_number and right_number and left_number ~= right_number) then
            return left_number < right_number;
        end
        return tostring(left) < tostring(right);
    end);
    return result;
end

local function load_progression(module_name)
    local ok, loaded = pcall(
        dofile, ADDON .. '/modules/' .. module_name .. '.lua');
    if (not ok or type(loaded) ~= 'table') then
        return nil, nil,
            'could not load ' .. module_name .. ': ' .. tostring(loaded);
    end

    local entries = type(loaded.objectives) == 'table'
        and loaded.objectives or loaded;
    local by_step = {};

    for _, entry in pairs(entries) do
        for _, action in ipairs(
            type(entry) == 'table' and entry.progression_actions or {}) do
            local step_id = clean(action.step_id);
            if (step_id ~= '') then
                by_step[step_id] = by_step[step_id] or {};
                by_step[step_id][#by_step[step_id] + 1] = action;
            end
        end
    end

    return entries, by_step, nil;
end

local function instruction_by_nature(step, info_map)
    local has_place = false;
    for _, value in ipairs(rows(step.zones)) do
        if (clean(value) ~= '') then
            has_place = true;
        end
    end
    for _, value in ipairs(rows(step.entities)) do
        if (clean(value) ~= '') then
            has_place = true;
        end
    end
    if (not has_place) then
        return true;
    end

    local record = info_map[step.stable_step_id];
    if (record ~= nil
        and not record.kinds['npc']
        and not record.kinds['object']
        and not record.kinds['enemy']
        and not record.kinds['question-mark']
        and not record.kinds['area']
        and not record.kinds['zone']
        and (record.kinds['item'] or record.kinds['key-item'])) then
        return true;
    end

    return false;
end

local function pre_material(step, info_map)
    if (type(step) ~= 'table') then
        return false;
    end
    local action = name_key(step.action);
    return not NON_POSITIONAL[action]
        and name_key(step.comparison) ~= 'conflict'
        and step.optional_nonessential ~= true
        and step.route_recommendation ~= true
        and not instruction_by_nature(step, info_map);
end

-- The reference removes catalogue-absent acquisitions only after the resolver
-- proves that their names describe loot or an instruction rather than a place.
local function post_instruction_only(step, targets, info)
    local action = name_key(step.action);
    return #targets == 0
        and ((ACQUISITION[action]
                and info.reason == resolver.REASONS.ENTITY_ABSENT)
            or info.modifier_only == true);
end

local function route_result(targets, info)
    if (#targets > 0) then
        if (info.partial ~= nil) then
            return 'zone-only', true;
        end
        return 'full', true;
    end

    -- "Already there" satisfies the route leg, but it is not a fresh zone
    -- event and therefore cannot earn strict end-to-end completion credit.
    if (info.reason == resolver.REASONS.ALREADY_IN_ZONE) then
        return 'already-in-zone', true;
    end

    return 'refused', false, tostring(info.reason or 'unknown');
end

local function add_zone(set, value)
    value = tonumber(value) or 0;
    if (value > 0) then
        set[value] = true;
    end
end

local function add_zone_bucket(set, bucket)
    for key, value in pairs(rows(bucket)) do
        if (value == true) then
            add_zone(set, key);
        elseif (type(key) == 'number') then
            add_zone(set, value);
        elseif (tonumber(value)) then
            add_zone(set, value);
        end
    end
end

local function zone_ids_for_name(ctx, value)
    if (type(ctx.zone_ids_for_name) ~= 'function') then
        return {};
    end
    local ok, result = pcall(ctx.zone_ids_for_name, value);
    return ok and type(result) == 'table' and result or {};
end

local function points_for_zone_entity(ctx, zone, key)
    if (type(ctx.points_for_zone_entity) ~= 'function') then
        return {};
    end
    local ok, result = pcall(ctx.points_for_zone_entity, zone, key);
    return ok and type(result) == 'table' and result or {};
end

local function point_zone(point)
    return tonumber(type(point) == 'table'
        and (point.zone_id or point.zone) or nil) or 0;
end

local function point_name(point)
    return clean(type(point) == 'table'
        and (point.target_name or point.name) or '');
end

local function point_has_server_id(point)
    if (type(point) ~= 'table') then
        return false;
    end

    for key, value in pairs(rows(point.raw_spawn_ids)) do
        local candidate = value == true and tonumber(key) or tonumber(value);
        if ((candidate or 0) > 0) then
            return true;
        end
    end

    local destination = clean(point.destination_id);
    local raw_identity = clean(point.raw_identity);
    return (tonumber(destination:match(':(%d+)$')) or 0) > 0
        or (tonumber(raw_identity:match(':(%d+)$')) or 0) > 0;
end

local function target_names(action)
    local result, seen = {}, {};

    local function add(value)
        local key = lower(value_name(value));
        if (key ~= '' and not seen[key]) then
            seen[key] = true;
            result[#result + 1] = key;
        end
    end

    add(action.target);
    for _, value in ipairs(rows(action.npcs)) do
        add(value);
    end
    for _, value in ipairs(rows(action.objects)) do
        add(value);
    end
    return result;
end

local function named_values(values)
    local result = {};
    for _, value in ipairs(rows(values)) do
        local key = lower(value_name(value));
        if (key ~= '') then
            result[key] = true;
        end
    end
    return result;
end

-- Source derivation writes resolver-produced travel zones only when its older
-- explicit zone/entity pass found nothing. Reproduce that seam; merely seeing a
-- standalone resolver target is not proof that committed-zone can read it live.
local function resolver_zones_would_be_persisted(step, targets, ctx)
    if (#targets == 0) then
        return false;
    end

    local changing = type(resolver.is_zone_changing_action) == 'function'
        and resolver.is_zone_changing_action(clean(step.action))
        or lower(step.action) == 'travel';
    if (not changing) then
        return false;
    end

    local navigation_target = step.navigation_target;
    if (type(navigation_target) == 'table'
        and (type(navigation_target.point) == 'table'
            or type(navigation_target.reference) == 'table')) then
        return false;
    end

    local allowed_zones, entity_names = {}, {};
    for _, value in ipairs(rows(step.zones)) do
        add_zone_bucket(allowed_zones, zone_ids_for_name(ctx, value));
    end
    for _, value in ipairs(rows(step.entities)) do
        local zones = zone_ids_for_name(ctx, value);
        if (next(zones) ~= nil) then
            add_zone_bucket(allowed_zones, zones);
        else
            local key = name_key(value_name(value));
            if (key ~= '') then
                entity_names[key] = true;
            end
        end
    end

    if (next(allowed_zones) ~= nil and next(entity_names) ~= nil) then
        for zone in pairs(allowed_zones) do
            for key in pairs(entity_names) do
                for _, point in ipairs(
                    points_for_zone_entity(ctx, zone, key)) do
                    local allowed = type(ctx.kind_allowed) == 'function'
                        and ctx.kind_allowed(step.action, point.kind);
                    if (allowed) then
                        return false;
                    end
                end
            end
        end
    end

    return true;
end

local function identity_zones(action, route, ctx)
    local zones = {};
    add_zone(zones, action.destination_zone_id);

    for _, value in ipairs(rows(action.zones)) do
        add_zone_bucket(zones, zone_ids_for_name(ctx, value));
    end
    for _, point in ipairs(rows(route.targets)) do
        add_zone(zones, point_zone(point));
    end

    return zones;
end

local function action_identity(action, route, ctx)
    local catalogue = rows(action.catalogue);
    if (#catalogue > 0) then
        for _, point in ipairs(catalogue) do
            if (point_zone(point) > 0 and point_has_server_id(point)) then
                return true, 'action-catalogue';
            end
        end
        return false, 'populated-catalogue-has-no-exact-id';
    end

    local names = target_names(action);
    if (#names == 0) then
        return false, 'empty-target-name';
    end

    for zone in pairs(identity_zones(action, route, ctx)) do
        for _, key in ipairs(names) do
            for _, point in ipairs(points_for_zone_entity(ctx, zone, key)) do
                if (point_zone(point) == zone
                    and lower(point_name(point)) == key
                    and point_has_server_id(point)) then
                    return true, 'zone-name-index';
                end
            end
        end
    end

    return false, 'no-zone-name-server-id';
end

local function legacy_arrival_identity(action, route)
    if (route.shape ~= 'full') then
        return false;
    end

    for _, point in ipairs(rows(route.targets)) do
        local kind = lower(
            point.kind or point.target_kind or action.target_kind);
        if ((kind == 'npc' or kind == 'object' or kind == 'area')
            and point_zone(point) > 0
            and point_has_server_id(point)) then
            return true;
        end
    end

    return false;
end

local function fight_path(action)
    if (lower(action.relationship):find('defeat', 1, true) == nil) then
        return false, 'fight:not-defeat';
    end

    local names = named_values(action.enemies);
    local target = lower(action.target);
    if (target ~= '') then
        names[target] = true;
    end

    for _, point in ipairs(rows(action.catalogue)) do
        if (point_zone(point) > 0
            and names[lower(point_name(point))] == true) then
            return true, 'kill-credit';
        end
    end

    return false, 'fight:no-catalogue-zone-name';
end

local function obtain_path(action)
    if (lower(action.relationship) ~= 'obtain-item') then
        return false, 'obtain:not-obtain-item';
    end

    local items = named_values(action.items);
    local key_items = named_values(action.key_items);
    local target = lower(action.target);
    local kind = lower(action.target_kind);

    if (target ~= '' and kind == 'item') then
        items[target] = true;
    end
    if (target ~= '' and kind == 'key-item') then
        key_items[target] = true;
    end
    if (lower(action.result_relation):find('obtain', 1, true) ~= nil) then
        for item in pairs(named_values(action.result_items)) do
            items[item] = true;
        end
    end

    if (next(items) ~= nil and next(key_items) ~= nil) then
        return true, 'inventory-delta+key-item-delta';
    elseif (next(items) ~= nil) then
        return true, 'inventory-delta';
    elseif (next(key_items) ~= nil) then
        return true, 'key-item-delta';
    end

    return false, 'obtain:no-supported-item-field';
end

local function travel_zones(action, route, ctx)
    local zones, sources = {}, {};
    local destination = tonumber(action.destination_zone_id) or 0;

    if (destination > 0) then
        add_zone(zones, destination);
        sources.destination_zone_id = true;
    end

    for _, value in ipairs(rows(action.zones)) do
        local bucket = zone_ids_for_name(ctx, value);
        if (next(bucket) ~= nil) then
            add_zone_bucket(zones, bucket);
            sources.action_zones = true;
        end
    end

    local resolver_targets = false;
    for _, point in ipairs(rows(route.targets)) do
        if (point_zone(point) > 0) then
            resolver_targets = true;
        end
    end

    if (route.resolver_zone_persisted == true) then
        for _, point in ipairs(rows(route.targets)) do
            add_zone(zones, point_zone(point));
        end
        sources.resolver_recorded = true;
    elseif (resolver_targets) then
        sources.resolver_unproven = true;
    end

    return zones, sources;
end

local function committed_zone_path(action, route, ctx)
    local zones, sources = travel_zones(action, route, ctx);

    if (next(zones) ~= nil) then
        if (sources.destination_zone_id) then
            return true, 'committed-zone:destination-zone-id';
        elseif (sources.action_zones) then
            return true, 'committed-zone:guide-zones';
        end
        return true, 'committed-zone:resolver-recorded';
    end

    if (sources.resolver_unproven) then
        return false, 'travel:resolver-zone-not-persisted';
    end

    return false, 'travel:no-destination-zone';
end

local function classify_action(action, route, ctx)
    local verb = lower(action.action);
    local relationship = lower(action.relationship);
    local kind = lower(action.target_kind);

    if (INTERACTION[verb]) then
        local identity, why = action_identity(action, route, ctx);
        if (identity) then
            return 'direct', 'interaction:' .. why;
        end
        if (legacy_arrival_identity(action, route)) then
            return 'direct', 'interaction:arrival-armed-event';
        end
        return 'none', 'interaction:' .. why;
    elseif (verb == 'fight') then
        local ok, why = fight_path(action);
        return ok and 'direct' or 'none', why;
    elseif (verb == 'obtain') then
        local ok, why = obtain_path(action);
        return ok and 'direct' or 'none', why;
    end

    local transport = kind == 'transport'
        or relationship == 'use-transport';

    if (transport) then
        local identity, why = action_identity(action, route, ctx);
        if (identity and (tonumber(action.destination_zone_id) or 0) > 0) then
            return 'direct', 'transport-request+committed-zone';
        end

        -- target_kind=transport does not exclude the ordinary travel branch;
        -- relationship=use-transport does. Preserve that real dual path.
        if (verb == 'travel' and relationship ~= 'use-transport') then
            local ok, travel_why =
                committed_zone_path(action, route, ctx);
            if (ok) then
                return 'direct', travel_why;
            end
        end

        if (not identity) then
            return 'none', 'transport:' .. why;
        end
        return 'none', 'transport:no-destination-zone';
    elseif (verb == 'travel' and relationship ~= 'use-transport') then
        local ok, why = committed_zone_path(action, route, ctx);
        return ok and 'direct' or 'none', why;
    end

    return 'none', ('unsupported:%s:%s:%s'):format(
        verb ~= '' and verb or '(blank)',
        relationship ~= '' and relationship or '(blank)',
        kind ~= '' and kind or '(blank)');
end

local NATIVE_PROGRESS_CONTEXTS = {
    ["San d'Oria"] = true,
    Bastok = true,
    Windurst = true,
    ['Rise of the Zilart'] = true,
    ['Chains of Promathia'] = true,
    Assault = true,
    ['Treasures of Aht Urhgan'] = true,
    ['Wings of the Goddess'] = true,
    ['Seekers of Adoulin'] = true,
    ["Rhapsodies of Vana'diel"] = true,
    ['A Crystalline Prophecy'] = true,
    ["A Moogle Kupo d'Etat"] = true,
    ['A Shantotto Ascension'] = true,
};

-- A native transition is diagnostic fallback evidence, not proof that an
-- intermediate action completed. Credit it only where the packet exposes a
-- real progress stream and both ends map uniquely through the guide index.
local function native_replacement_possible(
    native_key, progression_entries)

    local record = guide_index[clean(native_key)];
    local context = clean(type(record) == 'table' and record.context or '');
    local native_id = tonumber(type(record) == 'table'
        and record.native_id or nil) or 0;
    local progress_id = tonumber(type(record) == 'table'
        and record.progress_id or nil);

    if (lower(type(record) == 'table' and record.kind or '') ~= 'mission'
        or NATIVE_PROGRESS_CONTEXTS[context] ~= true
        or native_id <= 0
        or progress_id == nil) then
        return false;
    end

    local mapped_key = progress_tracker.native_key_for_progress(
        guide_index, context, progress_id);
    if (mapped_key ~= native_key) then
        return false;
    end

    local successor_id, successor_key, successor_count = nil, '', 0;
    for candidate_key, candidate in pairs(guide_index) do
        if (lower(type(candidate) == 'table'
                and candidate.kind or '') == 'mission'
            and clean(candidate.context) == context) then
            local candidate_id = tonumber(candidate.native_id) or 0;
            if (candidate_id > native_id
                and (successor_id == nil
                    or candidate_id <= successor_id)) then
                if (successor_id == nil
                    or candidate_id < successor_id) then
                    successor_id = candidate_id;
                    successor_key = candidate_key;
                    successor_count = 1;
                else
                    successor_count = successor_count + 1;
                end
            end
        end
    end

    if (successor_id == nil or successor_count ~= 1
        or not progress_tracker.is_direct_successor(
            guide_index, context, native_id, successor_id)) then
        return false;
    end

    local successor = guide_index[successor_key];
    local next_key, next_id = progress_tracker.native_key_for_progress(
        guide_index, context, successor.progress_id);
    if (next_key ~= successor_key or next_id ~= successor_id) then
        return false;
    end

    local entry = progression_entries[successor_key];
    return type(entry) == 'table'
        and type(entry.progression_actions) == 'table';
end

local function classify_step(
    native_key,
    actions,
    route,
    ctx,
    progression_entries,
    path_counts,
    blockers,
    objective_kind)

    if (type(actions) ~= 'table' or #actions == 0) then
        blockers['step:no-progression-action'] =
            (blockers['step:no-progression-action'] or 0) + 1;
        return 'none';
    end

    local direct = true;
    for _, action in ipairs(actions) do
        local status, path = classify_action(action, route, ctx);
        if (status == 'direct') then
            path_counts[path] = (path_counts[path] or 0) + 1;
        else
            direct = false;
            blockers[path] = (blockers[path] or 0) + 1;
        end
    end

    if (direct) then
        return 'direct';
    end
    if (objective_kind == 'mission'
        and native_replacement_possible(native_key, progression_entries)) then
        return 'native-only';
    end
    return 'none';
end

local function cursor_gap_actions(entry, included_steps)
    local gaps = {};
    for _, action in ipairs(type(entry) == 'table'
        and rows(entry.progression_actions) or {}) do
        if (action.material ~= false
            and included_steps[clean(action.step_id)] ~= true) then
            gaps[#gaps + 1] = action;
        end
    end
    return gaps;
end

local function new_stats()
    return {
        missions = 0,
        no_material = 0,
        material_steps = 0,
        route_full = 0,
        route_zone = 0,
        route_already = 0,
        route_refused = 0,
        completion_direct = 0,
        completion_native = 0,
        completion_none = 0,
        route_all_missions = 0,
        completion_all_missions = 0,
        every_both = 0,
        full_endpoint = 0,
        zone_assisted = 0,
        chain_ready = 0,
        cursor_gap_missions = 0,
        cursor_gap_actions = 0,
    };
end

local STAT_FIELDS = {
    'missions',
    'no_material',
    'material_steps',
    'route_full',
    'route_zone',
    'route_already',
    'route_refused',
    'completion_direct',
    'completion_native',
    'completion_none',
    'route_all_missions',
    'completion_all_missions',
    'every_both',
    'full_endpoint',
    'zone_assisted',
    'chain_ready',
    'cursor_gap_missions',
    'cursor_gap_actions',
};

local function merge_stats(destination, source)
    for _, field in ipairs(STAT_FIELDS) do
        destination[field] = destination[field] + source[field];
    end
end

local function add_bucket(bucket, key, amount)
    key = clean(key);
    if (key == '') then
        key = '(blank)';
    end
    bucket[key] = (bucket[key] or 0) + (amount or 1);
end

local function print_stats(label, stats)
    print(('%-40s missions=%3d every-both=%3d full-endpoint=%3d'
        .. ' zone-assisted=%3d within-ready=%3d no-material=%3d'
        .. ' steps=%4d route(full=%4d zone=%3d satisfied=%3d refused=%3d)'
        .. ' completion(direct=%4d native-only=%3d none=%3d)'
        .. ' cursor-gaps=%3d/%4d'):format(
        label,
        stats.missions,
        stats.every_both,
        stats.full_endpoint,
        stats.zone_assisted,
        stats.chain_ready,
        stats.no_material,
        stats.material_steps,
        stats.route_full,
        stats.route_zone,
        stats.route_already,
        stats.route_refused,
        stats.completion_direct,
        stats.completion_native,
        stats.completion_none,
        stats.cursor_gap_missions,
        stats.cursor_gap_actions));
end

local function print_quest_stats(label, stats)
    print(('%-40s quests=%3d every-both=%3d full-endpoint=%3d'
        .. ' zone-assisted=%3d within-ready=%3d no-material=%3d'
        .. ' steps=%4d route(full=%4d zone=%3d satisfied=%3d refused=%3d)'
        .. ' completion(direct=%4d native-only=%3d none=%3d)'
        .. ' cursor-gaps=%3d/%4d'):format(
        label,
        stats.missions,
        stats.every_both,
        stats.full_endpoint,
        stats.zone_assisted,
        stats.chain_ready,
        stats.no_material,
        stats.material_steps,
        stats.route_full,
        stats.route_zone,
        stats.route_already,
        stats.route_refused,
        stats.completion_direct,
        stats.completion_native,
        stats.completion_none,
        stats.cursor_gap_missions,
        stats.cursor_gap_actions));
end

local function sorted_rows(bucket)
    local result = {};
    for key, count in pairs(bucket) do
        result[#result + 1] = {
            key = key,
            count = count,
        };
    end

    table.sort(result, function (left, right)
        if (left.count ~= right.count) then
            return left.count > right.count;
        end
        return left.key < right.key;
    end);

    return result;
end

local function print_top(label, bucket, limit)
    print(label .. ':');
    local values = sorted_rows(bucket);
    if (#values == 0) then
        print('  (none)');
        return;
    end

    for index = 1, math.min(limit or 20, #values) do
        print(('  %6d  %s'):format(
            values[index].count, values[index].key));
    end
end

local function module_nation(short)
    if (short == 'mission_san_doria') then
        return "San d'Oria";
    end
    if (short == 'mission_bastok') then
        return 'Bastok';
    end
    if (short == 'mission_windurst') then
        return 'Windurst';
    end
    return nil;
end

local function cursor_shape(action)
    return table.concat({
        lower(action.action) ~= ''
            and lower(action.action) or '(blank)',
        lower(action.relationship) ~= ''
            and lower(action.relationship) or '(blank)',
        lower(action.target_kind) ~= ''
            and lower(action.target_kind) or '(blank)',
    }, ':');
end

local function compute_quests()
    local modules, discover_error = discover_quest_modules();
    if (modules == nil) then
        error(discover_error);
    end

    local grand = new_stats();
    local route_blockers = {};
    local completion_blockers = {};
    local completion_paths = {};
    local cursor_shapes = {};
    local zero_action_objectives = 0;

    print(
        'QUEST COVERAGE (one accepted instance; Lower Jeuno route baseline):');

    for _, module_name in ipairs(modules) do
        local short =
            module_name:gsub('mission_quest_reconcile_', '');
        local ok, reconciled = pcall(
            dofile, ADDON .. '/modules/' .. module_name .. '.lua');
        if (not ok or type(reconciled) ~= 'table') then
            error('could not load ' .. module_name
                .. ': ' .. tostring(reconciled));
        end

        local progression_module =
            module_name:gsub('reconcile', 'progression');
        local progression_entries, actions_by_step, progression_error =
            load_progression(progression_module);
        if (progression_entries == nil) then
            error(progression_error);
        end

        local destination_map, destination_ok =
            progression_destinations(progression_module);
        if (not destination_ok) then
            error('could not load ' .. progression_module
                .. ' through the resolver harness');
        end

        local info_map = progression_info(progression_module);
        local destination_for_step = function (step_id)
            return destination_map[step_id] or 0;
        end;
        local module_stats = new_stats();

        for _, native_key in ipairs(mission_keys(reconciled)) do
            if (clean(native_key):match('^quest:[^:]+:%d+$') == nil) then
                error('unexpected quest native key: ' .. tostring(native_key));
            end

            local entry = reconciled[native_key];
            local steps = entry.steps;
            local progression_entry = progression_entries[native_key];
            local zone = lower_jeuno;
            local included_steps = {};
            local material = 0;
            local route_all = true;
            local route_full = true;
            local completion_all = true;

            module_stats.missions = module_stats.missions + 1;
            if (type(progression_entry) ~= 'table'
                or #rows(progression_entry.progression_actions) == 0) then
                zero_action_objectives = zero_action_objectives + 1;
            end

            for step_index, step in ipairs(steps) do
                if (pre_material(step, info_map)) then
                    local ctx =
                        make_ctx(zone, destination_for_step, nil);
                    local targets, info =
                        resolver.resolve_step(steps, step_index, ctx);
                    targets =
                        type(targets) == 'table' and targets or {};
                    info = type(info) == 'table' and info or {};

                    if (not post_instruction_only(step, targets, info)) then
                        local shape, routable, refusal =
                            route_result(targets, info);
                        local route = {
                            shape = shape,
                            targets = targets,
                            resolver_zone_persisted =
                                resolver_zones_would_be_persisted(
                                    step, targets, ctx),
                        };

                        local completion = classify_step(
                            native_key,
                            actions_by_step[
                                clean(step.stable_step_id)] or {},
                            route,
                            ctx,
                            progression_entries,
                            completion_paths,
                            completion_blockers,
                            'quest');

                        material = material + 1;
                        included_steps[
                            clean(step.stable_step_id)] = true;
                        module_stats.material_steps =
                            module_stats.material_steps + 1;

                        if (shape == 'full') then
                            module_stats.route_full =
                                module_stats.route_full + 1;
                        elseif (shape == 'zone-only') then
                            module_stats.route_zone =
                                module_stats.route_zone + 1;
                            route_full = false;
                        elseif (shape == 'already-in-zone') then
                            module_stats.route_already =
                                module_stats.route_already + 1;
                            route_full = false;
                        else
                            module_stats.route_refused =
                                module_stats.route_refused + 1;
                            route_all = false;
                            route_full = false;
                            add_bucket(route_blockers, refusal);
                        end

                        if (completion == 'direct') then
                            module_stats.completion_direct =
                                module_stats.completion_direct + 1;
                        elseif (completion == 'native-only') then
                            error(
                                'quest received impossible native-only credit');
                        else
                            module_stats.completion_none =
                                module_stats.completion_none + 1;
                            completion_all = false;
                        end

                        if (#targets > 0) then
                            zone = tonumber(targets[1].zone) or zone;
                        end
                    end
                end
            end

            local gaps =
                cursor_gap_actions(progression_entry, included_steps);
            if (#gaps > 0) then
                module_stats.cursor_gap_missions =
                    module_stats.cursor_gap_missions + 1;
                module_stats.cursor_gap_actions =
                    module_stats.cursor_gap_actions + #gaps;

                for _, action in ipairs(gaps) do
                    add_bucket(cursor_shapes, cursor_shape(action));
                end
            end

            if (material == 0) then
                module_stats.no_material =
                    module_stats.no_material + 1;
            else
                if (route_all) then
                    module_stats.route_all_missions =
                        module_stats.route_all_missions + 1;
                end
                if (completion_all) then
                    module_stats.completion_all_missions =
                        module_stats.completion_all_missions + 1;
                end

                if (route_all and completion_all) then
                    module_stats.every_both =
                        module_stats.every_both + 1;

                    if (route_full) then
                        module_stats.full_endpoint =
                            module_stats.full_endpoint + 1;
                    else
                        module_stats.zone_assisted =
                            module_stats.zone_assisted + 1;
                    end

                    if (route_full and #gaps == 0) then
                        module_stats.chain_ready =
                            module_stats.chain_ready + 1;
                    end
                end
            end
        end

        print_quest_stats(short, module_stats);
        merge_stats(grand, module_stats);
    end

    print_quest_stats('QUEST TOTAL', grand);
    print('');
    print(('QUEST GATES route-all=%d completion-all=%d'
        .. ' every-both=%d full-endpoint=%d zone-assisted=%d'
        .. ' conservative-within-ready=%d'):format(
        grand.route_all_missions,
        grand.completion_all_missions,
        grand.every_both,
        grand.full_endpoint,
        grand.zone_assisted,
        grand.chain_ready));
    print(('QUEST SCHEMA objectives-with-zero-actions=%d'):format(
        zero_action_objectives));

    print_top(
        'QUEST TOP ROUTE BLOCKERS (material steps)',
        route_blockers,
        20);
    print_top(
        'QUEST TOP COMPLETION BLOCKERS (progression actions)',
        completion_blockers,
        25);
    print_top(
        'QUEST DIRECT COMPLETION PATHS (progression actions)',
        completion_paths,
        20);
    print_top(
        'QUEST UNMEASURED CURSOR ACTION SHAPES',
        cursor_shapes,
        20);

    print('');
    print('Quest notes:');
    print('  Quest keys are validated as quest:<area>:<number>. Route facts');
    print('  come from reconciled steps; completion facts remain joined by');
    print('  progression step_id.');
    print('  every-both means one already-accepted quest instance has every');
    print('  material route leg usable and every attached action backed by');
    print('  direct evidence.');
    print('  It does not prove acceptance, repeat reset, cooldown, or');
    print('  successor rollover.');
    print('  Quests have no deployed per-run native transition producer, so');
    print('  native-only is always zero.');
    print('  Repeatable quests need a fresh-run epoch before prior cursor state');
    print('  can reset; this census awards no credit for that missing state.');
    print('  Lower Jeuno is a deterministic route baseline, not a claimed');
    print('  quest start.');
    print('  As with missions, route-arrival has no deployed producer and');
    print('  earns no credit.');

    return true;
end

local function compute()
    local modules, discover_error = discover_modules();
    if (modules == nil) then
        error(discover_error);
    end

    local grand = new_stats();
    local route_blockers = {};
    local completion_blockers = {};
    local completion_paths = {};
    local cursor_shapes = {};

    for _, module_name in ipairs(modules) do
        local short =
            module_name:gsub('mission_quest_reconcile_', '');
        local ok, reconciled = pcall(
            dofile, ADDON .. '/modules/' .. module_name .. '.lua');
        if (not ok or type(reconciled) ~= 'table') then
            error('could not load ' .. module_name
                .. ': ' .. tostring(reconciled));
        end

        local progression_module =
            module_name:gsub('reconcile', 'progression');
        local progression_entries, actions_by_step, progression_error =
            load_progression(progression_module);
        if (progression_entries == nil) then
            error(progression_error);
        end

        local destination_map, destination_ok =
            progression_destinations(progression_module);
        if (not destination_ok) then
            error('could not load ' .. progression_module
                .. ' through the resolver harness');
        end

        local info_map = progression_info(progression_module);
        local destination_for_step = function (step_id)
            return destination_map[step_id] or 0;
        end;
        local nation = module_nation(short);
        local module_stats = new_stats();

        for _, native_key in ipairs(mission_keys(reconciled)) do
            local entry = reconciled[native_key];
            local steps = entry.steps;
            local progression_entry = progression_entries[native_key];
            local zone = START_ZONE[short] or lower_jeuno;
            local included_steps = {};
            local material = 0;
            local route_all = true;
            local route_full = true;
            local completion_all = true;

            module_stats.missions = module_stats.missions + 1;

            for step_index, step in ipairs(steps) do
                if (pre_material(step, info_map)) then
                    local ctx =
                        make_ctx(zone, destination_for_step, nation);
                    local targets, info =
                        resolver.resolve_step(steps, step_index, ctx);
                    targets =
                        type(targets) == 'table' and targets or {};
                    info = type(info) == 'table' and info or {};

                    if (not post_instruction_only(step, targets, info)) then
                        local shape, routable, refusal =
                            route_result(targets, info);
                        local route = {
                            shape = shape,
                            targets = targets,
                            resolver_zone_persisted =
                                resolver_zones_would_be_persisted(
                                    step, targets, ctx),
                        };

                        local completion = classify_step(
                            native_key,
                            actions_by_step[
                                clean(step.stable_step_id)] or {},
                            route,
                            ctx,
                            progression_entries,
                            completion_paths,
                            completion_blockers,
                            'mission');

                        material = material + 1;
                        included_steps[
                            clean(step.stable_step_id)] = true;
                        module_stats.material_steps =
                            module_stats.material_steps + 1;

                        if (shape == 'full') then
                            module_stats.route_full =
                                module_stats.route_full + 1;
                        elseif (shape == 'zone-only') then
                            module_stats.route_zone =
                                module_stats.route_zone + 1;
                            route_full = false;
                        elseif (shape == 'already-in-zone') then
                            module_stats.route_already =
                                module_stats.route_already + 1;
                            route_full = false;
                        else
                            module_stats.route_refused =
                                module_stats.route_refused + 1;
                            route_all = false;
                            route_full = false;
                            add_bucket(route_blockers, refusal);
                        end

                        if (completion == 'direct') then
                            module_stats.completion_direct =
                                module_stats.completion_direct + 1;
                        elseif (completion == 'native-only') then
                            module_stats.completion_native =
                                module_stats.completion_native + 1;
                            completion_all = false;
                        else
                            module_stats.completion_none =
                                module_stats.completion_none + 1;
                            completion_all = false;
                        end

                        if (#targets > 0) then
                            zone = tonumber(targets[1].zone) or zone;
                        end
                    end
                end
            end

            local gaps =
                cursor_gap_actions(progression_entry, included_steps);
            if (#gaps > 0) then
                module_stats.cursor_gap_missions =
                    module_stats.cursor_gap_missions + 1;
                module_stats.cursor_gap_actions =
                    module_stats.cursor_gap_actions + #gaps;

                for _, action in ipairs(gaps) do
                    add_bucket(cursor_shapes, cursor_shape(action));
                end
            end

            if (material == 0) then
                module_stats.no_material =
                    module_stats.no_material + 1;
            else
                if (route_all) then
                    module_stats.route_all_missions =
                        module_stats.route_all_missions + 1;
                end
                if (completion_all) then
                    module_stats.completion_all_missions =
                        module_stats.completion_all_missions + 1;
                end

                if (route_all and completion_all) then
                    module_stats.every_both =
                        module_stats.every_both + 1;

                    if (route_full) then
                        module_stats.full_endpoint =
                            module_stats.full_endpoint + 1;
                    else
                        module_stats.zone_assisted =
                            module_stats.zone_assisted + 1;
                    end

                    if (route_full and #gaps == 0) then
                        module_stats.chain_ready =
                            module_stats.chain_ready + 1;
                    end
                end
            end
        end

        print_stats(short, module_stats);
        merge_stats(grand, module_stats);
    end

    print_stats('TOTAL', grand);
    print('');
    print(('MISSION GATES route-all=%d completion-all=%d'
        .. ' every-both=%d full-endpoint=%d zone-assisted=%d'
        .. ' conservative-within-ready=%d'):format(
        grand.route_all_missions,
        grand.completion_all_missions,
        grand.every_both,
        grand.full_endpoint,
        grand.zone_assisted,
        grand.chain_ready));

    print_top(
        'TOP ROUTE BLOCKERS (material steps)',
        route_blockers,
        20);
    print_top(
        'TOP COMPLETION BLOCKERS (progression actions)',
        completion_blockers,
        25);
    print_top(
        'DIRECT COMPLETION PATHS (progression actions)',
        completion_paths,
        20);
    print_top(
        'UNMEASURED CURSOR ACTION SHAPES',
        cursor_shapes,
        20);

    print('');
    print('Notes:');
    print('  every-both is the broad structural ceiling: at least one material');
    print('  step, every such route leg usable (full, zone-only, or already');
    print('  satisfied), and every attached action has a direct evidence path.');
    print('  full-endpoint rejects zone-only and already-in-zone steps. The latter');
    print('  satisfies movement but supplies no new committed-zone event.');
    print('  conservative-within-ready additionally rejects excluded or unmapped');
    print('  cursor actions; some acceptance actions may be proven-skippable live.');
    print('  native-only never counts as direct completion; it requires a uniquely');
    print('  mapped direct successor in a packet-backed mission progress stream.');
    print('  The reducer has no deployed route-arrival producer, so it earns no credit.');
    print('  Resolver travel zones count only when live source derivation persists');
    print('  them, not merely because this standalone resolver returned a target.');
    print('  No production_handles shortcut is added: these are resolve_step results.');
    print('  Native diagnostics cover the three nations plus Zilart, CoP, Assault,');
    print('  ToAU, Wings, Adoulin, RoV, ACP, MKD, and ASA. Campaign has no packet');
    print('  stream, and TVR tales is an expansion-start bit rather than mission');
    print('  progress.');
    print('  This is structural potential, not a live guarantee: event availability');
    print('  and inventory/key-item uniqueness still depend on runtime state.');

    print('');
    compute_quests();
    return true;
end

local ok, result = xpcall(compute, debug.traceback);
if (not ok) then
    io.stderr:write(
        'mission completion coverage could not compute: '
        .. tostring(result) .. '\n');
    os.exit(1);
end

os.exit(0);

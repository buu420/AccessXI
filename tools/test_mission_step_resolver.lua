-- Production-shaped regression for modules/mission_quest_step_resolver.lua.
--
-- Drives the resolver with the REAL reconciled guide steps, the REAL
-- destination catalogue (data/ffxi-nav-destinations.tsv) and the REAL
-- zone-line graph (data/ffxi-nav-zoneline-graph.tsv). No stand-ins for the
-- data, and the ROAD is no longer a stand-in either: this file used to BFS for
-- itself and silently ignore the fourth preferred_zones argument, so every
-- claim that had ever asserted guide-road behaviour through this harness was
-- asserting nothing at all (sol found it). It now loads the real
-- nav_zoneline_router and mirrors accessxi.nav_zoneline_path exactly. Only
-- edge rank is still reimplemented.
--
--   luajit tools/test_mission_step_resolver.lua            -- claims + census
--   luajit tools/test_mission_step_resolver.lua --census   -- census only
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;

local resolver = dofile(ADDON .. '/modules/mission_quest_step_resolver.lua');

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
-- Mirrors source_name_key in mission_quest_navigation.lua. The guide writes
-- "Door: Papal Chambers" and the catalogue "Door:Papal Chambers"; a harness
-- that normalises differently from production tests a seam that does not exist.
local function name_key(s)
    local key = trim(s):lower();
    key = key:gsub('%s*([:,])%s*', '%1');
    key = key:gsub('%s+', ' ');
    return key;
end
local function split_tsv(line)
    local parts = {};
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do parts[#parts + 1] = part; end
    return parts;
end

-- zone-line graph --------------------------------------------------------
local edges, out_edges, zone_names = {}, {}, {};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv', 'r'));
    local header = nil;
    for line in f:lines() do
        if (line ~= '' and not line:match('^#')) then
            local p = split_tsv(line);
            if (header == nil) then
                header = p;
            else
                local e = {};
                for i, key in ipairs(header) do e[key] = p[i]; end
                e.id = tonumber(e.zoneline_id); e.from_zone = tonumber(e.from_zone); e.to_zone = tonumber(e.to_zone);
                e.from_x, e.from_z, e.from_y = tonumber(e.from_x), tonumber(e.from_z), tonumber(e.from_y);
                e.to_x, e.to_z, e.to_y = tonumber(e.to_x), tonumber(e.to_z), tonumber(e.to_y);
                edges[#edges + 1] = e;
                out_edges[e.from_zone] = out_edges[e.from_zone] or {};
                table.insert(out_edges[e.from_zone], e);
                if (zone_names[e.from_zone] == nil and trim(e.from_name) ~= '') then zone_names[e.from_zone] = trim(e.from_name); end
                if (zone_names[e.to_zone] == nil and trim(e.to_name) ~= '') then zone_names[e.to_zone] = trim(e.to_name); end
            end
        end
    end
    f:close();
    -- Typed transports are required input, including for embedded coverage.
    -- A release staging race once silently removed every transport and made
    -- valid travel and NPC-reachability assertions fail later in the census.
    -- Availability is character state; this structural census assumes it.
    local transport_path = ADDON .. '/data/ffxi-nav-transport-edges.tsv';
    local tfile = assert(io.open(transport_path, 'r'),
        'required transport data unavailable: ' .. transport_path);
    local transport_count = 0;
    for line in tfile:lines() do
        if (line ~= '' and not line:match('^#') and line:match('^%d')) then
            local p = split_tsv(line);
            local e = { id = tonumber(p[1]), from_zone = tonumber(p[3]), from_name = trim(p[4]), from_x = tonumber(p[5]), from_z = tonumber(p[6]), from_y = tonumber(p[7]),
                to_zone = tonumber(p[9]), to_name = trim(p[10]), to_x = tonumber(p[11]), to_z = tonumber(p[12]), to_y = tonumber(p[13]),
                source = trim(p[17]), confidence = trim(p[18]), transport = { type = trim(p[2]), anchor_name = trim(p[8]), via_zone = tonumber(p[14]), availability = trim(p[15]), instruction = trim(p[16]) } };
            e.assumed = (trim(p[15]):find('^unlock:') ~= nil);
            if (e.from_zone and e.to_zone) then
                transport_count = transport_count + 1;
                edges[#edges + 1] = e;
                out_edges[e.from_zone] = out_edges[e.from_zone] or {};
                table.insert(out_edges[e.from_zone], e);
                if (zone_names[e.from_zone] == nil and e.from_name ~= '') then zone_names[e.from_zone] = e.from_name; end
                if (zone_names[e.to_zone] == nil and e.to_name ~= '') then zone_names[e.to_zone] = e.to_name; end
            end
        end
    end
    tfile:close();
    assert(transport_count > 0,
        'required transport data has no usable edges: ' .. transport_path);
end

-- THE ROAD IS THE REAL ONE. The router was extracted from the addon so the
-- choice of road could be tested offline; this harness then ignored it and
-- rolled its own plain BFS, which meant it could never see the fault the
-- router exists to prevent -- a level-14 player sent through King Ranperre's
-- Tomb while the guide named La Theine Plateau and Jugner Forest.
log_line = log_line or function () end;
accessxi.nav_zoneline_out_edges = function (zone)
    return out_edges[tonumber(zone) or 0] or {};
end
do
    local loaded, err = pcall(dofile, ADDON .. '/modules/nav_zoneline_router.lua');
    assert(loaded, 'nav_zoneline_router must load for the harness to be an oracle: ' .. tostring(err));
end

-- NOT A MIRROR ANY MORE. accessxi.nav_zoneline_path now lives in the router
-- module, so the harness calls the shipped one. Hand-mirroring it is what let
-- the missing fourth argument, and then the destination-in-the-road defect,
-- both hide behind green claims.
accessxi.nav_zoneline_edges = edges;
accessxi.nav_load_zoneline_graph = function () end
accessxi.nav_graph_zone_name = function (zone)
    return zone_names[tonumber(zone) or 0] or ('zone ' .. tostring(zone));
end
accessxi.nav_transport_edge_available = function () return true; end

local function zone_path(from_zone, to_zone, final_edge_id, preferred_zones)
    return accessxi.nav_zoneline_path(
        from_zone, to_zone, final_edge_id, preferred_zones);
end

local function edge_rank(e)
    local c = tostring(e.confidence or ''):lower();
    if (c:find('proven', 1, true)) then return 0 end
    if (c:find('verified', 1, true)) then return 2 end
    if (c:find('generated', 1, true)) then return 6 end
    if (c:find('untested', 1, true)) then return 8 end
    return 50;
end

-- catalogue ---------------------------------------------------------------
local points_by_zone_entity, points_by_entity, zone_ids_by_name, points_by_zone_base = {}, {}, {}, {};
local points_by_base = {};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-destinations.tsv', 'r'));
    for line in f:lines() do
        if (line ~= '' and not line:match('^#')) then
            local p = split_tsv(line);
            local zone = tonumber(p[1]);
            if (zone and zone > 0 and trim(p[2]) ~= '') then
                local point = { zone = zone, name = trim(p[2]), x = tonumber(p[3]), z = tonumber(p[4]), y = tonumber(p[5]),
                    kind = trim(p[6]), source = trim(p[7]), confidence = trim(p[8]), destination_id = trim(p[10] or ''), raw_identity = trim(p[11] or '') };
                local nk = name_key(point.name);
                local zk = zone .. '\t' .. nk;
                points_by_zone_entity[zk] = points_by_zone_entity[zk] or {};
                table.insert(points_by_zone_entity[zk], point);
                points_by_entity[nk] = points_by_entity[nk] or {};
                table.insert(points_by_entity[nk], point);
                local base = nk:match('^(.-)%s*#%d+$');
                if (base and base ~= '') then
                    local bk = zone .. '	' .. base;
                    points_by_zone_base[bk] = points_by_zone_base[bk] or {};
                    table.insert(points_by_zone_base[bk], point);
                    points_by_base[base] = points_by_base[base] or {};
                    table.insert(points_by_base[base], point);
                end
            end
        end
    end
    f:close();
    for zone, name in pairs(zone_names) do
        local k = name_key(name);
        zone_ids_by_name[k] = zone_ids_by_name[k] or {};
        zone_ids_by_name[k][zone] = true;
    end
end

local function kind_allowed(action, kind)
    action, kind = name_key(action), name_key(kind);
    if (action == 'fight') then return kind == 'enemy' or kind == 'nm' or kind == 'live-nm'; end
    -- Mirrors source_route_kind_allowed. You talk to doors in this game, and
    -- FFXI catalogues them as objects; trade stays npc-only so "trade to ???"
    -- cannot admit 1,267 object rows. A gate pins these two copies together.
    if (action == 'talk') then return kind == 'npc' or kind == 'object'; end
    if (action == 'trade') then return kind == 'npc'; end
    if (action == 'examine' or action == 'use') then return kind == 'npc' or kind == 'object' or kind == 'area'; end
    if (action == 'obtain') then return kind == 'enemy' or kind == 'nm' or kind == 'npc' or kind == 'object'; end
    return kind == 'npc' or kind == 'object' or kind == 'enemy' or kind == 'nm';
end

local NATION_GROUPS = { ["san d'oria"] = { 230, 231, 232, 233 }, bastok = { 234, 235, 236, 237 }, windurst = { 238, 239, 240, 241, 242 } };
-- The real role table and the real point index, so a role step is resolved here
-- exactly as the addon resolves it.
local role_members_table = dofile(ADDON .. '/modules/objective_role_members.lua');
local function harness_role_members(key)
    return role_members_table[trim(key):lower()];
end
local points_by_destination_id = nil;
local function harness_point_for_destination_id(destination_id)
    destination_id = trim(destination_id);
    if (destination_id == '') then return nil; end
    if (points_by_destination_id == nil) then
        points_by_destination_id = {};
        for _, bucket in pairs(points_by_entity) do
            for _, point in ipairs(bucket) do
                local key = trim(point.destination_id);
                if (key ~= '' and points_by_destination_id[key] == nil) then
                    points_by_destination_id[key] = point;
                end
            end
        end
    end
    return points_by_destination_id[destination_id];
end

-- Every progression module's declared items/key-items/result-items, keyed by
-- step id -- the join sol identified. Loaded once; the reconciled steps carry
-- none of this.
local declared_results = nil;
local function harness_declared_result_names(step_id)
    if (declared_results == nil) then
        declared_results = {};
        local pipe = io.popen('dir /b "' .. ADDON:gsub('/', '\\')
            .. '\\modules\\mission_quest_progression_mission_*.lua"');
        for name in (pipe and pipe:lines() or function () return nil; end) do
            local module = name:gsub('%.lua$', '');
            local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. module .. '.lua');
            if (ok and type(tbl) == 'table') then
                for _, entry in pairs(type(tbl.objectives) == 'table' and tbl.objectives or tbl) do
                    for _, action in ipairs(type(entry) == 'table' and entry.progression_actions or {}) do
                        local sid = trim(action.step_id);
                        for _, field in ipairs({ 'items', 'key_items', 'result_items' }) do
                            for _, item in ipairs(type(action[field]) == 'table' and action[field] or {}) do
                                local value = trim(type(item) == 'table'
                                    and (item.name or item.item or item.key_item) or item);
                                if (sid ~= '' and value ~= '') then
                                    declared_results[sid] = declared_results[sid] or {};
                                    declared_results[sid][value:lower()] = true;
                                end
                            end
                        end
                    end
                end
            end
        end
        if (pipe) then pipe:close(); end
    end
    return declared_results[trim(step_id)] or {};
end

-- Same shape as the production context: indexed once, not scanned per zone.
local in_edges = {};
for _, e in ipairs(edges) do
    in_edges[e.to_zone] = in_edges[e.to_zone] or {};
    table.insert(in_edges[e.to_zone], e);
end
local function incoming_edges(zone)
    return in_edges[tonumber(zone) or 0] or {};
end

-- The batch provider, built on the same shipped router the addon uses. The
-- census has always assumed transport availability is character state, so every
-- edge is available here -- which is also what makes the batch and the legacy
-- per-entrance search comparable at all.
accessxi.nav_transport_edge_available = function () return true; end
local entry_edge_workspace = nil;
local entry_edge_trees = {};
local provider_calls, tree_calls = 0, 0;
local function harness_entry_edge_candidates(from_zone, destination_zones, preferred_zones)
    -- A named road is scored per destination; one shared plain tree is not
    -- equivalent to it and must not answer for it.
    if (type(preferred_zones) == 'table' and next(preferred_zones) ~= nil) then
        return nil;
    end
    provider_calls = provider_calls + 1;
    if (entry_edge_workspace == nil) then
        entry_edge_workspace = accessxi.nav_zoneline_entry_edge_workspace(
            edges, accessxi.nav_transport_edge_available, edge_rank);
    end
    from_zone = tonumber(from_zone) or 0;
    local tree = entry_edge_trees[from_zone];
    if (tree == nil) then
        tree_calls = tree_calls + 1;
        tree = accessxi.nav_zoneline_entry_edge_shortest_tree(entry_edge_workspace, from_zone);
        entry_edge_trees[from_zone] = tree;
    end
    return accessxi.nav_zoneline_entry_edge_candidates(
        entry_edge_workspace, tree, destination_zones, incoming_edges);
end

-- Read by the claims that pin how much searching the batch actually saves.
-- The production code carries no counter; the harness wraps instead.
local function entry_edge_counters()
    return provider_calls, tree_calls;
end
local function reset_entry_edge_counters()
    provider_calls, tree_calls = 0, 0;
    -- The tree is memoised for the whole run; a claim that counts trees must
    -- start from an empty cache or it counts the parity run's tree instead.
    entry_edge_trees = {};
end

local primary_actions_by_step = nil;

local function ensure_primary_actions()
    if (primary_actions_by_step ~= nil) then
        return;
    end

    primary_actions_by_step = {};

    local pipe = io.popen(
        'dir /b "'
            .. ADDON:gsub('/', '\\')
            .. '\\modules\\mission_quest_progression_*.lua"');

    for name in (pipe and pipe:lines()
            or function() return nil; end) do
        local module = name:gsub('%.lua$', '');
        local ok, tbl =
            pcall(
                dofile,
                ADDON .. '/modules/' .. module .. '.lua');

        if (ok and type(tbl) == 'table') then
            local objectives =
                type(tbl.objectives) == 'table'
                    and tbl.objectives or tbl;

            for _, entry in pairs(objectives) do
                for _, action in ipairs(
                        type(entry) == 'table'
                            and entry.progression_actions
                            or {}) do
                    local step_id =
                        trim(action.step_id);

                    if (step_id ~= '') then
                        primary_actions_by_step[
                            step_id] =
                            primary_actions_by_step[
                                step_id] or {};
                        table.insert(
                            primary_actions_by_step[
                                step_id],
                            action);
                    end
                end
            end
        end
    end

    if (pipe) then pipe:close(); end
end

local function harness_primary_actions_for_step(
    step_id)

    ensure_primary_actions();

    local source =
        primary_actions_by_step[
            trim(step_id)] or {};
    local result = {};

    for i = 1, #source do
        result[i] = source[i];
    end

    return result;
end

local reconciled_step_ids = nil;

local function ensure_reconciled_step_ids()
    if (reconciled_step_ids ~= nil) then
        return;
    end

    reconciled_step_ids = {};

    local pipe = io.popen(
        'dir /b "'
            .. ADDON:gsub('/', '\\')
            .. '\\modules\\mission_quest_reconcile_*.lua"');

    for name in (pipe and pipe:lines()
            or function() return nil; end) do
        local module = name:gsub('%.lua$', '');
        local ok, tbl =
            pcall(
                dofile,
                ADDON .. '/modules/' .. module .. '.lua');

        if (ok and type(tbl) == 'table') then
            local objectives =
                type(tbl.objectives) == 'table'
                    and tbl.objectives or tbl;

            for _, entry in pairs(objectives) do
                for _, step in ipairs(
                        type(entry) == 'table'
                            and entry.steps or {}) do
                    local step_id =
                        trim(step.stable_step_id);

                    if (step_id ~= '') then
                        reconciled_step_ids[
                            step_id] = true;
                    end
                end
            end
        end
    end

    if (pipe) then pipe:close(); end
end

local function harness_step_exists(step_id)
    ensure_reconciled_step_ids();

    return reconciled_step_ids[
        trim(step_id)] == true;
end

-- EACH PAGE'S OWN READING, from the REAL guide module. The reconciled step
-- merges both wikis' entities; resolving that union can name a place neither
-- page stated. Loading the shipped GuideState rather than reimplementing its
-- lookup keeps this a test of the seam instead of a second opinion about it.
local guide_state = nil;
do
    local ok_index, index = pcall(dofile, ADDON .. '/modules/mission_quest_guide_index.lua');
    local ok_module, module = pcall(dofile, ADDON .. '/modules/mission_quest_guides.lua');
    if (ok_module and type(module) == 'table' and type(module.new) == 'function') then
        -- Constructed the way accessxi_reader.lua constructs it: the real
        -- index, and a loader that dofiles the shipped module by name.
        guide_state = module.new({
            index = ok_index and index or {},
            module_loader = function (name)
                local loaded, data = pcall(dofile, ADDON .. '/modules/' .. name .. '.lua');
                return (loaded and type(data) == 'table') and data or nil;
            end,
            identity_provider = function () return 'harness'; end,
            logger = function () end,
        });
    end
end

local function harness_source_readings(native_key, step_id)
    if (type(guide_state) ~= 'table'
        or type(guide_state.source_step_readings) ~= 'function') then
        return {};
    end
    local ok, value = pcall(guide_state.source_step_readings,
        guide_state, native_key, step_id);
    return (ok and type(value) == 'table') and value or {};
end

local harness_ingress, harness_ingress_index;
local function make_ctx(player_zone, destination_zone_for_step, nation, native_key)
    -- Which objective the ctx is currently reading. A census walks many
    -- objectives through one ctx, so this is a handle it can retarget rather
    -- than a value captured once.
    local objective = { key = native_key or '' };
    return {
        destination_ingress = function(point)
            if not harness_ingress then
                harness_ingress = dofile(ADDON .. '/modules/nav_destination_ingress.lua');
                harness_ingress_index = harness_ingress.load(ADDON .. '/data/ffxi-nav-destination-ingress.tsv');
            end
            return harness_ingress.lookup(harness_ingress_index, point);
        end,
        select_destination_ingress = function(...)
            return harness_ingress.select(...);
        end,
        objective = objective,
        source_readings = function (step_id)
            return harness_source_readings(objective.key, step_id);
        end,
        default_zone_group = nation and NATION_GROUPS[name_key(nation)] or nil,
        player_zone = player_zone,
        name_key = name_key,
        zone_ids_for_name = function (v) return zone_ids_by_name[name_key(v)]; end,
        points_for_zone_entity = function (zone, key) return points_by_zone_entity[zone .. '\t' .. key]; end,
        points_for_entity = function (key) return points_by_entity[key]; end,
        points_for_zone_base = function (zone, key) return points_by_zone_base[zone .. '	' .. key]; end,
        points_for_entity_base = function (key) return points_by_base[key]; end,
        entry_edge_candidates = harness_entry_edge_candidates,
        -- THE HARNESS COULD NOT EXPRESS A ROAD. Production supplies this and
        -- the harness did not, so M.named_via_zones returned nil here for
        -- every step ever tested -- the same silent gap as the missing fourth
        -- argument of zone_path, one layer up. A single unambiguous zone name
        -- only; several ids is not a road.
        zone_id_for_name = function (value)
            local ids = zone_ids_by_name[name_key(value)];
            if (type(ids) ~= 'table') then return 0; end
            local found, count = 0, 0;
            for zone in pairs(ids) do found = zone; count = count + 1; end
            return count == 1 and found or 0;
        end,
        effective_kind = function (p) return p.kind; end,
        kind_allowed = kind_allowed,
        declared_result_names = harness_declared_result_names,
        primary_actions_for_step = harness_primary_actions_for_step,
        role_members = harness_role_members,
        point_for_destination_id = harness_point_for_destination_id,
        zone_name = function (zone) return zone_names[tonumber(zone) or 0] or ''; end,
        incoming_edges = incoming_edges,
        zone_path = zone_path,
        edge_rank = edge_rank,
        destination_zone_for_step = destination_zone_for_step or function () return 0; end,
        nation_zones = function (v)
            local tbl = { ["san d'oria"] = { 230, 231, 232 }, bastok = { 234, 235, 236 }, windurst = { 238, 239, 240, 241 } };
            return tbl[name_key(v)];
        end,
        -- Mirrors accessxi.nav_nation_of_zone. A harness that does not supply
        -- this tests a context production does have.
        step_target_binding = function (step_id)
            local path = ADDON .. '/data/ffxi-objective-step-targets.tsv';
            local h = io.open(path, 'r');
            if (h == nil) then return nil; end
            local found = nil;
            for line in h:lines() do
                if (line ~= '' and line:sub(1,1) ~= '#') then
                    local f = {};
                    for field in (line .. '	'):gmatch('([^	]*)	') do f[#f+1] = field; end
                    if (trim(f[1] or '') == trim(step_id) and tonumber(f[2]) and trim(f[3] or '') ~= '') then
                        found = { zone = tonumber(f[2]), target = trim(f[3]), destination_id = trim(f[6] or '') };
                    end
                end
            end
            h:close();
            return found;
        end,
        nation_of_zone = function (zone)
            local tbl = { ["san d'oria"] = { 230, 231, 232 }, bastok = { 234, 235, 236 }, windurst = { 238, 239, 240, 241 } };
            for nation, ids in pairs(tbl) do
                for _, id in ipairs(ids) do
                    if (id == (tonumber(zone) or 0)) then return nation; end
                end
            end
            return '';
        end,
    };
end

-- progression destination zones (travel actions carry destination_zone_id)
local function progression_destinations(module_name)
    local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. module_name .. '.lua');
    local map = {};
    if (ok and type(tbl) == 'table') then
        for native_key, entry in pairs(type(tbl.objectives) == 'table' and tbl.objectives or tbl) do
            for _, action in ipairs(type(entry) == 'table' and entry.progression_actions or {}) do
                local zone = tonumber(action.destination_zone_id) or 0;
                if (zone > 0 and name_key(action.action) == 'travel' and map[action.step_id] == nil) then
                    map[action.step_id] = zone;
                end
            end
        end
    end
    return map, ok;
end

-- Per-step progression facts the walkthrough needs: the first action's
-- target kind and whether any action of the step ships a catalogue.
local function progression_info(module_name)
    local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. module_name .. '.lua');
    local map = {};
    if (ok and type(tbl) == 'table') then
        for native_key, entry in pairs(type(tbl.objectives) == 'table' and tbl.objectives or tbl) do
            for _, action in ipairs(type(entry) == 'table' and entry.progression_actions or {}) do
                local rec = map[action.step_id] or { kinds = {}, catalogue = false, actions = 0 };
                rec.actions = rec.actions + 1;
                rec.kinds[name_key(action.target_kind)] = true;
                if (type(action.catalogue) == 'table' and #action.catalogue > 0) then rec.catalogue = true; end
                map[action.step_id] = rec;
            end
        end
    end
    return map;
end

-- Shared with tools/test_mission_walkthrough.lua: hand back the production
-- shaped context instead of running the claims.
if (WALKTHROUGH_EMBED) then
    return { resolver = resolver, make_ctx = make_ctx, zone_names = zone_names, zone_path = zone_path,
        progression_destinations = progression_destinations, progression_info = progression_info, name_key = name_key,
        edges = edges, edge_rank = edge_rank, incoming_edges = incoming_edges,
        entry_edge_counters = entry_edge_counters,
        reset_entry_edge_counters = reset_entry_edge_counters };
end

-- claims ------------------------------------------------------------------
local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1; print('  ok  ' .. text);
    else failures = failures + 1; print('  FAIL ' .. text); end
end

local function real_step(
    module_name,
    native_key,
    step_id)

    local tbl =
        dofile(ADDON .. '/modules/'
            .. module_name .. '.lua');
    local entry = assert(tbl[native_key], native_key);

    for _, step in ipairs(entry.steps or {}) do
        if (step.stable_step_id == step_id) then
            return step;
        end
    end
    error('missing real step ' .. step_id);
end

local function has_unreachable_zone(
    info,
    zone,
    count)

    for _, entry in ipairs(
        type(info.unreachable_choices) == 'table'
            and info.unreachable_choices or {}) do
        if (entry.zone == zone
            and (count == nil
                or entry.count == count)) then
            return true;
        end
    end
    return false;
end

local run_claims = (arg[1] ~= '--census');
if (run_claims) then
    -- AN ENTITY IS NOT THE ACTION'S TARGET.
    --
    -- Below the Arks, step-009. The reconciled step's entities are the whole
    -- wiki paragraph flattened:
    --
    --   zones    = { Tahrongi Canyon, Konschtat Highlands, La Theine Plateau }
    --   entities = { crag, Tahrongi Canyon, Konschtat Highlands,
    --                La Theine Plateau, Shattered Telepoint,
    --                Hall of Transference, Large Apparatus }
    --
    -- Every one of those nouns was looked up in every zone, so the browse
    -- offered SIX "Large Apparatus" rows in the Hall of Transference -- a
    -- chamber you can only ARRIVE in, by examining the very telepoint this step
    -- is about. Live 2026-08-28 the player heard ten rows for this one step and
    -- asked to be shown "just the places you need to visit".
    --
    -- "Is it a zone?" cannot separate them: LandSandBoat says Hall of
    -- Transference and Leujaoam Sanctum are both real zones, and bounding
    -- entity-derived zones to the step's declared ones would break the Assault
    -- briefings that name their objective zone only in prose. The action's own
    -- compact target does separate them -- examine-object -> Shattered
    -- Telepoint, while Hall of Transference belongs to this step's OTHER action
    -- (enter-through) and Large Apparatus to no action at all (sol).
    --
    -- Player stands in Upper Jeuno, not in a crag, so a pass here cannot be an
    -- artefact of already standing on one of the answers.
    print('Below the Arks (mission:Chains of Promathia:3), player in Upper Jeuno (244):');
    do
        local cop = dofile(ADDON .. '/modules/mission_quest_reconcile_mission_chains_of_promathia.lua');
        local arks = cop["mission:Chains of Promathia:3"];
        claim(arks ~= nil and type(arks.steps) == 'table',
            'reconciled steps exist for Below the Arks');
        if (arks ~= nil and type(arks.steps) == 'table') then
            local cop_by_id = {};
            for i, s in ipairs(arks.steps) do cop_by_id[s.stable_step_id] = i; end
            local index = cop_by_id["mission:Chains of Promathia:3:step-009"];
            claim(index ~= nil, 'step-009 is present');
            if (index ~= nil) then
                local cop_dest = progression_destinations(
                    'mission_quest_progression_mission_chains_of_promathia');
                local cop_ctx = make_ctx(244,
                    function (step_id) return cop_dest[step_id] or 0; end,
                    nil, "mission:Chains of Promathia:3");
                local cop_targets = resolver.resolve_step(arks.steps, index, cop_ctx);
                cop_targets = type(cop_targets) == 'table' and cop_targets or {};

                -- Not vacuous: if the step resolved to nothing this fails loudly
                -- rather than passing because there is nothing to be wrong.
                claim(#cop_targets > 0,
                    'step-009 still resolves to somewhere, got ' .. #cop_targets);

                local telepoints, hall, other, zones_hit = 0, 0, {}, {};
                for _, target in ipairs(cop_targets) do
                    local zone = tonumber(target.zone) or 0;
                    local nm = name_key(target.name or '');
                    zones_hit[zone] = true;
                    if (nm == 'shattered telepoint') then telepoints = telepoints + 1;
                    elseif (zone == 14 or nm == 'large apparatus') then hall = hall + 1;
                    else other[#other + 1] = tostring(target.name) .. '@' .. zone; end
                end

                claim(hall == 0,
                    'no Hall of Transference or Large Apparatus row survives, got ' .. hall);
                claim(telepoints > 0,
                    'the Shattered Telepoint is what the step points at, got ' .. telepoints);
                claim(#other == 0,
                    'and nothing incidental came with it, got ' .. table.concat(other, ', '));
                claim(zones_hit[102] and zones_hit[108] and zones_hit[117],
                    'all three crags are offered -- they are a real choice, not a narrowing');
                claim(not zones_hit[14],
                    'and zone 14 is not among them');
            end
        end
    end

    print('The Davoi Report (mission:San d\'Oria:5), player in Southern San d\'Oria (230):');
    local reconcile = dofile(ADDON .. '/modules/mission_quest_reconcile_mission_san_doria.lua');
    local davoi = reconcile["mission:San d'Oria:5"];
    claim(davoi ~= nil and type(davoi.steps) == 'table', 'reconciled steps exist for the mission');
    local steps = davoi.steps;
    local by_id = {};
    for i, s in ipairs(steps) do by_id[s.stable_step_id] = i; end
    local dest_map = progression_destinations('mission_quest_progression_mission_san_doria');
    local ctx = make_ctx(230, function (step_id) return dest_map[step_id] or 0; end);

    -- claim 1: "Make your way to Davoi" is a zone-travel target into 149 via the one edge Jugner -> Davoi
    local i9 = by_id["mission:San d'Oria:5:step-009"];
    local targets, info = resolver.resolve_step(steps, i9, ctx);
    claim(#targets == 1 and info.kind == 'zone-travel', 'step-009 (travel, zones only) resolves as zone-travel');
    claim(targets[1] and targets[1].zone == 149, 'step-009 target is inside Davoi (149)');
    claim(targets[1] and targets[1].canonical_from_zone == 104, 'step-009 binds the Jugner Forest (104) -> Davoi edge');
    claim(targets[1] and zone_path(230, 149, targets[1].canonical_edge_id):len() > 0, 'the bound edge is reachable from Southern San d\'Oria by the directed chain');
    claim(targets[1] and targets[1].destination_id ~= '' and targets[1].raw_identity ~= '', 'zone-travel target carries a destination id and raw identity');

    -- claim 2: "Talk to Zantaviat" with its explicit zone
    local i11 = by_id["mission:San d'Oria:5:step-011"];
    targets, info = resolver.resolve_step(steps, i11, ctx);
    claim(#targets >= 1 and info.kind == 'explicit' and targets[1].zone == 149 and name_key(targets[1].name) == 'zantaviat', 'step-011 (talk Zantaviat, zone Davoi) resolves to the catalogue Zantaviat in 149');

    -- "Return to a Gate Guard": the guide is offering a choice, not naming one
    -- person. Live 2026-08-22 this was refused -- "Gate Guard is not in the
    -- Davoi catalogue" -- while the acceptance step a few steps earlier had
    -- routed to Ambrotien, Endracion and Grilau, and the guide itself lists all
    -- three. It is the second-to-last step of the mission, so refusing it ends
    -- the run one step short of finishing.
    local i15 = by_id["mission:San d'Oria:5:step-015"];
    targets, info = resolver.resolve_step(steps, i15, ctx);
    claim(i15 ~= nil, 'the mission has a "Return to a Gate Guard" step');
    claim(#targets > 1 and info.reason == nil,
        ('step-015 offers every gate guard the guide named rather than refusing (%d, %s)'):format(
            #targets, tostring(info.reason or info.kind)));
    do
        local names = {};
        for _, point in ipairs(targets) do names[name_key(point.name)] = true; end
        claim(names['ambrotien'] and names['endracion'] and names['grilau'],
            'and they are the three the guide lists: Ambrotien, Endracion, Grilau');
        claim(info.kind == 'role-choice',
            'resolved as the ROLE the guide named, and marked a choice so nothing is picked for the player');
    end
    -- A definite name must still bind to one instance, or refuse.
    claim(resolver.indefinite_target({ primary_instruction = 'Return to Halver.' },
        { halver = 'Halver' }) == false,
        '"Return to Halver" is one person and is not treated as a choice');
    claim(resolver.indefinite_target({ primary_instruction = 'Return to a Gate Guard.' },
        { ['gate guard'] = 'Gate Guard' }) == true,
        'while "a Gate Guard" is the guide saying any of them will do');
    claim(resolver.indefinite_target({ primary_instruction = 'Speak to the Bastokan Gate Guard.' },
        { ['gate guard'] = 'Gate Guard' }) == false,
        'and a name merely ENDING in the target is not an indefinite article');

    -- claim 3: the same step with its zone stripped inherits Davoi from step-009
    local stripped = {};
    for i, s in ipairs(steps) do
        local c = {}; for k, v in pairs(s) do c[k] = v; end
        if (i == i11) then c.zones = {}; c.entities = { 'Zantaviat' }; end
        stripped[i] = c;
    end
    targets, info = resolver.resolve_step(stripped, i11, ctx);
    claim(#targets >= 1 and info.kind == 'inherited' and info.inherited_zone == 149, 'step-011 with no zone inherits 149 from the preceding travel step');

    -- WHAT YOU COME AWAY WITH IS NOT WHERE YOU GO.
    --
    -- Extraction lifts the reward into `entities` and loses the target. Live
    -- corpus: entities = { "Drops of Amnio" } against
    -- "Check the Fountain of Kings again ... for some key item Drops of Amnio."
    -- The fountain is the destination and is nowhere in the structured fields.
    claim(resolver.is_result_item(
        { bg_instruction = 'Check the Fountain of Kings again for some key item Drops of Amnio.' },
        'Drops of Amnio') == true,
        'a key item the guide names is a reward, not a destination');
    claim(resolver.is_result_item(
        { bg_instruction = 'Check the Dreamrose to spawn Sabotender Enamorado.' },
        'Sabotender Enamorado') == true,
        'and so is something the guide says you SPAWN -- the Dreamrose is the place');
    claim(resolver.is_result_item(
        { bg_instruction = 'Upon defeating Magma, it will drop 6 Rare/Ex Frag Rocks.' },
        'Frag Rock') == false,
        'but only when the guide names it exactly -- "Frag Rocks" plural is not matched, and we do not stem');
    claim(resolver.is_result_item(
        { bg_instruction = "Talk to Ambrotien in Southern San d'Oria." },
        'Ambrotien') == false,
        'a real NPC in an ordinary sentence is never mistaken for a reward');
    claim(resolver.is_result_item(
        { bg_instruction = 'Speak to the Bastokan Gate Guard.' },
        'Guard') == false,
        'and a name merely ENDING in a labelled word is not a reward');
    claim(resolver.is_result_item(
        { items = { 'Silver Bell' }, bg_instruction = 'Trade it.' },
        'Silver Bell') == true,
        'a step that declares the item outright needs no reading at all');
    claim(resolver.is_result_item({ bg_instruction = '' }, 'Anything') == false,
        'and with no guide text there is nothing to conclude');
    -- Stripping the reward lets the real target through.
    do
        local both = { { stable_step_id = 'r:1', order = 1, action = 'examine',
            entities = { 'Ambrotien', 'Drops of Amnio' }, zones = { "Southern San d'Oria" },
            grid_coordinates = {},
            bg_instruction = "Examine Ambrotien in Southern San d'Oria for the key item Drops of Amnio." } };
        local tg, nf = resolver.resolve_step(both, 1, make_ctx(230));
        claim(#tg >= 1 and name_key(tg[1].name) == 'ambrotien',
            'a step naming BOTH resolves to the target, not the reward (' .. tostring(nf.reason or nf.kind) .. ')');
    end

    -- A reward that is ALSO a real place stays a place. Live corpus: "Be sure
    -- to collect the Survival Guide in Beaucedine Glacier (S)" -- declared a
    -- reward, and somewhere the player genuinely walks to.
    do
        local both = { { stable_step_id = 'sg:1', order = 1, action = 'obtain',
            entities = { 'Survival Guide' }, zones = { "Northern San d'Oria" }, grid_coordinates = {},
            bg_instruction = 'Be sure to collect the key item Survival Guide.' } };
        local tg = resolver.resolve_step(both, 1, make_ctx(231));
        claim(#tg >= 1, 'a reward that is also a catalogue row is still routed to');
    end

    -- claim 4: no preceding zone context -> named refusal
    local lone = { { stable_step_id = 'x:1', order = 1, action = 'talk', entities = { 'Zantaviat' }, zones = {}, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(lone, 1, make_ctx(230));
    -- Zantaviat is unique in the catalogue, so the unique fallback should carry it
    claim(#targets >= 1 and info.kind == 'catalogue-unique', 'a unique entity with no zone context routes through the unique-catalogue fallback');
    local dup = { { stable_step_id = 'x:1', order = 1, action = 'talk', entities = { 'Glowing Whatsit' }, zones = {}, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(dup, 1, make_ctx(230));
    claim(#targets == 0 and (info.reason == resolver.REASONS.ENTITY_DUPLICATED or info.reason == resolver.REASONS.ZONE_CONTEXT_MISSING or info.reason == resolver.REASONS.ENTITY_ABSENT), 'a genuinely unknown entity with no zone context is refused with a named reason (' .. tostring(info.reason) .. ')');
    -- "Gate Guard" used to be this claim's example of an unplaceable entity.
    -- It is a ROLE, and the guide says who fills it, so it now resolves --
    -- with no zone context at all, because the role carries its own.
    local role = { { stable_step_id = 'x:1', order = 1, action = 'talk', entities = { 'Gate Guard' }, zones = {}, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(role, 1, make_ctx(230));
    claim(#targets == 3 and info.kind == 'role-choice',
        'a role resolves to its members without any zone context (' .. tostring(info.kind) .. ')');
    claim(trim(tostring(info.review_basis or '')) ~= '',
        'and carries the review basis that admitted those members');
    claim(#targets == 3
        and info.kind == 'role-choice'
        and info.reason == nil
        and info.ambiguity == nil,
        'Gate Guard remains a semantic role choice');
    local missing = { { stable_step_id = 'x:1', order = 1, action = 'talk', entities = { 'Nobody Of That Name' }, zones = {}, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(missing, 1, make_ctx(230));
    claim(#targets == 0 and info.reason == resolver.REASONS.ENTITY_ABSENT, 'an entity absent from the catalogue is refused as entity-absent');

    -- claim 5: ambiguous preceding zone-changing step blocks inheritance
    local amb = {
        { stable_step_id = 'a:1', order = 1, action = 'travel', entities = { 'Jugner Forest', 'Davoi' }, zones = { 'Jugner Forest', 'Davoi' }, grid_coordinates = {} },
        { stable_step_id = 'a:2', order = 2, action = 'talk', entities = { 'Zantaviat' }, zones = {}, grid_coordinates = {} },
    };
    local amb_ctx = make_ctx(230);
    local saved = amb_ctx.zone_ids_for_name;
    amb_ctx.zone_ids_for_name = function (v) if (name_key(v) == 'jugner forest') then return { [104] = true, [82] = true }; end return saved(v); end
    targets, info = resolver.resolve_step(amb, 2, amb_ctx);
    claim(info.kind ~= 'inherited', 'inheritance never crosses an ambiguous zone-changing step (kind=' .. tostring(info.kind) .. ')');

    -- claim 6: travel to an unreachable zone -> no-zone-chain; already there -> already-in-zone
    local far = { { stable_step_id = 'f:1', order = 1, action = 'travel', entities = { 'Davoi' }, zones = { 'Davoi' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(far, 1, make_ctx(9999));
    claim(#targets == 0 and info.reason == resolver.REASONS.NO_ZONE_CHAIN, 'travel with no directed chain from the player zone is refused as no-zone-chain');
    targets, info = resolver.resolve_step(far, 1, make_ctx(149));
    claim(#targets == 0 and info.reason == resolver.REASONS.ALREADY_IN_ZONE, 'travel into the zone the player already stands in is already-in-zone');

    -- claim 7: several reachable entrances + an exit square -> exit-square-unresolved; without the square -> best edge
    local multi_zone = nil;
    for zone in pairs(zone_names) do
        local n = 0;
        for _, e in ipairs(edges) do if (e.to_zone == zone and zone_path(230, zone, e.id):len() > 0) then n = n + 1; end end
        if (n >= 2 and zone ~= 230) then multi_zone = zone; break; end
    end
    claim(multi_zone ~= nil, 'the graph has a zone with several reachable entrances from 230 (' .. tostring(multi_zone and zone_names[multi_zone]) .. ')');
    if (multi_zone) then
        local mz = zone_names[multi_zone];
        local sq = { { stable_step_id = 'm:1', order = 1, action = 'travel', entities = { mz }, zones = { mz }, grid_coordinates = { 'M-8' } } };
        targets, info = resolver.resolve_step(sq, 1, make_ctx(230));
        claim(#targets >= 2 and info.kind == 'zone-travel-choice' and info.unbound_square == 'M-8' and info.partial == 'unbound-square' and tostring(targets[1].choice_note):find('M-8', 1, true) ~= nil, 'an exit square over several entrances lists every entrance as a choice, choosing none, as PARTIAL credit that speaks the square (' .. tostring(#targets) .. ')');
        local nosq = { { stable_step_id = 'm:2', order = 1, action = 'travel', entities = { mz }, zones = { mz }, grid_coordinates = {} } };
        targets, info = resolver.resolve_step(nosq, 1, make_ctx(230));
        claim(#targets == 1 and info.kind == 'zone-travel', 'the same travel without a square picks one reachable entrance');
    end

    -- claim 7b: "Home Point" inside a known zone resolves to that zone's numbered home points
    local hp = { { stable_step_id = 'h:1', order = 1, action = 'examine', entities = { 'Home Point', 'Windurst Waters' }, zones = { 'Windurst Waters' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(hp, 1, make_ctx(230));
    claim(#targets >= 1 and targets[1].zone == 238 and name_key(targets[1].name):find('home point #', 1, true) == 1, 'a generic "Home Point" in a known zone lists that zone numbered home points (' .. tostring(#targets) .. ')');

    -- claim 9: a bare nation name is a district CHOICE, never one silently chosen
    local nation = { { stable_step_id = 'n:1', order = 1, action = 'travel', entities = { "San d'Oria" }, zones = {}, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(nation, 1, make_ctx(149));
    -- Was three (one per district). The guide names NATIONS, so a nation is
    -- one answer; offering every district is the same answer written three times.
    claim(#targets == 1 and info.kind == 'zone-travel', 'travel to "San d\'Oria" from Davoi offers ONE way into the nation, not one per district (' .. tostring(#targets) .. ')');
    targets, info = resolver.resolve_step(nation, 1, make_ctx(231));
    claim(#targets == 0 and info.reason == resolver.REASONS.ALREADY_IN_ZONE, 'standing in a district of that nation is already-in-zone');
    local nation_npc = { { stable_step_id = 'n:2', order = 1, action = 'talk', entities = { 'Ambrotien', "San d'Oria" }, zones = {}, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(nation_npc, 1, make_ctx(149));
    claim(#targets >= 1 and targets[1].zone == 230 and name_key(targets[1].name) == 'ambrotien', '"Talk to Ambrotien in San d\'Oria" finds Ambrotien in Southern San d\'Oria');

    -- claim 10 (sol's four gates): sequence is not requiredness
    -- gate 1: the REAL Davoi Report progression routes with zero Silent Oil and zero Prism Powder
    local prog = dofile(ADDON .. '/modules/mission_quest_progression_mission_san_doria.lua');
    local davoi_actions = (prog.objectives or prog)["mission:San d'Oria:5"].progression_actions;
    local never_owned = function () return false; end
    claim(resolver.blocking_prerequisite(davoi_actions, 0, "mission:San d'Oria:5:step-009", never_owned) == nil,
        'gate 1: Davoi travel is not held by the advisory Silent Oil / Prism Powder with none owned');
    -- gate 2: an explicitly linked key item blocks until live evidence satisfies it
    local linked = {
        { step_id = 'l:13', step_order = 13, action = 'examine', items = {}, key_items = { 'Lost document' }, result_items = { 'Lost document' }, material = true },
        { step_id = 'l:16', step_order = 16, action = 'travel', items = {}, key_items = { 'Lost document' }, result_items = {}, material = true },
    };
    local block = resolver.blocking_prerequisite(linked, 12, 'l:16', never_owned);
    claim(block ~= nil and block.step_id == 'l:13', 'gate 2: a travel step that lists the Lost document is held until it is obtained');
    claim(resolver.blocking_prerequisite(linked, 12, 'l:16', function () return true; end) == nil, 'gate 2: live possession of the Lost document releases the travel step');
    -- gate 3: an advisory item (no explicit link) can never produce prerequisite-pending
    local advisory = {
        { step_id = 'a:2', step_order = 2, action = 'obtain', items = { 'Silent Oil', 'Prism Powder' }, key_items = {}, result_items = {}, material = true },
        { step_id = 'a:9', step_order = 9, action = 'travel', items = {}, key_items = {}, result_items = {}, material = true },
    };
    claim(resolver.blocking_prerequisite(advisory, 1, 'a:9', never_owned) == nil, 'gate 3: an unlinked acquisition never blocks travel');
    claim(resolver.blocking_prerequisite(linked, 13, 'l:16', never_owned) == nil, 'an acquisition already behind the completed cursor does not block');
    local text = resolver.prerequisite_refusal(linked[1], { primary_instruction = 'Head to the Cathedral in Northern San d\'Oria.' });
    claim(text.reason == 'prerequisite-pending' and text.detail:find('Lost document', 1, true) ~= nil, 'the held travel step speaks the linked prerequisite (' .. text.detail .. ')');

    -- claim 11: the mission's nation is context for an NPC with no zone
    local halver = { { stable_step_id = 'h:1', order = 1, action = 'talk', entities = { 'Halver' }, zones = {}, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(halver, 1, make_ctx(230, nil, "San d'Oria"));
    claim(#targets >= 1 and targets[1].zone == 233 and info.kind == 'nation-group', 'a San d\'Oria mission with the player back in San d\'Oria finds Halver in Chateau d\'Oraguille');
    targets, info = resolver.resolve_step(halver, 1, make_ctx(230));
    claim(#targets > 0 and info.reason == nil and info.kind == 'entity-zone-choice'
        and info.ambiguity == resolver.REASONS.ENTITY_DUPLICATED,
        'without a nation the two Halvers are offered as a choice, and the ambiguity is still recorded');
    targets, info = resolver.resolve_step(halver, 1, make_ctx(149, nil, "San d'Oria"));
    claim(info.kind ~= 'nation-group' and trim(tostring(info.narrowed_by or '')) == ''
        and info.ambiguity == resolver.REASONS.ENTITY_DUPLICATED,
        'a San d\'Oria mission with the player abroad (Davoi) still has no evidence for the nation group; nothing narrows Halver');
    local halver_abroad = {
        { stable_step_id = 'hx:1', order = 1, action = 'travel', entities = { 'Davoi' }, zones = { 'Davoi' }, grid_coordinates = {} },
        { stable_step_id = 'hx:2', order = 2, action = 'talk', entities = { 'Halver' }, zones = {}, grid_coordinates = {} },
    };
    targets, info = resolver.resolve_step(halver_abroad, 2, make_ctx(230, nil, "San d'Oria"));
    claim(#targets == 0 and info.reason == resolver.REASONS.ENTITY_ABSENT, 'an inherited zone (Davoi) that lacks Halver is a source/catalogue conflict, never overridden by the nation group');
    -- claim 12: a zone-only step with any positional action is carried to the zone
    local rulude = { { stable_step_id = 'r:1', order = 1, action = 'talk', entities = { "Ru'Lude Gardens" }, zones = { "Ru'Lude Gardens" }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(rulude, 1, make_ctx(230));
    claim(#targets >= 1 and info.kind == 'zone-travel' and info.partial == 'zone-only', '"talk ... in Ru\'Lude Gardens" with no NPC named reaches the zone as PARTIAL credit');

    -- claim 13: a title the catalogue does not store is stripped, never guessed past
    local trion = {
        { stable_step_id = 't:0', order = 1, action = 'travel', entities = { "Chateau d'Oraguille" }, zones = { "Chateau d'Oraguille" }, grid_coordinates = {} },
        { stable_step_id = 't:1', order = 2, action = 'talk', entities = { 'Prince Trion' }, zones = {}, grid_coordinates = {} },
    };
    targets, info = resolver.resolve_step(trion, 2, make_ctx(230, nil, "San d'Oria"));
    claim(#targets >= 1 and targets[1].zone == 233 and name_key(targets[1].name) == 'trion' and targets[1].spoken_name == 'Prince Trion', 'Prince Trion after entering the chateau finds the catalogue bare Trion there and keeps the guide name for speech');
    local the_x = { { stable_step_id = 'the:1', order = 1, action = 'talk', entities = { 'The Ambrotien' }, zones = { "Southern San d'Oria" }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(the_x, 1, make_ctx(230));
    claim(#targets == 0, 'the article "the" is never stripped as a title');
    targets, info = resolver.resolve_step({ trion[2] }, 1, make_ctx(230, nil, "San d'Oria"));
    claim(#targets == 0 and (info.reason == resolver.REASONS.ENTITY_DUPLICATED or info.reason == resolver.REASONS.ENTITY_ABSENT), 'with no context the alias is never tried and Prince Trion stays a refusal rather than a guess (' .. tostring(info.reason) .. ')');
    -- claim 14: a modifier that is not a place does not hide the zone
    local sneak = { { stable_step_id = 's:1', order = 1, action = 'travel', entities = { 'Sneak', 'Xarcabard' }, zones = { 'Xarcabard' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(sneak, 1, make_ctx(230));
    claim(#targets >= 1 and (info.kind == 'zone-travel' or info.kind == 'zone-travel-choice'), '"head to Xarcabard with Sneak" is a zone step, Sneak being in the modifier registry (' .. tostring(info.kind) .. ')');
    -- An unknown name is still NOT assumed to be a modifier -- but it no longer
    -- costs the player the zone the guide named. It routes to Xarcabard and
    -- says outright that the guide does not say where inside; the modifier case
    -- resolves as an ordinary zone-travel with nothing to disclaim. The two
    -- stay distinguishable, which is what this claim was always protecting.
    local unknown = { { stable_step_id = 'u:1', order = 1, action = 'travel', entities = { 'Glowing Whatsit', 'Xarcabard' }, zones = { 'Xarcabard' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(unknown, 1, make_ctx(230));
    claim(#targets >= 1 and info.guide_zone_fallback == true and info.partial == 'zone-only',
        'an unknown absent name does not cost the player the zone the guide named (' .. tostring(info.kind) .. ')');
    claim(#targets >= 1 and tostring(targets[1].choice_note or ''):find('does not say where in Xarcabard', 1, true) ~= nil,
        'and the player is told the guide does not say where inside it');
    targets, info = resolver.resolve_step(sneak, 1, make_ctx(230));
    claim(info.guide_zone_fallback ~= true,
        'while a recognised modifier is an ordinary zone step, with nothing to disclaim');
    -- A named zone must still not rescue a NOTE: standing somewhere never
    -- satisfies "X drops from Y in Z". It is no longer REFUSED for that,
    -- though -- a refusal says we failed to route something routable, and a
    -- note was never routable. It is information, and says so.
    local note = { { stable_step_id = 'n:1', order = 1, action = 'note', entities = { 'Yagudo Caulk', 'Giddeus' }, zones = { 'Giddeus' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(note, 1, make_ctx(230));
    claim(#targets == 0 and info.kind == 'note-information' and info.reason == nil
        and info.note_information == true,
        'a note that names a zone yields information, not a destination and not a refusal');
    claim(trim(tostring(info.instruction or '')) == trim(tostring(note[1].primary_instruction or ''))
        and resolver.note_source_mode(note[1]) == 'information',
        'and the guide sentence still travels with it');
    -- And an INHERITED zone is never attributed to the guide.
    local inherited = {
        { stable_step_id = 'i:0', order = 1, action = 'travel', entities = { 'Davoi' }, zones = { 'Davoi' }, grid_coordinates = {} },
        { stable_step_id = 'i:1', order = 2, action = 'talk', entities = { 'Glowing Whatsit' }, zones = {}, grid_coordinates = {} },
    };
    targets, info = resolver.resolve_step(inherited, 2, make_ctx(230));
    claim(#targets == 0 and info.guide_zone_fallback ~= true,
        'a zone inherited from an earlier step never becomes a destination the guide named');
    claim(tostring(info.detail or ''):find('catalogue', 1, true) == nil,
        'and the refusal never says "catalogue" to the player');

    -- claim 15: transports are edges -- Kazham by airship, Whitegate by ship
    local kazham = { { stable_step_id = 'k:1', order = 1, action = 'travel', entities = { 'Kazham' }, zones = { 'Kazham' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(kazham, 1, make_ctx(246));
    claim(#targets >= 1 and targets[1].zone == 250 and targets[1].canonical_edge_id == 900000002, 'travel to Kazham from Port Jeuno binds the airship edge (' .. tostring(targets[1] and targets[1].canonical_edge_id) .. ')');
    local whitegate = { { stable_step_id = 'w:1', order = 1, action = 'travel', entities = { 'Aht Urhgan Whitegate' }, zones = { 'Aht Urhgan Whitegate' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(whitegate, 1, make_ctx(249));
    claim(#targets >= 1 and targets[1].zone == 50 and targets[1].canonical_edge_id == 900000011, 'travel to Whitegate from Mhaura binds the ship edge');
    targets, info = resolver.resolve_step(whitegate, 1, make_ctx(230));
    claim(#targets >= 1 and targets[1].zone == 50 and zone_path(230, 50, targets[1].canonical_edge_id):len() >= 3, 'travel to Whitegate from Southern San d Oria chains walking, the ferry to Mhaura and the ship (' .. tostring(targets[1] and zone_path(230, 50, targets[1].canonical_edge_id):len()) .. ' legs)');
    local past = { { stable_step_id = 'p:1', order = 1, action = 'travel', entities = { 'Batallia Downs (S)' }, zones = { 'Batallia Downs (S)' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(past, 1, make_ctx(230));
    local maw_chain = targets[1] and zone_path(230, 84, targets[1].canonical_edge_id) or T{};
    local uses_maw = false;
    for _, e in ipairs(maw_chain) do if (e.transport and e.transport.type == 'maw') then uses_maw = true; end end
    claim(#targets >= 1 and targets[1].zone == 84 and uses_maw, 'travel to Batallia Downs (S) chains through a Cavernous Maw (' .. tostring(#maw_chain) .. ' legs)');
    local xs = { { stable_step_id = 'x:1', order = 1, action = 'travel', entities = { 'Xarcabard (S)' }, zones = { 'Xarcabard (S)' }, grid_coordinates = {} } };
    targets, info = resolver.resolve_step(xs, 1, make_ctx(230));
    local direct_false = false;
    if (targets[1]) then
        for _, e in ipairs(zone_path(230, 137, targets[1].canonical_edge_id)) do
            if (e.transport and e.from_zone == 112 and e.to_zone == 137) then direct_false = true; end
        end
    end
    claim(not direct_false, 'past Xarcabard is never reached by a present-day Xarcabard Maw (that Maw leads to Abyssea)');
    -- return-home: a prior step bound Halver in the chateau; after Fei Yin, "return to Halver" goes back to that instance
    local home = {
        { stable_step_id = 'rh:1', order = 1, action = 'travel', entities = { "Chateau d'Oraguille" }, zones = { "Chateau d'Oraguille" }, grid_coordinates = {} },
        { stable_step_id = 'rh:2', order = 2, action = 'talk', entities = { 'Halver' }, zones = {}, grid_coordinates = {} },
        { stable_step_id = 'rh:3', order = 3, action = 'travel', entities = { "Fei'Yin" }, zones = { "Fei'Yin" }, grid_coordinates = {} },
        { stable_step_id = 'rh:4', order = 4, action = 'talk', entities = { 'Halver' }, zones = {}, grid_coordinates = {} },
    };
    targets, info = resolver.resolve_step(home, 4, make_ctx(230, nil, "San d'Oria"));
    claim(#targets >= 1 and targets[1].zone == 233 and info.kind == 'return-to-prior', '"Return to Halver" after Fei Yin routes back to the instance an earlier step bound (' .. tostring(info.kind) .. ')');
    local multi = {
        { stable_step_id = 'mp:1', order = 1, action = 'travel', entities = { 'Windurst Waters' }, zones = { 'Windurst Waters' }, grid_coordinates = {} },
        { stable_step_id = 'mp:2', order = 2, action = 'examine', entities = { 'Home Point', 'Windurst Waters' }, zones = { 'Windurst Waters' }, grid_coordinates = {} },
        { stable_step_id = 'mp:3', order = 3, action = 'travel', entities = { "Fei'Yin" }, zones = { "Fei'Yin" }, grid_coordinates = {} },
        { stable_step_id = 'mp:4', order = 4, action = 'examine', entities = { 'Home Point' }, zones = {}, grid_coordinates = {} },
    };
    targets, info = resolver.resolve_step(multi, 4, make_ctx(238, nil, 'Windurst'));
    claim(info.kind ~= 'return-to-prior', 'a same-zone multi-point name (four home points) never collapses into an automatic return (' .. tostring(info.kind or info.reason) .. ')');
    local nohome = { home[3], home[4] };
    targets, info = resolver.resolve_step(nohome, 2, make_ctx(230, nil, "San d'Oria"));
    claim(#targets == 0, 'with no prior binding, "Return to Halver" from Fei Yin stays a refusal (' .. tostring(info.reason) .. ')');

    do
        local steps = { {
            stable_step_id = 'duplicate:survival-guide',
            order = 1,
            action = 'use',
            entities = { 'Survival Guide' },
            zones = {},
            grid_coordinates = {},
            primary_instruction = 'Use a Survival Guide.',
        } };

        local tg, nf =
            resolver.resolve_step(
                steps, 1, make_ctx(231));
        local physical_here, staged = 0, 0;
        local stage_zones, unique_stages = {}, true;

        for _, point in ipairs(tg) do
            if (point.entity_choice_zone == true) then
                staged = staged + 1;
                if (stage_zones[point.zone]) then
                    unique_stages = false;
                end
                stage_zones[point.zone] = true;
            elseif (point.zone == 231) then
                physical_here = physical_here + 1;
            end
        end

        claim(nf.kind == 'entity-zone-choice'
            and nf.reason == nil
            and nf.ambiguity
                == resolver.REASONS.ENTITY_DUPLICATED
            and nf.choice_stage == 'mixed',
            'Survival Guide exposes a mixed physical/zone choice');

        claim(nf.raw_candidate_count
                > nf.physical_candidate_count
            and nf.physical_candidate_zone_count > 1
            and physical_here > 1
            and staged > 1
            and unique_stages,
            'Survival Guide precisely deduplicates and emits one stage target per reachable remote zone');

        claim(type(nf.unreachable_choices) == 'table'
            and #nf.unreachable_choices > 0
            and nf.instruction == 'Use a Survival Guide.',
            'Survival Guide preserves unavailable zones and guide speech');
    end

    do
        local step = real_step(
            'mission_quest_reconcile_mission_a_crystalline_prophecy',
            'mission:A Crystalline Prophecy:4',
            'mission:A Crystalline Prophecy:4:step-003');

        local tg, nf =
            resolver.resolve_step(
                { step }, 1, make_ctx(230));

        claim(#tg == 1
            and tg[1].zone == 126
            and name_key(tg[1].name) == '???'
            and nf.kind == 'explicit'
            and nf.reason == nil
            and nf.ambiguity
                == resolver.REASONS.ENTITY_DUPLICATED
            and nf.narrowed_by == 'guide-zone'
            and nf.narrowed_candidate_count == 1,
            'real Qufim ??? preserves explicit kind while retaining global ambiguity');

        claim(nf.unbound_square == 'G-6'
            and nf.instruction == step.bg_instruction
            and nf.bg_instruction == step.bg_instruction
            and nf.ffxiclopedia_instruction
                == step.ffxiclopedia_instruction,
            'real Qufim ??? retains G-6 and both source instructions');
    end

    do
        local step = real_step(
            'mission_quest_reconcile_mission_windurst',
            'mission:Windurst:22',
            'mission:Windurst:22:step-017');

        local tg, nf =
            resolver.resolve_step(
                { step }, 1, make_ctx(241));
        local current, staged = 0, 0;

        for _, point in ipairs(tg) do
            if (point.entity_choice_zone == true) then
                staged = staged + 1;
            elseif (point.zone == 241
                and name_key(point.name) == 'apururu') then
                current = current + 1;
            end
        end

        claim(current >= 1
            and staged > 1
            and nf.kind == 'entity-zone-choice'
            and nf.choice_stage == 'mixed'
            and nf.reason == nil
            and nf.ambiguity
                == resolver.REASONS.ENTITY_DUPLICATED,
            'real Apururu exposes the current NPC plus remote zone stages');

        claim(has_unreachable_zone(nf, 45, 1)
            and nf.instruction == step.bg_instruction,
            'real Apururu reports its unreachable zone-45 candidate');
    end

    do
        local halver = { {
            stable_step_id = 'duplicate:halver',
            order = 1,
            action = 'talk',
            entities = { 'Halver' },
            zones = {},
            grid_coordinates = {},
            primary_instruction = 'Return to Halver.',
        } };

        local tg, nf =
            resolver.resolve_step(
                halver, 1, make_ctx(230));

        claim(nf.raw_candidate_count == 3
            and nf.action_eligible_candidate_count == 3
            and nf.physical_candidate_count == 2
            and nf.deduplicated_candidate_count == 1,
            'Halver deduplicates three rows to two physical candidates');

        claim(#tg == 1
            and tg[1].entity_choice_zone == true
            and tg[1].zone == 233
            and nf.kind == 'entity-zone-choice'
            and nf.reason == nil
            and has_unreachable_zone(nf, 132, 1),
            'bare Halver exposes Chateau staging and unavailable zone 132');

        local nation_tg, nation_nf =
            resolver.resolve_step(
                halver,
                1,
                make_ctx(230, nil, "San d'Oria"));

        claim(#nation_tg == 1
            and nation_tg[1].zone == 233
            and nation_nf.kind == 'nation-group'
            and nation_nf.narrowed_by == 'nation-group'
            and nation_nf.ambiguity
                == resolver.REASONS.ENTITY_DUPLICATED,
            'nation evidence narrows Halver without erasing ambiguity metadata');

        local inherited = {
            {
                stable_step_id = 'halver-conflict:1',
                order = 1,
                action = 'travel',
                entities = { 'Davoi' },
                zones = { 'Davoi' },
                grid_coordinates = {},
            },
            {
                stable_step_id = 'halver-conflict:2',
                order = 2,
                action = 'talk',
                entities = { 'Halver' },
                zones = {},
                grid_coordinates = {},
                primary_instruction = 'Return to Halver.',
            },
        };

        local conflict_tg, conflict_nf =
            resolver.resolve_step(
                inherited,
                2,
                make_ctx(230, nil, "San d'Oria"));

        claim(#conflict_tg == 0
            and conflict_nf.reason
                == resolver.REASONS.ENTITY_ABSENT
            and conflict_nf.kind == 'none',
            'an inherited Davoi context missing Halver remains a source conflict');
    end

    do
        local step = real_step(
            'mission_quest_reconcile_mission_treasures_of_aht_urhgan',
            'mission:Treasures of Aht Urhgan:2',
            'mission:Treasures of Aht Urhgan:2:step-057');

        local tg, nf =
            resolver.resolve_step(
                { step }, 1, make_ctx(230));

        claim(nf.raw_candidate_count == 3
            and nf.action_eligible_candidate_count == 2
            and nf.action_filtered_count == 1
            and nf.physical_candidate_count == 2
            and nf.physical_candidate_zone_count == 2,
            'real talk-to Naja filters one enemy before grouping');

        claim(#tg == 1
            and tg[1].entity_choice_zone == true
            and tg[1].zone == 50
            and nf.kind == 'entity-zone-choice'
            and nf.reason == nil
            and has_unreachable_zone(nf, 77, 1),
            'real Naja exposes Whitegate and reports the unavailable Nyzul NPC');
    end

    do
        local hp = { {
            stable_step_id = 'duplicate:home-point',
            order = 1,
            action = 'examine',
            entities = {
                'Home Point',
                'Windurst Waters',
            },
            zones = { 'Windurst Waters' },
            grid_coordinates = {},
            primary_instruction =
                'Examine a Home Point in Windurst Waters.',
        } };

        local tg, nf =
            resolver.resolve_step(
                hp, 1, make_ctx(238));
        local identities = {};

        for _, point in ipairs(tg) do
            identities[trim(point.destination_id)] = true;
        end

        local identity_count = 0;
        for _ in pairs(identities) do
            identity_count = identity_count + 1;
        end

        claim(#tg == 4
            and identity_count == 4
            and nf.kind == 'entity-choice'
            and nf.reason == nil
            and nf.choice_stage == 'physical'
            and nf.narrowed_by == 'guide-zone',
            'four same-zone Home Points remain four physical choices');

        local bare = { {
            stable_step_id = 'duplicate:bare-home-point',
            order = 1,
            action = 'examine',
            entities = { 'Home Point' },
            zones = {},
            grid_coordinates = {},
            primary_instruction = 'Examine a Home Point.',
        } };

        tg, nf =
            resolver.resolve_step(
                bare, 1, make_ctx(230));

        claim(#tg > 0
            and nf.kind == 'entity-zone-choice'
            and nf.reason == nil
            and nf.physical_candidate_zone_count > 1,
            'bare Home Point resolves through the global numbered-base index');
    end

    do
        local prior = {
            {
                stable_step_id = 'prior-choice:1',
                order = 1,
                action = 'talk',
                entities = { 'Halver' },
                zones = {},
                grid_coordinates = {},
            },
            {
                stable_step_id = 'prior-choice:2',
                order = 2,
                action = 'talk',
                entities = { 'Halver' },
                zones = {},
                grid_coordinates = {},
            },
            {
                stable_step_id = 'prior-choice:3',
                order = 3,
                action = 'travel',
                entities = { "Fei'Yin" },
                zones = { "Fei'Yin" },
                grid_coordinates = {},
            },
            {
                stable_step_id = 'prior-choice:4',
                order = 4,
                action = 'talk',
                entities = { 'Halver' },
                zones = {},
                grid_coordinates = {},
                primary_instruction =
                    'Return to any Halver.',
            },
        };

        local prior_ctx =
            make_ctx(230, function(step_id)
                if (step_id == 'prior-choice:1') then
                    return 233;
                elseif (step_id == 'prior-choice:2') then
                    return 132;
                end
                return 0;
            end);

        local tg, nf =
            resolver.resolve_step(
                prior, 4, prior_ctx);

        claim(#tg == 2
            and nf.kind == 'return-to-prior-choice'
            and nf.reason == nil
            and nf.equivalent_choices == true,
            'indefinite prior bindings remain explicit equivalent choices');

        local definite = {};
        for index, step in ipairs(prior) do
            definite[index] = {};
            for key, value in pairs(step) do
                definite[index][key] = value;
            end
        end
        definite[4].primary_instruction =
            'Return to Halver.';

        tg, nf =
            resolver.resolve_step(
                definite, 4, prior_ctx);

        claim(#tg == 2
            and nf.kind == 'return-to-prior-choice'
            and nf.reason == nil
            and nf.equivalent_choices == false
            and nf.ambiguity
                == resolver.REASONS.ENTITY_DUPLICATED,
            'definite prior bindings remain an explicit non-equivalent choice');
    end

    -- THE ORACLE HAS TO BE ABLE TO FAIL. This harness ignored the fourth
    -- preferred_zones argument of zone_path entirely, so every claim that has
    -- ever asserted guide-road behaviour through it was asserting nothing
    -- (sol found it). These two claims are the proof it is fixed: they compare
    -- the SAME journey with and without a named road, on the shipped graph, in
    -- exactly the fault class the router was extracted to prevent -- a blind
    -- player sent through King Ranperre's Tomb, an undead dungeon. Under the
    -- old implementation both roads were identical and both claims were red.
    do
        local CARPENTERS, EAST_RONFAURE = 2, 101;
        local WEST_RONFAURE, RANPERRE = 100, 190;
        local function visits(path, zone)
            for _, edge in ipairs(path or {}) do
                if ((tonumber(edge.to_zone) or 0) == zone) then return true; end
            end
            return false;
        end

        local plain = zone_path(CARPENTERS, EAST_RONFAURE, 0, nil);
        claim(#plain > 0 and visits(plain, RANPERRE),
            'with no road named, the shortest chain to East Ronfaure goes through King Ranperre\'s Tomb');

        local guided = zone_path(CARPENTERS, EAST_RONFAURE, 0, { WEST_RONFAURE });
        claim(#guided > 0 and visits(guided, WEST_RONFAURE) and not visits(guided, RANPERRE),
            'and naming West Ronfaure moves the road off it -- the harness passes the guide road through');
    end

    -- THE BATCH MUST CHOOSE WHAT THE PER-ENTRANCE SEARCH CHOSE. Not merely
    -- "is it reachable": the same entrance, the same reason, and the same
    -- ordered alternatives when an unbound square makes every entrance a
    -- choice. Run over every destination in the shipped graph from three
    -- player zones, with and without a square. Anything else is an
    -- optimisation that quietly reroutes people.
    do
        local mismatches = {};
        local compared = 0;

        local function edge_id(edge)
            return tonumber(type(edge) == 'table' and edge.id or nil) or 0;
        end
        local function edge_ids(edges_list)
            local out = {};
            for _, edge in ipairs(edges_list or {}) do out[#out + 1] = edge_id(edge); end
            return table.concat(out, ',');
        end

        local destinations = {};
        for zone in pairs(zone_names) do destinations[#destinations + 1] = zone; end
        table.sort(destinations);

        for _, player_zone in ipairs({ 230, 149, 238 }) do
            for _, square in ipairs({ false, true }) do
                local step = { stable_step_id = 'parity', order = 1, action = 'travel',
                    entities = {}, zones = {},
                    grid_coordinates = square and { 'G-6' } or {} };

                local batched = make_ctx(player_zone);
                local legacy = make_ctx(player_zone);
                legacy.entry_edge_candidates = nil;

                for _, dest in ipairs(destinations) do
                    compared = compared + 1;
                    local be, br, ba = resolver.choose_entry_edge(dest, step, batched);
                    local le, lr, la = resolver.choose_entry_edge(dest, step, legacy);
                    if (edge_id(be) ~= edge_id(le) or tostring(br) ~= tostring(lr)
                        or edge_ids(ba) ~= edge_ids(la)) then
                        if (#mismatches < 6) then
                            mismatches[#mismatches + 1] = ('%d->%d square=%s batch=%d/%s/[%s] legacy=%d/%s/[%s]')
                                :format(player_zone, dest, tostring(square),
                                    edge_id(be), tostring(br), edge_ids(ba),
                                    edge_id(le), tostring(lr), edge_ids(la));
                        end
                    end
                end
            end
        end

        claim(compared > 1000 and #mismatches == 0,
            #mismatches == 0
                and ('batch choices equal the legacy real graph over %d comparisons, including ordered square alternatives'):format(compared)
                or ('batch mismatches: ' .. table.concat(mismatches, ', ')));
    end

    -- WHAT THE BATCH IS ALLOWED TO ASSUME. A provider that fails, or that has
    -- nothing to say about a destination, must fall back to the search that
    -- always worked. A provider that answers with an EMPTY bucket has proved
    -- the destination unreachable, and restarting the search would throw that
    -- evidence away (sol).
    do
        local step = { stable_step_id = 'batch', order = 1, action = 'travel',
            entities = {}, zones = {}, grid_coordinates = {} };

        local function counting_ctx(provider)
            local ctx = make_ctx(230);
            local calls = 0;
            local inner = ctx.zone_path;
            ctx.zone_path = function (...) calls = calls + 1; return inner(...); end
            ctx.entry_edge_candidates = provider;
            return ctx, function () return calls; end
        end

        local failing, failing_calls = counting_ctx(function () error('provider down'); end);
        local edge = resolver.choose_entry_edge(149, step, failing);
        claim(edge ~= nil and failing_calls() > 0,
            'a provider that fails falls back to the legacy router rather than refusing');

        local missing, missing_calls = counting_ctx(function () return {}; end);
        local missing_edge = resolver.choose_entry_edge(149, step, missing);
        claim(missing_edge ~= nil and missing_calls() > 0,
            'a missing provider key uses the legacy router');

        local empty, empty_calls = counting_ctx(function () return { [149] = {} }; end);
        local empty_edge, empty_reason = resolver.choose_entry_edge(149, step, empty);
        claim(empty_edge == nil and empty_reason == resolver.REASONS.NO_ZONE_CHAIN
            and empty_calls() == 0,
            'an explicit empty provider answer is evidence, and does not restart the search');

        -- One call, one tree, for a hundred destinations.
        reset_entry_edge_counters();
        local many = {};
        for zone in pairs(zone_names) do
            if (#many < 100 and zone ~= 230) then many[#many + 1] = zone; end
        end
        resolver.choose_entry_edges(many, step, make_ctx(230));
        local provider_calls, tree_calls = entry_edge_counters();
        claim(#many == 100 and provider_calls == 1 and tree_calls == 1,
            '100 destinations with no road named cost one provider call and one search tree');

        -- And the guide's road is never answered by the shared plain tree.
        reset_entry_edge_counters();
        local road_ctx, road_calls = counting_ctx(harness_entry_edge_candidates);
        local road_step = { stable_step_id = 'road', order = 1, action = 'travel',
            entities = {}, zones = { 'La Theine Plateau', 'Jugner Forest' },
            grid_coordinates = {} };
        local road_edge = resolver.choose_entry_edge(149, road_step, road_ctx);
        local road_provider = entry_edge_counters();
        claim(road_edge ~= nil and road_provider == 0 and road_calls() > 0,
            'a step naming its road keeps the per-entrance scorer -- the shared tree is not equivalent to it');
    end

    do
        local note = {
            action = 'note',
            primary_instruction =
                'This is guide information.',
            zones = { 'Davoi' },
            entities = { '???' },
        };
        local targets, info =
            resolver.resolve_step(
                { note },
                1,
                make_ctx(230));

        claim(#targets == 0,
            'unannotated notes produce zero targets');
        claim(info.kind == 'note-information'
                and info.reason == nil,
            'unannotated notes are information rather than refusals');
    end

    do
        local step = real_step(
            'mission_quest_reconcile_mission_assault',
            'mission:Assault:34',
            'mission:Assault:34:step-001');
        local targets, info =
            resolver.resolve_step(
                { step },
                1,
                make_ctx(230));

        claim(#(step.zones or {}) == 1
                and #(step.entities or {}) == 4,
            'Assault 34 step 001 is the real flattened briefing fixture');
        claim(#targets == 0
                and info.kind == 'note-information',
            'one accidental flattened match never creates a note binding');
    end

    do
        local step = {
            action = 'note',
            zones = {
                'Aht Urhgan Whitegate',
            },
            entities = { 'Lageegee' },
        };
        local variants =
            resolver.note_route_variants(step);

        claim(#variants == 0,
            'flattened note fields never manufacture bindings');
    end

    do
        local step = {
            action = 'note',
            primary_instruction =
                'Travel to Davoi.',
            note_route_options = {
                {
                    scope = 'zone',
                    zone_name = 'Davoi',
                },
            },
        };
        local targets, info =
            resolver.resolve_step(
                { step },
                1,
                make_ctx(230));

        claim(#targets > 0
                and targets[1].zone == 149
                and info.kind == 'note-route',
            'explicit zone note binding routes only from its annotation');
    end

    do
        local step = {
            action = 'note',
            primary_instruction =
                'Keep this sentence.',
            note_route_options = {
                {
                    scope = 'entity',
                    zone_name = 'Nowhere',
                    entity_name = 'Nobody',
                },
            },
        };
        local targets, info =
            resolver.resolve_step(
                { step },
                1,
                make_ctx(230));

        claim(#targets == 0
                and info.kind == 'note-information'
                and info.reason == nil,
            'invalid explicit note binding remains guide information');
        claim(#info.note_route_failures == 1,
            'invalid explicit note binding retains a typed diagnostic');
    end

    do
        local step = {
            action = 'note',
            note_attach_to_step_id = 'step-004',
            navigation_target = {},
            note_route_options = {
                {
                    scope = 'zone',
                    zone_name = 'Davoi',
                },
            },
        };

        claim(resolver.note_source_mode(step)
                == 'attachment',
            'attachment outranks verified and explicit note routing');

        step.note_attach_to_step_id = nil;

        claim(resolver.note_source_mode(step)
                == 'verified',
            'verified note target outranks explicit binding');

        step.navigation_target = nil;

        claim(resolver.note_source_mode(step)
                == 'explicit',
            'reviewed annotation produces explicit note mode');

        step.note_route_options = nil;
        step.zones = { 'Davoi' };
        step.entities = { '???' };

        claim(resolver.note_source_mode(step)
                == 'information',
            'flattened note fields remain information');
    end

    do
        local step = {
            action = 'note',
            zones = {
                'King Ranperre\'s Tomb',
            },
            note_route_options = {
                {
                    scope = 'zone',
                    zone_name = 'Davoi',
                },
            },
        };

        claim(resolver.named_via_zones(
                step,
                make_ctx(230)) == nil,
            'raw note zones cannot constrain the selected road');
    end

    do
        local note = {
            stable_step_id = 'step-note',
            action = 'note',
            note_attach_to_step_id =
                'step-004',
            primary_instruction =
                'Bring Silent Oil first.',
        };
        local target = {
            stable_step_id = 'step-004',
            action = 'talk',
        };
        local other = {
            stable_step_id = 'step-005',
            action = 'talk',
        };
        local attachments =
            resolver.note_attachments({
                note,
                target,
                other,
            });
        local shared = {
            choice_note = 'Existing.',
        };
        local attached =
            resolver.point_with_attached_notes(
                shared,
                attachments['step-004']);
        local untouched =
            resolver.point_with_attached_notes(
                shared,
                attachments['step-005']);

        claim(attached ~= shared
                and attached.choice_note:find(
                    'Guide note: Bring Silent Oil first.',
                    1,
                    true) ~= nil,
            'attached note annotates only its exact actionable row');
        claim(untouched == shared
                and shared.choice_note == 'Existing.',
            'attached note neither leaks nor mutates shared catalogue data');
    end

        do
            local selected = {};

            for _, point in ipairs(
                    points_by_entity.apururu or {}) do
                local zone = tonumber(point.zone) or 0;

                if (zone == 239 or zone == 241) then
                    selected[#selected + 1] = point;
                end
            end

            local physical =
                resolver.dedupe_entity_points(
                    selected,
                    make_ctx(230));
            local zones = {};

            for _, point in ipairs(physical) do
                zones[tonumber(point.zone) or 0] =
                    true;
            end

            claim(zones[239] and zones[241],
                'same-coordinate Apururu rows remain distinct across zones');
        end

        local function inherited_fixture(
            step_id,
            action,
            relationship,
            target,
            target_kind,
            entities,
            rows)

            local steps = {
                {
                    stable_step_id =
                        step_id .. ':prior',
                    order = 1,
                    action = 'travel',
                    zones = {
                        "Southern San d'Oria",
                    },
                    entities = {
                        "Southern San d'Oria",
                    },
                    grid_coordinates = {},
                },
                {
                    stable_step_id = step_id,
                    order = 2,
                    action = action,
                    zones = {},
                    entities =
                        entities or { target },
                    grid_coordinates = {},
                },
            };

            local ctx = make_ctx(230);
            local old_entity =
                ctx.points_for_entity;
            local old_zone =
                ctx.points_for_zone_entity;

            ctx.primary_actions_for_step =
                function(value)
                    if (value ~= step_id) then
                        return {};
                    end

                    return {
                        {
                            step_id = step_id,
                            action = action,
                            relationship = relationship,
                            target = target,
                            target_kind = target_kind,
                        },
                    };
                end;

            if (type(rows) == 'table') then
                ctx.points_for_entity =
                    function(key)
                        if (key == name_key(target)) then
                            return rows;
                        end

                        return old_entity(key);
                    end;

                ctx.points_for_zone_entity =
                    function(zone, key)
                        if (key == name_key(target)) then
                            local result = {};

                            for _, point in ipairs(rows) do
                                if (tonumber(point.zone)
                                        == tonumber(zone)) then
                                    result[#result + 1] =
                                        point;
                                end
                            end

                            return result;
                        end

                        return old_zone(zone, key);
                    end;
            end

            return steps, ctx;
        end

        do
            local cases = {
                { 'talk', 'talk-to', 'npc' },
                { 'trade', 'trade-to', 'npc' },
                { 'deliver', 'deliver-to', 'npc' },
                { 'examine', 'examine-object', 'object' },
                { 'use', 'use-object', 'object' },
            };
            local all_safe = true;

            for i, value in ipairs(cases) do
                local step_id =
                    'compact-direct:' .. tostring(i);
                local steps, ctx =
                    inherited_fixture(
                        step_id,
                        value[1],
                        value[2],
                        'Contract Target',
                        value[3],
                        { 'Contract Target' },
                        {
                            {
                                zone = 149,
                                name = 'Contract Target',
                                kind = value[3],
                                x = 1,
                                z = 2,
                                y = 3,
                            },
                        });
                local targets, info =
                    resolver.resolve_step(
                        steps,
                        2,
                        ctx);

                if (#targets ~= 1
                        or targets[1].zone ~= 149
                        or info.primary_target_source
                            ~= 'compact-action'
                        or info.inherited_context_conflict
                            ~= true) then
                    all_safe = false;
                end
            end

            claim(all_safe,
                'the five direct compact relationships rescue exact targets');
        end

        -- An incidental noun in the inherited zone must not answer before the
        -- proven primary target.
        do
            local steps, ctx =
                inherited_fixture(
                    'compact:gentle-tiger',
                    'talk',
                    'talk-to',
                    'Gentle Tiger',
                    'npc',
                    {
                        'Gentle Tiger',
                        'Quadav',
                    },
                    {
                        {
                            zone = 87,
                            name = 'Gentle Tiger',
                            kind = 'npc',
                            x = -203.932,
                            z = 2.237,
                            y = -9.998,
                        },
                    });

            local old_entity =
                ctx.points_for_entity;
            local old_zone =
                ctx.points_for_zone_entity;

            local quadav = {
                {
                    zone = 230,
                    name = 'Quadav',
                    kind = 'npc',
                    x = 0,
                    z = 0,
                    y = 0,
                },
            };

            ctx.points_for_entity =
                function(key)
                    if (key == 'quadav') then
                        return quadav;
                    end
                    return old_entity(key);
                end;

            ctx.points_for_zone_entity =
                function(zone, key)
                    if (key == 'quadav'
                            and tonumber(zone) == 230) then
                        return quadav;
                    end
                    return old_zone(zone, key);
                end;

            local targets =
                resolver.resolve_step(
                    steps,
                    2,
                    ctx);
            local only_primary = #targets > 0;

            for _, point in ipairs(targets) do
                if (name_key(point.name)
                        ~= 'gentle tiger') then
                    only_primary = false;
                end
            end

            claim(only_primary,
                'incidental Quadav in inherited zone cannot preempt Gentle Tiger');
        end

        do
            local unsafe = {
                {
                    id = 'unsafe:arciela',
                    action = 'fight',
                    relationship = 'protect-target',
                    target = 'Arciela',
                    kind = 'npc',
                },
                {
                    id = 'unsafe:chigoe',
                    action = 'travel',
                    relationship = 'travel-to',
                    target = 'Chigoe',
                    kind = 'enemy',
                },
                {
                    id = 'unsafe:question',
                    action = 'examine',
                    relationship = 'examine-object',
                    target = '???',
                    kind = 'object',
                },
            };
            local all_blocked = true;

            for _, value in ipairs(unsafe) do
                local steps, ctx =
                    inherited_fixture(
                        value.id,
                        value.action,
                        value.relationship,
                        value.target,
                        value.kind,
                        { value.target });

                local targets, info =
                    resolver.resolve_step(
                        steps,
                        2,
                        ctx);

                -- WHAT MUST HOLD IS THAT NOTHING ESCAPES. Requiring zero
                -- targets asserted more than that and was wrong: with an
                -- inherited Southern San d'Oria, "examine ???" legitimately
                -- finds 20 distinct ??? THERE, and the pre-change resolver
                -- returns exactly the same 20. That is the ordinary
                -- inherited-zone path offering every candidate in the zone the
                -- guide gave us, which is the duplicate contract working. The
                -- danger this claim exists to catch is different: an unsafe
                -- relationship proving a primary target, which would let it
                -- override the inherited zone and search the whole catalogue --
                -- Arciela's enemy record, a Quadav standing in for Gentle
                -- Tiger. So: no proven target, and nothing outside the zone.
                if (info.primary_target_source ~= nil) then
                    all_blocked = false;
                end

                for _, point in ipairs(targets) do
                    if ((tonumber(point.zone) or 0) ~= 230) then
                        all_blocked = false;
                    end
                end
            end

            claim(all_blocked,
                'fight, protect, travel and generic-marker matches never prove a target, and never leave the inherited zone');
        end

        do
            local step_id = 'unsafe:two-primary';
            local steps, ctx =
                inherited_fixture(
                    step_id,
                    'talk',
                    'talk-to',
                    'First Person',
                    'npc',
                    {
                        'First Person',
                        'Second Person',
                    });

            ctx.primary_actions_for_step =
                function()
                    return {
                        {
                            step_id = step_id,
                            action = 'talk',
                            relationship = 'talk-to',
                            target = 'First Person',
                            target_kind = 'npc',
                        },
                        {
                            step_id = step_id,
                            action = 'talk',
                            relationship = 'talk-to',
                            target = 'Second Person',
                            target_kind = 'npc',
                        },
                    };
                end;

            local targets, info =
                resolver.resolve_step(
                    steps,
                    2,
                    ctx);

            claim(#targets == 0
                    and info.primary_target_source
                        == nil,
                'two distinct compact primary targets disable automatic rescue');
        end

    -- A DISAGREEMENT IS NOT A REASON TO HIDE THE STEP. All 1,451 conflicted
    -- steps name exactly one conflicting field, target_identity -- the two
    -- pages wording the target differently. Both guards refused them outright,
    -- and the census excluded them, so 632 mission steps were invisible as
    -- well as unroutable. The real case, live 2026-08-23:
    do
        local reconcile = dofile(ADDON .. '/modules/mission_quest_reconcile_mission_san_doria.lua');
        local entry = reconcile["mission:San d'Oria:5"];
        local idx;
        for i, s in ipairs(entry.steps) do
            if (s.stable_step_id == "mission:San d'Oria:5:step-013") then idx = i; end
        end
        local ctx = make_ctx(149, nil, nil, "mission:San d'Oria:5");

        local readings = ctx.source_readings("mission:San d'Oria:5:step-013");
        claim(type(readings.bg) == 'table' and type(readings.ffxiclopedia) == 'table',
            'both pages are readable on their own terms for a conflicted step');
        claim(#(readings.bg.entities or {}) == 1
            and name_key(readings.bg.entities[1]) == 'lost document'
            and #(readings.ffxiclopedia.entities or {}) == 2,
            'and they really do differ -- BG names only the reward, FFXIclopedia names the marker');

        local targets, info = resolver.resolve_step(entry.steps, idx, ctx);
        claim(#targets == 4 and info.reason == nil,
            ('the step routes instead of refusing (%d targets, reason %s)')
                :format(#targets, tostring(info.reason)));
        local all_markers = true;
        for _, point in ipairs(targets) do
            if (point.zone ~= 149 or name_key(point.name) ~= '!') then all_markers = false; end
        end
        claim(all_markers,
            'to the four ! markers in Davoi, which only FFXIclopedia named');
        claim(info.ambiguity == 'source-conflict'
            and trim(tostring(info.unbound_square or '')) == 'J-8',
            ('the disagreement is recorded and the BG square survives (%s, %s)')
                :format(tostring(info.ambiguity), tostring(info.unbound_square)));
        claim(trim(tostring(info.conflict_sources or '')) == 'FFXIclopedia',
            'and the page that named a routable place is attributed');

        -- Without the per-page readings the union is unsafe, so the old
        -- refusal must stand rather than resolving merged fields.
        local blind = make_ctx(149);
        blind.source_readings = function () return {}; end
        local blind_targets, blind_info = resolver.resolve_step(entry.steps, idx, blind);
        claim(#blind_targets == 0
            and blind_info.reason == resolver.REASONS.SOURCE_CONFLICT,
            'with no per-page reading available it still refuses rather than guessing from the merge');
    end

    -- claim 8: refusal speech names the class, never the generic sentence
    local speech = resolver.refusal_speech('The Davoi Report', { reason = resolver.REASONS.ZONE_CONTEXT_MISSING, detail = 'the guide does not say which zone Zantaviat is in' });
    claim(speech:find('Zantaviat', 1, true) ~= nil and speech:find('source%-backed') == nil, 'refusal speech carries the detail and drops the generic sentence');
end

-- census ------------------------------------------------------------------
print('');
print('Census over every reconciled step (player zone 230 for zone-travel reachability):');
-- --missions restricts the census to mission modules. The guide road is now
-- honoured here (it never was, because the harness had no zone_id_for_name),
-- and scoring a road is a bounded-depth search per entrance, so the full
-- 29,673-step census costs minutes. The release gate reads only the MISSIONS
-- ONLY line, so it asks for that alone.
local missions_only = false;
for _, value in ipairs(arg) do
    if (value == '--missions') then missions_only = true; end
end
local modules = {};
local p = io.popen('dir /b "' .. ADDON:gsub('/', '\\') .. '\\modules\\mission_quest_reconcile_*.lua"');
for line in p:lines() do
    local name = (line:gsub('%.lua$', ''));
    if (not missions_only or name:find('reconcile_mission_', 1, true) ~= nil) then
        modules[#modules + 1] = name;
    end
end
p:close();
table.sort(modules);
local total_steps, old_ok, new_ok = 0, 0, 0;
local mission_steps, mission_old, mission_new = 0, 0, 0;
local reason_counts, kind_counts = {}, {};
local absent_names, duplicated_names = {}, {};
for _, mod in ipairs(modules) do
    local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. mod .. '.lua');
    if (ok and type(tbl) == 'table') then
        local dest_map = progression_destinations((mod:gsub('reconcile', 'progression')));
        local nation = mod:match('mission_(san_doria)$') and "San d'Oria" or mod:match('mission_(bastok)$') and 'Bastok' or mod:match('mission_(windurst)$') and 'Windurst' or nil;
        local ctx = make_ctx(230, function (step_id) return dest_map[step_id] or 0; end, nation);
        local m_steps, m_old, m_new = 0, 0, 0;
        for native_key, entry in pairs(tbl) do
            local steps = type(entry) == 'table' and entry.steps or nil;
            -- Point the ctx at this objective so a conflicted step can be read
            -- from each page's own structured fields.
            ctx.objective.key = native_key;
            if (type(steps) == 'table') then
                for i, step in ipairs(steps) do
                    -- CONFLICTS ARE COUNTED NOW. They used to be excluded from
                    -- the census as well as refused, so the 1,451 steps the two
                    -- pages word differently were invisible in every number we
                    -- ever quoted.
                    if (type(step) == 'table') then
                        m_steps = m_steps + 1;
                        -- old rule: explicit zone AND a non-zone entity with a catalogue point in that zone
                        local zone_ids, entity_keys = resolver.classify_step(step, ctx);
                        local old_hit = false;
                        for zone in pairs(zone_ids) do
                            for key in pairs(entity_keys) do
                                for _, pt in ipairs(points_by_zone_entity[zone .. '\t' .. key] or {}) do
                                    if (kind_allowed(step.action, pt.kind)) then old_hit = true; end
                                end
                            end
                        end
                        if (old_hit) then m_old = m_old + 1; end
                        local targets, info = resolver.resolve_step(steps, i, ctx);
                        if (#targets > 0) then
                            m_new = m_new + 1;
                            kind_counts[info.kind] = (kind_counts[info.kind] or 0) + 1;
                        elseif (info.kind == 'note-information') then
                            -- A note with nothing to walk to is not a failure to
                            -- route; it is a sentence, and counting it as a
                            -- nil-reason refusal buried 22,523 of them in the
                            -- refusal column (sol).
                            kind_counts[info.kind] = (kind_counts[info.kind] or 0) + 1;
                        else
                            reason_counts[tostring(info.reason)] = (reason_counts[tostring(info.reason)] or 0) + 1;
                            if (info.reason == resolver.REASONS.ENTITY_ABSENT or info.reason == resolver.REASONS.ENTITY_DUPLICATED) then
                                local bucket = info.reason == resolver.REASONS.ENTITY_ABSENT and absent_names or duplicated_names;
                                local _, ek = resolver.classify_step(step, ctx);
                                for _, label in pairs(ek) do bucket[label] = (bucket[label] or 0) + 1; end
                            end
                        end
                    end
                end
            end
        end
        total_steps, old_ok, new_ok = total_steps + m_steps, old_ok + m_old, new_ok + m_new;
        if (mod:find('reconcile_mission_', 1, true)) then
            mission_steps, mission_old, mission_new = mission_steps + m_steps, mission_old + m_old, mission_new + m_new;
        end
        print(('  %-55s steps=%5d old=%5d new=%5d'):format(mod:gsub('mission_quest_reconcile_', ''), m_steps, m_old, m_new));
    end
end
print(('TOTAL steps=%d routable-before=%d routable-after=%d'):format(total_steps, old_ok, new_ok));
local kinds = {}; for k, v in pairs(kind_counts) do kinds[#kinds + 1] = k .. '=' .. v; end table.sort(kinds);
print('  by kind: ' .. table.concat(kinds, ' '));
local reasons = {}; for k, v in pairs(reason_counts) do reasons[#reasons + 1] = k .. '=' .. v; end table.sort(reasons);
print('  remaining refusals: ' .. table.concat(reasons, ' '));
print(('MISSIONS ONLY steps=%d routable-before=%d routable-after=%d'):format(mission_steps, mission_old, mission_new));
local function top(bucket, n, label)
    local rows = {}; for k, v in pairs(bucket) do rows[#rows + 1] = { k, v }; end
    table.sort(rows, function (a, b) if (a[2] ~= b[2]) then return a[2] > b[2]; end return a[1] < b[1]; end);
    local parts = {}; for i = 1, math.min(n, #rows) do parts[#parts + 1] = rows[i][1] .. '=' .. rows[i][2]; end
    print('  ' .. label .. ': ' .. table.concat(parts, ' | '));
end
top(absent_names, 40, 'top absent entity names');
top(duplicated_names, 25, 'top duplicated entity names');

if (run_claims) then
    print('');
    print(('%d claims passed, %d failed'):format(passes, failures));
    if (failures > 0) then os.exit(1); end
end

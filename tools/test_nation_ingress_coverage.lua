-- Data-backed regression for entrance selection into nation-mission targets.
--
-- WHAT THIS FILE IS ALLOWED TO CLAIM.
--
-- The shipped table data/ffxi-nav-destination-ingress.tsv records, per
-- (destination point, entrance edge), whether the native mesh could walk from
-- that entrance to that point. It is measured geometry, not live play. So the
-- only thing provable here is a CONSISTENCY property:
--
--   HARD CLAIM -- if any entrance into a target's zone is recorded
--   mesh-connected for that target, then modules/nav_destination_ingress.lua
--   must not select an entrance recorded mesh-no-path for it.
--
-- That is exactly the Horutoto failure shape: a mouth was chosen that cannot
-- reach the target while a mouth that can was available.
--
-- WHAT THIS FILE MUST NEVER CLAIM. That the missions are verified. Some
-- shipped pairs have no positive mesh result, and a mesh-no-path
-- pair is not proof a player cannot get there (scripted exits, doors and
-- transports are outside the mesh). Points with no positive evidence stay
-- UNKNOWN and are reported, never asserted about, never counted as passing.
--
-- Coverage of the table against the candidates the resolver can actually reach
-- is reported as a gap list, not a failure: Codex owns regenerating the data
-- after the export widens.
--
--   luajit tools/test_nation_ingress_coverage.lua
--   ACCESSXI_ADDON=<tree> luajit tools/test_nation_ingress_coverage.lua
--
-- Exit 1 only if a HARD CLAIM fails.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

WALKTHROUGH_EMBED = true;
local here = (arg[0]:match('^(.*)[/\\]') or '.');
local h = dofile(here .. '/test_mission_step_resolver.lua');
local resolver, make_ctx, name_key = h.resolver, h.make_ctx, h.name_key;
local zone_names, incoming_edges = h.zone_names, h.incoming_edges;
local zone_path, edge_rank = h.zone_path, h.edge_rank;
local progression_destinations = h.progression_destinations;

-- The runtime module under test. accessxi is already a table by now (the
-- resolver harness created it), so loading this registers the real callback
-- alongside M -- the same seam the addon uses.
local ingress = dofile(ADDON .. '/modules/nav_destination_ingress.lua');
local INGRESS_TSV = ADDON .. '/data/ffxi-nav-destination-ingress.tsv';
local index = ingress.load(INGRESS_TSV);

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1;
    else failures = failures + 1; print('  FAIL ' .. text); end
end

-- structural preconditions -------------------------------------------------
local point_count, row_count = 0, 0;
local status_counts = {};
for _, rows in pairs(index) do
    point_count = point_count + 1;
    for _, r in ipairs(rows) do
        row_count = row_count + 1;
        status_counts[r.status] = (status_counts[r.status] or 0) + 1;
    end
end
claim(row_count > 0, 'the shipped ingress table loaded at all (' .. INGRESS_TSV .. ')');
claim(type(ingress.select) == 'function', 'nav_destination_ingress exposes select()');
claim(type(accessxi.nav_destination_ingress) == 'function',
    'loading the module registers the runtime callback accessxi.nav_destination_ingress');

-- candidate enumeration, independent of tools/audit_nation_mission_routes.lua
local NATIONS = {
    { module = 'mission_quest_reconcile_mission_san_doria', nation = "San d'Oria", start_zone = 230 },
    { module = 'mission_quest_reconcile_mission_bastok',    nation = 'Bastok',     start_zone = 234 },
    { module = 'mission_quest_reconcile_mission_windurst',  nation = 'Windurst',   start_zone = 238 },
};
local zone_ids_by_graph_name = {};
for id, nm in pairs(zone_names) do
    local k = name_key(nm);
    if (k ~= '') then
        zone_ids_by_graph_name[k] = zone_ids_by_graph_name[k] or {};
        table.insert(zone_ids_by_graph_name[k], id);
    end
end

local function all_compact(module_name)
    local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. module_name .. '.lua');
    local map = {};
    if (ok and type(tbl) == 'table') then
        local root = type(tbl.objectives) == 'table' and tbl.objectives or tbl;
        for _, entry in pairs(root) do
            for _, a in ipairs(type(entry) == 'table' and entry.progression_actions or {}) do
                local id = tostring(a.step_id or '');
                if (id ~= '') then map[id] = map[id] or {}; table.insert(map[id], a); end
            end
        end
    end
    return map;
end

local candidates, cand_seen = {}, {};
local function note_candidate(point, step_id)
    if (tonumber(point.x) == nil or tonumber(point.z) == nil or tonumber(point.y) == nil) then return; end
    local key = ('%d\t%s\t%.3f\t%.3f\t%.3f'):format(
        point.zone, tostring(point.name or ''), point.x, point.z, point.y);
    local rec = cand_seen[key];
    if (rec == nil) then
        rec = { point = point, steps = {} };
        cand_seen[key] = rec; candidates[#candidates + 1] = rec;
    end
    rec.steps[step_id] = true;
end

for _, spec in ipairs(NATIONS) do
    local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. spec.module .. '.lua');
    if (ok and type(tbl) == 'table') then
        local dest_map = progression_destinations((spec.module:gsub('reconcile', 'progression')));
        local dest_fn = function (id) return dest_map[id] or 0; end
        local compact_map = all_compact((spec.module:gsub('reconcile', 'progression')));
        for native_key, entry in pairs(tbl) do
            if (type(entry) == 'table' and type(entry.steps) == 'table') then
                local zone = spec.start_zone;
                for i, step in ipairs(entry.steps) do
                    local step_id = tostring(step.stable_step_id or '');
                    local compact = compact_map[step_id] or {};
                    local ctx = make_ctx(zone, dest_fn, spec.nation, native_key);
                    local targets = resolver.resolve_step(entry.steps, i, ctx);
                    targets = type(targets) == 'table' and targets or {};
                    for _, t in ipairs(targets) do
                        if (name_key(t.source or '') ~= 'zone-travel' and tonumber(t.x)) then
                            note_candidate(t, step_id);
                        end
                    end
                    -- names from the step AND every compact action, in every
                    -- zone the guide names for the step
                    local zone_ids, names, seen = {}, {}, {};
                    local function add_zone(z) z = tonumber(z); if (z and z > 0) then zone_ids[z] = true; end end
                    local function add_named_zone(zn)
                        for _, z in ipairs(ctx.zone_ids_for_name(zn) or {}) do add_zone(z); end
                        for _, z in ipairs(zone_ids_by_graph_name[name_key(zn)] or {}) do add_zone(z); end
                    end
                    local function add_name(v)
                        v = tostring(v or '');
                        local k = name_key(v);
                        if (k ~= '' and not seen[k]) then seen[k] = true; names[#names + 1] = k; end
                    end
                    for _, zn in ipairs(step.zones or {}) do add_named_zone(zn); end
                    for _, v in ipairs(step.entities or {}) do add_name(v); end
                    for _, a in ipairs(compact) do
                        for _, zn in ipairs(type(a.zones) == 'table' and a.zones or {}) do add_named_zone(zn); end
                        add_zone(a.destination_zone_id or 0);
                        add_name(a.target);
                        for _, group in ipairs({ a.objects, a.npcs, a.enemies }) do
                            for _, v in ipairs(type(group) == 'table' and group or {}) do add_name(v); end
                        end
                    end
                    if (next(zone_ids) == nil) then add_zone(zone); end
                    for _, k in ipairs(names) do
                        for z in pairs(zone_ids) do
                            for _, p in ipairs(ctx.points_for_zone_entity(z, k) or {}) do note_candidate(p, step_id); end
                        end
                    end
                    if (#targets > 0 and tonumber(targets[1].zone)) then zone = tonumber(targets[1].zone); end
                end
            end
        end
    end
end

-- HARD CLAIM ---------------------------------------------------------------
local covered, uncovered, positive, no_positive, unknown_only = 0, {}, 0, 0, 0;
local by_zone_missing = {};

for _, rec in ipairs(candidates) do
    local point = rec.point;
    local rows = ingress.lookup(index, point);
    if (type(rows) ~= 'table' or #rows == 0) then
        uncovered[#uncovered + 1] = rec;
        by_zone_missing[point.zone] = (by_zone_missing[point.zone] or 0) + 1;
    else
        covered = covered + 1;
        local connected, has_unknown = {}, false;
        for _, r in ipairs(rows) do
            if (r.status == 'mesh-connected') then connected[#connected + 1] = r; end
            if (r.status == 'unknown') then has_unknown = true; end
        end
        if (#connected == 0) then
            -- No positive evidence. NOT a failure and NOT a pass: a mesh-no-path
            -- pair does not prove a player cannot get there.
            if (has_unknown) then unknown_only = unknown_only + 1; else no_positive = no_positive + 1; end
        else
            positive = positive + 1;
            -- Stand where a connected entrance comes from, so a chain exists.
            local from = tonumber(connected[1].from_zone) or 0;
            local ctx = {
                player_zone = from,
                incoming_edges = incoming_edges,
                zone_path = zone_path,
                edge_rank = edge_rank,
            };
            local edge = ingress.select(point, rows, ctx, nil);
            local ok_edge, why = false, 'select() returned no entrance';
            if (type(edge) == 'table') then
                for _, r in ipairs(rows) do
                    if (ingress.matches(r, edge)) then
                        ok_edge = (r.status == 'mesh-connected');
                        if (not ok_edge) then why = 'selected an entrance recorded ' .. tostring(r.status); end
                    end
                end
                if (edge ~= nil and not ok_edge and why:find('no entrance')) then
                    why = 'selected an entrance with no row in the table';
                end
            end
            claim(ok_edge, ('%s in %s: %s (from %s)'):format(
                tostring(point.name), tostring(zone_names[point.zone] or point.zone),
                why, tostring(zone_names[from] or from)));
        end
    end
end

-- Named regression: the reported Windurst 1 gate must select a connected mouth.
do
    local gate = { zone = 192, name = 'Gate: Magical Gizmo', x = 420.000, z = -30.375, y = -1.660 };
    local rows = ingress.lookup(index, gate);
    if (type(rows) == 'table' and #rows > 0) then
        local any_connected = false;
        for _, r in ipairs(rows) do if (r.status == 'mesh-connected') then any_connected = true; end end
        if (any_connected) then
            local edge = ingress.select(gate, rows,
                { player_zone = 115, incoming_edges = incoming_edges,
                  zone_path = zone_path, edge_rank = edge_rank }, nil);
            local status = 'no entrance selected';
            if (type(edge) == 'table') then
                for _, r in ipairs(rows) do if (ingress.matches(r, edge)) then status = r.status; end end
            end
            claim(status == 'mesh-connected',
                'Windurst 1 Gate: Magical Gizmo (420,-30.375,-1.660) from West Sarutabaruta selects a '
                    .. 'mesh-connected entrance, got: ' .. status);
        else
            print('  NOTE the Windurst 1 gate has no mesh-connected row; nothing asserted.');
        end
    else
        print('  NOTE the Windurst 1 gate is absent from the shipped table; nothing asserted.');
    end
end

-- report --------------------------------------------------------------------
print('');
print('nation ingress coverage');
print('-----------------------');
print(('  table points / rows            %d / %d'):format(point_count, row_count));
for _, k in ipairs({ 'mesh-connected', 'mesh-no-path', 'unknown' }) do
    print(('    %-16s           %d'):format(k, status_counts[k] or 0));
end
print(('  resolver candidates            %d'):format(#candidates));
print(('    present in table             %d'):format(covered));
print(('    ABSENT from table            %d'):format(#uncovered));
print(('  points with positive evidence  %d  (hard claims run)'):format(positive));
print(('  points with no positive row    %d  (UNKNOWN, nothing asserted)'):format(no_positive));
print(('  points with an unknown row     %d  (UNKNOWN, nothing asserted)'):format(unknown_only));
print('');
print('  NOT a live-verification result: mesh geometry only, no mission was played.');

if (#uncovered > 0) then
    print('');
    print('  candidates absent from the shipped table, by zone:');
    local zones = {};
    for z, n in pairs(by_zone_missing) do zones[#zones + 1] = { z, n }; end
    table.sort(zones, function (a, b) return a[2] > b[2]; end);
    for i, e in ipairs(zones) do
        if (i <= 15) then
            print(('    %-34s %d'):format(tostring(zone_names[e[1]] or e[1]) .. '(' .. e[1] .. ')', e[2]));
        end
    end
    print('  (Codex owns regenerating the table; these are not asserted failures.)');
end

print('');
print(('claims: %d passed, %d failed'):format(passes, failures));
if (failures > 0) then os.exit(1); end

-- Does zoning into the place the guide named actually finish the step?
--
-- Live 2026-08-22 it did not. The player was held on
-- "mission:Rhapsodies of Vana'diel:3:step-001" -- "Zone into any area
-- connecting to a Mog House in San d'Oria, Windurst, or Bastok" -- having
-- zoned into San d'Oria repeatedly. The completion test read
-- `action.destination_zone_id`, which that step carries as 0 because the guide
-- names ten zones and none of them survived extraction into a single field, so
-- it compared the zone entered against 0 and never matched. 1,563 of the 2,940
-- travel-shaped actions in the shipped progression modules -- 53.2% -- are
-- shaped that way.
--
-- Step-002 is the same bug wearing a different hat, and it is the one the
-- player would have hit next: "zone into Mhaura or Selbina", with
-- `destination_zone_id = 249` (Mhaura). Walking into Selbina, which the guide
-- expressly permits, matched nothing.
--
-- Driven against the REAL navigation module, the REAL shipped RoV progression
-- module and the REAL zone-line graph.
--
--   luajit tools/test_objective_travel_completion.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

accessxi = { mission_quest_objectives = { missions = {}, quests = {} } };
T = function (t)
    t = t or {};
    t.len = function (s) return #s end;
    t.append = function (s, v) s[#s + 1] = v end;
    t.clear = function (s) for i = #s, 1, -1 do s[i] = nil end end;
    return t;
end;
string.fmt = string.format;
log_line = function () end
speak = function () end
tick = function () return 0; end

local claims, failed = 0, 0;
local function claim(ok, text)
    claims = claims + 1;
    print((ok and '  ok   %s' or '  FAIL %s'):format(text));
    if (not ok) then failed = failed + 1; end
end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end

-- real zone names, so "Selbina" resolves the way the addon resolves it --------
local points = T{};
do
    local seen = {};
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv', 'r'));
    local header = nil;
    for line in f:lines() do
        if (line ~= '' and line:sub(1, 1) ~= '#') then
            local p = {};
            for part in (line .. '\t'):gmatch('([^\t]*)\t') do p[#p + 1] = part; end
            if (header == nil) then
                header = p;
            else
                for _, pair in ipairs({ { tonumber(p[2]), trim(p[3]) }, { tonumber(p[8]), trim(p[9]) } }) do
                    local zone, name = pair[1], pair[2];
                    if ((zone or 0) > 0 and name ~= '' and not seen[zone]) then
                        seen[zone] = true;
                        points:append(T{
                            zone = zone, zone_name = name, name = name,
                            x = 0, z = 0, y = 0, kind = 'zone', source = 'zoneline',
                            confidence = '', section = '', destination_id = '',
                            raw_identity = '', raw_spawn_ids = T{}, cluster_policy_version = '',
                        });
                    end
                end
            end
        end
    end
    f:close();
end
accessxi.nav_points = points;
accessxi.nav_catalog_revision = 1;
accessxi.nav_graph_zone_name = function (zone) return ('zone%d'):format(tonumber(zone) or 0); end
accessxi.current_zone_id = function () return 230; end
accessxi.current_player_identity = function () return 'testchar:1'; end
accessxi.current_player_world_id = function () return 1; end
accessxi.current_objective_session_epoch = function () return 7; end

-- the real shipped guide ------------------------------------------------------
local NATIVE = "mission:Rhapsodies of Vana'diel:3";
local progression = dofile(ADDON .. '/modules/mission_quest_progression_mission_rhapsodies_of_vanadiel.lua');
local record = progression.objectives[NATIVE];
assert(type(record) == 'table', 'shipped progression module is missing ' .. NATIVE);
local rows = record.progression_actions;
accessxi.mission_quest_guide_index = {
    [NATIVE] = {
        kind = 'mission', context = "Rhapsodies of Vana'diel", native_id = 3, progress_id = 2,
        title = "Rhapsodies of Vana'diel", status = 'guide',
        progression_schema_version = 2,
        progression_revision = record.progression_revision,
    },
};
accessxi.objective_guides = {
    progression_actions = function (_, key) return key == NATIVE and rows or {}; end,
    objective_destinations = function () return {}; end,
    source_route_steps = function () return {}; end,
};

local function action_for(step_id)
    for _, row in ipairs(rows) do
        if (trim(row.step_id) == step_id) then return row; end
    end
    return nil;
end

local STEP1 = NATIVE .. ':step-001';
local STEP2 = NATIVE .. ':step-002';
local one, two = action_for(STEP1), action_for(STEP2);

claim(one ~= nil and trim(one.action) == 'travel'
    and (tonumber(one.destination_zone_id) or 0) == 0 and #(one.zones or {}) == 0,
    'step-001 ships with NO destination id and NO zone names -- the shape that could never complete');
claim(two ~= nil and (tonumber(two.destination_zone_id) or 0) == 249
    and #(two.zones or {}) == 2,
    'step-002 names two zones but carries only one id -- Mhaura, not Selbina');

dofile(ADDON .. '/modules/mission_quest_step_resolver.lua');
local ok_load, load_err = pcall(dofile, ADDON .. '/modules/mission_quest_navigation.lua');
claim(ok_load, 'the real navigation module loads' .. (ok_load and '' or (': ' .. tostring(load_err))));

local SELBINA, MHAURA, SANDY_S = 248, 249, 230;

-- "Mhaura or Selbina" means either -------------------------------------------
local accepted = accessxi.nav_objective_travel_destination_zones(NATIVE, two);
claim(accepted[MHAURA] == true, 'zoning into Mhaura satisfies "zone into Mhaura or Selbina"');
claim(accepted[SELBINA] == true,
    'and so does Selbina -- the zone the guide named that extraction dropped');
claim(accepted[SANDY_S] ~= true,
    'while a zone the step never named does not satisfy it');

-- the router's answer survives the zone change that completes the step --------
local before = accessxi.nav_objective_travel_destination_zones(NATIVE, one);
claim(next(before) == nil,
    'step-001 has nothing to match on from its own fields alone');
accessxi.nav_objective_travel_zones = {
    [NATIVE] = {
        [STEP1] = {
            zones = { [230] = true, [231] = true, [232] = true, [234] = true },
            revision = record.progression_revision,
        },
    },
};
local after = accessxi.nav_objective_travel_destination_zones(NATIVE, one);
claim(after[SANDY_S] == true,
    'but the destinations the router resolved while travelling do satisfy it');
claim(after[234] == true, 'including every city it offered, not just the first');
claim(after[SELBINA] ~= true, 'and nowhere it did not offer');

-- a stale record must not complete anything ----------------------------------
accessxi.nav_objective_travel_zones[NATIVE][STEP1].revision = 'a-different-revision';
local stale = accessxi.nav_objective_travel_destination_zones(NATIVE, one);
claim(next(stale) == nil,
    'a record from a different guide revision is discarded, never trusted');

print('');
print(('claims=%d failed=%d'):format(claims, failed));
os.exit(failed == 0 and 0 or 1);

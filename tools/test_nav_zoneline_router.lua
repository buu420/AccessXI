-- Which road the cross-zone router chooses, tested against the SHIPPED
-- zone-line graph (data/ffxi-nav-zoneline-graph.tsv), not a hand-made one.
--
--   luajit tools/test_nav_zoneline_router.lua
--
-- The live fault of 2026-08-22: The Davoi Report step-009 says "Make your way
-- to Davoi. To reach Davoi, zone into Jugner Forest from La Theine Plateau at
-- (M-8)". Two chains of four edges exist from Southern San d'Oria; edge count
-- alone made them equal and the tie fell to graph order, so a blind level-14
-- player was routed through King Ranperre's Tomb, an undead dungeon.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;
log_line = function () end;

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1; print('  ok  ' .. text);
    else failures = failures + 1; print('  FAIL ' .. text); end
end

local ok_load, err = pcall(dofile, ADDON .. '/modules/nav_zoneline_router.lua');
if (not ok_load) then
    print('  FAIL nav_zoneline_router failed to load: ' .. tostring(err));
    os.exit(1);
end

-- Load the real graph.
local out_edges, zone_name = {}, {};
local f = assert(io.open(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv', 'r'));
local rows = 0;
for line in f:lines() do
    local col = {};
    for field in (line .. '\t'):gmatch('([^\t]*)\t') do col[#col + 1] = field; end
    local id = tonumber(col[1]);
    local from_zone, to_zone = tonumber(col[2]), tonumber(col[8]);
    if (id ~= nil and from_zone ~= nil and to_zone ~= nil) then
        rows = rows + 1;
        zone_name[from_zone] = col[3];
        zone_name[to_zone] = col[9];
        out_edges[from_zone] = out_edges[from_zone] or {};
        table.insert(out_edges[from_zone], {
            id = id, from_zone = from_zone, to_zone = to_zone,
            from_name = col[3], to_name = col[9] });
    end
end
f:close();
accessxi.nav_zoneline_out_edges = function (zone) return out_edges[zone] or {}; end;
print(('Loaded %d zone-line edges from the shipped graph.'):format(rows));

local SOUTHERN_SAN_DORIA, DAVOI = 230, 149;
local LA_THEINE, JUGNER, WEST_RONFAURE = 102, 104, 100;
local KING_RANPERRES_TOMB, EAST_RONFAURE = 190, 101;

local function describe(path)
    if (path == nil or path:len() == 0) then return '(none)'; end
    local parts = { zone_name[tonumber(path[1].from_zone)] or '?' };
    for _, e in ipairs(path) do
        parts[#parts + 1] = zone_name[tonumber(e.to_zone)] or ('zone ' .. tostring(e.to_zone));
    end
    return table.concat(parts, ' -> ');
end

local function visits(path, zone)
    if (path == nil) then return false; end
    for _, e in ipairs(path) do
        if ((tonumber(e.to_zone) or 0) == zone) then return true; end
    end
    return false;
end

print('The Davoi Report, step-009, from Southern San d\'Oria:');

local shortest = accessxi.nav_zoneline_shortest_path(SOUTHERN_SAN_DORIA, DAVOI);
claim(shortest:len() > 0, ('a chain to Davoi exists at all (%d edges: %s)'):format(shortest:len(), describe(shortest)));

-- The guide's own words for this step.
local via = { DAVOI, JUGNER, LA_THEINE };
local preferred = accessxi.nav_zoneline_preferred_set(via, SOUTHERN_SAN_DORIA, DAVOI);
claim(preferred ~= nil, 'the guide names via-zones worth scoring');
claim(preferred ~= nil and preferred[DAVOI] == nil,
    'the destination itself does not score as a via-zone (sol, ruling D)');
claim(preferred ~= nil and preferred[LA_THEINE] and preferred[JUGNER],
    'La Theine Plateau and Jugner Forest do score');

local guided, unnamed = accessxi.nav_zoneline_preferred_path(
    SOUTHERN_SAN_DORIA, DAVOI, preferred, shortest:len() + 2);
claim(guided ~= nil, 'a guide-preferring chain is found');
if (guided ~= nil) then
    print('       chosen: ' .. describe(guided));
    claim(visits(guided, LA_THEINE), 'the chosen road goes through La Theine Plateau, as the guide says');
    claim(visits(guided, JUGNER), 'the chosen road goes through Jugner Forest, as the guide says');
    claim(not visits(guided, KING_RANPERRES_TOMB),
        'the chosen road does NOT go through King Ranperre\'s Tomb');
    claim(visits(guided, WEST_RONFAURE),
        'the chosen road may still use West Ronfaure, an UNNAMED connector (sol, ruling D)');
    claim(guided:len() <= shortest:len() + 1,
        ('the chosen road is at most one edge longer than the shortest (%d vs %d)'):format(
            guided:len(), shortest:len()));
    claim((tonumber(guided[guided:len()].to_zone) or 0) == DAVOI,
        'the chosen road actually ends in Davoi');
    claim(unnamed == 1,
        ('exactly ONE zone the guide never named is used, and only because it is'
         .. ' unavoidable (%d)'):format(unnamed));
    claim(not visits(guided, EAST_RONFAURE),
        'East Ronfaure -- the other unnamed connector -- is not used either');

    -- The road the player was actually sent down, scored the same way.
    local tomb_road = { EAST_RONFAURE, KING_RANPERRES_TOMB, JUGNER, DAVOI };
    local tomb_unnamed = 0;
    for _, z in ipairs(tomb_road) do
        if (z ~= DAVOI and not preferred[z]) then tomb_unnamed = tomb_unnamed + 1; end
    end
    claim(tomb_unnamed > unnamed,
        ('the tomb road uses more unnamed zones (%d) and therefore loses, whatever'
         .. ' the edge counts'):format(tomb_unnamed));
end

print('Honest fallback when the guide names an impossible road:');
local impossible = accessxi.nav_zoneline_preferred_set({ 284 }, SOUTHERN_SAN_DORIA, DAVOI);
local fallback = accessxi.nav_zoneline_preferred_path(
    SOUTHERN_SAN_DORIA, DAVOI, impossible, shortest:len() + 2);
claim(fallback ~= nil and (tonumber(fallback[fallback:len()].to_zone) or 0) == DAVOI,
    'an unreachable named zone still yields a real chain to the destination');
claim(fallback == nil or fallback:len() <= shortest:len() + 2,
    'and does not wander further than the length bound');

print('No preference named:');
claim(accessxi.nav_zoneline_preferred_set(nil, SOUTHERN_SAN_DORIA, DAVOI) == nil,
    'no via-zones means no preference, so the plain shortest path is used');
claim(accessxi.nav_zoneline_preferred_set({ SOUTHERN_SAN_DORIA, DAVOI }, SOUTHERN_SAN_DORIA, DAVOI) == nil,
    'a step naming only where you are and where you are going scores nothing');

print('Determinism:');
local again = accessxi.nav_zoneline_preferred_path(
    SOUTHERN_SAN_DORIA, DAVOI, preferred, shortest:len() + 2);
claim(guided ~= nil and again ~= nil and describe(guided) == describe(again),
    'the same question gives the same road twice');

print(('%d claims passed, %d failed'):format(passes, failures));
os.exit(failures == 0 and 0 or 1);

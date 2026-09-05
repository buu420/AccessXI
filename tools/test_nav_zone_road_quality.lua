-- A TOMB IS NOT A ROAD.
--
-- Live 2026-08-24, The Davoi Report: from East Ronfaure the player was routed to
-- Davoi through King Ranperre's Tomb and was standing at its zone line when they
-- said it was leading them the wrong way. The chain search counted edges, and
-- the tomb route is one zone shorter than the field route, so it won.
--
-- Drives the REAL router over the REAL shipped zoneline graph.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
package.path = ADDON .. '/modules/?.lua;' .. package.path;
string.fmt = string.format;
local Tmt = {}; Tmt.__index = {
    append = function (s, v) s[#s + 1] = v; return s; end,
    len = function (s) return #s; end,
    each = function (s, f) for i, v in ipairs(s) do f(v, i); end end,
};
_G.T = function (t) return setmetatable(t or {}, Tmt); end
_G.accessxi = {};

local out_edges, names = {}, {};
local header = true;
for line in io.lines(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv') do
    if (header) then header = false; else
        local f = {};
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = field; end
        local from_zone, to_zone = tonumber(f[2]), tonumber(f[8]);
        if (from_zone ~= nil and to_zone ~= nil and from_zone > 0 and to_zone > 0) then
            names[from_zone] = f[3]; names[to_zone] = f[9];
            out_edges[from_zone] = out_edges[from_zone] or {};
            table.insert(out_edges[from_zone], { to_zone = to_zone, from_zone = from_zone });
        end
    end
end
function accessxi.nav_zoneline_out_edges(zone) return out_edges[zone] or {}; end

dofile(ADDON .. '/modules/nav_zoneline_router.lua');

local passed, failed = 0, 0;
local function claim(ok, what)
    if (ok) then passed = passed + 1;
    else failed = failed + 1; io.write(('  FAIL  %s\n'):format(what)); end
end

local function chain(from, to)
    local path = accessxi.nav_zoneline_shortest_path(from, to);
    local zones = { from };
    for _, e in ipairs(path) do zones[#zones + 1] = e.to_zone; end
    return zones, #path;
end

local function passes_through(zones, zone_id)
    for i = 2, #zones - 1 do
        if (zones[i] == zone_id) then return true; end
    end
    return false;
end

local types = require('nav_zone_types');
claim(tonumber(types[190]) == 4, "King Ranperre's Tomb is typed as a dungeon");
claim(tonumber(types[166]) == 4, 'Ranguemont Pass is typed as a dungeon');
claim(tonumber(types[102]) == 2, 'La Theine Plateau is typed as outdoors');
claim(tonumber(types[104]) == 2, 'Jugner Forest is typed as outdoors');
claim(tonumber(types[149]) == 4, 'Davoi is a dungeon -- and is still a legal destination');

-- The live bug.
local davoi_zones, davoi_len = chain(101, 149);
claim(not passes_through(davoi_zones, 190),
    'East Ronfaure to Davoi does not transit King Ranperre\'s Tomb');
claim(passes_through(davoi_zones, 102),
    'East Ronfaure to Davoi goes overland through La Theine Plateau');
claim(davoi_len == 4, ('East Ronfaure to Davoi is the four-zone field chain (got %d)'):format(davoi_len));

-- Already inside the tomb: do NOT walk back out the long way.
local from_tomb, tomb_len = chain(190, 149);
claim(tomb_len == 2, ('from inside the tomb Davoi is still two zones (got %d)'):format(tomb_len));

-- A dungeon that IS the destination is never penalised.
local _, to_tomb = chain(101, 190);
claim(to_tomb == 1, ('East Ronfaure to King Ranperre\'s Tomb stays one zone (got %d)'):format(to_tomb));

-- Ordinary field routes are untouched.
local _, field = chain(100, 102);
claim(field == 1, ('West Ronfaure to La Theine stays one zone (got %d)'):format(field));
local _, dunes = chain(102, 103);
claim(dunes == 1, ('La Theine to Valkurm Dunes stays one zone (got %d)'):format(dunes));

-- Nation capital out to a field target still crosses no dungeon.
local sandy_zones = chain(230, 149);
claim(not passes_through(sandy_zones, 190),
    'Southern San d\'Oria to Davoi avoids the tomb too');

io.write(('\n%d claims passed, %d failed\n'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

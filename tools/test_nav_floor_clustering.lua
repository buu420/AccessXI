-- A DESTINATION ON ANOTHER FLOOR MUST BE SELECTABLE.
--
-- The navigation browse collapsed every same-named static destination in a zone
-- to ONE entry, and chose the survivor with nav_distance, which measures x and z
-- and never reads y. In Palborough Mines the two Elevator Levers sit at the SAME
-- x and z, 33 yalms apart in height -- upper refinery floor and lower. The upper
-- was always nearer to a measurement that cannot see height, so the lever that
-- takes you DOWN was silently dropped and could not be chosen at all. Live
-- 2026-08-26 the player had to find it themselves; the two Refiner Levers, 16
-- yalms apart, collapsed the same way.
--
-- Drives the REAL accessxi.nav_cluster_static_points_by_height, lifted verbatim
-- out of the deployed accessxi_reader.lua, against the REAL shipped catalogue.
-- Only nav_point_source_rank is stubbed, and it is not the thing under test.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');

-- Lift a top-level function out of the deployed source by name. Its terminating
-- `end` is the first one at column zero after the header.
local function lift(header)
    local from = reader:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = reader:find('\nend\n', from, true);
    if (to == nil) then return nil; end
    return reader:sub(from, to + 4);
end

local cluster_src = lift('function accessxi.nav_cluster_static_points_by_height(points)');
local better_src = lift('accessxi.nav_static_destination_is_better = function (point, previous)');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

claim(cluster_src ~= nil, 'the clustering function is present in the deployed reader');
claim(better_src ~= nil, 'and so is the tiebreak it calls');
if (cluster_src == nil or better_src == nil) then
    print('override floor clustering: 0 passed, 2 failed'); os.exit(1);
end

-- The one dependency, stubbed: source preference, not height logic.
_G.nav_point_source_rank = function (point)
    return (tostring(point.source or ''):find('lsb', 1, true) ~= nil) and 1 or 2;
end
assert(load(better_src, 'better'))();
assert(load(cluster_src, 'cluster'))();
claim(type(accessxi.nav_cluster_static_points_by_height) == 'function',
    'the real clustering function loaded');

-- Real catalogue rows: zone, name, x, z, y, kind, source, ...
local by_key = {};
for line in io.lines(ADDON .. '/data/ffxi-nav-destinations.tsv') do
    if (line:sub(1, 1) ~= '#') then
        local f = {};
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = field; end
        local zone = tonumber(f[1]);
        local y = tonumber(f[5]);
        if (zone ~= nil and y ~= nil and f[6] ~= nil
            and f[6] ~= 'enemy' and f[6] ~= 'live-nm') then
            local key = ('%d:%s:%s'):format(zone, f[6], tostring(f[2]):lower());
            by_key[key] = by_key[key] or {};
            table.insert(by_key[key], {
                zone = zone, name = f[2], x = tonumber(f[3]), z = tonumber(f[4]),
                y = y, kind = f[6], source = f[7], distance = 0,
                -- Column 11 is the exact transition identity, and without it
                -- the supersede rule cannot fire -- the first run of this test
                -- silently skipped that half of the behaviour.
                raw_identity = f[11] or '',
            });
        end
    end
end

local function entries(key)
    return accessxi.nav_cluster_static_points_by_height(by_key[key] or {});
end
local function heights(list)
    local out = {};
    for _, p in ipairs(list) do out[#out + 1] = ('%.1f'):format(p.y); end
    table.sort(out);
    return table.concat(out, ', ');
end

-- 1. THE REGRESSION ITSELF. Palborough Mines, zone 143.
local elevator = entries('143:npc:elevator lever');
claim(#(by_key['143:npc:elevator lever'] or {}) == 2,
    'the catalogue really does ship two Elevator Levers, got '
    .. #(by_key['143:npc:elevator lever'] or {}));
claim(#elevator == 2,
    'both Elevator Levers survive clustering -- this is the lever that goes DOWN, got '
    .. #elevator .. ' at ' .. heights(elevator));

local refiner = entries('143:npc:refiner lever');
claim(#refiner == 2,
    'both Refiner Levers survive, 16 yalms apart, got ' .. #refiner .. ' at ' .. heights(refiner));

-- 2. AND THE CROWD STAYS TOGETHER. The two Dock Levers are 0.64 yalms apart in
--    height on ONE floor; a fixed 6-yalm band split them across an edge, which
--    is why this clusters on gaps instead.
local dock = entries('143:npc:dock lever');
claim(#(by_key['143:npc:dock lever'] or {}) == 2, 'the catalogue ships two Dock Levers');
claim(#dock == 1,
    'the two Dock Levers on one floor stay a single entry, got ' .. #dock .. ' at ' .. heights(dock));

-- 3. A scatter of interchangeable objects on one floor must not explode the menu.
local worst_name, worst_count, worst_rows = '', 0, 0;
for key, list in pairs(by_key) do
    if (#list >= 8) then
        local n = #accessxi.nav_cluster_static_points_by_height(list);
        if (n > worst_count) then worst_name, worst_count, worst_rows = key, n, #list; end
    end
end
claim(worst_count > 0, 'the catalogue has crowded names to cluster, worst=' .. worst_name);
claim(worst_count <= 20,
    'no single name explodes into a huge menu, worst is ' .. worst_name
    .. ' at ' .. worst_count .. ' entries from ' .. worst_rows .. ' rows');

-- 4. Whole-catalogue budget. Splitting floors must cost entries, but modestly.
local before, after = 0, 0;
for _, list in pairs(by_key) do
    before = before + 1;
    after = after + #accessxi.nav_cluster_static_points_by_height(list);
end
claim(after > before, 'clustering does add entries, ' .. before .. ' -> ' .. after);
claim(after <= before * 1.25,
    'and it adds under 25 percent overall, ' .. before .. ' -> ' .. after
    .. (' (+%.1f%%)'):format(100.0 * (after - before) / before));

-- 5. Points identical in height never split, however many sources describe them.
local same = accessxi.nav_cluster_static_points_by_height({
    { y = 5.0, source = 'a', distance = 3 }, { y = 5.0, source = 'lsb', distance = 3 },
    { y = 5.0, source = 'c', distance = 9 },
});
claim(#same == 1, 'three sources describing one object give one entry, got ' .. #same);
claim(same[1].source == 'lsb', 'and the best-ranked source wins, got ' .. tostring(same[1].source));

-- 6. Single linkage, not fixed banding: a chain of small steps stays together
--    even when its ends are far apart, and a real gap always splits.
local chain = accessxi.nav_cluster_static_points_by_height({
    { y = 0 }, { y = 5 }, { y = 10 }, { y = 15 }, { y = 40 },
});
claim(#chain == 2,
    'a 5-yalm chain is one place and the 25-yalm gap starts another, got ' .. #chain);

local edge = accessxi.nav_cluster_static_points_by_height({ { y = 5.9 }, { y = 0.0 } });
claim(#edge == 1, 'points 5.9 apart merge regardless of where they sit, got ' .. #edge);
local split = accessxi.nav_cluster_static_points_by_height({ { y = 6.1 }, { y = 0.0 } });
claim(#split == 2, 'points 6.1 apart separate, got ' .. #split);

-- 7. The browse must actually consume the clustering, not merely define it.
claim(reader:find('for _, point in ipairs(accessxi.nav_cluster_static_points_by_height(bucket)) do', 1, true) ~= nil,
    'nav_collect_menu_items iterates the clusters');
claim(reader:find('bucket[#bucket + 1] = point;', 1, true) ~= nil,
    'and collects every candidate rather than only the survivor');

-- 8. WIDENING A MENU MUST NOT PROMOTE A ROW THAT WAS SUPPRESSED ON MERIT.
--
-- Port Jeuno ships two rows named "Qufim Island zone line": the real door,
-- carrying lsb:zonelines:880096890, and one with seven fields, no identity and
-- coordinates a hundred yalms away. The ranking had always hidden the impostor,
-- because an exact zoneline identity earns a bias. Splitting by height surfaced
-- it, and live 2026-08-27 the player was walked to it, told "You are on it",
-- and stood there until the zoning watch timed out.
local pair = accessxi.nav_cluster_static_points_by_height({
    { y = -4.999, x = -186.377, z = 2.297, source = 'bg-wiki-lsb-npc-list', distance = 5 },
    { y = 9.878, x = -157.114, z = 100.055, source = 'lsb-zoneline-all',
      raw_identity = 'lsb:zonelines:880096890', distance = 90 },
});
claim(#pair == 1, 'the unidentified namesake is superseded, got ' .. #pair);
claim(pair[1] ~= nil and tostring(pair[1].raw_identity or '') == 'lsb:zonelines:880096890',
    'and the surviving row is the identified door');

-- A scripted trigger counts as identified too -- that is how the Chateau exit
-- the player walked is represented.
local scripted = accessxi.nav_cluster_static_points_by_height({
    { y = 0, source = 'guess', distance = 1 },
    { y = 40, source = 'lsb', raw_identity = 'lsb:scripted_trigger:569', distance = 9 },
});
claim(#scripted == 1 and tostring(scripted[1].raw_identity):find('scripted_trigger', 1, true) ~= nil,
    'a scripted trigger supersedes an unidentified namesake too, got ' .. #scripted);

-- TWO IDENTIFIED DOORS ON DIFFERENT FLOORS ARE STILL TWO DOORS. The supersede
-- rule must not undo the floor split it sits in front of.
local two_doors = accessxi.nav_cluster_static_points_by_height({
    { y = 0, source = 'lsb', raw_identity = 'lsb:zonelines:111', distance = 1 },
    { y = 40, source = 'lsb', raw_identity = 'lsb:zonelines:222', distance = 9 },
});
claim(#two_doors == 2,
    'two identified doors 40 yalms apart stay separate, got ' .. #two_doors);

-- And where nothing is identified, height clustering is untouched.
local neither = accessxi.nav_cluster_static_points_by_height({
    { y = 0, source = 'a', distance = 1 }, { y = 40, source = 'b', distance = 9 },
});
claim(#neither == 2, 'unidentified rows still split by floor, got ' .. #neither);

-- 9. The real catalogue: the Qufim pair really is the shape described.
local qufim = by_key['246:area:qufim island zone line'];
claim(qufim ~= nil and #qufim == 2,
    'Port Jeuno really does ship two Qufim zone-line rows, got '
    .. tostring(qufim and #qufim));
if (qufim ~= nil) then
    local resolved = accessxi.nav_cluster_static_points_by_height(qufim);
    claim(#resolved == 1, 'and only one survives, got ' .. #resolved);
end

print(('nav floor clustering: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

-- PROMYVION-HOLLA MUST BE NAVIGABLE BY EAR.
--
-- Live 2026-08-29 the player entered Promyvion-Holla and said "this zone needs
-- work". The destination list read back to them:
--
--   nav menu move warp 07. 6 of 20. npc. Confidence untested.
--   nav menu move kiokudama c. 9 of 20. npc. Confidence untested.
--
-- Two problems, and the second is worse than the names.
--
-- 1. Every source calls warp_01..11 a MEMORY STREAM: BG Wiki, FFXIclopedia,
--    Square Enix's 2004 patch notes ('the length of time the "Memory Stream"
--    remains active'), and LandSandBoat's own code -- MEMORY_STREAM_OFFSET, and
--    a comment on every row reading 'Associated "Memory stream" NPC ID'. The
--    numbers are not arbitrary: LSB's Zone.lua registers each with a floor and a
--    compass bearing, matching npc_list coordinates to under 0.09 yalms.
--
-- 2. THE EXIT WAS NOT IN THE CATALOGUE. Zone 16 shipped exactly one `area` row,
--    the Spire zone line. The way out and the four portals back down a floor are
--    cylindrical trigger areas in Zone.lua with NO entity behind them, so
--    nothing reading npc_list or zonelines could ever see them. The blocked
--    beacon aims at 11:58:56 sit at (83.9, 89.1) -- 9.7 yalms from the exit
--    trigger at (80, 80). The player was standing on the way out unable to ask
--    for it.
--
--   luajit tools/test_promyvion_holla_catalogue.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end

local rows, malformed = {}, 0;
for line in io.lines(ADDON .. '/data/ffxi-nav-destinations.tsv') do
    if (line:sub(1, 1) ~= '#' and line:match('%S')) then
        local c = {};
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do c[#c + 1] = field; end
        if (c[1] == '16') then
            if (#c < 8) then malformed = malformed + 1; end
            rows[#rows + 1] = {
                name = c[2], x = tonumber(c[3]), z = tonumber(c[4]), y = tonumber(c[5]),
                kind = c[6], source = c[7], confidence = c[8],
            };
        end
    end
end
claim(#rows > 80, 'zone 16 rows load, got ' .. #rows);
claim(malformed == 0, 'and every one has its full column set, malformed=' .. malformed);

local function find(name)
    for _, r in ipairs(rows) do if (r.name == name) then return r; end end
    return nil;
end
local function count(pattern)
    local n = 0;
    for _, r in ipairs(rows) do if (r.name:find(pattern)) then n = n + 1; end end
    return n;
end

-- ---------------------------------------------------------------------------
-- 1. NO INTERNAL NAMES LEFT. A blind player cannot navigate by "warp 07".
-- ---------------------------------------------------------------------------
claim(count('^warp %d') == 0, 'no "warp NN" row survives, got ' .. count('^warp %d'));
claim(count('^Memory Stream') == 11,
    'and all eleven are Memory Streams, got ' .. count('^Memory Stream'));

-- The floor and bearing come from LSB's own Zone.lua labels, so a player can
-- tell one from another rather than hearing eleven identical names.
claim(find('Memory Stream (floor 1)') ~= nil, 'the floor 1 stream is named');
claim(find('Memory Stream (floor 2 northeast, leads west)') ~= nil,
    'and a floor 2 stream carries its bearing and destination');
claim(count('floor 3 west') == 3, 'three streams on floor 3 west, got ' .. count('floor 3 west'));
claim(count('floor 3 east') == 3, 'three on floor 3 east, got ' .. count('floor 3 east'));
-- Anchored to Memory Stream: 'floor 2' alone also matches the two
-- 'Portal down to floor 2' returns, which is what this first caught.
claim(count('^Memory Stream %(floor 2') == 4,
    'four streams on floor 2, got ' .. count('^Memory Stream %(floor 2'));

-- ---------------------------------------------------------------------------
-- 2. THE WAY OUT. The whole point -- a player must be able to ask for it.
-- ---------------------------------------------------------------------------
local exit_row = find('Exit to Hall of Transference');
claim(exit_row ~= nil, 'the zone exit is in the catalogue at all');
if (exit_row ~= nil) then
    claim(math.abs(exit_row.x - 80.0) < 0.01 and math.abs(exit_row.z - 80.0) < 0.01,
        'at the trigger centre Zone.lua registers, (80, 80)');
    -- Height from ground the player actually stood on: their logged position
    -- beside it was (81.656, 76.793, -1.000). Every catalogued entity in the
    -- zone sits between -0.50 and +0.04, so this is consistent, not invented.
    claim(math.abs(exit_row.y + 1.0) < 0.01,
        'with the height the player was standing at, y=' .. tostring(exit_row.y));
    claim(exit_row.kind == 'area', 'as an area -- it is a trigger volume, not an NPC');
    claim(exit_row.confidence == 'observed',
        'marked observed, because that height is walked evidence');
end

claim(count('^Portal down to floor') == 4,
    'and all four return portals are present, got ' .. count('^Portal down to floor'));
local back1 = find('Portal down to floor 1');
claim(back1 ~= nil and math.abs(back1.x + 120.0) < 0.01 and math.abs(back1.z - 0.0) < 0.01,
    'the floor 2 return sits at (-120, 0)');

-- They are marked untested on purpose: unlike the exit, no walked height backs
-- them. Claiming more than the evidence supports is how a blind player gets
-- walked at a floor that is not there.
for _, name in ipairs({ 'Portal down to floor 1', 'Portal down to floor 2 (west)',
                        'Portal down to floor 2 (east)', 'Portal down to floor 3' }) do
    local r = find(name);
    if (r == nil or r.confidence ~= 'untested') then
        claim(false, name .. ' is marked untested');
    end
end
claim(true, 'and the four unwalked returns claim only untested confidence');

-- ---------------------------------------------------------------------------
-- 3. NOTHING ELSE MOVED. The Spire zone line was the zone's only area row
--    before; it must still be there and unchanged.
-- ---------------------------------------------------------------------------
local spire = find('Spire of Holla zone line');
claim(spire ~= nil and spire.kind == 'area', 'the Spire zone line is untouched');
claim(spire ~= nil and math.abs(spire.x - 180.0) < 0.01,
    'at its original coordinates');
claim(count('^Memory Flux') >= 3, 'the Memory Flux rows are untouched, got ' .. count('^Memory Flux'));

print(('promyvion holla catalogue: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

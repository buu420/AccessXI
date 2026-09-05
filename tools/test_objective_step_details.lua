-- THE LINES UNDER THE LINE.
--
-- The guides are written as a TREE and stored as a flat list. Live 2026-08-27,
-- A Crystalline Prophecy mission 2, the player heard:
--
--   "Current instruction: Collect the following 3 items: Native mission orders:
--    The primordial crystal appeared over Jeuno..."
--
-- and nothing else. Three items, three zones, three mob families and three
-- nearby Survival Guides are all in our own data, in the rows beneath that
-- instruction, and not one word was spoken. The player: "it doesn't track the
-- mission, or the items. Where do I go, who do I talk to what do I get."
--
-- Drives the REAL reader against the REAL reconciled corpus.
local load = loadstring or load; -- Lua 5.1 compiles source strings with loadstring.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local src = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

local function lift(header)
    local from = src:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = src:find('\nend\n', from, true);
    return to and src:sub(from, to + 4) or nil;
end

_G.clean = function (v) return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', ''); end

-- The real steps, parsed out of the real reconciled module in file order.
local steps = {};
do
    local text = io.open(ADDON ..
        '/modules/mission_quest_reconcile_mission_a_crystalline_prophecy.lua'):read('*a');
    local from = text:find('"mission:A Crystalline Prophecy:2"', 1, true);
    local body = from and text:sub(from, from + 40000) or text;
    -- Collect the id positions first, then slice BETWEEN them. A gmatch that
    -- matches the next id as its terminator consumes it, so it reads every
    -- other step -- which is how the first run of this test picked up the
    -- depth-3 Survival Guide notes and skipped the Seedspall lines entirely.
    local ids, at = {}, 1;
    while true do
        local s, e, id = body:find('stable_step_id = "(mission:A Crystalline Prophecy:2:step%-%d+)"', at);
        if (s == nil) then break; end
        ids[#ids + 1] = { id = id, from = s, to = nil };
        if (#ids > 1) then ids[#ids - 1].to = s - 1; end
        at = e + 1;
    end
    if (#ids > 0) then ids[#ids].to = #body; end
    for _, entry in ipairs(ids) do
        local chunk = body:sub(entry.from, entry.to);
        steps[#steps + 1] = {
            stable_step_id = entry.id,
            action = chunk:match('action = "([^"]*)"') or '',
            primary_instruction = '',
            bg_instruction = chunk:match('bg_instruction = "([^"]*)"') or '',
            ffxiclopedia_instruction = chunk:match('ffxiclopedia_instruction = "([^"]*)"') or '',
        };
    end
end
claim(#steps >= 8, 'parsed the real reconciled steps, got ' .. #steps);
_G.objective_source_steps = function () return steps; end

-- Order matters: objective_step_detail_text delegates its sentence joining to
-- objective_detail_text_from_lines, so the joiner must exist first.
for _, header in ipairs({
    'function accessxi.objective_step_detail_lines(native_key, step_id)',
    'function accessxi.objective_detail_text_from_lines(lines)',
    'function accessxi.objective_step_detail_text(native_key, step_id)',
}) do
    local body = lift(header);
    claim(body ~= nil, 'lifted ' .. header:sub(1, 52));
    if (body ~= nil) then assert(load(body, 'detail'))(); end
end
claim(type(accessxi.objective_step_detail_text) == 'function', 'the real reader loaded');

-- 1. THE REGRESSION. The header step must yield the rows beneath it.
local text = accessxi.objective_step_detail_text(
    "mission:A Crystalline Prophecy:2", "mission:A Crystalline Prophecy:2:step-001");
claim(text ~= '', 'the collect header now carries detail, got "' .. text:sub(1, 60) .. '"');

-- WHAT DO I GET -- every item named.
for _, item in ipairs({ 'Seedspall Lux', 'Seedspall Luna', 'Seedspall Astrum' }) do
    claim(text:find(item, 1, true) ~= nil, 'names the item ' .. item);
end
-- WHERE DO I GO -- every zone, and the grid reference with it.
for _, place in ipairs({ 'Jugner Forest', 'Pashhow Marshlands', 'Meriphataud Mountains' }) do
    claim(text:find(place, 1, true) ~= nil, 'names the zone ' .. place);
end
for _, grid in ipairs({ 'G-11', 'K-10', 'K-8' }) do
    claim(text:find(grid, 1, true) ~= nil, 'names the grid reference ' .. grid);
end
-- WHO DO I TALK TO / KILL -- the mob families.
for _, who in ipairs({ 'Orcs', 'Quadavs', 'Yagudos' }) do
    claim(text:find(who, 1, true) ~= nil, 'names who drops it: ' .. who);
end
-- And the accessibility detail a sighted player would read anyway.
claim(text:find('Survival Guide', 1, true) ~= nil,
    'keeps the nearest Survival Guide lines');

-- 2. It stops at the next REAL step, so a step never swallows the mission.
claim(text:find('Qufim', 1, true) == nil,
    'the subtree stops before the next real step, got "' .. text .. '"');

-- 3. A step whose child is a locating note gets it. This is the ??? at G-6.
local trade = accessxi.objective_step_detail_text(
    "mission:A Crystalline Prophecy:2", "mission:A Crystalline Prophecy:2:step-012");
claim(trade:find('rock columns', 1, true) ~= nil,
    'the trade step carries "Mid-east section of (G-6), near 2 rock columns", got "'
    .. trade .. '"');

-- 4. A note step of its own yields nothing extra rather than repeating itself.
local note = accessxi.objective_step_detail_text(
    "mission:A Crystalline Prophecy:2", "mission:A Crystalline Prophecy:2:step-003");
claim(note:find('Seedspall Lux', 1, true) == nil,
    'a child does not re-read its own siblings above it');

-- 5. Unknown ids are quiet rather than throwing.
claim(accessxi.objective_step_detail_text('nope', 'nope') == '', 'an unknown step yields nothing');
claim(accessxi.objective_step_detail_text('nope', '') == '', 'an empty step id yields nothing');

-- 6. Every sentence is terminated, so a reader pauses between items instead of
--    running three lines together in one breath.
local _, dots = text:gsub('%.', '');
claim(dots >= 6, 'each detail ends a sentence, got ' .. dots .. ' full stops');

-- 7. THE DEAD-PATH GUARD. The caller must pass a field that is actually
--    assigned somewhere. The first version of this passed
--    item.objective_step_id, which is assigned NOWHERE, so the whole feature
--    was inert -- the exact failure this addon keeps hitting.
local call = src:find('accessxi.objective_step_detail_text(', 1, true);
claim(call ~= nil, 'the speech path calls the reader');
-- The identifying fields are read inside objective_step_supplement now. Each
-- must be ASSIGNED somewhere too: the first version of this feature read
-- item.objective_step_id, a field assigned nowhere, and was silently inert.
for _, name in ipairs({ 'objective_native_key', 'objective_guide_step_id' }) do
    local reads = 0;
    for _ in src:gmatch('item%.' .. name) do reads = reads + 1; end
    claim(reads > 0, 'the supplement reads item.' .. name);
    local assigns = 0;
    for _ in src:gmatch('%.' .. name .. '%s*=') do assigns = assigns + 1; end
    claim(assigns > 0,
        'and item.' .. name .. ' is assigned somewhere, not only read');
end

-- 8. EVERY SPEECH BRANCH MUST CARRY THE SUPPLEMENT.
--
-- The objective speech has several return paths. The item progress went into
-- the instruction-only branch alone, and every objective the player was
-- actually looking at came out of the candidate-choice branch -- so the line
-- never appeared once in 1.1M log lines. A feature wired into one branch
-- reaches only the players whose current step happens to take it.
claim(src:find('function accessxi.objective_step_supplement(item)', 1, true) ~= nil,
    'the supplement is one function, not repeated inline per branch');

-- Count the speech-building branches by their distinctive opening phrase, and
-- require each to call the supplement before it returns.
local branches = {
    { label = 'instruction-only', marker = "' Current instruction: '" },
    { label = 'candidate-choice', marker = "' Objective choice: '" },
};
for _, branch in ipairs(branches) do
    local at = src:find(branch.marker, 1, true);
    claim(at ~= nil, 'found the ' .. branch.label .. ' branch');
    if (at ~= nil) then
        -- The supplement must appear between this branch's phrase and its return.
        local stop = src:find('Press K to repeat instructions', at, true)
            or src:find('Press I to start navigation', at, true)
            or (at + 3000);
        local segment = src:sub(at, stop);
        claim(segment:find('accessxi.objective_step_supplement(item)', 1, true) ~= nil,
            'the ' .. branch.label .. ' branch calls the supplement before returning');
    end
end

local supplement_calls = 0;
for _ in src:gmatch('accessxi%.objective_step_supplement%(item%)') do
    supplement_calls = supplement_calls + 1;
end
claim(supplement_calls >= 3,
    'defined once and called from at least two branches, occurrences='
    .. supplement_calls);

-- And the supplement itself must reach both halves of what it promises.
local sup_at = src:find('function accessxi.objective_step_supplement(item)', 1, true);
local sup_end = sup_at and src:find('\nend\n', sup_at, true) or nil;
claim(sup_at ~= nil and sup_end ~= nil, 'the supplement is a complete function');
if (sup_at ~= nil and sup_end ~= nil) then
    local body = src:sub(sup_at, sup_end);
    claim(body:find('accessxi.objective_step_detail_lines', 1, true) ~= nil,
        'it gathers the lines under the step');
    claim(body:find('accessxi.objective_detail_text_from_lines', 1, true) ~= nil,
        'and joins them into sentences');
    claim(body:find('accessxi.objective_item_progress', 1, true) ~= nil,
        'and what the player already holds');
end

-- 9. A LOCATION FOR SOMETHING ALREADY CARRIED IS NOISE.
--
-- Player, 2026-08-27: "It still shows the armor locations, I figured they would
-- get removed when they showed in my inventory. same with the seeds."
local filter_src = lift('function accessxi.objective_detail_lines_without_held(lines, progress)');
local joiner_src = lift('function accessxi.objective_detail_text_from_lines(lines)');
claim(filter_src ~= nil, 'the held-line filter exists');
claim(joiner_src ~= nil, 'and the sentence joiner is reusable');
if (filter_src ~= nil) then assert(load(filter_src, 'filter'))(); end
if (joiner_src ~= nil) then assert(load(joiner_src, 'join'))(); end

local all = accessxi.objective_step_detail_lines(
    "mission:A Crystalline Prophecy:2", "mission:A Crystalline Prophecy:2:step-001");
claim(#all == 6, 'the collect step has six rows, got ' .. #all);

local kept, dropped = accessxi.objective_detail_lines_without_held(all, {
    held = { 'Seedspall Lux' },
    needed = { 'Seedspall Luna', 'Seedspall Astrum' }, unknown = {} });
claim(dropped == 2, 'holding one item drops its line AND its sub-note, got ' .. dropped);
local text2 = accessxi.objective_detail_text_from_lines(kept);
claim(text2:find('Seedspall Lux', 1, true) == nil,
    'the held item is no longer given directions');
claim(text2:find('Davoi', 1, true) == nil,
    'and its Survival Guide note leaves with it rather than being orphaned');
claim(text2:find('Seedspall Luna', 1, true) ~= nil
    and text2:find('Seedspall Astrum', 1, true) ~= nil,
    'while the two still needed keep theirs');

-- 10. NOTHING MAY BE HIDDEN ON A GUESS. An item we could not check keeps its
--     directions -- withholding a location because we were unsure is the exact
--     failure this addon exists to prevent.
local _, none = accessxi.objective_detail_lines_without_held(all, {
    held = {}, needed = {},
    unknown = { 'Seedspall Lux', 'Seedspall Luna', 'Seedspall Astrum' } });
claim(none == 0, 'an unreadable inventory hides nothing, got ' .. none);
_, none = accessxi.objective_detail_lines_without_held(all, nil);
claim(none == 0, 'and a missing progress result hides nothing');
_, none = accessxi.objective_detail_lines_without_held(all, { held = {}, needed = {}, unknown = {} });
claim(none == 0, 'nor does an empty result');

-- 11. Holding everything empties the directions but the progress line still
--     speaks, so the player is never left with silence.
local emptied;
emptied, dropped = accessxi.objective_detail_lines_without_held(all, {
    held = { 'Seedspall Lux', 'Seedspall Luna', 'Seedspall Astrum' },
    needed = {}, unknown = {} });
claim(#emptied == 0 and dropped == 6, 'holding all three drops every direction, got ' .. dropped);

-- 12. The supplement must apply the filter, not merely define it.
local sup = lift('function accessxi.objective_step_supplement(item)');
claim(sup ~= nil and sup:find('objective_detail_lines_without_held', 1, true) ~= nil,
    'the supplement filters before speaking');

-- 13. ONE LINE PER THING. The reconciled list interleaves BOTH wikis, so the
--     same item is described twice in different words -- "Seedspall Luna from
--     Quadavs in Pashhow Marshlands around (K-10)" and then "Seedspall Luna is
--     dropped by Quadav in Pashhow Marshlands". Live 2026-08-27 the player
--     heard every item twice.
local doubled = {
    'Seedspall Lux from Orcs in Jugner Forest around (G-11).',
    'Closest Survival Guide is Davoi.',
    'Seedspall Luna from Quadavs in Pashhow Marshlands around (K-10).',
    'Seedspall Lux is dropped by Orc in Jugner Forest.',
    'Seedspall Luna is dropped by Quadav in Pashhow Marshlands.',
};
local once, cut = accessxi.objective_detail_lines_without_held(doubled, {
    held = {}, needed = { 'Seedspall Lux', 'Seedspall Luna' }, unknown = {} });
claim(cut == 2, 'the second telling of each item is dropped, got ' .. cut);
local once_text = accessxi.objective_detail_text_from_lines(once);
claim(once_text:find('from Orcs in Jugner Forest', 1, true) ~= nil,
    'the first telling survives');
claim(once_text:find('is dropped by Orc in', 1, true) == nil,
    'and the repeat does not, got "' .. once_text .. '"');
claim(once_text:find('Davoi', 1, true) ~= nil,
    'a sub-note between them is not mistaken for a repeat');

-- A repeat of a HELD item is dropped once, not counted twice over.
local held_twice;
held_twice, cut = accessxi.objective_detail_lines_without_held(doubled, {
    held = { 'Seedspall Lux' }, needed = { 'Seedspall Luna' }, unknown = {} });
claim(cut == 4, 'held item, its note, its repeat and the repeat of the other all go, got ' .. cut);
claim(#held_twice == 1, 'leaving only the first telling of the item still needed, got ' .. #held_twice);

print(('objective step details: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

-- THE UNNAMED TARGET THE SCRAPER DROPPED.
--
-- FFXI marks many interaction points with a literal "???" rather than a name,
-- and the guides write them into prose. The corpus writes "the???" 746 times
-- against 271 correctly spaced, so an extractor splitting on word boundaries
-- swallowed the marker into the preceding word and kept only the zone.
--
-- Live 2026-08-27, A Crystalline Prophecy mission 2: the step reads "Trade the
-- 3 Seedspalls to the??? at (G-6) in Qufim Island for a cutscene." Its entities
-- are { "Qufim Island" } and nothing else, so the player -- standing in Qufim,
-- where there is exactly ONE catalogued ??? -- was told the step had no
-- destination and had to find it themselves.
--
-- Drives the REAL recovery helper, lifted from the deployed resolver, and
-- measures the gap it closes across the REAL shipped corpus.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.M = {};

local src = io.open(ADDON .. '/modules/mission_quest_step_resolver.lua'):read('*a');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

local from = src:find('function M.step_entities_with_unnamed(step)', 1, true);
claim(from ~= nil, 'the recovery helper exists in the deployed resolver');
local to = from and src:find('\nend\n', from, true) or nil;
claim(to ~= nil, 'and is a complete function');
if (from == nil or to == nil) then
    print('unnamed target recovery: 0 passed, 2 failed'); os.exit(1);
end

-- Its two dependencies, neither of which is the thing under test.
_G.clean = function (v) return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', ''); end
_G.list = function (v) return type(v) == 'table' and v or {}; end
assert(load(src:sub(from, to + 4), 'recovery'))();
claim(type(M.step_entities_with_unnamed) == 'function', 'the real helper loaded');

local function has(t, want)
    for _, v in ipairs(t) do if (v == want) then return true; end end
    return false;
end

-- 1. THE LIVE STEP. Exactly as the corpus ships it.
local live = {
    instruction = 'Trade the 3 Seedspalls to the??? at (G-6) in Qufim Island for a cutscene.',
    entities = { 'Qufim Island' },
    zones = { 'Qufim Island' },
    grid_coordinates = { 'G-6' },
};
local got = M.step_entities_with_unnamed(live);
claim(has(got, '???'), 'the missing-space "the???" is recovered as a target');
claim(has(got, 'Qufim Island'), 'and the zone the step already named is kept');
claim(#got == 2, 'with nothing else invented, got ' .. #got);

-- 2. A step that already names it is untouched -- no duplicate entry.
local already = { instruction = 'Examine the ??? in Qufim Island.', entities = { '???', 'Qufim Island' } };
local same = M.step_entities_with_unnamed(already);
claim(#same == 2, 'a step that already lists ??? is returned unchanged, got ' .. #same);

-- 3. A step with no marker gains nothing. This is the guard that stops the
--    recovery from attaching a target to every step in the game.
local plain = { instruction = 'Talk to Pius in the Metalworks.', entities = { 'Pius', 'Metalworks' } };
claim(#M.step_entities_with_unnamed(plain) == 2, 'a step with no ??? is untouched');
claim(not has(M.step_entities_with_unnamed(plain), '???'), 'and gains no phantom target');

-- 4. It reads every instruction field, because which one is populated varies.
for _, field in ipairs({ 'instruction', 'primary_instruction', 'bg_instruction',
                         'ffxiclopedia_instruction' }) do
    local step = { entities = { 'Somewhere' } };
    step[field] = 'Examine the??? there.';
    claim(has(M.step_entities_with_unnamed(step), '???'),
        'recovered from ' .. field);
end

-- 5. THE SCALE. Measure against the real shipped modules, so a future change to
--    the scraper that fixes this upstream shows up as this number collapsing.
-- A named set rather than a shell listing: io.popen('dir') hangs under LuaJIT
-- here, and a test that hangs is worse than no test at all.
local instruction_has, entities_lack = 0, 0;
local dir = ADDON .. '/modules/';
local files = {
    'mission_quest_bg_mission_a_crystalline_prophecy.lua',
    'mission_quest_bg_mission_a_shantotto_ascension.lua',
    'mission_quest_bg_mission_a_moogle_kupo_d_etat.lua',
    'mission_quest_bg_mission_san_doria.lua',
    'mission_quest_bg_mission_bastok.lua',
    'mission_quest_bg_mission_windurst.lua',
    'mission_quest_bg_mission_zilart.lua',
    'mission_quest_bg_mission_chains_of_promathia.lua',
    'mission_quest_bg_mission_assault.lua',
    'mission_quest_bg_quest_jeuno.lua',
};
local present = 0;
for _, name in ipairs(files) do
    local fh = io.open(dir .. name, 'r');
    if (fh ~= nil) then present = present + 1; fh:close(); end
end
claim(present >= 5, 'the sampled guide modules are present, got ' .. present);
for _, name in ipairs(files) do
    local fh = io.open(dir .. name, 'r');
    if (fh ~= nil) then
        local text = fh:read('*a'); fh:close();
        for instruction, between, ents in text:gmatch(
            'instruction = "([^"]*)",(.-)entities = {([^}]*)}') do
            if (instruction:find('???', 1, true) and not between:find('instruction = "', 1, true)) then
                instruction_has = instruction_has + 1;
                if (not ents:find('???', 1, true)) then
                    entities_lack = entities_lack + 1;
                end
            end
        end
    end
end
claim(instruction_has > 40,
    'the corpus really does name ??? in many steps, got ' .. instruction_has);
claim(entities_lack > 20,
    'and most of them lost it -- this is the gap being closed, got '
    .. entities_lack .. ' of ' .. instruction_has);
print(('   corpus: %d steps name ???, %d lost it from entities (%.0f%%)'):format(
    instruction_has, entities_lack, 100.0 * entities_lack / math.max(1, instruction_has)));

-- 6. The caller must actually use it.
claim(src:find('for _, value in ipairs(M.step_entities_with_unnamed(step)) do', 1, true) ~= nil,
    'the entity loop calls the recovery rather than reading step.entities raw');

print(('unnamed target recovery: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

-- A LANDMARK YOU ARE TOLD SOMETHING IS NEAR IS NOT WHERE YOU ARE GOING.
--
-- "Examine the Undulating Confluence at (G-8) in Qufim Island. It's close to
-- the Qufim Home Point." The extractor took "Home Point" from that second
-- sentence and it became a second destination, so At the Heavens' Door appeared
-- TWICE -- once pointing at the Confluence and once at a Home Point. The player:
-- "there should [not] be 2 heavens doors, I'm standing at the actual qufim
-- island zone, the other one took me to my mog house so it's obviously not
-- right." Same shape gave "Closest Survival Guide is Davoi" as a destination
-- for a step whose real business was three Seedspalls.
--
-- Drives the REAL test, lifted from the deployed resolver.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.M = {};
_G.clean = function (v) return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', ''); end

local src = io.open(ADDON .. '/modules/mission_quest_step_resolver.lua'):read('*a');
local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

local from = src:find('function M.entity_is_proximity_hint(step, value, other_targets)', 1, true);
claim(from ~= nil, 'the proximity test exists in the deployed resolver');
local to = from and src:find('\nend\n', from, true) or nil;
if (from == nil or to == nil) then print('proximity hint: 0 passed, 1 failed'); os.exit(1); end
assert(load(src:sub(from, to + 4), 'prox'))();

local function step(text)
    return { instruction = text, primary_instruction = '',
             bg_instruction = '', ffxiclopedia_instruction = '' };
end

-- 1. THE REGRESSION, verbatim from the corpus.
local heavens = step("Examine the Undulating Confluence at (G-8) in Qufim Island. It's close to the Qufim Home Point.");
claim(M.entity_is_proximity_hint(heavens, 'Home Point', 2) == true,
    'the Qufim Home Point is a hint, not a second destination');
claim(M.entity_is_proximity_hint(heavens, 'Undulating Confluence', 2) == false,
    'the thing you examine is not');
claim(M.entity_is_proximity_hint(heavens, 'Qufim Island', 2) == false,
    'and neither is the zone');

-- 2. The Seedspall sub-note that outranked a real drop location.
claim(M.entity_is_proximity_hint(step('Closest Survival Guide is Davoi.'), 'Survival Guide', 1) == true,
    'a "closest Survival Guide" note is a hint');

-- 3. GUARD ONE: a landmark that is the errand keeps its place. Without this,
--    "go and set your Home Point" would resolve to nothing at all.
claim(M.entity_is_proximity_hint(step('Speak to the Survival Guide in Bastok Markets.'),
    'Survival Guide', 0) == false,
    'a landmark that is the ONLY target is never demoted');
claim(M.entity_is_proximity_hint(step('Examine the Home Point to set it.'), 'Home Point', 1) == false,
    'nor is one named without a proximity clause');

-- 4. GUARD TWO: only landmark classes are ever demoted.
claim(M.entity_is_proximity_hint(step('Kupipi is close to the entrance.'), 'Kupipi', 1) == false,
    'an NPC near something is still the target');
claim(M.entity_is_proximity_hint(step('The ??? is next to the rock columns.'), '???', 1) == false,
    'and so is an unnamed marker');

-- 5. The clause must be in the SAME sentence, so a proximity phrase elsewhere
--    in a long step cannot condemn a genuine target.
local mixed = step('Set your Home Point here. The Survival Guide is close to the docks.');
claim(M.entity_is_proximity_hint(mixed, 'Home Point', 2) == false,
    'a landmark in its own clean sentence survives a proximity clause elsewhere');
claim(M.entity_is_proximity_hint(mixed, 'Survival Guide', 2) == true,
    'while the one actually inside the clause is demoted');

-- 6. Empty and malformed input is safe.
claim(M.entity_is_proximity_hint(step(''), 'Home Point', 1) == false, 'no prose, no demotion');
claim(M.entity_is_proximity_hint(step('near the Home Point'), '', 1) == false, 'an empty name is safe');

-- 7. The resolver must actually consult it, and only where a real target exists.
claim(src:find('M.entity_is_proximity_hint(step, value, non_landmark_targets)', 1, true) ~= nil,
    'the entity loop calls it');
claim(src:find('local non_landmark_targets = 0;', 1, true) ~= nil,
    'and counts the non-landmark targets first');
local count_at = src:find('local non_landmark_targets = 0;', 1, true);
local use_at = src:find('M.entity_is_proximity_hint(step, value, non_landmark_targets)', 1, true);
claim(count_at ~= nil and use_at ~= nil and count_at < use_at,
    'counting happens before the loop that uses it');

print(('proximity hint: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

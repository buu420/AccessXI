-- ONE NATIVE ID, THREE MEANINGS.
--
-- Retail's 0x056 carries no status for nation missions. Native id 6 "Journey
-- Abroad" therefore reads identically whether the player has chosen no nation,
-- finished one half, or finished both and owes Halver a report. Live
-- 2026-08-25 the player was on native id 7 (packet nation_mission=6, the Bastok
-- half); the moment they trade the mythril sand the packet drops back to 5 and
-- without this the addon replays the collapsed wiki page at them.
--
-- Key items separate the three, with no stored history -- which is the release
-- case, because a player installing mid-mission has none.
--
-- Drives the REAL resolver in mission_quest_navigation.lua over the REAL
-- override table. Only the 0x055 packet layer is stubbed, and test 14 asserts
-- the function this stubs still exists under that name in the reader.
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

-- The real override table, loaded the way the addon loads it.
accessxi.mission_quest_step_overrides = dofile(ADDON .. '/modules/mission_quest_step_overrides.lua');

-- The real resolver. mission_quest_navigation.lua defines dozens of things we
-- do not exercise; we only need it to LOAD, and the three functions under test
-- touch nothing but accessxi.*, math and pcall.
local ok_nav, nav_err = pcall(dofile, ADDON .. '/modules/mission_quest_navigation.lua');

-- Stub only the 0x055 layer. `held` nil means "no packet has arrived".
local held = nil;
local function key_items(state)
    if (state == nil) then
        accessxi.key_items_packet_tables = nil;
        held = nil;
        return;
    end
    accessxi.key_items_packet_tables = { [0] = { flags = string.rep('0', 128) } };
    held = state;
end
function accessxi.key_items_packet_has_id(id) return (held or {})[id] == true; end

local SANDORIA_6 = "mission:San d'Oria:6";
local SANDORIA_7 = "mission:San d'Oria:7";
local LETTER, REPORT = 5, 29;

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end
local function names_of(steps)
    local out = {};
    for _, s in ipairs(steps or {}) do out[#out + 1] = (s.entities or {})[1] or '?'; end
    return table.concat(out, ', ');
end

claim(ok_nav, 'mission_quest_navigation.lua loads: ' .. tostring(nav_err));
claim(type(accessxi.mission_quest_override_steps) == 'function',
    'the resolver is defined on accessxi, not as a file local');
claim(type(accessxi.mission_quest_key_item_state) == 'function',
    'the tri-state key-item reader is defined');

-- 1. No key-item packet yet: offer both nations, claim nothing.
key_items(nil);
claim(accessxi.mission_quest_key_item_state(LETTER) == 'unknown',
    'with no packet the letter is UNKNOWN, not absent');
local steps, source, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(type(steps) == 'table' and #steps == 3,
    'unknown -> the default, which names both nations and Halver, got ' .. tostring(steps and #steps));
claim(state == '', 'unknown -> no variant state claimed, got "' .. tostring(state) .. '"');
claim(source == 'lsb:2_3_0_Journey_Abroad', 'unknown -> unnamespaced source, got ' .. tostring(source));

-- 2. Carrying the letter: neither half started.
key_items({ [LETTER] = true });
steps, source, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'choose', 'letter held -> choose, got "' .. tostring(state) .. '"');
claim(#steps == 2, 'choose -> exactly one entry per nation, got ' .. tostring(#steps));
claim(names_of(steps) == 'Savae E Paleade, Mourices',
    'choose -> Bastok then Windurst, got ' .. names_of(steps));
claim(source == 'lsb:2_3_0_Journey_Abroad:choose',
    'the cursor revision is namespaced by state, got ' .. tostring(source));

-- 3. Letter gone, no report: exactly one half is finished.
key_items({});
claim(accessxi.mission_quest_key_item_state(LETTER) == 'absent',
    'with a packet loaded a missing letter is ABSENT');
steps, source, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'second', 'letter gone and no report -> second, got "' .. tostring(state) .. '"');
claim(#steps == 2, 'second -> still one entry per nation, got ' .. tostring(#steps));
claim(steps[1].bg_instruction:find('battlefield', 1, true) ~= nil,
    'second -> says the remaining half is the battlefield version');

-- 4. Kindred Report in hand: both done.
key_items({ [REPORT] = true });
steps, source, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'report', 'report held -> report, got "' .. tostring(state) .. '"');
claim(#steps == 1 and names_of(steps) == 'Halver',
    'report -> a single step naming Halver, got ' .. names_of(steps));

-- 5. Report wins over a stale letter; order in the table is the tie-break.
key_items({ [LETTER] = true, [REPORT] = true });
_, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'report', 'report outranks the letter, got "' .. tostring(state) .. '"');

-- 6. A record with no variants is untouched.
key_items({ [LETTER] = true });
steps, source, state = accessxi.mission_quest_override_steps(SANDORIA_7);
claim(#steps == 7 and source == 'lsb:2_3_1_Journey_to_Bastok' and state == '',
    'a variant-free record still returns its fixed steps, got ' ..
    tostring(#steps) .. '/' .. tostring(source));

-- 7. An unknown key resolves to nothing rather than to something.
claim(accessxi.mission_quest_override_steps("mission:San d'Oria:99") == nil,
    'an unknown native key returns nil');
claim(accessxi.mission_quest_override_steps('') == nil, 'an empty native key returns nil');

-- 8. An empty or absent when-clause never matches.
claim(accessxi.mission_quest_override_when_met(nil) == false, 'a nil when-clause is not met');
claim(accessxi.mission_quest_override_when_met({}) == false, 'an empty when-clause is not met');

-- 9. Every step id in the record is unique across all variants and the default.
local seen, collisions = {}, 0;
local record = accessxi.mission_quest_step_overrides[SANDORIA_6];
local function scan(list)
    for _, s in ipairs(list or {}) do
        if (seen[s.stable_step_id]) then collisions = collisions + 1; end
        seen[s.stable_step_id] = true;
    end
end
for _, v in ipairs(record.variants or {}) do scan(v.steps); end
scan(record.steps);
claim(collisions == 0,
    'no step id is shared between states -- a shared id would carry a cursor across, got '
    .. collisions);

-- 10. Every entity named resolves in the shipped catalogue.
local catalogue = {};
for line in io.lines(ADDON .. '/data/ffxi-nav-destinations.tsv') do
    local zone, name = line:match('^(%d+)\t([^\t]+)\t');
    if (name ~= nil) then catalogue[name] = tonumber(zone); end
end
-- entities[1] is the thing you walk to; entities[2] is the zone it stands in.
-- They are checked against different registries -- treating the zone as an NPC
-- is how a passing test would hide a missing NPC.
local zone_names = {};
local header = true;
for line in io.lines(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv') do
    if (header) then header = false; else
        local f = {};
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = field; end
        if (f[3] ~= nil) then zone_names[f[3]] = tonumber(f[2]); end
        if (f[9] ~= nil) then zone_names[f[9]] = tonumber(f[8]); end
    end
end
local missing = {};
local function check(list)
    for _, s in ipairs(list or {}) do
        local target = (s.entities or {})[1];
        local zone = (s.entities or {})[2];
        if (target ~= nil and catalogue[target] == nil) then
            missing[#missing + 1] = 'npc:' .. target;
        end
        if (zone ~= nil and zone_names[zone] == nil) then
            missing[#missing + 1] = 'zone:' .. zone;
        end
        for _, z in ipairs(s.zones or {}) do
            if (zone_names[z] == nil) then missing[#missing + 1] = 'zones:' .. z; end
        end
    end
end
for _, v in ipairs(record.variants or {}) do check(v.steps); end
check(record.steps);
claim(#missing == 0, 'every named entity is in the catalogue, missing: ' .. table.concat(missing, ', '));
claim(catalogue['Mourices'] == 241, 'Mourices is in Windurst Woods (241), got ' .. tostring(catalogue['Mourices']));
claim(catalogue['Halver'] == 233, "Halver is in Chateau d'Oraguille (233), got " .. tostring(catalogue['Halver']));

-- 11. Every step carries usable prose; a silent step is worse than a wrong one.
local blank = 0;
local function prose(list)
    for _, s in ipairs(list or {}) do
        if (#tostring(s.bg_instruction or '') < 40) then blank = blank + 1; end
    end
end
for _, v in ipairs(record.variants or {}) do prose(v.steps); end
prose(record.steps);
claim(blank == 0, 'no step is left without instructions, blank=' .. blank);

-- 12. The choose state tells the player both nations are required.
key_items({ [LETTER] = true });
steps = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(steps[1].bg_instruction:find('either order', 1, true) ~= nil
    and steps[2].bg_instruction:find('either order', 1, true) ~= nil,
    'both entries say the order is free and both are required');

-- 13. A malformed record degrades to nil rather than to a wrong answer.
accessxi.mission_quest_step_overrides['mission:Broken:1'] = { source = 'x', variants = 'nope' };
claim(accessxi.mission_quest_override_steps('mission:Broken:1') == nil,
    'a record with a malformed variants field returns nil');

-- 14. The stubbed seam still exists in the reader under that exact name.
local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
claim(reader:find('function accessxi.key_items_packet_has_id', 1, true) ~= nil,
    'accessxi.key_items_packet_has_id still exists -- this test stubs it');
claim(reader:find('accessxi.key_items_packet_tables', 1, true) ~= nil,
    'accessxi.key_items_packet_tables is still the table this reads');

-- ---------------------------------------------------------------------------
-- The completed-mission bitmap: 0x056 port 0x00D0, one u32 per nation, bit N =
-- packet mission id N. This is the only evidence that names WHICH half is done.
-- Packet ids: 6 Bastok-first, 7 Windurst-first, 8 Bastok-second, 9 Windurst-second.
local DAVOI_DONE = 31;  -- 0b11111, the live value on 2026-08-25
local function bitmap(word)
    accessxi.mission_packet_nations_complete = word and { word, 0, 0, 0, 0, 0, 0, 0 } or nil;
end

-- 15. The accessor reads the live word correctly.
bitmap(DAVOI_DONE);
claim(accessxi.mission_quest_nation_mission_complete(0, 4) == true,
    'bit 4 of 31 is set -- The Davoi Report is complete');
claim(accessxi.mission_quest_nation_mission_complete(0, 5) == false,
    'bit 5 of 31 is clear -- Journey Abroad is still in progress');
claim(accessxi.mission_quest_nation_mission_complete(0, 6) == false,
    'bit 6 of 31 is clear -- the Bastok half is not done yet');
claim(accessxi.mission_quest_nation_mission_complete(1, 4) == false,
    "Bastok's word is read separately and is empty");
bitmap(nil);
claim(accessxi.mission_quest_nation_mission_complete(0, 6) == nil,
    'with no 0x00D0 the answer is nil, not false');
claim(accessxi.mission_quest_nation_mission_complete(0, 99) == nil, 'an absurd bit is nil');
claim(accessxi.mission_quest_nation_mission_complete(7, 6) == nil, 'an absurd nation is nil');

-- 16. No bitmap: the bit-driven states never fire.
key_items({});
bitmap(nil);
_, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'second', 'without the bitmap we fall back to the unnamed half, got ' .. tostring(state));

-- 17. Bastok's half recorded done -> Windurst is what remains.
bitmap(DAVOI_DONE + 64);   -- bit 6
steps, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'second-windurst', 'bit 6 -> second-windurst, got ' .. tostring(state));
claim(names_of(steps) == 'Mourices, Savae E Paleade',
    'the half that remains is listed first, got ' .. names_of(steps));
claim(steps[1].bg_instruction:find("Balga", 1, true) ~= nil,
    'and it names the battlefield the second half actually uses');

-- 18. Windurst's half recorded done -> Bastok remains. Mirror.
bitmap(DAVOI_DONE + 128);  -- bit 7
steps, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'second-bastok', 'bit 7 -> second-bastok, got ' .. tostring(state));
claim(names_of(steps) == 'Savae E Paleade, Mourices',
    'the half that remains is listed first, got ' .. names_of(steps));
claim(steps[1].bg_instruction:find('Waughroon', 1, true) ~= nil,
    'and it names the other battlefield');

-- 19. A PERMANENT BIT MAY ANNOTATE A CHOICE, NEVER REMOVE ONE.
-- These bits survive an allegiance change, so a re-running player can meet a
-- set bit for a half they have not done this time. Both nations stay listed.
for _, word in ipairs({ DAVOI_DONE + 64, DAVOI_DONE + 128 }) do
    bitmap(word);
    steps = accessxi.mission_quest_override_steps(SANDORIA_6);
    claim(#steps == 2, 'both nations remain reachable, got ' .. tostring(#steps));
    claim(steps[2].bg_instruction:find('previous allegiance', 1, true) ~= nil,
        'and the demoted entry says why it is still listed');
end

-- 20. A second half recorded done means both are done.
bitmap(DAVOI_DONE + 64 + 512);   -- bits 6 and 9
steps, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'report-bits', 'a completed second half -> report-bits, got ' .. tostring(state));
claim(#steps == 1 and names_of(steps) == 'Halver', 'and it sends you to Halver alone');
bitmap(DAVOI_DONE + 128 + 256);  -- bits 7 and 8, the other order
_, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'report-bits', 'either branch order reaches report-bits, got ' .. tostring(state));

-- 21. A FRESH RUN OUTRANKS A STALE BIT. Holding the letter means Halver has
-- just sent you out again, whatever an old bitmap says.
key_items({ [LETTER] = true });
bitmap(DAVOI_DONE + 64 + 512);
_, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'choose', 'the letter in hand beats permanent bits, got ' .. tostring(state));

-- 22. The Kindred Report still outranks everything.
key_items({ [REPORT] = true });
bitmap(DAVOI_DONE);
_, _, state = accessxi.mission_quest_override_steps(SANDORIA_6);
claim(state == 'report', 'the report in hand wins outright, got ' .. tostring(state));

-- 23. The reader still captures the port this depends on.
claim(reader:find('accessxi.mission_packet_nations_complete = accessxi.quest_packet_data_words', 1, true) ~= nil,
    'port 0x00D0 is still captured into mission_packet_nations_complete');
claim(reader:find('packet_port == 0x00D0', 1, true) ~= nil, 'and 0x00D0 is still routed there');

-- 24. Step ids stay unique now that there are seven states.
seen, collisions = {}, 0;
record = accessxi.mission_quest_step_overrides[SANDORIA_6];
for _, v in ipairs(record.variants or {}) do scan(v.steps); end
scan(record.steps);
claim(collisions == 0, 'still no step id shared between states, got ' .. collisions);
claim(#record.variants == 6, 'six evidence-driven states plus the default, got ' .. #record.variants);

-- 25. Every entity in the new states resolves too.
missing = {};
for _, v in ipairs(record.variants or {}) do check(v.steps); end
check(record.steps);
claim(#missing == 0, 'every entity in every state resolves, missing: ' .. table.concat(missing, ', '));

-- ---------------------------------------------------------------------------
-- A BATTLEFIELD IS PROVED WON BY ITS REWARD, NOT BY A BODY COUNT.
--
-- A defeat count cannot tell two enemies apart, so it can never separate "both
-- essential mobs died" from "the same one died twice", nor one kill before a
-- wipe from one after it. Putting the Kindred Crest in a step BEHIND the fight
-- was no better: the fight step still advanced on its own, so the player could
-- hear it complete while the Searcher was alive. The crest is now the fight
-- step's own completion evidence.
local nav_src = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');

for _, spec in ipairs({
    { key = "mission:San d'Oria:9",  order = 4, enemies = 'Dark Dragon',  steps = 5 },
    { key = "mission:San d'Oria:10", order = 3, enemies = 'Black Dragon', steps = 4 },
}) do
    local record = accessxi.mission_quest_step_overrides[spec.key];
    claim(type(record) == 'table' and #record.steps == spec.steps,
        spec.key .. ' has ' .. spec.steps .. ' steps, got '
        .. tostring(type(record) == 'table' and #record.steps or 'nil'));
    local fight = record.steps[spec.order];
    claim(fight ~= nil and fight.action == 'fight'
        and (fight.entities or {})[1] == spec.enemies,
        spec.key .. ' step ' .. spec.order .. ' is the fight, got '
        .. tostring(fight and fight.action));
    claim(fight ~= nil and fight.completion_evidence == 'key-item:Kindred Crest',
        'and it names the Kindred Crest as its proof, got '
        .. tostring(fight and fight.completion_evidence));
    claim(fight ~= nil and #(fight.entities or {}) == 2,
        'while still naming BOTH enemies so the player is told what to kill, got '
        .. #((fight or {}).entities or {}));
    -- The crest must NOT be a step of its own any more.
    local crest_steps = 0;
    for _, s in ipairs(record.steps) do
        if ((s.entities or {})[1] == 'Kindred Crest') then crest_steps = crest_steps + 1; end
    end
    claim(crest_steps == 0,
        spec.key .. ' no longer carries the crest as a separate step, got ' .. crest_steps);
end

-- The three code paths that make the evidence real, not decorative.
claim(nav_src:find('completion_evidence = clean(entry.completion_evidence)', 1, true) ~= nil,
    'the action builder carries completion evidence onto the action');
claim(nav_src:find("and clean(action.completion_evidence) == ''", 1, true) ~= nil,
    'kill credit refuses to complete a step that names its own proof');
local evidence_at = nav_src:find('local evidence = clean(action.completion_evidence):lower()', 1, true);
local obtain_at = nav_src:find("if (clean(action.action):lower() ~= 'obtain'", 1, true);
claim(evidence_at ~= nil, 'the acquisition matcher reads completion evidence');
claim(evidence_at ~= nil and obtain_at ~= nil and evidence_at < obtain_at,
    'and reads it BEFORE the obtain-only gate that would otherwise reject a fight step');

-- A step with no evidence must be unaffected, or every ordinary fight breaks.
local seven = accessxi.mission_quest_step_overrides["mission:San d'Oria:7"];
local plain = nil;
for _, s in ipairs(seven.steps) do
    if (s.action == 'trade' and plain == nil) then plain = s; end
end
claim(plain ~= nil and (plain.completion_evidence == nil or plain.completion_evidence == ''),
    'an ordinary step names no evidence and is untouched');

print(('override variants: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

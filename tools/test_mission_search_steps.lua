-- Regression for modules/mission_quest_search_steps.lua.
--
-- THE DEFECT THIS EXISTS FOR.
--
-- Windurst 1 step-018 is the "check the six different Ancient Magical Gizmos
-- until you are given the key item Cracked Mana Orb" step. Both source pages
-- agree on it (comparison = corroborated) and ffxiclopedia even lists all six
-- map squares. It still reached the player as nothing routable, because:
--
--   * action = 'note', so the resolver declines it by design;
--   * entities = { 'Cracked Mana Orb' } -- the REWARD sits in the slot the
--     destination should occupy, and "Ancient Magical Gizmo" appears nowhere;
--   * the step has NO compact progression action at all, so there is nothing
--     for an identity binding to attach to.
--
-- A player who watched the gate cutscene was therefore routed back to the gate
-- forever, and the six gizmos were never offered.
--
-- WHAT THE MODULE MAY NOT DO. It may not guess which gizmo holds the orb (the
-- game assigns it randomly per player), may not own stage proof or saved state,
-- and may not turn ordinary notes into routes. Everything here is derived from
-- the source text plus the shipped catalogue, or it is refused with a named
-- reason.
--
--   luajit tools/test_mission_search_steps.lua
--   ACCESSXI_ADDON=<tree> luajit tools/test_mission_search_steps.lua
--
-- Exit 1 on any failed claim.

local here = (arg[0]:match('^(.*)[/\\]') or '.');
local ADDON = os.getenv('ACCESSXI_ADDON')
    or (here .. '/../ashita/addons/accessxi_reader');

local M = dofile(ADDON .. '/modules/mission_quest_search_steps.lua');

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1;
    else failures = failures + 1; print('  FAIL ' .. text); end
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
local function split_tsv(line)
    local parts = {};
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do parts[#parts + 1] = part; end
    return parts;
end
local function name_key(s)
    local key = trim(s):lower();
    key = key:gsub('%s*([:,])%s*', '%1');
    key = key:gsub('%s+', ' ');
    return key;
end

-- REAL catalogue, not a stand-in. The six gizmos ship as kind='npc', which is
-- exactly why the module must not demand kind=='object'.
local catalogue = {};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-destinations.tsv', 'r'));
    for line in f:lines() do
        if (line ~= '' and not line:match('^#')) then
            local p = split_tsv(line);
            local zone = tonumber(p[1]);
            if (zone and zone > 0 and trim(p[2]) ~= '') then
                local key = zone .. '\t' .. name_key(p[2]);
                catalogue[key] = catalogue[key] or {};
                table.insert(catalogue[key], {
                    zone = zone, name = trim(p[2]),
                    x = tonumber(p[3]), z = tonumber(p[4]), y = tonumber(p[5]),
                    kind = trim(p[6]), source = trim(p[7]), confidence = trim(p[8]),
                    destination_id = trim(p[10] or ''), raw_identity = trim(p[11] or ''),
                });
            end
        end
    end
    f:close();
end

local extra_points = {};
local function points(zone, name)
    local key = tonumber(zone) .. '\t' .. name_key(name);
    return extra_points[key] or catalogue[key];
end

local zone_ids = { ['inner horutoto ruins'] = { 192 } };
local function zone_id_for_name(name) return zone_ids[name_key(name)]; end

local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end return n; end
local function find_step(steps, id)
    for _, s in ipairs(steps or {}) do
        if (tostring(s.stable_step_id) == id) then return s; end
    end
end

-- the real step -------------------------------------------------------------
local windurst = dofile(ADDON .. '/modules/mission_quest_reconcile_mission_windurst.lua');
local real_steps = assert(windurst['mission:Windurst:1']).steps;
local real_018 = assert(find_step(real_steps, 'mission:Windurst:1:step-018'),
    'the real step-018 is missing from the shipped guide');

claim(name_key(real_018.action) == 'note',
    'precondition: the real step-018 still ships as a note (got ' .. tostring(real_018.action) .. ')');
claim(#(real_018.entities or {}) == 1 and real_018.entities[1] == 'Cracked Mana Orb',
    'precondition: the real step-018 still carries only the reward as its entity');

local normalized = M.normalize_steps(real_steps, points, zone_id_for_name);
local n018 = assert(find_step(normalized, 'mission:Windurst:1:step-018'),
    'normalize_steps dropped step-018');
local set = n018.search_set;

claim(type(set) == 'table', 'the real step-018 gains a search_set');
if (type(set) == 'table') then
    claim(set.target_name == 'Ancient Magical Gizmo',
        'search_set.target_name is the exact singular catalogue name (got '
            .. tostring(set.target_name) .. ')');
    claim(set.zone_id == 192, 'search_set.zone_id is 192 (got ' .. tostring(set.zone_id) .. ')');
    claim(set.expected_count == 6,
        'search_set.expected_count is the six the source names (got ' .. tostring(set.expected_count) .. ')');
    claim(set.completion_item == 'Cracked Mana Orb',
        'search_set.completion_item is the exact key item (got ' .. tostring(set.completion_item) .. ')');
    local ids = set.destination_ids or {};
    claim(#ids == 6, 'search_set carries six destination ids (got ' .. tostring(#ids) .. ')');
    local expected_ids = {
        'npc:v1:192:17563868', 'npc:v1:192:17563869', 'npc:v1:192:17563870',
        'npc:v1:192:17563871', 'npc:v1:192:17563872', 'npc:v1:192:17563873',
    };
    local matched = (#ids == #expected_ids);
    for i, want in ipairs(expected_ids) do
        if (ids[i] ~= want) then matched = false; end
    end
    claim(matched, 'destination_ids are the exact six gizmo identities, sorted');
end

claim(name_key(n018.action) == 'examine',
    'the effective action becomes examine (got ' .. tostring(n018.action) .. ')');
claim(#(n018.entities or {}) == 1 and n018.entities[1] == 'Ancient Magical Gizmo',
    'the effective entities become just the search target, not the reward');
claim(n018.bg_instruction == real_018.bg_instruction
        and n018.ffxiclopedia_instruction == real_018.ffxiclopedia_instruction
        and n018.stable_step_id == real_018.stable_step_id
        and n018.comparison == real_018.comparison,
    'guide text, step id and source comparison are preserved verbatim');

-- the source must not be mutated
claim(name_key(real_018.action) == 'note'
        and #(real_018.entities or {}) == 1
        and real_018.entities[1] == 'Cracked Mana Orb'
        and real_018.search_set == nil,
    'normalize_steps does not mutate the caller and s steps');

-- unrelated steps stay exactly as they were
local n019 = find_step(normalized, 'mission:Windurst:1:step-019');
claim(type(n019) == 'table' and name_key(n019.action) == 'note' and n019.search_set == nil,
    'an ordinary note is left alone');
local n017 = find_step(normalized, 'mission:Windurst:1:step-017');
claim(type(n017) == 'table' and name_key(n017.action) == 'examine' and n017.search_set == nil,
    'the gate step is untouched');
claim(#normalized == #real_steps, 'no step is added or removed');

-- idempotence
local twice = M.normalize_steps(normalized, points, zone_id_for_name);
local t018 = find_step(twice, 'mission:Windurst:1:step-018');
claim(type(t018) == 'table' and type(t018.search_set) == 'table'
        and t018.search_set.expected_count == 6
        and #(t018.search_set.destination_ids or {}) == 6
        and #(t018.entities or {}) == 1
        and t018.entities[1] == 'Ancient Magical Gizmo',
    'normalize_steps is idempotent');

-- a second, non-Windurst shape ----------------------------------------------
zone_ids['test hall'] = { 9001 };
extra_points['9001\tancient brazier'] = {
    { zone = 9001, name = 'Ancient Brazier', x = 1, z = 1, y = 0, kind = 'object', destination_id = 'object:v1:9001:400' },
    { zone = 9001, name = 'Ancient Brazier', x = 2, z = 2, y = 0, kind = 'object', destination_id = 'object:v1:9001:200' },
    { zone = 9001, name = 'Ancient Brazier', x = 3, z = 3, y = 0, kind = 'object', destination_id = 'object:v1:9001:300' },
    { zone = 9001, name = 'Ancient Brazier', x = 4, z = 4, y = 0, kind = 'object', destination_id = 'object:v1:9001:100' },
};
local synthetic = {
    { stable_step_id = 's:1:step-001', order = 1, action = 'talk', entities = { 'Someone' }, zones = { 'Test Hall' } },
    { stable_step_id = 's:1:step-002', order = 2, action = 'note',
      comparison = 'corroborated',
      entities = { 'Test Sigil' }, zones = { 'Test Hall' },
      bg_instruction = 'Check the four different Ancient Braziers until you are given the key item Test Sigil.',
      ffxiclopedia_instruction = 'Search the four different Ancient Braziers until you find the key item Test Sigil.' },
};
local snorm = M.normalize_steps(synthetic, points, zone_id_for_name);
local s2 = find_step(snorm, 's:1:step-002');
claim(type(s2) == 'table' and type(s2.search_set) == 'table'
        and s2.search_set.target_name == 'Ancient Brazier'
        and s2.search_set.zone_id == 9001
        and s2.search_set.expected_count == 4
        and s2.search_set.completion_item == 'Test Sigil',
    'a non-Windurst search step of the same shape normalizes too');
if (type(s2) == 'table' and type(s2.search_set) == 'table') then
    local ids = s2.search_set.destination_ids or {};
    claim(#ids == 4 and ids[1] == 'object:v1:9001:100' and ids[4] == 'object:v1:9001:400',
        'destination ids are sorted, not catalogue order');
end

-- refusals: named reason, never invention ------------------------------------
local function refusal(step_overrides, label, want_reason)
    local step = {
        stable_step_id = 'r:1:step-001', order = 1, action = 'note',
        comparison = 'corroborated',
        entities = { 'Test Sigil' }, zones = { 'Test Hall' },
        bg_instruction = 'Check the four different Ancient Braziers until you are given the key item Test Sigil.',
    };
    for k, v in pairs(step_overrides or {}) do step[k] = v; end
    local out = M.normalize_steps({ step }, points, zone_id_for_name);
    local got = out[1];
    local ok = type(got) == 'table' and got.search_set == nil
        and name_key(got.action) == 'note';
    claim(ok, label .. ' is refused and left as a note');
    if (want_reason) then
        claim(type(got) == 'table' and type(got.search_refusal) == 'table'
                and got.search_refusal.reason == want_reason,
            label .. ' carries reason ' .. want_reason .. ' (got '
                .. tostring(type(got) == 'table' and type(got.search_refusal) == 'table'
                    and got.search_refusal.reason or 'none') .. ')');
    end
end

refusal({ bg_instruction = 'Check the five different Ancient Braziers until you are given the key item Test Sigil.' },
    'a count the catalogue cannot match', 'member-count-mismatch');
refusal({ zones = { 'Nowhere At All' } }, 'an unknown zone', 'zone-unknown');
refusal({ bg_instruction = 'Check the four different Ancient Braziers until you are done.' },
    'a search naming no key item', 'reward-missing');
refusal({ bg_instruction = 'Do not check the four different Ancient Braziers until you are given the key item Test Sigil.' },
    'a negated instruction', 'negated-instruction');
refusal({ bg_instruction = 'Check the four different Ancient Boxen until you are given the key item Test Sigil.' },
    'an irregular plural that matches no catalogue name', 'target-unmatched');

do
    zone_ids['twin hall'] = { 9101, 9102 };
    refusal({ zones = { 'Twin Hall' } }, 'an ambiguous zone', 'zone-ambiguous');
end

do
    extra_points['9001\tangry brazier'] = {
        { zone = 9001, name = 'Angry Brazier', x = 1, z = 1, y = 0, kind = 'enemy', destination_id = 'mob:v1:9001:1' },
        { zone = 9001, name = 'Angry Brazier', x = 2, z = 2, y = 0, kind = 'mob', destination_id = 'mob:v1:9001:2' },
        { zone = 9001, name = 'Angry Brazier', x = 3, z = 3, y = 0, kind = 'enemy', destination_id = 'mob:v1:9001:3' },
        { zone = 9001, name = 'Angry Brazier', x = 4, z = 4, y = 0, kind = 'enemy', destination_id = 'mob:v1:9001:4' },
    };
    refusal({ bg_instruction = 'Check the four different Angry Braziers until you are given the key item Test Sigil.' },
        'a set whose members are enemies', 'member-count-mismatch');
end

-- an ordinary duplicate-name step is NOT a search
do
    local ordinary = { {
        stable_step_id = 'd:1:step-001', order = 1, action = 'examine',
        entities = { 'Ancient Magical Gizmo' }, zones = { 'Inner Horutoto Ruins' },
        bg_instruction = 'Check the Ancient Magical Gizmo.',
    } };
    local out = M.normalize_steps(ordinary, points, zone_id_for_name);
    claim(type(out[1]) == 'table' and out[1].search_set == nil,
        'a normal duplicated-entity step is left to the usual choice path');
end

-- augment_actions -------------------------------------------------------------
local prog = dofile(ADDON .. '/modules/mission_quest_progression_mission_windurst.lua');
local prog_root = type(prog.objectives) == 'table' and prog.objectives or prog;
local real_actions = assert(prog_root['mission:Windurst:1']).progression_actions;
local before_count = #real_actions;

local augmented = M.augment_actions(real_actions, normalized);
claim(#augmented == before_count + 1,
    'augment_actions inserts exactly one action (got ' .. tostring(#augmented) .. ')');
claim(#real_actions == before_count, 'augment_actions does not mutate the caller and s actions');

local inserted, insert_index;
for i, a in ipairs(augmented) do
    if (tostring(a.step_id) == 'mission:Windurst:1:step-018') then inserted, insert_index = a, i; end
end
claim(type(inserted) == 'table', 'the search action exists for step-018');
if (type(inserted) == 'table') then
    claim(inserted.action_id == 'mission:Windurst:1:step-018:claim-01',
        'action id is step-018:claim-01 (got ' .. tostring(inserted.action_id) .. ')');
    claim(tonumber(inserted.step_order) == 18,
        'step_order comes from the source step (got ' .. tostring(inserted.step_order) .. ')');
    claim(tonumber(inserted.action_order) == 1, 'action_order is 1');
    claim(name_key(inserted.action) == 'examine', 'the action verb is examine');
    claim(name_key(inserted.target_kind) == 'object', 'target_kind is object');
    claim(inserted.target == 'Ancient Magical Gizmo', 'target is the singular catalogue name');
    claim(#(inserted.objects or {}) == 1 and inserted.objects[1] == 'Ancient Magical Gizmo',
        'objects names the search target');
    claim(#(inserted.key_items or {}) == 1 and inserted.key_items[1] == 'Cracked Mana Orb',
        'key_items names the reward');
    claim(inserted.completion_evidence == 'key-item:Cracked Mana Orb',
        'completion_evidence is the key item, not a visit count (got '
            .. tostring(inserted.completion_evidence) .. ')');
    claim(tonumber(inserted.required_count) == 1 and name_key(inserted.count_mode) == 'single',
        'the step completes once on the orb, NOT after six interactions');
    claim(inserted.material == true, 'the action is material');
    claim(inserted.source == 'source-search', 'source is source-search');
    claim(type(inserted.search_set) == 'table'
            and #(inserted.search_set.destination_ids or {}) == 6,
        'the action carries the search_set with its six ids');
end

-- ordering: after step-017, before step-021
do
    local order_of = {};
    for i, a in ipairs(augmented) do order_of[tostring(a.step_id)] = i; end
    claim((order_of['mission:Windurst:1:step-017'] or 0) < (insert_index or 0)
            and (insert_index or 0) < (order_of['mission:Windurst:1:step-021'] or 0),
        'the search action sits between the gate step and the turn-in');
    local prev, ok_sorted = -1, true;
    for _, a in ipairs(augmented) do
        local so = tonumber(a.step_order) or 0;
        if (so < prev) then ok_sorted = false; end
        prev = so;
    end
    claim(ok_sorted, 'the returned actions remain sorted by step_order');
end

-- existing actions survive intact
do
    local kept = true;
    for _, before in ipairs(real_actions) do
        local found = false;
        for _, after in ipairs(augmented) do
            if (after.action_id == before.action_id
                and after.action == before.action
                and after.target == before.target
                and tonumber(after.step_order) == tonumber(before.step_order)) then
                found = true;
            end
        end
        if (not found) then kept = false; end
    end
    claim(kept, 'every pre-existing action survives unchanged in identity');
end

-- idempotence of augmentation
do
    local again = M.augment_actions(augmented, normalized);
    local n = 0;
    for _, a in ipairs(again) do
        if (tostring(a.step_id) == 'mission:Windurst:1:step-018') then n = n + 1; end
    end
    claim(#again == #augmented and n == 1, 'augment_actions is idempotent');
end

-- a normalized set with no search steps changes nothing
do
    local plain = M.augment_actions(real_actions, M.normalize_steps({ real_steps[1] }, points, zone_id_for_name));
    claim(#plain == before_count, 'no search step means no inserted action');
end

print(('claims: %d passed, %d failed'):format(passes, failures));
if (failures > 0) then os.exit(1); end

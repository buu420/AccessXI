-- Regression for modules/objective_npc_rewards.lua.
--
-- THE DEFECT THIS EXISTS FOR.
--
-- Windurst 2 "The Heart of the Matter": the player talked to Pore-Ohre
-- (17253039, zone 116), heard the whole briefing, and was handed the key item
-- "Southeastern star charm" at 18:03:02. The cursor never moved and the addon
-- routed them straight back to the same NPC.
--
-- Two guide steps describe that single conversation -- step-020 `talk` to
-- Pore-Ohre and step-021 `travel` + `talk` to Pore-Ohre -- and step-021 is the
-- one whose sentence names the reward. Neither compact action carried
-- key_items or completion_evidence, so the arriving key item proved nothing and
-- the two look-alike actions could not be told apart.
--
-- This module reads the reward sentence the guide actually wrote and annotates
-- BOTH talk actions with the same key item and the same group_action_id, so the
-- reducer can treat them as one conversation and finish them when the item
-- really arrives.
--
-- WHAT IT MAY NOT DO. It owns no progression proof, no cursor, no recovery. It
-- never invents a reward: the name must resolve through the caller's callback
-- to a positive numeric key-item id, or the step is left exactly as it was. It
-- refuses negation, conditionals, prerequisites, two-reward sentences and
-- disagreeing sources rather than guessing between them.
--
--   luajit tools/test_objective_npc_rewards.lua
--   ACCESSXI_ADDON=<tree> luajit tools/test_objective_npc_rewards.lua
--
-- Exit 1 on any failed claim.

local here = (arg[0]:match('^(.*)[/\\]') or '.');
local ADDON = os.getenv('ACCESSXI_ADDON')
    or (here .. '/../ashita/addons/accessxi_reader');

local M = dofile(ADDON .. '/modules/objective_npc_rewards.lua');

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1;
    else failures = failures + 1; print('  FAIL ' .. text); end
end
local function lower(v) return tostring(v or ''):lower(); end

-- The caller owns id resolution. Ids here are arbitrary but positive; the real
-- adapter will read the shipped key-item resource.
local KNOWN = {
    ['southeastern star charm'] = { 112, 'Southeastern star charm' },
    ['dark key'] = { 501, 'Dark Key' },
    ['hideout key'] = { 502, 'Hideout key' },
    ['food offering'] = { 503, 'Food Offering' },
    ['drink offering'] = { 504, 'Drink Offering' },
};
local lookups = 0;
local function key_item_id_for_name(name)
    lookups = lookups + 1;
    local row = KNOWN[lower(name):gsub('^%s+', ''):gsub('%s+$', '')];
    if (row == nil) then return nil; end
    return row[1], row[2];
end

local function find_action(actions, action_id)
    for _, a in ipairs(actions or {}) do
        if (tostring(a.action_id) == action_id) then return a; end
    end
end

-- the real Windurst 2 case ---------------------------------------------------
local windurst_steps = assert(
    dofile(ADDON .. '/modules/mission_quest_reconcile_mission_windurst.lua')['mission:Windurst:2']).steps;
local prog = dofile(ADDON .. '/modules/mission_quest_progression_mission_windurst.lua');
local prog_root = type(prog.objectives) == 'table' and prog.objectives or prog;
local windurst_actions = assert(prog_root['mission:Windurst:2']).progression_actions;

local TALK_020 = 'mission:Windurst:2:step-020:claim-01';
local TRAVEL_021 = 'mission:Windurst:2:step-021:claim-01';
local TALK_021 = 'mission:Windurst:2:step-021:claim-02';

do
    local before = #windurst_actions;
    local out, changed = M.augment_actions(windurst_actions, windurst_steps, key_item_id_for_name);
    claim(changed == true, 'the real Windurst 2 reward sentence is recognised (changed=true)');
    claim(#out == before, 'augment_actions inserts and removes nothing');
    claim(#windurst_actions == before, 'the caller actions table is not mutated');

    local terminal = find_action(out, TALK_021);
    claim(type(terminal) == 'table', 'the rewarded terminal talk action is present');
    if (type(terminal) == 'table') then
        claim(terminal.completion_evidence == 'key-item:Southeastern star charm',
            'terminal talk gains completion_evidence (got ' .. tostring(terminal.completion_evidence) .. ')');
        local reward = terminal.completion_reward;
        claim(type(reward) == 'table'
                and reward.kind == 'key-item'
                and reward.name == 'Southeastern star charm'
                and reward.id == 112
                and reward.group_action_id == TALK_021,
            'terminal completion_reward names the item, its id and itself as the group');
    end

    local heading = find_action(out, TALK_020);
    claim(type(heading) == 'table', 'the preceding same-NPC talk action is present');
    if (type(heading) == 'table') then
        claim(heading.completion_evidence == 'key-item:Southeastern star charm',
            'the preceding same-NPC talk carries the same evidence');
        claim(type(heading.completion_reward) == 'table'
                and heading.completion_reward.group_action_id == TALK_021,
            'the preceding talk points at the TERMINAL action as its group');
    end

    local travel = find_action(out, TRAVEL_021);
    claim(type(travel) == 'table' and travel.completion_evidence == nil
            and travel.completion_reward == nil,
        'the intervening travel action is crossed but never annotated');

    local annotated = 0;
    for _, a in ipairs(out) do if (a.completion_reward ~= nil) then annotated = annotated + 1; end end
    claim(annotated == 2, 'exactly two actions are annotated (got ' .. tostring(annotated) .. ')');

    -- the source itself must be untouched
    local src_terminal = find_action(windurst_actions, TALK_021);
    claim(type(src_terminal) == 'table' and src_terminal.completion_reward == nil
            and (src_terminal.completion_evidence == nil or src_terminal.completion_evidence == ''),
        'the caller actions are not annotated in place');

    -- idempotence
    local again, changed_again = M.augment_actions(out, windurst_steps, key_item_id_for_name);
    local again_count = 0;
    for _, a in ipairs(again) do if (a.completion_reward ~= nil) then again_count = again_count + 1; end end
    claim(changed_again == false and again_count == 2 and #again == #out,
        'augment_actions is idempotent and reports changed=false the second time');
end

-- synthetic shapes -----------------------------------------------------------
local function build(instruction, opts)
    opts = opts or {};
    local npc = opts.npc or 'Kupipi';
    local steps = {
        { stable_step_id = 's:1:step-001', order = 1, action = 'talk',
          entities = { npc }, zones = { 'Windurst Walls' },
          bg_instruction = opts.lead or ('Speak to ' .. npc .. '.') },
        { stable_step_id = 's:1:step-002', order = 2, action = 'talk',
          entities = { npc }, zones = { 'Windurst Walls' },
          bg_instruction = instruction,
          ffxiclopedia_instruction = opts.ffxi },
    };
    local actions = {
        { step_id = 's:1:step-001', action_id = 's:1:step-001:claim-01', step_order = 1,
          action_order = 1, order = 1, action = 'talk', target = npc, npcs = { npc } },
        { step_id = 's:1:step-002', action_id = 's:1:step-002:claim-01', step_order = 2,
          action_order = 1, order = 2, action = 'travel', target = 'Windurst Walls', npcs = {} },
        { step_id = 's:1:step-002', action_id = 's:1:step-002:claim-02', step_order = 2,
          action_order = 2, order = 3, action = 'talk', target = npc, npcs = { npc } },
    };
    if (opts.between) then
        table.insert(actions, 2, opts.between);
        for i, a in ipairs(actions) do a.order = i; end
    end
    return actions, steps;
end

local function accepted(instruction, label, expected_name, expected_id, opts)
    local actions, steps = build(instruction, opts);
    local out, changed = M.augment_actions(actions, steps, key_item_id_for_name);
    local terminal = find_action(out, 's:1:step-002:claim-02');
    local ok = changed == true and type(terminal) == 'table'
        and type(terminal.completion_reward) == 'table'
        and terminal.completion_reward.name == expected_name
        and terminal.completion_reward.id == expected_id
        and terminal.completion_evidence == 'key-item:' .. expected_name;
    claim(ok, label);
    return out;
end

local function refused(instruction, label, opts)
    local actions, steps = build(instruction, opts);
    local out, changed = M.augment_actions(actions, steps, key_item_id_for_name);
    local annotated = 0;
    for _, a in ipairs(out) do if (a.completion_reward ~= nil) then annotated = annotated + 1; end end
    claim(changed == false and annotated == 0, label .. ' is refused, nothing annotated');
end

accepted('Talk to Kupipi in Heavens Tower. She will give you a key item Dark Key.',
    '"She will give you a key item X" is recognised', 'Dark Key', 501);
accepted('Make your way back to Nanaa Mihgo, who will give you the key item Hideout key.',
    '"who will give you the key item X" is recognised', 'Hideout key', 502,
    { npc = 'Nanaa Mihgo' });
accepted('He will give you the KEY ITEM dark key.',
    'the reward name is matched case-insensitively and canonicalised', 'Dark Key', 501);
accepted('Speak to Kupipi, who gives you the key item Dark Key.',
    'present tense "gives you the key item X" is recognised', 'Dark Key', 501);

refused('If you traded a Rolanberry to Kupipi earlier, she will not give you the key item Dark Key until now.',
    'a negated conditional sentence');
refused('She will not give you the key item Dark Key.', 'a plain negation');
refused('You must already have the key item Dark Key before she will speak to you.',
    'a prerequisite rather than a reward');
refused('She will give you the key item Food Offering and key item Drink Offering.',
    'a sentence granting two different key items');
refused('She will give you the key item Nonexistent Widget.',
    'a reward the caller cannot resolve to an id');
refused('Talk to the Yagudo NPC Laa Mozi to give key item Food Offering.',
    'the player giving an item away, not receiving one');
refused('She will give you the key item .', 'a malformed sentence with no reward name');
refused('She will give you the Key Item key item Dark Key.',
    'a malformed doubled "key item" phrase');
refused('Speak to Kupipi. She might give you the key item Dark Key if you are lucky.',
    'a conditional reward');
refused('She will give you the key item "Creature Counter" magic doll to keep track of your objective.',
    'a run-on clause that is not a plain item name');
refused('She will give you the key item Dark Key of the Ancient Windurstian Ministry of Magical Affairs',
    'an implausibly long captured name');

-- source disagreement
refused('She will give you the key item Dark Key.',
    'sources naming different rewards', { ffxi = 'She will give you the key item Hideout key.' });
accepted('She will give you the key item Dark Key.',
    'sources agreeing apart from case still resolve', 'Dark Key', 501,
    { ffxi = 'She will give you a key item DARK KEY.' });

-- the preceding-talk carry rule ---------------------------------------------
do
    local actions, steps = build('She will give you a key item Dark Key.',
        {lead='Speak to Kupipi about your citizenship before leaving the city.'});
    local out = M.augment_actions(actions, steps, key_item_id_for_name);
    claim(find_action(out, 's:1:step-001:claim-01').completion_reward == nil,
        'a substantive earlier conversation with the same NPC is not a duplicate heading');
end

do
    local out = accepted('She will give you a key item Dark Key.',
        'baseline for the carry rule', 'Dark Key', 501);
    local heading = find_action(out, 's:1:step-001:claim-01');
    claim(type(heading) == 'table' and type(heading.completion_reward) == 'table'
            and heading.completion_reward.group_action_id == 's:1:step-002:claim-02',
        'a same-NPC talk separated only by travel is carried');
end

do
    local fight = { step_id = 's:1:step-00X', action_id = 's:1:step-00X:claim-01', step_order = 1,
        action_order = 1, order = 0, action = 'fight', target = 'Orcish Fodder', npcs = {}, enemies = { 'Orcish Fodder' } };
    local actions, steps = build('She will give you a key item Dark Key.', { between = fight });
    local out = M.augment_actions(actions, steps, key_item_id_for_name);
    local heading = find_action(out, 's:1:step-001:claim-01');
    claim(type(heading) == 'table' and heading.completion_reward == nil,
        'a fight between the two talks stops the carry');
    claim(find_action(out, 's:1:step-00X:claim-01').completion_reward == nil,
        'the intervening fight is never annotated');
end

do
    local trade = { step_id = 's:1:step-00Y', action_id = 's:1:step-00Y:claim-01', step_order = 1,
        action_order = 1, order = 0, action = 'trade', target = 'Kupipi', npcs = { 'Kupipi' } };
    local actions, steps = build('She will give you a key item Dark Key.', { between = trade });
    local out = M.augment_actions(actions, steps, key_item_id_for_name);
    claim(find_action(out, 's:1:step-001:claim-01').completion_reward == nil,
        'a trade between the two talks stops the carry');
end

do
    local other = { step_id = 's:1:step-00Z', action_id = 's:1:step-00Z:claim-01', step_order = 1,
        action_order = 1, order = 0, action = 'talk', target = 'Someone Else', npcs = { 'Someone Else' } };
    local actions, steps = build('She will give you a key item Dark Key.', { between = other });
    local out = M.augment_actions(actions, steps, key_item_id_for_name);
    claim(find_action(out, 's:1:step-001:claim-01').completion_reward == nil,
        'a different NPC between the two talks stops the carry');
    claim(find_action(out, 's:1:step-00Z:claim-01').completion_reward == nil,
        'the unrelated NPC talk is never annotated');
end

-- a later return visit to the same NPC is a different objective
do
    local actions, steps = build('She will give you a key item Dark Key.');
    steps[#steps + 1] = { stable_step_id = 's:1:step-009', order = 9, action = 'talk',
        entities = { 'Kupipi' }, zones = { 'Windurst Walls' },
        bg_instruction = 'Return to Kupipi to finish the mission.' };
    actions[#actions + 1] = { step_id = 's:1:step-009', action_id = 's:1:step-009:claim-01',
        step_order = 9, action_order = 1, order = 9, action = 'talk', target = 'Kupipi', npcs = { 'Kupipi' } };
    local out = M.augment_actions(actions, steps, key_item_id_for_name);
    claim(find_action(out, 's:1:step-009:claim-01').completion_reward == nil,
        'a later return visit to the same NPC is never folded into the group');
end

-- malformed / defensive inputs
do
    local out, changed = M.augment_actions(nil, nil, key_item_id_for_name);
    claim(type(out) == 'table' and #out == 0 and changed == false, 'nil inputs are handled');
    local out2, changed2 = M.augment_actions({}, {}, nil);
    claim(type(out2) == 'table' and #out2 == 0 and changed2 == false, 'a missing callback annotates nothing');
end

do
    local actions, steps = build('She will give you a key item Dark Key.');
    local bad = function () return 0; end
    local out, changed = M.augment_actions(actions, steps, bad);
    local annotated = 0;
    for _, a in ipairs(out) do if (a.completion_reward ~= nil) then annotated = annotated + 1; end end
    claim(changed == false and annotated == 0, 'a non-positive id is rejected');
    local bad2 = function () return 'not a number'; end
    local out2, changed2 = M.augment_actions(actions, steps, bad2);
    claim(changed2 == false, 'a non-numeric first return is rejected');
end

-- existing evidence is never overwritten
do
    local actions, steps = build('She will give you a key item Dark Key.');
    for _, a in ipairs(actions) do
        if (a.action_id == 's:1:step-002:claim-02') then a.completion_evidence = 'key-item:Something Else'; end
    end
    local out, changed = M.augment_actions(actions, steps, key_item_id_for_name);
    local terminal = find_action(out, 's:1:step-002:claim-02');
    claim(changed == false and terminal.completion_evidence == 'key-item:Something Else',
        'an action that already names its own evidence is left alone');
end

print(('claims: %d passed, %d failed  (%d id lookups)'):format(passes, failures, lookups));
if (failures > 0) then os.exit(1); end

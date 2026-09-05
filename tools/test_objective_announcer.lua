-- Does the mission category TELL the player what changed?
--
-- Until 2026-08-22 it did not. modules/mission_quest_navigation.lua contained no
-- speak() call at all: a completed step, a finished mission and a newly accepted
-- one all ended at on_objective_interaction_progress_changed(kind, cancelled),
-- which speaks only when cancelled == true. The list was marked dirty, rebuilt,
-- and nothing was said.
--
-- The contract these claims pin was authored by sol. Two of its guards are the
-- reason it is not just "say something": never promise a key that cannot
-- deliver, and never infer that a mission is complete because its last guide
-- step was.
--
--   luajit tools/test_objective_announcer.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;

local A = dofile(ADDON .. '/modules/objective_announcer.lua');

local claims, failed = 0, 0;
local function claim(ok, text)
    claims = claims + 1;
    print((ok and '  ok   %s' or '  FAIL %s'):format(text));
    if (not ok) then failed = failed + 1; end
end
local function says(transition, expected, text)
    local actual = A.sentence(transition);
    claim(actual == expected, ('%s\n         got: %s'):format(text, actual));
end
local function contains(transition, needle, text)
    claim(tostring(A.sentence(transition)):find(needle, 1, true) ~= nil,
        ('%s\n         got: %s'):format(text, A.sentence(transition)));
end
local function lacks(transition, needle, text)
    claim(tostring(A.sentence(transition)):find(needle, 1, true) == nil,
        ('%s\n         got: %s'):format(text, A.sentence(transition)));
end

print('A completed step names what is next, and never starts the route:');
says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Click on it to receive the key item Lost document',
    route = A.ROUTE.FULL,
}, 'Objective complete. Next: Click on it to receive the key item Lost document. Press I to start navigation.',
    'an ordinary step completing');

says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Talk to the NPC Zantaviat just inside the zone',
    route = A.ROUTE.FULL,
    route_stopped = true,
}, 'Objective complete. Navigation stopped. Next: Talk to the NPC Zantaviat just inside the zone. Press I to start navigation.',
    'and it says so when the route it owned was stopped');

print('');
print('It never promises a key that cannot deliver:');
says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Kill Goblins in Batallia Downs to obtain the key item Bowl of bland Goblin salad',
    route = A.ROUTE.ZONE_ONLY,
    zone_name = 'Batallia Downs',
}, 'Objective complete. Next: Kill Goblins in Batallia Downs to obtain the key item Bowl of bland Goblin salad. Press I to navigate to Batallia Downs. The guide does not say where inside it.',
    'a zone-only step offers the zone and says the guide stops there');

says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Trade all three items to your Moogle in your home nation Mog House',
    route = A.ROUTE.UNAVAILABLE,
}, 'Objective complete. Next: Trade all three items to your Moogle in your home nation Mog House. No route is available for this objective.',
    'a step with no route says so instead of telling the player to press I');

says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = '',
    route = A.ROUTE.UNAVAILABLE,
}, 'Objective complete. The next objective is not described in the guide.',
    'and a step the guide does not describe is still reported as a completion');

print('');
print('A choice is neither a route nor a refusal:');
says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Examine a Home Point in Windurst Waters',
    route = A.ROUTE.CHOICE,
    route_choice = { count = 4, stage = 'physical' },
}, 'Objective complete. Next: Examine a Home Point in Windurst Waters. Several indexed matches fit this objective. Press I to choose from 4 locations.',
    'four places in one zone are counted and offered, never picked between');

says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Examine the ??? in Qufim Island',
    route = A.ROUTE.CHOICE,
    route_choice = { count = 3, stage = 'physical', unbound_square = 'G-6' },
}, 'Objective complete. Next: Examine the ??? in Qufim Island. The guide gives square G-6, but it is not linked to one indexed point. Press I to choose from 3 locations.',
    'a square the guide printed is spoken even though we cannot bind it to a point');

says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Talk to Halver',
    route = A.ROUTE.CHOICE,
    route_choice = { count = 2, stage = 'zone', unreachable = 1 },
}, 'Objective complete. Next: Talk to Halver. The guide does not identify which one. Press I to choose from 2 reachable places. 1 other indexed place cannot currently be routed from here.',
    'a cross-zone choice says how many are reachable AND how many are not');

says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Talk to Halver',
    route = A.ROUTE.CHOICE,
    route_choice = { count = 1, stage = 'zone', unreachable = 2 },
}, 'Objective complete. Next: Talk to Halver. One indexed place is reachable from here; 2 others cannot currently be routed. Press I to start navigation.',
    'and one reachable candidate still admits the ones it cannot reach');

says({
    type = A.TRANSITIONS.OBJECTIVE,
    instruction = 'Talk to Naja Salaheem',
    route = A.ROUTE.CHOICE,
    route_choice = { count = 3, stage = 'mixed' },
}, 'Objective complete. Next: Talk to Naja Salaheem. Several possible locations are indexed. Press I to choose from 3 reachable choices.',
    'a mixed here-and-elsewhere choice is described as choices, not as one place');

lacks({ type = A.TRANSITIONS.OBJECTIVE, instruction = 'Talk to Halver',
    route = A.ROUTE.CHOICE, route_choice = { count = 3, stage = 'zone' } },
    'Press I to start navigation',
    'stage one never tells the player that pressing I starts walking');

print('');
print('The last guide step is not the mission, and is not the last of the guide:');
-- Revised 2026-08-29. This branch used to say "Objective complete. No further
-- guide objectives.", and BOTH halves could be false at once. Running out of
-- compact actions proves only that AccessXI has no next action to point at.
-- Live that day, Below the Arks said it while BG Wiki's page still had four
-- sentences to go, the first being "You must now complete each of the three
-- Promyvions" -- and the player, hearing the objective declared complete and
-- then shown three steps they had already done, asked what they were meant to
-- be doing. The continuation is supplied by the caller; an objective whose page
-- really does stop where its actions stop passes an empty one and the sentence
-- reads exactly as it did before, minus the false claim.
says({
    type = A.TRANSITIONS.FINAL_OBJECTIVE,
    route = A.ROUTE.UNAVAILABLE,
}, 'Recorded steps complete. Waiting for the mission to update.',
    'running out of guide steps waits for the server, it does not claim completion');
says({
    type = A.TRANSITIONS.FINAL_OBJECTIVE,
    continuation = 'BG Wiki continues: You must now complete each of the three Promyvions.',
    route = A.ROUTE.UNAVAILABLE,
}, 'Recorded steps complete. BG Wiki continues: You must now complete each of the '
    .. 'three Promyvions. Waiting for the mission to update.',
    'and when the guide has more to say, it is said, attributed to the page that said it');
lacks({ type = A.TRANSITIONS.FINAL_OBJECTIVE }, 'Mission complete',
    'it never says the mission is complete on its own evidence');
lacks({ type = A.TRANSITIONS.FINAL_OBJECTIVE }, 'Objective complete',
    'nor that the objective is, which the cursor cannot know either');
lacks({ type = A.TRANSITIONS.FINAL_OBJECTIVE }, 'No further guide objectives',
    'and it no longer claims the guide is finished when only the cursor is');
-- A QUEST IS NOT A MISSION. One sentence served both, so a quest that ran out
-- of compact actions was told to wait for "the mission" to update (sol found
-- this reading the repair). The reducer already stamps the category.
says({ type = A.TRANSITIONS.FINAL_OBJECTIVE, category = 'quest' },
    'Recorded steps complete. Waiting for the quest to update.',
    'a quest is told to wait for the quest');
says({ type = A.TRANSITIONS.FINAL_OBJECTIVE, category = 'mission' },
    'Recorded steps complete. Waiting for the mission to update.',
    'and a mission for the mission');

print('');
print('Mission-level transitions:');
says({
    type = A.TRANSITIONS.MISSION_COMPLETE,
    mission = 'The Davoi Report',
}, 'Objective complete. Mission complete: The Davoi Report.',
    'a confirmed completion');
says({
    type = A.TRANSITIONS.MISSION_COMPLETE,
    mission = 'The Davoi Report',
    objective_seen = false,
}, 'Mission complete: The Davoi Report.',
    'and it drops "Objective complete" when no step of ours was seen to finish');

says({
    type = A.TRANSITIONS.MISSION_SUCCESSOR,
    previous_mission = 'The Davoi Report',
    mission = 'Journey Abroad',
    instruction = 'Talk to any Gate Guard',
    route = A.ROUTE.FULL,
}, 'Objective complete. Mission complete: The Davoi Report. New mission accepted: Journey Abroad. First objective: Talk to any Gate Guard. Press I to start navigation.',
    'completion and its proven successor coalesce into ONE sentence, not three');

says({
    type = A.TRANSITIONS.MISSION_ACCEPTED,
    mission = 'Journey Abroad',
    instruction = 'Talk to any Gate Guard',
    route = A.ROUTE.FULL,
}, 'New mission accepted: Journey Abroad. First objective: Talk to any Gate Guard. Press I to start navigation.',
    'a mission accepted with no predecessor');

says({
    type = A.TRANSITIONS.MISSION_CHANGED,
    previous_mission = 'The Davoi Report',
    mission = 'The Rescue Drill',
    instruction = 'Talk to any Gate Guard',
    route = A.ROUTE.FULL,
}, 'Active mission changed from The Davoi Report to The Rescue Drill. First objective: Talk to any Gate Guard. Press I to start navigation.',
    'an UNPROVEN replacement reports what was observed and claims no completion');
lacks({
    type = A.TRANSITIONS.MISSION_CHANGED,
    previous_mission = 'The Davoi Report',
    mission = 'The Rescue Drill',
}, 'complete', 'and never uses the word complete for it');

print('');
print('Nothing here starts a route -- the player decides when:');
for _, kind in ipairs({ A.TRANSITIONS.OBJECTIVE, A.TRANSITIONS.MISSION_SUCCESSOR,
    A.TRANSITIONS.MISSION_ACCEPTED, A.TRANSITIONS.MISSION_CHANGED }) do
    local text = A.sentence({ type = kind, mission = 'M', previous_mission = 'P',
        instruction = 'do the thing', route = A.ROUTE.FULL });
    claim(text:find('Press I', 1, true) ~= nil and text:find('Navigating', 1, true) == nil
        and text:find('Starting route', 1, true) == nil,
        ('%s offers the key and does not take it'):format(kind));
end

print('');
print('The same change said once, a different change never swallowed:');
local base = {
    identity = 'testchar:1', mission_epoch = 7, type = A.TRANSITIONS.OBJECTIVE,
    previous_mission = "mission:San d'Oria:5", mission = "mission:San d'Oria:5",
    previous_step_id = "mission:San d'Oria:5:step-011",
    step_id = "mission:San d'Oria:5:step-013",
};
local repeated = {};
for key in pairs(base) do repeated[key] = base[key]; end
claim(A.dedup_key(base) == A.dedup_key(repeated),
    'four identical reducer emissions produce one key -- live it fired four times in eight seconds');
local next_step = {};
for key in pairs(base) do next_step[key] = base[key]; end
next_step.previous_step_id = "mission:San d'Oria:5:step-013";
next_step.step_id = "mission:San d'Oria:5:step-014";
claim(A.dedup_key(base) ~= A.dedup_key(next_step),
    'the very next step is a different key, even arriving immediately after');
local reaccepted = {};
for key in pairs(base) do reaccepted[key] = base[key]; end
reaccepted.mission_epoch = 8;
claim(A.dedup_key(base) ~= A.dedup_key(reaccepted),
    'and repeating a mission is a new instance, so it may be announced again');
local other_character = {};
for key in pairs(base) do other_character[key] = base[key]; end
other_character.identity = 'someoneelse:1';
claim(A.dedup_key(base) ~= A.dedup_key(other_character),
    'another character never inherits what this one was told');
claim(A.dedup_key(nil) == '' and A.dedup_key('x') == '',
    'a malformed transition yields no key, so it can never be silently deduped away');

print('');
print('One moment, one sentence -- the richer description wins:');
claim(A.outranks({ type = A.TRANSITIONS.MISSION_SUCCESSOR }, { type = A.TRANSITIONS.OBJECTIVE }),
    'a proven successor replaces a bare objective completion waiting to be said');
claim(A.outranks({ type = A.TRANSITIONS.MISSION_COMPLETE }, { type = A.TRANSITIONS.FINAL_OBJECTIVE }),
    'and a confirmed mission completion replaces "waiting for the mission to update"');
claim(not A.outranks({ type = A.TRANSITIONS.OBJECTIVE }, { type = A.TRANSITIONS.MISSION_SUCCESSOR }),
    'but never the other way round');
claim(A.outranks({ type = A.TRANSITIONS.OBJECTIVE }, nil),
    'with nothing waiting, anything is worth saying');

print('');
print(('claims=%d failed=%d'):format(claims, failed));
os.exit(failed == 0 and 0 or 1);

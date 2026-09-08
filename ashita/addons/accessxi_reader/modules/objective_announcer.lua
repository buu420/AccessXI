-- What the player hears when a mission moves.
--
-- Why this exists (2026-08-22). The mission category updated itself silently.
-- `modules/mission_quest_navigation.lua` contained no `speak(` call at all:
-- every advance -- step completed, mission replaced, next mission accepted --
-- ended at `on_objective_interaction_progress_changed(kind, cancelled)`, which
-- speaks only when `cancelled == true`. So the list was marked dirty, rebuilt,
-- and nothing was said. The player found out by opening the menu and arrowing
-- to it. Asked why a guide browser was needed at all, the user answered that it
-- should not be: "there is already a mission category, it's supposed to update
-- automatically when you complete a step of a mission, and update automatically
-- when you complete the mission, and update when you accept the next mission".
--
-- And it stays MANUAL. His words: "make it say objective complete. Then, tell
-- the player to start navigation to the next route to the next objective. This
-- way everything is manual. In case they maybe don't want to start that
-- objective yet or prepare for it." Nothing here starts a route. The next
-- instruction is named because deciding whether to prepare requires knowing
-- what is next.
--
-- Contract authored by sol; two of its guards are theirs and are load-bearing:
-- never promise "Press I" when no route exists, and never infer that a mission
-- is complete merely because its last guide step was.
--
-- Pure: every input arrives in the transition table, so the same code runs
-- under the addon and under an offline LuaJIT harness.

local M = {};

M.TRANSITIONS = {
    OBJECTIVE_PROGRESS = 'objective-progress', -- part of a distinct set completed
    OBJECTIVE = 'objective',                 -- an intermediate guide step completed
    FINAL_OBJECTIVE = 'final-objective',     -- the last guide step completed; mission not yet confirmed
    MISSION_COMPLETE = 'mission-complete',   -- native state confirms the mission finished
    MISSION_SUCCESSOR = 'mission-successor', -- completed, and the proven next mission is now active
    MISSION_ACCEPTED = 'mission-accepted',   -- a mission became active with no completed predecessor
    MISSION_CHANGED = 'mission-changed',     -- the active mission changed and succession is NOT proven
};

M.ROUTE = {
    FULL = 'full',
    ZONE_ONLY = 'zone-only',
    -- Several places fit the objective and the guide does not say which. The
    -- key opens a list; it does not start walking (sol).
    CHOICE = 'choice',
    UNAVAILABLE = 'unavailable',
};

local function clean(value)
    value = tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('%s+', ' ');
    return (value:gsub('^%s+', ''):gsub('%s+$', ''));
end

-- Sentences are joined, not concatenated: each part ends in exactly one stop so
-- a screen reader gets the pause it needs between them.
local function sentence(value)
    value = clean(value);
    if (value == '') then return ''; end
    if (not value:find('[%.%?!]$')) then value = value .. '.'; end
    return value;
end

local function join(parts)
    local out = {};
    for _, part in ipairs(parts) do
        part = clean(part);
        if (part ~= '') then out[#out + 1] = part; end
    end
    return table.concat(out, ' ');
end

-- NEVER PROMISE A KEY THAT CANNOT DELIVER (sol). "Press I to start navigation"
-- against a step with no route is the same false instruction as "Press G for
-- the source guide" was while nothing read G.
-- STAGE ONE OF A CHOICE IS NOT A ROUTE. "Press I to start navigation" would
-- promise that one place had been chosen; what we actually have is several,
-- and the choosing is the player's. Say how many, say what the guide did and
-- did not settle, and count the candidates we cannot reach at all rather than
-- quietly leaving them out of the number (sol's stage-one contract).
function M.choice_suffix(choice)
    choice = type(choice) == 'table' and choice or {};
    local count = tonumber(choice.count) or 0;
    local unreachable = tonumber(choice.unreachable) or 0;
    local square = clean(choice.unbound_square);
    local stage = clean(choice.stage);
    local plural = unreachable == 1 and '' or 's';
    if (stage == 'all-members' and count > 0) then
        return ('Complete all %d locations. Press I to choose an unfinished location.'):format(count);
    end;
    if (stage == 'search' and count > 0) then
        local item = clean(choice.completion_item);
        if (item == '') then item = 'the requested item'; end
        return ('Search %d locations until you obtain %s. Press I to choose a location to search.'):format(count, item);
    end

    if (count <= 1) then
        if (unreachable > 0) then
            return ('One indexed place is reachable from here; %d other%s cannot currently be routed. Press I to start navigation.')
                :format(unreachable, plural);
        end
        return 'Press I to start navigation.';
    end

    local lead, noun;
    if (square ~= '') then
        lead = ('The guide gives square %s, but it is not linked to one indexed point.'):format(square);
        noun = 'locations';
    elseif (stage == 'zone') then
        lead = 'The guide does not identify which one.';
        noun = 'reachable places';
    elseif (stage == 'mixed') then
        lead = 'Several possible locations are indexed.';
        noun = 'reachable choices';
    else
        lead = 'Several indexed matches fit this objective.';
        noun = 'locations';
    end

    return join({
        lead,
        ('Press I to choose from %d %s.'):format(count, noun),
        unreachable > 0
            and ('%d other indexed place%s cannot currently be routed from here.'):format(unreachable, plural)
            or '',
    });
end

function M.route_suffix(capability, zone_name, choice)
    capability = clean(capability);
    if (capability == M.ROUTE.CHOICE) then
        return M.choice_suffix(choice);
    end
    if (capability == M.ROUTE.FULL) then
        return 'Press I to start navigation.';
    end
    if (capability == M.ROUTE.ZONE_ONLY) then
        zone_name = clean(zone_name);
        if (zone_name == '') then
            return 'Press I to start navigation. The guide does not say exactly where.';
        end
        return ('Press I to navigate to %s. The guide does not say where inside it.'):format(zone_name);
    end
    return 'No route is available for this objective.';
end

-- The transition table:
--   type              one of M.TRANSITIONS
--   instruction       the guide's own sentence for the step now current
--   route             one of M.ROUTE, describing that step
--   zone_name         the zone, when route is zone-only
--   route_stopped     true when the route that was running belonged to the step
--                     that just completed (an unrelated route is never stopped)
--   objective_seen    false when nothing completed and only native state moved
--   mission           the mission now active
--   previous_mission  the mission that was active before
function M.sentence(transition)
    if (type(transition) ~= 'table') then return ''; end
    local kind = clean(transition.type);
    local instruction = clean(transition.instruction);
    local stopped = transition.route_stopped == true and 'Navigation stopped.' or '';
    local suffix = M.route_suffix(transition.route, transition.zone_name, transition.route_choice);
    local mission = clean(transition.mission);
    local previous = clean(transition.previous_mission);
    if (kind == M.TRANSITIONS.OBJECTIVE_PROGRESS) then
        local done = tonumber(transition.completed_count) or 0;
        local total = tonumber(transition.required_count) or 0;
        local next_route = transition.distinct_interactions and transition.route ~= M.ROUTE.UNAVAILABLE
            and 'Press I to choose an unfinished location.' or suffix;
        return join({('Objective progress: %d of %d complete.'):format(done, total), stopped,
            sentence(instruction), ('%d remaining.'):format(math.max(0,total-done)), next_route});
    end;

    if (kind == M.TRANSITIONS.OBJECTIVE) then
        if (instruction == '') then
            -- A step we cannot describe is still a step that completed. Say so
            -- rather than inventing one, and never promise a key for it.
            return join({ 'Objective complete.', stopped,
                'The next objective is not described in the guide.' });
        end
        return join({ 'Objective complete.', stopped,
            ('Next: %s'):format(sentence(instruction)), suffix });
    end

    -- THE LAST GUIDE STEP IS NOT THE MISSION (sol). The guide running out says
    -- nothing about what the server thinks; claiming completion here would
    -- announce a mission finished that the player still has to hand in.
    if (kind == M.TRANSITIONS.FINAL_OBJECTIVE) then
        -- "NO FURTHER GUIDE OBJECTIVES" WAS FALSE, AND SO WAS "OBJECTIVE
        -- COMPLETE".
        --
        -- Running out of compact actions proves one thing: this addon has no
        -- next action to point at. It does not prove the objective finished,
        -- and it certainly does not prove the guide has nothing left -- live
        -- 2026-08-29 Below the Arks said this while BG Wiki still had four
        -- sentences to go, the first of which was "You must now complete each
        -- of the three Promyvions". The player heard the addon declare the
        -- objective complete and then show them three steps they had already
        -- done, and asked what they were supposed to do.
        -- A QUEST IS NOT A MISSION. One sentence served both, so every quest
        -- that ran out of compact actions was told to wait for "the mission"
        -- to update (sol). The reducer already stamps which category this is.
        local continuation = clean(transition.continuation);
        local noun = clean(transition.category):lower() == 'quest' and 'quest' or 'mission';
        return join({ 'Recorded steps complete.', stopped, continuation,
            ('Waiting for the %s to update.'):format(noun) });
    end

    if (kind == M.TRANSITIONS.MISSION_COMPLETE) then
        local opening = transition.objective_seen == false and '' or 'Objective complete.';
        return join({ opening, stopped, ('Mission complete: %s'):format(sentence(mission)) });
    end

    if (kind == M.TRANSITIONS.MISSION_SUCCESSOR) then
        local opening = transition.objective_seen == false and '' or 'Objective complete.';
        return join({ opening, stopped,
            ('Mission complete: %s'):format(sentence(previous)),
            ('New mission accepted: %s'):format(sentence(mission)),
            instruction ~= '' and ('First objective: %s'):format(sentence(instruction)) or '',
            instruction ~= '' and suffix or '' });
    end

    if (kind == M.TRANSITIONS.MISSION_ACCEPTED) then
        return join({ ('New mission accepted: %s'):format(sentence(mission)),
            instruction ~= '' and ('First objective: %s'):format(sentence(instruction)) or '',
            instruction ~= '' and suffix or '' });
    end

    -- Succession unproven: report the change as observed, claim nothing about
    -- why it happened. A mission abandoned, repeated or swapped lands here.
    if (kind == M.TRANSITIONS.MISSION_CHANGED) then
        return join({ ('Active mission changed from %s to %s.'):format(
                previous ~= '' and previous or 'an unknown mission',
                mission ~= '' and mission or 'an unknown mission'),
            instruction ~= '' and ('First objective: %s'):format(sentence(instruction)) or '',
            instruction ~= '' and suffix or '' });
    end

    return '';
end

-- DEDUP BY MEANING, NOT BY CLOCK (sol). The reducer recomputes the same state
-- freely -- live, `mission active context complete` appeared four times in
-- eight seconds -- so a time window would either drop a real second transition
-- or let a repeat through depending only on scheduling. The key is the
-- transition itself, and it holds for the whole mission instance.
function M.dedup_key(transition)
    if (type(transition) ~= 'table') then return ''; end
    local key = table.concat({
        clean(transition.identity):lower(),
        tostring(tonumber(transition.mission_epoch) or 0),
        clean(transition.type),
        clean(transition.previous_mission),
        clean(transition.previous_step_id),
        clean(transition.mission),
        clean(transition.step_id),
    }, '|');
    if transition.type == M.TRANSITIONS.OBJECTIVE_PROGRESS then
        key = key .. '|' .. tostring(tonumber(transition.completed_count) or 0);
    end;
    return key;
end

-- Which of two transitions describes more of the same moment. Objective
-- completion, native completion and successor acceptance arrive as separate
-- signals within a breath of each other; the contract coalesces them into one
-- richer sentence rather than speaking three.
local COALESCE_RANK = {
    [M.TRANSITIONS.OBJECTIVE] = 1,
    [M.TRANSITIONS.FINAL_OBJECTIVE] = 2,
    [M.TRANSITIONS.MISSION_CHANGED] = 3,
    [M.TRANSITIONS.MISSION_ACCEPTED] = 4,
    [M.TRANSITIONS.MISSION_COMPLETE] = 5,
    [M.TRANSITIONS.MISSION_SUCCESSOR] = 6,
};

function M.outranks(candidate, held)
    if (type(held) ~= 'table') then return true; end
    if (type(candidate) ~= 'table') then return false; end
    return (COALESCE_RANK[clean(candidate.type)] or 0)
        > (COALESCE_RANK[clean(held.type)] or 0);
end

M.COALESCE_MS = 1500;

if (type(accessxi) == 'table') then
    accessxi.objective_announcer = M;
end
return M;

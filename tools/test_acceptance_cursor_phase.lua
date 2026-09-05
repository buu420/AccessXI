-- AN ACTIVE MISSION MUST NOT START ON THE STEP THAT UNLOCKS IT.
--
-- Live 2026-08-29 the player accepted mission:San d'Oria:11 "Infiltrate Davoi" and the cursor
-- did not move for two days, parked on step-002 -- "Trade enough Crystals (1+) to the Conquest
-- NPC to raise your Rank bar and unlock the Mission". A precondition the game had already
-- proved satisfied, whose target is in no catalogue, so it refused every time:
--
--   2026-08-31 19:11:26 objective step refused native="mission:San d'Oria:11"
--       step="mission:San d'Oria:11:step-002" reason=entity-absent
--       detail="I have no indexed location for Conquest NPC, Crystals"
--
-- Their words: "I feel like I'm going to be forced to do every mission to make sure it works
-- because every mission I do doesn't work." So this is a gate over all 72 nation missions, not
-- a claim about one.
--
-- THE TEST THAT MATTERS is not "does the landing resolve". An action ordered at or before
-- acceptance is work the game has already proved done, so routing to it is wrong however well
-- it routes -- counting only resolvability credits the old behaviour for sending the player to
-- raise rank points on a mission they are already holding. Measured both ways:
--
--   actionable alone            before 56, after 52
--   actionable AND after accept before 21, after 52   <-- the real one
--
-- Every matcher below is LIFTED VERBATIM from the deployed module. A companion measurement
-- that used its own hand-written matcher reported a mission landing somewhere it does not,
-- which is the mistake this project keeps making.
--
--   luajit tools/test_acceptance_cursor_phase.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
local LIST = false;
for i = 1, #arg do if (arg[i] == '--list') then LIST = true; end end

T = function (t) t = t or {}; t.len = function (s) return #s; end;
    t.append = function (s, v) s[#s + 1] = v; end; return t; end
string.fmt = string.format;

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end

-- ----------------------------------------------------- the SHIPPED matchers
local src = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
local function lift(header)
    local from = src:find(header, 1, true);
    assert(from ~= nil, 'could not lift: ' .. header);
    local to = src:find('\nend\n', from, true) or src:find('\nend;\n', from, true);
    assert(to ~= nil, 'unterminated: ' .. header);
    return src:sub(from, to + 5);
end
clean = function (value) return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
-- source_name_key normalises spacing around punctuation; the guide writes
-- "Door: Papal Chambers" and the catalogue "Door:Papal Chambers".
source_name_key = function (value)
    local key = clean(value):lower();
    key = key:gsub('%s*([:,])%s*', '%1');
    key = key:gsub('%s+', ' ');
    return key;
end
assert(load(lift('local function exact_gate_guard_role(step)'):gsub('^local ', ''), 'role'))();
assert(load(lift('local function mission_acceptance_instruction(step)'):gsub('^local ', ''), 'instr'))();

-- The real two-pass resolver, minus only its data source.
local function acceptance_step(steps)
    for _, step in ipairs(steps) do
        local action = clean(step.action):lower();
        if (action == 'talk' and exact_gate_guard_role(step)
            and mission_acceptance_instruction(step)) then
            return step, 'strict';
        end
    end
    local relaxed = nil;
    for _, step in ipairs(steps) do
        local action = clean(step.action):lower();
        if (action ~= 'travel' and exact_gate_guard_role(step)
            and mission_acceptance_instruction(step)) then
            relaxed = step;
        end
    end
    return relaxed, relaxed ~= nil and 'relaxed' or 'none';
end

-- ---------------------------------------------------------------- real data
local reconciled, progression = {}, {};
local function each_module(pattern, sink)
    local pipe = io.popen('dir /b "' .. ADDON:gsub('/', '\\') .. '\\modules\\' .. pattern .. '"');
    for name in (pipe and pipe:lines() or function () return nil; end) do
        local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. (name:gsub('%.lua$', '')) .. '.lua');
        if (ok and type(tbl) == 'table') then sink(tbl); end
    end
    if (pipe) then pipe:close(); end
end
each_module('mission_quest_reconcile_mission_*.lua', function (tbl)
    for key, entry in pairs(tbl) do
        if (type(entry) == 'table' and type(entry.steps) == 'table') then reconciled[key] = entry; end
    end
end);
each_module('mission_quest_progression_mission_*.lua', function (tbl)
    local objectives = type(tbl.objectives) == 'table' and tbl.objectives or tbl;
    for key, entry in pairs(objectives) do
        if (type(entry) == 'table' and type(entry.progression_actions) == 'table') then
            progression[key] = entry;
        end
    end
end);

-- Zone NAMES are a separate namespace from catalogue row names, and a target like
-- "Metalworks" or "East Ronfaure" is a perfectly routable zone that appears in no row.
-- Counting only rows made the first version of this file report the repair as a net
-- regression -- 54 actionable before, 46 after -- which was the measurement being wrong,
-- not the repair.
local zone_names = {};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv', 'r'));
    local header = nil;
    for line in f:lines() do
        if (line:sub(1, 1) ~= '#' and line:match('%S')) then
            local c = {};
            for field in (line .. '	'):gmatch('([^	]*)	') do c[#c + 1] = field; end
            if (header == nil) then header = c;
            else
                for i, key in ipairs(header) do
                    if (key == 'from_name' or key == 'to_name') then
                        local n = source_name_key(c[i]);
                        if (n ~= '') then zone_names[n] = true; end
                    end
                end
            end
        end
    end
    f:close();
end

local catalogue = {};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-destinations.tsv', 'r'));
    for line in f:lines() do
        if (line:sub(1, 1) ~= '#' and line:match('%S')) then
            local c = {};
            for field in (line .. '\t'):gmatch('([^\t]*)\t') do c[#c + 1] = field; end
            local name = source_name_key(c[2]);
            if (name ~= '') then catalogue[name] = true; end
        end
    end
    f:close();
end

-- An action the player can act on: a catalogue row by name, a destination zone, a compact
-- catalogue of its own, or a gate-guard role the addon resolves from its own table.
local function landing_is_actionable(action, step)
    if (type(action) ~= 'table') then return false, 'no action'; end
    local target = source_name_key(action.target);
    if (target ~= '' and catalogue[target]) then return true, 'catalogue row'; end
    if ((tonumber(action.destination_zone_id) or 0) > 0) then return true, 'zone id'; end
    if (target ~= '' and zone_names[target]) then return true, 'zone name'; end
    if (target ~= '') then
        -- "Conquest NPC to raise your Rank bar and unlock the Mission" is a sentence the
        -- generator kept as a target; a zone name inside a longer target still routes.
        for name in pairs(zone_names) do
            if (#name > 6 and target:find(name, 1, true)) then return true, 'zone name in target'; end
        end
    end
    if (type(action.catalogue) == 'table' and #action.catalogue > 0) then return true, 'compact catalogue'; end
    if (type(step) == 'table' and exact_gate_guard_role(step)) then return true, 'gate guard role'; end
    for _, zone in ipairs(type(action.zones) == 'table' and action.zones or {}) do
        if (catalogue[source_name_key(zone)]) then return true, 'named zone'; end
    end
    return false, 'unresolvable';
end

local nation = { ["mission:San d'Oria:"] = true, ['mission:Bastok:'] = true,
                 ['mission:Windurst:'] = true };
local function is_nation(key)
    for prefix in pairs(nation) do
        if (key:sub(1, #prefix) == prefix) then return true; end
    end
    return false;
end

local total, with_acceptance = 0, 0;
local by_strict, by_relaxed = 0, 0;
local moved, same = 0, 0;
local land_ok, land_bad = 0, 0;
local before_ok, before_bad = 0, 0;
local bad, improved = {}, {};
local before_good, after_good = 0, 0;
local pre_acceptance_after = 0;
local net_gain, net_loss = {}, {};

for key, entry in pairs(reconciled) do
    local prog = progression[key];
    local actions = type(prog) == 'table' and prog.progression_actions or nil;
    if (is_nation(key) and type(actions) == 'table' and #actions > 0) then
        total = total + 1;
        local acceptance, how = acceptance_step(entry.steps);
        if (acceptance ~= nil) then
            with_acceptance = with_acceptance + 1;
            if (how == 'strict') then by_strict = by_strict + 1; else by_relaxed = by_relaxed + 1; end

            -- BEFORE: only a strict match could move it, and only via an action carrying that
            -- step's id.
            local before_index = 1;
            if (how == 'strict') then
                local passed = false;
                for index, action in ipairs(actions) do
                    if (clean(action.step_id) == clean(acceptance.stable_step_id)) then passed = true;
                    elseif (passed) then before_index = index; break; end
                end
            end
            -- AFTER: strictly past the acceptance step's order.
            local after_index = 1;
            local ord = tonumber(acceptance.order) or 0;
            for index, action in ipairs(actions) do
                if ((tonumber(action.step_order) or 0) > ord) then after_index = index; break; end
            end

            local function step_of(action)
                for _, s in ipairs(entry.steps) do
                    if (clean(s.stable_step_id) == clean(type(action) == 'table' and action.step_id or '')) then
                        return s;
                    end
                end
                return nil;
            end
            local before_ok_flag = landing_is_actionable(actions[before_index], step_of(actions[before_index]));
            local after_ok_flag, why = landing_is_actionable(actions[after_index], step_of(actions[after_index]));
            if (before_ok_flag) then before_ok = before_ok + 1; else before_bad = before_bad + 1; end
            if (after_ok_flag) then land_ok = land_ok + 1; else land_bad = land_bad + 1; end

            -- ACTIONABLE IS NOT ENOUGH. An action ordered at or before acceptance is work the
            -- game has already proved done, so routing to it is wrong however well it routes.
            -- Counting only "does it resolve" credits the old behaviour for sending the player
            -- to raise rank points on a mission they are already holding.
            local before_step_ord = 0;
            for _, s in ipairs(entry.steps) do
                if (clean(s.stable_step_id) == clean(actions[before_index].step_id)) then
                    before_step_ord = tonumber(s.order) or 0;
                end
            end
            local before_phase_ok = before_step_ord > ord;
            if (before_ok_flag and before_phase_ok) then before_good = before_good + 1; end
            if (after_ok_flag) then after_good = after_good + 1; end
            do
                local after_step_ord = 0;
                for _, s in ipairs(entry.steps) do
                    if (clean(s.stable_step_id) == clean(actions[after_index].step_id)) then
                        after_step_ord = tonumber(s.order) or 0;
                    end
                end
                if (after_step_ord > 0 and after_step_ord <= ord) then
                    pre_acceptance_after = pre_acceptance_after + 1;
                end
            end
            if ((after_ok_flag) and not (before_ok_flag and before_phase_ok)) then
                net_gain[#net_gain + 1] = ('%-40s %s -> actionable, after acceptance'):fmt(
                    key, before_phase_ok and 'was unresolvable' or 'was pre-acceptance');
            elseif ((before_ok_flag and before_phase_ok) and not after_ok_flag) then
                net_loss[#net_loss + 1] = ('%-40s was "%s" -> now "%s"'):fmt(key,
                    trim(actions[before_index].instruction):sub(1, 32),
                    trim(actions[after_index].instruction):sub(1, 32));
            end

            if (after_index ~= before_index) then
                moved = moved + 1;
                if (after_ok_flag and not before_ok_flag) then
                    improved[#improved + 1] = ('%-40s -> "%s" (%s)'):fmt(
                        key, trim(actions[after_index].instruction):sub(1, 44), why);
                end
            else
                same = same + 1;
            end
            if (not after_ok_flag) then
                bad[#bad + 1] = ('%-40s stays on "%s" target="%s"'):fmt(
                    key, trim(actions[after_index].instruction):sub(1, 44),
                    trim(actions[after_index].target));
            end
        end
    end
end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end

claim(total == 72, ('all 72 nation missions load, got %d'):fmt(total));
claim(with_acceptance >= 60,
    ('and the addon can see an acceptance step in %d of them'):fmt(with_acceptance));
claim(by_relaxed > 0,
    ('%d of those are found only because the relaxed pass reads prose'):fmt(by_relaxed));

-- THE GATE. A repair that moved cursors without improving where they land would be churn;
-- one that improved some and broke others would be a trade nobody agreed to.
claim(after_good > before_good,
    ('more missions now start actionable AND after acceptance: %d -> %d'):fmt(
        before_good, after_good));
claim(#net_loss == 0,
    ('and NOT ONE regressed, got %d'):fmt(#net_loss));
for _, line in ipairs(net_loss) do print('       ' .. line); end

-- The mission the player is actually stuck on, by name.
local davoi = false;
for _, line in ipairs(improved) do
    if (line:find("mission:San d'Oria:11", 1, true) ~= nil) then davoi = true; end
end
claim(davoi, 'Infiltrate Davoi is one of them -- the mission they have been stuck on for two days');

-- And no cursor may land at or before acceptance any more. That is the invariant, not a count.
claim(pre_acceptance_after == 0,
    ('no nation mission still starts at or before its acceptance step, got %d'):fmt(
        pre_acceptance_after));

print('');
print(('acceptance cursor phase: %d passed, %d failed'):fmt(passed, failed));
os.exit(failed == 0 and 0 or 1);

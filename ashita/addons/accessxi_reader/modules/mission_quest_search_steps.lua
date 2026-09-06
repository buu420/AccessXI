-- Normalizes "check each of N until you get X" guide steps into one routable
-- search step plus one material action.
--
-- THE SHAPE THIS EXISTS FOR.
--
-- Windurst 1 step-018 reads "Now, head back out and check the six different
-- Ancient Magical Gizmos until you are given the key item Cracked Mana Orb."
-- Both source pages agree on it. It still reached the player as nothing at all:
-- the verb is `note` so the resolver declines it, the only entity is the REWARD
-- rather than the place, and the step has no compact progression action for an
-- identity binding to attach to. A player who watched the gate cutscene was
-- routed back to the gate forever.
--
-- This module reads the sentence the guide actually wrote, matches the plural
-- against the shipped catalogue, and emits the six exact identities. It does
-- not enable notes in general: a step is rewritten only when the sentence has
-- this shape AND every part of it resolves against real data.
--
-- WHAT IT DELIBERATELY DOES NOT DO.
--
--   * It never guesses which member holds the reward. The game assigns that
--     randomly per player, so the completion evidence is the key item and
--     nothing else -- required_count is 1, not N. Visiting all six proves
--     nothing.
--   * It owns no stage proof, no saved state and no progress inference.
--   * It never invents. Anything that does not resolve is refused with a named
--     reason in `search_refusal`, and the step is handed back untouched.
--   * It does not disturb ordinary duplicate-name steps, which remain a choice.
--
-- API
--   M.normalize_steps(steps, points, zone_id_for_name) -> copied steps
--   M.augment_actions(actions, normalized_steps)       -> copied actions
--
--   points(zone_id, name)      -> array of catalogue points, or nil
--   zone_id_for_name(name)     -> array of zone ids, or nil
--
-- Both entry points copy their input and are idempotent.

local M = {};

local function trim(value)
    return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''));
end

local function name_key(value)
    local key = trim(value):lower();
    key = key:gsub('%s*([:,])%s*', '%1');
    key = key:gsub('%s+', ' ');
    return key;
end

-- Only counts a guide would actually write out. A digit would be a different
-- sentence shape and is not accepted here rather than half-supported.
local NUMBER_WORDS = {
    two = 2, three = 3, four = 4, five = 5, six = 6,
    seven = 7, eight = 8, nine = 9, ten = 10, eleven = 11, twelve = 12,
};

-- A search set is a set of places to stand. An enemy is a fight, and folding
-- one into a search would tell a blind player to walk into it.
local EXCLUDED_KIND = { enemy = true, mob = true, nm = true, monster = true };

local function copy_list(list)
    local out = {};
    for i, v in ipairs(type(list) == 'table' and list or {}) do out[i] = v; end
    return out;
end

local function copy_table(source)
    local out = {};
    for k, v in pairs(type(source) == 'table' and source or {}) do
        if (type(v) == 'table') then
            local nested = {};
            for nk, nv in pairs(v) do nested[nk] = nv; end
            out[k] = nested;
        else
            out[k] = v;
        end
    end
    return out;
end

-- sentence ------------------------------------------------------------------

-- "do not check", "don't search", "never check". A negated instruction has the
-- same words in the same order as the real one, so it has to be excluded before
-- anything else is read out of it.
local function is_negated(text)
    local lowered = ' ' .. name_key(text) .. ' ';
    return lowered:find('%f[%w]do not%s+%a*%s*check%f[%W]') ~= nil
        or lowered:find('%f[%w]do not%s+%a*%s*search%f[%W]') ~= nil
        or lowered:find("%f[%w]don't%s+%a*%s*check%f[%W]") ~= nil
        or lowered:find("%f[%w]don't%s+%a*%s*search%f[%W]") ~= nil
        or lowered:find('%f[%w]never%s+check%f[%W]') ~= nil
        or lowered:find('%f[%w]never%s+search%f[%W]') ~= nil;
end

-- 'check|search [the] <number-word> different <plural> ... until ...'
--
-- ffxiclopedia writes the member locations inline -- "the six different Ancient
-- Magical Gizmos at Inner Horutoto Ruins Lily Tower G-8, G-9, ..." -- so the
-- plural has to be cut at the first ' at ' or comma, or the whole square list
-- ends up inside the name.
local function read_shape(text)
    local lowered = name_key(text);
    if (lowered == '') then return nil; end
    local number_word = lowered:match('%f[%w]check%s+the%s+(%a+)%s+different%f[%W]')
        or lowered:match('%f[%w]check%s+(%a+)%s+different%f[%W]')
        or lowered:match('%f[%w]search%s+the%s+(%a+)%s+different%f[%W]')
        or lowered:match('%f[%w]search%s+(%a+)%s+different%f[%W]');
    local expected = NUMBER_WORDS[number_word or ''];
    if (expected == nil) then return nil; end

    -- Read the plural from the ORIGINAL casing so the catalogue comparison has
    -- something to hand back verbatim.
    local original = trim(tostring(text or ''):gsub('%s+', ' '));
    local after = original:match('[Dd]ifferent%s+(.*)$');
    if (after == nil) then return nil; end
    local plural = after:match('^(.-)%s+[Uu]ntil%f[%W]') or after;
    plural = plural:match('^(.-)%s+at%s') or plural;
    plural = plural:match('^(.-),') or plural;
    plural = trim(plural);
    if (plural == '') then return nil; end
    if (original:lower():find('%f[%w]until%f[%W]') == nil) then return nil; end
    return { expected_count = expected, plural = plural };
end

local function read_reward(text)
    local original = trim(tostring(text or ''):gsub('%s+', ' '));
    local reward = original:match('[Kk]ey item%s+([^%.;]+)');
    if (reward == nil) then return nil; end
    -- "...key item Cracked Mana Orb. It will be at a random Gizmo." already
    -- stops at the period; trailing clauses that use a comma are cut here.
    reward = reward:match('^(.-),') or reward;
    reward = trim(reward);
    if (reward == '') then return nil; end
    return reward;
end

-- Regular plurals only. An irregular plural is a different word and guessing a
-- stem for it would be inventing a catalogue name.
local function singular_candidates(plural)
    local out = { plural };
    if (plural:sub(-2):lower() == 'es') then out[#out + 1] = plural:sub(1, -3); end
    if (plural:sub(-1):lower() == 's') then out[#out + 1] = plural:sub(1, -2); end
    return out;
end

local function instruction_texts(step)
    local list = {};
    for _, field in ipairs({ 'bg_instruction', 'ffxiclopedia_instruction', 'primary_instruction' }) do
        local value = trim(step[field]);
        if (value ~= '') then list[#list + 1] = value; end
    end
    return list;
end

-- resolution ----------------------------------------------------------------

local function resolve_zone(step, zone_id_for_name)
    if (type(zone_id_for_name) ~= 'function') then
        return nil, 'zone-unknown', 'no zone resolver supplied';
    end
    local found, seen = {}, {};
    for _, zone_name in ipairs(type(step.zones) == 'table' and step.zones or {}) do
        if (trim(zone_name) ~= '') then
            for _, id in ipairs(zone_id_for_name(zone_name) or {}) do
                id = tonumber(id);
                if (id and id > 0 and not seen[id]) then
                    seen[id] = true; found[#found + 1] = id;
                end
            end
        end
    end
    if (#found == 0) then return nil, 'zone-unknown', 'no named zone resolved to an id'; end
    if (#found > 1) then return nil, 'zone-ambiguous', tostring(#found) .. ' zones matched'; end
    return found[1];
end

local function resolve_members(zone_id, candidate, points)
    if (type(points) ~= 'function') then return nil, nil; end
    local rows = points(zone_id, candidate);
    if (type(rows) ~= 'table' or #rows == 0) then return nil, nil; end
    local exact_name, ids, seen = nil, {}, {};
    for _, row in ipairs(rows) do
        if (name_key(row.name) == name_key(candidate)) then
            exact_name = exact_name or trim(row.name);
            if (not EXCLUDED_KIND[name_key(row.kind)]) then
                local id = trim(row.destination_id);
                if (id ~= '' and not seen[id]) then seen[id] = true; ids[#ids + 1] = id; end
            end
        end
    end
    if (exact_name == nil) then return nil, nil; end
    table.sort(ids);
    return exact_name, ids;
end

-- Returns search_set, or nil plus a named reason. Never partially applied.
local function build_search_set(step, points, zone_id_for_name)
    local texts = instruction_texts(step);
    if (#texts == 0) then return nil; end

    local shape, reward, matched_any = nil, nil, false;
    for _, text in ipairs(texts) do
        if (is_negated(text)) then
            return nil, 'negated-instruction', 'the instruction tells the player not to search';
        end
        local this_shape = read_shape(text);
        if (this_shape ~= nil) then
            matched_any = true;
            if (shape == nil) then
                shape = this_shape;
            elseif (shape.expected_count ~= this_shape.expected_count
                or name_key(shape.plural) ~= name_key(this_shape.plural)) then
                return nil, 'source-conflict', 'the source pages disagree on the search set';
            end
            local this_reward = read_reward(text);
            if (this_reward ~= nil) then
                if (reward == nil) then
                    reward = this_reward;
                elseif (name_key(reward) ~= name_key(this_reward)) then
                    return nil, 'source-conflict', 'the source pages disagree on the reward';
                end
            end
        end
    end
    if (not matched_any) then return nil; end
    if (reward == nil) then
        return nil, 'reward-missing', 'the instruction names no key item to finish on';
    end

    local zone_id, zone_reason, zone_detail = resolve_zone(step, zone_id_for_name);
    if (zone_id == nil) then return nil, zone_reason, zone_detail; end

    local exact_name, ids;
    for _, candidate in ipairs(singular_candidates(shape.plural)) do
        if (exact_name == nil) then
            exact_name, ids = resolve_members(zone_id, candidate, points);
        end
    end
    if (exact_name == nil) then
        return nil, 'target-unmatched',
            ('no catalogue name in zone %d matches "%s"'):format(zone_id, shape.plural);
    end
    if (#ids ~= shape.expected_count) then
        return nil, 'member-count-mismatch',
            ('the source names %d, the catalogue supplies %d usable'):format(
                shape.expected_count, #ids);
    end

    return {
        target_name = exact_name,
        zone_id = zone_id,
        expected_count = shape.expected_count,
        completion_item = reward,
        destination_ids = ids,
    };
end

-- public --------------------------------------------------------------------

function M.normalize_steps(steps, points, zone_id_for_name)
    local out = {};
    for index, step in ipairs(type(steps) == 'table' and steps or {}) do
        local copy = copy_table(step);
        copy.entities = copy_list(step.entities);
        copy.zones = copy_list(step.zones);
        if (type(step.search_set) ~= 'table') then
            local set, reason, detail = build_search_set(step, points, zone_id_for_name);
            if (type(set) == 'table') then
                copy.search_set = set;
                copy.action = 'examine';
                copy.entities = { set.target_name };
                copy.search_refusal = nil;
            elseif (reason ~= nil) then
                copy.search_refusal = { reason = reason, detail = detail };
            end
        else
            copy.search_set = copy_table(step.search_set);
            copy.search_set.destination_ids = copy_list(step.search_set.destination_ids);
        end
        out[index] = copy;
    end
    return out;
end

local function step_order_of(step)
    local order = tonumber(step.step_order) or tonumber(step.order);
    if (order ~= nil) then return order; end
    return tonumber(tostring(step.stable_step_id or ''):match('step%-(%d+)')) or 0;
end

function M.augment_actions(actions, normalized_steps)
    local out, present = {}, {};
    for index, action in ipairs(type(actions) == 'table' and actions or {}) do
        local copy = copy_table(action);
        for _, field in ipairs({ 'objects', 'npcs', 'enemies', 'items', 'key_items', 'zones', 'catalogue' }) do
            if (type(action[field]) == 'table') then copy[field] = copy_list(action[field]); end
        end
        out[index] = copy;
        present[tostring(action.step_id or '')] = true;
    end

    for _, step in ipairs(type(normalized_steps) == 'table' and normalized_steps or {}) do
        local set = step.search_set;
        local step_id = tostring(step.stable_step_id or '');
        if (type(set) == 'table' and step_id ~= '' and not present[step_id]) then
            present[step_id] = true;
            local order = step_order_of(step);
            local action = {
                step_id = step_id,
                action_id = step_id .. ':claim-01',
                step_order = order,
                action_order = 1,
                action = 'examine',
                target = set.target_name,
                target_kind = 'object',
                relationship = 'examine-object',
                objects = { set.target_name },
                npcs = {}, enemies = {}, items = {},
                key_items = { set.completion_item },
                zones = {},
                destination_zone_id = set.zone_id,
                -- ONE completion, on the key item. Not six.
                required_count = 1,
                count_mode = 'single',
                count_explicit = false,
                material = true,
                completion_evidence = 'key-item:' .. set.completion_item,
                source = 'source-search',
                instruction = trim(step.bg_instruction) ~= '' and trim(step.bg_instruction)
                    or trim(step.ffxiclopedia_instruction),
                search_set = {
                    target_name = set.target_name,
                    zone_id = set.zone_id,
                    expected_count = set.expected_count,
                    completion_item = set.completion_item,
                    destination_ids = copy_list(set.destination_ids),
                },
            };
            -- Insert after the last action of an earlier step, then push the
            -- dense `order` sequence along so the inserted action does not
            -- collide with the one that used to follow it.
            local insert_at = #out + 1;
            for index, existing in ipairs(out) do
                if ((tonumber(existing.step_order) or 0) > order) then
                    insert_at = index;
                    break;
                end
            end
            local previous_order = 0;
            for index = 1, insert_at - 1 do
                previous_order = math.max(previous_order, tonumber(out[index].order) or 0);
            end
            action.order = previous_order + 1;
            for index = insert_at, #out do
                local existing_order = tonumber(out[index].order);
                if (existing_order ~= nil and existing_order >= action.order) then
                    out[index].order = existing_order + 1;
                end
            end
            table.insert(out, insert_at, action);
        end
    end
    return out;
end

if (type(accessxi) == 'table') then
    accessxi.mission_quest_search_steps = M;
end

return M;

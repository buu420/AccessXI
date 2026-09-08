-- Reads the reward sentence a guide step actually wrote and annotates the talk
-- action that earns it, so an arriving key item can prove the step.
--
-- THE DEFECT THIS EXISTS FOR.
--
-- Windurst 2 "The Heart of the Matter": the player talked to Pore-Ohre, heard
-- the entire briefing, and was handed the key item "Southeastern star charm".
-- The cursor never moved and the addon routed them back to the same NPC.
--
-- Two guide steps describe that one conversation -- step-020 `talk` to
-- Pore-Ohre, and step-021 `travel` + `talk` to Pore-Ohre -- and only step-021's
-- sentence names the reward. Neither compact action carried `key_items` or
-- `completion_evidence`, so the key item that really arrived proved nothing,
-- and the two look-alike talk actions could not be told apart from each other.
--
-- This module annotates BOTH talk actions with the same key item and the same
-- `group_action_id` (the terminal one), so the reducer can treat them as a
-- single conversation and finish them together when the item actually arrives.
--
-- WHAT IT DELIBERATELY DOES NOT DO.
--
--   * It owns no progression proof, no cursor and no recovery. It only labels
--     actions with what the guide already claims.
--   * It never invents a reward. The name must resolve through the caller's
--     callback to a POSITIVE NUMERIC key-item id, or the step is left exactly
--     as it was.
--   * It refuses rather than guesses: negation, conditionals, prerequisites,
--     the player giving an item away, sentences granting two different items,
--     malformed phrasing, and sources that disagree on the reward.
--   * It looks BACKWARD only, across intervening travel actions, so a later
--     return visit to the same NPC is never folded into the group.
--   * It does not touch plain inventory items, and it never overwrites an
--     action that already names its own completion evidence.
--
-- API
--   M.augment_actions(actions, source_steps, key_item_id_for_name)
--       -> copied actions, changed boolean
--
--   key_item_id_for_name(name) -> id (number, required, > 0)
--                               , canonical_name (string, optional)
--
-- The input tables are never mutated and every id, order and field is carried
-- through unchanged.

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

local function copy_list(list)
    local out = {};
    for i, v in ipairs(type(list) == 'table' and list or {}) do out[i] = v; end
    return out;
end

local function copy_action(action)
    local out = {};
    for k, v in pairs(type(action) == 'table' and action or {}) do
        if (type(v) == 'table') then
            local nested = {};
            for nk, nv in pairs(v) do nested[nk] = nv; end
            out[k] = nested;
        else
            out[k] = v;
        end
    end
    for _, field in ipairs({ 'objects', 'npcs', 'enemies', 'items', 'key_items', 'zones', 'catalogue' }) do
        if (type(action[field]) == 'table') then out[field] = copy_list(action[field]); end
    end
    return out;
end

-- A sentence that hedges is not a promise. These are checked against the whole
-- instruction rather than one clause: the corpus writes "If you traded a
-- Rolanberry to Kupipi earlier, she will not give you the key item Portal
-- Charm until now", and half-reading that is worse than refusing it.
local DISQUALIFIERS = {
    'not%s+give', "won'?t%s+give", 'never%s+give', 'cannot%s+give', 'can%s*not%s+give',
    'does%s*n[o\']?t%s+give', 'do%s+not%s+give',
    '%f[%w]if%f[%W]', '%f[%w]unless%f[%W]', '%f[%w]might%f[%W]', '%f[%w]maybe%f[%W]',
    '%f[%w]only%f[%W]', '%f[%w]until%f[%W]', '%f[%w]should%s+you%f[%W]',
    'must%s+have', 'must%s+already%s+have', '%f[%w]requires%f[%W]',
};

local function disqualified(lowered)
    for _, pattern in ipairs(DISQUALIFIERS) do
        if (lowered:find(pattern)) then return true; end
    end
    return false;
end

local VALID_ARTICLE = { [''] = true, ['the'] = true, ['a'] = true, ['an'] = true };

-- Every reward this sentence promises. More than one distinct name means the
-- step has two outcomes and cannot be proved by a single key item, so the
-- caller refuses it.
local function rewards_in(text)
    local original = trim(tostring(text or ''):gsub('%s+', ' '));
    if (original == '') then return {}; end
    local lowered = original:lower();
    if (disqualified(lowered)) then return nil, 'disqualified'; end

    local found, seen, index = {}, {}, 1;
    while (true) do
        -- "give you", "gives you" -- the player must be the RECIPIENT. The
        -- corpus also writes "to give key item Food Offering", where the player
        -- hands one over; that has no "you" and must never match here.
        local start, stop, article =
            lowered:find('give[s]?%s+you%s+(%a*)%s*key item%s+', index);
        if (start == nil) then break; end
        index = stop + 1;
        if (not VALID_ARTICLE[article or '']) then return nil, 'malformed'; end

        local tail_low = lowered:sub(stop + 1);
        local tail_original = original:sub(stop + 1);
        local cut = #tail_low + 1;
        for _, pattern in ipairs({ '%.', ',', ';', '%f[%w]and%f[%W]' }) do
            local at = tail_low:find(pattern);
            if (at ~= nil and at < cut) then cut = at; end
        end
        local name = trim(tail_original:sub(1, cut - 1));
        if (name == '') then return nil, 'malformed'; end
        -- "the Key Item key item Dark Key" -- a doubled phrase, not a name.
        if (name:lower():find('^key item%f[%W]')) then return nil, 'malformed'; end
        -- A key item name is short and plain. Windurst 5 writes "the key item
        -- \"Creature Counter\" magic doll to keep track of your objective",
        -- where the clause runs on past the name; the caller's id lookup would
        -- reject that, but guessing a 60-character name is not this module's
        -- job in the first place.
        if (#name > 40 or name:find('"', 1, true) or name:find('\\', 1, true)) then
            return nil, 'malformed';
        end
        local key = name_key(name);
        if (not seen[key]) then
            seen[key] = true;
            found[#found + 1] = name;
        end
    end
    if (#found > 1) then return nil, 'multiple-rewards'; end
    -- A coordinated second reward does not repeat "give you": the corpus writes
    -- "give you the key item Food Offering and key item Drink Offering", and the
    -- scan above sees only the first. Any further "key item <word>" in the same
    -- instruction means the sentence has more outcomes than one item can prove.
    if (#found == 1) then
        local occurrences = 0;
        for _ in lowered:gmatch('key item%s+%a') do occurrences = occurrences + 1; end
        if (occurrences > 1) then return nil, 'multiple-rewards'; end
    end
    return found;
end

local function instruction_texts(step)
    local list = {};
    for _, field in ipairs({ 'bg_instruction', 'ffxiclopedia_instruction', 'primary_instruction' }) do
        local value = trim(step[field]);
        if (value ~= '') then list[#list + 1] = value; end
    end
    return list;
end

-- The reward a step promises, or nil. Sources that both name a reward must name
-- the same one; a source that names none simply has nothing to say.
local function step_reward(step, key_item_id_for_name)
    if (type(key_item_id_for_name) ~= 'function') then return nil; end
    local chosen = nil;
    for _, text in ipairs(instruction_texts(step)) do
        local found, reason = rewards_in(text);
        if (found == nil) then return nil, reason; end
        if (#found == 1) then
            if (chosen == nil) then
                chosen = found[1];
            elseif (name_key(chosen) ~= name_key(found[1])) then
                return nil, 'source-conflict';
            end
        end
    end
    if (chosen == nil) then return nil; end

    local ok, id, canonical = pcall(key_item_id_for_name, chosen);
    if (not ok) then return nil, 'lookup-failed'; end
    id = tonumber(id);
    if (id == nil or id <= 0) then return nil, 'unresolved-reward'; end
    local name = (type(canonical) == 'string' and trim(canonical) ~= '')
        and trim(canonical) or chosen;
    return { kind = 'key-item', name = name, id = id };
end

local function action_npc_key(action)
    for _, value in ipairs(type(action.npcs) == 'table' and action.npcs or {}) do
        if (trim(value) ~= '') then return name_key(value); end
    end
    return name_key(action.target);
end

local function is_talk(action) return name_key(action.action) == 'talk'; end
local function is_travel(action) return name_key(action.action) == 'travel'; end

local function is_heading(step, npc)
    if (type(step) ~= 'table') then return false; end;
    local texts = instruction_texts(step);
    if (#texts == 0) then return false; end;
    for _, text in ipairs(texts) do
        local value = name_key(text):gsub('[%.:!]+$', '');
        if (value ~= 'talk to ' .. npc and value ~= 'speak to ' .. npc
            and value ~= 'talk with ' .. npc and value ~= 'speak with ' .. npc) then return false; end;
    end;
    return true;
end;

function M.augment_actions(actions, source_steps, key_item_id_for_name)
    local out = {};
    for index, action in ipairs(type(actions) == 'table' and actions or {}) do
        out[index] = copy_action(action);
    end
    if (type(source_steps) ~= 'table' or type(key_item_id_for_name) ~= 'function') then
        return out, false;
    end

    local by_step = {};
    for _, step in ipairs(source_steps) do by_step[tostring(step.stable_step_id)] = step; end;
    local changed = false;
    for _, step in ipairs(source_steps) do
        local step_id = tostring(step.stable_step_id or '');
        local reward = step_id ~= '' and step_reward(step, key_item_id_for_name) or nil;
        if (type(reward) == 'table') then
            -- Exactly one talk action in the rewarded step, or the sentence
            -- does not say which conversation earns the item.
            local terminal_index, talk_count = nil, 0;
            for index, action in ipairs(out) do
                if (tostring(action.step_id) == step_id and is_talk(action)) then
                    talk_count = talk_count + 1;
                    terminal_index = index;
                end
            end
            if (talk_count == 1) then
                local terminal = out[terminal_index];
                -- An action that already names its own evidence is authoritative;
                -- the whole group is left alone rather than half-relabelled.
                if (trim(terminal.completion_evidence) == '') then
                    local npc = action_npc_key(terminal);
                    local group = {
                        kind = 'key-item', name = reward.name, id = reward.id,
                        group_action_id = tostring(terminal.action_id or ''),
                    };
                    local function annotate(action)
                        action.completion_evidence = 'key-item:' .. reward.name;
                        action.completion_reward = {
                            kind = group.kind, name = group.name, id = group.id,
                            group_action_id = group.group_action_id,
                        };
                        changed = true;
                    end
                    annotate(terminal);

                    -- Backward only, and only across travel. The first thing
                    -- that is not travel decides: a same-NPC talk is the other
                    -- half of this conversation; anything else -- a fight, a
                    -- trade, another NPC -- ends the group.
                    for index = terminal_index - 1, 1, -1 do
                        local previous = out[index];
                        if (is_travel(previous)) then
                            -- keep walking
                        elseif (is_talk(previous) and npc ~= '' and action_npc_key(previous) == npc
                            and tonumber(previous.step_order) == (tonumber(terminal.step_order) or 0) - 1
                            and is_heading(by_step[tostring(previous.step_id)], npc)
                            and trim(previous.completion_evidence) == '') then
                            annotate(previous);
                            break;
                        else
                            break;
                        end
                    end
                end
            end
        end
    end
    return out, changed;
end

if (type(accessxi) == 'table') then
    accessxi.objective_npc_rewards = M;
end

return M;

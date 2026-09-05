local navigation = {}

navigation.REPEAT_DELAY_MS = 220
-- G reads the guide. It is LAST so it cannot take precedence from any key
-- that already worked -- current_key returns the first key in this order that
-- is down.
--
-- Until now nothing read G at all, while the addon told the player to press it
-- in three places (mission_quest_navigation.lua:5011, :5258, :5265). The step
-- browser behind it was complete and had no callers: of The Davoi Report's 18
-- guide steps exactly one was audible, the cursor row in the menu. The other
-- seventeen -- "Walk south until you reach a pond.", "This mission can be
-- skipped.", "Trade all three items to your Moogle in your home nation Mog
-- House." -- could not be reached by any key on the keyboard.
-- N MARKS THE CURRENT STEP DONE.
--
-- A mission step completes ONCE. If the addon is not watching at the moment it
-- happens -- and on 2026-08-22 it was not, for The Davoi Report step-011 -- the
-- game will never offer that completion again. Talking to Zantaviat a second
-- time gets his reminder line, not the event, so no amount of detection can
-- ever advance the cursor. Live, the objective still read "Talk to the NPC
-- Zantaviat just inside the zone" a full day later while every route led back
-- to an NPC with nothing left to say.
--
-- accessxi.nav_mission_quest_mark_step_done was written for exactly this and
-- had NO CALLER, like the guide browser behind G before it. The player could
-- not unstick themselves by any key on the keyboard.
--
-- N, not H: H is the quick-status key, and the hotkey suite said so on the
-- first run.
navigation.KEY_ORDER = { 'I', 'U', 'O', 'J', 'K', 'L', 'N', 'G' }
navigation.VK = {
    I = 0x49,
    U = 0x55,
    O = 0x4F,
    J = 0x4A,
    K = 0x4B,
    L = 0x4C,
    N = 0x4E,
    G = 0x47,
}
navigation.DIK_BY_VK = {
    [0x49] = 0x17,
    [0x55] = 0x16,
    [0x4F] = 0x18,
    [0x4A] = 0x24,
    [0x4B] = 0x25,
    [0x4C] = 0x26,
    [0x4E] = 0x31,
    [0x47] = 0x22,
}

local action_by_key = {
    I = 'route_toggle',
    U = 'previous_category',
    O = 'next_category',
    J = 'previous_item',
    K = 'repeat_item',
    L = 'next_item',
    N = 'mark_step_done',
    G = 'open_guide',
}

local action_by_vk = {}
for key, virtual_key in pairs(navigation.VK) do
    action_by_vk[virtual_key] = action_by_key[key]
end

local function available(snapshot)
    return type(snapshot) == 'table'
        and snapshot.foreground == true
        and snapshot.chat_open ~= true
        and snapshot.modifier_down ~= true
end

local function current_key(snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.keys) ~= 'table' then
        return nil
    end
    for _, key in ipairs(navigation.KEY_ORDER) do
        if snapshot.keys[key] == true then
            return key
        end
    end
    return nil
end

function navigation.new_state()
    return {
        last_key = nil,
        last_tick = 0,
    }
end

function navigation.is_hotkey_vk(value)
    return action_by_vk[tonumber(value) or -1] ~= nil
end

function navigation.should_claim_vk(state, virtual_key, snapshot)
    if type(state) ~= 'table' or not available(snapshot) then
        return false
    end
    local action = action_by_vk[tonumber(virtual_key) or -1]
    if action == nil then
        return false
    end
    return true
end

function navigation.poll(state, snapshot)
    if type(state) ~= 'table' or type(snapshot) ~= 'table' then
        return nil
    end

    local key = current_key(snapshot)
    if key == nil then
        state.last_key = nil
        state.last_tick = 0
        return nil
    end

    local action = action_by_key[key]
    local now = tonumber(snapshot.now) or 0
    if key == state.last_key then
        if action == 'route_toggle' then
            return nil
        end
        if (now - (tonumber(state.last_tick) or 0)) < navigation.REPEAT_DELAY_MS then
            return nil
        end
    end

    state.last_key = key
    state.last_tick = now
    if not available(snapshot) then
        return nil
    end

    if action == 'route_toggle' then
        if snapshot.route_active == true or snapshot.route_pending == true then
            return 'stop_route'
        end
        return 'start_route'
    end
    return action
end

return navigation

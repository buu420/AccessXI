local navigation = {}

navigation.REPEAT_DELAY_MS = 220
navigation.KEY_ORDER = { 'I', 'U', 'O', 'J', 'K', 'L' }
navigation.VK = {
    I = 0x49,
    U = 0x55,
    O = 0x4F,
    J = 0x4A,
    K = 0x4B,
    L = 0x4C,
}
navigation.DIK_BY_VK = {
    [0x49] = 0x17,
    [0x55] = 0x16,
    [0x4F] = 0x18,
    [0x4A] = 0x24,
    [0x4B] = 0x25,
    [0x4C] = 0x26,
}

local action_by_key = {
    I = 'route_toggle',
    U = 'previous_category',
    O = 'next_category',
    J = 'previous_item',
    K = 'repeat_item',
    L = 'next_item',
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

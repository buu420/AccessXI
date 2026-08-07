local gear = {}

gear.REPEAT_DELAY_MS = 220
gear.MAX_CONTEXT_AGE_MS = 1000
gear.KEY_ORDER = { 'J', 'K', 'L' }
gear.VK = {
    J = 0x4A,
    K = 0x4B,
    L = 0x4C,
}

local function clean(text)
    text = tostring(text or ''):gsub('%s+', ' ')
    return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function add(lines, text)
    text = clean(text)
    if text ~= '' then
        lines[#lines + 1] = text
    end
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
    for _, key in ipairs(gear.KEY_ORDER) do
        if snapshot.keys[key] == true then
            return key
        end
    end
    return nil
end

local function build_lines(detail)
    local lines = {}
    local name = clean(detail.name)
    local slot_name = clean(detail.slot_name)
    if slot_name ~= '' then
        add(lines, ('%s, %s'):format(slot_name, name))
    else
        add(lines, name)
    end

    local count = tonumber(detail.count) or 0
    if count > 1 then
        add(lines, ('Quantity %d'):format(count))
    end

    if type(detail.detail_parts) == 'table' then
        for _, part in ipairs(detail.detail_parts) do
            add(lines, part)
        end
    end

    add(lines, detail.description)
    if #lines == 1 then
        add(lines, 'No further details.')
    end
    return lines
end

local function identity(detail)
    return table.concat({
        tostring(detail.menu or ''),
        tostring(detail.context_key or ''),
        tostring(tonumber(detail.id) or 0),
        tostring(tonumber(detail.index) or -1),
        clean(detail.name),
        clean(detail.slot_name),
        tostring(detail.source or ''),
    }, '\31')
end

local function context_matches(state, snapshot)
    if type(state) ~= 'table' or state.active ~= true or #state.lines == 0 then
        return false
    end
    if not available(snapshot) then
        return false
    end
    if tostring(snapshot.current_menu or '') == ''
        or tostring(snapshot.current_menu or '') ~= tostring(state.menu or '') then
        return false
    end
    if tostring(snapshot.context_key or '') == ''
        or tostring(snapshot.context_key or '') ~= tostring(state.context_key or '') then
        return false
    end

    local now = tonumber(snapshot.now) or 0
    local updated = tonumber(state.updated_tick) or 0
    local age = now - updated
    return updated > 0 and age >= 0 and age <= gear.MAX_CONTEXT_AGE_MS
end

function gear.new_state()
    return {
        active = false,
        identity = '',
        menu = '',
        context_key = '',
        lines = {},
        index = 0,
        updated_tick = 0,
        last_key = nil,
        last_tick = 0,
        owns_press = false,
    }
end

function gear.clear(state)
    if type(state) ~= 'table' then
        return
    end
    state.active = false
    state.identity = ''
    state.menu = ''
    state.context_key = ''
    state.lines = {}
    state.index = 0
    state.updated_tick = 0
    state.last_key = nil
    state.last_tick = 0
    state.owns_press = false
end

function gear.set_detail(state, detail)
    if type(state) ~= 'table' or type(detail) ~= 'table'
        or detail.is_gear ~= true
        or (tonumber(detail.id) or 0) <= 0
        or clean(detail.menu) == ''
        or clean(detail.context_key) == ''
        or clean(detail.name) == '' then
        return false
    end

    local lines = build_lines(detail)
    if #lines == 0 then
        return false
    end

    local next_identity = identity(detail)
    local changed = next_identity ~= tostring(state.identity or '')
    state.active = true
    state.identity = next_identity
    state.menu = tostring(detail.menu or '')
    state.context_key = tostring(detail.context_key or '')
    state.lines = lines
    state.updated_tick = tonumber(detail.updated_tick) or 0
    if changed then
        state.index = 0
    elseif state.index > #lines then
        state.index = #lines
    end
    return true
end

function gear.needs_refresh(state, snapshot)
    if type(state) ~= 'table' or not available(snapshot) then
        return false
    end
    local key = current_key(snapshot)
    if key == nil then
        return false
    end
    if key ~= state.last_key then
        return true
    end
    local now = tonumber(snapshot.now) or 0
    return (now - (tonumber(state.last_tick) or 0)) >= gear.REPEAT_DELAY_MS
end

function gear.poll(state, snapshot)
    if type(state) ~= 'table' or type(snapshot) ~= 'table' then
        return nil, false
    end

    local key = current_key(snapshot)
    if key == nil then
        state.last_key = nil
        state.last_tick = 0
        state.owns_press = false
        return nil, false
    end

    if not available(snapshot) then
        state.last_key = key
        state.last_tick = tonumber(snapshot.now) or 0
        state.owns_press = false
        return nil, false
    end

    local now = tonumber(snapshot.now) or 0
    local same_key = key == state.last_key
    local repeat_due = (now - (tonumber(state.last_tick) or 0)) >= gear.REPEAT_DELAY_MS
    if same_key and not repeat_due then
        if state.owns_press == true then
            return '', true
        end
        return nil, false
    end

    if not same_key then
        state.owns_press = false
    end

    state.last_key = key
    state.last_tick = now
    if not context_matches(state, snapshot) then
        if state.owns_press == true then
            return '', true
        end
        return nil, false
    end

    state.owns_press = true
    local total = #state.lines
    if state.index <= 0 then
        state.index = 1
        return state.lines[1] or '', true
    end

    if key == 'K' then
        return state.lines[state.index] or '', true
    elseif key == 'J' then
        if state.index <= 1 then
            state.index = 1
            return ('First line. %s'):format(state.lines[1]), true
        end
        state.index = state.index - 1
        return state.lines[state.index] or '', true
    elseif key == 'L' then
        if state.index >= total then
            state.index = total
            return ('Last line. %s'):format(state.lines[total]), true
        end
        state.index = state.index + 1
        return state.lines[state.index] or '', true
    end

    return '', true
end

return gear

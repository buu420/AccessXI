local data = {}

local function valid_key(value)
    return type(value) == 'string' and value:match('%S') ~= nil
end

local function valid_position(value)
    return type(value) == 'number'
        and value > 0
        and value == math.floor(value)
end

local function trimmed(value)
    return tostring(value or ''):match('^%s*(.-)%s*$') or ''
end

function data.new_state()
    return {
        surface_key = '',
        opening_position = 0,
        last_position = 0,
    }
end

function data.reset(state)
    if (type(state) ~= 'table') then
        return nil, nil, 'invalid-state'
    end
    state.surface_key = ''
    state.opening_position = 0
    state.last_position = 0
    return nil, nil, 'reset'
end

function data.begin_surface(state, surface_key, position)
    if (type(state) ~= 'table') then
        return nil, nil, 'invalid-state'
    end
    if (not valid_key(surface_key)) then
        return nil, nil, 'invalid-surface-key'
    end
    if (not valid_position(position)) then
        return nil, nil, 'invalid-position'
    end

    state.surface_key = surface_key
    state.opening_position = position
    state.last_position = position
    return nil, nil, 'surface-seeded'
end

function data.current_line(state, surface_key, position, lines)
    if (type(state) ~= 'table') then
        return nil, nil, 'invalid-state'
    end
    if (not valid_key(surface_key)) then
        return nil, nil, 'invalid-surface-key'
    end
    if (not valid_position(position)) then
        return nil, nil, 'invalid-position'
    end
    if (type(lines) ~= 'table') then
        return nil, nil, 'invalid-lines'
    end

    if (state.surface_key ~= surface_key
        or not valid_position(state.opening_position)
        or not valid_position(state.last_position)) then
        return data.begin_surface(state, surface_key, position)
    end
    if (state.last_position == position) then
        return nil, nil, 'unchanged-position'
    end

    state.last_position = position
    local line_index = position - state.opening_position + 1
    if (line_index < 1 or line_index > #lines) then
        return nil, nil, 'position-out-of-range'
    end

    local text = trimmed(lines[line_index])
    if (text == '') then
        return nil, nil, 'blank-line'
    end
    return text, line_index, 'native-position-line'
end

return data

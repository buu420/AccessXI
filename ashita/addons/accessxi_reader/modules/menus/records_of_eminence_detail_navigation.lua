local navigation = {}

local function positive_integer(value)
    return type(value) == 'number'
        and value > 0
        and value == math.floor(value)
end

local function trimmed(value)
    return tostring(value or ''):match('^%s*(.-)%s*$') or ''
end

function navigation.signal_matches_row(signal, row)
    if (type(signal) ~= 'table' or type(row) ~= 'table') then
        return false
    end

    local signal_record_id = signal.record_id
    local signal_selected = signal.selected
    local row_record_id = row.record_id
    local row_selected = row.selected

    if (not positive_integer(signal_record_id) or not positive_integer(row_record_id)
        or signal_record_id ~= row_record_id) then
        return false
    end
    if (not positive_integer(signal_selected) or not positive_integer(row_selected)
        or signal_selected ~= row_selected) then
        return false
    end
    if (not positive_integer(signal.visible_count)) then
        return false
    end
    if (type(signal.slot_id) ~= 'number' or signal.slot_id < 0xE001) then
        return false
    end

    return true
end

function navigation.resolve_dat_line(detail_index, parts, kinds, signal, row)
    if (navigation.signal_matches_row(signal, row) ~= true) then
        return nil, nil, 'signal-mismatch', false
    end
    if (not positive_integer(detail_index)) then
        return nil, nil, 'invalid-detail-index', false
    end
    if (type(parts) ~= 'table') then
        return nil, nil, 'invalid-parts', false
    end
    if (type(kinds) ~= 'table') then
        return nil, nil, 'invalid-kinds', false
    end

    local selected = row.selected
    local base_position = detail_index
    if (selected == 1 and detail_index > 1) then
        base_position = detail_index - 1
    elseif (selected > 1 and detail_index > selected) then
        base_position = detail_index - selected + 1
    end

    local bottom_start = 0
    for index, kind in ipairs(kinds) do
        kind = tostring(kind or '')
        if (kind == 'number-required' or kind == 'rewards') then
            bottom_start = index
            break
        end
    end

    local mapped_index = base_position
    if (bottom_start >= 5 and base_position >= 3) then
        mapped_index = bottom_start + (base_position - 3)
    end

    if (mapped_index < 1 or mapped_index > #parts) then
        return nil, nil, 'detail-line-out-of-range', true
    end

    local text = trimmed(parts[mapped_index])
    if (text == '') then
        return nil, nil, 'blank-dat-line', true
    end

    return text, mapped_index, 'dat-line', true
end

return navigation

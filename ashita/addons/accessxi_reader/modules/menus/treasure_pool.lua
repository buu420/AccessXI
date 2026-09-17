local data = {}
local ctx = treasure_pool_context or {}

local function integer(value, minimum, maximum)
    return type(value) == 'number' and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function clean(text)
    return tostring(text or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
end

function data.resolve(menu_name, obj, child, reader)
    local actions = menu_name == 'menu    lootope'
    if menu_name ~= 'menu    loot' and not actions then return nil, 'unsupported-menu' end
    if type(reader.is_pointer) ~= 'function' or type(reader.read_u32) ~= 'function'
        or type(reader.read_u16) ~= 'function' or type(reader.read_u8) ~= 'function'
        or type(reader.item_info) ~= 'function' then
        return nil, 'invalid-reader'
    end
    if not reader.is_pointer(obj) or not reader.is_pointer(child) then
        return nil, 'invalid-pointer'
    end
    if reader.read_u32(obj + 0x0C) ~= child or reader.read_u32(child + 8) ~= obj then
        return nil, 'parent-mismatch'
    end

    -- FFXiMain September 2026: 1013EBE0 sorts the visible records by drop time;
    -- 1013EE10 renders them. Pool storage order and the generic count (12)
    -- do not describe the displayed list. 1013E880 reads the parent cursor.
    -- 1013F340 opens lootope with one copied record at +1C. Its input
    -- handler 1013F460 maps cursor 1 to Lot (0x041), 2 to Pass (0x042).
    local count = actions and 2 or reader.read_u16(child + 0x15C)
    if not integer(count, 0, 10) then return nil, 'invalid-count' end
    if count == 0 then
        return { selected = 0, count = 0, item_id = 0, pool_slot = -1,
            text = 'Treasure Pool. Empty.' }, 'native-empty'
    end
    local selected = reader.read_u16(obj + 0x4C)
    if not integer(selected, 1, count) then return nil, 'invalid-selection' end
    local record = child + 0x1C + (actions and 0 or (selected - 1) * 0x20)
    local item_id = reader.read_u16(record)
    local quantity = reader.read_u8(record + 2)
    local lot = reader.read_u16(record + 4)
    -- The action handler reads only the byte at +6; +7 is padding.
    local pool_slot = reader.read_u8(record + 6)
    if not integer(item_id, 1, 65534) then return nil, 'invalid-item' end
    -- Optional details must not suppress an otherwise identified item or action.
    if not integer(quantity, 1, 255) then quantity = 0 end
    if not integer(pool_slot, 0, 9) then pool_slot = -1 end
    if not integer(lot, 0, 999) and lot ~= 65535 then lot = 0 end
    local info = reader.item_info(item_id) or {}
    local label = clean(info.name)
    if label == '' then return nil, 'missing-item-name' end
    local text = 'Treasure Pool. ' .. label .. '.'
    if actions then
        text = text .. (selected == 1 and ' Lot.' or ' Pass.')
        -- 1013F3C0 disables Lot when the copied local lot is positive.
        if selected == 1 and lot > 0 and lot ~= 65535 then text = text .. ' Unavailable.' end
    else
        if quantity > 1 then text = text .. ' Quantity ' .. quantity .. '.' end
        -- Passed rows are grey and cannot reopen the action popup (1013E880).
        if lot == 65535 then text = text .. ' Passed.' end
        text = text .. string.format(' %d of %d.', selected, count)
    end
    return { selected = selected, count = count, item_id = item_id,
        quantity = quantity, pool_slot = pool_slot, text = text },
        actions and 'native-action-row' or 'native-sorted-row'
end

if type(accessxi) == 'table' then
    function accessxi.treasure_pool_menu_speech(menu_name, obj, child)
        local row, reason = data.resolve(menu_name, obj, child, ctx)
        if row == nil then
            ctx.log_state(string.format(
                'state treasure-pool quiet menu="%s" obj=0x%08X child=0x%08X reason="%s"',
                ctx.escape_log_text(menu_name), tonumber(obj) or 0, tonumber(child) or 0, reason))
            return nil
        end
        accessxi.last_native_menu_name = menu_name
        accessxi.last_native_menu_label = row.text
        accessxi.last_native_menu_selected = row.selected
        accessxi.last_native_menu_tick = ctx.tick()
        accessxi.current_speech_key = string.format('treasure-pool:%s:%d:%d:%d:%s',
            menu_name, row.selected, row.item_id, row.pool_slot, row.text)
        ctx.log_state(string.format(
            'state treasure-pool menu="%s" select=%d count=%d itemId=%d poolSlot=%d text="%s" source="%s"',
            ctx.escape_log_text(menu_name), row.selected, row.count, row.item_id,
            row.pool_slot, ctx.escape_log_text(row.text), reason))
        return row.text
    end
end

return data

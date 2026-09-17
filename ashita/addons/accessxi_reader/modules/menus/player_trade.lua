local data = {}
local ctx = player_trade_context or {}

local function integer(value, minimum, maximum)
    return type(value) == 'number' and value == math.floor(value)
        and value >= minimum and value <= maximum
end

local function clean(text)
    return tostring(text or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$')
end

function data.resolve(menu_name, obj, child, reader)
    local other = menu_name == 'menu    gift'
    if menu_name ~= 'menu    trade' and not other then return nil, 'unsupported-menu' end
    if not reader.is_pointer(obj) or not reader.is_pointer(child) then
        return nil, 'invalid-pointer'
    end
    if reader.read_u32(obj + 0x0C) ~= child or reader.read_u32(child + 8) ~= obj then
        return nil, 'parent-mismatch'
    end
    -- September 2026 FFXiMain 101515E0 and row map 10371D60:
    -- 1..8 select own item records; 9 confirms, 10 cancels, 11 edits gil.
    -- Generic query-child cursor/count describe unrelated widget fields.
    local selected = reader.read_u16(obj + 0x4C)
    if not integer(selected, 1, 11) or (other and (selected == 9 or selected == 10)) then
        return nil, 'invalid-selection'
    end
    local row = { selected = selected, item_id = 0, quantity = 0, side = other and 'other' or 'own' }
    if selected == 9 or selected == 10 then
        row.text = selected == 9 and 'Trade. Okay.' or 'Trade. Cancel.'
        return row, 'native-control'
    end

    local gil = selected == 11
    local side = other and "Other player's offer. " or 'Your offer. '
    local prefix = side .. (gil and 'Gil ' or ('Slot ' .. selected .. '. '))
    local function unavailable(reason)
        row.text = prefix .. (gil and 'amount unavailable.' or 'Item information unavailable.')
        return row, reason
    end
    local inventory = reader.inventory_base()
    if not reader.is_pointer(inventory) then return unavailable('inventory-unavailable') end
    -- 101513D0 renders these live records, independent of packet capture.
    -- Each is u32 quantity, u16 item id, u8 inventory index, one padding byte.
    local record = inventory + 0x194C0 + (gil and 0 or selected * 8)
    -- Gift render 10138FF0 and update 10139140 instead use inventory +19308,
    -- stride 2C: u16 item id at +0, u32 quantity at +4; record 0 is gil.
    -- Its map 1036F9BC has the same item/gil rows, with no confirmation buttons.
    if other then record = inventory + 0x19308 + (gil and 0 or selected * 0x2C) end
    local quantity = reader.read_u32(record + (other and 4 or 0))
    local item_id = reader.read_u16(record + (other and 0 or 4))
    if gil then
        if not integer(quantity, 0, 4294967295) then return unavailable('quantity-unavailable') end
        if not other and (reader.read_u8(record + 6) ~= 0 or item_id ~= 65535) then quantity = 0 end
        row.quantity, row.text = quantity, prefix .. quantity .. '.'
        return row, 'native-gil'
    end
    if (other and (item_id == 0 or item_id == 65535)) or (not other and quantity == 0) then
        row.text = prefix .. 'Empty.'
        return row, 'native-empty-slot'
    end
    if not integer(item_id, 1, 65534) then return unavailable('item-unavailable') end
    local info = reader.item_info(item_id) or {}
    local name = clean(info.name)
    if name == '' then return unavailable('missing-item-name') end
    if not integer(quantity, 0, 4294967295) then
        row.item_id, row.text = item_id, prefix .. name .. '.'
        return row, 'native-item-quantity-unavailable'
    end
    row.item_id, row.quantity = item_id, quantity
    row.text = prefix .. name .. '. Quantity ' .. quantity .. '.'
    return row, 'native-offer-slot'
end

if type(accessxi) == 'table' then
    function accessxi.player_trade_menu_speech(menu_name, obj, child)
        local row, reason = data.resolve(menu_name, obj, child, ctx)
        if row == nil then
            ctx.log_state(string.format(
                'state player-trade quiet menu="%s" obj=0x%08X child=0x%08X reason="%s"',
                ctx.escape_log_text(menu_name), tonumber(obj) or 0, tonumber(child) or 0, reason))
            return nil
        end
        accessxi.last_native_menu_name = menu_name
        accessxi.last_native_menu_label = row.text
        accessxi.last_native_menu_selected = row.selected
        accessxi.last_native_menu_tick = ctx.tick()
        accessxi.current_speech_key = string.format('player-trade:%s:%d:%d:%s',
            menu_name, row.selected, row.item_id, row.text)
        ctx.log_state(string.format(
            'state player-trade menu="%s" side=%s select=%d itemId=%d quantity=%u text="%s" source="%s"',
            ctx.escape_log_text(menu_name), row.side, row.selected, row.item_id,
            row.quantity, ctx.escape_log_text(row.text), reason))
        return row.text
    end
end

return data

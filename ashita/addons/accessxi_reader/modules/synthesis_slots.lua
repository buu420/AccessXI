local synthesis_slots = {};

local function cleaned(text)
    return tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '');
end

function synthesis_slots.is_menu_name(name)
    return tostring(name or ''):lower() == 'menu    tskill1';
end

function synthesis_slots.slot_for_cursor(cursor)
    cursor = tonumber(cursor);
    if (cursor == nil) then
        return nil;
    end
    cursor = math.floor(cursor);
    if (cursor < 1 or cursor > 8) then
        return nil;
    end
    return cursor;
end

function synthesis_slots.slot_speech(slot, occupied, item_text)
    slot = synthesis_slots.slot_for_cursor(slot);
    if (slot == nil) then
        return nil;
    end

    item_text = cleaned(item_text);
    if occupied == true then
        if (item_text ~= '') then
            return string.format('Synthesis slot %d. %s', slot, item_text);
        end
        return string.format('Synthesis slot %d.', slot);
    end
    return string.format('Synthesis slot %d. Empty.', slot);
end

function synthesis_slots.control_for_cursor(cursor)
    cursor = tonumber(cursor);
    if (cursor == nil) then
        return nil;
    end
    cursor = math.floor(cursor);
    if (cursor == 9) then
        return 'synthesize';
    end
    if (cursor == 10) then
        return 'cancel';
    end
    return nil;
end

function synthesis_slots.control_speech(cursor, native_text)
    if (synthesis_slots.control_for_cursor(cursor) == nil) then
        return nil;
    end

    native_text = cleaned(native_text);
    if (native_text == '') then
        return nil;
    end
    if (native_text:match('[%.%!%?]$') == nil) then
        native_text = native_text .. '.';
    end
    return native_text;
end

return synthesis_slots;

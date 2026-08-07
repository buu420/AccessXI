local function cleaned(text)
    return tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '');
end

local function sentence(text)
    text = cleaned(text);
    if (text == '') then
        return '';
    end
    if (text:match('[%.%!%?]$') == nil) then
        text = text .. '.';
    end
    return text;
end

local function append_sentence(parts, text)
    text = sentence(text);
    if (text ~= '') then
        table.insert(parts, text);
    end
end

local function position_text(index, total)
    index = math.max(0, math.floor(tonumber(index) or 0));
    total = math.max(0, math.floor(tonumber(total) or 0));
    return ('%d of %d.'):fmt(index, total);
end

function accessxi.navigation_row_speech(name, index, total, kind, confidence, phrase, note)
    local parts = {};
    append_sentence(parts, name);
    table.insert(parts, position_text(index, total));
    append_sentence(parts, kind);
    confidence = cleaned(confidence);
    if (confidence ~= '') then
        append_sentence(parts, 'Confidence ' .. confidence);
    end
    append_sentence(parts, phrase);
    append_sentence(parts, note);
    return table.concat(parts, ' ');
end

function accessxi.navigation_category_speech(category_label)
    return sentence(category_label);
end

function accessxi.navigation_zone_search_row_speech(name, index, total, zone_name, route_text, confidence)
    local parts = {};
    append_sentence(parts, name);
    table.insert(parts, position_text(index, total));
    append_sentence(parts, 'NPC');
    append_sentence(parts, zone_name);
    append_sentence(parts, route_text);
    confidence = cleaned(confidence);
    if (confidence ~= '') then
        append_sentence(parts, 'Confidence ' .. confidence);
    end
    return table.concat(parts, ' ');
end

function accessxi.navigation_empty_speech(search_query)
    search_query = cleaned(search_query);
    if (search_query ~= '') then
        return ('Search %s. No search results found.'):fmt(search_query);
    end
    return 'No destinations found in this zone.';
end

function accessxi.chat_message_speech(line)
    line = tostring(line or '');
    if (line == '') then
        return 'Blank line.';
    end
    return line;
end

function accessxi.menu_selection_speech(label)
    return sentence(label);
end

function accessxi.menu_selection_detail_speech(label, description)
    local parts = {};
    append_sentence(parts, label);
    append_sentence(parts, description);
    return table.concat(parts, ' ');
end

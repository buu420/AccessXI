local ctx = generic_query_context or T{};

local safe_call = ctx.safe_call or function (fn, default)
    local ok, result = pcall(fn);
    if (ok) then
        return result;
    end
    return default;
end;
local read_u8 = ctx.read_u8 or function () return nil; end;
local read_u32 = ctx.read_u32 or function () return 0; end;
local read_probe_string = ctx.read_probe_string or function () return ''; end;
local read_current_native_menu_index = ctx.read_current_native_menu_index or function () return 0; end;
local log_line = ctx.log_line or function () end;
local log_state = ctx.log_state or function () end;
local tick = ctx.tick or function () return 0; end;
function accessxi.generic_query_label_for_speech(label)
    label = accessxi.plain_native_menu_label(label or '');
    if (label == '') then
        return '';
    end

    local lower_words = T{
        A = 'a',
        About = 'about',
        Access = 'access',
        An = 'an',
        And = 'and',
        Are = 'are',
        As = 'as',
        At = 'at',
        Be = 'be',
        By = 'by',
        Can = 'can',
        Do = 'do',
        Does = 'does',
        Expire = 'expire',
        Find = 'find',
        For = 'for',
        From = 'from',
        Happens = 'happens',
        If = 'if',
        In = 'in',
        Into = 'into',
        Is = 'is',
        It = 'it',
        Me = 'me',
        Message = 'message',
        Messages = 'messages',
        Mentor = 'mentor',
        Mentors = 'mentors',
        My = 'my',
        Now = 'now',
        Of = 'of',
        On = 'on',
        Or = 'or',
        Post = 'post',
        Posting = 'posting',
        Requirements = 'requirements',
        Rights = 'rights',
        Tell = 'tell',
        Thumbs = 'thumbs',
        The = 'the',
        To = 'to',
        Up = 'up',
        Warnings = 'warnings',
        What = 'what',
        When = 'when',
        Where = 'where',
        Who = 'who',
        Why = 'why',
        With = 'with',
    };
    local speech_words = T{
        Equ = 'Equipment',
        Lv = 'level',
    };
    local words = T{};
    local index = 0;
    for word in label:gmatch('%S+') do
        index = index + 1;
        local prefix = word:match('^([^%w]*)') or '';
        local suffix = word:match('([^%w]*)$') or '';
        local core_start = #prefix + 1;
        local core_end = #word - #suffix;
        local core = word:sub(core_start, core_end);
        local replacement = speech_words[core];
        if (replacement == nil and index > 1) then
            replacement = lower_words[core];
        end
        if (replacement ~= nil) then
            word = prefix .. replacement .. suffix;
        end
        words:append(word);
    end

    return accessxi.survival_guide_text(words:concat(' '));
end

function accessxi.generic_query_label_is_clean(label)
    label = accessxi.plain_native_menu_label(label or '');
    if (label == '') then
        return false;
    end
    if (label:eq('Pt', true)) then
        return false;
    end
    if (label:contains('Ssages', true)
        or label:contains('StrengthReduce', true)
        or label:contains('Control', true)
        or label:contains('Outline', true)
        or label:contains('Hover', true)) then
        return false;
    end
    return true;
end

function accessxi.generic_query_match_key(text)
    text = accessxi.plain_native_menu_label(text or ''):lower();
    if (text == '') then
        return '';
    end

    local parts = T{};
    for word in text:gmatch("[a-z0-9]+") do
        if (word ~= '') then
            parts:append(word);
        end
    end
    return parts:concat('');
end

function accessxi.generic_query_label_matches_dat(candidate, dat_label)
    local candidate_key = accessxi.generic_query_match_key(candidate);
    local dat_key = accessxi.generic_query_match_key(dat_label);
    if (candidate_key == '' or dat_key == '') then
        return false;
    end
    if (candidate_key == dat_key) then
        return true;
    end
    if (#candidate_key >= 5 and dat_key:sub(1, #candidate_key) == candidate_key) then
        return true;
    end

    local hits = 0;
    local total = 0;
    for word in tostring(candidate or ''):lower():gmatch("[a-z0-9]+") do
        if (#word >= 4) then
            total = total + 1;
            if (dat_key:find(word, 1, true) ~= nil) then
                hits = hits + 1;
            end
        end
    end
    return total > 0 and hits == total;
end

function accessxi.generic_query_content_word_count(label)
    label = accessxi.plain_native_menu_label(label or '');
    if (label == '') then
        return 0;
    end

    local ignored = {
        a = true,
        an = true,
        ['and'] = true,
        by = true,
        ['for'] = true,
        from = true,
        ['in'] = true,
        of = true,
        on = true,
        ['or'] = true,
        the = true,
        to = true,
        up = true,
    };
    local count = 0;
    for word in label:lower():gmatch("[a-z0-9]+") do
        if (word ~= '' and ignored[word] ~= true) then
            count = count + 1;
        end
    end
    return count;
end

function accessxi.generic_query_direct_label_is_confirmation(label)
    label = accessxi.plain_native_menu_label(label or ''):lower();
    return label == 'yes.'
        or label == 'no.'
        or label == 'sure.'
        or label == 'ok.'
        or label == 'okay.'
        or label == 'back.'
        or label == 'none.'
        or label == 'nothing.'
        or label == 'cancel.'
        or label == 'never mind.';
end

function accessxi.generic_query_direct_label_should_override(list_label, direct_label, direct_help)
    local direct = accessxi.plain_native_menu_label(direct_label or '');
    if (direct == '') then
        return false;
    end

    local list = accessxi.plain_native_menu_label(list_label or '');
    if (list == '') then
        return true;
    end
    if (accessxi.generic_query_direct_label_is_confirmation(direct)) then
        return true;
    end

    local direct_key = accessxi.generic_query_match_key(direct);
    local list_key = accessxi.generic_query_match_key(list);
    if (direct_key == '' or list_key == '' or direct_key == list_key) then
        return true;
    end

    local direct_words = accessxi.generic_query_content_word_count(direct);
    local list_words = accessxi.generic_query_content_word_count(list);
    if (((direct_words <= 1 and list_words >= 2) or (direct_words == 0 and list_words > 0))
        and list_key:sub(1, #direct_key) == direct_key) then
        return false;
    end

    local help = accessxi.generic_query_resource_help_text(direct_help or '');
    if (help == '' and direct_words <= 1 and list_words > direct_words and direct:match('[!][%.%-!]+') ~= nil) then
        return false;
    end

    return true;
end

function accessxi.generic_query_rolandienne_sparkshop_equipment_label(title, selected, count, raw, list_label)
    title = accessxi.plain_native_menu_label(title or '');
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    raw = tonumber(raw) or 0;
    local list_key = accessxi.generic_query_match_key(list_label or '');
    if (count ~= 13 or not title:eq('Rolandienne', true) or list_key ~= 'equlvupto') then
        return '', '';
    end

    -- LSB sparkshop.lua maps event categories 3-10 to these equipment ranges.
    -- The live query raw low byte is the zero-based selected category.
    local category = selected;
    local raw_category = math.floor(raw % 0x100) + 1;
    if (raw_category >= 3 and raw_category <= 10) then
        category = raw_category;
    end

    local ranges = T{
        [3] = '1 through 9',
        [4] = '10 through 19',
        [5] = '20 through 29',
        [6] = '30 through 39',
        [7] = '40 through 50',
        [8] = '51 through 70',
        [9] = '71 through 98',
        [10] = '99',
    };
    local range = ranges[category];
    if (range == nil) then
        return '', '';
    end

    return ('Equipment level %s'):fmt(range), ('sparkshop-equipment-category:%d'):fmt(category);
end

function accessxi.generic_query_dat_label_for_context(title, selected, count, list_label, direct_label)
    title = accessxi.plain_native_menu_label(title or '');
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    if (title == '' or selected <= 0 or count <= 0) then
        return '', '';
    end

    local zone = tonumber(accessxi.current_zone_id ~= nil and accessxi.current_zone_id() or 0) or 0;
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    local window_server = target ~= nil and (tonumber(safe_call(function () return target:GetWindowServerId(); end, 0)) or 0) or 0;
    local focus_server = target ~= nil and (tonumber(safe_call(function () return target:GetFocusTargetServerId(); end, 0)) or 0) or 0;
    local server_id = window_server ~= 0 and window_server or focus_server;

    local source = '';
    local labels = nil;
    if (zone == 243 and title:eq('Syndella', true) and count == 2 and (server_id == 0 or server_id == 0x010F3136)) then
        source = 'dat:ROM/25/52.DAT actor=0x010F3136 event=0x283C message=15747';
        labels = T{ 'Sure.', "Sorry, I'm busy." };
    end
    if (labels == nil) then
        return '', '';
    end

    local dat_label = labels[selected] or '';
    if (dat_label == '') then
        return '', '';
    end
    if (accessxi.generic_query_label_matches_dat(direct_label, dat_label)
        or accessxi.generic_query_label_matches_dat(list_label, dat_label)) then
        return dat_label, source;
    end
    return '', '';
end

function accessxi.generic_query_utf16_next_pair_is_printable(ptr, off, max_off)
    ptr = tonumber(ptr) or 0;
    off = tonumber(off) or 0;
    max_off = tonumber(max_off) or 0;
    if (not accessxi.is_probe_pointer(ptr) or off < 0 or off + 1 > max_off) then
        return false;
    end

    local lo = read_u8(ptr + off);
    local hi = read_u8(ptr + off + 1);
    return lo ~= nil and hi == 0 and accessxi.probe_printable_ascii(lo);
end

function accessxi.generic_query_row_apostrophe_continuation(run, next_lo, next_hi)
    if (next_hi ~= 0 or next_lo == nil) then
        return false;
    end
    if (next_lo == 0x53) then
        return true;
    end

    local raw = type(run) == 'table' and run:concat('') or tostring(run or '');
    if (raw == '' or accessxi.decode_ffxi_menu_text_fragment == nil) then
        return false;
    end

    local decoded = accessxi.survival_guide_text(accessxi.decode_ffxi_menu_text_fragment(raw) or '');
    if (decoded:eq('I', true)) then
        return next_lo == 0x64 or next_lo == 0x6C or next_lo == 0x6D or next_lo == 0x76;
    end
    return false;
end

function accessxi.generic_query_row_label_from_ptr(ptr)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr) or accessxi.decode_ffxi_menu_text_fragment == nil) then
        return '';
    end

    local words = T{};
    local run = T{};
    local blank_pairs = 0;
    local ended_with_period = false;
    local control_char = function (lo)
        lo = tonumber(lo) or -1;
        if (lo >= 0x10 and lo <= 0x19) then
            return string.char(0x30 + (lo - 0x10));
        end
        if (lo == 0x0D) then
            return '-';
        end
        if (lo == 0x0E) then
            return '.';
        end
        if (lo == 0x0C) then
            return ',';
        end
        return nil;
    end;
    local flush_run = function ()
        if (#run <= 0) then
            return;
        end

        local raw_word = run:concat('');
        run = T{};
        local previous_word = tostring(words[#words] or '');
        local raw_number_after_chapter = raw_word:match('^%d+$') ~= nil and previous_word:eq('Chapter', true);
        local word = raw_number_after_chapter and raw_word or accessxi.decode_ffxi_menu_text_fragment(raw_word);
        word = accessxi.survival_guide_text(word or ''):gsub('%s+', ' '):trim();
        local number_after_chapter = word:match('^%d+$') ~= nil and previous_word:eq('Chapter', true);
        if (word == '' or word:find('\\', 1, true) ~= nil or (word:match('^%d+$') ~= nil and not number_after_chapter) or word == '.' or word == '/') then
            ended_with_period = false;
            return;
        end
        if (word:upper() == word and #word > 1) then
            word = word:sub(1, 1) .. word:sub(2):lower();
        end
        words:append(word);
        ended_with_period = word:match('%.$') ~= nil;
    end;

    for off = 0, 0x7E, 2 do
        local lo = read_u8(ptr + off);
        local hi = read_u8(ptr + off + 1);
        if (lo == nil or hi == nil) then
            flush_run();
            break;
        elseif (hi == 0 and lo == 0) then
            flush_run();
            if (#words > 0) then
                blank_pairs = blank_pairs + 1;
                local last_word = tostring(words[#words] or '');
                local keeps_reading = last_word:lower():match('%-pt%.$') ~= nil;
                if ((ended_with_period and not keeps_reading) or blank_pairs >= 2) then
                    break;
                end
            end
        elseif (hi == 0 and lo == 0x07) then
            local next_lo = read_u8(ptr + off + 2);
            local next_hi = read_u8(ptr + off + 3);
            if (#run > 0 and accessxi.generic_query_row_apostrophe_continuation(run, next_lo, next_hi)) then
                run:append("'");
                blank_pairs = 0;
            elseif (#run > 0 and accessxi.generic_query_utf16_next_pair_is_printable(ptr, off + 2, 0x7E)) then
                flush_run();
                blank_pairs = 0;
            else
                flush_run();
                if (#words > 0) then
                    break;
                end
            end
        elseif (hi == 0 and lo == 0x0F) then
            flush_run();
            blank_pairs = 0;
        elseif (hi == 0 and lo == 0x1F) then
            flush_run();
            break;
        elseif (hi == 0 and control_char(lo) ~= nil) then
            blank_pairs = 0;
            ended_with_period = false;
            run:append(control_char(lo));
        elseif (hi == 0 and accessxi.probe_printable_ascii(lo)) then
            blank_pairs = 0;
            ended_with_period = false;
            run:append(string.char(lo));
        else
            flush_run();
            if (#words > 0) then
                break;
            end
        end
    end
    flush_run();

    if (#words <= 0) then
        return '';
    end

    local label = accessxi.native_query_normalize_phrase(words:concat(' '), 'plain');
    if (accessxi.native_query_label_looks_real(label) and accessxi.generic_query_label_is_clean(label)) then
        return label;
    end

    return '';
end

function accessxi.generic_query_help_allowed_for_label(label, count)
    label = accessxi.plain_native_menu_label(label or '');
    count = tonumber(count) or 0;
    if (label == '' or count <= 2) then
        return false;
    end

    local lower = label:lower();
    if (lower == 'yes.' or lower == 'no.' or lower == 'nothing.' or lower == 'back.'
        or lower == 'check exchange points.' or lower == 'learn about the campaign.') then
        return false;
    end
    if (lower:match('^%d+%-?%s*pt%.?%s+items%.$') ~= nil
        or lower:match('^%d+%-?%s*point%s+items%.$') ~= nil
        or lower == 'point items.') then
        return false;
    end

    return true;
end

function accessxi.generic_query_help_tokens(text)
    text = accessxi.survival_guide_text(text or ''):lower();
    local tokens = {};
    local ignored = {
        ['and'] = true,
        are = true,
        bearing = true,
        chapter = true,
        chapters = true,
        copy = true,
        copies = true,
        from = true,
        item = true,
        items = true,
        named = true,
        ordinary = true,
        point = true,
        points = true,
        that = true,
        the = true,
        this = true,
        with = true,
    };
    for word in text:gmatch("[a-z0-9']+") do
        word = word:gsub("'s$", ''):gsub("^'+", ''):gsub("'+$", '');
        if ((#word >= 4 or word == 'rem') and ignored[word] ~= true) then
            tokens[word] = true;
            if (#word >= 5 and word:sub(-1) == 's') then
                tokens[word:sub(1, -2)] = true;
            end
        end
    end
    return tokens;
end

function accessxi.generic_query_text_matches_label(label, text)
    label = accessxi.plain_native_menu_label(label or '');
    text = accessxi.plain_native_menu_help(text or '');
    if (label == '' or text == '') then
        return false;
    end

    local label_tokens = accessxi.generic_query_help_tokens(label);
    local text_tokens = accessxi.generic_query_help_tokens(text);
    for word, _ in pairs(label_tokens) do
        if (text_tokens[word] == true) then
            return true;
        end
    end
    return false;
end

function accessxi.generic_query_help_shape_is_clean(help)
    help = accessxi.plain_native_menu_help(help or '');
    if (help == '' or #help < 16) then
        return false;
    end
    local lower = help:lower();
    if (lower:find('\\', 1, true) ~= nil
        or lower:find('final fantasy xi', 1, true) ~= nil
        or lower:find('would you please', 1, true) ~= nil
        or lower:find('could appear around', 1, true) ~= nil
        or lower:match('^(s|es|ous|is|are|of|to|and)%s+') ~= nil) then
        return false;
    end

    local words = 0;
    for _ in help:gmatch('%S+') do
        words = words + 1;
    end
    if (words < 4) then
        return false;
    end
    if (help:match('[%.%!%?]') == nil and words < 7) then
        return false;
    end
    return true;
end

function accessxi.generic_query_resource_label_key(text)
    text = accessxi.survival_guide_text(text or ''):lower();
    return text:gsub('[^a-z0-9]+', '');
end

function accessxi.generic_query_resource_help_text(text)
    text = tostring(text or ''):gsub('[\r\n]+', ' ');
    text = accessxi.survival_guide_text(text):gsub('^["\']+', ''):gsub('["\']+$', '');
    text = accessxi.survival_guide_text(text);
    if (text == '' or text:match('^[%p%s]+$') ~= nil) then
        return '';
    end
    if (text:find('\\', 1, true) ~= nil or text:find('menu    ', 1, true) ~= nil or text:find('anc     ', 1, true) ~= nil) then
        return '';
    end
    if (#text > 260) then
        local clipped = text:sub(1, 260);
        local sentence_end = 0;
        for pos in clipped:gmatch('()[%.%!%?]') do
            sentence_end = pos;
        end
        if (sentence_end >= 120) then
            text = clipped:sub(1, sentence_end);
        else
            text = clipped:gsub('%s+%S*$', ''):gsub('[,;:%s]+$', '');
            if (text ~= '' and text:match('[%.%!%?]$') == nil) then
                text = text .. '...';
            end
        end
    end
    return text;
end

function accessxi.generic_query_resource_index_add(index, key, id, help, source)
    key = tostring(key or '');
    id = tonumber(id) or 0;
    help = accessxi.generic_query_resource_help_text(help or '');
    if (key == '' or id <= 0 or help == '') then
        return;
    end

    local existing = index[key];
    if (existing == nil) then
        index[key] = { id = id, help = help, source = tostring(source or '') };
    elseif (tonumber(existing.id) ~= id or tostring(existing.help or '') ~= help) then
        existing.ambiguous = true;
    end
end

function accessxi.generic_query_resource_index()
    if (accessxi.generic_query_item_resource_index ~= nil) then
        return accessxi.generic_query_item_resource_index;
    end
    if (accessxi.generic_query_item_resource_load_tried == true) then
        return nil;
    end
    accessxi.generic_query_item_resource_load_tried = true;

    local items_path = accessxi.resource_path('windower', 'items.lua');
    local descriptions_path = accessxi.resource_path('windower', 'item_descriptions.lua');
    local items = accessxi.load_module_file_table(items_path, 'windower:items', nil);
    local descriptions = accessxi.load_module_file_table(descriptions_path, 'windower:item_descriptions', nil);
    if (type(items) ~= 'table' or type(descriptions) ~= 'table') then
        return nil;
    end

    local index = {};
    local add_label = function (label, id, help, source)
        label = accessxi.plain_native_menu_label(label or '');
        local key = accessxi.generic_query_resource_label_key(label);
        accessxi.generic_query_resource_index_add(index, key, id, help, source);
    end;

    for id, item in pairs(items) do
        local numeric_id = tonumber(id) or tonumber(type(item) == 'table' and item.id) or 0;
        local desc = type(descriptions[numeric_id]) == 'table' and descriptions[numeric_id] or nil;
        local help = desc ~= nil and tostring(desc.en or '') or '';
        if (numeric_id > 0 and type(item) == 'table' and help ~= '') then
            add_label(item.en, numeric_id, help, ('item:%d:en'):fmt(numeric_id));
            add_label(item.enl, numeric_id, help, ('item:%d:enl'):fmt(numeric_id));
            local without_prefix = tostring(item.en or ''):gsub('^[^A-Za-z0-9]+', '');
            add_label(without_prefix, numeric_id, help, ('item:%d:en-clean'):fmt(numeric_id));
            without_prefix = tostring(item.enl or ''):gsub('^[^A-Za-z0-9]+', '');
            add_label(without_prefix, numeric_id, help, ('item:%d:enl-clean'):fmt(numeric_id));
        end
    end

    accessxi.generic_query_item_resource_index = index;
    log_line(('loaded generic query item resource index items="%s" descriptions="%s" keys=%d'):fmt(
        items_path,
        descriptions_path,
        accessxi.table_count(index)));
    return index;
end

function accessxi.generic_query_resource_help_for_label(label)
    label = accessxi.plain_native_menu_label(label or '');
    if (label == '') then
        return '', '';
    end

    local index = accessxi.generic_query_resource_index();
    if (type(index) ~= 'table') then
        return '', '';
    end

    local key = accessxi.generic_query_resource_label_key(label);
    local entry = index[key];
    if (type(entry) ~= 'table' or entry.ambiguous == true) then
        return '', '';
    end

    local help = accessxi.generic_query_resource_help_text(entry.help or '');
    if (help == '') then
        return '', '';
    end

    return help, tostring(entry.source or 'item-resource');
end

function accessxi.generic_query_resource_label_from_ptr(ptr)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return '';
    end

    local label = accessxi.plain_native_menu_label(accessxi.native_query_candidate_label_from_ptr(ptr, 'plain') or '');
    if (label ~= '' and accessxi.generic_query_label_is_clean(label)) then
        return label;
    end

    for _, off in ipairs(T{ 0x00, 0x28 }) do
        label = accessxi.plain_native_menu_label(read_probe_string(ptr + off, 100));
        if (label ~= '' and accessxi.generic_query_label_is_clean(label)) then
            return label;
        end
    end
    return '';
end

function accessxi.generic_query_help_from_resource_ptr(ptr, label)
    ptr = tonumber(ptr) or 0;
    label = accessxi.plain_native_menu_label(label or '');
    if (not accessxi.is_probe_pointer(ptr) or label == '') then
        return '', '';
    end

    local resource_label = accessxi.generic_query_resource_label_from_ptr(ptr);
    local resource_matches = resource_label ~= '' and accessxi.generic_query_text_matches_label(label, resource_label);
    local candidates = T{};
    for _, off in ipairs(T{ 0x2C, 0x30, 0x38, 0x3C, 0x40, 0x46, 0x50, 0x58, 0x60, 0x80 }) do
        candidates:append({
            ptr = ptr + off,
            source = ('direct+%03X'):fmt(off),
            text = accessxi.plain_native_menu_help(read_probe_string(ptr + off, 260)),
        });
    end
    for _, off in ipairs(T{ 0x08, 0x0C, 0x10, 0x14, 0x18, 0x20, 0x28, 0x30, 0x38, 0x40 }) do
        local help_ptr = read_u32(ptr + off) or 0;
        if (accessxi.is_probe_pointer(help_ptr)) then
            candidates:append({
                ptr = help_ptr,
                source = ('ptr+%03X'):fmt(off),
                text = accessxi.plain_native_menu_help(read_probe_string(help_ptr, 260)),
            });
        end
    end

    for _, candidate in ipairs(candidates) do
        local help = accessxi.plain_native_menu_help(candidate.text or '');
        if (accessxi.generic_query_help_shape_is_clean(help)
            and not help:eq(label, true)
            and (resource_matches or accessxi.generic_query_text_matches_label(label, help))) then
            return help, tostring(candidate.source or '');
        end
    end

    return '', '';
end

function accessxi.generic_query_help_for_node(node, label, count)
    node = tonumber(node) or 0;
    label = accessxi.plain_native_menu_label(label or '');
    if (not accessxi.is_probe_pointer(node) or not accessxi.generic_query_help_allowed_for_label(label, count)) then
        return '', '';
    end

    local cache_key = ('%08X:%d:%s'):fmt(node, tonumber(count) or 0, label);
    local cached = accessxi.generic_query_item_help_cache ~= nil and accessxi.generic_query_item_help_cache[cache_key] or nil;
    if (cached ~= nil) then
        return tostring(cached.help or ''), tostring(cached.mode or '');
    end

    local resource_help, resource_mode = accessxi.generic_query_resource_help_for_label(label);
    if (resource_help ~= '') then
        accessxi.generic_query_item_help_cache = accessxi.generic_query_item_help_cache or {};
        accessxi.generic_query_item_help_cache[cache_key] = { help = resource_help, mode = resource_mode };
        return resource_help, resource_mode;
    end

    accessxi.generic_query_item_help_cache = accessxi.generic_query_item_help_cache or {};
    accessxi.generic_query_item_help_cache[cache_key] = { help = '', mode = '' };
    return '', '';
end

function accessxi.generic_query_direct_label_for_child(child, selected, count)
    child = tonumber(child) or 0;
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    if (not accessxi.is_probe_pointer(child) or selected <= 0 or count <= 0 or selected > count) then
        return '', '', '', '', 0;
    end

    local items, mode = accessxi.native_query_items_for_child(child, count, 'plain');
    local item = items ~= nil and items[selected] or nil;
    local node = tonumber(item ~= nil and item.ptr or 0) or 0;
    if (not accessxi.is_probe_pointer(node)) then
        return '', '', '', '', 0;
    end

    for _, off in ipairs(T{ 0x10, 0x88 }) do
        local ptr = read_u32(node + off) or 0;
        if (accessxi.is_probe_pointer(ptr)) then
            local label = accessxi.generic_query_row_label_from_ptr(ptr);
            if (label == '') then
                label = accessxi.native_query_candidate_label_from_ptr(ptr, 'plain');
            end
            label = accessxi.plain_native_menu_label(label or '');
            if (accessxi.generic_query_label_is_clean(label)) then
                local help, help_mode = accessxi.generic_query_help_for_node(node, label, count);
                return label, ('%s:direct+%03X'):fmt(tostring(mode or 'query'), off), help, help_mode, node;
            end
        end
    end

    return '', '', '', '', node;
end

function accessxi.generic_query_probe_escape(text)
    local esc = accessxi.escape_probe_log_text_wide or accessxi.escape_probe_log_text;
    if (esc ~= nil) then
        return esc(text);
    end
    return tostring(text or ''):gsub('[\r\n"]+', ' ');
end

function accessxi.generic_query_probe_ffxi16_text(ptr)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return '';
    end

    if (accessxi.collect_probe_ffxi_utf16_entries ~= nil) then
        local entries = accessxi.collect_probe_ffxi_utf16_entries(ptr, 0x180, 2, 12);
        local parts = T{};
        for _, entry in ipairs(entries or T{}) do
            local text = accessxi.plain_native_menu_label(entry.text or '');
            if (text ~= '') then
                parts:append(text);
            end
        end
        return parts:concat(' | ');
    end

    if (accessxi.collect_probe_ffxi_utf16_runs ~= nil and accessxi.probe_runs_to_text ~= nil) then
        return accessxi.probe_runs_to_text(accessxi.collect_probe_ffxi_utf16_runs(ptr, 0x180, 2, 12));
    end
    return '';
end

function accessxi.generic_query_equipment_category_probe(title, selected, count, page, raw, child, list_label, list_mode, direct_label, direct_mode, node)
    title = accessxi.plain_native_menu_label(title or '');
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    page = tonumber(page) or 0;
    raw = tonumber(raw) or 0;
    child = tonumber(child) or 0;
    node = tonumber(node) or 0;

    if (count ~= 13 or not title:eq('Rolandienne', true) or not accessxi.is_probe_pointer(node)) then
        return;
    end

    local list_key = accessxi.generic_query_match_key(list_label or '');
    local direct_key = accessxi.generic_query_match_key(direct_label or '');
    if (list_key ~= 'equlvupto' and direct_key ~= 'equ') then
        return;
    end

    local key = ('%s:%d:%d:%d:%08X:%08X:%s:%s'):fmt(
        title,
        selected,
        count,
        page,
        raw,
        node,
        tostring(list_label or ''),
        tostring(direct_label or ''));
    if (key == tostring(accessxi.generic_query_equipment_category_probe_key or '')) then
        return;
    end
    accessxi.generic_query_equipment_category_probe_key = key;

    local parts = T{};
    if (accessxi.native_query_node_debug ~= nil) then
        parts:append(accessxi.native_query_node_debug(node, 'selected'));
    end

    for _, off in ipairs(T{ 0x00, 0x04, 0x10, 0x38, 0x88, 0x100, 0x104, 0x108 }) do
        local value = read_u32(node + off) or 0;
        if (accessxi.is_probe_pointer(value)) then
            local strings = accessxi.probe_strings_at ~= nil and accessxi.probe_strings_at(value) or '';
            local ffxi16 = accessxi.generic_query_probe_ffxi16_text(value);
            local bytes = accessxi.format_probe_bytes ~= nil and accessxi.format_probe_bytes(value, 0, 0x80) or '';
            local dwords = accessxi.format_probe_dwords ~= nil and accessxi.format_probe_dwords(value, 0, 20) or '';
            parts:append(('+%03X->0x%08X strings="%s" ffxi16="%s" dwords="%s" bytes="%s"'):fmt(
                off,
                value,
                accessxi.generic_query_probe_escape(strings),
                accessxi.generic_query_probe_escape(ffxi16),
                accessxi.generic_query_probe_escape(dwords),
                accessxi.generic_query_probe_escape(bytes)));
        else
            parts:append(('+%03X=0x%08X'):fmt(off, value));
        end
    end

    log_state(('state generic-query equipment-category-probe title="%s" select=%d count=%d page=%d raw=0x%08X child=0x%08X node=0x%08X listMode="%s" directMode="%s" listLabel="%s" directLabel="%s" details="%s"'):fmt(
        accessxi.generic_query_probe_escape(title),
        selected,
        count,
        page,
        raw,
        child,
        node,
        accessxi.generic_query_probe_escape(list_mode or ''),
        accessxi.generic_query_probe_escape(direct_mode or ''),
        accessxi.generic_query_probe_escape(list_label or ''),
        accessxi.generic_query_probe_escape(direct_label or ''),
        accessxi.generic_query_probe_escape(parts:concat(' || '))));
end

function accessxi.generic_query_menu_speech(menu_name, title, obj)
    menu_name = tostring(menu_name or '');
    title = tostring(title or '');
    obj = tonumber(obj) or 0;
    if (not menu_name:eq('menu    query', true) or obj == 0) then
        return nil;
    end
    if (title == '') then
        local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
        title = accessxi.plain_native_menu_label(target ~= nil and safe_call(function () return target:GetWindowName(); end, '') or '');
    else
        title = accessxi.plain_native_menu_label(title);
    end
    accessxi.current_menu_speech_title = title;

    local selected, page, raw, child, count = accessxi.survival_guide_query_child_state_for_obj(obj);
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    if (selected <= 0) then
        selected = read_current_native_menu_index(0x4C);
    end
    if (count <= 0 or count > 64) then
        count = math.max(tonumber(accessxi.native_menu_index(0x24)) or 0, tonumber(accessxi.native_menu_index(0x28)) or 0);
    end
    if (selected <= 0 or count <= 0 or selected > count or count > 64 or not accessxi.is_probe_pointer(child)) then
        return nil;
    end

    local label, mode = accessxi.native_query_label_for_selection(child, selected, count, 'plain');
    label = accessxi.plain_native_menu_label(label or '');
    local direct_label, direct_mode, direct_help, direct_help_mode, direct_node = accessxi.generic_query_direct_label_for_child(child, selected, count);
    accessxi.generic_query_equipment_category_probe(title, selected, count, page, raw, child, label, mode, direct_label, direct_mode, direct_node);
    local context_label, context_mode = accessxi.generic_query_rolandienne_sparkshop_equipment_label(title, selected, count, raw, label);
    local dat_label, dat_mode = accessxi.generic_query_dat_label_for_context(title, selected, count, label, direct_label);
    local help = '';
    local help_mode = '';
    if (context_label ~= '') then
        label = context_label;
        mode = context_mode;
    elseif (dat_label ~= '') then
        label = dat_label;
        mode = dat_mode;
    elseif (direct_label ~= '' and accessxi.generic_query_direct_label_should_override(label, direct_label, direct_help)) then
        label = direct_label;
        mode = direct_mode;
        help = accessxi.generic_query_resource_help_text(direct_help or '');
        help_mode = tostring(direct_help_mode or '');
    elseif (not accessxi.generic_query_label_is_clean(label)) then
        label = '';
    end
    local speech_label = accessxi.generic_query_label_for_speech(label);
    local speech_help = accessxi.generic_query_resource_help_text(help or '');
    if (speech_help ~= '' and (speech_label == '' or speech_help:eq(speech_label, true))) then
        speech_help = '';
        help_mode = '';
    end
    local speech_text = accessxi.sentence_fragment(speech_label);
    if (speech_help ~= '') then
        speech_text = ('%s %s'):fmt(speech_text, accessxi.sentence_fragment(speech_help));
    end
    local key = ('%s:%s:%d:%d:%d:%08X:%08X:%s:%s:%s:%s'):fmt(
        menu_name,
        title,
        selected,
        count,
        tonumber(page) or 0,
        tonumber(raw) or 0,
        tonumber(child) or 0,
        tostring(mode or ''),
        label,
        speech_help,
        help_mode);
    if (key ~= tostring(accessxi.last_generic_query_menu_log_key or '')) then
        accessxi.last_generic_query_menu_log_key = key;
        log_state(('state generic-query menu="%s" title="%s" select=%d count=%d page=%d raw=0x%08X child=0x%08X mode="%s" label="%s" help="%s" helpMode="%s" speech="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title),
            selected,
            count,
            tonumber(page) or 0,
            tonumber(raw) or 0,
            tonumber(child) or 0,
            tostring(mode or ''),
            accessxi.escape_probe_log_text(label),
            accessxi.escape_probe_log_text(speech_help),
            accessxi.escape_probe_log_text(help_mode),
            accessxi.escape_probe_log_text(speech_text)));
    end
    if (speech_label == '') then
        return nil;
    end

    accessxi.last_native_menu_name = menu_name;
    accessxi.last_native_menu_label = speech_text;
    accessxi.last_native_menu_selected = selected;
    accessxi.last_native_menu_tick = tick();
    accessxi.current_speech_key = ('generic-query:%s:%s:%d:%d:%d:%s:%s'):fmt(
        menu_name,
        title,
        selected,
        tonumber(page) or 0,
        count,
        speech_label,
        speech_help);
    if (title ~= '') then
        return ('%s. %s'):fmt(title, speech_text);
    end
    return speech_text;
end


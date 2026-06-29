local ctx = debug_probe_helpers_context or T{};

local read_u8 = ctx.read_u8 or function () return nil; end;
local read_u16 = ctx.read_u16 or function () return nil; end;
local read_u32 = ctx.read_u32 or function () return 0; end;
local read_i32 = ctx.read_i32 or function () return 0; end;
local read_current_native_menu_index = ctx.read_current_native_menu_index or function () return 0; end;
local read_probe_string = ctx.read_probe_string or function () return ''; end;
local get_menu_name = ctx.get_menu_name or function () return ''; end;
local get_current_menu_object_ptr = ctx.get_current_menu_object_ptr or function () return 0; end;
local get_ffximain_base = ctx.get_ffximain_base or function () return 0; end;
local clean_probe_text = ctx.clean_probe_text or function (text) return tostring(text or ''); end;
local log_line = ctx.log_line or function () end;
local log_state = ctx.log_state or function () end;
local safe_call = ctx.safe_call or function (fn, default)
    local ok, result = pcall(fn);
    if (ok) then
        return result;
    end
    return default;
end;
local speak = ctx.speak or function () end;
local hex32 = ctx.hex32 or function (value)
    value = tonumber(value) or 0;
    if (value < 0) then
        value = value + 0x100000000;
    end
    return ('%08X'):fmt(value);
end;
local current_target_snapshot = ctx.current_target_snapshot or function () return ''; end;
local format_runtime_dwords = ctx.format_runtime_dwords or function () return ''; end;
local log_menu_dump_dwords = ctx.log_menu_dump_dwords or function () end;
local log_menu_dump_candidates = ctx.log_menu_dump_candidates or function () end;
local log_menu_dump_pointer_targets = ctx.log_menu_dump_pointer_targets or function () end;
local log_menu_dump_shapes = ctx.log_menu_dump_shapes or function () end;
function accessxi.probe_byte_ascii(byte_value)
    byte_value = tonumber(byte_value) or 0;
    if (byte_value >= 0x20 and byte_value <= 0x7E) then
        return string.char(byte_value);
    end
    return '.';
end

function accessxi.probe_printable_ascii(byte_value)
    byte_value = tonumber(byte_value) or 0;
    return byte_value >= 0x20 and byte_value <= 0x7E;
end

function accessxi.log_probe_ascii_runs(seq, label, ptr, length, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return;
    end

    length = tonumber(length) or 0;
    limit = tonumber(limit) or 16;
    local logged = 0;
    local run = T{};
    local run_start = 0;

    for off = 0, length do
        local byte_value = off < length and read_u8(ptr + off) or nil;
        if (byte_value ~= nil and accessxi.probe_printable_ascii(byte_value)) then
            if (#run == 0) then
                run_start = off;
            end
            run:append(string.char(byte_value));
        else
            if (#run >= 4) then
                logged = logged + 1;
                log_line(('menudump seq=%d %s asciiRun +%03X="%s"'):fmt(seq, label, run_start, run:concat('')));
                if (logged >= limit) then
                    return;
                end
            end
            run = T{};
        end
    end
end

function accessxi.log_probe_utf16_runs(seq, label, ptr, length, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return;
    end

    length = tonumber(length) or 0;
    limit = tonumber(limit) or 16;
    local logged = 0;
    for start_phase = 0, 1 do
        local run = T{};
        local run_start = start_phase;
        for off = start_phase, length - 2, 2 do
            local lo = read_u8(ptr + off);
            local hi = read_u8(ptr + off + 1);
            if (lo ~= nil and hi == 0 and accessxi.probe_printable_ascii(lo)) then
                if (#run == 0) then
                    run_start = off;
                end
                run:append(string.char(lo));
            else
                if (#run >= 4) then
                    logged = logged + 1;
                    log_line(('menudump seq=%d %s utf16Run +%03X="%s"'):fmt(seq, label, run_start, run:concat('')));
                    if (logged >= limit) then
                        return;
                    end
                end
                run = T{};
            end
        end
        if (#run >= 4) then
            logged = logged + 1;
            log_line(('menudump seq=%d %s utf16Run +%03X="%s"'):fmt(seq, label, run_start, run:concat('')));
            if (logged >= limit) then
                return;
            end
        end
    end
end

function accessxi.escape_probe_log_text(text)
    text = clean_probe_text(text);
    text = text:gsub('"', "'");
    if (#text > 96) then
        text = text:sub(1, 96) .. '...';
    end
    return text;
end

function accessxi.escape_probe_log_text_wide(text)
    text = clean_probe_text(text);
    text = text:gsub('"', "'");
    if (#text > 320) then
        text = text:sub(1, 320) .. '...';
    end
    return text;
end

function accessxi.probe_text_candidate_ok(text, min_len)
    text = clean_probe_text(text);
    min_len = tonumber(min_len) or 2;
    if (#text < min_len) then
        return false;
    end

    if (text:match('^%p+$') ~= nil or text:match('^%d+$') ~= nil) then
        return false;
    end
    if (#text <= 4 and text:match('^(.)%1+$') ~= nil) then
        return false;
    end

    local lower = text:lower();
    if (lower:find('function ', 1, true) ~= nil
        or lower:find('__index', 1, true) ~= nil
        or lower:find('package.', 1, true) ~= nil
        or lower:find('accessxi', 1, true) ~= nil
        or lower:find('menudump', 1, true) ~= nil) then
        return false;
    end

    return true;
end

function accessxi.collect_probe_ascii_runs(ptr, length, min_len, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return T{};
    end

    length = tonumber(length) or 0;
    min_len = tonumber(min_len) or 2;
    limit = tonumber(limit) or 16;
    local parts = T{};
    local run = T{};
    local run_start = 0;

    for off = 0, length do
        local byte_value = off < length and read_u8(ptr + off) or nil;
        if (byte_value ~= nil and accessxi.probe_printable_ascii(byte_value)) then
            if (#run == 0) then
                run_start = off;
            end
            run:append(string.char(byte_value));
        else
            local text = run:concat('');
            if (accessxi.probe_text_candidate_ok(text, min_len)) then
                parts:append(('+%03X="%s"'):fmt(run_start, accessxi.escape_probe_log_text(text)));
                if (#parts >= limit) then
                    return parts;
                end
            end
            run = T{};
        end
    end

    return parts;
end

function accessxi.collect_probe_utf16_runs(ptr, length, min_len, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return T{};
    end

    length = tonumber(length) or 0;
    min_len = tonumber(min_len) or 2;
    limit = tonumber(limit) or 16;
    local parts = T{};

    for start_phase = 0, 1 do
        local run = T{};
        local run_start = start_phase;
        for off = start_phase, length - 2, 2 do
            local lo = read_u8(ptr + off);
            local hi = read_u8(ptr + off + 1);
            if (lo ~= nil and hi == 0 and accessxi.probe_printable_ascii(lo)) then
                if (#run == 0) then
                    run_start = off;
                end
                run:append(string.char(lo));
            else
                local text = run:concat('');
                if (accessxi.probe_text_candidate_ok(text, min_len)) then
                    parts:append(('+%03X="%s"'):fmt(run_start, accessxi.escape_probe_log_text(text)));
                    if (#parts >= limit) then
                        return parts;
                    end
                end
                run = T{};
            end
        end

        local text = run:concat('');
        if (accessxi.probe_text_candidate_ok(text, min_len)) then
            parts:append(('+%03X="%s"'):fmt(run_start, accessxi.escape_probe_log_text(text)));
            if (#parts >= limit) then
                return parts;
            end
        end
    end

    return parts;
end

function accessxi.probe_runs_to_text(runs)
    if (type(runs) == 'table') then
        return runs:concat(' | ');
    end
    return tostring(runs or '');
end

function accessxi.chat_log_probe_timestamp_marker_len(ptr)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr) or (read_u8(ptr) or 0) ~= 0x5B) then
        return 0;
    end

    local function digit(value)
        value = tonumber(value) or 0;
        return value >= 0x30 and value <= 0x39;
    end

    local b1 = read_u8(ptr + 1);
    local b2 = read_u8(ptr + 2);
    if (not digit(b1)) then
        return 0;
    end

    if (b2 == 0x3A) then
        if (digit(read_u8(ptr + 3)) and digit(read_u8(ptr + 4))) then
            if ((read_u8(ptr + 5) or 0) == 0x3A
                and digit(read_u8(ptr + 6))
                and digit(read_u8(ptr + 7))
                and ((read_u8(ptr + 8) or 0) == 0x5D)) then
                return 9;
            end
            if ((read_u8(ptr + 5) or 0) == 0x5D) then
                return 6;
            end
        end
        return 0;
    end

    if (digit(b2)
        and ((read_u8(ptr + 3) or 0) == 0x3A)
        and digit(read_u8(ptr + 4))
        and digit(read_u8(ptr + 5))) then
        if ((read_u8(ptr + 6) or 0) == 0x3A
            and digit(read_u8(ptr + 7))
            and digit(read_u8(ptr + 8))
            and ((read_u8(ptr + 9) or 0) == 0x5D)) then
            return 10;
        end
        if ((read_u8(ptr + 6) or 0) == 0x5D) then
            return 7;
        end
    end
    return 0;
end

function accessxi.chat_log_probe_timestamp_lines(ptr, length, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return '';
    end

    length = tonumber(length) or 0;
    limit = tonumber(limit) or 24;
    local parts = T{};
    local seen = {};
    local off = 0;
    while (off < length and #parts < limit) do
        local marker_len = accessxi.chat_log_probe_timestamp_marker_len(ptr + off);
        if (marker_len > 0) then
            local line = accessxi.chat_log_ascii_text_from_ptr(ptr + off, accessxi.chat_log_max_line_len);
            local speech = accessxi.chat_log_speech_text(line);
            local key = ('%04X:%s'):fmt(off, speech:lower());
            if (speech ~= '' and seen[key] ~= true) then
                seen[key] = true;
                parts:append(('+%04X="%s"'):fmt(off, accessxi.escape_probe_log_text(speech)));
            end
            off = off + marker_len;
        else
            off = off + 1;
        end
    end

    return parts:concat(' | ');
end

function accessxi.chat_log_probe_timestamp_context(ptr, length, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return '';
    end

    length = tonumber(length) or 0;
    limit = tonumber(limit) or 8;
    local parts = T{};
    local off = 0;
    while (off < length and #parts < limit) do
        local marker_len = accessxi.chat_log_probe_timestamp_marker_len(ptr + off);
        if (marker_len > 0) then
            local line = accessxi.chat_log_speech_text(accessxi.chat_log_ascii_text_from_ptr(ptr + off, accessxi.chat_log_max_line_len));
            local context_start = math.max(0, off - 0x24);
            parts:append(('+%04X="%s" %s'):fmt(
                off,
                accessxi.escape_probe_log_text(line),
                accessxi.format_probe_bytes(ptr, context_start, 0x80)));
            off = off + marker_len;
        else
            off = off + 1;
        end
    end

    return parts:concat(' | ');
end

function accessxi.decode_ffxi_menu_text_fragment(text)
    text = clean_probe_text(text);
    if (text == '') then
        return '';
    end

    local output = T{};
    local previous_word = false;
    for i = 1, #text do
        local byte_value = text:byte(i);
        local next_byte = i < #text and text:byte(i + 1) or 0;
        local decoded = byte_value;
        if (not previous_word
            and byte_value >= 0x21 and byte_value <= 0x3F
            and ((next_byte >= 0x41 and next_byte <= 0x5A) or next_byte == 0x27 or #text == 1)) then
            local candidate = bit.bxor(byte_value, 0x60);
            if (candidate >= 0x41 and candidate <= 0x5A) then
                decoded = candidate;
            end
        end

        output:append(string.char(decoded));
        previous_word = (decoded >= 0x30 and decoded <= 0x39)
            or (decoded >= 0x41 and decoded <= 0x5A)
            or (decoded >= 0x61 and decoded <= 0x7A);
    end

    return output:concat('');
end

function accessxi.collect_probe_ffxi_utf16_runs(ptr, length, min_len, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return T{};
    end

    length = tonumber(length) or 0;
    min_len = tonumber(min_len) or 2;
    limit = tonumber(limit) or 16;
    local parts = T{};

    for start_phase = 0, 1 do
        local run = T{};
        local run_start = start_phase;
        for off = start_phase, length - 2, 2 do
            local lo = read_u8(ptr + off);
            local hi = read_u8(ptr + off + 1);
            if (lo ~= nil and hi == 0 and accessxi.probe_printable_ascii(lo)) then
                if (#run == 0) then
                    run_start = off;
                end
                run:append(string.char(lo));
            else
                local text = accessxi.decode_ffxi_menu_text_fragment(run:concat(''));
                if (accessxi.probe_text_candidate_ok(text, min_len)) then
                    parts:append(('+%03X="%s"'):fmt(run_start, accessxi.escape_probe_log_text(text)));
                    if (#parts >= limit) then
                        return parts;
                    end
                end
                run = T{};
            end
        end

        local text = accessxi.decode_ffxi_menu_text_fragment(run:concat(''));
        if (accessxi.probe_text_candidate_ok(text, min_len)) then
            parts:append(('+%03X="%s"'):fmt(run_start, accessxi.escape_probe_log_text(text)));
            if (#parts >= limit) then
                return parts;
            end
        end
    end

    return parts;
end

function accessxi.collect_probe_ffxi_utf16_entries(ptr, length, min_len, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return T{};
    end

    length = tonumber(length) or 0;
    min_len = tonumber(min_len) or 2;
    limit = tonumber(limit) or 32;
    local entries = T{};

    for start_phase = 0, 1 do
        local run = T{};
        local run_start = start_phase;
        for off = start_phase, length - 2, 2 do
            local lo = read_u8(ptr + off);
            local hi = read_u8(ptr + off + 1);
            if (lo ~= nil and hi == 0 and accessxi.probe_printable_ascii(lo)) then
                if (#run == 0) then
                    run_start = off;
                end
                run:append(string.char(lo));
            else
                local text = accessxi.decode_ffxi_menu_text_fragment(run:concat(''));
                if (accessxi.probe_text_candidate_ok(text, min_len)) then
                    entries:append(T{ offset = run_start, text = text });
                    if (#entries >= limit) then
                        return entries;
                    end
                end
                run = T{};
            end
        end

        local text = accessxi.decode_ffxi_menu_text_fragment(run:concat(''));
        if (accessxi.probe_text_candidate_ok(text, min_len)) then
            entries:append(T{ offset = run_start, text = text });
            if (#entries >= limit) then
                return entries;
            end
        end
    end

    table.sort(entries, function (a, b)
        return (tonumber(a.offset) or 0) < (tonumber(b.offset) or 0);
    end);
    return entries;
end

function accessxi.log_probe_ffxi_menu_text(seq, label, ptr, length, min_len, limit)
    local runs = accessxi.collect_probe_ffxi_utf16_runs(ptr, length, min_len, limit);
    if (#runs > 0) then
        log_line(('menudump seq=%d %s ptr=0x%08X ffxiMenuText %s'):fmt(seq, label, tonumber(ptr) or 0, runs:concat(' ')));
    end
    accessxi.log_probe_ffxi_menu_lines(seq, label, ptr, length, min_len, limit);
    if ((label == 'sg.fast.child')
        or label:find('sg.fast.child+014+010', 1, true)
        or label:find('sg.fast.child+018+010', 1, true)) then
        accessxi.log_probe_ffxi_menu_line_bytes(seq, label, ptr, length, min_len, limit);
    end
end

function accessxi.log_probe_ffxi_menu_lines(seq, label, ptr, length, min_len, limit)
    local entries = accessxi.collect_probe_ffxi_utf16_entries(ptr, length, min_len, limit);
    if (#entries == 0) then
        return;
    end

    local lines = T{};
    local words = T{};
    local offsets = T{};
    local line_start = 0;
    local last_offset = -9999;
    local line_end = 0;

    local function flush()
        if (#words == 0) then
            return;
        end

        local text = accessxi.survival_guide_text(words:concat(' '));
        if (accessxi.probe_text_candidate_ok(text, 3) and (#words >= 2 or #text >= 6)) then
            lines:append(('+%03X-%03X="%s" [%s]'):fmt(line_start, line_end, accessxi.escape_probe_log_text(text), offsets:concat(',')));
        end
        words = T{};
        offsets = T{};
    end

    for _, entry in ipairs(entries) do
        local offset = tonumber(entry.offset) or 0;
        local text = accessxi.survival_guide_text(entry.text or '');
        if (text ~= '') then
            if (#words == 0) then
                line_start = offset;
            elseif ((offset - last_offset) > 0x24) then
                flush();
                line_start = offset;
            end

            words:append(text);
            offsets:append(('+%03X'):fmt(offset));
            line_end = offset + (#text * 2);
            last_offset = offset;
        end
    end
    flush();

    if (#lines > 0) then
        log_line(('menudump seq=%d %s ptr=0x%08X ffxiMenuLine %s'):fmt(seq, label, tonumber(ptr) or 0, lines:concat(' | ')));
    end
end

function accessxi.log_probe_ffxi_menu_line_bytes(seq, label, ptr, length, min_len, limit)
    local entries = accessxi.collect_probe_ffxi_utf16_entries(ptr, length, min_len, limit);
    if (#entries == 0) then
        return;
    end

    local logged = 0;
    for _, entry in ipairs(entries) do
        local offset = tonumber(entry.offset) or 0;
        local text = accessxi.survival_guide_text(entry.text or '');
        if (accessxi.probe_text_candidate_ok(text, 3) and (#text >= 5)) then
            local start = math.max(0, offset - 0x10);
            local bytes = accessxi.format_probe_bytes(ptr, start, 0x50);
            log_line(('menudump seq=%d %s ptr=0x%08X ffxiMenuBytes word+%03X="%s" %s'):fmt(
                seq,
                label,
                tonumber(ptr) or 0,
                offset,
                accessxi.escape_probe_log_text(text),
                bytes));
            logged = logged + 1;
            if (logged >= 8) then
                return;
            end
        end
    end
end

function accessxi.log_probe_short_text_runs(seq, label, ptr, length, min_len, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return;
    end

    local ascii = accessxi.collect_probe_ascii_runs(ptr, length, min_len, limit);
    if (#ascii > 0) then
        log_line(('menudump seq=%d %s ptr=0x%08X asciiShort %s'):fmt(seq, label, ptr, ascii:concat(' ')));
    end

    local utf16 = accessxi.collect_probe_utf16_runs(ptr, length, min_len, limit);
    if (#utf16 > 0) then
        log_line(('menudump seq=%d %s ptr=0x%08X utf16Short %s'):fmt(seq, label, ptr, utf16:concat(' ')));
    end

    accessxi.log_probe_ffxi_menu_text(seq, label, ptr, length, min_len, limit);
end

function accessxi.log_probe_pointer_text_targets(seq, label, ptr, start_offset, end_offset, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return;
    end

    limit = tonumber(limit) or 32;
    local seen = {};
    local logged = 0;
    for off = start_offset, end_offset, 4 do
        if (accessxi.menu_dump_textptr_budget ~= nil and accessxi.menu_dump_textptr_budget <= 0) then
            return;
        end
        if (logged >= limit) then
            return;
        end

        local target = read_u32(ptr + off);
        if (target ~= nil and accessxi.is_probe_pointer(target) and not seen[target]) then
            seen[target] = true;
            local ascii = accessxi.collect_probe_ascii_runs(target, 0x240, 2, 8);
            local utf16 = accessxi.collect_probe_utf16_runs(target, 0x240, 2, 8);
            local strings = accessxi.probe_strings_at(target);
            if (#ascii > 0 or #utf16 > 0 or strings ~= '') then
                logged = logged + 1;
                if (accessxi.menu_dump_textptr_budget ~= nil) then
                    accessxi.menu_dump_textptr_budget = accessxi.menu_dump_textptr_budget - 1;
                end
                log_line(('menudump seq=%d %s textPtr +%03X->0x%08X strings="%s" asciiShort="%s" utf16Short="%s"'):fmt(
                    seq,
                    label,
                    off,
                    target,
                    strings,
                    ascii:concat(' '),
                    utf16:concat(' ')));
            end
        end
    end
end

function accessxi.probe_utf16le_runs_at(ptr, length, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return '';
    end

    length = tonumber(length) or 0;
    limit = tonumber(limit) or 8;
    local parts = T{};
    for start_phase = 0, 1 do
        local run = T{};
        for off = start_phase, length - 2, 2 do
            local lo = read_u8(ptr + off);
            local hi = read_u8(ptr + off + 1);
            if (lo ~= nil and hi == 0 and accessxi.probe_printable_ascii(lo)) then
                run:append(string.char(lo));
            else
                if (#run >= 3) then
                    parts:append(('+%03X="%s"'):fmt(off - (#run * 2), run:concat('')));
                    if (parts:len() >= limit) then
                        return parts:concat(' ');
                    end
                end
                run = T{};
            end
        end
        if (#run >= 3) then
            parts:append(('+%03X="%s"'):fmt(length - (#run * 2), run:concat('')));
            if (parts:len() >= limit) then
                return parts:concat(' ');
            end
        end
    end
    return parts:concat(' ');
end

function accessxi.log_probe_bytes(seq, label, ptr, length)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return;
    end

    length = tonumber(length) or 0;
    for line_start = 0, length - 1, 0x20 do
        local hex = T{};
        local ascii = T{};
        for off = line_start, math.min(line_start + 0x1F, length - 1) do
            local byte_value = read_u8(ptr + off);
            hex:append(byte_value ~= nil and ('%02X'):fmt(byte_value) or '??');
            ascii:append(byte_value ~= nil and accessxi.probe_byte_ascii(byte_value) or '?');
        end
        log_line(('menudump seq=%d %s+%03X bytes=%s ascii="%s"'):fmt(seq, label, line_start, hex:concat(' '), ascii:concat('')));
    end
end

function accessxi.format_probe_bytes(ptr, offset, length)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_scan_address(ptr)) then
        return '';
    end

    offset = tonumber(offset) or 0;
    length = tonumber(length) or 0;
    local hex = T{};
    local ascii = T{};
    for off = offset, offset + length - 1 do
        local byte_value = read_u8(ptr + off);
        hex:append(byte_value ~= nil and ('%02X'):fmt(byte_value) or '??');
        ascii:append(byte_value ~= nil and accessxi.probe_byte_ascii(byte_value) or '?');
    end
    return ('bytes=%s ascii="%s"'):fmt(hex:concat(' '), ascii:concat(''));
end

function accessxi.format_probe_hex_bytes(ptr, offset, length)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_scan_address(ptr)) then
        return '';
    end

    offset = tonumber(offset) or 0;
    length = tonumber(length) or 0;
    local hex = T{};
    for off = offset, offset + length - 1 do
        local byte_value = read_u8(ptr + off);
        hex:append(byte_value ~= nil and ('%02X'):fmt(byte_value) or '??');
    end
    return hex:concat('');
end

function accessxi.format_probe_dwords(ptr, offset, count)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_scan_address(ptr)) then
        return '';
    end

    offset = tonumber(offset) or 0;
    count = tonumber(count) or 0;
    local parts = T{};
    for i = 0, count - 1 do
        local value = read_u32(ptr + offset + (i * 4));
        parts:append(value ~= nil and hex32(value) or '????????');
    end
    return parts:concat(',');
end

function accessxi.format_probe_index_fields(ptr, start_offset, end_offset)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return '';
    end

    local parts = T{};
    for off = tonumber(start_offset) or 0, tonumber(end_offset) or 0, 4 do
        local value = read_i32(ptr + off);
        if (value ~= nil and value >= -1 and value <= 256) then
            parts:append(('+%03X=%d'):fmt(off, value));
        end
    end
    return parts:concat(' ');
end

function accessxi.log_survival_guide_layout_probe(seq, label, ptr, selected, child_count)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return;
    end

    log_line(('menudump seq=%d %s layout indexes="%s" dwords000=%s dwords040=%s dwords080=%s'):fmt(
        seq,
        label,
        accessxi.format_probe_index_fields(ptr, 0x00, 0xA0),
        accessxi.format_probe_dwords(ptr, 0x00, 16),
        accessxi.format_probe_dwords(ptr, 0x40, 16),
        accessxi.format_probe_dwords(ptr, 0x80, 16)));

    local logged = 0;
    for off = 0x00, 0xA0, 4 do
        if (logged >= 36) then
            return;
        end

        local target = read_u32(ptr + off) or 0;
        if (accessxi.is_probe_pointer(target)) then
            logged = logged + 1;
            local desc = read_u32(target + 0x04) or 0;
            local desc_name = accessxi.is_probe_pointer(desc) and read_probe_string(desc + 0x46) or '';
            log_line(('menudump seq=%d %s ptrfield +%03X->0x%08X desc=0x%08X descName="%s" strings="%s" indexes="%s" dwords=%s'):fmt(
                seq,
                label,
                off,
                target,
                desc,
                desc_name,
                accessxi.probe_strings_at(target),
                accessxi.format_probe_index_fields(target, 0x00, 0x60),
                accessxi.format_probe_dwords(target, 0x00, 12)));
            accessxi.log_probe_value_hits(seq, ('%s.ptr+%03X'):fmt(label, off), target, 0x80, T{
                (tonumber(selected) or 0) - 1,
                tonumber(selected) or 0,
                tonumber(child_count) or 0
            });
        end
    end
end

function accessxi.log_survival_guide_selection_structure(obj, child, selected, visible_selected, page, child_count, raw, reason)
    obj = tonumber(obj) or 0;
    child = tonumber(child) or 0;
    if (not accessxi.is_probe_pointer(obj) or not accessxi.is_probe_pointer(child)) then
        return;
    end

    local key = ('%s:%08X:%08X:%d:%d:%d:%d:%08X:%d'):fmt(
        tostring(reason or ''),
        obj,
        child,
        tonumber(selected) or 0,
        tonumber(visible_selected) or 0,
        tonumber(page) or 0,
        tonumber(child_count) or 0,
        tonumber(raw) or 0,
        tonumber(accessxi.survival_guide_menu_id) or 0);
    if (key == accessxi.survival_guide_last_structure_key) then
        return;
    end
    accessxi.survival_guide_last_structure_key = key;

    local holder14 = read_u32(child + 0x14) or 0;
    local holder18 = read_u32(child + 0x18) or 0;
    local render14 = accessxi.is_probe_pointer(holder14) and (read_u32(holder14 + 0x10) or 0) or 0;
    local render18 = accessxi.is_probe_pointer(holder18) and (read_u32(holder18 + 0x10) or 0) or 0;
    log_state(('state survivalguide structure reason="%s" select=%d visible=%d page=%d count=%d raw=0x%08X obj=0x%08X child=0x%08X holders=0x%08X/0x%08X renders=0x%08X/0x%08X objIdx="%s" childIdx="%s" obj40=%s child00=%s child40=%s'):fmt(
        tostring(reason or ''),
        tonumber(selected) or 0,
        tonumber(visible_selected) or 0,
        tonumber(page) or 0,
        tonumber(child_count) or 0,
        tonumber(raw) or 0,
        obj,
        child,
        holder14,
        holder18,
        render14,
        render18,
        accessxi.format_probe_index_fields(obj, 0x20, 0x70),
        accessxi.format_probe_index_fields(child, 0x00, 0x70),
        accessxi.format_probe_dwords(obj, 0x40, 12),
        accessxi.format_probe_dwords(child, 0x00, 16),
        accessxi.format_probe_dwords(child, 0x40, 12)));
end

function accessxi.log_survival_guide_native_rows(seq, obj, selected, visible_selected, child_count, reason)
    obj = tonumber(obj) or 0;
    if (not accessxi.is_probe_pointer(obj)) then
        return;
    end

    local rows, child = accessxi.survival_guide_native_row_candidates(obj, true);
    local chosen, mode = accessxi.survival_guide_native_label_for_query(obj, visible_selected, selected, child_count, accessxi.survival_guide_context or '');
    local line = ('menudump seq=%d sg.rows reason="%s" selected=%d visible=%d count=%d child=0x%08X mode="%s" chosen="%s" candidates=%s'):fmt(
        tonumber(seq) or 0,
        tostring(reason or ''),
        tonumber(selected) or 0,
        tonumber(visible_selected) or 0,
        tonumber(child_count) or 0,
        tonumber(child) or 0,
        tostring(mode or ''),
        accessxi.escape_probe_log_text(chosen or ''),
        accessxi.survival_guide_format_native_row_candidates(rows));
    log_line(line);
end

function accessxi.log_survival_guide_render_node_probe(seq, label, ptr, depth)
    ptr = tonumber(ptr) or 0;
    depth = tonumber(depth) or 0;
    if (not accessxi.is_probe_pointer(ptr) or depth > 2) then
        return;
    end
    if (accessxi.menu_dump_render_node_budget ~= nil) then
        if (accessxi.menu_dump_render_node_budget <= 0) then
            return;
        end
        accessxi.menu_dump_render_node_budget = accessxi.menu_dump_render_node_budget - 1;
    end

    log_line(('menudump seq=%d %s ptr=0x%08X strings="%s" utf16="%s" dwords=%s'):fmt(
        seq,
        label,
        ptr,
        accessxi.probe_strings_at(ptr),
        accessxi.probe_utf16le_runs_at(ptr, 0x180, 12),
        accessxi.format_probe_dwords(ptr, 0, 32)));
    accessxi.log_probe_short_text_runs(seq, label, ptr, 0x240, 2, 18);
    accessxi.log_probe_pointer_text_targets(seq, label, ptr, 0x00, 0x13C, 20);
    log_line(('menudump seq=%d %s raw0 %s'):fmt(seq, label, accessxi.format_probe_bytes(ptr, 0, 0x40)));
    log_line(('menudump seq=%d %s raw40 %s'):fmt(seq, label, accessxi.format_probe_bytes(ptr, 0x40, 0x40)));

    local followed = 0;
    for off = 0, 0x17C, 4 do
        if (followed >= 32) then
            break;
        end

        local child = read_u32(ptr + off);
        if (child ~= nil and accessxi.is_probe_pointer(child)) then
            local strings = accessxi.probe_strings_at(child);
            local first = read_u32(child) or 0;
            local desc = read_u32(child + 0x04) or 0;
            if (strings ~= '' or accessxi.is_probe_pointer(first) or accessxi.is_probe_pointer(desc)) then
                followed = followed + 1;
                log_line(('menudump seq=%d %s child+%03X ptr=0x%08X first=0x%08X desc=0x%08X strings="%s" utf16="%s" dwords=%s'):fmt(
                    seq,
                    label,
                    off,
                    child,
                    first,
                    desc,
                    strings,
                    accessxi.probe_utf16le_runs_at(child, 0x180, 12),
                    accessxi.format_probe_dwords(child, 0, 16)));
                accessxi.log_probe_short_text_runs(seq, ('%s.child%03X'):fmt(label, off), child, 0x240, 2, 12);
                accessxi.log_probe_pointer_text_targets(seq, ('%s.child%03X'):fmt(label, off), child, 0x00, 0xFC, 12);
                if (depth < 2) then
                    accessxi.log_survival_guide_render_node_probe(seq, ('%s.child%03X'):fmt(label, off), child, depth + 1);
                end
            end
        end
    end
end

function accessxi.format_survival_guide_entries(entries, limit)
    local parts = T{};
    limit = tonumber(limit) or 48;
    for i = 1, math.min(entries ~= nil and entries:len() or 0, limit) do
        local entry = entries[i];
        if (entry ~= nil) then
            parts:append(('%d:%s(bit=%d zone=%d)'):fmt(
                tonumber(entry.index) or -1,
                tostring(entry.label or ''),
                tonumber(entry.unlock_bit) or -1,
                tonumber(entry.zone) or -1));
        end
    end
    return parts:concat(' | ');
end

function accessxi.add_probe_hit(hits, label, off, width, value)
    append_limited(hits, ('%s+%03X/%s=%d'):fmt(label, off, width, value), 80);
end

function accessxi.log_probe_value_hits(seq, label, ptr, length, values)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr) or values == nil or #values == 0) then
        return;
    end

    local wanted = {};
    for _, value in ipairs(values) do
        value = tonumber(value) or -1;
        if (value >= 0 and value <= 65535) then
            wanted[value] = true;
        end
    end

    local hits = T{};
    for off = 0, (tonumber(length) or 0) - 1 do
        local b = read_u8(ptr + off);
        if (b ~= nil and wanted[b]) then
            accessxi.add_probe_hit(hits, label, off, 'u8', b);
        end

        if (off + 1 < length) then
            local w = read_u16(ptr + off);
            if (w ~= nil and wanted[w]) then
                accessxi.add_probe_hit(hits, label, off, 'u16', w);
            end
        end

        if (hits:len() >= 80) then
            break;
        end
    end

    log_line(('menudump seq=%d %s valueHits=%s'):fmt(seq, label, hits:concat(' ')));
end

function accessxi.log_survival_guide_resolution_probe(seq, obj, child, selected, child_count)
    local category = tonumber(accessxi.survival_guide_last_area_category) or 0;
    local region_category = tonumber(accessxi.survival_guide_last_region_category) or 0;
    local destinations, mode, content = nil, '', -1;
    if (region_category > 0 and category == 0) then
        destinations, mode = accessxi.survival_guide_region_destination_list(region_category, child_count);
    else
        destinations, mode, content = accessxi.survival_guide_destination_list(category, child_count);
    end

    local selected_entry = destinations ~= nil and destinations[selected] or nil;

    log_line(('menudump seq=%d sg.resolve selected=%d count=%d category=%d region=%d content=%d mode="%s" current=%d menuId=%d params="%s" unlockBits="%s" selectedCandidate="%s" candidates="%s"'):fmt(
        seq,
        tonumber(selected) or 0,
        tonumber(child_count) or 0,
        category,
        region_category,
        tonumber(content) or -1,
        tostring(mode or ''),
        tonumber(accessxi.survival_guide_current_index) or -1,
        tonumber(accessxi.survival_guide_menu_id) or 0,
        accessxi.packet_hex(accessxi.survival_guide_params or ''),
        accessxi.packet_set_bits(accessxi.survival_guide_unlocks or '', 127),
        selected_entry ~= nil and accessxi.format_survival_guide_entries(T{ selected_entry }, 1) or '',
        accessxi.format_survival_guide_entries(destinations or T{}, 64)));
end

function accessxi.survival_guide_compact_text_at(ptr, length, limit)
    ptr = tonumber(ptr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return '';
    end

    length = tonumber(length) or 0xC0;
    limit = tonumber(limit) or 4;
    local parts = T{};
    local seen = {};
    local function add(kind, text)
        text = tostring(text or '');
        if (text == '') then
            return;
        end
        local key = kind .. ':' .. text;
        if (seen[key] == true) then
            return;
        end
        seen[key] = true;
        parts:append(('%s=%s'):fmt(kind, text));
    end

    local ffxi = accessxi.collect_probe_ffxi_utf16_runs(ptr, length, 2, limit);
    if (#ffxi > 0) then
        add('ffxi', ffxi:concat(' '));
    end

    local utf16 = accessxi.collect_probe_utf16_runs(ptr, length, 3, limit);
    if (#utf16 > 0) then
        add('utf16', utf16:concat(' '));
    end

    local ascii = accessxi.collect_probe_ascii_runs(ptr, length, 3, limit);
    if (#ascii > 0) then
        add('ascii', ascii:concat(' '));
    end

    if (#parts > 3) then
        local limited = T{};
        for i = 1, 3 do
            limited:append(parts[i]);
        end
        return limited:concat(' || ');
    end
    return parts:concat(' || ');
end

function accessxi.survival_guide_entry_pointer_texts(entry)
    entry = tonumber(entry) or 0;
    if (not accessxi.is_probe_pointer(entry)) then
        return '';
    end

    local parts = T{};
    local seen = {};
    for field = 0, 0x28, 4 do
        local ptr = read_u32(entry + field) or 0;
        if (accessxi.is_probe_pointer(ptr) and seen[ptr] ~= true) then
            seen[ptr] = true;
            local text = accessxi.survival_guide_compact_text_at(ptr, 0xC0, 3);
            if (text ~= '') then
                parts:append(('+%02X->0x%08X{%s}'):fmt(field, ptr, text));
                if (#parts >= 4) then
                    break;
                end
            end
        end
    end
    return parts:concat(' ');
end

function accessxi.survival_guide_collect_long_probe_seeds(obj, child)
    local seeds = T{};
    local seen = {};
    local function add(label, ptr)
        ptr = tonumber(ptr) or 0;
        if (not accessxi.is_probe_pointer(ptr) or seen[ptr] == true) then
            return;
        end
        seen[ptr] = true;
        seeds:append(T{ label = label, ptr = ptr });
    end

    add('obj', obj);
    add('child', child);

    for _, spec in ipairs(T{
        T{ base = obj, label = 'obj', first = 0x00, last = 0xA0 },
        T{ base = child, label = 'child', first = 0x00, last = 0xE0 },
    }) do
        local base = tonumber(spec.base) or 0;
        if (accessxi.is_probe_pointer(base)) then
            for off = spec.first, spec.last, 4 do
                local ptr = read_u32(base + off) or 0;
                if (accessxi.is_probe_pointer(ptr)) then
                    add(('%s+%03X'):fmt(spec.label, off), ptr);
                    if (spec.label == 'child' and (off == 0x14 or off == 0x18 or off == 0x38 or off == 0x54 or off == 0x60 or off == 0x88 or off == 0xC8)) then
                        for inner = 0x00, 0x80, 4 do
                            local nested = read_u32(ptr + inner) or 0;
                            if (accessxi.is_probe_pointer(nested)) then
                                add(('%s+%03X+%03X'):fmt(spec.label, off, inner), nested);
                            end
                        end
                    end
                end
            end
        end
    end

    return seeds;
end

function accessxi.log_survival_guide_long_list_probe(seq, obj, child, selected, visible_selected, page, child_count, reason)
    obj = tonumber(obj) or 0;
    child = tonumber(child) or 0;
    selected = tonumber(selected) or 0;
    visible_selected = tonumber(visible_selected) or 0;
    page = tonumber(page) or 0;
    child_count = tonumber(child_count) or 0;

    if (not accessxi.is_probe_pointer(obj) or not accessxi.is_probe_pointer(child) or child_count <= 4) then
        return;
    end

    local abs_index = selected > 0 and (selected - 1) or -1;
    local pagevis_index = (page >= 0 and visible_selected > 0) and (page + visible_selected - 1) or -1;
    local visible_index = visible_selected > 0 and (visible_selected - 1) or -1;
    local indices = T{
        T{ name = 'abs', value = abs_index },
        T{ name = 'pagevis', value = pagevis_index },
        T{ name = 'vis', value = visible_index },
        T{ name = 'page', value = page },
    };

    log_line(('menudump seq=%d sg.long begin reason="%s" selected=%d visible=%d page=%d count=%d context="%s" menuKind=%d menuId=%d zone=%d current=%d params="%s" unlockBits="%s"'):fmt(
        seq,
        tostring(reason or ''),
        selected,
        visible_selected,
        page,
        child_count,
        tostring(accessxi.survival_guide_context or ''),
        tonumber(accessxi.survival_guide_menu_kind_for_obj(obj)) or 0,
        tonumber(accessxi.survival_guide_menu_id) or 0,
        tonumber(accessxi.survival_guide_zone) or 0,
        tonumber(accessxi.survival_guide_current_index) or -1,
        accessxi.packet_hex(accessxi.survival_guide_params or ''),
        accessxi.packet_set_bits(accessxi.survival_guide_unlocks or '', 127)));
    log_line(('menudump seq=%d sg.long objIdx="%s" childIdx="%s" objDwords=%s childDwords=%s'):fmt(
        seq,
        accessxi.format_probe_index_fields(obj, 0x00, 0xA0),
        accessxi.format_probe_index_fields(child, 0x00, 0xA0),
        accessxi.format_probe_dwords(obj, 0x00, 24),
        accessxi.format_probe_dwords(child, 0x00, 24)));

    local seeds = accessxi.survival_guide_collect_long_probe_seeds(obj, child);
    local logged = 0;
    for _, seed in ipairs(seeds) do
        if (logged >= 72) then
            break;
        end

        local ptr = tonumber(seed.ptr) or 0;
        local base_text = accessxi.survival_guide_compact_text_at(ptr, 0x100, 3);
        local first_dwords = accessxi.format_probe_dwords(ptr, 0x00, 8);
        local probes = T{};
        local text_hits = T{};
        local stride_set = T{ 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 64, 80, 96, 0x118 };
        local compact_stride_set = T{ 4, 8, 16, 32, 64, 0x118 };
        local seen_probe_key = {};

        for _, stride in ipairs(compact_stride_set) do
            for _, index in ipairs(indices) do
                local index_value = tonumber(index.value) or -1;
                if (index_value >= 0 and index_value <= math.max(child_count + 4, 8)) then
                    local probe_key = ('%d:%d'):fmt(stride, index_value);
                    if (seen_probe_key[probe_key] ~= true) then
                        seen_probe_key[probe_key] = true;
                        local entry = ptr + (index_value * stride);
                        local d0 = read_u32(entry);
                        local d1 = read_u32(entry + 4);
                        if ((d0 ~= nil and d0 ~= 0) or (d1 ~= nil and d1 ~= 0)) then
                            probes:append(('%s:s%03X@+%03X=%08X,%08X'):fmt(
                                index.name,
                                stride,
                                index_value * stride,
                                tonumber(d0) or 0,
                                tonumber(d1) or 0));
                        end
                    end
                end
            end
        end

        for _, stride in ipairs(stride_set) do
            if (abs_index >= 0 and abs_index <= math.max(child_count + 4, 8)) then
                local entry = ptr + (abs_index * stride);
                local text = accessxi.survival_guide_compact_text_at(entry, math.min(stride + 0x60, 0xC0), 3);
                local ptr_text = accessxi.survival_guide_entry_pointer_texts(entry);
                if (text ~= '' or ptr_text ~= '') then
                    text_hits:append(('abs:s%03X@0x%08X dwords=%s text="%s" ptrText="%s"'):fmt(
                        stride,
                        entry,
                        accessxi.format_probe_dwords(entry, 0, 8),
                        accessxi.escape_probe_log_text(text),
                        accessxi.escape_probe_log_text(ptr_text)));
                    if (#text_hits >= 8) then
                        break;
                    end
                end
            end
        end

        if (base_text ~= '' or #text_hits > 0 or #probes > 0) then
            logged = logged + 1;
            log_line(('menudump seq=%d sg.long seed src="%s" ptr=0x%08X baseText="%s" dwords=%s probes="%s" textHits="%s"'):fmt(
                seq,
                tostring(seed.label or ''),
                ptr,
                accessxi.escape_probe_log_text(base_text),
                first_dwords,
                probes:concat(' | '),
                text_hits:concat(' || ')));
        end
    end

    log_line(('menudump seq=%d sg.long end seeds=%d logged=%d'):fmt(seq, seeds:len(), logged));
end

function accessxi.log_survival_guide_shape_text_probe(seq)
    local target = AshitaCore:GetMemoryManager():GetTarget();
    if (target == nil) then
        return;
    end

    for i = 0, 8 do
        local shape = tonumber(safe_call(function () return target:GetWindowAnkShape(i); end, 0)) or 0;
        if (accessxi.is_probe_pointer(shape)) then
            log_line(('menudump seq=%d sg.shape index=%d ptr=0x%08X strings="%s"'):fmt(
                seq,
                i,
                shape,
                accessxi.probe_strings_at(shape)));
            accessxi.log_probe_ascii_runs(seq, ('sg.shape%d'):fmt(i), shape, 0x180, 12);
            accessxi.log_probe_utf16_runs(seq, ('sg.shape%d'):fmt(i), shape, 0x180, 12);
            accessxi.log_probe_short_text_runs(seq, ('sg.shape%d'):fmt(i), shape, 0x300, 2, 24);
            accessxi.log_probe_pointer_text_targets(seq, ('sg.shape%d'):fmt(i), shape, 0x00, 0x180, 24);
            accessxi.log_survival_guide_render_node_probe(seq, ('sg.shape%d.render'):fmt(i), shape, 0);
            log_menu_dump_pointer_targets(seq, shape, 0x00, 0x120);
        end
    end
end

function accessxi.log_survival_guide_menu_text_probe(seq, obj, child)
    obj = tonumber(obj) or 0;
    child = tonumber(child) or 0;

    if (not accessxi.is_probe_pointer(child)) then
        return;
    end

    accessxi.log_probe_ffxi_menu_text(seq, 'sg.fast.child', child, 0x100, 2, 24);
    for _, off in ipairs(T{ 0x00, 0x08, 0x0C, 0x14, 0x18, 0x1C, 0x20, 0x38, 0x54, 0x60, 0x88, 0xC8 }) do
        local ptr = read_u32(child + off) or 0;
        if (accessxi.is_probe_pointer(ptr)) then
            accessxi.log_probe_ffxi_menu_text(seq, ('sg.fast.child+%03X'):fmt(off), ptr, 0x300, 2, 32);
            for _, inner_off in ipairs(T{ 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x38, 0x50, 0x54, 0x60, 0x78, 0x88, 0xC8 }) do
                local nested = read_u32(ptr + inner_off) or 0;
                if (accessxi.is_probe_pointer(nested)) then
                    accessxi.log_probe_ffxi_menu_text(seq, ('sg.fast.child+%03X+%03X'):fmt(off, inner_off), nested, 0x300, 2, 32);
                end
            end
        end
    end
end

function accessxi.log_survival_guide_nearby_menu_objects(seq, obj)
    obj = tonumber(obj) or 0;
    if (obj == 0) then
        return;
    end

    for delta = -0x1D0, 0x2B8, 0xE8 do
        local candidate = obj + delta;
        if (accessxi.is_probe_pointer(candidate)) then
            local desc = read_u32(candidate + 0x04) or 0;
            local desc_name = read_probe_string(desc + 0x46);
            local selected, page, raw, child, count = accessxi.survival_guide_query_child_state_for_obj(candidate);
            local marker = read_i32(candidate + 0x34) or 0;
            local obj_count = read_i32(candidate + 0x24) or 0;
            local obj_count2 = read_i32(candidate + 0x28) or 0;
            local obj_selected = read_i32(candidate + 0x4C) or -1;
            log_line(('menudump seq=%d sg.nearby delta=%+d obj=0x%08X desc=0x%08X descName="%s" objSel=%d objCount=%d/%d marker=%d selected=%d page=%d count=%d raw=0x%08X child=0x%08X'):fmt(
                seq,
                delta,
                candidate,
                desc,
                desc_name,
                obj_selected,
                obj_count,
                obj_count2,
                marker,
                selected,
                page,
                count or 0,
                raw or 0,
                child or 0));
            if (accessxi.is_probe_pointer(child)
                and ((count or 0) > 0 or desc_name:eq('menu    query', true) or desc_name:eq('menu    inline', true))) then
                accessxi.log_survival_guide_menu_text_probe(seq, candidate, child);
            end
        end
    end
end

function accessxi.log_survival_guide_deep_text_probe(seq, obj, child)
    obj = tonumber(obj) or 0;
    child = tonumber(child) or 0;

    accessxi.log_probe_short_text_runs(seq, 'sg.obj.deep', obj, 0x400, 2, 32);
    accessxi.log_probe_short_text_runs(seq, 'sg.child.deep', child, 0x400, 2, 32);
    accessxi.log_probe_pointer_text_targets(seq, 'sg.obj.deep', obj, 0x00, 0x1FC, 48);
    accessxi.log_probe_pointer_text_targets(seq, 'sg.child.deep', child, 0x00, 0x1FC, 48);

    if (accessxi.is_probe_pointer(child)) then
        for off = 0, 0x1FC, 4 do
            local ptr = read_u32(child + off);
            if (ptr ~= nil and accessxi.is_probe_pointer(ptr)) then
                accessxi.log_probe_pointer_text_targets(seq, ('sg.child.deep+%03X'):fmt(off), ptr, 0x00, 0xFC, 16);
            end
        end
    end
end

function accessxi.log_survival_guide_native_text_probe(seq, obj, reason)
    obj = tonumber(obj) or 0;
    if (obj == 0) then
        return;
    end

    local target = AshitaCore:GetMemoryManager():GetTarget();
    local window_name = accessxi.survival_guide_text(target ~= nil and safe_call(function () return target:GetWindowName(); end, '') or '');
    if (not window_name:eq('Survival Guide', true)) then
        return;
    end

    local selected, page, raw, child, child_count = accessxi.survival_guide_query_child_state_for_obj(obj);
    local visible_selected = tonumber(read_i32(obj + 0x4C)) or accessxi.native_menu_index(0x4C);
    local deep_dump = tostring(reason or ''):contains('deep');
    accessxi.menu_dump_render_node_budget = deep_dump and 96 or 0;
    accessxi.menu_dump_textptr_budget = deep_dump and 240 or 0;
    log_line(('menudump seq=%d sgtext selected=%d visible=%d page=%d count=%d raw=0x%08X child=0x%08X obj=0x%08X'):fmt(
        seq,
        selected,
        visible_selected,
        page,
        tonumber(child_count) or 0,
        raw,
        child,
        obj));

    log_line(('menudump seq=%d sg.direct objStrings="%s" childStrings="%s"'):fmt(
        seq,
        accessxi.probe_strings_at(obj),
        accessxi.probe_strings_at(child)));

    accessxi.log_probe_ascii_runs(seq, 'sg.obj', obj, 0x240, 18);
    accessxi.log_probe_utf16_runs(seq, 'sg.obj', obj, 0x240, 18);
    accessxi.log_probe_ascii_runs(seq, 'sg.child', child, 0x240, 18);
    accessxi.log_probe_utf16_runs(seq, 'sg.child', child, 0x240, 18);
    accessxi.log_survival_guide_native_rows(seq, obj, selected, visible_selected, child_count, reason or '');
    accessxi.log_survival_guide_layout_probe(seq, 'sg.obj', obj, selected, child_count);
    accessxi.log_survival_guide_layout_probe(seq, 'sg.child', child, selected, child_count);
    accessxi.log_survival_guide_menu_text_probe(seq, obj, child);
    accessxi.log_survival_guide_nearby_menu_objects(seq, obj);
    if (tostring(reason or ''):contains('hotkey', true)
        or tostring(reason or ''):contains('command', true)
        or deep_dump) then
        accessxi.log_survival_guide_long_list_probe(seq, obj, child, selected, visible_selected, page, child_count, reason or '');
    end
    if (deep_dump) then
        accessxi.log_survival_guide_deep_text_probe(seq, obj, child);
        log_menu_dump_pointer_targets(seq, obj, 0x00, 0x17C);
        log_menu_dump_pointer_targets(seq, child, 0x00, 0x17C);
        accessxi.log_survival_guide_shape_text_probe(seq);
    end

    accessxi.log_probe_value_hits(seq, 'sg.obj', obj, 0x180, T{ selected - 1, selected, visible_selected, page, child_count });
    accessxi.log_probe_value_hits(seq, 'sg.child', child, 0x80, T{ selected - 1, selected, visible_selected, page, child_count });

    accessxi.log_survival_guide_resolution_probe(seq, obj, child, selected, child_count);
    accessxi.menu_dump_render_node_budget = nil;
    accessxi.menu_dump_textptr_budget = nil;
end

local function dump_current_menu(reason, quiet)
    accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;

    local seq = accessxi.menu_dump_sequence;
    local name = get_menu_name() or '';
    local obj = get_current_menu_object_ptr();
    local desc = obj ~= 0 and (read_u32(obj + 0x04) or 0) or 0;
    local vtbl = obj ~= 0 and (read_u32(obj) or 0) or 0;
    local base = get_ffximain_base();
    local target = AshitaCore:GetMemoryManager():GetTarget();
    local window_name = accessxi.survival_guide_text(target ~= nil and safe_call(function () return target:GetWindowName(); end, '') or '');
    local survival_guide_dump = window_name:eq('Survival Guide', true);

    log_line(('menudump begin seq=%d reason=%s menu="%s" obj=0x%08X vtbl=0x%08X desc=0x%08X descName="%s" ffximain=0x%08X mirrorGrid=%d'):fmt(
        seq,
        reason or '',
        name,
        obj,
        vtbl,
        desc,
        read_probe_string(desc + 0x46),
        base,
        tonumber(accessxi.equipment_cursor_grid) or -1));

    if (survival_guide_dump) then
        accessxi.log_survival_guide_native_text_probe(seq, obj, reason or '');
        log_line(('menudump end seq=%d'):fmt(seq));
        if (not quiet) then
            speak(('Menu dump %d written.'):fmt(seq));
        end
        return;
    end

    log_line(('menudump seq=%d target %s'):fmt(seq, current_target_snapshot()));
    log_line(('menudump seq=%d static layout=%s equipDesc=%s equipRuntime=%s invRuntime=%s'):fmt(
        seq,
        format_runtime_dwords(base, 0x36F7E8, 16),
        format_runtime_dwords(base, 0x3729E4, 8),
        format_runtime_dwords(base, 0x5781A8, 12),
        format_runtime_dwords(base, 0x630C20, 12)));

    log_menu_dump_shapes(seq);
    log_menu_dump_dwords(seq, obj, 0x00, 0x1FC);
    log_menu_dump_candidates(seq, obj, 0x00, 0x1FC);
    log_menu_dump_pointer_targets(seq, obj, 0x00, 0x1FC);
    accessxi.log_survival_guide_native_text_probe(seq, obj);
    log_line(('menudump end seq=%d'):fmt(seq));

    if (not quiet) then
        speak(('Menu dump %d written.'):fmt(seq));
    end
end

accessxi.debug_probe_dump_current_menu = dump_current_menu;

local function maybe_auto_dump_menu(name)
    name = tostring(name or '');
    if (not name:eq('menu    menuwind', true)
        and not name:eq('menu    socialme', true)) then
        return;
    end

    local obj = get_current_menu_object_ptr();
    if (obj == 0) then
        return;
    end

    local selected = read_current_native_menu_index(0x4C);
    local key = ('%s:0x%08X:%d'):fmt(name, obj, selected);
    if (key == accessxi.last_main_menu_native_dump_key) then
        return;
    end
    accessxi.last_main_menu_native_dump_key = key;

    dump_current_menu('auto-main-menu-native-missing', true);
end

local function maybe_auto_dump_chat_log_menu(name)
    -- Keep chat-log probing manual; automatic dumps are noisy and can make the
    -- live log harder to use while testing speech.
    local enabled = false;
    if (not enabled) then
        return;
    end

    name = tostring(name or '');
    local lower = name:lower();

    local target = AshitaCore:GetMemoryManager():GetTarget();
    local window_name = '';
    if (target ~= nil) then
        window_name = clean_probe_text(safe_call(function () return target:GetWindowName(); end, ''));
    end
    local window_lower = window_name:lower();

    if (lower:find('chat', 1, true) == nil
        and lower:find('log', 1, true) == nil
        and window_lower:find('chat', 1, true) == nil
        and window_lower:find('log', 1, true) == nil) then
        return;
    end

    local obj = get_current_menu_object_ptr();
    if (obj == 0) then
        return;
    end

    local selected = read_current_native_menu_index(0x4C);
    local key = ('%s:%s:0x%08X:%d'):fmt(name, window_name, obj, selected);
    if (key == (accessxi.last_auto_chat_log_dump_key or '')) then
        return;
    end
    accessxi.last_auto_chat_log_dump_key = key;

    dump_current_menu('auto-chat-log-menu', true);
end

accessxi.debug_probe_maybe_auto_dump_menu = maybe_auto_dump_menu;
accessxi.debug_probe_maybe_auto_dump_chat_log_menu = maybe_auto_dump_chat_log_menu;


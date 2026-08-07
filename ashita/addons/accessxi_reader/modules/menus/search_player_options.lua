local data = {}

local ctx = search_player_options_context or {}

function data.resolve_native_help(menu_name, selected, entry, is_pointer, read_u32, read_string)
    if tostring(menu_name or '') ~= 'menu    scoption' then
        return nil, 'unsupported-menu'
    end

    selected = tonumber(selected) or 0
    if selected <= 0 then
        return nil, 'invalid-selection'
    end
    if type(is_pointer) ~= 'function' or type(read_u32) ~= 'function' or type(read_string) ~= 'function' then
        return nil, 'invalid-reader'
    end

    entry = tonumber(entry) or 0
    if not is_pointer(entry) then
        return nil, 'invalid-entry'
    end

    local help_ptr = tonumber(read_u32(entry + 0x40)) or 0
    if not is_pointer(help_ptr) then
        return nil, 'invalid-help-pointer', help_ptr
    end

    local text = tostring(read_string(help_ptr) or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    if text == '' then
        return nil, 'empty-native-help', help_ptr
    end
    return text, 'native-entry-help', help_ptr
end

if type(accessxi) == 'table' then
    local is_pointer = ctx.is_pointer or function () return false end
    local read_u32 = ctx.read_u32 or function () return 0 end
    local read_string = ctx.read_string or function () return '' end
    local clean_help = ctx.clean_help or function (text)
        return tostring(text or ''):gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    end
    local escape_log_text = ctx.escape_log_text or function (text) return tostring(text or '') end
    local log_state = ctx.log_state or function () end
    local tick = ctx.tick or function () return 0 end

    function accessxi.search_player_option_menu_speech(menu_name, selected, entry)
        menu_name = tostring(menu_name or '')
        selected = tonumber(selected) or 0
        entry = tonumber(entry) or 0

        local text, reason, help_ptr = data.resolve_native_help(
            menu_name, selected, entry, is_pointer, read_u32, read_string)
        if text ~= nil then
            text = clean_help(text)
            if text == '' then
                reason = 'sanitized-empty'
            end
        end

        if text == nil or text == '' then
            log_state(string.format(
                'state search-player-option quiet menu="%s" select=%d entry=0x%08X help=0x%08X reason="%s" source="entry+0x40"',
                escape_log_text(menu_name), selected, entry, tonumber(help_ptr) or 0,
                escape_log_text(reason or 'missing-native-help')))
            return nil
        end

        accessxi.last_native_menu_name = menu_name
        accessxi.last_native_menu_label = text
        accessxi.last_native_menu_selected = selected
        accessxi.last_native_menu_tick = tick()
        accessxi.current_speech_key = string.format(
            'search-player-option:%s:%d:0x%08X:%s', menu_name, selected, entry, text)
        log_state(string.format(
            'state search-player-option menu="%s" select=%d entry=0x%08X help=0x%08X text="%s" source="entry+0x40"',
            escape_log_text(menu_name), selected, entry, tonumber(help_ptr) or 0,
            escape_log_text(text)))
        return text
    end
end

return data

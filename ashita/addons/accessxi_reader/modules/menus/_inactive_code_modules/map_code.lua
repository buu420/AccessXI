function accessxi.map_menu_entry_text(entry, selected)
    entry = tonumber(entry) or 0;
    selected = tonumber(selected) or 0;
    if (not accessxi.is_probe_pointer(entry)) then
        return '', 'none';
    end

    local rendered = '';
    if (accessxi.search_result_rendered_row_text ~= nil) then
        rendered = accessxi.plain_native_menu_label(accessxi.search_result_rendered_row_text(entry, selected));
        if (rendered ~= '') then
            return rendered, 'rendered-row';
        end
    end

    local label_ptr = read_u32(entry + 0x44) or 0;
    local help_ptr = read_u32(entry + 0x40) or 0;
    local label = accessxi.plain_native_menu_label(read_probe_string(label_ptr, 160));
    if (label ~= '') then
        return label, 'entry+44';
    end

    label = accessxi.plain_native_menu_label(read_probe_string(help_ptr, 220));
    if (label ~= '') then
        return label, 'entry+40';
    end

    return '', 'empty';
end

accessxi.map_menu_data = accessxi.load_menu_module_table('map', T{ main_rows = T{} });

function accessxi.map_menu_static_entry(selected)
    selected = tonumber(selected) or 0;
    local rows = accessxi.map_menu_data.main_rows or T{};

    if (selected < 1 or selected > rows:len()) then
        local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
        local ank = target ~= nil and (tonumber(safe_call(function () return target:GetWindowAnkNum(); end, -1)) or -1) or -1;
        if (ank >= 0 and ank < rows:len()) then
            selected = ank + 1;
        end
    end

    return rows[selected];
end

function accessxi.map_current_zone_name()
    local zone = tonumber(accessxi.current_zone_id()) or 0;
    if (zone <= 0) then
        return '';
    end

    return accessxi.plain_native_menu_label(safe_call(function ()
        return AshitaCore:GetResourceManager():GetString('zones.names', zone);
    end, '') or '');
end

function accessxi.map_clean_native_label(text)
    text = accessxi.survival_guide_text(text or '');
    if (text == '') then
        return '';
    end

    text = text:gsub('%z.*$', ''):gsub('[%c]', ''):gsub('%s+', ' '):trim();
    text = text:gsub('^["\']+', ''):gsub('["\']+$', '');
    if (text == '' or #text > 80) then
        return '';
    end
    if (text:match('^[%p%s]+$') ~= nil) then
        return '';
    end
    if (text:find('menu    ', 1, true) ~= nil or text:find('anc     ', 1, true) ~= nil) then
        return '';
    end
    return text;
end

function accessxi.map_native_window_label()
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    if (target == nil) then
        return '';
    end

    local window_name = accessxi.map_clean_native_label(safe_call(function ()
        return target:GetWindowName();
    end, '') or '');
    if (window_name == '' or window_name:eq('Map', true) or window_name:eq('Markers', true)) then
        return '';
    end
    return window_name;
end

function accessxi.ffximain_rebased_va(static_va)
    static_va = tonumber(static_va) or 0;
    local base = get_ffximain_base();
    if (base == 0 or static_va < 0x10000000) then
        return 0;
    end
    return base + (static_va - 0x10000000);
end

function accessxi.ffximain_global_ptr(static_va)
    local addr = accessxi.ffximain_rebased_va(static_va);
    if (not accessxi.is_probe_pointer(addr)) then
        return 0;
    end

    local ptr = read_u32(addr) or 0;
    if (not accessxi.is_probe_pointer(ptr)) then
        return 0;
    end
    return ptr;
end

function accessxi.map_controller_ptr()
    return accessxi.ffximain_global_ptr(0x10630D68);
end

function accessxi.map_mode_label(mode)
    mode = tonumber(mode) or -1;
    if (mode == 0) then
        return 'Markers mode';
    elseif (mode == 1) then
        return 'Marker actions mode';
    elseif (mode == 2) then
        return 'Wide Scan mode';
    elseif (mode == 3) then
        return 'Scan mode';
    end
    return 'Markers mode';
end

function accessxi.map_selected_record_ptr(controller, selected, mode)
    controller = tonumber(controller) or 0;
    selected = tonumber(selected) or 0;
    mode = tonumber(mode) or 0;
    if (not accessxi.is_probe_pointer(controller) or selected < 1 or selected > 32) then
        return 0;
    end

    local index = selected - 1;
    local base = 0x6E8;
    if (mode == 1) then
        base = 0x7C4;
    elseif (mode == 2 or mode == 3) then
        index = index + (mode * 10);
    end
    return controller + base + (index * 0x16);
end

function accessxi.map_record_label_is_useful(label)
    label = accessxi.map_clean_native_label(label or '');
    if (label == '') then
        return false;
    end

    local lower = label:lower();
    if (#label < 3
        or lower == 'marker'
        or lower == 'markers'
        or lower == 'rker'
        or lower == 'ker'
        or lower == 'enu'
        or lower == 'men'
        or lower == 'menu'
        or lower:find('marker', 1, true) ~= nil
        or lower:find('menu', 1, true) ~= nil) then
        return false;
    end
    return true;
end

function accessxi.map_record_label(record)
    record = tonumber(record) or 0;
    if (not accessxi.is_probe_pointer(record)) then
        return '';
    end

    for _, off in ipairs(T{ 0x01, 0x02, 0x04, 0x06, 0x08 }) do
        local label = accessxi.map_clean_native_label(read_probe_string(record + off, 18));
        if (accessxi.map_record_label_is_useful(label)) then
            return label;
        end
    end
    return '';
end

function accessxi.map_marker_slot_label(selected, count, mode)
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    mode = tonumber(mode) or 0;
    if (selected <= 0 or (mode ~= 0 and mode ~= 1)) then
        return '';
    end
    if (count > 0 and count <= 32) then
        return ('Marker %d of %d'):fmt(selected, count);
    end
    return ('Marker %d'):fmt(selected);
end

function accessxi.map_current_area_surface_label(selected, count)
    local parts = T{};
    local zone_name = accessxi.map_current_zone_name();
    local controller = accessxi.map_controller_ptr();
    local mode = accessxi.is_probe_pointer(controller) and (read_u16(controller + 0x106) or 0) or 0;
    local record = accessxi.map_selected_record_ptr(controller, selected, mode);
    local record_label = accessxi.map_record_label(record);
    local window_name = accessxi.map_native_window_label();
    local slot_label = accessxi.map_marker_slot_label(selected, count, mode);

    parts:append(accessxi.map_mode_label(mode));
    if (record_label ~= '') then
        parts:append(record_label);
    elseif (window_name ~= '') then
        parts:append(window_name);
    elseif (slot_label ~= '') then
        parts:append(slot_label);
    end
    if (zone_name ~= '') then
        parts:append(zone_name);
    end

    return accessxi.map_clean_native_label(parts:concat('. ')), mode;
end

function accessxi.log_map_menu_probe(menu_name, title, obj, selected, count, page, raw, child, entry, label, mode)
    local key = ('%s:%d:%d:%08X:%08X:%08X:%08X:%s:%s'):fmt(
        tostring(menu_name or ''),
        tonumber(selected) or 0,
        tonumber(count) or 0,
        tonumber(obj) or 0,
        tonumber(child) or 0,
        tonumber(entry) or 0,
        tonumber(raw) or 0,
        tostring(label or ''),
        tostring(mode or ''));
    if (key == tostring(accessxi.last_map_menu_probe_key or '')) then
        return;
    end
    accessxi.last_map_menu_probe_key = key;

    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    local ank_num = target ~= nil and (tonumber(safe_call(function () return target:GetWindowAnkNum(); end, -1)) or -1) or -1;
    local ank_x = target ~= nil and (tonumber(safe_call(function () return target:GetWindowAnkX(); end, -1)) or -1) or -1;
    local ank_y = target ~= nil and (tonumber(safe_call(function () return target:GetWindowAnkY(); end, -1)) or -1) or -1;
    local win = target ~= nil and clean_probe_text(safe_call(function () return target:GetWindowName(); end, '')) or '';
    local controller = accessxi.map_controller_ptr();
    local map_mode = accessxi.is_probe_pointer(controller) and (read_u16(controller + 0x106) or 0) or -1;
    local map_kind = accessxi.is_probe_pointer(controller) and (read_u16(controller + 0x104) or 0) or -1;
    local map_zone = accessxi.is_probe_pointer(controller) and (read_u16(controller + 0x100) or 0) or -1;
    local record = accessxi.map_selected_record_ptr(controller, selected, map_mode);

    log_state(('state map-menu menu="%s" title="%s" select=%d count=%d page=%d raw=0x%08X obj=0x%08X child=0x%08X entry=0x%08X mode="%s" label="%s" win="%s" ankNum=%d ank=(%d,%d) ctrl=0x%08X mapMode=%d mapKind=%d mapZone=%d rec=0x%08X recBytes="%s" recRuns="%s" objDwords="%s" childDwords="%s" entryDwords="%s" entryRuns="%s" entryPtrs="%s"'):fmt(
        tostring(menu_name or ''),
        accessxi.escape_probe_log_text(title or ''),
        tonumber(selected) or 0,
        tonumber(count) or 0,
        tonumber(page) or 0,
        tonumber(raw) or 0,
        tonumber(obj) or 0,
        tonumber(child) or 0,
        tonumber(entry) or 0,
        accessxi.escape_probe_log_text(mode or ''),
        accessxi.escape_probe_log_text(label or ''),
        accessxi.escape_probe_log_text(win),
        ank_num,
        ank_x,
        ank_y,
        tonumber(controller) or 0,
        tonumber(map_mode) or -1,
        tonumber(map_kind) or -1,
        tonumber(map_zone) or -1,
        tonumber(record) or 0,
        accessxi.escape_probe_log_text_wide(accessxi.format_probe_bytes(record, 0, 0x16)),
        accessxi.escape_probe_log_text_wide(accessxi.status_menu_probe_runs(record, 0x40)),
        accessxi.escape_probe_log_text(accessxi.format_probe_dwords(obj, 0, 40)),
        accessxi.escape_probe_log_text(accessxi.format_probe_dwords(child, 0, 40)),
        accessxi.escape_probe_log_text(accessxi.format_probe_dwords(entry, 0, 48)),
        accessxi.escape_probe_log_text_wide(accessxi.status_menu_probe_runs(entry, 0x220)),
        accessxi.escape_probe_log_text_wide(accessxi.status_menu_probe_pointer_fields(entry))));
end

function accessxi.map_menu_speech(menu_name, title, obj, selected, count, page, raw, child, entry)
    menu_name = tostring(menu_name or '');
    title = tostring(title or 'Map');
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;

    local label = '';
    local mode = '';
    local help = '';

    if (menu_name:eq('menu    map0', true)) then
        local row = accessxi.map_menu_static_entry(selected);
        if (row ~= nil) then
            label = tostring(row.label or '');
            help = tostring(row.help or '');
            mode = 'dat-map0';
        end
    else
        label, mode = accessxi.map_menu_entry_text(entry, selected);
        if (label == '' and accessxi.is_probe_pointer(child) and selected > 0 and count > 0 and count <= 64) then
            local query_label, query_mode = accessxi.native_query_label_for_selection(child, selected, count, 'plain');
            query_label = accessxi.plain_native_menu_label(query_label or '');
            if (query_label ~= '') then
                label = query_label;
                mode = 'native-query:' .. tostring(query_mode or '');
            end
        end
        if (label == ''
            and (menu_name:eq('menu    mapv3', true) or menu_name:eq('menu    mapframe', true))) then
            local native_map_mode = 0;
            label, native_map_mode = accessxi.map_current_area_surface_label(selected, count);
            if (label ~= '') then
                mode = ('native-window:%d'):fmt(tonumber(native_map_mode) or 0);
            end
        end
    end

    accessxi.log_map_menu_probe(menu_name, title, obj, selected, count, page, raw, child, entry, label, mode);
    if (label == '') then
        return nil;
    end

    accessxi.last_native_menu_name = menu_name;
    accessxi.last_native_menu_label = label;
    accessxi.last_native_menu_selected = selected;
    accessxi.last_native_menu_tick = tick();
    accessxi.current_speech_key = ('map-menu:%s:%d:%d:%d:%s:%s'):fmt(
        menu_name,
        selected,
        tonumber(page) or 0,
        count,
        tostring(mode or ''),
        label);

    if (help ~= '') then
        return ('%s. %s %s'):fmt(title, accessxi.sentence_fragment(label), accessxi.sentence_fragment(help));
    end
    return ('%s. %s'):fmt(title, accessxi.sentence_fragment(label));
end

function accessxi.home_point_query_menu_speech(menu_name, title, obj)
    menu_name = tostring(menu_name or '');
    title = tostring(title or '');
    obj = tonumber(obj) or 0;
    if (title == '') then
        local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
        title = accessxi.survival_guide_text(target ~= nil and safe_call(function () return target:GetWindowName(); end, '') or '');
    end
    if (not menu_name:eq('menu    query', true) or obj == 0 or not title:contains('Home Point', true)) then
        return nil;
    end

    local selected, page, raw, child, count = accessxi.survival_guide_query_child_state_for_obj(obj);
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    if (selected <= 0) then
        selected = read_current_native_menu_index(0x4C);
    end
    if (count <= 0 or count > 64) then
        count = math.max(accessxi.native_menu_index(0x24), accessxi.native_menu_index(0x28));
    end

    local label, mode = accessxi.native_query_label_for_selection(child, selected, count, 'plain');
    label = accessxi.home_point_query_normalize_phrase(label or '');
    if (selected >= 2 and accessxi.home_point_label_is_destination_row(label)) then
        label = accessxi.home_point_destination_row_label(selected);
    elseif (label ~= '') then
        accessxi.home_point_remember_area_label(label);
    end
    local key = ('%s:%d:%d:%d:%08X:%s:%s'):fmt(
        menu_name,
        selected,
        count,
        tonumber(page) or 0,
        tonumber(child) or 0,
        tostring(mode or ''),
        label);
    if (key ~= tostring(accessxi.last_home_point_query_log_key or '')) then
        accessxi.last_home_point_query_log_key = key;
        log_state(('state homepoint query menu="%s" title="%s" select=%d count=%d page=%d raw=0x%08X child=0x%08X mode="%s" label="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title),
            selected,
            count,
            tonumber(page) or 0,
            tonumber(raw) or 0,
            tonumber(child) or 0,
            tostring(mode or ''),
            accessxi.escape_probe_log_text(label)));
    end
    if (label == '') then
        return nil;
    end

    accessxi.last_native_menu_name = menu_name;
    accessxi.last_native_menu_label = label;
    accessxi.last_native_menu_selected = selected;
    accessxi.last_native_menu_tick = tick();
    accessxi.current_speech_key = ('homepoint-query:%s:%d:%d:%d:%s'):fmt(
        menu_name,
        selected,
        tonumber(page) or 0,
        count,
        label);
    return ('%s. %s'):fmt(title, accessxi.sentence_fragment(label));
end

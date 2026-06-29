accessxi.festive_moogle_menu_data = accessxi.load_menu_module_table('festive_moogle', T{
    query_label_tail_patterns = T{},
    query_contains_labels = T{},
    query_exact_labels = T{},
});

function accessxi.festive_moogle_clean_query_label(label)
    label = accessxi.plain_native_menu_label(label or '');
    if (label == '') then
        return '';
    end

    for _, pattern in ipairs(accessxi.festive_moogle_menu_data.query_label_tail_patterns or T{}) do
        label = label:gsub(pattern, '');
    end
    label = label:gsub('%s+', ' '):trim();

    for _, row in ipairs(accessxi.festive_moogle_menu_data.query_contains_labels or T{}) do
        local contains = tostring(row ~= nil and row.contains or '');
        local clean = tostring(row ~= nil and row.label or '');
        if (contains ~= '' and clean ~= '' and label:contains(contains, true)) then
            return clean;
        end
    end

    for raw, clean in pairs(accessxi.festive_moogle_menu_data.query_exact_labels or {}) do
        if (label:eq(tostring(raw or ''), true)) then
            return tostring(clean or label);
        end
    end

    return label;
end

function accessxi.festive_moogle_query_menu_speech(menu_name, title, obj)
    menu_name = tostring(menu_name or '');
    title = tostring(title or '');
    obj = tonumber(obj) or 0;
    if (title == '') then
        local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
        title = accessxi.survival_guide_text(target ~= nil and safe_call(function () return target:GetWindowName(); end, '') or '');
    end
    if (not menu_name:eq('menu    query', true) or obj == 0 or not title:contains('Festive Moogle', true)) then
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
    label = accessxi.festive_moogle_clean_query_label(label or '');
    local key = ('%s:%s:%d:%d:%d:%08X:%s:%s'):fmt(
        menu_name,
        title,
        selected,
        count,
        tonumber(page) or 0,
        tonumber(child) or 0,
        tostring(mode or ''),
        label);
    if (key ~= tostring(accessxi.last_festive_moogle_query_log_key or '')) then
        accessxi.last_festive_moogle_query_log_key = key;
        log_state(('state festive-moogle query menu="%s" title="%s" select=%d count=%d page=%d raw=0x%08X child=0x%08X mode="%s" label="%s"'):fmt(
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
    accessxi.current_speech_key = ('festive-moogle-query:%s:%d:%d:%d:%s'):fmt(
        menu_name,
        selected,
        tonumber(page) or 0,
        count,
        label);
    return ('%s. %s'):fmt(title, accessxi.sentence_fragment(label));
end

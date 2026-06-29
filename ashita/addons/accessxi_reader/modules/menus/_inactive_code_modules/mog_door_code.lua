accessxi.mog_door_menu_data = accessxi.load_menu_module_table('mog_door', T{
    parent_choices = T{},
    area_return_choice = { label = 'Area you entered from.', dat = '' },
    area_families = T{},
});

function accessxi.mog_door_dat_choice_for_row(row)
    row = tonumber(row) or -1;
    local choices = accessxi.mog_door_menu_data.parent_choices or T{};
    if (row < 1 or row > choices:len()) then
        return nil;
    end

    local choice = choices[row];
    if (choice == nil) then
        return nil;
    end

    return {
        row = row,
        label = accessxi.plain_native_menu_label(choice.label),
        dat = choice.dat,
    };
end

function accessxi.mog_door_dat_choice_for_ank(ank_num)
    ank_num = tonumber(ank_num) or -1;
    if (ank_num < 0 or ank_num > 5) then
        return nil;
    end
    return accessxi.mog_door_dat_choice_for_row(math.floor(ank_num / 2) + 1);
end

function accessxi.mog_door_zone_name(zone)
    zone = tonumber(zone) or 0;
    if (zone <= 0) then
        return '';
    end

    return accessxi.plain_native_menu_label(safe_call(function () return AshitaCore:GetResourceManager():GetString('zones.names', zone); end, '') or '');
end

function accessxi.mog_door_area_choices_for_zone(zone)
    zone = tonumber(zone) or 0;
    local family = '';
    local rows = nil;

    for _, row in ipairs(accessxi.mog_door_menu_data.area_families or T{}) do
        if (accessxi.menu_name_in_list(tostring(zone), row.zones or T{})) then
            family = tostring(row.family or '');
            rows = row.zones;
            break;
        end
    end

    if (rows == nil) then
        return nil, '';
    end

    local return_choice = accessxi.mog_door_menu_data.area_return_choice or { label = 'Area you entered from.', dat = '' };
    local choices = T{ return_choice };
    for _, dat_row in ipairs(rows) do
        local label = accessxi.mog_door_zone_name(dat_row);
        if (label ~= '') then
            choices:append({
                label = label,
                dat = ('ROM\\97\\53.DAT:%d; ROM\\165\\84.DAT:%d'):fmt(dat_row, dat_row),
            });
        end
    end

    return choices, family;
end

function accessxi.mog_door_area_choice_for_row(row, zone)
    row = tonumber(row) or -1;
    local choices, family = accessxi.mog_door_area_choices_for_zone(zone);
    if (choices == nil or row < 1 or row > #choices) then
        return nil;
    end

    local choice = choices[row];
    if (choice == nil) then
        return nil;
    end

    return {
        row = row,
        label = accessxi.plain_native_menu_label(choice.label),
        dat = choice.dat,
        family = family,
    };
end

function accessxi.mog_door_native_state(ank_num)
    local base = get_ffximain_base();
    if (base == 0) then
        return { valid = false, reason = 'no-base' };
    end

    local obj = read_u32(base + 0x6306BC) or 0;
    if (not accessxi.is_probe_pointer(obj)) then
        return { valid = false, reason = 'no-object', obj = obj };
    end

    local vtable = read_u32(obj) or 0;
    local expected_vtable = base + 0x338460;
    if (vtable ~= expected_vtable) then
        return {
            valid = false,
            reason = 'bad-vtable',
            obj = obj,
            vtable = vtable,
            expected_vtable = expected_vtable,
        };
    end

    local control = read_u32(obj + 0x08) or 0;
    local mode = read_u8(obj + 0x18) or 0;
    local count = read_u8(obj + 0x16) or 0;
    local selected_action = read_u8(obj + 0x15) or 0;
    local area_table = read_u32(obj + 0x1C) or 0;
    local cursor4c = accessxi.is_probe_pointer(control) and (read_i32(control + 0x4C) or 0) or 0;
    local cursor5e = accessxi.is_probe_pointer(control) and (read_u16(control + 0x5E) or 0) or 0;
    local row = tonumber(cursor4c) or 0;
    local ank = tonumber(ank_num) or -1;

    if (mode ~= 0 and count > 0) then
        if (row < 1 or row > count) then
            local zero_based = tonumber(cursor5e) or -1;
            if (zero_based >= 0 and zero_based < count) then
                row = zero_based + 1;
            end
        end
        if ((row < 1 or row > count) and ank >= 1 and ank <= count) then
            row = ank;
        end
        if ((row < 1 or row > count) and ank >= 0 and (ank + 1) <= count) then
            row = ank + 1;
        end
    end

    return {
        valid = true,
        obj = obj,
        vtable = vtable,
        control = control,
        mode = mode,
        count = count,
        selected_action = selected_action,
        area_table = area_table,
        cursor4c = tonumber(cursor4c) or 0,
        cursor5e = tonumber(cursor5e) or 0,
        row = tonumber(row) or 0,
    };
end

function accessxi.mog_door_native_area_choice_for_row(row, state)
    row = tonumber(row) or 0;
    state = state or accessxi.mog_door_native_state();
    if (not state.valid or (tonumber(state.mode) or 0) == 0) then
        return nil;
    end

    local count = tonumber(state.count) or 0;
    local table_ptr = tonumber(state.area_table) or 0;
    if (row < 1 or row > count or not accessxi.is_probe_pointer(table_ptr)) then
        return nil;
    end

    local code = read_u16(table_ptr + ((row - 1) * 2)) or 0;
    local label = '';
    local dat = ('mogdoor+0x1C[%d]=0x%04X'):fmt(row, code);
    if (code == 0x0118) then
        label = 'Area you entered from.';
        dat = dat .. '; ROM\\97\\37.DAT:70; ROM\\165\\72.DAT:70';
    elseif (code > 0) then
        label = accessxi.mog_door_zone_name(code);
        dat = dat .. ('; zones.names:%d'):fmt(code);
    end

    label = accessxi.plain_native_menu_label(label);
    if (label == '') then
        return nil;
    end

    return {
        row = row,
        code = code,
        label = label,
        dat = dat,
        family = 'native',
    };
end

function accessxi.mog_door_clear_area_state(reason)
    reason = tostring(reason or '');
    accessxi.mog_door_area_list_until = 0;
    accessxi.mog_door_area_list_obj = 0;
    accessxi.mog_door_area_list_child = 0;
    accessxi.mog_door_area_list_sub = -1;
    accessxi.mog_door_area_list_sub_x = -1;
    accessxi.mog_door_area_list_sub_y = -1;
    accessxi.mog_door_area_list_proof_tick = 0;
    accessxi.mog_door_area_escape_hold = reason:eq('escape', true) and 1 or 0;
    accessxi.mog_door_area_hold_reason = reason;
    accessxi.mog_door_area_pending_until = 0;
    accessxi.mog_door_blank_area_active_until = 0;
    accessxi.mog_door_blank_area_last_row = 0;
    accessxi.mog_door_area_ank_mode_until = 0;
    accessxi.mog_door_area_ank_mode_row = 0;
    accessxi.last_mog_door_area_arm_key = '';
    if (reason:eq('escape', true)) then
        accessxi.mog_door_need_parent_row4 = 1;
    end
    log_state(('state mogdoor area-clear reason="%s"'):fmt(accessxi.escape_probe_log_text(reason)));
end

function accessxi.mog_door_arm_area_state(reason, obj, child, sub, sub_x, sub_y, duration)
    local now = tick();
    accessxi.mog_door_area_list_until = now + (tonumber(duration) or 3000);
    accessxi.mog_door_area_list_obj = tonumber(obj) or 0;
    accessxi.mog_door_area_list_child = tonumber(child) or 0;
    accessxi.mog_door_area_list_sub = tonumber(sub) or -1;
    accessxi.mog_door_area_list_sub_x = tonumber(sub_x) or -1;
    accessxi.mog_door_area_list_sub_y = tonumber(sub_y) or -1;
    accessxi.mog_door_area_list_proof_tick = now;
    accessxi.mog_door_area_escape_hold = 0;
    accessxi.mog_door_area_hold_reason = '';
    accessxi.mog_door_area_pending_until = 0;

    local key = ('%s:%08X:%08X:%d:%d:%d'):fmt(
        tostring(reason or ''),
        tonumber(obj) or 0,
        tonumber(child) or 0,
        tonumber(sub) or -1,
        tonumber(sub_x) or -1,
        tonumber(sub_y) or -1);
    if (key ~= tostring(accessxi.last_mog_door_area_arm_key or '')) then
        accessxi.last_mog_door_area_arm_key = key;
        log_state(('state mogdoor area-arm reason="%s" obj=0x%08X child=0x%08X sub=%d subXY=(%d,%d) until=%d'):fmt(
            accessxi.escape_probe_log_text(reason or ''),
            tonumber(obj) or 0,
            tonumber(child) or 0,
            tonumber(sub) or -1,
            tonumber(sub_x) or -1,
            tonumber(sub_y) or -1,
            tonumber(accessxi.mog_door_area_list_until) or 0));
    end
end

function accessxi.mog_door_remember_cursor(native_cursor, mode)
    accessxi.mog_door_last_cursor4c = tonumber(native_cursor) or 0;
    accessxi.mog_door_last_cursor_mode = tostring(mode or '');
    accessxi.mog_door_last_cursor_tick = tick();
end

function accessxi.mog_door_target_window_raw_signature(target)
    if (target == nil) then
        return '';
    end

    local raw = safe_call(function () return target:GetRawStructureWindow(); end, nil);
    if (raw == nil) then
        return '';
    end

    local function field(name, default)
        return safe_call(function () return raw[name]; end, default);
    end

    local function num_field(name)
        return tonumber(field(name, 0)) or 0;
    end

    local function ptr_field(name)
        return tonumber(safe_call(function ()
            return ffi.cast('uintptr_t', field(name, nil));
        end, 0)) or 0;
    end

    local raw_name = safe_call(function ()
        local value = raw.Name;
        if (type(value) == 'string') then
            return value;
        end
        return ffi.string(value);
    end, '');

    return ('vt=0x%08X base=0x%08X parent=0x%08X input=%d unk0D=%d save=%d repo=%d rawName="%s" server=%d loaded=%d help=0x%08X helpTitle=0x%08X sub=%d ank=%d ankXY=(%d,%d) subXY=(%d,%d)'):fmt(
        ptr_field('VTablePointer'),
        ptr_field('m_BaseObj'),
        ptr_field('m_pParentMCD'),
        num_field('m_InputEnable'),
        num_field('unknown000D'),
        num_field('m_SaveCursol'),
        num_field('m_Reposition'),
        accessxi.escape_probe_log_text(clean_probe_text(raw_name)),
        num_field('ServerId'),
        num_field('IsWindowLoaded'),
        num_field('HelpString'),
        num_field('HelpTitle'),
        num_field('m_Sub'),
        num_field('m_AnkNum'),
        num_field('m_AnkX'),
        num_field('m_AnkY'),
        num_field('m_SubAnkX'),
        num_field('m_SubAnkY'));
end

function accessxi.mog_door_target_window_parent_ptr(target)
    if (target == nil) then
        return 0;
    end

    local raw = safe_call(function () return target:GetRawStructureWindow(); end, nil);
    if (raw == nil) then
        return 0;
    end

    return tonumber(safe_call(function ()
        return ffi.cast('uintptr_t', raw.m_pParentMCD);
    end, 0)) or 0;
end

function accessxi.mog_door_blank_parent_scan(parent)
    parent = tonumber(parent) or 0;
    if (not accessxi.is_probe_pointer(parent)) then
        return '';
    end

    local texts = T{};
    for off = 0, 0x1C0, 4 do
        local ptr = read_u32(parent + off) or 0;
        if (accessxi.is_probe_pointer(ptr)) then
            local found = accessxi.probe_strings_at(ptr);
            if (found ~= '') then
                texts:append(('+%03X=0x%08X{%s}'):fmt(off, ptr, accessxi.escape_probe_log_text_wide(found)));
                if (#texts >= 12) then
                    break;
                end
            end
        end
    end

    return ('parent=0x%08X texts="%s" d00="%s" d40="%s" d80="%s" dC0="%s"'):fmt(
        parent,
        texts:concat(' | '),
        accessxi.format_probe_dwords(parent, 0x00, 16),
        accessxi.format_probe_dwords(parent, 0x40, 16),
        accessxi.format_probe_dwords(parent, 0x80, 16),
        accessxi.format_probe_dwords(parent, 0xC0, 16));
end

function accessxi.log_mog_door_blank_signal_probe(reason, target, obj, ank, ank_x, ank_y, sub, sub_x, sub_y, loaded, server_id, current_zone, area_count, window_name, target_name)
    if ((tonumber(accessxi.mog_door_probe_until) or 0) <= tick()) then
        return;
    end

    local parent = accessxi.mog_door_target_window_parent_ptr(target);
    local raw = accessxi.mog_door_target_window_raw_signature(target);
    local shapes = T{};
    if (target ~= nil) then
        for i = 0, 15 do
            local shape = tonumber(safe_call(function () return target:GetWindowAnkShape(i); end, 0)) or 0;
            if (shape ~= 0) then
                shapes:append(('%d=0x%08X'):fmt(i, shape));
            end
        end
    end

    local parent_summary = '';
    if (accessxi.is_probe_pointer(parent)) then
        parent_summary = ('d00=%s d40=%s d80=%s dC0=%s d100=%s'):fmt(
            accessxi.format_probe_dwords(parent, 0x00, 16),
            accessxi.format_probe_dwords(parent, 0x40, 16),
            accessxi.format_probe_dwords(parent, 0x80, 16),
            accessxi.format_probe_dwords(parent, 0xC0, 16),
            accessxi.format_probe_dwords(parent, 0x100, 16));
    end

    local key = ('%s:%08X:%08X:%d:%d:%d:%d:%d:%d:%d:%d:%d:%s:%s'):fmt(
        tostring(reason or ''),
        tonumber(obj) or 0,
        tonumber(parent) or 0,
        tonumber(ank) or -1,
        tonumber(ank_x) or -1,
        tonumber(ank_y) or -1,
        tonumber(sub) or -1,
        tonumber(sub_x) or -1,
        tonumber(sub_y) or -1,
        tonumber(loaded) or 0,
        tonumber(server_id) or 0,
        tonumber(current_zone) or 0,
        tostring(shapes:concat(',')),
        parent_summary);
    if (key == tostring(accessxi.last_mog_door_blank_signal_key or '')) then
        return;
    end
    accessxi.last_mog_door_blank_signal_key = key;

    log_state(('state mogdoor blank-signal reason="%s" zone=%d areaCount=%d menuObj=0x%08X parent=0x%08X ank=%d ankXY=(%d,%d) sub=%d subXY=(%d,%d) loaded=%d server=%d window="%s" target="%s" raw="%s" shapes="%s" parent="%s"'):fmt(
        accessxi.escape_probe_log_text(reason or ''),
        tonumber(current_zone) or 0,
        tonumber(area_count) or 0,
        tonumber(obj) or 0,
        tonumber(parent) or 0,
        tonumber(ank) or -1,
        tonumber(ank_x) or -1,
        tonumber(ank_y) or -1,
        tonumber(sub) or -1,
        tonumber(sub_x) or -1,
        tonumber(sub_y) or -1,
        tonumber(loaded) or 0,
        tonumber(server_id) or 0,
        accessxi.escape_probe_log_text(window_name or ''),
        accessxi.escape_probe_log_text(target_name or ''),
        accessxi.escape_probe_log_text(raw),
        accessxi.escape_probe_log_text(shapes:concat(',')),
        accessxi.escape_probe_log_text(parent_summary)));
end

function accessxi.mog_door_pointer_text_scan(base, max_offset, max_found)
    base = tonumber(base) or 0;
    max_offset = tonumber(max_offset) or 0x140;
    max_found = tonumber(max_found) or 10;
    if (not accessxi.is_probe_pointer(base)) then
        return '';
    end

    local texts = T{};
    for off = 0, max_offset, 4 do
        local ptr = read_u32(base + off) or 0;
        if (accessxi.is_probe_pointer(ptr)) then
            local found = accessxi.probe_strings_at(ptr);
            if (found ~= '') then
                texts:append(('+%03X=0x%08X{%s}'):fmt(off, ptr, accessxi.escape_probe_log_text_wide(found)));
                if (#texts >= max_found) then
                    break;
                end
            end
        end
    end
    return texts:concat(' | ');
end

function accessxi.log_mog_door_parent_text_probe(parent, reason)
    parent = tonumber(parent) or 0;
    if (not accessxi.is_probe_pointer(parent)) then
        return;
    end

    local texts = accessxi.mog_door_pointer_text_scan(parent, 0x1C0, 16);
    local key = ('%s:0x%08X:%s'):fmt(tostring(reason or ''), parent, texts);
    if (key == tostring(accessxi.last_mog_door_parent_text_probe_key or '')) then
        return;
    end
    accessxi.last_mog_door_parent_text_probe_key = key;

    log_state(('state mogdoor parent-text reason="%s" parent=0x%08X texts="%s"'):fmt(
        accessxi.escape_probe_log_text(reason or ''),
        parent,
        accessxi.escape_probe_log_text_wide(texts)));
    log_state(('state mogdoor parent-dwords reason="%s" parent=0x%08X d00="%s" d40="%s" d80="%s" dC0="%s" d100="%s" d140="%s"'):fmt(
        accessxi.escape_probe_log_text(reason or ''),
        parent,
        accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(parent, 0x00, 16)),
        accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(parent, 0x40, 16)),
        accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(parent, 0x80, 16)),
        accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(parent, 0xC0, 16)),
        accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(parent, 0x100, 16)),
        accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(parent, 0x140, 16))));
end

function accessxi.log_mog_door_row_text_probe(menu_name, title, obj, child, entry, selected, count, display_selected, display_count, native_cursor, mode, reason)
    if ((tonumber(accessxi.mog_door_signal_probe_until) or 0) <= tick()) then
        return;
    end

    obj = tonumber(obj) or 0;
    child = tonumber(child) or 0;
    entry = tonumber(entry) or 0;
    selected = tonumber(selected) or 0;
    count = tonumber(count) or 0;
    display_selected = tonumber(display_selected) or 0;
    display_count = tonumber(display_count) or 0;
    native_cursor = tonumber(native_cursor) or 0;

    local label_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x44) or 0) or 0;
    local help_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x40) or 0) or 0;
    local desc04 = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x04) or 0) or 0;
    local desc0c = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x0C) or 0) or 0;
    local desc24 = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x24) or 0) or 0;
    local label = accessxi.plain_native_menu_label(read_probe_string(label_ptr, 160));
    local help = accessxi.plain_native_menu_help(read_probe_string(help_ptr, 260));
    local d04 = accessxi.is_probe_pointer(desc04) and clean_probe_text(read_probe_string(desc04 + 0x46, 180)) or '';
    local d0c = accessxi.is_probe_pointer(desc0c) and clean_probe_text(read_probe_string(desc0c + 0x46, 180)) or '';
    local d24 = accessxi.is_probe_pointer(desc24) and clean_probe_text(read_probe_string(desc24 + 0x46, 180)) or '';
    local q_display, q_display_mode = accessxi.native_query_label_for_selection(child, display_selected, display_count, 'plain');
    local q_native, q_native_mode = accessxi.native_query_label_for_selection(child, native_cursor, count, 'plain');
    q_display = accessxi.plain_native_menu_label(q_display or '');
    q_native = accessxi.plain_native_menu_label(q_native or '');

    local entry_texts = accessxi.mog_door_pointer_text_scan(entry, 0x180, 12);
    local child_texts = accessxi.mog_door_pointer_text_scan(child, 0x180, 12);
    local key = ('0x%08X:0x%08X:0x%08X:%d:%d:%d:%d:%s:%s:%s:%s:%s:%s:%s:%s'):fmt(
        obj,
        child,
        entry,
        selected,
        count,
        display_selected,
        display_count,
        tostring(mode or ''),
        tostring(reason or ''),
        label,
        help,
        d04,
        d0c,
        q_display,
        q_native);
    if (key == tostring(accessxi.last_mog_door_row_text_probe_key or '')) then
        return;
    end
    accessxi.last_mog_door_row_text_probe_key = key;

    log_state(('state mogdoor row-text menu="%s" title="%s" mode="%s" reason="%s" selected=%d count=%d display=%d/%d cursor4C=%d obj58=%d obj=0x%08X child=0x%08X entry=0x%08X labelPtr=0x%08X helpPtr=0x%08X desc04=0x%08X desc0C=0x%08X desc24=0x%08X label="%s" help="%s" desc04Text="%s" desc0CText="%s" desc24Text="%s" queryDisplay="%s" queryDisplayMode="%s" queryNative="%s" queryNativeMode="%s"'):fmt(
        accessxi.escape_probe_log_text(menu_name or ''),
        accessxi.escape_probe_log_text(title or ''),
        accessxi.escape_probe_log_text(mode or ''),
        accessxi.escape_probe_log_text(reason or ''),
        selected,
        count,
        display_selected,
        display_count,
        native_cursor,
        read_current_native_menu_index(0x58),
        obj,
        child,
        entry,
        label_ptr,
        help_ptr,
        desc04,
        desc0c,
        desc24,
        accessxi.escape_probe_log_text(label),
        accessxi.escape_probe_log_text(help),
        accessxi.escape_probe_log_text(d04),
        accessxi.escape_probe_log_text(d0c),
        accessxi.escape_probe_log_text(d24),
        accessxi.escape_probe_log_text(q_display),
        accessxi.escape_probe_log_text(q_display_mode or ''),
        accessxi.escape_probe_log_text(q_native),
        accessxi.escape_probe_log_text(q_native_mode or '')));
    log_state(('state mogdoor row-text-ptrs obj=0x%08X child=0x%08X entry=0x%08X entryTexts="%s" childTexts="%s" entryD40="%s" entryD80="%s" childD00="%s" childD40="%s"'):fmt(
        obj,
        child,
        entry,
        accessxi.escape_probe_log_text_wide(entry_texts),
        accessxi.escape_probe_log_text_wide(child_texts),
        accessxi.is_probe_pointer(entry) and accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(entry, 0x40, 16)) or '',
        accessxi.is_probe_pointer(entry) and accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(entry, 0x80, 16)) or '',
        accessxi.is_probe_pointer(child) and accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(child, 0x00, 16)) or '',
        accessxi.is_probe_pointer(child) and accessxi.escape_probe_log_text_wide(accessxi.format_probe_dwords(child, 0x40, 16)) or ''));
end

function accessxi.mog_door_blank_menu_probe(reason)
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    if (target == nil) then
        return false;
    end

    local now = tick();
    local window_name = accessxi.plain_native_menu_label(safe_call(function () return target:GetWindowName(); end, '') or '');
    local target_name = tostring(accessxi.last_target_name or '');
    local myroom_callback = tonumber(safe_call(function () return target:GetMyroomCallback(); end, 0) or 0) or 0;
    local is_door_context = window_name:eq('Door: Back to Town', true)
        or target_name:eq('Door: Back to Town', true)
        or target_name:eq('Door. Back to Town', true);
    if (not is_door_context) then
        accessxi.mog_door_blank_area_active_until = 0;
        accessxi.mog_door_blank_area_last_row = 0;
        accessxi.mog_door_area_ank_mode_until = 0;
        accessxi.mog_door_area_ank_mode_row = 0;
        return false;
    end

    local probe_active = ((tonumber(accessxi.mog_door_signal_probe_until) or 0) > now);
    local skip_diag = false;
    if (not probe_active) then
        if ((tonumber(accessxi.last_mog_door_blank_probe_tick) or 0) + 1000 > now) then
            skip_diag = true;
        else
            accessxi.last_mog_door_blank_probe_tick = now;
        end
    end

    local ank = tonumber(safe_call(function () return target:GetWindowAnkNum(); end, -1) or -1) or -1;
    local ank_x = tonumber(safe_call(function () return target:GetWindowAnkX(); end, -1) or -1) or -1;
    local ank_y = tonumber(safe_call(function () return target:GetWindowAnkY(); end, -1) or -1) or -1;
    local sub = tonumber(safe_call(function () return target:GetWindowSub(); end, -1) or -1) or -1;
    local sub_x = tonumber(safe_call(function () return target:GetWindowSubAnkX(); end, -1) or -1) or -1;
    local sub_y = tonumber(safe_call(function () return target:GetWindowSubAnkY(); end, -1) or -1) or -1;
    local loaded = tonumber(safe_call(function () return target:GetWindowIsWindowLoaded(); end, 0) or 0) or 0;
    local server_id = tonumber(safe_call(function () return target:GetWindowServerId(); end, 0) or 0) or 0;
    local obj = get_current_menu_object_ptr();
    local current_zone = accessxi.current_zone_id();
    local area_choices, area_family = accessxi.mog_door_area_choices_for_zone(current_zone);
    local area_count = (area_choices ~= nil) and #area_choices or 0;
    local last_cursor = tonumber(accessxi.mog_door_last_cursor4c) or 0;
    local last_cursor_mode = tostring(accessxi.mog_door_last_cursor_mode or '');
    local last_cursor_tick = tonumber(accessxi.mog_door_last_cursor_tick) or 0;
    accessxi.log_mog_door_blank_signal_probe(reason, target, obj, ank, ank_x, ank_y, sub, sub_x, sub_y, loaded, server_id, current_zone, area_count, window_name, target_name);

    local native_state = accessxi.mog_door_native_state(ank);
    if (native_state.valid) then
        local native_mode = tonumber(native_state.mode) or 0;
        if (native_mode ~= 0) then
            local native_row = tonumber(native_state.row) or 0;
            local native_count = tonumber(native_state.count) or 0;
            if (native_row >= 1 and native_count > 0 and native_row <= native_count) then
                local area_choice = accessxi.mog_door_native_area_choice_for_row(native_row, native_state);
                if (area_choice ~= nil and tostring(area_choice.label or '') ~= '') then
                    local area_label = tostring(area_choice.label or '');
                    local speech_key = ('mogdoor-native-blank-area:%d:%s'):fmt(native_row, area_label);
                    if (speech_key ~= tostring(accessxi.current_speech_key or '')) then
                        log_state(('state mogdoor native-blank-area reason="%s" obj=0x%08X ctl=0x%08X mode=%d row=%d count=%d table=0x%08X code=0x%04X dat="%s" label="%s"'):fmt(
                            accessxi.escape_probe_log_text(reason or ''),
                            tonumber(native_state.obj) or 0,
                            tonumber(native_state.control) or 0,
                            native_mode,
                            native_row,
                            native_count,
                            tonumber(native_state.area_table) or 0,
                            tonumber(area_choice.code) or 0,
                            accessxi.escape_probe_log_text(area_choice.dat or ''),
                            accessxi.escape_probe_log_text(area_label)));
                    end
                    accessxi.current_speech_key = speech_key;
                    accessxi.mog_door_area_list_obj = tonumber(native_state.obj) or 0;
                    accessxi.mog_door_area_list_child = tonumber(native_state.control) or 0;
                    accessxi.mog_door_area_list_until = now + 3000;
                    accessxi.mog_door_area_pending_until = 0;
                    accessxi.mog_door_area_escape_hold = 0;
                    accessxi.mog_door_area_hold_reason = '';
                    accessxi.mog_door_remember_cursor(native_row, 'area-list');
                    return ('Door. %s'):fmt(accessxi.sentence_fragment(area_label));
                end
            end
        else
            local had_area_state = ((tonumber(accessxi.mog_door_area_pending_until) or 0) > now)
                or ((tonumber(accessxi.mog_door_blank_area_active_until) or 0) > now)
                or ((tonumber(accessxi.mog_door_area_ank_mode_until) or 0) > now);
            if (had_area_state) then
                accessxi.mog_door_clear_area_state('native-blank-parent-state');
            end
        end
    end

    if (obj == 0) then
        local had_area_state = ((tonumber(accessxi.mog_door_area_pending_until) or 0) > now)
            or ((tonumber(accessxi.mog_door_blank_area_active_until) or 0) > now)
            or ((tonumber(accessxi.mog_door_area_ank_mode_until) or 0) > now);
        if (had_area_state) then
            accessxi.mog_door_clear_area_state('blank-no-object');
        end
    end

    if (skip_diag) then
        return true;
    end

    local shape_parts = T{};
    if (probe_active) then
        for i = 0, 6 do
            local shape = tonumber(safe_call(function () return target:GetWindowAnkShape(i); end, 0)) or 0;
            if (shape ~= 0) then
                shape_parts:append(('%d=0x%08X:%s'):fmt(
                    i,
                    shape,
                    accessxi.escape_probe_log_text_wide(accessxi.status_menu_probe_runs(shape, 0x100))));
            end
        end
    end

    local raw_sig = probe_active and accessxi.mog_door_target_window_raw_signature(target) or '';
    local parent_ptr = probe_active and accessxi.mog_door_target_window_parent_ptr(target) or 0;
    local parent_scan = probe_active and accessxi.mog_door_blank_parent_scan(parent_ptr) or '';
    if (probe_active) then
        accessxi.log_mog_door_parent_text_probe(parent_ptr, tostring(reason or 'blank-window'));
    end
    local key = ('%s:%s:%s:%08X:%d:%d:%d:%d:%d:%d:%d:%d:%s:%s'):fmt(
        tostring(reason or ''),
        window_name,
        target_name,
        obj,
        myroom_callback,
        loaded,
        server_id,
        ank,
        ank_x,
        ank_y,
        sub,
        sub_x,
        sub_y,
        raw_sig,
        parent_scan);
    if (key == tostring(accessxi.last_mog_door_blank_probe_key or '')) then
        return true;
    end
    accessxi.last_mog_door_blank_probe_key = key;

    log_state(('state mogdoor blank-window reason="%s" menu="" target="%s" window="%s" obj=0x%08X myroomCb=0x%08X loaded=%d server=%d ank=%d ankXY=(%d,%d) sub=%d subXY=(%d,%d) raw="%s" parentScan="%s" shapes="%s"'):fmt(
        accessxi.escape_probe_log_text(reason or ''),
        accessxi.escape_probe_log_text(target_name),
        accessxi.escape_probe_log_text(window_name),
        obj,
        myroom_callback,
        loaded,
        server_id,
        ank,
        ank_x,
        ank_y,
        sub,
        sub_x,
        sub_y,
        accessxi.escape_probe_log_text(raw_sig),
        accessxi.escape_probe_log_text_wide(parent_scan),
        accessxi.escape_probe_log_text_wide(shape_parts:concat(' | '))));
    return true;
end

function accessxi.mog_door_packet_summary(id, data)
    id = tonumber(id) or 0;
    data = data or '';
    if (id == 0x032) then
        return ('npc=0x%08X npcIndex=%d zone=%d menuId=%d unk1=%d dupeZone=%d'):fmt(
            accessxi.packet_u32(data, 5),
            accessxi.packet_u16(data, 9),
            accessxi.packet_u16(data, 11),
            accessxi.packet_u16(data, 13),
            accessxi.packet_u16(data, 15),
            accessxi.packet_byte(data, 17));
    elseif (id == 0x034) then
        return ('npc=0x%08X npcIndex=%d zone=%d menuId=%d unk1=%d dupeZone=%d params="%s"'):fmt(
            accessxi.packet_u32(data, 5),
            accessxi.packet_u16(data, 41),
            accessxi.packet_u16(data, 43),
            accessxi.packet_u16(data, 45),
            accessxi.packet_u16(data, 47),
            accessxi.packet_u16(data, 49),
            accessxi.packet_hex_limit(data:sub(9, 40), 32));
    elseif (id == 0x05B) then
        return ('target=0x%08X option=%d unk1=%d targetIndex=%d auto=%d unk2=%d zone=%d menuId=%d'):fmt(
            accessxi.packet_u32(data, 5),
            accessxi.packet_u16(data, 9),
            accessxi.packet_u16(data, 11),
            accessxi.packet_u16(data, 13),
            accessxi.packet_byte(data, 15),
            accessxi.packet_byte(data, 16),
            accessxi.packet_u16(data, 17),
            accessxi.packet_u16(data, 19));
    elseif (id == 0x067) then
        return ('spawnX=%.3f spawnZ=%.3f spawnY=%.3f entityId=0x%08X index=%d type=%d unk1=%d'):fmt(
            accessxi.packet_i32(data, 5) / 1000,
            accessxi.packet_i32(data, 9) / 1000,
            accessxi.packet_i32(data, 13) / 1000,
            accessxi.packet_u32(data, 17),
            accessxi.packet_u16(data, 21),
            accessxi.packet_byte(data, 23),
            accessxi.packet_byte(data, 24));
    elseif (id == 0x00D) then
        return ('seq=0x%04X v04=0x%08X v08=0x%04X v0A=0x%04X v0C=0x%04X v20=0x%04X v22=0x%04X nonzero="%s"'):fmt(
            accessxi.packet_u16(data, 3),
            accessxi.packet_u32(data, 5),
            accessxi.packet_u16(data, 9),
            accessxi.packet_u16(data, 11),
            accessxi.packet_u16(data, 13),
            accessxi.packet_u16(data, 33),
            accessxi.packet_u16(data, 35),
            accessxi.packet_nonzero_words(data, 1, 80));
    elseif (id == 0x015) then
        return ('seq=0x%04X posX=0x%08X posY=0x%08X mode=0x%04X arg=0x%04X tick=0x%08X nonzero="%s"'):fmt(
            accessxi.packet_u16(data, 3),
            accessxi.packet_u32(data, 5),
            accessxi.packet_u32(data, 13),
            accessxi.packet_u16(data, 19),
            accessxi.packet_u16(data, 21),
            accessxi.packet_u32(data, 25),
            accessxi.packet_nonzero_words(data, 1, 40));
    end
    return '';
end

function accessxi.trace_mog_door_packet(e, direction)
    local now = tick();
    local id = tonumber(e.id) or 0;
    local menu_name = tostring(get_menu_name() or '');
    if ((tonumber(accessxi.mog_door_packet_trace_until) or 0) <= now) then
        return;
    end

    local trace_count = tonumber(accessxi.mog_door_packet_trace_count) or 0;
    local trace_limit = tonumber(accessxi.mog_door_packet_trace_limit) or 160;
    if (trace_count >= trace_limit) then
        return;
    end

    local data = e.data_modified or e.data or accessxi.packet_event_string(e, 'data_modified', 'size') or accessxi.packet_event_string(e, 'data', 'size') or '';
    local target_name = tostring(accessxi.last_target_name or '');
    local window_name = '';
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    if (target ~= nil) then
        window_name = accessxi.plain_native_menu_label(safe_call(function () return target:GetWindowName(); end, '') or '');
    end
    local myroom_callback = tonumber(target ~= nil and safe_call(function () return target:GetMyroomCallback(); end, 0) or 0) or 0;

    local is_mog_door = menu_name:eq('menu    mogdoor', true)
        or target_name:eq('Door: Back to Town', true)
        or target_name:eq('Door. Back to Town', true)
        or window_name:eq('Door: Back to Town', true);
    if (not is_mog_door) then
        return;
    end

    local preview_limit = 96;
    local hex_limit = 160;
    if (id == 0x015) then
        preview_limit = 40;
        hex_limit = 40;
    elseif (id == 0x00D) then
        preview_limit = 80;
        hex_limit = 80;
    end

    accessxi.mog_door_packet_trace_count = trace_count + 1;
    log_line(('mogdoor packet trace dir=%s n=%d id=0x%03X len=%d menu="%s" target="%s" window="%s" myroomCb=0x%08X cursor4C=%d obj24=%d obj28=%d obj50=%d obj58=%d obj64=%d active=%s fields="%s" ascii="%s" hex="%s"'):fmt(
        tostring(direction or ''),
        trace_count + 1,
        id,
        #(data or ''),
        accessxi.escape_probe_log_text(menu_name),
        accessxi.escape_probe_log_text(target_name),
        accessxi.escape_probe_log_text(window_name),
        myroom_callback,
        read_current_native_menu_index(0x4C),
        read_current_native_menu_index(0x24),
        read_current_native_menu_index(0x28),
        read_current_native_menu_index(0x50),
        read_current_native_menu_index(0x58),
        read_current_native_menu_index(0x64),
        tostring(menu_name:eq('menu    mogdoor', true) or target_name:eq('Door: Back to Town', true) or window_name:eq('Door: Back to Town', true)),
        accessxi.escape_probe_log_text(accessxi.mog_door_packet_summary(id, data)),
        accessxi.escape_probe_log_text(accessxi.packet_ascii_preview(data, preview_limit)),
        accessxi.packet_hex_limit(data, hex_limit)));
end

function accessxi.capture_mog_door_outgoing_packet(e)
    local id = tonumber(e ~= nil and e.id or 0) or 0;
    if (id ~= 0x005B and id ~= 0x015) then
        return;
    end

    local menu_name = tostring(get_menu_name() or '');
    local target_name = tostring(accessxi.last_target_name or '');
    local window_name = '';
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    if (target ~= nil) then
        window_name = accessxi.plain_native_menu_label(safe_call(function () return target:GetWindowName(); end, '') or '');
    end

    local is_mog_door = menu_name:eq('menu    mogdoor', true)
        or window_name:eq('Door: Back to Town', true)
        or target_name:eq('Door: Back to Town', true)
        or target_name:eq('Door. Back to Town', true);
    if (not is_mog_door) then
        return;
    end

    local data = e.data_modified or e.data or accessxi.packet_event_string(e, 'data_modified', 'size') or accessxi.packet_event_string(e, 'data', 'size') or '';
    local native_cursor = read_current_native_menu_index(0x4C);
    local native_count = read_current_native_menu_index(0x58);
    local area_choices = accessxi.mog_door_area_choices_for_zone(accessxi.current_zone_id());
    local area_count = (area_choices ~= nil) and #area_choices or 0;

    if (id == 0x015) then
        -- 0x015 fires while the Door parent row is merely highlighted, so it is
        -- not a reliable area-list transition signal.
        return;
    end

    local key = ('%d:%d:%d:%s'):fmt(
        native_cursor,
        area_count,
        get_current_menu_object_ptr(),
        accessxi.packet_hex_limit(data, 24));
    if (key ~= tostring(accessxi.last_mog_door_submit_packet_key or '')) then
        accessxi.last_mog_door_submit_packet_key = key;
        log_state(('state mogdoor packet-submit id=0x%03X cursor4C=%d nativeCount=%d areaCount=%d menu="%s" target="%s" window="%s" hex=%s'):fmt(
            id,
            native_cursor,
            native_count,
            area_count,
            accessxi.escape_probe_log_text(menu_name),
            accessxi.escape_probe_log_text(target_name),
            accessxi.escape_probe_log_text(window_name),
            accessxi.packet_hex_limit(data, 80)));
    end

    if (native_cursor ~= 4) then
        return;
    end

    log_state(('state mogdoor area-submit-probe reason="packet-out-05b-row4" cursor4C=%d nativeCount=%d areaCount=%d'):fmt(
        native_cursor,
        native_count,
        area_count));
    if (area_count > 0) then
        accessxi.mog_door_area_pending_until = tick() + 3500;
    end
end

function accessxi.capture_mog_door_incoming_packet(e)
    local id = tonumber(e ~= nil and e.id or 0) or 0;
    if (id ~= 0x067) then
        return;
    end

    local menu_name = tostring(get_menu_name() or '');
    local target_name = tostring(accessxi.last_target_name or '');
    local window_name = '';
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    if (target ~= nil) then
        window_name = accessxi.plain_native_menu_label(safe_call(function () return target:GetWindowName(); end, '') or '');
    end

    local is_mog_door = menu_name:eq('menu    mogdoor', true)
        or window_name:eq('Door: Back to Town', true)
        or target_name:eq('Door: Back to Town', true)
        or target_name:eq('Door. Back to Town', true);
    if (not is_mog_door) then
        return;
    end

    local native_cursor = read_current_native_menu_index(0x4C);
    local area_choices = accessxi.mog_door_area_choices_for_zone(accessxi.current_zone_id());
    local area_count = (area_choices ~= nil) and #area_choices or 0;
    local data = e.data_modified or e.data or accessxi.packet_event_string(e, 'data_modified', 'size') or accessxi.packet_event_string(e, 'data', 'size') or '';
    local hex80 = accessxi.packet_hex_limit(data, 80);
    local key = ('%03X:%d:%d:%08X:%s'):fmt(
        id,
        native_cursor,
        area_count,
        get_current_menu_object_ptr(),
        accessxi.packet_hex_limit(data, 32));
    if (key ~= tostring(accessxi.last_mog_door_067_candidate_key or '')) then
        accessxi.last_mog_door_067_candidate_key = key;
        log_state(('state mogdoor packet-067-candidate id=0x%03X cursor4C=%d nativeCount=%d areaCount=%d menu="%s" target="%s" window="%s" hex=%s'):fmt(
            id,
            native_cursor,
            read_current_native_menu_index(0x58),
            area_count,
            accessxi.escape_probe_log_text(menu_name),
            accessxi.escape_probe_log_text(target_name),
            accessxi.escape_probe_log_text(window_name),
            hex80));
    end

    if (native_cursor ~= 4) then
        return;
    end

    if (key ~= tostring(accessxi.last_mog_door_in_packet_key or '')) then
        accessxi.last_mog_door_in_packet_key = key;
        log_state(('state mogdoor area-reply-probe reason="packet-in-067-row4" id=0x%03X cursor4C=%d nativeCount=%d areaCount=%d menu="%s" target="%s" window="%s" hex=%s'):fmt(
            id,
            native_cursor,
            read_current_native_menu_index(0x58),
            area_count,
            accessxi.escape_probe_log_text(menu_name),
            accessxi.escape_probe_log_text(target_name),
            accessxi.escape_probe_log_text(window_name),
            hex80));
    end
end

function accessxi.mog_door_note_key(key)
    key = tonumber(key) or 0;
    local menu_name = tostring(get_menu_name() or '');
    if (key == VK_ESCAPE and not menu_name:eq('menu    mogdoor', true)) then
        local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
        local window_name = '';
        if (target ~= nil) then
            window_name = accessxi.plain_native_menu_label(safe_call(function () return target:GetWindowName(); end, '') or '');
        end
        local target_name = tostring(accessxi.last_target_name or '');
        if (window_name:eq('Door: Back to Town', true)
            or target_name:eq('Door: Back to Town', true)
            or target_name:eq('Door. Back to Town', true)) then
            accessxi.mog_door_clear_area_state('escape');
            return true;
        end
    end
    if (not menu_name:eq('menu    mogdoor', true)) then
        return false;
    end

    if (key == VK_ESCAPE) then
        local cursor4c = read_current_native_menu_index(0x4C);
        local native_count = read_current_native_menu_index(0x58);
        local diag_key = ('%d:%d:%d:%08X'):fmt(
            key,
            cursor4c,
            native_count,
            get_current_menu_object_ptr());
        if (diag_key ~= tostring(accessxi.last_mog_door_key_diag or '')) then
            accessxi.last_mog_door_key_diag = diag_key;
            log_state(('state mogdoor key key=0x%02X cursor4C=%d nativeCount=%d obj=0x%08X parent4=0x%08X areaObj=0x%08X areaUntil=%d'):fmt(
                key,
                cursor4c,
                native_count,
                get_current_menu_object_ptr(),
                tonumber(accessxi.mog_door_parent_row4_entry) or 0,
                tonumber(accessxi.mog_door_area_list_obj) or 0,
                tonumber(accessxi.mog_door_area_list_until) or 0));
        end
    end

    if (key == VK_ESCAPE) then
        accessxi.mog_door_clear_area_state('escape');
        return true;
    end

    return false;
end

function accessxi.mog_door_area_mode_for_state(native_cursor, entry, obj, child, sub, sub_x, sub_y, area_count, ank_num, native_state)
    native_cursor = tonumber(native_cursor) or 0;
    entry = tonumber(entry) or 0;
    obj = tonumber(obj) or 0;
    child = tonumber(child) or 0;
    sub = tonumber(sub) or -1;
    sub_x = tonumber(sub_x) or -1;
    sub_y = tonumber(sub_y) or -1;
    area_count = tonumber(area_count) or 0;
    ank_num = tonumber(ank_num) or -1;

    local now = tick();
    native_state = native_state or accessxi.mog_door_native_state(ank_num);
    if (native_state.valid) then
        if ((tonumber(native_state.mode) or 0) ~= 0) then
            local native_count = tonumber(native_state.count) or 0;
            local row = tonumber(native_state.row) or 0;
            if ((row < 1 or (native_count > 0 and row > native_count))
                and native_cursor >= 1
                and (native_count <= 0 or native_cursor <= native_count)) then
                row = native_cursor;
            end
            accessxi.mog_door_area_list_obj = tonumber(native_state.obj) or 0;
            accessxi.mog_door_area_list_child = tonumber(native_state.control) or 0;
            accessxi.mog_door_area_list_until = now + 3000;
            accessxi.mog_door_area_pending_until = 0;
            accessxi.mog_door_area_escape_hold = 0;
            accessxi.mog_door_area_hold_reason = '';
            accessxi.mog_door_remember_cursor(row, 'area-list');
            return true, 'native-mogdoor-state', row;
        end

        if ((tonumber(accessxi.mog_door_area_list_obj) or 0) ~= 0
            or (tonumber(accessxi.mog_door_area_pending_until) or 0) > now
            or (tonumber(accessxi.mog_door_area_ank_mode_until) or 0) > now) then
            accessxi.mog_door_clear_area_state('native-parent-state');
        end
        accessxi.mog_door_remember_cursor(native_cursor, 'parent');
        return false, 'native-mogdoor-parent', native_cursor;
    end

    accessxi.mog_door_remember_cursor(native_cursor, 'parent');
    return false, tostring(native_state.reason or 'native-mogdoor-missing'), native_cursor;
end

function accessxi.mog_door_menu_speech(menu_name, title, obj, selected, count, page, raw, child, entry)
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    local myroom_callback = tonumber(target ~= nil and safe_call(function () return target:GetMyroomCallback(); end, 0) or 0) or 0;
    local action_callback = tonumber(target ~= nil and safe_call(function () return target:GetActionCallback(); end, 0) or 0) or 0;
    local cancel_callback = tonumber(target ~= nil and safe_call(function () return target:GetCancelCallback(); end, 0) or 0) or 0;
    local ank_num = tonumber(target ~= nil and safe_call(function () return target:GetWindowAnkNum(); end, -1) or -1) or -1;
    local ank_x = tonumber(target ~= nil and safe_call(function () return target:GetWindowAnkX(); end, -1) or -1) or -1;
    local ank_y = tonumber(target ~= nil and safe_call(function () return target:GetWindowAnkY(); end, -1) or -1) or -1;
    local sub = tonumber(target ~= nil and safe_call(function () return target:GetWindowSub(); end, -1) or -1) or -1;
    local sub_x = tonumber(target ~= nil and safe_call(function () return target:GetWindowSubAnkX(); end, -1) or -1) or -1;
    local sub_y = tonumber(target ~= nil and safe_call(function () return target:GetWindowSubAnkY(); end, -1) or -1) or -1;
    local window_name = accessxi.survival_guide_text(target ~= nil and safe_call(function () return target:GetWindowName(); end, '') or '');
    if (window_name ~= '') then
        title = window_name;
    end
    local speech_title = 'Door';
    local destination = '';
    if (tostring(title or '') ~= '') then
        destination = tostring(title or ''):match('^%s*Door:%s*(.-)%s*$') or '';
    end

    if ((tonumber(accessxi.mog_door_area_list_obj) or 0) ~= 0
        and bit.band(kernel32.GetAsyncKeyState(VK_ESCAPE), 0x8000) ~= 0
        and tick() > (tonumber(accessxi.mog_door_last_escape_clear_tick) or 0)) then
        accessxi.mog_door_last_escape_clear_tick = tick() + 500;
        accessxi.mog_door_clear_area_state('escape');
    end

    local shape_parts = T{};
    if (target ~= nil) then
        for i = 0, 6 do
            local shape = tonumber(safe_call(function () return target:GetWindowAnkShape(i); end, 0)) or 0;
            if (shape ~= 0) then
                local direct = accessxi.is_probe_pointer(shape) and accessxi.status_menu_probe_runs(shape, 0x100) or '';
                shape_parts:append(('%d=0x%08X:%s'):fmt(
                    i,
                    shape,
                    accessxi.escape_probe_log_text_wide(direct)));
            end
        end
    end

    local current_zone = accessxi.current_zone_id();
    local current_zone_name = accessxi.mog_door_zone_name(current_zone);
    local area_choices, area_family = accessxi.mog_door_area_choices_for_zone(current_zone);
    local area_count = (area_choices ~= nil) and #area_choices or 0;
    local native_cursor = read_current_native_menu_index(0x4C);
    local native_area_count = read_current_native_menu_index(0x58);
    local native_state = accessxi.mog_door_native_state(ank_num);
    local native_state_count = native_state.valid and (tonumber(native_state.count) or 0) or 0;
    local area_mode, area_reason, area_row = accessxi.mog_door_area_mode_for_state(native_cursor, entry, obj, child, sub, sub_x, sub_y, area_count, ank_num, native_state);
    local display_selected = area_mode and (tonumber(area_row) or native_cursor) or native_cursor;
    local display_count = area_mode and math.max(native_state_count, area_count, native_area_count, 1) or 4;
    if (display_selected < 1 or display_selected > display_count) then
        display_selected = 0;
    end

        local key = ('%s:%d:%d:%08X:%08X:%08X:%08X:%08X:%08X:%s'):fmt(
        menu_name,
        display_selected,
        display_count,
        tonumber(obj) or 0,
        tonumber(child) or 0,
        tonumber(entry) or 0,
        myroom_callback,
        action_callback,
        cancel_callback,
        tostring(title or ''));
    if (key ~= tostring(accessxi.last_mog_door_key or '')) then
        accessxi.last_mog_door_key = key;
        log_state(('state mogdoor native menu="%s" title="%s" mode="%s" reason="%s" zone=%d zoneName="%s" areaFamily="%s" areaCount=%d nativeObj=0x%08X nativeMode=%d nativeRows=%d nativeRow=%d nativeCtl=0x%08X nativeAreaTable=0x%08X ank=%d ankXY=(%d,%d) sub=%d subXY=(%d,%d) myroomCb=0x%08X actionCb=0x%08X cancelCb=0x%08X option=%d count=%d selected=%d nativeCount=%d cursor4C=%d obj24=%d obj28=%d obj30=%d obj34=%d obj50=%d obj58=%d obj64=%d page=%d raw=0x%08X obj=0x%08X child=0x%08X entry=0x%08X parent1=0x%08X parent4=0x%08X areaObj=0x%08X areaChild=0x%08X areaSub=%d areaSubXY=(%d,%d) areaUntil=%d pendingUntil=%d hold=%d holdReason="%s" shapes="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            area_mode and 'area-list' or 'parent',
            tostring(area_reason or ''),
            current_zone,
            accessxi.escape_probe_log_text(current_zone_name),
            accessxi.escape_probe_log_text(area_family or ''),
            area_count,
            tonumber(native_state.obj) or 0,
            tonumber(native_state.mode) or -1,
            tonumber(native_state.count) or 0,
            tonumber(native_state.row) or 0,
            tonumber(native_state.control) or 0,
            tonumber(native_state.area_table) or 0,
            ank_num,
            ank_x,
            ank_y,
            sub,
            sub_x,
            sub_y,
            myroom_callback,
            action_callback,
            cancel_callback,
            display_selected,
            display_count,
            selected,
            count,
            native_cursor,
            read_current_native_menu_index(0x24),
            read_current_native_menu_index(0x28),
            read_current_native_menu_index(0x30),
            read_current_native_menu_index(0x34),
            read_current_native_menu_index(0x50),
            read_current_native_menu_index(0x58),
            read_current_native_menu_index(0x64),
            tonumber(page) or 0,
            tonumber(raw) or 0,
            tonumber(obj) or 0,
            tonumber(child) or 0,
            tonumber(entry) or 0,
            tonumber(accessxi.mog_door_parent_row1_entry) or 0,
            tonumber(accessxi.mog_door_parent_row4_entry) or 0,
            tonumber(accessxi.mog_door_area_list_obj) or 0,
            tonumber(accessxi.mog_door_area_list_child) or 0,
            tonumber(accessxi.mog_door_area_list_sub) or -1,
            tonumber(accessxi.mog_door_area_list_sub_x) or -1,
            tonumber(accessxi.mog_door_area_list_sub_y) or -1,
            tonumber(accessxi.mog_door_area_list_until) or 0,
            tonumber(accessxi.mog_door_area_pending_until) or 0,
            tonumber(accessxi.mog_door_area_escape_hold) or 0,
            accessxi.escape_probe_log_text(accessxi.mog_door_area_hold_reason or ''),
            accessxi.escape_probe_log_text_wide(shape_parts:concat(' | '))));
    end

    if ((tonumber(accessxi.mog_door_signal_probe_until) or 0) > tick()) then
        accessxi.log_mog_door_signal_probe(menu_name, title, obj, selected, count, page, raw, child, entry, native_cursor, area_mode, area_reason, area_count);
    end

    if (display_selected <= 0) then
        return nil;
    end

    local parent_ptr = target ~= nil and accessxi.mog_door_target_window_parent_ptr(target) or 0;
    accessxi.log_mog_door_parent_text_probe(parent_ptr, 'active-row');
    accessxi.log_mog_door_row_text_probe(
        menu_name,
        title,
        obj,
        child,
        entry,
        selected,
        count,
        display_selected,
        display_count,
        native_cursor,
        area_mode and 'area-list' or 'parent',
        area_reason);

    local label_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x44) or 0) or 0;
    local help_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x40) or 0) or 0;
    local direct_label = accessxi.plain_native_menu_label(read_probe_string(label_ptr, 120));
    local help_text = accessxi.plain_native_menu_help(read_probe_string(help_ptr, 220));
    if (direct_label ~= '' and not area_mode) then
        accessxi.last_native_menu_name = menu_name;
        accessxi.last_native_menu_label = direct_label;
        accessxi.last_native_menu_selected = display_selected;
        accessxi.last_native_menu_tick = tick();
        accessxi.current_speech_key = ('mogdoor-label:%d:%d:0x%08X:%s:%s'):fmt(
            display_selected,
            display_count,
            tonumber(label_ptr) or 0,
            direct_label,
            help_text);
        log_state(('state mogdoor label menu="%s" title="%s" ank=%d option=%d count=%d entry=0x%08X labelPtr=0x%08X helpPtr=0x%08X label="%s" help="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            ank_num,
            display_selected,
            display_count,
            tonumber(entry) or 0,
            tonumber(label_ptr) or 0,
            tonumber(help_ptr) or 0,
            accessxi.escape_probe_log_text(direct_label),
            accessxi.escape_probe_log_text(help_text)));
        if (help_text ~= '') then
            return ('%s. %s %s'):fmt(speech_title, accessxi.sentence_fragment(direct_label), accessxi.sentence_fragment(help_text));
        end
        return ('%s. %s'):fmt(speech_title, accessxi.sentence_fragment(direct_label));
    end

    if (area_mode) then
        local area_choice = accessxi.mog_door_native_area_choice_for_row(display_selected, native_state);
        if (area_choice ~= nil and tostring(area_choice.label or '') ~= '') then
            local area_row = tonumber(area_choice.row) or 0;
            local area_label = tostring(area_choice.label or '');
            accessxi.last_native_menu_name = menu_name;
            accessxi.last_native_menu_label = area_label;
            accessxi.last_native_menu_selected = area_row;
            accessxi.last_native_menu_tick = tick();
            local speech_key = ('mogdoor-area:%d:%s'):fmt(
                area_row,
                area_label);
            if (speech_key ~= tostring(accessxi.current_speech_key or '')) then
                log_state(('state mogdoor area-dat-label menu="%s" title="%s" reason="%s" zone=%d zoneName="%s" family="%s" ank=%d cursor4C=%d row=%d count=%d dat="%s" label="%s"'):fmt(
                    menu_name,
                    accessxi.escape_probe_log_text(title or ''),
                    tostring(area_reason or ''),
                    current_zone,
                    accessxi.escape_probe_log_text(current_zone_name),
                    accessxi.escape_probe_log_text(area_choice.family or ''),
                    ank_num,
                    native_cursor,
                    area_row,
                    display_count,
                    accessxi.escape_probe_log_text(area_choice.dat or ''),
                    accessxi.escape_probe_log_text(area_label)));
            end
            accessxi.current_speech_key = speech_key;
            accessxi.log_mog_door_shape_probe(menu_name, title, obj, selected, count, page, raw, child, entry, ank_num, display_selected, display_count, destination);
            return ('%s. %s'):fmt(speech_title, accessxi.sentence_fragment(area_label));
        end

        log_state(('state mogdoor area-unmapped menu="%s" title="%s" reason="%s" zone=%d zoneName="%s" row=%d count=%d'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            tostring(area_reason or ''),
            current_zone,
            accessxi.escape_probe_log_text(current_zone_name),
            display_selected,
            display_count));
        accessxi.log_mog_door_shape_probe(menu_name, title, obj, selected, count, page, raw, child, entry, ank_num, display_selected, display_count, destination);
        return nil;
    end

    local dat_choice = accessxi.mog_door_dat_choice_for_row(display_selected);
    if (dat_choice ~= nil and tostring(dat_choice.label or '') ~= '') then
        local dat_row = tonumber(dat_choice.row) or 0;
        local dat_label = tostring(dat_choice.label or '');
        accessxi.last_native_menu_name = menu_name;
        accessxi.last_native_menu_label = dat_label;
        accessxi.last_native_menu_selected = dat_row;
        accessxi.last_native_menu_tick = tick();
        local speech_key = ('mogdoor-dat:%d:%s'):fmt(
            dat_row,
            dat_label);
        if (speech_key ~= tostring(accessxi.current_speech_key or '')) then
            log_state(('state mogdoor dat-label menu="%s" title="%s" ank=%d cursor4C=%d row=%d count=%d dat="%s" label="%s"'):fmt(
                menu_name,
                accessxi.escape_probe_log_text(title or ''),
                ank_num,
                native_cursor,
                dat_row,
                display_count,
                accessxi.escape_probe_log_text(dat_choice.dat or ''),
                accessxi.escape_probe_log_text(dat_label)));
        end
        accessxi.current_speech_key = speech_key;
        accessxi.log_mog_door_shape_probe(menu_name, title, obj, selected, count, page, raw, child, entry, ank_num, display_selected, display_count, destination);
        return ('%s. %s'):fmt(speech_title, accessxi.sentence_fragment(dat_label));
    end

    local list_label, list_mode = accessxi.native_query_label_for_selection(child, display_selected, display_count, 'plain');
    if ((list_label == nil or list_label == '') and count > display_count and display_selected <= count) then
        list_label, list_mode = accessxi.native_query_label_for_selection(child, display_selected, count, 'plain');
    end
    list_label = accessxi.plain_native_menu_label(list_label or '');
    if (list_label ~= '') then
        accessxi.last_native_menu_name = menu_name;
        accessxi.last_native_menu_label = list_label;
        accessxi.last_native_menu_selected = display_selected;
        accessxi.last_native_menu_tick = tick();
        accessxi.current_speech_key = ('mogdoor-list:%d:%d:%s:%s'):fmt(
            display_selected,
            display_count,
            tostring(list_mode or ''),
            list_label);
        log_state(('state mogdoor list-label menu="%s" title="%s" ank=%d option=%d count=%d nativeCount=%d mode="%s" label="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            ank_num,
            display_selected,
            display_count,
            count,
            tostring(list_mode or ''),
            accessxi.escape_probe_log_text(list_label)));
        return ('%s. %s'):fmt(speech_title, accessxi.sentence_fragment(list_label));
    end

    accessxi.log_mog_door_shape_probe(menu_name, title, obj, selected, count, page, raw, child, entry, ank_num, display_selected, display_count, destination);

    if (destination ~= '') then
        local speech = ('%s. %s'):fmt(speech_title, accessxi.sentence_fragment(destination));
        accessxi.last_native_menu_name = menu_name;
        accessxi.last_native_menu_label = destination;
        accessxi.last_native_menu_selected = display_selected;
        accessxi.last_native_menu_tick = tick();
        accessxi.current_speech_key = ('mogdoor-window:%s:%s'):fmt(menu_name, destination);
        log_state(('state mogdoor window-title menu="%s" title="%s" ank=%d option=%d count=%d destination="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            ank_num,
            display_selected,
            display_count,
            accessxi.escape_probe_log_text(destination)));
        return speech;
    end

    local probe_key = ('0x%08X:0x%08X'):fmt(tonumber(entry) or 0, tonumber(child) or 0);
    if (probe_key ~= tostring(accessxi.last_mog_door_deep_key or '')) then
        accessxi.last_mog_door_deep_key = probe_key;
        log_line(('mogdoorprobe menu="%s" title="%s" destination="%s" ank=%d option=%d count=%d obj=0x%08X child=0x%08X entry=0x%08X entryDwords="%s" entryInline="%s" entryRuns="%s" entryPtrs="%s" childDwords="%s" childInline="%s" childRuns="%s" childPtrs="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            accessxi.escape_probe_log_text(destination),
            ank_num,
            display_selected,
            display_count,
            tonumber(obj) or 0,
            tonumber(child) or 0,
            tonumber(entry) or 0,
            accessxi.escape_probe_log_text(accessxi.format_probe_dwords(entry, 0, 64)),
            accessxi.escape_probe_log_text(accessxi.status_menu_probe_inline_strings(entry)),
            accessxi.escape_probe_log_text(accessxi.status_menu_probe_runs(entry, 0x260)),
            accessxi.escape_probe_log_text(accessxi.status_menu_probe_pointer_fields(entry)),
            accessxi.escape_probe_log_text(accessxi.format_probe_dwords(child, 0, 64)),
            accessxi.escape_probe_log_text(accessxi.status_menu_probe_inline_strings(child)),
            accessxi.escape_probe_log_text(accessxi.status_menu_probe_runs(child, 0x260)),
            accessxi.escape_probe_log_text(accessxi.status_menu_probe_pointer_fields(child))));
    end

    local suppressed_key = ('%s:%s:%d'):fmt(menu_name, destination, display_count);
    if (suppressed_key ~= tostring(accessxi.last_mog_door_suppressed_key or '')) then
        accessxi.last_mog_door_suppressed_key = suppressed_key;
        log_state(('state mogdoor suppressed menu="%s" title="%s" destination="%s" reason="native-label-missing"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            accessxi.escape_probe_log_text(destination)));
    end
    return nil;
end

function accessxi.mog_roomlist_menu_speech(menu_name, title, obj, selected, count, page, raw, child, entry)
    local target = safe_call(function () return AshitaCore:GetMemoryManager():GetTarget(); end, nil);
    local ank_num = tonumber(target ~= nil and safe_call(function () return target:GetWindowAnkNum(); end, -1) or -1) or -1;
    local window_name = accessxi.survival_guide_text(target ~= nil and safe_call(function () return target:GetWindowName(); end, '') or '');
    if (window_name ~= '') then
        title = window_name;
    end
    if (tostring(title or '') == '') then
        title = 'Area';
    end

    local native_cursor = read_current_native_menu_index(0x4C);
    local display_selected = native_cursor;
    local display_count = tonumber(count) or 0;
    if (display_count <= 0 or display_count > 32) then
        display_count = math.max(
            tonumber(read_current_native_menu_index(0x24)) or 0,
            tonumber(read_current_native_menu_index(0x28)) or 0);
    end
    if (display_count <= 0 or display_count > 32) then
        display_count = 0;
    end
    if (display_selected < 1 or (display_count > 0 and display_selected > display_count)) then
        display_selected = tonumber(selected) or 0;
    end

    local key = ('%s:%d:%d:%08X:%08X:%08X:%s'):fmt(
        menu_name,
        tonumber(display_selected) or 0,
        tonumber(display_count) or 0,
        tonumber(obj) or 0,
        tonumber(child) or 0,
        tonumber(entry) or 0,
        tostring(title or ''));
    if (key ~= tostring(accessxi.last_mog_roomlist_key or '')) then
        accessxi.last_mog_roomlist_key = key;
        log_state(('state roomlist native menu="%s" title="%s" ank=%d option=%d count=%d selected=%d nativeCount=%d cursor4C=%d obj24=%d obj28=%d obj30=%d obj34=%d obj50=%d obj64=%d page=%d raw=0x%08X obj=0x%08X child=0x%08X entry=0x%08X'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            ank_num,
            tonumber(display_selected) or 0,
            tonumber(display_count) or 0,
            tonumber(selected) or 0,
            tonumber(count) or 0,
            native_cursor,
            read_current_native_menu_index(0x24),
            read_current_native_menu_index(0x28),
            read_current_native_menu_index(0x30),
            read_current_native_menu_index(0x34),
            read_current_native_menu_index(0x50),
            read_current_native_menu_index(0x64),
            tonumber(page) or 0,
            tonumber(raw) or 0,
            tonumber(obj) or 0,
            tonumber(child) or 0,
            tonumber(entry) or 0));
    end

    if (display_selected <= 0 or display_count <= 0) then
        return nil;
    end

    local label_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x44) or 0) or 0;
    local help_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x40) or 0) or 0;
    local direct_label = accessxi.plain_native_menu_label(read_probe_string(label_ptr, 160));
    local help_text = accessxi.plain_native_menu_help(read_probe_string(help_ptr, 220));
    if (direct_label ~= '') then
        accessxi.last_native_menu_name = menu_name;
        accessxi.last_native_menu_label = direct_label;
        accessxi.last_native_menu_selected = display_selected;
        accessxi.last_native_menu_tick = tick();
        accessxi.current_speech_key = ('roomlist-label:%d:%d:0x%08X:%s:%s'):fmt(
            display_selected,
            display_count,
            tonumber(label_ptr) or 0,
            direct_label,
            help_text);
        log_state(('state roomlist label menu="%s" title="%s" ank=%d option=%d count=%d entry=0x%08X labelPtr=0x%08X helpPtr=0x%08X label="%s" help="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            ank_num,
            display_selected,
            display_count,
            tonumber(entry) or 0,
            tonumber(label_ptr) or 0,
            tonumber(help_ptr) or 0,
            accessxi.escape_probe_log_text(direct_label),
            accessxi.escape_probe_log_text(help_text)));
        if (help_text ~= '') then
            return ('%s. %s %s'):fmt(title, accessxi.sentence_fragment(direct_label), accessxi.sentence_fragment(help_text));
        end
        return ('%s. %s'):fmt(title, accessxi.sentence_fragment(direct_label));
    end

    local list_label, list_mode = accessxi.native_query_label_for_selection(child, display_selected, display_count, 'plain');
    list_label = accessxi.plain_native_menu_label(list_label or '');
    if (list_label ~= '') then
        accessxi.last_native_menu_name = menu_name;
        accessxi.last_native_menu_label = list_label;
        accessxi.last_native_menu_selected = display_selected;
        accessxi.last_native_menu_tick = tick();
        accessxi.current_speech_key = ('roomlist-list:%d:%d:%s:%s'):fmt(
            display_selected,
            display_count,
            tostring(list_mode or ''),
            list_label);
        log_state(('state roomlist list-label menu="%s" title="%s" ank=%d option=%d count=%d nativeCount=%d mode="%s" label="%s"'):fmt(
            menu_name,
            accessxi.escape_probe_log_text(title or ''),
            ank_num,
            display_selected,
            display_count,
            tonumber(count) or 0,
            tostring(list_mode or ''),
            accessxi.escape_probe_log_text(list_label)));
        return ('%s. %s'):fmt(title, accessxi.sentence_fragment(list_label));
    end

    log_state(('state roomlist native-missing-label menu="%s" title="%s" ank=%d option=%d count=%d mode="%s" raw=0x%08X child=0x%08X entry=0x%08X'):fmt(
        menu_name,
        accessxi.escape_probe_log_text(title or ''),
        ank_num,
        display_selected,
        display_count,
        tostring(list_mode or ''),
        tonumber(raw) or 0,
        tonumber(child) or 0,
        tonumber(entry) or 0));
    return nil;
end


local ctx = main_menu_context or T{};

local get_current_menu_object_ptr = ctx.get_current_menu_object_ptr or function () return 0; end;
local read_current_native_menu_index = ctx.read_current_native_menu_index or function () return 0; end;
local read_u32 = ctx.read_u32 or function () return 0; end;
local read_probe_string = ctx.read_probe_string or function () return ''; end;
local log_state = ctx.log_state or function () end;
local tick = ctx.tick or function () return 0; end;

function accessxi.native_main_menu_speech(name)
    local menu_name = tostring(name or '');
    if (not menu_name:eq('menu    menuwind', true) and not menu_name:eq('menu    socialme', true)) then
        return nil;
    end
    accessxi.current_menu_speech_title = 'Main menu';

    local obj = get_current_menu_object_ptr();
    if (obj == 0) then
        return nil;
    end

    local query_selected, page, raw, child, count = accessxi.survival_guide_query_child_state_for_obj(obj);
    local selected = tonumber(query_selected) or 0;
    count = tonumber(count) or 0;
    if (selected <= 0) then
        selected = read_current_native_menu_index(0x4C);
    end
    if (count <= 0 or count > 64) then
        local count_a = accessxi.native_menu_index(0x24);
        local count_b = accessxi.native_menu_index(0x28);
        count = math.max(tonumber(count_a) or 0, tonumber(count_b) or 0);
    end

    local entry = read_u32(obj + 0x08) or 0;
    local label_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x44) or 0) or 0;
    local help_ptr = accessxi.is_probe_pointer(entry) and (read_u32(entry + 0x40) or 0) or 0;
    local direct_label = accessxi.plain_native_menu_label(read_probe_string(label_ptr));

    local label = '';
    local source = '';
    local mode = '';
    if (selected > 0 and count > 0 and count <= 64 and selected <= count and accessxi.is_probe_pointer(child)) then
        label, mode = accessxi.native_query_label_for_selection(child, selected, count, 'main-menu');
        label = accessxi.plain_native_menu_label(label or '');
        if (label ~= '') then
            source = 'native-query';
        end
    end

    if (label == '' and direct_label ~= '') then
        label = direct_label;
        source = 'direct-entry';
    end

    local mog_house_state = false;
    local mog_house_flags = 0;
    local mog_house_zone_info = 0;
    local mog_house_reason = '';
    local current_zone = accessxi.current_zone_id();
    local residence = accessxi.current_player_residence();
    local dat_entry = nil;
    local dat_reason = '';
    local dat_source_label = direct_label ~= '' and direct_label or label;
    if (menu_name:eq('menu    menuwind', true) and selected == 12 and dat_source_label:eq('Map', true)) then
        mog_house_state, mog_house_flags, mog_house_zone_info, mog_house_reason = accessxi.current_mog_house_zone_flag();
        if (mog_house_state == true) then
            dat_source_label = 'Mog House';
        end
    end

    dat_entry, dat_reason = accessxi.main_menu_dat_entry(dat_source_label);
    if (dat_entry ~= nil) then
        label = tostring(dat_entry.label or '');
        source = mog_house_state == true and 'main-menu-dat-mog-house' or 'main-menu-dat';
    end

    if (label ~= '') then
        local direct_help = accessxi.plain_native_menu_help(read_probe_string(help_ptr));
        local help_text = '';
        local dat_ref = '';
        if (dat_entry ~= nil) then
            help_text = tostring(dat_entry.help or '');
            dat_ref = tostring(dat_entry.source or '');
            if (mog_house_state == true) then
                dat_ref = dat_ref .. ' signal=zone-flags+0x0100';
            end
        elseif (source == 'direct-entry' or label:eq(direct_label, true)) then
            help_text = direct_help;
        end
        accessxi.last_native_menu_name = menu_name;
        accessxi.last_native_menu_label = label;
        accessxi.last_native_menu_selected = selected;
        accessxi.last_native_menu_tick = tick();
        if (label:eq('Synthesis', true)) then
            accessxi.synthesis_context_until = tick() + 120000;
        end
        if (label:eq('Key Items', true)) then
            accessxi.key_items_context_until = tick() + 120000;
        end
        accessxi.current_speech_key = ('main-menu-entry:%s:%d:%d:%d:%s:%s'):fmt(
            menu_name,
            selected,
            tonumber(page) or 0,
            count,
            source,
            label);
        local state_key = ('%s:%d:%d:%d:%s:%s:%s:%s:%s:%s:%s:%d:%d:%s:%s'):fmt(
            menu_name,
            selected,
            tonumber(page) or 0,
            count,
            source,
            tostring(mode or ''),
            label,
            help_text,
            direct_label,
            dat_source_label,
            tostring(dat_reason or ''),
            tonumber(current_zone) or 0,
            tonumber(residence) or -1,
            tostring(mog_house_state),
            tostring(mog_house_reason or ''));
        if (state_key ~= tostring(accessxi.main_menu_last_state_key or '')) then
            accessxi.main_menu_last_state_key = state_key;
            log_state(('state mainmenu entry menu="%s" select=%d page=%d count=%d source="%s" mode="%s" raw=0x%08X child=0x%08X entry=0x%08X labelPtr=0x%08X helpPtr=0x%08X label="%s" directLabel="%s" datSourceLabel="%s" help="%s" directHelp="%s" datReason="%s" zone=%d residence=%d mogFlag=%s mogFlags=0x%08X mogZoneInfo=0x%08X mogReason="%s" dat="%s"'):fmt(
                menu_name,
                selected,
                tonumber(page) or 0,
                count,
                source,
                tostring(mode or ''),
                tonumber(raw) or 0,
                tonumber(child) or 0,
                entry,
                label_ptr,
                help_ptr,
                label,
                direct_label,
                dat_source_label,
                help_text,
                direct_help,
                accessxi.escape_probe_log_text(dat_reason),
                tonumber(current_zone) or 0,
                tonumber(residence) or -1,
                tostring(mog_house_state),
                tonumber(mog_house_flags) or 0,
                tonumber(mog_house_zone_info) or 0,
                accessxi.escape_probe_log_text(mog_house_reason),
                accessxi.escape_probe_log_text(dat_ref)));
        end
        if (help_text ~= '') then
            return ('Main menu. %s %s'):fmt(accessxi.sentence_fragment(label), accessxi.sentence_fragment(help_text));
        end
        return ('Main menu. %s'):fmt(accessxi.sentence_fragment(label));
    end

    if (selected <= 0 or count <= 0 or count > 64 or selected > count or not accessxi.is_probe_pointer(child)) then
        log_state(('state mainmenu native-missing menu="%s" select=%d count=%d page=%d raw=0x%08X child=0x%08X'):fmt(
            menu_name,
            selected,
            count,
            tonumber(page) or 0,
            tonumber(raw) or 0,
            tonumber(child) or 0));
        return nil;
    end

    log_state(('state mainmenu native-missing menu="%s" select=%d count=%d page=%d mode="%s" raw=0x%08X child=0x%08X directLabel="%s"'):fmt(
        menu_name,
        selected,
        count,
        tonumber(page) or 0,
        tostring(mode or ''),
        tonumber(raw) or 0,
        tonumber(child) or 0,
        direct_label));
    return nil;
end

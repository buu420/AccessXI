local debug_commands = {};

local function has_command(args, ...)
    return (#args >= 2 and args[2]:any(...));
end

local function bounded_seconds(args, index, min_value, max_value, default_value)
    return math.max(min_value, math.min(max_value, tonumber(args[index]) or default_value));
end

function debug_commands.handle(args, ctx)
    ctx = ctx or {};
    local accessxi = ctx.accessxi;
    if (accessxi == nil) then
        return false;
    end

    local speak = ctx.speak or function () end;
    local log_line = ctx.log_line or function () end;
    local tick = ctx.tick or function () return 0; end;
    local command_tail = ctx.command_tail or function () return ''; end;
    local get_menu_name = ctx.get_menu_name or function () return ''; end;
    local safe_call = ctx.safe_call or function (fn, default)
        local ok, result = pcall(fn);
        return ok and result or default;
    end;

    if (has_command(args, 'inputstate', 'movementstate', 'inputdiag', 'stuck')) then
        if (type(accessxi.input_state_text) == 'function') then
            speak(accessxi.input_state_text());
        else
            speak('Input state command is not available.');
            log_line('input state command unavailable');
        end
        return true;
    elseif (has_command(args, 'inputfix', 'unblockinput', 'fixmovement')) then
        if (type(accessxi.input_fix_text) == 'function') then
            speak(accessxi.input_fix_text());
        else
            speak('Input fix command is not available.');
            log_line('input fix command unavailable');
        end
        return true;
    elseif (has_command(args, 'debugprobes', 'ambientprobes', 'menuprobes', 'dispatchprobe', 'probes')) then
        local action = tostring(args[3] or ''):lower();
        if (action:any('off', 'stop', 'disable')) then
            accessxi.debug_probe_logging_enabled = false;
            accessxi.debug_probe_logging_until = 0;
            log_line('debug probes disabled');
            speak('Debug probes disabled.');
            return true;
        end

        local seconds_index = action:any('on', 'start', 'enable') and 4 or 3;
        local seconds = bounded_seconds(args, seconds_index, 5, 120, 30);
        accessxi.debug_probe_logging_enabled = true;
        accessxi.debug_probe_logging_until = tick() + (seconds * 1000);
        accessxi.last_menu_dispatch_probe_log = '';
        accessxi.last_ingame_probe_log = '';
        accessxi.last_unknown_menu_log = '';
        speak(('Debug probes enabled for %d seconds.'):fmt(seconds));
        log_line(('debug probes enabled seconds=%d until=%d'):fmt(
            seconds,
            tonumber(accessxi.debug_probe_logging_until) or 0));
        return true;
    elseif (has_command(args, 'missiontext', 'missionnative', 'missionrowprobe')) then
        local seconds = bounded_seconds(args, 3, 5, 60, 20);
        accessxi.missions_menu_text_probe_until = tick() + (seconds * 1000);
        accessxi.missions_menu_text_probe_count = 0;
        accessxi.missions_menu_text_probe_limit = tonumber(args[4]) or 32;
        accessxi.last_missions_menu_text_probe_key = '';
        speak(('Mission native text probe enabled for %d seconds. Arrow the bad mission rows now.'):fmt(seconds));
        log_line(('missiontext command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.missions_menu_text_probe_until) or 0,
            seconds,
            tonumber(accessxi.missions_menu_text_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'keyitemprobe', 'keyitemsprobe', 'kiprobe')) then
        local seconds = bounded_seconds(args, 3, 5, 60, 20);
        accessxi.key_items_order_probe_until = tick() + (seconds * 1000);
        accessxi.key_items_order_probe_count = 0;
        accessxi.key_items_order_probe_limit = math.max(4, math.min(160, tonumber(args[4]) or 48));
        accessxi.last_key_items_order_probe_key = '';
        accessxi.last_key_items_native_scan_probe_key = '';
        accessxi.key_items_native_order_cache = {};
        speak(('Key items order probe enabled for %d seconds. Arrow the wrong key item rows now.'):fmt(seconds));
        log_line(('keyitemprobe command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.key_items_order_probe_until) or 0,
            seconds,
            tonumber(accessxi.key_items_order_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'keyitemdetail', 'keyitemdetailprobe', 'kidetail', 'kidetailprobe')) then
        accessxi.log_key_items_detail_surface_probe('command');
        speak('Key item detail probe written.');
        return true;
    elseif (has_command(args, 'roehelp', 'roetext', 'roeobjective')) then
        local seconds = bounded_seconds(args, 3, 5, 60, 20);
        accessxi.records_of_eminence_text_probe_until = tick() + (seconds * 1000);
        accessxi.records_of_eminence_text_probe_count = 0;
        accessxi.records_of_eminence_text_probe_limit = math.max(4, math.min(120, tonumber(args[4]) or 32));
        accessxi.last_records_of_eminence_text_probe_key = '';
        log_line(('roetext command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.records_of_eminence_text_probe_until) or 0,
            seconds,
            tonumber(accessxi.records_of_eminence_text_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'roedeep', 'roedetail', 'roegraph')) then
        local seconds = bounded_seconds(args, 3, 5, 60, 25);
        accessxi.records_of_eminence_detail_probe_until = tick() + (seconds * 1000);
        accessxi.records_of_eminence_detail_probe_count = 0;
        accessxi.records_of_eminence_detail_probe_limit = math.max(2, math.min(40, tonumber(args[4]) or 12));
        accessxi.last_records_of_eminence_detail_probe_key = '';
        log_line(('roedeep command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.records_of_eminence_detail_probe_until) or 0,
            seconds,
            tonumber(accessxi.records_of_eminence_detail_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'roetransition', 'roekey', 'roestate')) then
        local seconds = bounded_seconds(args, 3, 5, 60, 20);
        accessxi.records_of_eminence_transition_probe_until = tick() + (seconds * 1000);
        accessxi.records_of_eminence_transition_probe_count = 0;
        accessxi.records_of_eminence_transition_probe_limit = math.max(8, math.min(160, tonumber(args[4]) or 80));
        accessxi.records_of_eminence_transition_probe_last_state_key = '';
        accessxi.records_of_eminence_transition_probe_key_name = '';
        accessxi.records_of_eminence_transition_probe_key_tick = 0;
        log_line(('roetransition command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.records_of_eminence_transition_probe_until) or 0,
            seconds,
            tonumber(accessxi.records_of_eminence_transition_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'questprobe', 'questsubprobe')) then
        local seconds = bounded_seconds(args, 3, 5, 60, 20);
        accessxi.quests_menu_submenu_probe_until = tick() + (seconds * 1000);
        accessxi.last_quests_menu_submenu_probe_key = '';
        accessxi.last_quests_menu_submenu_desc_records_key = '';
        speak(('Quest submenu probe enabled for %d seconds. Arrow the silent quest rows now.'):fmt(seconds));
        log_line(('questprobe command until=%d seconds=%d'):fmt(
            tonumber(accessxi.quests_menu_submenu_probe_until) or 0,
            seconds));
        return true;
    elseif (has_command(args, 'missionobj', 'missionruntime', 'missionhandler')) then
        local seconds = bounded_seconds(args, 3, 5, 60, 20);
        accessxi.missions_menu_object_probe_until = tick() + (seconds * 1000);
        accessxi.missions_menu_object_probe_count = 0;
        accessxi.missions_menu_object_probe_limit = math.max(4, math.min(80, tonumber(args[4]) or 24));
        accessxi.last_missions_menu_object_probe_key = '';
        accessxi.missions_menu_object_probe_table_logged = false;
        speak(('Mission runtime object probe enabled for %d seconds. Arrow the bad mission rows now.'):fmt(seconds));
        log_line(('missionobj command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.missions_menu_object_probe_until) or 0,
            seconds,
            tonumber(accessxi.missions_menu_object_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'helpdeskprobe', 'faqprobe', 'helpdeskdiff', 'faqdiff')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 15);
        accessxi.help_desk_diff_probe_until = tick() + (seconds * 1000);
        accessxi.help_desk_diff_probe_count = 0;
        accessxi.help_desk_diff_probe_limit = math.max(4, math.min(120, tonumber(args[4]) or 80));
        accessxi.help_desk_diff_probe_next = 0;
        accessxi.help_desk_diff_probe_seen = {};
        accessxi.help_desk_diff_probe_last_idx = '';
        speak(('Help Desk diff probe enabled for %d seconds. Arrow the Help Desk rows now.'):fmt(seconds));
        log_line(('helpdeskdiff command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.help_desk_diff_probe_until) or 0,
            seconds,
            tonumber(accessxi.help_desk_diff_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'helpdeskshape', 'helpdeskconfig', 'helpdeskconfigprobe')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.help_desk_shape_probe_until = tick() + (seconds * 1000);
        accessxi.help_desk_shape_probe_count = 0;
        accessxi.help_desk_shape_probe_limit = math.max(2, math.min(40, tonumber(args[4]) or 12));
        accessxi.help_desk_shape_probe_next = 0;
        accessxi.help_desk_shape_probe_last_key = 0;
        accessxi.help_desk_any_probe_count = 0;
        accessxi.help_desk_any_probe_last_sig = '';
        accessxi.help_desk_light_probe_count = 0;
        accessxi.help_desk_light_probe_limit = math.max(20, math.min(240, seconds * 5));
        accessxi.help_desk_light_probe_next = 0;
        speak(('Help Desk shape probe enabled for %d seconds. Arrow the Help Desk rows now.'):fmt(seconds));
        log_line(('helpdeskprobe command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.help_desk_shape_probe_until) or 0,
            seconds,
            tonumber(accessxi.help_desk_shape_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'helpdeskpacket', 'faqpacket')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.help_desk_packet_trace_until = tick() + (seconds * 1000);
        accessxi.help_desk_packet_trace_count = 0;
        accessxi.help_desk_packet_trace_limit = math.max(2, math.min(80, tonumber(args[4]) or 24));
        accessxi.help_desk_packet_trace_key = '';
        speak(('Help Desk packet trace enabled for %d seconds. Open Help Desk and arrow the rows now.'):fmt(seconds));
        log_line(('helpdeskpacket command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.help_desk_packet_trace_until) or 0,
            seconds,
            tonumber(accessxi.help_desk_packet_trace_limit) or 0));
        return true;
    elseif (has_command(args, 'friendtrace', 'friendpacket', 'flistpacket')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.friend_list_packet_trace_until = tick() + (seconds * 1000);
        accessxi.friend_list_packet_trace_count = 0;
        accessxi.friend_list_packet_trace_limit = math.max(5, math.min(160, tonumber(args[4]) or 80));
        accessxi.friend_list_packet_trace_key = '';
        accessxi.friend_list_packet_records_by_key = {};
        accessxi.friend_list_packet_record_order = T{};
        speak(('Friend List packet trace enabled for %d seconds. Close and reopen Friend List, then arrow rows.'):fmt(seconds));
        log_line(('friendtrace command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.friend_list_packet_trace_until) or 0,
            seconds,
            tonumber(accessxi.friend_list_packet_trace_limit) or 0));
        return true;
    elseif (has_command(args, 'friendprobe', 'flistprobe')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.friend_list_dynamic_probe_until = tick() + (seconds * 1000);
        accessxi.last_friend_list_dynamic_child_probe_key = '';
        accessxi.last_friend_list_row_render_probe_key = '';
        accessxi.last_friend_list_dynamic_probe_key = '';
        speak(('Friend List native row probe enabled for %d seconds. Arrow the Edit Friend List rows now.'):fmt(seconds));
        log_line(('friendprobe command until=%d seconds=%d'):fmt(
            tonumber(accessxi.friend_list_dynamic_probe_until) or 0,
            seconds));
        return true;
    elseif (has_command(args, 'friendglyph', 'flistglyph')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.friend_list_glyph_probe_until = tick() + (seconds * 1000);
        accessxi.friend_list_glyph_probe_count = 0;
        accessxi.friend_list_glyph_probe_limit = math.max(4, math.min(180, tonumber(args[4]) or 80));
        accessxi.last_friend_list_glyph_probe_key = '';
        speak(('Friend List glyph probe enabled for %d seconds. Arrow the Edit Friend List rows now.'):fmt(seconds));
        log_line(('friendglyph command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.friend_list_glyph_probe_until) or 0,
            seconds,
            tonumber(accessxi.friend_list_glyph_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'friendraw', 'flistraw')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.friend_list_raw_probe_until = tick() + (seconds * 1000);
        accessxi.last_friend_list_raw_row_probe_key = '';
        accessxi.last_friend_list_dynamic_probe_key = '';
        speak(('Friend List raw row probe enabled for %d seconds. Arrow the Edit Friend List rows now.'):fmt(seconds));
        log_line(('friendraw command until=%d seconds=%d'):fmt(
            tonumber(accessxi.friend_list_raw_probe_until) or 0,
            seconds));
        return true;
    elseif (has_command(args, 'friendtable', 'flisttable')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.friend_list_table_probe_until = tick() + (seconds * 1000);
        accessxi.friend_list_child_table_probe_limit = math.max(4, math.min(tonumber(args[4]) or 80, 180));
        accessxi.friend_list_child_table_probe_count = 0;
        accessxi.last_friend_list_child_table_probe_key = '';
        speak(('Friend List child table probe enabled for %d seconds. Arrow the Edit Friend List rows now.'):fmt(seconds));
        log_line(('friendtable command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.friend_list_table_probe_until) or 0,
            seconds,
            tonumber(accessxi.friend_list_child_table_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'friendnames', 'flistnames')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.friend_list_name_buffer_probe_until = tick() + (seconds * 1000);
        accessxi.friend_list_name_buffer_probe_limit = math.max(2, math.min(tonumber(args[4]) or 12, 32));
        accessxi.last_friend_list_name_buffer_probe_key = '';
        speak(('Friend List name buffer probe enabled for %d seconds. Arrow the Edit Friend List rows now.'):fmt(seconds));
        log_line(('friendnames command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.friend_list_name_buffer_probe_until) or 0,
            seconds,
            tonumber(accessxi.friend_list_name_buffer_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'friendmem', 'flistmem')) then
        local terms = command_tail(args, 3);
        if (accessxi.survival_guide_text(terms) == '') then
            speak('Friend memory scan needs one or more visible names.');
            log_line('friendmem command skipped no terms');
            return true;
        end
        local ran, hits = pcall(function ()
            return accessxi.log_friend_list_memory_scan('command', terms);
        end);
        if (not ran) then
            log_line(('friendmem error="%s"'):fmt(accessxi.escape_probe_log_text(hits)));
            speak('Friend memory scan failed. Error written.');
        else
            speak(('Friend memory scan written. %d hits.'):fmt(tonumber(hits) or 0));
        end
        return true;
    elseif (has_command(args, 'guideprobe', 'primerprobe', 'adventuringprobe')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.adventuring_primer_guide01_probe_until = tick() + (seconds * 1000);
        accessxi.adventuring_primer_guide01_probe_count = 0;
        accessxi.adventuring_primer_guide01_probe_limit = math.max(2, math.min(40, tonumber(args[4]) or 12));
        accessxi.adventuring_primer_guide01_probe_next = 0;
        accessxi.last_adventuring_primer_guide01_native_probe_key = '';
        speak(('Adventuring Primer probe enabled for %d seconds. Arrow the Primer rows now.'):fmt(seconds));
        log_line(('guideprobe command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.adventuring_primer_guide01_probe_until) or 0,
            seconds,
            tonumber(accessxi.adventuring_primer_guide01_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'guidedetail', 'primerdetail', 'adventuringdetail')) then
        local seconds = bounded_seconds(args, 3, 5, 45, 20);
        accessxi.adventuring_primer_detail_probe_until = tick() + (seconds * 1000);
        accessxi.adventuring_primer_detail_probe_count = 0;
        accessxi.adventuring_primer_detail_probe_limit = math.max(1, math.min(20, tonumber(args[4]) or 6));
        accessxi.adventuring_primer_detail_probe_next = 0;
        accessxi.last_adventuring_primer_detail_probe_key = '';
        local current_menu = get_menu_name();
        if ((current_menu:eq('menu    inline', true)
            or current_menu:eq('menu    mapframe', true)
            or current_menu:eq('menu    hfr1', true))) then
            local probe_label = tostring(accessxi.adventuring_primer_detail_candidate_label or '');
            if (probe_label == '') then
                probe_label = tostring(accessxi.last_native_menu_label or '');
            end
            accessxi.log_adventuring_primer_detail_probe(
                current_menu,
                tonumber(accessxi.adventuring_primer_detail_candidate_record_id) or 0,
                probe_label,
                'command-current');
        end
        speak(('Adventuring Primer detail probe enabled for %d seconds. Open one Primer article now.'):fmt(seconds));
        log_line(('primerdetail command until=%d seconds=%d limit=%d'):fmt(
            tonumber(accessxi.adventuring_primer_detail_probe_until) or 0,
            seconds,
            tonumber(accessxi.adventuring_primer_detail_probe_limit) or 0));
        return true;
    elseif (has_command(args, 'guidefind', 'primerfind', 'adventuringfind')) then
        local terms = command_tail(args, 3);
        if (accessxi.survival_guide_text(terms) == '') then
            terms = accessxi.adventuring_primer_guide01_find_terms();
        end
        accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
        local seq = accessxi.menu_dump_sequence;
        local hits = accessxi.log_survival_guide_memory_scan(seq, 'guidefind', terms);
        speak(('Adventuring Primer memory scan %d written. %d hits.'):fmt(seq, tonumber(hits) or 0));
        return true;
    elseif (has_command(args, 'missionrender', 'missiondraw', 'missiongdi')) then
        local ok = accessxi.load_searchhook();
        if (not ok) then
            speak('Mission render trace failed. Search hook did not load.');
            return true;
        end

        local seconds = bounded_seconds(args, 3, 5, 60, 20);
        local limit = math.max(20, math.min(2000, tonumber(args[4]) or 300));
        local ran, result = pcall(function ()
            return accessxi.searchhook.accessxi_missionrender_trace(seconds, limit);
        end);
        if (not ran) then
            log_line(('missionrender command failed error="%s"'):fmt(accessxi.escape_probe_log_text(result)));
            speak('Mission render trace failed. Error written.');
        else
            local status = 0;
            pcall(function ()
                status = tonumber(accessxi.searchhook.accessxi_missionrender_status()) or 0;
            end);
            log_line(('missionrender command seconds=%d limit=%d previous=%d status=0x%02X'):fmt(seconds, limit, tonumber(result) or 0, status));
            speak(('Mission render trace enabled for %d seconds. Arrow the bad mission rows now.'):fmt(seconds));
        end
        return true;
    elseif (has_command(args, 'searchtrace', 'seatrace', 'searchpacket')) then
        accessxi.search_result_packet_trace_until = tick() + 60000;
        accessxi.search_result_packet_trace_count = 0;
        accessxi.search_result_packet_trace_limit = tonumber(args[3]) or 220;
        accessxi.search_result_event_fields_logged = false;
        accessxi.last_search_result_packet_trace_key = '';
        speak('Search packet trace enabled for 60 seconds. Run sea all now.');
        log_line(('searchtrace command until=%d limit=%d'):fmt(tonumber(accessxi.search_result_packet_trace_until) or 0, tonumber(accessxi.search_result_packet_trace_limit) or 0));
        return true;
    elseif (has_command(args, 'searchdump', 'seadump', 'searchrows')) then
        accessxi.log_search_result_deep_dump('command');
        speak('Search result dump written.');
        return true;
    elseif (has_command(args, 'searchhook', 'seahook')) then
        local ok, dumps = accessxi.load_searchhook();
        if (ok) then
            speak(('Search hook enabled. Dump count %d. Run sea now.'):fmt(tonumber(dumps) or 0));
        else
            speak('Search hook failed. Error written.');
        end
        return true;
    elseif (has_command(args, 'searchixffwatch', 'seaixffwatch')) then
        accessxi.search_result_ixff_watch_until = tick() + 45000;
        log_line(('searchixff watch enabled until=%d'):fmt(tonumber(accessxi.search_result_ixff_watch_until) or 0));
        speak('Search IXFF watch enabled. Run sea all now.');
        return true;
    elseif (has_command(args, 'searchixff', 'seaixff')) then
        local ran, hits = pcall(function ()
            return accessxi.log_live_ixff_scan('command');
        end);
        if (not ran) then
            log_line(('searchixff error="%s"'):fmt(accessxi.escape_probe_log_text(hits)));
            speak('Search IXFF scan failed. Error written.');
        else
            speak(('Search IXFF scan written. %d hits.'):fmt(tonumber(hits) or 0));
        end
        return true;
    elseif (has_command(args, 'searchmem', 'seamem')) then
        local ran, ok, decoded_count, candidates = pcall(function ()
            return accessxi.search_result_scan_memory_packets('command');
        end);
        if (not ran) then
            log_line(('searchmem error="%s"'):fmt(accessxi.escape_probe_log_text(ok)));
            speak('Search memory scan failed. Error written.');
        elseif (ok) then
            speak(('Search memory decoded. %d candidates.'):fmt(tonumber(candidates) or 0));
        else
            speak(('Search memory scan written. No decoded rows. %d candidates.'):fmt(tonumber(candidates) or 0));
        end
        return true;
    elseif (has_command(args, 'currencyprobe', 'currencydump')) then
        local deep = (#args >= 3 and args[3]:any('deep', 'text', 'graph'));
        local now = tick();
        accessxi.currency_probe_until = now + 10000;
        accessxi.currency_text_probe_until = deep and (now + 10000) or 0;
        accessxi.last_currency_menu_probe_key = '';
        accessxi.last_currency_candidate_probe_key = '';
        accessxi.last_currency_text_graph_probe_key = '';
        local text = deep and 'Currency deep probe enabled for 10 seconds.' or 'Currency probe enabled for 10 seconds.';
        speak(text);
        accessxi.log_currency_packet_cache('currencyprobe-command', true);
        log_line(('currencyprobe command deep=%s until=%d'):fmt(tostring(deep), tonumber(accessxi.currency_probe_until) or 0));
        return true;
    elseif (has_command(args, 'mogdoorprobe', 'doorprobe')) then
        accessxi.mog_door_probe_until = tick() + 20000;
        accessxi.last_mog_door_probe_key = '';
        accessxi.last_mog_door_blank_signal_key = '';
        speak('Mog door probe enabled for 20 seconds.');
        log_line(('mogdoorprobe command until=%d'):fmt(tonumber(accessxi.mog_door_probe_until) or 0));
        return true;
    elseif (has_command(args, 'mogdoortrace', 'doortrace')) then
        accessxi.mog_door_packet_trace_until = tick() + ((tonumber(args[3]) or 45) * 1000);
        accessxi.mog_door_packet_trace_count = 0;
        accessxi.mog_door_packet_trace_limit = tonumber(args[4]) or 180;
        speak('Mog door packet trace enabled. Open the door menu, select an area, arrow, then escape.');
        log_line(('mogdoortrace command until=%d limit=%d'):fmt(
            tonumber(accessxi.mog_door_packet_trace_until) or 0,
            tonumber(accessxi.mog_door_packet_trace_limit) or 0));
        return true;
    elseif (has_command(args, 'postprobe', 'mogpostprobe', 'deliveryprobe')) then
        accessxi.mogpost_probe_until = tick() + 15000;
        accessxi.last_mogpost_menu_probe_key = '';
        accessxi.last_mogpost_receive_rows_probe_key = '';
        accessxi.last_mogpost_receive_selected_probe_key = '';
        speak('Delivery Box receive probe enabled for 15 seconds.');
        log_line(('mogpost probe command until=%d'):fmt(tonumber(accessxi.mogpost_probe_until) or 0));
        return true;
    elseif (has_command(args, 'deliverytrace', 'posttrace', 'pbxtrace')) then
        accessxi.delivery_box_packet_trace_until = tick() + 60000;
        accessxi.delivery_box_packet_trace_count = 0;
        accessxi.delivery_box_packet_trace_limit = tonumber(args[3]) or 120;
        accessxi.delivery_box_packet_trace_key = '';
        speak('Delivery Box packet trace enabled for 60 seconds. Open Receive now.');
        log_line(('deliverytrace command until=%d limit=%d'):fmt(
            tonumber(accessxi.delivery_box_packet_trace_until) or 0,
            tonumber(accessxi.delivery_box_packet_trace_limit) or 0));
        return true;
    elseif (has_command(args, 'meritprobe', 'meritnative')) then
        accessxi.merit_option_probe_until = tick() + 20000;
        accessxi.last_merit_option_native_probe_key = '';
        speak('Merit native option probe enabled for 20 seconds.');
        log_line(('merit option probe command until=%d'):fmt(tonumber(accessxi.merit_option_probe_until) or 0));
        return true;
    elseif (has_command(args, 'meritstate', 'meritvalueprobe', 'meritvalues')) then
        accessxi.merit_state_probe_until = tick() + 20000;
        accessxi.last_merit_state_probe_key = '';
        speak('Merit state probe enabled for 20 seconds.');
        log_line(('merit state probe command until=%d'):fmt(tonumber(accessxi.merit_state_probe_until) or 0));
        return true;
    elseif (has_command(args, 'meritcatshape', 'meritshape', 'meritcatstate')) then
        accessxi.meritcat_shape_probe_until = tick() + 30000;
        accessxi.last_meritcat_shape_probe_key = '';
        accessxi.meritcat_shape_probe_poll_key = 0;
        accessxi.meritcat_shape_probe_poll_tick = 0;
        speak('Merit category shape probe enabled for 30 seconds.');
        log_line(('meritcat shape probe command until=%d'):fmt(tonumber(accessxi.meritcat_shape_probe_until) or 0));
        return true;
    elseif (has_command(args, 'sortynprobe', 'meritconfirmprobe')) then
        accessxi.sortyn_probe_until = tick() + 15000;
        accessxi.last_sortyn_probe_key = '';
        speak('Merit confirmation probe enabled for 15 seconds.');
        log_line(('sortynprobe command until=%d'):fmt(tonumber(accessxi.sortyn_probe_until) or 0));
        return true;
    elseif (has_command(args, 'meritpacket', 'meritranks', 'meritcosts')) then
        accessxi.restore_merit_packet_cache_if_needed();
        local count = accessxi.table_count(accessxi.merit_packet_entries or {});
        accessxi.merit_packet_trace_until = tick() + 60000;
        accessxi.merit_packet_trace_key = '';
        local misc_text = '';
        if ((tonumber(accessxi.merit_misc_tick) or 0) > 0) then
            misc_text = (' Current merit points %d of %d.'):fmt(
                tonumber(accessxi.merit_misc_merit_points) or 0,
                tonumber(accessxi.merit_misc_max_merit_points) or 0);
        end
        local text = count > 0 and ('Merit packet has %d rank entries.%s Merit packet trace enabled for 60 seconds.'):fmt(count, misc_text) or ('No merit rank entries cached yet.%s Merit packet trace enabled for 60 seconds.'):fmt(misc_text);
        speak(text);
        log_line(('meritpacket command count=%d age=%d player="%s" miscAge=%d merits=%d max=%d limit=%d traceUntil=%d preview="%s"'):fmt(
            count,
            math.max(0, tick() - (tonumber(accessxi.merit_packet_tick) or 0)),
            accessxi.current_player_name(),
            math.max(0, tick() - (tonumber(accessxi.merit_misc_tick) or 0)),
            tonumber(accessxi.merit_misc_merit_points) or -1,
            tonumber(accessxi.merit_misc_max_merit_points) or -1,
            tonumber(accessxi.merit_misc_limit_points) or -1,
            tonumber(accessxi.merit_packet_trace_until) or 0,
            accessxi.escape_probe_log_text(accessxi.merit_packet_preview(accessxi.merit_packet_entries or {}, 80))));
        return true;
    elseif (has_command(args, 'jobpoints', 'jppacket', 'jpranks', 'jpcosts')) then
        accessxi.load_job_points_resource();
        local count = accessxi.table_count(accessxi.job_point_packet_entries or {});
        local misc_count = accessxi.table_count(accessxi.job_point_misc_jobs or {});
        accessxi.job_point_packet_trace_until = tick() + 60000;
        accessxi.job_point_packet_trace_key = '';
        local current_job = 0;
        local player = safe_call(function () return AshitaCore:GetMemoryManager():GetPlayer(); end, nil);
        if (player ~= nil) then
            current_job = tonumber(safe_call(function () return player:GetMainJob(); end, 0)) or 0;
        end
        local current_text = '';
        if (current_job > 0) then
            local state = accessxi.job_point_job_state_text(current_job);
            if (state ~= '') then
                current_text = (' %s.'):fmt(state);
            end
        end
        local text = count > 0 and ('Job point packet has %d rank entries.%s Job point packet trace enabled for 60 seconds.'):fmt(count, current_text) or ('No job point rank entries cached yet.%s Job point packet trace enabled for 60 seconds.'):fmt(current_text);
        speak(text);
        log_line(('jobpoint command entries=%d miscJobs=%d access=%d currentJob=%d packetAge=%d miscAge=%d traceUntil=%d preview="%s"'):fmt(
            count,
            misc_count,
            tonumber(accessxi.job_point_misc_access) or -1,
            current_job,
            math.max(0, tick() - (tonumber(accessxi.job_point_packet_tick) or 0)),
            math.max(0, tick() - (tonumber(accessxi.job_point_misc_tick) or 0)),
            tonumber(accessxi.job_point_packet_trace_until) or 0,
            accessxi.escape_probe_log_text(accessxi.job_point_packet_preview(accessxi.job_point_packet_entries or {}, 80))));
        return true;
    elseif (has_command(args, 'currencyorder', 'currencyrows')) then
        local now = tick();
        accessxi.currency_order_probe_until = now + 90000;
        accessxi.last_currency_order_probe_key = '';
        accessxi.last_currency_native_record_key = '';
        accessxi.last_currency_compound_probe_key = '';
        accessxi.last_currency_shape_probe_key = '';
        accessxi.last_currency_known_label_probe_key = '';
        accessxi.last_currency_id_probe_key = '';
        accessxi.last_currency_idproof_probe_key = '';
        accessxi.last_currency_visible_rows_probe_key = '';
        accessxi.last_currency_rejected_label_key = '';
        speak('Currency order probe enabled for 90 seconds.');
        accessxi.log_currency_packet_cache('currencyorder-command', true);
        log_line(('currencyorder command until=%d'):fmt(tonumber(accessxi.currency_order_probe_until) or 0));
        return true;
    elseif (has_command(args, 'currencyres', 'currencyresources')) then
        speak('Currency resource probe written.');
        accessxi.log_currency_resource_manager_probe();
        return true;
    elseif (has_command(args, 'currencystrings', 'currencystring')) then
        local needle = command_tail(args, 3);
        local max_index = 1024;
        local last_word = tostring(args[#args] or '');
        if (tonumber(last_word) ~= nil) then
            max_index = tonumber(last_word) or max_index;
            local parts = T{};
            for i = 3, #args - 1 do
                parts:append(args[i]);
            end
            needle = parts:concat(' '):trim();
        end
        local hits = accessxi.log_currency_resource_string_search(needle, max_index);
        speak(('Currency string search written. %d hits.'):fmt(tonumber(hits) or 0));
        return true;
    elseif (has_command(args, 'currencyrange', 'currencybank', 'currencydmsg')) then
        local start_index = tonumber(args[3]) or 0;
        local end_index = tonumber(args[4]) or start_index;
        local rows = accessxi.log_currency_native_string_range(start_index, end_index);
        speak(('Currency string range written. %d rows.'):fmt(tonumber(rows) or 0));
        return true;
    elseif (has_command(args, 'currencydisplay', 'currencyhelp', 'currencyfields')) then
        local page = 1;
        if (#args >= 3 and tostring(args[3] or ''):contains('2', true)) then
            page = 2;
        end
        accessxi.log_currency_packet_cache('currencydisplay-command', true);
        accessxi.log_currency_display_order_with_help(page);
        speak(('Currency display page %d written.'):fmt(page));
        return true;
    elseif (has_command(args, 'say', 'speechtest', 'prismtest')) then
        local text = command_tail(args, 3);
        if (text == '') then
            text = 'Access XI speech test.';
        end
        local result = speak(text);
        log_line(('speech test result="%s" text="%s"'):fmt(
            accessxi.escape_probe_log_text(result or ''),
            accessxi.escape_probe_log_text(text)));
        return true;
    elseif (has_command(args, 'checkprobe', 'probecheck')) then
        local text = accessxi.manual_check_probe_field(#args >= 3 and args[3] or 'target');
        speak(text);
        log_line('checkprobe manual ' .. text);
        return true;
    elseif (has_command(args, 'equipprobe', 'equipmentprobe')) then
        if (type(ctx.enable_equipment_probe) == 'function') then
            ctx.enable_equipment_probe('command');
        end
        return true;
    elseif (has_command(args, 'partyprobe', 'partylabel', 'partylabels', 'alarmprobe', 'alarmlabel', 'languageprobe', 'partylanguageprobe')) then
        accessxi.enable_party_label_probe('command');
        return true;
    elseif (has_command(args, 'chattrace', 'logtrace')) then
        accessxi.chat_log_native_trace_until = tick() + 30000;
        accessxi.chat_log_native_trace_last_tick = 0;
        accessxi.chat_log_native_trace_last_key = '';
        accessxi.chat_log_native_trace_sequence = 0;
        accessxi.chat_log_trace_poll_last_tick = 0;
        accessxi.chat_log_probe_until = accessxi.chat_log_native_trace_until;
        accessxi.chat_log_probe_last_tick = 0;
        accessxi.chat_log_probe_last_log = '';
        log_line('chattrace enabled for 30 seconds');
        speak('Chat trace enabled for 30 seconds.');
        return true;
    elseif (has_command(args, 'chatprobe', 'logprobe')) then
        if (#args >= 3 and args[3]:any('once', 'dump', 'now')) then
            accessxi.log_chat_log_selection_probe('command-once', true);
            speak('Chat log probe snapshot written.');
        else
            accessxi.enable_chat_log_probe('command');
        end
        return true;
    elseif (has_command(args, 'chatfind', 'logfind')) then
        local terms = command_tail(args, 3);
        if (accessxi.survival_guide_text(terms) == '') then
            speak('Chat memory scan needs exact text.');
            log_line('chatfind command skipped no exact text');
        else
            accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
            local seq = accessxi.menu_dump_sequence;
            local hits = accessxi.log_survival_guide_memory_scan(seq, 'chatfind', terms);
            speak(('Chat memory scan %d written. %d hits.'):fmt(seq, tonumber(hits) or 0));
        end
        return true;
    elseif (has_command(args, 'chatbufscan', 'logbufscan')) then
        accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
        local seq = accessxi.menu_dump_sequence;
        local hits = accessxi.log_chat_log_buffer_scan(seq, 'command', command_tail(args, 3));
        speak(('Chat buffer scan %d written. %d hits.'):fmt(seq, tonumber(hits) or 0));
        return true;
    elseif (has_command(args, 'chatptrscan', 'logptrscan')) then
        local raw_address = accessxi.survival_guide_text(args[3] or ''):gsub('^0x', '');
        local address = tonumber(raw_address, 16) or tonumber(raw_address) or 0;
        accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
        local seq = accessxi.menu_dump_sequence;
        local hits = accessxi.log_chat_log_pointer_scan(seq, 'command', address);
        speak(('Chat pointer scan %d written. %d hits.'):fmt(seq, tonumber(hits) or 0));
        return true;
    elseif (has_command(args, 'chatrecscan', 'logrecscan')) then
        local raw_address = accessxi.survival_guide_text(args[3] or ''):gsub('^0x', '');
        local address = tonumber(raw_address, 16) or tonumber(raw_address) or 0;
        accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
        local seq = accessxi.menu_dump_sequence;
        local hits = accessxi.log_chat_log_record_scan(seq, 'command', address);
        speak(('Chat record scan %d written. %d hits.'):fmt(seq, tonumber(hits) or 0));
        return true;
    elseif (has_command(args, 'chatrowscan', 'logrowscan')) then
        local raw_address = accessxi.survival_guide_text(args[3] or ''):gsub('^0x', '');
        local address = tonumber(raw_address, 16) or tonumber(raw_address) or 0;
        accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
        local seq = accessxi.menu_dump_sequence;
        local hits = accessxi.log_chat_log_row_scan(seq, 'command', address);
        speak(('Chat row scan %d written. %d hits.'):fmt(seq, tonumber(hits) or 0));
        return true;
    elseif (has_command(args, 'chatownerscan', 'logownerscan', 'chatowner')) then
        local raw_address = accessxi.survival_guide_text(args[3] or ''):gsub('^0x', '');
        local address = tonumber(raw_address, 16) or tonumber(raw_address) or 0;
        accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
        local seq = accessxi.menu_dump_sequence;
        local hits = accessxi.log_chat_log_row_owner_scan(seq, 'command', address);
        speak(('Chat owner scan %d written. %d fields.'):fmt(seq, tonumber(hits) or 0));
        return true;
    elseif (has_command(args, 'houseprobe', 'viewhouseprobe', 'mogcontprobe')) then
        accessxi.enable_view_house_probe('command');
        speak('View House probe armed. Arrow the View House menu.');
        return true;
    elseif (has_command(args, 'bazaarprobe', 'setbazaarprobe')) then
        accessxi.enable_bazaar_probe('command');
        speak('Set Bazaar probe armed. Arrow the Set Bazaar menu.');
        return true;
    elseif (has_command(args, 'shopsellprobe', 'bazaarconfirmprobe')) then
        accessxi.enable_shopsell_probe('command');
        speak('Set Bazaar confirmation probe armed. Arrow Sell and Cancel.');
        return true;
    elseif (has_command(args, 'mcrprobe', 'macroprobe', 'macropaletteprobe')) then
        accessxi.enable_macro_palette_probe('command');
        speak('MacroPalette probe armed. Arrow the MacroPalette menu.');
        return true;
    elseif (has_command(args, 'sgscan', 'survivalguidescan')) then
        local terms = command_tail(args, 3);
        if (accessxi.survival_guide_text(terms) == '') then
            speak('Survival Guide memory scan needs exact text.');
            log_line('sgscan command skipped no exact text');
        else
            accessxi.menu_dump_sequence = (accessxi.menu_dump_sequence or 0) + 1;
            local seq = accessxi.menu_dump_sequence;
            local hits = accessxi.log_survival_guide_memory_scan(seq, 'command', terms);
            speak(('Survival Guide memory scan %d written. %d hits.'):fmt(seq, tonumber(hits) or 0));
        end
        return true;
    elseif (has_command(args, 'sgdeep', 'survivalguidedeep')) then
        if (type(ctx.dump_current_menu) == 'function') then
            ctx.dump_current_menu('deep command');
        end
        return true;
    elseif (has_command(args, 'menudump', 'dump')) then
        if (type(ctx.dump_current_menu) == 'function') then
            ctx.dump_current_menu('command');
        end
        return true;
    end

    return false;
end

return debug_commands;

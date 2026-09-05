-- Mission-level walkthrough census: plays every mission's reconciled steps
-- in order, carrying the zone the player would be in, and reports which
-- missions route END TO END and, for the rest, the first step that blocks
-- and why. Steps that are instructions by nature (note, wait, select) are not
-- counted against a mission.
--
--   luajit tools/test_mission_walkthrough.lua [module-filter] [--list]
--
-- Output: per-module totals, the overall total, and (with --list or a
-- filter) every mission with its first blocker.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;

-- Reuse the production-shaped context from the resolver regression.
WALKTHROUGH_EMBED = true;
local env = dofile((arg[0]:match('^(.*)[/\\]') or '.') .. '/test_mission_step_resolver.lua');
local resolver, make_ctx, zone_names, progression_destinations, progression_info, name_key =
    env.resolver, env.make_ctx, env.zone_names, env.progression_destinations, env.progression_info, env.name_key;
local env_zone_path = env.zone_path;

local filter = nil;
local list_all = false;
for _, a in ipairs(arg) do
    if (a == '--list') then list_all = true; else filter = a; end
end

local NON_POSITIONAL = { note = true, wait = true, select = true, ['choose'] = true };
local START_ZONE = {
    mission_san_doria = 230, mission_bastok = 234, mission_windurst = 238,
};
local lower_jeuno = 245;
for zone, name in pairs(zone_names) do
    if (name_key(name) == 'lower jeuno') then lower_jeuno = zone; end
end

local modules = {};
local p = io.popen('dir /b "' .. ADDON:gsub('/', '\\') .. '\\modules\\mission_quest_reconcile_mission_*.lua"');
for line in p:lines() do modules[#modules + 1] = (line:gsub('%.lua$', '')); end
p:close();
table.sort(modules);

local grand = { missions = 0, end_to_end = 0, partial = 0, none = 0, steps = 0, routable = 0 };
local blockers = {};
for _, mod in ipairs(modules) do
    local short = mod:gsub('mission_quest_reconcile_', '');
    if (filter == nil or short:find(filter, 1, true)) then
        local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. mod .. '.lua');
        if (ok and type(tbl) == 'table') then
            local dest_map = progression_destinations((mod:gsub('reconcile', 'progression')));
            local dest_fn = function (step_id) return dest_map[step_id] or 0; end
            local info_map = progression_info((mod:gsub('reconcile', 'progression')));
            local nation = short == 'mission_san_doria' and "San d'Oria" or short == 'mission_bastok' and 'Bastok' or short == 'mission_windurst' and 'Windurst' or nil;
            -- Steps that are instructions by nature never count against a
            -- mission: no place named at all, or an acquisition whose target
            -- is an item/key item rather than somewhere to walk. Steps whose
            -- progression action ships a catalogue, or names the Gate Guard
            -- role, are routed by production paths the resolver does not own.
            local function instruction_by_nature(step)
                local has_place = false;
                for _, v in ipairs(step.zones or {}) do if (v ~= '') then has_place = true; end end
                for _, v in ipairs(step.entities or {}) do if (v ~= '') then has_place = true; end end
                if (not has_place) then return true; end
                local rec = info_map[step.stable_step_id];
                if (rec ~= nil and not rec.kinds['npc'] and not rec.kinds['object'] and not rec.kinds['enemy']
                    and not rec.kinds['question-mark'] and not rec.kinds['area'] and not rec.kinds['zone']
                    and (rec.kinds['item'] or rec.kinds['key-item'])) then
                    return true;
                end
                return false;
            end
            local function production_handles(step)
                local rec = info_map[step.stable_step_id];
                if (rec ~= nil and rec.catalogue) then return true; end
                for _, v in ipairs(step.entities or {}) do
                    if (name_key(v):find('gate guard', 1, true)) then return true; end
                end
                return false;
            end
            local keys = {};
            for native_key, entry in pairs(tbl) do
                if (type(entry) == 'table' and type(entry.steps) == 'table') then keys[#keys + 1] = native_key; end
            end
            table.sort(keys, function (a, b)
                local na, nb = tonumber(a:match(':(%d+)$')), tonumber(b:match(':(%d+)$'));
                if (na and nb and na ~= nb) then return na < nb; end
                return a < b;
            end);
            local m = { missions = 0, end_to_end = 0, partial = 0, none = 0, steps = 0, routable = 0 };
            local lines = {};
            for _, native_key in ipairs(keys) do
                local steps = tbl[native_key].steps;
                local zone = START_ZONE[short] or lower_jeuno;
                local material, routable, first_block, partial_steps, first_partial = 0, 0, nil, 0, nil;
                for i, step in ipairs(steps) do
                    local action = name_key(step.action);
                    -- A CONFLICTED STEP IS A STEP. It used to be excluded here
                    -- as well as refused, so a mission could be called
                    -- end-to-end while a step both pages describe was silently
                    -- not counted. The resolver reads each page separately now.
                    if (type(step) == 'table' and not NON_POSITIONAL[action]
                        and step.optional_nonessential ~= true and step.route_recommendation ~= true
                        and not instruction_by_nature(step)) then
                        material = material + 1;
                        local ctx = make_ctx(zone, dest_fn, nation, native_key);
                        local prev_zone = zone;
                        local targets, info = resolver.resolve_step(steps, i, ctx);
                        if (#targets == 0 and production_handles(step)) then
                            targets = { { zone = zone } };
                        end
                        -- An acquisition whose every name is absent from the whole
                        -- catalogue is a shopping/drop instruction, not a place.
                        local ACQ = { obtain = true, trade = true, use = true, farm = true };
                        if (#targets == 0 and ((ACQ[action] and info.reason == resolver.REASONS.ENTITY_ABSENT) or info.modifier_only == true)) then
                            material = material - 1;
                            targets = nil;
                        end
                        if (targets == nil) then
                        elseif (#targets > 0) then
                            routable = routable + 1;
                            zone = tonumber(targets[1].zone) or zone;
                            local assumed = false;
                            if (targets[1].canonical_edge_id ~= nil) then
                                for _, e in ipairs(env_zone_path(prev_zone, targets[1].zone, targets[1].canonical_edge_id)) do
                                    if (e.assumed) then assumed = true; end
                                end
                            end
                            if (info.partial ~= nil or assumed) then
                                partial_steps = partial_steps + 1;
                                first_partial = first_partial or ('%s [%s] partial:%s'):format(step.stable_step_id:gsub('^mission:', ''), action, tostring(info.partial or 'availability-unknown'));
                            end
                        elseif (info.reason == resolver.REASONS.ALREADY_IN_ZONE) then
                            routable = routable + 1;   -- satisfied where the player stands
                        else
                            if (first_block == nil) then
                                first_block = ('%s [%s] %s: %s'):format(step.stable_step_id:gsub('^mission:', ''), action, tostring(info.reason), tostring(info.detail or ''));
                            end
                            blockers[tostring(info.reason)] = (blockers[tostring(info.reason)] or 0) + 1;
                            if (info.return_home_zone ~= nil) then blockers['(of which return-home shape)'] = (blockers['(of which return-home shape)'] or 0) + 1; end
                        end
                    end
                end
                m.missions = m.missions + 1; m.steps = m.steps + material; m.routable = m.routable + routable;
                local status;
                if (material == 0) then status = 'no-steps'; m.end_to_end = m.end_to_end + 1;
                elseif (first_block == nil and partial_steps == 0) then status = 'END-TO-END'; m.end_to_end = m.end_to_end + 1;
                elseif (first_block == nil) then status = 'partial'; m.partial = m.partial + 1; m.routed_partial = (m.routed_partial or 0) + 1;
                elseif (routable > 0) then status = 'partial'; m.partial = m.partial + 1;
                else status = 'none'; m.none = m.none + 1; end
                lines[#lines + 1] = ('  %-32s %-10s steps=%2d routable=%2d %s'):format(native_key, status, material, routable, first_block or first_partial or '');
            end
            print(('%-40s missions=%3d end-to-end=%3d partial=%3d (of which every step resolves but some only to a zone or a choice: %d) none=%3d  steps=%4d routable=%4d'):format(
                short, m.missions, m.end_to_end, m.partial, m.routed_partial or 0, m.none, m.steps, m.routable));
            if (list_all or filter ~= nil) then
                for _, l in ipairs(lines) do print(l); end
            end
            for k, v in pairs(m) do grand[k] = (grand[k] or 0) + v; end
        end
    end
end
print(('TOTAL missions=%d end-to-end=%d partial=%d (every step resolves, some only to a zone or a choice: %d) none=%d  steps=%d routable=%d'):format(
    grand.missions, grand.end_to_end, grand.partial, grand.routed_partial or 0, grand.none, grand.steps, grand.routable));
local bl = {}; for k, v in pairs(blockers) do bl[#bl + 1] = k .. '=' .. v; end table.sort(bl);
print('blocking reasons: ' .. table.concat(bl, ' '));

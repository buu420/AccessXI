-- Focused regression for the ??? placeholder in modules/mission_quest_step_resolver.lua.
--
-- THE DEFECT THIS EXISTS FOR.
--
-- 2026-09-19 13:52:42, the reporter was on the level-55 limit break quest "In
-- Defiant Challenge" (quest:jeuno:128) in Crawler's Nest, and the objective row
-- spoke:
--
--   "In Defiant Challenge. Active quest. Jeuno. Objective choice: YOU MUST
--    CLICK ALL THREE??? to receive the Exoray Mold Destination: West Ronfaure
--    ??? in West Ronfaure..."
--
-- and at 13:53:14 it committed: `nav ingress selected target="West Ronfaure
-- entrance" zone=100`. The player was sent to a starting-area forest for a
-- level 55 quest step that happens inside Crawler's Nest.
--
-- WHY. The shipped compact action already says this is not an identity:
--
--   quest:jeuno:128:step-014:claim-01
--     action = "examine", relationship = "examine-to-obtain",
--     target = "???", target_key = "", target_kind = "question-mark",
--     objects = { "???" }, zones = {}, grid_coordinates = {}
--
-- `target_key = ""` is the generator refusing to mint a key. But the resolver
-- treated target_kind as corroboration only, so `???` fell through to the
-- ordinary name lookup -- and data/ffxi-nav-destinations.tsv holds 1,267 rows
-- named exactly "???", spread across most zones in the game. With no zone to
-- narrow them, every one of them was a candidate.
--
-- The kind filter already knew about this trap for one verb: `kind_allowed`
-- keeps `trade` npc-only "so 'trade to ???' cannot admit 1,267 object rows".
-- `examine` admits objects, so this step walked straight through it.
--
-- WHAT THE FIX MAY NOT DO. It may not invent a zone. Crawler's Nest is named by
-- the PRECEDING step (order 13), not by this one, and a runtime registry of
-- zones inherited from neighbouring steps was built for this corpus once,
-- measured worthless and deleted. So a zone-less ??? must refuse and let the
-- guide sentence be spoken verbatim -- the player still hears "YOU MUST CLICK
-- ALL THREE ??? to receive the Exoray Mold", which is the information a sighted
-- player reads off the page. A ??? that DOES carry a zone must still route.
--
--   luajit tools/test_question_mark_target_resolution.lua
--   ACCESSXI_ADDON=<tree> ACCESSXI_RESOLVER=<file> luajit tools/...
--
-- Exit 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON')
    or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
-- The module under test defaults to the REPO copy; the DATA always comes from
-- the installed tree. Editing the resolver must not require deploying it.
local here = (arg[0]:match('^(.*)[/\\]') or '.');
local RESOLVER = os.getenv('ACCESSXI_RESOLVER')
    or (here .. '/../ashita/addons/accessxi_reader/modules/mission_quest_step_resolver.lua');

accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end;
    t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;

local resolver = dofile(RESOLVER);

local failures, passes = 0, 0;
local function claim(ok, text)
    if (ok) then passes = passes + 1;
    else failures = failures + 1; print('  FAIL ' .. text); end
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
-- Mirrors source_name_key in mission_quest_navigation.lua.
local function name_key(s)
    local key = trim(s):lower();
    key = key:gsub('%s*([:,])%s*', '%1');
    key = key:gsub('%s+', ' ');
    return key;
end
local function split_tsv(line)
    local parts = {};
    for part in (line .. '\t'):gmatch('([^\t]*)\t') do parts[#parts + 1] = part; end
    return parts;
end

-- Copied verbatim from tools/test_mission_step_resolver.lua so the two
-- harnesses cannot disagree about which kinds a verb admits.
local function kind_allowed(action, kind)
    action, kind = name_key(action), name_key(kind);
    if (action == 'fight') then return kind == 'enemy' or kind == 'nm' or kind == 'live-nm'; end
    if (action == 'talk') then return kind == 'npc' or kind == 'object'; end
    if (action == 'trade') then return kind == 'npc'; end
    if (action == 'examine' or action == 'use') then return kind == 'npc' or kind == 'object' or kind == 'area'; end
    if (action == 'obtain') then return kind == 'enemy' or kind == 'nm' or kind == 'npc' or kind == 'object'; end
    return kind == 'npc' or kind == 'object' or kind == 'enemy' or kind == 'nm';
end

-- REAL catalogue ------------------------------------------------------------
local points_by_entity, points_by_zone_entity = {}, {};
local zone_ids_by_name, zone_names = {}, {};
local question_mark_rows, question_mark_zones = 0, {};
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-destinations.tsv', 'r'));
    for line in f:lines() do
        if (line ~= '' and line:sub(1, 1) ~= '#') then
            local p = split_tsv(line);
            local zone = tonumber(p[1]);
            local label = trim(p[2]);
            if (zone and zone > 0 and label ~= '') then
                local point = {
                    zone = zone, name = label,
                    x = tonumber(p[3]), z = tonumber(p[4]), y = tonumber(p[5]),
                    kind = trim(p[6]), source = trim(p[7]),
                    destination_id = trim(p[10] or ''),
                };
                local key = name_key(label);
                points_by_entity[key] = points_by_entity[key] or {};
                table.insert(points_by_entity[key], point);
                local zkey = zone .. '\t' .. key;
                points_by_zone_entity[zkey] = points_by_zone_entity[zkey] or {};
                table.insert(points_by_zone_entity[zkey], point);
                if (key == '???') then
                    question_mark_rows = question_mark_rows + 1;
                    question_mark_zones[zone] = true;
                end
            end
        end
    end
    f:close();
end
do
    local f = assert(io.open(ADDON .. '/data/ffxi-nav-zoneline-graph.tsv', 'r'));
    local header = nil;
    for line in f:lines() do
        if (line ~= '' and line:sub(1, 1) ~= '#') then
            local p = split_tsv(line);
            if (header == nil) then header = p;
            else
                local e = {};
                for i, k in ipairs(header) do e[k] = p[i]; end
                for _, side in ipairs({ 'from', 'to' }) do
                    local id = tonumber(e[side .. '_zone']);
                    local nm = trim(e[side .. '_name'] or '');
                    if (id and id > 0 and nm ~= '') then
                        zone_names[id] = nm;
                        local k = name_key(nm);
                        zone_ids_by_name[k] = zone_ids_by_name[k] or {};
                        zone_ids_by_name[k][id] = true;
                    end
                end
            end
        end
    end
    f:close();
end

local qm_zone_count = 0;
for _ in pairs(question_mark_zones) do qm_zone_count = qm_zone_count + 1; end
claim(question_mark_rows > 1000 and qm_zone_count > 50,
    ('precondition: the catalogue still holds a world of ??? rows (got %d rows in %d zones)')
        :format(question_mark_rows, qm_zone_count));

-- REAL guide + compact actions ---------------------------------------------
local function load_objective(reconcile_module, progression_module, native_key)
    local recon = dofile(ADDON .. '/modules/' .. reconcile_module .. '.lua');
    local steps = assert(recon[native_key], native_key .. ' is missing from ' .. reconcile_module).steps;
    local prog = dofile(ADDON .. '/modules/' .. progression_module .. '.lua');
    local root = (type(prog.objectives) == 'table' and prog.objectives) or prog;
    local actions = assert(root[native_key], native_key .. ' is missing from ' .. progression_module)
        .progression_actions;
    local by_step = {};
    for _, a in ipairs(actions) do
        local id = trim(a.step_id);
        by_step[id] = by_step[id] or {};
        table.insert(by_step[id], a);
    end
    return steps, by_step;
end

local function step_index(steps, stable_step_id)
    for i, s in ipairs(steps) do
        if (trim(s.stable_step_id) == stable_step_id) then return i; end
    end
end

local function make_ctx(by_step, player_zone)
    return {
        objective = { key = '' },
        player_zone = player_zone,
        name_key = name_key,
        zone_ids_for_name = function (v) return zone_ids_by_name[name_key(v)]; end,
        zone_id_for_name = function (v)
            local ids = zone_ids_by_name[name_key(v)];
            if (type(ids) ~= 'table') then return 0; end
            local found, count = 0, 0;
            for zone in pairs(ids) do found = zone; count = count + 1; end
            return count == 1 and found or 0;
        end,
        points_for_zone_entity = function (zone, key) return points_by_zone_entity[zone .. '\t' .. key]; end,
        points_for_entity = function (key) return points_by_entity[key]; end,
        effective_kind = function (p) return p.kind; end,
        kind_allowed = kind_allowed,
        primary_actions_for_step = function (step_id)
            local src = by_step[trim(step_id)] or {};
            local out = {};
            for i = 1, #src do out[i] = src[i]; end
            return out;
        end,
        zone_name = function (zone) return zone_names[tonumber(zone) or 0] or ''; end,
        destination_zone_for_step = function () return 0; end,
        source_readings = function () return {}; end,
    };
end

local function target_zones(targets)
    local seen, list = {}, {};
    for _, t in ipairs(type(targets) == 'table' and targets or {}) do
        local zone = tonumber(t.zone) or tonumber(t.point ~= nil and t.point.zone or 0) or 0;
        if (zone > 0 and not seen[zone]) then seen[zone] = true; list[#list + 1] = zone; end
    end
    table.sort(list);
    return list;
end

local function describe(targets)
    local zones = target_zones(targets);
    local names = {};
    for i, z in ipairs(zones) do names[i] = z .. '(' .. (zone_names[z] or '?') .. ')'; end
    return ('%d target(s) in zones [%s]'):format(#(targets or {}), table.concat(names, ' '));
end

-- CASE A: the reported defect ----------------------------------------------
do
    local steps, by_step = load_objective(
        'mission_quest_reconcile_quest_jeuno',
        'mission_quest_progression_quest_jeuno',
        'quest:jeuno:128');
    local index = assert(step_index(steps, 'quest:jeuno:128:step-014'),
        'the shipped In Defiant Challenge step-014 is gone');
    local step = steps[index];

    claim(#(step.zones or {}) == 0,
        'precondition: shipped step-014 still names no zone');
    local action = (by_step['quest:jeuno:128:step-014'] or {})[1];
    claim(type(action) == 'table'
            and trim(action.target) == '???'
            and trim(action.target_key) == ''
            and trim(action.target_kind) == 'question-mark',
        'precondition: shipped claim-01 is still an unkeyed question-mark examine');

    -- 100 = West Ronfaure, the zone the live log actually committed to.
    local targets, info = resolver.resolve_step(steps, index, make_ctx(by_step, 197));
    local zones = target_zones(targets);
    claim(#zones == 0,
        'a zone-less ??? yields no destination at all -- got ' .. describe(targets));
    for _, zone in ipairs(zones) do
        claim(false, ('zone-less ??? must not reach zone %d (%s)')
            :format(zone, zone_names[zone] or '?'));
    end
    claim(trim(type(info) == 'table' and info.reason or '') ~= '',
        'the refusal names a reason so the caller can speak the guide sentence');

    -- The information must survive the refusal.
    local instruction = resolver.guide_instruction(step);
    claim(tostring(instruction):find('Exoray Mold', 1, true) ~= nil,
        'the guide sentence naming the Exoray Mold is still available to speak (got "'
            .. tostring(instruction) .. '")');
end

-- CASE B: a ??? that DOES state its zones must still be found there.
--
-- Asserted at the sweep the admission decision lives in rather than through
-- resolve_step: producing a cross-zone ROUTE additionally needs the road
-- context (zone_path, incoming_edges, edge_rank, entry_edge_candidates,
-- destination_ingress) that tools/test_mission_step_resolver.lua supplies. A
-- harness that half-supplies a road proves nothing about routing, so routing
-- claims stay in that file; what belongs here is which rows may be admitted.
do
    local steps, by_step = load_objective(
        'mission_quest_reconcile_mission_bastok',
        'mission_quest_progression_mission_bastok',
        'mission:Bastok:22');
    local index = assert(step_index(steps, 'mission:Bastok:22:step-008'),
        'the shipped Bastok 22 step-008 is gone');
    local step = steps[index];
    local action = (by_step['mission:Bastok:22:step-008'] or {})[1];
    claim(type(action) == 'table' and trim(action.target_kind) == 'question-mark'
            and #(action.zones or {}) >= 1,
        'precondition: Bastok 22 step-008 is a question-mark that names its zones');

    local ctx = make_ctx(by_step, 174);
    local stated = resolver.stated_placeholder_zones(step, ctx, {});
    claim(stated[174] == true,
        'the stated zones of a question-mark include the Kuftal Tunnel it names');

    local keys = { ['???'] = '???' };
    local inside = resolver.entity_rows_in_zones({ [174] = true }, keys, 'examine', ctx, stated);
    claim(#inside > 0,
        ('a stated-zone ??? is still found inside it (got %d rows)'):format(#inside));
    for _, row in ipairs(inside) do
        claim(tonumber(row.zone) == 174, 'every admitted row is in the stated zone');
    end

    -- A zone the step never stated stays closed even when asked for directly.
    local elsewhere = resolver.entity_rows_in_zones({ [100] = true }, keys, 'examine', ctx, stated);
    claim(#elsewhere == 0,
        ('an unstated zone admits no ??? (got %d rows in West Ronfaure)'):format(#elsewhere));

    -- And with nothing stated at all, no zone opens.
    local none = resolver.entity_rows_in_zones({ [174] = true }, keys, 'examine', ctx, {});
    claim(#none == 0,
        ('with no stated zone a ??? is admitted nowhere (got %d)'):format(#none));
end

-- CASE C: the control. An ordinary named entity must be completely unaffected,
-- including when no placeholder zones are supplied at all.
do
    local ctx = make_ctx({}, 243);
    local maat = resolver.entity_rows_in_zones(
        { [243] = true }, { ['maat'] = 'Maat' }, 'talk', ctx, nil);
    claim(#maat > 0,
        ('control: a named NPC still resolves with no placeholder zones (got %d rows)')
            :format(#maat));
    local named = false;
    for _, row in ipairs(maat) do
        if (name_key(row.name) == 'maat') then named = true; end
    end
    claim(named, 'control: the admitted rows really are Maat');

    local global_maat = resolver.collect_entity_rows(
        { ['maat'] = 'Maat' }, 'talk', ctx);
    claim(#global_maat > 0,
        ('control: the global sweep still finds named entities (got %d)'):format(#global_maat));
end

-- CASE D: no verb may admit a worldwide ??? sweep. The kind filter already
-- protected `trade`; the reported defect came in through `examine`.
do
    local ctx = make_ctx({}, 197);
    for _, verb in ipairs({ 'examine', 'use', 'talk', 'obtain', 'trade', 'fight' }) do
        local rows, absent, wrong_kind =
            resolver.collect_entity_rows({ ['???'] = '???' }, verb, ctx);
        claim(#rows == 0,
            ('"%s ???" admits no global candidates (got %d)'):format(verb, #rows));
        -- A ??? is unidentifiable, not missing. Reporting it absent would make
        -- the caller say the entity does not exist, which is a different lie.
        claim(#absent == 0 and #wrong_kind == 0,
            ('"%s ???" is not reported as an absent entity'):format(verb));
    end
end

print(('%d passed, %d failed'):format(passes, failures));
os.exit(failures == 0 and 0 or 1);

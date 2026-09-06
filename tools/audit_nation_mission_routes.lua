-- Inventory audit of destination and INGRESS coverage for the three nation
-- mission storylines (San d'Oria, Bastok, Windurst).
--
-- WHY THIS IS NOT ANOTHER PASS/FAIL HARNESS.
--
-- tools/test_mission_walkthrough.lua answers "did the step resolve?". That was
-- green for Windurst mission 1 while the player could not reach the Magical
-- Gizmo. A resolved target and a reachable target are different claims, and
-- only the first was ever counted.
--
-- WHY THE FIRST REVISION OF THIS FILE MISSED THE REPORTED STEP.
--
-- It inherited the walkthrough's material filter, which drops a step whose
-- `entities` list is empty. mission:Windurst:1:step-017 is exactly that step:
-- both source pages name "Gate: Magical Gizmo", the reconciler marked
-- comparison=conflict on target_identity, and `entities` came out EMPTY. The
-- name survives only on the primary compact progression action
-- (target = "Gate: Magical Gizmo", objects = {Gate: Magical Gizmo}).
--
-- So the audit that was meant to find the gap silently filtered the gap. A step
-- is positional here if the reconciled step OR its primary compact action names
-- somewhere to stand, and note/instruction steps are counted and reported in
-- their own bucket -- never dropped without a number against them.
--
-- Target classes:
--   refused          the resolver names a reason and no target comes back
--   zone-substitute  source == 'zone-travel' or entity_choice_stage == 'zone'
--                    (the STEP's own field, not a guess from the name)
--   precise          a physical point of its own
--
-- WHAT THIS AUDIT CANNOT SAY. Distance is not reachability, and this file
-- probes no navmesh. Ingress findings are candidates for native verification;
-- --export-cases emits exactly the cases a native probe should run.
--
--   luajit tools/audit_nation_mission_routes.lua
--   luajit tools/audit_nation_mission_routes.lua --shape
--   luajit tools/audit_nation_mission_routes.lua --export-cases=<path.tsv>
--
-- ACCESSXI_ADDON selects the tree; defaults to the installed addon.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

local shape_only, export_path = false, nil;
for _, a in ipairs(arg or {}) do
    if (a == '--shape') then shape_only = true; end
    local p = tostring(a):match('^%-%-export%-cases=(.+)$');
    if (p) then export_path = p; end
end

WALKTHROUGH_EMBED = true;
local here = (arg[0]:match('^(.*)[/\\]') or '.');
local env = dofile(here .. '/test_mission_step_resolver.lua');
local resolver, make_ctx, zone_names, name_key =
    env.resolver, env.make_ctx, env.zone_names, env.name_key;
local progression_destinations = env.progression_destinations;
local incoming_edges, zone_path = env.incoming_edges, env.zone_path;

local NATIONS = {
    { module = 'mission_quest_reconcile_mission_san_doria', nation = "San d'Oria", start_zone = 230 },
    { module = 'mission_quest_reconcile_mission_bastok',    nation = 'Bastok',     start_zone = 234 },
    { module = 'mission_quest_reconcile_mission_windurst',  nation = 'Windurst',   start_zone = 238 },
};

-- ctx.zone_ids_for_name is built from the destination catalogue alone and
-- returns EMPTY for a zone the catalogue never names as a destination --
-- "Inner Horutoto Ruins" among them. Falling back to the player's zone then
-- looked the target up in the wrong zone and found nothing, which is why the
-- first export carried no Gate rows at all. The zone-line graph names every
-- zone it can reach, so resolve against that too.
local zone_ids_by_graph_name = {};
for id, nm in pairs(zone_names) do
    local k = name_key(nm);
    if (k ~= '') then
        zone_ids_by_graph_name[k] = zone_ids_by_graph_name[k] or {};
        table.insert(zone_ids_by_graph_name[k], id);
    end
end

local function zname(zone)
    zone = tonumber(zone) or 0;
    return (zone_names[zone] or ('zone-' .. tostring(zone))) .. ('(%d)'):format(zone);
end
local function num(v) return tonumber(v); end
local function xyz(t)
    local x, z, y = num(t.x), num(t.z), num(t.y);
    if (x == nil or z == nil) then return nil; end
    return x, z, (y or 0);
end
local function edge_xyz(e)
    local x, z, y = num(e.to_x), num(e.to_z), num(e.to_y);
    if (x == nil or z == nil) then return nil; end
    return x, z, (y or 0);
end
local function flat(x1, z1, x2, z2)
    local dx, dz = x1 - x2, z1 - z2;
    return math.sqrt(dx * dx + dz * dz);
end

-- EVERY compact action per step, ordered by action_order. Reading only the
-- lowest-order action was a coverage hole of its own: a multi-action step names
-- its later targets nowhere else, so those candidates never reached the export
-- and could never be natively verified. [1] is still the primary.
local function compact_actions(module_name)
    local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. module_name .. '.lua');
    local map = {};
    if (ok and type(tbl) == 'table') then
        local root = type(tbl.objectives) == 'table' and tbl.objectives or tbl;
        for _, entry in pairs(root) do
            for _, a in ipairs(type(entry) == 'table' and entry.progression_actions or {}) do
                local id = tostring(a.step_id or '');
                if (id ~= '') then
                    map[id] = map[id] or {};
                    table.insert(map[id], a);
                end
            end
        end
    end
    for _, list in pairs(map) do
        table.sort(list, function (x, y)
            return (tonumber(x.action_order) or 99) < (tonumber(y.action_order) or 99);
        end);
    end
    return map;
end

-- Every name the step points at, from both the reconciled step and its primary
-- compact action. Order preserved, deduplicated by normalised key.
local function candidate_names(step, compact)
    local seen, list = {}, {};
    local function add(v)
        v = tostring(v or '');
        if (v == '') then return; end
        local k = name_key(v);
        if (k == '' or seen[k]) then return; end
        seen[k] = true; list[#list + 1] = v;
    end
    for _, v in ipairs(step.entities or {}) do add(v); end
    for _, action in ipairs(type(compact) == 'table' and compact or {}) do
        add(action.target);
        for _, group in ipairs({ action.objects, action.npcs, action.enemies }) do
            for _, v in ipairs(type(group) == 'table' and group or {}) do add(v); end
        end
    end
    return list;
end

local POSITIONAL_KIND = {
    npc = true, object = true, enemy = true, entrance = true,
    area = true, zone = true, ['question-mark'] = true,
};

-- Three buckets, and nothing is dropped without a number against it.
--
--   'actionable'  the step tells the player to be somewhere: it names an
--                 entity, OR its primary compact action is positional, OR its
--                 own action verb is positional and it names a zone.
--   'prose-place' a note/wait/select step that merely MENTIONS a place in
--                 prose and whose compact action names nowhere. The resolver
--                 declines these by design; counting them as refusals would
--                 have inflated the gap count by 806.
--   'instruction' names nowhere at all.
--
-- An empty `entities` list is NOT evidence of a non-positional step: it is what
-- a target_identity conflict leaves behind (Windurst 1 step-017).
local NON_POSITIONAL_VERB = { note = true, wait = true, select = true, choose = true };
local function compact_is_positional(compact)
    for _, a in ipairs(type(compact) == 'table' and compact or {}) do
        if (POSITIONAL_KIND[name_key(a.target_kind or '')]) then return true; end
        for _, group in ipairs({ a.objects, a.npcs, a.enemies }) do
            for _, v in ipairs(type(group) == 'table' and group or {}) do
                if (tostring(v) ~= '') then return true; end
            end
        end
        if ((tonumber(a.destination_zone_id) or 0) > 0) then return true; end
    end
    return false;
end

-- The VERB decides whether a step is an instruction to go somewhere. A `note`
-- whose compact action happens to name an NPC is still a note: the resolver
-- declines it by design. Revision 2 counted all 971 of them as actionable steps
-- that then "refused" with reason unknown -- 971 fictional gaps stacked on top
-- of the real ones. They get their own bucket and are never called refused.
-- An `examine` or `travel` step can NEVER land in this bucket, so no real gap
-- is hidden by the change.
local function step_bucket(step, compact)
    local named_entity = false;
    for _, v in ipairs(step.entities or {}) do if (tostring(v) ~= '') then named_entity = true; end end
    local named_zone = false;
    for _, v in ipairs(step.zones or {}) do if (tostring(v) ~= '') then named_zone = true; end end
    local names_somewhere = named_entity or named_zone or compact_is_positional(compact);
    if (NON_POSITIONAL_VERB[name_key(step.action)]) then
        return names_somewhere and 'instruction-mention' or 'instruction';
    end
    if (names_somewhere) then return 'actionable'; end
    return 'instruction';
end

local function is_zone_substitute(t)
    if (type(t) ~= 'table') then return true; end
    if (name_key(t.source or '') == 'zone-travel') then return true; end
    if (name_key(t.entity_choice_stage or '') == 'zone') then return true; end
    if (xyz(t) == nil) then return true; end
    return false;
end

local rows, cases, case_seen = {}, {}, {};
local totals = {
    steps = 0, positional = 0, note_instruction = 0, instruction_mention = 0,
    refused = 0, zone_substitute = 0, precise = 0,
    conflict_positional = 0, entityless_positional = 0,
    ingress_steps = 0, ingress_alternate = 0, ingress_single_mouth = 0,
    ingress_unevaluated = 0, ingress_ok = 0, untested_confidence = 0,
    case_candidates = 0, case_rows = 0, case_no_mouth = 0,
};
local refusal_reasons = {};
local shape_dumped = false;

-- one case row per (physical candidate point) x (incoming edge of its zone)
local function record_case(zone, point, step_id)
    local tx, tz, ty = xyz(point);
    if (tx == nil) then return; end
    local ident = tostring(point.destination_id or point.raw_identity or '');
    local key = ('%d\t%s\t%s\t%.3f\t%.3f\t%.3f'):format(
        zone, name_key(point.name or ''), ident, tx, tz, ty);
    local rec = case_seen[key];
    if (rec == nil) then
        totals.case_candidates = totals.case_candidates + 1;
        rec = { zone = zone, name = tostring(point.name or ''), ident = ident,
            tx = tx, tz = tz, ty = ty, steps = {}, step_seen = {} };
        case_seen[key] = rec;
        cases[#cases + 1] = rec;
    end
    if (step_id and not rec.step_seen[step_id]) then
        rec.step_seen[step_id] = true;
        rec.steps[#rec.steps + 1] = step_id;
    end
end

-- CANDIDATE COLLECTION IS WIDER THAN CLASSIFICATION ON PURPOSE.
--
-- Every resolver target (not just targets[1]), plus every name from the step and
-- from EVERY compact action, looked up in every zone the guide names for the
-- step. It runs for instruction-mention steps too: reclassifying a note changed
-- what the audit REPORTS, and must not shrink what Codex can natively verify.
-- Scoping the export to 'actionable' cost 259 candidates the moment the buckets
-- changed, which is how this was caught.
local function collect_cases(ctx, step, compact, prev_zone, targets, step_id)
    if (not export_path) then return; end
    for _, t in ipairs(type(targets) == 'table' and targets or {}) do
        if (not is_zone_substitute(t)) then
            record_case(tonumber(t.zone) or prev_zone, t, step_id);
        end
    end
    local zone_ids = {};
    local function add_zone(z) z = tonumber(z); if (z and z > 0) then zone_ids[z] = true; end end
    local function add_named_zone(zn)
        for _, z in ipairs(ctx.zone_ids_for_name(zn) or {}) do add_zone(z); end
        for _, z in ipairs(zone_ids_by_graph_name[name_key(zn)] or {}) do add_zone(z); end
    end
    for _, zn in ipairs(step.zones or {}) do add_named_zone(zn); end
    for _, action in ipairs(type(compact) == 'table' and compact or {}) do
        for _, zn in ipairs(type(action.zones) == 'table' and action.zones or {}) do add_named_zone(zn); end
        add_zone(action.destination_zone_id or 0);
    end
    if (next(zone_ids) == nil) then add_zone(prev_zone); end
    for _, nm in ipairs(candidate_names(step, compact)) do
        local key = name_key(nm);
        for z in pairs(zone_ids) do
            for _, p in ipairs(ctx.points_for_zone_entity(z, key) or {}) do
                record_case(z, p, step_id);
            end
        end
    end
end

for _, spec in ipairs(NATIONS) do
    local ok, tbl = pcall(dofile, ADDON .. '/modules/' .. spec.module .. '.lua');
    if (not ok or type(tbl) ~= 'table') then
        rows[#rows + 1] = { nation = spec.nation, fatal = tostring(tbl) };
    else
        local prog = spec.module:gsub('reconcile', 'progression');
        local dest_map = progression_destinations(prog);
        local dest_fn = function (step_id) return dest_map[step_id] or 0; end
        local compact_map = compact_actions(prog);

        local keys = {};
        for native_key, entry in pairs(tbl) do
            if (type(entry) == 'table' and type(entry.steps) == 'table') then keys[#keys + 1] = native_key; end
        end
        table.sort(keys, function (a, b)
            local na, nb = tonumber(a:match(':(%d+)$')), tonumber(b:match(':(%d+)$'));
            if (na and nb and na ~= nb) then return na < nb; end
            return a < b;
        end);

        for _, native_key in ipairs(keys) do
            local steps = tbl[native_key].steps;
            local zone = spec.start_zone;
            for i, step in ipairs(steps) do
                totals.steps = totals.steps + 1;
                local step_id = tostring(step.stable_step_id or '');
                local compact = compact_map[step_id];
                local action = name_key(step.action);

                local bucket = step_bucket(step, compact);
                if (bucket == 'instruction') then
                    totals.note_instruction = totals.note_instruction + 1;
                elseif (bucket == 'instruction-mention') then
                    totals.instruction_mention = totals.instruction_mention + 1;
                    collect_cases(make_ctx(zone, dest_fn, spec.nation, native_key),
                        step, compact, zone, nil, step_id);
                else
                    totals.positional = totals.positional + 1;
                    local entityless = (#(step.entities or {}) == 0);
                    if (entityless) then totals.entityless_positional = totals.entityless_positional + 1; end
                    if (name_key(step.comparison or '') == 'conflict') then
                        totals.conflict_positional = totals.conflict_positional + 1;
                    end

                    local ctx = make_ctx(zone, dest_fn, spec.nation, native_key);
                    local prev_zone = zone;
                    local targets, info = resolver.resolve_step(steps, i, ctx);
                    info = type(info) == 'table' and info or {};
                    targets = type(targets) == 'table' and targets or {};

                    if (shape_only and not shape_dumped and #targets > 0) then
                        shape_dumped = true;
                        print('-- target shape for ' .. step_id);
                        for k, v in pairs(targets[1]) do
                            print(('   %-22s %s'):format(tostring(k), tostring(v)));
                        end
                    end

                    collect_cases(ctx, step, compact, prev_zone, targets, step_id);
                    if (false) then
                    end

                    if (#targets == 0) then
                        local reason = tostring(info.reason or 'unknown');
                        totals.refused = totals.refused + 1;
                        refusal_reasons[reason] = (refusal_reasons[reason] or 0) + 1;
                        rows[#rows + 1] = { nation = spec.nation, step_id = step_id, action = action,
                            class = 'refused', detail = reason .. ': ' .. tostring(info.detail or ''),
                            from_zone = prev_zone, entityless = entityless };
                    else
                        local t = targets[1];
                        local tzone = tonumber(t.zone) or prev_zone;
                        if (is_zone_substitute(t)) then
                            totals.zone_substitute = totals.zone_substitute + 1;
                            rows[#rows + 1] = { nation = spec.nation, step_id = step_id, action = action,
                                class = 'zone-substitute', from_zone = prev_zone, to_zone = tzone,
                                target_name = tostring(t.name or ''), entityless = entityless,
                                detail = ('source=%s entity_choice_stage=%s'):format(
                                    tostring(t.source or ''), tostring(t.entity_choice_stage or '')) };
                            zone = tzone;
                        else
                            totals.precise = totals.precise + 1;
                            if (name_key(t.confidence or ''):find('untested', 1, true)) then
                                totals.untested_confidence = totals.untested_confidence + 1;
                            end
                            if (tzone ~= prev_zone) then
                                totals.ingress_steps = totals.ingress_steps + 1;
                                local tx, tz = xyz(t);
                                local chosen, chosen_d, best, best_d, counted = nil, nil, nil, nil, 0;
                                local path = zone_path(prev_zone, tzone, t.canonical_edge_id);
                                if (type(path) == 'table' and #path > 0) then
                                    local last = path[#path];
                                    if (tonumber(last.to_zone) == tzone) then chosen = last; end
                                end
                                for _, e in ipairs(incoming_edges(tzone)) do
                                    local ex, ez = edge_xyz(e);
                                    if (ex ~= nil and tx ~= nil) then
                                        counted = counted + 1;
                                        local d = flat(tx, tz, ex, ez);
                                        if (best_d == nil or d < best_d) then best, best_d = e, d; end
                                        if (chosen ~= nil and e.id == chosen.id) then chosen_d = d; end
                                    end
                                end
                                if (chosen ~= nil and chosen_d == nil) then chosen = nil; end
                                if (counted <= 1) then
                                    totals.ingress_single_mouth = totals.ingress_single_mouth + 1;
                                elseif (chosen == nil or best == nil) then
                                    totals.ingress_unevaluated = totals.ingress_unevaluated + 1;
                                elseif (chosen.id ~= best.id and (chosen_d - best_d) >= 100) then
                                    totals.ingress_alternate = totals.ingress_alternate + 1;
                                    rows[#rows + 1] = { nation = spec.nation, step_id = step_id, action = action,
                                        class = 'ingress-alternate', from_zone = prev_zone, to_zone = tzone,
                                        target_name = tostring(t.name or ''), entityless = entityless,
                                        detail = ('chose %s from %s at %.1f yalms; %s from %s is %.1f yalms (%.1f closer)'):format(
                                            tostring(chosen.to_name ~= '' and chosen.to_name or chosen.id), zname(chosen.from_zone), chosen_d,
                                            tostring(best.to_name ~= '' and best.to_name or best.id), zname(best.from_zone), best_d,
                                            chosen_d - best_d) };
                                else
                                    totals.ingress_ok = totals.ingress_ok + 1;
                                end
                            end
                            zone = tzone;
                        end
                    end
                end
            end
        end
    end
end

if (shape_only) then return; end

-- export ------------------------------------------------------------------
if (export_path) then
    local f = assert(io.open(export_path, 'wb'));
    f:write('zone\tzone_name\ttarget_name\ttarget_identity\ttx\ttz\tty\t'
        .. 'edge_id\tfrom_zone\tfrom_zone_name\tsx\tsz\tsy\tmission_step_ids\n');
    table.sort(cases, function (a, b)
        if (a.zone ~= b.zone) then return a.zone < b.zone; end
        if (a.name ~= b.name) then return a.name < b.name; end
        return a.ident < b.ident;
    end);
    for _, c in ipairs(cases) do
        table.sort(c.steps);
        local mouths = incoming_edges(c.zone);
        local wrote = 0;
        for _, e in ipairs(mouths) do
            local sx, sz, sy = edge_xyz(e);
            if (sx ~= nil) then
                wrote = wrote + 1;
                totals.case_rows = totals.case_rows + 1;
                f:write(('%d\t%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%s\t%d\t%s\t%.3f\t%.3f\t%.3f\t%s\n'):format(
                    c.zone, zone_names[c.zone] or '', c.name, c.ident, c.tx, c.tz, c.ty,
                    tostring(e.id), tonumber(e.from_zone) or 0, zone_names[tonumber(e.from_zone) or 0] or '',
                    sx, sz, sy, table.concat(c.steps, ',')));
            end
        end
        if (wrote == 0) then totals.case_no_mouth = totals.case_no_mouth + 1; end
    end
    f:close();
end

-- report ------------------------------------------------------------------
local function header(s) print(''); print(s); print(string.rep('-', #s)); end

print('AccessXI nation-mission destination and ingress audit');
print('addon: ' .. ADDON);

header('inventory');
print(('  steps walked                    %d'):format(totals.steps));
print(('  instruction (names nowhere)     %d'):format(totals.note_instruction));
print(('  instruction-only, positional mention %d'):format(totals.instruction_mention));
print(('  ACTIONABLE positional steps     %d'):format(totals.positional));
print(('    of which entity-less          %d'):format(totals.entityless_positional));
print(('    of which comparison=conflict  %d'):format(totals.conflict_positional));
print(('    refused                       %d'):format(totals.refused));
print(('    zone-level substitute         %d'):format(totals.zone_substitute));
print(('    precise target                %d'):format(totals.precise));
print(('  precise steps entering a zone   %d'):format(totals.ingress_steps));
print(('    single-mouth zones            %d'):format(totals.ingress_single_mouth));
print(('    multi-mouth, closest chosen   %d'):format(totals.ingress_ok));
print(('    multi-mouth, NOT EVALUATED    %d'):format(totals.ingress_unevaluated));
print(('    ingress-alternate flagged     %d'):format(totals.ingress_alternate));
print(('  precise targets marked untested %d of %d'):format(totals.untested_confidence, totals.precise));
print('  physical reachability           UNKNOWN (no navmesh probed by this file)');
if (export_path) then
    print(('  export candidates               %d'):format(totals.case_candidates));
    print(('  export rows (candidate x mouth) %d'):format(totals.case_rows));
    print(('  candidates with NO mouth        %d'):format(totals.case_no_mouth));
    print('  export path                     ' .. export_path);
end

header('refusal reasons');
local reasons = {};
for k, v in pairs(refusal_reasons) do reasons[#reasons + 1] = { k, v }; end
table.sort(reasons, function (a, b) return a[2] > b[2]; end);
for _, r in ipairs(reasons) do print(('  %-34s %d'):format(r[1], r[2])); end

local function dump(class, title)
    header(title);
    local n = 0;
    for _, r in ipairs(rows) do
        if (r.class == class) then
            n = n + 1;
            print(('  %s [%s]%s'):format(r.step_id, r.action, r.entityless and '  (entity-less)' or ''));
            print(('      %s -> %s  target=%s'):format(zname(r.from_zone),
                r.to_zone and zname(r.to_zone) or '(refused)', tostring(r.target_name or '')));
            print('      ' .. tostring(r.detail));
        end
    end
    if (n == 0) then print('  (none)'); end
end

dump('zone-substitute', 'ZONE-LEVEL SUBSTITUTE: routed to a zone mouth instead of the named place');
dump('ingress-alternate', 'INGRESS-ALTERNATE: a closer mouth of the same zone was not chosen');
dump('refused', 'REFUSED steps');

for _, r in ipairs(rows) do
    if (r.fatal) then print(('FATAL %s: %s'):format(r.nation, r.fatal)); end
end

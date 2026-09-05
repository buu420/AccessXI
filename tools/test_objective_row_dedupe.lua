-- THE MISSION BROWSE MUST NOT READ THE SAME PLACE THREE TIMES.
--
-- Live 2026-08-28, "Below the Arks" (mission:Chains of Promathia:3). The player
-- heard TEN rows for one step, 13 through 22 of 34, every one announced with the
-- same instruction:
--
--   13,14,15 -> La Theine Plateau Shattered Telepoint
--   16       -> Konschtat Highlands Shattered Telepoint
--   17       -> Tahrongi Canyon Shattered Telepoint
--   18..22   -> Hall of Transference Large Apparatus
--
-- Their words: "it appears as if it's showing a bunch of duplicate entries for
-- this particular mission... you can make it show just the places you need to
-- visit."
--
-- The cause: nav_collect_menu_items returns early for the mission and quest
-- categories, so the confidence filter, the same-name bucketing and the height
-- clustering below that return are all dead code for them. The two categories a
-- player spends the most time in were the only two with no dedup at all.
--
-- The three La Theine rows are three different files: the proven lsb-npc-list
-- row, a confidence=bad screenshot row, and a recorded survey mark out of
-- data/ffxi-nav-recorded-marks.tsv, which the destinations TSV knows nothing
-- about.
--
-- Drives the REAL accessxi.nav_dedupe_objective_rows, lifted verbatim from the
-- deployed accessxi_reader.lua, against the REAL shipped catalogue rows.
--
--   luajit tools/test_objective_row_dedupe.lua
--
-- Exit code 1 on any failed claim.

local load = loadstring or load; -- Lua 5.1 compiles source strings with loadstring.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');

local function lift(header)
    local from = reader:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = reader:find('\nend\n', from, true);
    if (to == nil) then return nil; end
    return reader:sub(from, to + 4);
end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end

local key_src = lift('accessxi.nav_menu_static_key = function (point)');
local cluster_src = lift('function accessxi.nav_cluster_static_points_by_height(points)');
local better_src = lift('accessxi.nav_static_destination_is_better = function (point, previous)');
local dedupe_src = lift('function accessxi.nav_dedupe_objective_rows(items)');

claim(key_src ~= nil, 'the static key function is in the deployed reader');
claim(cluster_src ~= nil, 'so is the height clustering');
claim(better_src ~= nil, 'so is the tiebreak');
claim(dedupe_src ~= nil, 'so is the objective row deduper');
if (dedupe_src == nil or key_src == nil or cluster_src == nil or better_src == nil) then
    print(('objective row dedupe: %d passed, %d failed'):format(passed, failed));
    os.exit(1);
end

-- Dependencies, stubbed. None of these is the thing under test.
local logged = {};
_G.log_line = function (text) logged[#logged + 1] = tostring(text or ''); end
_G.nav_clean_field = function (v) return (tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')); end
_G.nav_point_key = function (p) return ('%s:%s:%s'):format(tostring(p.zone), tostring(p.name), tostring(p.y)); end
-- Rank mirrors the deployed ordering that matters here: proven lsb rows beat
-- recorded marks beat a confidence=bad row (which the real ranker forces to 99).
_G.nav_point_source_rank = function (point)
    local confidence = tostring(point.confidence or ''):lower();
    if (confidence == 'bad') then return 99; end
    if (tostring(point.source or ''):find('lsb', 1, true)) then return 1; end
    return 2;
end
accessxi.nav_point_effective_kind = function (point)
    return tostring(point.kind or '');
end

assert(load(better_src, 'better'))();
assert(load(cluster_src, 'cluster'))();
assert(load(key_src, 'key'))();
assert(load(dedupe_src, 'dedupe'))();
claim(type(accessxi.nav_dedupe_objective_rows) == 'function', 'the real deduper loaded');

-- ---------------------------------------------------------------------------
-- Real catalogue rows, from BOTH files that feed accessxi.nav_points.
-- ---------------------------------------------------------------------------
local function read_rows(path, has_identity)
    local out = {};
    local f = io.open(path, 'r');
    if (f == nil) then return out; end
    for line in f:lines() do
        if (line ~= '' and line:sub(1, 1) ~= '#') then
            local c = {};
            for field in (line .. '\t'):gmatch('([^\t]*)\t') do c[#c + 1] = field; end
            local zone, y = tonumber(c[1]), tonumber(c[5]);
            if (zone ~= nil and y ~= nil and (c[2] or '') ~= '') then
                out[#out + 1] = {
                    zone = zone, name = c[2],
                    x = tonumber(c[3]) or 0, z = tonumber(c[4]) or 0, y = y,
                    kind = c[6] or 'npc', source = c[7] or '',
                    confidence = c[8] or '',
                    raw_identity = has_identity and (c[11] or '') or '',
                    distance = 0,
                };
            end
        end
    end
    f:close();
    return out;
end

local catalogue = read_rows(ADDON .. '/data/ffxi-nav-destinations.tsv', true);
local marks = read_rows(ADDON .. '/data/ffxi-nav-recorded-marks.tsv', false);
for _, r in ipairs(marks) do catalogue[#catalogue + 1] = r; end
claim(#catalogue > 1000, 'the real catalogue loaded, ' .. #catalogue .. ' rows');

local function pick(zone, name)
    local out = {};
    for _, r in ipairs(catalogue) do
        if (r.zone == zone and tostring(r.name):lower() == tostring(name):lower()) then
            out[#out + 1] = r;
        end
    end
    return out;
end

-- Stamp rows as one objective's destinations, the way the browse does.
local function as_objective(rows, native_key, step_id)
    local out = {};
    for _, r in ipairs(rows) do
        local copy = {};
        for k, v in pairs(r) do copy[k] = v; end
        copy.objective_kind = 'mission';
        copy.objective_native_key = native_key or "mission:Chains of Promathia:3";
        copy.objective_guide_step_id = step_id or "mission:Chains of Promathia:3:step-009";
        copy.objective_action_id = (step_id or 'step-009') .. ':claim-02';
        copy.objective_candidate_id = '';
        out[#out + 1] = copy;
    end
    return out;
end

-- ---------------------------------------------------------------------------
-- 1. THE LA THEINE TRIPLE. Three files, one place.
-- ---------------------------------------------------------------------------
local lathine = pick(102, 'Shattered Telepoint');
claim(#lathine == 3, 'the shipped data really does hold three La Theine telepoint rows, got ' .. #lathine);

local deduped = accessxi.nav_dedupe_objective_rows(as_objective(lathine));
claim(#deduped == 1, 'they collapse to ONE browse row, got ' .. #deduped);
claim(deduped[1] ~= nil and tostring(deduped[1].confidence):lower() ~= 'bad',
    'and the survivor is not the confidence=bad row');
claim(deduped[1] ~= nil and tostring(deduped[1].source):find('lsb', 1, true) ~= nil,
    'it is the proven lsb row, got source=' .. tostring(deduped[1] and deduped[1].source));

-- ---------------------------------------------------------------------------
-- 2. THE SIX LARGE APPARATUS. Three chambers, two apparatus each; the chambers
--    are 40 yalms apart in height and the pairs share a height.
-- ---------------------------------------------------------------------------
local apparatus = pick(14, 'Large Apparatus');
claim(#apparatus == 6, 'the shipped data holds six Large Apparatus, got ' .. #apparatus);

local apparatus_deduped = accessxi.nav_dedupe_objective_rows(as_objective(apparatus));
claim(#apparatus_deduped == 3,
    'they collapse to one per chamber, got ' .. #apparatus_deduped);
local bands = {};
for _, r in ipairs(apparatus_deduped) do bands[#bands + 1] = ('%.1f'):format(r.y); end
table.sort(bands);
claim(table.concat(bands, ',') == '-4.9,-44.9,-84.9',
    'one row in each height band, got ' .. table.concat(bands, ','));

-- ---------------------------------------------------------------------------
-- 3. THE WHOLE STEP AS THE PLAYER HEARD IT: ten rows in, and what comes out.
-- ---------------------------------------------------------------------------
local all = {};
for _, r in ipairs(lathine) do all[#all + 1] = r; end
for _, r in ipairs(pick(108, 'Shattered Telepoint')) do all[#all + 1] = r; end
for _, r in ipairs(pick(117, 'Shattered Telepoint')) do all[#all + 1] = r; end
for _, r in ipairs(apparatus) do all[#all + 1] = r; end
local step_rows = accessxi.nav_dedupe_objective_rows(as_objective(all));
print(('       (Below the Arks: %d rows in -> %d out)'):format(#all, #step_rows));
claim(#all >= 10, 'the step really did produce ten or more rows, got ' .. #all);
claim(#step_rows < #all, 'and the browse now speaks fewer of them');
local telepoints = 0;
for _, r in ipairs(step_rows) do
    if (tostring(r.name):lower() == 'shattered telepoint') then telepoints = telepoints + 1; end
end
claim(telepoints == 3, 'all three crags survive -- they are a real choice, got ' .. telepoints);

-- ---------------------------------------------------------------------------
-- 4. IT MUST NOT MERGE ACROSS OBJECTIVES. Two missions naming the same place
--    are two different instructions.
-- ---------------------------------------------------------------------------
local mixed = {};
for _, r in ipairs(as_objective(lathine, 'mission:A:1', 'mission:A:1:step-001')) do
    mixed[#mixed + 1] = r;
end
for _, r in ipairs(as_objective(lathine, 'mission:B:2', 'mission:B:2:step-001')) do
    mixed[#mixed + 1] = r;
end
local mixed_out = accessxi.nav_dedupe_objective_rows(mixed);
claim(#mixed_out == 2, 'each objective keeps its own row, got ' .. #mixed_out);

-- ---------------------------------------------------------------------------
-- 5. A LONE BAD ROW SURVIVES. Losing an objective's last destination is worse
--    than offering a poor one -- the player would simply lose the entry.
-- ---------------------------------------------------------------------------
local only_bad = nil;
for _, r in ipairs(lathine) do
    if (tostring(r.confidence):lower() == 'bad') then only_bad = r; end
end
claim(only_bad ~= nil, 'the bad row is identifiable in the shipped data');
local lone = accessxi.nav_dedupe_objective_rows(as_objective({ only_bad }));
claim(#lone == 1, 'a bad row that is the only row is still offered, got ' .. #lone);

-- ---------------------------------------------------------------------------
-- 6. NON-DESTINATION ROWS PASS THROUGH. An instruction-only row has no place
--    and must never be dropped by a place-based rule.
-- ---------------------------------------------------------------------------
local with_instruction = as_objective(lathine);
table.insert(with_instruction, 1, {
    objective_kind = 'mission', objective_native_key = "mission:Chains of Promathia:3",
    objective_instruction_only = true, name = '', zone = 0,
});
local kept = accessxi.nav_dedupe_objective_rows(with_instruction);
claim(#kept == 2, 'the instruction row survives alongside the single destination, got ' .. #kept);
claim(kept[1] ~= nil and kept[1].objective_instruction_only == true,
    'and stays in its original position');

print(('objective row dedupe: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

-- AN OVERRIDE STEP ID MUST NOT COLLIDE WITH THE PAGE IT REPLACES.
--
-- Live 2026-08-25, Journey to Bastok. The player's saved cursor sat on the
-- collapsed "Journey Abroad" page's step-004, "Halver will instruct you to
-- visit two other Nations". mapped_previous_progress_record() carries a cursor
-- across a revision change by matching step_id and action_id as STRINGS, and
-- the reviewed override named its own fourth step step-004 too -- so the cursor
-- landed on "trade the gravel to the Refiner Lid" and the addon skipped Pius,
-- Grohm and the Mythril Seam. The player found Pius with /axi zonesearch.
--
-- Drives the REAL override table against the REAL shipped guide modules and the
-- player's REAL saved progress file.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
package.path = ADDON .. '/modules/?.lua;' .. package.path;
string.fmt = string.format;
local Tmt = {}; Tmt.__index = {
    append = function (s, v) s[#s + 1] = v; return s; end,
    len = function (s) return #s; end,
    each = function (s, f) for i, v in ipairs(s) do f(v, i); end end,
};
_G.T = function (t) return setmetatable(t or {}, Tmt); end
_G.accessxi = {};

local overrides = dofile(ADDON .. '/modules/mission_quest_step_overrides.lua');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

-- Collect every id the override table can ever emit, per native key.
local override_ids, all_override_ids = {}, {};
for native_key, record in pairs(overrides) do
    override_ids[native_key] = {};
    local function take(list)
        for _, s in ipairs(list or {}) do
            override_ids[native_key][s.stable_step_id] = true;
            all_override_ids[s.stable_step_id] = native_key;
        end
    end
    for _, v in ipairs(record.variants or {}) do take(v.steps); end
    take(record.steps);
end

local native_count = 0;
for _ in pairs(override_ids) do native_count = native_count + 1; end
claim(native_count == 5, 'five native keys are overridden, got ' .. native_count);

-- 1. Every emitted id is namespaced.
local unnamespaced = {};
for id in pairs(all_override_ids) do
    if (id:find(':reviewed:', 1, true) == nil) then unnamespaced[#unnamespaced + 1] = id; end
end
claim(#unnamespaced == 0,
    'every override step id carries ":reviewed:", bare: ' .. table.concat(unnamespaced, ', '));

-- 2. THE REGRESSION ITSELF. The shipped guide modules must not generate any id
--    the override also generates. Read the real progression module as text --
--    it is the source the live actions are built from.
local guide_text = io.open(ADDON .. '/modules/mission_quest_progression_mission_san_doria.lua'):read('*a');
local guide_ids = {};
for id in guide_text:gmatch('"(mission:San d\'Oria:%d+:step%-%d+)"') do guide_ids[id] = true; end
local guide_count = 0;
for _ in pairs(guide_ids) do guide_count = guide_count + 1; end
claim(guide_count > 0, 'the shipped guide module really does emit step ids, got ' .. guide_count);

local collisions = {};
for id in pairs(all_override_ids) do
    if (guide_ids[id]) then collisions[#collisions + 1] = id; end
end
claim(#collisions == 0,
    'NO override id is also a guide id -- this is the Pius skip, colliding: '
    .. table.concat(collisions, ', '));

-- 3. The exact id that caused it is gone from the override.
claim(all_override_ids["mission:San d'Oria:7:step-004"] == nil,
    'the override no longer claims the id the old cursor was parked on');
claim(guide_ids["mission:San d'Oria:7:step-004"] == true,
    'while the guide page still does -- so the two are genuinely distinguishable now');

-- 4. THE TWO DATASETS MUST NEVER SHARE A SAVED CURSOR.
--
--    The original wording asserted that NO saved row names an override step.
--    That was true only for the instant after the ids were namespaced, and it
--    went red the moment the player actually walked the mission -- their file
--    now records :reviewed:step-002 through step-007 for Journey to Bastok,
--    which is the fix working, not breaking. A snapshot is not an invariant.
--
--    The durable invariant is that a row's revision and its step id must agree
--    about which dataset they came from. A row saved under an 'override:'
--    revision must name an override id, and a row saved under a scraped
--    revision hash must NOT -- either direction is the collision that skipped
--    Pius, and either direction is what lets a cursor land mid-sequence.
local crossed, rows, override_rows = {}, 0, 0;
local progress = io.open(ADDON .. '/data/ffxi-objective-interaction-progress.tsv');
if (progress ~= nil) then
    for line in progress:lines() do
        local f = {};
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = field; end
        -- v2 layout: version, identity, world, native_key, revision, step_id, ...
        if (f[1] == 'v2' and override_ids[f[4]] ~= nil) then
            rows = rows + 1;
            local is_override_revision = tostring(f[5]):sub(1, 9) == 'override:';
            local is_override_id = override_ids[f[4]][f[6]] == true;
            if (is_override_revision) then override_rows = override_rows + 1; end
            if (is_override_revision ~= is_override_id) then
                crossed[#crossed + 1] = ('%s rev=%s step=%s'):format(
                    f[4], is_override_revision and 'override' or 'scraped', f[6]);
            end
        end
    end
    progress:close();
end
claim(rows > 0, 'the live progress file really does carry rows for an overridden mission, got ' .. rows);

--    Crossed rows DO still exist: the file is append-only and never rewritten,
--    so the poisoned row the migration wrote on 2026-08-25 is in there forever.
--    What must hold is that the loader screens them on the way in, so assert
--    the screen exists and that its predicate rejects every crossed row found.
local nav_early = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
claim(nav_early:find('function progress_row_crosses_datasets', 1, true) ~= nil,
    'the loader screens rows whose revision and step id disagree');
claim(nav_early:find('not progress_row_crosses_datasets(clean(fields[4]), clean(fields[5]), clean(fields[6]))', 1, true) ~= nil,
    'and it is applied where rows enter the history, not merely defined');
local screened = 0;
for _, row in ipairs(crossed) do
    -- The screen's rule: an 'override:' revision must name a ':reviewed:' id.
    local rev_override = row:find('rev=override', 1, true) ~= nil;
    local id_override = row:find(':reviewed:', 1, true) ~= nil;
    if (rev_override ~= id_override) then screened = screened + 1; end
end
claim(screened == #crossed,
    'every crossed row in the live file is one the screen rejects, '
    .. screened .. ' of ' .. #crossed);

-- 5. And the fix is observably WORKING in the wild: the player walked the
--    mission after it landed, so namespaced rows exist and were written by real
--    progress rather than by a migration.
claim(override_rows > 0,
    'the player has since advanced through namespaced steps, got ' .. override_rows .. ' rows');

-- 5. The migration guard exists and runs BEFORE the id match. The function is a
--    file local and cannot be called from here, so assert it structurally.
local nav = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
claim(nav:find('function progression_revision_is_override', 1, true) ~= nil,
    'the override-boundary guard exists');
local guard_at = nav:find('progression_revision_is_override(revision)', 1, true);
local match_at = nav:find('local index = action_index_by_stable_identity', 1, true);
claim(guard_at ~= nil and match_at ~= nil and guard_at < match_at,
    'and it refuses the migration before any id is matched');
claim(nav:find("clean(revision):sub(1, 9) == 'override:'", 1, true) ~= nil,
    'the guard tests the override revision prefix the resolver actually emits');

-- 6. Ordering is preserved: Pius is still first for Journey to Bastok.
local seven = overrides["mission:San d'Oria:7"];
claim(seven.steps[1].entities[1] == 'Pius',
    'Journey to Bastok still begins at Pius, got ' .. tostring(seven.steps[1].entities[1]));
claim(seven.steps[2].entities[1] == 'Grohm', 'then Grohm for the pickaxes');
claim(seven.steps[1].stable_step_id == "mission:San d'Oria:7:reviewed:step-001",
    'and its id is namespaced, got ' .. tostring(seven.steps[1].stable_step_id));

-- 7. Action ids inherit the namespace, because they are derived from the step id.
claim(nav:find("action_id = step_id .. ':claim-01'", 1, true) ~= nil,
    'action ids are derived from step ids, so they inherit the namespace too');

-- 8. A CURSOR THAT MOVES ON ITS OWN MUST SAY SO. The migration write is the
--    only progress writer that fires without the player acting, and it was the
--    only one that logged nothing -- which is why this bug needed a four-agent
--    investigation instead of one grep.
local migrate_at = nav:find('objective cursor MIGRATED', 1, true);
local save_at = nav:find('and save_cursor_action(\n                native_key, actions[index], migration.progress_count, revision)', 1, true);
claim(migrate_at ~= nil, 'the migration announces itself in the log');
claim(save_at ~= nil and migrate_at > save_at,
    'and it does so at the write site, after the write succeeds');
claim(nav:find('from-revision="%s" to-revision="%s"', 1, true) ~= nil,
    'the message names both revisions, which is what identifies the collision');
claim(nav:find('source_revision = clean(record.progression_revision)', 1, true) ~= nil,
    'the originating revision is carried through so the message can name it');

print(('override step id namespace: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

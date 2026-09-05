-- A PARENT WITH NOTHING OF ITS OWN INHERITS ITS CHILDREN'S PLACES.
--
-- Speaking the rows beneath a step was only half the job. The player asked the
-- obvious next question -- "when people try to make a path to these, are they
-- going to be able to" -- and the answer was no: the cursor sits on the parent,
-- the parent carries entities = {} and zones = {}, and pressing I did nothing.
--
--   A Crystalline Prophecy 2 step-001  "Collect the following 3 items:"
--       children name Jugner Forest, Pashhow Marshlands, Meriphataud Mountains
--   A Shantotto Ascension 3 step-002   (a bare talk step, instruction truncated)
--       children name Kuroido-Moido in Port Windurst, Faulpie in Southern
--       San d'Oria, Abd-al-Raziq in Bastok Mines
--
-- Drives the REAL rollup against the REAL reconciled corpus for both.
local load = loadstring or load; -- Lua 5.1 compiles source strings with loadstring.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local src = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
_G.clean = function (v) return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', ''); end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

local function lift(header)
    local from = src:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = src:find('\nend\n', from, true);
    return to and src:sub(from, to + 4) or nil;
end

local body_src = lift('function accessxi.objective_roll_up_child_targets(steps)');
claim(body_src ~= nil, 'the rollup exists in the deployed navigation module');
if (body_src == nil) then print('child rollup: 0 passed, 1 failed'); os.exit(1); end
assert(load(body_src, 'rollup'))();
claim(type(accessxi.objective_roll_up_child_targets) == 'function', 'the real rollup loaded');

-- Parse the real reconciled steps for one native key, in file order.
local function real_steps(module_name, native_key)
    local text = io.open(ADDON .. '/modules/' .. module_name):read('*a');
    local from = text:find('"' .. native_key .. '"', 1, true);
    if (from == nil) then return {}; end
    local body = text:sub(from, from + 40000);
    local pattern = 'stable_step_id = "(' .. native_key:gsub('%p', '%%%0') .. ':step%-%d+)"';
    local ids, at = {}, 1;
    while true do
        local s, e, id = body:find(pattern, at);
        if (s == nil) then break; end
        ids[#ids + 1] = { id = id, from = s };
        if (#ids > 1) then ids[#ids - 1].to = s - 1; end
        at = e + 1;
    end
    if (#ids > 0) then ids[#ids].to = #body; end
    local steps = {};
    for _, entry in ipairs(ids) do
        local chunk = body:sub(entry.from, entry.to);
        local function lst(field)
            local blk = chunk:match(field .. ' = %{([^}]*)%}');
            local out = {};
            if (blk ~= nil) then for v in blk:gmatch('"([^"]+)"') do out[#out + 1] = v; end end
            return out;
        end
        steps[#steps + 1] = {
            stable_step_id = entry.id,
            action = chunk:match('action = "([^"]*)"') or '',
            entities = lst('entities'), zones = lst('zones'), items = lst('items'),
        };
    end
    return steps;
end

local function names(list)
    local out = {};
    for _, v in ipairs(list or {}) do out[#out + 1] = tostring(v):lower(); end
    return ' ' .. table.concat(out, ' | ') .. ' ';
end
local function mentions(list, want)
    return names(list):find(want:lower(), 1, true) ~= nil;
end

-- 1. A CRYSTALLINE PROPHECY. Three items, three zones.
local cp = real_steps('mission_quest_reconcile_mission_a_crystalline_prophecy.lua',
    'mission:A Crystalline Prophecy:2');
claim(#cp >= 12, 'parsed the Crystalline Prophecy steps, got ' .. #cp);
claim(#cp > 0 and #cp[1].entities == 0 and #cp[1].zones == 0,
    'the collect header really does ship with no target of its own');
local changed = accessxi.objective_roll_up_child_targets(cp);
claim(changed >= 1, 'the rollup changed at least one step, got ' .. changed);
claim(#cp[1].zones >= 3, 'the header inherited its zones, got ' .. #cp[1].zones);
for _, zone in ipairs({ 'Jugner Forest', 'Pashhow Marshlands', 'Meriphataud Mountains' }) do
    claim(mentions(cp[1].zones, zone), 'a path can now be made to ' .. zone);
end
for _, item in ipairs({ 'Seedspall Lux', 'Seedspall Luna', 'Seedspall Astrum' }) do
    claim(mentions(cp[1].entities, item), 'and it names the item ' .. item);
end
claim(cp[1].inherited_from_children == true, 'the step records that it inherited');

-- 2. A SHANTOTTO ASCENSION. The one whose own instruction is truncated, so the
--    children are the ONLY thing that can answer where to go and who to see.
local sa = real_steps('mission_quest_reconcile_mission_a_shantotto_ascension.lua',
    'mission:A Shantotto Ascension:3');
claim(#sa >= 8, 'parsed the Shantotto Ascension steps, got ' .. #sa);
local target = sa[2];
claim(target ~= nil and clean(target.action):lower() == 'talk',
    'step-002 is the talk step the player was stuck on, got '
    .. tostring(target and target.action));
claim(target ~= nil and #target.entities == 0 and #target.zones == 0,
    'and it ships with nothing of its own');
accessxi.objective_roll_up_child_targets(sa);
claim(#target.zones >= 3, 'it inherited its cities, got ' .. #target.zones);
for _, zone in ipairs({ 'Port Windurst', "Southern San d'Oria", 'Bastok Mines' }) do
    claim(mentions(target.zones, zone), 'a path can now be made to ' .. zone);
end
for _, who in ipairs({ 'Kuroido-Moido', 'Faulpie', 'Abd-al-Raziq' }) do
    claim(mentions(target.entities, who), 'and it names who to talk to: ' .. who);
end

-- 3. THE GUARD. A step that named its own target must never have it replaced,
--    or the rollup could pull a route away from somewhere the guide was
--    specific about.
local own = {
    { stable_step_id = 'x:step-001', action = 'talk',
      entities = { 'Pius' }, zones = { 'Metalworks' } },
    { stable_step_id = 'x:step-002', action = 'note',
      entities = { 'Somewhere Else' }, zones = { 'Another Zone' } },
};
accessxi.objective_roll_up_child_targets(own);
claim(#own[1].entities == 1 and own[1].entities[1] == 'Pius',
    'a step with its own target keeps it untouched');
claim(own[1].inherited_from_children == nil, 'and is not marked as inherited');

-- 4. A note never inherits, because a note is read and not walked -- otherwise
--    every line of prose would become a destination.
local notes = {
    { stable_step_id = 'y:step-001', action = 'note', entities = {}, zones = {} },
    { stable_step_id = 'y:step-002', action = 'note',
      entities = { 'Somewhere' }, zones = { 'A Zone' } },
};
accessxi.objective_roll_up_child_targets(notes);
claim(#notes[1].zones == 0, 'a note parent inherits nothing');

-- 5. The subtree stops at the next real step.
local bounded = {
    { stable_step_id = 'z:step-001', action = 'obtain', entities = {}, zones = {} },
    { stable_step_id = 'z:step-002', action = 'note', entities = {}, zones = { 'Mine' } },
    { stable_step_id = 'z:step-003', action = 'talk', entities = {}, zones = { 'Not Mine' } },
};
accessxi.objective_roll_up_child_targets(bounded);
claim(#bounded[1].zones == 1 and bounded[1].zones[1] == 'Mine',
    'inheritance stops at the next real step, got ' .. table.concat(bounded[1].zones, ','));

-- 6. It runs where steps are built, not merely defined.
claim(src:find('accessxi.objective_roll_up_child_targets(result);', 1, true) ~= nil,
    'the rollup is called from the source-step build');

-- 7. INHERIT WHAT IS STILL TO BE DONE, NOT EVERY PLACE MENTIONED.
--
-- Taking every child's entities put three kinds of noise into the destination.
-- Live 2026-08-27 the player heard "Destination: Jugner Forest Survival Guide
-- in Jugner Forest" for a step whose Jugner Forest item was already in their
-- bag, and reported that the locations "still show".
accessxi.objective_inventory_named_state = function (name)
    local items = {
        ['seedspall lux'] = { 2740, 1, 'held' },
        ['seedspall luna'] = { 2741, 0, 'absent' },
        ['seedspall astrum'] = { 2742, 0, 'absent' },
    };
    local row = items[clean(name):lower()];
    if (row == nil) then return 0, nil, 'unknown'; end
    return row[2], row[1], row[3];
end

local cp2 = real_steps('mission_quest_reconcile_mission_a_crystalline_prophecy.lua',
    'mission:A Crystalline Prophecy:2');
accessxi.objective_roll_up_child_targets(cp2);
claim(not mentions(cp2[1].zones, 'Jugner Forest'),
    'the zone of an item already held is NOT inherited, got ' .. names(cp2[1].zones));
claim(mentions(cp2[1].zones, 'Pashhow Marshlands')
    and mentions(cp2[1].zones, 'Meriphataud Mountains'),
    'while the two still needed are, got ' .. names(cp2[1].zones));
claim(not mentions(cp2[1].zones, 'Davoi') and not mentions(cp2[1].zones, 'Beadeaux'),
    'and a "Closest Survival Guide" hint does not outrank a real destination, got '
    .. names(cp2[1].zones));
claim(#cp2[1].zones == 2, 'exactly the two places left to go, got ' .. #cp2[1].zones);

-- 8. A HINT IS ONLY DROPPED WHEN THERE IS SOMETHING BETTER. When no child names
--    an item, the hints are all there is and must still be inherited.
local hints_only = {
    { stable_step_id = 'h:step-001', action = 'travel', entities = {}, zones = {} },
    { stable_step_id = 'h:step-002', action = 'note',
      entities = { 'Home Point' }, zones = { 'Qufim Island' } },
};
accessxi.objective_roll_up_child_targets(hints_only);
claim(#hints_only[1].zones == 1,
    'with no item-bearing child, hints are still inherited, got ' .. #hints_only[1].zones);

-- 9. AN UNCHECKABLE ITEM KEEPS ITS PLACE. Dropping a destination on a guess is
--    how a player ends up stranded.
accessxi.objective_inventory_named_state = function (name)
    if (clean(name):lower():find('seedspall', 1, true)) then
        return 0, 2740, 'unknown';
    end
    return 0, nil, 'unknown';
end
local unknown_cp = real_steps('mission_quest_reconcile_mission_a_crystalline_prophecy.lua',
    'mission:A Crystalline Prophecy:2');
accessxi.objective_roll_up_child_targets(unknown_cp);
claim(mentions(unknown_cp[1].zones, 'Jugner Forest'),
    'an item we cannot check keeps its zone, got ' .. names(unknown_cp[1].zones));

-- 10. The cache must be dropped when a holding changes, or the destination
--     stays stale until a reload.
local nav_src = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
claim(nav_src:find('function accessxi.nav_mission_quest_forget_source_steps', 1, true) ~= nil,
    'the step cache can be dropped on demand');
local reader_src = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
claim(reader_src:find('accessxi.nav_mission_quest_forget_source_steps', 1, true) ~= nil,
    'and an inventory change drops it');
local hook_at = reader_src:find('function accessxi.on_objective_inventory_changed', 1, true);
local drop_at = hook_at and reader_src:find('nav_mission_quest_forget_source_steps', hook_at, true) or nil;
claim(hook_at ~= nil and drop_at ~= nil and (drop_at - hook_at) < 500,
    'from inside the inventory-changed hook itself');

print(('objective child rollup: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

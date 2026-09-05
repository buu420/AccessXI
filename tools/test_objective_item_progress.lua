-- WHAT THE PLAYER ALREADY HAS.
--
-- Player, 2026-08-27: "I was wanting the mission tracker to do that, why can't
-- it go off of inventory and key items as well." The tracker named the three
-- Seedspalls and where each drops, but never said which were already carried.
--
-- Written with sol; these assertions are its suite, adapted where I diverged
-- from its draft (see the comment on accessxi.objective_item_progress).
--
-- THE RULE: a thing we cannot check is 'unknown', NEVER 'needed'. Sending a
-- player to farm a Seedspall they are holding is worse than saying nothing.
--
-- Drives the REAL function, lifted from the deployed navigation module.
local load = loadstring or load; -- Lua 5.1 compiles source strings with loadstring.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};
_G.clean = function (v) return tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', ''); end

local src = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

local from = src:find('function accessxi.objective_item_progress(step)', 1, true);
claim(from ~= nil, 'the function exists in the deployed module');
local to = from and src:find('\nend\n', from, true) or nil;
if (from == nil or to == nil) then
    print('objective item progress: 0 passed, 1 failed'); os.exit(1);
end
assert(load(src:sub(from, to + 4), 'progress'))();
claim(type(accessxi.objective_item_progress) == 'function', 'the real function loaded');

-- The two stores it consults.
local inventory, key_ids, key_states = {}, {}, {};
accessxi.objective_inventory_named_state = function (name)
    local row = inventory[clean(name):lower()];
    if (row == nil) then return 0, nil, 'unknown'; end
    return row.count, row.id, row.state;
end
accessxi.objective_key_item_owned_by_name = function (name)
    local id = key_ids[clean(name):lower()];
    return id ~= nil and key_states[id] == 'held', id;
end
accessxi.mission_quest_key_item_state = function (id) return key_states[id] or 'unknown'; end

local function reset() inventory, key_ids, key_states = {}, {}, {}; end
local function joined(v) return table.concat(v or {}, '|'); end

-- 1. Nothing to say about nothing.
reset();
local r = accessxi.objective_item_progress({});
claim(r.total == 0 and r.kind == 'item', 'an empty step has no requirements');
claim(r.speech == '', 'and stays silent');
claim(accessxi.objective_item_progress(nil).total == 0, 'a nil step is safe');

-- 2. THE REGRESSION. Before the snapshot arrives, nothing is "needed".
reset();
r = accessxi.objective_item_progress({
    items = { 'Seedspall Lux', 'Seedspall Luna', 'Seedspall Astrum' } });
claim(r.total == 3, 'three distinct items');
claim(#r.needed == 0 and #r.unknown == 3,
    'with no snapshot every item is unknown, not needed -- got needed='
    .. #r.needed .. ' unknown=' .. #r.unknown);
claim(r.speech == '', 'and an entirely unknown step stays silent rather than guessing');

-- 3. The sentence the player asked for.
reset();
inventory['seedspall lux'] = { id = 1, count = 1, state = 'held' };
inventory['seedspall luna'] = { id = 2, count = 0, state = 'absent' };
inventory['seedspall astrum'] = { id = 3, count = 0, state = 'absent' };
r = accessxi.objective_item_progress({
    items = { 'Seedspall Lux', 'Seedspall Luna', 'Seedspall Astrum' } });
claim(joined(r.held) == 'Seedspall Lux', 'the held item is named');
claim(joined(r.needed) == 'Seedspall Luna|Seedspall Astrum',
    'the absences are named in guide order, got ' .. joined(r.needed));
claim(r.speech == 'You have 1 of 3. Held: Seedspall Lux. Still needed: Seedspall Luna, Seedspall Astrum.',
    'the speech reads plainly, got "' .. r.speech .. '"');

-- 4. Key items keep their own store and their own third state.
reset();
key_ids['rhapsody in white'] = 10; key_states[10] = 'held';
key_ids['kindred report'] = 11;    key_states[11] = 'unknown';
r = accessxi.objective_item_progress({ key_items = { 'Rhapsody in White', 'Kindred Report' } });
claim(r.kind == 'key-item' and r.total == 2, 'key items use their own kind');
claim(joined(r.held) == 'Rhapsody in White' and joined(r.unknown) == 'Kindred Report',
    'an unread key-item table stays unknown');
claim(r.speech:find('Confirmed held: 1 of 2', 1, true) ~= nil,
    'partial knowledge is hedged, got "' .. r.speech .. '"');
claim(r.speech:find('Could not check: Kindred Report', 1, true) ~= nil,
    'and the unchecked one is named rather than claimed absent');

-- 5. Same label in two stores is two questions. sol's catch.
reset();
inventory['proof'] = { id = 20, count = 1, state = 'held' };
key_ids['proof'] = 21; key_states[21] = 'absent';
r = accessxi.objective_item_progress({ items = { 'Proof' }, key_items = { 'Proof' } });
claim(r.kind == 'mixed' and r.total == 2,
    'an item and a key item sharing a name stay distinct, got ' .. r.total);
claim(joined(r.held) == 'Proof' and joined(r.needed) == 'Proof', 'each store answers for itself');
claim(r.speech:find('Key items still needed: Proof', 1, true) ~= nil,
    'and the missing one is named as a key item, got "' .. r.speech .. '"');

-- 6. Duplicate rows are one requirement, at the strongest quantity. sol's rule.
reset();
inventory['bee pollen'] = { id = 30, count = 2, state = 'held' };
r = accessxi.objective_item_progress({ items = {
    { name = 'Bee Pollen', count = 1 }, { item = 'bee pollen', quantity = 3 } } });
claim(r.total == 1, 'duplicate names count once, got ' .. r.total);
claim(joined(r.needed) == 'Bee Pollen',
    'two of a required three is not satisfied, got held=' .. joined(r.held));

-- 7. A quantity that IS satisfied reads held.
reset();
inventory['bee pollen'] = { id = 30, count = 3, state = 'held' };
r = accessxi.objective_item_progress({ items = { { name = 'Bee Pollen', count = 3 } } });
claim(joined(r.held) == 'Bee Pollen', 'three of three is held');

-- 8. A name the resources cannot resolve proves nothing.
reset();
r = accessxi.objective_item_progress({ items = { 'Unresolvable Item' } });
claim(joined(r.unknown) == 'Unresolvable Item', 'an unresolved name is unknown');
claim(r.speech == '', 'and alone it stays silent');

-- 9. An accessor that throws is unknown, not absent.
reset();
accessxi.objective_inventory_named_state = function () error('boom'); end
r = accessxi.objective_item_progress({ items = { 'Anything' } });
claim(joined(r.unknown) == 'Anything', 'a raising accessor reads unknown');
accessxi.objective_inventory_named_state = function (name)
    local row = inventory[clean(name):lower()];
    if (row == nil) then return 0, nil, 'unknown'; end
    return row.count, row.id, row.state;
end

-- 10. A missing accessor is unknown too, rather than an error or a false absence.
reset();
local saved = accessxi.objective_inventory_named_state;
accessxi.objective_inventory_named_state = nil;
r = accessxi.objective_item_progress({ items = { 'Anything' } });
claim(joined(r.unknown) == 'Anything', 'a missing accessor reads unknown');
accessxi.objective_inventory_named_state = saved;

-- 11. THE WIRING. A function nothing calls is the failure this codebase repeats.
-- Count both call shapes: a direct call and a pcall passing the function as a
-- value, which carries no parenthesis after the name.
local defs, uses = 0, 0;
for _ in src:gmatch('function accessxi%.objective_item_progress%(') do defs = defs + 1; end
for _ in src:gmatch('pcall%(accessxi%.objective_item_progress[,%)]') do uses = uses + 1; end
for _ in src:gmatch('[^n] accessxi%.objective_item_progress%(') do uses = uses + 1; end
claim(defs == 1, 'defined exactly once, got ' .. defs);
claim(uses >= 1, 'and actually called somewhere, uses=' .. uses);
claim(src:find('accessxi.objective_step_supplement(item)', 1, true) ~= nil,
    'through the supplement that every speech branch shares');
claim(src:find('accessxi.objective_step_for_guide_id(', 1, true) ~= nil,
    'the step lookup the wiring needs exists');
local lookup_defs = 0;
for _ in src:gmatch('function accessxi%.objective_step_for_guide_id%(') do
    lookup_defs = lookup_defs + 1;
end
claim(lookup_defs == 1, 'and is DEFINED, not merely called, defs=' .. lookup_defs);

-- 12. It must use the strict availability reader, not the one whose source
--     string is assigned nowhere.
claim(src:find('objective_inventory_state_ready', 1, true) == nil
    or src:find('accessxi.objective_inventory_named_state', 1, true) ~= nil,
    'ownership goes through the tri-state reader');

-- 13. THE ITEM NAMES ARE IN ENTITIES, NOT ITEMS.
--
-- The reconciled corpus carries NO `items` field on these steps -- "Collect the
-- following 3 items:" and each Seedspall row list their names in `entities`
-- beside the zone they drop in. This function therefore found zero
-- requirements and said nothing, and live 2026-08-27 the player was still shown
-- the Jugner Forest directions for a Seedspall they were carrying.
reset();
inventory['seedspall lux'] = { id = 2740, count = 1, state = 'held' };
inventory['seedspall luna'] = { id = 2741, count = 0, state = 'absent' };
inventory['seedspall astrum'] = { id = 2742, count = 0, state = 'absent' };
r = accessxi.objective_item_progress({
    items = {},
    entities = { 'Seedspall Lux', 'Jugner Forest', 'Seedspall Luna',
                 'Pashhow Marshlands', 'Seedspall Astrum', 'Yagudo' },
});
claim(r.total == 3,
    'three items are recovered from entities, got ' .. r.total);
claim(joined(r.held) == 'Seedspall Lux', 'and ownership still reads correctly');
claim(r.speech:find('You have 1 of 3', 1, true) ~= nil,
    'and it speaks, got "' .. r.speech .. '"');

-- A zone, an NPC or a mob family resolves to no item id and must never become
-- a requirement -- otherwise every step would demand its own scenery.
claim(joined(r.needed):find('Jugner', 1, true) == nil
    and joined(r.unknown):find('Jugner', 1, true) == nil,
    'a zone name is not treated as an item');
claim(joined(r.needed):find('Yagudo', 1, true) == nil
    and joined(r.unknown):find('Yagudo', 1, true) == nil,
    'nor is a mob family');

-- 14. DECLARED DATA WINS. A step that names its own items must not have
--     entities bolted on beside them.
reset();
inventory['declared'] = { id = 50, count = 1, state = 'held' };
inventory['seedspall lux'] = { id = 2740, count = 1, state = 'held' };
r = accessxi.objective_item_progress({
    items = { 'Declared' }, entities = { 'Seedspall Lux' } });
claim(r.total == 1 and joined(r.held) == 'Declared',
    'entities are only consulted when the step declared no items, got ' .. r.total);

-- 15. Key items alone must not trigger the entity fallback either.
reset();
key_ids['kindred crest'] = 13; key_states[13] = 'held';
inventory['seedspall lux'] = { id = 2740, count = 1, state = 'held' };
r = accessxi.objective_item_progress({
    key_items = { 'Kindred Crest' }, entities = { 'Seedspall Lux' } });
claim(r.total == 2, 'a key-item step still scans entities for items, got ' .. r.total);
claim(r.kind == 'mixed', 'and reports as mixed, got ' .. r.kind);

print(('objective item progress: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

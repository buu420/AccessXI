-- "NONE" AND "WE DO NOT KNOW" ARE DIFFERENT ANSWERS.
--
-- accessxi.objective_inventory_count returns 0 for an item the player does not
-- have AND for an inventory we have not been told about -- wrong identity,
-- wrong session epoch, or no native snapshot. Key items have had
-- key_item_state_available for exactly this since long ago; ordinary items
-- never got the equivalent.
--
-- It stops being harmless the moment the mission tracker REPORTS holdings
-- instead of merely gating on them. Telling a player "you still need Seedspall
-- Lux" while they are carrying it is worse than saying nothing, and this addon
-- has already lost twelve days to a false() that meant both "no" and "no data".
--
-- Drives the REAL readers, lifted from the deployed accessxi_reader.lua.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;
_G.accessxi = {};

local src = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');

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

for _, header in ipairs({
    'function accessxi.objective_inventory_state_available()',
    'function accessxi.objective_inventory_named_state(name)',
}) do
    local body = lift(header);
    claim(body ~= nil, 'lifted ' .. header:sub(1, 56));
    if (body ~= nil) then assert(load(body, 'inv'))(); end
end
claim(type(accessxi.objective_inventory_state_available) == 'function', 'availability reader loaded');
claim(type(accessxi.objective_inventory_named_state) == 'function', 'named-state reader loaded');

-- The environment those readers consult.
local function setup(opts)
    opts = opts or {};
    accessxi.current_player_identity = function () return opts.identity or 'longrod:127'; end
    accessxi.current_objective_session_epoch = function () return opts.epoch or 42; end
    accessxi.inventory_packet_source = opts.source or 'native-inventory';
    accessxi.inventory_packet_identity = opts.packet_identity or 'longrod:127';
    accessxi.inventory_packet_session_epoch = opts.packet_epoch or 42;
    -- A snapshot must record WHICH containers it actually saw. The label alone
    -- used to be enough, and the builder stamped it on a read of nothing.
    accessxi.inventory_packet_coverage = opts.coverage
        or (opts.coverage == '' and '' or '0,1,2,5,6,7,8');
    accessxi.inventory_packet_slots = opts.slots or 210;
    accessxi.objective_inventory_count_by_name = opts.count_by_name
        or function (name)
            if (name == 'Seedspall Lux') then return 1, 4001; end
            if (name == 'Seedspall Luna') then return 0, 4002; end
            return 0, nil;      -- unresolvable name
        end;
end

-- 1. A healthy snapshot.
setup({});
claim(accessxi.objective_inventory_state_available() == true,
    'a matching native snapshot is available');
local count, id, state = accessxi.objective_inventory_named_state('Seedspall Lux');
claim(state == 'held' and count == 1 and id == 4001,
    'an item the player carries reads held, got ' .. tostring(state));
count, id, state = accessxi.objective_inventory_named_state('Seedspall Luna');
claim(state == 'absent' and count == 0,
    'an item they genuinely lack reads absent, got ' .. tostring(state));

-- 2. THE REGRESSION. Every way the snapshot can be untrustworthy must read
--    unknown, NEVER absent.
for _, bad in ipairs({
    { label = 'no native snapshot', source = 'cache' },
    { label = 'a different character', packet_identity = 'someone:127' },
    { label = 'a stale session epoch', packet_epoch = 41 },
    { label = 'no identity yet', identity = '' },
    { label = 'no session epoch yet', epoch = 0 },
    -- THE ONE THE SURVEY CAUGHT. The builder stamped 'native-inventory' on a
    -- read taken before any container had loaded: 199 of 601 snapshots in the
    -- live log held zero items, one written in the same second the tracker
    -- resolved eight steps against it.
    { label = 'a snapshot that saw no containers', coverage = '' },
    { label = 'a snapshot that scanned no slots', slots = 0 },
}) do
    setup(bad);
    claim(accessxi.objective_inventory_state_available() == false,
        'unavailable with ' .. bad.label);
    local _, _, s = accessxi.objective_inventory_named_state('Seedspall Luna');
    claim(s == 'unknown',
        'and an item reads unknown rather than absent with ' .. bad.label
        .. ', got ' .. tostring(s));
end

-- 3. An unresolvable name is not evidence of anything.
setup({});
count, id, state = accessxi.objective_inventory_named_state('Nonexistent Widget');
claim(state == 'unknown' and id == nil,
    'a name that resolves to no item reads unknown, got ' .. tostring(state));

-- 4. A throwing accessor must not be mistaken for absence either.
setup({ count_by_name = function () error('boom'); end });
_, _, state = accessxi.objective_inventory_named_state('Seedspall Lux');
claim(state == 'unknown', 'an accessor that raises reads unknown, got ' .. tostring(state));

-- 5. A missing accessor is unknown, not absent.
setup({});
accessxi.objective_inventory_count_by_name = nil;
_, _, state = accessxi.objective_inventory_named_state('Seedspall Lux');
claim(state == 'unknown', 'a missing accessor reads unknown, got ' .. tostring(state));

-- 6. The availability test must stay in step with the function whose zero it
--    qualifies -- if objective_inventory_count grows a condition and this does
--    not, the two silently disagree.
local counter = lift('function accessxi.objective_inventory_count(item_id)');
claim(counter ~= nil, 'found objective_inventory_count');
for _, guard in ipairs({ 'native-inventory', 'inventory_packet_identity',
                         'inventory_packet_session_epoch' }) do
    claim(counter:find(guard, 1, true) ~= nil and src:find(guard, 1, true) ~= nil,
        'both readers test ' .. guard);
end

-- 7. The key-item side already had this. Confirm it still does, so the two
--    halves of the feature rest on the same guarantee.
local nav = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
claim(nav:find('local function key_item_state_available(id)', 1, true) ~= nil,
    'key items still have their own availability guard');

print(('inventory third state: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

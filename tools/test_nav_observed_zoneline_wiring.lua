-- THE EXIT LEARNER FAILED TWICE, BOTH TIMES ON WIRING RATHER THAN LOGIC.
--
-- First attempt: nav_zoneline_complete_observed was defined and never called --
-- the same no-caller shape as the guide browser behind G and the N key.
-- Second attempt: it was hooked into the two zone pollers, but
-- nav_cached_player_position notices a zone change FIRST (the walk-graph poll
-- calls it every frame), and it sets nav_current_position to nil before either
-- poller runs. The learner read a field that had just been cleared and returned
-- silently, so a real transition produced no log line at all.
--
-- Both failures are visible in the source, so assert on the source.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
local handle = io.open(ADDON .. '/accessxi_reader.lua', 'r');
local src = handle:read('*a');
handle:close();

local passed, failed = 0, 0;
local function claim(ok, what)
    if (ok) then passed = passed + 1;
    else failed = failed + 1; io.write(('  FAIL  %s\n'):format(what)); end
end

local function defined(name)
    return src:find('function accessxi%.' .. name .. '%(') ~= nil;
end

local function called(name)
    -- A call that is not the definition line.
    for line in src:gmatch('[^\n]+') do
        if (line:find('accessxi%.' .. name) ~= nil
            and line:find('function accessxi%.' .. name .. '%(') == nil) then
            return true;
        end
    end
    return false;
end

for _, name in ipairs({ 'nav_zoneline_note_observed', 'nav_zoneline_complete_observed' }) do
    claim(defined(name), ('%s is defined'):format(name));
    claim(called(name), ('%s HAS A CALLER'):format(name));
end

-- The single choke point. Hooking the pollers alone missed the path that fires
-- first, which is exactly why nothing was recorded.
local reset_body = src:match('function accessxi%.nav_reset_zone_state%(reason, old_zone, new_zone%)(.-)\nend');
claim(reset_body ~= nil, 'nav_reset_zone_state was found');
claim(reset_body ~= nil and reset_body:find('nav_zoneline_note_observed') ~= nil,
    'the learner is hooked into nav_reset_zone_state, the choke point every zone change passes through');

-- It must NOT read nav_current_position: that field is nil by the time any
-- zone-change hook runs.
local note_body = src:match('function accessxi%.nav_zoneline_note_observed%(from_zone, to_zone%)(.-)\nend\n');
claim(note_body ~= nil, 'nav_zoneline_note_observed was found');
claim(note_body ~= nil and note_body:find('nav_last_position_by_zone') ~= nil,
    'the learner reads the per-zone position that survives the reset');
claim(note_body ~= nil and note_body:find('nav_current_position') == nil,
    'and never reads nav_current_position, which is cleared before it runs');

-- The per-zone position must actually be maintained somewhere.
claim(src:find('accessxi%.nav_last_position_by_zone%[zone_of%] = ') ~= nil,
    'the per-zone position is recorded whenever a position is stored');

-- The observed file has to be both written and read back.
claim(src:find('nav_zoneline_observed_path') ~= nil, 'the observed-edge file has a path');
claim(select(2, src:gsub('nav_zoneline_observed_path', '')) >= 3,
    'and it is referenced by the loader, the writer and the failure log');

io.write(('\n%d claims passed, %d failed\n'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

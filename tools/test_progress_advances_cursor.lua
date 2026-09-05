-- THE GAME'S OWN COUNTER IS EVIDENCE OF PROGRESS.
--
-- Live 2026-08-27, Chains of Promathia: the player watched two cutscenes, the
-- storyline counter went 110 -> 115, and the cursor sat on "Head to Lower
-- Delkfutt's Tower" -- somewhere they had been the day before. The zone arrival
-- that would have completed it happened at 19:37:30 and will never happen
-- again, so nothing could clear that step but the N key. "I already did that."
--
-- Cutscenes complete steps and emit no signal this addon can see. The counter
-- is the one thing that does move, and the server does not move it for nothing.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
string.fmt = string.format;

local nav = io.open(ADDON .. '/modules/mission_quest_navigation.lua'):read('*a');
local reader = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1;
    else failed = failed + 1; print('  FAIL  ' .. what); end
end

-- 1. It exists, and is called.
claim(nav:find('function accessxi.nav_mission_quest_advance_within_mission', 1, true) ~= nil,
    'the advance exists');
claim(reader:find('accessxi.nav_mission_quest_advance_within_mission,', 1, true) ~= nil,
    'and the progress handler calls it');

-- 2. THE SCOPE TRAP. It calls two FILE LOCALS, and in Lua 5.1 a local
--    referenced before its declaration compiles to a global read -- nil at
--    runtime, dying silently inside the pcall that wraps it. The first version
--    of this sat 800 lines above both.
local function line_of(hay, needle)
    local i = hay:find(needle, 1, true);
    if (i == nil) then return nil; end
    local _, n = hay:sub(1, i):gsub('\n', '');
    return n + 1;
end
local save_at = line_of(nav, 'local function save_cursor_action(');
local resolved_at = line_of(nav, 'local function resolved_progress_record(');
local helper_at = line_of(nav, 'function accessxi.nav_mission_quest_advance_within_mission');
claim(save_at ~= nil and resolved_at ~= nil and helper_at ~= nil,
    'all three are present');
claim(helper_at > save_at,
    'the advance is declared AFTER save_cursor_action, got ' .. tostring(helper_at)
    .. ' vs ' .. tostring(save_at));
claim(helper_at > resolved_at,
    'and after resolved_progress_record, got ' .. tostring(helper_at)
    .. ' vs ' .. tostring(resolved_at));

-- 3. ONE STEP PER RISE. A cursor that overshoots silently swallows steps the
--    player still has to do -- worse than one that lags, which merely repeats
--    an instruction they have already followed.
local from = nav:find('function accessxi.nav_mission_quest_advance_within_mission', 1, true);
local body = nav:sub(from, nav:find('\nend\n', from, true) or #nav);
claim(body:find('actions[index + 1]', 1, true) ~= nil,
    'it advances by exactly one');
claim(body:find('index >= #actions', 1, true) ~= nil,
    'and declines at the last step rather than running off the end');
claim(body:find('objective progress ADVANCED', 1, true) ~= nil,
    'and says so, so an unexpected advance is one grep');

-- 4. Only a RISE, and only within the SAME mission. A mission change is already
--    handled as a succession; re-advancing there would double-count.
local guard = reader:find('current_key == previous_key', 1, true);
claim(guard ~= nil, 'it only fires when the mission is unchanged');
claim(reader:find('(tonumber(value) or 0) > (tonumber(before) or 0)', 1, true) ~= nil,
    'and only when the counter actually rose');

print(('progress advances cursor: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

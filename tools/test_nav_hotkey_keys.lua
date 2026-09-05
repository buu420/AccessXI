-- EVERY KEY THE ADDON TELLS THE PLAYER TO PRESS MUST REACH AN ACTION.
--
-- N was wired into KEY_ORDER, VK, DIK_BY_VK and action_by_key -- and the
-- snapshot in accessxi.poll_nav_browser_hotkeys never sampled it, so
-- current_key could not return it and mark_step_done could not fire.
-- "mark_step_done" appeared ZERO times in a 956,000-line log. This test drives
-- the REAL module, and also reads the real caller to prove the key is sampled.
local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
local navigation = dofile(ADDON .. '/modules/navigation_hotkeys.lua');

local passed, failed = 0, 0;
local function claim(ok, what)
    if (ok) then passed = passed + 1;
    else failed = failed + 1; io.write(('  FAIL  %s\n'):format(what)); end
end

local EXPECTED = {
    -- I is state-dependent: it starts a route, or stops the one running.
    I = { start_route = true, stop_route = true, route_toggle = true },
    U = 'previous_category',
    O = 'next_category',
    J = 'previous_item',
    K = 'repeat_item',
    L = 'next_item',
    N = 'mark_step_done',
    G = 'open_guide',
}

-- 1. Every key in KEY_ORDER produces its action through the real poll.
for _, key in ipairs(navigation.KEY_ORDER) do
    local state = navigation.new_state();
    local snapshot = {
        foreground = true, chat_open = false, modifier_down = false,
        route_active = false, route_pending = false, now = 1000,
        keys = { [key] = true },
    };
    local action = navigation.poll(state, snapshot);
    local want = EXPECTED[key];
    local ok = (type(want) == 'table') and (want[action] == true) or (action == want);
    claim(ok, ('%s produces an action (got %s)'):format(key, tostring(action)));
end

-- 2. Every key has a virtual-key and a DirectInput scan code.
for _, key in ipairs(navigation.KEY_ORDER) do
    local vk = navigation.VK[key];
    claim(type(vk) == 'number' and vk > 0, ('%s has a virtual-key code'):format(key));
    claim(type(navigation.DIK_BY_VK[vk]) == 'number',
        ('%s has a DirectInput scan code'):format(key));
end

-- 3. THE CALLER MUST SAMPLE IT. This is the half that was missing: the module
--    was entirely correct and the snapshot simply had no N in it.
local reader = io.open(ADDON .. '/accessxi_reader.lua', 'r');
local source = reader:read('*a');
reader:close();
local snapshot_block = source:match('local snapshot = {.-keys = {(.-)},');
claim(snapshot_block ~= nil, 'the nav hotkey snapshot block was found');
if (snapshot_block ~= nil) then
    for _, key in ipairs(navigation.KEY_ORDER) do
        claim(snapshot_block:find('%f[%w]' .. key .. '%s*=') ~= nil,
            ('the caller samples %s'):format(key));
    end
end

io.write(('\n%d claims passed, %d failed\n'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

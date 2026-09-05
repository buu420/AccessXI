-- A WINDOW THE PLAYER CANNOT HEAR IS A WINDOW THAT IS NOT THERE.
--
-- Live 2026-08-29 the player reported two silences in one message:
--
--   "when I open some of these treasure caskets, the items literally are silent
--    instead of speaking when I arrow over them"
--   "in the status menu pressing enter on a entry doesn't read it to me anymore
--    and it used to"
--
-- A four-agent sweep of the log found they were two of a class, and that the
-- class is bigger than either: 387 opens of menu    netbar with not one word
-- spoken, a login Yes/No that has been silent on 14 of 14 logins, six status
-- sub-windows that no build has ever had a reader for, and a defeat prompt that
-- speaks the name of the mob that killed you where the question should be.
--
-- This file pins the repairs. Every function is lifted verbatim out of the
-- DEPLOYED accessxi_reader.lua, so a claim here is a claim about what runs.
--
--   luajit tools/test_menu_never_silent.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';

_G.accessxi = {};
T = function (t)
    t = t or {};
    t.len = function (s) return #s; end
    t.append = function (s, v) s[#s + 1] = v; end
    return t;
end
string.fmt = string.format;
string.eq = function (s, other, ignore_case)
    if (ignore_case) then return tostring(s):lower() == tostring(other):lower(); end
    return tostring(s) == tostring(other);
end

local clock = 400000;
_G.tick = function () return clock; end
local spoken = {};
_G.speak = function (text) spoken[#spoken + 1] = tostring(text or ''); return 'ok'; end
_G.log_line = function () end
_G.log_state = function () end
_G.safe_call = function (fn, fallback)
    local ok, value = pcall(fn);
    if (ok) then return value; end
    return fallback;
end
accessxi.escape_probe_log_text = function (v) return tostring(v or ''); end
accessxi.survival_guide_text = function (v) return tostring(v or ''); end
accessxi.sentence_fragment = function (v) return tostring(v or ''); end

local passed, failed = 0, 0;
local function claim(cond, what)
    if (cond) then passed = passed + 1; print('  ok   ' .. what);
    else failed = failed + 1; print('  FAIL ' .. what); end
end

local src = io.open(ADDON .. '/accessxi_reader.lua'):read('*a');
local function lift(header)
    local from = src:find(header, 1, true);
    if (from == nil) then return nil; end
    local to = src:find('\nend\n', from, true);
    return to and src:sub(from, to + 4) or nil;
end
local function load_fn(header)
    local body = lift(header);
    claim(body ~= nil, 'lifted ' .. header:sub(1, 58));
    if (body ~= nil) then assert(load(body, 'lifted'))(); end
    return body;
end

-- ---------------------------------------------------------------------------
-- 1. THE CASKET. Every upgraded item in the game carries a plus, and a Treasure
--    Casket names its contents in exactly the short, article-prefixed form the
--    punctuation-soup clause was charging 60 points.
-- ---------------------------------------------------------------------------
load_fn('function accessxi.native_query_label_is_menu_structure(label)');
load_fn('function accessxi.native_query_label_fragment_penalty(label)');
load_fn('function accessxi.native_query_label_looks_real(label)');

for _, name in ipairs({ 'An Ether +1.', 'A Potion +3.', 'A Wool Hat.', 'An Axe +1.' }) do
    claim(accessxi.native_query_label_fragment_penalty(name) == 0,
        ('"%s" is an item name, penalty=%d'):fmt(
            name, accessxi.native_query_label_fragment_penalty(name)));
end
for _, garbage in ipairs({ "R5!d&'", 'x?!&', '3:v1 x', 'erf%1a' }) do
    claim(accessxi.native_query_label_fragment_penalty(garbage) >= 60,
        ('"%s" is still soup, penalty=%d'):fmt(
            garbage, accessxi.native_query_label_fragment_penalty(garbage)));
end

-- ---------------------------------------------------------------------------
-- 2. THE STATUS SUB-WINDOWS. Six of the eight have never had a reader in any
--    build; the other two -- Currencies and Unity -- are the only two that have
--    ever been observed open, so a list that omits them fixes nothing anyone
--    has seen.
-- ---------------------------------------------------------------------------
load_fn('function accessxi.is_status_submenu(name)');
load_fn('function accessxi.status_menu_remember_row(label, row_code)');
load_fn('function accessxi.status_detail_label_supported(label)');

for _, name in ipairs({ 'menu    btlskill', 'menu    mgcskill', 'menu    trdskill',
                        'menu    joblevel', 'menu    masterle', 'menu    profile',
                        'menu    evitem', 'menu    ut_menu' }) do
    claim(accessxi.is_status_submenu(name) == true,
        ('"%s" is a status sub-window'):fmt(name));
end
for _, name in ipairs({ 'menu    statcom2', 'menu    inventor', 'menu    magic',
                        'menu    netbar', '' }) do
    claim(accessxi.is_status_submenu(name) == false,
        ('"%s" is not'):fmt(name));
end

-- The row the player is standing on has to be remembered BEFORE Enter, because
-- once the sub-window is open statcom2 is gone and cannot answer for itself.
accessxi.status_menu_last_row_label = nil;
claim(accessxi.status_menu_remember_row('Combat Skills', 0x36) == true,
    'the arrowed row is remembered');
claim(accessxi.status_menu_last_row_label == 'Combat Skills'
    and accessxi.status_menu_last_row_code == 0x36,
    'with its label and row code');
claim(accessxi.status_menu_remember_row('', 0) == false,
    'and a blank row never overwrites a good one');
claim(accessxi.status_menu_last_row_label == 'Combat Skills',
    'so the last real row survives');
for _, label in ipairs({ 'Combat Skills', 'Magic Skills', 'Craft Skills',
                         'Job Levels', 'Master Levels', 'Profile', 'Unity' }) do
    claim(accessxi.status_detail_label_supported(label) == true,
        ('the existing reader already supports "%s"'):fmt(label));
end

-- STRUCTURAL: the schedule must be guarded on the TRANSITION, not on the window
-- being open. current_menu_speech runs about eight times a second, and an
-- unguarded call would re-read the whole skill summary every 1.5 seconds for as
-- long as the player left the window up.
claim(src:find('if (accessxi.is_status_submenu(name) and not previous_menu_name:eq(name, true)) then',
    1, true) ~= nil, 'the sub-window branch fires once per transition, not per poll');
claim(src:find("'status-submenu-open', 250", 1, true) ~= nil,
    'and it schedules the reader that already existed');
-- COMING BACK IS NOT OPENING. Escaping a sub-window re-opened statcom2 and
-- buried the row under the whole thirty-word status overview.
claim(src:find('if (not accessxi.is_status_submenu(previous_menu_name)) then', 1, true) ~= nil,
    'and returning from one does not re-recite the status overview');

-- ---------------------------------------------------------------------------
-- 3. THE UNCLAIMED WINDOW. It must say something -- and must never say it over
--    a reader that works.
-- ---------------------------------------------------------------------------
_G.is_chat_input_open = function () return false; end
local current_menu = 'menu    netbar';
_G.get_menu_name = function () return current_menu; end
_G.AshitaCore = {
    GetMemoryManager = function ()
        return { GetTarget = function () return { GetWindowName = function () return ''; end }; end };
    end,
};
load_fn('function accessxi.arm_unsupported_menu_voice(name)');
load_fn('function accessxi.clear_unsupported_menu_voice()');
load_fn('function accessxi.poll_unsupported_menu_voice()');

-- The window OPENING is what watermarks it. Arming happens later, the first
-- time current_menu_speech has nothing to add -- which for a window that reads
-- fine is simply the player pausing on a row they already heard, and is why the
-- first version of this fired on an open inventory.
local function open_window(name)
    accessxi.clear_unsupported_menu_voice();
    accessxi.unsupported_menu_voice_last_key = '';
    accessxi.unsupported_menu_voice_last_tick = 0;
    spoken = {};
    accessxi.last = 'something said before this window opened';
    accessxi.unsupported_menu_open_name = name;
    accessxi.unsupported_menu_open_last = tostring(accessxi.last);
    current_menu = name;
end
local function rearm(name)
    open_window(name);
    return accessxi.arm_unsupported_menu_voice(name);
end

claim(rearm('menu    netbar') == true, 'an unclaimed window arms a last-resort line');
claim(accessxi.poll_unsupported_menu_voice() == false,
    'which does not fire immediately -- a real reader gets first refusal');
clock = clock + 800;
claim(accessxi.poll_unsupported_menu_voice() == true,
    'but does fire once nothing else has spoken');
claim(#spoken == 1 and spoken[1]:find('netbar', 1, true) ~= nil,
    ('naming the window: "%s"'):fmt(spoken[1] or ''));
claim(spoken[1]:find('not read yet', 1, true) ~= nil,
    'and saying plainly that its contents are not read');

-- SOMEBODY ELSE SPOKE AFTER IT ARMED. Whatever they said beats this.
clock = clock + 5000;
rearm('menu    magic');
accessxi.last = 'Cure. Restores HP.';
clock = clock + 800;
claim(accessxi.poll_unsupported_menu_voice() == false,
    'a window whose rows are read by another subsystem is never talked over');
claim(#spoken == 0, 'and nothing is spoken for it at all');

-- THE REGRESSION THIS SHIPPED WITH. An OPEN window that has already read rows
-- and then goes quiet -- the player pausing on a row -- must never arm at all.
-- Live 2026-08-29 21:33:02 the fallback announced itself over an inventory that
-- was reading items seconds either side of it.
clock = clock + 5000;
open_window('menu    inventor');
accessxi.last = 'Hare Meat. This meat is from a small wild rabbit.';
claim(accessxi.arm_unsupported_menu_voice('menu    inventor') == false,
    'a window that has spoken since it opened never arms the fallback');
clock = clock + 800;
claim(accessxi.poll_unsupported_menu_voice() == false, 'and never fires');
claim(#spoken == 0, 'so an idle inventory is left alone');

-- THE WINDOW CLOSED while we waited.
clock = clock + 5000;
rearm('menu    netbar');
current_menu = 'menu    inventor';
clock = clock + 800;
claim(accessxi.poll_unsupported_menu_voice() == false,
    'a window that closed before the line was due is dropped');
current_menu = 'menu    netbar';

-- AND IT NEVER SPEAKS A TARGET NAME AS A WINDOW TITLE. GetWindowName() is the
-- TARGET window, so with a player selected it hands back another character's
-- name -- and this line spoke "Achantere, T.K." twice on 2026-08-29 as if that
-- were what had just opened. A name sounds like an answer; a menu id does not.
clock = clock + 5000;
_G.AshitaCore = {
    GetMemoryManager = function ()
        return { GetTarget = function ()
            return { GetWindowName = function () return 'Achantere, T.K.'; end };
        end };
    end,
};
rearm('menu    itmsortw');
clock = clock + 800;
claim(accessxi.poll_unsupported_menu_voice() == true, 'an unclaimed window still fires');
claim(#spoken == 1 and spoken[1]:find('Achantere', 1, true) == nil,
    ('and never borrows the target name: "%s"'):fmt(spoken[1] or ''));
claim(spoken[1]:find('itmsortw', 1, true) ~= nil,
    'it names the menu id, which is something the player can report');
claim(src:find('GetWindowName', 1, true) == nil
    or src:find('local spoken_name = armed:gsub', 1, true) ~= nil,
    'and the fallback no longer reads a window name at all');

-- STRUCTURAL: armed at the terminal branch, polled after poll_menu.
claim(src:find('accessxi.arm_unsupported_menu_voice(name);', 1, true) ~= nil,
    'the terminal branch arms it instead of returning silence');
claim(src:find('    poll_menu();\n    accessxi.poll_unsupported_menu_voice();', 1, true) ~= nil,
    'and it is polled AFTER poll_menu, so a real row always wins the race');

-- ---------------------------------------------------------------------------
-- 4. THE DEFEAT PROMPT. Being told a mob name where a question is asked is
--    worse than being told nothing, because it sounds like an answer.
-- ---------------------------------------------------------------------------
load_fn('function accessxi.generic_comyn_prompt_from_context(ctx)');

local prompt, label, source = accessxi.generic_comyn_prompt_from_context({
    label = '', source_menu = 'menu    playermo',
    window_name = "Gigas's Leech", transition_from = 'menu    dead', tick = clock,
});
claim(label:find('defeated', 1, true) ~= nil,
    ('a comyn arriving from the death menu says the player died: "%s"'):fmt(label));
claim(label:find("Gigas's Leech", 1, true) == nil,
    'and not the name of what killed them');
claim(prompt:find('Home Point', 1, true) ~= nil,
    ('and names the question being asked: "%s"'):fmt(prompt));
claim(source:find('inferred', 1, true) ~= nil,
    'marked inferred, because the game string has not been located yet');

-- Every other confirmation is untouched.
local p2, l2 = accessxi.generic_comyn_prompt_from_context({
    label = 'Shut Down', source_menu = 'menu    socialme', window_name = '', tick = clock,
});
claim(p2 == 'Shut down?' and l2 == 'Shut Down', 'Shut Down still reads as before');
-- THE TARGET WINDOW IS THE LAST RESORT, NOT THE FIRST.
--
-- ctx.window_name is GetWindowName() on the target manager, so it is whatever
-- the player has SELECTED -- which is how a death prompt came to be read out as
-- "Gigas's Leech". The death case was special-cased; every other confirmation
-- still ran through the same field. A title the addon knows for the menu, and
-- then the row the player actually just chose, both beat a name it happened to
-- find selected.
accessxi.native_known_menu_title = function (menu_name)
    if (tostring(menu_name) == 'menu    auc3') then return 'Auction House'; end
    return '';
end
local p3, l3, s3 = accessxi.generic_comyn_prompt_from_context({
    label = 'pinch of prism powder. Bid.', source_menu = 'menu    auc3',
    window_name = 'Ranperre, T.K.', transition_from = 'menu    moneyctr', tick = clock,
});
claim(l3 == 'Auction House' and s3 == 'known-title',
    ('a menu we know the title of is named by it, not by the target: "%s"'):fmt(l3));

-- With no known title, the row the player just chose carries the meaning. That
-- is the case the function's own header was written for: on 2026-08-23 an
-- auction bid confirmation said nothing while label="pinch of prism powder.
-- Bid. Place..." sat in the captured context.
accessxi.native_known_menu_title = function () return ''; end
local p4, l4, s4 = accessxi.generic_comyn_prompt_from_context({
    label = 'pinch of prism powder. Bid.', source_menu = 'menu    auc3',
    window_name = 'Ranperre, T.K.', transition_from = 'menu    moneyctr', tick = clock,
});
claim(l4 == 'pinch of prism powder. Bid.' and s4 == 'last-native',
    ('otherwise the chosen row carries it: "%s"'):fmt(l4));
claim(l4:find('Ranperre', 1, true) == nil, 'and never the selected target');

-- The target window is still better than nothing, which is what it is for.
local p5, l5, s5 = accessxi.generic_comyn_prompt_from_context({
    label = '', source_menu = 'menu    auc3',
    window_name = 'Auction House', transition_from = 'menu    moneyctr', tick = clock,
});
claim(l5 == 'Auction House' and s5 == 'window',
    'with nothing else to go on it is still used, rather than going silent');

-- ---------------------------------------------------------------------------
-- 5. THE STORAGE + MENU. The player: "The plus menu in the storage doesn't
--    work, so when I press plus that menu isn't reading." Pressing + in a
--    container opens menu    itmsortw and then menu    sortyn, a Yes/No. The
--    name itmsortw appeared in ZERO lines of Lua, so four separate allowlists
--    rejected it, and the confirmation was locked out twice over -- once for
--    having no cached label, once for not listing itmsortw as a window a sort
--    may arrive from. Arrowing between Yes and No produced nothing.
-- ---------------------------------------------------------------------------
do
    local menus = dofile(ADDON .. '/modules/menus/native_menus.lua');
    local titled = false;
    for _, row in ipairs((type(menus) == 'table' and menus.fixed_titles) or {}) do
        for _, name in ipairs(row.menus or {}) do
            if (tostring(name) == 'menu    itmsortw' and tostring(row.title) == 'Sort') then
                titled = true;
            end
        end
    end
    claim(titled, 'the container sort window has a title');

    -- All four gates, each of which alone is enough to silence it.
    local gates = {
        { "and not menu_name:eq('menu    itmsortw', true)",
          'the sort reader admits it' },
        { "or menu_name:eq('menu    itmsortw', true)",
          'and the dispatcher routes to it' },
        { "transition_from:eq('menu    itmsortw', true)",
          'and the Yes/No accepts a sort that came from it' },
    };
    for _, gate in ipairs(gates) do
        claim(src:find(gate[1], 1, true) ~= nil, gate[2]);
    end
    local dispatch = 0;
    for _ in src:gmatch("or menu_name:eq%('menu    itmsortw', true%)") do
        dispatch = dispatch + 1;
    end
    claim(dispatch == 2,
        ('both dispatcher sites route it -- cursor read and reader call, got %d'):fmt(dispatch));

    -- A cached label lives 120 seconds and now has more than one window that
    -- could have produced it, so it has to say which.
    claim(src:find('accessxi.current_item_sort_menu_name = menu_name;', 1, true) ~= nil,
        'the cached sort label records the window that produced it');
    claim(src:find("return nil, 'item-sort-context-from-another-window';", 1, true) ~= nil,
        'and a label from a different sort window is refused, not spoken');
end

print('');
print(('menu never silent: %d passed, %d failed'):fmt(passed, failed));
os.exit(failed == 0 and 0 or 1);

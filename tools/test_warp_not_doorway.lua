-- A WARP IS NOT A DOORWAY.
--
-- The observed-zoneline learner exists because scripted exits are real and
-- LandSandBoat does not list them -- the player walked out of Chateau
-- d'Oraguille through an NPC and the addon had no idea that road existed. But
-- it recorded every zone change alike, and a Home Point, a Survival Guide and a
-- ferry all change zone.
--
-- Of the SIXTEEN transitions it had learned, FIFTEEN were warps: Qufim ->
-- Southern San d'Oria, Sauromugue -> Southern San d'Oria, Lower Delkfutt's
-- Tower -> La Theine Plateau. Each became an edge the router could plan
-- through, so a player could be sent down a road that only exists if they own
-- that Home Point. The player raised this weeks before it was fixed: "a user
-- doesn't try to navigate to a mission and it tells them to use a homepoint
-- warp they might not have."
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

local clock = 500000;
_G.tick = function () return clock; end

_G.log_line = function () end
accessxi.escape_probe_log_text = function (v) return tostring(v or ''); end
string.fmt = string.format;

for _, header in ipairs({
    'function accessxi.nav_note_warp_intent(title)',
    'function accessxi.nav_note_relocation_item_action(action)',
    'function accessxi.nav_note_death_relocation(reason, zone)',
    'function accessxi.nav_clear_death_relocation(reason)',
    'function accessxi.nav_death_relocation_pending(now)',
    'function accessxi.nav_zoneline_observed_warp_recent(now)',
}) do
    local body = lift(header);
    claim(body ~= nil, 'lifted ' .. header:sub(1, 52));
    if (body ~= nil) then assert(load(body, 'warp'))(); end
end

-- 3b. A WARP ITEM HAS NO WARP-TITLED MENU.
--
--     Live 2026-08-31 in Promyvion - Holla, the player used item 28540.  The
--     native action was actor=self, cmd=9, result.value=28540, message=28;
--     thirteen seconds later the learner banked Holla -> Southern San d'Oria
--     as a walked road.  The inventory menu is titled "Use", so title matching
--     can never see this class.  The executed action is the evidence.
accessxi.combat_player_server_id = function () return 0x00067CC4; end
accessxi.resource_item_info = function (id)
    if (tonumber(id) == 28540) then
        return { id = 28540, name = 'warp ring', description = 'Enchantment: Warp' };
    end
    return { id = tonumber(id) or 0, name = 'meat jerky', description = 'Food' };
end
accessxi.nav_warp_intent_tick = nil;
local warp_action = {
    m_uID = 0x00067CC4, cmd_no = 9,
    target = { {
        m_uID = 0x00067CC4,
        result = { { value = 28540, message = 28 } },
    } },
};
claim(accessxi.nav_note_relocation_item_action(warp_action) == true,
    'an executed Warp Ring stamps relocation intent');
claim(accessxi.nav_zoneline_observed_warp_recent(clock) == true,
    'the zone change after that action is not learned as a doorway');

accessxi.nav_warp_intent_tick = nil;
local food_action = {
    m_uID = 0x00067CC4, cmd_no = 9,
    target = { {
        m_uID = 0x00067CC4,
        result = { { value = 4376, message = 28 } },
    } },
};
claim(accessxi.nav_note_relocation_item_action(food_action) == false,
    'an ordinary self-used item does not suppress doorway learning');
claim(accessxi.nav_zoneline_observed_warp_recent(clock) == false,
    'ordinary item use leaves the next walked transition learnable');

accessxi.nav_warp_intent_tick = nil;
warp_action.m_uID = 0x12345678;
claim(accessxi.nav_note_relocation_item_action(warp_action) == false,
    'another actor using a relocation item cannot stamp this player');
warp_action.m_uID = 0x00067CC4;

-- 1. Every menu that can move you without walking stamps intent.
for _, title in ipairs({ 'Survival Guide', 'Home Point #3', 'Telepoint',
                         'Runic Portal', 'Airship', 'Ferry', 'Chocobo' }) do
    accessxi.nav_warp_intent_tick = nil;
    claim(accessxi.nav_note_warp_intent(title) == true, title .. ' stamps warp intent');
end

-- 2. An ordinary menu does not.
for _, title in ipairs({ 'Magic', 'Trade', 'Gate Guard', '', 'Cermet Door' }) do
    accessxi.nav_warp_intent_tick = nil;
    claim(accessxi.nav_note_warp_intent(title) == false,
        '"' .. title .. '" does not stamp warp intent');
end

-- 3. THE REGRESSION. A zone change soon after a warp menu is that menu's doing.
accessxi.nav_warp_intent_tick = nil;
accessxi.nav_note_warp_intent('Home Point #3');
claim(accessxi.nav_zoneline_observed_warp_recent(clock) == true,
    'a zone change right after a Home Point is a warp');
claim(accessxi.nav_zoneline_observed_warp_recent(clock + 29000) == true,
    'and still is twenty-nine seconds later');
claim(accessxi.nav_zoneline_observed_warp_recent(clock + 31000) == false,
    'but not thirty-one seconds later -- that is walking again');

-- 4. With no warp ever used, nothing is suppressed. The Chateau exit had to
--    survive, or the learner has no purpose.
accessxi.nav_warp_intent_tick = nil;
claim(accessxi.nav_zoneline_observed_warp_recent(clock) == false,
    'a player who has touched no warp menu is walking');

-- 4b. A DEATH IS A WARP THE PLAYER DID NOT CHOOSE.
--
--     Live 2026-08-29 this file went red because a purged warp row had come
--     back -- two of them. The player died in Promyvion - Holla at 15:14:33
--     ("Longrodvonhugen was defeated by the Wanderer") and again in Qufim
--     Island at 19:34, Home Pointed both times, and the learner banked
--     Promyvion - Holla -> Southern San d'Oria and Qufim Island -> Southern
--     San d'Oria as walkable exits. Neither road exists.
--
--     The guard could not have known. nav_note_warp_intent matches menu
--     TITLES, and the death window is titled with whatever killed you --
--     "Weeper", "Gigas's Leech". Dying is the one relocation with no warp
--     menu behind it.
accessxi.nav_warp_intent_tick = nil;
accessxi.nav_death_relocation_tick = nil;
claim(accessxi.nav_note_death_relocation('death-menu', 16) == true,
    'the death menu stamps a pending relocation');
claim(accessxi.nav_zoneline_observed_warp_recent(clock) == true,
    'and the zone change that follows a death is not a doorway');
claim(accessxi.nav_zoneline_observed_warp_recent(clock + 120000) == true,
    'two minutes later it is still not one -- a corpse waits for a raise');
claim(accessxi.nav_zoneline_observed_warp_recent(clock + 1500000) == true,
    'and twenty-five minutes later, because a clock is not what ends a death');
claim(accessxi.nav_note_death_relocation('death-menu', 16) == false,
    'a second death menu poll does not restamp and extend it');

--     One death, one relocation: whoever refuses the learn consumes the stamp,
--     so the walk taken after a raise is still learnable. Left set, the learner
--     would go quiet for the rest of the session.
claim(accessxi.nav_clear_death_relocation('consumed-by-relocation') == true,
    'the refusal consumes it');
claim(accessxi.nav_zoneline_observed_warp_recent(clock) == false,
    'and the next zone change is walking again');
claim(accessxi.nav_clear_death_relocation('consumed-by-relocation') == false,
    'and consuming an unarmed stamp is a no-op, not a second clear');

--     And it lets go on its own, for the death that is raised where it fell and
--     never produces a zone change at all.
accessxi.nav_death_relocation_tick = nil;
accessxi.nav_note_death_relocation('death-menu', 16);
claim(accessxi.nav_zoneline_observed_warp_recent(clock + 1799000) == true,
    'the corruption backstop holds for thirty minutes');
claim(accessxi.nav_zoneline_observed_warp_recent(clock + 1801000) == false,
    'and then lets go -- cleanup, never normal control flow');
claim(src:find('nav_death_relocation_release_if_alive', 1, true) ~= nil,
    'a raise where you fell releases it, on the ordinary poll');
claim(src:find("zone ~= (tonumber(accessxi.nav_death_relocation_zone) or 0)", 1, true) ~= nil,
    'and only in the zone the player died in, so a Home Point cannot self-clear');

--     The stamp must have a caller, or it is inert -- which is how the warp
--     guard itself shipped the first time.
local death_callers = 0;
for _ in src:gmatch('accessxi%.nav_note_death_relocation%(') do
    death_callers = death_callers + 1;
end
claim(death_callers >= 2,
    'and the reader actually calls it from the menu observer, mentions=' .. death_callers);
claim(src:find("reason:find('menu    dead', 1, true)", 1, true) ~= nil,
    'from the death menu specifically');

-- 5. THE DEAD-PATH GUARD. The stamp must have real callers, or the whole guard
--    is inert -- which is exactly how it was first written.
local callers = 0;
for _ in src:gmatch('accessxi%.nav_note_warp_intent%(title%)') do callers = callers + 1; end
claim(callers >= 1, 'the reader stamps it from a menu, callers=' .. callers);
local gq = io.open(ADDON .. '/modules/menus/generic_query.lua'):read('*a');
claim(gq:find('accessxi.nav_note_warp_intent(title)', 1, true) ~= nil,
    'and so does the generic query, where Survival Guides appear');
claim(src:find('accessxi.nav_zoneline_observed_warp_recent(tick())', 1, true) ~= nil,
    'and the learner actually consults it');

-- 6. The purge kept the real walked exit, and no WARP has been learned since.
--
--    This used to assert a row count of exactly one, which was true the day it
--    was written and is not the invariant. The learner is SUPPOSED to keep
--    learning: on 2026-08-29 it recorded 14 Hall of Transference -> 16
--    Promyvion - Holla, reached by examining the Large Apparatus. That is a
--    scripted exit like the Chateau d'Oraguille one -- anybody standing there
--    can use it -- and the log shows the real warp on the way IN, La Theine ->
--    Hall of Transference, being refused by the very rule under test. Counting
--    rows would have to be edited every time the addon does its job.
--
--    What must never come back are the fifteen purged rows: transitions a Home
--    Point, Survival Guide or ferry produced, which are roads only a player who
--    owns that warp can travel.
local PURGED_WARPS = {
    ['16\t230'] = true,
    ['126\t230'] = true, ['126\t231'] = true, ['126\t232'] = true,
    ['108\t230'] = true, ['117\t238'] = true, ['119\t238'] = true,
    ['127\t230'] = true, ['184\t230'] = true, ['184\t231'] = true,
    ['246\t230'] = true, ['246\t231'] = true, ['245\t231'] = true,
    ['102\t230'] = true, ['103\t230'] = true, ['104\t230'] = true,
};
local kept, warps, learned = 0, 0, 0;
for line in io.lines(ADDON .. '/data/ffxi-nav-zoneline-observed.tsv') do
    if (line:sub(1, 1) ~= '#' and line:match('%S')) then
        local f = {};
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = field; end
        if (f[2] == '233' and f[8] == '231') then
            kept = kept + 1;
        elseif (PURGED_WARPS[tostring(f[2]) .. '\t' .. tostring(f[8])]) then
            warps = warps + 1;
        else
            learned = learned + 1;
        end
    end
end
claim(kept == 1, "the walked Chateau d'Oraguille exit is kept, got " .. kept);
claim(warps == 0, 'and no purged warp row has come back, got ' .. warps);
print(('       (%d further transition(s) learned since; scripted exits, not warps)'):format(learned));

print(('warp is not a doorway: %d passed, %d failed'):format(passed, failed));
os.exit(failed == 0 and 0 or 1);

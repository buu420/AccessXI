-- Does finishing a mission register in EVERY storyline, or only the three
-- nations?
--
-- Until 2026-08-22 it was only the nations. The mission packet reports eleven
-- progress fields and the Aht Urhgan packet four more; exactly one,
-- nation_mission, was ever compared for a change. Finishing a Rise of the
-- Zilart, Chains of Promathia, Treasures of Aht Urhgan, Wings of the Goddess,
-- Seekers of Adoulin or Rhapsodies of Vana'diel mission produced no signal at
-- all. The user asked exactly this: "Same with every other nation, ROV,
-- treasures, chains, zilart, you get the idea."
--
-- Driven against the REAL shipped guide index, because the whole point is that
-- a progress value maps to a mission by lookup and not by arithmetic.
--
--   luajit tools/test_mission_progress_tracker.lua
--
-- Exit code 1 on any failed claim.

local ADDON = os.getenv('ACCESSXI_ADDON') or 'C:/Users/buu42/Ashita/addons/accessxi_reader';
accessxi = {};
T = function (t) t = t or {}; t.len = function (s) return #s end; t.append = function (s, v) s[#s + 1] = v end; return t end;
string.fmt = string.format;

local tracker = dofile(ADDON .. '/modules/mission_progress_tracker.lua');
local index = dofile(ADDON .. '/modules/mission_quest_guide_index.lua');

local claims, failed = 0, 0;
local function claim(ok, text)
    claims = claims + 1;
    print((ok and '  ok   %s' or '  FAIL %s'):format(text));
    if (not ok) then failed = failed + 1; end
end

-- every storyline is present in the shipped index ----------------------------
local STORYLINES = {
    "San d'Oria", 'Bastok', 'Windurst', 'Rise of the Zilart',
    'Chains of Promathia', 'Treasures of Aht Urhgan', 'Wings of the Goddess',
    'Seekers of Adoulin', "Rhapsodies of Vana'diel", 'The Voracious Resurgence',
    'Assault', 'Campaign', 'A Crystalline Prophecy', "A Moogle Kupo d'Etat",
    'A Shantotto Ascension',
};
do
    local counts = {};
    for _, record in pairs(index) do
        if (type(record) == 'table' and tostring(record.kind):lower() == 'mission') then
            local ctx = tostring(record.context or '');
            counts[ctx] = (counts[ctx] or 0) + 1;
        end
    end
    local missing = {};
    for _, ctx in ipairs(STORYLINES) do
        if ((counts[ctx] or 0) == 0) then missing[#missing + 1] = ctx; end
    end
    claim(#missing == 0, 'the shipped guide index covers every storyline ('
        .. (#missing == 0 and 'all 15' or table.concat(missing, ', ')) .. ')');
end

print('');
print('A progress value names its mission by LOOKUP, because no offset survives:');
-- Rise of the Zilart native ids run 1, 3, 5 against progress 0, 2, 4.
do
    local key, native = tracker.native_key_for_progress(index, 'Rise of the Zilart', 0);
    claim(key == 'mission:Rise of the Zilart:1' and native == 1,
        'Zilart progress 0 is mission 1 (' .. tostring(key) .. ')');
    key, native = tracker.native_key_for_progress(index, 'Rise of the Zilart', 2);
    claim(key == 'mission:Rise of the Zilart:3' and native == 3,
        'Zilart progress 2 is mission THREE, not two -- the ids skip (' .. tostring(key) .. ')');
end
do
    local key = tracker.native_key_for_progress(index, "San d'Oria", 4);
    claim(key == "mission:San d'Oria:5",
        'San d\'Oria progress 4 is The Davoi Report (' .. tostring(key) .. ')');
end
do
    local key = tracker.native_key_for_progress(index, 'Chains of Promathia', 101);
    claim(key == 'mission:Chains of Promathia:1',
        'Chains of Promathia progress 101 is its first mission (' .. tostring(key) .. ')');
end

print('');
print('A value that names more than one mission names none:');
do
    -- Seekers of Adoulin 1 and 2 both carry progress_id 110.
    local key = tracker.native_key_for_progress(index, 'Seekers of Adoulin', 110);
    claim(key == '', 'an ambiguous Adoulin value is refused rather than guessed at');
    claim(tracker.native_key_for_progress(index, 'Rise of the Zilart', 99999) == '',
        'and so is a value no mission claims');
    claim(tracker.native_key_for_progress(index, 'Not A Storyline', 0) == '',
        'and a storyline that does not exist');
    claim(tracker.native_key_for_progress(nil, 'Bastok', 0) == '',
        'and a missing index never throws');
end

print('');
print('Only the NEXT mission is a completion:');
do
    claim(tracker.is_direct_successor(index, 'Rise of the Zilart', 1, 3),
        'Zilart 1 to 3 is direct -- there is no mission 2 in between');
    claim(not tracker.is_direct_successor(index, 'Rise of the Zilart', 1, 5),
        'Zilart 1 to 5 skips mission 3, so it is not a completion');
    claim(tracker.is_direct_successor(index, "San d'Oria", 5, 6),
        'The Davoi Report to Journey Abroad is direct');
    claim(not tracker.is_direct_successor(index, "San d'Oria", 6, 5),
        'and going backwards is never a completion');
    claim(not tracker.is_direct_successor(index, "San d'Oria", 5, 5),
        'nor is standing still');
end

print('');
print('Only a storyline present on BOTH sides can have moved:');
do
    local moved = tracker.diff(
        { ["San d'Oria"] = 4, ['Rise of the Zilart'] = 0 },
        { ["San d'Oria"] = 5, ['Rise of the Zilart'] = 0 });
    claim(#moved == 1 and moved[1].context == "San d'Oria"
        and moved[1].before == 4 and moved[1].after == 5,
        'the one that changed is reported, the one that did not is silent');
    moved = tracker.diff({}, { ['Chains of Promathia'] = 101 });
    claim(#moved == 0,
        'a storyline seen for the first time is a baseline, not a mission that just changed');
    moved = tracker.diff({ ['Chains of Promathia'] = 101 }, {});
    claim(#moved == 0,
        'and one we can no longer read is silence, not progress');
    moved = tracker.diff(
        { ['Bastok'] = 1, ['Seekers of Adoulin'] = 110 },
        { ['Bastok'] = 2, ['Seekers of Adoulin'] = 112 });
    claim(#moved == 2, 'two storylines moving at once are both reported');
    claim(moved[1].context == 'Bastok' and moved[2].context == 'Seekers of Adoulin',
        'in a stable order, so the log reads the same way twice');
end

print('');
print('A value BETWEEN two missions is the earlier one, part done:');
do
    -- Live 2026-08-27: the player watched two Chains of Promathia cutscenes and
    -- the field went 110 -> 115. CoP starts its missions at 101, 110, 118, 128,
    -- so there is no mission at 115 -- an exact match found nothing, the change
    -- was reported with current="" and the tracker went on showing The Rites of
    -- Life an hour later. "I've gotten 2 cut scenes now and neither one have
    -- updated the mission progress."
    local key, id, exact = tracker.native_key_for_progress(index, 'Chains of Promathia', 110);
    claim(key == 'mission:Chains of Promathia:2' and exact == true,
        'a starting value resolves exactly');
    key, id, exact = tracker.native_key_for_progress(index, 'Chains of Promathia', 115);
    claim(key == 'mission:Chains of Promathia:2',
        'and 115 is The Rites of Life partway through, got ' .. tostring(key));
    claim(exact == false, 'reported as inside the mission, not at its start');
    key = tracker.native_key_for_progress(index, 'Chains of Promathia', 117);
    claim(key == 'mission:Chains of Promathia:2', 'so is 117, still before 118');
    key, id, exact = tracker.native_key_for_progress(index, 'Chains of Promathia', 118);
    claim(key == 'mission:Chains of Promathia:3' and exact == true,
        'and 118 starts the next mission exactly');

    -- The bound. Being above a start is not enough, or any number resolves to
    -- the last mission in the storyline.
    claim(tracker.native_key_for_progress(index, 'Chains of Promathia', 1) == '',
        'a value below every mission still refuses');
    claim(tracker.native_key_for_progress(index, 'Rise of the Zilart', 99999) == '',
        'and a nonsense value far above them all still refuses');
end

print('');
print('Every storyline can be resolved, not just the nations:');
do
    local resolved, total = 0, 0;
    for _, ctx in ipairs(STORYLINES) do
        local ids = {};
        for _, record in pairs(index) do
            if (type(record) == 'table' and tostring(record.kind):lower() == 'mission'
                and tostring(record.context or '') == ctx) then
                ids[#ids + 1] = tonumber(record.progress_id) or -1;
            end
        end
        for _, pid in ipairs(ids) do
            total = total + 1;
            if (tracker.native_key_for_progress(index, ctx, pid) ~= '') then
                resolved = resolved + 1;
            end
        end
    end
    claim(total > 600 and resolved > 0.97 * total,
        ('%d of %d mission progress values across all storylines resolve to exactly one mission'):format(
            resolved, total));
end

print('');
print(('claims=%d failed=%d'):format(claims, failed));
os.exit(failed == 0 and 0 or 1);

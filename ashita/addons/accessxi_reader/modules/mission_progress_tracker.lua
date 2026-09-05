-- Which mission a storyline's progress value denotes, and whether it moved.
--
-- Why this exists (2026-08-22). The mission packet reports eleven progress
-- fields -- nation, nation_mission, zilart, cop, cop_status, addons, tales,
-- soa, rov, port -- and the Aht Urhgan packet reports assault, toau, wotg and
-- campaign on top. Exactly ONE of them, nation_mission, was ever compared for a
-- change. Finishing a Rise of the Zilart, Chains of Promathia, Treasures of Aht
-- Urhgan, Wings of the Goddess, Seekers of Adoulin or Rhapsodies of Vana'diel
-- mission therefore produced no signal of any kind, and the player was told
-- nothing. The user asked precisely this: "Same with every other nation, ROV,
-- treasures, chains, zilart, you get the idea."
--
-- None of the data was missing. `accessxi.mission_rom_tables` already names the
-- packet field for all sixteen storylines and
-- `accessxi.current_mission_value_for_context` already reads any of them,
-- including the acp/mkd/asa values bit-packed into `addons`. Only the
-- comparison, and the lookup from a progress value back to a mission, were
-- absent.
--
-- Pure: the guide index and the two snapshots come in as arguments, so this
-- runs identically under the addon and under an offline LuaJIT harness.

local M = {};

local function clean(value)
    value = tostring(value or ''):gsub('[\t\r\n]', ' '):gsub('%s+', ' ');
    return (value:gsub('^%s+', ''):gsub('%s+$', ''));
end

local function is_mission(record, context)
    return type(record) == 'table'
        and clean(record.kind):lower() == 'mission'
        and clean(record.context) == context;
end

-- A LOOKUP, NOT ARITHMETIC.
--
-- Rise of the Zilart's native ids run 1, 3, 5 against progress values 0, 2, 4;
-- no offset survives that, and guessing one would name the wrong mission. The
-- guide index records `progress_id` for every mission, so ask it.
--
-- A value that names more than one mission names none. That is 5 of Seekers of
-- Adoulin's 112 and 3 of Rhapsodies of Vana'diel's 98; for the other thirteen
-- storylines every value is unique. We do not pick between them.
function M.native_key_for_progress(index, context, progress_id)
    context = clean(context);
    progress_id = tonumber(progress_id);
    if (context == '' or progress_id == nil or type(index) ~= 'table') then
        return '', 0;
    end
    local found, native_id, count = '', 0, 0;
    for native_key, record in pairs(index) do
        if (is_mission(record, context) and tonumber(record.progress_id) == progress_id) then
            count = count + 1;
            found, native_id = native_key, tonumber(record.native_id) or 0;
        end
    end
    if (count == 1) then
        return found, native_id, true;
    end
    if (count > 1) then
        return '', 0, false;        -- ambiguous; we do not pick between them
    end

    -- A VALUE BETWEEN TWO MISSIONS IS THE EARLIER ONE, PART DONE.
    --
    -- The index records the value each mission STARTS at, and the field keeps
    -- counting while the player works through it. Chains of Promathia starts
    -- its missions at 101, 110, 118, 128; live 2026-08-27 the player watched
    -- two cutscenes and the field went 110 -> 115. There is no mission at 115,
    -- so an exact match found nothing and the tracker reported
    -- current="" -- it had no mission at all, and went on showing The Rites of
    -- Life an hour later. The player: "I've gotten 2 cut scenes now and neither
    -- one have updated the mission progress."
    --
    -- 115 is not a new mission, it is The Rites of Life partway through. The
    -- mission with the greatest starting value at or below the current one is
    -- the one being played.
    --
    -- Still refuses to guess: the candidate must be unique, exactly as an exact
    -- match must be. The third return says whether the value landed on a
    -- mission's start or inside it, so a caller can tell "you have begun
    -- something new" from "you are further into this one".
    local best_key, best_id, best_progress, best_count = '', 0, nil, 0;
    local next_start = nil;
    for native_key, record in pairs(index) do
        if (is_mission(record, context)) then
            local candidate = tonumber(record.progress_id);
            if (candidate ~= nil and candidate <= progress_id) then
                if (best_progress == nil or candidate > best_progress) then
                    best_key, best_id, best_progress, best_count = native_key,
                        tonumber(record.native_id) or 0, candidate, 1;
                elseif (candidate == best_progress) then
                    best_count = best_count + 1;
                end
            elseif (candidate ~= nil
                and (next_start == nil or candidate < next_start)) then
                next_start = candidate;     -- the next mission's starting value
            end
        end
    end
    if (best_progress == nil or best_count ~= 1) then
        return '', 0, false;
    end
    -- BOUND IT, OR ANY NUMBER RESOLVES TO THE LAST MISSION.
    --
    -- Being above a mission's start is not enough: 99999 is above every Rise of
    -- the Zilart value and means nothing at all. A value is INSIDE a mission
    -- only if the next mission has not started yet. Where there is no next
    -- mission -- the player is in the final one -- fall back to a window, since
    -- observed intra-mission ranges are well under ten (Chains of Promathia
    -- starts at 101, 110, 118, 128) and twenty is generous without admitting
    -- nonsense.
    if (next_start ~= nil) then
        if (progress_id >= next_start) then
            return '', 0, false;
        end
    elseif ((progress_id - best_progress) > 20) then
        return '', 0, false;
    end
    return best_key, best_id, false;
end

-- Is this the mission immediately after that one, in the guide's own ordering?
-- Asked of the ordering rather than of the numbers, because the numbers have
-- gaps: Zilart 1 is directly followed by Zilart 3.
--
-- Only a direct successor is a completion. A jump, a repeat, or a storyline we
-- could not name is "the active mission changed" and must never be announced as
-- a completion the player did not earn (sol).
function M.is_direct_successor(index, context, previous_id, native_id)
    context = clean(context);
    previous_id = tonumber(previous_id) or 0;
    native_id = tonumber(native_id) or 0;
    if (context == '' or previous_id <= 0 or native_id <= previous_id
        or type(index) ~= 'table') then
        return false;
    end
    for _, record in pairs(index) do
        if (is_mission(record, context)) then
            local id = tonumber(record.native_id) or 0;
            if (id > previous_id and id < native_id) then
                return false;
            end
        end
    end
    return true;
end

-- What moved between two snapshots. A storyline absent from either side is not
-- a change: it means we could not read it, which is silence, not progress.
function M.diff(previous, current)
    local moved = {};
    if (type(previous) ~= 'table' or type(current) ~= 'table') then
        return moved;
    end
    for context, value in pairs(current) do
        local before = previous[context];
        if (before ~= nil and tonumber(before) ~= tonumber(value)) then
            moved[#moved + 1] = {
                context = context,
                before = tonumber(before) or 0,
                after = tonumber(value) or 0,
            };
        end
    end
    table.sort(moved, function (a, b) return a.context < b.context; end);
    return moved;
end

if (type(accessxi) == 'table') then
    accessxi.mission_progress_tracker = M;
end
return M;

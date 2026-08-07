local quick = {}

local key_order = { 'D', 'B', 'H', 'M', 'X' }
local action_by_key = {
    D = 'debuffs',
    B = 'buffs',
    H = 'hp',
    M = 'mp',
    X = 'experience',
}
quick.VK = {
    D = 0x44,
    B = 0x42,
    H = 0x48,
    M = 0x4D,
    X = 0x58,
}
quick.DIK_BY_VK = {
    [0x44] = 0x20,
    [0x42] = 0x30,
    [0x48] = 0x23,
    [0x4D] = 0x32,
    [0x58] = 0x2D,
}
local hotkey_virtual_keys = {
    [0x44] = true,
    [0x42] = true,
    [0x48] = true,
    [0x4D] = true,
    [0x58] = true,
}

local debuff_ids = {}
local reviewed_buff_ids = {}
local invalid_status_ids = {}

local function add_id(set, id)
    set[id] = true
end

local function add_ids(set, values)
    for _, id in ipairs(values) do
        set[id] = true
    end
end

local function add_range(set, first, last)
    for id = first, last do
        set[id] = true
    end
end

-- Retail detrimental effects verified against the installed English status DAT
-- and current LandSandBoat status definitions. These are IDs only; spoken names
-- always come from the running game's resource manager.
add_range(debuff_ids, 0, 23)
add_range(debuff_ids, 28, 31)
add_range(debuff_ids, 128, 149)
add_ids(debuff_ids, {
    155, 156, 157, 158, 159, 160,
    167, 168, 174, 175, 177, 186, 189,
    192, 193, 194, 217, 223,
})
add_range(debuff_ids, 259, 264)
add_ids(debuff_ids, { 291, 298, 299, 309 })
add_range(debuff_ids, 372, 374)
add_range(debuff_ids, 378, 380)
add_range(debuff_ids, 386, 400)
add_id(debuff_ids, 404)
add_range(debuff_ids, 448, 452)
add_ids(debuff_ids, { 473, 496, 509, 536, 540 })
add_range(debuff_ids, 557, 567)
add_ids(debuff_ids, { 571, 572, 576, 597, 614 })
add_range(debuff_ids, 630, 633)

-- Reviewed beneficial or neutral player statuses that are not reliably marked
-- cancellable in the native status metadata (songs, rolls, favors, geomancy,
-- battlefield state, job modes, and similar visible status icons).
add_range(reviewed_buff_ids, 32, 127)
add_range(reviewed_buff_ids, 150, 154)
add_range(reviewed_buff_ids, 161, 166)
add_range(reviewed_buff_ids, 169, 173)
add_id(reviewed_buff_ids, 176)
add_range(reviewed_buff_ids, 178, 185)
add_range(reviewed_buff_ids, 187, 188)
add_range(reviewed_buff_ids, 190, 191)
add_range(reviewed_buff_ids, 195, 216)
add_range(reviewed_buff_ids, 218, 222)
add_range(reviewed_buff_ids, 224, 231)
add_range(reviewed_buff_ids, 233, 254)
add_range(reviewed_buff_ids, 256, 258)
add_range(reviewed_buff_ids, 265, 290)
add_range(reviewed_buff_ids, 292, 297)
add_range(reviewed_buff_ids, 300, 308)
add_range(reviewed_buff_ids, 310, 371)
add_range(reviewed_buff_ids, 375, 377)
add_range(reviewed_buff_ids, 381, 385)
add_range(reviewed_buff_ids, 401, 403)
add_range(reviewed_buff_ids, 405, 447)
add_range(reviewed_buff_ids, 453, 472)
add_range(reviewed_buff_ids, 474, 495)
add_range(reviewed_buff_ids, 497, 508)
add_range(reviewed_buff_ids, 510, 513)
add_range(reviewed_buff_ids, 515, 519)
add_range(reviewed_buff_ids, 522, 535)
add_range(reviewed_buff_ids, 537, 539)
add_range(reviewed_buff_ids, 541, 556)
add_range(reviewed_buff_ids, 568, 570)
add_range(reviewed_buff_ids, 573, 575)
add_range(reviewed_buff_ids, 577, 596)
add_range(reviewed_buff_ids, 598, 613)
add_range(reviewed_buff_ids, 615, 629)
add_range(reviewed_buff_ids, 634, 635)

add_range(invalid_status_ids, 24, 27)
add_ids(invalid_status_ids, { 232, 255, 514, 520, 521 })
add_range(invalid_status_ids, 636, 767)

local function integer(value)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return math.floor(number)
end

local function clean_name(value)
    local name = tostring(value or '')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' or name == '.' or name:lower():find('debug:%s*please report', 1, false) ~= nil then
        return nil
    end
    return name
end

local function current_chord(snapshot)
    if type(snapshot.keys) ~= 'table' then
        return nil
    end
    for _, key in ipairs(key_order) do
        if snapshot.keys[key] == true then
            return key
        end
    end
    return nil
end

local function format_vital(label, current, maximum)
    current = integer(current)
    maximum = integer(maximum)
    if current == nil or maximum == nil or current < 0 or maximum < 0 then
        return nil
    end
    return ('%s %d of %d.'):format(label, current, maximum)
end

local function category_available(snapshot, field)
    if snapshot[field] ~= nil then
        return snapshot[field] == true
    end
    return snapshot.vitals_available == true
end

local function status_speech(snapshot, wanted)
    if snapshot.statuses_available ~= true or type(snapshot.statuses) ~= 'table' then
        if wanted == 'debuff' then
            return 'Debuff information unavailable.', { unknown_ids = {}, missing_name_ids = {} }
        end
        return 'Buff information unavailable.', { unknown_ids = {}, missing_name_ids = {} }
    end

    local names = {}
    local seen = {}
    local meta = { unknown_ids = {}, missing_name_ids = {} }
    local unknown_seen = {}
    local missing_seen = {}

    for _, entry in ipairs(snapshot.statuses) do
        if type(entry) == 'table' then
            local id = integer(entry.id)
            if id ~= nil and id >= 0 and not seen[id] then
                seen[id] = true
                local class = quick.classify_status(id, entry.can_cancel == true)
                if class == nil then
                    if not unknown_seen[id] then
                        unknown_seen[id] = true
                        meta.unknown_ids[#meta.unknown_ids + 1] = id
                    end
                elseif class == wanted then
                    local name = clean_name(entry.name)
                    if name ~= nil then
                        names[#names + 1] = name
                    elseif not missing_seen[id] then
                        missing_seen[id] = true
                        meta.missing_name_ids[#meta.missing_name_ids + 1] = id
                    end
                end
            end
        end
    end

    if #names == 0 then
        if wanted == 'debuff' then
            return 'No debuffs.', meta
        end
        return 'No buffs.', meta
    end
    if wanted == 'debuff' then
        return 'Debuffs: ' .. table.concat(names, ', ') .. '.', meta
    end
    return 'Buffs: ' .. table.concat(names, ', ') .. '.', meta
end

function quick.new_state()
    return { last_chord = nil }
end

function quick.is_hotkey_vk(value)
    return hotkey_virtual_keys[integer(value) or -1] == true
end

function quick.classify_status(id, can_cancel)
    id = integer(id)
    if id == nil or id < 0 or invalid_status_ids[id] then
        return nil
    end
    if debuff_ids[id] then
        return 'debuff'
    end
    if reviewed_buff_ids[id] or can_cancel == true then
        return 'buff'
    end
    return nil
end

function quick.poll(state, snapshot)
    if type(state) ~= 'table' or type(snapshot) ~= 'table' then
        return nil
    end

    local chord = current_chord(snapshot)
    if chord == nil then
        state.last_chord = nil
        return nil
    end
    if chord == state.last_chord then
        return nil
    end
    state.last_chord = chord

    if snapshot.foreground ~= true
        or snapshot.chat_open == true
        or snapshot.modifier_down == true then
        return nil
    end

    local action = action_by_key[chord]
    if action == 'hp' then
        if not category_available(snapshot, 'hp_available') then
            return 'HP information unavailable.', action
        end
        return format_vital('HP', snapshot.hp_current, snapshot.hp_max)
            or 'HP information unavailable.', action
    end
    if action == 'mp' then
        if not category_available(snapshot, 'mp_available') then
            return 'MP information unavailable.', action
        end
        return format_vital('MP', snapshot.mp_current, snapshot.mp_max)
            or 'MP information unavailable.', action
    end
    if action == 'experience' then
        if not category_available(snapshot, 'experience_available') then
            return 'Experience information unavailable.', action
        end
        local current = integer(snapshot.exp_current)
        local needed = integer(snapshot.exp_needed)
        if current == nil or needed == nil or current < 0 or needed < 0 then
            return 'Experience information unavailable.', action
        end
        local tnl = needed - current
        if tnl < 0 then
            tnl = 0
        end
        return ('Experience %d. TNL %d.'):format(current, tnl), action
    end
    if action == 'debuffs' then
        local text, meta = status_speech(snapshot, 'debuff')
        return text, action, meta
    end
    if action == 'buffs' then
        local text, meta = status_speech(snapshot, 'buff')
        return text, action, meta
    end
    return nil
end

return quick

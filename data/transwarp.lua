_addon.author = 'Ivaar'
_addon.name = 'Transwarp'
_addon.version = '0.0.0.4'
_addon.commands = {'tw'}

require('luau')
require('pack')

packets = require('packets')
alias = require('alias')

maps = {
    homepoints = require('homepoints'),
    survival_guides = require('survival_guides'),
    waypoints = require('waypoints'),
    confluxes = require('confluxes'),
    eschan_portals = require('eschan_portals'),
    proto_waypoints = require('proto_waypoints'),
    abyssea_warp = require('abyssea_warp'),
    runic_portal = require('runic_portals'),
    voidwatch = require('voidwatch'),
    unity = require('unity'),
}

local last_attempt = os.time() - 10

local send_all_delay = 1
local retry_delay = 3
local retry_limit = 5

local enable_injection = true
local queued = {}

local function build_packet(p)
    if enable_injection then
        packets.inject(p)
    elseif p._id ~= 0x1A and p._id ~= 0x114 then
        queued = queued or {}
        queued[#queued+1] = packets.build(p)
    end
end

local function build_dialog_option(p)
    return packets.new('outgoing', 0x05B, {
        ['Target'] = p['NPC'],
        ['Target Index'] = p['NPC Index'],
        ['Zone'] = p['Zone'],
        ['Menu ID'] = p['Menu ID'],
        ['Automated Message'] = true
    })
end

local function npc_warp_request(p, action, option)
    build_packet(  packets.new('outgoing', 0x05C, {
        ['Target ID'] = p['NPC'],
        ['Target Index'] = p['NPC Index'],
        ['Zone'] = p['Zone'],
        ['Menu ID'] = p['Menu ID'],
        ['X'] = action.x,
        ['Y'] = action.y,
        ['Z'] = action.z,
        ['_unknown1'] = option,
        ['_unknown2'] = 1,
        ['Rotation'] = action.rotation
    }))
end

local function interact_npc(target)
    last_attempt = os.time()
    notice('Initiating NPC Interaction: %s':format(target.name))
    packets.inject(  packets.new('outgoing', 0x01A, {['Target'] = target.id, ['Target Index'] = target.index}))
end

string.has_bit = function(data, position)
    return data:unpack('q', math.floor(position/8)+1, position%8+1)
end

math.has_bit = function(mask, offset)
    return math.floor(mask/2^offset)%2 == 1
end

local handled_menus = {}

handled_menus.homepoints = {
    npcs = S{'Home Point #1','Home Point #2','Home Point #3','Home Point #4','Home Point #5'},
    ids = S{8700,8701,8702,8703,8704},
    zones = S{230,231,232,234,235,236,237,238,239,240,241,243,244,245,246,250,249,252,247,248,256,257,261,262,265,263,266,267,142,143,
        145,204,208,160,162,130,26,50,53,80,87,94,158,178,29,52,79,5,7,9,12,30,33,34,35,61,113,153,205,137,281,155,126,169,276,25},
}

handled_menus.survival_guides = {
    npcs = S{'Survival Guide'},
    ids = S{8500,8501},
    zones = S{231,234,240,243,26,50,100,141,167,190,102,103,108,193,196,2,104,105,149,195,106,172,173,191,109,110,147,197,115,169,
        192,4,117,118,198,213,119,120,151,200,111,166,112,161,126,127,184,121,122,154,114,125,247,113,128,174,212,123,176,250,252,
        124,159,205,130,11,24,25,27,28,51,65,68,62,53,54,79,80,81,82,84,175,87,88,89,83,90,91,171,94,95,96,97,98,164,136,138,257},
}

handled_menus.waypoints = {
    npcs = S{'Waypoint'},
    zones = {
        [245] = S{10121},
        [256] = S{5000,5001,5002,5003,5004,5005,5006,5007,5008},
        [257] = S{5000,5001,5002,5003,5004,5005,5006,5007,5008},
        [260] = S{5000,5001,5002,5003},
        [261] = S{5000,5001,5002,5003},
        [262] = S{5000,5001,5002,5003,5004},
        [263] = S{5000,5001,5002,5003},
        [265] = S{5000,5001,5002,5003,5004,5005},
        [266] = S{5000,5001,5002,5003,5004},
        [267] = S{5000,5001,5002,5003,5004},
    },
}

handled_menus.proto_waypoints = {
    npcs = S{'Proto-Waypoint'},
    zones = {
        [243] = S{10209},
        [247] = S{141},
        [248] = S{10012},
        [249] = S{345},
        [252] = S{266},
    },
}

handled_menus.eschan_portals = {
    npcs = {
        ['Eschan Portal'] = true,
        ['Ethereal Ingress'] = true,
        contains = function(names, str)
            return names[str:gsub('[%#%d]', ''):trim()] == true
        end
    },

    ids = S{9100},
    zones = S{288,289,291},
}

handled_menus.confluxes = {
    npcs = {
        ['Veridical Conflux'] = true,
        contains = function(names, str)
            return names[str:sub(1, 17)] == true
        end
    },

    zones = {
        [15]  = S{2132,2133,2134,2135,2136,2137,2138,2139},
        [45]  = S{2132,2133,2134,2135,2136,2137,2138,2139},
        [132] = S{2132,2133,2134,2135,2136,2137,2138,2139},
        [215] = S{2132,2133,2134,2135,2136,2137,2138,2139,123},
        [216] = S{2132,2133,2134,2135,2136,2137,2138,2139,123},
        [217] = S{2132,2133,2134,2135,2136,2137,2138,2139,123},
        [218] = S{2132,2133,2134,2135,2136,2137,2138,2139},
        [253] = S{2132,2133,2134,2135,2136,2137,2138,2139},
        [254] = S{2132,2133,2134,2135,2136,2137,2138,2139},
    },
}

handled_menus.elvorseal = {
    npcs = S{'Affi', 'Dremi', 'Shiftrix'},
    ids = S{9701},
    zones = S{288,289,291},
}

handled_menus.unity = {
    npcs = S{'Urbiolaine', 'Igsli', 'Teldro-Kesdrodo', 'Nunaarl Bthtrogg'},
    zones = {
        [230] = S{3529},
        [235] = S{598},
        [241] = S{879},
        [256] = S{5149}
    },
}

handled_menus.voidwatch = {
    npcs = S{'Atmacite Refiner'},
    zones = {
        [80] = S{657},
        [230] = S{962},
    }
}

handled_menus.runic_portal = {
    npcs = S{'Runic Portal'},
    zones = {
        [50] = S{101},
        [52] = S{109},
        [54] = S{109},
        [61] = S{109},
        [72] = S{117,118},
        [79] = S{131,134},
    }
}

handled_menus.abyssea_warp = {
    npcs = S{'Horst', 'Ivan', 'Willis', 'Ernst', 'Vincent'},
    zones = {
        [232] = S{795},
        [236] = S{404},
        [240] = S{873},
        [243] = S{10185},
        [246] = S{339},
    }
}

handled_menus.enter = {
    npcs = S{'Undulating Confluence', 'Cavernous Maw', 'Dimensional Portal'},
    zones = {
        [25] = S{14},
        [126] = S{65},

        [103] = S{55},
        [102] = S{218,222},
        [104] = S{47},
        [106] = S{908},
        [107] = S{914},
        [108] = S{107,926},
        [112] = S{204},
        [117] = S{100,926},
        [118] = S{61},
    },
    reisenjima = {[102] = 222,[108] = 926,[117] = 926}
}

local events = {}

events.homepoints = function(p, packet)
    local unlocks = p['Menu Parameters']:unpack('A16', 5)
    local gil = p['Menu Parameters']:unpack('i', 21)
    local enabled_expansions = p['Menu Parameters']:unpack('A2', 25)
    local current_index = p['Menu Parameters']:unpack('C', 29)
    local rhapsody_in_white = p['Menu Parameters']:unpack('q', 31, 2)

    packet['Option Index'] = 8
    build_packet( packet)    
    packet['Option Index'] = 0
    packet['_unknown1'] = 0x4000

    action.cost = 1000 -- FIX ME
    
    local teleport_cost = rhapsody_in_white and action.cost * 0.2 or action.cost

    if not action.index then
        packet['Option Index'] = 1
        packet['_unknown1'] = 0
    elseif current_index == action.index then
        notice('You are already at that teleport')
    elseif gil < teleport_cost then
        notice('You do not have enough gil.')
    elseif not unlocks:has_bit(action.index) then
        notice('You have not unlocked the destination teleport')
    elseif not enabled_expansions:has_bit(action.content) then
        notice('You do not have that expansion registered')
    else
        build_packet(  packets.new('outgoing', 0x114))
        packet['Option Index'] = 2
        packet['_unknown1'] = action.index
        build_packet( packet)

        if action.zone == p['Zone'] then
            npc_warp_request(p, action, bit.bor(3, bit.lshift(action.index, 16)))
            packet['Option Index'] = 3
            packet['_unknown1'] = 0
        end
    end

    packet['Automated Message'] = false
    build_packet( packet)
end

events.survival_guides = function(p, packet)
    local current_index = p['Menu Parameters']:unpack('C', 5)
    local thrifty_transit = p['Menu Parameters']:unpack('q', 6, 3)
    local rhapsody_in_white = p['Menu Parameters']:unpack('q', 6, 6)
    local valor_points = p['Menu Parameters']:unpack('H', 7)
    local gil = p['Menu Parameters']:unpack('i', 9)
    local unlocks = p['Menu Parameters']:unpack('A16', 13)
    local enabled_expansions = p['Menu Parameters']:unpack('A2', 29)

    local teleport_cost = thrifty_transit and 0 or rhapsody_in_white and 200 or 1000

    local tab_cost = rhapsody_in_white and 10 or 50

    if current_index == action.index then
        notice('You are already at that teleport')        
    elseif gil < teleport_cost then
        notice('You do not have enough gil.')
    elseif not unlocks:has_bit(action.unlock_bit) then
        notice('You have not unlocked the destination teleport')
    elseif not enabled_expansions:has_bit(action.content) then
        notice('You do not have that expansion registered')
    else
        build_packet(  packets.new('outgoing', 0x114))
        packet['Option Index'] = 7
        build_packet( packet)

        packet['Option Index'] = 1
        build_packet( packet)
        packet['_unknown1'] = action.index
    end

    packet['Automated Message'] = false
    build_packet( packet)
end

local waypoint_unlocks = {
    [01] = {'b9',  5, 1},
    [02] = {'b9',  6, 8},
    [12] = {'b32', 9, 1},
    [03] = {'b4', 13, 1},
    [04] = {'b4', 13, 7},
    [05] = {'b5', 17, 1},
    [06] = {'b6', 17, 7},
    [07] = {'b4', 21, 1},
    [08] = {'b5', 21, 7},
    [11] = {'b6', 25, 1},
    [09] = {'b5', 25, 7},
}

local has_waypoint = function(params, category, point)

    if category == 10 then
        return true
    end

    local unlocks = params:unpack(unpack(waypoint_unlocks[category]))

    if category == 12 then
        return bit.bnot(unlocks):has_bit(point)
    end

    return unlocks:has_bit(point - 1)
end

events.waypoints = function(p, packet)
    local current_index = p['Menu Parameters']:byte(1)
    local kinetic_cost_adjustment = p['Menu Parameters']:unpack('b2', 2, 6)
    local kinetic_units, unlocks = p['Menu Parameters']:unpack('HA24', 3)

    local current_category = math.max(1, math.floor(current_index/10))
    local current_point = current_index % 10
--[[
    local current_category = {
        [256] = 1,
        [257] = 2,
        [261] = 3,
        [260] = 4,
        [262] = 5,
        [265] = 6,
        [263] = 7,
        [266] = 8,
        [267] = 9,
        [245] = 10,
    }[p.Zone]
]]
    local teleport_cost = ({
        {1,1,50,50,50,50,50,50,50,15,150,100},
        {1,1,50,50,50,50,50,50,50,15,150,100},
        {15,15,2},
        {15,15,[4]=2},
        {15,15,[5]=2},
        {15,15,[6]=2},
        {15,15,[7]=2},
        {15,15,[8]=2},
        {15,15,[9]=2},
        {15,15}
    }[current_category] or {})[action.category]

    if current_category == action.category and current_point == action.point then
        notice('You are already at that teleport')
    elseif not teleport_cost then
        notice('You can not travel to that destination from this area')
    elseif kinetic_cost_adjustment ~= 2 then
        notice('Kinetic Unit Cost Adjustment II is not active')
    elseif kinetic_units < teleport_cost then
        notice('You do not have enough kinetic units.')
    elseif not has_waypoint(p['Menu Parameters'], action.category, action.point) then
        notice('You have not unlocked the destination teleport')
    else
        build_packet(  packets.new('outgoing', 0x114))
        packet['Option Index'] = current_index % 2^7 + action.category * 2^7 + action.point * 2^11
        packet['_unknown1'] = teleport_cost * 2^5
        build_packet( packet)

        if action.category == current_category then
            npc_warp_request(p, action, 0)
            packet['Option Index'] = action.category > 2 and 1002 or 0
        else
            packet['Option Index'] = action.index
        end
        packet['_unknown1'] = 0
    end

    packet['Automated Message'] = false
    build_packet( packet)
end

events.proto_waypoints = function(p, packet)
    local unlocks = p['Menu Parameters']:unpack('A4')
    --local zone_id = p['Menu Parameters']:unpack('H', 9)
    local kinetic_units = p['Menu Parameters']:unpack('i', 13)

    if p.Zone == action.zone then
        notice('You are already at that teleport')
    elseif kinetic_units < action.cost then
        notice('You do not have enough kinetic units.')
    elseif not unlocks:has_bit(action.index - 4) then
        notice('You have not unlocked the destination teleport')
    else
        packet['Option Index'] = action.index
        build_packet( packet)
    end

    packet['Automated Message'] = false
    build_packet( packet)
end

events.eschan_portals = function(p, packet)
    -- teleport                    = 1,
    -- use_escha_silt              = 2,
    -- use_eschan_droplets         = 3,
    -- use_scintillating_rhapsody  = 4,
    local unlocks = p['Menu Parameters']:unpack('I', 5)
    local zone_id = p['Menu Parameters']:unpack('I', 9)
    local current_index =  p['Menu Parameters']:unpack('I', 13)
    --local new_teleport = p['Menu Parameters']:unpack('q', 17)
    --local has_eschan_droplets = p['Menu Parameters']:unpack('q', 17, 2)
    local has_scintillating = p['Menu Parameters']:unpack('q', 17, 3)
    local silt = p['Menu Parameters']:unpack('i', 21)
    local teleport_cost = p['Menu Parameters']:unpack('i', 25)

    local use_scintillating_rhapsody = action.scintillating and has_scintillating

    if current_index == action.index then
        notice('You are already at that teleport')
    elseif silt < teleport_cost then
        notice('You do not have enough silt.')
    elseif not use_scintillating_rhapsody and not unlocks:has_bit(action.index) then
        notice('You have not unlocked the destination teleport')
    else
        build_packet(  packets.new('outgoing', 0x114))
        packet['Option Index'] = 1
        packet['_unknown1'] = action.index
        build_packet( packet)

        local option = use_scintillating_rhapsody and 4 or 2
        npc_warp_request(p, action, bit.bor(option, bit.lshift(action.index, 16)))
        packet['Option Index'] = option
        packet['_unknown1'] = 0
    end

    packet['Automated Message'] = false
    build_packet( packet)
end

events.elvorseal = function(p, packet)
    local dragon_state = p['Menu Parameters']:unpack('b3') -- 1 and 6 - coming soon, 2 and 7 - shown up
    local dragon_hpp = p['Menu Parameters']:unpack('b7', 1, 4)
    --local unknown = p['Menu Parameters']:unpack('b21', 2, 3)
    local has_elvorseal = p['Menu Parameters']:unpack('q', 4, 8)
    local silt = p['Menu Parameters']:unpack('i', 5)
    --local zone_index = p['Menu Parameters']:unpack('C', 11) -- 0 based, used to lookup teleport destinations
    local can_select_options = p['Menu Parameters']:unpack('q', 12, 2)
    local elvorseal_available = {[1]=true,[2]=true,[6]=true,[7]=true}[dragon_state]

    local destination = {
        [288] = {x = -2, z = 0, y = 59.500003814697, rotation = 63}, -- Zitah
        [289] = {x = 0, z = -43.600002288818, y = -238.00001525879, rotation = 191}, -- Ru'Aun
        [291] = {x = 640, z = -372.00003051758, y = -921.00006103516, rotation = 95}, -- Reisenjima
    }[p.Zone]

    --print(dragon_hpp)
    packet['Option Index'] = 14
    build_packet( packet)
    packet['Option Index'] = 8
    build_packet( packet)
    if can_select_options then
        packet['Option Index'] = 9
        build_packet( packet)
        if elvorseal_available then
            if not has_elvorseal then
                packet['Option Index'] = 9
                build_packet( packet)
                packet['Option Index'] = 10
                build_packet( packet)
            end
            packet['Option Index'] = 11
            build_packet( packet)
            npc_warp_request(p, destination, 12)
            packet['Option Index'] = 12
        else
            packet['Option Index'] = 0
            packet['_unknown1'] = 0x4000
            notice('Elvorseal is not currently available')
        end
    else
        packet['Option Index'] = 0
        packet['_unknown1'] = 0x4000
        notice('You have not selected to hear various explanations at this NPC... unable to proceed')
    end
    packet['Automated Message'] = false
    build_packet( packet)
end

events.unity = function(p, packet)
    local accolades = p['Menu Parameters']:unpack('i', 9)
    local unlocks = p['Menu Parameters']:unpack('A', 25)
    local expansions = p['Menu Parameters']:unpack('A2', 29)

    packet['Option Index'] = 10
    build_packet( packet)
    packet['Option Index'] = 0

    if action.unlock_bit and not unlocks:has_bit(action.unlock_bit) then
        notice('You have not unlocked the destination teleport')
    elseif not expansions:has_bit(action.content) then
        notice('You do not have that expansion registered')
    elseif accolades < 200 then
        notice('You do not have enough Accolades.')
    else
        packet['Option Index'] = 7
        build_packet( packet)
        packet['Option Index'] = action.option
    end

    packet['Automated Message'] = false
    build_packet( packet)
end

events.runic_portal = function(p, packet)
    if p['Zone'] == 50 then
        if p['Menu ID'] == 101 then
            local runic_permit, unlocks, merc_ranks, imperial_standing, free_portal_use, astral_candescence, has_permit = p['Menu Parameters']:unpack('i7')

            if not action.index then
                notice('Unable to confirm destination')
            elseif not unlocks:has_bit(action.index) then
                notice('You have not unlocked the destination teleport')
            elseif astral_candescence == 0 then
                packet['Option Index'] = action.index + 100
            elseif free_portal_use == 1 then
                packet['Option Index'] = action.index
            elseif imperial_standing >= 200 then
                packet['Option Index'] = action.index + 1000
            else
                notice('You do not have enough Imperial Standing.')
            end
        elseif p['Menu ID'] >= 120 and p['Menu ID'] <= 125 then
            if action.index and p['Menu ID']-119 ~= action.index then
                notice('Assault orders prevent you from traveling to that destination')
            else
                notice('Confirming orders')
                packet['Option Index'] = 1
            end
        end
    else
        packet['Option Index'] = 0
        build_packet( packet)
        packet['Option Index'] = 1
    end

    packet['Automated Message'] = false
    build_packet( packet)
end

events.confluxes = function(p, packet)
    local conflux_costs = {p['Menu Parameters']:unpack('H8')}
    local unlocks = p['Menu Parameters']:unpack('I', 17)
    local current_index = p['Menu Parameters']:unpack('I', 21) + 1
    local conflux_state = p['Menu Parameters']:unpack('I', 25) -- 1 = activated, 2 = unactivated
    local cruor = p['Menu Parameters']:unpack('i', 29)

    if conflux_state == 2 then
        if conflux_costs[current_index] <= cruor then
            packet['Option Index'] = 1
            notice('Activating conflux')
        else
            notice('You do not have enough Cruor.')
        end
    elseif action.index ~= 9 and conflux_costs[action.index] > cruor then
        notice('You do not have enough Cruor.')
    elseif current_index == action.index then
        notice('You are already at that teleport')
    elseif not unlocks:has_bit(action.index - 1) then
        notice('You have not unlocked the destination teleport')
    elseif conflux_state == 1 then
        packet['Option Index'] = 1
        packet['_unknown1'] = action.index
        build_packet( packet)
        npc_warp_request(p, action, bit.bor(2, bit.lshift(action.index, 16)))
        packet['Option Index'] = action.index
        packet['_unknown1'] = 0
    end
    packet['Automated Message'] = false
    build_packet( packet)
end

events.abyssea_warp = function(p, packet)
    local menu_enabled = p['Menu Parameters']:unpack('i')
    local cruor = p['Menu Parameters']:unpack('i', 5)
    local unlocks = p['Menu Parameters']:unpack('A12', 9)

    if menu_enabled == 0 then
        notice('You do not meet the requirements.')
    elseif not unlocks:has_bit(action.unlock_bit) then
        notice('You have not unlocked the destination teleport')
    elseif cruor < 200 then
        notice('You do not have enough Cruor.')
    else
        packet['Option Index'] = action.option
        build_packet( packet)
    end
    packet['Automated Message'] = false
    build_packet( packet)
end

local past_vw = {[4]=true,[5]=true,[6]=true,[13]=true,[14]=true,[15]=true} 

events.voidwatch = function(p, packet)
    local menu_enabled = p['Menu Parameters']:unpack('b', 1, 2)
    local current_index = p['Menu Parameters']:unpack('b6',3, 3)
    local cruor = p['Menu Parameters']:unpack('i', 17)
    local unlocks = p['Menu Parameters']:unpack('I', 21)
    local content = p['Menu Parameters']:byte(29)

    packet['_unknown1'] = 0x4000

    if not menu_enabled then
        packet['_unknown1'] = 0
        notice('You do not meet the requirements.') 
    elseif current_index == action.index then
        notice('You are already at that teleport')
    elseif action.option ~= 55 and past_vw[current_index] ~= action.past_vw then
        notice('You can not travel to that destination from this area')
    elseif action.content and not content:has_bit(action.content) then
        notice('You do not have that expansion registered')
    elseif bit.band(unlocks, action.unlock_mask) == 0 then
        notice('You have not unlocked the destination teleport')
    elseif cruor < 1000 then
        notice('You do not have enough Cruor.')
    else
        packet['Option Index'] = 2
        packet['_unknown1'] = action.option
    end
    packet['Automated Message'] = false
    build_packet( packet)
end

events.outpost = function(p, packet)
--[[
     sandyRegions, bastokRegions, windyRegions, beastmenRegions, 
     bit.lshift(1, teleporterRegion), 0, 
     main_job_level, 
     allowedTeleports
 ]]
end

events.enter = function(p, packet)
    packet['Option Index'] = 0
    build_packet( packet)

    if p['Menu ID'] == handled_menus.enter.reisenjima[p.Zone] then
        --local sea_access = p['Menu Parameters']:unpack('b', 1)
        packet['Option Index'] = 2
    else
        packet['Option Index'] = 1
    end
    packet['Automated Message'] = false
    build_packet( packet)
end

local function check_event(menu, p)
    if menu.ids then
        return menu.zones:contains(p.Zone) and menu.ids:contains(p['Menu ID'])
    else
        return menu.zones[p.Zone] and menu.zones[p.Zone]:contains(p['Menu ID'])
    end
end

local map_markers = {
    unknown_1       = {'H',   0x06+1},
    homepoints      = {'A16', 0x08+1},
    survival_guides = {'A16', 0x18+1},
    waypoints = {
        [01]        = {'b9',  0x28+1, 1},
        [02]        = {'b9',  0x29+1, 2},
        [03]        = {'b4',  0x2A+1, 3},
        [04]        = {'b4',  0x2A+1, 7},
        [05]        = {'b5',  0x2B+1, 3},
        [06]        = {'b6',  0x2B+1, 8},
        [07]        = {'b4',  0x2C+1, 6},
        [08]        = {'b5',  0x2D+1, 2},
        [09]        = {'b5',  0x2D+1, 7},
    },
    gate_crystals   = {'b9',  0x38+1},
    wotg_maws       = {'b9',  0x3C+1},
    unknown_2       = {'b23', 0x3D+1, 1},
    eschan_portals  = {'I',   0x40+1},
}

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if (id == 0x32 or id == 0x34) and action then
        local p = packets.parse('incoming', data)
        
        if check_event(handled_menus[action.str], p) then
            if not action.in_event then
                action.in_event = true
                
                queued = {}
                
                events[action.str](p, build_dialog_option(p))
                action = nil
                return enable_injection
            end
        end
    elseif id == 0x052 then
        
    elseif id == 0x05C then
    
    elseif id == 0x063 and data:byte(5) == 6 and check_unlocks then
        if check_unlocks == 'homepoints' then
            local unlocks = data:sub(0x08+1, 0x17+1)
            for zone, tab in pairs(maps.homepoints) do
                for k, v in ipairs(tab) do  
                    if unlocks:has_bit(v.index) then
                        windower.add_to_chat(207, 'Home Point #%s: %s':format(k, zone))
                    end
                end
            end
        elseif check_unlocks == 'survival_guides' then
            local unlocks = data:sub(0x18+1, 0x27+1)
            for zone, tab in pairs(maps.survival_guides) do
                if unlocks:has_bit(tab.unlock_bit) then
                    windower.add_to_chat(207, 'Survival Guide: %s':format(zone))
                end
            end
        end
        check_unlocks = nil
    end
end)

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if (id == 0x05C or id == 0x5B) and not enable_injection then
        --local p = packets.parse('outgoing', data)
        local matches
        local num = #queued
        if queued[1] then
            matches = queued[1]:sub(5) == data:sub(5)
            if not matches then
                print('queued   ' .. queued[1]:hex())
            end
            table.remove(queued, 1)
            print(injected and 'injected' or 'outgoing '.. data:hex() .. (matches and ' MATCHES ' or ' ERROR ') .. num)
        end
        if id == 0x05B and data:byte(15) == 0 then queued = {} end
    end
end)

local function get_distance(a, b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
end

local function valid_target(targ)
    return targ and targ.valid_target and targ.is_npc and targ.spawn_type == 2
end

local function find_npc(names)
    local targ, dist
    local self = windower.ffxi.get_mob_by_target('me')
    for index = 0, 0x3FF do local npc = windower.ffxi.get_mob_by_index(index)
        if valid_target(npc) and names:contains(npc.name) and (not targ or get_distance(self, npc) < dist) then
           targ = npc
           dist = get_distance(self, npc)
        end
    end
    return targ, dist
end

local function retry()
    if action and not action.in_event then
        if retry_limit > action.retry_attempts then
            action.retry_attempts = action.retry_attempts + 1
            local self = windower.ffxi.get_mob_by_target('me')
            local targ = windower.ffxi.get_mob_by_id(action.target)
            if self and self.status == 0 and valid_target(targ) and get_distance(self, targ) <= 6 then
                notice('retrying')
                interact_npc(targ)
                retry:schedule(retry_delay)
                return
            end
        end
        action = nil
    end
end

local function valid_args(command, arg)
    if not alias[command] then return end
    for zone, tab in pairs(alias[command]) do
        if tab[arg] then
            return true
        end
    end
end

local function check_args(command, args)
    if not args[2] then return end
    local point = args[#args]:lower()
    if tonumber(point) or valid_args(command, point) then
        if #args == 2 then 
            local zone = res.zones[windower.ffxi.get_info().zone].english

            if alias[command].global[point] and not (alias[command][zone] and alias[command][zone][point]) then
                return command, table.copy(alias[command].global[point])
            end
            return command, {zone = zone, point = point}
        end
        return command, {zone = table.concat(args,' ', 2, #args-1), point = point}
    end
    return command, {zone = table.concat(args, ' ', 2)}
end

local translate = function(str)
    if #str == 5 and str:byte(1) == 0xFD and str:sub(4) == string.char(0x27,0xFD) then
        str = str:sub(1,4) .. 0x5C:char() .. str:sub(5)
    end
    return windower.convert_auto_trans(str)
end

local function resolve_zone(command, args)
    if not args then return end
    args.command = command
    local map = maps[args.command]
    args.zone = translate(args.zone)
    args.zone = alias.zone[args.zone] or args.zone
    if map[args.zone] then
        args.message = 'Teleporting to ' .. args.zone
        args.dest = table.copy(map[args.zone])
        return args
    end
    local match = ('*' .. args.zone:gsub('%p', '') .. '*'):gsub(' ', '*')
    for zone, dest in pairs(map) do
        if zone:gsub('[%s%p]', ''):wmatch(match) then
            args.message = 'Teleporting to ' .. zone
            args.zone = zone
            args.dest = dest
            return args
        end
    end
    notice('Unable to locate destination zone %s.':format(args.zone))
end

local function resolve_point(args)
    if not args then return end

    if not args.point then
        args.dest = args.dest[0] or args.dest[1]
    else 
        local point = tonumber(args.point) or alias[args.command] and alias[args.command][args.zone] and alias[args.command][args.zone][args.point]
        args.dest = args.dest[point]
        args.message = args.message .. ' ' .. args.point
    end

    if args.dest then
        return args
    end

    notice('Unable to locate destination point%s in %s.':format(args.point, args.zone))
end

local function handle_command(commands)
    if not commands then return end
    local targ, dist = find_npc(handled_menus[commands.command].npcs)

    if not targ then
        notice('No target found')
    elseif dist > 6 then
        notice('%s is too far away':format(targ.name))
    else
        action = commands.dest and table.copy(commands.dest) or {}
        action.str = commands.command
        action.target = targ.id
        action.retry_attempts = 0
        interact_npc(targ)
        if commands.message then
            notice(commands.message)
        end
        retry:schedule(retry_delay)
    end
end

local names = {}

local function do_all(str)
    for name in pairs(names) do
        windower.send_ipc_message(name .. ' ' .. str)
        coroutine.sleep(send_all_delay)
    end
end

handled_commands = {
    hp = 'homepoints',
    sg = 'survival_guides',
    wp = 'waypoints',
    pw = 'proto_waypoints',
    uw = 'unity',
    di = 'elvorseal',
    ew = 'eschan_portals',
    ab = 'confluxes',
    aw = 'abyssea_warp',
    rp = 'runic_portal',
    vw = 'voidwatch',
    enter = 'enter',
}

local function on_command(...)
    local commands = {...}

    local command = commands[1] and handled_commands[commands[1]:lower()]

    if not command then return end

    if action then return end

    if os.time() - last_attempt < 5 then return end

    if windower.ffxi.get_player().status ~= 0 then return end

    if commands[2] == 'list' then
        packets.inject(  packets.new('outgoing', 0x114))
        check_unlocks = command
        return
    end

    local zone_id = windower.ffxi.get_info().zone

    if not handled_menus[command].zones[zone_id] then return end

    if commands[2] and commands[2]:lower() == 'all' then
        names = {}
        windower.send_ipc_message('roll_call')

        while commands[2] and commands[2]:lower() == 'all' do
            table.remove(commands, 2)
        end

        do_all:schedule(send_all_delay, table.concat(commands, ' '))
    end

    if command == 'waypoints' or command == 'homepoints' and 'set' ~= (commands[2] and commands[2]:lower()) then
        handle_command(resolve_point(resolve_zone(check_args(command, commands))))
    elseif command == 'eschan_portals' or command == 'confluxes' then
        local point = tonumber(commands[2])

        if not point then return end

        handle_command(resolve_point{
            command = command,
            message = 'Teleporting to point',
            zone = res.zones[zone_id].name,
            dest = maps[command][zone_id],
            point = point
        })
    elseif command == 'survival_guides' or
        command == 'proto_waypoints' or
        command == 'unity' or
        command == 'abyssea_warp' or
        command == 'voidwatch' or
        command == 'runic_portal' and commands[2] then

        handle_command(resolve_zone(command, {zone = table.concat(commands, ' ', 2)}))
    else
        handle_command{command = command}
    end
end

local function ipc_message(message)
    message = message:split(' ')

    if message[1] == 'roll_call' then
        windower.send_ipc_message('name %s':format(windower.ffxi.get_mob_by_target('me').name))
    elseif message[1] == 'name' then
        names[message[2]] = true
    elseif message[1] == windower.ffxi.get_mob_by_target('me').name then
        table.remove(message, 1)
        on_command(unpack(message))
    end
end

windower.register_event('ipc message', ipc_message)
windower.register_event('addon command', on_command)
windower.register_event('unhandled command', on_command)

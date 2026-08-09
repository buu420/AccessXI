local addon_path = assert(arg[1], 'missing addon path')
local source_file = assert(io.open(addon_path, 'r'))
local source = source_file:read('*a')
source_file:close()

local start_marker = 'function accessxi.nav_zoneline_path'
local end_marker = 'function accessxi.nav_zoneline_approach_candidates'
local start_index = assert(source:find(start_marker, 1, true))
local end_index = assert(source:find(end_marker, start_index, true))
local function_source = source:sub(start_index, end_index - 1)

local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
T = function(values) return setmetatable(values or {}, { __index = list_methods }) end

accessxi = {
    nav_zoneline_edges = T{
        T{ id = 10, from_zone = 236, to_zone = 144 },
        T{ id = 20, from_zone = 236, to_zone = 106 },
        T{ id = 30, from_zone = 144, to_zone = 143 },
        T{ id = 947466874, from_zone = 106, to_zone = 143 },
    },
    nav_load_zoneline_graph = function() end,
}

function accessxi.nav_zoneline_out_edges(zone)
    local edges = T{}
    for _, edge in ipairs(accessxi.nav_zoneline_edges) do
        if edge.from_zone == zone then edges:append(edge) end
    end
    return edges
end

assert(loadstring(function_source))()

local ordinary = accessxi.nav_zoneline_path(236, 143)
assert(ordinary:len() == 2)
assert(ordinary[ordinary:len()].id == 30)

local canonical = accessxi.nav_zoneline_path(236, 143, 947466874)
assert(canonical:len() == 2)
assert(canonical[canonical:len()].id == 947466874)
assert(canonical[canonical:len()].from_zone == 106)
assert(canonical[canonical:len()].to_zone == 143)

local direct = accessxi.nav_zoneline_path(106, 143, 947466874)
assert(direct:len() == 1 and direct[1].id == 947466874)

assert(accessxi.nav_zoneline_path(236, 143, 999999999):len() == 0)

-- A canonical final entrance cannot be treated as final if the prefix already
-- entered and exited the destination zone through another doorway.
accessxi.nav_zoneline_edges:append(T{ id = 40, from_zone = 500, to_zone = 143 })
accessxi.nav_zoneline_edges:append(T{ id = 41, from_zone = 143, to_zone = 106 })
assert(accessxi.nav_zoneline_path(500, 143, 947466874):len() == 0)

accessxi.nav_zoneline_edges:append(T{ id = 947466874, from_zone = 144, to_zone = 143 })
assert(accessxi.nav_zoneline_path(236, 143, 947466874):len() == 0)

print('nav zoneline canonical path tests passed')

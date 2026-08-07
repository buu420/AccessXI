$ErrorActionPreference = 'Stop'

$root = 'C:\Users\buu42\AccessXI'
$modulePath = Join-Path $root 'ashita\addons\accessxi_reader\modules\same_zone_reentry_navigation.lua'
$graphPath = Join-Path $root 'ashita\addons\accessxi_reader\data\ffxi-nav-zoneline-graph.tsv'
$probePath = Join-Path $root 'tools\navprobe\bin\Release\net8.0\win-x86\publish\navprobe.exe'
$northMeshPath = Join-Path $root 'third_party\xiNavmeshes\North_Gustaberg.nav'
$southMeshPath = Join-Path $root 'third_party\xiNavmeshes\South_Gustaberg.nav'
$luaPath = Join-Path $root 'tools\lua51\lua5.1.exe'

function Get-WaypointCount {
    param([string[]]$Output)

    $line = $Output | Where-Object { $_ -match '^waypoints\s+\d+' } | Select-Object -First 1
    if ($null -eq $line -or $line -notmatch '^waypoints\s+(\d+)') {
        throw 'navprobe did not report a waypoint count.'
    }
    return [int]$Matches[1]
}

foreach ($path in @($graphPath, $probePath, $northMeshPath, $southMeshPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing same-zone re-entry test dependency: $path"
    }
}

# Exact live regression captured on 2026-08-03. The Guide is in a valid but
# disconnected North Gustaberg mesh component. Every walking leg of the only
# accepted detour must remain independently verifiable in the current meshes.
$directOutput = & $probePath $northMeshPath 1.769 -0.502 -75.402 -582.687 40.107 52.281
$eastExitOutput = & $probePath $northMeshPath 1.769 -0.502 -75.402 0.735 -5.555 -79.065
$southCrossingOutput = & $probePath $southMeshPath 0.840 -5.027 76.838 -440.502 35.486 -121.753
$westGuideOutput = & $probePath $northMeshPath -440.792 35.531 -272.901 -582.687 40.107 52.281

$directCount = Get-WaypointCount $directOutput
$eastExitCount = Get-WaypointCount $eastExitOutput
$southCrossingCount = Get-WaypointCount $southCrossingOutput
$westGuideCount = Get-WaypointCount $westGuideOutput

if ($directCount -ne 1) {
    throw "Expected the disconnected live Survival Guide query to return one unusable point; got $directCount."
}
if ($eastExitCount -le 1 -or $southCrossingCount -le 1 -or $westGuideCount -le 1) {
    throw "Every detour leg must be walkable (east=$eastExitCount south=$southCrossingCount west=$westGuideCount)."
}

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Missing same-zone re-entry planner module: $modulePath"
}

$graphRows = Import-Csv -LiteralPath $graphPath -Delimiter "`t"
foreach ($edgeId in @('846803578', '880358010', '880423546', '913977978')) {
    $row = $graphRows | Where-Object { $_.zoneline_id -eq $edgeId } | Select-Object -First 1
    if ($null -eq $row) { throw "Missing Gustaberg zoneline edge $edgeId." }
    if ($row.confidence -notmatch '^(proven|verified)$') {
        throw "Gustaberg zoneline edge $edgeId must be backed by live evidence before detour use; got '$($row.confidence)'."
    }
}

$luaHarness = @'
local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear() for i = #self, 1, -1 do self[i] = nil end end
T = function(values) return setmetatable(values or {}, { __index = list_methods }) end
string.fmt = function(self, ...) return string.format(self, ...) end

local function copy(point)
    if point == nil then return nil end
    local result = T{}
    for key, value in pairs(point) do result[key] = value end
    return result
end

local function near(a, b, tolerance)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (tolerance or 0.01)
end

local function same_point(a, b)
    return a ~= nil and b ~= nil
        and (tonumber(a.zone) or 0) == (tonumber(b.zone) or 0)
        and near(a.x, b.x)
        and near(a.z, b.z)
        and near(a.y, b.y)
end

local player = T{ zone = 106, x = 1.769, z = -75.402, y = -0.502 }
local target = T{ zone = 106, name = 'Survival Guide', x = -582.687, z = 52.281, y = 40.107, kind = 'object' }

local north_east_exit = T{
    id = 846803578, from_zone = 106, from_name = 'North Gustaberg',
    from_x = 0.735, from_z = -79.065, from_y = -5.555,
    to_zone = 107, to_name = 'South Gustaberg',
    to_x = 0.840, to_z = 76.838, to_y = -5.027,
    confidence = 'proven', source = 'lsb-zonelines',
}
local north_west_exit = T{
    id = 880358010, from_zone = 106, from_name = 'North Gustaberg',
    from_x = -440.639, from_z = -276.308, from_y = 33.094,
    to_zone = 107, to_name = 'South Gustaberg',
    to_x = -440.502, to_z = -121.753, to_y = 35.486,
    confidence = 'proven', source = 'lsb-zonelines',
}
local south_east_return = T{
    id = 880423546, from_zone = 107, from_name = 'South Gustaberg',
    from_x = 0.877, from_z = 80.156, from_y = -6.763,
    to_zone = 106, to_name = 'North Gustaberg',
    to_x = 0.020, to_z = -75.405, to_y = -4.409,
    confidence = 'proven', source = 'lsb-zonelines',
}
local south_west_return = T{
    id = 913977978, from_zone = 107, from_name = 'South Gustaberg',
    from_x = -440.465, from_z = -118.436, from_y = 33.268,
    to_zone = 106, to_name = 'North Gustaberg',
    to_x = -440.792, to_z = -272.901, to_y = 35.531,
    confidence = 'proven', source = 'lsb-zonelines',
}

local edges_by_zone = {
    [106] = { north_east_exit, north_west_exit },
    [107] = { south_east_return, south_west_return },
}
local allow_middle = true
local allow_final = true

local function from_point(edge)
    return T{ zone = edge.from_zone, x = edge.from_x, z = edge.from_z, y = edge.from_y }
end
local function to_point(edge)
    return T{ zone = edge.to_zone, x = edge.to_x, z = edge.to_z, y = edge.to_y }
end

nav_compute_mesh_route = function(start_point, end_point)
    if same_point(start_point, player) and same_point(end_point, from_point(north_east_exit)) then
        return T{ copy(start_point), copy(end_point) }
    end
    if allow_middle and same_point(start_point, to_point(north_east_exit)) and same_point(end_point, from_point(south_west_return)) then
        return T{ copy(start_point), T{ zone = 107, x = -200, z = -50, y = 10 }, copy(end_point) }
    end
    if allow_final and same_point(start_point, to_point(south_west_return)) and same_point(end_point, target) then
        return T{ copy(start_point), T{ zone = 106, x = -520, z = -100, y = 38 }, copy(end_point) }
    end
    return T{ copy(end_point) }
end

nav_distance = function(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    local dy = (tonumber(b.y) or 0) - (tonumber(a.y) or 0)
    return math.sqrt((dx * dx) + (dz * dz) + (dy * dy))
end

logs = T{}
log_line = function(text) logs:append(text) end
nav_clean_field = function(value) return tostring(value or '') end

accessxi = {
    nav_zoneline_out_edges = function(zone)
        local result = T{}
        for _, edge in ipairs(edges_by_zone[tonumber(zone) or 0] or {}) do result:append(edge) end
        return result
    end,
    nav_zoneline_edge_rank = function(edge)
        local confidence = string.lower(tostring(edge.confidence or ''))
        if confidence == 'proven' then return 0, 0 end
        if confidence == 'verified' then return 2, 0 end
        return 8, 0
    end,
    nav_graph_zone_name = function(zone)
        if tonumber(zone) == 106 then return 'North Gustaberg' end
        if tonumber(zone) == 107 then return 'South Gustaberg' end
        return 'Unknown zone'
    end,
    nav_copy_point = copy,
}

local chunk = assert(loadfile(module_path))
local env = {
    accessxi = accessxi,
    T = T,
    nav_distance = nav_distance,
    nav_compute_mesh_route = nav_compute_mesh_route,
    nav_clean_field = nav_clean_field,
    log_line = log_line,
}
setmetatable(env, { __index = _G })
setfenv(chunk, env)
assert(chunk())

local plan = accessxi.nav_same_zone_reentry_find(player, target)
assert(plan ~= nil and plan.edges:len() == 2, 'expected a verified two-transition re-entry plan')
assert(plan.edges[1].id == 846803578, 'planner did not choose the reachable east exit')
assert(plan.edges[2].id == 913977978, 'planner did not choose the walkable west re-entry')

assert(accessxi.nav_same_zone_reentry_begin(player, target) == true)
assert(accessxi.nav_same_zone_reentry_active() == true)
local first_leg, first_status = accessxi.nav_same_zone_reentry_current_leg(player)
assert(first_status == 'leg' and first_leg.same_zone_reentry_step == 1)
assert(first_leg.to_zone == 107 and first_leg.x == north_east_exit.from_x)
assert(string.find(first_leg.source, 'zonesearch:', 1, true) == 1)
assert(accessxi.nav_same_zone_reentry_advance(first_leg) == true)

local south_player = copy(to_point(north_east_exit))
local second_leg, second_status = accessxi.nav_same_zone_reentry_current_leg(south_player)
assert(second_status == 'leg' and second_leg.same_zone_reentry_step == 2)
assert(second_leg.to_zone == 106 and second_leg.x == south_west_return.from_x)
assert(accessxi.nav_same_zone_reentry_advance(second_leg) == true)

local north_player = copy(to_point(south_west_return))
local final_leg, final_status = accessxi.nav_same_zone_reentry_current_leg(north_player)
assert(final_leg == nil and final_status == 'complete')
accessxi.nav_same_zone_reentry_clear()
assert(accessxi.nav_same_zone_reentry_active() == false)

local started_reason = nil
accessxi.nav_zone_search_start_next_leg = function(reason)
    started_reason = reason
    accessxi.nav_active = true
    return 'Started verified re-entry leg.'
end
local start_text = accessxi.nav_same_zone_reentry_start(player, target, 'menu-route-reentry')
assert(start_text == 'Started verified re-entry leg.')
assert(started_reason == 'menu-route-reentry')
assert(accessxi.nav_same_zone_reentry_active() == true)
accessxi.nav_same_zone_reentry_clear()
accessxi.nav_zone_search_target = nil

south_west_return.confidence = 'untested'
assert(accessxi.nav_same_zone_reentry_find(player, target) == nil, 'untested transition was accepted')
south_west_return.confidence = 'proven'

allow_middle = false
assert(accessxi.nav_same_zone_reentry_find(player, target) == nil, 'missing neighboring-zone walk was accepted')
allow_middle = true

allow_final = false
assert(accessxi.nav_same_zone_reentry_find(player, target) == nil, 'missing final-zone walk was accepted')

return true
'@

$escapedModulePath = $modulePath.Replace('\', '\\').Replace("'", "\'")
& $luaPath -e "module_path='$escapedModulePath'; $luaHarness"
if ($LASTEXITCODE -ne 0) {
    throw "Same-zone re-entry Lua behavior harness failed with exit code $LASTEXITCODE."
}

Write-Host "nav same-zone re-entry tests passed (direct=$directCount east=$eastExitCount south=$southCrossingCount west=$westGuideCount)"

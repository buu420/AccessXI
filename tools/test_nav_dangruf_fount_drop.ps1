$ErrorActionPreference = 'Stop'

$root = 'C:\Users\buu42\AccessXI'
$addonPath = Join-Path $root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$modulePath = Join-Path $root 'ashita\addons\accessxi_reader\modules\dangruf_fount_drop_navigation.lua'
$probePath = Join-Path $root 'tools\navprobe\bin\Release\net8.0\win-x86\publish\navprobe.exe'
$meshPath = Join-Path $root 'third_party\xiNavmeshes\Dangruf_Wadi.nav'
$luaPath = Join-Path $root 'tools\lua51\lua5.1.exe'

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Get-WaypointCount {
    param([string[]]$Output)
    $line = $Output | Where-Object { $_ -match '^waypoints\s+\d+' } | Select-Object -First 1
    if ($null -eq $line -or $line -notmatch '^waypoints\s+(\d+)') {
        throw 'navprobe did not report a waypoint count.'
    }
    return [int]$Matches[1]
}

foreach ($path in @($addonPath, $probePath, $meshPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Dangruf fount test dependency: $path"
    }
}

# Exact live failure and the two independently walkable halves. Coordinates
# passed to navprobe are x, vertical y, map z; AccessXI data stores x, z, y.
$directOutput = & $probePath $meshPath -4.025 -1.060 3.391 -480.364 2.457 -58.355
$doorOutput = & $probePath $meshPath -4.025 -1.060 3.391 -466.483 -6.730 -100.001
$lowerOutput = & $probePath $meshPath -460.000 2.500 -100.000 -480.364 2.457 -58.355
$reverseDropOutput = & $probePath $meshPath -460.000 2.500 -100.000 -466.483 -6.730 -100.001

$directCount = Get-WaypointCount $directOutput
$doorCount = Get-WaypointCount $doorOutput
$lowerCount = Get-WaypointCount $lowerOutput
$reverseDropCount = Get-WaypointCount $reverseDropOutput

if ($directCount -ne 1) {
    throw "Expected the live entrance-to-fount query to remain disconnected; got $directCount waypoints."
}
if ($doorCount -le 1) {
    throw "Expected the current mesh to route from the entrance to the Cermet Door; got $doorCount waypoints."
}
if ($lowerCount -le 1) {
    throw "Expected the current lower mesh to continue to the fount; got $lowerCount waypoints."
}
if ($reverseDropCount -ne 1) {
    throw "Expected the physical drop to remain a one-way mesh split; got $reverseDropCount reverse waypoints."
}

if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw 'Missing one-way Dangruf fount drop navigation module.'
}

$source = Get-Content -LiteralPath $addonPath -Raw
$moduleSource = Get-Content -LiteralPath $modulePath -Raw
Assert-Match $source "load_code_module\('dangruf_fount_drop_navigation'" 'The addon must load the Dangruf fount drop module.'
Assert-Match $source 'nav_dangruf_fount_drop_route\(player, point\)' 'Disconnected routes must try the verified fount drop approach.'
Assert-Match $source 'nav_dangruf_fount_drop_poll\(player, destination, now\)' 'Live polling must detect the landing before resuming.'
Assert-Match $source 'nav_dangruf_fount_drop_beacon_target\(player, now\)' 'The beacon must own the final Cermet Door/drop approach.'
Assert-Match $source 'nav_dangruf_fount_drop_start_suffix\(\)' 'Route start must disclose the false wall and one-way drop.'
Assert-Match $source "nav_dangruf_fount_drop_clear\('zone-change'\)" 'Zone changes must clear a stale drop transition.'

$luaHarness = @'
local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear() for index = #self, 1, -1 do self[index] = nil end end
T = function(values) return setmetatable(values or {}, { __index = list_methods }) end
string.fmt = function(self, ...) return string.format(self, ...) end

local function copy(point)
    if point == nil then return nil end
    return T{
        zone = point.zone,
        name = point.name,
        x = point.x,
        z = point.z,
        y = point.y,
        kind = point.kind,
        source = point.source,
    }
end

local function near(value, expected, tolerance)
    return math.abs((tonumber(value) or 0) - expected) <= (tolerance or 0.2)
end

local fount = T{
    zone = 191,
    name = 'Geomagnetic Fount',
    x = -480.364,
    z = -58.355,
    y = 2.457,
    kind = 'object',
    source = 'lsb-npc-list-all',
}
local cermet_door = T{
    zone = 191,
    name = 'Cermet Door',
    x = -466.483,
    z = -100.001,
    y = -6.730,
    kind = 'object',
    source = 'lsb-npc-list-all',
}
local entrance = T{ zone = 191, x = -4.025, z = 3.391, y = -1.060 }
local lower_landing = T{ zone = 191, x = -460.000, z = -100.000, y = 2.500 }
local approach_enabled = true
local fount_query_count = 0

local function same_position(a, b, tolerance)
    return a ~= nil and b ~= nil
        and near(a.x, b.x, tolerance or 0.3)
        and near(a.z, b.z, tolerance or 0.3)
        and near(a.y, b.y, tolerance or 0.3)
end

nav_compute_mesh_route = function(start_point, end_point)
    if same_position(end_point, cermet_door, 0.4) then
        if approach_enabled and (tonumber(start_point.zone) or 0) == 191 and (tonumber(start_point.x) or 0) > -450 then
            return T{
                copy(start_point),
                T{ zone = 191, x = -387.600, z = -99.600, y = 0.254 },
                copy(cermet_door),
            }
        end
        return T{ copy(cermet_door) }
    end
    if same_position(end_point, fount, 0.8) then
        fount_query_count = fount_query_count + 1
        if (tonumber(start_point.x) or 0) <= -450 and (tonumber(start_point.y) or 0) >= 1.0 then
            return T{
                copy(start_point),
                T{ zone = 191, x = -470.000, z = -75.000, y = 2.500 },
                copy(fount),
            }
        end
        return T{ copy(fount) }
    end
    return T{ copy(end_point) }
end

nav_distance = function(a, b)
    local dx = (tonumber(b ~= nil and b.x) or 0) - (tonumber(a ~= nil and a.x) or 0)
    local dz = (tonumber(b ~= nil and b.z) or 0) - (tonumber(a ~= nil and a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end

spoken = T{}
speak = function(text) spoken:append(text) end
logs = T{}
log_line = function(text) logs:append(text) end
tick = function() return 1000 end

accessxi = {
    nav_dangruf_fount_drop_transition = nil,
    nav_route_points = T{},
    nav_route_point_index = 1,
    nav_route_last_recalc_tick = 0,
    nav_route_live_replan_last_key = '',
    nav_route_live_replan_last_tick = 0,
    nav_last_key = '',
    nav_last_direction_text = '',
    nav_beacon_last_key = '',
    nav_beacon_last_tick = 0,
    nav_progress_x = nil,
    nav_progress_z = nil,
    nav_progress_distance = 0,
    nav_progress_tick = 0,
    nav_collision_x = nil,
    nav_collision_z = nil,
    nav_collision_tick = 0,
    nav_first_route_index = function() return 2 end,
    nav_collision_quiet = function() end,
    nav_reset_progress_watch = function() end,
    nav_collision_reset = function() end,
    escape_probe_log_text = function(value) return tostring(value or '') end,
}

local chunk = assert(loadfile(module_path))
setfenv(chunk, {
    accessxi = accessxi,
    T = T,
    nav_distance = nav_distance,
    nav_compute_mesh_route = nav_compute_mesh_route,
    log_line = log_line,
    speak = speak,
    tick = tick,
    math = math,
    string = string,
    tostring = tostring,
    tonumber = tonumber,
    ipairs = ipairs,
    type = type,
    setmetatable = setmetatable,
})
assert(chunk())

-- A disconnected request to the exact fount becomes a verified route to the
-- Cermet Door, never a fabricated segment to the lower destination.
local route = accessxi.nav_dangruf_fount_drop_route(copy(entrance), copy(fount))
assert(route:len() == 3)
assert(accessxi.nav_dangruf_fount_drop_transition ~= nil)
assert(same_position(route[#route], cermet_door, 0.4))
assert(not same_position(route[#route], fount, 0.8))
local suffix = accessxi.nav_dangruf_fount_drop_start_suffix()
assert(string.find(suffix, 'false wall', 1, true) ~= nil)
assert(string.find(suffix, 'one-way drop', 1, true) ~= nil)

-- The special transition is scoped to this destination and does not create a
-- generic or reverse route through the hole.
accessxi.nav_dangruf_fount_drop_clear('test-scope')
local other = T{ zone = 191, name = 'Geyser Lizard', x = -363, z = -69, y = 3, kind = 'enemy' }
assert(accessxi.nav_dangruf_fount_drop_route(copy(entrance), other):len() == 0)
assert(accessxi.nav_dangruf_fount_drop_transition == nil)
local exit = T{ zone = 191, name = 'South Gustaberg zone line', x = 0.228, z = -0.011, y = -6.431, kind = 'area' }
assert(accessxi.nav_dangruf_fount_drop_route(copy(lower_landing), exit):len() == 0)
assert(accessxi.nav_dangruf_fount_drop_transition == nil)
local wrong_zone = copy(fount)
wrong_zone.zone = 190
assert(accessxi.nav_dangruf_fount_drop_route(copy(entrance), wrong_zone):len() == 0)

-- A missing current-mesh approach remains unavailable instead of becoming a
-- straight-line fallback.
approach_enabled = false
assert(accessxi.nav_dangruf_fount_drop_route(copy(entrance), copy(fount)):len() == 0)
assert(accessxi.nav_dangruf_fount_drop_transition == nil)
approach_enabled = true

-- Near the real door, the transition owns the beacon and speaks the published
-- false-wall/hole instruction while the upper and lower meshes are disconnected.
route = accessxi.nav_dangruf_fount_drop_route(copy(entrance), copy(fount))
local far_query_count = fount_query_count
assert(accessxi.nav_dangruf_fount_drop_poll(copy(entrance), copy(fount), 1200) == false)
assert(fount_query_count == far_query_count, 'far approach polled the disconnected fount mesh')
local far_target, far_handled = accessxi.nav_dangruf_fount_drop_beacon_target(copy(entrance), 1500)
assert(far_target == nil and far_handled == false)
local near_door = T{ zone = 191, x = -455.000, z = -99.000, y = -4.300 }
local door_target, door_handled = accessxi.nav_dangruf_fount_drop_beacon_target(copy(near_door), 1600)
assert(door_handled == true and same_position(door_target, cermet_door, 3.0))
local waiting = accessxi.nav_dangruf_fount_drop_poll(copy(near_door), copy(fount), 2000)
assert(waiting == true)
assert(accessxi.nav_dangruf_fount_drop_transition ~= nil)
assert(string.find(spoken[#spoken], 'false wall', 1, true) ~= nil)
assert(string.find(spoken[#spoken], 'hole immediately before the door', 1, true) ~= nil)

-- Live position after the fall must independently produce the continuation.
-- Only then may the approach be replaced and normal route tracking resume.
local resumed = accessxi.nav_dangruf_fount_drop_poll(copy(lower_landing), copy(fount), 3000)
assert(resumed == true)
assert(accessxi.nav_dangruf_fount_drop_transition == nil)
assert(accessxi.nav_route_points:len() == 3)
assert(accessxi.nav_route_point_index == 2)
assert(same_position(accessxi.nav_route_points[#accessxi.nav_route_points], fount, 0.8))
assert(string.find(spoken[#spoken], 'Route resumed', 1, true) ~= nil)

-- A destination change cancels the pending transition without consuming the
-- ordinary route poll.
route = accessxi.nav_dangruf_fount_drop_route(copy(entrance), copy(fount))
assert(route:len() > 1)
assert(accessxi.nav_dangruf_fount_drop_poll(copy(entrance), other, 4000) == false)
assert(accessxi.nav_dangruf_fount_drop_transition == nil)

return true
'@

$escapedModulePath = $modulePath.Replace('\', '\\').Replace("'", "\'")
& $luaPath -e "module_path='$escapedModulePath'; $luaHarness"
if ($LASTEXITCODE -ne 0) {
    throw "Dangruf fount drop Lua behavior harness failed with exit code $LASTEXITCODE."
}

Write-Host "nav Dangruf fount drop tests passed (direct=$directCount door=$doorCount lower=$lowerCount reverse=$reverseDropCount)"

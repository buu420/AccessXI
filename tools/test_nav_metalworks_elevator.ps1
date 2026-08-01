$ErrorActionPreference = 'Stop'

$root = 'C:\Users\buu42\AccessXI'
$addonPath = Join-Path $root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$modulePath = Join-Path $root 'ashita\addons\accessxi_reader\modules\metalworks_elevator_navigation.lua'
$probePath = Join-Path $root 'tools\navprobe\bin\Release\net8.0\win-x86\publish\navprobe.exe'
$meshPath = Join-Path $root 'third_party\xiNavmeshes\Metalworks.nav'
$luaPath = Join-Path $root 'tools\lua51\lua5.1.exe'

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

function Get-WaypointCount {
    param([string[]]$Output)
    $line = $Output | Where-Object { $_ -match '^waypoints\s+\d+' } | Select-Object -First 1
    if ($null -eq $line -or $line -notmatch '^waypoints\s+(\d+)') {
        throw 'navprobe did not report a waypoint count.'
    }
    return [int]$Matches[1]
}

function Get-MinimumDistance {
    param(
        [string[]]$Output,
        [double]$X,
        [double]$Y,
        [double]$Z
    )
    $minimum = [double]::PositiveInfinity
    foreach ($line in $Output) {
        if ($line -match '^\d+\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)$') {
            $dx = [double]$Matches[1] - $X
            $dy = [double]$Matches[2] - $Y
            $dz = [double]$Matches[3] - $Z
            $distance = [Math]::Sqrt(($dx * $dx) + ($dy * $dy) + ($dz * $dz))
            if ($distance -lt $minimum) { $minimum = $distance }
        }
    }
    return $minimum
}

foreach ($path in @($addonPath, $modulePath, $probePath, $meshPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Metalworks elevator test dependency: $path"
    }
}

# Exact live regression from 2026-08-01. FFXINAV returns a core path to the old
# guessed landing, but that path enters the real Metalworks -> Bastok Markets
# zone trigger and zoned the player. A collision path is not sufficient proof.
$directOutput = & $probePath $meshPath -30.805 0 2.409 66.865 -13.999 -4.562
$unsafeOldOutput = & $probePath $meshPath -30.805 0 2.409 1.333 0 13.000
$southLowerOutput = & $probePath $meshPath -30.805 0 2.409 -58.850 0 -11.914
$southUpperOutput = & $probePath $meshPath -53.126 -12.098 -11.875 66.865 -13.999 -4.562
$northLowerOutput = & $probePath $meshPath -30.805 0 2.409 -58.850 0 12.002
$northUpperOutput = & $probePath $meshPath -53.126 -12.098 12.040 66.865 -13.999 -4.562
$arrivalLowerOutput = & $probePath $meshPath -9.168 0 -0.498 -58.850 0 -11.914
$upperReturnOutput = & $probePath $meshPath 66.865 -13.999 -4.562 -53.126 -12.098 -11.875
$lowerReturnOutput = & $probePath $meshPath -58.850 0 -11.914 -30.805 0 2.409
$verticalOutput = & $probePath $meshPath -58.850 0 -11.914 -53.126 -12.098 -11.875

$directCount = Get-WaypointCount $directOutput
$unsafeOldCount = Get-WaypointCount $unsafeOldOutput
$southLowerCount = Get-WaypointCount $southLowerOutput
$southUpperCount = Get-WaypointCount $southUpperOutput
$northLowerCount = Get-WaypointCount $northLowerOutput
$northUpperCount = Get-WaypointCount $northUpperOutput
$arrivalLowerCount = Get-WaypointCount $arrivalLowerOutput
$upperReturnCount = Get-WaypointCount $upperReturnOutput
$lowerReturnCount = Get-WaypointCount $lowerReturnOutput
$verticalCount = Get-WaypointCount $verticalOutput
$unsafeOldZoneDistance = Get-MinimumDistance $unsafeOldOutput -X -6.175 -Y -2.966 -Z -0.008
$southLowerZoneDistance = Get-MinimumDistance $southLowerOutput -X -6.175 -Y -2.966 -Z -0.008

if ($directCount -ne 1) { throw "Expected the disconnected live Naji query to return one unusable point; got $directCount." }
if ($unsafeOldCount -le 1 -or $unsafeOldZoneDistance -gt 6) { throw 'The regression fixture must preserve the navmesh route that actually crosses the Bastok Markets zone trigger.' }
if ($southLowerCount -le 1 -or $northLowerCount -le 1) { throw 'Both real lower elevator approaches must be walkable in the current Metalworks mesh.' }
if ($arrivalLowerCount -le 1) { throw 'The actual Metalworks arrival point must have a verified route that moves away from the nearby zone trigger.' }
if ($southUpperCount -le 1 -or $northUpperCount -le 1) { throw 'Both real upper elevator continuations to Naji must be walkable in the current Metalworks mesh.' }
if ($upperReturnCount -le 1 -or $lowerReturnCount -le 1) { throw 'The real elevator must also have verified return legs.' }
if ($verticalCount -ne 1) { throw "The moving elevator must remain staged, not a fabricated vertical walk edge; got $verticalCount." }
if ($southLowerZoneDistance -le 12) { throw "The real south elevator approach unexpectedly comes near the outgoing zone trigger: $southLowerZoneDistance." }

$source = Get-Content -LiteralPath $addonPath -Raw
$moduleSource = Get-Content -LiteralPath $modulePath -Raw
Assert-Match $source "load_code_module\('metalworks_elevator_navigation'" 'The addon must load the verified Metalworks elevator module.'
Assert-Match $source 'nav_metalworks_elevator_route\(player, point\)' 'Disconnected exact routes must try the verified elevator transition.'
Assert-Match $source 'nav_transport_transition_poll\(player, destination, now\)' 'Live route polling must advance the elevator transition from current position.'
Assert-Match $source 'nav_transport_waiting_beacon_target\(player, now\)' 'The beacon must guide through the elevator door and pause only once aboard.'
Assert-Match $moduleSource "zone_id\s*=\s*237" 'The transition must be restricted to Metalworks.'
Assert-Match $moduleSource 'x\s*=\s*-58\.850' 'The lower landing must use the native North/South elevator doors.'
Assert-Match $moduleSource 'x\s*=\s*-53\.126' 'The upper landing must use the native North/South elevator doors.'
Assert-Match $moduleSource 'z\s*=\s*-11\.914' 'The south lower elevator door coordinate is missing.'
Assert-Match $moduleSource 'z\s*=\s*12\.002' 'The north lower elevator door coordinate is missing.'
Assert-Match $moduleSource 'x\s*=\s*-55\.978[\s\S]*?z\s*=\s*-12\.020' 'The south moving-platform target is missing.'
Assert-Match $moduleSource 'x\s*=\s*-56\.006[\s\S]*?z\s*=\s*12\.014' 'The north moving-platform target is missing.'
Assert-Match $moduleSource 'route_crosses_zone_trigger' 'Elevator legs must explicitly reject the outgoing Metalworks zone trigger.'
Assert-Match $moduleSource 'x\s*=\s*-6\.175[\s\S]*?z\s*=\s*-0\.008[\s\S]*?y\s*=\s*-2\.966' 'The zone-trigger guard must use the current zoneline graph coordinate.'
Assert-NotMatch $moduleSource 'x\s*=\s*1\.333' 'The collision-component near point that zoned the player must never be used as an elevator landing.'

$luaHarness = @'
local list_methods = {}
function list_methods:len() return #self end
function list_methods:append(value) self[#self + 1] = value; return self end
function list_methods:clear() for i = #self, 1, -1 do self[i] = nil end end
T = function(values) return setmetatable(values or {}, { __index = list_methods }) end
string.fmt = function(self, ...) return string.format(self, ...) end

local function copy(point)
    return T{ zone = point.zone, name = point.name, x = point.x, z = point.z, y = point.y, kind = point.kind, source = point.source }
end
local function near(value, expected, tolerance) return math.abs((tonumber(value) or 0) - expected) < (tolerance or 0.2) end
local lower_north = T{ zone = 237, x = -58.850, z = 12.002, y = 0 }
local upper_north = T{ zone = 237, x = -53.126, z = 12.040, y = -12.098 }
local lower_south = T{ zone = 237, x = -58.850, z = -11.914, y = 0 }
local upper_south = T{ zone = 237, x = -53.126, z = -11.875, y = -12.098 }
local continuation_enabled = true
local unsafe_approach = false
local calls = T{}

local function same_position(a, b)
    return near(a.x, b.x) and near(a.z, b.z) and near(a.y, b.y)
end
local function is_lower_door(point)
    return same_position(point, lower_north) or same_position(point, lower_south)
end
local function is_upper_door(point)
    return same_position(point, upper_north) or same_position(point, upper_south)
end

nav_compute_mesh_route = function(start_point, end_point)
    calls:append(T{ start_point = copy(start_point), end_point = copy(end_point) })
    local start_lower = near(start_point.y, 0, 2.6)
    local start_upper = near(start_point.y, -14, 4.1) or is_upper_door(start_point)
    local end_upper_destination = (tonumber(end_point.x) or 0) > 40 and near(end_point.y, -14, 2.1)
    local end_lower_destination = (tonumber(end_point.x) or 0) < -20 and near(end_point.y, 0, 2.6) and not is_lower_door(end_point)
    if start_lower and is_lower_door(end_point) then
        if unsafe_approach then
            return T{ copy(start_point), T{ zone = 237, x = -3.8, z = 2.6, y = 0 }, copy(end_point) }
        end
        return T{ copy(start_point), T{ zone = 237, x = -38, z = end_point.z, y = 0 }, copy(end_point) }
    end
    if continuation_enabled and start_upper and end_upper_destination then
        return T{ copy(start_point), T{ zone = 237, x = 20, z = end_point.z, y = -14 }, copy(end_point) }
    end
    if start_upper and is_upper_door(end_point) then
        return T{ copy(start_point), T{ zone = 237, x = -20, z = end_point.z, y = -14 }, copy(end_point) }
    end
    if continuation_enabled and start_lower and end_lower_destination then
        return T{ copy(start_point), T{ zone = 237, x = -38, z = start_point.z, y = 0 }, copy(end_point) }
    end
    return T{ copy(end_point) }
end
nav_distance = function(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end
spoken = T{}
speak = function(text) spoken:append(text) end
logs = T{}
log_line = function(text) logs:append(text) end
tick = function() return 1000 end

accessxi = {
    nav_route_points = T{},
    nav_route_point_index = 1,
    nav_route_last_recalc_tick = 0,
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

local player = T{ zone = 237, x = -30.805, z = 2.409, y = 0 }
local naji = T{ zone = 237, name = 'Naji', x = 66.865, z = -4.562, y = -13.999, kind = 'npc' }
local route = accessxi.nav_metalworks_elevator_route(player, naji)
assert(route:len() == 3)
assert(accessxi.nav_transport_transition ~= nil)
assert(accessxi.nav_transport_transition.direction == 'up')
assert(accessxi.nav_transport_transition.elevator_id == 'metalworks-north-elevator' or accessxi.nav_transport_transition.elevator_id == 'metalworks-south-elevator')
assert(near(accessxi.nav_transport_transition.from_landing.x, -58.850))
for _, point in ipairs(route) do
    assert((tonumber(point.x) or 0) < -20, 'approach route entered the Bastok Markets zone trigger corridor')
    assert(math.abs(tonumber(point.y) or 0) < 3, 'approach route fabricated a vertical elevator edge')
end

-- Starting inside the trigger guard is allowed only when the first leg moves away.
accessxi.nav_transport_clear('test-arrival-route')
local arrival_player = T{ zone = 237, x = -9.168, z = -0.498, y = 0 }
local arrival_route = accessxi.nav_metalworks_elevator_route(arrival_player, naji)
assert(arrival_route:len() > 1)
assert((tonumber(arrival_route[2].x) or 0) < -20)

-- Prove that behavior is destination-generic and not tied to Naji's name.
accessxi.nav_transport_clear('test-new-destination')
local other = T{ zone = 237, name = 'Presidential guard', x = 60, z = -2, y = -14, kind = 'npc' }
local other_route = accessxi.nav_metalworks_elevator_route(player, other)
assert(other_route:len() > 1)
assert(accessxi.nav_transport_transition.destination_name == other.name)

-- The same verified transition must work in reverse without a separate NPC rule.
accessxi.nav_transport_clear('test-downward-route')
local upper_player = T{ zone = 237, x = 66.865, z = -4.562, y = -14 }
local lower_destination = T{ zone = 237, name = 'Lower floor clerk', x = -30.805, z = 2.409, y = 0, kind = 'npc' }
local downward = accessxi.nav_metalworks_elevator_route(upper_player, lower_destination)
assert(downward:len() > 1)
assert(accessxi.nav_transport_transition.direction == 'down')
for _, point in ipairs(downward) do
    assert(math.abs((tonumber(point.y) or 0) + 14) < 4.1, 'downward approach fabricated a vertical elevator edge')
end

-- Both independently walkable halves are mandatory.
accessxi.nav_transport_clear('test-unverified-half')
continuation_enabled = false
local rejected = accessxi.nav_metalworks_elevator_route(player, naji)
assert(rejected:len() == 0)
assert(accessxi.nav_transport_transition == nil)
continuation_enabled = true

-- Even a multi-point navmesh result is rejected if it enters the real zone trigger.
unsafe_approach = true
local zone_rejected = accessxi.nav_metalworks_elevator_route(player, naji)
assert(zone_rejected:len() == 0)
assert(accessxi.nav_transport_transition == nil)
unsafe_approach = false

-- At the native lower door, guidance pauses and explains the automatic elevator.
route = accessxi.nav_metalworks_elevator_route(player, naji)
accessxi.nav_route_points = route
local state = accessxi.nav_transport_transition
local handled = accessxi.nav_transport_transition_poll(copy(state.from_landing), naji, 2000)
assert(handled == true)
assert(accessxi.nav_transport_transition.phase == 'waiting')
assert(accessxi.nav_transport_transition_waiting(nil, 2100) == true)
assert(string.find(spoken[#spoken], 'elevator', 1, true) ~= nil)
assert(string.find(spoken[#spoken], 'upper floor', 1, true) ~= nil)
local boarding_target, boarding_handled = accessxi.nav_transport_waiting_beacon_target(copy(state.from_landing), 2100)
assert(boarding_handled == true)
assert(boarding_target ~= nil)
assert(near(boarding_target.x, state.elevator_id == 'metalworks-south-elevator' and -55.978 or -56.006))
local aboard = copy(boarding_target)
aboard.y = state.from_landing.y
local quiet_target, quiet_handled = accessxi.nav_transport_waiting_beacon_target(aboard, 2200)
assert(quiet_handled == true)
assert(quiet_target == nil)

-- A live floor change resumes a fresh verified route from the current position.
local arrival = copy(state.to_landing)
arrival.y = -14
handled = accessxi.nav_transport_transition_poll(arrival, naji, 3000)
assert(handled == true)
assert(accessxi.nav_transport_transition == nil)
assert(accessxi.nav_route_points:len() > 1)
assert(accessxi.nav_route_point_index == 2)
assert(string.find(spoken[#spoken], 'Route resumed', 1, true) ~= nil)

return true
'@

$escapedModulePath = $modulePath.Replace('\', '\\').Replace("'", "\'")
& $luaPath -e "module_path='$escapedModulePath'; $luaHarness"
if ($LASTEXITCODE -ne 0) { throw "Metalworks elevator Lua behavior harness failed with exit code $LASTEXITCODE." }

Write-Host "nav Metalworks elevator tests passed (direct=$directCount unsafe-old=$unsafeOldCount south=$southLowerCount/$southUpperCount north=$northLowerCount/$northUpperCount arrival=$arrivalLowerCount return=$upperReturnCount/$lowerReturnCount vertical=$verticalCount)"

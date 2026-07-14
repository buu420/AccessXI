$ErrorActionPreference = 'Stop'

$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaExe = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
$navProbe = 'C:\Users\buu42\AccessXI\tools\navprobe\bin\Release\net8.0\win-x86\publish\navprobe.exe'
$mesh = 'C:\Users\buu42\Ashita\addons\accessxi_reader\third_party\xiNavmeshes\La_Theine_Plateau.nav'

function Assert-Match {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

# Exact live loop position and the nearest retained waypoint from the walked
# ravine escape. The current mesh requires a bend around the embankment; a
# direct player-to-waypoint segment is therefore not a safe reattachment.
$probeOutput = & $navProbe $mesh '-453.631' '-0.298' '230.109' '-457.872' '-1.794' '229.261'
if ($LASTEXITCODE -ne 0) {
    throw "navprobe failed for the live La Theine reattachment regression: $probeOutput"
}
$probeWaypoints = @($probeOutput | Where-Object { $_ -match '^\d+\t' })
if ($probeWaypoints.Count -lt 3 -or $probeWaypoints.Count -gt 16) {
    throw "Expected a short bent connector around the live embankment, got $($probeWaypoints.Count) waypoints."
}

$source = Get-Content -LiteralPath $sourceLuaPath -Raw
$projectFunction = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_project_to_segment\(pos, a, b\).*?\r?\nend'
)
$liveMatchFunction = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_route_live_match\(pos, points[^\)]*\).*?\r?\nend'
)
$connectorFunction = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_lathine_recorded_corridor_start_connector\(player, corridor, route_id, preferred_index\).*?\r?\nend'
)
if (-not $projectFunction.Success -or -not $liveMatchFunction.Success -or -not $connectorFunction.Success) {
    throw 'Missing continuous safe recorded-corridor start matching.'
}

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_lathine_recorded_corridor_candidate\(player, point, corridor, player_index, direction\)[\s\S]*?nav_lathine_recorded_corridor_start_connector\(\s*player, corridor, route_id, player_index\)' `
    -Message 'Directional recorded-corridor routes must begin with a validated connector.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_lathine_recorded_corridor_slice\(player, point, corridor, player_index, destination_index\)[\s\S]*?nav_lathine_recorded_corridor_start_connector\(\s*player, corridor, route_id, player_index\)' `
    -Message 'Recorded-corridor slices must begin with a validated connector.'

$harness = @"
accessxi = {}

function string.fmt(self, ...)
    return string.format(self, ...)
end

function T(value)
    value = value or {}
    local mt = {
        __index = {
            append = function(self, item) table.insert(self, item) end,
            len = function(self) return #self end,
            clear = function(self) while #self > 0 do table.remove(self) end end,
        }
    }
    return setmetatable(value, mt)
end

local function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz))
end

local mesh_result = T{}
local function nav_compute_mesh_route(player, waypoint)
    return mesh_result
end

local function log_line(_) end
function accessxi.escape_probe_log_text(value) return value end
function accessxi.nav_route_quarantine_reason(_, _) return '' end
function accessxi.nav_lathine_recorded_corridor_append(points, waypoint, route_id, suffix)
    points:append(T{
        zone = waypoint.zone,
        x = waypoint.x,
        z = waypoint.z,
        y = waypoint.y,
        source = 'route-override:' .. route_id .. suffix,
        route_override_id = route_id,
    })
end
function accessxi.nav_lathine_recorded_corridor_length(points)
    local length = 0
    for i = 2, points:len() do length = length + nav_distance(points[i - 1], points[i]) end
    return length
end

$($projectFunction.Value)
$($liveMatchFunction.Value)
$($connectorFunction.Value)

local player = T{ zone = 102, x = -453.631, z = 230.109, y = -0.298 }
local join = T{ zone = 102, x = -457.872, z = 229.261, y = -1.794 }
local old_embankment = T{ waypoints = T{
    join,
    T{ zone = 102, x = -461.000, z = 228.800, y = -2.100 },
} }
mesh_result = T{
    T{ zone = 102, x = -453.573, z = 230.132, y = -0.557 },
    T{ zone = 102, x = -453.200, z = 229.200, y = -0.650 },
    T{ zone = 102, x = -452.800, z = 227.600, y = -0.650 },
    T{ zone = 102, x = -453.600, z = 227.200, y = -1.250 },
    T{ zone = 102, x = -457.872, z = 229.261, y = -2.203 },
}

local connector = accessxi.nav_lathine_recorded_corridor_start_connector(player, old_embankment, 'safe-west', 1)
assert(connector:len() == 0,
    'live-disproved embankment shortcut must stay outside the continuous start bound')

mesh_result = T{}
connector = accessxi.nav_lathine_recorded_corridor_start_connector(player, T{ waypoints = T{} }, 'safe-west', 1)
assert(connector:len() == 0, 'missing recorded geometry must stay silent')

local recorded_near = T{ zone = 102, x = -453.306, z = 228.992, y = -0.500 }
local live_near = T{ zone = 102, x = -453.422, z = 229.171, y = -0.467 }
local near_corridor = T{ waypoints = T{
    recorded_near,
    T{ zone = 102, x = -452.000, z = 228.500, y = -0.450 },
} }
local start_index
connector, start_index = accessxi.nav_lathine_recorded_corridor_start_connector(live_near, near_corridor, 'safe-west', 1)
assert(connector:len() == 1 and start_index == 2, 'sub-yalm live projection to the walked survey was rejected')
assert(connector[1].route_override_id == 'safe-west', 'live projection lost precise route identity')

local live_detour = T{ zone = 102, x = -524.582, z = 378.291, y = -0.883 }
local detour_corridor = T{ waypoints = T{
    T{ zone = 102, x = -520.728, z = 380.195, y = -0.531 },
    T{ zone = 102, x = -523.984, z = 381.284, y = -0.762 },
    T{ zone = 102, x = -526.083, z = 382.002, y = -0.731 },
} }
connector, start_index = accessxi.nav_lathine_recorded_corridor_start_connector(live_detour, detour_corridor, 'safe-west', 2)
assert(connector:len() == 1 and start_index == 2,
    'three-yalm live combat detour did not reconnect to the current recorded segment')
assert(math.abs(connector[1].x - (-523.622)) < 0.01 and math.abs(connector[1].z - 381.163) < 0.01,
    'live start connector snapped to a recorder sample instead of the current segment projection')

mesh_result = T{
    T{ zone = 102, x = -453.6, z = 230.1, y = -0.3 },
    T{ zone = 102, x = -430.0, z = 230.1, y = -0.3 },
    T{ zone = 102, x = -457.9, z = 229.3, y = -1.8 },
}
connector = accessxi.nav_lathine_recorded_corridor_start_connector(
    T{ zone = 102, x = -524.582, z = 388.291, y = -0.883 }, detour_corridor, 'safe-west', 2)
assert(connector:len() == 0, 'position outside the safe live start bound must stay silent')

print('recorded corridor safe start connector behavior ok')
"@

$tempLua = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + '.lua')
try {
    [System.IO.File]::WriteAllText($tempLua, $harness, (New-Object System.Text.UTF8Encoding($false)))
    $output = & $luaExe $tempLua
    $luaExitCode = $LASTEXITCODE
}
finally {
    Remove-Item -LiteralPath $tempLua -Force -ErrorAction SilentlyContinue
}
if ($luaExitCode -ne 0) {
    throw "Lua start-connector regression failed: $output"
}

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) {
    throw 'Source and live Lua copies are not byte-identical.'
}

Write-Host $output

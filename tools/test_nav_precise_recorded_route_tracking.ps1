$ErrorActionPreference = 'Stop'

$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaExe = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'

function Extract-LuaFunction {
    param([string]$Source, [string]$Name)
    $match = [regex]::Match(
        $Source,
        "(?s)function accessxi\.$([regex]::Escape($Name))\([^\r\n]*\).*?\r?\nend"
    )
    if (-not $match.Success) { throw "Missing Lua function accessxi.$Name." }
    return $match.Value
}

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NoMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

$source = Get-Content -LiteralPath $sourceLuaPath -Raw
$projectFunction = Extract-LuaFunction $source 'nav_project_to_segment'
$matchFunction = Extract-LuaFunction $source 'nav_route_live_match'
$passedFunction = Extract-LuaFunction $source 'nav_precise_route_waypoint_passed'
$trackingFunction = Extract-LuaFunction $source 'nav_precise_route_track_index'

Assert-Match $trackingFunction 'nav_route_live_match\(\s*player,\s*accessxi\.nav_route_points' `
    'High-frequency precise tracking must map the current player position onto the recorded route.'
Assert-Match $trackingFunction 'nav_route_point_index\s*=\s*desired' `
    'Precise tracking must replace stale progress with the live matched segment.'
Assert-Match $source 'local now = tick\(\);[\s\S]*?nav_precise_route_track_index\(nav_cached_player_position\(\), now\);[\s\S]*?nav_route_poll_ms' `
    'Precise route progress must update before the 850 ms guidance throttle.'
Assert-Match $source 'route_count > 1[\s\S]*?not precise_override[\s\S]*?real_waypoint_distance <= accessxi\.nav_route_waypoint_arrival_radius' `
    'The throttled guidance loop must not separately consume precise-route waypoints.'

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
string.fmt = string.format

accessxi = {
    nav_route_points = T({
        { x = -340.570, z = 371.834, y = 8.129, zone = 102 },
        { x = -340.140, z = 372.566, y = 8.089, zone = 102 },
        { x = -340.378, z = 370.527, y = 8.269, zone = 102 },
        { x = -340.656, z = 368.170, y = 8.481, zone = 102 }
    }),
    nav_route_point_index = 1,
    nav_precise_route_track_tick = 0
}

local function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz
end
function log_line(_) end
function accessxi.nav_route_precise_override_active(_, _) return true end

$projectFunction
$matchFunction
$passedFunction
$trackingFunction

local at_4006 = { x = -339.909, z = 372.164, y = 8.123, zone = 102 }
assert(accessxi.nav_precise_route_track_index(at_4006, 100) == true,
    'live sample at waypoint 4006 did not advance to the escape')
assert(accessxi.nav_route_point_index == 2, 'near-tied live match did not retain the current recorded leg')

assert(accessxi.nav_precise_route_track_index(at_4006, 100) == false,
    'same tracking tick consumed more than one waypoint')
assert(accessxi.nav_route_point_index == 2, 'same tick changed the live match twice')

local at_escape_3 = { x = -340.378, z = 370.527, y = 8.269, zone = 102 }
assert(accessxi.nav_precise_route_track_index(at_escape_3, 160) == true,
    'fast movement across escape sample 2 did not advance locally')
assert(accessxi.nav_route_point_index == 4, 'exact waypoint tie did not select the forward segment toward the destination')

local wrong_shelf = { x = -340.656, z = 368.170, y = 13.481, zone = 102 }
assert(accessxi.nav_precise_route_track_index(wrong_shelf, 220) == false,
    'same horizontal route on the wrong shelf advanced')
assert(accessxi.nav_route_point_index == 4, 'wrong shelf changed the route index')

print('precise recorded route high-frequency tracking ok')
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
if ($luaExitCode -ne 0) { throw "Lua precise-route tracking regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

$ErrorActionPreference = 'Stop'

$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaExe = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
$source = Get-Content -LiteralPath $sourceLuaPath -Raw

function Extract-LuaFunction {
    param([string]$Name, [bool]$Required = $true)
    $match = [regex]::Match(
        $source,
        "(?s)function accessxi\.$([regex]::Escape($Name))\([^\r\n]*\).*?\r?\nend"
    )
    if (-not $match.Success) {
        if ($Required) { throw "Missing Lua function accessxi.$Name." }
        return ''
    }
    return $match.Value
}

$projectFunction = Extract-LuaFunction 'nav_project_to_segment'
$matchFunction = Extract-LuaFunction 'nav_route_live_match'
$targetFunction = Extract-LuaFunction 'nav_route_target_from_match'
$clearFunction = Extract-LuaFunction 'nav_precise_route_return_clear' $false
$steeringFunction = Extract-LuaFunction 'nav_precise_steering_target'

if ($source -notmatch '(?s)function accessxi\.poll_nav_beacon\(\).*?local precise_override = accessxi\.nav_route_precise_override_active.*?if \(not precise_override\) then\s*route_target = accessxi\.nav_apply_dynamic_obstacle.*?route_target = accessxi\.nav_apply_wall_avoidance') {
    throw 'Precise recorded beacon routes are no longer isolated from obstacle and wall target substitution.'
}

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
string.fmt = string.format

accessxi = {}

local function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz
end

$projectFunction
$matchFunction
$targetFunction
$clearFunction
$steeringFunction

local function nearly_equal(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) < 0.001
end

local live_points = T({
    { x = -539.626, z = 437.033, y = -0.553, zone = 102 },
    { x = -540.356, z = 441.659, y = -0.551, zone = 102 },
    { x = -542.287, z = 446.305, y = -0.382, zone = 102 },
    { x = -543.880, z = 448.842, y = -0.367, zone = 102 },
    { x = -547.110, z = 452.605, y = -0.347, zone = 102 },
    { x = -553.581, z = 457.275, y = -0.732, zone = 102 },
    { x = -560.424, z = 459.897, y = -0.519, zone = 102 }
})
local live_player = { x = -539.226, z = 451.158, y = -0.994, zone = 102 }
local first_target = accessxi.nav_precise_steering_target(live_player, live_points, 5, 5)
assert(first_target ~= nil and first_target.source == 'live-route-lookahead'
    and first_target.x < -547 and first_target.z > 452,
    'live sample did not select a forward intercept on the authoritative recording')

local moved_player = { x = -541.000, z = 452.000, y = -0.900, zone = 102 }
local moved_match = accessxi.nav_route_live_match(moved_player, live_points, 4)
local moving_target = accessxi.nav_route_target_from_match(moved_player, live_points, moved_match, 5)
assert(moving_target ~= nil and moving_target.source == 'live-route-lookahead',
    'moving live sample did not retain a forward intercept')
local held_target = accessxi.nav_precise_steering_target(moved_player, live_points, 5, 5)
assert(held_target ~= nil
    and held_target.source == 'live-route-lookahead'
    and held_target.x < -547,
    'moving toward the recording lost the forward authoritative intercept')

local far_target = accessxi.nav_precise_steering_target(
    { x = -533.000, z = 451.000, y = -0.900, zone = 102 }, live_points, 5, 5)
assert(far_target == nil,
    'moving beyond the verified anchor envelope selected a different course')

local sharp = T({
    { x = 0, z = 0, y = 0, zone = 102 },
    { x = 2, z = 0, y = 0, zone = 102 },
    { x = 2, z = 4, y = 0, zone = 102 },
    { x = 2, z = 8, y = 0, zone = 102 }
})
local sharp_target = accessxi.nav_precise_steering_target(
    { x = 0, z = 0, y = 0, zone = 102 }, sharp, 4, 5)
assert(sharp_target ~= nil and nearly_equal(sharp_target.x, 2) and nearly_equal(sharp_target.z, 0),
    'recorded-route recovery cut across a sharp corner')

local straight = T({
    { x = 0, z = 0, y = 0, zone = 102 },
    { x = 5, z = 0, y = 0, zone = 102 },
    { x = 10, z = 0, y = 0, zone = 102 }
})
local distant_target = accessxi.nav_precise_steering_target(
    { x = 5, z = 7, y = 0, zone = 102 }, straight, 1, 5)
assert(distant_target == nil, 'unsafe distant match produced recorded-route guidance')

print('authoritative recorded route steering behavior ok')
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
if ($luaExitCode -ne 0) { throw "Lua authoritative-route regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

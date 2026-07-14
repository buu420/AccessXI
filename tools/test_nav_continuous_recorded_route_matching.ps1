$ErrorActionPreference = 'Stop'

$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaExe = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
$source = Get-Content -LiteralPath $sourceLuaPath -Raw

function Extract-LuaFunction {
    param([string]$Name)
    $match = [regex]::Match(
        $source,
        "(?s)function accessxi\.$([regex]::Escape($Name))\([^\r\n]*\).*?\r?\nend"
    )
    if (-not $match.Success) { throw "Missing Lua function accessxi.$Name." }
    return $match.Value
}

$projectFunction = Extract-LuaFunction 'nav_project_to_segment'
$matchFunction = Extract-LuaFunction 'nav_route_live_match'
$targetFunction = Extract-LuaFunction 'nav_route_target_from_match'
$trackingFunction = Extract-LuaFunction 'nav_precise_route_track_index'
$clearFunction = Extract-LuaFunction 'nav_precise_route_return_clear'
$steeringFunction = Extract-LuaFunction 'nav_precise_steering_target'

if ($trackingFunction -notmatch 'nav_route_live_match') {
    throw 'Precise route progress is not derived from the current live route match.'
}
if ($trackingFunction -notmatch 'nav_route_point_index\s*=\s*desired') {
    throw 'Precise route progress cannot advance to the live match.'
}
if ($steeringFunction -notmatch 'nav_route_live_match') {
    throw 'Recorded-route steering is still based on a stored waypoint index.'
}

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
string.fmt = string.format

accessxi = {
    nav_route_points = T({}),
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
$targetFunction
$trackingFunction
$clearFunction
$steeringFunction

local straight = T({
    { x = 0, z = 0, y = 0, zone = 102 },
    { x = 2, z = 0, y = 0, zone = 102 },
    { x = 4, z = 0, y = 0, zone = 102 },
    { x = 6, z = 0, y = 0, zone = 102 },
    { x = 8, z = 0, y = 0, zone = 102 },
    { x = 10, z = 0, y = 0, zone = 102 }
})
accessxi.nav_route_points = straight

local player = { x = 7.2, z = 0, y = 0, zone = 102 }
local match = accessxi.nav_route_live_match(player, straight)
assert(match ~= nil and match.segment == 4, 'live matcher did not locate a player far beyond a stale early index')
assert(accessxi.nav_precise_route_track_index(player, 100) == true, 'forward live match did not update progress')
assert(accessxi.nav_route_point_index == 5, 'forward live match selected the wrong route index')

player = { x = 3.1, z = 0, y = 0, zone = 102 }
assert(accessxi.nav_precise_route_track_index(player, 160) == false,
    'backtracking rewound progress to an already completed recorded segment')
assert(accessxi.nav_route_point_index == 5,
    'route progress rewound after the player moved backward')

player = { x = 9.4, z = 0, y = 0, zone = 102 }
assert(accessxi.nav_precise_route_track_index(player, 220) == true, 'one-poll speed jump did not update progress')
assert(accessxi.nav_route_point_index == 6, 'speed jump remained attached to skipped samples')

local layered = T({
    { x = 0, z = 0, y = 0, zone = 102 },
    { x = 10, z = 0, y = 0, zone = 102 },
    { x = 20, z = 0, y = 5, zone = 102 },
    { x = 10, z = 0, y = 10, zone = 102 },
    { x = 0, z = 0, y = 10, zone = 102 }
})
match = accessxi.nav_route_live_match({ x = 5, z = 0, y = 9.5, zone = 102 }, layered)
assert(match ~= nil and match.segment == 4 and match.vertical < 0.51,
    'live matcher aliased an upper shelf to lower overlapping geometry')

local parallel = T({
    { x = 0, z = 0, y = 0, zone = 102 },
    { x = 10, z = 0, y = 0, zone = 102 },
    { x = 20, z = 20, y = 0, zone = 102 },
    { x = 10, z = 0.4, y = 0, zone = 102 },
    { x = 0, z = 0.4, y = 0, zone = 102 }
})
match = accessxi.nav_route_live_match({ x = 5, z = 0.19, y = 0, zone = 102 }, parallel, 1)
assert(match ~= nil and match.segment == 1,
    'nearby parallel recorded legs ignored the current live segment on an ambiguous match')
match = accessxi.nav_route_live_match({ x = 5, z = 0.21, y = 0, zone = 102 }, parallel, 4)
assert(match ~= nil and match.segment == 4,
    'nearby parallel recorded legs could not retain the later live segment')

player = { x = 5, z = 3, y = 0, zone = 102 }
local target = accessxi.nav_precise_steering_target(player, straight, 1, 5)
assert(target ~= nil and math.abs(target.x - 10) < 0.01 and math.abs(target.z) < 0.01,
    'small lateral combat detour did not retain smooth forward route lookahead')

local inside_target = accessxi.nav_precise_steering_target(
    { x = 5, z = 1.49, y = 0, zone = 102 }, straight, 1, 5)
local outside_target = accessxi.nav_precise_steering_target(
    { x = 5, z = 1.51, y = 0, zone = 102 }, straight, 1, 5)
assert(inside_target ~= nil and outside_target ~= nil
        and math.abs(inside_target.x - outside_target.x) < 0.01
        and math.abs(inside_target.z - outside_target.z) < 0.01,
    'tiny cross-track change caused a forward/back steering-target discontinuity')

target = accessxi.nav_precise_steering_target({ x = 5, z = 4, y = 0, zone = 102 }, straight, 1, 5)
assert(target ~= nil and math.abs(target.x - 10) < 0.01 and math.abs(target.z) < 0.01,
    'large but bounded route drift did not select a forward route intercept')

local before_recovery_boundary = accessxi.nav_precise_steering_target(
    { x = 5, z = 3.24, y = 0, zone = 102 }, straight, 1, 5)
local after_recovery_boundary = accessxi.nav_precise_steering_target(
    { x = 5, z = 3.26, y = 0, zone = 102 }, straight, 1, 5)
assert(before_recovery_boundary ~= nil and after_recovery_boundary ~= nil
        and nav_distance(before_recovery_boundary, after_recovery_boundary) < 0.05,
    'crossing the recovery threshold flipped the steering target from forward to sideways')

local west_entry = T({
    { x = -559.850, z = 677.532, y = 0.000, zone = 102 },
    { x = -561.033, z = 675.675, y = 0.015, zone = 102 },
    { x = -562.221, z = 673.983, y = 0.100, zone = 102 },
    { x = -564.151, z = 671.898, y = 0.115, zone = 102 },
    { x = -565.507, z = 670.711, y = -0.246, zone = 102 },
    { x = -567.667, z = 668.910, y = -0.836, zone = 102 },
    { x = -569.394, z = 667.441, y = -1.528, zone = 102 },
    { x = -571.610, z = 665.335, y = -2.309, zone = 102 }
})
target = accessxi.nav_precise_steering_target(
    { x = -567.535, z = 675.328, y = -1.305, zone = 102 }, west_entry, 6, 5)
assert(target ~= nil and target.source == 'live-route-lookahead' and target.z < 669.5,
    'the live West Ronfaure entry drift sample aimed at a sideways return point instead of forward')

local survey_bend = T({
    { x = -563.914, z = 644.329, y = 0.010, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -562.348, z = 642.470, y = 0.000, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -560.515, z = 640.291, y = 0.000, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -560.382, z = 640.134, y = 0.000, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -561.358, z = 638.775, y = 0.000, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -563.082, z = 638.059, y = 0.000, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -564.939, z = 637.365, y = 0.046, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -567.748, z = 636.073, y = 0.157, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' },
    { x = -569.584, z = 635.154, y = -0.017, zone = 102, route_override_id = 'lathine-recorded-survey-20260712' }
})
target = accessxi.nav_precise_steering_target(
    { x = -565.262, z = 644.677, y = 0.095, zone = 102 }, survey_bend, 1, 5)
assert(target ~= nil and target.source == 'live-route-lookahead'
        and math.abs(target.x - -563.060) < 0.05
        and math.abs(target.z - 638.068) < 0.05,
    'full-survey steering did not use the working-zone nine-yalm live lookahead')

target = accessxi.nav_precise_steering_target(
    { x = -561.865, z = 641.198, y = 0.000, zone = 102 }, survey_bend, 3, 5)
assert(target ~= nil and target.source == 'live-route-lookahead'
        and target.x < -565 and target.z < 637,
    'full-survey steering pinned the beacon to the Cavernous Maw mark instead of looking through the bend')

target = accessxi.nav_precise_steering_target({ x = 5, z = 0, y = 0, zone = 102 }, straight, 1, 5)
assert(target ~= nil and math.abs(target.x - 10) < 0.01,
    'on-route steering did not look ahead from the live projection')

local sharp = T({
    { x = 0, z = 0, y = 0, zone = 102 },
    { x = 2, z = 0, y = 0, zone = 102 },
    { x = 2, z = 4, y = 0, zone = 102 },
    { x = 2, z = 8, y = 0, zone = 102 }
})
target = accessxi.nav_precise_steering_target({ x = 0, z = 0, y = 0, zone = 102 }, sharp, 4, 5)
assert(target ~= nil and math.abs(target.x - 2) < 0.01 and math.abs(target.z) < 0.01,
    'continuous lookahead cut across a sharp recorded corner')
target = accessxi.nav_precise_steering_target({ x = 1.8, z = 0, y = 0, zone = 102 }, sharp, 1, 5)
assert(target ~= nil and target.z > 3.9, 'continuous lookahead did not proceed after reaching the corner')

target = accessxi.nav_precise_steering_target({ x = 5, z = 7, y = 0, zone = 102 }, straight, 1, 5)
assert(target == nil, 'unsafe unmatched position produced recorded-route guidance')

print('continuous recorded route matching behavior ok')
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
if ($luaExitCode -ne 0) { throw "Lua continuous-route regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

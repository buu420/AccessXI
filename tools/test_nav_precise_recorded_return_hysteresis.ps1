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
$clearFunction = Extract-LuaFunction 'nav_precise_route_return_clear'
$steeringFunction = Extract-LuaFunction 'nav_precise_steering_target'

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end

accessxi = {
    nav_precise_return_target = nil,
    nav_precise_return_points = nil,
    nav_precise_return_segment = 0,
}

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

local id = 'lathine-recorded-corridor-20260712-west-via-ravine-01'
local points = T({
    { x = -451.419, z = 212.173, y = 2.356, zone = 102, route_override_id = id },
    { x = -449.415, z = 217.777, y = 1.383, zone = 102, route_override_id = id },
    { x = -450.415, z = 219.165, y = 0.847, zone = 102, route_override_id = id },
    { x = -455.412, z = 222.377, y = -0.983, zone = 102, route_override_id = id },
    { x = -456.708, z = 224.552, y = -1.720, zone = 102, route_override_id = id },
    { x = -457.872, z = 229.261, y = -1.794, zone = 102, route_override_id = id },
})

local overshot = { x = -456.160, z = 222.458, y = -1.219, zone = 102 }
local first = accessxi.nav_precise_steering_target(overshot, points, 4, 5)
assert(first ~= nil and first.source == 'live-route-return',
    'off-route recovery did not produce a latched return target')
assert(accessxi.nav_precise_return_target == first,
    'off-route recovery target was not stored for beacon hysteresis')

local near_anchor = { x = -455.381, z = 223.124, y = -1.153, zone = 102 }
local second = accessxi.nav_precise_steering_target(near_anchor, points, 4, 5)
assert(second == first,
    'sub-yalm movement replaced the recovery target and can flip the beacon front-to-rear')

local reached_anchor = { x = -455.410, z = 222.380, y = -0.983, zone = 102 }
local third = accessxi.nav_precise_steering_target(reached_anchor, points, 4, 5)
assert(third ~= nil and third ~= first and third.source == 'live-route-lookahead',
    'reaching the recorded line did not release the recovery target forward')

print('precise recorded return-target hysteresis behavior ok')
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
if ($luaExitCode -ne 0) { throw "Lua return-hysteresis regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

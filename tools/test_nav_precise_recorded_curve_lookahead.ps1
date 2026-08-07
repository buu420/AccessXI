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

local function route(route_id, x, z)
    return T({
        { zone = 102, x = x, z = z, y = 0, route_override_id = route_id },
        { zone = 102, x = x + 5, z = z, y = 0, route_override_id = route_id },
        { zone = 102, x = x + 10, z = z, y = 0, route_override_id = route_id },
    })
end

local cliff_id = 'lathine-recorded-corridor-20260712-01'
local cliff_points = route(cliff_id, 10, -274)
local cliff_player = { zone = 102, x = 10, z = -274, y = 0 }
local target = accessxi.nav_precise_steering_target(cliff_player, cliff_points, 1, 5)
local distance = nav_distance(cliff_player, target)
assert(target ~= nil and distance >= 1.75 and distance <= 2.75,
    'cliff path 1 still aims too far ahead to follow its delicate curve')

local west_id = 'lathine-recorded-corridor-20260712-west-via-ravine-01'
local west_points = route(west_id, -451, 212)
local west_player = { zone = 102, x = -451, z = 212, y = 0 }
target = accessxi.nav_precise_steering_target(west_player, west_points, 1, 5)
distance = nav_distance(west_player, target)
assert(target ~= nil and distance >= 1.75 and distance <= 2.75,
    'directional West shelf still aims too far ahead through its delicate bend')

local straight_points = route(west_id, -500, 350)
local straight_player = { zone = 102, x = -500, z = 350, y = 0 }
target = accessxi.nav_precise_steering_target(straight_player, straight_points, 1, 5)
distance = nav_distance(straight_player, target)
assert(target ~= nil and math.abs(distance - 5) < 0.01,
    'curve-only steering restriction leaked onto an ordinary recorded straight')

print('precise recorded curve lookahead behavior ok')
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
if ($luaExitCode -ne 0) { throw "Lua curve-lookahead regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

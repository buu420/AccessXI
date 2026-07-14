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

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
string.fmt = string.format

accessxi = {
    nav_route_points = T({
        { x = -445.350, z = 212.748, y = 3.736, zone = 102 },
        { x = -447.110, z = 208.565, y = 3.661, zone = 102 },
        { x = -448.943, z = 209.014, y = 3.317, zone = 102 },
        { x = -450.548, z = 210.104, y = 2.859, zone = 102 },
        { x = -451.492, z = 210.775, y = 2.473, zone = 102 },
        { x = -451.419, z = 212.173, y = 2.356, zone = 102 },
        { x = -449.415, z = 217.777, y = 1.383, zone = 102 },
        { x = -450.415, z = 219.165, y = 0.847, zone = 102 },
        { x = -455.412, z = 222.377, y = -0.983, zone = 102 }
    }),
    nav_route_point_index = 6,
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

local player = { x = -448.530, z = 211.967, y = 3.198, zone = 102 }
local match = accessxi.nav_route_live_match(player, accessxi.nav_route_points, 5)
assert(match ~= nil and match.segment >= 5,
    'live matching rewound from the current ravine progress to an overlapping earlier segment')

accessxi.nav_precise_route_track_index(player, 100)
assert(accessxi.nav_route_point_index >= 6,
    'precise route progress moved backward inside the recorded ravine escape')

local target = accessxi.nav_precise_steering_target(player, accessxi.nav_route_points, accessxi.nav_route_point_index, 5)
assert(target ~= nil and target.x < -451 and target.z > 211.5,
    'recorded-route steering pointed back into the already walked ravine loop')

print('precise recorded route no-rewind behavior ok')
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
if ($luaExitCode -ne 0) { throw "Lua recorded-route no-rewind regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

$ErrorActionPreference = 'Stop'

$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaExe = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
$source = Get-Content -LiteralPath $sourceLuaPath -Raw

$match = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_precise_steering_target\(player, points, index, lookahead\).*?\r?\nend'
)
if (-not $match.Success) {
    throw 'Missing multi-segment steering target for dense recorded routes.'
}
$functionSource = $match.Value

$projectSource = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_project_to_segment\(pos, a, b\).*?\r?\nend'
).Value
$liveMatchSource = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_route_live_match\(pos, points[^\)]*\).*?\r?\nend'
).Value
$targetSource = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_route_target_from_match\([^\r\n]*\).*?\r?\nend'
).Value
$clearSource = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_precise_route_return_clear\(\).*?\r?\nend'
).Value
if ($projectSource -eq '' -or $liveMatchSource -eq '' -or $targetSource -eq '' -or $clearSource -eq '') {
    throw 'Missing continuous recorded-route steering dependencies.'
}

if ($source -notmatch 'function accessxi\.nav_beacon_route_target\(player\)[\s\S]*?nav_precise_steering_target\(\s*player, accessxi\.nav_route_points, accessxi\.nav_route_point_index, 5\)') {
    throw 'Beacon still chases individual dense recorded waypoints.'
}
if ($source -notmatch 'local function poll_nav_route\(\)[\s\S]*?precise_override[\s\S]*?nav_precise_steering_target\(\s*player, accessxi\.nav_route_points, accessxi\.nav_route_point_index, 5\)') {
    throw 'Spoken route guidance does not share the stable precise steering target.'
}

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end

accessxi = {}

local function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz
end

$projectSource
$liveMatchSource
$targetSource
$clearSource
$functionSource

local player = { zone = 102, x = 0, z = 0, y = 0 }
local dense_straight = T({
    { zone = 102, x = 0, z = 0, y = 0 },
    { zone = 102, x = 2, z = 0, y = 0 },
    { zone = 102, x = 4, z = 0, y = 0 },
    { zone = 102, x = 6, z = 0, y = 0 },
    { zone = 102, x = 8, z = 0, y = 0 },
})
local target = accessxi.nav_precise_steering_target(player, dense_straight, 1, 5)
assert(math.abs(target.x - 5) < 0.01 and math.abs(target.z) < 0.01,
    'dense straight samples did not produce a five-yalm steering carrot')

local sharp_corner = T({
    { zone = 102, x = 2, z = 0, y = 0 },
    { zone = 102, x = 2, z = 4, y = 0 },
    { zone = 102, x = 2, z = 8, y = 0 },
})
target = accessxi.nav_precise_steering_target(player, sharp_corner, 1, 5)
assert(math.abs(target.x - 2) < 0.01 and math.abs(target.z) < 0.01,
    'steering carrot cut across a sharp recorded corner')

player = { zone = 102, x = 1.6, z = 0, y = 0 }
target = accessxi.nav_precise_steering_target(player, sharp_corner, 1, 5)
assert(target.z > 3.9,
    'steering carrot did not continue after the player reached the sharp corner')

local hashes_equal = true
print('precise recorded steering carrot behavior ok')
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
if ($luaExitCode -ne 0) { throw "Lua precise-steering regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

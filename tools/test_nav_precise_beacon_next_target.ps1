$ErrorActionPreference = 'Stop'

$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaExe = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
$source = Get-Content -LiteralPath $sourceLuaPath -Raw

$match = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_beacon_route_target\(player\).*?\r?\nend'
)
if (-not $match.Success) { throw 'Could not extract nav_beacon_route_target.' }
$functionSource = $match.Value

if ($functionSource -notmatch 'nav_route_precise_override_active[\s\S]*?nav_precise_steering_target\([\s\S]*?player, accessxi\.nav_route_points, accessxi\.nav_route_point_index, 5\)') {
    throw 'Precise beacon does not use the stable multi-segment steering target.'
}

$steeringMatch = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_precise_steering_target\(player, points, index, lookahead\).*?\r?\nend'
)
if (-not $steeringMatch.Success) { throw 'Missing precise recorded steering target.' }
$steeringSource = $steeringMatch.Value

$projectMatch = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_project_to_segment\(pos, a, b\).*?\r?\nend'
)
if (-not $projectMatch.Success) { throw 'Missing route segment projection.' }
$projectSource = $projectMatch.Value

$liveMatch = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_route_live_match\(pos, points[^\)]*\).*?\r?\nend'
)
if (-not $liveMatch.Success) { throw 'Missing continuous live route matcher.' }
$liveMatchSource = $liveMatch.Value

$targetMatch = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_route_target_from_match\([^\r\n]*\).*?\r?\nend'
)
if (-not $targetMatch.Success) { throw 'Missing continuous route target builder.' }
$targetSource = $targetMatch.Value

$clearMatch = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_precise_route_return_clear\(\).*?\r?\nend'
)
if (-not $clearMatch.Success) { throw 'Missing precise route return-state reset.' }
$clearSource = $clearMatch.Value

$lookaheadMatch = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_precise_beacon_lookahead_allowed\(player, route_target, next_target\).*?\r?\nend'
)
if (-not $lookaheadMatch.Success) { throw 'Missing precise beacon turn-angle guard.' }
$lookaheadSource = $lookaheadMatch.Value

$guidanceMatch = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_guidance_phrase\(from_pos, route_target, next_target, allow_on_it\).*?\r?\nend'
)
if (-not $guidanceMatch.Success) { throw 'Missing navigation guidance phrase function.' }
$guidanceSource = $guidanceMatch.Value
if ($guidanceSource -notmatch 'nav_precise_beacon_lookahead_allowed\(from_pos, route_target, next_target\)') {
    throw 'Spoken guidance still cuts sharp recorded turns inside five yalms.'
}

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end

accessxi = {
    nav_active = true,
    nav_destination = { zone = 102, x = 100, z = 100, y = 0 },
    nav_route_points = T({}),
    nav_route_point_index = 1
}

local function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz
end
local function nav_vertical_phrase(_, _) return '' end
function string.fmt(self, ...) return string.format(self, ...) end
function accessxi.nav_capitalize(value) return value:sub(1, 1):upper() .. value:sub(2) end
function accessxi.nav_facing_instruction(_, target)
    if target.x == -4 and target.z == 0 then return 'turn left' end
    return 'go straight'
end
function accessxi.nav_sync_route_index(_) end
function accessxi.nav_route_precise_override_active(_, _) return true end
function accessxi.nav_indexed_lookahead_target(_, _, _) return nil, nil end
function accessxi.nav_route_lookahead_distance(_, _) return 12 end

$lookaheadSource
$projectSource
$liveMatchSource
$targetSource
$clearSource
$steeringSource
$guidanceSource
$functionSource

local player = { zone = 102, x = 0, z = 0, y = 0 }
local current = { zone = 102, x = 0, z = 0, y = 0 }
local next_target = { zone = 102, x = 2, z = 0, y = 0 }
accessxi.nav_route_points = T({ current, next_target, { zone = 102, x = 6, z = 0, y = 0 } })
accessxi.nav_route_point_index = 1
local selected = accessxi.nav_beacon_route_target(player)
assert(math.abs(selected.x - 5) < 0.01 and math.abs(selected.z) < 0.01,
    'close precise beacon did not aim five yalms along the recorded line')
assert(accessxi.nav_route_point_index == 1, 'beacon lookahead must not consume route progress')

current = { zone = 102, x = 7, z = 0, y = 0 }
next_target = { zone = 102, x = 12, z = 0, y = 0 }
accessxi.nav_route_points = T({ current, next_target })
accessxi.nav_route_point_index = 1
selected = accessxi.nav_beacon_route_target(player)
assert(selected == nil, 'unsafe unmatched precise route produced beacon guidance')

current = { zone = 102, x = -4, z = 0, y = 0 }
next_target = { zone = 102, x = -4, z = 5, y = 0 }
accessxi.nav_route_points = T({ current, next_target })
accessxi.nav_route_point_index = 1
selected = accessxi.nav_beacon_route_target(player)
assert(selected ~= nil and math.abs(selected.x - current.x) < 0.01 and math.abs(selected.z - current.z) < 0.01,
    'close precise beacon cut a 90-degree recorded corner')

local phrase, distance = accessxi.nav_guidance_phrase(player, current, next_target, false)
assert(phrase:find('Turn left', 1, true) == 1 and math.abs(distance - 4) < 0.01,
    'spoken guidance cut the same 90-degree recorded corner')

accessxi.nav_route_points = T({ current })
accessxi.nav_route_point_index = 1
selected = accessxi.nav_beacon_route_target(player)
assert(selected == accessxi.nav_destination, 'single-point route did not retain existing destination behavior')

print('precise beacon close-range next target ok')
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
if ($luaExitCode -ne 0) { throw "Lua precise-beacon regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

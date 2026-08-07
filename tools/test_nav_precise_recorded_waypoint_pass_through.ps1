$ErrorActionPreference = 'Stop'

$sourceLuaPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$liveLuaPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$luaExe = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'

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

$source = Get-Content -LiteralPath $sourceLuaPath -Raw
$projectFunction = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_project_to_segment\(pos, a, b\).*?\r?\nend'
)
if (-not $projectFunction.Success) {
    throw 'Could not extract nav_project_to_segment for the executable regression test.'
}

$passFunction = [regex]::Match(
    $source,
    '(?s)function accessxi\.nav_precise_route_waypoint_passed\(player, current_target, next_target\).*?\r?\nend'
)
if (-not $passFunction.Success) {
    throw 'Missing precise recorded-route pass-through handling for a waypoint crossed between polls.'
}

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_precise_route_track_index\(player, now\)[\s\S]*?nav_route_live_match\(\s*player,\s*accessxi\.nav_route_points' `
    -Message 'Recorded precise routes must map skipped samples from the current position instead of relying on one-at-a-time pass-through.'

$harness = @"
accessxi = {}
function T(value) return value end

local function nav_distance(a, b)
    local dx = (tonumber(b.x) or 0) - (tonumber(a.x) or 0)
    local dz = (tonumber(b.z) or 0) - (tonumber(a.z) or 0)
    return math.sqrt((dx * dx) + (dz * dz)), dx, dz
end

$($projectFunction.Value)
$($passFunction.Value)

local current_target = { x = -368.682, z = 347.010, y = 7.765, zone = 102 }
local next_target = { x = -367.307, z = 349.584, y = 7.784, zone = 102 }

-- Literal player sample from the 19:15:26 circle reproduction: waypoint 7 was
-- crossed between 850 ms polls and the player was already at waypoint 8.
local crossed = { x = -367.269, z = 349.307, y = 7.786, zone = 102 }
assert(accessxi.nav_precise_route_waypoint_passed(crossed, current_target, next_target) == true,
    'live crossed-waypoint sample was not advanced')

local before_current = { x = -370.128, z = 342.163, y = 8.306, zone = 102 }
assert(accessxi.nav_precise_route_waypoint_passed(before_current, current_target, next_target) == false,
    'player before the waypoint must not advance')

local wrong_shelf = { x = -367.269, z = 349.307, y = 13.786, zone = 102 }
assert(accessxi.nav_precise_route_waypoint_passed(wrong_shelf, current_target, next_target) == false,
    'nearby horizontal geometry on another shelf must not advance')

local off_recorded_leg = { x = -363.500, z = 347.500, y = 7.780, zone = 102 }
assert(accessxi.nav_precise_route_waypoint_passed(off_recorded_leg, current_target, next_target) == false,
    'player away from the recorded next leg must not advance')

print('precise recorded waypoint pass-through behavior ok')
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
    throw "Lua waypoint pass-through regression failed: $output"
}

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) {
    throw 'Source and live Lua copies are not byte-identical.'
}

Write-Host $output

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

$handoffFunction = Extract-LuaFunction 'nav_lathine_live_recorded_corridor_handoff'
if ($source -notmatch '(?s)local route_count = accessxi\.nav_route_points:len\(\).*?nav_lathine_live_recorded_corridor_handoff\(\s*player, destination, accessxi\.nav_route_points\).*?nav live replan') {
    throw 'Active navigation does not check for a safe recorded-corridor handoff before ordinary live replanning.'
}

$harness = @"
local list_methods = {}
function list_methods:len() return #self end
function T(value) return setmetatable(value or {}, { __index = list_methods }) end
string.startswith = function(value, prefix) return value:sub(1, #prefix) == prefix end

accessxi = {}
function accessxi.nav_route_points_override_id(points)
    return tostring(points ~= nil and points[1] ~= nil and points[1].route_override_id or '')
end

local offered = T({
    { x = 1, z = 1, y = 1, zone = 102, route_override_id = 'lathine-recorded-corridor-safe' },
    { x = 2, z = 2, y = 2, zone = 102, route_override_id = 'lathine-recorded-corridor-safe' }
})
function accessxi.nav_lathine_recorded_corridor_route(_, _) return offered, true end

$handoffFunction

local player = { x = 1, z = 1, y = 1, zone = 102 }
local destination = { x = -558, z = 688, y = -7, zone = 102, name = 'West Ronfaure zone line' }
local plain = T({ { x = 1, z = 1, y = 1, zone = 102 }, { x = 3, z = 3, y = 1, zone = 102 } })
local result = accessxi.nav_lathine_live_recorded_corridor_handoff(player, destination, plain)
assert(result:len() == 2, 'plain mesh route did not hand off to the safe recorded corridor')

local unrelated = T({
    { x = 1, z = 1, y = 1, zone = 102, route_override_id = 'some-other-override' },
    { x = 3, z = 3, y = 1, zone = 102, route_override_id = 'some-other-override' }
})
result = accessxi.nav_lathine_live_recorded_corridor_handoff(player, destination, unrelated)
assert(result:len() == 2, 'an unrelated active route prevented a safe recorded-corridor handoff')

result = accessxi.nav_lathine_live_recorded_corridor_handoff(player, destination, offered)
assert(result:len() == 0, 'an active recorded corridor tried to hand off to itself')

offered = T({ { x = 1, z = 1, y = 1, zone = 102 }, { x = 2, z = 2, y = 2, zone = 102 } })
result = accessxi.nav_lathine_live_recorded_corridor_handoff(player, destination, plain)
assert(result:len() == 0, 'a route without a recorded-corridor id was accepted as a live handoff')

player.zone = 101
result = accessxi.nav_lathine_live_recorded_corridor_handoff(player, destination, plain)
assert(result:len() == 0, 'a recorded La Theine corridor was offered outside La Theine')

print('live recorded corridor handoff behavior ok')
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
if ($luaExitCode -ne 0) { throw "Lua live-corridor handoff regression failed: $output" }

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceLuaPath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $liveLuaPath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host $output

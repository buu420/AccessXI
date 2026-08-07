$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

function Assert-NotMatch {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) { throw $Message }
}

foreach ($fragment in @(
    'function accessxi.nav_entity_is_verified_door(pos)',
    'function accessxi.nav_verified_door_ahead(player, route_target)',
    'function accessxi.nav_door_context_active(now)',
    'function accessxi.nav_door_begin_prompt(player, destination, route_target, door, state, now, source)',
    'function accessxi.nav_door_prompt_for_route(player, destination, route_target, now)',
    'function accessxi.nav_door_prompt_for_collision(player, destination, route_target, state, now)',
    'function accessxi.nav_door_waiting(player, now)'
)) {
    Assert-Match -Text $source -Pattern ([regex]::Escape($fragment)) -Message "Missing door-navigation helper: $fragment"
}

$verifiedStart = $source.IndexOf('function accessxi.nav_entity_is_verified_door(pos)')
$verifiedEnd = $source.IndexOf('function accessxi.nav_verified_door_ahead', $verifiedStart)
if ($verifiedStart -lt 0 -or $verifiedEnd -lt 0) { throw 'Could not isolate verified-door classification.' }
$verifiedBody = $source.Substring($verifiedStart, $verifiedEnd - $verifiedStart)
Assert-Match -Text $verifiedBody -Pattern 'tonumber\(pos\.type\)[\s\S]*?~=\s*3[\s\S]*?return false' -Message 'Ashita type 3 must be required, not merely preferred.'
Assert-Match -Text $verifiedBody -Pattern "contains\('door'\)[\s\S]*?contains\('gate'\)[\s\S]*?contains\('entrance'\)" -Message 'Verified doors must also have a conservative door-like live name.'
Assert-NotMatch -Text $verifiedBody -Pattern "tonumber\(pos\.type\)[^\r\n]*==\s*3[^\r\n]*return true" -Message 'Type 3 alone includes lights and bridges and must not prove a door.'

$aheadStart = $source.IndexOf('function accessxi.nav_verified_door_ahead(player, route_target)')
$aheadEnd = $source.IndexOf('function accessxi.nav_door_wait_clear', $aheadStart)
if ($aheadStart -lt 0 -or $aheadEnd -lt 0) { throw 'Could not isolate door-ahead geometry.' }
$aheadBody = $source.Substring($aheadStart, $aheadEnd - $aheadStart)
Assert-Match -Text $aheadBody -Pattern 'nav_live_entity_snapshot\(80,\s*12\)' -Message 'Door evidence must come from nearby live entities.'
Assert-Match -Text $aheadBody -Pattern 'nav_entity_is_verified_door\(pos\)' -Message 'Door geometry must use strict type-and-name verification.'
Assert-Match -Text $aheadBody -Pattern 'side\s*<=\s*4\.5' -Message 'Door must lie inside a narrow route corridor.'
Assert-Match -Text $aheadBody -Pattern 'ahead\s*>\s*0' -Message 'A door behind the player must not prompt.'

foreach ($stateName in @(
    'nav_door_pause_until',
    'nav_door_x',
    'nav_door_z',
    'nav_door_route_unit_x',
    'nav_door_route_unit_z'
)) {
    Assert-Match -Text $source -Pattern ("$stateName\s*=") -Message "Missing directional door state: $stateName"
}

$waitStart = $source.IndexOf('function accessxi.nav_door_waiting(player, now)')
$waitEnd = $source.IndexOf('function accessxi.nav_door_prompt_for_route', $waitStart)
if ($waitStart -lt 0 -or $waitEnd -lt 0) { throw 'Could not isolate directional door wait handling.' }
$waitBody = $source.Substring($waitStart, $waitEnd - $waitStart)
Assert-Match -Text $waitBody -Pattern 'nav_door_pause_until' -Message 'Door speech should use a short audio-only pause separate from prompt debounce.'
Assert-Match -Text $waitBody -Pattern 'nav_door_route_unit_x[\s\S]*?nav_door_route_unit_z' -Message 'Door passage must be measured along the saved route direction.'
Assert-Match -Text $waitBody -Pattern 'progress\s*>=\s*1\.25' -Message 'Door context should clear only after crossing beyond the door plane.'
Assert-NotMatch -Text $waitBody -Pattern 'nav_compute_route_with_zoneline_approach|moved\s*>=\s*2\.5|moved_through' -Message 'Door wait must not replan or treat arbitrary movement as passage.'

$routePromptStart = $source.IndexOf('function accessxi.nav_door_prompt_for_route(player, destination, route_target, now)')
$routePromptEnd = $source.IndexOf('function accessxi.nav_door_prompt_for_collision', $routePromptStart)
if ($routePromptStart -lt 0 -or $routePromptEnd -lt 0) { throw 'Could not isolate proactive route door prompt.' }
$routePromptBody = $source.Substring($routePromptStart, $routePromptEnd - $routePromptStart)
Assert-Match -Text $routePromptBody -Pattern 'nav_verified_door_ahead\(player, route_target\)' -Message 'Proactive prompting must retain strict live door verification and route alignment.'
Assert-Match -Text $routePromptBody -Pattern 'nav_distance\(player, door\)\s*>\s*6' -Message 'Proactive door prompts must stay inside a six-yalm range.'
Assert-Match -Text $routePromptBody -Pattern 'nav_door_begin_prompt' -Message 'Proactive and collision paths should share one prompt-state initializer.'

$promptStart = $source.IndexOf('function accessxi.nav_door_prompt_for_collision(player, destination, route_target, state, now)')
$promptEnd = $source.IndexOf('function accessxi.nav_collision_watch', $promptStart)
if ($promptStart -lt 0 -or $promptEnd -lt 0) { throw 'Could not isolate the door prompt helper.' }
$promptBody = $source.Substring($promptStart, $promptEnd - $promptStart)
Assert-Match -Text $promptBody -Pattern "state\.state\s*~=\s*'blocked'" -Message 'Door instructions should only follow confirmed blocked-route state.'
Assert-Match -Text $promptBody -Pattern 'nav_door_begin_prompt' -Message 'Confirmed collision prompting should share the same route-preserving door state.'

$beginStart = $source.IndexOf('function accessxi.nav_door_begin_prompt(player, destination, route_target, door, state, now, source)')
$beginEnd = $source.IndexOf('function accessxi.nav_door_prompt_for_route', $beginStart)
if ($beginStart -lt 0 -or $beginEnd -lt 0) { throw 'Could not isolate shared door prompt initialization.' }
$beginBody = $source.Substring($beginStart, $beginEnd - $beginStart)
Assert-Match -Text $beginBody -Pattern 'Press Tab until %s is targeted, then press Enter to open it' -Message 'Door prompt must describe the accessible manual interaction.'
Assert-NotMatch -Text $beginBody -Pattern 'setkey|key_down|key_up|DirectInput|axi_drive|QueueCommand|\/press' -Message 'Door handling must never inject Tab or Enter.'

$collisionStart = $source.IndexOf('function accessxi.nav_collision_watch')
$collisionEnd = $source.IndexOf('function accessxi.nav_freewalk_collision_reset', $collisionStart)
if ($collisionStart -lt 0 -or $collisionEnd -lt 0) { throw 'Could not isolate collision handling.' }
$collisionBody = $source.Substring($collisionStart, $collisionEnd - $collisionStart)
Assert-Match -Text $collisionBody -Pattern 'nav_door_prompt_for_collision\(player, destination, route_target, state, now\)' -Message 'Blocked-route handling must consult verified doors before generic collision guidance.'
Assert-NotMatch -Text $collisionBody -Pattern 'speak\s*\(' -Message 'The collision watcher itself must remain free of direct speech spam.'

$beaconStart = $source.IndexOf('function accessxi.poll_nav_beacon()')
$beaconEnd = $source.IndexOf('local function poll_nav_route', $beaconStart)
$routeStart = $beaconEnd
$routeEnd = $source.IndexOf('local function load_step', $routeStart)
if ($beaconStart -lt 0 -or $beaconEnd -lt 0 -or $routeEnd -lt 0) { throw 'Could not isolate route polling.' }
$beaconBody = $source.Substring($beaconStart, $beaconEnd - $beaconStart)
$routeBody = $source.Substring($routeStart, $routeEnd - $routeStart)
Assert-Match -Text $beaconBody -Pattern 'nav_door_waiting\(player, now\)' -Message 'Beacon audio must pause while the player targets a verified door.'
Assert-Match -Text $routeBody -Pattern 'nav_door_waiting\(player, now\)' -Message 'Ordinary route guidance must pause while the player targets a verified door.'
Assert-Match -Text $routeBody -Pattern 'nav_door_prompt_for_route\(player, destination, route_target, now\)' -Message 'Normal routing must announce a verified door before the fully-blocked timeout.'
if (([regex]::Matches($routeBody, 'not\s+accessxi\.nav_door_context_active\(now\)')).Count -lt 2) {
    throw 'Door interaction context must suppress both live-drift and off-route navmesh replans.'
}
Assert-Match -Text $source -Pattern 'nav_door_pause_until\s*=\s*now\s*\+\s*2500' -Message 'Door speech should pause the beacon for only 2.5 seconds.'
Assert-Match -Text $source -Pattern 'Navigation will resume with the beacon through the doorway' -Message 'Door speech should tell the player that route guidance resumes through the doorway.'

$luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath)) { throw 'Expected the Lua 5.1 test runtime.' }
$pureDoorFunctions = $source.Substring($verifiedStart, $aheadEnd - $verifiedStart)
$luaHarness = @"
string.contains = function(self, value) return string.find(self, value, 1, true) ~= nil end
accessxi = {}
nav_clean_field = function(value) return tostring(value or '') end
$pureDoorFunctions
assert(accessxi.nav_entity_is_verified_door({ type = 3, name = 'Door: Warehouse' }) == true)
assert(accessxi.nav_entity_is_verified_door({ type = 3, name = 'Harbor Light' }) == false)
assert(accessxi.nav_entity_is_verified_door({ type = 2, name = 'Door: Warehouse' }) == false)
local entities = { { type = 3, name = 'Door: Warehouse', zone = 240, x = 5, z = 1, index = 10 } }
accessxi.nav_live_entity_snapshot = function() return entities end
local player = { zone = 240, x = 0, z = 0 }
local target = { zone = 240, x = 10, z = 0 }
assert(accessxi.nav_verified_door_ahead(player, target).index == 10)
entities = { { type = 3, name = 'Door: Warehouse', zone = 240, x = 5, z = 5, index = 11 } }
assert(accessxi.nav_verified_door_ahead(player, target) == nil)
entities = { { type = 3, name = 'Door: Warehouse', zone = 240, x = -2, z = 0, index = 12 } }
assert(accessxi.nav_verified_door_ahead(player, target) == nil)
"@
& $luaPath -e $luaHarness
if ($LASTEXITCODE -ne 0) { throw "Door classification Lua harness failed with exit code $LASTEXITCODE." }

$waitFunctionStart = $source.IndexOf('function accessxi.nav_door_wait_clear(reason)')
$waitFunctionEnd = $source.IndexOf('function accessxi.nav_door_prompt_for_route', $waitFunctionStart)
if ($waitFunctionStart -lt 0 -or $waitFunctionEnd -lt 0) { throw 'Could not isolate door crossing functions for Lua behavior test.' }
$waitFunctions = $source.Substring($waitFunctionStart, $waitFunctionEnd - $waitFunctionStart)
$waitHarness = @"
string.fmt = function(self, ...) return string.format(self, ...) end
accessxi = {
    nav_door_wait_until = 16000,
    nav_door_pause_until = 3500,
    nav_door_x = 5,
    nav_door_z = 0,
    nav_door_route_unit_x = 1,
    nav_door_route_unit_z = 0,
    nav_door_wait_key = 'door',
    nav_door_wait_name = 'Door:Orastery'
}
tick = function() return 4000 end
log_line = function() end
accessxi.escape_probe_log_text = function(value) return tostring(value or '') end
$waitFunctions
assert(accessxi.nav_door_waiting({ x = 0, z = 3 }, 4000) == false)
assert(accessxi.nav_door_wait_until == 16000)
assert(accessxi.nav_door_waiting({ x = 6.5, z = 0 }, 4000) == false)
assert(accessxi.nav_door_wait_until == 0)
"@
& $luaPath -e $waitHarness
if ($LASTEXITCODE -ne 0) { throw "Door crossing Lua harness failed with exit code $LASTEXITCODE." }

Write-Host 'nav door interaction prompt tests passed'

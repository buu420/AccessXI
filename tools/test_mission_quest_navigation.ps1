param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$addonPath = Join-Path $Root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$navigationDataPath = Join-Path $Root 'ashita\addons\accessxi_reader\modules\navigation_data.lua'
$objectivesPath = Join-Path $Root 'ashita\addons\accessxi_reader\modules\mission_quest_objectives.lua'
$modulePath = Join-Path $Root 'ashita\addons\accessxi_reader\modules\mission_quest_navigation.lua'
$harnessPath = Join-Path $Root 'tools\lua_tests\test_mission_quest_navigation.lua'
$luaPath = Join-Path $Root 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) {
    $luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
}

function Assert-Match {
    param([string] $Text, [string] $Pattern, [string] $Message)
    if ($Text -notmatch $Pattern) { throw $Message }
}

foreach ($path in @($addonPath, $navigationDataPath, $objectivesPath, $modulePath, $harnessPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing mission/quest navigation test dependency: $path"
    }
}

$navigationSource = Get-Content -LiteralPath $navigationDataPath -Raw
$addonSource = Get-Content -LiteralPath $addonPath -Raw
Assert-Match $navigationSource "key\s*=\s*'mission'.*label\s*=\s*'Missions'" 'Navigation data must expose a Missions category.'
Assert-Match $navigationSource "key\s*=\s*'quest'.*label\s*=\s*'Quests'" 'Navigation data must expose a Quests category.'
Assert-Match $addonSource "load_code_module\('mission_quest_navigation'" 'The addon must load the mission/quest navigation engine.'
Assert-Match $addonSource 'nav_mission_quest_active_items' 'The navigation browser must build dynamic mission and quest rows.'
Assert-Match $addonSource 'nav_mission_quest_prepare_route' 'Route start must resolve or block the exact objective stage.'
Assert-Match $addonSource 'nav_mission_quest_item_speech' 'Mission and quest rows must use objective-aware speech.'
Assert-Match $addonSource 'arrival_radius\s*=\s*tonumber\(point\.arrival_radius\)' 'Copied objective points must preserve their precise arrival radius.'
Assert-Match $addonSource 'nav_mission_quest_arrival_suffix' 'Arrival speech must preserve the objective interaction instruction.'
Assert-Match $addonSource 'function accessxi\.current_player_identity\(' 'Mission and quest state must use a name plus native server ID identity.'
Assert-Match $addonSource 'server_id=' 'Mission and quest packet caches must persist a collision-resistant native player ID.'
Assert-Match $addonSource 'nav_cancel_mission_quest_route' 'Character switching must cancel copied mission/quest routes.'
Assert-Match $addonSource 'objective_character_identity' 'Copied objective points must preserve their character owner.'
Assert-Match $addonSource 'nav_mission_quest_route_owner_mismatch' 'Active objective routes must revalidate their character owner.'
Assert-Match $addonSource 'reentry_text\s*=\s*reentry_text\s*\.\.\s*accessxi\.nav_mission_quest_start_suffix\(item\)' 'Menu-start same-zone re-entry must preserve the objective instruction.'
Assert-Match $addonSource 'reentry_text\s*=\s*reentry_text\s*\.\.\s*accessxi\.nav_mission_quest_start_suffix\(point\)' 'Command-start same-zone re-entry must preserve the objective instruction.'

& $luaPath $harnessPath $objectivesPath $modulePath
if ($LASTEXITCODE -ne 0) {
    throw "Mission/quest navigation Lua behavior harness failed with exit code $LASTEXITCODE."
}

Write-Host 'mission and quest navigation tests passed'

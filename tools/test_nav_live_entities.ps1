$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$navigationDataPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\navigation_data.lua'
$source = Get-Content -LiteralPath $addonPath -Raw
$navigationData = Get-Content -LiteralPath $navigationDataPath -Raw

function Assert-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotMatch {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-Match -Text $navigationData -Pattern "key\s*=\s*'nm'.*?label\s*=\s*'NM Spawns'" -Message 'Static NM spawn category must remain.'
Assert-Match -Text $navigationData -Pattern "key\s*=\s*'live-nm'.*?label\s*=\s*'Live NM'" -Message 'Expected separate Live NM category.'

foreach ($fragment in @(
    'function accessxi.nav_live_entity_key(pos)',
    'function accessxi.nav_live_entity_valid(pos)',
    'function accessxi.nav_live_entity_snapshot(max_count, max_distance)',
    'function accessxi.nav_live_nm_names_for_zone(zone)',
    'function accessxi.nav_entity_is_live_nm_candidate(pos)',
    'function accessxi.nav_zone_suppresses_named_npc_obstacles(zone)',
    'function accessxi.nav_entity_is_dynamic_obstacle_candidate(pos)',
    'function accessxi.nav_live_entities_for_category(category_key, max_distance)',
    'function accessxi.nav_recent_live_obstacle(now)'
)) {
    Assert-Match -Text $source -Pattern ([regex]::Escape($fragment)) -Message "Missing live entity helper: $fragment"
}

$segmentStart = $source.IndexOf('function accessxi.nav_segment_obstacle')
$segmentEnd = $source.IndexOf('function accessxi.nav_obstacle_avoidance_target', $segmentStart)
if ($segmentStart -lt 0 -or $segmentEnd -lt 0) {
    throw 'Could not locate nav_segment_obstacle block.'
}
$segmentBody = $source.Substring($segmentStart, $segmentEnd - $segmentStart)
Assert-Match -Text $segmentBody -Pattern 'nav_live_entity_snapshot' -Message 'Dynamic obstacle detection must use live entity snapshot.'
Assert-Match -Text $segmentBody -Pattern 'nav_live_entity_valid' -Message 'Dynamic obstacle detection must validate live entities.'
Assert-Match -Text $segmentBody -Pattern 'nav_entity_is_dynamic_obstacle_candidate' -Message 'Dynamic obstacle detection should only consider live players and enemies.'
Assert-NotMatch -Text $segmentBody -Pattern 'entity_type\s*~=\s*0\s*and\s*not\s*accessxi\.nav_entity_is_obvious_object' -Message 'Dynamic obstacle detection must not treat ordinary NPCs as obstacles.'
Assert-NotMatch -Text $segmentBody -Pattern 'GetEntityMapSize\(\)' -Message 'Dynamic obstacle detection should not do broad raw entity scans directly.'

$dynamicStart = $source.IndexOf('function accessxi.nav_entity_is_dynamic_obstacle_candidate')
$dynamicEnd = $source.IndexOf('function accessxi.nav_live_entity_key', $dynamicStart)
if ($dynamicStart -lt 0 -or $dynamicEnd -lt 0) {
    throw 'Could not locate nav_entity_is_dynamic_obstacle_candidate block.'
}
$dynamicBody = $source.Substring($dynamicStart, $dynamicEnd - $dynamicStart)
Assert-Match -Text $dynamicBody -Pattern "kind == 'player'" -Message 'Other players should remain dynamic obstacle candidates.'
Assert-Match -Text $dynamicBody -Pattern "kind == 'enemy'" -Message 'Enemies should remain dynamic obstacle candidates.'
Assert-Match -Text $dynamicBody -Pattern "kind == 'live-nm'" -Message 'Live NMs should remain dynamic obstacle candidates.'
Assert-Match -Text $dynamicBody -Pattern 'nav_zone_suppresses_named_npc_obstacles' -Message 'Town zones should suppress named NPCs that were misclassified as enemy obstacles.'
Assert-Match -Text $dynamicBody -Pattern 'nav_entity_name_looks_like_enemy' -Message 'Town obstacle suppression should still allow names that genuinely look hostile.'
Assert-NotMatch -Text $dynamicBody -Pattern "kind == 'npc'|nav_entity_is_npc\(pos\).*?return true" -Message 'Static NPCs should not be dynamic obstacle candidates.'

$avoidStart = $source.IndexOf('function accessxi.nav_apply_dynamic_obstacle')
$avoidEnd = $source.IndexOf('function accessxi.nav_recent_live_obstacle', $avoidStart)
if ($avoidStart -lt 0 -or $avoidEnd -lt 0) {
    throw 'Could not locate nav_apply_dynamic_obstacle block.'
}
$avoidBody = $source.Substring($avoidStart, $avoidEnd - $avoidStart)
Assert-Match -Text $avoidBody -Pattern 'nav obstacle warn' -Message 'Dynamic obstacle avoidance should keep diagnostic logs.'
Assert-NotMatch -Text $avoidBody -Pattern 'speak\s*\(' -Message 'Dynamic obstacle avoidance should not speak obstacle warnings.'
Assert-NotMatch -Text $avoidBody -Pattern 'Obstacle ahead' -Message 'Dynamic obstacle avoidance should not say obstacle ahead.'

$progressStart = $source.IndexOf('function accessxi.nav_progress_watch')
$progressEnd = $source.IndexOf('function accessxi.poll_nav_beacon', $progressStart)
if ($progressStart -lt 0 -or $progressEnd -lt 0) {
    throw 'Could not locate nav_progress_watch block.'
}
$progressBody = $source.Substring($progressStart, $progressEnd - $progressStart)
Assert-NotMatch -Text $progressBody -Pattern 'Possible obstacle' -Message 'No-progress watchdog must not claim possible obstacles without live proof.'
Assert-NotMatch -Text $progressBody -Pattern 'Obstacle still nearby|nav_recent_live_obstacle' -Message 'No-progress watchdog should not speak obstacle-specific status.'
Assert-Match -Text $progressBody -Pattern 'No forward progress' -Message 'No-progress watchdog should use honest no-progress wording.'

$routeSpeechStart = $source.IndexOf('function accessxi.nav_route_guidance_speech_enabled')
if ($routeSpeechStart -lt 0) {
    throw 'Could not locate route guidance speech gate before poll_nav_beacon.'
}
$routeSpeechEnd = $source.IndexOf('function accessxi.poll_nav_beacon', $routeSpeechStart)
if ($routeSpeechEnd -lt 0) {
    throw 'Could not locate poll_nav_beacon after route guidance speech gate.'
}
$routeSpeechBody = $source.Substring($routeSpeechStart, $routeSpeechEnd - $routeSpeechStart)
Assert-Match -Text $routeSpeechBody -Pattern 'not\s+accessxi\.nav_beacon_enabled' -Message 'Routine route guidance speech should be quiet while beacon audio is active.'
Assert-Match -Text $routeSpeechBody -Pattern 'function accessxi\.nav_speak_route_guidance\(text\)' -Message 'Expected shared route guidance speech helper.'

$pollRouteStart = $source.IndexOf('local function poll_nav_route')
$pollRouteEnd = $source.IndexOf('local function load_step', $pollRouteStart)
if ($pollRouteStart -lt 0 -or $pollRouteEnd -lt 0) {
    throw 'Could not locate poll_nav_route block.'
}
$pollRouteBody = $source.Substring($pollRouteStart, $pollRouteEnd - $pollRouteStart)
Assert-Match -Text $pollRouteBody -Pattern "local text = phrase[\s\S]*?accessxi\.nav_speak_route_guidance\(text\)[\s\S]*?nav waypoint" -Message 'Waypoint direction speech should use the beacon-aware route guidance gate.'
Assert-Match -Text $pollRouteBody -Pattern "local text = \('Route adjusted\. %s'\):fmt\(phrase\)[\s\S]*?accessxi\.nav_speak_route_guidance\(text\)[\s\S]*?nav route adjusted" -Message 'Route-adjusted direction speech should use the beacon-aware route guidance gate.'
Assert-Match -Text $pollRouteBody -Pattern "local text = prefix \.\. phrase[\s\S]*?accessxi\.nav_speak_route_guidance\(text\)[\s\S]*?nav route" -Message 'Routine direction speech should use the beacon-aware route guidance gate.'

$liveEnemiesStart = $source.IndexOf('function accessxi.nav_live_enemies')
$liveEnemiesEnd = $source.IndexOf('function accessxi.nav_live_category', $liveEnemiesStart)
if ($liveEnemiesStart -lt 0 -or $liveEnemiesEnd -lt 0) {
    throw 'Could not locate nav_live_enemies block.'
}
$liveEnemiesBody = $source.Substring($liveEnemiesStart, $liveEnemiesEnd - $liveEnemiesStart)
Assert-Match -Text $liveEnemiesBody -Pattern 'nav_live_entities_for_category' -Message 'Enemy warning should share live category filtering.'

$liveCategoryStart = $source.IndexOf('function accessxi.nav_live_category')
$liveCategoryEnd = $source.IndexOf('function accessxi.nav_log_entity_candidates', $liveCategoryStart)
if ($liveCategoryStart -lt 0 -or $liveCategoryEnd -lt 0) {
    throw 'Could not locate nav_live_category block.'
}
$liveCategoryBody = $source.Substring($liveCategoryStart, $liveCategoryEnd - $liveCategoryStart)
Assert-Match -Text $liveCategoryBody -Pattern "category_key == 'live-nm'" -Message 'Live NM category should refresh dynamically.'

$collectStart = $source.IndexOf('local function nav_collect_menu_items')
$collectEnd = $source.IndexOf('local function nav_refresh_search_results', $collectStart)
if ($collectStart -lt 0 -or $collectEnd -lt 0) {
    throw 'Could not locate nav_collect_menu_items block.'
}
$collectBody = $source.Substring($collectStart, $collectEnd - $collectStart)
Assert-Match -Text $collectBody -Pattern 'nav_live_entities_for_category' -Message 'Navigation menu should use shared live entity category filtering.'
Assert-Match -Text $collectBody -Pattern "source = \('live-entity:%d:%d'" -Message 'Live menu entries should be visibly live entity sourced.'

Write-Host 'nav live entity checks ok'

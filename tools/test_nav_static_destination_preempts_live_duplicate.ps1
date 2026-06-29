$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

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

function Assert-NotMatch {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Text -match $Pattern) {
        throw $Message
    }
}

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_stable_destination_duplicate_key\(point\)' `
    -Message 'Expected a normalized duplicate key for stable static destinations.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_live_entity_duplicate_key\(entity_point\)' `
    -Message 'Expected live entity duplicate suppression to compute a key without requiring static confidence fields.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_live_entity_shadowed_by_static_destination\(entity_point,\s*static_destination_keys\)' `
    -Message 'Expected live entity duplicate suppression against observed/proven static destinations.'

$obviousStart = $source.IndexOf('function accessxi.nav_entity_is_obvious_object')
$obviousEnd = $source.IndexOf('function accessxi.nav_entity_is_known_non_hostile', $obviousStart)
if ($obviousStart -lt 0 -or $obviousEnd -lt 0) {
    throw 'Could not locate nav_entity_is_obvious_object block.'
}
$obviousBody = $source.Substring($obviousStart, $obviousEnd - $obviousStart)

Assert-Match `
    -Text $obviousBody `
    -Pattern "name:contains\('telepoint'\)" `
    -Message 'Telepoints should be treated as stable interactable objects, not live enemies.'

Assert-Match `
    -Text $obviousBody `
    -Pattern "name:contains\('ergon locus'\)" `
    -Message 'Ergon Locus targets should not be treated as live enemy obstacles.'

$shadowStart = $source.IndexOf('function accessxi.nav_live_entity_shadowed_by_static_destination')
$shadowEnd = $source.IndexOf('function accessxi.nav_live_entity_snapshot', $shadowStart)
if ($shadowStart -lt 0 -or $shadowEnd -lt 0) {
    throw 'Could not locate live duplicate suppression helper block.'
}
$shadowBody = $source.Substring($shadowStart, $shadowEnd - $shadowStart)

Assert-Match `
    -Text $shadowBody `
    -Pattern 'nav_live_entity_duplicate_key\(entity_point\)' `
    -Message 'Live duplicate suppression should compare normalized zone/name keys that do not depend on entity confidence.'

Assert-NotMatch `
    -Text $shadowBody `
    -Pattern 'nav_stable_destination_duplicate_key\(entity_point\)' `
    -Message 'Live entity duplicate suppression must not require observed/proven confidence on live entities.'

Assert-Match `
    -Text $shadowBody `
    -Pattern 'static_destination_keys\[key\]\s*==\s*true' `
    -Message 'Live duplicate suppression should use the static destination key set.'

Assert-NotMatch `
    -Text $shadowBody `
    -Pattern "kind == 'enemy'|kind == 'live-nm'|kind == 'player'" `
    -Message 'Enemy, live-NM, and player live entries must not be suppressed by static destination keys.'

$collectStart = $source.IndexOf('local function nav_collect_menu_items')
$collectEnd = $source.IndexOf('local function nav_refresh_search_results', $collectStart)
if ($collectStart -lt 0 -or $collectEnd -lt 0) {
    throw 'Could not locate nav_collect_menu_items block.'
}
$collectBody = $source.Substring($collectStart, $collectEnd - $collectStart)

Assert-Match `
    -Text $collectBody `
    -Pattern 'local static_destination_keys\s*=\s*\{\}' `
    -Message 'Navigation search should maintain a set of stable static destination names.'

Assert-Match `
    -Text $collectBody `
    -Pattern 'nav_stable_destination_duplicate_key\(point\)' `
    -Message 'Static destination rows should seed duplicate suppression keys.'

Assert-Match `
    -Text $collectBody `
    -Pattern 'not\s+accessxi\.nav_live_entity_shadowed_by_static_destination\(entity_point,\s*static_destination_keys\)' `
    -Message 'Live duplicates should not appear in nav search when an observed/proven static destination already exists.'

Write-Host 'nav static destination duplicate suppression checks ok'

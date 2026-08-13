param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$addonPath = Join-Path $Root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$harnessPath = Join-Path $Root 'tools\lua_tests\test_nav_zoneline_path.lua'
$dedupHarnessPath = Join-Path $Root 'tools\lua_tests\test_nav_zone_search_dedup.lua'
$luaPath = Join-Path $Root 'tools\lua51\lua5.1.exe'
if (-not (Test-Path -LiteralPath $luaPath -PathType Leaf)) {
    $luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'
}
foreach ($path in @($addonPath, $harnessPath, $dedupHarnessPath, $luaPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing zone-search test dependency: $path"
    }
}
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
    -Pattern 'nav_zone_search_target\s*=\s*nil' `
    -Message 'Expected persistent zone search final target state.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_zoneline_path\(from_zone,\s*to_zone,\s*final_edge_id\)' `
    -Message 'Expected zoneline graph path helper with optional canonical final ingress.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_zone_search_npc_results\(query,\s*player\)' `
    -Message 'Expected /axi zonesearch to collect selectable global NPC results.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_find_zone_search_npc\(query,\s*player\)' `
    -Message 'Expected global NPC lookup helper for /axi zonesearch.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_zone_search_start\(query\)' `
    -Message 'Expected /axi zonesearch command starter.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.poll_nav_zone_search\(\)' `
    -Message 'Expected polling helper to resume zone search after zoning.'

$commandStart = $source.IndexOf('function accessxi.handle_axi_command')
$commandEnd = $source.IndexOf('function accessxi.dispatch_axi_command_text', $commandStart)
if ($commandStart -lt 0 -or $commandEnd -lt 0) {
    throw 'Could not locate shared AXI command handler.'
}
$commandBody = $source.Substring($commandStart, $commandEnd - $commandStart)

Assert-Match `
    -Text $commandBody `
    -Pattern "args\[2\]:any\('zonesearch', 'zsearch'\)" `
    -Message 'Expected /axi zonesearch command alias.'

Assert-Match `
    -Text $commandBody `
    -Pattern 'accessxi\.nav_zone_search_start\(command_tail\(args,\s*3\)\)' `
    -Message 'Expected /axi zonesearch to use its own command tail, not /axi nav search.'

$navCommandStart = $commandBody.IndexOf("args[2]:any('nav', 'navigation', 'dest')")
$beaconStart = $commandBody.IndexOf("args[2]:any('beacon', 'navbeacon')")
if ($navCommandStart -lt 0 -or $beaconStart -lt 0) {
    throw 'Could not locate normal nav command block.'
}
$navCommandBody = $commandBody.Substring($navCommandStart, $beaconStart - $navCommandStart)

Assert-NotMatch `
    -Text $navCommandBody `
    -Pattern 'zonesearch|zsearch|nav_find_zone_search_npc|nav_zone_search_start' `
    -Message '/axi nav search should remain separate from /axi zonesearch.'

$zoneOpenIndex = $source.IndexOf('function accessxi.nav_zone_search_start(query)')
$zoneOpenEndIndex = $source.IndexOf('function accessxi.poll_nav_zone_search', $zoneOpenIndex)
if ($zoneOpenIndex -lt 0 -or $zoneOpenEndIndex -lt 0) {
    throw 'Could not locate zone search open block.'
}
$zoneOpenBody = $source.Substring($zoneOpenIndex, $zoneOpenEndIndex - $zoneOpenIndex)

Assert-Match `
    -Text $zoneOpenBody `
    -Pattern 'nav_menu_search_results:append\(item\)' `
    -Message '/axi zonesearch should populate selectable search results.'

Assert-Match `
    -Text $zoneOpenBody `
    -Pattern 'accessxi\.nav_menu_items:append\(item\)' `
    -Message '/axi zonesearch should populate the active nav browser item list.'

Assert-Match `
    -Text $zoneOpenBody `
    -Pattern 'U selects the previous category\..*?O selects the next category\..*?J selects the previous destination\..*?K repeats\..*?L selects the next destination\..*?I starts the selected route or stops active navigation\.' `
    -Message '/axi zonesearch should announce browser controls instead of immediately starting a route.'

Assert-NotMatch `
    -Text $zoneOpenBody `
    -Pattern 'nav_zone_search_start_next_leg\(' `
    -Message '/axi zonesearch should not immediately start routing before the user selects a result.'

$zoneStartIndex = $source.IndexOf('function accessxi.nav_zone_search_start_next_leg')
$zoneEndIndex = $source.IndexOf('nav_route_stop = function', $zoneStartIndex)
if ($zoneStartIndex -lt 0 -or $zoneEndIndex -lt 0) {
    throw 'Could not locate zone search start block.'
}
$zoneSearchBody = $source.Substring($zoneStartIndex, $zoneEndIndex - $zoneStartIndex)

$menuStartIndex = $source.IndexOf('local function nav_menu_start_route')
$menuStartEndIndex = $source.IndexOf('local function nav_menu_handle_action', $menuStartIndex)
if ($menuStartIndex -lt 0 -or $menuStartEndIndex -lt 0) {
    throw 'Could not locate nav menu route start block.'
}
$menuStartBody = $source.Substring($menuStartIndex, $menuStartEndIndex - $menuStartIndex)

Assert-Match `
    -Text $menuStartBody `
    -Pattern 'item\.zone_search_result == true' `
    -Message 'Starting a selected zone-search result should use cross-zone routing.'

Assert-Match `
    -Text $menuStartBody `
    -Pattern 'accessxi\.nav_zone_search_start_next_leg\(' `
    -Message 'Selected zone-search results should start the next zoneline leg only after selection.'

Assert-Match `
    -Text $zoneSearchBody `
    -Pattern 'nav_zoneline_path\(player\.zone,\s*target\.zone,\s*canonical_edge_id\)' `
    -Message 'Zone search should preserve a reviewed canonical final ingress when present.'

Assert-Match `
    -Text $zoneSearchBody `
    -Pattern "source = \('zonesearch:%d:%d:%d'\)" `
    -Message 'Zone search leg should be marked as a generated zonesearch zoneline target.'

Assert-Match `
    -Text $zoneSearchBody `
    -Pattern 'accessxi\.nav_start_route_to_point\(leg,' `
    -Message 'Zone search should start a normal in-zone route to the next zone line.'

$pollRouteStart = $source.IndexOf('local function poll_nav_route')
$pollRouteEnd = $source.IndexOf('local function load_step', $pollRouteStart)
if ($pollRouteStart -lt 0 -or $pollRouteEnd -lt 0) {
    throw 'Could not locate nav route polling block.'
}
$pollRouteBody = $source.Substring($pollRouteStart, $pollRouteEnd - $pollRouteStart)

Assert-Match `
    -Text $pollRouteBody `
    -Pattern 'nav_zone_search_waiting_zone' `
    -Message 'Arriving at a zone search leg should wait for the actual zone transition.'

Assert-Match `
    -Text $pollRouteBody `
    -Pattern 'Zone into %s to continue to %s' `
    -Message 'Zone search should speak an explicit zone-through prompt at the zone line.'

$presentStart = $source.IndexOf("ashita.events.register('d3d_present'")
if ($presentStart -lt 0) {
    throw 'Could not locate d3d_present callback.'
}
$presentBody = $source.Substring($presentStart)

Assert-Match `
    -Text $presentBody `
    -Pattern 'accessxi\.poll_nav_zone_search\(\)' `
    -Message 'Present loop should poll zone search resume before normal route polling.'

Assert-Match `
    -Text $source `
    -Pattern "local function nav_route_start\(query\)[\s\S]*?accessxi\.nav_clear_zone_search\(\)" `
    -Message 'Starting a normal route should cancel pending zone search.'

Assert-Match `
    -Text $source `
    -Pattern "nav_route_stop = function\s*\(\)[\s\S]*?accessxi\.nav_clear_zone_search\(\)" `
    -Message 'Stopping a route should cancel pending zone search.'

& $luaPath $harnessPath $addonPath
if ($LASTEXITCODE -ne 0) {
    throw "Canonical zoneline path Lua behavior harness failed with exit code $LASTEXITCODE."
}

& $luaPath $dedupHarnessPath $addonPath
if ($LASTEXITCODE -ne 0) {
    throw "Zone-search presentation dedup behavior failed with exit code $LASTEXITCODE."
}

Write-Host 'nav zone search command checks ok'

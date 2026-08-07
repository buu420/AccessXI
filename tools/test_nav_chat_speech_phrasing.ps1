$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\speech_format.lua'
$luaPath = 'C:\Users\buu42\AccessXI\tools\lua51\lua5.1.exe'

if (-not (Test-Path -LiteralPath $modulePath)) {
    throw "Speech formatter module not found: $modulePath"
}

$script = @"
local module_path = [[$modulePath]]

function string.trim(self)
    return tostring(self or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function string.fmt(self, ...)
    return string.format(self, ...)
end

accessxi = {}
dofile(module_path)

local nav = accessxi.navigation_row_speech(
    'East Sarutabaruta zone line', 2, 270, 'area', 'untested',
    'Turn left. Go straight 38 yalms. Height down 5.', '')
local nav_expected = 'East Sarutabaruta zone line. 2 of 270. area. Confidence untested. Turn left. Go straight 38 yalms. Height down 5.'
if nav ~= nav_expected then
    error(('navigation row expected %q, got %q'):format(nav_expected, tostring(nav)))
end

local category = accessxi.navigation_category_speech('Areas')
local category_expected = 'Areas.'
if category ~= category_expected then
    error(('category change expected %q, got %q'):format(category_expected, tostring(category)))
end

local zone = accessxi.navigation_zone_search_row_speech(
    'Kupipi', 4, 12, 'Heavens Tower', 'Route 2 zones.', 'recorded')
local zone_expected = 'Kupipi. 4 of 12. NPC. Heavens Tower. Route 2 zones. Confidence recorded.'
if zone ~= zone_expected then
    error(('zone-search row expected %q, got %q'):format(zone_expected, tostring(zone)))
end

local message = 'NPC. Fhelm Jobeizat says hello.'
if accessxi.chat_message_speech(message) ~= message then
    error('chat row added category or position text')
end
if accessxi.chat_message_speech('') ~= 'Blank line.' then
    error('blank chat row did not retain useful feedback')
end
"@

$tmp = Join-Path $env:TEMP ('accessxi-nav-chat-speech-{0}.lua' -f ([guid]::NewGuid().ToString('N')))
try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
    & $luaPath $tmp
    if ($LASTEXITCODE -ne 0) {
        throw "Lua test failed with exit code $LASTEXITCODE"
    }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

$source = Get-Content -LiteralPath $addonPath -Raw
if ($source -notmatch "accessxi\.load_code_module\('speech_format'\)") {
    throw 'Main addon does not load the speech formatter module.'
}
if ($source -notmatch 'accessxi\.navigation_row_speech\(') {
    throw 'Navigation browser is not using the category-free row formatter.'
}
if ($source -notmatch 'accessxi\.navigation_zone_search_row_speech\(') {
    throw 'Zone-search results are not using name-first speech.'
}
if ($source -notmatch 'nav_menu_category_move[\s\S]*?accessxi\.navigation_category_speech\(') {
    throw 'U/O category changes do not announce the new category.'
}
$categoryMoveStart = $source.IndexOf('local function nav_menu_category_move(delta)')
$categoryMoveEnd = $source.IndexOf('local function nav_menu_start_route()', $categoryMoveStart)
if ($categoryMoveStart -lt 0 -or $categoryMoveEnd -le $categoryMoveStart) {
    throw 'Could not isolate nav category movement.'
}
$categoryMoveBody = $source.Substring($categoryMoveStart, $categoryMoveEnd - $categoryMoveStart)
if ($categoryMoveBody -match 'nav_menu_item_speech\(') {
    throw 'Category keys must announce only the category, not a destination row.'
}
if ($source -notmatch 'accessxi\.chat_reader_entry_speech\(category, entries, next_pos, prefix, true\)') {
    throw 'Chat reader movement is not using message-only speech.'
}
if ($source -notmatch 'return accessxi\.chat_message_speech\(line\);') {
    throw 'Native chat log rows are not using message-only speech.'
}

Write-Host 'navigation and chat speech phrasing regression ok'

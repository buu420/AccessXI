$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

$normalizeStart = $source.IndexOf('function accessxi.home_point_query_normalize_phrase')
if ($normalizeStart -lt 0) {
    throw 'Missing Home Point query label normalizer.'
}
$normalizeEnd = $source.IndexOf("`nfunction ", $normalizeStart + 1)
if ($normalizeEnd -lt 0) {
    throw 'Could not locate the end of the Home Point query label normalizer.'
}
$normalizeBody = $source.Substring($normalizeStart, $normalizeEnd - $normalizeStart)

$watersEntry = "T{ 'Windurst Waters', 'Windurst Waters' }"
$parentEntry = "T{ 'Windurst', 'Windurst' }"
$watersIndex = $normalizeBody.IndexOf($watersEntry)
$parentIndex = $normalizeBody.IndexOf($parentEntry)
if ($watersIndex -lt 0) {
    throw 'Windurst Waters is missing from the native Home Point location-prefix normalization list.'
}
if ($parentIndex -lt 0) {
    throw 'Missing broad Windurst Home Point location normalization entry.'
}
if ($watersIndex -gt $parentIndex) {
    throw 'Windurst Waters must be matched before the broader Windurst prefix.'
}

$menuStart = $source.IndexOf('function accessxi.home_point_query_menu_speech')
$menuEnd = $source.IndexOf("`nfunction ", $menuStart + 1)
$menuBody = $source.Substring($menuStart, $menuEnd - $menuStart)
if ($menuBody -notmatch "native_query_label_for_selection\(child,\s*selected,\s*count,\s*'plain'\)") {
    throw 'Home Point speech must continue to obtain the selected label from the live native query list.'
}
if ($menuBody -notmatch 'home_point_query_normalize_phrase\(label\s+or\s+''''\)') {
    throw 'Home Point speech must normalize the live label through the shared location normalizer.'
}
if ($menuBody -match "selected\s*==\s*2.*?Windurst Waters|count\s*==\s*5.*?Windurst Waters") {
    throw 'Windurst Waters must not be tied to a row number or fixed menu size.'
}

Write-Host 'homepoint Windurst Waters native-label static checks ok'

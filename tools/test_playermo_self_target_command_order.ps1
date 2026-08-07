$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $addonPath -Raw

$functionStart = $source.IndexOf('function accessxi.playermo_menu_speech')
if ($functionStart -lt 0) {
    throw 'Missing playermo command-menu reader.'
}
$functionEnd = $source.IndexOf("`nfunction ", $functionStart + 1)
if ($functionEnd -lt 0) {
    throw 'Could not locate the end of the playermo command-menu reader.'
}
$body = $source.Substring($functionStart, $functionEnd - $functionStart)

$nativeQueryIndex = $body.IndexOf('native_query_label_for_selection(child, selected, count')
$selfDatIndex = $body.IndexOf('playermo_command_menu_dat_entry(selected, command_ptr)')
if ($nativeQueryIndex -lt 0 -or $selfDatIndex -lt 0) {
    throw 'Missing generic native query or verified self-command DAT resolver.'
}

$nativeQueryPrefixStart = [Math]::Max(0, $nativeQueryIndex - 420)
$nativeQueryPrefix = $body.Substring($nativeQueryPrefixStart, $nativeQueryIndex - $nativeQueryPrefixStart)
if ($nativeQueryPrefix -notmatch "not\s+tostring\(target_context\.kind\s+or\s+''\):eq\('self',\s*true\)") {
    throw 'Self-target command rows still reach the unrelated generic native text-pointer resolver.'
}

if ($body -notmatch "(?s)if\s+\(not\s+tostring\(target_context\.kind\s+or\s+''\):eq\('self',\s*true\).*?native_query_label_for_selection\(child,\s*selected,\s*count,\s*'plain'\)") {
    throw 'Generic native text-pointer lookup must be explicitly limited to non-self targets.'
}

if ($body -notmatch "(?s)if\s+\(not\s+tostring\(target_context\.kind.*?return\s+nil;.*?playermo_command_menu_dat_entry\(selected,\s*command_ptr\).*?count\s*==\s*12") {
    throw 'Verified self-command DAT rows must remain reachable after dynamic-target handling.'
}

Write-Host 'playermo self-target command ordering static checks ok'

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

$listStart = $source.IndexOf('function accessxi.blue_magic_current_set_spell_list')
if ($listStart -lt 0) {
    throw 'Missing current-character Blue Magic set spell-list resolver.'
}
$listEnd = $source.IndexOf("`nfunction ", $listStart + 1)
if ($listEnd -lt 0) {
    throw 'Could not locate end of current-character Blue Magic set spell-list resolver.'
}
$listBody = $source.Substring($listStart, $listEnd - $listStart)

Assert-Match `
    -Text $listBody `
    -Pattern '(?s)for\s+slot\s*=\s*1,\s*20\s+do.*?blue_magic_set_current_spell_for_slot\(slot\)' `
    -Message 'Castable Blue Magic must come from the current character native 20 set slots.'

Assert-Match `
    -Text $listBody `
    -Pattern '(?s)magic_mix_read_order\(\).*?for\s+_,\s*id\s+in\s+ipairs\(mix_order\.ids\).*?if\s+\(set_ids\[id\]\s*==\s*true\)' `
    -Message 'Current set spell ids must be filtered through the active profile mix.dat order without sorting.'

Assert-Match `
    -Text $listBody `
    -Pattern 'spells:len\(\)\s*~=\s*set_count' `
    -Message 'An incomplete set-to-mix match must stay unavailable instead of producing partial false rows.'

$dynamicStart = $source.IndexOf('function accessxi.magic_dynamic_spell_from_entry')
if ($dynamicStart -lt 0) {
    throw 'Missing magic_dynamic_spell_from_entry.'
}
$dynamicEnd = $source.IndexOf("`nfunction accessxi.magic_probe_offsets", $dynamicStart)
if ($dynamicEnd -lt 0) {
    throw 'Could not locate end of magic_dynamic_spell_from_entry.'
}
$dynamicBody = $source.Substring($dynamicStart, $dynamicEnd - $dynamicStart)

$helpIndex = $dynamicBody.IndexOf('magic_spell_from_window_help')
$castIndex = $dynamicBody.IndexOf('blue_magic_current_cast_spell_for_selected')
$learnedMixIndex = $dynamicBody.IndexOf('magic_mix_category_spell_for_selected')
if ($helpIndex -lt 0 -or $castIndex -lt 0 -or $learnedMixIndex -lt 0) {
    throw 'Blue Magic castable resolver, exact native help resolver, or learned mix fallback is missing.'
}
if ($helpIndex -gt $castIndex) {
    throw 'Exact native help must remain ahead of the complete Blue Magic cast-list resolver.'
}
if ($castIndex -gt $learnedMixIndex) {
    throw 'Complete Blue Magic cast-list resolver must run before the all-learned mix.dat category resolver.'
}

Assert-Match `
    -Text $dynamicBody `
    -Pattern "(?s)if\s+\(category_label:eq\('Blue Magic', true\)\)\s+then.*?blue_magic_current_cast_spell_for_selected\(selected\).*?'native-blue-set-mix'.*?'native-blue-unbridled-mix'.*?'native-blue-cast-range'.*?return\s+nil" `
    -Message 'Only verified current-set and learned Unbridled Blue Magic rows may resolve; out-of-range rows must stay silent.'

if ($source -match '(?i)zaltar|longrodvonhugen|USER\\fb6a14') {
    throw 'Blue Magic castable resolver must not contain character names or a fixed USER profile folder.'
}

Write-Host 'blue magic complete castable order static checks ok'

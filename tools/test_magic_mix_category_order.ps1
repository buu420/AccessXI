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

$helperStart = $source.IndexOf('function accessxi.magic_mix_category_spell_list')
if ($helperStart -lt 0) {
    throw 'Missing category-filtered mix.dat spell resolver for player-custom magic order.'
}
$helperEnd = $source.IndexOf("`nfunction accessxi.blue_magic_mix_spell_list", $helperStart)
if ($helperEnd -lt 0) {
    throw 'Could not locate end of magic_mix_category_spell_list helper.'
}
$helperBody = $source.Substring($helperStart, $helperEnd - $helperStart)

Assert-Match `
    -Text $helperBody `
    -Pattern 'magic_mix_read_order\(\)' `
    -Message 'Category spell resolver should use the live FFXI USER profile mix.dat spell-order file.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'magic_category_type\(label\)' `
    -Message 'Category spell resolver should filter mix.dat order through the active native Magic category.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'player:HasSpell\(id\)' `
    -Message 'Category spell resolver should only speak spells the player actually knows.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'tonumber\(info\.type\)\s*==\s*wanted_type' `
    -Message 'Category spell resolver should match the resource spell type to the active category.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'seen\[id\]' `
    -Message 'Category spell resolver should de-duplicate mix.dat spell ids before indexing rows.'

Assert-NotMatch `
    -Text $helperBody `
    -Pattern 'spells:sort|for id = 0,\s*2048' `
    -Message 'Category spell resolver must preserve mix.dat order, not rebuild a spell-id sorted list.'

$dynamicStart = $source.IndexOf('function accessxi.magic_dynamic_spell_from_entry')
if ($dynamicStart -lt 0) {
    throw 'Missing magic_dynamic_spell_from_entry.'
}
$dynamicEnd = $source.IndexOf("`nfunction accessxi.magic_probe_offsets", $dynamicStart)
if ($dynamicEnd -lt 0) {
    throw 'Could not locate end of magic_dynamic_spell_from_entry.'
}
$dynamicBody = $source.Substring($dynamicStart, $dynamicEnd - $dynamicStart)

$mixIndex = $dynamicBody.IndexOf('magic_mix_category_spell_for_selected')
$knownIndex = $dynamicBody.IndexOf('magic_category_spell_for_selected')
if ($mixIndex -lt 0 -or $knownIndex -lt 0 -or $mixIndex -gt $knownIndex) {
    throw 'Dynamic Magic category rows should prefer category-filtered mix.dat order before the old spell-id fallback.'
}

Assert-Match `
    -Text $dynamicBody `
    -Pattern "'mix-magic-category'" `
    -Message 'Dynamic Magic speech should log when a row came from category-filtered mix.dat order.'

Assert-Match `
    -Text $dynamicBody `
    -Pattern "(?s)category_label:eq\('Blue Magic', true\).*?'mix-magic-category-range'" `
    -Message 'Blue Magic should stay silent if mix.dat category order cannot verify the selected row.'

Write-Host 'magic mix.dat category order static checks ok'

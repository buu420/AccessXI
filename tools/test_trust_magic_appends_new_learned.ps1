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
    throw 'Missing magic_mix_category_spell_list.'
}
$helperEnd = $source.IndexOf("`nfunction accessxi.blue_magic_mix_spell_list", $helperStart)
if ($helperEnd -lt 0) {
    throw 'Could not locate end of magic_mix_category_spell_list.'
}
$helperBody = $source.Substring($helperStart, $helperEnd - $helperStart)

Assert-Match `
    -Text $helperBody `
    -Pattern 'magic_append_known_spells_missing_from_mix\(spells,\s*seen,\s*player,\s*label,\s*wanted_type\s*==\s*8\)' `
    -Message 'Trust Magic should have a dynamic append path for newly learned Trusts missing from mix.dat.'

$appendStart = $source.IndexOf('function accessxi.magic_append_known_spells_missing_from_mix')
if ($appendStart -lt 0) {
    throw 'Missing magic_append_known_spells_missing_from_mix.'
}
$appendEnd = $source.IndexOf("`nfunction accessxi.magic_mix_category_spell_list", $appendStart)
if ($appendEnd -lt 0) {
    throw 'Could not locate end of magic_append_known_spells_missing_from_mix.'
}
$appendBody = $source.Substring($appendStart, $appendEnd - $appendStart)

Assert-Match `
    -Text $appendBody `
    -Pattern 'magic_known_spell_list_for_category\(label\)' `
    -Message 'Trust Magic append path should use live known Trust spells, not a static list.'

Assert-Match `
    -Text $appendBody `
    -Pattern '(?s)magic_known_spell_list_for_category\(label\).*?seen\[id\]\s*~=\s*true.*?spells:append\(info\)' `
    -Message 'Newly learned Trusts absent from mix.dat should be appended after verified mix.dat rows.'

Assert-Match `
    -Text $appendBody `
    -Pattern 'player:HasSpell\(id\)' `
    -Message 'Trust Magic append path should still verify live player spell knowledge.'

Assert-NotMatch `
    -Text $appendBody `
    -Pattern 'spells:sort|for id = 0,\s*2048|for id = 1,\s*2048' `
    -Message 'Trust Magic append path must not rebuild the whole row order as a sorted/static list.'

$dynamicStart = $source.IndexOf('function accessxi.magic_dynamic_spell_from_entry')
if ($dynamicStart -lt 0) {
    throw 'Missing magic_dynamic_spell_from_entry.'
}
$dynamicEnd = $source.IndexOf("`nfunction accessxi.magic_probe_offsets", $dynamicStart)
if ($dynamicEnd -lt 0) {
    throw 'Could not locate end of magic_dynamic_spell_from_entry.'
}
$dynamicBody = $source.Substring($dynamicStart, $dynamicEnd - $dynamicStart)

Assert-Match `
    -Text $dynamicBody `
    -Pattern "trust-magic-category-unverified" `
    -Message 'Trust Magic should still refuse the unsafe sorted known-list fallback when no verified row exists.'

Write-Host 'trust magic newly learned append static checks ok'

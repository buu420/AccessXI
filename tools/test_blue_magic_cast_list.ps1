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

Assert-NotMatch `
    -Text $source `
    -Pattern 'magic_blue_tail_command_for_selected|native-blue-magic-tail|magic-blue-tail' `
    -Message 'Blue Magic cast rows must never be replaced with guessed trailing command rows.'

$predicateStart = $source.IndexOf('function accessxi.blue_magic_spell_is_unbridled')
if ($predicateStart -lt 0) {
    throw 'Missing native Blue Magic special-spell classifier.'
}
$predicateEnd = $source.IndexOf("`nfunction ", $predicateStart + 1)
if ($predicateEnd -lt 0) {
    throw 'Could not locate end of Blue Magic special-spell classifier.'
}
$predicateBody = $source.Substring($predicateStart, $predicateEnd - $predicateStart)

Assert-Match `
    -Text $predicateBody `
    -Pattern '(?s)tonumber\(spell\.type\).*?==\s*6.*?spell_id\s*>=\s*736.*?spell_id\s*<=\s*753' `
    -Message 'Special Blue Magic membership must use the installed client resource ID block, not row position or spell names.'

Assert-NotMatch `
    -Text $predicateBody `
    -Pattern 'Polar Roar|Thunderbolt|Mighty Guard|selected|row' `
    -Message 'The special-spell classifier must not depend on screenshot names or menu rows.'

$listStart = $source.IndexOf('function accessxi.blue_magic_current_cast_spell_list')
if ($listStart -lt 0) {
    throw 'Missing dynamic Blue Magic cast-list builder.'
}
$listEnd = $source.IndexOf("`nfunction ", $listStart + 1)
if ($listEnd -lt 0) {
    throw 'Could not locate end of dynamic Blue Magic cast-list builder.'
}
$listBody = $source.Substring($listStart, $listEnd - $listStart)

Assert-Match `
    -Text $listBody `
    -Pattern 'blue_magic_current_set_spell_list\(\)' `
    -Message 'The cast list must begin with the live native Blue Magic set.'

Assert-Match `
    -Text $listBody `
    -Pattern "magic_mix_category_spell_list\('Blue Magic'\)" `
    -Message 'The cast list must use the active character learned-spell list and mix.dat order.'

Assert-Match `
    -Text $listBody `
    -Pattern '(?s)blue_magic_spell_is_unbridled\(spell\).*?seen\[spell_id\].*?spells:append\(spell\)' `
    -Message 'Only learned special spells not already present in the set may be appended.'

Assert-NotMatch `
    -Text $listBody `
    -Pattern 'Polar Roar|Thunderbolt|Mighty Guard|Longrodvonhugen|Zaltar|20\s*\+\s*3' `
    -Message 'The cast list must be dynamic and character-independent.'

$selectedStart = $source.IndexOf('function accessxi.blue_magic_current_cast_spell_for_selected')
if ($selectedStart -lt 0) {
    throw 'Missing dynamic Blue Magic selected-row resolver.'
}
$selectedEnd = $source.IndexOf("`nfunction ", $selectedStart + 1)
if ($selectedEnd -lt 0) {
    throw 'Could not locate end of dynamic Blue Magic selected-row resolver.'
}
$selectedBody = $source.Substring($selectedStart, $selectedEnd - $selectedStart)

Assert-Match `
    -Text $selectedBody `
    -Pattern 'selected\s*>\s*spells:len\(\)' `
    -Message 'Selection bounds must come from the dynamically built cast-list length.'

$dynamicStart = $source.IndexOf('function accessxi.magic_dynamic_spell_from_entry')
$dynamicEnd = $source.IndexOf("`nfunction ", $dynamicStart + 1)
$dynamicBody = $source.Substring($dynamicStart, $dynamicEnd - $dynamicStart)

Assert-Match `
    -Text $dynamicBody `
    -Pattern 'blue_magic_current_cast_spell_for_selected\(selected\)' `
    -Message 'The Magic menu must resolve Blue Magic rows through the complete dynamic cast list.'

Write-Host 'blue magic dynamic cast-list static checks ok'

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

$menuStart = $source.IndexOf("if (menu_name:eq('menu    magic', true)) then")
if ($menuStart -lt 0) {
    throw 'Missing menu magic handler.'
}
$menuEnd = $source.IndexOf("`n    if (menu_name:eq('menu    ability', true)) then", $menuStart)
if ($menuEnd -lt 0) {
    throw 'Could not locate end of menu magic handler.'
}
$menuBody = $source.Substring($menuStart, $menuEnd - $menuStart)

$mixIndex = $menuBody.IndexOf('magic_mix_spell_for_selected(selected, false)')
$dynamicIndex = $menuBody.IndexOf('magic_dynamic_spell_from_entry(entry, selected, child)')
if ($mixIndex -lt 0) {
    throw 'Direct Magic rows should resolve through the active live mix.dat order.'
}

if ($dynamicIndex -lt 0) {
    throw 'Missing dynamic Magic row fallback.'
}
Assert-Match `
    -Text $menuBody `
    -Pattern "category_label\s*==\s*''" `
    -Message 'Direct mix.dat order should only be used when no native Magic category context is available.'

$categoryGuardIndex = $menuBody.IndexOf("if (category_label == '')")
if ($categoryGuardIndex -lt 0 -or $menuBody.IndexOf('magic_mix_spell_for_selected(selected, false)', $categoryGuardIndex) -lt 0) {
    throw 'Direct mix.dat resolver must be guarded by empty category context.'
}

Assert-Match `
    -Text $menuBody `
    -Pattern "local\s+mix_spell,\s*mix_id,\s*mix_order,\s*mix_reason\s*=\s*nil,\s*0,\s*nil,\s*''" `
    -Message 'The Magic mix row branch should initialize resolver state before mix.dat lookup.'

Assert-Match `
    -Text $source `
    -Pattern "function\s+accessxi\.magic_mix_spell_for_selected\(selected,\s*allow_trust_magic\)" `
    -Message 'magic_mix_spell_for_selected should accept an allow_trust_magic guard.'

$mixFnStart = $source.IndexOf('function accessxi.magic_mix_spell_for_selected(selected, allow_trust_magic)')
if ($mixFnStart -lt 0) {
    throw 'Failed to locate magic_mix_spell_for_selected function for trust-filter regression check.'
}
$mixFnEnd = $source.IndexOf("`nfunction accessxi.magic_menu_index_probe", $mixFnStart)
if ($mixFnEnd -lt 0) {
    throw 'Could not locate end of magic_mix_spell_for_selected helper block.'
}
$mixFnBody = $source.Substring($mixFnStart, $mixFnEnd - $mixFnStart)

Assert-Match `
    -Text $mixFnBody `
    -Pattern 'allow_trust_magic\s*~=\s*true\s+and\s+tonumber\(info\.type\)\s*==\s*8' `
    -Message 'mix.dat selected-spell lookup should reject Trust Magic rows unless trust is explicitly allowed.'

Assert-Match `
    -Text $menuBody `
    -Pattern "'native-mixdat-magic-row" `
    -Message 'Direct Magic rows should log/speak a distinct live mix.dat source.'

Write-Host 'magic list live mix.dat order static checks ok'

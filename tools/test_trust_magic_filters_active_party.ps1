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

Assert-NotMatch `
    -Text $helperBody `
    -Pattern 'magic_active_trust_name_keys\(\)' `
    -Message 'Trust Magic must not shrink live mix.dat order using active party state.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'player:HasSpell\(id\)' `
    -Message 'Trust Magic should still use live player knowledge before speaking rows.'

Assert-NotMatch `
    -Text $helperBody `
    -Pattern 'magic_spell_is_active_trust' `
    -Message 'Trust Magic row order must preserve the live menu count; do not remove active Trust entries.'

Assert-Match `
    -Text $helperBody `
    -Pattern 'wanted_type\s*~=\s*8\s*[\r\n\s]*and\s+accessxi\.magic_mix_category_cache' `
    -Message 'Trust Magic category order should not use the shared cached spell list.'

Assert-Match `
    -Text $helperBody `
    -Pattern '(?s)if\s*\(wanted_type\s*~=\s*8\)\s*then.*?magic_mix_category_cache\s*=\s*spells' `
    -Message 'Trust Magic category order should avoid storing active-party filtered rows in the shared cache.'

Write-Host 'trust magic live mix order static checks ok'

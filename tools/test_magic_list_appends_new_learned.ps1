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

function Function-Body {
    param(
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $start = $source.IndexOf($StartMarker)
    if ($start -lt 0) {
        throw "Missing $Name."
    }
    $end = $source.IndexOf($EndMarker, $start)
    if ($end -lt 0) {
        throw "Could not locate end of $Name."
    }
    return $source.Substring($start, $end - $start)
}

$appendBody = Function-Body `
    -StartMarker 'function accessxi.magic_append_known_spells_missing_from_mix' `
    -EndMarker "`nfunction accessxi.magic_mix_category_spell_list" `
    -Name 'magic_append_known_spells_missing_from_mix'

Assert-Match `
    -Text $appendBody `
    -Pattern 'magic_known_spell_list_all\(\)|magic_known_spell_list_for_category\(label\)' `
    -Message 'Missing mix.dat rows should be filled from live-known spells, not from a static table.'

Assert-Match `
    -Text $appendBody `
    -Pattern 'seen\[id\]\s*~=\s*true' `
    -Message 'Newly learned append path should only add spells absent from the verified mix.dat rows.'

Assert-Match `
    -Text $appendBody `
    -Pattern 'player:HasSpell\(id\)' `
    -Message 'Newly learned append path must verify live player spell knowledge.'

Assert-Match `
    -Text $appendBody `
    -Pattern 'tonumber\(info\.type\)\s*==\s*wanted_type|info_type\s*==\s*wanted_type' `
    -Message 'Newly learned category append path must preserve the active native magic category.'

Assert-Match `
    -Text $appendBody `
    -Pattern 'allow_trust_magic\s*~=\s*true\s+and\s+info_type\s*==\s*8|allow_trust_magic\s*~=\s*true\s+and\s+tonumber\(info\.type\)\s*==\s*8' `
    -Message 'Direct Magic append path must keep Trust Magic out unless explicitly allowed.'

Assert-NotMatch `
    -Text $appendBody `
    -Pattern 'spells:sort|for id = 0,\s*2048|for id = 1,\s*2048' `
    -Message 'Append helper must not rebuild a guessed sorted spell list itself.'

$categoryBody = Function-Body `
    -StartMarker 'function accessxi.magic_mix_category_spell_list' `
    -EndMarker "`nfunction accessxi.blue_magic_mix_spell_list" `
    -Name 'magic_mix_category_spell_list'

Assert-Match `
    -Text $categoryBody `
    -Pattern 'magic_append_known_spells_missing_from_mix\(spells,\s*seen,\s*player,\s*label,\s*wanted_type\s*==\s*8\)' `
    -Message 'Magic category lists should append newly learned live spells missing from mix.dat.'

Assert-Match `
    -Text $categoryBody `
    -Pattern 'wanted_type\s*~=\s*6' `
    -Message 'Blue Magic should remain on its stricter mix.dat/native row path.'

$directBody = Function-Body `
    -StartMarker 'function accessxi.magic_mix_direct_spell_list' `
    -EndMarker "`nfunction accessxi.magic_mix_spell_for_selected" `
    -Name 'magic_mix_direct_spell_list'

Assert-Match `
    -Text $directBody `
    -Pattern 'magic_append_known_spells_missing_from_mix\(spells,\s*seen,\s*player,\s*nil,\s*allow_trust_magic\)' `
    -Message 'Direct Magic lists should append newly learned live spells missing from mix.dat.'

Assert-NotMatch `
    -Text $directBody `
    -Pattern 'spells:sort|for id = 0,\s*2048|for id = 1,\s*2048' `
    -Message 'Direct Magic list must not rebuild a guessed sorted list.'

Write-Host 'magic newly learned append static checks ok'

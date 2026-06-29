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

$directListBody = Function-Body `
    -StartMarker 'function accessxi.magic_mix_direct_spell_list' `
    -EndMarker "`nfunction accessxi.magic_mix_spell_for_selected" `
    -Name 'magic_mix_direct_spell_list'

Assert-Match `
    -Text $directListBody `
    -Pattern 'magic_mix_read_order\(\)' `
    -Message 'Direct Magic list should preserve the active live mix.dat order.'

Assert-Match `
    -Text $directListBody `
    -Pattern 'tonumber\(info\.type\)\s*~=\s*8|tonumber\(info\.type\)\s*==\s*8' `
    -Message 'Direct Magic list must explicitly filter Trust Magic rows out of raw mix.dat order.'

Assert-Match `
    -Text $directListBody `
    -Pattern 'player:HasSpell\(id\)|magic_known_flag_for_id\(id\)' `
    -Message 'Direct Magic list should only speak spells the player actually knows.'

Assert-Match `
    -Text $directListBody `
    -Pattern 'spells:append\(info\)' `
    -Message 'Direct Magic list should build a filtered spell list from live mix.dat order.'

Assert-NotMatch `
    -Text $directListBody `
    -Pattern 'spells:sort|for id = 0,\s*2048' `
    -Message 'Direct Magic list must not rebuild a guessed sorted list.'

$selectedBody = Function-Body `
    -StartMarker 'function accessxi.magic_mix_spell_for_selected' `
    -EndMarker "`nfunction accessxi.magic_menu_index_probe" `
    -Name 'magic_mix_spell_for_selected'

Assert-Match `
    -Text $selectedBody `
    -Pattern 'magic_mix_direct_spell_list\(allow_trust_magic\)' `
    -Message 'Direct Magic row selection should index the Trust-filtered live mix.dat list.'

Assert-NotMatch `
    -Text $selectedBody `
    -Pattern 'order\.ids\[selected\]' `
    -Message 'Direct Magic row selection must not index raw mix.dat rows that include Trust Magic.'

Write-Host 'magic list direct mix.dat Trust filter static checks ok'

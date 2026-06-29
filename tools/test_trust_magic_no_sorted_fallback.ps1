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

$dynamicStart = $source.IndexOf('function accessxi.magic_dynamic_spell_from_entry')
if ($dynamicStart -lt 0) {
    throw 'Missing magic_dynamic_spell_from_entry.'
}
$dynamicEnd = $source.IndexOf("`nfunction accessxi.magic_probe_offsets", $dynamicStart)
if ($dynamicEnd -lt 0) {
    throw 'Could not locate end of magic_dynamic_spell_from_entry.'
}
$dynamicBody = $source.Substring($dynamicStart, $dynamicEnd - $dynamicStart)

$trustGuardIndex = $dynamicBody.IndexOf("category_label:eq('Trust Magic', true)")
$knownFallbackIndex = $dynamicBody.IndexOf('magic_category_spell_for_selected(selected)')
if ($knownFallbackIndex -lt 0) {
    throw 'Missing known Magic category fallback; test cannot verify Trust guard placement.'
}
if ($trustGuardIndex -lt 0 -or $trustGuardIndex -gt $knownFallbackIndex) {
    throw 'Trust Magic rows must refuse the sorted known-spell fallback before magic_category_spell_for_selected.'
}

$guardBody = $dynamicBody.Substring($trustGuardIndex, $knownFallbackIndex - $trustGuardIndex)

Assert-Match `
    -Text $guardBody `
    -Pattern "'trust-magic-category-unverified'" `
    -Message 'Trust Magic guard should log a distinct unverified source.'

Assert-Match `
    -Text $guardBody `
    -Pattern 'return\s+nil' `
    -Message 'Trust Magic guard should stay silent when no native/mix row source verifies the selected Trust.'

Assert-Match `
    -Text $dynamicBody `
    -Pattern "'known-magic-category'" `
    -Message 'Non-Trust Magic categories should retain the existing known-category fallback.'

Write-Host 'trust magic sorted fallback guard static checks ok'

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

$dynamicStart = $source.IndexOf('function accessxi.magic_dynamic_spell_from_entry')
if ($dynamicStart -lt 0) {
    throw 'Missing magic_dynamic_spell_from_entry.'
}
$dynamicEnd = $source.IndexOf("`nfunction accessxi.magic_probe_offsets", $dynamicStart)
if ($dynamicEnd -lt 0) {
    throw 'Could not locate end of magic_dynamic_spell_from_entry.'
}
$dynamicBody = $source.Substring($dynamicStart, $dynamicEnd - $dynamicStart)

Assert-NotMatch `
    -Text $dynamicBody `
    -Pattern 'magic_known_type_auto_spell_for_selected\(selected\)' `
    -Message 'Dynamic Magic rows must not resolve spell labels from the sorted known-spell fallback.'

Assert-NotMatch `
    -Text $dynamicBody `
    -Pattern "'known-magic-list'" `
    -Message 'Dynamic Magic rows must not speak a spell with source known-magic-list.'

Assert-Match `
    -Text $dynamicBody `
    -Pattern 'sorted-known-fallback-blocked' `
    -Message 'Dynamic Magic rows should log that the unsafe sorted known-spell fallback was blocked.'

Assert-Match `
    -Text $dynamicBody `
    -Pattern "'magic-list-unverified'" `
    -Message 'Dynamic Magic rows should use a distinct unverified source when no live row source verifies the spell.'

function Assert-FunctionBody {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$StartMarker,
        [Parameter(Mandatory = $true)][string]$EndMarker
    )

    $start = $source.IndexOf($StartMarker)
    if ($start -lt 0) {
        throw "Missing $Name function."
    }
    $end = $source.IndexOf($EndMarker, $start)
    if ($end -lt 0) {
        throw "Could not locate end of $Name."
    }
    return $source.Substring($start, $end - $start)
}

$effectiveBody = Assert-FunctionBody `
    -Name 'magic_effective_selected' `
    -StartMarker 'function accessxi.magic_effective_selected' `
    -EndMarker "`nfunction accessxi.magic_mix_order_paths"

Assert-Match `
    -Text $effectiveBody `
    -Pattern 'if \(changed_sample and last_raw > 0\)' `
    -Message 'magic_effective_selected should infer navigation direction from raw sample delta.'

Assert-Match `
    -Text $effectiveBody `
    -Pattern 'local delta = raw_selected - last_raw' `
    -Message 'magic_effective_selected should keep the dynamic-row unwrap direction stable across wrap.'

Assert-Match `
    -Text $effectiveBody `
    -Pattern 'if \(entry ~= last_entry and last_entry ~= 0 and base > 0\)' `
    -Message 'magic_effective_selected should reset unwrap base on row entry changes.'

Assert-Match `
    -Text $effectiveBody `
    -Pattern 'if \(delta > 128\)' `
    -Message 'magic_effective_selected should account for wraparound movement when inferring navigation direction.'

Write-Host 'magic list sorted known fallback guard static checks ok'

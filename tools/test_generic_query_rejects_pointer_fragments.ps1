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

$looksRealStart = $source.IndexOf('function accessxi.native_query_label_looks_real')
if ($looksRealStart -lt 0) {
    throw 'Missing native_query_label_looks_real.'
}
$looksRealEnd = $source.IndexOf("`nfunction accessxi.native_query_candidate_label_from_text", $looksRealStart)
if ($looksRealEnd -lt 0) {
    throw 'Could not locate end of native_query_label_looks_real.'
}
$looksRealBody = $source.Substring($looksRealStart, $looksRealEnd - $looksRealStart)

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.native_query_label_fragment_penalty\(label\)' `
    -Message 'Native query scoring should centralize pointer-fragment penalties.'

Assert-Match `
    -Text $looksRealBody `
    -Pattern 'native_query_label_fragment_penalty\(label\)' `
    -Message 'Native query labels should reject corrupt pointer fragments like "tive: /".'

Assert-Match `
    -Text $looksRealBody `
    -Pattern 'return\s+false' `
    -Message 'Corrupt native query pointer fragments should be rejected before list scoring.'

$scoreStart = $source.IndexOf('function accessxi.native_query_score_items')
if ($scoreStart -lt 0) {
    throw 'Missing native_query_score_items.'
}
$scoreEnd = $source.IndexOf("`nfunction accessxi.native_query_items_are_expansion_sort", $scoreStart)
if ($scoreEnd -lt 0) {
    throw 'Could not locate end of native_query_score_items.'
}
$scoreBody = $source.Substring($scoreStart, $scoreEnd - $scoreStart)

Assert-Match `
    -Text $scoreBody `
    -Pattern 'native_query_label_fragment_penalty\(label\)' `
    -Message 'Native query list scoring should penalize corrupt labels like "PbxV" so clean direct rows win.'

Write-Host 'generic query pointer-fragment rejection static checks ok'

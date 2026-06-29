$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$genericQueryModulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\menus\generic_query.lua'
$debugProbesModulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\debug_probes.lua'

if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "Addon not found: $addonPath"
}

$source = Get-Content -LiteralPath $addonPath -Raw
$genericSource = if (Test-Path -LiteralPath $genericQueryModulePath) { Get-Content -LiteralPath $genericQueryModulePath -Raw } else { $source }
$debugSource = if (Test-Path -LiteralPath $debugProbesModulePath) { Get-Content -LiteralPath $debugProbesModulePath -Raw } else { '' }
$allSource = $source + "`n" + $genericSource + "`n" + $debugSource

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

$start = $genericSource.IndexOf('function accessxi.generic_query_row_label_from_ptr')
if ($start -lt 0) {
    throw 'Missing generic_query_row_label_from_ptr.'
}

$end = $genericSource.IndexOf("`nfunction accessxi.generic_query_help_allowed_for_label", $start)
if ($end -lt 0) {
    throw 'Could not locate the end of generic_query_row_label_from_ptr.'
}

$body = $genericSource.Substring($start, $end - $start)

Assert-Match `
    -Text $genericSource `
    -Pattern 'function\s+accessxi\.generic_query_utf16_next_pair_is_printable' `
    -Message 'Generic query wrapped rows should have a narrow UTF-16 continuation guard.'

Assert-Match `
    -Text $genericSource `
    -Pattern 'function\s+accessxi\.generic_query_row_apostrophe_continuation' `
    -Message 'Generic query wrapped rows should keep native apostrophe continuations separate from row wraps.'

Assert-Match `
    -Text $allSource `
    -Pattern 'next_byte\s*==\s*0x27' `
    -Message 'FFXI menu text decoding should decode encoded initials before apostrophes, such as native I in I''d.'

Assert-Match `
    -Text $body `
    -Pattern "(?s)lo\s*==\s*0x07.*?generic_query_utf16_next_pair_is_printable\(ptr,\s*off\s*\+\s*2,\s*0x7E\).*?flush_run\(\).*?blank_pairs\s*=\s*0" `
    -Message 'Generic query row labels should continue across native 0x07 row-wrap separators by flushing the current decodable chunk, not by injecting raw spaces.'

Assert-Match `
    -Text $body `
    -Pattern '(?s)lo\s*==\s*0x07.*?generic_query_row_apostrophe_continuation\(run,\s*next_lo,\s*next_hi\).*?run:append\("''"\)' `
    -Message 'The existing FFXI apostrophe handling for 0x07 must be preserved and extended through the explicit apostrophe guard.'

if ($body -match "(?s)generic_query_utf16_next_pair_is_printable\(ptr,\s*off\s*\+\s*2,\s*0x7E\).*?run:append\(' '\)") {
    throw 'Generic query row wraps must not inject a raw space into the current decode run; that drops encoded I letters.'
}

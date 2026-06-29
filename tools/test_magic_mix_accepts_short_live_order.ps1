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

$readStart = $source.IndexOf('function accessxi.magic_mix_read_order')
if ($readStart -lt 0) {
    throw 'Missing magic_mix_read_order.'
}
$readEnd = $source.IndexOf("`nfunction accessxi.magic_trust_name_key", $readStart)
if ($readEnd -lt 0) {
    throw 'Could not locate end of magic_mix_read_order.'
}
$readBody = $source.Substring($readStart, $readEnd - $readStart)

Assert-NotMatch `
    -Text $readBody `
    -Pattern 'ids:len\(\)\s*>=\s*20' `
    -Message 'A live profile mix.dat with fewer than 20 valid spells must not be rejected as unread.'

Assert-Match `
    -Text $readBody `
    -Pattern 'ids:len\(\)\s*>\s*0|ids:len\(\)\s*>=\s*1' `
    -Message 'magic_mix_read_order should accept any non-empty validated live profile order.'

Write-Host 'magic mix.dat short live order static checks ok'

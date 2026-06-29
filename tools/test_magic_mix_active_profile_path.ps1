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

$pathsStart = $source.IndexOf('function accessxi.magic_mix_order_paths')
if ($pathsStart -lt 0) {
    throw 'Missing magic_mix_order_paths.'
}
$pathsEnd = $source.IndexOf("`nfunction accessxi.magic_mix_u16le", $pathsStart)
if ($pathsEnd -lt 0) {
    throw 'Could not locate end of magic_mix_order_paths.'
}
$pathsBody = $source.Substring($pathsStart, $pathsEnd - $pathsStart)

Assert-Match `
    -Text $pathsBody `
    -Pattern 'macro_active_profile\(\)' `
    -Message 'mix.dat order should come from the active live FFXI USER profile.'

Assert-Match `
    -Text $pathsBody `
    -Pattern "\\\\mix\.dat" `
    -Message 'mix.dat order paths should append mix.dat under the active profile directory.'

Assert-NotMatch `
    -Text $pathsBody `
    -Pattern "addon_path\('data', 'mix\.dat'\)" `
    -Message 'Do not fall back to addon data mix.dat; stale copied DATs can create false Trust labels.'

Write-Host 'magic mix.dat active live profile path static checks ok'

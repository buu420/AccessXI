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

$resetStart = $source.IndexOf('function accessxi.nav_reset_zone_state')
if ($resetStart -lt 0) {
    throw 'Missing nav_reset_zone_state.'
}
$resetEnd = $source.IndexOf("`nlocal function poll_nav_position", $resetStart)
if ($resetEnd -lt 0) {
    throw 'Could not locate end of nav_reset_zone_state.'
}
$resetBody = $source.Substring($resetStart, $resetEnd - $resetStart)

Assert-Match `
    -Text $resetBody `
    -Pattern 'nav_active\s*=\s*false' `
    -Message 'Zone reset should clear active nav route state before the next zone/menu load.'

Assert-Match `
    -Text $resetBody `
    -Pattern 'nav_destination\s*=\s*nil' `
    -Message 'Zone reset should clear stale route destination across hard zone changes.'

Assert-Match `
    -Text $resetBody `
    -Pattern 'nav_route_start_point\s*=\s*nil' `
    -Message 'Zone reset should clear stale route start point across hard zone changes.'

Write-Host 'nav zone reset clears active route static checks ok'

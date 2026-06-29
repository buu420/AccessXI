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

function Slice-Block {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End
    )

    $startIndex = $Text.IndexOf($Start)
    if ($startIndex -lt 0) {
        throw "Could not locate block start: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex)
    if ($endIndex -lt 0) {
        throw "Could not locate block end after: $Start"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

Assert-Match `
    -Text $source `
    -Pattern 'nav_zone_load_settle_until\s*=\s*0' `
    -Message 'Expected nav-led zoning to keep a post-zone load settle timestamp.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_zone_load_settle_ms\s*=\s*8000' `
    -Message 'Expected an 8 second post-zone load settle window.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.nav_begin_zone_load_settle\s*\(' `
    -Message 'Expected a helper that starts post-zone load settle after nav-led zoning.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.nav_zone_load_settle_active\s*\(' `
    -Message 'Expected a helper that reports whether post-zone settle is still active.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.nav_poll_zone_transition_only\s*\(' `
    -Message 'Expected a zone-transition-only poller for nav-led zoning.'

$transitionPoll = Slice-Block `
    -Text $source `
    -Start 'function accessxi.nav_poll_zone_transition_only' `
    -End "`nlocal function poll_nav_position"

Assert-Match `
    -Text $transitionPoll `
    -Pattern 'nav_zone_id\(\)' `
    -Message 'The transition poller should only need the live zone id.'

Assert-Match `
    -Text $transitionPoll `
    -Pattern 'accessxi\.nav_reset_zone_state\(' `
    -Message 'The transition poller should still detect and clear state on zone changes.'

Assert-Match `
    -Text $transitionPoll `
    -Pattern 'accessxi\.nav_last_seen_zone\s*=\s*zone' `
    -Message 'The transition poller should update the last seen zone.'

if ($transitionPoll -match 'nav_player_position|nav_cached_player_position|GetPlayerEntity|GetEntity|GetLocalPosition') {
    throw 'The transition poller must not touch player/entity position while the zone is loading.'
}

$clearWatch = Slice-Block `
    -Text $source `
    -Start 'function accessxi.nav_clear_zoning_watch' `
    -End "`nfunction accessxi.nav_begin_zoning_watch"

Assert-Match `
    -Text $clearWatch `
    -Pattern "(?s)had_watch.*?reason_key\s*==\s*'zone-change'.*?accessxi\.nav_begin_zone_load_settle" `
    -Message 'Clearing a nav zoning watch because the zone changed should start the post-zone settle guard.'

$presentStart = $source.IndexOf("ashita.events.register('d3d_present'")
if ($presentStart -lt 0) {
    throw 'Could not locate d3d_present callback.'
}
$presentBody = $source.Substring($presentStart)

$guardIndex = $presentBody.IndexOf('accessxi.nav_zoning_watch_active')
$transitionIndex = $presentBody.IndexOf('accessxi.nav_poll_zone_transition_only(')
$transitionReturnIndex = if ($transitionIndex -ge 0) { $presentBody.IndexOf('return;', $transitionIndex) } else { -1 }
$positionIndex = $presentBody.IndexOf('poll_nav_position();')

if ($guardIndex -lt 0 -or $transitionIndex -lt 0 -or $transitionReturnIndex -lt 0 -or $positionIndex -lt 0) {
    throw 'Could not locate the expected nav zoning guard, transition poll, return, and position poll in d3d_present.'
}

if (-not ($guardIndex -lt $transitionIndex -and $transitionIndex -lt $transitionReturnIndex -and $transitionReturnIndex -lt $positionIndex)) {
    throw 'Present loop should zone-poll and return before any player/entity position polling during nav zoning or settle.'
}

Assert-Match `
    -Text $presentBody `
    -Pattern "(?s)poll_nav_position\(\);.*?accessxi\.poll_compass_hotkey\(\)" `
    -Message 'Present loop should still poll player position before normal addon polling outside the zone-transition guard.'

Write-Host 'nav zone load settle guard static checks ok'

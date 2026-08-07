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

$commandStart = $source.IndexOf('function accessxi.handle_axi_command')
$commandEnd = $source.IndexOf('function accessxi.dispatch_axi_command_text', $commandStart)
if ($commandStart -lt 0 -or $commandEnd -lt 0) {
    throw 'Could not locate shared AXI command handler.'
}
$commandBody = $source.Substring($commandStart, $commandEnd - $commandStart)

$presentStart = $source.IndexOf("ashita.events.register('d3d_present'")
if ($presentStart -lt 0) {
    throw 'Could not locate d3d_present callback.'
}
$presentBody = $source.Substring($presentStart)

Assert-Match `
    -Text $source `
    -Pattern "nav_route_recorder_path\s*=\s*accessxi_paths\.addon_path\('logs',\s*'ffxi-nav-route-recordings\.tsv'\)" `
    -Message 'Expected route recorder output to use an addon-relative logs path.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_route_recorder_start\(name\)' `
    -Message 'Expected route recorder start helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_route_recorder_stop\(\)' `
    -Message 'Expected route recorder stop helper.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_route_recorder_mark\(label\)' `
    -Message 'Expected route recorder mark helper for noting stairs, gates, and bad spots.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.nav_route_recorder_poll\(now\)' `
    -Message 'Expected route recorder to poll live player movement while active.'

Assert-Match `
    -Text $source `
    -Pattern "io\.open\(accessxi\.nav_route_recorder_path,\s*'a'\)" `
    -Message 'Expected route recorder to append route points instead of replacing previous recordings.'

Assert-Match `
    -Text $source `
    -Pattern "timestamp\\tsession\\tname\\tevent\\tseq\\tzone\\tx\\tz\\ty\\tyaw\\tindex\\tdistance\\tlabel" `
    -Message 'Expected route recordings to include live zone, x/z/y, yaw, index, distance, and label columns.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_route_recorder_min_distance\s*=\s*1\.0' `
    -Message 'Expected movement threshold to record walked routes without spamming while standing.'

Assert-Match `
    -Text $source `
    -Pattern 'nav_distance\(pos,\s*last\)' `
    -Message 'Expected route recorder to use live movement distance between player samples.'

Assert-Match `
    -Text $commandBody `
    -Pattern "args\[2\]:any\('record', 'recorder', 'routelog'\)" `
    -Message 'Expected /axi record command alias.'

Assert-Match `
    -Text $commandBody `
    -Pattern "args\[2\]:any\('route'\).*args\[3\]:any\('record', 'recorder', 'routelog'\)" `
    -Message 'Expected /axi route record command alias before normal route start.'

Assert-Match `
    -Text $commandBody `
    -Pattern "args\[3\]:any\('record', 'recorder', 'routelog'\)" `
    -Message 'Expected /axi nav record command alias.'

Assert-Match `
    -Text $commandBody `
    -Pattern 'accessxi\.nav_route_recorder_command\(args,\s*3,\s*4\)' `
    -Message 'Expected /axi record start <name> to dispatch with the route name tail.'

Assert-Match `
    -Text $commandBody `
    -Pattern 'accessxi\.nav_route_recorder_command\(args,\s*4,\s*5\)' `
    -Message 'Expected /axi route record start <name> and /axi nav record start <name> to dispatch with the route name tail.'

Assert-Match `
    -Text $presentBody `
    -Pattern 'accessxi\.nav_route_recorder_poll\(now\)' `
    -Message 'Expected present loop to poll the route recorder.'

Write-Host 'nav route recorder checks ok'

param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$sourcePath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$modulePath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\menus\detail_summary_navigation.lua'
$source = Get-Content -LiteralPath $sourcePath -Raw

function Get-SourceSection {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End
    )

    $startIndex = $Text.IndexOf($Start, [System.StringComparison]::Ordinal)
    if ($startIndex -lt 0) {
        throw "Expected source marker: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex + $Start.Length, [System.StringComparison]::Ordinal)
    if ($endIndex -lt 0) {
        throw "Expected end marker after $Start`: $End"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

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

$roeOpen = Get-SourceSection -Text $source `
    -Start 'function accessxi.poll_records_of_eminence_summary_open_speech(menu_name)' `
    -End 'function accessxi.records_of_eminence_surface_dat_summary_speech'
$pollMenu = Get-SourceSection -Text $source `
    -Start 'local function poll_menu()' `
    -End "ashita.events.register('d3d_present'"
$questSummary = Get-SourceSection -Text $source `
    -Start 'function accessxi.quest_detail_summary_lines(row)' `
    -End 'function accessxi.clear_quests_menu_detail_deferred_speech()'
$missionSummary = Get-SourceSection -Text $source `
    -Start 'function accessxi.mission_detail_summary_lines(row)' `
    -End 'function accessxi.missions_menu_detail_hold_ms(text)'
$missionPositionPoll = Get-SourceSection -Text $source `
    -Start 'function accessxi.poll_missions_menu_detail_position_speech(menu_name)' `
    -End 'function accessxi.poll_chat_log_deferred_speech()'

Assert-Match -Text $source `
    -Pattern "accessxi\.detail_summary_navigation\s*=\s*accessxi\.load_menu_module_table\('detail_summary_navigation'" `
    -Message 'Expected the reader to load the pure detail-summary navigation module.'

if ($roeOpen -match "return\s+type\(row\)\s*==\s*'table'.*type\(record\)\s*==\s*'table'") {
    throw 'The Records of Eminence opening poll must not consume every later poll merely because context exists.'
}
Assert-Match -Text $roeOpen `
    -Pattern "records_of_eminence_summary_open_speech\(menu_name, row, record, reason\)[\s\S]*return false;\s*end\s*$" `
    -Message 'Expected a repeated Records of Eminence summary opening to return false when it did not speak.'

$roeOpenCall = $pollMenu.IndexOf('poll_records_of_eminence_summary_open_speech')
$roePositionCall = $pollMenu.IndexOf('poll_records_of_eminence_detail_position_speech')
if ($roeOpenCall -lt 0 -or $roePositionCall -le $roeOpenCall) {
    throw 'Expected poll_menu to check Records of Eminence native detail position after one-time opening speech.'
}

Assert-Match -Text $source `
    -Pattern 'function\s+accessxi\.quest_rom_detail_parts_for_row\(row\)' `
    -Message 'Expected quest DAT decoding to preserve its variable-length display parts.'
Assert-Match -Text $source `
    -Pattern 'function\s+accessxi\.poll_quests_menu_detail_position_speech\(' `
    -Message 'Expected a native-position poll for scrollable quest summaries.'

$questPositionCall = $pollMenu.IndexOf('poll_quests_menu_detail_position_speech')
$questProtect = $pollMenu.IndexOf('quests_menu_detail_speech_protect_until')
if ($questPositionCall -lt 0 -or $questProtect -lt 0 -or $questPositionCall -ge $questProtect) {
    throw 'Expected quest line speech to run before the long-summary protection return.'
}

Assert-Match -Text $source `
    -Pattern 'function\s+accessxi\.mission_rom_order_text_from_runs\(runs\)[\s\S]{0,2500}return\s+heading,[^\r\n]*body:concat\([^\)]*\)[^\r\n]*,\s*body' `
    -Message 'Expected mission DAT decoding to return the individual mission-order body lines.'
$ordersLineAssignments = [regex]::Matches($source, 'orders_lines\s*=\s*orders_lines').Count
if ($ordersLineAssignments -lt 2) {
    throw 'Expected both mission DAT row loaders to retain variable-length orders_lines.'
}
Assert-Match -Text $source `
    -Pattern 'function\s+accessxi\.poll_missions_menu_detail_position_speech\(' `
    -Message 'Expected a native-position poll for scrollable mission summaries.'

$missionPositionCall = $pollMenu.IndexOf('poll_missions_menu_detail_position_speech')
$missionProtect = $pollMenu.IndexOf('missions_menu_detail_speech_protect_until')
if ($missionPositionCall -lt 0 -or $missionProtect -lt 0 -or $missionPositionCall -ge $missionProtect) {
    throw 'Expected mission line speech to run before the long-summary protection return.'
}

if ($questSummary -match 'position\s*>\s*\d+' -or
    $missionSummary -match 'position\s*>\s*\d+' -or
    $missionPositionPoll -match 'position\s*>\s*\d+') {
    throw 'Scrollable summary navigation must validate against the current line collection, not a fixed maximum row count.'
}

if (Test-Path -LiteralPath $modulePath) {
    $module = Get-Content -LiteralPath $modulePath -Raw
    if ($module -match '(?i)character[_-]?name|player[_-]?name|fixed[_-]?(row|count)|summary[_-]?row[_-]?count\s*=\s*\d+') {
        throw 'Detail-summary navigation must not use character identity or a fixed summary row count.'
    }
}

Write-Host 'Scrollable objective summary integration checks passed'

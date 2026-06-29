param(
    [string]$SourcePath = "C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Source not found: $SourcePath"
}

$source = Get-Content -LiteralPath $SourcePath -Raw

function Assert-Contains {
    param(
        [string]$Needle,
        [string]$Message
    )
    if (-not $source.Contains($Needle)) {
        throw $Message
    }
}

function Assert-Matches {
    param(
        [string]$Pattern,
        [string]$Message
    )
    if ($source -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Contains "search_result_packet_focus_until" "search packets must arm a short native focus window for result-list polling"
Assert-Matches "search_result_cache_packet[\s\S]*accessxi\.search_result_packet_focus_until\s*=\s*tick\(\)\s*\+\s*5000" "packet decode must fast-poll only briefly after native search rows arrive"
Assert-Matches "poll_menu[\s\S]*search_result_packet_focus_until[\s\S]*poll_interval\s*=\s*math\.min\(poll_interval,\s*35\)" "poll_menu must use a short interval while a fresh search result packet waits for native focus"
Assert-Matches "poll_menu[\s\S]*local ok_text,\s*text\s*=\s*pcall\(current_menu_speech\)[\s\S]*state menu-speech-error[\s\S]*return" "menu speech resolution must be protected so one bad native read cannot kill the addon"
Assert-Matches "unload_cb[\s\S]*local ok,\s*result\s*=\s*pcall\(function \(\) return accessxi\.unload_searchhook\(\); end\)[\s\S]*searchhook shutdown failed during unload" "searchhook unload must be protected during addon reload/shutdown"
Assert-Contains "menu_name:eq('menu    scresult', true)" "search result speech must remain native menu backed, not synthetic"

Write-Host "ok"

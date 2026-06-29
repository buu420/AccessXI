$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$debugModulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\debug_commands.lua'

$source = Get-Content -LiteralPath $addonPath -Raw
$debugModule = Get-Content -LiteralPath $debugModulePath -Raw

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

function Slice-Function {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Start,
        [Parameter(Mandatory = $true)][string]$End
    )

    $startIndex = $Text.IndexOf($Start)
    if ($startIndex -lt 0) {
        throw "Could not locate function start: $Start"
    }
    $endIndex = $Text.IndexOf($End, $startIndex)
    if ($endIndex -lt 0) {
        throw "Could not locate function end after: $Start"
    }
    return $Text.Substring($startIndex, $endIndex - $startIndex)
}

Assert-Match `
    -Text $source `
    -Pattern 'debug_probe_logging_enabled\s*=\s*false' `
    -Message 'Ambient debug probe logging should be disabled by default for normal play and nav.'

Assert-Match `
    -Text $source `
    -Pattern 'function accessxi\.debug_probe_logging_active\(\)' `
    -Message 'Addon should centralize the ambient debug-probe enabled check.'

$dispatchProbe = Slice-Function `
    -Text $source `
    -Start 'function accessxi.log_menu_dispatch_probe' `
    -End "`nlocal function option_from_index"

Assert-Match `
    -Text $dispatchProbe `
    -Pattern 'debug_probe_logging_active\(\)' `
    -Message 'Menu dispatch probe should be gated behind explicit debug probe logging.'

$ingameProbe = Slice-Function `
    -Text $source `
    -Start 'local function log_ingame_target_probe' `
    -End "`nlocal function log_unknown_menu_probe"

Assert-Match `
    -Text $ingameProbe `
    -Pattern 'debug_probe_logging_active\(\)' `
    -Message 'In-game target probe should not run unless debug probe logging is enabled.'

$unknownProbe = Slice-Function `
    -Text $source `
    -Start 'local function log_unknown_menu_probe' `
    -End "`nfunction accessxi.plain_native_menu_label"

Assert-Match `
    -Text $unknownProbe `
    -Pattern 'debug_probe_logging_active\(\)' `
    -Message 'Unknown menu memory probe should not run unless debug probe logging is enabled.'

$chatDiag = Slice-Function `
    -Text $source `
    -Start 'accessxi.chat_text_in_diag = function' `
    -End "`nlocal function is_chat_log_menu_name"

Assert-Match `
    -Text $chatDiag `
    -Pattern 'debug_probe_logging_active\(\)' `
    -Message 'Chat text hex diagnostics should not run unless debug probe logging is enabled.'

$magicProbe = Slice-Function `
    -Text $source `
    -Start 'function accessxi.log_magic_shortcut_target_probe' `
    -End "`nfunction accessxi.magic_model_probe_candidates"

Assert-Match `
    -Text $magicProbe `
    -Pattern 'debug_probe_logging_active\(\)' `
    -Message 'Magic shortcut hex dump should not run at load unless debug probe logging is enabled.'

Assert-Match `
    -Text $debugModule `
    -Pattern "has_command\(args,\s*'debugprobes'.*'probes'" `
    -Message 'Debug commands should expose a short command for temporarily enabling ambient probes.'

Assert-Match `
    -Text $debugModule `
    -Pattern 'debug_probe_logging_until\s*=\s*tick\(\)\s*\+\s*\(seconds\s*\*\s*1000\)' `
    -Message 'Ambient debug probes should auto-expire after a bounded window.'

Write-Host 'debug probes quiet-by-default static checks ok'

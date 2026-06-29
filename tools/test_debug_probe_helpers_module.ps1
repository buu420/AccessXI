$ErrorActionPreference = 'Stop'

$addonPath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$modulePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\modules\debug_probes.lua'

if (-not (Test-Path -LiteralPath $addonPath)) {
    throw "Addon not found: $addonPath"
}

$source = Get-Content -LiteralPath $addonPath -Raw
$module = if (Test-Path -LiteralPath $modulePath) { Get-Content -LiteralPath $modulePath -Raw } else { '' }

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

if ($module -eq '') {
    throw 'Expected modules\debug_probes.lua to exist.'
}

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.load_code_module\s*\(' `
    -Message 'Main addon should expose a code-module loader for non-menu modules.'

Assert-Match `
    -Text $source `
    -Pattern 'function\s+accessxi\.debug_probe_helpers_module_context\s*\(' `
    -Message 'Main addon should expose a narrow context object for debug probe helpers.'

Assert-Match `
    -Text $source `
    -Pattern "accessxi\.load_code_module\('debug_probes',\s*accessxi\.debug_probe_helpers_module_context\(\)\)" `
    -Message 'Main addon should load modules\debug_probes.lua through the code-module loader.'

Assert-NotMatch `
    -Text $source `
    -Pattern 'function\s+accessxi\.probe_byte_ascii\s*\(' `
    -Message 'Generic probe helpers should not remain in the main addon file.'

Assert-Match `
    -Text $module `
    -Pattern 'function\s+accessxi\.probe_byte_ascii\s*\(byte_value\)' `
    -Message 'Debug probe module should install accessxi.probe_byte_ascii.'

Assert-Match `
    -Text $module `
    -Pattern 'function\s+accessxi\.decode_ffxi_menu_text_fragment\s*\(text\)' `
    -Message 'Debug probe module should keep the native FFXI menu text fragment decoder.'

Assert-Match `
    -Text $module `
    -Pattern 'function\s+accessxi\.log_survival_guide_native_text_probe\s*\(seq,\s*obj,\s*reason\)' `
    -Message 'Debug probe module should keep the Survival Guide native text probe helper.'

Assert-Match `
    -Text $source `
    -Pattern 'accessxi\.dump_current_menu\s*=\s*dump_current_menu' `
    -Message 'Main addon should preserve the public dump_current_menu wrapper for early probe callers.'

Assert-Match `
    -Text $module `
    -Pattern 'accessxi\.debug_probe_dump_current_menu\s*=\s*dump_current_menu' `
    -Message 'Debug probe module should export the dump implementation behind the main wrapper.'

Assert-Match `
    -Text $module `
    -Pattern 'accessxi\.debug_probe_maybe_auto_dump_menu\s*=\s*maybe_auto_dump_menu' `
    -Message 'Debug probe module should export the auto main-menu dump helper.'

Assert-Match `
    -Text $module `
    -Pattern 'accessxi\.debug_probe_maybe_auto_dump_chat_log_menu\s*=\s*maybe_auto_dump_chat_log_menu' `
    -Message 'Debug probe module should export the auto chat-log dump helper.'

foreach ($dependency in @(
    'read_u8',
    'read_u16',
    'read_u32',
    'read_i32',
    'read_current_native_menu_index',
    'read_probe_string',
    'get_menu_name',
    'get_current_menu_object_ptr',
    'get_ffximain_base',
    'clean_probe_text',
    'log_line',
    'log_state',
    'safe_call',
    'speak',
    'hex32',
    'current_target_snapshot',
    'format_runtime_dwords',
    'log_menu_dump_dwords',
    'log_menu_dump_candidates',
    'log_menu_dump_pointer_targets',
    'log_menu_dump_shapes'
)) {
    Assert-Match `
        -Text $source `
        -Pattern ([regex]::Escape($dependency)) `
        -Message "Debug probe helper module context should expose $dependency."

    Assert-Match `
        -Text $module `
        -Pattern ("ctx\.{0}" -f [regex]::Escape($dependency)) `
        -Message "Debug probe helper module should take $dependency from its context."
}

Write-Host 'debug probe helper module boundary static checks ok'

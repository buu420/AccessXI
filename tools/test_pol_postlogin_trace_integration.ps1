param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI'
)

$ErrorActionPreference = 'Stop'

function Assert-Contains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

function Assert-NotContains {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -match $Pattern) {
        throw $Message
    }
}

function Assert-Before {
    param([string]$Text, [string]$First, [string]$Second, [string]$Message)
    $firstIndex = $Text.IndexOf($First, [System.StringComparison]::Ordinal)
    $secondIndex = $Text.IndexOf($Second, [System.StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        throw $Message
    }
}

function Get-FunctionBody {
    param([string]$Text, [string]$Signature)
    $start = $Text.IndexOf($Signature, [System.StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Function signature not found: $Signature"
    }
    $brace = $Text.IndexOf('{', $start)
    if ($brace -lt 0) {
        throw "Function body not found: $Signature"
    }
    $depth = 0
    for ($index = $brace; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -eq '{') {
            $depth++
        }
        elseif ($Text[$index] -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $index - $start + 1)
            }
        }
    }
    throw "Function body did not terminate: $Signature"
}

$sourcePath = Join-Path $RepoRoot 'src\accessxi_pol.cpp'
$tracePath = Join-Path $RepoRoot 'src\pol_trace\postlogin_trace.cpp'
$cmakePath = Join-Path $RepoRoot 'CMakeLists.txt'
foreach ($path in @($sourcePath, $tracePath, $cmakePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required source file is missing: $path"
    }
}

$source = Get-Content -LiteralPath $sourcePath -Raw
$trace = Get-Content -LiteralPath $tracePath -Raw
$cmake = Get-Content -LiteralPath $cmakePath -Raw

Assert-Contains $source '#include\s+"pol_trace/postlogin_trace\.h"' 'Native hook DLL must include the bounded PlayOnline trace module.'
Assert-Contains $source 'DefaultPolUiTraceFileName\s*=\s*L"pol-ui-native-trace\.tsv"' 'PlayOnline capture must use its full-flow TSV log.'
Assert-Contains $source 'g_pol_ui_trace_active\s*\{\s*false\s*\}' 'PlayOnline capture must be disabled by default.'
Assert-Contains $source 'std::mutex\s+g_pol_ui_trace_state_lock' 'Capture stop and callback enqueue must share a short state lock.'

$poll = Get-FunctionBody $source 'void poll_pol_ui_trace_hotkey()'
Assert-Contains $poll 'VK_CONTROL' 'Capture hotkey must require Control.'
Assert-Contains $poll 'VK_SHIFT' 'Capture hotkey must require Shift.'
Assert-Contains $poll 'VK_F10' 'Capture hotkey must require F10.'
Assert-Contains $poll 'start_pol_ui_trace\s*\(' 'Capture hotkey must start an inactive trace.'
Assert-Contains $poll 'stop_pol_ui_trace\s*\(' 'Capture hotkey must stop an active trace.'
Assert-Contains $poll 'native_post_login_surface_active\s*\(\s*\)' 'Capture polling must detect FFXI loading.'
Assert-Contains $poll 'ffxi-loaded' 'FFXI loading must identify the automatic stop reason.'

$start = Get-FunctionBody $source 'void start_pol_ui_trace()'
Assert-Before $start 'format_schema' 'g_pol_ui_trace_active.store' 'Schema must be written before capture becomes active.'
Assert-Before $start 'format_session' 'g_pol_ui_trace_active.store' 'Session start must be written before capture becomes active.'
Assert-Contains $start 'if\s*\(\s*!append_pol_ui_trace_lines' 'Capture must not become active when the trace header cannot be written.'
Assert-Contains $start 'PlayOnline capture started' 'Capture start must have one fixed audible status.'

$stop = Get-FunctionBody $source 'void stop_pol_ui_trace(const char* reason)'
Assert-Before $stop 'g_pol_ui_trace_active.exchange' 'drain_pol_ui_trace' 'Capture must become inactive before its final drain.'
Assert-Before $stop 'g_pol_ui_trace_state_lock' 'g_pol_ui_trace_active.exchange' 'Capture stop must acquire the callback handoff lock before publishing inactive.'
Assert-Contains $stop 'PlayOnline capture stopped' 'Capture stop must have one fixed audible status.'

$focusShared = Get-FunctionBody $source 'void __fastcall hook_pml_shared_focus_event'
$focusSelect = Get-FunctionBody $source 'void __fastcall hook_pml_select_focus_event'
$currentChild = Get-FunctionBody $source 'void remember_current_child_candidate'
$selectedIndex = Get-FunctionBody $source 'void remember_selected_index_candidate'
Assert-Contains $focusShared 'capture_pol_ui_focus_event\s*\(\s*accessxi::pol_trace::EventKind::focus_shared' 'Shared PML focus hook must capture a diagnostic snapshot.'
Assert-Contains $focusSelect 'capture_pol_ui_focus_event\s*\(\s*accessxi::pol_trace::EventKind::focus_select' 'Selection PML focus hook must capture a diagnostic snapshot.'
Assert-Contains $currentChild 'capture_pol_ui_current_child\s*\(' 'Current-child resolver must capture the already-resolved child without a second native lookup.'
Assert-Contains $selectedIndex 'capture_pol_ui_selected_index\s*\(' 'Selected-index resolver must capture the already-resolved child without a second native lookup.'

$captureBase = Get-FunctionBody $source 'void capture_pol_ui_snapshot('
Assert-NotContains $captureBase '_wfopen_s|fopen\s*\(|CreateFile|fprintf|dispatch_speech|speak_prelogin' 'Capture callback helper must not perform file I/O or speech.'
Assert-Before $captureBase 'classify_pol_ui_control_role' 'collect_pol_ui_trace_candidates' 'Control role must be proven before generic candidate reads.'
Assert-Contains $captureBase 'secret_control_role\s*\(' 'Capture must have an explicit secret-role branch.'
Assert-Before $captureBase 'set_masked_snapshot' 'g_pol_ui_trace.enqueue' 'Secret sanitization must occur before queue insertion.'
Assert-Before $captureBase 'g_pol_ui_trace_state_lock' 'g_pol_ui_trace.enqueue' 'Callback enqueue must occur under the short capture-state handoff lock.'

$traceCandidates = Get-FunctionBody $source 'void collect_pol_ui_trace_candidates('
Assert-Contains $traceCandidates '0x11Cu' 'Opt-in capture must include the Ghidra-proven primary CPmlImage alt field.'
Assert-Contains $traceCandidates '0x138u' 'Opt-in capture must include the paired CPmlImage alternate-state field for diagnosis.'

Assert-Contains $source 'PRELOGIN_TEXTSETTER hook-disabled rva=00064156 reason=crash-stability' 'Crash-prone PML text-setter hook must remain disabled.'
Assert-NotContains $trace 'Prism|dispatch_speech|speech_sink|speak_prelogin' 'Pure trace module must never depend on speech.'
Assert-Contains $cmake 'add_library\s*\(\s*accessxi_pol_hook[\s\S]*?src/pol_trace/postlogin_trace\.cpp' 'Native hook DLL must link the trace implementation.'

$iteration = Get-FunctionBody $source 'void run_native_hook_iteration()'
Assert-Contains $iteration 'poll_pol_ui_trace_hotkey\s*\(' 'Native worker must poll the capture hotkey.'
Assert-Contains $iteration 'poll_masked_field_state\s*\(' 'Native worker must poll the displayed masked-field state.'
Assert-Contains $iteration 'poll_set_password_state\s*\(' 'Native worker must poll the retained Set Password choice.'
Assert-Contains $iteration 'drain_pol_ui_trace\s*\(' 'Native worker must drain capture snapshots.'

$maskedPoll = Get-FunctionBody $source 'void poll_masked_field_state()'
Assert-Contains $maskedPoll 'read_native_text_field_snapshot\s*\(' 'Masked-field polling must use the exact native password decoder.'
Assert-Contains $maskedPoll 'snapshot\.field\s*!=\s*retained\.state\.object' 'Masked-field polling must reject a different native password owner.'
Assert-Contains $maskedPoll 'secret_control_role\s*\(\s*retained\.role\s*\)' 'Masked-field polling must retain the geometry-proven control role.'
Assert-Contains $maskedPoll 'observe_tracked_native_value\s*\(' 'Masked-field polling must require a verified value transition.'
Assert-Contains $maskedPoll 'masked_delta_speech\s*\(' 'Masked-field changes must report accepted character insertion.'
Assert-NotContains $maskedPoll 'GetAsyncKeyState|GetKeyboardState|ToUnicode' 'Secret-field speech must be derived from displayed native state, not keystrokes.'
Assert-NotContains $maskedPoll 'PmlGlobalFocusManagerRva|manager_value|\+\s*0x164' 'Masked-field polling must not treat CPolWinApp as a focus manager.'

$focusCandidate = Get-FunctionBody $source 'void remember_focus_candidate'
Assert-Contains $focusCandidate 'native_object_has_password_field_vtable' 'Generic focus speech must keep password fields out of text discovery.'
$currentChildResolver = Get-FunctionBody $source 'void process_current_child_candidate'
Assert-Contains $currentChildResolver 'native_object_has_password_field_vtable' 'Generic current-child speech must hand exact password fields and wrappers to the masked-field tracker.'
Assert-Contains $currentChildResolver 'prelogin_add_member_password_field_label[\s\S]*masked_focus_speech[\s\S]*remember_masked_field_focus' 'Only a geometry-owned Add Member password wrapper may seed labeled password speech.'

$reset = Get-FunctionBody $source 'void reset_prelogin_runtime_speech_state(const char* reason)'
Assert-Contains $reset 'reset_add_member_native_value_trackers\s*\(' 'Runtime reset must discard all retained Add Member native state.'

'ok: full-flow PlayOnline capture is opt-in, role-aware, secret-safe, bounded, worker-written, and speech-isolated.'

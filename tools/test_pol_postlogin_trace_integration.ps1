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

Assert-Contains $source '#include\s+"pol_trace/postlogin_trace\.h"' 'Native hook DLL must include the bounded post-login trace module.'
Assert-Contains $source 'DefaultPostLoginTraceFileName\s*=\s*L"pol-postlogin-pml-trace\.tsv"' 'Post-login capture must use its dedicated TSV log.'
Assert-Contains $source 'g_postlogin_trace_active\s*\{\s*false\s*\}' 'Post-login capture must be disabled by default.'
Assert-Contains $source 'std::mutex\s+g_postlogin_trace_state_lock' 'Capture stop and callback enqueue must share a short state lock.'

$poll = Get-FunctionBody $source 'void poll_postlogin_trace_hotkey()'
Assert-Contains $poll 'VK_CONTROL' 'Capture hotkey must require Control.'
Assert-Contains $poll 'VK_SHIFT' 'Capture hotkey must require Shift.'
Assert-Contains $poll 'VK_F10' 'Capture hotkey must require F10.'
Assert-Contains $poll 'start_postlogin_trace\s*\(' 'Capture hotkey must start an inactive trace.'
Assert-Contains $poll 'stop_postlogin_trace\s*\(' 'Capture hotkey must stop an active trace.'
Assert-Contains $poll 'native_post_login_surface_active\s*\(\s*\)' 'Capture polling must detect FFXI loading.'
Assert-Contains $poll 'ffxi-loaded' 'FFXI loading must identify the automatic stop reason.'

$start = Get-FunctionBody $source 'void start_postlogin_trace()'
Assert-Before $start 'format_schema' 'g_postlogin_trace_active.store' 'Schema must be written before capture becomes active.'
Assert-Before $start 'format_session' 'g_postlogin_trace_active.store' 'Session start must be written before capture becomes active.'
Assert-Contains $start 'if\s*\(\s*!append_postlogin_trace_lines' 'Capture must not become active when the trace header cannot be written.'
Assert-Contains $start 'Post-login capture started' 'Capture start must have one fixed audible status.'

$stop = Get-FunctionBody $source 'void stop_postlogin_trace(const char* reason)'
Assert-Before $stop 'g_postlogin_trace_active.exchange' 'drain_postlogin_trace' 'Capture must become inactive before its final drain.'
Assert-Before $stop 'g_postlogin_trace_state_lock' 'g_postlogin_trace_active.exchange' 'Capture stop must acquire the callback handoff lock before publishing inactive.'
Assert-Contains $stop 'Post-login capture stopped' 'Capture stop must have one fixed audible status.'

$focusShared = Get-FunctionBody $source 'void __fastcall hook_pml_shared_focus_event'
$focusSelect = Get-FunctionBody $source 'void __fastcall hook_pml_select_focus_event'
$currentChild = Get-FunctionBody $source 'void remember_current_child_candidate'
$selectedIndex = Get-FunctionBody $source 'void remember_selected_index_candidate'
Assert-Contains $focusShared 'capture_postlogin_focus_event\s*\(\s*accessxi::pol_trace::EventKind::focus_shared' 'Shared PML focus hook must capture a diagnostic snapshot.'
Assert-Contains $focusSelect 'capture_postlogin_focus_event\s*\(\s*accessxi::pol_trace::EventKind::focus_select' 'Selection PML focus hook must capture a diagnostic snapshot.'
Assert-Contains $currentChild 'capture_postlogin_current_child\s*\(' 'Current-child resolver must capture the already-resolved child without a second native lookup.'
Assert-Contains $selectedIndex 'capture_postlogin_selected_index\s*\(' 'Selected-index resolver must capture the already-resolved child without a second native lookup.'

$captureBase = Get-FunctionBody $source 'void capture_postlogin_snapshot('
Assert-NotContains $captureBase '_wfopen_s|fopen\s*\(|CreateFile|fprintf|dispatch_speech|speak_prelogin' 'Capture callback helper must not perform file I/O or speech.'
Assert-Before $captureBase 'g_postlogin_trace_state_lock' 'g_postlogin_trace.enqueue' 'Callback enqueue must occur under the short capture-state handoff lock.'

$traceCandidates = Get-FunctionBody $source 'void collect_postlogin_trace_candidates('
Assert-Contains $traceCandidates '0x11Cu' 'Opt-in capture must include the Ghidra-proven primary CPmlImage alt field.'
Assert-Contains $traceCandidates '0x138u' 'Opt-in capture must include the paired CPmlImage alternate-state field for diagnosis.'

Assert-Contains $source 'PRELOGIN_TEXTSETTER hook-disabled rva=00064156 reason=crash-stability' 'Crash-prone PML text-setter hook must remain disabled.'
Assert-NotContains $trace 'Prism|dispatch_speech|speech_sink|speak_prelogin' 'Pure trace module must never depend on speech.'
Assert-Contains $cmake 'add_library\s*\(\s*accessxi_pol_nvda[\s\S]*?src/pol_trace/postlogin_trace\.cpp' 'Native hook DLL must link the trace implementation.'

$iteration = Get-FunctionBody $source 'void run_reloaded_native_hook_iteration()'
Assert-Contains $iteration 'poll_postlogin_trace_hotkey\s*\(' 'Native worker must poll the capture hotkey.'
Assert-Contains $iteration 'drain_postlogin_trace\s*\(' 'Native worker must drain capture snapshots.'

'ok: post-login PML capture is opt-in, bounded, worker-written, and speech-isolated.'

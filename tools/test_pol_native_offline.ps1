param(
    [string]$RepoRoot = 'C:\Users\buu42\AccessXI',
    [string]$Configuration = 'Release',
    [string]$AshitaSdk = 'C:\Users\buu42\Ashita\plugins\sdk'
)

$ErrorActionPreference = 'Stop'
$repo = [System.IO.Path]::GetFullPath($RepoRoot)
$build = Join-Path $repo 'build'
$env:ASHITA4_SDK_PATH = [System.IO.Path]::GetFullPath($AshitaSdk)

cmake -S $repo -B $build -A Win32
if ($LASTEXITCODE -ne 0) {
    throw "Win32 CMake configuration failed with exit $LASTEXITCODE"
}
cmake --build $build --config $Configuration --target pol_native_queue_tests pol_postlogin_trace_tests pol_pml_selected_text_tests pol_native_speech_worker_tests pol_native_host_tests
if ($LASTEXITCODE -ne 0) {
    throw "Offline native harness build failed with exit $LASTEXITCODE"
}
ctest --test-dir $build -C $Configuration -R 'pol_(native_(queue|speech_worker|host)|postlogin_trace|pml_selected_text)_tests' --output-on-failure
if ($LASTEXITCODE -ne 0) {
    throw "Offline native harness failed with exit $LASTEXITCODE"
}

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\test_pol_native_hook_abi.ps1') -RepoRoot $repo
if ($LASTEXITCODE -ne 0) {
    throw "Native hook ABI regression failed with exit $LASTEXITCODE"
}

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\test_pol_postlogin_trace_integration.ps1') -RepoRoot $repo
if ($LASTEXITCODE -ne 0) {
    throw "Post-login PML trace integration regression failed with exit $LASTEXITCODE"
}

powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\test_pol_native_selected_text_integration.ps1') -RepoRoot $repo
if ($LASTEXITCODE -ne 0) {
    throw "Native selected-text integration regression failed with exit $LASTEXITCODE"
}

'ok: native PlayOnline offline queue, post-login trace, selected text, Prism, host, fingerprint, and hook ABI tests passed.'

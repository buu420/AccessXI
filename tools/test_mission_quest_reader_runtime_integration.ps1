param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$readerPath = Join-Path $Root 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$manifestPath = Join-Path $Root 'ashita\addons\accessxi_reader\data\mission-quest-route-manifest.tsv'
$luaPath = Join-Path $Root 'tools\lua51\lua5.1.exe'
$luaHarnessPath = Join-Path $Root 'tools\lua_tests\test_mission_quest_reader_runtime_integration.lua'
$integrityHarnessPath = Join-Path $Root 'tools\lua_tests\test_mission_quest_reader_integrity.lua'

& $luaPath $luaHarnessPath $readerPath
if ($LASTEXITCODE -ne 0) {
    throw "Mission/quest reader runtime Lua integration harness failed with exit code $LASTEXITCODE."
}

& $luaPath $integrityHarnessPath $readerPath
if ($LASTEXITCODE -ne 0) {
    throw "Mission/quest reader integrity Lua harness failed with exit code $LASTEXITCODE."
}

$reader = [IO.File]::ReadAllText($readerPath)
$stream = [IO.File]::OpenRead($manifestPath)
try {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $manifestDigest = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
}
finally {
    $stream.Dispose()
}
$marker = [regex]::Matches(
    $reader,
    '(?m)^local ACCESSXI_OBJECTIVE_ROUTE_MANIFEST_SHA256 = "([0-9a-f]{64})";$'
)

if ($marker.Count -ne 1) {
    throw "Reader must own exactly one canonical objective route manifest pin; found $($marker.Count)."
}
if ($marker[0].Groups[1].Value -cne $manifestDigest) {
    throw "Reader objective route manifest pin does not match the exact manifest bytes."
}

Write-Host 'mission and quest reader runtime pin test passed'

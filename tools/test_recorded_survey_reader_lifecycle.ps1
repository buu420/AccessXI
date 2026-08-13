$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Lua = Join-Path $PSScriptRoot 'lua51\lua5.1.exe'
$Harness = Join-Path $PSScriptRoot 'lua_tests\test_recorded_survey_reader_lifecycle.lua'
$Reader = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'

& $Lua $Harness $Reader
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

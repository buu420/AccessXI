$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$lua = Join-Path $repoRoot 'tools\lua51\lua5.1.exe'
$test = Join-Path $repoRoot 'tools\lua_tests\test_mission_quest_route_runtime.lua'
$runtime = Join-Path $repoRoot 'ashita\addons\accessxi_reader\modules\mission_quest_route_runtime.lua'
$policy = Join-Path $repoRoot 'ashita\addons\accessxi_reader\modules\mission_quest_route_policy.lua'

foreach ($path in @($lua, $test, $policy)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing mission/quest route runtime test dependency: $path"
    }
}

& $lua $test $runtime $policy
if ($LASTEXITCODE -ne 0) {
    throw "Mission/quest route runtime Lua behavior harness failed with exit code $LASTEXITCODE."
}

Write-Output 'mission and quest route runtime wrapper tests passed'

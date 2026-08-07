$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$lua = Join-Path $root 'tools\lua51\lua5.1.exe'
$test = Join-Path $root 'tools\test_synthesis_slots_and_key_items_speech.lua'
$synthesisModule = Join-Path $root 'ashita\addons\accessxi_reader\modules\synthesis_slots.lua'
$speechModule = Join-Path $root 'ashita\addons\accessxi_reader\modules\speech_format.lua'

& $lua $test $synthesisModule $speechModule
if ($LASTEXITCODE -ne 0) {
    throw "Synthesis slots and Key Items speech checks failed with exit code $LASTEXITCODE."
}

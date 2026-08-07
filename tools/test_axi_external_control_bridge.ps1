$ErrorActionPreference = 'Stop'

$sourcePath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$livePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $sourcePath -Raw

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

Assert-Match $source "axi_external_control_path\s*=\s*accessxi_paths\.addon_path\('logs',\s*'ffxi-accessxi-control\.txt'\)" 'Expected addon-local external control path.'
Assert-Match $source 'axi_external_control_poll_ms\s*=\s*150' 'Expected bounded 150 millisecond control-file polling.'
Assert-Match $source 'function accessxi\.poll_axi_external_control\(now\)' 'Expected external AXI control poller.'
Assert-Match $source "io\.open\(accessxi\.axi_external_control_path,\s*'r'\)" 'Expected read-only control-file open.'
Assert-Match $source 'f:close\(\)[\s\S]*?os\.remove\(accessxi\.axi_external_control_path\)' 'Expected close and one-shot deletion before dispatch.'
Assert-Match $source 'is_axi_command_args\(args\)[\s\S]*?external control rejected' 'Expected non-AXI command rejection.'
Assert-Match $source "dispatch_axi_command_text\(command_text,\s*'external-control-file'\)" 'Expected reuse of the existing AXI dispatcher.'
Assert-Match $source "ashita\.events\.register\('d3d_present'[\s\S]*?local now = tick\(\);[\s\S]*?poll_axi_external_control\(now\)[\s\S]*?nav_zoning_watch_active" 'Expected external commands before zone-settle and recorder polling.'

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $livePath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host 'AXI external control bridge checks passed'

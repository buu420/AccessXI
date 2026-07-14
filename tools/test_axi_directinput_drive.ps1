$ErrorActionPreference = 'Stop'

$sourcePath = 'C:\Users\buu42\AccessXI\ashita\addons\accessxi_reader\accessxi_reader.lua'
$livePath = 'C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua'
$source = Get-Content -LiteralPath $sourcePath -Raw

function Assert-Match([string]$Text, [string]$Pattern, [string]$Message) {
    if ($Text -notmatch $Pattern) { throw $Message }
}

Assert-Match $source 'axi_drive_min_ms\s*=\s*50' 'Expected a 50 millisecond minimum drive pulse.'
Assert-Match $source 'axi_drive_max_ms\s*=\s*500' 'Expected a 500 millisecond maximum drive pulse.'
Assert-Match $source 'function accessxi\.axi_drive_command\(args\)' 'Expected a bounded AXI drive command.'
Assert-Match $source "direction ~= '2'[\s\S]*?direction ~= '4'[\s\S]*?direction ~= '6'[\s\S]*?direction ~= '8'" 'Expected only numpad 2, 4, 6, and 8.'
Assert-Match $source 'accessxi\.is_foreground_process\(\)' 'Expected foreground-only drive input.'
Assert-Match $source 'nav_collision_control_interrupt_state\(\)' 'Expected menu and chat safety guards.'
Assert-Match $source 'nav_zoning_watch_active\(now\)[\s\S]*?nav_zone_load_settle_active\(now\)[\s\S]*?axi_drive_stop\(''zoning''' 'Expected an active drive pulse to stop immediately during zoning or post-zone settle.'
Assert-Match $source 'GetKeyboard\(\):V2D\(virtual_key\)' 'Expected runtime conversion to a DirectInput scan code.'
Assert-Match $source "args\[2\]:any\('drive',\s*'move',\s*'steer'\)[\s\S]*?axi_drive_command\(args\)" 'Expected AXI command dispatch for drive.'
Assert-Match $source "ashita\.events\.register\('key_state'[\s\S]*?ffi\.cast\('uint8_t\*',\s*e\.data_raw\)[\s\S]*?\[directinput_key\]\s*=\s*0x80" 'Expected DirectInput held-state injection.'
Assert-Match $source "ashita\.events\.register\('d3d_present'[\s\S]*?poll_axi_drive\(now\)" 'Expected automatic drive expiry polling.'
Assert-Match $source "events\.register\('unload'[\s\S]*?axi_drive_stop\('unload'" 'Expected automatic release during addon unload.'

$hashes = @(
    (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash,
    (Get-FileHash -Algorithm SHA256 -LiteralPath $livePath).Hash
) | Select-Object -Unique
if ($hashes.Count -ne 1) { throw 'Source and live Lua copies are not byte-identical.' }

Write-Host 'AXI DirectInput drive checks passed'

param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$readerPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\accessxi_reader.lua'
$queryPath = Join-Path $RepoRoot 'ashita\addons\accessxi_reader\modules\menus\generic_query.lua'
$reader = Get-Content -LiteralPath $readerPath -Raw
$query = Get-Content -LiteralPath $queryPath -Raw

function Assert-Match {
    param([string]$Text, [string]$Pattern, [string]$Message)
    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

Assert-Match $reader "load_module_table\('gear_detail_hotkeys'" `
    'Main addon must load the pure gear detail hotkey module.'
Assert-Match $reader 'function\s+accessxi\.capture_current_gear_detail\s*\(' `
    'Main addon must have a native structured gear-detail handoff.'
Assert-Match $reader 'capture_current_gear_detail\(menu_name,\s*info' `
    'Inventory item rows must hand verified current gear to the line reader.'
Assert-Match $reader 'capture_current_gear_detail\(menu_name,\s*info,\s*T\{[\s\S]*?slot_name' `
    'Equipped gear rows must preserve their live slot name in the line reader.'
Assert-Match $reader 'capture_current_gear_detail\(menu_name,\s*info,\s*T\{[\s\S]*?source\s*=\s*''inspect''' `
    'Check/inspect gear rows must hand their native item identity to the line reader.'
Assert-Match $reader 'capture_current_gear_detail\(menu_name,\s*T\{[\s\S]*?source\s*=\s*''auction''' `
    'Auction House item rows must hand verified resource-backed gear to the line reader.'
Assert-Match $query 'capture_current_gear_detail\(menu_name,\s*gear_info' `
    'Generic query and Sparks gear rows must publish their resolved native item details.'
Assert-Match $reader 'function\s+accessxi\.poll_gear_detail_hotkeys\s*\(' `
    'Main addon must poll the context-sensitive gear reader.'
Assert-Match $reader 'poll_gear_detail_hotkeys\(\)\)\s*then\s*return[\s\S]*?poll_nav_browser_hotkeys\(\)' `
    'Gear J/K/L must have priority over navigation only while verified gear is highlighted.'

Write-Host 'Gear detail hotkey integration checks passed'

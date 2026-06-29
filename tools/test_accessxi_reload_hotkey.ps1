param(
    [string]$AddonPath = "C:\Users\buu42\Ashita\addons\accessxi_reader\accessxi_reader.lua",
    [string]$DefaultScriptPath = "C:\Users\buu42\Ashita\scripts\default.txt"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $AddonPath)) {
    throw "Addon not found: $AddonPath"
}
if (-not (Test-Path -LiteralPath $DefaultScriptPath)) {
    throw "Default script not found: $DefaultScriptPath"
}

$source = Get-Content -LiteralPath $AddonPath -Raw
$defaultScript = Get-Content -LiteralPath $DefaultScriptPath -Raw

function Assert-Match {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        throw $Message
    }
}

$reloadBindPattern = '(?m)^/bind\s+\^\+r\s+/addon reload accessxi_reader\s*$'

Assert-Match -Text $defaultScript -Pattern $reloadBindPattern -Message 'Missing persistent Ctrl+Shift+R reload bind in default.txt.'
Assert-Match -Text $source -Pattern 'function\s+accessxi\.install_reload_hotkey\s*\(' -Message 'Missing runtime reload hotkey installer.'
Assert-Match -Text $source -Pattern ([regex]::Escape("/bind ^+r /addon reload accessxi_reader")) -Message 'Addon must install the Ctrl+Shift+R reload bind at runtime.'
Assert-Match -Text $source -Pattern 'install_reload_hotkey\(\)' -Message 'Reload hotkey installer must be called on addon load.'

Write-Host 'accessxi reload hotkey test passed'

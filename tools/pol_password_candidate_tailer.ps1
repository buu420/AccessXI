param(
    [string]$LogPath = 'C:\Users\buu42\AccessXI\logs\pol-monitor.log',
    [string]$OutPath = 'C:\Users\buu42\AccessXI\logs\pol-password-candidates.log'
)

function Out-Line([string]$text) {
    $dir = Split-Path -Parent $OutPath
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    Add-Content -LiteralPath $OutPath -Value "$stamp $text" -Encoding ASCII
}

$position = 0L
if (Test-Path -LiteralPath $LogPath) { $position = (Get-Item -LiteralPath $LogPath).Length }
Out-Line "START position=$position"

$currentKey = ''
$frame = @{}
$lastFlush = [DateTime]::Now

function Flush-Frame([string]$reason) {
    if ($script:frame.Count -eq 0) { return }
    $order = @('Square Enix Password','One-Time Password','Automatically log in at startup','Settings','Connect','Cancel','Connect to PlayOnline')
    $parts = @()
    foreach ($name in $order) {
        if ($script:frame.ContainsKey($name)) { $parts += "$name=$($script:frame[$name])" }
    }
    if ($parts.Count -gt 0) { Out-Line "FRAME key=$script:currentKey reason=$reason $($parts -join ' | ')" }
    $script:frame = @{}
    $script:lastFlush = [DateTime]::Now
}

while ($true) {
    Start-Sleep -Milliseconds 50
    if (([DateTime]::Now - $lastFlush).TotalMilliseconds -gt 450) { Flush-Frame 'timer' }
    if (-not (Test-Path -LiteralPath $LogPath)) { continue }
    $file = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($file.Length -lt $position) { $position = 0 }
        if ($file.Length -eq $position) { continue }
        $file.Seek($position, [System.IO.SeekOrigin]::Begin) | Out-Null
        $reader = New-Object System.IO.StreamReader($file, [Text.Encoding]::UTF8, $true, 4096, $true)
        $text = $reader.ReadToEnd()
        $position = $file.Position
        $reader.Dispose()
    } finally { $file.Dispose() }

    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match ' KEY (?<key>up|down|left|right|enter|escape)$') {
            Flush-Frame 'key'
            $currentKey = $matches.key
            continue
        }
        if ($line -match 'AccessXI POL plugin (initializing|releasing)') {
            Flush-Frame 'plugin'
            Out-Line $matches[0]
            continue
        }
        if ($line -match 'POLTEXT .*xy=(?<xy>\d+,\d+) color=(?<color>0x[0-9A-F]+) flags=(?<flags>0x[0-9A-F]+) value=(?<value>Square Enix Password|One-Time Password|Automatically log in at startup|Settings|Connect|Cancel|Connect to PlayOnline)$') {
            $value = $matches.value
            $sample = "$($matches.color),$($matches.flags),$($matches.xy)"
            if (-not $frame.ContainsKey($value)) { $frame[$value] = $sample }
            elseif ($frame[$value] -notlike "*$sample*") { $frame[$value] = $frame[$value] + ',' + $sample }
        }
    }
}

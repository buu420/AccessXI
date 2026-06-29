$cmdPath = 'C:\Users\buu42\AccessXI\logs\pol-key-driver.cmd'
$ackPath = 'C:\Users\buu42\AccessXI\logs\pol-key-driver.ack'
$hbPath = 'C:\Users\buu42\AccessXI\logs\pol-key-driver.heartbeat'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AXPolKeyDriver {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
function Tap([byte]$vk,[bool]$ext=$false,[int]$ms=800){
  $base = if ($ext) { 1 } else { 0 }
  [AXPolKeyDriver]::keybd_event($vk,0,$base,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [AXPolKeyDriver]::keybd_event($vk,0,($base -bor 2),[UIntPtr]::Zero)
  Start-Sleep -Milliseconds $ms
}

function TapRightMouse([int]$ms = 800)
{
  $down = 0x0008
  $up = 0x0010
  [AXPolKeyDriver]::mouse_event($down, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [AXPolKeyDriver]::mouse_event($up, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds $ms
}
function FocusPol(){
  $p = Get-Process pol -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($p) {
    [AXPolKeyDriver]::ShowWindow($p.MainWindowHandle,5) | Out-Null
    [AXPolKeyDriver]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 350
    return $true
  }
  return $false
}
$map = @{
  enter=@(0x0D,$false); escape=@(0x1B,$false); esc=@(0x1B,$false); tab=@(0x09,$false);
  left=@(0x25,$true); up=@(0x26,$true); right=@(0x27,$true); down=@(0x28,$true)
}
$last = ''
Set-Content -LiteralPath $hbPath -Value (Get-Date).ToString('o') -Encoding ASCII
while ($true) {
  Start-Sleep -Milliseconds 250
  Set-Content -LiteralPath $hbPath -Value (Get-Date).ToString('o') -Encoding ASCII
  if (-not (Test-Path -LiteralPath $cmdPath)) { continue }
  $cmd = Get-Content -LiteralPath $cmdPath -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($cmd) -or $cmd -eq $last) { continue }
  $last = $cmd
  $parts = $cmd -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { continue }
  $id = $parts[0].Trim()
  if ($parts.Count -gt 1 -and $parts[1].Trim().ToLowerInvariant() -eq 'stop') {
    Set-Content -LiteralPath $ackPath -Value "$id stopped" -Encoding ASCII
    break
  }
  $ok = FocusPol
  foreach ($line in $parts | Select-Object -Skip 1) {
    $t = $line.Trim().ToLowerInvariant()
  if ($t -match '^sleep\s+(\d+)$') { Start-Sleep -Milliseconds ([int]$Matches[1]); continue }
  if ($t -in @('rightclick','right-click','right_button')) { TapRightMouse 850; continue }
  if ($map.ContainsKey($t)) { $v=$map[$t]; Tap ([byte]$v[0]) ([bool]$v[1]) 850 }
}
  Set-Content -LiteralPath $ackPath -Value "$id ok focus=$ok" -Encoding ASCII
}

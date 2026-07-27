param(
    [string]$OutputPath = "$env:USERPROFILE\AccessXI\logs\pol-native-focus-inspection.json",
    [uint64]$ObjectAddress = 0
)

$ErrorActionPreference = 'Stop'
$errorOutputPath = $OutputPath + '.error.txt'
Remove-Item -LiteralPath $errorOutputPath -Force -ErrorAction SilentlyContinue

trap {
    ($_ | Out-String) |
        Set-Content -LiteralPath $errorOutputPath -Encoding UTF8
    exit 1
}

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Text;
using System.Runtime.InteropServices;

public sealed class AccessXiPolReadProcess : IDisposable
{
    private const uint ProcessVmRead = 0x0010;
    private const uint ProcessQueryInformation = 0x0400;
    private IntPtr handle;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint desiredAccess,
        bool inheritHandle,
        int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(
        IntPtr process,
        IntPtr address,
        byte[] buffer,
        int size,
        out IntPtr bytesRead);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    public AccessXiPolReadProcess(int processId)
    {
        handle = OpenProcess(
            ProcessVmRead | ProcessQueryInformation,
            false,
            processId);
        if (handle == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    public uint ReadUInt32(ulong address)
    {
        byte[] buffer = new byte[4];
        IntPtr bytesRead;
        if (!ReadProcessMemory(
                handle,
                new IntPtr(unchecked((long)address)),
                buffer,
                buffer.Length,
                out bytesRead) ||
            bytesRead.ToInt64() != buffer.Length)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        return BitConverter.ToUInt32(buffer, 0);
    }

    public string ReadAscii(ulong address, int maximumLength)
    {
        if (maximumLength <= 0)
            return String.Empty;
        byte[] buffer = new byte[maximumLength];
        IntPtr bytesRead;
        if (!ReadProcessMemory(
                handle,
                new IntPtr(unchecked((long)address)),
                buffer,
                buffer.Length,
                out bytesRead))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        int length = Array.IndexOf(buffer, (byte)0, 0, bytesRead.ToInt32());
        if (length < 0)
            return String.Empty;
        return Encoding.ASCII.GetString(buffer, 0, length);
    }

    public void Dispose()
    {
        if (handle != IntPtr.Zero)
        {
            CloseHandle(handle);
            handle = IntPtr.Zero;
        }
    }
}
'@

$processes = @(Get-Process -Name pol -ErrorAction Stop)
if ($processes.Count -ne 1) {
    throw "Expected exactly one pol.exe process; found $($processes.Count)."
}

$appModules = @(
    $processes[0].Modules |
        Where-Object { $_.ModuleName -ieq 'app.dll' }
)
if ($appModules.Count -ne 1) {
    throw "Expected exactly one app.dll module; found $($appModules.Count)."
}
$appBase = [uint64]$appModules[0].BaseAddress.ToInt64()
$appSize = [uint64]$appModules[0].ModuleMemorySize

function Format-Address {
    param([uint64]$Value)
    return '0x{0:X8}' -f $Value
}

function Read-ObjectSummary {
    param(
        [AccessXiPolReadProcess]$Reader,
        [uint64]$Address
    )

    if ($Address -lt 0x10000) {
        return $null
    }

    $vtable = [uint64]$Reader.ReadUInt32($Address)
    $summary = [ordered]@{
        Address = Format-Address $Address
        Vtable = Format-Address $vtable
        VtableRva = if ($vtable -ge $appBase -and
            $vtable -lt $appBase + $appSize) {
            Format-Address ($vtable - $appBase)
        } else {
            ''
        }
        RttiName = ''
    }
    if (-not [string]::IsNullOrEmpty($summary.VtableRva)) {
        try {
            $locator = [uint64]$Reader.ReadUInt32($vtable - 4)
            $typeDescriptor = [uint64]$Reader.ReadUInt32($locator + 12)
            $typeName = $Reader.ReadAscii($typeDescriptor + 8, 160)
            if ($typeName.StartsWith('.?AV')) {
                $summary.RttiName = $typeName
            }
        } catch {
        }
    }

    try {
        $summary.Rect = @(
            [int32]$Reader.ReadUInt32($Address + 0x54),
            [int32]$Reader.ReadUInt32($Address + 0x58),
            [int32]$Reader.ReadUInt32($Address + 0x5C),
            [int32]$Reader.ReadUInt32($Address + 0x60)
        )
    } catch {
        $summary.Rect = @()
    }

    $summary.Fields = [ordered]@{}
    foreach ($offset in @(
        0x20, 0x2C, 0x44, 0x48, 0x4C, 0x50, 0x60, 0x64,
        0x7C, 0x80, 0x84, 0x88, 0x8C, 0x90, 0x94,
        0x154, 0x158, 0x160, 0x164, 0x188, 0x18C,
        0x190, 0x194, 0x198, 0x19C, 0x1BC, 0x1C0, 0x1E8,
        0x202, 0x208, 0x244, 0x258, 0x260
    )) {
        try {
            $value = [uint64]$Reader.ReadUInt32($Address + $offset)
            $field = [ordered]@{
                Value = Format-Address $value
                VtableRva = ''
            }
            if ($value -ge 0x10000) {
                try {
                    $linkedVtable = [uint64]$Reader.ReadUInt32($value)
                    if ($linkedVtable -ge $appBase -and
                        $linkedVtable -lt $appBase + $appSize) {
                        $field.VtableRva =
                            Format-Address ($linkedVtable - $appBase)
                    }
                } catch {
                }
            }
            $summary.Fields['0x{0:X}' -f $offset] = $field
        } catch {
            $summary.Fields['0x{0:X}' -f $offset] = [ordered]@{
                Value = ''
                VtableRva = ''
            }
        }
    }
    return $summary
}

$reader = [AccessXiPolReadProcess]::new($processes[0].Id)
try {
    $manager = [uint64]$reader.ReadUInt32($appBase + 0x4E13C8)
    $focused = [uint64]$reader.ReadUInt32($manager + 0x164)
    $inspection = [ordered]@{
        Timestamp = (Get-Date).ToString('o')
        ProcessId = $processes[0].Id
        AppBase = Format-Address $appBase
        Manager = Read-ObjectSummary $reader $manager
        Focused = Read-ObjectSummary $reader $focused
        Requested = Read-ObjectSummary $reader $ObjectAddress
        LinkedObjects = @()
    }

    $rootSummaries = @($inspection.Focused, $inspection.Requested) |
        Where-Object { $_ -ne $null }
    foreach ($rootSummary in $rootSummaries) {
        $seen = @{}
        foreach ($entry in $rootSummary.Fields.GetEnumerator()) {
            $raw = $entry.Value.Value
            if ([string]::IsNullOrEmpty($raw) -or
                [string]::IsNullOrEmpty($entry.Value.VtableRva)) {
                continue
            }
            $value = [Convert]::ToUInt64($raw.Substring(2), 16)
            if ($value -lt 0x10000 -or $seen.ContainsKey($value)) {
                continue
            }
            $seen[$value] = $true
            try {
                $inspection.LinkedObjects +=
                    Read-ObjectSummary $reader $value
            } catch {
            }
        }
    }
} finally {
    $reader.Dispose()
}

$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $directory | Out-Null
$inspection | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output $OutputPath

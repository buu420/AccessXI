$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Users\buu42\AccessXI\logs\pol-selection-diff.log'
"=== selection diff start $(Get-Date -Format o) ===" | Set-Content -LiteralPath $log -Encoding UTF8
$cs = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class PolSelectionDiff
{
    const uint PROCESS_QUERY_INFORMATION = 0x0400;
    const uint PROCESS_VM_READ = 0x0010;
    const uint MEM_COMMIT = 0x1000;
    const uint PAGE_NOACCESS = 0x01;
    const uint PAGE_GUARD = 0x100;

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORY_BASIC_INFORMATION
    {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public uint AllocationProtect;
        public IntPtr RegionSize;
        public uint State;
        public uint Protect;
        public uint Type;
    }

    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern int VirtualQueryEx(IntPtr h, IntPtr addr, out MEMORY_BASIC_INFORMATION mbi, int len);
    [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buffer, int size, out IntPtr read);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);

    static bool Readable(uint protect)
    {
        if ((protect & PAGE_GUARD) != 0 || (protect & PAGE_NOACCESS) != 0) return false;
        return true;
    }

    static uint U32(byte[] b, int i)
    {
        return (uint)(b[i] | (b[i+1] << 8) | (b[i+2] << 16) | (b[i+3] << 24));
    }

    static Process FindPol()
    {
        Process best = null;
        foreach (var p in Process.GetProcesses())
        {
            string n = "";
            string t = "";
            try { n = p.ProcessName.ToLowerInvariant(); t = (p.MainWindowTitle ?? "").ToLowerInvariant(); } catch { }
            if (n.Contains("pol") || t.Contains("playonline"))
            {
                if (best == null || p.StartTime > best.StartTime) best = p;
            }
        }
        return best;
    }

    static Dictionary<long,uint> Snapshot(IntPtr h, StreamWriter log, bool initial)
    {
        var map = new Dictionary<long,uint>(200000);
        long addr = 0;
        int regions = 0;
        int keptRegions = 0;
        byte[] buffer = new byte[1024 * 1024];
        while (addr < 0x7fff0000L)
        {
            MEMORY_BASIC_INFORMATION mbi;
            int ok = VirtualQueryEx(h, new IntPtr(addr), out mbi, Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION)));
            if (ok == 0) break;
            long baseAddr = mbi.BaseAddress.ToInt64();
            long size = mbi.RegionSize.ToInt64();
            if (size <= 0) break;
            regions++;
            if (mbi.State == MEM_COMMIT && Readable(mbi.Protect) && size <= 32L * 1024L * 1024L)
            {
                keptRegions++;
                long pos = 0;
                while (pos < size)
                {
                    int want = (int)Math.Min(buffer.Length, size - pos);
                    IntPtr read;
                    if (ReadProcessMemory(h, new IntPtr(baseAddr + pos), buffer, want, out read) && read.ToInt64() >= 4)
                    {
                        int got = (int)read.ToInt64();
                        for (int i = 0; i + 4 <= got; i += 4)
                        {
                            uint v = U32(buffer, i);
                            if (v <= 20)
                                map[baseAddr + pos + i] = v;
                        }
                    }
                    pos += want;
                }
            }
            addr = baseAddr + size;
        }
        if (initial) log.WriteLine("baseline regions={0} kept={1} smallDwords={2}", regions, keptRegions, map.Count);
        return map;
    }

    static bool Down(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

    public static void Run(string logPath, int seconds)
    {
        using (var log = new StreamWriter(logPath, true, Encoding.UTF8))
        {
            var proc = FindPol();
            if (proc == null) { log.WriteLine("no POL-like process found"); return; }
            log.WriteLine("target pid={0} name={1} title={2}", proc.Id, proc.ProcessName, proc.MainWindowTitle);
            IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, proc.Id);
            if (h == IntPtr.Zero) { log.WriteLine("OpenProcess failed"); return; }
            try
            {
                var prev = Snapshot(h, log, true);
                var lastDown = new Dictionary<int,bool>();
                int[] keys = new int[] { 0x25, 0x26, 0x27, 0x28 };
                string[] names = new string[] { "LEFT", "UP", "RIGHT", "DOWN" };
                var end = DateTime.UtcNow.AddSeconds(seconds);
                while (DateTime.UtcNow < end)
                {
                    for (int k = 0; k < keys.Length; k++)
                    {
                        bool d = Down(keys[k]);
                        bool was = lastDown.ContainsKey(keys[k]) && lastDown[keys[k]];
                        if (d && !was)
                        {
                            Thread.Sleep(180);
                            var now = Snapshot(h, log, false);
                            int shown = 0;
                            foreach (var kv in prev)
                            {
                                uint nv;
                                if (now.TryGetValue(kv.Key, out nv) && nv != kv.Value && nv <= 20 && kv.Value <= 20)
                                {
                                    if (shown < 160)
                                        log.WriteLine("KEY {0} addr=0x{1:X8} {2}->{3}", names[k], kv.Key, kv.Value, nv);
                                    shown++;
                                }
                            }
                            log.WriteLine("KEY {0} changedSmall={1}", names[k], shown);
                            log.Flush();
                            prev = now;
                        }
                        lastDown[keys[k]] = d;
                    }
                    Thread.Sleep(15);
                }
            }
            finally { CloseHandle(h); }
            log.WriteLine("=== selection diff end $(Get-Date -Format o) ===");
        }
    }
}
"@
Add-Type -TypeDefinition $cs
[PolSelectionDiff]::Run($log, 90)

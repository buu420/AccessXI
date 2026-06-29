using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public static class MemScanPol {
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, UIntPtr size, out UIntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)] static extern UIntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MEMORY_BASIC_INFORMATION mbi, UIntPtr len);
  [DllImport("kernel32.dll")] static extern uint GetLastError();
  [StructLayout(LayoutKind.Sequential)] struct MEMORY_BASIC_INFORMATION { public IntPtr BaseAddress; public IntPtr AllocationBase; public uint AllocationProtect; public UIntPtr RegionSize; public uint State; public uint Protect; public uint Type; }
  const int PROCESS_QUERY_INFORMATION=0x0400, PROCESS_VM_READ=0x0010;
  const uint MEM_COMMIT=0x1000, PAGE_NOACCESS=0x01, PAGE_GUARD=0x100;
  static bool Readable(uint p){ return (p & PAGE_NOACCESS)==0 && (p & PAGE_GUARD)==0; }
  static int IndexOf(byte[] hay, int len, byte[] needle){ for(int i=0;i<=len-needle.Length;i++){ int j=0; for(;j<needle.Length;j++) if(hay[i+j]!=needle[j]) break; if(j==needle.Length) return i;} return -1; }
  static string Clean(byte[] b){ var sb=new StringBuilder(); foreach(byte x in b){ if(x>=32 && x<127) sb.Append((char)x); else if(x==0) sb.Append(' '); else sb.Append('.'); } return sb.ToString(); }
  public static void Main(){
    var ps=Process.GetProcessesByName("pol"); if(ps.Length==0){ Console.WriteLine("NO_POL"); return; }
    var p=ps[0]; Console.WriteLine("PID="+p.Id+" title="+p.MainWindowTitle);
    var h=OpenProcess(PROCESS_QUERY_INFORMATION|PROCESS_VM_READ,false,p.Id); Console.WriteLine("HANDLE=0x"+h.ToInt64().ToString("X")+" err="+Marshal.GetLastWin32Error()); if(h==IntPtr.Zero) return;
    string[] terms={"arMenu2Rec","fncMenu2","apMenuBt","PLAYINGCLASSID","Message List","Handle List","Main Menu","Quick Manuals","Navigator","Logout","Extras","Options","PlayOnline"};
    var needles=new List<Tuple<string,byte[]> >();
    foreach(var t in terms){ needles.Add(Tuple.Create("A:"+t, Encoding.ASCII.GetBytes(t))); needles.Add(Tuple.Create("W:"+t, Encoding.Unicode.GetBytes(t))); }
    long addr=0; int hits=0, regions=0, committed=0, readok=0, readfail=0;
    while(addr < 0x7fff0000 && hits < 80){
      MEMORY_BASIC_INFORMATION mbi; var q=VirtualQueryEx(h,(IntPtr)addr,out mbi,(UIntPtr)Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION))); if(q==UIntPtr.Zero) { if(regions==0) Console.WriteLine("VQ_FAIL err="+Marshal.GetLastWin32Error()+" addr=0x"+addr.ToString("X")); break; }
      regions++; long baseAddr=mbi.BaseAddress.ToInt64(); long size=(long)mbi.RegionSize;
      if(mbi.State==MEM_COMMIT && Readable(mbi.Protect) && size>0 && size<64*1024*1024){
        committed++; byte[] buf=new byte[size]; UIntPtr got;
        if(ReadProcessMemory(h,(IntPtr)baseAddr,buf,(UIntPtr)buf.Length,out got)){
          readok++; int glen=(int)got;
          foreach(var n in needles){ int at=IndexOf(buf,glen,n.Item2); if(at>=0){
            int s=Math.Max(0,at-96), l=Math.Min(glen-s,n.Item2.Length+192);
            Console.WriteLine(string.Format("HIT {0} addr=0x{1:X8} region=0x{2:X8}+0x{3:X} protect=0x{4:X}", n.Item1, baseAddr+at, baseAddr, size, mbi.Protect));
            byte[] slice=new byte[l]; Array.Copy(buf,s,slice,0,l); Console.WriteLine(Clean(slice));
            hits++; if(hits>=80) return;
          }}
        } else { readfail++; }
      }
      addr = baseAddr + Math.Max(size,0x1000);
    }
    Console.WriteLine("DONE hits="+hits+" regions="+regions+" committed="+committed+" readok="+readok+" readfail="+readfail);
  }
}

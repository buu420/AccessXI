using System.Globalization;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct PositionT
{
    public float X;
    public float Y;
    public float Z;
}

internal static class Native
{
    [DllImport("FFXINAV.dll", EntryPoint = "CreateFFXINavClass", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr CreateFFXINavClass();

    [DllImport("FFXINAV.dll", EntryPoint = "DisposeFFXINavClass", CallingConvention = CallingConvention.Cdecl)]
    public static extern void DisposeFFXINavClass(IntPtr obj);

    [DllImport("FFXINAV.dll", EntryPoint = "LoadMesh", CharSet = CharSet.Auto, CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool LoadMesh(IntPtr obj, string path);

    [DllImport("FFXINAV.dll", EntryPoint = "FindPath", CallingConvention = CallingConvention.Cdecl)]
    public static extern void FindPath(IntPtr obj, PositionT start, PositionT end, [MarshalAs(UnmanagedType.I1)] bool useCustom);

    [DllImport("FFXINAV.dll", EntryPoint = "FindClosestPath", CallingConvention = CallingConvention.Cdecl)]
    public static extern void FindClosestPath(IntPtr obj, PositionT start, PositionT end, [MarshalAs(UnmanagedType.I1)] bool useCustom);

    [DllImport("FFXINAV.dll", EntryPoint = "Get_WayPoints", CallingConvention = CallingConvention.Cdecl)]
    public static extern int GetWayPoints(IntPtr obj, out IntPtr pointer);

    [DllImport("FFXINAV.dll", EntryPoint = "Pathpoints", CallingConvention = CallingConvention.Cdecl)]
    public static extern int Pathpoints(IntPtr obj);

    [DllImport("FFXINAV.dll", EntryPoint = "IsValidPosition", CallingConvention = CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    public static extern bool IsValidPosition(IntPtr obj, PositionT pos, [MarshalAs(UnmanagedType.I1)] bool useCustom);

    [DllImport("FFXINAV.dll", EntryPoint = "GetDistanceToWall", CallingConvention = CallingConvention.Cdecl)]
    public static extern double GetDistanceToWall(IntPtr obj, PositionT pos);
}

internal static class Program
{
    private static float F(string value) => float.Parse(value, CultureInfo.InvariantCulture);

    private static int Main(string[] args)
    {
        if (args.Length != 7)
        {
            Console.Error.WriteLine("usage: navprobe <mesh.nav> <sx> <sy> <sz> <ex> <ey> <ez>");
            return 2;
        }

        var mesh = Path.GetFullPath(args[0]);
        var start = new PositionT { X = F(args[1]), Y = F(args[2]), Z = F(args[3]) };
        var end = new PositionT { X = F(args[4]), Y = F(args[5]), Z = F(args[6]) };
        Environment.CurrentDirectory = AppContext.BaseDirectory;

        var obj = Native.CreateFFXINavClass();
        if (obj == IntPtr.Zero)
        {
            Console.Error.WriteLine("CreateFFXINavClass failed");
            return 3;
        }

        try
        {
            if (!Native.LoadMesh(obj, mesh))
            {
                Console.Error.WriteLine("LoadMesh failed: " + mesh);
                return 4;
            }

            Console.WriteLine($"mesh\t{mesh}");
            Console.WriteLine($"start_valid\t{Native.IsValidPosition(obj, start, false)}\twall\t{Native.GetDistanceToWall(obj, start):0.###}");
            Console.WriteLine($"end_valid\t{Native.IsValidPosition(obj, end, false)}\twall\t{Native.GetDistanceToWall(obj, end):0.###}");

            Native.FindPath(obj, start, end, false);
            var count = Native.GetWayPoints(obj, out var ptr);
            if (count <= 0)
            {
                Native.FindClosestPath(obj, start, end, false);
                count = Native.GetWayPoints(obj, out ptr);
            }

            Console.WriteLine($"waypoints\t{count}");
            var size = Marshal.SizeOf<PositionT>();
            for (var i = 0; i < count; i++)
            {
                var pos = Marshal.PtrToStructure<PositionT>(IntPtr.Add(ptr, i * size));
                Console.WriteLine($"{i + 1}\t{pos.X:0.###}\t{pos.Y:0.###}\t{pos.Z:0.###}");
            }

            return 0;
        }
        finally
        {
            Native.DisposeFFXINavClass(obj);
        }
    }
}

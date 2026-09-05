using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using FFXI_Navmesh_Builder.Views;
using Ffxi_Navmesh_Builder.Common;
using Ffxi_Navmesh_Builder.Common.dat;

namespace NavBuild;

public static class Program
{
    private const string FfxiRoot = @"C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI\";
    private const string FfxiNavDll = @"C:\Users\buu42\Ashita\addons\accessxi_reader\third_party\FFXI-NavMesh-Builder\FFXINAV.dll";
    private const string ShippedLathineNav = @"C:\Users\buu42\Ashita\addons\accessxi_reader\third_party\xiNavmeshes\La_Theine_Plateau.nav";
    private const int ZoneListDatFileId = 55465;

    private static readonly double DefaultCellSize = 0.4;
    private static readonly double DefaultCellHeight = 0.2;
    private static readonly double DefaultAgentHeight = 1.8;
    private static readonly double DefaultAgentRadius = 0.7;
    private static readonly double DefaultClimb = 0.5;
    private static readonly double DefaultSlope = 46;
    private static readonly double DefaultTileSize = 64;
    private static readonly double DefaultRegionMin = 8;
    private static readonly double DefaultRegionMerge = 20;
    private static readonly double DefaultEdgeMaxLen = 12;
    private static readonly double DefaultEdgeError = 1.3;
    private static readonly double DefaultVertsPerPoly = 6;
    private static readonly double DefaultDetailDist = 6;
    private static readonly double DefaultDetailError = 1.0;

    private static readonly HomeView SharedHeadlessMainView = new HomeView();
    private static readonly Log SharedLog = new Log();

    public static async Task<int> Main(string[] args)
    {
        if (args.Length == 0)
        {
            Usage();
            return 2;
        }

        return args[0].ToLowerInvariant() switch
        {
            "obj" => await HandleObjCommand(args),
            "bake" => await HandleBakeCommand(args),
            "graph" => HandleGraphCommand(args),
            "selftest" => GraphBuilder.SelfTest(),
            _ => InvalidCommand(),
        };
    }

    private static async Task<int> HandleObjCommand(string[] args)
    {
        if (args.Length != 3)
        {
            Usage();
            return 2;
        }

        if (!int.TryParse(args[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out var zoneId))
        {
            Console.Error.WriteLine($"ERROR: invalid zone id '{args[1]}'.");
            return 2;
        }

        var requestedOutObj = args[2];
        if (string.IsNullOrWhiteSpace(requestedOutObj))
        {
            Console.Error.WriteLine("ERROR: output .obj path is empty.");
            return 2;
        }

        if (!Path.IsPathRooted(requestedOutObj))
            requestedOutObj = Path.Combine(Environment.CurrentDirectory, requestedOutObj);

        var requested = Path.GetFullPath(requestedOutObj);
        var targetBaseName = Path.GetFileNameWithoutExtension(requested);
        if (string.IsNullOrWhiteSpace(targetBaseName))
            targetBaseName = zoneId.ToString(CultureInfo.InvariantCulture);

        var loader = new dat(SharedLog, SharedHeadlessMainView, FfxiRoot);
        loader.ParseDat(ZoneListDatFileId);
        var zone = loader.Dms._zones.FirstOrDefault(z => z.Id == zoneId);
        var zoneName = zone?.Name ?? $"{zoneId}";
        var relZoneDatPath = zone?.Path;
        if (string.IsNullOrWhiteSpace(relZoneDatPath))
        {
            var romPath = new RomPath(FfxiRoot, SharedLog, SharedHeadlessMainView);
            var fileId = zoneId < 256 ? zoneId + 100 : zoneId + 83635;
            relZoneDatPath = romPath.GetRomPath(fileId, romPath.TableDirectory);
            if (string.IsNullOrWhiteSpace(relZoneDatPath) || relZoneDatPath == "NULL")
            {
                Console.Error.WriteLine($"ERROR: zone {zoneId} not found in ZoneList.dat.");
                return 2;
            }
        }

        var fullDatPath = Path.Combine(FfxiRoot, relZoneDatPath);
        if (!File.Exists(fullDatPath))
        {
            Console.Error.WriteLine($"ERROR: resolved zone DAT does not exist: {fullDatPath}");
            return 2;
        }

        var parsed = new ParseZoneModelDat(SharedLog, SharedHeadlessMainView, zoneId, zoneName, FfxiRoot, false);
        if (!parsed.LoadDat(fullDatPath))
        {
            Console.Error.WriteLine("ERROR: failed to parse collision dat.");
            return 2;
        }

        foreach (var subRegion in parsed.Rid.SubRegions
                     .Where(s => !string.IsNullOrWhiteSpace(s.RomPath) && s.RomPath != FfxiRoot && s.RomPath != fullDatPath))
        {
            parsed.LoadDat(subRegion.RomPath);
        }

        // MZB.WriteObj writes to ./"Map Collision obj files" and does not create it.
        Directory.CreateDirectory(Path.Combine(Directory.GetCurrentDirectory(), "Map Collision obj files"));
        if (!parsed.Mzb.WriteObj(targetBaseName))
        {
            Console.Error.WriteLine("ERROR: MZB.WriteObj failed.");
            return 2;
        }

        var hardcodedObjPath = Path.GetFullPath(Path.Combine(
            Directory.GetCurrentDirectory(),
            "Map Collision obj files",
            $"{targetBaseName}.obj"));
        if (!File.Exists(hardcodedObjPath))
        {
            Console.Error.WriteLine($"ERROR: hardcoded output missing: {hardcodedObjPath}");
            return 2;
        }

        var finalObj = requested;
        var hardcodedDir = Path.GetDirectoryName(finalObj);
        if (!string.IsNullOrWhiteSpace(hardcodedDir))
            Directory.CreateDirectory(hardcodedDir);

        if (!string.Equals(hardcodedObjPath, finalObj, StringComparison.OrdinalIgnoreCase))
        {
            File.Copy(hardcodedObjPath, finalObj, overwrite: true);
        }

        var counts = CountObjCounts(finalObj);

        Console.WriteLine($"obj: zoneId={zoneId}");
        Console.WriteLine($"obj: zoneName={zoneName}");
        Console.WriteLine($"obj: src={fullDatPath}");
        Console.WriteLine($"obj: out={finalObj}");
        Console.WriteLine($"obj: vertices={counts.vertices} faces={counts.faces}");
        return 0;
    }

    private static async Task<int> HandleBakeCommand(string[] args)
    {
        if (args.Length < 3)
        {
            Usage();
            return 2;
        }

        var inputObj = args[1];
        var outputNav = args[2];
        if (!File.Exists(inputObj))
        {
            Console.Error.WriteLine($"ERROR: input OBJ not found: {inputObj}");
            return 2;
        }

        var settings = new BakeSettings(
            DefaultCellSize,
            DefaultCellHeight,
            DefaultAgentHeight,
            DefaultAgentRadius,
            DefaultClimb,
            DefaultSlope,
            DefaultTileSize,
            DefaultRegionMin,
            DefaultRegionMerge,
            DefaultEdgeMaxLen,
            DefaultEdgeError,
            DefaultVertsPerPoly,
            DefaultDetailDist,
            DefaultDetailError);
        try
        {
            ParseOptions(args, 3, settings);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"ERROR: {ex.Message}");
            return 2;
        }

        var inObj = Path.GetFullPath(inputObj);
        var outNav = Path.GetFullPath(outputNav);
        Directory.CreateDirectory(Path.GetDirectoryName(outNav) ?? Environment.CurrentDirectory);

        PrintSettings(settings);

        if (!File.Exists(FfxiNavDll))
        {
            Console.Error.WriteLine($"ERROR: FFXINAV DLL not found: {FfxiNavDll}");
            return 2;
        }

        // The DLL writes to .\"Dumped NavMeshes"\<objname>.nav relative to the working
        // directory and does not create that folder -- same trap as MZB.WriteObj. Without
        // it Dump_NavMesh fails silently, because it swallows every exception.
        var dumpDir = Path.Combine(Directory.GetCurrentDirectory(), "Dumped NavMeshes");
        Directory.CreateDirectory(dumpDir);

        var stopwatch = Stopwatch.StartNew();
        using (var native = CreateFfxi())
        {
            // Dump_NavMesh BUILDS from the OBJ and saves the .nav in one call -- its own
            // docs say "remember to pass NavMesh Settings to the DLL BEFORE you try and
            // build a mesh", and the GUI's BuildNavMesh passes it the OBJ path, not an
            // output path. Settings first, then hand it the geometry.
            native.ChangeNavMeshSettings(
                settings.CellSize,
                settings.CellHeight,
                settings.AgentHeight,
                settings.AgentRadius,
                settings.Climb,
                settings.Slope,
                settings.TileSize,
                settings.RegionMin,
                settings.RegionMerge,
                settings.EdgeMaxLen,
                settings.EdgeError,
                settings.VertsPerPoly,
                settings.DetailDist,
                settings.DetailError,
                false);

            await native.Dump_NavMesh(inObj);
        }

        stopwatch.Stop();

        // Dump_NavMesh swallows every exception, so the only honest success test is
        // whether a file appeared. It names the output after the OBJ.
        var produced = Path.Combine(dumpDir,
            Path.GetFileNameWithoutExtension(inObj) + ".nav");
        if (!File.Exists(produced))
        {
            var guess = new[] { dumpDir, Path.GetDirectoryName(inObj) ?? ".", Directory.GetCurrentDirectory() }
                .Where(Directory.Exists)
                .SelectMany(d => Directory.GetFiles(d, "*.nav"))
                .OrderByDescending(f => new FileInfo(f).LastWriteTimeUtc)
                .FirstOrDefault();
            if (guess == null)
            {
                Console.Error.WriteLine("ERROR: bake produced no .nav file.");
                return 2;
            }
            produced = guess;
        }
        if (!string.Equals(produced, outNav, StringComparison.OrdinalIgnoreCase))
        {
            File.Move(produced, outNav, true);
        }

        var outSize = new FileInfo(outNav).Length;
        Console.WriteLine($"bake: out={outNav}");
        Console.WriteLine($"bake: elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F1}");
        Console.WriteLine($"bake: size={outSize}");

        using (var native = CreateFfxi())
        {
            var loadsOur = native.LoadNavMesh(outNav);
            var loadsShipped = false;
            var shippedExists = File.Exists(ShippedLathineNav);
            var shippedSize = shippedExists ? new FileInfo(ShippedLathineNav).Length : -1;
            if (shippedExists)
                loadsShipped = native.LoadNavMesh(ShippedLathineNav);

            Console.WriteLine($"bake: output_loads={loadsOur}");
            Console.WriteLine($"bake: shipped_nav={ShippedLathineNav}");
            Console.WriteLine($"bake: shipped_exists={shippedExists}");
            Console.WriteLine($"bake: shipped_size={shippedSize}");
            Console.WriteLine($"bake: shipped_loads={loadsShipped}");
        }

        return 0;
    }

    private static Ffxinav CreateFfxi()
    {
        if (!File.Exists(FfxiNavDll))
            throw new FileNotFoundException("Missing FFXINAV.dll.", FfxiNavDll);

        var originalDir = Environment.CurrentDirectory;
        Directory.SetCurrentDirectory(Path.GetDirectoryName(FfxiNavDll)!);
        try
        {
            return new Ffxinav();
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDir);
        }
    }

    private static int InvalidCommand()
    {
        Console.Error.WriteLine("ERROR: unknown command.");
        Usage();
        return 2;
    }

    private static int HandleGraphCommand(string[] args)
    {
        if (args.Length < 3) { Usage(); return 2; }
        var inObj = args[1];
        if (!File.Exists(inObj))
        {
            Console.Error.WriteLine($"ERROR: input OBJ not found: {inObj}");
            return 2;
        }
        var opt = new GraphBuilder.Options();
        var sawUpGrade = false; var sawDownGrade = false;
        for (var i = 3; i + 1 < args.Length + 1 && i < args.Length; i += 2)
        {
            if (i + 1 >= args.Length) break;
            if (args[i].ToLowerInvariant() == "--survey") { opt.SurveyPath = args[i + 1]; continue; }
            if (args[i].ToLowerInvariant() == "--baseline") { opt.BaselinePath = args[i + 1]; continue; }
            if (args[i].ToLowerInvariant() == "--destinations") { opt.DestinationsPath = args[i + 1]; continue; }
            if (args[i].ToLowerInvariant() == "--triage") { opt.TriagePath = args[i + 1]; continue; }
            if (args[i].ToLowerInvariant() == "--sidetestab") { opt.SideTestAB = args[i + 1] != "0"; continue; }
            if (args[i].ToLowerInvariant() == "--doorwayveto") { opt.DoorwayVeto = args[i + 1] != "0"; continue; }
            // --diagbox "x0,z0,x1,z1"  (game-frame XZ; order-agnostic corners)
            if (args[i].ToLowerInvariant() == "--diagbox")
            {
                var c = args[i + 1].Split(',');
                if (c.Length != 4
                    || !double.TryParse(c[0], System.Globalization.CultureInfo.InvariantCulture, out double dx0)
                    || !double.TryParse(c[1], System.Globalization.CultureInfo.InvariantCulture, out double dz0)
                    || !double.TryParse(c[2], System.Globalization.CultureInfo.InvariantCulture, out double dx1)
                    || !double.TryParse(c[3], System.Globalization.CultureInfo.InvariantCulture, out double dz1))
                { Console.Error.WriteLine($"ERROR: bad --diagbox '{args[i + 1]}'"); return 2; }
                opt.DiagX0 = Math.Min(dx0, dx1); opt.DiagX1 = Math.Max(dx0, dx1);
                opt.DiagZ0 = Math.Min(dz0, dz1); opt.DiagZ1 = Math.Max(dz0, dz1);
                opt.HasDiag = true;
                continue;
            }
            // --probe "name:sx,sz,sy>gx,gz,gy"  (repeatable)
            if (args[i].ToLowerInvariant() == "--probe")
            {
                var spec = args[i + 1];
                var colon = spec.IndexOf(':');
                var name = colon > 0 ? spec.Substring(0, colon) : "probe";
                var body = colon > 0 ? spec.Substring(colon + 1) : spec;
                var ends = body.Split('>');
                if (ends.Length != 2) { Console.Error.WriteLine($"ERROR: bad --probe '{spec}'"); return 2; }
                var a = ends[0].Split(','); var b = ends[1].Split(',');
                if (a.Length != 3 || b.Length != 3) { Console.Error.WriteLine($"ERROR: bad --probe '{spec}'"); return 2; }
                opt.Probes.Add((name,
                    double.Parse(a[0], CultureInfo.InvariantCulture), double.Parse(a[1], CultureInfo.InvariantCulture),
                    double.Parse(a[2], CultureInfo.InvariantCulture),
                    double.Parse(b[0], CultureInfo.InvariantCulture), double.Parse(b[1], CultureInfo.InvariantCulture),
                    double.Parse(b[2], CultureInfo.InvariantCulture)));
                continue;
            }
            // --erode wall:rim[,wall:rim...]  e.g. --erode 0.70:0.70,0.40:0.40,0.70:0.00
            if (args[i].ToLowerInvariant() == "--erode")
            {
                foreach (var pair in args[i + 1].Split(',', StringSplitOptions.RemoveEmptyEntries))
                {
                    var halves = pair.Split(':');
                    if (halves.Length != 2) { Console.Error.WriteLine($"ERROR: bad --erode pair '{pair}'"); return 2; }
                    opt.ErodeRadii.Add((double.Parse(halves[0], CultureInfo.InvariantCulture),
                                        double.Parse(halves[1], CultureInfo.InvariantCulture)));
                }
                continue;
            }
            var v = double.Parse(args[i + 1], CultureInfo.InvariantCulture);
            switch (args[i].ToLowerInvariant())
            {
                case "--slope": opt.MaxSlopeDeg = v; break;
                case "--stepup": opt.MaxStepUp = v; break;
                case "--maxdrop": opt.MaxDrop = v; break;
                case "--agentradius": opt.AgentRadius = v; break;
                case "--regionerode": opt.RegionErode = v; break;
                case "--downgrade": opt.MaxDownGrade = v; sawDownGrade = true; break;
                case "--upgrade": opt.MaxUpGrade = v; sawUpGrade = true; break;
                case "--weld": opt.WeldTolerance = v; break;
                case "--zone": opt.ZoneId = (int)v; break;
                case "--permissiveportals": opt.PermissivePortals = v != 0; break;   // diagnostic
                case "--format": opt.FormatVersion = (int)v; break;
                default:
                    Console.Error.WriteLine($"ERROR: unknown option {args[i]}");
                    return 2;
            }
        }
        // Grade limits follow the slope limit unless explicitly overridden --
        // otherwise --slope 40 admits steeper triangles while the edge rule
        // still refuses to connect them, which silently fragments the graph.
        if (!sawUpGrade) opt.MaxUpGrade = Math.Tan(opt.MaxSlopeDeg * Math.PI / 180.0);
        if (!sawDownGrade) opt.MaxDownGrade = Math.Max(1.0, Math.Tan(opt.MaxSlopeDeg * Math.PI / 180.0));
        return GraphBuilder.Run(Path.GetFullPath(inObj), Path.GetFullPath(args[2]), opt);
    }

    private static void Usage()
    {
        Console.WriteLine("Usage:");
        Console.WriteLine("  navbuild obj <zoneId> <out.obj>");
        Console.WriteLine("  navbuild selftest");
        Console.WriteLine(
            "  navbuild bake <in.obj> <out.nav> [--cellsize V] [--cellheight V] [--agentheight V] [--agentradius V] [--climb V] [--slope V] [--tilesize V] [--regionmin V] [--regionmerge V] [--edgemaxlen V] [--edgeerror V] [--vertsperpoly V] [--detaildist V] [--detailerror V]");
        Console.WriteLine("  navbuild graph <in.obj> <out.bin> [--slope V] [--stepup V] [--maxdrop V] [--agentradius V] [--survey F] [--baseline F] [--destinations F]");
        Console.WriteLine("  navbuild graph <in.obj> <out.bin> [--slope V] [--stepup V] [--maxdrop V] [--agentradius V] [--survey F] [--baseline F] [--destinations F]");
    }

    private static (int vertices, int faces) CountObjCounts(string path)
    {
        var vertices = 0;
        var faces = 0;
        foreach (var line in File.ReadLines(path))
        {
            if (line.StartsWith("v ", StringComparison.OrdinalIgnoreCase)) vertices++;
            else if (line.StartsWith("f ", StringComparison.OrdinalIgnoreCase)) faces++;
        }

        return (vertices, faces);
    }

    private static void PrintSettings(BakeSettings settings)
    {
        Console.WriteLine("bake: settings used");
        Console.WriteLine($"  cellsize = {settings.CellSize}");
        Console.WriteLine($"  cellheight = {settings.CellHeight}");
        Console.WriteLine($"  agentheight = {settings.AgentHeight}");
        Console.WriteLine($"  agentradius = {settings.AgentRadius}");
        Console.WriteLine($"  climb = {settings.Climb}");
        Console.WriteLine($"  slope = {settings.Slope}");
        Console.WriteLine($"  tilesize = {settings.TileSize}");
        Console.WriteLine($"  regionmin = {settings.RegionMin}");
        Console.WriteLine($"  regionmerge = {settings.RegionMerge}");
        Console.WriteLine($"  edgemaxlen = {settings.EdgeMaxLen}");
        Console.WriteLine($"  edgeerror = {settings.EdgeError}");
        Console.WriteLine($"  vertsperpoly = {settings.VertsPerPoly}");
        Console.WriteLine($"  detaildist = {settings.DetailDist}");
        Console.WriteLine($"  detailerror = {settings.DetailError}");
    }

    private static void ParseOptions(string[] args, int offset, BakeSettings settings)
    {
        var i = offset;
        while (i < args.Length)
        {
            if (!args[i].StartsWith("--", StringComparison.Ordinal))
                throw new ArgumentException($"Unexpected token '{args[i]}'.");

            string key;
            string value;
            var eq = args[i].IndexOf('=', StringComparison.Ordinal);
            if (eq >= 0)
            {
                key = args[i][2..eq].ToLowerInvariant();
                value = args[i][(eq + 1)..];
            }
            else
            {
                if (i + 1 >= args.Length)
                    throw new ArgumentException($"Missing value for option '{args[i]}'.");

                key = args[i][2..];
                value = args[i + 1];
                i++;
            }

            var numericValue = double.Parse(value, CultureInfo.InvariantCulture);
            switch (key.ToLowerInvariant())
            {
                case "cellsize":
                    settings.CellSize = numericValue;
                    break;
                case "cellheight":
                    settings.CellHeight = numericValue;
                    break;
                case "agentheight":
                    settings.AgentHeight = numericValue;
                    break;
                case "agentradius":
                    settings.AgentRadius = numericValue;
                    break;
                case "climb":
                    settings.Climb = numericValue;
                    break;
                case "slope":
                    settings.Slope = numericValue;
                    break;
                case "tilesize":
                    settings.TileSize = numericValue;
                    break;
                case "regionmin":
                    settings.RegionMin = numericValue;
                    break;
                case "regionmerge":
                    settings.RegionMerge = numericValue;
                    break;
                case "edgemaxlen":
                    settings.EdgeMaxLen = numericValue;
                    break;
                case "edgeerror":
                    settings.EdgeError = numericValue;
                    break;
                case "vertsperpoly":
                    settings.VertsPerPoly = numericValue;
                    break;
                case "detaildist":
                    settings.DetailDist = numericValue;
                    break;
                case "detailerror":
                    settings.DetailError = numericValue;
                    break;
                default:
                    throw new ArgumentException($"Unknown option '--{key}'.");
            }

            i++;
        }
    }
}

internal sealed class BakeSettings
{
    public BakeSettings(
        double cellSize,
        double cellHeight,
        double agentHeight,
        double agentRadius,
        double climb,
        double slope,
        double tileSize,
        double regionMin,
        double regionMerge,
        double edgeMaxLen,
        double edgeError,
        double vertsPerPoly,
        double detailDist,
        double detailError)
    {
        CellSize = cellSize;
        CellHeight = cellHeight;
        AgentHeight = agentHeight;
        AgentRadius = agentRadius;
        Climb = climb;
        Slope = slope;
        TileSize = tileSize;
        RegionMin = regionMin;
        RegionMerge = regionMerge;
        EdgeMaxLen = edgeMaxLen;
        EdgeError = edgeError;
        VertsPerPoly = vertsPerPoly;
        DetailDist = detailDist;
        DetailError = detailError;
    }

    public double CellSize { get; set; }
    public double CellHeight { get; set; }
    public double AgentHeight { get; set; }
    public double AgentRadius { get; set; }
    public double Climb { get; set; }
    public double Slope { get; set; }
    public double TileSize { get; set; }
    public double RegionMin { get; set; }
    public double RegionMerge { get; set; }
    public double EdgeMaxLen { get; set; }
    public double EdgeError { get; set; }
    public double VertsPerPoly { get; set; }
    public double DetailDist { get; set; }
    public double DetailError { get; set; }
}

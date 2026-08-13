using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;

[StructLayout(LayoutKind.Sequential)]
public struct PositionT
{
    public float X;
    public float Y;
    public float Z;
}

internal sealed class NativeCallCounts
{
    public int FindPath;
    public int FindClosestPath;
    public int GetWayPoints;

    public object JsonValue() => new Dictionary<string, int>
    {
        ["FindPath"] = FindPath,
        ["FindClosestPath"] = FindClosestPath,
        ["Get_WayPoints"] = GetWayPoints,
    };

    public override string ToString() =>
        $"FindPath:{FindPath},FindClosestPath:{FindClosestPath},Get_WayPoints:{GetWayPoints}";
}

internal interface IProofNative : IDisposable
{
    bool IsValid(PositionT position);
    void FindPath(PositionT start, PositionT end);
    PositionT[] CopyWayPointsImmediately(int maximumCount);
    double DistanceToWall(PositionT position);
}

internal sealed class PinnedFile : IDisposable
{
    private readonly FileStream stream;
    public string CanonicalPath { get; }

    public PinnedFile(string canonicalPath)
    {
        CanonicalPath = Path.GetFullPath(canonicalPath);
        stream = new FileStream(
            CanonicalPath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize: 128 * 1024,
            FileOptions.SequentialScan
        );
    }

    public string HashCurrent()
    {
        stream.Position = 0;
        var digest = SHA256.HashData(stream);
        stream.Position = 0;
        return Convert.ToHexString(digest).ToLowerInvariant();
    }

    public void Dispose() => stream.Dispose();
}

internal sealed class ExactNative : IProofNative
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr CreateDelegate();

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void DisposeDelegate(IntPtr obj);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool LoadMeshDelegate(IntPtr obj, [MarshalAs(UnmanagedType.LPWStr)] string path);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    [return: MarshalAs(UnmanagedType.I1)]
    private delegate bool IsValidPositionDelegate(
        IntPtr obj,
        PositionT position,
        [MarshalAs(UnmanagedType.I1)] bool useCustom
    );

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void FindPathDelegate(
        IntPtr obj,
        PositionT start,
        PositionT end,
        [MarshalAs(UnmanagedType.I1)] bool useCustom
    );

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int GetWayPointsDelegate(IntPtr obj, out IntPtr pointer);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate double GetDistanceToWallDelegate(IntPtr obj, PositionT position);

    private readonly IntPtr library;
    private readonly DisposeDelegate dispose;
    private readonly LoadMeshDelegate loadMesh;
    private readonly IsValidPositionDelegate isValidPosition;
    private readonly FindPathDelegate findPath;
    private readonly GetWayPointsDelegate getWayPoints;
    private readonly GetDistanceToWallDelegate getDistanceToWall;
    private IntPtr instance;

    public ExactNative(string canonicalDllPath)
    {
        library = NativeLibrary.Load(canonicalDllPath);
        try
        {
            var create = Export<CreateDelegate>("CreateFFXINavClass");
            dispose = Export<DisposeDelegate>("DisposeFFXINavClass");
            loadMesh = Export<LoadMeshDelegate>("LoadMesh");
            isValidPosition = Export<IsValidPositionDelegate>("IsValidPosition");
            findPath = Export<FindPathDelegate>("FindPath");
            getWayPoints = Export<GetWayPointsDelegate>("Get_WayPoints");
            getDistanceToWall = Export<GetDistanceToWallDelegate>("GetDistanceToWall");
            instance = create();
            if (instance == IntPtr.Zero)
            {
                throw new InvalidOperationException("CreateFFXINavClass returned null.");
            }
        }
        catch
        {
            NativeLibrary.Free(library);
            throw;
        }
    }

    private T Export<T>(string name) where T : Delegate =>
        Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library, name));

    public void LoadMesh(string canonicalMeshPath)
    {
        if (!loadMesh(instance, canonicalMeshPath))
        {
            throw new InvalidOperationException($"LoadMesh failed: {canonicalMeshPath}");
        }
    }

    public bool IsValid(PositionT position) => isValidPosition(instance, position, false);

    public void FindPath(PositionT start, PositionT end) =>
        findPath(instance, start, end, false);

    public void FindClosestPathDiagnostic(PositionT start, PositionT end)
    {
        var diagnostic = Export<FindPathDelegate>("FindClosestPath");
        diagnostic(instance, start, end, false);
    }

    public PositionT[] CopyWayPointsImmediately(int maximumCount)
    {
        var count = getWayPoints(instance, out var pointer);
        if (count < 0 || count > maximumCount)
        {
            throw new InvalidDataException($"Native waypoint count is unsafe: {count}.");
        }
        if (count > 0 && pointer == IntPtr.Zero)
        {
            throw new InvalidDataException("Native waypoint pointer is null for a nonempty path.");
        }
        var copied = new PositionT[count];
        var size = Marshal.SizeOf<PositionT>();
        for (var index = 0; index < count; index++)
        {
            var point = Marshal.PtrToStructure<PositionT>(IntPtr.Add(pointer, checked(index * size)));
            if (!float.IsFinite(point.X) || !float.IsFinite(point.Y) || !float.IsFinite(point.Z))
            {
                throw new InvalidDataException("Native path returned a non-finite waypoint.");
            }
            copied[index] = point;
        }
        return copied;
    }

    public double DistanceToWall(PositionT position) => getDistanceToWall(instance, position);

    public void Dispose()
    {
        if (instance != IntPtr.Zero)
        {
            dispose(instance);
            instance = IntPtr.Zero;
        }
        if (library != IntPtr.Zero)
        {
            NativeLibrary.Free(library);
        }
    }
}

internal sealed class SpyProofNative : IProofNative
{
    private readonly int[] pathCounts;
    private int requestIndex;
    private PositionT currentStart;
    private PositionT currentEnd;

    public List<string> Order { get; } = new();
    public List<PositionT> Starts { get; } = new();
    public List<PositionT> Ends { get; } = new();
    public IReadOnlyList<string> LoadedExports { get; } = new[]
    {
        "CreateFFXINavClass", "DisposeFFXINavClass", "LoadMesh", "IsValidPosition",
        "FindPath", "Get_WayPoints", "GetDistanceToWall",
    };

    public SpyProofNative(params int[] pathCounts)
    {
        this.pathCounts = pathCounts;
    }

    public bool IsValid(PositionT position) => true;

    public void FindPath(PositionT start, PositionT end)
    {
        if (requestIndex >= pathCounts.Length)
        {
            throw new InvalidOperationException("Spy received an unexpected request.");
        }
        currentStart = start;
        currentEnd = end;
        Starts.Add(start);
        Ends.Add(end);
        Order.Add("FindPath");
    }

    public PositionT[] CopyWayPointsImmediately(int maximumCount)
    {
        Order.Add("Get_WayPoints");
        var count = pathCounts[requestIndex++];
        if (count > maximumCount)
        {
            throw new InvalidDataException("Spy path exceeds the selected maximum.");
        }
        var result = count switch
        {
            0 => Array.Empty<PositionT>(),
            2 => new[] { currentStart, currentEnd },
            _ => throw new InvalidOperationException("Spy supports only zero or two points."),
        };
        var copied = result.ToArray();
        Order.Add("copy");
        return copied;
    }

    public double DistanceToWall(PositionT position) => 1.0;

    public void Dispose() { }
}

internal sealed record AccessPoint(double X, double Z, double Y)
{
    public PositionT Native() => new()
    {
        X = CheckedFloat(X, "x"),
        Y = CheckedFloat(Y, "y"),
        Z = CheckedFloat(Z, "z"),
    };

    private static float CheckedFloat(double value, string name)
    {
        if (!double.IsFinite(value) || value < -float.MaxValue || value > float.MaxValue)
        {
            throw new InvalidDataException($"Coordinate {name} is outside finite float range.");
        }
        return (float)value;
    }
}

internal sealed record ProofRequest(
    int Schema,
    string Protocol,
    string RequestId,
    int Zone,
    string MeshRelativePath,
    string MeshSha256,
    string FfxiNavRelativePath,
    string FfxiNavSha256,
    string PolicyRevision,
    string PolicySha256,
    IReadOnlyDictionary<string, double> Thresholds,
    AccessPoint Start,
    AccessPoint End,
    string ExpectedLoadedDllPath,
    string ExpectedLoadedMeshPath,
    string CanonicalDllPath,
    string CanonicalMeshPath
);

internal static class Program
{
    private const string Protocol = "accessxi-navprobe-jsonl-v2";
    private const int Schema = 2;
    private const int HardWaypointCeiling = 1_000_000;
    private static readonly string[] RequestFields =
    {
        "schema", "protocol", "op", "request_id", "zone", "mesh_relative_path",
        "mesh_sha256", "ffxinav_relative_path", "ffxinav_sha256", "policy_revision",
        "policy_sha256", "thresholds", "start", "end", "expected_loaded_dll_path",
        "expected_loaded_mesh_path",
    };
    private static readonly string[] ThresholdFields =
    {
        "endpoint_epsilon_yalms", "minimum_endpoint_clearance_yalms",
        "minimum_waypoint_clearance_yalms", "maximum_segment_length_yalms",
        "maximum_waypoint_count", "transition_corridor_radius_yalms",
    };
    private static readonly string[] PointFields = { "x", "z", "y" };

    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--proof-native-self-test")
        {
            return RunSelfTest();
        }
        if (args.Length == 3 && args[0] == "--proof-jsonl" && args[1] == "--third-party-root")
        {
            return RunProofWorker(args[2]);
        }
        return RunDiagnostic(args);
    }

    private static int RunProofWorker(string rootArgument)
    {
        var totals = new NativeCallCounts();
        try
        {
            var root = CanonicalExistingDirectory(rootArgument, "third-party root");
            var input = Console.In.ReadToEnd();
            var lines = input.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
            if (lines.Length > 0 && lines[^1].Length == 0)
            {
                lines = lines[..^1];
            }
            if (lines.Length == 0 || lines.Any(string.IsNullOrWhiteSpace))
            {
                throw new InvalidDataException("Proof JSONL is empty or contains a blank line.");
            }

            var requests = lines.Select(line => ParseRequest(line, root)).ToArray();
            if (requests.Select(row => row.RequestId).Distinct(StringComparer.Ordinal).Count() != requests.Length)
            {
                throw new InvalidDataException("Duplicate request_id in proof batch.");
            }
            var first = requests[0];
            foreach (var request in requests)
            {
                if (!SamePath(request.CanonicalDllPath, first.CanonicalDllPath)
                    || !SamePath(request.CanonicalMeshPath, first.CanonicalMeshPath)
                    || request.FfxiNavSha256 != first.FfxiNavSha256
                    || request.MeshSha256 != first.MeshSha256)
                {
                    throw new InvalidDataException("A proof worker may load exactly one DLL and one mesh.");
                }
            }

            var output = new List<string>();
            using (var dllPinned = new PinnedFile(first.CanonicalDllPath))
            using (var meshPinned = new PinnedFile(first.CanonicalMeshPath))
            {
                var dllBefore = dllPinned.HashCurrent();
                var meshBefore = meshPinned.HashCurrent();
                if (dllBefore != first.FfxiNavSha256 || meshBefore != first.MeshSha256)
                {
                    throw new InvalidDataException("Requested native dependency hash does not match pinned canonical bytes.");
                }
                using (var native = new ExactNative(first.CanonicalDllPath))
                {
                    native.LoadMesh(first.CanonicalMeshPath);
                    RequireUnchanged(dllPinned, meshPinned, dllBefore, meshBefore);
                    foreach (var request in requests)
                    {
                        var response = ProbeOne(
                            native,
                            request,
                            dllPinned.HashCurrent,
                            meshPinned.HashCurrent,
                            dllBefore,
                            meshBefore,
                            totals
                        );
                        RequireUnchanged(dllPinned, meshPinned, dllBefore, meshBefore);
                        output.Add(JsonSerializer.Serialize(response));
                    }
                    RequireUnchanged(dllPinned, meshPinned, dllBefore, meshBefore);
                }
                RequireUnchanged(dllPinned, meshPinned, dllBefore, meshBefore);
            }
            foreach (var line in output)
            {
                Console.Out.WriteLine(line);
            }
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"proof worker error: {error.Message}");
            Console.Error.WriteLine($"native_calls={totals}");
            return 2;
        }
    }

    private static Dictionary<string, object?> ProbeOne(
        IProofNative native,
        ProofRequest request,
        Func<string> dllHashCurrent,
        Func<string> meshHashCurrent,
        string dllBefore,
        string meshBefore,
        NativeCallCounts totals
    )
    {
        var start = request.Start.Native();
        var end = request.End.Native();
        var startValid = native.IsValid(start);
        var endValid = native.IsValid(end);
        var calls = new NativeCallCounts();
        var copied = new List<PositionT>();
        string status;
        if (!startValid)
        {
            status = "start-invalid";
        }
        else if (!endValid)
        {
            status = "end-invalid";
        }
        else
        {
            native.FindPath(start, end);
            calls.FindPath++;
            totals.FindPath++;
            var policyMaximum = checked((int)request.Thresholds["maximum_waypoint_count"]);
            var maximum = Math.Min(policyMaximum, HardWaypointCeiling);
            copied.AddRange(native.CopyWayPointsImmediately(maximum));
            calls.GetWayPoints++;
            totals.GetWayPoints++;
            status = copied.Count >= 2 ? "exact-path" : "no-exact-path";
        }

        var waypointRows = new List<Dictionary<string, object?>>();
        foreach (var point in copied)
        {
            waypointRows.Add(new Dictionary<string, object?>
            {
                ["x"] = (double)point.X,
                ["z"] = (double)point.Z,
                ["y"] = (double)point.Y,
                ["clearance"] = SafeClearance(native.DistanceToWall(point)),
            });
        }
        var startClearance = SafeClearance(native.DistanceToWall(start));
        var endClearance = SafeClearance(native.DistanceToWall(end));
        var minimumClearance = waypointRows.Count == 0
            ? 0.0
            : waypointRows.Min(row => (double)row["clearance"]!);
        var firstError = copied.Count == 0 ? 0.0 : Distance(start, copied[0]);
        var lastError = copied.Count == 0 ? 0.0 : Distance(end, copied[^1]);
        var pathLength = 0.0;
        for (var index = 1; index < copied.Count; index++)
        {
            pathLength += Distance(copied[index - 1], copied[index]);
        }
        var dllAfter = dllHashCurrent();
        var meshAfter = meshHashCurrent();
        return new Dictionary<string, object?>
        {
            ["schema"] = request.Schema,
            ["protocol"] = request.Protocol,
            ["request_id"] = request.RequestId,
            ["status"] = status,
            ["start_valid"] = startValid,
            ["end_valid"] = endValid,
            ["fallback_used"] = false,
            ["waypoint_count"] = copied.Count,
            ["waypoints"] = waypointRows,
            ["first_endpoint_error"] = firstError,
            ["last_endpoint_error"] = lastError,
            ["start_clearance"] = startClearance,
            ["end_clearance"] = endClearance,
            ["minimum_waypoint_clearance"] = minimumClearance,
            ["path_length"] = pathLength,
            ["mesh_relative_path"] = request.MeshRelativePath,
            ["mesh_sha256"] = request.MeshSha256,
            ["mesh_sha256_before"] = meshBefore,
            ["mesh_sha256_after"] = meshAfter,
            ["ffxinav_relative_path"] = request.FfxiNavRelativePath,
            ["ffxinav_sha256"] = request.FfxiNavSha256,
            ["ffxinav_sha256_before"] = dllBefore,
            ["ffxinav_sha256_after"] = dllAfter,
            ["loaded_dll_path"] = request.CanonicalDllPath,
            ["loaded_mesh_path"] = request.CanonicalMeshPath,
            ["native_calls"] = calls.JsonValue(),
        };
    }

    private static ProofRequest ParseRequest(string line, string root)
    {
        using var document = JsonDocument.Parse(
            line,
            new JsonDocumentOptions { AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow }
        );
        RejectDuplicateProperties(document.RootElement);
        var row = document.RootElement;
        RequireObjectFields(row, RequestFields, "request");
        var schema = RequireInteger(row, "schema");
        if (schema != Schema)
        {
            throw new InvalidDataException("Unsupported proof schema.");
        }
        var protocol = RequireString(row, "protocol");
        if (protocol != Protocol)
        {
            throw new InvalidDataException("Unsupported proof protocol.");
        }
        if (RequireString(row, "op") != "FindPath")
        {
            throw new InvalidDataException("Proof mode accepts only FindPath.");
        }
        var requestId = RequireString(row, "request_id");
        var zone = RequireInteger(row, "zone");
        if (zone < 0)
        {
            throw new InvalidDataException("Zone must be nonnegative.");
        }
        var meshRelative = CanonicalRelative(RequireString(row, "mesh_relative_path"), "mesh path");
        var dllRelative = CanonicalRelative(RequireString(row, "ffxinav_relative_path"), "DLL path");
        if (dllRelative != "FFXI-NavMesh-Builder/FFXINAV.dll")
        {
            throw new InvalidDataException("Unexpected FFXINAV relative path.");
        }
        var meshHash = RequireSha256(row, "mesh_sha256");
        var dllHash = RequireSha256(row, "ffxinav_sha256");
        var policyRevision = RequireString(row, "policy_revision");
        var policyHash = RequireSha256(row, "policy_sha256");
        var thresholds = ParseThresholds(row.GetProperty("thresholds"));
        var start = ParsePoint(row.GetProperty("start"), "start");
        var end = ParsePoint(row.GetProperty("end"), "end");
        var dllPath = ResolveContainedExistingFile(root, dllRelative, "FFXINAV DLL");
        var meshPath = ResolveContainedExistingFile(root, meshRelative, "zone mesh");
        var expectedDll = CanonicalExpectedPath(RequireString(row, "expected_loaded_dll_path"));
        var expectedMesh = CanonicalExpectedPath(RequireString(row, "expected_loaded_mesh_path"));
        if (!SamePath(expectedDll, dllPath) || !SamePath(expectedMesh, meshPath))
        {
            throw new InvalidDataException("Expected loaded dependency path mismatch.");
        }
        return new ProofRequest(
            schema,
            protocol,
            requestId,
            zone,
            meshRelative,
            meshHash,
            dllRelative,
            dllHash,
            policyRevision,
            policyHash,
            thresholds,
            start,
            end,
            expectedDll,
            expectedMesh,
            dllPath,
            meshPath
        );
    }

    private static IReadOnlyDictionary<string, double> ParseThresholds(JsonElement value)
    {
        RequireObjectFields(value, ThresholdFields, "thresholds");
        var result = new Dictionary<string, double>(StringComparer.Ordinal);
        foreach (var field in ThresholdFields)
        {
            var number = RequireNumber(value, field);
            if (number <= 0)
            {
                throw new InvalidDataException($"Threshold {field} must be positive.");
            }
            if (field == "maximum_waypoint_count"
                && (number != Math.Truncate(number) || number < 2 || number > HardWaypointCeiling))
            {
                throw new InvalidDataException("maximum_waypoint_count is invalid.");
            }
            result[field] = number;
        }
        return result;
    }

    private static AccessPoint ParsePoint(JsonElement value, string label)
    {
        RequireObjectFields(value, PointFields, label);
        return new AccessPoint(
            RequireNumber(value, "x"),
            RequireNumber(value, "z"),
            RequireNumber(value, "y")
        );
    }

    private static void RejectDuplicateProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name))
                {
                    throw new InvalidDataException($"Duplicate JSON property {property.Name}.");
                }
                RejectDuplicateProperties(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in value.EnumerateArray())
            {
                RejectDuplicateProperties(item);
            }
        }
    }

    private static void RequireObjectFields(JsonElement value, IEnumerable<string> expected, string label)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidDataException($"{label} must be an object.");
        }
        var actual = value.EnumerateObject().Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal).ToArray();
        var required = expected.OrderBy(name => name, StringComparer.Ordinal).ToArray();
        if (!actual.SequenceEqual(required, StringComparer.Ordinal))
        {
            throw new InvalidDataException($"{label} field set mismatch.");
        }
    }

    private static string RequireString(JsonElement row, string name)
    {
        var value = row.GetProperty(name);
        if (value.ValueKind != JsonValueKind.String)
        {
            throw new InvalidDataException($"{name} must be a string.");
        }
        var result = value.GetString() ?? "";
        if (result.Length == 0 || result.Any(character => char.IsControl(character)))
        {
            throw new InvalidDataException($"{name} must be a nonempty control-free string.");
        }
        return result;
    }

    private static int RequireInteger(JsonElement row, string name)
    {
        var value = row.GetProperty(name);
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var result))
        {
            throw new InvalidDataException($"{name} must be an integer.");
        }
        return result;
    }

    private static double RequireNumber(JsonElement row, string name)
    {
        var value = row.GetProperty(name);
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetDouble(out var result) || !double.IsFinite(result))
        {
            throw new InvalidDataException($"{name} must be finite numeric data.");
        }
        return result;
    }

    private static string RequireSha256(JsonElement row, string name)
    {
        var value = RequireString(row, name);
        if (value.Length != 64 || value.Any(character => !(character is >= '0' and <= '9' or >= 'a' and <= 'f')))
        {
            throw new InvalidDataException($"{name} is not canonical SHA-256 text.");
        }
        return value;
    }

    private static string CanonicalRelative(string value, string label)
    {
        if (value.Contains('\\') || value.Contains(':') || Path.IsPathRooted(value))
        {
            throw new InvalidDataException($"{label} must be a canonical relative path.");
        }
        var parts = value.Split('/');
        if (parts.Length == 0 || parts.Any(part => part.Length == 0 || part is "." or ".."))
        {
            throw new InvalidDataException($"{label} contains a noncanonical path segment.");
        }
        return string.Join('/', parts);
    }

    private static string CanonicalExistingDirectory(string value, string label)
    {
        if (string.IsNullOrWhiteSpace(value) || !Path.IsPathFullyQualified(value))
        {
            throw new InvalidDataException($"{label} must be an absolute path.");
        }
        var full = Path.GetFullPath(value);
        if (!Directory.Exists(full))
        {
            throw new InvalidDataException($"{label} does not exist: {full}");
        }
        RejectReparsePath(full, label);
        return full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static void RejectReparsePath(string fullPath, string label)
    {
        var root = Path.GetPathRoot(fullPath)
            ?? throw new InvalidDataException($"{label} has no filesystem root.");
        var current = root;
        var remainder = fullPath[root.Length..];
        foreach (var part in remainder.Split(
            new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar },
            StringSplitOptions.RemoveEmptyEntries
        ))
        {
            current = Path.Combine(current, part);
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
            {
                throw new InvalidDataException($"{label} contains a reparse-point alias: {current}");
            }
        }
    }

    private static string ResolveContainedExistingFile(string root, string relative, string label)
    {
        var current = root;
        foreach (var part in relative.Split('/'))
        {
            var next = Path.Combine(current, part);
            if (!File.Exists(next) && !Directory.Exists(next))
            {
                throw new InvalidDataException($"{label} does not exist: {next}");
            }
            var attributes = File.GetAttributes(next);
            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                FileSystemInfo info = Directory.Exists(next)
                    ? new DirectoryInfo(next)
                    : new FileInfo(next);
                var target = info.ResolveLinkTarget(true)
                    ?? throw new InvalidDataException($"{label} has an unresolved reparse point.");
                next = target.FullName;
            }
            current = Path.GetFullPath(next);
            if (!IsContained(root, current))
            {
                throw new InvalidDataException($"{label} escapes the third-party root.");
            }
        }
        if (!File.Exists(current))
        {
            throw new InvalidDataException($"{label} is not a file.");
        }
        return current;
    }

    private static bool IsContained(string root, string child)
    {
        var relative = Path.GetRelativePath(root, child);
        return relative != ".."
            && !relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal)
            && !Path.IsPathRooted(relative);
    }

    private static string CanonicalExpectedPath(string value)
    {
        if (!Path.IsPathFullyQualified(value))
        {
            throw new InvalidDataException("Expected loaded path must be absolute.");
        }
        return Path.GetFullPath(value);
    }

    private static bool SamePath(string first, string second) =>
        string.Equals(Path.GetFullPath(first), Path.GetFullPath(second), StringComparison.OrdinalIgnoreCase);

    private static void RequireUnchanged(
        PinnedFile dllPinned,
        PinnedFile meshPinned,
        string dllHash,
        string meshHash
    )
    {
        if (dllPinned.HashCurrent() != dllHash || meshPinned.HashCurrent() != meshHash)
        {
            throw new InvalidDataException("Native dependency bytes changed during proof.");
        }
    }

    private static void RequireFinite(PositionT point)
    {
        if (!float.IsFinite(point.X) || !float.IsFinite(point.Y) || !float.IsFinite(point.Z))
        {
            throw new InvalidDataException("Native path returned a non-finite waypoint.");
        }
    }

    private static double SafeClearance(double value) =>
        double.IsFinite(value) && value >= 0 ? value : 0.0;

    private static double Distance(PositionT first, PositionT second)
    {
        var dx = (double)first.X - second.X;
        var dy = (double)first.Y - second.Y;
        var dz = (double)first.Z - second.Z;
        return Math.Sqrt(dx * dx + dy * dy + dz * dz);
    }

    private static int RunSelfTest()
    {
        var starts = new[]
        {
            new AccessPoint(11, 22, -33),
            new AccessPoint(1, 2, 3),
            new AccessPoint(7, 8, 9),
        };
        var ends = new[]
        {
            new AccessPoint(44, 55, -66),
            new AccessPoint(4, 5, 6),
            new AccessPoint(10, 11, 12),
        };
        var dllHash = new string('a', 64);
        var meshHash = new string('b', 64);
        var totals = new NativeCallCounts();
        using var spy = new SpyProofNative(2, 0, 2);
        var responses = new List<Dictionary<string, object?>>();
        for (var index = 0; index < starts.Length; index++)
        {
            var request = new ProofRequest(
                Schema,
                Protocol,
                $"self-{index}",
                1,
                "xiNavmeshes/Self.nav",
                meshHash,
                "FFXI-NavMesh-Builder/FFXINAV.dll",
                dllHash,
                "self-test-policy",
                new string('c', 64),
                new Dictionary<string, double> { ["maximum_waypoint_count"] = 8 },
                starts[index],
                ends[index],
                "C:/self/FFXINAV.dll",
                "C:/self/Self.nav",
                "C:/self/FFXINAV.dll",
                "C:/self/Self.nav"
            );
            responses.Add(
                ProbeOne(spy, request, () => dllHash, () => meshHash, dllHash, meshHash, totals)
            );
            spy.Order.Add("next-request");
        }
        var report = new Dictionary<string, object?>
        {
            ["statuses"] = responses.Select(row => row["status"]).ToArray(),
            ["waypoint_counts"] = responses.Select(row => row["waypoint_count"]).ToArray(),
            ["calls"] = totals.JsonValue(),
            ["native_starts"] = spy.Starts.Select(point => new Dictionary<string, float>
            {
                ["X"] = point.X, ["Y"] = point.Y, ["Z"] = point.Z,
            }).ToArray(),
            ["native_ends"] = spy.Ends.Select(point => new Dictionary<string, float>
            {
                ["X"] = point.X, ["Y"] = point.Y, ["Z"] = point.Z,
            }).ToArray(),
            ["copy_order"] = spy.Order,
            ["loaded_exports"] = spy.LoadedExports,
        };
        Console.WriteLine(JsonSerializer.Serialize(report));
        return 0;
    }

    private static int RunDiagnostic(string[] args)
    {
        if (args.Length != 7)
        {
            Console.Error.WriteLine(
                "usage: navprobe <mesh.nav> <sx> <sy> <sz> <ex> <ey> <ez>\n"
                + "       navprobe --proof-jsonl --third-party-root <absolute-root>"
            );
            return 2;
        }
        try
        {
            var mesh = Path.GetFullPath(args[0]);
            var dll = Path.Combine(AppContext.BaseDirectory, "FFXINAV.dll");
            var start = new PositionT
            {
                X = float.Parse(args[1], CultureInfo.InvariantCulture),
                Y = float.Parse(args[2], CultureInfo.InvariantCulture),
                Z = float.Parse(args[3], CultureInfo.InvariantCulture),
            };
            var end = new PositionT
            {
                X = float.Parse(args[4], CultureInfo.InvariantCulture),
                Y = float.Parse(args[5], CultureInfo.InvariantCulture),
                Z = float.Parse(args[6], CultureInfo.InvariantCulture),
            };
            using var native = new ExactNative(dll);
            native.LoadMesh(mesh);
            Console.WriteLine($"mesh\t{mesh}");
            Console.WriteLine($"start_valid\t{native.IsValid(start)}\twall\t{native.DistanceToWall(start):0.###}");
            Console.WriteLine($"end_valid\t{native.IsValid(end)}\twall\t{native.DistanceToWall(end):0.###}");
            native.FindPath(start, end);
            var copied = native.CopyWayPointsImmediately(HardWaypointCeiling);
            if (copied.Length <= 0)
            {
                native.FindClosestPathDiagnostic(start, end);
                copied = native.CopyWayPointsImmediately(HardWaypointCeiling);
            }
            var count = copied.Length;
            Console.WriteLine($"waypoints\t{count}");
            for (var index = 0; index < count; index++)
            {
                var point = copied[index];
                Console.WriteLine($"{index + 1}\t{point.X:0.###}\t{point.Y:0.###}\t{point.Z:0.###}");
            }
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error.Message);
            return 3;
        }
    }
}

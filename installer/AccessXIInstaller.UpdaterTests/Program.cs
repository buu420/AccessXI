using System.IO.Compression;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using AccessXIInstaller;

if (args.Length == 2 && string.Equals(args[0], "--validate-package", StringComparison.Ordinal))
{
    ReleasePayloadUpdater.ValidatePackageArchive(args[1]);
    Console.WriteLine("ok: AccessXI package contains every required file and only safe ZIP paths.");
    return 0;
}

if (args.Length == 2 && string.Equals(args[0], "--live-current", StringComparison.Ordinal))
{
    return await RunLiveCurrentReleaseProbeAsync(args[1]);
}

var tests = new (string Name, Func<Task> Run)[]
{
    ("matching embedded digest avoids download", MatchingEmbeddedDigestAvoidsDownloadAsync),
    ("different verified payload is selected", DifferentVerifiedPayloadIsSelectedAsync),
    ("offline check falls back explicitly", OfflineCheckFallsBackExplicitlyAsync),
    ("digest mismatch is rejected", DigestMismatchIsRejectedAsync),
    ("non-GitHub download URL is rejected", NonGitHubDownloadUrlIsRejectedAsync),
    ("traversal ZIP is rejected", TraversalZipIsRejectedAsync),
    ("point-of-use verification rejects changed payload", PointOfUseVerificationRejectsChangedPayloadAsync),
    ("incomplete critical payload is rejected", IncompleteCriticalPayloadIsRejectedAsync),
};

var failures = new List<string>();
foreach (var test in tests)
{
    try
    {
        await test.Run();
        Console.WriteLine("PASS: " + test.Name);
    }
    catch (Exception ex)
    {
        failures.Add(test.Name + ": " + ex.Message);
        Console.Error.WriteLine("FAIL: " + test.Name + Environment.NewLine + ex);
    }
}

if (failures.Count > 0)
{
    Console.Error.WriteLine($"{failures.Count} updater test(s) failed.");
    return 1;
}

Console.WriteLine($"ok: {tests.Length} AccessXI installer updater behavior tests passed.");
return 0;

static async Task MatchingEmbeddedDigestAvoidsDownloadAsync()
{
    var embedded = BuildValidPackage("embedded-current");
    var downloadCalls = 0;
    using var client = CreateClient(request =>
    {
        if (IsLatestReleaseRequest(request))
        {
            return JsonResponse(BuildReleaseJson(embedded));
        }

        downloadCalls++;
        return BytesResponse(embedded);
    });
    var tempRoot = NewTempRoot();
    try
    {
        var updater = new ReleasePayloadUpdater(client);
        using var result = await updater.SelectPayloadAsync(() => new MemoryStream(embedded, writable: false), tempRoot);

        Equal(PayloadSelectionKind.EmbeddedCurrent, result.Kind, "Expected the matching embedded payload to be current.");
        Equal(0, downloadCalls, "A current embedded payload must not be downloaded again.");
        True(result.DownloadedZipPath is null, "Current embedded selection must not return a downloaded path.");
        Contains(result.Message, "already current", "Current result should be clear to the user.");
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }
}

static async Task DifferentVerifiedPayloadIsSelectedAsync()
{
    var embedded = BuildValidPackage("embedded-old");
    var update = BuildValidPackage("downloaded-new");
    using var client = CreateClient(request =>
        IsLatestReleaseRequest(request)
            ? JsonResponse(BuildReleaseJson(update, tag: "v2099.01.02.3"))
            : BytesResponse(update));
    var tempRoot = NewTempRoot();
    string? downloadedPath;
    using (var result = await new ReleasePayloadUpdater(client).SelectPayloadAsync(() => new MemoryStream(embedded, writable: false), tempRoot))
    {
        Equal(PayloadSelectionKind.DownloadedUpdate, result.Kind, "Expected a verified changed payload to be selected.");
        Equal("v2099.01.02.3", result.ReleaseTag, "Release tag should be preserved for status text.");
        downloadedPath = result.DownloadedZipPath;
        True(downloadedPath is not null && File.Exists(downloadedPath), "Verified update ZIP should exist until the result is disposed.");
        SequenceEqual(update, await File.ReadAllBytesAsync(downloadedPath!), "Selected ZIP bytes should match the verified download.");
        Contains(result.Message, "Verified AccessXI update", "Verified download should be clearly reported.");
    }

    True(downloadedPath is not null && !File.Exists(downloadedPath), "Disposing the result should clean the update ZIP.");
    DeleteDirectory(tempRoot);
}

static async Task OfflineCheckFallsBackExplicitlyAsync()
{
    var embedded = BuildValidPackage("offline-embedded");
    using var client = CreateClient(_ => throw new HttpRequestException("network unavailable"));
    var tempRoot = NewTempRoot();
    try
    {
        using var result = await new ReleasePayloadUpdater(client).SelectPayloadAsync(() => new MemoryStream(embedded, writable: false), tempRoot);
        Equal(PayloadSelectionKind.EmbeddedFallback, result.Kind, "Offline update check should use the complete embedded payload.");
        Contains(result.Message, "using the embedded AccessXI package", "Offline fallback must be disclosed.");
        Contains(result.Message, "network unavailable", "Fallback should preserve a concise failure reason.");
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }
}

static async Task DigestMismatchIsRejectedAsync()
{
    var embedded = BuildValidPackage("digest-embedded");
    var describedUpdate = BuildValidPackage("described-update");
    var wrongDownload = BuildValidPackage("wrong-download");
    using var client = CreateClient(request =>
        IsLatestReleaseRequest(request)
            ? JsonResponse(BuildReleaseJson(describedUpdate, advertisedSize: wrongDownload.LongLength))
            : BytesResponse(wrongDownload));
    var tempRoot = NewTempRoot();
    try
    {
        using var result = await new ReleasePayloadUpdater(client).SelectPayloadAsync(() => new MemoryStream(embedded, writable: false), tempRoot);
        Equal(PayloadSelectionKind.EmbeddedFallback, result.Kind, "Digest mismatch must fall back instead of installing the download.");
        Contains(result.Message, "SHA-256", "Digest mismatch should be identified in the warning.");
        Equal(0, CountFiles(tempRoot), "Rejected downloads and partial files should be removed.");
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }
}

static async Task NonGitHubDownloadUrlIsRejectedAsync()
{
    var embedded = BuildValidPackage("host-embedded");
    var update = BuildValidPackage("host-update");
    var downloadCalls = 0;
    using var client = CreateClient(request =>
    {
        if (IsLatestReleaseRequest(request))
        {
            return JsonResponse(BuildReleaseJson(update, downloadUrl: "https://example.com/not-accessxi.zip"));
        }

        downloadCalls++;
        return BytesResponse(update);
    });
    var tempRoot = NewTempRoot();
    try
    {
        using var result = await new ReleasePayloadUpdater(client).SelectPayloadAsync(() => new MemoryStream(embedded, writable: false), tempRoot);
        Equal(PayloadSelectionKind.EmbeddedFallback, result.Kind, "An arbitrary download host must be rejected.");
        Equal(0, downloadCalls, "Rejected URLs must never be requested.");
        Contains(result.Message, "official AccessXI GitHub release path", "URL rejection should explain the trust boundary.");
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }
}

static async Task TraversalZipIsRejectedAsync()
{
    var embedded = BuildValidPackage("traversal-embedded");
    var unsafeUpdate = BuildValidPackage("unsafe-update", "../escape.txt");
    using var client = CreateClient(request =>
        IsLatestReleaseRequest(request)
            ? JsonResponse(BuildReleaseJson(unsafeUpdate))
            : BytesResponse(unsafeUpdate));
    var tempRoot = NewTempRoot();
    try
    {
        using var result = await new ReleasePayloadUpdater(client).SelectPayloadAsync(() => new MemoryStream(embedded, writable: false), tempRoot);
        Equal(PayloadSelectionKind.EmbeddedFallback, result.Kind, "A traversal ZIP must never be selected.");
        Contains(result.Message, "unsafe path", "Traversal rejection should identify unsafe ZIP structure.");
        Equal(0, CountFiles(tempRoot), "Rejected unsafe package should be deleted.");
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }
}

static Task IncompleteCriticalPayloadIsRejectedAsync()
{
    var incomplete = BuildIncompletePackage("missing-native-bridge");
    var tempRoot = NewTempRoot();
    var packagePath = Path.Combine(tempRoot, ReleasePayloadUpdater.ReleaseAssetName);
    try
    {
        File.WriteAllBytes(packagePath, incomplete);
        var rejected = false;
        try
        {
            ReleasePayloadUpdater.ValidatePackageArchive(packagePath);
        }
        catch (InvalidDataException ex)
        {
            rejected = ex.Message.Contains("missing required file", StringComparison.OrdinalIgnoreCase);
        }

        True(rejected, "A package missing the native bridge, Prism, launch profile, or prerequisites must be rejected before installation.");
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }

    return Task.CompletedTask;
}

static Task PointOfUseVerificationRejectsChangedPayloadAsync()
{
    var original = BuildValidPackage("point-of-use-original");
    var changed = BuildValidPackage("point-of-use-changed");
    var expectedDigest = Convert.ToHexString(SHA256.HashData(original)).ToLowerInvariant();
    var tempRoot = NewTempRoot();
    var packagePath = Path.Combine(tempRoot, ReleasePayloadUpdater.ReleaseAssetName);
    try
    {
        File.WriteAllBytes(packagePath, original);
        ReleasePayloadUpdater.VerifyPackageFile(packagePath, expectedDigest);
        File.WriteAllBytes(packagePath, changed);

        var rejected = false;
        try
        {
            ReleasePayloadUpdater.VerifyPackageFile(packagePath, expectedDigest);
        }
        catch (InvalidDataException ex)
        {
            rejected = ex.Message.Contains("changed after verification", StringComparison.OrdinalIgnoreCase);
        }

        True(rejected, "A payload changed after download verification must be rejected immediately before extraction.");
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }

    return Task.CompletedTask;
}

static async Task<int> RunLiveCurrentReleaseProbeAsync(string embeddedPackagePath)
{
    if (!File.Exists(embeddedPackagePath))
    {
        Console.Error.WriteLine("Live probe package was not found: " + embeddedPackagePath);
        return 2;
    }

    using var handler = new HttpClientHandler
    {
        AllowAutoRedirect = true,
        MaxAutomaticRedirections = 5,
        CheckCertificateRevocationList = true,
    };
    using var client = new HttpClient(handler)
    {
        Timeout = TimeSpan.FromMinutes(45),
    };
    var tempRoot = NewTempRoot();
    try
    {
        var progress = new Progress<PayloadUpdateProgress>(item => Console.WriteLine($"{item.Percent}: {item.Message}"));
        using var result = await new ReleasePayloadUpdater(client).SelectPayloadAsync(
            () => new FileStream(embeddedPackagePath, FileMode.Open, FileAccess.Read, FileShare.Read),
            tempRoot,
            progress);
        Console.WriteLine(result.Message);
        if (result.Kind != PayloadSelectionKind.EmbeddedCurrent)
        {
            Console.Error.WriteLine("Expected the current public release ZIP to match GitHub metadata; got " + result.Kind + ".");
            return 1;
        }

        return 0;
    }
    finally
    {
        DeleteDirectory(tempRoot);
    }
}

static HttpClient CreateClient(Func<HttpRequestMessage, HttpResponseMessage> responder)
{
    return new HttpClient(new DelegateHandler(responder), disposeHandler: true)
    {
        Timeout = TimeSpan.FromSeconds(10),
    };
}

static bool IsLatestReleaseRequest(HttpRequestMessage request)
{
    return request.RequestUri?.AbsoluteUri == ReleasePayloadUpdater.LatestReleaseApiUrl;
}

static string BuildReleaseJson(byte[] asset, string tag = "v2099.01.01.1", string? downloadUrl = null, long? advertisedSize = null)
{
    return JsonSerializer.Serialize(new
    {
        tag_name = tag,
        draft = false,
        prerelease = false,
        assets = new[]
        {
            new
            {
                name = ReleasePayloadUpdater.ReleaseAssetName,
                state = "uploaded",
                size = advertisedSize ?? asset.LongLength,
                digest = "sha256:" + Convert.ToHexString(SHA256.HashData(asset)).ToLowerInvariant(),
                browser_download_url = downloadUrl ?? "https://github.com/buu420/AccessXI/releases/download/" + tag + "/" + ReleasePayloadUpdater.ReleaseAssetName,
            },
        },
    });
}

static byte[] BuildIncompletePackage(string marker)
{
    using var stream = new MemoryStream();
    using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
    {
        AddEntry(archive, "install_accessxi.ps1", "# installer " + marker);
        AddEntry(archive, "legacy_accessxi_cleanup.ps1", "# cleanup");
        AddEntry(archive, "manifest.json", "{}");
        AddEntry(archive, "setup-guide.md", "# guide");
        AddEntry(archive, "payload/Ashita/addons/accessxi_reader/accessxi_reader.lua", "-- reader");
        AddEntry(archive, "payload/PlayOnlineNative/AccessXI.PolNative.asi", marker);
    }

    return stream.ToArray();
}

static byte[] BuildValidPackage(string marker, string? extraEntry = null)
{
    using var stream = new MemoryStream();
    using (var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: true))
    {
        AddEntry(archive, "install_accessxi.ps1", "# installer " + marker);
        AddEntry(archive, "legacy_accessxi_cleanup.ps1", "# cleanup");
        AddEntry(archive, "manifest.json", "{\"marker\":\"" + marker + "\"}");
        AddEntry(archive, "setup-guide.md", "# guide");
        AddEntry(archive, "third-party-notices/Ultimate-ASI-Loader-LICENSE.txt", "license");
        AddEntry(archive, "third-party-notices/BG-Wiki-objective-guides-CC-BY-NC-SA-3.0.txt", "license");
        AddEntry(archive, "third-party-notices/FFXIclopedia-objective-guides-CC-BY-SA-3.0.txt", "license");
        AddEntry(archive, "payload/Ashita/Ashita-cli.exe", marker);
        AddEntry(archive, "payload/Ashita/AccessXI.cmd", marker);
        AddEntry(archive, "payload/Ashita/config/boot/accessxi-retail.ini", marker);
        AddEntry(archive, "payload/Ashita/config/boot/AccessXI Retail.xml", marker);
        AddEntry(archive, "payload/Ashita/scripts/default.txt", marker);
        AddEntry(archive, "payload/Ashita/addons/accessxi_reader/accessxi_reader.lua", "-- " + marker);
        AddEntry(archive, "payload/Ashita/addons/accessxi_reader/modules/mission_quest_guide_index.lua", "return {}");
        AddEntry(archive, "payload/Ashita/addons/accessxi_reader/modules/mission_quest_bg_mission_bastok.lua", "return {}");
        AddEntry(archive, "payload/Ashita/addons/accessxi_reader/modules/mission_quest_ffxiclopedia_mission_bastok.lua", "return {}");
        AddEntry(archive, "payload/Ashita/addons/accessxi_reader/data/mission-quest-guides/coverage.json", "{}");
        AddEntry(archive, "payload/Ashita/addons/accessxi_reader/data/mission-quest-guides/source-snapshot.json", "{}");
        AddEntry(archive, "payload/PlayOnlineNative/ddraw.dll", marker);
        AddEntry(archive, "payload/PlayOnlineNative/AccessXI.PolNative.asi", marker);
        AddEntry(archive, "payload/PlayOnlineNative/AccessXI.PolNative/accessxi_pol_native.dll", marker);
        AddEntry(archive, "payload/PlayOnlineNative/AccessXI.PolNative/prism.dll", marker);
        AddEntry(archive, "payload/Prerequisites/vc_redist.x86.exe", marker);
        AddEntry(archive, "payload/Prerequisites/vc_redist.x64.exe", marker);
        if (extraEntry is not null)
        {
            AddEntry(archive, extraEntry, "unsafe");
        }
    }

    return stream.ToArray();
}

static void AddEntry(ZipArchive archive, string name, string content)
{
    var entry = archive.CreateEntry(name, CompressionLevel.NoCompression);
    using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    writer.Write(content);
}

static HttpResponseMessage JsonResponse(string json)
{
    return new HttpResponseMessage(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json"),
    };
}

static HttpResponseMessage BytesResponse(byte[] bytes)
{
    return new HttpResponseMessage(HttpStatusCode.OK)
    {
        Content = new ByteArrayContent(bytes),
    };
}

static string NewTempRoot()
{
    var path = Path.Combine(Path.GetTempPath(), "AccessXIUpdaterTests", Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(path);
    return path;
}

static int CountFiles(string path)
{
    return Directory.Exists(path) ? Directory.GetFiles(path, "*", SearchOption.AllDirectories).Length : 0;
}

static void DeleteDirectory(string path)
{
    if (Directory.Exists(path))
    {
        Directory.Delete(path, recursive: true);
    }
}

static void True(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}

static void Equal<T>(T expected, T actual, string message)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException(message + $" Expected={expected}; Actual={actual}.");
    }
}

static void Contains(string value, string expected, string message)
{
    if (!value.Contains(expected, StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException(message + $" Expected text '{expected}' in '{value}'.");
    }
}

static void SequenceEqual(byte[] expected, byte[] actual, string message)
{
    if (!expected.AsSpan().SequenceEqual(actual))
    {
        throw new InvalidOperationException(message);
    }
}

internal sealed class DelegateHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            return Task.FromResult(responder(request));
        }
        catch (Exception ex)
        {
            return Task.FromException<HttpResponseMessage>(ex);
        }
    }
}

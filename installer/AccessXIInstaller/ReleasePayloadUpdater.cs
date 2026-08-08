using System.IO.Compression;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace AccessXIInstaller;

internal enum PayloadSelectionKind
{
    EmbeddedCurrent,
    DownloadedUpdate,
    EmbeddedFallback,
}

internal sealed record PayloadUpdateProgress(int Percent, string Message);

internal sealed class PayloadUpdateResult : IDisposable
{
    private readonly string? cleanupDirectory;
    private bool disposed;

    internal PayloadUpdateResult(PayloadSelectionKind kind, string message, string releaseTag = "", string? downloadedZipPath = null, string? verifiedSha256Hex = null, string? cleanupDirectory = null)
    {
        Kind = kind;
        Message = message;
        ReleaseTag = releaseTag;
        DownloadedZipPath = downloadedZipPath;
        VerifiedSha256Hex = verifiedSha256Hex;
        this.cleanupDirectory = cleanupDirectory;
    }

    public PayloadSelectionKind Kind { get; }

    public string Message { get; }

    public string ReleaseTag { get; }

    public string? DownloadedZipPath { get; }

    public string? VerifiedSha256Hex { get; }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        disposed = true;
        ReleasePayloadUpdater.TryDeleteDirectory(cleanupDirectory);
    }
}

internal sealed class ReleasePayloadUpdater
{
    public const string LatestReleaseApiUrl = "https://api.github.com/repos/buu420/AccessXI/releases/latest";
    public const string ReleaseAssetName = "AccessXI-Ashita-Installer.zip";

    private const string GitHubApiVersion = "2022-11-28";
    private const string GitHubOwner = "buu420";
    private const string GitHubRepository = "AccessXI";
    private const long MaximumMetadataBytes = 1024 * 1024;
    private const long MaximumAssetBytes = 2L * 1024 * 1024 * 1024;
    private const long MaximumExpandedArchiveBytes = 4L * 1024 * 1024 * 1024;
    private const long MaximumExpandedEntryBytes = 1024L * 1024 * 1024;
    private const int MaximumArchiveEntries = 20_000;

    private static readonly string[] RequiredArchiveEntries =
    [
        "install_accessxi.ps1",
        "legacy_accessxi_cleanup.ps1",
        "manifest.json",
        "setup-guide.md",
        "third-party-notices/Ultimate-ASI-Loader-LICENSE.txt",
        "third-party-notices/BG-Wiki-objective-guides-CC-BY-NC-SA-3.0.txt",
        "third-party-notices/FFXIclopedia-objective-guides-CC-BY-SA-3.0.txt",
        "payload/Ashita/Ashita-cli.exe",
        "payload/Ashita/AccessXI.cmd",
        "payload/Ashita/config/boot/accessxi-retail.ini",
        "payload/Ashita/config/boot/AccessXI Retail.xml",
        "payload/Ashita/scripts/default.txt",
        "payload/Ashita/addons/accessxi_reader/accessxi_reader.lua",
        "payload/Ashita/addons/accessxi_reader/modules/mission_quest_guide_index.lua",
        "payload/Ashita/addons/accessxi_reader/modules/mission_quest_bg_mission_bastok.lua",
        "payload/Ashita/addons/accessxi_reader/modules/mission_quest_ffxiclopedia_mission_bastok.lua",
        "payload/Ashita/addons/accessxi_reader/data/mission-quest-guides/coverage.json",
        "payload/Ashita/addons/accessxi_reader/data/mission-quest-guides/source-snapshot.json",
        "payload/PlayOnlineNative/ddraw.dll",
        "payload/PlayOnlineNative/AccessXI.PolNative.asi",
        "payload/PlayOnlineNative/AccessXI.PolNative/accessxi_pol_native.dll",
        "payload/PlayOnlineNative/AccessXI.PolNative/prism.dll",
        "payload/Prerequisites/vc_redist.x86.exe",
        "payload/Prerequisites/vc_redist.x64.exe",
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly HttpClient httpClient;

    public ReleasePayloadUpdater(HttpClient httpClient)
    {
        this.httpClient = httpClient ?? throw new ArgumentNullException(nameof(httpClient));
    }

    public async Task<PayloadUpdateResult> SelectPayloadAsync(
        Func<Stream> openEmbeddedPayload,
        string tempRoot,
        IProgress<PayloadUpdateProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(openEmbeddedPayload);
        ArgumentException.ThrowIfNullOrWhiteSpace(tempRoot);

        string? cleanupDirectory = null;
        string releaseTag = string.Empty;
        try
        {
            progress?.Report(new(0, "Checking GitHub for AccessXI updates."));
            using var metadataTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            metadataTimeout.CancelAfter(TimeSpan.FromSeconds(20));
            var release = await GetLatestReleaseAsync(metadataTimeout.Token).ConfigureAwait(false);
            releaseTag = release.TagName;

            progress?.Report(new(5, "Comparing the embedded AccessXI package with " + release.TagName + "."));
            string embeddedDigest;
            using (var embeddedPayload = openEmbeddedPayload())
            {
                if (embeddedPayload is null)
                {
                    throw new InvalidDataException("The embedded AccessXI package stream was unavailable.");
                }

                embeddedDigest = await ComputeSha256HexAsync(embeddedPayload, cancellationToken).ConfigureAwait(false);
            }

            if (string.Equals(embeddedDigest, release.Asset.Sha256Hex, StringComparison.OrdinalIgnoreCase))
            {
                progress?.Report(new(100, "The embedded AccessXI package is already current."));
                return new(
                    PayloadSelectionKind.EmbeddedCurrent,
                    "The embedded AccessXI package is already current (" + release.TagName + ").",
                    release.TagName);
            }

            cleanupDirectory = Path.Combine(Path.GetFullPath(tempRoot), Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(cleanupDirectory);
            var partialPath = Path.Combine(cleanupDirectory, ReleaseAssetName + ".partial");
            var finalPath = Path.Combine(cleanupDirectory, ReleaseAssetName);

            progress?.Report(new(10, "Downloading AccessXI update " + release.TagName + "."));
            await DownloadAndVerifyAsync(release.Asset, partialPath, progress, cancellationToken).ConfigureAwait(false);
            File.Move(partialPath, finalPath);

            progress?.Report(new(95, "Checking the downloaded AccessXI package structure."));
            ValidatePackageArchive(finalPath);

            progress?.Report(new(100, "Verified AccessXI update " + release.TagName + "."));
            var selectedDirectory = cleanupDirectory;
            cleanupDirectory = null;
            return new(
                PayloadSelectionKind.DownloadedUpdate,
                "Verified AccessXI update " + release.TagName + ".",
                release.TagName,
                finalPath,
                release.Asset.Sha256Hex,
                selectedDirectory);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            TryDeleteDirectory(cleanupDirectory);
            throw;
        }
        catch (Exception ex) when (IsRecoverableUpdateException(ex))
        {
            TryDeleteDirectory(cleanupDirectory);
            var reason = ConciseFailureReason(ex);
            progress?.Report(new(100, "Update check failed; using the embedded AccessXI package."));
            return new(
                PayloadSelectionKind.EmbeddedFallback,
                "Update check failed; using the embedded AccessXI package. " + reason,
                releaseTag);
        }
    }

    private async Task<ReleaseDescriptor> GetLatestReleaseAsync(CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseApiUrl);
        AddGitHubHeaders(request.Headers);

        using var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is > MaximumMetadataBytes)
        {
            throw new InvalidDataException("GitHub release metadata exceeded the allowed size.");
        }

        await using var responseStream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        var metadata = await ReadLimitedBytesAsync(responseStream, MaximumMetadataBytes, cancellationToken).ConfigureAwait(false);
        var release = JsonSerializer.Deserialize<GitHubRelease>(metadata, JsonOptions)
            ?? throw new InvalidDataException("GitHub returned empty release metadata.");

        if (release.Draft || release.Prerelease)
        {
            throw new InvalidDataException("GitHub's latest release response was not a normal published release.");
        }

        if (string.IsNullOrWhiteSpace(release.TagName))
        {
            throw new InvalidDataException("GitHub's latest AccessXI release did not include a tag.");
        }

        var matchingAssets = (release.Assets ?? [])
            .Where(asset => string.Equals(asset.Name, ReleaseAssetName, StringComparison.Ordinal))
            .ToList();
        if (matchingAssets.Count != 1)
        {
            throw new InvalidDataException("GitHub's latest AccessXI release did not contain exactly one " + ReleaseAssetName + " asset.");
        }

        var asset = matchingAssets[0];
        if (!string.Equals(asset.State, "uploaded", StringComparison.Ordinal))
        {
            throw new InvalidDataException("The AccessXI release package was not in the uploaded state.");
        }

        if (asset.Size <= 0 || asset.Size > MaximumAssetBytes)
        {
            throw new InvalidDataException("The AccessXI release package size was outside the allowed range.");
        }

        var sha256Hex = ParseSha256Digest(asset.Digest);
        var downloadUri = ValidateDownloadUri(asset.BrowserDownloadUrl, release.TagName);
        return new(release.TagName, new(downloadUri, asset.Size, sha256Hex));
    }

    private async Task DownloadAndVerifyAsync(
        ReleaseAsset asset,
        string partialPath,
        IProgress<PayloadUpdateProgress>? progress,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, asset.DownloadUri);
        request.Headers.UserAgent.ParseAdd("AccessXI-Installer/1.0");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/octet-stream"));

        using var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is long contentLength && contentLength != asset.Size)
        {
            throw new InvalidDataException("Downloaded AccessXI package size did not match GitHub release metadata.");
        }

        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        await using var output = new FileStream(
            partialPath,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            128 * 1024,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[128 * 1024];
        long total = 0;
        int read;
        var lastPercent = -1;
        while ((read = await input.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
        {
            total = checked(total + read);
            if (total > asset.Size || total > MaximumAssetBytes)
            {
                throw new InvalidDataException("Downloaded AccessXI package exceeded the expected size.");
            }

            hash.AppendData(buffer, 0, read);
            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);

            var receivedPercent = (int)Math.Clamp(total * 100L / asset.Size, 0, 100);
            var stagePercent = 10 + (receivedPercent * 80 / 100);
            if (stagePercent != lastPercent)
            {
                lastPercent = stagePercent;
                progress?.Report(new(stagePercent, "Downloading AccessXI update: " + receivedPercent + "% of package received."));
            }
        }

        await output.FlushAsync(cancellationToken).ConfigureAwait(false);
        if (total != asset.Size)
        {
            throw new InvalidDataException("Downloaded AccessXI package size did not match GitHub release metadata.");
        }

        var actualDigest = hash.GetHashAndReset();
        var expectedDigest = Convert.FromHexString(asset.Sha256Hex);
        if (!CryptographicOperations.FixedTimeEquals(actualDigest, expectedDigest))
        {
            throw new InvalidDataException("Downloaded AccessXI package SHA-256 did not match GitHub release metadata.");
        }
    }

    internal static void VerifyPackageFile(string path, string expectedSha256Hex)
    {
        if (expectedSha256Hex.Length != 64 || expectedSha256Hex.Any(character => !Uri.IsHexDigit(character)))
        {
            throw new InvalidDataException("The verified AccessXI package SHA-256 was invalid.");
        }

        using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var actualDigest = SHA256.HashData(file);
            var expectedDigest = Convert.FromHexString(expectedSha256Hex);
            if (!CryptographicOperations.FixedTimeEquals(actualDigest, expectedDigest))
            {
                throw new InvalidDataException("The AccessXI package changed after verification and will not be installed.");
            }
        }

        ValidatePackageArchive(path);
    }

    internal static void ValidatePackageArchive(string path)
    {
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        using var archive = new ZipArchive(file, ZipArchiveMode.Read, leaveOpen: false);
        if (archive.Entries.Count == 0 || archive.Entries.Count > MaximumArchiveEntries)
        {
            throw new InvalidDataException("The downloaded AccessXI package contained an invalid number of ZIP entries.");
        }

        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        long expandedBytes = 0;
        foreach (var entry in archive.Entries)
        {
            var normalizedName = NormalizeAndValidateEntryName(entry.FullName);
            if (!names.Add(normalizedName))
            {
                throw new InvalidDataException("The downloaded AccessXI package contained a duplicate ZIP path: " + normalizedName);
            }

            if (entry.Length < 0 || entry.Length > MaximumExpandedEntryBytes)
            {
                throw new InvalidDataException("The downloaded AccessXI package contained an oversized ZIP entry.");
            }

            expandedBytes = checked(expandedBytes + entry.Length);
            if (expandedBytes > MaximumExpandedArchiveBytes)
            {
                throw new InvalidDataException("The downloaded AccessXI package expanded size exceeded the allowed limit.");
            }
        }

        foreach (var requiredEntry in RequiredArchiveEntries)
        {
            if (!names.Contains(requiredEntry))
            {
                throw new InvalidDataException("The downloaded AccessXI package was missing required file: " + requiredEntry);
            }
        }
    }

    private static string NormalizeAndValidateEntryName(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.IndexOf('\0') >= 0)
        {
            throw new InvalidDataException("The downloaded AccessXI package contained an unsafe path.");
        }

        var normalized = name.Replace('\\', '/');
        if (normalized.StartsWith("/", StringComparison.Ordinal) || Path.IsPathRooted(name))
        {
            throw new InvalidDataException("The downloaded AccessXI package contained an unsafe path: " + name);
        }

        var segments = normalized.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0 || segments.Any(segment => segment is "." or ".." || segment.Contains(':')))
        {
            throw new InvalidDataException("The downloaded AccessXI package contained an unsafe path: " + name);
        }

        return string.Join('/', segments) + (normalized.EndsWith("/", StringComparison.Ordinal) ? "/" : string.Empty);
    }

    private static Uri ValidateDownloadUri(string? value, string releaseTag)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(uri.Host, "github.com", StringComparison.OrdinalIgnoreCase) ||
            !string.IsNullOrEmpty(uri.UserInfo) ||
            !string.IsNullOrEmpty(uri.Query) ||
            !string.IsNullOrEmpty(uri.Fragment))
        {
            throw new InvalidDataException("The release package did not use the official AccessXI GitHub release path.");
        }

        var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.UnescapeDataString)
            .ToArray();
        if (segments.Length != 6 ||
            !string.Equals(segments[0], GitHubOwner, StringComparison.Ordinal) ||
            !string.Equals(segments[1], GitHubRepository, StringComparison.Ordinal) ||
            !string.Equals(segments[2], "releases", StringComparison.Ordinal) ||
            !string.Equals(segments[3], "download", StringComparison.Ordinal) ||
            !string.Equals(segments[4], releaseTag, StringComparison.Ordinal) ||
            !string.Equals(segments[5], ReleaseAssetName, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The release package did not use the official AccessXI GitHub release path.");
        }

        return uri;
    }

    private static string ParseSha256Digest(string? digest)
    {
        const string prefix = "sha256:";
        if (digest is null || !digest.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("The AccessXI release package did not include a SHA-256 digest.");
        }

        var hex = digest[prefix.Length..];
        if (hex.Length != 64 || hex.Any(character => !Uri.IsHexDigit(character)))
        {
            throw new InvalidDataException("The AccessXI release package included an invalid SHA-256 digest.");
        }

        return hex.ToLowerInvariant();
    }

    private static async Task<string> ComputeSha256HexAsync(Stream stream, CancellationToken cancellationToken)
    {
        var digest = await SHA256.HashDataAsync(stream, cancellationToken).ConfigureAwait(false);
        return Convert.ToHexString(digest).ToLowerInvariant();
    }

    private static async Task<byte[]> ReadLimitedBytesAsync(Stream stream, long maximumBytes, CancellationToken cancellationToken)
    {
        using var output = new MemoryStream();
        var buffer = new byte[32 * 1024];
        long total = 0;
        int read;
        while ((read = await stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false)) > 0)
        {
            total = checked(total + read);
            if (total > maximumBytes)
            {
                throw new InvalidDataException("GitHub release metadata exceeded the allowed size.");
            }

            output.Write(buffer, 0, read);
        }

        return output.ToArray();
    }

    private static void AddGitHubHeaders(HttpRequestHeaders headers)
    {
        headers.UserAgent.ParseAdd("AccessXI-Installer/1.0");
        headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        headers.TryAddWithoutValidation("X-GitHub-Api-Version", GitHubApiVersion);
    }

    private static bool IsRecoverableUpdateException(Exception exception)
    {
        return exception is HttpRequestException or IOException or InvalidDataException or JsonException or CryptographicException or UnauthorizedAccessException or FormatException or OverflowException or OperationCanceledException;
    }

    private static string ConciseFailureReason(Exception exception)
    {
        if (exception is OperationCanceledException)
        {
            return "The GitHub update request timed out.";
        }

        var message = exception.GetBaseException().Message;
        message = string.Join(' ', message.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (message.Length > 240)
        {
            message = message[..237] + "...";
        }

        return message.EndsWith(".", StringComparison.Ordinal) ? message : message + ".";
    }

    internal static void TryDeleteDirectory(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, recursive: true);
            }
        }
        catch
        {
            // Best-effort cleanup must not hide the completed install/update result.
        }
    }

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")]
        public string? TagName { get; init; }

        [JsonPropertyName("draft")]
        public bool Draft { get; init; }

        [JsonPropertyName("prerelease")]
        public bool Prerelease { get; init; }

        [JsonPropertyName("assets")]
        public List<GitHubAsset>? Assets { get; init; }
    }

    private sealed class GitHubAsset
    {
        [JsonPropertyName("name")]
        public string? Name { get; init; }

        [JsonPropertyName("state")]
        public string? State { get; init; }

        [JsonPropertyName("size")]
        public long Size { get; init; }

        [JsonPropertyName("digest")]
        public string? Digest { get; init; }

        [JsonPropertyName("browser_download_url")]
        public string? BrowserDownloadUrl { get; init; }
    }

    private sealed record ReleaseDescriptor(string TagName, ReleaseAsset Asset);

    private sealed record ReleaseAsset(Uri DownloadUri, long Size, string Sha256Hex);
}

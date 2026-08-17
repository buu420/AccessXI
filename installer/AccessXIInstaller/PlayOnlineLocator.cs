using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace AccessXIInstaller;

/// <summary>
/// Finds the PlayOnline Viewer that AccessXI has to install beside.
/// The standalone Square Enix installer drops the viewer under Program Files, but the
/// Steam release puts it in a Steam library (steamapps\common\FFXINA\SquareEnix), which
/// no Program Files guess can reach. Both installers ask the PlayOnline registry keys
/// first because those are written by whichever installer actually ran.
/// </summary>
internal static class PlayOnlineLocator
{
    /// <summary>Depot folder names Steam uses for the regional FFXI releases.</summary>
    private static readonly string[] SteamGameFolders = { "FFXINA", "FFXIEU", "FFXIJP" };

    private static readonly string[][] ProgramFilesRelativeCandidates =
    {
        new[] { "PlayOnline", "SquareEnix", "PlayOnlineViewer", "pol.exe" },
        new[] { "SquareEnix", "PlayOnlineViewer", "pol.exe" },
    };

    /// <summary>
    /// Builds the ordered pol.exe probe list. Registry-reported viewer folders win because
    /// they describe the install that exists rather than one of the conventional layouts.
    /// </summary>
    internal static IEnumerable<string> GetPolExeCandidates(
        IEnumerable<string>? registryViewerRoots,
        IEnumerable<string>? steamLibraryRoots,
        IEnumerable<string>? programFilesRoots)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var viewerRoot in Clean(registryViewerRoots))
        {
            var candidate = Path.Combine(viewerRoot, "pol.exe");
            if (seen.Add(candidate))
            {
                yield return candidate;
            }
        }

        foreach (var libraryRoot in Clean(steamLibraryRoots))
        {
            foreach (var gameFolder in SteamGameFolders)
            {
                var candidate = Path.Combine(libraryRoot, "steamapps", "common", gameFolder, "SquareEnix", "PlayOnlineViewer", "pol.exe");
                if (seen.Add(candidate))
                {
                    yield return candidate;
                }
            }
        }

        foreach (var programFilesRoot in Clean(programFilesRoots))
        {
            foreach (var relativeCandidate in ProgramFilesRelativeCandidates)
            {
                var parts = new string[relativeCandidate.Length + 1];
                parts[0] = programFilesRoot;
                relativeCandidate.CopyTo(parts, 1);
                var candidate = Path.Combine(parts);
                if (seen.Add(candidate))
                {
                    yield return candidate;
                }
            }
        }
    }

    /// <summary>
    /// Scans one level of every steamapps\common folder so a depot name we do not know about
    /// still resolves. Only returns paths that exist.
    /// </summary>
    internal static IEnumerable<string> EnumerateSteamCommonPolExe(IEnumerable<string>? steamLibraryRoots)
    {
        foreach (var libraryRoot in Clean(steamLibraryRoots))
        {
            string[] gameFolders;
            try
            {
                gameFolders = Directory.GetDirectories(Path.Combine(libraryRoot, "steamapps", "common"));
            }
            catch
            {
                continue;
            }

            foreach (var gameFolder in gameFolders)
            {
                var candidate = Path.Combine(gameFolder, "SquareEnix", "PlayOnlineViewer", "pol.exe");
                if (File.Exists(candidate))
                {
                    yield return candidate;
                }
            }
        }
    }

    /// <summary>
    /// Reads every library path out of a steamapps\libraryfolders.vdf document.
    /// VDF escapes path separators, so "D:\\Games" means D:\Games.
    /// </summary>
    internal static IReadOnlyList<string> ParseSteamLibraryRoots(string? libraryFoldersVdf)
    {
        var roots = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (Match match in Regex.Matches(libraryFoldersVdf ?? string.Empty, "\"path\"\\s*\"([^\"]*)\"", RegexOptions.IgnoreCase))
        {
            var libraryRoot = match.Groups[1].Value.Replace(@"\\", @"\").Trim();
            if (libraryRoot.Length == 0)
            {
                continue;
            }

            if (seen.Add(libraryRoot.TrimEnd('\\')))
            {
                roots.Add(libraryRoot);
            }
        }

        return roots;
    }

    /// <summary>
    /// Expands Steam install roots into every library folder Steam knows about, so games
    /// installed on a second drive are still found.
    /// </summary>
    internal static IReadOnlyList<string> GetSteamLibraryRoots(IEnumerable<string>? steamInstallRoots)
    {
        var roots = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var steamRoot in Clean(steamInstallRoots))
        {
            if (seen.Add(steamRoot.TrimEnd('\\')))
            {
                roots.Add(steamRoot);
            }

            string libraryFoldersVdf;
            try
            {
                libraryFoldersVdf = File.ReadAllText(Path.Combine(steamRoot, "steamapps", "libraryfolders.vdf"));
            }
            catch
            {
                continue;
            }

            foreach (var libraryRoot in ParseSteamLibraryRoots(libraryFoldersVdf))
            {
                if (seen.Add(libraryRoot.TrimEnd('\\')))
                {
                    roots.Add(libraryRoot);
                }
            }
        }

        return roots;
    }

    /// <summary>
    /// FFXI always sits next to PlayOnlineViewer under the same SquareEnix folder, which
    /// holds for the Steam layout as well as the standalone one.
    /// </summary>
    internal static string GetFfxiInstallRootFromPolExe(string polExe)
    {
        if (string.IsNullOrWhiteSpace(polExe))
        {
            return string.Empty;
        }

        var viewerDirectory = Path.GetDirectoryName(Path.GetFullPath(polExe));
        if (string.IsNullOrEmpty(viewerDirectory))
        {
            return string.Empty;
        }

        var squareEnixRoot = Path.GetDirectoryName(viewerDirectory);
        if (string.IsNullOrEmpty(squareEnixRoot))
        {
            return string.Empty;
        }

        return Path.Combine(squareEnixRoot, "FINAL FANTASY XI");
    }

    /// <summary>
    /// Resolves the pol.exe to install beside, or an empty string when nothing is found.
    /// </summary>
    internal static string FindDefaultPolExe()
    {
        var steamLibraryRoots = GetSteamLibraryRoots(GetSteamInstallRoots());
        var candidate = GetPolExeCandidates(ReadPlayOnlineViewerRootsFromRegistry(), steamLibraryRoots, GetProgramFilesRoots())
            .FirstOrDefault(File.Exists);
        if (!string.IsNullOrEmpty(candidate))
        {
            return candidate;
        }

        // Last resort for a Steam depot folder name we do not know about.
        return EnumerateSteamCommonPolExe(steamLibraryRoots).FirstOrDefault() ?? string.Empty;
    }

    internal static IReadOnlyList<string> GetProgramFilesRoots()
    {
        return new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Environment.GetEnvironmentVariable("ProgramW6432") ?? string.Empty,
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        };
    }

    /// <summary>
    /// The PlayOnline installer records the viewer folder under InstallFolder\1000 whether it ran
    /// from the Square Enix download or from the Steam depot, so this is the one probe that covers
    /// both. FFXI is 32-bit, so the value normally lives in the WOW6432Node view.
    /// </summary>
    internal static IReadOnlyList<string> ReadPlayOnlineViewerRootsFromRegistry()
    {
        var viewerRoots = new List<string>();

        foreach (var registryView in new[] { RegistryView.Registry32, RegistryView.Registry64 })
        {
            using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, registryView);
            foreach (var product in new[] { "PlayOnlineUS", "PlayOnlineEU", "PlayOnlineJP", "PlayOnline" })
            {
                using var installFolderKey = baseKey.OpenSubKey(@"SOFTWARE\" + product + @"\InstallFolder");
                if (installFolderKey?.GetValue("1000") is string viewerRoot && !string.IsNullOrWhiteSpace(viewerRoot))
                {
                    viewerRoots.Add(viewerRoot.Trim());
                }
            }
        }

        return viewerRoots;
    }

    internal static IReadOnlyList<string> GetSteamInstallRoots()
    {
        var steamRoots = new List<string>();

        void Add(string? steamRoot)
        {
            if (!string.IsNullOrWhiteSpace(steamRoot))
            {
                // HKCU stores the Steam path with forward slashes.
                steamRoots.Add(steamRoot.Trim().Replace('/', '\\'));
            }
        }

        using (var currentUserKey = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
        {
            Add(currentUserKey?.GetValue("SteamPath") as string);
        }

        foreach (var registryView in new[] { RegistryView.Registry32, RegistryView.Registry64 })
        {
            using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, registryView);
            using var steamKey = baseKey.OpenSubKey(@"SOFTWARE\Valve\Steam");
            Add(steamKey?.GetValue("InstallPath") as string);
        }

        foreach (var programFilesRoot in Clean(GetProgramFilesRoots()))
        {
            Add(Path.Combine(programFilesRoot, "Steam"));
        }

        return steamRoots;
    }

    private static IEnumerable<string> Clean(IEnumerable<string>? values)
    {
        return (values ?? Array.Empty<string>())
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim());
    }
}

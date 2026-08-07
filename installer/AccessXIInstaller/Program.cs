using System.Diagnostics;
using System.IO.Compression;
using System.Reflection;
using Microsoft.Win32;

namespace AccessXIInstaller;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new InstallerForm());
    }
}

internal sealed class InstallerForm : Form
{
    private const string PayloadResourceName = "Payload.AccessXI-Ashita-Installer.zip";
    private const string CompletionMessage = "AccessXI was installed. Use the AccessXI Ashita desktop shortcut to start the game. Advanced: from the Ashita folder, run Ashita-cli.exe accessxi-retail.ini. PlayOnline diagnostics are written to %USERPROFILE%\\AccessXI\\logs.";
    private const long KnownUpdatedPlayOnlineAppDllSize = 4335104;
    private const ulong KnownUpdatedPlayOnlineAppDllFnv64 = 0x07E88E8067FEF6CCUL;
    private const string UpdatedPlayOnlineAppDllRelativePathForDiagnostics = @"PlayOnlineViewer\viewer\com\app.dll";

    private readonly TextBox installRootText;
    private readonly TextBox polExeText;
    private readonly TextBox logText;
    private readonly Button installButton;
    private readonly Button closeButton;
    private readonly Button browseInstallButton;
    private readonly Button browsePolButton;
    private readonly Label statusLabel;
    private readonly Label completionLabel;
    private readonly CheckBox openSetupGuideCheckBox;
    private readonly ProgressBar progressBar;
    private readonly bool playOnlineDetectedOnLaunch;
    private InstallState installState = InstallState.Ready;

    private sealed record RuntimePrerequisite(string Name, string FileName);

    private enum PlayOnlineViewerStateKind
    {
        Updated,
        UpdateSafe,
    }

    private sealed record PlayOnlineViewerState(PlayOnlineViewerStateKind Kind, string Message);

    private sealed record VisualCppPrerequisite(string Name, string Architecture, string FileName)
    {
        public RuntimePrerequisite ToRuntimePrerequisite() => new(Name, FileName);
    }

    private static readonly VisualCppPrerequisite[] VisualCppPrerequisites =
    [
        new("Microsoft Visual C++ Runtime (x86)", "x86", "vc_redist.x86.exe"),
        new("Microsoft Visual C++ Runtime (x64)", "x64", "vc_redist.x64.exe"),
    ];

    private enum InstallState
    {
        Ready,
        Installing,
        Complete,
        Failed,
    }

    public InstallerForm()
    {
        var detectedPolExe = FindDefaultPolExe();
        playOnlineDetectedOnLaunch = !string.IsNullOrWhiteSpace(detectedPolExe);

        Text = "AccessXI Installer";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(760, 520);
        Width = 820;
        Height = 560;

        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 6,
            Padding = new Padding(12),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        Controls.Add(root);

        var title = new Label
        {
            AutoSize = true,
            Font = new Font(Font.FontFamily, 14, FontStyle.Bold),
            Text = "Install AccessXI",
            Margin = new Padding(0, 0, 0, 8),
        };
        root.Controls.Add(title, 0, 0);

        var intro = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(760, 0),
            Text = "Choose where AccessXI should be installed. The installer will place Ashita there, remove files from older AccessXI installations when safely detected, and deploy the native PlayOnline accessibility files beside pol.exe.",
            Margin = new Padding(0, 0, 0, 12),
        };
        root.Controls.Add(intro, 0, 1);

        var fields = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 3,
            RowCount = 2,
            AutoSize = true,
        };
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        fields.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        fields.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        fields.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.Controls.Add(fields, 0, 2);

        fields.Controls.Add(new Label
        {
            Text = "Install destination",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 6, 8, 6),
        }, 0, 0);

        installRootText = new TextBox
        {
            Dock = DockStyle.Fill,
            Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AccessXI"),
        };
        fields.Controls.Add(installRootText, 1, 0);

        browseInstallButton = new Button
        {
            Text = "Browse...",
            AutoSize = true,
            Margin = new Padding(8, 0, 0, 4),
        };
        browseInstallButton.Click += (_, _) => BrowseInstallRoot();
        fields.Controls.Add(browseInstallButton, 2, 0);

        fields.Controls.Add(new Label
        {
            Text = "PlayOnline pol.exe",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 6, 8, 6),
        }, 0, 1);

        polExeText = new TextBox
        {
            Dock = DockStyle.Fill,
            Text = detectedPolExe,
        };
        fields.Controls.Add(polExeText, 1, 1);

        browsePolButton = new Button
        {
            Text = "Browse...",
            AutoSize = true,
            Margin = new Padding(8, 0, 0, 4),
        };
        browsePolButton.Click += (_, _) => BrowsePolExe();
        fields.Controls.Add(browsePolButton, 2, 1);

        var progressPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 4,
            AutoSize = true,
            Margin = new Padding(0, 12, 0, 0),
        };
        progressPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        progressPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        progressPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        progressPanel.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.Controls.Add(progressPanel, 0, 3);

        statusLabel = new Label
        {
            AutoSize = true,
            Text = "Ready to install.",
            Margin = new Padding(0, 0, 0, 4),
        };
        progressPanel.Controls.Add(statusLabel, 0, 0);

        progressBar = new ProgressBar
        {
            Dock = DockStyle.Fill,
            Height = 18,
            Minimum = 0,
            Maximum = 100,
            Style = ProgressBarStyle.Continuous,
            Value = 0,
        };
        progressPanel.Controls.Add(progressBar, 0, 1);

        completionLabel = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(760, 0),
            Text = string.Empty,
            Visible = false,
            Margin = new Padding(0, 8, 0, 0),
        };
        progressPanel.Controls.Add(completionLabel, 0, 2);

        openSetupGuideCheckBox = new CheckBox
        {
            AutoSize = true,
            Checked = true,
            Text = "Open setup guide when I click Finish",
            Visible = false,
            Margin = new Padding(0, 8, 0, 0),
        };
        progressPanel.Controls.Add(openSetupGuideCheckBox, 0, 3);

        logText = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Vertical,
            Font = new Font(FontFamily.GenericMonospace, 9),
            Margin = new Padding(0, 12, 0, 8),
        };
        root.Controls.Add(logText, 0, 4);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
        };
        root.Controls.Add(buttons, 0, 5);

        closeButton = new Button
        {
            Text = "Cancel",
            AutoSize = true,
        };
        closeButton.Click += (_, _) =>
        {
            if (installState == InstallState.Complete)
            {
                OpenSetupGuideAfterFinish();
                Close();
                return;
            }

            if (installState != InstallState.Installing)
            {
                Close();
            }
        };
        buttons.Controls.Add(closeButton);

        installButton = new Button
        {
            Text = "Install",
            AutoSize = true,
        };
        installButton.Click += async (_, _) => await InstallAsync();
        buttons.Controls.Add(installButton);

        AppendLog("Ready. This installer must run elevated so it can deploy the PlayOnline loader files.");
        SetInstallState(InstallState.Ready);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);

        if (!playOnlineDetectedOnLaunch)
        {
            ExitBecausePlayOnlineMissing();
        }
    }

    private void BrowseInstallRoot()
    {
        using var dialog = new FolderBrowserDialog
        {
            Description = "Choose the AccessXI installation destination.",
            UseDescriptionForTitle = true,
            SelectedPath = Directory.Exists(installRootText.Text) ? installRootText.Text : Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        };

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            installRootText.Text = dialog.SelectedPath;
        }
    }

    private void BrowsePolExe()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Choose PlayOnline Viewer pol.exe",
            Filter = "PlayOnline pol.exe|pol.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*",
            FileName = "pol.exe",
            CheckFileExists = true,
        };

        var current = polExeText.Text.Trim();
        if (File.Exists(current))
        {
            dialog.InitialDirectory = Path.GetDirectoryName(current);
        }

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            polExeText.Text = dialog.FileName;
        }
    }

    private async Task InstallAsync()
    {
        var installRoot = installRootText.Text.Trim();
        var polExe = polExeText.Text.Trim();

        if (string.IsNullOrWhiteSpace(installRoot))
        {
            MessageBox.Show(this, "Choose an installation destination.", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        if (!File.Exists(polExe))
        {
            ExitBecausePlayOnlineMissing();
            return;
        }

        var playOnlineViewerState = DetectPlayOnlineViewerVersion(polExe);
        AppendLog(playOnlineViewerState.Message);
        if (playOnlineViewerState.Kind == PlayOnlineViewerStateKind.UpdateSafe)
        {
            MessageBox.Show(this, playOnlineViewerState.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        try
        {
            var missingVisualCppRedistributables = DetectMissingVisualCppRedistributables();
            var missingPrerequisites = missingVisualCppRedistributables
                .Select(prerequisite => prerequisite.ToRuntimePrerequisite())
                .ToList();
            var installMissingPrerequisites = false;

            if (missingPrerequisites.Count > 0)
            {
                var choice = AskPrerequisiteInstallChoice(missingPrerequisites);
                if (choice == DialogResult.Cancel)
                {
                    AppendLog("Installation canceled before dependency installation.");
                    return;
                }

                installMissingPrerequisites = choice == DialogResult.Yes;
                if (installMissingPrerequisites)
                {
                    AppendLog("Will run bundled Microsoft dependency installers before installing AccessXI.");
                }
                else
                {
                    AppendLog("Continuing without running bundled Microsoft dependency installers at the user's request.");
                }
            }
            else
            {
                AppendLog("Runtime prerequisites are already registered.");
            }

            SetInstallState(InstallState.Installing);
            SetStep("Starting installation.", 5);
            AppendLog("Starting installation.");
            AppendLog("Install destination: " + installRoot);
            AppendLog("PlayOnline executable: " + polExe);

            var summary = await Task.Run(() => RunInstaller(installRoot, polExe, installMissingPrerequisites, missingVisualCppRedistributables));
            AppendLog("Installation finished.");
            AppendLog("Launcher: " + Path.Combine(installRoot, "Ashita", "Ashita-cli.exe") + " accessxi-retail.ini");
            AppendLog("Desktop shortcut: AccessXI Ashita");
            if (!string.IsNullOrWhiteSpace(summary))
            {
                AppendLog("Summary:");
                AppendLog(summary);
            }

            SetStep("AccessXI installation is complete. Use Finish to close this installer.", 100);
            SetInstallState(InstallState.Complete);
        }
        catch (Exception ex)
        {
            SetStep("Installation failed.", Math.Max(progressBar.Value, 5));
            SetInstallState(InstallState.Failed);
            AppendLog("ERROR: " + ex.Message);
            MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private string RunInstaller(string installRoot, string polExe, bool installMissingPrerequisites, IReadOnlyCollection<VisualCppPrerequisite> missingVisualCppRedistributables)
    {
        var extractionRoot = Path.Combine(Path.GetTempPath(), "AccessXIInstaller", DateTime.Now.ToString("yyyyMMdd-HHmmss"));
        Directory.CreateDirectory(extractionRoot);

        SetStepThreadSafe("Extracting embedded AccessXI payload.", 15);
        var zipPath = Path.Combine(extractionRoot, "AccessXI-Ashita-Installer.zip");
        using (var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream(PayloadResourceName))
        {
            if (payload == null)
            {
                throw new InvalidOperationException("Embedded AccessXI payload was not found.");
            }

            using var file = File.Create(zipPath);
            payload.CopyTo(file);
        }

        AppendLogThreadSafe("Extracting embedded payload.");
        ZipFile.ExtractToDirectory(zipPath, extractionRoot, overwriteFiles: true);
        var prerequisitesRoot = Path.Combine(extractionRoot, "payload", "Prerequisites");
        if (installMissingPrerequisites)
        {
            SetStepThreadSafe("Installing missing Microsoft runtime prerequisites.", 25);
            RunPrerequisiteInstallers(prerequisitesRoot, missingVisualCppRedistributables);
        }
        else if (missingVisualCppRedistributables.Count > 0)
        {
            AppendLogThreadSafe("Missing runtime prerequisite installation was skipped by user choice.");
        }

        var installerScript = Path.Combine(extractionRoot, "install_accessxi.ps1");
        if (!File.Exists(installerScript))
        {
            throw new FileNotFoundException("Extracted installer script was not found.", installerScript);
        }

        var powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        var startInfo = new ProcessStartInfo
        {
            FileName = powershell,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            WorkingDirectory = extractionRoot,
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(installerScript);
        startInfo.ArgumentList.Add("-InstallRoot");
        startInfo.ArgumentList.Add(installRoot);
        startInfo.ArgumentList.Add("-PolExe");
        startInfo.ArgumentList.Add(polExe);
        startInfo.ArgumentList.Add("-SkipVisualCppRedistributables");

        SetStepThreadSafe("Installing Ashita, cleaning files from older AccessXI installations, and deploying native PlayOnline accessibility.", 35);
        AppendLogThreadSafe("Running packaged installer script.");
        using var process = new Process { StartInfo = startInfo };
        process.OutputDataReceived += (_, e) => { if (e.Data != null) AppendLogThreadSafe(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (e.Data != null) AppendLogThreadSafe(e.Data); };

        if (!process.Start())
        {
            throw new InvalidOperationException("PowerShell installer process could not be started.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        process.WaitForExit();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException("Installer script failed with exit code " + process.ExitCode + ".");
        }

        SetStepThreadSafe("Reading installation summary.", 95);
        var summaryPath = Path.Combine(installRoot, "install_summary.json");
        return File.Exists(summaryPath) ? File.ReadAllText(summaryPath) : string.Empty;
    }

    private static PlayOnlineViewerState DetectPlayOnlineViewerVersion(string polExe)
    {
        var polDirectory = Path.GetDirectoryName(polExe);
        if (string.IsNullOrWhiteSpace(polDirectory))
        {
            return new(
                PlayOnlineViewerStateKind.UpdateSafe,
                "AccessXI will install in update-safe mode. The selected pol.exe path could not be classified, so native PlayOnline menu hooks will stay disabled until the updated viewer files are present.");
        }

        var appDll = Path.Combine(polDirectory, "viewer", "com", "app.dll");
        if (!File.Exists(appDll))
        {
            return new(
                PlayOnlineViewerStateKind.UpdateSafe,
                "AccessXI will install in update-safe mode. The updated PlayOnline app.dll was not found at " + UpdatedPlayOnlineAppDllRelativePathForDiagnostics + "; start PlayOnline through AccessXI and finish the PlayOnline update. Native PlayOnline menu hooks stay disabled until the updated viewer files are present.");
        }

        try
        {
            var fingerprint = ComputeFileFnv64(appDll, out var size);
            if (size == KnownUpdatedPlayOnlineAppDllSize && fingerprint == KnownUpdatedPlayOnlineAppDllFnv64)
            {
                return new(
                    PlayOnlineViewerStateKind.Updated,
                    "Updated PlayOnline Viewer recognized. AccessXI can enable native PlayOnline menu hooks after installation.");
            }

            return new(
                PlayOnlineViewerStateKind.UpdateSafe,
                "AccessXI will install in update-safe mode. This PlayOnline Viewer appears to be pre-update or an unrecognized build; start PlayOnline through AccessXI and finish the PlayOnline update. Native PlayOnline menu hooks stay disabled until the updated viewer files are present. Detected size=" + size + ", fnv64=0x" + fingerprint.ToString("X16") + ".");
        }
        catch (Exception ex)
        {
            return new(
                PlayOnlineViewerStateKind.UpdateSafe,
                "AccessXI will install in update-safe mode. The PlayOnline Viewer version could not be fingerprinted (" + ex.GetType().Name + "), so native PlayOnline menu hooks will stay disabled until the updated viewer files are present.");
        }
    }

    private static ulong ComputeFileFnv64(string path, out long size)
    {
        const ulong offsetBasis = 14695981039346656037UL;
        const ulong prime = 1099511628211UL;

        var hash = offsetBasis;
        size = 0;
        var buffer = new byte[32768];
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
        {
            size += read;
            for (var index = 0; index < read; index++)
            {
                hash ^= buffer[index];
                hash *= prime;
            }
        }

        return hash;
    }

    private DialogResult AskPrerequisiteInstallChoice(IReadOnlyCollection<RuntimePrerequisite> missingPrerequisites)
    {
        var missingNames = string.Join(Environment.NewLine, missingPrerequisites.Select(prerequisite => " - " + prerequisite.Name));
        var message = "AccessXI needs these Microsoft runtime components before PlayOnline can load the accessibility bridge:" +
            Environment.NewLine + Environment.NewLine +
            missingNames +
            Environment.NewLine + Environment.NewLine +
            "Run the bundled Microsoft installers now before AccessXI installs?" +
            Environment.NewLine + Environment.NewLine +
            "Yes: run the bundled installers now." + Environment.NewLine +
            "No: continue without running them." + Environment.NewLine +
            "Cancel: stop installation.";

        return MessageBox.Show(this, message, "Install dependencies", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
    }

    private void RunPrerequisiteInstallers(string prerequisitesRoot, IReadOnlyCollection<VisualCppPrerequisite> missingVisualCppRedistributables)
    {
        if (!Directory.Exists(prerequisitesRoot))
        {
            throw new DirectoryNotFoundException("Packaged prerequisite folder was not found: " + prerequisitesRoot);
        }

        var prerequisites = missingVisualCppRedistributables
            .Select(prerequisite => prerequisite.ToRuntimePrerequisite())
            .ToList();
        if (prerequisites.Count == 0)
        {
            AppendLogThreadSafe("No missing runtime prerequisites need bundled installer runs.");
            return;
        }

        foreach (var prerequisite in prerequisites)
        {
            RunPrerequisiteInstaller(prerequisitesRoot, prerequisite);
        }
    }

    private void RunPrerequisiteInstaller(string prerequisitesRoot, RuntimePrerequisite prerequisite)
    {
        var installerPath = Path.Combine(prerequisitesRoot, prerequisite.FileName);
        if (!File.Exists(installerPath))
        {
            throw new FileNotFoundException("Packaged dependency installer is missing.", installerPath);
        }

        AppendLogThreadSafe("Running bundled dependency installer: " + prerequisite.Name);
        var startInfo = new ProcessStartInfo
        {
            FileName = installerPath,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        startInfo.ArgumentList.Add("/install");
        startInfo.ArgumentList.Add("/quiet");
        startInfo.ArgumentList.Add("/norestart");

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException("Dependency installer could not be started: " + prerequisite.Name);
        }

        process.WaitForExit();
        if (process.ExitCode != 0 && process.ExitCode != 3010 && process.ExitCode != 1638)
        {
            throw new InvalidOperationException(prerequisite.Name + " installer failed with exit code " + process.ExitCode + ".");
        }

        AppendLogThreadSafe("Finished " + prerequisite.Name + " installer with exit code " + process.ExitCode + ".");
    }

    private static List<VisualCppPrerequisite> DetectMissingVisualCppRedistributables()
    {
        return VisualCppPrerequisites
            .Where(prerequisite => !IsVisualCppRuntimeInstalled(prerequisite.Architecture))
            .ToList();
    }

    private static bool IsVisualCppRuntimeInstalled(string architecture)
    {
        foreach (var registryView in new[] { RegistryView.Registry64, RegistryView.Registry32 })
        {
            using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, registryView);
            using var runtimeKey = baseKey.OpenSubKey(@"SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\" + architecture);
            if (runtimeKey == null)
            {
                continue;
            }

            var installed = Convert.ToInt32(runtimeKey.GetValue("Installed", 0));
            var major = Convert.ToInt32(runtimeKey.GetValue("Major", 0));
            if (installed == 1 && major >= 14)
            {
                return true;
            }
        }

        return false;
    }

    private static string FindDefaultPolExe()
    {
        return GetDefaultPolExeCandidates().FirstOrDefault(File.Exists) ?? string.Empty;
    }

    private static IEnumerable<string> GetDefaultPolExeCandidates()
    {
        var roots = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
            Environment.GetEnvironmentVariable("ProgramW6432") ?? string.Empty,
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        };
        var relativeCandidates = new[]
        {
            new[] { "PlayOnline", "SquareEnix", "PlayOnlineViewer", "pol.exe" },
            new[] { "SquareEnix", "PlayOnlineViewer", "pol.exe" },
        };
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var root in roots.Where(root => !string.IsNullOrWhiteSpace(root)))
        {
            foreach (var relativeCandidate in relativeCandidates)
            {
                var parts = new string[relativeCandidate.Length + 1];
                parts[0] = root;
                relativeCandidate.CopyTo(parts, 1);
                var candidate = Path.Combine(parts);
                if (seen.Add(candidate))
                {
                    yield return candidate;
                }
            }
        }
    }

    private void AppendLog(string message)
    {
        logText.AppendText(message + Environment.NewLine);
    }

    private void AppendLogThreadSafe(string message)
    {
        if (IsDisposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke(new Action<string>(AppendLogThreadSafe), message);
            return;
        }

        AppendLog(message);
    }

    private void SetStep(string message, int percent)
    {
        statusLabel.Text = message;
        progressBar.Value = Math.Clamp(percent, progressBar.Minimum, progressBar.Maximum);
    }

    private void SetStepThreadSafe(string message, int percent)
    {
        if (IsDisposed)
        {
            return;
        }

        if (InvokeRequired)
        {
            BeginInvoke(new Action<string, int>(SetStepThreadSafe), message, percent);
            return;
        }

        SetStep(message, percent);
    }

    private void OpenSetupGuideAfterFinish()
    {
        if (!openSetupGuideCheckBox.Checked)
        {
            return;
        }

        var installRoot = installRootText.Text.Trim();
        var guidePath = Path.Combine(installRoot, "setup-guide.md");
        if (!File.Exists(guidePath))
        {
            MessageBox.Show(this, "The setup guide was not found at: " + guidePath, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = guidePath,
                UseShellExecute = true,
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "The setup guide could not be opened: " + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void ExitBecausePlayOnlineMissing()
    {
        AppendLog("PlayOnline Viewer was not detected. Closing installer.");
        MessageBox.Show(this, "PlayOnline Viewer was not detected. Install PlayOnline Viewer and Final Fantasy XI first, then run the AccessXI installer again.", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        Close();
    }

    private void SetInstallState(InstallState state)
    {
        installState = state;

        var installing = state == InstallState.Installing;
        var complete = state == InstallState.Complete;
        var failed = state == InstallState.Failed;
        var editable = !installing && !complete;

        installRootText.Enabled = editable;
        polExeText.Enabled = editable;
        browseInstallButton.Enabled = editable;
        browsePolButton.Enabled = editable;

        installButton.Enabled = !installing && !complete;
        installButton.Visible = !complete;
        installButton.Text = failed ? "Retry" : "Install";

        closeButton.Enabled = !installing;
        closeButton.Text = complete ? "Finish" : failed ? "Close" : "Cancel";

        completionLabel.Text = complete ? CompletionMessage : string.Empty;
        completionLabel.Visible = complete;
        openSetupGuideCheckBox.Visible = complete;
        openSetupGuideCheckBox.Enabled = complete;
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (installState == InstallState.Installing)
        {
            e.Cancel = true;
            return;
        }

        base.OnFormClosing(e);
    }
}

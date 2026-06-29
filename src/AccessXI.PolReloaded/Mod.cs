using Reloaded.Hooks.ReloadedII.Interfaces;
using Reloaded.Mod.Interfaces;
using AccessXI.PolReloaded.Template;
using AccessXI.PolReloaded.Configuration;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace AccessXI.PolReloaded;

/// <summary>
/// Your mod logic goes here.
/// </summary>
public class Mod : ModBase // <= Do not Remove.
{
    private static readonly PrismSpeech Speech = new();
    private static string ModDirectory => Path.GetDirectoryName(typeof(Mod).Assembly.Location) ?? AppContext.BaseDirectory;
    private static string DiagnosticLogDirectory
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable("ACCESSXI_POL_LOG_DIR");
            if (!string.IsNullOrWhiteSpace(configured))
                return configured;

            var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            return Path.Combine(userProfile, "AccessXI", "logs");
        }
    }

    private static string NativeSpeechQueuePath
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable("ACCESSXI_POL_SPEECH_QUEUE");
            if (!string.IsNullOrWhiteSpace(configured))
                return configured;

            return Path.Combine(DiagnosticLogDirectory, "pol-reloaded-native-speech.queue");
        }
    }

    private readonly object _nativeSpeechQueueLock = new();
    private Thread? _nativeSpeechQueueThread;
    private volatile bool _nativeSpeechQueueStop;

    /// <summary>
    /// Provides access to the mod loader API.
    /// </summary>
    private readonly IModLoader _modLoader;

    /// <summary>
    /// Provides access to the Reloaded.Hooks API.
    /// </summary>
    /// <remarks>This is null if you remove dependency on Reloaded.SharedLib.Hooks in your mod.</remarks>
    private readonly IReloadedHooks? _hooks;

    /// <summary>
    /// Provides access to the Reloaded logger.
    /// </summary>
    private readonly ILogger _logger;

    /// <summary>
    /// Entry point into the mod, instance that created this class.
    /// </summary>
    private readonly IMod _owner;

    /// <summary>
    /// Provides access to this mod's configuration.
    /// </summary>
    private Config _configuration;

    /// <summary>
    /// The configuration of the currently executing mod.
    /// </summary>
    private readonly IModConfig _modConfig;

    public Mod(ModContext context)
    {
        _modLoader = context.ModLoader;
        _hooks = context.Hooks;
        _logger = context.Logger;
        _owner = context.Owner;
        _configuration = context.Configuration;
        _modConfig = context.ModConfig;

#if DEBUG
        // Attaches debugger in debug mode; ignored in release.
        Debugger.Launch();
#endif

        // For more information about this template, please see
        // https://reloaded-project.github.io/Reloaded-II/ModTemplate/

        // If you want to implement e.g. unload support in your mod,
        // and some other neat features, override the methods in ModBase.

        // POL pre-login only. The Ashita addon remains responsible for in-game FFXI.
        LogStartupProbe();
        StartNativeSpeechQueueWorker();
        LoadNativeHookShim();
    }

    #region Standard Overrides
    public override void ConfigurationUpdated(Config configuration)
    {
        // Apply settings from configuration.
        // ... your code here.
        _configuration = configuration;
        _logger.WriteLine($"[{_modConfig.ModId}] Config Updated: Applying");
    }
    #endregion

    private void LogStartupProbe()
    {
        var process = Process.GetCurrentProcess();
        var appDllLoaded = process.Modules
            .Cast<ProcessModule>()
            .Any(module => string.Equals(module.ModuleName, "app.dll", StringComparison.OrdinalIgnoreCase));

        var executable = string.Empty;
        try
        {
            executable = process.MainModule?.FileName ?? string.Empty;
        }
        catch
        {
            executable = string.Empty;
        }

        var message = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED startup pid={process.Id} process={process.ProcessName} exe=\"{executable}\" modDir=\"{EscapeLogValue(ModDirectory)}\" logDir=\"{EscapeLogValue(DiagnosticLogDirectory)}\" queue=\"{EscapeLogValue(NativeSpeechQueuePath)}\" hooks={(_hooks != null)} app.dll={appDllLoaded} prismLocal={File.Exists(Path.Combine(ModDirectory, "prism.dll"))} nativeLocal={File.Exists(Path.Combine(ModDirectory, "accessxi_pol_native.dll"))}";
        _logger.WriteLine(message);
        AppendStartupMarker(message);
    }

    private static void ConfigureNativeDiagnostics()
    {
        var logDirectory = DiagnosticLogDirectory;
        var queuePath = NativeSpeechQueuePath;
        Directory.CreateDirectory(logDirectory);
        Environment.SetEnvironmentVariable("ACCESSXI_POL_LOG_DIR", logDirectory, EnvironmentVariableTarget.Process);
        Environment.SetEnvironmentVariable("ACCESSXI_POL_SPEECH_QUEUE", queuePath, EnvironmentVariableTarget.Process);
        AppendStartupMarker($"native-diagnostics-configured logDir=\"{EscapeLogValue(logDirectory)}\" queue=\"{EscapeLogValue(queuePath)}\"");
    }

    private static void AppendStartupMarker(string message)
    {
        try
        {
            var logDirectory = DiagnosticLogDirectory;
            Directory.CreateDirectory(logDirectory);
            File.AppendAllText(
                Path.Combine(logDirectory, "pol-reloaded-startup.log"),
                $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch
        {
            // Startup logging is evidence only; never let it break PlayOnline.
        }
    }

    private static void AppendSpeechMarker(string message)
    {
        try
        {
            var logDirectory = DiagnosticLogDirectory;
            Directory.CreateDirectory(logDirectory);
            File.AppendAllText(
                Path.Combine(logDirectory, "pol-reloaded-speech.log"),
                $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}");
        }
        catch
        {
            // Speech logging is evidence only; never let it break PlayOnline.
        }
    }

    private void StartNativeSpeechQueueWorker()
    {
        try
        {
            ConfigureNativeDiagnostics();
            var logDirectory = DiagnosticLogDirectory;
            Directory.CreateDirectory(logDirectory);
            var queuePath = NativeSpeechQueuePath;
            File.WriteAllText(queuePath, string.Empty);

            lock (_nativeSpeechQueueLock)
            {
                if (_nativeSpeechQueueThread is { IsAlive: true })
                    return;

                _nativeSpeechQueueStop = false;
                _nativeSpeechQueueThread = new Thread(() => RunNativeSpeechQueueWorker(queuePath))
                {
                    IsBackground = true,
                    Name = "AccessXI POL native speech queue"
                };
                _nativeSpeechQueueThread.SetApartmentState(ApartmentState.STA);
                _nativeSpeechQueueThread.Start();
            }

            var started = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE_SPEECH managed-queue-started logDir=\"{EscapeLogValue(logDirectory)}\" queue=\"{EscapeLogValue(queuePath)}\" apartment=STA";
            _logger.WriteLine(started);
            AppendSpeechMarker(started);
        }
        catch (Exception ex)
        {
            var message = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE_SPEECH worker-start-failed type={ex.GetType().Name} message=\"{ex.Message}\"";
            _logger.WriteLine(message);
            AppendSpeechMarker(message);
        }
    }

    private void RunNativeSpeechQueueWorker(string queuePath)
    {
        long offset = 0;
        var pendingFragment = string.Empty;
        var workerStarted = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE_SPEECH managed-queue-worker-started apartment={Thread.CurrentThread.GetApartmentState()}";
        _logger.WriteLine(workerStarted);
        AppendSpeechMarker(workerStarted);

        while (!_nativeSpeechQueueStop)
        {
            try
            {
                if (File.Exists(queuePath))
                {
                    using var stream = new FileStream(queuePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    if (stream.Length < offset)
                    {
                        offset = 0;
                        pendingFragment = string.Empty;
                        var rewind = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE_SPEECH managed-queue-rewind";
                        _logger.WriteLine(rewind);
                        AppendSpeechMarker(rewind);
                    }

                    stream.Position = offset;
                    using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, bufferSize: 1024, leaveOpen: true);
                    var chunk = reader.ReadToEnd();
                    offset = stream.Length;

                    if (!string.IsNullOrEmpty(chunk))
                        pendingFragment = DrainNativeSpeechLines(pendingFragment + chunk);
                }
            }
            catch (Exception ex)
            {
                var message = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE_SPEECH managed-queue-error type={ex.GetType().Name} message=\"{EscapeLogValue(ex.Message)}\"";
                _logger.WriteLine(message);
                AppendSpeechMarker(message);
            }

            Thread.Sleep(20);
        }
    }

    private string DrainNativeSpeechLines(string text)
    {
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');
        var lastNewline = text.LastIndexOf('\n');
        if (lastNewline < 0)
            return text;

        var complete = text[..lastNewline];
        var remainder = text[(lastNewline + 1)..];
        foreach (var rawLine in complete.Split('\n'))
        {
            var line = rawLine.Trim();
            if (line.Length == 0)
                continue;

            var message = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE_SPEECH managed-queue-speak text=\"{EscapeLogValue(line)}\"";
            _logger.WriteLine(message);
            AppendSpeechMarker(message);
            Speech.Speak(line, _logger);
        }

        return remainder;
    }

    private static string EscapeLogValue(string value) =>
        value.Replace("\\", "\\\\").Replace("\"", "\\\"");

    private void LoadNativeHookShim()
    {
        try
        {
            ConfigureNativeDiagnostics();
            var shimPath = Path.Combine(ModDirectory, "accessxi_pol_native.dll");
            if (!File.Exists(shimPath))
            {
                var missing = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE missing path=\"{shimPath}\"";
                _logger.WriteLine(missing);
                AppendStartupMarker(missing);
                return;
            }

            var module = LoadLibraryNative(shimPath);
            if (module == IntPtr.Zero)
            {
                var failed = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE load-failed path=\"{shimPath}\" error={Marshal.GetLastWin32Error()}";
                _logger.WriteLine(failed);
                AppendStartupMarker(failed);
                return;
            }

            var initializeProc = GetProcAddressNative(module, "AccessXI_POL_ReloadedInitialize");
            if (initializeProc == IntPtr.Zero)
            {
                var failed = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE export-missing path=\"{shimPath}\"";
                _logger.WriteLine(failed);
                AppendStartupMarker(failed);
                return;
            }

            var initialize = Marshal.GetDelegateForFunctionPointer<NativeReloadedInitialize>(initializeProc);
            initialize();

            var loaded = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE initialized path=\"{shimPath}\"";
            _logger.WriteLine(loaded);
            AppendStartupMarker(loaded);
        }
        catch (Exception ex)
        {
            var failed = $"[{_modConfig.ModId}] AccessXI_POL_RELOADED_NATIVE exception type={ex.GetType().Name} message=\"{ex.Message}\"";
            _logger.WriteLine(failed);
            AppendStartupMarker(failed);
        }
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate void NativeReloadedInitialize();

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "LoadLibraryW")]
    private static extern IntPtr LoadLibraryNative(string fileName);

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Ansi, EntryPoint = "GetProcAddress")]
    private static extern IntPtr GetProcAddressNative(IntPtr module, string procName);

    private sealed unsafe class PrismSpeech
    {
        private const ulong PrismBackendNvda = 0x89CC19C5C4AC1A56UL;
        private const ulong PrismBackendJaws = 0x0AC3D60E9BD84B53EUL;
        private const ulong PrismBackendUia = 0x6238F019DB678F8EUL;
        private const int GwlExStyle = -20;
        private const uint WsExToolWindow = 0x00000080;
        private const uint WsExTopmost = 0x00000008;
        private const int WindowPollIntervalMs = 50;
        private static readonly string[] PrismDllPaths =
        [
            Path.Combine(ModDirectory, "prism.dll"),
            Path.Combine(AppContext.BaseDirectory, "prism.dll"),
            "prism.dll"
        ];

        private bool _initialized;
        private IntPtr _module;
        private IntPtr _context;
        private IntPtr _backend;
        private string _backendName = string.Empty;
        private readonly object _lock = new();
        private PrismInit? _init;
        private PrismShutdown? _shutdown;
        private PrismRegistryCreate? _create;
        private PrismRegistryCreateBest? _createBest;
        private PrismBackendInitialize? _backendInitialize;
        private PrismBackendFree? _backendFree;
        private PrismBackendName? _backendNameExport;
        private PrismBackendOutput? _output;
        private PrismBackendStop? _stop;
        private PrismErrorString? _errorString;

        public void Speak(string text, ILogger logger)
        {
            if (string.IsNullOrWhiteSpace(text))
                return;

            lock (_lock)
            {
            try
            {
                if (!Initialize(logger))
                    return;

                var utf8 = Encoding.UTF8.GetBytes(text + "\0");
                fixed (byte* textPointer = utf8)
                {
                    var result = _output!(_backend, textPointer, true);
                    if (result == 0)
                    {
                        Log(logger, $"AccessXI_POL_RELOADED_SPEAK output-ok backend=\"{_backendName}\"");
                        return;
                    }

                    Log(logger, $"AccessXI_POL_RELOADED_SPEAK output-failed backend=\"{_backendName}\" error=\"{ErrorText(result)}\"");
                }

                ResetBackend();
                _initialized = false;

                if (!Initialize(logger))
                    return;

                fixed (byte* retryPointer = utf8)
                {
                    var retry = _output!(_backend, retryPointer, true);
                    if (retry == 0)
                    {
                        Log(logger, $"AccessXI_POL_RELOADED_SPEAK output-retry-ok backend=\"{_backendName}\"");
                        return;
                    }

                    Log(logger, $"AccessXI_POL_RELOADED_SPEAK output-retry-failed backend=\"{_backendName}\" error=\"{ErrorText(retry)}\"");
                    ResetBackend();
                    _initialized = false;
                }
            }
            catch (Exception ex)
            {
                Log(logger, $"AccessXI_POL_RELOADED_SPEAK exception type={ex.GetType().Name} message=\"{ex.Message}\"");
            }
            }
        }

        private bool Initialize(ILogger logger)
        {
            if (_initialized)
                return _backend != IntPtr.Zero;

            if (_module == IntPtr.Zero)
                _module = LoadPrismModule(logger);
            if (_module == IntPtr.Zero)
            {
                return FailInitialize(logger, "prism-dll-not-found", resetBackend: false);
            }

            _init = GetDelegate<PrismInit>(_module, "prism_init");
            _shutdown = GetDelegate<PrismShutdown>(_module, "prism_shutdown");
            _create = GetDelegate<PrismRegistryCreate>(_module, "prism_registry_create");
            _createBest = GetDelegate<PrismRegistryCreateBest>(_module, "prism_registry_create_best");
            _backendInitialize = GetDelegate<PrismBackendInitialize>(_module, "prism_backend_initialize");
            _backendFree = GetDelegate<PrismBackendFree>(_module, "prism_backend_free");
            _backendNameExport = GetDelegate<PrismBackendName>(_module, "prism_backend_name");
            _output = GetDelegate<PrismBackendOutput>(_module, "prism_backend_output");
            _stop = GetDelegate<PrismBackendStop>(_module, "prism_backend_stop");
            _errorString = GetDelegate<PrismErrorString>(_module, "prism_error_string");

            if (_init == null || _shutdown == null || _create == null || _createBest == null ||
                _backendInitialize == null || _backendFree == null || _output == null)
            {
                return FailInitialize(logger, "prism-exports-missing", resetBackend: false);
            }

            _context = _init(IntPtr.Zero);
            if (_context == IntPtr.Zero)
            {
                return FailInitialize(logger, "prism-init-failed");
            }

            if (TryCreateBackend(logger, PrismBackendNvda, "NVDA"))
            {
                _initialized = true;
                return true;
            }

            if (TryCreateBackend(logger, PrismBackendJaws, "JAWS"))
            {
                _initialized = true;
                return true;
            }

            if (!WaitForPrismUiaHostWindow(logger, TimeSpan.FromSeconds(10)))
                return FailInitialize(logger, "prism-uia-host-window-missing");

            if (TryCreateBackend(logger, PrismBackendUia, "UIA"))
            {
                _initialized = true;
                return true;
            }

            _backend = _createBest(_context);
            if (_backend == IntPtr.Zero)
            {
                return FailInitialize(logger, "prism-no-backend");
            }

            RememberBackendName(_backend);
            Log(logger, $"Prism speech backend available: {_backendName}");
            _initialized = true;
            return true;
        }

        private bool FailInitialize(ILogger logger, string reason, bool resetBackend = true)
        {
            Log(logger, $"AccessXI_POL_RELOADED_SPEAK initialize-failed reason=\"{reason}\"");
            if (resetBackend)
                ResetBackend();
            _initialized = false;
            return false;
        }

        private bool WaitForPrismUiaHostWindow(ILogger logger, TimeSpan timeout)
        {
            var started = Stopwatch.GetTimestamp();
            var timeoutMs = Math.Max(WindowPollIntervalMs, (int)timeout.TotalMilliseconds);

            while (true)
            {
                var hwnd = FindPrismUiaHostWindow();
                if (hwnd != IntPtr.Zero)
                {
                    var waitedMs = (int)Stopwatch.GetElapsedTime(started).TotalMilliseconds;
                    Log(
                        logger,
                        $"AccessXI_POL_RELOADED_SPEAK prism-uia-host-window-ready hwnd=0x{hwnd.ToInt64():X} waitedMs={waitedMs} foreground={IsSameWindow(GetForegroundWindow(), hwnd).ToString().ToLowerInvariant()} active={IsSameWindow(GetActiveWindow(), hwnd).ToString().ToLowerInvariant()} class=\"{EscapeLogValue(WindowClassName(hwnd))}\" title=\"{EscapeLogValue(WindowTitle(hwnd))}\"");
                    return true;
                }

                var elapsedMs = (int)Stopwatch.GetElapsedTime(started).TotalMilliseconds;
                if (elapsedMs >= timeoutMs)
                    break;

                Thread.Sleep(WindowPollIntervalMs);
            }

            Log(
                logger,
                $"AccessXI_POL_RELOADED_SPEAK prism-uia-host-window-missing timeoutMs={timeoutMs} foreground=0x{GetForegroundWindow().ToInt64():X} active=0x{GetActiveWindow().ToInt64():X}");
            return false;
        }

        private IntPtr FindPrismUiaHostWindow()
        {
            var foreground = GetForegroundWindow();
            if (IsPrismUiaCandidateWindow(foreground))
                return foreground;

            var active = GetActiveWindow();
            if (IsPrismUiaCandidateWindow(active))
                return active;

            var found = IntPtr.Zero;
            EnumWindows(
                (hwnd, _) =>
                {
                    if (!IsPrismUiaCandidateWindow(hwnd))
                        return true;

                    found = hwnd;
                    return false;
                },
                IntPtr.Zero);
            return found;
        }

        private bool IsPrismUiaCandidateWindow(IntPtr hwnd)
        {
            if (hwnd == IntPtr.Zero || !IsWindow(hwnd) || !IsWindowVisible(hwnd) || IsIconic(hwnd))
                return false;

            GetWindowThreadProcessId(hwnd, out var pid);
            if (pid != (uint)Environment.ProcessId)
                return false;

            var exStyle = (uint)GetWindowLongW(hwnd, GwlExStyle);
            if ((exStyle & (WsExToolWindow | WsExTopmost)) != 0)
                return false;

            if (IsSameWindow(hwnd, GetConsoleWindow()))
                return false;

            var className = WindowClassName(hwnd);
            if (string.Equals(className, "ConsoleWindowClass", StringComparison.Ordinal) ||
                string.Equals(className, "CASCADIA_HOSTING_WINDOW_CLASS", StringComparison.Ordinal))
                return false;

            return true;
        }

        private static bool IsSameWindow(IntPtr left, IntPtr right) =>
            left != IntPtr.Zero && left == right;

        private static string WindowClassName(IntPtr hwnd)
        {
            var buffer = new StringBuilder(256);
            return GetClassNameW(hwnd, buffer, buffer.Capacity) > 0 ? buffer.ToString() : string.Empty;
        }

        private static string WindowTitle(IntPtr hwnd)
        {
            var buffer = new StringBuilder(256);
            return GetWindowTextW(hwnd, buffer, buffer.Capacity) > 0 ? buffer.ToString() : string.Empty;
        }

        private bool TryCreateBackend(ILogger logger, ulong backendId, string name)
        {
            var backend = _create!(_context, backendId);
            if (backend == IntPtr.Zero)
            {
                Log(logger, $"AccessXI_POL_RELOADED_SPEAK prism-specific-backend-unavailable name=\"{name}\" error=\"create-failed\"");
                return false;
            }

            var initializeResult = _backendInitialize!(backend);
            if (initializeResult != 0)
            {
                Log(logger, $"AccessXI_POL_RELOADED_SPEAK prism-specific-backend-unavailable name=\"{name}\" error=\"{ErrorText(initializeResult)}\"");
                _backendFree!(backend);
                return false;
            }

            _backend = backend;
            RememberBackendName(_backend);
            Log(logger, $"Prism speech backend available: {_backendName} preferred={name}");
            return true;
        }

        private static IntPtr LoadPrismModule(ILogger logger)
        {
            foreach (var path in PrismDllPaths)
            {
                var module = LoadLibraryW(path);
                if (module != IntPtr.Zero)
                {
                    Log(logger, $"AccessXI_POL_RELOADED_SPEAK prism-loaded path=\"{path}\"");
                    return module;
                }

                Log(logger, $"AccessXI_POL_RELOADED_SPEAK prism-load-miss path=\"{path}\" error={Marshal.GetLastWin32Error()}");
            }

            return IntPtr.Zero;
        }

        private void ResetBackend()
        {
            if (_backend != IntPtr.Zero && _stop != null)
                _stop(_backend);
            if (_backend != IntPtr.Zero && _backendFree != null)
                _backendFree(_backend);
            _backend = IntPtr.Zero;
            _backendName = string.Empty;

            if (_context != IntPtr.Zero && _shutdown != null)
                _shutdown(_context);
            _context = IntPtr.Zero;
        }

        private string ErrorText(int error)
        {
            if (_errorString != null)
            {
                var textPointer = _errorString(error);
                var text = PtrToUtf8(textPointer, string.Empty);
                if (!string.IsNullOrEmpty(text))
                    return text;
            }

            return error.ToString();
        }

        private void RememberBackendName(IntPtr backend)
        {
            var namePointer = _backendNameExport?.Invoke(backend) ?? IntPtr.Zero;
            _backendName = PtrToUtf8(namePointer, "unknown");
        }

        private static string PtrToUtf8(IntPtr pointer, string fallback)
        {
            if (pointer == IntPtr.Zero)
                return fallback;

            try
            {
                return Marshal.PtrToStringUTF8(pointer) ?? fallback;
            }
            catch
            {
                return fallback;
            }
        }

        private static T? GetDelegate<T>(IntPtr module, string exportName)
            where T : Delegate
        {
            var proc = GetProcAddress(module, exportName);
            return proc == IntPtr.Zero ? null : Marshal.GetDelegateForFunctionPointer<T>(proc);
        }

        private static void Log(ILogger logger, string message)
        {
            logger.WriteLine(message);
            AppendSpeechMarker(message);
        }

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr PrismInit(IntPtr config);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void PrismShutdown(IntPtr context);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr PrismRegistryCreate(IntPtr context, ulong backendId);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr PrismRegistryCreateBest(IntPtr context);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int PrismBackendInitialize(IntPtr backend);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void PrismBackendFree(IntPtr backend);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr PrismBackendName(IntPtr backend);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int PrismBackendOutput(IntPtr backend, byte* text, [MarshalAs(UnmanagedType.I1)] bool interrupt);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int PrismBackendStop(IntPtr backend);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr PrismErrorString(int error);

        private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr LoadLibraryW(string fileName);

        [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Ansi)]
        private static extern IntPtr GetProcAddress(IntPtr module, string procName);

        [DllImport("kernel32")]
        private static extern IntPtr GetConsoleWindow();

        [DllImport("user32")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32")]
        private static extern IntPtr GetActiveWindow();

        [DllImport("user32")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

        [DllImport("user32")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr hwnd);

        [DllImport("user32")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr hwnd);

        [DllImport("user32")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsIconic(IntPtr hwnd);

        [DllImport("user32", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);

        [DllImport("user32", SetLastError = true, EntryPoint = "GetWindowLongW")]
        private static extern int GetWindowLongW(IntPtr hwnd, int index);

        [DllImport("user32", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetClassNameW(IntPtr hwnd, StringBuilder className, int maxCount);

        [DllImport("user32", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextW(IntPtr hwnd, StringBuilder text, int maxCount);
    }

    #region For Exports, Serialization etc.
#pragma warning disable CS8618 // Non-nullable field must contain a non-null value when exiting constructor. Consider declaring as nullable.
    public Mod() { }
#pragma warning restore CS8618
    #endregion
}

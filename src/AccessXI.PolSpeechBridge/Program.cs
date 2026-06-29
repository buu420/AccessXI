using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

internal static class Program
{
    private static string LogDirectory
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

    private static string LogPath => Path.Combine(LogDirectory, "pol-speech-bridge.log");

    private static string DefaultQueuePath
    {
        get
        {
            var configured = Environment.GetEnvironmentVariable("ACCESSXI_POL_SPEECH_QUEUE");
            if (!string.IsNullOrWhiteSpace(configured))
                return configured;

            return Path.Combine(LogDirectory, "pol-reloaded-native-speech.queue");
        }
    }

    public static int Main(string[] args)
    {
        Directory.CreateDirectory(LogDirectory);

        using var mutex = new Mutex(initiallyOwned: true, name: @"Global\AccessXI.PolSpeechBridge", createdNew: out var createdNew);
        if (!createdNew)
        {
            Log("bridge already running; exiting duplicate.");
            return 0;
        }

        var queuePath = GetArg(args, "--queue") ?? DefaultQueuePath;
        var parentPid = int.TryParse(GetArg(args, "--parent"), out var parsedPid) ? parsedPid : 0;
        var speech = new PrismSpeech(Log);

        Log($"bridge starting queue=\"{queuePath}\" parent={parentPid} engine=Prism");

        long offset = 0;
        var pendingFragment = string.Empty;
        while (ParentAlive(parentPid))
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
                        Log("queue rewind detected.");
                    }

                    stream.Position = offset;
                    using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, bufferSize: 1024, leaveOpen: true);
                    var chunk = reader.ReadToEnd();
                    offset = stream.Length;

                    if (!string.IsNullOrEmpty(chunk))
                        pendingFragment = DrainSpeechLines(speech, pendingFragment + chunk);
                }
            }
            catch (Exception ex)
            {
                Log($"bridge error type={ex.GetType().Name} message=\"{Escape(ex.Message)}\"");
            }

            Thread.Sleep(20);
        }

        speech.Shutdown(stopSpeech: false);
        Log("bridge exiting; parent is gone.");
        return 0;
    }

    private static string DrainSpeechLines(PrismSpeech speech, string text)
    {
        text = text.Replace("\r\n", "\n").Replace('\r', '\n');
        var lastNewline = text.LastIndexOf('\n');
        if (lastNewline < 0)
            return text;

        var complete = text[..lastNewline];
        var remainder = text[(lastNewline + 1)..];

        var latestLine = LatestCompleteSpeechLine(complete);
        if (!string.IsNullOrEmpty(latestLine))
        {
            Log($"bridge speak-latest text=\"{Escape(latestLine)}\"");
            var result = speech.Speak(latestLine);
            Log($"bridge speak-result text=\"{Escape(latestLine)}\" result=\"{Escape(result)}\"");
        }

        return remainder;
    }

    private static string? LatestCompleteSpeechLine(string complete)
    {
        var lines = complete.Split('\n');
        for (var index = lines.Length - 1; index >= 0; index--)
        {
            var line = lines[index].Trim();
            if (line.Length != 0)
                return line;
        }

        return null;
    }

    private static bool ParentAlive(int parentPid)
    {
        if (parentPid <= 0)
            return true;

        try
        {
            using var process = Process.GetProcessById(parentPid);
            return !process.HasExited;
        }
        catch
        {
            return false;
        }
    }

    private static string? GetArg(string[] args, string name)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        }

        return null;
    }

    private static string Escape(string value) =>
        value.Replace("\\", "\\\\").Replace("\"", "\\\"");

    private static void Log(string line)
    {
        try
        {
            Directory.CreateDirectory(LogDirectory);
            File.AppendAllText(LogPath, $"{DateTimeOffset.Now:O} {line}{Environment.NewLine}");
        }
        catch
        {
        }
    }
}

internal sealed class PrismSpeech
{
    private static readonly string[] PrismDllPaths =
    [
        Path.Combine(AppContext.BaseDirectory, "prism.dll"),
        "prism.dll"
    ];

    private readonly Action<string> _log;
    private bool _initialized;
    private IntPtr _module;
    private IntPtr _context;
    private IntPtr _backend;
    private string _backendName = string.Empty;
    private PrismInit? _init;
    private PrismShutdown? _shutdown;
    private PrismRegistryCreateBest? _createBest;
    private PrismBackendFree? _backendFree;
    private PrismBackendName? _backendNameExport;
    private PrismBackendOutput? _output;
    private PrismBackendStop? _stop;
    private PrismErrorString? _errorString;

    public PrismSpeech(Action<string> log)
    {
        _log = log;
    }

    public string Speak(string text)
    {
        if (string.IsNullOrWhiteSpace(text))
            return "empty";

        try
        {
            if (!Initialize())
                return "prism-unavailable";

            var result = Output(text);
            if (result == 0)
                return $"prism-ok:{_backendName}";

            var failure = ErrorText(result);
            _log($"bridge prism-output-failed backend=\"{Escape(_backendName)}\" error=\"{Escape(failure)}\"");
            ResetBackend();
            _initialized = false;

            if (!Initialize())
                return $"prism-retry-unavailable:{failure}";

            var retry = Output(text);
            if (retry == 0)
                return $"prism-retry-ok:{_backendName}";

            var retryFailure = ErrorText(retry);
            _log($"bridge prism-output-retry-failed backend=\"{Escape(_backendName)}\" error=\"{Escape(retryFailure)}\"");
            ResetBackend();
            _initialized = false;
            return $"prism-failed:{retryFailure}";
        }
        catch (Exception ex)
        {
            _log($"bridge prism-exception type={ex.GetType().Name} message=\"{Escape(ex.Message)}\"");
            return $"prism-exception:{ex.GetType().Name}";
        }
    }

    public void Shutdown(bool stopSpeech)
    {
        _log($"bridge prism-shutdown stopSpeech={stopSpeech.ToString().ToLowerInvariant()}");
        ResetBackend(stopSpeech);
        if (_module != IntPtr.Zero)
        {
            FreeLibrary(_module);
            _module = IntPtr.Zero;
        }

        _initialized = false;
    }

    private bool Initialize()
    {
        if (_initialized)
            return _backend != IntPtr.Zero;

        _initialized = true;
        _module = LoadPrismModule();
        if (_module == IntPtr.Zero)
        {
            _log("bridge prism-dll-not-found");
            return false;
        }

        _init = GetDelegate<PrismInit>(_module, "prism_init");
        _shutdown = GetDelegate<PrismShutdown>(_module, "prism_shutdown");
        _createBest = GetDelegate<PrismRegistryCreateBest>(_module, "prism_registry_create_best");
        _backendFree = GetDelegate<PrismBackendFree>(_module, "prism_backend_free");
        _backendNameExport = GetDelegate<PrismBackendName>(_module, "prism_backend_name");
        _output = GetDelegate<PrismBackendOutput>(_module, "prism_backend_output");
        _stop = GetDelegate<PrismBackendStop>(_module, "prism_backend_stop");
        _errorString = GetDelegate<PrismErrorString>(_module, "prism_error_string");

        if (_init == null || _shutdown == null || _createBest == null || _backendFree == null || _output == null)
        {
            _log("bridge prism-exports-missing");
            return false;
        }

        _context = _init(IntPtr.Zero);
        if (_context == IntPtr.Zero)
        {
            _log("bridge prism-init-failed");
            return false;
        }

        _backend = _createBest(_context);
        if (_backend == IntPtr.Zero)
        {
            _log("bridge prism-no-backend");
            ResetBackend();
            return false;
        }

        RememberBackendName(_backend);
        _log($"bridge prism-backend backend=\"{Escape(_backendName)}\"");
        return true;
    }

    private int Output(string text)
    {
        var bytes = Encoding.UTF8.GetBytes(text + "\0");
        var pointer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, pointer, bytes.Length);
            return _output!(_backend, pointer, true);
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
    }

    private IntPtr LoadPrismModule()
    {
        foreach (var path in PrismDllPaths)
        {
            var module = LoadLibraryW(path);
            if (module != IntPtr.Zero)
            {
                _log($"bridge prism-loaded path=\"{Escape(path)}\"");
                return module;
            }
        }

        return IntPtr.Zero;
    }

    private void ResetBackend(bool stopSpeech = true)
    {
        if (stopSpeech && _backend != IntPtr.Zero && _stop != null)
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

    private static string Escape(string value) =>
        value.Replace("\\", "\\\\").Replace("\"", "\\\"");

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr PrismInit(IntPtr config);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PrismShutdown(IntPtr context);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr PrismRegistryCreateBest(IntPtr context);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PrismBackendFree(IntPtr backend);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr PrismBackendName(IntPtr backend);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int PrismBackendOutput(IntPtr backend, IntPtr text, [MarshalAs(UnmanagedType.I1)] bool interrupt);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate int PrismBackendStop(IntPtr backend);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate IntPtr PrismErrorString(int error);

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibraryW(string fileName);

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern IntPtr GetProcAddress(IntPtr module, string procName);

    [DllImport("kernel32", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);
}

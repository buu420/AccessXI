using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

internal static class Program
{
    private const string LogDir = @"C:\Users\buu42\AccessXI\logs";
    private const string LogPath = @"C:\Users\buu42\AccessXI\logs\ocr-watcher.log";
    private const string CapturePath = @"C:\Users\buu42\AccessXI\logs\pol-capture.png";
    private const string TesseractPath = @"C:\Program Files\Tesseract-OCR\tesseract.exe";

    private static readonly int[] Keys = [0x25, 0x26, 0x27, 0x28, 0x0D, 0x1B];
    private static readonly Dictionary<int, bool> Previous = [];
    private static string _lastSpoken = string.Empty;
    private static long _captureDue;

    public static async Task Main()
    {
        Directory.CreateDirectory(LogDir);
        Log("AccessXI OCR watcher starting.");
        Nvda.Speak("Access XI OCR watcher loaded.");

        while (true)
        {
            var hwnd = Native.GetForegroundWindow();
            var title = Native.GetWindowTitle(hwnd);
            var isPol = title.Contains("PlayOnline Viewer", StringComparison.OrdinalIgnoreCase);

            if (isPol && PollKeys())
                _captureDue = Environment.TickCount64 + 250;

            if (isPol && _captureDue != 0 && Environment.TickCount64 >= _captureDue)
            {
                _captureDue = 0;
                await CaptureOcrAndSpeak(hwnd);
            }

            await Task.Delay(25);
        }
    }

    private static bool PollKeys()
    {
        var pressedAny = false;
        foreach (var key in Keys)
        {
            var down = (Native.GetAsyncKeyState(key) & 0x8000) != 0;
            var wasDown = Previous.TryGetValue(key, out var previous) && previous;
            if (down && !wasDown)
            {
                pressedAny = true;
                Log($"KEY {KeyName(key)}");
            }
            Previous[key] = down;
        }
        return pressedAny;
    }

    private static async Task CaptureOcrAndSpeak(IntPtr hwnd)
    {
        if (!Native.GetWindowRect(hwnd, out var rect))
        {
            Log("Capture failed: GetWindowRect failed.");
            return;
        }

        var width = Math.Max(1, rect.Right - rect.Left);
        var height = Math.Max(1, rect.Bottom - rect.Top);
        if (width < 100 || height < 100)
        {
            Log($"Capture skipped: suspicious size {width}x{height}.");
            return;
        }

        using (var bmp = new Bitmap(width, height))
        using (var g = Graphics.FromImage(bmp))
        {
            g.CopyFromScreen(rect.Left, rect.Top, 0, 0, new Size(width, height));
            bmp.Save(CapturePath, System.Drawing.Imaging.ImageFormat.Png);
        }

        var text = await RunTesseract(CapturePath);
        text = CleanText(text);
        if (string.IsNullOrWhiteSpace(text))
        {
            Log("OCR empty.");
            return;
        }

        Log("OCR text: " + text.ReplaceLineEndings(" | "));

        var speak = PickSpeechText(text);
        if (string.IsNullOrWhiteSpace(speak) || speak == _lastSpoken)
            return;

        _lastSpoken = speak;
        Log("OCR speaking: " + speak.ReplaceLineEndings(" | "));
        Nvda.Speak(speak);
    }

    private static async Task<string> RunTesseract(string imagePath)
    {
        if (!File.Exists(TesseractPath))
        {
            Log("Tesseract missing at " + TesseractPath);
            return string.Empty;
        }

        using var process = new Process();
        process.StartInfo.FileName = TesseractPath;
        process.StartInfo.ArgumentList.Add(imagePath);
        process.StartInfo.ArgumentList.Add("stdout");
        process.StartInfo.ArgumentList.Add("-l");
        process.StartInfo.ArgumentList.Add("eng");
        process.StartInfo.ArgumentList.Add("--psm");
        process.StartInfo.ArgumentList.Add("6");
        process.StartInfo.UseShellExecute = false;
        process.StartInfo.RedirectStandardOutput = true;
        process.StartInfo.RedirectStandardError = true;
        process.StartInfo.CreateNoWindow = true;
        process.Start();
        var output = await process.StandardOutput.ReadToEndAsync();
        var error = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        if (!string.IsNullOrWhiteSpace(error))
            Log("Tesseract stderr: " + error.ReplaceLineEndings(" | "));
        return output;
    }

    private static string PickSpeechText(string text)
    {
        var lines = text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(l => l.Length >= 2)
            .Where(l => !l.Contains("PlayOnline Viewer", StringComparison.OrdinalIgnoreCase))
            .Where(l => !l.Contains("Ashita", StringComparison.OrdinalIgnoreCase))
            .Take(6)
            .ToArray();
        return lines.Length == 0 ? string.Empty : string.Join(". ", lines);
    }

    private static string CleanText(string text)
    {
        var lines = text.Replace("\r", "\n")
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(l => string.Join(' ', l.Split(' ', StringSplitOptions.RemoveEmptyEntries)))
            .Where(l => l.Any(char.IsLetterOrDigit));
        return string.Join('\n', lines);
    }

    private static string KeyName(int key) => key switch
    {
        0x25 => "left",
        0x26 => "up",
        0x27 => "right",
        0x28 => "down",
        0x0D => "enter",
        0x1B => "escape",
        _ => key.ToString("X2")
    };

    private static void Log(string line)
    {
        Directory.CreateDirectory(LogDir);
        File.AppendAllText(LogPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {line}{Environment.NewLine}");
    }
}

internal static partial class Native
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr hWnd, out Rect lpRect);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    public static string GetWindowTitle(IntPtr hwnd)
    {
        var sb = new StringBuilder(512);
        GetWindowTextW(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}

internal static partial class Nvda
{
    private const string DllPath = @"C:\Users\buu42\AccessXI\ocr-watcher\nvdaControllerClient64.dll";

    [DllImport(DllPath, CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Unicode)]
    private static extern int nvdaController_speakText(string text);

    [DllImport(DllPath, CallingConvention = CallingConvention.StdCall)]
    private static extern int nvdaController_testIfRunning();

    public static void Speak(string text)
    {
        try
        {
            if (nvdaController_testIfRunning() == 0)
                nvdaController_speakText(text);
        }
        catch
        {
        }
    }
}

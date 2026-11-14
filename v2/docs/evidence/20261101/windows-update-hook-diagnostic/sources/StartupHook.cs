using System.Diagnostics;
using System.Runtime.ExceptionServices;
using System.Text;
using System.Text.Json;

// Disposable diagnostic only. No app changes, messages, data, environment dumps or memory dumps.
internal static class StartupHook
{
    [ThreadStatic] private static bool recording;
    private static readonly object gate = new();
    private static string? output;
    private static int count;

    public static void Initialize()
    {
        try
        {
            var args = Environment.GetCommandLineArgs();
            if (args.Length != 3 || args[1] != "--update-helper") return;
            var tx = Path.GetFullPath(args[2]);
            var transactionRoot = Directory.GetParent(tx);
            var scenario = transactionRoot?.Parent;
            var cases = scenario?.Parent;
            var root = cases?.Parent;
            if (root is null || cases!.Name != "cases" || scenario!.Name != "health-failure"
                || !transactionRoot!.Name.StartsWith(".pesto-v2-update-", StringComparison.Ordinal)
                || !Guid.TryParseExact(Path.GetFileName(tx), "N", out _)
                || !root.Name.StartsWith("Pesto-native-update-", StringComparison.Ordinal)
                || !Guid.TryParseExact(root.Name["Pesto-native-update-".Length..], "N", out _)) return;
            if (!string.Equals(Environment.ProcessPath, Path.Combine(tx, "helper", "Pesto.exe"), StringComparison.OrdinalIgnoreCase)) return;
            var expected = Path.Combine(root.FullName, "evidence", "health-failure", "hook-first-chance.jsonl");
            var requested = Environment.GetEnvironmentVariable("PESTO_DIAGNOSTIC_OUTPUT");
            if (requested is null || !string.Equals(Path.GetFullPath(requested), expected, StringComparison.OrdinalIgnoreCase)) return;
            for (var dir = new DirectoryInfo(Path.GetDirectoryName(expected)!); dir is not null; dir = dir.Parent)
                if ((dir.Attributes & FileAttributes.ReparsePoint) != 0) return;
            using (var file = new FileStream(expected, FileMode.CreateNew, FileAccess.Write, FileShare.Read))
            {
                var bytes = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { kind="pesto.first-chance-diagnostic", initialized=true, diagnosticOnly=true, utc=DateTimeOffset.UtcNow, pid=Environment.ProcessId }) + "\n");
                file.Write(bytes); file.Flush(true);
            }
            output = expected;
            AppDomain.CurrentDomain.FirstChanceException += Observe;
        }
        catch { /* A diagnostic must not prevent the real application entry point. */ }
    }

    private static void Observe(object? sender, FirstChanceExceptionEventArgs e)
    {
        if (recording || output is null) return;
        recording = true;
        try
        {
            lock (gate)
            {
                if (++count > 256) return;
                // Stack metadata only, without exception text, source filenames, arguments or exception Data.
                var frames = new StackTrace(e.Exception, false).GetFrames() ?? [];
                var stack = frames.Take(32).Select(f => new {
                    type=f.GetMethod()?.DeclaringType?.FullName,
                    method=f.GetMethod()?.Name,
                    ilOffset=f.GetILOffset()
                }).ToArray();
                var line = JsonSerializer.Serialize(new { utc=DateTimeOffset.UtcNow, pid=Environment.ProcessId,
                    threadId=Environment.CurrentManagedThreadId, type=e.Exception.GetType().FullName,
                    hResult=e.Exception.HResult, hResultHex=e.Exception.HResult.ToString("X8"), stack }) + "\n";
                File.AppendAllText(output, line, new UTF8Encoding(false));
            }
        }
        catch { }
        finally { recording = false; }
    }
}

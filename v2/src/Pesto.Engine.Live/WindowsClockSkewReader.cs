using System.Diagnostics;
using System.Text;

namespace Pesto.Engine.Live;

/// <summary>Port of Get-PestoClockObservation: one w32tm stripchart sample, no resync, no AD module and no fallback DC.</summary>
public sealed class WindowsClockSkewReader : IClockSkewReader
{
    public const int TimeoutMilliseconds = 6000;
    public static IReadOnlyList<string> ArgumentsFor(string server)
    {
        if (!JoinClockGuard.IsServer(server)) throw new ArgumentException("Contrôleur invalide.", nameof(server));
        return ["/stripchart", "/computer:" + server, "/dataonly", "/samples:1"];
    }

    public ClockSkewObservation ReadClockSkew(string server)
    {
        ClockSkewObservation Unknown(string code) => new(server, DateTimeOffset.UtcNow, null, code);
        if (!OperatingSystem.IsWindows() || !JoinClockGuard.IsServer(server)) return Unknown("clock.unavailable");
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "w32tm.exe");
        if (!File.Exists(path)) return Unknown("clock.unavailable");
        var start = new ProcessStartInfo(path)
        {
            RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8
        };
        foreach (var argument in ArgumentsFor(server)) start.ArgumentList.Add(argument);
        try
        {
            using var process = Process.Start(start);
            if (process is null) return Unknown("clock.unavailable");
            using var cancellation = new CancellationTokenSource();
            var output = ReadBounded(process.StandardOutput, cancellation.Token);
            var errors = ReadBounded(process.StandardError, cancellation.Token);
            if (!process.WaitForExit(TimeoutMilliseconds))
            {
                cancellation.Cancel();
                try { process.Kill(entireProcessTree: true); } catch (Exception) { }
                return Unknown("clock.timeout");
            }
            var text = output.GetAwaiter().GetResult();
            var error = errors.GetAwaiter().GetResult();
            if (text is null || error is null) return Unknown("clock.response_invalid");
            return JoinClockGuard.Parse(server, process.ExitCode, text, DateTimeOffset.UtcNow);
        }
        catch (Exception) { return Unknown("clock.unavailable"); }
    }

    private static async Task<string?> ReadBounded(StreamReader stream, CancellationToken cancellation)
    {
        var text = new StringBuilder();
        var buffer = new char[1024];
        var tooLong = false;
        try
        {
            while (true)
            {
                var count = await stream.ReadAsync(buffer.AsMemory(), cancellation).ConfigureAwait(false);
                if (count == 0) break;
                if (text.Length + count > 65536) tooLong = true;
                if (!tooLong) text.Append(buffer, 0, count);
            }
            return tooLong ? null : text.ToString();
        }
        catch (Exception) { return null; }
    }
}

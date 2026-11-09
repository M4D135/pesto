using System.Diagnostics;
using System.Text;

namespace Pesto.Engine.Live;

/// <summary>The powershell.exe file version tracks Windows, not the PowerShell engine. Read PSVersionTable in an
/// isolated no-profile process instead. No credentials, user script, environment override or mutation is involved.</summary>
public static class WindowsPowerShellProbe
{
    private const int MaximumCharacters = 1024;
    private const string VersionScript = "$v=$PSVersionTable.PSVersion;[Console]::Out.Write($v.Major.ToString()+'.'+$v.Minor.ToString())";
    // powershell.exe can take several seconds to start just after a boot (Defender, SysMain): a 10 s bound refused
    // whole sessions on slow workstations. A confirmed engine is kept for the process; a failure is reported as is and
    // probed again after a short delay rather than refusing every later operation of the session.
    private const int ProbeTimeoutMilliseconds = 60000;
    private const long FailureRetryMilliseconds = 30000;
    private static readonly object Gate = new();
    private static bool confirmed;
    private static string? lastFailure;
    private static long lastFailureTicks;

    public static string? UnavailableReason
    {
        get
        {
            lock (Gate)
            {
                if (confirmed) return null;
                if (lastFailure is not null && Environment.TickCount64 - lastFailureTicks < FailureRetryMilliseconds) return lastFailure;
                var reason = ProbeOnce();
                if (reason is null) { confirmed = true; lastFailure = null; }
                else { lastFailure = reason; lastFailureTicks = Environment.TickCount64; }
                return reason;
            }
        }
    }

    public static bool IsSupportedVersion(int exitCode, string? output) => exitCode == 0
        && output is { Length: <= MaximumCharacters } && string.Equals(output.Trim(), "5.1", StringComparison.Ordinal);

    private static string? ProbeOnce()
    {
        if (!OperatingSystem.IsWindows())
            return "Windows PowerShell 5.1 exige Windows ; ce poste n’est pas Windows : lectures et écritures refusées plutôt que simulées.";
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(path)) return "Windows PowerShell 5.1 est introuvable : les opérations sont refusées plutôt que simulées.";
        try
        {
            var start = new ProcessStartInfo(path)
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8
            };
            foreach (var value in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(VersionScript)) })
                start.ArgumentList.Add(value);
            using var process = Process.Start(start);
            if (process is null) return "Windows PowerShell n’a pas pu être vérifié : aucune opération autorisée.";
            var output = ReadBounded(process.StandardOutput);
            var errors = ReadBounded(process.StandardError);
            if (!process.WaitForExit(ProbeTimeoutMilliseconds))
            {
                try { process.Kill(entireProcessTree: true); } catch (Exception) { }
                return "La vérification de Windows PowerShell a expiré : aucune opération autorisée.";
            }
            var version = output.GetAwaiter().GetResult();
            _ = errors.GetAwaiter().GetResult();
            return IsSupportedVersion(process.ExitCode, version) ? null
                : "Le moteur Windows PowerShell 5.1 n’a pas été confirmé par PSVersionTable : opérations refusées.";
        }
        catch (Exception) { return "Windows PowerShell 5.1 n’a pas pu être vérifié : opérations refusées."; }
    }

    private static async Task<string> ReadBounded(StreamReader reader)
    {
        var value = new StringBuilder();
        var buffer = new char[256];
        int count;
        while ((count = await reader.ReadAsync(buffer).ConfigureAwait(false)) != 0)
        {
            if (value.Length + count > MaximumCharacters) throw new IOException("Réponse de sonde trop volumineuse.");
            value.Append(buffer, 0, count);
        }
        return value.ToString();
    }
}

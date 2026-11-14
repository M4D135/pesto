using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace Pesto.Engine.Live;

/// <summary>A short fixed bootstrap avoids Windows' command-line limit. Only the compiled script matching its embedded SHA runs.</summary>
internal static class PowerShellFixedWorker
{
    private const int MaximumScriptBytes = 256 * 1024;
    public static ProcessStartInfo StartInfo(string script)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            "System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
        {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = new UTF8Encoding(false),
            StandardErrorEncoding = new UTF8Encoding(false),
        };
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
            Convert.ToBase64String(Encoding.Unicode.GetBytes(Bootstrap(script))) }) start.ArgumentList.Add(argument);
        return start;
    }

    public static void Send(Process process, string script, string json)
    {
        var bytes = ScriptBytes(script);
        // Caller MUST attach its owned JobObject before this first byte. Worker reads only the remaining JSON.
        process.StandardInput.WriteLine(Convert.ToBase64String(bytes));
        process.StandardInput.Write(json); process.StandardInput.Close();
    }

    // Session startup sends only the verified script line before the acknowledgement and JSON frames.
    public static async Task SendScriptAsync(Process process, string script)
    {
        await process.StandardInput.WriteLineAsync(Convert.ToBase64String(ScriptBytes(script))).ConfigureAwait(false);
        await process.StandardInput.FlushAsync().ConfigureAwait(false);
    }

    public static string Bootstrap(string script)
    {
        var bytes = ScriptBytes(script); var hash = Convert.ToHexString(SHA256.HashData(bytes));
        return "# Pesto compiled worker\n$ErrorActionPreference='Stop'\n"
            + "[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)\n"
            + "[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)\n$line=[Console]::In.ReadLine()\n"
            + "if($null -eq $line -or $line.Length -gt " + ((MaximumScriptBytes + 2) / 3 * 4) + "){exit 96}\n"
            + "$bytes=[Convert]::FromBase64String($line)\nif($bytes.Length -gt " + MaximumScriptBytes + "){exit 96}\n"
            + "$digest=[Security.Cryptography.SHA256]::Create()\ntry{$actual=([BitConverter]::ToString($digest.ComputeHash($bytes))).Replace('-','')}finally{$digest.Dispose()}\n"
            + "if($actual -cne '" + hash + "'){exit 96}\n"
            + "$source=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)\n& ([ScriptBlock]::Create($source))\n";
    }

    private static byte[] ScriptBytes(string script)
    {
        var bytes = Encoding.UTF8.GetBytes(script);
        if (bytes.Length is < 1 or > MaximumScriptBytes) throw new InvalidOperationException("Script natif compilé hors limites.");
        return bytes;
    }
}

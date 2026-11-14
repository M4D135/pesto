using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

// Executes only a fixed echo fixture: no directory gateway, credentials, files or machine changes.
internal static class PowerShellUtf8Validation
{
    private const string Text = "Équipe été — 東京 € 🧪";
    private const string Input = "{\"text\":\"Équipe été — 東京 € 🧪\"}";
    private const string Script = """
        $ProgressPreference='SilentlyContinue'
        $j=[Console]::In.ReadToEnd()|ConvertFrom-Json
        [Console]::Error.Write('Équipe été — 東京 € 🧪')
        [ordered]@{input=$j.text;source='Équipe été — 東京 € 🧪';major=$PSVersionTable.PSVersion.Major;minor=$PSVersionTable.PSVersion.Minor}|ConvertTo-Json -Compress
        """;

    public static async Task<int> Run()
    {
        if (!OperatingSystem.IsWindows()) return 1;
        Console.OutputEncoding = new System.Text.UTF8Encoding(false);
        try
        {
            var output = await PowerShellTestWorker.Execute(Script, Script, Input);
            using var json = JsonDocument.Parse(output.Stdout);
            Check.Equal(0, output.Code, "Echo fixture exits normally");
            Check.Equal(5, json.RootElement.GetProperty("major").GetInt32(), "Windows PowerShell 5.1");
            Check.Equal(1, json.RootElement.GetProperty("minor").GetInt32(), "Windows PowerShell 5.1");
            Check.Equal(Text, json.RootElement.GetProperty("input").GetString(), "Literal UTF-8 input survives the fixed bootstrap");
            Check.Equal(Text, json.RootElement.GetProperty("source").GetString(), "Compiled Unicode source survives stdout");
            Check.Equal(Text, output.Stderr, "Unicode stderr survives the pipe");
            var rejected = await PowerShellTestWorker.Execute(Script, Script + "\n# changed body", Input);
            Check.Equal(96, rejected.Code, "Changed script refused by its compiled hash");
            Check.Equal("", rejected.Stdout, "Rejected body never executes");
            Check.Equal("", rejected.Stderr, "Rejected body never executes");
            Console.WriteLine(JsonSerializer.Serialize(new { success = true, checks = 2, powershell = "5.1", unicodeRoundTrip = true, substitutedBodyRejected = true, businessScriptsExecuted = false, adExecuted = false }));
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("ECHEC transport UTF-8 PS5.1 : " + error.Message);
            return 1;
        }
    }

}

internal static class PowerShellTestWorker
{
    internal static async Task<(int Code, string Stdout, string Stderr, int Pid)> Execute(string pinnedBody,
        string suppliedBody, string input, Action<ProcessStartInfo>? configure = null, int timeoutSeconds = 20)
    {
        var assembly = typeof(PowerShellMutationGateway).Assembly;
        var worker = assembly.GetType("Pesto.Engine.Live.PowerShellFixedWorker", true)!;
        var start = (ProcessStartInfo)worker.GetMethod("StartInfo", BindingFlags.Public | BindingFlags.Static)!.Invoke(null, [pinnedBody])!;
        configure?.Invoke(start);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("PowerShell fixture not started");
        using var job = (IDisposable)assembly.GetType("Pesto.Engine.Live.OwnedMutationJob", true)!
            .GetMethod("Attach", BindingFlags.Public | BindingFlags.Static)!.Invoke(null, [process])!;
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        worker.GetMethod("Send", BindingFlags.Public | BindingFlags.Static)!.Invoke(null, [process, suppliedBody, input]);
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(timeoutSeconds));
        await process.WaitForExitAsync(deadline.Token);
        return (process.ExitCode, await stdout, await stderr, process.Id);
    }
}

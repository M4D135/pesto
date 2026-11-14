using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Separate Windows-only syntax check. The parser receives source as data and never executes a business script.</summary>
internal static class PowerShellSyntaxValidation
{
    public static async Task<int> Run()
    {
        if (!OperatingSystem.IsWindows())
        {
            Console.Error.WriteLine("Windows PowerShell 5.1 requis : validation native de syntaxe non exécutée.");
            return 1;
        }
        try
        {
            var scripts = Sources();
            var input = JsonSerializer.Serialize(scripts.Select(x => new { name = x.Key, source = x.Value }));
            if (Encoding.UTF8.GetByteCount(input) > 4 * 1024 * 1024) throw new InvalidOperationException("Corpus de syntaxe hors limite.");
            var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
            {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = new UTF8Encoding(false),
                StandardErrorEncoding = new UTF8Encoding(false)
            };
            foreach (var value in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
                Convert.ToBase64String(Encoding.Unicode.GetBytes(ParserOnly)) }) start.ArgumentList.Add(value);
            using var process = Process.Start(start) ?? throw new InvalidOperationException("Parseur non démarré.");
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            await process.StandardInput.WriteAsync(input); process.StandardInput.Close();
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(45));
            try { await process.WaitForExitAsync(deadline.Token); }
            catch (OperationCanceledException)
            {
                try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { }
                throw new InvalidOperationException("Délai du seul processus parseur dépassé.");
            }
            var output = await stdout; var error = await stderr;
            if (output.Length > 512 * 1024 || error.Length > 16 * 1024) throw new InvalidOperationException("Réponse du parseur hors limite.");
            using var response = JsonDocument.Parse(output);
            var root = response.RootElement;
            var parsed = root.GetProperty("scripts").EnumerateArray().ToArray();
            Console.WriteLine(output.Trim());
            Console.WriteLine(JsonSerializer.Serialize(new { parserExitCode = process.ExitCode, stderrCharacters = error.Length,
                scriptCount = parsed.Length, expectedScriptCount = scripts.Count,
                namesMatch = parsed.Select(x => x.GetProperty("name").GetString()).SequenceEqual(scripts.Keys),
                stderr = error }));
            if (process.ExitCode != 0 || !string.IsNullOrWhiteSpace(error) || !root.GetProperty("success").GetBoolean()
                || root.GetProperty("powershellMajor").GetInt32() != 5 || root.GetProperty("powershellMinor").GetInt32() != 1
                || root.GetProperty("scriptsExecuted").GetBoolean() || parsed.Length != scripts.Count
                || !parsed.Select(x => x.GetProperty("name").GetString()).SequenceEqual(scripts.Keys))
                throw new InvalidOperationException("Syntaxe Windows PowerShell 5.1 non validée pour l’intégralité du corpus.");
            foreach (var source in scripts)
                Console.WriteLine($"SYNTAXE {source.Key} : {source.Value.Length} caractères ; SHA256 UTF8 {Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(source.Value))).ToLowerInvariant()}");
            Console.WriteLine($"{scripts.Count}/{scripts.Count} scripts compilés analysés par Windows PowerShell 5.1 ; aucune exécution de script métier, aucune qualification AD.");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("ECHEC validation syntaxe PS5.1 : " + error.Message);
            return 1;
        }
    }

    private static Dictionary<string, string> Sources()
    {
        const string machine = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", guid = "11111111-1111-1111-1111-111111111111";
        const string computer = "P111301PAINF009", newName = "P111301PAINF010", domain = "example.local";
        var now = new DateTimeOffset(2026, 10, 25, 12, 0, 0, TimeSpan.Zero);
        var entra = new EntraLeaveCommand("receipt-syntax", "plan-syntax", new string('b', 64),
            new("rename", computer, guid, newName, domain, "dc.example.local", "OU=Paris,OU=Postes,DC=example,DC=local", new string('a', 64)), machine, now);
        var restart = new RestartCommand("restart-1234567890abcdef1234567890abcdef", "receipt-syntax", new string('a', 64), "plan-syntax",
            computer, newName, domain, guid, machine, now.AddHours(-1), false, now, "rename", AuthorizationConfigurationSha256: new string('c', 64));
        var remote = new RemoteWindowsEvidenceRequest("receipt-syntax", computer, domain, "dc.example.local", guid,
            null, null, "baseline", computer, computer);
        var receiptType = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.PowerShellReceiptEvidence", throwOnError: true)!;
        return new()
        {
            ["directory"] = PowerShellDirectoryGateway.ConstantScript,
            ["mutation"] = PowerShellMutationGateway.ConstantScript,
            ["mutation-bootstrap"] = PowerShellMutationGateway.WorkerBootstrap,
            ["reservation"] = PowerShellMutationGateway.ReservationWorkerScript,
            ["receipt-evidence"] = (string)receiptType.GetProperty("ConstantScript", BindingFlags.Static | BindingFlags.Public)!.GetValue(null)!,
            ["remote-windows"] = RemoteWindowsDiagnosticTask.Script(remote, new string('b', 32)),
            ["entra-diagnostic"] = EntraDiagnosticTask.StatusScript(computer, domain),
            ["entra-leave"] = PowerShellEntraWorker.Build(entra),
            ["entra-inspection"] = PowerShellEntraWorker.Build(entra, inspect: true),
            ["restart-local"] = ReceiptRestartScript.LocalSource,
            ["restart-remote"] = ReceiptRestartScript.RemoteSource(restart),
            ["rename-fallback"] = PestoTaskFallbackRunner.RenameTaskScript(newName, @"C:\ProgramData\GP\Tasks\syntax.log"),
            ["audit"] = WindowsReceiptAuditSink.ConstantScript,
            ["attributes"] = PowerShellMutationGateway.AttributesWorkerScript,
            ["offline-local"] = WindowsOfflineJoinScripts.ReadLocal,
            ["offline-apply"] = WindowsOfflineJoinScripts.Apply,
            ["offline-observe"] = WindowsOfflineJoinScripts.Observe,
            ["acknowledgement-activity"] = (string)typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.WindowsAcknowledgementActivity", true)!
                .GetField("Script", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!
        };
    }

    private const string ParserOnly = """
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
[Console]::InputEncoding=[Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'Windows PowerShell 5.1 requis.'}
$items=ConvertFrom-Json -InputObject ([Console]::In.ReadToEnd())
if($items -isnot [Array] -or $items.Count -lt 1){throw 'Tableau de sources requis.'}
$results=[Collections.Generic.List[object]]::new()
$failed=0
foreach($item in $items){
  $tokens=$null;$errors=$null
  $null=[Management.Automation.Language.Parser]::ParseInput([string]$item.source,[ref]$tokens,[ref]$errors)
  $details=@($errors|ForEach-Object{[ordered]@{id=$_.ErrorId;line=$_.Extent.StartLineNumber;column=$_.Extent.StartColumnNumber;message=$_.Message}})
  if($details.Count -gt 0){$failed++}
  $results.Add([ordered]@{name=[string]$item.name;errors=$details})
}
$result=[ordered]@{schema=1;powershellMajor=$PSVersionTable.PSVersion.Major;powershellMinor=$PSVersionTable.PSVersion.Minor;scripts=$results.ToArray();scriptsExecuted=$false;adQualified=$false;success=($failed -eq 0 -and $items.Count -gt 0)}
[Console]::WriteLine(($result|ConvertTo-Json -Depth 8 -Compress))
if(-not $result.success){exit 1}
exit 0
""";
}

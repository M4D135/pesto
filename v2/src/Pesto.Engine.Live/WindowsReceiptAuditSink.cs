using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace Pesto.Engine.Live;

/// <summary>V1 Application/Pesto/1000 sink. The administrator provisions the source; Pesto never creates it.</summary>
public sealed class WindowsReceiptAuditSink : IReceiptAuditSink
{
    public const int TimeoutMilliseconds = 5000;
    public static string ConstantScript => Script;
    public ReceiptAuditEmission Write(ReceiptAuditEvent value)
    {
        if (!OperatingSystem.IsWindows() || WindowsPowerShellProbe.UnavailableReason is not null)
            return new(false, "audit.platform_unavailable");
        var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        var start = new ProcessStartInfo(executable)
        {
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            UseShellExecute = false, CreateNoWindow = true, StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = new UTF8Encoding(false)
        };
        foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
                     Convert.ToBase64String(Encoding.Unicode.GetBytes(Script)) }) start.ArgumentList.Add(argument);
        try
        {
            using var process = Process.Start(start);
            if (process is null) return new(false, "audit.unavailable");
            var output = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            process.StandardInput.Write(JsonSerializer.Serialize(value));
            process.StandardInput.Close();
            if (!process.WaitForExit(TimeoutMilliseconds))
            {
                try { process.Kill(entireProcessTree: true); } catch (Exception) { }
                return new(false, "audit.timeout"); // An event may be late: no retry and no claimed success.
            }
            var response = output.GetAwaiter().GetResult();
            _ = error.GetAwaiter().GetResult();
            return process.ExitCode == 0 && response.Trim() == "PESTO_AUDIT_WRITTEN"
                ? new(true) : new(false, "audit.source_unavailable");
        }
        catch (Exception) { return new(false, "audit.unavailable"); }
    }

    private const string Script = """
$ErrorActionPreference='Stop'
try{
  $json=[Console]::In.ReadToEnd()
  if($json.Length -gt 2048){throw 'Projection invalide.'}
  $j=$json|ConvertFrom-Json
  $expected=@('Schema','Product','OperationId','Kind','State','ResultCode','Sequence','UpdatedUtc')
  $names=@($j.PSObject.Properties.Name)
  if($names.Count -ne $expected.Count -or @($names|Where-Object{$_ -cnotin $expected}).Count -gt 0){throw 'Projection invalide.'}
  if($j.Schema -ne 1 -or $j.Product -cne 'Pesto' -or $j.OperationId -cnotmatch '^[0-9a-f]{32}$' -or $j.OperationId -eq ('0'*32)){throw 'Identité invalide.'}
  if($j.Kind -cnotin @('Join','Direct','Intervention') -or $j.State -cnotin @('Running','Failed','PendingRestart','Partial','MoveReady','Protection','Uncertain','NotStarted','Verified')){throw 'Etat invalide.'}
  if($j.ResultCode -isnot [int] -or $null -ne $j.Sequence -or $j.UpdatedUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$'){throw 'Résultat invalide.'}
  Write-EventLog -LogName 'Application' -Source 'Pesto' -EntryType 'Information' -EventId 1000 -Message $json -ErrorAction Stop
  [Console]::Out.Write('PESTO_AUDIT_WRITTEN')
}catch{exit 1}
""";
}

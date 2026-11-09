using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>Conservative local activity check. It never opens AD/SMB/HTTP and never stops a process.
/// Unreadable process identities or a Pesto/Entra worker still present cause refusal.</summary>
internal static class WindowsAcknowledgementActivity
{
    public static ReceiptAcknowledgementWorkerProof Read()
    {
        if (!OperatingSystem.IsWindows()) throw new PestoException("receipt.activity", "L’absence de worker doit être vérifiée nativement sous Windows.");
        var machine = Registry.GetValue(@"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography", "MachineGuid", null) as string;
        if (!Guid.TryParse(machine, out var machineId) || machineId == Guid.Empty)
            throw new PestoException("receipt.activity", "L’identité Windows de la machine est indisponible.");
        var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess ? "Sysnative" : "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = new UTF8Encoding(false) };
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand",
                     Convert.ToBase64String(Encoding.Unicode.GetBytes(Script)) }) start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new PestoException("receipt.activity", "Le contrôle local d’activité n’a pas démarré.");
        var stdout = process.StandardOutput.ReadToEndAsync(); var stderr = process.StandardError.ReadToEndAsync();
        if (!process.WaitForExit(15000))
            throw new PestoException("receipt.activity", "Le contrôle local d’activité n’a pas terminé. Aucun acquittement, aucun processus arrêté.");
        var text = stdout.GetAwaiter().GetResult(); _ = stderr.GetAwaiter().GetResult();
        if (process.ExitCode != 0 || text.Length is < 2 or > 4096)
            throw new PestoException("receipt.activity", "L’absence de worker n’a pas pu être prouvée.");
        using var document = JsonDocument.Parse(text); var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != 3
            || !root.TryGetProperty("schema", out var schema) || schema.ValueKind != JsonValueKind.Number || schema.GetInt32() != 1
            || !root.TryGetProperty("clear", out var clear) || clear.ValueKind != JsonValueKind.True
            || !root.TryGetProperty("observedUtc", out var at) || at.ValueKind != JsonValueKind.String
            || !DateTimeOffset.TryParse(at.GetString(), out var observed) || observed.Offset != TimeSpan.Zero
            || observed > DateTimeOffset.UtcNow || DateTimeOffset.UtcNow - observed > TimeSpan.FromSeconds(30))
            throw new PestoException("receipt.activity", "Un worker Pesto, une commande Entra ou une identité de processus inconnue conserve la barrière.");
        return new(machineId.ToString("D"), observed, true, "local-process-snapshot");
    }

    internal const string Script = """
$ErrorActionPreference='Stop'
try {
  $clear=$true
  $items=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='dsregcmd.exe'" -OperationTimeoutSec 8 -ErrorAction Stop)
  foreach($item in $items) {
    if([int]$item.ProcessId -eq $PID){continue}
    $line=[string]$item.CommandLine
    if(-not $line -or -not $item.CreationDate){$clear=$false;continue}
    if([string]$item.Name -ieq 'dsregcmd.exe'){
      if($line -match '(?i)(^|\s)/leave(\s|$)'){$clear=$false}
      continue
    }
    $body=$line
    if($line -match '(?i)-(?:EncodedCommand|enc|e)\s+["'']?([A-Za-z0-9+/=]+)'){
      try{$body=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($matches[1]))}
      catch{$clear=$false;continue}
    }
    if($body -match '(?i)Pesto|GP_PostMutation|\\GP\\|Add-Computer|Rename-Computer|Move-ADObject|New-ADComputer|Remove-ADComputer'){$clear=$false}
  }
  @{schema=1;clear=[bool]$clear;observedUtc=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Compress
  exit 0
}catch{exit 96}
""";
}

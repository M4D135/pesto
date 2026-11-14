using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using System.Xml.Linq;

namespace Pesto.Engine;

/// <summary>Connection credentials authenticate COM only; the diagnostic itself runs as local SYSTEM.</summary>
public interface ISystemDiagnosticTaskTransport : ITaskSchedulerTransport
{
    void RegisterSystem(string computer, string taskName, string xml, string connectionPrincipal, string connectionPassword);
}

public sealed record EntraDiagnosticResult(bool AdOnlyConfirmed, string Message, string TaskName, int? ResultCode, bool TaskStateUncertain);

/// <summary>
/// A single-use remote dsregcmd /status read. This runner cannot issue a rename, domain join, leave or restart.
/// All task effects have durable evidence and a unique name; uncertain runs are never repeated or deleted.
/// </summary>
public sealed class EntraDiagnosticTask(ISystemDiagnosticTaskTransport transport, string gpRoot, TimeProvider? clock = null,
    int timeoutSeconds = 90, int pollDelayMilliseconds = 500)
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private static readonly long[] InProgress = [267008, 267009, 267011];

    public EntraDiagnosticResult Read(string computer, string domain, string receiptId, PestoAdCredential credential)
    {
        var taskId = Guid.NewGuid().ToString("N")[..12];
        var taskName = "\\Pesto_EntraStatus_" + taskId;
        if (!Regex.IsMatch(computer, @"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$")
            || domain.Length > 253 || !Regex.IsMatch(domain, @"^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$") || !credential.IsAvailable)
            return new(false, "Cible ou compte du diagnostic Entra invalide : aucune tâche créée.", taskName, null, false);
        var principal = credential.UserName.Contains('\\') || credential.UserName.Contains('@') ? credential.UserName : credential.UserName + "@" + domain;
        const string command = "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
        var arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand "
            + Convert.ToBase64String(Encoding.Unicode.GetBytes(StatusScript(computer, domain)));
        var xml = TaskFallback.NewRunOnceTaskXml(command, arguments, "S-1-5-18", "ServiceAccount", "HighestAvailable", "Pesto - lecture seule du statut Entra")
            .Replace("<ExecutionTimeLimit>PT10M</ExecutionTimeLimit>", "<ExecutionTimeLimit>PT2M</ExecutionTimeLimit>", StringComparison.Ordinal);
        TaskEvidence evidence;
        try
        {
            evidence = new TaskEvidence(gpRoot, receiptId, taskId, clock, "entra-status-evidence", computer, taskName);
            evidence.Record("Registering");
        }
        catch (Exception) { return new(false, "Preuve du diagnostic Entra non enregistrable : aucune tâche créée.", taskName, null, false); }
        var registered = false;
        var runRequested = false;
        var finished = false;
        var validDefinition = false;
        var result = new EntraDiagnosticResult(false, "État Entra non confirmé : aucun renommage.", taskName, null, true);
        try
        {
            transport.RegisterSystem(computer, taskName, xml, principal, credential.TakePassword());
            registered = true;
            var initial = transport.Probe(computer, taskName);
            // Task Scheduler may normalize XML. Validate executable/principal/settings first, then bind all
            // later probes to the exact observed definition, as in V1 Get-PestoTaskDefinitionHash.
            ValidateDefinition(initial.DefinitionXml, command, arguments);
            if (initial.LastRunTime is { Year: >= 2000 }) throw new InvalidOperationException("La tâche de diagnostic a déjà été exécutée.");
            validDefinition = true;
            evidence.Record("Registered", TaskFallback.DefinitionHash(initial.DefinitionXml));
            evidence.AssertDefinition(transport.Probe(computer, taskName).DefinitionXml);
            evidence.Record("StartRequested");
            var started = clock.GetUtcNow();
            runRequested = true;
            transport.Run(computer, taskName);
            evidence.Record("Started");
            var deadline = started.AddSeconds(Math.Clamp(timeoutSeconds, 1, 120));
            for (var attempt = 0; attempt < 240; attempt++)
            {
                TaskProbeResult? probe = null;
                try { probe = transport.Probe(computer, taskName); }
                catch (Exception) { /* Transient read only; never rerun the task. */ }
                if (probe is not null)
                {
                    evidence.AssertDefinition(probe.DefinitionXml);
                    // Unique TASK_CREATE + no trigger + previously unrun definition establishes freshness.
                    // Comparing two machines' clocks would incorrectly reject a valid diagnostic on clock skew.
                    if (probe.State == 3 && probe.LastRunTime is { Year: >= 2000 } && !InProgress.Contains(probe.LastTaskResult))
                    {
                        finished = true;
                        evidence.Record("Finished", nativeCode: probe.LastTaskResult);
                        result = probe.LastTaskResult switch
                        {
                            0 => new(true, "État AD seul confirmé par dsregcmd /status sous SYSTEM sur la cible ; aucun retrait Entra.", taskName, 0, false),
                            43 => new(false, "Poste hybride Entra détecté (diagnostic 43) : aucun renommage ni retrait automatique.", taskName, 43, false),
                            44 => new(false, "Identité, rôle, domaine ou état Entra non confirmé par le diagnostic (44) : aucun renommage.", taskName, 44, false),
                            97 => new(false, "La lecture dsregcmd a expiré ou échoué (97) : aucun renommage, aucune conclusion supposée.", taskName, 97, false),
                            _ => new(false, "Code du diagnostic Entra non reconnu : aucun renommage.", taskName, null, false),
                        };
                        break;
                    }
                }
                if (clock.GetUtcNow() >= deadline) break;
                if (pollDelayMilliseconds > 0) Thread.Sleep(Math.Clamp(pollDelayMilliseconds, 1, 1000));
            }
            if (!finished) result = new(false, "Tâche de lecture Entra non confirmée terminée : " + taskName + ". Tâche conservée ; aucun renommage ni répétition automatique.", taskName, null, true);
        }
        catch (Exception)
        {
            result = new(false, (runRequested ? "Résultat de la tâche Entra incertain" : "Création ou définition du diagnostic Entra non confirmée")
                + " : " + taskName + ". Aucun renommage ; la preuve durable doit être vérifiée.", taskName, null, true);
        }
        if (registered && validDefinition && (finished || !runRequested))
        {
            try
            {
                var last = transport.Probe(computer, taskName);
                evidence.AssertDefinition(last.DefinitionXml);
                if (last.State is not (1 or 3)) throw new InvalidOperationException();
                transport.Delete(computer, taskName); // The native transport verifies absence before returning.
                evidence.Record("Deleted");
            }
            catch (Exception)
            {
                try { evidence.Record("DeleteFailed"); } catch (Exception) { }
                result = new(false, "Nettoyage de la tâche Entra non confirmé : " + taskName + ". Aucun renommage ; consulter sa preuve durable.", taskName, result.ResultCode, true);
            }
        }
        return result;
    }

    public static void ValidateDefinition(string xml, string command, string arguments)
    {
        if (xml.Length is 0 or > 131072) throw new InvalidOperationException("Définition de diagnostic invalide.");
        using var reader = XmlReader.Create(new StringReader(xml), new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
        var doc = XDocument.Load(reader);
        XNamespace ns = "http://schemas.microsoft.com/windows/2004/02/mit/task";
        var root = doc.Root;
        var actions = root?.Element(ns + "Actions")?.Elements().ToArray() ?? [];
        var principals = root?.Element(ns + "Principals")?.Elements().ToArray() ?? [];
        var settings = root?.Element(ns + "Settings");
        if (root?.Name != ns + "Task" || root.Elements(ns + "Triggers").Any(t => t.HasElements)
            || root.Elements(ns + "Actions").Count() != 1 || root.Elements(ns + "Principals").Count() != 1 || root.Elements(ns + "Settings").Count() != 1
            || actions.Length != 1 || actions[0].Name != ns + "Exec"
            || actions[0].Elements(ns + "Command").Count() != 1 || actions[0].Elements(ns + "Arguments").Count() != 1
            || actions[0].Elements().Any(e => e.Name != ns + "Command" && e.Name != ns + "Arguments" && e.Name != ns + "WorkingDirectory")
            || (string?)actions[0].Element(ns + "Command") != command || (string?)actions[0].Element(ns + "Arguments") != arguments
            || !string.IsNullOrEmpty((string?)actions[0].Element(ns + "WorkingDirectory"))
            || principals.Length != 1 || principals[0].Name != ns + "Principal" || principals[0].Element(ns + "GroupId") is not null
            || (string?)principals[0].Element(ns + "UserId") != "S-1-5-18"
            || (string?)principals[0].Element(ns + "RunLevel") != "HighestAvailable"
            || (string?)principals[0].Element(ns + "LogonType") is not (null or "ServiceAccount")
            || (string?)settings?.Element(ns + "MultipleInstancesPolicy") != "IgnoreNew"
            || (string?)settings?.Element(ns + "ExecutionTimeLimit") != "PT2M"
            || settings?.Element(ns + "RestartOnFailure") is not null
            || (string?)settings?.Element(ns + "AllowStartOnDemand") != "true")
            throw new InvalidOperationException("Le diagnostic n’a pas la définition SYSTEM sans déclencheur attendue.");
    }

    public static string StatusScript(string computer, string domain)
    {
        // Called only after strict target/domain validation; literals still escape apostrophes defensively.
        var expectedComputer = computer.Replace("'", "''", StringComparison.Ordinal);
        var expectedDomain = domain.Replace("'", "''", StringComparison.Ordinal);
        return "# Pesto diagnostic : lecture seule, retour 0 AD seul, 43 hybride, 44 identité/état inconnu, 97 délai.\r\n"
            + "$ErrorActionPreference='Stop'\r\n$p=$null\r\ntry{\r\n"
            + "  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()\r\n"
            + "  try{if($identity.User.Value -ne 'S-1-5-18'){exit 44}}finally{$identity.Dispose()}\r\n"
            + "  if($env:COMPUTERNAME -ine '" + expectedComputer + "'){exit 44}\r\n"
            + "  $cs=@(Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 10 -ErrorAction Stop)\r\n"
            + "  if($cs.Count -ne 1 -or $cs[0].Name -ine '" + expectedComputer + "' -or -not $cs[0].PartOfDomain -or $cs[0].DomainRole -notin @(1,3) -or $cs[0].Domain -ine '" + expectedDomain + "'){exit 44}\r\n"
            + "  $dir=if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){'Sysnative'}else{'System32'}\r\n"
            + "  $exe=Join-Path $env:SystemRoot ($dir+'\\dsregcmd.exe')\r\n"
            + "  if(-not [IO.File]::Exists($exe)){exit 44}\r\n"
            + "  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$exe;$start.Arguments='/status';$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true\r\n"
            + "  $p=[Diagnostics.Process]::new();$p.StartInfo=$start;if(-not $p.Start()){exit 97}\r\n"
            + "  $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()\r\n"
            + "  if(-not $p.WaitForExit(60000)){try{$p.Kill()}catch{};exit 97}\r\n"
            + "  $text=$stdout.GetAwaiter().GetResult();$null=$stderr.GetAwaiter().GetResult()\r\n"
            + "  if($p.ExitCode -ne 0 -or $text.Length -gt 65536){exit 97}\r\n"
            + "  $aad=[regex]::Matches($text,'(?im)^[ \\t]*AzureAdJoined[ \\t]*:[ \\t]*(YES|NO)[ \\t]*\\r?$')\r\n"
            + "  $dom=[regex]::Matches($text,'(?im)^[ \\t]*DomainJoined[ \\t]*:[ \\t]*(YES|NO)[ \\t]*\\r?$')\r\n"
            + "  if($aad.Count -ne 1 -or $dom.Count -ne 1 -or $dom[0].Groups[1].Value -ine 'YES'){exit 44}\r\n"
            + "  if($aad[0].Groups[1].Value -ieq 'YES'){exit 43}\r\n  exit 0\r\n"
            + "}catch{exit 97}finally{if($p){$p.Dispose()}}\r\n";
    }
}

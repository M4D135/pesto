using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace Pesto.Engine;

/// <summary>One authenticated SYSTEM task with an immutable script/nonce. A timeout never launches it again.</summary>
public sealed class EntraLeaveTask(ISystemDiagnosticTaskTransport transport, TimeProvider? clock = null,
    int timeoutSeconds = 450, int pollDelayMilliseconds = 500)
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private static readonly long[] InProgress = [267008, 267009, 267011];
    public static string TaskName(EntraLeaveCommand command) => "\\Pesto_EntraLeave_" + command.Nonce[..24];
    public static string WorkerArguments(string script) => "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand "
        + Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
    public static bool FitsNativeCommand(string executable, string arguments) =>
        arguments.Length is > 0 and <= 30000 && executable.Length + arguments.Length + 4 < 32767;

    public EntraLeaveNativeResult Run(EntraLeaveCommand command, string workerScript, PestoAdCredential credential,
        Action<string, string?, string?, long?> record)
    {
        EntraLeaveEvidence.Validate(command);
        if (!credential.IsAvailable) return new("NotRequested", false, "Compte AD explicite indisponible : aucun retrait.", 44);
        var name = TaskName(command);
        var principal = credential.UserName.Contains('\\') || credential.UserName.Contains('@')
            ? credential.UserName : credential.UserName + "@" + command.Request.Domain;
        const string executable = "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";
        var arguments = WorkerArguments(workerScript);
        if (!FitsNativeCommand(executable, arguments))
            return new("NotRequested", false, "La commande Entra dépasse la limite native Windows ; aucune tâche créée ni retrait lancé.", 44);
        var xml = TaskFallback.NewRunOnceTaskXml(executable, arguments, "S-1-5-18", "ServiceAccount", "HighestAvailable",
            "Pesto - retrait Entra explicitement confirmé, une seule fois");
        string? definition = null;
        var finished = false;
        long? nativeCode = null;
        try
        {
            record("TaskRegistering", name, null, null); // Durable before TASK_CREATE.
            transport.RegisterSystem(command.Request.Computer, name, xml, principal, credential.TakePassword());
            var initial = transport.Probe(command.Request.Computer, name);
            ValidateDefinition(initial.DefinitionXml, executable, arguments);
            if (initial.LastRunTime is { Year: >= 2000 }) throw new InvalidOperationException("Tâche déjà exécutée.");
            definition = TaskFallback.DefinitionHash(initial.DefinitionXml);
            record("TaskRegistered", name, definition, null);
            AssertSame(transport.Probe(command.Request.Computer, name), definition);
            record("TaskStartRequested", name, definition, null); // Durable before Run, including a lost reply.
            transport.Run(command.Request.Computer, name);
            record("TaskStarted", name, definition, null);
            var deadline = clock.GetUtcNow().AddSeconds(Math.Clamp(timeoutSeconds, 1, 480));
            for (var attempt = 0; attempt < 1200 && clock.GetUtcNow() < deadline; attempt++)
            {
                TaskProbeResult? probe = null;
                try { probe = transport.Probe(command.Request.Computer, name); } catch (Exception) { }
                if (probe is not null)
                {
                    AssertSame(probe, definition);
                    if (probe.State == 3 && probe.LastRunTime is { Year: >= 2000 } && !InProgress.Contains(probe.LastTaskResult))
                    {
                        nativeCode = probe.LastTaskResult; finished = true;
                        record("TaskFinished", name, definition, nativeCode);
                        break;
                    }
                }
                if (pollDelayMilliseconds > 0) Thread.Sleep(Math.Clamp(pollDelayMilliseconds, 1, 1000));
            }
            if (!finished) return new("Uncertain", true, "Tâche Entra non confirmée terminée ; preuve et tâche conservées, aucun renommage.", 97);
            // The fixed worker returns 42 only AFTER its target receipt and exact NO/YES read were flushed.
            var result = nativeCode switch
            {
                42 => new EntraLeaveNativeResult("Confirmed", false, "Retrait Entra confirmé ; réinscription hybride à vérifier séparément.", 42),
                44 => new("NotRequested", false, "Précontrôle Entra refusé avant tout retrait ; nouvel aperçu requis.", 44),
                _ => new("Uncertain", true, "Fin du travailleur observée, mais retrait ou processus natif non confirmé ; inspectez sa preuve.", 97)
            };
            if (nativeCode is 42 or 44)
            {
                try
                {
                    var last = transport.Probe(command.Request.Computer, name);
                    AssertSame(last, definition);
                    if (last.State is not (1 or 3)) throw new InvalidOperationException("Tâche redevenue active.");
                    transport.Delete(command.Request.Computer, name);
                    record("TaskDeleted", name, definition, nativeCode);
                }
                catch (Exception)
                {
                    try { record("TaskDeleteFailed", name, definition, nativeCode); } catch (Exception) { }
                    // Preserve the actual effect; cleanup uncertainty cannot turn a real leave into a refusal.
                    return new(result.Effect == "Confirmed" ? "Confirmed" : "Uncertain", true,
                        "Nettoyage de tâche Entra non confirmé ; aucun renommage, preuves conservées.", nativeCode);
                }
            }
            return result;
        }
        catch (Exception)
        {
            return new("Uncertain", true, "Création, lancement ou définition de la tâche Entra non confirmé ; aucun renommage ni nouvel essai.", 97);
        }
    }

    private static void AssertSame(TaskProbeResult probe, string definition)
    {
        if (!TaskFallback.DefinitionHash(probe.DefinitionXml).Equals(definition, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("La définition de la tâche Entra a changé.");
    }

    public static void ValidateDefinition(string xml, string command, string arguments)
    {
        if (xml.Length is 0 or > 131072) throw new InvalidOperationException("Définition Entra invalide.");
        using var reader = XmlReader.Create(new StringReader(xml), new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
        var doc = XDocument.Load(reader); XNamespace ns = "http://schemas.microsoft.com/windows/2004/02/mit/task";
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
            || (string?)settings?.Element(ns + "ExecutionTimeLimit") != "PT10M"
            || settings?.Element(ns + "RestartOnFailure") is not null
            || (string?)settings?.Element(ns + "AllowStartOnDemand") != "true")
            throw new InvalidOperationException("Définition SYSTEM Entra sans déclencheur requise.");
    }
}

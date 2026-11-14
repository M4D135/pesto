using System.Text;

namespace Pesto.Engine;

/// <summary>A separately confirmed, one-shot SYSTEM restart; registration and request are journalled before Run.</summary>
public sealed class RemoteRestartTask(ISystemDiagnosticTaskTransport transport, string gpRoot,
    TimeProvider? time = null, int timeoutSeconds = 60, int pollDelayMilliseconds = 500, Action<string>? protectJournal = null,
    Action? beforeRequest = null)
{
    private readonly TimeProvider clock = time ?? TimeProvider.System;
    public static string TaskName(RestartCommand command) => "\\Pesto_Restart_" + command.Id[8..20];

    public RestartNativeResult Run(RestartCommand command, PestoAdCredential credential)
    {
        try { ReceiptRestartRules.ValidateCommand(command); }
        catch (Exception) { return new("refused", "Demande de redémarrage invalide ; aucune tâche créée."); }
        if (command.LocalTarget || !credential.IsAvailable) return new("refused", "Compte ou cible de redémarrage distant indisponible ; aucune tâche créée.");
        try { beforeRequest?.Invoke(); }
        catch (Exception) { return new("refused", "La politique d’autorisation du redémarrage a changé : aucune tâche créée."); }
        var task = TaskName(command);
        var args = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand "
            + Convert.ToBase64String(Encoding.Unicode.GetBytes(ReceiptRestartScript.RemoteSource(command)));
        if (args.Length > 30000) return new("refused", "Le worker fixe dépasse la borne de commande Windows : aucune tâche créée.");
        var xml = TaskFallback.NewRunOnceTaskXml(RemoteWindowsDiagnosticTask.Command, args, "S-1-5-18", "ServiceAccount", "HighestAvailable", "Pesto - redémarrage explicitement confirmé")
            .Replace("<ExecutionTimeLimit>PT10M</ExecutionTimeLimit>", "<ExecutionTimeLimit>PT2M</ExecutionTimeLimit>", StringComparison.Ordinal);
        TaskEvidence evidence;
        try
        {
            var folder = Path.Combine(gpRoot, "V2", "tasks"); SharedCoordinationProtocol.RequireNoLinks(folder);
            Directory.CreateDirectory(folder); protectJournal?.Invoke(folder);
            evidence = new TaskEvidence(gpRoot, command.ReceiptId, command.Id[8..20], clock, "restart-request-evidence", command.Computer, task);
            evidence.Record("Registering");
        }
        catch (Exception) { return new("refused", "La preuve de tâche de redémarrage ne peut pas être enregistrée ; aucun envoi."); }
        var principal = credential.UserName.Contains('\\') || credential.UserName.Contains('@') ? credential.UserName : credential.UserName + "@" + command.Domain;
        var registered = false; var definitionConfirmed = false; var started = false; var finished = false; var admissionRefused = false;
        RestartNativeResult result = new("uncertain", "Réponse du redémarrage distant inconnue ; aucune nouvelle demande pour ce boot.");
        try
        {
            transport.RegisterSystem(command.Computer, task, xml, principal, credential.TakePassword()); registered = true;
            var first = transport.Probe(command.Computer, task);
            EntraDiagnosticTask.ValidateDefinition(first.DefinitionXml, RemoteWindowsDiagnosticTask.Command, args);
            if (first.LastRunTime is { Year: >= 2000 }) throw new IOException("Tâche déjà exécutée.");
            evidence.Record("Registered", TaskFallback.DefinitionHash(first.DefinitionXml)); definitionConfirmed = true;
            evidence.AssertDefinition(transport.Probe(command.Computer, task).DefinitionXml);
            try { beforeRequest?.Invoke(); }
            catch (Exception) { admissionRefused = true; throw; }
            evidence.Record("StartRequested"); started = true;
            transport.Run(command.Computer, task); evidence.Record("Started");
            var deadline = clock.GetUtcNow().AddSeconds(Math.Clamp(timeoutSeconds, 1, 90));
            for (var i = 0; i < 200; i++)
            {
                TaskProbeResult? current = null;
                try { current = transport.Probe(command.Computer, task); } catch (Exception) { }
                if (current is not null)
                {
                    evidence.AssertDefinition(current.DefinitionXml);
                    if (current.State == 3 && current.LastRunTime is { Year: >= 2000 } && current.LastTaskResult is not (267008 or 267009 or 267011))
                    {
                        evidence.Record("Finished", nativeCode: current.LastTaskResult); finished = true;
                        result = current.LastTaskResult switch
                        {
                            0 => new("accepted", "Windows a accepté la demande explicite de redémarrage. Le résultat du reçu métier reste inchangé ; vérifiez-le après le boot."),
                            96 => new("refused", "La tâche a prouvé un refus avant Restart-Computer : identité ou boot modifiés, aucun redémarrage envoyé."),
                            _ => new("uncertain", "La tâche n’a pas confirmé l’acceptation de Restart-Computer. Aucun second envoi pour ce boot."),
                        };
                        break;
                    }
                }
                if (clock.GetUtcNow() >= deadline) break;
                if (pollDelayMilliseconds > 0) Thread.Sleep(Math.Clamp(pollDelayMilliseconds, 1, 1000));
            }
        }
        catch (Exception)
        {
            result = admissionRefused && !started
                ? new("refused", "La politique a changé pendant les lectures du Planificateur : aucun lancement ni redémarrage envoyé.")
                : new("uncertain", started
                ? "Réponse interrompue après demande de lancement ; le poste peut redémarrer. Aucun second envoi pour ce boot."
                : "L’enregistrement de la tâche n’est pas complètement confirmé. Aucune demande de lancement n’a été répétée ; preuve conservée, vérification requise.");
        }
        if (registered && definitionConfirmed && (finished || !started))
        {
            try
            {
                var final = transport.Probe(command.Computer, task); evidence.AssertDefinition(final.DefinitionXml);
                if (final.State is not (1 or 3)) throw new IOException("Tâche encore active.");
                transport.Delete(command.Computer, task); evidence.Record("Deleted");
            }
            catch (Exception)
            {
                try { evidence.Record("DeleteFailed"); } catch (Exception) { }
                result = new("uncertain", result.Message + " Nettoyage de la tâche non confirmé ; preuve conservée, aucun second envoi.");
            }
        }
        return result;
    }
}

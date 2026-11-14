using System.Text;
using System.Text.Json;

namespace Pesto.Engine;

/// <summary>One explicitly requested SYSTEM reader. Business changes and arbitrary scripts are not accepted.</summary>
public sealed partial class RemoteWindowsDiagnosticTask(ISystemDiagnosticTaskTransport transport, IRemoteWindowsEvidenceFiles files,
    string gpRoot, TimeProvider? clock = null, int timeoutSeconds = 90, int pollDelayMilliseconds = 500, Action<string>? protectJournal = null)
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private static readonly long[] InProgress = [267008, 267009, 267011];
    public const string Command = "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe";

    public RemoteWindowsEvidenceResult Read(RemoteWindowsEvidenceRequest request, PestoAdCredential credential)
    {
        try { RemoteWindowsEvidenceProtocol.ValidateRequest(request); }
        catch (Exception) { return new(null, "Demande de preuve Windows invalide : aucune tâche créée.", false); }
        if (!credential.IsAvailable) return new(null, "Compte AD du diagnostic indisponible : aucune tâche créée.", false);
        var nonce = Guid.NewGuid().ToString("N");
        var taskName = RemoteWindowsEvidenceProtocol.TaskName(nonce);
        var script = Script(request, nonce);
        var arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " + Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        if (arguments.Length > 30000) return new(null, "Le lecteur fixe dépasse la borne de commande Windows : aucune tâche créée.", false, taskName);
        var xml = TaskFallback.NewRunOnceTaskXml(Command, arguments, "S-1-5-18", "ServiceAccount", "HighestAvailable", "Pesto - preuve Windows en lecture seule")
            .Replace("<ExecutionTimeLimit>PT10M</ExecutionTimeLimit>", "<ExecutionTimeLimit>PT2M</ExecutionTimeLimit>", StringComparison.Ordinal);
        var principal = credential.UserName.Contains('\\') || credential.UserName.Contains('@') ? credential.UserName : credential.UserName + "@" + request.Domain;
        TaskEvidence evidence;
        try
        {
            EnsureJournal();
            evidence = new TaskEvidence(gpRoot, request.ReceiptId, nonce[..12], clock, "windows-proof-evidence", request.Computer, taskName);
            // Request binding is durable before registration. This immutable journal contains no credential.
            SaveNew(request.ReceiptId, nonce, "request", new { Schema = 1, Request = request, Nonce = nonce, TaskName = taskName,
                RequestSha256 = RemoteWindowsEvidenceProtocol.RequestHash(request, nonce), CreatedUtc = clock.GetUtcNow() });
            evidence.Record("Registering");
        }
        catch (Exception) { return new(null, "Intention de diagnostic non enregistrable : aucune tâche créée.", false, taskName); }
        var registered = false; var runRequested = false; var finished = false; var definitionConfirmed = false;
        var definitionHash = ""; RemoteWindowsProof? proof = null; var message = "Preuve Windows non confirmée.";
        try
        {
            transport.RegisterSystem(request.Computer, taskName, xml, principal, credential.TakePassword()); registered = true;
            var first = transport.Probe(request.Computer, taskName);
            EntraDiagnosticTask.ValidateDefinition(first.DefinitionXml, Command, arguments);
            if (first.LastRunTime is { Year: >= 2000 }) throw new InvalidOperationException("Tâche déjà exécutée.");
            definitionHash = TaskFallback.DefinitionHash(first.DefinitionXml); definitionConfirmed = true;
            evidence.Record("Registered", definitionHash);
            evidence.AssertDefinition(transport.Probe(request.Computer, taskName).DefinitionXml);
            evidence.Record("StartRequested"); runRequested = true;
            var deadline = clock.GetUtcNow().AddSeconds(Math.Clamp(timeoutSeconds, 1, 110));
            transport.Run(request.Computer, taskName); evidence.Record("Started");
            for (var attempt = 0; attempt < 240; attempt++)
            {
                TaskProbeResult? current = null;
                try { current = transport.Probe(request.Computer, taskName); } catch (Exception) { }
                if (current is not null)
                {
                    evidence.AssertDefinition(current.DefinitionXml);
                    if (current.State == 3 && current.LastRunTime is { Year: >= 2000 } && !InProgress.Contains(current.LastTaskResult))
                    {
                        finished = true; evidence.Record("Finished", nativeCode: current.LastTaskResult);
                        if (current.LastTaskResult == 0)
                        {
                            var bytes = files.Read(request.Computer, nonce);
                            _ = RemoteWindowsEvidenceProtocol.ReadResult(request, nonce, bytes);
                            proof = new(1, request, nonce, taskName, definitionHash, RemoteWindowsEvidenceProtocol.Hash(bytes),
                                new UTF8Encoding(false, true).GetString(bytes), clock.GetUtcNow(), false);
                            _ = RemoteWindowsEvidenceProtocol.ValidateProof(proof, requireCleanup: false);
                            SaveNew(request.ReceiptId, nonce, "result", proof); // flushed before any remote deletion
                            evidence.Record("ResultSaved");
                            message = "Preuve Windows recueillie ; nettoyage à confirmer.";
                        }
                        else message = "Le diagnostic Windows a refusé ou n’a pas pu lire l’identité complète (code " + current.LastTaskResult + "). Aucune conclusion de réussite.";
                        break;
                    }
                }
                if (clock.GetUtcNow() >= deadline) break;
                if (pollDelayMilliseconds > 0) Thread.Sleep(Math.Clamp(pollDelayMilliseconds, 1, 1000));
            }
            if (!finished) message = "Fin du diagnostic Windows non confirmée : tâche et preuves conservées, aucune répétition automatique.";
        }
        catch (Exception)
        {
            message = runRequested ? "Résultat du diagnostic Windows incertain : tâche, résultat éventuel et preuve durable conservés."
                : "Création ou définition de la tâche Windows non confirmée : aucune preuve utilisable.";
            proof = null;
        }
        if (registered && definitionConfirmed && (finished || !runRequested))
        {
            try
            {
                var last = transport.Probe(request.Computer, taskName); evidence.AssertDefinition(last.DefinitionXml);
                if (last.State is not (1 or 3)) throw new InvalidOperationException("Tâche active ou inconnue.");
                if (proof is not null)
                {
                    files.DeleteExact(request.Computer, nonce, proof.ResultSha256);
                    evidence.Record("ResultDeleted");
                }
                transport.Delete(request.Computer, taskName); evidence.Record("Deleted");
                if (proof is not null)
                {
                    proof = proof with { CleanupConfirmed = true };
                    SaveNew(request.ReceiptId, nonce, "confirmed", proof);
                    return new(proof, "Identité Windows distante lue sous SYSTEM, résultat conservé localement et nettoyage confirmé.", false, taskName);
                }
            }
            catch (Exception)
            {
                try { evidence.Record("DeleteFailed"); } catch (Exception) { }
                return new(null, "Nettoyage du diagnostic Windows non confirmé : aucune preuve utilisée pour lever une barrière. Consultez la tâche " + taskName + ".", true, taskName);
            }
        }
        return new(null, message, !finished || proof is null && runRequested, taskName);
    }

    private void EnsureJournal()
    {
        if (!Path.IsPathFullyQualified(gpRoot) || gpRoot.StartsWith(@"\\", StringComparison.Ordinal)) throw new IOException("Registre local requis.");
        foreach (var part in new[] { Path.Combine(gpRoot, "V2", "tasks"), Path.Combine(gpRoot, "V2", "windows-proofs") })
        {
            SharedCoordinationProtocol.RequireNoLinks(part); Directory.CreateDirectory(part); protectJournal?.Invoke(part);
        }
    }

    private void SaveNew(string receiptId, string nonce, string stage, object value)
    {
        var path = Path.Combine(gpRoot, "V2", "windows-proofs", receiptId + "." + nonce + "." + stage + ".json");
        SharedCoordinationProtocol.RequireNoLinks(path);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(value);
        if (bytes.Length > 65536) throw new IOException("Preuve locale hors limites.");
        using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
        file.Write(bytes); file.Flush(true);
    }
}

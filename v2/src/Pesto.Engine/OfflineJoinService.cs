using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Closed local ODJ workflow. No platform call or file access takes place in the constructor.</summary>
public sealed class OfflineJoinService(string configurationPath, string gpRoot, ConfigurationAccessMode mode,
    IOfflineJoinPlatform platform, TimeProvider? clock = null) : IDisposable
{
    private readonly object gate = new();
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private readonly Dictionary<string, ApplyPlan> plans = [];
    private string? configurationStamp;
    private bool disposed;
    private OfflineJoinStore Store => new(gpRoot, mode, platform.SecureDirectory, clock);
    private sealed record ApplyPlan(string Id, string BlobId, string ImportedSha256, string ConfigurationSha256,
        string Computer, DateTimeOffset ExpiresUtc);

    public void InvalidatePlans() { lock (gate) plans.Clear(); }
    public void Dispose() { lock (gate) { if (disposed) return; disposed = true; plans.Clear(); platform.Dispose(); } }
    private void Guard() { OfflineJoinRules.Guard(mode); ObjectDisposedException.ThrowIf(disposed, this); }

    public JsonObject List()
    {
        lock (gate)
        {
            Guard(); var local = ReadLocal(); OfflineJoinConfiguration? configuration = null; string? reason = null;
            try
            {
                RequirePlatform(); configuration = ReadConfiguration();
                OfflineJoinRules.RequireLocal(local, clock.GetUtcNow());
                OfflineJoinRules.RequireAdmission(configuration, local.Computer!, configuration.Config.RootOu);
                RequireNoPendingMutation(local.Computer!);
            }
            catch (Exception error) { reason = SafeReason(error); }
            var items = new JsonArray();
            try
            {
                foreach (var id in Store.Ids())
                {
                    try { items.Add(Item(Store.Read(id) ?? throw Evidence(), configuration, local)); }
                    catch (Exception)
                    {
                        reason ??= "Un journal ODJ local est incomplet ; aucune nouvelle application.";
                        items.Add(new JsonObject { ["id"] = id, ["state"] = "Unreadable", ["replayAllowed"] = false,
                            ["canPrepare"] = false, ["canObserve"] = false, ["identityDeclared"] = true,
                            ["message"] = "Journal incomplet ou concurrent, conservé sans réparation ni rejeu." });
                    }
                }
            }
            catch (Exception) { reason ??= "Le registre ODJ local ne peut pas être lu complètement ; aucune application."; }
            return new JsonObject { ["available"] = reason is null, ["reason"] = reason, ["local"] = Local(local), ["items"] = items };
        }
    }

    public JsonObject Import(string selectedLocalPath, string objectGuid, string targetOU, bool confirmed)
    {
        lock (gate)
        {
            Guard(); MutationSessionGuard.RequireWritableSession();
            if (!confirmed) throw OfflineJoinRules.Refused("confirmation.required", "Confirmez l’import local et les références AD déclarées.");
            using var gp = EnterGp(); using var pin = PinConfiguration(out var configuration);
            RequirePlatform(); var local = ReadLocal(); OfflineJoinRules.RequireLocal(local, clock.GetUtcNow());
            if (!OfflineJoinRules.IsGuid(objectGuid)) throw OfflineJoinRules.Refused("offlineJoin.guid", "Le GUID AD provisionné doit être déclaré intégralement, sans valeur vide.");
            OfflineJoinRules.RequireAdmission(configuration, local.Computer!, targetOU); RequireNoPendingMutation(local.Computer!);
            byte[]? bytes = null; byte[]? encrypted = null;
            try
            {
                bytes = OfflineJoinStore.ReadBounded(selectedLocalPath, OfflineJoinRules.MaximumBlobBytes);
                encrypted = platform.ProtectBlob(bytes);
                if (encrypted.Length is < 1 or > OfflineJoinRules.MaximumSecretBytes) throw Evidence();
                var now = clock.GetUtcNow();
                var binding = new OfflineJoinBinding(OfflineJoinRules.Hash(bytes), local.Computer!, configuration.Config.Domain,
                    Guid.Parse(objectGuid).ToString("D"), targetOU, local.MachineId!, configuration.Sha256,
                    OfflineJoinRules.Hash(encrypted), now, now.AddHours(24), local.BootUtc!.Value, local.Domain!,
                    local.DomainRole!.Value, configuration.Policy.AuditEventLogEnabled);
                var snapshot = Store.Begin(binding); Store.WriteProtected(snapshot, encrypted);
                snapshot = Store.Append(snapshot, "Imported");
                return new JsonObject { ["status"] = "imported", ["item"] = Item(snapshot, configuration, local),
                    ["message"] = "Blob protégé localement avec DPAPI machine. Le fichier sélectionné reste intact ; GUID et OU restent déclarés jusqu’à l’observation après boot." };
            }
            catch (PestoException) { throw; }
            catch (Exception) { throw OfflineJoinRules.Refused("offlineJoin.import", "Import local non confirmé. Aucune application ; une éventuelle intention incomplète reste conservée."); }
            finally { if (bytes is not null) CryptographicOperations.ZeroMemory(bytes); if (encrypted is not null) CryptographicOperations.ZeroMemory(encrypted); }
        }
    }

    public JsonObject Prepare(string id)
    {
        lock (gate)
        {
            Guard(); MutationSessionGuard.RequireWritableSession(); using var gp = EnterGp();
            using var pin = PinConfiguration(out var configuration); RequirePlatform();
            var snapshot = Store.Read(id) ?? throw Evidence(); RequireImported(snapshot, configuration);
            var local = ReadLocal(); OfflineJoinRules.RequireLocal(local, clock.GetUtcNow(), snapshot.Event.Binding);
            OfflineJoinRules.RequireAdmission(configuration, local.Computer!, snapshot.Event.Binding.TargetOu);
            RequireNoPendingMutation(local.Computer!);
            var encrypted = Store.ReadProtected(snapshot.Event.Binding); CryptographicOperations.ZeroMemory(encrypted);
            var now = clock.GetUtcNow(); foreach (var stale in plans.Where(p => p.Value.ExpiresUtc <= now).Select(p => p.Key).ToArray()) plans.Remove(stale);
            if (plans.Count >= 64) throw OfflineJoinRules.Refused("offlineJoin.limit", "Trop de préparations locales ; fermez cette fenêtre avant de recommencer.");
            var expires = now.AddMinutes(5); if (expires > snapshot.Event.Binding.ExpiresUtc) expires = snapshot.Event.Binding.ExpiresUtc;
            var plan = new ApplyPlan("odj-plan-" + Guid.NewGuid().ToString("N"), id, snapshot.Sha256, configuration.Sha256, local.Computer!, expires);
            plans.Add(plan.Id, plan); var b = snapshot.Event.Binding;
            return new JsonObject
            {
                ["planId"] = plan.Id, ["id"] = id, ["kind"] = "offlineJoin", ["mode"] = "offline",
                ["computer"] = b.Computer, ["newName"] = b.Computer, ["domain"] = b.Domain, ["expectedAdGuid"] = b.ExpectedAdGuid,
                ["targetOU"] = b.TargetOu, ["confirmationName"] = b.Computer, ["expiresAt"] = expires.ToString("O"),
                ["requiresConfirmation"] = true, ["identityDeclared"] = true,
                ["warnings"] = new JsonArray("Le blob s’applique au nom Windows local actuel, affiché ici ; aucun renommage.",
                    "Le GUID et l’OU sont déclarés par l’opérateur ; leur existence sera prouvée après un nouveau démarrage.",
                    "Dès l’intention durable, ce blob ne peut plus être rejoué, même après interruption.",
                    "Aucun redémarrage implicite. Après redémarrage, Observez ce reçu pour vérifier le canal sécurisé et l’identité AD.")
            };
        }
    }

    public JsonObject Apply(string planId, string confirmationName, bool confirmed)
    {
        lock (gate)
        {
            Guard(); MutationSessionGuard.RequireWritableSession();
            if (!confirmed) throw OfflineJoinRules.Refused("confirmation.required", "Confirmez explicitement l’application unique du blob ODJ.");
            if (!plans.TryGetValue(planId, out var plan) || plan.ExpiresUtc <= clock.GetUtcNow())
                throw OfflineJoinRules.Refused("offlineJoin.plan", "La préparation ODJ est absente, expirée ou consommée.");
            if (!string.Equals(confirmationName, plan.Computer, StringComparison.Ordinal))
                throw OfflineJoinRules.Refused("confirmation.name", "Le nom confirmé ne correspond pas au nom local du plan. Préparez de nouveau l’application.");
            using var gp = EnterGp(); using var pin = PinConfiguration(out var configuration); RequirePlatform();
            if (configuration.Sha256 != plan.ConfigurationSha256) throw Changed();
            var snapshot = Store.Read(plan.BlobId) ?? throw Evidence(); RequireImported(snapshot, configuration);
            if (snapshot.Sha256 != plan.ImportedSha256) throw Changed();
            var baseline = ReadLocal(); OfflineJoinRules.RequireLocal(baseline, clock.GetUtcNow(), snapshot.Event.Binding);
            OfflineJoinRules.RequireAdmission(configuration, baseline.Computer!, snapshot.Event.Binding.TargetOu);
            RequireNoPendingMutation(baseline.Computer!);
            byte[]? encrypted = null; byte[]? plaintext = null; string? mirrorSha256 = null; var requested = false;
            var mayRun = false; var receiptId = "receipt-" + Guid.NewGuid().ToString("N");
            try
            {
                encrypted = Store.ReadProtected(snapshot.Event.Binding); plaintext = platform.UnprotectBlob(encrypted);
                if (plaintext.Length is < 1 or > OfflineJoinRules.MaximumBlobBytes || OfflineJoinRules.Hash(plaintext) != plan.BlobId) throw Evidence();
                plans.Remove(planId);
                snapshot = Store.Append(snapshot, "Requested", receiptId, planId, baseline: baseline); requested = true;
                mirrorSha256 = WriteReceipt(snapshot, null);
                snapshot = Store.Append(snapshot, "Requested", workerMayRun: true, sourceReceiptSha256: mirrorSha256);
                Store.WritePlain(snapshot.Event.Binding, plaintext);
                using var plainPin = new FileStream(Store.PlainPath(plan.BlobId), FileMode.Open, FileAccess.Read, FileShare.Read);
                var finalConfiguration = ReadConfiguration();
                if (finalConfiguration.Sha256 != plan.ConfigurationSha256 || plan.ExpiresUtc <= clock.GetUtcNow()) throw Changed();
                OfflineJoinRules.RequireAdmission(finalConfiguration, baseline.Computer!, snapshot.Event.Binding.TargetOu);
                MutationSessionGuard.RequireWritableSession(); mayRun = true;
                var native = platform.Apply(new(snapshot.Event.Binding, receiptId, planId, snapshot.Sha256, snapshot.Event.Utc, baseline, plan.ExpiresUtc));
                mayRun = native.WorkerMayRun;
                var phase = native.Started && native.NativeCode == 0 && !mayRun ? "PendingRestart" : "Uncertain";
                snapshot = Store.Append(snapshot, phase, nativeCode: native.NativeCode, workerMayRun: mayRun, sourceReceiptSha256: mirrorSha256);
                mirrorSha256 = WriteReceipt(snapshot, mirrorSha256);
                plainPin.Dispose();
                var cleanup = !mayRun ? Cleanup(snapshot.Event.Binding) : "Le secret reste protégé tant que la fin du worker n’est pas prouvée.";
                return Result(snapshot, configuration, ReadLocal(), null, cleanup);
            }
            catch (Exception error)
            {
                if (!requested) { if (error is PestoException) throw; throw OfflineJoinRules.Refused("offlineJoin.prepare_failed", "La preuve ou le secret local ne permet pas l’application ; aucune commande envoyée."); }
                try
                {
                    snapshot = Store.Append(snapshot, "Uncertain", workerMayRun: mayRun, sourceReceiptSha256: mirrorSha256);
                    if (mirrorSha256 is not null) _ = WriteReceipt(snapshot, mirrorSha256);
                }
                catch (Exception) { /* Preserve both exact prior files and the consumed intent; never overwrite a concurrent mirror. */ }
                throw OfflineJoinRules.Refused("offlineJoin.uncertain", "Intention ODJ durable, résultat ou enregistrement final non confirmé. Le blob reste consommé ; observez après redémarrage, sans nouvel envoi.");
            }
            finally { if (encrypted is not null) CryptographicOperations.ZeroMemory(encrypted); if (plaintext is not null) CryptographicOperations.ZeroMemory(plaintext); }
        }
    }

    public JsonObject Observe(string id)
    {
        lock (gate)
        {
            Guard(); MutationSessionGuard.RequireWritableSession(); using var gp = EnterGp(); RequirePlatform();
            using var pin = PinConfiguration(out var configuration); var snapshot = Store.Read(id) ?? throw Evidence();
            if (snapshot.Event.State is "Importing" or "Imported") throw OfflineJoinRules.Refused("offlineJoin.not_applied", "Ce blob n’a pas été appliqué ; aucune observation AD.");
            if (!OfflineJoinRules.Same(snapshot.Event.Binding.Domain, configuration.Config.Domain)) throw Changed();
            var mirror = ReadLinkedReceipt(snapshot); var local = ReadLocal();
            if (OfflineJoinRules.LocalObservationRefusal(snapshot.Event.Binding, local, clock.GetUtcNow(), snapshot.Event.Baseline?.BootUtc) is { } refusal)
                return Result(snapshot, configuration, local, false, refusal);
            var observation = platform.Observe(snapshot.Event.Binding);
            if (ReadConfiguration().Sha256 != configuration.Sha256) throw Changed();
            var reason = OfflineJoinRules.ObservationRefusal(snapshot.Event.Binding, observation, clock.GetUtcNow(), snapshot.Event.Baseline?.BootUtc);
            if (snapshot.Event.State == "Verified" && reason is not null)
                return Result(snapshot, configuration, observation.Local, false, "La preuve historique reste conservée. " + reason);
            snapshot = Store.Append(snapshot, reason is null ? "Verified" : "Uncertain", workerMayRun: false,
                observation: observation, sourceReceiptSha256: mirror);
            _ = WriteReceipt(snapshot, mirror);
            return Result(snapshot, configuration, observation.Local, reason is null,
                reason ?? Cleanup(snapshot.Event.Binding));
        }
    }

    private string ReadLinkedReceipt(OfflineJoinSnapshot head)
    {
        var path = Store.ReceiptPath(head.Event.ReceiptId!); OfflineJoinStore.RequirePlain(path);
        // A crash between the immutable intent and the first mirror is recoverable only by creating an absent
        // projection. A disappeared/replaced mirror whose exact hash was already recorded is never repaired.
        if (!File.Exists(path) && head.Event.SourceReceiptSha256 is null) return WriteReceipt(head, null);
        var bytes = OfflineJoinStore.ReadBounded(path, 65536);
        using var parsed = JsonDocument.Parse(bytes); OfflineJoinStore.RequireUnique(parsed.RootElement);
        var root = parsed.RootElement;
        var eventSha = root.TryGetProperty("OfflineJoinSha256", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
        if (!OfflineJoinRules.IsHash(eventSha)) throw Evidence();
        var linked = Store.ReadEvent(head.Event.Binding.Id, eventSha!) ?? throw Evidence();
        var hash = OfflineJoinRules.Hash(bytes);
        if (!OfflineJoinReceipt.Matches(linked, root) || linked.Event.ReceiptId != head.Event.ReceiptId
            || eventSha != head.Sha256 && hash != head.Event.SourceReceiptSha256) throw Evidence();
        return hash;
    }

    private string WriteReceipt(OfflineJoinSnapshot snapshot, string? expectedSha256)
    {
        var path = Store.ReceiptPath(snapshot.Event.ReceiptId!); var folder = Path.GetDirectoryName(path)!;
        OfflineJoinStore.RequirePlain(folder); Directory.CreateDirectory(folder); platform.SecureDirectory(folder);
        var json = OfflineJoinReceipt.Create(snapshot).ToJsonString(); var bytes = Encoding.UTF8.GetBytes(json);
        var temporary = Path.Combine(folder, ".odj-" + Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            OfflineJoinStore.WriteNew(temporary, bytes); OfflineJoinStore.RequirePlain(path);
            if (expectedSha256 is null)
            {
                if (File.Exists(path)) throw Changed();
                File.Move(temporary, path, overwrite: false);
            }
            else
            {
                if (OfflineJoinRules.Hash(OfflineJoinStore.ReadBounded(path, 65536)) != expectedSha256) throw Changed();
                File.Move(temporary, path, overwrite: true);
            }
            var hash = OfflineJoinRules.Hash(bytes);
            if (OfflineJoinRules.Hash(OfflineJoinStore.ReadBounded(path, 65536)) != hash) throw Changed();
            try { platform.Audit(snapshot.Event.Binding.AuditEventLogEnabled, json); } catch (Exception) { }
            return hash;
        }
        finally { if (File.Exists(temporary)) { try { File.Delete(temporary); } catch (Exception) { } } }
    }

    private string? Cleanup(OfflineJoinBinding binding)
    {
        var failed = false;
        foreach (var (path, hash) in new[] { (Store.PlainPath(binding.Id), binding.Id), (Store.ProtectedPath(binding.Id), binding.ProtectedSha256) })
        {
            try { OfflineJoinStore.RequirePlain(path); if (File.Exists(path)) platform.DeleteExact(path, hash); }
            catch (Exception) { failed = true; }
        }
        return failed ? "Le résultat durable est conservé, mais le nettoyage exact du secret local reste à vérifier ; aucune suppression d’un fichier modifié." : null;
    }

    private void RequireImported(OfflineJoinSnapshot value, OfflineJoinConfiguration configuration)
    {
        if (value.Event.State != "Imported") throw OfflineJoinRules.Refused("offlineJoin.consumed", "Ce blob n’est plus un import disponible ; aucune répétition, même après interruption.");
        if (value.Event.Binding.ConfigurationSha256 != configuration.Sha256 || value.Event.Binding.ExpiresUtc <= clock.GetUtcNow()) throw Changed();
    }
    private OfflineJoinConfiguration ReadConfiguration()
    {
        var bytes = OfflineJoinStore.ReadBounded(configurationPath, ConfigurationDocument.MaximumBytes);
        return AcceptConfiguration(bytes);
    }
    private FileStream PinConfiguration(out OfflineJoinConfiguration configuration)
    {
        OfflineJoinStore.RequirePlain(configurationPath);
        var stream = new FileStream(configurationPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
            if (stream.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw Evidence();
            var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes); configuration = AcceptConfiguration(bytes); return stream;
        }
        catch { stream.Dispose(); throw; }
    }
    private OfflineJoinConfiguration AcceptConfiguration(byte[] bytes)
    {
        var value = OfflineJoinRules.ReadConfiguration(bytes, platform.ReadManagedPolicy());
        if (configurationStamp != value.Sha256) { plans.Clear(); configurationStamp = value.Sha256; }
        return value;
    }

    private void RequireNoPendingMutation(string computer)
    {
        if (OfflineJoinStore.RefusalForMutation(gpRoot, computer, localTarget: true) is { } reason) throw OfflineJoinRules.Refused("offlineJoin.barrier", reason);
        OfflineJoinStore.RequirePlain(gpRoot);
        foreach (var folder in new[] { Path.Combine(gpRoot, "Interventions"), Path.Combine(gpRoot, "V2", "receipts") }) OfflineJoinStore.RequirePlain(folder);
        var history = GpHistory.Read(gpRoot);
        if (!history.Available || history.InvalidCount != 0 || history.Truncated) throw OfflineJoinRules.Refused("offlineJoin.barrier", "L’historique GP est incomplet ou illisible ; aucune application ODJ.");
        if (history.Entries.Any(entry => !entry.Acknowledged && (OfflineJoinRules.Same(entry.Receipt.Computer, computer)
            || OfflineJoinRules.Same(entry.Receipt.NewName, computer)) && entry.Receipt.Status is not ("succeeded" or "refused")))
            throw OfflineJoinRules.Refused("offlineJoin.barrier", "Un reçu antérieur de ce poste reste non résolu ; aucune application ODJ.");
        foreach (var store in new[] { "direct", "join" })
        {
            var path = ReceiptAcknowledgementSource.ReceiptPath(gpRoot, store, "00000000000000000000000000000001");
            OfflineJoinStore.RequirePlain(path); if (!File.Exists(path)) continue;
            var bytes = OfflineJoinStore.ReadBounded(path, ReceiptAcknowledgementSource.MaximumBytes);
            using var document = JsonDocument.Parse(bytes); OfflineJoinStore.RequireUnique(document.RootElement);
            if (!document.RootElement.TryGetProperty("OperationId", out var value) || value.ValueKind != JsonValueKind.String
                || !Guid.TryParse(value.GetString(), out var id) || id == Guid.Empty) throw Evidence();
            var target = ReceiptAcknowledgementSource.ReadTarget(gpRoot, store, id.ToString("N"));
            if (!target.Acknowledged && target.Target.Phase is not ("Failed" or "Verified" or "NotStarted")
                && ReceiptAcknowledgementStore.TryReadForReceipt(gpRoot, path, bytes) is null)
                throw OfflineJoinRules.Refused("offlineJoin.barrier", "Un reçu local V1 reste non résolu ; aucune application ODJ.");
        }
    }

    private OfflineJoinLocalState ReadLocal()
    {
        try { return platform.ReadLocal(); } catch (Exception) { return OfflineJoinLocalState.Unknown("Identité locale non observée ; aucun état supposé."); }
    }
    private void RequirePlatform()
    {
        if (platform.UnavailableReason is { } reason) throw OfflineJoinRules.Refused("offlineJoin.platform", reason);
    }
    private JsonObject Item(OfflineJoinSnapshot snapshot, OfflineJoinConfiguration? configuration, OfflineJoinLocalState local)
    {
        var e = snapshot.Event; var b = e.Binding; var canPrepare = false;
        if (configuration is not null)
        {
            try { RequireImported(snapshot, configuration); OfflineJoinRules.RequireLocal(local, clock.GetUtcNow(), b);
                OfflineJoinRules.RequireAdmission(configuration, b.Computer, b.TargetOu);
                var encrypted = Store.ReadProtected(b); CryptographicOperations.ZeroMemory(encrypted); canPrepare = true; }
            catch (Exception) { }
        }
        return new JsonObject
        {
            ["id"] = b.Id, ["state"] = e.State, ["receiptId"] = e.ReceiptId, ["domain"] = b.Domain, ["computer"] = b.Computer,
            ["expectedAdGuid"] = b.ExpectedAdGuid, ["targetOU"] = b.TargetOu, ["importedAt"] = b.ImportedUtc.ToString("O"),
            ["expiresAt"] = b.ExpiresUtc.ToString("O"), ["nativeCode"] = e.NativeCode, ["restartRequired"] = e.State == "PendingRestart",
            ["replayAllowed"] = false, ["canPrepare"] = canPrepare,
            ["canObserve"] = e.State is "Requested" or "PendingRestart" or "Uncertain" or "Verified",
            ["identityDeclared"] = e.State != "Verified", ["message"] = OfflineJoinReceipt.Message(e.State)
        };
    }
    private JsonObject Result(OfflineJoinSnapshot snapshot, OfflineJoinConfiguration configuration, OfflineJoinLocalState local, bool? verified, string? detail)
    {
        var result = new JsonObject { ["item"] = Item(snapshot, configuration, local), ["receipt"] = OfflineJoinReceipt.Public(snapshot),
            ["message"] = OfflineJoinReceipt.Message(snapshot.Event.State) + (detail is null ? "" : " " + detail) };
        if (verified is not null) result["verified"] = verified.Value;
        return result;
    }
    private static JsonObject Local(OfflineJoinLocalState value) => new()
    {
        ["computer"] = value.Computer, ["activeName"] = value.ActiveName, ["configuredName"] = value.ConfiguredName,
        ["machineId"] = value.MachineId, ["domain"] = value.Domain, ["partOfDomain"] = value.PartOfDomain,
        ["domainRole"] = value.DomainRole, ["bootUtc"] = value.BootUtc?.ToString("O"), ["administrator"] = value.Administrator, ["error"] = value.Error
    };
    private static string SafeReason(Exception error) => error is PestoException ? error.Message : "Configuration ou preuves locales ODJ indisponibles ; aucune application.";
    private static PestoException Evidence() => OfflineJoinRules.Refused("offlineJoin.evidence", "Les preuves ODJ sont absentes, incohérentes ou concurrentes ; aucun remplacement ni rejeu.");
    private static PestoException Changed() => OfflineJoinRules.Refused("offlineJoin.changed", "La préparation, la configuration ou la preuve locale a changé ou expiré ; aucun envoi ni remplacement.");
    private static GpLease EnterGp() => new();
    private sealed class GpLease : IDisposable
    {
        private readonly Mutex mutex = new(false, OfflineJoinRules.MutexName);
        public GpLease()
        {
            bool acquired;
            try { acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
            if (!acquired) { mutex.Dispose(); throw OfflineJoinRules.Refused("offlineJoin.busy", "Une autre mutation détient le mutex GP ; aucune préparation ni application concurrente."); }
        }
        public void Dispose() { try { mutex.ReleaseMutex(); } finally { mutex.Dispose(); } }
    }
}

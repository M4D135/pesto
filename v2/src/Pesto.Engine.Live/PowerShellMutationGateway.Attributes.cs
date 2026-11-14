using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Principal;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IMutationAttributes
{
    private sealed record AttributeConfiguration(string Path, string Json, string Sha256, string Domain, string RootOu);
    private readonly object attributeGate = new();
    private readonly Dictionary<string, AttributeSnapshot> attributeProofs = new(StringComparer.Ordinal);
    private readonly Dictionary<string, AttributeObservation> attributeObservations = new(StringComparer.Ordinal);
    public static string AttributesWorkerScript => PowerShellAttributeWorker.Source;

    private AttributeConfiguration ReadAttributeConfiguration()
    {
        if (unavailableReason is not null) throw new PestoException("attributes.unavailable", unavailableReason);
        if (v1InstallationPath is null) throw AttributeMutationRules.Refused("Configuration des attributs absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json"); RequireNoReparsePoint(path);
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw AttributeMutationRules.Refused("Configuration illisible.");
        var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes);
        using var memory = new MemoryStream(bytes); using var reader = new StreamReader(memory, Encoding.UTF8, true);
        var json = reader.ReadToEnd(); AttributeMutationRules.RequireLiveConfiguration(json);
        var policy = JoinReservationPolicy.Read(json);
        return new(path, json, ReceiptAcknowledgementSource.Digest(bytes), policy.Domain, policy.RootOu);
    }
    public AttributeSnapshot ReadAttributes(AttributeTarget target)
    {
        var configuration = ReadAttributeConfiguration(); AttributeMutationRules.RequireConfiguration(configuration.Json, target, mutation: false);
        var result = RunAttributes("inspect", configuration, target.Domain, target.Dc, target);
        if (result.State != "inspected" || result.Snapshot is null) throw AttributeMutationRules.Refused("La lecture AD exacte des attributs est indisponible ou la cible a changé.");
        AttributeMutationRules.RequireSnapshot(result.Snapshot, target); return result.Snapshot;
    }
    public AttributeReference ResolveAttributeReference(string domain, string dc, string distinguishedName)
    {
        var configuration = ReadAttributeConfiguration();
        AttributeMutationRules.RequireValue(distinguishedName);
        if (!AttributeMutationRules.Same(configuration.Domain, domain) || !AttributeMutationRules.InDomain(distinguishedName, domain)
            || !JoinClockGuard.IsServer(dc) || AttributeMutationRules.Same(dc, domain) || !dc.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase))
            throw AttributeMutationRules.Refused("La référence managedBy sort du domaine/DC configuré.");
        var result = RunAttributes("reference", configuration, domain, dc, referenceDn: distinguishedName);
        if (result.State != "reference" || result.Reference is null) throw AttributeMutationRules.Refused("La référence managedBy ne peut pas être confirmée.");
        AttributeMutationRules.RequireReference(result.Reference, domain, distinguishedName); return result.Reference;
    }
    private AttributeNativeResult RunAttributes(string operation, AttributeConfiguration configuration, string domain, string dc,
        AttributeTarget? target = null, IReadOnlyList<AttributeChange>? changes = null, string? referenceDn = null)
    {
        var module = ResolveAdModulePath() ?? throw AttributeMutationRules.Refused("Module ActiveDirectory vérifié absent.");
        return PowerShellAttributeWorker.Run(operation, domain, dc, target, changes, referenceDn, module,
            (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload(), configuration.Path, configuration.Sha256,
            configuration.RootOu, operation == "apply" ? ReadPolicyRequirements().ExcludedGroupGuids : []);
    }

    /// <summary>Called only from Execute after GP, pinned configuration, policy and all ordinary receipt barriers.</summary>
    private MutationOutcome SendAttributes(MutationRequest request)
    {
        AttributeMutationRules.RequireRequest(request); var plan = request.Attributes!;
        AttributeConfiguration configuration; AttributeSnapshot before;
        try
        {
            if (Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1") return Refused(96, "La consultation interdit la modification des attributs.");
            configuration = ReadAttributeConfiguration();
            if (!AttributeMutationRules.Same(configuration.Sha256, request.ConfigurationSha256)) return Refused(96, "Configuration changée depuis le plan attributs.");
            AttributeMutationRules.RequireConfiguration(configuration.Json, plan.Target, mutation: true);
            before = ReadAttributes(plan.Target);
            if (!AttributeMutationRules.BeforeMatches(plan, before)) return Refused(96, "Anciennes valeurs changées ; aucune modification envoyée.");
            foreach (var change in plan.Changes.Where(c => !string.IsNullOrEmpty(c.ReferenceGuid)))
            {
                var reference = ResolveAttributeReference(request.Domain, request.Dc!, change.After);
                if (!AttributeMutationRules.Same(reference.Guid, change.ReferenceGuid)) return Refused(96, "Référence managedBy remplacée ; aucune modification envoyée.");
            }
            if (GroupExclusionRefusal(request) is { } group) return group;
        }
        catch (Exception) { return Refused(96, "Identité, valeurs, configuration ou référence managedBy non confirmées : aucune modification envoyée."); }

        string path;
        try
        {
            var baseline = new NativeReceiptSnapshot(null, null, null, null, null, null, null,
                plan.Target.ComputerGuid, plan.Target.Computer, plan.Target.Ou, null, null, false);
            path = WritePreSendReceipt(request, baseline); // Includes the exact diff + Requested, flushed before shared/native IO.
            if (ConfiguredPolicyRefusal(request) is { } changed) return Refused(96, changed);
            AcquireCoordination(request, path); VerifyCoordinationBeforeSend(request);
            if (GroupExclusionRefusal(request) is { } group) { AbortCoordinationBeforeSend(request); return group; }
            if (!AttributeMutationRules.BeforeMatches(plan, ReadAttributes(plan.Target)))
            { AbortCoordinationBeforeSend(request); return Refused(96, "Les valeurs ont changé pendant la coordination ; aucun envoi."); }
        }
        catch (Exception)
        {
            try { AbortCoordinationBeforeSend(request); } catch (Exception) { }
            return Refused(96, "Le reçu préalable ou la coordination ne peut pas être conservé : aucune modification envoyée.");
        }

        // The worker repeats identity/role/group/Before/reference checks immediately before its sole Set-ADObject.
        AttributeNativeResult native;
        try { native = RunAttributes("apply", configuration, request.Domain, request.Dc!, plan.Target, plan.Changes); }
        catch (Exception) { native = new("uncertain", "La réponse native est inconnue ; aucun rejeu.", MutationMayHaveStarted: true); }
        if (native.Snapshot is { } snapshot)
        {
            lock (attributeGate)
            {
                if (attributeProofs.Count >= 128) attributeProofs.Remove(attributeProofs.Keys.First());
                attributeProofs[request.ReceiptId] = snapshot;
            }
        }
        var outcome = native.State == "refused" && !native.MutationMayHaveStarted ? Refused(96, native.Message)
            : native.State == "verified" && native.MutationMayHaveStarted && native.Snapshot is { } after && AttributeMutationRules.AfterMatches(plan, after)
                ? new MutationOutcome(MutationStatus.Succeeded, 30, "Attributs relus par GUID après la commande native.", false, plan.Target.ComputerGuid)
                : new MutationOutcome(MutationStatus.Uncertain, 97, "Modification possible ; preuve finale incomplète. Observez le reçu sans rejouer le plan.", false);
        try
        {
            CompletePreSendReceipt(path, request, new(MutationStatus.Uncertain, 97,
                "Réponse native reçue ; relecture finale du moteur non encore enregistrée. Aucun rejeu.", false));
        }
        catch (Exception) { return new(MutationStatus.Uncertain, 97, "Le résultat natif ne peut pas être enregistré durablement ; observation requise, aucun rejeu.", false); }
        return outcome;
    }

    /// <summary>CompletePreSendReceipt calls this before its atomic flush. It cannot certify success without the retained native proof.</summary>
    private void ApplyAttributeReceipt(JsonObject stored, MutationRequest request, MutationOutcome outcome)
    {
        if (request.Attributes is null && request.Kind != "attributes") return;
        AttributeMutationRules.RequireRequest(request); var plan = request.Attributes!;
        using var document = JsonDocument.Parse(stored.ToJsonString()); var root = document.RootElement;
        if (!AttributeMutationRules.ReadChanges(root.GetProperty("AttributeChanges"), request.Domain).SequenceEqual(plan.Changes)
            || !AttributeMutationRules.Same(stored["ConfigurationSha256"]?.GetValue<string>(), plan.ConfigurationSha256)
            || !AttributeMutationRules.Same(stored["ComputerGuid"]?.GetValue<string>(), plan.Target.ComputerGuid)
            || !AttributeMutationRules.Same(stored["InitialOu"]?.GetValue<string>(), plan.Target.Ou)
            || !AttributeMutationRules.Same(stored["TargetOuGuid"]?.GetValue<string>(), plan.Target.OuGuid))
            throw AttributeMutationRules.Refused("Le reçu ne contient plus le diff et les identités du plan confirmé.");
        AttributeSnapshot? proof; lock (attributeGate) attributeProofs.TryGetValue(request.ReceiptId, out proof);
        if (outcome.Status == MutationStatus.PendingRestart || outcome.RestartRequired) throw AttributeMutationRules.Refused("Un changement attributs ne peut pas demander un redémarrage.");
        if (outcome.Status == MutationStatus.Succeeded && (outcome.Code != 30 || proof is null
            || proof.ObservedAt < DateTimeOffset.UtcNow.AddMinutes(-2) || proof.ObservedAt > DateTimeOffset.UtcNow.AddSeconds(30)
            || !AttributeMutationRules.AfterMatches(plan, proof)))
            throw AttributeMutationRules.Refused("Aucune preuve native des valeurs finales : reçu conservé incertain.");
        stored["Attributes"] = outcome.Status == MutationStatus.Succeeded ? "Confirmed" : outcome.Status == MutationStatus.Failed ? "NotRequested" : "Uncertain";
        stored["AttributeObservation"] = proof is not null && outcome.Status != MutationStatus.Failed ? JsonSerializer.SerializeToNode(proof) : null;
    }

    public AttributeObservation ReadAttributeObservation(string receiptId) => WithAttributeObservationMutex(() =>
    {
        var path = ReceiptPath(receiptId); var bytes = ReadReceiptBytes(path);
        var source = AttributeMutationRules.ReadReceipt(path, bytes, new FileInfo(path).LastWriteTimeUtc);
        if (source.Phase is not ("Running" or "Uncertain" or "Verified")) throw AttributeMutationRules.Refused("Ce reçu ne requiert pas une observation de modification envoyée.");
        _ = WindowsAcknowledgementActivity.Read(); // No worker is stopped; unknown/active work conserves the receipt.
        AttributeObservation observation;
        try { observation = new(source, ReadAttributes(source.Plan.Target)); }
        catch (Exception) { observation = new(source, null, "Identité ou attributs non observables ; reçu conservé sans rejeu."); }
        lock (attributeGate)
        {
            if (attributeObservations.Count >= 128) attributeObservations.Remove(attributeObservations.Keys.First());
            attributeObservations[receiptId] = observation;
        }
        return observation;
    }, writing: false);

    public void PersistAttributeObservation(AttributeObservation observation) => WithAttributeObservationMutex(() =>
    {
        var source = observation.Source;
        lock (attributeGate)
        {
            if (!attributeObservations.Remove(source.Receipt.Id, out var retained) || !ReferenceEquals(retained, observation)
                || observation.Error is not null || observation.Snapshot is null
                || observation.Snapshot.ObservedAt < DateTimeOffset.UtcNow.AddMinutes(-1) || observation.Snapshot.ObservedAt > DateTimeOffset.UtcNow.AddSeconds(30)
                || !AttributeMutationRules.AfterMatches(source.Plan, observation.Snapshot)) throw AttributeMutationRules.Refused("La preuve est absente, périmée ou déjà consommée.");
        }
        var path = ReceiptPath(source.Receipt.Id); var bytes = ReadReceiptBytes(path);
        if (!AttributeMutationRules.Same(source.ReceiptSha256, ReceiptAcknowledgementSource.Digest(bytes))) throw AttributeMutationRules.Refused("Le reçu a changé depuis sa lecture.");
        var current = AttributeMutationRules.ReadReceipt(path, bytes, new FileInfo(path).LastWriteTimeUtc);
        var configuration = ReadAttributeConfiguration();
        using var pin = new FileStream(configuration.Path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (pin.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw AttributeMutationRules.Refused("Configuration illisible.");
        var configBytes = new byte[checked((int)pin.Length)]; pin.ReadExactly(configBytes);
        if (!AttributeMutationRules.Same(configuration.Sha256, ReceiptAcknowledgementSource.Digest(configBytes))) throw AttributeMutationRules.Refused("La configuration a changé pendant la vérification.");
        AttributeMutationRules.RequireConfiguration(configuration.Json, source.Plan.Target, mutation: false);
        _ = WindowsAcknowledgementActivity.Read();
        var fresh = ReadAttributes(source.Plan.Target);
        if (!AttributeMutationRules.AfterMatches(current.Plan, fresh)) throw AttributeMutationRules.Refused("Les valeurs finales ne sont plus confirmées ; reçu conservé.");
        if (!AttributeMutationRules.Same(source.ReceiptSha256, ReceiptAcknowledgementSource.Digest(ReadReceiptBytes(path)))) throw AttributeMutationRules.Refused("Le reçu a changé pendant la relecture AD.");
        if (current.Phase == "Verified") return true;
        var stored = JsonNode.Parse(bytes)!.AsObject();
        stored["Attributes"] = "Confirmed"; stored["AttributeObservation"] = JsonSerializer.SerializeToNode(fresh);
        stored["Phase"] = "Verified"; stored["Code"] = 30; stored["RestartRequired"] = false; stored["Utc"] = DateTimeOffset.UtcNow.ToString("o");
        stored["Message"] = "Attributs confirmés par observation explicite du GUID et des valeurs ; aucune modification AD rejouée.";
        using (var completed = JsonDocument.Parse(stored.ToJsonString()))
            if (!AttributeMutationRules.ReceiptMetadataIsValid(completed.RootElement)) throw AttributeMutationRules.Refused("Preuve finale incohérente ; aucun remplacement.");
        WriteCompletedReceipt(path, stored); ReleaseCoordinationAfterCompletion(path, source.Receipt.Id);
        return true;
    }, writing: true);

    private T WithAttributeObservationMutex<T>(Func<T> action, bool writing)
    {
        if (unavailableReason is not null) throw new PestoException("attributes.unavailable", unavailableReason);
        if (writing && Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1") throw new PestoException("attributes.readonly", "La consultation conserve tous les reçus et verrous.");
        if (writing)
        {
            if (!OperatingSystem.IsWindows()) throw AttributeMutationRules.Refused("La preuve doit être enregistrée nativement sous Windows.");
            using var identity = WindowsIdentity.GetCurrent();
            if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
                throw AttributeMutationRules.Refused("L’élévation locale est requise pour confirmer le reçu et libérer ses propres verrous.");
        }
        using var mutex = new Mutex(false, PostMutationMutexName); var owned = false;
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw AttributeMutationRules.Refused("Une opération utilise le verrou GP ; observation refusée sans arrêt de processus.");
            return action();
        }
        finally { if (owned) mutex.ReleaseMutex(); }
    }
}

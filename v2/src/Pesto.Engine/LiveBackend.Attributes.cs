using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private sealed record AttributeInspectionEntry(AttributeSnapshot Snapshot, string ConfigurationSha256, DateTimeOffset ExpiresAt);
    private sealed class AttributePreparedEntry(string id, AttributeMutationPlan effect, DateTimeOffset expiresAt)
    {
        public string Id { get; } = id;
        public AttributeMutationPlan Effect { get; } = effect;
        public DateTimeOffset ExpiresAt { get; } = expiresAt;
        public bool Used;
    }
    private readonly Dictionary<string, AttributeInspectionEntry> attributeInspections = new(StringComparer.Ordinal);
    private readonly Dictionary<string, AttributePreparedEntry> attributePlans = new(StringComparer.Ordinal);

    private string? AttributesCapabilityBlockReason()
    {
        try { _ = RequireAttributes(writing: true); return null; }
        catch (PestoException error) { return error.Message; }
        catch (Exception) { return "Le contexte des attributs AD ne peut pas être confirmé."; }
    }
    private IMutationAttributes RequireAttributes(bool writing)
    {
        if (mutation is not IMutationAttributes provider || mutation is not IMutationReceiptFinalizer)
            throw new PestoException("attributes.unavailable", "Le fournisseur d’attributs AD et de reçus durables n’est pas disponible.");
        if (mutation is IMutationAvailability { IsAvailable: false } availability)
            throw new PestoException("attributes.unavailable", availability.UnavailableReason ?? "Fournisseur AD indisponible.");
        _ = RequireConfig(); RequireUnchangedConfiguration();
        AttributeMutationRules.RequireLiveConfiguration(AttributeConfigurationText());
        if (writing)
        {
            if (Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1")
                throw new PestoException("attributes.readonly", "La consultation interdit toute modification des attributs AD.");
            Policy(RequireConfig()).RequireSupported("attributes");
            if (WriteBlockReason is { } reason) throw new PestoException("attributes.unavailable", reason);
        }
        return provider;
    }
    private string AttributeConfigurationText()
    {
        var path = V1Config.ConfigPathOf(v1InstallationPath) ?? throw new PestoException("config.missing", "Configuration absente.");
        ReceiptAcknowledgementSource.RequirePlainPath(path);
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw new PestoException("config.invalid", "Configuration illisible.");
        var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes);
        if (!AttributeMutationRules.Same(ReceiptAcknowledgementSource.Digest(bytes), configStamp)) throw new PestoException("config.changed", "La configuration a changé.");
        using var memory = new MemoryStream(bytes); using var reader = new StreamReader(memory, Encoding.UTF8, true);
        return reader.ReadToEnd();
    }
    private AttributeSnapshot FreshAttributes(IMutationAttributes provider, AttributeTarget target)
    {
        var snapshot = provider.ReadAttributes(target); AttributeMutationRules.RequireSnapshot(snapshot, target);
        if (snapshot.ObservedAt > clock.GetUtcNow().AddSeconds(30) || snapshot.ObservedAt < clock.GetUtcNow().AddMinutes(-1))
            throw AttributeMutationRules.Refused("La lecture des attributs n’est pas fraîche.");
        return snapshot;
    }
    private JsonObject AttributesInspect(JsonElement args)
    {
        Arguments.Only(args, "computer"); var name = Arguments.Text(args, "computer", true, 15); ValidateComputerName(name);
        var provider = RequireAttributes(writing: false); var read = RequireConfig(); var directory = RequireGateway();
        var computer = directory.FindComputer(read.Domain, DcOrNull(), name) ?? throw new PestoException("computer.missing", "Ce poste n’a pas été trouvé.");
        if (!AttributeMutationRules.Same(computer.Name, name) || !AttributeMutationRules.Same(computer.Domain, read.Domain)
            || computer.Ou is null || !WithinScope(computer.Ou, read.RootOu)) throw AttributeMutationRules.Refused("Le poste lu n’appartient pas à la portée configurée.");
        var target = new AttributeTarget(computer.Name, computer.Guid ?? "", "CN=" + computer.Name + "," + computer.Ou,
            computer.Ou, ResolveTargetGuid(read, directory, computer.Ou), read.Domain, DcOrNull() ?? "");
        AttributeMutationRules.RequireConfiguration(AttributeConfigurationText(), target, mutation: false);
        var snapshot = FreshAttributes(provider, target); var expires = clock.GetUtcNow().AddMinutes(PreviewMinutes);
        foreach (var key in attributeInspections.Where(p => p.Value.ExpiresAt <= clock.GetUtcNow()
            || AttributeMutationRules.Same(p.Value.Snapshot.Target.ComputerGuid, target.ComputerGuid)).Select(p => p.Key).ToArray()) attributeInspections.Remove(key);
        var id = "attributes-inspection-" + Guid.NewGuid().ToString("N");
        attributeInspections[id] = new(snapshot, configStamp!, expires);
        var result = AttributeSnapshotNode(snapshot); result["inspectionId"] = id; result["expiresAt"] = Iso(expires);
        result["mode"] = "live"; result["complete"] = true; result["collectedAt"] = Iso(snapshot.ObservedAt);
        return result;
    }
    private JsonObject AttributesPrepare(JsonElement args)
    {
        Arguments.Only(args, "inspectionId", "values"); var id = Arguments.Text(args, "inspectionId", true, 128);
        var provider = RequireAttributes(writing: true);
        if (!attributeInspections.TryGetValue(id, out var held) || held.ExpiresAt <= clock.GetUtcNow())
            throw new PestoException("attributes.stale", "Relisez les attributs du poste avant de préparer le diff.");
        if (!AttributeMutationRules.Same(held.ConfigurationSha256, configStamp)) throw new PestoException("config.changed", "Nouvelle configuration : relisez le poste.");
        if (!args.TryGetProperty("values", out var values)) throw new PestoException("invalid_arguments", "Les valeurs demandées sont absentes.");
        var requested = AttributeMutationRules.ReadRequested(values); var target = held.Snapshot.Target;
        AttributeMutationRules.RequireConfiguration(AttributeConfigurationText(), target, mutation: true);
        var current = FreshAttributes(provider, target);
        if (current.Values != held.Snapshot.Values || !AttributeMutationRules.Same(current.ManagedByReferenceGuid, held.Snapshot.ManagedByReferenceGuid))
            throw new PestoException("attributes.changed", "Les attributs ont changé depuis l’inspection ; relisez le poste.");
        var changes = AttributeMutationRules.Changes(current, requested, dn => provider.ResolveAttributeReference(target.Domain, target.Dc, dn));
        var policy = Policy(RequireConfig()); policy.AssertPlan("attributes", target.Computer, target.Computer, target.Ou, target.Ou, GetConvention(RequireConfig()));
        RequireGroupExclusions(RequireConfig(), policy, target.ComputerGuid, target.Computer, target.Ou);
        var planId = "attributes-plan-" + Guid.NewGuid().ToString("N");
        foreach (var key in attributePlans.Where(p => p.Value.ExpiresAt <= clock.GetUtcNow()
            || AttributeMutationRules.Same(p.Value.Effect.Target.ComputerGuid, target.ComputerGuid)).Select(p => p.Key).ToArray()) attributePlans.Remove(key);
        var plan = new AttributePreparedEntry(planId, new(target, changes, configStamp!), clock.GetUtcNow().AddMinutes(PlanMinutes));
        attributePlans[planId] = plan;
        return Resp.Obj(("planId", planId), ("kind", "attributes"), ("mode", "live"), ("computer", target.Computer),
            ("computerGuid", target.ComputerGuid), ("domain", target.Domain), ("dc", target.Dc), ("sourceOU", target.Ou), ("targetOU", target.Ou),
            ("confirmationName", target.Computer), ("expiresAt", Iso(plan.ExpiresAt)), ("changes", AttributeChangesNode(changes)),
            ("warnings", Resp.Arr(new[] { "Seules les valeurs affichées seront modifiées. Une valeur vide demande l’effacement de cet attribut.",
                "Un résultat interrompu reste à vérifier. L’observation ultérieure ne rejoue aucune modification." }, x => (JsonNode?)Resp.Node(x))),
            ("steps", Resp.Arr(new[] { new Step("Relire la cible et le diff", "GUID, nom, OU, anciennes valeurs et références managedBy."),
                new Step("Consigner puis modifier les attributs", "Une commande ciblée par GUID ; aucune modification du nom, de l’OU ou des droits."),
                new Step("Relire les valeurs finales", "Réussite uniquement après preuve et reçu durables.") }, x => Resp.Obj(("label", x.Label), ("detail", x.Detail)))));
    }
    private JsonObject AttributesApply(JsonElement args)
    {
        Arguments.Only(args, "planId", "confirmationName"); var provider = RequireAttributes(writing: true);
        var id = Arguments.Text(args, "planId", true, 128);
        if (!attributePlans.TryGetValue(id, out var plan) || plan.ExpiresAt <= clock.GetUtcNow()) throw new PestoException("plan.stale", "Le plan attributs a expiré ; préparez à nouveau.");
        if (plan.Used) throw new PestoException("plan.consumed", "Ce plan a déjà été envoyé ; aucun rejeu.");
        var target = plan.Effect.Target;
        if (Arguments.Text(args, "confirmationName", true, 15) != target.Computer) throw new PestoException("confirmation.invalid", "Le nom confirmé ne correspond pas au poste du diff. Préparez de nouveau les attributs.");
        if (!AttributeMutationRules.Same(configStamp, plan.Effect.ConfigurationSha256)) throw new PestoException("config.changed", "La configuration a changé depuis le diff confirmé.");
        AttributeMutationRules.RequireConfiguration(AttributeConfigurationText(), target, mutation: true);
        var policy = Policy(RequireConfig()); policy.AssertPlan("attributes", target.Computer, target.Computer, target.Ou, target.Ou, GetConvention(RequireConfig()));
        RequireGroupExclusions(RequireConfig(), policy, target.ComputerGuid, target.Computer, target.Ou);
        var before = FreshAttributes(provider, target);
        if (!AttributeMutationRules.BeforeMatches(plan.Effect, before)) throw new PestoException("attributes.changed", "Les valeurs précédentes ont changé ; aucune modification envoyée.");
        foreach (var change in plan.Effect.Changes.Where(c => c.ReferenceGuid is not null))
        {
            var reference = provider.ResolveAttributeReference(target.Domain, target.Dc, change.After);
            AttributeMutationRules.RequireReference(reference, target.Domain, change.After);
            if (!AttributeMutationRules.Same(reference.Guid, change.ReferenceGuid)) throw new PestoException("attributes.changed", "La référence managedBy a été remplacée ; préparez un nouveau diff.");
        }
        plan.Used = true;
        var receiptId = "receipt-" + Guid.NewGuid().ToString("N");
        var request = new MutationRequest("attributes", target.Computer, target.ComputerGuid, null, target.Ou, target.Domain, target.Dc,
            plan.Id, receiptId, target.Ou, target.OuGuid, ConfigurationSha256: plan.Effect.ConfigurationSha256, Attributes: plan.Effect);
        var receipt = new Receipt(receiptId, clock.GetUtcNow(), "attributes", target.Computer, "", target.Ou, "live", "running", 0,
            "Modification des attributs confirmée ; résultat non encore connu.", false);
        receipts.Insert(0, receipt);
        MutationOutcome outcome;
        try { outcome = mutation!.Execute(request); }
        catch (Exception) { outcome = new(MutationStatus.Uncertain, 97, "Réponse interrompue : les attributs peuvent avoir changé ; observez ce reçu sans rejouer le plan.", false); }
        AttributeSnapshot? after = null;
        if (outcome.Status != MutationStatus.Failed)
        {
            try { after = FreshAttributes(provider, target); }
            catch (Exception) { /* Unknown is never an empty attribute or a no-write refusal. */ }
        }
        var status = outcome.Status == MutationStatus.Failed && !outcome.RestartRequired ? MutationStatus.Failed
            : outcome.Status == MutationStatus.Succeeded && outcome.Code == 30 && !outcome.RestartRequired
                && AttributeMutationRules.Same(outcome.ObservedGuid, target.ComputerGuid) && after is not null && AttributeMutationRules.AfterMatches(plan.Effect, after)
                ? MutationStatus.Succeeded : MutationStatus.Uncertain;
        var code = status == MutationStatus.Succeeded ? 30 : status == MutationStatus.Failed ? 96 : 97;
        var message = status == MutationStatus.Succeeded ? "Attributs relus par GUID et confirmés ; diff conservé dans le reçu."
            : status == MutationStatus.Failed ? "Refus confirmé avant toute modification des attributs. " + Safe(outcome.Message)
            : "Résultat à vérifier : une modification a pu être envoyée. Observez le reçu ; aucun rejeu automatique. " + Safe(outcome.Message);
        var final = Finalize(receipt, request, status, code, message, false, status == MutationStatus.Succeeded ? target.ComputerGuid : null);
        return Resp.Obj(("receipt", WithAttributeReceiptInfo(receipts.Single(r => r.Id == receiptId), final)),
            ("changes", AttributeChangesNode(plan.Effect.Changes)), ("observation", after is null ? null : AttributeObservationNode(plan.Effect, after)), ("replayAllowed", false));
    }
    private JsonObject AttributesObserve(JsonElement args)
    {
        Arguments.Only(args, "id"); var id = Arguments.Text(args, "id", true, 128);
        var provider = RequireAttributes(writing: false); var observation = provider.ReadAttributeObservation(id);
        var source = observation.Source;
        if (source.Receipt.Id != id || source.Receipt.Kind != "attributes" || source.Phase is not ("Running" or "Uncertain" or "Verified")
            || source.ReceiptSha256 is not { Length: 64 } || !source.ReceiptSha256.All(Uri.IsHexDigit)) throw AttributeMutationRules.Refused("L’observation ne correspond pas au reçu demandé.");
        AttributeMutationRules.RequirePlan(source.Plan);
        AttributeMutationRules.RequireConfiguration(AttributeConfigurationText(), source.Plan.Target, mutation: false);
        var matches = false;
        if (observation.Error is null && observation.Snapshot is { } snapshot)
        {
            AttributeMutationRules.RequireSnapshot(snapshot, source.Plan.Target);
            matches = snapshot.ObservedAt <= clock.GetUtcNow().AddSeconds(30) && snapshot.ObservedAt >= clock.GetUtcNow().AddMinutes(-1)
                && AttributeMutationRules.AfterMatches(source.Plan, snapshot);
        }
        var readOnly = Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1";
        var verified = false; var receipt = source.Receipt;
        string? reason = matches ? null : "L’identité ou toutes les valeurs attendues ne sont pas confirmées ; reçu et verrous conservés.";
        if (matches && readOnly) reason = "Les valeurs concordent, mais la consultation conserve le reçu et les verrous sans les modifier.";
        else if (matches)
        {
            try { provider.PersistAttributeObservation(observation); }
            catch (Exception) { throw new PestoException("attributes.persistence", "La preuve finale n’a pas pu être enregistrée ou a changé ; aucune réussite ajoutée et aucun rejeu."); }
            receipt = receipt with { Status = "succeeded", Code = 30, RestartRequired = false,
                Message = "Attributs confirmés par observation explicite du GUID et des valeurs ; aucune modification AD rejouée." };
            verified = true;
        }
        var index = receipts.FindIndex(r => r.Id == id); if (index >= 0) receipts[index] = receipt; else receipts.Insert(0, receipt);
        return Resp.Obj(("receipt", WithAttributeReceiptInfo(receipt, ReceiptNode(receipt))), ("verified", verified), ("reason", reason),
            ("observation", observation.Snapshot is null ? null : AttributeObservationNode(source.Plan, observation.Snapshot)),
            ("targetReadOnly", true), ("replayAllowed", false));
    }
    private JsonObject WithAttributeReceiptInfo(Receipt receipt, JsonObject node)
    {
        if (receipt.Kind != "attributes" || gpRoot is null) return node;
        try
        {
            var path = ReceiptAcknowledgementSource.ReceiptPath(gpRoot, "adapter", receipt.Id);
            ReceiptAcknowledgementSource.RequirePlainPath(path);
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length is < 1 or > ReceiptAcknowledgementSource.MaximumBytes) return node;
            var bytes = new byte[checked((int)file.Length)]; file.ReadExactly(bytes);
            var source = AttributeMutationRules.ReadReceipt(path, bytes, new FileInfo(path).LastWriteTimeUtc);
            if (!SameAcknowledgementReceipt(ReceiptNode(source.Receipt), node)) return node;
            node["attributes"] = source.Effect; node["attributeChanges"] = AttributeChangesNode(source.Plan.Changes);
            node["domain"] = source.Plan.Target.Domain; node["dc"] = source.Plan.Target.Dc; node["computerGuid"] = source.Plan.Target.ComputerGuid;
        }
        catch (Exception) { /* An unreadable diff never becomes an implicit permission to retry. */ }
        return node;
    }
    private static JsonArray AttributeChangesNode(IReadOnlyList<AttributeChange> changes) => Resp.Arr(changes, c =>
        Resp.Obj(("attribute", c.Attribute), ("before", c.Before), ("after", c.After), ("referenceGuid", c.ReferenceGuid)));
    private static JsonObject AttributeSnapshotNode(AttributeSnapshot snapshot) => Resp.Obj(("computer", snapshot.Target.Computer),
        ("computerGuid", snapshot.Target.ComputerGuid), ("distinguishedName", snapshot.Target.DistinguishedName), ("domain", snapshot.Target.Domain),
        ("dc", snapshot.Target.Dc), ("ou", snapshot.Target.Ou), ("ouGuid", snapshot.Target.OuGuid), ("observedAt", Iso(snapshot.ObservedAt)),
        ("values", Resp.Obj(("description", snapshot.Values.Description), ("location", snapshot.Values.Location), ("managedBy", snapshot.Values.ManagedBy))),
        ("managedByReferenceGuid", snapshot.ManagedByReferenceGuid));
    private static JsonObject AttributeObservationNode(AttributeMutationPlan plan, AttributeSnapshot snapshot)
    {
        var result = AttributeSnapshotNode(snapshot);
        result["changes"] = Resp.Arr(plan.Changes, c => Resp.Obj(("attribute", c.Attribute), ("expected", c.After), ("observed", snapshot.Values.Get(c.Attribute)),
            ("matches", snapshot.Values.Get(c.Attribute) == c.After && (c.Attribute != "managedBy" || c.After.Length == 0 || AttributeMutationRules.Same(c.ReferenceGuid, snapshot.ManagedByReferenceGuid)))));
        return result;
    }
}

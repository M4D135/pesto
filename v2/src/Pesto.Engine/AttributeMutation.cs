using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public sealed record AttributeTarget(string Computer, string ComputerGuid, string DistinguishedName,
    string Ou, string OuGuid, string Domain, string Dc);
public sealed record AttributeValues(string Description, string Location, string ManagedBy)
{
    public string Get(string name) => name switch
    {
        "description" => Description, "location" => Location, "managedBy" => ManagedBy,
        _ => throw AttributeMutationRules.Refused("Attribut inconnu.")
    };
}
public sealed record AttributeReference(string DistinguishedName, string Guid);
public sealed record AttributeSnapshot(AttributeTarget Target, AttributeValues Values, DateTimeOffset ObservedAt,
    string? ManagedByReferenceGuid = null);
public sealed record AttributeChange(string Attribute, string Before, string After, string? ReferenceGuid);
public sealed record AttributeMutationPlan(AttributeTarget Target, IReadOnlyList<AttributeChange> Changes,
    string ConfigurationSha256);
public sealed record AttributeReceiptSource(Receipt Receipt, string ReceiptSha256, string Phase, string Effect,
    AttributeMutationPlan Plan, string PlanId);
public sealed record AttributeObservation(AttributeReceiptSource Source, AttributeSnapshot? Snapshot, string? Error = null);

/// <summary>Only explicit reads and persistence of a retained, fresh observation. Mutation itself uses IMutationGateway.Execute.</summary>
public interface IMutationAttributes
{
    AttributeSnapshot ReadAttributes(AttributeTarget target);
    AttributeReference ResolveAttributeReference(string domain, string dc, string distinguishedName);
    AttributeObservation ReadAttributeObservation(string receiptId);
    void PersistAttributeObservation(AttributeObservation observation);
}

/// <summary>Closed V1 attribute contract. Browser values never supply Before, a reference GUID or an AD command.</summary>
public static class AttributeMutationRules
{
    public static IReadOnlyList<string> Names { get; } = Array.AsReadOnly<string>(["description", "location", "managedBy"]);
    private static readonly JsonSerializerOptions JsonOptions = new() { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    public static PestoException Refused(string text) => new("attributes.evidence", text);
    public static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    public static bool Within(string value, string root) => Same(value, root) || value.EndsWith("," + root, StringComparison.OrdinalIgnoreCase);
    private static bool GuidValue(string? value) => Guid.TryParse(value, out var guid) && guid != Guid.Empty;
    private static bool Dns(string? value) => value is { Length: > 0 and <= 253 }
        && Regex.IsMatch(value, "^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$", RegexOptions.CultureInvariant);
    public static void RequireValue(string? value)
    {
        if (value is null || value.Length > 1024 || value.Any(char.IsControl))
            throw new PestoException("attributes.value", "Une valeur doit être une chaîne de 1 024 caractères au plus, sans caractère de contrôle ; une chaîne vide demande un effacement.");
    }
    public static void RequireTarget(AttributeTarget target)
    {
        if (target is null || !Regex.IsMatch(target.Computer ?? "", "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$", RegexOptions.CultureInvariant)
            || !GuidValue(target.ComputerGuid) || !GuidValue(target.OuGuid) || !Dns(target.Domain) || !Dns(target.Dc)
            || Same(target.Dc, target.Domain) || !target.Dc.EndsWith("." + target.Domain, StringComparison.OrdinalIgnoreCase)
            || target.Ou is not { Length: > 0 and <= 2048 } || !V1Config.IsOuPath(target.Ou)
            || !InDomain(target.Ou, target.Domain) || !Same(target.DistinguishedName, "CN=" + target.Computer + "," + target.Ou))
            throw Refused("GUID, nom, DN, OU et domaine/DC exacts de la cible ne sont pas confirmés.");
    }
    public static bool InDomain(string dn, string domain) => dn.EndsWith(",DC=" + domain.Replace(".", ",DC=", StringComparison.Ordinal), StringComparison.OrdinalIgnoreCase);
    public static void RequireReference(AttributeReference reference, string domain, string? expectedDn = null)
    {
        if (reference is null) throw Refused("Référence managedBy absente.");
        RequireValue(reference.DistinguishedName);
        if (!GuidValue(reference.Guid) || !Regex.IsMatch(reference.DistinguishedName, "^(CN|OU)=.+,DC=", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)
            || !InDomain(reference.DistinguishedName, domain) || expectedDn is not null && !Same(expectedDn, reference.DistinguishedName))
            throw Refused("La référence managedBy ne correspond pas à un DN et un GUID observés dans ce domaine.");
    }
    public static void RequireSnapshot(AttributeSnapshot snapshot, AttributeTarget? target = null)
    {
        if (snapshot is null || snapshot.Values is null) throw Refused("Lecture des attributs incomplète.");
        RequireTarget(snapshot.Target);
        foreach (var name in Names) RequireValue(snapshot.Values.Get(name));
        if (snapshot.ObservedAt.Offset != TimeSpan.Zero || snapshot.ObservedAt == default
            || target is not null && !SameTarget(snapshot.Target, target)) throw Refused("L’instantané ne correspond pas à l’identité demandée.");
        if (snapshot.Values.ManagedBy.Length > 0)
            RequireReference(new(snapshot.Values.ManagedBy, snapshot.ManagedByReferenceGuid ?? ""), snapshot.Target.Domain);
        else if (!string.IsNullOrEmpty(snapshot.ManagedByReferenceGuid)) throw Refused("GUID managedBy présent sans référence.");
    }
    public static bool SameTarget(AttributeTarget a, AttributeTarget b) =>
        Same(a.Computer, b.Computer) && Same(a.ComputerGuid, b.ComputerGuid) && Same(a.DistinguishedName, b.DistinguishedName)
        && Same(a.Ou, b.Ou) && Same(a.OuGuid, b.OuGuid) && Same(a.Domain, b.Domain) && Same(a.Dc, b.Dc);

    public static IReadOnlyDictionary<string, string> ReadRequested(JsonElement values)
    {
        if (values.ValueKind != JsonValueKind.Object) throw new PestoException("invalid_arguments", "values doit contenir les attributs explicitement demandés.");
        var requested = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in values.EnumerateObject())
        {
            if (!Names.Contains(item.Name, StringComparer.Ordinal) || item.Value.ValueKind != JsonValueKind.String || requested.ContainsKey(item.Name))
                throw new PestoException("invalid_arguments", "Attribut inconnu, dupliqué ou valeur non textuelle.");
            var text = item.Value.GetString()!; RequireValue(text); requested.Add(item.Name, text);
        }
        if (requested.Count is < 1 or > 3) throw new PestoException("invalid_arguments", "Un à trois attributs doivent être explicitement demandés.");
        return requested;
    }
    public static IReadOnlyList<AttributeChange> Changes(AttributeSnapshot before, IReadOnlyDictionary<string, string> requested,
        Func<string, AttributeReference> resolve)
    {
        RequireSnapshot(before);
        var changes = new List<AttributeChange>();
        foreach (var name in Names)
        {
            if (!requested.TryGetValue(name, out var after)) continue;
            RequireValue(after);
            if (before.Values.Get(name) == after) continue;
            string? referenceGuid = null;
            if (name == "managedBy" && after.Length > 0)
            {
                var reference = resolve(after); RequireReference(reference, before.Target.Domain, after);
                // Show the observed canonical DN in the diff, before the operator confirms it.
                after = reference.DistinguishedName; referenceGuid = reference.Guid;
                if (before.Values.ManagedBy == after) continue;
            }
            changes.Add(new(name, before.Values.Get(name), after, referenceGuid));
        }
        RequireChanges(changes, before.Target.Domain);
        return changes.AsReadOnly();
    }
    public static void RequireChanges(IReadOnlyList<AttributeChange> changes, string domain)
    {
        if (changes is null || changes.Count is < 1 or > 3) throw new PestoException("attributes.empty", "Aucune différence à appliquer : une à trois modifications réelles sont requises.");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var change in changes)
        {
            if (change is null || !Names.Contains(change.Attribute, StringComparer.Ordinal) || !seen.Add(change.Attribute)) throw Refused("Diff inconnu ou dupliqué.");
            RequireValue(change.Before); RequireValue(change.After);
            if (change.Before == change.After) throw Refused("Diff vide.");
            if (change.Attribute == "managedBy" && change.After.Length > 0)
                RequireReference(new(change.After, change.ReferenceGuid ?? ""), domain);
            else if (!string.IsNullOrEmpty(change.ReferenceGuid)) throw Refused("Référence GUID inattendue dans le diff.");
        }
    }
    public static void RequirePlan(AttributeMutationPlan plan)
    {
        if (plan is null) throw Refused("Plan attributs absent.");
        RequireTarget(plan.Target); RequireChanges(plan.Changes, plan.Target.Domain);
        if (plan.ConfigurationSha256 is not { Length: 64 } || !plan.ConfigurationSha256.All(Uri.IsHexDigit)) throw Refused("Empreinte de configuration absente.");
    }
    public static void RequireRequest(MutationRequest request)
    {
        if (request.Kind != "attributes" && request.Attributes is null) return;
        var plan = request.Attributes ?? throw Refused("Un plan attributs interne est requis."); RequirePlan(plan);
        var t = plan.Target;
        if (request.Kind != "attributes" || request.NewName is not null || request.Continuation is not null || request.Reservation is not null
            || request.ReservationRequired || request.NameReservation is not null || request.PrecreatedJoin is not null
            || request.Entra is not null || request.EntraLeaveConfirmed || !Same(t.Computer, request.Computer)
            || !Same(t.ComputerGuid, request.ComputerGuid) || !Same(t.Domain, request.Domain) || !Same(t.Dc, request.Dc)
            || !Same(t.Ou, request.SourceOu) || !Same(t.Ou, request.TargetOu) || !Same(t.OuGuid, request.TargetOuGuid)
            || !Same(plan.ConfigurationSha256, request.ConfigurationSha256)) throw Refused("Le diff ne correspond plus au plan confirmé.");
    }
    public static void RequireConfiguration(string json, AttributeTarget target, bool mutation)
    {
        RequireTarget(target); RequireLiveConfiguration(json); var config = V1Config.ValidateText(json);
        if (!Same(config.Domain, target.Domain) || !Within(target.Ou, config.RootOu)) throw Refused("La cible sort du domaine ou de la racine gérée configurés.");
        if (mutation) config.OperationPolicy.AssertPlan("attributes", target.Computer, target.Computer, target.Ou, target.Ou, config.BuildConvention());
    }
    public static void RequireLiveConfiguration(string json)
    {
        _ = V1Config.ValidateText(json);
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.TryGetProperty("DEBUG", out var debug) && debug.ValueKind == JsonValueKind.Object)
            foreach (var name in new[] { "Simulation", "GUI", "HorsDomaine", "MauvaiseOU", "ForceADM", "BPVerifNomAD" })
                if (debug.TryGetProperty(name, out var flag) && (flag.ValueKind == JsonValueKind.True
                    || flag.ValueKind == JsonValueKind.String && Same(flag.GetString()?.Trim(), "true"))) throw Refused("Les attributs réels exigent une configuration sans flags DEBUG actifs.");
    }
    public static bool BeforeMatches(AttributeMutationPlan plan, AttributeSnapshot snapshot) => SameTarget(plan.Target, snapshot.Target)
        && plan.Changes.All(change => snapshot.Values.Get(change.Attribute) == change.Before);
    public static bool AfterMatches(AttributeMutationPlan plan, AttributeSnapshot snapshot) => SameTarget(plan.Target, snapshot.Target)
        && plan.Changes.All(change => snapshot.Values.Get(change.Attribute) == change.After
            && (change.Attribute != "managedBy" || change.After.Length == 0 || Same(change.ReferenceGuid, snapshot.ManagedByReferenceGuid)));

    public static IReadOnlyList<AttributeChange> ReadChanges(JsonElement value, string domain)
    {
        if (value.ValueKind != JsonValueKind.Array) throw Refused("Diff durable absent.");
        foreach (var change in value.EnumerateArray()) Closed(change, ["Attribute", "Before", "After", "ReferenceGuid"]);
        var changes = JsonSerializer.Deserialize<List<AttributeChange>>(value.GetRawText(), JsonOptions) ?? throw Refused("Diff illisible.");
        RequireChanges(changes, domain); return changes.AsReadOnly();
    }
    public static bool IsV1Attributes(JsonElement root)
    {
        if (!root.TryGetProperty("Plan", out var plan) || plan.ValueKind != JsonValueKind.Object) return false;
        if (plan.TryGetProperty("Action", out var action)) return action.ValueKind == JsonValueKind.String && action.GetString() == "Attributes";
        // The real V1 Start-PestoIntervention copies only its closed common Plan fields and drops Action/Changes.
        // Its later Set-PestoEffect flush retains Attributes + AttributeChanges at the receipt root.
        return root.TryGetProperty("Attributes", out var effect) && effect.ValueKind == JsonValueKind.String
            && root.TryGetProperty("AttributeChanges", out var changes) && changes.ValueKind == JsonValueKind.Array;
    }
    public static bool ReceiptMetadataIsValid(JsonElement root, bool legacy = false)
    {
        try
        {
            var attributes = legacy ? IsV1Attributes(root) : Text(root, "Kind") == "attributes";
            if (!attributes) return new[] { "Attributes", "AttributeChanges", "AttributeObservation" }.All(name => !root.TryGetProperty(name, out var v) || v.ValueKind == JsonValueKind.Null);
            var effect = Text(root, "Attributes");
            if (effect is not ("NotRequested" or "Requested" or "Confirmed" or "Uncertain")) return false;
            var holder = legacy ? root.GetProperty("Plan") : root;
            var domain = Text(holder, "Domain") ?? "";
            var changes = ReadChanges(root.GetProperty("AttributeChanges"), domain);
            if (legacy)
            {
                if (holder.TryGetProperty("Action", out _))
                {
                    if (!changes.SequenceEqual(ReadChanges(holder.GetProperty("Changes"), domain))) return false;
                }
                else if (holder.TryGetProperty("Changes", out _) || holder.TryGetProperty("Metadata", out _)) return false;
                var ou = Text(holder, "OU_Actuelle") ?? "";
                var dc = Text(holder, "DC") ?? "";
                var legacyPhase = Text(root, "Phase");
                var code = root.GetProperty("ResultCode").GetInt32();
                if (legacyPhase == "Verified" ? effect != "Confirmed" || code != 30
                    : legacyPhase == "Failed" ? effect != "NotRequested"
                    : legacyPhase is not ("Running" or "Uncertain" or "Partial")) return false;
                return Dns(domain) && Dns(dc) && dc.EndsWith("." + domain, StringComparison.OrdinalIgnoreCase)
                    && V1Config.IsOuPath(ou) && InDomain(ou, domain)
                    && Text(root, "Entra") == "NotRequested" && Text(root, "Rename") == "NotRequested" && Text(root, "Move") == "NotRequested"
                    && (Text(root, "Protection") is "NotChanged" or "Restored")
                    && holder.GetProperty("Renommer").ValueKind == JsonValueKind.False && holder.GetProperty("Deplacer").ValueKind == JsonValueKind.False
                    && (!holder.TryGetProperty("Reboot", out var reboot) || reboot.ValueKind == JsonValueKind.False)
                    && Same(Text(holder, "Nom_du_PC"), Text(holder, "Nouveau_Nom"))
                    && Same(Text(holder, "OU_Actuelle"), Text(holder, "OU_Destination")) && GuidValue(Text(holder, "Objet_GUID"));
            }
            var target = TargetFromReceipt(root); RequireTarget(target);
            if (root.TryGetProperty("NewName", out var nn) && nn.ValueKind != JsonValueKind.Null
                || root.GetProperty("RestartRequired").ValueKind != JsonValueKind.False
                || new[] { "ParentReceiptId", "ParentReceiptSha256", "ContinuationAttemptId", "ContinuationChildReceiptId", "ContinuationChildPlanId",
                    "ContinuationParentStateSha256", "ContinuationParentReceiptSha256", "ResolutionChildReceiptId", "ResolutionChildReceiptSha256", "ResolutionUtc",
                    "ReservationId", "ReservationAction", "EntraEvidenceId", "JoinAccountMode", "Clock", "WindowsBaselineProof" }
                    .Any(key => root.TryGetProperty(key, out var v) && v.ValueKind != JsonValueKind.Null)) return false;
            if (root.TryGetProperty("Entra", out var entra) && entra.ValueKind != JsonValueKind.Null && entra.GetString() != "NotRequested") return false;
            var phase = Text(root, "Phase");
            if (phase == "Verified" ? effect != "Confirmed" || root.GetProperty("Code").GetInt32() != 30
                : phase == "Failed" ? effect != "NotRequested"
                : phase is not ("Running" or "Uncertain") || effect is not ("Requested" or "Uncertain")) return false;
            var plan = new AttributeMutationPlan(target, changes, Text(root, "ConfigurationSha256") ?? ""); RequirePlan(plan);
            if (!root.TryGetProperty("AttributeObservation", out var proof) || proof.ValueKind == JsonValueKind.Null) return phase != "Verified";
            var snapshot = ReadSnapshot(proof); RequireSnapshot(snapshot, target);
            return phase != "Verified" || AfterMatches(plan, snapshot);
        }
        catch (Exception) { return false; }
    }
    public static AttributeSnapshot ReadSnapshot(JsonElement value)
    {
        Closed(value, ["Target", "Values", "ObservedAt", "ManagedByReferenceGuid"]);
        Closed(value.GetProperty("Target"), ["Computer", "ComputerGuid", "DistinguishedName", "Ou", "OuGuid", "Domain", "Dc"]);
        Closed(value.GetProperty("Values"), ["Description", "Location", "ManagedBy"]);
        var result = JsonSerializer.Deserialize<AttributeSnapshot>(value.GetRawText(), JsonOptions) ?? throw Refused("Observation illisible.");
        RequireSnapshot(result); return result;
    }
    public static AttributeReceiptSource ReadReceipt(string path, ReadOnlyMemory<byte> bytes, DateTimeOffset lastWriteUtc)
    {
        var entry = GpHistory.ParseAdapterSnapshot(path, bytes, lastWriteUtc);
        using var doc = JsonDocument.Parse(bytes); var root = doc.RootElement;
        if (!entry.Readable || entry.Receipt.Kind != "attributes" || !ReceiptMetadataIsValid(root)) throw Refused("Ce reçu attributs durable n’est pas reconnu.");
        var target = TargetFromReceipt(root);
        return new(entry.Receipt, ReceiptAcknowledgementSource.Digest(bytes.ToArray()), Text(root, "Phase")!, Text(root, "Attributes")!,
            new(target, ReadChanges(root.GetProperty("AttributeChanges"), target.Domain), Text(root, "ConfigurationSha256")!), Text(root, "PlanId")!);
    }
    private static AttributeTarget TargetFromReceipt(JsonElement root)
    {
        var computer = Text(root, "Computer") ?? ""; var ou = Text(root, "InitialOu") ?? "";
        if (!Same(ou, Text(root, "TargetOu"))) throw Refused("Le reçu attributs ne peut pas déplacer le poste.");
        return new(computer, Text(root, "ComputerGuid") ?? "", "CN=" + computer + "," + ou, ou,
            Text(root, "TargetOuGuid") ?? "", Text(root, "Domain") ?? "", Text(root, "Dc") ?? "");
    }
    private static string? Text(JsonElement value, string key) => value.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.String ? item.GetString() : null;
    private static void Closed(JsonElement value, string[] fields)
    {
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Count() != fields.Length
            || value.EnumerateObject().Any(p => !fields.Contains(p.Name, StringComparer.Ordinal))
            || value.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() != fields.Length)
            throw Refused("Schéma de preuve attributs inconnu, incomplet ou dupliqué.");
    }
}

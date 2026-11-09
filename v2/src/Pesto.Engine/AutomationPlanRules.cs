using System.Collections.ObjectModel;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Portable CLI documents contain reviewed facts only. A checksum never grants execution authority.</summary>
public static class AutomationPlanRules
{
    public const string Purpose = "PestoV2PreparedPlan";
    public const int MaximumDocumentBytes = 65536;
    internal static readonly JsonSerializerOptions JsonOptions = new() { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    private static readonly string[] MetadataFields = ["Campaign", "Sequence", "Stage", "DeploymentBuild", "Orchestrator"];
    private static readonly string[] PlanFields = ["Schema", "Purpose", "Action", "CreatedUtc", "ExpiresUtc", "ProfileSid", "OperatorSid", "MachineId",
        "ConfigurationIdentitySha256", "ConfigurationSha256", "Domain", "Dc", "Computer", "NewName", "ComputerGuid", "SourceOu", "TargetOu",
        "TargetOuGuid", "Type", "SiteCode", "ServiceCode", "TargetMachineId", "EntraState", "EntraPolicy", "EntraLeaveRequired", "Metadata", "Integrity"];
    internal static PestoException Refused(string message) => new("automation.plan", message);
    internal static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    internal static bool Sid(string? value) => value is { Length: > 0 and <= 184 }
        && Regex.IsMatch(value, "^S-1-[0-9]+(?:-[0-9]+){1,15}$", RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    internal static string Digest(ReadOnlySpan<byte> bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    internal static string Digest(string value) => Digest(Encoding.UTF8.GetBytes(value));

    public static string ConfigurationIdentity(string directory, string profileSid) =>
        Digest(Path.GetFullPath(Path.Combine(directory, "cfg.json")).ToUpperInvariant() + "\n" + profileSid);

    public static IReadOnlyDictionary<string, string> ReadMetadata(string? path)
    {
        if (path is null) return ValidateMetadata(new Dictionary<string, string>());
        using var document = ParseObject(ReadDocument(path));
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var item in document.RootElement.EnumerateObject())
        {
            if (item.Value.ValueKind != JsonValueKind.String) throw Refused("Les métadonnées CLI doivent être des chaînes fermées.");
            result.Add(item.Name, item.Value.GetString()!);
        }
        return ValidateMetadata(result);
    }

    public static IReadOnlyDictionary<string, string> ValidateMetadata(IReadOnlyDictionary<string, string>? metadata)
    {
        if (metadata is null || metadata.Count > MetadataFields.Length) throw Refused("Métadonnées CLI absentes ou hors limites.");
        var copy = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in metadata)
        {
            if (!MetadataFields.Contains(key, StringComparer.Ordinal) || value is null || value.Length > 120 || value.Any(char.IsControl)
                || Regex.IsMatch(value, "(?:password|passwd|token|secret)\\s*[:=]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking))
                throw Refused("Métadonnée inconnue, trop longue ou contenant une forme de secret ; aucune valeur n'est publiée.");
            copy.Add(key, value);
        }
        return new ReadOnlyDictionary<string, string>(copy);
    }

    public static AutomationPlan Seal(AutomationPlan value)
    {
        var normalized = value with { Metadata = ValidateMetadata(value.Metadata), Integrity = "" };
        var result = normalized with { Integrity = ComputeIntegrity(normalized) };
        Validate(result); return result;
    }

    public static string ComputeIntegrity(AutomationPlan value)
    {
        var node = JsonSerializer.SerializeToNode(value, JsonOptions)!.AsObject();
        node.Remove("Integrity");
        return ConfigurationDocument.Fingerprint(node);
    }

    public static void Validate(AutomationPlan value)
    {
        if (value is null || value.Schema != 1 || value.Purpose != Purpose
            || value.Action is not ("join" or "rename" or "move" or "renameMove")
            || value.CreatedUtc == default || value.CreatedUtc.Offset != TimeSpan.Zero || value.ExpiresUtc.Offset != TimeSpan.Zero
            || value.ExpiresUtc <= value.CreatedUtc || value.ExpiresUtc > value.CreatedUtc.AddHours(24)
            || !Sid(value.ProfileSid) || !Sid(value.OperatorSid) || !RemoteWindowsEvidenceProtocol.IsGuid(value.MachineId)
            || !RemoteWindowsEvidenceProtocol.IsHash(value.ConfigurationIdentitySha256) || !RemoteWindowsEvidenceProtocol.IsHash(value.ConfigurationSha256)
            || !RemoteWindowsEvidenceProtocol.IsHash(value.Integrity) || !Same(value.Integrity, ComputeIntegrity(value))
            || !SharedCoordinationProtocol.IsDomainName(value.Domain) || !JoinClockGuard.IsServer(value.Dc)
            || Same(value.Dc, value.Domain) || !value.Dc.EndsWith("." + value.Domain, StringComparison.OrdinalIgnoreCase)
            || !RemoteWindowsEvidenceProtocol.IsName(value.Computer) || !RemoteWindowsEvidenceProtocol.IsName(value.NewName)
            || !V1Config.IsOuPath(value.TargetOu) || !Same(V1Config.DomainFromDn(value.TargetOu), value.Domain))
            throw Refused("Le plan exporté est incomplet, incohérent ou ne possède pas une portée exacte ; aucune valeur n'est corrigée implicitement.");
        _ = ValidateMetadata(value.Metadata);
        if (value.Action != "join" && (!RemoteWindowsEvidenceProtocol.IsGuid(value.ComputerGuid) || value.SourceOu is null
            || !V1Config.IsOuPath(value.SourceOu) || !Same(V1Config.DomainFromDn(value.SourceOu), value.Domain)))
            throw Refused("Le plan exige une identité GUID et une OU source réellement observées.");
        if (value.Action == "join" && (value.ComputerGuid is not null || value.SourceOu is not null)
            || value.Action is "join" or "move" or "renameMove" && !RemoteWindowsEvidenceProtocol.IsGuid(value.TargetOuGuid)
            || value.Action == "move" && !Same(value.Computer, value.NewName)
            || value.Action == "rename" && !Same(value.SourceOu, value.TargetOu)) throw Refused("Les effets du plan ne correspondent pas à l'action annoncée.");
        if (value.Action is "rename" or "renameMove")
        {
            if (!RemoteWindowsEvidenceProtocol.IsGuid(value.TargetMachineId) || value.EntraState is not ("adOnly" or "hybrid")
                || value.EntraPolicy is not ("Disabled" or "HybridOnly") || value.EntraLeaveRequired != (value.EntraState == "hybrid")
                || value.EntraLeaveRequired && value.EntraPolicy != "HybridOnly") throw Refused("L'intention Entra et la machine cible ne sont pas prouvées dans le plan.");
        }
        else if (value.TargetMachineId is not null || value.EntraState is not null || value.EntraPolicy is not null || value.EntraLeaveRequired)
            throw Refused("Une action sans renommage ne peut porter d'autorisation Entra.");
        foreach (var facet in new[] { value.Type, value.SiteCode, value.ServiceCode })
            if (facet is not null && (facet.Length is < 1 or > 8 || !facet.All(char.IsAsciiLetterOrDigit))) throw Refused("Facette de plan invalide.");
    }

    public static AutomationPlan Read(string path)
    {
        using var doc = ParseObject(ReadDocument(path));
        RequireFields(doc.RootElement, PlanFields);
        var plan = JsonSerializer.Deserialize<AutomationPlan>(doc.RootElement.GetRawText(), JsonOptions)
            ?? throw Refused("Plan exporté illisible.");
        Validate(plan); return plan with { Metadata = ValidateMetadata(plan.Metadata) };
    }

    public static void Write(string path, AutomationPlan plan)
    {
        Validate(plan);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(plan, JsonOptions);
        if (bytes.Length > MaximumDocumentBytes) throw Refused("Plan exporté trop volumineux.");
        SharedCoordinationProtocol.RequireNoLinks(path);
        using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        output.Write(bytes); output.Flush(flushToDisk: true);
    }

    public static void RequireContext(AutomationPlan plan, AutomationHostContext context, string configurationSha256, DateTimeOffset now, bool checkExpiry = true)
    {
        Validate(plan);
        if (!Same(plan.ProfileSid, context.ProfileSid) || !Same(plan.OperatorSid, context.OperatorSid) || !Same(plan.MachineId, context.MachineId)
            || !Same(plan.ConfigurationIdentitySha256, ConfigurationIdentity(context.ConfigurationDirectory, context.ProfileSid))
            || !Same(plan.ConfigurationSha256, configurationSha256)) throw Refused("Le plan ne correspond plus au profil, à l'opérateur, à la machine ou à cette configuration exacte.");
        if (checkExpiry && (plan.CreatedUtc > now.AddMinutes(1) || plan.ExpiresUtc <= now))
            throw Refused("Le plan exporté a expiré ; préparez un nouveau plan avant toute nouvelle intention.");
        if (plan.Action == "join" && !Same(plan.Computer, context.ComputerName)) throw Refused("La jonction automatique ne concerne que ce poste local.");
    }

    public static void RequireSameIntent(AutomationPlan expected, AutomationPlan fresh)
    {
        Validate(expected); Validate(fresh);
        foreach (var (a, b) in new[] { (expected.Action, fresh.Action), (expected.ProfileSid, fresh.ProfileSid), (expected.OperatorSid, fresh.OperatorSid),
            (expected.MachineId, fresh.MachineId), (expected.ConfigurationIdentitySha256, fresh.ConfigurationIdentitySha256), (expected.ConfigurationSha256, fresh.ConfigurationSha256),
            (expected.Domain, fresh.Domain), (expected.Dc, fresh.Dc), (expected.Computer, fresh.Computer), (expected.NewName, fresh.NewName),
            (expected.ComputerGuid, fresh.ComputerGuid), (expected.SourceOu, fresh.SourceOu), (expected.TargetOu, fresh.TargetOu), (expected.TargetOuGuid, fresh.TargetOuGuid),
            (expected.Type, fresh.Type), (expected.SiteCode, fresh.SiteCode), (expected.ServiceCode, fresh.ServiceCode), (expected.TargetMachineId, fresh.TargetMachineId),
            (expected.EntraPolicy, fresh.EntraPolicy) })
            if (!Same(a, b)) throw Refused("L'identité, le nom, la destination ou la politique ont changé depuis le plan exporté ; aucune cible de remplacement choisie.");
        if (!expected.EntraLeaveRequired && fresh.EntraLeaveRequired) throw Refused("Le poste exige maintenant un retrait Entra absent du plan exporté ; préparez une nouvelle intention explicite.");
        if (ConfigurationDocument.Fingerprint(JsonSerializer.SerializeToNode(expected.Metadata)!)
            != ConfigurationDocument.Fingerprint(JsonSerializer.SerializeToNode(fresh.Metadata)!)) throw Refused("Les métadonnées diffèrent du plan exporté.");
    }

    internal static byte[] ReadDocument(string path)
    {
        if (!Path.IsPathFullyQualified(path)) throw Refused("Chemin absolu de document requis.");
        SharedCoordinationProtocol.RequireNoLinks(path);
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length is < 1 or > MaximumDocumentBytes) throw Refused("Document CLI vide ou trop volumineux.");
        var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes); return bytes;
    }

    internal static JsonDocument ParseObject(ReadOnlyMemory<byte> bytes)
    {
        JsonDocument document;
        try { document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 20 }); }
        catch (JsonException) { throw Refused("Document CLI JSON illisible."); }
        try
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object) throw Refused("Objet JSON CLI requis.");
            RejectDuplicates(document.RootElement); return document;
        }
        catch { document.Dispose(); throw; }
    }

    internal static void RequireFields(JsonElement root, string[] fields)
    {
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Count() != fields.Length
            || root.EnumerateObject().Any(property => !fields.Contains(property.Name, StringComparer.Ordinal)))
            throw Refused("Schéma CLI fermé : champ inconnu ou absent.");
    }

    private static void RejectDuplicates(JsonElement node)
    {
        if (node.ValueKind == JsonValueKind.Object)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in node.EnumerateObject())
            { if (!seen.Add(property.Name)) throw Refused("Clé JSON CLI dupliquée."); RejectDuplicates(property.Value); }
        }
        else if (node.ValueKind == JsonValueKind.Array) foreach (var item in node.EnumerateArray()) RejectDuplicates(item);
    }
}

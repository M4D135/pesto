using System.Text.Json;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Restrictions accepted by the V1 configuration are enforced before preparing and sending every mutation.
/// Admission also honors the process consultation flag; external providers are checked by live preparation and native mutation paths.
/// </summary>
internal sealed record V1OperationPolicy
{
    private const string ReadOnlyReason = "Session de consultation : aucune nouvelle mutation autorisée, même par appel direct au moteur.";
    public static readonly V1OperationPolicy Default = new();
    public IReadOnlyList<string> ExcludedNames { get; init; } = [];
    public IReadOnlyList<string> ExcludedOus { get; init; } = [];
    public IReadOnlyList<string> ExcludedGroups { get; init; } = [];
    public string CoordinationRoot { get; init; } = "";
    public bool CoordinationRequired { get; init; }
    public bool ReserveNamesInAd { get; init; }
    public bool AllowPrecreatedJoin { get; init; }
    public bool BlockJoinOnClockSkew { get; init; }
    public bool IncidentMode { get; init; }
    public bool AuditEventLogEnabled { get; init; }
    public V1ScenarioPolicy? Scenario { get; init; }
    public string? VerificationFailure { get; init; }
    public int? ManagedMaxBatch { get; init; }

    public V1OperationPolicy WithManaged(MutationManagedPolicy managed)
    {
        if (managed.Refusal is not null) return this with { VerificationFailure = managed.Refusal };
        if (managed.MaxBatch is < 1 or > 200) return this with { VerificationFailure = "POLICY HKLM.MaxBatch invalide : aucune mutation." };
        var scenario = Scenario;
        if (managed.ScenarioJson is not null)
        {
            try
            {
                if (managed.ScenarioJson.Length > 65536) throw new JsonException();
                using var doc = JsonDocument.Parse(managed.ScenarioJson);
                var errors = new List<string>();
                scenario = V1ScenarioPolicy.Read(doc.RootElement, errors);
                if (errors.Count > 0) throw new JsonException();
            }
            catch (JsonException) { return this with { VerificationFailure = "POLICY HKLM.ScenarioJson illisible ou invalide : aucune mutation." }; }
        }
        return this with { IncidentMode = IncidentMode || managed.IncidentMode, Scenario = scenario, ManagedMaxBatch = managed.MaxBatch };
    }

    public static V1OperationPolicy Read(JsonElement cfg, List<string> errors)
    {
        if (!cfg.TryGetProperty("POLICY", out var value) || value.ValueKind != JsonValueKind.Object) return Default;
        var coordinationRoot = "";
        if (value.TryGetProperty("CoordinationRoot", out var root))
        {
            if (root.ValueKind != JsonValueKind.String) errors.Add("POLICY.CoordinationRoot : chaîne attendue.");
            else
            {
                coordinationRoot = root.GetString()!.Trim();
                if (coordinationRoot.Length > 0 && (coordinationRoot.Length > 240 || coordinationRoot.Any(c => char.IsControl(c) || c is '"' or '*' or '?')
                    || !(Regex.IsMatch(coordinationRoot, @"^[A-Za-z]:[\\/]") || coordinationRoot.StartsWith(@"\\", StringComparison.Ordinal)
                        || Path.IsPathFullyQualified(coordinationRoot))))
                    errors.Add("POLICY.CoordinationRoot : chemin absolu invalide.");
            }
        }
        return new()
        {
            ExcludedNames = ReadList(value, "ExcludedNames", errors, s => Regex.IsMatch(s, "^[A-Za-z0-9*?-]{1,64}$")),
            ExcludedOus = ReadList(value, "ExcludedOUs", errors, V1Config.IsOuPath),
            ExcludedGroups = ReadList(value, "ExcludedGroupGuids", errors, s => Guid.TryParse(s, out var guid) && guid != Guid.Empty),
            CoordinationRoot = coordinationRoot,
            CoordinationRequired = Flag(value, "CoordinationRequired"),
            ReserveNamesInAd = Flag(value, "ReserveNamesInAD"),
            AllowPrecreatedJoin = Flag(value, "AllowPrecreatedJoin"),
            BlockJoinOnClockSkew = Flag(value, "BlockJoinOnClockSkew"),
            IncidentMode = Flag(value, "IncidentMode"),
            AuditEventLogEnabled = Flag(value, "AuditEventLogEnabled"),
            Scenario = value.TryGetProperty("Scenario", out var scenario) ? V1ScenarioPolicy.Read(scenario, errors) : null,
        };
    }

    private static bool Flag(JsonElement value, string name) => value.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.True;

    private static IReadOnlyList<string> ReadList(JsonElement policy, string name, List<string> errors, Func<string, bool> valid)
    {
        if (!policy.TryGetProperty(name, out var list)) return [];
        if (list.ValueKind != JsonValueKind.Array || list.GetArrayLength() > 200)
        {
            errors.Add("POLICY." + name + " : tableau de 200 valeurs au plus attendu.");
            return [];
        }
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in list.EnumerateArray())
        {
            var text = item.ValueKind == JsonValueKind.String ? item.GetString()! : "";
            if (text.Length is < 1 or > 4096 || text.Any(char.IsControl) || !valid(text))
                errors.Add("POLICY." + name + " : valeur invalide.");
            else result.Add(text);
        }
        return result.ToArray();
    }

    public string? BlockReason(string kind)
    {
        if (Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1") return ReadOnlyReason;
        if (VerificationFailure is not null) return VerificationFailure;
        if (IncidentMode) return "POLICY.IncidentMode : les nouvelles mutations sont suspendues ; les diagnostics restent disponibles.";
        return null;
    }

    public void RequireSupported(string kind)
    {
        if (BlockReason(kind) is { } reason) throw new PestoException(reason == ReadOnlyReason ? "policy.readonly" : IncidentMode ? "policy.incident" : "policy.unsupported", reason);
    }

    public bool IsNameExcluded(string name) => ExcludedNames.Any(pattern => V1Config.MatchesWildcard(pattern, name));

    public void AssertExclusions(string? computer, string? newName, string? sourceOu, string? targetOu)
    {
        foreach (var name in new[] { computer, newName })
            if (!string.IsNullOrEmpty(name) && IsNameExcluded(name))
                throw new PestoException("policy.excluded_name", "La cible ou le nouveau nom est exclu par POLICY.ExcludedNames : aucune préparation ni mutation.");
        foreach (var ou in new[] { sourceOu, targetOu })
            if (ou is not null && ExcludedOus.Any(excluded => ou.Equals(excluded, StringComparison.OrdinalIgnoreCase)
                || ou.EndsWith("," + excluded, StringComparison.OrdinalIgnoreCase)))
                throw new PestoException("policy.excluded_ou", "L’OU source ou destination, ou l’un de ses parents, est exclu par POLICY.ExcludedOUs : aucune mutation.");
    }

    public void AssertPlan(string kind, string computer, string newName, string? sourceOu, string targetOu, NamingConvention convention)
    {
        RequireSupported(kind);
        AssertExclusions(computer, newName, sourceOu, targetOu);
        Scenario?.AssertValues(convention.TryParse(newName), targetOu);
    }
}

/// <summary>Port of V1 Scenario.Required/Allowed/Locked; comparisons deliberately retain the V1 case sensitivity.</summary>
internal sealed record V1ScenarioPolicy(string Name, IReadOnlyList<string> Required,
    IReadOnlyDictionary<string, IReadOnlyList<string>> Allowed, IReadOnlyDictionary<string, string> Locked)
{
    private static readonly string[] Fields = ["Type", "SiteCode", "ServiceCode", "TargetOU"];

    public static V1ScenarioPolicy? Read(JsonElement value, List<string> errors)
    {
        if (value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind != JsonValueKind.Object)
        { errors.Add("POLICY.Scenario : objet attendu."); return null; }
        var expected = new[] { "Schema", "Name", "Required", "Allowed", "Locked" };
        if (value.EnumerateObject().Any(p => !expected.Contains(p.Name, StringComparer.Ordinal))
            || expected.Any(name => !value.TryGetProperty(name, out _)))
        { errors.Add("POLICY.Scenario : schéma fermé incomplet ou champ inconnu."); return null; }
        var schema = value.GetProperty("Schema");
        var nameNode = value.GetProperty("Name");
        var name = nameNode.ValueKind == JsonValueKind.String ? nameNode.GetString()! : "";
        if (schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var number) || number != 1
            || name.Length is < 1 or > 80 || name.Any(char.IsControl)) errors.Add("POLICY.Scenario : schéma ou nom invalide.");
        var requiredNode = value.GetProperty("Required");
        var required = new List<string>();
        if (requiredNode.ValueKind != JsonValueKind.Array || requiredNode.GetArrayLength() > 4)
            errors.Add("POLICY.Scenario.Required : quatre champs connus au plus attendus.");
        else foreach (var field in requiredNode.EnumerateArray())
        {
            if (field.ValueKind != JsonValueKind.String || !Fields.Contains(field.GetString(), StringComparer.Ordinal))
                errors.Add("POLICY.Scenario.Required : champ inconnu.");
            else required.Add(field.GetString()!);
        }
        var allowed = ReadMap(value.GetProperty("Allowed"), errors, locked: false);
        var locks = ReadMap(value.GetProperty("Locked"), errors, locked: true);
        foreach (var field in locks)
            if (allowed.TryGetValue(field.Key, out var choices) && !choices.Contains(field.Value[0], StringComparer.Ordinal))
                errors.Add("POLICY.Scenario.Locked : verrou hors des valeurs autorisées.");
        return new(name, required, allowed, locks.ToDictionary(p => p.Key, p => p.Value[0], StringComparer.Ordinal));
    }

    private static Dictionary<string, IReadOnlyList<string>> ReadMap(JsonElement value, List<string> errors, bool locked)
    {
        var result = new Dictionary<string, IReadOnlyList<string>>(StringComparer.Ordinal);
        if (value.ValueKind != JsonValueKind.Object) { errors.Add("POLICY.Scenario : Allowed et Locked exigent des objets."); return result; }
        foreach (var field in value.EnumerateObject())
        {
            if (!Fields.Contains(field.Name, StringComparer.Ordinal)) { errors.Add("POLICY.Scenario : champ inconnu."); continue; }
            var elements = field.Value.ValueKind == JsonValueKind.Array && !locked ? field.Value.EnumerateArray().ToArray() : [field.Value];
            if (elements.Length is < 1 or > 200 || elements.Any(v => v.ValueKind != JsonValueKind.String || v.GetString()!.Length is < 1 or > 4096 || v.GetString()!.Any(char.IsControl)))
            { errors.Add("POLICY.Scenario : valeur ou liste invalide."); continue; }
            result[field.Name] = elements.Select(v => v.GetString()!).ToArray();
        }
        return result;
    }

    public void AssertValues(NamingConvention.NameParts? parts, string targetOu)
    {
        var values = new Dictionary<string, string>(StringComparer.Ordinal)
        { ["Type"] = parts?.Type ?? "", ["SiteCode"] = parts?.Site ?? "", ["ServiceCode"] = parts?.Service ?? "", ["TargetOU"] = targetOu };
        foreach (var (field, value) in values)
            if ((Required.Contains(field, StringComparer.Ordinal) && value.Length == 0)
                || (Allowed.TryGetValue(field, out var allowed) && !allowed.Contains(value, StringComparer.Ordinal))
                || (Locked.TryGetValue(field, out var locked) && value != locked))
                throw new PestoException("policy.scenario", $"Scénario « {Name} » : le champ {field} est obligatoire, interdit ou verrouillé ; aucun plan contraire à la politique.");
    }
}

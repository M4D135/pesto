using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Closed, data-only configuration format. Exports never copy a user's configuration file wholesale.</summary>
public static class ConfigurationDocument
{
    public const int MaximumBytes = 1_048_576;

    /// <summary>Read one bounded, stable snapshot with strict BOM-aware decoding. Never replace invalid bytes.</summary>
    public static string ReadFile(string path) => ConfigurationStore.Read(path);

    private static readonly string[] ConfFields = ["Domaine", "Prefixe", "PreprodSite", "DirectProd", "DarkMode", "Buffer", "OUScanNoms", "EntraPolicy", "DsregLeaveOnMove", "ClearProtectionOnMove", "MoveRollbackOnRenameFail", "AllowHybridRepair"];
    private static readonly string[] PolicyFields = ["Schema", "Scenario", "ExcludedNames", "ExcludedOUs", "ExcludedGroupGuids", "CoordinationRoot", "CoordinationRequired", "AllowPasswordTaskFallback", "AllowPrecreatedJoin", "AllowOfflineJoin", "BlockJoinOnClockSkew", "MaxReaders", "ReadAttempts", "MaxBatch", "NameReservationMinutes", "ReserveNamesInAD", "RandomNameEnabled", "RandomNameChoice", "LogRetentionDays", "UnattendedJoinEnabled", "UnattendedOperationsEnabled", "IncidentMode", "AuditEventLogEnabled"];

    public static JsonObject Sanitize(string text)
    {
        var source = ParseObject(text);
        RequireExactFieldCase(source, ["Configured", "CONF", "OUBase", "OUSite", "TAGS", "NameCatalogue", "NamingConvention", "POLICY", "V2DirectorySites", "ReferenceData"]);
        var result = new JsonObject { ["Configured"] = source.ContainsKey("Configured") ? source["Configured"]?.DeepClone() : JsonValue.Create(true) };
        if (source["CONF"] is not JsonArray conf || conf.Count != 1 || conf[0] is not JsonObject confObject)
            throw Invalid("CONF doit contenir exactement un objet.");
        result["CONF"] = new JsonArray(CopyScalarObject(confObject, ConfFields));
        CopyRows(source, result, "OUBase", ["Nom", "OU"], row => String(row, "Nom"));
        CopyRows(source, result, "OUSite", ["Nom", "OU"], row => String(row, "Nom"));
        CopyRows(source, result, "TAGS", ["Site", "Tag"], row => String(row, "Site"));
        CopyRows(source, result, "NameCatalogue", ["Site", "Service"], row => String(row, "Site") + "|" + String(row, "Service"));
        if (source["NamingConvention"] is JsonObject convention)
        {
            var copy = CopyScalarObject(convention, ["Schema", "Id", "Types"]);
            copy["Tokens"] = CopyStrings(convention["Tokens"], 5);
            copy["Widths"] = convention["Widths"] is JsonObject widths
                ? CopyScalarObject(widths, ["Prefix", "Site", "Service", "Number"]) : throw Invalid("Largeurs de convention absentes.");
            result["NamingConvention"] = copy;
        }
        else if (source["NamingConvention"] is not null) throw Invalid("Convention invalide.");
        if (source["POLICY"] is JsonObject policy)
        {
            // A policy is not a preference: dropping an unknown/misspelled restriction could weaken it.
            // Preserve every accepted value, including Scenario's closed structured contract and explicit null.
            // V1Config below validates this exact payload (types, 200-item lists, lengths, scenario locks).
            RequireFields(policy, PolicyFields);
            result["POLICY"] = policy.DeepClone();
        }
        else if (source["POLICY"] is not null) throw Invalid("Politique invalide.");
        else if (source.ContainsKey("POLICY")) result["POLICY"] = null;
        CopyRows(source, result, "V2DirectorySites", ["Id", "Name", "Code", "OU"], row => String(row, "Id"));
        if (source["ReferenceData"] is JsonObject reference)
        {
            var copy = CopyScalarObject(reference, ["Schema", "Version"]);
            CopyRows(reference, copy, "ServiceLabels", ["Site", "Service", "Name"], row => String(row, "Site") + "|" + String(row, "Service"));
            result["ReferenceData"] = copy;
        }
        else if (source["ReferenceData"] is not null) throw Invalid("Référentiel invalide.");
        var canonical = Canonical(result);
        _ = V1Config.ValidateText(canonical);
        return ParseObject(canonical);
    }

    public static JsonObject Export(string configuration, string version)
    {
        ValidateVersion(version);
        var clean = Sanitize(configuration);
        return new JsonObject
        {
            ["schema"] = 1, ["kind"] = "pesto.configuration", ["version"] = version,
            ["fingerprint"] = Fingerprint(clean), ["configuration"] = clean
        };
    }

    public static JsonObject ValidateBundle(string text)
    {
        var bundle = ParseObject(text);
        RequireFields(bundle, ["schema", "kind", "version", "fingerprint", "configuration"]);
        if (bundle["schema"] is not JsonValue schema || !schema.TryGetValue<int>(out var schemaNumber) || schemaNumber != 1
            || String(bundle, "kind") != "pesto.configuration" || bundle["configuration"] is not JsonObject original)
            throw Invalid("Format de configuration distribuée non reconnu.");
        ValidateVersion(String(bundle, "version"));
        var clean = Sanitize(original.ToJsonString());
        if (Canonical(clean) != Canonical(original))
            throw Invalid("La configuration distribuée contient des champs non diffusables ou non canoniques.");
        if (!string.Equals(String(bundle, "fingerprint"), Fingerprint(clean), StringComparison.Ordinal))
            throw Invalid("L’empreinte de la configuration distribuée ne correspond pas à son contenu.");
        return bundle;
    }

    public static string Fingerprint(JsonNode node) => Hash(Canonical(node));
    internal static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    public static string Canonical(JsonNode node) => Sort(node).ToJsonString();
    private static JsonNode Sort(JsonNode node) => node switch
    {
        JsonObject obj => new JsonObject(obj.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => new KeyValuePair<string, JsonNode?>(p.Key, p.Value is null ? null : Sort(p.Value)))),
        JsonArray array => new JsonArray(array.Select(n => n is null ? null : Sort(n)).ToArray()),
        _ => node.DeepClone()
    };

    internal static JsonObject ParseObject(string text)
    {
        if (Encoding.UTF8.GetByteCount(text) > MaximumBytes) throw Invalid("Document trop volumineux (limite 1 Mio).");
        try
        {
            using var document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 24 });
            CheckDuplicateProperties(document.RootElement);
            return JsonNode.Parse(text) as JsonObject ?? throw Invalid("Objet JSON attendu.");
        }
        catch (JsonException) { throw Invalid("Document JSON illisible."); }
    }

    private static void CheckDuplicateProperties(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in element.EnumerateObject())
            {
                if (!seen.Add(property.Name)) throw Invalid("Champ JSON répété : " + property.Name);
                CheckDuplicateProperties(property.Value);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var child in element.EnumerateArray()) CheckDuplicateProperties(child);
    }

    private static JsonObject CopyScalarObject(JsonObject source, string[] allowed)
    {
        RequireExactFieldCase(source, allowed);
        var result = new JsonObject();
        foreach (var name in allowed)
            if (source.TryGetPropertyValue(name, out var value))
            {
                // Keep null for the schema validator; removing it would turn an invalid explicit guard into its default.
                if (value is null) { result[name] = null; continue; }
                if (value.GetValueKind() is not (JsonValueKind.String or JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False))
                    throw Invalid("Valeur simple attendue pour " + name + ".");
                if (value.GetValueKind() == JsonValueKind.String && (value.GetValue<string>().Length > 4096 || value.GetValue<string>().Any(char.IsControl)))
                    throw Invalid("Texte invalide pour " + name + ".");
                result[name] = value.DeepClone();
            }
        return result;
    }

    private static void RequireExactFieldCase(JsonObject source, string[] known)
    {
        foreach (var key in source.Select(p => p.Key))
            if (!known.Contains(key, StringComparer.Ordinal) && known.Contains(key, StringComparer.OrdinalIgnoreCase))
                throw Invalid("Respectez le nom exact du champ de configuration : " + key + ".");
    }

    private static JsonArray CopyStrings(JsonNode? source, int maximum)
    {
        if (source is not JsonArray array || array.Count > maximum) throw Invalid("Liste de textes invalide.");
        var result = new JsonArray();
        foreach (var value in array)
        {
            if (value?.GetValueKind() != JsonValueKind.String || value.GetValue<string>().Length > 2048 || value.GetValue<string>().Any(char.IsControl))
                throw Invalid("Texte attendu dans la liste.");
            result.Add(value.DeepClone());
        }
        return result;
    }

    private static void CopyRows(JsonObject source, JsonObject target, string property, string[] fields, Func<JsonObject, string> key)
    {
        if (source[property] is null) return;
        if (source[property] is not JsonArray rows || rows.Count > 2000) throw Invalid("Liste invalide : " + property);
        var result = new JsonArray();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var node in rows)
        {
            var row = node as JsonObject ?? throw Invalid("Objet attendu dans " + property);
            var clean = CopyScalarObject(row, fields);
            foreach (var field in fields) _ = String(clean, field);
            if (!seen.Add(key(clean))) throw Invalid("Doublon dans " + property + ".");
            result.Add(clean);
        }
        target[property] = result;
    }

    internal static void RequireFields(JsonObject obj, string[] allowed)
    {
        foreach (var key in obj.Select(p => p.Key))
            if (!allowed.Contains(key, StringComparer.Ordinal)) throw Invalid("Champ non autorisé : " + key);
    }

    internal static string String(JsonObject obj, string name)
    {
        if (obj[name]?.GetValueKind() != JsonValueKind.String) throw Invalid("Texte requis : " + name);
        var value = obj[name]!.GetValue<string>().Trim();
        if (value.Length is < 1 or > 4096 || value.Any(char.IsControl)) throw Invalid("Texte invalide : " + name);
        return value;
    }

    internal static void ValidateVersion(string version)
    {
        if (!Regex.IsMatch(version, "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")) throw Invalid("Version de configuration invalide.");
    }

    internal static PestoException Invalid(string message) => new("config.invalid", message);
}

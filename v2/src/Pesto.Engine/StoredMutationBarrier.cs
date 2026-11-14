using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Pesto.Engine;

/// <summary>Port of V1 Assert-PestoAcknowledgement/Test-PestoAcknowledgedReceipt. A receipt is never repaired here.</summary>
public static class StoredMutationBarrier
{
    public static bool IsAcknowledged(JsonElement receipt)
    {
        if (receipt.ValueKind != JsonValueKind.Object) return false;
        if (!receipt.TryGetProperty("Acknowledged", out var ack) || !Closed(ack, "Schema", "Utc", "By", "Reason", "Phase", "ResultCode", "Observation")) return false;
        if (!One(ack.GetProperty("Schema")) || !Date(ack.GetProperty("Utc"), false)
            || !Text(ack.GetProperty("By"), 1, 256) || !Text(ack.GetProperty("Reason"), 3, 500)) return false;
        var phase = ack.GetProperty("Phase");
        if (phase.ValueKind != JsonValueKind.String || phase.GetString() is not ("Running" or "PendingRestart" or "Partial" or "MoveReady" or "Protection" or "Uncertain")) return false;
        if (!receipt.TryGetProperty("Phase", out var actualPhase) || actualPhase.ValueKind != JsonValueKind.String || actualPhase.GetString() != phase.GetString()) return false;
        var code = ack.GetProperty("ResultCode");
        if (code.ValueKind != JsonValueKind.Null && (code.ValueKind != JsonValueKind.Number || !code.TryGetInt32(out _))) return false;
        var hasCode = (receipt.TryGetProperty("ResultCode", out var actualCode) || receipt.TryGetProperty("Code", out actualCode)) && actualCode.ValueKind != JsonValueKind.Null;
        if (hasCode != (code.ValueKind != JsonValueKind.Null)) return false;
        if (hasCode && (actualCode.ValueKind != JsonValueKind.Number || !actualCode.TryGetInt32(out var number) || code.GetInt32() != number)) return false;
        var observation = ack.GetProperty("Observation");
        return observation.ValueKind == JsonValueKind.Null || Observation(observation);
    }

    private static bool Observation(JsonElement value)
    {
        if (!Closed(value, "Schema", "CapturedUtc", "ADUtc", "WindowsUtc", "HealthUtc", "AD", "Windows", "Health") || !One(value.GetProperty("Schema"))) return false;
        foreach (var name in new[] { "CapturedUtc", "ADUtc", "WindowsUtc", "HealthUtc" })
            if (!Date(value.GetProperty(name), name != "CapturedUtc")) return false;
        var schemas = new Dictionary<string, string[]>
        {
            ["AD"] = ["Name", "Guid", "OU", "Protected"],
            ["Windows"] = ["ActiveName", "ConfiguredName", "Domain", "PartOfDomain", "MachineId", "BootUtc", "DomainRole"],
            ["Health"] = ["Scope", "AzureAdJoined", "DomainJoined", "SecureChannel"]
        };
        foreach (var (name, keys) in schemas)
        {
            var part = value.GetProperty(name);
            if (part.ValueKind == JsonValueKind.Null) continue;
            if (!Closed(part, keys)) return false;
            foreach (var key in keys)
            {
                var item = part.GetProperty(key);
                if (item.ValueKind == JsonValueKind.Null) continue;
                if (key is "Protected" or "PartOfDomain" or "SecureChannel")
                {
                    if (item.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
                }
                else if (key == "DomainRole")
                {
                    if (item.ValueKind != JsonValueKind.Number || !item.TryGetInt32(out var role) || role is < 0 or > 5) return false;
                }
                else if (key is "AzureAdJoined" or "DomainJoined")
                {
                    if (item.ValueKind != JsonValueKind.String || item.GetString() is not ("YES" or "NO" or "Unknown" or "")) return false;
                }
                else if (!Text(item, 0, 4096)) return false;
            }
            if (name == "AD" && part.GetProperty("Guid") is { ValueKind: JsonValueKind.String } guid && !string.IsNullOrEmpty(guid.GetString()))
                if (!Guid.TryParse(guid.GetString(), out var parsed) || parsed == Guid.Empty) return false;
        }
        return true;
    }

    private static bool Closed(JsonElement value, params string[] fields)
    {
        if (value.ValueKind != JsonValueKind.Object) return false;
        var names = value.EnumerateObject().Select(p => p.Name).ToArray();
        return names.Length == fields.Length && names.Distinct(StringComparer.Ordinal).Count() == fields.Length
            && fields.All(name => value.TryGetProperty(name, out _));
    }

    private static bool One(JsonElement value) => value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var n) && n == 1;
    private static bool Text(JsonElement value, int minimum, int maximum) => value.ValueKind == JsonValueKind.String
        && value.GetString() is { } s && s.Trim().Length >= minimum && s.Length <= maximum && !s.Any(char.IsControl);
    private static bool Date(JsonElement value, bool emptyAllowed)
    {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { Length: <= 64 } s) return false;
        if (s.Length == 0) return emptyAllowed;
        return Regex.IsMatch(s, @"(Z|[+-][0-9]{2}:[0-9]{2})$")
            && DateTimeOffset.TryParse(s, CultureInfo.InvariantCulture, DateTimeStyles.None, out _);
    }
}

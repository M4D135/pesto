using System.Globalization;
using System.Text.Json.Nodes;

// Legacy intervention history is not an active GP barrier. Never rewrite or mark it successful.
// Called only after exact current VM/name/boot/AD/source-receipt validation, under the GP mutex.
internal static class RestoreHistoryPolicy
{
    internal static JsonArray Validate(JsonNode history, string currentName, DateTimeOffset boot, DateTimeOffset sourceTime)
    {
        var retained = new JsonArray();
        var ids = new HashSet<string>(StringComparer.Ordinal);
        if (history["items"] is not JsonArray items) throw Refused();
        foreach (var entry in items)
        {
            if (entry is not JsonObject || entry["readable"]?.GetValue<bool>() != true) throw Refused();
            var id = entry["id"]?.GetValue<string>() ?? "";
            if (id.Length == 0 || !ids.Add(id)) throw Refused();
            var status = entry["status"]?.GetValue<string>();
            if (status is "succeeded" or "failed" or "refused") continue;
            if (status != "pendingRestart"
                || entry["mode"]?.GetValue<string>() != "V1 · registre local GP (relu, lecture seule)"
                || !Guid.TryParseExact(id, "N", out _)
                || !DateTimeOffset.TryParse(entry["time"]?.GetValue<string>(), CultureInfo.InvariantCulture, DateTimeStyles.None, out var time)
                || time >= boot || time >= sourceTime
                || string.IsNullOrWhiteSpace(entry["computer"]?.GetValue<string>())
                || string.IsNullOrWhiteSpace(entry["newName"]?.GetValue<string>())
                || string.Equals(entry["computer"]?.GetValue<string>(), currentName, StringComparison.OrdinalIgnoreCase)
                || string.Equals(entry["newName"]?.GetValue<string>(), currentName, StringComparison.OrdinalIgnoreCase))
                throw Refused();
            retained.Add(new JsonObject { ["id"] = id, ["time"] = time.ToString("O"), ["status"] = status,
                ["reason"] = "Legacy intervention before the observed boot and verified current rename; retained unchanged. Active raw GP barriers are checked separately." });
        }
        return retained;
    }
    private static InvalidOperationException Refused() => new("An active, ambiguous or unresolved durable receipt remains; restore refused.");
}

using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellDirectoryGateway : IGroupExclusionReader
{
    public GroupExclusionObservation ReadGroupExclusions(string domain, string? dc, string computerGuid, IReadOnlyList<string> excludedGroupGuids)
    {
        if (!Guid.TryParse(computerGuid, out var id) || id == Guid.Empty)
            throw new PestoException("policy.group_unverified", "Identité AD de politique invalide.");
        var groups = GroupExclusionGuard.Normalize(excludedGroupGuids);
        if (groups.Count == 0) throw new PestoException("policy.group_unverified", "Aucun groupe demandé au lecteur d’exclusions.");
        var result = Run("groups", Payload(domain, dc, ("ComputerGuid", id.ToString("D")), ("ExcludedGroupGuids", groups)));
        static string? Text(JsonElement value, string name) => value.TryGetProperty(name, out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() : null;
        if (result.ValueKind != JsonValueKind.Object || !result.TryGetProperty("checkedGroupGuids", out var list)
            || list.ValueKind != JsonValueKind.Array || list.GetArrayLength() > 200 || list.EnumerateArray().Any(p => p.ValueKind != JsonValueKind.String))
            throw new PestoException("policy.group_unverified", "Résultat de lecture des exclusions incomplet.");
        return new(Text(result, "computerGuid") ?? "", domain, string.IsNullOrWhiteSpace(dc) ? domain : dc,
            Text(result, "computerName"), Text(result, "sourceOu"), list.EnumerateArray().Select(p => p.GetString()!).ToArray(),
            result.TryGetProperty("complete", out var complete) && complete.ValueKind == JsonValueKind.True,
            result.TryGetProperty("domainController", out var role) && role.ValueKind is JsonValueKind.True or JsonValueKind.False ? role.GetBoolean() : null,
            Text(result, "excludedGroupGuid"), DateTimeOffset.UtcNow);
    }
}

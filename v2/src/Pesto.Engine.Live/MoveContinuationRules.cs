using System.Text.Json;
using Pesto.Engine;

namespace Pesto.Engine.Live;

/// <summary>Fail-closed rules used by the native continuation path and its portable safety tests.</summary>
public static class MoveContinuationRules
{
    private static bool Same(string? a, string? b) => !string.IsNullOrEmpty(a) && !string.IsNullOrEmpty(b)
        && string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    private static bool Digest(string? value) => value is { Length: 64 } && value.All(char.IsAsciiHexDigit);
    private static bool Id(string? value) => Guid.TryParse(value, out var id) && id != Guid.Empty;

    public static string? EvidenceRefusal(ReceiptReconciliationObservation e, string? savedTargetGuid, string? observedTargetGuid)
    {
        if (e.Receipt.Kind != "renameMove" || e.Receipt.Code != 89 || e.Receipt.Status is not ("pendingRestart" or "uncertain")
            || e.Receipt.ResolutionChildReceiptId is not null)
            return "Seul le déplacement restant d’un renommage-déplacement de code 89 non résolu peut être préparé.";
        if (e.Error is not null || ReceiptWindowsEvidence.IdentityRefusal(e) is not null || e.InitialBootUtc is null
            || e.CurrentBootUtc is null || e.CurrentBootUtc <= e.InitialBootUtc || e.WindowsPartOfDomain != true
            || e.SecureChannel != true || !Same(e.Domain, e.WindowsDomain))
            return "Le redémarrage, l’identité Windows prouvée, le domaine et le canal sécurisé ne sont pas tous confirmés.";
        if (!Id(e.ExpectedGuid) || !Same(e.ExpectedGuid, e.AdGuid) || !Same(e.Receipt.NewName, e.AdName)
            || !Same(e.Receipt.NewName, e.WindowsActiveName) || !Same(e.Receipt.NewName, e.WindowsConfiguredName))
            return "Le même GUID doit porter le nouveau nom confirmé dans Windows actif, Windows configuré et AD.";
        if (!Same(e.InitialOu, e.AdOu) || string.IsNullOrEmpty(e.Receipt.TargetOU) || Same(e.InitialOu, e.Receipt.TargetOU)
            || e.InitialProtected is null || e.AdProtected != e.InitialProtected)
            return "L’objet doit être dans l’OU initiale, avec sa protection initiale inchangée et une destination distincte.";
        if (!Id(savedTargetGuid) || !Same(savedTargetGuid, observedTargetGuid))
            return "Le GUID de la destination originale n’est plus confirmé : aucun déplacement préparé.";
        return null;
    }

    public static bool RequestMatches(MoveContinuationAuthorization a, MutationRequest r, DateTimeOffset now) =>
        r.Continuation == a && a.ExpiresAt > now && a.ExpiresAt <= now.AddMinutes(5)
        && r.Kind == "move" && string.IsNullOrEmpty(r.NewName) && r.PlanId == a.PlanId && r.ReceiptId != a.ParentReceiptId
        && Same(r.Computer, a.Computer) && Id(a.ComputerGuid) && Same(r.ComputerGuid, a.ComputerGuid)
        && Same(r.SourceOu, a.SourceOu) && Same(r.TargetOu, a.TargetOu) && Id(a.TargetOuGuid) && Same(r.TargetOuGuid, a.TargetOuGuid);

    private static string? Text(JsonElement e, string key) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v)
        && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    private static bool? Flag(JsonElement e, string key) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(key, out var v)
        && v.ValueKind is JsonValueKind.True or JsonValueKind.False ? v.GetBoolean() : null;
    public static bool IsPartialParent(JsonElement p) => Text(p, "Kind") == "renameMove" && Text(p, "Phase") == "Partial"
        && p.TryGetProperty("Code", out var code) && code.TryGetInt32(out var n) && n == 89 && Flag(p, "RestartRequired") == false;

    /// <summary>Link identity is required even for a failed child; no missing, foreign or ambiguous attempt is ignored.</summary>
    public static bool IsLinkedChild(JsonElement p, JsonElement c) => IsPartialParent(p)
        && Text(c, "Kind") == "move" && string.IsNullOrEmpty(Text(c, "NewName"))
        && Same(Text(c, "ParentReceiptId"), Text(p, "ReceiptId"))
        && Same(Text(c, "ReceiptId"), Text(p, "ContinuationChildReceiptId"))
        && Same(Text(c, "PlanId"), Text(p, "ContinuationChildPlanId"))
        && Digest(Text(c, "ParentReceiptSha256")) && Digest(Text(c, "ContinuationAttemptId"))
        && Same(Text(c, "ParentReceiptSha256"), Text(p, "ContinuationParentReceiptSha256"))
        && Same(Text(c, "ContinuationAttemptId"), Text(p, "ContinuationAttemptId"))
        && Same(Text(c, "Computer"), Text(p, "NewName")) && Id(Text(p, "ComputerGuid"))
        && Same(Text(c, "ComputerGuid"), Text(p, "ComputerGuid")) && Same(Text(c, "Domain"), Text(p, "Domain"))
        && Flag(p, "LocalTarget") is { } local && Flag(c, "LocalTarget") == local
        && (local || ReceiptWindowsEvidence.RemoteBaselineMatches(p) && ReceiptWindowsEvidence.RemoteBaselineMatches(c))
        && Same(Text(p, "MachineId"), Text(c, "MachineId"))
        && DateTimeOffset.TryParse(Text(p, "InitialBootUtc"), out var initialBoot)
        && DateTimeOffset.TryParse(Text(c, "InitialBootUtc"), out var childBoot) && childBoot > initialBoot
        && Same(Text(c, "TargetOu"), Text(p, "TargetOu")) && Id(Text(p, "TargetOuGuid"))
        && Same(Text(c, "TargetOuGuid"), Text(p, "TargetOuGuid")) && Same(Text(c, "InitialOu"), Text(p, "InitialOu"))
        && Flag(p, "InitialProtected") is { } protection && Flag(c, "InitialProtected") == protection;

    /// <summary>A parent resolution written before its child is durable does not release the barrier.</summary>
    public static bool IsResolved(JsonElement parent, JsonElement child, string childSha256) => IsLinkedChild(parent, child)
        && Text(child, "Phase") == "Verified" && Flag(child, "RestartRequired") == false
        && Same(Text(parent, "ResolutionChildReceiptId"), Text(child, "ReceiptId"))
        && Digest(childSha256) && Same(Text(parent, "ResolutionChildReceiptSha256"), childSha256)
        && DateTimeOffset.TryParse(Text(parent, "ResolutionUtc"), out _);
}

/// <summary>Native memory only; a fresh preparation replaces all grants for its parent, and consume is atomic.</summary>
public sealed class MoveContinuationGrants
{
    private readonly object gate = new();
    private readonly Dictionary<string, MoveContinuationAuthorization> grants = new(StringComparer.Ordinal);
    public void Invalidate(string parentId) { lock (gate) grants.Remove(parentId); }
    public void Add(MoveContinuationAuthorization authorization)
    {
        lock (gate)
        {
            foreach (var expired in grants.Where(x => x.Value.ExpiresAt <= DateTimeOffset.UtcNow).Select(x => x.Key).ToArray()) grants.Remove(expired);
            if (grants.Count >= 128 && !grants.ContainsKey(authorization.ParentReceiptId)) throw new InvalidOperationException("Trop de préparations actives.");
            grants[authorization.ParentReceiptId] = authorization;
        }
    }
    public bool Contains(MoveContinuationAuthorization authorization, DateTimeOffset now)
    { lock (gate) return grants.TryGetValue(authorization.ParentReceiptId, out var saved) && saved == authorization && saved.ExpiresAt > now; }
    public bool Consume(MoveContinuationAuthorization authorization, DateTimeOffset now)
    {
        lock (gate)
        {
            if (!grants.TryGetValue(authorization.ParentReceiptId, out var saved) || saved != authorization || saved.ExpiresAt <= now) return false;
            grants.Remove(authorization.ParentReceiptId);
            return true;
        }
    }
}

namespace Pesto.Engine;

/// <summary>Observed machine restrictions. Only the native live adapter reads HKLM; no demo probes this provider.</summary>
public sealed record MutationManagedPolicy(bool IncidentMode = false, int? MaxBatch = null, string? ScenarioJson = null, string? Refusal = null,
    bool DisableUnattendedJoin = false, bool DisableUnattendedOperations = false, string? CampaignApprovalJson = null);

public interface IMutationManagedPolicy
{
    MutationManagedPolicy ReadManagedPolicy();
}

/// <summary>Pure, validated requirements shared with native readers. No policy is inferred from a partial JSON read.</summary>
public sealed record MutationPolicyRequirements(bool AuditEventLogEnabled, bool BlockJoinOnClockSkew, IReadOnlyList<string> ExcludedGroupGuids);

/// <summary>Shared admission rule for the engine and the native adapter's final pre-send check, including process consultation.</summary>
public static class MutationPolicyGuard
{
    public static string? ConfigurationRefusal(ReadOnlySpan<byte> configurationBytes, string? expectedSha256)
    {
        if (expectedSha256 is not { Length: 64 } || !expectedSha256.All(Uri.IsHexDigit))
            return "L’empreinte complète de la configuration du plan est absente : aucune mutation ni coordination engagée.";
        var actual = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(configurationBytes));
        return actual.Equals(expectedSha256, StringComparison.OrdinalIgnoreCase) ? null
            : "La configuration a changé depuis la préparation confirmée : aucune mutation ni coordination engagée. Préparez un nouveau plan.";
    }

    public static MutationPolicyRequirements ReadRequirements(string configurationJson)
    {
        var policy = V1Config.ValidateText(configurationJson).OperationPolicy;
        return new(policy.AuditEventLogEnabled, policy.BlockJoinOnClockSkew, policy.ExcludedGroups);
    }

    public static string? Refusal(string configurationJson, MutationRequest request, MutationManagedPolicy managed)
    {
        try
        {
            var config = V1Config.ValidateText(configurationJson);
            if (!string.Equals(config.Domain, request.Domain, StringComparison.OrdinalIgnoreCase))
                return "Le domaine du plan ne correspond plus à la configuration relue : aucune mutation.";
            config.OperationPolicy.WithManaged(managed).AssertPlan(request.Kind, request.Computer, request.NewName ?? request.Computer,
                request.SourceOu, request.TargetOu ?? request.SourceOu ?? "", config.BuildConvention());
            return null;
        }
        catch (Pesto.Core.PestoException error) { return error.Message; }
    }
}

using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public sealed record EntraPreparationRequest(string Kind, string Computer, string ComputerGuid, string NewName,
    string Domain, string? Dc, string SourceOu, string ConfigurationSha256);

/// <summary>Issued by the native reader and held by the engine plan. A browser cannot supply this authorization.</summary>
public sealed record EntraRenameAuthorization(string Token, EntraPreparationRequest Request, string State,
    string Policy, string MachineId, DateTimeOffset ObservedAt, DateTimeOffset ExpiresAt)
{
    public bool LeaveRequired => State == "hybrid";
}

public interface IMutationEntraPreparation
{
    EntraRenameAuthorization PrepareEntra(EntraPreparationRequest request);
}

public sealed record EntraBarrierEvidence(bool CanAcknowledge, string? Reason, string EvidenceSha256);

/// <summary>Pure V1 decision: only an unambiguous YES/YES observation can request an explicitly permitted leave.</summary>
public static class EntraPreparationRules
{
    public const string Disabled = "Disabled";
    public const string HybridOnly = "HybridOnly";

    public static string ReadPolicy(string configuration) => V1Config.ValidateText(configuration).EntraPolicy;

    public static string State(int exitCode, string output)
    {
        if (exitCode != 0 || output.Length is 0 or > 65536) return "unknown";
        const RegexOptions options = RegexOptions.IgnoreCase | RegexOptions.Multiline | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking;
        var azure = Regex.Matches(output, @"^[ \t]*AzureAdJoined[ \t]*:[ \t]*(YES|NO)[ \t]*\r?$", options);
        var domain = Regex.Matches(output, @"^[ \t]*DomainJoined[ \t]*:[ \t]*(YES|NO)[ \t]*\r?$", options);
        if (azure.Count != 1 || domain.Count != 1 || !domain[0].Groups[1].Value.Equals("YES", StringComparison.OrdinalIgnoreCase)) return "unknown";
        return azure[0].Groups[1].Value.Equals("YES", StringComparison.OrdinalIgnoreCase) ? "hybrid" : "adOnly";
    }

    public static void ValidateRequest(EntraPreparationRequest request)
    {
        if (request.Kind is not ("rename" or "renameMove") || !Name(request.Computer) || !Name(request.NewName)
            || request.Computer.Equals(request.NewName, StringComparison.OrdinalIgnoreCase)
            || !Guid.TryParse(request.ComputerGuid, out var guid) || guid == Guid.Empty
            || request.Domain.Length is < 3 or > 253 || !Regex.IsMatch(request.Domain, @"^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$")
            || request.Dc is { Length: > 253 } || request.Dc is { } dc && dc.Any(char.IsControl)
            || request.SourceOu.Length is < 1 or > 2048 || request.SourceOu.Any(char.IsControl)
            || !Regex.IsMatch(request.ConfigurationSha256, "^[a-fA-F0-9]{64}$"))
            throw new PestoException("entra.request", "Identité, opération ou configuration de la préparation Entra invalide.");
    }

    public static void RequireAllowed(string state, string policy)
    {
        if (policy is not (Disabled or HybridOnly)) throw new PestoException("entra.policy", "Politique Entra inconnue : aucun retrait ni renommage.");
        if (state is not ("adOnly" or "hybrid")) throw new PestoException("entra.unknown", "Appartenance AD et état Entra non prouvés : aucun retrait ni renommage.");
        if (state == "hybrid" && policy != HybridOnly) throw new PestoException("entra.disabled", "Poste hybride : le retrait préalable est désactivé. Aucun retrait ni renommage.");
    }

    public static bool Name(string? value) => value is { Length: > 0 and <= 15 }
        && Regex.IsMatch(value, @"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$");
}

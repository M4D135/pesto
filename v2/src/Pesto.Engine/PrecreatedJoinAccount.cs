using Pesto.Core;

namespace Pesto.Engine;

/// <summary>The existing account observed by a native/read-only preview. This object is retained inside
/// the engine; the web API supplies only previewId/planId, never an authoritative GUID or policy flag.</summary>
public sealed record PrecreatedJoinAccount(string ComputerGuid, string Name, string Domain, string Dc,
    string TargetOu, string TargetOuGuid, string ConfigurationSha256);

/// <summary>Explicit implementation capability. A legacy adapter cannot accidentally accept this new path.</summary>
public interface IMutationPrecreatedJoin
{
    bool SupportsPrecreatedJoin { get; }
}

public static class PrecreatedJoinRules
{
    public static void Validate(PrecreatedJoinAccount account)
    {
        if (!Guid.TryParse(account.ComputerGuid, out var guid) || guid == Guid.Empty
            || !Guid.TryParse(account.TargetOuGuid, out var ou) || ou == Guid.Empty
            || !ReceiptAcknowledgementSource.IsComputer(account.Name) || !ReceiptAcknowledgementSource.IsDomain(account.Domain)
            || !JoinClockGuard.IsServer(account.Dc) || !V1Config.IsOuPath(account.TargetOu)
            || !ReceiptAcknowledgementSource.IsHash(account.ConfigurationSha256))
            throw new PestoException("join.precreated_identity", "L’identité complète du compte précréé n’est pas confirmée.");
    }

    public static void RequireRequest(MutationRequest request)
    {
        if (request.PrecreatedJoin is not { } account) return;
        Validate(account);
        if (request.Kind != "join" || request.Reservation is not null || request.ReservationRequired || request.NameReservation is not null
            || !Same(request.ComputerGuid, account.ComputerGuid) || !Same(request.NewName, account.Name)
            || !Same(request.Domain, account.Domain) || !Same(request.Dc, account.Dc)
            || !Same(request.TargetOu, account.TargetOu) || !Same(request.TargetOuGuid, account.TargetOuGuid)
            || !Same(request.ConfigurationSha256, account.ConfigurationSha256))
            throw new PestoException("join.precreated_identity", "Le compte précréé n’est plus lié au plan confirmé ; aucune création ni jonction.");
    }

    public static string? ConfigurationRefusal(string configurationJson, MutationRequest request)
    {
        try
        {
            RequireRequest(request);
            if (request.PrecreatedJoin is not { } account) return null;
            var config = V1Config.ValidateText(configurationJson);
            if (!config.OperationPolicy.AllowPrecreatedJoin) return "POLICY.AllowPrecreatedJoin est désactivée : aucun compte existant repris.";
            if (!Same(config.Domain, account.Domain) || !Within(account.TargetOu, config.RootOu)
                || !config.Production && !Same(account.TargetOu, config.PreprodOu))
                return "Le domaine ou l’OU du compte précréé sort du parcours configuré : aucune jonction.";
            config.OperationPolicy.AssertPlan("join", request.Computer, account.Name, account.TargetOu, account.TargetOu, config.BuildConvention());
            if (config.BuildConvention().TryParse(account.Name) is null) return "Le nom du compte précréé ne respecte pas la convention active.";
            return null;
        }
        catch (PestoException error) { return error.Message; }
        catch (Exception) { return "La politique du compte précréé ne peut pas être validée : aucune jonction."; }
    }

    public static bool Matches(PrecreatedJoinAccount account, DirectoryComputer? computer, DirectoryOrganizationalUnit? ou) =>
        computer is not null && ou is not null && Same(account.ComputerGuid, computer.Guid) && Same(account.Name, computer.Name)
        && Same(account.Domain, computer.Domain) && Same(account.TargetOu, computer.Ou)
        && Same(account.TargetOu, ou.DistinguishedName) && Same(account.TargetOuGuid, ou.Guid);

    private static bool Within(string value, string root) => Same(value, root) || value.EndsWith("," + root, StringComparison.OrdinalIgnoreCase);
    private static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
}

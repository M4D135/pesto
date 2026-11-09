using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private EntraRenameAuthorization? PrepareEntraPlan(string kind, string computer, string? guid, string newName,
        string domain, string? sourceOu, string configurationSha256)
    {
        if (kind is not ("rename" or "renameMove")) return null;
        if (mutation is not IMutationEntraPreparation provider)
            throw new PestoException("entra.unavailable", "Le lecteur Entra préalable au renommage n’est pas disponible : aucun plan de retrait ou de renommage n’est préparé.");
        var request = new EntraPreparationRequest(kind, computer, guid ?? "", newName, domain, DcOrNull(), sourceOu ?? "", configurationSha256);
        EntraPreparationRules.ValidateRequest(request);
        var result = provider.PrepareEntra(request);
        EntraPreparationRules.RequireAllowed(result.State, result.Policy);
        var now = clock.GetUtcNow();
        if (result.Request != request || result.ExpiresAt <= now || result.ObservedAt > now.AddSeconds(5)
            || result.ObservedAt < now.AddMinutes(-5) || result.ExpiresAt > result.ObservedAt.AddMinutes(5)
            || !RemoteWindowsEvidenceProtocol.IsGuid(result.MachineId) || string.IsNullOrWhiteSpace(result.Token))
            throw new PestoException("entra.stale", "L’observation Entra n’est pas liée à ce plan ou a expiré : aucun renommage préparé.");
        return result;
    }

    private static DateTimeOffset ExpiresWithEntra(DateTimeOffset limit, EntraRenameAuthorization? entra) =>
        entra is not null && entra.ExpiresAt < limit ? entra.ExpiresAt : limit;
}

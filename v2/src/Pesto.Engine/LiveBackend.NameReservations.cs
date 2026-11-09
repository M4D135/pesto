using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private string? CoordinationProviderRefusal(V1OperationPolicy? policy) =>
        policy is not null && (policy.CoordinationRequired || policy.CoordinationRoot.Length > 0) && mutation is not IMutationNameReservations
            ? "POLICY.CoordinationRoot : l’adaptateur des baux de noms partagés est absent. Aucun nom annoncé réservé ni mutation coordonnée préparée."
            : null;

    private IMutationNameReservations? NameReservations(V1OperationPolicy policy)
    {
        if (!policy.CoordinationRequired && policy.CoordinationRoot.Length == 0) return null;
        return mutation as IMutationNameReservations ?? throw new PestoException("names.reservation_unavailable", CoordinationProviderRefusal(policy)!);
    }

    private SharedNameReservationProof? ReservePreviewName(V1Config read, V1OperationPolicy policy, string name, string previewId)
    {
        var service = NameReservations(policy);
        if (service is null) return null;
        MutationSessionGuard.RequireWritableSession();
        RequireUnchangedConfiguration();
        var proof = service.ReservePreviewName(read.Domain, name, previewId, configStamp!);
        if (proof is null) throw new PestoException("names.reservation_unavailable", "Le bail partagé n’a pas été confirmé : aucun nom proposé.");
        ValidatePreviewNameProof(read, proof, name, configStamp!, previewId);
        return proof;
    }

    private void ValidatePreviewNameProof(V1Config read, SharedNameReservationProof proof, string name, string stamp, string? previewId = null)
    {
        SharedNameReservationProtocol.ValidateProof(proof);
        if (!string.Equals(proof.Domain, read.Domain, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(proof.Name, name, StringComparison.OrdinalIgnoreCase) || proof.ConfigSha256 != stamp
            || (previewId is not null && proof.PreviewId != previewId) || proof.ExpiresAt <= clock.GetUtcNow())
            throw new PestoException("names.reservation_changed", "Le bail partagé est périmé ou ne correspond pas au nom, au profil ou à la configuration du plan. Aucun nom de remplacement choisi.");
    }

    private void VerifyPreviewName(V1Config read, V1OperationPolicy policy, string kind, string name, SharedNameReservationProof? proof, string stamp)
    {
        var service = NameReservations(policy);
        if (kind == "move") return;
        if (service is null)
        {
            if (proof is not null) throw new PestoException("names.reservation_changed", "La coordination de cet aperçu a été désactivée : nouveau plan nécessaire.");
            return;
        }
        if (proof is null) throw new PestoException("names.reservation_required", "Le nom confirmé ne porte pas de bail partagé : préparez un nouvel aperçu.");
        ValidatePreviewNameProof(read, proof, name, stamp);
        service.VerifyPreviewName(proof, stamp);
    }

    private void ReleaseUnusedPreviewName(SharedNameReservationProof? proof)
    {
        if (proof is null || mutation is not IMutationNameReservations service) return;
        try { MutationSessionGuard.RequireWritableSession(); service.ReleasePreviewName(proof); }
        catch (Exception) { Log("Libération du bail partagé non confirmée : sa preuve et son expiration restent conservées ; aucun autre propriétaire n’est supprimé.", "warn"); }
    }

    private static DateTimeOffset ExpiresWithNameLease(DateTimeOffset ordinary, SharedNameReservationProof? proof) =>
        proof is not null && proof.ExpiresAt < ordinary ? proof.ExpiresAt : ordinary;
}

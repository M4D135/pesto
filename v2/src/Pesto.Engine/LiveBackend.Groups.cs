using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private string? lastGroupObservation;
    private bool lastGroupsConfirmed;

    private void RequireGroupExclusions(V1Config read, V1OperationPolicy policy, string? computerGuid, string computer, string? sourceOu)
    {
        // A fresh join has no AD account. It gets a group check later if an explicitly confirmed reservation creates one.
        if (policy.ExcludedGroups.Count == 0 || computerGuid is null) return;
        try
        {
            GroupExclusionGuard.Require(gateway as IGroupExclusionReader, read.Domain, DcOrNull(), computerGuid,
                policy.ExcludedGroups, computer, sourceOu, clock);
            lastGroupsConfirmed = true;
            lastGroupObservation = "Exclusions des " + policy.ExcludedGroups.Count + " groupe(s) entièrement relues par GUID, appartenances imbriquées comprises. Une nouvelle lecture est obligatoire avant chaque mutation.";
        }
        catch (PestoException error)
        {
            lastGroupsConfirmed = false; lastGroupObservation = error.Message;
            throw;
        }
    }

    private Check GroupDiagnostic(V1OperationPolicy? policy)
    {
        if (policy is null) return new("Groupes exclus", "unknown", "Configuration absente : politique de groupes non lue.");
        if (policy.ExcludedGroups.Count == 0) return new("Groupes exclus", "ok", "Aucun groupe exclu configuré ; aucune lecture d’appartenance demandée.");
        if (gateway is not IGroupExclusionReader)
            return new("Groupes exclus", "warn", "POLICY.ExcludedGroupGuids : lecteur absent. Toute mutation d’un compte AD existant est refusée ; une appartenance inconnue n’est jamais considérée autorisée.");
        return new("Groupes exclus", lastGroupObservation is null ? "unknown" : lastGroupsConfirmed ? "ok" : "warn",
            lastGroupObservation ?? "POLICY.ExcludedGroupGuids : contrôle des appartenances imbriquées demandé ; aucun compte AD n’a encore été contrôlé.");
    }
}

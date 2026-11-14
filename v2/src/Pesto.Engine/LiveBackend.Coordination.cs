using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private Check CoordinationDiagnostic(V1OperationPolicy? policy)
    {
        var cleanup = (mutation as ISharedCoordinationDisclosure)?.CoordinationCleanupStatus;
        if (cleanup is { State: "failed" }) return new("Coordination partagée", "warn",
            "Nettoyage des verrous partagés non confirmé pour le reçu " + cleanup.ReceiptId + " (" + cleanup.FailureCode + "). "
            + "Les preuves et verrous non confirmés restent conservés ; le résultat métier durable n’est pas modifié. Échecs observés : " + cleanup.Failures + ".");
        if (policy is null) return new("Coordination partagée", "unknown", "Configuration absente : registre partagé non lu.");
        if (!policy.CoordinationRequired && policy.CoordinationRoot.Length == 0)
            return new("Coordination partagée", "ok", "Aucun registre de coordination configuré ; aucun accès partagé demandé.");
        if (CoordinationProviderRefusal(policy) is { } unavailable) return new("Coordination partagée", "warn", unavailable);
        return cleanup?.State switch
        {
            "confirmed" => new("Coordination partagée", "ok", "Libération des verrous terminés confirmée pour le reçu " + cleanup.ReceiptId + ". Aucun verrou d’un autre propriétaire supprimé."),
            "retained" => new("Coordination partagée", "warn", "Le reçu " + cleanup.ReceiptId + " reste en attente ou incertain : ses verrous partagés sont conservés jusqu’à vérification explicite."),
            _ => new("Coordination partagée", "unknown", "Registre configuré ; aucune libération de verrou n’a encore été confirmée dans cette session. Le diagnostic ne sonde pas le partage.")
        };
    }
}

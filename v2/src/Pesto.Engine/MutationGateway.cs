namespace Pesto.Engine;

/// <summary>Résultat rapporté par l'adaptateur de mutation. « Uncertain » n'est jamais un échec : c'est un résultat inconnu,
/// qui bloque toute nouvelle tentative automatique (port des phases v1 PendingRestart/Uncertain de Get-PestoJoinReceiptDecision).</summary>
public enum MutationStatus
{
    /// <summary>La commande native est partie et l'adaptateur la confirme.</summary>
    Succeeded,
    /// <summary>Acceptée, effet attendu après un redémarrage explicitement planifié par l'opérateur (port exit 10 v1).</summary>
    PendingRestart,
    /// <summary>Refusée avant tout envoi : rien n'a été écrit (port Phase='Failed' v1, nouvelle vérification complète obligatoire).</summary>
    Failed,
    /// <summary>Résultat inconnu : la commande a pu partir. Jamais rejoué automatiquement (port Phase='Uncertain' v1).</summary>
    Uncertain,
}

/// <summary>
/// Demande d'une seule mutation, déjà validée par le moteur (aperçu consommé, confirmation exacte recopiée, GUID vérifié).
/// Aucun secret : jamais de mot de passe, jamais de commande arbitraire — l'adaptateur construit lui-même sa commande constante.
/// </summary>
public sealed record MutationRequest(
    string Kind,
    string Computer,
    string? ComputerGuid,
    string? NewName,
    string? TargetOu,
    string Domain,
    string? Dc,
    string PlanId,
    string ReceiptId,
    string? SourceOu = null,
    string? TargetOuGuid = null,
    MoveContinuationAuthorization? Continuation = null,
    JoinReservationAuthorization? Reservation = null,
    bool ReservationRequired = false,
    string? ConfigurationSha256 = null,
    SharedNameReservationProof? NameReservation = null,
    EntraRenameAuthorization? Entra = null,
    bool EntraLeaveConfirmed = false,
    PrecreatedJoinAccount? PrecreatedJoin = null,
    AttributeMutationPlan? Attributes = null,
    AutomationExecutionAuthorization? Automation = null);

/// <summary>Résultat brut de l'adaptateur ; le moteur le recoupe toujours par une relecture annuaire avant d'écrire l'état du reçu.</summary>
public sealed record MutationOutcome(MutationStatus Status, int Code, string Message, bool RestartRequired, string? ObservedGuid = null);

/// <summary>
/// Adaptateur d'écriture du mode réel, injecté par l'hôte Windows configuré ou par un banc explicite.
/// Son raccordement ne constitue pas une qualification : le moteur exige toujours plan frais, confirmation,
/// identité observée et reçu durable. Sans adaptateur, les demandes restent refusées par write.unavailable.
/// L'adaptateur transitoire <c>Pesto.Engine.Live.PowerShellMutationGateway</c> porte les gardes d'écriture lues dans la
/// référence v1 avant la moindre écriture native :
/// mutex global V1 <c>Global\GP_PostMutation_v1</c> acquis avant mutation et relâché en finally (Pesto.Engine.Runtime.ps1),
/// reçus de barrière GP relus avant action (Get-PestoJoinReceiptDecision : PendingRestart et Uncertain bloquent, aucune
/// nouvelle tentative automatique), reçu durable écrit AVANT la commande native — l'impossibilité d'enregistrer ce reçu bloque
/// avant Add-Computer/Rename-Computer/Set-ADComputer/Move-ADObject (Pesto-Join.ps1) —, relecture après envoi, statut incertain
/// conservé et jamais rejoué, aucune activation implicite du mode non accompagné (UnattendedJoinEnabled est lu, jamais activé),
/// aucun secret en ligne de commande, en log ou en retour.
/// </summary>
public interface IMutationGateway
{
    /// <summary>Origine observée des écritures (ex. « Windows PowerShell 5.1 · module ActiveDirectory »).</summary>
    string Description { get; }

    /// <summary>Exécute une seule mutation déjà admise par le moteur. Une exception = résultat inconnu : le moteur trace un reçu
    /// « uncertain » et refuse tout rejeu automatique ; il ne rappelle jamais cette méthode pour le même plan.</summary>
    MutationOutcome Execute(MutationRequest request);
}

/// <summary>
/// L'adaptateur relit lui-même, au dernier point avant envoi natif, l'identité source, la collision du nouveau nom,
/// l'OU cible et les exclusions/politiques nécessaires. Pour un renommage, le moteur peut alors éviter de refaire
/// exactement ces lectures juste avant Execute ; la relecture finale après mutation reste toujours obligatoire.
/// </summary>
public interface IMutationGatewayFinalReadback { }

/// <summary>
/// Divulgation d'état pour l'aperçu du plan — port du « control summary » V1 (Pesto-Core.ps1:4035 pour la confirmation
/// de file, Pesto-Direct.ps1:345 pour la confirmation unitaire) : avant de confirmer, V1 affichait la politique de repli
/// réellement lue. Un adaptateur de qualification qui lit réellement <c>POLICY.AllowPasswordTaskFallback</c> et observe
/// le mode de compte l'expose par ce contrat ; le moteur n'affiche une note de politique QUE pour un adaptateur qui
/// l'implémente — il n'invente jamais un état. La simulation n'injecte aucun adaptateur natif et n'annonce
/// aucune autorisation de repli réelle.
/// </summary>
public interface IMutationFallbackDisclosure
{
    /// <summary>État réellement lu de <c>POLICY.AllowPasswordTaskFallback</c> : « true », « false » ou « unknown »
    /// (port <see cref="TaskFallbackPolicy"/>). Jamais une valeur supposée ni un défaut de complaisance.</summary>
    string FallbackPolicyState { get; }

    /// <summary>Mode de compte observé par l'adaptateur : en session SSO le repli V1 reste refusé, comme en V1.</summary>
    TaskFallbackAccountMode FallbackAccountMode { get; }
}

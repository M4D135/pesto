using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>
/// Adaptateur Windows PowerShell 5.1 + ActiveDirectory, raccordé au profil Windows normal et au harnais.
/// L'identité Windows ou le compte AD saisi dans la fenêtre native est utilisé ; le mot de passe explicite reste
/// en mémoire, chiffré DPAPI CurrentUser pendant le transport stdin puis déchiffré dans le seul processus enfant.
/// Script constant, jamais une commande arbitraire reçue du pont. Une sélection ne lance aucune mutation.
/// Gardes d'écriture portées de V1 (lues dans ../references/pesto-v1/DEV avant codage) :
/// - mutex <c>Global\GP_PostMutation_v1</c> acquis avant mutation et relâché en finally (Pesto.Engine.Runtime.ps1) ;
/// - reçus de barrière GP relus avant action (Assert-PestoStoredMutationReady + Get-PestoJoinReceiptDecision :
///   PendingRestart et Uncertain bloquent, « aucune nouvelle tentative automatique ») ;
/// - reçu durable écrit AVANT la commande native — l'impossibilité de l'enregistrer bloque avant
///   Add-Computer/Rename-Computer/Move-ADObject (Write-PestoJoinReceipt Phase='Running' de Pesto-Join.ps1) —, complété
///   après envoi ; un reçu final qui ne s'enregistre pas rend le résultat incertain (jamais rejoué) ;
/// - refus prouvé avant envoi = Failed (rien d'écrit, port des codes v1 11/13/21/31/33/96/99) ; résultat inconnu après
///   envoi = Uncertain (port des codes 97/98) ; acceptation avec redémarrage à planifier = PendingRestart (exit 10/20) ;
///   ce chemin ne redémarre rien : toute demande de redémarrage appartient à un plan séparé explicitement confirmé ;
/// - jonction locale uniquement, élévation locale exigée, aucun compte ancien réutilisé, aucun objet supprimé ;
///   le renommage direct reste exécuté à l'identité de la session (jamais un mot de passe en ligne de commande) ;
///   le repli V1 authentifié par tâche planifiée sous compte AD est PORTÉ selon les sources V1 (Pesto-Operations.ps1
///   RenameComputer 1257-1267, Invoke-RenameComputerTaskFallback, New-PestoTaskService, New-PestoRunOnceTaskXml,
///   Get-PestoTaskRunResult, Set-PestoTaskEvidence/Assert-PestoTaskDefinition) via <see cref="PestoTaskFallbackRunner"/> :
///   uniquement renommage distant, refus confirmé 5 ou 1314, compte AD explicitement saisi par la source injectée
///   (jamais le jeton SSO), <c>POLICY.AllowPasswordTaskFallback</c> lu vrai du cfg.json — jamais activé implicitement ;
///   le mot de passe ne voyage qu'en mémoire COM du transport, jamais en arguments CLI, log, reçu, XML ou réponse du
///   pont, et le credential est purgé dès l'opération terminée ; aucun repli après un résultat incertain (règle V1) ;
///   déplacement uniquement par GUID réellement
///   observé, jamais sur un contrôleur ; protection contre la suppression accidentelle levée uniquement selon V1 :
///   CONF.ClearProtectionOnMove lu du cfg.json (absent = true, valeur appliquée par le moteur V1), levée temporaire
///   pendant le seul déplacement, toujours restaurée puis relue, code 32 si le rétablissement échoue, refus 31 si la
///   configuration l'interdit, refus 96 si la valeur n'a pas pu être lue — jamais une levée implicite ;
/// - UnattendedJoinEnabled ne désactive pas l’exécution interactive confirmée et n’autorise aucune action implicite ;
/// - aucun secret en ligne de commande, en log ou en retour ; arguments en stdin, script constant en -EncodedCommand.
/// Hors Windows ou sans PowerShell 5.1 vérifié, chaque demande est refusée avant tout envoi (Failed, rien d'écrit) :
/// aucun fait n'est simulé et aucune commande n'est inventée.
/// </summary>
public sealed partial class PowerShellMutationGateway : IMutationGateway, IMutationFallbackDisclosure, IMutationAvailability, IMutationReceiptFinalizer, IMutationReceiptReconciler, IMutationMoveContinuation
{
    private const int TimeoutSeconds = 180;
    private const long MaximumResponseBytes = 64 * 1024;
    private const string PostMutationMutexName = "Global\\GP_PostMutation_v1";
    private static readonly string PowerShellPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");

    private readonly string? v1InstallationPath;
    private readonly string? unavailableReason;
    private readonly ITaskFallbackCredentialSource? fallbackCredentials;
    private readonly ITaskSchedulerTransport? taskTransport;
    private readonly string? taskGpRoot;
    private readonly string? receiptGpRoot;
    private readonly object reconciliationGate = new();
    private ReceiptReconciliationObservation? pendingReconciliation;
    private DateTimeOffset reconciliationReadAt;

    /// <summary>État lu de POLICY.AllowPasswordTaskFallback (« true » / « false » / « unknown ») — jamais activé implicitement.
    /// Divulgué au moteur pour l'aperçu du plan (port du control summary V1, <see cref="IMutationFallbackDisclosure"/>).</summary>
    public string FallbackPolicyState { get; }

    /// <summary>Mode du compte de repli observé par l'adaptateur (session SSO par défaut : le repli y est refusé, comme en V1).
    /// Divulgué au moteur pour l'aperçu du plan (port du control summary V1, <see cref="IMutationFallbackDisclosure"/>).</summary>
    public TaskFallbackAccountMode FallbackAccountMode => fallbackCredentials?.Mode ?? TaskFallbackAccountMode.SessionSso;

    public string Description { get; }
    public bool IsAvailable => unavailableReason is null;
    public string? UnavailableReason => unavailableReason;

    /// <param name="v1InstallationPath">Installation V1 dont le cfg.json commande la politique de repli (lu, jamais écrit).</param>
    /// <param name="fallbackCredentials">Source du compte AD explicitement saisi pour le repli authentifié V1 ;
    /// <c>null</c> = mode session SSO : le repli est refusé avec la raison V1, jamais simulé. Jamais injectée par le pont.</param>
    /// <param name="taskTransport">Transport du Planificateur pour le repli ; <c>null</c> sous Windows = transport COM réel
    /// (mémoire seule, jamais d'arguments CLI) ; hors Windows, le repli reste refusé plutôt que simulé.</param>
    /// <param name="taskGpRoot">Dossier des preuves de tâche (défaut : %ProgramData%\GP sous Windows) ; l'impossibilité
    /// d'y écrire bloque le repli avant toute création de tâche.</param>
    public PowerShellMutationGateway(string? v1InstallationPath = null, ITaskFallbackCredentialSource? fallbackCredentials = null,
        ITaskSchedulerTransport? taskTransport = null, string? taskGpRoot = null, string? receiptGpRoot = null,
        IReceiptAuditSink? auditSink = null, IClockSkewReader? clockReader = null, IGroupExclusionReader? groupReader = null)
    {
        this.v1InstallationPath = V1ConfigDirectory.Resolve(v1InstallationPath);
        this.fallbackCredentials = fallbackCredentials;
        this.taskTransport = taskTransport;
        this.taskGpRoot = taskGpRoot;
        this.receiptGpRoot = receiptGpRoot;
        receiptAudit = new ReceiptAuditTrail(auditSink ?? new WindowsReceiptAuditSink());
        this.clockReader = clockReader ?? new WindowsClockSkewReader();
        groupExclusionReader = groupReader ?? new PowerShellDirectoryGateway(fallbackCredentials as IWindowsCredentialSource, this.v1InstallationPath);
        unavailableReason = Probe();
        FallbackPolicyState = TaskFallbackPolicy.ReadAllowPasswordTaskFallback(this.v1InstallationPath);
        var transportState = taskTransport is not null ? "injecté"
            : OperatingSystem.IsWindows() ? "COM Planificateur (mémoire seule)" : "aucun hors Windows — repli refusé, jamais simulé";
        Description = "Windows PowerShell 5.1 · adaptateur de mutations transitoire (gardes d’écriture portées de V1) · identité Windows ou compte AD explicite · non qualifié Windows/AD"
            + (unavailableReason is null ? "" : " · " + unavailableReason)
            + " · repli V1 par tâche sous compte AD : politique lue « " + FallbackPolicyState + " », compte « "
            + (FallbackAccountMode == TaskFallbackAccountMode.ExplicitAccount ? "explicite" : "session SSO") + " », transport « " + transportState + " »";
    }

    private static string? Probe() => WindowsPowerShellProbe.UnavailableReason;

    // ---- point d'entrée -------------------------------------------------------------------

    public MutationOutcome Execute(MutationRequest request)
    {
        // Tout ce qui est prouvable avant envoi refuse en Failed (rien d'écrit) : un refus qui n'a jamais quitté
        // le processus ne peut pas être « incertain ». Seuls les résultats réellement inconnus après envoi sont Uncertain.
        if (Inspect(request) is { } invalid) return invalid;
        if (unavailableReason is not null) return Refused(96, unavailableReason);

        var mutex = new Mutex(false, PostMutationMutexName);
        bool owned;
        try
        {
            try { owned = mutex.WaitOne(0); }
            catch (AbandonedMutexException) { owned = true; }
            if (!owned)
                return Refused(96, "Une autre instance traite déjà une mutation sur ce poste (mutex Global\\GP_PostMutation_v1) : aucun nouvel envoi.");
            try
            {
                FileStream configuration;
                try { configuration = PinConfirmedConfiguration(request); }
                catch (Exception) { return Refused(96, "La configuration du plan est absente, modifiée ou ne peut pas être protégée pendant l’action : aucune commande ni coordination engagée."); }
                using var pinnedConfiguration = configuration;
                FileStream? automationIntent;
                try { automationIntent = request.Automation is { } authority ? AutomationJournal.PinAuthority(ReceiptGpRoot(), authority) : null; }
                catch (Exception) { return Refused(96, "L'intention automatique n'est plus durable, unique ou protégée pendant l'action : aucune commande envoyée."); }
                using var pinnedAutomationIntent = automationIntent;
                if (ConfiguredPolicyRefusal(request) is { } policyRefusal) return Refused(96, policyRefusal);
                if (OfflineJoinStore.RefusalForMutation(ReceiptGpRoot(), request.Computer,
                    localTarget: string.Equals(request.Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase)) is { } offlineBarrier) return Refused(96, offlineBarrier);
                if (ReadV1Barriers() is { } v1Barrier) return Refused(96, v1Barrier);
                if (ReservationBarrier(request) is { } reservationBarrier) return Refused(96, reservationBarrier);
                try
                {
                    if (request.Continuation is { } proposed) ValidateMoveContinuation(request, proposed);
                    if (ReadV2Barrier(request, request.Continuation) is { } v2Barrier) return Refused(96, v2Barrier);
                    if (request.Continuation is { } authorization && !continuationGrants.Consume(authorization, DateTimeOffset.UtcNow))
                        return Refused(96, "L’autorisation du déplacement restant a expiré ou a déjà été consommée.");
                }
                catch (PestoException error) { return Refused(96, error.Message); }
                catch (Exception) { return Refused(96, "Les preuves du déplacement restant ne peuvent pas être confirmées : aucune commande lancée."); }
                return request.Kind == "attributes" ? SendAttributes(request) : PreserveEntraEffects(request, Send(request));
            }
            finally { if (owned) mutex.ReleaseMutex(); }
        }
        finally { mutex.Dispose(); }
    }

    // ---- validation préalable (aucune dépendance au système) --------------------------------

    private static MutationOutcome? Inspect(MutationRequest request)
    {
        try { AttributeMutationRules.RequireRequest(request); }
        catch (PestoException error) { return Refused(96, error.Message); }
        if (request.Kind is not ("join" or "rename" or "move" or "renameMove" or "attributes"))
            return Refused(11, "Type de mutation non déclaré : aucune commande lancée.");
        if (!IsComputerName(request.Computer))
            return Refused(11, "Nom de poste invalide (modèle historique, 15 caractères maximum) : aucune commande lancée.");
        if (!System.Text.RegularExpressions.Regex.IsMatch(request.Domain, @"^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$") || request.Domain.Length > 253)
            return Refused(11, "Domaine invalide : aucune commande lancée.");
        if (request.Dc is { Length: > 253 } || request.Dc is { } dc && dc.Any(char.IsControl))
            return Refused(11, "Contrôleur de domaine invalide : aucune commande lancée.");
        if (!IsOpaqueId(request.PlanId) || !IsOpaqueId(request.ReceiptId))
            return Refused(11, "Identifiants de plan ou de reçu invalides : aucune commande lancée.");
        var requiresName = request.Kind is "join" or "rename" or "renameMove";
        if (requiresName && !IsComputerName(request.NewName))
            return Refused(11, "Nouveau nom invalide ou absent : aucune commande lancée.");
        if (!requiresName && !string.IsNullOrEmpty(request.NewName))
            return Refused(11, "Un déplacement ne change pas le nom : aucune commande lancée.");
        var requiresOu = request.Kind is "join" or "move" or "renameMove";
        if (requiresOu && string.IsNullOrEmpty(request.TargetOu))
            return Refused(11, "OU de destination absente ou invalide : aucune commande lancée.");
        if (request.TargetOu is { } ou && (ou.Length > 2048 || ou.Any(char.IsControl)))
            return Refused(11, "OU de destination absente ou invalide : aucune commande lancée.");
        if (request.Kind is "move" or "renameMove" or "attributes" && (string.IsNullOrEmpty(request.ComputerGuid) || !Guid.TryParse(request.ComputerGuid, out var parsed) || parsed == Guid.Empty))
            return Refused(96, "Identité GUID réellement observée absente du plan : aucun déplacement sans GUID vérifié.");
        if (request.Kind is "rename" && request.ComputerGuid is { } guid && (string.IsNullOrEmpty(guid) || !Guid.TryParse(guid, out _)))
            return Refused(96, "Identité GUID du plan invalide : aucune commande lancée.");
        if (request.Kind == "join" && !string.Equals(request.Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase))
            return Refused(96, "La jonction ne concerne que le poste local : aucune commande ne sera lancée pour un autre poste.");
        if (request.Kind != "join" && (string.IsNullOrWhiteSpace(request.SourceOu) || request.SourceOu.Length > 2048 || request.SourceOu.Any(char.IsControl)))
            return Refused(96, "OU source observée absente ou invalide : aucune commande lancée.");
        if (requiresOu && (!Guid.TryParse(request.TargetOuGuid, out var targetGuid) || targetGuid == Guid.Empty))
            return Refused(96, "GUID de l’OU cible non confirmé : aucune commande lancée.");
        return null;
    }

    private static bool IsComputerName(string? name) =>
        !string.IsNullOrEmpty(name) && System.Text.RegularExpressions.Regex.IsMatch(name, @"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$");

    private static bool IsOpaqueId(string? id) =>
        !string.IsNullOrEmpty(id) && id.Length <= 128 && id.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-');

    // ---- barrières et politique lues avant tout envoi ----------------------------------------

    /// <summary>Port d'Assert-PestoStoredMutationReady + Get-PestoJoinReceiptDecision : les reçus de barrière GP de V1 sont
    /// relus avant action. Failed/Verified/NotStarted/None libèrent ; tout le reste (Running, PendingRestart, Uncertain…)
    /// bloque, acquitté compris côté V1 ; un reçu illisible bloque aussi — jamais on n'envoie par-dessus une barrière douteuse.</summary>
    private string? ReadBarrier(string path, string label)
    {
        if (!File.Exists(path)) return null;
        try
        {
            var info = new FileInfo(path);
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0) return label + " est un lien : les barrières V1 ne sont pas traversées, envoi refusé.";
            if (info.Length is > 65536 or 0) return label + " invalide : vérification manuelle nécessaire avant tout envoi.";
            var bytes = File.ReadAllBytes(path);
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return label + " illisible : vérification manuelle nécessaire avant tout envoi.";
            if (HasAppliedAcknowledgement(path, bytes)) return null;
            if (StoredMutationBarrier.IsAcknowledged(root)) return null;
            var phase = root.TryGetProperty("Phase", out var p) && p.ValueKind == JsonValueKind.String ? p.GetString() : null;
            if (string.IsNullOrEmpty(phase)) return label + " sans phase valide : vérification manuelle nécessaire avant tout envoi.";
            if (phase.Equals("Failed", StringComparison.OrdinalIgnoreCase) || phase.Equals("Verified", StringComparison.OrdinalIgnoreCase)
                || phase.Equals("NotStarted", StringComparison.OrdinalIgnoreCase) || phase.Equals("None", StringComparison.OrdinalIgnoreCase))
                return null;
            return phase.Equals("PendingRestart", StringComparison.OrdinalIgnoreCase)
                ? label + " « PendingRestart » : ajout accepté, redémarrez explicitement ; aucune nouvelle tentative automatique."
                : label + " « " + phase + " » : à vérifier avant toute reprise ; aucune nouvelle tentative automatique.";
        }
        catch (Exception error)
        {
            return label + " illisible : " + Short(error.Message) + " Vérification manuelle nécessaire avant tout envoi.";
        }
    }

    private string? ReadV2Barrier(MutationRequest request, MoveContinuationAuthorization? continuation = null)
    {
        var folder = Path.Combine(ReceiptGpRoot(), "V2", "receipts");
        if (!Directory.Exists(folder)) return null;
        try
        {
            RequireNoReparsePoint(folder);
            var paths = Directory.EnumerateFiles(folder, "*.json").Take(5001).ToArray();
            if (paths.Length > 5000) return "Historique des reçus V2 trop volumineux : vérification manuelle nécessaire avant tout envoi.";
            foreach (var path in paths)
            {
                RequireNoReparsePoint(path);
                if (new FileInfo(path).Length is 0 or > 65536) return "Reçu V2 illisible : aucun nouvel envoi avant vérification manuelle.";
                var receiptBytes = File.ReadAllBytes(path);
                if (!OfflineJoinReceipt.ValidateStored(ReceiptGpRoot(), receiptBytes))
                    return "La preuve durable spécialisée ODJ ne correspond plus à son reçu : aucun nouvel envoi. Ouvrez Pesto.exe --offline-join.";
                using var document = JsonDocument.Parse(receiptBytes);
                var receipt = document.RootElement;
                if (receipt.ValueKind != JsonValueKind.Object || !receipt.TryGetProperty("Computer", out var computer)
                    || computer.ValueKind != JsonValueKind.String || string.IsNullOrWhiteSpace(computer.GetString()))
                    return "Identité d’un reçu V2 illisible : aucun nouvel envoi avant vérification manuelle.";
                var previousName = receipt.TryGetProperty("NewName", out var name) && name.ValueKind == JsonValueKind.String ? name.GetString() : null;
                var previousGuid = receipt.TryGetProperty("ComputerGuid", out var guidNode) && guidNode.ValueKind == JsonValueKind.String ? guidNode.GetString() : null;
                if (IsReservationParentBarrier(request, receipt, path) || HasResolvedReservationParent(receipt, path)) continue;
                if (!string.Equals(computer.GetString(), request.Computer, StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(previousName, request.Computer, StringComparison.OrdinalIgnoreCase)
                    && !(request.ComputerGuid is not null && string.Equals(previousGuid, request.ComputerGuid, StringComparison.OrdinalIgnoreCase))) continue;
                if (HasAppliedAcknowledgement(path, receiptBytes)) continue;
                if (continuation is not null && Matches(receipt, "ReceiptId", continuation.ParentReceiptId)
                    && Path.GetFileName(path) == continuation.ParentReceiptId + ".json"
                    && Hash(ReadReceiptBytes(path)) == continuation.ParentReceiptSha256) continue;
                if (HasResolvedContinuation(receipt)) continue;
                if (MoveContinuationRules.IsPartialParent(receipt))
                    return "Renommage confirmé mais déplacement restant non résolu : préparez uniquement le déplacement lié au reçu original.";
                if (ReadBarrier(path, "Reçu V2 de ce poste") is { } blocked) return blocked;
            }
            return null;
        }
        catch (Exception)
        {
            return "Les reçus V2 ne peuvent pas être vérifiés : aucun nouvel envoi, aucune reprise automatique.";
        }
    }

    /// <summary>
    /// Port de la lecture V1 de CONF.ClearProtectionOnMove (Pesto-Core : « $script:CLEAR_PROTECTION = if ($null -ne
    /// $conf.ClearProtectionOnMove) { Convert-Value-TF ... } else { $true } ») : absent = true (valeur appliquée par le
    /// moteur V1), booléen JSON ou texte « true »/« false » admise (la clé est cherchée sans casse, comme V1 qui la
    /// normalise) ; toute autre valeur, un cfg.json absent, malformé ou illisible rend « unknown » : dans cet état un
    /// objet protégé n'est JAMAIS levé (le script refuse 96), jamais une levée implicite par défaut.
    /// </summary>
    public static string ReadClearProtectionOnMove(string? v1InstallationPath)
    {
        if (string.IsNullOrWhiteSpace(v1InstallationPath)) return "unknown";
        var path = Path.Combine(v1InstallationPath!, "cfg.json");
        if (!File.Exists(path)) return "unknown";
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
            if (document.RootElement.ValueKind != JsonValueKind.Object) return "unknown";
            if (!document.RootElement.TryGetProperty("CONF", out var confs) || confs.ValueKind != JsonValueKind.Array) return "unknown";
            var conf = default(JsonElement);
            var count = 0;
            foreach (var item in confs.EnumerateArray()) { conf = item; count++; }
            if (count != 1 || conf.ValueKind != JsonValueKind.Object) return "unknown";
            foreach (var property in conf.EnumerateObject())
            {
                if (!property.Name.Equals("ClearProtectionOnMove", StringComparison.OrdinalIgnoreCase)) continue;
                var value = property.Value;
                if (value.ValueKind == JsonValueKind.True) return "true";
                if (value.ValueKind == JsonValueKind.False) return "false";
                if (value.ValueKind == JsonValueKind.String)
                {
                    var text = value.GetString()!.Trim();
                    if (text.Equals("true", StringComparison.OrdinalIgnoreCase)) return "true";
                    if (text.Equals("false", StringComparison.OrdinalIgnoreCase)) return "false";
                }
                return "unknown";
            }
            return "true"; // absent = la valeur qu'applique le moteur V1
        }
        catch (Exception)
        {
            return "unknown";
        }
    }

    // ---- reçu durable avant envoi, complété après (port Write-PestoJoinReceipt) -----------------

    private MutationOutcome Send(MutationRequest request)
    {
        string payload;
        NativeReceiptSnapshot baseline;
        try
        {
            var module = ResolveAdModulePath();
            if (module is null) return Refused(96, "Module ActiveDirectory vérifié introuvable : aucune commande native lancée.");
            var credential = (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload();
            RequirePrecreatedAccount(request);
            var local = string.Equals(request.Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase);
            if (!local && request.Kind is ("rename" or "renameMove") && credential is null)
                return Refused(96, "Renommage distant non lancé : choisissez Autre compte AD à l’ouverture de Pesto pour confirmer l’identité Windows distante.");
            baseline = ReadMutationBaseline(request, module, credential, local);
            if (baseline.Error is not null || ((local || request.Kind is "rename" or "renameMove" || request.Continuation is not null)
                    && (baseline.BootUtc is null || !RemoteWindowsEvidenceProtocol.IsGuid(baseline.MachineId)))
                || (request.Kind != "join" && (baseline.AdGuid is null || baseline.AdProtected is null || baseline.AdOu is null)))
                return Refused(96, "L’état initial Windows/AD ne peut pas être conservé de façon fiable : aucune commande native lancée.");
            if (baseline.DomainController == true || (request.Kind != "join" && baseline.DomainController is null))
                return Refused(96, "Contrôleur de domaine ou rôle AD non confirmé : aucune mutation de poste autorisée.");
            if (request.Kind != "join" && (!string.Equals(baseline.AdGuid, request.ComputerGuid, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(baseline.AdName, request.Computer, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(baseline.AdOu, request.SourceOu, StringComparison.OrdinalIgnoreCase)))
                return Refused(96, "L’identité AD de la cible ne correspond plus au plan : aucune commande native lancée.");
            if (request.Kind is ("rename" or "renameMove") && (baseline.DomainRole is not (1 or 3) || baseline.PartOfDomain != true
                || !string.Equals(baseline.Domain, request.Domain, StringComparison.OrdinalIgnoreCase)
                || !string.Equals(baseline.ActiveName, request.Computer, StringComparison.OrdinalIgnoreCase)
                || (baseline.ConfiguredName is not null && !string.Equals(baseline.ConfiguredName, request.Computer, StringComparison.OrdinalIgnoreCase))))
                return Refused(96, "Identités Windows et AD incohérentes, cible sensible ou nom déjà en attente : aucun renommage lancé.");
            if (ContinuationBaselineRefusal(request, baseline) is { } changed) return Refused(96, changed);
            if (EntraRenameRefusal(request, baseline) is { } entraRefusal) return Refused(96, entraRefusal);
            payload = BuildPayload(request, ReadClearProtectionOnMove(v1InstallationPath), credential: credential,
                adModulePath: module, expectedProtection: request.Continuation is null ? null : baseline.AdProtected,
                excludedGroupGuids: ReadPolicyRequirements().ExcludedGroupGuids);
        }
        catch (PestoException error) { return Refused(96, error.Message); }
        catch (Exception) { return Refused(96, "Préparation du module ou du compte AD impossible : aucune commande native lancée."); }
        if (JoinClockRefusal(request) is { } clockRefusal) return clockRefusal;
        if (GroupExclusionRefusal(request) is { } groupRefusal) return groupRefusal;
        string receiptPath;
        try
        {
            receiptPath = WritePreSendReceipt(request, baseline);
            LinkContinuationBeforeSend(request, receiptPath);
            if (ConfiguredPolicyRefusal(request) is { } changedConfiguration) return Refused(96, changedConfiguration);
            AcquireCoordination(request, receiptPath);
            VerifyCoordinationBeforeSend(request);
            // Coordination may wait for SMB. Keep the final clock/group observations after that wait.
            if (GroupExclusionRefusal(request) is { } finalGroups) { AbortCoordinationBeforeSend(request); return finalGroups; }
            if (JoinClockRefusal(request) is { } finalClock) { AbortCoordinationBeforeSend(request); return finalClock; }
            // A lease must still be valid after all diagnostic waits, without choosing another name.
            VerifyNameReservationBeforeSend(request);
            if (ConfiguredPolicyRefusal(request) is { } finalPolicy) { AbortCoordinationBeforeSend(request); return Refused(96, finalPolicy); }
        }
        catch (Exception error)
        {
            // Port de Pesto-Join.ps1 : une impossibilité d'enregistrer le reçu bloque AVANT la commande native.
            try { AbortCoordinationBeforeSend(request); } catch (Exception) { /* Any unconfirmed shared lock is preserved. */ }
            return Refused(96, "La préparation durable ou la coordination préalable n’a pas pu être confirmée : aucune commande native lancée. " + Short(error.Message));
        }
        // A confirmed Entra leave is a real effect. No path below may promise that nothing happened.
        if (PrepareEntraBeforeRename(request, baseline, receiptPath) is { } entraOutcome) return entraOutcome;
        if (request.Kind is "rename" or "renameMove")
        {
            try
            {
                if (ConfiguredPolicyRefusal(request) is { } policyChanged) return PreserveEntraEffects(request, Refused(96, policyChanged));
                VerifyCoordinationBeforeSend(request);
                if (GroupExclusionRefusal(request) is { } groupsChanged) return PreserveEntraEffects(request, groupsChanged);
                VerifyNameReservationBeforeSend(request);
                if (ConfiguredPolicyRefusal(request) is { } finalPolicy) return PreserveEntraEffects(request, Refused(96, finalPolicy));
            }
            catch (Exception) { return PreserveEntraEffects(request, Refused(96, "Les gardes finales après le contrôle Entra ne sont plus confirmés ; aucun renommage envoyé.")); }
        }
        // This block may create an explicitly confirmed AD reservation. It must never be caught by the
        // earlier pre-send refusal path, whose guarantee is that no AD command was sent.
        var binding = BindJoinReservationBeforeSend(request, baseline, receiptPath);
        if (binding.Refusal is { } reservationRefusal) return WithClockWarning(request, reservationRefusal);
        request = binding.Request;
        if (request.Reservation is not null)
        {
            try
            {
                payload = BuildPayload(request, ReadClearProtectionOnMove(v1InstallationPath),
                    credential: (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload(),
                    adModulePath: ResolveAdModulePath(), excludedGroupGuids: ReadPolicyRequirements().ExcludedGroupGuids);
            }
            catch (Exception)
            {
                return CompleteReservationJoin(request, Uncertain(97,
                    "Le compte réservé reste conservé mais la préparation native de sa jonction n’a pas abouti. Inspectez la réservation ; aucune reprise automatique."));
            }
        }
        var outcome = CompleteReservationJoin(request, WithPrecreatedJoinOutcome(request, WithClockWarning(request, AfterDirectAttempt(request, RunOnce(payload)))));
        try
        {
            // Native acceptance is not the final engine observation. A crash during AD readback must never
            // resurrect a provisional success as Verified on the next launch.
            CompletePreSendReceipt(receiptPath, request, new MutationOutcome(MutationStatus.Uncertain, 97,
                "Réponse native reçue ; vérification finale du moteur non encore enregistrée. Vérifier avant toute reprise, jamais rejoué automatiquement.", outcome.RestartRequired));
        }
        catch (Exception error)
        {
            // Port de Pesto-Join.ps1 : « résultat Windows connu mais reçu final non enregistré » → incertain, à vérifier.
            return new MutationOutcome(MutationStatus.Uncertain, 97,
                Short("Résultat observé (« " + outcome.Status + " ») mais reçu final non enregistré : " + Short(error.Message)
                    + " Vérifier avant toute reprise, jamais rejoué automatiquement."), outcome.RestartRequired);
        }
        return outcome;
    }

    /// <summary>
    /// Port du garde V1 de <c>RenameComputer</c> (Pesto-Operations.ps1 1257-1267) : après un refus CONFIRMÉ du
    /// renommage direct (codes natifs 5/1314/1326 rendus par le script constant), la décision du repli authentifié
    /// est prise par <see cref="TaskFallback.Decide"/> — jamais ici à la légère : distant seulement, compte explicite
    /// seulement, politique lue vraie seulement, 5/1314 seulement, jamais après un incertain. Le compte n'est acquis
    /// qu'au moment du repli et purgé en finally (durée de conservation bornée à l'opération, port du nettoyage V1) ;
    /// le mot de passe ne transite qu'en mémoire du transport COM, jamais en arguments CLI, log, reçu, XML ou pont.
    /// Un repli de renommage accepté pour « renameMove » enchaîne sur le déplacement seul (op « moveAfterRename »,
    /// même pipeline attente de visibilité + mapping 77/89/97/32 que <c>GoRenameAndMove</c> V1).
    /// </summary>
    private MutationOutcome AfterDirectAttempt(MutationRequest request, MutationOutcome outcome)
    {
        if (request.Kind is not ("rename" or "renameMove")) return outcome;
        if (outcome.Status != MutationStatus.Failed || !TaskFallback.IsDefiniteRefusalCode(outcome.Code)) return outcome;
        if (request.Automation is not null)
            return outcome with { Message = Short(outcome.Message + " CLI : aucun repli avec mot de passe sans confirmation opérateur séparée ; résultat conservé, aucun nouvel envoi.") };
        var decision = TaskFallback.Decide(new TaskFallbackGate(
            request.Kind,
            !string.Equals(request.Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase),
            FallbackAccountMode, FallbackPolicyState, outcome.Code, WasUncertain: false));
        if (!decision.Allowed)
            return new MutationOutcome(outcome.Status, outcome.Code, Short(outcome.Message + " " + decision.Reason), outcome.RestartRequired);
        PestoAdCredential? credential = null;
        try
        {
            credential = fallbackCredentials?.AcquireForFallback(request.Computer, request.NewName, request.PlanId);
            if (credential is null)
                return new MutationOutcome(MutationStatus.Failed, 21,
                    Short(outcome.Message + " Repli refusé : aucun compte AD explicitement fourni pour cette opération — le repli n'est jamais implicite (port V1)."), false);
            // The explicit fallback dialogue may stay open. No membership observation from before it authorizes a task.
            if (ConfiguredPolicyRefusal(request) is { } policyRefusal) return Refused(96, policyRefusal);
            try { VerifyCoordinationBeforeSend(request); }
            catch (Exception) { return Uncertain(97, "La coordination n’est plus confirmée après le refus direct : aucun repli créé, preuves conservées pour vérification."); }
            if (GroupExclusionRefusal(request) is { } groupRefusal) return groupRefusal;
            try { VerifyNameReservationBeforeSend(request); }
            catch (Exception) { return Uncertain(97, "Le bail du nom n’est plus confirmé après le refus direct : aucun repli créé ni nom de remplacement choisi, preuves conservées."); }
            var gpRoot = string.IsNullOrEmpty(taskGpRoot) ? DefaultGpRoot() : taskGpRoot;
            if (string.IsNullOrEmpty(gpRoot))
                return new MutationOutcome(MutationStatus.Failed, 96,
                    Short(outcome.Message + " Repli refusé : aucun dossier de preuves de tâche disponible — les preuves durables V1 sont obligatoires avant toute tâche."), false);
            var transport = taskTransport ?? (OperatingSystem.IsWindows() ? new TaskSchedulerComTransport() : null);
            if (transport is null)
                return new MutationOutcome(MutationStatus.Failed, 96,
                    Short(outcome.Message + " Repli refusé : aucun transport Planificateur sur ce système — refusé plutôt que simulé."), false);
            try
            {
                var fallback = new PestoTaskFallbackRunner(transport, gpRoot!)
                    .RunRename(request.Computer, request.NewName!, credential, request.Domain, request.PlanId, request.ReceiptId);
                if (request.Kind == "renameMove" && fallback.Status == MutationStatus.PendingRestart
                    && !string.Equals(request.SourceOu, request.TargetOu, StringComparison.OrdinalIgnoreCase))
                    return RunOnce(BuildPayload(request, ReadClearProtectionOnMove(v1InstallationPath), "moveAfterRename",
                        (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload(), ResolveAdModulePath(),
                        excludedGroupGuids: ReadPolicyRequirements().ExcludedGroupGuids));
                return fallback;
            }
            finally { if (taskTransport is null && transport is IDisposable owned) owned.Dispose(); }
        }
        finally { credential?.Dispose(); }
    }

    private string? ResolveAdModulePath() => TrustedActiveDirectoryModule.Resolve(v1InstallationPath);

    private static string? DefaultGpRoot()
    {
        if (!OperatingSystem.IsWindows()) return null;
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        return string.IsNullOrEmpty(programData) ? null : Path.Combine(programData, "GP");
    }

    private string ReceiptGpRoot() => receiptGpRoot ?? DefaultGpRoot()
        ?? throw new IOException("Dossier des reçus Windows indisponible.");

    /// <summary>Persist the engine's final readback, never just the native command result. A failed write leaves
    /// Running/Uncertain on disk; the engine reports uncertainty and no automatic replay is allowed.</summary>
    public void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome)
    {
        outcome = PreserveEntraEffects(request, outcome);
        if (!IsOpaqueId(request.ReceiptId) || !IsOpaqueId(request.PlanId)) throw new IOException("Identité de reçu invalide.");
        if (receiptGpRoot is null && !OperatingSystem.IsWindows() && outcome.Status == MutationStatus.Failed) return;
        var path = Path.Combine(ReceiptGpRoot(), "V2", "receipts", request.ReceiptId + ".json");
        RequireNoReparsePoint(path);
        if (!File.Exists(path))
        {
            // Inspect, prerequisite, mutex and barrier refusals occur before any native receipt or command.
            if (outcome.Status == MutationStatus.Failed) return;
            throw new IOException("Reçu préalable absent : résultat final non enregistré.");
        }
        using var mutex = new Mutex(false, PostMutationMutexName);
        var owned = false;
        try
        {
            try { owned = mutex.WaitOne(0); }
            catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw new IOException("Une autre mutation utilise le registre : résultat final non enregistré.");
            if (new FileInfo(path).Length is 0 or > 65536) throw new IOException("Reçu préalable illisible.");
            using var document = JsonDocument.Parse(File.ReadAllText(path, Encoding.UTF8));
            var stored = document.RootElement;
            if (stored.ValueKind != JsonValueKind.Object
                || !Matches(stored, "ReceiptId", request.ReceiptId) || !Matches(stored, "PlanId", request.PlanId)
                || !Matches(stored, "Kind", request.Kind) || !Matches(stored, "Computer", request.Computer)
                || !Matches(stored, "NewName", request.NewName) || !Matches(stored, "TargetOu", request.TargetOu))
                throw new IOException("Le reçu préalable ne correspond plus à l’opération : aucun remplacement.");
            CompletePreSendReceipt(path, request, outcome);
            FinalizeCoordination(request, outcome);
        }
        finally { if (owned) mutex.ReleaseMutex(); }
    }

    private static bool Matches(JsonElement stored, string key, string? expected) =>
        stored.TryGetProperty(key, out var value) && (expected is null
            ? value.ValueKind == JsonValueKind.Null
            : value.ValueKind == JsonValueKind.String && string.Equals(value.GetString(), expected, StringComparison.Ordinal));

    private string WritePreSendReceipt(MutationRequest request, NativeReceiptSnapshot baseline)
    {
        var folder = Path.Combine(ReceiptGpRoot(), "V2", "receipts");
        RequireNoReparsePoint(folder);
        Directory.CreateDirectory(folder);
        if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(folder);
        var path = Path.Combine(folder, request.ReceiptId + ".json");
        RequireNoReparsePoint(path);
        if (File.Exists(path)) throw new IOException("Ce reçu existe déjà : aucun nouvel envoi sous la même identité.");
        var json = ReceiptJson(request, "Running", 0, "Demande préparée, reçu écrit avant la commande native, résultat non encore reçu.", false, baseline);
        WriteAtomic(path, json);
        AuditDurableReceipt(json);
        return path;
    }

    private void CompletePreSendReceipt(string path, MutationRequest request, MutationOutcome outcome)
    {
        var phase = outcome.Status switch
        {
            MutationStatus.Succeeded when outcome.RestartRequired => "PendingRestart",
            MutationStatus.Succeeded => "Verified",
            MutationStatus.PendingRestart => "PendingRestart",
            MutationStatus.Failed => "Failed",
            _ => "Uncertain",
        };
        RequireNoReparsePoint(path);
        var stored = JsonNode.Parse(File.ReadAllText(path, Encoding.UTF8))?.AsObject() ?? throw new IOException("Reçu préalable illisible.");
        if (outcome.ObservedGuid is { } observed)
        {
            if (!Guid.TryParse(observed, out var guid) || guid == Guid.Empty) throw new IOException("GUID observé invalide.");
            var bound = stored["ComputerGuid"]?.GetValue<string>();
            if (bound is not null && !string.Equals(bound, observed, StringComparison.OrdinalIgnoreCase))
                throw new IOException("L’identité AD observée a changé : reçu conservé sans remplacement.");
            stored["ComputerGuid"] = observed;
        }
        stored["Phase"] = phase;
        stored["Utc"] = DateTimeOffset.UtcNow.ToString("o");
        stored["Code"] = outcome.Code;
        stored["Message"] = Short(outcome.Message);
        stored["RestartRequired"] = outcome.RestartRequired;
        ApplyEntraReceipt(stored, request);
        ApplyAttributeReceipt(stored, request, outcome);
        WriteCompletedReceipt(path, stored);
    }

    private string ReceiptJson(MutationRequest request, string phase, int code, string message, bool restartRequired, NativeReceiptSnapshot baseline)
    {
        return JsonSerializer.Serialize(new Dictionary<string, object?>
        {
            ["Schema"] = 1, ["Version"] = "2.0", ["Phase"] = phase,
            ["Utc"] = DateTimeOffset.UtcNow.ToString("o"), ["CreatedUtc"] = DateTimeOffset.UtcNow.ToString("o"),
            ["Adapter"] = Short(Description), ["ReceiptId"] = request.ReceiptId, ["PlanId"] = request.PlanId,
            ["Kind"] = request.Kind, ["Computer"] = request.Computer, ["NewName"] = request.NewName,
            ["TargetOu"] = request.TargetOu, ["Code"] = code, ["Message"] = Short(message), ["RestartRequired"] = restartRequired,
            ["ComputerGuid"] = request.ComputerGuid, ["Domain"] = request.Domain, ["Dc"] = request.Dc,
            ["InitialBootUtc"] = baseline.BootUtc?.ToString("o"), ["MachineId"] = baseline.MachineId,
            ["InitialWindowsDomain"] = baseline.Domain, ["InitialPartOfDomain"] = baseline.PartOfDomain, ["InitialDomainRole"] = baseline.DomainRole,
            ["LocalTarget"] = string.Equals(request.Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase),
            ["InitialProtected"] = baseline.AdProtected, ["InitialOu"] = baseline.AdOu, ["TargetOuGuid"] = request.TargetOuGuid,
            ["ParentReceiptId"] = request.Continuation?.ParentReceiptId,
            ["ParentReceiptSha256"] = request.Continuation?.ParentReceiptSha256,
            ["ContinuationAttemptId"] = request.Continuation is { } continuation ? Hash(continuation.Token) : null,
            ["Clock"] = request.Kind == "join" ? LastJoinClockCheck : null,
            ["AuditEventLogEnabled"] = ReadPolicyRequirements().AuditEventLogEnabled,
            ["ConfigurationSha256"] = request.ConfigurationSha256,
            ["ReservationId"] = request.Reservation?.ReservationId,
            ["ReservationAction"] = request.Reservation?.Action,
            ["Coordination"] = CoordinationReceipt(request),
            ["WindowsBaselineProof"] = baseline.RemoteProof,
            ["Entra"] = InitialEntraEffect(request),
            ["EntraEvidenceId"] = request.Entra?.LeaveRequired == true ? request.ReceiptId : null,
            ["JoinAccountMode"] = request.Kind == "join" ? request.PrecreatedJoin is null ? "new" : "precreated" : null,
            ["Attributes"] = request.Attributes is null ? null : "Requested",
            ["AttributeChanges"] = request.Attributes?.Changes,
            ["AttributeObservation"] = null,
        });
    }

    public ReceiptReconciliationObservation ReadReconciliation(string receiptId)
    {
        MutationSessionGuard.RequireWritableSession();
        var path = ReceiptPath(receiptId);
        var bytes = ReadReceiptBytes(path);
        using var document = JsonDocument.Parse(bytes);
        var saved = document.RootElement;
        if (saved.ValueKind != JsonValueKind.Object || !Matches(saved, "ReceiptId", receiptId))
            throw new PestoException("receipt.invalid", "Le reçu durable ne correspond pas à son identifiant.");
        if (SavedText(saved, "Kind") == "offlineJoin")
            throw new PestoException("offlineJoin.observe", "Ce reçu hors connexion se vérifie depuis Pesto.exe --offline-join ; aucune réussite déduite par la réconciliation générale.");
        if (SavedText(saved, "Kind") == "attributes")
            throw new PestoException("attributes.observe", "Ce reçu d'attributs doit être observé depuis le parcours Attributs ; aucune preuve de démarrage n'est nécessaire ni fabriquée.");
        if (SavedText(saved, "Entra") is "Requested" or "Uncertain" or "Confirmed"
            && !ReadEntraBarrier(receiptId).CanAcknowledge) _ = InspectEntraBarrier(receiptId);
        if (EntraEvidenceAllowsReconciliation(saved) is { } entraRefusal)
            throw new PestoException("receipt.entra", entraRefusal);
        var kind = SavedText(saved, "Kind") ?? "";
        var computer = SavedText(saved, "Computer") ?? "";
        var name = SavedText(saved, "NewName") ?? "";
        var targetOu = SavedText(saved, "TargetOu") ?? "";
        var phase = SavedText(saved, "Phase") ?? "";
        if (kind is not ("join" or "rename" or "move" or "renameMove") || !IsComputerName(computer)
            || (name.Length > 0 && !IsComputerName(name)) || phase is not ("Running" or "Uncertain" or "PendingRestart" or "Verified" or "Failed" or "Partial")
            || !saved.TryGetProperty("Code", out var code) || !code.TryGetInt32(out var nativeCode)
            || SavedDate(saved, "Utc") is not { } timestamp)
            throw new PestoException("receipt.invalid", "Le reçu durable ne peut pas être vérifié.");
        var status = phase switch { "Verified" => "succeeded", "Failed" => "refused", "PendingRestart" => "pendingRestart", _ => "uncertain" };
        var receipt = new Receipt(receiptId, timestamp, kind, computer, name, targetOu, "V2 · registre local GP", status,
            nativeCode, SavedText(saved, "Message") ?? "", SavedFlag(saved, "RestartRequired") == true,
            SavedText(saved, "ParentReceiptId"), HasResolvedContinuation(saved) ? SavedText(saved, "ResolutionChildReceiptId") : null);
        var domain = SavedText(saved, "Domain") ?? "";
        var expectedGuid = SavedText(saved, "ComputerGuid");
        var local = SavedFlag(saved, "LocalTarget") == true;
        NativeReceiptSnapshot snapshot;
        var module = ResolveAdModulePath();
        if (module is null || domain.Length == 0 || !Guid.TryParse(expectedGuid, out var id) || id == Guid.Empty)
            snapshot = new(null, null, null, null, null, null, null, null, null, null, null,
                "Le reçu ne contient pas d’identité AD liée ou le module de lecture est indisponible ; aucune réussite déduite.");
        else if (!local && kind != "move")
        {
            snapshot = !ReceiptWindowsEvidence.RemoteBaselineMatches(saved)
                ? UnknownWindows("Ancien reçu sans baseline Windows distante complète : aucune preuve de redémarrage ni réussite inventée.")
                : ReadBoundWindowsEvidence(domain, SavedText(saved, "Dc"), expectedGuid, name, name, name, receiptId,
                    "reconciliation", SavedText(saved, "MachineId"), Convert.ToHexString(SHA256.HashData(bytes)));
        }
        else snapshot = PowerShellReceiptEvidence.Read(domain, SavedText(saved, "Dc"), expectedGuid, local, module,
            (fallbackCredentials as IWindowsCredentialSource)?.CreateProtectedPayload());
        var machineId = SavedText(saved, "MachineId");
        var observation = new ReceiptReconciliationObservation(receipt, Convert.ToHexString(SHA256.HashData(bytes)), expectedGuid, domain,
            SavedDate(saved, "InitialBootUtc"), snapshot.BootUtc, snapshot.AdGuid, snapshot.AdName, snapshot.AdOu,
            SavedText(saved, "InitialOu"), SavedFlag(saved, "InitialProtected"), snapshot.AdProtected,
            snapshot.ActiveName, snapshot.ConfiguredName, snapshot.Domain, snapshot.PartOfDomain, snapshot.SecureChannel, local,
            !string.IsNullOrEmpty(machineId) && string.Equals(machineId, snapshot.MachineId, StringComparison.OrdinalIgnoreCase), snapshot.Error, snapshot.RemoteProof);
        lock (reconciliationGate) { pendingReconciliation = observation; reconciliationReadAt = DateTimeOffset.UtcNow; }
        return observation;
    }

    public void PersistReconciliation(ReceiptReconciliationObservation observation)
    {
        MutationSessionGuard.RequireWritableSession();
        if (observation.Receipt.Kind == "renameMove" && observation.Receipt.Code == 89)
            throw new PestoException("receipt.partial", "Le reçu partiel conserve son résultat : seule la résolution liée au déplacement enfant est autorisée.");
        lock (reconciliationGate)
        {
            if (!ReferenceEquals(pendingReconciliation, observation) || DateTimeOffset.UtcNow - reconciliationReadAt > TimeSpan.FromMinutes(2)
                || observation.Error is not null)
                throw new PestoException("receipt.stale", "La preuve de vérification est absente ou périmée ; aucune barrière levée.");
            pendingReconciliation = null;
        }
        var path = ReceiptPath(observation.Receipt.Id);
        using var mutex = new Mutex(false, PostMutationMutexName);
        var owned = false;
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw new PestoException("receipt.busy", "Une mutation utilise le registre ; aucune barrière levée.");
            var bytes = ReadReceiptBytes(path);
            if (!Convert.ToHexString(SHA256.HashData(bytes)).Equals(observation.ReceiptSha256, StringComparison.Ordinal))
                throw new PestoException("receipt.stale", "Le reçu a changé depuis sa lecture ; aucune barrière levée.");
            var stored = JsonNode.Parse(bytes)?.AsObject() ?? throw new IOException("Reçu illisible.");
            using (var pinned = JsonDocument.Parse(bytes))
                if (EntraEvidenceAllowsReconciliation(pinned.RootElement) is { } entraRefusal)
                    throw new PestoException("receipt.entra", entraRefusal);
            stored["Phase"] = "Verified";
            stored["Utc"] = DateTimeOffset.UtcNow.ToString("o");
            stored["RestartRequired"] = false;
            stored["Message"] = "Vérification explicite confirmée par lectures Windows et AD ; aucune opération rejouée.";
            stored["Reconciliation"] = ReconciliationJson(observation);
            MutationSessionGuard.RequireWritableSession();
            WriteCompletedReceipt(path, stored);
            ReleaseCompletedCoordination(observation.Receipt.Id);
        }
        finally { if (owned) mutex.ReleaseMutex(); }
    }

    private string ReceiptPath(string receiptId)
    {
        if (!IsOpaqueId(receiptId)) throw new PestoException("receipt.invalid", "Identifiant de reçu invalide.");
        return Path.Combine(ReceiptGpRoot(), "V2", "receipts", receiptId + ".json");
    }
    private static byte[] ReadReceiptBytes(string path)
    {
        RequireNoReparsePoint(path);
        if (!File.Exists(path) || new FileInfo(path).Length is 0 or > 65536) throw new PestoException("receipt.unavailable", "Reçu durable absent ou illisible.");
        return File.ReadAllBytes(path);
    }
    private static string? SavedText(JsonElement value, string key) => value.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    private static bool? SavedFlag(JsonElement value, string key) => value.TryGetProperty(key, out var v) && v.ValueKind is JsonValueKind.True or JsonValueKind.False ? v.GetBoolean() : null;
    private static DateTimeOffset? SavedDate(JsonElement value, string key) => DateTimeOffset.TryParse(SavedText(value, key), System.Globalization.CultureInfo.InvariantCulture,
        System.Globalization.DateTimeStyles.None, out var d) ? d : null;

    private static void WriteAtomic(string path, string json)
    {
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var file = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                using var writer = new StreamWriter(file, new UTF8Encoding(false), leaveOpen: true);
                writer.Write(json);
                writer.Flush();
                file.Flush(flushToDisk: true);
            }
            File.Move(temp, path, overwrite: true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    /// <summary>Port de Write-PestoJoinReceipt : aucun lien ni jonction suivi dans le chemin de stockage des états machine.</summary>
    private static void RequireNoReparsePoint(string path)
    {
        for (string? ancestor = Path.GetFullPath(path); ancestor is not null;)
        {
            if ((Directory.Exists(ancestor) || File.Exists(ancestor)) && (File.GetAttributes(ancestor) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Le stockage des reçus ne peut pas traverser un lien ou une jonction.");
            var next = Path.GetDirectoryName(ancestor);
            if (next == ancestor) break;
            ancestor = next;
        }
    }

    /// <summary>Port de l'ACL V1 : seuls SYSTEM et les administrateurs (S-1-5-18, S-1-5-32-544) peuvent modifier le stockage.</summary>
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static void RestrictToSystemAndAdmins(string folder)
    {
        var directory = new DirectoryInfo(folder);
        var acl = new DirectorySecurity();
        acl.SetAccessRuleProtection(true, false);
        foreach (var sid in new[] { new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
            acl.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
        directory.SetAccessControl(acl);
    }

    // ---- transport borné (script constant, arguments en stdin, jamais de secret) -----------------

    /// <summary>Seules les valeurs déjà validées quittent le processus vers le script constant, en stdin : jamais de
    /// mot de passe en clair, jamais de commande ; l'enveloppe DPAPI reste interne au transport natif. La décision de levée de protection est celle lue du cfg.json par
    /// <see cref="ReadClearProtectionOnMove"/> — une valeur non lue reste « unknown » (le script bloque alors sur objet
    /// protégé), jamais un « true » de complaisance. <paramref name="operationOverride"/> n'est utilisé qu'en interne
    /// pour enchaîner le déplacement seul (« moveAfterRename ») après un repli de renommage accepté ; les tests le
    /// contrôlent. Exposée pour les tests de qualification (assertions statiques).</summary>
    public static string BuildPayload(MutationRequest request, string clearProtectionOnMove, string? operationOverride = null,
        ProtectedWindowsCredential? credential = null, string? adModulePath = null, bool? expectedProtection = null,
        IReadOnlyList<string>? excludedGroupGuids = null) => JsonSerializer.Serialize(new Dictionary<string, object?>
    {
        ["Op"] = operationOverride ?? request.Kind,
        ["Credential"] = credential,
        ["AdModulePath"] = adModulePath,
        ["Domain"] = request.Domain,
        ["Server"] = string.IsNullOrWhiteSpace(request.Dc) ? request.Domain : request.Dc!.Trim(),
        ["Computer"] = request.Computer,
        ["ComputerGuid"] = request.ComputerGuid,
        ["NewName"] = request.NewName,
        ["TargetOu"] = request.TargetOu,
        ["SourceOu"] = request.SourceOu,
        ["TargetOuGuid"] = request.TargetOuGuid,
        ["ExpectedProtection"] = expectedProtection,
        ["ExcludedGroupGuids"] = GroupExclusionGuard.Normalize(excludedGroupGuids ?? []),
        ["Reservation"] = ReservationPayload(request),
        ["PrecreatedJoin"] = PrecreatedJoinPayload(request),
        ["ClearProtectionOnMove"] = clearProtectionOnMove == "true" ? "true" : clearProtectionOnMove == "false" ? "false" : "unknown",
    });

    /// <summary>Script constant, exposé uniquement pour les tests de qualification (assertions sur les gardes portées
    /// de V1). Seul <see cref="RunOnce"/> l'envoie après validation et écriture du reçu durable.</summary>
    public static string ConstantScript => Script;
    public static string WorkerBootstrap => PowerShellFixedWorker.Bootstrap(Script);

    private static MutationOutcome RunOnce(string requestJson)
    {
        var start = PowerShellFixedWorker.StartInfo(Script);
        Process process;
        try
        {
            process = Process.Start(start) ?? throw new InvalidOperationException("Le moteur Windows PowerShell n’a pas pu être lancé.");
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            // Prouvé : le processus n'a jamais démarré, aucune commande native n'a pu partir.
            return Refused(96, "Le moteur Windows PowerShell n’a pas pu être lancé : " + Short(error.Message) + " Aucune commande native exécutée.");
        }
        using (process)
        {
            OwnedMutationJob job;
            try { job = OwnedMutationJob.Attach(process); }
            catch (Exception)
            {
                // The worker waits for stdin. Attachment failed before any request bytes were supplied.
                return Refused(96, "Le moteur natif ne peut pas être lié à la durée de vie de Pesto : aucune demande ni commande AD envoyée.");
            }
            using var ownedWorker = job;
            var stdoutTask = process.StandardOutput.ReadToEndAsync();
            var stderrTask = process.StandardError.ReadToEndAsync();
            PowerShellFixedWorker.Send(process, Script, requestJson);
            if (!process.WaitForExit(TimeoutSeconds * 1000))
            {
                try { process.Kill(entireProcessTree: true); } catch (Exception) { /* le processus vient de finir */ }
                return Uncertain(97, "Mutation interrompue après " + TimeoutSeconds + " s : la commande a pu être acceptée. À vérifier avant toute reprise, jamais rejouée automatiquement.");
            }
            var stdout = stdoutTask.GetAwaiter().GetResult();
            stderrTask.GetAwaiter().GetResult();
            if (Encoding.UTF8.GetByteCount(stdout) > MaximumResponseBytes)
                return Uncertain(97, "Réponse de l’adaptateur trop volumineuse : résultat non publié, à vérifier avant toute reprise, jamais rejouée automatiquement.");
            return MapOutcome(stdout);
        }
    }

    private static MutationOutcome MapOutcome(string stdout)
    {
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(stdout) ? "{}" : stdout);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !(root.TryGetProperty("ok", out var ok) && ok.ValueKind == JsonValueKind.True)
                || !root.TryGetProperty("status", out var statusNode) || statusNode.ValueKind != JsonValueKind.String)
                return Uncertain(97, "Réponse de l’adaptateur illisible : la commande a pu partir. À vérifier avant toute reprise, jamais rejouée automatiquement.");
            var status = statusNode.GetString() switch
            {
                "succeeded" => MutationStatus.Succeeded,
                "pendingRestart" => MutationStatus.PendingRestart,
                "refused" => MutationStatus.Failed,
                _ => MutationStatus.Uncertain,
            };
            var code = root.TryGetProperty("code", out var c) && c.ValueKind == JsonValueKind.Number && c.TryGetInt32(out var parsed)
                ? parsed
                : status == MutationStatus.Succeeded ? 0 : 97;
            var message = root.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String ? Short(m.GetString()) : "Aucun détail renvoyé par l’adaptateur.";
            var restart = status == MutationStatus.PendingRestart
                || root.TryGetProperty("restartRequired", out var r) && r.ValueKind == JsonValueKind.True;
            return new MutationOutcome(status, code, message, restart);
        }
        catch (JsonException)
        {
            return Uncertain(97, "Réponse de l’adaptateur illisible : la commande a pu partir. À vérifier avant toute reprise, jamais rejouée automatiquement.");
        }
    }

    private static MutationOutcome Refused(int code, string message) => new(MutationStatus.Failed, code, Short(message), false);

    private static MutationOutcome Uncertain(int code, string message) => new(MutationStatus.Uncertain, code, Short(message), false);

    /// <summary>Messages bornés à 300 caractères, sans caractère de contrôle : aucun secret ni bloc arbitraire ne transite.</summary>
    private static string Short(string? text)
    {
        var trimmed = new string((text ?? "").Where(c => !char.IsControl(c)).ToArray()).Trim();
        if (trimmed.Length == 0) return "Aucun détail fourni.";
        return trimmed.Length > 300 ? trimmed[..300] : trimmed;
    }

    // ---- script constant, mutations nommées uniquement -------------------------------------------

    private static readonly string Script = GroupExclusionScript.Source + ReservationJoinGuardScript + PrecreatedJoinScript.Source + "\n" + """
$ErrorActionPreference='Stop'
function Get-NativeCode($e){
  $x=if($e -is [Exception]){$e}else{$e.Exception}
  for($i=0;$x -and $i -lt 8;$i++){
    if($x.PSObject.Properties['NativeErrorCode'] -and $x.NativeErrorCode -is [int]){return [long]$x.NativeErrorCode}
    $hr=[long]$x.HResult -band 4294967295
    if(($hr -band 4294901760) -eq 2147942400){return ($hr -band 65535)}
    $x=$x.InnerException
  }
  return $null
}
function Out-PestoResult($status,$code,$message,$restart){
  $m=([string]$message -replace '[\x00-\x1f]',' ')
  if($m.Length -gt 300){$m=$m.Substring(0,300)}
  @{ ok=$true; status=[string]$status; code=[int]$code; message=$m; restartRequired=[bool]$restart }|ConvertTo-Json -Depth 4 -Compress
}
function Get-ParentDn([string]$dn){
  for($i=0;$i -lt $dn.Length;$i++){
    $c=$dn[$i]
    if($c -eq '\'){$i++;continue}
    if($c -eq ','){ return $dn.Substring($i+1) }
  }
  throw 'Objet sans parent dans le DN.'
}
function Get-LocalStatus{
  $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
  $active=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  $configured=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  [pscustomobject]@{
    Name=[string]$env:COMPUTERNAME
    ActiveName=$active
    ConfiguredName=$configured
    DomainRole=[int]$cs.DomainRole
    PartOfDomain=[bool]$cs.PartOfDomain
    PendingRename=($active -ine $configured)
  }
}
function Test-IsLocalAdmin{
  $id=[Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Test-ConfirmedChange($change){
  $items=@($change)
  return ($items.Count -eq 1 -and $null -ne $items[0] -and $null -ne $items[0].PSObject.Properties['HasSucceeded'] -and $items[0].HasSucceeded -is [bool] -and $items[0].HasSucceeded)
}
function Test-DefiniteRefusal($code){ return ($null -ne $code) -and (@(5,1314,1326,1327,1355,2732) -contains [int]$code) }
function Assert-PestoDestination($targetOu,$expectedGuid,$adp){
  $id=[Guid]::Empty
  if(-not [Guid]::TryParse([string]$expectedGuid,[ref]$id) -or $id -eq [Guid]::Empty){throw 'GUID de l''OU cible absent : aucune commande lancée.'}
  $destination=Get-ADOrganizationalUnit -Identity $targetOu -Properties ObjectGUID -ErrorAction Stop @adp
  if(-not $destination -or [Guid]$destination.ObjectGUID -ne $id){throw 'L''identité de l''OU cible a changé depuis la confirmation : aucune commande lancée.'}
}
function Invoke-PestoRename($computer,$newName){
  try{
    $source=Get-ADComputer -Identity ([Guid]$guid) -Properties Name,DistinguishedName,ObjectGUID -ErrorAction Stop @adp
    if(-not $source -or [string]$source.Name -ine $computer -or (Get-ParentDn ([string]$source.DistinguishedName)) -ine $sourceOu){throw 'Identité ou OU source modifiée.'}
  }catch{return @{status='refused';code=96;message='L''identité ou l''OU source ne correspond plus au plan : aucun renommage lancé.';restart=$false}}
  try{Assert-PestoGroupExclusions $guid @($j.ExcludedGroupGuids) $adp $computer $sourceOu}
  catch{return @{status='refused';code=96;message='POLICY.ExcludedGroupGuids : appartenance exclue ou non confirmée juste avant le renommage ; aucune commande lancée.';restart=$false}}
  $renameAuth=@{}
  if($null -ne $adp.Credential){$renameAuth.DomainCredential=$adp.Credential}

  if($computer -ieq $env:COMPUTERNAME){
    $st=Get-LocalStatus
    if($st.ActiveName -ine $computer){ return @{status='refused';code=96;message='Le nom actif local ne correspond plus au plan : aucune commande lancée.';restart=$false} }
    if($st.PendingRename){ return @{status='refused';code=96;message='Un changement de nom attend déjà un redémarrage : aucune commande lancée.';restart=$false} }
    if(-not (Test-IsLocalAdmin)){ return @{status='refused';code=96;message='Pesto n''est pas élevé : Rename-Computer non lancé. Relancez l''hôte pour autoriser l''UAC. Le repli V1 par tâche élevée (POLICY.AllowPasswordTaskFallback) est réservé au renommage distant : le renommage local garde Rename-Computer comme seule autorité.';restart=$false} }
    try{ $change=@(Rename-Computer -NewName $newName -PassThru -Force -ErrorAction Stop -WarningAction SilentlyContinue @renameAuth) }
    catch{
      $native=Get-NativeCode $_
      if(Test-DefiniteRefusal $native){ return @{status='refused';code=[int]$native;message=('Refus Windows confirmé ('+[int]$native+') : '+[string]$_.Exception.Message+' Aucun repli automatique : le repli V1 par tâche (POLICY.AllowPasswordTaskFallback) est réservé au renommage distant ; le renommage local garde Rename-Computer comme seule autorité (port V1).');restart=$false} }
      return @{status='uncertain';code=97;message=('Appel de renommage engagé, résultat non confirmé (code natif '+$native+') : '+[string]$_.Exception.Message+' Vérifier avant toute reprise, jamais rejoué automatiquement. Aucun repli après un résultat incertain (règle V1).');restart=$true}
    }
  } else {
    if($null -eq $adp.Credential){ return @{status='refused';code=96;message='Renommage distant non lancé : choisissez Autre compte AD à l''ouverture de Pesto. Le jeton Windows ne fournit pas un mot de passe à déléguer (règle V1).';restart=$false} }
    $renameAuth.LocalCredential=$adp.Credential
    try{ $change=@(Rename-Computer -ComputerName $computer -NewName $newName -PassThru -Force -ErrorAction Stop -WarningAction SilentlyContinue @renameAuth) }
    catch{
      $native=Get-NativeCode $_
      if(Test-DefiniteRefusal $native){ return @{status='refused';code=[int]$native;message=('Refus Windows confirmé ('+[int]$native+') sur la cible distante : '+[string]$_.Exception.Message+' Aucun repli automatique hors politique : le repli V1 par tâche planifiée sous compte AD (POLICY.AllowPasswordTaskFallback) est décidé par l''adaptateur selon la politique lue du cfg.json, le compte explicitement saisi et le code natif, jamais après un résultat incertain (règle V1).');restart=$false} }
      return @{status='uncertain';code=97;message=('Appel de renommage distant engagé, résultat non confirmé (code natif '+$native+') : '+[string]$_.Exception.Message+' Vérifier avant toute reprise, jamais rejoué automatiquement. Aucun repli après un résultat incertain (règle V1).');restart=$true}
    }
  }
  if(Test-ConfirmedChange $change){ return @{status='pendingRestart';code=20;message='Renommage accepté ; redémarrage requis, planifié par l''opérateur. Pesto ne redémarre rien.';restart=$true} }
  if(@($change).Count -eq 1 -and $change[0].HasSucceeded -is [bool] -and -not $change[0].HasSucceeded){ return @{status='refused';code=21;message='Rename-Computer a confirmé HasSucceeded=False.';restart=$false} }
  return @{status='uncertain';code=97;message='Rename-Computer n''a pas renvoyé de résultat fiable ; aucun repli automatique. Vérifier le poste avant toute reprise.';restart=$true}
}
function Invoke-PestoMove($parsedGuid,$targetOu,$adp,$clearProtection){
  try{ $pc=Get-ADComputer -Identity $parsedGuid -Properties DistinguishedName,ObjectGUID,ProtectedFromAccidentalDeletion,userAccountControl -ErrorAction Stop @adp }
  catch{ return @{status='refused';code=99;message=('Précontrôle du déplacement impossible : '+[string]$_.Exception.Message+' Aucune écriture tentée.');restart=$false} }
  if($null -eq $pc){ return @{status='refused';code=99;message='Poste absent de l''annuaire par GUID : rien à déplacer.';restart=$false} }
  if([Guid]([string]$pc.ObjectGUID) -ne $parsedGuid){ return @{status='refused';code=96;message='L''identité AD observée ne correspond plus au plan GUID : aucun déplacement lancé.';restart=$false} }
  if($null -eq $pc.userAccountControl){ return @{status='refused';code=96;message='Rôle AD de la cible non confirmé : aucun déplacement lancé.';restart=$false} }
  if(([long]$pc.userAccountControl -band 8192) -ne 0){ return @{status='refused';code=96;message='Les contrôleurs de domaine sont exclus : aucun déplacement lancé.';restart=$false} }
  $srcOU=Get-ParentDn ([string]$pc.DistinguishedName)
  if(-not $sourceOu -or $srcOU -ine $sourceOu){return @{status='refused';code=96;message='L''OU source a changé depuis le plan : aucun déplacement lancé.';restart=$false}}
  try{Assert-PestoDestination $targetOu $targetOuGuid $adp}
  catch{return @{status='refused';code=96;message='L''identité de l''OU cible n''est plus confirmée : aucune protection levée, aucun déplacement lancé.';restart=$false}}
  if($srcOU -ieq $targetOu){ return @{status='refused';code=33;message='Le poste est déjà dans l''OU cible : aucun Move-ADObject nécessaire.';restart=$false} }
  if($pc.ProtectedFromAccidentalDeletion -isnot [bool]){ return @{status='refused';code=96;message='Protection initiale AD non confirmée : aucun déplacement lancé.';restart=$false} }
  $protected=[bool]$pc.ProtectedFromAccidentalDeletion
  if($null -ne $j.ExpectedProtection -and ($j.ExpectedProtection -isnot [bool] -or $protected -ne [bool]$j.ExpectedProtection)){
    return @{status='refused';code=96;message='La protection ne correspond plus au reçu parent : aucun déplacement lancé.';restart=$false}
  }
  if($null -ne $j.ExpectedProtection -and ([string]$pc.Name) -ine $computer){
    return @{status='refused';code=96;message='Le nom du GUID ne correspond plus au poste renommé : aucun déplacement lancé.';restart=$false}
  }
  $policyName=if($op -in @('renameMove','moveAfterRename')){$newName}else{$computer}
  try{Assert-PestoGroupExclusions $parsedGuid @($j.ExcludedGroupGuids) $adp $policyName $sourceOu}
  catch{return @{status='refused';code=96;message='POLICY.ExcludedGroupGuids : appartenance exclue ou non confirmée juste avant le déplacement ; aucune protection levée.';restart=$false}}
  # Port de MoveComputer V1 : levée temporaire uniquement si CONF.ClearProtectionOnMove est lu true (absent = true,
  # valeur du moteur V1) ; refus 31 motivé si la configuration l'interdit ; refus 96 si la valeur n'a pas pu être lue.
  if($protected){
    if($clearProtection -eq 'unknown'){ return @{status='refused';code=96;message='Objet protégé contre la suppression accidentelle et ClearProtectionOnMove non lu de façon fiable dans le cfg.json : protection ni levée ni admise, aucun déplacement lancé. Vérifier la configuration V1.';restart=$false} }
    if($clearProtection -ne 'true'){ return @{status='refused';code=31;message='Objet protégé ; levée temporaire interdite par la configuration (CONF.ClearProtectionOnMove lu false).';restart=$false} }
  }
  $moveStarted=$false;$moveError='';$restoreError='';$restoreRequired=$false
  try{
    if($protected){
      # Même si cet appel lève une exception, le finally tentera de restaurer le droit original (port V1).
      $restoreRequired=$true
      Set-ADObject -Identity $parsedGuid -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop @adp
    }
    $moveStarted=$true
    Move-ADObject -Identity $parsedGuid -TargetPath $targetOu -ErrorAction Stop @adp
  }catch{ $moveError=[string]$_.Exception.Message }
  finally{
    if($restoreRequired){
      try{ Set-ADObject -Identity $parsedGuid -ProtectedFromAccidentalDeletion:$true -ErrorAction Stop @adp }
      catch{ $restoreError=[string]$_.Exception.Message }
    }
  }
  $after=$null
  for($i=0;$i -lt 3;$i++){
    try{ $after=Get-ADComputer -Identity $parsedGuid -Properties DistinguishedName,ProtectedFromAccidentalDeletion -ErrorAction Stop @adp; break }
    catch{ if($i -lt 2){ Start-Sleep -Milliseconds 700 } }
  }
  if(-not $after){ return @{status='uncertain';code=97;message=('État indéterminé : lecture finale par GUID impossible. Déplacement : '+$moveError+' Protection : '+$restoreError+' Vérifier avant toute reprise, jamais rejoué automatiquement.');restart=$false} }
  $actualOU=Get-ParentDn ([string]$after.DistinguishedName)
  $moved=($actualOU -ieq $targetOu)
  # L'effet observé est consigné avant le contrôle de protection : un échec de restauration ne doit jamais effacer
  # un déplacement réellement constaté (port V1). Protection non rétablie = réparation manuelle, jamais de rejeu.
  if($after.ProtectedFromAccidentalDeletion -isnot [bool] -or [bool]$after.ProtectedFromAccidentalDeletion -ne $protected){
    return @{status='uncertain';code=32;message=('Protection NON RÉTABLIE. OU observée : '''+$actualOU+'''. Vérification et réparation manuelles requises. '+$restoreError+' Jamais rejoué automatiquement.');restart=$false}
  }
  if($moved){
    if($moveError){ return @{status='uncertain';code=97;message=('Déplacement constaté malgré une erreur de transport : '+$moveError+' Vérifier avant toute reprise, jamais rejoué automatiquement.');restart=$false} }
    return @{status='succeeded';code=30;message=('Déplacement confirmé par GUID vers la destination observée ; protection d''origine vérifiée.');restart=$false}
  }
  if($moveStarted -and $moveError){ return @{status='uncertain';code=97;message=('Déplacement non confirmé après erreur de transport. OU actuellement observée : '''+$actualOU+'''. Un effet différé reste possible ; vérifier avant relance. '+$moveError);restart=$false} }
  if($actualOU -ieq $srcOU -and ($moveError -or -not $moveStarted)){ return @{status='refused';code=31;message=('Déplacement refusé ; objet confirmé dans l''OU source et protection d''origine conservée. '+$moveError);restart=$false} }
  return @{status='uncertain';code=97;message=('Résultat du déplacement incohérent : OU observée inattendue. Ne relancez pas sans contrôle AD. '+$moveError);restart=$false}
}
function Complete-PestoRenameMove($parsedGuid,$targetOu,$adp,$clearProtection,$newName){
  # Port de Wait-ADComputerVisible V1 (60 s) : une panne AD est levée immédiatement et n'est plus maquillée en
  # délai de réplication ; une absence de visibilité sous 60 s est un déplacement DIFFÉRÉ. Dans les deux cas le
  # déplacement n'a pas été tenté : code 89, redémarrage à planifier, jamais relancé automatiquement.
  # L'observation porte sur le GUID du plan sous le nouveau nom (même objet, jamais un objet qui aurait pris ce nom).
  $visible=$false;$adFail=''
  $limit=(Get-Date).AddSeconds(60)
  while($true){
    try{ $found=Get-ADComputer -Identity $parsedGuid -Properties Name -ErrorAction Stop @adp; if($found -and ([string]$found.Name) -ieq $newName){$visible=$true;break} }
    catch{ $adFail=[string]$_.Exception.Message; break }
    if((Get-Date) -ge $limit){break}
    Start-Sleep -Milliseconds 800
  }
  if($adFail){ return @{status='pendingRestart';code=89;message=('Poste renommé en '''+$newName+''' mais la vérification AD a échoué ('+$adFail+') : DÉPLACEMENT NON TENTÉ. Reprogrammer un déplacement seul après vérification ; jamais relancé automatiquement.');restart=$true} }
  if(-not $visible){ return @{status='pendingRestart';code=89;message=('Poste renommé en '''+$newName+''' mais pas encore visible sous ce nom sur le contrôleur (réplication AD) : DÉPLACEMENT DIFFÉRÉ. Reprogrammer un déplacement seul ; jamais relancé automatiquement.');restart=$true} }
  $m=Invoke-PestoMove $parsedGuid $targetOu $adp $clearProtection
  # Port du mapping V1 (GoRenameAndMove) : 30/33 → 77 ; 32 protection non rétablie ; 97 arrêt de sécurité ;
  # tout autre refus = renommage accepté mais déplacement échoué → 89 à reprogrammer, jamais un demi-succès en succès.
  if($m.status -eq 'succeeded' -or ($m.status -eq 'refused' -and [int]$m.code -eq 33)){ return @{status='succeeded';code=77;message=('Poste renommé en '''+$newName+''' et déplacé vers la destination observée (ou déjà en place) ; redémarrage à planifier par l''opérateur.');restart=$true} }
  if([int]$m.code -eq 32){ return @{status='uncertain';code=32;message=('Renommage confirmé ; protection AD non rétablie : '+$m.message+' Jamais rejoué automatiquement.');restart=$true} }
  if($m.status -eq 'uncertain'){ return @{status='uncertain';code=97;message=('Poste renommé en '''+$newName+''' mais état du DÉPLACEMENT INDÉTERMINÉ : '+$m.message+' ARRÊT DE SÉCURITÉ : vérifier l''AD avant toute relance.');restart=$true} }
  return @{status='pendingRestart';code=89;message=('Poste renommé en '''+$newName+''' mais DÉPLACEMENT ÉCHOUÉ (code '+[int]$m.code+') : '+$m.message+' | Reprogrammer un déplacement seul ; jamais relancé automatiquement.');restart=$true}
}
$nativeChangeStarted=$false
$secure=$null
try{
  $j=[Console]::In.ReadToEnd()|ConvertFrom-Json
  $op=[string]$j.Op
  $domain=[string]$j.Domain
  $server=[string]$j.Server
  if(-not $server){$server=$domain}
  $computer=[string]$j.Computer
  $guid=[string]$j.ComputerGuid
  $newName=[string]$j.NewName
  $targetOu=[string]$j.TargetOu
  $sourceOu=[string]$j.SourceOu
  # Même OU : le pipeline natif ne doit jamais lever de protection ni tenter un déplacement inutile.
  # Le moteur normalise aussi renameMove quand le site reste identique, y compris en sous-OU.
  if($op -eq 'renameMove' -and $sourceOu -and $targetOu -ieq $sourceOu){$op='rename'}
  $targetOuGuid=[string]$j.TargetOuGuid
  # Décision lue du cfg.json par l'adaptateur (port Convert-Value-TF V1) : seule « true » autorise la levée temporaire ;
  # toute autre valeur reste « unknown » et bloque un objet protégé — jamais une levée implicite par défaut.
  $clearProtection=[string]$j.ClearProtectionOnMove
  if($clearProtection -ne 'true' -and $clearProtection -ne 'false'){$clearProtection='unknown'}
  if(-not $domain -or $domain -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$'){ throw 'Domaine invalide : aucune commande lancée.' }
  $adp=@{ Server=$server }
  $joinAuth=@{}
  if($null -ne $j.Credential){
    $bytes=$null
    try{
      Add-Type -AssemblyName System.Security
      $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String([string]$j.Credential.blob),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
      $secure=New-Object Security.SecureString
      for($i=0;$i -lt $bytes.Length;$i+=2){$secure.AppendChar([char]([int]$bytes[$i] -bor ([int]$bytes[$i+1] -shl 8)))}
      $secure.MakeReadOnly()
      $adp.Credential=New-Object Management.Automation.PSCredential([string]$j.Credential.userName,$secure)
      $joinAuth.Credential=$adp.Credential
    }catch{throw 'Compte AD explicite indisponible pour cette session Windows.'}
    finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
  }
  if(-not $j.AdModulePath){throw 'Module ActiveDirectory vérifié introuvable : aucune commande native lancée.'}
  Import-Module -Name ([string]$j.AdModulePath) -ErrorAction Stop
  if($op -in @('join','move','renameMove','moveAfterRename')){Assert-PestoDestination $targetOu $targetOuGuid $adp}
  $nameRx='^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$'
  switch($op){
    'join'{
      if(-not $newName -or $newName -notmatch $nameRx){ Out-PestoResult 'refused' 11 'Nom de jonction invalide ou hors convention : aucune commande lancée.' $false; break }
      if(-not $targetOu -or $targetOu.Length -gt 2048 -or $targetOu -match '[\x00-\x1f]'){ Out-PestoResult 'refused' 11 'OU de jonction invalide : aucune commande lancée.' $false; break }
      $local=Get-LocalStatus
      if($local.Name -ine $computer){ Out-PestoResult 'refused' 96 'Le nom du poste local a changé depuis la préparation : la jonction ne concerne que ce poste, aucune commande lancée.' $false; break }
      if($local.PartOfDomain){ Out-PestoResult 'refused' 96 'Poste déjà membre d''un domaine : aucune sortie de domaine implicite, aucune commande lancée.' $false; break }
      if($local.PendingRename){ Out-PestoResult 'refused' 96 'Un changement de nom attend un redémarrage : aucune commande lancée.' $false; break }
      if(-not (Test-IsLocalAdmin)){ Out-PestoResult 'refused' 96 'Pesto n''est pas élevé : Add-Computer non lancé. Relancez l''hôte pour autoriser l''UAC avant la connexion. Le repli V1 par tâche élevée est réservé au renommage distant (port V1) : la jonction locale garde Add-Computer comme seule autorité.' $false; break }
      $ldap='(|(name='+$newName+')(sAMAccountName='+$newName+'$)(dNSHostName='+$newName+'.'+$domain+'))'
      $existing=@(Get-ADComputer -LDAPFilter $ldap -ResultSetSize 2 -ErrorAction Stop @adp)
      if($null -ne $j.Reservation){
        try{
          Assert-PestoReservedJoin $j.Reservation $newName $targetOu $domain $server $adp
          if($existing.Count -ne 1 -or [Guid]$existing[0].ObjectGUID -ne [Guid]$j.Reservation.ComputerGuid){throw 'Le nom ne correspond pas au GUID réservé.'}
          Assert-PestoGroupExclusions ([string]$j.Reservation.ComputerGuid) @($j.ExcludedGroupGuids) $adp $newName $targetOu
        }catch{Out-PestoResult 'refused' 96 'Réservation AD ou exclusions non confirmées : aucun renommage ni ajout lancé.' $false;break}
      }elseif($null -ne $j.PrecreatedJoin){
        try{
          Assert-PestoPrecreatedJoin $j.PrecreatedJoin $newName $targetOu $domain $server $adp
          if($existing.Count -ne 1 -or [Guid]$existing[0].ObjectGUID -ne [Guid]$j.PrecreatedJoin.ComputerGuid){throw 'Le nom ne correspond plus au GUID précréé.'}
          Assert-PestoGroupExclusions ([string]$j.PrecreatedJoin.ComputerGuid) @($j.ExcludedGroupGuids) $adp $newName $targetOu
        }catch{Out-PestoResult 'refused' 96 'Compte précréé ou exclusions non confirmés : aucun renommage ni ajout lancé.' $false;break}
      }elseif($existing.Count -gt 0){ Out-PestoResult 'refused' 13 'Compte ordinateur déjà présent dans l''annuaire : aucun objet supprimé, Add-Computer non lancé.' $false; break }
      $renameRequested=$false
      if($local.ActiveName -ine $newName){
        try{ $ren=@(Rename-Computer -NewName $newName -PassThru -Force -ErrorAction Stop -WarningAction SilentlyContinue) }
        catch{ Out-PestoResult 'uncertain' 97 ('Préparation du nom local engagée, résultat non confirmé : '+[string]$_.Exception.Message+' Vérifier le nom actif avant toute reprise, jamais rejouée automatiquement.') $true; break }
        if(-not (Test-ConfirmedChange $ren)){ Out-PestoResult 'uncertain' 97 'Préparation du nom local non confirmée : aucun ajout lancé ; vérifier le nom actif et le nom en attente avant toute reprise.' $true; break }
        $renameRequested=$true
        $nativeChangeStarted=$true
      }
      $after=Get-LocalStatus
      if($after.PartOfDomain -or $after.ConfiguredName -ine $newName){
        if($renameRequested){ Out-PestoResult 'uncertain' 97 'État Windows modifié ou nouveau nom local non confirmé avant l''ajout : aucun Add-Computer supplémentaire. Conserver le reçu et vérifier le poste.' $true }
        else{ Out-PestoResult 'refused' 96 'État Windows modifié avant l''ajout : aucun Add-Computer lancé. Conserver le reçu et vérifier le poste.' $false }
        break
      }
      Assert-PestoDestination $targetOu $targetOuGuid $adp
      if($null -ne $j.Reservation){
        Assert-PestoReservedJoin $j.Reservation $newName $targetOu $domain $server $adp
        Assert-PestoGroupExclusions ([string]$j.Reservation.ComputerGuid) @($j.ExcludedGroupGuids) $adp $newName $targetOu
      }
      if($null -ne $j.PrecreatedJoin){
        Assert-PestoPrecreatedJoin $j.PrecreatedJoin $newName $targetOu $domain $server $adp
        Assert-PestoGroupExclusions ([string]$j.PrecreatedJoin.ComputerGuid) @($j.ExcludedGroupGuids) $adp $newName $targetOu
      }
      try{
        $nativeChangeStarted=$true
        if($null -ne $j.Reservation -or $null -ne $j.PrecreatedJoin){
          $change=@(Add-Computer -DomainName $domain -Server $server -OUPath $targetOu -Options JoinWithNewName -PassThru -Force -ErrorAction Stop -WarningAction SilentlyContinue @joinAuth)
        }else{
          $change=@(Add-Computer -DomainName $domain -Server $server -OUPath $targetOu -Options JoinWithNewName,AccountCreate -PassThru -Force -ErrorAction Stop -WarningAction SilentlyContinue @joinAuth)
        }
      }catch{
        $native=Get-NativeCode $_
        if($renameRequested){ Out-PestoResult 'uncertain' 97 'Ajout refusé après préparation du nouveau nom local : le changement de nom reste à vérifier ; aucune reprise ni annulation automatique.' $true; break }
        if(Test-DefiniteRefusal $native){ Out-PestoResult 'refused' ([int]$native) ('Refus Windows confirmé ('+[int]$native+') : '+[string]$_.Exception.Message+' Aucun objet AD supprimé, aucun repli.') $false; break }
        Out-PestoResult 'uncertain' 97 ('Jonction engagée, résultat non confirmé (code natif '+$native+') : '+[string]$_.Exception.Message+' Vérifier le poste avant toute reprise, jamais rejouée automatiquement.') $true; break
      }
      if(-not (Test-ConfirmedChange $change)){
        if($change.Count -eq 1 -and $change[0].HasSucceeded -is [bool] -and -not $change[0].HasSucceeded){
          if($renameRequested){ Out-PestoResult 'uncertain' 97 'Ajout refusé après préparation du nouveau nom local : le changement de nom reste à vérifier ; aucune reprise ni annulation automatique.' $true; break }
          Out-PestoResult 'refused' 11 'Add-Computer a confirmé HasSucceeded=False : rien n''a été écrit.' $false; break
        }
        Out-PestoResult 'uncertain' 97 'Jonction indéterminée : Add-Computer n''a pas renvoyé de confirmation fiable. Vérifier aussi le nom local en attente.' $true; break
      }
      if($null -ne $j.Reservation){
        try{Assert-PestoReservedJoinResult $j.Reservation $adp}
        catch{Out-PestoResult 'uncertain' 97 'Jonction engagée mais GUID du compte réservé non confirmé après ajout ; inspectez avant toute reprise.' $true;break}
      }
      if($null -ne $j.PrecreatedJoin){
        try{Assert-PestoPrecreatedJoinResult $j.PrecreatedJoin $adp}
        catch{Out-PestoResult 'uncertain' 97 'Jonction engagée mais GUID du compte précréé non confirmé après ajout ; aucune création ni reprise automatique.' $true;break}
      }
      Out-PestoResult 'pendingRestart' 10 'Ajout au domaine accepté ; redémarrage à préparer et confirmer séparément par l''opérateur. Aucun redémarrage implicite.' $true
      break
    }
    'rename'{
      if(-not $newName -or $newName -notmatch $nameRx){ Out-PestoResult 'refused' 11 'Nouveau nom invalide : aucune commande lancée.' $false; break }
      $r=Invoke-PestoRename $computer $newName
      Out-PestoResult $r.status $r.code $r.message $r.restart
      break
    }
    'move'{
      $parsedGuid=[Guid]::Empty
      if(-not [Guid]::TryParse($guid,[ref]$parsedGuid) -or $parsedGuid -eq [Guid]::Empty){ Out-PestoResult 'refused' 96 'Identité GUID du plan absente ou invalide : aucune commande lancée.' $false; break }
      if(-not $targetOu -or $targetOu.Length -gt 2048 -or $targetOu -match '[\x00-\x1f]'){ Out-PestoResult 'refused' 31 'OU cible invalide ou hors périmètre : aucune commande lancée.' $false; break }
      $m=Invoke-PestoMove $parsedGuid $targetOu $adp $clearProtection
      Out-PestoResult $m.status $m.code $m.message $m.restart
      break
    }
    'renameMove'{
      if(-not $newName -or $newName -notmatch $nameRx){ Out-PestoResult 'refused' 11 'Nouveau nom invalide : aucune commande lancée.' $false; break }
      $parsedGuid=[Guid]::Empty
      if(-not [Guid]::TryParse($guid,[ref]$parsedGuid) -or $parsedGuid -eq [Guid]::Empty){ Out-PestoResult 'refused' 96 'Identité GUID du plan absente ou invalide : aucune commande lancée.' $false; break }
      if(-not $targetOu -or $targetOu.Length -gt 2048 -or $targetOu -match '[\x00-\x1f]'){ Out-PestoResult 'refused' 31 'OU cible invalide ou hors périmètre : aucune commande lancée.' $false; break }
      $r=Invoke-PestoRename $computer $newName
      if($r.status -ne 'pendingRestart'){ Out-PestoResult $r.status $r.code $r.message $r.restart; break }
      $nativeChangeStarted=$true
      $f=Complete-PestoRenameMove $parsedGuid $targetOu $adp $clearProtection $newName
      Out-PestoResult $f.status $f.code $f.message $f.restart
      break
    }
    'moveAfterRename'{
      $nativeChangeStarted=$true
      # Enchaînement porté de GoRenameAndMove V1 après un repli de renommage accepté par tâche élevée : le renommage a
      # déjà été confirmé par le repli (tâche sous compte AD) ; seule la pipeline déplacement est rejouée — attente de
      # visibilité du GUID du plan sous le nouveau nom (60 s) puis déplacement, mapping 77/89/97/32 inchangés. Le
      # renommage n'est JAMAIS relancé ici : un repli accepté ne se répète pas (règle V1 « aucun rejeu »).
      if(-not $newName -or $newName -notmatch $nameRx){ Out-PestoResult 'refused' 11 'Nouveau nom invalide : aucune commande lancée.' $false; break }
      $parsedGuid=[Guid]::Empty
      if(-not [Guid]::TryParse($guid,[ref]$parsedGuid) -or $parsedGuid -eq [Guid]::Empty){ Out-PestoResult 'refused' 96 'Identité GUID du plan absente ou invalide : aucune commande lancée.' $false; break }
      if(-not $targetOu -or $targetOu.Length -gt 2048 -or $targetOu -match '[\x00-\x1f]'){ Out-PestoResult 'refused' 31 'OU cible invalide ou hors périmètre : aucune commande lancée.' $false; break }
      $f=Complete-PestoRenameMove $parsedGuid $targetOu $adp $clearProtection $newName
      Out-PestoResult $f.status $f.code $f.message $f.restart
      break
    }
    default{ throw 'Opération de mutation non déclarée : aucune commande lancée.' }
  }
}catch{
  if($nativeChangeStarted){
    Out-PestoResult 'uncertain' 97 'Changement Windows déjà engagé, résultat final non confirmé. Vérifier les noms actif/configuré et le domaine ; aucune reprise automatique.' $true
  }else{
    Out-PestoResult 'refused' 96 ('Conditions préalables non réunies, aucune commande native lancée : '+[string]$_.Exception.Message) $false
  }
}finally{if($secure){$secure.Dispose()}}
""";
}

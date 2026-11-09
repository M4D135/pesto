using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Une ligne de l'historique durable. <c>Readable=false</c> = fichier isolé (port de Get-PestoInterventionCatalogue :
/// un reçu illisible est annoncé comme tel, « Aucun verrou levé », jamais silencieusement écarté ni présenté comme un reçu).
/// </summary>
public sealed record HistoryEntry(Receipt Receipt, bool Readable, bool Acknowledged);

/// <summary>Résultat de la lecture du registre durable : jamais d'écriture, jamais de suppression, jamais de fusion arbitraire.</summary>
public sealed record GpHistoryResult(bool Available, string? Reason, IReadOnlyList<HistoryEntry> Entries, int InvalidCount, bool Truncated);

/// <summary>
/// Port des lecteurs d'historique durable V1 (Get-PestoInterventionCatalogue + Read-PestoIntervention pour le registre
/// %ProgramData%\GP\Interventions, et du format de reçu durable écrit par l'adaptateur de mutation dans GP\V2\receipts).
/// Lecture seule stricte : aucun fichier n'est supprimé, déplacé, réécrit ni « réparé » ; un fichier illisible est isolé
/// avec son nom, pas fusionné ni ignoré ; la borne d'affichage (5 000 fichiers par dossier, port v1) est annoncée tronquée.
/// Ce lecteur est celui de l'affichage (reçus, tableau de bord) : les barrières métier d'écriture restent lues par
/// l'adaptateur de mutation lui-même avant toute commande native (docs/PARITY.md).
/// </summary>
internal static class GpHistory
{
    public const string Source = "registre local GP · Interventions V1 + reçus durables de l’adaptateur (lecture seule)";
    private const int MaximumFilesPerFolder = 5000;
    private const long MaximumFileBytes = 131072;
    private static readonly Regex ComputerName = new(@"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$", RegexOptions.CultureInvariant);
    private static readonly Regex DnsName = new(@"^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$", RegexOptions.CultureInvariant);
    private static readonly Regex OpaqueId = new(@"^[A-Za-z0-9._-]{1,128}$", RegexOptions.CultureInvariant);
    private static readonly Regex Hash64 = new(@"\A[A-Fa-f0-9]{64}\z", RegexOptions.CultureInvariant);
    private static readonly Regex TaskName = new(@"^\\Pesto_[A-Za-z0-9_]+$", RegexOptions.CultureInvariant);

    private static readonly string[] V1Phases = ["Running", "Failed", "PendingRestart", "Partial", "MoveReady", "Protection", "Uncertain", "Verified"];
    private static readonly string[] V1Entra = ["NotRequested", "Requested", "Skipped", "Confirmed", "Uncertain"];
    private static readonly string[] V1Protection = ["NotChanged", "Prepared", "Lowering", "Lowered", "Restoring", "Restored"];
    private static readonly string[] V1Effect = ["NotRequested", "Requested", "Confirmed", "Refused"];
    private static readonly string[] AdapterPhases = ["Running", "Verified", "Failed", "PendingRestart", "Uncertain", "Partial"];
    private static readonly string[] Kinds = ["join", "rename", "move", "renameMove", "attributes", "offlineJoin"];

    private static readonly string[] V1Fields =
    [
        "Schema", "Version", "OperationId", "Plan", "StartedUtc", "UpdatedUtc", "Phase", "InitialProtection", "TargetMachineId",
        "TargetOUGuid", "Entra", "Protection", "Rename", "Move", "ResultCode", "ResultMessage", "LastStage", "VerifiedUtc",
        "VerifiedBy", "ResumeFrom", "PlanFingerprint", "Sequence", "Timeline", "Coordination", "Tasks", "Legacy", "Baseline",
        "LastObservation", "JoinEvidence", "Metadata", "Acknowledged", "Attributes", "AttributeChanges", "OfflineJoin",
    ];
    private static readonly string[] V1Required = ["Schema", "OperationId", "Plan", "Phase", "Entra", "Protection", "Rename", "Move", "ResultCode"];
    private static readonly string[] V1PlanFields =
    [
        "Nom_du_PC", "Nouveau_Nom", "OU_Actuelle", "OU_Destination", "Objet_GUID", "Domain", "DC", "ConfigStamp", "TargetOUGuid",
        "Renommer", "Deplacer", "Reboot", "Reference", "Action", "Metadata", "Changes",
    ];
    private static readonly string[] V1PlanRequired = ["Nom_du_PC", "Domain", "Renommer", "Deplacer"];
    private static readonly string[] AdapterFields =
    [
        "Schema", "Version", "Phase", "Utc", "Adapter", "ReceiptId", "PlanId", "Kind", "Computer", "NewName", "TargetOu", "Code", "Message", "RestartRequired", "Acknowledged", "CreatedUtc", "ComputerGuid", "Domain", "Dc", "InitialBootUtc", "MachineId", "LocalTarget", "InitialProtected", "InitialOu", "TargetOuGuid", "Reconciliation", "ParentReceiptId", "ParentReceiptSha256", "ContinuationAttemptId", "ContinuationParentStateSha256",
        "ContinuationChildReceiptId", "ContinuationChildPlanId", "ContinuationParentReceiptSha256", "ResolutionChildReceiptId", "ResolutionChildReceiptSha256", "ResolutionUtc",
        "Clock", "AuditEventLogEnabled", "ConfigurationSha256", "ReservationId", "ReservationAction", "Coordination", "WindowsBaselineProof",
        "InitialWindowsDomain", "InitialPartOfDomain", "InitialDomainRole", "Entra", "EntraEvidenceId", "EntraEvidenceSha256", "EntraMayStillRun", "EntraReenrollmentPending",
        "JoinAccountMode", "Attributes", "AttributeChanges", "AttributeObservation", "OfflineJoin", "OfflineJoinId", "OfflineJoinSha256", "ExpectedAdGuid",
    ];
    private static readonly string[] AdapterRequired = ["Schema", "Phase", "ReceiptId", "PlanId", "Kind", "Computer", "Code"];

    /// <summary>Lit le registre durable sous <paramref name="gpRoot"/> (dossier GP : Interventions V1 + V2/receipts de l'adaptateur).
    /// gpRoot null = aucun emplacement durable connu sur ce poste : résultat « inconnu », jamais une liste vide présentée comme un historique lu.</summary>
    public static GpHistoryResult Read(string? gpRoot)
    {
        if (string.IsNullOrWhiteSpace(gpRoot))
            return new GpHistoryResult(false, "Aucun dossier d’historique durable n’est disponible sur ce poste (GP/Interventions et reçus de l’adaptateur non accessibles) : les compteurs d’historique restent inconnus plutôt que supposés.", [], 0, false);
        var entries = new List<HistoryEntry>();
        var invalid = 0;
        var truncated = false;
        foreach (var (folder, parse) in new (string, Func<string, string, HistoryEntry>)[]
        {
            (Path.Combine(gpRoot, "Interventions"), (path, folder) => ReadV1(path, folder, gpRoot)),
            (Path.Combine(gpRoot, "V2", "receipts"), (path, folder) => ReadAdapter(path, folder, gpRoot)),
        })
        {
            if (!Directory.Exists(folder)) continue;
            List<string> files;
            try { files = Directory.EnumerateFiles(folder, "*.json", SearchOption.TopDirectoryOnly).Take(MaximumFilesPerFolder + 1).ToList(); }
            catch (Exception error) when (error is UnauthorizedAccessException or IOException)
            {
                return new GpHistoryResult(false, "Le dossier d’historique durable « " + folder + " » n’a pas pu être énuméré : " + Short(error.Message) + " Aucun fichier supprimé, aucune liste partielle présentée comme un historique.", [], 0, false);
            }
            if (files.Count > MaximumFilesPerFolder) truncated = true;
            foreach (var path in files.Take(MaximumFilesPerFolder))
            {
                var entry = parse(path, folder);
                entries.Add(entry);
                if (!entry.Readable) invalid++;
            }
        }
        return new GpHistoryResult(true, null, entries, invalid, truncated);
    }

    // ---- reçus durables de l'adaptateur v2 (format écrit par PowerShellMutationGateway) --------------

    private static HistoryEntry ReadAdapter(string path, string folder, string gpRoot)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.Length is < 1 or > MaximumFileBytes || (info.Attributes & FileAttributes.ReparsePoint) != 0) return Unreadable(path);
            var bytes = File.ReadAllBytes(path);
            var entry = ParseAdapterSnapshot(path, bytes, new DateTimeOffset(info.LastWriteTimeUtc, TimeSpan.Zero));
            if (entry.Readable && !OfflineJoinReceipt.ValidateStored(gpRoot, bytes)) return Unreadable(path);
            return entry.Readable && ReceiptAcknowledgementStore.TryReadForReceipt(gpRoot, path, bytes) is not null
                ? entry with { Acknowledged = true } : entry;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return Unreadable(path); }
    }

    /// <summary>Validate only these exact bytes. A caller can hash/pin the same snapshot without a second file read.</summary>
    internal static HistoryEntry ParseAdapterSnapshot(string path, ReadOnlyMemory<byte> bytes, DateTimeOffset lastWriteUtc)
    {
        var fileName = Path.GetFileName(path);
        var root = ParseObjectSnapshot(bytes);
        if (root is null) return Unreadable(path);
        if (!Closed(root.Value, AdapterFields, AdapterRequired) || !ReceiptEvidenceIsValid(root.Value)) return Unreadable(path);
        if (!Text(root.Value, "Phase", out var phase) || !AdapterPhases.Contains(phase, StringComparer.Ordinal)) return Unreadable(path);
        if (!Text(root.Value, "ReceiptId", out var receiptId) || !OpaqueId.IsMatch(receiptId)) return Unreadable(path);
        if (!fileName.Equals(receiptId + ".json", StringComparison.OrdinalIgnoreCase)) return Unreadable(path); // le fichier est nommé d'après le reçu : aucune identité croisée
        if (!Text(root.Value, "PlanId", out var planId) || !OpaqueId.IsMatch(planId)) return Unreadable(path);
        if (!Text(root.Value, "Kind", out var kind) || !Kinds.Contains(kind, StringComparer.Ordinal)) return Unreadable(path);
        if (!Text(root.Value, "Computer", out var computer) || !ComputerName.IsMatch(computer)) return Unreadable(path);
        if (!OptionalText(root.Value, "NewName", out var newName) || (newName is not null && !ComputerName.IsMatch(newName))) return Unreadable(path);
        if (!OptionalText(root.Value, "TargetOu", out var targetOu) || (targetOu is not null && (targetOu.Length > 2048 || targetOu.Any(char.IsControl)))) return Unreadable(path);
        if (!Integer(root.Value, "Code", out var code)) return Unreadable(path);
        if (!OptionalText(root.Value, "Message", out var message) || (message is not null && (message.Length > 1024 || message.Any(char.IsControl)))) return Unreadable(path);
        if (!OptionalText(root.Value, "Adapter", out var adapter) || (adapter is not null && (adapter.Length > 400 || adapter.Any(char.IsControl)))) return Unreadable(path);
        if (!OptionalText(root.Value, "Version", out var version) || (version is not null && version.Length > 32)) return Unreadable(path);
        if (root.Value.TryGetProperty("Schema", out var schema) && (schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var schemaValue) || schemaValue != 1)) return Unreadable(path);
        if (!Flag(root.Value, "RestartRequired", out var restart)) return Unreadable(path);
        if (!Time(root.Value, "Utc", out var utc)) utc = lastWriteUtc; // timestamp observed by the snapshot's caller
        var status = phase switch
        {
            "Verified" => "succeeded",
            "Failed" => "refused",
            "PendingRestart" => "pendingRestart",
            _ => "uncertain", // Running et Uncertain : non finalisé, à vérifier, jamais rejoué automatiquement
        };
        if (!OptionalText(root.Value, "ParentReceiptId", out var parentId) || !OptionalText(root.Value, "ResolutionChildReceiptId", out var resolutionId)) return Unreadable(path);
        var receipt = new Receipt(receiptId, utc, kind, computer, newName ?? "", targetOu ?? "",
            "live · " + (adapter ?? "adaptateur de mutation") + " · reçu durable relu sur disque", status, code,
            message ?? "Aucun détail consigné par l’adaptateur.", restart, parentId, resolutionId);
        return new HistoryEntry(receipt, true, StoredMutationBarrier.IsAcknowledged(root.Value));
    }

    private static bool ReceiptEvidenceIsValid(JsonElement root)
    {
        if (!AttributeMutationRules.ReceiptMetadataIsValid(root) || !OfflineJoinReceipt.ValidateEvidence(root)) return false;
        if (!PolicyEvidenceIsValid(root)) return false;
        if (!EntraEvidenceIsValid(root)) return false;
        if (root.TryGetProperty("JoinAccountMode", out var account) && account.ValueKind != JsonValueKind.Null)
        {
            if (account.ValueKind != JsonValueKind.String || account.GetString() is not ("new" or "precreated")
                || !Text(root, "Kind", out var joinKind) || joinKind != "join") return false;
            if (account.GetString() == "precreated"
                && (!Text(root, "ComputerGuid", out var computerGuid) || !RemoteWindowsEvidenceProtocol.IsGuid(computerGuid)
                    || !Text(root, "TargetOuGuid", out var targetGuid) || !RemoteWindowsEvidenceProtocol.IsGuid(targetGuid)
                    || !Text(root, "ConfigurationSha256", out var configHash) || !Hash64.IsMatch(configHash)
                    || !Text(root, "TargetOu", out _) || !OptionalText(root, "ReservationId", out var reservationId) || reservationId is not null)) return false;
        }
        if (root.TryGetProperty("WindowsBaselineProof", out var baseline) && baseline.ValueKind != JsonValueKind.Null
            && !ReceiptWindowsEvidence.RemoteBaselineMatches(root)) return false;
        foreach (var key in new[] { "ParentReceiptId", "ContinuationChildReceiptId", "ContinuationChildPlanId", "ResolutionChildReceiptId" })
            if (!OptionalText(root, key, out var id) || (id is not null && !OpaqueId.IsMatch(id))) return false;
        foreach (var key in new[] { "ParentReceiptSha256", "ContinuationAttemptId", "ContinuationParentStateSha256", "ContinuationParentReceiptSha256", "ResolutionChildReceiptSha256" })
            if (!OptionalText(root, key, out var hashValue) || (hashValue is not null && !Hash64.IsMatch(hashValue))) return false;
        if (root.TryGetProperty("ResolutionUtc", out var resolutionTime) && resolutionTime.ValueKind != JsonValueKind.Null && !Time(root, "ResolutionUtc", out _)) return false;
        if (root.TryGetProperty("ResolutionChildReceiptId", out var resolution) && resolution.ValueKind != JsonValueKind.Null
            && (!Text(root, "ResolutionChildReceiptSha256", out var childHash) || !Hash64.IsMatch(childHash)
                || !Time(root, "ResolutionUtc", out _) || !Text(root, "Phase", out var partial) || partial != "Partial"
                || !Integer(root, "Code", out var code) || code != 89)) return false;

        foreach (var key in new[] { "ComputerGuid", "Domain", "Dc", "MachineId", "InitialOu", "TargetOuGuid", "InitialWindowsDomain" })
            if (root.TryGetProperty(key, out var value) && value.ValueKind != JsonValueKind.Null
                && (value.ValueKind != JsonValueKind.String || value.GetString()!.Length > 2048 || value.GetString()!.Any(char.IsControl))) return false;
        foreach (var key in new[] { "ComputerGuid", "TargetOuGuid" })
            if (root.TryGetProperty(key, out var guid) && guid.ValueKind == JsonValueKind.String
                && (!Guid.TryParse(guid.GetString(), out var parsed) || parsed == Guid.Empty)) return false;
        foreach (var key in new[] { "CreatedUtc", "InitialBootUtc" })
            if (root.TryGetProperty(key, out var value) && value.ValueKind != JsonValueKind.Null && !Time(root, key, out _)) return false;
        foreach (var key in new[] { "LocalTarget", "InitialProtected", "InitialPartOfDomain" })
            if (root.TryGetProperty(key, out var value) && value.ValueKind is not (JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null)) return false;
        if (root.TryGetProperty("InitialDomainRole", out var initialRole) && initialRole.ValueKind != JsonValueKind.Null
            && (initialRole.ValueKind != JsonValueKind.Number || !initialRole.TryGetInt32(out var role) || role is < 0 or > 5)) return false;
        if (!root.TryGetProperty("Reconciliation", out var proof) || proof.ValueKind == JsonValueKind.Null) return true;
        string[] fields = ["Utc", "PreviousPhase", "ReceiptSha256", "ExpectedGuid", "AdGuid", "AdName", "AdOu", "AdProtected", "CurrentBootUtc", "WindowsActiveName", "WindowsConfiguredName", "WindowsDomain", "WindowsPartOfDomain", "SecureChannel", "MachineIdentityMatches"];
        if (!Closed(proof, [.. fields, "RemoteWindowsProof"], fields) || !Time(proof, "Utc", out _)) return false;
        foreach (var item in proof.EnumerateObject())
        {
            if (item.Value.ValueKind == JsonValueKind.Null) continue;
            if (item.Name == "RemoteWindowsProof")
            {
                if (!ReceiptWindowsEvidence.RemoteReconciliationMatches(root, proof)) return false;
                continue;
            }
            if (item.Name is "AdProtected" or "WindowsPartOfDomain" or "SecureChannel" or "MachineIdentityMatches")
            {
                if (item.Value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
            }
            else if (item.Value.ValueKind != JsonValueKind.String || item.Value.GetString()!.Length > 2048 || item.Value.GetString()!.Any(char.IsControl)) return false;
        }
        if (!Text(proof, "ReceiptSha256", out var hash) || !Hash64.IsMatch(hash)) return false;
        foreach (var key in new[] { "ExpectedGuid", "AdGuid" })
            if (!Text(proof, key, out var value) || !Guid.TryParse(value, out var proofGuid) || proofGuid == Guid.Empty) return false;
        if (proof.TryGetProperty("CurrentBootUtc", out var boot) && boot.ValueKind != JsonValueKind.Null && !Time(proof, "CurrentBootUtc", out _)) return false;
        return true;
    }

    private static bool EntraEvidenceIsValid(JsonElement root)
    {
        if (!root.TryGetProperty("Entra", out var entra))
            return !root.TryGetProperty("EntraEvidenceId", out _) && !root.TryGetProperty("EntraEvidenceSha256", out _)
                && !root.TryGetProperty("EntraMayStillRun", out _) && !root.TryGetProperty("EntraReenrollmentPending", out _);
        if (entra.ValueKind != JsonValueKind.String || !V1Entra.Contains(entra.GetString(), StringComparer.Ordinal)
            || !OptionalText(root, "EntraEvidenceId", out var evidenceId) || !OptionalText(root, "EntraEvidenceSha256", out var sha)) return false;
        var effect = entra.GetString();
        if (evidenceId is not null && (!Text(root, "ReceiptId", out var receiptId) || evidenceId != receiptId
            || !Text(root, "Kind", out var kind) || kind is not ("rename" or "renameMove"))) return false;
        if (sha is not null && (evidenceId is null || !Hash64.IsMatch(sha))) return false;
        foreach (var field in new[] { "EntraMayStillRun", "EntraReenrollmentPending" })
            if (root.TryGetProperty(field, out var node) && node.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
        var mayRun = root.TryGetProperty("EntraMayStillRun", out var running) && running.ValueKind == JsonValueKind.True;
        var reenroll = root.TryGetProperty("EntraReenrollmentPending", out var pending) && pending.ValueKind == JsonValueKind.True;
        if (effect is "Requested" or "Confirmed" or "Uncertain" && evidenceId is null) return false;
        if (effect == "Confirmed" && (sha is null || !reenroll)) return false;
        if (effect != "Confirmed" && reenroll) return false;
        if (effect is "NotRequested" or "Skipped" && mayRun) return false;
        if (effect == "Skipped" && (sha is not null || evidenceId is not null)) return false;
        if ((mayRun || effect is "Requested" or "Uncertain") && Text(root, "Phase", out var phase)
            && phase is "Verified" or "PendingRestart" or "Failed") return false;
        return true;
    }

    /// <summary>Only metadata emitted by the native C3 receipt is admitted. Parsing an intention is pure:
    /// the history reader never probes its share, reservation account or current configuration.</summary>
    private static bool PolicyEvidenceIsValid(JsonElement root)
    {
        if (root.TryGetProperty("ConfigurationSha256", out var configuration)
            && (configuration.ValueKind != JsonValueKind.String || !Hash64.IsMatch(configuration.GetString()!))) return false;
        if (root.TryGetProperty("AuditEventLogEnabled", out var audit)
            && audit.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
        if (!OptionalText(root, "ReservationId", out var reservationId) || !OptionalText(root, "ReservationAction", out var action)) return false;
        if (reservationId is not null)
        {
            if (reservationId.Length != 44 || !JoinReservationStore.IsId(reservationId)
                || !Guid.TryParseExact(reservationId[12..], "N", out var id) || id == Guid.Empty
                || !Text(root, "Kind", out var kind) || kind != "join") return false;
        }
        if (action is not null && (reservationId is null || action is not ("initialJoin" or "resumeJoin")
            || !Text(root, "ComputerGuid", out var reservedGuid) || !Guid.TryParse(reservedGuid, out var reserved) || reserved == Guid.Empty)) return false;
        if (root.TryGetProperty("Clock", out var clock) && clock.ValueKind != JsonValueKind.Null)
        {
            string[] fields = ["State", "Message", "Server", "ObservedUtc", "OffsetSeconds", "Blocked"];
            if (!Text(root, "Kind", out var kind) || kind != "join" || !Closed(clock, fields, fields)
                || !Text(clock, "State", out var state) || !Text(clock, "Message", out var message) || message.Length > 2048
                || !Text(clock, "ObservedUtc", out _) || !Time(clock, "ObservedUtc", out var observed) || observed.Offset != TimeSpan.Zero
                || !Flag(clock, "Blocked", out var blocked) || !OptionalText(clock, "Server", out var server)
                || server is not null && !JoinClockGuard.IsServer(server)) return false;
            if (server is not null && (!OptionalText(root, "Dc", out var dc) || !string.Equals(server, dc, StringComparison.OrdinalIgnoreCase))) return false;
            var offsetNode = clock.GetProperty("OffsetSeconds");
            double? offset = null;
            if (offsetNode.ValueKind != JsonValueKind.Null)
            {
                if (offsetNode.ValueKind != JsonValueKind.Number || !offsetNode.TryGetDouble(out var measured) || !double.IsFinite(measured)) return false;
                offset = measured;
            }
            if (state == "warning") { if (offset is not null || blocked) return false; }
            else if (state is "observed" or "blocked")
            {
                if (server is null || offset is null || blocked != (Math.Abs(offset.Value) >= JoinClockGuard.MaximumAllowedSkewSeconds)
                    || blocked != (state == "blocked")) return false;
                if (blocked && (!Text(root, "Phase", out var phase) || phase != "Failed")) return false;
            }
            else return false;
        }
        if (!root.TryGetProperty("Coordination", out var coordination) || coordination.ValueKind == JsonValueKind.Null) return true;
        try
        {
            var intent = SharedCoordinationProtocol.ReadIntent(coordination);
            if (!Text(root, "ReceiptId", out var receiptId) || intent.ReceiptId != receiptId
                || !Text(root, "ConfigurationSha256", out var sha) || !string.Equals(intent.ConfigSha256, sha, StringComparison.OrdinalIgnoreCase)
                || !Text(root, "Domain", out var domain) || !string.Equals(intent.Domain, domain, StringComparison.OrdinalIgnoreCase)
                || !Text(root, "Computer", out var computer) || !string.Equals(intent.Identity.Computer, computer, StringComparison.OrdinalIgnoreCase)
                || !OptionalText(root, "NewName", out var name) || !string.Equals(intent.Identity.NewName, name, StringComparison.OrdinalIgnoreCase)) return false;
            if (intent.Identity.ComputerGuid is { } expected)
            {
                if (!Text(root, "ComputerGuid", out var actual) || !Guid.TryParse(actual, out var guid) || guid != Guid.Parse(expected)) return false;
            }
            // A fresh join acquires its name locks before an AD GUID exists. The later bound GUID does not
            // rewrite that initial intention; other mutation kinds always had an observed object identity.
            else if (!Text(root, "Kind", out var kind) || kind != "join") return false;
            return true;
        }
        catch (Exception error) when (error is PestoException or JsonException or InvalidOperationException or ArgumentException or FormatException)
        { return false; }
    }

    // ---- registre d'interventions V1 (port de Read-PestoIntervention pour l'affichage) -----------------

    private static HistoryEntry ReadV1(string path, string folder, string gpRoot)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.Length is < 1 or > MaximumFileBytes || (info.Attributes & FileAttributes.ReparsePoint) != 0) return Unreadable(path);
            var bytes = File.ReadAllBytes(path);
            var entry = ParseV1Snapshot(path, bytes, new DateTimeOffset(info.LastWriteTimeUtc, TimeSpan.Zero));
            return entry.Readable && ReceiptAcknowledgementStore.TryReadForReceipt(gpRoot, path, bytes) is not null
                ? entry with { Acknowledged = true } : entry;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return Unreadable(path); }
    }

    internal static HistoryEntry ParseV1Snapshot(string path, ReadOnlyMemory<byte> bytes, DateTimeOffset lastWriteUtc)
    {
        var fileName = Path.GetFileName(path);
        var root = ParseObjectSnapshot(bytes);
        if (root is null) return Unreadable(path);
        if (!Closed(root.Value, V1Fields, V1Required)) return Unreadable(path);
        if (root.Value.TryGetProperty("Schema", out var schema) && (schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var schemaValue) || schemaValue is < 1 or > 3)) return Unreadable(path);
        if (!Text(root.Value, "OperationId", out var operationId) || !Guid.TryParse(operationId, out var parsed) || parsed == Guid.Empty) return Unreadable(path);
        if (!Path.GetFileNameWithoutExtension(fileName).Equals(parsed.ToString("N"), StringComparison.OrdinalIgnoreCase)) return Unreadable(path); // le fichier est nommé d'après l'opération (BaseName v1) : aucune identité croisée
        if (!Text(root.Value, "Phase", out var phase) || !V1Phases.Contains(phase, StringComparer.Ordinal)) return Unreadable(path);
        if (!EnumValue(root.Value, "Entra", V1Entra) || !EnumValue(root.Value, "Protection", V1Protection) || !EnumValue(root.Value, "Rename", V1Effect) || !EnumValue(root.Value, "Move", V1Effect)) return Unreadable(path);
        if (!Integer(root.Value, "ResultCode", out var code)) return Unreadable(path);
        if (root.Value.TryGetProperty("InitialProtection", out var initial) && initial.ValueKind is not (JsonValueKind.True or JsonValueKind.False or JsonValueKind.Null)) return Unreadable(path);
        if (!root.Value.TryGetProperty("Plan", out var plan) || plan.ValueKind != JsonValueKind.Object) return Unreadable(path);
        if (!Closed(plan, V1PlanFields, V1PlanRequired)) return Unreadable(path);
        var attributeKind = AttributeMutationRules.IsV1Attributes(root.Value);
        if (!AttributeMutationRules.ReceiptMetadataIsValid(root.Value, legacy: true)) return Unreadable(path);
        if (!attributeKind && (plan.TryGetProperty("Action", out _) || plan.TryGetProperty("Changes", out _) || plan.TryGetProperty("Metadata", out _))) return Unreadable(path);
        if (!Text(plan, "Nom_du_PC", out var computer) || !ComputerName.IsMatch(computer)) return Unreadable(path);
        if (!Text(plan, "Domain", out var domain) || !DnsName.IsMatch(domain) || domain.Length > 253) return Unreadable(path);
        if (!Flag(plan, "Renommer", out var rename) || !Flag(plan, "Deplacer", out var move)) return Unreadable(path);
        foreach (var name in new[] { "Nouveau_Nom", "OU_Actuelle", "OU_Destination", "Objet_GUID", "DC", "ConfigStamp", "TargetOUGuid", "Reference" })
            if (plan.TryGetProperty(name, out var value) && value.ValueKind != JsonValueKind.Null && (value.ValueKind != JsonValueKind.String || value.GetString()!.Length > 4096 || value.GetString()!.Any(char.IsControl))) return Unreadable(path);
        if (plan.TryGetProperty("Reference", out var reference) && reference.ValueKind == JsonValueKind.String && reference.GetString()!.Length > 120) return Unreadable(path);
        if (!TimelineIsValid(root.Value)) return Unreadable(path);
        if (!TasksAreValid(root.Value)) return Unreadable(path);
        if (!CoordinationIsValid(root.Value, parsed)) return Unreadable(path);
        if (root.Value.TryGetProperty("OfflineJoin", out var offline) && offline.ValueKind != JsonValueKind.Null &&
            !(offline.ValueKind == JsonValueKind.String && new[] { "Requested", "PendingRestart", "Uncertain", "Verified" }.Contains(offline.GetString(), StringComparer.Ordinal))) return Unreadable(path);
        if (root.Value.TryGetProperty("Attributes", out var attributes) && attributes.ValueKind != JsonValueKind.Null &&
            !(attributes.ValueKind == JsonValueKind.String && new[] { "NotRequested", "Requested", "Confirmed", "Uncertain" }.Contains(attributes.GetString(), StringComparer.Ordinal))) return Unreadable(path);
        var acknowledged = StoredMutationBarrier.IsAcknowledged(root.Value);
        var newName = plan.TryGetProperty("Nouveau_Nom", out var nn) && nn.ValueKind == JsonValueKind.String ? nn.GetString() ?? "" : "";
        var targetOu = plan.TryGetProperty("OU_Destination", out var ou) && ou.ValueKind == JsonValueKind.String ? ou.GetString() ?? "" : "";
        if (!Time(root.Value, "UpdatedUtc", out var utc) && !Time(root.Value, "StartedUtc", out utc))
            utc = lastWriteUtc; // observed timestamp supplied with the same snapshot
        var status = phase switch
        {
            "Verified" => "succeeded",
            "Failed" => "refused",
            "PendingRestart" => "pendingRestart",
            _ => "uncertain", // Running, Partial, MoveReady, Uncertain : à vérifier avant toute reprise
        };
        var kind = attributeKind ? "attributes" : (rename, move) switch { (true, true) => "renameMove", (true, false) => "rename", (false, true) => "move", _ => "join" };
        var message = root.Value.TryGetProperty("ResultMessage", out var m) && m.ValueKind == JsonValueKind.String ? m.GetString() ?? "" : "";
        if (acknowledged) message = (message.Length > 0 ? message + " · " : "") + "acquittée (le reçu garde son état réel ; aucune commande lancée par l’acquittement)";
        var receipt = new Receipt(parsed.ToString("N"), utc, kind, computer, newName, targetOu, "V1 · registre local GP (relu, lecture seule)", status, code, message, phase == "PendingRestart");
        return new HistoryEntry(receipt, true, acknowledged);
    }

    // ---- pièces validées du reçu V1 (port des gardes de Read-PestoIntervention) --------------------------

    private static bool TimelineIsValid(JsonElement root)
    {
        if (!root.TryGetProperty("Timeline", out var timeline) || timeline.ValueKind == JsonValueKind.Null) return true;
        if (timeline.ValueKind != JsonValueKind.Array || timeline.GetArrayLength() > 96) return false;
        long last = 0;
        foreach (var item in timeline.EnumerateArray())
        {
            if (item.ValueKind == JsonValueKind.Null) continue;
            if (!Closed(item, ["Sequence", "Utc", "Stage", "State"], ["Sequence", "Utc", "Stage", "State"])) return false;
            if (!Integer(item, "Sequence", out var sequence) || sequence <= last) return false;
            if (!Text(item, "Utc", out var utc) || !DateTimeOffset.TryParse(utc, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out _)) return false;
            if (!Text(item, "Stage", out var stage) || stage.Length > 200) return false;
            if (!Text(item, "State", out var state) || state.Length > 4096) return false;
            last = sequence;
        }
        return true;
    }

    private static bool TasksAreValid(JsonElement root)
    {
        if (!root.TryGetProperty("Tasks", out var tasks) || tasks.ValueKind == JsonValueKind.Null) return true;
        if (tasks.ValueKind != JsonValueKind.Array || tasks.GetArrayLength() > 8) return false;
        foreach (var item in tasks.EnumerateArray())
        {
            if (item.ValueKind == JsonValueKind.Null) continue;
            if (!Closed(item, ["Computer", "Name", "Phase", "Hash", "NativeCode", "Utc"], ["Computer", "Name", "Phase", "Hash"])) return false;
            if (!Text(item, "Computer", out var computer) || !ComputerName.IsMatch(computer)) return false;
            if (!Text(item, "Name", out var name) || !TaskName.IsMatch(name)) return false;
            if (!Text(item, "Phase", out var phase) || !new[] { "Registering", "Registered", "StartRequested", "Started", "Finished", "Deleted" }.Contains(phase, StringComparer.Ordinal)) return false;
            if (item.TryGetProperty("Hash", out var hash) && hash.ValueKind != JsonValueKind.Null &&
                !(hash.ValueKind == JsonValueKind.String && Hash64.IsMatch(hash.GetString()!))) return false;
        }
        return true;
    }

    private static bool CoordinationIsValid(JsonElement root, Guid operationId)
    {
        if (!root.TryGetProperty("Coordination", out var coordination) || coordination.ValueKind == JsonValueKind.Null) return true;
        if (coordination.ValueKind != JsonValueKind.Object) return false;
        if (!Closed(coordination, ["Enabled", "Keys", "Owner", "ResumeFrom"], ["Enabled", "Keys", "Owner"])) return false;
        if (coordination.TryGetProperty("Enabled", out var enabled) && enabled.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
        if (!Text(coordination, "Owner", out var owner) || !owner.Equals(operationId.ToString("N"), StringComparison.OrdinalIgnoreCase)) return false;
        if (!coordination.TryGetProperty("Keys", out var keys) || keys.ValueKind != JsonValueKind.Array || keys.GetArrayLength() > 3) return false;
        foreach (var key in keys.EnumerateArray())
            if (key.ValueKind != JsonValueKind.String || !Hash64.IsMatch(key.GetString()!)) return false;
        return true;
    }

    // ---- primitives de lecture (aucune écriture, aucun fichier traversé deux fois) ----------------------

    private static JsonElement? ParseObjectSnapshot(ReadOnlyMemory<byte> bytes)
    {
        try
        {
            if (bytes.Length == 0 || bytes.Length > MaximumFileBytes) return null;
            using var memory = new MemoryStream(bytes.ToArray());
            using var reader = new StreamReader(memory, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            var text = reader.ReadToEnd();
            using var document = JsonDocument.Parse(text, new JsonDocumentOptions { AllowTrailingCommas = false, CommentHandling = JsonCommentHandling.Disallow });
            if (document.RootElement.ValueKind != JsonValueKind.Object) return null;
            return document.RootElement.Clone();
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static HistoryEntry Unreadable(string path) => new(
        new Receipt("invalid:" + Path.GetFileName(path), DateTimeOffset.UnixEpoch, "inconnu", Path.GetFileName(path), "", "", "GP", "unreadable", 0,
            "Reçu illisible ou invalide. Faites contrôler ce fichier par le support. Aucun verrou levé.", false), false, false);

    private static bool Closed(JsonElement value, string[] allowed, string[]? required = null)
    {
        if (value.ValueKind != JsonValueKind.Object) return false;
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in value.EnumerateObject())
            if (!allowed.Contains(property.Name, StringComparer.Ordinal) || !names.Add(property.Name)) return false;
        if (required is not null) foreach (var key in required) if (!names.Contains(key)) return false;
        return true;
    }

    private static bool Text(JsonElement value, string name, out string text)
    {
        text = "";
        if (!value.TryGetProperty(name, out var property) || property.ValueKind != JsonValueKind.String) return false;
        text = property.GetString()!;
        return text.Length > 0 && !text.Any(char.IsControl);
    }

    private static bool OptionalText(JsonElement value, string name, out string? text)
    {
        text = null;
        if (!value.TryGetProperty(name, out var property) || property.ValueKind == JsonValueKind.Null) return true;
        if (property.ValueKind != JsonValueKind.String) return false;
        text = property.GetString();
        return true;
    }

    private static bool Integer(JsonElement value, string name, out int number)
    {
        number = 0;
        return value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.Number && property.TryGetInt32(out number);
    }

    private static bool Flag(JsonElement value, string name, out bool flag)
    {
        flag = false;
        if (!value.TryGetProperty(name, out var property)) return true; // absent = défaut v1 rendu par l'appelant
        if (property.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
        flag = property.GetBoolean();
        return true;
    }

    private static bool EnumValue(JsonElement value, string name, string[] allowed)
    {
        if (!value.TryGetProperty(name, out var property) || property.ValueKind != JsonValueKind.String) return false;
        return allowed.Contains(property.GetString(), StringComparer.Ordinal);
    }

    private static bool Time(JsonElement value, string name, out DateTimeOffset utc)
    {
        utc = default;
        return value.TryGetProperty(name, out var property) && property.ValueKind == JsonValueKind.String
            && DateTimeOffset.TryParse(property.GetString(), System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out utc);
    }

    private static string Short(string message)
    {
        var trimmed = new string(message.Where(c => !char.IsControl(c)).ToArray()).Trim();
        return trimmed.Length > 200 ? trimmed[..200] + "…" : trimmed;
    }
}

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Reads each source once and passes exactly those bytes to the history validator. Related V1
/// copies are covered by the same event; no old receipt is rewritten merely to release a V2 barrier.</summary>
public static class ReceiptAcknowledgementSource
{
    public const int MaximumBytes = 131072;
    private static readonly string[] Eligible = ["Running", "PendingRestart", "Partial", "MoveReady", "Protection", "Uncertain"];
    internal static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = false };

    public static ReceiptAcknowledgementSnapshot Read(string gpRoot, string receiptId)
    {
        RequireId(receiptId);
        RequirePlainPath(gpRoot);
        var v2 = ReceiptPath(gpRoot, "adapter", receiptId);
        var canonical = Guid.TryParse(receiptId, out var operation) && operation != Guid.Empty ? operation.ToString("N") : receiptId;
        var ledger = ReceiptPath(gpRoot, "intervention", canonical);
        if (File.Exists(v2) && File.Exists(ledger)) throw Refused("Deux registres portent cette identité : aucun acquittement ambigu.");
        var records = new List<(ReceiptAcknowledgementTarget Target, Receipt Receipt, bool Acknowledged, bool Entra)>();
        if (File.Exists(v2)) records.Add(ReadTarget(gpRoot, "adapter", receiptId));
        else
        {
            if (File.Exists(ledger)) records.Add(ReadTarget(gpRoot, "intervention", canonical));
            foreach (var kind in new[] { "direct", "join" })
            {
                var path = ReceiptPath(gpRoot, kind, canonical);
                if (!File.Exists(path)) continue;
                var bytes = ReadBytes(path);
                using var document = ParseObject(bytes);
                if (!Guid.TryParse(Text(document.RootElement, "OperationId"), out var related) || related == Guid.Empty)
                    throw Refused("Un reçu V1 local ne permet pas de vérifier son identité : aucun acquittement partiel.");
                if (related != operation) continue;
                var target = ParseLegacy(kind, canonical, bytes, new FileInfo(path).LastWriteTimeUtc);
                if (records.Count == 0 || IsEligible(target.Target.Phase)) records.Add(target);
            }
        }
        if (records.Count == 0) throw Refused("Ce reçu durable n’existe pas dans le registre local.");
        var first = records[0];
        if (records.Any(item => !Same(item.Target.Domain, first.Target.Domain) || !Same(item.Target.Computer, first.Target.Computer)
            || !Same(item.Target.NewName, first.Target.NewName)))
            throw Refused("Les copies de ce reçu ne désignent pas la même opération : aucune levée de barrière.");
        var targets = records.Select(item => item.Target).OrderBy(item => item.Store, StringComparer.Ordinal).ToArray();
        return new(first.Receipt, first.Target.Domain, targets, Digest(JsonSerializer.SerializeToUtf8Bytes(targets)),
            ReadTaskProofSha256(gpRoot, first.Target.ReceiptId), records.All(item => item.Acknowledged), records.Any(item => item.Entra));
    }

    internal static (ReceiptAcknowledgementTarget Target, Receipt Receipt, bool Acknowledged, bool Entra) ReadTarget(
        string gpRoot, string store, string receiptId)
    {
        var path = ReceiptPath(gpRoot, store, receiptId);
        var bytes = ReadBytes(path);
        var modified = new DateTimeOffset(new FileInfo(path).LastWriteTimeUtc, TimeSpan.Zero);
        if (store is "direct" or "join") return ParseLegacy(store, receiptId, bytes, modified);
        var entry = store == "adapter" ? GpHistory.ParseAdapterSnapshot(path, bytes, modified)
            : GpHistory.ParseV1Snapshot(path, bytes, modified);
        if (!entry.Readable) throw Refused("Le schéma du reçu durable n’est pas validé : aucun acquittement.");
        if (entry.Receipt.Kind == "offlineJoin")
            throw Refused("La jonction hors connexion conserve ses preuves et sa barrière dédiées. Ouvrez Pesto.exe --offline-join ; aucun acquittement général ne peut autoriser un nouveau passage du blob.");
        using var document = ParseObject(bytes);
        var root = document.RootElement;
        var domain = store == "adapter" ? Text(root, "Domain") : Text(root.GetProperty("Plan"), "Domain");
        if (!IsDomain(domain)) throw Refused("Le domaine du reçu n’est pas confirmé.");
        RequireInlineAcknowledgement(root);
        RequireTerminalInlineTasks(root);
        var code = ReadCode(root, store == "adapter" ? "Code" : "ResultCode", required: true);
        var target = new ReceiptAcknowledgementTarget(store, entry.Receipt.Id, Digest(bytes), Text(root, "Phase")!, code,
            entry.Receipt.Computer, entry.Receipt.NewName, domain!, null);
        return (target, entry.Receipt, entry.Acknowledged, NeedsEntraInspection(root));
    }

    private static (ReceiptAcknowledgementTarget Target, Receipt Receipt, bool Acknowledged, bool Entra) ParseLegacy(
        string store, string receiptId, byte[] bytes, DateTimeOffset modified)
    {
        using var document = ParseObject(bytes);
        var root = document.RootElement;
        string[] fields = store == "join"
            ? ["Schema", "Version", "OperationId", "Phase", "Utc", "MachineId", "BootUtc", "Computer", "NewName", "Domain", "OU", "DC", "Reference", "Account", "Message", "Metadata", "Acknowledged"]
            : ["Schema", "Version", "OperationId", "OperatorMachineId", "LocalSource", "TargetMachineId", "Phase", "StartedUtc", "FinishedUtc", "ObservedUtc", "Plan", "ResultCode", "ResultMessage", "ResumeFrom", "Metadata", "Acknowledged"];
        Closed(root, fields, ["Schema", "OperationId", "Phase"]);
        if (!root.GetProperty("Schema").TryGetInt32(out var schema) || schema != 1
            || !Guid.TryParse(Text(root, "OperationId"), out var operation) || operation == Guid.Empty || operation.ToString("N") != receiptId)
            throw Refused("Identité du reçu historique invalide.");
        var phase = Text(root, "Phase") ?? throw Refused("Phase historique absente.");
        if (!IsEligible(phase) && phase is not ("Failed" or "Verified" or "NotStarted")) throw Refused("Phase historique inconnue.");
        string computer, name, domain, ou, machine, kind;
        int? code;
        if (store == "join")
        {
            computer = Text(root, "Computer") ?? ""; name = Text(root, "NewName") ?? "";
            domain = Text(root, "Domain") ?? ""; ou = Text(root, "OU") ?? "";
            machine = Text(root, "MachineId") ?? ""; kind = "join"; code = null;
            if (!DateTimeOffset.TryParse(Text(root, "Utc"), out var utc) || !DateTimeOffset.TryParse(Text(root, "BootUtc"), out var boot) || boot > utc)
                throw Refused("Les preuves de démarrage du reçu historique sont invalides.");
        }
        else
        {
            if (!root.TryGetProperty("Plan", out var plan)) throw Refused("Plan historique absent.");
            string[] planFields = ["Metadata", "Nom_du_PC", "Nouveau_Nom", "OU_Actuelle", "OU_Destination", "Objet_GUID", "TargetOUGuid", "Domain", "DC", "ConfigStamp", "Renommer", "Deplacer", "Reboot", "InitialProtection", "Reference"];
            Closed(plan, planFields, ["Nom_du_PC", "Objet_GUID", "Domain", "Renommer", "Deplacer"]);
            computer = Text(plan, "Nom_du_PC") ?? ""; name = Text(plan, "Nouveau_Nom") ?? "";
            domain = Text(plan, "Domain") ?? ""; ou = Text(plan, "OU_Destination") ?? "";
            machine = Text(root, "OperatorMachineId") ?? "";
            if (!Guid.TryParse(Text(plan, "Objet_GUID"), out var guid) || guid == Guid.Empty
                || plan.GetProperty("Renommer").ValueKind is not (JsonValueKind.True or JsonValueKind.False)
                || plan.GetProperty("Deplacer").ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw Refused("L’identité ou le type de l’opération historique est invalide.");
            kind = plan.GetProperty("Renommer").GetBoolean() ? plan.GetProperty("Deplacer").GetBoolean() ? "renameMove" : "rename" : "move";
            code = ReadCode(root, "ResultCode", required: true);
        }
        if (!IsComputer(computer) || name.Length > 0 && !IsComputer(name) || !IsDomain(domain)
            || !Guid.TryParse(machine, out var machineGuid) || machineGuid == Guid.Empty || ou.Length > 4096 || ou.Any(char.IsControl))
            throw Refused("La portée du reçu historique n’est pas confirmée.");
        RequireInlineAcknowledgement(root);
        var status = phase == "Verified" ? "succeeded" : phase is "Failed" or "NotStarted" ? "refused" : phase == "PendingRestart" ? "pendingRestart" : "uncertain";
        var receipt = new Receipt(receiptId, modified, kind, computer, name, ou, "live · reçu historique V1", status,
            code ?? (phase == "PendingRestart" ? 10 : 97), Text(root, store == "join" ? "Message" : "ResultMessage") ?? "Reçu historique conservé.", phase == "PendingRestart");
        return (new(store, receiptId, Digest(bytes), phase, code, computer, name, domain, machineGuid.ToString("D")),
            receipt, StoredMutationBarrier.IsAcknowledged(root), false);
    }

    public static string ReadTaskProofSha256(string gpRoot, string receiptId)
    {
        RequireId(receiptId);
        var folder = Path.Combine(gpRoot, "V2", "tasks"); RequirePlainPath(folder);
        if (!Directory.Exists(folder)) return Digest("[]");
        var all = Directory.EnumerateFiles(folder, "*.json", SearchOption.TopDirectoryOnly).Take(5001).ToArray();
        if (all.Length > 5000) throw Refused("Trop de preuves de tâches pour confirmer l’absence d’activité.");
        var proofs = new List<KeyValuePair<string, string>>();
        foreach (var path in all.OrderBy(Path.GetFileName, StringComparer.Ordinal))
        {
            var name = Path.GetFileName(path);
            if (!name.StartsWith(receiptId + ".", StringComparison.OrdinalIgnoreCase)) continue;
            if (!Regex.IsMatch(name[(receiptId.Length + 1)..], "^[a-f0-9]{12}\\.json$", RegexOptions.CultureInvariant))
                throw Refused("Une preuve de tâche porte une identité invalide.");
            var bytes = ReadBytes(path);
            using var document = ParseObject(bytes);
            var root = document.RootElement;
            Closed(root, ["Schema", "Version", "Kind", "Computer", "TaskName", "Phases"], ["Schema", "Version", "Kind", "Phases"]);
            if (!root.GetProperty("Schema").TryGetInt32(out var schema) || schema != 1 || Text(root, "Version") != "2.0"
                || Text(root, "Kind") is not ("task-fallback-evidence" or "entra-status-evidence" or "windows-proof-evidence" or "restart-request-evidence"))
                throw Refused("Type de preuve de tâche inconnu : aucun acquittement.");
            if (Text(root, "Computer") is { } computer && !IsComputer(computer)
                || Text(root, "TaskName") is { } task && !TaskFallback.IsPestoTaskName(task))
                throw Refused("Identité de tâche invalide.");
            var phases = root.GetProperty("Phases");
            if (phases.ValueKind != JsonValueKind.Array || phases.GetArrayLength() is < 1 or > 2048) throw Refused("Journal de tâche incomplet.");
            string? last = null;
            foreach (var phase in phases.EnumerateArray())
            {
                Closed(phase, ["Phase", "Utc", "Hash", "NativeCode"], ["Phase", "Utc", "Hash", "NativeCode"]);
                last = Text(phase, "Phase");
                if (last is not ("Registering" or "Registered" or "StartRequested" or "Started" or "Finished" or "Deleted" or "DeleteFailed" or "ResultSaved" or "ResultDeleted")
                    || !DateTimeOffset.TryParse(Text(phase, "Utc"), out _)
                    || Text(phase, "Hash") is not { } hash || hash.Length > 0 && !IsHash(hash)
                    || phase.GetProperty("NativeCode").ValueKind != JsonValueKind.Null && !phase.GetProperty("NativeCode").TryGetInt64(out _))
                    throw Refused("Le journal de tâche contient une preuve invalide.");
                if (last is "Finished" or "Deleted" && !IsHash(hash)) throw Refused("La définition de la tâche terminée n’est pas prouvée.");
            }
            if (last is not ("Finished" or "Deleted")) throw Refused("Une tâche Windows peut encore agir. Confirmez explicitement sa fin avant d’acquitter.");
            proofs.Add(new(name, Digest(bytes)));
        }
        return Digest(JsonSerializer.SerializeToUtf8Bytes(proofs));
    }

    private static void RequireTerminalInlineTasks(JsonElement root)
    {
        if (!root.TryGetProperty("Tasks", out var tasks) || tasks.ValueKind == JsonValueKind.Null) return;
        if (tasks.ValueKind != JsonValueKind.Array || tasks.GetArrayLength() > 8) throw Refused("Preuves de tâches historiques invalides.");
        foreach (var task in tasks.EnumerateArray())
            if (Text(task, "Phase") is not ("Finished" or "Deleted")) throw Refused("Une tâche historique peut encore agir : aucun acquittement.");
    }

    private static bool NeedsEntraInspection(JsonElement root) => Text(root, "Entra") is "Requested" or "Uncertain";
    private static void RequireInlineAcknowledgement(JsonElement root)
    {
        if (!root.TryGetProperty("Acknowledged", out var ack) || ack.ValueKind == JsonValueKind.Null) return;
        // A structurally valid but stale V1 acknowledgement may be replaced by a new, explicitly confirmed event.
        if (ack.ValueKind != JsonValueKind.Object || !ack.TryGetProperty("Phase", out var phase) || !ack.TryGetProperty("ResultCode", out var code))
            throw Refused("L’acquittement historique est altéré.");
        var wrapper = new JsonObject { ["Phase"] = JsonNode.Parse(phase.GetRawText()), ["ResultCode"] = JsonNode.Parse(code.GetRawText()), ["Acknowledged"] = JsonNode.Parse(ack.GetRawText()) };
        using var check = JsonDocument.Parse(wrapper.ToJsonString());
        if (!StoredMutationBarrier.IsAcknowledged(check.RootElement)) throw Refused("L’acquittement historique n’a pas un schéma valide.");
    }

    public static string ReceiptPath(string gpRoot, string store, string receiptId)
    {
        RequireId(receiptId);
        var relative = store switch
        {
            "adapter" => Path.Combine("V2", "receipts", receiptId + ".json"),
            "intervention" => Path.Combine("Interventions", receiptId + ".json"),
            "direct" => Path.Combine("Operations", "direct.json"),
            "join" => Path.Combine("Join", "receipt.json"),
            _ => throw Refused("Emplacement de reçu non déclaré.")
        };
        var path = Path.Combine(Path.GetFullPath(gpRoot), relative); RequirePlainPath(path); return path;
    }

    internal static byte[] ReadBytes(string path)
    {
        RequirePlainPath(path);
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (file.Length is < 1 or > MaximumBytes) throw Refused("Reçu absent ou trop volumineux.");
        var bytes = new byte[checked((int)file.Length)]; file.ReadExactly(bytes); return bytes;
    }
    internal static JsonDocument ParseObject(ReadOnlyMemory<byte> bytes)
    {
        var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 64 });
        try { if (document.RootElement.ValueKind != JsonValueKind.Object) throw Refused("Objet JSON attendu."); RequireUniqueKeys(document.RootElement); return document; }
        catch { document.Dispose(); throw; }
    }
    private static void RequireUniqueKeys(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var item in value.EnumerateObject()) { if (!names.Add(item.Name)) throw Refused("Clé JSON dupliquée."); RequireUniqueKeys(item.Value); }
        }
        else if (value.ValueKind == JsonValueKind.Array) foreach (var item in value.EnumerateArray()) RequireUniqueKeys(item);
    }
    internal static void Closed(JsonElement value, string[] allowed, string[] required)
    {
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Any(p => !allowed.Contains(p.Name, StringComparer.Ordinal))
            || required.Any(name => !value.TryGetProperty(name, out _))) throw Refused("Schéma fermé incomplet ou champ inconnu.");
    }
    internal static string? Text(JsonElement value, string key)
    {
        if (!value.TryGetProperty(key, out var item) || item.ValueKind == JsonValueKind.Null) return null;
        if (item.ValueKind != JsonValueKind.String || item.GetString()!.Any(char.IsControl)) throw Refused("Texte de preuve invalide.");
        return item.GetString();
    }
    private static int? ReadCode(JsonElement root, string key, bool required)
    {
        if (!root.TryGetProperty(key, out var value)) { if (required) throw Refused("Code du reçu absent."); return null; }
        if (value.ValueKind == JsonValueKind.Null) return null;
        if (!value.TryGetInt32(out var code)) throw Refused("Code du reçu non typé."); return code;
    }
    public static bool IsEligible(string phase) => Eligible.Contains(phase, StringComparer.Ordinal);
    internal static bool IsHash(string? value) => value is { Length: 64 } && value.All(Uri.IsHexDigit);
    internal static bool IsComputer(string? value) => value is not null && Regex.IsMatch(value, "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$", RegexOptions.CultureInvariant);
    internal static bool IsDomain(string? value) => value is { Length: > 0 and <= 253 } && Regex.IsMatch(value, "^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", RegexOptions.CultureInvariant);
    internal static bool Same(string? a, string? b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
    internal static void RequireId(string? id)
    {
        if (id is null || !Regex.IsMatch(id, "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", RegexOptions.CultureInvariant) || id.EndsWith('.')) throw Refused("Identifiant de reçu invalide.");
    }
    public static string Digest(byte[] value) => Convert.ToHexString(SHA256.HashData(value)).ToLowerInvariant();
    public static string Digest(string value) => Digest(Encoding.UTF8.GetBytes(value));
    public static void RequirePlainPath(string path)
    {
        for (string? item = Path.GetFullPath(path); item is not null; item = Path.GetDirectoryName(item))
            if ((File.Exists(item) || Directory.Exists(item)) && (File.GetAttributes(item) & FileAttributes.ReparsePoint) != 0)
                throw Refused("Le registre d’acquittement ne peut pas traverser un lien ou une jonction.");
    }
    internal static PestoException Refused(string message) => new("receipt.acknowledgement", message);
}

using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Immutable acknowledgement events. A valid event releases only the exact receipt bytes and
/// finished-task inventory it covered. It never rewrites an operation or a continuation link.</summary>
public sealed class ReceiptAcknowledgementStore(string gpRoot, Action<string>? secureDirectory = null)
{
    public const string EventKind = "pesto.receipt-acknowledgement";
    private readonly string gpRoot = Path.GetFullPath(gpRoot);

    public ReceiptAcknowledgementEvidence Append(ReceiptAcknowledgementSnapshot snapshot,
        ReceiptAcknowledgementContext context, string reason, DateTimeOffset now)
    {
        reason = ValidateReason(reason);
        var fresh = ReceiptAcknowledgementSource.Read(gpRoot, snapshot.Receipt.Id);
        if (fresh.TargetsSha256 != snapshot.TargetsSha256 || fresh.TaskProofSha256 != snapshot.TaskProofSha256)
            throw ReceiptAcknowledgementSource.Refused("Le reçu ou ses tâches ont changé avant l’écriture : préparez et confirmez à nouveau.");
        var record = new ReceiptAcknowledgementEvent(1, EventKind, "ack-" + Guid.NewGuid().ToString("N"), snapshot.Receipt.Id,
            now.ToUniversalTime(), context.Author, reason, snapshot.Targets.ToArray(), snapshot.TargetsSha256,
            snapshot.TaskProofSha256, context.EntraEvidenceSha256, context.ConfigurationSha256, context.WorkerProof);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(record, ReceiptAcknowledgementSource.JsonOptions);
        _ = Parse(bytes);
        var path = EventPath(gpRoot, record.ReceiptId, record.Id);
        var folder = Path.GetDirectoryName(path)!;
        ReceiptAcknowledgementSource.RequirePlainPath(folder); Directory.CreateDirectory(folder);
        ReceiptAcknowledgementSource.RequirePlainPath(folder);
        secureDirectory?.Invoke(Path.GetDirectoryName(folder)!); secureDirectory?.Invoke(folder);
        var pins = new List<FileStream>();
        string? temporary = null;
        try
        {
            // FileShare.Read forbids replacement/deletion on Windows until the event is durable.
            foreach (var target in record.Targets)
            {
                var source = ReceiptAcknowledgementSource.ReceiptPath(gpRoot, target.Store, target.ReceiptId);
                var pin = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read);
                pins.Add(pin);
                if (pin.Length is < 1 or > ReceiptAcknowledgementSource.MaximumBytes) throw ReceiptAcknowledgementSource.Refused("Reçu non protégeable.");
                var current = new byte[checked((int)pin.Length)]; pin.ReadExactly(current);
                if (ReceiptAcknowledgementSource.Digest(current) != target.ReceiptSha256)
                    throw ReceiptAcknowledgementSource.Refused("Un reçu a changé pendant la préparation de son événement.");
            }
            if (ReceiptAcknowledgementSource.ReadTaskProofSha256(gpRoot, record.ReceiptId) != record.TaskProofSha256)
                throw ReceiptAcknowledgementSource.Refused("Les preuves de tâches ont changé avant l’écriture.");
            temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { output.Write(bytes); output.Flush(flushToDisk: true); }
            ReceiptAcknowledgementSource.RequirePlainPath(path);
            File.Move(temporary, path, overwrite: false); temporary = null;
            var reread = ReceiptAcknowledgementSource.ReadBytes(path);
            if (!reread.AsSpan().SequenceEqual(bytes)) throw new IOException("La relecture de l’événement ne correspond pas à l’écriture.");
            return new(record.Id, record.ReceiptId, ReceiptAcknowledgementSource.Digest(reread), record.TargetsSha256, Parse(reread));
        }
        finally
        {
            foreach (var pin in pins) pin.Dispose();
            if (temporary is not null && File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public ReceiptAcknowledgementEvidence? ReadApplied(string receiptId)
    {
        var folder = Path.GetDirectoryName(EventPath(gpRoot, receiptId, "ack-" + Guid.NewGuid().ToString("N")))!;
        if (!Directory.Exists(folder)) return null;
        ReceiptAcknowledgementSource.RequirePlainPath(folder);
        var files = Directory.EnumerateFiles(folder, "*.json", SearchOption.TopDirectoryOnly).Take(65).ToArray();
        if (files.Length > 64) throw ReceiptAcknowledgementSource.Refused("Trop d’événements pour ce reçu : lecture administrative nécessaire.");
        var events = new List<ReceiptAcknowledgementEvidence>();
        foreach (var path in files)
        {
            var bytes = ReceiptAcknowledgementSource.ReadBytes(path); var record = Parse(bytes);
            if (record.ReceiptId != receiptId || Path.GetFileName(path) != record.Id + ".json")
                throw ReceiptAcknowledgementSource.Refused("Un événement ne correspond pas à son emplacement.");
            var evidence = new ReceiptAcknowledgementEvidence(record.Id, receiptId, ReceiptAcknowledgementSource.Digest(bytes), record.TargetsSha256, record);
            if (ValidateApplied(gpRoot, evidence)) events.Add(evidence);
        }
        return events.OrderByDescending(item => item.Event.Utc).ThenByDescending(item => item.EventId, StringComparer.Ordinal).FirstOrDefault();
    }

    /// <summary>Pure local revalidation used before shared-lock cleanup. No receipt, task or effect is rewritten.</summary>
    public static bool ValidateApplied(string gpRoot, ReceiptAcknowledgementEvidence evidence)
    {
        try
        {
            var bytes = ReceiptAcknowledgementSource.ReadBytes(EventPath(gpRoot, evidence.ReceiptId, evidence.EventId));
            if (ReceiptAcknowledgementSource.Digest(bytes) != evidence.EventSha256) return false;
            var record = Parse(bytes);
            if (record.Id != evidence.EventId || record.ReceiptId != evidence.ReceiptId || record.TargetsSha256 != evidence.TargetsSha256
                || !JsonSerializer.SerializeToUtf8Bytes(record).AsSpan().SequenceEqual(JsonSerializer.SerializeToUtf8Bytes(evidence.Event))) return false;
            var snapshot = ReceiptAcknowledgementSource.Read(gpRoot, evidence.ReceiptId);
            return snapshot.TargetsSha256 == record.TargetsSha256 && snapshot.TaskProofSha256 == record.TaskProofSha256;
        }
        catch (Exception) { return false; }
    }

    /// <summary>History/native-barrier projection over the same bytes already read by the caller.</summary>
    public static ReceiptAcknowledgementEvidence? TryReadForReceipt(string gpRoot, string path, ReadOnlyMemory<byte> bytes)
    {
        try
        {
            using var document = ReceiptAcknowledgementSource.ParseObject(bytes);
            var root = document.RootElement;
            var id = ReceiptAcknowledgementSource.Text(root, "ReceiptId");
            if (id is null && Guid.TryParse(ReceiptAcknowledgementSource.Text(root, "OperationId"), out var operation) && operation != Guid.Empty) id = operation.ToString("N");
            if (id is null) return null;
            var evidence = new ReceiptAcknowledgementStore(gpRoot).ReadApplied(id);
            if (evidence is null) return null;
            var full = Path.GetFullPath(path);
            var hash = ReceiptAcknowledgementSource.Digest(bytes.ToArray());
            return evidence.Event.Targets.Any(target => target.ReceiptSha256 == hash
                && string.Equals(ReceiptAcknowledgementSource.ReceiptPath(gpRoot, target.Store, target.ReceiptId), full,
                    OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal)) ? evidence : null;
        }
        catch (Exception) { return null; }
    }

    public static string ValidateReason(string reason)
    {
        if (reason is null || reason.Length > 500 || reason.Any(char.IsControl))
            throw ReceiptAcknowledgementSource.Refused("Le motif doit tenir sur une ligne et contenir entre 3 et 500 caractères.");
        var text = reason.Trim();
        if (text.Length < 3) throw ReceiptAcknowledgementSource.Refused("Indiquez un motif d’acquittement de 3 caractères au moins.");
        return text;
    }

    private static string EventPath(string gpRoot, string receiptId, string eventId)
    {
        ReceiptAcknowledgementSource.RequireId(receiptId);
        if (!eventId.StartsWith("ack-", StringComparison.Ordinal) || eventId.Length != 36
            || !Guid.TryParseExact(eventId[4..], "N", out var id) || id == Guid.Empty) throw ReceiptAcknowledgementSource.Refused("Identité d’événement invalide.");
        var path = Path.Combine(Path.GetFullPath(gpRoot), "V2", "acknowledgements", receiptId, eventId + ".json");
        ReceiptAcknowledgementSource.RequirePlainPath(path); return path;
    }

    private static ReceiptAcknowledgementEvent Parse(byte[] bytes)
    {
        using var document = ReceiptAcknowledgementSource.ParseObject(bytes);
        string[] fields = ["Schema", "Kind", "Id", "ReceiptId", "Utc", "By", "Reason", "Targets", "TargetsSha256", "TaskProofSha256", "EntraEvidenceSha256", "ConfigurationSha256", "WorkerProof"];
        var root = document.RootElement; ReceiptAcknowledgementSource.Closed(root, fields, fields);
        var targets = root.GetProperty("Targets");
        if (targets.ValueKind != JsonValueKind.Array || targets.GetArrayLength() is < 1 or > 3) throw ReceiptAcknowledgementSource.Refused("Portée d’événement invalide.");
        string[] targetFields = ["Store", "ReceiptId", "ReceiptSha256", "Phase", "Code", "Computer", "NewName", "Domain", "LocalMachineId"];
        foreach (var target in targets.EnumerateArray()) ReceiptAcknowledgementSource.Closed(target, targetFields, targetFields);
        string[] workerFields = ["MachineId", "ObservedUtc", "Clear", "Method"];
        ReceiptAcknowledgementSource.Closed(root.GetProperty("WorkerProof"), workerFields, workerFields);
        var record = JsonSerializer.Deserialize<ReceiptAcknowledgementEvent>(bytes, ReceiptAcknowledgementSource.JsonOptions)
            ?? throw ReceiptAcknowledgementSource.Refused("Événement illisible.");
        _ = EventPath(Path.GetTempPath(), record.ReceiptId, record.Id); // validates identities, never writes
        if (record.Schema != 1 || record.Kind != EventKind || record.Utc.Offset != TimeSpan.Zero
            || string.IsNullOrWhiteSpace(record.By) || record.By.Length > 256 || record.By.Any(char.IsControl)
            || ValidateReason(record.Reason) != record.Reason || record.WorkerProof is null || !record.WorkerProof.Clear
            || !Guid.TryParse(record.WorkerProof.MachineId, out var machine) || machine == Guid.Empty
            || record.WorkerProof.Method != "local-process-snapshot" || record.WorkerProof.ObservedUtc.Offset != TimeSpan.Zero
            || record.WorkerProof.ObservedUtc > record.Utc || record.Utc - record.WorkerProof.ObservedUtc > TimeSpan.FromSeconds(30))
            throw ReceiptAcknowledgementSource.Refused("Auteur, date, motif ou preuve de fin d’activité invalide.");
        if (new[] { record.TargetsSha256, record.TaskProofSha256, record.EntraEvidenceSha256, record.ConfigurationSha256 }.Any(hash => !ReceiptAcknowledgementSource.IsHash(hash))
            || record.TargetsSha256 != ReceiptAcknowledgementSource.Digest(JsonSerializer.SerializeToUtf8Bytes(record.Targets)))
            throw ReceiptAcknowledgementSource.Refused("Empreinte de l’événement invalide.");
        var stores = new HashSet<string>(StringComparer.Ordinal);
        foreach (var target in record.Targets)
        {
            if (target.Store is not ("adapter" or "intervention" or "direct" or "join") || !stores.Add(target.Store)
                || target.ReceiptId != record.ReceiptId || !ReceiptAcknowledgementSource.IsHash(target.ReceiptSha256)
                || !ReceiptAcknowledgementSource.IsEligible(target.Phase) || !ReceiptAcknowledgementSource.IsComputer(target.Computer)
                || target.NewName.Length > 0 && !ReceiptAcknowledgementSource.IsComputer(target.NewName) || !ReceiptAcknowledgementSource.IsDomain(target.Domain)
                || target.LocalMachineId is not null && (!Guid.TryParse(target.LocalMachineId, out var local) || local == Guid.Empty))
                throw ReceiptAcknowledgementSource.Refused("Cible d’acquittement invalide.");
            var first = record.Targets[0];
            if (!ReceiptAcknowledgementSource.Same(first.Computer, target.Computer) || !ReceiptAcknowledgementSource.Same(first.NewName, target.NewName)
                || !ReceiptAcknowledgementSource.Same(first.Domain, target.Domain)) throw ReceiptAcknowledgementSource.Refused("Identités d’événement divergentes.");
        }
        return record;
    }
}

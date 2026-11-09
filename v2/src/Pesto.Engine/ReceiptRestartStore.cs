using System.Text.Json;

namespace Pesto.Engine;

public sealed record RestartJournalEntry(int Schema, RestartCommand Command, string Status, DateTimeOffset Utc, string Message);

/// <summary>Append-only request and result, separate from the unchanged business receipt. Callers hold the GP mutex.</summary>
public sealed class ReceiptRestartStore(string gpRoot, Action<string>? protectJournal = null)
{
    private readonly string folder = Path.Combine(gpRoot, "V2", "restarts");

    public RestartJournalEntry? ReadLatest(string receiptId, string receiptSha256)
    {
        if (!RemoteWindowsEvidenceProtocol.IsId(receiptId) || !RemoteWindowsEvidenceProtocol.IsHash(receiptSha256))
            throw ReceiptRestartRules.Refused("Identité de reçu invalide.");
        if (!Directory.Exists(folder)) return null;
        SharedCoordinationProtocol.RequireNoLinks(folder);
        var paths = Directory.EnumerateFiles(folder, "*.requested.json").Take(5001).ToArray();
        if (paths.Length > 5000) throw ReceiptRestartRules.Refused("Trop de demandes de redémarrage.");
        RestartJournalEntry? latest = null;
        foreach (var path in paths)
        {
            var requested = Read(path);
            if (requested.Status != "requested") throw ReceiptRestartRules.Refused("Intention de redémarrage incohérente.");
            if (requested.Command.ReceiptId != receiptId || !RemoteWindowsEvidenceProtocol.Same(requested.Command.ReceiptSha256, receiptSha256)) continue;
            var finalPath = Path.Combine(folder, requested.Command.Id + ".final.json");
            RestartJournalEntry value;
            try { value = File.Exists(finalPath) ? Read(finalPath) : requested; }
            catch (Exception) { value = requested with { Status = "uncertain", Message = "Réponse finale illisible ; demande initiale conservée." }; }
            if (value.Command != requested.Command || value.Status is not ("requested" or "accepted" or "refused" or "uncertain"))
                throw ReceiptRestartRules.Refused("Résultat de redémarrage incohérent.");
            if (latest is null || value.Utc >= latest.Utc) latest = value;
        }
        return latest;
    }

    public void RequireNoPriorRequest(string machineId, DateTimeOffset boot)
    {
        if (!Directory.Exists(folder)) return;
        SharedCoordinationProtocol.RequireNoLinks(folder);
        var paths = Directory.EnumerateFiles(folder, "*.requested.json").Take(5001).ToArray();
        if (paths.Length > 5000) throw ReceiptRestartRules.Refused("Trop de demandes de redémarrage à relire ; aucun nouvel envoi.");
        foreach (var path in paths)
        {
            var requested = Read(path);
            if (requested.Status != "requested") throw ReceiptRestartRules.Refused("Journal de redémarrage incohérent ; aucun nouvel envoi.");
            if (!RemoteWindowsEvidenceProtocol.Same(requested.Command.MachineId, machineId) || requested.Command.BootUtc != boot) continue;
            var final = Path.Combine(folder, requested.Command.Id + ".final.json");
            if (File.Exists(final))
            {
                var ended = Read(final);
                if (ended.Command != requested.Command || ended.Status is not ("accepted" or "refused" or "uncertain"))
                    throw ReceiptRestartRules.Refused("Résultat de redémarrage incohérent ; aucun nouvel envoi.");
                if (ended.Status == "refused") continue; // Only a native proof of zero send permits a new plan.
            }
            throw ReceiptRestartRules.Refused("Une demande de redémarrage existe déjà pour cette identité et ce boot. Vérifiez le poste et son reçu ; aucun second envoi.");
        }
    }

    public void Requested(RestartCommand command)
    {
        ReceiptRestartRules.ValidateCommand(command);
        RequireNoPriorRequest(command.MachineId, command.BootUtc);
        Save(command.Id + ".requested.json", new(1, command, "requested", command.RequestedUtc,
            "Demande explicite durable avant action ; redémarrage non encore confirmé."));
    }

    public void Finished(RestartCommand command, RestartNativeResult result, DateTimeOffset utc)
    {
        if (result.Status is not ("accepted" or "refused" or "uncertain")) throw new IOException("Statut de redémarrage invalide.");
        var initial = Read(Path.Combine(folder, command.Id + ".requested.json"));
        if (initial.Command != command || initial.Status != "requested") throw new IOException("Demande initiale différente.");
        Save(command.Id + ".final.json", new(1, command, result.Status, utc, result.Message));
    }

    private void Save(string name, RestartJournalEntry entry)
    {
        if (!Path.IsPathFullyQualified(gpRoot) || gpRoot.StartsWith(@"\\", StringComparison.Ordinal)) throw new IOException("Registre local requis.");
        SharedCoordinationProtocol.RequireNoLinks(folder); Directory.CreateDirectory(folder); protectJournal?.Invoke(folder);
        var path = Path.Combine(folder, name); SharedCoordinationProtocol.RequireNoLinks(path);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(entry);
        if (bytes.Length > 16384) throw new IOException("Demande de redémarrage hors limites.");
        using var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
        file.Write(bytes); file.Flush(true);
    }

    private static RestartJournalEntry Read(string path)
    {
        try
        {
            SharedCoordinationProtocol.RequireNoLinks(path);
            using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (file.Length is < 1 or > 16384) throw new IOException();
            using var document = JsonDocument.Parse(file); var root = document.RootElement;
            RemoteWindowsEvidenceProtocol.RequireClosed(root, ["Schema", "Command", "Status", "Utc", "Message"]);
            RemoteWindowsEvidenceProtocol.RequireClosed(root.GetProperty("Command"), ["Id", "ReceiptId", "ReceiptSha256", "PlanId", "Computer", "ConfiguredName", "Domain", "ComputerGuid", "MachineId", "BootUtc", "LocalTarget", "RequestedUtc", "OperationKind", "AllowPendingJoin", "InitialWindowsDomain", "InitialDomainRole", "AuthorizationConfigurationSha256"]);
            var entry = root.Deserialize<RestartJournalEntry>() ?? throw new IOException();
            ReceiptRestartRules.ValidateCommand(entry.Command);
            if (entry.Schema != 1 || entry.Utc == default || entry.Utc.Offset != TimeSpan.Zero || entry.Message.Length > 2048
                || !Path.GetFileName(path).StartsWith(entry.Command.Id + ".", StringComparison.Ordinal)) throw new IOException();
            return entry;
        }
        catch (Exception) { throw ReceiptRestartRules.Refused("Preuve de redémarrage illisible : aucun nouvel envoi."); }
    }
}

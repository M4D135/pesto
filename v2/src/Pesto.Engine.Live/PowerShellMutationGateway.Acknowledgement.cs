using System.Security.Principal;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IMutationReceiptAcknowledgement
{
    private ReceiptAcknowledgementCoordinator? acknowledgements;
    private ReceiptAcknowledgementCoordinator Acknowledgements => acknowledgements ??= new(ReceiptGpRoot(),
        ReadAcknowledgementContext, secureDirectory: folder => { if (OperatingSystem.IsWindows()) RestrictToSystemAndAdmins(folder); });

    public ReceiptAcknowledgementPreparation PrepareAcknowledgement(string receiptId, string planId) =>
        WithAcknowledgementMutex(() => Acknowledgements.Prepare(receiptId, planId));

    public ReceiptAcknowledgementResult Acknowledge(ReceiptAcknowledgementAuthorization authorization, string reason) =>
        WithAcknowledgementMutex(() =>
        {
            var result = Acknowledgements.Acknowledge(authorization, reason);
            // Cleanup is secondary to the durable operator decision. It never changes the original receipt.
            ReleaseAcknowledgedCoordination(ReceiptGpRoot(), result.Evidence, ReleaseCoordinationAfterAcknowledgement);
            return result;
        });

    private static void ReleaseAcknowledgedCoordination(string gpRoot, ReceiptAcknowledgementEvidence evidence,
        Action<string, string, ReceiptAcknowledgementEvidence> release)
    {
        // The V1 direct copy has no Coordination; its intervention ledger owns the lock evidence.
        var target = evidence.Event.Targets.FirstOrDefault(item => item.Store == "adapter")
            ?? evidence.Event.Targets.FirstOrDefault(item => item.Store == "intervention")
            ?? evidence.Event.Targets.First();
        release(ReceiptAcknowledgementSource.ReceiptPath(gpRoot, target.Store, target.ReceiptId), target.ReceiptId, evidence);
    }

    private T WithAcknowledgementMutex<T>(Func<T> operation)
    {
        ReceiptAcknowledgementAdmission.RequireSession(Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1",
            unavailableReason is null, unavailableReason);
        if (!OperatingSystem.IsWindows()) throw new PestoException("receipt.acknowledgement_unavailable", "L’acquittement natif exige Windows.");
        bool elevated;
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            elevated = new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch (Exception) { elevated = false; }
        if (!elevated) throw new PestoException("receipt.acknowledgement_unavailable", "L’élévation locale n’est pas confirmée : aucun acquittement natif.");
        using var mutex = new Mutex(false, PostMutationMutexName);
        var owned = false;
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw new PestoException("receipt.acknowledgement", "Une mutation détient encore le verrou GP : aucun acquittement.");
            if (v1InstallationPath is null) throw new PestoException("receipt.acknowledgement", "Configuration absente.");
            var path = Path.Combine(v1InstallationPath, "cfg.json"); RequireNoReparsePoint(path);
            using var configuration = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (configuration.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw new PestoException("receipt.acknowledgement", "Configuration illisible.");
            using var reader = new StreamReader(configuration, System.Text.Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
            ReceiptAcknowledgementAdmission.RequireConfiguration(reader.ReadToEnd());
            return operation();
        }
        finally { if (owned) mutex.ReleaseMutex(); }
    }

    private ReceiptAcknowledgementContext ReadAcknowledgementContext(ReceiptAcknowledgementSnapshot snapshot)
    {
        if (!OperatingSystem.IsWindows()) throw new PestoException("receipt.acknowledgement", "Auteur Windows indisponible.");
        var policy = ReadReservationPolicy();
        var stamp = ReservationConfigurationStamp();
        var reservationsResolved = !ReservationRegistry.List().Any(item => !JoinReservationStore.IsTerminal(item.Receipt.State));
        RequireLegacyReservationResolved();
        var entra = ReadEntraBarrier(snapshot.Receipt.Id);
        var worker = WindowsAcknowledgementActivity.Read();
        using var identity = WindowsIdentity.GetCurrent();
        return new(policy.Domain, stamp, identity.Name, worker, reservationsResolved, entra.CanAcknowledge,
            entra.EvidenceSha256, entra.CanAcknowledge ? null : entra.Reason);
    }

    private void RequireLegacyReservationResolved()
    {
        var path = Path.Combine(ReceiptGpRoot(), "Join", "ad-reservation.json");
        if (!File.Exists(path)) return;
        using var document = System.Text.Json.JsonDocument.Parse(ReadReceiptBytes(path));
        var root = document.RootElement;
        string[] fields = ["Schema", "OperationId", "MachineId", "Mode", "Name", "Guid", "OU", "DC", "Domain", "State", "Outcome", "NeedsReview", "Message", "UpdatedUtc"];
        if (root.ValueKind != System.Text.Json.JsonValueKind.Object
            || root.EnumerateObject().Any(item => !fields.Contains(item.Name, StringComparer.Ordinal))
            || root.EnumerateObject().Select(item => item.Name).Distinct(StringComparer.Ordinal).Count() != root.EnumerateObject().Count()
            || !root.TryGetProperty("Schema", out var schema) || schema.ValueKind != System.Text.Json.JsonValueKind.Number || schema.GetInt32() != 1
            || !Guid.TryParse(SavedText(root, "OperationId"), out var operation) || operation == Guid.Empty
            || !Guid.TryParse(SavedText(root, "MachineId"), out var machine) || machine == Guid.Empty
            || SavedText(root, "Mode") is not ("Reserve" or "Release" or "Inspect")
            || !IsComputerName(SavedText(root, "Name")) || !JoinClockGuard.IsServer(SavedText(root, "DC"))
            || !JoinClockGuard.IsServer(SavedText(root, "Domain")) || SavedText(root, "OU") is not { Length: > 0 and <= 4096 } ou
            || ou.Any(char.IsControl) || SavedDate(root, "UpdatedUtc") is null
            || SavedText(root, "Guid") is { Length: > 0 } account && (!Guid.TryParse(account, out var accountId) || accountId == Guid.Empty)
            || SavedFlag(root, "NeedsReview") is not { } review)
            throw new PestoException("receipt.acknowledgement", "Le reçu de réservation AD V1 est illisible : aucune barrière levée.");
        var state = SavedText(root, "State");
        if (review || state is "Released" or "Consumed" && !Guid.TryParse(SavedText(root, "Guid"), out _)
            || state is not ("Released" or "Gone" or "Taken" or "Consumed")
            && !(state == "Failed" && SavedFlag(root, "NeedsReview") == false))
            throw new PestoException("receipt.acknowledgement", "Une réservation AD V1 conservée doit être inspectée : l’acquittement ne la résout pas.");
    }

    /// <summary>Called before ordinary receipt barriers, but never before/around ReservationBarrier.</summary>
    private bool HasAppliedAcknowledgement(string path, ReadOnlyMemory<byte> bytes)
    {
        var evidence = ReceiptAcknowledgementStore.TryReadForReceipt(ReceiptGpRoot(), path, bytes);
        if (evidence is null) return false;
        try
        {
            var entra = ReadEntraBarrier(evidence.ReceiptId);
            return entra.CanAcknowledge && entra.EvidenceSha256 == evidence.Event.EntraEvidenceSha256;
        }
        catch (Exception) { return false; }
    }
}

using Pesto.Core;
using System.Text.Json;

namespace Pesto.Engine;

/// <summary>One immutable receipt covered by an acknowledgement. Store is a closed logical location,
/// never a browser supplied path. Its complete byte hash binds phase, code, effects and all parent links.</summary>
public sealed record ReceiptAcknowledgementTarget(string Store, string ReceiptId, string ReceiptSha256,
    string Phase, int? Code, string Computer, string NewName, string Domain, string? LocalMachineId);

public sealed record ReceiptAcknowledgementWorkerProof(string MachineId, DateTimeOffset ObservedUtc,
    bool Clear, string Method);

/// <summary>Separate from the operation receipt: an acknowledgement is an operator decision, not a success.</summary>
public sealed record ReceiptAcknowledgementEvent(int Schema, string Kind, string Id, string ReceiptId,
    DateTimeOffset Utc, string By, string Reason, IReadOnlyList<ReceiptAcknowledgementTarget> Targets,
    string TargetsSha256, string TaskProofSha256, string EntraEvidenceSha256, string ConfigurationSha256,
    ReceiptAcknowledgementWorkerProof WorkerProof);

public sealed record ReceiptAcknowledgementEvidence(string EventId, string ReceiptId, string EventSha256,
    string TargetsSha256, ReceiptAcknowledgementEvent Event);

public sealed record ReceiptAcknowledgementSnapshot(Receipt Receipt, string Domain,
    IReadOnlyList<ReceiptAcknowledgementTarget> Targets, string TargetsSha256, string TaskProofSha256,
    bool AlreadyAcknowledged, bool NeedsEntraInspection);

/// <summary>Fresh facts supplied by the native host while holding the immediate GP mutex.
/// A fixture can provide these facts to test the coordinator without Windows, AD or a process.</summary>
public sealed record ReceiptAcknowledgementContext(string Domain, string ConfigurationSha256,
    string Author, ReceiptAcknowledgementWorkerProof WorkerProof, bool ReservationsResolved,
    bool EntraCanAcknowledge, string EntraEvidenceSha256, string? Refusal = null);

/// <summary>Retained by reference in the native coordinator. It never crosses the web bridge.</summary>
public sealed record ReceiptAcknowledgementAuthorization(string Token, string PlanId, string ReceiptId,
    string TargetsSha256, string TaskProofSha256, string EntraEvidenceSha256, string ConfigurationSha256,
    string Computer, string NewName, string Domain, string Phase, int? Code, string ConfirmationName,
    DateTimeOffset ExpiresAt);

public sealed record ReceiptAcknowledgementPreparation(ReceiptAcknowledgementSnapshot Snapshot,
    ReceiptAcknowledgementAuthorization Authorization);

public sealed record ReceiptAcknowledgementResult(Receipt Receipt, ReceiptAcknowledgementEvidence Evidence);

public interface IMutationReceiptAcknowledgement
{
    ReceiptAcknowledgementPreparation PrepareAcknowledgement(string receiptId, string planId);
    ReceiptAcknowledgementResult Acknowledge(ReceiptAcknowledgementAuthorization authorization, string reason);
}

/// <summary>An acknowledgement is a durable operator decision. Consultation/demo are forbidden;
/// IncidentMode forbids new mutations, but deliberately does not forbid this V1 decision.</summary>
public static class ReceiptAcknowledgementAdmission
{
    public static void RequireSession(bool readOnly, bool adapterAvailable, string? unavailableReason = null)
    {
        if (readOnly) throw new PestoException("receipt.acknowledgement_readonly", "L’acquittement est interdit en consultation : aucun reçu ni événement modifié.");
        if (!adapterAvailable) throw new PestoException("receipt.acknowledgement_unavailable",
            unavailableReason ?? "L’adaptateur natif n’est pas disponible : aucun acquittement.");
    }

    public static void RequireConfiguration(string json)
    {
        _ = V1Config.ValidateText(json);
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("DEBUG", out var debug) || debug.ValueKind != JsonValueKind.Object) return;
        foreach (var key in new[] { "Simulation", "GUI" })
            if (debug.TryGetProperty(key, out var flag) && (flag.ValueKind == JsonValueKind.True
                || flag.ValueKind == JsonValueKind.String && string.Equals(flag.GetString()!.Trim(), "true", StringComparison.OrdinalIgnoreCase)))
                throw new PestoException("receipt.acknowledgement_readonly", "L’acquittement est interdit avec DEBUG.Simulation ou DEBUG.GUI : aucun reçu réel modifié.");
    }
}

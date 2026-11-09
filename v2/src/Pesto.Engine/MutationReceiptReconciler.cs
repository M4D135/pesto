using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Fresh read-only observations of one durable mutation receipt, bound to its hash.
/// Missing facts remain null. LocalTarget describes the saved target, MachineIdentityMatches compares its saved Windows identity.</summary>
public sealed record ReceiptReconciliationObservation(
    Receipt Receipt, string ReceiptSha256, string? ExpectedGuid, string Domain,
    DateTimeOffset? InitialBootUtc, DateTimeOffset? CurrentBootUtc,
    string? AdGuid, string? AdName, string? AdOu, string? InitialOu,
    bool? InitialProtected, bool? AdProtected,
    string? WindowsActiveName, string? WindowsConfiguredName, string? WindowsDomain,
    bool? WindowsPartOfDomain, bool? SecureChannel, bool LocalTarget, bool MachineIdentityMatches,
    string? Error, RemoteWindowsProof? RemoteWindowsProof = null);

/// <summary>Explicit receipt verification only: never replays a mutation, repairs state or restarts Windows.</summary>
public interface IMutationReceiptReconciler
{
    ReceiptReconciliationObservation ReadReconciliation(string receiptId);
    /// <summary>Called only after the engine validates all evidence. Recheck ReceiptSha256 under mutex,
    /// persist Verified with RestartRequired=false and the evidence; throw on any conflict or persistence failure.</summary>
    void PersistReconciliation(ReceiptReconciliationObservation observation);
}

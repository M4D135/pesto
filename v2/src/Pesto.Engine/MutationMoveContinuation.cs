namespace Pesto.Engine;

/// <summary>In-memory single-use authority for only the remaining move of one code-89 renameMove receipt.
/// Never exposed through the web bridge. Native execution rechecks the parent hash and all identities under the GP mutex.</summary>
public sealed record MoveContinuationAuthorization(string Token, string ParentReceiptId, string ParentReceiptSha256,
    string PlanId, string Computer, string ComputerGuid, string SourceOu, string TargetOu, string TargetOuGuid, DateTimeOffset ExpiresAt);

/// <summary>Fresh factual proof plus the exact expiring authorization; the engine independently validates both.</summary>
public sealed record MoveContinuationPreparation(ReceiptReconciliationObservation Observation,
    MoveContinuationAuthorization Authorization, string? ObservedTargetOuGuid);

public interface IMutationMoveContinuation
{
    /// <summary>Prepare only, never modify AD or reboot. May persist the parent's observed Partial state.
    /// Refuse other barriers, resolved parents, or an already active child. The observation hash must match the returned authorization.</summary>
    MoveContinuationPreparation PrepareMoveContinuation(string parentReceiptId, string planId);
}

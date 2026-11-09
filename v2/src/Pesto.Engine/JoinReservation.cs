namespace Pesto.Engine;

/// <summary>A local, durable account-creation receipt. It is separate from every join receipt and never
/// contains a credential, an ACL, a browser supplied path, or an instruction to replay a mutation.</summary>
public sealed record JoinReservationReceipt(
    int Schema, string Id, string OperationId, string ParentReceiptId, string[] JoinReceiptIds,
    string Computer, string Name, string Domain, string Dc, string TargetOu, string TargetOuGuid,
    string MachineId, string Marker, string? ComputerGuid, string State, bool NeedsReview, string Message,
    DateTimeOffset CreatedUtc, DateTimeOffset UpdatedUtc, int Revision = 1,
    DateTimeOffset? InspectedUtc = null, string? CurrentComputer = null, DateTimeOffset? CurrentBootUtc = null,
    bool JoinAttempted = false, DateTimeOffset? LastJoinBootUtc = null,
    JoinReservationParent[]? ResolvedParents = null);

public sealed record JoinReservationParent(string ReceiptId, string Sha256);

/// <summary>Evidence returned by a fixed native worker. Absence is true only for an AD identity-not-found
/// response from the receipt's exact DC; failed reads never mean absence.</summary>
public sealed record JoinReservationObservation(
    string MachineId, string CurrentComputer, string Domain, string Dc, DateTimeOffset BootUtc,
    bool PartOfDomain, bool PendingRename, bool DomainController,
    bool Absent, string? ComputerGuid, string? Name, string? DistinguishedName, string? Marker,
    string? DnsHostName, string[] ServicePrincipalNames, string TargetOuGuid, string? Error = null);

public sealed record JoinReservationNativeResult(string State, string Message,
    JoinReservationObservation? Observation = null, bool MutationMayHaveStarted = false);

/// <summary>The native implementation is fixed and is called only after a durable pending receipt.
/// Read must not mutate AD or Windows; Create/Remove must independently check the immutable tuple.</summary>
public interface IJoinReservationNative
{
    JoinReservationObservation Read(JoinReservationReceipt receipt);
    JoinReservationNativeResult Create(JoinReservationReceipt receipt);
    JoinReservationNativeResult Remove(JoinReservationReceipt receipt);
}

public sealed record JoinReservationView(JoinReservationReceipt Receipt, bool CanResume, bool CanRelease);

/// <summary>Native, expiring, single-use authority. Never serialize this object to the web bridge.
/// A matching string token alone is insufficient: the gateway retains the exact grant in memory.</summary>
public sealed record JoinReservationAuthorization(
    string Token, string ReservationId, string ReservationSha256, string PlanId, string Action,
    string Computer, string Name, string Domain, string Dc, string TargetOu, string TargetOuGuid,
    string MachineId, string? ComputerGuid, string Marker, DateTimeOffset ExpiresAt,
    IReadOnlyList<JoinReservationParent> Parents, string ConfigurationSha256);

public sealed record JoinReservationPreparation(JoinReservationView Reservation, JoinReservationAuthorization Authorization);

public interface IMutationJoinReservation
{
    /// <summary>Local files only. It must not contact AD, a share, or HTTP.</summary>
    IReadOnlyList<JoinReservationView> ListReservations();
    /// <summary>Explicit native inspection, with no account creation, deletion, join or repair.</summary>
    JoinReservationView InspectReservation(string reservationId);
    JoinReservationPreparation PrepareReservation(string reservationId, string action, string planId);
    JoinReservationView ReleaseReservation(JoinReservationAuthorization authorization);
}

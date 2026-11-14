using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Observed by the native host before the lazy adapter factory. Contains no credential or reusable secret.</summary>
public sealed record AutomationHostContext(string ConfigurationDirectory, string ProfileSid, string OperatorSid,
    string MachineId, string ComputerName, string GpRoot, bool AlreadyElevated, bool ExplicitCredentialAvailable,
    bool? OperatorDomainJoined = null, Action<string>? SecureDirectory = null, Func<MutationManagedPolicy>? ManagedPolicyReader = null);

/// <summary>Portable reviewed intent. Integrity is a consistency hash, never a signature or a permission grant.</summary>
public sealed record AutomationPlan(int Schema, string Purpose, string Action, DateTimeOffset CreatedUtc, DateTimeOffset ExpiresUtc,
    string ProfileSid, string OperatorSid, string MachineId, string ConfigurationIdentitySha256, string ConfigurationSha256,
    string Domain, string Dc, string Computer, string NewName, string? ComputerGuid, string? SourceOu, string TargetOu,
    string? TargetOuGuid, string? Type, string? SiteCode, string? ServiceCode, string? TargetMachineId,
    string? EntraState, string? EntraPolicy, bool EntraLeaveRequired, IReadOnlyDictionary<string, string> Metadata, string Integrity);

/// <summary>Transient preparation token, held by reference in LiveBackend; it is never exported in Plan or a receipt.</summary>
public sealed record AutomationPreparation(string Token, AutomationPlan Plan, DateTimeOffset ExpiresAt);

/// <summary>One durable CLI intent linked to one business receipt, validated again under the GP mutex.</summary>
public sealed record AutomationExecutionAuthorization(string KeyHash, string PayloadSha256, string RequestSha256,
    string ReceiptId, AutomationPlan Plan, string ProfileSid, string OperatorSid, string MachineId,
    bool EntraLeaveConfirmed, string? ApprovalJson);

public interface IPestoAutomationBackend
{
    AutomationPreparation PrepareAutomation(PestoCliOptions options, AutomationHostContext context,
        IReadOnlyDictionary<string, string> metadata, AutomationPlan? expected = null, AutomationExecutionAuthorization? execution = null);
    Receipt ExecuteAutomation(AutomationPreparation preparation, AutomationExecutionAuthorization execution);
}

/// <summary>Closed result safe for stdout and the durable idempotency registry. Raw native objects/logs are never included.</summary>
public sealed record PestoCliResult(int Schema, string Mode, string State, int ExitCode, int? EngineCode,
    bool RestartRequired, bool MutationStarted, string? OperationId, DateTimeOffset Utc, string Message,
    AutomationPlan? Plan = null, IReadOnlyDictionary<string, string>? Metadata = null, bool Replayed = false,
    JsonObject? Observation = null);

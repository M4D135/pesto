using System.Globalization;
using System.Text.Json;

namespace Pesto.Engine;

/// <summary>The exact, closed V1 EventLog projection. No target, account, path, free text or secret is exported.</summary>
public sealed record ReceiptAuditEvent(int Schema, string Product, string OperationId, string Kind, string State,
    int? ResultCode, int? Sequence, string UpdatedUtc)
{
    private static readonly string[] Phases = ["Running", "Failed", "PendingRestart", "Partial", "MoveReady", "Protection", "Uncertain", "NotStarted", "Verified"];

    /// <summary>V2 stores one durable receipt per action. Its GUID is the operation identity; it has no invented sequence.</summary>
    public static ReceiptAuditEvent? FromV2Receipt(JsonElement receipt)
    {
        static string? Text(JsonElement value, string name) => value.TryGetProperty(name, out var item)
            && item.ValueKind == JsonValueKind.String ? item.GetString() : null;
        if (receipt.ValueKind != JsonValueKind.Object
            || !receipt.TryGetProperty("Schema", out var schema) || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1
            || Text(receipt, "Version") != "2.0") return null;
        var id = Text(receipt, "ReceiptId");
        if (id is null || !id.StartsWith("receipt-", StringComparison.Ordinal) || id.Length != 40
            || !Guid.TryParseExact(id[8..], "N", out var guid) || guid == Guid.Empty) return null;
        var kind = Text(receipt, "Kind") switch { "join" => "Join", "rename" or "move" or "renameMove" => "Direct", "attributes" or "offlineJoin" => "Intervention", _ => null };
        var phase = Text(receipt, "Phase");
        var time = Text(receipt, "Utc");
        if (kind is null || phase is null || !Phases.Contains(phase, StringComparer.Ordinal)
            || !receipt.TryGetProperty("Code", out var code) || code.ValueKind != JsonValueKind.Number || !code.TryGetInt32(out var result)
            || time is null || time.Length > 40 || !DateTimeOffset.TryParseExact(time,
                ["yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'", "O"], CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal, out var observed) || observed.Offset != TimeSpan.Zero) return null;
        return new(1, "Pesto", guid.ToString("N"), kind, phase, result, null, observed.UtcDateTime.ToString("O", CultureInfo.InvariantCulture));
    }
}

public sealed record ReceiptAuditEmission(bool Confirmed, string? FailureCode = null);

/// <summary>Best effort EventLog write only. A failed audit never changes the durable operation result.</summary>
public interface IReceiptAuditSink
{
    ReceiptAuditEmission Write(ReceiptAuditEvent value);
}

public sealed record ReceiptAuditStatus(string State, DateTimeOffset? LastSuccessUtc, DateTimeOffset? LastFailureUtc,
    int Failures, string? FailureCode);

public interface IReceiptAuditDisclosure
{
    ReceiptAuditStatus AuditStatus { get; }
}

/// <summary>Pure orchestration: called only after a durable receipt write has returned successfully.</summary>
public sealed class ReceiptAuditTrail(IReceiptAuditSink sink, TimeProvider? clock = null)
{
    private readonly object gate = new();
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private ReceiptAuditStatus status = new("notAttempted", null, null, 0, null);
    public ReceiptAuditStatus Status { get { lock (gate) return status; } }

    public void AfterDurableReceipt(bool enabled, string receiptJson)
    {
        if (!enabled) return;
        lock (gate)
        {
            try
            {
                using var document = JsonDocument.Parse(receiptJson);
                var value = ReceiptAuditEvent.FromV2Receipt(document.RootElement);
                if (value is null) { Failed("audit.receipt_invalid"); return; }
                var result = sink.Write(value);
                if (!result.Confirmed) { Failed(ClosedFailure(result.FailureCode)); return; }
                status = status with { State = "confirmed", LastSuccessUtc = clock.GetUtcNow(), FailureCode = null };
            }
            catch (Exception) { Failed("audit.unavailable"); }
        }
    }

    public void Unavailable()
    {
        lock (gate) Failed("audit.configuration_unreadable");
    }

    private void Failed(string code) => status = status with
    {
        State = "failed", LastFailureUtc = clock.GetUtcNow(), Failures = (int)Math.Min(int.MaxValue, (long)status.Failures + 1), FailureCode = code
    };
    private static string ClosedFailure(string? code) => code is "audit.source_unavailable" or "audit.timeout" or "audit.platform_unavailable"
        or "audit.response_invalid" ? code : "audit.unavailable";
}

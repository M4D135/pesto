using System.Text.Json;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IReceiptAuditDisclosure
{
    private readonly ReceiptAuditTrail receiptAudit;
    public ReceiptAuditStatus AuditStatus => receiptAudit.Status;

    private void AuditDurableReceipt(string json)
    {
        // This secondary sink cannot invalidate a receipt, its hash, or a confirmed business outcome.
        try
        {
            using var document = JsonDocument.Parse(json);
            var requiredAtSend = document.RootElement.TryGetProperty("AuditEventLogEnabled", out var flag) && flag.ValueKind == JsonValueKind.True;
            receiptAudit.AfterDurableReceipt(requiredAtSend || ReadPolicyRequirements().AuditEventLogEnabled, json);
        }
        catch (Exception) { receiptAudit.Unavailable(); }
    }
}

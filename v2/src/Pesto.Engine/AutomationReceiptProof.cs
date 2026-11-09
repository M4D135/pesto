using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>One exact, locally pinned business receipt. Neither a cached exit code nor its hash alone proves the planned effect.</summary>
internal sealed class AutomationReceiptProof : IDisposable
{
    private readonly FileStream handle;
    public Receipt Receipt { get; }
    public string Sha256 { get; }

    private AutomationReceiptProof(FileStream handle, Receipt receipt, string sha256)
    { this.handle = handle; Receipt = receipt; Sha256 = sha256; }

    public static AutomationReceiptProof Pin(string gpRoot, string receiptId, AutomationPlan plan, DateTimeOffset now)
    {
        if (receiptId is not { Length: 40 } || !receiptId.StartsWith("receipt-", StringComparison.Ordinal)
            || !Guid.TryParseExact(receiptId[8..], "N", out _)) throw Invalid();
        var path = Path.Combine(gpRoot, "V2", "receipts", receiptId + ".json");
        SharedCoordinationProtocol.RequireNoLinks(path);
        var handle = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        try
        {
            if (handle.Length is < 1 or > 131072) throw Invalid();
            var bytes = new byte[checked((int)handle.Length)]; handle.ReadExactly(bytes);
            var durable = GpHistory.ParseAdapterSnapshot(path, bytes, now);
            if (!durable.Readable) throw Invalid();
            var receipt = durable.Receipt;
            using var doc = AutomationPlanRules.ParseObject(bytes);
            var root = doc.RootElement;
            if (receipt.Id != receiptId || receipt.Kind != plan.Action
                || !AutomationPlanRules.Same(receipt.Computer, plan.Computer)
                || !AutomationPlanRules.Same(receipt.TargetOU, plan.TargetOu)
                || (plan.Action == "move" ? !string.IsNullOrEmpty(receipt.NewName) : !AutomationPlanRules.Same(receipt.NewName, plan.NewName))
                || !Same(root, "Domain", plan.Domain) || !Same(root, "Dc", plan.Dc)
                || !Same(root, "ConfigurationSha256", plan.ConfigurationSha256)
                || !Same(root, "TargetOuGuid", plan.TargetOuGuid)
                || plan.ComputerGuid is not null && !Same(root, "ComputerGuid", plan.ComputerGuid)
                || plan.SourceOu is not null && !Same(root, "InitialOu", plan.SourceOu)
                || plan.TargetMachineId is not null && !Same(root, "MachineId", plan.TargetMachineId)
                || plan.Action == "join" && !Same(root, "MachineId", plan.MachineId)) throw Invalid();
            // A receipt cannot add a leave which was absent from the exported, approved intent.
            if (root.TryGetProperty("Entra", out var entra) && entra.ValueKind == JsonValueKind.String
                && (entra.GetString() is "Requested" or "Uncertain"
                    || entra.GetString() == "Confirmed" && !plan.EntraLeaveRequired)) throw Invalid();
            return new(handle, receipt, AutomationPlanRules.Digest(bytes));
        }
        catch { handle.Dispose(); throw; }
    }

    public void RequireResult(PestoCliResult result)
    {
        if (result.OperationId != Receipt.Id || result.EngineCode != Receipt.Code || result.RestartRequired != Receipt.RestartRequired
            || result.ExitCode == 0 && (result.State != "Verified" || Receipt.Status != "succeeded"
                || Receipt.Code is not (30 or 33) || Receipt.RestartRequired || !result.MutationStarted)
            || result.ExitCode == 3010 && (result.State != "PendingRestart" || Receipt.Status != "pendingRestart"
                || Receipt.Code != (Receipt.Kind == "join" ? 10 : Receipt.Kind == "rename" ? 20 : Receipt.Kind == "renameMove" ? 77 : -1)
                || !Receipt.RestartRequired || !result.MutationStarted)) throw Invalid();
    }

    private static bool Same(JsonElement root, string name, string? expected) => root.TryGetProperty(name, out var value)
        && (expected is null ? value.ValueKind == JsonValueKind.Null
            : value.ValueKind == JsonValueKind.String && AutomationPlanRules.Same(value.GetString(), expected));
    private static IOException Invalid() => new("La preuve métier durable ne correspond plus à l'intention exacte ou au résultat annoncé.");
    public void Dispose() => handle.Dispose();
}

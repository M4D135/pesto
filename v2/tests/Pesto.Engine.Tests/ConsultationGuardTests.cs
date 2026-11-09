using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class ConsultationGuardTests
{
    private sealed class SharedIo : ISharedNameReservationFiles, ISharedCoordinationDeletion, ISharedCoordinationAccess
    {
        public int Calls;
        public SharedNameReservationCreation CreateNew(string path, byte[] bytes) { Calls++; throw new TestFailureException("No share mutation in consultation"); }
        public void RewriteExisting(string path, byte[] replacement, Func<byte[], bool> mayReplace) { Calls++; throw new TestFailureException("No lease renewal in consultation"); }
        public CoordinationDeletionResult DeleteExact(string path, string expectedSha256, int maximumBytes) { Calls++; throw new TestFailureException("No lease deletion in consultation"); }
        public T Run<T>(Func<T> operation) { Calls++; throw new TestFailureException("No credential context entered in consultation"); }
    }
    private static void ReadOnly(Action run)
    {
        var previous = Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION");
        try { Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", "1"); run(); }
        finally { Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", previous); }
    }

    [Test]
    public void DirectRecoveryApisRefuseBeforeProvidersAndPreservePureLocalLists()
    {
        using var w = new AutomationFixture(); var backend = w.Factory();
        ReadOnly(() =>
        {
            foreach (var operation in new[] { "receipts.reconcile", "receipts.prepareMove", "reservations.inspect", "reservations.prepare", "reservations.execute" })
            {
                object args = operation == "reservations.prepare" ? new { id = "unread", action = "release" }
                    : operation == "reservations.execute" ? new { planId = "unread", confirmationName = "unread" }
                    : new { id = "unread" };
                Check.Pesto(() => Harness.Call(backend, operation, args), "policy.readonly", "Direct API refuses before touching its native provider: " + operation);
            }
            var list = Harness.Call(backend, "receipts.list"); Check.NotNull(list, "Pure local history remains readable");
        });
        Check.Equal(0, w.Directory.Reads, "Recovery refusals do not contact the directory");
        Check.Equal(0, w.Native.Sends, "No operation sent"); Check.False(System.IO.Directory.Exists(w.Gp), "No recovery ledger fabricated");
    }

    [Test]
    public void NativeReconcileContinuationReservationAndLeaseApisRefuseBeforeAnyIo()
    {
        using var w = new AutomationFixture(); var native = new PowerShellMutationGateway(w.Configuration, receiptGpRoot: w.Gp);
        ReadOnly(() =>
        {
            Check.Pesto(() => native.ReadReconciliation("invalid"), "policy.readonly", "No remote task for reconciliation");
            Check.Pesto(() => { native.PersistReconciliation(null!); return null; }, "policy.readonly", "No durable reconciliation write");
            Check.Pesto(() => native.PrepareMoveContinuation("invalid", "invalid"), "policy.readonly", "No continuation record");
            Check.Pesto(() => native.InspectReservation("invalid"), "policy.readonly", "No reservation inspection that persists ownership");
            Check.Pesto(() => native.ReservePreviewName("invalid", "invalid", "invalid", "invalid"), "policy.readonly", "No lazy share adapter construction");
            Check.Pesto(() => { native.ReleasePreviewName(null!); return null; }, "policy.readonly", "No release from a direct managed call");
        });
        Check.False(System.IO.Directory.Exists(w.Gp), "All refusals happen before local/remote journal IO");
    }

    [Test]
    public void NameLeaseServiceRefusesCreateRenewAndDeleteBeforeCredentialsOrFiles()
    {
        using var w = new AutomationFixture(); var io = new SharedIo();
        var journal = Path.Combine(w.Root, "never-created");
        var service = new SharedNameReservationService(Path.Combine(w.Configuration, "cfg.json"), journal,
            SharedCoordinationAccessMode.Live, io, io, io, w.Clock);
        ReadOnly(() =>
        {
            Check.Pesto(() => service.ReservePreviewName("bad", "bad", "bad", "bad"), "policy.readonly", "Guard precedes even configuration/domain validation");
            Check.Pesto(() => { service.ReleasePreviewName(null!); return null; }, "policy.readonly", "Guard precedes native deletion context");
        });
        Check.Equal(0, io.Calls, "No file or credential provider called"); Check.False(System.IO.Directory.Exists(journal), "No local lease intent written");
    }

    [Test]
    public void ConsultationSwitchAfterCliExportRefusesBeforeFactoryOrStartedRecord()
    {
        using var w = new AutomationFixture(); w.Prepare(); var factories = w.Factories;
        ReadOnly(() => Check.Equal(96, w.Run(w.ExecuteOptions()).ExitCode, "Consultation is checked afresh for execute"));
        Check.Equal(factories, w.Factories, "No network factory after readonly switch");
        Check.Equal(0, w.Native.Sends, "No send from stale prepared context");
        Check.False(System.IO.Directory.Exists(Path.Combine(w.Gp, "V2", "automation"))
            && System.IO.Directory.EnumerateFiles(Path.Combine(w.Gp, "V2", "automation"), "*.request.json").Any(), "No Started after consultation refusal");
    }

    [Test]
    public void AttributeAndOfflineJoinAuditUseTheV1InterventionProjectionAcceptedByNativeSink()
    {
        foreach (var kind in new[] { "attributes", "offlineJoin" })
        {
            using var json = System.Text.Json.JsonDocument.Parse(System.Text.Json.JsonSerializer.Serialize(new
            { Schema = 1, Version = "2.0", ReceiptId = "receipt-11111111111111111111111111111111", Kind = kind, Phase = "Uncertain", Code = 97, Utc = "2026-10-25T12:00:00.0000000Z", AttributeChanges = "SECRET-SENTINEL" }));
            var audit = ReceiptAuditEvent.FromV2Receipt(json.RootElement);
            Check.NotNull(audit, "The durable specialized receipt has an audit projection");
            Check.Equal("Intervention", audit!.Kind, "V1 projection retained");
            Check.False(System.Text.Json.JsonSerializer.Serialize(audit).Contains("SECRET-SENTINEL", StringComparison.Ordinal), "No attribute values enter EventLog");
        }
        Check.Contains("@('Join','Direct','Intervention')", WindowsReceiptAuditSink.ConstantScript, "Native schema admits precisely the V1 audit kinds");
    }
}

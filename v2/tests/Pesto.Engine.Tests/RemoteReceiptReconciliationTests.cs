using Pesto.Engine.Live;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class RemoteReceiptReconciliationTests
{
    private static ReceiptReconciliationObservation Observation(bool partial = false)
    {
        var request = WindowsEvidenceFixture.Request("reconciliation"); var proof = WindowsEvidenceFixture.Proof(request);
        return new(new Receipt(request.ReceiptId, WindowsEvidenceFixture.Now, partial ? "renameMove" : "rename",
            WindowsEvidenceFixture.Computer, WindowsEvidenceFixture.NewName, partial ? "OU=Lyon,OU=SITES,OU=Postes,DC=example,DC=local" : WindowsEvidenceFixture.Ou,
            "live", partial ? "uncertain" : "pendingRestart", partial ? 89 : 20, "Original receipt", true),
            request.ReceiptSha256!, request.ExpectedAdGuid, request.Domain, WindowsEvidenceFixture.Now.AddHours(-2), WindowsEvidenceFixture.Now.AddHours(-1),
            request.ExpectedAdGuid, WindowsEvidenceFixture.NewName, WindowsEvidenceFixture.Ou, WindowsEvidenceFixture.Ou, true, true,
            WindowsEvidenceFixture.NewName, WindowsEvidenceFixture.NewName, request.Domain, true, true, false, true, null, proof);
    }

    [Test]
    public void RemoteRenameCanReconcileOnlyWithBoundSystemBootProofWithoutAnyMutation()
    {
        var good = Observation(); var gateway = new ProofGateway { Evidence = good };
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), new FakeGateway(), gateway);
        var result = Harness.Call(backend, "receipts.reconcile", new { id = good.Receipt.Id });
        Check.True(Harness.Bool(result, "verified"), "Remote complete SYSTEM proof allows reconciliation");
        Check.False(good.LocalTarget, "No fabricated local flag"); Check.Equal(0, gateway.Writes, "No rename, join, move or reboot");
        foreach (var bad in new[] { good with { RemoteWindowsProof = null }, good with { ReceiptSha256 = new string('b', 64) },
            good with { CurrentBootUtc = good.InitialBootUtc }, good with { WindowsActiveName = WindowsEvidenceFixture.Computer },
            good with { RemoteWindowsProof = good.RemoteWindowsProof! with { CleanupConfirmed = false } } })
        {
            var reader = new ProofGateway { Evidence = bad };
            var refused = Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), new FakeGateway(), reader), "receipts.reconcile", new { id = good.Receipt.Id });
            Check.False(Harness.Bool(refused, "verified"), "Old or inconsistent remote evidence keeps original barrier");
            Check.Equal(0, reader.Verifications, "No durable Verified without a complete proof");
        }
    }

    [Test]
    public void RemainingMoveRequiresNewBootExactOriginalDestinationAndRemoteProofBoundToCurrentParentHash()
    {
        var good = Observation(partial: true);
        Check.Null(MoveContinuationRules.EvidenceRefusal(good, WindowsEvidenceFixture.OuGuid, WindowsEvidenceFixture.OuGuid), "Remote code89 can prepare the remaining move after proved boot");
        foreach (var bad in new[] { good with { RemoteWindowsProof = null }, good with { ReceiptSha256 = new string('b', 64) },
            good with { CurrentBootUtc = good.InitialBootUtc }, good with { AdOu = good.Receipt.TargetOU }, good with { AdProtected = false } })
            Check.NotNull(MoveContinuationRules.EvidenceRefusal(bad, WindowsEvidenceFixture.OuGuid, WindowsEvidenceFixture.OuGuid), "Missing or changed proof cannot prepare a move");
        Check.NotNull(MoveContinuationRules.EvidenceRefusal(good, WindowsEvidenceFixture.OuGuid, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"), "Same OU name with another GUID rejected");
        Check.NotNull(MoveContinuationRules.EvidenceRefusal(good with { Receipt = good.Receipt with { Code = 20 } }, WindowsEvidenceFixture.OuGuid, WindowsEvidenceFixture.OuGuid), "An ordinary rename is never turned into a move authorization");
    }
}

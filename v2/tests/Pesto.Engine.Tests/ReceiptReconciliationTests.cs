using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class ProofGateway : IMutationGateway, IMutationReceiptReconciler
{
    public required ReceiptReconciliationObservation Evidence { get; set; }
    public int Writes;
    public int Verifications;
    public bool FailPersistence;
    public string Description => "fixture de preuves, aucune commande native";
    public MutationOutcome Execute(MutationRequest request) { Writes++; throw new TestFailureException("La vérification ne doit jamais exécuter une mutation"); }
    public ReceiptReconciliationObservation ReadReconciliation(string receiptId) => Evidence;
    public void PersistReconciliation(ReceiptReconciliationObservation evidence)
    {
        if (FailPersistence) throw new IOException("Fixture disque indisponible");
        Verifications++;
    }
}

internal sealed class ReceiptReconciliationTests
{
    private const string Id = "receipt-proof";
    private const string Guid = "11111111-1111-1111-1111-111111111111";
    private const string Ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";
    private static ReceiptReconciliationObservation Proof(string kind = "rename") => new(
        new Receipt(Id, DateTimeOffset.UtcNow, kind, "OLD-PC", kind == "move" ? "OLD-PC" : "NEW-PC", Ou, "live", "pendingRestart", 20, "Attente de preuve", true),
        new string('a', 64), Guid, "example.local", new DateTimeOffset(2026, 10, 25, 8, 0, 0, TimeSpan.Zero), new DateTimeOffset(2026, 10, 25, 9, 0, 0, TimeSpan.Zero),
        Guid, kind == "move" ? "OLD-PC" : "NEW-PC", Ou, Ou, true, true, "NEW-PC", "NEW-PC", "example.local", true, true, true, true, null);
    private static (IPestoBackend Backend, ProofGateway Gateway) World(ReceiptReconciliationObservation evidence)
    {
        var gateway = new ProofGateway { Evidence = evidence };
        return (Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), new FakeGateway(), gateway), gateway);
    }

    [Test]
    public void LocalRenameAndJoinVerifyOnlyCompletePostBootEvidence()
    {
        foreach (var kind in new[] { "rename", "join", "renameMove" })
        {
            var (backend, gateway) = World(Proof(kind));
            var result = Harness.Call(backend, "receipts.reconcile", new { id = Id });
            Check.True(Harness.Bool(result, "verified"), kind + " preuve complète");
            Check.Equal("succeeded", Harness.Str(result, "status"), "Résultat confirmé");
            Check.False(Harness.Bool(result, "restartRequired"), "Redémarrage effectivement prouvé");
            Check.Equal(1, gateway.Verifications, "Persistance unique après preuve");
            Check.Equal(0, gateway.Writes, "Aucun rejeu ni reboot");
        }
    }

    [Test]
    public void IncompleteOrContradictoryProofPreservesOriginalBarrier()
    {
        var good = Proof();
        foreach (var evidence in new[]
        {
            good with { InitialBootUtc = null }, good with { CurrentBootUtc = good.InitialBootUtc },
            good with { ExpectedGuid = null }, good with { AdGuid = "22222222-2222-2222-2222-222222222222" },
            good with { AdName = "OTHER-PC" }, good with { AdOu = "OU=Elsewhere,DC=example,DC=local" },
            good with { InitialOu = null }, good with { WindowsConfiguredName = "OLD-PC" },
            good with { WindowsActiveName = "OLD-PC" }, good with { WindowsPartOfDomain = false },
            good with { WindowsDomain = "other.local" }, good with { SecureChannel = false },
            good with { LocalTarget = false }, good with { MachineIdentityMatches = false }, good with { Error = "Panne AD" },
        })
        {
            var (backend, gateway) = World(evidence);
            var result = Harness.Call(backend, "receipts.reconcile", new { id = Id });
            Check.False(Harness.Bool(result, "verified"), "Preuve insuffisante");
            Check.Equal("pendingRestart", Harness.Str(result, "status"), "Phase originale conservée");
            Check.True(Harness.Bool(result, "restartRequired"), "Attente originale conservée");
            Check.False(string.IsNullOrWhiteSpace(Harness.Str(result, "reason")), "Raison visible");
            Check.Equal(0, gateway.Verifications, "Aucune levée de barrière");
            Check.Equal(0, gateway.Writes, "Aucune mutation");
        }
    }

    [Test]
    public void CompletedMoveRequiresGuidDestinationAndOriginalProtectionButNoLocalReboot()
    {
        var move = Proof("move") with { InitialBootUtc = null, CurrentBootUtc = null, LocalTarget = false, MachineIdentityMatches = false, SecureChannel = null };
        var (backend, gateway) = World(move);
        Check.True(Harness.Bool(Harness.Call(backend, "receipts.reconcile", new { id = Id }), "verified"), "Un déplacement ne nécessite aucun redémarrage local");
        Check.Equal(0, gateway.Writes, "Vérification AD seulement");
        foreach (var missingProtection in new[] { move with { AdProtected = false }, move with { InitialProtected = null } })
        {
            var (blocked, adapter) = World(missingProtection);
            Check.False(Harness.Bool(Harness.Call(blocked, "receipts.reconcile", new { id = Id }), "verified"), "Protection non confirmée reste bloquante");
            Check.Equal(0, adapter.Verifications, "Aucune persistance Verified");
        }
    }

    [Test]
    public void UncertainReceiptCanOnlyBeReconciledWithCompleteFacts()
    {
        var good = Proof("join");
        var (backend, gateway) = World(good with { Receipt = good.Receipt with { Status = "uncertain" }, ExpectedGuid = null });
        var result = Harness.Call(backend, "receipts.reconcile", new { id = Id });
        Check.Equal("uncertain", Harness.Str(result, "status"), "Impossible de rattacher l’objet apparu sans GUID initial confirmé");
        Check.False(Harness.Bool(result, "verified"), "Pas de succès inventé");
        Check.Equal(0, gateway.Verifications, "Pas d’acquittement implicite");
    }

    [Test]
    public void PersistenceConflictAndWrongReceiptNeverReportVerification()
    {
        var (backend, gateway) = World(Proof());
        gateway.FailPersistence = true;
        Check.Pesto(() => Harness.Call(backend, "receipts.reconcile", new { id = Id }), "receipt.reconcile_persistence", "Le résultat doit être enregistré");
        Check.Equal(0, gateway.Verifications, "Conflit non accepté");
        Check.Pesto(() => Harness.Call(backend, "receipts.reconcile", new { id = "another-receipt" }), "receipt.identity", "Identité du reçu exacte");
        Check.Equal(0, gateway.Writes, "Aucune commande native");
    }
}

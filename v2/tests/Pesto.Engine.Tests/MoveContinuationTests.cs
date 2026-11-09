using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class MoveContinuationTests
{
    private const string Parent = "receipt-parent";
    private const string Identity = "11111111-1111-1111-1111-111111111111";
    private const string OuIdentity = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string Source = "OU=Lyon-Sud," + Container;
    private const string Target = "OU=Paris-Nord," + Container;
    private const string Current = "NEW-PC";
    private static DirectoryComputer Computer(string ou = Source) => new(Current, null, ou, null, Identity, "example.local", null, null, null, null, null);

    private sealed class ContinuationGateway : IMutationGateway, IMutationMoveContinuation, IMutationReceiptFinalizer, IMutationReceiptReconciler
    {
        public required FakeGateway Directory;
        public required FixedClock Clock;
        public required ReceiptReconciliationObservation Evidence;
        public ReceiptReconciliationObservation? ReconcileEvidence;
        public Func<MoveContinuationPreparation, MoveContinuationPreparation>? Alter;
        public string ParentHash = new('a', 64);
        public bool OtherBarrier, Uncertain, FailFinalization, Resolved, UnresolvedChild;
        public int NativeSends;
        public readonly List<MutationRequest> Requests = [];
        private string? token;
        public string Description => "Fixture continuation, no native command";
        public MoveContinuationPreparation PrepareMoveContinuation(string parentReceiptId, string planId)
        {
            if (OtherBarrier || UnresolvedChild || Resolved) throw new PestoException("continuation.blocked", "Autre barrière, enfant non résolu ou parent déjà résolu");
            token = System.Guid.NewGuid().ToString("N");
            var auth = new MoveContinuationAuthorization(token, Parent, ParentHash, planId, Current, Identity, Source, Target, OuIdentity, Clock.GetUtcNow().AddMinutes(4));
            var result = new MoveContinuationPreparation(Evidence with { ReceiptSha256 = ParentHash }, auth, OuIdentity);
            return Alter?.Invoke(result) ?? result;
        }
        public MutationOutcome Execute(MutationRequest request)
        {
            Requests.Add(request);
            if (request.Kind != "move" || request.NewName is not null || request.Computer != Current || request.Continuation is not { } auth)
                throw new TestFailureException("Only a move carrying its continuation is allowed");
            if (OtherBarrier || UnresolvedChild || Resolved || auth.Token != token || auth.ParentReceiptSha256 != ParentHash || auth.PlanId != request.PlanId)
                return new(MutationStatus.Failed, 96, "Autorisation ou barrière modifiée avant envoi", false);
            token = null;
            NativeSends++;
            UnresolvedChild = true;
            if (Uncertain) return new(MutationStatus.Uncertain, 97, "Résultat inconnu", false);
            Directory.Find = name => name == Current ? Computer(Target) : null;
            return new(MutationStatus.Succeeded, 30, "Déplacement observé", false);
        }
        public ReceiptReconciliationObservation ReadReconciliation(string id) => ReconcileEvidence ?? Evidence;
        public void PersistReconciliation(ReceiptReconciliationObservation evidence) { Resolved = true; UnresolvedChild = false; }
        public void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome)
        {
            if (FailFinalization) throw new IOException("Fixture finalization failed");
            if (outcome.Status == MutationStatus.Succeeded) { Resolved = true; UnresolvedChild = false; }
        }
    }
    private sealed record World(IPestoBackend Backend, FakeGateway Directory, ContinuationGateway Mutation, FixedClock Clock);
    private static World Create()
    {
        var clock = new FixedClock();
        var directory = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord", "Lyon-Sud"] }, Find = name => name == Current ? Computer() : null };
        var receipt = new Receipt(Parent, clock.GetUtcNow(), "renameMove", "OLD-PC", Current, Target, "live", "uncertain", 89, "Partial", false);
        var proof = new ReceiptReconciliationObservation(receipt, new string('a', 64), Identity, "example.local",
            clock.GetUtcNow().AddHours(-2), clock.GetUtcNow().AddHours(-1), Identity, Current, Source, Source,
            true, true, Current, Current, "example.local", true, true, true, true, null);
        var mutation = new ContinuationGateway { Directory = directory, Clock = clock, Evidence = proof };
        return new(Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), directory, mutation, clock), directory, mutation, clock);
    }
    private static JsonNode Prepare(World w) => Harness.Call(w.Backend, "receipts.prepareMove", new { id = Parent });
    private static JsonNode Execute(World w, JsonNode plan) => Harness.Call(w.Backend, "operation.execute", new
        { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });

    [Test]
    public void Code89PreparesOnlyRemainingMoveAndLinksDistinctSuccessfulChild()
    {
        var w = Create();
        var plan = Prepare(w);
        Check.Equal("move", Harness.Str(plan, "kind"), "Jamais un nouveau renameMove");
        Check.Equal(Current, Harness.Str(plan, "computer"), "Nom déjà renommé");
        Check.Equal(Current, Harness.Str(plan, "newName"), "Aucun nom différent proposé");
        Check.Equal(Target, Harness.Str(plan, "targetOU"), "Cible du reçu seulement");
        Check.Equal(Parent, Harness.Str(plan, "parentReceiptId"), "Lien parent explicite");
        Check.False(plan.ToJsonString().Contains("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), "SHA d’autorisation non exposé au web");
        Check.Equal(0, w.Mutation.NativeSends, "Préparation sans envoi");
        var child = Execute(w, plan);
        Check.Equal("succeeded", Harness.Str(child, "status"), "Enfant move vérifié");
        Check.Equal(Parent, Harness.Str(child, "parentReceiptId"), "Reçu enfant distinct lié");
        Check.Equal(1, w.Mutation.NativeSends, "Une seule commande move");
        var parent = Harness.Call(w.Backend, "receipts.get", new { id = Parent });
        Check.Equal("uncertain", Harness.Str(parent, "status"), "Le parent garde son résultat partiel");
        Check.Equal("89", Harness.Str(parent, "code"), "Code89 non réécrit en succès");
        Check.Equal(Harness.Str(child, "id"), Harness.Str(parent, "resolutionChildReceiptId"), "Résolution portée par le reçu enfant");
    }

    [Test]
    public void PartialRenameNeedsCompletePostBootIdentityOuAndProtectionProof()
    {
        var good = Create().Mutation.Evidence;
        foreach (var proof in new[]
        {
            good with { InitialBootUtc = null }, good with { CurrentBootUtc = good.InitialBootUtc },
            good with { AdGuid = "22222222-2222-2222-2222-222222222222" }, good with { AdName = "OLD-PC" },
            good with { AdOu = Target }, good with { InitialOu = null }, good with { InitialProtected = null },
            good with { AdProtected = false }, good with { WindowsActiveName = "OLD-PC" }, good with { WindowsConfiguredName = "OTHER-PC" },
            good with { LocalTarget = false }, good with { MachineIdentityMatches = false }, good with { WindowsPartOfDomain = false },
            good with { WindowsDomain = "other.local" }, good with { SecureChannel = false }, good with { Error = "read failed" },
        })
        {
            var w = Create(); w.Mutation.Evidence = proof;
            Check.Pesto(() => Prepare(w), "receipt.prepareMove_evidence", "Preuve partielle refusée");
            Check.Equal(0, w.Mutation.NativeSends, "Aucune mutation sur preuve insuffisante");
        }
    }

    [Test]
    public void WrongReceiptTypeCodeOrResolvedParentCannotPrepare()
    {
        foreach (var change in new Func<Receipt, Receipt>[]
        {
            r => r with { Id = "other" }, r => r with { Kind = "rename" }, r => r with { Code = 97 },
            r => r with { Status = "succeeded" }, r => r with { ResolutionChildReceiptId = "receipt-child" },
        })
        {
            var w = Create(); w.Mutation.Evidence = w.Mutation.Evidence with { Receipt = change(w.Mutation.Evidence.Receipt) };
            Check.Pesto(() => Prepare(w), "receipt.prepareMove_ineligible", "Reprise limitée au parent code89 exact");
            Check.Equal(0, w.Mutation.NativeSends, "Aucune reprise générique");
        }
    }

    [Test]
    public void NativeAuthorizationMustMatchObservedParentHashPlanAndTargetIdentity()
    {
        foreach (var change in new Func<MoveContinuationPreparation, MoveContinuationPreparation>[]
        {
            p => p with { Authorization = p.Authorization with { ParentReceiptSha256 = new string('b', 64) } },
            p => p with { Authorization = p.Authorization with { PlanId = "other-plan" } },
            p => p with { Authorization = p.Authorization with { ComputerGuid = "22222222-2222-2222-2222-222222222222" } },
            p => p with { Authorization = p.Authorization with { SourceOu = Target } },
            p => p with { Authorization = p.Authorization with { TargetOu = Source } },
            p => p with { ObservedTargetOuGuid = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb" },
            p => p with { Authorization = p.Authorization with { Token = "" } },
        })
        {
            var w = Create(); w.Mutation.Alter = change;
            Check.Pesto(() => Prepare(w), "receipt.prepareMove_authorization", "Autorisation invalide non transformée en plan");
            Check.Equal(0, w.Mutation.NativeSends, "Aucun envoi");
        }
    }

    [Test]
    public void ParentHashDriftOrAnotherBarrierRefusesAtExecuteWithoutFallback()
    {
        foreach (var otherBarrier in new[] { false, true })
        {
            var w = Create(); var plan = Prepare(w);
            if (otherBarrier) w.Mutation.OtherBarrier = true;
            else w.Mutation.ParentHash = new string('b', 64);
            var result = Execute(w, plan);
            Check.Equal("refused", Harness.Str(result, "status"), "Le refus natif demeure un refus");
            Check.Equal(0, w.Mutation.NativeSends, "Pas de move normal de contournement ni rename");
            Check.True(Harness.IsNull(Harness.Call(w.Backend, "receipts.get", new { id = Parent }), "resolutionChildReceiptId"), "Parent toujours non résolu");
        }
        var blocked = Create(); blocked.Mutation.OtherBarrier = true;
        Check.Pesto(() => Prepare(blocked), "continuation.blocked", "Autre barrière refuse dès préparation");
    }

    [Test]
    public void DoubleClickAndSupersededPreparationNeverSendTwice()
    {
        var w = Create(); var plan = Prepare(w); Execute(w, plan);
        Check.Pesto(() => Execute(w, plan), "plan.consumed", "Double clic du même plan refusé");
        Check.Equal(1, w.Mutation.NativeSends, "Un seul envoi");
        var another = Create(); var stale = Prepare(another); var latest = Prepare(another);
        Check.Equal("refused", Harness.Str(Execute(another, stale), "status"), "Nouvelle préparation invalide l’ancien jeton");
        Check.Equal(0, another.Mutation.NativeSends, "Ancien jeton jamais envoyé");
        Check.Equal("succeeded", Harness.Str(Execute(another, latest), "status"), "Dernière préparation explicitement confirmée seulement");
        Check.Equal(1, another.Mutation.NativeSends, "Pas de double commande");
    }

    [Test]
    public void UnknownChildOrFailedFinalPersistenceNeverResolveParent()
    {
        foreach (var persistFailure in new[] { false, true })
        {
            var w = Create(); var plan = Prepare(w);
            w.Mutation.Uncertain = !persistFailure; w.Mutation.FailFinalization = persistFailure;
            var child = Execute(w, plan);
            Check.Equal("uncertain", Harness.Str(child, "status"), "Enfant reste incertain");
            var parent = Harness.Call(w.Backend, "receipts.get", new { id = Parent });
            Check.True(Harness.IsNull(parent, "resolutionChildReceiptId"), "Pas de résolution optimiste");
            Check.Pesto(() => Prepare(w), "continuation.blocked", "Un enfant non finalisé bloque toute nouvelle préparation");
            Check.Equal(1, w.Mutation.NativeSends, "Aucun rejeu après résultat inconnu");
        }
    }

    [Test]
    public void ExplicitChildVerificationUpdatesParentLinkWithoutReplayingMove()
    {
        var w = Create(); var plan = Prepare(w); w.Mutation.Uncertain = true;
        var child = Execute(w, plan); var childId = Harness.Str(child, "id");
        var receipt = new Receipt(childId, w.Clock.GetUtcNow(), "move", Current, Current, Target, "live", "uncertain", 97, "À vérifier", false, Parent);
        w.Mutation.ReconcileEvidence = w.Mutation.Evidence with { Receipt = receipt, AdOu = Target };
        var verified = Harness.Call(w.Backend, "receipts.reconcile", new { id = childId });
        Check.True(Harness.Bool(verified, "verified"), "L’enfant seul est vérifié par relecture explicite");
        var parent = Harness.Call(w.Backend, "receipts.get", new { id = Parent });
        Check.Equal("uncertain", Harness.Str(parent, "status"), "Le résultat parent reste partiel");
        Check.Equal(childId, Harness.Str(parent, "resolutionChildReceiptId"), "Le lien session suit la résolution durable de l’enfant");
        Check.Equal(1, w.Mutation.NativeSends, "La vérification ne rejoue aucun déplacement");
    }

    [Test]
    public void FreshDirectoryDriftAndExpiryRefuseBeforeMutationGateway()
    {
        var w = Create(); var plan = Prepare(w);
        w.Directory.Find = name => name == Current ? Computer(Target) : null;
        Check.Pesto(() => Execute(w, plan), "source.changed", "OU déplacée après confirmation");
        Check.Equal(0, w.Mutation.Requests.Count, "Pas même d’appel natif");
        var expired = Create(); var old = Prepare(expired); expired.Clock.Advance(TimeSpan.FromMinutes(5));
        Check.Pesto(() => Execute(expired, old), "plan.stale", "Autorisation expirée refusée");
        Check.Equal(0, expired.Mutation.Requests.Count, "Aucun envoi expiré");
    }

    [Test]
    public void GenericReconciliationCannotRewriteCode89AsSucceeded()
    {
        var w = Create(); var evidence = w.Mutation.Evidence with { AdOu = Target };
        var gateway = new ProofGateway { Evidence = evidence };
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), new FakeGateway(), gateway);
        var result = Harness.Call(backend, "receipts.reconcile", new { id = Parent });
        Check.False(Harness.Bool(result, "verified"), "Même cible atteinte, le parent conserve le résultat partiel historique");
        Check.Equal(0, gateway.Verifications, "Aucune conversion du parent en Verified");
    }

    [Test]
    public void DurablePartialParentAndChildLinksSurviveBackendRestart()
    {
        var gp = Harness.IsolatedGpRoot(); var folder = Path.Combine(gp, "V2", "receipts"); Directory.CreateDirectory(folder);
        var child = new { Schema = 1, Phase = "Verified", ReceiptId = "receipt-child", PlanId = "plan-child", Kind = "move", Computer = Current,
            NewName = (string?)null, TargetOu = Target, Code = 30, Utc = DateTimeOffset.UtcNow, RestartRequired = false, ParentReceiptId = Parent,
            ParentReceiptSha256 = new string('a', 64), ContinuationAttemptId = new string('b', 64), ContinuationParentStateSha256 = new string('c', 64) };
        var bytes = System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(child);
        File.WriteAllBytes(Path.Combine(folder, "receipt-child.json"), bytes);
        var parent = new { Schema = 1, Phase = "Partial", ReceiptId = Parent, PlanId = "plan-parent", Kind = "renameMove", Computer = "OLD-PC",
            NewName = Current, TargetOu = Target, Code = 89, Utc = DateTimeOffset.UtcNow, RestartRequired = false,
            ResolutionChildReceiptId = "receipt-child", ResolutionChildReceiptSha256 = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)), ResolutionUtc = DateTimeOffset.UtcNow };
        File.WriteAllText(Path.Combine(folder, Parent + ".json"), System.Text.Json.JsonSerializer.Serialize(parent));
        var restarted = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), new FakeGateway(), null, null, gp);
        var loaded = Harness.Call(restarted, "receipts.get", new { id = Parent });
        Check.Equal("uncertain", Harness.Str(loaded, "status"), "Partial ne devient pas succeeded après relance");
        Check.Equal("89", Harness.Str(loaded, "code"), "Code d’origine conservé");
        Check.Equal("receipt-child", Harness.Str(loaded, "resolutionChildReceiptId"), "Lien du parent relu");
        Check.Equal(Parent, Harness.Str(Harness.Call(restarted, "receipts.get", new { id = "receipt-child" }), "parentReceiptId"), "Lien enfant relu");
        Check.Equal(0, Harness.Int(Harness.Call(restarted, "receipts.list"), "invalidCount"), "Le schéma durable comprend les nouvelles métadonnées");
    }

    [Test]
    public async Task ClosedBridgeRejectsFreeDestinationAndSimulationRefusesContinuation()
    {
        var w = Create();
        var result = await Harness.DispatchAsync(w.Backend, "tamper", "receipts.prepareMove", new { id = Parent, targetOU = Source, newName = "OTHER-PC" });
        Check.Equal("arguments.invalid", Harness.ErrorCode(result)!, "Aucune cible ni nouveau nom fournis par le web");
        Check.Equal(0, w.Mutation.NativeSends, "Aucune mutation via arguments étrangers");
        Check.Pesto(() => Harness.Call(Harness.Simulation(), "receipts.prepareMove", new { id = Parent }), "receipt.prepareMoveSimulation", "Aucune preuve live fabriquée en simulation");
    }
}

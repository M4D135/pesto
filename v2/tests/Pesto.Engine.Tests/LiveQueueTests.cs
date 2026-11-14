using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>
/// Lot file live : la file réelle du mode réel est implémentée sur le gateway de qualification injecté.
/// Chaque ligne est liée à un aperçu consommé à l'ajout, au GUID et à l'OU réellement observés ; doublons refusés ;
/// borne = POLICY.MaxBatch lu ; préparation = relecture annuaire ligne à ligne puis plans reforgés ; exécution
/// séquentielle sous verrou par le pipeline unitaire, arrêt sur la première ligne non réussie, lignes non tentées
/// restantes en file, reçu par ligne envoyée, aucun rejeu. Ces tests échouent réellement si queue.* redevient un
/// refus constant ou un retour vide. Aucune mutation réelle, aucun AD, aucun service modifié.
/// </summary>
internal sealed class LiveQueueTests
{
    private sealed class SlowPreparation(FixedClock clock) : IMutationGateway, IMutationEntraPreparation
    {
        public TimeSpan Delay;
        public int Sends;
        public string Description => "Fixture de latence de lecture, aucun accès réel";
        public EntraRenameAuthorization PrepareEntra(EntraPreparationRequest request)
        {
            clock.Advance(Delay); var now = clock.GetUtcNow();
            return new(Guid.NewGuid().ToString("N"), request, "adOnly", "Disabled", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", now, now.AddMinutes(5));
        }
        public MutationOutcome Execute(MutationRequest request) { Sends++; throw new TestFailureException("No write expected"); }
    }

    [Test]
    public void ATargetThatBecameAnotherQueuedSourceIsRejectedAsDependencyBeforeBatchPreparation()
    {
        var w = QueueWorld(true); EnqueueRename(w, ComputerA);
        var future = Harness.Str(Harness.Arr(Harness.Call(w.Backend, "queue.list"), "items")[0]!, "newName");
        var original = w.Gateway.Find;
        w.Gateway.Find = name => name.Equals(future, StringComparison.OrdinalIgnoreCase)
            ? Observed(future, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") : original!(name);
        EnqueueRename(w, future);
        Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare"), "queue.dependent", "One line’s target cannot also be another line’s source");
        Check.Equal(0, w.Mutation!.Requests.Count, "No sent mutation");
    }

    [Test]
    public void SequentialRemoteDiagnosticLatencyCannotExposeAnAlreadyExpiredBatchAsReady()
    {
        var seed = QueueWorld(true); var reader = new SlowPreparation(seed.Clock);
        var w = new World { Clock = seed.Clock, Gateway = seed.Gateway,
            Backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), seed.Gateway, reader, seed.Clock) };
        EnqueueRename(w, ComputerA); EnqueueRename(w, ComputerB);
        reader.Delay = TimeSpan.FromMinutes(6);
        var error = Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare"), "batch.stale", "Expired first evidence cannot become an executable batch");
        Check.Contains("lot plus petit", error.Message, "Operator has a concrete smaller-batch action");
        Check.Equal(0, reader.Sends, "No implicit write after a slow preparation");
    }

    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string ComputerA = "P111301PAINF009";
    private const string GuidA = "11111111-1111-1111-1111-111111111111";
    private const string ComputerB = "P111301PAINF019";
    private const string GuidB = "22222222-2222-2222-2222-222222222222";
    private const string ComputerC = "P111301PAINF029";
    private const string GuidC = "33333333-3333-3333-3333-333333333333";

    private static DirectoryComputer Observed(string name, string guid, string? ou = ParisOu) =>
        new(name, null, ou, null, guid, "example.local", null, null, null, null, null);

    private sealed class World
    {
        public required IPestoBackend Backend { get; init; }
        public required FakeGateway Gateway { get; init; }
        public FakeMutationGateway? Mutation { get; init; }
        public required FixedClock Clock { get; init; }
    }

    /// <summary>Monde live à trois postes observés ; l'inventaire est vide : tous les numéros 001..999 sont libres hors vus.</summary>
    private static World QueueWorld(bool withMutation, string? cfg = null, bool withoutAdapter = false)
    {
        var machines = new Dictionary<string, DirectoryComputer>(StringComparer.OrdinalIgnoreCase)
        {
            [ComputerA] = Observed(ComputerA, GuidA),
            [ComputerB] = Observed(ComputerB, GuidB),
            [ComputerC] = Observed(ComputerC, GuidC),
        };
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] },
            Find = name => machines.TryGetValue(name, out var c) ? c : null,
        };
        var clock = new FixedClock();
        var mutation = withMutation ? new FakeMutationGateway() : null;
        if (mutation is not null)
        {
            mutation.Respond = request =>
            {
                if (request.Kind == "move" && machines.TryGetValue(request.Computer, out var m))
                    machines[request.Computer] = m with { Ou = request.TargetOu };
                else if (machines.TryGetValue(request.Computer, out var c))
                {
                    machines.Remove(request.Computer);
                    machines[request.NewName!] = Observed(request.NewName!, c.Guid ?? "", request.TargetOu ?? c.Ou);
                }
                return new(Pesto.Engine.MutationStatus.Succeeded, 0, "OK fixture", false);
            };
        }
        return new World
        {
            Backend = Harness.Live(LiveTestConfig.Write(cfg ?? LiveTestConfig.NoRandom), gateway,
                mutation is not null ? mutation : withoutAdapter ? null : new FixtureEntraReadOnly(), clock),
            Gateway = gateway,
            Mutation = mutation,
            Clock = clock,
        };
    }

    private static string Preview(World w, string computer, string type = "P", string service = "INF") =>
        Harness.Str(Harness.Call(w.Backend, "names.preview", new { type, site = "PA", service, computer }), "previewId");

    private static void EnqueueRename(World w, string computer, string type = "P", string service = "INF") =>
        Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer, previewId = Preview(w, computer, type, service) });

    // ---- add / list / remove --------------------------------------------------------------

    [Test]
    public void QueueAddListRemoveRoundTrip()
    {
        var w = QueueWorld(false);
        var list = Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer = ComputerA, previewId = Preview(w, ComputerA) });
        Check.Equal(1, Harness.Int(list, "count"), "La file réelle stocke la ligne validée (pas un refus constant, pas un vide)");
        var item = Harness.Arr(list, "items")[0]!;
        Check.False(string.IsNullOrEmpty(Harness.Str(item, "id")), "Chaque ligne porte son identifiant");
        Check.Equal("rename", Harness.Str(item, "kind"), "Type de la ligne");
        Check.Equal(ComputerA, Harness.Str(item, "computer"), "Poste visé");
        Check.Equal("P111301PAINF001", Harness.Str(item, "newName"), "Nom de l'aperçu réellement libre");
        Check.Equal(ParisOu, Harness.Str(item, "targetOU"), "OU réellement observée");
        Check.Equal("ready", Harness.Str(item, "status"), "Statut de la ligne");
        var id = Harness.Str(item, "id");
        Check.Equal(1, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "queue.list rend le contenu réel de la file");
        Check.Equal(0, Harness.Int(Harness.Call(w.Backend, "queue.remove", new { id }), "count"), "Retrait par identifiant");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.remove", new { id }), "queue.missing", "Une ligne retirée n'existe plus");
    }

    [Test]
    public void JoinCannotBeQueued()
    {
        var w = QueueWorld(false);
        Check.Pesto(() => Harness.Call(w.Backend, "queue.add", new { kind = "join", computer = Environment.MachineName }),
            "queue.local", "La jonction locale reste hors file");
    }

    [Test]
    public void AddConsumesThePreviewOnce()
    {
        var w = QueueWorld(false);
        var previewId = Preview(w, ComputerA);
        var list = Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer = ComputerA, previewId });
        var id = Harness.Str(Harness.Arr(list, "items")[0]!, "id");
        Harness.Call(w.Backend, "queue.remove", new { id });
        Check.Pesto(() => Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer = ComputerA, previewId }),
            "plan.stale", "Un aperçu ne fonde qu'une seule ligne : retirée puis re-addée avec le même aperçu, refus — jamais deux lignes");
    }

    [Test]
    public void DuplicateComputerRejected()
    {
        var w = QueueWorld(false);
        EnqueueRename(w, ComputerA);
        Check.Pesto(() => { EnqueueRename(w, ComputerA); return null; },
            "queue.duplicate", "Le même poste ne peut pas être ajouté deux fois, même avec un nouvel aperçu");
    }

    [Test]
    public void QueueLimitComesFromTheConfiguredMaxBatch()
    {
        var w = QueueWorld(false, LiveTestConfig.NoRandom.Replace("\"MaxBatch\": 50", "\"MaxBatch\": 2"));
        EnqueueRename(w, ComputerA);
        EnqueueRename(w, ComputerB);
        var error = Check.Pesto(() => { EnqueueRename(w, ComputerC); return null; },
            "queue.limit", "La borne de la file est POLICY.MaxBatch lu, jamais une valeur codée en dur");
        Check.Contains("2", error.Message, "La raison annonce la borne réellement lue");
        Check.Contains("MaxBatch", error.Message, "La raison nomme la source de la borne");
        Check.Equal(2, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "La ligne refusée n'a pas été ajoutée");
    }

    [Test]
    public void AddRefusesExpiredPreview()
    {
        var w = QueueWorld(false);
        var previewId = Preview(w, ComputerA);
        w.Clock.Advance(TimeSpan.FromMinutes(6));
        Check.Pesto(() => Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer = ComputerA, previewId }),
            "plan.stale", "Aperçu expiré : nouvel aperçu + nouveau clic, la file n'accepte pas une lecture périmée");
    }

    [Test]
    public void AddRefusesNameTakenAfterPreview()
    {
        var w = QueueWorld(false);
        var previewId = Preview(w, ComputerA);
        w.Gateway.Find = name => name.Equals(ComputerA, StringComparison.OrdinalIgnoreCase) ? Observed(ComputerA, GuidA)
            : name.Equals("P111301PAINF001", StringComparison.OrdinalIgnoreCase) ? Observed("P111301PAINF001", "44444444-4444-4444-4444-444444444444")
            : null;
        var error = Check.Pesto(() => Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer = ComputerA, previewId }),
            "name.taken", "Collision entre l'aperçu et l'ajout : refus motivé, jamais d'ajout automatique");
        Check.Contains("nouvel aperçu", error.Message, "La raison renvoie vers un nouvel aperçu et un nouveau clic");
    }

    [Test]
    public void MoveLineKeepsTheNameAndNeedsNoPreview()
    {
        var w = QueueWorld(false);
        var list = Harness.Call(w.Backend, "queue.add", new { kind = "move", computer = ComputerA, targetOU = "PA" });
        var item = Harness.Arr(list, "items")[0]!;
        Check.Equal(ComputerA, Harness.Str(item, "newName"), "Déplacement seul : le nom ne change pas");
        Check.Equal(ParisOu, Harness.Str(item, "targetOU"), "Destination = OU réellement observée du site choisi");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.add", new { kind = "move", computer = ComputerB }),
            "invalid_arguments", "Déplacement sans destination refusé");
    }

    [Test]
    public void QueuedNameIsNeverReProposedWhileQueued()
    {
        var w = QueueWorld(false);
        EnqueueRename(w, ComputerA);
        var second = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = ComputerB });
        Check.Equal("P111301PAINF002", Harness.Str(second, "name"), "Le nom visé par la file n'est jamais reproposé pendant qu'il y est");
    }

    // ---- préparation du lot ----------------------------------------------------------------

    [Test]
    public void EmptyQueueCannotBePrepared()
    {
        var w = QueueWorld(true);
        Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare"), "queue.empty", "File vide refusée");
    }

    [Test]
    public void PrepareRefusesALineWhoseIdentityChanged()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        w.Gateway.Find = name => name.Equals(ComputerA, StringComparison.OrdinalIgnoreCase)
            ? Observed(ComputerA, "99999999-9999-9999-9999-999999999999") : null;
        Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare"), "identity.changed",
            "La préparation relit le GUID de chaque ligne : une identité qui a bougé refuse le lot, jamais un plan suspect");
    }

    [Test]
    public void PrepareRefusesANameTakenAfterTheAdd()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        w.Gateway.Find = name => name.Equals(ComputerA, StringComparison.OrdinalIgnoreCase) ? Observed(ComputerA, GuidA)
            : name.Equals("P111301PAINF001", StringComparison.OrdinalIgnoreCase) ? Observed("P111301PAINF001", "44444444-4444-4444-4444-444444444444")
            : null;
        Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare"), "name.taken",
            "Nom pris après l'ajout : la préparation le voit et refuse le lot, aucun ajout automatique");
    }

    // ---- exécution du lot -------------------------------------------------------------------

    [Test]
    public void BatchExecutesSequentiallyAndStopsOnRefusal()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        EnqueueRename(w, ComputerB);
        EnqueueRename(w, ComputerC);
        var batch = Harness.Call(w.Backend, "queue.prepare");
        Check.Equal(3, Harness.Arr(batch, "items").Count, "Un plan par ligne, dans l'ordre de la file");
        var apply = w.Mutation!.Respond;
        w.Mutation.Respond = request => request.Computer.Equals(ComputerB, StringComparison.OrdinalIgnoreCase)
            ? new(Pesto.Engine.MutationStatus.Failed, 5, "Refus avant envoi (fixture)", false)
            : apply(request);
        var result = Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        var receipts = Harness.Arr(result, "receipts");
        Check.Equal(2, receipts.Count, "Deux lignes tentées : la troisième n'a jamais été envoyée");
        Check.Equal("succeeded", Harness.Str(receipts[0]!, "status"), "Première ligne appliquée et relue");
        Check.Equal("refused", Harness.Str(receipts[1]!, "status"), "Ligne refusée : reçu honnête, rien d'écrit");
        Check.True(Harness.Bool(result, "stopped"), "Arrêt sur la première ligne non réussie");
        Check.False(string.IsNullOrEmpty(Harness.Str(result, "reason")), "La raison de l'arrêt est rendue");
        Check.Equal(1, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "La ligne non tentée reste dans la file");
        Check.Equal(2, w.Mutation.Requests.Count, "Séquentiel sous verrou : la ligne suivante n'a jamais été tentée après le refus");
        Check.Equal(ComputerA, w.Mutation.Requests[0].Computer, "Ordre de la file respecté (ligne 1)");
        Check.Equal(ComputerB, w.Mutation.Requests[1].Computer, "Ordre de la file respecté (ligne 2)");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }),
            "batch.stale", "Un lot arrêté ne rejoue jamais : re-préparation obligatoire");
        Check.Equal(2, w.Mutation.Requests.Count, "Aucun second envoi après le rejeu refusé");
    }

    [Test]
    public void UncertainLineStopsTheBatchAndIsNeverReplayed()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        EnqueueRename(w, ComputerB);
        var batch = Harness.Call(w.Backend, "queue.prepare");
        w.Mutation!.Throw = new InvalidOperationException("panne réseau après envoi possible");
        var result = Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        var receipts = Harness.Arr(result, "receipts");
        Check.Equal(1, receipts.Count, "Une seule ligne tentée");
        Check.Equal("uncertain", Harness.Str(receipts[0]!, "status"), "Résultat inconnu conservé, jamais transformé en succès ni en échec");
        Check.True(Harness.Bool(result, "stopped"), "L'incertain arrête le lot (port des barrières v1)");
        Check.Equal(1, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "La ligne suivante reste en file, non tentée");
        Check.Equal(1, w.Mutation.Requests.Count, "L'adaptateur n'a jamais été rappelé");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }),
            "batch.stale", "Aucun rejeu automatique d'un lot contenant un incertain");
    }

    [Test]
    public void PendingRestartReceiptIsKeptAndIndependentNextComputerContinues()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        EnqueueRename(w, ComputerB);
        var batch = Harness.Call(w.Backend, "queue.prepare");
        var original = w.Mutation!.Respond;
        w.Mutation.Respond = request => { _ = original!(request); return request.Computer.Equals(ComputerA, StringComparison.OrdinalIgnoreCase)
            ? new(Pesto.Engine.MutationStatus.PendingRestart, 20, "Accepté, redémarrage à planifier (fixture)", true)
            : new(Pesto.Engine.MutationStatus.Succeeded, 0, "OK fixture", false); };
        var result = Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        Check.Equal(2, Harness.Arr(result, "receipts").Count, "Les deux cibles indépendantes ont reçu leur demande unique");
        Check.False(Harness.Bool(result, "stopped"), "L’acceptation en attente de boot n’arrête pas la cible indépendante suivante (V1)");
        Check.Equal("pendingRestart", Harness.Str(Harness.Arr(result, "receipts")[0]!, "status"), "Premier reçu toujours en attente, aucun faux succès de boot");
        Check.Equal(0, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "Aucune ligne non tentée");
        Check.Equal(2, w.Mutation!.Requests.Count, "Un seul envoi par cible, aucun reboot");
    }

    [Test]
    public void ExecuteWithoutAdapterRefusesWithoutConsuming()
    {
        var w = QueueWorld(false, withoutAdapter: true);
        Harness.Call(w.Backend, "queue.add", new { kind = "move", computer = ComputerA, targetOU = "PA" });
        var batchId = Harness.Str(Harness.Call(w.Backend, "queue.prepare"), "batchId");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId, confirmed = true }),
            "write.unavailable", "Sans adaptateur de mutation injecté, l'exécution du lot reste fermée (production fermée jusqu'à qualification)");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId, confirmed = true }),
            "write.unavailable", "Le refus avant envoi n'a pas consommé le lot : refus répété, jamais d'envoi différé");
        Check.Equal(1, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "La file est intacte après le refus");
        Check.Equal(0, Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Count, "Aucun reçu fictif");
    }

    [Test]
    public void BatchNeedsExplicitConfirmation()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        var batchId = Harness.Str(Harness.Call(w.Backend, "queue.prepare"), "batchId");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId, confirmed = false }),
            "confirmation.invalid", "Le lot doit être confirmé explicitement, avant toute autre vérification d'état");
        Check.Equal(0, w.Mutation!.Requests.Count, "Aucun envoi sans confirmation");
    }

    [Test]
    public void BatchBecomesStaleWhenTheQueueChanges()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        var batchId = Harness.Str(Harness.Call(w.Backend, "queue.prepare"), "batchId");
        EnqueueRename(w, ComputerB);
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId, confirmed = true }),
            "batch.stale", "La file a changé après la préparation : le lot est refusé, re-préparation obligatoire");
        Check.Equal(0, w.Mutation!.Requests.Count, "Aucun envoi sur un lot périmé");
    }

    [Test]
    public void BatchExpires()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        var batchId = Harness.Str(Harness.Call(w.Backend, "queue.prepare"), "batchId");
        w.Clock.Advance(TimeSpan.FromMinutes(6));
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId, confirmed = true }),
            "batch.stale", "Lot expiré : on repasse par une préparation relue, aucune exécution sur un aperçu périmé");
    }

    [Test]
    public void IdentityChangedBeforeSendKeepsTheLineInQueue()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        EnqueueRename(w, ComputerB);
        var batch = Harness.Call(w.Backend, "queue.prepare");
        var originalFind = w.Gateway.Find!;
        w.Gateway.Find = name => name.Equals(ComputerA, StringComparison.OrdinalIgnoreCase)
            ? Observed(ComputerA, "99999999-9999-9999-9999-999999999999")
            : originalFind(name);
        var result = Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        Check.Equal(0, Harness.Arr(result, "receipts").Count, "Aucun reçu : rien n'a été envoyé sur une identité qui a bougé");
        Check.True(Harness.Bool(result, "stopped"), "Arrêt immédiat, raison rendue");
        Check.Equal(2, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "Aucune ligne consommée : la ligne fautive reste en file");
        Check.Equal(0, w.Mutation!.Requests.Count, "L'adaptateur n'a jamais été appelé");
    }

    [Test]
    public void QueueReceiptsAreListedAndBoundToTheSend()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        var batch = Harness.Call(w.Backend, "queue.prepare");
        var result = Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        var receipt = Harness.Arr(result, "receipts")[0]!;
        Check.Equal("succeeded", Harness.Str(receipt, "status"), "Ligne appliquée et confirmée par relecture");
        Check.Contains("fixture", Harness.Str(receipt, "mode"), "La source de l'envoi est celle injectée, jamais une origine cachée");
        var id = Harness.Str(receipt, "id");
        Check.Equal(id, Harness.Str(Harness.Call(w.Backend, "receipts.get", new { id }), "id"), "Le reçu du lot est consultable après coup");
        Check.Equal(1, Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Count, "Historique de session de la file");
        Check.Equal(id, w.Mutation!.Requests[0].ReceiptId, "Le reçu est lié à la demande AVANT l'envoi");
        Check.False(string.IsNullOrEmpty(w.Mutation.Requests[0].PlanId), "La demande porte l'identifiant du plan du lot");
        Check.Equal(GuidA, w.Mutation.Requests[0].ComputerGuid, "Le GUID observé à l'ajout est transmis à l'envoi");
    }
    [Test]
    public void CancellationFinishesActiveLineAndKeepsUntouchedLinesQueued()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        EnqueueRename(w, ComputerB);
        var batch = Harness.Call(w.Backend, "queue.prepare");
        using var cancellation = new CancellationTokenSource();
        var apply = w.Mutation!.Respond;
        w.Mutation.Respond = request =>
        {
            var outcome = apply(request);
            cancellation.Cancel(); // Fermeture demandée après engagement natif : terminer le reçu de cette ligne.
            return outcome;
        };
        var args = System.Text.Json.JsonSerializer.SerializeToElement(new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        var result = (System.Text.Json.Nodes.JsonNode)w.Backend.InvokeAsync("queue.execute", args, cancellation.Token).GetAwaiter().GetResult()!;
        var receipt = Harness.Arr(result, "receipts").Single()!;
        Check.Equal("succeeded", Harness.Str(receipt, "status"), "La ligne engagée achève sa relecture et son reçu malgré fermeture");
        Check.Equal("succeeded", Harness.Str(Harness.Call(w.Backend, "receipts.get", new { id = Harness.Str(receipt, "id") }), "status"), "Reçu final consultable");
        Check.True(Harness.Bool(result, "stopped"), "Arrêt explicite entre les lignes");
        Check.Contains("Arrêt demandé", Harness.Str(result, "reason"), "Raison de fermeture rendue");
        Check.Equal(1, w.Mutation.Requests.Count, "La deuxième mutation ne démarre jamais");
        var remaining = Harness.Arr(Harness.Call(w.Backend, "queue.list"), "items");
        Check.Equal(ComputerB, Harness.Str(remaining.Single()!, "computer"), "Ligne non engagée conservée");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }), "batch.stale", "Aucune reprise implicite du lot arrêté");
    }

    [Test]
    public void QueuedSourceOuDriftRefusesBatchPreparation()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA);
        w.Gateway.Find = name => name == ComputerA ? Observed(name, GuidA, "OU=Staging,OU=Postes,DC=example,DC=local") : null;
        Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare"), "source.changed", "Une ligne garde l’OU source observée lors de l’ajout");
        Check.Equal(0, w.Mutation!.Requests.Count, "Aucune commande envoyée après dérive en file");
    }

    [Test]
    public void PilotPreparesAndSendsOnlyTheFirstLineThenPreservesTheRest()
    {
        var w = QueueWorld(true);
        EnqueueRename(w, ComputerA); EnqueueRename(w, ComputerB);
        var batch = Harness.Call(w.Backend, "queue.prepare", new { pilot = true });
        Check.True(Harness.Bool(batch, "pilot"), "Le mode pilote appartient au lot natif");
        Check.Equal(1, Harness.Arr(batch, "items").Count, "Un seul plan peut être confirmé");
        Check.Equal(1, Harness.Int(batch, "remainingCount"), "La ligne suivante reste hors du plan");
        var result = Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        Check.True(Harness.Bool(result, "pilotCompleted"), "Le pilote terminé est explicite");
        Check.Equal(1, w.Mutation!.Requests.Count, "Un seul envoi réel, aucune continuation implicite");
        Check.Equal(ComputerA, w.Mutation.Requests[0].Computer, "Première ligne seulement");
        Check.Equal(ComputerB, Harness.Str(Harness.Arr(Harness.Call(w.Backend, "queue.list"), "items").Single()!, "computer"), "La seconde ligne est conservée");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }), "batch.stale", "Le pilote ne se rejoue pas");
    }

    [Test]
    public void PilotCannotBeChangedAtExecutionOrPassedAsText()
    {
        var w = QueueWorld(true); EnqueueRename(w, ComputerA); EnqueueRename(w, ComputerB);
        Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare", new { pilot = "true" }), "invalid_arguments", "Booléen strict");
        var batch = Harness.Call(w.Backend, "queue.prepare", new { pilot = true });
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true, pilot = false }), "invalid_arguments", "Le navigateur ne peut pas élargir le lot confirmé");
        Check.Equal(0, w.Mutation!.Requests.Count, "Aucune mutation après falsification");
    }

    [Test]
    public void UncertainPilotCannotReportCompletionOrAdvanceTheNextComputer()
    {
        var w = QueueWorld(true); EnqueueRename(w, ComputerA); EnqueueRename(w, ComputerB);
        var batch = Harness.Call(w.Backend, "queue.prepare", new { pilot = true });
        w.Mutation!.Throw = new IOException("Réponse perdue après envoi possible");
        var result = Harness.Call(w.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        Check.False(Harness.Bool(result, "pilotCompleted"), "Le résultat incertain ne vaut jamais pilote terminé");
        Check.Equal("uncertain", Harness.Str(Harness.Arr(result, "receipts").Single()!, "status"), "Reçu incertain conservé");
        Check.Equal(1, w.Mutation.Requests.Count, "Aucun deuxième envoi");
        Check.Equal(ComputerB, Harness.Str(Harness.Arr(Harness.Call(w.Backend, "queue.list"), "items").Single()!, "computer"), "Suite intacte, préparation explicite requise");
    }

}

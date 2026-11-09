using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>Adaptateur de mutation de test : n'exécute rien de réel, enregistre les demandes et rend le résultat convenu.</summary>
internal sealed class FakeMutationGateway : Pesto.Engine.IMutationGateway, IFixtureEntraPreparation
{
    public string Description => "fixture de qualification";
    public List<Pesto.Engine.MutationRequest> Requests = [];
    public Func<Pesto.Engine.MutationRequest, Pesto.Engine.MutationOutcome> Respond = _ =>
        new(Pesto.Engine.MutationStatus.Succeeded, 0, "OK fixture", false);
    public Exception? Throw;

    public Pesto.Engine.MutationOutcome Execute(Pesto.Engine.MutationRequest request)
    {
        Requests.Add(request);
        if (Throw is not null) throw Throw;
        return Respond(request);
    }
}

/// <summary>
/// Lot moteur live 3 : préparation liée à l'aperçu (consommation unique, expiration, poste, GUID), confirmation exacte,
/// refus total d'écriture sans adaptateur qualifié, et cycle d'envoi du harnais de qualification (reçu avant envoi,
/// relecture après, incertain jamais rejoué). Aucune mutation réelle, aucun service modifié.
/// </summary>
internal sealed class LiveWriteTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string Computer = "P111301PAINF009";
    private const string ComputerGuid = "11111111-1111-1111-1111-111111111111";

    private static DirectoryComputer Observed(string name, string? guid = ComputerGuid, string? ou = ParisOu) =>
        new(name, null, ou, null, guid, "example.local", null, null, null, null, null);

    private sealed class World
    {
        public required IPestoBackend Backend { get; init; }
        public required FakeGateway Gateway { get; init; }
        public FakeMutationGateway? Mutation { get; init; }
        public required FixedClock Clock { get; init; }
        public required string ConfigurationRoot { get; init; }
    }

    /// <summary>Monde live : site Paris-Nord observé, poste existant, candidats libres vus par l'inventaire, horloge contrôlée.</summary>
    private static World LiveWorld(bool withMutation, params string[] takenNames)
    {
        var present = new HashSet<string>(takenNames, StringComparer.OrdinalIgnoreCase);
        var machines = new Dictionary<string, DirectoryComputer>(StringComparer.OrdinalIgnoreCase) { [Computer] = Observed(Computer) };
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] },
            ScopeNames = [.. takenNames],
            Find = name => machines.TryGetValue(name, out var c) ? c : present.Contains(name) ? Observed(name, "22222222-2222-2222-2222-222222222222") : null,
        };
        var clock = new FixedClock();
        var mutation = withMutation ? new FakeMutationGateway() : null;
        if (mutation is not null)
        {
            // L'envoi réussi de la fixture déplace réellement l'objet dans la fixture : la relecture du moteur doit le voir.
            mutation.Respond = request =>
            {
                if (request.Kind == "join") present.Add(request.NewName!);
                else if (request.Kind != "move" && machines.TryGetValue(request.Computer, out var c))
                {
                    machines.Remove(request.Computer);
                    machines[request.NewName!] = Observed(request.NewName!, c.Guid, request.TargetOu ?? c.Ou);
                }
                else if (request.Kind == "move" && machines.TryGetValue(request.Computer, out var m))
                    machines[request.Computer] = m with { Ou = request.TargetOu };
                return new(Pesto.Engine.MutationStatus.Succeeded, 0, "OK fixture", false);
            };
        }
        var configurationRoot = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        return new World
        {
            Backend = Harness.Live(configurationRoot, gateway, mutation, clock),
            Gateway = gateway,
            Mutation = mutation,
            Clock = clock,
            ConfigurationRoot = configurationRoot,
        };
    }

    private static (World World, string PreviewId, string Name) WithPreview(World w, string type = "P", string service = "INF", string? computer = null)
    {
        var args = computer is null
            ? (object)new { type, site = "PA", service }
            : new { type, site = "PA", service, computer };
        var p = Harness.Call(w.Backend, "names.preview", args);
        return (w, Harness.Str(p, "previewId"), Harness.Str(p, "name"));
    }

    // ---- préparation (lecture seule, liée à l'aperçu) ---------------------------------

    [Test]
    public void PrepareJoinBuildsAPlanBoundToThePreview()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(false));
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "join", previewId });
        Check.Equal("join", Harness.Str(plan, "kind"), "Action demandée");
        Check.Equal(Environment.MachineName, Harness.Str(plan, "computer"), "Jonction locale uniquement : le poste est celui observé");
        Check.Equal(name, Harness.Str(plan, "newName"), "Le nom vient de l'aperçu réellement libre");
        Check.Equal(ParisOu, Harness.Str(plan, "targetOU"), "OU réellement observée du site");
        Check.Equal("live", Harness.Str(plan, "mode"), "Mode réel annoncé, jamais « simulation »");
        Check.Equal(name, Harness.Str(plan, "confirmationName"), "La confirmation exacte porte sur le nom à appliquer");
        Check.False(string.IsNullOrEmpty(Harness.Str(plan, "expiresAt")), "Expiration du plan");
        Check.Equal(3, Harness.Arr(plan, "steps").Count, "Identité, nom, placement : les étapes réelles du plan");
        Check.True(Harness.Arr(plan, "warnings").Count >= 1, "Avertissements honnêtes sur le mode réel");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "join", previewId }),
            "plan.stale", "Un aperçu ne fonde qu'un seul plan : consommation unique");
    }

    [Test]
    public void PrepareJoinIsLocalOnlyAndRefusesAnAlreadyKnownMachine()
    {
        var (w, previewId, _) = WithPreview(LiveWorld(false));
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "join", previewId, computer = "AUTRE-PC" }),
            "join.localOnly", "La jonction ne concerne jamais un autre poste");
        var joined = LiveWorld(false);
        var (w2, previewId2, name2) = WithPreview(joined);
        joined.Gateway.ScopeNames = [.. joined.Gateway.ScopeNames, Environment.MachineName];
        var present = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { name2, Environment.MachineName };
        joined.Gateway.Find = name => present.Contains(name) ? Observed(name, "33333333-3333-3333-3333-333333333333") : null;
        Check.Pesto(() => Harness.Call(joined.Backend, "operation.prepare", new { kind = "join", previewId = previewId2 }),
            "join.alreadyJoined", "Poste local déjà présent dans l'annuaire : la jonction n'a pas de sens");
    }

    [Test]
    public void PrepareRenameIsBoundToItsPreviewAndComputer()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer }),
            "preview.missing", "Sans aperçu, aucun nom n'est calculé à la volée : la disponibilité reste à prouver");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = "AUTRE-POSTE", previewId }),
            "preview.identity", "L'aperçu appartient au poste P…009, pas à un autre : refus avant même la lecture");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "move", computer = "ABSENT-DE-L-AD", targetOU = "PA" }),
            "computer.missing", "Poste absent de l'annuaire : rien à déplacer");
        var (w2, joinPreviewId, _) = WithPreview(LiveWorld(false));
        Check.Pesto(() => Harness.Call(w2.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = joinPreviewId }),
            "preview.identity", "Un aperçu de jonction ne fonde pas un renommage");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId, newName = "NOM-INVENTE" }),
            "preview.changed", "Le nom demandé doit être exactement celui de l'aperçu");
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        Check.Equal(name, Harness.Str(plan, "newName"), "Renommage : le nom confirmé de l'aperçu");
        Check.Equal(Computer, Harness.Str(plan, "computer"), "Le poste de l'aperçu");
        Check.Equal(ParisOu, Harness.Str(plan, "targetOU"), "Même site : OU réellement observée conservée");
    }

    [Test]
    public void RenameOnlyWithDifferentSitePreviewKeepsObservedSourceOuInPlanAndReceipt()
    {
        const string oldName = "V111301LYINF009";
        const string sourceOu = "OU=Ateliers,OU=Lyon," + Container;
        var observed = Observed(oldName, ComputerGuid, sourceOu);
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord", "Lyon"] },
            ScopeNames = [oldName],
            Find = name => name.Equals(observed.Name, StringComparison.OrdinalIgnoreCase) ? observed : null,
        };
        var mutation = new FakeMutationGateway
        {
            Respond = request =>
            {
                // Windows Rename-Computer changes the name; it never applies a target OU.
                observed = observed with { Name = request.NewName! };
                return new MutationOutcome(MutationStatus.PendingRestart, 20, "Renommage fixture sans déplacement.", true);
            },
        };
        var b = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), gateway, mutation, new FixedClock());
        var preview = Harness.Call(b, "names.preview", new { type = "V", site = "PA", service = "INF", computer = oldName });
        Check.Equal(ParisOu, Harness.Str(preview, "ou"), "L’aperçu vise bien un autre site pour un éventuel renommage avec déplacement");
        var previewId = Harness.Str(preview, "previewId");
        Check.Pesto(() => Harness.Call(b, "operation.prepare", new { kind = "rename", computer = oldName, previewId, targetOU = ParisOu }),
            "rename.no_move", "Une demande contradictoire ne laisse pas croire que rename déplace l’objet");
        var plan = Harness.Call(b, "operation.prepare", new { kind = "rename", computer = oldName, previewId });
        Check.Equal(sourceOu, Harness.Str(plan, "targetOU"), "Le plan annonce l’OU effectivement conservée");
        var receipt = Harness.Call(b, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        Check.Equal(sourceOu, mutation.Requests[0].TargetOu, "Le reçu natif reçoit l’OU source");
        Check.Equal(sourceOu, Harness.Str(receipt, "targetOU"), "Le reçu final n’invente pas un déplacement");
        Check.Equal(sourceOu, observed.Ou, "L’objet reste dans son OU initiale");
    }

    [Test]
    public void SameSiteRenameMoveNormalizesToRenameAndPreservesDeeperOu()
    {
        const string sourceOu = "OU=Ateliers," + ParisOu;
        var observed = Observed(Computer, ComputerGuid, sourceOu);
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] }, ScopeNames = [Computer],
            Find = name => name.Equals(observed.Name, StringComparison.OrdinalIgnoreCase) ? observed : null,
        };
        var mutation = new FakeMutationGateway
        {
            Respond = request =>
            {
                Check.Equal("rename", request.Kind, "Aucun Move-ADObject ne peut être demandé sur le même site");
                observed = observed with { Name = request.NewName! };
                return new MutationOutcome(MutationStatus.PendingRestart, 20, "Renommage seul", true);
            },
        };
        var b = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), gateway, mutation, new FixedClock());
        var preview = Harness.Call(b, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var previewId = Harness.Str(preview, "previewId");
        Check.Pesto(() => Harness.Call(b, "operation.prepare", new { kind = "renameMove", computer = Computer, previewId, targetOU = ParisOu }),
            "rename.no_move", "Une sous-OU n’est pas remontée à la racine du site");
        var plan = Harness.Call(b, "operation.prepare", new { kind = "renameMove", computer = Computer, previewId });
        Check.Equal("rename", Harness.Str(plan, "kind"), "La règle métier est portée par le moteur, même sur appel API direct");
        Check.Equal(sourceOu, Harness.Str(plan, "targetOU"), "La sous-OU observée est conservée");
        var receipt = Harness.Call(b, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        Check.Equal("20", Harness.Str(receipt, "code"), "Renommage seul, pas faux code77 de déplacement");
        Check.Equal("rename", Harness.Str(receipt, "kind"), "Reçu conforme à l’opération effectivement admise");
        Check.Equal(sourceOu, observed.Ou, "La sous-OU reste inchangée");

        var next = Harness.Call(b, "names.preview", new { type = "P", site = "PA", service = "INF", computer = observed.Name });
        var queue = Harness.Call(b, "queue.add", new { kind = "renameMove", computer = observed.Name, previewId = Harness.Str(next, "previewId") });
        Check.Equal("rename", Harness.Str(Harness.Arr(queue, "items")[0]!, "kind"), "Le lot utilise aussi le type normalisé");
        Check.Equal(sourceOu, Harness.Str(Harness.Arr(Harness.Call(b, "queue.prepare"), "items")[0]!, "targetOU"), "Le lot ne réintroduit pas de déplacement");
    }

    [Test]
    public void PrepareRefusesExpiredOrSupersededPreviews()
    {
        var (w, previewId, _) = WithPreview(LiveWorld(false), computer: Computer);
        w.Clock.Advance(TimeSpan.FromMinutes(6));
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId }),
            "plan.stale", "Aperçu expiré : nouvel aperçu + nouveau clic, jamais de poursuite avec une lecture périmée");

        var w2 = LiveWorld(true);
        var first = Harness.Call(w2.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var second = Harness.Call(w2.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        Check.Pesto(() => Harness.Call(w2.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(first, "previewId") }),
            "plan.stale", "Un calcul plus récent a remplacé cet aperçu : le moteur ne reprend que le dernier");
        var plan = Harness.Call(w2.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(second, "previewId") });
        Check.False(string.IsNullOrEmpty(Harness.Str(plan, "planId")), "Le dernier aperçu fonde bien le plan");
    }

    [Test]
    public void PrepareRefusesANameTakenAfterThePreview()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(false), computer: Computer);
        // Le nom de l'aperçu apparaît dans l'annuaire entre l'aperçu et la préparation (compte d'un autre technicien).
        w.Gateway.Find = n => n.Equals(Computer, StringComparison.OrdinalIgnoreCase) ? Observed(Computer)
            : n.Equals(name, StringComparison.OrdinalIgnoreCase) ? Observed(name, "22222222-2222-2222-2222-222222222222")
            : null;
        var error = Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId }),
            "name.taken", "Collision après l'aperçu : refus motivé à la préparation");
        Check.Contains("nouvel aperçu", error.Message, "La raison renvoie vers un nouvel aperçu et un nouveau clic, jamais un ajout automatique");
    }

    [Test]
    public void PrepareMoveNeedsAnObservedTargetOuAndKeepsTheName()
    {
        var w = LiveWorld(false);
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "PA" });
        Check.Equal(Computer, Harness.Str(plan, "newName"), "Déplacement seul : le nom ne change pas");
        Check.Equal(Computer, Harness.Str(plan, "confirmationName"), "La confirmation porte sur le nom du poste");
        Check.Equal(ParisOu, Harness.Str(plan, "targetOU"), "Destination = OU réellement observée du site choisi");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "move", computer = Computer }),
            "invalid_arguments", "Sans destination, pas de déplacement");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "OU=Fantome," + Container }),
            "site.invalid", "Un OU non observé n'est jamais admis comme destination");
    }

    // ---- exécution sans adaptateur qualifié : refus total, aucun reçu fictif -------------

    [Test]
    public void ExecuteWithoutQualifiedAdapterRefusesEveryWrite()
    {
        var w = LiveWorld(false);
        var name = Computer;
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "PA" });
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = "mal" }),
            "confirmation.invalid", "La confirmation exacte est vérifiée avant même le refus d'écriture");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name }),
            "write.unavailable", "Sans adaptateur de mutation qualifié Windows/AD, rien n'est jamais envoyé");
        Check.Equal(0, Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Count, "Aucun reçu fictif : un refus d'envoi n'est pas un envoi");
        Check.Pesto(() => Harness.Call(w.Backend, "receipts.get", new { id = "receipt-1" }), "receipt.missing", "Aucun reçu à consulter");
        // Le plan n'a jamais été envoyé : il reste consultable mais l'exécution refuse toujours autant.
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name }),
            "write.unavailable", "Refus répété, jamais d'envoi différé automatique");

        // Depuis le lot file live : l'ajout et la préparation sont lecture seule (aucune écriture, aucun reçu) ;
        // seule l'exécution du lot touche l'adaptateur — elle reste refusée sans adaptateur qualifié.
        var w2 = LiveWorld(false);
        var queued = Harness.Call(w2.Backend, "queue.add", new { kind = "move", computer = Computer, targetOU = "PA" });
        Check.Equal(1, Harness.Int(queued, "count"), "La file réelle existe : l'ajout stocke la ligne validée, sans écrire");
        var batch = Harness.Call(w2.Backend, "queue.prepare");
        Check.Equal(1, Harness.Arr(batch, "items").Count, "La préparation forge un plan par ligne relue contre l'annuaire");
        Check.Pesto(() => Harness.Call(w2.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }),
            "write.unavailable", "L'exécution du lot reste fermée sans adaptateur de mutation qualifié");
        Check.Equal(0, Harness.Arr(Harness.Call(w2.Backend, "receipts.list"), "items").Count, "Aucun reçu fictif : un refus d'envoi n'est pas un envoi");
        Check.Equal(1, Harness.Int(Harness.Call(w2.Backend, "queue.list"), "count"), "Le refus avant envoi ne consomme rien : la file est intacte");
    }

    [Test]
    public void ExecuteRefusesUnknownOrExpiredPlans()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = "plan-inconnu", confirmationName = name }),
            "plan.stale", "Plan inconnu refusé");
        w.Clock.Advance(TimeSpan.FromMinutes(6));
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name }),
            "plan.stale", "Plan expiré : on repasse par un nouvel aperçu et un nouveau clic");
    }

    // ---- cycle du harnais de qualification : reçu avant envoi, relecture, jamais de rejeu --

    [Test]
    public void QualifiedSendConsumesOnceWritesReceiptThenReReads()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name });
        Check.Equal("succeeded", Harness.Str(receipt, "status"), "Adaptateur d'accord ET relecture annuaire d'accord : seul cas « réussi »");
        Check.Equal("rename", Harness.Str(receipt, "kind"), "Type de l'action");
        Check.Equal(Computer, Harness.Str(receipt, "computer"), "Poste d'origine");
        Check.Equal(name, Harness.Str(receipt, "newName"), "Nouveau nom");
        Check.Contains("live", Harness.Str(receipt, "mode"), "Mode réel annoncé");
        Check.Contains("fixture", Harness.Str(receipt, "mode"), "La source de l'envoi est celle injectée, jamais une origine cachée");
        Check.Equal(1, w.Mutation!.Requests.Count, "Un seul appel à l'adaptateur");
        Check.Equal(ComputerGuid, w.Mutation.Requests[0].ComputerGuid, "Le GUID observé à la préparation est transmis");
        Check.Equal(name, w.Mutation.Requests[0].NewName, "Le nom confirmé est transmis");
        Check.False(string.IsNullOrEmpty(w.Mutation.Requests[0].ReceiptId), "Le reçu est lié à la demande avant l'envoi");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name }),
            "plan.consumed", "Consommation unique : un plan admis ne peut plus être rejoué");
        Check.Equal(1, w.Mutation.Requests.Count, "Le second appel n'a jamais eu lieu");
        var listed = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items");
        Check.Equal(1, listed.Count, "Le reçu de session est consultable");
        Check.Equal(Harness.Str(receipt, "id"), Harness.Str(Harness.Call(w.Backend, "receipts.get", new { id = Harness.Str(receipt, "id") }), "id"), "reçu rechargé par identifiant");
    }

    [Test]
    public void UncertainResultIsKeptAndNeverReplayed()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        w.Mutation!.Throw = new InvalidOperationException("panne réseau après envoi possible");
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name });
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "Résultat inconnu : jamais présenté comme réussi ni comme échec");
        Check.Contains("jamais rejoué automatiquement", Harness.Str(receipt, "message"), "La raison interdit explicitement le rejeu automatique");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name }),
            "plan.consumed", "Même incertain, le plan est consommé : aucune nouvelle tentative automatique");
        Check.Equal(1, w.Mutation.Requests.Count, "L'adaptateur n'a jamais été rappelé");
    }

    [Test]
    public void SuccessClaimedButNotSeenByRereadStaysUncertain()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        w.Mutation!.Respond = _ => new(Pesto.Engine.MutationStatus.Succeeded, 0, "crash avant d'appliquer", false);
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name });
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "L'adaptateur confirme mais la relecture non plus : le moteur ne jure que par l'annuaire");
    }

    [Test]
    public void SuccessRequiresTheExactFinalNameGuidAndPlacement()
    {
        foreach (var scenario in new[] { "rename-name", "rename-ou", "move-name", "join-guid" })
        {
            var w = LiveWorld(true);
            var kind = scenario.StartsWith("move", StringComparison.Ordinal) ? "move"
                : scenario.StartsWith("join", StringComparison.Ordinal) ? "join" : "rename";
            var preview = kind == "move" ? null : WithPreview(w, computer: kind == "join" ? null : Computer).PreviewId;
            var plan = Harness.Call(w.Backend, "operation.prepare", kind == "move"
                ? (object)new { kind, computer = Computer, targetOU = "PA" }
                : kind == "join" ? new { kind, previewId = preview } : new { kind, computer = Computer, previewId = preview });
            w.Mutation!.Respond = request =>
            {
                var expectedName = request.Kind == "move" ? request.Computer : request.NewName!;
                // Model CN/sAM alias resolution or a concurrent change after the native adapter's own check.
                var observed = Observed(scenario.EndsWith("name", StringComparison.Ordinal) ? "AUTRE-NOM" : expectedName,
                    scenario == "join-guid" ? null : ComputerGuid,
                    scenario == "rename-ou" ? "OU=Lyon," + Container : request.TargetOu);
                w.Gateway.Find = _ => observed;
                return new MutationOutcome(MutationStatus.Succeeded, 0, "Succès annoncé par la fixture.", false);
            };
            var execute = new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") };
            var receipt = Harness.Call(w.Backend, "operation.execute", execute);
            Check.Equal("uncertain", Harness.Str(receipt, "status"), scenario + " : une identité/OU finale divergente ne vaut pas confirmation");
            Check.Equal(1, w.Mutation.Requests.Count, "Un seul envoi est conservé");
            Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", execute), "plan.consumed", "Le résultat incertain ne rend pas le plan rejouable");
        }
    }

    [Test]
    public void PlanExpiryDuringFinalDirectoryReadsPreventsTheSend()
    {
        foreach (var kind in new[] { "rename", "move", "join" })
        {
            var w = LiveWorld(true);
            var preview = kind == "move" ? null : WithPreview(w, computer: kind == "join" ? null : Computer).PreviewId;
            var plan = Harness.Call(w.Backend, "operation.prepare", kind == "move"
                ? (object)new { kind, computer = Computer, targetOU = "PA" }
                : kind == "join" ? new { kind, previewId = preview } : new { kind, computer = Computer, previewId = preview });
            var originalFind = w.Gateway.Find!;
            w.Gateway.Find = name => { w.Clock.Advance(TimeSpan.FromMinutes(6)); return originalFind(name); };
            Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new
            {
                planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName")
            }), "plan.stale", "Une lecture lente ne prolonge pas l’autorisation confirmée : " + kind);
            Check.Equal(0, w.Mutation!.Requests.Count, "Aucun appel natif après expiration pendant les dernières lectures");
            Check.Equal(0, Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Count, "Aucun reçu d’envoi fictif n’est créé");
        }
    }

    [Test]
    public void ConfigurationChangedDuringFinalDirectoryReadPreventsTheSend()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        var originalFind = w.Gateway.Find!;
        var changed = false;
        w.Gateway.Find = requested =>
        {
            if (!changed) { File.AppendAllText(Path.Combine(w.ConfigurationRoot, "cfg.json"), "\n"); changed = true; }
            return originalFind(requested);
        };
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name }),
            "config.changed", "Le plan ne reste pas autorisé si le fichier change pendant la dernière lecture");
        Check.Equal(0, w.Mutation!.Requests.Count, "Aucune demande transmise avec l’ancienne empreinte");
        Check.Equal(0, Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Count, "Un refus avant envoi n’est pas enregistré comme mutation");
    }

    [Test]
    public void RefusalBeforeSendIsRefusedAndRestartIsPendingRestart()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        w.Mutation!.Respond = _ => new(Pesto.Engine.MutationStatus.Failed, 5, "Refus avant envoi (fixture)", false);
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name });
        Check.Equal("refused", Harness.Str(receipt, "status"), "Refus avant envoi, relecture conforme : rien n'a été écrit");
        Check.Contains("Refus avant envoi", Harness.Str(receipt, "message"), "Le message de l'adaptateur est conservé, borné et sans secret");

        var (w2, previewId2, name2) = WithPreview(LiveWorld(true), computer: Computer);
        // La fixture n'applique rien : l'objet attend le redémarrage que l'opérateur planifie lui-même.
        w2.Mutation!.Respond = _ => new(Pesto.Engine.MutationStatus.PendingRestart, 10, "Accepté, redémarrage à planifier (fixture)", true);
        var plan2 = Harness.Call(w2.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = previewId2 });
        var receipt2 = Harness.Call(w2.Backend, "operation.execute", new { planId = Harness.Str(plan2, "planId"), confirmationName = name2 });
        Check.Equal("pendingRestart", Harness.Str(receipt2, "status"), "Port de la phase v1 PendingRestart (exit 10)");
        Check.True(Harness.Bool(receipt2, "restartRequired"), "Redémarrage requis, jamais déclenché par Pesto");
    }

    [Test]
    public void IdentityOrAvailabilityMovedBeforeSendStopsEverything()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true), computer: Computer);
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId });
        w.Gateway.Find = n => n.Equals(Computer, StringComparison.OrdinalIgnoreCase)
            ? Observed(Computer, "99999999-9999-9999-9999-999999999999")
            : null;
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name }),
            "identity.changed", "Le GUID a bougé entre préparation et envoi : rien n'est appliqué");
        Check.Equal(0, w.Mutation!.Requests.Count, "L'adaptateur n'a jamais été appelé");

        var (w2, previewId2, name2) = WithPreview(LiveWorld(true), computer: Computer);
        var plan2 = Harness.Call(w2.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = previewId2 });
        w2.Gateway.ScopeNames = [.. w2.Gateway.ScopeNames, name2];
        var squatter = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { name2 };
        w2.Gateway.Find = n => n.Equals(Computer, StringComparison.OrdinalIgnoreCase) ? Observed(Computer)
            : squatter.Contains(n) ? Observed(n, "88888888-8888-8888-8888-888888888888") : null;
        Check.Pesto(() => Harness.Call(w2.Backend, "operation.execute", new { planId = Harness.Str(plan2, "planId"), confirmationName = name2 }),
            "name.taken", "Le nom vient d'être pris juste avant l'envoi : refus, nouvel aperçu, nouveau clic");
        Check.Equal(0, w2.Mutation!.Requests.Count, "Aucun envoi sur une disponibilité périmée");
    }

    [Test]
    public void JoinSendIsLocalOnlyAndBindsTheObservedName()
    {
        var (w, previewId, name) = WithPreview(LiveWorld(true));
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "join", previewId });
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = name });
        Check.Equal("succeeded", Harness.Str(receipt, "status"), "Jonction locale appliquée et relue (objet présent après envoi)");
        Check.Equal(Environment.MachineName, w.Mutation!.Requests[0].Computer, "La jonction ne porte que sur ce poste");
        Check.True(w.Mutation.Requests[0].TargetOu!.StartsWith("OU=Paris-Nord,", StringComparison.Ordinal), "La destination est l'OU observée de l'aperçu");
    }
}

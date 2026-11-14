using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>
/// Écrit dans un dossier GP temporaire les deux formats que le moteur doit relire sans jamais rien effacer :
/// le reçu durable de l'adaptateur (même format que PowerShellMutationGateway.WritePreSendReceipt) et le reçu
/// d'intervention V1 du registre %ProgramData%\GP\Interventions (schéma fermé de Read-PestoIntervention).
/// </summary>
internal sealed class GpFixture
{
    public string Root { get; } = Path.Combine(Path.GetTempPath(), "pesto-gp-" + Guid.NewGuid().ToString("N"));

    public GpFixture() => Directory.CreateDirectory(Root);

    public string AdapterReceipt(string receiptId, string phase, DateTimeOffset utc, string kind = "rename",
        string computer = "P111301PAINF009", string? newName = "P111301PAINF010",
        string? targetOu = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local", int code = 0,
        string message = "Reçu de qualification", bool restart = false, string adapter = "fixture d’adaptateur")
        => AdapterRaw(receiptId, JsonSerializer.Serialize(new Dictionary<string, object?>
        {
            ["Schema"] = 1, ["Version"] = "2.0", ["Phase"] = phase, ["Utc"] = utc.ToString("o"), ["Adapter"] = adapter,
            ["ReceiptId"] = receiptId, ["PlanId"] = "plan-x", ["Kind"] = kind, ["Computer"] = computer,
            ["NewName"] = newName, ["TargetOu"] = targetOu, ["Code"] = code, ["Message"] = message, ["RestartRequired"] = restart,
        }));

    public string AdapterRaw(string receiptId, string json)
    {
        var folder = Path.Combine(Root, "V2", "receipts");
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, receiptId + ".json");
        File.WriteAllText(path, json, new UTF8Encoding(false));
        return path;
    }

    public string V1Intervention(Guid operationId, string phase, bool rename = true, bool move = false,
        string? updatedUtc = "2026-10-23T07:00:00+00:00", int resultCode = 10, string? acknowledged = null)
        => V1Raw(operationId, V1Json(operationId, phase, rename, move, updatedUtc, resultCode, acknowledged));

    public string V1Raw(Guid operationId, string json)
    {
        var folder = Path.Combine(Root, "Interventions");
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, operationId.ToString("N") + ".json");
        File.WriteAllText(path, json, new UTF8Encoding(false));
        return path;
    }

    public static string V1Json(Guid operationId, string phase, bool rename, bool move, string? updatedUtc, int resultCode, string? acknowledged)
    {
        const string ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";
        var plan = $$"""
        {"Nom_du_PC":"P111301PAINF009","Nouveau_Nom":"P111301PAINF010","OU_Actuelle":"{{ou}}","OU_Destination":"{{ou}}","Objet_GUID":"11111111-1111-1111-1111-111111111111","Domain":"example.local","DC":"dc01.example.local","ConfigStamp":"stamp","TargetOUGuid":null,"Renommer":{{(rename ? "true" : "false")}},"Deplacer":{{(move ? "true" : "false")}},"Reboot":false,"Reference":null}
        """;
        var timeline = """
        [{"Sequence":1,"Utc":"2026-10-23T06:59:00+00:00","Stage":"Start","State":"Running"}]
        """;
        return $$"""
        {"Schema":1,"Version":"1.0","OperationId":"{{operationId}}","Plan":{{plan}},"StartedUtc":"2026-10-23T06:58:00+00:00","UpdatedUtc":{{(updatedUtc is null ? "null" : "\"" + updatedUtc + "\"")}},"Phase":"{{phase}}","InitialProtection":true,"TargetMachineId":null,"TargetOUGuid":null,"Entra":"NotRequested","Protection":"Restored","Rename":"{{(rename ? "Confirmed" : "NotRequested")}}","Move":"{{(move ? "Confirmed" : "NotRequested")}}","ResultCode":{{resultCode}},"ResultMessage":"Suivi qualification","LastStage":"Rename","VerifiedUtc":null,"VerifiedBy":null,"ResumeFrom":null,"PlanFingerprint":null,"Sequence":1,"Timeline":{{timeline}},"Coordination":null,"Tasks":[],"Legacy":null,"Baseline":null,"LastObservation":null,"JoinEvidence":null,"Metadata":null,"Acknowledged":{{acknowledged ?? "null"}},"Attributes":null,"AttributeChanges":null,"OfflineJoin":null}
        """;
    }
}

/// <summary>Adaptateur de mutation de qualification : écrit le reçu durable AVANT la commande (ici la réponse de fixture),
/// le complète après, exactement au format de PowerShellMutationGateway — c'est ce fichier que le moteur doit relire après redémarrage.</summary>
internal sealed class WritingMutationGateway : Pesto.Engine.IMutationGateway, Pesto.Engine.IMutationReceiptFinalizer, IFixtureEntraPreparation
{
    public required string GpRoot { get; init; }
    public bool FailFinalization { get; init; }
    public string Description => "fixture d’adaptateur écrivant des reçus durables (format PowerShellMutationGateway)";
    public Func<Pesto.Engine.MutationRequest, Pesto.Engine.MutationOutcome> Respond = _ =>
        new(Pesto.Engine.MutationStatus.Succeeded, 0, "OK fixture", false);

    public Pesto.Engine.MutationOutcome Execute(Pesto.Engine.MutationRequest request)
    {
        var folder = Path.Combine(GpRoot, "V2", "receipts");
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, request.ReceiptId + ".json");
        Write(path, "Running", 0, "Demande préparée, reçu écrit avant la commande native, résultat non encore reçu.", false);
        var outcome = Respond(request);
        Write(path, "Uncertain", 97, "Résultat natif en attente de la relecture moteur", outcome.RestartRequired);
        return outcome;
    }

    public void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome)
    {
        if (FailFinalization) throw new IOException("Fixture : disque indisponible");
        var phase = outcome.Status switch { MutationStatus.Succeeded => "Verified", MutationStatus.PendingRestart => "PendingRestart", MutationStatus.Failed => "Failed", _ => "Uncertain" };
        Write(Path.Combine(GpRoot, "V2", "receipts", request.ReceiptId + ".json"), phase, outcome.Code, outcome.Message, outcome.RestartRequired);
    }

    private void Write(string path, string phase, int code, string message, bool restart) => File.WriteAllText(path, JsonSerializer.Serialize(new Dictionary<string, object?>
    {
        ["Schema"] = 1, ["Version"] = "2.0", ["Phase"] = phase, ["Utc"] = DateTimeOffset.UtcNow.ToString("o"), ["Adapter"] = Description,
        ["ReceiptId"] = path.EndsWith(".json") ? Path.GetFileNameWithoutExtension(path) : "", ["PlanId"] = "plan-x", ["Kind"] = "rename",
        ["Computer"] = "P111301PAINF009", ["NewName"] = "P111301PAINF010", ["TargetOu"] = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local",
        ["Code"] = code, ["Message"] = message, ["RestartRequired"] = restart,
    }), new UTF8Encoding(false));
}

/// <summary>
/// Constats 3 et 4 de la revue du 24/10 : le tableau de bord réel est un lecteur (gateway annuaire injecté + registre
/// durable GP relu), plus une constante null/listes vides ; l'historique des reçus survit au redémarrage, sans effacement
/// ni fusion arbitraire. Les tests échouent réellement si dashboard.read redevient une constante ou si l'historique lu est ignoré.
/// </summary>
internal sealed class LiveDashboardHistoryTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string Computer = "P111301PAINF009";
    private const string ComputerGuid = "11111111-1111-1111-1111-111111111111";

    private sealed class World
    {
        public required IPestoBackend Backend { get; set; }
        public required FakeGateway Gateway { get; init; }
        public required GpFixture Gp { get; init; }
        public required FixedClock Clock { get; init; }
        public Dictionary<string, DirectoryComputer> Machines = new(StringComparer.OrdinalIgnoreCase);
    }

    private static World LiveWorld(string? gpRoot = null, bool withWritingAdapter = false, bool overrideGp = false, params string[] scopeNames)
    {
        var gp = new GpFixture();
        var effectiveGp = overrideGp ? gpRoot : gpRoot ?? gp.Root; // overrideGp=true permet le null explicite (aucun registre)
        var machines = new Dictionary<string, DirectoryComputer>(StringComparer.OrdinalIgnoreCase)
        {
            [Computer] = new(Computer, null, ParisOu, null, ComputerGuid, "example.local", null, null, null, null, null),
        };
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord", "Lyon"] },
            ScopeNames = [.. scopeNames],
            Find = name => machines.TryGetValue(name, out var c) ? c : null,
        };
        var clock = new FixedClock();
        Pesto.Engine.IMutationGateway? mutation = null;
        if (withWritingAdapter)
        {
            var writer = new WritingMutationGateway { GpRoot = effectiveGp ?? gp.Root };
            writer.Respond = request =>
            {
                if (machines.TryGetValue(request.Computer, out var c))
                {
                    machines.Remove(request.Computer);
                    machines[request.NewName!] = c with { Name = request.NewName!, Ou = request.TargetOu ?? c.Ou };
                }
                return new(Pesto.Engine.MutationStatus.Succeeded, 0, "OK fixture", false);
            };
            mutation = writer;
        }
        return new World
        {
            Backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), gateway, mutation, clock, effectiveGp),
            Gateway = gateway,
            Gp = gp,
            Clock = clock,
            Machines = machines,
        };
    }

    private static DateTimeOffset T(int minutes) => new(2026, 10, 23, 7, minutes, 0, TimeSpan.Zero);

    // ---- constat 3 : le tableau de bord est un lecteur, pas une constante -------------------------------

    [Test]
    public void DashboardWithoutAdapterIsRefusedWithActionableReason()
    {
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid));
        var error = Check.Pesto(() => Harness.Call(backend, "dashboard.read"), "directory.unavailable",
            "Plus de null/listes vides constants : sans adaptateur annuaire, le lecteur du tableau de bord refuse avec raison");
        Check.Contains("adaptateur annuaire", error.Message, "La raison dit quoi injecter et pourquoi");
    }

    [Test]
    public void DashboardWithoutConfigIsRefused()
    {
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] } };
        Check.Pesto(() => Harness.Call(Harness.Live(null, gateway), "dashboard.read"), "config.missing",
            "Aucun tableau de bord fictif sans configuration V1 lue");
    }

    [Test]
    public void DashboardCountsComeFromTheObservedInventory()
    {
        var w = LiveWorld(scopeNames: ["P111301PAINF001", "P111301PAINF002", "S111301PAINF003", "V111301LYINF001", "HORSNOM"]);
        var d = Harness.Call(w.Backend, "dashboard.read");
        Check.Equal(5, Harness.Int(d, "computers"), "Postes suivis = inventaire réellement lu de la racine gérée (borné 20 000)");
        Check.True(Harness.IsNull(d, "availableNames"), "La disponibilité n'est pas un fait global : null, jamais un compteur inventé");
        var sites = Harness.Arr(d, "sites");
        Check.Equal(2, sites.Count, "Sites déclarés ET réellement observés dans l'annuaire");
        Check.Equal(3, Harness.Int(sites[0]!, "count"), "Paris-Nord : 3 noms que la convention reconnaît comme PA");
        Check.Equal(1, Harness.Int(sites[1]!, "count"), "Lyon : 1 nom LY observé ; HORSNOM ne compte dans aucun site");
        Check.Equal(20000, w.Gateway.LastMaxRows!.Value, "Lecture d’inventaire bornée par le plafond dur");
    }

    [Test]
    public void DashboardCountersAreNullWhenTheInventoryIsIncomplete()
    {
        var w = LiveWorld(scopeNames: ["P111301PAINF001"]);
        w.Gateway.NamesComplete = false;
        var d = Harness.Call(w.Backend, "dashboard.read");
        Check.True(Harness.IsNull(d, "computers"), "Lecture incomplète = inconnu : jamais un compteur partiel présenté comme un total");
        var sites = Harness.Arr(d, "sites");
        Check.True(Harness.IsNull(sites[0]!, "count"), "Compte de site inconnu lui aussi, jamais 0 par défaut");
        Check.Equal(0, Harness.Int(d, "pendingRestart"), "Les compteurs d'après reçus restent des faits lus (registre vide lu = 0)");
    }

    [Test]
    public void DashboardPendingRestartAndUncertainComeFromPersistentReceipts()
    {
        var w = LiveWorld();
        w.Gp.AdapterReceipt("receipt-a", "PendingRestart", T(1), restart: true);
        w.Gp.AdapterReceipt("receipt-b", "PendingRestart", T(2), restart: true);
        w.Gp.AdapterReceipt("receipt-c", "Uncertain", T(3), code: 97);
        w.Gp.AdapterReceipt("receipt-d", "Verified", T(4));
        w.Gp.AdapterReceipt("receipt-e", "Failed", T(5), code: 31);
        var d = Harness.Call(w.Backend, "dashboard.read");
        Check.Equal(2, Harness.Int(d, "pendingRestart"), "Deux reçus durables PendingRestart réellement lus (port exit 10/20 v1)");
        Check.Equal(1, Harness.Int(d, "uncertain"), "Un seul reçu incertain : le refus prouvé et le succès ne comptent pas comme à vérifier");
        Check.Equal(5, Harness.Arr(d, "lastActivity").Count, "Dernières interventions = reçus durables relus, pas une liste vide constante");
        var history = d["history"]!.AsObject();
        Check.True(history["readable"]!.GetValue<bool>(), "Le registre durable est déclaré lu");
        Check.Equal(5, history["validCount"]!.GetValue<int>(), "Les cinq reçus lisibles sont comptés");
        Check.Equal(0, history["invalidCount"]!.GetValue<int>(), "Aucun fichier illisible dans ce monde");
    }

    [Test]
    public void DashboardLastActivityIsNewestFirstFromTheDurableLedger()
    {
        var w = LiveWorld();
        w.Gp.AdapterReceipt("receipt-old", "Verified", T(1));
        w.Gp.AdapterReceipt("receipt-new", "Verified", T(3));
        w.Gp.AdapterReceipt("receipt-mid", "Failed", T(2), code: 31);
        var items = Harness.Arr(Harness.Call(w.Backend, "dashboard.read"), "lastActivity");
        Check.Equal("receipt-new", Harness.Str(items[0]!, "id"), "Le plus récent d'abord (tri v1 Updated descending)");
        Check.Equal("receipt-mid", Harness.Str(items[1]!, "id"), "Puis le milieu, puis l'ancien : ordre réellement trié, pas l'ordre du disque");
        Check.Equal("receipt-old", Harness.Str(items[2]!, "id"), "Troisième reçu durable relu");
    }

    [Test]
    public void AcknowledgedUncertainReceiptIsNotCountedAsToVerify()
    {
        var w = LiveWorld();
        w.Gp.V1Intervention(Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"), "Uncertain",
            acknowledged: """{"Schema":1,"By":"EXAMPLE\\operateur","Utc":"2026-10-23T07:30:00+00:00","Reason":"vérifié à la main","Phase":"Uncertain","ResultCode":10,"Observation":null}""");
        var d = Harness.Call(w.Backend, "dashboard.read");
        Check.Equal(0, Harness.Int(d, "uncertain"), "Un reçu acquitté garde son état réel mais ne compte plus dans « à vérifier » (port v1)");
        var item = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Single()!;
        Check.True(Harness.Bool(item, "acknowledged"), "La ligne affiche l’acquittement, le reçu n’est pas transformé");
        Check.Equal("uncertain", Harness.Str(item, "status"), "Le statut réel du reçu est conservé");
    }

    [Test]
    public void MalformedAcknowledgementCannotHideAnUncertainReceipt()
    {
        foreach (var ack in new[] { "{}", "{\"By\":\"someone\"}", "{\"Schema\":1,\"Utc\":\"2026-10-23T07:30:00Z\",\"By\":\"EXAMPLE/operator\",\"Reason\":\"manual verification\",\"Phase\":\"PendingRestart\",\"ResultCode\":10,\"Observation\":null}" })
        {
            var w = LiveWorld();
            w.Gp.V1Intervention(Guid.NewGuid(), "Uncertain", acknowledged: ack);
            Check.Equal(1, Harness.Int(Harness.Call(w.Backend, "dashboard.read"), "uncertain"), "Acquittement malformé ou visant une autre phase : toujours à vérifier");
            var item = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Single()!;
            Check.False(Harness.Bool(item, "acknowledged"), "Même validation que la barrière de mutation");
        }
    }

    [Test]
    public void EngineReadbackDowngradeSurvivesBackendRestart()
    {
        var gp = new GpFixture();
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] }, Find = name => name == Computer ? new DirectoryComputer(name, null, ParisOu, null, ComputerGuid, "example.local", null, null, null, null, null) : null };
        var writer = new WritingMutationGateway { GpRoot = gp.Root, Respond = _ => { gateway.FailOn = "find"; return new(MutationStatus.Succeeded, 20, "Renommage accepté", true); } };
        var configRoot = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var backend = Harness.Live(configRoot, gateway, writer, null, gp.Root);
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var plan = Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") });
        var receipt = Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "Panne de relecture après acceptation");
        var restarted = Harness.Live(configRoot, gateway, null, null, gp.Root);
        var durable = Harness.Call(restarted, "receipts.get", new { id = Harness.Str(receipt, "id") });
        Check.Equal("uncertain", Harness.Str(durable, "status"), "Le disque conserve la décision finale du moteur après redémarrage");
        Check.True(Harness.Bool(durable, "restartRequired"), "Le redémarrage connu reste visible");
    }

    [Test]
    public void FailedFinalReceiptPersistenceCannotBecomeSuccess()
    {
        var gp = new GpFixture();
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] }, Find = name => name == Computer ? new DirectoryComputer(name, null, ParisOu, null, ComputerGuid, "example.local", null, null, null, null, null) : null };
        var writer = new WritingMutationGateway { GpRoot = gp.Root, FailFinalization = true, Respond = request => { gateway.Find = name => name == request.NewName ? new DirectoryComputer(name, null, ParisOu, null, ComputerGuid, "example.local", null, null, null, null, null) : null; return new(MutationStatus.Succeeded, 20, "Renommage accepté", true); } };
        var configRoot = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var backend = Harness.Live(configRoot, gateway, writer, null, gp.Root);
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var plan = Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") });
        var receipt = Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        Check.Equal("uncertain", Harness.Str(receipt, "status"), "Résultat non persisté reste incertain");
        var restarted = Harness.Live(configRoot, gateway, null, null, gp.Root);
        Check.Equal("uncertain", Harness.Str(Harness.Call(restarted, "receipts.get", new { id = Harness.Str(receipt, "id") }), "status"), "Le reçu préalable conservateur reste incertain sur disque");
    }

    // ---- constat 4 : l'historique durable survit au redémarrage, sans effacement ni fusion arbitraire ----

    [Test]
    public void PersistentReceiptsSurviveARestart()
    {
        var gp = new GpFixture();
        gp.AdapterReceipt("receipt-persiste", "Verified", T(1));
        var w = LiveWorld(gp.Root);
        var listed = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items");
        Check.Equal(1, listed.Count, "Reçu de l’adaptateur écrit avant redémarrage, relu après redémarrage");
        Check.Equal("receipt-persiste", Harness.Str(listed[0]!, "id"), "Identifiant du fichier durable conservé");
        Check.Equal("succeeded", Harness.Str(listed[0]!, "status"), "Phase Verified mappée en succeeded");
        Check.Contains("adaptateur", Harness.Str(listed[0]!, "mode"), "La source du reçu est annoncée");
        var one = Harness.Call(w.Backend, "receipts.get", new { id = "receipt-persiste" });
        Check.Equal("receipt-persiste", Harness.Str(one, "id"), "receipts.get relit aussi le registre durable");
        Check.Pesto(() => Harness.Call(w.Backend, "receipts.get", new { id = "receipt-introuvable" }), "receipt.missing",
            "Introuvable partout = receipt.missing motivé, jamais un reçu vide");
    }

    [Test]
    public void UnreadableReceiptIsIsolatedNeverDeletedNeverIgnored()
    {
        var gp = new GpFixture();
        var badPath = gp.AdapterRaw("receipt-casse", "{ ceci n’est pas du json ");
        gp.AdapterReceipt("receipt-sain", "Verified", T(1));
        var w = LiveWorld(gp.Root);
        var listed = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items");
        Check.Equal(2, listed.Count, "Le fichier illisible est une ligne à part, jamais fondu ni ignoré (port Get-PestoInterventionCatalogue)");
        var bad = listed.Single(r => Harness.Str(r!, "id") == "invalid:receipt-casse.json")!;
        Check.False(Harness.Bool(bad, "readable"), "Ligne marquée illisible");
        Check.Equal("unreadable", Harness.Str(bad, "status"), "Statut distinct des reçus lus");
        Check.Contains("Aucun verrou levé", Harness.Str(bad, "message"), "Raison v1 : aucun verrou supprimé par la lecture");
        Check.True(Harness.IsNull(bad, "time"), "Pas de date lue = null, jamais 1970");
        Check.Equal(1, Harness.Int(Harness.Call(w.Backend, "receipts.list"), "invalidCount"), "Compteur de fichiers illisibles rendu");
        Check.True(File.Exists(badPath), "Le moteur ne supprime, ne déplace ni ne réécrit aucun fichier du registre");
    }

    [Test]
    public void V1LedgerReceiptsAreReadAndMappedForDisplay()
    {
        var gp = new GpFixture();
        gp.V1Intervention(Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"), "PendingRestart", rename: true, move: false, resultCode: 10);
        var w = LiveWorld(gp.Root);
        var item = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items").Single()!;
        Check.Equal("pendingRestart", Harness.Str(item, "status"), "Phase V1 PendingRestart → redémarrage en attente");
        Check.Equal("rename", Harness.Str(item, "kind"), "Plan Renommer=true/Deplacer=false → renommage");
        Check.Contains("V1", Harness.Str(item, "mode"), "Le mode annonce un reçu V1 relu du registre local, jamais un reçu v2");
        Check.Equal("10", Harness.Str(item, "code"), "ResultCode conservé");
        Check.True(Harness.Bool(item, "restartRequired"), "PendingRestart exige le redémarrage que l’opérateur planifie lui-même");
        Check.Equal("P111301PAINF009", Harness.Str(item, "computer"), "Poste du plan V1");
        Check.Equal("P111301PAINF010", Harness.Str(item, "newName"), "Nom prévu du plan V1");
        var d = Harness.Call(w.Backend, "dashboard.read");
        Check.Equal(1, Harness.Int(d, "pendingRestart"), "Le registre V1 compte dans le tableau de bord");
    }

    [Test]
    public void V1ReaderRejectsInvalidLedgerEntriesLikeTheStrictV1Reader()
    {
        var gp = new GpFixture();
        var id = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");
        gp.V1Raw(id, GpFixture.V1Json(id, "TOTO", true, false, null, 0, null)); // Phase hors énumération
        var wrongName = Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd");
        gp.V1Raw(Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"), GpFixture.V1Json(wrongName, "Verified", true, false, null, 0, null)); // fichier ≠ OperationId
        var withUnknown = GpFixture.V1Json(id, "Verified", true, false, null, 0, null).Replace("\"Schema\":1,", "\"Schema\":1,\"Inconnu\":1,");
        gp.V1Raw(Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff"), withUnknown); // schéma fermé violé
        gp.V1Raw(Guid.Parse("11111111-1111-1111-1111-111111111111"),
            GpFixture.V1Json(Guid.Parse("11111111-1111-1111-1111-111111111111"), "Verified", true, false, null, 0, null).Replace("\"Renommer\":true", "\"Renommer\":\"true\"")); // Renommer non booléen
        var w = LiveWorld(gp.Root);
        var listed = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items");
        Check.Equal(4, listed.Count, "Chaque entrée invalide est isolée, aucune n’est présentée comme lisible ni ignorée");
        Check.True(listed.All(r => Harness.Str(r!, "status") == "unreadable"), "Aucun de ces fichiers ne peut se faire passer pour un reçu vérifié");
        Check.Equal(4, Harness.Int(Harness.Call(w.Backend, "receipts.list"), "invalidCount"), "Tous comptabilisés comme illisibles");
    }

    [Test]
    public void MergeKeepsSessionAndPersistentWithoutErasure()
    {
        var w = LiveWorld(withWritingAdapter: true);
        w.Gp.AdapterReceipt("receipt-ancien", "Verified", T(1));
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") });
        Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        var listed = Harness.Arr(Harness.Call(w.Backend, "receipts.list"), "items");
        Check.Equal(2, listed.Count, "Reçu de la session + reçu durable antérieur : les deux survivent, aucun n’écrase l’autre");
        Check.True(listed.Any(r => Harness.Str(r!, "id") == "receipt-ancien"), "L’antérieur durable est toujours là");
        Check.True(listed.Any(r => Harness.Str(r!, "id").StartsWith("receipt-", StringComparison.Ordinal) && Harness.Str(r!, "id") != "receipt-ancien"),
            "Le reçu de la session est présent, en tête (plus récent)");
        Check.True(File.Exists(Path.Combine(w.Gp.Root, "V2", "receipts", "receipt-ancien.json")), "Aucun fichier du registre n’a été effacé par la session");
    }

    [Test]
    public void AdapterReceiptWrittenBeforeSendIsVisibleAfterRestart()
    {
        var w = LiveWorld(withWritingAdapter: true);
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") });
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        var id = Harness.Str(receipt, "id");
        var path = Path.Combine(w.Gp.Root, "V2", "receipts", id + ".json");
        Check.True(File.Exists(path), "Le reçu durable de l’adaptateur a été écrit sur le chemin du registre");
        Check.Contains("\"Phase\":\"Verified\"", File.ReadAllText(path), "Complété après envoi, comme Write-PestoJoinReceipt v1");
        // Redémarrage : nouveau moteur, même registre, aucun adaptateur de mutation injecté.
        var restarted = Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), new FakeGateway(), null, new FixedClock(), w.Gp.Root);
        var reread = Harness.Call(restarted, "receipts.get", new { id });
        Check.Equal(id, Harness.Str(reread, "id"), "Le reçu est reconsultable après redémarrage, sans être rejoué");
        Check.Equal("succeeded", Harness.Str(reread, "status"), "Statut relu depuis le fichier durable");
        Check.Contains("relu sur disque", Harness.Str(reread, "mode"), "La provenance est annoncée : relecture du fichier, pas la mémoire de la session");
    }

    [Test]
    public void DurableHistoryIsHonestlyUnknownWhenNoGpFolderExists()
    {
        if (OperatingSystem.IsWindows()) return; // sur Windows le défaut est %ProgramData%\GP réellement dérivé, jamais null
        var w = LiveWorld(overrideGp: true);
        var listed = Harness.Call(w.Backend, "receipts.list");
        Check.Equal(0, Harness.Arr(listed, "items").Count, "Aucun reçu inventé quand le registre est indisponible");
        Check.Contains("inconnus", Harness.Str(listed, "persistent"), "L’état dit inconnu, pas « historique vide »");
        var d = Harness.Call(w.Backend, "dashboard.read");
        Check.True(Harness.IsNull(d, "pendingRestart"), "Compteur inconnu plutôt que 0 supposé");
        Check.True(Harness.IsNull(d, "uncertain"), "Compteur inconnu plutôt que 0 supposé");
        Check.False(d["history"]!.AsObject()["readable"]!.GetValue<bool>(), "Le registre est explicitement déclaré non lu");
        var history = Harness.Arr(Harness.Call(w.Backend, "diagnostics.read"), "checks")
            .Single(c => c!["label"]!.GetValue<string>() == "Historique durable")!;
        Check.Equal("unknown", history["state"]!.GetValue<string>(), "Le diagnostic sépare explicitement « non lu » de « lu et vide »");
    }

    [Test]
    public void DurableHistoryIsHonestlyUnknownWhenTheLedgerCannotBeEnumerated()
    {
        if (OperatingSystem.IsWindows() || Environment.UserName == "root") return; // permissions non simulables
        var gp = new GpFixture();
        var ledger = Path.Combine(gp.Root, "Interventions");
        Directory.CreateDirectory(ledger);
        File.WriteAllText(Path.Combine(ledger, "00000000-0000-0000-0000-000000000000.json"), "{}");
        File.SetUnixFileMode(ledger, (UnixFileMode)0); // plus aucune lecture, même pour le propriétaire : panne réelle d'énumération
        try
        {
            var w = LiveWorld(gp.Root);
            var listed = Harness.Call(w.Backend, "receipts.list");
            Check.Contains("n’a pas pu être énuméré", Harness.Str(listed, "persistent"), "Panne de lecture annoncée, jamais masquée par un historique vide");
            var d = Harness.Call(w.Backend, "dashboard.read");
            Check.True(Harness.IsNull(d, "uncertain"), "Compteurs inconnus pendant la panne, jamais 0");
        }
        finally
        {
            File.SetUnixFileMode(ledger, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute |
                UnixFileMode.GroupRead | UnixFileMode.GroupExecute | UnixFileMode.OtherRead | UnixFileMode.OtherExecute);
        }
    }

    [Test]
    public void ReceiptsListQueryStillFiltersAcrossBothSources()
    {
        var w = LiveWorld(withWritingAdapter: true);
        w.Gp.AdapterReceipt("receipt-cible", "Verified", T(1), computer: "P111301PAINF042");
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") });
        Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        var items = Harness.Arr(Harness.Call(w.Backend, "receipts.list", new { query = "PAINF042" }), "items");
        Check.Equal(1, items.Count, "Le filtre retrouve le reçu durable par son poste");
        Check.Equal("receipt-cible", Harness.Str(items[0]!, "id"), "Filtré sur la source durable comme sur la session");
    }
}

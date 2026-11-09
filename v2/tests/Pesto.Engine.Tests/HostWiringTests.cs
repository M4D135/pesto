using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>Production and qualification wiring on fixtures only; no Windows mutation is executed.</summary>
internal sealed class HostWiringTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string Computer = "P111301PAINF009";
    private const string ComputerGuid = "11111111-1111-1111-1111-111111111111";

    private static DirectoryComputer Observed(string name, string? guid = ComputerGuid, string? ou = ParisOu) =>
        new(name, null, ou, null, guid, "example.local", null, null, null, null, null);

    private static string Root() => LiveTestConfig.Write(LiveTestConfig.NoRandom);

    private static HostWiringRequest HarnessRequest(
        bool isWindows = true, bool hasV1Root = true, string? adapter = HostWiring.AdapterPs51,
        string? confirmation = HostWiring.ConfirmationPhrase, bool simulation = false) =>
        new(simulation, true, adapter, confirmation, isWindows, hasV1Root);

    // ---- profil par défaut : production, aucune injection possible par accident ----------------

    [Test]
    public void NoArgumentsIsProductionAndInjectsNoMutation()
    {
        var launch = HostWiring.Parse([]);
        Check.False(launch.Simulation, "Sans option, ce n'est pas la simulation");
        Check.Equal(HostProfile.Production, launch.Wiring.Profile, "Le profil par défaut est la production");
        Check.False(launch.Wiring.IsQualificationHarness, "Le harnais n'est jamais le défaut");
        Check.Null(launch.Wiring.AdapterId, "Aucun adaptateur de mutation au profil par défaut");

        // Le backend construit exactement comme le fait l'hôte en production refuse toute écriture.
        var backend = PestoBackend.CreateLive(Root(), new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] },
            Find = name => name.Equals(Computer, StringComparison.OrdinalIgnoreCase) ? Observed(Computer) : null,
        }, null, new FixedClock(), Harness.IsolatedGpRoot());
        var session = Harness.Call(backend, "session.info");
        Check.True(Harness.Bool(session, "readOnly"), "Production : lecture seule réellement déclarée");
        foreach (var item in Harness.Arr(session, "capabilities"))
            Check.False(item!["enabled"]!.GetValue<bool>(), "Aucune capacité activée par le raccordement de production");
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") }),
            "entra.unavailable", "Sans lecteur natif Entra, aucun plan de renommage exécutable n'est préparé");
        var plan = Harness.Call(backend, "operation.prepare", new { kind = "move", computer = Computer, targetOU = "PA" });
        Check.Pesto(() => Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") }),
            "write.unavailable", "Le chemin de production n'atteint jamais un adaptateur de mutation");
        Check.Equal(0, Harness.Arr(Harness.Call(backend, "receipts.list"), "items").Count, "Aucun reçu fictif sur le chemin de production");
    }

    [Test]
    public void SimulationLaunchKeepsProductionWiring()
    {
        var launch = HostWiring.Parse(["--simulation"]);
        Check.True(launch.Simulation, "Simulation demandée");
        Check.Equal(HostProfile.Production, launch.Wiring.Profile, "La simulation ne change pas le raccordement : aucune mutation injectée");
    }

    [Test]
    public void JoinedStartupUsesWindowsAndAccountChoiceRemainsExplicit()
    {
        var startup = HostWiring.Parse([]);
        Check.False(startup.ChooseAccount, "Le lancement normal ne demande aucun second choix de compte après UAC");
        Check.Equal(HostAuthenticationMode.Windows, HostAuthentication.Select(true, startup.ChooseAccount),
            "Poste joint : identité Windows effective par défaut");
        var reconnect = HostWiring.Parse(["--choose-account"]);
        Check.True(reconnect.ChooseAccount, "La reconnexion explicite conserve la demande de choix");
        Check.Equal(HostAuthenticationMode.ChooseAccount, HostAuthentication.Select(true, reconnect.ChooseAccount),
            "L'opérateur peut demander un autre compte AD en domaine");
        Check.Null(reconnect.Wiring.AdapterId, "Choisir un compte n'injecte pas un adaptateur sans configuration");
    }

    [Test]
    public void WorkgroupAlwaysRequiresExplicitAdCredentials()
    {
        Check.Equal(HostAuthenticationMode.ExplicitAd, HostAuthentication.Select(false, false),
            "Hors domaine : aucun jeton Windows supposé compte AD");
        Check.Equal(HostAuthenticationMode.ExplicitAd, HostAuthentication.Select(false, true),
            "Une reconnexion hors domaine exige encore le compte AD natif");
    }

    [Test]
    public void SimulationAndDuplicateAccountChoicesAreRefusedBeforeProviders()
    {
        Check.Pesto(() => HostWiring.Parse(["--simulation", "--choose-account"]), "mode_fixed",
            "La démonstration ne peut ouvrir de dialogue AD");
        Check.Pesto(() => HostWiring.Parse(["--choose-account", "--choose-account"]), "host.args",
            "Pas de choix de compte ambigu ou dupliqué");
    }

    [Test]
    public void SettingsEntryNeverSelectsAnAdapterOrAccountPrompt()
    {
        var launch = HostWiring.Parse(["--settings", "--v1-root", Root()]);
        Check.True(launch.SettingsOnly, "Entrée locale explicite");
        Check.False(launch.ChooseAccount, "Aucun choix de compte AD dans les paramètres locaux");
        Check.Null(launch.Wiring.AdapterId, "Une configuration présente ne sélectionne pas un adaptateur en mode local");
        foreach (var forbidden in new[] { "--simulation", "--choose-account", "--qualification-harness", "--settings" })
            Check.Pesto(() => HostWiring.Parse(["--settings", forbidden]), forbidden == "--settings" ? "host.args" : "mode_fixed",
                "Les modes incompatibles sont refusés avant tout fournisseur");
    }

    // ---- refus du raccordement avant toute construction de backend ------------------------------

    [Test]
    public void MutationFlagsWithoutHarnessAreRefused()
    {
        var root = Root();
        Check.Pesto(() => HostWiring.Parse(["--v1-root", root, "--mutation-adapter", HostWiring.AdapterPs51]),
            "host.wiring_inconsistent", "Un adaptateur sans harnais explicite est refusé, jamais ignoré en silence");
        Check.Pesto(() => HostWiring.Parse(["--v1-root", root, "--confirm-qualification", HostWiring.ConfirmationPhrase]),
            "host.wiring_inconsistent", "Une confirmation sans harnais est refusée");
        // Défense en profondeur : la décision pure refuse aussi, même hors analyse d'arguments.
        Check.Pesto(() => HostWiring.Select(new HostWiringRequest(false, false, HostWiring.AdapterPs51, null, true, true)),
            "host.wiring_inconsistent", "Select refuse un adaptateur demandé sans harnais");
        Check.Pesto(() => HostWiring.Select(new HostWiringRequest(false, false, null, HostWiring.ConfirmationPhrase, true, true)),
            "host.wiring_inconsistent", "Select refuse une confirmation reçue sans harnais");
    }

    [Test]
    public void SimulationIsExclusiveWithV1RootAndWithHarness()
    {
        Check.Pesto(() => HostWiring.Parse(["--simulation", "--v1-root", Root()]),
            "mode_fixed", "La simulation n'utilise jamais une installation V1");
        Check.Pesto(() => HostWiring.Parse(["--simulation", "--qualification-harness"]),
            "mode_fixed", "La qualification ne s'exécute jamais en simulation : aucun fait réel ne peut en sortir");
        Check.Pesto(() => HostWiring.Select(HarnessRequest(simulation: true)),
            "mode_fixed", "Select refuse aussi le harnais en simulation");
    }

    [Test]
    public void UnknownDuplicatedOrTruncatedOptionsAreRefused()
    {
        Check.Pesto(() => HostWiring.Parse(["--ecritures-maintenant"]), "host.args", "Aucune option non déclarée n'ouvre quoi que ce soit");
        Check.Pesto(() => HostWiring.Parse(["--v1-root"]), "host.args", "--v1-root sans valeur est refusé");
        Check.Pesto(() => HostWiring.Parse(["--simulation", "--simulation"]), "host.args", "Option dupliquée : refus, pas d'état ambigu");
        Check.Pesto(() => HostWiring.Parse(["--v1-root", Root(), "--qualification-harness", "--mutation-adapter"]),
            "host.args", "--mutation-adapter sans valeur est refusé");
        Check.Pesto(() => HostWiring.Parse(["--v1-root", Root(), "--confirm-qualification"]),
            "host.args", "--confirm-qualification sans valeur est refusé");
    }

    [Test]
    public void V1RootMustBeALocalAbsolutePath()
    {
        Check.Pesto(() => HostWiring.Parse(["--v1-root", "dossier/relatif"]), "host.args", "Chemin relatif refusé");
        Check.Pesto(() => HostWiring.Parse(["--v1-root", "\\\\serveur\\partage"]), "host.args", "Aucun partage réseau implicite");
        Check.Pesto(() => HostWiring.Parse(["--v1-root", "//serveur/partage"]), "host.args", "Aucun partage réseau implicite (forme slash)");
    }

    // ---- gardes du harnais de qualification (décision pure, testable hors Windows) ----------------

    [Test]
    public void HarnessWithoutV1RootIsRefused()
    {
        Check.Pesto(() => HostWiring.Select(HarnessRequest(hasV1Root: false)),
            "config.missing", "Sans installation V1 réellement lisible, aucune écriture ne peut être qualifiée");
    }

    [Test]
    public void HarnessWithoutDeclaredAdapterIsRefused()
    {
        Check.Pesto(() => HostWiring.Select(HarnessRequest(adapter: null)),
            "host.adapter_missing", "Le harnais n'injecte rien par défaut : l'adaptateur doit être nommé");
        Check.Pesto(() => HostWiring.Select(HarnessRequest(adapter: "   ")),
            "host.adapter_missing", "Un adaptateur vide n'est pas une déclaration");
        Check.Pesto(() => HostWiring.Select(HarnessRequest(adapter: "ps7")),
            "host.adapter_unknown", "Seul ps51 est déclaré : aucun autre code d'écriture n'est admis");
        Check.Pesto(() => HostWiring.Select(HarnessRequest(adapter: "PS51")),
            "host.adapter_unknown", "L'identifiant est exact : aucune variante non déclarée");
    }

    [Test]
    public void HarnessOffWindowsIsRefused()
    {
        // C'est la garde qui ferme ce job : depuis Linux, le harnais reste refusé, même complètement demandé.
        Check.Pesto(() => HostWiring.Select(HarnessRequest(isWindows: false)),
            "host.not_windows", "Le harnais ne s'exécute que sur le poste Windows de qualification");
    }

    [Test]
    public void HarnessRequiresTheExactConfirmation()
    {
        foreach (var confirmation in new string?[] { null, "", "qualification windows/ad", "QUALIFICATION", "QUALIFICATION WINDOWS/AD ", " QUALIFICATION WINDOWS/AD" })
        {
            Check.Pesto(() => HostWiring.Select(HarnessRequest(confirmation: confirmation)),
                "host.confirmation_required", "Seule la confirmation exacte « " + HostWiring.ConfirmationPhrase + " » ouvre le harnais (obtenu : " + (confirmation ?? "null") + ")");
        }
    }

    [Test]
    public void FullyConfirmedHarnessIsSelectedOnWindowsOnly()
    {
        var selection = HostWiring.Select(HarnessRequest(isWindows: true));
        Check.Equal(HostProfile.QualificationHarness, selection.Profile, "Toutes les gardes passées, le harnais est sélectionné");
        Check.Equal(HostWiring.AdapterPs51, selection.AdapterId, "L'adaptateur sélectionné est celui déclaré");
        // Le même jeu d'arguments passé par l'hôte réel : refusé ici (non-Windows), sélectionné sur le poste de qualification.
        var args = new[] { "--v1-root", Root(), "--qualification-harness", "--mutation-adapter", HostWiring.AdapterPs51, "--confirm-qualification", HostWiring.ConfirmationPhrase };
        if (OperatingSystem.IsWindows())
            Check.True(HostWiring.Parse(args).Wiring.IsQualificationHarness, "Sur le poste Windows de qualification, le jeu complet sélectionne le harnais");
        else
            Check.Pesto(() => HostWiring.Parse(args), "host.not_windows", "Depuis ce système, le jeu complet lui-même reste refusé : rien ne s'exécute ici");
    }

    // ---- le raccordement décide réellement de l'injection (fixtures, aucune écriture réelle) -------

    private sealed class World
    {
        public required IPestoBackend Backend { get; init; }
        public required FakeGateway Gateway { get; init; }
        public FakeMutationGateway? Mutation { get; init; }
    }

    private static World BuildWorld(bool harnessSelected)
    {
        var machines = new Dictionary<string, DirectoryComputer>(StringComparer.OrdinalIgnoreCase) { [Computer] = Observed(Computer) };
        var present = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var gateway = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] },
            Find = name => machines.TryGetValue(name, out var c) ? c : present.Contains(name) ? Observed(name, "22222222-2222-2222-2222-222222222222") : null,
        };
        FakeMutationGateway? mutation = null;
        {
            mutation = new FakeMutationGateway();
            // La fixture applique le renommage en mémoire : la relecture du moteur doit le voir, comme sur un annuaire réel.
            mutation.Respond = request =>
            {
                if (machines.TryGetValue(request.Computer, out var c))
                {
                    machines.Remove(request.Computer);
                    machines[request.NewName!] = Observed(request.NewName!, c.Guid, c.Ou);
                }
                return new MutationOutcome(MutationStatus.Succeeded, 0, "OK fixture", false);
            };
        }
        var selection = harnessSelected
            ? HostWiring.Select(HarnessRequest(isWindows: true))
            : HostWiring.Select(new HostWiringRequest(false, false, null, null, true, true));
        Check.Equal(harnessSelected ? HostProfile.QualificationHarness : HostProfile.Production, selection.Profile, "La décision de raccordement est celle testée");
        Check.Equal(HostWiring.AdapterPs51, selection.AdapterId, "Windows configuré sélectionne le même adaptateur dans les deux profils");
        var clock = new FixedClock();
        FixtureEntraPreparation.SetClock(mutation, clock);
        var backend = PestoBackend.CreateLive(Root(), gateway, mutation, clock, Harness.IsolatedGpRoot());
        return new World { Backend = backend, Gateway = gateway, Mutation = mutation };
    }

    private static (string PlanId, string Confirmation) PrepareRename(World w)
    {
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = Computer });
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Harness.Str(preview, "previewId") });
        return (Harness.Str(plan, "planId"), Harness.Str(plan, "confirmationName"));
    }

    [Test]
    public void HarnessSelectionOpensTheConfirmedSendPipeline()
    {
        var w = BuildWorld(harnessSelected: true);
        var (planId, confirmation) = PrepareRename(w);
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId, confirmationName = confirmation });
        Check.Equal("succeeded", Harness.Str(receipt, "status"), "Sélection harnais : le pipeline d'envoi (reçu avant envoi, relecture après) fonctionne sur fixture");
        Check.Equal(1, w.Mutation!.Requests.Count, "Un seul appel à l'adaptateur, celui injecté par la surcharge de qualification");
        Check.False(Harness.Bool(Harness.Call(w.Backend, "session.info"), "readOnly"), "Sélection harnais : la lecture seule n'est plus déclarée — c'est le seul chemin qui injecte");
        foreach (var item in Harness.Arr(Harness.Call(w.Backend, "session.info"), "capabilities"))
        {
            if (Harness.Str(item!, "id") is "joinPrecreated" or "acknowledge" or "attributes")
                Check.False(Harness.Bool(item!, "enabled"), "Une capacité dédiée exige son provider explicite, et sa politique lorsque nécessaire");
            else Check.True(Harness.Bool(item!, "enabled"), "Une capacité disponible ne prétend pas être une preuve de qualification AD");
        }
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId, confirmationName = confirmation }),
            "plan.consumed", "Consommation unique, même en harnais : aucun rejeu");
    }

    [Test]
    public void ProductionSelectionRequiresWindowsConfigurationAndNeverSelectsMutationsInSimulation()
    {
        Check.Equal(HostWiring.AdapterPs51, HostWiring.Select(new(false, false, null, null, true, true)).AdapterId,
            "Production Windows configurée : adaptateur normal sélectionné");
        foreach (var request in new[]
        {
            new HostWiringRequest(true, false, null, null, true, true),
            new HostWiringRequest(false, false, null, null, false, true),
            new HostWiringRequest(false, false, null, null, true, false)
        }) Check.Null(HostWiring.Select(request).AdapterId, "Simulation, hors Windows ou configuration absente : aucun adaptateur");
    }

    [Test]
    public void ProductionSelectionUsesTheConfirmedSingleUseSendPipeline()
    {
        var w = BuildWorld(harnessSelected: false);
        var (planId, confirmation) = PrepareRename(w);
        var result = Harness.Call(w.Backend, "operation.execute", new { planId, confirmationName = confirmation });
        Check.Equal("succeeded", Harness.Str(result, "status"), "Production : succès seulement après relecture de la fixture");
        Check.Equal(1, w.Mutation!.Requests.Count, "Une seule mutation confirmée");
        Check.False(Harness.Bool(Harness.Call(w.Backend, "session.info"), "readOnly"), "Adaptateur disponible déclaré honnêtement");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId, confirmationName = confirmation }),
            "plan.consumed", "La production ne rejoue jamais un plan consommé");
    }
}

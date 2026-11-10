using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class LiveHonestyTests
{
    [Test]
    public void SessionReportsObservedIdentityAndRefusesEveryWrite()
    {
        var session = Harness.Call(Harness.Live(), "session.info");
        Check.Equal("live", Harness.Str(session, "mode"), "Mode réel annoncé");
        Check.True(Harness.Bool(session, "readOnly"), "Lecture seule tant que l’écriture n’est pas qualifiée");
        Check.False(string.IsNullOrEmpty(Harness.Str(session, "computer")), "Le nom du poste est réellement observé");
        foreach (var item in Harness.Arr(session, "capabilities"))
        {
            Check.False(item!["enabled"]!.GetValue<bool>(), "Aucune capacité réelle activée par défaut");
            Check.False(string.IsNullOrEmpty(item!["reason"]!.GetValue<string>()), "Chaque refus porte une raison exploitable");
        }
    }

    [Test]
    public void DirectoryAndNamingReadsAreRefusedRatherThanInvented()
    {
        var backend = Harness.Live();
        Check.Pesto(() => Harness.Call(backend, "directory.sites"), "config.missing", "Aucun site fictif sans configuration V1 lue");
        Check.Pesto(() => Harness.Call(backend, "directory.services", new { site = "paris" }), "config.missing", "Aucun service fictif sans configuration V1 lue");
        Check.Pesto(() => Harness.Call(backend, "directory.search", new { query = "PC" }), "config.missing", "Aucune recherche fictive sans configuration V1 lue");
        Check.Pesto(() => Harness.Call(backend, "computer.inspect", new { computer = "PC001" }), "config.missing", "Aucune inspection fictive sans configuration V1 lue");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "paris", service = "INF" }), "config.missing", "Aucun nom fictif sans configuration V1 lue");
    }

    [Test]
    public void NamesPreviewWithoutAdapterStaysUnknownRatherThanSimulated()
    {
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid));
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" }),
            "names.unavailable", "Sans adaptateur annuaire, la disponibilité reste inconnue : jamais un nom simulé derrière un aperçu « réel »");
    }

    [Test]
    public void DirectoryReadsWithoutAdapterAreRefusedEvenWithConfig()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.Valid);
        var backend = Harness.Live(root);
        Check.Pesto(() => Harness.Call(backend, "directory.sites"), "directory.unavailable", "Aucun site inventé sans adaptateur annuaire");
        Check.Pesto(() => Harness.Call(backend, "directory.services", new { site = "PA" }), "directory.unavailable", "Aucun service inventé sans adaptateur annuaire");
        Check.Pesto(() => Harness.Call(backend, "directory.search", new { query = "PC" }), "directory.unavailable", "Aucune recherche inventée sans adaptateur annuaire");
        Check.Pesto(() => Harness.Call(backend, "computer.inspect", new { computer = "PC001" }), "directory.unavailable", "Aucune inspection inventée sans adaptateur annuaire");
    }

    [Test]
    public void WritesAndConfigAreRefused()
    {
        var backend = Harness.Live();
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = "X" }), "config.missing", "Aucun plan fictif sans configuration V1 lue");
        Check.Pesto(() => Harness.Call(backend, "operation.execute", new { planId = "plan-1", confirmationName = "X" }), "plan.stale", "Aucun plan à exécuter : rien n'est envoyé");
        Check.Pesto(() => Harness.Call(backend, "queue.add", new { kind = "rename", computer = "X" }),
            "config.missing", "Aucune ligne de file validée sans configuration V1 lue : la file réelle n'invente ni borne ni portée");
        Check.Pesto(() => Harness.Call(backend, "queue.execute", new { batchId = "batch-1", confirmed = true }),
            "batch.stale", "Aucun lot sans préparation : rien n'est envoyé, même sans configuration");
        Check.Pesto(() => Harness.Call(backend, "settings.save", new { domain = "a.local", dc = "dc.a.local", prefix = "1", production = false,
            namingPattern = PestoSettings.DefaultPattern, randomNames = false, sites = new object[] { new { id = "p", name = "P", code = "PA", ou = "OU=P,DC=a,DC=local" } } }),
            "config.missing", "Aucune écriture de configuration sans dossier d’installation V1 fourni : rien n’est écrit n’importe où");
    }

    [Test]
    public void EveryWriteStaysRefusedWithoutAQualifiedMutationAdapter()
    {
        // Configuration lue + adaptateur lecture injectés : c'est l'adaptateur de MUTATION qui manque, tout envoi reste refusé.
        var gateway = new FakeGateway { ChildOus = { ["OU=SITES,OU=Postes,DC=example,DC=local"] = ["Paris-Nord"] } };
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.Production), gateway);
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        var plan = Harness.Call(backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
        Check.Equal("live", Harness.Str(plan, "mode"), "La préparation est bien du mode réel, pas une simulation déguisée");
        Check.Pesto(() => Harness.Call(backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") }),
            "write.unavailable", "Aucune écriture sans adaptateur de mutation qualifié Windows/AD");
        Check.Equal(0, Harness.Arr(Harness.Call(backend, "receipts.list"), "items").Count, "Aucun reçu fictif : rien n'a été envoyé, rien n'est consigné comme envoyé");
        foreach (var item in Harness.Arr(Harness.Call(backend, "session.info"), "capabilities"))
            Check.False(item!["enabled"]!.GetValue<bool>(), "Capacité join/rename/move/renameMove/queue toujours désactivée même avec l'adaptateur lecture");
        var writes = System.Linq.Enumerable.Single(Harness.Arr(Harness.Call(backend, "diagnostics.read"), "checks"), c => c!["label"]!.GetValue<string>() == "Écritures");
        Check.Equal("unknown", writes!["state"]!.GetValue<string>(), "Aucune écriture qualifiée : état unknown, jamais ok");
        var unattended = System.Linq.Enumerable.Single(Harness.Arr(Harness.Call(backend, "diagnostics.read"), "checks"), c => c!["label"]!.GetValue<string>() == "Jonction non accompagnée");
        Check.Equal("ok", unattended!["state"]!.GetValue<string>(), "UnattendedJoinEnabled est lu (false ici) et jamais activé par le moteur");
    }

    [Test]
    public void EmptyResultsAreHonestNotFabricated()
    {
        var backend = Harness.Live();
        Check.Equal(0, Harness.Arr(Harness.Call(backend, "receipts.list"), "items").Count, "Aucun reçu inventé");
        Check.Equal(0, Harness.Arr(Harness.Call(backend, "logs.list"), "items").Count, "Aucun journal inventé (le journal conserve les événements de session, port v1)");
        // Constat 3 de la revue : le tableau de bord réel est un lecteur, pas une constante. Sans configuration ni adaptateur
        // annuaire, il refuse avec une raison exploitable ; le null est réservé à l'inconnu d'une lecture réellement tentée.
        Check.Pesto(() => Harness.Call(backend, "dashboard.read"), "config.missing", "Aucun tableau de bord fictif sans configuration V1 lue");
        var withoutAdapter = Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid));
        Check.Pesto(() => Harness.Call(withoutAdapter, "dashboard.read"), "directory.unavailable", "Aucun tableau de bord constamment vide : sans adaptateur annuaire, le lecteur refuse avec raison");
        var settings = Harness.Call(backend, "settings.get");
        Check.False(Harness.Bool(settings, "simulation"), "Le mode réel ne se déclare pas simulation");
        Check.Equal(0, Harness.Arr(settings, "sites").Count, "Aucun site inventé en configuration");
    }

    [Test]
    public void DiagnosticsSeparateObservedFromUnavailable()
    {
        var diagnostics = Harness.Call(Harness.Live(), "diagnostics.read");
        Check.Equal("live", Harness.Str(diagnostics, "mode"), "Mode réel");
        var ad = System.Linq.Enumerable.Single(Harness.Arr(diagnostics, "checks"), c => c!["label"]!.GetValue<string>() == "Active Directory");
        Check.Equal("unknown", ad!["state"]!.GetValue<string>(), "AD explicitement indisponible, jamais simulé");
        var config = System.Linq.Enumerable.Single(Harness.Arr(diagnostics, "checks"), c => c!["label"]!.GetValue<string>() == "Configuration V1");
        Check.Equal("unknown", config!["state"]!.GetValue<string>(), "Configuration absente annoncée, jamais remplacée par des valeurs d’exemple");
    }

    [Test]
    public void LocalMembershipComesFromWindowsAndStaysUnknownWhenUnread()
    {
        Check.Null(Harness.Call(Harness.Live(), "session.info")["localJoined"], "Sans lecteur Windows, l’appartenance reste inconnue, jamais « hors domaine »");
        foreach (var joined in new bool?[] { true, false, null })
        {
            var session = Harness.Call(Harness.Live(null, new FakeGateway { LocalComputerJoined = joined }), "session.info");
            Check.Equal(joined, session["localJoined"]?.GetValue<bool>(), $"Appartenance {joined?.ToString() ?? "inconnue"} rapportée telle que Windows la lit");
        }
        var read = new PowerShellDirectoryGateway().LocalComputerJoined;
        if (OperatingSystem.IsWindows()) Check.NotNull(read, "Sous Windows, NetGetJoinInformation répond sans contrôleur ni réseau");
        else Check.Null(read, "Hors Windows, aucune appartenance n’est supposée");
    }

    [Test]
    public void TransientAdapterNeverFabricatesOffWindows()
    {
        var gateway = new PowerShellDirectoryGateway();
        Check.False(string.IsNullOrEmpty(gateway.Description), "L’adaptateur déclare son origine réelle");
        if (!OperatingSystem.IsWindows())
        {
            Check.Pesto(() => gateway.SearchComputers("example.local", null, "pc", 10), "directory.unavailable", "Hors Windows, la recherche est refusée, jamais simulée");
            Check.Pesto(() => gateway.FindComputer("example.local", null, "PC001"), "directory.unavailable", "Hors Windows, l’inspection est refusée");
            Check.Pesto(() => gateway.ListChildOuNames("example.local", null, "OU=SITES,DC=example,DC=local"), "directory.unavailable", "Hors Windows, la lecture des OU est refusée");
            Check.Pesto(() => gateway.ListComputerNames("example.local", null, "OU=SITES,DC=example,DC=local", 100), "directory.unavailable", "Hors Windows, l’inventaire est refusé");
            Check.Pesto(() => gateway.DiscoverDomainController("example.local"), "directory.unavailable", "Hors Windows, la découverte du contrôleur est refusée");
        }
        else
        {
            // Sur Windows sans qualification AD, seule une panne motivée est acceptable : jamais un item inventé.
            try
            {
                var result = gateway.SearchComputers("example.invalid.local", null, "pc", 10);
                throw new TestFailureException("Une lecture AD ne peut pas réussir sans qualification ; obtenu " + result.Items.Count + " items.");
            }
            catch (PestoException error)
            {
                Check.True(error.Code.StartsWith("directory.", StringComparison.Ordinal), "Panne annuaire motivée, jamais un fait fictif");
            }
        }
    }
}

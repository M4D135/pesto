namespace Pesto.Engine.Tests;

internal sealed class SessionDashboardTests
{
    [Test]
    public void SessionAnnouncesSimulationAndFullCapabilities()
    {
        var session = Harness.Call(Harness.Simulation(), "session.info");
        Check.Equal("simulation", Harness.Str(session, "mode"), "Mode annoncé");
        Check.False(Harness.Bool(session, "readOnly"), "La simulation autorise ses actions en mémoire");
        Check.Equal("NOUVEAU-PC", Harness.Str(session, "computer"), "Poste local simulé");
        var capabilities = Harness.Arr(session, "capabilities");
        Check.Equal(5, capabilities.Count, "Cinq capacités déclarées");
        foreach (var item in capabilities)
            Check.True(item!["enabled"]!.GetValue<bool>(), "Capacité " + item!["id"]!.GetValue<string>() + " disponible en simulation");
    }

    [Test]
    public void DashboardReportsCountsAndUnknowns()
    {
        var dashboard = Harness.Call(Harness.Simulation(), "dashboard.read");
        Check.Equal(4, Harness.Int(dashboard, "computers"), "Quatre postes simulés");
        Check.True(Harness.IsNull(dashboard, "availableNames"), "Noms disponibles inconnus (jamais fictifs)");
        Check.Equal(0, Harness.Int(dashboard, "pendingRestart"), "Aucun redémarrage en attente au départ");
        Check.Equal(2, Harness.Arr(dashboard, "sites").Count, "Répartition par site");
    }

    [Test]
    public void DirectoryReadsAreBoundedAndHonest()
    {
        var backend = Harness.Simulation();
        Check.Equal(2, Harness.Arr(Harness.Call(backend, "directory.sites"), "items").Count, "Deux sites");
        Check.Equal(3, Harness.Arr(Harness.Call(backend, "directory.services", new { site = "paris" }), "items").Count, "Trois services");
        Check.Pesto(() => Harness.Call(backend, "directory.services", new { site = "mars" }), "site.invalid", "Site inconnu refusé");

        var search = Harness.Call(backend, "directory.search", new { query = "P111301PAINF001" });
        Check.Equal(1, Harness.Arr(search, "items").Count, "Recherche exacte");
        Check.True(Harness.Bool(search, "complete"), "Résultat complet");
        Check.Pesto(() => Harness.Call(backend, "directory.search", new { query = "   " }), "invalid_arguments", "Recherche vide refusée");
    }

    [Test]
    public void InspectReturnsChecks()
    {
        var backend = Harness.Simulation();
        var inspect = Harness.Call(backend, "computer.inspect", new { computer = "V111301LYINF001" });
        Check.Equal("V111301LYINF001", Harness.Str(inspect, "name"), "Poste trouvé");
        Check.Equal(2, Harness.Arr(inspect, "checks").Count, "Contrôles rendus");
        Check.Pesto(() => Harness.Call(backend, "computer.inspect", new { computer = "INCONNU" }), "computer.missing", "Poste inconnu refusé");
    }

    [Test]
    public void DiagnosticsDeclareIsolation()
    {
        var diagnostics = Harness.Call(Harness.Simulation(), "diagnostics.read");
        Check.Equal("simulation", Harness.Str(diagnostics, "mode"), "Mode diagnostic");
        var ad = System.Linq.Enumerable.Single(Harness.Arr(diagnostics, "checks"),
            c => c!["label"]!.GetValue<string>() == "Active Directory");
        Check.Equal("unknown", ad!["state"]!.GetValue<string>(), "Aucun contact AD revendiqué en simulation");
    }
}

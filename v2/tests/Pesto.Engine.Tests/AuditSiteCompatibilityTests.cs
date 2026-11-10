using System.Text.Json.Nodes;

namespace Pesto.Engine.Tests;

internal sealed class AuditSiteCompatibilityTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";

    private static int Sites(bool declared)
    {
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["TAGS"] = JsonNode.Parse(declared
            ? "[{\"Site\":\"PREPROD\",\"Tag\":\"PR\"},{\"Site\":\"AgencePA\",\"Tag\":\"PA\"}]"
            : "[{\"Site\":\"PREPROD\",\"Tag\":\"PR\"}]");
        var root = LiveTestConfig.Write(cfg.ToJsonString());
        try
        {
            var gateway = new FakeGateway();
            gateway.ChildOus[Container] = ["AgencePA"];
            return Harness.Arr(Harness.Call(Harness.Live(root, gateway), "directory.sites"), "items").Count;
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void DeclaredSiteIsListedControl() => Check.Equal(1, Sites(true), "Témoin avec TAGS explicite");

    [Test]
    public void V1SuffixFallbackShouldPreserveOrdinarySite() => Check.Equal(1, Sites(false), "Parité V1 : AgencePA doit rester visible avec le code PA");

    [Test]
    public void TwoConfiguredPreproductionSitesDoNotHideOrdinaryAdSites()
        => VerifyObservedSites(["222_PROD_A_NOMMER", "222_PREPROD", "AgenceMN", "SIEGE-XY"]);

    // Also exercised with children returned by the compiled PowerShell worker on the Windows CI runner.
    internal static void VerifyObservedSites(string[] children)
    {
        const string parent = "OU=SITES,OU=Postes,DC=labo,DC=local";
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom.Replace("example", "labo").Replace("EXAMPLE", "LABO"))!.AsObject();
        cfg["TAGS"] = JsonNode.Parse("""
            [{"Site":"PREPROD","Tag":"PR"},{"Site":"222_PROD_A_NOMMER","Tag":"PR"},{"Site":"222_PREPROD","Tag":"PR"}]
            """);
        cfg["NameCatalogue"] = new JsonArray();
        var root = LiveTestConfig.Write(cfg.ToJsonString());
        try
        {
            var gateway = new FakeGateway { DiscoveredDc = "dc01.labo.local",
                FindOu = dn => dn == "OU=AgenceMN," + parent ? new(dn, "11111111-2222-3333-4444-555555555555", "AgenceMN") : null,
                ScopeNames = ["P111301MN456001"],
                DomainNames = ["P111301MN456001", "V111301MN789001", "P111301XY333001"] };
            gateway.ChildOus[parent] = children.ToList();
            var backend = Harness.Live(root, gateway);
            var sites = Harness.Arr(Harness.Call(backend, "directory.sites"), "items");
            Check.Equal(4, sites.Count, "Deux sites de préproduction et deux sites AD sans TAGS explicite");
            Check.Equal("PR,PR,MN,XY", string.Join(',', sites.Select(item => Harness.Str(item!, "code"))), "Ordre des TAGS puis suffixes V1");
            Check.Equal(4, sites.Select(item => Harness.Str(item!, "id")).Distinct().Count(), "Les deux codes PR gardent des identifiants distincts");
            var selected = Harness.Str(sites.Single(item => Harness.Str(item!, "code") == "MN")!, "selector");
            Check.Equal("OU=AgenceMN," + parent, selected, "La sélection désigne l’OU AD observée");
            var services = Harness.Arr(Harness.Call(backend, "directory.services", new { site = selected }), "items");
            Check.Equal("456,789", string.Join(',', services.Select(item => Harness.Str(item!, "code"))), "Services observés dans l’OU et par tag dans le domaine");
            var preview = Harness.Call(backend, "names.preview", new { type = "P", site = selected, service = "456" });
            Check.Equal("P111301MN456002", Harness.Str(preview, "name"), "Le site découvert reste utilisable pour calculer le nom suivant");
            Check.Equal(1, gateway.ChildOuReads[parent], "Services et calcul gardent la sélection sans réénumérer les sites");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test] public void FallbackWorksWithoutTagsButNeverInventsPreproductionOrInvalidCodes()
    {
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["CONF"]![0]!["DirectProd"] = true; cfg["TAGS"] = new JsonArray();
        var root = LiveTestConfig.Write(cfg.ToJsonString());
        try
        {
            var gateway = new FakeGateway();
            gateway.ChildOus[Container] = ["AgencePA", "PREPROD", "765", "765_PREPROD", "765_PROD_A_NOMMER", "Depot42", "X"];
            var items = Harness.Arr(Harness.Call(Harness.Live(root, gateway), "directory.sites"), "items");
            Check.Equal(1, items.Count, "seul le suffixe ordinaire valide est proposé");
            Check.Equal("PA", Harness.Str(items[0]!, "code"), "code V1 observé sans aucun TAGS");
            Check.Equal(1, gateway.ChildOuReads[Container], "une lecture suffit sans TAGS");
            var service = new ProfileConfigurationService(root, "origin", ConfigurationAccessMode.Live);
            var settings = service.ReadSettings();
            foreach (var key in new[] {"configured", "configurationExists", "configurationState", "diagnostic", "simulation", "liveExecutionEnabled"}) settings.Remove(key);
            settings["prefix"] = "222222";
            var plan = service.PreviewSettings(System.Text.Json.JsonSerializer.SerializeToElement(settings));
            service.ApplyImport(Harness.Str(plan, "planId"), true);
            var saved = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "cfg.json")))!;
            Check.Equal(0, saved["TAGS"]!.AsArray().Count, "sauvegarder les paramètres ne fabrique pas de TAGS");
            Check.Equal("222222", saved["CONF"]![0]!["Prefixe"]!.GetValue<string>(), "le réglage reste modifiable");
        }
        finally { Directory.Delete(root, true); }
    }
}

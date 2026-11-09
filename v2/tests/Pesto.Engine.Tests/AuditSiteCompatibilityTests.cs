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

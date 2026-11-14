using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pesto.Engine.Tests;

internal sealed class AuditSettingsRoundtripTests
{
    [Test]
    public void SavingMixedConfigurationMustPreserveUndisplayedDiscoveredSites()
    {
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["CONF"]![0]!["DirectProd"] = true;
        cfg["V2DirectorySites"] = JsonNode.Parse("""
          [{"Id":"paris","Name":"Paris-Nord","Code":"PA","OU":"OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local"}]
          """);
        var root = LiveTestConfig.Write(ConfigurationDocument.Sanitize(cfg.ToJsonString()).ToJsonString());
        try
        {
            var gateway = new FakeGateway();
            gateway.ChildOus["OU=SITES,OU=Postes,DC=example,DC=local"] = ["Paris-Nord", "Lyon"];
            var backend = Harness.Live(root, gateway);
            var before = Harness.Arr(Harness.Call(backend, "directory.sites"), "items").Count;
            var service = new ProfileConfigurationService(root, "origin", ConfigurationAccessMode.Live);
            var shown = service.ReadSettings();
            foreach (var key in new[] {"configured", "configurationExists", "configurationState", "diagnostic", "simulation", "liveExecutionEnabled"}) shown.Remove(key);
            var beforeSaved = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "cfg.json")))!;
            shown["prefix"] = "222222";
            var plan = service.PreviewSettings(JsonSerializer.SerializeToElement(shown));
            service.ApplyImport(Harness.Str(plan, "planId"), true);
            var after = Harness.Arr(Harness.Call(backend, "directory.sites"), "items").Count;
            var saved = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "cfg.json")))!;
            Console.WriteLine($"Audit roundtrip: sites {before} -> {after}; TAGS={saved["TAGS"]!.ToJsonString()}; OUSite={saved["OUSite"]!.ToJsonString()}");
            Check.Equal(2, before, "Témoin : Paris explicite et Lyon découvert");
            Check.Equal(before, after, "Enregistrer les champs affichés sans changer les sites doit conserver Lyon");
            foreach (var section in new[] { "TAGS", "OUSite", "V2DirectorySites" })
                Check.True(JsonNode.DeepEquals(beforeSaved[section], saved[section]), section + " conservé intégralement");
            Check.Equal("222222", saved["CONF"]![0]!["Prefixe"]!.GetValue<string>(), "L’autre réglage est bien appliqué");
            shown["fingerprint"] = service.ReadSettings()["fingerprint"]!.DeepClone();
            shown["sites"]![0]!["name"] = "Paris-Renomme";
            var stable = File.ReadAllText(Path.Combine(root, "cfg.json"));
            Check.Pesto(() => service.PreviewSettings(JsonSerializer.SerializeToElement(shown)), "config.invalid", "L’édition partielle d’un modèle mixte est refusée explicitement");
            Check.Equal(stable, File.ReadAllText(Path.Combine(root, "cfg.json")), "Le refus ne réécrit rien");
        }
        finally { Directory.Delete(root, true); }
    }
}

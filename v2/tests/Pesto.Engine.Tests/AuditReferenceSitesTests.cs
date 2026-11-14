using System.Text.Json.Nodes;

namespace Pesto.Engine.Tests;

internal static class AuditReferenceSitesTests
{
    [Test] private static void ExistingExplicitSiteShouldAcceptAnImportedService()
    {
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["CONF"]![0]!["DirectProd"] = true;
        cfg["TAGS"] = new JsonArray();
        cfg["V2DirectorySites"] = JsonNode.Parse("""
          [{"Id":"paris","Name":"Paris-Nord","Code":"PA","OU":"OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local"}]
          """);
        var root = LiveTestConfig.Write(ConfigurationDocument.Sanitize(cfg.ToJsonString()).ToJsonString());
        const string incoming = """
          {"schema":1,"kind":"pesto.references","version":"audit1","sites":[],"services":[{"site":"PA","code":"002","name":"Accueil"}]}
          """;
        try
        {
            var backend = Harness.Live(root, new FakeGateway());
            Check.Equal(1, Harness.Arr(Harness.Call(backend, "directory.sites"), "items").Count, "Témoin : site explicite valide et visible");
            var service = new ProfileConfigurationService(root, "origin", ConfigurationAccessMode.Live);
            var plan = service.PreviewReferences(incoming);
            Check.Equal(1, Harness.Int(plan, "additions"), "Le service PA devrait être accepté pour le site explicite existant");
            Check.Pesto(() => service.ApplyReferences(Harness.Str(plan, "planId"), new Dictionary<string, string>(), false),
                "config.confirmation", "La confirmation reste nécessaire");
            service.ApplyReferences(Harness.Str(plan, "planId"), new Dictionary<string, string>(), true);
            var saved = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "cfg.json")))!;
            Check.True(saved["NameCatalogue"]!.AsArray().Any(p => p!["Site"]!.GetValue<string>() == "PA" && p["Service"]!.GetValue<string>() == "002"), "Service persisté");
            Check.True(JsonNode.DeepEquals(cfg["V2DirectorySites"], saved["V2DirectorySites"]), "Sites explicites conservés");
            Check.True(JsonNode.DeepEquals(cfg["OUSite"], saved["OUSite"]), "Racines de découverte conservées");
            Check.Pesto(() => service.PreviewReferences(incoming.Replace("\"PA\"", "\"ZZ\"", StringComparison.Ordinal)),
                "config.invalid", "Un service vraiment orphelin reste refusé");
        }
        finally { Directory.Delete(root, true); }
    }
}

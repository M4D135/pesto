using System.Text.Json;
using System.Text.Json.Nodes;

namespace Pesto.Engine.Tests;

internal static class AuditNameScopeSettingsTests
{
    [Test] private static void SavingDisplayedSettingsShouldPreserveUndisplayedNameScope()
    {
        const string expected = "OU=Inventaire,DC=example,DC=local";
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["CONF"]![0]!["OUScanNoms"] = expected;
        var root = LiveTestConfig.Write(ConfigurationDocument.Sanitize(cfg.ToJsonString()).ToJsonString());
        try
        {
            var service = new ProfileConfigurationService(root, "origin", ConfigurationAccessMode.Live);
            var shown = service.ReadSettings();
            foreach (var key in new[] {"configured", "configurationExists", "configurationState", "diagnostic", "simulation", "liveExecutionEnabled"}) shown.Remove(key);
            var plan = service.PreviewSettings(JsonSerializer.SerializeToElement(shown));
            service.ApplyImport(Harness.Str(plan, "planId"), true);
            var saved = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "cfg.json")))!;
            var actual = saved["CONF"]![0]!["OUScanNoms"]!.GetValue<string>();
            Console.WriteLine($"Audit périmètre noms : avant={expected}, après={actual}");
            Check.Equal(expected, actual, "Enregistrer les champs affichés ne doit pas changer le périmètre distinct de recherche des noms");
        }
        finally { Directory.Delete(root, true); }
    }
}

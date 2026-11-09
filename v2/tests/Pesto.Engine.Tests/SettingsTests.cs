using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class SettingsTests
{
    private static object ValidSettings(string prefix = "111301", string namingPattern = PestoSettings.DefaultPattern) => new
    {
        domain = "example.local",
        dc = "dc01.example.local",
        prefix,
        production = false,
        namingPattern,
        randomNames = false,
        sites = new object[]
        {
            new { id = "paris", name = "Paris", code = "PA", ou = "OU=Paris,OU=Postes,DC=example,DC=local" },
            new { id = "lyon", name = "Lyon", code = "LY", ou = "OU=Lyon,OU=Postes,DC=example,DC=local" },
        },
    };

    [Test]
    public void GetReturnsDemoConfiguration()
    {
        var settings = Harness.Call(Harness.Simulation(), "settings.get");
        Check.Equal("example.local", Harness.Str(settings, "domain"), "Domaine de démonstration");
        Check.Equal("111301", Harness.Str(settings, "prefix"), "Préfixe de démonstration");
        Check.Equal(2, Harness.Arr(settings, "sites").Count, "Deux sites configurés");
        Check.True(Harness.Bool(settings, "simulation"), "Mode simulation");
        Check.False(Harness.Bool(settings, "liveExecutionEnabled"), "Écritures réelles jamais activées par les paramètres");
    }

    [Test]
    public void SaveInvalidatesEarlierPreviewsAndPlans()
    {
        var backend = Harness.Simulation();
        var preview = Harness.Call(backend, "names.preview", new { type = "S", site = "paris", service = "ADM", computer = "S111301PAADM001" });
        var previewId = Harness.Str(preview, "previewId");
        Harness.Call(backend, "settings.save", ValidSettings());
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = "S111301PAADM001", previewId }),
            "plan.stale", "Un changement de paramètres invalide l’aperçu");
    }

    [Test]
    public void SaveRejectsModeAndLiveExecutionChanges()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Harness.Call(backend, "settings.save", new { domain = "example.local", dc = "dc01.example.local", prefix = "1",
            production = false, namingPattern = PestoSettings.DefaultPattern, randomNames = false, simulation = false,
            sites = ValidSites() }), "mode_fixed", "Le mode n’est pas modifiable ici");
        Check.Pesto(() => Harness.Call(backend, "settings.save", new { domain = "example.local", dc = "dc01.example.local", prefix = "1",
            production = false, namingPattern = PestoSettings.DefaultPattern, randomNames = false, liveExecutionEnabled = true,
            sites = ValidSites() }), "live_execution_unavailable", "Les écritures réelles ne s’activent pas ici");
    }

    [Test]
    public void SaveRejectsInvalidValues()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Harness.Call(backend, "settings.save", ValidSettings(prefix: "bad!")), "invalid_settings", "Préfixe invalide");
        Check.Pesto(() => Harness.Call(backend, "settings.save", new { domain = "not-a-domain", dc = "", prefix = "1", production = false,
            namingPattern = PestoSettings.DefaultPattern, randomNames = false, sites = ValidSites() }), "invalid_settings", "Domaine invalide");
        Check.Pesto(() => Harness.Call(backend, "settings.save", ValidSettings(namingPattern: "{type}{prefix}{site}{service}")),
            "invalid_naming", "Convention incomplète refusée");
    }

    private static object[] ValidSites() =>
    [
        new { id = "paris", name = "Paris", code = "PA", ou = "OU=Paris,OU=Postes,DC=example,DC=local" },
    ];
}

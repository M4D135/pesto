using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class ConfigurationOnlyTests
{
    [Test]
    public void ConfiguredSessionRemainsLocalAndRefusesEveryBusinessFamily()
    {
        var path = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var backend = PestoBackend.CreateConfigurationOnly(path, Harness.IsolatedGpRoot());
        var session = Harness.Call(backend, "session.info");
        Check.True(Harness.Bool(session, "configurationOnly"), "Le statut indique une configuration locale");
        Check.True(Harness.Bool(session, "readOnly"), "Aucune mutation disponible");
        Check.Null(session["dc"], "Aucun DC n'est présenté comme connecté");
        foreach (var capability in Harness.Arr(session, "capabilities"))
            Check.False(capability!["enabled"]!.GetValue<bool>(), "Aucune capacité métier activée");
        foreach (var operation in new[] { "dashboard.read", "directory.sites", "directory.services", "directory.search", "computer.inspect",
            "names.preview", "join.precreated.preview", "operation.prepare", "operation.execute", "queue.add", "queue.execute",
            "attributes.inspect", "attributes.apply", "reservations.execute", "receipts.acknowledge", "receipts.restart", "settings.save" })
            Check.Pesto(() => Harness.Call(backend, operation, new { source = @"\\example.invalid\never-read", confirmed = true }),
                "session.configurationOnly", "Refus métier avant interprétation des arguments : " + operation);
        _ = Harness.Call(backend, "diagnostics.read");
        _ = Harness.Call(backend, "logs.list");
    }

    [Test]
    public void InvalidConfigurationDoesNotPreventTheLocalSessionOpening()
    {
        var path = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var configuration = Path.Combine(path, "cfg.json");
        var original = new byte[] { 0xff, 0xfe, 0x7b, 0x00, 0x00 };
        File.WriteAllBytes(configuration, original);
        var backend = PestoBackend.CreateConfigurationOnly(path, Harness.IsolatedGpRoot());
        Check.True(Harness.Bool(Harness.Call(backend, "session.info"), "configurationOnly"), "Le shell local reste accessible");
        Check.True(original.SequenceEqual(File.ReadAllBytes(configuration)), "Aucune réécriture implicite du fichier invalide");
    }

    [Test]
    public void RepeatedLocalSessionReadsSurviveMissingCreatedAndRemovedConfiguration()
    {
        var path = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var configuration = Path.Combine(path, "cfg.json");
        var original = File.ReadAllBytes(configuration);
        var expectedDomain = V1Config.Load(path).Domain;
        File.Delete(configuration);
        var backend = PestoBackend.CreateConfigurationOnly(path, Harness.IsolatedGpRoot());

        void ReadLocal(string? domain)
        {
            for (var attempt = 0; attempt < 3; attempt++)
            {
                var session = Harness.Call(backend, "session.info");
                Check.True(Harness.Bool(session, "configurationOnly"), "Les relectures restent locales");
                Check.True(Harness.Bool(session, "readOnly"), "Aucun adaptateur ne devient disponible");
                Check.Null(session["dc"], "Aucun DC n'est supposé connecté");
                if (domain is null) Check.Null(session["domain"], "Aucun domaine actif sans configuration");
                else Check.Equal(domain, session["domain"]!.GetValue<string>(), "La nouvelle configuration est relue");
                foreach (var capability in Harness.Arr(session, "capabilities"))
                    Check.False(capability!["enabled"]!.GetValue<bool>(), "Les capacités métier restent fermées");
            }
        }

        ReadLocal(null);
        Check.False(File.Exists(configuration), "Les lectures n'inventent pas de configuration");
        File.WriteAllBytes(configuration, original);
        ReadLocal(expectedDomain);
        File.Delete(configuration);
        ReadLocal(null);
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { confirmed = true }),
            "session.configurationOnly", "Le parcours local ne prépare jamais de mutation");
    }
}

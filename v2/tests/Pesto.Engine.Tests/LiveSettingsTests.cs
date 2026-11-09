using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>
/// Lot « configuration réelle » (revue 24/10, constat 2) : la convention de nommage configurable est réellement
/// lue, enregistrée et prise en compte selon le modèle V1 — pas seulement exposée en simulation. Un cfg.json V1 avec
/// NamingConvention (schéma fermé Schema/Id/Tokens/Widths/Types) commande la génération ET l'analyse inverse ;
/// settings.save écrit le cfg.json de l'installation fournie (validation avant écriture, empreinte de concurrence,
/// écriture atomique + cfg.json.bak, relecture/revalidation, invalidation des aperçus, plans et file) ; les champs
/// métier (domaine, préfixe, production, sites) restent la propriété de l'installation V1. Ces tests échouent
/// réellement si settings.save redevient un refus constant, si l'écriture ignore le motif demandé, ou si
/// SettingsGet/NamesPreview retombent sur le motif par défaut. Écritures limitées aux fixtures temporaires :
/// aucun AD, aucun service, aucun fichier hors dossier temporaire.
/// </summary>
internal sealed class LiveSettingsTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string ParisOu = "OU=Paris-Nord," + Container;
    private const string ComputerA = "P111301PAINF009";
    private const string GuidA = "11111111-1111-1111-1111-111111111111";

    /// <summary>Convention atelier du modèle V1 (NAMING_119) : numéro au milieu, préfixe 3 chiffres, service 2 caractères.</summary>
    private const string Atelier = """
{
  "Configured": true,
  "NamingConvention": { "Schema": 1, "Id": "atelier", "Tokens": ["Service", "Number", "Type", "Prefix", "Site"], "Widths": { "Prefix": 3, "Site": 2, "Service": 2, "Number": 2 }, "Types": "PSV" },
  "DEBUG": { "Simulation": "false", "GUI": "false", "HorsDomaine": "false", "MauvaiseOU": "false", "BPVerifNomAD": "false", "ForceADM": "false" },
  "CONF": [ { "Domaine": "EXAMPLE.LOCAL", "ADM": "EXAMPLE\\admin-postes", "Prefixe": "123", "PreprodSite": "76",
              "DirectProd": "false", "DarkMode": "2", "Buffer": "10", "OUScanNoms": "OU=Postes,DC=example,DC=local",
              "EntraPolicy": "HybridOnly", "ClearProtectionOnMove": "true" } ],
  "TAGS": [ { "Site": "PREPROD", "Tag": "PR" }, { "Site": "Paris*", "Tag": "PA" }, { "Site": "Lyon*", "Tag": "LY" } ],
  "OUBase": [ { "Nom": "ROOT", "OU": "OU=Postes,DC=example,DC=local" }, { "Nom": "PREPROD", "OU": "OU=Staging,OU=Postes,DC=example,DC=local" } ],
  "OUSite": [ { "Nom": "Siege", "OU": "OU=SITES,OU=Postes,DC=example,DC=local" } ],
  "NameCatalogue": [ { "Site": "PA", "Service": "IT" } ],
  "POLICY": { "Schema": 1, "MaxReaders": 4, "ReadAttempts": 2, "MaxBatch": 50, "RandomNameEnabled": false }
}
""";

    private sealed class World
    {
        public required IPestoBackend Backend { get; init; }
        public required FakeGateway Gateway { get; init; }
        public required string CfgPath { get; init; }
    }

    private static World Live(string cfgJson, bool withObservedComputer = false, IMutationGateway? mutation = null)
    {
        var root = LiveTestConfig.Write(cfgJson);
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] } };
        if (withObservedComputer)
            gateway.Find = name => name.Equals(ComputerA, StringComparison.OrdinalIgnoreCase)
                ? new Pesto.Engine.DirectoryComputer(ComputerA, null, ParisOu, null, GuidA, "example.local", null, null, null, null, null)
                : null;
        return new World
        {
            Backend = Harness.Live(root, gateway, mutation, new FixedClock()),
            Gateway = gateway,
            CfgPath = Path.Combine(root, "cfg.json"),
        };
    }

    private static object[] DeclaredSites() =>
    [
        new { id = "PR", name = "PREPROD", code = "PR", ou = "null" },
        new { id = "PA", name = "Paris*", code = "PA", ou = "null" },
        new { id = "LY", name = "Lyon*", code = "LY", ou = "null" },
    ];

    private static object SaveArgs(string namingPattern, bool randomNames = false, string domain = "example.local",
        string prefix = "111301", bool production = false, object[]? sites = null) =>
        new { domain, dc = "", prefix, production, namingPattern, randomNames, sites = sites ?? DeclaredSites() };

    private static string Read(World w) => File.ReadAllText(w.CfgPath, System.Text.Encoding.UTF8);

    // ---- la convention lue commande réellement le nommage --------------------------------

    [Test]
    public void SettingsGetReturnsThePatternActuallyRead()
    {
        var w = Live(Atelier);
        var settings = Harness.Call(w.Backend, "settings.get");
        Check.Equal("{service:2}{number:2}{type}{prefix}{site}", Harness.Str(settings, "namingPattern"),
            "settings.get rend le motif réellement lu dans le cfg.json, jamais le motif par défaut");
        Check.Equal("123", Harness.Str(settings, "prefix"), "Préfixe lu");
    }

    [Test]
    public void ReadConventionCommandsProposedName()
    {
        var w = Live(Atelier);
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "IT" });
        Check.Equal("IT01P123PA", Harness.Str(preview, "name"),
            "Le nom proposé suit la convention lue : service, numéro AU MILIEU, type, préfixe, site (port NAMING_119 v1)");
    }

    [Test]
    public void ReadConventionParsesObservedNamesAtConfiguredPositions()
    {
        var w = Live(Atelier);
        w.Gateway.ScopeNames = ["IT01P123PA", "HORSNOM", "XX99P123PA"];
        var items = Harness.Arr(Harness.Call(w.Backend, "directory.services", new { site = "PA" }), "items");
        Check.Equal(2, items.Count, "Services lus à la position que la convention leur donne (IT et XX vus, HORSNOM ignoré) + catalogue");
        Check.Equal("IT", Harness.Str(items[0]!, "code"), "Catalogue fusionné");
        Check.Equal("XX", Harness.Str(items[1]!, "code"), "Service analysé à la largeur configurée, pas à un offset fixe");
    }

    [Test]
    public void ConventionTypesSubsetCommandsPreview()
    {
        var w = Live(Atelier.Replace("\"Types\": \"PSV\"", "\"Types\": \"PS\""));
        Check.Pesto(() => Harness.Call(w.Backend, "names.preview", new { type = "V", site = "PA", service = "IT" }),
            "type.invalid", "La convention lue n'admet que P et S : V refusé, jamais proposé");
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "IT" });
        Check.Equal("IT01P123PA", Harness.Str(preview, "name"), "P reste admis");
    }

    // ---- settings.save : écriture réelle selon le modèle V1 --------------------------------

    [Test]
    public void SaveWritesConventionToCfgAndCommandsNaming()
    {
        var w = Live(LiveTestConfig.NoRandom);
        var before = Read(w);
        var settings = Harness.Call(w.Backend, "settings.save", SaveArgs("{type}{prefix}{site}{service}{number:2}"));
        Check.Equal("{type}{prefix}{site}{service}{number:2}", Harness.Str(settings, "namingPattern"), "La réponse rend la configuration enregistrée");
        var cfg = Read(w);
        Check.Contains("\"NamingConvention\"", cfg, "Le cfg.json porte réellement la convention enregistrée");
        Check.Contains("\"Number\": 2", cfg, "La largeur de numéro enregistrée vient du motif demandé");
        Check.True(File.Exists(w.CfgPath + ".bak"), "La sauvegarde cfg.json.bak est conservée (port Write-PestoAtomicText -Backup)");
        Check.Equal(before, File.ReadAllText(w.CfgPath + ".bak", System.Text.Encoding.UTF8), "La sauvegarde contient exactement l'ancienne version");
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.Equal("P111301PAINF01", Harness.Str(preview, "name"),
            "Le nom proposé après enregistrement suit le motif réellement écrit et relu — pas le motif par défaut");
    }

    [Test]
    public void SaveHistoricalDefaultRemovesTheConventionObject()
    {
        var w = Live(LiveTestConfig.NoRandom);
        Harness.Call(w.Backend, "settings.save", SaveArgs("{service}{number:2}{type}{prefix}{site}"));
        Check.Contains("\"NamingConvention\"", Read(w), "Convention personnalisée écrite");
        Harness.Call(w.Backend, "settings.save", SaveArgs(PestoSettings.DefaultPattern));
        Check.False(Read(w).Contains("NamingConvention", StringComparison.Ordinal),
            "Le retour à la convention historique supprime l'objet : l'absence conserve le format historique (port v1), rien d'inventé dans le fichier");
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.Equal("P111301PAINF001", Harness.Str(preview, "name"), "Le nommage est revenu à l'historique réellement relu");
    }

    [Test]
    public void SaveRejectsInvalidPatternWithoutTouchingDisk()
    {
        var w = Live(LiveTestConfig.NoRandom);
        var before = Read(w);
        Check.Pesto(() => Harness.Call(w.Backend, "settings.save", SaveArgs("{type}{prefix}{site}{service}")),
            "invalid_naming", "Un motif sans numéro est refusé par le moteur avant toute écriture");
        Check.Equal(before, Read(w), "Aucune écriture sur un motif refusé");
        Check.False(File.Exists(w.CfgPath + ".bak"), "Aucune sauvegarde parasite créée par un refus");
    }

    [Test]
    public void SaveRejectsConventionIncompatibleWithReadFacets()
    {
        var w = Live(LiveTestConfig.NoRandom);
        var before = Read(w);
        var error = Check.Pesto(() => Harness.Call(w.Backend, "settings.save", SaveArgs("{type}{prefix}{site:3}{service}{number:2}")),
            "config.invalid", "Site largeur 3 alors que les TAGS lus font 2 lettres : la validation intégrale v1 refuse, rien n'est écrit");
        Check.Contains("TAGS", error.Message, "La raison nomme la facette incompatible");
        Check.Equal(before, Read(w), "Le cfg.json est intact après refus");
    }

    [Test]
    public void SaveRefusesBusinessChangesWithoutWriting()
    {
        var w = Live(LiveTestConfig.NoRandom);
        var before = Read(w);
        Check.Pesto(() => Harness.Call(w.Backend, "settings.save", SaveArgs(PestoSettings.DefaultPattern, domain: "autre.local")),
            "config.business_readonly", "Le domaine appartient à l'installation V1");
        Check.Pesto(() => Harness.Call(w.Backend, "settings.save", SaveArgs(PestoSettings.DefaultPattern, prefix: "222222")),
            "config.business_readonly", "Le préfixe appartient à l'installation V1");
        Check.Pesto(() => Harness.Call(w.Backend, "settings.save", SaveArgs(PestoSettings.DefaultPattern, production: true)),
            "config.business_readonly", "L'environnement de production appartient à l'installation V1");
        Check.Pesto(() => Harness.Call(w.Backend, "settings.save",
                SaveArgs(PestoSettings.DefaultPattern, sites: [new { id = "PA", name = "Paris*", code = "PB", ou = "null" }])),
            "config.business_readonly", "Les sites (TAGS/OUSite) appartiennent à l'installation V1");
        Check.Pesto(() => Harness.Call(w.Backend, "settings.save",
                SaveArgs(PestoSettings.DefaultPattern, sites: [.. DeclaredSites(), new { id = "ML", name = "Melle*", code = "ML", ou = "null" }])),
            "config.business_readonly", "Ajouter un site depuis la v2 est refusé");
        Check.Pesto(() => Harness.Call(w.Backend, "settings.save",
                SaveArgs(PestoSettings.DefaultPattern, sites: [new { id = "PR", name = "PREPROD", code = "PR", ou = "OU=Staging,OU=Postes,DC=example,DC=local" }, DeclaredSites()[1], DeclaredSites()[2]])),
            "config.business_readonly", "Un OU saisi dans la zone sites n'est pas enregistré : les OU viennent de l'annuaire observé");
        Check.Equal(before, Read(w), "Aucune de ces tentatives n'a écrit le moindre octet");
    }

    [Test]
    public void SaveRefusesWhenCfgChangedOnDiskAfterLoad()
    {
        var w = Live(LiveTestConfig.NoRandom);
        Harness.Call(w.Backend, "settings.get");
        var external = LiveTestConfig.NoRandom.Replace("\"MaxBatch\": 50", "\"MaxBatch\": 77");
        File.WriteAllText(w.CfgPath, external, new System.Text.UTF8Encoding(false));
        var error = Check.Pesto(() => Harness.Call(w.Backend, "settings.save", SaveArgs("{type}{prefix}{site}{service}{number:2}")),
            "config.changed", "Port d'Assert-PestoConfigFileUnchanged : le fichier modifié en dehors de la session n'est jamais remplacé à l'aveugle");
        Check.Contains("Aucun fichier remplacé", error.Message, "La raison est explicite");
        Check.Contains("\"MaxBatch\": 77", Read(w), "La modification extérieure est restée intacte");
    }

    [Test]
    public void SaveRandomNamesPersistsAndCommandsSelection()
    {
        var w = Live(LiveTestConfig.Valid);
        Harness.Call(w.Backend, "settings.save", SaveArgs(PestoSettings.DefaultPattern, randomNames: false));
        Check.Contains("\"RandomNameEnabled\": false", Read(w), "POLICY.RandomNameEnabled est réellement enregistré");
        Check.False(Harness.Bool(Harness.Call(w.Backend, "settings.get"), "randomNames"), "settings.get rend la valeur relue du disque");
        var w2 = Live(LiveTestConfig.NoRandom);
        Harness.Call(w2.Backend, "settings.save", SaveArgs(PestoSettings.DefaultPattern, randomNames: true));
        Check.Contains("\"RandomNameEnabled\": true", Read(w2), "Activation réellement écrite");
        Check.True(Harness.Bool(Harness.Call(w2.Backend, "settings.get"), "randomNames"), "Relue depuis le disque");
    }

    [Test]
    public void SaveSynchronizesRandomNameChoiceToAvoidContradiction()
    {
        var w = Live(LiveTestConfig.Valid.Replace("\"RandomNameEnabled\": true", "\"RandomNameChoice\": 10"));
        Harness.Call(w.Backend, "settings.save", SaveArgs(PestoSettings.DefaultPattern, randomNames: false));
        var cfg = Read(w);
        Check.Contains("\"RandomNameEnabled\": false", cfg, "La valeur demandée est écrite");
        Check.Contains("\"RandomNameChoice\": 1", cfg, "RandomNameChoice est synchronisé : les deux clés ne se contredisent jamais (garde v1)");
        Check.False(Harness.Bool(Harness.Call(w.Backend, "settings.get"), "randomNames"), "La configuration relue est cohérente et acceptée par le validateur");
    }

    [Test]
    public void SaveKeepsUnrelatedConfigUntouched()
    {
        var w = Live(LiveTestConfig.NoRandom);
        Harness.Call(w.Backend, "settings.save", SaveArgs("{type}{prefix}{site}{service}{number:2}"));
        var cfg = Read(w);
        foreach (var kept in new[] { "\"MaxBatch\": 50", "OU=Postes,DC=example,DC=local", "\"Paris*\"", "\"INF\"", "\"PreprodSite\": \"765\"" })
            Check.Contains(kept, cfg, "Le reste du cfg.json V1 est conservé octet pour octet de valeur : " + kept);
    }

    [Test]
    public void SaveInvalidatesPreviewsPlansAndQueue()
    {
        var w = Live(LiveTestConfig.NoRandom, withObservedComputer: true, mutation: new FixtureEntraReadOnly());
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = ComputerA });
        var previewId = Harness.Str(preview, "previewId");
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = ComputerA, previewId });
        var planId = Harness.Str(plan, "planId");
        var second = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = ComputerA });
        Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer = ComputerA, previewId = Harness.Str(second, "previewId") });
        Check.Equal(1, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "File non vide avant l'enregistrement");

        Harness.Call(w.Backend, "settings.save", SaveArgs("{type}{prefix}{site}{service}{number:2}"));

        Check.Equal(0, Harness.Int(Harness.Call(w.Backend, "queue.list"), "count"), "La file est invalidée à l'enregistrement (Invalidate-PestoConfigurationPlans)");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.prepare"), "queue.empty", "Aucun lot ne survit à un changement de convention");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId, confirmationName = "P111301PAINF001" }),
            "plan.stale", "Un plan fondé sur l'ancienne convention n'est jamais exécutable : tout écriture doit être re-préparée et re-confirmée");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = ComputerA, previewId }),
            "plan.stale", "L'aperçu antérieur à l'enregistrement est obsolète : nouvel aperçu obligatoire");
        var fresh = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = ComputerA });
        Check.Equal("P111301PAINF01", Harness.Str(fresh, "name"), "Le nouveau calcul suit la convention enregistrée");
    }

    [Test]
    public void SettingsGetWithoutConfigHasNoInventedPattern()
    {
        var settings = Harness.Call(Harness.Live(null), "settings.get");
        Check.True(Harness.IsNull(settings, "namingPattern"), "Sans configuration lue, aucun motif n'est présenté comme actif");
    }

    [Test]
    public void SaveIsExposedThroughTheBridgeAndRefusesModeChanges()
    {
        var w = Live(LiveTestConfig.NoRandom);
        var envelope = Harness.DispatchAsync(w.Backend, "cfg-1", "settings.save",
            new { domain = "example.local", dc = "", prefix = "111301", production = false,
                namingPattern = "{type}{prefix}{site}{service}{number:2}", randomNames = false, sites = DeclaredSites(), simulation = true }).GetAwaiter().GetResult();
        Check.Equal("mode_fixed", Harness.ErrorCode(envelope), "Le mode ne se change pas depuis les paramètres, même via le pont");
        Check.False(Read(w).Contains("NamingConvention", StringComparison.Ordinal), "Refus = aucune écriture");
        var ok = Harness.DispatchAsync(w.Backend, "cfg-2", "settings.save",
            new { domain = "example.local", dc = "", prefix = "111301", production = false,
                namingPattern = "{type}{prefix}{site}{service}{number:2}", randomNames = false, sites = DeclaredSites() }).GetAwaiter().GetResult();
        Check.Null(ok["error"], "Le flux complet du pont enregistre réellement la convention");
        Check.Contains("\"Number\": 2", Read(w), "Écriture vérifiée via le pont fermé");
    }
}

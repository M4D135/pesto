using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>Écrit un cfg.json de test dans un dossier temporaire et rend le chemin de l'installation V1.</summary>
internal static class LiveTestConfig
{
    public const string Valid = """
{
  "Configured": true,
  "DEBUG": { "Simulation": "false", "GUI": "false", "HorsDomaine": "false", "MauvaiseOU": "false", "BPVerifNomAD": "false", "ForceADM": "false" },
  "CONF": [ { "Domaine": "EXAMPLE.LOCAL", "ADM": "EXAMPLE\\admin-postes", "Prefixe": "111301", "PreprodSite": "765",
              "DirectProd": "false", "DarkMode": "2", "Buffer": "10", "OUScanNoms": "OU=Postes,DC=example,DC=local",
              "EntraPolicy": "HybridOnly", "ClearProtectionOnMove": "true" } ],
  "TAGS": [ { "Site": "PREPROD", "Tag": "PR" }, { "Site": "Paris*", "Tag": "PA" }, { "Site": "Lyon*", "Tag": "LY" } ],
  "OUBase": [ { "Nom": "ROOT", "OU": "OU=Postes,DC=example,DC=local" }, { "Nom": "PREPROD", "OU": "OU=Staging,OU=Postes,DC=example,DC=local" } ],
  "OUSite": [ { "Nom": "Siege", "OU": "OU=SITES,OU=Postes,DC=example,DC=local" } ],
  "NameCatalogue": [ { "Site": "PA", "Service": "INF" } ],
  "POLICY": { "Schema": 1, "MaxReaders": 4, "ReadAttempts": 2, "MaxBatch": 50, "RandomNameEnabled": true }
}
""";

    /// <summary>Même configuration sans tirage au hasard : la sélection séquentielle devient déterministe pour les tests.</summary>
    public static readonly string NoRandom = Valid.Replace("\"RandomNameEnabled\": true", "\"RandomNameEnabled\": false");

    public static string Write(string json)
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-v1-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "cfg.json"), json, new System.Text.UTF8Encoding(false));
        return root;
    }
}

/// <summary>Annuaire en mémoire contrôlé : le moteur doit borner les lectures et ne jamais compléter un champ inconnu.</summary>
internal sealed class FakeGateway : Pesto.Engine.IDirectoryGateway, IAutomationNameInventory, IDirectoryAccountDisclosure, ILocalDomainMembership
{
    public string Description => "fixture de qualification";
    public string? SelectedAccount { get; set; }
    public bool? LocalComputerJoined { get; set; }
    public Dictionary<string, List<string>> ChildOus = new(StringComparer.OrdinalIgnoreCase);
    public Dictionary<string, int> ChildOuReads = new(StringComparer.OrdinalIgnoreCase);
    public List<Pesto.Engine.DirectoryComputer> Computers = [];
    public List<string> ScopeNames = [];
    public bool NamesComplete = true;
    public string? DiscoveredDc = "dc01.example.local";
    public Func<string, Pesto.Engine.DirectoryComputer?>? Find;
    public int LastSearchLimit;
    public int? LastMaxRows;
    public string? FailOn;
    public string? FailOnChildOu;
    public string OuGuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    public Func<string, DirectoryOrganizationalUnit?>? FindOu;

    public string? DiscoverDomainController(string domain)
    {
        Guard("dc");
        return DiscoveredDc;
    }

    public Pesto.Engine.DirectorySearchResult SearchComputers(string domain, string? dc, string query, int limit)
    {
        Guard("search");
        LastSearchLimit = limit;
        var matches = Computers.Where(c => c.Name.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();
        var complete = matches.Count <= limit;
        return new Pesto.Engine.DirectorySearchResult(matches.Take(limit).ToList(), complete);
    }

    public Pesto.Engine.DirectoryComputer? FindComputer(string domain, string? dc, string name)
    {
        Guard("find");
        return Find?.Invoke(name);
    }

    public DirectoryOrganizationalUnit? FindOrganizationalUnit(string domain, string? dc, string distinguishedName)
    {
        Guard("ou");
        return FindOu is not null ? FindOu(distinguishedName) : new DirectoryOrganizationalUnit(distinguishedName, OuGuid);
    }

    public IReadOnlyList<string> ListChildOuNames(string domain, string? dc, string parentOu)
    {
        ChildOuReads[parentOu] = ChildOuReads.GetValueOrDefault(parentOu) + 1;
        Guard("ous");
        if (string.Equals(parentOu, FailOnChildOu, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("directory.unavailable", "Panne simulée de lecture du second conteneur.");
        return ChildOus.TryGetValue(parentOu, out var names) ? names : [];
    }

    public Pesto.Engine.DirectoryNameInventory ListComputerNames(string domain, string? dc, string scopeOu, int maxRows)
    {
        Guard("names");
        LastMaxRows = maxRows;
        return new Pesto.Engine.DirectoryNameInventory(ScopeNames, NamesComplete);
    }

    public SiteComputerNames ReadSiteComputerNames(string domain, string? dc, string ou, IReadOnlyList<string> patterns, int maximum)
    {
        var local = ListComputerNames(domain, dc, ou, maximum);
        return new(local, new(DomainNames ?? [], NamesComplete));
    }

    public List<string>? DomainNames;
    public List<string> SeriesReads = [];
    public DirectoryNameInventory ListAutomationComputerNames(string domain, string dc, string pattern, int maximum)
    {
        Guard("names");
        SeriesReads.Add(pattern);
        LastMaxRows = maximum;
        return new(DomainNames ?? ScopeNames, NamesComplete);
    }

    private void Guard(string operation)
    {
        if (FailOn == operation) throw new PestoException("directory.unavailable", "Panne simulée de la fixture : " + operation + ".");
    }
}

internal sealed class LiveReadTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";

    private static (IPestoBackend Backend, FakeGateway Gateway) LiveWith(Pesto.Engine.IDirectoryGateway gateway)
        => (Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid), gateway), (FakeGateway)gateway);

    // ---- configuration V1 -------------------------------------------------------------

    [Test]
    public void SessionDisclosesTheSelectedDirectoryAccountWithoutClaimingAuthentication()
    {
        const string selectedAccount = "EXAMPLE\\operateur-ad-explicite";
        var gateway = new FakeGateway { SelectedAccount = selectedAccount };
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid), gateway);
        var localAccount = Harness.Str(Harness.Call(Harness.Live(null), "session.info"), "account");
        Check.False(localAccount == selectedAccount, "Le compte AD de la fixture est distinct de l’identité du processus");
        var session = Harness.Call(backend, "session.info");
        Check.Equal(selectedAccount, Harness.Str(session, "account"), "La barre de session annonce le compte réellement sélectionné pour AD");
        var checks = Harness.Arr(Harness.Call(backend, "diagnostics.read"), "checks");
        var directory = checks.Single(c => Harness.Str(c!, "label") == "Compte annuaire")!;
        var local = checks.Single(c => Harness.Str(c!, "label") == "Identité locale")!;
        Check.Contains(selectedAccount, Harness.Str(directory, "detail"), "L’identité du lecteur annuaire est divulguée");
        Check.Contains("ne prouve ni une authentification réussie ni les droits AD", Harness.Str(directory, "detail"), "Aucune promesse d’authentification ou de privilège");
        Check.Contains(localAccount, Harness.Str(local, "detail"), "Le diagnostic distingue l’identité Windows du processus");
        gateway.SelectedAccount = null;
        Check.Equal(localAccount, Harness.Str(Harness.Call(backend, "session.info"), "account"), "Sans compte explicite le lecteur utilise l’identité Windows");
    }

    [Test]
    public void SettingsReflectTheReadConfigAndNothingElse()
    {
        var settings = Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid)), "settings.get");
        Check.Equal("example.local", Harness.Str(settings, "domain"), "Le domaine vient du cfg.json lu, en minuscules");
        Check.Equal("111301", Harness.Str(settings, "prefix"), "Le préfixe vient du cfg.json lu");
        Check.False(Harness.Bool(settings, "production"), "DirectProd lu");
        Check.True(Harness.Bool(settings, "randomNames"), "RandomNameEnabled lu");
        Check.False(Harness.Bool(settings, "simulation"), "Le mode réel ne se déclare jamais simulation");
        Check.False(Harness.Bool(settings, "liveExecutionEnabled"), "Les écritures ne s'activent jamais par les paramètres");
        var sites = Harness.Arr(settings, "sites");
        Check.Equal(3, sites.Count, "Les trois sites déclarés du cfg.json sont listés");
        Check.True(Harness.IsNull(sites[0]!, "ou"), "Un OU non observé reste null, jamais deviné");
        var session = Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid)), "session.info");
        Check.Equal("example.local", Harness.Str(session, "domain"), "La session annonce le domaine lu");
    }

    [Test]
    public void NothingIsHardcodedWhenTheConfigNamesAnotherDomain()
    {
        var other = LiveTestConfig.Valid
            .Replace("EXAMPLE.LOCAL", "LABO.ENTREPRISE")
            .Replace("DC=example,DC=local", "DC=labo,DC=entreprise");
        var settings = Harness.Call(Harness.Live(LiveTestConfig.Write(other)), "settings.get");
        Check.Equal("labo.entreprise", Harness.Str(settings, "domain"), "Aucune valeur d’exemple : le domaine lu commande tout");
    }

    [Test]
    public void MissingOrInvalidConfigsAreRefusedWithActionableReasons()
    {
        // Les lectures annuaire exigent une configuration lue : c'est le chemin qui refuse, settings.get rend des null honnêtes.
        Check.Pesto(() => Harness.Call(Harness.Live(null), "directory.sites"), "config.missing", "Aucun dossier fourni");
        var emptyRoot = Path.Combine(Path.GetTempPath(), "pesto-v1-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(emptyRoot);
        Check.Pesto(() => Harness.Call(Harness.Live(emptyRoot), "directory.sites"), "config.missing", "Dossier sans cfg.json");
        Check.Pesto(() => Harness.Call(Harness.Live(Path.Combine(emptyRoot, "absent")), "directory.sites"), "config.missing", "Dossier inexistant");
        var settings = Harness.Call(Harness.Live(null), "settings.get");
        Check.True(Harness.IsNull(settings, "domain"), "Sans configuration, settings.get rend null, jamais un domaine d’exemple");

        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("EXAMPLE.LOCAL", "AUTRE.LOCAL"))), "directory.sites"),
            "config.invalid", "Un OU d’un autre domaine est refusé (domaine unique)");
        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"Schema\": 1", "\"Schema\": 1, \"Inconnue\": true"))), "directory.sites"),
            "config.invalid", "POLICY est un schéma fermé");
        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"MaxReaders\": 4", "\"MaxReaders\": 9"))), "directory.sites"),
            "config.invalid", "MaxReaders hors bornes refusé");
        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"HorsDomaine\": \"false\"", "\"HorsDomaine\": \"true\""))), "directory.sites"),
            "config.invalid", "DEBUG.HorsDomaine interdit en mode réel");
        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"Configured\": true", "\"Configured\": false"))), "directory.sites"),
            "config.invalid", "Configuration non validée refusée");
        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"Configured\": true,", "\"Configured\": true, \"NamingConvention\": { \"Pattern\": \"{type}{number:2}\" },"))), "directory.sites"),
            "config.invalid", "Convention hors du schéma fermé V1 (Schema/Id/Tokens/Widths/Types) : refus explicite");
        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"Configured\": true,",
            "\"Configured\": true, \"NamingConvention\": { \"Schema\": 1, \"Id\": \"large\", \"Tokens\": [\"Type\", \"Prefix\", \"Site\", \"Service\", \"Number\"], \"Widths\": { \"Prefix\": 20, \"Site\": 2, \"Service\": 3, \"Number\": 3 }, \"Types\": \"PSV\" },"))), "directory.sites"),
            "config.invalid", "Convention jamais acceptée aux forceps : largeurs bornées (Prefix 1 à 12)");
        Check.Pesto(() => Harness.Call(Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid.Replace("\"Configured\": true,",
            "\"Configured\": true, \"NamingConvention\": { \"Schema\": 1, \"Id\": \"types\", \"Tokens\": [\"Type\", \"Prefix\", \"Site\", \"Service\", \"Number\"], \"Widths\": { \"Prefix\": 6, \"Site\": 2, \"Service\": 3, \"Number\": 3 }, \"Types\": \"PSX\" },"))), "directory.sites"),
            "config.invalid", "Types hors sous-ensemble P/S/V refusés");
    }

    [Test]
    public void OversizedConfigIsRefusedNotParsed()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-v1-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        File.WriteAllText(Path.Combine(root, "cfg.json"), new string('x', 2 * 1024 * 1024));
        Check.Pesto(() => Harness.Call(Harness.Live(root), "directory.sites"), "config.invalid", "Fichier trop volumineux refusé avant analyse");
    }

    // ---- directory reads ---------------------------------------------------------------

    [Test]
    public void SitesComeFromConfigMatchedToObservedOus()
    {
        var gateway = new FakeGateway();
        gateway.ChildOus[Container] = ["Paris-Nord", "Lyon", "Autre"];
        var (backend, _) = LiveWith(gateway);
        var items = Harness.Arr(Harness.Call(backend, "directory.sites"), "items");
        Check.Equal(3, items.Count, "Les motifs et le repli V1 ne listent que des OU réellement observées");
        Check.Equal("PA", Harness.Str(items[0]!, "code"), "Code du site déclaré");
        Check.Equal("Paris-Nord", Harness.Str(items[0]!, "name"), "Nom réellement observé dans l’annuaire");
        Check.Equal("OU=Paris-Nord," + Container, Harness.Str(items[0]!, "ou"), "OU observé, jamais supposé");
        Check.Equal("LY", Harness.Str(items[1]!, "code"), "Second site observé");
        Check.Equal("Autre", Harness.Str(items[2]!, "name"), "L’OU sans TAGS est conservée");
        Check.Equal("RE", Harness.Str(items[2]!, "code"), "Repli V1 sur les dernières lettres du nom observé");
    }

    [Test]
    public void ABroadPatternNeverHidesSitesThatAMoreSpecificPatternNames()
    {
        // 2.0.10 dropped every OU matched by two codes: with a catch-all PREPROD pattern only PR sites were left.
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["TAGS"] = JsonNode.Parse("""
            [ { "Site": "*", "Tag": "PR" }, { "Site": "Paris*", "Tag": "PA" }, { "Site": "*-Nord", "Tag": "NO" }, { "Site": "Lyon*", "Tag": "LY" } ]
            """);
        var root = LiveTestConfig.Write(cfg.ToJsonString());
        try
        {
            var gateway = new FakeGateway { ChildOus = { [Container] = ["765_PREPROD", "Paris-Nord", "Lyon"] },
                ScopeNames = ["P111301PAINF001"], DomainNames = [],
                FindOu = dn => new(dn, Guid.NewGuid().ToString(), dn.Split(',')[0][3..]) };
            var backend = Harness.Live(root, gateway);
            var items = Harness.Arr(Harness.Call(backend, "directory.sites"), "items");
            Check.Equal("765_PREPROD:PR,Paris-Nord:PA,Lyon:LY", string.Join(',', items.Select(item => Harness.Str(item!, "name") + ":" + Harness.Str(item!, "code"))),
                "Chaque OU reste listée avec le motif le plus précis ; à précision égale, le premier TAGS déclaré");
            var services = Harness.Arr(Harness.Call(backend, "directory.services", new { site = Harness.Str(items[1]!, "selector") }), "items");
            Check.Equal("INF", string.Join(',', services.Select(item => Harness.Str(item!, "code"))), "Le site choisi garde le même code pour ses services");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void SitePatternsShareOneFreshReadPerContainerWithoutChangingOrder()
    {
        const string secondContainer = "OU=AutresSites,OU=Postes,DC=example,DC=local";
        var raw = JsonNode.Parse(LiveTestConfig.Valid)!.AsObject();
        raw["CONF"]![0]!["DirectProd"] = true;
        raw["TAGS"] = new JsonArray(Enumerable.Range(0, 30).Select(index => (JsonNode)new JsonObject
        {
            ["Site"] = $"Site-{index:D2}-*",
            ["Tag"] = $"{(char)('A' + index / 26)}{(char)('A' + index % 26)}"
        }).ToArray());
        raw["OUSite"]!.AsArray().Add(new JsonObject { ["Nom"] = "Autres", ["OU"] = secondContainer });
        var root = LiveTestConfig.Write(raw.ToJsonString());
        try
        {
            var gateway = new FakeGateway();
            gateway.ChildOus[Container] = Enumerable.Range(0, 30).Select(index => $"Site-{index:D2}-Nord").Append("Sans-correspondance").ToList();
            gateway.ChildOus[secondContainer] = Enumerable.Range(0, 30).Select(index => $"Site-{index:D2}-Sud").ToList();
            var backend = Harness.Live(root, gateway);
            var items = Harness.Arr(Harness.Call(backend, "directory.sites"), "items");
            Check.Equal(61, items.Count, "Les 30 motifs et l’OU sans motif restent visibles");
            Check.Equal("Sans-correspondance", Harness.Str(items[60]!, "name"), "Le repli est ajouté après les motifs déclarés");
            Check.Equal("CE", Harness.Str(items[60]!, "code"), "Code de repli V1");
            Check.Equal(1, gateway.ChildOuReads[Container], "Un seul appel annuaire pour le premier conteneur, pas 30");
            Check.Equal(1, gateway.ChildOuReads[secondContainer], "Un seul appel annuaire pour le second conteneur, pas 30");
            for (var index = 0; index < 30; index++)
            {
                var code = $"{(char)('A' + index / 26)}{(char)('A' + index % 26)}";
                Check.Equal($"Site-{index:D2}-Nord", Harness.Str(items[index * 2]!, "name"), "Ordre motif puis conteneur conservé");
                Check.Equal($"Site-{index:D2}-Sud", Harness.Str(items[index * 2 + 1]!, "name"), "Second conteneur au même rang de motif");
                Check.Equal(code, Harness.Str(items[index * 2]!, "id"), "Identifiant du premier site conservé");
                Check.Equal(code + "-2", Harness.Str(items[index * 2 + 1]!, "id"), "Dédoublonnage d’identifiant conservé");
            }

            gateway.ChildOus[Container].Remove("Site-00-Nord");
            var refreshed = Harness.Arr(Harness.Call(backend, "directory.sites"), "items");
            Check.Equal(60, refreshed.Count, "La demande suivante observe la suppression d’une OU");
            Check.Equal(2, gateway.ChildOuReads[Container], "Aucun cache persistant entre deux demandes");
            Check.Equal(2, gateway.ChildOuReads[secondContainer], "Chaque conteneur est relu à la demande suivante");
            Check.Equal("Site-00-Sud", Harness.Str(refreshed[0]!, "name"), "Aucune ancienne OU n’est réutilisée");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void SiteReadFailureNeverPublishesOrRetainsAPartialSnapshot()
    {
        const string secondContainer = "OU=AutresSites,OU=Postes,DC=example,DC=local";
        var raw = JsonNode.Parse(LiveTestConfig.Valid)!.AsObject();
        raw["OUSite"]!.AsArray().Add(new JsonObject { ["Nom"] = "Autres", ["OU"] = secondContainer });
        var root = LiveTestConfig.Write(raw.ToJsonString());
        try
        {
            var gateway = new FakeGateway { FailOnChildOu = secondContainer };
            gateway.ChildOus[Container] = ["Paris-Nord"];
            var backend = Harness.Live(root, gateway);
            Check.Pesto(() => Harness.Call(backend, "directory.sites"), "directory.unavailable", "L’échec de lecture remonte, sans résultat partiel");
            Check.Equal(1, gateway.ChildOuReads[Container], "Le premier conteneur a été lu avant l’échec du second");
            Check.Equal(1, gateway.ChildOuReads[secondContainer], "La résolution s’arrête au second conteneur en échec");
            gateway.FailOnChildOu = null;
            gateway.ChildOus[Container] = ["Lyon"];
            var retried = Harness.Arr(Harness.Call(backend, "directory.sites"), "items");
            Check.Equal(1, retried.Count, "Seule l’OU réellement relue est publiée");
            Check.Equal("Lyon", Harness.Str(retried[0]!, "name"), "L’ancien contenu n’est pas conservé après l’échec");
            Check.Equal(2, gateway.ChildOuReads[Container], "La nouvelle demande relit le conteneur une seule fois");
            Check.Equal(2, gateway.ChildOuReads[secondContainer], "Le conteneur en échec est lui aussi relu une seule fois");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void AlternateDnEncodingStillUsesTheObservedNameForTheTag()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        try
        {
            var ou = @"OU=Paris\2CNord," + Container;
            var gateway = new FakeGateway { FindOu = dn => new(dn, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "Paris,Nord") };
            var backend = Harness.Live(root, gateway);
            var preview = Harness.Call(backend, "names.preview", new { type = "S", site = ou, service = "INF" });
            Check.Equal("S111301PAINF001", Harness.Str(preview, "name"), "Un DN historique encodé garde le TAG du nom AD observé");
            Check.Equal(ou, Harness.Str(preview, "ou"), "L’aperçu conserve le DN observé sans normalisation");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void PreviewWithoutDcStopsBeforeOuOrInventoryAndRecoversOnNextRequest()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        try
        {
            var site = "OU=Paris-Nord," + Container;
            var gateway = new FakeGateway { DiscoveredDc = null, FindOu = _ => throw new InvalidOperationException("Unexpected OU query") };
            var backend = Harness.Live(root, gateway);
            var args = new { type = "P", site, service = "INF" };
            Check.Pesto(() => Harness.Call(backend, "names.preview", args), "names.unavailable", "DC absent : refus avant même l’OU");
            Check.Equal(0, gateway.SeriesReads.Count, "Aucun inventaire sans contrôleur");
            gateway.DiscoveredDc = "dc01.example.local";
            gateway.FindOu = dn => new(dn, gateway.OuGuid, "Paris-Nord");
            Check.Equal("P111301PAINF001", Harness.Str(Harness.Call(backend, "names.preview", args), "name"), "Le nouvel appel redécouvre le DC");
            gateway.FindOu = dn => new(dn, gateway.OuGuid, "Lyon");
            Check.Pesto(() => Harness.Call(backend, "names.preview", args), "site.invalid", "L’OU est revérifiée même quand le DC n’a pas changé");
            Check.Equal(1, gateway.SeriesReads.Count, "Aucune nouvelle lecture de série si le nom de l’OU a changé");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void SelectedOuUsesTheExactV1TagAndReadsServicesAcrossThePark()
    {
        const string site = "131_PROD_A,NOMMER";
        var ou = @"OU=131_PROD_A\,NOMMER," + Container;
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["TAGS"]!.AsArray().Insert(0, new JsonObject { ["Site"] = "*_PROD_*", ["Tag"] = "XX" });
        cfg["TAGS"]!.AsArray().Add(new JsonObject { ["Site"] = site, ["Tag"] = "PR" });
        var root = LiveTestConfig.Write(cfg.ToJsonString());
        try
        {
            var gateway = new FakeGateway { ChildOus = { [Container] = [site] },
                ScopeNames = ["S111301LYADM001"], DomainNames = ["V111301PR765007", "P111301LYBAD001"],
                FindOu = dn => dn == ou ? new(dn, Guid.NewGuid().ToString(), site) : null };
            var backend = Harness.Live(root, gateway);
            var sites = Harness.Arr(Harness.Call(backend, "directory.sites"), "items");
            Check.Equal(1, sites.Count, "Une seule entrée pour l’OU même avec un motif plus large");
            Check.Equal("PR", Harness.Str(sites[0]!, "code"), "Le TAG exact de la V1 est prioritaire");
            var selector = Harness.Str(sites[0]!, "selector");
            Check.Equal(ou, selector, "La sélection reste liée à l’OU si la liste change");
            var services = Harness.Arr(Harness.Call(backend, "directory.services", new { site = selector }), "items");
            Check.Equal("765,ADM", string.Join(',', services.Select(item => Harness.Str(item!, "code"))), "Services du site par OU ou par tag dans le domaine");
            var preview = Harness.Call(backend, "names.preview", new { type = "P", site = selector, service = "765" });
            Check.Equal("P111301PR765001", Harness.Str(preview, "name"), "La série P est distincte de V");
            Check.Equal(1, gateway.ChildOuReads[Container], "Choisir un site puis calculer ne réénumère pas les autres sites");
            gateway.DomainNames = ["S111301PRFIN009"];
            services = Harness.Arr(Harness.Call(backend, "directory.services", new { site = selector }), "items");
            Check.Equal("ADM,FIN", string.Join(',', services.Select(item => Harness.Str(item!, "code"))), "La demande suivante voit le service ajouté et le retrait de 765");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void HomeCanReadReceiptsWithoutBlockingOnAWholeParkScan()
    {
        var gateway = new FakeGateway { FailOn = "names" };
        var (backend, _) = LiveWith(gateway);
        var light = Harness.Call(backend, "dashboard.read", new { inventory = false });
        Check.True(Harness.IsNull(light, "computers") && !Harness.Bool(light, "inventoryRead"), "Les compteurs restent à lire");
        Check.Equal(0, gateway.ChildOuReads.Count, "Aucune énumération de sites au démarrage");
        Check.Pesto(() => Harness.Call(backend, "dashboard.read"), "directory.unavailable", "Le bouton d’actualisation tente une vraie lecture");
    }

    [Test]
    public void ServicesComeFromObservedNamesAndCatalogue()
    {
        var gateway = new FakeGateway();
        gateway.ChildOus[Container] = ["Paris-Nord"];
        gateway.ScopeNames = ["P111301PAINF001", "S111301PAADM002", "HORSNOMME", "V111301LYLOG001"];
        var (backend, _) = LiveWith(gateway);
        var items = Harness.Arr(Harness.Call(backend, "directory.services", new { site = "PA" }), "items");
        Check.Equal(1, gateway.ChildOuReads[Container], "La résolution de site des services partage aussi une seule lecture par conteneur");
        Check.Equal(3, items.Count, "Un poste dans l’OU du site fournit aussi son service même si son nom porte un autre tag");
        Check.Equal("ADM", Harness.Str(items[0]!, "code"), "Services triés");
        Check.Equal("INF", Harness.Str(items[1]!, "code"), "Catalogue NameCatalogue bien fusionné");
        Check.Equal(20000, gateway.LastMaxRows!.Value, "Lecture d’inventaire bornée par le plafond dur");
        gateway.NamesComplete = false;
        Check.Pesto(() => Harness.Call(backend, "directory.services", new { site = "PA" }), "directory.incomplete", "Lecture incomplète = inconnu, jamais une liste partielle présentée comme fiable");
        Check.Pesto(() => Harness.Call(backend, "directory.services", new { site = "inexistant" }), "site.invalid", "Site inconnu refusé");
    }

    [Test]
    public void SearchIsBoundedAndNeverFillsUnknownFields()
    {
        var gateway = new FakeGateway();
        gateway.Computers =
        [
            new("HORS-CONVENTION", null, "OU=Paris-Nord," + Container, null, null, "example.local", null, null, null, null, null),
            new("P111301PAINF001", "p111301painf001.example.local", "OU=Paris-Nord," + Container, "Windows 11 Pro", "11111111-1111-1111-1111-111111111111", "example.local", null, null, null, null, null),
            new("P111301PAINF002", null, "OU=Paris-Nord," + Container, null, null, "example.local", null, null, null, null, null),
        ];
        var (backend, _) = LiveWith(gateway);
        var result = Harness.Call(backend, "directory.search", new { query = "N", limit = 2 });
        Check.Equal(2, Harness.Arr(result, "items").Count, "La limite demandée est un plafond dur");
        Check.False(Harness.Bool(result, "complete"), "Trois postes correspondent : la lecture n’est pas complète");
        Check.Equal(2, gateway.LastSearchLimit, "La limite transmise au lecteur est celle demandée");
        var first = Harness.Arr(result, "items")[0]!;
        Check.Equal("HORS-CONVENTION", Harness.Str(first, "name"), "Ordre du lecteur conservé");
        Check.True(Harness.IsNull(first, "type"), "Nom hors convention : type null, jamais deviné depuis le matériel");
        Check.True(Harness.IsNull(first, "site"), "Nom hors convention : site null, jamais deviné");
        Check.True(Harness.IsNull(first, "service"), "Nom hors convention : service null");
        Check.True(Harness.IsNull(first, "os"), "Champ non observé : null");
        Check.True(Harness.IsNull(first, "manufacturer"), "Fabricant jamais inventé");
        Check.True(Harness.IsNull(first, "pendingRestart"), "Redémarrage inconnu pour un poste distant");
        Check.Equal("known", Harness.Str(first, "status"), "Statut : objet réellement observé dans l’annuaire");
        var parsed = Harness.Arr(result, "items")[1]!;
        Check.Equal("P", Harness.Str(parsed, "type"), "Type issu de la convention configurée");
        Check.Equal("PA", Harness.Str(parsed, "site"), "Facettes dérivées par la convention, pas par un offset fixe");
        Check.Equal("INF", Harness.Str(parsed, "service"), "Service lu à la position que la convention lui donne");
        Check.False(string.IsNullOrEmpty(Harness.Str(result, "collectedAt")), "Horodatage de la lecture");
        Check.Pesto(() => Harness.Call(backend, "directory.search", new { query = "N", limit = 500 }), "invalid_arguments", "Plafond dur de 100 par page");
    }

    [Test]
    public void InspectReportsObservedFactsAndScope()
    {
        var gateway = new FakeGateway();
        gateway.Find = name => name.Equals("P111301PAINF001", StringComparison.OrdinalIgnoreCase)
            ? new("P111301PAINF001", "p111301painf001.example.local", "OU=Paris-Nord," + Container, "Windows 11 Pro", "11111111-1111-1111-1111-111111111111", "example.local", null, null, null, null, null)
            : name.Equals("HORS-SCOPE", StringComparison.OrdinalIgnoreCase)
                ? new("HORS-SCOPE", null, "OU=Autres,DC=example,DC=local", null, null, "example.local", null, null, null, null, null)
                : name.Equals("SANS-OU", StringComparison.OrdinalIgnoreCase)
                    ? new("SANS-OU", null, null, null, null, "example.local", null, null, null, null, null)
                : null;
        var (backend, _) = LiveWith(gateway);
        var found = Harness.Call(backend, "computer.inspect", new { computer = "P111301PAINF001" });
        Check.Equal("P111301PAINF001", Harness.Str(found, "name"), "Nom observé");
        Check.Equal("PA", Harness.Str(found, "site"), "Facettes dérivées de la convention appliquée au nom observé");
        var scope = Harness.Arr(found, "checks").Single(c => c!["label"]!.GetValue<string>() == "Périmètre")!;
        Check.Equal("ok", scope["state"]!.GetValue<string>(), "Sous la racine gérée configurée");
        Check.True(found["inManagedScope"]!.GetValue<bool>(), "L’inspection confirme le périmètre sans interpréter le texte affiché");
        var outside = Harness.Call(backend, "computer.inspect", new { computer = "HORS-SCOPE" });
        var outsideScope = Harness.Arr(outside, "checks").Single(c => c!["label"]!.GetValue<string>() == "Périmètre")!;
        Check.Equal("warn", outsideScope["state"]!.GetValue<string>(), "Hors racine : annoncé, aucune opération ne sera proposée");
        Check.False(outside["inManagedScope"]!.GetValue<bool>(), "Une OU extérieure est distinguée d’une OU non observée");
        var uncertain = Harness.Call(backend, "computer.inspect", new { computer = "SANS-OU" });
        Check.True(uncertain.AsObject().ContainsKey("inManagedScope") && uncertain["inManagedScope"] is null, "L’OU absente donne un périmètre explicitement inconnu");
        Check.Pesto(() => Harness.Call(backend, "computer.inspect", new { computer = "ABSENT" }), "computer.missing", "Absence confirmée, pas un objet vide inventé");
        Check.Pesto(() => Harness.Call(backend, "computer.inspect", new { computer = "mauvais nom!" }), "invalid_arguments", "Nom validé avant toute requête annuaire");
    }

    [Test]
    public void InspectPreservesTheNamingTypeWhenTheHardwareModelIsUnknown()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.Valid);
        try
        {
            var gateway = new FakeGateway
            {
                Find = name => new DirectoryComputer(name, null, "OU=Paris-Nord," + Container, null,
                    "11111111-1111-1111-1111-111111111111", "example.local", null, null, null, null, null)
            };
            var backend = Harness.Live(root, gateway);
            foreach (var type in new[] { "P", "S", "V" })
            {
                var observed = Harness.Call(backend, "computer.inspect", new { computer = type + "111301PAINF001" });
                Check.Equal(type, Harness.Str(observed, "type"), "La facette exacte du nom observé est disponible pour le formulaire");
                Check.True(Harness.IsNull(observed, "model"), "Le matériel reste inconnu : aucune sonde ni déduction de modèle");
            }
            var outside = Harness.Call(backend, "computer.inspect", new { computer = "ANCIEN-POSTE" });
            Check.True(Harness.IsNull(outside, "type"), "Un nom hors convention ne fournit aucun type implicite");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void GatewayFailuresSurfaceAsActionableRefusals()
    {
        var gateway = new FakeGateway();
        gateway.ChildOus[Container] = ["Paris-Nord"];
        gateway.FailOn = "ous";
        var (backend, _) = LiveWith(gateway);
        Check.Pesto(() => Harness.Call(backend, "directory.sites"), "directory.unavailable", "Panne du lecteur annoncée, jamais masquée par un succès");
    }

    [Test]
    public void WritesStayRefusedEvenWithGateway()
    {
        var gateway = new FakeGateway();
        gateway.ChildOus[Container] = ["Paris-Nord"];
        var (backend, _) = LiveWith(gateway);
        // Depuis le lot mutations : prepare planifie sans écrire mais n'invente jamais un nom — l'aperçu vérifié reste obligatoire.
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = "P111301PAINF001" }),
            "preview.missing", "Préparation sans écriture, jamais sans aperçu dont la disponibilité a été lue");
        Check.Pesto(() => Harness.Call(backend, "operation.execute", new { planId = "plan-1", confirmationName = "P111301PAINF001" }),
            "plan.stale", "Aucun plan n'existe sans préparation : rien n'est envoyé");
        Check.Pesto(() => Harness.Call(backend, "queue.add", new { kind = "rename", computer = "P111301PAINF001" }),
            "preview.missing", "Aucune ligne de file sans aperçu dont la disponibilité a été lue : le nom n'est jamais calculé à la volée");
        Check.Pesto(() => Harness.Call(backend, "queue.execute", new { batchId = "batch-1", confirmed = true }),
            "batch.stale", "Aucun lot sans préparation relue : rien n'est envoyé");
        // Depuis le lot « configuration réelle » : settings.save écrit le cfg.json de l'installation fournie, mais les
        // champs métier (domaine, préfixe, production, sites) appartiennent à l'installation V1 et doivent revenir
        // inchangés. Un changement métier reste refusé, sans aucune écriture.
        Check.Pesto(() => Harness.Call(backend, "settings.save", new { domain = "a.local", dc = "", prefix = "1", production = false,
            namingPattern = PestoSettings.DefaultPattern, randomNames = false, sites = new object[] { new { id = "p", name = "P", code = "PA", ou = "OU=P,DC=a,DC=local" } } }),
            "config.business_readonly", "Aucun changement métier écrit depuis la v2 : domaine, préfixe et sites refusés");
    }

    // ---- names.preview live ---------------------------------------------------------------

    private static (IPestoBackend Backend, FakeGateway Gateway) LivePreviewGateway(params string[] takenNames)
    {
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] }, ScopeNames = [.. takenNames] };
        return (Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), gateway), gateway);
    }

    [Test]
    public void NamesPreviewProposesOnlyANameObservedFree()
    {
        var (backend, gateway) = LivePreviewGateway("P111301PAINF001", "P111301PAINF003", "S111301PAINF002");
        var p = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.Equal("P111301PAINF002", Harness.Str(p, "name"), "Premier numéro réellement libre (001 et 003 pris ; le S voisin ne compte pas)");
        Check.True(Harness.Bool(p, "complete"), "Lecture complète : le nom est confirmé libre");
        Check.Contains("annuaire réel", Harness.Str(p, "source"), "La source annonce une lecture réelle");
        Check.False(Harness.Str(p, "source").Contains("simulation", StringComparison.OrdinalIgnoreCase), "Un aperçu live ne provient jamais de la simulation");
        Check.Equal("OU=Paris-Nord," + Container, Harness.Str(p, "ou"), "OU réellement observée du site");
        Check.Equal(997, Harness.Int(p, "availableCount"), "999 candidats moins les 2 noms P pris ; le S voisin ne compte pas");
        Check.False(string.IsNullOrEmpty(Harness.Str(p, "previewId")), "Un aperçu horodaté est enregistré");
        Check.False(string.IsNullOrEmpty(Harness.Str(p, "collectedAt")), "Horodatage de la lecture");
        Check.False(string.IsNullOrEmpty(Harness.Str(p, "expiresAt")), "Expiration de l’aperçu");
        Check.Equal(20000, gateway.LastMaxRows!.Value, "Inventaire borné par le plafond dur");
    }

    [Test]
    public void NamesPreviewRefusesPartialReadsAndBadArguments()
    {
        var (backend, gateway) = LivePreviewGateway("P111301PAINF001");
        gateway.NamesComplete = false;
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" }),
            "names.unavailable", "Lecture incomplète = inconnu : jamais un nom proposé sur une liste partielle");
        gateway.NamesComplete = true;
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "X", site = "PA", service = "INF" }), "type.invalid", "Type hors P/S/V refusé");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "IN" }), "service.invalid", "Service hors convention refusé");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "inexistant", service = "INF" }), "site.invalid", "Site non observé refusé");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = "mauvais nom!" }),
            "invalid_arguments", "Nom de poste validé avant toute requête annuaire");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = "ABSENT" }),
            "computer.missing", "Poste absent confirmé : aucun aperçu de renommage");
        gateway.FailOn = "names";
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" }),
            "directory.unavailable", "Panne du lecteur remontée, jamais masquée par un nom");
    }

    [Test]
    public void NamesPreviewReadsOccupancyAgainAfterANameIsReleased()
    {
        var (backend, gateway) = LivePreviewGateway();
        var firstCall = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        var first = Harness.Str(firstCall, "name");
        Check.Equal("P111301PAINF001", first, "Sélection séquentielle sans RandomNameEnabled");
        gateway.ScopeNames = ["P111301PAINF001"];
        var second = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.Equal("P111301PAINF002", Harness.Str(second, "name"), "Nom pris entre-temps : nom suivant, nouvel aperçu, nouveau clic");
        Check.False(Harness.Str(second, "previewId") == Harness.Str(firstCall, "previewId"), "Chaque aperçu porte son propre identifiant : l’ancien est obsolète");
        gateway.ScopeNames = [];
        Check.Equal(first, Harness.Str(Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" }), "name"),
            "Une nouvelle lecture complète et la vérification exacte voient le numéro libéré");
    }

    [Test]
    public void PreviewUsesTheDomainSnapshotAndLeavesTheRaceCheckToRename()
    {
        var (backend, gateway) = LivePreviewGateway();
        gateway.DomainNames = ["P111301PAINF001", "P111301PAINF002"];
        gateway.Find = _ => throw new TestFailureException("La lecture de la série ne sonde pas chaque numéro.");
        var p = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.Equal("P111301PAINF003", Harness.Str(p, "name"), "Premier trou de la série du domaine");
        Check.Equal(997, Harness.Int(p, "availableCount"), "Deux noms occupés dans la série complète");
    }

    [Test]
    public void NamesPreviewSkipsOccupiedDomainAliasesInOneSeriesRead()
    {
        var (backend, gateway) = LivePreviewGateway();
        gateway.ChildOus[Container] = ["131_PROD_A_NOMMER"];
        var cfg = JsonNode.Parse(LiveTestConfig.NoRandom)!.AsObject();
        cfg["TAGS"]!.AsArray().Insert(0, new JsonObject { ["Site"] = "131_PROD_A_NOMMER", ["Tag"] = "PR" });
        backend = Harness.Live(LiveTestConfig.Write(cfg.ToJsonString()), gateway);
        gateway.DomainNames = Enumerable.Range(1, 12).Select(n => $"P111301PR765{n:D3}").ToList();
        var exactReads = 0;
        gateway.Find = name => { exactReads++; return null; };
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PR", service = "765" });
        Check.Equal("P111301PR765013", Harness.Str(preview, "name"), "Les douze noms pris ailleurs dans le domaine sont écartés en une lecture");
        Check.Equal(0, exactReads, "Une lecture de la série, aucun sondage unitaire des candidats");
        Check.Equal("P111301PR765*", gateway.SeriesReads.Single(), "La requête porte sur la série de la convention");
        gateway.DomainNames.Remove("P111301PR765004");
        Check.Equal("P111301PR765004", Harness.Str(Harness.Call(backend, "names.preview", new { type = "P", site = "PR", service = "765" }), "name"),
            "La demande suivante voit immédiatement le trou libéré dans le parc");
    }

    [Test]
    public void NamesPreviewRandomSelectionStaysInsideTheObservedFreeSet()
    {
        var gateway = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] } };
        for (var n = 1; n <= 999; n++)
            if (n != 404) gateway.ScopeNames.Add("P111301PAINF" + n.ToString("D3"));
        var backend = Harness.Live(LiveTestConfig.Write(LiveTestConfig.Valid), gateway);
        var p = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        Check.Equal("P111301PAINF404", Harness.Str(p, "name"), "Même en tirage au hasard, seul le nom réellement libre observé est proposé");
        Check.Equal(1, Harness.Int(p, "availableCount"), "Un seul libre observé");
    }

    [Test]
    public void NamesPreviewRefusesWhenEveryCandidateIsTaken()
    {
        var names = new List<string>();
        for (var n = 1; n <= 999; n++) names.Add("P111301PAINF" + n.ToString("D3"));
        var (backend, _) = LivePreviewGateway([.. names]);
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" }),
            "names.exhausted", "Série épuisée dans la portée : refus motivé, jamais un nom hors convention");
    }

    [Test]
    public void NamesPreviewAlternativeNeverRepeatsTheLastProposal()
    {
        var (backend, _) = LivePreviewGateway();
        var first = Harness.Str(Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" }), "name");
        var second = Harness.Str(Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", alternative = true }), "name");
        var third = Harness.Str(Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", alternative = true }), "name");
        Check.False(second == first, "Autre nom : différent de la dernière proposition");
        Check.False(third == second, "Autre nom encore : encore différent");
    }

    [Test]
    public void NamesPreviewRenameKeepsTheObservedOuAndRefusesTheUnknownOne()
    {
        var (backend, gateway) = LivePreviewGateway();
        gateway.Find = (name) => name.Equals("P111301PAINF009", StringComparison.OrdinalIgnoreCase)
            ? new Pesto.Engine.DirectoryComputer(name, null, "OU=Ateliers,OU=Paris-Nord," + Container, null, null, "example.local", null, null, null, null, null)
            : name.Equals("P111301PAINF010", StringComparison.OrdinalIgnoreCase)
                ? new Pesto.Engine.DirectoryComputer(name, null, null, null, null, "example.local", null, null, null, null, null)
                : name.Equals("V111301LYINF001", StringComparison.OrdinalIgnoreCase)
                    ? new Pesto.Engine.DirectoryComputer(name, null, "OU=Lyon," + Container, null, null, "example.local", null, null, null, null, null)
                    : null;
        var sameSite = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = "P111301PAINF009" });
        Check.Equal("OU=Ateliers,OU=Paris-Nord," + Container, Harness.Str(sameSite, "ou"), "Même site : OU réellement observée conservée, jamais ramenée à la racine du site");
        Check.Pesto(() => Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = "P111301PAINF010" }),
            "names.unavailable", "OU du poste non observée : destination inconnue, aucun OU supposé");
        var otherSite = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer = "V111301LYINF001" });
        Check.Equal("OU=Paris-Nord," + Container, Harness.Str(otherSite, "ou"), "Changement de site : OU observée du site cible");
    }

    [Test]
    public void DiagnosticsReportObservedConfigAndAdapter()
    {
        var gateway = new FakeGateway();
        gateway.ChildOus[Container] = ["Paris-Nord"];
        var (backend, _) = LiveWith(gateway);
        var diagnostics = Harness.Call(backend, "diagnostics.read");
        Check.Equal("ok", State(diagnostics, "Configuration V1"), "cfg.json lu : état ok");
        Check.Equal("ok", State(diagnostics, "Active Directory"), "Adaptateur actif annoncé");
        Check.Equal("ok", State(diagnostics, "Contrôleur"), "Contrôleur réellement découvert");
        var session = Harness.Call(backend, "session.info");
        Check.Equal("dc01.example.local", Harness.Str(session, "dc"), "Le DC affiché est celui observé");
    }

    private static string State(JsonNode diagnostics, string label) =>
        Harness.Arr(diagnostics, "checks").Single(c => c!["label"]!.GetValue<string>() == label)!["state"]!.GetValue<string>();
}

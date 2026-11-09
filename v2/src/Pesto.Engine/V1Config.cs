using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>
/// Lecteur du cfg.json d'une installation V1 passée en paramètre. Aucune valeur métier n'est codée en dur :
/// domaine, préfixe, sites, OU et politique viennent uniquement du fichier relu, validé selon les règles v1
/// (Test-CfgValid et ConvertTo-PestoPolicy portés). Un fichier manquant ou invalide est refusé avec une raison
/// exploitable, jamais complété par des valeurs d'exemple. Domaine unique : tout DN dont la partie DC diffère
/// du Domaine configuré est refusé.
/// </summary>
internal sealed class V1Config
{
    public const long MaximumFileBytes = 1024 * 1024;

    public sealed record DeclaredSite(string Pattern, string Tag);
    public sealed record CataloguePair(string Site, string Service);

    /// <summary>
    /// Convention de nommage lue dans le cfg.json (port de Assert-PestoNamingConvention). Son absence dans le fichier
    /// conserve le format historique {type}{prefix}{site}{service}{number:3} : aucun cfg.json existant ne change de sens.
    /// </summary>
    public sealed record NamingConventionModel(string Id, IReadOnlyList<string> Tokens, int PrefixWidth, int SiteWidth, int ServiceWidth, int NumberWidth, string Types)
    {
        /// <summary>Rendu canonique de la convention sous la forme du contrat du pont (motif à jetons, sans séparateur : V1 n'en connaît pas).</summary>
        public string ToPattern() => string.Concat(Tokens.Select(token => token switch
        {
            "Type" => Types == "PSV" ? "{type}" : "{type:" + Types + "}",
            "Prefix" => "{prefix}",
            "Site" => SiteWidth == 2 ? "{site}" : "{site:" + SiteWidth + "}",
            "Service" => ServiceWidth == 3 ? "{service}" : "{service:" + ServiceWidth + "}",
            _ => "{number:" + NumberWidth + "}",
        }));
    }

    public required string Domain { get; init; }
    public required string Prefix { get; init; }
    public required string PreprodSite { get; init; }
    public required bool Production { get; init; }
    public required bool RandomNames { get; init; }
    public required string RootOu { get; init; }
    public string? PreprodOu { get; init; }
    public required IReadOnlyList<DeclaredSite> DeclaredSites { get; init; }
    public required IReadOnlyList<string> OrganismOus { get; init; }
    public required IReadOnlyList<CataloguePair> NameCatalogue { get; init; }
    public IReadOnlyList<Site> ExplicitSites { get; init; } = [];
    public IReadOnlyDictionary<string, string> ServiceLabels { get; init; } = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    public required NamingConventionModel Convention { get; init; }
    public string NamingPattern => Convention.ToPattern();
    public int ReadAttempts { get; init; } = 2;
    public int MaxReaders { get; init; } = 4;
    public int MaxBatch { get; init; } = 200;
    public bool UnattendedJoinEnabled { get; init; }
    public bool UnattendedOperationsEnabled { get; init; }
    /// <summary>V1 applies HybridOnly when this historical setting is absent/empty. New V2 profiles explicitly write Disabled.</summary>
    public string EntraPolicy { get; init; } = EntraPreparationRules.HybridOnly;
    public V1OperationPolicy OperationPolicy { get; init; } = V1OperationPolicy.Default;

    /// <summary>La convention réellement lue commande la génération et l'analyse inverse des noms.</summary>
    public NamingConvention BuildConvention() => new(NamingPattern, Prefix);

    /// <summary>Chemin du cfg.json d'une installation V1, ou <c>null</c> si aucune installation n'a été fournie.</summary>
    public static string? ConfigPathOf(string? installationPath) =>
        V1ConfigDirectory.Resolve(installationPath) is { } directory ? Path.Combine(directory, "cfg.json") : null;

    public static V1Config Load(string? installationPath) => Load(installationPath, out _);

    /// <summary>The parsed configuration and its confirmation fingerprint come from one bounded file snapshot.</summary>
    internal static V1Config Load(string? installationPath, out string fingerprint)
    {
        var path = ConfigPathOf(installationPath);
        if (path is null)
            throw new PestoException("config.missing", "Aucun dossier d’installation V1 n’a été fourni ; aucune valeur de domaine, de préfixe ou d’OU n’est supposée.");
        if (!Directory.Exists(installationPath))
            throw new PestoException("config.missing", "Le dossier d’installation V1 fourni n’existe pas ou n’est pas accessible.");
        if (!File.Exists(path))
            throw new PestoException("config.missing", "Aucun cfg.json n’a été trouvé dans le dossier d’installation V1 fourni.");

        var info = new FileInfo(path);
        if ((info.Attributes & FileAttributes.ReparsePoint) != 0)
            throw new PestoException("config.invalid", "Le cfg.json fourni est un lien ; seule une configuration ordinaire est lue.");
        if (info.Length > MaximumFileBytes)
            throw new PestoException("config.invalid", "Configuration trop volumineuse (plus de 1 Mio).");

        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (file.Length > MaximumFileBytes)
            throw new PestoException("config.invalid", "Configuration trop volumineuse (plus de 1 Mio).");
        var bytes = new byte[checked((int)file.Length)];
        file.ReadExactly(bytes);
        fingerprint = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)).ToLowerInvariant();
        using var memory = new MemoryStream(bytes);
        using var reader = new StreamReader(memory, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        return ValidateText(reader.ReadToEnd());
    }

    /// <summary>Même validation que Load sur un texte déjà en mémoire : utilisée par settings.save avant la moindre écriture.</summary>
    internal static V1Config ValidateText(string json)
    {
        JsonDocument document;
        try
        {
            // Options par défaut : commentaires et virgules de fin sont refusés.
            document = JsonDocument.Parse(json);
        }
        catch (JsonException error)
        {
            throw new PestoException("config.invalid", "cfg.json illisible : " + error.Message);
        }
        using (document)
        {
            RejectDuplicateProperties(document.RootElement);
            return Validate(document.RootElement);
        }
    }

    private static void RejectDuplicateProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw Invalid(["Champ JSON dupliqué ou ambigu par sa casse : " + property.Name + "."]);
                RejectDuplicateProperties(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) RejectDuplicateProperties(item);
    }

    private static void RejectWrongCase(JsonElement value, IReadOnlyList<string> known, List<string> errors)
    {
        foreach (var property in value.EnumerateObject())
        {
            var canonical = known.FirstOrDefault(key => key.Equals(property.Name, StringComparison.OrdinalIgnoreCase));
            if (canonical is not null && canonical != property.Name)
                errors.Add("Casse de champ invalide : « " + property.Name + " » doit s’écrire « " + canonical + " » ; aucune politique ignorée.");
        }
    }

    // ---- validation (port de Test-CfgValid et ConvertTo-PestoPolicy) ----------------------------------------

    private static V1Config Validate(JsonElement cfg)
    {
        var errors = new List<string>();
        if (cfg.ValueKind != JsonValueKind.Object)
            throw new PestoException("config.invalid", "Configuration vide.");
        RejectWrongCase(cfg, ["Configured", "DEBUG", "CONF", "TAGS", "OUBase", "OUSite", "NameCatalogue", "POLICY", "NamingConvention", "V2DirectorySites", "ReferenceData"], errors);
        if (cfg.TryGetProperty("Configured", out var configured) && configured.ValueKind != JsonValueKind.True)
            errors.Add("Première utilisation : importez une configuration d’entreprise valide dans l’installation V1. Aucun accès AD tant que cette étape n’est pas terminée.");
        // Port de Test-CfgValid : une convention invalide est refusée, mais la validation continue avec la convention
        // par défaut (les erreurs remontent toutes ensemble, jamais un repli silencieux sur une convention douteuse).
        var convention = ReadConvention(cfg, errors) ?? DefaultConvention;
        var facetSite = "^[A-Za-z]{" + convention.SiteWidth + "}$";
        var facetService = "^[A-Za-z0-9]{" + convention.ServiceWidth + "}$";

        ValidatePolicy(cfg, errors, out var readAttempts, out var maxReaders, out var maxBatch, out var randomNames, out var unattended);
        var operationPolicy = V1OperationPolicy.Read(cfg, errors);

        List<JsonElement> confs = cfg.TryGetProperty("CONF", out var confArray) && confArray.ValueKind == JsonValueKind.Array
            ? confArray.EnumerateArray().ToList() : [];
        if (confs.Count != 1 || confs[0].ValueKind != JsonValueKind.Object)
        {
            errors.Add("« CONF » doit contenir exactement un objet.");
            throw Invalid(errors);
        }
        var conf = confs[0];
        RejectWrongCase(conf, ["Domaine", "Prefixe", "PreprodSite", "DirectProd", "DarkMode", "Buffer", "OUScanNoms", "EntraPolicy", "DsregLeaveOnMove", "ClearProtectionOnMove", "MoveRollbackOnRenameFail", "AllowHybridRepair"], errors);

        var domain = Text(conf, "Domaine").Trim().ToLowerInvariant();
        var prefix = Text(conf, "Prefixe").Trim().ToUpperInvariant();
        var preprodSite = Text(conf, "PreprodSite").Trim().ToUpperInvariant();
        if (!IsDnsName(domain)) errors.Add($"Domaine DNS invalide : « {domain} ».");
        // Facettes commandées par la convention lue (port de Get-PestoFacetPattern dans Test-CfgValid) :
        // préfixe numérique à la largeur Prefix, préprod à la largeur Service, tags à la largeur Site.
        if (!Regex.IsMatch(prefix, "^[0-9]{" + convention.PrefixWidth + "}$")) errors.Add("Préfixe invalide : " + convention.PrefixWidth + " chiffres requis (largeur définie par la convention).");
        if (!Regex.IsMatch(preprodSite, facetService)) errors.Add("PreprodSite invalide : " + convention.ServiceWidth + " caractères alphanumériques requis (largeur de service définie par la convention).");
        var darkMode = Text(conf, "DarkMode").Trim();
        if (darkMode.Length > 0 && darkMode is not ("0" or "1" or "2")) errors.Add("DarkMode : 0, 1 ou 2 requis.");
        var buffer = Text(conf, "Buffer").Trim();
        if (buffer.Length > 0 && (!int.TryParse(buffer, out var bufferValue) || bufferValue < 0 || bufferValue > 999))
            errors.Add("Buffer : entier compris entre 0 et 999 requis.");
        var scanOu = Text(conf, "OUScanNoms").Trim();
        if (scanOu.Length > 0 && !IsOuPath(scanOu)) errors.Add("OUScanNoms doit être un DN d’OU valide ou rester vide.");
        var entra = Text(conf, "EntraPolicy").Trim();
        if (entra.Length > 0 && entra is not ("HybridOnly" or "Disabled")) errors.Add("EntraPolicy doit valoir HybridOnly ou Disabled.");
        foreach (var property in new[] { "DirectProd", "DsregLeaveOnMove", "ClearProtectionOnMove", "MoveRollbackOnRenameFail", "AllowHybridRepair" })
            if (conf.TryGetProperty(property, out var value) && !IsTrueFalse(value, out _))
                errors.Add($"{property} : valeur booléenne invalide.");
        if (!TryConfFlag(conf, "DirectProd", out var directProd)) directProd = false;

        var simulation = false;
        var gui = false;
        if (cfg.TryGetProperty("DEBUG", out var debug) && debug.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in new[] { "Simulation", "HorsDomaine", "MauvaiseOU", "BPVerifNomAD", "ForceADM", "GUI" })
                if (debug.TryGetProperty(property, out var value) && !IsTrueFalse(value, out _))
                    errors.Add($"DEBUG.{property} : valeur booléenne invalide.");
            _ = TryDebugFlag(debug, "Simulation", out simulation);
            _ = TryDebugFlag(debug, "GUI", out gui);
            if (!simulation && !gui)
            {
                if (TryDebugFlag(debug, "HorsDomaine", out var odm) && odm)
                    errors.Add("DEBUG.HorsDomaine=true est interdit en mode réel. La v2 détecte l’appartenance au domaine ; utilisez la simulation pour ce test.");
                if (TryDebugFlag(debug, "MauvaiseOU", out var wou) && wou)
                    errors.Add("DEBUG.MauvaiseOU=true est interdit en mode réel. Utilisez la simulation pour ce test.");
            }
        }

        var baseNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        string? rootOu = null;
        string? preprodOu = null;
        foreach (var entry in Objects(cfg, "OUBase"))
        {
            var name = Text(entry, "Nom").Trim();
            var ou = Text(entry, "OU").Trim();
            if (name.Length == 0 || ou.Length == 0) { errors.Add("OUBase : Nom et OU sont obligatoires."); continue; }
            if (!baseNames.Add(name)) errors.Add($"OUBase : nom dupliqué « {name} ».");
            if (!IsOuPath(ou)) errors.Add($"OUBase « {name} » : DN invalide.");
            if (name.Equals("ROOT", StringComparison.OrdinalIgnoreCase)) rootOu = ou;
            if (name.Equals("PREPROD", StringComparison.OrdinalIgnoreCase)) preprodOu = ou;
        }
        if (rootOu is null) errors.Add("L’OU ROOT est manquante (OUBase).");
        if (!directProd && preprodOu is null) errors.Add("L’OU PREPROD est obligatoire quand DirectProd=false.");

        var organismOus = new List<string>();
        var siteNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in Objects(cfg, "OUSite"))
        {
            var name = Text(entry, "Nom").Trim();
            var ou = Text(entry, "OU").Trim();
            if (name.Length == 0 || ou.Length == 0) { errors.Add("OUSite : Nom et OU sont obligatoires."); continue; }
            if (!siteNames.Add(name)) errors.Add($"OUSite : nom dupliqué « {name} ».");
            if (!IsOuPath(ou)) errors.Add($"OUSite « {name} » : DN invalide.");
            else organismOus.Add(ou);
        }
        if (siteNames.Count == 0) errors.Add("Aucun organisme (OUSite) défini.");

        var declaredSites = new List<DeclaredSite>();
        var tagPatterns = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var preprodTagCovered = false;
        var preprodAliases = new[] { "PREPROD", preprodSite, preprodSite + "_PREPROD", preprodSite + "_PROD_A_NOMMER" }
            .Where(alias => alias.Length > 0).ToArray();
        foreach (var entry in Objects(cfg, "TAGS"))
        {
            var pattern = Text(entry, "Site").Trim();
            var tag = Text(entry, "Tag").Trim().ToUpperInvariant();
            if (pattern.Length == 0) { errors.Add("TAGS : le motif Site est obligatoire."); continue; }
            if (!Regex.IsMatch(tag, facetSite)) errors.Add($"Tag « {pattern} » incohérent : {convention.SiteWidth} lettres requises (largeur de site définie par la convention).");
            if (!tagPatterns.Add(pattern)) errors.Add($"TAGS : motif dupliqué « {pattern} ».");
            if (Regex.IsMatch(tag, facetSite) && preprodAliases.Any(alias => MatchesWildcard(pattern, alias))) preprodTagCovered = true;
            declaredSites.Add(new DeclaredSite(pattern, tag));
        }
        if (!directProd && !preprodTagCovered) errors.Add($"Aucun TAGS valide ne couvre PREPROD / « {preprodSite} ».");

        // Domaine unique : une chaîne syntaxiquement correcte peut désigner un AUTRE domaine.
        var expectedDns = domain.TrimEnd('.');
        foreach (var (label, ou) in Objects(cfg, "OUBase").Select(o => ("OUBase", Text(o, "OU").Trim()))
                     .Concat(Objects(cfg, "OUSite").Select(o => ("OUSite", Text(o, "OU").Trim()))))
        {
            if (!IsOuPath(ou)) continue;
            var actual = DomainFromDn(ou);
            if (actual is not null && !actual.Equals(expectedDns, StringComparison.OrdinalIgnoreCase))
                errors.Add($"{label} « {ou} » : domaine DN « {actual} » différent de Domaine=« {domain} ».");
        }
        if (scanOu.Length > 0 && IsOuPath(scanOu))
        {
            var actual = DomainFromDn(scanOu);
            if (actual is not null && !actual.Equals(expectedDns, StringComparison.OrdinalIgnoreCase))
                errors.Add($"OUScanNoms ne correspond pas au domaine « {domain} ».");
        }

        var catalogue = new List<CataloguePair>();
        foreach (var entry in Objects(cfg, "NameCatalogue"))
        {
            var keys = entry.EnumerateObject().Select(p => p.Name).ToList();
            if (keys.Any(k => k is not ("Site" or "Service")) || !entry.TryGetProperty("Site", out _) || !entry.TryGetProperty("Service", out _))
            { errors.Add("NameCatalogue : seules les clés Site et Service sont admises, toutes deux requises."); continue; }
            var site = Text(entry, "Site").Trim().ToUpperInvariant();
            var service = Text(entry, "Service").Trim().ToUpperInvariant();
            if (!Regex.IsMatch(site, facetSite) || !Regex.IsMatch(service, facetService))
            { errors.Add("NameCatalogue : combinaison site/service invalide au regard des largeurs de la convention."); continue; }
            catalogue.Add(new CataloguePair(site, service));
        }

        var explicitSites = new List<Site>();
        var siteIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var siteCodes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var siteOus = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (cfg.TryGetProperty("V2DirectorySites", out var configuredSites) && configuredSites.ValueKind != JsonValueKind.Array)
            errors.Add("V2DirectorySites : tableau attendu.");
        foreach (var entry in Objects(cfg, "V2DirectorySites"))
        {
            var id = Text(entry, "Id").Trim();
            var name = Text(entry, "Name").Trim();
            var code = Text(entry, "Code").Trim().ToUpperInvariant();
            var ou = Text(entry, "OU").Trim();
            if (!Regex.IsMatch(id, "^[A-Za-z0-9_-]{1,80}$") || name.Length is < 1 or > 200 || name.Any(char.IsControl)
                || !Regex.IsMatch(code, facetSite) || !IsOuPath(ou) || !string.Equals(DomainFromDn(ou), domain, StringComparison.OrdinalIgnoreCase)
                || rootOu is null || !(ou.Equals(rootOu, StringComparison.OrdinalIgnoreCase) || ou.EndsWith("," + rootOu, StringComparison.OrdinalIgnoreCase)))
                errors.Add("V2DirectorySites : identifiant, libellé, code ou OU hors de la racine/domaine.");
            if (!siteIds.Add(id) || !siteCodes.Add(code) || !siteOus.Add(ou)) errors.Add("V2DirectorySites : doublon d’identifiant, code ou OU.");
            explicitSites.Add(new(id, name, code, ou));
        }
        var labels = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (cfg.TryGetProperty("ReferenceData", out var references))
        {
            if (references.ValueKind != JsonValueKind.Object || !references.TryGetProperty("Schema", out var referenceSchema)
                || referenceSchema.ValueKind != JsonValueKind.Number || !referenceSchema.TryGetInt32(out var schemaNumber) || schemaNumber != 1)
                errors.Add("ReferenceData : schéma invalide.");
            else
            {
                if (!Regex.IsMatch(Text(references, "Version"), "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")) errors.Add("ReferenceData : version invalide.");
                foreach (var entry in Objects(references, "ServiceLabels"))
                {
                    var site = Text(entry, "Site").Trim().ToUpperInvariant();
                    var service = Text(entry, "Service").Trim().ToUpperInvariant();
                    var name = Text(entry, "Name").Trim();
                    if (!Regex.IsMatch(site, facetSite) || !Regex.IsMatch(service, facetService) || name.Length is < 1 or > 200 || name.Any(char.IsControl)
                        || !catalogue.Any(pair => pair.Site.Equals(site, StringComparison.OrdinalIgnoreCase) && pair.Service.Equals(service, StringComparison.OrdinalIgnoreCase)))
                        errors.Add("ReferenceData : libellé de service invalide ou sans entrée NameCatalogue.");
                    if (!labels.TryAdd(site + "|" + service, name)) errors.Add("ReferenceData : libellé de service dupliqué.");
                }
            }
        }

        if (errors.Count > 0) throw Invalid(errors);
        if (rootOu is null) throw Invalid(["L’OU ROOT est manquante (OUBase)."]);

        // La convention lue doit rester applicable aux valeurs lues (échec = config refusée, pas de repli silencieux).
        try { _ = new NamingConvention(convention.ToPattern(), prefix); }
        catch (PestoException error) { throw Invalid(["Convention inapplicable aux valeurs lues : " + error.Message]); }

        return new V1Config
        {
            Domain = domain,
            Prefix = prefix,
            PreprodSite = preprodSite,
            Production = directProd,
            RandomNames = randomNames,
            RootOu = rootOu,
            PreprodOu = preprodOu,
            DeclaredSites = declaredSites,
            OrganismOus = organismOus,
            NameCatalogue = catalogue,
            ExplicitSites = explicitSites,
            ServiceLabels = labels,
            Convention = convention,
            ReadAttempts = readAttempts,
            MaxReaders = maxReaders,
            MaxBatch = maxBatch,
            UnattendedJoinEnabled = unattended,
            UnattendedOperationsEnabled = cfg.TryGetProperty("POLICY", out var automationPolicy)
                && automationPolicy.ValueKind == JsonValueKind.Object && automationPolicy.TryGetProperty("UnattendedOperationsEnabled", out var unattendedOperations)
                && unattendedOperations.ValueKind == JsonValueKind.True,
            EntraPolicy = entra.Length == 0 ? EntraPreparationRules.HybridOnly : entra,
            OperationPolicy = operationPolicy,
        };
    }

    // ---- convention de nommage (port de Assert-PestoNamingConvention, Pesto-Contracts.ps1) -------------------------

    private static readonly string[] ConventionTokens = ["Type", "Prefix", "Site", "Service", "Number"];
    private static readonly NamingConventionModel DefaultConvention =
        new("defaut", ["Type", "Prefix", "Site", "Service", "Number"], 6, 2, 3, 3, "PSV");

    /// <summary>
    /// Convention administrable mais fermée (port v1) : objet {Schema,Id,Tokens,Widths,Types} sans champ inconnu,
    /// les cinq facettes exactement une fois chacune dans l'ordre configuré, largeurs Prefix 1-12 / Site 1-4 /
    /// Service 1-6 / Number 1-6, types sous-ensemble sans doublon de P/S/V, total plafonné à 15. L'absence (ou null)
    /// conserve le format historique ; une convention invalide est ajoutée aux erreurs et le défaut sert à la
    /// suite de la validation, comme dans Test-CfgValid.
    /// </summary>
    private static NamingConventionModel? ReadConvention(JsonElement cfg, List<string> errors)
    {
        if (!cfg.TryGetProperty("NamingConvention", out var node) || node.ValueKind == JsonValueKind.Null) return null;
        if (node.ValueKind != JsonValueKind.Object) { errors.Add("NamingConvention : objet structuré attendu."); return null; }
        foreach (var property in node.EnumerateObject())
            if (!new[] { "Schema", "Id", "Tokens", "Widths", "Types" }.Contains(property.Name, StringComparer.Ordinal))
            { errors.Add($"NamingConvention : champ non autorisé « {property.Name} »."); return null; }
        foreach (var required in new[] { "Schema", "Id", "Tokens", "Widths", "Types" })
            if (!node.TryGetProperty(required, out _)) { errors.Add($"NamingConvention : champ obligatoire absent : {required}."); return null; }
        if (!node.TryGetProperty("Schema", out var schema) || !schema.TryGetInt32(out var schemaValue) || schemaValue != 1)
        { errors.Add("NamingConvention : schéma de convention invalide."); return null; }
        var id = Text(node, "Id");
        if (!Regex.IsMatch(id, "^[a-z0-9][a-z0-9._-]{0,31}$"))
        { errors.Add("NamingConvention : identifiant invalide : minuscules, chiffres, point, tiret et tiret bas, 32 caractères maximum."); return null; }
        var tokensNode = node.GetProperty("Tokens");
        if (tokensNode.ValueKind != JsonValueKind.Array) { errors.Add("NamingConvention : Tokens doit être un tableau."); return null; }
        var tokens = tokensNode.EnumerateArray().Select(t => t.ValueKind == JsonValueKind.String ? t.GetString()! : " ").ToList();
        // Toute permutation est admise (le numéro peut être au milieu) ; chaque facette doit figurer exactement une fois.
        if (ConventionTokens.Any(expected => tokens.Count(token => string.Equals(token, expected, StringComparison.Ordinal)) != 1))
        { errors.Add("NamingConvention : la convention doit aligner exactement les jetons Type, Prefix, Site, Service et Number, chacun une seule fois."); return null; }
        var types = Text(node, "Types");
        if (!Regex.IsMatch(types, "^[PSV]{1,3}$") || types.Distinct().Count() != types.Length)
        { errors.Add("NamingConvention : types invalides : sous-ensemble sans doublon de P, S et V."); return null; }
        var widths = node.GetProperty("Widths");
        if (widths.ValueKind != JsonValueKind.Object) { errors.Add("NamingConvention : Widths doit être un objet."); return null; }
        var keys = widths.EnumerateObject().Select(p => p.Name).ToList();
        foreach (var key in ConventionTokens.Skip(1))
            if (!keys.Contains(key, StringComparer.Ordinal)) { errors.Add($"NamingConvention : largeur absente dans la convention : {key}."); return null; }
        foreach (var key in keys)
            if (!ConventionTokens.Skip(1).Contains(key, StringComparer.Ordinal)) { errors.Add($"NamingConvention : largeur inconnue dans la convention : {key}."); return null; }
        var floor = new Dictionary<string, int>(StringComparer.Ordinal) { ["Prefix"] = 1, ["Site"] = 1, ["Service"] = 1, ["Number"] = 1 };
        var ceiling = new Dictionary<string, int>(StringComparer.Ordinal) { ["Prefix"] = 12, ["Site"] = 4, ["Service"] = 6, ["Number"] = 6 };
        var resolved = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var key in ConventionTokens.Skip(1))
        {
            if (!widths.GetProperty(key).TryGetInt32(out var width) || width < floor[key] || width > ceiling[key])
            { errors.Add($"NamingConvention : largeur hors bornes pour {key} : {floor[key]} à {ceiling[key]} caractères."); return null; }
            resolved[key] = width;
        }
        var total = 1 + resolved.Values.Sum();
        if (total > 15)
        { errors.Add($"NamingConvention : convention de {total} caractères : un nom d'ordinateur Windows est plafonné à 15. Réduisez une largeur."); return null; }
        return new NamingConventionModel(id, tokens, resolved["Prefix"], resolved["Site"], resolved["Service"], resolved["Number"], types);
    }

    private static void ValidatePolicy(JsonElement cfg, List<string> errors, out int readAttempts, out int maxReaders, out int maxBatch, out bool randomNames, out bool unattended)
    {
        readAttempts = 2; maxReaders = 4; maxBatch = 200; randomNames = true; unattended = false;
        if (!cfg.TryGetProperty("POLICY", out var policy) || policy.ValueKind == JsonValueKind.Null) return;
        if (policy.ValueKind != JsonValueKind.Object) { errors.Add("POLICY : objet ou null attendu."); return; }
        var allowed = new HashSet<string>(StringComparer.Ordinal)
        {
            "Schema", "Scenario", "ExcludedNames", "ExcludedOUs", "ExcludedGroupGuids", "CoordinationRoot", "CoordinationRequired",
            "AllowPasswordTaskFallback", "AllowPrecreatedJoin", "AllowOfflineJoin", "BlockJoinOnClockSkew", "MaxReaders", "ReadAttempts",
            "MaxBatch", "NameReservationMinutes", "ReserveNamesInAD", "RandomNameEnabled", "RandomNameChoice", "LogRetentionDays",
            "UnattendedJoinEnabled", "UnattendedOperationsEnabled", "IncidentMode", "AuditEventLogEnabled",
        };
        foreach (var property in policy.EnumerateObject())
            if (!allowed.Contains(property.Name)) errors.Add($"POLICY : clé inconnue « {property.Name} » (schéma fermé).");
        if (!policy.TryGetProperty("Schema", out var schema) || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var schemaNumber) || schemaNumber != 1)
            errors.Add("Schéma de politique non reconnu (POLICY.Schema doit valoir 1).");
        foreach (var flag in new[] { "BlockJoinOnClockSkew", "CoordinationRequired", "AllowPasswordTaskFallback", "AllowPrecreatedJoin", "AllowOfflineJoin",
                     "ReserveNamesInAD", "RandomNameEnabled", "UnattendedJoinEnabled", "UnattendedOperationsEnabled", "IncidentMode", "AuditEventLogEnabled" })
        {
            if (!policy.TryGetProperty(flag, out var value)) continue;
            if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) { errors.Add($"La politique {flag} exige un booléen JSON."); continue; }
            switch (flag)
            {
                case "RandomNameEnabled": randomNames = value.GetBoolean(); break;
                case "UnattendedJoinEnabled": unattended = value.GetBoolean(); break;
            }
        }
        if (policy.TryGetProperty("RandomNameChoice", out var choice))
        {
            if (choice.ValueKind != JsonValueKind.Number || !choice.TryGetInt32(out var choiceValue) || choiceValue < 0 || choiceValue > 50)
                errors.Add("Limite invalide : RandomNameChoice");
            else
            {
                var enabled = choiceValue >= 2;
                if (policy.TryGetProperty("RandomNameEnabled", out var explicitFlag) && explicitFlag.ValueKind is JsonValueKind.True or JsonValueKind.False
                    && explicitFlag.GetBoolean() != enabled)
                    errors.Add("RandomNameEnabled et RandomNameChoice se contredisent. Conservez uniquement RandomNameEnabled.");
                randomNames = enabled;
            }
        }
        foreach (var (name, minimum, maximum) in new (string, int, int)[]
        {
            ("MaxReaders", 1, 8), ("ReadAttempts", 1, 3), ("MaxBatch", 1, 200),
            ("NameReservationMinutes", 5, 240), ("LogRetentionDays", 0, 3650),
        })
        {
            if (!policy.TryGetProperty(name, out var value)) continue;
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number) || number < minimum || number > maximum)
                errors.Add("Limite invalide : " + name);
            else
            {
                switch (name)
                {
                    case "MaxReaders": maxReaders = number; break;
                    case "ReadAttempts": readAttempts = number; break;
                    case "MaxBatch": maxBatch = number; break;
                }
            }
        }
        if (policy.TryGetProperty("CoordinationRequired", out var required) && required.ValueKind == JsonValueKind.True)
        {
            var root = policy.TryGetProperty("CoordinationRoot", out var rootValue) && rootValue.ValueKind == JsonValueKind.String
                ? rootValue.GetString()!.Trim() : "";
            if (root.Length == 0) errors.Add("Un emplacement de coordination approuvé est obligatoire pour cette politique.");
        }
    }

    // ---- helpers de lecture (port des gardes v1) ---------------------------------------------------------------

    private static PestoException Invalid(List<string> errors) =>
        new("config.invalid", "cfg.json refusé : " + string.Join(" ", errors));

    private static string Text(JsonElement entry, string name) =>
        entry.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString()!
        : entry.TryGetProperty(name, out var number) && number.ValueKind == JsonValueKind.Number ? number.GetRawText()
        : entry.TryGetProperty(name, out var flag) && flag.ValueKind is JsonValueKind.True or JsonValueKind.False ? flag.GetBoolean().ToString().ToLowerInvariant()
        : "";

    private static IEnumerable<JsonElement> Objects(JsonElement cfg, string name) =>
        cfg.TryGetProperty(name, out var array) && array.ValueKind == JsonValueKind.Array
            ? array.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.Object) : [];

    private static bool IsTrueFalse(JsonElement value, out bool result)
    {
        result = false;
        if (value.ValueKind is JsonValueKind.True) { result = true; return true; }
        if (value.ValueKind is JsonValueKind.False) return true;
        if (value.ValueKind == JsonValueKind.String)
        {
            var text = value.GetString()!.Trim();
            if (text.Equals("true", StringComparison.OrdinalIgnoreCase)) { result = true; return true; }
            if (text.Equals("false", StringComparison.OrdinalIgnoreCase)) return true;
        }
        return false;
    }

    private static bool TryConfFlag(JsonElement conf, string name, out bool value)
    {
        value = false;
        return conf.TryGetProperty(name, out var element) && IsTrueFalse(element, out value);
    }

    private static bool TryDebugFlag(JsonElement debug, string name, out bool value)
    {
        value = false;
        return debug.TryGetProperty(name, out var element) && IsTrueFalse(element, out value);
    }

    private static bool IsDnsName(string value) =>
        Regex.IsMatch(value, @"^(?=.{3,253}$)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$");

    private static string[]? SplitDn(string? dn)
    {
        if (string.IsNullOrWhiteSpace(dn) || dn.Any(c => char.IsControl(c) || c == '\u007f')) return null;
        var parts = new List<string>();
        var current = new StringBuilder();
        for (var i = 0; i < dn.Length; i++)
        {
            var c = dn[i];
            if (c == '\\' && i + 1 < dn.Length) { current.Append(c).Append(dn[++i]); continue; }
            if (c == ',') { parts.Add(current.ToString()); current.Clear(); continue; }
            current.Append(c);
        }
        parts.Add(current.ToString());
        return parts.All(p => Regex.IsMatch(p, @"^(?i:OU|CN|DC)=(?:\\.|[^\\])+$")) ? parts.ToArray() : null;
    }

    internal static bool IsOuPath(string? dn)
    {
        var parts = SplitDn(dn);
        if (parts is null || parts.Length < 2 || !Regex.IsMatch(parts[0], @"^(?i:OU)=")) return false;
        return parts.All(p => Regex.IsMatch(p, @"^(?i:OU|DC)="));
    }

    internal static string? DomainFromDn(string dn)
    {
        var parts = SplitDn(dn);
        if (parts is null) return null;
        var labels = new List<string>();
        var inDomain = false;
        foreach (var part in parts)
        {
            var match = Regex.Match(part, @"^(?i:DC)=(.+)$");
            if (match.Success) { inDomain = true; labels.Add(match.Groups[1].Value); }
            else if (inDomain) return null;
        }
        if (labels.Count == 0) return null;
        var dns = string.Join('.', labels).ToLowerInvariant();
        return IsDnsName(dns) ? dns : null;
    }

    /// <summary>PowerShell string wildcards: *, ?, character sets/ranges and backtick escapes, without regex syntax.</summary>
    internal static bool MatchesWildcard(string pattern, string value)
    {
        static string Literal(char c) => "\\u" + ((int)c).ToString("X4", System.Globalization.CultureInfo.InvariantCulture);
        static PestoException InvalidPattern() => new("config.invalid", "Motif de site invalide : vérifiez les crochets et les plages de caractères du TAGS.");
        var regex = new StringBuilder("\\A");
        for (var i = 0; i < pattern.Length; i++)
        {
            var c = pattern[i];
            if (c == '`') regex.Append(Literal(i + 1 < pattern.Length ? pattern[++i] : c));
            else if (c == '*') regex.Append(".*");
            else if (c == '?') regex.Append('.');
            else if (c != '[') regex.Append(Literal(c));
            else
            {
                var set = new List<(char Value, bool Escaped)>();
                var closed = false;
                while (++i < pattern.Length)
                {
                    var member = pattern[i];
                    if (member == ']' && set.Count > 0) { closed = true; break; }
                    var escaped = member == '`' && i + 1 < pattern.Length;
                    if (escaped) member = pattern[++i];
                    set.Add((member, escaped));
                }
                if (!closed) throw InvalidPattern();
                regex.Append('[');
                for (var j = 0; j < set.Count; j++)
                {
                    regex.Append(Literal(set[j].Value));
                    if (j + 2 < set.Count && set[j + 1] == ('-', false))
                    {
                        if (set[j].Value > set[j + 2].Value) throw InvalidPattern();
                        regex.Append('-').Append(Literal(set[j + 2].Value));
                        j += 2;
                    }
                }
                regex.Append(']');
            }
        }
        regex.Append("\\z");
        return Regex.IsMatch(value, regex.ToString(), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant
            | RegexOptions.NonBacktracking | RegexOptions.Singleline);
    }
}

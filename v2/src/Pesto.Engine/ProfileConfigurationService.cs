using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

public enum ConfigurationAccessMode { Live, Demo, HealthCheck, BinaryRecovery }

/// <summary>
/// Profile-owned configuration. The host resolves the originating Windows SID before UAC and supplies its local
/// directory here. No environment lookup can silently select the elevated administrator's profile.
/// </summary>
public sealed partial class ProfileConfigurationService
{
    private readonly string profileRoot;
    private readonly string profileIdentity;
    private readonly ConfigurationAccessMode mode;
    private readonly TimeProvider clock;
    private readonly object gate = new();
    private readonly Dictionary<string, ImportPlan> imports = new(StringComparer.Ordinal);
    private JsonObject? pendingDistribution;
    private sealed record ImportPlan(string Id, JsonObject Configuration, string? ExpectedStamp, DateTimeOffset ExpiresAt,
        string Source, string Version, string Fingerprint, string? DecisionKey);
    private sealed record ConfigurationState(bool Exists, JsonObject? Configuration, string? Stamp, string? Diagnostic)
    {
        public string State => !Exists ? "missing" : Configuration is null ? "invalid" : "valid";
    }
    private const string InvalidConfigurationMessage = "La configuration existante est invalide ou illisible. Aucun paramètre par défaut n’a été appliqué. Importez explicitement une configuration valide pour préparer son remplacement avec sauvegarde du fichier original.";

    public ProfileConfigurationService(string profileRoot, string profileIdentity, ConfigurationAccessMode mode, TimeProvider? clock = null)
    {
        // Isolation is checked before paths are probed, including direct API calls outside the web bridge.
        this.mode = mode;
        this.profileRoot = mode == ConfigurationAccessMode.Live ? ConfigurationStore.LocalPath(profileRoot) : profileRoot;
        if (string.IsNullOrWhiteSpace(profileIdentity) || profileIdentity.Length > 200 || profileIdentity.Any(char.IsControl))
            throw new PestoException("config.profile", "Identité du profil d’origine requise.");
        this.profileIdentity = profileIdentity;
        this.clock = clock ?? TimeProvider.System;
    }

    public string ConfigurationRoot => profileRoot;
    public string ConfigurationPath => Path.Combine(profileRoot, "cfg.json");
    private string DecisionsPath => Path.Combine(profileRoot, "configuration-decisions.json");

    public JsonObject Initialize(string? defaultBundlePath = null, string? legacyRoot = null)
    {
        if (mode != ConfigurationAccessMode.Live) return new JsonObject { ["status"] = "isolated", ["mode"] = mode.ToString(), ["changed"] = false };
        lock (gate)
        {
            using var profileLock = ConfigurationStore.Lock(profileRoot);
            var existing = InspectConfiguration();
            if (existing.State == "invalid")
            {
                ClearPendingDistribution();
                // Do not even inspect a distributed/legacy path when an existing profile needs an explicit repair.
                return StatusNode(existing);
            }
            if (!File.Exists(ConfigurationPath) && legacyRoot is not null)
            {
                // Only an explicitly selected legacy installation is read. It remains untouched.
                var original = V1Config.ConfigPathOf(legacyRoot) ?? throw new PestoException("config.missing", "Configuration choisie absente.");
                var clean = ConfigurationDocument.Sanitize(ConfigurationStore.Read(original));
                _ = ConfigurationStore.Write(ConfigurationPath, ConfigurationDocument.Canonical(clean), null);
            }
            if (defaultBundlePath is null || !File.Exists(defaultBundlePath)) return Status();
            var bundle = ConfigurationDocument.ValidateBundle(ConfigurationStore.Read(defaultBundlePath));
            var version = ConfigurationDocument.String(bundle, "version");
            var fingerprint = ConfigurationDocument.String(bundle, "fingerprint");
            var decisionKey = DecisionKey(version, fingerprint);
            var decisions = ReadDecisions();
            if (decisions[decisionKey] is not null) return Status();
            var candidate = (JsonObject)bundle["configuration"]!.DeepClone();
            if (!File.Exists(ConfigurationPath))
            {
                _ = ConfigurationStore.Write(ConfigurationPath, ConfigurationDocument.Canonical(candidate), null);
                SaveDecision(decisions, decisionKey, "imported", version, fingerprint);
                return Result("imported", true, null);
            }
            var current = ReadConfiguration();
            if (ConfigurationDocument.Fingerprint(current) == fingerprint)
            {
                SaveDecision(decisions, decisionKey, "identical", version, fingerprint);
                return Result("identical", false, null);
            }
            pendingDistribution = CreateImport(candidate, "distribution", version, fingerprint, decisionKey);
            pendingDistribution["requiresDecision"] = true;
            return Status();
        }
    }

    public JsonObject Status()
    {
        RequireLive();
        lock (gate)
        {
            var observed = InspectConfiguration();
            if (observed.State == "invalid")
            {
                ClearPendingDistribution();
                return StatusNode(observed);
            }
            RefreshPendingDistribution();
            return StatusNode(observed);
        }
    }

    public JsonObject Export(string version)
    {
        RequireLive();
        lock (gate) return ConfigurationDocument.Export(ConfigurationStore.Read(ConfigurationPath), version);
    }

    public JsonObject PreviewImport(string text)
    {
        RequireLive();
        lock (gate)
        {
            var parsed = ConfigurationDocument.ParseObject(text);
            JsonObject candidate;
            string version;
            if (parsed["kind"] is not null)
            {
                var bundle = ConfigurationDocument.ValidateBundle(text);
                candidate = (JsonObject)bundle["configuration"]!.DeepClone();
                version = ConfigurationDocument.String(bundle, "version");
            }
            else
            {
                candidate = ConfigurationDocument.Sanitize(text);
                version = "import-" + clock.GetUtcNow().ToString("yyyyMMdd-HHmmss");
            }
            return CreateImport(candidate, "import", version, ConfigurationDocument.Fingerprint(candidate), null, allowInvalidCurrent: true);
        }
    }

    public JsonObject ApplyImport(string planId, bool confirmed)
    {
        RequireLive();
        if (!confirmed) throw new PestoException("config.confirmation", "Confirmez le remplacement de la configuration affichée.");
        lock (gate)
        {
            using var profileLock = ConfigurationStore.Lock(profileRoot);
            var plan = GetImport(planId);
            var backup = ConfigurationStore.Write(ConfigurationPath, ConfigurationDocument.Canonical(plan.Configuration), plan.ExpectedStamp);
            imports.Remove(planId);
            if (plan.DecisionKey is not null)
            {
                var decisions = ReadDecisions();
                SaveDecision(decisions, plan.DecisionKey, "replaced", plan.Version, plan.Fingerprint);
                pendingDistribution = null;
            }
            return Result("applied", true, backup);
        }
    }

    public JsonObject DecideDistribution(string planId, bool replace, bool confirmed)
    {
        RequireLive();
        if (!confirmed) throw new PestoException("config.confirmation", "Confirmez le choix Remplacer ou Conserver.");
        if (replace) return ApplyImport(planId, true);
        lock (gate)
        {
            using var profileLock = ConfigurationStore.Lock(profileRoot);
            var plan = GetImport(planId);
            if (plan.DecisionKey is null) throw new PestoException("config.plan", "Ce plan n’est pas une configuration distribuée.");
            if (ConfigurationStore.Stamp(ConfigurationPath) != plan.ExpectedStamp)
                throw new PestoException("config.changed", "La configuration a changé depuis la comparaison. Relisez les différences avant de choisir.");
            SaveDecision(ReadDecisions(), plan.DecisionKey, "kept", plan.Version, plan.Fingerprint);
            imports.Remove(planId);
            pendingDistribution = null;
            return Result("kept", false, null);
        }
    }

    public JsonObject ReadSettings()
    {
        RequireLive();
        lock (gate)
        {
            var observed = InspectConfiguration();
            if (observed.State == "invalid")
            {
                var invalid = StatusNode(observed);
                invalid["sites"] = new JsonArray();
                invalid["simulation"] = false;
                invalid["liveExecutionEnabled"] = false;
                return invalid;
            }
            if (!observed.Exists) return new JsonObject
            {
                ["configured"] = false, ["configurationExists"] = false, ["configurationState"] = "missing", ["diagnostic"] = null,
                ["domain"] = "", ["dc"] = "", ["prefix"] = "", ["rootOu"] = "", ["preprodOu"] = "", ["preprodSite"] = "",
                ["production"] = true, ["randomNames"] = true, ["namingPattern"] = PestoSettings.DefaultPattern,
                ["sites"] = new JsonArray(), ["simulation"] = false, ["liveExecutionEnabled"] = false, ["fingerprint"] = null,
                ["coordinationRoot"] = "", ["coordinationRequired"] = false, ["reserveNamesInAd"] = false,
                ["auditEventLogEnabled"] = false, ["blockJoinOnClockSkew"] = false, ["excludedGroupGuids"] = new JsonArray(),
                ["entraPolicy"] = EntraPreparationRules.Disabled, ["allowPrecreatedJoin"] = false, ["allowOfflineJoin"] = false,
                ["unattendedJoinEnabled"] = false, ["unattendedOperationsEnabled"] = false
            };
            var raw = observed.Configuration!;
            var read = V1Config.ValidateText(raw.ToJsonString());
            var sites = read.ExplicitSites.Count > 0
                ? new JsonArray(read.ExplicitSites.Select(s => (JsonNode)new JsonObject { ["id"] = s.Id, ["name"] = s.Name, ["code"] = s.Code, ["ou"] = s.Ou }).ToArray())
                : new JsonArray(read.DeclaredSites.Select(s => (JsonNode)new JsonObject { ["id"] = s.Tag, ["name"] = s.Pattern, ["code"] = s.Tag, ["ou"] = "" }).ToArray());
            return new JsonObject
            {
                ["configured"] = true, ["configurationExists"] = true, ["configurationState"] = "valid", ["diagnostic"] = null,
                ["domain"] = read.Domain, ["dc"] = "", ["prefix"] = read.Prefix, ["production"] = read.Production,
                ["rootOu"] = read.RootOu, ["preprodOu"] = read.PreprodOu ?? "", ["preprodSite"] = read.PreprodSite,
                ["namingPattern"] = read.NamingPattern, ["randomNames"] = read.RandomNames, ["sites"] = sites,
                ["entraPolicy"] = read.EntraPolicy, ["allowPrecreatedJoin"] = raw["POLICY"]?["AllowPrecreatedJoin"]?.GetValue<bool>() ?? false,
                ["allowOfflineJoin"] = raw["POLICY"]?["AllowOfflineJoin"]?.GetValue<bool>() ?? false,
                ["unattendedJoinEnabled"] = read.UnattendedJoinEnabled, ["unattendedOperationsEnabled"] = read.UnattendedOperationsEnabled,
                ["simulation"] = false, ["liveExecutionEnabled"] = false, ["fingerprint"] = ConfigurationDocument.Fingerprint(raw),
                ["coordinationRoot"] = read.OperationPolicy.CoordinationRoot, ["coordinationRequired"] = read.OperationPolicy.CoordinationRequired,
                ["reserveNamesInAd"] = read.OperationPolicy.ReserveNamesInAd, ["auditEventLogEnabled"] = read.OperationPolicy.AuditEventLogEnabled,
                ["blockJoinOnClockSkew"] = read.OperationPolicy.BlockJoinOnClockSkew,
                ["excludedGroupGuids"] = new JsonArray(read.OperationPolicy.ExcludedGroups.Select(g => (JsonNode?)JsonValue.Create(g)).ToArray())
            };
        }
    }

    public JsonObject PreviewSettings(JsonElement args)
    {
        RequireLive();
        Arguments.Only(args, "domain", "dc", "prefix", "rootOu", "preprodOu", "preprodSite", "production", "randomNames", "namingPattern", "sites", "fingerprint",
            "coordinationRoot", "coordinationRequired", "reserveNamesInAd", "auditEventLogEnabled", "blockJoinOnClockSkew", "excludedGroupGuids",
            "entraPolicy", "allowPrecreatedJoin", "allowOfflineJoin", "unattendedJoinEnabled", "unattendedOperationsEnabled");
        lock (gate)
        {
            var observed = InspectConfiguration();
            if (observed.State == "invalid") throw new PestoException("config.recovery_required", InvalidConfigurationMessage);
            var snapshotStamp = observed.Stamp;
            var current = observed.Configuration;
            var currentFingerprint = current is null ? "" : ConfigurationDocument.Fingerprint(current);
            if (args.TryGetProperty("fingerprint", out var expected) && expected.ValueKind == JsonValueKind.String
                && expected.GetString() != currentFingerprint)
                throw new PestoException("config.changed", "Les paramètres ont changé depuis leur affichage. Relisez-les avant de les enregistrer.");
            var candidate = current is null ? new JsonObject() : (JsonObject)current.DeepClone();
            var domain = Arguments.Text(args, "domain", true, 253).ToLowerInvariant();
            var prefix = Arguments.Text(args, "prefix", true, 12).ToUpperInvariant();
            var rootOu = Arguments.Text(args, "rootOu", true, 2048);
            var production = Arguments.Flag(args, "production");
            var convention = new NamingConvention(Arguments.Text(args, "namingPattern", true, 150), prefix);
            var preprodSite = Arguments.Text(args, "preprodSite", !production, 6).ToUpperInvariant();
            if (preprodSite.Length == 0) preprodSite = new string('0', convention.ServiceWidth);
            var preprodOu = Arguments.Text(args, "preprodOu", !production, 2048);
            var conf = candidate["CONF"] is JsonArray confs && confs[0] is JsonObject existingConf ? (JsonObject)existingConf.DeepClone()
                : new JsonObject { ["EntraPolicy"] = "Disabled", ["DsregLeaveOnMove"] = false, ["ClearProtectionOnMove"] = false, ["AllowHybridRepair"] = false };
            conf["Domaine"] = domain; conf["Prefixe"] = prefix; conf["DirectProd"] = production;
            conf["PreprodSite"] = preprodSite; conf["OUScanNoms"] = rootOu;
            if (args.TryGetProperty("entraPolicy", out _))
            {
                var entraPolicy = Arguments.Text(args, "entraPolicy", true, 16);
                if (entraPolicy is not (EntraPreparationRules.Disabled or EntraPreparationRules.HybridOnly))
                    throw ConfigurationDocument.Invalid("La politique Entra doit valoir exactement Disabled ou HybridOnly.");
                conf["EntraPolicy"] = entraPolicy;
            }
            candidate["CONF"] = new JsonArray(conf);
            candidate["Configured"] = true;
            candidate["OUBase"] = new JsonArray(new JsonObject { ["Nom"] = "ROOT", ["OU"] = rootOu });
            if (preprodOu.Length > 0) candidate["OUBase"]!.AsArray().Add(new JsonObject { ["Nom"] = "PREPROD", ["OU"] = preprodOu });
            candidate["NamingConvention"] = new JsonObject
            {
                ["Schema"] = 1, ["Id"] = "v2", ["Types"] = convention.Types,
                ["Tokens"] = new JsonArray(convention.Tokens.Select(t => (JsonNode?)JsonValue.Create(t)).ToArray()),
                ["Widths"] = new JsonObject { ["Prefix"] = convention.PrefixWidth, ["Site"] = convention.SiteWidth, ["Service"] = convention.ServiceWidth, ["Number"] = convention.NumberWidth }
            };
            var policy = candidate["POLICY"] as JsonObject ?? new JsonObject
            { ["Schema"] = 1, ["AllowOfflineJoin"] = false, ["UnattendedJoinEnabled"] = false, ["UnattendedOperationsEnabled"] = false };
            if (policy.Parent is null) candidate["POLICY"] = policy;
            policy["RandomNameEnabled"] = Arguments.Flag(args, "randomNames");
            policy.Remove("RandomNameChoice");
            // These are explicit configuration choices only. Never probe a share, audit sink or AD group here.
            if (args.TryGetProperty("coordinationRoot", out _)) policy["CoordinationRoot"] = Arguments.Text(args, "coordinationRoot", false, 240);
            foreach (var (argument, property) in new[] { ("coordinationRequired", "CoordinationRequired"), ("reserveNamesInAd", "ReserveNamesInAD"),
                ("auditEventLogEnabled", "AuditEventLogEnabled"), ("blockJoinOnClockSkew", "BlockJoinOnClockSkew"),
                ("allowPrecreatedJoin", "AllowPrecreatedJoin"), ("allowOfflineJoin", "AllowOfflineJoin"),
                ("unattendedJoinEnabled", "UnattendedJoinEnabled"), ("unattendedOperationsEnabled", "UnattendedOperationsEnabled") })
                if (args.TryGetProperty(argument, out _)) policy[property] = Arguments.Flag(args, argument);
            if (args.TryGetProperty("excludedGroupGuids", out var groups))
            {
                if (groups.ValueKind != JsonValueKind.Array || groups.GetArrayLength() > 200)
                    throw ConfigurationDocument.Invalid("Définissez au plus 200 GUID de groupes exclus.");
                var identifiers = new HashSet<Guid>();
                var values = new JsonArray();
                foreach (var item in groups.EnumerateArray())
                {
                    if (item.ValueKind != JsonValueKind.String || item.GetString() is not { Length: <= 38 } text
                        || !Guid.TryParse(text, out var guid) || guid == Guid.Empty || !identifiers.Add(guid))
                        throw ConfigurationDocument.Invalid("Les groupes exclus exigent des GUID non vides, valides et uniques.");
                    values.Add(guid.ToString("D"));
                }
                policy["ExcludedGroupGuids"] = values;
            }
            if (!args.TryGetProperty("sites", out var siteValues) || siteValues.ValueKind != JsonValueKind.Array || siteValues.GetArrayLength() is < 1 or > 100)
                throw ConfigurationDocument.Invalid("Définissez de 1 à 100 sites.");
            var explicitSites = new JsonArray();
            var tags = new JsonArray();
            var allOusEmpty = true;
            foreach (var site in siteValues.EnumerateArray())
            {
                Arguments.Only(site, "id", "name", "code", "ou");
                var id = Arguments.Text(site, "id", true, 80);
                var name = Arguments.Text(site, "name", true, 200);
                var code = Arguments.Text(site, "code", true, 4).ToUpperInvariant();
                var ou = Arguments.Text(site, "ou", false, 2048);
                if (ou.Length > 0 && ou != "null") allOusEmpty = false;
                explicitSites.Add(new JsonObject { ["Id"] = id, ["Name"] = name, ["Code"] = code, ["OU"] = ou });
                tags.Add(new JsonObject { ["Site"] = name, ["Tag"] = code });
            }
            if (allOusEmpty && current is not null && current["V2DirectorySites"] is null)
            {
                // A legacy configuration uses discovered child OUs; editing other fields must retain that model.
                if (ConfigurationDocument.Canonical(tags) != ConfigurationDocument.Canonical(current["TAGS"]!))
                    throw ConfigurationDocument.Invalid("Pour modifier ces sites historiques, renseignez leur OU complète ou importez un référentiel.");
            }
            else
            {
                candidate["V2DirectorySites"] = explicitSites;
                candidate["OUSite"] = new JsonArray(new JsonObject { ["Nom"] = "Gestion", ["OU"] = rootOu });
                if (!production && !tags.Any(t => t!["Site"]!.GetValue<string>().Equals("PREPROD", StringComparison.OrdinalIgnoreCase)))
                {
                    var preprod = explicitSites.FirstOrDefault(s => s!["OU"]!.GetValue<string>().Equals(preprodOu, StringComparison.OrdinalIgnoreCase));
                    if (preprod is null) throw ConfigurationDocument.Invalid("En préproduction, ajoutez le site correspondant à l’OU de préproduction.");
                    tags.Add(new JsonObject { ["Site"] = "PREPROD", ["Tag"] = preprod["Code"]!.GetValue<string>() });
                }
                candidate["TAGS"] = tags;
            }
            var clean = ConfigurationDocument.Sanitize(candidate.ToJsonString());
            return CreateImport(clean, "settings", "settings-" + clock.GetUtcNow().ToString("yyyyMMdd-HHmmss"),
                ConfigurationDocument.Fingerprint(clean), null, snapshotStamp, requireSameSnapshot: true);
        }
    }

    public JsonObject PrepareCustomizedPack(string sourcePack, string destination, string version)
    {
        RequireLive();
        lock (gate)
        {
            var bundle = Export(version);
            // Validate closed binary inventory before any copy; never include profile, history, sessions or secrets.
            var sourceFingerprint = UpdatePackage.Validate(sourcePack).Fingerprint;
            destination = ConfigurationStore.LocalPath(destination);
            var sourcePath = Path.GetFullPath(sourcePack).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if ((destination + Path.DirectorySeparatorChar).StartsWith(sourcePath, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
                throw new PestoException("package.destination", "Préparez le pack personnalisé dans un dossier extérieur au pack source.");
            if (Directory.Exists(destination) || File.Exists(destination)) throw new PestoException("package.destination", "Le dossier de destination existe déjà.");
            var stage = Path.Combine(Path.GetDirectoryName(destination)!, ".pesto-personnalisation-" + Guid.NewGuid().ToString("N"));
            try
            {
                // The copy must still be the exact validated source before Rehash can bless our own changes.
                UpdatePackage.CopyToNew(sourcePack, stage, sourceFingerprint);
                var defaults = Path.Combine(stage, "wad", "defaults");
                Directory.CreateDirectory(defaults);
                File.WriteAllText(Path.Combine(defaults, "configuration.json"), ConfigurationDocument.Canonical(bundle));
                var manifestPath = Path.Combine(stage, "wad", "Pesto.package.json");
                var manifest = ConfigurationDocument.ParseObject(File.ReadAllText(manifestPath));
                manifest["distribution"] = "custom";
                manifest["official"] = false;
                manifest["configurationVersion"] = version;
                manifest["configurationFingerprint"] = bundle["fingerprint"]!.DeepClone();
                File.WriteAllText(manifestPath, manifest.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
                UpdatePackage.Rehash(stage);
                _ = UpdatePackage.Validate(stage);
                Directory.Move(stage, destination);
            }
            finally { if (Directory.Exists(stage)) Directory.Delete(stage, recursive: true); }
            return new JsonObject { ["status"] = "prepared", ["distribution"] = "custom", ["official"] = false,
                ["destination"] = destination, ["version"] = version, ["fingerprint"] = bundle["fingerprint"]!.DeepClone() };
        }
    }

    private JsonObject ReadConfiguration() => ConfigurationDocument.Sanitize(ConfigurationStore.Read(ConfigurationPath));

    private ConfigurationState InspectConfiguration()
    {
        try
        {
            var snapshot = ConfigurationStore.ReadOptionalSnapshot(ConfigurationPath);
            if (snapshot is null) return new(false, null, null, null);
            try { return new(true, ConfigurationDocument.Sanitize(snapshot.Text), snapshot.Stamp, null); }
            catch (PestoException) { return new(true, null, snapshot.Stamp, InvalidConfigurationMessage); }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or PestoException)
        {
            // No file contents, parser messages, paths or unknown policy values are disclosed to the WebView.
            return new(true, null, null, InvalidConfigurationMessage);
        }
    }

    private JsonObject StatusNode(ConfigurationState observed) => new()
    {
        ["configured"] = observed.Configuration is not null,
        ["configurationExists"] = observed.Exists,
        ["configurationState"] = observed.State,
        ["diagnostic"] = observed.Diagnostic,
        ["fingerprint"] = observed.Configuration is null ? null : ConfigurationDocument.Fingerprint(observed.Configuration),
        ["profile"] = ConfigurationDocument.Hash(profileIdentity)[..16],
        ["pendingDistribution"] = observed.State == "invalid" ? null : pendingDistribution?.DeepClone(),
        ["requiresDecision"] = observed.State != "invalid" && pendingDistribution is not null
    };

    private void ClearPendingDistribution()
    {
        if (pendingDistribution?["planId"] is JsonValue value && value.TryGetValue<string>(out var id)) imports.Remove(id);
        pendingDistribution = null;
    }
    private string DecisionKey(string version, string fingerprint) => ConfigurationDocument.Hash(profileIdentity + "\n" + version + "\n" + fingerprint);
    private JsonObject ReadDecisions() => File.Exists(DecisionsPath) ? ConfigurationDocument.ParseObject(ConfigurationStore.Read(DecisionsPath)) : new JsonObject();
    private void SaveDecision(JsonObject decisions, string key, string choice, string version, string fingerprint)
    {
        decisions[key] = new JsonObject { ["choice"] = choice, ["version"] = version, ["fingerprint"] = fingerprint,
            ["at"] = clock.GetUtcNow().ToString("O") };
        _ = ConfigurationStore.Write(DecisionsPath, decisions.ToJsonString(), ConfigurationStore.Stamp(DecisionsPath), backup: false);
    }

    private JsonObject CreateImport(JsonObject candidate, string source, string version, string fingerprint, string? decisionKey,
        string? basedOnStamp = null, bool requireSameSnapshot = false, bool allowInvalidCurrent = false)
    {
        var id = Guid.NewGuid().ToString("N");
        var observed = InspectConfiguration();
        var expectedStamp = observed.Stamp;
        if (observed.Exists && expectedStamp is null)
            throw new PestoException("config.unreadable", "Le fichier existant ne peut pas être lu et sauvegardé exactement. Aucun remplacement n’est préparé ; vérifiez les droits, le type et la taille du fichier.");
        var replacesInvalid = observed.State == "invalid";
        if (replacesInvalid && !allowInvalidCurrent) throw new PestoException("config.recovery_required", InvalidConfigurationMessage);
        if (requireSameSnapshot && expectedStamp != basedOnStamp)
            throw new PestoException("config.changed", "La configuration a changé pendant la préparation. Relisez les paramètres ; aucun aperçu périmé n’est utilisable.");
        var current = observed.Configuration ?? new JsonObject();
        var expires = clock.GetUtcNow().AddMinutes(15);
        PruneImports();
        imports[id] = new(id, (JsonObject)candidate.DeepClone(), expectedStamp, expires, source, version, fingerprint, decisionKey);
        return new JsonObject
        {
            ["planId"] = id, ["source"] = source, ["version"] = version, ["fingerprint"] = fingerprint,
            ["expiresAt"] = expires.ToString("O"),
            ["differences"] = replacesInvalid ? new JsonArray(new JsonObject
            {
                ["field"] = "Configuration existante invalide",
                ["before"] = "Fichier invalide : son contenu n’est pas affiché. Ses octets originaux seront sauvegardés avant le remplacement confirmé.",
                ["after"] = candidate.DeepClone()
            }) : Differences(current, candidate),
            ["replacesInvalidConfiguration"] = replacesInvalid,
            ["backupRequired"] = expectedStamp is not null, ["requiresConfirmation"] = true
        };
    }

    private ImportPlan GetImport(string id)
    {
        if (!imports.TryGetValue(id, out var plan) || plan.ExpiresAt <= clock.GetUtcNow())
            throw new PestoException("config.plan", "Cet aperçu est absent, consommé ou expiré. Préparez une nouvelle comparaison.");
        return plan;
    }

    private void RefreshPendingDistribution()
    {
        if (pendingDistribution is null) return;
        var id = ConfigurationDocument.String(pendingDistribution, "planId");
        if (!imports.TryGetValue(id, out var plan)) { pendingDistribution = null; return; }
        if (plan.ExpiresAt > clock.GetUtcNow() && plan.ExpectedStamp == ConfigurationStore.Stamp(ConfigurationPath)) return;
        imports.Remove(id);
        pendingDistribution = CreateImport(plan.Configuration, plan.Source, plan.Version, plan.Fingerprint, plan.DecisionKey);
        pendingDistribution["requiresDecision"] = true;
    }

    private void PruneImports()
    {
        foreach (var id in imports.Where(p => p.Value.ExpiresAt <= clock.GetUtcNow()).Select(p => p.Key).ToArray()) imports.Remove(id);
        if (imports.Count >= 32) throw new PestoException("config.busy", "Trop de comparaisons ouvertes. Fermez les aperçus ou attendez leur expiration.");
    }

    internal static JsonArray Differences(JsonObject before, JsonObject after)
    {
        var result = new JsonArray();
        foreach (var key in before.Select(p => p.Key).Union(after.Select(p => p.Key), StringComparer.Ordinal).Order(StringComparer.Ordinal))
        {
            var previous = before[key]; var next = after[key];
            if ((previous is null ? "null" : ConfigurationDocument.Canonical(previous)) == (next is null ? "null" : ConfigurationDocument.Canonical(next))) continue;
            result.Add(new JsonObject { ["field"] = key, ["before"] = previous?.DeepClone(), ["after"] = next?.DeepClone() });
        }
        return result;
    }

    private JsonObject Result(string status, bool changed, string? backup)
    {
        var result = StatusNode(InspectConfiguration());
        result["status"] = status; result["changed"] = changed; result["backup"] = backup;
        return result;
    }

    private void RequireLive()
    {
        if (mode != ConfigurationAccessMode.Live)
            throw new PestoException("config.isolated", "La configuration réelle est inaccessible en démonstration, contrôle de santé et reprise binaire.");
    }
}

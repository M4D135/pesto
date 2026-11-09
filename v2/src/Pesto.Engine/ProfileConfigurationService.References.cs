using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Core;

namespace Pesto.Engine;

public sealed partial class ProfileConfigurationService
{
    private sealed record ReferenceChange(string Key, string Kind, JsonObject Incoming, JsonObject? Current, bool Conflict);
    private sealed record ReferencePlan(string Id, string Version, string ExpectedStamp, DateTimeOffset ExpiresAt,
        JsonObject Configuration, IReadOnlyList<ReferenceChange> Changes);
    private readonly Dictionary<string, ReferencePlan> referencePlans = new(StringComparer.Ordinal);

    public JsonObject PreviewReferences(string text)
    {
        RequireLive();
        lock (gate)
        {
            var document = ConfigurationDocument.ParseObject(text);
            ConfigurationDocument.RequireFields(document, ["schema", "kind", "version", "sites", "services"]);
            if (document["schema"] is not JsonValue schema || !schema.TryGetValue<int>(out var schemaNumber) || schemaNumber != 1
                || ConfigurationDocument.String(document, "kind") != "pesto.references")
                throw ConfigurationDocument.Invalid("Référentiel Pesto schema 1 attendu.");
            var version = ConfigurationDocument.String(document, "version");
            ConfigurationDocument.ValidateVersion(version);
            var snapshot = ConfigurationStore.ReadSnapshot(ConfigurationPath);
            var snapshotStamp = snapshot.Stamp;
            var current = ConfigurationDocument.Sanitize(snapshot.Text);
            var config = V1Config.ValidateText(current.ToJsonString());
            var sitePattern = "^[A-Z]{" + config.Convention.SiteWidth + "}$";
            var servicePattern = "^[A-Z0-9]{" + config.Convention.ServiceWidth + "}$";
            var changes = new List<ReferenceChange>();
            var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var tags = current["TAGS"] as JsonArray ?? new JsonArray();
            var catalogue = current["NameCatalogue"] as JsonArray ?? new JsonArray();
            var labels = current["ReferenceData"]?["ServiceLabels"] as JsonArray ?? new JsonArray();
            if (document["sites"] is not JsonArray sites || sites.Count > 500 || document["services"] is not JsonArray services || services.Count > 2000)
                throw ConfigurationDocument.Invalid("Les listes sites/services sont requises et doivent rester bornées.");
            foreach (var item in sites)
            {
                var incoming = item as JsonObject ?? throw ConfigurationDocument.Invalid("Site de référentiel invalide.");
                ConfigurationDocument.RequireFields(incoming, ["pattern", "code"]);
                var pattern = ConfigurationDocument.String(incoming, "pattern");
                var code = ConfigurationDocument.String(incoming, "code").ToUpperInvariant();
                if (pattern.Length > 200 || !Regex.IsMatch(code, sitePattern)) throw ConfigurationDocument.Invalid("Motif de site ou largeur de code invalide.");
                var key = "site:" + pattern.ToUpperInvariant();
                if (!keys.Add(key)) throw ConfigurationDocument.Invalid("Le référentiel contient un site en double.");
                var existing = tags.OfType<JsonObject>().FirstOrDefault(t => ConfigurationDocument.String(t, "Site").Equals(pattern, StringComparison.OrdinalIgnoreCase));
                var candidate = new JsonObject { ["Site"] = pattern, ["Tag"] = code };
                var conflict = existing is not null && !ConfigurationDocument.String(existing, "Tag").Equals(code, StringComparison.OrdinalIgnoreCase);
                changes.Add(new(key, "site", candidate, existing is null ? null : (JsonObject)existing.DeepClone(), conflict));
            }
            var knownSites = tags.OfType<JsonObject>().Select(t => ConfigurationDocument.String(t, "Tag").ToUpperInvariant())
                .Concat(changes.Where(c => c.Kind == "site").Select(c => ConfigurationDocument.String(c.Incoming, "Tag"))).ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var item in services)
            {
                var incoming = item as JsonObject ?? throw ConfigurationDocument.Invalid("Service de référentiel invalide.");
                ConfigurationDocument.RequireFields(incoming, ["site", "code", "name"]);
                var site = ConfigurationDocument.String(incoming, "site").ToUpperInvariant();
                var code = ConfigurationDocument.String(incoming, "code").ToUpperInvariant();
                var name = ConfigurationDocument.String(incoming, "name");
                if (!Regex.IsMatch(site, sitePattern) || !Regex.IsMatch(code, servicePattern) || name.Length > 200 || !knownSites.Contains(site))
                    throw ConfigurationDocument.Invalid("Service invalide ou rattaché à un site absent du référentiel.");
                var key = "service:" + site + ":" + code;
                if (!keys.Add(key)) throw ConfigurationDocument.Invalid("Le référentiel contient un service en double.");
                var existingPair = catalogue.OfType<JsonObject>().FirstOrDefault(t => PairMatches(t, site, code));
                var existingLabel = labels.OfType<JsonObject>().FirstOrDefault(t => PairMatches(t, site, code));
                var existing = existingPair is null ? null : new JsonObject { ["Site"] = site, ["Service"] = code,
                    ["Name"] = existingLabel is null ? code : ConfigurationDocument.String(existingLabel, "Name") };
                var candidate = new JsonObject { ["Site"] = site, ["Service"] = code, ["Name"] = name };
                changes.Add(new(key, "service", candidate, existing, existing is not null && ConfigurationDocument.String(existing, "Name") != name));
            }
            var id = Guid.NewGuid().ToString("N");
            var expires = clock.GetUtcNow().AddMinutes(15);
            if (ConfigurationStore.Stamp(ConfigurationPath) != snapshotStamp)
                throw new PestoException("config.changed", "La configuration a changé pendant la comparaison du référentiel. Aucun plan périmé n’est conservé.");
            foreach (var stale in referencePlans.Where(p => p.Value.ExpiresAt <= clock.GetUtcNow()).Select(p => p.Key).ToArray()) referencePlans.Remove(stale);
            if (referencePlans.Count >= 32) throw new PestoException("config.busy", "Trop de comparaisons de référentiels ouvertes.");
            referencePlans[id] = new(id, version, snapshotStamp, expires, current, changes);
            return new JsonObject
            {
                ["planId"] = id, ["version"] = version, ["expiresAt"] = expires.ToString("O"),
                ["additions"] = changes.Count(c => c.Current is null), ["conflictCount"] = changes.Count(c => c.Conflict),
                ["unchanged"] = changes.Count(c => c.Current is not null && !c.Conflict),
                ["conflicts"] = new JsonArray(changes.Where(c => c.Conflict).Select(c => (JsonNode)new JsonObject
                { ["key"] = c.Key, ["kind"] = c.Kind, ["current"] = c.Current!.DeepClone(), ["incoming"] = c.Incoming.DeepClone() }).ToArray()),
                ["changes"] = new JsonArray(changes.Select(c => (JsonNode)new JsonObject
                { ["key"] = c.Key, ["kind"] = c.Kind, ["conflict"] = c.Conflict, ["current"] = c.Current?.DeepClone(), ["incoming"] = c.Incoming.DeepClone() }).ToArray()),
                ["requiresConfirmation"] = true
            };
        }
    }

    public JsonObject ApplyReferences(string planId, IReadOnlyDictionary<string, string> resolutions, bool confirmed)
    {
        RequireLive();
        if (!confirmed) throw new PestoException("config.confirmation", "Confirmez l’application du référentiel comparé.");
        lock (gate)
        {
            using var profileLock = ConfigurationStore.Lock(profileRoot);
            if (!referencePlans.TryGetValue(planId, out var plan) || plan.ExpiresAt <= clock.GetUtcNow())
                throw new PestoException("config.plan", "Aperçu de référentiel absent, consommé ou expiré.");
            var conflictKeys = plan.Changes.Where(c => c.Conflict).Select(c => c.Key).ToHashSet(StringComparer.Ordinal);
            if (resolutions.Count != conflictKeys.Count || resolutions.Any(p => !conflictKeys.Contains(p.Key) || p.Value is not ("current" or "incoming")))
                throw new PestoException("references.conflicts", "Choisissez Conserver ou Remplacer pour chaque conflit, sans résolution supplémentaire.");
            var candidate = (JsonObject)plan.Configuration.DeepClone();
            var tags = candidate["TAGS"] as JsonArray ?? new JsonArray();
            if (tags.Parent is null) candidate["TAGS"] = tags;
            var catalogue = candidate["NameCatalogue"] as JsonArray ?? new JsonArray();
            if (catalogue.Parent is null) candidate["NameCatalogue"] = catalogue;
            var labels = candidate["ReferenceData"]?["ServiceLabels"] is JsonArray originalLabels ? (JsonArray)originalLabels.DeepClone() : new JsonArray();
            foreach (var change in plan.Changes)
            {
                if (change.Conflict && resolutions[change.Key] == "current") continue;
                if (change.Kind == "site")
                {
                    var pattern = ConfigurationDocument.String(change.Incoming, "Site");
                    var existing = tags.OfType<JsonObject>().FirstOrDefault(t => ConfigurationDocument.String(t, "Site").Equals(pattern, StringComparison.OrdinalIgnoreCase));
                    if (existing is not null) tags.Remove(existing);
                    tags.Add(change.Incoming.DeepClone());
                    if (candidate["V2DirectorySites"] is JsonArray explicitSites)
                        foreach (var site in explicitSites.OfType<JsonObject>().Where(s => ConfigurationDocument.String(s, "Name").Equals(pattern, StringComparison.OrdinalIgnoreCase)))
                            site["Code"] = change.Incoming["Tag"]!.DeepClone();
                }
                else
                {
                    var site = ConfigurationDocument.String(change.Incoming, "Site");
                    var service = ConfigurationDocument.String(change.Incoming, "Service");
                    if (!catalogue.OfType<JsonObject>().Any(t => PairMatches(t, site, service)))
                        catalogue.Add(new JsonObject { ["Site"] = site, ["Service"] = service });
                    var existing = labels.OfType<JsonObject>().FirstOrDefault(t => PairMatches(t, site, service));
                    if (existing is not null) labels.Remove(existing);
                    labels.Add(change.Incoming.DeepClone());
                }
            }
            var validSites = tags.OfType<JsonObject>().Select(t => ConfigurationDocument.String(t, "Tag")).ToHashSet(StringComparer.OrdinalIgnoreCase);
            if (plan.Changes.Where(c => c.Kind == "service" && (!c.Conflict || resolutions[c.Key] == "incoming"))
                .Any(c => !validSites.Contains(ConfigurationDocument.String(c.Incoming, "Site"))))
                throw new PestoException("references.conflicts", "Un service importé dépend d’un changement de site conservé. Résolvez ces deux choix de façon cohérente.");
            candidate["ReferenceData"] = new JsonObject { ["Schema"] = 1, ["Version"] = plan.Version, ["ServiceLabels"] = labels };
            var clean = ConfigurationDocument.Sanitize(candidate.ToJsonString());
            var backup = ConfigurationStore.Write(ConfigurationPath, ConfigurationDocument.Canonical(clean), plan.ExpectedStamp);
            referencePlans.Remove(planId);
            return Result("applied", true, backup);
        }
    }

    private static bool PairMatches(JsonObject value, string site, string service) =>
        ConfigurationDocument.String(value, "Site").Equals(site, StringComparison.OrdinalIgnoreCase)
        && ConfigurationDocument.String(value, "Service").Equals(service, StringComparison.OrdinalIgnoreCase);
}

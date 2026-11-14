using System.Text;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Explicit administration of the configured registry only. Status never probes a share; no API accepts a path.</summary>
public sealed class SharedCoordinationAdministration(string configurationPath, SharedCoordinationAccessMode mode,
    ISharedCoordinationAccess? access = null, TimeProvider? clock = null)
{
    private readonly object gate = new();
    private readonly ISharedCoordinationAccess context = access ?? new CurrentIdentityCoordinationAccess();
    private readonly TimeProvider time = clock ?? TimeProvider.System;
    private readonly Dictionary<string, Preparation> preparations = new(StringComparer.Ordinal);
    private sealed record Preparation(string Id, SharedCoordinationConfiguration Configuration,
        SharedCoordinationRegistryState State, DateTimeOffset ExpiresAt);

    public JsonObject Status()
    {
        SharedCoordinationProtocol.Guard(mode);
        lock (gate)
        {
            if (!File.Exists(configurationPath)) return new()
            {
                ["configured"] = false, ["required"] = false, ["root"] = "", ["domain"] = "",
                ["state"] = "notConfigured", ["ready"] = false, ["inspected"] = false,
                ["message"] = "Configurez le domaine et le dossier de coordination avant de demander son inspection."
            };
            var configuration = ReadConfiguration();
            return new()
            {
                ["configured"] = configuration.Root.Length > 0, ["required"] = configuration.Required,
                ["root"] = configuration.Root, ["domain"] = configuration.Domain, ["configFingerprint"] = configuration.ConfigSha256,
                ["state"] = configuration.Root.Length == 0 ? "disabled" : "notInspected", ["inspected"] = false,
                ["message"] = "Aucun partage n’est sondé au chargement. Inspectez explicitement le registre configuré."
            };
        }
    }

    public JsonObject Inspect()
    {
        SharedCoordinationProtocol.Guard(mode);
        lock (gate)
        {
            var configuration = RequireConfigured();
            var state = context.Run(() => SharedCoordinationProtocol.InspectRegistry(configuration.Root, configuration.Domain));
            RequireUnchanged(configuration);
            return Describe(configuration, state);
        }
    }

    public JsonObject Prepare()
    {
        SharedCoordinationProtocol.Guard(mode);
        lock (gate)
        {
            var configuration = RequireConfigured();
            var state = context.Run(() =>
            {
                var observed = SharedCoordinationProtocol.InspectRegistry(configuration.Root, configuration.Domain);
                RequireExistingParent(observed);
                return observed;
            });
            RequireUnchanged(configuration);
            foreach (var stale in preparations.Where(p => p.Value.ExpiresAt <= time.GetUtcNow()).Select(p => p.Key).ToArray()) preparations.Remove(stale);
            if (preparations.Count >= 16) throw new PestoException("coordination.busy", "Trop de préparations de registre ouvertes.");
            var id = Guid.NewGuid().ToString("N");
            var expires = time.GetUtcNow().AddMinutes(15);
            preparations[id] = new(id, configuration, state, expires);
            var result = Describe(configuration, state);
            result["planId"] = id; result["expiresAt"] = expires.ToString("O");
            result["requiresConfirmation"] = true;
            result["actions"] = Actions(state);
            result["warnings"] = new JsonArray("Aucun partage ni ACL ne sera créé ou modifié.",
                "Aucun verrou existant ne sera remplacé ou expiré.");
            result["message"] = state.Ready ? "Ce registre est déjà prêt. Aucun fichier existant ne sera remplacé."
                : "Après confirmation, créer uniquement les éléments manquants dans ce dossier. Aucun partage ni droit Windows n’est créé ou modifié.";
            return result;
        }
    }

    public JsonObject Apply(string planId, bool confirmed)
    {
        SharedCoordinationProtocol.Guard(mode);
        if (!confirmed) throw new PestoException("coordination.confirmation", "Confirmez la préparation du registre affiché.");
        lock (gate)
        {
            if (!preparations.TryGetValue(planId, out var plan) || plan.ExpiresAt <= time.GetUtcNow())
                throw new PestoException("coordination.plan", "Préparation de registre absente, consommée ou expirée.");
            var localDirectory = Path.GetDirectoryName(Path.GetFullPath(configurationPath))!;
            using var configurationLock = ConfigurationStore.Lock(localDirectory);
            RequireUnchanged(plan.Configuration);
            // Consumed before creation: a partial IO failure requires a fresh inspection, never a hidden retry.
            preparations.Remove(planId);
            var result = context.Run(() =>
            {
                var current = SharedCoordinationProtocol.InspectRegistry(plan.Configuration.Root, plan.Configuration.Domain);
                if (current.Fingerprint != plan.State.Fingerprint)
                    throw new PestoException("coordination.changed", "Le registre a changé depuis l’aperçu. Aucune préparation concurrente n’est écrasée.");
                RequireExistingParent(current);
                SharedCoordinationProtocol.RequireNoLinks(current.Root);
                if (!current.RootExists) Directory.CreateDirectory(current.Root);
                SharedCoordinationProtocol.RequireNoLinks(current.Root);
                var marker = Path.Combine(current.Root, "pesto-coordination.json");
                if (!current.MarkerPresent)
                {
                    SharedCoordinationProtocol.RequireNoLinks(marker);
                    var json = new JsonObject { ["Schema"] = 1, ["Domain"] = plan.Configuration.Domain, ["Purpose"] = "PestoCoordination" }.ToJsonString();
                    using var file = new FileStream(marker, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
                    file.Write(Encoding.UTF8.GetBytes(json)); file.Flush(true);
                }
                var locks = Path.Combine(current.Root, "locks");
                SharedCoordinationProtocol.RequireNoLinks(locks);
                if (!current.LocksPresent) Directory.CreateDirectory(locks);
                var reservations = Path.Combine(current.Root, "reservations");
                SharedCoordinationProtocol.RequireNoLinks(reservations);
                if (!current.ReservationsPresent) Directory.CreateDirectory(reservations);
                var observed = SharedCoordinationProtocol.InspectRegistry(current.Root, plan.Configuration.Domain);
                if (!observed.Ready) throw new PestoException("coordination.unprepared", "La préparation du registre n’a pas pu être confirmée. Inspectez les éléments conservés avant toute nouvelle demande.");
                return Describe(plan.Configuration, observed);
            });
            RequireUnchanged(plan.Configuration);
            result["status"] = plan.State.Ready ? "unchanged" : "prepared";
            result["message"] = "Registre préparé et relu. Aucun partage ni ACL n’a été créé ou modifié ; les verrous existants sont conservés.";
            return result;
        }
    }

    private SharedCoordinationConfiguration ReadConfiguration() => SharedCoordinationConfiguration.ReadBytes(
        SharedCoordinationProtocol.ReadBounded(configurationPath, ConfigurationDocument.MaximumBytes));
    private SharedCoordinationConfiguration RequireConfigured()
    {
        var configuration = ReadConfiguration();
        if (configuration.Root.Length == 0) throw new PestoException("coordination.disabled", "Définissez d’abord le dossier de coordination dans les paramètres et confirmez la configuration.");
        return configuration;
    }
    private void RequireUnchanged(SharedCoordinationConfiguration expected)
    {
        if (ReadConfiguration().ConfigSha256 != expected.ConfigSha256)
            throw new PestoException("coordination.config_changed", "La configuration a changé depuis l’aperçu du registre. Relisez-la avant de confirmer.");
    }
    private static void RequireExistingParent(SharedCoordinationRegistryState state)
    {
        if (state.RootExists) return;
        var parent = Path.GetDirectoryName(state.Root);
        if (parent is null) throw new PestoException("coordination.parent", "Le dossier parent du registre doit exister ; aucun partage n’est créé automatiquement.");
        SharedCoordinationProtocol.RequireNoLinks(parent);
        if (!Directory.Exists(parent)) throw new PestoException("coordination.parent", "Le dossier parent du registre doit exister ; aucun partage ni arbre de dossiers n’est créé automatiquement.");
    }
    private static JsonArray Actions(SharedCoordinationRegistryState state)
    {
        var actions = new JsonArray();
        if (!state.RootExists) actions.Add("Créer le dossier de coordination sous son parent existant");
        if (!state.MarkerPresent) actions.Add("Créer le marqueur Schema 1 du domaine configuré");
        if (!state.LocksPresent) actions.Add("Créer le sous-dossier locks");
        if (!state.ReservationsPresent) actions.Add("Créer le sous-dossier reservations");
        return actions;
    }
    private static JsonObject Describe(SharedCoordinationConfiguration configuration, SharedCoordinationRegistryState state) => new()
    {
        ["configured"] = true, ["required"] = configuration.Required, ["domain"] = configuration.Domain,
        ["root"] = configuration.Root, ["configFingerprint"] = configuration.ConfigSha256,
        ["state"] = state.Ready ? "ready" : "unprepared", ["ready"] = state.Ready, ["prepared"] = state.Ready, ["inspected"] = true,
        ["rootExists"] = state.RootExists, ["markerPresent"] = state.MarkerPresent, ["locksPresent"] = state.LocksPresent,
        ["reservationsPresent"] = state.ReservationsPresent,
        ["registryFingerprint"] = state.Fingerprint,
        ["message"] = state.Ready ? "Marqueur du domaine et dossier de verrous relus ; aucune écriture effectuée par cette inspection."
            : "Registre incomplet. Préparez un aperçu puis confirmez explicitement les créations manquantes."
    };
}

using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Native selections stay outside the web page. No arbitrary file or process API is exposed.</summary>
public interface IPestoHostActions
{
    Task<string?> ReadImportAsync(string kind, CancellationToken cancellationToken);
    Task<string?> SaveExportAsync(string suggestedName, string text, CancellationToken cancellationToken);
    Task<string?> SelectPackSourceAsync(string kind, CancellationToken cancellationToken);
    Task<object?> OpenDemoAsync(CancellationToken cancellationToken);
    Task<object?> ReconnectAsync(CancellationToken cancellationToken);
    Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken cancellationToken);
}

/// <summary>
/// One admission gate for business operations and maintenance, including callers bypassing the web dispatcher.
/// A demo never invokes a live service or a file picker; isolation is decided before argument/path inspection.
/// </summary>
public sealed class ApplicationServicesBackend(IPestoBackend business, bool simulation,
    ProfileConfigurationService? configuration, UpdateService? updates, IPestoHostActions host,
    string installationDirectory, SharedCoordinationAdministration? coordination = null) : IPestoBackend, IDisposable
{
    private readonly SemaphoreSlim admission = new(1, 1);
    private bool handoffRequested;

    public async Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        if (simulation && (operation.StartsWith("configuration.", StringComparison.Ordinal)
            || operation.StartsWith("references.", StringComparison.Ordinal)
            || operation.StartsWith("updates.", StringComparison.Ordinal)
            || operation.StartsWith("coordination.", StringComparison.Ordinal)
            || operation.StartsWith("reservations.", StringComparison.Ordinal)
            || operation.StartsWith("attributes.", StringComparison.Ordinal)
            || operation.StartsWith("offlineJoin.", StringComparison.Ordinal)
            || operation is "join.precreated.preview" or "receipts.prepareAcknowledgement" or "receipts.acknowledge"
                or "receipts.prepareRestart" or "receipts.restart"
            || operation.StartsWith("host.", StringComparison.Ordinal) || operation == "demo.open"))
            throw new PestoException("demo.isolated", "La démonstration est isolée : aucun fichier réel, réseau, profil ni mise à jour n’est accessible.");
        if (business is ConfigurationOnlyBackend && operation is ("offlineJoin.open" or "coordination.inspect" or "coordination.prepare" or "coordination.apply"))
            throw new PestoException("session.configurationOnly", "Configuration locale : reconnectez Pesto avant une action métier ou l’accès au registre partagé.");
        await admission.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (handoffRequested) throw new PestoException("host.closing", "La fermeture est engagée. Aucune nouvelle opération ne peut démarrer.");
            if (simulation) return await business.InvokeAsync(operation, args, cancellationToken).ConfigureAwait(false);
            if (operation.StartsWith("demo.", StringComparison.Ordinal) && operation != "demo.open")
                throw new PestoException("demo.required", "Cette commande appartient à la fenêtre de démonstration isolée.");
            switch (operation)
            {
                case "demo.open":
                    Arguments.Only(args);
                    return await host.OpenDemoAsync(cancellationToken).ConfigureAwait(false);
                case "offlineJoin.open":
                    Arguments.Only(args);
                    return host is IPestoOfflineJoinHost offlineHost
                        ? await offlineHost.OpenOfflineJoinAsync(cancellationToken).ConfigureAwait(false)
                        : throw new PestoException("offlineJoin.unavailable", "Le parcours local de jonction hors ligne n’est pas raccordé à cet hôte.");
                case "configuration.status":
                {
                    Arguments.Only(args);
                    var status = Config().Status();
                    // Light read for the default-configuration confirmation; the whole pack is validated when writing.
                    status["installationDefault"] = InstallationDefaults.Inspect(installationDirectory).ToJson();
                    return status;
                }
                case "configuration.settings":
                    Arguments.Only(args);
                    return Config().ReadSettings();
                case "configuration.export":
                {
                    Arguments.Only(args, "version");
                    var version = OptionalVersion(args);
                    var bundle = Config().Export(version);
                    var file = await host.SaveExportAsync("Pesto-configuration.json", bundle.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), cancellationToken).ConfigureAwait(false);
                    return new JsonObject { ["status"] = file is null ? "cancelled" : "exported", ["file"] = file, ["fingerprint"] = bundle["fingerprint"]?.DeepClone() };
                }
                case "configuration.previewImport":
                {
                    Arguments.Only(args);
                    var text = await host.ReadImportAsync("configuration", cancellationToken).ConfigureAwait(false);
                    return text is null ? Cancelled() : Config().PreviewImport(text);
                }
                case "configuration.previewSettings": return Config().PreviewSettings(args);
                case "coordination.status":
                    Arguments.Only(args);
                    if (business is ConfigurationOnlyBackend)
                    {
                        var settings = Config().ReadSettings();
                        var root = settings["coordinationRoot"]?.GetValue<string>() ?? "";
                        return new JsonObject
                        {
                            ["configured"] = root.Length > 0, ["root"] = root,
                            ["domain"] = settings["domain"]?.DeepClone() ?? JsonValue.Create(""),
                            ["required"] = settings["coordinationRequired"]?.DeepClone() ?? JsonValue.Create(false),
                            ["configurationOnly"] = true,
                            ["message"] = "Paramètres locaux relus sans accès au partage. Reconnectez Pesto pour tester ou préparer le registre."
                        };
                    }
                    return Coordination().Status();
                case "coordination.inspect":
                    Arguments.Only(args); return Coordination().Inspect();
                case "coordination.prepare":
                    Arguments.Only(args); return Coordination().Prepare();
                case "coordination.apply":
                    Arguments.Only(args, "planId", "confirmed");
                    return Coordination().Apply(Arguments.Text(args, "planId", true, 100), Arguments.Flag(args, "confirmed"));
                case "configuration.applyImport":
                    Arguments.Only(args, "planId", "confirmed");
                    return Config().ApplyImport(Arguments.Text(args, "planId", true, 100), Arguments.Flag(args, "confirmed"));
                case "configuration.decideDistribution":
                    Arguments.Only(args, "planId", "replace", "confirmed");
                    return Config().DecideDistribution(Arguments.Text(args, "planId", true, 100), Arguments.Flag(args, "replace"), Arguments.Flag(args, "confirmed"));
                case "configuration.setDefault":
                    Arguments.Only(args, "version", "expectedSha256", "confirmed");
                    Confirm(args);
                    // Written in place in this installation, like GLPI-Pilot: no destination, no rebuilt pack.
                    return Config().WriteInstallationDefault(installationDirectory, OptionalVersion(args), Arguments.Text(args, "expectedSha256", false, 64));
                case "references.preview":
                {
                    Arguments.Only(args);
                    var text = await host.ReadImportAsync("references", cancellationToken).ConfigureAwait(false);
                    return text is null ? Cancelled() : Config().PreviewReferences(text);
                }
                case "references.apply":
                {
                    Arguments.Only(args, "planId", "resolutions", "confirmed");
                    var resolutions = new Dictionary<string, string>(StringComparer.Ordinal);
                    if (args.TryGetProperty("resolutions", out var items))
                    {
                        if (items.ValueKind != JsonValueKind.Array || items.GetArrayLength() > 2500)
                            throw new PestoException("invalid_arguments", "Liste de résolutions bornée attendue.");
                        foreach (var item in items.EnumerateArray())
                        {
                            Arguments.Only(item, "key", "choice");
                            if (!resolutions.TryAdd(Arguments.Text(item, "key", true, 256), Arguments.Text(item, "choice", true, 20)))
                                throw new PestoException("invalid_arguments", "Une résolution de conflit est répétée.");
                        }
                    }
                    return Config().ApplyReferences(Arguments.Text(args, "planId", true, 100), resolutions, Arguments.Flag(args, "confirmed"));
                }
                case "updates.status":
                    Arguments.Only(args); return Updates().Status();
                case "updates.windows":
                    Arguments.Only(args); return PackWindows.Describe(PackSource()?.List() ?? []);
                case "updates.inspect":
                {
                    Arguments.Only(args, "source", "kind");
                    var source = Arguments.Text(args, "source");
                    if (source.Length == 0)
                    {
                        var kind = Arguments.Text(args, "kind", true, 10);
                        if (kind is not ("zip" or "folder")) throw new PestoException("invalid_arguments", "Choisissez ZIP ou dossier.");
                        source = await host.SelectPackSourceAsync(kind, cancellationToken).ConfigureAwait(false) ?? "";
                    }
                    return source.Length == 0 ? Cancelled() : Updates().InspectLocal(source);
                }
                case "updates.prepare":
                    Arguments.Only(args, "candidateId");
                    return await Updates().PrepareAsync(Arguments.Text(args, "candidateId", true, 100), cancellationToken).ConfigureAwait(false);
                case "updates.install":
                case "updates.rollback":
                case "updates.recover":
                {
                    Arguments.Only(args, operation == "updates.install" ? ["preparedId", "confirmed", "closeWindows"] : ["confirmed", "closeWindows"]);
                    Confirm(args);
                    if (PackSource() is { } source) await PackWindows.ReleaseAsync(source, Arguments.Text(args, "closeWindows", false, 64), cancellationToken).ConfigureAwait(false);
                    var request = operation == "updates.install" ? Updates().RequestInstall(Arguments.Text(args, "preparedId", true, 100), true)
                        : operation == "updates.rollback" ? Updates().RequestRollback(true) : Updates().RequestRecovery(true);
                    var result = await host.InstallAsync(request, cancellationToken).ConfigureAwait(false);
                    handoffRequested = true;
                    return result;
                }
                case "host.reconnect":
                    Arguments.Only(args, "confirmed"); Confirm(args);
                    var reconnect = await host.ReconnectAsync(cancellationToken).ConfigureAwait(false);
                    handoffRequested = true;
                    return reconnect;
                default: return await business.InvokeAsync(operation, args, cancellationToken).ConfigureAwait(false);
            }
        }
        finally { admission.Release(); }
    }

    private ProfileConfigurationService Config() => configuration ?? throw new PestoException("config.unavailable", "Le service de configuration n’est pas raccordé.");
    private IPackProcessSource? PackSource() => (host as IPestoPackWindowsHost)?.PackProcesses;
    private UpdateService Updates() => updates ?? throw new PestoException("update.unavailable", "Le service de mise à jour n’est pas raccordé.");
    private SharedCoordinationAdministration Coordination() => coordination ?? throw new PestoException("coordination.unavailable", "Le service de coordination n’est pas raccordé.");
    private static JsonObject Cancelled() => new() { ["status"] = "cancelled" };
    private static string OptionalVersion(JsonElement args) => args.TryGetProperty("version", out _) ? Arguments.Text(args, "version", true, 80) : DateTimeOffset.UtcNow.ToString("yyyyMMdd-HHmmss");
    private static void Confirm(JsonElement args)
    {
        if (!Arguments.Flag(args, "confirmed")) throw new PestoException("confirmation.required", "Une confirmation explicite est requise.");
    }
    public void Dispose()
    {
        updates?.Dispose();
        if (business is IDisposable disposable) disposable.Dispose();
        admission.Dispose();
    }
}

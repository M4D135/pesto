using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>Observes the real dispatcher/backend path; never supplies synthetic success responses.</summary>
internal sealed class ConfigurationQualificationBackend(IPestoBackend inner) : IPestoBackend, IDisposable
{
    private readonly object gate = new();
    private readonly List<JsonObject> calls = [];
    private int forbidden;
    public int ForbiddenInvocations => Volatile.Read(ref forbidden);

    public int Count(string operation) { lock (gate) return calls.Count(item => Text(item, "operation") == operation); }
    public JsonObject? Last(string operation)
    {
        lock (gate) return calls.LastOrDefault(item => Text(item, "operation") == operation)?.DeepClone() as JsonObject;
    }
    public JsonArray Snapshot() { lock (gate) return new(calls.Select(item => item.DeepClone()).ToArray()); }

    public async Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        var entry = new JsonObject { ["operation"] = operation, ["completed"] = false,
            ["confirmed"] = args.TryGetProperty("confirmed", out var confirmation) && confirmation.ValueKind == JsonValueKind.True };
        // IDs are non-secret correlations. Keeping them proves preview -> confirmation -> preparation,
        // without copying any supplied configuration, credential or arbitrary argument into evidence.
        foreach (var key in new[] { "planId", "candidateId", "preparedId", "kind", "version" })
            if (args.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String) entry[key] = value.GetString();
        lock (gate) { entry["sequence"] = calls.Count + 1; calls.Add(entry); }
        try
        {
            if (operation is not ("session.info" or "settings.get" or "diagnostics.read" or "logs.list"
                or "configuration.status" or "configuration.settings" or "configuration.export"
                or "configuration.previewImport" or "configuration.previewSettings" or "configuration.applyImport"
                or "configuration.setDefault" or "coordination.status" or "updates.inspect" or "updates.prepare" or "updates.status"
                or "updates.windows"))
            {
                Interlocked.Increment(ref forbidden);
                throw new PestoException("qualification.configuration.forbidden-operation", "Cette opération sort du parcours local isolé.");
            }
            var result = await inner.InvokeAsync(operation, args, cancellationToken).ConfigureAwait(false);
            lock (gate)
            {
                var selected = new JsonObject();
                if (result is JsonObject json)
                    foreach (var key in new[] { "status", "file", "backup", "destination", "fingerprint", "version", "planId",
                        "candidateId", "preparedId", "distribution", "channel", "official", "pendingRecovery", "canRollback" })
                        if (json[key] is { } value) selected[key] = value.DeepClone();
                entry["result"] = selected;
                entry["completed"] = true;
            }
            return result;
        }
        catch (Exception error)
        {
            lock (gate)
            {
                entry["failureCode"] = error is PestoException pesto ? pesto.Code : error.GetType().Name;
                entry["completed"] = true;
            }
            throw;
        }
    }

    public void Dispose() { if (inner is IDisposable disposable) disposable.Dispose(); }
    private static string Text(JsonObject value, string key) => value[key]?.GetValue<string>() ?? "";
}

/// <summary>The only admitted host effects are the production file pickers, inside this owned temporary scope.</summary>
internal sealed class ConfigurationQualificationHost(NativeHostActions native, DemoQualificationScope scope) : IPestoHostActions
{
    private readonly object gate = new();
    private readonly List<JsonObject> calls = [];
    private int forbidden;
    public int ForbiddenInvocations => Volatile.Read(ref forbidden);
    public int Count(string action) { lock (gate) return calls.Count(item => item["action"]?.GetValue<string>() == action); }
    public JsonArray Snapshot() { lock (gate) return new(calls.Select(item => item.DeepClone()).ToArray()); }

    public void ObserveSelectionBeforeIo(string action, string path)
    {
        lock (gate)
        {
            var entry = calls.LastOrDefault(item => item["action"]?.GetValue<string>() == action && item["completed"]?.GetValue<bool>() == false)
                ?? throw new PestoException("qualification.configuration.selection", "Aucun dialogue du banc n’attend cette sélection.");
            entry["selectedPath"] = path;
            entry["normalizedSelectedPath"] = Path.GetFullPath(path);
            entry["selectionObservedBeforeIo"] = true;
        }
    }

    private async Task<string?> Observe(string action, bool returnedPath, Func<Task<string?>> run)
    {
        var entry = new JsonObject { ["action"] = action, ["completed"] = false };
        lock (gate) calls.Add(entry);
        try
        {
            var result = await run().ConfigureAwait(false);
            if (returnedPath && result is not null) scope.RequireOwned(result);
            lock (gate)
            {
                entry["completed"] = true; entry["cancelled"] = result is null;
                if (returnedPath && result is not null) entry["relativePath"] = Path.GetRelativePath(scope.Root, result).Replace('\\', '/');
            }
            return result;
        }
        catch (Exception error)
        {
            lock (gate) { entry["completed"] = true; entry["failureCode"] = error is PestoException pesto ? pesto.Code : error.GetType().Name; }
            throw;
        }
    }

    public Task<string?> ReadImportAsync(string kind, CancellationToken token) => kind == "configuration"
        ? Observe("import", false, () => native.ReadImportAsync(kind, token)) : Refused<string?>();
    public Task<string?> SaveExportAsync(string name, string text, CancellationToken token)
        => Observe("export", true, () => native.SaveExportAsync(name, text, token));
    public Task<string?> SelectPackSourceAsync(string kind, CancellationToken token)
        => Observe("source", true, () => native.SelectPackSourceAsync(kind, token));
    public Task<string?> SelectPackDestinationAsync(CancellationToken token)
        => Observe("destination", true, () => native.SelectPackDestinationAsync(token));
    public Task<object?> OpenDemoAsync(CancellationToken token) => Refused<object?>();
    public Task<object?> ReconnectAsync(CancellationToken token) => Refused<object?>();
    public Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken token) => Refused<object?>();
    private Task<T> Refused<T>()
    {
        Interlocked.Increment(ref forbidden);
        throw new PestoException("qualification.configuration.forbidden-host", "Aucun relais ni autre fenêtre n’est autorisé dans ce banc.");
    }
}

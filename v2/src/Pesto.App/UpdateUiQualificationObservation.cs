using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>Closed observer of real services. No successful result is synthesized by the bench.</summary>
internal sealed class UpdateUiQualificationBackend(IPestoBackend inner) : IPestoBackend, IDisposable
{
    private readonly object gate = new();
    private readonly List<JsonObject> calls = [];
    private int forbidden;
    internal int ForbiddenInvocations => Volatile.Read(ref forbidden);
    internal int Count(string operation) { lock (gate) return calls.Count(value => Text(value, "operation") == operation); }
    internal JsonObject? Last(string operation)
    {
        lock (gate) return calls.LastOrDefault(value => Text(value, "operation") == operation)?.DeepClone() as JsonObject;
    }
    internal JsonArray Snapshot() { lock (gate) return new(calls.Select(value => value.DeepClone()).ToArray()); }

    public async Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        var entry = new JsonObject { ["operation"] = operation, ["completed"] = false,
            ["confirmed"] = args.TryGetProperty("confirmed", out var confirmed) && confirmed.ValueKind == JsonValueKind.True };
        foreach (var key in new[] { "candidateId", "preparedId", "kind" })
            if (args.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String) entry[key] = value.GetString();
        lock (gate) { entry["sequence"] = calls.Count + 1; calls.Add(entry); }
        try
        {
            if (operation is not ("session.info" or "settings.get" or "diagnostics.read" or "logs.list"
                or "configuration.status" or "configuration.settings" or "coordination.status"
                or "updates.status" or "updates.windows" or "updates.inspect" or "updates.prepare" or "updates.install"))
            {
                Interlocked.Increment(ref forbidden);
                throw new PestoException("qualification.update-ui.forbidden-operation", "Cette action sort du parcours de mise à jour isolé.");
            }
            var result = await inner.InvokeAsync(operation, args, cancellationToken).ConfigureAwait(false);
            lock (gate)
            {
                var selected = new JsonObject();
                if (result is JsonObject json)
                    foreach (var key in new[] { "status", "candidateId", "preparedId", "transactionId", "version", "channel",
                        "distribution", "fingerprint", "source", "pendingRecovery", "canRollback" })
                        if (json[key] is { } value) selected[key] = value.DeepClone();
                entry["result"] = selected;
                entry["completed"] = true;
            }
            return result;
        }
        catch (Exception error)
        {
            lock (gate) { entry["failureCode"] = error is PestoException pesto ? pesto.Code : error.GetType().Name; entry["completed"] = true; }
            throw;
        }
    }

    public void Dispose() { if (inner is IDisposable disposable) disposable.Dispose(); }
    private static string Text(JsonObject value, string key) => value[key]?.GetValue<string>() ?? "";
}

/// <summary>Only a guarded native ZIP picker and the genuine host install relay are permitted.</summary>
internal sealed class UpdateUiQualificationHost(NativeHostActions native, DemoQualificationScope scope,
    UpdateUiQualificationRequest fixture, string selectedZip) : IPestoHostActions
{
    private readonly object gate = new();
    private readonly List<JsonObject> calls = [];
    private int forbidden;
    internal int ForbiddenInvocations => Volatile.Read(ref forbidden);
    internal int Count(string action) { lock (gate) return calls.Count(value => value["action"]?.GetValue<string>() == action); }
    internal JsonArray Snapshot() { lock (gate) return new(calls.Select(value => value.DeepClone()).ToArray()); }
    internal UpdateInstallRequest? InstallRequest { get; private set; }

    internal void ObserveSelectionBeforeIo(string action, string path)
    {
        lock (gate)
        {
            var entry = calls.LastOrDefault(value => value["action"]?.GetValue<string>() == "source" && value["completed"]?.GetValue<bool>() == false)
                ?? throw new PestoException("qualification.update-ui.selection", "Aucun sélecteur du banc n’attend cette source.");
            entry["selectedPath"] = path;
            entry["normalizedSelectedPath"] = Path.GetFullPath(path);
            entry["selectionObservedBeforeIo"] = true;
        }
        scope.RequireOwned(path);
        UpdateUiQualificationRequest.Require(action == "source" && UpdateUiQualificationRequest.SamePath(path, selectedZip), "selected-zip");
    }

    public async Task<string?> SelectPackSourceAsync(string kind, CancellationToken token)
    {
        if (kind != "zip") return await Refused<string?>();
        var entry = new JsonObject { ["action"] = "source", ["kind"] = kind, ["completed"] = false };
        lock (gate) calls.Add(entry);
        try
        {
            var result = await native.SelectPackSourceAsync(kind, token).ConfigureAwait(false);
            UpdateUiQualificationRequest.Require(result is not null && UpdateUiQualificationRequest.SamePath(result, selectedZip), "selected-zip");
            lock (gate) { entry["completed"] = true; entry["cancelled"] = false; }
            return result;
        }
        catch (Exception error)
        {
            lock (gate) { entry["completed"] = true; entry["failureCode"] = error is PestoException pesto ? pesto.Code : error.GetType().Name; }
            throw;
        }
    }

    public async Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken token)
    {
        fixture.RequireOwned(request.TransactionDirectory);
        fixture.RequireOwned(request.HelperExecutable);
        UpdateUiQualificationRequest.Require(request.Action == "install"
            && UpdateUiQualificationRequest.SamePath(UpdateTransaction.ReadInstallationDirectory(request.TransactionDirectory), fixture.Installation)
            && UpdateUiQualificationRequest.SamePath(request.HelperExecutable, Path.Combine(request.TransactionDirectory, "helper", "Pesto.exe"))
            && UpdatePackage.Hash(request.HelperExecutable) == fixture.SourceExecutableSha256, "install-request");
        UpdateTransaction.ValidateHelperInvocation(request.TransactionDirectory, request.HelperExecutable);
        lock (gate)
        {
            UpdateUiQualificationRequest.Require(InstallRequest is null, "single-host-request");
            InstallRequest = request;
            calls.Add(new JsonObject { ["action"] = "install", ["transactionId"] = request.TransactionId, ["completed"] = false });
        }
        var result = await native.InstallAsync(request, token).ConfigureAwait(false);
        lock (gate) calls.Last(value => value["action"]?.GetValue<string>() == "install")["completed"] = true;
        return result;
    }

    public Task<string?> ReadImportAsync(string kind, CancellationToken token) => Refused<string?>();
    public Task<string?> SaveExportAsync(string name, string text, CancellationToken token) => Refused<string?>();
    public Task<object?> OpenDemoAsync(CancellationToken token) => Refused<object?>();
    public Task<object?> ReconnectAsync(CancellationToken token) => Refused<object?>();
    private Task<T> Refused<T>()
    {
        Interlocked.Increment(ref forbidden);
        throw new PestoException("qualification.update-ui.forbidden-host", "Cette action hôte sort du parcours de mise à jour isolé.");
    }
}

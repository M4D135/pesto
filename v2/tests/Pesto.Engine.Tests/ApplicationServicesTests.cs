using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class ApplicationServicesTests
{
    [Test]
    public void LocalConfigurationCannotOpenOfflineJoinOrAccessSharedCoordination()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var host = new HostSpy();
        var configuration = new ProfileConfigurationService(root, "configuration-fixture", ConfigurationAccessMode.Live);
        using var wrapped = new ApplicationServicesBackend(PestoBackend.CreateConfigurationOnly(root, Harness.IsolatedGpRoot()),
            false, configuration, null, host, "/unused");
        foreach (var operation in new[] { "offlineJoin.open", "coordination.inspect", "coordination.prepare", "coordination.apply" })
            Check.Pesto(() => Harness.Call(wrapped, operation, new { source = @"\\example.invalid\never-read", confirmed = true }),
                "session.configurationOnly", "Refus avant arguments et hôte : " + operation);
        Check.Equal(0, host.Calls, "Aucune ouverture native réelle ni sélection de blob");
        Check.True(Harness.Bool(Harness.Call(wrapped, "coordination.status"), "configurationOnly"), "Le statut reste une lecture locale");
        _ = Harness.Call(wrapped, "configuration.settings");
        Check.True(Harness.Bool(Harness.Call(wrapped, "demo.open"), "opened"), "La démo séparée reste disponible");
        Check.Equal(1, host.Calls, "Seule la demande explicite de démo atteint l'hôte");
    }

    [Test]
    public async Task DemoRejectsMaintenanceBeforeAnyNativeActionOrFilesystemSelection()
    {
        var host = new HostSpy();
        using var wrapped = new ApplicationServicesBackend(Harness.Simulation(), true, null, null, host, @"\\never-contact\pack");
        foreach (var operation in new[] { "configuration.status", "configuration.previewImport", "configuration.setDefault", "references.preview",
            "references.apply", "updates.status", "updates.windows", "updates.inspect", "updates.prepare", "updates.install", "updates.rollback", "updates.recover", "host.reconnect", "demo.open",
            "coordination.status", "coordination.inspect", "coordination.prepare", "coordination.apply",
            "reservations.list", "reservations.inspect", "reservations.prepare", "reservations.execute",
                "join.precreated.preview", "receipts.prepareAcknowledgement", "receipts.acknowledge", "receipts.prepareRestart", "receipts.restart",
                "attributes.inspect", "attributes.prepare", "attributes.apply", "attributes.observe",
                "offlineJoin.open", "offlineJoin.list", "offlineJoin.import", "offlineJoin.prepare", "offlineJoin.apply", "offlineJoin.observe" })
        {
            try { await wrapped.InvokeAsync(operation, PestoJson.Element(new { source = @"\\never-contact\share" })); throw new TestFailureException("maintenance accepted: " + operation); }
            catch (PestoException error) { Check.Equal("demo.isolated", error.Code, "isolation before parsing paths"); }
        }
        Check.Equal(0, host.Calls, "no picker, process, export or network hook");
        Check.Equal("simulation", Harness.Str(Harness.Call(wrapped, "session.info"), "mode"), "demo remains usable");
    }

    [Test]
    public async Task DemoControlsNeverReachLiveBusinessAndOpeningDemoKeepsTheSession()
    {
        var host = new HostSpy(); var business = new BusinessSpy();
        using var wrapped = new ApplicationServicesBackend(business, false, null, null, host, "/unused");
        foreach (var operation in new[] { "demo.reset", "demo.scenario", "demo.restart", "demo.prepareMove" })
        {
            try { await wrapped.InvokeAsync(operation, PestoJson.Element(new { confirmed = true })); throw new TestFailureException("live demo action accepted"); }
            catch (PestoException error) { Check.Equal("demo.required", error.Code, "live boundary"); }
        }
        var opened = Harness.Call(wrapped, "demo.open");
        Check.True(Harness.Bool(opened, "opened"), "separate native window requested");
        Check.Equal(0, business.Calls, "no live business reset invoked");
        _ = Harness.Call(wrapped, "session.info");
        Check.Equal(1, business.Calls, "normal context still accepts requests");
    }

    [Test]
    public async Task MaintenanceWaitsForBusinessCompletionEvenOutsideTheBridge()
    {
        var host = new HostSpy(); var business = new BlockingBusiness();
        using var wrapped = new ApplicationServicesBackend(business, false, null, null, host, "/unused");
        var operation = wrapped.InvokeAsync("operation.execute", PestoJson.Element(new { }));
        await business.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var opening = wrapped.InvokeAsync("demo.open", PestoJson.Element(new { }));
        Check.False(opening.IsCompleted, "native action waits for business receipt");
        Check.Equal(0, host.Calls, "host not called while write owns gate");
        business.Release.SetResult(); await operation; await opening;
        Check.Equal(1, host.Calls, "host called after completion");
    }

    [Test]
    public async Task CancelledAdmissionNeverRunsLaterAndDoesNotPoisonTheGate()
    {
        var host = new HostSpy(); var business = new BlockingBusiness();
        using var wrapped = new ApplicationServicesBackend(business, false, null, null, host, "/unused");
        var operation = wrapped.InvokeAsync("operation.execute", PestoJson.Element(new { }));
        await business.Entered.Task;
        using var cancellation = new CancellationTokenSource();
        var pending = wrapped.InvokeAsync("demo.open", PestoJson.Element(new { }), cancellation.Token);
        cancellation.Cancel();
        try { await pending; throw new TestFailureException("cancel ignored"); } catch (OperationCanceledException) { }
        business.Release.SetResult(); await operation;
        Check.Equal(0, host.Calls, "cancelled open is never replayed");
        _ = Harness.Call(wrapped, "demo.open"); Check.Equal(1, host.Calls, "gate remains available");
    }

    [Test]
    public void ReconnectRequiresConfirmationAndBlocksEveryLaterBusinessRequest()
    {
        var host = new HostSpy(); var business = new BusinessSpy();
        using var wrapped = new ApplicationServicesBackend(business, false, null, null, host, "/unused");
        Check.Pesto(() => Harness.Call(wrapped, "host.reconnect", new { confirmed = false }), "confirmation.required", "explicit confirmation");
        Check.Pesto(() => Harness.Call(wrapped, "host.reconnect", new { confirmed = true, command = "arbitrary" }), "invalid_arguments", "closed direct API");
        Check.Equal(0, host.Calls, "nothing launched on refusals");
        Check.Equal("closing", Harness.Str(Harness.Call(wrapped, "host.reconnect", new { confirmed = true }), "status"), "handoff is not success");
        Check.Pesto(() => Harness.Call(wrapped, "operation.execute"), "host.closing", "no write can slip after shutdown requested");
        Check.Equal(0, business.Calls, "business untouched");
    }

    [Test]
    public async Task ClosedBridgeAcceptsDemoControlsAndRejectsForgedMaintenanceFields()
    {
        var host = new HostSpy();
        using var wrapped = new ApplicationServicesBackend(Harness.Simulation(), true, null, null, host, "/unused");
        var reset = await Harness.DispatchAsync(wrapped, "reset_demo", "demo.reset", new { confirmed = true });
        Check.Equal("result", reset["kind"]!.GetValue<string>(), "demo op declared in bridge");
        var inspect = await Harness.DispatchAsync(wrapped, "bad_update", "updates.inspect", new { source = @"\\server\pack" });
        Check.Equal("demo.isolated", Harness.ErrorCode(inspect), "bridge also enforces demo boundary");
        var forged = await Harness.DispatchAsync(wrapped, "bad_field", "configuration.applyImport", new { planId = "a", confirmed = true, profileRoot = "C:\\Windows" });
        Check.Equal("arguments.invalid", Harness.ErrorCode(forged), "profile paths never supplied by page");
        Check.Equal(0, host.Calls, "all native actions untouched");
    }

    [Test]
    public async Task PackWindowsAreReleasedBeforeUpdateTransactionAndHiddenWhenHostHasNoCapability()
    {
        var host = new PackWindowsHostSpy();
        using var wrapped = new ApplicationServicesBackend(Harness.Simulation(), false, null, null, host, @"C:\Pack");
        var described = Harness.Call(wrapped, "updates.windows");
        Check.Equal(1, Harness.Arr(described, "windows").Count, "host capability lists the window");
        var token = Harness.Str(described, "token");
        Check.True(token.Length == 64, "token is a SHA-256 hex digest");

        try { await wrapped.InvokeAsync("updates.rollback", PestoJson.Element(new { confirmed = true })); throw new TestFailureException("rollback accepted without close token"); }
        catch (PestoException error) { Check.Equal("update.windows", error.Code, "missing token refuses before transaction"); }
        Check.Equal(0, host.Source.CloseRequests, "no window close without token");
        Check.Equal(0, host.InstallCalls, "install not called");

        try { await wrapped.InvokeAsync("updates.rollback", PestoJson.Element(new { confirmed = true, closeWindows = token })); throw new TestFailureException("rollback accepted without update service"); }
        catch (PestoException error) { Check.Equal("update.unavailable", error.Code, "release precedes update service admission"); }
        Check.True(host.Source.Closed, "window was closed before the transaction");
        Check.Equal(1, host.Source.CloseRequests, "one close request");
        Check.Equal(0, host.InstallCalls, "install not called when update service is absent");

        var plainHost = new HostSpy();
        using var plain = new ApplicationServicesBackend(Harness.Simulation(), false, null, null, plainHost, @"C:\Pack");
        var empty = Harness.Call(plain, "updates.windows");
        Check.Equal(0, Harness.Arr(empty, "windows").Count, "host without capability reports no window");
        Check.Equal("", Harness.Str(empty, "token"), "host without capability reports empty token");
    }

    private sealed class PackWindowsHostSpy : IPestoHostActions, IPestoPackWindowsHost
    {
        public PackWindowsSourceSpy Source { get; } = new();
        public int Calls { get; private set; }
        public int InstallCalls { get; private set; }
        public IPackProcessSource PackProcesses => Source;
        public Task<string?> ReadImportAsync(string kind, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SaveExportAsync(string name, string text, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SelectPackSourceAsync(string kind, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SelectPackDestinationAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<object?> OpenDemoAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(new JsonObject { ["opened"] = true }); }
        public Task<object?> ReconnectAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(new JsonObject { ["status"] = "closing" }); }
        public Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken cancellationToken) { Calls++; InstallCalls++; return Task.FromResult<object?>(new JsonObject { ["status"] = "closing" }); }
    }

    private sealed class PackWindowsSourceSpy : IPackProcessSource
    {
        private readonly List<PackProcess> processes = [new PackProcess(42, 123456789, "Fenêtre Pesto", null)];
        public int CloseRequests { get; private set; }
        public bool Closed { get; private set; }
        public IReadOnlyList<PackProcess> List() => processes;
        public bool RequestClose(PackProcess process) { CloseRequests++; Closed = true; return true; }
        public bool HasExited(PackProcess process) => Closed;
    }

    private sealed class BusinessSpy : IPestoBackend
    {
        public int Calls;
        public Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
        { Calls++; return Task.FromResult<object?>(new JsonObject { ["mode"] = "live" }); }
    }
    private sealed class BlockingBusiness : IPestoBackend
    {
        public TaskCompletionSource Entered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Release { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
        { Entered.TrySetResult(); await Release.Task; return new JsonObject { ["status"] = "uncertain" }; }
    }
    private sealed class HostSpy : IPestoHostActions, IPestoOfflineJoinHost
    {
        public int Calls;
        public Task<string?> ReadImportAsync(string kind, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SaveExportAsync(string name, string text, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SelectPackSourceAsync(string kind, CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<string?> SelectPackDestinationAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
        public Task<object?> OpenDemoAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(new JsonObject { ["opened"] = true }); }
        public Task<object?> ReconnectAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(new JsonObject { ["status"] = "closing" }); }
        public Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(new JsonObject { ["status"] = "closing" }); }
        public Task<object?> OpenOfflineJoinAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<object?>(new JsonObject { ["opened"] = true }); }
        public Task<string?> SelectOfflineJoinBlobAsync(CancellationToken cancellationToken) { Calls++; return Task.FromResult<string?>(null); }
    }
}

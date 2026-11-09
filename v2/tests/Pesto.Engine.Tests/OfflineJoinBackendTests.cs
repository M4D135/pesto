using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class OfflineJoinBackendTests
{
    private sealed class Sentinel : IOfflineJoinPlatform, IPestoOfflineJoinHost
    {
        public int Calls, Disposals;
        private Exception Forbidden() { Calls++; return new TestFailureException("Forbidden platform or picker call"); }
        public string? UnavailableReason => throw Forbidden();
        public OfflineJoinLocalState ReadLocal() => throw Forbidden();
        public MutationManagedPolicy ReadManagedPolicy() => throw Forbidden();
        public byte[] ProtectBlob(byte[] plaintext) => throw Forbidden();
        public byte[] UnprotectBlob(byte[] protectedBytes) => throw Forbidden();
        public void SecureDirectory(string directory) => throw Forbidden();
        public void DeleteExact(string path, string expectedSha256) => throw Forbidden();
        public OfflineJoinNativeResult Apply(OfflineJoinCommand command) => throw Forbidden();
        public OfflineJoinObservation Observe(OfflineJoinBinding binding) => throw Forbidden();
        public void Audit(bool enabled, string json) => throw Forbidden();
        public Task<object?> OpenOfflineJoinAsync(CancellationToken cancellationToken) => throw Forbidden();
        public Task<string?> SelectOfflineJoinBlobAsync(CancellationToken cancellationToken) => throw Forbidden();
        public void Dispose() => Disposals++;
    }

    [Test]
    public void LocalBackendRefusesEveryUnrelatedApiBeforeArgsProvidersOrPaths()
    {
        var sentinel = new Sentinel();
        using var backend = new OfflineJoinBackend(new OfflineJoinService(@"\\unreachable\cfg.json", @"\\unreachable\GP", ConfigurationAccessMode.Live, sentinel), sentinel, "fixture");
        var hostile = PestoJson.Element(new { path = @"\\server\secret", source = "https://example.invalid" });
        foreach (var operation in new[] { "dashboard.read", "directory.search", "computer.inspect", "names.preview", "operation.execute", "attributes.apply",
            "configuration.status", "updates.inspect", "host.reconnect", "receipts.reconcile", "offlineJoin.open", "automation.execute", "demo.open" })
            Check.Pesto(() => backend.InvokeAsync(operation, hostile).GetAwaiter().GetResult(), "offlineJoin.local_only", "No fallback to ordinary network or mutation backend");
        Check.Equal(0, sentinel.Calls, "No platform or file selection invoked");
    }

    [Test]
    public void IsolatedServiceAlsoPreventsTheLocalBackendFromOpeningAFilePicker()
    {
        foreach (var mode in new[] { ConfigurationAccessMode.Demo, ConfigurationAccessMode.HealthCheck, ConfigurationAccessMode.BinaryRecovery })
        {
            var sentinel = new Sentinel();
            using var backend = new OfflineJoinBackend(new OfflineJoinService(@"\\unreachable\cfg.json", @"\\unreachable\GP", mode, sentinel), sentinel, "fixture");
            foreach (var (operation, args) in new (string, object)[]
            {
                ("session.info", new { }), ("offlineJoin.list", new { }),
                ("offlineJoin.import", new { objectGuid = "11111111-1111-1111-1111-111111111111", targetOU = "OU=Postes,DC=example,DC=local", confirmed = true }),
                ("offlineJoin.prepare", new { id = new string('a', 64) }),
                ("offlineJoin.apply", new { planId = "held", confirmationName = "PC", confirmed = true }),
                ("offlineJoin.observe", new { id = new string('a', 64) })
            })
                Check.Pesto(() => Harness.Call(backend, operation, args), "offlineJoin.isolated", "Isolation precedes all native services and dialogs");
            Check.Equal(0, sentinel.Calls, "No network, local reader or picker");
        }
    }
}

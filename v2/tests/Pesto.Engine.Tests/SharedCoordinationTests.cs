using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class SharedCoordinationTests
{
    private static readonly SharedCoordinationIdentity Identity = new("example.local", "PC-OLD", "PC-NEW", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
    private static string Root() => Path.Combine(Path.GetTempPath(), "pesto-coordination-tests-" + Guid.NewGuid().ToString("N"));
    private static string PreparedRoot()
    {
        var root = Root(); Directory.CreateDirectory(Path.Combine(root, "locks")); Directory.CreateDirectory(Path.Combine(root, "reservations"));
        File.WriteAllText(Path.Combine(root, "pesto-coordination.json"), "{\"Schema\":1,\"Domain\":\"EXAMPLE.LOCAL\",\"Purpose\":\"PestoCoordination\"}");
        return root;
    }
    private static SharedCoordinationIntent Intent(string root, string? receiptId = null, SharedCoordinationIdentity? identity = null, SharedCoordinationIntent? parent = null) =>
        SharedCoordinationProtocol.CreateIntent(new("example.local", root, true, new string('a', 64)), identity ?? Identity,
            receiptId ?? "receipt-" + Guid.NewGuid().ToString("N"), new DateTimeOffset(2026, 10, 26, 10, 0, 0, TimeSpan.Zero), parent)!;
    private static string Lease(string root, string key) => Path.Combine(root, "locks", key + ".json");

    /// <summary>Local fixture only; production uses Windows DELETE-by-handle, exercised on Windows by this same fixture.
    /// Linux tests prove protocol bytes/ownership/concurrency admission, not SMB handle semantics.</summary>
    private sealed class FixtureDeletion : ISharedCoordinationDeletion
    {
        public int Calls;
        public CoordinationDeletionResult DeleteExact(string path, string expectedSha256, int maximumBytes)
        {
            Calls++;
            if (OperatingSystem.IsWindows()) return new WindowsCoordinationDeletion().DeleteExact(path, expectedSha256, maximumBytes);
            if (!File.Exists(path)) return CoordinationDeletionResult.Missing;
            var bytes = SharedCoordinationProtocol.ReadBounded(path, maximumBytes);
            if (SharedCoordinationProtocol.Hash(bytes) != expectedSha256) return CoordinationDeletionResult.Changed;
            File.Delete(path);
            return CoordinationDeletionResult.Deleted;
        }
    }
    private sealed class ObservedAccess : ISharedCoordinationAccess
    {
        public int Calls;
        public bool Forbidden;
        public T Run<T>(Func<T> operation) { Calls++; if (Forbidden) throw new InvalidOperationException("unexpected external IO"); return operation(); }
    }
    private static string WriteConfiguration(string coordinationRoot)
    {
        var config = JsonNode.Parse(LiveTestConfig.Valid)!;
        config["POLICY"]!["CoordinationRoot"] = coordinationRoot;
        config["POLICY"]!["CoordinationRequired"] = true;
        return Path.Combine(LiveTestConfig.Write(config.ToJsonString()), "cfg.json");
    }

    [Test]
    public void KeysUseTheQuotedV1StringHashAndCanonicalGuidAndNames()
    {
        var keys = SharedCoordinationProtocol.Keys(Identity);
        Check.Equal("101434883091e2089cbb732bc8627c2700896005435f392e2dd2c2e8fd3dc806,c28974d98872d4f499d34f875875918e6f83a63eeda29722f2bce658371e58c7,f5d5e5b3a4c78231c86b1e63dc3902baeaad00d214529cca5d3f3e1f2788e3d0",
            string.Join(',', keys), "golden V1 SHA256 of compressed JSON strings, sorted and deduplicated");
        Check.Equal(string.Join(',', keys), string.Join(',', SharedCoordinationProtocol.Keys(Identity with
            { Domain = "EXAMPLE.LOCAL", Computer = "pc-old", NewName = "pc-new", ComputerGuid = "{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}" })), "case/format maps to the same machine and names");
        Check.Equal(1, SharedCoordinationProtocol.Keys(new("example.local", "PC-OLD", "pc-old", null)).Count, "same name locked once");
    }

    [Test]
    public void MutationAcquireNeverPreparesARegistryImplicitly()
    {
        var missing = Root(); var intent = Intent(missing);
        Check.Pesto(() => { SharedCoordinationProtocol.Acquire(intent, SharedCoordinationAccessMode.Live, new FixtureDeletion()); return null; }, "coordination.unprepared", "missing registry refuses");
        Check.False(Directory.Exists(missing), "no root, marker, share or locks created by acquisition");
        var root = PreparedRoot();
        File.WriteAllText(Path.Combine(root, "pesto-coordination.json"), "{\"Schema\":1,\"Domain\":\"another.local\",\"Purpose\":\"PestoCoordination\"}");
        Check.Pesto(() => { SharedCoordinationProtocol.Acquire(Intent(root), SharedCoordinationAccessMode.Live, new FixtureDeletion()); return null; }, "coordination.invalid", "another domain refuses");
        Check.Equal(0, Directory.GetFiles(Path.Combine(root, "locks")).Length, "no lease before a valid domain marker");
    }

    [Test]
    public void AcquireCreatesExclusiveV1LeasesAndForeignLocksNeverExpire()
    {
        var root = PreparedRoot(); var intent = Intent(root); var deletion = new FixtureDeletion();
        SharedCoordinationProtocol.Acquire(intent, SharedCoordinationAccessMode.Live, deletion);
        foreach (var entry in intent.Entries)
        {
            var bytes = File.ReadAllBytes(Lease(root, entry.Key));
            Check.Equal(entry.Sha256, SharedCoordinationProtocol.Hash(bytes), "exact durable intent bytes created");
            using var document = JsonDocument.Parse(bytes);
            Check.Equal(intent.Owner, document.RootElement.GetProperty("OperationId").GetString(), "V1 owner field");
            Check.Equal("Prepared", document.RootElement.GetProperty("State").GetString(), "V1 state");
            File.SetLastWriteTimeUtc(Lease(root, entry.Key), new DateTime(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc));
        }
        Check.Pesto(() => { SharedCoordinationProtocol.Acquire(Intent(root), SharedCoordinationAccessMode.Live, deletion); return null; }, "coordination.held", "age never releases a mutation lease");
        Check.Equal(3, Directory.GetFiles(Path.Combine(root, "locks")).Length, "foreign old locks retained");
        SharedCoordinationProtocol.ReleaseOwned(intent, SharedCoordinationAccessMode.Live, deletion);
        Check.Equal(0, Directory.GetFiles(Path.Combine(root, "locks")).Length, "terminal owner can remove its exact leases");
    }

    [Test]
    public void AConflictRollsBackOnlyNewFilesFromThatAcquisition()
    {
        var root = PreparedRoot(); var intent = Intent(root); var last = intent.Entries[^1];
        const string foreign = "{\"Schema\":1,\"OperationId\":\"other\",\"State\":\"Prepared\"}";
        File.WriteAllText(Lease(root, last.Key), foreign);
        Check.Pesto(() => { SharedCoordinationProtocol.Acquire(intent, SharedCoordinationAccessMode.Live, new FixtureDeletion()); return null; }, "coordination.held", "last-key conflict refuses whole mutation");
        Check.Equal(1, Directory.GetFiles(Path.Combine(root, "locks")).Length, "partial own creation cleaned, not the conflicting file");
        Check.Equal(foreign, File.ReadAllText(Lease(root, last.Key)), "foreign bytes preserved, even if malformed");
    }

    [Test]
    public void TwoSimultaneousOperatorsCannotBothOwnTheSameTarget()
    {
        var root = PreparedRoot(); var winners = 0; var refused = 0;
        Parallel.Invoke(Attempt, Attempt);
        Check.Equal(1, winners, "exclusive creation admits exactly one operation");
        Check.Equal(1, refused, "second operation refused, never overwrites");
        Check.Equal(3, Directory.GetFiles(Path.Combine(root, "locks")).Length, "winning ownership complete");
        void Attempt()
        {
            try { SharedCoordinationProtocol.Acquire(Intent(root), SharedCoordinationAccessMode.Live, new FixtureDeletion()); Interlocked.Increment(ref winners); }
            catch (PestoException error) when (error.Code == "coordination.held") { Interlocked.Increment(ref refused); }
        }
    }

    [Test]
    public void ChangedBytesWithTheSameOwnerAreNeverDeletedOrAccepted()
    {
        var root = PreparedRoot(); var intent = Intent(root);
        SharedCoordinationProtocol.Acquire(intent, SharedCoordinationAccessMode.Live, new FixtureDeletion());
        var path = Lease(root, intent.Entries[0].Key); var changed = File.ReadAllText(path) + " "; File.WriteAllText(path, changed);
        Check.Pesto(() => { SharedCoordinationProtocol.Verify(intent, SharedCoordinationAccessMode.Live); return null; }, "coordination.changed", "owner equality cannot substitute for exact bytes");
        Check.Pesto(() => { SharedCoordinationProtocol.ReleaseOwned(intent, SharedCoordinationAccessMode.Live, new FixtureDeletion()); return null; }, "coordination.changed", "concurrent bytes preserved on cleanup");
        Check.Equal(changed, File.ReadAllText(path), "no overwrite and no pathname-only deletion");
    }

    [Test]
    public void AContinuationBorrowsButNeverTransfersOrReleasesParentLocks()
    {
        var root = PreparedRoot(); var parent = Intent(root); var deletion = new FixtureDeletion();
        SharedCoordinationProtocol.Acquire(parent, SharedCoordinationAccessMode.Live, deletion);
        var original = parent.Entries.ToDictionary(e => e.Key, e => File.ReadAllText(Lease(root, e.Key)));
        var child = Intent(root, identity: Identity with { Computer = Identity.NewName!, NewName = null }, parent: parent);
        Check.True(child.Entries.All(e => e.Inherited && e.Owner == parent.Owner), "borrowed ownership never transferred to child");
        SharedCoordinationProtocol.Acquire(child, SharedCoordinationAccessMode.Live, deletion);
        SharedCoordinationProtocol.ReleaseOwned(child, SharedCoordinationAccessMode.Live, deletion);
        foreach (var pair in original) Check.Equal(pair.Value, File.ReadAllText(Lease(root, pair.Key)), "failed child keeps parent's complete target scope");
        SharedCoordinationProtocol.ReleaseOwned(parent, SharedCoordinationAccessMode.Live, deletion);
        Check.Equal(0, Directory.GetFiles(Path.Combine(root, "locks")).Length, "parent cleanup requires separate durable terminal/resolved authority");
        Check.Pesto(() => { SharedCoordinationProtocol.Acquire(child, SharedCoordinationAccessMode.Live, deletion); return null; }, "coordination.changed", "missing inherited ownership is not silently recreated");
    }

    [Test]
    public void ReservationRetriesPreserveEveryAncestorOwnerWhenAGuidBecomesKnown()
    {
        var root = PreparedRoot(); var deletion = new FixtureDeletion();
        var first = Intent(root, identity: Identity with { ComputerGuid = null });
        SharedCoordinationProtocol.Acquire(first, SharedCoordinationAccessMode.Live, deletion);
        var second = Intent(root, parent: first);
        SharedCoordinationProtocol.Acquire(second, SharedCoordinationAccessMode.Live, deletion);
        Check.Equal(2, second.Entries.Count(e => e.Inherited), "initial name locks keep original owner");
        Check.Equal(1, second.Entries.Count(e => !e.Inherited), "known GUID gets a new exclusive lock");
        var third = Intent(root, parent: second);
        using var json = JsonDocument.Parse(third.ToJson().ToJsonString());
        third = SharedCoordinationProtocol.ReadIntent(json.RootElement);
        Check.Equal(2, third.BorrowedOwners.Count, "both ancestors are preserved, never transferred to latest child");
        SharedCoordinationProtocol.Acquire(third, SharedCoordinationAccessMode.Live, deletion);
        SharedCoordinationProtocol.ReleaseOwned(third, SharedCoordinationAccessMode.Live, deletion);
        Check.Equal(3, Directory.GetFiles(Path.Combine(root, "locks")).Length, "child failure cannot release any ancestor");
        SharedCoordinationProtocol.ReleaseOwned(second, SharedCoordinationAccessMode.Live, deletion);
        Check.Equal(2, Directory.GetFiles(Path.Combine(root, "locks")).Length, "separate resolved proof cleans only second owner's GUID lock");
        SharedCoordinationProtocol.ReleaseOwned(first, SharedCoordinationAccessMode.Live, deletion);
        Check.Equal(0, Directory.GetFiles(Path.Combine(root, "locks")).Length, "initial owner's proof cleans both names");
    }

    [Test]
    public void ConfigurationStampIncludesTheActualUtf8BomBytes()
    {
        var raw = Encoding.UTF8.GetBytes(LiveTestConfig.Valid);
        var bom = new byte[] { 0xef, 0xbb, 0xbf }.Concat(raw).ToArray();
        var first = SharedCoordinationConfiguration.ReadBytes(raw);
        var second = SharedCoordinationConfiguration.ReadBytes(bom);
        Check.Equal(first.Domain, second.Domain, "UTF8 BOM configuration remains valid");
        Check.Equal(SharedCoordinationProtocol.Hash(bom), second.ConfigSha256, "fingerprint binds exact bytes used by the mutation plan");
        Check.True(first.ConfigSha256 != second.ConfigSha256, "BOM cannot be silently omitted from concurrency evidence");
    }

    [Test]
    public void TerminalDecisionsDoNotTurnUnknownEffectsIntoCleanupPermission()
    {
        bool Allowed(string json) { using var doc = JsonDocument.Parse(json); return SharedCoordinationProtocol.IsCompletedReceipt(doc.RootElement); }
        Check.True(Allowed("{\"Phase\":\"Verified\"}"), "durable verified phase admitted");
        Check.True(Allowed("{\"Phase\":\"Failed\"}"), "durable proven refusal admitted");
        foreach (var phase in new[] { "Running", "Uncertain", "Partial", "MoveReady", "Protection", "PendingRestart" })
            Check.False(Allowed("{\"Phase\":\"" + phase + "\",\"Code\":20}"), "V2 pending/uncertain lacks V1 effect evidence: " + phase);
        const string optional = "{\"Phase\":\"PendingRestart\",\"ResultCode\":20,\"Protection\":\"Restored\",\"Entra\":\"NotRequested\",\"Rename\":\"Confirmed\",\"Move\":\"NotRequested\"}";
        Check.True(Allowed(optional), "exact V1 optional postcheck fields recognized");
        Check.False(Allowed(optional.Replace("Restored", "Uncertain", StringComparison.Ordinal)), "protection uncertainty keeps lease");
        Check.False(Allowed(optional.Replace("NotRequested\",\"Rename", "Requested\",\"Rename", StringComparison.Ordinal)), "Entra uncertainty keeps lease");
        Check.False(Allowed(optional.Replace("\"ResultCode\":20", "\"ResultCode\":\"20\"", StringComparison.Ordinal)), "untyped result code not accepted");
    }

    [Test]
    public void IsolationRefusesBeforePathInspectionOrAnExternalIdentityScope()
    {
        var intent = Intent(@"\\never-access.example.invalid\share\coordination");
        foreach (var mode in new[] { SharedCoordinationAccessMode.Demo, SharedCoordinationAccessMode.HealthCheck, SharedCoordinationAccessMode.BinaryRecovery })
        {
            var deletion = new FixtureDeletion();
            Check.Pesto(() => { SharedCoordinationProtocol.Acquire(intent, mode, deletion); return null; }, "coordination.isolated", "acquisition isolated");
            Check.Pesto(() => { SharedCoordinationProtocol.Verify(intent, mode); return null; }, "coordination.isolated", "verification isolated");
            Check.Pesto(() => { SharedCoordinationProtocol.ReleaseOwned(intent, mode, deletion); return null; }, "coordination.isolated", "cleanup isolated");
            Check.Equal(0, deletion.Calls, "no deletion transport reached");
            var access = new ObservedAccess { Forbidden = true };
            var admin = new SharedCoordinationAdministration(@"\\never-access.example.invalid\profile\cfg.json", mode, access);
            Check.Pesto(() => admin.Status(), "coordination.isolated", "even status isolated before local config lookup");
            Check.Pesto(() => admin.Inspect(), "coordination.isolated", "inspect isolated");
            Check.Pesto(() => admin.Prepare(), "coordination.isolated", "prepare isolated");
            Check.Pesto(() => admin.Apply("unknown", true), "coordination.isolated", "apply isolated");
            Check.Equal(0, access.Calls, "no identity or external IO scope reached");
        }
    }

    [Test]
    public void StatusDoesNotProbeAndRegistryPreparationIsExplicitAndSingleUse()
    {
        var parent = Root(); Directory.CreateDirectory(parent); var root = Path.Combine(parent, "approved-registry");
        var config = WriteConfiguration(root); var access = new ObservedAccess { Forbidden = true };
        var admin = new SharedCoordinationAdministration(config, SharedCoordinationAccessMode.Live, access);
        var status = admin.Status(); Check.True(Harness.Bool(status, "configured"), "configured from local policy only");
        Check.Equal(0, access.Calls, "startup status cannot contact share");
        access.Forbidden = false;
        var preview = admin.Prepare(); var id = Harness.Str(preview, "planId");
        Check.False(Directory.Exists(root), "preparation is only a plan");
        Check.Pesto(() => admin.Apply(id, false), "coordination.confirmation", "no creation without explicit confirmation");
        var applied = admin.Apply(id, true);
        Check.Equal("prepared", Harness.Str(applied, "status"), "prepared after reread");
        Check.True(Harness.Bool(applied, "prepared"), "marker and both directories observed");
        Check.Equal(0, Directory.GetFiles(Path.Combine(root, "locks")).Length, "no operation lease invented");
        Check.True(Directory.Exists(Path.Combine(root, "reservations")), "temporary-name directory only created explicitly here");
        Check.Pesto(() => admin.Apply(id, true), "coordination.plan", "single use");
        var repeated = admin.Prepare();
        Check.Equal("unchanged", Harness.Str(admin.Apply(Harness.Str(repeated, "planId"), true), "status"), "ready registry not replaced");
    }

    [Test]
    public void PreparationBindsConfigurationAndRegistryStateWithoutOverwritingConcurrentWork()
    {
        var parent = Root(); Directory.CreateDirectory(parent); var root = Path.Combine(parent, "registry"); var config = WriteConfiguration(root);
        var admin = new SharedCoordinationAdministration(config, SharedCoordinationAccessMode.Live);
        var first = admin.Prepare(); var before = File.ReadAllText(config);
        File.WriteAllText(config, before.Replace("111301", "222222", StringComparison.Ordinal));
        Check.Pesto(() => admin.Apply(Harness.Str(first, "planId"), true), "coordination.config_changed", "stale config plan refused");
        Check.False(Directory.Exists(root), "no creation after config change");
        var second = admin.Prepare(); Directory.CreateDirectory(root); File.WriteAllText(Path.Combine(root, "operator.txt"), "concurrent");
        Check.Pesto(() => admin.Apply(Harness.Str(second, "planId"), true), "coordination.changed", "changed root refused");
        Check.Equal("concurrent", File.ReadAllText(Path.Combine(root, "operator.txt")), "concurrent file preserved");
        Check.False(File.Exists(Path.Combine(root, "pesto-coordination.json")), "no marker after stale preview");
        var deep = Path.Combine(parent, "missing-parent", "registry");
        var missingParent = new SharedCoordinationAdministration(WriteConfiguration(deep), SharedCoordinationAccessMode.Live);
        Check.Pesto(() => missingParent.Prepare(), "coordination.parent", "no implicit parent/share creation");
        Check.False(Directory.Exists(Path.GetDirectoryName(deep)), "missing parent remains missing");
    }

    [Test]
    public void LinkedOrMalformedRegistryEvidenceIsNeverFollowed()
    {
        var root = PreparedRoot();
        File.WriteAllText(Path.Combine(root, "pesto-coordination.json"), "{\"Schema\":1,\"Domain\":\"example.local\",\"Purpose\":\"PestoCoordination\",\"domain\":\"other.local\"}");
        Check.Pesto(() => SharedCoordinationProtocol.InspectRegistry(root, "example.local"), "coordination.invalid", "duplicate/case extra field rejected");
        if (!OperatingSystem.IsWindows())
        {
            var target = PreparedRoot(); var link = Root(); Directory.CreateSymbolicLink(link, target);
            Check.Pesto(() => SharedCoordinationProtocol.InspectRegistry(link, "example.local"), "coordination.invalid", "no link traversal");
        }
        var intent = Intent(PreparedRoot()); var node = intent.ToJson(); node["Entries"]![0]!["Sha256"] = new string('0', 64);
        using var tampered = JsonDocument.Parse(node.ToJsonString());
        Check.Pesto(() => SharedCoordinationProtocol.ReadIntent(tampered.RootElement), "coordination.invalid", "local intent byte fingerprint validated before IO");
    }
}

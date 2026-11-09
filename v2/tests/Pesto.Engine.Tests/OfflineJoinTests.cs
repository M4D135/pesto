using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class OfflineJoinTests
{
    private const string Computer = "P111301PAINF009", Machine = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private const string AdGuid = "11111111-2222-3333-4444-555555555555", Domain = "example.local";
    private const string Ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";
    private static string NewRoot() => Path.Combine(Path.GetTempPath(), "pesto-odj-" + Guid.NewGuid().ToString("N"));
    private static bool Flag(JsonNode value, string key) => value[key]!.GetValue<bool>();

    private sealed class World : IDisposable
    {
        public readonly string Root = NewRoot();
        public readonly FixedClock Clock = new();
        public readonly Native Platform;
        public readonly OfflineJoinService Service;
        public readonly string Config, Gp, Source;
        public World()
        {
            Directory.CreateDirectory(Root); Config = Path.Combine(Root, "cfg.json"); Gp = Path.Combine(Root, "GP"); Source = Path.Combine(Root, "selected-secret.txt");
            var configuration = JsonNode.Parse(LiveTestConfig.Valid)!.AsObject(); configuration["POLICY"]!["AllowOfflineJoin"] = true;
            File.WriteAllText(Config, configuration.ToJsonString()); File.WriteAllText(Source, "OPAQUE-ODJ-SECRET-not-for-web-or-audit", new UTF8Encoding(false));
            Platform = new(this); Service = new(Config, Gp, ConfigurationAccessMode.Live, Platform, Clock);
        }
        public OfflineJoinStore Store => new(Gp, ConfigurationAccessMode.Live, clock: Clock);
        public string Import() => Harness.Str(Service.Import(Source, AdGuid, Ou, true)["item"]!, "id");
        public JsonObject Plan(string id) => Service.Prepare(id);
        public JsonObject Apply(JsonObject plan) => Service.Apply(Harness.Str(plan, "planId"), Computer, true);
        public void SetPolicy(string name, JsonNode? value)
        {
            var configuration = JsonNode.Parse(File.ReadAllText(Config))!; configuration["POLICY"]![name] = value; File.WriteAllText(Config, configuration.ToJsonString());
        }
        public void JoinAfterBoot()
        {
            Clock.Advance(TimeSpan.FromMinutes(2)); Platform.Local = Platform.Local with
            { PartOfDomain = true, Domain = Domain, DomainRole = 1, BootUtc = Clock.GetUtcNow().AddMinutes(-1) };
        }
        public void Dispose() => Service.Dispose();
    }

    private sealed class Native(World world) : IOfflineJoinPlatform
    {
        public OfflineJoinLocalState Local = new(Computer, Computer, Computer, Machine, "WORKGROUP", false, 0,
            world.Clock.GetUtcNow().AddHours(-2), true, null);
        public MutationManagedPolicy Managed = new();
        public int Calls, ApplyCalls, ObserveCalls, DeleteCalls, Audits, Disposes;
        public bool ThrowApply, FailCleanup;
        public OfflineJoinNativeResult Result = new(true, 0, false, "fixture native accepted");
        public Action<OfflineJoinCommand>? DuringApply;
        public Action<string>? DuringSecure;
        public Func<OfflineJoinObservation, OfflineJoinObservation>? AlterObservation;
        public string? UnavailableReason { get { Calls++; return null; } }
        public OfflineJoinLocalState ReadLocal() { Calls++; return Local; }
        public MutationManagedPolicy ReadManagedPolicy() { Calls++; return Managed; }
        public byte[] ProtectBlob(byte[] value) { Calls++; return value.Select(b => (byte)(b ^ 0xa5)).ToArray(); }
        public byte[] UnprotectBlob(byte[] value) { Calls++; return value.Select(b => (byte)(b ^ 0xa5)).ToArray(); }
        public void SecureDirectory(string directory) { Calls++; DuringSecure?.Invoke(directory); }
        public void DeleteExact(string path, string expectedSha256)
        {
            Calls++; DeleteCalls++; if (FailCleanup) throw new IOException("fixture cleanup refused");
            if (OfflineJoinRules.Hash(File.ReadAllBytes(path)) != expectedSha256) throw new IOException("changed"); File.Delete(path);
        }
        public OfflineJoinNativeResult Apply(OfflineJoinCommand command)
        {
            Calls++; ApplyCalls++;
            var head = world.Store.Read(command.Binding.Id)!;
            Check.Equal("Requested", head.Event.State, "actual immutable intent is durable before native apply");
            Check.Equal(command.IntentSha256, head.Sha256, "native command bound to exact durable head");
            Check.True(head.Event.WorkerMayRun, "possible dispatch declared before native effect");
            var receiptPath = world.Store.ReceiptPath(command.ReceiptId); var bytes = File.ReadAllBytes(receiptPath);
            Check.Equal(head.Event.SourceReceiptSha256, OfflineJoinRules.Hash(bytes), "exact mirror receipt durable before native effect");
            Check.True(OfflineJoinReceipt.ValidateStored(world.Gp, bytes), "real integrated receipt format references its immutable event");
            Check.Equal(command.Binding.Id, OfflineJoinRules.Hash(File.ReadAllBytes(world.Store.PlainPath(command.Binding.Id))), "only the confirmed opaque bytes enter the fixed native call");
            DuringApply?.Invoke(command);
            if (ThrowApply) throw new IOException("fixture lost native reply"); return Result;
        }
        public OfflineJoinObservation Observe(OfflineJoinBinding binding)
        {
            Calls++; ObserveCalls++;
            var observation = new OfflineJoinObservation(Local, binding.ExpectedAdGuid, binding.Computer, binding.TargetOu, binding.Domain,
                false, true, world.Clock.GetUtcNow(), null);
            return AlterObservation?.Invoke(observation) ?? observation;
        }
        public void Audit(bool enabled, string json)
        {
            Calls++; if (!enabled) return; Audits++;
            using var parsed = JsonDocument.Parse(json); var id = parsed.RootElement.GetProperty("ReceiptId").GetString()!;
            Check.Equal(json, File.ReadAllText(world.Store.ReceiptPath(id)), "audit only after exact receipt is durable");
            Check.False(json.Contains("OPAQUE-ODJ-SECRET", StringComparison.Ordinal), "audit never receives blob bytes");
        }
        public void Dispose() => Disposes++;
    }

    [Test]
    public void ConstructorsAndAllIsolatedEntryPointsLeaveDiskAndProvidersUntouched()
    {
        foreach (var mode in new[] { ConfigurationAccessMode.Demo, ConfigurationAccessMode.HealthCheck, ConfigurationAccessMode.BinaryRecovery })
        {
            using var world = new World(); var target = NewRoot(); var bytes = File.ReadAllBytes(world.Config);
            using var service = new OfflineJoinService(world.Config, target, mode, world.Platform, world.Clock);
            Check.Equal(0, world.Platform.Calls, "constructor does not read environment or configuration");
            foreach (var action in new Func<object?>[] { service.List, () => service.Import(world.Source, AdGuid, Ou, true),
                () => service.Prepare(new string('a', 64)), () => service.Apply("plan", Computer, true), () => service.Observe(new string('a', 64)) })
                Check.Pesto(action, "offlineJoin.isolated", "direct API isolation precedes all IO");
            Check.Equal(0, world.Platform.Calls, "isolated service never probes native provider");
            Check.False(Directory.Exists(target), "isolated profile/store not created"); Check.True(bytes.SequenceEqual(File.ReadAllBytes(world.Config)), "real configuration untouched");
            using var native = new WindowsOfflineJoinPlatform(world.Config, target, mode);
            Check.Pesto(() => native.ReadLocal(), "offlineJoin.isolated", "native read is also isolated before OS check");
            Check.Pesto(() => native.ProtectBlob([1]), "offlineJoin.isolated", "direct secret import isolated");
        }
    }

    [Test]
    public void ImportStoresOnlyProtectedBytesAndDeclaredPublicIdentity()
    {
        using var world = new World(); var original = File.ReadAllBytes(world.Source); var id = world.Import();
        Check.Equal(OfflineJoinRules.Hash(original), id, "blob fingerprint is stable across sessions");
        var item = world.Service.List()["items"]![0]!;
        Check.Equal(Computer, Harness.Str(item, "computer"), "current local name chosen, never generated");
        Check.True(Flag(item, "identityDeclared"), "AD identity is declared, not claimed as observed");
        Check.True(Flag(item, "canPrepare"), "valid imported blob has explicit preparation path");
        Check.Equal(0, world.Platform.ApplyCalls, "import does not apply"); Check.Equal(0, world.Platform.ObserveCalls, "list/import never read AD");
        Check.True(original.SequenceEqual(File.ReadAllBytes(world.Source)), "selected source is retained intact");
        Check.False(original.SequenceEqual(File.ReadAllBytes(world.Store.ProtectedPath(id))), "only protected secret stored");
        var publicJson = world.Service.List().ToJsonString();
        Check.False(publicJson.Contains(world.Source, StringComparison.Ordinal) || publicJson.Contains("OPAQUE-ODJ-SECRET", StringComparison.Ordinal), "WebView receives no selected path or secret");
        Check.False(string.Concat(Directory.EnumerateFiles(world.Gp, "*.json", SearchOption.AllDirectories).Select(File.ReadAllText)).Contains("OPAQUE-ODJ-SECRET", StringComparison.Ordinal), "journal contains no secret");
        Check.Pesto(() => world.Service.Import(world.Source, AdGuid, Ou, true), "offlineJoin.duplicate", "duplicate import never issues a new identity");
    }

    [Test]
    public void ConfirmationConfigurationAndExpiryAreCheckedBeforeConsumptionOrNativeCall()
    {
        using var world = new World(); var id = world.Import(); var plan = world.Plan(id);
        Check.Pesto(() => world.Service.Apply(Harness.Str(plan, "planId"), Computer, false), "confirmation.required", "confirmation required");
        Check.Pesto(() => world.Service.Apply(Harness.Str(plan, "planId"), "OTHER", true), "confirmation.name", "exact local name required");
        world.Clock.Advance(TimeSpan.FromMinutes(6));
        Check.Pesto(() => world.Apply(plan), "offlineJoin.plan", "expired plan refuses");
        plan = world.Plan(id); world.SetPolicy("AuditEventLogEnabled", true);
        Check.Pesto(() => world.Apply(plan), "offlineJoin.changed", "configuration changed after confirmation snapshot");
        Check.Equal("Imported", world.Store.Read(id)!.Event.State, "no intent consumed for preflight refusal");
        Check.Equal(0, world.Platform.ApplyCalls, "no native application");
    }

    [Test]
    public void DurableRealReceiptPrecedesSingleNativeCallAndPendingRestartIsNotSuccess()
    {
        using var world = new World(); world.SetPolicy("AuditEventLogEnabled", true);
        var id = world.Import(); var plan = world.Plan(id); var result = world.Apply(plan);
        Check.Equal("PendingRestart", Harness.Str(result["item"]!, "state"), "native code zero only accepts request");
        Check.Equal("pendingRestart", Harness.Str(result["receipt"]!, "status"), "no premature success");
        Check.True(Flag(result["item"]!, "restartRequired"), "explicit reboot required");
        Check.False(Flag(result["item"]!, "replayAllowed"), "repeat forbidden");
        Check.Equal(1, world.Platform.ApplyCalls, "one native call"); Check.Equal(2, world.Platform.Audits, "audit follows requested and terminal durable mirrors");
        Check.False(File.Exists(world.Store.PlainPath(id)) || File.Exists(world.Store.ProtectedPath(id)), "consumed temporary secret removed after proven worker end");
        Check.Pesto(() => world.Apply(plan), "offlineJoin.plan", "same plan consumed");
        Check.Pesto(() => world.Service.Prepare(id), "offlineJoin.consumed", "same blob cannot be planned again");
        var history = GpHistory.Read(world.Gp); Check.Equal(0, history.InvalidCount, "actual generated format accepted by history");
        Check.Equal("pendingRestart", history.Entries.Single().Receipt.Status, "history preserves pending state");
        Check.NotNull(OfflineJoinStore.RefusalForMutation(world.Gp, Computer), "ODJ pending remains a mutation barrier");
    }

    [Test]
    public void LostReplyNeverReplaysAndRetainsPossibleWorkerSecret()
    {
        using var world = new World(); var id = world.Import(); var plan = world.Plan(id); world.Platform.ThrowApply = true;
        Check.Pesto(() => world.Apply(plan), "offlineJoin.uncertain", "lost response stays uncertain");
        var head = world.Store.Read(id)!; Check.Equal("Uncertain", head.Event.State, "durable uncertain state");
        Check.True(head.Event.WorkerMayRun, "possible native effect retained");
        Check.True(File.Exists(world.Store.PlainPath(id)) && File.Exists(world.Store.ProtectedPath(id)), "no deletion while possible worker may read secret");
        using var reopened = new OfflineJoinService(world.Config, world.Gp, ConfigurationAccessMode.Live, world.Platform, world.Clock);
        Check.Pesto(() => reopened.Prepare(id), "offlineJoin.consumed", "fresh process still cannot replay");
        Check.Equal(1, world.Platform.ApplyCalls, "no hidden second call");
    }

    [Test]
    public void NonzeroNativeCodeAndCleanupFailureCannotBecomeFalseSuccess()
    {
        using var world = new World(); var id = world.Import(); world.Platform.Result = new(true, 5, false, "native refusal");
        world.Platform.FailCleanup = true;
        var result = world.Apply(world.Plan(id));
        Check.Equal("Uncertain", Harness.Str(result["item"]!, "state"), "postdispatch nonzero remains uncertain");
        Check.Equal(5, result["item"]!["nativeCode"]!.GetValue<int>(), "actual native code retained");
        Check.Contains("nettoyage", Harness.Str(result, "message"), "cleanup failure disclosed without rewriting business outcome");
        Check.Equal("uncertain", Harness.Str(result["receipt"]!, "status"), "never success or no-effect failed");
    }

    [Test]
    public void MissingDurableMirrorPreventsNativeCallAndConcurrentBytesArePreserved()
    {
        using var world = new World(); var id = world.Import();
        world.Platform.DuringSecure = directory =>
        {
            if (Path.GetFileName(directory) != "receipts") return;
            var head = world.Store.Read(id)!; File.WriteAllText(world.Store.ReceiptPath(head.Event.ReceiptId!), "concurrent receipt bytes");
        };
        Check.Pesto(() => world.Apply(world.Plan(id)), "offlineJoin.uncertain", "mirror cannot be installed without replacing a file");
        var current = world.Store.Read(id)!;
        Check.Equal(0, world.Platform.ApplyCalls, "no command before durable mirror");
        Check.Equal("concurrent receipt bytes", File.ReadAllText(world.Store.ReceiptPath(current.Event.ReceiptId!)), "concurrent receipt untouched");
        Check.NotNull(OfflineJoinStore.RefusalForMutation(world.Gp, Computer), "consumed intent blocks even with invalid mirror");
    }

    [Test]
    public void ConcurrentMirrorChangeAfterNativeCallIsNeverOverwritten()
    {
        using var world = new World(); var id = world.Import(); string? changed = null;
        world.Platform.DuringApply = command =>
        {
            var path = world.Store.ReceiptPath(command.ReceiptId); changed = File.ReadAllText(path) + " "; File.WriteAllText(path, changed);
        };
        Check.Pesto(() => world.Apply(world.Plan(id)), "offlineJoin.uncertain", "final projection cannot overwrite changed bytes");
        var head = world.Store.Read(id)!;
        Check.Equal(changed, File.ReadAllText(world.Store.ReceiptPath(head.Event.ReceiptId!)), "byte-exact competing receipt preserved");
        world.JoinAfterBoot();
        Check.Pesto(() => world.Service.Observe(id), "offlineJoin.evidence", "observation cannot hide changed mirror");
        Check.Equal(0, world.Platform.ObserveCalls, "no AD read before local proof linkage");
    }

    [Test]
    public void ObservationRequiresNewBootBeforeAnyAdAndAllIdentityFactsBeforeVerified()
    {
        using var world = new World(); var id = world.Import(); world.Apply(world.Plan(id));
        var pending = world.Service.Observe(id); Check.False(Flag(pending, "verified"), "same boot cannot confirm");
        Check.Equal(0, world.Platform.ObserveCalls, "no AD contact until local postboot proof");
        world.JoinAfterBoot();
        world.Platform.AlterObservation = observation => observation with { AdGuid = "22222222-2222-2222-2222-222222222222" };
        var wrong = world.Service.Observe(id); Check.False(Flag(wrong, "verified"), "name and OU alone never confirm wrong GUID");
        Check.Equal("Uncertain", world.Store.Read(id)!.Event.State, "wrong identity remains durable uncertainty");
        world.Platform.AlterObservation = observation => observation with { SecureChannel = null };
        Check.False(Flag(world.Service.Observe(id), "verified"), "unknown secure channel refuses");
        world.Platform.AlterObservation = null;
        var verified = world.Service.Observe(id); Check.True(Flag(verified, "verified"), "complete exact proof verifies");
        Check.Equal("Verified", world.Store.Read(id)!.Event.State, "verified journal contains full observation");
        Check.Null(OfflineJoinStore.RefusalForMutation(world.Gp, Computer), "only verified postboot state releases ODJ barrier");
        var history = GpHistory.Read(world.Gp); Check.Equal(0, history.InvalidCount, "verified projection accepted from real journal");
        Check.Equal("succeeded", history.Entries.Single().Receipt.Status, "history displays verified evidence");
        Check.Equal(1, world.Platform.ApplyCalls, "all observations remain read only to Windows/AD");
    }

    [Test]
    public void BootAtApplicationRatherThanImportDeterminesPostbootProof()
    {
        using var world = new World(); var id = world.Import(); world.Clock.Advance(TimeSpan.FromMinutes(2));
        world.Platform.Local = world.Platform.Local with { BootUtc = world.Clock.GetUtcNow().AddMinutes(-1) };
        var appliedBoot = world.Platform.Local.BootUtc;
        world.Apply(world.Plan(id)); Check.Equal(appliedBoot, world.Store.Read(id)!.Event.Baseline!.BootUtc, "request stores its actual Windows boot");
        world.Platform.Local = world.Platform.Local with { PartOfDomain = true, Domain = Domain, DomainRole = 1 };
        Check.False(Flag(world.Service.Observe(id), "verified"), "reboot between import and apply is not the post-apply boot");
        Check.Equal(0, world.Platform.ObserveCalls, "no AD until newer than applied boot");
        world.JoinAfterBoot(); Check.True(Flag(world.Service.Observe(id), "verified"), "next boot qualifies");
    }

    [Test]
    public void CrashAfterIntentBeforeMirrorIsObservableWithoutReplay()
    {
        using var world = new World(); var id = world.Import(); var imported = world.Store.Read(id)!;
        var requested = world.Store.Append(imported, "Requested", "receipt-" + Guid.NewGuid().ToString("N"), "odj-plan-crash", baseline: world.Platform.Local);
        Check.False(File.Exists(world.Store.ReceiptPath(requested.Event.ReceiptId!)), "simulated interruption precedes mirror");
        var read = world.Service.Observe(id);
        Check.False(Flag(read, "verified"), "missing postboot proof stays unverified");
        Check.True(File.Exists(world.Store.ReceiptPath(requested.Event.ReceiptId!)), "only absent initial mirror projected from actual durable intent");
        Check.Equal(0, world.Platform.ApplyCalls + world.Platform.ObserveCalls, "no replay or AD without new boot");
        Check.Pesto(() => world.Service.Prepare(id), "offlineJoin.consumed", "interrupted Requested remains consumed");
    }

    [Test]
    public void LocalAndOnlinePolicyGuardsFailClosedButOfflineClockPolicyDoesNotContactDc()
    {
        foreach (var policy in new[] { "CoordinationRequired", "IncidentMode" })
        {
            using var world = new World(); world.SetPolicy(policy, true);
            var rejected = false; try { world.Import(); } catch (PestoException) { rejected = true; }
            Check.True(rejected, policy + " prevents import"); Check.Equal(0, world.Platform.ApplyCalls + world.Platform.ObserveCalls, "no network");
        }
        using (var world = new World())
        {
            world.SetPolicy("ExcludedGroupGuids", new JsonArray(AdGuid));
            Check.Pesto(() => world.Import(), "offlineJoin.online_policy", "group exclusion needs AD and cannot be bypassed offline");
        }
        using (var world = new World())
        {
            world.SetPolicy("BlockJoinOnClockSkew", true); var id = world.Import(); world.Apply(world.Plan(id));
            Check.Equal(1, world.Platform.ApplyCalls, "historical offline path does not impose a DC clock dependency");
            Check.Equal(0, world.Platform.ObserveCalls, "no network observation before boot");
        }
        foreach (var change in new Func<OfflineJoinLocalState, OfflineJoinLocalState>[] { s => s with { Administrator = null }, s => s with { PartOfDomain = true },
            s => s with { DomainRole = 4 }, s => s with { ConfiguredName = "OTHER" }, s => s with { MachineId = null }, s => s with { BootUtc = null } })
        {
            using var world = new World(); world.Platform.Local = change(world.Platform.Local);
            Check.Pesto(() => world.Import(), "offlineJoin.local", "unknown or unsafe local identity refuses before import");
        }
    }

    [Test]
    public void AppendOnlyEventsRefuseStaleWritersAndTerminalMirrorsNeedTheirRealJournal()
    {
        using var world = new World(); var id = world.Import(); var original = world.Store.Read(id)!;
        var next = world.Store.Append(original, "Requested", "receipt-" + Guid.NewGuid().ToString("N"), "odj-plan-store", baseline: world.Platform.Local);
        Check.Pesto(() => world.Store.Append(original, "Requested", "receipt-other", "plan-other", baseline: world.Platform.Local), "offlineJoin.changed", "stale writer cannot replace intent");
        Check.Equal(next.Sha256, world.Store.Read(id)!.Sha256, "concurrent event retained");
        var projection = Encoding.UTF8.GetBytes(OfflineJoinReceipt.Create(next).ToJsonString());
        Check.True(OfflineJoinReceipt.ValidateStored(world.Gp, projection), "projection bound to actual immutable event");
        Check.False(OfflineJoinReceipt.ValidateStored(NewRoot(), projection), "same JSON is not evidence without its journal");
        File.AppendAllText(Path.Combine(world.Store.DirectoryFor(id), "events", "0003.json"), " ");
        Check.False(OfflineJoinReceipt.ValidateStored(world.Gp, projection), "even semantically same modified bytes break evidence hash");
    }

    [Test]
    public void ImportLimitRefusesBeforeCreatingAnUnreadableFiveHundredAndFirstRecord()
    {
        using var world = new World(); var now = world.Clock.GetUtcNow();
        var binding = new OfflineJoinBinding(new string('a', 64), Computer, Domain, AdGuid, Ou, Machine,
            new string('b', 64), new string('c', 64), now, now.AddHours(24), now.AddHours(-2), "WORKGROUP", 0, false);
        OfflineJoinSnapshot? first = null;
        for (var index = 0; index < 500; index++)
        {
            var record = world.Store.Begin(binding with { Id = index.ToString("x64", System.Globalization.CultureInfo.InvariantCulture) });
            first ??= record;
        }
        Check.Pesto(() => world.Store.Begin(binding), "offlineJoin.limit", "admission bound precedes directory and event creation");
        Check.Equal(500, world.Store.Ids().Count, "registry remains within its readable bound");
        Check.False(Directory.Exists(world.Store.DirectoryFor(binding.Id)), "rejected import leaves no partial new directory");
        Check.Equal(first!.Sha256, world.Store.Read(first.Event.Binding.Id)!.Sha256, "existing durable bytes preserved");
    }

    [Test]
    public void HistoricalV1BarriersAreIdentifiedWithoutMigrationOrBlobReplay()
    {
        using var world = new World(); var id = OfflineJoinRules.Hash(File.ReadAllBytes(world.Source));
        var folder = Path.Combine(world.Gp, "OfflineJoin"); Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, id + ".json");
        var legacy = new JsonObject
        {
            ["Schema"] = 1, ["Mode"] = "OfflineJoin", ["Id"] = id, ["State"] = "Requested",
            ["BootUtc"] = world.Platform.Local.BootUtc!.Value.ToString("O"), ["OperationId"] = Guid.NewGuid().ToString("N"),
            ["NativeCode"] = null, ["Utc"] = world.Clock.GetUtcNow().ToString("O"),
            ["Plan"] = new JsonObject
            {
                ["Schema"] = 1, ["Purpose"] = "PestoPreparedPlan", ["Action"] = "OfflineJoin",
                ["CreatedUtc"] = world.Clock.GetUtcNow().ToString("O"), ["ExpiresUtc"] = world.Clock.GetUtcNow().AddHours(24).ToString("O"),
                ["MachineId"] = Machine, ["ConfigStamp"] = new string('a', 64), ["Domain"] = Domain,
                ["Computer"] = Computer, ["NewName"] = Computer, ["TargetOU"] = Ou, ["ObjectGuid"] = AdGuid,
                ["BlobSHA256"] = id, ["Integrity"] = new string('b', 64)
            }
        };
        var original = legacy.ToJsonString(); File.WriteAllText(path, original);
        Check.Contains("V1", OfflineJoinStore.RefusalForMutation(world.Gp, Computer), "historic pending state is diagnosed as V1");
        Check.NotNull(OfflineJoinStore.RefusalForMutation(world.Gp, "CHANGEDNAME", localTarget: true), "local name change cannot hide historical local uncertainty");
        Check.Pesto(() => world.Import(), "offlineJoin.barrier", "old pending blob cannot be imported into a new identity");
        Check.Equal(original, File.ReadAllText(path), "old journal never migrated or rewritten");
        Check.Equal(0, world.Platform.ApplyCalls + world.Platform.ObserveCalls, "no native or AD action for old journal");
        legacy["State"] = "Verified"; legacy["Plan"] = new JsonObject { ["Computer"] = Computer }; File.WriteAllText(path, legacy.ToJsonString());
        Check.NotNull(OfflineJoinStore.RefusalForMutation(world.Gp, Computer), "malformed historical terminal claim never removes a barrier");
    }

    [Test]
    public void GlobalGpMutexSerializesTheWholeConfirmedOfflineApplication()
    {
        using var world = new World(); var id = world.Import(); var plan = world.Plan(id);
        using var other = new OfflineJoinService(world.Config, world.Gp, ConfigurationAccessMode.Live, world.Platform, world.Clock);
        world.Platform.DuringApply = _ =>
        {
            Exception? failure = null;
            var competitor = new Thread(() =>
            {
                try { Check.Pesto(() => other.Prepare(id), "offlineJoin.busy", "another thread cannot cross GP while native application is active"); }
                catch (Exception error) { failure = error; }
            });
            competitor.Start(); Check.True(competitor.Join(TimeSpan.FromSeconds(10)), "competing admission is bounded");
            if (failure is not null) throw failure;
        };
        world.Apply(plan);
        Check.Equal(1, world.Platform.ApplyCalls, "one native request under the shared historical mutex");
    }

    [Test]
    public void FixedWorkersHaveOneDurableNativeCallAndSeparateReadOnlyObservation()
    {
        var apply = WindowsOfflineJoinScripts.Apply;
        Check.Equal(1, apply.Split("$process.Start()", StringSplitOptions.None).Length - 1, "one native dispatch site");
        Check.True(apply.IndexOf("Write-PestoOfflineNew $j.AttemptPath", StringComparison.Ordinal) < apply.IndexOf("$process.Start()", StringComparison.Ordinal), "exclusive durable marker before djoin");
        Check.Contains("[IO.FileMode]::CreateNew", apply, "native marker never replaces an old attempt");
        Check.Contains("/requestodj /loadfile", apply, "local request only"); Check.Contains("/localos", apply, "local Windows target");
        Check.False(apply.Contains("/provision", StringComparison.OrdinalIgnoreCase) || apply.Contains("Import-Module", StringComparison.OrdinalIgnoreCase), "apply has no AD provisioning or module");
        var observe = WindowsOfflineJoinScripts.Observe;
        Check.True(observe.IndexOf("Postboot local proof absent", StringComparison.Ordinal) < observe.IndexOf("Import-Module", StringComparison.Ordinal), "local boot proof precedes AD");
        Check.Contains("Test-ComputerSecureChannel -Server", observe, "secure channel read is explicit");
        Check.False(observe.Contains("-Repair", StringComparison.OrdinalIgnoreCase) || observe.Contains("/requestodj", StringComparison.Ordinal), "observation never repairs or applies");
        foreach (var script in new[] { WindowsOfflineJoinScripts.ReadLocal, apply, observe })
            Check.False(script.Contains('\u2019') || script.Contains('\u201c') || script.Contains('\u201d'), "PowerShell delimiters are ASCII");
    }
}

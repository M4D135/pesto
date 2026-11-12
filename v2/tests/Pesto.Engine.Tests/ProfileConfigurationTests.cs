using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class ProfileConfigurationTests
{
    private sealed class DuringPreparationClock : TimeProvider
    {
        public Action? NextRead;
        public override DateTimeOffset GetUtcNow()
        {
            var action = NextRead; NextRead = null; action?.Invoke();
            return new DateTimeOffset(2026, 10, 25, 12, 0, 0, TimeSpan.Zero);
        }
    }
    private static string NewRoot() => Path.Combine(Path.GetTempPath(), "pesto-profile-tests-" + Guid.NewGuid().ToString("N"));
    private static ProfileConfigurationService Service(string root, FixedClock? clock = null, string identity = "S-1-5-21-origin")
        => new(root, identity, ConfigurationAccessMode.Live, clock);
    private static string Bundle(string configuration = LiveTestConfig.Valid, string version = "2026.10.25")
        => ConfigurationDocument.Export(configuration, version).ToJsonString();
    private static string DefaultFile(string text)
    {
        var root = NewRoot(); Directory.CreateDirectory(root);
        var file = Path.Combine(root, "default.json"); File.WriteAllText(file, text); return file;
    }
    private static JsonObject Import(ProfileConfigurationService service, string text)
    {
        var plan = service.PreviewImport(text);
        return service.ApplyImport(Harness.Str(plan, "planId"), true);
    }
    private static JsonElement Settings(string prefix = "111301") => PestoJson.Element(new
    {
        domain = "example.local", dc = "", prefix, rootOu = "OU=Postes,DC=example,DC=local",
        preprodOu = "", preprodSite = "", production = true, randomNames = false,
        namingPattern = PestoSettings.DefaultPattern,
        sites = new[] { new { id = "paris", name = "Paris", code = "PA", ou = "OU=Paris,OU=Postes,DC=example,DC=local" } }
    });

    [Test]
    public void SelectedImportFileUsesStrictBomAwareDecodingAndABoundedSnapshot()
    {
        var root = NewRoot(); Directory.CreateDirectory(root);
        var path = Path.Combine(root, "selected.json");
        var text = Bundle();
        try
        {
            foreach (var encoding in new Encoding[] { new UTF8Encoding(false, true), new UTF8Encoding(true, true),
                new UnicodeEncoding(false, true, true), new UnicodeEncoding(true, true, true),
                new UTF32Encoding(false, true, true), new UTF32Encoding(true, true, true) })
            {
                File.WriteAllBytes(path, encoding.GetPreamble().Concat(encoding.GetBytes(text)).ToArray());
                Check.Equal(text, ConfigurationDocument.ReadFile(path), "selected import preserves BOM-aware document text");
            }
            foreach (var malformed in new byte[][] { [0xc3, 0x28], [0xef, 0xbb, 0xbf, 0xff], [0xff, 0xfe, 0x00], [0x00, 0x00, 0xfe, 0xff, 0x01] })
            {
                File.WriteAllBytes(path, malformed);
                Check.Pesto(() => ConfigurationDocument.ReadFile(path), "config.encoding", "invalid bytes cannot silently change configuration data");
                Check.True(malformed.SequenceEqual(File.ReadAllBytes(path)), "a refused import never changes its source");
            }
            File.WriteAllBytes(path, new byte[ConfigurationDocument.MaximumBytes + 1]);
            Check.Pesto(() => ConfigurationDocument.ReadFile(path), "config.invalid", "oversized selected file refused before decoding");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void ExportUsesClosedAllowlistAndStableFingerprint()
    {
        var raw = JsonNode.Parse(LiveTestConfig.Valid)!.AsObject();
        raw["Password"] = "DO-NOT-DISTRIBUTE";
        raw["Sessions"] = new JsonArray("DO-NOT-DISTRIBUTE");
        raw["history"] = "DO-NOT-DISTRIBUTE";
        raw["CONF"]![0]!["Secret"] = "DO-NOT-DISTRIBUTE";
        raw["CONF"]![0]!["ADM"] = "DO-NOT-DISTRIBUTE";
        var first = ConfigurationDocument.Export(raw.ToJsonString(), "1.0");
        Check.False(first.ToJsonString().Contains("DO-NOT-DISTRIBUTE", StringComparison.Ordinal), "secret/session/history not exported");
        Check.Null(first["configuration"]!["DEBUG"], "debug overrides not distributed");
        var second = ConfigurationDocument.Export(first["configuration"]!.ToJsonString(), "2.0");
        Check.Equal(Harness.Str(first, "fingerprint"), Harness.Str(second, "fingerprint"), "fingerprint is payload-based");
        _ = ConfigurationDocument.ValidateBundle(first.ToJsonString());
    }

    [Test]
    public void BundleRejectsForgedHashAndUnknownPayloadFields()
    {
        var bundle = JsonNode.Parse(Bundle())!.AsObject();
        bundle["configuration"]!["CONF"]![0]!["Prefixe"] = "222222";
        Check.Pesto(() => ConfigurationDocument.ValidateBundle(bundle.ToJsonString()), "config.invalid", "tamper rejected");
        bundle = JsonNode.Parse(Bundle())!.AsObject();
        bundle["configuration"]!["Password"] = "secret";
        Check.Pesto(() => ConfigurationDocument.ValidateBundle(bundle.ToJsonString()), "config.invalid", "unknown field rejected, not silently imported");
    }

    [Test]
    public void DuplicateJsonPropertiesAndNestedPayloadsAreRejected()
    {
        Check.Pesto(() => ConfigurationDocument.Sanitize(LiveTestConfig.Valid.Replace("\"Configured\": true", "\"Configured\": true, \"configured\": false", StringComparison.Ordinal)), "config.invalid", "case duplicate rejected");
        var raw = JsonNode.Parse(LiveTestConfig.Valid)!;
        raw["POLICY"]!["ExcludedNames"] = new JsonArray(new JsonObject { ["password"] = "secret" });
        Check.Pesto(() => ConfigurationDocument.Sanitize(raw.ToJsonString()), "config.invalid", "structured secrets cannot ride allowed array");
    }

    [Test]
    public void FreshProfileAutomaticallyImportsPackDefaultsExactlyOnce()
    {
        var root = NewRoot(); var service = Service(root); var defaults = DefaultFile(Bundle());
        var result = service.Initialize(defaults);
        Check.Equal("imported", Harness.Str(result, "status"), "fresh automatic import");
        Check.True(File.Exists(Path.Combine(root, "cfg.json")), "stored in profile");
        var original = File.ReadAllText(service.ConfigurationPath);
        var repeat = Service(root).Initialize(defaults);
        Check.False(Harness.Bool(repeat, "requiresDecision"), "same distribution remembered");
        Check.Equal(original, File.ReadAllText(service.ConfigurationPath), "no rewrite");
        Check.False(Directory.Exists(Path.Combine(root, "backups")), "no redundant backup");
    }

    [Test]
    public void InvalidProfileIsDisclosedWithoutReadingDefaultsOrInventingActiveSettings()
    {
        var root = NewRoot(); Directory.CreateDirectory(root);
        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes("{\"Password\":\"PRIVATE-INVALID-CFG\",\"CONF\":")).ToArray();
        File.WriteAllBytes(Path.Combine(root, "cfg.json"), bytes);
        var service = Service(root);
        // Parsing this default would fail. A malformed existing profile must take priority over it.
        var defaults = DefaultFile("DO-NOT-READ-OR-APPLY-THIS-DEFAULT");
        var initialized = service.Initialize(defaults, Path.Combine(NewRoot(), "missing-legacy"));
        Check.Equal("invalid", Harness.Str(initialized, "configurationState"), "startup can open the explicit repair interface");
        Check.True(Harness.Bool(initialized, "configurationExists"), "existing malformed file is not treated as a fresh profile");
        Check.False(Harness.Bool(initialized, "configured") || Harness.Bool(initialized, "requiresDecision"), "no usable configuration or automatic distribution decision");
        Check.Null(initialized["fingerprint"], "invalid data has no advertised business fingerprint");
        var settings = service.ReadSettings();
        Check.Equal("invalid", Harness.Str(settings, "configurationState"), "settings endpoint remains usable");
        Check.Null(settings["domain"], "no invented domain");
        Check.Null(settings["production"], "no default presented as the active environment");
        Check.False((initialized.ToJsonString() + settings.ToJsonString()).Contains("PRIVATE-INVALID-CFG", StringComparison.Ordinal), "raw parser contents never reach the web");
        Check.Pesto(() => service.PreviewSettings(Settings()), "config.recovery_required", "normal editing cannot erase unreadable restrictions");
        Check.True(bytes.SequenceEqual(File.ReadAllBytes(service.ConfigurationPath)), "startup and settings preserve every original byte");
        Check.False(File.Exists(Path.Combine(root, "configuration-decisions.json")), "no distributed choice is inferred");
        Check.False(Directory.Exists(Path.Combine(root, "backups")), "no replacement before an explicit import");
    }

    [Test]
    public void ExplicitRecoveryRequiresConfirmationAndBacksUpEvenInvalidEncodingExactlyOnce()
    {
        var root = NewRoot(); Directory.CreateDirectory(root);
        var bytes = Encoding.UTF8.GetBytes("PRIVATE-BINARY-CFG").Concat(new byte[] { 0xc3, 0x28, 0xff }).ToArray();
        File.WriteAllBytes(Path.Combine(root, "cfg.json"), bytes);
        var service = Service(root);
        Check.Equal("invalid", Harness.Str(service.Status(), "configurationState"), "bad encoding is reported safely");
        var plan = service.PreviewImport(Bundle());
        Check.True(Harness.Bool(plan, "replacesInvalidConfiguration") && Harness.Bool(plan, "backupRequired"), "recovery is explicit in the real import plan");
        Check.Contains("invalide", plan["differences"]!.ToJsonString(), "comparison identifies the unreadable source");
        Check.False(plan.ToJsonString().Contains("PRIVATE-BINARY-CFG", StringComparison.Ordinal), "no secret/raw bytes in the comparison");
        var id = Harness.Str(plan, "planId");
        Check.Pesto(() => service.ApplyImport(id, false), "config.confirmation", "recovery needs explicit confirmation");
        Check.True(bytes.SequenceEqual(File.ReadAllBytes(service.ConfigurationPath)), "preview and refused confirmation never touch the old file");
        var applied = service.ApplyImport(id, true);
        Check.True(bytes.SequenceEqual(File.ReadAllBytes(Harness.Str(applied, "backup"))), "backup contains the exact original binary data");
        Check.Equal("valid", Harness.Str(applied, "configurationState"), "confirmed replacement is valid");
        Check.True(Harness.Bool(applied, "configured"), "host can reconnect only after a valid configuration exists");
        Check.Equal("111301", Harness.Str(service.ReadSettings(), "prefix"), "new parameters are now readable");
        Check.Pesto(() => service.ApplyImport(id, true), "config.plan", "recovery is not replayable");
        Check.Equal(1, Directory.GetFiles(Path.Combine(root, "backups")).Length, "only one original backup");
    }

    [Test]
    public void RecoveryPlanRejectsAConcurrentByteChangeEvenWhenDecodedTextIsIdentical()
    {
        var root = NewRoot(); Directory.CreateDirectory(root);
        var withoutBom = Encoding.UTF8.GetBytes("{\"CONF\":");
        File.WriteAllBytes(Path.Combine(root, "cfg.json"), Encoding.UTF8.GetPreamble().Concat(withoutBom).ToArray());
        var service = Service(root); var plan = service.PreviewImport(Bundle());
        File.WriteAllBytes(service.ConfigurationPath, withoutBom);
        Check.Pesto(() => service.ApplyImport(Harness.Str(plan, "planId"), true), "config.changed", "a BOM-only concurrent change invalidates the byte-bound preview");
        Check.True(withoutBom.SequenceEqual(File.ReadAllBytes(service.ConfigurationPath)), "concurrent writer wins without overwrite");
        Check.False(Directory.Exists(Path.Combine(root, "backups")), "no stale replacement was attempted");
    }

    [Test]
    public void ValidBomConfigurationsKeepByteBoundSettingsAndReferencePlans()
    {
        var root = NewRoot(); Directory.CreateDirectory(root);
        var path = Path.Combine(root, "cfg.json");
        var utf8 = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(LiveTestConfig.Valid)).ToArray();
        File.WriteAllBytes(path, utf8);
        var service = Service(root);
        var settings = service.PreviewSettings(Settings("222222"));
        var saved = service.ApplyImport(Harness.Str(settings, "planId"), true);
        Check.True(utf8.SequenceEqual(File.ReadAllBytes(Harness.Str(saved, "backup"))), "valid UTF8 BOM also survives in its exact backup");
        var utf16 = Encoding.Unicode.GetPreamble().Concat(Encoding.Unicode.GetBytes(LiveTestConfig.Valid)).ToArray();
        File.WriteAllBytes(path, utf16);
        Check.Equal("valid", Harness.Str(service.Status(), "configurationState"), "historical UTF16 BOM remains supported");
        var references = service.PreviewReferences("""{"schema":1,"kind":"pesto.references","version":"bom-test","sites":[],"services":[]}""");
        var applied = service.ApplyReferences(Harness.Str(references, "planId"), new Dictionary<string, string>(), true);
        Check.True(utf16.SequenceEqual(File.ReadAllBytes(Harness.Str(applied, "backup"))), "reference plan uses the same exact byte stamp as the store");
    }

    [Test]
    public void TwoOperatorProfilesCanInitializeFromTheSamePackConcurrently()
    {
        var defaults = DefaultFile(Bundle()); var original = File.ReadAllText(defaults);
        var first = Service(NewRoot(), identity: "operator-one"); var second = Service(NewRoot(), identity: "operator-two");
        Parallel.Invoke(() => first.Initialize(defaults), () => second.Initialize(defaults));
        Check.True(File.Exists(first.ConfigurationPath) && File.Exists(second.ConfigurationPath), "both independent profiles initialized");
        Check.Equal(original, File.ReadAllText(defaults), "shared pack never mutated");
        Import(first, LiveTestConfig.Valid.Replace("111301", "222222", StringComparison.Ordinal));
        Check.Equal("111301", Harness.Str(second.ReadSettings(), "prefix"), "one profile cannot overwrite another");
        Check.False(Harness.Str(first.Status(), "profile") == Harness.Str(second.Status(), "profile"), "profile decision namespaces differ");
    }

    [Test]
    public void ConcurrentWriterLockRefusesInsteadOfLosingAChange()
    {
        var service = Service(NewRoot()); var plan = service.PreviewImport(Bundle());
        Directory.CreateDirectory(service.ConfigurationRoot);
        using (var held = new FileStream(Path.Combine(service.ConfigurationRoot, ".configuration.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            Check.Pesto(() => service.ApplyImport(Harness.Str(plan, "planId"), true), "config.busy", "cooperating writer excluded");
            Check.False(File.Exists(service.ConfigurationPath), "no write while lock owned by another operation");
        }
        service.ApplyImport(Harness.Str(plan, "planId"), true);
        Check.True(File.Exists(service.ConfigurationPath), "explicit retry after lock release succeeds");
    }

    [Test]
    public void ExplicitLegacyImportNeverChangesTheOriginal()
    {
        var legacy = LiveTestConfig.Write(LiveTestConfig.Valid);
        var original = File.ReadAllText(Path.Combine(legacy, "cfg.json"));
        var service = Service(NewRoot());
        service.Initialize(legacyRoot: legacy);
        Check.Equal(original, File.ReadAllText(Path.Combine(legacy, "cfg.json")), "legacy untouched");
        Check.False(File.ReadAllText(service.ConfigurationPath).Contains("admin-postes", StringComparison.Ordinal), "login not migrated");
    }

    [Test]
    public void ExistingProfileProposesDifferencesAndRemembersKeep()
    {
        var root = NewRoot(); var service = Service(root); Import(service, LiveTestConfig.Valid);
        var original = File.ReadAllText(service.ConfigurationPath);
        var defaults = DefaultFile(Bundle(LiveTestConfig.Valid.Replace("111301", "222222", StringComparison.Ordinal)));
        var proposal = service.Initialize(defaults);
        Check.True(Harness.Bool(proposal, "requiresDecision"), "decision proposed");
        var pending = proposal["pendingDistribution"]!;
        Check.True(Harness.Arr(pending, "differences").Count > 0, "differences shown");
        service.DecideDistribution(Harness.Str(pending, "planId"), false, true);
        Check.Equal(original, File.ReadAllText(service.ConfigurationPath), "keep preserves config");
        Check.False(Harness.Bool(Service(root).Initialize(defaults), "requiresDecision"), "choice survived process recreation");
    }

    [Test]
    public void ReplacementIsConfirmedBackedUpAndSingleUse()
    {
        var service = Service(NewRoot()); Import(service, LiveTestConfig.Valid);
        var original = File.ReadAllText(service.ConfigurationPath);
        var proposal = service.Initialize(DefaultFile(Bundle(LiveTestConfig.Valid.Replace("111301", "222222", StringComparison.Ordinal))));
        var id = Harness.Str(proposal["pendingDistribution"]!, "planId");
        Check.Pesto(() => service.DecideDistribution(id, true, false), "config.confirmation", "explicit confirmation required");
        Check.Equal(original, File.ReadAllText(service.ConfigurationPath), "no write before confirmation");
        var result = service.DecideDistribution(id, true, true);
        Check.Equal(original, File.ReadAllText(Harness.Str(result, "backup")), "immutable backup retains previous config");
        Check.Contains("222222", File.ReadAllText(service.ConfigurationPath), "new prefix saved");
        Check.Pesto(() => service.ApplyImport(id, true), "config.plan", "plan not replayable");
    }

    [Test]
    public void SameVersionDifferentFingerprintAndDifferentProfileAskAgain()
    {
        var root = NewRoot(); var service = Service(root); Import(service, LiveTestConfig.Valid);
        var first = DefaultFile(Bundle(LiveTestConfig.Valid.Replace("111301", "222222", StringComparison.Ordinal), "same"));
        var pending = service.Initialize(first)["pendingDistribution"]!;
        service.DecideDistribution(Harness.Str(pending, "planId"), false, true);
        Check.True(Harness.Bool(Service(root, identity: "other-origin").Initialize(first), "requiresDecision"), "decision belongs to profile identity");
        var second = DefaultFile(Bundle(LiveTestConfig.Valid.Replace("111301", "333333", StringComparison.Ordinal), "same"));
        Check.True(Harness.Bool(Service(root).Initialize(second), "requiresDecision"), "changed payload asks despite same version");
    }

    [Test]
    public void ConcurrentEditWinsOverAnOldPreview()
    {
        var service = Service(NewRoot()); Import(service, LiveTestConfig.Valid);
        var plan = service.PreviewImport(Bundle(LiveTestConfig.Valid.Replace("111301", "222222", StringComparison.Ordinal)));
        var concurrent = LiveTestConfig.Valid.Replace("111301", "333333", StringComparison.Ordinal);
        File.WriteAllText(service.ConfigurationPath, concurrent);
        Check.Pesto(() => service.ApplyImport(Harness.Str(plan, "planId"), true), "config.changed", "stale import refused");
        Check.Equal(concurrent, File.ReadAllText(service.ConfigurationPath), "concurrent change preserved");
    }

    [Test]
    public void EditDuringPreviewCannotBeReboundToANewerConfigurationStamp()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.Valid);
        var clock = new DuringPreparationClock();
        var service = new ProfileConfigurationService(root, "origin", ConfigurationAccessMode.Live, clock);
        var changed = LiveTestConfig.Valid.Replace("111301", "333333", StringComparison.Ordinal);
        clock.NextRead = () => File.WriteAllText(service.ConfigurationPath, changed);
        Check.Pesto(() => service.PreviewSettings(Settings("222222")), "config.changed", "candidate built on old bytes cannot acquire newer stamp");
        Check.Equal(changed, File.ReadAllText(service.ConfigurationPath), "concurrent writer preserved");
        File.WriteAllText(service.ConfigurationPath, LiveTestConfig.Valid);
        clock.NextRead = () => File.WriteAllText(service.ConfigurationPath, changed);
        Check.Pesto(() => service.PreviewReferences("""
            {"schema":1,"kind":"pesto.references","version":"1","sites":[],"services":[{"site":"PA","code":"002","name":"Accueil"}]}
            """), "config.changed", "reference plan keeps exact source snapshot");
        Check.Equal(changed, File.ReadAllText(service.ConfigurationPath), "reference comparison never overwrote concurrent writer");
    }

    [Test]
    public void ExpiredImportNeverWrites()
    {
        var clock = new FixedClock(); var service = Service(NewRoot(), clock);
        var plan = service.PreviewImport(Bundle()); clock.Advance(TimeSpan.FromMinutes(16));
        Check.Pesto(() => service.ApplyImport(Harness.Str(plan, "planId"), true), "config.plan", "expired preview refused");
        Check.False(File.Exists(service.ConfigurationPath), "no configuration written");
    }

    [Test]
    public void IsolationProtectsRealProfileEvenWithDirectApiCalls()
    {
        var root = LiveTestConfig.Write(LiveTestConfig.Valid);
        var before = File.ReadAllText(Path.Combine(root, "cfg.json"));
        foreach (var mode in new[] { ConfigurationAccessMode.Demo, ConfigurationAccessMode.HealthCheck, ConfigurationAccessMode.BinaryRecovery })
        {
            var service = new ProfileConfigurationService(root, "origin", mode);
            Check.Equal("isolated", Harness.Str(service.Initialize(@"\\unreachable\defaults\cfg.json", @"\\unreachable\legacy"), "status"), "no external path evaluated");
            Check.Pesto(() => service.Export("1"), "config.isolated", "export blocked");
            Check.Pesto(() => service.PreviewImport(Bundle()), "config.isolated", "import blocked");
            Check.Pesto(() => service.ApplyImport("anything", true), "config.isolated", "apply blocked");
            Check.Pesto(() => service.WriteInstallationDefault(@"\\unreachable\pack", "1", ""), "config.isolated", "installation default blocked before path access");
            Check.Pesto(() => service.PreviewReferences("{}"), "config.isolated", "reference import blocked");
            Check.Pesto(() => service.PreviewSettings(Settings()), "config.isolated", "settings blocked");
        }
        Check.Equal(before, File.ReadAllText(Path.Combine(root, "cfg.json")), "real configuration unchanged");
        Check.Equal(1, Directory.GetFiles(root).Length, "no hidden decision or lock file created in isolated modes");
    }

    [Test]
    public void FreshConfigurationNeedsNoV1InstallationAndReliesOnObservedOu()
    {
        var service = Service(NewRoot());
        Check.Equal("", Harness.Str(service.ReadSettings(), "domain"), "no invented domain");
        var plan = service.PreviewSettings(Settings()); service.ApplyImport(Harness.Str(plan, "planId"), true);
        var settings = service.ReadSettings(); Check.Equal("111301", Harness.Str(settings, "prefix"), "configured");
        var gateway = new FakeGateway { FindOu = _ => null };
        var backend = Harness.Live(service.ConfigurationRoot, gateway);
        Check.Equal(0, Harness.Arr(Harness.Call(backend, "directory.sites"), "items").Count, "unobserved OU excluded");
        gateway.FindOu = path => new DirectoryOrganizationalUnit(path, gateway.OuGuid);
        Check.Equal(1, Harness.Arr(Harness.Call(backend, "directory.sites"), "items").Count, "observed OU available");
    }

    [Test]
    public void SettingsChangeBusinessFieldsAndPreserveExistingPolicy()
    {
        var service = Service(NewRoot()); Import(service, LiveTestConfig.Valid);
        var plan = service.PreviewSettings(Settings("222222")); service.ApplyImport(Harness.Str(plan, "planId"), true);
        Check.Equal("222222", Harness.Str(service.ReadSettings(), "prefix"), "prefix editable");
        var raw = JsonNode.Parse(File.ReadAllText(service.ConfigurationPath))!;
        Check.Equal(50, raw["POLICY"]!["MaxBatch"]!.GetValue<int>(), "existing policy retained");
        Check.False(raw["POLICY"]!["RandomNameEnabled"]!.GetValue<bool>(), "explicit random setting applied");
    }

    [Test]
    public void EntraAndPrecreatedSettingsKeepLegacyDefaultsAndRequireConfirmedApplication()
    {
        var root = NewRoot(); var service = Service(root);
        Check.Equal("Disabled", Harness.Str(service.ReadSettings(), "entraPolicy"), "new profile never opts into a leave");
        Check.False(Harness.Bool(service.ReadSettings(), "allowPrecreatedJoin"), "new profile does not reuse an old AD account");
        var initial = service.PreviewSettings(Settings()); service.ApplyImport(Harness.Str(initial, "planId"), true);
        Check.Equal("Disabled", Harness.Str(service.ReadSettings(), "entraPolicy"), "new-profile default explicitly persisted");
        var legacy = JsonNode.Parse(LiveTestConfig.Valid)!.AsObject(); legacy["CONF"]![0]!.AsObject().Remove("EntraPolicy");
        legacy["POLICY"]!["AllowPrecreatedJoin"] = true;
        Import(service, legacy.ToJsonString());
        Check.Equal("HybridOnly", Harness.Str(service.ReadSettings(), "entraPolicy"), "missing historical option retains effective V1 policy");
        var absent = service.PreviewSettings(Settings()); service.ApplyImport(Harness.Str(absent, "planId"), true);
        Check.True(Harness.Bool(service.ReadSettings(), "allowPrecreatedJoin"), "absent optional field preserves permission");
        var before = File.ReadAllText(service.ConfigurationPath);
        var args = JsonNode.Parse(Settings().GetRawText())!.AsObject();
        args["entraPolicy"] = "Disabled"; args["allowPrecreatedJoin"] = false;
        var plan = service.PreviewSettings(JsonSerializer.SerializeToElement(args));
        Check.Equal(before, File.ReadAllText(service.ConfigurationPath), "preview does not change either policy");
        service.ApplyImport(Harness.Str(plan, "planId"), true);
        Check.Equal("Disabled", Harness.Str(service.ReadSettings(), "entraPolicy"), "confirmed Entra choice applied");
        Check.False(Harness.Bool(service.ReadSettings(), "allowPrecreatedJoin"), "explicit false applied");
        var exported = ConfigurationDocument.Export(File.ReadAllText(service.ConfigurationPath), "policy-test");
        Check.Equal("Disabled", exported["configuration"]!["CONF"]![0]!["EntraPolicy"]!.GetValue<string>(), "pack/export preserves explicit Entra policy");
        Check.False(exported["configuration"]!["POLICY"]!["AllowPrecreatedJoin"]!.GetValue<bool>(), "pack/export preserves reuse policy");
    }

    [Test]
    public void OfflineAndAutomationSettingsRequireExplicitConfirmedBooleansAndTravelWithThePack()
    {
        var service = Service(NewRoot());
        var pairs = new[] { ("allowOfflineJoin", "AllowOfflineJoin"), ("unattendedJoinEnabled", "UnattendedJoinEnabled"),
            ("unattendedOperationsEnabled", "UnattendedOperationsEnabled") };
        foreach (var (argument, _) in pairs) Check.False(Harness.Bool(service.ReadSettings(), argument), "new profile opts into no offline or unattended mutation");
        var initial = service.PreviewSettings(Settings()); service.ApplyImport(Harness.Str(initial, "planId"), true);
        var created = JsonNode.Parse(File.ReadAllText(service.ConfigurationPath))!;
        foreach (var (_, property) in pairs) Check.False(created["POLICY"]![property]!.GetValue<bool>(), "new default persisted explicitly");
        var before = File.ReadAllText(service.ConfigurationPath);
        var args = JsonNode.Parse(Settings().GetRawText())!.AsObject();
        foreach (var (argument, _) in pairs) args[argument] = true;
        var prepared = service.PreviewSettings(JsonSerializer.SerializeToElement(args));
        Check.Equal(before, File.ReadAllText(service.ConfigurationPath), "preview performs no configuration mutation");
        Check.Pesto(() => service.ApplyImport(Harness.Str(prepared, "planId"), false), "config.confirmation", "saving these permissions requires confirmation");
        service.ApplyImport(Harness.Str(prepared, "planId"), true);
        var absent = service.PreviewSettings(Settings()); service.ApplyImport(Harness.Str(absent, "planId"), true);
        var exported = service.Export("offline-automation-policy");
        foreach (var (argument, property) in pairs)
        {
            Check.True(Harness.Bool(service.ReadSettings(), argument), "absence preserves explicitly enabled policy");
            Check.True(exported["configuration"]!["POLICY"]![property]!.GetValue<bool>(), "custom package/default envelope carries exact explicit choice");
        }
    }

    [Test]
    public void OfflineAndAutomationSettingsRejectNullStringsNumbersAndCollections()
    {
        var service = Service(NewRoot());
        foreach (var argument in new[] { "allowOfflineJoin", "unattendedJoinEnabled", "unattendedOperationsEnabled" })
        foreach (var value in new JsonNode?[] { null, JsonValue.Create("true"), JsonValue.Create(1), new JsonArray(), new JsonObject() })
        {
            var args = JsonNode.Parse(Settings().GetRawText())!.AsObject(); args[argument] = value?.DeepClone();
            var refused = false;
            try { service.PreviewSettings(JsonSerializer.SerializeToElement(args)); } catch (PestoException) { refused = true; }
            Check.True(refused, "optional policy present requires an actual JSON boolean");
        }
        Check.False(File.Exists(service.ConfigurationPath), "invalid settings never initialize a profile");
    }

    [Test]
    public void EntraAndPrecreatedSettingsRejectUnknownAndUntypedChoices()
    {
        var service = Service(NewRoot());
        foreach (var value in new JsonNode?[] { JsonValue.Create("Always"), JsonValue.Create("hybridonly"), JsonValue.Create(true), null })
        {
            var args = JsonNode.Parse(Settings().GetRawText())!.AsObject(); args["entraPolicy"] = value?.DeepClone();
            var refused = false;
            try { service.PreviewSettings(JsonSerializer.SerializeToElement(args)); } catch (PestoException) { refused = true; }
            Check.True(refused, "unknown Entra choices never become permission");
        }
        var flag = JsonNode.Parse(Settings().GetRawText())!.AsObject(); flag["allowPrecreatedJoin"] = "true";
        var rejected = false;
        try { service.PreviewSettings(JsonSerializer.SerializeToElement(flag)); } catch (PestoException) { rejected = true; }
        Check.True(rejected, "precreated permission requires a JSON boolean");
    }

    [Test]
    public void AdvancedPolicyFormFieldsAreExplicitAndDoNotProbeTheConfiguredShare()
    {
        var service = Service(NewRoot()); Import(service, ConfigurationPolicyFixture.Create().ToJsonString());
        var absent = service.PreviewSettings(Settings()); service.ApplyImport(Harness.Str(absent, "planId"), true);
        var retained = service.ReadSettings();
        Check.True(Harness.Bool(retained, "coordinationRequired") && Harness.Bool(retained, "reserveNamesInAd")
            && Harness.Bool(retained, "auditEventLogEnabled") && Harness.Bool(retained, "blockJoinOnClockSkew"), "absent form options keep restrictions");
        Check.Equal(1, Harness.Arr(retained, "excludedGroupGuids").Count, "absent exclusion field preserved");
        var args = JsonNode.Parse(Settings().GetRawText())!.AsObject();
        var registry = Path.Combine(NewRoot(), "not-created");
        args["coordinationRoot"] = registry; args["coordinationRequired"] = true;
        args["reserveNamesInAd"] = false; args["auditEventLogEnabled"] = false; args["blockJoinOnClockSkew"] = false;
        args["excludedGroupGuids"] = new JsonArray("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
        var plan = service.PreviewSettings(JsonSerializer.SerializeToElement(args));
        Check.False(Directory.Exists(registry), "preview does not prepare or probe a registry");
        service.ApplyImport(Harness.Str(plan, "planId"), true);
        var result = service.ReadSettings();
        Check.Equal(registry, Harness.Str(result, "coordinationRoot"), "explicit path persisted only as data");
        Check.False(Harness.Bool(result, "reserveNamesInAd") || Harness.Bool(result, "auditEventLogEnabled") || Harness.Bool(result, "blockJoinOnClockSkew"), "explicit false is a real configuration choice");
        Check.Equal("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", Harness.Arr(result, "excludedGroupGuids")[0]!.GetValue<string>(), "GUID canonicalized without resolving a group");
        Check.False(Directory.Exists(registry), "saving settings never creates a share or registry");
    }

    [Test]
    public void AdvancedPolicyFormRejectsDuplicateInvalidAndOversizedGroupLists()
    {
        var service = Service(NewRoot()); Import(service, LiveTestConfig.Valid);
        foreach (var groups in new[]
        {
            new JsonArray("00000000-0000-0000-0000-000000000000"), new JsonArray("not-a-guid"),
            new JsonArray("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
            new JsonArray(Enumerable.Range(0, 201).Select(_ => (JsonNode?)JsonValue.Create(Guid.NewGuid().ToString("D"))).ToArray())
        })
        {
            var args = JsonNode.Parse(Settings().GetRawText())!.AsObject(); args["excludedGroupGuids"] = groups;
            Check.Pesto(() => service.PreviewSettings(JsonSerializer.SerializeToElement(args)), "config.invalid", "group restriction list refused before application");
        }
        var invalid = JsonNode.Parse(Settings().GetRawText())!.AsObject(); invalid["coordinationRequired"] = true; invalid["coordinationRoot"] = "";
        Check.Pesto(() => service.PreviewSettings(JsonSerializer.SerializeToElement(invalid)), "config.invalid", "required coordination cannot lack a root");
    }

    [Test]
    public void SymlinkedProfileOrConfigurationIsRejected()
    {
        if (OperatingSystem.IsWindows()) return; // Windows symlink privileges are qualified separately.
        var actual = LiveTestConfig.Write(LiveTestConfig.Valid); var link = NewRoot();
        Directory.CreateSymbolicLink(link, actual);
        Check.Pesto(() => Service(link), "config.path", "profile link rejected");
        var root = NewRoot(); Directory.CreateDirectory(root);
        File.CreateSymbolicLink(Path.Combine(root, "cfg.json"), Path.Combine(actual, "cfg.json"));
        Check.Pesto(() => Service(root).Export("1"), "config.path", "config link rejected");
    }

    [Test]
    public void LegacyCustomizedPackContainsOnlySanitizedDefaultsAndIsNotOfficial()
    {
        var sourceConfiguration = ConfigurationPolicyFixture.Create();
        var profile = Service(NewRoot()); Import(profile, sourceConfiguration.ToJsonString());
        var source = NewRoot(); var destination = NewRoot();
        Directory.CreateDirectory(Path.Combine(source, "wad", "web"));
        var pe = new byte[256];
        pe[0] = 0x4d; pe[1] = 0x5a; pe[0x3c] = 0x80;
        pe[0x80] = 0x50; pe[0x81] = 0x45; pe[0x84] = 0x64; pe[0x85] = 0x86;
        pe[0x98] = 0x0b; pe[0x99] = 0x02;
        File.WriteAllBytes(Path.Combine(source, "Pesto.exe"), pe);
        ActiveDirectoryTestBundle.CopyToApplication(source);
        File.WriteAllText(Path.Combine(source, "wad", "web", "index.html"), "<html>package fixture</html>");
        File.WriteAllText(Path.Combine(source, "wad", "Pesto.package.json"), """
            {"schemaVersion":2,"packName":"Pesto-v2-portable","version":"2.0.0","channel":"PROD","entryPoint":"Pesto.exe",
             "layout":"singlefile-wad","repository":"M4D135/pesto","webview2Runtime":"evergreen","distribution":"candidate","official":false}
            """);
        UpdatePackage.Rehash(source);
        var sourceHash = UpdatePackage.Validate(source).Fingerprint;
        _ = LegacyCustomPack.Build(source, destination, profile.Export("entreprise.1"), "entreprise.1");
        Check.Equal(sourceHash, UpdatePackage.Validate(source).Fingerprint, "source remains untouched");
        Check.Equal("custom", UpdatePackage.Validate(destination).Distribution, "all copied hashes verify");
        var defaults = ConfigurationDocument.ValidateBundle(File.ReadAllText(Path.Combine(destination, "wad", "defaults", "configuration.json")));
        Check.Equal(ConfigurationDocument.Canonical(sourceConfiguration["POLICY"]!), ConfigurationDocument.Canonical(defaults["configuration"]!["POLICY"]!), "custom defaults retain every V1 restriction and structured scenario");
        Check.Equal("HybridOnly", defaults["configuration"]!["CONF"]![0]!["EntraPolicy"]!.GetValue<string>(), "custom export does not reinterpret Entra policy");
        Check.False(defaults.ToJsonString().Contains("admin-postes", StringComparison.Ordinal), "no account in defaults");
        Check.False(Directory.Exists(Path.Combine(destination, "backups")), "no profile backups copied");
        var fresh = Service(NewRoot()); fresh.Initialize(Path.Combine(destination, "wad", "defaults", "configuration.json"));
        Check.Equal("111301", Harness.Str(fresh.ReadSettings(), "prefix"), "new operator profile imports custom settings");
        var freshConfiguration = JsonNode.Parse(File.ReadAllText(fresh.ConfigurationPath))!;
        Check.Equal(ConfigurationDocument.Canonical(sourceConfiguration["POLICY"]!), ConfigurationDocument.Canonical(freshConfiguration["POLICY"]!), "automatic import keeps the distributed restrictions");
        Check.Pesto(() => LegacyCustomPack.Build(source, Path.Combine(source, "child"), profile.Export("1"), "1"), "package.destination", "source cannot be mutated by nested export");
    }
}

internal sealed class ReferenceImportTests
{
    private static (ProfileConfigurationService Service, string Root) Prepared()
    {
        var root = LiveTestConfig.Write(ConfigurationDocument.Sanitize(LiveTestConfig.Valid).ToJsonString());
        return (new ProfileConfigurationService(root, "origin", ConfigurationAccessMode.Live), root);
    }
    private const string Incoming = """
      {"schema":1,"kind":"pesto.references","version":"2026.10.25","sites":[{"pattern":"Marseille*","code":"MA"}],
       "services":[{"site":"PA","code":"INF","name":"Informatique"},{"site":"MA","code":"001","name":"Accueil"}]}
      """;

    [Test]
    public void ConflictsRequireExplicitResolutionBeforeAtomicApplication()
    {
        var (service, root) = Prepared(); var before = File.ReadAllText(Path.Combine(root, "cfg.json"));
        var plan = service.PreviewReferences(Incoming); var id = Harness.Str(plan, "planId");
        Check.Equal(1, Harness.Int(plan, "conflictCount"), "label disagreement is explicit");
        Check.Equal(2, Harness.Int(plan, "additions"), "site and new service shown");
        Check.Pesto(() => service.ApplyReferences(id, new Dictionary<string, string>(), true), "references.conflicts", "missing resolution refused");
        Check.Equal(before, File.ReadAllText(Path.Combine(root, "cfg.json")), "no partial merge");
        var result = service.ApplyReferences(id, new Dictionary<string, string> { ["service:PA:INF"] = "incoming" }, true);
        Check.Equal(before, File.ReadAllText(Harness.Str(result, "backup")), "reference merge backed up");
        var raw = JsonNode.Parse(File.ReadAllText(Path.Combine(root, "cfg.json")))!;
        Check.Equal(2, raw["NameCatalogue"]!.AsArray().Count, "unique catalogue");
        Check.Equal(4, raw["TAGS"]!.AsArray().Count, "site added");
        Check.Equal(2, raw["ReferenceData"]!["ServiceLabels"]!.AsArray().Count, "labels stored atomically with catalogue");
        Check.Pesto(() => service.ApplyReferences(id, new Dictionary<string, string>(), true), "config.plan", "single use");
    }

    [Test]
    public void DuplicateReferencesAreRejectedAndRepeatedImportAddsNoDuplicates()
    {
        var (service, _) = Prepared();
        Check.Pesto(() => service.PreviewReferences(Incoming.Replace("\"Marseille*\",\"code\":\"MA\"}", "\"Marseille*\",\"code\":\"MA\"},{\"pattern\":\"marseille*\",\"code\":\"MA\"}", StringComparison.Ordinal)), "config.invalid", "case insensitive duplicate rejected");
        var first = service.PreviewReferences(Incoming);
        service.ApplyReferences(Harness.Str(first, "planId"), new Dictionary<string, string> { ["service:PA:INF"] = "incoming" }, true);
        var repeated = service.PreviewReferences(Incoming);
        Check.Equal(0, Harness.Int(repeated, "additions"), "repeated import no additions");
        Check.Equal(0, Harness.Int(repeated, "conflictCount"), "same labels no conflict");
        service.ApplyReferences(Harness.Str(repeated, "planId"), new Dictionary<string, string>(), true);
        var raw = JsonNode.Parse(File.ReadAllText(service.ConfigurationPath))!;
        Check.Equal(2, raw["NameCatalogue"]!.AsArray().Count, "still exactly two pairs");
    }

    [Test]
    public void ImportedServiceLabelIsUsedByActualDirectoryApi()
    {
        var (service, root) = Prepared();
        var gateway = new FakeGateway(); gateway.ChildOus["OU=SITES,OU=Postes,DC=example,DC=local"] = ["Paris", "Marseille"];
        var backend = Harness.Live(root, gateway);
        Check.Equal("INF", Harness.Str(Harness.Arr(Harness.Call(backend, "directory.services", new { site = "PA" }), "items")[0]!, "name"), "original catalogue observed");
        var preview = service.PreviewReferences(Incoming);
        service.ApplyReferences(Harness.Str(preview, "planId"), new Dictionary<string, string> { ["service:PA:INF"] = "incoming" }, true);
        var services = Harness.Call(backend, "directory.services", new { site = "PA" });
        Check.Equal("Informatique", Harness.Str(Harness.Arr(services, "items")[0]!, "name"), "same backend reloads imported label");
        var sites = Harness.Call(backend, "directory.sites");
        Check.True(Harness.Arr(sites, "items").Any(s => Harness.Str(s!, "code") == "MA"), "new mapping resolves an observed OU");
    }

    [Test]
    public void KeepingAConflictPreservesTheLocalValue()
    {
        var (service, _) = Prepared(); var preview = service.PreviewReferences(Incoming);
        service.ApplyReferences(Harness.Str(preview, "planId"), new Dictionary<string, string> { ["service:PA:INF"] = "current" }, true);
        var raw = JsonNode.Parse(File.ReadAllText(service.ConfigurationPath))!;
        Check.False(raw["ReferenceData"]!["ServiceLabels"]!.AsArray().Any(n => n!["Site"]!.GetValue<string>() == "PA"), "existing implicit label kept");
        Check.Equal(2, raw["NameCatalogue"]!.AsArray().Count, "nonconflicting addition applied");
    }

    [Test]
    public void ConcurrentConfigurationChangeCancelsReferenceMerge()
    {
        var (service, _) = Prepared(); var preview = service.PreviewReferences(Incoming);
        var changed = LiveTestConfig.Valid.Replace("111301", "222222", StringComparison.Ordinal);
        File.WriteAllText(service.ConfigurationPath, changed);
        Check.Pesto(() => service.ApplyReferences(Harness.Str(preview, "planId"), new Dictionary<string, string> { ["service:PA:INF"] = "incoming" }, true), "config.changed", "concurrent write preserved");
        Check.Equal(changed, File.ReadAllText(service.ConfigurationPath), "no partial catalogue update");
    }

    [Test]
    public void UnknownSiteCannotBeIntroducedByAServiceOnly()
    {
        var (service, _) = Prepared();
        var text = Incoming.Replace("\"sites\":[{\"pattern\":\"Marseille*\",\"code\":\"MA\"}]", "\"sites\":[]", StringComparison.Ordinal);
        Check.Pesto(() => service.PreviewReferences(text), "config.invalid", "orphan service refused");
    }

    [Test]
    public void ReferenceUrisAndEmptySiteIdentifiersAreRejectedAsData()
    {
        var (service, _) = Prepared();
        Check.Pesto(() => service.PreviewReferences(Incoming.Replace("\"site\":\"PA\"", "\"site\":\"\"", StringComparison.Ordinal)), "config.invalid", "empty service site rejected");
        Check.Pesto(() => service.PreviewReferences(Incoming.Replace("\"code\":\"MA\"", "\"code\":\"https://example.invalid\"", StringComparison.Ordinal)), "config.invalid", "URI cannot be site code");
        Check.Pesto(() => service.PreviewReferences(Incoming.Replace("\"kind\":\"pesto.references\"", "\"kind\":\"pesto.references\",\"sourceUri\":\"https://example.invalid\"", StringComparison.Ordinal)), "config.invalid", "no implicit remote source accepted");
        Check.Pesto(() => service.PreviewReferences(Incoming.Replace("Marseille*", "", StringComparison.Ordinal)), "config.invalid", "empty site pattern rejected");
    }
}

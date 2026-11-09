using System.Text.Json.Nodes;
using System.Text;
using Pesto.Engine.Live;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class ReceiptRestartTests
{
    private sealed class World : IReceiptRestartEnvironment, IDisposable
    {
        public readonly string Root = WindowsEvidenceFixture.Root();
        public readonly FixedClock Clock = new();
        public readonly ReceiptRestartStore Store;
        public readonly ReceiptRestartCoordinator Service;
        public RestartReceiptSnapshot Source;
        public RestartTargetEvidence Target;
        public RestartNativeResult Result = new("accepted", "Fixture request accepted; no real reboot");
        public int Sends; public bool ThrowSend, FailFinal; public Action? DuringRead;
        public string Configuration = LiveTestConfig.NoRandom;
        public bool ReadOnly, Available = true;
        public MutationManagedPolicy Managed = new();
        public string ConfigurationHash => RemoteWindowsEvidenceProtocol.Hash(Encoding.UTF8.GetBytes(Configuration));
        public World(string kind = "rename", bool remote = false)
        {
            Store = new(Root); var now = Clock.GetUtcNow();
            var receipt = new Receipt("receipt-restart", now, kind, WindowsEvidenceFixture.Computer, WindowsEvidenceFixture.NewName,
                WindowsEvidenceFixture.Ou, "fixture", "pendingRestart", kind == "join" ? 10 : 20, "Original accepted receipt", true);
            Source = new(receipt, new string('a', 64), WindowsEvidenceFixture.Domain, WindowsEvidenceFixture.Dc,
                WindowsEvidenceFixture.AdGuid, WindowsEvidenceFixture.Machine, now.AddHours(-1), !remote, InitialOu: WindowsEvidenceFixture.Ou);
            Target = new(receipt.Computer, receipt.NewName, Source.Domain, true, 1, Source.MachineId, Source.InitialBootUtc,
                Source.ComputerGuid, receipt.NewName, !remote, now, RemoteProof: remote ? WindowsEvidenceFixture.Proof(WindowsEvidenceFixture.Request("restart", receipt.Id, Source.Sha256)) : null,
                AdOu: WindowsEvidenceFixture.Ou, AdProtected: true);
            Service = new(this, Store, Clock);
        }
        public RestartReceiptSnapshot ReadSource(string id) { Check.Equal(Source.Receipt.Id, id, "Exact receipt lookup"); return Source; }
        public void RequireAdmission(RestartReceiptSnapshot source, string configurationSha256)
        {
            ReceiptRestartAdmission.RequireSession(ReadOnly, Available);
            var requirements = ReceiptRestartAdmission.RequireConfiguration(Encoding.UTF8.GetBytes(Configuration), configurationSha256, source, Managed);
            if (requirements.ExcludedGroupGuids.Count > 0) throw ReceiptRestartRules.Refused("Fixture has no external group reader");
        }
        public RestartTargetEvidence ReadTarget(RestartReceiptSnapshot source) { DuringRead?.Invoke(); return Target with { ObservedUtc = Clock.GetUtcNow() }; }
        public RestartNativeResult Send(RestartCommand command)
        {
            Sends++; ReceiptRestartRules.ValidateCommand(command);
            var requested = Path.Combine(Root, "V2", "restarts", command.Id + ".requested.json");
            Check.True(File.Exists(requested), "Durable requested receipt precedes every native effect");
            Check.Contains(command.ReceiptSha256, File.ReadAllText(requested), "Request binds exact parent SHA");
            Check.Equal(ConfigurationHash, command.AuthorizationConfigurationSha256, "Current authorization hash is distinct from historical receipt hash");
            if (FailFinal) File.WriteAllText(Path.Combine(Root, "V2", "restarts", command.Id + ".final.json"), "concurrent-or-torn");
            if (ThrowSend) throw new IOException("Lost native reply"); return Result;
        }
        public RestartPreparation Prepare() => Service.Prepare(Source.Receipt.Id, "plan-" + Guid.NewGuid().ToString("N"), ConfigurationHash);
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); else if (File.Exists(Root)) File.Delete(Root); }
    }

    [Test]
    public void ExplicitRestartKeepsParentPendingAndBlocksAnotherRequestOnSameBoot()
    {
        using var w = new World(); var original = w.Source.Receipt; var plan = w.Prepare();
        Check.Equal(0, w.Sends, "Preparation does not request reboot");
        var result = w.Service.Execute(plan.Authorization);
        Check.Equal("accepted", result.Status, "Acceptance only, never successful reboot");
        Check.Equal(original, result.Receipt, "Every original business field unchanged");
        Check.Equal("pendingRestart", result.Receipt.Status, "No false reconciliation");
        Check.Pesto(() => w.Prepare(), "restart.refused", "Accepted request prevents a second request for the same boot");
        Check.Pesto(() => w.Service.Execute(plan.Authorization), "restart.refused", "Consumed plan never replays");
        Check.Equal(1, w.Sends, "One native request");
    }

    [Test]
    public void LostResponseAndUnrecordableFinalResultRemainDurablyUncertain()
    {
        foreach (var mode in new[] { "lost", "final" })
        {
            using var w = new World { ThrowSend = mode == "lost", FailFinal = mode == "final" };
            var result = w.Service.Execute(w.Prepare().Authorization);
            Check.Equal("uncertain", result.Status, "Unknown result does not become refused or accepted");
            Check.Pesto(() => w.Prepare(), "restart.refused", "Requested proof blocks another send even after a crash or torn final");
            Check.Equal(1, w.Sends, "No retry");
        }
    }

    [Test]
    public void RequestedJournalSurvivesProcessInterruptionAndNewCoordinator()
    {
        using var w = new World(); var command = new RestartCommand("restart-" + Guid.NewGuid().ToString("N"), w.Source.Receipt.Id,
            w.Source.Sha256, "plan-crash", w.Target.ActiveName, w.Target.ConfiguredName, w.Source.Domain, w.Source.ComputerGuid,
            w.Source.MachineId, w.Source.InitialBootUtc, true, w.Clock.GetUtcNow(), "rename", AuthorizationConfigurationSha256: w.ConfigurationHash);
        w.Store.Requested(command);
        var restarted = new ReceiptRestartCoordinator(w, new(w.Root), w.Clock);
        Check.Pesto(() => restarted.Prepare(w.Source.Receipt.Id, "plan-new", w.ConfigurationHash), "restart.refused", "A fresh process cannot resend an unanswered request");
        Check.Equal(0, w.Sends, "No native command on recovery");
    }

    [Test]
    public void DefinitePreSendRefusalNeedsANewPlanAndNeverReusesTheOldOne()
    {
        using var w = new World { Result = new("refused", "Fixture proved zero restart sends") }; var first = w.Prepare();
        Check.Equal("refused", w.Service.Execute(first.Authorization).Status, "Explicit zero-send proof retained");
        Check.Pesto(() => w.Service.Execute(first.Authorization), "restart.refused", "Even a refused plan stays consumed");
        var second = w.Prepare(); Check.True(second.Authorization.Token != first.Authorization.Token, "Fresh explicit preparation required");
        Check.Equal(1, w.Sends, "Preparation never retries implicitly");
    }

    [Test]
    public void ChangedReceiptMachineBootAndExpiredPlanRefuseBeforeJournalOrNativeSend()
    {
        foreach (var change in new[] { "receipt", "machine", "boot", "role", "name", "expiry", "duringRead" })
        {
            using var w = new World(); var plan = w.Prepare();
            switch (change)
            {
                case "receipt": w.Source = w.Source with { Sha256 = new string('b', 64) }; break;
                case "machine": w.Target = w.Target with { MachineId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" }; break;
                case "boot": w.Target = w.Target with { BootUtc = w.Target.BootUtc.AddHours(1) }; break;
                case "role": w.Target = w.Target with { DomainRole = 5 }; break;
                case "name": w.Target = w.Target with { ActiveName = "OTHER-PC" }; break;
                case "expiry": w.Clock.Advance(TimeSpan.FromMinutes(3)); break;
                default: w.DuringRead = () => w.Clock.Advance(TimeSpan.FromMinutes(3)); break;
            }
            Check.Pesto(() => w.Service.Execute(plan.Authorization), "restart.refused", "Changed proof rejects: " + change);
            Check.Equal(0, w.Sends, "No native call"); Check.False(Directory.Exists(w.Root), "No Requested written for a preflight refusal");
        }
    }

    [Test]
    public void PendingJoinMayStillBeWorkgroupOnlyWithTheExactInitialWindowsBaseline()
    {
        using var w = new World("join");
        w.Source = w.Source with { InitialWindowsDomain = "WORKGROUP", InitialPartOfDomain = false, InitialDomainRole = 0, ComputerGuid = null };
        w.Target = w.Target with { PartOfDomain = false, Domain = "WORKGROUP", DomainRole = 0, AdGuid = null, AdName = null };
        var plan = w.Prepare(); var result = w.Service.Execute(plan.Authorization);
        Check.Equal("accepted", result.Status, "The boot needed to establish domain membership can be explicitly requested");
        Check.False(plan.Authorization.Evidence.PartOfDomain, "Workgroup remains an observed fact, never changed to true");
        Check.Equal("pendingRestart", result.Receipt.Status, "No domain-join success invented");
        using var unknown = new World("join"); unknown.Target = unknown.Target with { PartOfDomain = false, Domain = "WORKGROUP", DomainRole = 0 };
        Check.Pesto(() => unknown.Prepare(), "restart.refused", "Old receipt without initial workgroup proof does not gain an invented baseline");
        using var contradicted = new World("join"); contradicted.Source = contradicted.Source with { InitialWindowsDomain = "ORIGINAL", InitialPartOfDomain = false, InitialDomainRole = 0 };
        contradicted.Target = contradicted.Target with { PartOfDomain = false, Domain = "OTHER", DomainRole = 0 };
        Check.Pesto(() => contradicted.Prepare(), "restart.refused", "A changed workgroup is not explained away");
    }

    [Test]
    public void RemoteRestartRequiresNonceBoundProofAndPreservesRemoteIdentity()
    {
        using var w = new World(remote: true); var plan = w.Prepare();
        Check.False(plan.Authorization.Evidence.LocalTarget, "Remote never masquerades as local");
        Check.Equal("accepted", w.Service.Execute(plan.Authorization).Status, "Fixture remote path accepted only with complete proof");
        using var missing = new World(remote: true); missing.Target = missing.Target with { RemoteProof = null };
        Check.Pesto(() => missing.Prepare(), "restart.refused", "No remote restart without SYSTEM proof");
    }

    [Test]
    public void NoRequestedDurableRecordMeansNoNativeCall()
    {
        using var w = new World(); File.WriteAllText(w.Root, "not a directory"); var plan = w.Prepare(); var rejected = false;
        try { w.Service.Execute(plan.Authorization); } catch (IOException) { rejected = true; }
        Check.True(rejected, "Unrecordable intent prevents action"); Check.Equal(0, w.Sends, "No request without durable journal");
    }

    [Test]
    public void FixedWorkerChecksStableIdentityAndNeverForcesOrChangesAd()
    {
        var script = ReceiptRestartScript.LocalSource;
        Check.Equal(1, script.Split("Restart-Computer -ErrorAction Stop", StringSplitOptions.None).Length - 1, "One fixed restart site");
        foreach (var required in new[] { "Get-PestoStableBootUtc", "UtcDateTime.Ticks", "MachineId", "ConfiguredName", "DomainRole", "$sent=$true", "AllowPendingJoin" })
            Check.Contains(required, script, "Native recheck before restart");
        foreach (var forbidden in new[] { "-Force", "Rename-Computer", "Add-Computer", "Move-ADObject", "/leave", "LastBootUpTime", "-Repair" })
            Check.False(script.Contains(forbidden, StringComparison.OrdinalIgnoreCase), "Forbidden implicit side effect: " + forbidden);
        Check.True(script.IndexOf("[Console]::In.ReadToEnd", StringComparison.Ordinal) < script.IndexOf("Restart-Computer", StringComparison.Ordinal), "Local worker waits until owned job is attached before stdin");
    }

    [Test]
    public void CurrentConfigurationAndPolicyAreCheckedAtPreparationAndAfterTheFinalWindowsRead()
    {
        foreach (var stage in new[] { "beforePrepare", "beforeExecute", "duringRead" })
        foreach (var restriction in new[] { "readOnly", "unavailable", "incident", "managedUnknown", "configuration", "excludedName", "scenario" })
        {
            using var w = new World();
            void Restrict()
            {
                switch (restriction)
                {
                    case "readOnly": w.ReadOnly = true; break;
                    case "unavailable": w.Available = false; break;
                    case "incident": w.Managed = new(IncidentMode: true); break;
                    case "managedUnknown": w.Managed = new(Refusal: "HKLM inaccessible"); break;
                    case "scenario": w.Managed = new(ScenarioJson: "{\"Schema\":1,\"Name\":\"locked\",\"Required\":[],\"Allowed\":{},\"Locked\":{\"SiteCode\":\"LY\"}}"); break;
                    default:
                        var cfg = JsonNode.Parse(w.Configuration)!;
                        if (restriction == "excludedName") cfg["POLICY"]!["ExcludedNames"] = new JsonArray("P111301PAINF*");
                        else cfg["CONF"]![0]!["DarkMode"] = "1";
                        w.Configuration = cfg.ToJsonString(); break;
                }
            }
            if (stage == "beforePrepare")
            {
                Restrict();
                // A harmless new configuration can authorize a fresh plan; a historical parent is never rewritten.
                if (restriction == "configuration") { var fresh = w.Prepare(); Check.Equal(w.ConfigurationHash, fresh.Authorization.ConfigurationSha256, "Fresh authorization may use a new configuration"); continue; }
            }
            RestartPreparation? prepared = stage == "beforePrepare" ? null : w.Prepare();
            if (stage == "beforeExecute") Restrict();
            if (stage == "duringRead") w.DuringRead = Restrict;
            var refused = false;
            try { if (prepared is null) w.Prepare(); else w.Service.Execute(prepared.Authorization); }
            catch (Pesto.Core.PestoException) { refused = true; }
            Check.True(refused, stage + "/" + restriction + " cannot authorize a restart");
            Check.Equal(0, w.Sends, "No native restart and no replay");
            Check.False(Directory.Exists(w.Root), "No requested event for a pre-send policy refusal");
        }
    }

    [Test]
    public void ExactPartialRenameMayRequestBootWithoutResolvingTheRemainingMove()
    {
        using var w = new World("renameMove");
        w.Source = w.Source with { Receipt = w.Source.Receipt with { Code = 89, Status = "uncertain", TargetOU = "OU=Lyon,OU=SITES,OU=Postes,DC=example,DC=local" },
            PartialRenameMove = true, InitialProtected = true };
        var original = w.Source.Receipt; var prepared = w.Prepare();
        Check.Equal("accepted", w.Service.Execute(prepared.Authorization).Status, "Separate explicit boot request after proven rename");
        Check.Equal(original, w.Source.Receipt, "Parent remains code89 and partial; no move or success is invented");
        Check.Equal(1, w.Sends, "One reboot request only");
        using var changed = new World("renameMove");
        changed.Source = w.Source;
        changed.Target = changed.Target with { AdProtected = false };
        Check.Pesto(() => changed.Prepare(), "restart.refused", "Protection must still equal the initial proof for code89");
        changed.Target = changed.Target with { AdProtected = true, AdOu = original.TargetOU };
        Check.Pesto(() => changed.Prepare(), "restart.refused", "Moved or ambiguous OU cannot authorize the partial-parent restart path");
    }
}

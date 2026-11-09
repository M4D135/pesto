using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Exercise the actual native writer and final Entra decorator. No native reader, module, task or reboot is invoked.</summary>
internal sealed class C4NativeReceiptHistoryTests
{
    private sealed class World : IDisposable
    {
        public readonly GpFixture Gp = new();
        public readonly string Config = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        public readonly PowerShellMutationGateway Native;
        public MutationRequest Request;
        public readonly object Baseline;
        public readonly string Id = "receipt-" + Guid.NewGuid().ToString("N");
        public World(string kind = "rename", bool remote = true, bool pendingWorkgroup = false)
        {
            Native = new(Config, receiptGpRoot: Gp.Root);
            var sha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(Config, "cfg.json"))));
            var computer = remote ? WindowsEvidenceFixture.Computer : Environment.MachineName;
            Request = new(kind, computer, WindowsEvidenceFixture.AdGuid, WindowsEvidenceFixture.NewName, WindowsEvidenceFixture.Ou,
                WindowsEvidenceFixture.Domain, WindowsEvidenceFixture.Dc, "plan-actual-writer", Id, WindowsEvidenceFixture.Ou,
                WindowsEvidenceFixture.OuGuid, ConfigurationSha256: sha);
            var type = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.NativeReceiptSnapshot")!;
            Baseline = Activator.CreateInstance(type, [WindowsEvidenceFixture.Now.AddHours(-1), WindowsEvidenceFixture.Machine,
                computer, computer, pendingWorkgroup ? "WORKGROUP" : WindowsEvidenceFixture.Domain, !pendingWorkgroup, !pendingWorkgroup,
                WindowsEvidenceFixture.AdGuid, kind == "join" ? WindowsEvidenceFixture.NewName : computer,
                WindowsEvidenceFixture.Ou, true, null, false, pendingWorkgroup ? 0 : 1])!;
            if (remote) type.GetProperty("RemoteProof")!.SetValue(Baseline, WindowsEvidenceFixture.Proof(WindowsEvidenceFixture.Request(id: Id)));
        }
        public JsonObject Render(string phase = "Running", int code = 0, bool restart = false) => JsonNode.Parse((string)typeof(PowerShellMutationGateway)
            .GetMethod("ReceiptJson", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(Native,
                [Request, phase, code, "Message du vrai writer", restart, Baseline])!)!.AsObject();
        public HistoryEntry Read(JsonObject json) { Gp.AdapterRaw(Id, json.ToJsonString()); return GpHistory.Read(Gp.Root).Entries.Single(); }
        public void Dispose() { Directory.Delete(Config, true); Directory.Delete(Gp.Root, true); }
    }

    [Test]
    public void ActualRemoteBaselineReceiptRoundTripsWithoutChangingLocalTarget()
    {
        using var w = new World(); var json = w.Render("PendingRestart", 20, true);
        Check.True(json["WindowsBaselineProof"] is JsonObject, "Actual writer persists the full remote evidence");
        Check.False(json["LocalTarget"]!.GetValue<bool>(), "Remote stays remote");
        Check.True(w.Read(json).Readable, "Actual remote receipt remains readable after close");
        Action<JsonObject>[] changes = [r => r["MachineId"] = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", r => r["ComputerGuid"] = null,
            r => r["LocalTarget"] = true, r => r["InitialBootUtc"] = WindowsEvidenceFixture.Now,
            r => r["WindowsBaselineProof"]!["CleanupConfirmed"] = false, r => r["WindowsBaselineProof"]!["Request"]!["ReceiptId"] = "other-receipt",
            r => r["WindowsBaselineProof"]!["Unknown"] = true];
        foreach (var change in changes) { var value = json.DeepClone().AsObject(); change(value); Check.False(w.Read(value).Readable, "Inconsistent full proof cannot survive history validation"); }
    }

    [Test]
    public void ActualEntraRequestedAndCompletedEvidenceRoundTripsAndCannotBecomeFalseSuccess()
    {
        using var w = new World(); var now = DateTimeOffset.UtcNow;
        var request = new EntraPreparationRequest("rename", w.Request.Computer, w.Request.ComputerGuid!, w.Request.NewName!,
            w.Request.Domain, w.Request.Dc, w.Request.SourceOu!, w.Request.ConfigurationSha256!);
        w.Request = w.Request with { Entra = new("PRIVATE-ENTRA-AUTHORIZATION", request, "hybrid", "HybridOnly", WindowsEvidenceFixture.Machine, now, now.AddMinutes(5)), EntraLeaveConfirmed = true };
        var json = w.Render(); Check.Equal("Requested", json["Entra"]!.GetValue<string>(), "Real pre-send writer announces the confirmed leave intention");
        Check.True(w.Read(json).Readable, "Requested running evidence is readable after interruption");
        var forgedSuccess = json.DeepClone().AsObject(); forgedSuccess["Phase"] = "Verified";
        Check.False(w.Read(forgedSuccess).Readable, "An incomplete leave cannot become a successful receipt");
        var evidence = new EntraLeaveEvidence(w.Gp.Root, ConfigurationAccessMode.Live);
        var started = evidence.Begin(new(w.Id, w.Request.PlanId, new string('a', 64), request, WindowsEvidenceFixture.Machine, now));
        _ = evidence.Append(started, "Completed", "Confirmed", false, nativeCode: 42);
        typeof(PowerShellMutationGateway).GetMethod("ApplyEntraReceipt", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(w.Native, [json, w.Request]);
        json["Phase"] = "PendingRestart"; json["Code"] = 20; json["RestartRequired"] = true;
        Check.True(w.Read(json).Readable, "Actual final Entra fields are admitted by the closed reader");
        Check.True(json["EntraReenrollmentPending"]!.GetValue<bool>(), "Hybrid reenrollment remains a separate uncompleted task");
        Check.False(json.ToJsonString().Contains("PRIVATE-ENTRA-AUTHORIZATION", StringComparison.Ordinal), "Opaque authority is not persisted");
        foreach (var key in new[] { "EntraEvidenceId", "EntraEvidenceSha256" })
        { var changed = json.DeepClone().AsObject(); changed[key] = "foreign"; Check.False(w.Read(changed).Readable, "Entra identity/hash must remain closed and bound"); }
        var mayRun = json.DeepClone().AsObject(); mayRun["EntraMayStillRun"] = true;
        Check.False(w.Read(mayRun).Readable, "A possibly running leave cannot announce PendingRestart");
    }

    [Test]
    public void ActualPrecreatedJoinReceiptKeepsExactExistingGuidWithoutReservationAuthority()
    {
        using var w = new World("join", remote: false);
        w.Request = w.Request with { PrecreatedJoin = new(WindowsEvidenceFixture.AdGuid, WindowsEvidenceFixture.NewName,
            w.Request.Domain, w.Request.Dc!, w.Request.TargetOu!, w.Request.TargetOuGuid!, w.Request.ConfigurationSha256!) };
        var json = w.Render("PendingRestart", 10, true);
        Check.Equal("precreated", json["JoinAccountMode"]!.GetValue<string>(), "Actual native writer distinguishes existing account");
        Check.True(w.Read(json).Readable, "The closed reader accepts the actual existing-account receipt");
        Check.Null(json["ReservationId"], "No reservation authority or cleanup entitlement invented");
        var altered = json.DeepClone().AsObject(); altered["ComputerGuid"] = null;
        Check.False(w.Read(altered).Readable, "Precreated cannot lose its exact object identity");
    }

    [Test]
    public void ActualLocalJoinReceiptCarriesTheWorkgroupBaselineForAnExplicitFirstRestart()
    {
        using var w = new World("join", remote: false, pendingWorkgroup: true); var json = w.Render("PendingRestart", 10, true);
        Check.True(w.Read(json).Readable, "Actual local preboot metadata is part of the closed schema");
        var source = ReceiptRestartRules.ReadSource(Path.Combine(w.Gp.Root, "V2", "receipts", w.Id + ".json"), Encoding.UTF8.GetBytes(json.ToJsonString()), DateTimeOffset.UtcNow);
        Check.Equal("WORKGROUP", source.InitialWindowsDomain, "Initial domain retained as observed");
        Check.Equal(false, source.InitialPartOfDomain, "No invented AD membership"); Check.Equal(0, source.InitialDomainRole, "Initial role retained");
        var target = new RestartTargetEvidence(w.Request.Computer, w.Request.NewName!, "WORKGROUP", false, 0,
            source.MachineId, source.InitialBootUtc, source.ComputerGuid, w.Request.NewName!, true, DateTimeOffset.UtcNow, AdOu: WindowsEvidenceFixture.Ou);
        ReceiptRestartRules.RequireTarget(source, target, DateTimeOffset.UtcNow);
        var missing = json.DeepClone().AsObject(); missing["MachineId"] = null;
        Check.Pesto(() => ReceiptRestartRules.ReadSource(w.Id + ".json", Encoding.UTF8.GetBytes(missing.ToJsonString()), DateTimeOffset.UtcNow), "restart.refused", "Old/incomplete baseline cannot gain a machine identity");
    }

    [Test]
    public void ActualCode89AllowsOnlyASeparatelyConfirmedRestartBeforeAnyChildMove()
    {
        using var w = new World("renameMove");
        w.Request = w.Request with { TargetOu = "OU=Lyon,OU=SITES,OU=Postes,DC=example,DC=local" };
        var json = w.Render("PendingRestart", 89, true);
        RestartReceiptSnapshot Read(JsonObject value) => ReceiptRestartRules.ReadSource(w.Id + ".json",
            Encoding.UTF8.GetBytes(value.ToJsonString()), DateTimeOffset.UtcNow);
        var source = Read(json);
        Check.True(source.PartialRenameMove, "Actual native code89 remains a partial rename-and-move");
        Check.Equal(WindowsEvidenceFixture.Ou, source.ExpectedAdOu, "Only the source OU is valid before remaining move");
        foreach (var phase in new[] { "Uncertain", "Partial" })
        { var sameResult = json.DeepClone().AsObject(); sameResult["Phase"] = phase; Check.True(Read(sameResult).PartialRenameMove, "Historic phase remains partial, never promoted by restart"); }
        Action<JsonObject>[] changes = [r => r["Code"] = 32, r => r["Code"] = 97, r => r["InitialProtected"] = null,
            r => r["InitialOu"] = null, r => r["ComputerGuid"] = null, r => r["RestartRequired"] = false,
            r => r["ContinuationChildReceiptId"] = "receipt-child", r => r["ContinuationChildPlanId"] = "plan-child",
            r => r["ResolutionChildReceiptId"] = "receipt-child"];
        foreach (var change in changes)
        { var altered = json.DeepClone().AsObject(); change(altered); Check.Pesto(() => Read(altered), "restart.refused", "No partial restart without complete evidence or after a child was engaged"); }
    }
}

using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class ReceiptRestartAdmissionTests
{
    private sealed class Adapter(World world) : IMutationGateway, IMutationRestart, IMutationManagedPolicy, IMutationAvailability
    {
        public string Description => "fixture restart admission, aucun processus";
        public int Preparations, Sends;
        public bool IsAvailable { get; set; } = true;
        public string? UnavailableReason => IsAvailable ? null : "Fixture indisponible";
        public MutationManagedPolicy Managed = new();
        public MutationManagedPolicy ReadManagedPolicy() => Managed;
        public MutationOutcome Execute(MutationRequest request) => throw new TestFailureException("No AD mutation is allowed by this fixture");
        public RestartPreparation PrepareRestart(string receiptId, string planId, string configurationSha256)
        {
            Preparations++; var source = world.Source(); Check.Equal(source.Receipt.Id, receiptId, "Exact parent only");
            var target = new RestartTargetEvidence(source.Receipt.Computer, source.Receipt.NewName, source.Domain, true, 1,
                source.MachineId, source.InitialBootUtc, source.ComputerGuid, source.Receipt.NewName, true, world.Clock.GetUtcNow(),
                AdOu: source.ExpectedAdOu, AdProtected: true);
            return new(new(Guid.NewGuid().ToString("N"), planId, source, target, world.Clock.GetUtcNow().AddMinutes(2), configurationSha256), source.Receipt);
        }
        public RestartResult Restart(RestartAuthorization authorization)
        {
            Sends++; return new(authorization.Source.Receipt, "restart-" + Guid.NewGuid().ToString("N"), "accepted",
                authorization.Evidence.ActiveName, world.Clock.GetUtcNow(), "Fixture request only, no reboot");
        }
    }

    private sealed class World : IDisposable
    {
        public readonly string Config = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        public readonly string Gp = Harness.IsolatedGpRoot();
        public readonly FixedClock Clock = new();
        public readonly Adapter Mutation;
        public readonly IPestoBackend Backend;
        public readonly string ReceiptPath;
        public const string Id = "receipt-restart-admission";
        public World()
        {
            var folder = Path.Combine(Gp, "V2", "receipts"); Directory.CreateDirectory(folder);
            ReceiptPath = Path.Combine(folder, Id + ".json");
            File.WriteAllText(ReceiptPath, JsonSerializer.Serialize(new
            {
                Schema = 1, Version = "2.0", Phase = "PendingRestart", Utc = Clock.GetUtcNow(), Adapter = "fixture",
                ReceiptId = Id, PlanId = "plan-historical", Kind = "rename", Computer = WindowsEvidenceFixture.Computer,
                NewName = WindowsEvidenceFixture.NewName, TargetOu = WindowsEvidenceFixture.Ou, Code = 20,
                Message = "Historical accepted rename", RestartRequired = true, ComputerGuid = WindowsEvidenceFixture.AdGuid,
                Domain = WindowsEvidenceFixture.Domain, Dc = WindowsEvidenceFixture.Dc, MachineId = WindowsEvidenceFixture.Machine,
                InitialBootUtc = Clock.GetUtcNow().AddHours(-1), LocalTarget = true, InitialOu = WindowsEvidenceFixture.Ou,
                InitialProtected = true, ConfigurationSha256 = new string('a', 64)
            }));
            Mutation = new(this); Backend = Harness.Live(Config, new FakeGateway(), Mutation, Clock, Gp);
        }
        public RestartReceiptSnapshot Source() => ReceiptRestartRules.ReadSource(ReceiptPath, File.ReadAllBytes(ReceiptPath), Clock.GetUtcNow());
        public JsonNode Prepare() => Harness.Call(Backend, "receipts.prepareRestart", new { id = Id });
        public JsonNode Execute(JsonNode plan) => Harness.Call(Backend, "receipts.restart",
            new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        public void Change(Action<JsonNode> change)
        { var path = Path.Combine(Config, "cfg.json"); var json = JsonNode.Parse(File.ReadAllText(path))!; change(json); File.WriteAllText(path, json.ToJsonString()); }
        public void Dispose() { Directory.Delete(Config, true); Directory.Delete(Gp, true); }
    }

    [Test]
    public void DirectRestartApisCannotBypassCurrentConsultationIncidentOrAvailability()
    {
        var previous = Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION");
        try
        {
            foreach (var restriction in new[] { "consultation", "incident", "unavailable", "managedUnknown" })
            {
                Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", null);
                using var w = new World(); var plan = w.Prepare(); var preparations = w.Mutation.Preparations;
                switch (restriction)
                {
                    case "consultation": Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", "1"); break;
                    case "incident": w.Mutation.Managed = new(IncidentMode: true); break;
                    case "unavailable": w.Mutation.IsAvailable = false; break;
                    default: w.Mutation.Managed = new(Refusal: "HKLM illisible"); break;
                }
                Check.Pesto(() => w.Prepare(), "restart.refused", "Direct preparation blocked: " + restriction);
                Check.Pesto(() => w.Execute(plan), "restart.refused", "Already prepared restart blocked: " + restriction);
                Check.Equal(preparations, w.Mutation.Preparations, "No native preparation after restriction");
                Check.Equal(0, w.Mutation.Sends, "No direct API can bypass admission");
            }
        }
        finally { Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", previous); }
    }

    [Test]
    public void AuthorizationConfigurationMayBeNewerThanHistoryButCannotChangeAfterConfirmation()
    {
        using var w = new World(); var before = File.ReadAllBytes(w.ReceiptPath); var plan = w.Prepare();
        w.Change(json => json["CONF"]![0]!["DarkMode"] = "1");
        Check.Pesto(() => w.Execute(plan), "config.changed", "Even an otherwise harmless cfg change requires a new restart confirmation");
        Check.Equal(0, w.Mutation.Sends, "Old authorization never follows a changed configuration");
        var fresh = w.Prepare(); var result = w.Execute(fresh);
        Check.Equal("accepted", Harness.Str(result["restart"]!, "status"), "Fresh current configuration can authorize the old operation's first reboot");
        Check.True(before.SequenceEqual(File.ReadAllBytes(w.ReceiptPath)), "Historical receipt and its old configuration SHA remain byte-identical");
        Check.Equal("pendingRestart", Harness.Str(result["receipt"]!, "status"), "Accepted request is not a verified reboot");
    }

    [Test]
    public void CurrentNamesOusScenarioDebugAndUnknownGroupsRefuseBeforeNativeRestart()
    {
        foreach (var restriction in new[] { "name", "ou", "scenario", "groups", "Simulation", "GUI" })
        {
            using var w = new World();
            w.Change(json =>
            {
                switch (restriction)
                {
                    case "name": json["POLICY"]!["ExcludedNames"] = new JsonArray(WindowsEvidenceFixture.NewName); break;
                    case "ou": json["POLICY"]!["ExcludedOUs"] = new JsonArray("OU=Postes,DC=example,DC=local"); break;
                    case "scenario": json["POLICY"]!["Scenario"] = JsonNode.Parse("{\"Schema\":1,\"Name\":\"locked\",\"Required\":[],\"Allowed\":{},\"Locked\":{\"SiteCode\":\"LY\"}}"); break;
                    case "groups": json["POLICY"]!["ExcludedGroupGuids"] = new JsonArray("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"); break;
                    default: json["DEBUG"]![restriction] = "true"; break;
                }
            });
            var refused = false; try { w.Prepare(); } catch (PestoException) { refused = true; }
            Check.True(refused, "Current restriction applies to historical receipt: " + restriction);
            Check.Equal(0, w.Mutation.Sends, "No restart without group/policy verification");
            if (restriction != "groups") Check.Equal(0, w.Mutation.Preparations, "Known local policy refusal precedes native diagnostics");
        }
    }

    [Test]
    public void NativeAdmissionUsesCurrentExactBytesAndNeverTreatsMissingGroupsAsAllowed()
    {
        using var w = new World(); var source = w.Source();
        var configuration = File.ReadAllBytes(Path.Combine(w.Config, "cfg.json")); var hash = RemoteWindowsEvidenceProtocol.Hash(configuration);
        _ = ReceiptRestartAdmission.RequireConfiguration(configuration, hash, source, new());
        Check.Pesto(() => ReceiptRestartAdmission.RequireConfiguration(configuration, new string('0', 64), source, new()), "restart.refused", "Exact current bytes required");
        Check.Pesto(() => ReceiptRestartAdmission.RequireConfiguration(configuration, hash, source, new(IncidentMode: true)), "policy.incident", "Native HKLM IncidentMode enforced");
        Check.Pesto(() => ReceiptRestartAdmission.RequireConfiguration(configuration, hash, source with { Domain = "other.local" }, new()), "restart.refused", "Historical domain cannot cross current configuration");
        var changed = JsonNode.Parse(Encoding.UTF8.GetString(configuration))!;
        changed["POLICY"]!["ExcludedGroupGuids"] = new JsonArray("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        var bytes = Encoding.UTF8.GetBytes(changed.ToJsonString());
        Check.Pesto(() => ReceiptRestartAdmission.RequireConfiguration(bytes, RemoteWindowsEvidenceProtocol.Hash(bytes), source with { ComputerGuid = null }, new()),
            "restart.refused", "Missing GUID cannot skip an enabled group policy after an existing join");
        var native = new PowerShellMutationGateway(w.Config, receiptGpRoot: w.Gp);
        Check.Pesto(() => { ((IReceiptRestartEnvironment)native).RequireAdmission(source, hash); return null; }, "restart.refused", "Direct native admission without a pinned config/GP scope never authorizes anything");
    }
}

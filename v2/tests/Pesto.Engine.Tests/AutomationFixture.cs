using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

/// <summary>Real V2 backend with an in-memory AD and a durable, explicitly fake writer. No Windows process or network.</summary>
internal sealed class AutomationFixture : IDisposable
{
    public const string Computer = "P111301PAINF009", NewName = "P111301PAINF010";
    public const string Domain = "example.local", Dc = "dc01.example.local";
    public const string SourceOu = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";
    public const string TargetOu = "OU=Lyon-Sud,OU=SITES,OU=Postes,DC=example,DC=local";
    public const string AdGuid = "11111111-1111-1111-1111-111111111111", OuGuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    public const string Machine = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", TargetMachine = "cccccccc-cccc-cccc-cccc-cccccccccccc";
    public readonly FixedClock Clock = new();
    public readonly string Root = Path.Combine(Path.GetTempPath(), "pesto-cli-test-" + Guid.NewGuid().ToString("N"));
    public readonly string Configuration;
    public string Gp => Path.Combine(Root, "GP");
    public string PlanPath => Path.Combine(Root, "reviewed-plan.json");
    public readonly MemoryDirectory Directory;
    public readonly MemoryMutation Native;
    public int Factories;
    public Action? BeforeFactory;
    public MutationManagedPolicy Managed = new();
    public AutomationHostContext Context { get; set; }

    public AutomationFixture()
    {
        System.IO.Directory.CreateDirectory(Root);
        Configuration = Path.Combine(Root, "profile"); System.IO.Directory.CreateDirectory(Configuration);
        var json = JsonNode.Parse(LiveTestConfig.NoRandom)!;
        json["POLICY"]!["UnattendedJoinEnabled"] = true; json["POLICY"]!["UnattendedOperationsEnabled"] = true;
        File.WriteAllText(Path.Combine(Configuration, "cfg.json"), json.ToJsonString(), new UTF8Encoding(false));
        Directory = new(this); Native = new(this);
        Context = new(Configuration, "S-1-5-21-100-200-300-1001", "S-1-5-21-100-200-300-500", Machine,
            Environment.MachineName, Gp, true, true, true, _ => { }, () => Managed);
    }
    public IPestoBackend Factory()
    {
        Factories++; BeforeFactory?.Invoke();
        return PestoBackend.CreateLive(Configuration, Directory, Native, Clock, Gp);
    }
    public PestoCliResult Run(PestoCliOptions options) => PestoCliRunner.Run(options, Context, Factory, Clock);
    public PestoCliOptions PrepareOptions(string action = "rename") => action == "move"
        ? new(action, Computer, TargetOu: TargetOu, OutPlanPath: PlanPath)
        : new(action, Computer, NewName, OutPlanPath: PlanPath);
    public PestoCliOptions ExecuteOptions(string action = "rename", string key = "deployment/key-1") =>
        new(action, PlanPath: PlanPath, IdempotencyKey: key, Execute: true);
    public AutomationPlan Prepare(string action = "rename")
    {
        var result = Run(PrepareOptions(action));
        Check.Equal(0, result.ExitCode, "Fixture preparation succeeds: " + result.Message);
        Check.NotNull(result.Plan, "A real reviewed intent was produced"); return result.Plan!;
    }
    public void ChangeConfiguration(Action<JsonObject> change)
    {
        var path = Path.Combine(Configuration, "cfg.json"); var json = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        change(json); File.WriteAllText(path, json.ToJsonString(), new UTF8Encoding(false));
    }
    public void Dispose() { if (System.IO.Directory.Exists(Root)) System.IO.Directory.Delete(Root, true); }

    internal sealed class MemoryDirectory(AutomationFixture world) : IDirectoryGateway, IAutomationNameInventory, ILocalDomainMembership
    {
        public bool? LocalComputerJoined => world.Context.OperatorDomainJoined;
        public string Description => "CLI fixture, in-memory AD only";
        public readonly Dictionary<string, DirectoryComputer> Computers = new(StringComparer.OrdinalIgnoreCase)
        { [Computer] = new(Computer, null, SourceOu, null, AdGuid, Domain, null, null, null, null, null) };
        public string[] Aliases = [];
        public bool Complete = true;
        public int Reads, Inventories;
        public string? ObservedPattern;
        public string DcName = Dc;
        public string TargetGuid = OuGuid;
        public string? DiscoverDomainController(string domain) { Reads++; return DcName; }
        public DirectoryComputer? FindComputer(string domain, string? dc, string name) { Reads++; return Computers.GetValueOrDefault(name); }
        public DirectoryOrganizationalUnit? FindOrganizationalUnit(string domain, string? dc, string distinguishedName) { Reads++; return new(distinguishedName, TargetGuid); }
        public DirectorySearchResult SearchComputers(string domain, string? dc, string query, int limit) { Reads++; return new(Computers.Values.Take(limit).ToArray(), Complete); }
        public IReadOnlyList<string> ListChildOuNames(string domain, string? dc, string parentOu) { Reads++; return ["Paris-Nord", "Lyon-Sud"]; }
        public DirectoryNameInventory ListComputerNames(string domain, string? dc, string scopeOu, int maxRows) { Reads++; return new(Computers.Keys.ToArray(), Complete); }
        public DirectoryNameInventory ListAutomationComputerNames(string domain, string dc, string seriesPattern, int maximum)
        { Reads++; Inventories++; ObservedPattern = seriesPattern; return new(Aliases.Concat(Computers.Keys).ToArray(), Complete); }
        public void Apply(MutationRequest request)
        {
            if (request.Kind == "join")
            { Computers[request.NewName!] = new(request.NewName!, null, request.TargetOu, null, AdGuid, Domain, null, null, null, null, null); return; }
            if (!Computers.Remove(request.Computer, out var old)) throw new IOException("Fixture identity absent");
            var name = request.NewName ?? request.Computer;
            Computers[name] = old with { Name = name, Ou = request.TargetOu };
        }
        public override string ToString() => world.Root;
    }

    internal sealed class MemoryMutation(AutomationFixture world) : IMutationGateway, IMutationReceiptFinalizer, IMutationEntraPreparation,
        IMutationManagedPolicy, IMutationNameReservations
    {
        public string Description => "CLI fixture, no native command";
        public string EntraState = "adOnly";
        public int Sends, Preparations, Leases, LeaseVerifications;
        public bool ThrowAfterSend, OmitReceipt, FailFinalWrite;
        public Action<JsonObject>? ChangeDurableReceipt;
        public MutationStatus Status = MutationStatus.PendingRestart;
        public int? Code;
        public MutationRequest? Last;
        public MutationManagedPolicy ReadManagedPolicy() => world.Managed;
        public EntraRenameAuthorization PrepareEntra(EntraPreparationRequest request)
        {
            Preparations++;
            return new("fixture-authority-" + Guid.NewGuid().ToString("N"), request, EntraState, "HybridOnly", TargetMachine,
                world.Clock.GetUtcNow(), world.Clock.GetUtcNow().AddMinutes(5));
        }
        public IReadOnlyList<string> OtherReservedNames(string domain) => [];
        public SharedNameReservationProof? ReservePreviewName(string domain, string name, string previewId, string configurationSha256)
        {
            Leases++;
            Check.True(System.IO.Directory.EnumerateFiles(Path.Combine(world.Gp, "V2", "automation"), "*.request.json").Any(), "CLI intent must exist before the first shared lease");
            var policy = V1Config.Load(world.Configuration).OperationPolicy;
            return new(policy.CoordinationRoot, domain, name, "11111111111111111111111111111111", previewId, configurationSha256,
                new string('a', 64), world.Clock.GetUtcNow().AddMinutes(4), "name-intent-" + Guid.NewGuid().ToString("N"));
        }
        public void VerifyPreviewName(SharedNameReservationProof proof, string configurationSha256) { LeaseVerifications++; }
        public void ReleasePreviewName(SharedNameReservationProof proof) { }
        public MutationOutcome Execute(MutationRequest request)
        {
            Sends++; Last = request;
            Check.NotNull(request.Automation, "All CLI sends carry the internal durable authority");
            AutomationJournal.RequireAuthority(world.Gp, request.Automation!);
            if (Status != MutationStatus.Failed) world.Directory.Apply(request);
            if (ThrowAfterSend) throw new IOException("Simulated lost reply; no actual command");
            var code = Code ?? (Status == MutationStatus.Failed ? 96 : request.Kind == "move" ? 30 : request.Kind == "join" ? 10 : request.Kind == "rename" ? 20 : 77);
            return new(Status == MutationStatus.PendingRestart && request.Kind == "move" ? MutationStatus.Succeeded : Status,
                code, "Explicit fixture outcome", Status != MutationStatus.Failed && request.Kind != "move", request.Kind == "join" ? AdGuid : null);
        }
        public void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome)
        {
            if (FailFinalWrite) throw new IOException("Fixture durable disk failure");
            if (OmitReceipt) return;
            var folder = Path.Combine(world.Gp, "V2", "receipts"); System.IO.Directory.CreateDirectory(folder);
            var phase = outcome.Status switch { MutationStatus.Failed => "Failed", MutationStatus.PendingRestart => "PendingRestart",
                MutationStatus.Succeeded => outcome.RestartRequired ? "PendingRestart" : "Verified", _ => "Uncertain" };
            var json = new JsonObject { ["Schema"] = 1, ["Version"] = "2.0", ["ReceiptId"] = request.ReceiptId, ["PlanId"] = request.PlanId,
                ["Kind"] = request.Kind, ["Computer"] = request.Computer, ["NewName"] = request.NewName, ["TargetOu"] = request.TargetOu,
                ["Phase"] = phase, ["Code"] = outcome.Code, ["Message"] = outcome.Message, ["RestartRequired"] = outcome.RestartRequired,
                ["Utc"] = world.Clock.GetUtcNow().ToString("O"), ["ComputerGuid"] = request.ComputerGuid ?? outcome.ObservedGuid,
                ["Domain"] = request.Domain, ["Dc"] = request.Dc, ["ConfigurationSha256"] = request.ConfigurationSha256,
                ["InitialOu"] = request.SourceOu, ["TargetOuGuid"] = request.TargetOuGuid,
                ["MachineId"] = request.Kind == "join" ? Machine : TargetMachine };
            ChangeDurableReceipt?.Invoke(json);
            using var output = new FileStream(Path.Combine(folder, request.ReceiptId + ".json"), FileMode.Create, FileAccess.Write, FileShare.Read);
            output.Write(Encoding.UTF8.GetBytes(json.ToJsonString())); output.Flush(true);
        }
    }
}

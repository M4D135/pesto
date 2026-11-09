using System.Reflection;
using System.Text;
using System.Text.Json;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class EntraLeaveTests
{
    private const string Machine = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private const string AdGuid = "11111111-1111-1111-1111-111111111111";
    private const string Computer = "P111301PAINF009", NewName = "P111301PAINF010";
    private const string Ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";
    private static string Root() => Path.Combine(Path.GetTempPath(), "pesto-entra-leave-" + Guid.NewGuid().ToString("N"));
    private static EntraLeaveCommand Command(string hash = "") => new("receipt-" + Guid.NewGuid().ToString("N"), "plan-entra",
        new string('b', 64), new("rename", Computer, AdGuid, NewName, "example.local", null, Ou, hash.Length == 0 ? new string('a', 64) : hash),
        Machine, new FixedClock().GetUtcNow());
    private static EntraLeaveEvidence Evidence(string root) => new(root, ConfigurationAccessMode.Live, new FixedClock());

    private sealed class Native(EntraLeaveEvidence evidence, Transport transport) : IEntraLeaveTransport
    {
        public int Calls;
        public EntraLeaveNativeResult Leave(EntraLeaveCommand command, Action<string, string?, string?, long?> record)
        {
            Calls++;
            Check.Equal("Requested", evidence.Read(command.ReceiptId)!.Event.Phase, "durable intent exists before native transport");
            transport.Command = command; transport.Evidence = evidence;
            using var credential = new PestoAdCredential("EXAMPLE\\operator", "fixture-entra-never-stored");
            return new EntraLeaveTask(transport, new FixedClock(), 1, 0)
                .Run(command, PowerShellEntraWorker.Build(command), credential, record);
        }
    }

    private sealed class Transport : ISystemDiagnosticTaskTransport
    {
        public EntraLeaveCommand? Command; public EntraLeaveEvidence? Evidence;
        public string Xml = ""; public string Task = ""; public int Registers, Runs, Deletes;
        public bool LostRunReply, CleanupFailure, Tamper, NoRunTime;
        public long Code = 42;
        private bool ran;
        public void RegisterSystem(string computer, string taskName, string xml, string principal, string password)
        {
            Check.Equal("TaskRegistering", Evidence!.Read(Command!.ReceiptId)!.Event.Phase, "register intent already flushed");
            Check.Equal(Computer, computer, "target fixed");
            Check.Equal("EXAMPLE\\operator", principal, "explicit connection identity");
            Check.False(xml.Contains(password, StringComparison.Ordinal), "no secret in XML");
            Xml = xml; Task = taskName; Registers++;
        }
        public void Register(string computer, string taskName, string xml, string principal, string? passwordForPrincipal) => throw new TestFailureException("SYSTEM only");
        public void Run(string computer, string taskName)
        {
            Check.Equal("TaskStartRequested", Evidence!.Read(Command!.ReceiptId)!.Event.Phase, "launch intent durable before Run");
            Runs++; ran = true;
            if (LostRunReply) throw new IOException("Lost reply after Run");
        }
        public TaskProbeResult Probe(string computer, string taskName) => new(3, Code,
            ran && !NoRunTime ? new FixedClock().GetUtcNow() : null,
            Tamper ? Xml.Replace("S-1-5-18", "S-1-5-19", StringComparison.Ordinal) : Xml);
        public void Delete(string computer, string taskName) { Deletes++; if (CleanupFailure) throw new IOException("Deletion not confirmed"); }
        public string? ReadTaskLogTail(string computer, string path) => throw new TestFailureException("No arbitrary SMB");
    }

    [Test]
    public void StateAndPolicyDistinguishAdOnlyHybridAndEntraOnly()
    {
        Check.Equal("adOnly", EntraPreparationRules.State(0, "AzureAdJoined : NO\r\nDomainJoined : YES\r\n"), "AD only");
        Check.Equal("hybrid", EntraPreparationRules.State(0, "AzureAdJoined : YES\nDomainJoined : YES\n"), "hybrid");
        foreach (var text in new[] { "AzureAdJoined : YES\nDomainJoined : NO", "AzureAdJoined : NO\nDomainJoined : NO",
            "AzureAdJoined : YES\nAzureAdJoined : NO\nDomainJoined : YES", "AzureAdJoined : YES", "DomainJoined : YES" })
            Check.Equal("unknown", EntraPreparationRules.State(0, text), "ambiguous or Entra-only state refuses");
        Check.Equal("unknown", EntraPreparationRules.State(1, "AzureAdJoined : NO\nDomainJoined : YES"), "failed status is unknown");
        EntraPreparationRules.RequireAllowed("adOnly", "Disabled");
        EntraPreparationRules.RequireAllowed("hybrid", "HybridOnly");
        Check.Pesto(() => { EntraPreparationRules.RequireAllowed("hybrid", "Disabled"); return null; }, "entra.disabled", "policy mandatory");
        Check.Pesto(() => { EntraPreparationRules.RequireAllowed("unknown", "HybridOnly"); return null; }, "entra.unknown", "policy cannot grant an unknown target");
    }

    [Test]
    public void DurableRealTaskFormatPrecedesEveryEffectAndConfirmsOnce()
    {
        var root = Root(); var command = Command(); var evidence = Evidence(root); var task = new Transport(); var native = new Native(evidence, task);
        var result = new EntraLeaveTransaction(evidence).Execute(command, native);
        Check.Equal("Confirmed", result.Effect, "fixed worker terminal code confirms leave");
        Check.False(result.MayStillRun, "terminal owned task removed");
        Check.Equal(1, task.Runs, "exactly one Run");
        var saved = evidence.Read(command.ReceiptId)!;
        Check.Equal("Confirmed", saved.Event.Effect, "actual serialized effect retained");
        Check.True(evidence.ReadBarrier(command.ReceiptId).CanAcknowledge, "completed process proof");
        Check.True(evidence.ContainsPhase(command.ReceiptId, "TaskDeleted"), "task cleanup durable");
        Check.False(string.Join("", Directory.EnumerateFiles(root, "*.json", SearchOption.AllDirectories).Select(File.ReadAllText))
            .Contains("fixture-entra-never-stored", StringComparison.Ordinal), "secret absent from all durable evidence");
        Check.Contains("<UserId>S-1-5-18</UserId>", task.Xml, "actual SYSTEM task");
        var script = PowerShellEntraWorker.Build(command);
        Check.Equal(1, script.Split("$start.Arguments='/leave'", StringSplitOptions.None).Length - 1, "one native leave site");
        Check.True(script.IndexOf("Save-EntraTarget 'LeaveRequested'", StringComparison.Ordinal) < script.IndexOf("$start.Arguments='/leave'", StringComparison.Ordinal), "target receipt before native effect");
        Check.Contains("$inspection=$true", PowerShellEntraWorker.Build(command, inspect: true), "inspection enters fixed read-only branch");
    }

    [Test]
    public void LostReplyKeepsBarrierAndNeverReplaysTheSameReceipt()
    {
        var root = Root(); var command = Command(); var evidence = Evidence(root); var task = new Transport { LostRunReply = true }; var native = new Native(evidence, task);
        var transaction = new EntraLeaveTransaction(evidence); var result = transaction.Execute(command, native);
        Check.Equal("Uncertain", result.Effect, "lost reply is uncertain");
        Check.False(evidence.ReadBarrier(command.ReceiptId).CanAcknowledge, "possible active native command blocks ack");
        Check.Pesto(() => transaction.Execute(command, native), "entra.replay", "same id never repeats leave");
        Check.Equal(1, task.Runs, "no second Run");
        Check.Equal(0, task.Deletes, "uncertain task retained");
    }

    [Test]
    public void UnrecordableOrConcurrentIntentSendsNothing()
    {
        var root = Root(); File.WriteAllText(root, "not a directory");
        var evidence = Evidence(root); var task = new Transport(); var native = new Native(evidence, task); var rejected = false;
        try { new EntraLeaveTransaction(evidence).Execute(Command(), native); } catch (Exception) { rejected = true; }
        Check.True(rejected, "failure before transport surfaces");
        Check.Equal(0, native.Calls, "no native call without durable intent");
        var store = Evidence(Root()); var command = Command(); var first = store.Begin(command);
        var next = store.Append(first, "DispatchRequested", "Requested", true);
        Check.Pesto(() => store.Append(first, "Completed", "NotRequested", false), "entra.changed", "stale writer cannot erase concurrent event");
        Check.Equal(next.Sha256, store.Read(command.ReceiptId)!.Sha256, "new evidence preserved byte for byte");
    }

    [Test]
    public void InvalidDefinitionAndMissingFreshRunCannotBecomeSuccess()
    {
        foreach (var task in new[] { new Transport { Tamper = true }, new Transport { NoRunTime = true }, new Transport { Code = 1234 } })
        {
            var evidence = Evidence(Root()); var command = Command();
            var result = new EntraLeaveTransaction(evidence).Execute(command, new Native(evidence, task));
            Check.Equal("Uncertain", result.Effect, "no unproved success");
            Check.False(evidence.ReadBarrier(command.ReceiptId).CanAcknowledge, "uncertain task/process retained");
            Check.Equal(0, task.Deletes, "never delete uncertain or altered task");
        }
    }

    [Test]
    public void CleanupFailurePreservesConfirmedEffectAndRequiresInspection()
    {
        var evidence = Evidence(Root()); var command = Command(); var task = new Transport { CleanupFailure = true };
        var result = new EntraLeaveTransaction(evidence).Execute(command, new Native(evidence, task));
        Check.Equal("Confirmed", result.Effect, "known leave cannot be erased by cleanup failure");
        Check.True(result.MayStillRun, "unconfirmed cleanup blocks rename");
        Check.False(evidence.ReadBarrier(command.ReceiptId).CanAcknowledge, "explicit inspection required");
        var prior = evidence.Read(command.ReceiptId)!;
        var inspected = evidence.Append(prior, "Inspected", "Confirmed", false);
        Check.True(evidence.ReadBarrier(command.ReceiptId).CanAcknowledge, "positive later stop proof allows ack only");
        Check.Equal("Confirmed", inspected.Event.Effect, "inspection preserves original effect");
    }

    [Test]
    public void DemoHealthAndRecoveryCannotCreateOrReadRealEvidence()
    {
        foreach (var mode in new[] { ConfigurationAccessMode.Demo, ConfigurationAccessMode.HealthCheck, ConfigurationAccessMode.BinaryRecovery })
        {
            var root = Root(); var evidence = new EntraLeaveEvidence(root, mode); var command = Command();
            Check.Pesto(() => evidence.Begin(command), "entra.isolated", "direct isolated API rejected");
            Check.Pesto(() => evidence.Read(command.ReceiptId), "entra.isolated", "isolated evidence read rejected before path access");
            Check.False(Directory.Exists(root), "no local storage created by isolated API");
        }
    }

    [Test]
    public void MissingOrDuplicateLivenessFieldsCannotBecomeAStoppedProcess()
    {
        foreach (var duplicate in new[] { false, true })
        {
            var root = Root(); var evidence = Evidence(root); var command = Command(); _ = evidence.Begin(command);
            var path = Directory.EnumerateFiles(root, "*.json", SearchOption.AllDirectories).Single();
            var text = File.ReadAllText(path);
            text = duplicate ? text.Replace("\"MayStillRun\":false", "\"MayStillRun\":false,\"MayStillRun\":false", StringComparison.Ordinal)
                : text.Replace("\"MayStillRun\":false,", "", StringComparison.Ordinal);
            File.WriteAllText(path, text);
            Check.Pesto(() => evidence.Read(command.ReceiptId), "entra.evidence", "closed required liveness field");
            Check.False(evidence.ReadBarrier(command.ReceiptId).CanAcknowledge, "malformed process proof stays blocking");
        }
    }

    [Test]
    public void LongOuDoesNotLeakIntoTheNativeCommandLine()
    {
        var command = Command();
        var large = command with { ReceiptId = new string('r', 128),
            Request = command.Request with { Kind = "renameMove", Domain = new string('d', 253), SourceOu = "OU=" + new string('x', 2000) } };
        var script = PowerShellEntraWorker.Build(large);
        var encoded = System.Text.RegularExpressions.Regex.Match(script, @"FromBase64String\('([A-Za-z0-9+/=]+)'\)").Groups[1].Value;
        using var payload = JsonDocument.Parse(Convert.FromBase64String(encoded));
        Check.False(payload.RootElement.GetProperty("Request").TryGetProperty("SourceOu", out _), "OU is local plan data, not needed by dsregcmd worker");
        Check.True(EntraLeaveTask.FitsNativeCommand(new string('w', 2048), EntraLeaveTask.WorkerArguments(script)),
            "maximum closed payload and long Windows path fit the real command-line bound");
        Check.True(EntraLeaveTask.FitsNativeCommand(new string('w', 2048), EntraLeaveTask.WorkerArguments(script.Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace("\n", "\r\n", StringComparison.Ordinal))), "Windows source line endings fit the same bound");
    }

    [Test]
    public void OversizedWorkerIsRefusedBeforeTaskRegistration()
    {
        var transport = new Transport();
        using var credential = new PestoAdCredential("EXAMPLE\\operator", "fixture-secret");
        var result = new EntraLeaveTask(transport).Run(Command(), new string('x', 14000), credential,
            (_, _, _, _) => throw new TestFailureException("No dispatch evidence before a rejected command"));
        Check.Equal("NotRequested", result.Effect, "command cannot have reached a native process");
        Check.False(result.MayStillRun, "no process launched");
        Check.Equal(0, transport.Registers, "no oversized task registration");
        Check.Equal(0, transport.Runs, "no oversized task start");
    }

    [Test]
    public void ActualGatewayReceiptRoundtripsWithEntraEffectAndCannotFinalizeAsNoEffectFailure()
    {
        var gp = Root(); var config = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        var command = Command(EntraLeaveEvidence.Digest(File.ReadAllBytes(V1Config.ConfigPathOf(config)!)));
        var now = DateTimeOffset.UtcNow;
        var auth = new EntraRenameAuthorization("fixture-auth", command.Request, "hybrid", "HybridOnly", Machine, now, now.AddMinutes(5));
        var request = new MutationRequest("rename", Computer, AdGuid, NewName, Ou, "example.local", null,
            command.PlanId, command.ReceiptId, Ou, ConfigurationSha256: command.Request.ConfigurationSha256, Entra: auth, EntraLeaveConfirmed: true);
        var gateway = new PowerShellMutationGateway(config, receiptGpRoot: gp);
        var baselineType = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.NativeReceiptSnapshot")!;
        var values = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase)
        {
            ["BootUtc"] = now.AddHours(-1), ["MachineId"] = Machine, ["ActiveName"] = Computer, ["ConfiguredName"] = Computer,
            ["Domain"] = "example.local", ["PartOfDomain"] = true, ["SecureChannel"] = true, ["AdGuid"] = AdGuid,
            ["AdName"] = Computer, ["AdOu"] = Ou, ["AdProtected"] = false, ["DomainController"] = false, ["DomainRole"] = 1
        };
        var constructor = baselineType.GetConstructors().Single();
        var baseline = constructor.Invoke(constructor.GetParameters().Select(p => values.GetValueOrDefault(p.Name!)).ToArray());
        var path = (string)typeof(PowerShellMutationGateway).GetMethod("WritePreSendReceipt", BindingFlags.NonPublic | BindingFlags.Instance)!
            .Invoke(gateway, [request, baseline])!;
        using (var sent = JsonDocument.Parse(File.ReadAllBytes(path)))
            Check.Equal("Requested", sent.RootElement.GetProperty("Entra").GetString(), "real gateway writes effect intent before leave");
        var evidence = Evidence(gp); var result = new EntraLeaveTransaction(evidence).Execute(command, new Native(evidence, new Transport()));
        Check.Equal("Confirmed", result.Effect, "fixture leave confirmed through actual transaction format");
        gateway.PersistFinalReceipt(request, new(MutationStatus.Failed, 21, "Rename refused", false));
        using var final = JsonDocument.Parse(File.ReadAllBytes(path));
        Check.Equal("Uncertain", final.RootElement.GetProperty("Phase").GetString(), "actual finalizer never advertises no effect");
        Check.Equal("Confirmed", final.RootElement.GetProperty("Entra").GetString(), "effect survives finalization");
        Check.Equal(evidence.Read(command.ReceiptId)!.Sha256, final.RootElement.GetProperty("EntraEvidenceSha256").GetString(), "real linked evidence hash");
        Check.True(gateway.ReadEntraBarrier(command.ReceiptId).CanAcknowledge, "native reader validates actual receipt and evidence binding");
        var history = GpHistory.Read(gp);
        Check.Equal(0, history.InvalidCount, "actual gateway format accepted by actual history reader");
        Check.Equal("uncertain", history.Entries.Single().Receipt.Status, "history does not invent success");
    }
}

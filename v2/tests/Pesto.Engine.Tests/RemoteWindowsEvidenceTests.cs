using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal static class WindowsEvidenceFixture
{
    public const string Computer = "P111301PAINF009", NewName = "P111301PAINF010", Domain = "example.local", Dc = "dc01.example.local";
    public const string AdGuid = "11111111-1111-1111-1111-111111111111", Machine = "22222222-2222-2222-2222-222222222222";
    public const string Ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local", OuGuid = "33333333-3333-3333-3333-333333333333";
    public static DateTimeOffset Now => new FixedClock().GetUtcNow();
    public static RemoteWindowsEvidenceRequest Request(string purpose = "baseline", string? id = null, string? sha = null) =>
        new(id ?? "receipt-proof", purpose == "reconciliation" ? NewName : Computer, Domain, Dc, AdGuid,
            purpose == "baseline" ? null : Machine, purpose == "baseline" ? null : sha ?? new string('a', 64), purpose,
            purpose == "reconciliation" ? NewName : Computer, purpose is "reconciliation" or "restart" ? NewName : Computer);
    public static byte[] Result(RemoteWindowsEvidenceRequest request, string nonce, DateTimeOffset? boot = null) => JsonSerializer.SerializeToUtf8Bytes(
        new RemoteWindowsSnapshot(1, nonce, RemoteWindowsEvidenceProtocol.RequestHash(request, nonce), request.ReceiptId,
            request.ExpectedAdGuid, "S-1-5-18", request.ExpectedActiveName, request.ExpectedConfiguredName, request.Domain,
            true, 1, Machine, boot ?? Now.AddHours(-1), Now, true));
    public static RemoteWindowsProof Proof(RemoteWindowsEvidenceRequest request, DateTimeOffset? boot = null)
    {
        const string nonce = "aaaabbbbccccddddeeeeffff11112222"; var bytes = Result(request, nonce, boot);
        return new(1, request, nonce, RemoteWindowsEvidenceProtocol.TaskName(nonce), new string('d', 64),
            RemoteWindowsEvidenceProtocol.Hash(bytes), Encoding.UTF8.GetString(bytes), Now, true);
    }
    public static string Root() => Path.Combine(Path.GetTempPath(), "pesto-windows-proof-" + Guid.NewGuid().ToString("N"));
}

internal sealed class RemoteWindowsEvidenceTests
{
    private sealed class Transport : ISystemDiagnosticTaskTransport
    {
        public int Runs, Deletes, Registers; public string Xml = "";
        public bool ThrowRun, Tamper, AlreadyRun, MissingRunTime, DeleteFailure; public int State = 3; public long Code;
        public void RegisterSystem(string computer, string taskName, string xml, string connectionPrincipal, string connectionPassword)
        { Registers++; Xml = xml; Check.Equal("EXAMPLE\\operator", connectionPrincipal, "Explicit account only"); Check.False(xml.Contains(connectionPassword, StringComparison.Ordinal), "No credential in task definition"); }
        public void Register(string computer, string taskName, string xml, string principal, string? password) => throw new TestFailureException("SYSTEM registration required");
        public void Run(string computer, string taskName) { Runs++; if (ThrowRun) throw new IOException("Lost RPC reply"); }
        public TaskProbeResult Probe(string computer, string taskName) => new(Runs == 0 ? 3 : State, Code,
            AlreadyRun || Runs > 0 && !MissingRunTime ? WindowsEvidenceFixture.Now : null,
            Tamper ? Xml.Replace("S-1-5-18", "S-1-5-19", StringComparison.Ordinal) : Xml);
        public void Delete(string computer, string taskName) { Deletes++; if (DeleteFailure) throw new IOException("Unknown delete"); }
        public string? ReadTaskLogTail(string computer, string path) => throw new TestFailureException("No arbitrary remote log read");
    }
    private sealed class Files(RemoteWindowsEvidenceRequest request, string root) : IRemoteWindowsEvidenceFiles
    {
        public int Reads, Deletes; public bool Alter = false, FailDelete; public byte[]? Bytes;
        public byte[] Read(string computer, string nonce)
        {
            Reads++; Check.Equal(request.Computer, computer, "Exact computer");
            Bytes = WindowsEvidenceFixture.Result(request, nonce);
            if (Alter) { var node = JsonNode.Parse(Bytes)!; node["MachineId"] = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"; Bytes = JsonSerializer.SerializeToUtf8Bytes(node); }
            return Bytes;
        }
        public void DeleteExact(string computer, string nonce, string hash)
        {
            Deletes++;
            Check.Equal(RemoteWindowsEvidenceProtocol.Hash(Bytes!), hash, "Cleanup bound to exact result bytes");
            var saved = Directory.GetFiles(Path.Combine(root, "V2", "windows-proofs"), "*.result.json");
            Check.Equal(1, saved.Length, "Durable local result exists BEFORE any remote cleanup");
            Check.Contains(hash, File.ReadAllText(saved[0]), "Durable proof contains returned SHA");
            if (FailDelete) throw new IOException("Exact deletion not confirmed");
        }
    }
    private static RemoteWindowsEvidenceResult Run(Transport transport, Files files, string root, RemoteWindowsEvidenceRequest request)
    {
        using var credential = new PestoAdCredential("EXAMPLE\\operator", "fixture-windows-proof-secret");
        return new RemoteWindowsDiagnosticTask(transport, files, root, new FixedClock(), 1, 0).Read(request, credential);
    }

    [Test]
    public void CompleteSystemProofIsSavedBeforeExactRemoteCleanupAndContainsNoSecret()
    {
        var root = WindowsEvidenceFixture.Root(); var request = WindowsEvidenceFixture.Request(); var transport = new Transport(); var files = new Files(request, root);
        var result = Run(transport, files, root, request);
        Check.True(result.Proof is not null && result.Proof.CleanupConfirmed, "Complete native lifecycle");
        Check.False(result.Uncertain, "No unconfirmed lifecycle step");
        Check.Equal(1, transport.Runs, "One run only"); Check.Equal(1, transport.Deletes, "Exact stopped task deleted"); Check.Equal(1, files.Deletes, "Exact result deleted");
        Check.Equal(WindowsEvidenceFixture.Machine, RemoteWindowsEvidenceProtocol.ValidateProof(result.Proof!).MachineId, "MachineGuid transported without local substitution");
        Check.False(string.Join("", Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Select(File.ReadAllText))
            .Contains("fixture-windows-proof-secret", StringComparison.Ordinal), "No secret in any journal");
    }

    [Test]
    public void LostReplyActiveTaskAndMissingRunTimeNeverYieldProofOrCleanup()
    {
        foreach (var transport in new[] { new Transport { ThrowRun = true }, new Transport { State = 4 }, new Transport { MissingRunTime = true }, new Transport { Code = 267009 } })
        {
            var root = WindowsEvidenceFixture.Root(); var request = WindowsEvidenceFixture.Request(); var files = new Files(request, root);
            var result = Run(transport, files, root, request);
            Check.Null(result.Proof, "No evidence invented"); Check.True(result.Uncertain, "Uncertain lifecycle explicit");
            Check.Equal(1, transport.Runs, "Never replay"); Check.Equal(0, transport.Deletes, "Unknown task retained"); Check.Equal(0, files.Reads, "No result read without task completion");
        }
    }

    [Test]
    public void ModifiedPreexistingDefinitionCannotRunAndCleanupFailureCannotAuthorizeAnything()
    {
        foreach (var transport in new[] { new Transport { Tamper = true }, new Transport { AlreadyRun = true }, new Transport { DeleteFailure = true } })
        {
            var root = WindowsEvidenceFixture.Root(); var request = WindowsEvidenceFixture.Request(); var files = new Files(request, root);
            Check.Null(Run(transport, files, root, request).Proof, "No usable proof after unsafe definition or cleanup");
            if (transport.Tamper || transport.AlreadyRun) Check.Equal(0, transport.Runs, "Preexisting or altered task never runs");
        }
        var dir = WindowsEvidenceFixture.Root(); var req = WindowsEvidenceFixture.Request();
        Check.Null(Run(new Transport(), new Files(req, dir) { FailDelete = true }, dir, req).Proof, "Result cleanup is also mandatory");
    }

    [Test]
    public void WrongNonceSystemMachineDomainAndClosedSchemaAreRejected()
    {
        var request = WindowsEvidenceFixture.Request("reconciliation"); const string nonce = "aaaabbbbccccddddeeeeffff11112222";
        var good = JsonNode.Parse(WindowsEvidenceFixture.Result(request, nonce))!.AsObject();
        Action<JsonObject>[] changes = [r => r["Nonce"] = new string('b', 32), r => r["RequestSha256"] = new string('b', 64),
            r => r["ReceiptId"] = "other", r => r["MachineId"] = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", r => r["SystemSid"] = "S-1-5-19",
            r => r["Domain"] = "other.local", r => r["ActiveName"] = "OTHER-PC", r => r["DomainRole"] = 5,
            r => r["BootUtc"] = WindowsEvidenceFixture.Now.AddDays(1), r => r["PartOfDomain"] = false, r => r["Extra"] = true];
        foreach (var change in changes)
        {
            var value = good.DeepClone().AsObject(); change(value);
            Check.Pesto(() => RemoteWindowsEvidenceProtocol.ReadResult(request, nonce, JsonSerializer.SerializeToUtf8Bytes(value)), "receipt.remote_evidence", "Identity and closed shape checked");
        }
        var duplicate = good.ToJsonString().Replace("\"Schema\":1", "\"Schema\":1,\"Schema\":1", StringComparison.Ordinal);
        Check.Pesto(() => RemoteWindowsEvidenceProtocol.ReadResult(request, nonce, Encoding.UTF8.GetBytes(duplicate)), "receipt.remote_evidence", "Duplicate property refused");
    }

    [Test]
    public void AProofCannotBeReboundToChangedReceiptBytesOrMarkedLocal()
    {
        var request = WindowsEvidenceFixture.Request("reconciliation"); var proof = WindowsEvidenceFixture.Proof(request);
        Check.Pesto(() => RemoteWindowsEvidenceProtocol.ValidateProof(proof with { Request = request with { ReceiptSha256 = new string('b', 64) } }), "receipt.remote_evidence", "No rehashing a result under a different parent");
        Check.Pesto(() => RemoteWindowsEvidenceProtocol.ValidateProof(proof with { CleanupConfirmed = false }), "receipt.remote_evidence", "Cleanup never presumed");
        Check.Pesto(() => RemoteWindowsEvidenceProtocol.ValidateProof(proof with { ResultJson = proof.ResultJson + " " }), "receipt.remote_evidence", "Exact byte digest");
    }

    [Test]
    public void ClosedPathsAndScriptRequireExclusiveSystemResultAndStableKernelBoot()
    {
        var script = RemoteWindowsDiagnosticTask.Script(WindowsEvidenceFixture.Request(), new string('a', 32));
        foreach (var required in new[] { "Get-PestoStableBootUtc", "[IO.FileMode]::CreateNew", "SetAccessRuleProtection($true,$false)",
            "SetOwner($system)", "[IO.FileShare]::None", "$output.Flush($true)", "ReparsePoint", "S-1-5-18", "ExpectedMachineId" })
            Check.Contains(required, script, "Mandatory native guard");
        foreach (var forbidden in new[] { "Restart-Computer", "Rename-Computer", "Add-Computer", "Move-ADObject", "Import-Module", "/leave", "LastBootUpTime", "-Repair" })
            Check.False(script.Contains(forbidden, StringComparison.OrdinalIgnoreCase), "Reader never mutates: " + forbidden);
        Check.Equal("\\\\" + WindowsEvidenceFixture.Computer + "\\ADMIN$\\Temp\\PestoEvidence-" + new string('a', 32) + ".json",
            WindowsRemoteEvidenceFiles.PathFor(WindowsEvidenceFixture.Computer, new string('a', 32)), "One generated administrative-share path");
        var refused = false; try { _ = WindowsRemoteEvidenceFiles.PathFor("..\\other", new string('a', 32)); } catch (ArgumentException) { refused = true; }
        Check.True(refused, "Arbitrary target/path rejected");
    }

    [Test]
    public void LargestClosedRemoteRequestStillFitsTheActualWindowsCommandLine()
    {
        var domain = new string('a', 247) + ".local";
        var request = WindowsEvidenceFixture.Request("reconciliation", new string('r', 128)) with { Domain = domain, Dc = domain };
        var script = RemoteWindowsDiagnosticTask.Script(request, new string('a', 32));
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        Check.True(encoded.Length + 100 < 30000, "The actual generated script fits with process-path/arguments margin");
        var bootstrap = PowerShellMutationGateway.WorkerBootstrap;
        Check.True(Convert.ToBase64String(Encoding.Unicode.GetBytes(bootstrap)).Length < 8000, "Large mutation script never enters the command line");
        Check.Contains("ReadLine()", bootstrap, "Bootstrap waits for the owned input stream");
        Check.Contains(Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(PowerShellMutationGateway.ConstantScript))), bootstrap, "Bootstrap pins exactly the compiled mutation body");
    }
}

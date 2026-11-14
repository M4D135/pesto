using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;
using Pesto.Engine.Live;

// One bounded invocation, one evidence directory, at most one native operation. No reboot/unjoin/replay.
internal static partial class Program
{
    private const string LabUuid = "9b2ad4f0-0506-4f58-aed2-c43ac1973516";
    private static string Domain => LabDomain.Name;
    private static readonly JsonSerializerOptions Json = new(PestoJson.Options) { WriteIndented = true, UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };
    private static string output = "";
    private static int step;

    private static async Task<int> Main(string[] args)
    {
        if (!OperatingSystem.IsWindows()) { Console.Error.WriteLine("Windows lab VM required; no simulation fallback."); return 2; }
        if (args.Length != 1) { Console.Error.WriteLine("Usage: Pesto.AdQualification.exe <request.json>"); return 2; }
        try
        {
            var request = JsonSerializer.Deserialize<Request>(File.ReadAllText(args[0]).Replace("@LABO_DN@", LabDomain.Dn), Json) ?? throw new InvalidOperationException("Request missing.");
            if (!Path.IsPathFullyQualified(request.V1Root) || !Path.IsPathFullyQualified(request.OutputRoot)) throw new InvalidOperationException("Absolute V1Root and OutputRoot required.");
            if (request.Action is not ("read" or "negative" or "move" or "rename" or "renameMove" or "join" or "reconcile" or "restoreName" or "inspect")) throw new InvalidOperationException("Undeclared action.");
            if (request.Execute && (request.Confirmation != (request.Action == "restoreName" ? RestoreNamePolicy.Confirmation : "EXECUTE PESTO CANARY") || request.ReturnPlan.Length < 20)) throw new InvalidOperationException("Explicit canary confirmation and concrete return plan required.");
            output = Path.Combine(request.OutputRoot, DateTimeOffset.UtcNow.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(output);
            Save("request", request);
            var identity = RunPowerShell(IdentityScript, new { });
            Save("identity", identity);
            if (!string.Equals(identity["uuid"]?.GetValue<string>(), LabUuid, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Wrong VM BIOS UUID: no AD operation allowed.");
            if (!string.Equals(identity["computer"]?.GetValue<string>(), request.ExpectedComputer, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Machine name changed: new reviewed request required.");
            if (identity["domainRole"]!.GetValue<int>() >= 4) throw new InvalidOperationException("Domain controllers are excluded.");
            if (identity["partOfDomain"]!.GetValue<bool>() && !string.Equals(identity["domain"]!.GetValue<string>(), Domain, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Unexpected domain.");
            using var credentials = request.ExplicitCredential ? WindowsAdCredentialSource.Prompt() : null;
            if (request.ExplicitCredential && credentials is null) throw new InvalidOperationException("Credential selection cancelled.");
            var directory = new PowerShellDirectoryGateway(credentials, request.V1Root);
            var mutation = new PowerShellMutationGateway(request.V1Root, credentials);
            var backend = PestoBackend.CreateLive(request.V1Root, directory, mutation);
            var session = await Call(backend, "session.info");
            if (!string.Equals(session["domain"]?.GetValue<string>(), Domain, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("V1 config domain is not " + Domain + ".");
            Save("config-hash", new { path = Path.Combine(V1ConfigDirectory.Resolve(request.V1Root)!, "cfg.json"), sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(V1ConfigDirectory.Resolve(request.V1Root)!, "cfg.json")))) });
            await Call(backend, "settings.get");
            await Call(backend, "directory.sites");
            await Call(backend, "directory.services", new { site = request.Site });
            await Call(backend, "diagnostics.read");
            await Call(backend, "dashboard.read");
            if (request.Action == "read") return 0;
            if (request.Action == "restoreName") return RestoreName(request, backend, session, directory, mutation, credentials, identity);
            if (request.Action == "reconcile")
            {
                if (!request.Execute || request.ReceiptId.Length == 0) throw new InvalidOperationException("Explicit execute confirmation and receiptId required for reconciliation.");
                var before = await Call(backend, "receipts.get", new { id = request.ReceiptId });
                if (!string.Equals(before["computer"]?.GetValue<string>(), request.Computer, StringComparison.OrdinalIgnoreCase)
                    && !string.Equals(before["newName"]?.GetValue<string>(), request.Computer, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Receipt does not belong to the approved canary.");
                var verification = await Call(backend, "receipts.reconcile", new { id = request.ReceiptId });
                Save("local-after-verification", RunPowerShell(IdentityScript, new { }));
                return verification["verified"]?.GetValue<bool>() == true ? 0 : 20;
            }

            string? observedGuid = null;
            JsonNode? independentBefore = null;
            if (request.Action != "join")
            {
                var observed = directory.FindComputer(Domain, session["dc"]?.GetValue<string>(), request.Computer)
                    ?? throw new InvalidOperationException("Canary computer not found.");
                Save("canary-before", observed);
                if (!Guid.TryParse(request.ExpectedGuid, out var expected) || !Guid.TryParse(observed.Guid, out var actual) || expected != actual) throw new InvalidOperationException("Canary GUID not confirmed.");
                if (string.IsNullOrWhiteSpace(request.ExpectedSourceOu) || !string.Equals(observed.Ou, request.ExpectedSourceOu, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Source OU changed: review required.");
                observedGuid = observed.Guid;
                if (request.Action is "rename" or "renameMove" && !string.Equals(request.Computer, request.ExpectedComputer, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Harness renames only the identified VM, never remote machines.");
                independentBefore = Snapshot(session, observedGuid!, credentials, request.V1Root);
                Save("independent-before", independentBefore);
                if ((independentBefore["userAccountControl"]!.GetValue<long>() & 8192) != 0) throw new InvalidOperationException("Domain controller can never be a canary.");
            }
            if (request.Action == "inspect")
            {
                if (request.Computer != request.ExpectedComputer || identity["partOfDomain"]?.GetValue<bool>() != true
                    || identity["secureChannel"]?.GetValue<bool>() != true || identity["pendingRename"]?.GetValue<bool>() != false
                    || !string.Equals(identity["activeName"]?.GetValue<string>(), request.ExpectedComputer, StringComparison.OrdinalIgnoreCase)
                    || !string.Equals(identity["configuredName"]?.GetValue<string>(), request.ExpectedComputer, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Inspection cannot confirm the expected local name, membership or secure channel.");
                await Call(backend, "receipts.list");
                Save("result", new { status = "observedOnly", nativeWrite = false });
                return 0;
            }
            if (request.Action == "negative")
            {
                await Expect(backend, "operation.prepare", new { kind = "join", computer = "OTHER-CANARY" }, "join.localOnly");
                await Expect(backend, "operation.prepare", new { kind = "rename", computer = request.Computer }, "preview.missing");
                await Expect(backend, "operation.prepare", new { kind = "move", computer = request.Computer, targetOU = "OU=NeverConfigured,DC=invalid" }, "site.invalid");
                var safePlan = await Call(backend, "operation.prepare", new { kind = "move", computer = request.Computer, targetOU = request.TargetOu });
                await Expect(backend, "operation.execute", new { planId = safePlan["planId"]!.GetValue<string>(), confirmationName = "WRONG-CONFIRMATION" }, "confirmation.invalid");
                return 0;
            }

            JsonNode? preview = null;
            if (request.Action != "move")
            {
                var facets = new JsonObject { ["type"] = request.Type, ["site"] = request.Site, ["service"] = request.Service };
                if (request.Action != "join") facets["computer"] = request.Computer;
                preview = await Call(backend, "names.preview", facets);
                if (!preview["complete"]!.GetValue<bool>()) throw new InvalidOperationException("Incomplete naming inventory.");
                if (directory.FindComputer(Domain, session["dc"]?.GetValue<string>(), preview["name"]!.GetValue<string>()) is not null) throw new InvalidOperationException("Calculated name is already taken.");
                if (!string.Equals(preview["ou"]!.GetValue<string>(), request.TargetOu, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Calculated destination differs from approved OU.");
            }
            var operation = new JsonObject { ["kind"] = request.Action, ["computer"] = request.Action == "join" ? request.ExpectedComputer : request.Computer };
            if (preview is not null) operation["previewId"] = preview["previewId"]!.GetValue<string>();
            if (request.Action is "move" or "renameMove") operation["targetOU"] = request.TargetOu;
            var plan = await Call(backend, "operation.prepare", operation);
            if (!string.Equals(plan["targetOU"]!.GetValue<string>(), request.TargetOu, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Plan destination differs from approved OU.");
            Save("return-plan", new { request.ReturnPlan, beforeName = request.Computer, observedGuid, beforeOu = request.ExpectedSourceOu, proposedName = plan["newName"]!.GetValue<string>(), noAutomaticReboot = true });
            if (!request.Execute) { Save("result", new { status = "preparedOnly", nativeWrite = false }); return 0; }
            if (!identity["elevated"]!.GetValue<bool>()) throw new InvalidOperationException("Elevated lab session required for durable receipts.");
            if (identity["pendingRename"]!.GetValue<bool>()) throw new InvalidOperationException("Pending rename requires separate readback/reboot review.");
            var receipt = await Call(backend, "operation.execute", new { planId = plan["planId"]!.GetValue<string>(), confirmationName = plan["confirmationName"]!.GetValue<string>() });
            await Expect(backend, "operation.execute", new { planId = plan["planId"]!.GetValue<string>(), confirmationName = plan["confirmationName"]!.GetValue<string>() }, "plan.consumed");
            await Call(backend, "receipts.get", new { id = receipt["id"]!.GetValue<string>() });
            var receiptPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GP", "V2", "receipts", receipt["id"]!.GetValue<string>() + ".json");
            if (File.Exists(receiptPath))
            {
                var bytes = File.ReadAllBytes(receiptPath);
                if (bytes.Length > 65536) throw new InvalidOperationException("Durable receipt unexpectedly oversized.");
                Save("durable-receipt", new { path = receiptPath, sha256 = Convert.ToHexString(SHA256.HashData(bytes)), receipt = JsonNode.Parse(bytes) });
            }
            else Save("durable-receipt", new { path = receiptPath, missing = true });
            if (observedGuid is null && request.Action == "join")
                observedGuid = directory.FindComputer(Domain, session["dc"]?.GetValue<string>(), plan["newName"]!.GetValue<string>())?.Guid;
            if (observedGuid is not null)
            {
                var independentAfter = Snapshot(session, observedGuid, credentials, request.V1Root);
                Save("independent-after", independentAfter);
                if (independentBefore is not null && independentAfter["protected"]!.GetValue<bool>() != independentBefore["protected"]!.GetValue<bool>())
                    throw new InvalidOperationException("Original AD deletion protection was not restored; manual repair required, no replay.");
            }
            Save("local-after", RunPowerShell(IdentityScript, new { }));
            await Call(backend, "receipts.list");
            await Call(backend, "logs.list");
            return receipt["status"]!.GetValue<string>() switch { "succeeded" => 0, "pendingRestart" => 10, _ => 20 };
        }
        catch (Exception ex)
        {
            // Inputs/credentials/raw PowerShell stderr are never copied to error evidence.
            var error = new { type = ex.GetType().Name, code = ex is PestoException pesto ? pesto.Code : "qualification.failed", message = ex.Message };
            if (output.Length > 0) Save("failure", error);
            Console.Error.WriteLine(JsonSerializer.Serialize(error, Json));
            return 2;
        }
        finally { if (output.Length > 0) Console.WriteLine(output); }
    }

    private static void Save(string label, object? value) => File.WriteAllText(Path.Combine(output, (++step).ToString("D3") + "-" + label.Replace('.', '-') + ".json"), JsonSerializer.Serialize(value, Json), new UTF8Encoding(false));
    private static async Task<JsonNode> Call(IPestoBackend backend, string op, object? args = null)
    {
        var node = JsonSerializer.SerializeToNode(await backend.InvokeAsync(op, PestoJson.Element(args ?? new { })), PestoJson.Options)!;
        Save(op, node); return node;
    }
    private static async Task Expect(IPestoBackend backend, string op, object args, string code)
    {
        try { await backend.InvokeAsync(op, PestoJson.Element(args)); }
        catch (PestoException ex) when (ex.Code == code) { Save("negative", new { op, expected = code, observed = ex.Code }); return; }
        throw new InvalidOperationException("Expected refusal absent: " + code);
    }
    private static JsonNode Snapshot(JsonNode session, string guid, IWindowsCredentialSource? credentials, string v1Root) => RunPowerShell(SnapshotScript,
        new { server = session["dc"]?.GetValue<string>() ?? Domain, guid, credential = credentials?.CreateProtectedPayload(), module = TrustedActiveDirectoryModule.Resolve(v1Root) });
    private static JsonNode RunPowerShell(string script, object input)
    {
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = new UTF8Encoding(false) };
        foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-EncodedCommand", Convert.ToBase64String(Encoding.Unicode.GetBytes(script)) }) start.ArgumentList.Add(arg);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("PowerShell not started.");
        var stdout = process.StandardOutput.ReadToEndAsync();
        var stderr = process.StandardError.ReadToEndAsync();
        process.StandardInput.Write(JsonSerializer.Serialize(input, PestoJson.Options)); process.StandardInput.Close();
        if (!process.WaitForExit(45000)) { process.Kill(true); throw new InvalidOperationException("Readback timeout; no replay."); }
        var text = stdout.GetAwaiter().GetResult(); stderr.GetAwaiter().GetResult();
        if (process.ExitCode != 0 || text.Length > 65536) throw new InvalidOperationException("Independent readback failed; inspect separately, no replay.");
        return JsonNode.Parse(text) ?? throw new InvalidOperationException("Readback JSON missing.");
    }

    private const string IdentityScript = """
$ErrorActionPreference='Stop'
$cs=Get-CimInstance Win32_ComputerSystem
$uuid=[string](Get-CimInstance Win32_ComputerSystemProduct).UUID
$active=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
$configured=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
$principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$channel=$null;if($cs.PartOfDomain){try{$channel=[bool](Test-ComputerSecureChannel -ErrorAction Stop)}catch{}}
@{uuid=$uuid;secureChannel=$channel;computer=$env:COMPUTERNAME;domain=[string]$cs.Domain;partOfDomain=[bool]$cs.PartOfDomain;domainRole=[int]$cs.DomainRole;activeName=$active;configuredName=$configured;pendingRename=($active -ine $configured);elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);bootUtc=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')}|ConvertTo-Json -Compress
""";
    private const string SnapshotScript = """
$ErrorActionPreference='Stop'
$j=[Console]::In.ReadToEnd()|ConvertFrom-Json
$p=@{Server=[string]$j.server};$bytes=$null;$secure=$null
try{
 if($j.module){Import-Module -Name ([string]$j.module) -ErrorAction Stop}else{throw 'Module AD Microsoft connu absent.'}
 if($j.credential){
  Add-Type -AssemblyName System.Security
  $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String([string]$j.credential.blob),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $secure=New-Object Security.SecureString
  for($i=0;$i -lt $bytes.Length;$i+=2){$secure.AppendChar([char]([int]$bytes[$i] -bor ([int]$bytes[$i+1] -shl 8)))}
  $secure.MakeReadOnly();$p.Credential=New-Object Management.Automation.PSCredential([string]$j.credential.userName,$secure)
 }
 $pc=Get-ADComputer -Identity ([Guid]$j.guid) -Properties ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion,userAccountControl,DNSHostName @p
 @{name=[string]$pc.Name;guid=[string]$pc.ObjectGUID;dn=[string]$pc.DistinguishedName;protected=[bool]$pc.ProtectedFromAccidentalDeletion;userAccountControl=[long]$pc.userAccountControl;dns=[string]$pc.DNSHostName;utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress
}finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)};if($secure){$secure.Dispose()}}
""";
    private sealed record Request(string V1Root, string OutputRoot, string ExpectedComputer, string Action, string Computer,
        string ExpectedGuid, string ExpectedSourceOu, string TargetOu, string Site, string Service, string Type,
        bool Execute = false, bool ExplicitCredential = false, string Confirmation = "", string ReturnPlan = "", string ReceiptId = "",
        string ReturnMoveReceiptId = "");
}

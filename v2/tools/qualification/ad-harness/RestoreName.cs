using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;
using Pesto.Engine.Live;

internal static partial class Program
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static int RestoreName(Request request, IPestoBackend backend, JsonNode session, PowerShellDirectoryGateway directory,
        PowerShellMutationGateway mutation, WindowsAdCredentialSource? credentials, JsonNode identity)
    {
        if (request.ExpectedGuid != RestoreNamePolicy.Guid || request.ExpectedSourceOu != RestoreNamePolicy.Paris
            || request.TargetOu != RestoreNamePolicy.Paris || request.Computer != request.ExpectedComputer)
            throw new InvalidOperationException("Restore request must name the recorded identity and unchanged Paris OU.");
        using var mutex = new Mutex(false, "Global\\GP_PostMutation_v1");
        var owned = false;
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw new InvalidOperationException("Another Pesto operation is active; restore refused.");
            var gpRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GP");
            RestoreV1Barriers.RequireClear(gpRoot);
            using var rawReceipts = request.ReceiptId == RestoreRenameMovePolicy.SourceReceiptId
                ? RestoreRenameMoveReceiptGate.Open(gpRoot, request.ReceiptId, request.ReturnMoveReceiptId)
                : request.ReturnMoveReceiptId.Length == 0 ? null
                : throw new InvalidOperationException("A return-move receipt is only valid for the recorded renameMove campaign.");
            var source = Call(backend, "receipts.get", new { id = request.ReceiptId }).GetAwaiter().GetResult();
            RestoreRenameMoveProof? renameMove = null;
            RestoreRenameMoveProof? returnMove = null;
            if (Text(source, "kind") == "renameMove")
            {
                if (rawReceipts is null)
                    throw new InvalidOperationException("Only the recorded renameMove campaign with a verified return-move receipt can be restored.");
                (renameMove, returnMove) = rawReceipts.Observe(id => RestoreProof(mutation.ReadReconciliation(id)));
                RestoreRenameMovePolicy.RequireUnchanged(renameMove, returnMove, rawReceipts.SourceHash, rawReceipts.ReturnHash);
                Save("rename-move-return-proof", new { source = renameMove, returned = returnMove });
            }
            else if (request.ReturnMoveReceiptId.Length != 0)
                throw new InvalidOperationException("A return-move receipt is only valid for the recorded renameMove campaign.");
            var history = Call(backend, "receipts.list").GetAwaiter().GetResult();
            var dashboard = Call(backend, "dashboard.read").GetAwaiter().GetResult();
            if (dashboard["history"]?["readable"]?.GetValue<bool>() != true || history["invalidCount"]?.GetValue<int>() != 0
                || history["truncated"]?.GetValue<bool>() != false)
                throw new InvalidOperationException("Complete readable durable history required; no barrier bypass.");
            var observed = directory.FindComputer(Domain, session["dc"]?.GetValue<string>(), request.Computer)
                ?? throw new InvalidOperationException("Current canary object missing.");
            var before = Snapshot(session, RestoreNamePolicy.Guid, credentials, request.V1Root);
            Save("restore-before", before);
            var observation = new RestoreObservation(Text(identity, "uuid"), observed.Guid ?? "", Text(identity, "computer"),
                Text(identity, "activeName"), Text(identity, "configuredName"), Text(identity, "domain"),
                identity["partOfDomain"]?.GetValue<bool>() == true, identity["domainRole"]!.GetValue<int>(),
                identity["elevated"]?.GetValue<bool>() == true, identity["secureChannel"]?.GetValue<bool>() == true,
                Text(before, "name"), observed.Ou ?? "", before["protected"]!.GetValue<bool>(), before["userAccountControl"]!.GetValue<long>(),
                directory.FindComputer(Domain, session["dc"]?.GetValue<string>(), RestoreNamePolicy.OriginalName) is null,
                request.ReceiptId, Text(source, "kind"), Text(source, "status"), Text(source, "computer"), Text(source, "newName"),
                source["restartRequired"]?.GetValue<bool>() != false, request.ExplicitCredential && credentials is not null,
                request.Confirmation, request.ReturnPlan, renameMove is not null);
            RestoreNamePolicy.Validate(observation);
            var retained = RestoreHistoryPolicy.Validate(history, request.Computer,
                DateTimeOffset.Parse(Text(identity, "bootUtc"), System.Globalization.CultureInfo.InvariantCulture),
                DateTimeOffset.Parse(Text(source, "time"), System.Globalization.CultureInfo.InvariantCulture));
            Save("historical-restarts-retained", retained);
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GP", "Qualification", "RestoreName");
            var path = Path.Combine(folder, request.ReceiptId + ".json");
            NoLinks(path);
            if (File.Exists(path)) throw new InvalidOperationException("This restore was already reserved or attempted; inspect its receipt, never replay.");
            Save("restore-plan", new { originalName = RestoreNamePolicy.OriginalName, currentName = request.Computer,
                expectedGuid = RestoreNamePolicy.Guid, sourceReceipt = request.ReceiptId, durableReceipt = path,
                request.ReturnPlan, returnMoveReceipt = returnMove?.Id, noReboot = true, noReplay = true });
            if (!request.Execute) { Save("result", new { status = "preparedOnly", nativeWrite = false }); return 0; }
            Directory.CreateDirectory(folder);
            NoLinks(folder);
            var acl = new DirectorySecurity();
            acl.SetAccessRuleProtection(true, false);
            foreach (var sid in new[] { new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null) })
                acl.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
            new DirectoryInfo(folder).SetAccessControl(acl);
            var receipt = new JsonObject
            {
                ["schema"] = "Pesto.AdQualification.RestoreName.v1", ["phase"] = "Running", ["utc"] = DateTimeOffset.UtcNow.ToString("o"),
                ["vmUuid"] = RestoreNamePolicy.Uuid, ["computerGuid"] = RestoreNamePolicy.Guid, ["computer"] = request.Computer,
                ["originalName"] = RestoreNamePolicy.OriginalName, ["sourceReceiptId"] = request.ReceiptId,
                ["returnMoveReceiptId"] = returnMove?.Id, ["sourceReceiptSha256"] = renameMove?.ReceiptSha256,
                ["returnMoveReceiptSha256"] = returnMove?.ReceiptSha256,
                ["returnPlan"] = request.ReturnPlan, ["before"] = before.DeepClone(), ["noReplay"] = true, ["restartRequired"] = false,
            };
            WriteRestoreReceipt(path, receipt, createNew: true); // durable reservation BEFORE the single native attempt
            Save("restore-receipt-before", receipt);
            try
            {
                RestoreV1Barriers.RequireClear(gpRoot); // Recheck both raw V1 barriers immediately before the only native call.
                if (rawReceipts is not null && renameMove is not null && returnMove is not null)
                {
                    var final = rawReceipts.Observe(id => RestoreProof(mutation.ReadReconciliation(id)));
                    RestoreRenameMovePolicy.RequireUnchanged(final.Source, final.Returned, rawReceipts.SourceHash, rawReceipts.ReturnHash);
                }
                RestoreV1Barriers.RequireClear(gpRoot); // The independent observations may take time: guard again after them, just before launch.
                var result = RunPowerShell(RestoreNameScript, new { currentName = request.Computer,
                    sourceReceiptId = request.ReceiptId, returnMoveReceiptId = returnMove?.Id,
                    server = session["dc"]?.GetValue<string>() ?? Domain, module = TrustedActiveDirectoryModule.Resolve(request.V1Root),
                    credential = credentials!.CreateProtectedPayload(),
                    domain = LabDomain.Name, ou = RestoreNamePolicy.Paris });
                receipt["phase"] = Text(result, "phase");
                receipt["restartRequired"] = result["restartRequired"]?.GetValue<bool>() == true;
                receipt["result"] = result.DeepClone();
                receipt["updatedUtc"] = DateTimeOffset.UtcNow.ToString("o");
                WriteRestoreReceipt(path, receipt, createNew: false);
                Save("restore-receipt-after", receipt);
                return Text(result, "phase") == "PendingRestart" ? 10 : 20;
            }
            catch
            {
                receipt["phase"] = "Uncertain";
                receipt["message"] = "Native attempt or readback did not complete. Inspect manually; this receipt can never authorize replay.";
                receipt["updatedUtc"] = DateTimeOffset.UtcNow.ToString("o");
                WriteRestoreReceipt(path, receipt, createNew: false);
                Save("restore-receipt-after", receipt);
                throw;
            }
        }
        finally { if (owned) mutex.ReleaseMutex(); }
    }

    private static string Text(JsonNode node, string key) => node[key]?.GetValue<string>() ?? "";
    private static RestoreRenameMoveProof RestoreProof(ReceiptReconciliationObservation e) => new(
        e.Receipt.Id, e.Receipt.Kind, e.Receipt.Status, e.Receipt.Code, e.Receipt.Computer, e.Receipt.NewName, e.Receipt.TargetOU,
        e.Receipt.RestartRequired, e.Receipt.Time, e.ReceiptSha256, e.ExpectedGuid, e.Domain, e.InitialOu, e.InitialProtected,
        e.AdGuid, e.AdName, e.AdOu, e.AdProtected, e.WindowsActiveName, e.WindowsConfiguredName, e.WindowsDomain,
        e.WindowsPartOfDomain, e.SecureChannel, e.LocalTarget, e.MachineIdentityMatches, e.InitialBootUtc, e.CurrentBootUtc, e.Error);
    private static void NoLinks(string path)
    {
        for (string? current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((Directory.Exists(current) || File.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Restore receipt cannot traverse a link or junction.");
    }
    private static void WriteRestoreReceipt(string path, JsonObject receipt, bool createNew)
    {
        NoLinks(path);
        var target = createNew ? path : path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                JsonSerializer.Serialize(stream, receipt, Json);
                stream.Flush(true);
            }
            if (!createNew) File.Move(target, path, overwrite: true);
        }
        finally { if (!createNew && File.Exists(target)) File.Delete(target); }
    }

    // Constant, lab-only cleanup script. No task, remote target, reboot, unjoin, repair or retry.
    private const string RestoreNameScript = """
$ErrorActionPreference='Stop';$WarningPreference='SilentlyContinue'
$j=[Console]::In.ReadToEnd()|ConvertFrom-Json
$bytes=$null;$secure=$null;$sent=$false
try{
 $original='P111301VA765158';$guid=[Guid]'b4797c9c-d790-4797-bf71-424a57acb36e'
 $ou=[string]$j.ou
 $cs=Get-CimInstance Win32_ComputerSystem
 $uuid=[string](Get-CimInstance Win32_ComputerSystemProduct).UUID
 $active=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
 $configured=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if($uuid -ine '9b2ad4f0-0506-4f58-aed2-c43ac1973516' -or -not $cs.PartOfDomain -or $cs.Domain -ine [string]$j.domain -or [int]$cs.DomainRole -ne 1){throw 'Wrong local identity'}
 if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or -not (Test-ComputerSecureChannel -ErrorAction Stop)){throw 'Local elevation/channel not confirmed'}
 $recordedRenameMove=[string]$j.currentName -ieq 'P111301LY765715' -and [string]$j.sourceReceiptId -ceq 'receipt-50a635a9b3ee46138c9fc231bcff83af' -and [string]$j.returnMoveReceiptId -match '^receipt-[a-fA-F0-9]{32}$'
 if(([string]$j.currentName -notmatch '^P111301VA765[0-9]{3}$' -and -not $recordedRenameMove) -or [string]$j.currentName -ieq $original -or $active -ine [string]$j.currentName -or $configured -ine $active -or $cs.Name -ine $active){throw 'Name drift or pending rename'}
 if(-not $j.module -or -not $j.credential){throw 'Explicit native credential/module missing'}
 Import-Module -Name ([string]$j.module) -ErrorAction Stop
 Add-Type -AssemblyName System.Security
 $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String([string]$j.credential.blob),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 $secure=New-Object Security.SecureString
 for($i=0;$i -lt $bytes.Length;$i+=2){$secure.AppendChar([char]([int]$bytes[$i] -bor ([int]$bytes[$i+1] -shl 8)))}
 $secure.MakeReadOnly();$credential=New-Object Management.Automation.PSCredential([string]$j.credential.userName,$secure)
 [Array]::Clear($bytes,0,$bytes.Length);$bytes=$null
 $p=@{Server=[string]$j.server;Credential=$credential}
 $before=Get-ADComputer -Identity $guid -Properties ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion,userAccountControl @p
 if([Guid]$before.ObjectGUID -ne $guid -or [string]$before.Name -ine $active -or [string]$before.DistinguishedName -ine ('CN='+$active+','+$ou) -or [bool]$before.ProtectedFromAccidentalDeletion -or [long]$before.userAccountControl -ne 4096){throw 'AD identity/OU/protection drift'}
 $occupied=@(Get-ADComputer -LDAPFilter '(|(name=P111301VA765158)(sAMAccountName=P111301VA765158$))' -ResultSetSize 2 @p)
 if($occupied.Count -ne 0){throw 'Original name occupied'}
 $sent=$true
 $renamed=Rename-Computer -NewName $original -DomainCredential $credential -Force -PassThru -ErrorAction Stop
 if(-not $renamed.HasSucceeded){throw 'Rename not confirmed'}
 $after=Get-ADComputer -Identity $guid -Properties ObjectGUID,DistinguishedName,ProtectedFromAccidentalDeletion,userAccountControl @p
 $configuredAfter=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName').ComputerName
 $activeAfter=[string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName').ComputerName
 if([Guid]$after.ObjectGUID -ne $guid -or [string]$after.Name -ine $original -or [string]$after.DistinguishedName -ine ('CN='+$original+','+$ou) -or [bool]$after.ProtectedFromAccidentalDeletion -or [long]$after.userAccountControl -ne 4096 -or $configuredAfter -ine $original -or $activeAfter -ine $active){throw 'Post-rename readback incomplete'}
 @{phase='PendingRestart';restartRequired=$true;guid=[string]$after.ObjectGUID;name=[string]$after.Name;dn=[string]$after.DistinguishedName;protected=[bool]$after.ProtectedFromAccidentalDeletion;uac=[long]$after.userAccountControl;activeName=$activeAfter;configuredName=$configuredAfter;utc=[DateTime]::UtcNow.ToString('o');nativeAttempts=1}|ConvertTo-Json -Compress
}catch{
 @{phase=$(if($sent){'Uncertain'}else{'Refused'});restartRequired=$sent;message='Guard, rename or readback did not confirm the intended state. Inspect separately; no replay.';utc=[DateTime]::UtcNow.ToString('o');nativeAttempts=$(if($sent){1}else{0})}|ConvertTo-Json -Compress
}finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)};if($secure){$secure.Dispose()}}
""";
}

using System.Text.Json;
using System.Text.Json.Nodes;

internal static class RestoreReceiptGateTests
{
    private const string SourceId = "receipt-50a635a9b3ee46138c9fc231bcff83af";
    private const string ReturnId = "receipt-22222222222222222222222222222222";
    // Native receipt field names and original campaign identity; timestamps describe a verified source and later return.
    private const string Source = """
        {"Schema":1,"Version":"2.0","Phase":"Verified","ReceiptId":"receipt-50a635a9b3ee46138c9fc231bcff83af",
        "Kind":"renameMove","Computer":"P111301VA765158","NewName":"P111301LY765715","Code":77,"RestartRequired":false,
        "ComputerGuid":"b4797c9c-d790-4797-bf71-424a57acb36e","Domain":"labo.local","Dc":"dc01.labo.local",
        "MachineId":"81387449-2dd8-4bd9-8059-f868a5b8ec68","LocalTarget":true,"InitialWindowsDomain":"labo.local",
        "InitialPartOfDomain":true,"InitialDomainRole":1,"InitialProtected":false,"Entra":"Skipped",
        "EntraEvidenceId":null,"EntraEvidenceSha256":null,"EntraMayStillRun":false,"EntraReenrollmentPending":false,
        "InitialOu":"OU=Paris,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local",
        "TargetOu":"OU=Lyon,OU=SITES,OU=Postes,OU=Departement 111301,OU=ADCC-Lab,DC=labo,DC=local",
        "InitialBootUtc":"2026-10-28T07:00:50.5000000+00:00","CreatedUtc":"2026-10-28T08:12:45.9206338+00:00",
        "Utc":"2026-10-28T09:25:35Z","ConfigurationSha256":"b33c77125445a8a1ee9ed4edc24f8af03007acab64c73672eb72d43145e51379"}
        """;

    public static int Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-restore-raw-gate-" + Guid.NewGuid().ToString("N"));
        var receipts = Path.Combine(root, "V2", "receipts");
        Directory.CreateDirectory(receipts);
        var sourcePath = Path.Combine(receipts, SourceId + ".json");
        var returnPath = Path.Combine(receipts, ReturnId + ".json");
        var returned = JsonNode.Parse(Source)!.AsObject();
        returned["ReceiptId"] = ReturnId; returned["Kind"] = "move"; returned["Code"] = 30;
        returned["Computer"] = "P111301LY765715"; returned["NewName"] = null;
        returned["InitialOu"] = RestoreRenameMovePolicy.Lyon; returned["TargetOu"] = RestoreNamePolicy.Paris;
        returned["InitialBootUtc"] = "2026-10-28T09:14:56Z"; returned["CreatedUtc"] = "2026-10-28T11:01:00Z";
        returned["Utc"] = "2026-10-28T11:01:02Z";
        // A different synthetic configuration is valid for the return; old source config is never reapplied.
        returned["ConfigurationSha256"] = "f76ad53a8d7ea367248fd2b067cb48ddaa0bb1dd7e9cc87566f7d85b58adfe35";
        var returnJson = returned.ToJsonString();
        var checks = 0;
        void Reset() { File.WriteAllText(sourcePath, Source); File.WriteAllText(returnPath, returnJson); }
        void Rejected(string label, Action alter, string sourceId = SourceId, string returnId = ReturnId)
        {
            Reset(); alter(); var calls = 0; var rejected = false;
            try
            {
                using var gate = RestoreRenameMoveReceiptGate.Open(root, sourceId, returnId);
                gate.Observe(id => { calls++; return id; });
            }
            catch (Exception e) when (e is InvalidOperationException or IOException or JsonException or UnauthorizedAccessException)
            { rejected = true; }
            if (!rejected || calls != 0) throw new Exception($"Raw gate {label}: rejected={rejected}, adapter calls={calls}");
            checks++;
        }
        void Change(string path, string field, JsonNode? value)
        {
            var json = JsonNode.Parse(File.ReadAllText(path))!;
            json[field] = value?.DeepClone(); File.WriteAllText(path, json.ToJsonString());
        }
        try
        {
            Reset();
            using (var gate = RestoreRenameMoveReceiptGate.Open(root, SourceId, ReturnId))
            {
                var calls = new List<string>();
                var pair = gate.Observe(id => { calls.Add(id); return File.ReadAllText(Path.Combine(receipts, id + ".json")); });
                if (!calls.SequenceEqual(new[] { SourceId, ReturnId }) || pair.Source != Source || pair.Returned != returnJson
                    || File.ReadAllText(sourcePath) != Source || File.ReadAllText(returnPath) != returnJson)
                    throw new Exception("Accepted receipts not observed exactly once without changes");
                checks++;
                if (OperatingSystem.IsWindows())
                {
                    foreach (var path in new[] { sourcePath, returnPath })
                    {
                        var blocked = false;
                        try { using var writer = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.ReadWrite); }
                        catch (IOException) { blocked = true; }
                        if (!blocked) throw new Exception("Windows receipt pin allowed writing during adapter observation");
                        checks++;
                    }
                }
            }
            foreach (var path in new[] { sourcePath, returnPath })
            {
                foreach (var bad in new (string Field, JsonNode? Value)[] {
                    ("Schema",2), ("Version","1.0"), ("Phase","PendingRestart"), ("Phase","Uncertain"), ("RestartRequired",true),
                    ("ReceiptId","receipt-33333333333333333333333333333333"), ("ComputerGuid","f4797c9c-d790-4797-bf71-424a57acb36e"),
                    ("MachineId","11387449-2dd8-4bd9-8059-f868a5b8ec68"), ("Domain","foreign.local"), ("Dc","dc01.foreign.local"),
                    ("LocalTarget",false), ("InitialWindowsDomain","WORKGROUP"), ("InitialPartOfDomain",false), ("InitialDomainRole",4),
                    ("InitialProtected",true), ("InitialProtected",null), ("Entra","Requested"), ("Entra","Uncertain"),
                    ("Entra","Confirmed"), ("Entra","Unknown"), ("Entra",true), ("Entra",""),
                    ("EntraEvidenceId","receipt-33333333333333333333333333333333"), ("EntraEvidenceSha256",new string('a',64)),
                    ("EntraMayStillRun",true), ("EntraReenrollmentPending",true), ("InitialBootUtc",null), ("CreatedUtc","invalid"),
                    ("Utc","2026-10-27T00:00:00Z"), ("Kind","join"), ("Computer","UNRELATED-PC"), ("NewName","UNRELATED-PC"),
                    ("TargetOu","OU=Foreign,DC=labo,DC=local"), ("InitialOu","OU=Foreign,DC=labo,DC=local") })
                    Rejected(Path.GetFileName(path) + "/" + bad.Field, () => Change(path, bad.Field, bad.Value));
                foreach (var malformed in new[] { "", "{}", "null", "[]", Source.Replace("\"Schema\":1", "\"Schema\":1,\"Schema\":1"),
                    Source.Replace("\"Schema\":1", "\"Schema\":1,\"schema\":1"), new string(' ', 65537) })
                    Rejected("malformed/bounded " + Path.GetFileName(path), () => File.WriteAllText(path, malformed));
                Rejected("missing " + Path.GetFileName(path), () => File.Delete(path));
            }
            Rejected("wrong source code", () => Change(sourcePath, "Code", 20));
            Rejected("wrong return code", () => Change(returnPath, "Code", 77));
            Rejected("old return before verified source", () => Change(returnPath, "CreatedUtc", "2026-10-28T09:24:00Z"));
            Rejected("return from pre-rename boot", () => Change(returnPath, "InitialBootUtc", "2026-10-28T07:00:50Z"));
            Rejected("return boot after return creation", () => Change(returnPath, "InitialBootUtc", "2026-10-28T11:01:01Z"));
            // A later reboot (for example a cold snapshot) does not invalidate the historical source verification.
            Reset(); Change(returnPath, "InitialBootUtc", "2026-10-28T09:30:00Z");
            using (var gate = RestoreRenameMoveReceiptGate.Open(root, SourceId, ReturnId))
            {
                var calls = 0; gate.Observe(id => ++calls);
                if (calls != 2) throw new Exception("A later legitimate boot was refused before current identity observations");
                checks++;
            }
            foreach (var id in new[] { "../outside", "receipt-" + new string('a',32) + "\n", "C:\\foreign.json", SourceId, "REPLACE_WITH_VERIFIED_RETURN_MOVE_RECEIPT_ID" })
                Rejected("unsafe return id", () => { }, returnId: id);
            Rejected("unrelated source id", () => { }, sourceId: ReturnId);
            Rejected("foreign opaque receipt with Entra requested", () =>
            {
                Change(returnPath, "Computer", "FOREIGN-CANARY"); Change(returnPath, "LocalTarget", false);
                Change(returnPath, "Entra", "Requested"); Change(returnPath, "Kind", "rename");
            });
            // Both leaf links and linked receipt directories must fail before the observation callback.
            Reset();
            var saved = Path.Combine(root, "saved-return.json"); File.Copy(returnPath, saved);
            Rejected("linked receipt", () => { File.Delete(returnPath); File.CreateSymbolicLink(returnPath, saved); });
            File.Delete(returnPath);
            Reset();
            var real = Path.Combine(root, "real-receipts"); Directory.Move(receipts, real);
            Directory.CreateSymbolicLink(receipts, real);
            var linkedCalls = 0; var linkRejected = false;
            try { using var gate = RestoreRenameMoveReceiptGate.Open(root, SourceId, ReturnId); gate.Observe(id => ++linkedCalls); }
            catch (InvalidOperationException) { linkRejected = true; }
            if (!linkRejected || linkedCalls != 0) throw new Exception("Linked ancestor reached observation API");
            checks++;
            Directory.Delete(receipts); Directory.Move(real, receipts);
            // No Entra value / explicit non-requested is accepted, including unchanged historical source configuration.
            foreach (var effect in new string?[] { null, "NotRequested", "Skipped" })
            {
                Reset(); Change(sourcePath, "Entra", effect); Change(returnPath, "Entra", effect);
                using var gate = RestoreRenameMoveReceiptGate.Open(root, SourceId, ReturnId);
                var calls = 0; gate.Observe(id => ++calls);
                if (calls != 2) throw new Exception("Valid non-Entra local pair was not observed");
                checks++;
            }
        }
        finally { Directory.Delete(root, true); }
        Console.WriteLine($"{checks}/{checks} raw receipt gates passed; every refused pair made zero adapter calls.");
        return checks;
    }
}

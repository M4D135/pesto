LabDomain.UseForTests("labo.local");
var valid = new RestoreObservation(RestoreNamePolicy.Uuid, RestoreNamePolicy.Guid, "P111301VA765159", "P111301VA765159", "P111301VA765159",
    RestoreNamePolicy.Domain, true, 1, true, true, "P111301VA765159", RestoreNamePolicy.Paris, false, 4096, true,
    "receipt-11111111111111111111111111111111", "rename", "succeeded", RestoreNamePolicy.OriginalName, "P111301VA765159", false,
    true, RestoreNamePolicy.Confirmation, "After explicit reboot, verify original name, unchanged GUID, Paris OU and secure channel.");
var cases = new (string Name, RestoreObservation Observation)[]
{
    ("wrong VM", valid with { Uuid = "00000000-0000-0000-0000-000000000000" }),
    ("replacement object", valid with { Guid = "00000000-0000-0000-0000-000000000000" }),
    ("foreign domain", valid with { Domain = "other.local" }),
    ("workgroup", valid with { Member = false }),
    ("domain controller", valid with { Role = 4 }),
    ("not elevated", valid with { Elevated = false }),
    ("broken channel", valid with { SecureChannel = false }),
    ("name not qualification naming", valid with { Computer = "OTHER-PC" }),
    ("original already restored", valid with { Computer = RestoreNamePolicy.OriginalName, ActiveName = RestoreNamePolicy.OriginalName, ConfiguredName = RestoreNamePolicy.OriginalName, AdName = RestoreNamePolicy.OriginalName }),
    ("local active drift", valid with { ActiveName = "P111301VA765160" }),
    ("pending rename", valid with { ConfiguredName = "P111301VA765160" }),
    ("AD name drift", valid with { AdName = "P111301VA765160" }),
    ("outside lab OU", valid with { Ou = "OU=Paris,DC=labo,DC=local" }),
    ("return move unfinished", valid with { Ou = RestoreNamePolicy.Paris.Replace("OU=Paris,", "OU=Lyon,") }),
    ("protection changed", valid with { Protected = true }),
    ("account disabled", valid with { Uac = 4098 }),
    ("original occupied", valid with { OriginalNameAvailable = false }),
    ("receipt path traversal", valid with { ReceiptId = "../outside" }),
    ("unrelated operation", valid with { ReceiptKind = "move" }),
    ("pending product receipt", valid with { ReceiptStatus = "pendingRestart" }),
    ("uncertain product receipt", valid with { ReceiptStatus = "uncertain" }),
    ("restart still required", valid with { ReceiptRestartRequired = true }),
    ("receipt belongs to another origin", valid with { ReceiptComputer = "OTHER-PC" }),
    ("receipt belongs to another target", valid with { ReceiptNewName = "P111301VA765160" }),
    ("no explicit AD credential", valid with { ExplicitCredential = false }),
    ("generic mutation confirmation", valid with { Confirmation = "EXECUTE PESTO CANARY" }),
    ("missing return plan", valid with { ReturnPlan = "" }),
};
RestoreNamePolicy.Validate(valid);
Console.WriteLine("PASS exact recorded target accepted");
foreach (var (name, observation) in cases)
{
    try { RestoreNamePolicy.Validate(observation); Console.Error.WriteLine("FAIL " + name); return 1; }
    catch (InvalidOperationException) { Console.WriteLine("PASS refuses " + name); }
}
var barrierChecks = 0;
foreach (var phase in new[] { "Running", "PendingRestart", "Partial", "Uncertain", "Protection", "MoveReady", "Unknown", "" })
{
    using var doc = System.Text.Json.JsonDocument.Parse(System.Text.Json.JsonSerializer.Serialize(new { Phase = phase }));
    if (RestoreV1Barriers.IsClear(doc.RootElement)) throw new InvalidOperationException("Unexpected barrier bypass: " + phase);
    barrierChecks++;
}
foreach (var phase in new[] { "Failed", "Verified", "NotStarted", "None" })
{
    using var doc = System.Text.Json.JsonDocument.Parse(System.Text.Json.JsonSerializer.Serialize(new { Phase = phase }));
    if (!RestoreV1Barriers.IsClear(doc.RootElement)) throw new InvalidOperationException("Unexpected refusal of terminal barrier: " + phase);
    barrierChecks++;
}
foreach (var text in new[] { "{}", "[]", "null", "{\"Phase\":\"Running\",\"Phase\":\"Verified\"}", "{\"Phase\":\"Running\",\"Acknowledged\":{}}" })
{
    using var doc = System.Text.Json.JsonDocument.Parse(text);
    if (RestoreV1Barriers.IsClear(doc.RootElement)) throw new InvalidOperationException("Malformed barrier accepted");
    barrierChecks++;
}
var temp = Path.Combine(Path.GetTempPath(), "pesto-restore-barriers-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(temp);
try
{
    RestoreV1Barriers.RequireClear(temp); barrierChecks++;
    foreach (var relative in new[] { Path.Combine("Join", "receipt.json"), Path.Combine("Operations", "direct.json") })
    {
        var path = Path.Combine(temp, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{\"Phase\":\"PendingRestart\"}");
        var refused = false;
        try { RestoreV1Barriers.RequireClear(temp); } catch (InvalidOperationException) { refused = true; }
        if (!refused) throw new InvalidOperationException("Raw V1 barrier was skipped: " + relative);
        File.Delete(path); barrierChecks++;
    }
}
finally { Directory.Delete(temp, true); }
var legacy = System.Text.Json.Nodes.JsonNode.Parse("""
{"items":[{"id":"11111111111111111111111111111111","status":"pendingRestart","readable":true,"mode":"V1 · registre local GP (relu, lecture seule)","time":"2026-10-18T11:28:48Z","computer":"P111301VA765480","newName":"P111301VA765158"}]}
""")!;
var boot = DateTimeOffset.Parse("2026-10-26T17:08:35Z");
var verified = DateTimeOffset.Parse("2026-10-26T17:12:46Z");
var beforeHistory = legacy.ToJsonString();
var retained = RestoreHistoryPolicy.Validate(legacy, valid.Computer, boot, verified);
if (retained.Count != 1 || legacy.ToJsonString() != beforeHistory) throw new InvalidOperationException("Legacy history was lost or rewritten");
var historyChecks = 1;
foreach (var change in new (string Field, System.Text.Json.Nodes.JsonNode? Value)[] {
    ("status", "sent"), ("status", "uncertain"), ("status", "partial"), ("status", "protection"),
    ("status", "unreadable"), ("status", "unknown"), ("readable", false),
    ("mode", "live"), ("id", "receipt-11111111111111111111111111111111"), ("id", "bad"),
    ("time", "invalid"), ("time", boot.ToString("O")), ("time", verified.AddSeconds(1).ToString("O")),
    ("computer", valid.Computer), ("newName", valid.Computer.ToLowerInvariant()), ("computer", ""), ("newName", "") })
{
    var changed = legacy.DeepClone(); changed["items"]![0]![change.Field] = change.Value?.DeepClone();
    var refused = false;
    try { RestoreHistoryPolicy.Validate(changed, valid.Computer, boot, verified); } catch (InvalidOperationException) { refused = true; }
    if (!refused) throw new InvalidOperationException("Unsafe history accepted: " + change.Field);
    historyChecks++;
}
foreach (var malformed in new[] { "{}", "{\"items\":[null]}" })
{
    var refused = false;
    try { RestoreHistoryPolicy.Validate(System.Text.Json.Nodes.JsonNode.Parse(malformed)!, valid.Computer, boot, verified); }
    catch (InvalidOperationException) { refused = true; }
    if (!refused) throw new InvalidOperationException("Malformed history accepted");
    historyChecks++;
}
var duplicated = legacy.DeepClone(); duplicated["items"]!.AsArray().Add(duplicated["items"]![0]!.DeepClone());
try { RestoreHistoryPolicy.Validate(duplicated, valid.Computer, boot, verified); throw new Exception("Duplicate accepted"); }
catch (InvalidOperationException) { historyChecks++; }
// A future source time cannot legitimize an entry newer than the boot, or vice versa.
var newerSource = legacy.DeepClone(); newerSource["items"]![0]!["time"] = "2026-10-26T17:10:00Z";
try { RestoreHistoryPolicy.Validate(newerSource, valid.Computer, verified, boot); throw new Exception("Future history accepted"); }
catch (InvalidOperationException) { historyChecks++; }
Console.WriteLine($"{historyChecks}/{historyChecks} history guards passed; original pending status retained.");
var sourceProof = new RestoreRenameMoveProof(RestoreRenameMovePolicy.SourceReceiptId, "renameMove", "succeeded", 77,
    RestoreNamePolicy.OriginalName, RestoreRenameMovePolicy.CurrentName, RestoreRenameMovePolicy.Lyon, false,
    DateTimeOffset.Parse("2026-10-28T09:25:35Z"), new string('a', 64), RestoreNamePolicy.Guid, RestoreNamePolicy.Domain,
    RestoreNamePolicy.Paris, false, RestoreNamePolicy.Guid, RestoreRenameMovePolicy.CurrentName, RestoreNamePolicy.Paris, false,
    RestoreRenameMovePolicy.CurrentName, RestoreRenameMovePolicy.CurrentName, RestoreNamePolicy.Domain, true, true, true, true,
    DateTimeOffset.Parse("2026-10-28T07:00:50Z"), DateTimeOffset.Parse("2026-10-28T09:14:56Z"), null);
var returnProof = sourceProof with { Id = "receipt-22222222222222222222222222222222", Kind = "move", Code = 30,
    Computer = RestoreRenameMovePolicy.CurrentName, NewName = "", InitialOu = RestoreRenameMovePolicy.Lyon,
    TargetOu = RestoreNamePolicy.Paris, Time = sourceProof.Time.AddMinutes(20), ReceiptSha256 = new string('b', 64),
    InitialBootUtc = sourceProof.CurrentBootUtc };
RestoreRenameMovePolicy.Validate(sourceProof, returnProof);
var moveChecks = 1;
var laterBoot = sourceProof.Time.AddMinutes(1);
RestoreRenameMovePolicy.Validate(sourceProof with { CurrentBootUtc = laterBoot },
    returnProof with { InitialBootUtc = laterBoot, CurrentBootUtc = laterBoot });
moveChecks++;
var renamedMove = valid with { Computer = RestoreRenameMovePolicy.CurrentName, ActiveName = RestoreRenameMovePolicy.CurrentName,
    ConfiguredName = RestoreRenameMovePolicy.CurrentName, AdName = RestoreRenameMovePolicy.CurrentName,
    ReceiptId = RestoreRenameMovePolicy.SourceReceiptId, ReceiptKind = "renameMove", ReceiptNewName = RestoreRenameMovePolicy.CurrentName,
    RenameMoveReturnConfirmed = true };
RestoreNamePolicy.Validate(renamedMove); moveChecks++;
foreach (var changed in new[] {
    renamedMove with { RenameMoveReturnConfirmed = false },
    renamedMove with { ReceiptId = returnProof.Id },
    renamedMove with { ReceiptKind = "rename" },
    renamedMove with { Ou = RestoreRenameMovePolicy.Lyon },
    renamedMove with { Computer = "P111301LY765716", ActiveName = "P111301LY765716", ConfiguredName = "P111301LY765716", AdName = "P111301LY765716", ReceiptNewName = "P111301LY765716" },
    valid with { RenameMoveReturnConfirmed = true } })
{
    try { RestoreNamePolicy.Validate(changed); throw new Exception("Unbound renameMove restore accepted"); }
    catch (InvalidOperationException) { moveChecks++; }
}
var sourceChanges = new[] {
    sourceProof with { Id = returnProof.Id }, sourceProof with { Kind = "rename" }, sourceProof with { Code = 89 },
    sourceProof with { Computer = "OTHER-PC" }, sourceProof with { NewName = "P111301LY765716" },
    sourceProof with { InitialOu = RestoreRenameMovePolicy.Lyon }, sourceProof with { TargetOu = RestoreNamePolicy.Paris },
    sourceProof with { InitialBootUtc = null }, sourceProof with { CurrentBootUtc = null },
    sourceProof with { CurrentBootUtc = sourceProof.InitialBootUtc } };
foreach (var changed in sourceChanges)
{
    try { RestoreRenameMovePolicy.Validate(changed, returnProof); throw new Exception("Wrong source renameMove accepted"); }
    catch (InvalidOperationException) { moveChecks++; }
}
var returnChanges = new[] {
    returnProof with { Id = "../outside" }, returnProof with { Id = sourceProof.Id }, returnProof with { Kind = "renameMove" },
    returnProof with { Code = 77 }, returnProof with { Computer = RestoreNamePolicy.OriginalName },
    returnProof with { NewName = RestoreNamePolicy.OriginalName }, returnProof with { InitialOu = RestoreNamePolicy.Paris },
    returnProof with { TargetOu = RestoreRenameMovePolicy.Lyon }, returnProof with { Time = sourceProof.Time },
    returnProof with { Time = sourceProof.Time.AddMinutes(-1) }, returnProof with { CurrentBootUtc = sourceProof.CurrentBootUtc!.Value.AddSeconds(1) } };
foreach (var changed in returnChanges)
{
    try { RestoreRenameMovePolicy.Validate(sourceProof, changed); throw new Exception("Wrong return move accepted"); }
    catch (InvalidOperationException) { moveChecks++; }
}
// Every missing/current-identity guard applies to BOTH independent receipt observations.
Func<RestoreRenameMoveProof, RestoreRenameMoveProof>[] identityChanges = [
    p => p with { Status = "pendingRestart" }, p => p with { RestartRequired = true }, p => p with { ReceiptSha256 = "bad" },
    p => p with { ExpectedGuid = "00000000-0000-0000-0000-000000000000" }, p => p with { AdGuid = null },
    p => p with { Domain = "other.local" }, p => p with { WindowsDomain = null }, p => p with { AdName = "OTHER-PC" },
    p => p with { AdOu = RestoreRenameMovePolicy.Lyon }, p => p with { ActiveName = RestoreNamePolicy.OriginalName },
    p => p with { ConfiguredName = RestoreNamePolicy.OriginalName }, p => p with { InitialProtected = null },
    p => p with { InitialProtected = true }, p => p with { AdProtected = true }, p => p with { AdProtected = null },
    p => p with { Member = false }, p => p with { Member = null }, p => p with { SecureChannel = null },
    p => p with { LocalTarget = false }, p => p with { MachineIdentityMatches = false }, p => p with { Error = "Incomplete read" } ];
foreach (var change in identityChanges)
{
    try { RestoreRenameMovePolicy.Validate(change(sourceProof), returnProof); throw new Exception("Wrong current source identity accepted"); }
    catch (InvalidOperationException) { moveChecks++; }
    try { RestoreRenameMovePolicy.Validate(sourceProof, change(returnProof)); throw new Exception("Wrong current return identity accepted"); }
    catch (InvalidOperationException) { moveChecks++; }
}
RestoreRenameMovePolicy.RequireUnchanged(sourceProof, returnProof, sourceProof.ReceiptSha256, returnProof.ReceiptSha256); moveChecks++;
foreach (var hashes in new[] { (new string('c', 64), returnProof.ReceiptSha256), (sourceProof.ReceiptSha256, new string('c', 64)) })
{
    try { RestoreRenameMovePolicy.RequireUnchanged(sourceProof, returnProof, hashes.Item1, hashes.Item2); throw new Exception("Changed durable receipt accepted"); }
    catch (InvalidOperationException) { moveChecks++; }
}
Console.WriteLine($"{moveChecks}/{moveChecks} recorded renameMove return guards passed; no native command executed.");
Console.WriteLine($"{cases.Length + 1}/{cases.Length + 1} restore guards and {barrierChecks}/{barrierChecks} raw V1 barrier checks passed; no native command executed.");
RestoreReceiptGateTests.Run();
return 0;

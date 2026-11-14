using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Pesto.Engine;

namespace Pesto.UpdateQualification;

internal sealed record SuitePackage(string Directory, string Fingerprint, string Version, string Channel, string ExecutableSha256,
    string RuntimeFingerprint, string SourceCommit);
internal sealed record SuiteState(int SchemaVersion, string Id, string Channel, SuitePackage Base, SuitePackage Candidate,
    string CandidateZip, string CandidateZipSha256, string SentinelSha256);
internal sealed record CaseState(int SchemaVersion, string Scenario, string InitialFingerprint, string CandidateFingerprint,
    string CandidateVersion, string Acquisition, bool SyntheticFault, string TransactionDirectory, string HelperExecutable, string TransactionId);
internal sealed record LaunchReceipt(int ProcessId, string StartUtcTicks, string Executable, string TransactionId);

/// <summary>Disposable fixture preparation only. No business backend or network operation is constructed.</summary>
internal static class Suite
{
    internal const string Prefix = "Pesto-native-update-";
    private static readonly string[] ProdScenarios = ["normal", "health-failure", "interruption"];
    private static readonly string[] DevScenarios = ["normal"];
    private static readonly string[] DevFormatScenarios = ["format-refusal"];
    private static readonly string[] KnownScenarios = [.. ProdScenarios, "format-refusal"];
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true, PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };

    internal static IReadOnlyList<string> Scenarios(SuiteState suite) => suite.Channel switch
    {
        "PROD" => ProdScenarios, "DEV" => RequiresNewDevInstallation(suite) ? DevFormatScenarios : DevScenarios,
        _ => throw new InvalidOperationException("Unknown qualification channel.")
    };

    /// <summary>
    /// The installed base validates a pack with its own compiled rules. A DEV base whose pack carries none of the
    /// exact DEV sources added after de527313 predates them and must refuse a candidate that carries them, before
    /// any replacement: that transition is a new DEV installation, qualified as an explicit refusal, not an update.
    /// </summary>
    internal static bool RequiresNewDevInstallation(SuiteState suite) => suite.Channel == "DEV"
        && UpdatePackage.Inventory(suite.Candidate.Directory).Keys.Any(UpdatePackage.DevExactSourcePaths.Contains)
        && !UpdatePackage.Inventory(suite.Base.Directory).Keys.Any(UpdatePackage.DevExactSourcePaths.Contains);
    internal static bool RealCandidate(string scenario) => scenario is "normal" or "format-refusal";

    internal static SuiteState Create(string basePack, string candidatePack, string candidateZip, string root)
    {
        root = NewRoot(root); basePack = LocalPath(basePack); candidatePack = LocalPath(candidatePack); candidateZip = LocalPath(candidateZip);
        foreach (var source in new[] { basePack, candidatePack, candidateZip })
            Require(!Within(source, root) && !Within(root, source) && !SamePath(source, root), "Fixture and sources must be disjoint.");
        Require(!SamePath(basePack, candidatePack), "Two distinct source packs are required.");
        Require(File.Exists(candidateZip) && candidateZip.EndsWith(".zip", StringComparison.OrdinalIgnoreCase),
            "The real candidate ZIP must exist; no directory fallback or generated replacement is allowed.");
        var initial = ReadSource(basePack); var next = ReadSource(candidatePack);
        var channel = initial.Channel;
        Require(next.Channel == channel, "Both packs must use the same channel.");
        Require(initial.ExecutableSha256 != next.ExecutableSha256 && initial.SourceCommit != next.SourceCommit,
            "Qualification requires different executable hashes and different source commits, not a renamed manifest.");
        Require(Version.Parse(next.Version) >= Version.Parse(initial.Version), "The candidate must not downgrade the base version.");
        Directory.CreateDirectory(root);
        Directory.CreateDirectory(Path.Combine(root, "evidence"));
        Directory.CreateDirectory(Path.Combine(root, "process-temp"));
        Directory.CreateDirectory(Path.Combine(root, "profile-sentinel"));
        var sentinel = Path.Combine(root, "profile-sentinel", "cfg.json");
        File.WriteAllText(sentinel, JsonSerializer.Serialize(new { kind = "synthetic-profile-sentinel", nonce = Guid.NewGuid().ToString("N"), mustRemainUnchanged = true }, Json));
        var state = new SuiteState(2, Path.GetFileName(root)[Prefix.Length..], channel, initial, next,
            candidateZip, UpdatePackage.Hash(candidateZip), UpdatePackage.Hash(sentinel));
        Save(Path.Combine(root, "qualification.json"), state);
        Save(Path.Combine(root, "evidence", "suite.json"), state);
        return state;
    }

    internal static async Task<UpdateInstallRequest> PrepareAsync(string root, string scenario)
    {
        var suite = Load(root); CheckUnchanged(root, suite); Require(Scenarios(suite).Contains(scenario), "Scenario is not required/admitted for this channel.");
        var directory = CaseDirectory(root, scenario);
        Require(!Directory.Exists(directory) && !File.Exists(directory), "A scenario must have a fresh fixture directory.");
        Directory.CreateDirectory(directory);
        Directory.CreateDirectory(Evidence(root, scenario));
        var installation = Path.Combine(directory, "installation");
        UpdatePackage.CopyToNew(suite.Base.Directory, installation, suite.Base.Fingerprint);
        var source = suite.CandidateZip; var fingerprint = suite.Candidate.Fingerprint;
        if (!RealCandidate(scenario))
        {
            source = Path.Combine(directory, "candidate");
            UpdatePackage.CopyToNew(suite.Candidate.Directory, source, suite.Candidate.Fingerprint);
            var manifestPath = Path.Combine(source, UpdatePackage.ManifestPath);
            var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
            // Keep the real build version. This deliberately altered web pack must not claim an intact source tree.
            manifest.Remove("sourceCommit"); UpdatePackage.WriteAtomic(manifestPath, manifest.ToJsonString(Json));
            var notice = "SYNTHETIC HEALTH FAULT. Not a release.\nScenario: " + scenario
                + "\nDerived from candidate commit: " + suite.Candidate.SourceCommit + "\nReal build version: " + suite.Candidate.Version
                + "\nUnchanged real executable SHA256: " + suite.Candidate.ExecutableSha256 + "\n";
            var noticePath = Path.Combine(source, "wad", "docs", "SYNTHETIC-UPDATE-QUALIFICATION.txt");
            Directory.CreateDirectory(Path.GetDirectoryName(noticePath)!); File.WriteAllText(noticePath, notice);
            // Present and hashed, but deliberately no shell/data-ready/mode-chip. This exercises real WebView2 health failure.
            File.WriteAllText(Path.Combine(source, "wad", "web", "index.html"),
                "<!doctype html><html lang=\"en\"><meta charset=\"utf-8\"><title>Synthetic health refusal fixture</title>"
                + "<body><main><h1>Native update qualification fixture</h1><p>The real health probe must refuse this local page.</p></main></body></html>");
            UpdatePackage.Rehash(source);
            var fault = UpdatePackage.Validate(source, suite.Channel);
            Require(fault.Version == suite.Candidate.Version, "Fault fixture must keep the real build version.");
            Require(UpdatePackage.Hash(Path.Combine(source, "Pesto.exe")) == suite.Candidate.ExecutableSha256
                && RuntimeFingerprint(source) == suite.Candidate.RuntimeFingerprint, "Fault fixture changed a real executable/runtime file.");
            ValidateVariant(suite.Candidate.Directory, source, scenario); fingerprint = fault.Fingerprint;
        }
        using var service = Service(root, scenario, suite);
        var inspected = service.InspectLocal(source);
        Require(Text(inspected, "fingerprint") == fingerprint && Text(inspected, "version") == suite.Candidate.Version,
            "The inspected ZIP/folder does not contain the exact reviewed candidate pack.");
        var prepared = await service.PrepareAsync(Text(inspected, "candidateId"));
        Require(Text(prepared, "fingerprint") == fingerprint, "Prepared content differs from the inspected candidate.");
        Require(UpdatePackage.Validate(installation, suite.Channel).Fingerprint == suite.Base.Fingerprint
            && UpdateTransaction.List(installation).Count == 0, "Inspection/preparation changed the installation or requested a transaction.");
        var request = service.RequestInstall(prepared["preparedId"]!.GetValue<string>(), true);
        Require(UpdatePackage.Hash(request.HelperExecutable) == suite.Base.ExecutableSha256,
            "The helper must be copied from the installed base build, never from the candidate.");
        var state = new CaseState(2, scenario, suite.Base.Fingerprint, fingerprint, suite.Candidate.Version,
            RealCandidate(scenario) ? "zip" : "directory", !RealCandidate(scenario), request.TransactionDirectory, request.HelperExecutable, request.TransactionId);
        Save(Path.Combine(directory, "case.json"), state);
        Save(Path.Combine(Evidence(root, scenario), "fixture.json"), state);
        Save(Path.Combine(Evidence(root, scenario), "request-install.json"), request);
        Save(Path.Combine(Evidence(root, scenario), "acquisition.json"), new
        {
            schemaVersion = 1, sourceKind = state.Acquisition, inspectedFingerprint = fingerprint,
            preparedFingerprint = Text(prepared, "fingerprint"), version = state.CandidateVersion,
            archiveSha256 = RealCandidate(scenario) ? suite.CandidateZipSha256 : null,
            candidateSourceCommit = suite.Candidate.SourceCommit, syntheticFault = state.SyntheticFault,
            syntheticVersion = false, installationPreservedBeforeConfirmation = true, directoryFallback = false
        });
        CheckUnchanged(root, suite);
        return request; // This process must exit before PowerShell starts the helper.
    }

    internal static UpdateInstallRequest Request(string root, string scenario, string action)
    {
        var suite = Load(root); CheckUnchanged(root, suite); var state = Case(root, scenario);
        Require(action is "rollback" or "recovery", "Only explicit rollback/recovery may be requested.");
        Require(scenario == "normal" && action == "rollback" || scenario == "interruption" && action == "recovery", "Action does not match scenario.");
        using var service = Service(root, scenario, suite);
        var request = action == "rollback" ? service.RequestRollback(true) : service.RequestRecovery(true);
        Require(request.TransactionId == state.TransactionId && request.HelperExecutable == state.HelperExecutable,
            "Request redirected the original fixture transaction.");
        Save(Path.Combine(Evidence(root, scenario), "request-" + action + ".json"), request);
        return request; // RequestRollback also records this process as the parent: exit before launching helper.
    }

    internal static JsonObject Verify(string root, string scenario, string stage)
    {
        var suite = Load(root); var state = Case(root, scenario); CheckUnchanged(root, suite);
        if (scenario == "format-refusal") return VerifyFormatRefusal(root, suite, state, stage);
        var installed = UpdatePackage.Validate(Path.Combine(CaseDirectory(root, scenario), "installation"), suite.Channel);
        var expectedStatus = scenario == "normal" && stage == "install" ? "completed" : "rolledBack";
        Require(scenario == "normal" ? stage is "install" or "rollback"
            : scenario == "health-failure" ? stage == "install" : stage == "recovery", "Verification stage does not match the required scenario.");
        var journal = ReadSharedObject(Path.Combine(state.TransactionDirectory, "transaction.json"));
        var observation = ReadSharedObject(Path.Combine(Evidence(root, scenario), "observation-" + stage + ".json"));
        Require(Boolean(observation, "success") && Boolean(observation, "dialogClosed")
            && observation["helperExitCode"]?.GetValue<int>() == 0 && Text(observation, "transactionId") == state.TransactionId,
            "A successful observation of the owned native helper is required before qualification.");
        Require(Text(journal, "status") == expectedStatus, "The native helper did not reach the required terminal state.");
        Require(Text(journal, "currentExecutableHash") == suite.Base.ExecutableSha256
            && Text(journal, "helperHash") == suite.Base.ExecutableSha256
            && Text(journal, "nextExecutableHash") == suite.Candidate.ExecutableSha256
            && Text(journal, "currentVersion") == suite.Base.Version && Text(journal, "nextVersion") == suite.Candidate.Version,
            "The transaction does not bind the distinct base/helper and candidate build identities.");
        Require(installed.Fingerprint == (expectedStatus == "completed" ? state.CandidateFingerprint : state.InitialFingerprint),
            "Installed content does not match the expected complete pack.");
        var expectedBuild = expectedStatus == "completed" ? suite.Candidate : suite.Base;
        Require(UpdatePackage.Hash(Path.Combine(installed.Directory, "Pesto.exe")) == expectedBuild.ExecutableSha256
            && RuntimeFingerprint(installed.Directory) == expectedBuild.RuntimeFingerprint, "Installed binary/runtime does not match the expected build.");
        var attempts = UpdateTransaction.ReadHealthAttempts(state.TransactionDirectory);
        var candidate = attempts.Where(a => Text(a, "target") == "candidate").ToArray();
        var rollback = attempts.Where(a => Text(a, "target") == "rollback").ToArray();
        Require(candidate.Length == 1, "Exactly one candidate health attempt is required.");
        if (scenario == "normal") Require(Passed(candidate[0]), "The candidate needs a durable positive native health receipt.");
        else if (scenario == "health-failure")
        {
            Require(Text(candidate[0], "status") == "failed" && !Boolean(candidate[0], "accepted")
                && candidate[0]["proof"] is JsonObject p && !Boolean(p, "success") && !Boolean(p, "webViewReady")
                && Boolean(p, "closeReturned") && Text(p, "nonce") == Text(candidate[0], "nonce")
                && Text(p, "transactionId") == state.TransactionId && Text(p, "executableSha256") == suite.Candidate.ExecutableSha256
                && Text(p, "version") == state.CandidateVersion && Text(journal, "failure") == "update.health",
                "A durable negative candidate proof and update.health journal failure are required.");
        }
        else
        {
            var interrupted = ReadSharedObject(Path.Combine(Evidence(root, scenario), "observation-install.json"));
            Require(Boolean(interrupted, "success") && Boolean(interrupted, "interrupted") && Boolean(interrupted, "checkingObserved")
                && Boolean(interrupted, "healthChildObserved") && Boolean(interrupted, "webViewChildObserved")
                && Text(interrupted, "finalJournalStatus") == "checking", "A real checking interruption with native browser descendants is required.");
            Require(Text(candidate[0], "status") == "interrupted" && !Boolean(candidate[0], "accepted"),
                "Recovery must preserve the interrupted candidate attempt without accepting it.");
        }
        if (expectedStatus == "rolledBack") Require(rollback.Length == 1 && Passed(rollback[0])
            && Text(rollback[0], "nonce") != Text(candidate[0], "nonce"), "A separate positive rollback health receipt is required.");
        else Require(rollback.Length == 0, "Unexpected rollback during normal installation.");
        foreach (var attempt in attempts)
        {
            var target = Text(attempt, "target");
            Require(target is "candidate" or "rollback", "Unknown health receipt target.");
            var build = target == "candidate" ? suite.Candidate : suite.Base;
            Require(Text(attempt, "transactionId") == state.TransactionId && Text(attempt, "expectedExecutableSha256") == build.ExecutableSha256
                && Text(attempt, "expectedVersion") == build.Version,
                "Health receipt identity mismatch.");
            Save(Path.Combine(Evidence(root, scenario), "health-" + Text(attempt, "nonce") + ".json"), attempt);
        }
        Save(Path.Combine(Evidence(root, scenario), "journal-" + stage + ".json"), journal);
        var proof = new JsonObject
        {
            ["schemaVersion"] = 1, ["kind"] = "pesto.native-update-stage", ["scenario"] = scenario, ["stage"] = stage,
            ["success"] = true, ["status"] = expectedStatus, ["transactionId"] = state.TransactionId,
            ["installedFingerprint"] = installed.Fingerprint, ["executableSha256"] = expectedBuild.ExecutableSha256,
            ["runtimeFingerprint"] = expectedBuild.RuntimeFingerprint, ["sentinelSha256"] = suite.SentinelSha256,
            ["baseExecutableSha256"] = suite.Base.ExecutableSha256, ["candidateExecutableSha256"] = suite.Candidate.ExecutableSha256,
            ["baseSourceCommit"] = suite.Base.SourceCommit, ["candidateSourceCommit"] = suite.Candidate.SourceCommit,
            ["healthAttemptCount"] = attempts.Count, ["candidateVersion"] = state.CandidateVersion,
            ["acquisition"] = state.Acquisition, ["syntheticFault"] = state.SyntheticFault, ["syntheticVersions"] = false,
            ["distinctBuilds"] = true, ["zipAcquisitionQualified"] = scenario == "normal", ["uncQualification"] = false,
            ["sourceUnchanged"] = true, ["profileSentinelUnchanged"] = true, ["adExecuted"] = false
        };
        Save(Path.Combine(Evidence(root, scenario), "proof-" + stage + ".json"), proof);
        return proof;
    }

    private static JsonObject VerifyFormatRefusal(string root, SuiteState suite, CaseState state, string stage)
    {
        Require(stage == "install", "A format refusal is only observed at installation.");
        var journal = ReadSharedObject(Path.Combine(state.TransactionDirectory, "transaction.json"));
        var observation = ReadSharedObject(Path.Combine(Evidence(root, "format-refusal"), "observation-install.json"));
        var refusedPath = Text(observation, "refusedPath");
        Require(Boolean(observation, "success") && Boolean(observation, "formatRefused") && Boolean(observation, "dialogClosed")
            && !Boolean(observation, "healthChildObserved") && !Boolean(observation, "webViewChildObserved")
            && observation["helperExitCode"]?.GetValue<int>() is int exit && exit != 0
            && Text(observation, "transactionId") == state.TransactionId && UpdatePackage.DevExactSourcePaths.Contains(refusedPath)
            && Text(observation, "refusalMessage") == "Fichier hors du contenu autorisé : " + refusedPath,
            "The base helper must refuse an exact new DEV source with its own message, exit non-zero and start no health check.");
        Require(Text(journal, "status") == "prepared" && Text(journal, "action") == "install" && Text(journal, "failure") == ""
            && Text(journal, "currentExecutableHash") == suite.Base.ExecutableSha256 && Text(journal, "helperHash") == suite.Base.ExecutableSha256
            && Text(journal, "nextExecutableHash") == suite.Candidate.ExecutableSha256,
            "The refusal must precede any transaction step and keep the distinct build identities.");
        Require(!Directory.Exists(Path.Combine(state.TransactionDirectory, "backup")) && !Directory.Exists(Path.Combine(state.TransactionDirectory, "failed-candidate"))
            && UpdatePackage.Validate(Path.Combine(state.TransactionDirectory, "stage"), suite.Channel).Fingerprint == state.CandidateFingerprint,
            "The refused stage must be the exact candidate and no replacement may have begun.");
        var installed = UpdatePackage.Validate(Path.Combine(CaseDirectory(root, "format-refusal"), "installation"), suite.Channel);
        Require(installed.Fingerprint == suite.Base.Fingerprint && UpdatePackage.Hash(Path.Combine(installed.Directory, "Pesto.exe")) == suite.Base.ExecutableSha256
            && RuntimeFingerprint(installed.Directory) == suite.Base.RuntimeFingerprint, "The base installation changed although its helper refused the pack.");
        Require(UpdateTransaction.ReadHealthAttempts(state.TransactionDirectory).Count == 0, "A refused pack must not start a health check.");
        Save(Path.Combine(Evidence(root, "format-refusal"), "journal-" + stage + ".json"), journal);
        var proof = new JsonObject
        {
            ["schemaVersion"] = 1, ["kind"] = "pesto.native-update-stage", ["scenario"] = "format-refusal", ["stage"] = stage,
            ["success"] = true, ["status"] = "refused", ["transactionId"] = state.TransactionId,
            ["formatRefused"] = true, ["refusedPath"] = refusedPath, ["inPlaceUpdateQualified"] = false, ["newInstallationRequired"] = true,
            ["installedFingerprint"] = installed.Fingerprint, ["executableSha256"] = suite.Base.ExecutableSha256,
            ["runtimeFingerprint"] = suite.Base.RuntimeFingerprint, ["sentinelSha256"] = suite.SentinelSha256,
            ["baseExecutableSha256"] = suite.Base.ExecutableSha256, ["candidateExecutableSha256"] = suite.Candidate.ExecutableSha256,
            ["baseSourceCommit"] = suite.Base.SourceCommit, ["candidateSourceCommit"] = suite.Candidate.SourceCommit,
            ["healthAttemptCount"] = 0, ["candidateVersion"] = state.CandidateVersion,
            ["acquisition"] = state.Acquisition, ["syntheticFault"] = false, ["syntheticVersions"] = false,
            ["distinctBuilds"] = true, ["zipAcquisitionQualified"] = true, ["uncQualification"] = false,
            ["sourceUnchanged"] = true, ["profileSentinelUnchanged"] = true, ["adExecuted"] = false
        };
        Save(Path.Combine(Evidence(root, "format-refusal"), "proof-" + stage + ".json"), proof);
        return proof;
    }

    internal static object Cleanup(string root, string scenario)
    {
        var suite = Load(root); CheckUnchanged(root, suite); _ = Case(root, scenario);
        var final = scenario == "normal" ? "rollback" : scenario == "interruption" ? "recovery" : "install";
        var proof = ReadSharedObject(Path.Combine(Evidence(root, scenario), "proof-" + final + ".json"));
        Require(Boolean(proof, "success") && Text(proof, "status") == (scenario == "format-refusal" ? "refused" : "rolledBack"),
            "Do not clean an unqualified/failed scenario.");
        var path = CaseDirectory(root, scenario);
        var pending = new Stack<string>(); pending.Push(path);
        while (pending.Count > 0)
            foreach (var item in Directory.EnumerateFileSystemEntries(pending.Pop()))
            {
                UpdatePackage.RequireNoLinks(item);
                if (Directory.Exists(item)) pending.Push(item);
            }
        Directory.Delete(path, true); // Only this generated, validated case. Evidence and profile sentinel remain outside it.
        return new { success = true, scenario, ownedFixtureRemoved = true };
    }

    internal static JsonObject Finish(string root)
    {
        var suite = Load(root); CheckUnchanged(root, suite);
        var results = new JsonArray(); var newInstallation = RequiresNewDevInstallation(suite);
        foreach (var scenario in Scenarios(suite))
        {
            var stage = scenario == "normal" ? "rollback" : scenario == "interruption" ? "recovery" : "install";
            var proof = ReadSharedObject(Path.Combine(Evidence(root, scenario), "proof-" + stage + ".json"));
            Require(Boolean(proof, "success"), "A required scenario is not qualified.");
            results.Add(proof);
        }
        var report = new JsonObject
        {
            ["schemaVersion"] = 2, ["kind"] = "pesto.native-update-qualification", ["success"] = true,
            ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["windowsVersion"] = Environment.OSVersion.VersionString,
            ["channel"] = suite.Channel,
            ["base"] = JsonSerializer.SerializeToNode(suite.Base, Json), ["candidate"] = JsonSerializer.SerializeToNode(suite.Candidate, Json),
            ["candidateZipSha256"] = suite.CandidateZipSha256,
            ["sourceUnchanged"] = true, ["baseUnchanged"] = true, ["candidateUnchanged"] = true, ["archiveUnchanged"] = true,
            ["profileSentinelUnchanged"] = true, ["distinctBuilds"] = true, ["syntheticVersions"] = false,
            ["zipAcquisitionQualified"] = true, ["uncQualification"] = false,
            ["nativeBinaryUpdateQualification"] = !newInstallation, ["inPlaceUpdateQualified"] = !newInstallation,
            ["formatRefusalQualified"] = newInstallation, ["newInstallationRequired"] = newInstallation, ["adQualification"] = false,
            ["scenarios"] = results
        };
        Save(Path.Combine(root, "evidence", "proof.json"), report); return report;
    }

    internal static SuiteState Load(string root)
    {
        root = Root(root);
        var state = Read<SuiteState>(Path.Combine(root, "qualification.json"));
        Require(state.SchemaVersion == 2 && state.Id == Path.GetFileName(root)[Prefix.Length..]
            && state.Channel is "PROD" or "DEV" && IsHash(state.CandidateZipSha256) && IsHash(state.SentinelSha256), "Fixture identity mismatch.");
        foreach (var package in new[] { state.Base, state.Candidate })
        {
            var item = package ?? throw new InvalidOperationException("Source package identity is missing.");
            Require(item.Channel == state.Channel && IsHash(item.Fingerprint)
                && IsHash(item.ExecutableSha256) && IsHash(item.RuntimeFingerprint)
                && Regex.IsMatch(item.SourceCommit, "^[0-9a-f]{40}$") && Version.TryParse(item.Version, out var version) && version.Major == 2,
                "Source package identity is incomplete.");
            _ = LocalPath(item.Directory);
            Require(!Within(item.Directory, root) && !Within(root, item.Directory) && !SamePath(item.Directory, root), "Source lies in the disposable fixture.");
        }
        _ = LocalPath(state.CandidateZip);
        Require(!Within(state.CandidateZip, root) && !Within(root, state.CandidateZip) && !SamePath(state.CandidateZip, root)
            && state.CandidateZip.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)
            && !SamePath(state.Base.Directory, state.Candidate.Directory)
            && state.Base.ExecutableSha256 != state.Candidate.ExecutableSha256 && state.Base.SourceCommit != state.Candidate.SourceCommit
            && Version.Parse(state.Candidate.Version) >= Version.Parse(state.Base.Version),
            "Two distinct builds and a separate ZIP are required.");
        return state;
    }
    internal static CaseState Case(string root, string scenario)
    {
        var suite = Load(root); var directory = CaseDirectory(root, scenario); var state = Read<CaseState>(Path.Combine(directory, "case.json"));
        Require(state.SchemaVersion == 2 && state.Scenario == scenario && Scenarios(suite).Contains(scenario)
            && state.InitialFingerprint == suite.Base.Fingerprint && IsHash(state.CandidateFingerprint)
            && state.CandidateVersion == suite.Candidate.Version && state.Acquisition == (RealCandidate(scenario) ? "zip" : "directory")
            && state.SyntheticFault == !RealCandidate(scenario) && (!RealCandidate(scenario) || state.CandidateFingerprint == suite.Candidate.Fingerprint)
            && Regex.IsMatch(state.TransactionId, "^[0-9a-f]{32}$")
            && Within(state.TransactionDirectory, directory) && state.HelperExecutable == Path.Combine(state.TransactionDirectory, "helper", "Pesto.exe"), "Case path/identity mismatch.");
        return state;
    }
    internal static string CaseDirectory(string root, string scenario) { Scenario(scenario); return Path.Combine(Root(root), "cases", scenario); }
    internal static string Evidence(string root, string scenario) { Scenario(scenario); return Path.Combine(Root(root), "evidence", scenario); }
    internal static void CheckUnchanged(string root, SuiteState suite)
    {
        Require(UpdatePackage.Hash(Path.Combine(Root(root), "profile-sentinel", "cfg.json")) == suite.SentinelSha256,
            "External profile sentinel changed.");
        Require(UpdatePackage.Validate(suite.Base.Directory, suite.Channel).Fingerprint == suite.Base.Fingerprint, "Original base pack changed.");
        Require(UpdatePackage.Validate(suite.Candidate.Directory, suite.Channel).Fingerprint == suite.Candidate.Fingerprint, "Original candidate pack changed.");
        Require(File.Exists(suite.CandidateZip) && UpdatePackage.Hash(suite.CandidateZip) == suite.CandidateZipSha256, "Original candidate ZIP changed or is missing.");
    }
    internal static JsonObject ReadSharedObject(string path)
    {
        UpdatePackage.RequireNoLinks(path);
        using var memory = new MemoryStream();
        // FileShare.Delete does not guarantee that Windows permits a concurrent overwrite move.
        // Close the journal before JSON parsing, which can otherwise prolong the open handle.
        using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        {
            const int maximum = 256 * 1024;
            Require(stream.Length <= maximum, "Qualification JSON too large.");
            var buffer = new byte[4096];
            int read;
            while ((read = stream.Read(buffer, 0, Math.Min(buffer.Length, maximum + 1 - (int)memory.Length))) > 0)
            {
                memory.Write(buffer, 0, read);
                Require(memory.Length <= maximum, "Qualification JSON too large.");
            }
        }
        memory.Position = 0;
        return JsonNode.Parse(memory) as JsonObject ?? throw new InvalidOperationException("Qualification object expected.");
    }
    internal static T Read<T>(string path) => ReadSharedObject(path).Deserialize<T>(Json) ?? throw new InvalidOperationException("Missing qualification record.");
    internal static void Save<T>(string path, T value) => UpdatePackage.WriteAtomic(path, JsonSerializer.Serialize(value, Json));
    internal static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    internal static string Text(JsonObject value, string name) => value[name]?.GetValue<string>() ?? "";
    internal static bool Boolean(JsonObject value, string name) => value[name]?.GetValue<bool>() == true;
    internal static bool Within(string path, string parent) => Path.GetFullPath(path).StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(parent)) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    // A LIGHT pack browses with the machine-wide Evergreen WebView2. Outside a case, only that exact browser image
    // is admitted, and only as a descendant of the helper; its file is never read or hashed.
    internal static bool IsEvergreenBrowser(string path) =>
        Path.GetFileName(path).Equals("msedgewebview2.exe", StringComparison.OrdinalIgnoreCase)
        && new[] { Environment.SpecialFolder.ProgramFilesX86, Environment.SpecialFolder.ProgramFiles }
            .Select(Environment.GetFolderPath).Where(folder => folder.Length > 0)
            .Any(folder => Within(path, Path.Combine(folder, "Microsoft", "EdgeWebView", "Application")));
    internal static string Root(string root)
    {
        root = LocalPath(root); var name = Path.GetFileName(root);
        Require(Within(root, Path.GetTempPath()) && Regex.IsMatch(name, "^" + Prefix + "[0-9a-f]{32}$"), "A dedicated named child of the local Temp directory is required.");
        return root;
    }
    private static string NewRoot(string root) { root = Root(root); Require(!Directory.Exists(root) && !File.Exists(root), "Never reuse/overwrite an existing qualification root."); return root; }
    private static string LocalPath(string path)
    {
        Require(Path.IsPathFullyQualified(path) && !path.StartsWith("\\\\", StringComparison.Ordinal) && !path.StartsWith("//", StringComparison.Ordinal)
            && !path.Any(char.IsControl), "A fully qualified local path is required; no UNC or URL.");
        var full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        if (OperatingSystem.IsWindows()) Require(new DriveInfo(Path.GetPathRoot(full)!).DriveType == DriveType.Fixed,
            "Qualification accepts local fixed drives only; no mapped/network volume.");
        UpdatePackage.RequireNoLinks(full); return full;
    }
    private static void Scenario(string scenario) => Require(KnownScenarios.Contains(scenario, StringComparer.Ordinal), "Unknown fixture scenario.");
    private static UpdateService Service(string root, string scenario, SuiteState suite) => new(new(
        Path.Combine(CaseDirectory(root, scenario), "installation"), Path.Combine(CaseDirectory(root, scenario), "state"), suite.Channel, false));
    private static bool Passed(JsonObject value) => Text(value, "status") == "passed" && Boolean(value, "accepted")
        && value["proof"] is JsonObject p && Boolean(p, "success") && Boolean(p, "webViewReady") && Boolean(p, "closeReturned");
    private static bool SamePath(string first, string second) => string.Equals(Path.TrimEndingDirectorySeparator(Path.GetFullPath(first)),
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(second)), StringComparison.OrdinalIgnoreCase);
    private static bool IsHash(string? value) => value is not null && Regex.IsMatch(value, "^[0-9a-f]{64}$");
    private static SuitePackage ReadSource(string directory)
    {
        var info = UpdatePackage.Validate(directory);
        Require((info.Distribution is "candidate" or "official") && info.ConfigurationFingerprint is null,
            "Native qualification accepts complete, uncustomized candidate or official packs only.");
        using var manifest = UpdatePackage.ReadJson(Path.Combine(directory, UpdatePackage.ManifestPath));
        var commit = manifest.RootElement.GetProperty("sourceCommit").GetString() ?? "";
        Require(Regex.IsMatch(commit, "^[0-9a-f]{40}$")
            && manifest.RootElement.GetProperty("official").ValueKind == (info.Distribution == "official" ? JsonValueKind.True : JsonValueKind.False)
            && manifest.RootElement.GetProperty("qualification").GetString() == "unqualified", "Build provenance/distribution metadata is incomplete.");
        return new(directory, info.Fingerprint, info.Version, info.Channel, UpdatePackage.Hash(Path.Combine(directory, "Pesto.exe")), RuntimeFingerprint(directory), commit);
    }
    // Runner evidence for an extracted Socle: exact pack validation and deep inspection, refusal code kept.
    internal static JsonObject SocleCheck(string pack)
    {
        pack = LocalPath(pack);
        var (state, problem) = SocleRuntime.Inspect(pack, deep: true);
        var proof = new JsonObject { ["schemaVersion"] = 1, ["kind"] = "pesto.socle-check", ["socleState"] = state.ToString(), ["problem"] = problem };
        try
        {
            var info = UpdatePackage.Validate(pack);
            proof["valid"] = true; proof["soclePresent"] = info.SoclePresent; proof["fingerprint"] = info.Fingerprint;
        }
        catch (Pesto.Core.PestoException error) { proof["valid"] = false; proof["code"] = error.Code; proof["message"] = error.Message; }
        return proof;
    }
    internal static string RuntimeFingerprint(string pack)
    {
        var root = Path.Combine(pack, "wad", "runtime", "webview2");
        // LIGHT packs ship no runtime: an absent Socle is the empty canonical, still a stable 64-hex identity.
        var canonical = !Directory.Exists(root) ? "" : string.Join('\n', UpdatePackage.Inventory(root).Keys.Order(StringComparer.Ordinal).Select(p => UpdatePackage.Hash(Path.Combine(root, p)) + "  " + p)) + "\n";
        return Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));
    }
    private static void ValidateVariant(string source, string candidate, string scenario)
    {
        var original = UpdatePackage.Inventory(source); var changed = UpdatePackage.Inventory(candidate);
        var allowed = new HashSet<string>(StringComparer.Ordinal) { UpdatePackage.ManifestPath, UpdatePackage.SumsPath, "wad/docs/SYNTHETIC-UPDATE-QUALIFICATION.txt" };
        if (scenario != "normal") allowed.Add("wad/web/index.html");
        foreach (var name in original.Keys.Union(changed.Keys, StringComparer.Ordinal))
            if (!allowed.Contains(name)) Require(original.ContainsKey(name) && changed.ContainsKey(name)
                && UpdatePackage.Hash(Path.Combine(source, name)) == UpdatePackage.Hash(Path.Combine(candidate, name)), "Fixture changed an unauthorized file: " + name);
        var expectedManifest = JsonNode.Parse(File.ReadAllText(Path.Combine(source, UpdatePackage.ManifestPath)))!.AsObject();
        expectedManifest.Remove("sourceCommit");
        var actualManifest = JsonNode.Parse(File.ReadAllText(Path.Combine(candidate, UpdatePackage.ManifestPath)))!;
        Require(JsonNode.DeepEquals(expectedManifest, actualManifest), "Only the intact-tree source claim may be removed from a fault fixture manifest; version/channel remain real.");
    }
}

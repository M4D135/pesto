using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Pesto.Engine;

namespace Pesto.UpdateQualification;

internal sealed record UiRequest(int SchemaVersion, string Kind, string RequestId, string Root, string Installation,
    string CandidateZip, string ReportDirectory, string Channel, string SourceFingerprint, string TargetFingerprint,
    string SourceExecutableSha256, string TargetExecutableSha256, string SourceCommit, string TargetSourceCommit,
    string CandidateZipSha256);
internal sealed record UiParentLaunch(int ProcessId, string StartUtcTicks, string Executable);

/// <summary>
/// An actual MainForm creates the install request. This companion only creates a disposable installation,
/// binds the observed UI/parent/helper identities, and verifies the native result and explicit service rollback.
/// No successful API response, transaction, or helper launch is supplied to the UI by this companion.
/// </summary>
internal static class UiSuite
{
    internal const string RequestKind = "pesto.native-update-ui-request";
    private const string Scenario = "normal";
    private static readonly string[] ExpectedChecks =
    [
        "requestBoundToRunningCopy", "twoDistinctBuilds", "sourceZipExact", "parentReady", "isolatedConfigurationPage",
        "nativeZipSelectionExact", "candidateInspectedFromButton", "noTransactionBeforePreparation", "preparedFromButton",
        "preparedCopyExact", "installWaitsForConfirmation", "installCancellationPreservedPreparation", "installReconfirmedFromUi",
        "singleInstallBridgeRequest", "singleNativeHostRequest", "transactionBoundToUiRequest", "parentClosedNormally",
        "installationUnchangedBeforeHandoff", "profileDataPreserved", "sourceZipUnchanged", "noForbiddenEffects", "helperLaunchedAfterParentClose"
    ];
    private static readonly string[] ExpectedCaptures = ["coexistence/maintenance-prepared.png", "coexistence/maintenance-install-confirmation.png"];

    internal static UiRequest Create(string currentPack, string targetPack, string targetZip, string root)
    {
        var suite = Suite.Create(currentPack, targetPack, targetZip, root);
        var installation = Path.Combine(Suite.CaseDirectory(root, Scenario), "installation");
        Directory.CreateDirectory(Suite.CaseDirectory(root, Scenario));
        Directory.CreateDirectory(Suite.Evidence(root, Scenario));
        UpdatePackage.CopyToNew(suite.Base.Directory, installation, suite.Base.Fingerprint);
        Suite.Require(UpdateTransaction.List(installation).Count == 0,
            "A new UI fixture must have no prepared transaction or reused request.");
        var request = new UiRequest(1, RequestKind, suite.Id, Suite.Root(root), installation,
            suite.CandidateZip, Path.Combine(Suite.Evidence(root, Scenario), "ui"), suite.Channel,
            suite.Base.Fingerprint, suite.Candidate.Fingerprint, suite.Base.ExecutableSha256, suite.Candidate.ExecutableSha256,
            suite.Base.SourceCommit, suite.Candidate.SourceCommit, suite.CandidateZipSha256);
        Suite.Save(Path.Combine(root, "ui-request.json"), request);
        Suite.CheckUnchanged(root, suite);
        return request;
    }

    internal static JsonObject Adopt(string root)
    {
        var suite = Suite.Load(root); Suite.CheckUnchanged(root, suite);
        var request = Request(root, suite);
        var proof = UiProof(request);
        Suite.Require(Suite.Text(proof, "sourceVersion") == suite.Base.Version && Suite.Text(proof, "targetVersion") == suite.Candidate.Version,
            "The UI must display both unchanged real build versions.");
        var parent = Suite.Read<UiParentLaunch>(Path.Combine(Suite.Evidence(root, Scenario), "ui-parent-launch.json"));
        var validParentTicks = long.TryParse(parent.StartUtcTicks, NumberStyles.None, CultureInfo.InvariantCulture, out var parentTicks);
        Suite.Require(parent.ProcessId > 0 && validParentTicks
            && parentTicks > 0 && SamePath(parent.Executable, Path.Combine(request.Installation, "Pesto.exe")),
            "The independently captured UI parent identity is incomplete.");
        Suite.Require(proof["parentProcessId"]?.GetValue<int>() == parent.ProcessId
            && Suite.Text(proof, "parentStartUtcTicks") == parent.StartUtcTicks,
            "The UI proof does not describe the process created by the orchestrator.");
        var exit = Suite.ReadSharedObject(Path.Combine(Suite.Evidence(root, Scenario), "ui-parent-exit.json"));
        Suite.Require(exit["processId"]?.GetValue<int>() == parent.ProcessId
            && Suite.Text(exit, "startUtcTicks") == parent.StartUtcTicks
            && exit["exitCode"]?.GetValue<int>() == 0 && Suite.Boolean(exit, "exited"),
            "The UI parent did not exit normally before the native handoff was adopted.");

        var install = Suite.Read<UpdateInstallRequest>(Path.Combine(request.ReportDirectory, "request-install.json"));
        var launch = Suite.Read<LaunchReceipt>(Path.Combine(request.ReportDirectory, "launch-install.json"));
        Suite.Require(install.Action == "install" && Regex.IsMatch(install.TransactionId, "^[a-f0-9]{32}$")
            && Suite.Text(proof, "transactionId") == install.TransactionId
            && Suite.Within(install.TransactionDirectory, Suite.CaseDirectory(root, Scenario))
            && SamePath(install.HelperExecutable, Path.Combine(install.TransactionDirectory, "helper", "Pesto.exe")),
            "The UI returned an unowned installation request.");
        UpdatePackage.RequireNoLinks(install.TransactionDirectory);
        UpdateTransaction.ValidateHelperInvocation(install.TransactionDirectory, install.HelperExecutable);
        Suite.Require(UpdatePackage.Hash(install.HelperExecutable) == suite.Base.ExecutableSha256,
            "The launched helper was not copied from the reviewed current UI build.");
        var transactions = UpdateTransaction.List(request.Installation);
        Suite.Require(transactions.Count == 1 && transactions[0].Id == install.TransactionId
            && SamePath(transactions[0].TransactionDirectory, install.TransactionDirectory),
            "Exactly one transaction created by this UI is required.");
        var journal = Suite.ReadSharedObject(Path.Combine(install.TransactionDirectory, "transaction.json"));
        Suite.Require(Suite.Text(journal, "id") == install.TransactionId
            && SamePath(Suite.Text(journal, "installation"), request.Installation)
            && journal["parentProcessId"]?.GetValue<int>() == parent.ProcessId
            && journal["parentStartUtc"]?.GetValue<DateTimeOffset>().UtcTicks == parentTicks
            && Suite.Text(journal, "action") == "install"
            && Suite.Text(journal, "channel") == suite.Channel
            && Suite.Text(journal, "currentFingerprint") == suite.Base.Fingerprint
            && Suite.Text(journal, "nextFingerprint") == suite.Candidate.Fingerprint
            && Suite.Text(journal, "currentExecutableHash") == suite.Base.ExecutableSha256
            && Suite.Text(journal, "helperHash") == suite.Base.ExecutableSha256
            && Suite.Text(journal, "nextExecutableHash") == suite.Candidate.ExecutableSha256
            && Suite.Text(journal, "currentVersion") == suite.Base.Version
            && Suite.Text(journal, "nextVersion") == suite.Candidate.Version,
            "The durable transaction is not bound to the actual UI parent and both exact builds.");
        Suite.Require(launch.ProcessId > 0 && launch.ProcessId != parent.ProcessId
            && proof["helperProcessId"]?.GetValue<int>() == launch.ProcessId
            && long.TryParse(launch.StartUtcTicks, NumberStyles.None, CultureInfo.InvariantCulture, out var helperTicks)
            && helperTicks >= parentTicks && SamePath(launch.Executable, install.HelperExecutable)
            && launch.TransactionId == install.TransactionId,
            "The UI helper launch receipt does not match the real installation request.");

        var state = new CaseState(2, Scenario, suite.Base.Fingerprint, suite.Candidate.Fingerprint,
            suite.Candidate.Version, "zip", false, install.TransactionDirectory, install.HelperExecutable, install.TransactionId);
        var statePath = Path.Combine(Suite.CaseDirectory(root, Scenario), "case.json");
        Suite.Require(!File.Exists(statePath), "A UI request may be adopted only once; previous evidence must remain intact.");
        Suite.Save(statePath, state);
        Suite.Save(Path.Combine(Suite.Evidence(root, Scenario), "fixture.json"), state);
        Suite.Save(Path.Combine(Suite.Evidence(root, Scenario), "request-install.json"), install);
        Suite.Save(Path.Combine(Suite.Evidence(root, Scenario), "launch-install.json"), launch);
        Suite.Save(Path.Combine(Suite.Evidence(root, Scenario), "journal-ui-handoff.json"), journal);
        Suite.Save(Path.Combine(Suite.Evidence(root, Scenario), "acquisition.json"), new
        {
            schemaVersion = 1, sourceKind = "zip", inspectedFingerprint = suite.Candidate.Fingerprint,
            preparedFingerprint = suite.Candidate.Fingerprint, version = suite.Candidate.Version,
            archiveSha256 = suite.CandidateZipSha256, candidateSourceCommit = suite.Candidate.SourceCommit,
            syntheticFault = false, syntheticVersion = false, directoryFallback = false,
            uiPreparedAndConfirmed = true, installationOutcomeNotYetQualified = true
        });
        return new JsonObject
        {
            ["success"] = true, ["requestId"] = request.RequestId, ["transactionId"] = install.TransactionId,
            ["parentProcessId"] = parent.ProcessId, ["helperProcessId"] = launch.ProcessId,
            ["nativeUpdateInstallFromUiQualified"] = false
        };
    }

    internal static JsonObject Finish(string root)
    {
        var suite = Suite.Load(root); Suite.CheckUnchanged(root, suite);
        var request = Request(root, suite); var ui = UiProof(request);
        var install = Suite.ReadSharedObject(Path.Combine(Suite.Evidence(root, Scenario), "proof-install.json"));
        var rollback = Suite.ReadSharedObject(Path.Combine(Suite.Evidence(root, Scenario), "proof-rollback.json"));
        Suite.Require(Suite.Boolean(install, "success") && Suite.Text(install, "status") == "completed"
            && Suite.Boolean(rollback, "success") && Suite.Text(rollback, "status") == "rolledBack"
            && Suite.Text(install, "transactionId") == Suite.Text(rollback, "transactionId")
            && Suite.Text(install, "executableSha256") == suite.Candidate.ExecutableSha256
            && Suite.Text(rollback, "executableSha256") == suite.Base.ExecutableSha256
            && install["healthAttemptCount"]?.GetValue<int>() == 1 && rollback["healthAttemptCount"]?.GetValue<int>() == 2,
            "Both a native installation and a distinct, healthy service rollback are required.");
        Suite.Require(!Directory.Exists(Suite.CaseDirectory(root, Scenario)),
            "The verified disposable installation must be removed only after its successful explicit rollback.");
        var cleanup = Suite.ReadSharedObject(Path.Combine(Suite.Evidence(root, Scenario), "ui-cleanup.json"));
        Suite.Require(Suite.Boolean(cleanup, "success") && Suite.Boolean(cleanup, "profileDataPreserved")
            && Suite.Boolean(cleanup, "profileDataRemoved") && !Directory.Exists(ProfileData(request)),
            "The isolated operator configuration must be verified after rollback, then its owned temporary data removed.");
        var report = new JsonObject
        {
            ["schemaVersion"] = 1, ["kind"] = "pesto.native-update-ui-qualification", ["success"] = true,
            ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["windowsVersion"] = Environment.OSVersion.VersionString,
            ["channel"] = suite.Channel, ["requestId"] = request.RequestId,
            ["current"] = JsonSerializer.SerializeToNode(suite.Base, Suite.Json),
            ["target"] = JsonSerializer.SerializeToNode(suite.Candidate, Suite.Json),
            ["targetZipSha256"] = suite.CandidateZipSha256,
            ["direction"] = "current-pack-to-selected-target-then-rollback-to-current",
            ["nativeUpdateInstallFromUiQualified"] = true, ["nativeRollbackFromUiQualified"] = false,
            ["nativeServiceRollbackQualified"] = true, ["parentClosed"] = true, ["helperLaunched"] = true,
            ["sourceUnchanged"] = true, ["profileSentinelUnchanged"] = true, ["ownedInstallationRemoved"] = true,
            ["profileDataPreserved"] = true, ["profileDataRemoved"] = true,
            ["distinctBuilds"] = true, ["syntheticVersions"] = false, ["zipAcquisitionQualified"] = true,
            ["adQualification"] = false, ["adExecuted"] = false, ["realUac"] = false,
            ["ordinaryProfileAccess"] = false, ["uncQualification"] = false,
            ["uiProof"] = ui.DeepClone(), ["installation"] = install, ["rollback"] = rollback
        };
        Suite.Save(Path.Combine(root, "evidence", "ui-proof.json"), report);
        return report;
    }

    internal static JsonObject Verify(string root, string stage)
    {
        Suite.Require(stage is "install" or "rollback", "Unknown UI transaction verification stage.");
        var proof = Suite.Verify(root, Scenario, stage);
        var request = Request(root, Suite.Load(root));
        var profile = CheckProfile(request);
        profile["stage"] = stage;
        Suite.Save(Path.Combine(Suite.Evidence(root, Scenario), "ui-profile-" + stage + ".json"), profile);
        return proof;
    }

    internal static JsonObject Cleanup(string root)
    {
        var request = Request(root, Suite.Load(root));
        var profile = CheckProfile(request);
        foreach (var stage in new[] { "install", "rollback" })
        {
            var check = Suite.ReadSharedObject(Path.Combine(Suite.Evidence(root, Scenario), "ui-profile-" + stage + ".json"));
            Suite.Require(Suite.Boolean(check, "success") && Suite.Boolean(check, "profileDataPreserved")
                && Suite.Text(check, "profileConfigurationSha256") == Suite.Text(profile, "profileConfigurationSha256"),
                "The same operator configuration must be preserved after installation and rollback.");
        }
        _ = Suite.Cleanup(root, Scenario);
        var data = ProfileData(request);
        var pending = new Stack<string>(); pending.Push(data);
        while (pending.Count > 0)
            foreach (var entry in Directory.EnumerateFileSystemEntries(pending.Pop()))
            {
                UpdatePackage.RequireNoLinks(entry);
                if (Directory.Exists(entry)) pending.Push(entry);
            }
        Directory.Delete(data, true);
        var proof = new JsonObject
        {
            ["success"] = true, ["requestId"] = request.RequestId, ["ownedInstallationRemoved"] = true,
            ["profileDataPreserved"] = true, ["profileDataRemoved"] = !Directory.Exists(data),
            ["profileConfigurationSha256"] = Suite.Text(profile, "profileConfigurationSha256")
        };
        Suite.Save(Path.Combine(Suite.Evidence(root, Scenario), "ui-cleanup.json"), proof);
        return proof;
    }

    internal static UiRequest Request(string root, SuiteState suite)
    {
        var request = Suite.Read<UiRequest>(Path.Combine(Suite.Root(root), "ui-request.json"));
        Suite.Require(request.SchemaVersion == 1 && request.Kind == RequestKind && request.RequestId == suite.Id
            && SamePath(request.Root, root) && SamePath(request.Installation, Path.Combine(Suite.CaseDirectory(root, Scenario), "installation"))
            && SamePath(request.ReportDirectory, Path.Combine(Suite.Evidence(root, Scenario), "ui"))
            && SamePath(request.CandidateZip, suite.CandidateZip) && request.Channel == suite.Channel
            && request.SourceFingerprint == suite.Base.Fingerprint && request.TargetFingerprint == suite.Candidate.Fingerprint
            && request.SourceExecutableSha256 == suite.Base.ExecutableSha256 && request.TargetExecutableSha256 == suite.Candidate.ExecutableSha256
            && request.SourceCommit == suite.Base.SourceCommit && request.TargetSourceCommit == suite.Candidate.SourceCommit
            && request.CandidateZipSha256 == suite.CandidateZipSha256,
            "The UI request does not match the independently recorded source packages.");
        return request;
    }

    private static JsonObject UiProof(UiRequest request)
    {
        var proof = Suite.ReadSharedObject(Path.Combine(request.ReportDirectory, "proof.json"));
        Suite.Require(proof["schemaVersion"]?.GetValue<int>() == 1 && Suite.Text(proof, "kind") == "pesto.native-update-ui-handoff"
            && Suite.Text(proof, "uiScope") == "mainform-webview2-zip-install-confirmation-and-native-handoff"
            && Suite.Text(proof, "requestId") == request.RequestId && Suite.Text(proof, "channel") == request.Channel
            && Suite.Text(proof, "sourceCommit") == request.SourceCommit && Suite.Text(proof, "targetSourceCommit") == request.TargetSourceCommit
            && Suite.Text(proof, "sourceFingerprint") == request.SourceFingerprint && Suite.Text(proof, "targetFingerprint") == request.TargetFingerprint
            && Suite.Text(proof, "sourceExecutableSha256") == request.SourceExecutableSha256
            && Suite.Text(proof, "targetExecutableSha256") == request.TargetExecutableSha256
            && Suite.Text(proof, "candidateZipSha256") == request.CandidateZipSha256,
            "The UI proof is not bound to the exact reviewed request and build identities.");
        foreach (var field in new[] { "success", "parentClosed", "helperLaunched", "uiInstallConfirmationQualified" })
            Suite.Require(proof[field]?.GetValue<bool>() == true, "The UI proof is missing a required positive observation: " + field);
        foreach (var field in new[] { "adQualification", "adExecuted", "realUac", "ordinaryProfileAccess", "uncQualification", "nativeUpdateInstallFromUiQualified" })
            Suite.Require(proof[field]?.GetValue<bool>() == false, "The UI handoff overclaims an unobserved outcome: " + field);
        foreach (var field in new[] { "forbiddenBackendInvocations", "forbiddenHostInvocations" })
            Suite.Require(proof[field]?.GetValue<int>() == 0, "The UI proof has an unexpected invocation: " + field);
        foreach (var field in new[] { "profileDataPreserved", "sourceZipUnchanged", "installationUnchangedBeforeHandoff" })
            Suite.Require(proof[field]?.GetValue<bool>() == true, "The UI proof is missing source/profile preservation: " + field);
        Suite.Require(proof["checks"] is JsonArray checks && checks.Select(value => value?.GetValue<string>()).SequenceEqual(ExpectedChecks),
            "The UI proof does not contain all 22 named observations in their actual execution order.");
        // From 2.0.15 the bench first opens the « Mises à jour » section of the settings page (ShowUpdates, a rail click proved
        // in the same evaluation); a proof made by an earlier baseline (962f3ba) starts with the picker. Nothing else is optional.
        string[] pickerToConfirmation = ["UpdateZip", "PrepareUpdate", "InstallUpdate", "CancelInstall", "InstallUpdate", "ConfirmInstall"];
        Suite.Require(proof["uiSteps"] is JsonArray steps
            && steps.OfType<JsonObject>().Select(value => Suite.Text(value, "step")).ToArray() is var names
            && (names.SequenceEqual(pickerToConfirmation) || names.SequenceEqual(["ShowUpdates", .. pickerToConfirmation]))
            && steps.All(value => value is JsonObject step && Suite.Boolean(step, "accepted") && Suite.Text(step, "source") == "dom"),
            "The confirmation must follow the actual picker, preparation, cancellation and explicit second confirmation.");
        Suite.Require(proof["captures"] is JsonArray captures && captures.Select(value => value?.GetValue<string>()).SequenceEqual(ExpectedCaptures),
            "Both native WebView2 screenshots are required.");
        foreach (var capture in ExpectedCaptures)
        {
            var path = Path.Combine(request.ReportDirectory, capture); UpdatePackage.RequireNoLinks(path);
            using var stream = File.OpenRead(path); var signature = new byte[8];
            Suite.Require(stream.Length > 8 && stream.Read(signature, 0, signature.Length) == signature.Length
                && signature.SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }), "The named capture is not a real PNG file.");
        }
        var selectedZip = Path.Combine(ProfileData(request), "candidate.zip");
        Suite.Require(proof["dialogObservations"] is JsonArray dialogs && dialogs.Count == 1 && dialogs[0] is JsonObject dialog
            && Suite.Text(dialog, "kind") == "file" && Suite.Boolean(dialog, "pathRequired")
            && SamePath(Suite.Text(dialog, "requestedPath"), selectedZip) && Suite.Boolean(dialog, "pathReadBackExact")
            && Suite.Boolean(dialog, "buttonFocusConfirmed") && Suite.Boolean(dialog, "clicked") && Suite.Boolean(dialog, "closedAfterClick")
            && dialog["stableReads"]?.GetValue<int>() >= 3 && dialog["editControlId"]?.GetValue<int>() is 1001 or 1148,
            "The exact ZIP must be positively selected through the observed native file dialog.");
        var calls = proof["backendCalls"] as JsonArray ?? throw new InvalidOperationException("Backend observations are missing.");
        foreach (var operation in new[] { "updates.inspect", "updates.prepare", "updates.install" })
            Suite.Require(calls.OfType<JsonObject>().Count(call => Suite.Text(call, "operation") == operation) == 1,
                "Exactly one real backend call is required for " + operation);
        Suite.Require(calls.OfType<JsonObject>().Where(call => Suite.Text(call, "operation") is "updates.inspect" or "updates.prepare" or "updates.install")
            .All(call => Suite.Boolean(call, "completed") && Suite.Text(call, "failureCode").Length == 0),
            "An incomplete or failed maintenance backend call cannot qualify the UI flow.");
        var inspect = calls.OfType<JsonObject>().Single(call => Suite.Text(call, "operation") == "updates.inspect");
        var prepare = calls.OfType<JsonObject>().Single(call => Suite.Text(call, "operation") == "updates.prepare");
        var install = calls.OfType<JsonObject>().Single(call => Suite.Text(call, "operation") == "updates.install");
        var inspected = inspect["result"] as JsonObject ?? throw new InvalidOperationException("The inspected package response is missing.");
        var prepared = prepare["result"] as JsonObject ?? throw new InvalidOperationException("The preparation response is missing.");
        Suite.Require(Suite.Text(inspect, "kind") == "zip"
            && Suite.Text(inspected, "fingerprint") == request.TargetFingerprint
            && Suite.Text(inspected, "version") == Suite.Text(proof, "targetVersion")
            && Suite.Text(inspected, "candidateId").Length > 0 && Suite.Text(inspected, "candidateId") == Suite.Text(proof, "candidateId")
            && Suite.Text(prepare, "candidateId") == Suite.Text(inspected, "candidateId")
            && Suite.Text(prepared, "fingerprint") == request.TargetFingerprint
            && Suite.Text(prepared, "version") == Suite.Text(proof, "targetVersion")
            && Suite.Text(prepared, "preparedId").Length > 0 && Suite.Text(prepared, "preparedId") == Suite.Text(proof, "preparedId")
            && inspect["sequence"]?.GetValue<int>() < prepare["sequence"]?.GetValue<int>()
            && prepare["sequence"]?.GetValue<int>() < install["sequence"]?.GetValue<int>(),
            "The recorded inspection, preparation and installation must bind the same exact target in sequence.");
        Suite.Require(Suite.Boolean(install, "confirmed") && Suite.Text(install, "preparedId") == Suite.Text(proof, "preparedId")
            && install["result"] is JsonObject result && Suite.Text(result, "status") == "closing"
            && Suite.Text(result, "transactionId") == Suite.Text(proof, "transactionId"),
            "The observed confirmed installation call must bind the prepared candidate and handoff transaction.");
        var targetVersion = Suite.Text(proof, "targetVersion");
        Suite.Require(Version.TryParse(targetVersion, out _) && proof["preparedObservation"] is JsonObject displayed
            && Suite.Text(displayed, "version") == targetVersion && Suite.Text(displayed, "channel") == request.Channel
            && Suite.Text(displayed, "source") == "local"
            && Suite.Text(displayed, "text").Contains(targetVersion, StringComparison.Ordinal)
            && Suite.Text(displayed, "text").Contains(request.Channel, StringComparison.Ordinal)
            && Suite.Text(displayed, "text").Contains("Source locale — origine à vérifier", StringComparison.Ordinal)
            && proof["confirmationObservation"] is JsonObject confirmation
            && Suite.Text(confirmation, "title") == "Installer la mise à jour préparée"
            && Suite.Text(confirmation, "body").Contains(targetVersion, StringComparison.Ordinal)
            && Suite.Text(confirmation, "body").Contains(request.Channel, StringComparison.Ordinal)
            && Suite.Text(confirmation, "body").Contains("Source locale — origine à vérifier", StringComparison.Ordinal),
            "The prepared package and accepted confirmation must visibly identify version, channel and local origin.");
        var hosts = proof["hostCalls"] as JsonArray ?? throw new InvalidOperationException("Native host observations are missing.");
        Suite.Require(hosts.Count == 2 && hosts[0] is JsonObject source && Suite.Text(source, "action") == "source"
            && Suite.Text(source, "kind") == "zip" && Suite.Boolean(source, "completed")
            && source["cancelled"]?.GetValue<bool>() == false && Suite.Text(source, "failureCode").Length == 0
            && Suite.Boolean(source, "selectionObservedBeforeIo")
            && SamePath(Suite.Text(source, "selectedPath"), selectedZip) && SamePath(Suite.Text(source, "normalizedSelectedPath"), selectedZip)
            && hosts[1] is JsonObject handoff && Suite.Text(handoff, "action") == "install"
            && Suite.Boolean(handoff, "completed") && Suite.Text(handoff, "transactionId") == Suite.Text(proof, "transactionId"),
            "The native host must observe the exact selected ZIP before IO and hand off one matching install request.");
        return proof;
    }

    private static JsonObject CheckProfile(UiRequest request)
    {
        var proof = UiProof(request);
        var relative = Suite.Text(proof, "profileConfigurationRelativePath");
        Suite.Require(relative.Length > 0 && !Path.IsPathRooted(relative) && !relative.Contains('\\')
            && relative.Split('/').All(part => part.Length > 0 && part is not "." and not ".." && !part.Contains(':')),
            "The isolated configuration proof must identify a strict relative file path.");
        var path = Path.GetFullPath(Path.Combine(request.ReportDirectory, relative));
        Suite.Require(Suite.Within(path, ProfileData(request)), "The profile configuration lies outside the owned temporary data.");
        UpdatePackage.RequireNoLinks(path);
        var hash = Suite.Text(proof, "profileConfigurationSha256");
        Suite.Require(Regex.IsMatch(hash, "^[a-f0-9]{64}$") && UpdatePackage.Hash(path) == hash,
            "The operator configuration changed during the UI installation or rollback.");
        var archive = Path.Combine(ProfileData(request), "candidate.zip");
        UpdatePackage.RequireNoLinks(archive);
        Suite.Require(UpdatePackage.Hash(archive) == request.CandidateZipSha256,
            "The ZIP selected by the native picker must remain the exact supplied target archive.");
        return new JsonObject
        {
            ["success"] = true, ["requestId"] = request.RequestId, ["profileDataPreserved"] = true,
            ["profileConfigurationRelativePath"] = relative, ["profileConfigurationSha256"] = hash,
            ["selectedZipSha256"] = request.CandidateZipSha256
        };
    }

    private static string ProfileData(UiRequest request) => Path.Combine(request.ReportDirectory, "coexistence", "data");

    private static bool SamePath(string first, string second) => string.Equals(Path.GetFullPath(first).TrimEnd(Path.DirectorySeparatorChar),
        Path.GetFullPath(second).TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);
}

using System.Diagnostics;
using System.Globalization;
using System.Security.Principal;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>
/// Real maintenance DOM -> closed bridge -> services -> NativeHostActions -> normal close -> shared
/// helper launch. The external companion observes health/transaction completion after this process exits.
/// </summary>
internal static class NativeUpdateUiQualification
{
    private const string ZipTitle = "Choisir un pack Pesto V2";
    private const string InstallTitle = "Installer la mise à jour préparée";

    internal static int Run(string requestPath)
    {
        var fixture = UpdateUiQualificationRequest.Read(requestPath);
        Directory.CreateDirectory(fixture.ReportDirectory);
        using var currentProcess = Process.GetCurrentProcess();
        var proof = new JsonObject
        {
            ["schemaVersion"] = 1, ["kind"] = "pesto.native-update-ui-handoff", ["requestId"] = fixture.RequestId,
            ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["success"] = false, ["channel"] = fixture.Channel,
            ["uiScope"] = "mainform-webview2-zip-install-confirmation-and-native-handoff",
            ["uiDriver"] = "compiled-dom-input-and-click", ["fixtureSetup"] = "synthetic-configuration-before-mainform-start",
            ["parentProcessId"] = currentProcess.Id,
            ["parentStartUtcTicks"] = currentProcess.StartTime.ToUniversalTime().Ticks.ToString(CultureInfo.InvariantCulture),
            ["sourceCommit"] = fixture.SourceCommit, ["targetSourceCommit"] = fixture.TargetSourceCommit,
            ["sourceFingerprint"] = fixture.SourceFingerprint, ["targetFingerprint"] = fixture.TargetFingerprint,
            ["sourceExecutableSha256"] = fixture.SourceExecutableSha256, ["targetExecutableSha256"] = fixture.TargetExecutableSha256,
            ["candidateZipSha256"] = fixture.CandidateZipSha256,
            ["adExecuted"] = false, ["adQualification"] = false, ["realUac"] = false,
            ["ordinaryProfileAccess"] = false, ["uncQualification"] = false,
            // Handoff is not completion. Only the external companion can grant native installation
            // qualification after parent exit, exact helper observation and a durable health receipt.
            ["nativeUpdateInstallFromUiQualified"] = false, ["uiInstallConfirmationQualified"] = false,
            ["parentClosed"] = false, ["helperLaunched"] = false, ["timeoutSeconds"] = 480
        };
        var checks = new JsonArray(); proof["checks"] = checks;
        var steps = new JsonArray(); proof["uiSteps"] = steps;
        var captures = new JsonArray(); proof["captures"] = captures;
        UpdateUiQualificationBackend? observed = null;
        UpdateUiQualificationHost? host = null;
        JsonObject? lastUi = null;
        var stage = "fixture";
        var handoffReady = false;
        var parentClosed = false;
        var parentFailed = false;
        NativeConfigurationQualification.ResetDialogObservations();

        void Check(bool value, string name)
        {
            if (!value) throw new PestoException("qualification.update-ui." + name, "Contrôle natif non satisfait : " + name);
            checks.Add(name);
        }

        try
        {
            UpdateUiQualificationRequest.Require(WindowsElevation.IsElevated(), "already-elevated");
            var installed = UpdatePackage.Validate(fixture.Installation, fixture.Channel);
            var sourceManifest = ReadObject(Path.Combine(fixture.Installation, "wad", "Pesto.package.json"));
            Check(installed.Fingerprint == fixture.SourceFingerprint
                && UpdatePackage.Hash(Environment.ProcessPath!) == fixture.SourceExecutableSha256
                && Text(sourceManifest, "sourceCommit") == fixture.SourceCommit, "requestBoundToRunningCopy");
            Check(fixture.SourceCommit != fixture.TargetSourceCommit
                && fixture.SourceExecutableSha256 != fixture.TargetExecutableSha256, "twoDistinctBuilds");
            Check(UpdatePackage.Hash(fixture.CandidateZip) == fixture.CandidateZipSha256, "sourceZipExact");
            AppPaths.RequirePortableFiles(); HostPolicy.ClearBrowserOverrides();
            var scope = new DemoQualificationScope(fixture.ReportDirectory);
            var data = Path.Combine(scope.Root, "data");
            scope.RequireOwned(data); Directory.CreateDirectory(data);
            var selectedZip = Path.Combine(data, "candidate.zip");
            File.Copy(fixture.CandidateZip, selectedZip, false);
            UpdateUiQualificationRequest.Require(UpdatePackage.Hash(selectedZip) == fixture.CandidateZipSha256, "copied-zip");
            using var identity = WindowsIdentity.GetCurrent();
            var profile = new OperatorProfile(identity.User!.Value, Path.Combine(data, "LocalData"));
            var parentData = AppPaths.UserData(fixture.Channel, false, false, profile.LocalData);
            scope.RequireOwned(parentData);
            var configuration = new ProfileConfigurationService(parentData, profile.Sid, ConfigurationAccessMode.Live);
            configuration.Initialize();
            var initial = configuration.PreviewSettings(PestoJson.Element(new
            {
                domain = "example.local", dc = "", prefix = "111301", rootOu = "OU=Postes,DC=example,DC=local",
                preprodOu = "", preprodSite = "", production = true, randomNames = false, namingPattern = PestoSettings.DefaultPattern,
                sites = new[] { new { id = "paris", name = "Paris", code = "PA", ou = "OU=Paris,OU=Postes,DC=example,DC=local" } }
            }));
            _ = configuration.ApplyImport(Text(initial, "planId"), true);
            var configurationHash = UpdatePackage.Hash(configuration.ConfigurationPath);
            proof["profileConfigurationRelativePath"] = Path.GetRelativePath(fixture.ReportDirectory, configuration.ConfigurationPath).Replace('\\', '/');
            proof["profileConfigurationSha256"] = configurationHash;
            proof["profileDataRelativePath"] = "coexistence/data";
            var native = new NativeHostActions(profile, fixture.Channel, false);
            host = new(native, scope, fixture, selectedZip);
            native.EnableQualificationFileGuard(scope, host.ObserveSelectionBeforeIo);
            var updates = new UpdateService(new(fixture.Installation, Path.Combine(data, "updates"), fixture.Channel, false));
            var backend = new ApplicationServicesBackend(PestoBackend.CreateConfigurationOnly(parentData, gpRoot: Path.Combine(data, "GP")),
                false, configuration, updates, host, fixture.Installation);
            observed = new(backend);
            using (var parent = new MainForm(observed, false, false, fixture.Channel, parentData, initialPage: "parametres", configurationOnly: true))
            {
                parent.EnableQualification(scope); native.Owner = parent;
                using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(480));
                using var watchdog = new System.Windows.Forms.Timer { Interval = 1000 };
                watchdog.Tick += (_, _) =>
                {
                    if (!stop.IsCancellationRequested) return;
                    proof["failureCode"] ??= JsonValue.Create("qualification.update-ui.timeout");
                    NativeConfigurationQualification.CancelDialogs(parent.Handle); parent.Close();
                };
                parent.FormClosed += (_, _) => { parentClosed = true; parentFailed = parent.StartFailed; };
                async Task Act(UpdateUiQualificationStep step)
                {
                    var result = await parent.QualificationStepAsync(step).WaitAsync(stop.Token);
                    if (result != "true") throw new PestoException("qualification.update-ui.ui-action", "Le contrôle visible attendu n’est pas disponible.");
                    steps.Add(new JsonObject { ["step"] = step.ToString(), ["source"] = "dom", ["accepted"] = true });
                }
                void CheckBackendFailures()
                {
                    var refused = observed.Snapshot().OfType<JsonObject>().FirstOrDefault(call => Text(call, "failureCode").Length > 0);
                    if (refused is null) return;
                    proof["backendFailure"] = refused;
                    throw new PestoException(Text(refused, "failureCode"), "Le service réel a refusé le parcours UI de qualification.");
                }
                async Task<JsonObject> WaitUi(Func<JsonObject, bool> predicate, int seconds = 120)
                {
                    var watch = Stopwatch.StartNew();
                    do
                    {
                        stop.Token.ThrowIfCancellationRequested(); CheckBackendFailures();
                        if (parent.StartFailed) throw new PestoException("qualification.update-ui.webview", "La fenêtre native n’est pas prête.");
                        var raw = await parent.QualificationStepAsync(UpdateUiQualificationStep.Snapshot).WaitAsync(stop.Token);
                        if (raw.Length > 256 * 1024) throw new PestoException("qualification.update-ui.snapshot", "Observation trop volumineuse.");
                        if (JsonNode.Parse(raw) is JsonObject state)
                        {
                            lastUi = state;
                            if (predicate(state)) return state;
                        }
                        await Task.Delay(100, stop.Token);
                    } while (watch.Elapsed < TimeSpan.FromSeconds(seconds));
                    throw new PestoException("qualification.update-ui.wait", "L’état attendu de l’interface n’est pas prouvé.");
                }
                async Task Capture(string name)
                {
                    await WaitUi(state => !Flag(state, "finiteAnimationsRunning"));
                    await parent.QualificationCaptureAsync(name).WaitAsync(stop.Token);
                    captures.Add("coexistence/" + name);
                }
                bool Returned(string operation) => Flag(observed.Last(operation), "completed") && Text(observed.Last(operation), "failureCode").Length == 0;
                JsonObject Result(string operation) => observed.Last(operation)?["result"] as JsonObject
                    ?? throw new PestoException("qualification.update-ui.result", "La réponse réelle du service est absente.");
                parent.Shown += async (_, _) =>
                {
                    try
                    {
                        stage = "parent";
                        var ready = await WaitUi(state => Idle(state) && Text(state, "prefix") == "111301");
                        Check(!parent.StartFailed, "parentReady");
                        Check(Text(ready, "mode") == "configuration" && Text(ready, "route") == "#/parametres", "isolatedConfigurationPage");

                        stage = "inspect-zip-ui";
                        await NativeConfigurationQualification.Dialog(parent, ZipTitle, selectedZip, () => Act(UpdateUiQualificationStep.UpdateZip), stop.Token);
                        await WaitUi(state => Idle(state) && Number(state, "candidateCount") == 1 && Returned("updates.inspect"), 180);
                        var selections = host.Snapshot().OfType<JsonObject>().Where(item => Text(item, "action") == "source").ToArray();
                        Check(selections.Length == 1 && Flag(selections[0], "selectionObservedBeforeIo")
                            && UpdateUiQualificationRequest.SamePath(Text(selections[0], "normalizedSelectedPath"), selectedZip)
                            && UpdatePackage.Hash(selectedZip) == fixture.CandidateZipSha256, "nativeZipSelectionExact");
                        Check(observed.Count("updates.inspect") == 1 && Text(observed.Last("updates.inspect"), "kind") == "zip"
                            && Text(Result("updates.inspect"), "fingerprint") == fixture.TargetFingerprint, "candidateInspectedFromButton");
                        Check(observed.Count("updates.prepare") == 0 && observed.Count("updates.install") == 0
                            && native.PendingUpdate is null && UpdateTransaction.List(fixture.Installation).Count == 0, "noTransactionBeforePreparation");
                        var candidateId = Text(Result("updates.inspect"), "candidateId");

                        stage = "prepare-ui";
                        await Act(UpdateUiQualificationStep.PrepareUpdate);
                        var preparedUi = await WaitUi(state => Idle(state) && Number(state, "preparedCount") == 1 && Returned("updates.prepare"), 180);
                        var preparedId = Text(Result("updates.prepare"), "preparedId");
                        Check(observed.Count("updates.prepare") == 1 && Text(observed.Last("updates.prepare"), "candidateId") == candidateId
                            && Text(Result("updates.prepare"), "fingerprint") == fixture.TargetFingerprint
                            && Text(preparedUi, "preparedText").Contains(fixture.Channel, StringComparison.Ordinal)
                            && Text(preparedUi, "preparedText").Contains("Source locale — origine à vérifier", StringComparison.Ordinal), "preparedFromButton");
                        var preparedDirectory = Path.Combine(data, "updates", "prepared", preparedId, "package");
                        scope.RequireOwned(preparedDirectory);
                        var target = UpdatePackage.Validate(preparedDirectory, fixture.Channel);
                        var targetManifest = ReadObject(Path.Combine(preparedDirectory, "wad", "Pesto.package.json"));
                        Check(target.Fingerprint == fixture.TargetFingerprint && target.Version == Text(Result("updates.prepare"), "version")
                            && Text(preparedUi, "preparedText").Contains(target.Version, StringComparison.Ordinal)
                            && UpdatePackage.Hash(Path.Combine(preparedDirectory, "Pesto.exe")) == fixture.TargetExecutableSha256
                            && Text(targetManifest, "sourceCommit") == fixture.TargetSourceCommit, "preparedCopyExact");
                        proof["sourceVersion"] = installed.Version; proof["targetVersion"] = target.Version;
                        proof["candidateId"] = candidateId; proof["preparedId"] = preparedId;
                        proof["preparedObservation"] = new JsonObject { ["text"] = Text(preparedUi, "preparedText"),
                            ["version"] = target.Version, ["channel"] = fixture.Channel, ["source"] = "local" };
                        await Capture("maintenance-prepared.png");

                        stage = "cancel-confirmation-ui";
                        await Act(UpdateUiQualificationStep.InstallUpdate);
                        var confirmation = await WaitUi(state => Text(state["dialog"], "title") == InstallTitle);
                        Check(observed.Count("updates.install") == 0 && native.PendingUpdate is null
                            && Text(confirmation["dialog"], "body").Contains("configuration reste", StringComparison.Ordinal)
                            && Text(confirmation["dialog"], "body").Contains(target.Version, StringComparison.Ordinal)
                            && Text(confirmation["dialog"], "body").Contains(fixture.Channel, StringComparison.Ordinal)
                            && Text(confirmation["dialog"], "body").Contains("Source locale — origine à vérifier", StringComparison.Ordinal)
                            && UpdateTransaction.List(fixture.Installation).Count == 0, "installWaitsForConfirmation");
                        await Act(UpdateUiQualificationStep.CancelInstall);
                        await WaitUi(state => Idle(state) && Number(state, "preparedCount") == 1);
                        Check(observed.Count("updates.install") == 0 && native.PendingUpdate is null
                            && UpdateTransaction.List(fixture.Installation).Count == 0
                            && UpdatePackage.Validate(fixture.Installation).Fingerprint == fixture.SourceFingerprint,
                            "installCancellationPreservedPreparation");

                        stage = "confirm-install-ui";
                        await Act(UpdateUiQualificationStep.InstallUpdate);
                        var finalConfirmation = await WaitUi(state => Text(state["dialog"], "title") == InstallTitle);
                        proof["confirmationObservation"] = finalConfirmation["dialog"]?.DeepClone();
                        await Capture("maintenance-install-confirmation.png");
                        await Act(UpdateUiQualificationStep.ConfirmInstall);
                        Check(steps.OfType<JsonObject>().Count(item => Text(item, "step") == nameof(UpdateUiQualificationStep.ConfirmInstall)) == 1
                            && Text(finalConfirmation["dialog"], "body").Contains(target.Version, StringComparison.Ordinal)
                            && Text(finalConfirmation["dialog"], "body").Contains(fixture.Channel, StringComparison.Ordinal)
                            && Text(finalConfirmation["dialog"], "body").Contains("Source locale — origine à vérifier", StringComparison.Ordinal),
                            "installReconfirmedFromUi");
                        // After confirmation the real UI deliberately removes its replay button. Observe
                        // the backend/host result, never wait for or recreate a DOM install control.
                        var pendingWatch = Stopwatch.StartNew();
                        while (!Returned("updates.install") || native.PendingUpdate is null)
                        {
                            stop.Token.ThrowIfCancellationRequested(); CheckBackendFailures();
                            if (pendingWatch.Elapsed > TimeSpan.FromSeconds(180))
                                throw new PestoException("qualification.update-ui.pending", "Le relais réel de la fenêtre n’a pas été observé.");
                            await Task.Delay(20, stop.Token);
                        }
                        var pending = native.PendingUpdate;
                        Check(observed.Count("updates.install") == 1 && Flag(observed.Last("updates.install"), "confirmed")
                            && Text(observed.Last("updates.install"), "preparedId") == preparedId
                            && Text(Result("updates.install"), "status") == "closing", "singleInstallBridgeRequest");
                        Check(host.Count("install") == 1 && host.InstallRequest == pending, "singleNativeHostRequest");
                        Check(Text(Result("updates.install"), "transactionId") == pending.TransactionId
                            && UpdateTransaction.List(fixture.Installation).Single().Id == pending.TransactionId
                            && UpdateUiQualificationRequest.SamePath(UpdateTransaction.ReadInstallationDirectory(pending.TransactionDirectory), fixture.Installation),
                            "transactionBoundToUiRequest");
                        proof["transactionId"] = pending.TransactionId;
                        proof["uiInstallConfirmationQualified"] = true;
                        handoffReady = true; stage = "waiting-for-native-close";
                        // NativeHostActions owns the 500 ms close-after-response timer. Do not replace
                        // it with a bench Close(): that would hide a broken production closing path.
                    }
                    catch (Exception error)
                    {
                        proof["failureCode"] = FailureCode(error);
                        stop.Cancel(); NativeConfigurationQualification.CancelDialogs(parent.Handle);
                        if (!parent.IsDisposed) parent.Close();
                    }
                };
                watchdog.Start(); Application.Run(parent); watchdog.Stop();
            }

            stage = "post-window-handoff";
            Check(handoffReady && parentClosed && !parentFailed && Program.UiFailure is null && proof["failureCode"] is null, "parentClosedNormally");
            proof["parentClosed"] = true;
            var request = native.PendingUpdate ?? throw new PestoException("qualification.update-ui.pending", "Le relais confirmé est absent.");
            fixture.RequireOwned(request.TransactionDirectory); fixture.RequireOwned(request.HelperExecutable);
            Check(UpdatePackage.Validate(fixture.Installation).Fingerprint == fixture.SourceFingerprint,
                "installationUnchangedBeforeHandoff");
            proof["installationUnchangedBeforeHandoff"] = true;
            Check(UpdatePackage.Hash(configuration.ConfigurationPath) == configurationHash, "profileDataPreserved");
            proof["profileDataPreserved"] = true;
            Check(UpdatePackage.Hash(fixture.CandidateZip) == fixture.CandidateZipSha256
                && UpdatePackage.Hash(selectedZip) == fixture.CandidateZipSha256, "sourceZipUnchanged");
            proof["sourceZipUnchanged"] = true;
            Check(observed.ForbiddenInvocations == 0 && host.ForbiddenInvocations == 0
                && observed.Snapshot().OfType<JsonObject>().All(call => Flag(call, "completed") && Text(call, "failureCode").Length == 0)
                && host.Snapshot().OfType<JsonObject>().All(call => Flag(call, "completed") && Text(call, "failureCode").Length == 0),
                "noForbiddenEffects");
            WriteNew(Path.Combine(fixture.ReportDirectory, "request-install.json"), request);
            using var helper = UpdateHostHandoff.Start(request);
            var launch = new
            {
                processId = helper.Id,
                startUtcTicks = helper.StartTime.ToUniversalTime().Ticks.ToString(CultureInfo.InvariantCulture),
                executable = request.HelperExecutable, transactionId = request.TransactionId
            };
            WriteNew(Path.Combine(fixture.ReportDirectory, "launch-install.json"), launch);
            Check(parentClosed && helper.Id != currentProcess.Id, "helperLaunchedAfterParentClose");
            proof["helperLaunched"] = true; proof["helperProcessId"] = helper.Id;
            proof["success"] = true; stage = "handed-off-awaiting-external-observation";
        }
        catch (Exception error) { proof["failureCode"] = FailureCode(error); proof["success"] = false; }
        finally
        {
            proof["stage"] = stage; proof["parentClosed"] = parentClosed;
            proof["backendCalls"] = observed?.Snapshot(); proof["hostCalls"] = host?.Snapshot();
            proof["dialogObservations"] = NativeConfigurationQualification.DialogObservations();
            proof["forbiddenBackendInvocations"] = observed?.ForbiddenInvocations ?? 0;
            proof["forbiddenHostInvocations"] = host?.ForbiddenInvocations ?? 0;
            // Preserve isolated data until the companion verifies the configuration again AFTER the
            // real transaction and rollback. It alone removes coexistence/data; screenshots stay.
            proof["temporaryDataRemoved"] = false;
            if (!Flag(proof, "success"))
            {
                proof["lastUi"] = lastUi; proof["lastDialogControls"] = NativeConfigurationQualification.LastDialogControls();
            }
            if (Program.UiFailure is { } failure)
            {
                proof["success"] = false; proof["failureCode"] = "qualification.update-ui.ui-exception";
                proof["uiException"] = new JsonObject { ["type"] = failure.GetType().FullName, ["hresult"] = failure.HResult };
            }
            WriteNew(Path.Combine(fixture.ReportDirectory, "proof.json"), proof);
        }
        return Flag(proof, "success") ? 0 : 3;
    }

    private static bool Idle(JsonObject value) => Flag(value, "ready") && Text(value, "mode") == "configuration"
        && Text(value, "route") == "#/parametres" && value["dialog"] is null && Flag(value, "buttonsReady")
        && Flag(value, "saveEnabled") && !Flag(value, "settingsBusy");
    private static bool Flag(JsonNode? value, string key) => value?[key]?.GetValue<bool>() == true;
    private static string Text(JsonNode? value, string key) => value?[key]?.GetValue<string>() ?? "";
    private static int Number(JsonNode? value, string key) => value?[key]?.GetValue<int>() ?? -1;
    private static string FailureCode(Exception error) => error is PestoException pesto ? pesto.Code : error.GetType().Name;
    private static JsonObject ReadObject(string path) => JsonNode.Parse(File.ReadAllText(path)) as JsonObject
        ?? throw new PestoException("qualification.update-ui.json", "Le document attendu n’est pas un objet JSON.");
    private static void WriteNew<T>(string path, T value)
    {
        OperatorProfile.RejectLinks(path);
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read);
        JsonSerializer.Serialize(stream, value, UpdateUiQualificationRequest.Json); stream.Flush(true);
    }
}

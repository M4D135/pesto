using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>Real MainForm buttons and native file pickers, in a new temporary tree with no AD adapter.</summary>
internal static class NativeConfigurationQualification
{
    private const string ImportTitle = "Importer une configuration Pesto";
    private const string ExportTitle = "Exporter les paramètres partageables";
    private const string FolderTitle = "Choisir le dossier parent : Pesto y créera un nouveau pack personnalisé complet, prêt à diffuser.";
    private const string SourceFolderTitle = "Choisir le dossier du pack Pesto V2, local ou sur un partage UNC";
    private static JsonArray? lastDialogControls;
    private static JsonArray dialogObservations = [];

    // Both compiled benches run as separate entry points/processes. Share the already qualified
    // Windows picker driver without allowing the CLI or page to supply code or native controls.
    internal static void ResetDialogObservations() { lastDialogControls = null; dialogObservations = []; }
    internal static JsonArray DialogObservations() => (JsonArray)dialogObservations.DeepClone();
    internal static JsonArray? LastDialogControls() => lastDialogControls?.DeepClone() as JsonArray;

    public static int Run(string reportDirectory)
    {
        var output = Path.TrimEndingDirectorySeparator(Path.GetFullPath(reportDirectory));
        var temporary = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar;
        if (!output.StartsWith(temporary, StringComparison.OrdinalIgnoreCase) || output.Length <= temporary.Length)
            throw new PestoException("qualification.path", "Un nouveau sous-dossier temporaire dédié est requis.");
        OperatorProfile.RejectLinks(output);
        if (Directory.Exists(output) || File.Exists(output)) throw new PestoException("qualification.path", "Le dossier de preuve existe déjà.");
        Directory.CreateDirectory(output);
        var scope = new DemoQualificationScope(output);
        var data = Path.Combine(scope.Root, "data");
        Directory.CreateDirectory(data);
        var proof = new JsonObject
        {
            ["schemaVersion"] = 2, ["kind"] = "pesto.native-configuration-qualification",
            ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["success"] = false, ["adQualification"] = false,
            ["adExecuted"] = false, ["realUac"] = false, ["ordinaryProfileAccess"] = false,
            ["uiScope"] = "mainform-webview2-buttons-and-native-dialogs", ["uiDriver"] = "compiled-dom-input-and-click",
            ["fixtureSetup"] = "synthetic-configuration-before-mainform-start", ["timeoutSeconds"] = 480,
            ["nativeUpdateInstallFromUiQualified"] = false, ["uncQualification"] = false
        };
        var checks = new JsonArray(); proof["checks"] = checks;
        var uiSteps = new JsonArray(); proof["uiSteps"] = uiSteps;
        var captures = new JsonArray(); proof["captures"] = captures;
        lastDialogControls = null;
        dialogObservations = [];
        proof["dialogObservations"] = dialogObservations;
        ConfigurationQualificationBackend? observed = null;
        ConfigurationQualificationHost? host = null;
        JsonObject? lastUi = null;
        string? sourceFingerprint = null;
        var stage = "package";
        var completed = false;
        try
        {
            var package = UpdatePackage.Validate(AppPaths.AppDirectory);
            AppPaths.RequirePortableFiles(); HostPolicy.ClearBrowserOverrides();
            sourceFingerprint = package.Fingerprint;
            proof["channel"] = package.Channel;
            proof["runtimeMode"] = package.WebView2Runtime; proof["runtimeSource"] = AppPaths.RuntimeSource;
            proof["sourceFingerprint"] = package.Fingerprint;
            proof["executableSha256"] = UpdatePackage.Hash(Path.Combine(AppPaths.AppDirectory, "Pesto.exe"));
            using var identity = WindowsIdentity.GetCurrent();
            var profile = new OperatorProfile(identity.User!.Value, Path.Combine(data, "LocalData"));
            var parentData = AppPaths.UserData(package.Channel, false, false, profile.LocalData);
            var config = new ProfileConfigurationService(parentData, profile.Sid, ConfigurationAccessMode.Live);
            config.Initialize();
            // Fixture setup only. All subsequent configuration changes must come through visible UI actions.
            var seed = config.PreviewSettings(PestoJson.Element(new
            {
                domain = "example.local", dc = "", prefix = "111301", rootOu = "OU=Postes,DC=example,DC=local",
                preprodOu = "", preprodSite = "", production = true, randomNames = false, namingPattern = PestoSettings.DefaultPattern,
                sites = new[] { new { id = "paris", name = "Paris", code = "PA", ou = "OU=Paris,OU=Postes,DC=example,DC=local" } }
            }));
            _ = config.ApplyImport(Text(seed, "planId"), true);
            var originalStamp = UpdatePackage.Hash(config.ConfigurationPath);
            var expectedConfiguration = Text(config.Export(ConfigurationQualificationScripts.Version), "fingerprint");
            var exportPath = Path.Combine(data, "export.json");
            var folderParent = Path.Combine(data, "selected destination");
            Directory.CreateDirectory(folderParent);
            var updateState = Path.Combine(data, "updates");
            var native = new NativeHostActions(profile, package.Channel, false);
            host = new(native, scope);
            native.EnableQualificationFileGuard(scope, host.ObserveSelectionBeforeIo);
            var updates = new UpdateService(new(AppPaths.AppDirectory, updateState, package.Channel, false));
            var backend = new ApplicationServicesBackend(PestoBackend.CreateConfigurationOnly(parentData, gpRoot: Path.Combine(data, "GP")),
                false, config, updates, host, AppPaths.AppDirectory);
            observed = new(backend);
            using var parent = new MainForm(observed, false, false, package.Channel, parentData, initialPage: "parametres", configurationOnly: true);
            parent.EnableQualification(scope);
            native.Owner = parent;
            using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(480));
            using var watchdog = new System.Windows.Forms.Timer { Interval = 1000 };
            watchdog.Tick += (_, _) => { if (stop.IsCancellationRequested) { CancelDialogs(parent.Handle); parent.Close(); } };
            parent.FormClosing += (_, args) =>
            {
                if (!completed && proof["failureCode"] is null)
                {
                    stop.Cancel(); CancelDialogs(parent.Handle);
                    args.Cancel = true; // Let the active operation finish before deleting its temporary tree.
                }
            };
            void Check(bool value, string name)
            {
                if (!value) throw new PestoException("qualification.configuration." + name, "Contrôle natif non satisfait : " + name);
                checks.Add(name);
            }
            var expectedBackendFailures = new HashSet<int>();
            var encodingImportNumber = -1;
            async Task Act(ConfigurationQualificationStep step)
            {
                var result = await parent.QualificationStepAsync(step).WaitAsync(stop.Token);
                if (result != "true") throw new PestoException("qualification.configuration.ui-action", "Le bouton ou champ attendu n’est pas disponible.");
                uiSteps.Add(new JsonObject { ["step"] = step.ToString(), ["source"] = "dom", ["accepted"] = true });
            }
            async Task<JsonObject> WaitUi(Func<JsonObject, bool> predicate, int seconds = 90)
            {
                var watch = Stopwatch.StartNew();
                do
                {
                    stop.Token.ThrowIfCancellationRequested();
                    if (parent.StartFailed) throw new PestoException("qualification.configuration.webview", "L’interface native n’est pas prête.");
                    foreach (var call in observed.Snapshot().OfType<JsonObject>())
                    {
                        var code = Text(call, "failureCode");
                        var sequence = Number(call, "sequence");
                        if (code.Length == 0 || expectedBackendFailures.Contains(sequence)) continue;
                        if (stage == "invalid-encoding-ui" && Text(call, "operation") == "configuration.previewImport" && code == "config.encoding"
                            && observed.Count("configuration.previewImport") == encodingImportNumber
                            && Number(observed.Last("configuration.previewImport"), "sequence") == sequence)
                        { expectedBackendFailures.Add(sequence); continue; }
                        proof["backendFailure"] = call.DeepClone();
                        throw new PestoException(code, "Le vrai moteur a refusé l’action UI du banc ; aucun succès n’est attendu après ce refus.");
                    }
                    var raw = await parent.QualificationStepAsync(ConfigurationQualificationStep.Snapshot).WaitAsync(stop.Token);
                    if (raw.Length > 256 * 1024) throw new PestoException("qualification.configuration.snapshot", "Observation trop volumineuse.");
                    if (JsonNode.Parse(raw) is JsonObject state)
                    {
                        lastUi = state;
                        if (predicate(state)) return state;
                    }
                    await Task.Delay(100, stop.Token);
                } while (watch.Elapsed < TimeSpan.FromSeconds(seconds));
                throw new PestoException("qualification.configuration.ui-timeout", "L’état attendu de l’interface n’a pas été prouvé.");
            }
            Task<JsonObject> WaitDialog(string title) => WaitUi(state => Text(state["dialog"], "title") == title);
            async Task Capture(string name)
            {
                await WaitUi(state => !Flag(state, "finiteAnimationsRunning"));
                await parent.QualificationCaptureAsync(name).WaitAsync(stop.Token);
                captures.Add("coexistence/" + name);
            }
            async Task Pick(string title, string? path, ConfigurationQualificationStep step)
            {
                await Dialog(parent, title, path, () => Act(step), stop.Token);
            }
            bool Returned(string operation, string status) => Flag(observed.Last(operation), "completed")
                && Text(observed.Last(operation)?["result"], "status") == status;
            JsonObject Result(string operation) => observed.Last(operation)?["result"] as JsonObject
                ?? throw new PestoException("qualification.configuration.result", "La réponse du vrai moteur manque.");
            void BackupMatches(string expected, string check)
            {
                var backup = Text(Result("configuration.applyImport"), "backup");
                scope.RequireOwned(backup);
                Check(File.Exists(backup) && UpdatePackage.Hash(backup) == expected, check);
            }
            parent.Shown += async (_, _) =>
            {
                try
                {
                    stage = "parent";
                    await WaitUi(state => Idle(state) && Text(state, "prefix") == "111301");
                    Check(!parent.StartFailed, "parentReady");
                    await Act(ConfigurationQualificationStep.SetVersion);
                    Check(Text(await WaitUi(state => Text(state, "version") == ConfigurationQualificationScripts.Version), "mode") == "configuration", "isolatedConfigurationPage");

                    stage = "export-ui";
                    await Pick(ExportTitle, exportPath, ConfigurationQualificationStep.Export);
                    var exportedUi = await WaitUi(state => Idle(state) && Returned("configuration.export", "exported"));
                    var exported = ConfigurationDocument.ValidateBundle(ConfigurationDocument.ReadFile(exportPath));
                    Check(observed.Count("configuration.export") == 1 && SamePath(Text(Result("configuration.export"), "file"), exportPath)
                        && Text(exportedUi, "configurationStatus").Contains(Text(Result("configuration.export"), "file"), StringComparison.Ordinal), "nativeExportFromButton");
                    Check(Text(exported, "version") == ConfigurationQualificationScripts.Version
                        && Text(exported, "fingerprint") == expectedConfiguration, "nativeExportExact");
                    var exportStamp = UpdatePackage.Hash(exportPath);
                    proof["exportObservation"] = new JsonObject { ["relativePath"] = Path.GetRelativePath(scope.Root, exportPath).Replace('\\', '/'),
                        ["sha256"] = exportStamp, ["configurationFingerprint"] = expectedConfiguration, ["version"] = ConfigurationQualificationScripts.Version };
                    Check(!Directory.EnumerateFiles(data, "export.json.*.tmp", SearchOption.TopDirectoryOnly).Any(), "noExportTemporaryFile");
                    proof["nativeExportFromUiQualified"] = true;
                    await Capture("configuration-export.png");

                    stage = "settings-ui";
                    await Act(ConfigurationQualificationStep.ChangePrefix);
                    await Act(ConfigurationQualificationStep.SaveSettings);
                    var saveDialog = await WaitDialog("Enregistrer les paramètres");
                    Check(observed.Count("configuration.applyImport") == 0 && UpdatePackage.Hash(config.ConfigurationPath) == originalStamp
                        && Text(saveDialog["dialog"], "body").Contains("111301", StringComparison.Ordinal)
                        && Text(saveDialog["dialog"], "body").Contains("222222", StringComparison.Ordinal), "settingsUnchangedBeforeConfirmation");
                    await Act(ConfigurationQualificationStep.ConfirmSettings);
                    await WaitUi(state => Idle(state) && Text(state, "prefix") == "222222"
                        && observed.Count("configuration.applyImport") == 1 && Flag(observed.Last("configuration.applyImport"), "completed"));
                    var changedStamp = UpdatePackage.Hash(config.ConfigurationPath);
                    Check(changedStamp != originalStamp && Text(config.ReadSettings(), "prefix") == "222222"
                        && Flag(observed.Last("configuration.applyImport"), "confirmed"), "settingsSavedFromButton");
                    BackupMatches(originalStamp, "settingsBackupExact");

                    stage = "native-cancellations-ui";
                    await Pick(ImportTitle, null, ConfigurationQualificationStep.Import);
                    await WaitUi(state => Idle(state) && Returned("configuration.previewImport", "cancelled"));
                    Check(observed.Count("configuration.applyImport") == 1 && UpdatePackage.Hash(config.ConfigurationPath) == changedStamp, "importCancelled");
                    await Pick(ExportTitle, null, ConfigurationQualificationStep.Export);
                    await WaitUi(state => Idle(state) && Returned("configuration.export", "cancelled"));
                    Check(UpdatePackage.Hash(exportPath) == exportStamp, "exportCancelled");

                    stage = "invalid-encoding-ui";
                    var malformed = Path.Combine(data, "malformed.json");
                    File.WriteAllBytes(malformed, [0x7b, 0x22, 0xc3, 0x28, 0x22, 0x7d]);
                    encodingImportNumber = observed.Count("configuration.previewImport") + 1;
                    await Pick(ImportTitle, malformed, ConfigurationQualificationStep.Import);
                    await WaitUi(state => Idle(state) && Text(observed.Last("configuration.previewImport"), "failureCode") == "config.encoding"
                        && Text(state, "notifications").Contains("encodage invalide", StringComparison.Ordinal));
                    // The response can arrive during the awaited DOM snapshot, after WaitUi's failure
                    // scan. Admit this exact expected refusal before changing stage, even in that race.
                    var encodingFailure = observed.Last("configuration.previewImport");
                    Check(Flag(encodingFailure, "completed") && Text(encodingFailure, "failureCode") == "config.encoding"
                        && observed.Count("configuration.previewImport") == encodingImportNumber
                        && UpdatePackage.Hash(config.ConfigurationPath) == changedStamp && observed.Count("configuration.applyImport") == 1, "invalidEncodingRejected");
                    expectedBackendFailures.Add(Number(encodingFailure, "sequence"));

                    stage = "import-cancel-preview-ui";
                    await Pick(ImportTitle, exportPath, ConfigurationQualificationStep.Import);
                    var importDialog = await WaitDialog("Importer la configuration");
                    Check(Text(Result("configuration.previewImport"), "fingerprint") == expectedConfiguration
                        && Text(importDialog["dialog"], "body").Contains("111301", StringComparison.Ordinal)
                        && Text(importDialog["dialog"], "body").Contains("222222", StringComparison.Ordinal)
                        && UpdatePackage.Hash(config.ConfigurationPath) == changedStamp && observed.Count("configuration.applyImport") == 1,
                        "importPreviewBeforeWrite");
                    await Capture("configuration-import-preview.png");
                    await Act(ConfigurationQualificationStep.CancelImport);
                    await WaitUi(Idle);
                    Check(UpdatePackage.Hash(config.ConfigurationPath) == changedStamp && observed.Count("configuration.applyImport") == 1, "importConfirmationCancelled");

                    stage = "import-confirm-ui";
                    await Pick(ImportTitle, exportPath, ConfigurationQualificationStep.Import);
                    await WaitDialog("Importer la configuration");
                    var importPlan = Text(Result("configuration.previewImport"), "planId");
                    await Act(ConfigurationQualificationStep.ConfirmImport);
                    await WaitUi(state => Idle(state) && Text(state, "prefix") == "111301"
                        && observed.Count("configuration.applyImport") == 2 && Flag(observed.Last("configuration.applyImport"), "completed"));
                    Check(Text(observed.Last("configuration.applyImport"), "planId") == importPlan
                        && Flag(observed.Last("configuration.applyImport"), "confirmed"), "nativeImportFromButton");
                    Check(UpdatePackage.Hash(config.ConfigurationPath) == originalStamp && UpdatePackage.Hash(exportPath) == exportStamp
                        && Text(config.Export(ConfigurationQualificationScripts.Version), "fingerprint") == expectedConfiguration, "importRoundTrip");
                    BackupMatches(changedStamp, "importBackupExact");
                    proof["nativeImportFromUiQualified"] = true;

                    stage = "default-confirmation-cancel-ui";
                    await Act(ConfigurationQualificationStep.Default);
                    await WaitDialog("Préparer un pack avec vos paramètres");
                    Check(observed.Count("configuration.setDefault") == 0 && host.Count("destination") == 0
                        && !Directory.EnumerateFileSystemEntries(folderParent).Any(), "customPackWaitsForConfirmation");
                    await Capture("configuration-default-confirmation.png");
                    await Act(ConfigurationQualificationStep.CancelDefault);
                    await WaitUi(Idle);
                    Check(observed.Count("configuration.setDefault") == 0 && host.Count("destination") == 0, "customPackConfirmationCancelled");

                    stage = "default-folder-cancel-ui";
                    await Act(ConfigurationQualificationStep.Default);
                    await WaitDialog("Préparer un pack avec vos paramètres");
                    await Pick(FolderTitle, null, ConfigurationQualificationStep.ConfirmDefault);
                    await WaitUi(state => Idle(state) && Returned("configuration.setDefault", "cancelled"));
                    Check(host.Count("destination") == 1 && !Directory.EnumerateFileSystemEntries(folderParent).Any()
                        && UpdatePackage.Hash(config.ConfigurationPath) == originalStamp, "packDestinationCancelled");

                    stage = "default-positive-folder-ui";
                    await Act(ConfigurationQualificationStep.Default);
                    await WaitDialog("Préparer un pack avec vos paramètres");
                    await Pick(FolderTitle, folderParent, ConfigurationQualificationStep.ConfirmDefault);
                    var preparedUi = await WaitUi(state => Idle(state) && Returned("configuration.setDefault", "prepared"), 180);
                    var destination = Text(Result("configuration.setDefault"), "destination");
                    scope.RequireOwned(destination);
                    Check(SamePath(Path.GetDirectoryName(destination), folderParent) && SamePath(Directory.EnumerateDirectories(folderParent).Single(), destination)
                        && host.Count("destination") == 2 && observed.Count("configuration.setDefault") == 2
                        && Flag(observed.Last("configuration.setDefault"), "confirmed"), "positiveNativeFolderSelection");
                    Check(Text(preparedUi, "configurationStatus") == "Pack prêt à diffuser : " + destination, "customPackResultVisible");
                    var custom = UpdatePackage.Validate(destination);
                    var customManifest = JsonNode.Parse(File.ReadAllText(Path.Combine(destination, "wad", "Pesto.package.json")))!;
                    Check(custom.Distribution == "custom" && customManifest["official"]?.GetValue<bool>() == false
                        && Text(customManifest, "configurationVersion") == ConfigurationQualificationScripts.Version
                        && Text(customManifest, "configurationFingerprint") == expectedConfiguration, "customPackValidated");
                    Check(UpdatePackage.Hash(Path.Combine(destination, "Pesto.exe")) == Text(proof, "executableSha256"), "customExecutableUnchanged");
                    var defaults = Path.Combine(destination, "wad", "defaults", "configuration.json");
                    Check(ConfigurationDocument.Canonical(ConfigurationDocument.ValidateBundle(ConfigurationDocument.ReadFile(defaults)))
                        == ConfigurationDocument.Canonical(exported), "customDefaultsMatchUiExport");
                    Check(!Directory.EnumerateDirectories(folderParent, ".pesto-personnalisation-*", SearchOption.TopDirectoryOnly).Any(), "noCustomPackStagingLeft");
                    proof["customPack"] = new JsonObject { ["relativePath"] = Path.GetRelativePath(scope.Root, destination).Replace('\\', '/'),
                        ["fingerprint"] = custom.Fingerprint, ["configurationFingerprint"] = expectedConfiguration,
                        ["executableSha256"] = Text(proof, "executableSha256"), ["fileCount"] = custom.FileCount };
                    proof["positiveFolderSelectionQualified"] = true;
                    proof["customPackButtonFlowQualified"] = true;
                    await Capture("configuration-custom-pack.png");

                    stage = "distribution-service-checks";
                    // Separate read/import checks of the produced bundle, not a claim of another UI journey.
                    var fresh = new ProfileConfigurationService(Path.Combine(data, "fresh"), profile.Sid, ConfigurationAccessMode.Live);
                    var first = fresh.Initialize(defaults);
                    Check(Text(first, "status") == "imported" && Text(fresh.ReadSettings(), "prefix") == "111301", "freshProfileImportsDefaults");
                    var freshStamp = UpdatePackage.Hash(fresh.ConfigurationPath);
                    _ = fresh.Initialize(defaults);
                    Check(UpdatePackage.Hash(fresh.ConfigurationPath) == freshStamp, "existingProfilePreserved");

                    stage = "maintenance-inspect-ui";
                    await Pick(SourceFolderTitle, destination, ConfigurationQualificationStep.UpdateFolder);
                    var candidateUi = await WaitUi(state => Idle(state) && Number(state, "candidateCount") == 1
                        && Flag(observed.Last("updates.inspect"), "completed"), 180);
                    Check(observed.Count("updates.inspect") == 1 && observed.Count("updates.prepare") == 0
                        && Text(Result("updates.inspect"), "fingerprint") == custom.Fingerprint
                        && Text(candidateUi, "candidatesText").Contains("Pack personnalisé", StringComparison.Ordinal), "maintenanceFolderInspectedFromButton");
                    var candidateId = Text(Result("updates.inspect"), "candidateId");
                    await Act(ConfigurationQualificationStep.PrepareUpdate);
                    await WaitUi(state => Idle(state) && Number(state, "preparedCount") == 1
                        && Flag(observed.Last("updates.prepare"), "completed"), 180);
                    Check(observed.Count("updates.prepare") == 1 && Text(observed.Last("updates.prepare"), "candidateId") == candidateId
                        && Text(Result("updates.prepare"), "fingerprint") == custom.Fingerprint, "maintenancePreparedFromButton");
                    var preparedId = Text(Result("updates.prepare"), "preparedId");
                    var preparedDirectory = Path.Combine(updateState, "prepared", preparedId, "package");
                    scope.RequireOwned(preparedDirectory);
                    Check(UpdatePackage.Validate(preparedDirectory).Fingerprint == custom.Fingerprint
                        && UpdatePackage.Validate(destination).Fingerprint == custom.Fingerprint, "maintenancePreparedCopyExact");
                    await Capture("maintenance-prepared.png");
                    await Act(ConfigurationQualificationStep.InstallUpdate);
                    var installDialog = await WaitDialog("Installer la mise à jour préparée");
                    Check(observed.Count("updates.install") == 0 && Text(installDialog["dialog"], "body").Contains("configuration reste", StringComparison.Ordinal), "maintenanceInstallWaitsForConfirmation");
                    await Capture("maintenance-install-confirmation.png");
                    await Act(ConfigurationQualificationStep.CancelInstall);
                    await WaitUi(Idle);
                    Check(observed.Count("updates.install") == 0 && native.PendingUpdate is null
                        && UpdateTransaction.List(AppPaths.AppDirectory).Count == 0, "maintenanceInstallConfirmationCancelled");
                    await Act(ConfigurationQualificationStep.UpdateStatus);
                    await WaitUi(state => Idle(state) && Flag(observed.Last("updates.status"), "completed"), 180);
                    Check(Text(Result("updates.status"), "status") == "idle" && !Flag(Result("updates.status"), "pendingRecovery"), "maintenanceStatusFromButton");
                    proof["maintenanceInspectionPreparationFromUiQualified"] = true;
                    proof["maintenanceInstallConfirmationCancelled"] = true;
                    proof["maintenanceScope"] = "local-folder-inspection-preparation-and-install-confirmation-cancellation";
                    proof["maintenancePreparedFingerprint"] = custom.Fingerprint;

                    stage = "integrity";
                    Check(observed.ForbiddenInvocations == 0 && host.ForbiddenInvocations == 0, "noForbiddenEffects");
                    Check(UpdatePackage.Hash(config.ConfigurationPath) == originalStamp && UpdatePackage.Hash(exportPath) == exportStamp, "operatorDataPreserved");
                    Check(UpdatePackage.Validate(AppPaths.AppDirectory).Fingerprint == package.Fingerprint, "sourcePackUnchanged");
                    completed = true;
                }
                catch (Exception error) { proof["failureCode"] = error is PestoException pesto ? pesto.Code : error.GetType().Name; }
                finally { CancelDialogs(parent.Handle); parent.Close(); }
            };
            watchdog.Start();
            Application.Run(parent);
            proof["parentClosed"] = true;
        }
        catch (Exception error) { proof["failureCode"] = error is PestoException pesto ? pesto.Code : error.GetType().Name; }
        finally
        {
            for (var attempt = 0; attempt < 60 && Directory.Exists(data); attempt++)
            {
                try { Directory.Delete(data, true); }
                catch (IOException) { Thread.Sleep(100); }
                catch (UnauthorizedAccessException) { Thread.Sleep(100); }
            }
            proof["temporaryDataRemoved"] = !Directory.Exists(data);
            proof["stage"] = stage;
            proof["backendCalls"] = observed?.Snapshot();
            proof["hostCalls"] = host?.Snapshot();
            proof["forbiddenBackendInvocations"] = observed?.ForbiddenInvocations ?? 0;
            proof["forbiddenHostInvocations"] = host?.ForbiddenInvocations ?? 0;
            try { proof["sourcePackUnchanged"] = sourceFingerprint is not null && UpdatePackage.Validate(AppPaths.AppDirectory).Fingerprint == sourceFingerprint; }
            catch (Exception) { proof["sourcePackUnchanged"] = false; }
            if (Program.UiFailure is { } uiFailure)
            {
                completed = false;
                proof["failureCode"] = "qualification.configuration.ui-exception";
                proof["uiException"] = new JsonObject
                {
                    ["type"] = uiFailure.GetType().FullName, ["hresult"] = uiFailure.HResult,
                    ["methods"] = new JsonArray(new StackTrace(uiFailure, false).GetFrames()
                        .Select(frame => frame.GetMethod()).Where(method => method is not null)
                        .Select(method => (method!.DeclaringType?.FullName ?? "") + "." + method.Name)
                        .Distinct().Take(12).Select(method => (JsonNode)JsonValue.Create(method)!).ToArray())
                };
            }
            if (!completed) { proof["lastDialogControls"] = lastDialogControls; proof["lastUi"] = lastUi; }
            proof["success"] = completed && !Directory.Exists(data) && Flag(proof, "sourcePackUnchanged")
                && (observed?.ForbiddenInvocations ?? 0) == 0 && (host?.ForbiddenInvocations ?? 0) == 0;
            if (!completed && proof["failureCode"] is null) proof["failureCode"] = "qualification.configuration.timeout";
            File.WriteAllText(Path.Combine(output, "proof.json"), proof.ToJsonString(new() { WriteIndented = true }));
        }
        return Flag(proof, "success") ? 0 : 3;
    }

    private static bool Idle(JsonObject value) => Flag(value, "ready") && Text(value, "mode") == "configuration"
        && Text(value, "route") == "#/parametres" && value["dialog"] is null && Flag(value, "buttonsReady")
        && Flag(value, "saveEnabled") && !Flag(value, "settingsBusy");
    private static bool Flag(JsonNode? value, string key) => value?[key]?.GetValue<bool>() == true;
    private static string Text(JsonNode? value, string key) => value?[key]?.GetValue<string>() ?? "";
    private static int Number(JsonNode? value, string key) => value?[key]?.GetValue<int>() ?? -1;
    private static bool SamePath(string? left, string right) => !string.IsNullOrWhiteSpace(left)
        && Path.TrimEndingDirectorySeparator(Path.GetFullPath(left)).Equals(Path.TrimEndingDirectorySeparator(Path.GetFullPath(right)), StringComparison.OrdinalIgnoreCase);

    internal static async Task Dialog(MainForm parent, string title, string? path, Func<Task> action, CancellationToken token)
    {
        var owner = parent.Handle;
        var isFolder = title is FolderTitle or SourceFolderTitle;
        using var driveStop = CancellationTokenSource.CreateLinkedTokenSource(token);
        token = driveStop.Token;
        var drive = Task.Run(async () =>
        {
            var watch = Stopwatch.StartNew();
            nint previousEdit = 0;
            var stableReads = 0;
            var observation = new JsonObject { ["title"] = title, ["pathRequired"] = path is not null,
                ["requestedPath"] = path, ["kind"] = isFolder ? "folder" : "file",
                ["writeAttempts"] = 0, ["stableReads"] = 0, ["clicked"] = false, ["closedAfterClick"] = false };
            dialogObservations.Add(observation);
            while (watch.Elapsed < TimeSpan.FromSeconds(20))
            {
                token.ThrowIfCancellationRequested();
                var dialog = OwnedDialogs(owner).SingleOrDefault(window => WindowText(window) == title);
                if (dialog != nint.Zero && IsWindowVisible(dialog) && IsWindowEnabled(dialog))
                {
                    var children = Children(dialog);
                    lastDialogControls = new JsonArray(children.Select(window => (JsonNode)new JsonObject
                        { ["class"] = ClassName(window), ["id"] = GetDlgCtrlID(window) }).ToArray());
                    var button = children.SingleOrDefault(window => ClassName(window) == "Button" && GetDlgCtrlID(window) == (path is null ? 2 : 1));
                    if (button == nint.Zero || !IsWindowVisible(button) || path is null && !IsWindowEnabled(button))
                    { stableReads = 0; await Task.Delay(100, token); continue; }
                    if (path is not null)
                    {
                        // The observed folder picker uses 1152; save and open pickers use 1001/1148.
                        // Keep these controls specific to the dialog kind instead of guessing an edit.
                        // Do not match the address bar (41477), search box or a label by its displayed text.
                        var edits = children.Where(window => ClassName(window) == "Edit"
                            && (isFolder ? GetDlgCtrlID(window) == 1152 : GetDlgCtrlID(window) is 1001 or 1148)
                            && IsWindowVisible(window) && IsWindowEnabled(window)).ToArray();
                        if (edits.Length != 1)
                        { stableReads = 0; await Task.Delay(100, token); continue; }
                        var edit = edits[0];
                        if (edit != previousEdit) { previousEdit = edit; stableReads = 0; }
                        var observed = WindowText(edit);
                        observation["observedLength"] = observed.Length;
                        if (!string.Equals(observed, path, StringComparison.Ordinal))
                        {
                            // A newly created picker can still replace its filename during initialization.
                            // Retry only this scenario's exact path, then observe it on separate UI turns.
                            stableReads = 0;
                            observation["writeAttempts"] = observation["writeAttempts"]!.GetValue<int>() + 1;
                            await FocusControlAsync(dialog, edit, token);
                            // Drive the edit's character-input path, with focus and an actual selection.
                            // Merely changing its displayed WM_SETTEXT buffer does not prove which path
                            // the Shell picker will return. No suggested filename is injected into the host.
                            _ = SendMessage(edit, 0x00b1, 0, -1); // EM_SETSEL: select the current contents.
                            foreach (var character in path) _ = SendMessage(edit, 0x0102, character, 0); // WM_CHAR.
                            observation["inputMethod"] = "focused-edit-character-input";
                            observation["typedCharacters"] = path.Length;
                            observation["writeAccepted"] = WindowText(edit) == path;
                        }
                        else stableReads++;
                        observation["stableReads"] = stableReads;
                        if (stableReads < 3) { await Task.Delay(150, token); continue; }
                        observation["pathReadBackExact"] = true;
                        observation["editControlId"] = GetDlgCtrlID(edit);
                    }
                    // A folder picker may enable Select only after its path field is populated.
                    if (!IsWindowEnabled(button)) { await Task.Delay(100, token); continue; }
                    await FocusControlAsync(dialog, button, token); // Commit the edit through its real focus-loss path.
                    await Task.Delay(150, token);
                    if (path is not null && WindowText(previousEdit) != path)
                    { stableReads = 0; continue; }
                    observation["buttonFocusConfirmed"] = true;
                    // Never accept a path that was merely written, but not read back stably.
                    if (!PostMessage(button, 0x00f5, 0, 0))
                        throw new PestoException("qualification.configuration.dialog-click", "Le dialogue natif n’a pas reçu la validation.");
                    observation["clicked"] = true;
                    observation["elapsedMs"] = watch.ElapsedMilliseconds;
                    // A posted BM_CLICK is not evidence of a selection. The actual picker must close;
                    // the caller then separately waits for the real bridge response and verifies the file.
                    for (var attempt = 0; attempt < 100; attempt++)
                    {
                        token.ThrowIfCancellationRequested();
                        if (!OwnedDialogs(owner).Contains(dialog))
                        { observation["closedAfterClick"] = true; return; }
                        await Task.Delay(100, token);
                    }
                    throw new PestoException("qualification.configuration.dialog-not-closed", "Le dialogue n’a pas confirmé la sélection demandée.");
                }
                else stableReads = 0;
                await Task.Delay(100, token);
            }
            throw new PestoException(path is not null && previousEdit != 0
                ? "qualification.configuration.dialog-path" : "qualification.configuration.dialog", "Le dialogue natif attendu n’est pas pilotable avec le chemin temporaire attendu.");
        }, token);
        try { await action().WaitAsync(TimeSpan.FromSeconds(30), token); await drive; }
        catch
        {
            driveStop.Cancel(); CancelDialogs(owner);
            try { await drive; } catch (Exception) { /* Preserve the initiating failure after the driver has stopped. */ }
            throw;
        }
    }

    private static nint[] OwnedDialogs(nint owner)
    {
        var windows = new List<nint>();
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out var pid);
            if (pid == Environment.ProcessId && GetAncestor(window, 3) == owner && ClassName(window) == "#32770") windows.Add(window);
            return true;
        }, 0);
        return windows.ToArray();
    }
    private static nint[] Children(nint window)
    {
        var children = new List<nint>();
        EnumChildWindows(window, (child, _) => { children.Add(child); return true; }, 0);
        return children.ToArray();
    }
    private static async Task FocusControlAsync(nint dialog, nint control, CancellationToken token)
    {
        // A freshly created Shell picker moves focus itself while it initializes (observed on a Windows runner:
        // official run 40717463230). Re-request this exact control on separate UI turns for a bounded time;
        // the path is still accepted only after its exact, stable read-back and the real dialog closure.
        // A loaded runner can keep the control hidden or disabled for a few seconds while the picker initializes
        // (run 40963727760): wait for it within the same bound instead of failing on the first look.
        for (var attempt = 0; ; attempt++)
        {
            var thread = GetWindowThreadProcessId(dialog, out var process);
            if (process != Environment.ProcessId)
                throw new PestoException("qualification.configuration.dialog-focus", "Le contrôle ne fait pas partie du dialogue actif du banc.");
            if (IsWindowVisible(control) && IsWindowEnabled(control))
            {
                _ = SendMessage(dialog, 0x0028, control, 1); // WM_NEXTDLGCTL: choose this exact control on the dialog thread.
                var info = new GuiThreadInfo { Size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
                if (GetGUIThreadInfo(thread, ref info) && info.Focus == control) return;
            }
            if (attempt == 100)
                throw new PestoException("qualification.configuration.dialog-focus", "Le contrôle natif n’a pas reçu le focus attendu.");
            await Task.Delay(100, token);
        }
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct GuiThreadInfo
    {
        public uint Size, Flags;
        public nint Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public int CaretLeft, CaretTop, CaretRight, CaretBottom;
    }
    internal static void CancelDialogs(nint owner) { foreach (var dialog in OwnedDialogs(owner)) _ = PostMessage(dialog, 0x0010, 0, 0); }
    private static string WindowText(nint window) { var text = new StringBuilder(1024); _ = GetWindowText(window, text, text.Capacity); return text.ToString(); }
    private static string ClassName(nint window) { var text = new StringBuilder(256); _ = GetClassName(window, text, text.Capacity); return text.ToString(); }
    private delegate bool EnumWindowProc(nint window, nint parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowProc callback, nint parameter);
    [DllImport("user32.dll")] private static extern bool EnumChildWindows(nint parent, EnumWindowProc callback, nint parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll")] private static extern nint GetAncestor(nint window, uint flags);
    [DllImport("user32.dll")] private static extern int GetDlgCtrlID(nint window);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(nint window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(nint window, StringBuilder text, int maximum);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(nint window, StringBuilder text, int maximum);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint SendMessage(nint window, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo information);
    [DllImport("user32.dll")] private static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
}

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>
/// Real MainForm buttons and native file pickers, in a new temporary tree with no AD adapter. The installation under test is
/// a verified copy of the running pack inside that tree: the bench never writes into <see cref="AppPaths.AppDirectory"/>,
/// which the CI verifies again afterwards.
/// </summary>
internal static class NativeConfigurationQualification
{
    private const string ImportTitle = "Importer une configuration Pesto";
    private const string ExportTitle = "Exporter les paramètres partageables";
    private const string SourceFolderTitle = "Choisir le dossier du pack Pesto V2, local ou sur un partage UNC";
    // Exact texts shared with web/js/pages/maintenance.js and the engine (2.0.14, configuration par défaut sur place).
    private const string DefaultConfirmLabel = "Enregistrer comme défaut";
    private const string ReadOnlyCode = "config.default_readonly";
    private const string ReadOnlyMessage = "Le dossier de cette installation n’est pas accessible en écriture : la configuration par défaut n’a pas été enregistrée. Lancez Pesto normalement depuis cette installation (autorisation administrateur), ou exportez la configuration et copiez le fichier sous wad\\defaults\\configuration.json.";
    private const string RefusedPrefix = "Configuration par défaut non enregistrée : ";
    private const string WrittenToast = "Configuration par défaut enregistrée.";
    private const string DefaultKeptOnUpdate = "La configuration par défaut de cette installation est conservée.";
    private static readonly string WrittenStatus = "Configuration par défaut enregistrée dans cette installation : " + InstallationDefaults.DisplayPath
        + " (version " + ConfigurationQualificationScripts.Version + ").";
    private static readonly string UnchangedStatus = "Configuration par défaut déjà identique (version " + ConfigurationQualificationScripts.Version
        + ") : aucun fichier modifié.";
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
            ["schemaVersion"] = 3, ["kind"] = "pesto.native-configuration-qualification",
            ["utc"] = DateTimeOffset.UtcNow.ToString("O"), ["success"] = false, ["adQualification"] = false,
            ["adExecuted"] = false, ["realUac"] = false, ["ordinaryProfileAccess"] = false,
            ["uiScope"] = "mainform-webview2-buttons-and-native-dialogs", ["uiDriver"] = "compiled-dom-input-and-click",
            ["fixtureSetup"] = "synthetic-configuration-and-pack-copy-before-mainform-start",
            ["installationUnderTest"] = "temporary-copy-of-running-pack", ["timeoutSeconds"] = 480,
            ["nativeUpdateInstallFromUiQualified"] = false, ["uncQualification"] = false,
            ["installationDefaultButtonFlowQualified"] = false, ["readOnlyRefusalQualified"] = false,
            ["legacyCustomPackPreparedFromUiQualified"] = false
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
        Dictionary<string, long>? sourceInventory = null;
        // A deny rule placed on the copy must be gone before the temporary tree is deleted, even after a failure.
        string? deniedDirectory = null;
        SecurityIdentifier? deniedSid = null;
        var stage = "package";
        var completed = false;
        void Check(bool value, string name)
        {
            if (!value) throw new PestoException("qualification.configuration." + name, "Contrôle natif non satisfait : " + name);
            checks.Add(name);
        }
        try
        {
            var package = UpdatePackage.Validate(AppPaths.AppDirectory);
            AppPaths.RequirePortableFiles(); HostPolicy.ClearBrowserOverrides();
            sourceFingerprint = package.Fingerprint;
            var sourceFiles = UpdatePackage.Inventory(AppPaths.AppDirectory);
            sourceInventory = sourceFiles;
            proof["channel"] = package.Channel;
            proof["runtimeMode"] = package.WebView2Runtime; proof["runtimeSource"] = AppPaths.RuntimeSource;
            proof["sourceFingerprint"] = package.Fingerprint;
            proof["sourceDistribution"] = package.Distribution;
            proof["executableSha256"] = UpdatePackage.Hash(Path.Combine(AppPaths.AppDirectory, "Pesto.exe"));
            // The pack under CI verification carries no default and must never receive one, even a refused one.
            if (Directory.Exists(Path.Combine(AppPaths.AppDirectory, "wad", "defaults")))
                throw new PestoException("qualification.configuration.source-defaults", "Le pack lancé contient déjà wad\\defaults : le banc exige un pack sans configuration par défaut et n’a rien modifié.");
            using var identity = WindowsIdentity.GetCurrent();
            var profile = new OperatorProfile(identity.User!.Value, Path.Combine(data, "LocalData"));
            var parentData = AppPaths.UserData(package.Channel, false, false, profile.LocalData);
            var config = new ProfileConfigurationService(parentData, profile.Sid, ConfigurationAccessMode.Live);
            config.Initialize();
            // Fixture setup only. All subsequent configuration changes of this profile must come through visible UI actions.
            static JsonObject Seed(ProfileConfigurationService service, string prefix) => service.PreviewSettings(PestoJson.Element(new
            {
                domain = "example.local", dc = "", prefix, rootOu = "OU=Postes,DC=example,DC=local",
                preprodOu = "", preprodSite = "", production = true, randomNames = false, namingPattern = PestoSettings.DefaultPattern,
                sites = new[] { new { id = "paris", name = "Paris", code = "PA", ou = "OU=Paris,OU=Postes,DC=example,DC=local" } }
            }));
            _ = config.ApplyImport(Text(Seed(config, "111301"), "planId"), true);
            var profileRoot = Path.GetDirectoryName(config.ConfigurationPath)!;
            var originalStamp = UpdatePackage.Hash(config.ConfigurationPath);
            var expectedConfiguration = Text(config.Export(ConfigurationQualificationScripts.Version), "fingerprint");
            var exportPath = Path.Combine(data, "export.json");

            stage = "installation-copy";
            // Fixture setup: the services and the buttons act on this verified copy, never on the running pack.
            var installation = Path.Combine(data, "install", "Pesto");
            scope.RequireOwned(installation);
            Directory.CreateDirectory(Path.GetDirectoryName(installation)!);
            UpdatePackage.CopyToNew(AppPaths.AppDirectory, installation, package.Fingerprint);
            var copy = UpdatePackage.Validate(installation, package.Channel);
            var copyInventory = UpdatePackage.Inventory(installation);
            var sumsPath = Path.Combine(installation, "wad", "SHA256SUMS");
            var manifestPath = Path.Combine(installation, "wad", "Pesto.package.json");
            var sumsSha = UpdatePackage.Hash(sumsPath);
            var manifestSha = UpdatePackage.Hash(manifestPath);
            var wad = Path.Combine(installation, "wad");
            var defaultsDirectory = Path.Combine(wad, "defaults");
            var defaultsFile = InstallationDefaults.PathIn(installation);
            Check(copy.Fingerprint == package.Fingerprint && copy.Distribution == package.Distribution && copy.FileCount == package.FileCount
                && copy.ConfigurationFingerprint is null && copy.LocalConfigurationFingerprint is null && SameInventory(copyInventory, sourceFiles)
                && sumsSha == UpdatePackage.Hash(Path.Combine(AppPaths.AppDirectory, "wad", "SHA256SUMS"))
                && manifestSha == UpdatePackage.Hash(Path.Combine(AppPaths.AppDirectory, "wad", "Pesto.package.json"))
                && UpdatePackage.Hash(Path.Combine(installation, "Pesto.exe")) == Text(proof, "executableSha256")
                && InstallationDefaults.Inspect(installation).State == "missing" && !Directory.Exists(defaultsDirectory), "installationCopyExact");
            proof["installationCopy"] = new JsonObject { ["relativePath"] = Relative(scope, installation), ["fingerprint"] = copy.Fingerprint,
                ["distribution"] = copy.Distribution, ["fileCount"] = copy.FileCount, ["sumsSha256"] = sumsSha, ["manifestSha256"] = manifestSha };
            IEnumerable<string> ProfileDefaultBackups()
            {
                var backups = Path.Combine(profileRoot, "backups");
                return Directory.Exists(backups) ? Directory.EnumerateFiles(backups, "installation-default.*", SearchOption.TopDirectoryOnly) : [];
            }
            bool SourcePackUntouched() => UpdatePackage.Validate(AppPaths.AppDirectory).Fingerprint == package.Fingerprint
                && SameInventory(UpdatePackage.Inventory(AppPaths.AppDirectory), sourceFiles)
                && !Directory.Exists(Path.Combine(AppPaths.AppDirectory, "wad", "defaults"));

            stage = "mainform";
            var updateState = Path.Combine(data, "updates");
            var native = new NativeHostActions(profile, package.Channel, false);
            host = new(native, scope);
            native.EnableQualificationFileGuard(scope, host.ObserveSelectionBeforeIo);
            // Both services receive the copy: a written, refused or carried default never reaches the running pack.
            var updates = new UpdateService(new(installation, updateState, package.Channel, false));
            var backend = new ApplicationServicesBackend(PestoBackend.CreateConfigurationOnly(parentData, gpRoot: Path.Combine(data, "GP")),
                false, config, updates, host, installation);
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
            var expectedBackendFailures = new HashSet<int>();
            // One exact engine refusal admitted at a time: its stage, operation, code and call number.
            (string Stage, string Operation, string Code, int Number)? admitted = null;
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
                        if (admitted is { } refusal && stage == refusal.Stage && Text(call, "operation") == refusal.Operation && code == refusal.Code
                            && observed.Count(refusal.Operation) == refusal.Number && Number(observed.Last(refusal.Operation), "sequence") == sequence)
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
            // Admits only the refusal observed for this exact call, then closes the admission.
            void CloseAdmission(string operation)
            {
                expectedBackendFailures.Add(Number(observed.Last(operation), "sequence"));
                admitted = null;
            }
            parent.Shown += async (_, _) =>
            {
                try
                {
                    stage = "parent";
                    await WaitUi(state => Idle(state) && Text(state, "prefix") == "111301");
                    Check(!parent.StartFailed, "parentReady");
                    // One section is shown at a time (2.0.15): open the one holding the next field or button first.
                    await Act(ConfigurationQualificationStep.ShowConfiguration);
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
                    proof["exportObservation"] = new JsonObject { ["relativePath"] = Relative(scope, exportPath),
                        ["sha256"] = exportStamp, ["configurationFingerprint"] = expectedConfiguration, ["version"] = ConfigurationQualificationScripts.Version };
                    Check(!Directory.EnumerateFiles(data, "export.json.*.tmp", SearchOption.TopDirectoryOnly).Any(), "noExportTemporaryFile");
                    proof["nativeExportFromUiQualified"] = true;
                    await Capture("configuration-export.png");

                    stage = "settings-ui";
                    await Act(ConfigurationQualificationStep.ShowDirectory);
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
                    await Act(ConfigurationQualificationStep.ShowConfiguration);
                    await Pick(ImportTitle, null, ConfigurationQualificationStep.Import);
                    await WaitUi(state => Idle(state) && Returned("configuration.previewImport", "cancelled"));
                    Check(observed.Count("configuration.applyImport") == 1 && UpdatePackage.Hash(config.ConfigurationPath) == changedStamp, "importCancelled");
                    await Pick(ExportTitle, null, ConfigurationQualificationStep.Export);
                    await WaitUi(state => Idle(state) && Returned("configuration.export", "cancelled"));
                    Check(UpdatePackage.Hash(exportPath) == exportStamp, "exportCancelled");

                    stage = "invalid-encoding-ui";
                    var malformed = Path.Combine(data, "malformed.json");
                    File.WriteAllBytes(malformed, [0x7b, 0x22, 0xc3, 0x28, 0x22, 0x7d]);
                    var encodingImportNumber = observed.Count("configuration.previewImport") + 1;
                    admitted = (stage, "configuration.previewImport", "config.encoding", encodingImportNumber);
                    await Pick(ImportTitle, malformed, ConfigurationQualificationStep.Import);
                    await WaitUi(state => Idle(state) && Text(observed.Last("configuration.previewImport"), "failureCode") == "config.encoding"
                        && Text(state, "notifications").Contains("encodage invalide", StringComparison.Ordinal));
                    // The response can arrive during the awaited DOM snapshot, after WaitUi's failure
                    // scan. Admit this exact expected refusal before changing stage, even in that race.
                    var encodingFailure = observed.Last("configuration.previewImport");
                    Check(Flag(encodingFailure, "completed") && Text(encodingFailure, "failureCode") == "config.encoding"
                        && observed.Count("configuration.previewImport") == encodingImportNumber
                        && UpdatePackage.Hash(config.ConfigurationPath) == changedStamp && observed.Count("configuration.applyImport") == 1, "invalidEncodingRejected");
                    CloseAdmission("configuration.previewImport");

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

                    // « Définir comme configuration par défaut » writes wad\defaults\configuration.json in place, in the copy only.
                    stage = "default-confirmation-cancel-ui";
                    var statusReads = observed.Count("configuration.status");
                    await Act(ConfigurationQualificationStep.Default);
                    var defaultDialog = await WaitDialog(ConfigurationQualificationScripts.DefaultTitle);
                    var readState = observed.LastCompleted("configuration.status")?["result"]?["installationDefault"];
                    Check(observed.Count("configuration.setDefault") == 0 && observed.Count("configuration.status") > statusReads
                        && Text(readState, "state") == "missing" && Text(readState, "path") == InstallationDefaults.DisplayPath
                        && ConfirmsWith(defaultDialog, DefaultConfirmLabel)
                        && Text(defaultDialog["dialog"], "body").Contains(InstallationDefaults.DisplayPath, StringComparison.Ordinal)
                        && Text(defaultDialog["dialog"], "body").Contains("Aucun pack n’est recréé", StringComparison.Ordinal)
                        && !Text(defaultDialog["dialog"], "body").Contains("Il remplace", StringComparison.Ordinal)
                        && !Directory.Exists(defaultsDirectory) && SameInventory(UpdatePackage.Inventory(installation), copyInventory), "defaultWaitsForConfirmation");
                    await Capture("configuration-default-confirmation.png");
                    await Act(ConfigurationQualificationStep.CancelDefault);
                    await WaitUi(Idle);
                    Check(observed.Count("configuration.setDefault") == 0 && !Directory.Exists(defaultsDirectory)
                        && SameInventory(UpdatePackage.Inventory(installation), copyInventory), "defaultConfirmationCancelled");

                    stage = "default-readonly-ui";
                    // A real refusal: deny creating files and folders, and writing, in the copy's wad\ for the current SID.
                    // No inheritance: wad\defaults does not exist yet, so the engine must create it there and is refused.
                    var sid = identity.User!;
                    if (Directory.Exists(defaultsDirectory) || HasDeny(wad, sid))
                        throw new PestoException("qualification.configuration.readonly-setup", "La copie n’est pas dans l’état attendu pour le refus d’écriture.");
                    deniedDirectory = wad; deniedSid = sid;
                    try
                    {
                        SetDeny(wad, sid, present: true);
                        Check(HasDeny(wad, sid), "readOnlyRuleApplied");
                        admitted = (stage, "configuration.setDefault", ReadOnlyCode, observed.Count("configuration.setDefault") + 1);
                        await Act(ConfigurationQualificationStep.Default);
                        await WaitDialog(ConfigurationQualificationScripts.DefaultTitle);
                        await Act(ConfigurationQualificationStep.ConfirmDefault);
                        var refusedUi = await WaitUi(state => Idle(state) && Text(observed.Last("configuration.setDefault"), "failureCode") == ReadOnlyCode
                            && Text(state, "configurationStatus") == RefusedPrefix + ReadOnlyMessage
                            && Text(state, "notifications").Contains(ReadOnlyMessage, StringComparison.Ordinal), 120);
                        var refusal = observed.Last("configuration.setDefault");
                        Check(Flag(refusal, "completed") && Text(refusal, "failureCode") == ReadOnlyCode && Flag(refusal, "confirmed")
                            && observed.Count("configuration.setDefault") == 1 && refusal?["expectedSha256"]?.GetValue<string>() == ""
                            && observed.FailureMessage("configuration.setDefault") == ReadOnlyMessage, "readOnlyRefusedByEngine");
                        CloseAdmission("configuration.setDefault");
                        Check(Text(refusedUi, "configurationStatus") == RefusedPrefix + ReadOnlyMessage
                            && !Text(refusedUi, "notifications").Contains(WrittenToast, StringComparison.Ordinal), "readOnlyRefusalVisible");
                        Check(!Directory.Exists(defaultsDirectory) && SameInventory(UpdatePackage.Inventory(installation), copyInventory)
                            && UpdatePackage.Validate(installation, package.Channel).Fingerprint == copy.Fingerprint
                            && InstallationDefaults.Inspect(installation).State == "missing" && !ProfileDefaultBackups().Any()
                            && UpdatePackage.Hash(config.ConfigurationPath) == originalStamp, "readOnlyLeftNothing");
                    }
                    finally { if (TryRemoveDeny(wad, sid)) deniedDirectory = null; }
                    Check(deniedDirectory is null && !HasDeny(wad, sid), "readOnlyRuleRemoved");
                    proof["readOnlyRefusal"] = new JsonObject { ["operation"] = "configuration.setDefault", ["code"] = ReadOnlyCode,
                        ["rule"] = "deny-createfiles-createdirectories-write-current-sid-on-copy-wad-without-inheritance",
                        ["messageExact"] = true, ["statusExact"] = true, ["ruleRemoved"] = true };
                    proof["readOnlyRefusalQualified"] = true;

                    stage = "default-written-ui";
                    await Act(ConfigurationQualificationStep.Default);
                    var writeDialog = await WaitDialog(ConfigurationQualificationScripts.DefaultTitle);
                    if (!ConfirmsWith(writeDialog, DefaultConfirmLabel) || Text(writeDialog["dialog"], "body").Contains("Il remplace", StringComparison.Ordinal))
                        throw new PestoException("qualification.configuration.default-dialog", "La confirmation affichée ne correspond pas à une installation sans configuration par défaut.");
                    await Act(ConfigurationQualificationStep.ConfirmDefault);
                    var writtenUi = await WaitUi(state => Idle(state) && Returned("configuration.setDefault", "written")
                        && Text(state, "configurationStatus") == WrittenStatus, 120);
                    var written = Result("configuration.setDefault");
                    var writtenSha = UpdatePackage.Hash(defaultsFile);
                    Check(observed.Count("configuration.setDefault") == 2 && Flag(observed.Last("configuration.setDefault"), "confirmed")
                        && observed.Last("configuration.setDefault")?["expectedSha256"]?.GetValue<string>() == ""
                        && Text(observed.Last("configuration.setDefault"), "version") == ConfigurationQualificationScripts.Version
                        && Text(written, "path") == InstallationDefaults.DisplayPath && SamePath(Text(written, "file"), defaultsFile)
                        && Text(written, "version") == ConfigurationQualificationScripts.Version && Text(written, "fingerprint") == expectedConfiguration
                        && Text(written, "sha256") == writtenSha && written["replaced"]?.GetValue<bool>() == false
                        && written["previous"] is null && written["backup"] is null
                        && Text(written, "distribution") == package.Distribution && written["official"]?.GetValue<bool>() == (package.Distribution == "official")
                        && Text(written, "packFingerprint") == package.Fingerprint && !ProfileDefaultBackups().Any(), "defaultWrittenFromButton");
                    Check(Text(writtenUi, "configurationStatus") == WrittenStatus
                        && Text(writtenUi, "notifications").Contains(WrittenToast, StringComparison.Ordinal), "defaultWrittenVisible");
                    var after = UpdatePackage.Validate(installation, package.Channel);
                    Check(after.Fingerprint == copy.Fingerprint && after.Distribution == copy.Distribution && after.FileCount == copy.FileCount
                        && after.Bytes == copy.Bytes && after.ConfigurationFingerprint is null
                        && after.LocalConfigurationFingerprint == expectedConfiguration && after.LocalConfigurationVersion == ConfigurationQualificationScripts.Version
                        && UpdatePackage.Hash(sumsPath) == sumsSha && UpdatePackage.Hash(manifestPath) == manifestSha
                        && !File.ReadAllText(sumsPath).Contains("wad/defaults/", StringComparison.OrdinalIgnoreCase), "defaultPackIdentityUnchanged");
                    Check(UpdatePackage.Hash(Path.Combine(installation, "Pesto.exe")) == Text(proof, "executableSha256"), "defaultExecutableUnchanged");
                    Check(File.ReadAllBytes(defaultsFile).SequenceEqual(new UTF8Encoding(false).GetBytes(ConfigurationDocument.Canonical(exported)))
                        && ConfigurationDocument.Canonical(ConfigurationDocument.ValidateBundle(ConfigurationDocument.ReadFile(defaultsFile)))
                        == ConfigurationDocument.Canonical(exported), "defaultMatchesUiExport");
                    var writtenInventory = UpdatePackage.Inventory(installation);
                    var writtenState = InstallationDefaults.Inspect(installation);
                    Check(writtenInventory.Count == copyInventory.Count + 1 && writtenInventory.ContainsKey(InstallationDefaults.RelativePath)
                        && copyInventory.All(item => writtenInventory.TryGetValue(item.Key, out var size) && size == item.Value)
                        && Directory.EnumerateFileSystemEntries(defaultsDirectory).Select(entry => Path.GetFileName(entry)).SequenceEqual(["configuration.json"])
                        && writtenState.State == "local" && writtenState.Sha256 == writtenSha && writtenState.Fingerprint == expectedConfiguration, "noDefaultDebris");
                    await Capture("configuration-default-written.png");

                    stage = "default-unchanged-ui";
                    await Act(ConfigurationQualificationStep.Default);
                    var replaceDialog = await WaitDialog(ConfigurationQualificationScripts.DefaultTitle);
                    var replaceWarned = ConfirmsWith(replaceDialog, DefaultConfirmLabel) && Text(replaceDialog["dialog"], "body").Contains(
                        "Il remplace la configuration par défaut actuelle (version " + ConfigurationQualificationScripts.Version + ")", StringComparison.Ordinal)
                        && Text(observed.LastCompleted("configuration.status")?["result"]?["installationDefault"], "sha256") == writtenSha;
                    await Act(ConfigurationQualificationStep.ConfirmDefault);
                    var unchangedUi = await WaitUi(state => Idle(state) && Returned("configuration.setDefault", "unchanged")
                        && Text(state, "configurationStatus") == UnchangedStatus, 120);
                    var unchanged = Result("configuration.setDefault");
                    Check(replaceWarned && observed.Count("configuration.setDefault") == 3 && Flag(observed.Last("configuration.setDefault"), "confirmed")
                        && Text(observed.Last("configuration.setDefault"), "expectedSha256") == writtenSha
                        && Text(unchanged, "sha256") == writtenSha && Text(unchanged, "version") == ConfigurationQualificationScripts.Version
                        && Text(unchanged, "fingerprint") == expectedConfiguration && unchanged["backup"] is null
                        && Text(unchangedUi, "configurationStatus") == UnchangedStatus && UpdatePackage.Hash(defaultsFile) == writtenSha
                        && SameInventory(UpdatePackage.Inventory(installation), writtenInventory) && !ProfileDefaultBackups().Any(), "defaultUnchangedFromButton");
                    proof["installationDefault"] = new JsonObject { ["relativePath"] = Relative(scope, defaultsFile), ["state"] = writtenState.State,
                        ["version"] = ConfigurationQualificationScripts.Version, ["configurationFingerprint"] = expectedConfiguration, ["sha256"] = writtenSha,
                        ["distribution"] = after.Distribution, ["packFingerprint"] = after.Fingerprint, ["fileCount"] = after.FileCount,
                        ["sumsSha256"] = sumsSha, ["manifestSha256"] = manifestSha };
                    proof["installationDefaultButtonFlowQualified"] = true;

                    stage = "default-service-checks";
                    // Service checks of the file written by the button, not another UI journey.
                    var fresh = new ProfileConfigurationService(Path.Combine(data, "fresh"), profile.Sid, ConfigurationAccessMode.Live);
                    var first = fresh.Initialize(defaultsFile);
                    Check(Text(first, "status") == "imported" && Text(fresh.ReadSettings(), "prefix") == "111301", "freshProfileImportsDefaults");
                    var freshStamp = UpdatePackage.Hash(fresh.ConfigurationPath);
                    _ = fresh.Initialize(defaultsFile);
                    var existing = new ProfileConfigurationService(Path.Combine(data, "existing"), profile.Sid, ConfigurationAccessMode.Live);
                    existing.Initialize();
                    _ = existing.ApplyImport(Text(Seed(existing, "333333"), "planId"), true);
                    var existingStamp = UpdatePackage.Hash(existing.ConfigurationPath);
                    var pending = existing.Initialize(defaultsFile);
                    Check(UpdatePackage.Hash(fresh.ConfigurationPath) == freshStamp && Flag(pending, "requiresDecision")
                        && UpdatePackage.Hash(existing.ConfigurationPath) == existingStamp && Text(existing.ReadSettings(), "prefix") == "333333", "existingProfilePreserved");
                    var kept = existing.DecideDistribution(Text(pending["pendingDistribution"], "planId"), false, true);
                    var again = existing.Initialize(defaultsFile);
                    Check(Text(kept, "status") == "kept" && !Flag(again, "requiresDecision")
                        && UpdatePackage.Hash(existing.ConfigurationPath) == existingStamp && UpdatePackage.Hash(defaultsFile) == writtenSha, "existingProfileChoiceRemembered");

                    stage = "legacy-custom-pack-fixture";
                    // Code fixture, not a UI journey: the sealed format the button produced up to 2.0.13, built from the running pack
                    // (read only) to prove that such packs remain valid candidates from the maintenance buttons.
                    var legacyParent = Path.Combine(data, "legacy");
                    Directory.CreateDirectory(legacyParent);
                    var legacyPath = Path.Combine(legacyParent, "Pesto-perso");
                    scope.RequireOwned(legacyPath);
                    var legacy = LegacyCustomPack.Build(AppPaths.AppDirectory, legacyPath,
                        config.Export(ConfigurationQualificationScripts.Version), ConfigurationQualificationScripts.Version);
                    var legacyManifest = JsonNode.Parse(File.ReadAllText(Path.Combine(legacyPath, "wad", "Pesto.package.json")))!;
                    Check(legacy.Distribution == "custom" && legacy.ConfigurationFingerprint == expectedConfiguration && legacy.LocalConfigurationFingerprint is null
                        && legacy.Fingerprint != copy.Fingerprint && legacy.Version == copy.Version && legacy.Channel == copy.Channel
                        && legacyManifest["official"]?.GetValue<bool>() == false
                        && Text(legacyManifest, "configurationVersion") == ConfigurationQualificationScripts.Version
                        && Text(legacyManifest, "configurationFingerprint") == expectedConfiguration
                        && InstallationDefaults.Inspect(legacyPath).State == "sealed"
                        && File.ReadLines(Path.Combine(legacyPath, "wad", "SHA256SUMS")).Any(line => line.EndsWith("  " + InstallationDefaults.RelativePath, StringComparison.Ordinal))
                        && UpdatePackage.Hash(Path.Combine(legacyPath, "Pesto.exe")) == Text(proof, "executableSha256")
                        && !Directory.EnumerateDirectories(legacyParent, ".pesto-personnalisation-*", SearchOption.TopDirectoryOnly).Any()
                        && SourcePackUntouched(), "legacyCustomPackFixtureSealed");
                    proof["legacyCustomPack"] = new JsonObject { ["fixture"] = "LegacyCustomPack.Build", ["relativePath"] = Relative(scope, legacyPath),
                        ["fingerprint"] = legacy.Fingerprint, ["configurationFingerprint"] = expectedConfiguration, ["fileCount"] = legacy.FileCount };

                    stage = "maintenance-inspect-ui";
                    await Act(ConfigurationQualificationStep.ShowUpdates);
                    await Pick(SourceFolderTitle, legacyPath, ConfigurationQualificationStep.UpdateFolder);
                    var candidateUi = await WaitUi(state => Idle(state) && Number(state, "candidateCount") == 1
                        && Flag(observed.Last("updates.inspect"), "completed"), 180);
                    var inspected = Result("updates.inspect");
                    Check(observed.Count("updates.inspect") == 1 && observed.Count("updates.prepare") == 0
                        && Text(inspected, "fingerprint") == legacy.Fingerprint && Text(inspected, "distribution") == "custom"
                        && inspected["configurationIncluded"]?.GetValue<bool>() == true && inspected["localConfiguration"]?.GetValue<bool>() == false
                        && Text(candidateUi, "candidatesText").Contains("Pack personnalisé", StringComparison.Ordinal)
                        && !Text(candidateUi, "candidatesText").Contains("configuration par défaut incluse", StringComparison.Ordinal), "maintenanceFolderInspectedFromButton");
                    var candidateId = Text(inspected, "candidateId");
                    await Act(ConfigurationQualificationStep.PrepareUpdate);
                    await WaitUi(state => Idle(state) && Number(state, "preparedCount") == 1
                        && Flag(observed.Last("updates.prepare"), "completed"), 180);
                    Check(observed.Count("updates.prepare") == 1 && Text(observed.Last("updates.prepare"), "candidateId") == candidateId
                        && Text(Result("updates.prepare"), "fingerprint") == legacy.Fingerprint, "maintenancePreparedFromButton");
                    var preparedId = Text(Result("updates.prepare"), "preparedId");
                    var workspaces = Path.Combine(updateState, "workspaces");
                    scope.RequireOwned(workspaces);
                    var preparedDirectory = Directory.EnumerateDirectories(workspaces)
                        .Select(work => Path.Combine(work, "prepared", preparedId, "package")).Single(Directory.Exists);
                    scope.RequireOwned(preparedDirectory);
                    Check(UpdatePackage.Validate(preparedDirectory).Fingerprint == legacy.Fingerprint
                        && UpdatePackage.Validate(legacyPath).Fingerprint == legacy.Fingerprint
                        && UpdatePackage.Validate(installation, package.Channel).Fingerprint == copy.Fingerprint
                        && UpdatePackage.Hash(defaultsFile) == writtenSha, "maintenancePreparedCopyExact");
                    await Capture("maintenance-prepared.png");
                    await Act(ConfigurationQualificationStep.InstallUpdate);
                    var installDialog = await WaitDialog("Installer la mise à jour préparée");
                    Check(observed.Count("updates.install") == 0 && Text(installDialog["dialog"], "body").Contains("configuration reste", StringComparison.Ordinal)
                        && Text(installDialog["dialog"], "body").Contains(DefaultKeptOnUpdate, StringComparison.Ordinal), "maintenanceInstallWaitsForConfirmation");
                    await Capture("maintenance-install-confirmation.png");
                    await Act(ConfigurationQualificationStep.CancelInstall);
                    await WaitUi(Idle);
                    Check(observed.Count("updates.install") == 0 && native.PendingUpdate is null
                        && UpdateTransaction.List(installation).Count == 0, "maintenanceInstallConfirmationCancelled");
                    await Act(ConfigurationQualificationStep.UpdateStatus);
                    await WaitUi(state => Idle(state) && Flag(observed.Last("updates.status"), "completed"), 180);
                    var updateStatus = Result("updates.status");
                    Check(Text(updateStatus, "status") == "idle" && !Flag(updateStatus, "pendingRecovery")
                        && Text(updateStatus, "distribution") == package.Distribution && Text(updateStatus, "fingerprint") == package.Fingerprint
                        && Text(updateStatus["localConfiguration"], "state") == "local"
                        && Text(updateStatus["localConfiguration"], "fingerprint") == expectedConfiguration, "maintenanceStatusFromButton");
                    proof["maintenanceInspectionPreparationFromUiQualified"] = true;
                    proof["maintenanceInstallConfirmationCancelled"] = true;
                    proof["maintenanceScope"] = "legacy-custom-pack-folder-inspection-preparation-and-install-confirmation-cancellation";
                    proof["maintenancePreparedFingerprint"] = legacy.Fingerprint;
                    // Inspection and preparation over an installation carrying a local default; the installation itself is not run here.
                    proof["legacyCustomPackPreparedFromUiQualified"] = true;

                    stage = "integrity";
                    Check(observed.ForbiddenInvocations == 0 && host.ForbiddenInvocations == 0, "noForbiddenEffects");
                    Check(UpdatePackage.Hash(config.ConfigurationPath) == originalStamp && UpdatePackage.Hash(exportPath) == exportStamp, "operatorDataPreserved");
                    Check(SourcePackUntouched(), "sourcePackUnchanged");
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
            // Never leave a deny rule behind: it would block the deletion below and survive in the temporary tree.
            var ruleLeft = deniedDirectory is not null && deniedSid is not null && !TryRemoveDeny(deniedDirectory, deniedSid);
            proof["readOnlyRuleLeftInPlace"] = ruleLeft;
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
            var defaultsAbsent = !Directory.Exists(Path.Combine(AppPaths.AppDirectory, "wad", "defaults"));
            proof["sourcePackDefaultsAbsent"] = defaultsAbsent;
            try
            {
                proof["sourcePackUnchanged"] = sourceFingerprint is not null && sourceInventory is not null && defaultsAbsent
                    && UpdatePackage.Validate(AppPaths.AppDirectory).Fingerprint == sourceFingerprint
                    && SameInventory(UpdatePackage.Inventory(AppPaths.AppDirectory), sourceInventory);
            }
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
            proof["success"] = completed && !Directory.Exists(data) && Flag(proof, "sourcePackUnchanged") && defaultsAbsent && !ruleLeft
                && (observed?.ForbiddenInvocations ?? 0) == 0 && (host?.ForbiddenInvocations ?? 0) == 0;
            if (!completed && proof["failureCode"] is null) proof["failureCode"] = "qualification.configuration.timeout";
            File.WriteAllText(Path.Combine(output, "proof.json"), proof.ToJsonString(new() { WriteIndented = true }));
        }
        return Flag(proof, "success") ? 0 : 3;
    }

    private static bool Idle(JsonObject value) => Flag(value, "ready") && Text(value, "mode") == "configuration"
        && ConfigurationQualificationScripts.IsSettingsRoute(Text(value, "route")) && value["dialog"] is null && Flag(value, "buttonsReady")
        && Flag(value, "saveEnabled") && !Flag(value, "settingsBusy");
    private static bool Flag(JsonNode? value, string key) => value?[key]?.GetValue<bool>() == true;
    private static string Text(JsonNode? value, string key) => value?[key]?.GetValue<string>() ?? "";
    private static int Number(JsonNode? value, string key) => value?[key]?.GetValue<int>() ?? -1;
    private static bool SamePath(string? left, string right) => !string.IsNullOrWhiteSpace(left)
        && Path.TrimEndingDirectorySeparator(Path.GetFullPath(left)).Equals(Path.TrimEndingDirectorySeparator(Path.GetFullPath(right)), StringComparison.OrdinalIgnoreCase);
    private static string Relative(DemoQualificationScope scope, string path) => Path.GetRelativePath(scope.Root, path).Replace('\\', '/');
    private static bool SameInventory(IReadOnlyDictionary<string, long> left, IReadOnlyDictionary<string, long> right)
        => left.Count == right.Count && left.All(item => right.TryGetValue(item.Key, out var size) && size == item.Value);

    /// <summary>The open dialog offers « cancel » and « ok », with the exact confirmation label on « ok ».</summary>
    private static bool ConfirmsWith(JsonObject state, string label)
    {
        if (state["dialog"]?["actions"] is not JsonArray actions || state["dialog"]?["labels"] is not JsonArray labels || actions.Count != labels.Count) return false;
        var ids = actions.Select(action => action?.GetValue<string>()).ToList();
        var ok = ids.IndexOf("ok");
        return ok >= 0 && ids.Contains("cancel") && labels[ok]?.GetValue<string>() == label;
    }

    // Exactly the bench's rule: explicit, on this directory only, never inherited by existing files.
    private static FileSystemAccessRule DenyRule(SecurityIdentifier sid) => new(sid,
        FileSystemRights.CreateFiles | FileSystemRights.CreateDirectories | FileSystemRights.Write,
        InheritanceFlags.None, PropagationFlags.None, AccessControlType.Deny);

    private static void SetDeny(string directory, SecurityIdentifier sid, bool present)
    {
        var info = new DirectoryInfo(directory);
        var security = info.GetAccessControl(AccessControlSections.Access);
        // Removal takes every explicit deny of this SID on this directory: the bench requires that none existed before its own.
        if (present) security.AddAccessRule(DenyRule(sid));
        else security.RemoveAccessRuleAll(DenyRule(sid));
        info.SetAccessControl(security);
    }

    private static bool HasDeny(string directory, SecurityIdentifier sid) => new DirectoryInfo(directory).GetAccessControl(AccessControlSections.Access)
        .GetAccessRules(includeExplicit: true, includeInherited: false, typeof(SecurityIdentifier)).OfType<FileSystemAccessRule>()
        .Any(rule => rule.AccessControlType == AccessControlType.Deny && sid.Equals(rule.IdentityReference));

    /// <summary>Removes the bench's rule; true only when no explicit deny for this SID remains on the directory.</summary>
    private static bool TryRemoveDeny(string directory, SecurityIdentifier sid)
    {
        try
        {
            if (!Directory.Exists(directory)) return true;
            if (HasDeny(directory, sid)) SetDeny(directory, sid, present: false);
            return !HasDeny(directory, sid);
        }
        // Best effort during cleanup: a failure is reported as a rule left in place, never as a removal.
        catch (Exception) { return false; }
    }

    internal static async Task Dialog(MainForm parent, string title, string? path, Func<Task> action, CancellationToken token)
    {
        var owner = parent.Handle;
        var isFolder = title is SourceFolderTitle;
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

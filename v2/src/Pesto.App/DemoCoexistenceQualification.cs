using System.Diagnostics;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>A capability for one new temporary tree. Never resolved from an operator's Windows profile.</summary>
internal sealed class DemoQualificationScope
{
    public string Root { get; }
    public string LocalData => Path.Combine(Root, "LocalData");
    public string GpRoot => Path.Combine(Root, "GP");

    public DemoQualificationScope(string reportDirectory)
    {
        var output = Path.TrimEndingDirectorySeparator(Path.GetFullPath(reportDirectory));
        var temporary = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar;
        if (!output.StartsWith(temporary, StringComparison.OrdinalIgnoreCase) || !Directory.Exists(output))
            throw new PestoException("qualification.scope", "Le banc exige son dossier temporaire de preuve préalablement validé.");
        Root = Path.Combine(output, "coexistence");
        OperatorProfile.RejectLinks(Root);
        if (Directory.Exists(Root) || File.Exists(Root))
            throw new PestoException("qualification.scope", "Le dossier de coexistence existe déjà ; il ne sera pas réutilisé.");
        Directory.CreateDirectory(Root);
    }

    public void RequireOwned(string path)
    {
        var full = Path.GetFullPath(path);
        if (!full.StartsWith(Root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("qualification.scope", "Une donnée de qualification sort de son dossier temporaire dédié.");
        OperatorProfile.RejectLinks(full);
    }
}

/// <summary>
/// Runs the real shell and NativeHostActions.OpenDemoAsync. The parent has no directory/mutation gateway or
/// credentials. A closed host wrapper permits only demo.open, and coordination access is a refusing sentinel.
/// All UI interactions are compiled steps; browser observations use the normal closed bridge.
/// </summary>
internal static class DemoCoexistenceQualification
{
    public const int TimeoutSeconds = 180;
    // Each UI transition must be proved within 35 s. Only the parent's first WebView2 initialization on a
    // fresh profile may take longer on a loaded runner; it stays inside the global watchdog and its duration
    // is recorded, so slowness is visible instead of hidden.
    private static readonly TimeSpan StepLimit = TimeSpan.FromSeconds(35);
    private static readonly TimeSpan ParentStartLimit = TimeSpan.FromSeconds(120);
    // One qualification per process (--qualify-demo). Last observed state of the current wait, for diagnosis only.
    private static JsonObject lastWait = new();
    private static readonly string[] RequiredChecks = ["parentReady", "demoOpenedFromUi", "profilesDistinct", "parentDraftPreserved",
        "parentRoutePreserved", "parentPreferencesPreserved", "parentLoginThemeRestored", "permanentBannerConfirmed", "scenarioConfirmed", "resetConfirmed",
        "fictitiousRestartConfirmed", "idsDistinctAfterReset", "idsDistinctAcrossWindows", "idsDistinct", "childClosed", "parentClosedWithChild", "freshUiTransitions"];

    public static JsonObject NotStarted() => new()
    {
        ["success"] = false, ["failureCode"] = "qualification.coexistence.not-started", ["timeoutSeconds"] = TimeoutSeconds
    };

    public static JsonObject Run(string reportDirectory, string channel)
    {
        var scope = new DemoQualificationScope(reportDirectory);
        var proof = NewProof();
        lastWait = new JsonObject();
        var uiTransitions = new JsonArray();
        proof["uiTransitions"] = uiTransitions;
        var watch = Stopwatch.StartNew();
        using var stop = new CancellationTokenSource();
        CoexistenceDeadline campaign = default;
        var profile = new OperatorProfile("S-1-5-21-0-0-0-1001", scope.LocalData);
        var parentData = AppPaths.UserData(channel, false, false, profile.LocalData);
        scope.RequireOwned(parentData);
        scope.RequireOwned(scope.GpRoot);
        var configuration = new ProfileConfigurationService(parentData, profile.Sid, ConfigurationAccessMode.Live);
        configuration.Initialize(); // No distributed or legacy configuration is supplied.
        var native = new NativeHostActions(profile, channel, false);
        var host = new DemoOnlyHost(native);
        var deniedCoordination = new DeniedCoordinationAccess();
        var coordination = new SharedCoordinationAdministration(configuration.ConfigurationPath, SharedCoordinationAccessMode.Live, deniedCoordination);
        var backend = new ApplicationServicesBackend(PestoBackend.CreateConfigurationOnly(parentData, gpRoot: scope.GpRoot), false,
            configuration, null, host, AppPaths.AppDirectory, coordination);
        using var parent = new MainForm(backend, false, false, channel, parentData, initialPage: "parametres", configurationOnly: true,
            loginTheme: new LoginThemePreference(parentData));
        parent.EnableQualification(scope);
        native.Owner = parent;
        var children = new List<MainForm>();
        var childClosed = new HashSet<MainForm>();
        var profiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { parent.QualificationProfile };
        var instances = new HashSet<string>(StringComparer.Ordinal);
        var receipts = new HashSet<string>(StringComparer.Ordinal);
        JsonObject? parentBefore = null;
        MainForm? lastChild = null;
        var completed = false;
        var closingParentWithChild = false;
        var parentClosed = false;
        var stage = "parent-start";

        void Fail(string code, Exception? error = null)
        {
            if (proof["failureCode"] is null)
            {
                proof["failureCode"] = code;
                if (error is not null)
                {
                    // Exception types and HRESULT only; browser messages may contain user or profile data.
                    proof["exceptionType"] = error.GetType().Name;
                    proof["exceptionHResult"] = error.HResult;
                    proof["innerExceptionType"] = error.InnerException?.GetType().Name;
                }
            }
            stop.Cancel();
            if (!parent.IsDisposed && parent.IsHandleCreated) parent.Close();
        }

        parent.FormClosed += (_, _) =>
        {
            parentClosed = true;
            proof["parentClosedWithChild"] = closingParentWithChild && lastChild is not null && childClosed.Contains(lastChild);
            stop.Cancel();
        };
        ThreadExceptionEventHandler uiFailure = (_, e) => Fail("qualification.coexistence.ui", e.Exception);
        Application.ThreadException += uiFailure;
        using var watchdog = new System.Windows.Forms.Timer { Interval = TimeoutSeconds * 1000 };
        watchdog.Tick += (_, _) => { watchdog.Stop(); Fail("qualification.coexistence.timeout"); };

        async Task<MainForm> OpenChildAsync()
        {
            await Act(parent, DemoQualificationStep.OpenDemo, campaign);
            BeginStep("owned-child-created");
            await Until(_ => Task.FromResult(parent.OwnedForms.OfType<MainForm>().Count(f => !f.IsDisposed) == 1
                && host.DemoOpens == children.Count + 1), campaign);
            var child = parent.OwnedForms.OfType<MainForm>().Single(f => !f.IsDisposed);
            Require(!children.Contains(child), "child-reused");
            children.Add(child);
            child.FormClosed += (_, _) => childClosed.Add(child);
            child.EnableQualification(scope);
            Require(profiles.Add(child.QualificationProfile), "profile-reused");
            var ui = await WaitSnapshot(child, "first-mount-and-demo-banner", value => Ready(value, "simulation") && HasDemoBanner(value), campaign);
            Require(!Flag(ui, "configurationEntry") && ((JsonArray?)ui["navigation"])?.Count >= 9, "child-navigation");
            var prefs = ui["preferences"] as JsonObject;
            Require(prefs is not null && prefs["pesto.native.qualification.parent"] is null
                && prefs["pesto.native.qualification.child"] is null, "profile-storage");
            var state = await ReadBackend(child, campaign);
            Require(Text(state, "mode") == "simulation" && Text(state["demo"], "scenario") == "standard", "child-mode");
            var instanceId = Text(state["demo"], "instanceId");
            Require(Guid.TryParseExact(instanceId, "N", out _) && instances.Add(instanceId), "instance-reused");
            return child;
        }

        async Task VerifyParentAsync()
        {
            var value = await WaitSnapshot(parent, "parent-context", state => Ready(state, "configuration"), campaign);
            var before = parentBefore ?? throw new PestoException("qualification.coexistence.parent-baseline", "Le contexte initial du parent n’a pas été consigné.");
            var draft = JsonNode.DeepEquals(before["draft"], value["draft"]);
            var route = Text(before, "route") == Text(value, "route") && Text(value, "route") == "#/parametres";
            var preferences = JsonNode.DeepEquals(before["preferences"], value["preferences"])
                && Text(value, "theme") == "dark" && Flag(value, "collapsed");
            proof["parentDraftPreserved"] = draft;
            proof["parentRoutePreserved"] = route;
            proof["parentPreferencesPreserved"] = preferences;
            Require(draft && route && preferences && parent.Visible && !parent.QualificationClosing, "parent-context");
            Require(!File.Exists(configuration.ConfigurationPath), "parent-configuration-written");
        }

        void RememberReceipt(JsonObject state, string code)
        {
            var id = Text(OnlyReceipt(state), "id");
            var prefix = "receipt-" + Text(state["demo"], "instanceId") + "-";
            Require(id.StartsWith(prefix, StringComparison.Ordinal) && long.TryParse(id[prefix.Length..], out var serial)
                && serial > 0 && receipts.Add(id), code);
        }

        parent.Shown += async (_, _) =>
        {
            try
            {
                var initial = await WaitSnapshot(parent, "parent-initial-mount", value => Ready(value, "configuration") && Flag(value, "demoEnabled"), campaign, ParentStartLimit);
                proof["parentReadyMilliseconds"] = watch.ElapsedMilliseconds;
                Require(Flag(initial, "configurationEntry") && Flag(initial, "bannerVisible"), "parent-local-mode");
                Require(JsonNode.DeepEquals(initial["navigation"], new JsonArray("aide", "parametres")), "parent-navigation");
                var parentSession = await ReadBackend(parent, campaign);
                Require(Text(parentSession, "mode") == "live" && Flag(parentSession, "configurationOnly") && Flag(parentSession, "readOnly")
                    && parentSession["domain"] is null && parentSession["dc"] is null, "parent-session");
                proof["parentReady"] = true;

                stage = "parent-draft";
                await Act(parent, DemoQualificationStep.SeedParent, campaign);
                parentBefore = await WaitSnapshot(parent, "parent-draft", value => Text(value, "theme") == "dark" && Flag(value, "collapsed")
                    && Text(value["draft"], "domain") == "qualification.invalid" && Text(value["draft"], "prefix") == "QF", campaign);
                await Capture(parent, "parent-draft.png", campaign);

                stage = "first-child";
                var child = await OpenChildAsync();
                proof["demoOpenedFromUi"] = host.DemoOpens == 1;
                await VerifyParentAsync();
                await Act(child, DemoQualificationStep.SetChildPreferences, campaign);
                await WaitSnapshot(child, "child-preferences", value => Text(value, "theme") == "contrast" && Flag(value, "collapsed"), campaign);
                await Act(child, DemoQualificationStep.ReloadWithCompactBanner, campaign);
                await WaitSnapshot(child, "child-reload", value => Ready(value, "simulation") && Flag(value, "reloaded") && HasDemoBanner(value)
                    && Text(value, "theme") == "contrast", campaign);
                proof["permanentBannerConfirmed"] = true;

                stage = "scenario-pending";
                var pending = await Scenario(child, DemoQualificationStep.SelectPendingRestart, "pendingRestart", uiTransitions, campaign);
                var firstReceipt = OnlyReceipt(pending);
                Require(Text(firstReceipt, "status") == "pendingRestart" && Text(firstReceipt, "code") == "20" && Flag(firstReceipt, "restartRequired"), "pending-receipt");
                RememberReceipt(pending, "receipt-reused");
                await Capture(child, "demo-pending.png", campaign);

                stage = "fictitious-restart";
                var beforeRestart = await DemoAction(child, DemoQualificationStep.Restart, campaign);
                var restarted = await WaitBackend(child, value => Number(value["demo"], "pendingRestart") == 0
                    && OnlyReceiptOrNull(value) is { } receipt && !Flag(receipt, "restartRequired") && Text(receipt, "status") == "simulated", beforeRestart, uiTransitions, campaign);
                Require(Text(OnlyReceipt(restarted), "id") == Text(firstReceipt, "id") && Text(OnlyReceipt(restarted), "code") == "20", "restart-receipt");
                proof["fictitiousRestartConfirmed"] = true;
                await Capture(child, "demo-restarted.png", campaign);

                stage = "scenario-joined";
                var joined = await Scenario(child, DemoQualificationStep.SelectJoined, "joined", uiTransitions, campaign);
                Require(Number(joined["demo"], "pendingRestart") == 0 && ((JsonArray?)joined["receipts"])?.Count == 0, "joined-scenario");
                proof["scenarioConfirmed"] = true;

                stage = "reset";
                var previousGeneration = Number(joined["demo"], "generation");
                var beforeReset = await DemoAction(child, DemoQualificationStep.Reset, campaign);
                var reset = await WaitBackend(child, value => Text(value["demo"], "scenario") == "standard"
                    && Number(value["demo"], "generation") > previousGeneration && ((JsonArray?)value["receipts"])?.Count == 0, beforeReset, uiTransitions, campaign);
                Require(Number(reset["demo"], "pendingRestart") == 0, "reset-pending");
                proof["resetConfirmed"] = true;
                proof["generationAfterReset"] = Number(reset["demo"], "generation");

                stage = "ids-after-reset";
                var again = await Scenario(child, DemoQualificationStep.SelectPendingRestart, "pendingRestart", uiTransitions, campaign);
                Require(Text(again["demo"], "instanceId") == Text(pending["demo"], "instanceId"), "reset-instance");
                RememberReceipt(again, "receipt-reused-after-reset");
                proof["idsDistinctAfterReset"] = true;
                await VerifyParentAsync();

                stage = "child-close";
                child.Close();
                BeginStep("owned-child-closed");
                await Until(_ => Task.FromResult(childClosed.Contains(child) && child.IsDisposed && parent.OwnedForms.Length == 0), campaign);
                proof["childClosed"] = true;
                await VerifyParentAsync();
                await Capture(parent, "parent-preserved.png", campaign);

                stage = "second-child";
                lastChild = await OpenChildAsync();
                var second = await Scenario(lastChild, DemoQualificationStep.SelectPendingRestart, "pendingRestart", uiTransitions, campaign);
                RememberReceipt(second, "receipt-reused-across-windows");
                Require(instances.Count == 2 && profiles.Count == 3 && host.DemoOpens == 2, "distinct-instances");
                proof["profilesDistinct"] = true;
                proof["idsDistinctAcrossWindows"] = true;
                proof["idsDistinct"] = receipts.Count == 3;
                proof["freshUiTransitions"] = uiTransitions.Count == 6;
                await VerifyParentAsync();

                stage = "parent-close-with-child";
                Require(parent.OwnedForms.Contains(lastChild) && !lastChild.IsDisposed && !lastChild.QualificationClosing, "owned-child");
                closingParentWithChild = true;
                completed = true;
                parent.Close();
            }
            catch (Exception error)
            {
                var code = error switch
                {
                    CoexistenceTimeout timeout => timeout.Code,
                    PestoException pesto => pesto.Code,
                    OperationCanceledException => "qualification.coexistence.cancelled",
                    _ => "qualification.coexistence.failed"
                };
                Fail(code, error);
            }
        };

        try
        {
            campaign = CoexistenceDeadline.Start(stop.Token, TimeSpan.FromSeconds(TimeoutSeconds), "qualification.coexistence.timeout");
            watchdog.Start();
            Application.Run(parent);
        }
        catch (Exception error) { Fail("qualification.coexistence.message-loop", error); }
        finally
        {
            watchdog.Stop();
            Application.ThreadException -= uiFailure;
            stop.Cancel();
            foreach (var child in children) child.Dispose();
            parent.Dispose();
        }
        proof["stage"] = stage;
        proof["lastWait"] = lastWait.DeepClone();
        proof["parentClosed"] = parentClosed;
        var parentLoginTheme = new LoginThemePreference(parentData).Read();
        proof["parentLoginThemeRestored"] = parentLoginTheme == "dark";
        // Un simple booleen ne distingue pas « jamais ecrit » de « ecrase par une autre fenetre » :
        // les deux passages 81e4b703 donnaient des valeurs opposees sur le meme binaire, sans explication.
        proof["parentLoginTheme"] = parentLoginTheme;
        proof["parentLoginThemeFilePresent"] = File.Exists(Path.Combine(parentData, "login-theme.txt"));
        proof["demoOpenInvocations"] = host.DemoOpens;
        proof["forbiddenHostInvocations"] = host.ForbiddenInvocations;
        proof["coordinationInvocations"] = deniedCoordination.Invocations;
        proof["configurationCreated"] = File.Exists(configuration.ConfigurationPath);
        proof["distinctProfileCount"] = profiles.Count;
        proof["distinctInstanceCount"] = instances.Count;
        proof["distinctReceiptCount"] = receipts.Count;
        proof["instanceIds"] = new JsonArray(instances.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray());
        proof["receiptIds"] = new JsonArray(receipts.Select(id => (JsonNode?)JsonValue.Create(id)).ToArray());
        proof["profiles"] = new JsonArray(profiles.Select(path => (JsonNode?)JsonValue.Create(Path.GetRelativePath(scope.Root, path).Replace('\\', '/'))).ToArray());
        proof["elapsedMilliseconds"] = watch.ElapsedMilliseconds;
        proof["success"] = completed && parentClosed && RequiredChecks.All(key => Flag(proof, key))
            && host.DemoOpens == 2 && profiles.Count == 3 && instances.Count == 2 && receipts.Count == 3
            && host.ForbiddenInvocations == 0 && deniedCoordination.Invocations == 0 && !File.Exists(configuration.ConfigurationPath)
            && proof["failureCode"] is null;
        if (!Flag(proof, "success")) proof["failureCode"] ??= "qualification.coexistence.incomplete";
        return proof;
    }

    private static JsonObject NewProof() => new()
    {
        ["success"] = false, ["timeoutSeconds"] = TimeoutSeconds, ["parentKind"] = "configuration-only-no-adapter",
        ["parentReady"] = false, ["demoOpenedFromUi"] = false, ["profilesDistinct"] = false,
        ["parentDraftPreserved"] = false, ["parentRoutePreserved"] = false, ["parentPreferencesPreserved"] = false,
        ["permanentBannerConfirmed"] = false, ["scenarioConfirmed"] = false, ["resetConfirmed"] = false,
        ["fictitiousRestartConfirmed"] = false, ["idsDistinctAfterReset"] = false, ["idsDistinctAcrossWindows"] = false,
        ["idsDistinct"] = false, ["childClosed"] = false, ["parentClosedWithChild"] = false, ["freshUiTransitions"] = false, ["failureCode"] = null,
        ["captures"] = new JsonArray("coexistence/parent-draft.png", "coexistence/demo-pending.png", "coexistence/demo-restarted.png", "coexistence/parent-preserved.png"),
        ["adQualification"] = false
    };

    private static JsonObject BeginStep(string label) => lastWait = new JsonObject
    {
        ["substep"] = label, ["startedUtc"] = DateTimeOffset.UtcNow.ToString("O")
    };

    private static async Task Act(MainForm form, DemoQualificationStep step, CoexistenceDeadline deadline)
    {
        var wait = BeginStep("action:" + step);
        wait["actionIssued"] = false;
        wait["actionConfirmed"] = false;
        var actionDeadline = deadline.Within(StepLimit);
        var result = await actionDeadline.OnUiAsync(() =>
        {
            wait["actionIssued"] = true;
            return form.QualificationStepAsync(step);
        }, pending => wait["actionPending"] = pending);
        _ = actionDeadline.Remaining();
        Require(result == "true", "ui-action");
        wait["actionConfirmed"] = true;
    }

    private static async Task<JsonObject> WaitSnapshot(MainForm form, string label, Func<JsonObject, bool> predicate, CoexistenceDeadline deadline,
        TimeSpan? limit = null, DemoQualificationStep observation = DemoQualificationStep.Snapshot)
    {
        JsonObject? found = null;
        var wait = BeginStep(label);
        wait["observation"] = observation.ToString();
        wait["snapshotRequests"] = 0;
        wait["snapshotReads"] = 0;
        var elapsed = Stopwatch.StartNew();
        await Until(async stepDeadline =>
        {
            Require(!form.StartFailed, "webview-start");
            wait["snapshotRequests"] = wait["snapshotRequests"]!.GetValue<int>() + 1;
            wait["windowBeforeRead"] = form.QualificationWindowState();
            var read = Stopwatch.StartNew();
            string raw;
            try
            {
                raw = await stepDeadline.OnUiAsync(() => form.QualificationStepAsync(observation),
                    pending => wait["snapshotPending"] = pending);
            }
            finally
            {
                wait["lastSnapshotMilliseconds"] = read.ElapsedMilliseconds;
                wait["elapsedMilliseconds"] = elapsed.ElapsedMilliseconds;
            }
            wait["windowAfterRead"] = form.QualificationWindowState();
            Require(raw.Length <= 256 * 1024, "snapshot-size");
            if (JsonNode.Parse(raw) is not JsonObject snapshot) return false;
            wait["snapshotReads"] = wait["snapshotReads"]!.GetValue<int>() + 1;
            // Compiled state labels only: no draft values, preferences, paths or messages enter the proof.
            wait["last"] = new JsonObject
            {
                ["ready"] = Flag(snapshot, "ready"), ["mode"] = Text(snapshot, "mode"), ["demoEnabled"] = snapshot["demoEnabled"]?.DeepClone(),
                ["route"] = Text(snapshot, "route"), ["readyRoute"] = Text(snapshot, "readyRoute"),
                ["bannerVisible"] = snapshot["bannerVisible"]?.DeepClone(),
                ["dialogOpen"] = snapshot.ContainsKey("dialog") ? JsonValue.Create(snapshot["dialog"] is not null) : null,
                ["finiteAnimationsRunning"] = snapshot["finiteAnimationsRunning"]?.DeepClone(),
                ["mainPage"] = Text(snapshot, "mainPage"), ["documentState"] = Text(snapshot, "documentState"),
                ["documentVisible"] = Flag(snapshot, "documentVisible"), ["headingPresent"] = Flag(snapshot, "headingPresent"),
                ["errorCards"] = Number(snapshot, "errorCards"), ["skeletons"] = Number(snapshot, "skeletons"),
                ["busyRegions"] = Number(snapshot, "busyRegions")
            };
            if (!predicate(snapshot)) return false;
            found = snapshot;
            return true;
        }, deadline, limit, wait);
        return found!;
    }

    private static async Task<JsonObject> ReadBackend(MainForm form, CoexistenceDeadline deadline)
    {
        await Act(form, DemoQualificationStep.ReadBackend, deadline);
        var state = await WaitSnapshot(form, "backend-read", value => Text(value["backend"], "state") is "done" or "failed", deadline);
        if (Text(state["backend"], "state") != "done")
        {
            // Only compiled diagnostic labels can enter a proof. Never echo exception messages,
            // URLs, payloads or stack traces from the browser/native services.
            var step = Text(state["backend"], "step") switch
            {
                "channel" => "channel", "module" => "module", "export" => "export", "session" => "session",
                "status" => "status", "receipts" => "receipts", _ => "read"
            };
            var reason = Text(state["backend"], "reason") switch
            {
                "unavailable" => "unavailable", "origin" => "origin", "invalid" => "invalid", "timeout" => "timeout",
                "closed" => "closed", "native-failed" => "native-failed", "cancelled" => "cancelled", "refused" => "refused",
                "type-error" => "type-error", _ => "error"
            };
            var serverCode = Text(state["backend"], "serverCode") switch
            {
                "config.missing" => "config.missing", "config.invalid" => "config.invalid", "config.changed" => "config.changed",
                "config.profile" => "config.profile", "directory.unavailable" => "directory.unavailable", "host.closing" => "host.closing",
                "session.configurationOnly" => "session.configurationOnly", "demo.required" => "demo.required", "demo.isolated" => "demo.isolated",
                "demo.closed" => "demo.closed", "operation.unknown" => "operation.unknown", "operation.busy" => "operation.busy",
                "operation.failed" => "operation.failed", "operation.cancelled" => "operation.cancelled", "message.size" => "message.size",
                "message.id" => "message.id", "message.json" => "message.json", "arguments.invalid" => "arguments.invalid",
                "invalid_arguments" => "invalid_arguments", "request.duplicate" => "request.duplicate", _ => null
            };
            throw new PestoException("qualification.coexistence.bridge-" + step + "-" + (serverCode ?? reason), "La lecture native de contrôle n’a pas été prouvée.");
        }
        return (JsonObject)state["backend"]!;
    }

    private sealed record UiTransitionStart(int MountId, string Route, string Action);

    private static async Task<JsonObject> WaitBackend(MainForm form, Func<JsonObject, bool> predicate,
        UiTransitionStart before, JsonArray transitions, CoexistenceDeadline deadline)
    {
        JsonObject? found = null;
        await Until(async stepDeadline =>
        {
            var ui = await WaitSnapshot(form, "transition:mapped-page", value => Ready(value, "simulation") && value["dialog"] is null, stepDeadline);
            Require(HasDemoBanner(ui), "demo-banner");
            var value = await ReadBackend(form, stepDeadline);
            if (!predicate(value)) return false;
            // Engine completion precedes changed(session.info -> router.go). Even the same route must
            // really remount, and Interventions must paint the exact new receipt status before advancing.
            var mounted = await WaitSnapshot(form, "transition:fresh-mount", state => ExpectedDemoPage(state, value, before), stepDeadline);
            transitions.Add(new JsonObject
            {
                ["action"] = before.Action, ["instanceId"] = Text(value["demo"], "instanceId"),
                ["scenario"] = Text(value["demo"], "scenario"), ["beforeMount"] = before.MountId,
                ["afterMount"] = Number(mounted, "mountId"), ["beforeRoute"] = before.Route,
                ["afterRoute"] = Text(mounted, "route"), ["readyRoute"] = Text(mounted, "readyRoute"),
                ["receiptCards"] = mounted["receiptCards"]?.DeepClone()
            });
            found = value; return true;
        }, deadline);
        return found!;
    }

    private static async Task<UiTransitionStart> DemoAction(MainForm form, DemoQualificationStep action, CoexistenceDeadline deadline)
    {
        await Act(form, DemoQualificationStep.NavigateSettings, deadline);
        var before = await WaitSnapshot(form, "settings-mounted", value => Ready(value, "simulation") && Text(value, "readyRoute") == "parametres"
            && Flag(value, "demoEnabled") && value["dialog"] is null, deadline);
        Require(Number(before, "mountId") > 0, "ui-mount");
        await Act(form, DemoQualificationStep.OpenDemo, deadline);
        await WaitSnapshot(form, "scenario-dialog-open", value => value["dialog"]?["scenario"] is not null, deadline);
        await Act(form, action, deadline);
        await WaitSnapshot(form, "confirmation-dialog-open", value => value["dialog"]?["actions"] is JsonArray actions
            && actions.Any(item => item?.GetValue<string>() == "ok"), deadline);
        await Act(form, DemoQualificationStep.Confirm, deadline);
        return new(Number(before, "mountId"), Text(before, "route"), action.ToString());
    }

    private static async Task<JsonObject> Scenario(MainForm form, DemoQualificationStep selection, string expected, JsonArray transitions, CoexistenceDeadline deadline)
    {
        var before = await ReadBackend(form, deadline);
        var generation = Number(before["demo"], "generation");
        var beforeUi = await DemoAction(form, selection, deadline);
        return await WaitBackend(form, value => Text(value["demo"], "scenario") == expected
            && Number(value["demo"], "generation") > generation, beforeUi, transitions, deadline);
    }

    private static bool ExpectedDemoPage(JsonObject ui, JsonObject backend, UiTransitionStart before)
    {
        var page = Text(backend["demo"], "page");
        if (!Ready(ui, "simulation") || ui["dialog"] is not null || !HasDemoBanner(ui) || Number(ui, "mountId") <= before.MountId
            || Text(ui, "route") != "#/" + page || Text(ui, "readyRoute") != page || Text(ui, "mainPage") != page)
            return false;
        if (page == "ajouter") return Flag(ui, "joinFormReady");
        if (page == "unposte") return Flag(ui, "singleComputerFormReady");
        if (page != "interventions" || !Flag(ui, "receiptListReady")
            || ui["receiptCards"] is not JsonArray cards || backend["receipts"] is not JsonArray expected || cards.Count != expected.Count)
            return false;
        return expected.All(receipt => cards.Count(card => Text(card, "id") == Text(receipt, "id")
            && Text(card, "status") == Text(receipt, "status") && Text(card, "mode") == "simulation") == 1);
    }

    private static async Task Capture(MainForm form, string name, CoexistenceDeadline deadline)
    {
        // Ignore intentionally infinite background motion, but let finite page/theme transitions finish
        // so the PNG depicts the proved DOM rather than the outgoing view-transition snapshot.
        await WaitSnapshot(form, "capture:finite-transitions", state => Flag(state, "ready") && state["finiteAnimationsRunning"]?.GetValue<bool>() == false,
            deadline, observation: DemoQualificationStep.CaptureSnapshot);
        var wait = BeginStep("capture:" + name);
        await deadline.Within(StepLimit).OnUiAsync(async () =>
        {
            await form.QualificationCaptureAsync(name);
            return true;
        }, pending => wait["capturePending"] = pending);
    }

    private static async Task Until(Func<CoexistenceDeadline, Task<bool>> predicate, CoexistenceDeadline deadline, TimeSpan? limit = null, JsonObject? timing = null)
    {
        var time = Stopwatch.StartNew();
        var stepDeadline = deadline.Within(limit ?? StepLimit);
        try
        {
            while (true)
            {
                _ = stepDeadline.Remaining();
                var matches = await predicate(stepDeadline);
                _ = stepDeadline.Remaining();
                if (matches) return;
                var delay = Stopwatch.StartNew();
                // Timestamp the timer completion off the UI context. Only the UI thread records its resumption.
                var completionMilliseconds = await stepDeadline.WaitAsync(() => ObserveDelayCompletionAsync(delay, stepDeadline.Token));
                if (timing is not null)
                {
                    var delayMilliseconds = delay.ElapsedMilliseconds;
                    timing["lastDelayMilliseconds"] = delayMilliseconds;
                    // Keep the split for the slowest wait: a later fast cycle must not erase it.
                    if (delayMilliseconds >= (timing["maxDelayMilliseconds"]?.GetValue<long>() ?? 0L))
                    {
                        timing["maxDelayMilliseconds"] = delayMilliseconds;
                        timing["maxDelayCompletionMilliseconds"] = completionMilliseconds;
                        timing["maxDelayContextResumeMilliseconds"] = delayMilliseconds - completionMilliseconds;
                    }
                    timing["lastDelayCompletionMilliseconds"] = completionMilliseconds;
                    timing["lastDelayContextResumeMilliseconds"] = delayMilliseconds - completionMilliseconds;
                    timing["delayCount"] = (timing["delayCount"]?.GetValue<int>() ?? 0) + 1;
                }
            }
        }
        finally { if (timing is not null) timing["waitElapsedMilliseconds"] = time.ElapsedMilliseconds; }
    }

    private static async Task<long> ObserveDelayCompletionAsync(Stopwatch elapsed, CancellationToken token)
    {
        await Task.Delay(100, token).ConfigureAwait(false);
        // Includes timer and background-continuation scheduling, not just the timer's due time.
        return elapsed.ElapsedMilliseconds;
    }

    private static JsonObject? OnlyReceiptOrNull(JsonNode state) => state["receipts"] is JsonArray { Count: 1 } items ? items[0] as JsonObject : null;
    private static JsonObject OnlyReceipt(JsonNode state) => OnlyReceiptOrNull(state)
        ?? throw new PestoException("qualification.coexistence.receipt", "Le scénario n’a pas produit le reçu fictif attendu.");
    private static bool Ready(JsonObject value, string mode) => Flag(value, "ready") && Text(value, "mode") == mode;
    private static bool HasDemoBanner(JsonObject value) => Flag(value, "bannerVisible")
        && Text(value, "bannerText").Contains("DÉMONSTRATION", StringComparison.Ordinal)
        && Text(value, "bannerText").Contains("AD, SMB ou HTTP", StringComparison.Ordinal);
    private static bool Flag(JsonNode? node, string key) => node?[key]?.GetValue<bool>() == true;
    private static string Text(JsonNode? node, string key) => node?[key]?.GetValue<string>() ?? "";
    private static int Number(JsonNode? node, string key) => node?[key]?.GetValue<int>() ?? -1;
    private static void Require(bool condition, string code)
    {
        if (!condition) throw new PestoException("qualification.coexistence." + code, "Une preuve obligatoire du parcours isolé manque.");
    }

    private sealed class DemoOnlyHost(NativeHostActions native) : IPestoHostActions, IPestoOfflineJoinHost
    {
        private int demoOpens, forbidden;
        public int DemoOpens => Volatile.Read(ref demoOpens);
        public int ForbiddenInvocations => Volatile.Read(ref forbidden);
        public async Task<object?> OpenDemoAsync(CancellationToken token)
        {
            var result = await native.OpenDemoAsync(token).ConfigureAwait(false);
            Interlocked.Increment(ref demoOpens);
            return result;
        }
        private Task<T> Refused<T>()
        {
            Interlocked.Increment(ref forbidden);
            throw new PestoException("qualification.isolation", "Le banc n’autorise aucune action hôte réelle.");
        }
        public Task<string?> ReadImportAsync(string kind, CancellationToken token) => Refused<string?>();
        public Task<string?> SaveExportAsync(string name, string text, CancellationToken token) => Refused<string?>();
        public Task<string?> SelectPackSourceAsync(string kind, CancellationToken token) => Refused<string?>();
        public Task<object?> ReconnectAsync(CancellationToken token) => Refused<object?>();
        public Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken token) => Refused<object?>();
        public Task<object?> OpenOfflineJoinAsync(CancellationToken token) => Refused<object?>();
        public Task<string?> SelectOfflineJoinBlobAsync(CancellationToken token) => Refused<string?>();
    }

    private sealed class DeniedCoordinationAccess : ISharedCoordinationAccess
    {
        public int Invocations { get; private set; }
        public T Run<T>(Func<T> operation)
        {
            Invocations++;
            throw new PestoException("qualification.isolation", "Aucun accès au partage n’est autorisé dans le banc.");
        }
    }
}

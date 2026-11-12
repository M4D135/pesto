using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Security.Principal;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>Same executable, separate launch paths. These run before profile initialization, UAC, credentials or AD.</summary>
internal static class MaintenanceHost
{
    public static bool TryRun(string[] args, out int result)
    {
        result = 0;
        if (args.Length > 0 && args[0] == "--health-check")
        {
            result = RunHealth(args); return true;
        }
        if (args.Length == 2 && args[0] == "--qualify-demo")
        {
            result = RunDemoQualification(args[1]); return true;
        }
        if (args.Length == 2 && args[0] == "--qualify-login")
        {
            result = NativeLoginQualification.Run(args[1]); return true;
        }
        if (args.Length == 2 && args[0] == "--qualify-configuration")
        {
            result = NativeConfigurationQualification.Run(args[1]); return true;
        }
        if (args.Length == 2 && args[0] == "--qualify-update-ui")
        {
            result = NativeUpdateUiQualification.Run(args[1]); return true;
        }
        if (args.Length == 2 && args[0] == "--update-helper")
        {
            result = RunHelper(args[1]); return true;
        }
        if (args.Length == 0 && string.Equals(Path.GetFileName(AppPaths.AppDirectory.TrimEnd(Path.DirectorySeparatorChar)), "helper", StringComparison.OrdinalIgnoreCase))
        {
            var directory = Path.GetDirectoryName(AppPaths.AppDirectory.TrimEnd(Path.DirectorySeparatorChar))!;
            if (!File.Exists(Path.Combine(directory, "transaction.json"))) return false;
            UpdateTransaction.ValidateHelperInvocation(directory, Environment.ProcessPath!);
            var answer = MessageBox.Show("Reprendre la transaction de mise à jour interrompue ? Pesto vérifiera les fichiers et rétablira la sauvegarde si nécessaire. Aucun paramètre utilisateur ni opération AD ne sera modifié.",
                "Pesto — Reprise de mise à jour", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            result = answer == DialogResult.Yes ? RunHelper(directory) : 0;
            return true;
        }
        return false;
    }

    private static int RunHelper(string transactionDirectory)
    {
        UpdateTransaction.ValidateHelperInvocation(transactionDirectory, Environment.ProcessPath!);
        using (var identity = WindowsIdentity.GetCurrent())
        {
            if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
            {
                var elevated = new ProcessStartInfo(Environment.ProcessPath!)
                {
                    UseShellExecute = true, Verb = "runas", WorkingDirectory = AppPaths.AppDirectory
                };
                elevated.ArgumentList.Add("--update-helper"); elevated.ArgumentList.Add(Path.GetFullPath(transactionDirectory));
                try { using var child = Process.Start(elevated) ?? throw new PestoException("update.helper", "Windows n’a pas pu ouvrir la reprise élevée."); }
                catch (System.ComponentModel.Win32Exception error) when (error.NativeErrorCode == 1223) { return 0; }
                catch (System.ComponentModel.Win32Exception)
                { throw new PestoException("update.helper", "Windows n’a pas autorisé la reprise élevée. Les fichiers et le journal sont conservés."); }
                return 0;
            }
        }
        using var diagnostics = UpdateHelperDiagnostics.Start(transactionDirectory);
        diagnostics.Record("helperValidated");
        try
        {
            var installation = UpdateTransaction.ReadInstallationDirectory(transactionDirectory);
            diagnostics.Record("waitingForParent");
            var result = UpdateTransaction.ExecuteAsync(transactionDirectory, StartHealthAsync,
                beforeReplacement: async token =>
                {
                    diagnostics.Record("parentReleased");
                    diagnostics.Record("waitingForPackProcesses");
                    await WaitForPackProcessesAsync(installation, token).ConfigureAwait(false);
                    diagnostics.Record("readyForExecuteCore");
                }).GetAwaiter().GetResult();
            diagnostics.Record("result", result.Status);
            MessageBox.Show(result.Message, "Pesto — Mise à jour", MessageBoxButtons.OK,
                result.Status is "completed" or "rolledBack" or "cancelled" ? MessageBoxIcon.Information : MessageBoxIcon.Warning);
            diagnostics.Record("resultDialogClosed", result.Status);
            return result.Status is "completed" or "rolledBack" or "cancelled" ? 0 : 3;
        }
        catch (Exception error)
        {
            diagnostics.Record("exception", error: error);
            throw;
        }
    }

    private static int RunHealth(string[] args)
    {
        if (args.Length != 6 || args[2] != "--health-token" || args[4] != "--health-transaction"
            || !Regex.IsMatch(args[3], "^[0-9a-f]{64}$") || !Regex.IsMatch(args[5], "^[0-9a-f]{32}$"))
            throw new PestoException("health.args", "La demande de contrôle de santé n’est pas liée à une transaction valide.");
        var output = Path.GetFullPath(args[1]);
        var transaction = Path.GetDirectoryName(output)!;
        if (Path.GetFileName(output) != "health.json" || Path.GetFileName(transaction) != args[5])
            throw new PestoException("health.args", "Destination du contrôle de santé invalide.");
        OperatorProfile.RejectLinks(output);
        if (!string.Equals(Path.TrimEndingDirectorySeparator(UpdateTransaction.ReadInstallationDirectory(transaction)),
            Path.TrimEndingDirectorySeparator(AppPaths.AppDirectory), StringComparison.OrdinalIgnoreCase))
            throw new PestoException("health.identity", "Ce contrôle de santé ne concerne pas cette installation.");
        // The destination is now bound to the active transaction. Every later failure has a durable
        // negative proof; maintenance never opens a modal error dialogue in an unattended check.
        UpdatePackageInfo? package = null;
        var executableHash = "";
        var isolatedRoot = Path.Combine(Path.GetTempPath(), "Pesto-health-" + Guid.NewGuid().ToString("N"));
        var probe = new ProbeResult(false, false, "health.not-started");
        try
        {
            package = UpdatePackage.Validate(AppPaths.AppDirectory);
            AppPaths.RequirePortableFiles();
            HostPolicy.ClearBrowserOverrides();
            executableHash = UpdatePackage.Hash(Path.Combine(AppPaths.AppDirectory, "Pesto.exe"));
            probe = RunProbe(PestoBackend.CreateSimulation(), package.Channel, isolatedRoot);
        }
        catch (Exception error) { probe = new(false, false, FailureCode(error)); }
        finally { RemoveIsolatedProfile(isolatedRoot); }
        var success = probe.Ready && probe.Closed && probe.FailureCode is null;
        WriteProof(output, new JsonObject
        {
            ["schemaVersion"] = 1, ["transactionId"] = args[5], ["nonce"] = args[3],
            ["version"] = package?.Version ?? "", ["executableSha256"] = executableHash,
            ["webViewReady"] = probe.Ready, ["closeReturned"] = probe.Closed,
            ["failureCode"] = probe.FailureCode, ["success"] = success
        });
        return success ? 0 : 3;
    }

    private static async Task<bool> StartHealthAsync(string installation, string output, string nonce, CancellationToken cancellationToken)
    {
        var start = new ProcessStartInfo(Path.Combine(installation, "Pesto.exe")) { UseShellExecute = false, WorkingDirectory = installation };
        foreach (var argument in new[] { "--health-check", output, "--health-token", nonce, "--health-transaction", Path.GetFileName(Path.GetDirectoryName(output))! })
            start.ArgumentList.Add(argument);
        using var process = Process.Start(start) ?? throw new PestoException("health.start", "Le programme installé n’a pas démarré.");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(75));
        try
        {
            await process.WaitForExitAsync(timeout.Token).ConfigureAwait(false);
            var success = process.ExitCode == 0;
            // Disposing a WebView2 controller is asynchronous at the browser-process level. Its loaded runtime
            // files must be released before ExecuteAsync can rename the candidate during a possible rollback.
            await WaitForPackProcessesAsync(installation, CancellationToken.None).ConfigureAwait(false);
            return success;
        }
        catch (OperationCanceledException)
        {
            // Only the health process created here and its children; never an unrelated user's session.
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
            await process.WaitForExitAsync(CancellationToken.None).ConfigureAwait(false);
            await WaitForPackProcessesAsync(installation, CancellationToken.None).ConfigureAwait(false);
            return false;
        }
    }

    private static int RunDemoQualification(string reportDirectory)
    {
        var output = Path.TrimEndingDirectorySeparator(Path.GetFullPath(reportDirectory));
        var temporaryRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar;
        if (!output.StartsWith(temporaryRoot, StringComparison.OrdinalIgnoreCase) || output.Length <= temporaryRoot.Length)
            throw new PestoException("qualification.path", "La qualification démo exige un nouveau sous-dossier temporaire dédié.");
        OperatorProfile.RejectLinks(output);
        if (Directory.Exists(output) || File.Exists(output)) throw new PestoException("qualification.path", "Le dossier de preuve existe déjà ; il n’est jamais écrasé.");
        Directory.CreateDirectory(output);
        var isolated = Path.Combine(output, "browser-profile");
        var forbiddenProfile = Path.Combine(output, "must-not-create-real-profile");
        var sentinel = new QualificationHostActions();
        UpdatePackageInfo? package = null;
        var executableHash = ""; string? runtimeHash = null, runtimePath = null, runtimeSource = null;
        var denied = 0;
        var probe = new ProbeResult(false, false, "qualification.not-started");
        var coexistence = DemoCoexistenceQualification.NotStarted();
        DemoProfileCleanup.Result cleanup;
        try
        {
            package = UpdatePackage.Validate(AppPaths.AppDirectory);
            AppPaths.RequirePortableFiles();
            HostPolicy.ClearBrowserOverrides();
            executableHash = UpdatePackage.Hash(Path.Combine(AppPaths.AppDirectory, "Pesto.exe"));
            runtimePath = AppPaths.WebViewRuntime; runtimeSource = AppPaths.RuntimeSource;
            if (runtimePath is not null) runtimeHash = UpdatePackage.Hash(Path.Combine(runtimePath, "msedgewebview2.exe"));
            using var updates = new UpdateService(new(AppPaths.AppDirectory, forbiddenProfile, package.Channel, true));
            var configuration = new ProfileConfigurationService(forbiddenProfile, "qualification-isolated", ConfigurationAccessMode.Demo);
            using var backend = new ApplicationServicesBackend(PestoBackend.CreateSimulation(), true, configuration, updates, sentinel, AppPaths.AppDirectory);
            foreach (var operation in new[] { "updates.status", "updates.windows", "updates.inspect", "updates.prepare", "updates.install", "updates.rollback", "updates.recover",
                "configuration.status", "configuration.settings", "configuration.export", "configuration.previewImport", "configuration.previewSettings", "configuration.applyImport",
                "configuration.decideDistribution", "configuration.setDefault", "references.preview", "references.apply", "host.reconnect", "demo.open",
                "coordination.status", "coordination.inspect", "coordination.prepare", "coordination.apply",
                "reservations.list", "reservations.inspect", "reservations.prepare", "reservations.execute",
                "join.precreated.preview", "receipts.prepareAcknowledgement", "receipts.acknowledge", "receipts.prepareRestart", "receipts.restart",
                "attributes.inspect", "attributes.prepare", "attributes.apply", "attributes.observe",
                "offlineJoin.open", "offlineJoin.list", "offlineJoin.import", "offlineJoin.prepare", "offlineJoin.apply", "offlineJoin.observe" })
            {
                try
                {
                    _ = backend.InvokeAsync(operation, PestoJson.Element(new { source = @"\\example.invalid\never-read", confirmed = true })).GetAwaiter().GetResult();
                    throw new PestoException("qualification.isolation", "Une API réelle a été admise dans la démonstration : " + operation);
                }
                catch (PestoException error) when (error.Code == "demo.isolated") { denied++; }
            }
            try { _ = configuration.Export("qualification"); throw new PestoException("qualification.isolation", "Le service de configuration admet un export en mode démo."); }
            catch (PestoException error) when (error.Code == "config.isolated") { denied++; }
            probe = RunProbe(backend, package.Channel, isolated);
            if (probe.Ready && probe.Closed && probe.FailureCode is null)
                coexistence = DemoCoexistenceQualification.Run(output, package.Channel);
        }
        catch (Exception error) { probe = probe with { FailureCode = FailureCode(error) }; }
        finally { cleanup = DemoProfileCleanup.Run(output); }
        var profilesRemoved = cleanup.Removed;
        var success = probe.Ready && probe.Closed && probe.FailureCode is null && denied == 43 && sentinel.Invocations == 0
            && !Directory.Exists(forbiddenProfile) && coexistence["success"]?.GetValue<bool>() == true && profilesRemoved;
        WriteProof(Path.Combine(output, "proof.json"), new JsonObject
        {
            ["schemaVersion"] = 1, ["kind"] = "pesto.windows-demo-qualification", ["utc"] = DateTimeOffset.UtcNow.ToString("O"),
            ["version"] = package?.Version ?? "", ["channel"] = package?.Channel ?? "", ["distribution"] = package?.Distribution ?? "",
            ["executableSha256"] = executableHash, ["runtimePath"] = runtimePath, ["runtimeSha256"] = runtimeHash,
            ["runtimeMode"] = package?.WebView2Runtime, ["runtimeSource"] = runtimeSource, ["browserVersion"] = probe.BrowserVersion,
            ["windowsVersion"] = Environment.OSVersion.VersionString, ["ready"] = probe.Ready, ["closeReturned"] = probe.Closed,
            ["blockedDirectApis"] = denied, ["hostInvocations"] = sentinel.Invocations, ["realProfileCreated"] = Directory.Exists(forbiddenProfile),
            ["coexistence"] = coexistence, ["temporaryProfilesRemoved"] = profilesRemoved, ["profileCleanup"] = cleanup.ToJson(),
            ["failureCode"] = probe.FailureCode ?? coexistence["failureCode"]?.GetValue<string>() ?? (profilesRemoved ? null : "qualification.profile-cleanup"),
            ["success"] = success, ["adQualification"] = false, ["binaryUpdateQualification"] = false
        });
        return success ? 0 : 3;
    }

    private sealed record ProbeResult(bool Ready, bool Closed, string? FailureCode, string? BrowserVersion = null);

    private static ProbeResult RunProbe(IPestoBackend backend, string channel, string isolatedRoot)
    {
        var ready = false; var closed = false; string? failure = null, browserVersion = null;
        ThreadExceptionEventHandler threadFailure = (_, _) => { failure = "maintenance.ui"; Application.Exit(); };
        Application.ThreadException += threadFailure;
        try
        {
            using (var form = new MainForm(backend, true, false, channel, isolatedRoot, healthProbe: true))
            using (var watchdog = new System.Windows.Forms.Timer { Interval = 45000 })
            {
                watchdog.Tick += (_, _) => { failure = "maintenance.timeout"; watchdog.Stop(); form.Close(); };
                watchdog.Start();
                Application.Run(form);
                browserVersion = form.LoadedBrowserVersion;
                ready = form.InterfaceReady && !form.StartFailed && failure is null;
                if (!ready) failure ??= "maintenance.webview";
            }
            // Set only after normal form disposal; the helper separately waits for browser processes.
            closed = true;
        }
        catch (Exception error) { failure = FailureCode(error); }
        finally { Application.ThreadException -= threadFailure; }
        return new(ready, closed, failure, browserVersion);
    }

    private static string FailureCode(Exception error) => error is PestoException pesto ? pesto.Code : "maintenance.failure";

    private static void RemoveIsolatedProfile(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, true); }
        catch (IOException) { } // A browser child can briefly retain its disposable, isolated profile.
        catch (UnauthorizedAccessException) { }
    }

    private static void WriteProof(string path, JsonObject proof)
    {
        OperatorProfile.RejectLinks(path);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { JsonSerializer.Serialize(stream, proof, new JsonSerializerOptions { WriteIndented = true }); stream.Flush(true); }
            OperatorProfile.RejectLinks(path);
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private sealed class QualificationHostActions : IPestoHostActions, IPestoOfflineJoinHost
    {
        public int Invocations { get; private set; }
        private Task<T> Refused<T>() { Invocations++; throw new PestoException("qualification.isolation", "Une action hôte réelle a été atteinte pendant la qualification démo."); }
        public Task<string?> ReadImportAsync(string kind, CancellationToken cancellationToken) => Refused<string?>();
        public Task<string?> SaveExportAsync(string suggestedName, string text, CancellationToken cancellationToken) => Refused<string?>();
        public Task<string?> SelectPackSourceAsync(string kind, CancellationToken cancellationToken) => Refused<string?>();
        public Task<object?> OpenDemoAsync(CancellationToken cancellationToken) => Refused<object?>();
        public Task<object?> OpenOfflineJoinAsync(CancellationToken cancellationToken) => Refused<object?>();
        public Task<string?> SelectOfflineJoinBlobAsync(CancellationToken cancellationToken) => Refused<string?>();
        public Task<object?> ReconnectAsync(CancellationToken cancellationToken) => Refused<object?>();
        public Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken cancellationToken) => Refused<object?>();
    }

    private static async Task WaitForPackProcessesAsync(string installation, CancellationToken cancellationToken)
    {
        var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(installation)) + Path.DirectorySeparatorChar;
        for (var attempt = 0; attempt < 60; attempt++)
        {
            var busy = false;
            foreach (var name in new[] { "Pesto", "msedgewebview2" })
            foreach (var process in Process.GetProcessesByName(name))
            using (process)
            {
                if (process.Id == Environment.ProcessId) continue;
                try
                {
                    if (process.HasExited) continue;
                    var path = process.MainModule?.FileName;
                    if (path is null) throw new PestoException("update.running", "L’identité d’un processus Pesto/WebView2 actif n’a pas pu être vérifiée.");
                    if (path.StartsWith(root, StringComparison.OrdinalIgnoreCase)) busy = true;
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception)
                { throw new PestoException("update.running", "Une autre session Pesto/WebView2 ne peut pas être inspectée. Fermez les instances de ce pack avant de reprendre."); }
            }
            if (!busy) return;
            await Task.Delay(500, cancellationToken).ConfigureAwait(false);
        }
        throw new PestoException("update.running", "Des processus utilisent encore ce pack. Aucun fichier n’a été remplacé ; fermez-les puis reprenez la transaction.");
    }
}

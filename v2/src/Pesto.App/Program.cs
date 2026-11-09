using Pesto.Core;
using Pesto.Engine;
using Pesto.Engine.Live;
using System.Text.Json;
using System.Diagnostics;
using System.Security.Principal;

namespace Pesto.App;

internal static class Program
{
    internal static Exception? UiFailure { get; private set; }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Contains("--cli", StringComparer.Ordinal)) return CliHost.Run(args);
        ApplicationConfiguration.Initialize();
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        var failed = false;
        var unattendedMaintenance = args.FirstOrDefault() is "--health-check" or "--qualify-demo" or "--qualify-configuration" or "--qualify-update-ui" or "--qualify-login";
        Application.ThreadException += (_, error) =>
        {
            failed = true;
            UiFailure ??= error.Exception;
            // A hidden health/smoke window must finish with a failed proof/exit code, never a blocking dialog.
            if (!unattendedMaintenance)
                ShowFatal("Pesto a rencontré une erreur inattendue. Fermez puis relancez l’application.");
            Application.Exit();
        };
        try
        {
            // Maintenance is a separate entry point: never initialize or replace a real configuration here.
            if (MaintenanceHost.TryRun(args, out var maintenanceResult)) return failed ? 2 : maintenanceResult;
            var (profile, normalArguments) = OperatorProfile.Resolve(args);
            if (normalArguments.FirstOrDefault() == "--offline-join")
            {
                if (ResumeInterruptedUpdate(profile, normalArguments)) return 0;
                return OfflineJoinHost.Run(profile, normalArguments);
            }
            // Selecting the native adapter never sends a mutation: every action still requires a fresh confirmed plan.
            var launch = HostWiring.Parse(normalArguments);
            var channel = AppPaths.Channel;
            var harness = launch.Wiring.IsQualificationHarness;
            // An interrupted binary transaction must be settled before the default-configuration lifecycle runs.
            if (!launch.Simulation && ResumeInterruptedUpdate(profile, normalArguments)) return 0;
            AppPaths.RequirePortableFiles();
            HostPolicy.ClearBrowserOverrides();
            var dataRoot = AppPaths.UserData(channel, launch.Simulation, harness, profile.LocalData);
            if (StartupPolicy.NeedsElevation(launch.Simulation, launch.SettingsOnly, WindowsElevation.IsElevated()))
            {
                // As in V1, Windows asks for UAC at once. Only the pack is checked first: no window, configuration
                // import, credential request or AD backend exists before the operator consents.
                UpdatePackage.Validate(AppPaths.AppDirectory);
                var relayArguments = normalArguments.Concat(new[] { "--operator-sid", profile.Sid }).ToArray();
                var code = StartupPolicy.Elevate(() => WindowsElevation.Start(relayArguments), ElevationRetryDialog.Ask);
                return failed ? 2 : code;
            }
            ProfileConfigurationService? configuration = null;
            var configured = false;
            var configurationOnly = launch.SettingsOnly;
            if (!launch.Simulation)
            {
                configuration = new(dataRoot, profile.Sid, ConfigurationAccessMode.Live);
                // Only --v1-root explicitly imports a legacy configuration; the original installation is untouched.
                var configurationStatus = configuration.Initialize(AppPaths.DistributedConfiguration, launch.V1Root);
                configured = configurationStatus["configured"]?.GetValue<bool>() == true;
                configurationOnly |= !configured;
                if (configured && !configurationOnly)
                {
                    launch = launch with { V1Root = dataRoot,
                        Wiring = HostWiring.Select(new HostWiringRequest(false, harness,
                            harness ? HostWiring.AdapterPs51 : null, harness ? HostWiring.ConfirmationPhrase : null, true, true)) };
                }
            }
            WindowsAdCredentialSource? acquired = null;
            var loginTheme = launch.Simulation ? null : new LoginThemePreference(dataRoot);
            if (!launch.Simulation && !configurationOnly && configured && launch.Wiring.AdapterId is not null)
            {
                // Joined Windows starts with the effective UAC identity. A second account chooser is explicit,
                // through Reconnect / Change account; a workgroup machine still requires native AD credentials.
                var authentication = HostAuthentication.Select(WindowsAutomationSupport.ReadDomainJoined(), launch.ChooseAccount);
                if (authentication != HostAuthenticationMode.Windows)
                {
                    using var login = new LoginForm(authentication != HostAuthenticationMode.ExplicitAd, LoginPalette.ForWindows(loginTheme!.Read()));
                    if (login.ShowDialog() == DialogResult.OK) acquired = login.TakeCredential();
                    else configurationOnly = true;
                }
            }
            NativeHostActions host;
            bool startFailed;
            using (var credentials = acquired)
            using (var directory = !launch.Simulation && !configurationOnly && configured
                ? PowerShellDirectoryGateway.ForInteractiveReads(credentials, launch.V1Root) : null)
            {
                var business = launch.Simulation
                    ? PestoBackend.CreateSimulation()
                    : configurationOnly || !configured ? PestoBackend.CreateConfigurationOnly(dataRoot)
                    : launch.Wiring.AdapterId is null
                        ? PestoBackend.CreateLive(launch.V1Root, directory!)
                        : PestoBackend.CreateLive(launch.V1Root, directory!,
                            new PowerShellMutationGateway(launch.V1Root, credentials));
                host = new NativeHostActions(profile, channel, harness);
                var updates = launch.Simulation ? null : new UpdateService(new UpdateServiceOptions(
                    AppPaths.AppDirectory, Path.Combine(dataRoot, "Updates"), channel, false));
                var coordination = launch.Simulation || configurationOnly || configuration is null ? null
                    : new SharedCoordinationAdministration(configuration.ConfigurationPath, SharedCoordinationAccessMode.Live,
                        new WindowsCoordinationAccess(credentials));
                var backend = new ApplicationServicesBackend(business, launch.Simulation, configuration, updates, host, AppPaths.AppDirectory, coordination);
                using var form = new MainForm(backend, launch.Simulation, harness, channel, dataRoot,
                    initialPage: !launch.Simulation && (configurationOnly || !configured) ? "parametres" : "accueil",
                    configurationOnly: !launch.Simulation && (configurationOnly || !configured), loginTheme: loginTheme);
                host.Owner = form;
                var windowHandle = form.Handle;
                credentials?.SetOwner(() => windowHandle);
                Application.Run(form);
                startFailed = form.StartFailed;
            }
            if (failed || startFailed) return 2;
            if (host.PendingUpdate is { } update)
            {
                using var helper = UpdateHostHandoff.Start(update);
            }
            else if (host.RestartRequested)
                StartProcess(Environment.ProcessPath!, host.RestartArguments(), AppPaths.AppDirectory);
            return 0;
        }
        catch (Exception error) when (error is ArgumentException or IOException or UnauthorizedAccessException or InvalidOperationException or JsonException or PestoException or System.ComponentModel.Win32Exception)
        {
            // Only our validation messages are useful to the operator; no paths, account names or stacks.
            var message = error is ArgumentException or FileNotFoundException or PestoException
                ? error.Message
                : "Pesto ne peut pas démarrer. Vérifiez le pack portable et l’accès à votre dossier de données local.";
            if (unattendedMaintenance) Console.Error.WriteLine("Pesto v2 : " + message);
            else ShowFatal(message);
            return 2;
        }
    }

    private static bool ResumeInterruptedUpdate(OperatorProfile profile, string[] normalArguments)
    {
        var pending = UpdateTransaction.List(AppPaths.AppDirectory).FirstOrDefault(t => t.Status is not ("completed" or "rolledBack" or "cancelled"));
        if (pending is null) return false;
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
        {
            var elevated = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = true, Verb = "runas", WorkingDirectory = AppPaths.AppDirectory };
            foreach (var argument in normalArguments) elevated.ArgumentList.Add(argument);
            elevated.ArgumentList.Add("--operator-sid"); elevated.ArgumentList.Add(profile.Sid);
            try { using var child = Process.Start(elevated); }
            catch (System.ComponentModel.Win32Exception error) when (error.NativeErrorCode == 1223) { }
            return true;
        }
        var answer = MessageBox.Show("Une mise à jour a été interrompue. Reprendre maintenant pour vérifier et rétablir les fichiers ? La configuration de votre profil ne sera ni importée ni remplacée pendant cette reprise.",
            "Pesto — Mise à jour interrompue", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
        if (answer == DialogResult.Yes)
        {
            var request = UpdateTransaction.RequestRollback(pending.TransactionDirectory, recovery: true);
            using var helper = UpdateHostHandoff.Start(request);
        }
        return true;
    }

    private static void StartProcess(string executable, IReadOnlyList<string> args, string workingDirectory)
    {
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, WorkingDirectory = workingDirectory };
        foreach (var argument in args) start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new PestoException("host.start", "Le programme n’a pas pu être relancé. La demande reste conservée pour reprise.");
    }

    private static void ShowFatal(string message)
    {
        if (Environment.UserInteractive)
        {
            MessageBox.Show(message, "Pesto v2", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        Console.Error.WriteLine("Pesto v2 : " + message);
    }
}

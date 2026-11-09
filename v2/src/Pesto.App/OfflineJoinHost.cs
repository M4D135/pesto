using System.Diagnostics;
using System.Security.Principal;
using Pesto.Core;
using Pesto.Engine;
using Pesto.Engine.Live;

namespace Pesto.App;

/// <summary>Same executable, local startup. No normal backend, credential prompt, DC discovery or dashboard.</summary>
internal static class OfflineJoinHost
{
    public static int Run(OperatorProfile profile, string[] arguments)
    {
        if (arguments.Length != 1 || arguments[0] != "--offline-join")
            throw new PestoException("offlineJoin.arguments", "La jonction hors ligne accepte uniquement --offline-join et le profil Windows d’origine.");
        using var identity = WindowsIdentity.GetCurrent();
        if (!new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator))
        {
            var start = new ProcessStartInfo(Environment.ProcessPath!)
            { UseShellExecute = true, Verb = "runas", WorkingDirectory = AppPaths.AppDirectory };
            start.ArgumentList.Add("--offline-join"); start.ArgumentList.Add("--operator-sid"); start.ArgumentList.Add(profile.Sid);
            try { using var child = Process.Start(start) ?? throw new PestoException("offlineJoin.start", "La fenêtre locale n’a pas pu être ouverte."); }
            catch (System.ComponentModel.Win32Exception error) when (error.NativeErrorCode == 1223) { }
            return 0;
        }
        AppPaths.RequirePortableFiles(); HostPolicy.ClearBrowserOverrides();
        var channel = AppPaths.Channel;
        var root = AppPaths.UserData(channel, false, false, profile.LocalData);
        OperatorProfile.RejectLinks(root);
        // Only a genuinely new profile receives the distributed local defaults. Existing bytes are untouched.
        if (!File.Exists(Path.Combine(root, "cfg.json")))
            new ProfileConfigurationService(root, profile.Sid, ConfigurationAccessMode.Live).Initialize(AppPaths.DistributedConfiguration);
        var host = new NativeHostActions(profile, channel, false);
        using var form = CreateWindow(profile, channel, false, host);
        host.Owner = form;
        Application.Run(form);
        return form.StartFailed ? 2 : 0;
    }

    public static MainForm CreateWindow(OperatorProfile profile, string channel, bool qualification, NativeHostActions host)
    {
        var root = AppPaths.UserData(channel, false, qualification, profile.LocalData);
        OperatorProfile.RejectLinks(root);
        var gpRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "GP");
        var path = Path.Combine(root, "cfg.json");
        var service = new OfflineJoinService(path, gpRoot, ConfigurationAccessMode.Live, new WindowsOfflineJoinPlatform(path, gpRoot));
        using var identity = WindowsIdentity.GetCurrent();
        var backend = new OfflineJoinBackend(service, host, identity.Name);
        return new MainForm(backend, false, qualification, channel,
            Path.Combine(root, "OfflineJoinUI", Guid.NewGuid().ToString("N")), initialPage: "offline-join", localOfflineJoin: true);
    }
}

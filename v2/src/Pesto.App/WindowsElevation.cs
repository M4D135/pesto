using System.Diagnostics;
using System.Security.Principal;

namespace Pesto.App;

internal static class WindowsElevation
{
    internal static bool IsElevated()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }
    internal static string AccountName() { using var identity = WindowsIdentity.GetCurrent(); return identity.Name; }
    internal static int Start(IReadOnlyList<string> arguments)
    {
        // Arguments are supplied only by native startup/qualification code, never by the web channel.
        var start = new ProcessStartInfo(Environment.ProcessPath ?? throw new InvalidOperationException("Exécutable Pesto introuvable."))
        { UseShellExecute = true, Verb = "runas", WorkingDirectory = AppPaths.AppDirectory };
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        using var child = Process.Start(start) ?? throw new IOException("Windows n’a pas lancé Pesto.");
        return child.Id;
    }
}

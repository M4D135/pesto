using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>Other Pesto.exe processes of this pack, identified like the update helper does. Closing is the
/// window's own close request; nothing is killed and no other process name is considered.</summary>
internal sealed class PackProcessSource(string installation) : IPackProcessSource
{
    private readonly string root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(installation)) + Path.DirectorySeparatorChar;

    public IReadOnlyList<PackProcess> List()
    {
        var result = new List<PackProcess>();
        using var current = Process.GetCurrentProcess();
        var currentSession = current.SessionId;

        foreach (var process in Process.GetProcessesByName("Pesto"))
        using (process)
        {
            try
            {
                if (process.Id == Environment.ProcessId) continue;
                if (process.HasExited) continue;

                long startTicks;
                string? path;
                try
                {
                    startTicks = process.StartTime.ToUniversalTime().Ticks;
                    path = process.MainModule?.FileName;
                }
                catch (InvalidOperationException)
                {
                    continue;
                }
                catch (Win32Exception)
                {
                    result.Add(new PackProcess(process.Id, 0, $"Pesto (processus {process.Id})", "elle ne peut pas être inspectée depuis cette fenêtre"));
                    continue;
                }

                if (path is null)
                {
                    result.Add(new PackProcess(process.Id, startTicks, Label(process), "son identité n’a pas pu être vérifiée"));
                    continue;
                }

                if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;

                string? blocker = null;
                if (process.SessionId != currentSession) blocker = "ouverte dans une autre session Windows";
                else if (process.MainWindowHandle == IntPtr.Zero) blocker = "sans fenêtre : commande en ligne ou démarrage en cours";
                else if (!IsWindowEnabled(process.MainWindowHandle)) blocker = "une boîte de dialogue Windows y est ouverte";

                result.Add(new PackProcess(process.Id, startTicks, Label(process), blocker));
            }
            catch (InvalidOperationException) { }
            catch (Win32Exception)
            {
                result.Add(new PackProcess(process.Id, 0, $"Pesto (processus {process.Id})", "elle ne peut pas être inspectée depuis cette fenêtre"));
            }
        }

        return result;
    }

    // Identity (start time and pack path) is checked on the same Process object just before the close request:
    // a reused identifier is never asked to close.
    // CloseMainWindow posts nothing to a window disabled by a Windows dialog and then returns false.
    public bool RequestClose(PackProcess process)
    {
        try
        {
            using var candidate = Process.GetProcessById(process.Id);
            return Identify(candidate, process) == Identity.Confirmed && candidate.CloseMainWindow();
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
        catch (Win32Exception) { return false; }
    }

    // A process that cannot be inspected any more is never reported closed without proof.
    public bool HasExited(PackProcess process)
    {
        try
        {
            using var candidate = Process.GetProcessById(process.Id);
            return Identify(candidate, process) is Identity.Missing or Identity.Other;
        }
        catch (ArgumentException) { return true; }
        catch (InvalidOperationException) { return true; }
        catch (Win32Exception) { return false; }
    }

    private static string Label(Process process)
    {
        var title = process.MainWindowTitle.Trim();
        return (title.Length == 0 ? "Pesto" : title) + $" (processus {process.Id})";
    }

    private enum Identity { Confirmed, Missing, Other, Uninspectable }

    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(nint window);

    private Identity Identify(Process candidate, PackProcess process)
    {
        if (process.StartTicks == 0) return Identity.Uninspectable;
        try
        {
            if (candidate.HasExited) return Identity.Missing;
            if (candidate.StartTime.ToUniversalTime().Ticks != process.StartTicks) return Identity.Other;
            var path = candidate.MainModule?.FileName;
            if (path is null) return Identity.Uninspectable;
            return path.StartsWith(root, StringComparison.OrdinalIgnoreCase) ? Identity.Confirmed : Identity.Other;
        }
        catch (InvalidOperationException) { return Identity.Missing; }
        catch (Win32Exception) { return Identity.Uninspectable; }
    }
}

using System.Diagnostics;
using Pesto.Core;
using Pesto.Engine;

namespace Pesto.App;

/// <summary>The normal host and isolated UI qualification use the same post-window helper launch.</summary>
internal static class UpdateHostHandoff
{
    // The caller must finish Application.Run and dispose its window before this handoff. The helper
    // independently validates the transaction, waits for the recorded parent and drains pack processes.
    internal static Process Start(UpdateInstallRequest request)
    {
        var start = new ProcessStartInfo(request.HelperExecutable)
        {
            UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(request.HelperExecutable)!
        };
        start.ArgumentList.Add("--update-helper");
        start.ArgumentList.Add(request.TransactionDirectory);
        return Process.Start(start) ?? throw new PestoException("host.start",
            "Le programme n’a pas pu être relancé. La demande reste conservée pour reprise.");
    }
}

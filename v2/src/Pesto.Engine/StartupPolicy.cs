using System.ComponentModel;

namespace Pesto.Engine;

/// <summary>Ordinary startup asks Windows for UAC at once, as in V1: no window, configuration, credential or AD backend
/// exists before consent. A cancelled or failed request offers Retry/Close; nothing is retried without the operator.</summary>
public static class StartupPolicy
{
    public const string CancelledMessage = "L’autorisation Windows a été annulée. Pesto a besoin des droits administrateur pour s’ouvrir.";
    public const string FailedMessage = "Windows n’a pas pu ouvrir Pesto comme administrateur.";

    public static bool NeedsElevation(bool simulation, bool settingsOnly, bool elevated) => !simulation && !settingsOnly && !elevated;

    /// <summary>Starts the elevated relay, asking again only when the operator chooses Retry. Returns 0 once the relay
    /// started or after closing a cancelled request, 2 after closing a failed one.</summary>
    public static int Elevate(Action start, Func<string, bool> retry)
    {
        while (true)
        {
            try { start(); return 0; }
            catch (Win32Exception error) when (error.NativeErrorCode == 1223)
            {
                if (!retry(CancelledMessage)) return 0;
            }
            catch (Exception error) when (error is Win32Exception or IOException or UnauthorizedAccessException or InvalidOperationException)
            {
                if (!retry(FailedMessage)) return 2;
            }
        }
    }
}

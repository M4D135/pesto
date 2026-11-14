namespace Pesto.App;

/// <summary>One local origin, no remote content and no privilege supplied by the page.</summary>
internal static class HostPolicy
{
    public const string Host = "pesto.local";
    public const string StartAddress = "https://pesto.local/index.html";
    public const int MaximumMessageLength = 1024 * 1024;
    public const int MaximumPendingMessages = 32;

    public static bool IsInterfaceAddress(string? address) =>
        Uri.TryCreate(address, UriKind.Absolute, out var uri)
        && uri.Scheme == Uri.UriSchemeHttps
        && string.Equals(uri.IdnHost, Host, StringComparison.OrdinalIgnoreCase)
        && uri.Port == 443
        && uri.UserInfo.Length == 0;

    public static bool IsAllowedResource(string? address) => IsInterfaceAddress(address)
        || (Uri.TryCreate(address, UriKind.Absolute, out var uri) && uri.Scheme == "data");

    /// <summary>Never inherit browser debugging, a different runtime or another mode's profile.</summary>
    public static void ClearBrowserOverrides()
    {
        foreach (var name in new[]
        {
            "WEBVIEW2_BROWSER_EXECUTABLE_FOLDER", "WEBVIEW2_USER_DATA_FOLDER",
            "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "WEBVIEW2_RELEASE_CHANNEL_PREFERENCE",
            "WEBVIEW2_RELEASE_CHANNELS", "WEBVIEW2_CHANNEL_SEARCH_KIND",
            "WEBVIEW2_PIPE_FOR_SCRIPT_DEBUGGER", "WEBVIEW2_WAIT_FOR_SCRIPT_DEBUGGER"
        })
        {
            Environment.SetEnvironmentVariable(name, null);
        }
    }
}

// Launch argument parsing and the production/qualification wiring decision moved to Pesto.Engine.HostWiring
// (constat 5 de la revue 24/10) so the refusals and permissions of the connection are testable on fixtures.

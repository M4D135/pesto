using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Pesto.Engine;

namespace Pesto.App;

internal static class AppPaths
{
    // One engine choice per process: the installed Evergreen runtime first, then the exact Socle in wad\runtime\webview2.
    private static readonly Lazy<(string? Folder, string Source)> runtime = new(ResolveRuntime);
    public static string AppDirectory => AppContext.BaseDirectory;
    public static string WebRoot => Path.Combine(AppDirectory, "wad", "web");
    /// <summary>Null selects the installed Evergreen runtime; otherwise the verified Socle folder.</summary>
    public static string? WebViewRuntime => runtime.Value.Folder;
    public static string RuntimeSource => runtime.Value.Source;
    public static string? RuntimeSourceIfResolved => runtime.IsValueCreated ? runtime.Value.Source : null;
    private static (string? Folder, string Source) ResolveRuntime()
    {
        var manifest = Path.Combine(AppDirectory, "wad", "Pesto.package.json");
        if (File.Exists(manifest))
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(manifest));
            var info = doc.RootElement;
            if (info.GetProperty("webview2Runtime").GetString() != "evergreen" || info.TryGetProperty("webview2Version", out _))
                throw new InvalidDataException("Le mode WebView2 ne correspond pas à ce pack Pesto.");
        }
        HostPolicy.ClearBrowserOverrides();
        try
        {
            if (!string.IsNullOrWhiteSpace(CoreWebView2Environment.GetAvailableBrowserVersionString(null, new CoreWebView2EnvironmentOptions { ReleaseChannels = CoreWebView2ReleaseChannels.Stable }))) return (null, "evergreen");
        }
        catch (WebView2RuntimeNotFoundException) { }
        var (state, problem) = SocleRuntime.Inspect(AppDirectory, false);
        if (state == SocleState.Valid) return (Path.Combine(AppDirectory, "wad", "runtime", "webview2"), "socle");
        throw new FileNotFoundException(state == SocleState.Absent ? SocleRuntime.MissingMessage : SocleRuntime.InvalidMessage(problem ?? "état inconnu"));
    }
    public static string DistributedConfiguration => Path.Combine(AppDirectory, "wad", "defaults", "configuration.json");

    public static string Channel
    {
        get
        {
            var file = Path.Combine(AppDirectory, "wad", "Pesto.package.json");
            if (!File.Exists(file)) return "DEV";
            using var doc = JsonDocument.Parse(File.ReadAllText(file));
            var channel = doc.RootElement.GetProperty("channel").GetString();
            return channel is "DEV" or "PROD" ? channel : throw new InvalidDataException("Canal du pack invalide.");
        }
    }

    public static string UserData(string channel, bool simulation, bool qualification, string? operatorLocalData = null,
        string? demoInstance = null)
    {
        var root = operatorLocalData ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (!Path.IsPathFullyQualified(root))
        {
            throw new InvalidOperationException("Windows ne fournit pas de dossier de données local pour ce compte.");
        }
        // Le harnais de qualification n'a jamais le même profil de données que le mode réel courant.
        var modeRoot = Path.Combine(root, "Pesto", "v2", channel, simulation ? "Simulation" : qualification ? "Qualification" : "Live");
        return simulation ? Path.Combine(modeRoot, demoInstance ?? Guid.NewGuid().ToString("N")) : modeRoot;
    }

    public static void RequirePortableFiles()
    {
        if (!File.Exists(Path.Combine(WebRoot, "index.html")))
        {
            throw new FileNotFoundException("L’interface locale wad\\web\\index.html manque. Relancez Pesto depuis le pack complet.");
        }
        _ = WebViewRuntime;
    }
}

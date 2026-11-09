using Microsoft.Web.WebView2.Core;
using Pesto.Core;
using System.Text.Json.Nodes;

namespace Pesto.App;

internal sealed partial class MainForm
{
    // These controls are not part of the bridge, a browser host object or ordinary startup. Only the
    // native qualification runner can enable them, and only on its newly created temporary profiles.
    private DemoQualificationScope? qualificationScope;

    internal void EnableQualification(DemoQualificationScope scope)
    {
        scope.RequireOwned(profile);
        if (qualificationScope is not null && qualificationScope != scope)
            throw new PestoException("qualification.scope", "La fenêtre appartient déjà à un autre banc isolé.");
        qualificationScope = scope;
    }

    internal string QualificationProfile
    {
        get { RequireQualification(); return Path.GetFullPath(profile); }
    }

    internal bool QualificationClosing { get { RequireQualification(); return closing; } }

    // Counters and fixed states only: no request, response, profile value or credential enters a proof.
    internal JsonObject QualificationWindowState()
    {
        RequireQualification();
        if (InvokeRequired) throw new PestoException("qualification.thread", "Le contrôle WebView doit rester sur son fil d’interface.");
        return new JsonObject
        {
            ["visible"] = Visible, ["webViewVisible"] = webView.Visible,
            ["active"] = ActiveForm == this, ["containsFocus"] = ContainsFocus,
            ["minimized"] = WindowState == FormWindowState.Minimized,
            ["coreCreated"] = webView.CoreWebView2 is not null,
            ["pendingBridgeRequests"] = inFlight.Count, ["startFailed"] = StartFailed,
            ["closing"] = closing, ["disposed"] = IsDisposed,
            // Where this window's own rendering process spent its start-up time, and whether the page ever navigated.
            ["webViewEnvironmentMilliseconds"] = WebViewEnvironmentMilliseconds,
            ["webViewCoreMilliseconds"] = WebViewCoreMilliseconds,
            ["webViewProcessFailures"] = WebViewProcessFailures,
            ["webViewNavigated"] = WebViewNavigated,
            ["browserVersion"] = LoadedBrowserVersion, ["runtimeSource"] = AppPaths.RuntimeSourceIfResolved,
        };
    }

    internal Task<string> QualificationStepAsync(DemoQualificationStep step)
        => ExecuteQualificationStepAsync(DemoQualificationScripts.For(step), step is DemoQualificationStep.Snapshot or DemoQualificationStep.CaptureSnapshot);

    internal Task<string> QualificationStepAsync(ConfigurationQualificationStep step)
        => ExecuteQualificationStepAsync(ConfigurationQualificationScripts.For(step), step == ConfigurationQualificationStep.Snapshot);

    internal Task<string> QualificationStepAsync(UpdateUiQualificationStep step)
        => ExecuteQualificationStepAsync(UpdateUiQualificationScripts.For(step), step == UpdateUiQualificationStep.Snapshot);

    private Task<string> ExecuteQualificationStepAsync(string compiledScript, bool snapshot)
    {
        RequireQualification();
        if (InvokeRequired) throw new PestoException("qualification.thread", "Le contrôle WebView doit rester sur son fil d’interface.");
        if (closing || IsDisposed) throw new PestoException("qualification.closed", "La fenêtre s’est fermée avant la fin du contrôle.");
        if (webView.CoreWebView2 is null)
        {
            if (snapshot) return Task.FromResult("null");
            throw new PestoException("qualification.webview", "Le moteur WebView n’est pas prêt.");
        }
        // The runner selects one compiled step. Neither the command line nor the page supplies JavaScript.
        return webView.CoreWebView2.ExecuteScriptAsync(compiledScript);
    }

    internal async Task QualificationCaptureAsync(string name)
    {
        var scope = RequireQualification();
        if (name is not ("parent-draft.png" or "demo-pending.png" or "demo-restarted.png" or "parent-preserved.png"
            or "configuration-export.png" or "configuration-import-preview.png" or "configuration-default-confirmation.png"
            or "configuration-custom-pack.png" or "maintenance-prepared.png" or "maintenance-install-confirmation.png"))
            throw new PestoException("qualification.capture", "Nom de capture de qualification inconnu.");
        if (InvokeRequired || closing || IsDisposed || webView.CoreWebView2 is null)
            throw new PestoException("qualification.capture", "La fenêtre n’est pas disponible pour une capture.");
        var destination = Path.Combine(scope.Root, name);
        scope.RequireOwned(destination);
        using var bytes = new MemoryStream();
        await webView.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, bytes);
        if (bytes.Length is < 100 or > 32 * 1024 * 1024)
            throw new PestoException("qualification.capture", "La capture WebView est absente ou dépasse la borne prévue.");
        scope.RequireOwned(destination);
        using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        bytes.Position = 0;
        bytes.CopyTo(output);
        output.Flush(true);
    }

    private DemoQualificationScope RequireQualification()
    {
        var scope = qualificationScope ?? throw new PestoException("qualification.scope", "Cette fenêtre n’appartient pas au banc isolé.");
        scope.RequireOwned(profile);
        return scope;
    }
}

using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Pesto.Bridge;
using Pesto.Core;

namespace Pesto.App;

/// <summary>Local HTML surface. The only native capability exposed is the closed bridge contract.</summary>
internal sealed partial class MainForm : Form
{
    private readonly WebView2 webView = new() { Dock = DockStyle.Fill };
    private readonly BridgeDispatcher dispatcher;
    private readonly IPestoBackend backend;
    private readonly CancellationTokenSource lifetime = new();
    private readonly ConcurrentDictionary<int, Task> inFlight = new();
    private readonly string profile;
    private readonly bool healthProbe;
    private readonly string initialPage;
    private readonly bool configurationOnly;
    private readonly LoginThemePreference? loginTheme;
    private bool closing;
    private bool drained;
    private int resourcesDisposed;

    public bool StartFailed { get; private set; }
    public bool InterfaceReady { get; private set; }

    public MainForm(IPestoBackend backend, bool simulation, bool qualification, string channel, string? dataRoot = null, bool healthProbe = false, string initialPage = "accueil", bool localOfflineJoin = false, bool configurationOnly = false, LoginThemePreference? loginTheme = null)
    {
        ArgumentNullException.ThrowIfNull(backend);
        this.backend = backend;
        dispatcher = new BridgeDispatcher(backend);
        profile = Path.Combine(dataRoot ?? AppPaths.UserData(channel, simulation, qualification), "WebView2");
        this.healthProbe = healthProbe;
        this.initialPage = initialPage;
        this.configurationOnly = configurationOnly;
        this.loginTheme = simulation || healthProbe || localOfflineJoin ? null : loginTheme;
        Text = $"Pesto v2 — {channel}" + (simulation ? " — Simulation" : localOfflineJoin ? " — Jonction hors ligne locale" : qualification ? " — Annuaire · Qualification" : " — Annuaire");
        Icon = ApplicationBrand.CreateWindowIcon();
        MinimumSize = new Size(1024, 680);
        Size = new Size(1440, 900);
        StartPosition = FormStartPosition.CenterScreen;
        if (healthProbe) { ShowInTaskbar = false; Opacity = 0; }
        Controls.Add(webView);
        Load += async (_, _) => await InitializeWebViewAsync();
        FormClosing += OnFormClosing;
    }

    internal string? LoadedBrowserVersion { get; private set; }

    // Startup cost of this window's own WebView2 profile. Two windows never share a profile, so each
    // one pays for its browser process; the qualification proof must say where the time went.
    internal long WebViewEnvironmentMilliseconds { get; private set; }
    internal long WebViewCoreMilliseconds { get; private set; }
    internal int WebViewProcessFailures { get; private set; }
    internal bool WebViewNavigated { get; private set; }

    private async Task InitializeWebViewAsync()
    {
        try
        {
            Directory.CreateDirectory(profile);
            var options = new CoreWebView2EnvironmentOptions
            {
                AreBrowserExtensionsEnabled = false,
                ReleaseChannels = CoreWebView2ReleaseChannels.Stable,
                AdditionalBrowserArguments = "--disable-background-networking --disable-component-update --disable-sync --no-first-run"
            };
            var environmentWatch = Stopwatch.StartNew();
            // Null selects the installed Evergreen runtime; otherwise the verified Socle folder (one choice per process).
            var environment = await CoreWebView2Environment.CreateAsync(AppPaths.WebViewRuntime, profile, options)
                .WaitAsync(lifetime.Token);
            WebViewEnvironmentMilliseconds = environmentWatch.ElapsedMilliseconds;
            LoadedBrowserVersion = environment.BrowserVersionString;
            var coreWatch = Stopwatch.StartNew();
            await webView.EnsureCoreWebView2Async(environment).WaitAsync(lifetime.Token);
            WebViewCoreMilliseconds = coreWatch.ElapsedMilliseconds;
            if (closing) return;
            var core = webView.CoreWebView2;
            core.Settings.AreDevToolsEnabled = false;
            core.Settings.AreDefaultContextMenusEnabled = false;
            core.Settings.AreBrowserAcceleratorKeysEnabled = false;
            core.Settings.AreHostObjectsAllowed = false;
            core.Settings.IsWebMessageEnabled = true;
            core.Settings.IsStatusBarEnabled = false;
            core.Settings.IsGeneralAutofillEnabled = false;
            core.Settings.IsPasswordAutosaveEnabled = false;
            core.Settings.IsReputationCheckingRequired = false;
            core.SetVirtualHostNameToFolderMapping(HostPolicy.Host, AppPaths.WebRoot, CoreWebView2HostResourceAccessKind.Deny);
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All, CoreWebView2WebResourceRequestSourceKinds.All);
            core.WebResourceRequested += (_, e) =>
            {
                if (!HostPolicy.IsAllowedResource(e.Request.Uri))
                {
                    e.Response = environment.CreateWebResourceResponse(null, 403, "Forbidden", "");
                }
            };
            core.NavigationStarting += (_, e) => e.Cancel = !HostPolicy.IsInterfaceAddress(e.Uri);
            // Pesto has no framed screens, popups, downloads or web authentication providers.
            core.FrameNavigationStarting += (_, e) => e.Cancel = true;
            core.NewWindowRequested += (_, e) => e.Handled = true;
            core.DownloadStarting += (_, e) => e.Cancel = true;
            core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
            core.BasicAuthenticationRequested += (_, e) => e.Cancel = true;
            core.ClientCertificateRequested += (_, e) => e.Cancel = true;
            core.ServerCertificateErrorDetected += (_, e) => e.Action = CoreWebView2ServerCertificateErrorAction.Cancel;
            core.ProcessFailed += (_, _) =>
            {
                WebViewProcessFailures += 1;
                ShowFallback("Le moteur d’affichage s’est arrêté. Relancez Pesto ; aucune opération n’est relancée automatiquement.");
            };
            core.NavigationCompleted += (_, e) => { if (e.IsSuccess) WebViewNavigated = true; };
            core.WebMessageReceived += OnWebMessageReceived;
            if (healthProbe) core.NavigationCompleted += async (_, e) =>
            {
                if (e.IsSuccess) await ProbeInterfaceAsync();
                else { StartFailed = true; Close(); }
            };
            core.Navigate(HostPolicy.StartAddress + (configurationOnly ? "?configuration=local" : "") + "#/" + initialPage);
        }
        catch (OperationCanceledException) when (closing) { }
        catch (Exception error) when (error is COMException or InvalidOperationException or ArgumentException or IOException or UnauthorizedAccessException)
        {
            ShowFallback("L’affichage local de Pesto n’a pas pu démarrer. Vérifiez WebView2 Evergreen ou le pack WebView2 du Socle extrait dans wad\\, et l’accès à votre dossier de données local.");
        }
    }

    private async Task ProbeInterfaceAsync()
    {
        try
        {
            // The real shell, CSS, ES modules, bridge and in-memory backend must all finish initialization.
            for (var attempt = 0; attempt < 120 && !closing; attempt++)
            {
                var ready = await webView.CoreWebView2.ExecuteScriptAsync(
                    "Boolean(document.documentElement.dataset.ready && document.querySelector('main h1') && document.querySelector('.mode-chip[data-mode=\"simulation\"]') && !document.querySelector('main .error-card'))");
                if (ready == "true") { InterfaceReady = true; Close(); return; }
                await Task.Delay(250, lifetime.Token);
            }
            if (!closing) { StartFailed = true; Close(); }
        }
        catch (OperationCanceledException) when (closing) { }
        catch (Exception error) when (error is COMException or InvalidOperationException)
        { StartFailed = true; if (!closing) Close(); }
    }

    private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        if (closing || !HostPolicy.IsInterfaceAddress(e.Source)) return;
        var json = e.WebMessageAsJson;
        var decision = BridgeAdmission.Classify(json, inFlight.Count);
        if (decision != BridgeAdmission.Decision.Accepted)
        {
            // No native dispatch for oversized messages or a page that floods the bridge, but the call
            // must still settle: an unanswered request leaves the screen busy and never ready.
            var refusal = BridgeAdmission.CorrelatedRefusal(json, decision);
            if (refusal is not null) PostToPage(refusal);
            return;
        }
        var token = lifetime.Token;
        var task = Task.Run(async () =>
        {
            try
            {
                var response = await dispatcher.DispatchAsync(json, token).ConfigureAwait(false);
                PostToPage(response);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { }
            catch (Exception)
            {
                // Dispatcher normally supplies a safe correlated error. Unexpected native exceptions never expose data.
                ShowUnexpectedBridgeFailure();
            }
        }, CancellationToken.None);
        inFlight[task.Id] = task;
        _ = task.ContinueWith(t => inFlight.TryRemove(t.Id, out _), CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    }

    private void PostToPage(string json)
    {
        if (closing || IsDisposed || !IsHandleCreated) return;
        try
        {
            BeginInvoke(() =>
            {
                if (!closing && !IsDisposed && webView.CoreWebView2 is not null)
                {
                    webView.CoreWebView2.PostWebMessageAsJson(json);
                }
            });
        }
        catch (InvalidOperationException) { } // The window closed between the checks and BeginInvoke.
    }

    private void ShowUnexpectedBridgeFailure()
    {
        if (closing || IsDisposed || !IsHandleCreated) return;
        try
        {
            BeginInvoke(() =>
            {
                if (!closing) ShowFallback("Une opération de l’interface s’est interrompue. Vérifiez son état avant de la relancer.");
            });
        }
        catch (InvalidOperationException) { }
    }

    private void ShowFallback(string message)
    {
        if (closing || IsDisposed) return;
        StartFailed = true;
        if (healthProbe) { Close(); return; }
        webView.Visible = false;
        Controls.Add(new Label
        {
            Dock = DockStyle.Fill, Text = message, TextAlign = ContentAlignment.MiddleCenter,
            Padding = new Padding(48), AutoSize = false
        });
    }

    private async void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (drained) return;
        e.Cancel = true;
        if (closing) return;
        closing = true;
        Text = "Pesto — Fermeture après la fin de l’opération et l’enregistrement du reçu";
        lifetime.Cancel();
        // An owned local ODJ window may already have cancelled the parent's first close while its
        // native request finishes. Keep this parent drain alive until every child has really closed.
        var tasks = inFlight.Values.Concat(OwnedForms.OfType<MainForm>().Select(CloseOwnedFormAsync)).ToArray();
        try
        {
            // The normal close (including Change account) completes before Program starts the new process.
            // Read just the selected theme from our own live shell. No new capability is exposed to the page.
            if (loginTheme is not null && webView.CoreWebView2 is { } core && HostPolicy.IsInterfaceAddress(core.Source))
            {
                try
                {
                    var json = await core.ExecuteScriptAsync("""
                        (() => {
                          if (!document.querySelector('.theme-switch')) return null;
                          try {
                            const raw = localStorage.getItem('pesto.prefs.v1#live') ?? localStorage.getItem('pesto.prefs.v1');
                            if (raw && raw.length <= 16384) {
                              const value = JSON.parse(raw)?.theme;
                              if (['light', 'dark', 'contrast', 'system'].includes(value)) return value;
                            }
                          } catch { /* Private storage: use the currently displayed preference. */ }
                          return document.documentElement.dataset.themePref ?? null;
                        })()
                        """)
                        .WaitAsync(TimeSpan.FromSeconds(1));
                    if (json.Length <= 10) loginTheme.Save(JsonSerializer.Deserialize<string>(json));
                }
                catch (Exception ex) when (ex is COMException or InvalidOperationException or TimeoutException or JsonException) { }
            }
            if (tasks.Length > 0) await Task.WhenAll(tasks);
        }
        catch (OperationCanceledException) { }
        finally
        {
            drained = true;
            // Close on the next UI turn: the original FormClosing event is still being cancelled.
            if (!IsDisposed && IsHandleCreated) BeginInvoke((Action)Close);
        }
    }

    private static Task CloseOwnedFormAsync(MainForm child)
    {
        if (child.IsDisposed) return Task.CompletedTask;
        var closed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        FormClosedEventHandler? handler = null;
        handler = (_, _) => { child.FormClosed -= handler; closed.TrySetResult(); };
        child.FormClosed += handler;
        child.Close();
        if (child.IsDisposed) { child.FormClosed -= handler; closed.TrySetResult(); }
        return closed.Task;
    }

    protected override void Dispose(bool disposing)
    {
        // WinForms closes/disposes the form; the host using declaration disposes it again.
        // CancellationTokenSource.Cancel after Dispose would turn a normal close into a startup error.
        if (disposing && Interlocked.Exchange(ref resourcesDisposed, 1) == 0)
        {
            lifetime.Cancel();
            webView.Dispose();
            // A timed-out operation still owns its backend; disposal must not race its receipt writes.
            if (inFlight.IsEmpty && backend is IDisposable disposable) disposable.Dispose();
            lifetime.Dispose();
        }
        base.Dispose(disposing);
    }
}

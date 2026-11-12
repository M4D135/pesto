namespace Pesto.App;

internal enum DemoQualificationStep
{
    Snapshot, CaptureSnapshot, SeedParent, OpenDemo, NavigateSettings, ReadBackend, SetChildPreferences, ReloadWithCompactBanner,
    SelectPendingRestart, SelectJoined, Reset, Restart, Confirm,
    // 2.0.15: opens the « Interface » section of the settings page, which holds the demonstration button.
    ShowInterface,
    // 2.0.15: opens « Annuaire » again, so the capture of the preserved parent shows its draft.
    ShowDirectory
}

/// <summary>Closed UI steps for the temporary native bench. No supplied script, path or native command.</summary>
internal static class DemoQualificationScripts
{
    // Two closed steps use one embedded function. The page and CLI cannot supply script text.
    private static readonly string SnapshotFunction = ReadSnapshotFunction();
    private static readonly string StateSnapshot = SnapshotFunction + "(false)";
    private static readonly string CaptureSnapshot = SnapshotFunction + "(true)";

    private static string ReadSnapshotFunction()
    {
        using var resource = typeof(DemoQualificationScripts).Assembly.GetManifestResourceStream("Pesto.Qualification.DemoSnapshot")
            ?? throw new InvalidOperationException("La sonde de qualification embarquée est absente.");
        using var reader = new StreamReader(resource);
        return reader.ReadToEnd().TrimEnd();
    }

    public static string For(DemoQualificationStep step) => step switch
    {
        DemoQualificationStep.Snapshot => StateSnapshot,
        DemoQualificationStep.CaptureSnapshot => CaptureSnapshot,
        DemoQualificationStep.SeedParent => """
            (() => {
              const fields = { domain: 'qualification.invalid', prefix: 'QF', rootOu: 'OU=Qualification,DC=qualification,DC=invalid' };
              if (!Object.keys(fields).every(k => document.querySelector(`[data-form="settings"] [name="${k}"]`))) return false;
              for (const [key, value] of Object.entries(fields)) {
                const field = document.querySelector(`[data-form="settings"] [name="${key}"]`);
                field.value = value; field.dispatchEvent(new Event('input', { bubbles: true }));
              }
              const sites = document.querySelector('textarea[name="sites"]');
              if (!sites) return false;
              sites.value = 'qualification;Site fictif;QF;OU=Qualification,DC=qualification,DC=invalid';
              sites.dispatchEvent(new Event('input', { bubbles: true }));
              const theme = document.querySelector('.theme-switch [data-set="dark"]');
              const toggle = document.querySelector('.nav-toggle');
              if (!theme || !toggle) return false;
              localStorage.setItem('pesto.native.qualification.parent', 'unsaved-parent-draft');
              theme.click();
              if (!document.querySelector('.shell.nav-collapsed')) toggle.click();
              return true;
            })()
            """,
        DemoQualificationStep.NavigateSettings => """
            (() => {
              if (location.hash.split('?')[0] === '#/parametres') return true;
              const link = document.querySelector('.nav-item[data-id="parametres"]');
              if (!link) return false;
              link.click(); return true;
            })()
            """,
        DemoQualificationStep.OpenDemo => """
            (() => {
              const button = document.querySelector('.demo-trigger');
              if (!button || button.disabled || button.hidden || document.querySelector('.shell')?.inert || !button.getClientRects().length) return false;
              button.click(); return true;
            })()
            """,
        // Same compiled rail click and proof as the configuration bench, refused while a dialog makes the shell inert.
        DemoQualificationStep.ShowInterface => """
            (() => {
              if (document.querySelector('.shell')?.inert) return false;
              return SHOW;
            })()
            """.Replace("SHOW", ConfigurationQualificationScripts.Show("interface"), StringComparison.Ordinal),
        DemoQualificationStep.ShowDirectory => """
            (() => {
              if (document.querySelector('.shell')?.inert) return false;
              return SHOW;
            })()
            """.Replace("SHOW", ConfigurationQualificationScripts.Show("annuaire"), StringComparison.Ordinal),
        DemoQualificationStep.ReadBackend => """
            (() => {
              globalThis.__pestoNativeQualification = { state: 'pending' };
              const failed = (step, reason, serverCode = null) => {
                const failure = { state: 'failed', step, reason };
                if (serverCode !== null) failure.serverCode = serverCode;
                globalThis.__pestoNativeQualification = failure;
              };
              if (!globalThis.window?.chrome?.webview) { failed('channel', 'unavailable'); return true; }
              // Do not depend on the referrer assigned to an evaluated script. Resolve the same fixed
              // module from this document, then pin its origin/path; never relax CSP or allow an external import.
              let moduleUrl;
              try { moduleUrl = new URL('js/bridge.js', document.baseURI); }
              catch { failed('module', 'origin'); return true; }
              if (moduleUrl.origin !== location.origin || moduleUrl.protocol !== 'https:' || moduleUrl.hostname !== 'pesto.local'
                  || moduleUrl.pathname !== '/js/bridge.js' || moduleUrl.search || moduleUrl.hash) {
                failed('module', 'origin'); return true;
              }
              let step = 'module';
              import(moduleUrl.href).then(async (module) => {
                step = 'export';
                if (typeof module.call !== 'function') { failed(step, 'invalid'); return; }
                step = 'session';
                const session = await module.call('session.info');
                if (!session || !['live', 'simulation'].includes(session.mode)) { failed(step, 'invalid'); return; }
                const result = { state: 'done', mode: session.mode, configurationOnly: session.configurationOnly === true,
                  readOnly: session.readOnly === true, domain: session.domain ?? null, dc: session.dc ?? null };
                if (session.mode === 'simulation') {
                  step = 'status';
                  result.demo = await module.call('demo.status');
                  if (result.demo?.mode !== 'simulation') { failed(step, 'invalid'); return; }
                  step = 'receipts';
                  const receipts = await module.call('receipts.list', {});
                  if (!Array.isArray(receipts?.items)) { failed(step, 'invalid'); return; }
                  result.receipts = receipts.items;
                }
                globalThis.__pestoNativeQualification = result;
              }).catch(error => {
                const reason = error?.code === 'bridge.timeout' ? 'timeout' : error?.code === 'bridge.closed' ? 'closed'
                  : error?.code === 'operation.failed' ? 'native-failed' : error?.code === 'operation.cancelled' ? 'cancelled'
                  : typeof error?.code === 'string' ? 'refused' : error?.name === 'TypeError' ? 'type-error' : 'error';
                const knownServerCodes = ['config.missing', 'config.invalid', 'config.changed', 'config.profile',
                  'directory.unavailable', 'host.closing', 'session.configurationOnly', 'demo.required', 'demo.isolated', 'demo.closed',
                  'operation.unknown', 'operation.busy', 'operation.failed', 'operation.cancelled',
                  'message.size', 'message.id', 'message.json', 'arguments.invalid', 'invalid_arguments', 'request.duplicate'];
                failed(step, reason, knownServerCodes.includes(error?.code) ? error.code : null);
              });
              return true;
            })()
            """,
        DemoQualificationStep.SetChildPreferences => """
            (() => {
              const theme = document.querySelector('.theme-switch [data-set="contrast"]');
              const toggle = document.querySelector('.nav-toggle');
              if (!theme || !toggle) return false;
              if (localStorage.getItem('pesto.native.qualification.parent') !== null) return false;
              localStorage.setItem('pesto.native.qualification.child', 'isolated-child');
              theme.click();
              if (!document.querySelector('.shell.nav-collapsed')) toggle.click();
              return true;
            })()
            """,
        DemoQualificationStep.ReloadWithCompactBanner => """
            (() => {
              for (const key of ['pesto.prefs.v1', 'pesto.prefs.v1#simulation']) {
                const raw = localStorage.getItem(key);
                if (!raw) return false;
                const preferences = JSON.parse(raw);
                preferences.bannerCompact = true;
                localStorage.setItem(key, JSON.stringify(preferences));
              }
              setTimeout(() => location.reload(), 0); return true;
            })()
            """,
        DemoQualificationStep.SelectPendingRestart => Scenario("pendingRestart"),
        DemoQualificationStep.SelectJoined => Scenario("joined"),
        DemoQualificationStep.Reset => DialogAction("reset"),
        DemoQualificationStep.Restart => DialogAction("restart"),
        DemoQualificationStep.Confirm => DialogAction("ok"),
        _ => throw new ArgumentOutOfRangeException(nameof(step))
    };

    // Both arguments below are selected exclusively by the enum switch, never by bridge or CLI input.
    private static string Scenario(string id) => """
        (() => {
          const dialog = [...document.querySelectorAll('.k-dlg-layer:not(.leaving) .k-dlg')].at(-1);
          const select = dialog?.querySelector('[name="demoScenario"]');
          const button = dialog?.querySelector('.k-dlg-foot [data-id="scenario"]');
          if (!select || !button || button.disabled || ![...select.options].some(o => o.value === 'SCENARIO')) return false;
          select.value = 'SCENARIO'; select.dispatchEvent(new Event('change', { bubbles: true }));
          button.click(); return true;
        })()
        """.Replace("SCENARIO", id, StringComparison.Ordinal);

    private static string DialogAction(string id) => """
        (() => {
          const dialog = [...document.querySelectorAll('.k-dlg-layer:not(.leaving) .k-dlg')].at(-1);
          const button = dialog?.querySelector('.k-dlg-foot [data-id="ACTION"]');
          if (!button || button.disabled) return false;
          button.click(); return true;
        })()
        """.Replace("ACTION", id, StringComparison.Ordinal);
}

namespace Pesto.App;

internal enum ConfigurationQualificationStep
{
    Snapshot, SetVersion, ChangePrefix, SaveSettings, ConfirmSettings,
    Export, Import, ConfirmImport, CancelImport, Default, ConfirmDefault, CancelDefault,
    UpdateFolder, PrepareUpdate, InstallUpdate, CancelInstall, UpdateStatus,
    // 2.0.15: the settings page shows one section at a time; these open the section of the next input or click.
    ShowDirectory, ShowConfiguration, ShowUpdates
}

/// <summary>Compiled DOM input and click steps. They never call the bridge or application services directly.</summary>
internal static class ConfigurationQualificationScripts
{
    internal const string Version = "native-ui-qualification";
    // Exact title of the confirmation opened by « Définir comme configuration par défaut » (web/js/pages/maintenance.js).
    internal const string DefaultTitle = "Définir comme configuration par défaut";

    public static string For(ConfigurationQualificationStep step) => step switch
    {
        ConfigurationQualificationStep.Snapshot => """
            (() => {
              const main = document.querySelector('main');
              const dialog = [...document.querySelectorAll('.k-dlg-layer:not(.leaving) .k-dlg')].at(-1);
              const button = selector => { const item = main?.querySelector(selector); return Boolean(item && !item.disabled && !item.hidden && !item.closest('[inert]')); };
              return {
                ready: document.documentElement.dataset.ready === 'parametres' && main?.dataset.page === 'parametres'
                  && Boolean(main.querySelector('[data-form="settings"]')) && !main.querySelector('.error-card, .skeleton'),
                mode: document.querySelector('.mode-chip')?.dataset.mode ?? '', route: location.hash,
                section: main?.querySelector('[data-section-panel]:not([hidden])')?.dataset.sectionPanel ?? '',
                prefix: main?.querySelector('[name="prefix"]')?.value ?? '',
                version: main?.querySelector('[name="configurationVersion"]')?.value ?? '',
                configurationState: main?.dataset.configurationState ?? '',
                settingsBusy: main?.querySelector('[data-settings-status]')?.getAttribute('aria-busy') === 'true',
                configurationStatus: main?.querySelector('[data-maint-status="configuration"]')?.textContent ?? '',
                updatesStatus: main?.querySelector('[data-maint-status="updates"]')?.textContent ?? '',
                buttonsReady: ['export', 'import', 'default', 'folder'].every(id => button(`[data-maint="${id}"]`)),
                saveEnabled: button('[data-act="save"]'),
                candidateCount: main?.querySelectorAll('[data-maint-zone="candidates"] [data-candidate]').length ?? 0,
                candidatesText: main?.querySelector('[data-maint-zone="candidates"]')?.textContent ?? '',
                preparedCount: main?.querySelectorAll('[data-maint-zone="prepared"] [data-install]').length ?? 0,
                preparedText: main?.querySelector('[data-maint-zone="prepared"]')?.textContent ?? '',
                notifications: document.querySelector('.toasts')?.textContent ?? '',
                finiteAnimationsRunning: document.getAnimations().some(a => a.playState === 'running' && Number.isFinite(a.effect?.getComputedTiming().endTime)),
                dialog: dialog ? {
                  title: dialog.querySelector('h2')?.textContent ?? '',
                  subtitle: dialog.querySelector('.k-dlg-sub')?.textContent ?? '',
                  body: dialog.querySelector('.k-dlg-body')?.textContent ?? '',
                  actions: [...dialog.querySelectorAll('.k-dlg-foot button:not([disabled])')].map(b => b.dataset.id),
                  labels: [...dialog.querySelectorAll('.k-dlg-foot button:not([disabled])')].map(b => b.textContent.trim())
                } : null
              };
            })()
            """,
        ConfigurationQualificationStep.SetVersion => Input("configurationVersion", Version),
        ConfigurationQualificationStep.ChangePrefix => Input("prefix", "222222"),
        ConfigurationQualificationStep.SaveSettings => Click("[data-act=\"save\"]"),
        ConfigurationQualificationStep.ConfirmSettings => Dialog("Enregistrer les paramètres", "apply"),
        ConfigurationQualificationStep.Export => Click("[data-maint=\"export\"]"),
        ConfigurationQualificationStep.Import => Click("[data-maint=\"import\"]"),
        ConfigurationQualificationStep.ConfirmImport => Dialog("Importer la configuration", "apply"),
        ConfigurationQualificationStep.CancelImport => Dialog("Importer la configuration", "cancel"),
        ConfigurationQualificationStep.Default => Click("[data-maint=\"default\"]"),
        ConfigurationQualificationStep.ConfirmDefault => Dialog(DefaultTitle, "ok"),
        ConfigurationQualificationStep.CancelDefault => Dialog(DefaultTitle, "cancel"),
        ConfigurationQualificationStep.UpdateFolder => Click("[data-maint=\"folder\"]"),
        ConfigurationQualificationStep.PrepareUpdate => Click("[data-maint-zone=\"candidates\"] [data-candidate]"),
        ConfigurationQualificationStep.InstallUpdate => Click("[data-maint-zone=\"prepared\"] [data-install]"),
        ConfigurationQualificationStep.CancelInstall => Dialog("Installer la mise à jour préparée", "cancel"),
        ConfigurationQualificationStep.UpdateStatus => Click("[data-maint=\"status\"]"),
        ConfigurationQualificationStep.ShowDirectory => Show("annuaire"),
        ConfigurationQualificationStep.ShowConfiguration => Show("configuration"),
        ConfigurationQualificationStep.ShowUpdates => Show("mises-a-jour"),
        _ => throw new ArgumentOutOfRangeException(nameof(step))
    };

    /// <summary>Address of the settings page: the bare default section (Annuaire) or one section named by the page itself.</summary>
    internal static bool IsSettingsRoute(string route) => route == "#/parametres"
        || (route.StartsWith("#/parametres?section=", StringComparison.Ordinal) && route.Length > 21
            && route[21..].All(c => c is >= 'a' and <= 'z' or '-'));

    // Clicks the rail item of one section, as a user would, then proves in the same evaluation that its panel is the
    // one shown, that the item is current and that the page wrote its address (Annuaire keeps the bare #/parametres).
    // A hidden field is never typed into: Input and Click below refuse an element without client rects.
    // The section is chosen only by the enum steps of this class and of DemoQualificationScripts.
    internal static string Show(string section) => """
        (() => {
          const items = document.querySelectorAll('main .pr-nav-item[data-section="SECTION"]');
          if (items.length !== 1) return false;
          const item = items[0];
          if (item.disabled || item.hidden || item.closest('[inert]') || !item.getClientRects().length) return false;
          item.focus(); item.click();
          const panel = document.querySelector('main [data-section-panel="SECTION"]');
          return Boolean(panel && !panel.hidden && panel.getClientRects().length && item.getAttribute('aria-current') === 'true'
            && location.hash === 'ADDRESS');
        })()
        """.Replace("SECTION", section, StringComparison.Ordinal)
        .Replace("ADDRESS", section == "annuaire" ? "#/parametres" : "#/parametres?section=" + section, StringComparison.Ordinal);

    // Values and selectors are chosen only by the enum above, never by the CLI, bridge or loaded page.
    private static string Input(string name, string value) => """
        (() => {
          const items = document.querySelectorAll('main [name="NAME"]');
          if (items.length !== 1) return false;
          const input = items[0];
          if (input.disabled || input.readOnly || input.hidden || input.closest('[inert]') || !input.getClientRects().length) return false;
          input.scrollIntoView({ block: 'center' }); input.focus();
          input.value = 'VALUE'; input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
          return input.value === 'VALUE';
        })()
        """.Replace("NAME", name, StringComparison.Ordinal).Replace("VALUE", value, StringComparison.Ordinal);

    private static string Click(string selector) => """
        (() => {
          const items = document.querySelectorAll('main SELECTOR');
          if (items.length !== 1) return false;
          const button = items[0];
          if (button.disabled || button.hidden || button.closest('[inert]') || !button.getClientRects().length) return false;
          button.scrollIntoView({ block: 'center' }); button.focus(); button.click(); return true;
        })()
        """.Replace("SELECTOR", selector, StringComparison.Ordinal);

    private static string Dialog(string title, string action) => """
        (() => {
          const dialogs = [...document.querySelectorAll('.k-dlg-layer:not(.leaving) .k-dlg')];
          if (dialogs.length !== 1) return false;
          const dialog = dialogs[0];
          if (dialog.querySelector('h2')?.textContent !== 'TITLE') return false;
          const button = dialog.querySelector('.k-dlg-foot [data-id="ACTION"]');
          if (!button || button.disabled || button.hidden || button.closest('[inert]') || !button.getClientRects().length) return false;
          button.focus(); button.click(); return true;
        })()
        """.Replace("TITLE", title, StringComparison.Ordinal).Replace("ACTION", action, StringComparison.Ordinal);
}

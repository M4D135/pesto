namespace Pesto.App;

internal enum UpdateUiQualificationStep
{
    Snapshot, UpdateZip, PrepareUpdate, InstallUpdate, CancelInstall, ConfirmInstall,
    // 2.0.15: opens the « Mises à jour » section of the settings page before its buttons are clicked.
    ShowUpdates
}

/// <summary>Closed DOM actions for the real maintenance page. No bridge/service invocation.</summary>
internal static class UpdateUiQualificationScripts
{
    internal static string For(UpdateUiQualificationStep step) => step switch
    {
        UpdateUiQualificationStep.Snapshot => ConfigurationQualificationScripts.For(ConfigurationQualificationStep.Snapshot),
        UpdateUiQualificationStep.PrepareUpdate => ConfigurationQualificationScripts.For(ConfigurationQualificationStep.PrepareUpdate),
        UpdateUiQualificationStep.InstallUpdate => ConfigurationQualificationScripts.For(ConfigurationQualificationStep.InstallUpdate),
        UpdateUiQualificationStep.CancelInstall => ConfigurationQualificationScripts.For(ConfigurationQualificationStep.CancelInstall),
        UpdateUiQualificationStep.UpdateZip => """
            (() => {
              const items = document.querySelectorAll('main [data-maint="zip"]');
              if (items.length !== 1) return false;
              const button = items[0];
              if (button.disabled || button.hidden || button.closest('[inert]') || !button.getClientRects().length) return false;
              button.scrollIntoView({ block: 'center' }); button.focus(); button.click(); return true;
            })()
            """,
        UpdateUiQualificationStep.ConfirmInstall => """
            (() => {
              const dialogs = [...document.querySelectorAll('.k-dlg-layer:not(.leaving) .k-dlg')];
              if (dialogs.length !== 1) return false;
              const dialog = dialogs[0];
              if (dialog.querySelector('h2')?.textContent !== 'Installer la mise à jour préparée') return false;
              const button = dialog.querySelector('.k-dlg-foot [data-id="ok"]');
              if (!button || button.disabled || button.hidden || button.closest('[inert]') || !button.getClientRects().length) return false;
              button.focus(); button.click(); return true;
            })()
            """,
        UpdateUiQualificationStep.ShowUpdates => ConfigurationQualificationScripts.For(ConfigurationQualificationStep.ShowUpdates),
        _ => throw new ArgumentOutOfRangeException(nameof(step))
    };
}

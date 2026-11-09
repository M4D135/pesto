namespace Pesto.App;

/// <summary>Native Retry/Close choice after a cancelled or failed UAC request. Nothing else is offered before consent.</summary>
internal static class ElevationRetryDialog
{
    internal static bool Ask(string message)
    {
        var retry = new TaskDialogButton("Réessayer");
        var close = new TaskDialogButton("Fermer");
        var page = new TaskDialogPage
        {
            Caption = "Pesto",
            Heading = "Pesto n’est pas ouvert",
            Text = message,
            Icon = TaskDialogIcon.Information,
            AllowCancel = true,
            Buttons = { retry, close },
            DefaultButton = retry,
        };
        return TaskDialog.ShowDialog(page, TaskDialogStartupLocation.CenterScreen) == retry;
    }
}

using System.Text.Json.Nodes;
using Pesto.Engine;

namespace Pesto.App;

internal sealed partial class NativeHostActions : IPestoOfflineJoinHost
{
    public Task<object?> OpenOfflineJoinAsync(CancellationToken cancellationToken) => OnUi<object?>(() =>
    {
        var localHost = new NativeHostActions(profile, channel, qualification);
        var form = OfflineJoinHost.CreateWindow(profile, channel, qualification, localHost);
        localHost.Owner = form;
        form.FormClosed += (_, _) => form.Dispose();
        form.Show(Owner);
        return new JsonObject { ["opened"] = true, ["localOnly"] = true, ["normalContextPreserved"] = true };
    }, cancellationToken);

    public Task<string?> SelectOfflineJoinBlobAsync(CancellationToken cancellationToken) => OnUi(() =>
    {
        using var picker = new OpenFileDialog
        {
            Title = "Importer un blob de jonction hors ligne pour le nom actuel de ce PC",
            Filter = "Blob de jonction (*.txt;*.blob)|*.txt;*.blob|Tous les fichiers (*.*)|*.*",
            CheckFileExists = true, Multiselect = false
        };
        return picker.ShowDialog(Owner) == DialogResult.OK ? picker.FileName : null;
    }, cancellationToken);
}

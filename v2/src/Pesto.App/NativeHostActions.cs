using Pesto.Core;
using Pesto.Engine;
using System.Text;
using System.Text.Json.Nodes;

namespace Pesto.App;

internal sealed partial class NativeHostActions(OperatorProfile profile, string channel, bool qualification) : IPestoHostActions, IPestoPackWindowsHost
{
    public MainForm? Owner { get; set; }
    public IPackProcessSource PackProcesses { get; } = new PackProcessSource(AppPaths.AppDirectory);
    public UpdateInstallRequest? PendingUpdate { get; private set; }
    public bool RestartRequested { get; private set; }
    private Action<string, string>? qualificationFileGuard;

    // Only the compiled temporary-profile bench can install this guard. Ordinary startup and the
    // bridge expose no path callback; selection remains entirely in the production Windows picker.
    internal void EnableQualificationFileGuard(DemoQualificationScope scope, Action<string, string> observeSelection)
    {
        scope.RequireOwned(profile.LocalData);
        if (qualificationFileGuard is not null)
            throw new PestoException("qualification.scope", "Le garde des fichiers du banc est déjà actif.");
        qualificationFileGuard = (action, path) =>
        {
            observeSelection(action, path); // Preserve the actual returned spelling even if admission fails.
            scope.RequireOwned(path);
        };
    }

    private Task<T> OnUi<T>(Func<T> action, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var form = Owner ?? throw new PestoException("host.unavailable", "La fenêtre Pesto n’est pas prête.");
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        if (form.IsDisposed || !form.IsHandleCreated) throw new PestoException("host.closed", "La fenêtre est fermée.");
        form.BeginInvoke(() =>
        {
            try { cancellationToken.ThrowIfCancellationRequested(); completion.SetResult(action()); }
            catch (Exception error) { completion.SetException(error); }
        });
        return completion.Task;
    }

    public async Task<string?> ReadImportAsync(string kind, CancellationToken cancellationToken)
    {
        var path = await OnUi(() =>
        {
            using var picker = new OpenFileDialog
            {
                Title = kind == "references" ? "Importer un référentiel sites/services" : "Importer une configuration Pesto",
                Filter = "Documents JSON (*.json)|*.json", CheckFileExists = true, Multiselect = false
            };
            return picker.ShowDialog(Owner) == DialogResult.OK ? picker.FileName : null;
        }, cancellationToken).ConfigureAwait(false);
        if (path is null) return null;
        qualificationFileGuard?.Invoke("import", path);
        // A selected UNC file can be slow. Only the picker belongs on the window's thread.
        return await Task.Run(() => ConfigurationDocument.ReadFile(path), cancellationToken).ConfigureAwait(false);
    }

    public async Task<string?> SaveExportAsync(string suggestedName, string text, CancellationToken cancellationToken)
    {
        var path = await OnUi(() =>
        {
            using var picker = new SaveFileDialog { Title = "Exporter les paramètres partageables", Filter = "Configuration JSON (*.json)|*.json", FileName = suggestedName, OverwritePrompt = true };
            return picker.ShowDialog(Owner) == DialogResult.OK ? picker.FileName : null;
        }, cancellationToken).ConfigureAwait(false);
        if (path is null) return null;
        qualificationFileGuard?.Invoke("export", path);
        return await Task.Run(() =>
        {
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    var bytes = new UTF8Encoding(false, true).GetBytes(text); output.Write(bytes); output.Flush(true);
                }
                cancellationToken.ThrowIfCancellationRequested();
                File.Move(temporary, path, true);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
            return path;
        }, cancellationToken).ConfigureAwait(false);
    }

    public Task<string?> SelectPackSourceAsync(string kind, CancellationToken cancellationToken) => OnUi(() =>
    {
        if (kind == "zip")
        {
            using var picker = new OpenFileDialog { Title = "Choisir un pack Pesto V2", Filter = "Pack ZIP (*.zip)|*.zip", CheckFileExists = true };
            if (picker.ShowDialog(Owner) != DialogResult.OK) return null;
            qualificationFileGuard?.Invoke("source", picker.FileName);
            return picker.FileName;
        }
        using var folder = new FolderBrowserDialog { Description = "Choisir le dossier du pack Pesto V2, local ou sur un partage UNC", UseDescriptionForTitle = true, ShowNewFolderButton = false };
        if (folder.ShowDialog(Owner) != DialogResult.OK) return null;
        qualificationFileGuard?.Invoke("source", folder.SelectedPath);
        return folder.SelectedPath;
    }, cancellationToken);

    public Task<object?> OpenDemoAsync(CancellationToken cancellationToken) => OnUi<object?>(() =>
    {
        var instance = Guid.NewGuid().ToString("N");
        var isolated = new ApplicationServicesBackend(PestoBackend.CreateSimulation(), true, null, null, this, AppPaths.AppDirectory);
        var demo = new MainForm(isolated, true, false, channel, AppPaths.UserData(channel, true, false, profile.LocalData, instance));
        demo.FormClosed += (_, _) => demo.Dispose();
        demo.Show(Owner);
        return new JsonObject { ["opened"] = true, ["isolated"] = true, ["instanceId"] = instance };
    }, cancellationToken);

    public Task<object?> ReconnectAsync(CancellationToken cancellationToken) => OnUi<object?>(() =>
    {
        RestartRequested = true; CloseAfterResponse();
        return new JsonObject { ["status"] = "closing", ["message"] = "Fermeture puis reconnexion avec la configuration du profil d’origine." };
    }, cancellationToken);

    public Task<object?> InstallAsync(UpdateInstallRequest request, CancellationToken cancellationToken) => OnUi<object?>(() =>
    {
        PendingUpdate = request; CloseAfterResponse();
        return new JsonObject { ["status"] = "closing", ["transactionId"] = request.TransactionId,
            ["message"] = "La fenêtre se ferme avant le remplacement. Le reçu transactionnel déterminera le résultat, jamais cette confirmation." };
    }, cancellationToken);

    private void CloseAfterResponse()
    {
        var timer = new System.Windows.Forms.Timer { Interval = 500 };
        timer.Tick += (_, _) => { timer.Stop(); timer.Dispose(); Owner?.Close(); };
        timer.Start();
    }

    public string[] RestartArguments()
    {
        var args = new List<string> { "--operator-sid", profile.Sid, "--choose-account" };
        if (qualification)
        {
            args.AddRange(["--v1-root", AppPaths.UserData(channel, false, true, profile.LocalData), "--qualification-harness",
                "--mutation-adapter", HostWiring.AdapterPs51, "--confirm-qualification", HostWiring.ConfirmationPhrase]);
        }
        return args.ToArray();
    }
}

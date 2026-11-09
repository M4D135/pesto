using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

public sealed record UpdateServiceOptions(string InstallationDirectory, string StateDirectory, string Channel, bool Simulation);
public sealed record UpdateInstallRequest(string TransactionDirectory, string HelperExecutable, string TransactionId, string Action);

/// <summary>Explicit local inspection, preparation, and handoff (folder, UNC share, or ZIP; no network source). Merely checking or preparing never replaces binaries.</summary>
public sealed class UpdateService : IDisposable
{
    private readonly UpdateServiceOptions options;
    private readonly Dictionary<string, Candidate> candidates = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Prepared> prepared = new(StringComparer.Ordinal);
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly object localGate = new();
    private readonly TimeProvider clock;
    private UpdateWorkspace? workspace;
    private bool disposed;

    public UpdateService(UpdateServiceOptions options, TimeProvider? clock = null)
    {
        this.options = options;
        this.clock = clock ?? TimeProvider.System;
    }

    public JsonObject InspectLocal(string source)
    {
        using var admission = Enter();
        if (string.IsNullOrWhiteSpace(source) || source.Any(char.IsControl) || !Path.IsPathFullyQualified(source))
            throw new PestoException("update.source", "Sélectionnez un dossier, un partage UNC ou une archive ZIP par son chemin absolu.");
        UpdatePackage.RequireNoLinks(source);
        var id = Guid.NewGuid().ToString("N");
        string? ownedInspection = null;
        try
        {
            string root;
            if (Directory.Exists(source)) root = ResolvePackRoot(source);
            else
            {
                if (!File.Exists(source) || !source.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                    throw new PestoException("update.source", "La source sélectionnée n’est ni un dossier ni une archive ZIP.");
                var inspection = Path.Combine(WorkspaceRoot(), "inspections", id);
                UpdatePackage.ExtractZip(source, inspection);
                // Ownership begins only after ExtractZip has created this fresh directory successfully.
                // Never clean the selected source, a pre-existing destination or another candidate.
                ownedInspection = inspection;
                root = ResolvePackRoot(inspection);
            }
            var info = UpdatePackage.Validate(root, options.Channel);
            var current = UpdatePackage.Validate(options.InstallationDirectory, options.Channel);
            ValidateUpgrade(current, info);
            lock (localGate) candidates[id] = new(id, "local", root, info.Version, info.Fingerprint, clock.GetUtcNow().AddMinutes(30), ownedInspection);
            return Describe(info, id, "candidateId", "local", "Source locale ou partage : intégrité vérifiée, origine officielle non attestée par un fichier manifeste.");
        }
        catch
        {
            if (ownedInspection is not null)
            {
                try
                {
                    UpdatePackage.RequireNoLinks(ownedInspection);
                    UpdatePackage.TryRemoveOwned(ownedInspection);
                }
                // Preserve the original inspection refusal if cleanup cannot safely resolve our directory.
                catch (Exception error) when (error is PestoException or IOException or UnauthorizedAccessException) { }
            }
            throw;
        }
    }

    public async Task<JsonObject> PrepareAsync(string candidateId, CancellationToken cancellationToken = default)
    {
        Guard();
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            Guard(); PruneExpired();
            Candidate candidate;
            lock (localGate)
            {
                if (!candidates.TryGetValue(candidateId, out candidate!) || candidate.ExpiresAt <= clock.GetUtcNow())
                    throw new PestoException("update.stale", "La sélection a expiré. Vérifiez de nouveau la source.");
            }
            var id = Guid.NewGuid().ToString("N");
            var directory = Path.Combine(WorkspaceRoot(), "prepared", id);
            var stage = Path.Combine(directory, "package");
            Directory.CreateDirectory(directory);
            try
            {
                var original = UpdatePackage.Validate(candidate.Path, options.Channel);
                if (original.Fingerprint != candidate.Fingerprint) throw new PestoException("update.changed", "Le pack a changé depuis l’aperçu. Inspectez-le à nouveau.");
                UpdatePackage.CopyToNew(candidate.Path, stage, candidate.Fingerprint);
                var info = UpdatePackage.Validate(stage, options.Channel);
                if (info.Version != candidate.Version)
                    throw new PestoException("update.changed", "Le pack préparé ne correspond pas à l’aperçu. Inspectez-le à nouveau.");
                var current = UpdatePackage.Validate(options.InstallationDirectory, options.Channel);
                ValidateUpgrade(current, info);
                var record = new Prepared(id, stage, info.Fingerprint, current.Fingerprint, clock.GetUtcNow().AddHours(2), candidate.Source);
                UpdatePackage.WriteJson(Path.Combine(directory, "prepared.json"), record);
                lock (localGate) prepared[id] = record;
                return Describe(info, id, "preparedId", candidate.Source, "Pack copié et revérifié. L’installation attend votre confirmation et fermera cette fenêtre.");
            }
            catch { UpdatePackage.TryRemoveOwned(directory); throw; }
        }
        finally { gate.Release(); }
    }

    public JsonObject Status()
    {
        using var admission = Enter();
        var current = UpdatePackage.Validate(options.InstallationDirectory, options.Channel);
        var transactions = UpdateTransaction.List(options.InstallationDirectory);
        var pending = transactions.FirstOrDefault(t => t.Status is not ("completed" or "rolledBack" or "cancelled"));
        var last = transactions.FirstOrDefault(t => t.Status == "completed" && Directory.Exists(Path.Combine(t.TransactionDirectory, "backup")));
        return new() { ["version"] = current.Version, ["channel"] = current.Channel, ["distribution"] = current.Distribution,
            ["fingerprint"] = current.Fingerprint, ["pendingRecovery"] = pending is not null, ["canRollback"] = last is not null,
            ["transactionId"] = pending?.Id ?? last?.Id, ["status"] = pending?.Status ?? last?.Status ?? "idle",
            ["configurationPreserved"] = true, ["message"] = pending is null ? "Les mises à jour remplacent uniquement les fichiers du pack." : "Une installation a été interrompue. Un retour transactionnel doit être confirmé avant une nouvelle mise à jour." };
    }

    public UpdateInstallRequest RequestInstall(string preparedId, bool confirmed)
    {
        using var admission = Enter(); Confirm(confirmed);
        lock (localGate)
        {
            if (!prepared.TryGetValue(preparedId, out var record) || record.ExpiresAt <= clock.GetUtcNow())
                throw new PestoException("update.stale", "La préparation a expiré. Préparez à nouveau la mise à jour.");
            var current = UpdatePackage.Validate(options.InstallationDirectory, options.Channel);
            if (current.Fingerprint != record.CurrentFingerprint) throw new PestoException("update.changed", "L’installation a changé depuis la préparation.");
            var next = UpdatePackage.Validate(record.Directory, options.Channel);
            if (next.Fingerprint != record.Fingerprint) throw new PestoException("update.changed", "Le pack préparé a changé. Aucun remplacement n’est autorisé.");
            var request = UpdateTransaction.Create(options.InstallationDirectory, record.Directory, current, next, "install");
            prepared.Remove(preparedId);
            // Create sealed its own stage on the installation volume; the preparation is now disposable.
            UpdateWorkspace.RemoveCopy(Path.GetDirectoryName(record.Directory)!);
            return request;
        }
    }

    public UpdateInstallRequest RequestRollback(bool confirmed)
    {
        using var admission = Enter(); Confirm(confirmed);
        var transaction = UpdateTransaction.List(options.InstallationDirectory).FirstOrDefault(t => t.Status == "completed")
            ?? throw new PestoException("update.rollback", "Aucune installation terminée ne dispose d’un retour disponible.");
        return UpdateTransaction.RequestRollback(transaction.TransactionDirectory, false);
    }

    public UpdateInstallRequest RequestRecovery(bool confirmed)
    {
        using var admission = Enter(); Confirm(confirmed);
        var transaction = UpdateTransaction.List(options.InstallationDirectory).FirstOrDefault(t => t.Status is not ("completed" or "rolledBack" or "cancelled"))
            ?? throw new PestoException("update.recovery", "Aucune interruption n’a été détectée.");
        return UpdateTransaction.RequestRollback(transaction.TransactionDirectory, true);
    }

    private string StateRoot()
    {
        var state = Path.GetFullPath(options.StateDirectory);
        var install = Path.GetFullPath(options.InstallationDirectory).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (state.Equals(install.TrimEnd(Path.DirectorySeparatorChar), StringComparison.OrdinalIgnoreCase)
            || state.StartsWith(install, StringComparison.OrdinalIgnoreCase)) throw new PestoException("update.state", "Le dossier de préparation doit être séparé des fichiers de l’application.");
        UpdatePackage.RequireNoLinks(state);
        Directory.CreateDirectory(state);
        return state;
    }

    private void Guard()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (options.Simulation) throw new PestoException("demo.isolated", "La démonstration interdit tout accès aux sources réelles de mise à jour, même par appel direct.");
        if (options.Channel is not ("DEV" or "PROD")) throw new PestoException("update.channel", "Canal de mise à jour invalide.");
    }

    private static void Confirm(bool confirmed)
    {
        if (!confirmed) throw new PestoException("update.confirmation", "Confirmez explicitement le remplacement des fichiers de l’application.");
    }

    private static void ValidateUpgrade(UpdatePackageInfo current, UpdatePackageInfo next)
    {
        if (current.Channel != next.Channel) throw new PestoException("package.channel", "Le canal de la mise à jour ne correspond pas à cette installation.");
        if (next.WebView2Runtime != current.WebView2Runtime) throw new PestoException("package.edition", "Choisissez un pack de la même édition (LIGHT ou DEV).");
        if (Version.Parse(next.Version) < Version.Parse(current.Version)) throw new PestoException("update.downgrade", "Ce pack est plus ancien. Utilisez le retour transactionnel pour rétablir la sauvegarde.");
        if (current.Fingerprint == next.Fingerprint) throw new PestoException("update.same", "Ce pack est déjà installé à l’identique.");
    }

    private static JsonObject Describe(UpdatePackageInfo info, string id, string idField, string source, string message) => new()
    {
        [idField] = id, ["version"] = info.Version, ["channel"] = info.Channel, ["distribution"] = info.Distribution,
        ["fingerprint"] = info.Fingerprint, ["fileCount"] = info.FileCount, ["bytes"] = info.Bytes,
        ["source"] = source, ["configurationIncluded"] = info.ConfigurationFingerprint is not null,
        ["message"] = message
    };

    private static string ResolvePackRoot(string directory)
    {
        UpdatePackage.RequireNoLinks(directory);
        if (File.Exists(Path.Combine(directory, "Pesto.exe"))) return directory;
        var entries = Directory.GetFileSystemEntries(directory);
        if (entries.Length == 1 && Directory.Exists(entries[0]) && File.Exists(Path.Combine(entries[0], "Pesto.exe"))) return entries[0];
        throw new PestoException("package.layout", "L’archive doit contenir Pesto.exe et wad, directement ou dans un dossier unique.");
    }

    private string WorkspaceRoot() => (workspace ??= new UpdateWorkspace(StateRoot())).DirectoryPath;

    private IDisposable Enter()
    {
        gate.Wait();
        try { Guard(); PruneExpired(); return new Admission(gate); }
        catch { gate.Release(); throw; }
    }

    private void PruneExpired()
    {
        var now = clock.GetUtcNow();
        foreach (var item in candidates.Values.Where(c => c.ExpiresAt <= now).ToArray())
        {
            candidates.Remove(item.Id);
            if (item.OwnedInspection is not null) UpdateWorkspace.RemoveCopy(item.OwnedInspection);
        }
        foreach (var item in prepared.Values.Where(p => p.ExpiresAt <= now).ToArray())
        {
            prepared.Remove(item.Id);
            UpdateWorkspace.RemoveCopy(Path.GetDirectoryName(item.Directory)!);
        }
    }

    public void Dispose()
    {
        gate.Wait();
        try
        {
            if (disposed) return;
            disposed = true;
            workspace?.Dispose(); candidates.Clear(); prepared.Clear();
        }
        finally { gate.Release(); }
        // Waiters must acquire the gate and observe disposed. No semaphore wait handle is allocated here.
    }

    private sealed class Admission(SemaphoreSlim gate) : IDisposable { public void Dispose() => gate.Release(); }
    private sealed record Candidate(string Id, string Source, string Path, string Version, string Fingerprint, DateTimeOffset ExpiresAt, string? OwnedInspection);
    private sealed record Prepared(string Id, string Directory, string Fingerprint, string CurrentFingerprint, DateTimeOffset ExpiresAt, string Source);
}

using System.Text;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Disposable pack copies only. Installation transactions and selected sources never live here.</summary>
internal sealed class UpdateWorkspace : IDisposable
{
    private readonly FileStream lease;
    private readonly string leasePath;
    public string DirectoryPath { get; }
    private static byte[] Marker(string id) => Encoding.ASCII.GetBytes("pesto.update-workspace.v1\n" + id + "\n");

    public UpdateWorkspace(string stateRoot)
    {
        var root = Path.Combine(stateRoot, "workspaces");
        UpdatePackage.RequireNoLinks(root);
        Directory.CreateDirectory(root);
        ReclaimAbandoned(root);
        var id = Guid.NewGuid().ToString("N");
        DirectoryPath = Path.Combine(root, id);
        leasePath = Path.Combine(root, id + ".lease");
        UpdatePackage.RequireNoLinks(DirectoryPath);
        UpdatePackage.RequireNoLinks(leasePath);
        if (Directory.Exists(DirectoryPath) || File.Exists(DirectoryPath))
            throw new PestoException("update.state", "Le dossier temporaire choisi existe déjà.");
        lease = new FileStream(leasePath, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None);
        try
        {
            lease.Write(Marker(id)); lease.Flush(true);
            Directory.CreateDirectory(DirectoryPath);
            UpdatePackage.RequireNoLinks(DirectoryPath);
        }
        catch
        {
            lease.Dispose();
            // A refusal to resolve the new path never authorizes deleting an existing tree.
            TryDeleteLease(leasePath);
            throw;
        }
    }

    private static void ReclaimAbandoned(string root)
    {
        // No age-based assumption: a live instance holds its lease until every copy has drained.
        foreach (var directory in Directory.EnumerateDirectories(root).Take(64))
        {
            var id = Path.GetFileName(directory);
            if (id.Length != 32 || !Guid.TryParseExact(id, "N", out _)) continue;
            var path = Path.Combine(root, id + ".lease");
            try
            {
                UpdatePackage.RequireNoLinks(directory); UpdatePackage.RequireNoLinks(path);
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                {
                    var marker = Marker(id);
                    if (stream.Length != marker.Length) continue;
                    var bytes = new byte[marker.Length]; stream.ReadExactly(bytes);
                    if (!bytes.AsSpan().SequenceEqual(marker)) continue;
                    RemoveCopy(directory);
                }
                if (!Directory.Exists(directory)) TryDeleteLease(path);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or PestoException)
            {
                // An active, unowned, inaccessible or linked workspace remains untouched.
            }
        }
    }

    internal static void RemoveCopy(string directory)
    {
        try
        {
            UpdatePackage.RequireNoLinks(directory);
            if (!Directory.Exists(directory)) return;
            // Reject links throughout the owned tree before recursive cleanup.
            _ = UpdatePackage.Inventory(directory);
            UpdatePackage.TryRemoveOwned(directory);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or PestoException) { }
    }

    private static void TryDeleteLease(string path)
    {
        try { UpdatePackage.RequireNoLinks(path); File.Delete(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or PestoException) { }
    }

    public void Dispose()
    {
        try { RemoveCopy(DirectoryPath); }
        finally { lease.Dispose(); }
        // Failed cleanup leaves a recoverable marker; no live process owns these copies anymore.
        if (!Directory.Exists(DirectoryPath)) TryDeleteLease(leasePath);
    }
}

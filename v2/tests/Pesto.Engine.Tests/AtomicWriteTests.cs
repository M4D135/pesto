using System.Diagnostics;
using System.Text;

namespace Pesto.Engine.Tests;

internal static class AtomicWriteTests
{
    [Test] private static void NewAndReplacedRecordsKeepExactUtf8Bytes()
    {
        using var fixture = new Fixture();
        foreach (var contents in new[] { "{\"état\":\"prêt 🌿\"}", new string('é', 9000) })
        {
            UpdatePackage.WriteAtomic(fixture.Target, contents);
            Check.True(File.ReadAllBytes(fixture.Target).SequenceEqual(Encoding.UTF8.GetBytes(contents)), "UTF-8 complet, sans BOM ni reste de l’ancien contenu");
            fixture.NoTemporary();
        }
    }

    [Test] private static void WindowsTransientReadersDoNotLoseThePreviousRecord()
    {
        if (!OperatingSystem.IsWindows()) return; // The Windows campaign executes both real sharing modes.
        foreach (var share in new[] { FileShare.Read, FileShare.ReadWrite | FileShare.Delete })
        {
            using var fixture = new Fixture();
            File.WriteAllText(fixture.Target, "previous");
            using var reader = new FileStream(fixture.Target, FileMode.Open, FileAccess.Read, share);
            using var started = new ManualResetEventSlim();
            using var done = new ManualResetEventSlim();
            Exception? failure = null;
            var writer = new Thread(() =>
            {
                started.Set();
                try { UpdatePackage.WriteAtomic(fixture.Target, "replacement é🌿"); }
                catch (Exception error) { failure = error; }
                finally { done.Set(); }
            }) { IsBackground = true };
            writer.Start();
            bool completedWhileHeld;
            try
            {
                Check.True(started.Wait(TimeSpan.FromSeconds(5)), "écrivain démarré");
                completedWhileHeld = done.Wait(TimeSpan.FromMilliseconds(300));
                if (share == FileShare.Read)
                {
                    Check.False(completedWhileHeld, "aucune publication avant libération du verrou sans partage de suppression");
                    Check.Equal("previous", File.ReadAllText(fixture.Target), "ancien journal conservé pendant l’attente");
                }
            }
            finally
            {
                reader.Dispose();
                Check.True(writer.Join(TimeSpan.FromSeconds(5)), "écrivain terminé après libération du lecteur");
            }
            Check.Null(failure, "le refus temporaire ne doit pas interrompre la publication");
            Check.Equal("replacement é🌿", File.ReadAllText(fixture.Target), "nouveau journal complet après libération");
            fixture.NoTemporary();
        }
    }

    [Test] private static void WindowsPersistentLockFailsWithoutPublishingOrDeletingPreviousRecord()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        File.WriteAllText(fixture.Target, "previous");
        using var reader = new FileStream(fixture.Target, FileMode.Open, FileAccess.Read, FileShare.Read);
        var watch = Stopwatch.StartNew();
        Exception? failure = null;
        try { UpdatePackage.WriteAtomic(fixture.Target, "must not be published"); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { failure = error; }
        Check.NotNull(failure, "un refus persistant reste un échec");
        Check.True(watch.Elapsed < TimeSpan.FromSeconds(5), "attente de publication bornée");
        Check.Equal("previous", File.ReadAllText(fixture.Target), "aucune suppression ou écriture partielle du journal précédent");
        fixture.NoTemporary();
    }

    private sealed class Fixture : IDisposable
    {
        private readonly string root = Path.Combine(Path.GetTempPath(), "Pesto-atomic-write-test-" + Guid.NewGuid().ToString("N"));
        internal string Target => Path.Combine(root, "transaction.json");
        internal Fixture() => Directory.CreateDirectory(root);
        internal void NoTemporary() => Check.Equal(0, Directory.GetFiles(root, "*.tmp").Length, "aucun fichier temporaire abandonné");
        public void Dispose() => Directory.Delete(root, true);
    }
}

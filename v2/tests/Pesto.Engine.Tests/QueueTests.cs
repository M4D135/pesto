using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class QueueTests
{
    private static void EnqueueRename(IPestoBackend backend, string computer, string type, string site, string service)
    {
        var preview = Harness.Call(backend, "names.preview", new { type, site, service, computer });
        Harness.Call(backend, "queue.add", new { kind = "rename", computer, previewId = Harness.Str(preview, "previewId") });
    }

    [Test]
    public void AddListRemoveRoundTrip()
    {
        var backend = Harness.Simulation();
        EnqueueRename(backend, "S111301PAADM001", "S", "paris", "ADM");
        Check.Equal(1, Harness.Int(Harness.Call(backend, "queue.list"), "count"), "Un poste en file");
        var id = Harness.Str(Harness.Arr(Harness.Call(backend, "queue.list"), "items")[0]!, "id");
        Harness.Call(backend, "queue.remove", new { id });
        Check.Equal(0, Harness.Int(Harness.Call(backend, "queue.list"), "count"), "File vidée");
    }

    [Test]
    public void JoinCannotBeQueued()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Harness.Call(backend, "queue.add", new { kind = "join", computer = "NOUVEAU-PC" }), "queue.local", "La jonction reste hors file");
    }

    [Test]
    public void DuplicateComputerIsRejected()
    {
        var backend = Harness.Simulation();
        EnqueueRename(backend, "S111301PAADM001", "S", "paris", "ADM");
        Check.Pesto(() => { EnqueueRename(backend, "S111301PAADM001", "S", "paris", "ADM"); return null; }, "queue.duplicate", "Pas de doublon dans la file");
    }

    [Test]
    public void RenameNeedsAFreshPreview()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Harness.Call(backend, "queue.add", new { kind = "rename", computer = "S111301PAADM001" }), "plan.stale", "Aperçu obligatoire avant la file");
    }

    [Test]
    public void EmptyQueueCannotBePrepared()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Harness.Call(backend, "queue.prepare"), "queue.empty", "File vide refusée");
    }

    [Test]
    public void BatchExecutesSequentiallyAndEmptiesQueue()
    {
        var backend = Harness.Simulation();
        EnqueueRename(backend, "S111301PAADM001", "S", "paris", "ADM");
        EnqueueRename(backend, "P111301LYLOG001", "P", "lyon", "LOG");
        var batch = Harness.Call(backend, "queue.prepare");
        Check.Equal(2, Harness.Arr(batch, "items").Count, "Deux plans préparés");
        var result = Harness.Call(backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        Check.Equal(2, Harness.Arr(result, "receipts").Count, "Deux reçus produits");
        Check.False(Harness.Bool(result, "stopped"), "Aucun arrêt");
        Check.Equal(0, Harness.Int(Harness.Call(backend, "queue.list"), "count"), "File vidée après exécution");
    }

    [Test]
    public void BatchNeedsExplicitConfirmation()
    {
        var backend = Harness.Simulation();
        EnqueueRename(backend, "S111301PAADM001", "S", "paris", "ADM");
        var batch = Harness.Call(backend, "queue.prepare");
        Check.Pesto(() => Harness.Call(backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = false }),
            "confirmation.invalid", "Confirmation explicite exigée");
    }

    [Test]
    public void BatchBecomesStaleWhenQueueChanges()
    {
        var backend = Harness.Simulation();
        EnqueueRename(backend, "S111301PAADM001", "S", "paris", "ADM");
        var batch = Harness.Call(backend, "queue.prepare");
        EnqueueRename(backend, "P111301LYLOG001", "P", "lyon", "LOG");
        Check.Pesto(() => Harness.Call(backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }),
            "plan.stale", "Un lot invalidé par un changement de file est refusé");
    }

    [Test]
    public void BatchIsConsumedOnce()
    {
        var backend = Harness.Simulation();
        EnqueueRename(backend, "S111301PAADM001", "S", "paris", "ADM");
        var batch = Harness.Call(backend, "queue.prepare");
        var batchId = Harness.Str(batch, "batchId");
        Harness.Call(backend, "queue.execute", new { batchId, confirmed = true });
        Check.Pesto(() => Harness.Call(backend, "queue.execute", new { batchId, confirmed = true }), "batch.stale", "Un lot ne rejoue pas");
    }
}

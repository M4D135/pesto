using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class SimulationLifecycleTests
{
    private const string ParisOu = "OU=Paris,OU=Postes,DC=example,DC=local";
    private const string LyonOu = "OU=Lyon,OU=Postes,DC=example,DC=local";

    private static JsonNode Preview(IPestoBackend b, string type, string site, string service, string? computer = null, bool alternative = false)
        => Harness.Call(b, "names.preview", new { type, site, service, computer, alternative });

    private static JsonNode Prepare(IPestoBackend b, object args) => Harness.Call(b, "operation.prepare", args);

    private static JsonNode Execute(IPestoBackend b, string planId, string confirmation)
        => Harness.Call(b, "operation.execute", new { planId, confirmationName = confirmation });

    [Test]
    public void RenameAppliesSimulatedReceiptAndKeepsSameSiteOu()
    {
        var backend = Harness.Simulation();
        var preview = Preview(backend, "S", "paris", "ADM", "S111301PAADM001");
        var name = Harness.Str(preview, "name");
        Check.Equal("S111301PAADM002", name, "Nom libre proposé pour le fixe");

        var plan = Prepare(backend, new { kind = "rename", computer = "S111301PAADM001", previewId = Harness.Str(preview, "previewId") });
        Check.Equal(ParisOu, Harness.Str(plan, "targetOU"), "Un renommage sur le même site conserve l’OU");

        var receipt = Execute(backend, Harness.Str(plan, "planId"), name);
        Check.Equal("simulated", Harness.Str(receipt, "status"), "Reçu simulé");
        Check.Equal("simulation", Harness.Str(receipt, "mode"), "Mode annoncé dans le reçu");
        Check.Equal(name, Harness.Str(receipt, "newName"), "Nouveau nom appliqué");
        Check.True(Harness.Bool(receipt, "restartRequired"), "Un renommage demande un redémarrage");

        Check.Equal(name, Harness.Str(Harness.Call(backend, "computer.inspect", new { computer = name }), "name"), "Le poste porte le nouveau nom");
        Check.Pesto(() => Harness.Call(backend, "computer.inspect", new { computer = "S111301PAADM001" }), "computer.missing", "L’ancien nom a disparu");
    }

    [Test]
    public void MoveChangesOuWithoutRenamingAndNeedsNoRestart()
    {
        var backend = Harness.Simulation();
        var plan = Prepare(backend, new { kind = "move", computer = "S111301PAADM001", targetOU = LyonOu });
        Check.Equal("S111301PAADM001", Harness.Str(plan, "newName"), "Un déplacement ne renomme pas");
        var receipt = Execute(backend, Harness.Str(plan, "planId"), "S111301PAADM001");
        Check.Equal(LyonOu, Harness.Str(receipt, "targetOU"), "L’OU de destination est appliquée");
        Check.False(Harness.Bool(receipt, "restartRequired"), "Un déplacement seul ne demande pas de redémarrage");
        Check.Equal("lyon", Harness.Str(Harness.Call(backend, "computer.inspect", new { computer = "S111301PAADM001" }), "site"), "Le site suit l’OU de destination");
    }

    [Test]
    public void MoveRequiresTargetOu()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Prepare(backend, new { kind = "move", computer = "S111301PAADM001" }), "invalid_arguments", "Déplacement sans OU refusé");
    }

    [Test]
    public void RenameMoveCombinesBothSteps()
    {
        var backend = Harness.Simulation();
        var preview = Preview(backend, "P", "paris", "LOG", "P111301LYLOG001");
        var name = Harness.Str(preview, "name");
        var plan = Prepare(backend, new { kind = "renameMove", computer = "P111301LYLOG001", previewId = Harness.Str(preview, "previewId") });
        var receipt = Execute(backend, Harness.Str(plan, "planId"), name);
        Check.Equal(name, Harness.Str(receipt, "newName"), "Renommage appliqué");
        Check.Equal("renameMove", Harness.Str(plan, "kind"), "Le changement de site conserve les deux étapes");
        Check.Equal("paris", Harness.Str(Harness.Call(backend, "computer.inspect", new { computer = name }), "site"), "Nouveau site appliqué après renommage");
    }

    [Test]
    public void JoinIsLocalOnlyAndSingleUse()
    {
        var backend = Harness.Simulation();
        Check.Pesto(() => Prepare(backend, new { kind = "join", computer = "P111301PAINF001", previewId = Harness.Str(Preview(backend, "P", "paris", "INF"), "previewId") }),
            "join.localOnly", "La jonction ne concerne que le poste local");

        var preview = Preview(backend, "P", "paris", "INF");
        var name = Harness.Str(preview, "name");
        var plan = Prepare(backend, new { kind = "join", previewId = Harness.Str(preview, "previewId") });
        var receipt = Execute(backend, Harness.Str(plan, "planId"), name);
        Check.Equal("join", Harness.Str(receipt, "kind"), "Reçu de jonction");
        Check.Equal(name, Harness.Str(Harness.Call(backend, "session.info"), "computer"), "Le poste local est joint");

        Check.Pesto(() => Prepare(backend, new { kind = "join", previewId = Harness.Str(Preview(backend, "P", "paris", "INF"), "previewId") }),
            "join.alreadyJoined", "Pas de seconde jonction");
    }

    [Test]
    public void PlanIsConsumedOnceAndNeedsExactConfirmation()
    {
        var backend = Harness.Simulation();
        var preview = Preview(backend, "S", "paris", "ADM", "S111301PAADM001");
        var name = Harness.Str(preview, "name");
        var plan = Prepare(backend, new { kind = "rename", computer = "S111301PAADM001", previewId = Harness.Str(preview, "previewId") });
        var planId = Harness.Str(plan, "planId");

        Check.Pesto(() => Execute(backend, planId, "MAUVAIS-NOM"), "confirmation.invalid", "Confirmation inexacte refusée");
        Execute(backend, planId, name);
        Check.Pesto(() => Execute(backend, planId, name), "plan.consumed", "Un plan ne sert qu’une fois");
    }

    [Test]
    public void ExpiredPlanIsRefused()
    {
        var clock = new FixedClock();
        var backend = Harness.Simulation(clock);
        var preview = Preview(backend, "S", "paris", "ADM", "S111301PAADM001");
        var name = Harness.Str(preview, "name");
        var plan = Prepare(backend, new { kind = "rename", computer = "S111301PAADM001", previewId = Harness.Str(preview, "previewId") });
        clock.Advance(TimeSpan.FromMinutes(6));
        Check.Pesto(() => Execute(backend, Harness.Str(plan, "planId"), name), "plan.stale", "Plan expiré refusé");
    }

    [Test]
    public void CollisionAfterPrepareNeverAutoRetries()
    {
        var backend = Harness.Simulation();
        var renamePreview = Preview(backend, "P", "paris", "INF", "P111301PAINF001");
        var name = Harness.Str(renamePreview, "name");
        var plan = Prepare(backend, new { kind = "rename", computer = "P111301PAINF001", previewId = Harness.Str(renamePreview, "previewId") });

        // The very name is taken by another confirmed action before this plan is executed.
        var joinPreview = Preview(backend, "P", "paris", "INF");
        var joinPlan = Prepare(backend, new { kind = "join", previewId = Harness.Str(joinPreview, "previewId") });
        Execute(backend, Harness.Str(joinPlan, "planId"), Harness.Str(joinPreview, "name"));

        Check.Pesto(() => Execute(backend, Harness.Str(plan, "planId"), name), "identity.changed", "Collision après préparation : rien n’est appliqué, aucun nouvel ajout automatique");
    }

    [Test]
    public void RenamingFreesTheOldNameForReuse()
    {
        var backend = Harness.Simulation();
        var preview = Preview(backend, "P", "paris", "INF", "P111301PAINF001");
        var name = Harness.Str(preview, "name");
        var plan = Prepare(backend, new { kind = "rename", computer = "P111301PAINF001", previewId = Harness.Str(preview, "previewId") });
        Execute(backend, Harness.Str(plan, "planId"), name);
        Check.Equal("P111301PAINF001", Harness.Str(Preview(backend, "P", "paris", "INF"), "name"), "L’ancien nom libéré redevient le premier disponible");
    }

    [Test]
    public void ReceiptsAreListedAndRetrievable()
    {
        var backend = Harness.Simulation();
        var preview = Preview(backend, "S", "paris", "ADM", "S111301PAADM001");
        var name = Harness.Str(preview, "name");
        var plan = Prepare(backend, new { kind = "rename", computer = "S111301PAADM001", previewId = Harness.Str(preview, "previewId") });
        var receipt = Execute(backend, Harness.Str(plan, "planId"), name);
        var id = Harness.Str(receipt, "id");
        Check.Equal(id, Harness.Str(Harness.Call(backend, "receipts.get", new { id }), "id"), "Reçu récupérable par identifiant");
        Check.Equal(1, Harness.Arr(Harness.Call(backend, "receipts.list", new { query = name }), "items").Count, "Reçu retrouvé par recherche");
        Check.Pesto(() => Harness.Call(backend, "receipts.get", new { id = "receipt-inexistant" }), "receipt.missing", "Reçu inconnu refusé");
    }
}

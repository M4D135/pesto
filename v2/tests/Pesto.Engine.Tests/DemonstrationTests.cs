using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class DemonstrationTests
{
    private static JsonNode Select(IPestoBackend b, string id) => Harness.Call(b, "demo.scenario", new { id, confirmed = true });
    private static JsonNode Plan(IPestoBackend b, string computer = "S111301PAADM001")
    {
        var preview = Harness.Call(b, "names.preview", new { type = "S", site = "paris", service = "ADM", computer });
        return Harness.Call(b, "operation.prepare", new { kind = "rename", computer, previewId = Harness.Str(preview, "previewId") });
    }
    private static JsonNode Execute(IPestoBackend b, JsonNode plan) => Harness.Call(b, "operation.execute",
        new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });

    [Test]
    public void IdentifiersNeverAliasAcrossResetOrWindows()
    {
        var first = Harness.Simulation();
        var second = Harness.Simulation();
        var before = Plan(first);
        var receipt = Execute(first, before);
        Harness.Call(first, "demo.reset", new { confirmed = true });
        var after = Plan(first);
        var other = Plan(second);
        Check.False(Harness.Str(before, "planId") == Harness.Str(after, "planId"), "Un reset ne réutilise pas les identifiants");
        Check.False(Harness.Str(after, "planId") == Harness.Str(other, "planId"), "Deux fenêtres sous horloge figée restent distinctes");
        Check.Pesto(() => Execute(first, before), "plan.stale", "Le plan de l’ancien monde reste invalide");
        Check.Pesto(() => Harness.Call(first, "receipts.get", new { id = Harness.Str(receipt, "id") }), "receipt.missing", "Un reçu ancien ne désigne aucun nouveau reçu");
    }

    [Test]
    public void ResetAndScenarioRequireExplicitConfirmation()
    {
        var b = Harness.Simulation();
        Check.Pesto(() => Harness.Call(b, "demo.reset"), "confirmation.invalid", "Reset direct sans confirmation refusé");
        Check.Pesto(() => Harness.Call(b, "demo.scenario", new { id = "joined", confirmed = false }), "confirmation.invalid", "Scénario non confirmé refusé");
        Check.Pesto(() => Harness.Call(b, "demo.reset", new { confirmed = true, path = @"\\server\share" }), "invalid_arguments", "Champs supplémentaires refusés aussi par API directe");
        Check.Equal(0, Harness.Int(Harness.Call(b, "demo.status"), "generation"), "Aucun reset admis");
    }

    [Test]
    public void InvalidScenarioPreservesWorld()
    {
        var b = Harness.Simulation();
        var plan = Plan(b);
        Check.Pesto(() => Select(b, "../live"), "demo.scenario", "Scénario arbitraire refusé avant reset");
        Check.Equal("simulated", Harness.Str(Execute(b, plan), "status"), "Le monde courant est conservé");
        Check.Equal(8, Harness.Arr(Harness.Call(b, "demo.status"), "scenarios").Count, "Huit scénarios disponibles");
    }

    [Test]
    public void NewWorldAndOtherWindowDoNotShareSettingsOrReceipts()
    {
        var b = Harness.Simulation(); var other = Harness.Simulation();
        var settings = Harness.Call(b, "settings.get").AsObject();
        settings["prefix"] = "222222";
        Harness.Call(b, "settings.save", settings);
        Check.Equal("111301", Harness.Str(Harness.Call(other, "settings.get"), "prefix"), "La seconde fenêtre n’hérite d’aucune modification");
        Select(b, "pendingRestart");
        Check.Equal("111301", Harness.Str(Harness.Call(b, "settings.get"), "prefix"), "Le scénario repart des paramètres fictifs");
        Check.Equal(0, Harness.Arr(Harness.Call(other, "receipts.list"), "items").Count, "Aucun reçu ne fuit dans la seconde fenêtre");
    }

    [Test]
    public void RestartOnlyFinishesConfirmedSimulatedRestarts()
    {
        var b = Harness.Simulation(); Select(b, "pendingRestart");
        Check.Pesto(() => Harness.Call(b, "demo.restart", new { confirmed = false }), "confirmation.invalid", "Reboot explicite exigé");
        Check.Equal(1, Harness.Int(Harness.Call(b, "demo.status"), "pendingRestart"), "Un reboot reste en attente");
        Harness.Call(b, "demo.restart", new { confirmed = true });
        var receipt = Harness.Arr(Harness.Call(b, "receipts.list"), "items")[0]!;
        Check.False(Harness.Bool(receipt, "restartRequired"), "Reboot fictif terminé");
        Check.Equal("simulated", Harness.Str(receipt, "status"), "Jamais une preuve réelle");
        Check.Equal("simulation", Harness.Str(receipt, "mode"), "Mode immuable");
        Check.Equal(0, Harness.Int(Harness.Call(b, "dashboard.read"), "pendingRestart"), "Tableau de bord actualisé");
    }

    [Test]
    public void PartialMoveRequiresRestartAndKeepsLinkedHistoricalParent()
    {
        var b = Harness.Simulation(); Select(b, "partialMove");
        var parent = Harness.Arr(Harness.Call(b, "receipts.list"), "items")[0]!;
        var id = Harness.Str(parent, "id");
        Check.Pesto(() => Harness.Call(b, "demo.prepareMove", new { id }), "demo.restartRequired", "Pas de déplacement avant reboot fictif");
        var beforeOu = Harness.Str(Harness.Call(b, "computer.inspect", new { computer = Harness.Str(parent, "newName") }), "ou");
        Harness.Call(b, "demo.restart", new { confirmed = true });
        var plan = Harness.Call(b, "demo.prepareMove", new { id });
        Check.Equal("move", Harness.Str(plan, "kind"), "Uniquement le déplacement restant");
        Check.Equal(Harness.Str(parent, "newName"), Harness.Str(plan, "computer"), "Le nom renommé est conservé");
        var secondPlan = Harness.Call(b, "demo.prepareMove", new { id });
        var child = Execute(b, plan);
        Check.Equal(id, Harness.Str(child, "parentReceiptId"), "Enfant lié au parent");
        var reloaded = Harness.Call(b, "receipts.get", new { id });
        Check.Equal("89", Harness.Str(reloaded, "code"), "Le résultat partiel n’est pas maquillé");
        Check.Equal("pendingRestart", Harness.Str(reloaded, "status"), "État historique conservé");
        Check.Equal(Harness.Str(child, "id"), Harness.Str(reloaded, "resolutionChildReceiptId"), "Lien de résolution fictive explicite");
        Check.False(beforeOu == Harness.Str(child, "targetOU"), "L’OU change réellement dans le monde mémoire");
        Check.Pesto(() => Execute(b, secondPlan), "demo.receipt", "Une autre préparation ne rejoue pas le déplacement");
    }

    [Test]
    public void DeniedScenarioProducesRefusalAndConsumesPlanWithoutChangingComputer()
    {
        var b = Harness.Simulation(); Select(b, "denied"); var plan = Plan(b);
        var receipt = Execute(b, plan);
        Check.Equal("refused", Harness.Str(receipt, "status"), "Refus visible");
        Check.Equal("5", Harness.Str(receipt, "code"), "Code de refus explicite");
        Check.Equal("S111301PAADM001", Harness.Str(Harness.Call(b, "computer.inspect", new { computer = "S111301PAADM001" }), "name"), "Aucun changement simulé après refus");
        Check.Pesto(() => Execute(b, plan), "plan.consumed", "Un refus n’autorise pas de rejeu implicite");
    }

    [Test]
    public void RefusedOrUncertainMoveReceiptsKeepThePlannedDestinationWithoutMovingTheComputer()
    {
        foreach (var scenario in new[] { "denied", "uncertain" })
        foreach (var kind in new[] { "move", "renameMove" })
        {
            var b = Harness.Simulation(); Select(b, scenario);
            const string computer = "S111301PAADM001";
            var before = Harness.Call(b, "computer.inspect", new { computer });
            var preview = Harness.Call(b, "names.preview", new { type = "S", site = "lyon", service = "INF", computer });
            var plan = kind == "move"
                ? Harness.Call(b, "operation.prepare", new { kind, computer, targetOU = Harness.Str(preview, "ou") })
                : Harness.Call(b, "operation.prepare", new { kind, computer, previewId = Harness.Str(preview, "previewId") });
            Check.False(Harness.Str(before, "ou") == Harness.Str(plan, "targetOU"), "Le test demande un autre placement");
            var receipt = Execute(b, plan);
            Check.Equal(Harness.Str(plan, "targetOU"), Harness.Str(receipt, "targetOU"), "Le reçu décrit l’OU du plan, pas un faux déplacement observé");
            Check.Equal(scenario == "denied" ? "refused" : "uncertain", Harness.Str(receipt, "status"), "L’issue non confirmée reste visible");
            Check.Equal(scenario == "denied" ? "5" : "97", Harness.Str(receipt, "code"), "Code d’issue conservé");
            var after = Harness.Call(b, "computer.inspect", new { computer });
            foreach (var field in new[] { "name", "guid", "ou" })
                Check.Equal(Harness.Str(before, field), Harness.Str(after, field), field + " fictif inchangé");
            Check.Pesto(() => Execute(b, plan), "plan.consumed", "Aucun rejeu après un résultat non confirmé");
        }
    }

    [Test]
    public void UncertainStopsQueueAndSurvivesFictitiousRestart()
    {
        var b = Harness.Simulation(); Select(b, "uncertain");
        foreach (var computer in new[] { "S111301PAADM001", "P111301PAINF001" })
        {
            var preview = Harness.Call(b, "names.preview", new { type = "S", site = "paris", service = "ADM", computer });
            Harness.Call(b, "queue.add", new { kind = "rename", computer, previewId = Harness.Str(preview, "previewId") });
        }
        var batch = Harness.Call(b, "queue.prepare");
        var result = Harness.Call(b, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true });
        Check.True(Harness.Bool(result, "stopped"), "Lot arrêté sur l’incertain");
        Check.Equal(1, Harness.Arr(result, "receipts").Count, "Une seule ligne tentée");
        Check.Equal(1, Harness.Int(Harness.Call(b, "queue.list"), "count"), "Seconde ligne non tentée");
        Harness.Call(b, "demo.restart", new { confirmed = true });
        Check.Equal("uncertain", Harness.Str(Harness.Arr(Harness.Call(b, "receipts.list"), "items")[0]!, "status"), "Reboot fictif ne fabrique pas de succès");
        Check.Pesto(() => Plan(b), "demo.uncertain", "Pas de reprise implicite après l’incertain");
    }

    [Test]
    public void CollisionRequiresAnotherPreview()
    {
        var b = Harness.Simulation(); Select(b, "nameCollision");
        var first = Harness.Call(b, "names.preview", new { type = "P", site = "paris", service = "INF" });
        Check.Pesto(() => Harness.Call(b, "operation.prepare", new { kind = "join", previewId = Harness.Str(first, "previewId") }), "name.taken", "Collision signalée avant écriture");
        var second = Harness.Call(b, "names.preview", new { type = "P", site = "paris", service = "INF" });
        Check.False(Harness.Str(first, "name") == Harness.Str(second, "name"), "Le nom pris n’est pas reproposé");
        Check.Equal(0, Harness.Arr(Harness.Call(b, "receipts.list"), "items").Count, "Aucune écriture implicite");
    }

    [Test]
    public void OfflineScenarioNeverInventsAvailableNames()
    {
        var b = Harness.Simulation(); Select(b, "directoryOffline");
        Check.Pesto(() => Harness.Call(b, "directory.sites"), "directory.unavailable", "Annuaire indisponible signalé");
        Check.Pesto(() => Harness.Call(b, "names.preview", new { type = "P", site = "paris", service = "INF" }), "directory.unavailable", "Aucun nom inventé");
        Check.True(Harness.IsNull(Harness.Call(b, "dashboard.read"), "computers"), "Compteur inconnu, pas faux zéro");
        Check.Equal("directoryOffline", Harness.Str(Harness.Call(b, "demo.status"), "scenario"), "Les commandes démo restent accessibles");
    }

    [Test]
    public void JoinCapabilityFollowsTheSimulatedLocalMembership()
    {
        var b = Harness.Simulation();
        static JsonNode Join(IPestoBackend backend) => Harness.Arr(Harness.Call(backend, "session.info"), "capabilities").Single(c => Harness.Str(c!, "id") == "join")!;
        Check.True(Harness.Bool(Join(b), "enabled"), "Nouveau poste : jonction proposée");
        Check.False(Harness.Bool(Harness.Call(b, "session.info"), "localJoined"), "Nouveau poste simulé : hors domaine");
        Harness.Call(b, "demo.scenario", new { id = "joined", confirmed = true });
        Check.True(Harness.Bool(Harness.Call(b, "session.info"), "localJoined"), "Poste déjà joint : membre du domaine");
        Check.False(Harness.Bool(Join(b), "enabled"), "Poste déjà joint : jonction fermée d’avance, comme la simulation du navigateur");
        Check.Equal("Ce poste simulé a déjà rejoint le domaine.", Harness.Str(Join(b), "reason"), "Motif affiché par la page Ajouter");
        var local = Harness.Str(Harness.Call(b, "session.info"), "computer");
        Check.Equal(local, Harness.Str(Harness.Call(b, "computer.inspect", new { computer = local }), "name"), "Ce poste se lit dans l’annuaire simulé");
    }

    [Test]
    public void RealMaintenanceIsRefusedAtDirectApiBoundary()
    {
        var b = Harness.Simulation();
        foreach (var op in new[] { "updates.status", "updates.windows", "updates.inspect", "updates.prepare", "updates.install", "updates.rollback", "updates.recover",
            "configuration.status", "configuration.settings", "configuration.export", "configuration.previewImport", "configuration.previewSettings", "configuration.applyImport", "configuration.decideDistribution", "configuration.setDefault",
            "references.preview", "references.apply", "host.reconnect",
            "coordination.status", "coordination.inspect", "coordination.prepare", "coordination.apply",
            "reservations.list", "reservations.inspect", "reservations.prepare", "reservations.execute",
                "join.precreated.preview", "receipts.prepareAcknowledgement", "receipts.acknowledge", "receipts.prepareRestart", "receipts.restart",
                "attributes.inspect", "attributes.prepare", "attributes.apply", "attributes.observe",
                "offlineJoin.open", "offlineJoin.list", "offlineJoin.import", "offlineJoin.prepare", "offlineJoin.apply", "offlineJoin.observe" })
            Check.Pesto(() => Harness.Call(b, op, new { path = @"\\example\private", source = "https://example.invalid/secret", confirmed = true }), "demo.isolated", op + " refusée avant tout I/O");
        Check.Pesto(() => Harness.Call(b, "receipts.reconcile", new { id = "real-receipt" }), "receipt.reconcileSimulation", "Pas de relecture d’un reçu réel");
        Check.Pesto(() => Harness.Call(b, "demo.prepareMove", new { id = "real-receipt" }), "demo.receipt", "Pas de continuation d’un reçu réel");
    }

    [Test]
    public void CancelledCallAndDisposedWindowCannotChangeWorld()
    {
        var b = Harness.Simulation();
        using var stop = new CancellationTokenSource(); stop.Cancel();
        try { b.InvokeAsync("demo.reset", PestoJson.Element(new { confirmed = true }), stop.Token).GetAwaiter().GetResult(); throw new TestFailureException("Annulation ignorée"); }
        catch (OperationCanceledException) { }
        Check.Equal(0, Harness.Int(Harness.Call(b, "demo.status"), "generation"), "Aucun reset après annulation");
        ((IDisposable)b).Dispose();
        Check.Pesto(() => Harness.Call(b, "demo.reset", new { confirmed = true }), "demo.closed", "Fenêtre fermée non réutilisable");
    }
}

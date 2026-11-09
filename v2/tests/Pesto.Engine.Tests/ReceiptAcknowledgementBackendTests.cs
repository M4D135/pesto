using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class ReceiptAcknowledgementBackendTests
{
    [Test]
    public void AcknowledgementOfAnotherDurableSnapshotDoesNotAcknowledgeStaleSessionReceipt()
    {
        using var w = new World(); var original = w.UncertainReceipt(); var session = w.Backend;
        var path = Path.Combine(w.Gp, "V2", "receipts", Harness.Str(original, "id") + ".json");
        var disk = JsonNode.Parse(File.ReadAllText(path))!; disk["Code"] = 98; File.WriteAllText(path, disk.ToJsonString());
        w.Backend = Harness.Live(w.Config, w.Directory, w.Mutation, w.Clock, w.Gp);
        var current = Harness.Call(w.Backend, "receipts.get", new { id = Harness.Str(original, "id") });
        _ = w.Acknowledge(w.Prepare(current));
        var listed = Harness.Arr(Harness.Call(session, "receipts.list"), "items").Single(n => Harness.Str(n!, "id") == Harness.Str(original, "id"))!;
        Check.Equal("97", Harness.Str(listed, "code"), "Session business result remains unchanged");
        Check.False(Harness.Bool(listed, "acknowledged"), "An id match cannot reuse another snapshot’s acknowledgement");
        Check.Equal(1, Harness.Int(Harness.Call(session, "dashboard.read"), "uncertain"), "Stale session barrier remains visible");
    }

    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private sealed class Adapter : IMutationGateway, IMutationReceiptFinalizer, IMutationReceiptAcknowledgement, IMutationAvailability
    {
        public required string Gp;
        public required string Configuration;
        public required FixedClock Clock;
        public int Mutations, Preparations, Acknowledgements;
        public bool IsAvailable { get; set; } = true;
        public string? UnavailableReason => IsAvailable ? null : "Fixture adaptateur indisponible";
        private ReceiptAcknowledgementCoordinator? service;
        private ReceiptAcknowledgementCoordinator Service => service ??= new(Gp, _ => new("example.local",
            ReceiptAcknowledgementSource.Digest(File.ReadAllBytes(Path.Combine(Configuration, "cfg.json"))), "FIXTURE\\operator",
            new("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", Clock.GetUtcNow(), true, "local-process-snapshot"), true, true, new('e', 64)), Clock);
        public string Description => "fixture écriture de reçu uniquement";
        public MutationOutcome Execute(MutationRequest request)
        {
            Mutations++; Write(request, "Running", 0, "Reçu fixture avant résultat", false);
            return new(MutationStatus.Uncertain, 97, "Fixture transport interrompu ; aucun appel natif", false);
        }
        public void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome) =>
            Write(request, outcome.Status == MutationStatus.PendingRestart ? "PendingRestart" : outcome.Status == MutationStatus.Failed ? "Failed" : "Uncertain", outcome.Code, outcome.Message, outcome.RestartRequired);
        private void Write(MutationRequest request, string phase, int code, string message, bool restart)
        {
            var folder = Path.Combine(Gp, "V2", "receipts"); Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, request.ReceiptId + ".json"), JsonSerializer.Serialize(new
            {
                Schema = 1, Version = "2.0", Phase = phase, Utc = Clock.GetUtcNow().ToString("o"), Adapter = Description,
                request.ReceiptId, request.PlanId, request.Kind, request.Computer, request.NewName, request.TargetOu,
                request.Domain, request.Dc, Code = code, Message = message, RestartRequired = restart
            }));
        }
        public ReceiptAcknowledgementPreparation PrepareAcknowledgement(string receiptId, string planId)
        { Preparations++; return Service.Prepare(receiptId, planId); }
        public ReceiptAcknowledgementResult Acknowledge(ReceiptAcknowledgementAuthorization authorization, string reason)
        { Acknowledgements++; return Service.Acknowledge(authorization, reason); }
    }
    private sealed class World : IDisposable
    {
        public readonly string Gp = Harness.IsolatedGpRoot();
        public readonly string Config = LiveTestConfig.Write(LiveTestConfig.NoRandom);
        public readonly FixedClock Clock = new();
        public readonly FakeGateway Directory = new() { ChildOus = { [Container] = ["Paris-Nord"] }, Find = _ => null };
        public readonly Adapter Mutation;
        public IPestoBackend Backend;
        public World()
        {
            Mutation = new() { Gp = Gp, Configuration = Config, Clock = Clock };
            Backend = Harness.Live(Config, Directory, Mutation, Clock, Gp);
        }
        public JsonNode UncertainReceipt()
        {
            var preview = Harness.Call(Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
            var plan = Harness.Call(Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
            return Harness.Call(Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        }
        public JsonNode Prepare(JsonNode receipt) => Harness.Call(Backend, "receipts.prepareAcknowledgement", new { id = Harness.Str(receipt, "id") });
        public JsonNode Acknowledge(JsonNode plan, string reason = "Contrôle opérateur consigné") => Harness.Call(Backend, "receipts.acknowledge",
            new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName"), reason });
        public void Dispose() { System.IO.Directory.Delete(Gp, true); System.IO.Directory.Delete(Config, true); }
    }

    private static JsonNode AcknowledgementCapability(World world) => Harness.Arr(Harness.Call(world.Backend, "session.info"), "capabilities")
        .Single(item => Harness.Str(item!, "id") == "acknowledge")!;

    [Test]
    public void ConfirmedAcknowledgementPreservesEveryDisplayedBusinessFieldAndAppearsAfterRestart()
    {
        using var w = new World(); var original = w.UncertainReceipt(); var plan = w.Prepare(original);
        Check.Equal("acknowledge", Harness.Str(plan, "action"), "Action explicite");
        Check.Equal(Harness.Str(original, "newName"), Harness.Str(plan, "confirmationName"), "Nom original à recopier");
        var response = w.Acknowledge(plan); var acknowledged = response["receipt"]!;
        foreach (var field in new[] { "id", "time", "kind", "computer", "newName", "targetOU", "mode", "status", "code", "message", "restartRequired" })
            Check.True(JsonNode.DeepEquals(original[field], acknowledged[field]), "Propriété d’origine conservée : " + field);
        Check.True(Harness.Bool(acknowledged, "acknowledged"), "Décision distincte affichée");
        Check.Equal(1, w.Mutation.Mutations, "L’acquittement n’envoie pas de nouvelle mutation");
        var current = Harness.Call(w.Backend, "receipts.get", new { id = Harness.Str(original, "id") });
        Check.True(Harness.Bool(current, "acknowledged"), "La priorité du reçu session ne masque pas la décision durable");
        Check.Equal("FIXTURE\\operator", Harness.Str(current["acknowledgement"]!, "by"), "Auteur disponible en session");
        w.Backend = Harness.Live(w.Config, w.Directory, w.Mutation, w.Clock, w.Gp);
        var restarted = Harness.Call(w.Backend, "receipts.get", new { id = Harness.Str(original, "id") });
        Check.True(Harness.Bool(restarted, "acknowledged"), "Décision relue après redémarrage");
        Check.Equal("Contrôle opérateur consigné", Harness.Str(restarted["acknowledgement"]!, "reason"), "Motif conservé et consultable");
        Check.Equal("uncertain", Harness.Str(restarted, "status"), "Résultat original incertain conservé");
        var counts = Harness.Call(w.Backend, "dashboard.read");
        Check.Equal(0, Harness.Int(counts, "uncertain"), "Le compteur de traitement observe l’ack sans le compter comme succès");
    }

    [Test]
    public void WrongConfirmationEmptyReasonExpiredPlanAndReplayDoNotWrite()
    {
        using var w = new World(); var r = w.UncertainReceipt(); var p = w.Prepare(r); var id = Harness.Str(p, "planId");
        Check.Pesto(() => Harness.Call(w.Backend, "receipts.acknowledge", new { planId = id, confirmationName = "WRONG", reason = "Motif valable" }), "confirmation.invalid", "Nom exact requis");
        Check.Pesto(() => w.Acknowledge(p, "ab"), "receipt.acknowledgement", "Motif explicite requis");
        Check.Equal(0, w.Mutation.Acknowledgements, "Refus du pont métier avant writer");
        w.Clock.Advance(TimeSpan.FromMinutes(3));
        Check.Pesto(() => w.Acknowledge(p), "plan.stale", "Plan périmé sans writer");
        var next = w.Prepare(r); _ = w.Acknowledge(next);
        Check.Pesto(() => w.Acknowledge(next), "plan.consumed", "Jamais deux événements par confirmation");
        Check.Equal(1, w.Mutation.Acknowledgements, "Un seul envoi writer confirmé");
    }

    [Test]
    public void DirectApiCannotSupplyAuthorPathsPhaseOrReceiptIdAtExecution()
    {
        using var w = new World(); var r = w.UncertainReceipt(); var p = w.Prepare(r);
        Check.Pesto(() => Harness.Call(w.Backend, "receipts.prepareAcknowledgement", new { id = Harness.Str(r, "id"), path = "arbitrary" }), "invalid_arguments", "Pas de chemin du navigateur");
        Check.Pesto(() => Harness.Call(w.Backend, "receipts.acknowledge", new { planId = Harness.Str(p, "planId"), confirmationName = Harness.Str(p, "confirmationName"), reason = "Motif valable", by = "forged" }), "invalid_arguments", "Auteur exclusivement natif");
        Check.Equal(0, w.Mutation.Acknowledgements, "Aucun argument étendu n’atteint le writer");
    }

    [Test]
    public void DirectConsultationCallsRefusePreparationAndAnAlreadyPreparedAcknowledgement()
    {
        using var w = new World(); var r = w.UncertainReceipt(); var p = w.Prepare(r);
        var previous = Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION");
        try
        {
            Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", "1");
            var capability = AcknowledgementCapability(w);
            Check.False(Harness.Bool(capability, "enabled"), "L’interface reçoit le même refus de consultation que les API");
            Check.Contains("consultation", Harness.Str(capability, "reason"), "La raison de la capacité vient du garde réel");
            Check.Pesto(() => w.Prepare(r), "receipt.acknowledgement_readonly", "L’API directe de préparation refuse la consultation");
            Check.Pesto(() => w.Acknowledge(p), "receipt.acknowledgement_readonly", "La consultation activée après le plan refuse aussi l’écriture");
            Check.Equal(1, w.Mutation.Preparations, "Aucune préparation native supplémentaire en consultation");
            Check.Equal(0, w.Mutation.Acknowledgements, "Le writer n’est jamais atteint par une confirmation en consultation");
            Check.Null(new ReceiptAcknowledgementStore(w.Gp).ReadApplied(Harness.Str(r, "id")), "Aucun événement n’est ajouté");
        }
        finally { Environment.SetEnvironmentVariable("PESTO_READONLY_SESSION", previous); }
    }

    [Test]
    public void UnavailableAdapterAndLegacyDemoFlagsRefuseDirectAcknowledgementCalls()
    {
        using (var w = new World())
        {
            var r = w.UncertainReceipt(); var p = w.Prepare(r); w.Mutation.IsAvailable = false;
            Check.False(Harness.Bool(AcknowledgementCapability(w), "enabled"), "Capacité indisponible quand le writer ne l’est plus");
            Check.Pesto(() => w.Prepare(r), "receipt.acknowledgement_unavailable", "Pas de plan avec un adaptateur devenu indisponible");
            Check.Pesto(() => w.Acknowledge(p), "receipt.acknowledgement_unavailable", "La disponibilité est relue lors de la confirmation");
            Check.Equal(0, w.Mutation.Acknowledgements, "Aucun writer indisponible invoqué");
        }
        foreach (var key in new[] { "Simulation", "GUI" })
        {
            using var w = new World(); var r = w.UncertainReceipt(); var p = w.Prepare(r);
            var path = Path.Combine(w.Config, "cfg.json"); var config = JsonNode.Parse(File.ReadAllText(path))!;
            config["DEBUG"]![key] = "true"; File.WriteAllText(path, config.ToJsonString());
            Check.False(Harness.Bool(AcknowledgementCapability(w), "enabled"), "La capacité reflète le refus historique " + key);
            Check.Pesto(() => w.Prepare(r), "receipt.acknowledgement_readonly", "Le flag historique " + key + " ne peut écrire un reçu réel");
            Check.Pesto(() => w.Acknowledge(p), "receipt.acknowledgement_readonly", "Le flag relu refuse un ancien plan confirmé");
            Check.Equal(0, w.Mutation.Acknowledgements, "Aucune mutation du registre réel depuis un mode fictif");
        }
    }

    [Test]
    public void IncidentModeStillAllowsTheV1OperatorDecisionWithoutChangingTheOutcome()
    {
        using var w = new World(); var r = w.UncertainReceipt();
        var path = Path.Combine(w.Config, "cfg.json"); var config = JsonNode.Parse(File.ReadAllText(path))!;
        config["POLICY"]!["IncidentMode"] = true; File.WriteAllText(path, config.ToJsonString());
        Check.True(Harness.Bool(Harness.Call(w.Backend, "session.info"), "readOnly"), "Le mode incident suspend les nouvelles mutations");
        var capability = AcknowledgementCapability(w);
        Check.True(Harness.Bool(capability, "enabled"), "La capacité distincte conserve l’acquittement pendant un incident");
        Check.Null(capability["reason"], "Aucun faux refus de politique ajouté à la décision V1");
        Check.Equal(0, w.Mutation.Preparations, "Lire la capacité ne prépare pas d’acquittement natif");
        var response = w.Acknowledge(w.Prepare(r));
        Check.True(Harness.Bool(response["receipt"]!, "acknowledged"), "La décision explicite V1 reste permise pendant l’incident");
        Check.Equal("uncertain", Harness.Str(response["receipt"]!, "status"), "Aucun succès produit par cette décision");
        Check.Equal(1, w.Mutation.Mutations, "Aucune nouvelle mutation AD déclenchée");
    }
}

using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class JoinReservationBackendTests
{
    private const string Identity = "11111111-2222-3333-4444-555555555555";
    private const string Machine = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private const string OuIdentity = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string Ou = "OU=Paris-Nord," + Container;
    private const string Name = "P111301PAINF001";

    private sealed class ReservationAdapter : IMutationGateway, IMutationJoinReservation, IMutationReceiptFinalizer
    {
        public required FixedClock Clock;
        public required string ConfigurationRoot;
        public JoinReservationReceipt? Current;
        public JoinReservationAuthorization? Authorization;
        public bool Inspected;
        public int Creates, Deletes, Joins, Inspections;
        public string Description => "Fixture réservation, aucun appel natif";
        private string ConfigurationStamp => JoinReservationStore.Digest(File.ReadAllBytes(Path.Combine(ConfigurationRoot, "cfg.json")));
        private JoinReservationReceipt NewReceipt(string name, string parent)
        {
            var operation = Guid.NewGuid().ToString("D");
            return new(1, "reservation-" + Guid.NewGuid().ToString("N"), operation, parent, [parent], Environment.MachineName,
                name, "example.local", "dc01.example.local", Ou, OuIdentity, Machine, JoinReservationStore.MarkerFor(operation),
                Identity, "reserved", false, "Fixture réservation conservée", Clock.GetUtcNow(), Clock.GetUtcNow());
        }
        public void Existing() => Current = NewReceipt(Name, "receipt-original");
        public IReadOnlyList<JoinReservationView> ListReservations() => Current is null ? [] : [new(Current, Inspected && Current.State == "reserved", Inspected && Current.State == "reserved")];
        public JoinReservationView InspectReservation(string id)
        {
            if (Current?.Id != id) throw new PestoException("reservation.missing", "Fixture missing");
            Inspections++; Inspected = true;
            return ListReservations().Single();
        }
        public JoinReservationPreparation PrepareReservation(string id, string action, string planId)
        {
            if (!Inspected || Current?.Id != id) throw new PestoException("reservation.evidence", "Fixture needs inspection");
            Authorization = new(new string('A', 64), id, new('b', 64), planId, action, Environment.MachineName, Current.Name,
                Current.Domain, Current.Dc, Current.TargetOu, Current.TargetOuGuid, Current.MachineId, Current.ComputerGuid,
                Current.Marker, Clock.GetUtcNow().AddMinutes(2), [new(Current.ParentReceiptId, new('a', 64))], ConfigurationStamp);
            return new(ListReservations().Single(), Authorization);
        }
        public JoinReservationView ReleaseReservation(JoinReservationAuthorization a)
        {
            Require(a, "release"); Deletes++;
            Current = Current! with { State = "released" }; Inspected = false; Authorization = null;
            return ListReservations().Single();
        }
        private void Require(JoinReservationAuthorization a, string action)
        {
            if (!ReferenceEquals(Authorization, a) || a.Action != action || a.ExpiresAt <= Clock.GetUtcNow() || a.ConfigurationSha256 != ConfigurationStamp)
                throw new PestoException("reservation.evidence", "Fixture grant changed");
        }
        public MutationOutcome Execute(MutationRequest request)
        {
            if (!request.ReservationRequired || request.ConfigurationSha256 != ConfigurationStamp)
                return new(MutationStatus.Failed, 96, "Fixture configuration changed", false);
            if (request.Reservation is { } a)
            {
                Require(a, "resumeJoin");
                if (request.ComputerGuid != Identity || request.Dc != a.Dc || request.NewName != a.Name)
                    throw new TestFailureException("Reserved join must retain exact GUID/DC/name");
                Authorization = null;
            }
            else { Creates++; Current = NewReceipt(request.NewName!, request.ReceiptId); }
            Joins++; Current = Current! with { State = "consumed" }; Inspected = false;
            return new(MutationStatus.PendingRestart, 10, "Fixture join accepted; manual restart", true, Identity);
        }
        public void PersistFinalReceipt(MutationRequest request, MutationOutcome outcome) { }
    }

    private sealed class World : IDisposable
    {
        public readonly FixedClock Clock = new();
        public readonly string Gp = Harness.IsolatedGpRoot();
        public readonly string Configuration;
        public readonly ReservationAdapter Mutation;
        public readonly IPestoBackend Backend;
        public World(bool existing = true)
        {
            Configuration = LiveTestConfig.Write(LiveTestConfig.NoRandom.Replace("\"Schema\": 1, \"MaxReaders\"", "\"Schema\": 1, \"ReserveNamesInAD\": true, \"MaxReaders\""));
            Mutation = new() { Clock = Clock, ConfigurationRoot = Configuration };
            if (existing) Mutation.Existing();
            var directory = new FakeGateway { ChildOus = { [Container] = ["Paris-Nord"] },
                Find = name => Mutation.Current is { } current && current.Name == name && current.State != "released"
                    ? new(name, null, Ou, null, Identity, "example.local", null, null, null, null, null) : null };
            Backend = Harness.Live(Configuration, directory, Mutation, Clock, Gp);
        }
        public JsonNode Prepare(string action)
        {
            var id = Mutation.Current!.Id;
            _ = Harness.Call(Backend, "reservations.inspect", new { id });
            return Harness.Call(Backend, "reservations.prepare", new { id, action });
        }
        public void Dispose()
        {
            Directory.Delete(Gp, true); Directory.Delete(Configuration, true);
        }
    }

    [Test]
    public void InitialJoinDisclosesReservationAndOnlyExactConfirmationCanCreate()
    {
        using var w = new World(existing: false);
        var preview = Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
        Check.True(Harness.Bool(plan, "reservationRequired"), "Effet création affiché dans le plan principal");
        Check.Equal(0, w.Mutation.Creates + w.Mutation.Joins, "Aperçu et préparation sans création ni join");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = "WRONG" }),
            "confirmation.invalid", "Confirmation exacte obligatoire");
        Check.Equal(0, w.Mutation.Creates, "Annulation ou confirmation erronée ne réserve rien");
        var receipt = Harness.Call(w.Backend, "operation.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });
        Check.Equal("pendingRestart", Harness.Str(receipt, "status"), "Jonction acceptée sans faux redémarrage");
        Check.Equal(1, w.Mutation.Creates, "Une création après confirmation");
        Check.Equal(0, w.Mutation.Deletes, "Aucun retrait automatique");
    }

    [Test]
    public void ListIsLocalAndAResumePlanOnlyExposesItsOpaquePlanAndImmutableScope()
    {
        using var w = new World();
        var list = Harness.Call(w.Backend, "reservations.list");
        Check.Equal(0, w.Mutation.Inspections, "Liste sans lecture AD");
        Check.False(Harness.Bool(Harness.Arr(list, "items")[0]!, "canResume"), "Pas d’autorisation héritée du fichier");
        Check.Pesto(() => Harness.Call(w.Backend, "reservations.prepare", new { id = w.Mutation.Current!.Id, action = "resumeJoin" }),
            "reservation.evidence", "Inspection explicite obligatoire");
        var plan = w.Prepare("resumeJoin");
        Check.Equal("live", Harness.Str(plan, "mode"), "Mode réel explicite");
        Check.Equal(w.Mutation.Current!.Id, Harness.Str(plan, "reservationId"), "Portée liée au reçu");
        Check.Equal(Name, Harness.Str(plan, "confirmationName"), "Nom exact visible avant confirmation");
        Check.False(plan.ToJsonString().Contains(Identity, StringComparison.Ordinal), "Aucun GUID d’autorité transmis au navigateur");
        Check.False(plan.ToJsonString().Contains(new string('A', 64), StringComparison.Ordinal), "Token natif non exposé");
        Check.Equal(0, w.Mutation.Creates + w.Mutation.Joins + w.Mutation.Deletes, "Préparation sans aucune mutation");
    }

    [Test]
    public void ResumeAndReleaseUseOnlyInternalPlansExactConfirmationAndSingleConsumption()
    {
        foreach (var action in new[] { "resumeJoin", "release" })
        {
            using var w = new World(); var plan = w.Prepare(action);
            var id = Harness.Str(plan, "planId");
            Check.Pesto(() => Harness.Call(w.Backend, "reservations.execute", new { planId = id, confirmationName = "other" }), "confirmation.invalid", "Mauvaise confirmation refusée");
            Check.Pesto(() => Harness.Call(w.Backend, "reservations.execute", new { planId = id, confirmationName = Name, computerGuid = Identity }), "invalid_arguments", "Le navigateur ne choisit jamais le GUID");
            var result = Harness.Call(w.Backend, "reservations.execute", new { planId = id, confirmationName = Name });
            Check.Equal(w.Mutation.Current!.Id, Harness.Str(result["reservation"]!, "id"), "Identité de résultat conservée");
            Check.Equal(0, w.Mutation.Creates, "La reprise ne recrée aucun compte");
            Check.Equal(action == "release" ? 1 : 0, w.Mutation.Deletes, "Suppression seulement sur plan release confirmé");
            Check.Equal(action == "resumeJoin" ? 1 : 0, w.Mutation.Joins, "Join seulement sur plan resume confirmé");
            Check.Pesto(() => Harness.Call(w.Backend, "reservations.execute", new { planId = id, confirmationName = Name }), "plan.consumed", "Aucun rejeu");
        }
    }

    [Test]
    public void ConfigurationChangeAfterReservationPlanRefusesEveryMutation()
    {
        using var w = new World(); var plan = w.Prepare("release");
        File.AppendAllText(Path.Combine(w.Configuration, "cfg.json"), "\n");
        Check.Pesto(() => Harness.Call(w.Backend, "reservations.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Name }),
            "config.changed", "Empreinte exacte exigée après préparation");
        Check.Equal(0, w.Mutation.Deletes + w.Mutation.Joins + w.Mutation.Creates, "Aucune mutation sur configuration remplacée");
    }

    [Test]
    public void ReservationPlanExpiresWithoutCreationDeletionOrJoin()
    {
        using var w = new World(); var plan = w.Prepare("release"); w.Clock.Advance(TimeSpan.FromMinutes(3));
        Check.Pesto(() => Harness.Call(w.Backend, "reservations.execute", new { planId = Harness.Str(plan, "planId"), confirmationName = Name }),
            "plan.stale", "Expiration stricte");
        Check.Equal(0, w.Mutation.Creates + w.Mutation.Deletes + w.Mutation.Joins, "Aucune action différée automatique");
    }
}

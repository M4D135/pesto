using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class LiveNameReservationTests
{
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local", Ou = "OU=Paris-Nord," + Container;
    private const string Computer = "P111301PAINF009", Second = "P111301PAINF010";

    private sealed class Mutation(FixedClock clock, string root) : IMutationGateway, IMutationNameReservations, IFixtureEntraPreparation
    {
        public string Description => "fixture baux mémoire, aucun partage";
        public readonly List<string> Reserved = [], Released = [];
        public readonly List<MutationRequest> Requests = [];
        public string[] Foreign = [];
        public int Reads, Verifications;
        public bool Collision, Changed;
        public TimeSpan LeaseLifetime = TimeSpan.FromMinutes(2);
        public IReadOnlyList<string> OtherReservedNames(string domain) { Reads++; return Foreign; }
        public SharedNameReservationProof? ReservePreviewName(string domain, string name, string previewId, string configurationSha256)
        {
            Reserved.Add(name);
            if (Collision) throw new PestoException("names.reservation_held", "Une autre session vient de prendre le nom.");
            return new(root, domain, name, "11111111111111111111111111111111", previewId, configurationSha256,
                new string('a', 64), clock.GetUtcNow().Add(LeaseLifetime), "name-intent-" + Guid.NewGuid().ToString("N"));
        }
        public void VerifyPreviewName(SharedNameReservationProof proof, string configurationSha256)
        {
            Verifications++;
            if (Changed) throw new PestoException("names.reservation_changed", "Le propriétaire ou les octets ont changé.");
        }
        public void ReleasePreviewName(SharedNameReservationProof proof) => Released.Add(proof.Name);
        public MutationOutcome Execute(MutationRequest request)
        { Requests.Add(request); return new(MutationStatus.Failed, 96, "Fixture sans envoi", false); }
    }

    private sealed record World(IPestoBackend Backend, Mutation Mutation, FixedClock Clock, string ConfigRoot, string Share);
    private static World Create(bool coordinated = true)
    {
        var clock = new FixedClock();
        var share = Path.Combine(Path.GetTempPath(), "pesto-share-not-created-" + Guid.NewGuid().ToString("N"));
        var configuration = JsonNode.Parse(LiveTestConfig.NoRandom)!;
        if (coordinated) configuration["POLICY"]!["CoordinationRoot"] = share;
        var root = LiveTestConfig.Write(configuration.ToJsonString());
        var mutation = new Mutation(clock, share);
        var directory = new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] }, ScopeNames = [Computer, Second],
            Find = name => name is Computer or Second ? new(name, null, Ou, null, name == Computer ? "11111111-1111-1111-1111-111111111111" : "22222222-2222-2222-2222-222222222222", "example.local", null, null, null, null, null) : null
        };
        return new(Harness.Live(root, directory, mutation, clock), mutation, clock, root, share);
    }
    private static JsonNode Preview(World w, string computer = Computer) => Harness.Call(w.Backend, "names.preview", new { type = "P", site = "PA", service = "INF", computer });
    private static JsonNode Prepare(World w, JsonNode preview, string computer = Computer) => Harness.Call(w.Backend, "operation.prepare",
        new { kind = "rename", computer, previewId = Harness.Str(preview, "previewId") });
    private static JsonNode Execute(World w, JsonNode plan) => Harness.Call(w.Backend, "operation.execute",
        new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });

    [Test]
    public void PreviewFiltersForeignLeasesAndDisclosesOnlyItsExpiration()
    {
        var world = Create();
        try
        {
            world.Mutation.Foreign = ["P111301PAINF001"];
            var preview = Preview(world);
            Check.Equal("P111301PAINF002", Harness.Str(preview, "name"), "Le nom réservé par un autre opérateur est écarté avant proposition");
            Check.Equal(Harness.Str(preview, "name"), world.Mutation.Reserved.Single(), "Le candidat affiché est celui acquis, aucune substitution cachée");
            Check.Equal(Harness.Str(preview, "expiresAt"), Harness.Str(preview, "reservationExpiresAt"), "L’aperçu ne peut dépasser son bail");
            Check.False(preview.ToJsonString().Contains(world.Share, StringComparison.Ordinal), "Chemin et autorité interne non exposés au web");
            Check.False(Directory.Exists(world.Share), "Fixture strictement en mémoire sans vrai partage");
        }
        finally { Directory.Delete(world.ConfigRoot, true); }
    }

    [Test]
    public void LeaseIsVerifiedAtPreparationAndExecutionAndCarriedIntoNativeRequest()
    {
        var world = Create();
        try
        {
            var plan = Prepare(world, Preview(world));
            Check.Equal(1, world.Mutation.Verifications, "Vérification fraîche au plan");
            Execute(world, plan);
            Check.Equal(2, world.Mutation.Verifications, "Vérification après confirmation avant envoi");
            var request = world.Mutation.Requests.Single();
            Check.NotNull(request.NameReservation, "La preuve reste interne mais atteint le natif");
            Check.Equal(request.NewName, request.NameReservation!.Name, "Même nom explicitement confirmé");
            Check.Equal(request.ConfigurationSha256, request.NameReservation.ConfigSha256, "Même configuration figée");
            Check.False(plan.ToJsonString().Contains("name-intent-", StringComparison.Ordinal), "Aucune autorisation fabriquable depuis le plan web");
        }
        finally { Directory.Delete(world.ConfigRoot, true); }
    }

    [Test]
    public void ChangedOrExpiredLeaseRefusesWithoutRetargetingOrSending()
    {
        var world = Create();
        try
        {
            var plan = Prepare(world, Preview(world));
            world.Mutation.Changed = true;
            Check.Pesto(() => Execute(world, plan), "names.reservation_changed", "Autre propriétaire ou hash changé bloque");
            Check.Equal(1, world.Mutation.Reserved.Count, "Aucun autre nom acquis après confirmation");
            Check.Equal(0, world.Mutation.Requests.Count, "Aucun envoi");
            world.Mutation.Changed = false;
            world.Clock.Advance(TimeSpan.FromMinutes(3));
            Check.Pesto(() => Execute(world, plan), "plan.stale", "Le plan expire avec le bail");
            Check.Equal(0, world.Mutation.Requests.Count, "Un bail expiré n’est jamais supposé renouvelé");
        }
        finally { Directory.Delete(world.ConfigRoot, true); }
    }

    [Test]
    public void AtomicLeaseConflictStopsThePreviewAfterOneCandidate()
    {
        var world = Create();
        try
        {
            world.Mutation.Collision = true;
            Check.Pesto(() => Preview(world), "names.reservation_held", "Course avec autre session explicite");
            Check.Equal(1, world.Mutation.Reserved.Count, "Pas de boucle silencieuse de réservation sur d’autres noms");
            Check.Equal(0, world.Mutation.Requests.Count, "Aucune mutation après collision");
        }
        finally { Directory.Delete(world.ConfigRoot, true); }
    }

    [Test]
    public void QueueKeepsLeaseAuthorityAndUsesTheEarliestExpiration()
    {
        var world = Create();
        try
        {
            var first = Preview(world);
            Harness.Call(world.Backend, "queue.add", new { kind = "rename", computer = Computer, previewId = Harness.Str(first, "previewId") });
            world.Mutation.LeaseLifetime = TimeSpan.FromMinutes(1);
            var second = Preview(world, Second);
            var queue = Harness.Call(world.Backend, "queue.add", new { kind = "rename", computer = Second, previewId = Harness.Str(second, "previewId") });
            var batch = Harness.Call(world.Backend, "queue.prepare");
            Check.Equal(Harness.Str(second, "expiresAt"), Harness.Str(batch, "expiresAt"), "Expiration commune bornée par le bail le plus proche");
            Check.Equal(4, world.Mutation.Verifications, "Les deux ajouts puis les deux lignes préparées vérifient leurs baux");
            Harness.Call(world.Backend, "queue.remove", new { id = Harness.Str(Harness.Arr(queue, "items")[0]!, "id") });
            Check.Equal(1, world.Mutation.Released.Count, "Retrait explicite d’une ligne libère seulement sa preuve non envoyée");
            Check.Pesto(() => Harness.Call(world.Backend, "queue.execute", new { batchId = Harness.Str(batch, "batchId"), confirmed = true }), "batch.stale", "Aucun ancien lot après retrait");
            Check.Equal(0, world.Mutation.Requests.Count, "Aucune mutation implicite");
        }
        finally { Directory.Delete(world.ConfigRoot, true); }
    }

    [Test]
    public void DisabledCoordinationNeverCallsTheLeaseProvider()
    {
        var world = Create(coordinated: false);
        try
        {
            var plan = Prepare(world, Preview(world)); Execute(world, plan);
            Check.Equal(0, world.Mutation.Reads, "Aucun snapshot partagé non demandé");
            Check.Equal(0, world.Mutation.Reserved.Count, "Aucun bail non demandé");
            Check.Equal(0, world.Mutation.Verifications, "Aucune vérification partagée non demandée");
            Check.Null(world.Mutation.Requests.Single().NameReservation, "Pas de preuve fictive");
        }
        finally { Directory.Delete(world.ConfigRoot, true); }
    }
}

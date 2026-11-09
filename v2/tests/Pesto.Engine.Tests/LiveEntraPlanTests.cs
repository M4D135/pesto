using Pesto.Core;

namespace Pesto.Engine.Tests;

internal sealed class LiveEntraPlanTests
{
    private const string Computer = "P111301PAINF009", Identity = "11111111-1111-1111-1111-111111111111";
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local", Ou = "OU=Paris-Nord," + Container;
    private sealed class Mutation(FixedClock clock) : IMutationGateway, IMutationEntraPreparation
    {
        public string Description => "fixture Entra, aucun processus";
        public int Sends;
        public MutationRequest? Last;
        public EntraRenameAuthorization PrepareEntra(EntraPreparationRequest request) => new("fixture-" + Guid.NewGuid().ToString("N"),
            request, "hybrid", "HybridOnly", "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", clock.GetUtcNow(), clock.GetUtcNow().AddMinutes(2));
        public MutationOutcome Execute(MutationRequest request) { Sends++; Last = request; return new(MutationStatus.Failed, 96, "Fixture sans écriture", false); }
    }
    private sealed class NoProvider : IMutationGateway
    {
        public string Description => "fixture sans lecteur Entra";
        public MutationOutcome Execute(MutationRequest request) => throw new TestFailureException("no provider may send");
    }
    private static (IPestoBackend Backend, Mutation Gateway, FixedClock Clock) World()
    {
        var clock = new FixedClock(); var mutation = new Mutation(clock);
        return (Backend(mutation, clock), mutation, clock);
    }
    private static IPestoBackend Backend(IMutationGateway mutation, FixedClock clock) =>
        Harness.Live(LiveTestConfig.Write(LiveTestConfig.NoRandom), new FakeGateway
        {
            ChildOus = { [Container] = ["Paris-Nord"] }, ScopeNames = [Computer],
            Find = name => name == Computer ? new(Computer, null, Ou, null, Identity, "example.local", null, null, null, null, null) : null
        }, mutation, clock);
    private static string Preview(IPestoBackend backend) => Harness.Str(Harness.Call(backend, "names.preview",
        new { computer = Computer, type = "P", site = "PA", service = "INF" }), "previewId");

    [Test]
    public void HybridPlanIsVisibleBeforeConsentAndDirectApiCannotSkipConsent()
    {
        var w = World();
        var plan = Harness.Call(w.Backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Preview(w.Backend) });
        Check.True(Harness.Bool(plan, "entraLeaveRequired"), "leave disclosed before send");
        Check.Equal("hybrid", Harness.Str(plan, "entraState"), "actual observation disclosed");
        Check.Equal("HybridOnly", Harness.Str(plan, "entraPolicy"), "permission disclosed");
        Check.Equal(0, w.Gateway.Sends, "preparation never executes");
        var planId = Harness.Str(plan, "planId"); var confirmationName = Harness.Str(plan, "confirmationName");
        Check.Pesto(() => Harness.Call(w.Backend, "operation.execute", new { planId, confirmationName }), "entra.confirmation", "name alone cannot authorize leave");
        Check.Equal(0, w.Gateway.Sends, "missing consent sends nothing");
        Harness.Call(w.Backend, "operation.execute", new { planId, confirmationName, entraLeaveConfirmed = true });
        Check.Equal(1, w.Gateway.Sends, "confirmed plan sent once");
        Check.True(w.Gateway.Last!.EntraLeaveConfirmed && w.Gateway.Last.Entra!.LeaveRequired, "internal authorization and consent reach native request");
    }

    [Test]
    public void BatchRequiresEntraConsentForItsListedHybridTargets()
    {
        var w = World();
        Harness.Call(w.Backend, "queue.add", new { kind = "rename", computer = Computer, previewId = Preview(w.Backend) });
        var batch = Harness.Call(w.Backend, "queue.prepare");
        Check.True(Harness.Bool(Harness.Arr(batch, "items")[0]!, "entraLeaveRequired"), "each batch target discloses leave");
        var batchId = Harness.Str(batch, "batchId");
        Check.Pesto(() => Harness.Call(w.Backend, "queue.execute", new { batchId, confirmed = true }), "entra.confirmation", "generic batch consent insufficient");
        Check.Equal(0, w.Gateway.Sends, "batch without leave consent sends nothing");
        Harness.Call(w.Backend, "queue.execute", new { batchId, confirmed = true, entraLeaveConfirmed = true });
        Check.Equal(1, w.Gateway.Sends, "native send only after both confirmations");
    }

    [Test]
    public void MissingEntraReaderCannotPrepareAnExecutableRename()
    {
        var backend = Backend(new NoProvider(), new FixedClock());
        Check.Pesto(() => Harness.Call(backend, "operation.prepare", new { kind = "rename", computer = Computer, previewId = Preview(backend) }),
            "entra.unavailable", "reader is required for a real rename plan");
    }
}

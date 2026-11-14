using System.Diagnostics;
using System.Text.Json;
using Pesto.Core;

namespace Pesto.Bridge.Tests;

/// <summary>Backend that blocks inside an operation so the dispatcher's admission, mutation and duplicate guards are observable.</summary>
internal sealed class GateBackend : IPestoBackend
{
    private readonly ManualResetEventSlim gate = new(false);
    private int inflight;
    public int MaxConcurrent { get; private set; }
    public int InFlight => Volatile.Read(ref inflight);

    public void Release() => gate.Set();

    public Task<object?> InvokeAsync(string operation, JsonElement args, CancellationToken cancellationToken = default)
    {
        if (operation is "operation.prepare" or "queue.prepare" or "operation.execute" or "directory.search" or "receipts.reconcile" or "receipts.prepareMove"
            or "receipts.prepareAcknowledgement" or "receipts.acknowledge" or "receipts.prepareRestart" or "receipts.restart"
            or "reservations.inspect" or "reservations.prepare" or "reservations.execute"
            or "coordination.inspect" or "coordination.prepare" or "coordination.apply")
        {
            var current = Interlocked.Increment(ref inflight);
            lock (this) MaxConcurrent = Math.Max(MaxConcurrent, current);
            gate.Wait(cancellationToken);
            Interlocked.Decrement(ref inflight);
        }
        return Task.FromResult<object?>(PestoJson.Element(new { ok = true }));
    }
}

internal sealed class BridgeDispatcherTests
{
    private static string Msg(string id, string op, object? args = null) =>
        JsonSerializer.Serialize(new { id, op, args = args ?? new { } }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });

    private static string Code(string json) => JsonDocument.Parse(json).RootElement.GetProperty("error").GetProperty("code").GetString()!;
    private static string Kind(string json) => JsonDocument.Parse(json).RootElement.GetProperty("kind").GetString()!;

    private static void WaitUntil(Func<bool> condition, string what)
    {
        var watch = Stopwatch.StartNew();
        while (!condition() && watch.ElapsedMilliseconds < 3000) Thread.SpinWait(2000);
        if (!condition()) throw new TestFailureException("Délai dépassé en attendant : " + what);
    }

    [Test]
    public async Task UnknownOperationIsRejected()
    {
        var dispatcher = new BridgeDispatcher(new GateBackend());
        var response = await dispatcher.DispatchAsync(Msg("r1", "host.run", new { command = "calc" }));
        Check.Equal("error", Kind(response), "Réponse d’erreur");
        Check.Equal("operation.unknown", Code(response), "Opération hors contrat refusée");
    }

    [Test]
    public async Task MutationsAreSerialized()
    {
        var backend = new GateBackend();
        var dispatcher = new BridgeDispatcher(backend);
        var first = dispatcher.DispatchAsync(Msg("m1", "operation.execute", new { planId = "p", confirmationName = "N" }));
        WaitUntil(() => backend.InFlight >= 1, "première mutation en cours");
        var second = await dispatcher.DispatchAsync(Msg("m2", "operation.execute", new { planId = "p", confirmationName = "N" }));
        Check.Equal("operation.busy", Code(second), "Une seconde mutation est refusée, pas mise en file");
        backend.Release();
        Check.Equal("result", Kind(await first), "La première mutation aboutit");
        Check.Equal(1, backend.MaxConcurrent, "Jamais deux mutations en parallèle");
    }

    [Test]
    public async Task ReceiptReconciliationIsSerializedWithMutationsAndHasClosedArguments()
    {
        var backend = new GateBackend();
        var dispatcher = new BridgeDispatcher(backend);
        var invalid = await dispatcher.DispatchAsync(Msg("invalid", "receipts.reconcile", new { id = "receipt-1", force = true }));
        Check.Equal("arguments.invalid", Code(invalid), "Aucun force ou contournement admis");
        var first = dispatcher.DispatchAsync(Msg("verify", "receipts.reconcile", new { id = "receipt-1" }));
        WaitUntil(() => backend.InFlight >= 1, "vérification en cours");
        var second = await dispatcher.DispatchAsync(Msg("mutate", "operation.execute", new { planId = "p", confirmationName = "N" }));
        Check.Equal("operation.busy", Code(second), "Aucune mutation concurrente à la vérification persistante");
        backend.Release();
        Check.Equal("result", Kind(await first), "Vérification explicitement demandée admise");
    }

    [Test]
    public async Task RemainingMovePreparationIsSerializedAndOnlyAcceptsReceiptId()
    {
        var backend = new GateBackend();
        var dispatcher = new BridgeDispatcher(backend);
        var invalid = await dispatcher.DispatchAsync(Msg("invalid-move", "receipts.prepareMove", new { id = "receipt-parent", targetOU = "OU=Other" }));
        Check.Equal("arguments.invalid", Code(invalid), "La destination reste liée au reçu parent");
        var first = dispatcher.DispatchAsync(Msg("remaining", "receipts.prepareMove", new { id = "receipt-parent" }));
        WaitUntil(() => backend.InFlight >= 1, "préparation liée en cours");
        var second = await dispatcher.DispatchAsync(Msg("duplicate-remaining", "receipts.prepareMove", new { id = "receipt-parent" }));
        Check.Equal("operation.busy", Code(second), "Aucune préparation native concurrente");
        backend.Release();
        Check.Equal("result", Kind(await first), "Préparation explicite admise");
    }

    [Test]
    public async Task DuplicateRequestIdIsRejected()
    {
        var backend = new GateBackend();
        var dispatcher = new BridgeDispatcher(backend);
        var first = dispatcher.DispatchAsync(Msg("dup", "operation.execute", new { planId = "p", confirmationName = "N" }));
        WaitUntil(() => backend.InFlight >= 1, "requête en cours");
        var second = await dispatcher.DispatchAsync(Msg("dup", "operation.execute", new { planId = "p", confirmationName = "N" }));
        Check.Equal("request.duplicate", Code(second), "Un identifiant déjà en cours est refusé");
        backend.Release();
        await first;
    }

    [Test]
    public async Task ReservationAndCoordinationActionsAreClosedAndSerialized()
    {
        var cases = new (string Op, object Args, object Invalid)[]
        {
            ("reservations.inspect", new { id = "reservation-1" }, new { id = "reservation-1", path = "other.json" }),
            ("reservations.prepare", new { id = "reservation-1", action = "release" }, new { id = "reservation-1", action = "release", objectGuid = Guid.NewGuid() }),
            ("reservations.execute", new { planId = "plan-1", confirmationName = "CANARY" }, new { planId = "plan-1", confirmationName = "CANARY", force = true }),
            ("coordination.inspect", new { }, new { root = "C:\\Other" }),
            ("coordination.prepare", new { }, new { domain = "other.local" }),
            ("coordination.apply", new { planId = "plan-1", confirmed = true }, new { planId = "plan-1", confirmed = true, root = "C:\\Other" })
        };
        foreach (var (op, args, invalid) in cases)
        {
            var backend = new GateBackend(); var dispatcher = new BridgeDispatcher(backend);
            Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg("invalid", op, invalid))), op + " refuse une portée fournie par l’appelant");
            var first = dispatcher.DispatchAsync(Msg("first", op, args));
            WaitUntil(() => backend.InFlight == 1, op + " en cours");
            var second = await dispatcher.DispatchAsync(Msg("second", "operation.execute", new { planId = "p", confirmationName = "N" }));
            Check.Equal("operation.busy", Code(second), op + " bloque les écritures concurrentes");
            backend.Release(); Check.Equal("result", Kind(await first), op + " admise explicitement");
        }
    }

    [Test]
    public async Task ReceiptDecisionsAndNativePreparationsAreClosedAndSerialized()
    {
        var cases = new (string Op, object Args, object Invalid)[]
        {
            ("receipts.prepareAcknowledgement", new { id = "receipt-1" }, new { id = "receipt-1", resultCode = 0 }),
            ("receipts.acknowledge", new { planId = "p", confirmationName = "CANARY", reason = "Contrôle manuel consigné" },
                new { planId = "p", confirmationName = "CANARY", reason = "Motif", author = "admin" }),
            ("receipts.prepareRestart", new { id = "receipt-1" }, new { id = "receipt-1", target = "OTHER" }),
            ("receipts.restart", new { planId = "p", confirmationName = "CANARY" }, new { planId = "p", confirmationName = "CANARY", force = true }),
            ("operation.prepare", new { kind = "rename", computer = "CANARY", previewId = "p" }, new { kind = "rename", entraLeaveRequired = false }),
            ("queue.prepare", new { }, new { force = true })
        };
        foreach (var (op, args, invalid) in cases)
        {
            var backend = new GateBackend(); var dispatcher = new BridgeDispatcher(backend);
            Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg("invalid", op, invalid))), op + " refuse toute preuve ou portée fournie par le navigateur");
            var first = dispatcher.DispatchAsync(Msg("first", op, args));
            WaitUntil(() => backend.InFlight == 1, op + " engagée");
            Check.Equal("operation.busy", Code(await dispatcher.DispatchAsync(Msg("second", "operation.execute", new { planId = "p", confirmationName = "CANARY" }))), "Aucune mutation concurrente");
            backend.Release(); Check.Equal("result", Kind(await first), "Action explicite admise");
        }
    }

    [Test]
    public async Task AcknowledgementReasonIsBoundedAndHasNoControlCharacters()
    {
        var backend = new GateBackend(); backend.Release(); var dispatcher = new BridgeDispatcher(backend);
        foreach (var reason in new[] { "", "ab", "   ", new string('a', 501), "valide\nmais contrôle", "valide\0suite" })
            Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg(Guid.NewGuid().ToString("N"), "receipts.acknowledge",
                new { planId = "p", confirmationName = "CANARY", reason }))), "Motif invalide refusé avant moteur");
        Check.Equal("result", Kind(await dispatcher.DispatchAsync(Msg("valid-reason", "receipts.acknowledge",
            new { planId = "p", confirmationName = "CANARY", reason = new string('a', 500) }))), "Borne 500 admise");
    }

    [Test]
    public async Task EntraConsentAndPrecreatedSelectionCannotInjectNativeAuthority()
    {
        var backend = new GateBackend(); backend.Release(); var dispatcher = new BridgeDispatcher(backend);
        Check.Equal("result", Kind(await dispatcher.DispatchAsync(Msg("entra-confirm", "operation.execute",
            new { planId = "p", confirmationName = "CANARY", entraLeaveConfirmed = true }))), "Confirmation explicite booléenne admise");
        Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg("entra-string", "operation.execute",
            new { planId = "p", confirmationName = "CANARY", entraLeaveConfirmed = "true" }))), "Pas de conversion de chaîne en consentement");
        Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg("entra-proof", "operation.execute",
            new { planId = "p", confirmationName = "CANARY", entraLeaveConfirmed = true, entraState = "adOnly" }))), "La preuve native ne vient pas du navigateur");
        Check.Equal("result", Kind(await dispatcher.DispatchAsync(Msg("precreated", "join.precreated.preview", new { name = "CANARY" }))), "Sélection exacte pour lecture");
        Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg("precreated-guid", "join.precreated.preview",
            new { name = "CANARY", computerGuid = Guid.NewGuid(), allowExisting = true }))), "GUID et autorisation sont natifs");
    }

    [Test]
    public async Task PolicySettingsRejectMalformedDuplicateAndUnboundedGroups()
    {
        var dispatcher = new BridgeDispatcher(new GateBackend());
        var settings = new Dictionary<string, object?>
        {
            ["domain"] = "example.local", ["prefix"] = "111301", ["rootOu"] = "OU=Postes,DC=example,DC=local",
            ["namingPattern"] = "{type}{prefix}{site}{service}{number:3}", ["production"] = true, ["randomNames"] = true,
            ["sites"] = Array.Empty<object>(), ["coordinationRoot"] = "C:\\Coordination", ["coordinationRequired"] = true,
            ["reserveNamesInAd"] = true, ["auditEventLogEnabled"] = true, ["blockJoinOnClockSkew"] = true,
            ["excludedGroupGuids"] = new[] { "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }
        };
        Check.Equal("result", Kind(await dispatcher.DispatchAsync(Msg("valid", "configuration.previewSettings", settings))), "Politiques typées acceptées pour aperçu");
        foreach (var invalid in new object[] { "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", new[] { "not-a-guid" },
            new[] { Guid.Empty.ToString("D") }, new[] { "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" },
            Enumerable.Range(0, 201).Select(_ => Guid.NewGuid().ToString("D")).ToArray() })
        {
            settings["excludedGroupGuids"] = invalid;
            Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg(Guid.NewGuid().ToString("N"), "configuration.previewSettings", settings))), "Liste de groupes invalide refusée avant le backend");
        }
        settings["excludedGroupGuids"] = Array.Empty<string>(); settings["reserveNamesInAd"] = "true";
        Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg("typed", "configuration.previewSettings", settings))), "Booléen strict requis");
        settings["reserveNamesInAd"] = true; settings["force"] = true;
        Check.Equal("arguments.invalid", Code(await dispatcher.DispatchAsync(Msg("closed", "configuration.previewSettings", settings))), "Aucun contournement de politique");
    }

    [Test]
    public async Task ReadsMayRunConcurrently()
    {
        var backend = new GateBackend();
        var dispatcher = new BridgeDispatcher(backend);
        var reads = new[]
        {
            dispatcher.DispatchAsync(Msg("a", "directory.search", new { query = "x" })),
            dispatcher.DispatchAsync(Msg("b", "directory.search", new { query = "y" })),
            dispatcher.DispatchAsync(Msg("c", "directory.search", new { query = "z" })),
        };
        WaitUntil(() => backend.InFlight >= 2, "deux lectures en parallèle");
        backend.Release();
        var responses = await Task.WhenAll(reads);
        foreach (var response in responses) Check.Equal("result", Kind(response), "Lecture réussie");
        Check.True(backend.MaxConcurrent >= 2, "Les lectures ne sont pas sérialisées");
    }
}

using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class JoinClockTests
{
    private const string Dc = "dc01.example.local";
    private sealed class Reader : IClockSkewReader
    {
        public int Reads;
        public double? Offset;
        public bool Throw;
        public string? ServerOverride;
        public DateTimeOffset Now;
        public ClockSkewObservation ReadClockSkew(string server)
        {
            Reads++;
            if (Throw) throw new IOException("lecture interrompue");
            return new(ServerOverride ?? server, Now, Offset);
        }
    }
    private sealed class Mutation(Reader reader) : IMutationGateway, IClockSkewReader
    {
        public string Description => "fixture horloge sans processus";
        public int Sends;
        public ClockSkewObservation ReadClockSkew(string server) => reader.ReadClockSkew(server);
        public MutationOutcome Execute(MutationRequest request)
        { Sends++; return new(MutationStatus.Failed, 96, "Fixture : mutation non envoyée.", false); }
    }
    private static (IPestoBackend Backend, Reader Reader, Mutation Mutation, string Root) World(bool enabled = true)
    {
        var clock = new FixedClock();
        var reader = new Reader { Now = clock.GetUtcNow() };
        var mutation = new Mutation(reader);
        var config = JsonNode.Parse(LiveTestConfig.Production)!;
        config["POLICY"]!["BlockJoinOnClockSkew"] = enabled;
        var root = LiveTestConfig.Write(config.ToJsonString());
        var gateway = new FakeGateway { ChildOus = { ["OU=SITES,OU=Postes,DC=example,DC=local"] = ["Paris-Nord"] } };
        return (Harness.Live(root, gateway, mutation, clock), reader, mutation, root);
    }
    private static JsonNode Prepare(IPestoBackend backend)
    {
        var preview = Harness.Call(backend, "names.preview", new { type = "P", site = "PA", service = "INF" });
        return Harness.Call(backend, "operation.prepare", new { kind = "join", previewId = Harness.Str(preview, "previewId") });
    }
    private static JsonNode Execute(IPestoBackend backend, JsonNode plan) => Harness.Call(backend, "operation.execute",
        new { planId = Harness.Str(plan, "planId"), confirmationName = Harness.Str(plan, "confirmationName") });

    [Test]
    public void OnlyFiniteMeasuredAbsoluteSkewOfAtLeastThreeHundredBlocks()
    {
        var clock = new FixedClock();
        var reader = new Reader { Now = clock.GetUtcNow() };
        foreach (var value in new[] { -300d, 300d, -600d, 600d })
        {
            reader.Offset = value;
            Check.True(JoinClockGuard.Observe(reader, Dc, clock).Blocked, "Seuil V1 inclusif, signe ignoré");
        }
        foreach (var value in new[] { -299.999, 299.999, 0 })
        {
            reader.Offset = value;
            var observation = JoinClockGuard.Observe(reader, Dc, clock);
            Check.False(observation.Blocked, "Une mesure inférieure au seuil autorise");
            Check.Equal("observed", observation.State, "Mesure numérique réelle");
        }
        foreach (var value in new double?[] { null, double.NaN, double.PositiveInfinity, double.NegativeInfinity })
        {
            reader.Offset = value;
            var observation = JoinClockGuard.Observe(reader, Dc, clock);
            Check.False(observation.Blocked, "L’inconnu avertit, il ne bloque pas par défaut");
            Check.Equal("warning", observation.State, "Jamais zéro supposé");
        }
    }

    [Test]
    public void StripchartParsingAcceptsSignedDecimalAndRejectsAmbiguousOrFailedResponses()
    {
        var now = new FixedClock().GetUtcNow();
        foreach (var (text, expected) in new[] { ("10:45:00, +299.125s\r\n", 299.125), ("10:45:00, -300,500s\r\n", -300.5) })
            Check.Equal<double?>(expected, JoinClockGuard.Parse(Dc, 0, text, now).OffsetSeconds, "Format stripchart V1 point ou virgule");
        foreach (var text in new[] { "", "10:45:00, NaNs", "10:45:00, 300s", "10:45:00, +1s\n10:45:01, +2s", "erreur +300s", new string('x', 65537) })
            Check.Null(JoinClockGuard.Parse(Dc, 0, text, now).OffsetSeconds, "Sortie incertaine sans mesure inventée");
        Check.Null(JoinClockGuard.Parse(Dc, 1, "10:45:00, +600s", now).OffsetSeconds, "Un code d’échec ne fournit pas de preuve numérique");
    }

    [Test]
    public void MissingReaderDcMismatchStaleObservationAndExceptionRemainWarnings()
    {
        var clock = new FixedClock();
        var reader = new Reader { Now = clock.GetUtcNow(), Offset = 900 };
        Check.False(JoinClockGuard.Observe(null, Dc, clock).Blocked, "Lecteur absent = avertissement V1");
        Check.False(JoinClockGuard.Observe(reader, null, clock).Blocked, "Aucun changement de DC automatique");
        Check.Equal(0, reader.Reads, "Aucun appel sans contrôleur sélectionné");
        reader.ServerOverride = "other.example.local";
        Check.Equal("warning", JoinClockGuard.Observe(reader, Dc, clock).State, "Pas de mesure d’un autre contrôleur");
        reader.ServerOverride = null; reader.Now = clock.GetUtcNow().AddMinutes(-1);
        Check.Equal("warning", JoinClockGuard.Observe(reader, Dc, clock).State, "Une ancienne mesure n’est pas une preuve actuelle");
        reader.Throw = true;
        var result = JoinClockGuard.Observe(reader, Dc, clock);
        Check.False(result.Blocked, "Échec de lecture autorise avec avertissement");
        Check.Contains("Aucune correction automatique", result.Message, "Jamais de resynchronisation implicite");
    }

    [Test]
    public void DisabledPolicyDoesNotReadClockAtPreparationOrExecution()
    {
        var world = World(enabled: false);
        try
        {
            world.Reader.Offset = 900;
            var plan = Prepare(world.Backend);
            Execute(world.Backend, plan);
            Check.Equal(0, world.Reader.Reads, "Désactivation V1 ne lance aucune sonde");
            Check.Equal(1, world.Mutation.Sends, "Pas de blocage fictif dû à une mesure non demandée");
        }
        finally { Directory.Delete(world.Root, true); }
    }

    [Test]
    public void ExcessiveSkewPreventsPlanAndLateIncreasePreventsSending()
    {
        var world = World();
        try
        {
            world.Reader.Offset = -300;
            Check.Pesto(() => Prepare(world.Backend), "policy.clock_skew", "Blocage dès préparation");
            Check.Equal(0, world.Mutation.Sends, "Aucun envoi avant confirmation");
            world.Reader.Offset = 299;
            var plan = Prepare(world.Backend);
            world.Reader.Offset = 300;
            Check.Pesto(() => Execute(world.Backend, plan), "policy.clock_skew", "Relecture après confirmation, avant toute mutation");
            Check.Equal(0, world.Mutation.Sends, "Aucun envoi si l’écart a augmenté");
            var diagnostic = Harness.Arr(Harness.Call(world.Backend, "diagnostics.read"), "checks").Single(c => Harness.Str(c!, "label") == "Horloge de jonction")!;
            Check.Equal("warn", Harness.Str(diagnostic, "state"), "Blocage visible dans les diagnostics");
            Check.Contains("300 s", Harness.Str(diagnostic, "detail"), "Motif numérique, pas une supposition");
        }
        finally { Directory.Delete(world.Root, true); }
    }

    [Test]
    public void UnknownClockIsVisibleInPlanAndDiagnosticsAndDoesNotInventMutationSuccess()
    {
        var world = World();
        try
        {
            var plan = Prepare(world.Backend);
            Check.True(Harness.Arr(plan, "warnings").Any(w => w!.GetValue<string>().Contains("écart inconnu", StringComparison.Ordinal)), "Avertissement affiché avant confirmation");
            var receipt = Execute(world.Backend, plan);
            Check.Equal(2, world.Reader.Reads, "Préparation puis relecture finale distinctes");
            Check.Equal(1, world.Mutation.Sends, "L’inconnu n’est pas un blocage ajouté à V1");
            Check.Equal("refused", Harness.Str(receipt, "status"), "Résultat de l’adaptateur conservé, aucun faux succès");
            var diagnostic = Harness.Arr(Harness.Call(world.Backend, "diagnostics.read"), "checks").Single(c => Harness.Str(c!, "label") == "Horloge de jonction")!;
            Check.Contains("écart inconnu", Harness.Str(diagnostic, "detail"), "Avertissement encore consultable après tentative");
        }
        finally { Directory.Delete(world.Root, true); }
    }

    [Test]
    public void NativeReaderIsOneBoundedReadOnAnExactDcWithoutClockRepair()
    {
        Check.Equal("/stripchart,/computer:dc01.example.local,/dataonly,/samples:1", string.Join(',', WindowsClockSkewReader.ArgumentsFor(Dc)), "Arguments V1 en ArgumentList, un seul échantillon");
        Check.Equal(6000, WindowsClockSkewReader.TimeoutMilliseconds, "Borne V1 de six secondes");
        foreach (var invalid in new[] { "/resync", "dc /resync", "dc\n", "dc\r\n", "dc\0", " dc", "dc ", "", "-server" })
        {
            var refused = false;
            try { WindowsClockSkewReader.ArgumentsFor(invalid); } catch (ArgumentException) { refused = true; }
            Check.True(refused, "Aucun argument natif arbitraire");
        }
        if (!OperatingSystem.IsWindows()) Check.Null(new WindowsClockSkewReader().ReadClockSkew(Dc).OffsetSeconds, "Hors Windows aucune mesure inventée ni processus lancé");
    }
}

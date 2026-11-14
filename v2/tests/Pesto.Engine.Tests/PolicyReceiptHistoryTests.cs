using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Round trips the native writer, not a separately maintained receipt imitation. No AD/SMB operation runs.</summary>
internal sealed class PolicyReceiptHistoryTests
{
    private const string Computer = "P111301PAINF009", Name = "P111301PAINF010", Domain = "example.local", Dc = "dc01.example.local";
    private const string Identity = "11111111-1111-1111-1111-111111111111", Machine = "22222222-2222-2222-2222-222222222222";
    private const string Ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";
    private const string Reservation = "reservation-33333333333333333333333333333333";
    private static readonly string[] NewFields = ["Clock", "AuditEventLogEnabled", "ConfigurationSha256", "ReservationId", "ReservationAction", "Coordination"];

    private sealed class Fixture : IDisposable
    {
        public readonly GpFixture Gp = new();
        public readonly string ConfigurationRoot;
        public readonly string Share = Path.Combine(Path.GetTempPath(), "pesto-history-share-must-not-exist-" + Guid.NewGuid().ToString("N"));
        public readonly string ReceiptId = "receipt-" + Guid.NewGuid().ToString("N");
        public readonly PowerShellMutationGateway Native;
        public readonly MutationRequest Request;
        private readonly object baseline;

        public Fixture(string kind = "join")
        {
            var configuration = JsonNode.Parse(LiveTestConfig.NoRandom)!;
            configuration["POLICY"]!["AuditEventLogEnabled"] = true;
            configuration["POLICY"]!["BlockJoinOnClockSkew"] = true;
            configuration["POLICY"]!["CoordinationRoot"] = Share;
            ConfigurationRoot = LiveTestConfig.Write(configuration.ToJsonString());
            var sha = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(ConfigurationRoot, "cfg.json")))).ToLowerInvariant();
            Native = new PowerShellMutationGateway(ConfigurationRoot, receiptGpRoot: Gp.Root);
            Request = new(kind, Computer, kind == "join" ? null : Identity, kind == "move" ? null : Name,
                Ou, Domain, Dc, "plan-history", ReceiptId, kind == "join" ? null : Ou,
                kind == "rename" ? null : "44444444-4444-4444-4444-444444444444", ConfigurationSha256: sha);
            typeof(PowerShellMutationGateway).GetProperty(nameof(PowerShellMutationGateway.LastJoinClockCheck))!
                .SetValue(Native, new JoinClockCheck("warning", "Écart inconnu, aucune correction.", Dc, DateTimeOffset.UtcNow, null, false));
            var type = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.NativeReceiptSnapshot")!;
            baseline = Activator.CreateInstance(type, [DateTimeOffset.UtcNow.AddHours(-1), Machine, Computer, Computer, Domain,
                true, true, kind == "join" ? null : Identity, kind == "join" ? null : Computer,
                kind == "join" ? null : Ou, kind == "join" ? null : (object)true, null, false, 1])!;
        }

        public JsonObject Receipt(string? reservationAction = null)
        {
            var method = typeof(PowerShellMutationGateway).GetMethod("ReceiptJson", BindingFlags.Instance | BindingFlags.NonPublic)!;
            var request = Request;
            string Render() => (string)method.Invoke(Native, [request, "PendingRestart", Request.Kind == "join" ? 10 : 20,
                "Résultat natif accepté, redémarrage non encore constaté.", true, baseline])!;
            var json = Render(); // Pure initial intent; no registry, share, module or audit sink is accessed.
            if (reservationAction is not null)
            {
                // Exercise the actual serializer after the initial GUID-less intention was bound to its receipt.
                // This fixture authority is never passed to Execute or to a native reservation operation.
                var authority = new JoinReservationAuthorization("PRIVATE-FIXTURE-AUTHORITY", Reservation, new string('a', 64),
                    Request.PlanId, reservationAction, Computer, Name, Domain, Dc, Ou, Request.TargetOuGuid!, Machine, Identity,
                    "fixture marker", DateTimeOffset.UtcNow.AddMinutes(1), [], Request.ConfigurationSha256!);
                request = Request with { ComputerGuid = Identity, Reservation = authority };
                json = Render();
            }
            return JsonNode.Parse(json)!.AsObject();
        }

        public HistoryEntry Read(JsonObject receipt)
        {
            Gp.AdapterRaw(ReceiptId, receipt.ToJsonString());
            return GpHistory.Read(Gp.Root).Entries.Single();
        }
        public void Dispose()
        {
            Directory.Delete(ConfigurationRoot, true);
            Directory.Delete(Gp.Root, true);
        }
    }

    [Test]
    public void ActualNativeReceiptRoundTripsEveryC3FieldForAllOperationalKinds()
    {
        foreach (var kind in new[] { "join", "rename", "move", "renameMove" })
        {
            using var world = new Fixture(kind);
            var receipt = world.Receipt();
            Check.True(NewFields.All(receipt.ContainsKey), "Le test suit les vrais champs écrits par le natif");
            Check.True(receipt["Adapter"]!.GetValue<string>().Length <= 400, "La description réelle de l’adaptateur reste dans la borne du reçu");
            var entry = world.Read(receipt);
            Check.True(entry.Readable, "Le reçu C3 se relit après fermeture pour " + kind);
            Check.Equal(kind, entry.Receipt.Kind, "Aucune conversion du type métier");
            Check.Equal("pendingRestart", entry.Receipt.Status, "Aucun faux succès pendant la relecture");
            Check.False(Directory.Exists(world.Share), "La lecture d’historique ne sonde ni ne prépare le partage nommé dans sa preuve");
        }
    }

    [Test]
    public void ReservationBindingMayAddTheObservedGuidWithoutRewritingItsInitialLocks()
    {
        using var world = new Fixture();
        foreach (var action in new[] { "initialJoin", "resumeJoin" })
        {
            var receipt = world.Receipt(action);
            Check.Equal(Reservation, receipt["ReservationId"]!.GetValue<string>(), "Identité du parcours conservée par le vrai writer");
            Check.Equal(action, receipt["ReservationAction"]!.GetValue<string>(), "Action fermée conservée");
            Check.Null(receipt["Coordination"]!["Identity"]!["ComputerGuid"], "L’intention initiale ne reçoit pas rétroactivement un GUID");
            Check.True(world.Read(receipt).Readable, "Le GUID observé de la réservation est admis pour cette jonction");
            Check.False(receipt.ToJsonString().Contains("PRIVATE-FIXTURE-AUTHORITY", StringComparison.Ordinal), "Aucun jeton d’autorisation persisté");
        }
        var initial = world.Receipt(); initial["ReservationId"] = Reservation; initial["ComputerGuid"] = Identity;
        Check.True(world.Read(initial).Readable, "Le lien initial ajoute le GUID et l’id avant que ReservationAction existe");
    }

    [Test]
    public void MalformedOrContradictoryClockAuditAndReservationMetadataIsUnreadable()
    {
        using var world = new Fixture();
        var valid = world.Receipt("resumeJoin");
        Action<JsonObject>[] invalid =
        [
            r => r["AuditEventLogEnabled"] = "true", r => r["AuditEventLogEnabled"] = null,
            r => r["ConfigurationSha256"] = "bad", r => r["ConfigurationSha256"] = null,
            r => r["ConfigurationSha256"] = RequestHash(r) + "\n",
            r => r["ReservationId"] = "../reservation.json", r => r["ReservationId"] = "reservation-" + new string('0', 32),
            r => r["ReservationAction"] = "release", r => r["ReservationId"] = null, r => r["ComputerGuid"] = null,
            r => r["Clock"] = new JsonArray(), r => r["Clock"]!["State"] = "success",
            r => r["Clock"]!["OffsetSeconds"] = 0, r => r["Clock"]!["Blocked"] = true,
            r => r["Clock"]!["Server"] = "other.example.local", r => r["Clock"]!["Server"] = "dc01.example.local\n",
            r => r["Clock"]!["ObservedUtc"] = "2026-10-25T10:00:00+02:00",
            r => r["Clock"]!["Unknown"] = true, r => r["Clock"]!["Message"] = "malformed\n",
            r => r["Clock"] = JsonSerializerNode(new JoinClockCheck("observed", "Écart", Dc, DateTimeOffset.UtcNow, 300, false)),
            r => r["Clock"] = JsonSerializerNode(new JoinClockCheck("blocked", "Écart", Dc, DateTimeOffset.UtcNow, 299, true)),
            r => r["Clock"] = JsonSerializerNode(new JoinClockCheck("blocked", "Écart", Dc, DateTimeOffset.UtcNow, 300, true)),
            r => r["NameReservation"] = new JsonObject(), // No such field is emitted by the adapter.
        ];
        foreach (var change in invalid)
        {
            var receipt = valid.DeepClone().AsObject(); change(receipt);
            var raw = receipt.ToJsonString();
            Check.False(world.Read(receipt).Readable, "Un champ incohérent reste visible comme illisible");
            Check.Equal(raw, File.ReadAllText(Path.Combine(world.Gp.Root, "V2", "receipts", world.ReceiptId + ".json")), "Aucune réparation ni suppression de l’historique");
        }
        var old = valid.DeepClone().AsObject(); foreach (var key in NewFields) old.Remove(key);
        Check.True(world.Read(old).Readable, "Les anciens reçus sans les champs C3 restent lisibles");
    }

    [Test]
    public void CoordinationMustBeClosedAndBoundToTheExactContainingReceipt()
    {
        using var world = new Fixture("rename");
        var valid = world.Receipt();
        Action<JsonObject>[] invalid =
        [
            r => r["Coordination"] = new JsonArray(), r => r["Coordination"]!["Unknown"] = true,
            r => r["Coordination"]!["Owner"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            r => r["Coordination"]!["ReceiptId"] = "receipt-other",
            r => r["ConfigurationSha256"] = new string('b', 64), r => r["Computer"] = "ANOTHER-PC",
            r => r["NewName"] = "ANOTHER-NAME", r => r["Domain"] = "other.local",
            r => r["ComputerGuid"] = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            r => r["Coordination"]!["Entries"]![0]!["Sha256"] = new string('b', 64),
            r => r["Coordination"]!["Entries"]![0]!["Inherited"] = true,
            r => r["ReservationId"] = Reservation,
            r => r["Clock"] = JsonSerializerNode(new JoinClockCheck("warning", "Écart inconnu", Dc, DateTimeOffset.UtcNow, null, false)),
        ];
        foreach (var change in invalid)
        {
            var receipt = valid.DeepClone().AsObject(); change(receipt);
            Check.False(world.Read(receipt).Readable, "Preuve étrangère, incohérente ou de type non applicable refusée");
        }
        Check.False(Directory.Exists(world.Share), "Aucune validation réseau des intentions relues");
    }

    private static string RequestHash(JsonObject receipt) => receipt["ConfigurationSha256"]!.GetValue<string>();
    private static JsonNode JsonSerializerNode(JoinClockCheck check) => System.Text.Json.JsonSerializer.SerializeToNode(check)!;
}

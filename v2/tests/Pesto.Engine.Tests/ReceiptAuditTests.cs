using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class ReceiptAuditTests
{
    private const string Id = "receipt-12345678123456781234567812345678";
    private sealed class Sink : IReceiptAuditSink
    {
        public readonly List<ReceiptAuditEvent> Values = [];
        public ReceiptAuditEmission Result = new(true);
        public Action<ReceiptAuditEvent>? BeforeWrite;
        public bool Throws;
        public ReceiptAuditEmission Write(ReceiptAuditEvent value)
        {
            BeforeWrite?.Invoke(value);
            Values.Add(value);
            if (Throws) throw new IOException("SECRET-SENTINEL exception");
            return Result;
        }
    }

    private static JsonObject Receipt(string kind = "rename", string phase = "Uncertain") => new()
    {
        ["Schema"] = 1, ["Version"] = "2.0", ["ReceiptId"] = Id, ["PlanId"] = "plan-fixture", ["Kind"] = kind,
        ["Computer"] = "SECRET-SENTINEL", ["NewName"] = "SECRET-SENTINEL", ["TargetOu"] = null,
        ["ComputerGuid"] = "11111111-1111-1111-1111-111111111111", ["Domain"] = "example.local",
        ["Phase"] = phase, ["Code"] = 97, ["Utc"] = "2026-10-25T10:00:00.0000000+00:00", ["Message"] = "SECRET-SENTINEL",
        ["Credentials"] = "SECRET-SENTINEL", ["Configuration"] = "SECRET-SENTINEL"
    };
    private static string Config(bool enabled = true)
    {
        var json = JsonNode.Parse(LiveTestConfig.NoRandom)!;
        json["POLICY"]!["AuditEventLogEnabled"] = enabled;
        return LiveTestConfig.Write(json.ToJsonString());
    }

    [Test]
    public void ProjectionUsesExactlyTheV1NonSensitiveFieldsAndStableOperationIdentity()
    {
        var sink = new Sink();
        var trail = new ReceiptAuditTrail(sink, new FixedClock());
        foreach (var kind in new[] { "join", "rename", "move", "renameMove" }) trail.AfterDurableReceipt(true, Receipt(kind).ToJsonString());
        Check.Equal(4, sink.Values.Count, "Chaque reçu opérationnel validé est projeté");
        foreach (var value in sink.Values)
        {
            using var doc = JsonDocument.Parse(JsonSerializer.Serialize(value));
            Check.Equal("Schema,Product,OperationId,Kind,State,ResultCode,Sequence,UpdatedUtc", string.Join(',', doc.RootElement.EnumerateObject().Select(p => p.Name)), "Champs exacts V1");
            Check.Equal(Id[8..], value.OperationId, "GUID durable conservé, jamais une identité inventée");
            Check.Equal("Uncertain", value.State, "L’incertitude reste explicite");
            Check.Equal(97, value.ResultCode, "Code réel du reçu");
            Check.Null(value.Sequence, "Aucune séquence fictive pour une action unitaire V2");
            Check.Equal("2026-10-25T10:00:00.0000000Z", value.UpdatedUtc, "Horodatage UTC canonique V1");
            Check.False(JsonSerializer.Serialize(value).Contains("SECRET-SENTINEL", StringComparison.Ordinal), "Aucun contenu sensible dans l’événement");
        }
        Check.Equal("Join", sink.Values[0].Kind, "Jonction V1");
        Check.True(sink.Values.Skip(1).All(v => v.Kind == "Direct"), "Autres actions unitaires V2");
        var partial = Receipt("renameMove", "Partial"); partial["Code"] = 89;
        trail.AfterDurableReceipt(true, partial.ToJsonString());
        Check.Equal("Partial", sink.Values[^1].State, "Un parent partiel ne devient pas Verified dans l’audit");
        Check.Equal<int?>(89, sink.Values[^1].ResultCode, "Le code du parent est conservé");
    }

    [Test]
    public void DisabledOrInvalidReceiptNeverReachesTheSink()
    {
        var sink = new Sink();
        var trail = new ReceiptAuditTrail(sink);
        trail.AfterDurableReceipt(false, "invalid-json");
        Check.Equal("notAttempted", trail.Status.State, "Désactivé : aucune tentative ni faux échec");
        foreach (var (field, invalid) in new (string, JsonNode?)[]
        {
            ("Schema", JsonValue.Create("1")), ("Version", JsonValue.Create("1.0")), ("Kind", JsonValue.Create("reservation")),
            ("Phase", JsonValue.Create("Success")), ("Code", JsonValue.Create("97")), ("Utc", JsonValue.Create("2026-10-25T10:00:00+02:00")),
            ("ReceiptId", JsonValue.Create("receipt-00000000000000000000000000000000")), ("ReceiptId", JsonValue.Create("receipt-other"))
        })
        {
            var json = Receipt(); json[field] = invalid;
            trail.AfterDurableReceipt(true, json.ToJsonString());
        }
        Check.Equal(0, sink.Values.Count, "Aucun reçu invalide ou réservation dans l’audit opérationnel");
        Check.Equal(8, trail.Status.Failures, "Chaque refus de projection est visible");
    }

    [Test]
    public void BestEffortFailureAndLateResultAreVisibleWithoutRetryOrSecret()
    {
        var sink = new Sink { Result = new(false, "audit.timeout") };
        var trail = new ReceiptAuditTrail(sink, new FixedClock());
        var original = Receipt().ToJsonString();
        trail.AfterDurableReceipt(true, original);
        Check.Equal(1, sink.Values.Count, "Pas de nouvel essai après délai d’écriture inconnu");
        Check.Equal("failed", trail.Status.State, "Un événement tardif n’est pas déclaré écrit");
        Check.Null(trail.Status.LastSuccessUtc, "Aucune réussite inventée");
        Check.Equal("audit.timeout", trail.Status.FailureCode, "Motif fermé exploitable");
        sink.Throws = true;
        trail.AfterDurableReceipt(true, original);
        Check.Equal(2, trail.Status.Failures, "L’exception n’interrompt pas la finalisation");
        Check.False(JsonSerializer.Serialize(trail.Status).Contains("SECRET-SENTINEL", StringComparison.Ordinal), "Détail d’exception non exporté");
        Check.Equal("Uncertain", Receipt()["Phase"]!.GetValue<string>(), "Le statut opérationnel ne change pas");
    }

    [Test]
    public void NativeFinalizerAuditsOnlyAfterTheNewReceiptIsDurableAndKeepsUncertain()
    {
        var root = Harness.IsolatedGpRoot();
        var config = Config();
        var folder = Path.Combine(root, "V2", "receipts"); Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, Id + ".json");
        try
        {
            var receipt = Receipt(); receipt["Computer"] = "LAB-PC"; receipt["NewName"] = "LAB-NEW";
            File.WriteAllText(path, receipt.ToJsonString());
            var sink = new Sink
            {
                BeforeWrite = audit =>
                {
                    using var saved = JsonDocument.Parse(File.ReadAllText(path));
                    Check.Equal(audit.State, saved.RootElement.GetProperty("Phase").GetString()!, "La nouvelle phase est déjà sur disque lors de l’audit");
                    Check.Equal(audit.ResultCode, saved.RootElement.GetProperty("Code").GetInt32(), "Le code durable précède l’événement");
                },
                Result = new(false, "audit.source_unavailable")
            };
            var native = new PowerShellMutationGateway(config, receiptGpRoot: root, auditSink: sink);
            var request = new MutationRequest("rename", "LAB-PC", "11111111-1111-1111-1111-111111111111", "LAB-NEW", null,
                "example.local", "dc01.example.local", "plan-fixture", Id);
            native.PersistFinalReceipt(request, new(MutationStatus.Uncertain, 97, "Résultat non confirmé.", true));
            Check.Equal(1, sink.Values.Count, "Une seule émission après finalisation durable");
            Check.Equal("Uncertain", JsonNode.Parse(File.ReadAllText(path))!["Phase"]!.GetValue<string>(), "Échec EventLog sans changement du résultat");
            Check.Equal("failed", native.AuditStatus.State, "Échec secondaire visible");
            var refused = false;
            try { native.PersistFinalReceipt(request with { PlanId = "changed" }, new(MutationStatus.Succeeded, 0, "Ne doit pas être écrit", false)); }
            catch (IOException) { refused = true; }
            Check.True(refused, "Un remplacement non autorisé du reçu est refusé");
            Check.Equal(1, sink.Values.Count, "Aucun événement pour une finalisation qui n’a pas écrit le reçu");
        }
        finally { Directory.Delete(root, true); Directory.Delete(config, true); }
    }

    [Test]
    public void AuditDiagnosticsNeverClaimSuccessBeforeAnActualConfirmedWrite()
    {
        var root = Config();
        try
        {
            var native = new PowerShellMutationGateway(root, auditSink: new Sink());
            var backend = Harness.Live(root, new FakeGateway(), native);
            var check = Harness.Arr(Harness.Call(backend, "diagnostics.read"), "checks").Single(n => Harness.Str(n!, "label") == "Audit Windows")!;
            Check.Equal("warn", Harness.Str(check, "state"), "Source non testée ne signifie pas audit fonctionnel");
            Check.Contains("aucune écriture d’audit", Harness.Str(check, "detail"), "État honnête sans créer ni tester une source");
            Check.Null(V1Config.ValidateText(File.ReadAllText(Path.Combine(root, "cfg.json"))).OperationPolicy.BlockReason("join"), "La politique V1 best effort ne bloque plus les mutations par principe");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void NativeAuditHasAClosedConstantDestinationAndNoProvisioningOrAd()
    {
        var script = WindowsReceiptAuditSink.ConstantScript;
        Check.Contains("Write-EventLog -LogName 'Application' -Source 'Pesto' -EntryType 'Information' -EventId 1000", script, "Destination V1 exacte");
        foreach (var forbidden in new[] { "New-EventLog", "Import-Module", "-Credential", "Add-Computer", "Rename-Computer", "Restart-Computer" })
            Check.False(script.Contains(forbidden, StringComparison.OrdinalIgnoreCase), "Aucun provisionnement, annuaire ou mutation dans le sink");
        Check.Equal(5000, WindowsReceiptAuditSink.TimeoutMilliseconds, "Émission secondaire bornée");
        if (!OperatingSystem.IsWindows())
        {
            using var doc = JsonDocument.Parse(Receipt().ToJsonString());
            var result = new WindowsReceiptAuditSink().Write(ReceiptAuditEvent.FromV2Receipt(doc.RootElement)!);
            Check.False(result.Confirmed, "Pas d’événement simulé hors Windows");
        }
    }
}

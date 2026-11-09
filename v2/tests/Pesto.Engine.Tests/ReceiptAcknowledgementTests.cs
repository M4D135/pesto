using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Only temporary JSON fixtures and a memory environment: no Windows/AD/SMB/process calls.</summary>
internal sealed class ReceiptAcknowledgementTests
{
    private const string Machine = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private const string Id = "receipt-ack-fixture";
    private const string Domain = "example.local";
    private const string Computer = "P111301PAINF009";
    private const string NewName = "P111301PAINF010";
    private const string Ou = "OU=Paris-Nord,OU=SITES,OU=Postes,DC=example,DC=local";

    private sealed class World : IDisposable
    {
        public readonly GpFixture Gp = new();
        public readonly FixedClock Clock = new();
        public readonly ReceiptAcknowledgementCoordinator Service;
        public Func<ReceiptAcknowledgementContext, ReceiptAcknowledgementContext>? Change;
        public int Inspections;
        public World()
        {
            Write();
            Service = new(Gp.Root, _ =>
            {
                Inspections++;
                var c = new ReceiptAcknowledgementContext(Domain, new('c', 64), "FIXTURE\\operator",
                    new(Machine, Clock.GetUtcNow(), true, "local-process-snapshot"), true, true, new('e', 64));
                return Change?.Invoke(c) ?? c;
            }, Clock);
        }
        public string PathOf(string id = Id) => Path.Combine(Gp.Root, "V2", "receipts", id + ".json");
        public void Write(string id = Id, string phase = "Uncertain", int code = 97)
        {
            Gp.AdapterReceipt(id, phase, Clock.GetUtcNow(), computer: Computer, newName: NewName, targetOu: Ou, code: code);
            ChangeFile(PathOf(id), node => { node["Domain"] = Domain; node["Dc"] = "dc01.example.local"; });
        }
        public ReceiptAcknowledgementPreparation Prepare(string id = Id) => Service.Prepare(id, "ack-plan-fixture");
        public string[] Events() => Directory.Exists(Path.Combine(Gp.Root, "V2", "acknowledgements"))
            ? Directory.GetFiles(Path.Combine(Gp.Root, "V2", "acknowledgements"), "*.json", SearchOption.AllDirectories) : [];
        public string Task(string phase, string kind = "task-fallback-evidence")
        {
            var folder = Path.Combine(Gp.Root, "V2", "tasks"); Directory.CreateDirectory(folder);
            var path = Path.Combine(folder, Id + ".123456abcdef.json");
            File.WriteAllText(path, JsonSerializer.Serialize(new { Schema = 1, Version = "2.0", Kind = kind, Computer,
                TaskName = "\\Pesto_Rename_123456abcdef", Phases = new[] { new { Phase = phase, Utc = Clock.GetUtcNow().ToString("o"), Hash = new string('a', 64), NativeCode = (long?)0 } } }));
            return path;
        }
        public void Dispose() => Directory.Delete(Gp.Root, true);
    }

    private static void ChangeFile(string path, Action<JsonObject> change)
    { var node = JsonNode.Parse(File.ReadAllText(path))!.AsObject(); change(node); File.WriteAllText(path, node.ToJsonString()); }

    [Test]
    public void PreparingWritesNothingAndConfirmedEventSurvivesNewReaderWithoutChangingResultBytes()
    {
        using var w = new World();
        var before = File.ReadAllBytes(w.PathOf());
        var plan = w.Prepare();
        Check.Equal(0, w.Events().Length, "Préparer n’écrit aucun acquittement");
        Check.Equal(NewName, plan.Authorization.ConfirmationName, "Nom d’origine à confirmer");
        var result = w.Service.Acknowledge(plan.Authorization, "Vérification manuelle documentée");
        Check.Equal(1, w.Events().Length, "Un seul événement append-only");
        Check.True(before.AsSpan().SequenceEqual(File.ReadAllBytes(w.PathOf())), "Phase/code/effets et tous octets du reçu conservés");
        Check.Equal("uncertain", result.Receipt.Status, "Un acquittement n’est jamais une réussite");
        Check.Equal(97, result.Receipt.Code, "Le code d’origine reste exact");
        Check.NotNull(new ReceiptAcknowledgementStore(w.Gp.Root).ReadApplied(Id), "Projection durable après nouvelle instance");
        Check.True(ReceiptAcknowledgementStore.ValidateApplied(w.Gp.Root, result.Evidence), "Événement relu et lié aux empreintes");
    }

    [Test]
    public void CloneExpiryAndReplayNeverCreateAnEvent()
    {
        using var w = new World(); var p = w.Prepare();
        Check.Pesto(() => w.Service.Acknowledge(p.Authorization with { }, "Motif valable"), "receipt.acknowledgement", "La copie d’un jeton n’est pas une autorisation native");
        w.Clock.Advance(TimeSpan.FromMinutes(3));
        Check.Pesto(() => w.Service.Acknowledge(p.Authorization, "Motif valable"), "receipt.acknowledgement", "Expiration sans écriture");
        var next = w.Prepare(); _ = w.Service.Acknowledge(next.Authorization, "Motif valable");
        Check.Pesto(() => w.Service.Acknowledge(next.Authorization, "Second envoi"), "receipt.acknowledgement", "Aucun rejeu");
        Check.Equal(1, w.Events().Length, "Un seul événement réellement confirmé");
    }

    [Test]
    public void MotiveBoundariesAndControlCharactersAreStrict()
    {
        using var w = new World(); var p = w.Prepare();
        foreach (var reason in new[] { "ab", "   ", new string('x', 501), "abc\ndef", "abc\u007f" })
            Check.Pesto(() => w.Service.Acknowledge(p.Authorization, reason), "receipt.acknowledgement", "Motif hors contrat refusé");
        Check.Equal(0, w.Events().Length, "Un motif refusé ne consomme pas une écriture");
        var result = w.Service.Acknowledge(p.Authorization, new string('x', 500));
        Check.Equal(500, result.Evidence.Event.Reason.Length, "Borne exacte de 500 acceptée sans troncature");
    }

    [Test]
    public void EveryOpenTaskPhaseIncludingRemoteProofAndRestartBlocks()
    {
        foreach (var phase in new[] { "Registering", "Registered", "StartRequested", "Started", "DeleteFailed", "ResultSaved", "ResultDeleted" })
        {
            using var w = new World(); w.Task(phase, phase == "ResultSaved" ? "windows-proof-evidence" : "restart-request-evidence");
            Check.Pesto(() => w.Prepare(), "receipt.acknowledgement", "Une tâche non terminée conserve la barrière : " + phase);
            Check.Equal(0, w.Events().Length, "Aucune écriture au-dessus d’une tâche incertaine");
        }
    }

    [Test]
    public void TerminalTaskHashIsBoundAndLaterTaskChangeInvalidatesProjection()
    {
        using var w = new World(); var task = w.Task("Finished"); var p = w.Prepare();
        var result = w.Service.Acknowledge(p.Authorization, "Tâche contrôlée terminée");
        Check.True(ReceiptAcknowledgementStore.ValidateApplied(w.Gp.Root, result.Evidence), "Finished avec hash complet admis");
        ChangeFile(task, node => node["Phases"]![0]!["Phase"] = "Started");
        Check.False(ReceiptAcknowledgementStore.ValidateApplied(w.Gp.Root, result.Evidence), "Nouvelle activité n’est jamais couverte par l’ancien acquittement");
        Check.Null(ReceiptAcknowledgementStore.TryReadForReceipt(w.Gp.Root, w.PathOf(), File.ReadAllBytes(w.PathOf())), "Barrière conservatrice lors d’un changement de tâche");
    }

    [Test]
    public void ChangedReceiptConfigurationOrEntraEvidenceRequiresNewConfirmation()
    {
        using (var w = new World())
        {
            var p = w.Prepare(); ChangeFile(w.PathOf(), node => node["Code"] = 98);
            Check.Pesto(() => w.Service.Acknowledge(p.Authorization, "Motif valable"), "receipt.acknowledgement", "Code changé refusé");
            Check.Equal(0, w.Events().Length, "Aucun événement pour une ancienne empreinte");
        }
        foreach (var entra in new[] { false, true })
        {
            using var w = new World(); var p = w.Prepare();
            w.Change = c => entra ? c with { EntraEvidenceSha256 = new('b', 64) } : c with { ConfigurationSha256 = new('d', 64) };
            Check.Pesto(() => w.Service.Acknowledge(p.Authorization, "Motif valable"), "receipt.acknowledgement", "Preuve/configuration changée refusée");
        }
    }

    [Test]
    public void ActiveWorkerReservationAndEntraNeverBecomeABypass()
    {
        foreach (var mode in new[] { "worker", "reservation", "entra", "machine", "domain" })
        {
            using var w = new World();
            w.Change = c => mode switch
            {
                "worker" => c with { WorkerProof = c.WorkerProof with { Clear = false } },
                "reservation" => c with { ReservationsResolved = false },
                "entra" => c with { EntraCanAcknowledge = false },
                "machine" => c with { WorkerProof = c.WorkerProof with { MachineId = "" } },
                _ => c with { Domain = "other.local" }
            };
            Check.Pesto(() => w.Prepare(), "receipt.acknowledgement", "Garde fraîche obligatoire : " + mode);
            Check.Equal(0, w.Events().Length, "Aucune barrière contournée");
        }
    }

    [Test]
    public void OriginalParentAndChildHashesStayIntactAndOnlyChildIsCovered()
    {
        using var w = new World(); w.Write("receipt-parent", "Partial", 89);
        var parent = File.ReadAllBytes(w.PathOf("receipt-parent"));
        ChangeFile(w.PathOf(), node => { node["ParentReceiptId"] = "receipt-parent"; node["ParentReceiptSha256"] = ReceiptAcknowledgementSource.Digest(parent); });
        var child = File.ReadAllBytes(w.PathOf()); var p = w.Prepare();
        _ = w.Service.Acknowledge(p.Authorization, "Décision limitée au reçu enfant");
        Check.True(parent.AsSpan().SequenceEqual(File.ReadAllBytes(w.PathOf("receipt-parent"))), "Parent inchangé");
        Check.True(child.AsSpan().SequenceEqual(File.ReadAllBytes(w.PathOf())), "Enfant inchangé");
        Check.Null(new ReceiptAcknowledgementStore(w.Gp.Root).ReadApplied("receipt-parent"), "L’acquittement enfant ne libère pas le parent");
    }

    [Test]
    public void ChangedEffectAfterAcknowledgementMakesItStaleWithoutRemovingItsHistory()
    {
        using var w = new World(); var p = w.Prepare(); var r = w.Service.Acknowledge(p.Authorization, "Motif consigné");
        ChangeFile(w.PathOf(), node => node["RestartRequired"] = true);
        Check.False(ReceiptAcknowledgementStore.ValidateApplied(w.Gp.Root, r.Evidence), "L’empreinte couvre les effets en plus du code/phase");
        Check.Equal(1, w.Events().Length, "L’événement historique reste conservé");
    }

    [Test]
    public void UnknownDuplicateFieldsAndBrokenTaskSchemaNeverQualify()
    {
        using (var w = new World())
        {
            ChangeFile(w.PathOf(), node => node["UnknownAuthority"] = true);
            Check.Pesto(() => w.Prepare(), "receipt.acknowledgement", "Champ inconnu dans le reçu refusé");
        }
        using (var w = new World())
        {
            w.Task("Deleted"); var path = Path.Combine(w.Gp.Root, "V2", "tasks", Id + ".123456abcdef.json");
            ChangeFile(path, node => node["Phases"]![0]!["Hash"] = "");
            Check.Pesto(() => w.Prepare(), "receipt.acknowledgement", "Une fin sans empreinte de définition ne suffit pas");
        }
        using (var w = new World())
        {
            var p = w.Prepare(); _ = w.Service.Acknowledge(p.Authorization, "Motif consigné");
            var path = w.Events().Single(); var text = File.ReadAllText(path); File.WriteAllText(path, text.Replace("\"Schema\":1", "\"Schema\":1,\"Schema\":1", StringComparison.Ordinal));
            Check.Null(ReceiptAcknowledgementStore.TryReadForReceipt(w.Gp.Root, w.PathOf(), File.ReadAllBytes(w.PathOf())), "Événement à clé dupliquée ne libère rien");
        }
    }

    [Test]
    public void V1LedgerAndMatchingDirectCopyAreCoveredAtomicallyWithoutRewrite()
    {
        using var w = new World(); var operation = Guid.NewGuid(); var id = operation.ToString("N");
        var ledger = w.Gp.V1Intervention(operation, "Protection", rename: true, resultCode: 32);
        var keys = SharedCoordinationProtocol.Keys(new(Domain, Computer, NewName, "11111111-1111-1111-1111-111111111111"));
        ChangeFile(ledger, node => node["Coordination"] = new JsonObject { ["Enabled"] = true, ["Owner"] = id,
            ["Keys"] = JsonSerializer.SerializeToNode(keys) });
        var original = JsonNode.Parse(File.ReadAllText(ledger))!.AsObject();
        var directFolder = Path.Combine(w.Gp.Root, "Operations"); Directory.CreateDirectory(directFolder);
        var direct = Path.Combine(directFolder, "direct.json");
        File.WriteAllText(direct, new JsonObject { ["Schema"] = 1, ["OperationId"] = operation.ToString("D"), ["Phase"] = "Protection",
            ["OperatorMachineId"] = Machine, ["Plan"] = original["Plan"]!.DeepClone(), ["ResultCode"] = 32, ["ResultMessage"] = "Résultat original" }.ToJsonString());
        var a = File.ReadAllBytes(ledger); var b = File.ReadAllBytes(direct);
        var p = w.Prepare(id); var result = w.Service.Acknowledge(p.Authorization, "Protection examinée manuellement");
        Check.Equal(2, result.Evidence.Event.Targets.Count, "Événement unique couvrant registre et copie locale exacts");
        Check.Equal("direct", result.Evidence.Event.Targets[0].Store, "La copie sans coordination arrive en premier dans l’inventaire trié");
        var releases = 0;
        Action<string, string, ReceiptAcknowledgementEvidence> release = (path, receiptId, evidence) =>
        {
            releases++;
            Check.Equal(ledger, path, "Le nettoyage reçoit réellement le registre V1 portant les clés, jamais sa copie direct");
            Check.Equal(id, receiptId, "Le propriétaire original reste lié au reçu acquitté");
            Check.True(ReferenceEquals(result.Evidence, evidence) && ReceiptAcknowledgementStore.ValidateApplied(w.Gp.Root, evidence),
                "Le nettoyage reçoit l’événement durable exact après validation de ses deux cibles");
            var coordination = JsonNode.Parse(File.ReadAllText(path))!["Coordination"]!;
            Check.Equal(id, coordination["Owner"]!.GetValue<string>(), "Le propriétaire de coordination est disponible dans le fichier sélectionné");
            Check.Equal(string.Join(',', keys), string.Join(',', coordination["Keys"]!.AsArray().Select(item => item!.GetValue<string>())),
                "Toutes les clés du registre confirmé parviennent à la frontière de nettoyage");
        };
        typeof(PowerShellMutationGateway).GetMethod("ReleaseAcknowledgedCoordination", BindingFlags.Static | BindingFlags.NonPublic)!
            .Invoke(null, [w.Gp.Root, result.Evidence, release]);
        Check.Equal(1, releases, "Un seul nettoyage du registre propriétaire, sans action native dans cette fixture");
        Check.True(a.AsSpan().SequenceEqual(File.ReadAllBytes(ledger)) && b.AsSpan().SequenceEqual(File.ReadAllBytes(direct)), "Aucun reçu V1 réécrit");
        Check.NotNull(ReceiptAcknowledgementStore.TryReadForReceipt(w.Gp.Root, direct, b), "La barrière de la copie exacte peut observer la même décision");
    }

    [Test]
    public void ForeignV1OperatorMachineAndUnsupportedTerminalOutcomeAreRefused()
    {
        using (var w = new World())
        {
            w.Write(phase: "Verified", code: 0);
            Check.Pesto(() => w.Prepare(), "receipt.acknowledgement", "Un succès ne devient pas une action d’acquittement");
        }
        using (var w = new World())
        {
            var operation = Guid.NewGuid(); var ledger = w.Gp.V1Intervention(operation, "Uncertain", resultCode: 97);
            var source = JsonNode.Parse(File.ReadAllText(ledger))!.AsObject(); var folder = Path.Combine(w.Gp.Root, "Operations"); Directory.CreateDirectory(folder);
            File.WriteAllText(Path.Combine(folder, "direct.json"), new JsonObject { ["Schema"] = 1, ["OperationId"] = operation.ToString("D"),
                ["Phase"] = "Uncertain", ["OperatorMachineId"] = Guid.NewGuid().ToString("D"), ["Plan"] = source["Plan"]!.DeepClone(), ["ResultCode"] = 97 }.ToJsonString());
            Check.Pesto(() => w.Prepare(operation.ToString("N")), "receipt.acknowledgement", "Copie locale d’une autre machine opératrice conservée");
        }
    }
}

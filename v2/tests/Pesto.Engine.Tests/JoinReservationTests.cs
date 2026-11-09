using System.Diagnostics;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

/// <summary>Portable reservation qualification. Every AD/Windows operation is an in-memory fixture;
/// all durable receipts live in a unique temporary directory. No domain, registry, share or native process is used.</summary>
internal sealed class JoinReservationTests
{
    private const string Machine = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private const string Identity = "11111111-2222-3333-4444-555555555555";
    private const string OuIdentity = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    private const string Container = "OU=SITES,OU=Postes,DC=example,DC=local";
    private const string Ou = "OU=Paris-Nord," + Container;
    private const string Name = "P111301PAINF001";
    private static readonly string ConfigurationHash = new('c', 64);

    private sealed class NativeFixture : IJoinReservationNative
    {
        public required JoinReservationStore Store;
        public required FixedClock Clock;
        public int Creates, Reads, Deletes;
        public bool ThrowCreate, ThrowRead, MissingGuid, Taken, DeleteUncertain, PersistenceRace;
        public bool Absent;
        public DateTimeOffset? Boot;
        public Func<JoinReservationObservation, JoinReservationObservation>? Alter;
        public string CreateSawState = "", DeleteSawState = "";
        private JoinReservationObservation Observation(JoinReservationReceipt r) => new(Machine, Environment.MachineName,
            r.Domain, r.Dc, Boot ?? Clock.GetUtcNow().AddHours(-1), false, false, false, Absent,
            Absent ? null : MissingGuid ? null : Identity, Absent ? null : r.Name,
            Absent ? null : "CN=" + r.Name + "," + r.TargetOu, Absent ? null : r.Marker, null, [], OuIdentity);
        public JoinReservationObservation Read(JoinReservationReceipt receipt)
        {
            Reads++;
            if (ThrowRead) throw new UnauthorizedAccessException("Fixture: access denied is not absence");
            var evidence = Observation(receipt);
            return Alter?.Invoke(evidence) ?? evidence;
        }
        public JoinReservationNativeResult Create(JoinReservationReceipt receipt)
        {
            Creates++;
            CreateSawState = Store.Read(receipt.Id).State;
            if (ThrowCreate) throw new IOException("Fixture: response lost after possible create");
            if (Taken) return new("taken", "Collision confirmed before ownership", MutationMayHaveStarted: false);
            if (PersistenceRace)
            {
                var r = Store.Read(receipt.Id);
                Store.Save(r with { Revision = r.Revision + 1, Message = "Concurrent durable evidence preserved" }, Store.Stamp(r.Id));
            }
            return new("reserved", "Fixture created and read by GUID", Read(receipt), MutationMayHaveStarted: true);
        }
        public JoinReservationNativeResult Remove(JoinReservationReceipt receipt)
        {
            Deletes++;
            DeleteSawState = Store.Read(receipt.Id).State;
            if (DeleteUncertain) return new("uncertain", "Fixture transport interrupted", MutationMayHaveStarted: true);
            Absent = true;
            return new("released", "Fixture absence confirmed", Read(receipt), MutationMayHaveStarted: true);
        }
    }

    private sealed class World : IDisposable
    {
        public readonly string Root = Harness.IsolatedGpRoot();
        public readonly FixedClock Clock = new();
        public readonly JoinReservationStore Store;
        public readonly NativeFixture Native;
        public JoinReservationCoordinator Service;
        public World()
        {
            Store = new(Root);
            Native = new() { Store = Store, Clock = Clock };
            Service = new(Store, Native, Clock);
        }
        public MutationRequest Request(string receiptId = "receipt-parent") => new("join", Environment.MachineName, null,
            Name, Ou, "example.local", "dc01.example.local", "plan-confirmed", receiptId, TargetOuGuid: OuIdentity,
            ReservationRequired: true, ConfigurationSha256: ConfigurationHash);
        public JoinReservationView Create() => Service.Create(Request(), Machine);
        public JoinReservationPreparation Prepare(JoinReservationReceipt receipt, string action = "release", string plan = "plan-release") =>
            Service.Prepare(receipt.Id, action, plan, receipt.JoinReceiptIds.Select(id => new JoinReservationParent(id, new('a', 64))).ToArray(), ConfigurationHash);
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, recursive: true); }
    }

    [Test]
    public void NoCreationDuringListOrUnconfirmedPreparationAndPendingReceiptPrecedesCreate()
    {
        using var w = new World();
        Check.Equal(0, w.Service.List().Count, "Liste locale vide");
        Check.Equal(0, w.Native.Creates + w.Native.Reads + w.Native.Deletes, "Liste sans aucun appel AD");
        Check.Pesto(() => w.Service.Create(w.Request() with { ReservationRequired = false }, Machine), "reservation.evidence", "Pas de création sans effet divulgué au plan");
        Check.Equal(0, w.Native.Creates, "Refus antérieur à New-ADComputer");
        var created = w.Create();
        Check.Equal("pending", w.Native.CreateSawState, "Reçu durable avant création");
        Check.Equal("reserved", created.Receipt.State, "Création et relecture fiables");
        Check.Equal(Identity, w.Store.Read(created.Receipt.Id).ComputerGuid, "GUID réellement relu conservé");
        Check.Equal("receipt-parent", created.Receipt.ParentReceiptId, "Reçu de jonction distinct lié");
        Check.Equal(JoinReservationStore.MarkerFor(created.Receipt.OperationId), created.Receipt.Marker, "Marqueur exact V1");
        var plans = w.Prepare(created.Receipt);
        Check.Equal(0, w.Native.Deletes, "Préparation de retrait sans suppression");
        Check.True(plans.Authorization.ExpiresAt > w.Clock.GetUtcNow(), "Plan borné dans le temps");
    }

    [Test]
    public void UncertainCreationNeverDeletesOrReportsAZeroWriteFailure()
    {
        using var w = new World(); w.Native.ThrowCreate = true;
        var result = w.Create();
        Check.Equal("uncertain", result.Receipt.State, "Une réponse perdue n’est pas Failed");
        Check.True(result.Receipt.NeedsReview, "Inspection obligatoire");
        Check.Equal(0, w.Native.Deletes, "Jamais de rollback AD implicite");
        Check.Pesto(() => w.Service.Create(w.Request("receipt-other"), Machine), "reservation.evidence", "Autre création bloquée par la réservation conservée");
        Check.Equal(1, w.Native.Creates, "Aucune tentative automatique supplémentaire");
        w.Native.ThrowCreate = false;
        var inspected = w.Service.Inspect(result.Receipt.Id);
        Check.Equal(Identity, inspected.Receipt.ComputerGuid, "Inspection récupère le GUID par marqueur exact");
        Check.True(inspected.CanResume, "Reprise seulement après inspection");
        Check.Equal(1, w.Native.Creates, "Inspection sans création");
    }

    [Test]
    public void PendingReceiptStorageFailurePreventsEnteringTheNativeTransport()
    {
        using var w = new World();
        Directory.CreateDirectory(Path.GetDirectoryName(w.Store.DirectoryPath)!);
        File.WriteAllText(w.Store.DirectoryPath, "Fixture: this path is a file, not a receipt directory");
        var refused = false; try { _ = w.Create(); } catch (IOException) { refused = true; }
        Check.True(refused, "Impossible de persister pending : refus avant envoi");
        Check.Equal(0, w.Native.Creates, "Aucun appel New-ADComputer sans reçu durable");
    }

    [Test]
    public void ExpiredNameLeaseInFinalCallbackRefusesAfterPendingButBeforeCreate()
    {
        using var w = new World();
        var result = w.Service.Create(w.Request(), Machine, () =>
        {
            Check.Equal("pending", w.Store.List().Single().State, "Callback après flush préalable");
            throw new PestoException("names.reservation_expired", "Bail expiré : nouvel aperçu et nouvelle confirmation nécessaires.");
        });
        Check.Equal("refused", result.Receipt.State, "Refus prouvé avant création");
        Check.Equal(0, w.Native.Creates, "Aucun worker lancé sur bail perdu");
        Check.Contains("nouvel aperçu", result.Receipt.Message, "Aucun nom de remplacement choisi automatiquement");
    }

    [Test]
    public void CollisionAndUnconfirmedGuidNeverAdoptAnExistingAccount()
    {
        using (var w = new World())
        {
            w.Native.Taken = true;
            var result = w.Create();
            Check.Equal("taken", result.Receipt.State, "Collision connue");
            Check.Null(result.Receipt.ComputerGuid, "Aucune propriété inventée");
            Check.False(result.CanResume || result.CanRelease, "Aucune réutilisation ou suppression");
        }
        using (var w = new World())
        {
            w.Native.MissingGuid = true;
            var result = w.Create();
            Check.Equal("uncertain", result.Receipt.State, "GUID non confirmé = résultat incertain");
            Check.False(result.CanResume || result.CanRelease, "Aucune autorisation sans GUID durable");
        }
    }

    [Test]
    public void DurableWriteConflictAfterCreationKeepsTheConcurrentReceiptAndStopsJoin()
    {
        using var w = new World(); w.Native.PersistenceRace = true;
        var result = w.Create();
        Check.Equal("uncertain", result.Receipt.State, "La perte de persistance après création est incertaine");
        var durable = w.Store.Read(result.Receipt.Id);
        Check.Equal("pending", durable.State, "Le reçu antérieur reste non résolu");
        Check.Null(durable.ComputerGuid, "Le parent join doit lier uniquement cette preuve durable, jamais le GUID de la réponse tardive");
        Check.Equal("Concurrent durable evidence preserved", durable.Message, "Le remplacement concurrent est préservé");
        Check.False(result.CanResume || result.CanRelease, "Aucune reprise avec preuve non enregistrée");
        w.Native.PersistenceRace = false;
        var inspected = w.Service.Inspect(durable.Id);
        Check.Equal(Identity, inspected.Receipt.ComputerGuid, "Après interruption, la propriété est rétablie par relecture native et persistée avant toute liaison");
        Check.True(inspected.CanResume, "La perte de persistance n’empêche pas une reprise explicitement préparée après inspection");
    }

    [Test]
    public void OwnershipDomainDcMachineDnDnsSpnAndWindowsChangesAllKeepTheAccount()
    {
        var changes = new Func<JoinReservationObservation, JoinReservationObservation>[]
        {
            e => e with { MachineId = "22222222-2222-2222-2222-222222222222" },
            e => e with { Domain = "other.local" }, e => e with { Dc = "dc02.example.local" },
            e => e with { TargetOuGuid = "22222222-2222-2222-2222-222222222222" },
            e => e with { ComputerGuid = "22222222-2222-2222-2222-222222222222" },
            e => e with { Name = "OTHER" }, e => e with { DistinguishedName = "CN=" + Name + ",OU=Other,DC=example,DC=local" },
            e => e with { Marker = e.Marker!.ToUpperInvariant() }, e => e with { DnsHostName = Name + ".example.local" },
            e => e with { ServicePrincipalNames = ["HOST/" + Name] }, e => e with { PartOfDomain = true },
            e => e with { PendingRename = true }, e => e with { DomainController = true }, e => e with { CurrentComputer = "OTHER-PC" },
            e => e with { Error = "Partial result" },
        };
        foreach (var change in changes)
        {
            using var w = new World(); var r = w.Create().Receipt; w.Native.Alter = change;
            var inspected = w.Service.Inspect(r.Id);
            Check.Equal("kept", inspected.Receipt.State, "Preuve changée conservée");
            Check.False(inspected.CanResume || inspected.CanRelease, "Aucune action avec propriété ou usage changé");
            Check.Equal(0, w.Native.Deletes, "Aucune suppression sur contrôle incomplet");
        }
    }

    [Test]
    public void FailedInspectionIsNeverReportedAsAdAbsence()
    {
        using var w = new World(); var r = w.Create().Receipt; w.Native.ThrowRead = true;
        var inspected = w.Service.Inspect(r.Id);
        Check.Equal("kept", inspected.Receipt.State, "Accès refusé n’est pas Gone");
        Check.True(inspected.Receipt.NeedsReview, "État conservé à vérifier");
        Check.False(inspected.CanRelease, "Aucun retrait permis");
    }

    [Test]
    public void AProcessRestartRequiresFreshInspectionEvenForADurableReservedState()
    {
        using var w = new World(); var r = w.Create().Receipt;
        var reads = w.Native.Reads;
        w.Service = new(w.Store, w.Native, w.Clock);
        var listed = w.Service.List().Single();
        Check.False(listed.CanResume || listed.CanRelease, "Preuve précédente non réutilisée après redémarrage de l’application");
        Check.Equal(reads, w.Native.Reads, "Liste seulement locale");
        Check.Pesto(() => w.Prepare(r), "reservation.evidence", "Inspection obligatoire");
        Check.True(w.Service.Inspect(r.Id).CanRelease, "Clic inspection rétablit une preuve fraîche");
    }

    [Test]
    public void PlansExpireCannotBeForgedAndAreConsumedBeforeNativeRead()
    {
        using var w = new World(); var r = w.Create().Receipt;
        var p = w.Prepare(r);
        Check.False(w.Service.IsAuthorized(p.Authorization with { }), "Copier le token ne recrée pas l’autorité native");
        Check.Pesto(() => w.Service.Release(p.Authorization with { ComputerGuid = "22222222-2222-2222-2222-222222222222" }), "reservation.evidence", "GUID arbitraire refusé");
        w.Native.ThrowRead = true;
        try { w.Service.Release(p.Authorization); throw new TestFailureException("L’inspection doit échouer"); }
        catch (UnauthorizedAccessException) { }
        Check.False(w.Service.IsAuthorized(p.Authorization), "Grant consommé même si relecture échoue");
        Check.Equal(0, w.Native.Deletes, "Aucune suppression avant contrôle");
        w.Native.ThrowRead = false; r = w.Service.Inspect(r.Id).Receipt;
        p = w.Prepare(r); w.Clock.Advance(TimeSpan.FromMinutes(3));
        Check.Pesto(() => w.Service.Release(p.Authorization), "reservation.evidence", "Plan expiré refusé");
    }

    [Test]
    public void ReplacedReceiptInvalidatesThePreparedNativeAuthority()
    {
        using var w = new World(); var r = w.Create().Receipt; var p = w.Prepare(r);
        w.Store.Save(r with { Revision = r.Revision + 1, Message = "New durable evidence" }, w.Store.Stamp(r.Id));
        Check.Pesto(() => w.Service.Release(p.Authorization), "reservation.evidence", "Empreinte du reçu changée");
        Check.Equal(0, w.Native.Deletes, "Aucune suppression avec un reçu modifié");
    }

    [Test]
    public void ConcurrentReceiptChangeDuringNativeInspectionIsPreservedBeforeRemoval()
    {
        using var w = new World(); var r = w.Create().Receipt; var p = w.Prepare(r);
        w.Native.Alter = evidence =>
        {
            var (current, stamp) = w.Store.ReadStamped(r.Id);
            w.Store.Save(current with { Revision = current.Revision + 1, Message = "Concurrent inspection preserved" }, stamp);
            return evidence;
        };
        var refused = false; try { _ = w.Service.Release(p.Authorization); } catch (IOException) { refused = true; }
        Check.True(refused, "La preuve initiale ne peut pas écraser une modification pendant la relecture");
        Check.Equal("Concurrent inspection preserved", w.Store.Read(r.Id).Message, "Modification concurrente conservée");
        Check.Equal(0, w.Native.Deletes, "Aucune suppression sur snapshot remplacé");
    }

    [Test]
    public void ConfirmedReleasePersistsPendingFirstAndRequiresAbsenceAfterTheExactGuidRemoval()
    {
        using var w = new World(); var r = w.Create().Receipt; var p = w.Prepare(r);
        var released = w.Service.Release(p.Authorization);
        Check.Equal("releasing", w.Native.DeleteSawState, "Reçu de retrait avant Remove-ADComputer");
        Check.Equal("released", released.Receipt.State, "Absence relue après retrait");
        Check.Equal(1, w.Native.Deletes, "Une seule suppression explicitement confirmée");
        Check.Equal("receipt-parent", released.Receipt.ResolvedParents!.Single().ReceiptId, "Résolution liée aux octets du join parent");
        Check.False(released.CanResume || released.CanRelease, "Aucun rejeu");
        Check.Pesto(() => w.Service.Release(p.Authorization), "reservation.evidence", "Plan consommé");
    }

    [Test]
    public void UncertainRemovalIsKeptWithoutAnAutomaticSecondRemoval()
    {
        using var w = new World(); var r = w.Create().Receipt; var p = w.Prepare(r); w.Native.DeleteUncertain = true;
        var uncertain = w.Service.Release(p.Authorization);
        Check.Equal("uncertain", uncertain.Receipt.State, "Une réponse perdue n’est pas Released");
        Check.True(uncertain.Receipt.NeedsReview, "Nouvelle inspection exigée");
        Check.Null(uncertain.Receipt.ResolvedParents, "Aucune levée des barrières parentes sans preuve");
        Check.Equal(1, w.Native.Deletes, "Pas de retry");
    }

    [Test]
    public void ProvenAbsenceCanResolveTheReceiptOnlyAfterASeparateConfirmedPlan()
    {
        using var w = new World(); var r = w.Create().Receipt; w.Native.Absent = true;
        var inspected = w.Service.Inspect(r.Id);
        Check.Equal("gone", inspected.Receipt.State, "Absence du GUID sur le DC exact");
        Check.False(inspected.CanResume, "Jamais de recréation implicite");
        Check.Null(inspected.Receipt.ResolvedParents, "Inspection seule ne retire pas les anciennes barrières");
        var result = w.Service.Release(w.Prepare(inspected.Receipt).Authorization);
        Check.Equal("gone", result.Receipt.State, "Absence confirmée enregistrée");
        Check.Equal(0, w.Native.Deletes, "Aucun Remove inutile sur objet absent");
        Check.NotNull(result.Receipt.ResolvedParents, "Levée limitée aux parents confirmés");
    }

    [Test]
    public void InterruptedJoinNeedsPostBootEvidenceAndNeverDeletesOrRecreatesTheReservation()
    {
        using var w = new World(); var r = w.Create().Receipt;
        var a = w.Prepare(r, "initialJoin", "plan-confirmed").Authorization;
        _ = w.Service.BeginJoin(a, "receipt-parent");
        var uncertain = w.Service.CompleteJoin(r.Id, new(MutationStatus.Failed, 5, "Native refused", false));
        Check.Equal("uncertain", uncertain.State, "Compte créé préalablement : pas de Failed zéro écriture");
        Check.False(w.Service.Inspect(r.Id).CanResume, "Même boot ne prouve pas absence de jonction en attente");
        w.Clock.Advance(TimeSpan.FromHours(2)); w.Native.Boot = w.Clock.GetUtcNow().AddMinutes(-1);
        var fresh = w.Service.Inspect(r.Id);
        Check.True(fresh.CanResume, "État postboot unjoined + compte exact inutilisé");
        var resume = w.Prepare(fresh.Receipt, "resumeJoin", "plan-resume").Authorization;
        var begun = w.Service.BeginJoin(resume, "receipt-child");
        Check.Equal(2, begun.JoinReceiptIds.Length, "Reçu de reprise distinct, append-only");
        Check.Pesto(() => w.Service.BeginJoin(resume, "receipt-other"), "reservation.evidence", "Aucun rejeu de la même autorisation");
        Check.Equal(1, w.Native.Creates, "Reprise du GUID, sans deuxième création");
        Check.Equal(0, w.Native.Deletes, "Compte conservé");
    }

    [Test]
    public void AcceptedJoinConsumesTheReservationWithoutPretendingRebootOrDeletingTheAccount()
    {
        using var w = new World(); var r = w.Create().Receipt;
        var a = w.Prepare(r, "initialJoin", "plan-confirmed").Authorization;
        _ = w.Service.BeginJoin(a, "receipt-parent");
        var completed = w.Service.CompleteJoin(r.Id, new(MutationStatus.PendingRestart, 10, "Accepted, reboot manual", true, Identity));
        Check.Equal("consumed", completed.State, "Réservation désormais utilisée par le join");
        Check.False(w.Service.Inspect(r.Id).CanRelease, "Aucun retrait du compte repris");
        Check.Equal(0, w.Native.Deletes, "Aucun nettoyage automatique");
    }

    [Test]
    public void OrphanPreSendChildIsTrackedWithoutAnyAdOperation()
    {
        using var w = new World(); var r = w.Create().Receipt; var reads = w.Native.Reads;
        w.Service.TrackLinkedReceipt(r.Id, "receipt-interrupted-child");
        var stored = w.Store.Read(r.Id);
        Check.Equal(2, stored.JoinReceiptIds.Length, "Enfant pré-send durable retrouvé");
        Check.Equal(reads, w.Native.Reads, "Récupération du lien seulement locale");
        Check.False(w.Service.View(stored).CanResume, "Une inspection explicite reste requise");
    }

    [Test]
    public void ClosedSchemaPathsAndSymlinksRefuseWithoutNativeWrites()
    {
        using var w = new World(); var r = w.Create().Receipt;
        Check.Pesto(() => w.Store.Read("../receipt-parent"), "reservation.id", "Le navigateur ne peut pas fournir un chemin");
        var path = Path.Combine(w.Store.DirectoryPath, r.Id + ".json");
        var original = File.ReadAllText(path);
        var changedMarker = JsonNode.Parse(original)!.AsObject(); changedMarker["Marker"] = "Réservé par un autre";
        foreach (var invalid in new[] { original.Insert(1, "\"Password\":\"forbidden\","), original.Insert(1, "\"Schema\":1,"), changedMarker.ToJsonString() })
        {
            File.WriteAllText(path, invalid);
            var refused = false; try { w.Store.Read(r.Id); } catch (IOException) { refused = true; }
            Check.True(refused, "Schéma inconnu, doublon ou marqueur invalide refusé");
        }
        File.WriteAllText(path, original);
        var linkedRoot = Path.Combine(w.Root, "link");
        try
        {
            Directory.CreateSymbolicLink(linkedRoot, w.Store.DirectoryPath);
            var refused = false; try { _ = new JoinReservationStore(linkedRoot); } catch (IOException) { refused = true; }
            Check.True(refused, "Registre via lien refusé");
        }
        catch (Exception e) when (e is UnauthorizedAccessException or PlatformNotSupportedException or System.Security.SecurityException) { }
        Check.Equal(0, w.Native.Deletes, "Aucune suppression AD issue de la validation de fichiers");
    }

    [Test]
    public void NativePayloadKeepsTheExactReservationIdentityWithoutTransportingTheGrant()
    {
        using var w = new World(); var r = w.Create().Receipt;
        var a = w.Prepare(r, "resumeJoin", "plan-resume").Authorization;
        var request = w.Request("receipt-child") with { ComputerGuid = Identity, Reservation = a, PlanId = a.PlanId };
        var json = PowerShellMutationGateway.BuildPayload(request, "false");
        using var document = JsonDocument.Parse(json);
        var reservation = document.RootElement.GetProperty("Reservation");
        Check.Equal(Identity, reservation.GetProperty("ComputerGuid").GetString(), "GUID exact envoyé au worker fixe");
        Check.Equal(r.Marker, reservation.GetProperty("Marker").GetString(), "Marqueur exact persisté");
        Check.Equal(Machine, reservation.GetProperty("MachineId").GetString(), "Lien avec machine Windows");
        Check.Equal(r.Dc, reservation.GetProperty("Dc").GetString(), "DC figé");
        Check.False(json.Contains(a.Token, StringComparison.Ordinal), "Token natif non transmis dans le payload");
        Check.False(json.Contains(a.ReservationSha256, StringComparison.Ordinal), "Autorité de remplacement non sérialisée au worker");
    }

    [Test]
    public void NativeWorkersRetainStableBootOwnershipGroupAndNoCreationJoinGuards()
    {
        var worker = PowerShellMutationGateway.ReservationWorkerScript;
        Check.Contains("$boot=Get-PestoStableBootUtc", worker, "Identité boot stable V1");
        Check.False(worker.Contains("LastBootUpTime", StringComparison.Ordinal), "Pas de repli CIM sensible à la correction d’horloge");
        Check.Contains("Assert-OwnedUnused $observation", worker, "Propriété et absence d’usage revérifiées");
        Check.Contains("Assert-PestoGroupExclusions ([string]$j.ComputerGuid)", worker, "Groupes relus avant retrait");
        Check.Contains("Remove-ADComputer -Identity ([Guid]$j.ComputerGuid) -Confirm:$false", worker, "Suppression par GUID seulement");
        Check.Contains("[IO.FileShare]::Read", worker, "Configuration figée jusqu’à fin de l’action native");
        Check.Contains("Global\\GP_JoinReservation_", worker, "Le worker conserve son verrou même après interruption du parent");
        foreach (var forbidden in new[] { "Set-Acl", "Set-ADObject", "Restart-Computer", "shutdown.exe", "takeown", "icacls" })
            Check.False(worker.Contains(forbidden, StringComparison.OrdinalIgnoreCase), "Aucune ACL/propriété, élévation ou reprise Windows implicite : " + forbidden);
        var main = PowerShellMutationGateway.ConstantScript;
        Check.Contains("-Options JoinWithNewName -PassThru", main, "Le join réservé exclut AccountCreate explicitement");
        Check.Contains("Assert-PestoReservedJoinResult $j.Reservation $adp", main, "GUID vérifié après la jonction");
    }

    [Test]
    public void ReservationWorkerFitsTheWindowsCommandLineAndPinsTheEntireCompiledScript()
    {
        var type = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.PowerShellJoinReservationNative")!;
        var start = (ProcessStartInfo)type.GetMethod("WorkerStartInfo", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, null)!;
        var commandLength = start.FileName.Length + start.ArgumentList.Sum(argument => argument.Length + 3) + 3;
        Check.True(commandLength < 8000, "La vraie commande reste largement sous la limite Windows CreateProcess de 32767 caractères");
        Check.True(start.RedirectStandardInput && start.RedirectStandardOutput && start.RedirectStandardError && !start.UseShellExecute,
            "Transport privé par pipes, aucun script ni secret dans un fichier de travail");
        var encoded = start.ArgumentList.IndexOf("-EncodedCommand");
        Check.True(encoded >= 0 && encoded + 1 == start.ArgumentList.Count - 1, "Seul le bootstrap court figure dans la ligne de commande");
        var bootstrap = Encoding.Unicode.GetString(Convert.FromBase64String(start.ArgumentList[encoded + 1]));
        var activityType = typeof(PowerShellMutationGateway).Assembly.GetType("Pesto.Engine.Live.WindowsAcknowledgementActivity")!;
        var activity = (string)activityType.GetField("Script", BindingFlags.Static | BindingFlags.NonPublic)!.GetRawConstantValue()!;
        var activityPattern = System.Text.RegularExpressions.Regex.Match(activity, @"\$body -match '([^']+)'").Groups[1].Value;
        Check.True(activityPattern.Length > 0, "Le vrai filtre natif de barrière est lu, pas une copie de test");
        Check.True(System.Text.RegularExpressions.Regex.IsMatch(bootstrap, activityPattern), "Une réservation active reste reconnue après le changement de transport");
        Check.True(System.Text.RegularExpressions.Regex.IsMatch(PowerShellMutationGateway.WorkerBootstrap, activityPattern), "Une mutation active reste reconnue avant acquittement");
        var script = PowerShellMutationGateway.ReservationWorkerScript;
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(script)));
        Check.Contains(hash, bootstrap, "Le bootstrap exige le SHA de toute la constante de réservation avant son exécution");
        Check.Contains("[Console]::In.ReadLine()", bootstrap, "La constante arrive sur la première ligne du pipe après rattachement au Job Object");
        Check.Contains("if($actual -cne '" + hash + "'){exit 96}", bootstrap, "Un script substitué est refusé avant tout accès AD");
        Check.False(bootstrap.Contains("New-ADComputer", StringComparison.Ordinal), "La commande native complète ne repasse pas par les arguments Windows");
        Check.Contains("[Console]::In.ReadToEnd()", script, "Le worker ne consomme ensuite que le JSON restant");
    }
}

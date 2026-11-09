using System.Security.Cryptography;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>Reservation state machine. Production holds Global\GP_PostMutation_v1 around every call;
/// fixture transports exercise the same durability and ownership rules without AD.</summary>
public sealed class JoinReservationCoordinator(JoinReservationStore store, IJoinReservationNative native, TimeProvider? timeProvider = null)
{
    private readonly TimeProvider clock = timeProvider ?? TimeProvider.System;
    private readonly Dictionary<string, (string Stamp, JoinReservationObservation Evidence, DateTimeOffset At)> inspections = new(StringComparer.Ordinal);
    private readonly Dictionary<string, JoinReservationAuthorization> grants = new(StringComparer.Ordinal);

    public IReadOnlyList<JoinReservationView> List() => store.List().Select(View).ToArray();
    public JoinReservationReceipt Read(string id) => store.Read(id);
    public string Stamp(string id) => store.Stamp(id);
    private static PestoException Refusal(string message) => new("reservation.evidence", message);
    private DateTimeOffset Now => clock.GetUtcNow();

    /// <summary>Recover a linked pre-send join receipt written just before a process interruption.
    /// The native adapter validates its entire immutable tuple and file identity first. No AD command runs.</summary>
    public void TrackLinkedReceipt(string id, string joinReceiptId)
    {
        if (!JoinReservationStore.IsOpaqueId(joinReceiptId)) throw Refusal("Identité enfant invalide.");
        var (receipt, stamp) = store.ReadStamped(id);
        if (receipt.JoinReceiptIds.Contains(joinReceiptId, StringComparer.Ordinal)) return;
        if (JoinReservationStore.IsTerminal(receipt.State)) throw Refusal("Un reçu enfant inconnu est lié à une réservation résolue : vérification manuelle nécessaire.");
        var updated = receipt with { JoinReceiptIds = [.. receipt.JoinReceiptIds, joinReceiptId], InspectedUtc = null,
            UpdatedUtc = Now, Revision = receipt.Revision + 1, NeedsReview = true,
            Message = "Reçu de reprise interrompue retrouvé ; inspection explicite requise avant tout nouvel envoi." };
        store.Save(updated, stamp);
        Invalidate(id);
    }

    public JoinReservationView View(JoinReservationReceipt receipt)
    {
        var fresh = inspections.TryGetValue(receipt.Id, out var proof) && proof.At.AddMinutes(2) > Now
            && proof.Stamp == store.Stamp(receipt.Id) && EvidenceRefusal(receipt, proof.Evidence) is null;
        return new(receipt, fresh && receipt.State == "reserved" && !proof.Evidence.Absent,
            fresh && receipt.State is "reserved" or "gone");
    }

    public static string? EvidenceRefusal(JoinReservationReceipt r, JoinReservationObservation o)
    {
        if (o.Error is not null) return "La lecture native est incomplète : le compte reste conservé.";
        if (!JoinReservationStore.IsGuid(o.MachineId) || !JoinReservationStore.Same(r.MachineId, o.MachineId))
            return "Le reçu appartient à une autre installation Windows : aucun compte repris ou supprimé.";
        if (!JoinReservationStore.Same(r.Domain, o.Domain) || !JoinReservationStore.Same(r.Dc, o.Dc)
            || !JoinReservationStore.Same(r.TargetOuGuid, o.TargetOuGuid))
            return "Domaine, contrôleur ou GUID d’OU différents du reçu : le compte reste conservé.";
        if (o.BootUtc == default || (!JoinReservationStore.Same(r.Computer, o.CurrentComputer) && !JoinReservationStore.Same(r.Name, o.CurrentComputer))
            || o.PartOfDomain || o.PendingRename || o.DomainController)
            return "L’état Windows n’autorise pas la reprise : domaine actif, nom en attente, rôle sensible ou identité locale différente.";
        // A sent join can leave pending Windows state. Reinspection on the same boot cannot prove its absence.
        if (r.JoinAttempted && (r.LastJoinBootUtc is null || o.BootUtc <= r.LastJoinBootUtc))
            return "Une jonction a pu être envoyée : après le redémarrage décidé par l’opérateur, inspectez à nouveau le reçu avant toute reprise ou tout retrait.";
        if (o.Absent) return null;
        if (!JoinReservationStore.IsGuid(o.ComputerGuid) || (r.ComputerGuid is not null && !JoinReservationStore.Same(r.ComputerGuid, o.ComputerGuid))
            || !JoinReservationStore.Same(r.Name, o.Name)
            || !JoinReservationStore.Same("CN=" + r.Name + "," + r.TargetOu, o.DistinguishedName)
            || !string.Equals(r.Marker, o.Marker, StringComparison.Ordinal))
            return "GUID, nom, DN exact ou marqueur de propriété différents du reçu : aucun compte repris ou supprimé.";
        if (!string.IsNullOrEmpty(o.DnsHostName) || o.ServicePrincipalNames is null || o.ServicePrincipalNames.Length != 0)
            return "Le compte possède un nom DNS ou un SPN : il est utilisé et reste conservé, sans retrait automatique.";
        return null;
    }

    public JoinReservationView Create(MutationRequest join, string machineId, Action? beforeNative = null)
    {
        if (join.Kind != "join" || !join.ReservationRequired || join.Reservation is not null || join.NewName is null || join.TargetOu is null
            || join.TargetOuGuid is null || join.Dc is null) throw Refusal("La réservation exige un plan de jonction locale complet avec un DC figé.");
        if (store.List().Any(r => !JoinReservationStore.IsTerminal(r.State))) throw Refusal("Une réservation conservée doit être inspectée et résolue avant toute nouvelle création.");
        var operation = Guid.NewGuid().ToString("D");
        var pending = new JoinReservationReceipt(1, "reservation-" + Guid.NewGuid().ToString("N"), operation,
            join.ReceiptId, [join.ReceiptId], join.Computer, join.NewName, join.Domain, join.Dc, join.TargetOu, join.TargetOuGuid,
            machineId, JoinReservationStore.MarkerFor(operation), null, "pending", true,
            "Réservation confirmée ; reçu durable écrit avant New-ADComputer. Résultat non encore observé.", Now, Now);
        var stamp = store.Save(pending); // Failure here prevents even entering the native transport.
        JoinReservationNativeResult result;
        var permitted = true;
        string? beforeNativeRefusal = null;
        try { beforeNative?.Invoke(); }
        catch (Exception error) { permitted = false; beforeNativeRefusal = error.Message; }
        if (!permitted) result = new("refused", "Vérification finale refusée avant New-ADComputer : " + Safe(beforeNativeRefusal ?? "preuve non confirmée"));
        else
        {
            try { result = native.Create(pending); }
            catch (Exception) { result = new("uncertain", "Création envoyée ou état inconnu : le compte éventuel reste conservé.", MutationMayHaveStarted: true); }
        }
        var observation = result.Observation;
        var good = result.State == "reserved" && observation is { Absent: false } && EvidenceRefusal(pending, observation) is null;
        var definitelyNone = !result.MutationMayHaveStarted && result.State is "refused" or "taken";
        var completed = pending with
        {
            ComputerGuid = observation is not null && JoinReservationStore.IsGuid(observation.ComputerGuid)
                && JoinReservationStore.Same(pending.Name, observation.Name)
                && string.Equals(pending.Marker, observation.Marker, StringComparison.Ordinal) ? observation.ComputerGuid : null,
            State = good ? "reserved" : definitelyNone ? result.State : "uncertain",
            NeedsReview = !good && !definitelyNone,
            Message = good ? "Nom réservé dans l’AD ; GUID, DN et marqueur relus sur le DC figé. Aucune suppression automatique."
                : definitelyNone ? Safe(result.Message) : "Résultat de création incomplet ou incertain : compte conservé, inspection explicite requise.",
            UpdatedUtc = Now, Revision = pending.Revision + 1,
            InspectedUtc = good ? Now : null, CurrentComputer = good ? observation!.CurrentComputer : null,
            CurrentBootUtc = good ? observation!.BootUtc : null,
        };
        string completedStamp;
        try { completedStamp = store.Save(completed, stamp); }
        catch (Exception)
        {
            inspections.Remove(pending.Id);
            return new(completed with { State = "uncertain", NeedsReview = true,
                Message = "La preuve de création n’a pas pu être enregistrée ; le reçu pending est conservé. Aucune jonction ni suppression lancée." }, false, false);
        }
        if (good) Remember(completed, observation!, completedStamp);
        return View(completed);
    }

    public JoinReservationView Inspect(string id)
    {
        Invalidate(id);
        var (receipt, stamp) = store.ReadStamped(id);
        if (receipt.State is "released" or "taken" or "refused") return new(receipt, false, false);
        JoinReservationObservation? evidence = null;
        string? failure;
        try { evidence = native.Read(receipt); failure = EvidenceRefusal(receipt, evidence); }
        catch (Exception) { failure = "La lecture du reçu dans AD a échoué : aucune absence ni propriété supposée."; }
        var resolved = receipt.State == "consumed";
        var safe = failure is null && !resolved;
        var inspected = receipt with
        {
            ComputerGuid = safe && evidence is { Absent: false } ? evidence.ComputerGuid : receipt.ComputerGuid,
            State = resolved ? "consumed" : safe ? evidence!.Absent ? "gone" : "reserved" : "kept",
            NeedsReview = !safe && !resolved,
            Message = resolved ? "Ce compte a été confié à une jonction acceptée : aucune nouvelle jonction ni suppression depuis ce reçu. Consultez le reçu de jonction."
                : safe ? evidence!.Absent ? "Absence de l’objet confirmée sur le DC du reçu ; aucun objet supprimé par cette inspection."
                    : "Compte réservé et inutilisé relu : une reprise ou un retrait peut être préparé puis confirmé séparément."
                : failure!,
            InspectedUtc = safe ? Now : null, CurrentComputer = safe ? evidence!.CurrentComputer : receipt.CurrentComputer,
            CurrentBootUtc = safe ? evidence!.BootUtc : receipt.CurrentBootUtc,
            Revision = receipt.Revision + 1, UpdatedUtc = Now,
        };
        var inspectedStamp = store.Save(inspected, stamp);
        if (safe) Remember(inspected, evidence!, inspectedStamp);
        return View(inspected);
    }

    private void Remember(JoinReservationReceipt receipt, JoinReservationObservation evidence, string stamp) =>
        inspections[receipt.Id] = (stamp, evidence, Now);
    private void Invalidate(string id)
    {
        inspections.Remove(id);
        foreach (var token in grants.Where(p => p.Value.ReservationId == id).Select(p => p.Key).ToArray()) grants.Remove(token);
    }

    public JoinReservationPreparation Prepare(string id, string action, string planId, IReadOnlyList<JoinReservationParent> parents, string configurationSha256)
    {
        if (action is not ("initialJoin" or "resumeJoin" or "release") || !JoinReservationStore.IsOpaqueId(planId)
            || !JoinReservationStore.IsHash(configurationSha256))
            throw Refusal("Action ou plan de réservation invalide.");
        var (receipt, stamp) = store.ReadStamped(id);
        var view = View(receipt);
        if ((action == "release" ? !view.CanRelease : !view.CanResume)) throw Refusal("Inspectez explicitement cette réservation avant de préparer une action : aucune preuve fraîche disponible.");
        if (parents.Count != receipt.JoinReceiptIds.Length || parents.Any(p => !JoinReservationStore.IsHash(p.Sha256)
            || !receipt.JoinReceiptIds.Contains(p.ReceiptId, StringComparer.Ordinal))
            || parents.Select(p => p.ReceiptId).Distinct(StringComparer.Ordinal).Count() != parents.Count)
            throw Refusal("Les reçus de jonction liés ne sont pas tous vérifiés.");
        foreach (var token in grants.Where(p => p.Value.ReservationId == id).Select(p => p.Key).ToArray()) grants.Remove(token);
        var authorization = new JoinReservationAuthorization(Convert.ToHexString(RandomNumberGenerator.GetBytes(32)), id,
            stamp, planId, action, inspections[id].Evidence.CurrentComputer, receipt.Name, receipt.Domain, receipt.Dc,
            receipt.TargetOu, receipt.TargetOuGuid, receipt.MachineId, receipt.ComputerGuid, receipt.Marker, Now.AddMinutes(2), parents.ToArray(), configurationSha256);
        grants.Add(authorization.Token, authorization);
        return new(view, authorization);
    }

    public bool IsAuthorized(JoinReservationAuthorization authorization)
    {
        try
        {
            return grants.TryGetValue(authorization.Token, out var known) && ReferenceEquals(known, authorization)
                && authorization.ExpiresAt > Now && store.Stamp(authorization.ReservationId) == authorization.ReservationSha256;
        }
        catch (Exception) { return false; }
    }

    private (JoinReservationReceipt Receipt, JoinReservationObservation Evidence) Consume(JoinReservationAuthorization authorization)
    {
        if (!IsAuthorized(authorization)) throw Refusal("Autorisation absente, remplacée, périmée ou déjà consommée : aucun envoi.");
        grants.Remove(authorization.Token); // before the first potentially failing read or native action
        var (receipt, stamp) = store.ReadStamped(authorization.ReservationId);
        if (stamp != authorization.ReservationSha256) throw Refusal("Le reçu a changé pendant la consommation du plan.");
        var evidence = native.Read(receipt);
        if (EvidenceRefusal(receipt, evidence) is { } failure) throw Refusal(failure);
        if (!JoinReservationStore.Same(evidence.CurrentComputer, authorization.Computer)
            || (!evidence.Absent && !JoinReservationStore.Same(evidence.ComputerGuid, authorization.ComputerGuid))
            || (authorization.Action != "release" && evidence.Absent))
            throw Refusal("La preuve locale ou le GUID a changé depuis le plan : aucune commande lancée.");
        inspections.Remove(receipt.Id);
        return (receipt, evidence);
    }

    public JoinReservationReceipt BeginJoin(JoinReservationAuthorization authorization, string joinReceiptId)
    {
        if (authorization.Action is not ("initialJoin" or "resumeJoin") || !JoinReservationStore.IsOpaqueId(joinReceiptId))
            throw Refusal("Autorisation de jonction attendue.");
        var (receipt, evidence) = Consume(authorization);
        var ids = receipt.JoinReceiptIds.Contains(joinReceiptId, StringComparer.Ordinal) ? receipt.JoinReceiptIds : [.. receipt.JoinReceiptIds, joinReceiptId];
        var starting = receipt with { State = "joining", NeedsReview = true, JoinAttempted = true, LastJoinBootUtc = evidence.BootUtc,
            JoinReceiptIds = ids, InspectedUtc = null, CurrentComputer = evidence.CurrentComputer, CurrentBootUtc = evidence.BootUtc,
            UpdatedUtc = Now, Revision = receipt.Revision + 1,
            Message = "GUID réservé figé ; reçu durable enregistré avant la jonction. Aucun retrait automatique en cas de refus ou d’interruption." };
        store.Save(starting, authorization.ReservationSha256);
        return starting;
    }

    public JoinReservationReceipt CompleteJoin(string id, MutationOutcome outcome)
    {
        var (receipt, stamp) = store.ReadStamped(id);
        if (receipt.State != "joining") throw Refusal("Aucune jonction réservée en cours pour ce reçu.");
        var accepted = outcome.Status is MutationStatus.PendingRestart or MutationStatus.Succeeded;
        var completed = receipt with { State = accepted ? "consumed" : "uncertain", NeedsReview = !accepted,
            UpdatedUtc = Now, Revision = receipt.Revision + 1,
            Message = accepted ? "La jonction a accepté le compte réservé ; consultez son reçu et planifiez vous-même le redémarrage. Aucun retrait depuis cette réservation."
                : "Jonction non confirmée ; le compte réservé est conservé. Inspection après le redémarrage décidé par l’opérateur avant toute nouvelle reprise ou tout retrait." };
        store.Save(completed, stamp);
        return completed;
    }

    public JoinReservationView Release(JoinReservationAuthorization authorization, Action? beforeNative = null)
    {
        if (authorization.Action != "release") throw Refusal("Une autorisation de retrait explicite est requise.");
        var (receipt, evidence) = Consume(authorization);
        var pending = receipt with { State = "releasing", NeedsReview = true, InspectedUtc = null,
            UpdatedUtc = Now, Revision = receipt.Revision + 1,
            Message = "Retrait explicitement confirmé ; preuve relue et reçu écrit avant Remove-ADComputer." };
        var pendingStamp = store.Save(pending, authorization.ReservationSha256);
        JoinReservationNativeResult result;
        try
        {
            beforeNative?.Invoke();
            result = evidence.Absent ? new("gone", "L’objet était déjà absent ; aucune commande de suppression envoyée.", evidence)
                : native.Remove(pending);
        }
        catch (Exception) { result = new("uncertain", "Le retrait peut avoir été envoyé ; vérification explicite requise.", MutationMayHaveStarted: true); }
        var absent = result.Observation is { Absent: true } observed && EvidenceRefusal(receipt, observed) is null;
        var success = result.State is "released" or "gone" && absent;
        var completed = pending with
        {
            State = success ? result.State : "uncertain", NeedsReview = !success, UpdatedUtc = Now, Revision = pending.Revision + 1,
            ResolvedParents = success ? authorization.Parents.ToArray() : null,
            Message = success ? "Absence de l’objet confirmée après l’action explicitement choisie. Le reçu conserve les identités et les opérations antérieures."
                : "Retrait non confirmé ; compte éventuel conservé, aucune suppression ni reprise automatique supplémentaire.",
        };
        try { store.Save(completed, pendingStamp); }
        catch (Exception) { return new(pending with { State = "uncertain", NeedsReview = true,
            Message = "Le résultat du retrait n’a pas pu être enregistré ; le reçu releasing reste à inspecter." }, false, false); }
        return new(completed, false, false);
    }

    private static string Safe(string text) => text.Length <= 2048 ? text : text[..2048];
}

using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private sealed class ReservationPlan
    {
        public required JoinReservationPreparation Preparation { get; init; }
        public bool Used;
    }
    private readonly Dictionary<string, ReservationPlan> reservationPlans = new(StringComparer.Ordinal);

    private IMutationJoinReservation RequireReservations() => mutation as IMutationJoinReservation
        ?? throw new PestoException("reservation.unavailable", "Le registre natif des réservations n’est pas disponible dans cette session.");

    private static JsonObject ReservationNode(JoinReservationView value)
    {
        var r = value.Receipt;
        return Resp.Obj(("id", r.Id), ("state", r.State), ("name", r.Name), ("computer", r.Computer),
            ("domain", r.Domain), ("dc", r.Dc), ("targetOU", r.TargetOu), ("message", r.Message),
            ("needsReview", r.NeedsReview), ("canResume", value.CanResume), ("canRelease", value.CanRelease),
            ("parentReceiptId", r.ParentReceiptId), ("updatedAt", Iso(r.UpdatedUtc)),
            ("inspectedAt", r.InspectedUtc is { } at ? Iso(at) : null), ("mode", "live"));
    }

    private JsonObject ReservationsList(JsonElement args)
    {
        Arguments.Only(args);
        // This call only enumerates bounded local receipts. No configuration, AD, share or HTTP probe.
        var list = mutation is IMutationJoinReservation source ? source.ListReservations() : [];
        return Resp.Obj(("items", Resp.Arr(list, item => (JsonNode?)ReservationNode(item))));
    }

    private void RequireReservationScope(JoinReservationReceipt receipt, V1Config configuration)
    {
        JoinReservationStore.Validate(receipt);
        if (!JoinReservationStore.Same(configuration.Domain, receipt.Domain) || !WithinScope(receipt.TargetOu, configuration.RootOu))
            throw new PestoException("reservation.scope", "La réservation appartient à un autre domaine ou à une autre portée configurée : aucune action.");
    }

    private JsonObject ReservationsInspect(JsonElement args)
    {
        Arguments.Only(args, "id");
        MutationSessionGuard.RequireWritableSession();
        var id = Arguments.Text(args, "id", true);
        var service = RequireReservations();
        var known = service.ListReservations().SingleOrDefault(item => item.Receipt.Id == id)
            ?? throw new PestoException("reservation.missing", "Ce reçu de réservation n’existe pas.");
        RequireReservationScope(known.Receipt, RequireConfig());
        var inspected = service.InspectReservation(id);
        if (!SameReservationIdentity(known.Receipt, inspected.Receipt))
            throw new PestoException("reservation.identity", "L’identité du reçu a changé pendant l’inspection : aucune action préparée.");
        return ReservationNode(inspected);
    }

    private JsonObject ReservationsPrepare(JsonElement args)
    {
        Arguments.Only(args, "id", "action");
        MutationSessionGuard.RequireWritableSession();
        var id = Arguments.Text(args, "id", true);
        var action = Arguments.Text(args, "action", true);
        if (action is not ("resumeJoin" or "release")) throw new PestoException("reservation.action", "Action de réservation non prise en charge.");
        var read = RequireConfig();
        RequireUnchangedConfiguration();
        var service = RequireReservations();
        var known = service.ListReservations().SingleOrDefault(item => item.Receipt.Id == id)
            ?? throw new PestoException("reservation.missing", "Ce reçu de réservation n’existe pas.");
        RequireReservationScope(known.Receipt, read);
        var policy = Policy(read);
        policy.AssertPlan("join", known.Receipt.Computer, known.Receipt.Name, null, known.Receipt.TargetOu, GetConvention(read));
        if (action == "resumeJoin" && !policy.ReserveNamesInAd)
            throw new PestoException("reservation.policy", "La réservation AD est désactivée dans la configuration actuelle : aucune reprise de jonction.");
        if (action == "resumeJoin") _ = CheckJoinClock(policy, "join");
        var planId = "reservation-plan-" + Guid.NewGuid().ToString("N");
        var prepared = service.PrepareReservation(id, action, planId);
        ValidateReservationPreparation(known.Receipt, prepared, action, planId);
        reservationPlans[planId] = new() { Preparation = prepared };
        var r = prepared.Reservation.Receipt;
        var a = prepared.Authorization;
        var steps = action == "release"
            ? new[] { new Step("Relire l’identité", "Machine Windows, domaine/DC figés, GUID, DN exact, marqueur et absence de DNS/SPN."),
                new Step("Retirer le compte réservé", "Seulement cet objet, après confirmation exacte ; aucune ACL ni propriété modifiée."),
                new Step("Vérifier l’absence", "Relecture sur le DC du reçu et conservation des reçus de toutes les tentatives.") }
            : new[] { new Step("Relire la réservation", "Uniquement le GUID, le nom et l’OU du reçu ; aucune création de compte supplémentaire."),
                new Step("Reprendre la jonction locale", "Le nom Windows et la jonction restent soumis aux contrôles natifs et à un reçu distinct."),
                new Step("Conserver les preuves", "Aucun retrait ni redémarrage automatique, y compris après un refus ou une interruption.") };
        return Resp.Obj(("planId", a.PlanId), ("reservationId", r.Id), ("action", action), ("mode", "live"),
            ("computer", a.Computer), ("name", r.Name), ("domain", r.Domain), ("dc", r.Dc), ("targetOU", r.TargetOu),
            ("confirmationName", r.Name), ("expiresAt", Iso(a.ExpiresAt)),
            ("steps", Resp.Arr(steps, s => Resp.Obj(("label", s.Label), ("detail", s.Detail)))),
            ("warnings", Resp.Arr(new[] { "Cette préparation ne modifie pas AD. Le plan expire dans deux minutes et ne peut être envoyé qu’une fois.",
                action == "release" ? "Aucun retrait si le GUID, le marqueur, le DN ou l’usage du compte change ; aucun retrait sur fermeture ou annulation."
                    : "Le compte existant reste conservé en cas de résultat incomplet. Le redémarrage reste une décision explicite de l’opérateur." }, s => (JsonNode?)Resp.Node(s))));
    }

    private void ValidateReservationPreparation(JoinReservationReceipt expected, JoinReservationPreparation prepared, string action, string planId)
    {
        var r = prepared.Reservation.Receipt;
        var a = prepared.Authorization;
        if (!SameReservationIdentity(expected, r) || a.ReservationId != r.Id || a.Action != action || a.PlanId != planId
            || a.Token.Length != 64 || !a.Token.All(Uri.IsHexDigit) || !JoinReservationStore.IsHash(a.ReservationSha256)
            || !JoinReservationStore.IsHash(a.ConfigurationSha256) || a.ConfigurationSha256 != configStamp
            || a.ExpiresAt <= clock.GetUtcNow() || a.ExpiresAt > clock.GetUtcNow().AddMinutes(3)
            || !JoinReservationStore.Same(a.Name, r.Name) || !JoinReservationStore.Same(a.Domain, r.Domain)
            || !JoinReservationStore.Same(a.Dc, r.Dc) || !JoinReservationStore.Same(a.TargetOu, r.TargetOu)
            || !JoinReservationStore.Same(a.TargetOuGuid, r.TargetOuGuid) || !JoinReservationStore.Same(a.MachineId, r.MachineId)
            || !JoinReservationStore.Same(a.ComputerGuid, r.ComputerGuid) || a.Marker != r.Marker
            || (!JoinReservationStore.Same(a.Computer, r.Computer) && !JoinReservationStore.Same(a.Computer, r.Name))
            || (action == "resumeJoin" ? !prepared.Reservation.CanResume : !prepared.Reservation.CanRelease))
            throw new PestoException("reservation.authorization", "La preuve native ne correspond pas au reçu et au plan demandés.");
    }

    private static bool SameReservationIdentity(JoinReservationReceipt a, JoinReservationReceipt b) =>
        a.Id == b.Id && a.OperationId == b.OperationId && a.ParentReceiptId == b.ParentReceiptId
        && JoinReservationStore.Same(a.Computer, b.Computer) && JoinReservationStore.Same(a.Name, b.Name)
        && JoinReservationStore.Same(a.Domain, b.Domain) && JoinReservationStore.Same(a.Dc, b.Dc)
        && JoinReservationStore.Same(a.TargetOu, b.TargetOu) && JoinReservationStore.Same(a.TargetOuGuid, b.TargetOuGuid)
        && JoinReservationStore.Same(a.MachineId, b.MachineId) && a.Marker == b.Marker
        && (a.ComputerGuid is null || JoinReservationStore.Same(a.ComputerGuid, b.ComputerGuid));

    private JsonObject ReservationsExecute(JsonElement args)
    {
        MutationSessionGuard.RequireWritableSession();
        Arguments.Only(args, "planId", "confirmationName");
        var planId = Arguments.Text(args, "planId", true);
        if (!reservationPlans.TryGetValue(planId, out var plan)) throw new PestoException("plan.stale", "Ce plan de réservation n’existe plus.");
        var a = plan.Preparation.Authorization;
        if (plan.Used) throw new PestoException("plan.consumed", "Ce plan a déjà été envoyé ; aucune reprise automatique.");
        if (a.ExpiresAt <= clock.GetUtcNow()) throw new PestoException("plan.stale", "Ce plan a expiré ; inspectez puis préparez à nouveau.");
        if (Arguments.Text(args, "confirmationName", true) != a.Name)
            throw new PestoException("confirmation.invalid", "Le nom confirmé ne correspond pas au compte réservé. Inspectez de nouveau la réservation.");
        var read = RequireConfig(); RequireUnchangedConfiguration();
        if (a.ConfigurationSha256 != configStamp)
            throw new PestoException("config.changed", "La configuration a changé depuis ce plan de réservation ; préparez et confirmez un nouveau plan.");
        RequireReservationScope(plan.Preparation.Reservation.Receipt, read);
        var policy = Policy(read);
        policy.AssertPlan("join", a.Computer, a.Name, null, a.TargetOu, GetConvention(read));
        if (a.Action == "resumeJoin" && !policy.ReserveNamesInAd)
            throw new PestoException("reservation.policy", "La réservation AD a été désactivée ; aucune reprise de jonction.");
        if (mutation is null) throw new PestoException("write.unavailable", WriteUnavailable);
        var service = RequireReservations();
        plan.Used = true;
        if (a.Action == "release")
        {
            var result = service.ReleaseReservation(a);
            if (!SameReservationIdentity(plan.Preparation.Reservation.Receipt, result.Receipt))
                throw new PestoException("reservation.identity", "Le résultat ne correspond pas au reçu confirmé ; inspectez avant toute autre action.");
            return Resp.Obj(("reservation", ReservationNode(result)));
        }
        _ = CheckJoinClock(policy, "join");
        var receipt = new Receipt("receipt-" + Guid.NewGuid().ToString("N"), clock.GetUtcNow(), "join", a.Computer,
            a.Name, a.TargetOu, "live · reprise de réservation · " + mutation.Description, "sent", 0,
            "Reprise explicitement confirmée ; reçus persistés avant toute commande native.", false);
        receipts.Insert(0, receipt);
        var request = new MutationRequest("join", a.Computer, a.ComputerGuid, a.Name, a.TargetOu, a.Domain, a.Dc,
            a.PlanId, receipt.Id, TargetOuGuid: a.TargetOuGuid, Reservation: a, ReservationRequired: true, ConfigurationSha256: a.ConfigurationSha256);
        MutationOutcome outcome;
        try { outcome = mutation.Execute(request); }
        catch (Exception) { outcome = new(MutationStatus.Uncertain, 97, "Résultat de reprise inconnu ; le compte reste conservé.", false, a.ComputerGuid); }
        bool confirmed = false;
        try
        {
            var observed = RequireGateway().FindComputer(a.Domain, a.Dc, a.Name);
            confirmed = observed is not null && JoinReservationStore.Same(observed.Guid, a.ComputerGuid)
                && JoinReservationStore.Same(observed.Ou, a.TargetOu);
        }
        catch (Exception) { outcome = outcome with { Status = MutationStatus.Uncertain, Code = 97,
            Message = "La relecture du GUID réservé est indisponible après reprise : aucune réussite supposée. " + outcome.Message }; }
        // The account predates this attempt. Its mere presence cannot prove a join or contradict a pre-send refusal.
        if (outcome.Status == MutationStatus.Succeeded && !confirmed)
            outcome = outcome with { Status = MutationStatus.Uncertain, Code = 97, Message = "L’identité réservée n’est plus confirmée après reprise." };
        var final = Finalize(receipt, request, outcome.Status, outcome.Code, outcome.Message, outcome.RestartRequired,
            confirmed ? a.ComputerGuid : null);
        var current = service.ListReservations().SingleOrDefault(v => v.Receipt.Id == a.ReservationId)
            ?? throw new PestoException("reservation.missing", "Le reçu de réservation ne peut plus être relu ; aucune autre action.");
        return Resp.Obj(("reservation", ReservationNode(current)), ("receipt", final));
    }
}

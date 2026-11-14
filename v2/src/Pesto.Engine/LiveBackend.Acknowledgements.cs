using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private sealed class AcknowledgementPlan
    {
        public required ReceiptAcknowledgementPreparation Preparation { get; init; }
        public required JsonObject OriginalReceipt { get; init; }
        public bool Used;
    }
    private readonly Dictionary<string, AcknowledgementPlan> acknowledgementPlans = new(StringComparer.Ordinal);

    internal string? AcknowledgementCapabilityBlockReason()
    {
        try { _ = RequireAcknowledgements(); return null; }
        catch (PestoException error) { return error.Message; }
        catch (Exception) { return "Le contexte d’acquittement ne peut pas être confirmé : aucun événement autorisé."; }
    }

    private IMutationReceiptAcknowledgement RequireAcknowledgements()
    {
        // Do not use WriteBlockReason: IncidentMode blocks new mutations, not a durable V1 acknowledgement.
        ReceiptAcknowledgementAdmission.RequireSession(Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1",
            mutation is not IMutationAvailability availability || availability.IsAvailable,
            (mutation as IMutationAvailability)?.UnavailableReason);
        var service = mutation as IMutationReceiptAcknowledgement
            ?? throw new PestoException("receipt.acknowledgement_unavailable", "L’acquittement natif des reçus n’est pas disponible dans cette session.");
        _ = RequireConfig();
        var path = V1Config.ConfigPathOf(v1InstallationPath) ?? throw new PestoException("config.missing", "Configuration absente.");
        ReceiptAcknowledgementSource.RequirePlainPath(path);
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length is < 1 or > ConfigurationDocument.MaximumBytes) throw new PestoException("config.invalid", "Configuration illisible.");
        var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes);
        if (!string.Equals(ReceiptAcknowledgementSource.Digest(bytes), configStamp, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("config.changed", "La configuration a changé : préparez un nouvel acquittement.");
        using var memory = new MemoryStream(bytes);
        using var reader = new StreamReader(memory, System.Text.Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        ReceiptAcknowledgementAdmission.RequireConfiguration(reader.ReadToEnd());
        return service;
    }

    private JsonObject ReceiptsPrepareAcknowledgement(JsonElement args)
    {
        Arguments.Only(args, "id");
        var service = RequireAcknowledgements();
        var id = Arguments.Text(args, "id", true, 128);
        var read = RequireConfig(); RequireUnchangedConfiguration();
        var original = (JsonObject)ReceiptsGet(args).DeepClone();
        if (original["acknowledged"]?.GetValue<bool>() == true)
            throw new PestoException("receipt.acknowledgement", "Ce résultat est déjà acquitté.");
        var planId = "ack-plan-" + Guid.NewGuid().ToString("N");
        var prepared = service.PrepareAcknowledgement(id, planId);
        var a = prepared.Authorization;
        if (a.PlanId != planId || a.ReceiptId != id || a.ConfigurationSha256 != configStamp
            || !string.Equals(a.Domain, read.Domain, StringComparison.OrdinalIgnoreCase)
            || a.ExpiresAt <= clock.GetUtcNow() || a.ExpiresAt > clock.GetUtcNow().AddMinutes(3)
            || !ReceiptAcknowledgementSource.IsEligible(a.Phase) || !SameAcknowledgementReceipt(original, ReceiptNode(prepared.Snapshot.Receipt))
            || a.Computer != prepared.Snapshot.Receipt.Computer || a.NewName != prepared.Snapshot.Receipt.NewName
            || a.ConfirmationName != (a.NewName.Length > 0 ? a.NewName : a.Computer)
            || a.TargetsSha256 != prepared.Snapshot.TargetsSha256 || a.TaskProofSha256 != prepared.Snapshot.TaskProofSha256)
            throw new PestoException("receipt.acknowledgement", "La preuve native ne correspond pas au résultat affiché ; relisez le reçu.");
        acknowledgementPlans[planId] = new() { Preparation = prepared, OriginalReceipt = original };
        var warnings = new List<string>
        {
            "L’acquittement conserve la phase, le code et les effets du résultat ; il n’est jamais compté comme une réussite.",
            "Aucune commande AD, réparation ou demande de redémarrage n’est lancée par l’acquittement.",
            "La prochaine opération exigera une nouvelle lecture complète et une confirmation distincte."
        };
        if (prepared.Snapshot.NeedsEntraInspection) warnings.Add("Le retrait Entra reste consigné avec son résultat d’origine ; cet acquittement ne réinscrit pas le poste et n’autorise aucun second retrait implicite.");
        return Resp.Obj(("planId", planId), ("receiptId", a.ReceiptId), ("action", "acknowledge"), ("mode", "live"),
            ("computer", a.Computer), ("newName", a.NewName), ("domain", a.Domain), ("phase", a.Phase), ("code", a.Code),
            ("confirmationName", a.ConfirmationName), ("expiresAt", Iso(a.ExpiresAt)),
            ("warnings", Resp.Arr(warnings, warning => (JsonNode?)Resp.Node(warning))), ("steps", Resp.Arr(
                new[] { new Step("Conserver le résultat d’origine", a.Phase + " · " + (a.Code?.ToString() ?? "sans code consigné")),
                    new Step("Enregistrer votre décision", "Auteur Windows, heure UTC et motif ; événement durable distinct du reçu.") },
                step => Resp.Obj(("label", step.Label), ("detail", step.Detail)))));
    }

    private JsonObject ReceiptsAcknowledge(JsonElement args)
    {
        Arguments.Only(args, "planId", "confirmationName", "reason");
        var service = RequireAcknowledgements();
        var planId = Arguments.Text(args, "planId", true, 128);
        if (!acknowledgementPlans.TryGetValue(planId, out var plan)) throw new PestoException("plan.stale", "Ce plan d’acquittement n’existe plus.");
        var a = plan.Preparation.Authorization;
        if (plan.Used) throw new PestoException("plan.consumed", "Ce plan a déjà été envoyé ; aucun nouvel événement automatique.");
        if (a.ExpiresAt <= clock.GetUtcNow()) throw new PestoException("plan.stale", "Le plan d’acquittement a expiré.");
        if (Arguments.Text(args, "confirmationName", true, 15) != a.ConfirmationName)
            throw new PestoException("confirmation.invalid", "Le nom confirmé ne correspond pas au résultat à acquitter. Préparez de nouveau l’acquittement.");
        var reason = ReceiptAcknowledgementStore.ValidateReason(Arguments.Text(args, "reason", true, 500));
        var read = RequireConfig(); RequireUnchangedConfiguration();
        if (a.ConfigurationSha256 != configStamp || !string.Equals(a.Domain, read.Domain, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("config.changed", "La configuration a changé : préparez un nouvel acquittement.");
        using var getArgs = JsonDocument.Parse(new JsonObject { ["id"] = a.ReceiptId }.ToJsonString());
        var current = ReceiptsGet(getArgs.RootElement);
        if (current["acknowledged"]?.GetValue<bool>() == true || !SameAcknowledgementReceipt(plan.OriginalReceipt, current, includeMessage: true))
            throw new PestoException("receipt.changed", "Le résultat affiché a changé depuis la préparation.");
        plan.Used = true;
        var result = service.Acknowledge(a, reason);
        if (!SameAcknowledgementReceipt(plan.OriginalReceipt, ReceiptNode(result.Receipt))
            || result.Evidence.ReceiptId != a.ReceiptId || result.Evidence.TargetsSha256 != a.TargetsSha256
            || result.Evidence.Event.Reason != reason || result.Evidence.Event.ConfigurationSha256 != a.ConfigurationSha256
            || gpRoot is null || !ReceiptAcknowledgementStore.ValidateApplied(gpRoot, result.Evidence))
            throw new PestoException("receipt.acknowledgement", "L’événement ne peut pas être rapproché du résultat confirmé ; relisez le registre.");
        var node = (JsonObject)plan.OriginalReceipt.DeepClone();
        node["acknowledged"] = true; node["acknowledgement"] = AcknowledgementNode(result.Evidence.Event, a.Phase, a.Code);
        return Resp.Obj(("receipt", node), ("acknowledgement", AcknowledgementNode(result.Evidence.Event, a.Phase, a.Code)),
            ("message", "Acquittement enregistré. Le résultat réel reste inchangé dans l’historique ; aucune réussite n’est ajoutée."));
    }

    private static bool SameAcknowledgementReceipt(JsonObject a, JsonObject b, bool includeMessage = false)
    {
        var fields = new[] { "id", "kind", "computer", "newName", "targetOU", "status", "code", "restartRequired" };
        return fields.All(field => JsonNode.DeepEquals(a[field], b[field]))
            && (!includeMessage || JsonNode.DeepEquals(a["message"], b["message"]));
    }

    private static JsonObject AcknowledgementNode(ReceiptAcknowledgementEvent value, string phase, int? code) =>
        Resp.Obj(("id", value.Id), ("utc", Iso(value.Utc)), ("by", value.By), ("reason", value.Reason), ("phase", phase), ("code", code));

    /// <summary>Used by list/get/dashboard for session receipts too; no network access or mutation.</summary>
    private JsonObject AcknowledgedReceiptNode(Receipt receipt, bool legacyAcknowledged = false)
    {
        ReceiptAcknowledgementEvidence? evidence = null;
        try
        {
            if (gpRoot is not null)
            {
                var candidate = new ReceiptAcknowledgementStore(gpRoot).ReadApplied(receipt.Id);
                if (candidate is not null && SameAcknowledgementReceipt(ReceiptNode(receipt), ReceiptNode(ReceiptAcknowledgementSource.Read(gpRoot, receipt.Id).Receipt))) evidence = candidate;
            }
        }
        catch (Exception) { /* An unreadable/stale event never releases a displayed or native barrier. */ }
        var node = ReceiptNode(receipt, legacyAcknowledged || evidence is not null);
        if (evidence is not null)
        {
            var target = evidence.Event.Targets.FirstOrDefault(item => item.Store == "adapter")
                ?? evidence.Event.Targets.FirstOrDefault(item => item.Store == "intervention") ?? evidence.Event.Targets[0];
            node["acknowledgement"] = AcknowledgementNode(evidence.Event, target.Phase, target.Code);
        }
        return node;
    }
}

using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

/// <summary>One deliberately synchronous CLI request. No prompt, elevation, background replay or restart exists here.</summary>
public static class PestoCliRunner
{
    public static PestoCliResult Run(PestoCliOptions options, AutomationHostContext context, Func<IPestoBackend> backendFactory, TimeProvider? time = null)
    {
        var clock = time ?? TimeProvider.System;
        AutomationExecutionAuthorization? authority = null;
        AutomationJournal? journal = null;
        var executeEntered = false;
        IReadOnlyDictionary<string, string>? metadata = null;
        try
        {
            options.Validate(); AutomationPolicy.RequireContext(context);
            var configPath = Path.Combine(context.ConfigurationDirectory, "cfg.json");
            var configBytes = ReadConfiguration(configPath);
            var configurationJson = new UTF8Encoding(false, true).GetString(configBytes).TrimStart('\uFEFF');
            _ = V1Config.ValidateText(configurationJson);
            var stamp = AutomationPlanRules.Digest(configBytes);
            AutomationPlan? expected = options.PlanPath is null ? null : AutomationPlanRules.Read(options.PlanPath);
            if (expected is not null)
            {
                options = BindOptions(options, expected);
                // Replay may report an expired historical plan, but never a changed profile/machine/configuration.
                AutomationPlanRules.RequireContext(expected, context, stamp, clock.GetUtcNow(), checkExpiry: false);
            }
            metadata = options.MetadataPath is null && expected is not null ? expected.Metadata : AutomationPlanRules.ReadMetadata(options.MetadataPath);
            if (expected is not null && ConfigurationDocument.Fingerprint(JsonSerializer.SerializeToNode(metadata)!)
                != ConfigurationDocument.Fingerprint(JsonSerializer.SerializeToNode(expected.Metadata)!))
                throw AutomationPlanRules.Refused("Les métadonnées fournies ne correspondent plus au plan exporté.");
            var approval = options.ApprovalPath is null ? null
                : new UTF8Encoding(false, true).GetString(AutomationPlanRules.ReadDocument(options.ApprovalPath)).TrimStart('\uFEFF');

            if (options.Execute)
            {
                if (expected is null) throw AutomationPlanRules.Refused("Plan exporté obligatoire avant exécution.");
                journal = new(context, options.IdempotencyKey!);
                var payload = AutomationJournal.PayloadHash(expected, context, options.EntraLeaveConfirmed, approval);
                if (journal.ReadPrevious(payload, expected, clock.GetUtcNow()) is { } previous) return previous;
                AutomationPlanRules.RequireContext(expected, context, stamp, clock.GetUtcNow());
                var managed = ReadManaged(context);
                AutomationPolicy.Require(configurationJson, managed, options, context);
                if (expected.EntraLeaveRequired && !options.EntraLeaveConfirmed)
                    throw new PestoException("automation.confirmation", "Le plan exige --confirm-entra-leave ; aucun retrait Entra n'est implicite.");
                if (!expected.EntraLeaveRequired && options.EntraLeaveConfirmed)
                    throw new PestoException("automation.confirmation", "Le plan n'autorise aucun retrait Entra : retirez cette option ou préparez un autre plan.");
                AutomationCampaignApproval.Require(managed.CampaignApprovalJson, approval, expected, context.OperatorSid, clock.GetUtcNow());
                authority = journal.Begin(expected, payload, options.EntraLeaveConfirmed, approval, clock.GetUtcNow());
                // The first durable intent precedes adapter creation, remote diagnostic tasks and shared-name acquisition.
                var backend = backendFactory();
                if (backend is not IPestoAutomationBackend automation) throw new PestoException("automation.unavailable", "Cet adaptateur ne prend pas en charge l'automatisation réelle.");
                var preparation = automation.PrepareAutomation(options, context, metadata, expected, authority);
                AutomationPlanRules.RequireSameIntent(expected, preparation.Plan);
                if (preparation.ExpiresAt <= clock.GetUtcNow()) throw AutomationPlanRules.Refused("La préparation native a expiré avant l'envoi ; aucune action.");
                // Recheck local policy after any remote preparation wait; no first business effect is allowed otherwise.
                var finalBytes = ReadConfiguration(configPath);
                if (AutomationPlanRules.Digest(finalBytes) != stamp) throw AutomationPlanRules.Refused("La configuration a changé pendant la préparation ; aucune action.");
                var finalManaged = ReadManaged(context);
                AutomationPolicy.Require(configurationJson, finalManaged, options, context);
                AutomationCampaignApproval.Require(finalManaged.CampaignApprovalJson, approval, expected, context.OperatorSid, clock.GetUtcNow());
                executeEntered = true;
                var receipt = automation.ExecuteAutomation(preparation, authority);
                var result = MapReceipt(receipt, authority, context.GpRoot, clock.GetUtcNow());
                journal.Complete(authority, result, clock.GetUtcNow());
                return result;
            }

            AutomationPolicy.Require(configurationJson, ReadManaged(context), options, context);
            var reader = backendFactory();
            if (options.Action is "inspect" or "diagnose")
            {
                var op = options.Action == "inspect" ? "computer.inspect" : "diagnostics.read";
                var args = options.Action == "inspect" ? PestoJson.Element(new { computer = options.Computer ?? context.ComputerName }) : PestoJson.Element(new { });
                var observed = reader.InvokeAsync(op, args).GetAwaiter().GetResult();
                return new(1, "CLI", "Observed", 0, null, false, false, null, clock.GetUtcNow(),
                    "Lecture terminée ; aucune mutation, aucun redémarrage ni nouvelle intention.", Observation: SafeObservation(observed, options.Action));
            }
            if (options.Action == "verify") return Verify(reader, options.ReceiptId!, clock.GetUtcNow());
            if (expected is not null) AutomationPlanRules.RequireContext(expected, context, stamp, clock.GetUtcNow());
            if (reader is not IPestoAutomationBackend preparing) throw new PestoException("automation.unavailable", "La préparation automatisée réelle n'est pas disponible.");
            var prepared = preparing.PrepareAutomation(options, context, metadata, expected);
            AutomationPlanRules.RequireContext(prepared.Plan, context, stamp, clock.GetUtcNow());
            if (expected is not null) AutomationPlanRules.RequireSameIntent(expected, prepared.Plan);
            if (options.OutPlanPath is not null) AutomationPlanRules.Write(options.OutPlanPath, prepared.Plan);
            return new(1, "CLI", "Prepared", 0, null, false, false, null, clock.GetUtcNow(),
                "Plan exact préparé. L'exécution exige ce document exporté, --execute et une clé d'idempotence ; aucun redémarrage automatique.",
                prepared.Plan, metadata);
        }
        catch (Exception error)
        {
            var uncertain = executeEntered || authority is not null && error is IOException;
            var message = error is PestoException pesto ? Safe(pesto.Message)
                : uncertain ? "La demande ne possède pas de résultat durable confirmé. Elle peut avoir été engagée ; aucun rejeu automatique."
                : "La demande CLI ne peut pas être admise ou son document n'est pas accessible ; aucune nouvelle commande envoyée.";
            var result = new PestoCliResult(1, "CLI", uncertain ? "Uncertain" : "Refused", uncertain ? 97 : 96, null,
                false, uncertain, authority?.ReceiptId, clock.GetUtcNow(), message, Metadata: metadata);
            if (authority is not null && journal is not null)
            {
                try { journal.Complete(authority, result, clock.GetUtcNow()); }
                catch (Exception)
                {
                    return result with { State = "Uncertain", ExitCode = 97, MutationStarted = true,
                        Message = "Le résultat final ne peut pas être enregistré. L'intention durable reste bloquante ; inspectez le reçu, sans rejeu automatique." };
                }
            }
            return result;
        }
        finally { journal?.Dispose(); }
    }

    private static MutationManagedPolicy ReadManaged(AutomationHostContext context)
    {
        if (OperatingSystem.IsWindows() && context.ManagedPolicyReader is null)
            throw new PestoException("automation.policy", "Lecteur des restrictions HKLM absent ; aucune automatisation native.");
        return context.ManagedPolicyReader?.Invoke() ?? new();
    }

    internal static byte[] ReadConfiguration(string path)
    {
        SharedCoordinationProtocol.RequireNoLinks(path);
        using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (input.Length is < 1 or > V1Config.MaximumFileBytes) throw AutomationPlanRules.Refused("Configuration absente ou trop volumineuse.");
        var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes); return bytes;
    }

    private static PestoCliOptions BindOptions(PestoCliOptions options, AutomationPlan plan)
    {
        if (options.Action != plan.Action) throw AutomationPlanRules.Refused("L'action demandée diffère du plan exporté.");
        foreach (var (supplied, expected) in new[] { (options.Computer, plan.Computer), (options.NewName, plan.NewName), (options.TargetOu, plan.TargetOu),
            (options.Type, plan.Type), (options.SiteCode, plan.SiteCode), (options.ServiceCode, plan.ServiceCode) })
            if (supplied is not null && !AutomationPlanRules.Same(supplied, expected)) throw AutomationPlanRules.Refused("Un argument contredit le plan exporté ; aucune cible de remplacement.");
        return options with { Computer = plan.Computer, NewName = plan.NewName, TargetOu = plan.TargetOu,
            Type = plan.Type, SiteCode = plan.SiteCode, ServiceCode = plan.ServiceCode };
    }

    private static PestoCliResult MapReceipt(Receipt receipt, AutomationExecutionAuthorization authority, string gpRoot, DateTimeOffset now)
    {
        if (receipt.Id != authority.ReceiptId || receipt.Kind != authority.Plan.Action || !AutomationPlanRules.Same(receipt.Computer, authority.Plan.Computer))
            throw new IOException("Le résultat n'est pas celui de l'intention engagée.");
        if (receipt.Status == "refused") return new(1, "CLI", "Refused", 96, receipt.Code, false, false, receipt.Id, now,
            Safe(receipt.Message), Metadata: authority.Plan.Metadata);
        using var proof = AutomationReceiptProof.Pin(gpRoot, receipt.Id, authority.Plan, now);
        var durable = proof.Receipt;
        if (durable.Code != receipt.Code || durable.Status != receipt.Status
            || durable.Kind != receipt.Kind || !AutomationPlanRules.Same(durable.Computer, receipt.Computer)
            || !AutomationPlanRules.Same(durable.TargetOU, receipt.TargetOU) || durable.RestartRequired != receipt.RestartRequired
            || receipt.Kind != "move" && !AutomationPlanRules.Same(durable.NewName, receipt.NewName))
            throw new IOException("Le résultat ne correspond pas au reçu durable exact.");
        var verified = receipt.Status == "succeeded" && receipt.Code is 30 or 33 && !receipt.RestartRequired;
        var pending = receipt.Status == "pendingRestart" && receipt.RestartRequired && receipt.Code == (receipt.Kind == "join" ? 10 : receipt.Kind == "rename" ? 20 : 77);
        return new(1, "CLI", verified ? "Verified" : pending ? "PendingRestart" : receipt.Code == 89 ? "Partial" : "Uncertain",
            verified ? 0 : pending ? 3010 : 97, receipt.Code, receipt.RestartRequired, true, receipt.Id, now,
            Safe(receipt.Message), Metadata: authority.Plan.Metadata);
    }

    /// <summary>Interventions > Vérifier l’état without the window: the engine rereads AD and Windows and records the
    /// final state only when every proof agrees. Unproved receipts keep their status and barrier; nothing is replayed.</summary>
    private static PestoCliResult Verify(IPestoBackend backend, string receiptId, DateTimeOffset now)
    {
        var answer = backend.InvokeAsync("receipts.reconcile", PestoJson.Element(new { id = receiptId })).GetAwaiter().GetResult();
        var node = JsonSerializer.SerializeToNode(answer, PestoJson.Options) as JsonObject
            ?? throw new PestoException("automation.observation", "La vérification n'a pas fourni d'objet contrôlé.");
        if (node["id"] is not JsonValue id || id.GetValueKind() != JsonValueKind.String || id.GetValue<string>() != receiptId)
            throw new PestoException("automation.observation", "Le reçu vérifié ne correspond pas à la demande.");
        var verified = node["verified"] is JsonValue flag && flag.GetValueKind() == JsonValueKind.True;
        var status = node["status"] is JsonValue s && s.GetValueKind() == JsonValueKind.String ? s.GetValue<string>() : "";
        var text = (verified ? node["message"] : node["reason"]) is JsonValue t && t.GetValueKind() == JsonValueKind.String ? t.GetValue<string>() : "";
        if (verified) return new(1, "CLI", "Verified", 0, null, false, false, receiptId, now, Safe(text));
        var pending = status == "pendingRestart";
        return new(1, "CLI", pending ? "PendingRestart" : "Uncertain", pending ? 3010 : 97, null, pending, false, receiptId, now,
            Safe(text.Length > 0 ? text : "Preuves insuffisantes : le reçu et sa barrière sont conservés."));
    }

    private static JsonObject SafeObservation(object? observed, string action)
    {
        var value = JsonSerializer.SerializeToNode(observed, PestoJson.Options) as JsonObject
            ?? throw new PestoException("automation.observation", "La lecture n'a pas fourni d'objet contrôlé.");
        var output = new JsonObject();
        foreach (var name in action == "inspect" ? new[] { "name", "dnsName", "site", "service", "ou", "os", "guid", "status", "domain", "manufacturer", "model", "serial", "ip", "pendingRestart" } : Array.Empty<string>())
        {
            if (!value.TryGetPropertyValue(name, out var node) || node is null) { output[name] = null; continue; }
            if (node is not JsonValue) throw new PestoException("automation.observation", "La lecture contient un champ non scalaire.");
            if (node.GetValueKind() == JsonValueKind.String && (node.GetValue<string>().Length > 2048 || node.GetValue<string>().Any(char.IsControl)))
                throw new PestoException("automation.observation", "La lecture contient un champ hors limites.");
            output[name] = node.DeepClone();
        }
        var checks = new JsonArray();
        if (value["checks"] is JsonArray items)
            foreach (var item in items.Take(100))
            {
                if (item is not JsonObject check) continue;
                var clean = new JsonObject();
                foreach (var field in new[] { "label", "state", "detail" })
                    clean[field] = check[field] is JsonValue v && v.GetValueKind() == JsonValueKind.String ? Safe(v.GetValue<string>()) : null;
                checks.Add(clean);
            }
        output["checks"] = checks; return output;
    }

    private static string Safe(string value) => new(value.Where(c => !char.IsControl(c)).Take(1024).ToArray());
}

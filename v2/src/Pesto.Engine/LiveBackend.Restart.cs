using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private readonly Dictionary<string, (RestartAuthorization Authorization, JsonObject Original)> restartPlans = [];

    private JsonObject ReceiptsPrepareRestart(JsonElement args)
    {
        Arguments.Only(args, "id"); var id = Arguments.Text(args, "id", true);
        var read = RequireConfig(); RequireUnchangedConfiguration(); RequireRestartSession();
        var authorizationStamp = configStamp!;
        var original = ReceiptsGet(args);
        ReceiptRestartAdmission.RequirePlan(read, Policy(read), original["kind"]!.GetValue<string>(), original["computer"]!.GetValue<string>(),
            original["newName"]!.GetValue<string>(), null, original["targetOU"]!.GetValue<string>(), read.Domain);
        if (mutation is not IMutationRestart restart) throw new PestoException("restart.unavailable", "Le redémarrage explicitement confirmé n’est pas disponible sur cet adaptateur.");
        var planId = "restart-plan-" + Guid.NewGuid().ToString("N");
        var prepared = restart.PrepareRestart(id, planId, authorizationStamp); var auth = prepared.Authorization;
        RequireUnchangedConfiguration(); RequireRestartSession();
        ReceiptRestartRules.RequireTarget(auth.Source, auth.Evidence, clock.GetUtcNow());
        if (auth.PlanId != planId || prepared.Receipt.Id != id || auth.Source.Receipt != prepared.Receipt || auth.ExpiresAt <= clock.GetUtcNow()
            || auth.ConfigurationSha256 != authorizationStamp || configStamp != authorizationStamp
            || !SameAcknowledgementReceipt(original, ReceiptNode(prepared.Receipt)))
            throw new PestoException("restart.proof", "La préparation native du redémarrage n’est pas liée à ce reçu.");
        RequireRestartPolicy(read, auth.Source);
        foreach (var key in restartPlans.Where(p => p.Value.Authorization.Source.Receipt.Id == id || p.Value.Authorization.ExpiresAt <= clock.GetUtcNow()).Select(p => p.Key).ToArray()) restartPlans.Remove(key);
        restartPlans.Add(planId, (auth, original.DeepClone().AsObject()));
        return Resp.Obj(("planId", planId), ("receiptId", id), ("action", "restart"), ("mode", "live"),
            ("computer", prepared.Receipt.Computer), ("newName", prepared.Receipt.NewName), ("domain", auth.Source.Domain),
            ("targetComputer", auth.Evidence.ActiveName), ("confirmationName", auth.Evidence.ActiveName), ("expiresAt", Iso(auth.ExpiresAt)),
            ("warnings", Resp.Arr(new[] { "Le poste affiché sera invité à redémarrer sans forçage. Enregistrez le travail en cours avant confirmation.",
                "La demande sera consignée avant l’action. Une acceptation ne prouve pas le redémarrage ; le reçu métier garde son résultat d’origine jusqu’à sa vérification explicite après boot.",
                "Après envoi ou réponse incertaine, Pesto n’envoie aucune seconde demande pour le même boot." }, s => (JsonNode?)Resp.Node(s))),
            ("steps", Resp.Arr(new[] { new Step("Relire l’identité Windows et le boot", auth.Evidence.ActiveName),
                new Step("Consigner la demande puis demander le redémarrage", "Sans Force ; aucune modification AD"),
                new Step("Vérifier le reçu après redémarrage", id) }, s => Resp.Obj(("label", s.Label), ("detail", s.Detail)))));
    }

    private JsonObject ReceiptsRestart(JsonElement args)
    {
        Arguments.Only(args, "planId", "confirmationName"); var planId = Arguments.Text(args, "planId", true);
        if (!restartPlans.TryGetValue(planId, out var held) || held.Authorization.ExpiresAt <= clock.GetUtcNow())
            throw new PestoException("restart.stale", "Le plan de redémarrage a expiré ou a déjà été envoyé.");
        var authorization = held.Authorization;
        if (!Arguments.Text(args, "confirmationName", true).Equals(authorization.Evidence.ActiveName, StringComparison.Ordinal))
            throw new PestoException("confirmation.invalid", "Le nom confirmé ne correspond pas au poste à redémarrer. Préparez de nouveau le redémarrage.");
        var read = RequireConfig(); RequireUnchangedConfiguration(); RequireRestartSession();
        if (configStamp != authorization.ConfigurationSha256)
            throw new PestoException("config.changed", "La configuration d’autorisation du redémarrage a changé : préparez et confirmez un nouveau plan.");
        RequireRestartPolicy(read, authorization.Source);
        if (mutation is not IMutationRestart restart) throw new PestoException("restart.unavailable", "Adaptateur de redémarrage indisponible.");
        var current = ReceiptsGet(JsonSerializer.SerializeToElement(new { id = authorization.Source.Receipt.Id }));
        if (!SameAcknowledgementReceipt(held.Original, current, includeMessage: true) || current["acknowledged"]?.GetValue<bool>() == true)
            throw new PestoException("restart.stale", "Le résultat du reçu affiché a changé depuis la préparation ; aucun redémarrage envoyé.");
        restartPlans.Remove(planId);
        var result = restart.Restart(authorization);
        if (result.Receipt != authorization.Source.Receipt || result.Status is not ("accepted" or "refused" or "uncertain")
            || !RemoteWindowsEvidenceProtocol.Same(result.Computer, authorization.Evidence.ActiveName))
            throw new PestoException("restart.uncertain", "Réponse native non liée à la demande ; vérifiez le poste, aucun nouvel envoi.");
        Log("Demande explicite de redémarrage " + result.Id + " : " + result.Computer + " · " + result.Status + ". Le reçu métier est conservé.", result.Status == "accepted" ? "info" : "warn");
        return Resp.Obj(("receipt", held.Original.DeepClone()),
            ("restart", Resp.Obj(("id", result.Id), ("status", result.Status), ("computer", result.Computer), ("utc", Iso(result.Utc)))),
            ("message", result.Message));
    }

    private void RequireRestartSession()
    {
        ReceiptRestartAdmission.RequireSession(Environment.GetEnvironmentVariable("PESTO_READONLY_SESSION") == "1", WritesAvailable, WriteBlockReason);
        ReceiptRestartAdmission.RequireLiveConfiguration(File.ReadAllText(ConfigPathOf()!));
    }

    private void RequireRestartPolicy(V1Config read, RestartReceiptSnapshot source)
    {
        var policy = Policy(read);
        ReceiptRestartAdmission.RequirePlan(read, policy, source.Receipt.Kind, source.Receipt.Computer, source.Receipt.NewName,
            source.InitialOu, source.Receipt.TargetOU, source.Domain);
        if (policy.ExcludedGroups.Count > 0)
        {
            if (!RemoteWindowsEvidenceProtocol.IsGuid(source.ComputerGuid))
                throw ReceiptRestartRules.Refused("POLICY.ExcludedGroupGuids : GUID AD du reçu inconnu, aucune appartenance supposée autorisée.");
            GroupExclusionGuard.Require(gateway as IGroupExclusionReader, source.Domain, source.Dc, source.ComputerGuid!,
                policy.ExcludedGroups, source.Receipt.NewName, source.ExpectedAdOu, clock);
        }
        // Group reads may wait on AD; a changed HKLM policy or profile must still stop the request afterwards.
        RequireUnchangedConfiguration(); RequireRestartSession();
        ReceiptRestartAdmission.RequirePlan(read, Policy(read), source.Receipt.Kind, source.Receipt.Computer, source.Receipt.NewName,
            source.InitialOu, source.Receipt.TargetOU, source.Domain);
    }

    private JsonObject ReceiptWithRestartInfo(Receipt receipt, bool acknowledged = false)
    {
        var node = AcknowledgedReceiptNode(receipt, acknowledged);
        node = WithAttributeReceiptInfo(receipt, node);
        try
        {
            if (gpRoot is null) return node;
            var path = Path.Combine(gpRoot, "V2", "receipts", receipt.Id + ".json");
            SharedCoordinationProtocol.RequireNoLinks(path);
            using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (input.Length is < 1 or > 131072) return node;
            var bytes = new byte[checked((int)input.Length)]; input.ReadExactly(bytes);
            var source = GpHistory.ParseAdapterSnapshot(path, bytes, clock.GetUtcNow());
            if (!source.Readable || !SameAcknowledgementReceipt(node, ReceiptNode(source.Receipt))) return node;
            var restart = new ReceiptRestartStore(gpRoot).ReadLatest(receipt.Id, RemoteWindowsEvidenceProtocol.Hash(bytes));
            if (restart is not null) node["restartRequest"] = Resp.Obj(("id", restart.Command.Id), ("status", restart.Status),
                ("computer", restart.Command.Computer), ("utc", Iso(restart.Utc)));
        }
        catch (Exception) { /* An uncertain display never authorizes a second native send: the durable coordinator checks again. */ }
        return node;
    }
}

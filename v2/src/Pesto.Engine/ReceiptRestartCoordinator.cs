namespace Pesto.Engine;

/// <summary>One consumed plan, one durable Requested before Send. Native callers serialize with the GP mutex.</summary>
public sealed class ReceiptRestartCoordinator(IReceiptRestartEnvironment environment, ReceiptRestartStore store, TimeProvider? time = null)
{
    private readonly TimeProvider clock = time ?? TimeProvider.System;
    private readonly Dictionary<string, RestartAuthorization> grants = [];

    public RestartPreparation Prepare(string receiptId, string planId, string configurationSha256)
    {
        if (!RemoteWindowsEvidenceProtocol.IsId(receiptId) || !RemoteWindowsEvidenceProtocol.IsId(planId)
            || !RemoteWindowsEvidenceProtocol.IsHash(configurationSha256))
            throw ReceiptRestartRules.Refused("Identité du plan ou du reçu invalide.");
        var source = environment.ReadSource(receiptId);
        environment.RequireAdmission(source, configurationSha256);
        var target = environment.ReadTarget(source);
        ReceiptRestartRules.RequireTarget(source, target, clock.GetUtcNow());
        environment.RequireAdmission(source, configurationSha256);
        ReceiptRestartRules.RequireTarget(source, target, clock.GetUtcNow());
        if (environment.ReadSource(receiptId) != source) throw ReceiptRestartRules.Refused("Le reçu a changé pendant la préparation du redémarrage.");
        store.RequireNoPriorRequest(target.MachineId, target.BootUtc);
        foreach (var key in grants.Where(p => p.Value.Source.Receipt.Id == receiptId || p.Value.ExpiresAt <= clock.GetUtcNow()).Select(p => p.Key).ToArray()) grants.Remove(key);
        if (grants.Count >= 2000) throw ReceiptRestartRules.Refused("Trop de préparations de redémarrage en mémoire.");
        var grant = new RestartAuthorization(Guid.NewGuid().ToString("N"), planId, source, target, clock.GetUtcNow().AddMinutes(2), configurationSha256);
        grants.Add(grant.Token, grant); return new(grant, source.Receipt);
    }

    public RestartResult Execute(RestartAuthorization authorization)
    {
        if (!grants.Remove(authorization.Token, out var held) || !ReferenceEquals(held, authorization) || held.ExpiresAt <= clock.GetUtcNow())
            throw ReceiptRestartRules.Refused("Plan de redémarrage absent, périmé ou déjà consommé.");
        var source = environment.ReadSource(held.Source.Receipt.Id);
        if (source != held.Source) throw ReceiptRestartRules.Refused("Le reçu a changé depuis la confirmation : aucun redémarrage envoyé.");
        environment.RequireAdmission(source, held.ConfigurationSha256);
        var target = environment.ReadTarget(source); ReceiptRestartRules.RequireTarget(source, target, clock.GetUtcNow());
        if (!RemoteWindowsEvidenceProtocol.Same(target.ActiveName, held.Evidence.ActiveName) || target.BootUtc != held.Evidence.BootUtc)
            throw ReceiptRestartRules.Refused("La cible ou le boot ont changé depuis la confirmation : aucun redémarrage envoyé.");
        if (held.ExpiresAt <= clock.GetUtcNow() || environment.ReadSource(source.Receipt.Id) != source)
            throw ReceiptRestartRules.Refused("Le plan ou le reçu ont changé pendant les dernières lectures : aucun redémarrage envoyé.");
        environment.RequireAdmission(source, held.ConfigurationSha256);
        ReceiptRestartRules.RequireTarget(source, target, clock.GetUtcNow());
        if (held.ExpiresAt <= clock.GetUtcNow() || environment.ReadSource(source.Receipt.Id) != source)
            throw ReceiptRestartRules.Refused("Le plan ou le reçu ont changé pendant les derniers contrôles de politique : aucun redémarrage envoyé.");
        var command = new RestartCommand("restart-" + Guid.NewGuid().ToString("N"), source.Receipt.Id, source.Sha256, held.PlanId,
            target.ActiveName, target.ConfiguredName, source.Domain, source.ComputerGuid, target.MachineId, target.BootUtc,
            source.LocalTarget, clock.GetUtcNow(), source.Receipt.Kind, ReceiptRestartRules.IsPendingLocalJoin(source, target),
            source.InitialWindowsDomain, source.InitialDomainRole, held.ConfigurationSha256);
        store.Requested(command); // durable BEFORE any process, task registration or restart request
        RestartNativeResult result;
        try { result = environment.Send(command); }
        catch (Exception) { result = new("uncertain", "La réponse native a été perdue : la demande peut avoir été envoyée. Aucun nouvel envoi pour ce boot."); }
        if (result.Status is not ("accepted" or "refused" or "uncertain"))
            result = new("uncertain", "Réponse native inconnue : aucun succès de redémarrage déduit, aucun nouvel envoi.");
        var utc = clock.GetUtcNow();
        try { store.Finished(command, result, utc); }
        catch (Exception) { result = new("uncertain", "La réponse n’a pas pu être conservée ; la demande initiale durable reste bloquante. Vérifiez le poste et le reçu après boot."); }
        return new(source.Receipt, command.Id, result.Status, command.Computer, utc, result.Message);
    }
}

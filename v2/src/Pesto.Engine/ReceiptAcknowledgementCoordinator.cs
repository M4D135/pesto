using System.Security.Cryptography;

namespace Pesto.Engine;

/// <summary>Testable acknowledgement state machine. The native caller holds the GP mutex and supplies
/// fresh worker/Entra/reservation facts for BOTH preparation and execution.</summary>
public sealed class ReceiptAcknowledgementCoordinator(string gpRoot,
    Func<ReceiptAcknowledgementSnapshot, ReceiptAcknowledgementContext> inspect,
    TimeProvider? clock = null, Action<string>? secureDirectory = null)
{
    private readonly TimeProvider clock = clock ?? TimeProvider.System;
    private readonly ReceiptAcknowledgementStore store = new(gpRoot, secureDirectory);
    private readonly Dictionary<string, ReceiptAcknowledgementAuthorization> grants = new(StringComparer.Ordinal);

    public ReceiptAcknowledgementPreparation Prepare(string receiptId, string planId)
    {
        ReceiptAcknowledgementSource.RequireId(planId);
        foreach (var old in grants.Values.Where(value => value.ReceiptId == receiptId).ToArray()) grants.Remove(old.Token);
        var snapshot = ReceiptAcknowledgementSource.Read(gpRoot, receiptId);
        RequireUnacknowledged(snapshot);
        var context = inspect(snapshot); RequireContext(snapshot, context);
        var primary = snapshot.Targets.First(target => target.Store == (snapshot.Targets.Any(t => t.Store == "adapter") ? "adapter"
            : snapshot.Targets.Any(t => t.Store == "intervention") ? "intervention" : snapshot.Targets[0].Store));
        var a = new ReceiptAcknowledgementAuthorization(Convert.ToHexString(RandomNumberGenerator.GetBytes(32)), planId,
            snapshot.Receipt.Id, snapshot.TargetsSha256, snapshot.TaskProofSha256, context.EntraEvidenceSha256,
            context.ConfigurationSha256, snapshot.Receipt.Computer, snapshot.Receipt.NewName, snapshot.Domain,
            primary.Phase, primary.Code, snapshot.Receipt.NewName.Length > 0 ? snapshot.Receipt.NewName : snapshot.Receipt.Computer,
            clock.GetUtcNow().AddMinutes(2));
        grants[a.Token] = a;
        return new(snapshot, a);
    }

    public ReceiptAcknowledgementResult Acknowledge(ReceiptAcknowledgementAuthorization authorization, string reason)
    {
        reason = ReceiptAcknowledgementStore.ValidateReason(reason);
        if (!grants.TryGetValue(authorization.Token, out var saved) || !ReferenceEquals(saved, authorization)
            || authorization.ExpiresAt <= clock.GetUtcNow()) throw ReceiptAcknowledgementSource.Refused("Plan d’acquittement absent, expiré ou déjà consommé.");
        grants.Remove(authorization.Token); // no replay after a confirmed submission, including a failed disk write
        var snapshot = ReceiptAcknowledgementSource.Read(gpRoot, authorization.ReceiptId);
        RequireUnacknowledged(snapshot);
        var context = inspect(snapshot); RequireContext(snapshot, context);
        if (snapshot.TargetsSha256 != authorization.TargetsSha256 || snapshot.TaskProofSha256 != authorization.TaskProofSha256
            || context.ConfigurationSha256 != authorization.ConfigurationSha256 || context.EntraEvidenceSha256 != authorization.EntraEvidenceSha256)
            throw ReceiptAcknowledgementSource.Refused("Le reçu, la configuration ou ses preuves ont changé : préparez et confirmez un nouveau plan.");
        var evidence = store.Append(snapshot, context, reason, clock.GetUtcNow());
        if (!ReceiptAcknowledgementStore.ValidateApplied(gpRoot, evidence))
            throw ReceiptAcknowledgementSource.Refused("L’événement est conservé mais sa portée ne peut plus être confirmée : aucune barrière supposée levée.");
        return new(snapshot.Receipt, evidence);
    }

    private void RequireUnacknowledged(ReceiptAcknowledgementSnapshot snapshot)
    {
        if (snapshot.Targets.Any(target => !ReceiptAcknowledgementSource.IsEligible(target.Phase)))
            throw ReceiptAcknowledgementSource.Refused("Ce résultat ne nécessite pas d’acquittement.");
        if (snapshot.AlreadyAcknowledged || store.ReadApplied(snapshot.Receipt.Id) is not null)
            throw ReceiptAcknowledgementSource.Refused("Ce résultat possède déjà un acquittement exact.");
    }

    private void RequireContext(ReceiptAcknowledgementSnapshot snapshot, ReceiptAcknowledgementContext context)
    {
        if (context.Refusal is not null) throw ReceiptAcknowledgementSource.Refused(context.Refusal);
        if (!context.ReservationsResolved) throw ReceiptAcknowledgementSource.Refused("Une réservation AD non résolue doit être inspectée ; l’acquittement ne la résout pas.");
        if (!context.EntraCanAcknowledge) throw ReceiptAcknowledgementSource.Refused("Une tâche ou un processus Entra peut encore agir : inspection explicite obligatoire.");
        if (!ReceiptAcknowledgementSource.Same(context.Domain, snapshot.Domain) || !ReceiptAcknowledgementSource.IsHash(context.ConfigurationSha256)
            || !ReceiptAcknowledgementSource.IsHash(context.EntraEvidenceSha256) || string.IsNullOrWhiteSpace(context.Author))
            throw ReceiptAcknowledgementSource.Refused("La portée, l’auteur ou la politique de l’acquittement n’est pas confirmée.");
        var proof = context.WorkerProof;
        if (proof is null || !proof.Clear || proof.Method != "local-process-snapshot" || proof.ObservedUtc > clock.GetUtcNow()
            || clock.GetUtcNow() - proof.ObservedUtc > TimeSpan.FromSeconds(30) || !Guid.TryParse(proof.MachineId, out var machine) || machine == Guid.Empty)
            throw ReceiptAcknowledgementSource.Refused("L’absence de worker actif n’est pas prouvée : aucun acquittement.");
        if (snapshot.Targets.Any(target => target.LocalMachineId is not null && !ReceiptAcknowledgementSource.Same(target.LocalMachineId, proof.MachineId)))
            throw ReceiptAcknowledgementSource.Refused("Un reçu historique appartient à une autre machine opératrice.");
    }
}

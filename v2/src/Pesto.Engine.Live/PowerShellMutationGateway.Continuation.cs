using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway
{
    private readonly MoveContinuationGrants continuationGrants = new();
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string Hash(string text) => Hash(Encoding.UTF8.GetBytes(text));
    private static PestoException ContinuationRefused(string reason) => new("receipt.prepareMove_evidence", reason);

    private string? ReadV1Barriers()
    {
        var gp = ReceiptGpRoot();
        return ReadBarrier(Path.Combine(gp, "Join", "receipt.json"), "Reçu de jonction V1")
            ?? ReadBarrier(Path.Combine(gp, "Operations", "direct.json"), "Opération directe V1");
    }

    public MoveContinuationPreparation PrepareMoveContinuation(string parentReceiptId, string planId)
    {
        MutationSessionGuard.RequireWritableSession();
        if (!IsOpaqueId(parentReceiptId) || !IsOpaqueId(planId)) throw ContinuationRefused("Identité de reçu ou de plan invalide.");
        continuationGrants.Invalidate(parentReceiptId);
        if (unavailableReason is not null) throw ContinuationRefused(unavailableReason);
        using var mutex = new Mutex(false, PostMutationMutexName);
        var owned = false;
        try
        {
            try { owned = mutex.WaitOne(0); } catch (AbandonedMutexException) { owned = true; }
            if (!owned) throw ContinuationRefused("Une autre mutation utilise le registre ; aucun déplacement préparé.");
            if (ReadV1Barriers() is { } barrier) throw ContinuationRefused(barrier);
            var evidence = ReadReconciliation(parentReceiptId);
            var path = ReceiptPath(parentReceiptId);
            var bytes = ReadReceiptBytes(path);
            if (Hash(bytes) != evidence.ReceiptSha256) throw ContinuationRefused("Le reçu a changé pendant sa lecture.");
            using var document = JsonDocument.Parse(bytes);
            var saved = document.RootElement;
            if (EntraEvidenceAllowsReconciliation(saved) is { } entraRefusal) throw ContinuationRefused(entraRefusal);
            RequireNoActiveContinuation(saved);
            var targetGuid = ReadContinuationTarget(saved, evidence);
            if (MoveContinuationRules.EvidenceRefusal(evidence, SavedText(saved, "TargetOuGuid"), targetGuid) is { } reason)
                throw ContinuationRefused(reason);
            if (evidence.LocalTarget && !string.Equals(evidence.Receipt.NewName, Environment.MachineName, StringComparison.OrdinalIgnoreCase))
                throw ContinuationRefused("Le reçu ne désigne pas le poste local actuellement renommé.");
            var a = new MoveContinuationAuthorization(Convert.ToHexString(RandomNumberGenerator.GetBytes(32)), parentReceiptId,
                evidence.ReceiptSha256, planId, evidence.Receipt.NewName, evidence.ExpectedGuid!, evidence.InitialOu!,
                evidence.Receipt.TargetOU, targetGuid!, DateTimeOffset.UtcNow.AddMinutes(2));
            var request = ContinuationRequest(a, evidence.Domain, SavedText(saved, "Dc"), "preparation-" + Guid.NewGuid().ToString("N"));
            if (ReadV2Barrier(request, a) is { } other) throw ContinuationRefused(other);
            var partial = JsonNode.Parse(bytes)!.AsObject();
            partial["Phase"] = "Partial";
            partial["RestartRequired"] = false;
            partial["Utc"] = DateTimeOffset.UtcNow.ToString("o");
            partial["Message"] = "Renommage confirmé après redémarrage ; déplacement restant vers la destination originale, soumis à un nouvel aperçu et à une confirmation distincte.";
            partial["Reconciliation"] = ReconciliationJson(evidence);
            foreach (var key in new[] { "ContinuationChildReceiptId", "ContinuationChildPlanId", "ContinuationAttemptId", "ContinuationParentReceiptSha256" }) partial.Remove(key);
            var json = partial.ToJsonString();
            MutationSessionGuard.RequireWritableSession();
            WriteAtomic(path, json);
            AuditDurableReceipt(json);
            a = a with { ParentReceiptSha256 = Hash(json) };
            var observed = evidence with
            {
                ReceiptSha256 = a.ParentReceiptSha256,
                Receipt = evidence.Receipt with { Status = "uncertain", RestartRequired = false,
                    Message = partial["Message"]!.GetValue<string>() }
            };
            if (!evidence.LocalTarget)
            {
                // The Partial update changed the receipt hash. Obtain a new remote proof bound to those exact
                // bytes instead of relabelling the previous SYSTEM result with a hash it never observed.
                observed = ReadReconciliation(parentReceiptId);
                if (observed.ReceiptSha256 != a.ParentReceiptSha256
                    || MoveContinuationRules.EvidenceRefusal(observed, SavedText(saved, "TargetOuGuid"), ReadContinuationTarget(saved, observed)) is { })
                    throw ContinuationRefused("Le parent partiel a été conservé mais sa nouvelle preuve distante n’est pas confirmée ; aucun déplacement autorisé.");
                a = a with { ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(2) };
            }
            continuationGrants.Add(a);
            return new(observed, a, targetGuid);
        }
        finally { if (owned) mutex.ReleaseMutex(); }
    }

    private static MutationRequest ContinuationRequest(MoveContinuationAuthorization a, string domain, string? dc, string receiptId) =>
        new("move", a.Computer, a.ComputerGuid, null, a.TargetOu, domain, dc, a.PlanId, receiptId, a.SourceOu, a.TargetOuGuid, a);

    private string? ReadContinuationTarget(JsonElement saved, ReceiptReconciliationObservation evidence)
    {
        var target = new PowerShellDirectoryGateway(fallbackCredentials as IWindowsCredentialSource, v1InstallationPath)
            .FindOrganizationalUnit(evidence.Domain, SavedText(saved, "Dc"), evidence.Receipt.TargetOU);
        return target is not null && string.Equals(target.DistinguishedName, evidence.Receipt.TargetOU, StringComparison.OrdinalIgnoreCase) ? target.Guid : null;
    }

    // All calls occur under the same GP mutex as execution. A failed child can be prepared again only after fresh proof.
    private void RequireNoActiveContinuation(JsonElement parent)
    {
        if (SavedText(parent, "ResolutionChildReceiptId") is not null)
            throw ContinuationRefused("Ce reçu possède déjà un lien de résolution ; aucun nouveau déplacement autorisé.");
        if (SavedText(parent, "ContinuationChildReceiptId") is not { } childId) return;
        using var child = JsonDocument.Parse(ReadReceiptBytes(ReceiptPath(childId)));
        if (!MoveContinuationRules.IsLinkedChild(parent, child.RootElement) || SavedText(child.RootElement, "Phase") != "Failed")
            throw ContinuationRefused("Une tentative enfant existe et son absence d’effet n’est pas prouvée : aucun nouvel envoi.");
    }

    private void ValidateMoveContinuation(MutationRequest request, MoveContinuationAuthorization a)
    {
        if (!continuationGrants.Contains(a, DateTimeOffset.UtcNow) || !MoveContinuationRules.RequestMatches(a, request, DateTimeOffset.UtcNow))
            throw ContinuationRefused("L’autorisation de déplacement est absente, consommée, périmée ou différente du plan confirmé.");
        var bytes = ReadReceiptBytes(ReceiptPath(a.ParentReceiptId));
        if (Hash(bytes) != a.ParentReceiptSha256) throw ContinuationRefused("Le reçu parent a changé depuis l’aperçu : aucune commande lancée.");
        using var document = JsonDocument.Parse(bytes);
        RequireNoActiveContinuation(document.RootElement);
        var e = ReadReconciliation(a.ParentReceiptId);
        var observedTarget = ReadContinuationTarget(document.RootElement, e);
        if (e.ReceiptSha256 != a.ParentReceiptSha256 || !string.Equals(request.Domain, e.Domain, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.Computer, e.Receipt.NewName, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.ComputerGuid, e.ExpectedGuid, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.SourceOu, e.InitialOu, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.TargetOu, e.Receipt.TargetOU, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(a.TargetOuGuid, observedTarget, StringComparison.OrdinalIgnoreCase))
            throw ContinuationRefused("La preuve actuelle ne correspond plus à l’autorisation liée au reçu parent.");
        if (MoveContinuationRules.EvidenceRefusal(e, SavedText(document.RootElement, "TargetOuGuid"), observedTarget) is { } reason)
            throw ContinuationRefused(reason);
    }

    private string? ContinuationBaselineRefusal(MutationRequest request, NativeReceiptSnapshot baseline)
    {
        if (request.Continuation is not { } a) return null;
        using var parent = JsonDocument.Parse(ReadReceiptBytes(ReceiptPath(a.ParentReceiptId)));
        var saved = parent.RootElement;
        var local = SavedFlag(saved, "LocalTarget");
        if (Hash(ReadReceiptBytes(ReceiptPath(a.ParentReceiptId))) != a.ParentReceiptSha256 || local is null
            || local.Value != string.Equals(request.Computer, Environment.MachineName, StringComparison.OrdinalIgnoreCase)
            || !local.Value && (!ReceiptWindowsEvidence.RemoteBaselineMatches(saved) || baseline.RemoteProof is not { } remote
                || remote.Request.Purpose != "continuation" || remote.Request.ReceiptId != request.ReceiptId
                || !RemoteWindowsEvidenceProtocol.Same(remote.Request.ReceiptSha256, a.ParentReceiptSha256))
            || baseline.AdProtected != SavedFlag(saved, "InitialProtected") || baseline.BootUtc is null
            || SavedDate(saved, "InitialBootUtc") is not { } initialBoot || baseline.BootUtc <= initialBoot
            || !string.Equals(baseline.MachineId, SavedText(saved, "MachineId"), StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.ActiveName, a.Computer, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.ConfiguredName, a.Computer, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(baseline.Domain, request.Domain, StringComparison.OrdinalIgnoreCase)
            || baseline.PartOfDomain != true || baseline.SecureChannel != true)
            return "Les preuves Windows ou la protection ont changé depuis la préparation : aucune commande lancée.";
        return null;
    }

    private void LinkContinuationBeforeSend(MutationRequest request, string childPath)
    {
        if (request.Continuation is not { } a) return;
        var parentPath = ReceiptPath(a.ParentReceiptId);
        var bytes = ReadReceiptBytes(parentPath);
        if (Hash(bytes) != a.ParentReceiptSha256) throw new IOException("Le reçu parent a changé avant l’envoi.");
        var parent = JsonNode.Parse(bytes)!.AsObject();
        parent["ContinuationChildReceiptId"] = request.ReceiptId;
        parent["ContinuationChildPlanId"] = request.PlanId;
        parent["ContinuationAttemptId"] = Hash(a.Token);
        parent["ContinuationParentReceiptSha256"] = a.ParentReceiptSha256;
        var linked = parent.ToJsonString();
        WriteAtomic(parentPath, linked);
        var child = JsonNode.Parse(ReadReceiptBytes(childPath))!.AsObject();
        child["ContinuationParentStateSha256"] = Hash(linked);
        WriteAtomic(childPath, child.ToJsonString());
        // Both durable files exist before Move-ADObject. A crash now leaves Running, never a reusable grant.
    }

    private bool HasResolvedContinuation(JsonElement parent)
    {
        try
        {
            if (SavedText(parent, "ResolutionChildReceiptId") is not { } childId) return false;
            var bytes = ReadReceiptBytes(ReceiptPath(childId));
            using var child = JsonDocument.Parse(bytes);
            return MoveContinuationRules.IsResolved(parent, child.RootElement, Hash(bytes));
        }
        catch (Exception) { return false; }
    }

    private void WriteCompletedReceipt(string childPath, JsonObject child)
    {
        if (child["ParentReceiptId"]?.GetValue<string>() is not { } parentId || child["Phase"]?.GetValue<string>() != "Verified")
        {
            var completed = child.ToJsonString();
            WriteAtomic(childPath, completed);
            AuditDurableReceipt(completed);
            return;
        }
        var parentPath = ReceiptPath(parentId);
        var parent = JsonNode.Parse(ReadReceiptBytes(parentPath))!.AsObject();
        var baseParent = (JsonObject)parent.DeepClone();
        foreach (var key in new[] { "ResolutionChildReceiptId", "ResolutionChildReceiptSha256", "ResolutionUtc" }) baseParent.Remove(key);
        using var parentDoc = JsonDocument.Parse(parent.ToJsonString());
        using var childDoc = JsonDocument.Parse(child.ToJsonString());
        if ((parent["ResolutionChildReceiptId"]?.GetValue<string>() is { } existingResolution
                && existingResolution != child["ReceiptId"]?.GetValue<string>())
            || !MoveContinuationRules.IsLinkedChild(parentDoc.RootElement, childDoc.RootElement)
            || Hash(baseParent.ToJsonString()) != child["ContinuationParentStateSha256"]?.GetValue<string>()
            || child["RestartRequired"]?.GetValue<bool>() != false)
            throw new IOException("Le lien parent-enfant a changé : la résolution ne peut pas être enregistrée.");
        var json = child.ToJsonString();
        parent["ResolutionChildReceiptId"] = child["ReceiptId"]!.GetValue<string>();
        parent["ResolutionChildReceiptSha256"] = Hash(json);
        parent["ResolutionUtc"] = DateTimeOffset.UtcNow.ToString("o");
        // The parent remains Partial/code89. Its link is effective only if the exact Verified child bytes exist.
        // If either write fails, Running/Uncertain or the hash mismatch keeps the barrier closed.
        WriteAtomic(parentPath, parent.ToJsonString());
        WriteAtomic(childPath, json);
        AuditDurableReceipt(parent.ToJsonString());
        AuditDurableReceipt(json);
    }

    private static JsonNode? ReconciliationJson(ReceiptReconciliationObservation e) => JsonSerializer.SerializeToNode(new
    {
        Utc = DateTimeOffset.UtcNow.ToString("o"), PreviousPhase = e.Receipt.Status,
        e.ReceiptSha256, e.ExpectedGuid, e.AdGuid, e.AdName, e.AdOu, e.AdProtected, e.CurrentBootUtc,
        e.WindowsActiveName, e.WindowsConfiguredName, e.WindowsDomain, e.WindowsPartOfDomain, e.SecureChannel, e.MachineIdentityMatches,
        e.RemoteWindowsProof
    });
}

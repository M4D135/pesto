using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;
using Pesto.Engine.Live;

namespace Pesto.Engine.Tests;

internal sealed class MoveContinuationNativeTests
{
    private const string GuidValue = "11111111-1111-1111-1111-111111111111";
    private const string TargetGuid = "22222222-2222-2222-2222-222222222222";
    private const string Source = "OU=Initial,DC=example,DC=local";
    private const string Target = "OU=Final,DC=example,DC=local";
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;
    private static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    private static ReceiptReconciliationObservation Evidence() => new(
        new Receipt("parent", Now, "renameMove", "LAB-OLD", "LAB-NEW", Target, "fixture", "pendingRestart", 89, "Déplacement différé", true),
        new string('A', 64), GuidValue, "example.local", Now.AddDays(-1), Now.AddHours(-1), GuidValue, "LAB-NEW", Source, Source,
        true, true, "LAB-NEW", "LAB-NEW", "example.local", true, true, true, true, null);
    private static MoveContinuationAuthorization Authorization() => new("opaque-native-token", "parent", new string('A', 64),
        "plan", "LAB-NEW", GuidValue, Source, Target, TargetGuid, DateTimeOffset.UtcNow.AddMinutes(2));
    private static MutationRequest Request(MoveContinuationAuthorization a) => new("move", a.Computer, a.ComputerGuid, null,
        a.TargetOu, "example.local", "dc.example.local", a.PlanId, "child", a.SourceOu, a.TargetOuGuid, a);

    [Test]
    public void OnlyCompleteLocalCode89RenameEvidenceAllowsTheRemainingMove()
    {
        var e = Evidence();
        Check.Null(MoveContinuationRules.EvidenceRefusal(e, TargetGuid, TargetGuid), "Toutes les preuves permettent un aperçu du seul déplacement");
        foreach (var changed in new[]
        {
            e with { Receipt = e.Receipt with { Kind = "rename", Code = 20 } },
            e with { Receipt = e.Receipt with { Code = 97 } },
            e with { Receipt = e.Receipt with { Status = "succeeded" } },
            e with { Receipt = e.Receipt with { ResolutionChildReceiptId = "already-done" } },
            e with { LocalTarget = false }, e with { MachineIdentityMatches = false }, e with { InitialBootUtc = null },
            e with { CurrentBootUtc = e.InitialBootUtc }, e with { WindowsPartOfDomain = false }, e with { SecureChannel = null },
            e with { WindowsDomain = "other.local" }, e with { ExpectedGuid = null }, e with { AdGuid = TargetGuid },
            e with { AdName = "OTHER" }, e with { WindowsActiveName = "LAB-OLD" }, e with { WindowsConfiguredName = "OTHER" },
            e with { AdOu = Target }, e with { InitialOu = null }, e with { InitialProtected = null }, e with { AdProtected = false },
            e with { Error = "lecture impossible" }
        }) Check.NotNull(MoveContinuationRules.EvidenceRefusal(changed, TargetGuid, TargetGuid), "Toute preuve manquante ou discordante bloque sans reprise");
        Check.NotNull(MoveContinuationRules.EvidenceRefusal(e, TargetGuid, GuidValue), "Une OU recréée sous le même DN n’est pas la destination autorisée");
    }

    [Test]
    public void ContinuationCannotRenameChangeDestinationOrReuseAnotherPlan()
    {
        var a = Authorization();
        var r = Request(a);
        Check.True(MoveContinuationRules.RequestMatches(a, r, Now), "L’enfant move correspond exactement à l’autorisation");
        foreach (var changed in new[]
        {
            r with { Kind = "renameMove", NewName = "OTHER" }, r with { NewName = "LAB-NEW" }, r with { PlanId = "different" },
            r with { Computer = "OTHER" }, r with { ComputerGuid = TargetGuid }, r with { SourceOu = Target },
            r with { TargetOu = Source }, r with { TargetOuGuid = GuidValue }, r with { ReceiptId = "parent" }, r with { Continuation = null }
        }) Check.False(MoveContinuationRules.RequestMatches(a, changed, Now), "Aucun élargissement du plan move-only n’est accepté");
        Check.False(MoveContinuationRules.RequestMatches(a, r, a.ExpiresAt), "L’expiration bloque même à l’instant limite");
    }

    [Test]
    public void PreparingAgainInvalidatesEarlierGrantAndConsumptionIsSingleUse()
    {
        var grants = new MoveContinuationGrants();
        var first = Authorization();
        var second = first with { Token = "second-token", PlanId = "second-plan" };
        grants.Add(first);
        grants.Add(second);
        Check.False(grants.Consume(first, Now), "Le premier aperçu ne peut plus envoyer après une nouvelle préparation");
        Check.False(grants.Consume(second with { TargetOu = Source }, Now), "Une autorisation falsifiée ne consomme pas le vrai jeton");
        Check.True(grants.Consume(second, Now), "Une seule consommation réussit");
        Check.False(grants.Consume(second, Now), "Le double clic ne rejoue jamais l’enfant");
        grants.Add(first);
        Check.False(grants.Consume(first, first.ExpiresAt), "Un jeton expiré ne donne aucune autorité");
        grants.Invalidate(first.ParentReceiptId);
        Check.False(grants.Contains(first, Now), "Même une préparation suivante avortée peut invalider l’ancien jeton");
    }

    private static (JsonObject Parent, JsonObject Child, MutationRequest Request) DurablePair()
    {
        var a = Authorization();
        var request = Request(a);
        var parent = new JsonObject
        {
            ["Schema"] = 1, ["Version"] = "2.0", ["Phase"] = "Partial", ["Utc"] = Now.ToString("o"),
            ["ReceiptId"] = "parent", ["PlanId"] = "initial-plan", ["Kind"] = "renameMove", ["Code"] = 89,
            ["Computer"] = "LAB-OLD", ["NewName"] = "LAB-NEW", ["ComputerGuid"] = GuidValue,
            ["TargetOu"] = Target, ["TargetOuGuid"] = TargetGuid, ["InitialOu"] = Source, ["InitialProtected"] = true,
            ["Domain"] = "example.local", ["RestartRequired"] = false, ["LocalTarget"] = true, ["MachineId"] = "same-windows-machine",
            ["InitialBootUtc"] = Now.AddDays(-1).ToString("o"),
            ["ContinuationChildReceiptId"] = "child", ["ContinuationChildPlanId"] = a.PlanId,
            ["ContinuationAttemptId"] = Hash(a.Token), ["ContinuationParentReceiptSha256"] = a.ParentReceiptSha256,
        };
        var child = new JsonObject
        {
            ["Schema"] = 1, ["Version"] = "2.0", ["Phase"] = "Uncertain", ["Utc"] = Now.ToString("o"),
            ["ReceiptId"] = request.ReceiptId, ["PlanId"] = request.PlanId, ["Kind"] = "move", ["Code"] = 97,
            ["Computer"] = request.Computer, ["NewName"] = null, ["ComputerGuid"] = GuidValue,
            ["TargetOu"] = Target, ["TargetOuGuid"] = TargetGuid, ["InitialOu"] = Source, ["InitialProtected"] = true,
            ["Domain"] = "example.local", ["RestartRequired"] = false, ["LocalTarget"] = true, ["MachineId"] = "same-windows-machine",
            ["InitialBootUtc"] = Now.AddHours(-1).ToString("o"),
            ["ParentReceiptId"] = "parent", ["ParentReceiptSha256"] = a.ParentReceiptSha256,
            ["ContinuationAttemptId"] = Hash(a.Token), ["ContinuationParentStateSha256"] = Hash(parent.ToJsonString()),
        };
        return (parent, child, request);
    }
    private static bool Resolved(JsonObject p, JsonObject c)
    {
        using var parent = JsonDocument.Parse(p.ToJsonString());
        using var child = JsonDocument.Parse(c.ToJsonString());
        return MoveContinuationRules.IsResolved(parent.RootElement, child.RootElement, Hash(c.ToJsonString()));
    }

    [Test]
    public void ParentResolutionBeforeDurableChildNeverReleasesTheBarrier()
    {
        var (parent, child, _) = DurablePair();
        parent["ResolutionChildReceiptId"] = "child";
        parent["ResolutionUtc"] = Now.ToString("o");
        parent["ResolutionChildReceiptSha256"] = Hash(child.ToJsonString());
        Check.False(Resolved(parent, child), "Uncertain reste bloquant même si le parent prétend être résolu");
        child["Phase"] = "Verified";
        Check.False(Resolved(parent, child), "Un hash ancien ne libère pas la barrière");
        parent["ResolutionChildReceiptSha256"] = Hash(child.ToJsonString());
        Check.True(Resolved(parent, child), "Seul le même enfant Verified avec empreinte exacte résout la partie restante");
        foreach (var key in new[] { "ComputerGuid", "TargetOu", "TargetOuGuid", "InitialOu", "ParentReceiptId", "ParentReceiptSha256", "ContinuationAttemptId", "PlanId", "Domain", "MachineId", "InitialBootUtc" })
        {
            var changed = (JsonObject)child.DeepClone(); changed[key] = "different";
            var changedParent = (JsonObject)parent.DeepClone(); changedParent["ResolutionChildReceiptSha256"] = Hash(changed.ToJsonString());
            Check.False(Resolved(changedParent, changed), "Même avec SHA recalculé, un enfant d’une autre identité ne résout pas le parent");
        }
        child["InitialProtected"] = false;
        parent["ResolutionChildReceiptSha256"] = Hash(child.ToJsonString());
        Check.False(Resolved(parent, child), "La protection initiale du parent doit être préservée");
    }

    [Test]
    public void DurableChildSuccessLinksParentWithoutRewritingItsPartialHistory()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-continuation-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "V2", "receipts"); Directory.CreateDirectory(folder);
        try
        {
            var (parent, child, request) = DurablePair();
            File.WriteAllText(Path.Combine(folder, "parent.json"), parent.ToJsonString());
            File.WriteAllText(Path.Combine(folder, "child.json"), child.ToJsonString());
            new PowerShellMutationGateway(receiptGpRoot: root).PersistFinalReceipt(request, new(MutationStatus.Succeeded, 30, "Déplacement confirmé", false, GuidValue));
            var savedParent = JsonNode.Parse(File.ReadAllText(Path.Combine(folder, "parent.json")))!.AsObject();
            var savedChild = JsonNode.Parse(File.ReadAllText(Path.Combine(folder, "child.json")))!.AsObject();
            Check.Equal("Partial", savedParent["Phase"]!.GetValue<string>(), "Le parent conserve sa phase partielle");
            Check.Equal(89, savedParent["Code"]!.GetValue<int>(), "Le code89 historique n’est pas réécrit en succèsrenameMove");
            Check.Equal("Verified", savedChild["Phase"]!.GetValue<string>(), "La réussite concerne exclusivement le déplacement enfant");
            Check.True(Resolved(savedParent, savedChild), "Le lien durable exact permet de reconnaître la résolution au redémarrage");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void ChangedParentCannotBeResolvedByAnOldChildFinalizer()
    {
        var root = Path.Combine(Path.GetTempPath(), "pesto-continuation-conflict-" + Guid.NewGuid().ToString("N"));
        var folder = Path.Combine(root, "V2", "receipts"); Directory.CreateDirectory(folder);
        try
        {
            var (parent, child, request) = DurablePair();
            parent["Message"] = "État concurrent modifié";
            File.WriteAllText(Path.Combine(folder, "parent.json"), parent.ToJsonString());
            File.WriteAllText(Path.Combine(folder, "child.json"), child.ToJsonString());
            var refused = false;
            try { new PowerShellMutationGateway(receiptGpRoot: root).PersistFinalReceipt(request, new(MutationStatus.Succeeded, 30, "Déplacé", false, GuidValue)); }
            catch (IOException) { refused = true; }
            Check.True(refused, "La finalisation refuse un parent changé après le lien préalable");
            Check.Equal(child.ToJsonString(), File.ReadAllText(Path.Combine(folder, "child.json")), "Le reçu enfant reste incertain et bloque le rejeu");
        }
        finally { Directory.Delete(root, true); }
    }

    [Test]
    public void GenericReconciliationCannotConvertCode89ParentIntoSuccess()
    {
        var e = Evidence();
        Check.Pesto(() => { new PowerShellMutationGateway().PersistReconciliation(e); return null; }, "receipt.partial",
            "La vérification générique ne peut contourner le chemin enfant ciblé");
    }
}

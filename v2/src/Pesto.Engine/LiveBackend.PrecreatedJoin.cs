using System.Text.Json;
using System.Text.Json.Nodes;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private string? PrecreatedJoinCapabilityBlockReason()
    {
        if (WriteBlockReason is { } blocked) return blocked;
        var read = ConfigOrNull();
        if (read is null || !Policy(read).AllowPrecreatedJoin) return "POLICY.AllowPrecreatedJoin est désactivée : choisissez le parcours d’un nom libre.";
        if (Policy(read).BlockReason("join") is { } policy) return policy;
        return mutation is IMutationPrecreatedJoin { SupportsPrecreatedJoin: true } ? null
            : "L’adaptateur n’implémente pas la jonction sur un compte précréé confirmé par GUID.";
    }

    private JsonObject JoinPrecreatedPreview(JsonElement args)
    {
        Arguments.Only(args, "name", "targetOU");
        RequireLocalJoinEligible();
        if (PrecreatedJoinCapabilityBlockReason() is { } blocked) throw new PestoException("join.precreated_unavailable", blocked);
        var name = Arguments.Text(args, "name", true, 15).ToUpperInvariant();
        ValidateComputerName(name);
        var read = RequireConfig(); RequireUnchangedConfiguration(); var policy = Policy(read);
        var convention = GetConvention(read);
        var parts = convention.TryParse(name) ?? throw new PestoException("join.precreated_name", "Le nom saisi ne respecte pas la convention configurée.");
        var adapter = RequireGateway();
        var dc = DcOrNull();
        if (!JoinClockGuard.IsServer(dc)) throw new PestoException("join.precreated_identity", "Le contrôleur exact doit être observé avant la préparation.");
        var observed = adapter.FindComputer(read.Domain, dc, name)
            ?? throw new PestoException("join.precreated_missing", "Aucun compte précréé exact n’existe sous ce nom. Aucun compte n’a été créé.");
        if (!string.Equals(observed.Name, name, StringComparison.OrdinalIgnoreCase) || observed.Ou is null
            || !WithinScope(observed.Ou, read.RootOu) || !string.Equals(observed.Domain, read.Domain, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("join.precreated_identity", "Le compte exact, son domaine ou son OU ne correspond pas au périmètre configuré.");
        var target = Optional(args, "targetOU");
        if (target is not null && !string.Equals(target, observed.Ou, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("join.precreated_ou", "Le compte doit déjà se trouver dans l’OU choisie ; aucune jonction ne déplace un compte existant.");
        if (!read.Production)
        {
            if (!string.Equals(observed.Ou, read.PreprodOu, StringComparison.OrdinalIgnoreCase))
                throw new PestoException("join.precreated_ou", "La configuration impose l’OU PREPROD ; le compte précréé doit déjà s’y trouver.");
        }
        else if (!ResolveSites(read, adapter).Any(site => string.Equals(site.Code, parts.Site, StringComparison.OrdinalIgnoreCase)
            && string.Equals(site.Ou, observed.Ou, StringComparison.OrdinalIgnoreCase)))
            throw new PestoException("join.precreated_ou", "Le nom et l’OU du compte doivent désigner le même site configuré et observé.");
        RequireJoinDestination(read, name, observed.Ou!);
        var account = new PrecreatedJoinAccount(observed.Guid ?? "", name, read.Domain, dc!, observed.Ou,
            ResolveTargetGuid(read, adapter, observed.Ou), configStamp!);
        PrecreatedJoinRules.Validate(account);
        policy.AssertPlan("join", Environment.MachineName, name, observed.Ou, observed.Ou, convention);
        RequireGroupExclusions(read, policy, account.ComputerGuid, name, observed.Ou);
        var now = clock.GetUtcNow();
        var key = "precreated|" + Environment.MachineName;
        if (latestByKey.TryGetValue(key, out var previous)) previews.Remove(previous.PreviewId);
        var preview = new LivePreview
        {
            PreviewId = "precreated-preview-" + Guid.NewGuid().ToString("N"), Name = name, Ou = observed.Ou, Key = key,
            CollectedAt = now, ExpiresAt = now.AddMinutes(PreviewMinutes), AvailableCount = 0, Computer = null,
            PrecreatedJoin = account
        };
        previews[preview.PreviewId] = preview; latestByKey[key] = preview;
        return Resp.Obj(("previewId", preview.PreviewId), ("name", name), ("ou", observed.Ou),
            ("computer", Environment.MachineName), ("domain", account.Domain), ("dc", account.Dc),
            ("computerGuid", account.ComputerGuid), ("targetOuGuid", account.TargetOuGuid),
            ("joinAccountMode", "precreated"), ("existingAccount", true), ("complete", true),
            ("collectedAt", Iso(now)), ("expiresAt", Iso(preview.ExpiresAt)), ("availableCount", (int?)null),
            ("source", "compte AD précréé · " + adapter.Description),
            ("warnings", Resp.Arr<string>(["Le compte existe déjà. Le plan reprend uniquement son GUID dans cette OU ; il ne crée ni ne déplace de compte.",
                "Windows vérifiera les règles Netjoin. Pesto ne modifie aucun propriétaire ni droit pour contourner un refus."], warning => (JsonNode?)Resp.Node(warning))));
    }

    private void ValidatePrecreatedJoinPreview(LivePreview preview, V1Config read, V1OperationPolicy policy)
    {
        if (preview.PrecreatedJoin is not { } account) return;
        if (PrecreatedJoinCapabilityBlockReason() is { } blocked) throw new PestoException("join.precreated_unavailable", blocked);
        if (account.ConfigurationSha256 != configStamp || preview.Name != account.Name || preview.Ou != account.TargetOu)
            throw new PestoException("plan.stale", "La configuration ou l’aperçu du compte précréé a changé.");
        RequirePrecreatedIdentity(account, read, policy);
    }

    private void ValidatePrecreatedJoinPlan(LivePlan plan, V1Config read, V1OperationPolicy policy)
    {
        if (plan.PrecreatedJoin is not { } account) return;
        if (plan.Kind != "join" || plan.ReservationRequired || plan.NameReservation is not null || plan.Continuation is not null
            || plan.Guid != account.ComputerGuid || plan.NewName != account.Name || plan.TargetOu != account.TargetOu
            || plan.TargetOuGuid != account.TargetOuGuid || plan.ConfigurationSha256 != account.ConfigurationSha256)
            throw new PestoException("join.precreated_identity", "Le plan ne correspond plus au compte précréé confirmé.");
        if (PrecreatedJoinCapabilityBlockReason() is { } blocked) throw new PestoException("join.precreated_unavailable", blocked);
        RequirePrecreatedIdentity(account, read, policy);
    }

    private void RequirePrecreatedIdentity(PrecreatedJoinAccount account, V1Config read, V1OperationPolicy policy)
    {
        PrecreatedJoinRules.Validate(account);
        if (!policy.AllowPrecreatedJoin || account.ConfigurationSha256 != configStamp
            || !string.Equals(account.Domain, read.Domain, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(account.Dc, DcOrNull(), StringComparison.OrdinalIgnoreCase)
            || !WithinScope(account.TargetOu, read.RootOu) || !read.Production && !string.Equals(account.TargetOu, read.PreprodOu, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("join.precreated_policy", "La politique ou la portée du compte précréé a changé ; nouvel aperçu obligatoire.");
        var adapter = RequireGateway();
        if (!PrecreatedJoinRules.Matches(account, adapter.FindComputer(account.Domain, account.Dc, account.Name),
            adapter.FindOrganizationalUnit(account.Domain, account.Dc, account.TargetOu)))
            throw new PestoException("join.precreated_changed", "Le compte précréé ou son OU a disparu ou changé d’identité ; aucune jonction ni création.");
        policy.AssertPlan("join", Environment.MachineName, account.Name, account.TargetOu, account.TargetOu, GetConvention(read));
        RequireGroupExclusions(read, policy, account.ComputerGuid, account.Name, account.TargetOu);
    }
}

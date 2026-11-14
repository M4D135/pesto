using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

internal sealed partial class LiveBackend
{
    private bool? LocalJoined => (gateway as ILocalDomainMembership)?.LocalComputerJoined;

    private static string? JoinMembershipBlockReason(bool? joined) => joined switch
    {
        false => null,
        true => "Ce PC est déjà membre d’un domaine. Utilisez « Un poste » pour le renommer ou le déplacer.",
        null => "L’appartenance de ce PC à un domaine n’a pas pu être confirmée. Relisez la session avant toute jonction."
    };

    private void RequireLocalJoinEligible()
    {
        var joined = LocalJoined;
        if (JoinMembershipBlockReason(joined) is { } reason)
            throw new PestoException(joined == true ? "join.alreadyJoined" : "join.membership_unknown", reason);
    }

    private static bool ForJoin(JsonElement args)
    {
        var purpose = Arguments.Text(args, "purpose");
        if (purpose.Length > 0 && purpose != "join")
            throw new PestoException("invalid_arguments", "Parcours de lecture inconnu.");
        return purpose == "join";
    }

    // V1 Get-SiteTag: exact PREPROD aliases first, otherwise one unambiguous wildcard code.
    // Never infer a preproduction code from the suffix of its OU's display name.
    private static string PreprodCode(V1Config read)
    {
        var explicitCodes = read.ExplicitSites.Where(s => s.Ou.Equals(read.PreprodOu, StringComparison.OrdinalIgnoreCase))
            .Select(s => s.Code).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        if (explicitCodes.Length == 1) return explicitCodes[0];
        if (explicitCodes.Length == 0)
        {
            var aliases = new[] { "PREPROD", read.PreprodSite, read.PreprodSite + "_PREPROD", read.PreprodSite + "_PROD_A_NOMMER" };
            foreach (var alias in aliases)
                if (read.DeclaredSites.FirstOrDefault(s => s.Pattern.Equals(alias, StringComparison.OrdinalIgnoreCase)) is { } exact)
                    return exact.Tag;
            var matches = read.DeclaredSites.Where(s => aliases.Any(alias => V1Config.MatchesWildcard(s.Pattern, alias)))
                .Select(s => s.Tag).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            if (matches.Length == 1) return matches[0];
        }
        throw new PestoException("join.preprod", "Le code du site PREPROD est absent ou ambigu dans la configuration.");
    }

    private ResolvedSite PreprodDestination(V1Config read, IDirectoryGateway adapter)
    {
        if (string.IsNullOrWhiteSpace(read.PreprodOu))
            throw new PestoException("join.preprod", "L’OU de préproduction n’est pas configurée.");
        var code = PreprodCode(read);
        _ = ResolveTargetGuid(read, adapter, read.PreprodOu);
        return new("PREPROD", "Préproduction", code, read.PreprodOu);
    }

    private (ResolvedSite Site, SelectedSiteOu? Selection) JoinSiteForInventory(V1Config read, IDirectoryGateway adapter, string wanted)
    {
        if (read.Production) return SiteForInventory(read, adapter, wanted);
        var site = PreprodDestination(read, adapter);
        if (!new[] { site.Id, site.Code, site.Ou }.Contains(wanted, StringComparer.OrdinalIgnoreCase))
            throw new PestoException("join.preprod", "La jonction en préproduction impose le site PREPROD configuré.");
        return (site, new(site.Ou, null));
    }

    private static void RequireJoinDestination(V1Config read, string name, string ou)
    {
        if (read.Production) return;
        var parts = read.BuildConvention().TryParse(name);
        if (!ou.Equals(read.PreprodOu, StringComparison.OrdinalIgnoreCase) || parts is null
            || !parts.Site.Equals(PreprodCode(read), StringComparison.OrdinalIgnoreCase)
            || !parts.Service.Equals(read.PreprodSite, StringComparison.OrdinalIgnoreCase))
            throw new PestoException("join.preprod", "La jonction en préproduction impose son OU, son code site et son service configurés.");
    }
}

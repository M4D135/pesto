using Pesto.Core;

namespace Pesto.Engine;

public sealed record GroupExclusionObservation(string ComputerGuid, string Domain, string Server, string? ComputerName, string? SourceOu,
    IReadOnlyList<string> CheckedGroupGuids, bool Complete, bool? DomainController, string? ExcludedGroupGuid, DateTimeOffset ObservedUtc);

/// <summary>Read-only, GUID-bound transitive membership. Missing groups, unknown roles, partial reads and errors refuse.</summary>
public interface IGroupExclusionReader
{
    GroupExclusionObservation ReadGroupExclusions(string domain, string? dc, string computerGuid, IReadOnlyList<string> excludedGroupGuids);
}

public static class GroupExclusionGuard
{
    public static IReadOnlyList<string> Normalize(IReadOnlyList<string> groups)
    {
        if (groups.Count > 200) throw Unverified();
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var value in groups)
        {
            if (!Guid.TryParse(value, out var id) || id == Guid.Empty) throw Unverified();
            result.Add(id.ToString("D"));
        }
        return result.ToArray();
    }

    public static GroupExclusionObservation? Require(IGroupExclusionReader? reader, string domain, string? dc, string computerGuid,
        IReadOnlyList<string> groups, string? expectedName = null, string? expectedOu = null, TimeProvider? clock = null)
    {
        var required = Normalize(groups);
        if (required.Count == 0) return null;
        if (reader is null || !Guid.TryParse(computerGuid, out var id) || id == Guid.Empty) throw Unverified();
        GroupExclusionObservation observed;
        try { observed = reader.ReadGroupExclusions(domain, dc, id.ToString("D"), required); }
        catch (Exception) { throw Unverified(); }
        var now = (clock ?? TimeProvider.System).GetUtcNow();
        if (observed is null || !Guid.TryParse(observed.ComputerGuid, out var actual) || actual != id
            || !string.Equals(domain, observed.Domain, StringComparison.OrdinalIgnoreCase)
            || !string.Equals(string.IsNullOrWhiteSpace(dc) ? domain : dc, observed.Server, StringComparison.OrdinalIgnoreCase)
            || observed.ObservedUtc > now.AddSeconds(15) || observed.ObservedUtc < now.AddSeconds(-60)
            || (expectedName is not null && !string.Equals(expectedName, observed.ComputerName, StringComparison.OrdinalIgnoreCase))
            || (expectedOu is not null && !string.Equals(expectedOu, observed.SourceOu, StringComparison.OrdinalIgnoreCase))) throw Unverified();
        if (observed.DomainController != false)
            throw new PestoException("policy.group_unverified", "POLICY.ExcludedGroupGuids : rôle de cible inconnu ou contrôleur de domaine exclu ; aucune mutation.");
        if (observed.ExcludedGroupGuid is { } excluded)
        {
            if (!Guid.TryParse(excluded, out var group) || !required.Contains(group.ToString("D"), StringComparer.OrdinalIgnoreCase)) throw Unverified();
            throw new PestoException("policy.excluded_group", "Le poste appartient à un groupe exclu par POLICY.ExcludedGroupGuids, directement ou par imbrication : aucune mutation.");
        }
        IReadOnlyList<string> checkedGroups;
        try { checkedGroups = Normalize(observed.CheckedGroupGuids); }
        catch (Exception) { throw Unverified(); }
        if (!observed.Complete || checkedGroups.Count != required.Count || observed.CheckedGroupGuids.Count != checkedGroups.Count
            || required.Any(group => !checkedGroups.Contains(group, StringComparer.OrdinalIgnoreCase))) throw Unverified();
        return observed;
    }

    public static string MembershipFilter(Guid computer, Guid group)
    {
        if (computer == Guid.Empty || group == Guid.Empty) throw Unverified();
        var literal = string.Concat(computer.ToByteArray().Select(value => "\\" + value.ToString("x2", System.Globalization.CultureInfo.InvariantCulture)));
        return "(&(objectGUID=" + literal + ")(memberOf:1.2.840.113556.1.4.1941:=<GUID=" + group.ToString("D") + ">))";
    }

    private static PestoException Unverified() => new("policy.group_unverified",
        "POLICY.ExcludedGroupGuids : identités, groupes ou appartenances AD imbriquées non confirmés complètement ; aucune mutation. Vérifiez les droits de lecture et le contrôleur sélectionné.");
}

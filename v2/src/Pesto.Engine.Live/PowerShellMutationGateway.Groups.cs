using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway
{
    private readonly IGroupExclusionReader groupExclusionReader;
    private MutationOutcome? GroupExclusionRefusal(MutationRequest request)
    {
        try
        {
            var groups = ReadPolicyRequirements().ExcludedGroupGuids;
            var id = request.ComputerGuid;
            if (groups.Count == 0 || (request.Kind == "join" && id is null)) return null;
            RequireReservedAccountGroups(request, id ?? "");
            return null;
        }
        catch (Exception)
        {
            return Refused(96, "POLICY.ExcludedGroupGuids : appartenance exclue, identité modifiée ou lecture AD incomplète ; aucune mutation autorisée.");
        }
    }

    /// <summary>Also used after a newly created reservation, before joining that exact account.</summary>
    private void RequireReservedAccountGroups(MutationRequest request, string computerGuid)
    {
        var groups = ReadPolicyRequirements().ExcludedGroupGuids;
        if (groups.Count == 0) return;
        GroupExclusionGuard.Require(groupExclusionReader, request.Domain, request.Dc, computerGuid, groups,
            request.Kind == "join" ? request.NewName : request.Computer, request.Kind == "join" ? request.TargetOu : request.SourceOu);
    }
}

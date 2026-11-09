using System.Text.Json;
using Pesto.Core;

namespace Pesto.Engine;

public static class AutomationPolicy
{
    public static void RequireContext(AutomationHostContext context)
    {
        if (context is null || !Path.IsPathFullyQualified(context.ConfigurationDirectory) || !Path.IsPathFullyQualified(context.GpRoot)
            || !AutomationPlanRules.Sid(context.ProfileSid) || !AutomationPlanRules.Sid(context.OperatorSid)
            || !RemoteWindowsEvidenceProtocol.IsGuid(context.MachineId) || !RemoteWindowsEvidenceProtocol.IsName(context.ComputerName))
            throw Refused("Le profil, l'opérateur ou l'identité locale n'ont pas été observés par l'hôte.");
        if (!context.AlreadyElevated) throw Refused("Le processus CLI doit déjà être administrateur local ; aucune invite UAC ne sera lancée.");
    }

    public static void Require(string configurationJson, MutationManagedPolicy managed, PestoCliOptions options, AutomationHostContext context)
    {
        RequireContext(context);
        if (managed.Refusal is not null) throw Refused(managed.Refusal);
        var read = V1Config.ValidateText(configurationJson);
        if (options.Action is "inspect" or "diagnose") return;
        MutationSessionGuard.RequireWritableSession();
        if (options.Action == "verify")
        {
            // Verifying releases a receipt barrier for the next automated operation: it needs an automation the
            // configuration and HKLM still allow, but no plan, account or campaign approval since nothing is sent.
            if (!(read.UnattendedOperationsEnabled && !managed.DisableUnattendedOperations) && !(read.UnattendedJoinEnabled && !managed.DisableUnattendedJoin))
                throw Refused("La vérification CLI d'un reçu exige POLICY.UnattendedOperationsEnabled ou UnattendedJoinEnabled sans interdiction HKLM.");
            return;
        }
        var policy = read.OperationPolicy.WithManaged(managed);
        policy.RequireSupported(options.Action);
        using var doc = JsonDocument.Parse(configurationJson);
        if (doc.RootElement.TryGetProperty("DEBUG", out var debug) && debug.ValueKind == JsonValueKind.Object)
            foreach (var flag in debug.EnumerateObject())
                if (flag.Value.ValueKind == JsonValueKind.True || flag.Value.ValueKind == JsonValueKind.String
                    && string.Equals(flag.Value.GetString()?.Trim(), "true", StringComparison.OrdinalIgnoreCase))
                    throw Refused("Une option DEBUG est active ; aucune préparation ou exécution automatisée réelle.");
        if (options.Action == "join")
        {
            if (!read.UnattendedJoinEnabled || managed.DisableUnattendedJoin)
                throw Refused("L'automatisation exige POLICY.UnattendedJoinEnabled=true et aucune interdiction HKLM ; le mode interactif reste distinct.");
            if (!context.ExplicitCredentialAvailable) throw Refused("La jonction automatique exige un compte AD fourni en mémoire via le canal protégé de l'hôte.");
            if (context.OperatorDomainJoined != false) throw Refused("La jonction automatique exige une appartenance locale hors domaine réellement observée.");
            if (policy.CoordinationRequired || policy.CoordinationRoot.Length > 0 || policy.ReserveNamesInAd)
                throw Refused("Comme en V1, la jonction non accompagnée refuse la coordination partagée et ReserveNamesInAD ; utilisez le parcours interactif explicite.");
        }
        else
        {
            if (!read.UnattendedOperationsEnabled || managed.DisableUnattendedOperations)
                throw Refused("L'automatisation exige POLICY.UnattendedOperationsEnabled=true et aucune interdiction HKLM.");
            if (context.OperatorDomainJoined != true) throw Refused("Le poste d'administration doit être membre du domaine pour une opération distante non accompagnée.");
            if (options.Action is "rename" or "renameMove" && !AutomationPlanRules.Same(options.Computer, context.ComputerName)
                && !context.ExplicitCredentialAvailable) throw Refused("Le renommage distant exige un compte AD explicite ; aucun mot de passe n'est déduit du jeton Windows.");
        }
    }

    public static void RequireRequest(MutationRequest request, AutomationExecutionAuthorization authority, string configurationJson,
        MutationManagedPolicy managed, AutomationHostContext context, DateTimeOffset now)
    {
        if (request.Automation is null || !ReferenceEquals(request.Automation, authority)) throw Refused("Autorisation automatique interne absente.");
        var plan = authority.Plan;
        AutomationPlanRules.RequireContext(plan, context, request.ConfigurationSha256 ?? "", now);
        Require(configurationJson, managed, new(plan.Action, plan.Computer, plan.NewName, plan.TargetOu,
            plan.Type, plan.SiteCode, plan.ServiceCode, Execute: true), context);
        if (request.Kind != plan.Action || request.ReceiptId != authority.ReceiptId || !AutomationPlanRules.Same(request.Computer, plan.Computer)
            || !AutomationPlanRules.Same(request.ComputerGuid, plan.ComputerGuid)
            || !AutomationPlanRules.Same(request.NewName ?? request.Computer, plan.NewName)
            || !AutomationPlanRules.Same(request.SourceOu, plan.SourceOu) || !AutomationPlanRules.Same(request.TargetOu, plan.TargetOu)
            || !AutomationPlanRules.Same(request.TargetOuGuid, plan.TargetOuGuid) || !AutomationPlanRules.Same(request.Domain, plan.Domain)
            || !AutomationPlanRules.Same(request.Dc, plan.Dc) || request.Continuation is not null || request.Reservation is not null
            || request.PrecreatedJoin is not null || request.Attributes is not null
            || request.Kind is "rename" or "renameMove" && (request.Entra is null
                || !AutomationPlanRules.Same(request.Entra.MachineId, plan.TargetMachineId)
                || request.Entra.Policy != plan.EntraPolicy)
            || request.Entra?.LeaveRequired == true && (!plan.EntraLeaveRequired || !authority.EntraLeaveConfirmed || !request.EntraLeaveConfirmed))
            throw Refused("La demande native ne correspond plus à l'intention automatisée confirmée.");
        AutomationCampaignApproval.Require(managed.CampaignApprovalJson, authority.ApprovalJson, plan, context.OperatorSid, now);
    }

    private static PestoException Refused(string message) => new("automation.policy", message);
}

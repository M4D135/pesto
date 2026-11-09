namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway
{
    /// <summary>CLI authority is not a bridge flag. Local identity, HKLM and immutable Started bytes are re-read under GP.</summary>
    private string? AutomationAuthorityRefusal(MutationRequest request, byte[] configurationBytes, string configurationJson)
    {
        if (request.Automation is not { } authority) return null;
        try
        {
            if (v1InstallationPath is null) return "La configuration d'automatisation n'est pas liée à ce moteur.";
            var identity = WindowsAutomationSupport.ReadLocalIdentity();
            var context = new AutomationHostContext(v1InstallationPath, authority.ProfileSid, identity.OperatorSid,
                identity.MachineId, identity.ComputerName, ReceiptGpRoot(), identity.AlreadyElevated,
                fallbackCredentials is IWindowsCredentialSource && FallbackAccountMode == TaskFallbackAccountMode.ExplicitAccount,
                identity.DomainJoined, WindowsAutomationSupport.SecureDirectory, WindowsManagedPolicyReader.Read);
            AutomationJournal.RequireAuthority(ReceiptGpRoot(), authority);
            if (MutationPolicyGuard.ConfigurationRefusal(configurationBytes, authority.Plan.ConfigurationSha256) is { } changed) return changed;
            AutomationPolicy.RequireRequest(request, authority, configurationJson, ReadManagedPolicy(), context, DateTimeOffset.UtcNow);
            return null;
        }
        catch (Pesto.Core.PestoException error) { return error.Message; }
        catch (Exception) { return "L'intention automatique, l'identité locale ou les restrictions HKLM ne sont plus prouvées ; aucune nouvelle commande."; }
    }
}

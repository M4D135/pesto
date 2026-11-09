using System.Text;
using Pesto.Core;

namespace Pesto.Engine.Live;

public sealed partial class PowerShellMutationGateway : IMutationPrecreatedJoin
{
    public bool SupportsPrecreatedJoin => true;

    /// <summary>Revalidated under the GP mutex and pinned configuration before any native mutation.
    /// The fixed worker repeats GUID/name/OU/domain/DC checks immediately before Rename and Add.</summary>
    private void RequirePrecreatedAccount(MutationRequest request)
    {
        if (request.PrecreatedJoin is not { } account) return;
        PrecreatedJoinRules.RequireRequest(request);
        if (v1InstallationPath is null) throw new PestoException("join.precreated_policy", "Configuration absente.");
        var path = Path.Combine(v1InstallationPath, "cfg.json"); RequireNoReparsePoint(path);
        if (new FileInfo(path).Length is < 1 or > ConfigurationDocument.MaximumBytes)
            throw new PestoException("join.precreated_policy", "Configuration illisible.");
        var bytes = File.ReadAllBytes(path);
        if (MutationPolicyGuard.ConfigurationRefusal(bytes, request.ConfigurationSha256) is { } changed)
            throw new PestoException("join.precreated_policy", changed);
        using var stream = new MemoryStream(bytes);
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        var policyFailure = PrecreatedJoinRules.ConfigurationRefusal(reader.ReadToEnd(), request);
        if (policyFailure is not null) throw new PestoException("join.precreated_policy", policyFailure);
        var directory = new PowerShellDirectoryGateway(fallbackCredentials as IWindowsCredentialSource, v1InstallationPath);
        var computer = directory.FindComputer(account.Domain, account.Dc, account.Name);
        var ou = directory.FindOrganizationalUnit(account.Domain, account.Dc, account.TargetOu);
        if (!PrecreatedJoinRules.Matches(account, computer, ou))
            throw new PestoException("join.precreated_changed", "Le GUID, le nom ou l’OU du compte précréé a changé : aucune création ni jonction.");
        RequireReservedAccountGroups(request, account.ComputerGuid);
    }

    private static object? PrecreatedJoinPayload(MutationRequest request) => request.PrecreatedJoin is { } account ? new
    { account.ComputerGuid, account.Name, account.Domain, account.Dc, account.TargetOu, account.TargetOuGuid } : null;

    private static MutationOutcome WithPrecreatedJoinOutcome(MutationRequest request, MutationOutcome outcome) =>
        request.PrecreatedJoin is { } account && outcome.Status is MutationStatus.PendingRestart or MutationStatus.Succeeded
            ? outcome with { ObservedGuid = account.ComputerGuid } : outcome;

    public static string PrecreatedJoinWorkerScript => PrecreatedJoinScript.Source;
}

internal static class PrecreatedJoinScript
{
    internal const string Source = """
function Assert-PestoPrecreatedJoin($r,$expectedName,$expectedOu,$expectedDomain,$expectedServer,$adp){
  if($null -eq $r){throw 'Compte précréé absent du plan.'}
  $id=[Guid]::Empty;$ouId=[Guid]::Empty
  if(-not [Guid]::TryParse([string]$r.ComputerGuid,[ref]$id) -or $id -eq [Guid]::Empty -or
     -not [Guid]::TryParse([string]$r.TargetOuGuid,[ref]$ouId) -or $ouId -eq [Guid]::Empty){throw 'GUID précréé ou OU invalide.'}
  if([string]$r.Name -ine $expectedName -or [string]$r.TargetOu -ine $expectedOu -or
     [string]$r.Domain -ine $expectedDomain -or [string]$r.Dc -ine $expectedServer){throw 'Portée précréée différente du plan.'}
  $root=Get-ADRootDSE -ErrorAction Stop @adp
  if([string]$root.dnsHostName -ine $expectedServer){throw 'Le contrôleur précréé a changé.'}
  $domainCheck=Get-ADDomain -ErrorAction Stop @adp
  if([string]$domainCheck.DNSRoot -ine $expectedDomain){throw 'Le domaine précréé a changé.'}
  $ou=@(Get-ADOrganizationalUnit -Identity $ouId -Properties ObjectGUID,DistinguishedName -ErrorAction Stop @adp)
  if($ou.Count -ne 1 -or [Guid]$ou[0].ObjectGUID -ne $ouId -or [string]$ou[0].DistinguishedName -ine $expectedOu){throw 'L''identité de l''OU précréée a changé.'}
  $owned=@(Get-ADComputer -Identity $id -Properties ObjectGUID,Name,DistinguishedName,userAccountControl -ErrorAction Stop @adp)
  $ldap='(|(name='+$expectedName+')(sAMAccountName='+$expectedName+'$)(dNSHostName='+$expectedName+'.'+$expectedDomain+'))'
  $named=@(Get-ADComputer -LDAPFilter $ldap -SearchBase ([string]$domainCheck.DistinguishedName) -SearchScope Subtree -ResultSetSize 2 -Properties ObjectGUID -ErrorAction Stop @adp)
  if($owned.Count -ne 1 -or $named.Count -ne 1 -or [Guid]$owned[0].ObjectGUID -ne $id -or [Guid]$named[0].ObjectGUID -ne $id -or
     [string]$owned[0].Name -ine $expectedName -or (Get-ParentDn ([string]$owned[0].DistinguishedName)) -ine $expectedOu -or
     $null -eq $owned[0].userAccountControl -or (([long]$owned[0].userAccountControl -band 8192) -ne 0)){
    throw 'Le compte précréé exact n''est plus confirmé ou désigne un contrôleur de domaine.'
  }
}
function Assert-PestoPrecreatedJoinResult($r,$adp){
  Assert-PestoPrecreatedJoin $r ([string]$r.Name) ([string]$r.TargetOu) ([string]$r.Domain) ([string]$r.Dc) $adp
}
""";
}

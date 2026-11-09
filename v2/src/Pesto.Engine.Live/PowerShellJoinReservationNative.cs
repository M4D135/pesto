using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Pesto.Engine.Live;

/// <summary>Fixed Windows PowerShell 5.1 worker. The parent keeps the GP mutex and durable receipt;
/// only these three typed operations can reach New/Remove-ADComputer. No ACL or owner changes exist.</summary>
internal sealed class PowerShellJoinReservationNative(Func<string?> module, Func<ProtectedWindowsCredential?> credentials,
    Func<(string Path, string Sha256)> configuration, Func<IReadOnlyList<string>> excludedGroups,
    Func<DateTimeOffset?> nameLeaseExpiresAt) : IJoinReservationNative
{
    private static readonly JsonSerializerOptions ResponseOptions = new()
    { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    public JoinReservationObservation Read(JoinReservationReceipt receipt)
    {
        var result = Run("inspect", receipt);
        return result.State == "inspected" && result.Observation is not null ? result.Observation
            : throw new IOException("Lecture native de réservation non confirmée.");
    }
    public JoinReservationNativeResult Create(JoinReservationReceipt receipt) => Run("reserve", receipt);
    public JoinReservationNativeResult Remove(JoinReservationReceipt receipt) => Run("release", receipt);
    public static string ConstantScript => Script;
    internal static ProcessStartInfo WorkerStartInfo() => PowerShellFixedWorker.StartInfo(Script);

    private JoinReservationNativeResult Run(string operation, JoinReservationReceipt receipt)
    {
        JoinReservationStore.Validate(receipt);
        if (!OperatingSystem.IsWindows() || WindowsPowerShellProbe.UnavailableReason is not null)
            return new("refused", "Windows PowerShell 5.1 indisponible ; aucune commande envoyée.");
        var modulePath = module() ?? throw new IOException("Module ActiveDirectory vérifié absent.");
        var configurationProof = configuration();
        var payload = JsonSerializer.Serialize(new
        {
            Operation = operation, ModulePath = modulePath, Credential = credentials(), receipt.OperationId,
            receipt.Computer, receipt.Name, receipt.Domain, receipt.Dc, receipt.TargetOu, receipt.TargetOuGuid,
            receipt.MachineId, receipt.Marker, receipt.ComputerGuid,
            ConfigurationPath = configurationProof.Path, ConfigurationSha256 = configurationProof.Sha256,
            ExcludedGroupGuids = excludedGroups(),
            NameLeaseExpiresAt = nameLeaseExpiresAt()?.ToString("O"),
        });
        var start = WorkerStartInfo();
        Process? process;
        try { process = Process.Start(start); }
        catch (Exception) { return new("refused", "Le processus natif n’a pas démarré ; aucune commande envoyée."); }
        if (process is null) return new("refused", "Le processus natif n’a pas démarré ; aucune commande envoyée.");
        using (process)
        {
            OwnedMutationJob job;
            try { job = OwnedMutationJob.Attach(process); }
            catch (Exception) { return new("refused", "Le cycle de vie du worker ne peut pas être garanti ; aucune commande AD transmise."); }
            using var ownedJob = job;
            var output = process.StandardOutput.ReadToEndAsync();
            var errors = process.StandardError.ReadToEndAsync();
            try
            {
                PowerShellFixedWorker.Send(process, Script, payload);
                if (!process.WaitForExit(operation == "inspect" ? 30000 : 90000))
                {
                    try { process.Kill(entireProcessTree: true); } catch (Exception) { }
                    return new("uncertain", "L’opération native a expiré ; aucune reprise ni suppression automatique.", MutationMayHaveStarted: operation != "inspect");
                }
                var json = output.GetAwaiter().GetResult();
                _ = errors.GetAwaiter().GetResult();
                if (json.Length is < 2 or > 65536) throw new JsonException();
                using var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 6 });
                if (document.RootElement.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count()
                    != document.RootElement.EnumerateObject().Count()) throw new JsonException();
                var result = JsonSerializer.Deserialize<JoinReservationNativeResult>(json, ResponseOptions) ?? throw new JsonException();
                if (result.State is not ("inspected" or "reserved" or "released" or "gone" or "taken" or "refused" or "kept" or "uncertain")
                    || result.Message is null || result.Message.Length > 2048) throw new JsonException();
                return result;
            }
            catch (Exception)
            {
                try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch (Exception) { }
                return new("uncertain", "Résultat natif illisible ou interrompu ; aucune reprise automatique.", MutationMayHaveStarted: operation != "inspect");
            }
        }
    }

    private const string Script = BootIdentityScript.Source + GroupExclusionScript.Source + """
$ErrorActionPreference='Stop'
$secure=$null
$configurationStream=$null
$reservationMutex=$null
$reservationMutexOwned=$false
$mayHaveStarted=$false
$observation=$null
$result=@{state='refused';message='Vérifications non terminées ; aucune mutation confirmée.';observation=$null;mutationMayHaveStarted=$false}
function Test-NotFound($e){ return $e.Exception.GetType().Name -eq 'ADIdentityNotFoundException' }
function Read-ReservedComputer($identity){
  try{ return @(Get-ADComputer -Identity $identity -Properties ObjectGUID,Name,DistinguishedName,Description,DNSHostName,ServicePrincipalName,userAccountControl -ErrorAction Stop @adp) }
  catch{if(Test-NotFound $_){return @()};throw}
}
function Read-ReservationObservation($identity){
  $items=@(Read-ReservedComputer $identity)
  if($items.Count -gt 1){throw 'Identité AD ambiguë.'}
  $r=@{machineId=$machineId;currentComputer=$active;domain=$domain;dc=$dc;bootUtc=$boot;partOfDomain=[bool]$cs.PartOfDomain;
       pendingRename=($active -ine $configured);domainController=([int]$cs.DomainRole -ge 4);absent=($items.Count -eq 0);
       computerGuid=$null;name=$null;distinguishedName=$null;marker=$null;dnsHostName=$null;servicePrincipalNames=@();targetOuGuid=$ouGuid;error=$null}
  if($items.Count -eq 1){
    $pc=$items[0];$id=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$pc.ObjectGUID,[ref]$id) -or $id -eq [Guid]::Empty){throw 'GUID AD non confirmé.'}
    $r.computerGuid=$id.ToString('D');$r.name=[string]$pc.Name;$r.distinguishedName=[string]$pc.DistinguishedName
    $r.marker=[string]$pc.Description;$r.dnsHostName=[string]$pc.DNSHostName;$r.servicePrincipalNames=@($pc.ServicePrincipalName|ForEach-Object{[string]$_})
    if($null -eq $pc.userAccountControl){throw 'Rôle AD non confirmé.'}
    if(([long]$pc.userAccountControl -band 8192) -ne 0){$r.domainController=$true}
  }
  return $r
}
function Assert-OwnedUnused($r){
  if($r.absent){throw 'Compte réservé absent.'}
  if($r.domainController -or $r.partOfDomain -or $r.pendingRename){throw 'État Windows ou rôle sensible incompatible.'}
  if($j.ComputerGuid -and $r.computerGuid -ine [string]$j.ComputerGuid){throw 'GUID différent du reçu.'}
  if($r.name -ine [string]$j.Name -or $r.distinguishedName -ine ('CN='+[string]$j.Name+','+[string]$j.TargetOu) -or $r.marker -cne [string]$j.Marker){throw 'Propriété exacte du compte non confirmée.'}
  if($r.dnsHostName -or @($r.servicePrincipalNames).Count -ne 0){throw 'Compte déjà utilisé : il reste conservé.'}
}
try{
  $j=[Console]::In.ReadToEnd()|ConvertFrom-Json
  if(-not $j.ConfigurationPath -or [string]$j.ConfigurationSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'Empreinte de configuration absente.'}
  # Keep the exact local file open against replacement while the worker checks and mutates AD.
  $configurationStream=[IO.File]::Open([string]$j.ConfigurationPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if($configurationStream.Length -lt 1 -or $configurationStream.Length -gt 1048576){throw 'Configuration illisible.'}
  $sha=[Security.Cryptography.SHA256]::Create()
  try{$configurationHash=[BitConverter]::ToString($sha.ComputeHash($configurationStream)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($configurationHash -cne [string]$j.ConfigurationSha256){throw 'Configuration remplacée après confirmation.'}
  if([string]$j.Operation -notin @('reserve','inspect','release')){throw 'Opération inconnue.'}
  $nameRx='^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$'
  if([string]$j.Name -notmatch $nameRx -or [string]$j.Computer -notmatch $nameRx){throw 'Nom invalide.'}
  $operationId=[Guid]::Empty;$expectedMachine=[Guid]::Empty;$expectedOu=[Guid]::Empty
  if(-not [Guid]::TryParse([string]$j.OperationId,[ref]$operationId) -or $operationId -eq [Guid]::Empty -or
     -not [Guid]::TryParse([string]$j.MachineId,[ref]$expectedMachine) -or $expectedMachine -eq [Guid]::Empty -or
     -not [Guid]::TryParse([string]$j.TargetOuGuid,[ref]$expectedOu) -or $expectedOu -eq [Guid]::Empty){throw 'Identité du reçu invalide.'}
  if([string]$j.Marker -cne ('Réservé par Pesto ['+[string]$j.OperationId+']')){throw 'Marqueur invalide.'}
  $domain=[string]$j.Domain;$dc=[string]$j.Dc
  if(-not $domain -or -not $dc -or $dc -ieq $domain -or -not $dc.EndsWith('.'+$domain,[StringComparison]::OrdinalIgnoreCase)){throw 'DC exact requis.'}
  $cs=Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
  $boot=Get-PestoStableBootUtc
  $machineId=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
  if($machineId -ine [string]$j.MachineId){throw 'Ce reçu appartient à une autre machine.'}
  # The parent owns GP_PostMutation_v1. This independent child-owned mutex survives a parent crash,
  # so another inspection cannot mistake an in-flight orphan create/remove for a completed operation.
  $reservationMutex=New-Object Threading.Mutex($false,('Global\GP_JoinReservation_'+$expectedMachine.ToString('N')))
  try{$reservationMutexOwned=$reservationMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$reservationMutexOwned=$true}
  if(-not $reservationMutexOwned){throw 'Un worker de réservation est encore actif ; inspection ou mutation refusée.'}
  $active=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  $configured=[string](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName' -Name ComputerName -ErrorAction Stop).ComputerName
  if($active -ine [string]$cs.Name -or ($active -ine [string]$j.Computer -and $active -ine [string]$j.Name)){throw 'Identité locale différente.'}
  if(-not $j.ModulePath){throw 'Module ActiveDirectory absent.'}
  $adp=@{Server=$dc}
  if($j.Credential){
    $bytes=$null
    try{
      Add-Type -AssemblyName System.Security
      $bytes=[Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String([string]$j.Credential.blob),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
      $secure=New-Object Security.SecureString
      for($i=0;$i -lt $bytes.Length;$i+=2){$secure.AppendChar([char]([int]$bytes[$i] -bor ([int]$bytes[$i+1] -shl 8)))}
      $secure.MakeReadOnly();$adp.Credential=New-Object Management.Automation.PSCredential([string]$j.Credential.userName,$secure)
    }finally{if($bytes){[Array]::Clear($bytes,0,$bytes.Length)}}
  }
  Import-Module -Name ([string]$j.ModulePath) -ErrorAction Stop
  $root=Get-ADRootDSE @adp
  if([string]$root.dnsHostName -ine $dc){throw 'Le serveur ne correspond pas au DC figé.'}
  $adDomain=Get-ADDomain @adp
  if([string]$adDomain.DNSRoot -ine $domain){throw 'Le DC appartient à un autre domaine.'}
  $ou=@(Get-ADOrganizationalUnit -Identity $expectedOu -Properties ObjectGUID,DistinguishedName @adp)
  if($ou.Count -ne 1 -or [string]$ou[0].DistinguishedName -ine [string]$j.TargetOu){throw 'OU déplacée ou remplacée.'}
  $ouGuid=([Guid]$ou[0].ObjectGUID).ToString('D')
  if($ouGuid -ine [string]$j.TargetOuGuid){throw 'GUID de destination différent.'}
  $identity=if($j.ComputerGuid){[Guid]$j.ComputerGuid}else{[string]$j.Name+'$'}
  $observation=Read-ReservationObservation $identity
  if([string]$j.Operation -eq 'inspect'){
    $result.state='inspected';$result.message='Lecture explicite terminée ; aucune mutation.'
  }else{
    if($env:PESTO_READONLY_SESSION -eq '1'){throw 'Session lecture seule.'}
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Élévation locale absente.'}
    if([bool]$cs.PartOfDomain -or [int]$cs.DomainRole -ge 4 -or $active -ine $configured){throw 'État local incompatible avec une réservation.'}
    if([string]$j.Operation -eq 'reserve'){
      $ldap='(|(name='+[string]$j.Name+')(sAMAccountName='+[string]$j.Name+'$)(dNSHostName='+[string]$j.Name+'.'+$domain+'))'
      $collisions=@(Get-ADComputer -LDAPFilter $ldap -ResultSetSize 2 -ErrorAction Stop @adp)
      if(-not $observation.absent -or $collisions.Count -gt 0){$result.state='taken';$result.message='Le nom existe déjà ; aucun objet existant adopté.'}
      else{
        try{
          if($j.NameLeaseExpiresAt){
            $leaseExpiry=[DateTimeOffset]::Parse([string]$j.NameLeaseExpiresAt,[Globalization.CultureInfo]::InvariantCulture)
            if($leaseExpiry -le [DateTimeOffset]::UtcNow){throw 'Le bail du nom a expiré pendant les vérifications AD ; nouvel aperçu et nouvelle confirmation requis.'}
          }
          $mayHaveStarted=$true
          $created=@(New-ADComputer -Name ([string]$j.Name) -SamAccountName ([string]$j.Name+'$') -Path ([string]$j.TargetOu) -Enabled $true -Description ([string]$j.Marker) -PassThru @adp)
        }catch{
          if($_.Exception.GetType().Name -eq 'ADIdentityAlreadyExistsException'){$mayHaveStarted=$false;$result.state='taken';$result.message='Le nom vient d''être pris ; aucun objet adopté.'}
          else{throw}
        }
        if($mayHaveStarted){
          if($created.Count -ne 1){throw 'Création sans identité unique.'}
          $createdGuid=[Guid]::Empty
          if(-not [Guid]::TryParse([string]$created[0].ObjectGUID,[ref]$createdGuid) -or $createdGuid -eq [Guid]::Empty){throw 'GUID créé non confirmé.'}
          $observation=Read-ReservationObservation $createdGuid
          Assert-OwnedUnused $observation
          if($observation.computerGuid -ine $createdGuid.ToString('D')){throw 'GUID relu différent.'}
          $result.state='reserved';$result.message='Compte créé puis relu par son GUID sur le DC figé.'
        }
      }
    }else{
      if($observation.absent){$result.state='gone';$result.message='Absence explicitement confirmée ; aucune suppression envoyée.'}
      else{
        Assert-OwnedUnused $observation
        if(-not $j.ComputerGuid){throw 'Aucun retrait sans GUID préalablement persisté.'}
        Assert-PestoGroupExclusions ([string]$j.ComputerGuid) @($j.ExcludedGroupGuids) $adp ([string]$j.Name) ([string]$j.TargetOu)
        $observation=Read-ReservationObservation ([Guid]$j.ComputerGuid)
        Assert-OwnedUnused $observation
        $mayHaveStarted=$true
        Remove-ADComputer -Identity ([Guid]$j.ComputerGuid) -Confirm:$false @adp
        $observation=Read-ReservationObservation ([Guid]$j.ComputerGuid)
        if(-not $observation.absent){throw 'Absence non confirmée après retrait.'}
        $result.state='released';$result.message='Retrait confirmé par absence sur le DC du reçu.'
      }
    }
  }
}catch{
  $result.state=if($mayHaveStarted){'uncertain'}else{'refused'}
  $result.message=if($mayHaveStarted){'Une commande a pu être envoyée ; le compte reste conservé, inspection explicite requise.'}else{'Vérification native refusée ; aucune commande de création ou de suppression envoyée.'}
  if($observation){$observation.error='Lecture ou contrôle natif incomplet.'}
}finally{
  if($secure){$secure.Dispose()};if($configurationStream){$configurationStream.Dispose()}
  if($reservationMutex){if($reservationMutexOwned){$reservationMutex.ReleaseMutex()};$reservationMutex.Dispose()}
}
$result.observation=$observation;$result.mutationMayHaveStarted=$mayHaveStarted
$result|ConvertTo-Json -Depth 6 -Compress
""";
}

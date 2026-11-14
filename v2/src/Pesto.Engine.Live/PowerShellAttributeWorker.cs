using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Pesto.Engine.Live;

internal sealed record AttributeNativeResult(string State, string Message, AttributeSnapshot? Snapshot = null,
    AttributeReference? Reference = null, bool MutationMayHaveStarted = false);

/// <summary>Fixed PS 5.1 attribute worker. Three closed operations, one Set-ADObject site and no replay branch.</summary>
internal static class PowerShellAttributeWorker
{
    private static readonly JsonSerializerOptions Options = new() { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };
    public static AttributeNativeResult Run(string operation, string domain, string dc, AttributeTarget? target,
        IReadOnlyList<AttributeChange>? changes, string? referenceDn, string modulePath, ProtectedWindowsCredential? credential,
        string configurationPath, string configurationSha256, string rootOu, IReadOnlyList<string> groups)
    {
        if (operation is not ("inspect" or "reference" or "apply")) throw new InvalidOperationException("Opération attributs non déclarée.");
        if (!OperatingSystem.IsWindows()) return new("refused", "La lecture native des attributs exige Windows.");
        var sent = false;
        try
        {
            var json = JsonSerializer.Serialize(new { Operation = operation, Domain = domain, Dc = dc, Target = target, Changes = changes,
                ReferenceDn = referenceDn, ModulePath = modulePath, Credential = credential, ConfigurationPath = configurationPath,
                ConfigurationSha256 = configurationSha256, RootOu = rootOu, ExcludedGroupGuids = groups });
            using var process = Process.Start(PowerShellFixedWorker.StartInfo(Source));
            if (process is null) return new("refused", "Le worker attributs ne peut pas démarrer ; aucune commande envoyée.");
            using var job = OwnedMutationJob.Attach(process);
            var output = ReadBounded(process.StandardOutput); var errors = ReadBounded(process.StandardError);
            sent = true; PowerShellFixedWorker.Send(process, Source, json);
            if (!process.WaitForExit(operation == "apply" ? 90000 : 30000))
            {
                try { process.Kill(entireProcessTree: true); } catch (Exception) { }
                return new("uncertain", "Délai du worker dépassé ; aucun rejeu autorisé.", MutationMayHaveStarted: operation == "apply");
            }
            var response = output.GetAwaiter().GetResult(); _ = errors.GetAwaiter().GetResult();
            using var document = JsonDocument.Parse(response, new JsonDocumentOptions { MaxDepth = 10 });
            RequireUnique(document.RootElement);
            var result = JsonSerializer.Deserialize<AttributeNativeResult>(response, Options) ?? throw new JsonException();
            if (result.State is not ("inspected" or "reference" or "verified" or "refused" or "uncertain")
                || result.Message is null || result.Message.Length > 1024 || result.Message.Any(char.IsControl)
                || result.State is "inspected" or "reference" or "verified" && process.ExitCode != 0
                || result.State == "refused" && (process.ExitCode != 96 || result.MutationMayHaveStarted)
                || result.State == "verified" && !result.MutationMayHaveStarted
                || operation != "apply" && result.MutationMayHaveStarted) throw new JsonException();
            if (result.Snapshot is not null) AttributeMutationRules.RequireSnapshot(result.Snapshot, target);
            if (result.Reference is not null) AttributeMutationRules.RequireReference(result.Reference, domain, referenceDn);
            return result;
        }
        catch (Exception)
        {
            return sent ? new("uncertain", "Réponse du worker non vérifiable ; aucun rejeu.", MutationMayHaveStarted: operation == "apply")
                : new("refused", "Le cycle de vie du worker ne peut pas être garanti ; aucune commande envoyée.");
        }
    }
    private static async Task<string> ReadBounded(StreamReader reader)
    {
        var result = new System.Text.StringBuilder(); var buffer = new char[2048]; int count;
        while ((count = await reader.ReadAsync(buffer).ConfigureAwait(false)) != 0)
        { if (result.Length + count > 131072) throw new IOException("Sortie attributs hors limites."); result.Append(buffer, 0, count); }
        return result.ToString();
    }
    private static void RequireUnique(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            if (value.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() != value.EnumerateObject().Count()) throw new JsonException();
            foreach (var p in value.EnumerateObject()) RequireUnique(p.Value);
        }
        else if (value.ValueKind == JsonValueKind.Array) foreach (var item in value.EnumerateArray()) RequireUnique(item);
    }
    public static string Source => GroupExclusionScript.Source + "\n" + Body;
    // Keep quote delimiters ASCII. PowerShell also treats typographic apostrophes as delimiters.
    public const string Body = """
$ErrorActionPreference='Stop'
$secure=$null;$configurationStream=$null
$result=@{State='refused';Message='Verification incomplete; aucune modification envoyee.';Snapshot=$null;Reference=$null;MutationMayHaveStarted=$false}
function Assert-Value($v){
  if($v -isnot [string] -or $v.Length -gt 1024 -or $v -match '[\x00-\x1f\x7f]'){throw 'Valeur attribut invalide.'}
}
function Read-Reference([string]$dn,[string]$expectedGuid=''){
  Assert-Value $dn
  if(-not $dn -or $dn -notmatch '^(CN|OU)=.+,DC=' -or -not $dn.EndsWith(','+[string]$adDomain.DistinguishedName,[StringComparison]::OrdinalIgnoreCase)){throw 'Reference hors domaine.'}
  $named=@(Get-ADObject -Identity $dn -Properties ObjectGUID,DistinguishedName -ErrorAction Stop @adp)
  $guid=[Guid]::Empty
  if($named.Count -ne 1 -or [string]$named[0].DistinguishedName -ine $dn -or -not [Guid]::TryParse([string]$named[0].ObjectGUID,[ref]$guid) -or $guid -eq [Guid]::Empty){throw 'Reference non unique.'}
  if($expectedGuid){
    $expected=[Guid]::Empty
    if(-not [Guid]::TryParse($expectedGuid,[ref]$expected) -or $expected -eq [Guid]::Empty -or $guid -ne $expected){throw 'Reference remplacee.'}
    $bound=@(Get-ADObject -Identity $expected -Properties ObjectGUID,DistinguishedName -ErrorAction Stop @adp)
    if($bound.Count -ne 1 -or [Guid]$bound[0].ObjectGUID -ne $expected -or [string]$bound[0].DistinguishedName -ine $dn){throw 'Reference deplacee.'}
  }
  return @{DistinguishedName=[string]$named[0].DistinguishedName;Guid=$guid.ToString('D')}
}
function Read-Target{
  $t=$j.Target;$guid=[Guid]::Empty;$ouGuid=[Guid]::Empty
  if($null -eq $t -or -not [Guid]::TryParse([string]$t.ComputerGuid,[ref]$guid) -or $guid -eq [Guid]::Empty -or
     -not [Guid]::TryParse([string]$t.OuGuid,[ref]$ouGuid) -or $ouGuid -eq [Guid]::Empty){throw 'Identite cible absente.'}
  if([string]$t.Computer -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$' -or [string]$t.Domain -ine [string]$j.Domain -or
     [string]$t.Dc -ine [string]$j.Dc -or [string]$t.DistinguishedName -ine ('CN='+[string]$t.Computer+','+[string]$t.Ou)){throw 'Portee cible incoherente.'}
  $ouText=[string]$t.Ou;$rootText=[string]$j.RootOu
  if(-not $rootText -or ($ouText -ine $rootText -and -not $ouText.EndsWith(','+$rootText,[StringComparison]::OrdinalIgnoreCase))){throw 'OU hors perimetre.'}
  $ou=@(Get-ADOrganizationalUnit -Identity $ouGuid -Properties ObjectGUID,DistinguishedName -ErrorAction Stop @adp)
  if($ou.Count -ne 1 -or [Guid]$ou[0].ObjectGUID -ne $ouGuid -or [string]$ou[0].DistinguishedName -ine $ouText){throw 'OU remplacee ou deplacee.'}
  $items=@(Get-ADComputer -Identity $guid -Properties ObjectGUID,Name,DistinguishedName,description,location,managedBy,userAccountControl -ErrorAction Stop @adp)
  if($items.Count -ne 1){throw 'Compte non unique.'};$pc=$items[0]
  if([Guid]$pc.ObjectGUID -ne $guid -or [string]$pc.Name -ine [string]$t.Computer -or [string]$pc.DistinguishedName -ine [string]$t.DistinguishedName -or
     $null -eq $pc.userAccountControl -or (([long]$pc.userAccountControl -band 8192) -ne 0)){throw 'Identite ou role AD different.'}
  $values=@{Description=[string]$pc.description;Location=[string]$pc.location;ManagedBy=[string]$pc.managedBy}
  foreach($name in @('Description','Location','ManagedBy')){Assert-Value $values[$name]}
  $referenceGuid=$null
  if($values.ManagedBy){$reference=Read-Reference $values.ManagedBy;$referenceGuid=$reference.Guid}
  return @{Target=@{Computer=[string]$pc.Name;ComputerGuid=$guid.ToString('D');DistinguishedName=[string]$pc.DistinguishedName;Ou=$ouText;OuGuid=$ouGuid.ToString('D');Domain=[string]$adDomain.DNSRoot;Dc=[string]$root.dnsHostName};
           Values=$values;ObservedAt=[DateTimeOffset]::UtcNow.ToString('o');ManagedByReferenceGuid=$referenceGuid}
}
function Assert-Changes($snapshot){
  if(@($j.Changes).Count -lt 1 -or @($j.Changes).Count -gt 3){throw 'Diff absent.'};$seen=@{}
  foreach($c in $j.Changes){
    if([string]$c.Attribute -cnotin @('description','location','managedBy') -or $seen.ContainsKey([string]$c.Attribute)){throw 'Attribut inconnu ou duplique.'};$seen[[string]$c.Attribute]=$true
    Assert-Value $c.Before;Assert-Value $c.After
    if([string]$c.Before -ceq [string]$c.After -or [string]$snapshot.Values.([string]$c.Attribute) -cne [string]$c.Before){throw 'Ancienne valeur differente.'}
    if([string]$c.Attribute -ceq 'managedBy' -and [string]$c.After){
      $referenceGuid=[Guid]::Empty
      if(-not [Guid]::TryParse([string]$c.ReferenceGuid,[ref]$referenceGuid) -or $referenceGuid -eq [Guid]::Empty){throw 'GUID managedBy absent.'}
      [void](Read-Reference ([string]$c.After) ($referenceGuid.ToString('D')))
    }
    elseif($c.ReferenceGuid){throw 'GUID de reference inattendu.'}
  }
}
try{
  $j=[Console]::In.ReadToEnd()|ConvertFrom-Json
  if([string]$j.Operation -cnotin @('inspect','reference','apply')){throw 'Operation inconnue.'}
  if(-not $j.ConfigurationPath -or [string]$j.ConfigurationSha256 -cnotmatch '^[A-Fa-f0-9]{64}$'){throw 'Configuration non liee.'}
  $configurationStream=[IO.File]::Open([string]$j.ConfigurationPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if($configurationStream.Length -lt 1 -or $configurationStream.Length -gt 1048576){throw 'Configuration hors limites.'}
  $digest=[Security.Cryptography.SHA256]::Create()
  try{$actual=([BitConverter]::ToString($digest.ComputeHash($configurationStream))).Replace('-','')}finally{$digest.Dispose()}
  if($actual -ine [string]$j.ConfigurationSha256){throw 'Configuration modifiee.'}
  if([string]$j.Dc -ieq [string]$j.Domain -or -not ([string]$j.Dc).EndsWith('.'+[string]$j.Domain,[StringComparison]::OrdinalIgnoreCase)){throw 'DC exact absent.'}
  $adp=@{Server=[string]$j.Dc}
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
  if(-not $j.ModulePath){throw 'Module AD absent.'};Import-Module -Name ([string]$j.ModulePath) -ErrorAction Stop
  $root=Get-ADRootDSE -ErrorAction Stop @adp;$adDomain=Get-ADDomain -ErrorAction Stop @adp
  if([string]$root.dnsHostName -ine [string]$j.Dc -or [string]$adDomain.DNSRoot -ine [string]$j.Domain){throw 'Domaine ou DC different.'}
  if([string]$j.Operation -ceq 'reference'){
    $result.Reference=Read-Reference ([string]$j.ReferenceDn);$result.State='reference';$result.Message='Reference lue par DN et GUID.'
  }else{
    $before=Read-Target
    if([string]$j.Operation -ceq 'inspect'){$result.Snapshot=$before;$result.State='inspected';$result.Message='Attributs lus; aucune modification.'}
    else{
      if($env:PESTO_READONLY_SESSION -eq '1'){throw 'Session de consultation.'}
      $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
      try{$admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
      if(-not $admin){throw 'Elevation locale absente.'}
      Assert-Changes $before
      Assert-PestoGroupExclusions ([string]$j.Target.ComputerGuid) @($j.ExcludedGroupGuids) $adp ([string]$j.Target.Computer) ([string]$j.Target.Ou)
      # All potentially slow group/reference reads precede the last comparison of the target and Before values.
      $latest=Read-Target;Assert-Changes $latest
      $replace=@{};$clear=@()
      foreach($c in $j.Changes){if([string]$c.After){$replace[[string]$c.Attribute]=[string]$c.After}else{$clear+=@([string]$c.Attribute)}}
      $mutation=@{Identity=[Guid]$j.Target.ComputerGuid;ErrorAction='Stop'}
      if($replace.Count){$mutation.Replace=$replace};if($clear.Count){$mutation.Clear=[string[]]$clear}
      $result.MutationMayHaveStarted=$true
      Set-ADObject @mutation @adp
      $after=Read-Target;$result.Snapshot=$after
      foreach($c in $j.Changes){
        if([string]$after.Values.([string]$c.Attribute) -cne [string]$c.After){throw 'Valeur finale non confirmee.'}
        if([string]$c.Attribute -ceq 'managedBy' -and [string]$c.After -and [string]$after.ManagedByReferenceGuid -ine [string]$c.ReferenceGuid){throw 'GUID final managedBy different.'}
      }
      $result.State='verified';$result.Message='Attributs relus par GUID apres la modification.'
    }
  }
}catch{
  if($result.MutationMayHaveStarted){$result.State='uncertain';$result.Message='Modification possible; preuve finale incomplete. Aucun rejeu.'}
  else{$result.State='refused';$result.Message='Verification prealable refusee; aucune modification des attributs envoyee.'}
}finally{if($secure){$secure.Dispose()};if($configurationStream){$configurationStream.Dispose()}}
[Console]::Out.Write(($result|ConvertTo-Json -Compress -Depth 8))
if($result.State -eq 'refused'){exit 96};if($result.State -eq 'uncertain'){exit 97};exit 0
""";
}

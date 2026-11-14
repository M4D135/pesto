namespace Pesto.Engine.Live;

/// <summary>Single constant V1 GUID/LDAP rule shared by the reader and the final native mutation checks.</summary>
public static class GroupExclusionScript
{
    public const string Source = """
function Get-PestoPolicyParentDn([string]$dn){
  for($i=0;$i -lt $dn.Length;$i++){
    if($dn[$i] -eq '\'){$i++;continue}
    if($dn[$i] -eq ','){return $dn.Substring($i+1)}
  }
  throw 'Identité AD sans parent.'
}
function Get-PestoGroupExclusionObservation($computerGuid,$groupGuids,$adp){
  $id=[Guid]::Empty
  if(-not [Guid]::TryParse([string]$computerGuid,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identité AD de politique invalide.'}
  $groups=@($groupGuids)
  if($groups.Count -lt 1 -or $groups.Count -gt 200){throw 'Liste de groupes exclus invalide.'}
  $watch=[Diagnostics.Stopwatch]::StartNew()
  $pc=Get-ADComputer -Identity $id -Properties ObjectGUID,Name,DistinguishedName,userAccountControl -ErrorAction Stop @adp
  if(-not $pc -or [Guid]$pc.ObjectGUID -ne $id -or $null -eq $pc.userAccountControl){throw 'Identité ou rôle du poste non confirmé.'}
  $isDc=([long]$pc.userAccountControl -band 8192) -ne 0
  $checked=New-Object 'Collections.Generic.List[string]'
  $result=[ordered]@{computerGuid=$id.ToString('D');computerName=[string]$pc.Name;sourceOu=(Get-PestoPolicyParentDn ([string]$pc.DistinguishedName));checkedGroupGuids=@();complete=$false;domainController=$isDc;excludedGroupGuid=$null}
  if($isDc){return [pscustomobject]$result}
  $member=($id.ToByteArray()|ForEach-Object{'\'+$_.ToString('x2')}) -join ''
  foreach($raw in $groups){
    if($watch.ElapsedMilliseconds -gt 25000){throw 'Lecture des exclusions incomplète : délai atteint.'}
    $groupId=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$raw,[ref]$groupId) -or $groupId -eq [Guid]::Empty){throw 'GUID de groupe exclu invalide.'}
    if($checked.Contains($groupId.ToString('D'))){throw 'GUID de groupe exclu dupliqué.'}
    $group=Get-ADGroup -Identity $groupId -Properties ObjectGUID -ErrorAction Stop @adp
    if(-not $group -or [Guid]$group.ObjectGUID -ne $groupId){throw 'Identité du groupe exclu non confirmée.'}
    $filter='(&(objectGUID='+$member+')(memberOf:1.2.840.113556.1.4.1941:=<GUID='+$groupId.ToString('D')+'>))'
    $found=@(Get-ADComputer -LDAPFilter $filter -ResultSetSize 1 -ErrorAction Stop @adp)
    [void]$checked.Add($groupId.ToString('D'))
    if($found.Count){
      if($found.Count -ne 1 -or [Guid]$found[0].ObjectGUID -ne $id){throw 'Résultat d''appartenance incohérent.'}
      $result.excludedGroupGuid=$groupId.ToString('D');$result.checkedGroupGuids=@($checked.ToArray())
      return [pscustomobject]$result
    }
  }
  if($watch.ElapsedMilliseconds -gt 25000){throw 'Lecture des exclusions incomplète : délai atteint.'}
  $result.checkedGroupGuids=@($checked.ToArray());$result.complete=$true
  return [pscustomobject]$result
}
function Assert-PestoGroupExclusions($computerGuid,$groupGuids,$adp,$expectedName,$expectedOu){
  if(@($groupGuids).Count -eq 0){return}
  $checked=Get-PestoGroupExclusionObservation $computerGuid $groupGuids $adp
  if($checked.domainController -ne $false){throw 'Rôle inconnu ou contrôleur de domaine exclu.'}
  if($expectedName -and $checked.computerName -ine $expectedName){throw 'Nom du GUID modifié depuis le plan.'}
  if($expectedOu -and $checked.sourceOu -ine $expectedOu){throw 'OU du GUID modifiée depuis le plan.'}
  if($checked.excludedGroupGuid){throw 'Le poste appartient à un groupe exclu, directement ou par imbrication.'}
  if($checked.complete -ne $true -or @($checked.checkedGroupGuids).Count -ne @($groupGuids).Count){throw 'Appartenances AD non entièrement confirmées.'}
}

""";
}

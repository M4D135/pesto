$ErrorActionPreference='Stop'
. C:\PestoTest-run\lab-common.ps1
$adp=@{Server=$script:DC;Credential=$script:cred;ErrorAction='Stop'}
$fixtureOU='OU=RECREATE-RR,OU=Computers,'+$script:OU.ROOT
$results=[Collections.Generic.List[object]]::new()
$created=[Collections.Generic.List[Guid]]::new()
$group=$null
try {
 $cases=@(
  @{Kind='name';Candidate='V999004RRQA1991';Name='V999004RRQA1991';Sam='PestoCheck991$';DNS='pestocheck991.labo.local'},
  @{Kind='sAMAccountName';Candidate='V999004RRQA1992';Name='PestoCheckSAM992';Sam='V999004RRQA1992$';DNS='pestocheck992.labo.local'},
  @{Kind='dNSHostName';Candidate='V999004RRQA1993';Name='PestoCheckDNS993';Sam='PestoCheck993$';DNS='V999004RRQA1993.labo.local'})
 $source=Get-PestoWorkerCoreSource
 foreach($case in $cases){
  $pc=New-ADComputer -Name $case.Name -SamAccountName $case.Sam -DNSHostName $case.DNS -Path $fixtureOU -Enabled $false -PassThru @adp
  $created.Add($pc.ObjectGUID)
  $request=[pscustomobject]@{Name=$case.Candidate;Prefix=$script:PREFIXE;Domain=$script:DOMAINE;DC=$script:DC;Credential=$script:cred;ADModulePath=(Join-Path $BasePath 'ActiveDirectory.psd1');Generation=1}
  $check=Invoke-PestoNameCheckWorker $request $source
  Assert-Lab (-not $check.Free) ('Collision non détectée : '+$case.Kind)
  $results.Add([pscustomobject]@{Case=('3.4 collision '+$case.Kind);Passed=$true;Check=$check;FixtureGuid=$pc.ObjectGUID.ToString()})
 }
 $request.Name='V999004RRQA1994';$free=Invoke-PestoNameCheckWorker $request $source
 Assert-Lab $free.Free 'Nom témoin non libre'
 $after=@(Get-ADComputer -Filter 'Name -eq "V999004RRQA1994"' @adp)
 Assert-Lab ($after.Count -eq 0) 'Une vérification ne doit pas réserver un nom'
 $results.Add([pscustomobject]@{Case='3.4 libre daté sans réservation';Passed=$true;Check=$free})
 $group=New-ADGroup -Name 'Pesto (test)*\groupe' -SamAccountName 'PestoExclusion20261004' -GroupCategory Security -GroupScope Global -Path ('OU=Accounts,'+$script:OU.ROOT) -PassThru @adp
 $pc=Get-ADComputer -Identity '568e0d9b-8bf4-49c5-ab61-fbdb4cdfa81b' @adp
 Add-ADGroupMember -Identity $group -Members $pc @adp
 $plan=[pscustomobject]@{Nom_du_PC=$pc.Name;Nouveau_Nom='V999004BBQA1003';Objet_GUID=$pc.ObjectGUID.ToString();OU_Actuelle=($pc.DistinguishedName -replace '^CN=.*?,','');OU_Destination=$fixtureOU}
 $policy=[pscustomobject]@{Schema=1;ExcludedGroupGuids=@($group.ObjectGUID.ToString())}
 $refusal=''
 try {Assert-PestoOperationPolicy $plan $policy}catch{$refusal=$_.Exception.Message}
 Assert-Lab ($refusal -match 'groupe exclu') ('Exclusion non appliquée : '+$refusal)
 $results.Add([pscustomobject]@{Case='4.16 groupe exclu avec parentheses etoile antislash';Passed=$true;GroupDN=$group.DistinguishedName;GroupGuid=$group.ObjectGUID.ToString();Refusal=$refusal})

 $parent=$null
 try {
  $parent=New-ADGroup -Name 'Pesto (parent)*\groupe' -SamAccountName 'PestoParent20261004' -GroupCategory Security -GroupScope Global -Path ('OU=Accounts,'+$script:OU.ROOT) -PassThru @adp
  Add-ADGroupMember -Identity $parent -Members $group @adp
  $policy.ExcludedGroupGuids=@($parent.ObjectGUID.ToString())
  $refusal='';try{Assert-PestoOperationPolicy $plan $policy}catch{$refusal=$_.Exception.Message}
  Assert-Lab ($refusal -match 'groupe exclu') 'Exclusion indirecte non appliquée'
  $results.Add([pscustomobject]@{Case='4.16 appartenance imbriquee avec DN special';Passed=$true;GroupDN=$parent.DistinguishedName;Refusal=$refusal})
  Remove-ADGroupMember -Identity $group -Members $pc -Confirm:$false @adp
  Assert-PestoOperationPolicy $plan $policy
  $results.Add([pscustomobject]@{Case='4.16 non membre non bloque';Passed=$true})
 }finally{if($parent){Remove-ADGroup -Identity $parent.ObjectGUID -Confirm:$false @adp}}

 Save-LabResult 'lectures-ad-reelles' $results.ToArray()
 $results|Select Case,Passed|Format-Table -AutoSize
} finally {
 if($group){Remove-ADGroup -Identity $group.ObjectGUID -Confirm:$false @adp}
 foreach($guid in $created){Remove-ADComputer -Identity $guid -Confirm:$false @adp}
}

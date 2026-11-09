#requires -Version 5.1
param()
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent
foreach($f in @('Contracts','Configuration','ManagedPolicy','Policy','Enterprise')){. (Join-Path $root ('wad/Pesto-'+$f+'.ps1'))}
$script:passed=0;$script:failed=0
function Case($name,[scriptblock]$body){try{&$body;$script:passed++}catch{$script:failed++;Write-Host ('FAIL '+$name+': '+$_)}}
function Assert($v){if(-not$v){throw 'Assertion failed'}}
function Reject([scriptblock]$body){$caught=$false;try{&$body|Out-Null}catch{$caught=$true};Assert $caught}
function Refusal([scriptblock]$body){$message='';try{&$body|Out-Null}catch{$message=[string]$_.Exception.Message};return $message}
$s=[pscustomobject]@{Schema=1;Name='Paris';Required=@('Type','ServiceCode');Allowed=[pscustomobject]@{Type=@('P','V');SiteCode=@('AA')};Locked=[pscustomobject]@{ServiceCode='765'}}
$v=[pscustomobject]@{Type='P';SiteCode='AA';ServiceCode='765';TargetOU='OU=Paris,DC=example,DC=local'}
Case 'Valid scenario' {Assert-PestoScenarioValues $s $v}
Case 'Required field absent' {$c=$v.PSObject.Copy();$c.Type='';Reject {Assert-PestoScenarioValues $s $c}}
Case 'Required field with no allowed list is still required' {
    $r=[pscustomobject]@{Schema=1;Name='Lyon';Required=@('TargetOU');Allowed=[pscustomobject]@{Type=@('P','V')};Locked=[pscustomobject]@{}}
    $c=$v.PSObject.Copy();$c.TargetOU='';Reject {Assert-PestoScenarioValues $r $c}
    Assert-PestoScenarioValues $r $v
}
Case 'Disallowed type' {$c=$v.PSObject.Copy();$c.Type='S';Reject {Assert-PestoScenarioValues $s $c}}
Case 'Locked field changed' {$c=$v.PSObject.Copy();$c.ServiceCode='766';Reject {Assert-PestoScenarioValues $s $c}}
Case 'Unknown rule refused' {$c=$s.PSObject.Copy();$c|Add-Member Extra $true;Reject {ConvertTo-PestoScenario $c}}
Case 'Contradictory rule refused' {$c=$s.PSObject.Copy();$c.Locked=[pscustomobject]@{Type='S'};Reject {ConvertTo-PestoScenario $c}}
Case 'GPO scenario overrides local' {$p=ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1}) -LocalOnly;$m=Merge-PestoManagedPolicy $p ([pscustomobject]@{Values=[pscustomobject]@{Scenario=$s}});Assert ($m.Scenario.Name -eq 'Paris')}
Case 'Engine derives fields from actual name' {$p=[pscustomobject]@{Nouveau_Nom='V111301AA765001';OU_Destination=$v.TargetOU};Assert-PestoScenarioValues $s (Get-PestoPlanScenarioValues $p);$p.Nouveau_Nom='S111301AA765001';Reject {Assert-PestoScenarioValues $s (Get-PestoPlanScenarioValues $p)}}
Case 'Operation policy gate applies the scenario before any effect' {
    $ok=[pscustomobject]@{Nom_du_PC='PC001';Nouveau_Nom='P111301AA765001';OU_Actuelle=$v.TargetOU;OU_Destination=$v.TargetOU}
    $bad=[pscustomobject]@{Nom_du_PC='PC001';Nouveau_Nom='S111301AA765001';OU_Actuelle=$v.TargetOU;OU_Destination=$v.TargetOU}
    $policy=[pscustomobject]@{Schema=1;Scenario=$s}
    Assert-PestoOperationPolicy -Plan $ok -Policy $policy
    $message=Refusal {Assert-PestoOperationPolicy -Plan $bad -Policy $policy}
    Assert ($message -like 'Scenario Paris*valeur interdite pour Type')
}
Case 'Allowed list is case-sensitive' {$c=$v.PSObject.Copy();$c.Type='p';Reject {Assert-PestoScenarioValues $s $c}}
Case 'Locked value is case-sensitive' {
    $l=[pscustomobject]@{Schema=1;Name='Paris';Required=@('ServiceCode');Allowed=[pscustomobject]@{Type=@('P','V')};Locked=[pscustomobject]@{ServiceCode='INF'}}
    $c=$v.PSObject.Copy();$c.ServiceCode='inf';Reject {Assert-PestoScenarioValues $l $c}
    $o=$v.PSObject.Copy();$o.ServiceCode='INF';Assert-PestoScenarioValues $l $o
}
Case 'GPO ScenarioJson payloads the engine must refuse' {
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='X';Required=@();Allowed=[pscustomobject]@{Type=@('')};Locked=[pscustomobject]@{}})}
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='X';Required=@('Type');Allowed=[pscustomobject]@{Type=@([string][char]7)};Locked=[pscustomobject]@{}})}
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='X';Required=@('Type');Allowed=[pscustomobject]@{Type=@('P')};Locked=[pscustomobject]@{Type=@('P','V')}})}
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='X';Required=@('Type');Allowed=[pscustomobject]@{Type=@('P')};Locked=[pscustomobject]@{Type='V'}})}
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='X';Required=@('Unknown');Allowed=[pscustomobject]@{};Locked=[pscustomobject]@{}})}
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='';Required=@();Allowed=[pscustomobject]@{};Locked=[pscustomobject]@{}})}
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=2;Name='X';Required=@();Allowed=[pscustomobject]@{};Locked=[pscustomobject]@{}})}
    Reject {ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='X';Required=@('Type','Type','Type','Type','Type');Allowed=[pscustomobject]@{};Locked=[pscustomobject]@{}})}
    $wide=[pscustomobject]@{Schema=1;Name='X';Required=@();Allowed=[pscustomobject]@{Type=@(1..201|ForEach-Object{('V{0:D3}' -f $_)})};Locked=[pscustomobject]@{}}
    Reject {ConvertTo-PestoScenario $wide}
    $accepted=ConvertTo-PestoScenario ([pscustomobject]@{Schema=1;Name='Portables Paris';Required=@('Type','ServiceCode');Allowed=[pscustomobject]@{Type=@('P');SiteCode=@('PA')};Locked=[pscustomobject]@{ServiceCode='INF'}})
    Assert ($accepted.Name -eq 'Portables Paris' -and @($accepted.Required).Count -eq 2)
}
Case 'Managed scenario survives the policy round trip and still refuses' {
    $merged=Merge-PestoManagedPolicy (ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1}) -LocalOnly) ([pscustomobject]@{Values=[pscustomobject]@{Scenario=$s}})
    $plan=[pscustomobject]@{Nom_du_PC='PC001';Nouveau_Nom='S111301AA765001';OU_Actuelle=$v.TargetOU;OU_Destination=$v.TargetOU}
    $message=Refusal {Assert-PestoOperationPolicy -Plan $plan -Policy $merged}
    Assert ($message -like 'Scenario Paris*')
}
# Les cas d'approbation de campagne (signature X509/RSA, fournisseurs crypto de l'hote) vivent dans
# Run-CampaignApproval117Tests.ps1, declare Windows51 : sous pwsh hors Windows, GetRSAPrivateKey rend un
# RSAOpenSsl dont KeySize n'a qu'un accesseur en ecriture et la garde de l'approbation leve une erreur de
# liaison au lieu de refuser. Les garder ici ferait avorter toute la suite avant son resume.
Write-Host "ManagedExtensions: $script:passed passed, $script:failed failed (no Windows/AD/VM calls)."
if($script:failed){exit 1}

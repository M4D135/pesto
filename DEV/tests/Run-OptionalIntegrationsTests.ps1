#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$dev=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $dev 'integrations/Pesto.Optional.psm1') -Force
. (Join-Path $dev 'wad/Pesto-ManagedPolicy.ps1')
. (Join-Path $dev 'wad/Pesto-Contracts.ps1')
. (Join-Path $dev 'wad/Pesto-Policy.ps1')
. (Join-Path $dev 'wad/Pesto-Journal.ps1')
. (Join-Path $dev 'wad/Pesto-Enterprise.ps1')
. (Join-Path $dev 'wad/Pesto-Extensions.ps1')
$cases=[Collections.Generic.List[object]]::new()
function Assert-Optional {param($Value);if(-not $Value){throw 'Condition fausse'}}
function Reject-Optional {param([scriptblock]$Body);$failed=$false;try{& $Body|Out-Null}catch{$failed=$true};Assert-Optional $failed}
function Case-Optional {param($Name,[scriptblock]$Body);try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "PASS $Name"}catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "FAIL $Name : $($_.Exception.Message)"}}
Case-Optional 'Scénario requis autorisé et verrouillé' {
    $s=[pscustomobject]@{Schema=1;Name='Paris';Required=@('Type','ServiceCode');Allowed=[pscustomobject]@{Type=@('P','S')};Locked=[pscustomobject]@{SiteCode='PA'}}
    Assert-Optional (Test-PestoScenarioInput $s ([pscustomobject]@{Type='P';ServiceCode='INF';SiteCode='PA'})).Valid
    $r=Test-PestoScenarioInput $s ([pscustomobject]@{Type='V';SiteCode='LY'});Assert-Optional (-not $r.Valid -and $r.Errors.Count -eq 3)
}
Case-Optional 'Forme de scénario refusée par le formulaire comme par le moteur' {
    Reject-Optional {Test-PestoScenarioInput ([pscustomobject]@{Schema=1;Name='X';Required=@();Allowed=[pscustomobject]@{Type=@('')};Locked=[pscustomobject]@{}}) ([pscustomobject]@{Type=''})}
    Reject-Optional {Test-PestoScenarioInput ([pscustomobject]@{Schema=1;Name='X';Required=@();Allowed=[pscustomobject]@{Type=@([string][char]7)};Locked=[pscustomobject]@{}}) ([pscustomobject]@{Type='P'})}
    Reject-Optional {Test-PestoScenarioInput ([pscustomobject]@{Schema=1;Name='X';Required=@();Allowed=[pscustomobject]@{Type=@('P')};Locked=[pscustomobject]@{Type=@('P','V')}}) ([pscustomobject]@{Type='P'})}
    Reject-Optional {Test-PestoScenarioInput ([pscustomobject]@{Schema=1;Name='X';Required=@();Allowed=[pscustomobject]@{Type=@('P')};Locked=[pscustomobject]@{Type='V'}}) ([pscustomobject]@{Type='V'})}
    Reject-Optional {Test-PestoScenarioInput ([pscustomobject]@{Schema=1;Name='X';Required=@('Type','SiteCode','ServiceCode','TargetOU','Type');Allowed=[pscustomobject]@{};Locked=[pscustomobject]@{}}) ([pscustomobject]@{})}
}
Case-Optional 'Le validateur du formulaire ne dépasse jamais celui du moteur' {
    # Corpus systématique et non sept cas choisis : le formulaire est plus strict que le moteur sur les
    # valeurs, il ne doit jamais être plus permissif sur la forme. Une forme admise ici et refusée plus tard
    # par ConvertTo-PestoScenario fait échouer la lecture de ScenarioJson sur tous les postes visés, donc
    # après publication de la GPO. Les cartes Allowed/Locked sont croisées absentes, nulles, vides, peuplées,
    # hors champ et vectorielles : c'est précisément la classe de formes qui laissait 444 scénarios passer.
    $values=[pscustomobject]@{Type='P';SiteCode='PA';ServiceCode='INF';TargetOU='OU=Paris,DC=example,DC=local'}
    $absent=[object]
    $schemas=@(1,2,'1',$null)
    $noms=@('A','',123,('A'+[string][char]1+'B'),('N'*81),$null)
    $requi=@(@(),@('Type'),@('Type','SiteCode','ServiceCode','TargetOU'),@('Inconnu'),'Type',$null)
    $cartes=@($absent,$null,[pscustomobject]@{},[pscustomobject]@{Type=@('P')},[pscustomobject]@{Type=@('')},[pscustomobject]@{Type=@('P','V')},[pscustomobject]@{Inconnu=@('P')},'chaine')
    $verrous=@($absent,$null,[pscustomobject]@{},[pscustomobject]@{Type='P'},[pscustomobject]@{Type=@('P')},[pscustomobject]@{Inconnu='P'},'chaine')
    $examinees=0;$refusesParLeMoteur=0;$acceptesParLesDeux=0
    foreach($schema in $schemas){foreach($nom in $noms){foreach($required in $requi){foreach($allowed in $cartes){foreach($locked in $verrous){
        $examinees++
        $forme=[ordered]@{Schema=$schema;Name=$nom;Required=$required}
        if($allowed -isnot [type]){$forme['Allowed']=$allowed}
        if($locked -isnot [type]){$forme['Locked']=$locked}
        $scenario=New-Object psobject -Property $forme
        $engineRefused=$false;try{[void](ConvertTo-PestoScenario $scenario)}catch{$engineRefused=$true}
        $formRefused=$false;try{[void](Test-PestoScenarioInput $scenario $values)}catch{$formRefused=$true}
        Assert-Optional ($formRefused -or -not $engineRefused)
        if($engineRefused){$refusesParLeMoteur++}elseif(-not $formRefused){$acceptesParLesDeux++}
    }}}}}
    # Un corpus qui ne refuserait presque rien, ou n'en acceptait aucun, ne prouverait rien.
    Assert-Optional ($examinees -ge 8000 -and $refusesParLeMoteur -gt 7000 -and $acceptesParLesDeux -ge 30)
}
Case-Optional 'Attributs complémentaires : aperçu non exécutable fermé' {
    $p=New-PestoAttributeProposal -ObjectGuid '22222222-2222-4222-8222-222222222222' -Current ([pscustomobject]@{description='A'}) -Requested ([pscustomobject]@{description='B'})
    Assert-Optional (-not $p.Executable -and $p.Changes.Count -eq 1 -and $p.Changes[0].Before -ceq 'A')
    Reject-Optional {New-PestoAttributeProposal -ObjectGuid '22222222-2222-4222-8222-222222222222' -Current ([pscustomobject]@{}) -Requested ([pscustomobject]@{userAccountControl='8192'})}
}
Case-Optional 'Attributs complémentaires : aperçu accepté par la garde du moteur' {
    # L'aperçu remis à l'opérateur doit être exactement le diff que le moteur accepterait de lui-même : s'il
    # produisait des lignes d'une autre forme, ou un diff que Assert-PestoAttributeChanges refuserait, la
    # revue serait approuvée puis le plan refusé, donc le refus tomberait sur la cible après la remise.
    $current=[pscustomobject]@{description='A';location='';managedBy=''}
    $requested=[pscustomobject]@{description='B';location='Atelier'}
    $rows=@((New-PestoAttributeProposal -ObjectGuid '22222222-2222-4222-8222-222222222222' -Current $current -Requested $requested).Changes)
    Assert-Optional ($rows.Count -eq 2)
    foreach($row in $rows){
        $fields=@($row.PSObject.Properties.Name)
        Assert-Optional (@(Compare-Object -ReferenceObject @('Attribute','Before','After','ReferenceGuid') -DifferenceObject $fields).Count -eq 0)
    }
    Assert-Optional ($rows[1].Before -ceq '' -and $rows[1].After -ceq 'Atelier' -and $rows[1].ReferenceGuid -ceq '')
    $refus=''
    try{[void](Assert-PestoAttributeChanges $rows)}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq '')
    # La référence managedBy n'est pas lisible ici : seule l'étape du plan lit le répertoire. Le moteur doit
    # donc la refuser nommément, et l'aperçu doit porter le champ vide plutôt que de l'omettre.
    $managed=@((New-PestoAttributeProposal -ObjectGuid '22222222-2222-4222-8222-222222222222' -Current $current -Requested ([pscustomobject]@{managedBy='CN=Admin Reference,OU=Postes,OU=Organisme,DC=example,DC=local'})).Changes)
    Assert-Optional ($managed.Count -eq 1 -and $managed[0].PSObject.Properties['ReferenceGuid'] -ne $null)
    $refus=''
    try{[void](Assert-PestoAttributeChanges $managed)}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq 'Identite managedBy manquante.')
}
Case-Optional 'Attributs complémentaires : aperçu sans changement ou hors liste refusé' {
    # Un aperçu vide n'est pas une évaluation : remis tel quel, il ferait courir une opération sans effet
    # annoncé, ou pire masquerait une demande mal formulée.
    $refus=''
    try{[void](New-PestoAttributeProposal -ObjectGuid '22222222-2222-4222-8222-222222222222' -Current ([pscustomobject]@{description='A';location='';managedBy=''}) -Requested ([pscustomobject]@{description='A'}))}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq 'Un à trois changements attendus.')
    foreach($hors in @('userAccountControl','distinguishedName','member','userPassword','Description')){
        $refus=''
        try{[void](New-PestoAttributeProposal -ObjectGuid '22222222-2222-4222-8222-222222222222' -Current ([pscustomobject]@{}) -Requested ([pscustomobject]@{$hors='0'}))}catch{$refus=[string]$_.Exception.Message}
        Assert-Optional ($refus -clike 'Attribut non autorisé : *')
    }
    $refus=''
    try{[void](New-PestoAttributeProposal -ObjectGuid '22222222-2222-4222-8222-222222222222' -Current ([pscustomobject]@{}) -Requested ([pscustomobject]@{managedBy='Administrateur'}))}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq 'managedBy attend un DN validé séparément.')
    $refus=''
    try{[void](New-PestoAttributeProposal -ObjectGuid '00000000-0000-0000-0000-000000000000' -Current ([pscustomobject]@{}) -Requested ([pscustomobject]@{description='B'}))}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq 'Identité AD requise.')
}
Case-Optional 'Export audit fermé sans détails sensibles' {
    $r=[pscustomobject]@{OperationId='33333333-3333-4333-8333-333333333333';Mode='Rename';State='PendingRestart';ExitCode=3010;RestartRequired=$true;Password='FAUX';Message='secret=FAUX'}
    $a=New-PestoAuditExport $r
    Assert-Optional (($a|ConvertTo-Json) -notmatch 'FAUX|Password|Message')
}
Case-Optional 'Export audit du résultat attributs rendu par le moteur' {
    # Le résultat est construit par le constructeur réel du moteur, pas par un double : l'export de
    # l'intégrateur doit accepter le mode de l'extension attributs tel que le moteur le rend, et refuser
    # tout mode ou état qu'il n'émet pas.
    $result=New-PestoIntegrationResult -Mode 'Attributes' -State 'Verified' -ExitCode 0 -Message 'Attributs remis' -OperationId '44444444-4444-4444-8444-444444444444'
    $a=New-PestoAuditExport $result
    Assert-Optional ($a.Mode -ceq 'Attributes' -and $a.State -ceq 'Verified' -and $a.ExitCode -eq 0 -and $a.OperationId -ceq '44444444-4444-4444-8444-444444444444')
    Assert-Optional (($a|ConvertTo-Json) -notmatch 'Metadata|Plan|Message')
    $refus=''
    try{[void](New-PestoAuditExport (New-PestoIntegrationResult -Mode 'Attributs' -State 'Verified' -ExitCode 0 -OperationId '44444444-4444-4444-8444-444444444444'))}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq 'Mode ou état audit inconnu.')
    $refus=''
    try{[void](New-PestoAuditExport (New-PestoIntegrationResult -Mode 'Attributes' -State 'Termine' -ExitCode 0 -OperationId '44444444-4444-4444-8444-444444444444'))}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq 'Mode ou état audit inconnu.')
    $refus=''
    try{[void](New-PestoAuditExport (New-PestoIntegrationResult -Mode 'Attributes' -State 'Verified' -ExitCode 0 -OperationId ''))}catch{$refus=[string]$_.Exception.Message}
    Assert-Optional ($refus -ceq 'Identifiant opération requis.')
}
Case-Optional 'GPO seulement restrictive et sans mutation du config objet' {
    $local=[pscustomobject]@{IncidentMode=$false;UnattendedJoinEnabled=$true;UnattendedOperationsEnabled=$true;MaxBatch=100}
    $managed=[pscustomobject]@{Values=[pscustomobject]@{IncidentMode=1;DisableUnattendedJoin=1;DisableUnattendedOperations=1;MaxBatch=50}}
    $r=Merge-PestoManagedPolicy $local $managed
    Assert-Optional ($r.IncidentMode -and -not $r.UnattendedJoinEnabled -and -not $r.UnattendedOperationsEnabled -and $r.MaxBatch -eq 50)
    Assert-Optional (-not $local.IncidentMode -and $local.UnattendedJoinEnabled -and $local.MaxBatch -eq 100)
}
Case-Optional 'GPO désactivée ne force pas activation locale' {
    $local=[pscustomobject]@{IncidentMode=$true;UnattendedJoinEnabled=$false;UnattendedOperationsEnabled=$false;MaxBatch=20}
    $r=Merge-PestoManagedPolicy $local ([pscustomobject]@{Values=[pscustomobject]@{IncidentMode=0;DisableUnattendedJoin=0;DisableUnattendedOperations=0;MaxBatch=150}})
    Assert-Optional ($r.IncidentMode -and -not $r.UnattendedJoinEnabled -and -not $r.UnattendedOperationsEnabled -and $r.MaxBatch -eq 20)
}
Case-Optional 'GPO valeurs mal typées bloquent' {
    $local=[pscustomobject]@{IncidentMode=$false;UnattendedJoinEnabled=$false;UnattendedOperationsEnabled=$false;MaxBatch=20}
    Reject-Optional {Merge-PestoManagedPolicy $local ([pscustomobject]@{Values=[pscustomobject]@{MaxBatch=201}})}
    Reject-Optional {Merge-PestoManagedPolicy $local ([pscustomobject]@{Values=[pscustomobject]@{IncidentMode='true'}})}
}
Case-Optional 'Modèles GPO XML lisibles et références cohérentes' {
    $admx=[xml][IO.File]::ReadAllText((Join-Path $dev 'integrations/policies/Pesto.admx'))
    $adml=[xml][IO.File]::ReadAllText((Join-Path $dev 'integrations/policies/fr-FR/Pesto.adml'))
    $strings=@($adml.SelectNodes('//*[local-name()="string"]')|ForEach-Object{$_.id})
    foreach($node in $admx.SelectNodes('//*')){foreach($attribute in $node.Attributes){if($attribute.Value -match '^\$\(string\.(.+)\)$'){Assert-Optional ($Matches[1] -cin $strings)}}}
}
$report=[pscustomobject]@{Schema=1;Suite='OptionalIntegrations';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=([Environment]::OSVersion.Platform -eq 'Win32NT');ADExecuted=$false;WPFExecuted=$false;GPOApplied=$false;Scope='Contrats et modèles XML locaux ; aucune lecture secret ni écriture réseau/registre';Total=$cases.Count;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Cases=$cases.ToArray()}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
$report|Select-Object Suite,Total,Passed,Failed|Format-Table
if($report.Failed){exit 1}

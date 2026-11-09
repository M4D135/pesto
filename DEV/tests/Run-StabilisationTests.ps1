#requires -Version 5.1
# Tests de stabilisation v1.0 : logique pure avec doubles AD/Windows. Aucun appel réseau, aucune écriture AD.
# Exécutable sous Windows PowerShell 5.1 (cible) et PowerShell 7 (contrôle secondaire, à ne pas confondre).
param([string]$ReportPath)
Set-StrictMode -Off
$ErrorActionPreference='Stop'
$script:Wad=Join-Path (Split-Path -Parent $PSScriptRoot) 'wad'
$script:Results=[Collections.Generic.List[object]]::new()

function Import-PestoFunction {
    param([string]$File,[string[]]$Names)
    $tokens=$null;$errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Wad $File),[ref]$tokens,[ref]$errors)
    if(@($errors).Count){throw ('Erreur de syntaxe dans '+$File+' : '+$errors[0].Message)}
    $text=[Text.StringBuilder]::new()
    foreach($wanted in $Names){
        $found=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $wanted},$true))
        if($found.Count -lt 1){throw ('Fonction introuvable : '+$wanted)}
        [void]$text.AppendLine($found[0].Extent.Text)
    }
    return $text.ToString()
}
function Test-Case {
    param([string]$Name,[scriptblock]$Body)
    try{& $Body;$script:Results.Add([pscustomobject]@{Name=$Name;Result='PASS';Detail=''})}
    catch{$script:Results.Add([pscustomobject]@{Name=$Name;Result='FAIL';Detail=[string]$_.Exception.Message})}
}
function Assert-Equal { param($Expected,$Actual,[string]$Message) if($Expected -ne $Actual){throw ($Message+' | attendu='+[string]$Expected+' obtenu='+[string]$Actual)} }
function Assert-True { param($Condition,[string]$Message) if(-not $Condition){throw $Message} }

# Fonctions réelles du moteur, extraites par AST (aucun chargement de l'interface ni du module AD).
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts','New-PestoComputerName','Get-PestoOutcome'))))
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Directory.ps1' @('Split-PestoDistinguishedName','Get-PestoParentDN','Get-PestoDomainFromDN'))))
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Operations.ps1' @('Test-PestoDnsName','Test-PestoComputerName','Test-PestoGeneratedComputerName','Test-PestoOUPath','New-ActionResult','RenameComputer','MoveComputer','GoMoveOnly','Get-PestoNameSiteCode','Get-PestoSiteContainerDN','Get-PestoRenameMoveDecision'))))
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Safety.ps1' @('Complete-PestoIntervention'))))
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Policy.ps1' @('Assert-PestoOperationPolicy','Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt'))))
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Core.ps1' @('Get-SiteTag','Get-AvailableMachines','Get-CityCodeFromComputerName','Set-PestoQueueRowResult','Fail-PestoQueueCallback','Reset-PestoRowPreflight'))))

# Doubles : aucune commande Windows/AD réelle.
$script:Effects=[Collections.Generic.List[string]]::new()
$script:Written=[Collections.Generic.List[object]]::new()
$script:GuidPc='11111111-2222-3333-4444-555555555555'
$script:SrcOU='OU=Paris,OU=Postes,DC=lab,DC=test'
$script:DstOU='OU=Lyon,OU=Postes,DC=lab,DC=test'
$script:AdState=@{OU=$script:SrcOU;Protected=$true;RestoreFails=$false;MoveFails=$false}
$script:LastFilter=''
function Set-PestoEffect { param([string]$Name,$Value) $script:Effects.Add($Name+'='+[string]$Value) }
function Set-PestoInitialObservation { param($Observation) }
function Assert-PestoWorkerMayContinue { param([switch]$Mutation) }
function Set-PestoWorkerStage { param([string]$Name,[string]$Detail) }
function Write-Log { param($Message,$Level,$Err,$Context) }
function Get-ADParams { return @{} }
function Test-PestoOUInConfiguredScope { param([string]$OU) return $true }
function Get-PestoIdentityChangeReason { param($ExpectedGuid,$ActualGuid,$ExpectedOU,$ActualOU) return $null }
function Get-ADComputer {
    param($Identity,$Properties,$ErrorAction,$LDAPFilter,$ResultSetSize)
    if($LDAPFilter){$script:LastFilter=[string]$LDAPFilter;if($script:PolicyMatch){return [pscustomobject]@{ObjectGUID=[Guid]$script:GuidPc}};return}
    [pscustomobject]@{Name='P123456PAINF001';DistinguishedName=('CN=P123456PAINF001,'+$script:AdState.OU);ObjectGUID=[Guid]$script:GuidPc;ProtectedFromAccidentalDeletion=[bool]$script:AdState.Protected;userAccountControl=4096}
}
function Get-ADOrganizationalUnit { param($Identity,$Properties,$ErrorAction) [pscustomobject]@{ObjectGUID=[Guid]'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'} }
function Get-ADGroup { param($Identity,$ErrorAction) [pscustomobject]@{ObjectGUID=[Guid]$Identity;DistinguishedName='CN=Exclus (prod)*\\groupe,OU=Groupes,DC=lab,DC=test'} }
function Set-ADObject {
    param($Identity,[bool]$ProtectedFromAccidentalDeletion,$ErrorAction)
    if($ProtectedFromAccidentalDeletion -and $script:AdState.RestoreFails){throw 'Acces refuse (double de test).'}
    $script:AdState.Protected=$ProtectedFromAccidentalDeletion
}
function Get-ComputerOU { param($Identity) return [pscustomobject]@{OU=$script:AdState.OU} }
function Confirm-YesNo { return $true }
function Move-ADObject { param($Identity,$TargetPath,$ErrorAction) if($script:AdState.MoveFails){throw 'Refus du deplacement (double de test).'};$script:AdState.OU=[string]$TargetPath }
function Write-PestoIntervention { param($Receipt) $script:Written.Add($Receipt) }
function Read-PestoIntervention { param($Path) return $script:Parent }
function Test-PestoLedgerResume { param($Existing,$Plan,$ResumeId) return $true }
function Exit-PestoCoordination { param($Receipt,$Policy) }
function Add-PestoInterventionEvent { param($Receipt,$Stage,$State) }
function Protect-PestoLogText { param($Text) return [string]$Text }
function Get-PestoInterventionRoot { return [IO.Path]::GetTempPath() }
function ConvertTo-PestoPolicy { param($Policy) return $Policy }

function Reset-TestState {
    param([bool]$RestoreFails=$false,[bool]$MoveFails=$false,[string]$OU=$script:SrcOU)
    $script:Effects.Clear();$script:Written.Clear()
    $script:AdState=@{OU=$OU;Protected=$true;RestoreFails=$RestoreFails;MoveFails=$MoveFails}
    $script:GUI=$false;$script:SIM=$false;$script:CLEAR_PROTECTION=$true;$script:PREFIXE='123456'
    $script:ExpectedObjectGuid='';$script:ExpectedSourceOU='';$script:ExpectedTargetOUGuid='';$script:PestoReadOnly=$false
    $script:ActiveIntervention=[pscustomobject]@{Plan=[pscustomobject]@{Objet_GUID=$script:GuidPc}}
}
function New-TestChild {
    [pscustomobject]@{OperationId='22222222222222222222222222222222';Plan=[pscustomobject]@{Objet_GUID=$script:GuidPc;Renommer=$false;Deplacer=$true}
        Phase='Running';Entra='NotRequested';Rename='NotRequested';Move='Confirmed';Protection='NotChanged';ResultCode=0;ResultMessage='';UpdatedUtc=''
        ResumeFrom='33333333-3333-3333-3333-333333333333';TargetMachineId='';InitialProtection=$false;JoinEvidence=$null}
}
function New-TestParent {
    [pscustomobject]@{OperationId='33333333333333333333333333333333';Plan=[pscustomobject]@{Renommer=$true;Deplacer=$true};Phase='MoveReady';Move='Requested';UpdatedUtc='';LastStage=''}
}

Test-Case 'D1 deplacement reussi + protection non retablie : code 32 ET effet Move conserve' {
    Reset-TestState -RestoreFails $true
    $r=MoveComputer -ComputerName 'P123456PAINF001' -OU_Destination $script:DstOU
    Assert-Equal 32 $r.ExitCode 'Code attendu pour une protection non retablie'
    Assert-True ($script:Effects -contains 'Move=Confirmed') 'L''effet Move=Confirmed doit rester consigne malgre le code 32'
    Assert-True ($script:Effects.IndexOf('Move=Requested') -lt $script:Effects.IndexOf('Move=Confirmed')) 'Requested doit preceder Confirmed'
    Assert-True (-not ($script:Effects -contains 'Protection=Restored')) 'La protection ne doit pas etre annoncee retablie'
}
Test-Case 'D1 deplacement seul : une protection non retablie ne devient pas un echec du deplacement' {
    Reset-TestState -RestoreFails $true
    $r=GoMoveOnly -Nom_du_PC 'P123456PAINF001' -OU_Destination $script:DstOU -Confirm $false
    Assert-Equal 32 $r.ExitCode 'Code de protection conserve'
    Assert-True ($r.ExitMsg -like 'Protection NON RÉTABLIE.*') 'Le resultat doit identifier la protection en echec'
    Assert-True ($r.ExitMsg -notmatch 'Déplacement échoué') 'Ne pas contredire le deplacement observe'
    Assert-True ($script:Effects -contains 'Move=Confirmed') 'Deplacement confirme conserve'
}
Test-Case 'D1 deplacement reussi + protection retablie : code 30, Move confirme une seule fois' {
    Reset-TestState
    $r=MoveComputer -ComputerName 'P123456PAINF001' -OU_Destination $script:DstOU
    Assert-Equal 30 $r.ExitCode 'Code attendu'
    Assert-Equal 1 @($script:Effects|Where-Object{$_ -eq 'Move=Confirmed'}).Count 'Nombre de confirmations'
    Assert-True ($script:Effects -contains 'Protection=Restored') 'Protection retablie attendue'
}
Test-Case 'D1 erreur apres la demande de deplacement : 97 incertain, aucun effet Move confirme' {
    Reset-TestState -MoveFails $true
    $r=MoveComputer -ComputerName 'P123456PAINF001' -OU_Destination $script:DstOU
    # Choix conservateur du moteur : une erreur apres Move=Requested reste incertaine (effet differe possible).
    Assert-Equal 97 $r.ExitCode 'Code attendu apres une erreur posterieure a la demande'
    Assert-True ($script:Effects -contains 'Protection=Restored') 'La protection initiale doit etre retablie'
    Assert-True (-not ($script:Effects -contains 'Move=Confirmed')) 'Aucun Move=Confirmed attendu'
}
Test-Case 'D2 resultat TARDIF d''une reprise : l''intervention parente n''est pas resolue' {
    Reset-TestState
    $script:Parent=New-TestParent;$script:ActiveIntervention=New-TestChild
    $a=Complete-PestoIntervention -Action (New-ActionResult 30 'Deplacement confirme') -TimedOut $true
    Assert-Equal 97 $a.ExitCode 'Un retour tardif doit etre reclasse incertain'
    Assert-Equal 'Uncertain' $script:ActiveIntervention.Phase 'Phase de la reprise'
    Assert-Equal 'Requested' $script:Parent.Move 'Le parent ne doit pas etre modifie'
    Assert-Equal 'MoveReady' $script:Parent.Phase 'Le parent reste a verifier'
}
Test-Case 'D2 resultat a temps et verifie : le parent est mis a jour' {
    Reset-TestState
    $script:Parent=New-TestParent;$script:ActiveIntervention=New-TestChild
    $a=Complete-PestoIntervention -Action (New-ActionResult 30 'Deplacement confirme') -TimedOut $false
    Assert-Equal 30 $a.ExitCode 'Code conserve'
    Assert-Equal 'Confirmed' $script:Parent.Move 'Deplacement du parent'
    Assert-Equal 'PendingRestart' $script:Parent.Phase 'Phase du parent apres renommage'
}
Test-Case 'D3 nom actuel = nom demande : jamais un succes de renommage' {
    Reset-TestState
    $r=RenameComputer -Computername 'P123456PAINF001' -NewName 'p123456painf001'
    Assert-Equal 96 $r.ExitCode 'Code attendu (action non lancee)'
    Assert-True (@($script:Effects|Where-Object{$_ -like 'Rename=*' -or $_ -like 'Entra=*'}).Count -eq 0) 'Aucun effet Rename/Entra ne doit etre consigne'
}
Test-Case 'D4 Get-SiteTag : exact, motif unique, motif ambigu' {
    Reset-TestState
    $script:RuntimeTags=$null;$script:PREPRODSITE='765'
    $script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='pa'},[pscustomobject]@{Site='Ly*';Tag='LY'},[pscustomobject]@{Site='L*';Tag='LX'})}
    Assert-Equal 'PA' (Get-SiteTag 'Paris') 'Correspondance exacte'
    Assert-Equal 'LX' (Get-SiteTag 'Lille') 'Motif unique'
    Assert-True ($null -eq (Get-SiteTag 'Lyon')) 'Deux codes distincts : ambigu, aucun code devine'
}
Test-Case 'F7 groupes exclus : GUID binaires et DN alternatif, noms speciaux sans interpolation' {
    Reset-TestState -OU 'OU=Salle (A\, B)*,OU=Postes,DC=lab,DC=test'
    $policy=[pscustomobject]@{ExcludedNames=@();ExcludedOUs=@();ExcludedGroupGuids=@('99999999-9999-9999-9999-999999999999')}
    $plan=[pscustomobject]@{Nom_du_PC='P123456PAINF001';Nouveau_Nom='';OU_Actuelle='';OU_Destination='';Objet_GUID=$script:GuidPc}
    Assert-PestoOperationPolicy -Plan $plan -Policy $policy
    $expected='(&(objectGUID=\11\11\11\11\22\22\33\33\44\44\55\55\55\55\55\55)(memberOf:1.2.840.113556.1.4.1941:=<GUID=99999999-9999-9999-9999-999999999999>))'
    Assert-Equal $expected $script:LastFilter 'Filtre LDAP'
}

Test-Case 'F7 appartenance au groupe exclu : refus avant mutation' {
    $script:PolicyMatch=$true
    try {
        $policy=[pscustomobject]@{ExcludedNames=@();ExcludedOUs=@();ExcludedGroupGuids=@('99999999-9999-9999-9999-999999999999')}
        $plan=[pscustomobject]@{Nom_du_PC='P123456PAINF001';Nouveau_Nom='';OU_Actuelle='';OU_Destination='';Objet_GUID=$script:GuidPc}
        $refusal=''
        try{Assert-PestoOperationPolicy -Plan $plan -Policy $policy}catch{$refusal=$_.Exception.Message}
        Assert-True ($refusal -like '*groupe exclu*') 'Appartenance non bloquée'
    }finally{$script:PolicyMatch=$false}
}

# File de lots et formulaire : DataRow réelles, doubles pour l'interface.
$script:OK_CODES=@(10,20,30,33,77);$script:SIM=$false;$script:GUI=$false;$script:PreflightCache=$null;$script:INDOMAIN=$true
$script:Completed=0;$script:Stopped=0
function Stop-PestoQueueRemainingForSafety { param($State,$Reason) $script:Stopped++ }
function Complete-PestoQueueRun { $script:Completed++ }
function Get-PestoPlanSignature { param($Row) return 'sig' }
function Get-PestoRowPlanText { param($Row,$InDomain) return 'plan' }
function New-TestQueueTable {
    $t=[Data.DataTable]::new()
    foreach($c in 'Mode_Resultat','Lot_ID','Code','Message','Duree','Horodatage','Statut','Precontrole','Controle_Detail','Controle_Utc','Controle_Signature','Objet_GUID','TargetOUGuid','Plan'){[void]$t.Columns.Add($c,[string])}
    [void]$t.Columns.Add('Traiter',[bool])
    return ,$t
}
function New-TestQueueState {
    param([int]$Count,[int]$Index)
    $t=New-TestQueueTable;$items=@()
    for($i=0;$i -lt $Count;$i++){$r=$t.NewRow();$r.Statut='';$r.Code='';$t.Rows.Add($r);$items+=[pscustomobject]@{Row=$r}}
    $script:QueueRunState=[pscustomobject]@{RunId='run-test';Mode='Lot';Items=$items;Index=$Index;OkCount=0;KoCount=0;CancelCount=0}
    $script:Completed=0;$script:Stopped=0
    return $script:QueueRunState
}
Test-Case 'E file : un poste deja termine dans ce lot garde son resultat apres une erreur de pilotage' {
    $st=New-TestQueueState -Count 2 -Index 2
    Set-PestoQueueRowResult -Row $st.Items[0].Row -Code 30 -Message 'deplace' -Duration 1
    Set-PestoQueueRowResult -Row $st.Items[1].Row -Code 20 -Message 'renomme' -Duration 1
    Fail-PestoQueueCallback -Failure ([Management.Automation.ErrorRecord]::new([Exception]::new('fin de lot'),'t','NotSpecified',$null))
    Assert-Equal '20' ([string]$st.Items[1].Row.Code) 'Resultat confirme non ecrase'
    Assert-Equal 'OK' ([string]$st.Items[1].Row.Statut) 'Statut conserve'
    Assert-Equal 2 $st.OkCount 'Deux succes comptes'
    Assert-Equal 1 $script:Completed 'Lot clos une fois'
}
Test-Case 'E file : le poste en cours sans resultat passe en 98' {
    $st=New-TestQueueState -Count 2 -Index 2
    Set-PestoQueueRowResult -Row $st.Items[0].Row -Code 20 -Message 'renomme' -Duration 1
    $st.Items[1].Row.Statut='EN COURS'
    Fail-PestoQueueCallback -Failure ([Management.Automation.ErrorRecord]::new([Exception]::new('panne'),'t','NotSpecified',$null))
    Assert-Equal '98' ([string]$st.Items[1].Row.Code) 'Poste en cours en erreur technique'
    Assert-Equal '20' ([string]$st.Items[0].Row.Code) 'Poste precedent intact'
    Assert-Equal 1 $st.OkCount 'Un succes'
    Assert-Equal 1 $st.KoCount 'Un echec'
}
Test-Case 'E formulaire : nouvelle saisie efface aussi le GUID de l''OU de destination' {
    $t=New-TestQueueTable;$r=$t.NewRow();$t.Rows.Add($r)
    $r.Objet_GUID=$script:GuidPc;$r.TargetOUGuid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';$r.Controle_Signature='sig'
    Reset-PestoRowPreflight -Row $r
    Assert-Equal 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' ([string]$r.TargetOUGuid) 'Reprise : GUID du plan conserve'
    Assert-Equal $script:GuidPc ([string]$r.Objet_GUID) 'Reprise : identite conservee'
    Reset-PestoRowPreflight -Row $r -ClearIdentity
    Assert-Equal '' ([string]$r.Objet_GUID) 'Identite effacee'
    Assert-Equal '' ([string]$r.TargetOUGuid) 'GUID d''OU efface'
    Assert-Equal 'À CONTRÔLER' ([string]$r.Precontrole) 'Precontrole a refaire'
}
# Point 36 : site du nom ACTUEL lu par le parseur unique. Référence = implémentation RC23/1.0 recopiée telle quelle.
function Get-ReferenceNameSiteCode {
    param([AllowNull()][string]$Name)
    $n="$Name".Trim()
    if($n -match '^(?i:[PSV])[0-9]{6}([A-Za-z]{2})[A-Za-z0-9]{3}[0-9]{3}$'){return $Matches[1].ToUpperInvariant()}
    return $null
}
Test-Case '36 site du nom actuel : identique a la reference sur 6 000 noms (P, S, V, 000, casse, espaces, hors convention)' {
    $rand=[Random]::new(36);$alphabet='PSVXpsvx0123456789ABCLYZablyz- '.ToCharArray();$names=[Collections.Generic.List[string]]::new()
    foreach($n in @('P123456PAINF001','s123456lyinf999','V123456PAVIR042',' V123456PAVIR000 ','X123456PAINF001','P12345PAINF001','P123456P1INF001','P123456PAIN-001','V123456PAINF0001','',$null)){$names.Add($n)}
    for($i=0;$i -lt 3000;$i++){$len=$rand.Next(12,17);$names.Add(-join (1..$len|ForEach-Object{$alphabet[$rand.Next($alphabet.Length)]}))}
    for($i=0;$i -lt 3000;$i++){
        $c='PSVpsvX'[$rand.Next(7)]+('{0:D6}' -f $rand.Next(1000000))+'PALYplZ9'.Substring($rand.Next(7),2)+'INFvir0-'.Substring($rand.Next(6),3)+('{0:D3}' -f $rand.Next(1000))
        if($rand.Next(5) -eq 0){$c=' '+$c}
        $names.Add($c)
    }
    $diff=@(foreach($n in $names){$a=Get-ReferenceNameSiteCode $n;$b=Get-PestoNameSiteCode $n;if([string]$a -cne [string]$b){"'$n' ref=$a new=$b"}})
    Assert-Equal 0 $diff.Count ('Ecarts : '+(($diff|Select-Object -First 3) -join ' ; '))
}
Test-Case '36 machine virtuelle V : renommage meme site seul, nouveau site deplacement ; generation autorisee' {
    $script:PREFIXE='123456'
    $src='OU=Serveurs,OU=Paris,OU=Postes,DC=lab,DC=test';$dst='OU=Lyon,OU=Postes,DC=lab,DC=test'
    $same=Get-PestoRenameMoveDecision -Computer 'V123456PAVIR001' -NewName 'S123456PAVIR002' -CurrentOU $src -TargetOU $dst -Rename $true -Move $false
    Assert-True ($same.Valid -and -not $same.Move -and $same.SourceSite -eq 'PA') ('Meme site : '+$same.Error+$same.Reason)
    $other=Get-PestoRenameMoveDecision -Computer 'V123456PAVIR001' -NewName 'S123456LYVIR002' -CurrentOU $src -TargetOU $dst -Rename $true -Move $false
    Assert-True ($other.Valid -and $other.Move -and $other.SiteChanged) ('Nouveau site : '+$other.Error)
    Assert-Equal 'V' (ConvertTo-PestoNameParts 'V123456PAVIR001').Type 'Convention de generation : V accepte'
    Assert-True (Test-PestoGeneratedComputerName 'V123456PAVIR001') 'V est un nom genere valide'
    Assert-Equal 'Virtuel' (ConvertTo-PestoNameParts 'V123456PAVIR001' -CurrentName).Label 'Libelle en lecture'
    Assert-True ($null -eq (ConvertTo-PestoNameParts 'P123456PAINF000')) 'Numero 000 jamais genere'
    Assert-Equal 'V123456PAVIR001' (New-PestoComputerName -Type 'V' -Prefix '123456' -Site 'PA' -Service 'VIR' -Number 1) 'Generation VM'
}

function Get-ReferenceAvailableMachines {
    param([array]$computers,[string]$baseName,[string]$site,[string]$equipe)
    $base="$baseName".Trim().ToUpperInvariant();$tag="$site".Trim().ToUpperInvariant();$team="$equipe".Trim().ToUpperInvariant()
    if($base -notmatch '^[PSV][0-9]{6}$' -or $tag -notmatch '^[A-Z]{2}$' -or $team -notmatch '^[A-Z0-9]{3}$'){return ,@()}
    $prefix="${base}${tag}${team}";if($prefix.Length -ne 12){return ,@()}
    $used=New-Object 'System.Collections.Generic.HashSet[int]'
    foreach($c in @($computers)){$n="$($c.Name)".Trim();if($n.Length -ne 15 -or -not $n.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)){continue};$num=0;if([int]::TryParse($n.Substring(12,3),[ref]$num) -and $num -ge 1 -and $num -le 999){[void]$used.Add($num)}}
    $available=New-Object System.Collections.Generic.List[string]
    for($i=1;$i -le 999;$i++){if(-not $used.Contains($i)){[void]$available.Add("${prefix}$($i.ToString('D3'))")}}
    return ,@($available)
}
Test-Case '36 noms disponibles : generateur unique, resultat identique a la reference' {
    $pcs=@('P123456PAINF001','p123456painf003','P123456PAINF999','P123456PAINF000','P123456PAINFABC','S123456PAINF002','V123456PAINF004',' P123456PAINF005','P123456PAINF0060')|ForEach-Object{[pscustomobject]@{Name=$_}}
    $cases=@(@('P123456','PA','INF'),@('s123456','ly','vir'),@('P123456','pa','in-'),@('V123456','PA','INF'),@('P12345','PA','INF'),@('P123456','P1','INF'),@('P123456','PA','INFO'),@(' P123456 ',' pa ',' inf '),@('','',''))
    foreach($c in $cases){
        $a=Get-ReferenceAvailableMachines -computers $pcs -baseName $c[0] -site $c[1] -equipe $c[2]
        $b=Get-AvailableMachines -computers $pcs -baseName $c[0] -site $c[1] -equipe $c[2]
        Assert-Equal $a.Count $b.Count ('Taille, cas '+($c -join '/'))
        Assert-Equal ($a -join ',') ($b -join ',') ('Cas '+($c -join '/'))
    }
    $r=Get-AvailableMachines -computers $pcs -baseName 'P123456' -site 'PA' -equipe 'INF'
    Assert-Equal 'P123456PAINF002' $r[0] 'Premier libre'
    Assert-Equal 995 $r.Count '001, 003, 999 et 005 pris (insensible a la casse et aux espaces), 000 ignore'
}

Test-Case '36 code ville du nom : seulement un nom conforme (P, S, V), jamais devine par position' {
    Assert-Equal 'pa' (Get-CityCodeFromComputerName 'P123456PAINF001') 'Portable'
    Assert-Equal 'ly' (Get-CityCodeFromComputerName ' s123456LYinf002 ') 'Fixe, casse et espaces'
    Assert-Equal 'pa' (Get-CityCodeFromComputerName 'V123456PAVIR000') 'Machine virtuelle'
    foreach($n in @('LAPTOP-ABCDEF','DESKTOP-285EKHU','X123456PAINF001','P123456PAINF01','',$null)){Assert-True ($null -eq (Get-CityCodeFromComputerName $n)) ('Aucun code pour '+[string]$n)}
}

# Point 79 : contraste élevé Windows en mode « Suivre Windows ».
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Appearance.ps1' @('Test-PestoAppearanceSid','Get-PestoSystemContrastColors','ConvertTo-PestoHighContrastPalette','Resolve-PestoTheme'))))
$themesAst=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Wad 'Pesto-Core.ps1'),[ref]$null,[ref]$null).FindAll({param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$script:Themes'},$true)|Select-Object -First 1
$script:RealThemes=Invoke-Expression $themesAst.Right.Extent.Text
$script:HcSystem=@{Window='#000000';WindowText='#FFFFFF';Highlight='#1AEBFF';HighlightText='#000000';ButtonFace='#000000';ButtonText='#FFFFFF';HotTrack='#FFFF00'}
Test-Case '79 contraste eleve : chaque couleur reelle des themes clair et sombre a un role systeme' {
    foreach($name in 'Light','Dark'){
        $p=ConvertTo-PestoHighContrastPalette -Keys @($script:RealThemes[$name].Keys) -System $script:HcSystem
        Assert-Equal $script:RealThemes[$name].Count $p.Count ('Palette complete depuis '+$name)
    }
    $p=ConvertTo-PestoHighContrastPalette -Keys @($script:RealThemes['Light'].Keys) -System $script:HcSystem
    Assert-Equal '#000000' $p.BgWindow 'Fond = fenetre'
    Assert-Equal '#FFFFFF' $p.FgText 'Texte = texte de fenetre'
    Assert-True ($p.AddBg -eq '#1AEBFF' -and $p.RunFg -eq '#000000') 'Bouton principal : texte de selection sur selection'
    Assert-True ($p.RowHoverBg -eq $p.BgWindow) 'Survol : texte de fenetre reste lisible'
    $threw=$false;try{[void](ConvertTo-PestoHighContrastPalette -Keys @('Inconnue') -System $script:HcSystem)}catch{$threw=$true}
    Assert-True $threw 'Couleur sans role refusee'
    $threw=$false;try{[void](ConvertTo-PestoHighContrastPalette -Keys @('FgText') -System @{})}catch{$threw=$true}
    Assert-True $threw 'Couleur systeme absente refusee'
}
Test-Case '79 contraste eleve : seulement en mode Suivre Windows, repli au moindre doute' {
    $script:Themes=@{Light=$script:RealThemes.Light;Dark=$script:RealThemes.Dark};$script:AppearanceOwnerSid=''
    function Get-PestoSystemContrastColors { return $script:HcSystem }
    Assert-Equal 'HighContrast' (Resolve-PestoTheme 'System') 'Systeme en contraste eleve'
    Assert-Equal $script:RealThemes.Light.Count $script:Themes['HighContrast'].Count 'Palette installee'
    Assert-Equal 'Dark' (Resolve-PestoTheme 'Dark') 'Choix explicite sombre respecte'
    Assert-Equal 'Light' (Resolve-PestoTheme 'Light') 'Choix explicite clair respecte'
    function Get-PestoSystemContrastColors { return @{Window='#000000'} }
    Assert-Equal 'Light' (Resolve-PestoTheme 'System') 'Couleurs systeme incompletes : thème habituel'
    function Get-PestoSystemContrastColors { return $null }
    Assert-Equal 'Light' (Resolve-PestoTheme 'System') 'Sans contraste eleve : comportement inchange'
}
Test-Case '79 aucun blanc en dur sur le fond d''action' {
    $xaml=[IO.File]::ReadAllText((Join-Path $script:Wad 'Pesto-Shell.xaml'))
    $lines=$xaml -split "`n"
    $hard=@($lines|Select-Object -Skip 4|Where-Object{$_ -match '(Foreground|Stroke|Fill)="#'})
    Assert-Equal 0 $hard.Count 'Couleur de texte en dur hors ressources'
    Assert-True (-not (Select-String -Path (Join-Path $script:Wad 'Pesto-Core.ps1') -Pattern 'Brushes\]::White' -Quiet)) 'Brushes White en dur'
}

# Point 01 : classification commune des échecs du Planificateur (COM).
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Safety.ps1' @('Get-PestoNativeFailureCode'))))
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Operations.ps1' @('ConvertTo-PestoTaskFailureCode'))))
function New-ComError { param([int]$HResult) $hr=$HResult; return [Management.Automation.ErrorRecord]::new([Management.Automation.MethodInvocationException]::new('appel COM',[Runtime.InteropServices.COMException]::new('com',$hr)),'t','NotSpecified',$null) }
Test-Case '01 Planificateur : seul un HRESULT Win32 donne un code Windows ; Run sans refus certain = indetermine' {
    Assert-Equal 5 (ConvertTo-PestoTaskFailureCode (New-ComError 0x80070005) $false) 'Acces refuse Win32'
    Assert-Equal 1722 (ConvertTo-PestoTaskFailureCode (New-ComError 0x800706BA) $false) 'RPC indisponible'
    Assert-Equal 999 (ConvertTo-PestoTaskFailureCode (New-ComError 0x80041318) $false) 'SCHED_E_INVALID_TASK : pas de faux 4888'
    Assert-Equal 1460 (ConvertTo-PestoTaskFailureCode (New-ComError 0x80040005) $true) 'Apres Run, HRESULT non Win32 aux bits bas 5 : indetermine, pas refus certain'
    Assert-Equal 5 (ConvertTo-PestoTaskFailureCode (New-ComError 0x80070005) $true) 'Apres Run, refus certain conserve'
    Assert-Equal 1460 (ConvertTo-PestoTaskFailureCode (New-ComError 0x800706BA) $true) 'Apres Run, RPC perdu : indetermine'
    Assert-Equal 999 (ConvertTo-PestoTaskFailureCode ([Management.Automation.ErrorRecord]::new([Exception]::new('x'),'t','NotSpecified',$null)) $false) 'Exception sans code'
}

Test-Case 'DEBLOQUER_TOUT : entrees du pack DEV et PROD reconnues, fichiers voisins ignores' {
    # Pas d'enumeration du dossier reel : un fichier pose par l'operateur (check.json) n'est pas du pack.
    # La couverture complete du contrat (distribution_files) est verifiee par test_distribution.py.
    $cmd=[IO.File]::ReadAllText((Join-Path $script:Wad 'support\DEBLOQUER_TOUT.cmd'))
    $line=@($cmd -split "`r?`n"|Where-Object{$_ -match '^\s*\$isPestoEntry='})
    Assert-Equal 1 $line.Count 'Filtre de premier niveau present une fois'
    Invoke-Expression $line[0]
    foreach($n in @('wad','tools','tests','docs','changes','.github')){Assert-True (& $isPestoEntry $n $true) ('Dossier du pack non reconnu : '+$n)}
    foreach($n in @('Pesto.exe','README.md','LIRE_MOI.txt','CHANGELOG.md','.gitignore','Pesto.cmd','Pesto_COMPTE_AD.cmd','DEMO.cmd','DEMO_DOMAINE.cmd','APERCU_LOGIN.cmd','ETAT_RENOMMAGE.cmd','TESTER.cmd','TEST_RC23.cmd','VERIFIER_PACK.cmd','VERIFIER_UAC.cmd','FABRIQUER_PACKS.cmd','pesto.EXE')){
        Assert-True (& $isPestoEntry $n $false) ('Element du pack non reconnu : '+$n)
    }
    foreach($n in @('check.json','facture.pdf','setup.exe','install.cmd','autre.ps1','Documents')){
        Assert-True (-not (& $isPestoEntry $n ($n -eq 'Documents'))) ('Element voisin accepte : '+$n)
    }
}

# Vu sous Windows PowerShell 5.1.26100.6584 (recette 2.1) : @() sur une List[object] créée par New-Object
# lève « Argument types do not match » ; le mode démo s'arrêtait à l'initialisation.
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Core.ps1' @('New-DemoComputers'))))
Test-Case 'Mode demo : jeu fictif construit, aucune liste generique par New-Object dans wad' {
    $oldPrefix=$script:PREFIXE
    try{
        $script:PREFIXE='PE'
        $demo=New-DemoComputers  # même usage que le démarrage : $script:Computers = New-DemoComputers
        Assert-True ($demo -is [array]) 'Tableau attendu'
        Assert-True ($demo.Count -ge 36) ('Jeu de demo trop court : '+$demo.Count)
        Assert-True ($demo[0].DistinguishedName -like 'CN=*,OU=Demo,DC=demo,DC=local') 'DN fictif'
    }finally{$script:PREFIXE=$oldPrefix}
    $hits=@(Select-String -Path (Join-Path $script:Wad '*.ps1') -Pattern 'New-Object\s+(-TypeName\s+)?(System\.)?(Collections\.Generic\.)?(List|HashSet|Dictionary|Queue|Stack|SortedDictionary)\[')
    Assert-Equal 0 $hits.Count ('Collections generiques par New-Object : '+(($hits|ForEach-Object{$_.Filename+':'+$_.LineNumber}) -join ', '))
}

# O7 : sonde de VERIFIER_UAC.cmd. Fonctions réelles de Pesto-Startup.ps1 ; journal, reçu, contrôle de chemin et
# fenêtre doublés. La vraie UAC, le relais élevé et Pesto.exe ne tournent que sous Windows (VERIFIER_UAC.cmd).
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Startup.ps1' @('ConvertTo-PestoStartupArgument','New-PestoStartupArgumentLine','Resolve-PestoStartupUacProbe','Complete-PestoStartupUacProbe'))))
$script:O7Files=@{};$script:O7Log=[Collections.Generic.List[string]]::new();$script:O7Shown=[Collections.Generic.List[object]]::new();$script:O7WriteFails=$false
function Assert-PestoStartupLocalPath { param([string]$Path) if($script:O7WriteFails){throw 'Lien ou jonction refuse'} }
function Write-PestoStartupNewFile { param([string]$Path,[byte[]]$Bytes) if($script:O7Files.ContainsKey($Path)){throw 'CreateNew : fichier existant'};$script:O7Files[$Path]=[Text.Encoding]::UTF8.GetString($Bytes) }
function Write-PestoStartupLog { param([string]$Root,[string]$Message) $script:O7Log.Add($Message) }
function Show-PestoStartupProbeMessage { param([string]$Text,[bool]$Success) $script:O7Shown.Add([pscustomobject]@{Text=$Text;Success=$Success}) }
function Test-O7Throws { param([scriptblock]$Body) try{[void](& $Body)}catch{return $true};return $false }
Test-Case 'O7 sonde UAC : jeton strict ; variable lue avant l''UAC seulement ; jamais ignoree si invalide' {
    $ok='0123456789abcdef0123456789abcdef'
    Assert-Equal '' (Resolve-PestoStartupUacProbe -Parameter '' -ParameterBound $false -Environment '' -ElevatedLaunch $false) 'Sans sonde : lancement normal'
    Assert-Equal $ok (Resolve-PestoStartupUacProbe -Parameter '' -ParameterBound $false -Environment $ok -ElevatedLaunch $false) 'Variable heritee de Pesto.exe'
    Assert-Equal '' (Resolve-PestoStartupUacProbe -Parameter '' -ParameterBound $false -Environment $ok -ElevatedLaunch $true) 'Relais eleve : variable jamais relue'
    Assert-Equal $ok (Resolve-PestoStartupUacProbe -Parameter $ok -ParameterBound $true -Environment '' -ElevatedLaunch $true) 'Relais eleve : parametre explicite'
    foreach($bad in @($ok.ToUpperInvariant(),($ok+"`n"),'..\..\Windows\x','0123456789abcdef0123456789abcde',($ok+'0'),'1',(' '+$ok))){
        Assert-True (Test-O7Throws {Resolve-PestoStartupUacProbe -Parameter '' -ParameterBound $false -Environment $bad -ElevatedLaunch $false}) ('Sonde invalide acceptee : ['+$bad+']')
    }
    Assert-True (Test-O7Throws {Resolve-PestoStartupUacProbe -Parameter '' -ParameterBound $true -Environment $ok -ElevatedLaunch $false}) 'Parametre -UacProbe vide accepte'
}
Test-Case 'O7 sonde UAC : jeton transmis au relais eleve, rien sans sonde, jeton forge refuse' {
    $ok='0123456789abcdef0123456789abcdef'
    $line=New-PestoStartupArgumentLine -EntryPath 'C:\Pesto d''atelier [1]\wad\Pesto-Startup.ps1' -OriginLocalAppData 'C:\Users\T\AppData\Local' -UacProbe $ok
    Assert-True ($line.EndsWith('-UacProbe "'+$ok+'"')) $line
    Assert-True ($line.Contains('-ElevatedLaunch') -and $line.Contains('-File "C:\Pesto d''atelier [1]\wad\Pesto-Startup.ps1"')) $line
    $plain=New-PestoStartupArgumentLine -EntryPath 'C:\Pesto\wad\Pesto-Startup.ps1' -OriginLocalAppData 'C:\Users\T\AppData\Local'
    Assert-True (-not $plain.Contains('UacProbe')) 'Lancement normal sans sonde'
    Assert-True (Test-O7Throws {New-PestoStartupArgumentLine -EntryPath 'C:\Pesto\wad\Pesto-Startup.ps1' -UacProbe 'x" -Command y'}) 'Sonde forgee transmise'
}
Test-Case 'O7 sonde UAC : seul le relais eleve administrateur conclut UAC_OK ; recu jamais remplace' {
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('pesto-o7-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    try{
        $ok='0123456789abcdef0123456789abcdef'
        Assert-Equal 0 (Complete-PestoStartupUacProbe -Root $temp -Probe $ok -Route 'Run' -IsAdministrator $true -ElevatedLaunch $true -Account 'LAB\admin') 'Relais eleve administrateur'
        $path=Join-Path $temp ('wad\logs\Pesto-sonde-uac-'+$ok+'.txt')
        Assert-True ($script:O7Files.ContainsKey($path)) ('Recu hors du chemin fixe : '+(@($script:O7Files.Keys) -join ', '))
        $first=$script:O7Files[$path]
        foreach($k in @("Sonde=$ok",'Resultat=UAC_OK','Admin=True','RelaisEleve=True','Compte=LAB\admin','Moteur=NON_CHARGE','RepriseEtat=NON_FAITE','AD=NON_CONTACTE')){
            Assert-True ($first -match ('(?m)^'+[regex]::Escape($k)+'\r?$')) ('Champ absent : '+$k)
        }
        Assert-True ($script:O7Shown[$script:O7Shown.Count-1].Success) 'Fenetre de succes attendue'
        $shownText=$script:O7Shown[$script:O7Shown.Count-1].Text
        Assert-True (-not $shownText.Contains('`r`n')) 'Echappement `r`n affiche litteralement'
        Assert-True ($shownText.Contains("`r`nJournal : ")) 'Recu et journal non separes par un vrai saut de ligne'
        Assert-Equal 3 (Complete-PestoStartupUacProbe -Root $temp -Probe $ok -Route 'Run' -IsAdministrator $true -ElevatedLaunch $true -Account 'LAB\admin') 'Meme jeton : recu existant, code 3'
        Assert-Equal $first $script:O7Files[$path] 'Recu existant modifie'
        $cases=@(
            @{Probe='fedcba9876543210fedcba9876543210';Route='Run';Admin=$true;Elevated=$false;Result='DEJA_ADMIN_SANS_UAC'},
            @{Probe='00000000000000000000000000000000';Route='Refuse';Admin=$false;Elevated=$true;Result='RELAIS_SANS_ADMIN'})
        foreach($c in $cases){
            Assert-Equal 2 (Complete-PestoStartupUacProbe -Root $temp -Probe $c.Probe -Route $c.Route -IsAdministrator $c.Admin -ElevatedLaunch $c.Elevated -Account 'LAB\x') ('Code '+$c.Result)
            Assert-True ($script:O7Files[(Join-Path $temp ('wad\logs\Pesto-sonde-uac-'+$c.Probe+'.txt'))] -match ('(?m)^Resultat='+$c.Result+'\r?$')) $c.Result
            Assert-True (-not $script:O7Shown[$script:O7Shown.Count-1].Success) ('Fenetre d''erreur attendue : '+$c.Result)
        }
        $script:O7WriteFails=$true
        try{Assert-Equal 3 (Complete-PestoStartupUacProbe -Root $temp -Probe '11111111111111111111111111111111' -Route 'Run' -IsAdministrator $true -ElevatedLaunch $true -Account 'LAB\admin') 'Lien refuse : code 3'}
        finally{$script:O7WriteFails=$false}
        Assert-True (Test-O7Throws {Complete-PestoStartupUacProbe -Root $temp -Probe '..\..\x' -Route 'Run' -IsAdministrator $true -ElevatedLaunch $true -Account 'x'}) 'Jeton forge accepte'
        Assert-True (@($script:O7Log|Where-Object{$_ -like 'Sonde UAC *Moteur non charge*'}).Count -ge 4) 'Journal de demarrage'
    }finally{[IO.Directory]::Delete($temp,$true)}
}

Test-Case 'Journal de demarrage : LOCALAPPDATA et TEMP absents (SYSTEM, service) ne levent jamais' {
    # Fonction reelle, chargee dans la portee du cas seulement (le double O7 reste en place ailleurs).
    . ([scriptblock]::Create((Import-PestoFunction 'Pesto-Startup.ps1' @('Write-PestoStartupLog'))))
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('pesto-startlog-'+[Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temp)
    $oldLocal=$env:LOCALAPPDATA;$oldTemp=$env:TEMP;$oldPath=$script:PestoStartupLogPath
    try{
        $env:LOCALAPPDATA=$null;$env:TEMP=$null;$script:PestoStartupLogPath=$null
        Write-PestoStartupLog -Root $temp -Message 'essai sans variables'
        Assert-True ($script:PestoStartupLogPath -and $script:PestoStartupLogPath.StartsWith($temp)) ('Racine non utilisee : '+[string]$script:PestoStartupLogPath)
        Assert-True ((Get-Content -LiteralPath $script:PestoStartupLogPath -Raw) -match 'essai sans variables') 'Ligne absente'
    }finally{$env:LOCALAPPDATA=$oldLocal;$env:TEMP=$oldTemp;$script:PestoStartupLogPath=$oldPath;[IO.Directory]::Delete($temp,$true)}
}
Test-Case 'Socle .NET : 4.7 et 4.7.1 refuses, 4.7.2 et plus acceptes' {
    . ([scriptblock]::Create((Import-PestoFunction 'Pesto-Integrity.ps1' @('Get-PestoDotNetFloorStatus'))))
    foreach($c in @(@{R=394802;S=$false},@{R=460798;S=$false},@{R=461308;S=$false},@{R=461808;S=$true},@{R=528040;S=$true},@{R=533320;S=$true})){
        $s=Get-PestoDotNetFloorStatus -Release $c.R
        Assert-True ($s.Known) ('Release non reconnue : '+$c.R)
        Assert-Equal $c.S $s.Supported ('Socle .NET pour '+$c.R+' ('+$s.Version+')')
    }
    Assert-True (-not (Get-PestoDotNetFloorStatus -Release $null).Known) 'Release absente : inconnue'
}

. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Core.ps1' @('ConvertTo-PestoRdnValue'))))
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Directory.ps1' @('Get-PestoSiteServiceCodes','Get-PestoNameInventoryIndex'))))
Test-Case 'Services du site : OU du site ou code site du nom, saisie libre conservee ailleurs' {
    Reset-TestState
    $script:PREFIXE='123456';$script:RuntimeTags=$null;$script:PREPRODSITE='765'
    $script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='PA'},[pscustomobject]@{Site='Lyon';Tag='LY'})}
    $org='OU=Postes,DC=lab,DC=test'
    $pcs=@(
        [pscustomobject]@{Name='P123456PAINF001';DistinguishedName='CN=P123456PAINF001,OU=Paris,OU=Postes,DC=lab,DC=test'},
        [pscustomobject]@{Name='S123456PARH0002';DistinguishedName='CN=S123456PARH0002,OU=Etage 2,OU=Paris,OU=Postes,DC=lab,DC=test'},
        [pscustomobject]@{Name='V123456PAADM003';DistinguishedName='CN=V123456PAADM003,OU=Transit,DC=lab,DC=test'},
        [pscustomobject]@{Name='P123456LYCPT001';DistinguishedName='CN=P123456LYCPT001,OU=Paris,OU=Postes,DC=lab,DC=test'},
        [pscustomobject]@{Name='P123456LYDIR001';DistinguishedName='CN=P123456LYDIR001,OU=Lyon,OU=Postes,DC=lab,DC=test'},
        [pscustomobject]@{Name='P999999PAXXX001';DistinguishedName='CN=P999999PAXXX001,OU=Paris,OU=Postes,DC=lab,DC=test'},
        [pscustomobject]@{Name='PC-SALLE-12';DistinguishedName='CN=PC-SALLE-12,OU=Paris,OU=Postes,DC=lab,DC=test'},
        [pscustomobject]@{Name='P123456PAINF004'},
        $null
    )
    # OU Paris (sous-OU comprise) : INF, RH0, CPT ; code site PA hors OU : ADM ; autre préfixe, hors convention et autre site exclus.
    Assert-Equal 'ADM,CPT,INF,RH0' ((Get-PestoSiteServiceCodes -OrganismeOU $org -Site 'Paris' -Computers $pcs) -join ',') 'Services de Paris'
    Assert-Equal 'CPT,DIR' ((Get-PestoSiteServiceCodes -OrganismeOU $org -Site 'Lyon' -Computers $pcs) -join ',') 'Services de Lyon (code site LY)'
    Assert-Equal 'ADM,INF,RH0' ((Get-PestoSiteServiceCodes -OrganismeOU '' -Site 'Paris' -Computers $pcs) -join ',') 'Sans OU d organisme : code site seul'
    Assert-Equal 0 @(Get-PestoSiteServiceCodes -OrganismeOU $org -Site '' -Computers $pcs).Count 'Sans site : aucune liste'
    Assert-Equal 0 @(Get-PestoSiteServiceCodes -OrganismeOU $org -Site 'Marseille' -Computers @()).Count 'Cache vide : liste vide, saisie libre'
}

# Identité du session : l'avertissement qui doit precéder un appel AD voue au refus d'ADWS.
. ([scriptblock]::Create((Import-PestoFunction 'Pesto-Authentication.ps1' @('Get-PestoDomainIdentityWarning','Add-PestoDomainIdentityCause'))))
Test-Case 'Identite domaine : rien a signaler quand l identite porte deja le domaine' {
    Assert-Equal '' (Get-PestoDomainIdentityWarning -Identity ([pscustomobject]@{IsDomainUser=$true})) 'Compte du domaine'
    Assert-Equal '' (Get-PestoDomainIdentityWarning -Identity ([pscustomobject]@{IsDomainUser=$false}) -HasExplicitCredential) 'Credential explicite : la cmdlet porte sa propre identite'
    Assert-Equal '' (Get-PestoDomainIdentityWarning -Identity ([pscustomobject]@{IsDomainUser=$false}) -InDomain $false) 'Hors domaine : la route explicite le dit deja'
}
Test-Case 'Identite domaine : compte local en mode integre, signale avant l appel AD' {
    $w=Get-PestoDomainIdentityWarning -Identity ([pscustomobject]@{IsDomainUser=$false})
    Assert-True ([bool]$w) 'Avertissement attendu'
    Assert-True ($w -match 'local') ('La cause doit nommer le compte local : '+$w)
    Assert-True ($w -match 'Autre compte AD') ('La sortie doit etre proposee : '+$w)
}
Test-Case 'Identite domaine : une identite absente ou illisible ne vaut pas un compte du domaine' {
    Assert-True ([bool](Get-PestoDomainIdentityWarning -Identity $null)) 'Identite nulle signalee'
    Assert-True ([bool](Get-PestoDomainIdentityWarning)) 'Identite non transmise signalee'
    Assert-True ([bool](Get-PestoDomainIdentityWarning -Identity ([pscustomobject]@{IsDomainUser=$null}))) 'IsDomainUser illisible signale'
}
Test-Case 'Identite domaine : le worker nomme la cause dans l exception, sans inventer d echec' {
    $er=$null
    try { throw [Exception]::new('Impossible de contacter le serveur AD.') } catch { $er=$_ }
    $cause=Add-PestoDomainIdentityCause $er ([pscustomobject]@{IsDomainUser=$false})
    Assert-True ($cause -isnot [Management.Automation.ErrorRecord]) 'Le worker doit rendre une exception'
    Assert-True ($cause.Message -match 'local') ('La cause doit nommer le compte local : '+$cause.Message)
    Assert-True ($cause.Message -match 'Impossible de contacter le serveur AD') ('Le texte d origine doit survivre : '+$cause.Message)
}
Test-Case 'Identite domaine : hors cause identifiee, l erreur d origine est rendue intacte' {
    $er=$null
    try { throw [Exception]::new('Authentification refusée.') } catch { $er=$_ }
    $same=Add-PestoDomainIdentityCause $er ([pscustomobject]@{IsDomainUser=$true})
    Assert-True ([object]::ReferenceEquals($same,$er)) 'Aucune reecriture quand le compte est du domaine'
    $sans=Add-PestoDomainIdentityCause $er ([pscustomobject]@{IsDomainUser=$true})
    Assert-Equal 'Authentification refusée.' ([string]$sans.Exception.Message) 'Le message d origine reste le seul'
}

Test-Case 'Identite explicite ou inconnue : ne pas inventer une cause locale' {
    $er=$null
    try { throw [Exception]::new('Authentification refusée ou réseau indisponible.') } catch { $er=$_ }
    foreach($identite in @($null,([pscustomobject]@{IsDomainUser=$false}),([pscustomobject]@{IsDomainUser=$true}))){
        $same=Add-PestoDomainIdentityCause $er $identite -HasExplicitCredential
        Assert-True ([object]::ReferenceEquals($same,$er)) 'Le credential explicite conserve l erreur AD originale'
    }
    foreach($identite in @($null,([pscustomobject]@{IsDomainUser=$null}))){
        $same=Add-PestoDomainIdentityCause $er $identite
        Assert-True ([object]::ReferenceEquals($same,$er)) 'Identite inconnue : aucune cause locale deduite'
    }
    $cause=Add-PestoDomainIdentityCause $er ([pscustomobject]@{IsDomainUser=$false})
    Assert-True ([object]::ReferenceEquals($cause.InnerException,$er.Exception)) 'Exception d origine conservee'
    Assert-True ($cause.Message -notmatch 'ne peut pas|n''a pas accepté') 'Aucune cause certaine deduite du seul jeton'
}

$script:QueueRunState=$null

$failed=@($script:Results|Where-Object{$_.Result -ne 'PASS'}).Count
foreach($r in $script:Results){'{0} {1}{2}' -f $r.Result,$r.Name,$(if($r.Detail){' :: '+$r.Detail}else{''})}
$engine='PowerShell '+$PSVersionTable.PSVersion.ToString()+' ('+[string]$PSVersionTable.PSEdition+')'
'RESULTAT {0} reussis, {1} echecs | moteur : {2} | doubles AD/Windows, aucune operation reelle' -f ($script:Results.Count-$failed),$failed,$engine
if($ReportPath){
    $report=[ordered]@{Schema=1;Suite='Stabilisation';Engine=$engine;Passed=($script:Results.Count-$failed);Failed=$failed;Skipped=0;Cases=$script:Results.ToArray();Utc=[DateTime]::UtcNow.ToString('o')}
    [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReportPath),($report|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
if($failed){exit 1}
exit 0

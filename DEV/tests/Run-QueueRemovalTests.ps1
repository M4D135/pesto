#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SourcePath='',
    [string]$ReportPath=''
)
# Windows PowerShell 5.1 : $PSScriptRoot est vide dans les valeurs par défaut des paramètres (vu le 03/10).
if(-not $SourcePath){$SourcePath=Join-Path $PSScriptRoot '..\wad\Pesto-Core.ps1'}
if(-not $ReportPath){$ReportPath=Join-Path $PSScriptRoot 'windows-queue-removal-results.json'}
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Tests de file : Windows PowerShell 5.1 x64 requis.'}
Add-Type -AssemblyName System.Data
# Ne jamais lancer/dot-sourcer Pesto : seules les fonctions listées sont extraites.
# DataTable/DataView et écriture atomique réelles. Contrôles UI et modales simulés.
# Ces tests ne sont ni un rendu WPF, ni une connexion AD.
$tokens=$null;$parseErrors=$null
$defs=@{}
# Le moteur a réparti ses fonctions dans les composants qu'il dot-source. Les garder du seul cœur laissait le
# harnais sans les portes de sécurité que Update-QueueButtons appelle : à l'exécution le terme absent levait
# CommandNotFoundException, et la suite échouait sans que le contrat soit testé. Même règle que les contrôleurs
# statiques : cœur d'abord, puis composants dot-sources, premier gagnant. Seules les fonctions de $load restent
# extraites — rien n'est dot-sourcé, aucun module Active Directory n'est chargé.
$corePath=[IO.Path]::GetFullPath($SourcePath)
$files=@($corePath)
$component=[regex]'(?m)^[ \t]*\.[ \t]+\(Join-Path[ \t]+\$PSScriptRoot[ \t]+''(Pesto-[A-Za-z]+\.ps1)''\)'
foreach($m in $component.Matches([IO.File]::ReadAllText($corePath))){
    $candidate=Join-Path ([IO.Path]::GetDirectoryName($corePath)) $m.Groups[1].Value
    if(Test-Path -LiteralPath $candidate){$files+=[IO.Path]::GetFullPath($candidate)}
}
foreach($file in $files){
    $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw ($file+"`n"+(($parseErrors|ForEach-Object{"$($_.Extent.StartLineNumber): $($_.Message)"}) -join "`n"))}
    foreach($node in $ast.EndBlock.Statements){
        if($node -is [Management.Automation.Language.FunctionDefinitionAst] -and -not $defs.ContainsKey($node.Name)){$defs[$node.Name]=$node.Extent.Text}
    }
}
$load=@('Save-PestoQueueUndo','Get-PestoQueueContentStamp','Get-PestoStableHash','ConvertTo-PestoCanonicalValue','New-QueueTable','Ensure-Table','Get-PestoPlanSignature','Get-PestoSelectedQueueIndex',
    'Write-PestoAtomicText','Save-PestoQueueCheckpoint','Restore-PestoQueueCheckpoint','Update-QueueButtons',
    'Exit-EditMode','Get-PestoQueueRemovalState','Remove-PestoQueueRow','Delete-SelectedRow',
    # Portes de sécurité appelées par Update-QueueButtons, chargées pour vrai et non stubbées : un bouchon qui
    # rendrait $false désactiverait le verrou dans le seul test censé le surveiller, et la suite passerait sur
    # un bouton que le moteur refuse. Leur chemin de reçus est doublé vers SuiteTemp plus bas.
    'Test-PestoGlobalSafetyBarrier','Test-PestoDirectTargetBarrier','Invoke-PestoQueueLockAcknowledgement',
    'Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt','Test-PestoAcknowledgementNeeded',
    'Assert-PestoAcknowledgement','Assert-PestoClosedObject','Assert-PestoObservationSnapshot','New-PestoAcknowledgement')
foreach($name in $load){if(-not $defs.ContainsKey($name)){throw "Fonction absente : $name"};. ([scriptblock]::Create($defs[$name]))}
# Les bouchons du harnais sont définis plus bas et écraseraient en silence une vraie fonction du moteur si $load
# venait à l'apporter : étendre $load ne changerait rien et la suite passerait en croyant tester le moteur. La
# signature de configuration est le seul cas où cette collision est probable — elle est refusée à la charge.
if($load -contains 'Get-PestoConfigurationSignature'){
    throw 'Get-PestoConfigurationSignature est dans $load alors que le harnais en définit un bouchon plus bas, qui écraserait la vraie fonction. Supprimer ce bouchon, et vérifier que la suite ne tire ni DNS ni Active Directory.'
}
$script:OriginalSaveCheckpoint=${function:Save-PestoQueueCheckpoint}
$results=New-Object 'Collections.Generic.List[object]'
$script:SuiteTemp=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-queue-tests-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:SuiteTemp)
function Assert-True {param($Value,[string]$Message='Condition non satisfaite');if($Value -ne $true){throw $Message}}
function Assert-Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]."}}
function Assert-Throws {param([scriptblock]$Body);$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};if(-not $caught){throw 'Exception attendue.'}}
function Case {param([string]$Name,[scriptblock]$Body);try{Reset-Fixture;& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "OK  $Name"}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO  $Name : $($_.Exception.Message)"}}
function Get-PestoStateDirectory {return $script:StateDir}
# Reçus synthétiques uniquement : les barrières réelles ne lisent jamais ProgramData.
function Get-PestoInterventionRoot {return (Join-Path $script:SuiteTemp 'interventions')}
function Save-PestoQueueCheckpoint {
    param([string]$Phase='Idle')
    $script:SaveCount++
    if($script:FailSave){throw [IO.IOException]::new('TEST : écriture du fichier de reprise refusée.')}
    & $script:OriginalSaveCheckpoint -Phase $Phase
}
function Test-PestoAsyncOperationRunning {param($Name);return $false}
# Get-PestoConfigurationSignature vit dans wad/Pesto-Configuration.ps1 : sa fermeture réelle atteint 11 fonctions
# du moteur, dont Test-PestoDnsName. La charger ici tirerait DNS et l'AD dans une suite déclarée « aucun AD
# connecté ». Le harnais ne définit jamais $script:CFG, et la première ligne du moteur rend '' pour une
# configuration absente : ce bouchon reproduit exactement cette branche et refuse toute autre entrée. S'il
# arrivait qu'un cas renseigne $script:CFG, la suite rougit au lieu de comparer des clés de cache fabriquées.
function Get-PestoConfigurationSignature {
    param($Config)
    if($Config){throw 'Get-PestoConfigurationSignature : $script:CFG est renseigné mais la fermeture réelle de la signature de configuration n''est pas chargée dans ce harnais. Étendre $load à wad/Pesto-Configuration.ps1 plutôt que de laisser ce bouchon calculer une clé fausse.'}
    return ''
}
function Update-PestoPilotage {}
function Update-AddButton {}
function Sync-Grid {
    if($Grid.SelectedItem -is [Data.DataRowView] -and $script:table.Rows.IndexOf($Grid.SelectedItem.Row) -lt 0){$Grid.SelectedItem=$null}
}
function Confirm-YesNo {param([string]$Msg,[bool]$Confirm);$script:LastPrompt=$Msg;if($script:StartRunInConfirm){$script:Running=$true};return $script:AllowConfirm}
function Show-MsgError {param($Message,$Title);$script:LastError=[string]$Message}
function Show-MsgWarning {param($Message);$script:LastError=[string]$Message}
function Write-Log {param($Message,$Level,$ErrorRecord,$Category);$script:LastLog=[string]$Message}
function Add-LogLine {param($Text,$Kind);$script:LastLog=[string]$Text}
# Pièges : ces commandes ne doivent jamais être appelées pour retirer une ligne.
function Rename-Computer {throw 'MUTATION INTERDITE : Rename-Computer'}
function Add-Computer {throw 'MUTATION INTERDITE : Add-Computer'}
function Move-ADObject {throw 'MUTATION INTERDITE : Move-ADObject'}
function Set-ADObject {throw 'MUTATION INTERDITE : Set-ADObject'}
function Remove-ADObject {throw 'MUTATION INTERDITE : Remove-ADObject'}
function Remove-ADComputer {throw 'MUTATION INTERDITE : Remove-ADComputer'}
function Restart-Computer {throw 'MUTATION INTERDITE : Restart-Computer'}
function New-TestRow {
    param([Data.DataTable]$Table,[int]$Number)
    $row=$Table.NewRow();$row.Nom_du_PC=('P111301PR765{0:000}' -f $Number)
    $row.Nouveau_Nom=('P111301PR765{0:000}' -f ($Number+100))
    $row.Renommer=$true;$row.Traiter=$true;$row.Site='PR';$row.Service='765'
    $row.OU_Actuelle='OU=PR,OU=Postes,DC=example,DC=local';$row.OU_Destination=$row.OU_Actuelle
    $row.Plan='RENOMMER SEUL';$row.Precontrole='À CONTRÔLER'
    [void]$Table.Rows.Add($row);return ,$row
}
function Reset-Fixture {
    $script:StateDir=Join-Path $script:SuiteTemp ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($script:StateDir)
    $script:DOMAINE='example.local';$script:DC='dc.example.local';$script:INDOMAIN=$true
    $script:Pesto_VERSION='17.0-RC8';$script:PREFIXE='111301';$script:PRD=$true;$script:CLEAR_PROTECTION=$true
    $script:OU=@{PREPROD='OU=Transit,OU=Postes,DC=example,DC=local';ROOT='OU=Postes,DC=example,DC=local'}
    $script:GUI=$false;$script:SIM=$false;$script:Running=$false;$script:PreflightRunning=$false
    $script:MutationUncertain=$false;$script:CfgRestartRequired=$false;$script:QueueStopRequested=$false
    # État lu par les deux portes de sécurité, désormais chargées pour vrai. Sans initialisation explicite, un
    # cas qui lèverait MutationUncertain hériterait d'un verrou « non rattaché » et d'un blocage imprévisible.
    $script:DirectLocked=$false;$script:DirectReceipt=$null;$script:QueueOperationIds=@()
    $script:EDIT_ROW_INDEX=-1;$script:QueueRestoreChecked=$false;$script:PreflightCache=@{}
    $script:SaveCount=0;$script:FailSave=$false;$script:AllowConfirm=$true;$script:StartRunInConfirm=$false
    $script:LastPrompt='';$script:LastError='';$script:LastLog=''
    $script:table=New-QueueTable
    foreach($i in 1..3){[void](New-TestRow -Table $script:table -Number $i)}
    $script:Grid=[pscustomobject]@{SelectedItem=$script:table.DefaultView[1];ItemsSource=$script:table.DefaultView}
    foreach($n in @('BtnAdd','BtnEdit','BtnDelete','BtnClear','BtnImport','BtnExport','BtnCheckAll','BtnUncheckAll','BtnPreview','BtnDetails','BtnRetryMove','BtnSafetyReset','BtnSafetyAck','BtnStop','BtnRun','LblEmpty','LblQueueCount','ChkRemote','LblStatus')){
        Set-Variable -Name $n -Scope Script -Value ([pscustomobject]@{IsEnabled=$false;Content='';Text='';Visibility='Visible';ToolTip=''})
    }
    $BtnAdd.Content='Ajouter à la file';$BtnEdit.Content='Modifier'
    $script:AcknowledgeDialogResult=$null;$script:StartRunInAck=$false;$script:WorkerStillActive=$false
    $script:InterventionFiles=@{};$script:AcknowledgedReceipts=@();$script:UnmappedQueueLock=$false
    $script:JoinBusy=$false;$script:DirectBusy=$false;$script:PestoReadOnly=$false
}
# Doubles limités au dialogue, aux workers et aux reçus du test de file. Le writer est qualifié séparément.
function Test-PestoQueueWorkerStillActive {return $script:WorkerStillActive}
function Show-PestoAcknowledgeDialog {param($Summary);$script:LastPrompt=$Summary;if($script:StartRunInAck){$script:Running=$true};return $script:AcknowledgeDialogResult}
function Read-PestoIntervention {param($Path);if($script:InterventionFiles.ContainsKey($Path)){return $script:InterventionFiles[$Path]};throw 'Reçu synthétique illisible'}
function Set-PestoOperationAcknowledgement {param($OperationId,$Reason);$script:AcknowledgedReceipts+=@($OperationId);return [pscustomobject]@{OperationId=$OperationId}}
function Show-PestoUsefulError {param($Title,$Message,$Stage,$MutationPossible);$script:LastError=$Message}
function Write-AuditLine {param($Text,$Kind);$script:LastLog=$Text}
function Update-PestoSuiteUI {}
function New-AckFixture {
    param([string]$Status='INCERTAIN',[string]$Domain='example.local',[string]$TaskPhase='',[switch]$AlreadyAcknowledged,[switch]$RowOnly)
    $script:MutationUncertain=$true;$script:AcknowledgeDialogResult='Examen manuel du poste effectué'
    $operation=[Guid]::NewGuid().ToString('N');$row=$script:table.Rows[0]
    $row.Operation_ID=$operation;$row.Statut=$Status;$row.Code=if($Status -eq 'PARTIEL'){'89'}else{'97'};$row.Traiter=$true;$row.Message='Résultat original'
    $receipt=[pscustomobject]@{OperationId=$operation;Plan=[pscustomobject]@{Domain=$Domain};Tasks=@();Phase='Uncertain';ResultCode=97}
    if($TaskPhase){$receipt.Tasks=@([pscustomobject]@{Phase=$TaskPhase})}
    if($AlreadyAcknowledged){$receipt|Add-Member NoteProperty Acknowledged (New-PestoAcknowledgement -Receipt $receipt -Utc '2026-10-15T12:00:00Z' -By 'EXAMPLE\test' -Reason 'Examen manuel terminé')}
    $path=Join-Path (Get-PestoInterventionRoot) ($operation+'.json')
    [void][IO.Directory]::CreateDirectory((Get-PestoInterventionRoot));[IO.File]::WriteAllText($path,'fixture')
    $script:InterventionFiles[$path]=$receipt
    $script:QueueOperationIds=@(if(-not $RowOnly){$operation})
    return ,$row
}

try {
    Case 'Cas de la capture : retirer autorisé pendant la modification, exécuter reste bloqué' {
        $script:EDIT_ROW_INDEX=1;Update-QueueButtons
        Assert-True $BtnDelete.IsEnabled;Assert-True (-not $BtnRun.IsEnabled)
        Assert-True ((Get-PestoQueueRemovalState -Row $Grid.SelectedItem.Row).EndsEdit)
    }
    Case 'Aucune ligne sélectionnée : retrait désactivé même si les cases sont cochées' {
        $Grid.SelectedItem=$null;Update-QueueButtons
        Assert-True (-not $BtnDelete.IsEnabled);Delete-SelectedRow;Assert-Equal $script:table.Rows.Count 3
    }
    Case 'Ligne décochée mais surlignée : peut être retirée' {
        $Grid.SelectedItem.Row.Traiter=$false;Update-QueueButtons;Assert-True $BtnDelete.IsEnabled
    }
    Case 'Exécution active : bouton et fonction refusent le retrait' {
        $script:Running=$true;Update-QueueButtons;Assert-True (-not $BtnDelete.IsEnabled)
        Assert-Throws {Remove-PestoQueueRow -Row $Grid.SelectedItem.Row};Assert-Equal $script:table.Rows.Count 3
    }
    Case 'Précontrôle actif : retrait refusé même en édition' {
        $script:PreflightRunning=$true;$script:EDIT_ROW_INDEX=1;Update-QueueButtons
        Assert-True (-not $BtnDelete.IsEnabled);Assert-Throws {Remove-PestoQueueRow -Row $Grid.SelectedItem.Row}
    }
    Case 'Une DataRow provenant d une autre table est refusée' {
        $other=New-QueueTable;$r=New-TestRow -Table $other -Number 2
        Assert-Throws {Remove-PestoQueueRow -Row $r};Assert-Equal $script:table.Rows.Count 3
    }
    Case 'Une ancienne ligne détachée est refusée' {
        $r=$script:table.Rows[1];$script:table.Rows.Remove($r)
        Assert-Throws {Remove-PestoQueueRow -Row $r}
    }
    Case 'Une ligne marquée Deleted est refusée' {
        $r=$script:table.Rows[1];$script:table.AcceptChanges();$r.Delete()
        Assert-Throws {Remove-PestoQueueRow -Row $r}
    }
    Case 'Refuser la confirmation ne change ni la file ni l édition ni la sauvegarde' {
        $script:EDIT_ROW_INDEX=1;$script:AllowConfirm=$false;Delete-SelectedRow
        Assert-Equal $script:table.Rows.Count 3;Assert-Equal $script:EDIT_ROW_INDEX 1;Assert-Equal $script:SaveCount 0
    }
    Case 'Retirer la ligne modifiée quitte son édition après confirmation' {
        $script:EDIT_ROW_INDEX=1;$BtnEdit.Content='Annuler la modification';Delete-SelectedRow
        Assert-Equal $script:table.Rows.Count 2;Assert-Equal $script:EDIT_ROW_INDEX -1
        Assert-Equal $BtnEdit.Content 'Modifier';Assert-True ($script:LastPrompt -match 'non enregistrés')
    }
    Case 'Seule la ligne surlignée est retirée, pas les autres lignes cochées' {
        Delete-SelectedRow
        Assert-Equal (($script:table.Rows|ForEach-Object{$_.Nom_du_PC}) -join ',') 'P111301PR765001,P111301PR765003'
        Assert-Equal @($script:table.Rows|Where-Object{$_.Traiter}).Count 2
    }
    Case 'Tri décroissant : le retrait utilise la DataRow réelle' {
        $script:table.DefaultView.Sort='Nom_du_PC DESC';$Grid.SelectedItem=$script:table.DefaultView[0]
        Delete-SelectedRow
        Assert-Equal (($script:table.Rows|ForEach-Object{$_.Nom_du_PC}) -join ',') 'P111301PR765001,P111301PR765002'
    }
    Case 'Filtre : retirer la ligne visible ne retire pas une ligne masquée' {
        $script:table.DefaultView.RowFilter="Nom_du_PC = 'P111301PR765003'";$Grid.SelectedItem=$script:table.DefaultView[0]
        Delete-SelectedRow
        Assert-Equal (($script:table.Rows|ForEach-Object{$_.Nom_du_PC}) -join ',') 'P111301PR765001,P111301PR765002'
    }
    Case 'Retirer avant une autre ligne en édition recalcule son index' {
        $edited=$script:table.Rows[2];$script:EDIT_ROW_INDEX=2;$Grid.SelectedItem=$script:table.DefaultView[0]
        $BtnEdit.Content='Annuler la modification';Delete-SelectedRow
        Assert-Equal $script:EDIT_ROW_INDEX 1
        Assert-True ([object]::ReferenceEquals($script:table.Rows[$script:EDIT_ROW_INDEX],$edited))
        Assert-Equal $BtnEdit.Content 'Annuler la modification'
    }
    Case 'Retirer après une autre ligne en édition conserve son index' {
        $edited=$script:table.Rows[0];$script:EDIT_ROW_INDEX=0;$Grid.SelectedItem=$script:table.DefaultView[2]
        Delete-SelectedRow;Assert-Equal $script:EDIT_ROW_INDEX 0
        Assert-True ([object]::ReferenceEquals($script:table.Rows[0],$edited))
    }
    Case 'La sauvegarde JSON ne contient plus la ligne retirée' {
        & $script:OriginalSaveCheckpoint
        Delete-SelectedRow
        $saved=Get-Content -LiteralPath (Join-Path $script:StateDir 'queue.json') -Raw -Encoding UTF8|ConvertFrom-Json
        Assert-Equal @($saved.Rows).Count 2
        Assert-Equal @($saved.Rows|Where-Object{$_.Nom_du_PC -eq 'P111301PR765002'}).Count 0
    }
    Case 'Le cache du précontrôle retiré est invalidé sans vider les autres' {
        $key=Get-PestoPlanSignature $Grid.SelectedItem.Row;$script:PreflightCache[$key]='removed';$script:PreflightCache['other']='keep'
        Delete-SelectedRow;Assert-True (-not $script:PreflightCache.ContainsKey($key));Assert-Equal $script:PreflightCache['other'] 'keep'
    }
    Case 'Échec de sauvegarde : même objet, mêmes données et même ordre restaurés' {
        $r=$Grid.SelectedItem.Row;$before=($r.ItemArray|ConvertTo-Json -Compress)
        $script:FailSave=$true;Delete-SelectedRow
        Assert-Equal $script:table.Rows.Count 3
        Assert-True ([object]::ReferenceEquals($script:table.Rows[1],$r))
        Assert-Equal ($r.ItemArray|ConvertTo-Json -Compress) $before
        Assert-True ($script:LastError -match 'conservée')
    }
    Case 'Échec de sauvegarde : l édition et le cache sont conservés' {
        $script:EDIT_ROW_INDEX=1;$BtnEdit.Content='Annuler la modification'
        $key=Get-PestoPlanSignature $Grid.SelectedItem.Row;$script:PreflightCache[$key]='keep';$script:FailSave=$true
        Delete-SelectedRow;Assert-Equal $script:EDIT_ROW_INDEX 1;Assert-Equal $BtnEdit.Content 'Annuler la modification'
        Assert-Equal $script:PreflightCache[$key] 'keep'
    }
    Case 'Échec avant écriture : ancien checkpoint intact' {
        & $script:OriginalSaveCheckpoint
        $path=Join-Path $script:StateDir 'queue.json';$old=[IO.File]::ReadAllText($path)
        $script:FailSave=$true;Delete-SelectedRow;Assert-Equal ([IO.File]::ReadAllText($path)) $old
    }
    Case 'Un traitement démarré pendant la confirmation est recontrôlé' {
        $script:StartRunInConfirm=$true;Delete-SelectedRow
        Assert-Equal $script:table.Rows.Count 3;Assert-Equal $script:SaveCount 0
    }
    Case 'Le retrait ne modifie ni le journal historique ni le verrou existant' {
        $path=Join-Path $script:StateDir 'history-v1.json';[IO.File]::WriteAllText($path,'{"keep":true}')
        $script:MutationUncertain=$true;Delete-SelectedRow
        Assert-Equal ([IO.File]::ReadAllText($path)) '{"keep":true}';Assert-True $script:MutationUncertain
    }
    Case 'File devenue vide : le verrou Uncertain survit à une relecture du checkpoint' {
        $script:table.Rows.Clear();$row=New-TestRow -Table $script:table -Number 1
        $script:MutationUncertain=$true;[void](Remove-PestoQueueRow -Row $row)
        $saved=Get-Content -LiteralPath (Join-Path $script:StateDir 'queue.json') -Raw -Encoding UTF8|ConvertFrom-Json
        Assert-Equal $saved.Phase 'Uncertain';Assert-Equal @($saved.Rows).Count 0
        $Grid.SelectedItem=$null;$script:MutationUncertain=$false;Restore-PestoQueueCheckpoint
        Assert-True $script:MutationUncertain;Assert-True ($LblStatus.Text -match 'VERROU')
    }
    Case 'Mode démo : retirer ne crée pas de checkpoint réel' {
        $script:GUI=$true;Delete-SelectedRow
        Assert-Equal $script:table.Rows.Count 2;Assert-True (-not (Test-Path -LiteralPath (Join-Path $script:StateDir 'queue.json')))
    }
    Case 'File vide sans verrou : retrait désactivé et aucune exécution possible' {
        $script:table.Rows.Clear();$Grid.SelectedItem=$null;Update-QueueButtons
        Assert-True (-not $BtnDelete.IsEnabled);Assert-True (-not $BtnRun.IsEnabled)
    }

    Case 'Acquittement annulé conserve verrou et fichiers' {
        $row=New-AckFixture;$script:AcknowledgeDialogResult=$null
        Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-Equal $script:SaveCount 0;Assert-Equal $script:AcknowledgedReceipts.Count 0;Assert-True $row.Traiter
    }
    Case 'Mutation démarrée pendant le dialogue refuse acquittement' {
        [void](New-AckFixture);$script:StartRunInAck=$true
        Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-True ($script:LastError -match 'opération est encore active');Assert-Equal $script:AcknowledgedReceipts.Count 0
    }
    Case 'Worker actif refuse acquittement avant le dialogue' {
        [void](New-AckFixture);$script:WorkerStillActive=$true
        Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-Equal $script:LastPrompt '';Assert-Equal $script:SaveCount 0
    }
    Case 'Reçu manquant conserve verrou' {
        $script:MutationUncertain=$true;$script:QueueOperationIds=@([Guid]::NewGuid().ToString('N'));$script:AcknowledgeDialogResult='Examen manuel'
        Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-True ($script:LastError -match 'introuvable')
    }
    Case 'Identifiant invalide conserve verrou' {
        $script:MutationUncertain=$true;$script:QueueOperationIds=@('invalide');$script:AcknowledgeDialogResult='Examen manuel'
        Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-True ($script:LastError -match 'Identifiant de reçu invalide')
    }
    Case 'Autre domaine conserve verrou' {
        [void](New-AckFixture -Domain other.invalid);Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-True ($script:LastError -match 'autre domaine');Assert-Equal $script:AcknowledgedReceipts.Count 0
    }
    Case 'Tâche non terminée conserve verrou' {
        [void](New-AckFixture -TaskPhase Started);Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-True ($script:LastError -match 'tâche Windows');Assert-Equal $script:AcknowledgedReceipts.Count 0
    }
    Case 'Identifiant de ligne absent de QueueOperationIds est acquitté' {
        $row=New-AckFixture -RowOnly;Invoke-PestoQueueLockAcknowledgement
        Assert-True (-not $script:MutationUncertain);Assert-Equal $script:AcknowledgedReceipts.Count 1;Assert-Equal $script:AcknowledgedReceipts[0] $row.Operation_ID
    }
    Case 'PARTIEL décoché conserve code message et identifiants' {
        $row=New-AckFixture -Status PARTIEL;Invoke-PestoQueueLockAcknowledgement
        Assert-True (-not $script:MutationUncertain);Assert-Equal $row.Statut PARTIEL;Assert-Equal $row.Code '89';Assert-Equal $row.Message 'Résultat original';Assert-Equal $row.Traiter $false
        Assert-Equal $script:QueueOperationIds[0] $row.Operation_ID
        $checkpoint=[IO.File]::ReadAllText((Join-Path $script:StateDir 'queue.json'))|ConvertFrom-Json
        Assert-Equal $checkpoint.Phase Acknowledged;Assert-Equal $checkpoint.OperationIds[0] $row.Operation_ID
    }
    Case 'EN COURS devient INCERTAIN code 97 et décoché' {
        $row=New-AckFixture -Status 'EN COURS';$row.Code='';Invoke-PestoQueueLockAcknowledgement
        Assert-True (-not $script:MutationUncertain);Assert-Equal $row.Statut INCERTAIN;Assert-Equal $row.Code '97';Assert-Equal $row.Traiter $false
    }
    Case 'Acquittement déjà enregistré ne se réécrit pas' {
        [void](New-AckFixture -AlreadyAcknowledged);Invoke-PestoQueueLockAcknowledgement
        Assert-True (-not $script:MutationUncertain);Assert-Equal $script:AcknowledgedReceipts.Count 0
    }
    Case 'Échec checkpoint restaure verrou et ligne' {
        $row=New-AckFixture -Status 'EN COURS';$row.Code='';$script:FailSave=$true
        Invoke-PestoQueueLockAcknowledgement
        Assert-True $script:MutationUncertain;Assert-Equal $row.Statut 'EN COURS';Assert-Equal $row.Code '';Assert-True $row.Traiter;Assert-True ($script:LastError -match 'Verrou de file conservé')
    }
} finally {
    # Seulement les données synthétiques du dossier temporaire de cette suite.
    if(Test-Path -LiteralPath $script:SuiteTemp){Remove-Item -LiteralPath $script:SuiteTemp -Recurse -Force}
}
$failed=@($results|Where-Object{-not $_.Passed}).Count
[pscustomobject]@{Version='17.0-RC8';Utc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Scope='Fonctions extraites du moteur, contrôles simulés, DataTable et fichiers temporaires réels. Aucun WPF ou AD connecté.';Passed=($results.Count-$failed);Failed=$failed;Tests=$results.ToArray()} |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "$($results.Count-$failed)/$($results.Count) tests de retrait réussis. Rapport : $ReportPath"
if($failed){exit 1}
exit 0

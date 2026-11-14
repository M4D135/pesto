#requires -Version 5.1
# Vues de reçus et archivage explicite de résultats terminés uniquement.
function Get-PestoReceiptIdentity {
    param($Receipt)
    if($Receipt.TargetMachineId){return 'Windows:'+([string]$Receipt.TargetMachineId).ToLowerInvariant()}
    $guid=[Guid]::Empty;$value=if($Receipt.JoinEvidence.BoundObjectGuid){$Receipt.JoinEvidence.BoundObjectGuid}else{$Receipt.Plan.Objet_GUID}
    if([Guid]::TryParse([string]$value,[ref]$guid) -and $guid -ne [Guid]::Empty){return 'AD:'+$guid.ToString('D')}
    return 'Operation:'+([string]$Receipt.OperationId)
}
function Merge-PestoTimelineRows {
    param([object[]]$Current,[object[]]$Other)
    # Un même reçu ne peut figurer qu'une fois ; l'emplacement lu en premier (vue ouverte) est conservé.
    $seen=@{};$result=[Collections.Generic.List[object]]::new()
    foreach($row in @(@($Current)+@($Other))){
        if(-not $row -or -not $row.OperationId){continue}
        $key=([string]$row.OperationId).ToLowerInvariant()
        if($seen.ContainsKey($key)){continue}
        $seen[$key]=$true;$result.Add($row)
    }
    # Date inconnue en tête, sans être confondue avec l'heure courante ; ordre stable sinon.
    return @($result|Sort-Object @{Expression={if($_.UpdatedUtc){$_.UpdatedUtc.UtcDateTime}else{[DateTime]::MinValue}}},@{Expression={[string]$_.OperationId}})
}
function Get-PestoReceiptTimelineOtherRoot {
    param([bool]$ShowingArchive=$false)
    $root=Get-PestoInterventionRoot
    if($ShowingArchive){return $root}
    return (Join-Path $root 'Archive')
}
function Get-PestoReceiptTimeline {
    <# Chronologie par identité stable, sur les reçus de la vue ouverte et ceux de l'autre emplacement
       (actifs ou archivés). Sans -OtherCatalogue ni -OtherError, l'autre emplacement est lu ici
       (lecture bornée à 5 000 fichiers, sans cache partagé). Aucun reçu n'est modifié. #>
    param($Receipt,[object[]]$Rows,[bool]$ShowingArchive=$false,[AllowNull()]$OtherCatalogue=$null,[string]$OtherError='')
    $identity=Get-PestoReceiptIdentity $Receipt
    $project={param($row,$where)[pscustomobject]@{Date=$row.UpdatedLocal;UpdatedUtc=$row.UpdatedUtc;Avant=$row.Computer;Apres=$row.NewName;Etat=$row.StatusLabel;OperationId=$row.RowId;Identite=$identity;Emplacement=$where}}
    $here=if($ShowingArchive){'Archivé'}else{'Actif'};$there=if($ShowingArchive){'Actif'}else{'Archivé'}
    $current=@($Rows|Where-Object{$_ -and $_.Readable -and (Get-PestoReceiptIdentity $_.Receipt) -ceq $identity}|ForEach-Object{& $project $_ $here})
    $other=@();$note=''
    if($OtherError){$note=$OtherError}
    else{
        try{
            if($null -eq $OtherCatalogue){$OtherCatalogue=Get-PestoInterventionCatalogue -Root (Get-PestoReceiptTimelineOtherRoot $ShowingArchive)}
            $other=@(foreach($entry in @($OtherCatalogue.Entries)){
                if(-not $entry -or -not $entry.Readable){continue}
                $row=ConvertTo-PestoInterventionRow $entry
                if((Get-PestoReceiptIdentity $row.Receipt) -ceq $identity){& $project $row $there}
            })
            if($OtherCatalogue.Truncated){$note='lecture limitée aux 5 000 premiers fichiers, la chronologie peut être incomplète.'}
        }catch{$note=$_.Exception.Message}
    }
    $merged=@(Merge-PestoTimelineRows -Current $current -Other $other)
    if($note){
        $label=if($ShowingArchive){'Reçus actifs non lus : '}else{'Archives non lues : '}
        $noteRow=[pscustomobject]@{Date='';UpdatedUtc=$null;Avant='';Apres='';Etat=$label+$note;OperationId='';Identite=$identity;Emplacement='Info'}
        $merged=@($merged)+@($noteRow)
    }
    return $merged
}
function Show-PestoReceiptTimeline {
    param($Context,[object[]]$Rows)
    if(-not $Context -or $Context.Shown -or -not [object]::ReferenceEquals($Context.Ui,$script:InterventionsUi)){return}
    $Context.Shown=$true
    [void](Show-PestoChoiceTable -Title 'Chronologie du poste' -Description ('Rapprochement par identité stable : '+(Get-PestoReceiptIdentity $Context.Receipt)+'. Reçus actifs et archivés. Aucun rapprochement basé seulement sur le nom.') -Rows @($Rows) -Columns @(@{Key='Date';Label='Date locale'},@{Key='Avant';Label='Nom source'},@{Key='Apres';Label='Nom cible'},@{Key='Etat';Label='Résultat'},@{Key='Emplacement';Label='Emplacement'}))
}
function Complete-PestoReceiptTimelineRead {
    param($Payload,$Context)
    if(-not $Context -or -not [object]::ReferenceEquals($Context.Ui,$script:InterventionsUi)){return}
    $values=@($Payload)
    if($values.Count -ne 1){Fail-PestoReceiptTimelineRead 'Retour de lecture ambigu.' $Context;return}
    try{Show-PestoReceiptTimeline $Context (Get-PestoReceiptTimeline -Receipt $Context.Receipt -Rows $Context.Rows -ShowingArchive $Context.ShowingArchive -OtherCatalogue $values[0])}
    catch{Show-MsgWarning $_.Exception.Message}
}
function Fail-PestoReceiptTimelineRead {
    param($ErrorRecord,$Context)
    if(-not $Context -or -not [object]::ReferenceEquals($Context.Ui,$script:InterventionsUi)){return}
    $reason=Protect-PestoLogText ([string]$ErrorRecord);if(-not $reason){$reason='lecture interrompue.'}
    try{Show-PestoReceiptTimeline $Context (Get-PestoReceiptTimeline -Receipt $Context.Receipt -Rows $Context.Rows -ShowingArchive $Context.ShowingArchive -OtherError $reason)}
    catch{Show-MsgWarning $_.Exception.Message}
}
function Test-PestoReceiptArchivable {
    param($Receipt)
    if(-not $Receipt -or [string]$Receipt.Phase -notin @('Verified','Failed','NotStarted')){return $false}
    if($Receipt.Protection -notin @('NotChanged','Restored') -or $Receipt.Rename -in @('Requested','Uncertain') -or $Receipt.Move -in @('Requested','Uncertain') -or $Receipt.Entra -in @('Requested','Uncertain')){return $false}
    if(@($Receipt.Tasks|Where-Object{$_ -and $_.Phase -notin @('Finished','Deleted','Refused')}).Count){return $false}
    return $true
}
function Move-PestoReceiptToArchive {
    param([Parameter(Mandatory=$true)][string]$OperationId)
    if($script:PestoReadOnly){throw 'Consultation : archivage indisponible.'}
    if($script:DirectBusy -or $script:Running -or $script:JoinBusy -or $script:RecoveryBusy -or $script:PreflightRunning){throw 'Attendez la fin des opérations avant cet archivage.'}
    $id=[Guid]::Empty;if(-not[Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant de reçu invalide.'}
    $root=Get-PestoInterventionRoot;$source=Join-Path $root ($id.ToString('N')+'.json');$archive=Join-Path $root 'Archive';$destination=Join-Path $archive ($id.ToString('N')+'.json')
    Assert-PestoPlainPath $source;Assert-PestoPlainPath $archive
    $mutex=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1');$owned=$false
    try{
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not$owned){throw 'Une mutation utilise les reçus. Archivage différé.'}
        $receipt=Read-PestoIntervention $source
        if([string]$receipt.OperationId -ne $id.ToString('N') -and [string]$receipt.OperationId -ne $id.ToString('D')){throw 'Identité du reçu différente du fichier.'}
        if(-not(Test-PestoReceiptArchivable $receipt)){throw 'Ce reçu reste actif : résultat non résolu, contrôle facultatif ou tâches non terminées. Il est conservé à sa place.'}
        if([IO.File]::Exists($destination)){throw 'Un reçu de même identifiant existe déjà dans les archives. Aucun remplacement.'}
        [void][IO.Directory]::CreateDirectory($archive);Assert-PestoPlainPath $archive
        $hash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        $meta=[pscustomobject]@{Schema=1;OperationId=$receipt.OperationId;ArchivedUtc=[DateTimeOffset]::UtcNow.ToString('o');Phase=$receipt.Phase;Sha256=$hash}
        $metaPath=Join-Path $archive ($id.ToString('N')+'.archive-info')
        # Une interruption entre la provenance et le déplacement peut laisser cette
        # provenance seule. Elle est réutilisée uniquement si elle décrit ces octets.
        $metaCreated=$false
        Assert-PestoPlainPath $metaPath
        if([IO.File]::Exists($metaPath)){
            $info=Get-Item -LiteralPath $metaPath -Force -ErrorAction Stop
            if($info.Length -gt 8192){throw 'Provenance existante trop volumineuse : aucun fichier modifié.'}
            $saved=[IO.File]::ReadAllText($metaPath,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -ErrorAction Stop
            $savedId=[Guid]::Empty;$archived=[DateTimeOffset]::MinValue
            $archivedText=if($saved.ArchivedUtc -is [DateTime]){$saved.ArchivedUtc.ToUniversalTime().ToString('o')}else{[string]$saved.ArchivedUtc}
            if($saved.Schema -ne 1 -or -not [Guid]::TryParse([string]$saved.OperationId,[ref]$savedId) -or $savedId -ne $id -or
               [string]$saved.Sha256 -cne $hash -or [string]$saved.Phase -cne [string]$receipt.Phase -or
               -not [DateTimeOffset]::TryParse($archivedText,[ref]$archived)){
                throw 'Provenance existante différente : reçu et provenance conservés pour examen.'
            }
        }else{
            Write-PestoNewExport -Path $metaPath -Text ($meta|ConvertTo-Json)
            $metaCreated=$true
        }
        try{[IO.File]::Move($source,$destination)}catch{
            # Ne supprimer que le fichier créé par cette tentative, jamais une
            # provenance préexistante ou un résultat concurrent.
            if($metaCreated){try{[IO.File]::Delete($metaPath)}catch{}}
            throw
        }
        if($script:PestoReceiptCatalogCache){Clear-PestoInterventionCatalogCache $script:PestoReceiptCatalogCache}
        [pscustomobject]@{Path=$destination;Sha256=$hash;OperationId=$receipt.OperationId}
    }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Get-PestoReconciliationAudit {
    param($Receipt)
    foreach($auditEntry in @($Receipt.Timeline|Select-Object -Last 96)){
        if($auditEntry.Stage -cne 'Reconciliation'){continue}
        $date=[DateTimeOffset]::MinValue
        $utc=if($auditEntry.Utc -is [DateTime]){$auditEntry.Utc.ToUniversalTime().ToString('o')}else{[string]$auditEntry.Utc}
        if(-not [DateTimeOffset]::TryParse($utc,[ref]$date)){continue}
        if([string]$auditEntry.State -cmatch '^Action=(TaskRead|Protection|Cleanup);State=(Requested|Confirmed|Unknown|Ready|NoDefinition|Empty);TaskIndex=([0-8])(?:;NativeCode=(-?[0-9]{1,10}))?$'){
            $code=$null;if($Matches[4]){$code=[long]$Matches[4];if($code -lt [int]::MinValue -or $code -gt [uint32]::MaxValue){continue}}
            [pscustomobject]@{Sequence=[long]$auditEntry.Sequence;Utc=$date.ToUniversalTime().ToString('o');Action=$Matches[1];State=$Matches[2];TaskIndex=[int]$Matches[3];NativeCode=$code}
        }
    }
}
function Get-PestoOperationSupport {
    param($Receipt,[bool]$Redact=$true)
    $data=[ordered]@{Schema=1;GeneratedUtc=[DateTimeOffset]::UtcNow.ToString('o');Redacted=$Redact;OperationId=[string]$Receipt.OperationId;Phase=[string]$Receipt.Phase;ResultCode=$Receipt.ResultCode;Rename=[string]$Receipt.Rename;Move=[string]$Receipt.Move;Protection=[string]$Receipt.Protection;Entra=[string]$Receipt.Entra;UpdatedUtc=[string]$Receipt.UpdatedUtc;Computer=$(if($Redact){'[POSTE]'}else{[string]$Receipt.Plan.Nom_du_PC});NewName=$(if($Redact){'[NOM CIBLE]'}else{[string]$Receipt.Plan.Nouveau_Nom});Domain=$(if($Redact){'[DOMAINE]'}else{[string]$Receipt.Plan.Domain});Summary=(Get-PestoOperationReport -Receipt $Receipt -Redact $Redact)}
    $data.ReconciliationAudit=@(Get-PestoReconciliationAudit $Receipt)
    $data.ReconciliationAuditScope='BoundedReceiptTimeline'
    return [pscustomobject]$data
}
function Export-PestoOperationSupport {
    param([string]$Directory,$Data,[string]$Diagnostics)
    Assert-PestoPlainPath $Directory
    if([IO.Directory]::Exists($Directory) -or [IO.File]::Exists($Directory)){throw 'Choisissez un dossier de support qui ne contient pas encore de données.'}
    $parent=Split-Path $Directory -Parent;if(-not[IO.Directory]::Exists($parent)){throw 'Le dossier parent doit déjà exister.'}
    $temp=Join-Path $parent ('.pesto-support-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
    try{
        Write-PestoNewExport (Join-Path $temp 'operation.json') ($Data|ConvertTo-Json -Depth 12)
        Write-PestoNewExport (Join-Path $temp 'diagnostic.json') $Diagnostics
        $files=@(Get-ChildItem -LiteralPath $temp -File|ForEach-Object{[pscustomobject]@{Name=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}})
        Write-PestoNewExport (Join-Path $temp 'manifest.json') ([pscustomobject]@{Schema=1;OperationId=$Data.OperationId;Redacted=[bool]$Data.Redacted;Files=$files}|ConvertTo-Json -Depth 6)
        [IO.Directory]::Move($temp,$Directory)
    }finally{if([IO.Directory]::Exists($temp)){Remove-Item -LiteralPath $temp -Recurse -Force}}
}
function Invoke-PestoReceiptTool {
    param([string]$Action)
    $ui=$script:InterventionsUi;if(-not$ui -or $ui.Loading){return}
    try{
        if($Action -eq 'LedgerArchives'){$ui.ShowArchived=-not $ui.ShowArchived;$ui.Window.FindName('LedgerArchives').Content=if($ui.ShowArchived){'Revenir aux reçus actifs'}else{'Consulter les archives'};Update-PestoInterventions;return}
        $row=$ui.Grid.SelectedItem;if(-not$row -or -not$row.Readable){Show-MsgInfo 'Sélectionnez un reçu lisible.';return};$receipt=$row.Receipt
        switch($Action){
            'LedgerTimeline' {
                # L'autre emplacement (archives ou reçus actifs) est lu hors du fil de l'interface, sans cache partagé.
                $context=[pscustomobject]@{Ui=$ui;Receipt=$receipt;Rows=@($ui.Rows);ShowingArchive=[bool]$ui.ShowArchived;Shown=$false}
                try{
                    $otherRoot=Get-PestoReceiptTimelineOtherRoot ([bool]$ui.ShowArchived)
                    $source=(Get-PestoWorkerCoreSource)+"`nfunction Get-PestoInterventionCatalogue {`n"+${function:Get-PestoInterventionCatalogue}.ToString()+"`n}"
                    $started=Start-PestoAsyncOperation -Name 'LedgerTimeline' -ScriptBlock {param($Source,$Root);. ([scriptblock]::Create($Source));Get-PestoInterventionCatalogue -Root $Root} -ArgumentList @($source,$otherRoot) -TimeoutSec 120 -CallbackContext $context `
                        -OnSuccess ${function:Complete-PestoReceiptTimelineRead} -OnError ${function:Fail-PestoReceiptTimelineRead}
                    if(-not $started -and -not $context.Shown){Fail-PestoReceiptTimelineRead 'une lecture de chronologie est déjà active.' $context}
                }catch{Fail-PestoReceiptTimelineRead $_ $context}
                return
            }
            'LedgerCompare' {
                $r=Show-PestoChoiceTable -Title 'Choisir les deux interventions à comparer' -Description 'Utilisez Ctrl+clic pour choisir exactement deux reçus. Aucun état ni observation ne sera modifié.' -Rows @($ui.Rows|Where-Object{$_.Readable}) -Columns @(@{Key='UpdatedLocal';Label='Date'},@{Key='Computer';Label='Poste'},@{Key='NewName';Label='Nom cible'},@{Key='StatusLabel';Label='État'}) -Multiple -AcceptText 'Comparer ces deux reçus'
                if($r.Accepted){if($r.Items.Count -ne 2){Show-MsgWarning 'Deux reçus exactement sont nécessaires. Recommencez la sélection.';return};$ordered=@($r.Items|Sort-Object UpdatedUtc);$differences=@(Compare-PestoInterventions $ordered[0].Receipt $ordered[1].Receipt);[void](Show-PestoChoiceTable -Title 'Comparer les interventions' -Description ('Premier : '+$ordered[0].RowId+' · second : '+$ordered[1].RowId+'. Les différences ne prouvent pas une causalité.') -Rows $differences -Columns @(@{Key='Champ';Label='Champ'},@{Key='Premiere';Label='Première intervention'},@{Key='Seconde';Label='Seconde intervention'}))};return
            }
            'LedgerArchiveSelected' {
                if($ui.ShowArchived){return};if(-not(Test-PestoReceiptArchivable $receipt)){Show-MsgWarning 'Seuls les reçus vérifiés ou refusés, sans tâche en cours, peuvent être archivés. Les suivis facultatifs restent conservés parmi les reçus actifs.';return}
                if(Confirm-YesNo -Msg ('Archiver le reçu '+$receipt.OperationId+' ? Son contenu sera conservé sans modification et restera consultable. Aucun poste ni objet AD ne sera modifié.') -Confirm $true -AcceptText 'Archiver ce reçu'){$moved=Move-PestoReceiptToArchive $receipt.OperationId;Add-LogLine ('Reçu archivé : '+$moved.OperationId+' · SHA256 '+$moved.Sha256) 'info';Update-PestoInterventions};return
            }
            'LedgerSupport' {
                $redact=[bool]$ui.Window.FindName('LedgerRedact').IsChecked;$data=Get-PestoOperationSupport $receipt $redact;$diagnostic=Get-PestoDiagnosticText -Redact $redact
                $preview=Show-PestoPanel -Title 'Dossier de support de cette intervention' -Body (($data|ConvertTo-Json -Depth 12)+"`n`nDIAGNOSTIC DE LA SESSION`n"+$diagnostic) -AcceptText 'Exporter ce dossier' -Monospace
                if($preview.Accepted){$dialog=[Microsoft.Win32.SaveFileDialog]::new();$dialog.Filter='Nom du dossier de support (*.support)|*.support';$dialog.FileName='Pesto-'+[string]$receipt.OperationId+'.support';if($dialog.ShowDialog($Win)){Export-PestoOperationSupport -Directory $dialog.FileName -Data $data -Diagnostics $diagnostic;Show-MsgInfo 'Dossier exporté avec manifeste SHA256. Aucun envoi automatique.'}};return
            }
        }
    }catch{Show-MsgWarning $_.Exception.Message}
}

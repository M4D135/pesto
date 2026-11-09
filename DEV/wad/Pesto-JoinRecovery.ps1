#requires -Version 5.1
# Contrats et reprise de jonction. Aucune commande ni écriture au chargement.

function Assert-PestoJoinReceiptData {
    param([Parameter(Mandatory=$true)]$Receipt)
    $allowed=@('Schema','Version','OperationId','Phase','Utc','MachineId','BootUtc','Computer','NewName','Domain','OU','DC','Reference','Account','Message','Metadata','Acknowledged')
    Assert-PestoClosedObject $Receipt $allowed @('Schema','OperationId','Phase','Utc','MachineId','BootUtc','Computer','NewName','Domain','OU')
    if($Receipt.Schema -isnot [int] -or $Receipt.Schema -ne 1 -or $Receipt.Phase -cnotin @('Running','PendingRestart','Uncertain','Failed','Verified')){throw 'Schéma ou phase du reçu de jonction invalide.'}
    $id=[Guid]::Empty
    if($Receipt.OperationId -isnot [string] -or -not [Guid]::TryParse($Receipt.OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant de jonction invalide.'}
    foreach($name in $allowed|Where-Object{$_ -notin @('Schema','Metadata','Acknowledged')}){
        $value=$Receipt.$name
        if($null -ne $value -and ($value -isnot [string] -or $value.Length -gt $(if($name -eq 'Message'){8192}elseif($name -eq 'OU'){4096}else{512}) -or $value -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')){throw ('Champ de reçu de jonction invalide : '+$name)}
    }
    # Reçu historique : structure du nom seulement ; le préfixe a pu changer depuis (autre département, autre cfg.json).
    # Le MachineId rattache le reçu à ce poste ; exiger le préfixe du jour bloquait toute opération (97) sur ce PC.
    if(-not(Test-PestoComputerName $Receipt.Computer) -or -not(Test-PestoGeneratedComputerName $Receipt.NewName -Prefix '') -or
       -not(Test-PestoDnsName $Receipt.Domain) -or -not(Test-PestoOUPath $Receipt.OU) -or
       (Get-PestoDomainFromDN $Receipt.OU) -ine $Receipt.Domain -or [string]::IsNullOrWhiteSpace($Receipt.MachineId)) {throw 'Cible ou domaine du reçu de jonction invalide.'}
    foreach($name in @('Utc','BootUtc')){
        $date=[DateTimeOffset]::MinValue
        if([string]$Receipt.$name -notmatch '(Z|[+-][0-9]{2}:[0-9]{2})$' -or -not [DateTimeOffset]::TryParse([string]$Receipt.$name,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw ('Date historique invalide : '+$name)}
    }
    if([DateTimeOffset]::Parse($Receipt.BootUtc) -gt [DateTimeOffset]::Parse($Receipt.Utc)){throw 'Le démarrage enregistré est postérieur à la demande.'}
    if($Receipt.Metadata){[void](ConvertTo-PestoDeploymentMetadata $Receipt.Metadata -LegacyReceipt)}
    # Acquittement (15/10) : schéma fermé, sans ResultCode (le reçu local de jonction n'en porte pas).
    if($Receipt.PSObject.Properties['Acknowledged'] -and $null -ne $Receipt.Acknowledged){[void](Assert-PestoAcknowledgement $Receipt.Acknowledged)}
    return $Receipt
}

function Test-PestoJoinIntervention {
    param($Receipt)
    if(-not $Receipt -or -not $Receipt.Plan){return $false}
    $p=$Receipt.Plan
    return ($p.Renommer -is [bool] -and $p.Deplacer -is [bool] -and -not $p.Renommer -and -not $p.Deplacer -and
        [string]::IsNullOrWhiteSpace([string]$p.OU_Actuelle) -and -not [string]::IsNullOrWhiteSpace([string]$p.OU_Destination) -and
        (Test-PestoComputerName ([string]$p.Nom_du_PC)) -and (Test-PestoGeneratedComputerName ([string]$p.Nouveau_Nom) -Prefix ''))
}

function Assert-PestoJoinEvidence {
    param([Parameter(Mandatory=$true)]$Evidence)
    $names=@('MachineId','BeforeBootUtc','PreparedUtc','NativeStatus','BoundObjectGuid')
    Assert-PestoClosedObject $Evidence $names $names
    foreach($name in $names){if($Evidence.$name -isnot [string] -or $Evidence.$name.Length -gt 512 -or $Evidence.$name -match '[\x00-\x1f\x7f]'){throw 'Métadonnée de jonction invalide.'}}
    if(-not $Evidence.MachineId -or $Evidence.NativeStatus -cnotin @('Unknown','Prepared','Requested','Accepted','Refused')){throw 'État de commande de jonction invalide.'}
    foreach($name in @('BeforeBootUtc','PreparedUtc')){$date=[DateTimeOffset]::MinValue;if($Evidence.$name -notmatch '(Z|[+-][0-9]{2}:[0-9]{2})$' -or -not [DateTimeOffset]::TryParse($Evidence.$name,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw 'Date de jonction non reconnue.'}}
    if($Evidence.BoundObjectGuid){$id=[Guid]::Empty;if(-not [Guid]::TryParse($Evidence.BoundObjectGuid,[ref]$id) -or $id -eq [Guid]::Empty){throw 'GUID lié à la jonction invalide.'}}
    if([DateTimeOffset]::Parse($Evidence.BeforeBootUtc) -gt [DateTimeOffset]::Parse($Evidence.PreparedUtc)){throw 'Chronologie de jonction incohérente.'}
    return $Evidence
}

function Set-PestoInitialJoinObservation {
    param([Parameter(Mandatory=$true)]$Local,[string]$ExistingGuid='')
    if($script:GUI -or $script:SIM){return}
    if(-not(Test-PestoJoinIntervention $script:ActiveIntervention)){throw 'Reçu de jonction absent avant engagement.'}
    $r=$script:ActiveIntervention
    if($r.Baseline -or $r.JoinEvidence){throw 'La photographie de jonction ne peut pas être remplacée.'}
    if($Local.PartOfDomain -isnot [bool] -or $Local.PendingRename -isnot [bool] -or $Local.Admin -isnot [bool] -or
       $Local.PartOfDomain -or $Local.PendingRename -or -not $Local.Admin -or $Local.DomainRole -notin @(0,2) -or
       $Local.Computer -ine $r.Plan.Nom_du_PC -or -not $Local.MachineId -or $Local.MachineId -ine $r.TargetMachineId){throw 'Identité initiale de jonction non confirmée.'}
    $now=[DateTime]::UtcNow.ToString('o')
    $e=Assert-PestoJoinEvidence ([pscustomobject]@{MachineId=[string]$Local.MachineId;BeforeBootUtc=[string]$Local.BootUtc;PreparedUtc=$now;NativeStatus='Prepared';BoundObjectGuid=[string]$ExistingGuid})
    $observation=[pscustomobject]@{ObservedUtc=$now;ADUtc='';WindowsUtc=$now;AD=$null;Health=$null;Windows=[pscustomobject]@{
        ActiveName=[string]$Local.ActiveName;ConfiguredName=[string]$Local.ConfiguredName;Domain=[string]$Local.Domain;PartOfDomain=$false;MachineId=[string]$Local.MachineId;BootUtc=[string]$Local.BootUtc;DomainRole=[int]$Local.DomainRole}}
    $snapshot=ConvertTo-PestoObservationSnapshot $observation
    $r|Add-Member -NotePropertyName Baseline -NotePropertyValue $snapshot -Force
    $r|Add-Member -NotePropertyName JoinEvidence -NotePropertyValue $e -Force
    $r.Schema=3;$r.UpdatedUtc=$now
    Add-PestoInterventionEvent -Receipt $r -Stage 'JoinBaseline' -State 'RecordedBeforeCommand'
    Write-PestoIntervention $r
}

function Set-PestoJoinNativeStatus {
    param([ValidateSet('Requested','Accepted','Refused')][string]$Status)
    if($script:GUI -or $script:SIM){return}
    $r=$script:ActiveIntervention
    if(-not $r -or -not $r.JoinEvidence){throw 'Métadonnées de jonction absentes. Aucun résultat supposé.'}
    [void](Assert-PestoJoinEvidence $r.JoinEvidence)
    if($r.JoinEvidence.NativeStatus -in @('Accepted','Refused')){throw 'Cette commande de jonction possède déjà un résultat. Ne pas la répéter.'}
    if($Status -eq 'Requested' -and $r.JoinEvidence.NativeStatus -ne 'Prepared'){throw 'Une jonction déjà demandée doit être vérifiée, pas répétée.'}
    if($Status -eq 'Accepted' -and $r.JoinEvidence.NativeStatus -ne 'Requested'){throw 'Aucune commande de jonction enregistrée : acceptation impossible.'}
    $r.JoinEvidence.NativeStatus=$Status;$r.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    Add-PestoInterventionEvent -Receipt $r -Stage 'Join' -State $Status
    Write-PestoIntervention $r
}

function Get-PestoJoinObservationDecision {
    param($Receipt,$Observation,[string]$LocalMachineId)
    $d=[ordered]@{Verified=$false;ResumeMove=$false;PendingRestart=$false;Message='Jonction à vérifier. Aucun renommage ni nouvel ajout proposé.';BoundObjectGuid=''}
    if(-not(Test-PestoJoinIntervention $Receipt) -or -not $Receipt.JoinEvidence){$d.Message='Ancienne jonction sans preuve initiale : importer son reçu local avant de la vérifier.';return [pscustomobject]$d}
    $e=Assert-PestoJoinEvidence $Receipt.JoinEvidence;$p=$Receipt.Plan;$w=$Observation.Windows;$ad=$Observation.AD;$health=$Observation.Health
    if(-not $LocalMachineId -or $LocalMachineId -ine $e.MachineId -or $Receipt.TargetMachineId -ine $e.MachineId -or
       -not $w -or $w.MachineId -ine $e.MachineId){$d.Message='Cette jonction doit être vérifiée depuis le PC concerné. Identité locale non confirmée.';return [pscustomobject]$d}
    [void](ConvertTo-PestoObservationSnapshot $Observation)
    if($w.PartOfDomain -isnot [bool] -or -not $w.PartOfDomain -or $w.Domain -ine $p.Domain -or $w.DomainRole -notin @(1,3)){
        $d.Message='Windows ne confirme pas encore le domaine attendu. Aucune nouvelle jonction automatique.';return [pscustomobject]$d
    }
    if($w.ActiveName -ine $p.Nouveau_Nom -or $w.ConfiguredName -ine $p.Nouveau_Nom){$d.PendingRestart=($w.ConfiguredName -ieq $p.Nouveau_Nom);$d.Message='Le nom Windows actif ou configuré diffère du nom demandé. Vérifier le redémarrage.';return [pscustomobject]$d}
    $before=[DateTimeOffset]::Parse($e.BeforeBootUtc,[Globalization.CultureInfo]::InvariantCulture);$boot=[DateTimeOffset]::MinValue
    if([string]$w.BootUtc -notmatch '(Z|[+-][0-9]{2}:[0-9]{2})$' -or -not [DateTimeOffset]::TryParse([string]$w.BootUtc,[ref]$boot) -or $boot -le $before -or $boot -le [DateTimeOffset]::Parse($e.PreparedUtc,[Globalization.CultureInfo]::InvariantCulture)){$d.PendingRestart=$true;$d.Message='Aucun démarrage postérieur au reçu initial n''est confirmé. Redémarrage explicite puis nouvelle lecture.';return [pscustomobject]$d}
    $gid=[Guid]::Empty
    if(-not $ad -or $ad.Name -ine $p.Nouveau_Nom -or $ad.OU -ine $p.OU_Destination -or
       -not [Guid]::TryParse([string]$ad.Guid,[ref]$gid) -or $gid -eq [Guid]::Empty){$d.Message='Nom, emplacement et identité AD de la jonction non confirmés.';return [pscustomobject]$d}
    if($p.TargetOUGuid -and $Observation.JoinDestinationGuid -ine $p.TargetOUGuid){$d.Message='L''identité de l''OU de destination n''est pas confirmée. Aucun verrou levé.';return [pscustomobject]$d}
    if(($p.Objet_GUID -and $p.Objet_GUID -ine $gid.ToString('D')) -or ($e.BoundObjectGuid -and $e.BoundObjectGuid -ine $gid.ToString('D'))){$d.Message='Le compte ordinateur a changé d''identité depuis le reçu. Aucun verrou levé.';return [pscustomobject]$d}
    # Une chaîne non vide telle que "false" n'est pas une preuve du canal sécurisé.
    $secure=$health -and (($health.SecureChannel -is [bool] -and $health.SecureChannel) -or ($health.SecureChannel -is [string] -and $health.SecureChannel -ceq 'Conforme'))
    if(-not $secure){
        $d.RetryAfterSec=30
        $d.Message='Le canal sécurisé local n''est pas confirmé. Netlogon peut démarrer après l''ouverture de session : relire dans 30 s. Aucune réparation automatique.'
        return [pscustomobject]$d
    }
    foreach($dateText in @($Observation.ObservedUtc,$Observation.ADUtc,$Observation.WindowsUtc,$health.Utc)){
        $date=[DateTimeOffset]::MinValue
        if(-not [DateTimeOffset]::TryParse([string]$dateText,[ref]$date)){$d.Message='Une date de lecture manque. Relire avant de consigner.';return [pscustomobject]$d}
        $age=([DateTimeOffset]::UtcNow-$date).TotalSeconds
        if($age -lt 0 -or $age -gt 120){$d.Message='Une source de la vérification est ancienne. Relire avant de consigner.';return [pscustomobject]$d}
    }
    $d.Verified=$true;$d.BoundObjectGuid=$gid.ToString('D');$d.Message='Nom actif, domaine, identité du PC, compte AD, emplacement et canal sécurisé confirmés après redémarrage. Entra reste un contrôle distinct.'
    return [pscustomobject]$d
}

function ConvertFrom-PestoLegacyJoinReceipt {
    param($Value,[string]$Domain,[string]$MachineId,[string]$SourceHash)
    $r=Assert-PestoJoinReceiptData $Value
    if($r.MachineId -ine $MachineId -or $r.Domain -ine $Domain -or $SourceHash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Le reçu historique ne correspond pas à ce PC et à ce domaine.'}
    if($r.Phase -in @('Failed','Verified')){return}
    $now=[DateTime]::UtcNow.ToString('o');$id=([Guid]$r.OperationId).ToString('N')
    $plan=[pscustomobject]@{Nom_du_PC=$r.Computer;Nouveau_Nom=$r.NewName;OU_Actuelle='';OU_Destination=$r.OU;Objet_GUID='';TargetOUGuid='';Domain=$Domain;DC=[string]$r.DC;ConfigStamp='';Renommer=$false;Deplacer=$false;Reboot=$false}
    $e=Assert-PestoJoinEvidence ([pscustomobject]@{MachineId=$MachineId;BeforeBootUtc=$r.BootUtc;PreparedUtc=$r.Utc;NativeStatus='Unknown';BoundObjectGuid=''})
    # Le fichier importé n'autorise rien et n'est pas une preuve de réussite Windows.
    return [pscustomobject]@{Schema=3;Version=$script:Pesto_VERSION;OperationId=$id;Plan=$plan;StartedUtc=$r.Utc;UpdatedUtc=$now;Phase='Uncertain';InitialProtection=$null;TargetMachineId=$MachineId;TargetOUGuid='';Entra='NotRequested';Protection='NotChanged';Rename='NotRequested';Move='NotRequested';ResultCode=97;ResultMessage='Jonction historique importée. Nouvelle lecture Windows et AD obligatoire.';LastStage='LegacyJoinImported';VerifiedUtc='';VerifiedBy='';ResumeFrom='';PlanFingerprint=(Get-PestoPlanFingerprint $plan);Sequence=0;Timeline=@();Legacy=[pscustomobject]@{Kind='Join';SHA256=$SourceHash;Line=1};Baseline=$null;LastObservation=$null;JoinEvidence=$e}
}

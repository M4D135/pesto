#requires -Version 5.1
# Operations explicites ; aucune connexion ou mutation au chargement.
function Get-PestoAttributeChanges {
    param($Current,$Requested)
    Assert-PestoClosedObject $Requested @('description','location','managedBy') @()
    $changes=@(foreach($p in $Requested.PSObject.Properties){
        if($p.Value -isnot [string] -or $p.Value.Length -gt 1024 -or $p.Value -match '[\x00-\x1f\x7f]'){throw 'Valeur attribut invalide.'}
        if($p.Name -eq 'managedBy' -and $p.Value -and $p.Value -notmatch '^(CN|OU)=.+,DC='){throw 'managedBy exige un DN.'}
        if([string]$Current.($p.Name) -cne $p.Value){[pscustomobject]@{Attribute=$p.Name;Before=[string]$Current.($p.Name);After=$p.Value;ReferenceGuid=''}}
    })
    return ,$changes
}
function Assert-PestoAttributeChanges {
    param($Changes)
    if($Changes -is [string] -or @($Changes).Count -lt 1 -or @($Changes).Count -gt 3){throw 'Une a trois modifications requises.'}
    $seen=@{}
    foreach($c in $Changes){
        Assert-PestoClosedObject $c @('Attribute','Before','After','ReferenceGuid') @('Attribute','Before','After','ReferenceGuid')
        if($c.Attribute -cnotin @('description','location','managedBy') -or $seen.ContainsKey($c.Attribute)){throw 'Attribut inconnu ou duplique.'};$seen[$c.Attribute]=$true
        foreach($field in @('Before','After')){if($c.$field -isnot [string] -or $c.$field.Length -gt 1024 -or $c.$field -match '[\x00-\x1f\x7f]'){throw 'Diff attribut invalide.'}}
        if($c.Before -ceq $c.After){throw 'Diff vide.'}
        if($c.Attribute -eq 'managedBy' -and $c.After){$g=[Guid]::Empty;if(-not[Guid]::TryParse([string]$c.ReferenceGuid,[ref]$g) -or $g -eq [Guid]::Empty){throw 'Identite managedBy manquante.'}}
        elseif($c.ReferenceGuid){throw 'Reference inattendue.'}
    }
}
function Get-PestoAttributeTarget {
    param([Guid]$ObjectGuid)
    if($ObjectGuid -eq [Guid]::Empty){throw 'GUID cible requis.'}
    $adp=Get-ADParams
    $pc=Get-ADComputer -Identity $ObjectGuid -Properties description,location,managedBy,ObjectGUID,DistinguishedName,userAccountControl -ErrorAction Stop @adp
    if(-not $pc -or [Guid]$pc.ObjectGUID -ne $ObjectGuid -or -not(Test-PestoOUInConfiguredScope (Get-PestoParentDN $pc.DistinguishedName)) -or (Get-PestoDomainFromDN $pc.DistinguishedName) -ine $script:DOMAINE){throw 'Identite ou perimetre AD non confirme.'}
    return $pc
}
function New-PestoAttributePlan {
    param([Guid]$ObjectGuid,$Requested,$Metadata=$null)
    $pc=Get-PestoAttributeTarget $ObjectGuid;$adp=Get-ADParams
    $changes=Get-PestoAttributeChanges $pc $Requested
    foreach($c in $changes){if($c.Attribute -eq 'managedBy' -and $c.After){
        if((Get-PestoDomainFromDN $c.After) -ine $script:DOMAINE){throw 'Reference managedBy hors domaine.'}
        $ref=Get-ADObject -Identity $c.After -Properties ObjectGUID -ErrorAction Stop @adp
        if(-not $ref){throw 'Reference managedBy absente.'};$c.ReferenceGuid=([Guid]$ref.ObjectGUID).ToString('D')
    }}
    Assert-PestoAttributeChanges $changes
    $parent=Get-PestoParentDN $pc.DistinguishedName
    $p=New-PestoPortablePlan -Action Move -Computer $pc.Name -NewName $pc.Name -SourceOU $parent -TargetOU $parent -Domain $script:DOMAINE -ObjectGuid $ObjectGuid.ToString('D') -ConfigStamp (Get-PestoConfigurationSignature $script:CFG) -MachineId (Get-PestoAutomationMachineId) -Metadata $Metadata
    $p.Action='Attributes';$p.PSObject.Properties.Remove('Integrity');$p|Add-Member Changes $changes
    $p|Add-Member Integrity (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $p))
    return $p
}
function Assert-PestoAttributePlan {
    param($Plan)
    $fields=@('Schema','Purpose','Action','CreatedUtc','ExpiresUtc','MachineId','ConfigStamp','Domain','Computer','NewName','SourceOU','TargetOU','ObjectGuid','TargetOUGuid','Type','SiteCode','ServiceCode','Metadata','Changes','Integrity')
    Assert-PestoClosedObject $Plan $fields $fields
    foreach($date in @('CreatedUtc','ExpiresUtc')){if($Plan.$date -is [DateTime]){$Plan.$date=$Plan.$date.ToUniversalTime().ToString('o')}}
    $copy=[ordered]@{};foreach($p in $Plan.PSObject.Properties){if($p.Name -ne 'Integrity'){$copy[$p.Name]=$p.Value}}
    if($Plan.Integrity -cnotmatch '^[a-f0-9]{64}$' -or (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -cne $Plan.Integrity -or $Plan.Schema -ne 1 -or $Plan.Purpose -cne 'PestoPreparedPlan' -or $Plan.Action -cne 'Attributes'){throw 'Plan attributs invalide.'}
    $created=[DateTimeOffset]::Parse($Plan.CreatedUtc,[Globalization.CultureInfo]::InvariantCulture);$expires=[DateTimeOffset]::Parse($Plan.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture)
    if($created -gt [DateTimeOffset]::UtcNow.AddMinutes(1) -or $expires -le [DateTimeOffset]::UtcNow -or $expires -le $created -or ($expires-$created).TotalHours -gt 24.1 -or $Plan.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or $Plan.MachineId -cne (Get-PestoAutomationMachineId) -or $Plan.Domain -ine $script:DOMAINE){throw 'Plan attributs expire ou contexte modifie.'}
    Assert-PestoAttributeChanges $Plan.Changes
}
function Invoke-PestoAttributeMutation {
    param($Plan,$Approval=$null)
    $script:ActiveIntervention=$null;$started=$false;$op=[Guid]::NewGuid().ToString('N')
    try{
        Assert-PestoAttributePlan $Plan
        $pc=Get-PestoAttributeTarget ([Guid]$Plan.ObjectGuid);$adp=Get-ADParams
        if($pc.Name -ine $Plan.Computer -or (Get-PestoParentDN $pc.DistinguishedName) -ine $Plan.SourceOU){throw 'Cible deplacee ou renommee depuis preparation.'}
        foreach($c in $Plan.Changes){
            if([string]$pc.($c.Attribute) -cne $c.Before){throw 'Un attribut a change depuis la preparation.'}
            if($c.ReferenceGuid){$ref=Get-ADObject -Identity ([Guid]$c.ReferenceGuid) -ErrorAction Stop @adp;if(-not $ref -or $ref.DistinguishedName -ine $c.After){throw 'Reference managedBy remplacee ou deplacee.'}}
        }
        $effect=[pscustomobject]@{Action='Attributes';Nom_du_PC=$Plan.Computer;Nouveau_Nom=$Plan.NewName;OU_Actuelle=$Plan.SourceOU;OU_Destination=$Plan.TargetOU;Objet_GUID=$Plan.ObjectGuid;TargetOUGuid='';Domain=$Plan.Domain;DC=$script:DC;ConfigStamp=$Plan.ConfigStamp;Renommer=$false;Deplacer=$false;Reboot=$false;Metadata=$Plan.Metadata;Changes=$Plan.Changes}
        Assert-PestoOperationPolicy $effect $script:PestoPolicy
        Assert-PestoStoredMutationReady -Plan $effect
        Assert-PestoCampaignApproval $effect $Approval
        Start-PestoIntervention -Plan $effect -OperationId $op
        $script:ActiveIntervention|Add-Member Attributes 'NotRequested';$script:ActiveIntervention|Add-Member AttributeChanges $Plan.Changes
        $replace=@{};$clear=@();foreach($c in $Plan.Changes){if($c.After){$replace[$c.Attribute]=$c.After}else{$clear+=@($c.Attribute)}}
        $mutationParams=@{Identity=[Guid]$Plan.ObjectGuid;ErrorAction='Stop'};if($replace.Count){$mutationParams.Replace=$replace};if($clear.Count){$mutationParams.Clear=[string[]]$clear}
        Set-PestoEffect -Name Attributes -Value Requested
        $started=$true
        Set-ADObject @mutationParams @adp
        $after=Get-PestoAttributeTarget ([Guid]$Plan.ObjectGuid)
        foreach($c in $Plan.Changes){if([string]$after.($c.Attribute) -cne $c.After){throw 'Observation apres mutation incomplete.'}}
        Set-PestoEffect -Name Attributes -Value Confirmed
        [void](Complete-PestoIntervention (New-ActionResult 30 'Attributs relus et confirmes.'))
        return New-PestoIntegrationResult -Mode Attributes -ExitCode 0 -State Verified -OperationId $op -MutationStarted $true -Plan $Plan -Message 'Attributs relus par GUID ; diff conserve dans le recu.'
    }catch{
        if($script:ActiveIntervention){try{[void](Complete-PestoIntervention (New-ActionResult $(if($started){97}else{96}) 'Verification des attributs requise.'))}catch{}}
        return New-PestoIntegrationResult -Mode Attributes -ExitCode $(if($started){97}else{96}) -State $(if($started){'Uncertain'}else{'NotStarted'}) -OperationId $op -MutationStarted $started -Message (Protect-PestoLogText $_.Exception.Message)
    }finally{$script:ActiveIntervention=$null}
}
function Get-PestoAttributeObservation {
    param([Guid]$OperationId)
    $receipt=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($OperationId.ToString('N')+'.json'))
    if($receipt.Plan.Domain -ine $script:DOMAINE -or $receipt.Attributes -notin @('Requested','Confirmed')){throw 'Recu attributs incompatible.'}
    Assert-PestoAttributeChanges $receipt.AttributeChanges
    $pc=Get-PestoAttributeTarget ([Guid]$receipt.Plan.Objet_GUID)
    $rows=@(foreach($c in $receipt.AttributeChanges){[pscustomobject]@{Attribute=$c.Attribute;Expected=$c.After;Observed=[string]$pc.($c.Attribute);Matches=([string]$pc.($c.Attribute) -ceq $c.After)}})
    $matched=(@($rows|Where-Object{-not $_.Matches}).Count -eq 0 -and $pc.Name -ieq $receipt.Plan.Nom_du_PC -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $receipt.Plan.OU_Actuelle)
    if($matched -and $env:PESTO_READONLY_SESSION -ne '1'){$receipt.Attributes='Confirmed';$receipt.Phase='Verified';$receipt.ResultCode=30;$receipt.UpdatedUtc=[DateTime]::UtcNow.ToString('o');$receipt.LastStage='Attributes observed';$receipt.VerifiedUtc=[DateTime]::UtcNow.ToString('o');$receipt.VerifiedBy=Get-PestoOperatorSid;Write-PestoIntervention $receipt}
    return [pscustomobject]@{OperationId=$OperationId.ToString('N');ExitCode=$(if($matched){0}else{97});State=$(if($matched){'Verified'}else{'Uncertain'});Changes=$rows;TargetReadOnly=$true;ReplayAllowed=$false}
}

function Initialize-PestoOfflineContext {
    param([string]$RuntimeRoot,[string]$ConfigPath,[switch]$ReadOnly)
    Assert-PestoAutomationPlatform
    [void](Test-PestoPackage -Root (Split-Path $RuntimeRoot -Parent))
    $script:CFG=Read-PestoAutomationJson $ConfigPath -MaximumBytes 1MB
    [void](Set-PestoActiveNamingConvention $script:CFG.NamingConvention)
    $errors=@(Test-CfgValid $script:CFG);if($errors.Count){throw ($errors -join ' ')}
    foreach($flag in @('Simulation','GUI','HorsDomaine','MauvaiseOU','ForceADM','BPVerifNomAD')){if($script:CFG.DEBUG -and (Convert-Value-TF $script:CFG.DEBUG.$flag -Strict)){throw 'Configuration DEBUG interdite pour ODJ.'}}
    $script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY
    if(-not $ReadOnly -and (-not $script:PestoPolicy.AllowOfflineJoin -or $script:PestoPolicy.IncidentMode -or $env:PESTO_READONLY_SESSION -eq '1')){throw 'Jonction hors connexion desactivee par la politique.'}
    if(-not $ReadOnly -and ($script:PestoPolicy.CoordinationRoot -or $script:PestoPolicy.ExcludedGroupGuids.Count)){throw 'ODJ hors ligne incompatible avec une coordination ou exclusion de groupes exigeant AD.'}
    $script:DOMAINE=[string](@($script:CFG.CONF)[0].Domaine);$script:SIM=$false;$script:GUI=$false;$script:PestoReadOnly=$false;$script:DC=''
    $script:OU=@{};foreach($row in $script:CFG.OUBase){$script:OU[$row.Nom]=$row.OU}
    $script:OUV=@{};foreach($row in $script:CFG.OUSite){$script:OUV[$row.Nom]=$row.OU}
    Initialize-PestoCommon -Root $RuntimeRoot
}
function Get-PestoOfflineStore {
    return [IO.Path]::Combine([Environment]::GetFolderPath('CommonApplicationData'),'GP','OfflineJoin')
}
function Get-PestoOfflinePaths {
    param([string]$Id)
    if($Id -cnotmatch '^[a-f0-9]{64}$'){throw 'Identifiant ODJ invalide.'}
    $root=Get-PestoOfflineStore
    [pscustomobject]@{State=(Join-Path $root ($Id+'.json'));Secret=(Join-Path $root ($Id+'.protected'));Plain=(Join-Path $root ($Id+'.odj.tmp'))}
}
function Import-PestoOfflineBlob {
    param([string]$BlobPath,[Guid]$ObjectGuid,[string]$TargetOU,$Metadata=$null)
    $local=Get-PestoJoinLocalStatus
    if($local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2)){throw 'ODJ exige un poste local hors domaine, sans renommage en attente.'}
    if($ObjectGuid -eq [Guid]::Empty -or -not(Test-PestoOUInConfiguredScope $TargetOU) -or (Get-PestoDomainFromDN $TargetOU) -ine $script:DOMAINE){throw 'GUID et OU du compte provisionne requis dans le domaine configure.'}
    Assert-PestoPlainPath $BlobPath;$file=Get-Item -LiteralPath $BlobPath -ErrorAction Stop
    if($file.PSIsContainer -or $file.Length -lt 1 -or $file.Length -gt 1MB){throw 'Blob ODJ vide ou trop volumineux.'}
    $bytes=[IO.File]::ReadAllBytes($file.FullName);$encrypted=$null
    try{
        $sha=Get-PestoBytesHash $bytes;$paths=Get-PestoOfflinePaths $sha
        if([IO.File]::Exists($paths.State) -or [IO.File]::Exists($paths.Secret)){throw 'Ce blob a deja ete importe. Reprendre son observation, jamais le rejouer.'}
        $p=New-PestoPortablePlan -Action Join -Computer $local.Computer -NewName $local.Computer -TargetOU $TargetOU -Domain $script:DOMAINE -ObjectGuid $ObjectGuid.ToString('D') -ConfigStamp (Get-PestoConfigurationSignature $script:CFG) -MachineId $local.MachineId -Metadata $Metadata
        $p.Action='OfflineJoin';$p.PSObject.Properties.Remove('Integrity');$p|Add-Member BlobSHA256 $sha;$p|Add-Member Integrity (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $p))
        # DPAPI LocalMachine ; ACL SYSTEM/Administrateurs sur le stockage, jamais dans le plan ou l'audit.
        $encrypted=(Protect-PestoOfflineBytes $bytes)
        $record=[pscustomobject]@{Schema=1;Mode='OfflineJoin';Id=$sha;State='Imported';Plan=$p;BootUtc=$local.BootUtc;OperationId='';NativeCode=$null;Utc=[DateTime]::UtcNow.ToString('o')}
        Write-PestoJoinReceipt $paths.State $record
        Assert-PestoPlainPath $paths.Secret
        Write-PestoAtomicText $paths.Secret ([Convert]::ToBase64String($encrypted))
        return [pscustomobject]@{State='Imported';ExitCode=0;BlobId=$sha;Plan=$p;SourceRetained=$true;Message='Blob protege localement. Supprimer la source selon votre procedure de secrets ; le logiciel ne la sauvegarde pas.'}
    }finally{[Array]::Clear($bytes,0,$bytes.Length);if($encrypted){[Array]::Clear($encrypted,0,$encrypted.Length)}}
}
function Read-PestoOfflineRecord {
    param([string]$Id)
    $paths=Get-PestoOfflinePaths $Id;$r=Read-PestoAutomationJson $paths.State
    Assert-PestoClosedObject $r @('Schema','Mode','Id','State','Plan','BootUtc','OperationId','NativeCode','Utc') @('Schema','Mode','Id','State','Plan','BootUtc','OperationId','NativeCode','Utc')
    if($r.Schema -ne 1 -or $r.Mode -cne 'OfflineJoin' -or $r.Id -cne $Id -or $r.State -cnotin @('Imported','Requested','PendingRestart','Uncertain','Verified') -or $r.Plan.BlobSHA256 -cne $Id){throw 'Recu ODJ invalide.'}
    $p=$r.Plan
    Assert-PestoClosedObject $p @('Schema','Purpose','Action','CreatedUtc','ExpiresUtc','MachineId','ConfigStamp','Domain','Computer','NewName','SourceOU','TargetOU','ObjectGuid','TargetOUGuid','Type','SiteCode','ServiceCode','Metadata','BlobSHA256','Integrity') @('Schema','Purpose','Action','CreatedUtc','ExpiresUtc','MachineId','ConfigStamp','Domain','Computer','NewName','TargetOU','ObjectGuid','BlobSHA256','Integrity')
    if($p.Schema -ne 1 -or -not(Test-PestoComputerName $p.Computer) -or $p.NewName -cne $p.Computer -or -not(Test-PestoOUPath $p.TargetOU)){throw 'Cible ODJ invalide.'}
    foreach($field in @('BootUtc','Utc')){if($r.$field -is [DateTime]){$r.$field=$r.$field.ToUniversalTime().ToString('o')}}
    foreach($date in @('CreatedUtc','ExpiresUtc')){if($p.$date -is [DateTime]){$p.$date=$p.$date.ToUniversalTime().ToString('o')}}
    $copy=[ordered]@{};foreach($prop in $p.PSObject.Properties){if($prop.Name -ne 'Integrity'){$copy[$prop.Name]=$prop.Value}}
    if($p.Action -cne 'OfflineJoin' -or $p.Purpose -cne 'PestoPreparedPlan' -or $p.Integrity -cne (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -or $p.Domain -ine $script:DOMAINE -or $p.MachineId -ine (Get-PestoAutomationMachineId)){throw 'Identite ou integrite du plan ODJ invalide.'}
    return $r
}
function Invoke-PestoOfflineNative {
    param([string]$Path)
    $windows=[Environment]::GetFolderPath('Windows');$exe=Join-Path $windows 'System32\djoin.exe'
    Assert-PestoPlainPath $Path;Assert-PestoPlainPath $exe
    if($Path -match '["\r\n]' -or $windows -match '["\r\n]'){throw 'Chemin natif invalide.'}
    $info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$exe;$info.Arguments='/requestodj /loadfile "'+$Path+'" /windowspath "'+$windows+'" /localos'
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::new();$process.StartInfo=$info
    try{
        if(-not $process.Start()){throw 'Lancement djoin impossible.'}
        # Sorties natives jamais publiees : elles pourraient contenir des donnees sensibles.
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(120000)){try{$process.Kill()}catch{};throw 'Delai djoin depasse : resultat incertain, aucun rejeu.'}
        return [int]$process.ExitCode
    }finally{$process.Dispose()}
}
function Invoke-PestoOfflineApply {
    param([string]$Id,$Approval=$null)
    $r=Read-PestoOfflineRecord $Id;$paths=Get-PestoOfflinePaths $Id;$p=$r.Plan
    if($r.State -ne 'Imported'){return [pscustomobject]@{ExitCode=97;State=$r.State;BlobId=$Id;ReplayAllowed=$false;Message='Demande deja enregistree ; observer apres redemarrage, sans repetition.'}}
    $local=Get-PestoJoinLocalStatus
    if($local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2) -or $local.Computer -ine $p.Computer -or $local.MachineId -ine $p.MachineId -or $p.ConfigStamp -cne (Get-PestoConfigurationSignature $script:CFG) -or [DateTimeOffset]::Parse($p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture) -le [DateTimeOffset]::UtcNow){throw 'Contexte ODJ change ou delai d application expire.'}
    $effect=[pscustomobject]@{Action='OfflineJoin';Nom_du_PC=$p.Computer;Nouveau_Nom=$p.NewName;OU_Actuelle='';OU_Destination=$p.TargetOU;Objet_GUID='';TargetOUGuid='';Domain=$p.Domain;DC='';ConfigStamp=$p.ConfigStamp;Renommer=$false;Deplacer=$false;Reboot=$false;Metadata=$p.Metadata;BlobSHA256=$Id}
    Assert-PestoOperationPolicy $effect $script:PestoPolicy
    Assert-PestoStoredMutationReady -Plan $effect
    Assert-PestoCampaignApproval $p $Approval
    $secret=$null;$bytes=$null;$started=$false;$op=[Guid]::NewGuid().ToString('N')
    try{
        Assert-PestoPlainPath $paths.Secret;$f=Get-Item -LiteralPath $paths.Secret -ErrorAction Stop;if($f.Length -gt 2MB){throw 'Secret protege invalide.'}
        $secret=[Convert]::FromBase64String([IO.File]::ReadAllText($paths.Secret));$bytes=(Unprotect-PestoOfflineBytes $secret)
        if((Get-PestoBytesHash $bytes) -cne $Id){throw 'Blob decrypte different du plan.'}
        Start-PestoIntervention -Plan $effect -OperationId $op
        $script:ActiveIntervention|Add-Member OfflineJoin 'Requested';Write-PestoIntervention $script:ActiveIntervention
        $r.State='Requested';$r.OperationId=$op;$r.BootUtc=$local.BootUtc;$r.Utc=[DateTime]::UtcNow.ToString('o')
        Write-PestoJoinReceipt $paths.State $r
        $started=$true
        # Fichier ephemere dans le dossier ACL prive ; CreateNew refuse toute collision.
        Assert-PestoPlainPath $paths.Plain;$stream=[IO.File]::Open($paths.Plain,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        $r.NativeCode=Invoke-PestoOfflineNative $paths.Plain
        $r.State=if($r.NativeCode -eq 0){'PendingRestart'}else{'Uncertain'}
        $script:ActiveIntervention.OfflineJoin=$r.State
        [void](Complete-PestoIntervention (New-ActionResult $(if($r.NativeCode -eq 0){10}else{97}) 'Demande ODJ enregistree ; observer apres redemarrage.'))
        Write-PestoJoinReceipt $paths.State $r
        return [pscustomobject]@{ExitCode=$(if($r.NativeCode -eq 0){3010}else{97});State=$r.State;BlobId=$Id;OperationId=$op;RestartRequired=($r.NativeCode -eq 0);ReplayAllowed=$false}
    }catch{
        if($started){$r.State='Uncertain';try{Write-PestoJoinReceipt $paths.State $r}catch{};if($script:ActiveIntervention){try{[void](Complete-PestoIntervention (New-ActionResult 97 'ODJ incertain. Observer ; aucun rejeu.'))}catch{}}}
        throw
    }finally{
        foreach($buffer in @($secret,$bytes)){if($buffer){[Array]::Clear($buffer,0,$buffer.Length)}}
        if($started){foreach($path in @($paths.Plain,$paths.Secret)){Assert-PestoPlainPath $path;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}}
        $script:ActiveIntervention=$null
    }
}
function Get-PestoOfflineObservation {
    param([string]$Id,[string]$RuntimeRoot,$Credential)
    $r=Read-PestoOfflineRecord $Id;$local=Get-PestoJoinLocalStatus;$p=$r.Plan
    if($r.State -eq 'Imported'){throw 'Blob non applique.'}
    $localMatches=$local.PartOfDomain -and $local.Domain -ieq $p.Domain -and $local.Computer -ieq $p.NewName -and $local.MachineId -ieq $p.MachineId -and -not $local.PendingRename -and [DateTimeOffset]::Parse([string]$local.BootUtc) -gt [DateTimeOffset]::Parse([string]$r.BootUtc)
    $secure=$false;$identity=$false
    if($localMatches){
        Import-PestoADModule (Join-Path $RuntimeRoot 'ActiveDirectory.psd1');$script:DC=Get-DomainController $p.Domain;$script:cred=$Credential
        $adp=Get-ADParams;$pc=Get-ADComputer -Identity ([Guid]$p.ObjectGuid) -Properties DistinguishedName,ObjectGUID -ErrorAction Stop @adp
        $identity=$pc.Name -ieq $p.NewName -and [string]$pc.ObjectGUID -ieq $p.ObjectGuid -and (Get-PestoParentDN $pc.DistinguishedName) -ieq $p.TargetOU
        # Observation uniquement : pas de -Repair et aucune nouvelle demande de jonction.
        $secure=[bool](Test-ComputerSecureChannel -Server $script:DC -ErrorAction Stop)
    }
    $state=if($localMatches -and $identity -and $secure){'Verified'}else{'Uncertain'}
    if($state -eq 'Verified' -and $env:PESTO_READONLY_SESSION -ne '1'){
        $ledger=Read-PestoIntervention (Join-Path (Get-PestoInterventionRoot) ($r.OperationId+'.json'))
        if($ledger.Plan.Nom_du_PC -ine $p.Computer -or $ledger.Plan.Domain -ine $p.Domain -or -not $ledger.OfflineJoin){throw 'Recu intervention ODJ incoherent.'}
        $ledger.OfflineJoin='Verified';$ledger.Phase='Verified';$ledger.ResultCode=30;$ledger.UpdatedUtc=[DateTime]::UtcNow.ToString('o');$ledger.LastStage='OfflineJoin observed';$ledger.VerifiedUtc=[DateTime]::UtcNow.ToString('o');$ledger.VerifiedBy=Get-PestoOperatorSid
        Write-PestoIntervention $ledger
        $r.State='Verified';Write-PestoJoinReceipt (Get-PestoOfflinePaths $Id).State $r
    }
    return [pscustomobject]@{State=$state;ExitCode=$(if($state -eq 'Verified'){0}else{97});BlobId=$Id;OperationId=$r.OperationId;IdentityConfirmed=$identity;SecureChannel=$secure;TargetReadOnly=$true;ReplayAllowed=$false}
}
function Invoke-PestoExtensionCommand {
    [CmdletBinding()]
    param([string]$RuntimeRoot,[string]$ConfigPath,$Credential,
        [ValidateSet('Attributes','OfflineImport','OfflineApply','OfflineObserve','AttributeObserve')][string]$Action,
        [Guid]$ObjectGuid=[Guid]::Empty,$Attributes=$null,[string]$TargetOU='',[string]$BlobPath='',[string]$BlobId='',
        [Guid]$OperationId=[Guid]::Empty,[string]$PlanPath='',[string]$OutPlanPath='',[string]$IdempotencyKey='',
        $Metadata=$null,$Approval=$null,[switch]$Execute)
    $gate=$null;$owned=$false
    try{
        $gate=[Threading.Mutex]::new($false,'Global\GP_PostMutation_v1')
        try{$owned=$gate.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Une mutation Pesto est deja en cours.'}
        if(-not $ConfigPath){$ConfigPath=Join-Path $RuntimeRoot 'cfg.json'}
        if($Action -eq 'Attributes' -or $Action -eq 'AttributeObserve'){
            Initialize-PestoHeadlessContext -RuntimeRoot $RuntimeRoot -ConfigPath $ConfigPath -Credential $Credential -ReadOnly:($Action -eq 'AttributeObserve' -or -not $Execute)
            if($Action -eq 'AttributeObserve'){if($Execute){throw 'Observation sans execution.'};return Get-PestoAttributeObservation $OperationId}
            if($PlanPath){$plan=Read-PestoAutomationJson $PlanPath;Assert-PestoAttributePlan $plan;if($Attributes -or $ObjectGuid -ne [Guid]::Empty){throw 'Ne pas combiner plan et changements directs.'}}
            else{$plan=New-PestoAttributePlan $ObjectGuid $Attributes $Metadata}
            if(-not $Execute){if($OutPlanPath){Export-PestoPortablePlan $plan $OutPlanPath};return New-PestoIntegrationResult -Mode Attributes -ExitCode 0 -State Prepared -Plan $plan -Message 'Diff prepare ; aucune mutation.'}
            if(-not $PlanPath -or $OutPlanPath -or -not $IdempotencyKey){throw 'Execution attributs : PlanPath et IdempotencyKey requis, sans export simultane.'}
        }else{
            Initialize-PestoOfflineContext $RuntimeRoot $ConfigPath -ReadOnly:($Action -eq 'OfflineObserve')
            if($Action -eq 'OfflineObserve'){if($Execute){throw 'Observation sans execution.'};return Get-PestoOfflineObservation $BlobId $RuntimeRoot $Credential}
            if(-not $Execute){throw 'Import ou application ODJ exige -Execute explicite.'}
        }
        switch($Action){
            'Attributes'{return Invoke-PestoIdempotentExecution -Key $IdempotencyKey -Payload ([pscustomobject]@{Action='Attributes';Plan=$plan;Approval=$Approval}) -Handler {Invoke-PestoAttributeMutation $plan $Approval}}
            'OfflineImport'{return Import-PestoOfflineBlob $BlobPath $ObjectGuid $TargetOU $Metadata}
            'OfflineApply'{return Invoke-PestoOfflineApply $BlobId $Approval}
        }
    }finally{if($gate){try{if($owned){$gate.ReleaseMutex()}}finally{$gate.Dispose()}};$script:cred=$null;$Credential=$null}
}

function Protect-PestoOfflineBytes {
    param([byte[]]$Bytes)
    Add-Type -AssemblyName System.Security
    return ,([Security.Cryptography.ProtectedData]::Protect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine))
}
function Unprotect-PestoOfflineBytes {
    param([byte[]]$Bytes)
    Add-Type -AssemblyName System.Security
    return ,([Security.Cryptography.ProtectedData]::Unprotect($Bytes,$null,[Security.Cryptography.DataProtectionScope]::LocalMachine))
}

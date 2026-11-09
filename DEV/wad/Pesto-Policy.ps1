#requires -Version 5.1
# Politique métier, indépendante de l'apparence. Aucune connexion au chargement.
function ConvertTo-PestoPolicy {
    param($Value,[switch]$LocalOnly)
    $out=[ordered]@{Schema=1;Scenario=$null;ExcludedNames=@();ExcludedOUs=@();ExcludedGroupGuids=@();
        CoordinationRoot='';CoordinationRequired=$false;AllowPasswordTaskFallback=$false;
        AllowPrecreatedJoin=$false;AllowOfflineJoin=$false;BlockJoinOnClockSkew=$false;MaxReaders=4;ReadAttempts=2;MaxBatch=200;
        NameReservationMinutes=15;ReserveNamesInAD=$false;RandomNameEnabled=$true;LogRetentionDays=30;UnattendedJoinEnabled=$false;UnattendedOperationsEnabled=$false;IncidentMode=$false;AuditEventLogEnabled=$false}
    if($null -eq $Value){if($LocalOnly){return [pscustomobject]$out};return Merge-PestoManagedPolicy ([pscustomobject]$out)}
    Assert-PestoClosedObject -Value $Value -Allowed (@($out.Keys)+@('RandomNameChoice')) -Required @('Schema')
    if(($Value.Schema -isnot [int] -and $Value.Schema -isnot [long]) -or $Value.Schema -ne 1){throw 'Schéma de politique non reconnu.'}
    foreach($name in @('BlockJoinOnClockSkew','CoordinationRequired','AllowPasswordTaskFallback','AllowPrecreatedJoin','AllowOfflineJoin','ReserveNamesInAD','RandomNameEnabled','UnattendedJoinEnabled','UnattendedOperationsEnabled','IncidentMode','AuditEventLogEnabled')){
        if((Test-PestoPropertyPresent $Value $name)){if($Value.$name -isnot [bool]){throw ('La politique '+$name+' exige un booléen JSON.')};$out[$name]=$Value.$name}
    }
    # Migration du réglage numérique : 0/1 désactive, 2..50 active le tirage sur TOUT le périmètre.
    if(Test-PestoPropertyPresent $Value 'RandomNameChoice'){
        $legacy=$Value.RandomNameChoice
        if(($legacy -isnot [int] -and $legacy -isnot [long]) -or $legacy -lt 0 -or $legacy -gt 50){throw 'Limite invalide : RandomNameChoice'}
        $enabled=($legacy -ge 2)
        if((Test-PestoPropertyPresent $Value 'RandomNameEnabled') -and $Value.RandomNameEnabled -ne $enabled){throw 'RandomNameEnabled et RandomNameChoice se contredisent. Conservez uniquement RandomNameEnabled.'}
        $out.RandomNameEnabled=$enabled
    }
    foreach($entry in @(@('MaxReaders',1,8),@('ReadAttempts',1,3),@('MaxBatch',1,200),@('NameReservationMinutes',5,240),@('LogRetentionDays',0,3650))){
        $name=[string]$entry[0]
        if((Test-PestoPropertyPresent $Value $name)){if(($Value.$name -isnot [int] -and $Value.$name -isnot [long]) -or $Value.$name -lt $entry[1] -or $Value.$name -gt $entry[2]){throw ('Limite invalide : '+$name)};$out[$name]=$Value.$name}
    }
    foreach($name in @('ExcludedNames','ExcludedOUs','ExcludedGroupGuids')){
        if((Test-PestoPropertyPresent $Value $name)){
            if($Value.$name -is [string] -or @($Value.$name).Count -gt 200){throw ('Liste invalide : '+$name)}
            $list=[Collections.Generic.List[string]]::new()
            foreach($item in @($Value.$name)){
                if($item -isnot [string] -or -not $item -or $item.Length -gt 4096 -or $item -match '[\x00-\x1f]'){throw 'Valeur de politique invalide.'}
                if($name -eq 'ExcludedNames' -and $item -notmatch '^[A-Za-z0-9*?-]{1,64}$'){throw 'Motif d''exclusion de nom invalide.'}
                if($name -eq 'ExcludedOUs' -and -not(Test-PestoOUPath $item)){throw 'Emplacement exclu invalide.'}
                if($name -eq 'ExcludedGroupGuids'){$g=[Guid]::Empty;if(-not [Guid]::TryParse($item,[ref]$g) -or $g -eq [Guid]::Empty){throw 'GUID de groupe exclu invalide.'}}
                $list.Add($item)
            }
            $out[$name]=@($list|Select-Object -Unique)
        }
    }
    if((Test-PestoPropertyPresent $Value 'CoordinationRoot')){
        $path=[string]$Value.CoordinationRoot
        if($path){
            if($path.Length -gt 240 -or $path -match '[\x00-\x1f"*?]' -or -not [IO.Path]::IsPathRooted($path)){throw 'Chemin de coordination absolu invalide.'}
            $out.CoordinationRoot=[IO.Path]::GetFullPath($path).TrimEnd('\')
        }
    }
    if(Test-PestoPropertyPresent $Value 'Scenario'){$out.Scenario=ConvertTo-PestoScenario $Value.Scenario}
    if($out.CoordinationRequired -and -not $out.CoordinationRoot){throw 'Un emplacement de coordination approuvé est obligatoire pour cette politique.'}
    if($LocalOnly){return [pscustomobject]$out}
    return Merge-PestoManagedPolicy ([pscustomobject]$out)
}

function Assert-PestoOperationPolicy {
    param($Plan,$Policy)
    if($script:PestoReadOnly -or $env:PESTO_READONLY_SESSION -eq '1'){throw 'Mode consultation : aucune mutation autorisée.'}
    $p=ConvertTo-PestoPolicy $Policy
    Assert-PestoScenarioValues $p.Scenario (Get-PestoPlanScenarioValues $Plan)
    if($p.IncidentMode){throw 'Mode incident : les nouvelles mutations sont suspendues. Les diagnostics restent disponibles.'}
    foreach($name in @($Plan.Nom_du_PC,$Plan.Nouveau_Nom)){
        if(-not $name){continue}
        foreach($pattern in $p.ExcludedNames){if([Management.Automation.WildcardPattern]::new($pattern,'IgnoreCase').IsMatch($name)){throw ('Cible exclue par la politique : '+$name)}}
    }
    foreach($ou in @($Plan.OU_Actuelle,$Plan.OU_Destination)){
        if(-not $ou){continue}
        foreach($excluded in $p.ExcludedOUs){if(Test-PestoDNWithinScope -DistinguishedName $ou -Roots @($excluded)){throw 'Un emplacement du plan est exclu par la politique.'}}
    }
    if(-not $Plan.Objet_GUID){return}
    $id=[Guid]::Empty;if(-not [Guid]::TryParse([string]$Plan.Objet_GUID,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identité AD invalide dans la politique.'}
    $adp=Get-ADParams
    $pc=Get-ADComputer -Identity $id -Properties userAccountControl,DistinguishedName -ErrorAction Stop @adp
    if($null -eq $pc.userAccountControl -or ([long]$pc.userAccountControl -band 8192) -ne 0){throw 'Rôle de cible inconnu ou contrôleur de domaine exclu.'}
    foreach($gid in $p.ExcludedGroupGuids){
        $groupId=[Guid]$gid
        $group=Get-ADGroup -Identity $groupId -ErrorAction Stop @adp
        if(-not $group -or [string]$group.ObjectGUID -ine $groupId.ToString('D')){throw 'Identité du groupe exclu non confirmée.'}
        # Identités AD stables : aucun DN avec antislash à réinterpréter dans le filtre ADWS.
        # ObjectGUID binaire (RFC 4515) et DN alternatif <GUID=...> (MS-ADTS 3.1.1.3.1.2.4).
        $member=($id.ToByteArray()|ForEach-Object{'\'+$_.ToString('x2')}) -join ''
        $filter='(&(objectGUID='+$member+')(memberOf:1.2.840.113556.1.4.1941:=<GUID='+$groupId.ToString('D')+'>))'
        $found=@(Get-ADComputer -LDAPFilter $filter -ResultSetSize 1 -ErrorAction Stop @adp)
        if($found.Count){throw 'Le poste appartient à un groupe exclu, directement ou par imbrication.'}
    }
}

function Add-PestoShareConnection {
    <# Note un partage auquel Pesto s'est connecté avec le compte AD, pour le fermer à la fermeture de Pesto. #>
    param([string]$Share)
    if(-not $Share){return}
    if(-not $script:PestoShareConnections){$script:PestoShareConnections=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)}
    [void]$script:PestoShareConnections.Add($Share)
}

function Connect-PestoCoordinationShare {
    <# Poste hors domaine (compte Windows local) : son jeton n'ouvre pas un partage du domaine. Connexion au partage du
       registre avec le compte AD saisi dans Pesto ($script:cred), sans lettre de lecteur ni mot de passe écrit. La
       connexion vaut pour la session Windows ; Pesto la ferme à sa fermeture. Vrai si le partage est joignable ensuite. #>
    param([string]$Root,$Credential)
    $unc=[regex]::Match([string]$Root,'^\\\\([^\\]+)\\([^\\]+)')
    if($null -eq $Credential -or -not $unc.Success){return $false}
    $share='\\'+$unc.Groups[1].Value+'\'+$unc.Groups[2].Value
    if([IO.Directory]::Exists($share)){return $true}
    try{[void](New-PSDrive -Name ('PestoReg'+[Guid]::NewGuid().ToString('N').Substring(0,8)) -PSProvider FileSystem -Root $share -Credential $Credential -Scope Global -ErrorAction Stop)}
    catch{throw ('Registre partagé inaccessible avec le compte '+[string]$Credential.UserName+' : '+$_.Exception.Message)}
    Add-PestoShareConnection $share
    return [IO.Directory]::Exists($share)
}

function Get-PestoCoordinationRoot {
    param($Policy,[string]$Domain)
    $p=ConvertTo-PestoPolicy $Policy
    if(-not $p.CoordinationRoot){return ''}
    $root=$p.CoordinationRoot
    Assert-PestoPlainPath $root
    $marker=Join-Path $root 'pesto-coordination.json'
    Assert-PestoPlainPath $marker
    if(-not [IO.File]::Exists($marker)){
        if(-not (Connect-PestoCoordinationShare -Root $root -Credential $script:cred) -or -not [IO.File]::Exists($marker)){throw 'Coordination non préparée. Aucun partage n''est créé automatiquement.'}
    }
    $file=Get-Item -LiteralPath $marker -ErrorAction Stop
    if($file.Length -gt 4096){throw 'Marqueur de coordination invalide.'}
    $m=[IO.File]::ReadAllText($marker,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
    Assert-PestoClosedObject $m @('Schema','Domain','Purpose') @('Schema','Domain','Purpose')
    if($m.Schema -ne 1 -or $m.Domain -ine $Domain -or $m.Purpose -cne 'PestoCoordination'){throw 'Ce registre de coordination ne correspond pas au domaine.'}
    $locks=Join-Path $root 'locks'
    Assert-PestoPlainPath $locks
    if(-not [IO.Directory]::Exists($locks)){throw 'Dossier de verrous non préparé. Vérifiez les droits du registre partagé.'}
    return $root
}

function Get-PestoCoordinationKeys {
    param($Plan)
    $keys=[Collections.Generic.List[string]]::new()
    if($Plan.Objet_GUID){$keys.Add((Get-PestoStableHash ('machine|'+$Plan.Domain.ToUpperInvariant()+'|'+([Guid]$Plan.Objet_GUID).ToString('N'))))}
    foreach($name in @($Plan.Nom_du_PC,$Plan.Nouveau_Nom)){
        if($name){$keys.Add((Get-PestoStableHash ('name|'+$Plan.Domain.ToUpperInvariant()+'|'+$name.ToUpperInvariant())))}
    }
    return ,@($keys|Sort-Object -Unique)
}

function Enter-PestoCoordination {
    param($Plan,[string]$OperationId,$Policy,[string]$ResumeId='')
    $root=Get-PestoCoordinationRoot -Policy $Policy -Domain $Plan.Domain
    if(-not $root){return [pscustomobject]@{Enabled=$false;Keys=@();Owner=$OperationId}}
    $keys=Get-PestoCoordinationKeys $Plan
    $created=[Collections.Generic.List[string]]::new()
    try {
        foreach($key in $keys){
            $path=Join-Path (Join-Path $root 'locks') ($key+'.json');Assert-PestoPlainPath $path
            if([IO.File]::Exists($path)){
                $f=Get-Item -LiteralPath $path -ErrorAction Stop
                if($f.Length -gt 8192){throw 'Verrou partagé invalide ; aucune mutation.'}
                $old=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)|ConvertFrom-Json -ErrorAction Stop
                if($ResumeId -and $old.OperationId -eq $ResumeId -and $old.Key -ceq $key -and $old.Domain -ieq $Plan.Domain){continue}
                throw ('Une intervention ou réservation détient cette cible dans le registre partagé. Identifiant : '+[string]$old.OperationId+'. Aucune expiration automatique.')
            }
            $lease=[ordered]@{Schema=1;OperationId=$OperationId;Key=$key;Domain=$Plan.Domain;CreatedUtc=[DateTime]::UtcNow.ToString('o');State='Prepared'}
            $bytes=[Text.Encoding]::UTF8.GetBytes(($lease|ConvertTo-Json -Compress))
            $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $created.Add($key)
            try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        }
        return [pscustomobject]@{Enabled=$true;Keys=$keys;Owner=$OperationId;ResumeFrom=$ResumeId}
    }catch{
        # Rien n'est engagé à ce stade. Seuls les fichiers créés par cette tentative sont retirés.
        foreach($key in $created){
            try{$path=Join-Path (Join-Path $root 'locks') ($key+'.json');$v=[IO.File]::ReadAllText($path)|ConvertFrom-Json
                if($v.OperationId -eq $OperationId -and $v.Key -eq $key){[IO.File]::Delete($path)}}catch{}
        }
        throw
    }
}

function Test-PestoOptionalPostCheckReceipt {
    param($Receipt)
    # Classe uniquement une commande terminée. Ne qualifie jamais son observation AD/Windows.
    if($Receipt.OfflineJoin){return $false}
    if(-not $Receipt -or $Receipt.Phase -cne 'PendingRestart'){return $false}
    if($Receipt.PSObject.Properties['ResultCode']){
        if($Receipt.ResultCode -isnot [int] -and $Receipt.ResultCode -isnot [long]){return $false}
        $accepted=($Receipt.ResultCode -in @(10,20,77))
        # Une reprise de déplacement confirmée laisse le code original 89 sur le reçu parent.
        if($Receipt.ResultCode -eq 89 -and $Receipt.Rename -ceq 'Confirmed' -and $Receipt.Move -ceq 'Confirmed'){$accepted=$true}
        if(-not $accepted){return $false}
        if($Receipt.PSObject.Properties['Protection'] -and $Receipt.Protection -cnotin @('NotChanged','Restored')){return $false}
        if($Receipt.PSObject.Properties['Entra'] -and $Receipt.Entra -cnotin @('NotRequested','Skipped','Confirmed')){return $false}
        foreach($effect in @('Rename','Move')){if($Receipt.PSObject.Properties[$effect] -and $Receipt.$effect -cnotin @('NotRequested','Confirmed')){return $false}}
        if($Receipt.JoinEvidence -and $Receipt.JoinEvidence.NativeStatus -cne 'Accepted'){return $false}
        return $true
    }
    # Le reçu local de jonction historique ne comporte pas de code ; son schéma fermé est validé.
    # JoinEvidence n'est pas un champ de ce schéma : un reçu qui le porte sans ResultCode est refusé ici.
    try{[void](Assert-PestoJoinReceiptData $Receipt);return $true}catch{return $false}
}

function Test-PestoAcknowledgedReceipt {
    param($Receipt)
    # Acquittement explicite (15/10) : le reçu garde sa phase, son code et ses effets réels, jamais comptés comme un
    # succès ; il ne bloque plus sa cible. Caduc dès que la phase ou le code du reçu changent après l'acquittement.
    if($null -eq $Receipt -or -not $Receipt.PSObject.Properties['Acknowledged'] -or $null -eq $Receipt.Acknowledged){return $false}
    try{$ack=Assert-PestoAcknowledgement $Receipt.Acknowledged}catch{return $false}
    if([string]$ack.Phase -cne [string]$Receipt.Phase){return $false}
    $code=if($Receipt.PSObject.Properties['ResultCode']){$Receipt.ResultCode}else{$null}
    if($null -eq $code -or $null -eq $ack.ResultCode){return ($null -eq $code -and $null -eq $ack.ResultCode)}
    return ([long]$code -eq [long]$ack.ResultCode)
}

function Test-PestoAcknowledgementNeeded {
    param($Receipt)
    # Reçu qui bloque encore sa cible et peut être acquitté : phase non résolue, ni suivi facultatif ni déjà acquitté.
    if($null -eq $Receipt -or [string]$Receipt.Phase -cnotin @('Running','PendingRestart','Partial','MoveReady','Protection','Uncertain')){return $false}
    return (-not(Test-PestoOptionalPostCheckReceipt $Receipt) -and -not(Test-PestoAcknowledgedReceipt $Receipt))
}

function New-PestoAcknowledgement {
    param([Parameter(Mandatory=$true)]$Receipt,[string]$Utc,[string]$By,[string]$Reason,$Observation=$null)
    # Phase et code recopiés du reçu acquitté : l'acquittement tombe de lui-même si l'un d'eux change ensuite.
    $code=if($Receipt.PSObject.Properties['ResultCode'] -and $null -ne $Receipt.ResultCode){[int]$Receipt.ResultCode}else{$null}
    return Assert-PestoAcknowledgement ([pscustomobject]@{Schema=1;Utc=$Utc;By=$By;Reason=$Reason;Phase=[string]$Receipt.Phase;ResultCode=$code;Observation=$Observation})
}

function Exit-PestoCoordination {
    param($Receipt,$Policy)
    if(-not $Receipt.Coordination -or -not $Receipt.Coordination.Enabled){return}
    if($Receipt.Phase -notin @('Failed','Verified') -and -not(Test-PestoOptionalPostCheckReceipt $Receipt) -and -not(Test-PestoAcknowledgedReceipt $Receipt)){return}
    $root=Get-PestoCoordinationRoot -Policy $Policy -Domain $Receipt.Plan.Domain
    if(-not $root){throw 'La coordination de cette opération doit être configurée pour libérer ses verrous.'}
    $expected=Get-PestoCoordinationKeys $Receipt.Plan
    foreach($key in @($Receipt.Coordination.Keys)){
        if($key -notmatch '^[a-f0-9]{64}$' -or $key -notin $expected){throw 'Clé de coordination inattendue.'}
        $path=Join-Path (Join-Path $root 'locks') ($key+'.json');Assert-PestoPlainPath $path
        if(-not [IO.File]::Exists($path)){continue}
        $entry=[IO.File]::ReadAllText($path)|ConvertFrom-Json -ErrorAction Stop
        if($entry.OperationId -ne $Receipt.OperationId){continue} # un reçu parent garde son verrou
        if($entry.Key -cne $key -or $entry.Domain -ine $Receipt.Plan.Domain){throw 'Verrou partagé modifié. Aucun nettoyage.'}
        [IO.File]::Delete($path)
    }
}

function Test-PestoGlobalSafetyBarrier {
    if(-not $script:MutationUncertain){return $false}
    $ids=@($script:QueueOperationIds)
    if(-not $ids.Count){return $true} # ancien verrou non rattaché conservé
    foreach($value in $ids){
        $id=[Guid]::Empty
        if(-not [Guid]::TryParse([string]$value,[ref]$id) -or $id -eq [Guid]::Empty){return $true}
        if(-not [IO.File]::Exists((Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json')))){return $true}
    }
    # Le moteur relit tous ces reçus au moment de l'engagement : aucune approbation ici.
    return $false
}

function Test-PestoDirectTargetBarrier {
    param([string]$Computer='')
    if(-not $script:DirectLocked){return $false}
    $r=$script:DirectReceipt
    if(-not $r -or -not $r.Plan){return $true}
    if((Test-PestoOptionalPostCheckReceipt $r) -or (Test-PestoAcknowledgedReceipt $r)){return $false}
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse([string]$r.OperationId,[ref]$id) -or $id -eq [Guid]::Empty){return $true}
    if(-not [IO.File]::Exists((Join-Path (Get-PestoInterventionRoot) ($id.ToString('N')+'.json')))){return $true}
    if(-not $Computer){return $false} # les cibles du lot seront vérifiées une à une
    return ($Computer -in @($r.Plan.Nom_du_PC,$r.Plan.Nouveau_Nom))
}

function ConvertTo-PestoScenario {
    param($Value)
    if($null -eq $Value){return $null}
    Assert-PestoClosedObject $Value @('Schema','Name','Required','Allowed','Locked') @('Schema','Name','Required','Allowed','Locked')
    if($Value.Schema -ne 1 -or $Value.Name -isnot [string] -or $Value.Name -notmatch '^[^\x00-\x1f]{1,80}$'){throw 'Scenario invalide.'}
    $fields=@('Type','SiteCode','ServiceCode','TargetOU')
    if($Value.Required -is [string] -or @($Value.Required).Count -gt 4){throw 'Champs obligatoires invalides.'}
    foreach($name in $Value.Required){if($name -cnotin $fields){throw 'Champ obligatoire inconnu.'}}
    foreach($map in @($Value.Allowed,$Value.Locked)){
        Assert-PestoClosedObject $map $fields @()
        foreach($p in $map.PSObject.Properties){
            $values=@($p.Value)
            if($values.Count -lt 1 -or $values.Count -gt 200){throw 'Liste de scenario invalide.'}
            foreach($v in $values){if($v -isnot [string] -or -not $v -or $v.Length -gt 4096 -or $v -match '[\x00-\x1f\x7f]'){throw 'Valeur de scenario invalide.'}}
        }
    }
    foreach($p in $Value.Locked.PSObject.Properties){
        if($p.Value -isnot [string]){throw 'Un verrou exige une valeur unique.'}
        if($Value.Allowed.PSObject.Properties[$p.Name] -and $p.Value -cnotin @($Value.Allowed.($p.Name))){throw 'Verrou hors des valeurs autorisees.'}
    }
    return $Value
}

function Assert-PestoScenarioValues {
    param($Scenario,$Values)
    $s=ConvertTo-PestoScenario $Scenario;if(-not $s){return}
    foreach($field in @('Type','SiteCode','ServiceCode','TargetOU')){
        $value=[string]$Values.$field
        if($field -cin @($s.Required) -and -not $value){throw ('Scenario '+$s.Name+' : champ obligatoire '+$field)}
        if($s.Allowed.PSObject.Properties[$field] -and $value -cnotin @($s.Allowed.$field)){throw ('Scenario '+$s.Name+' : valeur interdite pour '+$field)}
        if($s.Locked.PSObject.Properties[$field] -and $value -cne $s.Locked.$field){throw ('Scenario '+$s.Name+' : champ verrouille '+$field)}
    }
}

function Get-PestoPlanScenarioValues {
    param($Plan)
    $parts=ConvertTo-PestoNameParts ([string]$Plan.Nouveau_Nom)
    return [pscustomobject]@{Type=[string]$parts.Type;SiteCode=[string]$parts.Site;ServiceCode=[string]$parts.Service;TargetOU=[string]$Plan.OU_Destination}
}

# La confiance provient uniquement de HKLM ; aucun plan ne peut ajouter son signataire.
function Get-PestoCampaignPolicy {
    if([Environment]::OSVersion.Platform -ne 'Win32NT'){return $null}
    $key=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SOFTWARE\Policies\M4D\Pesto',$false)
    if(-not $key){return $null}
    try{
        if('CampaignApprovalJson' -cnotin $key.GetValueNames()){return $null}
        if($key.GetValueKind('CampaignApprovalJson') -ne [Microsoft.Win32.RegistryValueKind]::String){throw 'Politique approbation invalide.'}
        $text=[string]$key.GetValue('CampaignApprovalJson');if($text.Length -gt 65536){throw 'Politique approbation trop volumineuse.'}
        $p=$text|ConvertFrom-Json -ErrorAction Stop
        Assert-PestoClosedObject $p @('Schema','Campaigns','Signers') @('Schema','Campaigns','Signers')
        if($p.Schema -ne 1 -or $p.Campaigns -is [string] -or @($p.Campaigns).Count -gt 200 -or @($p.Signers).Count -gt 50){throw 'Politique approbation invalide.'}
        foreach($c in $p.Campaigns){if($c -isnot [string] -or -not $c -or $c.Length -gt 120 -or $c -match '[\x00-\x1f]'){throw 'Campagne invalide.'}}
        foreach($s in $p.Signers){Assert-PestoClosedObject $s @('CertificateSHA256','Sid') @('CertificateSHA256','Sid');if($s.CertificateSHA256 -cnotmatch '^[a-f0-9]{64}$' -or $s.Sid -notmatch '^S-1-[0-9-]+$'){throw 'Signataire invalide.'}}
        return $p
    }finally{$key.Dispose()}
}
function Get-PestoOperatorSid { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Get-PestoBytesHash {
    param([byte[]]$Bytes)
    $h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Get-PestoCampaignPlanHash {
    param($Plan)
    # L'accord couvre l'effet, toutes les identites et le contexte de configuration.
    if($Plan.Purpose -eq 'PestoPreparedPlan'){
        $data=[ordered]@{Action=[string]$Plan.Action;Computer=[string]$Plan.Computer;NewName=[string]$Plan.NewName;SourceOU=[string]$Plan.SourceOU;TargetOU=[string]$Plan.TargetOU;ObjectGuid=[string]$Plan.ObjectGuid;TargetOUGuid=[string]$Plan.TargetOUGuid;Domain=[string]$Plan.Domain;ConfigStamp=[string]$Plan.ConfigStamp;MachineId=[string]$Plan.MachineId;Metadata=$Plan.Metadata;Changes=$Plan.Changes;BlobSHA256=$Plan.BlobSHA256}
    }else{
        $action=if($Plan.Action){[string]$Plan.Action}elseif($Plan.Renommer -and $Plan.Deplacer){'RenameMove'}elseif($Plan.Renommer){'Rename'}elseif($Plan.Deplacer){'Move'}else{'Join'}
        $data=[ordered]@{Action=$action;Computer=[string]$Plan.Nom_du_PC;NewName=[string]$Plan.Nouveau_Nom;SourceOU=[string]$Plan.OU_Actuelle;TargetOU=[string]$Plan.OU_Destination;ObjectGuid=[string]$Plan.Objet_GUID;TargetOUGuid=[string]$Plan.TargetOUGuid;Domain=[string]$Plan.Domain;ConfigStamp=[string]$Plan.ConfigStamp;MachineId=(Get-PestoAutomationMachineId);Metadata=$Plan.Metadata;Changes=$Plan.Changes;BlobSHA256=$Plan.BlobSHA256}
    }
    return Get-PestoStableHash (ConvertTo-PestoCanonicalValue $data)
}
function New-PestoCampaignApproval {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object[]]$Plans,[Parameter(Mandatory=$true)][Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,[ValidateRange(1,1440)][int]$Minutes=60)
    if($Plans.Count -lt 1 -or $Plans.Count -gt 200){throw 'Une campagne contient 1 a 200 plans.'}
    $campaign=[string]$Plans[0].Metadata.Campaign;if(-not $campaign){throw 'Campagne requise dans les plans.'}
    $hashes=@(foreach($p in $Plans){if($p.Metadata.Campaign -cne $campaign -or $p.Purpose -cne 'PestoPreparedPlan'){throw 'Plans de campagnes differentes.'};Get-PestoCampaignPlanHash $p})
    $payload=[pscustomobject][ordered]@{Schema=1;Purpose='PestoCampaignApproval';Campaign=$campaign;ApproverSid=(Get-PestoOperatorSid);CreatedUtc=[DateTime]::UtcNow.ToString('o');ExpiresUtc=[DateTime]::UtcNow.AddMinutes($Minutes).ToString('o');PlanHashes=@($hashes|Sort-Object -Unique)}
    $bytes=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 5 -Compress))
    $key=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if(-not $key -or $key.KeySize -lt 2048){throw 'Cle privee RSA 2048 bits minimum requise.'}
    try{$signature=$key.SignData($bytes,[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)}finally{$key.Dispose()}
    return [pscustomobject]@{Schema=1;Payload=[Convert]::ToBase64String($bytes);Certificate=[Convert]::ToBase64String($Certificate.RawData);Signature=[Convert]::ToBase64String($signature)}
}
function Assert-PestoCampaignApproval {
    param($Plan,$Approval)
    $policy=Get-PestoCampaignPolicy
    $campaign=[string]$Plan.Metadata.Campaign
    if(-not $policy -or ($campaign -cnotin @($policy.Campaigns) -and '*' -cnotin @($policy.Campaigns))){return}
    if(-not $campaign){throw 'Campagne obligatoire pour la politique approbation.'}
    Assert-PestoClosedObject $Approval @('Schema','Payload','Certificate','Signature') @('Schema','Payload','Certificate','Signature')
    if($Approval.Schema -ne 1){throw 'Accord incompatible.'}
    foreach($field in @('Payload','Certificate','Signature')){if($Approval.$field -isnot [string] -or $Approval.$field.Length -gt 65536){throw 'Accord invalide.'}}
    $bytes=[Convert]::FromBase64String($Approval.Payload);$raw=[Convert]::FromBase64String($Approval.Certificate)
    $pin=Get-PestoBytesHash $raw;$signers=@($policy.Signers|Where-Object{$_.CertificateSHA256 -ceq $pin})
    if($signers.Count -ne 1){throw 'Certificat approbateur non approuve.'}
    $cert=[Security.Cryptography.X509Certificates.X509Certificate2]::new($raw);$key=$null
    try{
        if([DateTime]::UtcNow -lt $cert.NotBefore.ToUniversalTime() -or [DateTime]::UtcNow -ge $cert.NotAfter.ToUniversalTime()){throw 'Certificat approbateur expire.'}
        $key=[Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($cert)
        if(-not $key -or $key.KeySize -lt 2048 -or -not $key.VerifyData($bytes,[Convert]::FromBase64String($Approval.Signature),[Security.Cryptography.HashAlgorithmName]::SHA256,[Security.Cryptography.RSASignaturePadding]::Pkcs1)){throw 'Signature approbation invalide.'}
        $p=([Text.UTF8Encoding]::new($false,$true).GetString($bytes))|ConvertFrom-Json -ErrorAction Stop
        Assert-PestoClosedObject $p @('Schema','Purpose','Campaign','ApproverSid','CreatedUtc','ExpiresUtc','PlanHashes') @('Schema','Purpose','Campaign','ApproverSid','CreatedUtc','ExpiresUtc','PlanHashes')
        foreach($date in @('CreatedUtc','ExpiresUtc')){if($p.$date -is [DateTime]){$p.$date=$p.$date.ToUniversalTime().ToString('o')}}
        $created=[DateTimeOffset]::Parse([string]$p.CreatedUtc,[Globalization.CultureInfo]::InvariantCulture);$expires=[DateTimeOffset]::Parse([string]$p.ExpiresUtc,[Globalization.CultureInfo]::InvariantCulture)
        if($p.Schema -ne 1 -or $p.Purpose -cne 'PestoCampaignApproval' -or $p.Campaign -cne $campaign -or $p.ApproverSid -cne $signers[0].Sid -or $p.ApproverSid -ceq (Get-PestoOperatorSid) -or $created -gt [DateTimeOffset]::UtcNow.AddMinutes(1) -or $expires -le [DateTimeOffset]::UtcNow -or $expires -le $created -or ($expires-$created).TotalMinutes -gt 1440.1){throw 'Identite, campagne ou validite de l accord refusee.'}
        if($p.PlanHashes -is [string] -or @($p.PlanHashes).Count -gt 200 -or (Get-PestoCampaignPlanHash $Plan) -cnotin @($p.PlanHashes)){throw 'Plan absent ou modifie depuis l approbation.'}
    }finally{if($key){$key.Dispose()};$cert.Dispose()}
}

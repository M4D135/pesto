#requires -Version 5.1
# Contrats d'intégration. Aucun chargement AD, accès réseau ou écriture à l'import.

function ConvertTo-PestoDeploymentMetadata {
    param($Value,[switch]$LegacyReceipt)
    $out=[ordered]@{}
    if($null -eq $Value){return [pscustomobject]$out}
    $allowed=@('Campaign','Sequence','Stage','DeploymentBuild','Orchestrator')
    # Anciens reçus lisibles ; ces champs ne sont jamais admis dans une nouvelle demande.
    $accepted=if($LegacyReceipt){$allowed+@('Ticket','AssetId')}else{$allowed}
    Assert-PestoClosedObject -Value $Value -Allowed $accepted -Required @()
    foreach($name in $accepted){
        if(-not(Test-PestoPropertyPresent $Value $name)){continue}
        $v=$Value.$name
        if($v -isnot [string] -or $v.Length -gt 120 -or $v -match '[\x00-\x1f\x7f]' -or $v -match '(?i)(password|passwd|token|secret)\s*[:=]'){
            throw ('Métadonnée invalide : '+$name+'. Texte court uniquement, aucun secret.')
        }
        if($name -cin $allowed){$out[$name]=$v.Trim()}
    }
    return [pscustomobject]$out
}

function Read-PestoAutomationJson {
    param([Parameter(Mandatory=$true)][string]$Path,[int]$MaximumBytes=65536)
    if(-not[IO.Path]::IsPathRooted($Path)){throw 'Un chemin absolu est requis.'}
    Assert-PestoPlainPath $Path
    $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($f.PSIsContainer -or $f.Length -gt $MaximumBytes){throw 'Document absent ou trop volumineux.'}
    return ([IO.File]::ReadAllText($f.FullName,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -ErrorAction Stop)
}

function Get-PestoAutomationMachineId {
    $value=[string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    $id=[Guid]::Empty
    if(-not[Guid]::TryParse($value,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identité de la machine opérateur non confirmée.'}
    return $id.ToString('D')
}

function Get-PestoAutomationStore {
    $base=[Environment]::GetFolderPath('CommonApplicationData')
    if(-not $base){throw 'ProgramData indisponible.'}
    return [IO.Path]::Combine($base,'GP','Automation')
}

function Initialize-PestoHeadlessAudit {
    param([string]$RuntimeRoot)
    Initialize-PestoRuntimeTypes -Root $RuntimeRoot
    Initialize-AuditLog -PreferredDir (Join-Path (Get-PestoAutomationStore) 'logs')
    if(-not(Test-PestoAuditWritable)){throw 'Audit indisponible avant exécution.'}
}

function Enable-PestoHeadlessEventStream {
    param($Monitor)
    if(-not $Monitor){throw 'Moniteur silencieux absent.'}
    $Monitor.AuditStream=$true
    $Monitor.AuditSink={
        param($Entry)
        $auditEntry=New-PestoStructuredEvent -Message $Entry.Text -Level $Entry.Level -Context $Entry.Context `
            -OperationId $Entry.OperationId -WorkerId $Entry.WorkerId -Stage $Entry.Stage -BuildSHA256 $Entry.BuildSHA256 -Utc $Entry.Time
        return [bool](Write-PestoStructuredEvent -Event $auditEntry)
    }
}
function Write-PestoHeadlessEvents {
    param($Monitor)
    if($null -eq $Monitor -or $null -eq $Monitor.Events -or -not $script:PestoAuditWriter){return}
    $item=$null;$recovered=0;$lost=0
    while($Monitor.Events.TryDequeue([ref]$item)){
        try{
            $auditEntry=New-PestoStructuredEvent -Message $item.Text -Level $item.Level -Context $item.Context `
                -OperationId $item.OperationId -WorkerId $item.WorkerId -Stage $item.Stage -BuildSHA256 $item.BuildSHA256 -Utc $item.Time
            if(Write-PestoStructuredEvent -Event $auditEntry){$recovered++}else{$lost++}
        }catch{$lost++}
        $item=$null
    }
    if($lost -gt 0){$script:PestoAuditLost=$true}
    if($Monitor.AuditStream -or $Monitor.DroppedEvents -gt 0 -or $lost -gt 0){
        $kind=if($Monitor.AuditStreamFailed -gt 0 -or $Monitor.DroppedEvents -gt 0 -or $lost -gt 0){'warn'}else{'info'}
        Write-AuditLine -Text ('Audit : '+[string]$Monitor.AuditStreamed+' événement(s) acceptés en continu, '+$recovered+' en reprise, '+($lost+[int]$Monitor.DroppedEvents)+' non conservé(s).') -Kind $kind
    }
}
function Close-PestoHeadlessAudit {
    if(-not $script:PestoAuditWriter){return}
    $closed=$false
    try{$closed=[bool]$script:PestoAuditWriter.Close(2000)}catch{$closed=$false}
    finally{$script:PestoAuditWriter=$null}
    if(-not $closed -or $script:PestoAuditLost){
        # Canal erreur uniquement : ne pas corrompre le JSON ni transformer un effet accompli en refus.
        [Console]::Error.WriteLine('PESTO_AUDIT_INCOMPLETE : journal partiellement écrit ou vidage non confirmé ; conserver les reçus.')
    }
}

function New-PestoIntegrationResult {
    param([string]$Mode,[int]$ExitCode,[string]$State,[string]$Message,$Plan=$null,
        [string]$OperationId='',[bool]$MutationStarted=$false,$EngineCode=$null,$Metadata=$null)
    [pscustomobject]@{Schema=1;Mode=$Mode;State=$State;ExitCode=$ExitCode;EngineCode=$EngineCode;
        RestartRequired=($ExitCode -eq 3010);MutationStarted=$MutationStarted;OperationId=$OperationId;
        Utc=[DateTime]::UtcNow.ToString('o');Message=(Protect-PestoLogText $Message);Plan=$Plan;
        Metadata=(ConvertTo-PestoDeploymentMetadata $Metadata);Replayed=$false}
}

function Invoke-PestoIdempotentExecution {
    param([Parameter(Mandatory=$true)][string]$Key,[Parameter(Mandatory=$true)]$Payload,
        [Parameter(Mandatory=$true)][scriptblock]$Handler)
    if($Key -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$'){throw 'Clé idempotente : 1 à 128 caractères ASCII (lettres, chiffres, . _ : / -).'}
    $machine=Get-PestoAutomationMachineId
    $keyHash=Get-PestoStableHash ('PestoAutomation|'+$Key)
    $payloadHash=Get-PestoStableHash (ConvertTo-PestoCanonicalValue $Payload)
    $path=Join-Path (Get-PestoAutomationStore) ($keyHash+'.json')
    Assert-PestoPlainPath $path
    $gate=$null;$owned=$false;$started=$false
    try{
        $gate=[Threading.Mutex]::new($false,('Global\GP_Automation_'+$keyHash))
        try{$owned=$gate.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){throw 'Cette demande est déjà en cours. Aucun nouvel essai lancé.'}
        if([IO.File]::Exists($path)){
            $saved=Read-PestoAutomationJson $path
            Assert-PestoClosedObject $saved @('Schema','KeyHash','PayloadHash','MachineId','Status','Utc','Result') @('Schema','KeyHash','PayloadHash','MachineId','Status','Utc','Result')
            if(($saved.Schema -isnot [int] -and $saved.Schema -isnot [long]) -or $saved.Schema -ne 1 -or $saved.KeyHash -cne $keyHash -or $saved.PayloadHash -cne $payloadHash -or $saved.MachineId -ine $machine){throw 'Clé déjà utilisée pour une autre demande, configuration ou machine. Aucun rejeu.'}
            if($saved.Status -ceq 'Completed' -and $saved.Result -and ($saved.Result.ExitCode -is [int] -or $saved.Result.ExitCode -is [long])){
                $saved.Result|Add-Member -NotePropertyName Replayed -NotePropertyValue $true -Force
                return $saved.Result
            }
            return New-PestoIntegrationResult -Mode ([string]$Payload.Action) -ExitCode 97 -State Uncertain -Message 'Tentative antérieure enregistrée sans résultat final. Examiner les reçus ; aucune répétition automatique.'
        }
        if($env:PESTO_READONLY_SESSION -eq '1'){throw 'Session en consultation : exécution interdite.'}
        $record=[pscustomobject]@{Schema=1;KeyHash=$keyHash;PayloadHash=$payloadHash;MachineId=$machine;Status='Started';Utc=[DateTime]::UtcNow.ToString('o');Result=$null}
        # Stockage administrateur/SYSTEM, atomique et durable AVANT la première mutation.
        Write-PestoJoinReceipt -Path $path -Receipt $record
        $started=$true
        $returned=@(& $Handler)
        if($returned.Count -ne 1 -or -not $returned[0] -or $returned[0].ExitCode -isnot [int]){throw 'Résultat du moteur absent ou ambigu.'}
        $result=$returned[0]
        # Un refus 96 NotStarted, sans mutation, reste enregistré. Rejouer la même clé
        # restitue ce refus. Une nouvelle tentative exige une nouvelle clé : effacer
        # le registre transformerait un refus consigné en rejeu silencieux.
        # Projection fermée : jamais Request, credentials, logs bruts ou objets AD.
        $safe=[ordered]@{}
        foreach($field in @('Schema','Mode','State','ExitCode','EngineCode','RestartRequired','MutationStarted','OperationId','Utc','Message','Plan','PreparedPlan','Metadata','Checks','CandidateCount','Replayed')){
            if(Test-PestoPropertyPresent $result $field){$safe[$field]=$result.$field}
        }
        $record.Status='Completed';$record.Utc=[DateTime]::UtcNow.ToString('o');$record.Result=[pscustomobject]$safe
        if([Text.Encoding]::UTF8.GetByteCount(($record|ConvertTo-Json -Depth 8)) -gt 65536){throw 'Résultat trop volumineux pour le registre idempotent.'}
        Write-PestoJoinReceipt -Path $path -Receipt $record
        return $result
    }catch{
        if($started){return New-PestoIntegrationResult -Mode ([string]$Payload.Action) -ExitCode 97 -State Uncertain -Message ('Résultat à examiner ; clé conservée sans rejeu : '+$_.Exception.Message)}
        throw
    }finally{if($gate){try{if($owned){$gate.ReleaseMutex()}}finally{$gate.Dispose()}}}
}

function New-PestoPortablePlan {
    param([ValidateSet('Join','Rename','Move','RenameMove')][string]$Action,[string]$ConfigStamp,
        [string]$Computer,[string]$NewName,[string]$TargetOU,[string]$Domain,[string]$ObjectGuid='',
        [string]$TargetOUGuid='',[string]$SourceOU='',[string]$Type='',[string]$SiteCode='',
        [string]$ServiceCode='',$Metadata=$null,[string]$MachineId)
    $plan=[pscustomobject][ordered]@{Schema=1;Purpose='PestoPreparedPlan';Action=$Action;
        CreatedUtc=[DateTime]::UtcNow.ToString('o');ExpiresUtc=[DateTime]::UtcNow.AddHours(24).ToString('o');
        MachineId=$MachineId;ConfigStamp=$ConfigStamp;Domain=$Domain;Computer=$Computer;NewName=$NewName;
        SourceOU=$SourceOU;TargetOU=$TargetOU;ObjectGuid=$ObjectGuid;TargetOUGuid=$TargetOUGuid;
        Type=$Type;SiteCode=$SiteCode;ServiceCode=$ServiceCode;
        Metadata=(ConvertTo-PestoDeploymentMetadata $Metadata)}
    $hash=Get-PestoStableHash (ConvertTo-PestoCanonicalValue $plan)
    $plan|Add-Member -NotePropertyName Integrity -NotePropertyValue $hash
    return $plan
}

function Assert-PestoPortablePlan {
    param($Plan,[string]$ConfigStamp,[string]$MachineId,[string]$Action)
    $fields=@('Schema','Purpose','Action','CreatedUtc','ExpiresUtc','MachineId','ConfigStamp','Domain','Computer','NewName','SourceOU','TargetOU','ObjectGuid','TargetOUGuid','Type','SiteCode','ServiceCode','Metadata','Integrity')
    Assert-PestoClosedObject $Plan $fields $fields
    # PowerShell 7 peut convertir automatiquement les dates JSON ; le contrat exporte UTC 'o'.
    foreach($dateField in @('CreatedUtc','ExpiresUtc')){
        if($Plan.$dateField -is [DateTime]){$Plan.$dateField=$Plan.$dateField.ToUniversalTime().ToString('o')}
    }
    if(($Plan.Schema -isnot [int] -and $Plan.Schema -isnot [long]) -or $Plan.Schema -ne 1 -or $Plan.Purpose -cne 'PestoPreparedPlan' -or $Plan.Action -cnotin @('Join','Rename','Move','RenameMove')){throw 'Plan incompatible.'}
    foreach($field in @($fields|Where-Object{$_ -notin @('Schema','Metadata')})){
        if($Plan.$field -isnot [string] -or $Plan.$field.Length -gt 4096 -or $Plan.$field -match '[\x00-\x1f\x7f]'){throw ('Champ du plan invalide : '+$field)}
    }
    $copy=[ordered]@{};foreach($field in @($fields|Where-Object{$_ -ne 'Integrity'})){$copy[$field]=$Plan.$field}
    if($Plan.Integrity -cnotmatch '^[a-f0-9]{64}$' -or (Get-PestoStableHash (ConvertTo-PestoCanonicalValue $copy)) -cne $Plan.Integrity){throw 'Intégrité du plan invalide (empreinte de cohérence, pas signature).'}
    $created=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse($Plan.CreatedUtc,[ref]$created) -or -not[DateTimeOffset]::TryParse($Plan.ExpiresUtc,[ref]$expires) -or
        $created -gt [DateTimeOffset]::UtcNow.AddMinutes(1) -or $expires -le [DateTimeOffset]::UtcNow -or $expires -le $created -or ($expires-$created).TotalHours -gt 24.1){throw 'Plan expiré ou datation invalide. Préparez de nouveau.'}
    if($Plan.ConfigStamp -cne $ConfigStamp -or $Plan.MachineId -ine $MachineId -or ($Action -and $Plan.Action -cne $Action)){throw 'Le plan appartient à un autre contexte. Nouvelle préparation requise.'}
    if(-not(Test-PestoComputerName $Plan.Computer) -or -not(Test-PestoComputerName $Plan.NewName) -or -not(Test-PestoDnsName $Plan.Domain) -or -not(Test-PestoOUPath $Plan.TargetOU)){throw 'Cible du plan invalide.'}
    [void](ConvertTo-PestoDeploymentMetadata $Plan.Metadata)
    return $Plan
}

function Export-PestoPortablePlan {
    param($Plan,[Parameter(Mandatory=$true)][string]$Path)
    if(-not[IO.Path]::IsPathRooted($Path)){throw 'Chemin de plan absolu requis.'}
    Assert-PestoPlainPath $Path
    $text=$Plan|ConvertTo-Json -Depth 8
    if([Text.Encoding]::UTF8.GetByteCount($text) -gt 65536){throw 'Plan trop volumineux.'}
    # Ne remplace jamais silencieusement un plan déjà transmis à un orchestrateur.
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes($text);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}

function Initialize-PestoHeadlessContext {
    param([string]$RuntimeRoot,[string]$ConfigPath,$Credential,[switch]$ReadOnly)
    Assert-PestoAutomationPlatform
    [void](Test-PestoPackage -Root (Split-Path -Parent $RuntimeRoot))
    $script:PestoBuildSHA256=(Get-FileHash -LiteralPath (Join-Path (Split-Path -Parent $RuntimeRoot) 'Pesto.exe') -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    $script:CFG=Read-PestoAutomationJson -Path $ConfigPath -MaximumBytes 1MB
    [void](Set-PestoActiveNamingConvention $script:CFG.NamingConvention)
    $errors=@(Test-CfgValid $script:CFG);if($errors.Count){throw ($errors -join ' ')}
    foreach($flag in @('Simulation','GUI','HorsDomaine','MauvaiseOU','ForceADM','BPVerifNomAD')){
        if($script:CFG.DEBUG -and (Convert-Value-TF $script:CFG.DEBUG.$flag -Strict)){throw ('DEBUG.'+$flag+' doit être désactivé.')}
    }
    if($null -ne $Credential -and ($Credential -isnot [Management.Automation.PSCredential] -or -not $Credential.UserName -or $Credential.Password.Length -lt 1)){throw 'Credential doit être un PSCredential non vide fourni en mémoire.'}
    $script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY
    if(-not $ReadOnly -and (-not $script:PestoPolicy.UnattendedOperationsEnabled -or $script:PestoPolicy.IncidentMode -or $env:PESTO_READONLY_SESSION -eq '1')){throw 'Automatisation des opérations désactivée, mode incident ou consultation actif.'}
    $conf=@($script:CFG.CONF)[0]
    $script:SIM=$false;$script:GUI=$false;$script:PestoReadOnly=[bool]$ReadOnly;$script:cred=$Credential;$script:ActiveIntervention=$null
    $script:DOMAINE=([string]$conf.Domaine).Trim().TrimEnd('.');$script:PREFIXE=([string]$conf.Prefixe).Trim()
    $script:PRD=Convert-Value-TF $conf.DirectProd -Strict;$script:PREPRODSITE=[string]$conf.PreprodSite;$script:RuntimeTags=$null
    $script:OU=@{};foreach($row in $script:CFG.OUBase){$script:OU[[string]$row.Nom]=[string]$row.OU}
    $script:OUV=@{};foreach($row in $script:CFG.OUSite){$script:OUV[[string]$row.Nom]=[string]$row.OU}
    $script:OU_POSTES=$script:OU.ROOT;$script:OU_SCAN=if($conf.OUScanNoms){[string]$conf.OUScanNoms}else{$script:OU_POSTES}
    $script:CLEAR_PROTECTION=Convert-Value-TF $conf.ClearProtectionOnMove -Default $true
    $script:INDOMAIN=[bool](Get-PestoJoinLocalStatus).PartOfDomain
    if(-not $ReadOnly -and -not $script:INDOMAIN){throw 'Renommage et déplacement silencieux nécessitent un poste opérateur membre du domaine.'}
    Initialize-PestoCommon -Root $RuntimeRoot
    Import-PestoADModule -ADModulePath (Join-Path $RuntimeRoot 'ActiveDirectory.psd1')
    $script:DC=Get-DomainController $script:DOMAINE
    $adp=Get-ADParams;$domain=Get-ADDomain -ErrorAction Stop @adp
    if($domain.DNSRoot -ine $script:DOMAINE){throw 'Le contrôleur découvert ne correspond pas au domaine configuré.'}
}

function Invoke-PestoUnattendedOperation {
    [CmdletBinding()]
    param([string]$RuntimeRoot,[string]$ConfigPath,$Credential,[ValidateSet('Rename','Move','RenameMove')][string]$Action,
        [string]$Computer,[string]$NewName='',[string]$TargetOU='',
        $Metadata=$null,$PreparedPlan=$null,$Approval=$null,[switch]$Execute)
    # Le catch ne doit pas hériter d’une opération ou de métadonnées de l’appelant.
    $request=$null;$monitor=$null;$portable=$null;$meta=$null;$op=''
    try{
        Initialize-PestoHeadlessContext -RuntimeRoot $RuntimeRoot -ConfigPath $ConfigPath -Credential $Credential
        $meta=ConvertTo-PestoDeploymentMetadata $Metadata
        if(-not(Test-PestoComputerName $Computer)){throw 'Nom du poste source invalide.'}
        $stamp=Get-PestoConfigurationSignature $script:CFG;$machine=Get-PestoAutomationMachineId
        if($PreparedPlan){
            [void](Assert-PestoPortablePlan $PreparedPlan $stamp $machine $Action)
            if($Computer -ine $PreparedPlan.Computer -or $NewName -ine $PreparedPlan.NewName -or $TargetOU -ine $PreparedPlan.TargetOU){throw 'Les arguments diffèrent du plan importé.'}
        }
        $adp=Get-ADParams;$literal=ConvertTo-PestoFilterLiteral $Computer
        $sources=@(Get-ADComputer -LDAPFilter ('(|(name='+$literal+')(sAMAccountName='+$literal+'$))') -ResultSetSize 2 -Properties ObjectGUID,DistinguishedName -ErrorAction Stop @adp)
        if($sources.Count -ne 1){throw 'Source AD absente ou ambiguë.'}
        $source=$sources[0];$sourceOU=Get-PestoParentDN ([string]$source.DistinguishedName)
        $guid=([Guid]$source.ObjectGUID).ToString('D')
        if($guid -eq [Guid]::Empty.ToString()){throw 'GUID source absent.'}
        if(-not $TargetOU){$TargetOU=$sourceOU};if(-not $NewName){$NewName=$Computer}
        $rename=($Action -in @('Rename','RenameMove'));$move=($Action -in @('Move','RenameMove'))
        $decision=Get-PestoRenameMoveDecision -Computer $Computer -NewName $NewName -CurrentOU $sourceOU -TargetOU $TargetOU -Rename $rename -Move $move -InDomain $true
        if(-not $decision.Valid -or [bool]$decision.Move -ne $move){throw ('Plan incohérent avec les règles de site : '+$decision.Error+' '+$decision.Reason)}
        if($PreparedPlan -and ($guid -ine $PreparedPlan.ObjectGuid -or $sourceOU -ine $PreparedPlan.SourceOU)){throw 'Identité ou emplacement source changé depuis la préparation.'}
        $plan=[pscustomobject]@{Nom_du_PC=$Computer;Nouveau_Nom=$NewName;OU_Actuelle=$sourceOU;OU_Destination=$TargetOU;
            Renommer=$rename;Deplacer=$move;Reboot=$false;Objet_GUID=$guid;Domain=$script:DOMAINE;DC=$script:DC;ConfigStamp=$stamp;TargetOUGuid='';TargetMachineId=''}
        $explicitReason=Get-PestoExplicitCredentialRequirement -InDomain $true -Rows @($plan) -LocalComputerName $env:COMPUTERNAME
        if($explicitReason -and $Credential -isnot [Management.Automation.PSCredential]){throw $explicitReason}
        Assert-PestoOperationPolicy -Plan $plan -Policy $script:PestoPolicy
        Assert-PestoStoredMutationReady -Plan $plan
        $item=[pscustomobject]@{Key=(Get-PestoPlanSignature $plan);Nom_du_PC=$Computer;Nouveau_Nom=$NewName;OU_Actuelle=$sourceOU;OU_Destination=$TargetOU;Objet_GUID=$guid;Renommer=$rename;Deplacer=$move;Reboot=$false}
        $checkRequest=[pscustomobject]@{Items=@($item);DC=$script:DC;Domain=$script:DOMAINE;Credential=$Credential;InDomain=$true;Prefix=$script:PREFIXE;PRD=$script:PRD;
            OU=$script:OU;OUSite=$script:OUV;ClearProtection=$script:CLEAR_PROTECTION;Host=$env:COMPUTERNAME;ADModulePath=(Join-Path $RuntimeRoot 'ActiveDirectory.psd1');Progress=(New-PestoPreflightProgress 1)}
        $preflight=Get-PestoEngineWorkerScriptBlock -Name Preflight
        $checked=& $preflight $checkRequest (Get-PestoPreflightSource)
        $rows=@($checked.Results)
        if($rows.Count -ne 1 -or $rows[0].State -notin @('VÉRIFIÉ','AVERTISSEMENT') -or $rows[0].Guid -ine $guid){throw ('Contrôle refusé : '+[string]$rows[0].Detail)}
        $check=$rows[0];Assert-PestoDirectPreflightFreshness -Utc $check.Utc
        $plan.TargetOUGuid=[string]$check.TargetOUGuid
        if($PreparedPlan -and $move -and $PreparedPlan.TargetOUGuid -ine $plan.TargetOUGuid){throw 'OU destination remplacée depuis préparation.'}
        $portable=New-PestoPortablePlan -Action $Action -ConfigStamp $stamp -Computer $Computer -NewName $NewName -TargetOU $TargetOU -Domain $script:DOMAINE -ObjectGuid $guid -TargetOUGuid $plan.TargetOUGuid -SourceOU $sourceOU -Metadata $meta -MachineId $machine
        if(-not $Execute){return New-PestoIntegrationResult -Mode $Action -ExitCode 0 -State Prepared -Message 'Plan préparé, sans réservation ni mutation. Les identités seront relues à l’’exécution.' -Plan $portable -Metadata $meta}
        Initialize-PestoHeadlessAudit -RuntimeRoot $RuntimeRoot
        $fingerprint=Get-PestoPlanFingerprint $plan
        $op=[Guid]::NewGuid().ToString('N')
        $monitor=New-PestoQueueMonitor -Computer $Computer -OperationId $op
        # T018 : le worker direct s'exécute dans cette portée ; le journal peut donc partir au writer
        # d'audit dès son émission au lieu d'attendre un vidage borné en fin d'opération.
        Enable-PestoHeadlessEventStream $monitor
        $request=[pscustomobject]@{Plan=$plan;Metadata=$meta;Approval=$Approval;Version='1.0';OperationId=$op;ResumeId='';LocalSource=($Computer -ieq $env:COMPUTERNAME);TargetMachineId='';
            Telemetry=$monitor;Computer=$Computer;NewName=$NewName;TargetOU=$TargetOU;CurrentOU=$sourceOU;Rename=$rename;Move=$move;Reboot=$false;ObjectGuid=$guid;
            TargetOUGuid=$plan.TargetOUGuid;ConfigStamp=$stamp;PlanFingerprint=$fingerprint;Policy=$script:PestoPolicy;ReadOnly=$false;
            DC=$script:DC;Domain=$script:DOMAINE;Credential=$Credential;Prefix=$script:PREFIXE;SIM=$false;InDomain=$true;PRD=$script:PRD;OU=$script:OU;OUSite=$script:OUV;
            OUPostes=$script:OU_POSTES;OUScan=$script:OU_SCAN;ClearProtection=$script:CLEAR_PROTECTION;EntraPolicy=[string](@($script:CFG.CONF)[0].EntraPolicy);
            AllowPasswordTaskFallback=$script:PestoPolicy.AllowPasswordTaskFallback;ADModulePath=(Join-Path $RuntimeRoot 'ActiveDirectory.psd1')}
        $direct=Get-PestoEngineWorkerScriptBlock -Name Direct;$queue=Get-PestoEngineWorkerScriptBlock -Name Queue
        $result=& $direct $request (Get-PestoWorkerCoreSource) $queue.ToString() (Get-PestoDirectSupportSource)
        if(-not $result -or -not $result.Receipt -or $result.Action.ExitCode -isnot [int]){
            return New-PestoIntegrationResult -Mode $Action -ExitCode 97 -State Uncertain -Message 'Résultat ou reçu moteur incomplet. Vérifier avant toute reprise.' -Plan $portable -OperationId $op -MutationStarted ([bool]$monitor.MutationStarted) -Metadata $meta
        }
        $code=[int]$result.Action.ExitCode
        $state=[string]$result.Receipt.Phase
        $expected=Get-PestoDirectPhase -Code $code -Rename $rename -TimedOut ([bool]$monitor.TimedOut)
        # Un reçu incertain, un timeout, une phase qui ne correspond pas au code,
        # un 96 après mutation ou un code 0 nu restent 97. 20/77 deviennent 3010
        # et 30/33 deviennent 0 seulement quand la phase du reçu confirme ce résultat.
        if($monitor.TimedOut -or $state -eq 'Uncertain' -or $state -cne $expected -or ($code -eq 96 -and $monitor.MutationStarted) -or $code -eq 0){
            $exitCode=97;$state='Uncertain'
        }else{$exitCode=if($code -in @(20,77)){3010}elseif($code -in @(30,33)){0}elseif($code -in @(97,98,99)){97}else{$code}}
        return New-PestoIntegrationResult -Mode $Action -ExitCode $exitCode -State $state -Message ([string]$result.Action.ExitMsg) -Plan $portable -OperationId $op -MutationStarted ([bool]$monitor.MutationStarted) -EngineCode $code -Metadata $meta
    }catch{
        $started=($monitor -and [bool]$monitor.MutationStarted)
        $uncertain=$started -or ($monitor -and [bool]$monitor.TimedOut)
        return New-PestoIntegrationResult -Mode $Action -ExitCode $(if($uncertain){97}else{96}) -State $(if($uncertain){'Uncertain'}else{'NotStarted'}) -Message $_.Exception.Message -Plan $portable -OperationId $op -MutationStarted $started -Metadata $meta
    }finally{try{Write-PestoHeadlessEvents $monitor}catch{};if($request){$request.Credential=$null};$script:cred=$null;$script:PestoQueueMonitor=$null;Close-PestoHeadlessAudit}
}

function Invoke-PestoInspection {
    param([string]$RuntimeRoot,[string]$ConfigPath,$Credential,[string]$Computer='')
    try{
        Initialize-PestoHeadlessContext -RuntimeRoot $RuntimeRoot -ConfigPath $ConfigPath -Credential $Credential -ReadOnly
        if(-not $Computer){$Computer=$env:COMPUTERNAME}
        $request=[pscustomobject]@{Computer=$Computer;AlternativeComputer='';ObjectGuid='';DC=$script:DC;Domain=$script:DOMAINE;Credential=$Credential;
            LocalSource=($Computer -ieq $env:COMPUTERNAME);ADModulePath=(Join-Path $RuntimeRoot 'ActiveDirectory.psd1');JoinTargetOU=''}
        $observation=Get-PestoPostObservation $request
        [pscustomobject]@{Schema=1;Mode='Inspect';State='Observed';ExitCode=0;MutationStarted=$false;ReadOnly=$true;DC=$script:DC;Observation=$observation}
    }catch{New-PestoIntegrationResult -Mode Inspect -ExitCode 96 -State NotStarted -Message $_.Exception.Message}
    finally{$script:cred=$null;if($request){$request.Credential=$null}}
}

function Invoke-PestoCommand {
    [CmdletBinding()]
    param([string]$RuntimeRoot,[string]$ConfigPath,$Credential,
        [ValidateSet('Join','Rename','Move','RenameMove','Inspect','Diagnose')][string]$Action='Inspect',
        [string]$Computer='',[string]$NewName='',[string]$TargetOU='',[string]$Type='',
        [string]$SiteCode='',[string]$ServiceCode='',
        [string]$PlanPath='',[string]$OutPlanPath='',[string]$IdempotencyKey='',$Metadata=$null,$Approval=$null,[switch]$Execute)
    try{
        Assert-PestoAutomationPlatform
        if(-not $ConfigPath){$ConfigPath=Join-Path $RuntimeRoot 'cfg.json'}
        $cfg=Read-PestoAutomationJson -Path $ConfigPath -MaximumBytes 1MB
        $configErrors=@(Test-CfgValid $cfg);if($configErrors.Count){throw ($configErrors -join ' ')}
        $stamp=Get-PestoConfigurationSignature $cfg
        $metadataSafe=ConvertTo-PestoDeploymentMetadata $Metadata
        if($Action -eq 'Diagnose'){
            if($Execute -or $PlanPath -or $OutPlanPath -or $IdempotencyKey){throw 'Diagnose accepte uniquement une lecture.'}
            Initialize-PestoHeadlessContext -RuntimeRoot $RuntimeRoot -ConfigPath $ConfigPath -Credential $Credential -ReadOnly
            if(-not $Computer){$Computer=$env:COMPUTERNAME}
            $diagnostic=Invoke-PestoReadDiagnostics -Domain $script:DOMAINE -DC $script:DC -Computer $Computer -Action Observe -Checks Network,Clock,Account,Restart -Credential $Credential
            return [pscustomobject]@{Schema=1;Mode='Diagnose';State='Observed';ExitCode=0;MutationStarted=$false;ReadOnly=$true;DC=$script:DC;Diagnostic=$diagnostic}
        }
        if($Action -eq 'Inspect'){
            if($Execute -or $PlanPath -or $OutPlanPath -or $IdempotencyKey){throw 'Inspect accepte uniquement une lecture, sans plan ni clé exécution.'}
            return Invoke-PestoInspection -RuntimeRoot $RuntimeRoot -ConfigPath $ConfigPath -Credential $Credential -Computer $Computer
        }
        if($Execute -and $OutPlanPath){throw 'Séparez la préparation exportée et son exécution.'}
        $prepared=$null
        if($PlanPath){
            $prepared=Read-PestoAutomationJson $PlanPath
            # L'intégrité, la date et les identités sont recontrôlées dans le moteur avant exécution.
            # Le registre idempotent peut restituer un résultat accepté même après expiration du plan.
            if($prepared.Action -cne $Action){throw 'Action différente de celle du plan.'}
            foreach($pair in @(@('Computer',$Computer),@('NewName',$NewName),@('TargetOU',$TargetOU),@('Type',$Type),@('SiteCode',$SiteCode),@('ServiceCode',$ServiceCode))){
                if($pair[1] -and [string]$pair[1] -cne [string]$prepared.($pair[0])){throw ('Argument différent du plan : '+$pair[0])}
            }
            $Computer=[string]$prepared.Computer;$NewName=[string]$prepared.NewName;$TargetOU=[string]$prepared.TargetOU
            $Type=[string]$prepared.Type;$SiteCode=[string]$prepared.SiteCode;$ServiceCode=[string]$prepared.ServiceCode
            if($null -ne $Metadata -and (Get-PestoStableHash $metadataSafe) -cne (Get-PestoStableHash (ConvertTo-PestoDeploymentMetadata $prepared.Metadata))){throw 'Métadonnées différentes du plan.'}
            $metadataSafe=ConvertTo-PestoDeploymentMetadata $prepared.Metadata
        }
        $payload=[ordered]@{Action=$Action;ConfigStamp=$stamp;Computer=$Computer;NewName=$NewName;TargetOU=$TargetOU;Type=$Type;SiteCode=$SiteCode;
            ServiceCode=$ServiceCode;Metadata=$metadataSafe;Approval=$Approval;PlanIntegrity=$(if($prepared){[string]$prepared.Integrity}else{''});PlanContentHash=$(if($prepared){Get-PestoStableHash (ConvertTo-PestoCanonicalValue $prepared)}else{''})}
        $invoke={
            if($Action -eq 'Join'){
                if($Execute){Initialize-PestoHeadlessAudit -RuntimeRoot $RuntimeRoot}
                Invoke-PestoUnattendedJoin -RuntimeRoot $RuntimeRoot -ConfigPath $ConfigPath -Credential $Credential -Type $Type -SiteCode $SiteCode `
                    -ServiceCode $ServiceCode -TargetOU $TargetOU -PreparedPlan $prepared -Metadata $metadataSafe -Approval $Approval -Execute:$Execute
            }else{
                Invoke-PestoUnattendedOperation -RuntimeRoot $RuntimeRoot -ConfigPath $ConfigPath -Credential $Credential -Action $Action -Computer $Computer `
                    -NewName $NewName -TargetOU $TargetOU -PreparedPlan $prepared -Metadata $metadataSafe -Approval $Approval -Execute:$Execute
            }
        }
        $result=if($Execute -and $IdempotencyKey){Invoke-PestoIdempotentExecution -Key $IdempotencyKey -Payload $payload -Handler $invoke}else{& $invoke}
        if($OutPlanPath){
            if($result.State -cne 'Prepared' -or $result.ExitCode -ne 0){return $result}
            $export=if($Action -eq 'Join'){$result.PreparedPlan}else{$result.Plan}
            if(-not $export){throw 'Plan exportable absent.'}
            Export-PestoPortablePlan -Plan $export -Path $OutPlanPath
        }
        return $result
    }catch{return New-PestoIntegrationResult -Mode $Action -ExitCode 96 -State NotStarted -Message $_.Exception.Message}
    finally{$Credential=$null;$script:cred=$null;Close-PestoHeadlessAudit}
}

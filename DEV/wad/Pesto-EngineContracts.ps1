#requires -Version 5.1
# Contrats réutilisables : aucun effet de bord au chargement.
function Get-PestoEngineInfo {
    [pscustomobject]@{PSTypeName='Pesto.Engine.Info';Schema=1;Version='1.0';Runtime='WindowsPowerShell5.1';UIRequired=$false;AutomaticMutationRetry=$false}
}
function Get-PestoEngineWorkerScriptBlock {
    param([Parameter(Mandatory=$true)][ValidateSet('Direct','Queue','Preflight')][string]$Name)
    switch($Name){'Direct'{return $script:PestoDirectWorker};'Queue'{return $script:PestoQueueWorker};'Preflight'{return $script:PestoPreflightWorker}}
}
function Get-PestoExecutionContext {
    param([Parameter(Mandatory=$true)][string]$Domain,[Parameter(Mandatory=$true)][string]$DC,
        [string]$OperationId=([Guid]::NewGuid().ToString('N')),[string]$BuildSHA256='')
    $id=[Guid]::Empty
    if(-not [Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant opération invalide.'}
    if(-not(Test-PestoDnsName $Domain) -or -not(Test-PestoDnsName $DC) -or $DC -ieq $Domain -or $DC.IndexOf('.') -lt 1){throw 'Domaine et contrôleur FQDN explicite requis.'}
    if($BuildSHA256 -and $BuildSHA256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Empreinte de build invalide.'}
    [pscustomobject]@{PSTypeName='Pesto.Engine.Context';Schema=1;OperationId=$id.ToString('N');Domain=$Domain.ToLowerInvariant();DC=$DC.ToLowerInvariant();BuildSHA256=$BuildSHA256.ToLowerInvariant();CreatedUtc=[DateTime]::UtcNow.ToString('o')}
}
function New-PestoEngineError {
    param($ErrorRecord,[ValidateSet('Read','Write','Observe','Prepare')][string]$Phase='Read',[string]$OperationId='', [bool]$MutationPossible=$false)
    $native=Get-PestoNativeFailureCode $ErrorRecord
    $category='Unknown';$retryable=$false
    if($null -ne $native){
        switch([long]$native){
            {$_ -in @(5,1326,1314)}{$category='AccessDenied';break}
            {$_ -in @(53,64,121,1722,1726,1460)}{$category='Transport';$retryable=($Phase -eq 'Read' -and -not $MutationPossible);break}
            {$_ -in @(2224,2732)}{$category='AccountReuse';break}
            87{$category='InvalidArgument';break}
        }
    }
    $exception=if($ErrorRecord -is [Exception]){$ErrorRecord}else{$ErrorRecord.Exception}
    [pscustomobject]@{PSTypeName='Pesto.Engine.Error';Schema=1;OperationId=$OperationId;Phase=$Phase;Category=$category;NativeCode=$native;
        ExceptionType=$(if($exception){$exception.GetType().FullName}else{''});RetryableRead=$retryable;MutationPossible=$MutationPossible;
        Message=(Protect-PestoLogText ([string]$(if($exception){$exception.Message}else{$ErrorRecord})));NextAction=$(if($MutationPossible){'Relire la cible et le reçu ; aucune répétition automatique.'}elseif($null -ne $native){Get-PestoNativeGuidance $native $Phase}else{'Consulter les détails et préparer un nouveau contrôle explicite.'})}
}
function Get-PestoStateTransitions {
    # Contrat de phases centrales. Ce tableau ne change jamais un reçu par lui-même.
    [ordered]@{
        Prepared=@('Running','NotStarted','Failed');Running=@('PendingRestart','Verified','Partial','Protection','Uncertain','Failed','NotStarted');
        PendingRestart=@('PendingRestart','Verified','MoveReady','Partial','Protection','Uncertain');
        Partial=@('Partial','MoveReady','PendingRestart','Verified','Protection','Uncertain');MoveReady=@('MoveReady','PendingRestart','Verified','Partial','Protection','Uncertain');Protection=@('Protection','Verified','Partial','Uncertain');
        Uncertain=@('Uncertain','Verified','MoveReady','Partial','Protection');Verified=@('Verified');Failed=@('Failed');NotStarted=@('NotStarted')
    }
}
function Test-PestoStateTransition {
    param([string]$From,[string]$To,[bool]$ObservationConfirmed=$false,[bool]$MutationActive=$false)
    $graph=Get-PestoStateTransitions
    if(-not $graph.Contains($From) -or $To -cnotin $graph[$From]){return $false}
    if($To -eq 'Verified' -and (-not $ObservationConfirmed -or $MutationActive)){return $false}
    return $true
}
function ConvertTo-PestoSchemaMigration {
    param([Parameter(Mandatory=$true)][string]$Json,[ValidateSet('Policy','Configuration','Draft','Receipt')][string]$Kind)
    if([Text.Encoding]::UTF8.GetByteCount($Json) -gt 1MB){throw 'Document trop volumineux.'}
    $data=$Json|ConvertFrom-Json -ErrorAction Stop
    $before=$data|ConvertTo-Json -Depth 30 -Compress
    switch($Kind){
        'Policy'{
            $result=ConvertTo-PestoPolicy $data -LocalOnly
        }
        'Configuration'{
            $errors=@(Test-CfgValid $data);if($errors.Count){throw ($errors -join ' ')}
            $result=$data
            if($result.POLICY){
                # Migration locale uniquement : pas de fusion GPO (Merge-PestoManagedPolicy)
                $normalized = ConvertTo-PestoPolicy $result.POLICY -LocalOnly
                # On réécrit les propriétés de POLICY en place pour préserver la clé 'POLICY' (casse exacte)
                foreach($prop in @($normalized.PSObject.Properties)){
                    $result.POLICY | Add-Member NoteProperty $prop.Name $prop.Value -Force
                }
                # RandomNameChoice (historique) est converti en RandomNameEnabled : la clé source disparaît.
                [void]$result.POLICY.PSObject.Properties.Remove('RandomNameChoice')
            }
        }
        'Draft'{
            if(($data.Schema -isnot [int] -and $data.Schema -isnot [long]) -or $data.Schema -ne 1){throw 'Schéma de brouillon inconnu : aucune migration devinée.'}
            $data.Schema=[int]$data.Schema
            $result=ConvertTo-PestoDraft $data
        }
        'Receipt'{
            $id=[Guid]::Empty
            if(($data.Schema -isnot [int] -and $data.Schema -isnot [long]) -or $data.Schema -notin @(1,2,3) -or $data.OperationId -isnot [string] -or -not [Guid]::TryParse($data.OperationId,[ref]$id) -or $id -eq [Guid]::Empty -or $data.Phase -cnotin @('Running','Failed','PendingRestart','Partial','MoveReady','Protection','Uncertain','Verified','NotStarted')){throw 'Schéma de reçu inconnu : original à conserver.'}
            # Les phases et preuves historiques ne sont pas synthétisées. Migration de stockage uniquement.
            $result=$data
        }
    }
    $hash=[Security.Cryptography.SHA256]::Create()
    try{$sha=([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Json)))).Replace('-','').ToLowerInvariant()}finally{$hash.Dispose()}
    [pscustomobject]@{PSTypeName='Pesto.Engine.Migration';Schema=1;Kind=$Kind;OriginalJson=$Json;OriginalSHA256=$sha;Result=$result;
        Changed=($before -cne ($result|ConvertTo-Json -Depth 30 -Compress));RequiresExplicitSave=$true}
}
function Save-PestoSchemaMigration {
    param([Parameter(Mandatory=$true)][string]$SourcePath,[Parameter(Mandatory=$true)][string]$OutputPath,
        [Parameter(Mandatory=$true)][ValidateSet('Policy','Configuration','Draft','Receipt')][string]$Kind)
    Assert-PestoPlainPath $SourcePath;Assert-PestoPlainPath $OutputPath
    if([IO.File]::Exists($OutputPath) -or [IO.Directory]::Exists($OutputPath)){throw 'Choisir une destination neuve ; aucun original écrasé.'}
    
    $fileInfo = [IO.FileInfo]::new($SourcePath)
    if ($fileInfo.Length -gt 1MB) { throw 'Document trop volumineux.' }
    
    $bytes = [IO.File]::ReadAllBytes($SourcePath)
    
    # Strip UTF-8 BOM if present (EF BB BF)
    $start = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $start = 3
    }
    # Décodage strict : un octet UTF-8 invalide arrête la migration avant toute écriture.
    $json = ([Text.UTF8Encoding]::new($false, $true)).GetString($bytes, $start, $bytes.Length - $start)
    
    $migration = ConvertTo-PestoSchemaMigration -Json $json -Kind $Kind
    
    $backup = $OutputPath + '.original'
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $sourceHash = ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }

    if ([IO.File]::Exists($backup)) {
        $existingBytes = [IO.File]::ReadAllBytes($backup)
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            $existingHash = ([BitConverter]::ToString($sha256.ComputeHash($existingBytes))).Replace('-','').ToLowerInvariant()
        } finally {
            $sha256.Dispose()
        }
        if ($existingHash -ne $sourceHash) {
            throw 'Sauvegarde existante différente de la source : choisir une autre destination.'
        }
        # Reuse existing backup, do not rewrite
    } else {
        $temporary = $OutputPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        $stream = $null
        try {
            $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
            $stream.Dispose()
            $stream = $null
            [IO.File]::Move($temporary, $backup)
        } finally {
            if ($stream) { $stream.Dispose() }
            if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        }
    }

    $text = $migration.Result | ConvertTo-Json -Depth 30
    $out = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $tempOut = $OutputPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $stream = $null
    try {
        $stream = [IO.File]::Open($tempOut, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Write($out, 0, $out.Length)
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        [IO.File]::Move($tempOut, $OutputPath)
    } finally {
        if ($stream) { $stream.Dispose() }
        if ([IO.File]::Exists($tempOut)) { [IO.File]::Delete($tempOut) }
    }

    [pscustomobject]@{OutputPath=$OutputPath;OriginalBackup=$backup;OriginalUnchanged=$true;Kind=$Kind}
}
function New-PestoReadCoordinator {
    # Un coordinateur appartient à UNE session authentifiée et est abandonné lors du changement de compte.
    [hashtable]::Synchronized(@{Scope=[Guid]::NewGuid().ToString('N');Active=@{}})
}
function Invoke-PestoReadCoalesced {
    param([Parameter(Mandatory=$true)][hashtable]$Coordinator,[Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][scriptblock]$ReadAction,[object[]]$ArgumentList=@(),[ValidateRange(1,300000)][int]$WaitMilliseconds=30000)
    if(-not $Coordinator.Scope -or $Coordinator.Active -isnot [hashtable] -or -not $Key -or $Key.Length -gt 2048){throw 'Contexte de lecture invalide.'}
    $owner=$false
    [Threading.Monitor]::Enter($Coordinator.SyncRoot)
    try{
        if($Coordinator.Active.ContainsKey($Key)){$flight=$Coordinator.Active[$Key];$flight.Users++}
        else{$flight=[hashtable]::Synchronized(@{Done=[Threading.ManualResetEventSlim]::new($false);Value=$null;Failure=$null;Users=1});$Coordinator.Active[$Key]=$flight;$owner=$true}
    }finally{[Threading.Monitor]::Exit($Coordinator.SyncRoot)}
    try{
    if($owner){
        try{$flight.Value=& $ReadAction @ArgumentList}catch{$flight.Failure=$_.Exception}
        finally{
            [Threading.Monitor]::Enter($Coordinator.SyncRoot)
            try{if([object]::ReferenceEquals($Coordinator.Active[$Key],$flight)){$Coordinator.Active.Remove($Key)};$flight.Done.Set()}
            finally{[Threading.Monitor]::Exit($Coordinator.SyncRoot)}
        }
    }elseif(-not $flight.Done.Wait($WaitMilliseconds)){throw [TimeoutException]::new('Attente de lecture partagée expirée. La lecture d''origine reste surveillée ; aucune commande rejouée.')}
    if($flight.Failure){throw $flight.Failure}
    [pscustomobject]@{Value=$flight.Value;Shared=(-not $owner);Scope=$Coordinator.Scope}
    }finally{
        [Threading.Monitor]::Enter($Coordinator.SyncRoot)
        try{$flight.Users--;if($flight.Users -eq 0){$flight.Done.Dispose()}}finally{[Threading.Monitor]::Exit($Coordinator.SyncRoot)}
    }
}

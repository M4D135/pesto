#requires -Version 5.1
# Définitions uniquement, chargées dans la portée du moteur.


function Invoke-PestoWindowsLocalRename {
    # Appel WMI local avec le jeton courant. Aucun PSCredential fabriqué à vide.
    # Win32_ComputerSystem.Rename utilise l'appelant si UserName/Password sont omis.
    param([string]$ComputerName,[string]$NewName)
    if(-not (Test-PestoComputerName $ComputerName) -or -not (Test-PestoGeneratedComputerName $NewName)){
        return New-ActionResult 96 'Renommage Windows intégré : noms invalides, aucune action lancée.'
    }
    if($ComputerName -ine $env:COMPUTERNAME){
        return New-ActionResult 96 'Le renommage Windows intégré est strictement local. Aucun dsregcmd lancé.'
    }
    if($script:SIM -or $script:GUI){return New-ActionResult 20 'SIMULATION : renommage local avec le compte Windows, aucune écriture.'}
    try {
        Assert-PestoWorkerMayContinue
        $identity=Get-PestoWindowsAuthIdentity
        if(-not $identity.IsAdministrator -or -not $identity.IsDomainUser){throw 'Un compte du domaine avec jeton administrateur local est requis.'}
        $local=@(Get-CimInstance -ClassName Win32_ComputerSystem -Namespace 'root/cimv2' -OperationTimeoutSec 15 -ErrorAction Stop)
        if($local.Count -ne 1){throw 'La lecture du poste local ne renvoie pas un résultat unique.'}
        $cs=$local[0]
        if([string]$cs.Name -ine $ComputerName -or $cs.PartOfDomain -isnot [bool] -or -not $cs.PartOfDomain -or
           ([string]$cs.Domain).TrimEnd('.') -ine $script:DOMAINE.TrimEnd('.')){
            throw 'Le nom ou le domaine réel du poste ne correspond plus au plan préparé.'
        }
        if($null -eq $cs.DomainRole -or [int]$cs.DomainRole -notin @(1,3)){throw 'Le rôle Windows ne permet pas ce renommage. Les contrôleurs de domaine sont exclus.'}
        # Vérifie la disponibilité de la cmdlet avant le retrait Entra.
        [void](Get-Command Invoke-CimMethod -ErrorAction Stop)
    } catch {return New-ActionResult 96 ('Précontrôle du renommage intégré refusé : '+$_.Exception.Message+' Aucun dsregcmd lancé.')}

    $leave=Invoke-PestoDsregLeaveBeforeRename -ComputerName $ComputerName
    if(-not $leave){return New-ActionResult 97 'Résultat dsregcmd absent : aucun renommage lancé.'}
    if($leave.ExitCode -ne 20){return $leave}
    $note=if($leave.Entra -eq 'Confirmed'){' | Retrait Entra effectué : réinscription à vérifier séparément.'}else{' | Aucun retrait Entra nécessaire.'}
    try {
        Assert-PestoWorkerMayContinue -Mutation
        Set-PestoWorkerStage 'Renommage local avec le compte Windows' $identity.Name
        # -Query cible l'instance, sans -ComputerName, -CimSession ni -InputObject :
        # session COM locale, pas de WinRM ni de délégation vers un autre poste.
        $query="SELECT * FROM Win32_ComputerSystem WHERE Name='$ComputerName'"
        Set-PestoEffect -Name Rename -Value 'Requested'
        $result=@(Invoke-CimMethod -Query $query -Namespace 'root/cimv2' -MethodName 'Rename' -Arguments @{Name=$NewName} -OperationTimeoutSec 120 -ErrorAction Stop)
        if($result.Count -ne 1 -or $null -eq $result[0] -or -not $result[0].PSObject.Properties['ReturnValue']){
            return New-ActionResult 97 ('Résultat WMI absent ou incomplet : aucun succès supposé.'+$note)
        }
        $code=$result[0].ReturnValue
        if(($code -isnot [uint32] -and $code -isnot [int] -and $code -isnot [uint64] -and $code -isnot [long]) -or
            [long]$code -lt 0 -or [long]$code -gt [uint32]::MaxValue){
            return New-ActionResult 97 ('Code de retour WMI invalide : aucun succès supposé.'+$note)
        }
        if([uint32]$code -eq 0){Set-PestoEffect -Name Rename -Value 'Confirmed';return New-ActionResult 20 ("'$ComputerName' renommé en '$NewName' avec le compte Windows ; redémarrage requis."+$note)}
        $text=try{([ComponentModel.Win32Exception]::new([int]$code)).Message}catch{'Erreur Windows non traduite'}
        Set-PestoEffect -Name Rename -Value 'Refused'
        return New-ActionResult 21 ("Renommage WMI refusé (code $code) : $text. Aucun nouvel essai automatique."+$note)
    } catch {
        Write-Log 'Renommage Windows intégré interrompu après le retrait Entra.' 'ERROR' $_ 'rename'
        return New-ActionResult 97 ('Résultat incertain : '+$_.Exception.Message+'. Vérifier Windows et AD avant toute reprise.'+$note)
    }
}

function Get-PestoNameSiteCode {
    # Site lu dans le nom ACTUEL par le parseur unique (types P, S et V ; voir ConvertTo-PestoNameParts).
    param([AllowNull()][string]$Name)
    $parts=ConvertTo-PestoNameParts -Name $Name -CurrentName
    if($parts){return $parts.Site}
    return $null
}

function Get-PestoSiteContainerDN {
    <# Lecture en memoire : identifie le site sans confondre ses sous-OU avec un autre site.
       Utilise le conteneur PREPROD ou le premier enfant d'une racine OUSite configuree. #>
    param([AllowNull()][string]$OrganizationalUnit)
    if(-not(Test-PestoOUPath $OrganizationalUnit)){return $null}
    if($script:OU -and (Test-PestoOUPath ([string]$script:OU['PREPROD'])) -and
       (Test-PestoDNWithinScope -DistinguishedName $OrganizationalUnit -Roots @([string]$script:OU['PREPROD']))) {
        return (@(Split-PestoDistinguishedName ([string]$script:OU['PREPROD'])) -join ',')
    }
    $parts=@(Split-PestoDistinguishedName $OrganizationalUnit)
    $best=$null;$bestDepth=-1
    if($script:OUV) {
        foreach($entry in $script:OUV.GetEnumerator()) {
            $base=[string]$entry.Value
            if(-not(Test-PestoOUPath $base)){continue}
            $baseParts=@(Split-PestoDistinguishedName $base)
            if($parts.Count -le $baseParts.Count){continue}
            if($baseParts.Count -le $bestDepth){continue}
            if(Test-PestoDNWithinScope -DistinguishedName $OrganizationalUnit -Roots @($base)) {
                $offset=$parts.Count-$baseParts.Count-1
                $best=$parts[$offset..($parts.Count-1)] -join ','
                $bestDepth=$baseParts.Count
            }
        }
    }
    return $best
}

function Get-PestoRenameMoveDecision {
    <# Regle unique du renommage : deplacement automatique seulement si le site change.
       Les tags du nom Pesto sont prioritaires. Pour un ancien nom hors convention,
       les conteneurs de site AD permettent de trancher, sinon l'action est bloquee.
       Un deplacement seul, explicitement demande, reste une operation distincte. #>
    param([string]$Computer,[string]$NewName,[string]$CurrentOU,[string]$TargetOU,
          [bool]$Rename,[bool]$Move,[bool]$InDomain=$true)
    $r=[ordered]@{Move=$Move;Automatic=$false;SiteChanged=$false;SourceSite='';TargetSite='';Valid=$true;Reason='';Error=''}
    if(-not $InDomain){$r.Move=$true;$r.Reason='Jonction locale : OU de destination imposee.';return [pscustomobject]$r}
    if(-not $Rename){$r.Reason=if($Move){'Deplacement seul explicitement demande.'}else{'Aucune action de deplacement demandee.'};return [pscustomobject]$r}
    $r.Automatic=$true;$r.Move=$false
    $old=Get-PestoNameSiteCode $Computer;$new=Get-PestoNameSiteCode $NewName
    $r.SourceSite=[string]$old;$r.TargetSite=[string]$new
    if(-not(Test-PestoGeneratedComputerName $NewName) -or "$Computer".Trim() -ieq "$NewName".Trim()) {
        $r.Valid=$false;$r.Error='Renommage invalide : nouveau nom absent, hors convention ou identique au nom actuel.'
        return [pscustomobject]$r
    }
    $sameOU=$false
    if((Test-PestoOUPath $CurrentOU) -and (Test-PestoOUPath $TargetOU)) {
        $sameOU=(@(Split-PestoDistinguishedName $CurrentOU) -join ',') -ieq (@(Split-PestoDistinguishedName $TargetOU) -join ',')
    }
    if($old -and $new) {
        $r.SiteChanged=($old -ine $new)
        $r.Reason=if($r.SiteChanged){"Site $old -> $new : déplacement automatique après renommage confirmé."}else{"Site $old conservé : renommage seul, aucun déplacement."}
    } else {
        $sourceSite=Get-PestoSiteContainerDN $CurrentOU
        $targetSite=Get-PestoSiteContainerDN $TargetOU
        if($sourceSite -and $targetSite) {
            $r.SourceSite=$sourceSite;$r.TargetSite=$targetSite
            $r.SiteChanged=($sourceSite -ine $targetSite)
            $r.Reason=if($r.SiteChanged){'Site AD différent : déplacement automatique après renommage confirmé.'}else{'Même site AD : renommage seul, sous-OU actuelle conservée.'}
        } elseif($sameOU) {
            $r.Reason='OU actuelle deja egale a la cible : renommage seul.'
        } else {
            $r.Valid=$false;$r.Error='Site actuel indeterminable : relisez le poste et selectionnez son site avant de renommer. Aucun deplacement implicite.'
            return [pscustomobject]$r
        }
    }
    if($r.SiteChanged) {
        if($sameOU) {$r.Reason+=' Poste deja dans l''OU cible : aucun Move-ADObject necessaire.'}
        elseif(-not(Test-PestoOUPath $TargetOU)) {$r.Valid=$false;$r.Error='Changement de site : OU de destination absente ou invalide.'}
        else {$r.Move=$true}
    }
    return [pscustomobject]$r
}

function Test-PestoDnsName {
    param([AllowNull()][string]$Name)
    $n = "$Name".Trim().TrimEnd('.')
    if (-not $n -or $n.Length -gt 253) { return $false }
    foreach ($label in ($n -split '\.')) {
        if ($label -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$') { return $false }
    }
    return $true
}

function Test-PestoOUInConfiguredScope {
    param([string]$OU)
    if(-not (Test-PestoOUPath $OU)){return $false}
    return Test-PestoDNWithinScope -DistinguishedName $OU -Roots (@($script:OU.Values)+@($script:OUV.Values))
}

function Test-QueueRowSafe {
    <# Validation mémoire complète d'une ligne avant toute écriture AD. #>
    param([string]$Nom,[string]$NewName,[string]$OU,[bool]$Ren,[bool]$Move)
    $errs = [System.Collections.Generic.List[string]]::new()
    $src = "$Nom".Trim(); $new = "$NewName".Trim(); $dest = "$OU".Trim()
    if (-not (Test-PestoComputerName $src)) { $errs.Add("Nom_du_PC invalide : '$src'") }
    if (-not $Ren -and -not $Move) { $errs.Add('Aucune action (Renommer/Déplacer) sélectionnée.') }
    if ($Ren -and -not (Test-PestoGeneratedComputerName $new)) { $errs.Add("Nouveau_Nom hors convention Pesto : '$new'") }
    if ($Ren -and $script:INDOMAIN -and $src -ieq $new) { $errs.Add('Le nouveau nom est identique au nom actuel ; décochez Renommer.') }
    if ($Move) {
        if (-not (Test-PestoOUPath $dest)) { $errs.Add("OU_Destination non-DN ou invalide : '$dest'") }
        elseif (-not (Test-PestoOUInConfiguredScope $dest)) { $errs.Add("OU_Destination hors périmètre cfg.json : '$dest'") }
    }
    if (-not $script:INDOMAIN) {
        if ($src -ine $env:COMPUTERNAME) { $errs.Add("Hors domaine, la source doit être le poste local '$env:COMPUTERNAME'.") }
        if (-not $Ren -or -not $Move) { $errs.Add('Une jonction hors domaine impose Renommer=True et Deplacer=True.') }
    }
    return $errs.ToArray()
}

function Test-PestoConfirmedChange {
    param([AllowNull()]$Change)
    $items=@($Change)
    return ($items.Count -eq 1 -and $null -ne $items[0] -and
        $null -ne $items[0].PSObject.Properties['HasSucceeded'] -and
        $items[0].HasSucceeded -is [bool] -and $items[0].HasSucceeded -eq $true)
}

function New-PestoTaskService {
    <# Authentification COM en mémoire. Jamais /p, /rp ou secret dans un processus. #>
    param([string]$ComputerName)
    $service=New-Object -ComObject 'Schedule.Service'
    try {
        if($script:cred) {
            $nc=$script:cred.GetNetworkCredential()
            $user=$nc.UserName; $domain=$nc.Domain
            if(-not $domain -and $user -match '^([^@]+)@(.+)$') { $user=$Matches[1]; $domain=$Matches[2] }
            if(-not $domain){$domain=$script:DOMAINE}
            $service.Connect($ComputerName,$user,$domain,$nc.Password)
            $nc=$null
        } else { $service.Connect($ComputerName) }
        return $service
    } catch { Release-PestoComObject $service; throw }
}

function Release-PestoComObject {
    param([AllowNull()]$Value)
    if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) {
        try{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)}catch{}
    }
}

function Get-PestoTaskArgument {
    param([string[]]$Arguments,[string]$Key)
    for($i=0;$i -lt $Arguments.Count-1;$i++){if($Arguments[$i] -ieq $Key){return $Arguments[$i+1]}}
    return ''
}

function Test-PestoPipeClient {
    param($Pipe,[int]$ExpectedProcessId)
    Initialize-PestoRuntimeTypes
    [uint32]$actual=0
    if(-not [Pesto.NativePipe17]::GetNamedPipeClientProcessId($Pipe.SafePipeHandle,[ref]$actual)) {throw 'Impossible de vérifier le processus connecté au canal élevé.'}
    if($actual -ne [uint32]$ExpectedProcessId){throw 'Processus inattendu connecté au canal élevé. Aucun secret transmis.'}
}

function New-PestoElevatedHelperScript {
    # Construction pure du helper élevé : aucun effet, analysée par le contrôle de démarrage.
    param([Parameter(Mandatory=$true)][string]$SettingsB64,[AllowEmptyString()][string]$DsregFunction='')
    $helper=@'
$ErrorActionPreference='Stop'
$s=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__SETTINGS__'))|ConvertFrom-Json
__DSREG_FUNCTION__
$client=$null;$reader=$null;$writer=$null;$started=$false
$result=[ordered]@{Ok=$false;HasSucceeded=$false;Indeterminate=$false;DsregLeft=$false;Message=''}
try {
    $client=[IO.Pipes.NamedPipeClientStream]::new('.',[string]$s.Pipe,[IO.Pipes.PipeDirection]::InOut)
    $client.Connect(120000)
    $utf8=[Text.UTF8Encoding]::new($false)
    $reader=[IO.StreamReader]::new($client,$utf8,$false,4096,$true)
    $writer=[IO.StreamWriter]::new($client,$utf8,4096,$true);$writer.AutoFlush=$true
    $read=$reader.ReadLineAsync()
    if(-not $read.Wait(30000)){throw 'Aucun credential reçu dans le délai imparti.'}
    $payload=$read.Result|ConvertFrom-Json -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace([string]$payload.UserName)){throw 'Identifiant vide.'}
    $secure=ConvertTo-SecureString ([string]$payload.Password) -AsPlainText -Force
    $credential=[Management.Automation.PSCredential]::new([string]$payload.UserName,$secure)
    $payload=$null;$read=$null
    $common=@{NewName=[string]$s.NewName;PassThru=$true;Force=$true;ErrorAction='Stop';WarningAction='SilentlyContinue'}
    Write-Host ('Pesto : opération locale '+$s.Action+' vers '+$s.NewName+'. Ne fermez pas cette fenêtre pendant la commande.')
    if($s.Action -eq 'Join'){
        throw 'La jonction exige le moteur Pesto déjà élevé et ses reçus. Ce helper ne peut pas joindre le domaine.'
    } elseif($s.Action -eq 'Rename'){
        Write-Host 'Pesto : dsregcmd /leave AVANT le renommage local.'
        $leave=Invoke-PestoDsregLeaveLocal -ExpectedComputerName ([string]$s.Computer)
        if(-not $leave -or $leave.ExitCode -notin @(20,21,97)){$result.Indeterminate=$true;throw 'Résultat dsregcmd invalide : aucun renommage lancé.'}
        if($leave.ExitCode -eq 97){$result.Indeterminate=$true}
        if($leave.ExitCode -ne 20){throw ([string]$leave.ExitMsg)}
        $result.DsregLeft=$true;$started=$true
        Write-Host $leave.ExitMsg
        # Appel LOCAL : ne jamais fournir ComputerName/LocalCredential.
        $common.DomainCredential=$credential;$change=@(Rename-Computer @common)
    } else {throw 'Action interdite.'}
    if($change.Count -ne 1 -or -not $change[0].PSObject.Properties['HasSucceeded'] -or $change[0].HasSucceeded -isnot [bool]){
        $result.Indeterminate=$true;$result.Message='Retour de mutation inexploitable : vérification manuelle requise.'
    } elseif($change[0].HasSucceeded){
        $result.Ok=$true;$result.HasSucceeded=$true;$result.Message='La commande a confirmé HasSucceeded=True ; redémarrage requis.'
    } else {$result.Message='La commande a confirmé HasSucceeded=False.'}
} catch {
    $result.Message=[string]$_.Exception.Message
    # Une exception RPC/transport après appel peut cacher une écriture réussie.
    if($started -and $result.Message -match '(?i)(RPC|0x800706ba|timed?\s*out|d.lai|transport|connexion.*(perd|ferm))'){$result.Indeterminate=$true}
} finally {
    if($result.DsregLeft){$result.Message+=' Le retrait Entra a réussi : contrôler la réinscription, même si le renommage échoue.'}
    try{if($writer){$writer.WriteLine(($result|ConvertTo-Json -Compress));$writer.Flush()}}catch{}
    foreach($o in @($writer,$reader,$client)){try{if($o){$o.Dispose()}}catch{}}
    $credential=$null;$secure=$null
}
if($result.Ok){exit 0}else{exit 1}
'@
    return $helper.Replace('__SETTINGS__',$SettingsB64).Replace('__DSREG_FUNCTION__',$DsregFunction)
}

function Invoke-PestoElevatedLocalChange {
    <# UAC pour une seule mutation locale. Paramètres non secrets dans le helper ;
       credential transmis uniquement au PID attendu par un pipe ACLé. #>
    param([ValidateSet('Join','Rename')][string]$Action='Join',
          [string]$Domain,[string]$OUPath,[string]$NewName,[string]$DC,[AllowNull()]$Credential)
    # Le seul parcours de jonction passe par AddToDomain et ses reçus durables.
    if($Action -eq 'Join'){return New-ActionResult 96 'Jonction interdite par ce helper. Relancez Pesto.exe élevé puis utilisez Ajouter au domaine.'}
    $ko=21;$ok=20
    if($script:SIM -or $script:GUI){return New-ActionResult $ok "SIMULATION : $Action local, aucune élévation."}
    if(-not $Credential){return New-ActionResult $ko "Un credential de domaine explicite est requis pour cette élévation."}
    if(-not (Test-PestoGeneratedComputerName $NewName)){return New-ActionResult $ko "Nouveau nom invalide : '$NewName'."}
    if($Action -eq 'Join' -and (-not (Test-PestoOUPath $OUPath) -or -not (Test-PestoDnsName $DC) -or $DC -notmatch '\.' -or $DC -ieq $Domain)){
        return New-ActionResult $ko "Jonction bloquée : OU ou contrôleur de domaine FQDN invalide."
    }
    Assert-PestoWorkerMayContinue
    if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){return New-ActionResult $ko 'Élévation locale refusée : le worker doit être STA. Aucune commande transmise.'}
    Set-PestoWorkerStage 'Préparation de l''élévation locale' 'Le compte AD ne remplace pas le jeton administrateur Windows'
    $pipe=$null;$reader=$null;$writer=$null;$proc=$null;$credentialSent=$false;$wait=$null
    try {
        $pipeName='Pesto_Change_'+[Guid]::NewGuid().ToString('N')
        $acl=[IO.Pipes.PipeSecurity]::new();$acl.SetAccessRuleProtection($true,$false)
        $allow=[Security.AccessControl.AccessControlType]::Allow
        foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))){
            $acl.AddAccessRule([IO.Pipes.PipeAccessRule]::new($sid,[IO.Pipes.PipeAccessRights]::ReadWrite,$allow))
        }
        $pipe=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::InOut,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,4096,4096,$acl)
        $settings=[ordered]@{Action=$Action;Domain=$Domain;OU=$OUPath;NewName=$NewName;DC=$DC;Pipe=$pipeName;Computer=$env:COMPUTERNAME}
        $settingsB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($settings|ConvertTo-Json -Compress)))
        $dsregFunction=''
        if($Action -eq 'Rename'){
            $definition=(Get-Command Invoke-PestoDsregLeaveLocal -CommandType Function -ErrorAction Stop).Definition
            $dsregFunction="function Invoke-PestoDsregLeaveLocal {`r`n$definition`r`n}"
        }
        $helper=New-PestoElevatedHelperScript -SettingsB64 $settingsB64 -DsregFunction $dsregFunction
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($helper))
        $exe=Join-Path $PSHOME 'powershell.exe'
        Assert-PestoWorkerMayContinue
        Set-PestoWorkerStage 'Autorisation Windows attendue' 'Validez la fenêtre UAC ; elle peut être sur le bureau sécurisé'
        try{$proc=Start-Process -FilePath $exe -Verb RunAs -WindowStyle Normal -ArgumentList @('-NoLogo','-NoProfile','-STA','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -PassThru -ErrorAction Stop}
        catch{return New-ActionResult $ko "Élévation UAC annulée ou impossible : $($_.Exception.Message)"}
        if($script:PestoQueueMonitor){$script:PestoQueueMonitor.HelperPid=[int]$proc.Id}
        Assert-PestoWorkerMayContinue
        Set-PestoWorkerStage 'Connexion au helper élevé' ('PID '+$proc.Id+' ; maximum 120 s avant transmission')
        $wait=$pipe.BeginWaitForConnection($null,$null)
        $connectDeadline=[DateTime]::UtcNow.AddSeconds(120)
        while(-not $wait.AsyncWaitHandle.WaitOne(200)){
            Assert-PestoWorkerMayContinue
            if($proc.HasExited){return New-ActionResult $ko ('Le helper élevé a quitté avant communication (PID '+$proc.Id+'). Aucun credential transmis ; vérifiez les journaux AppLocker/WDAC/antivirus.')}
            if([DateTime]::UtcNow -ge $connectDeadline){
                return New-ActionResult $ko "Le helper élevé n'a pas établi la communication sous 120 s ; aucune commande transmise."
            }
        }
        $pipe.EndWaitForConnection($wait)
        [void](Test-PestoPipeClient -Pipe $pipe -ExpectedProcessId $proc.Id)
        $utf8=[Text.UTF8Encoding]::new($false)
        $reader=[IO.StreamReader]::new($pipe,$utf8,$false,4096,$true)
        $writer=[IO.StreamWriter]::new($pipe,$utf8,4096,$true);$writer.AutoFlush=$true
        $password=$Credential.GetNetworkCredential().Password
        $payloadJson=([ordered]@{UserName=[string]$Credential.UserName;Password=$password}|ConvertTo-Json -Compress)
        # Dès le début de WriteLine, une transmission partielle est possible.
        Assert-PestoWorkerMayContinue -Mutation
        Set-PestoWorkerStage $(if($Action -eq 'Rename'){'Retrait Entra puis renommage local'}else{'Jonction dans Windows'}) ('Helper PID '+$proc.Id+' ; attente du résultat, ne pas relancer')
        $credentialSent=$true;$writer.WriteLine($payloadJson);$writer.Flush()
        $password=$null;$payloadJson=$null
        $readTask=$reader.ReadLineAsync()
        $responseDeadline=[DateTime]::UtcNow.AddSeconds(300)
        while(-not $readTask.Wait(250)){
            if(($script:PestoQueueMonitor -and $script:PestoQueueMonitor.CancelRequested) -or [DateTime]::UtcNow -ge $responseDeadline){
                return New-ActionResult 97 "État indéterminé : le helper $Action (PID $($proc.Id)) peut encore travailler. Ne relancez pas la mutation."
            }
            if($proc.HasExited -and -not $readTask.IsCompleted){return New-ActionResult 97 'Helper terminé après transmission sans réponse exploitable. Vérifiez le nom local et AD.'}
        }
        $response=$readTask.Result|ConvertFrom-Json -ErrorAction Stop
        if($response.Indeterminate -eq $true){return New-ActionResult 97 ([string]$response.Message)}
        if($response.Ok -is [bool] -and $response.Ok -and $response.HasSucceeded -is [bool] -and $response.HasSucceeded){
            $note=if($response.DsregLeft){" dsregcmd /leave exécuté avant renommage ; contrôler la réinscription Entra après redémarrage."}else{''}
            Write-Log ("$Action local confirmé.$note") 'INFO' $null 'rename'
            return New-ActionResult $ok "$Action local confirmé : '$env:COMPUTERNAME' vers '$NewName'. Redémarrage requis.$note"
        }
        if($response.Ok -is [bool] -and -not $response.Ok){return New-ActionResult $ko ("$Action élevé : "+[string]$response.Message)}
        return New-ActionResult 97 "État indéterminé : réponse du helper invalide après transmission."
    } catch {
        if($credentialSent){return New-ActionResult 97 "État indéterminé après transmission au helper : $($_.Exception.Message)"}
        return New-ActionResult $ko "Préparation de l'élévation impossible : $($_.Exception.Message)"
    } finally {
        $password=$null;$payloadJson=$null
        try{if($wait){$wait.AsyncWaitHandle.Dispose()}}catch{}
        foreach($o in @($writer,$reader,$pipe,$proc)){try{if($o){$o.Dispose()}}catch{}}
    }
}

function Test-PestoComputerName {
    <# Valide un nom d'hôte Windows/NetBIOS de 1 à 15 caractères. #>
    param([AllowNull()][string]$Name)
    $n = "$Name".Trim()
    if ($n.Length -lt 1 -or $n.Length -gt 15) { return $false }
    return ($n -match '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$')
}

function Test-PestoGeneratedComputerName {
    param([AllowNull()][string]$Name,[string]$Prefix="$script:PREFIXE")
    return ($null -ne (ConvertTo-PestoNameParts -Name $Name -Prefix $Prefix))
}

function Test-PestoOUPath {
    param([AllowNull()][string]$DistinguishedName)
    try {
        $parts=@(Split-PestoDistinguishedName $DistinguishedName)
        if($parts.Count -lt 2 -or $parts[0] -notmatch '^(?i:OU)='){return $false}
        foreach($p in $parts){if($p -notmatch '^(?i:OU|DC)='){return $false}}
        [void](Get-PestoDomainFromDN $DistinguishedName)
        return $true
    } catch {return $false}
}

function New-ActionResult {
    param([AllowNull()]$ExitCode,[string]$ExitMsg)
    if($ExitCode -isnot [int]){$ExitCode=97;$ExitMsg='Retour natif absent ou mal typé. '+$ExitMsg}
    return [pscustomobject]@{PSTypeName='Pesto.ActionResult';Schema=2;ExitCode=[int]$ExitCode;ExitMsg=$ExitMsg;Outcome=(Get-PestoOutcome -Code $ExitCode)}
}

function ConvertTo-PestoQuotedArg([string]$s) {
    if ($null -eq $s -or $s -eq '') { return '""' }
    if ($s -notmatch '[\s"]') { return $s }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $s.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
        if ($bs -gt 0)   { [void]$sb.Append('\' * $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    [void]$sb.Append('\' * ($bs * 2))
    [void]$sb.Append('"')
    $sb.ToString()
}

function Get-PestoSecretArgIndexes([string[]]$ArgList) {
    $m = @()
    for ($i = 0; $i -lt ($ArgList.Count - 1); $i++) {
        if ($ArgList[$i] -iin @('/p','/rp')) { $m += ($i + 1) }
    }
    return $m
}

function Invoke-PestoProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgList,
        [int[]]$MaskIndexes = @(),
        [string]$DisplayName,
        [string]$Context = 'process',
        [ValidateRange(1,3600)][int]$TimeoutSec = 120
    )
    $line = ($ArgList | ForEach-Object { ConvertTo-PestoQuotedArg $_ }) -join ' '
    if ($DisplayName) {
        $disp = for ($i = 0; $i -lt $ArgList.Count; $i++) {
            if ($MaskIndexes -contains $i) { '"********"' } else { ConvertTo-PestoQuotedArg $ArgList[$i] }
        }
        Write-Log ("$DisplayName " + ($disp -join ' ')) 'DEBUG' $null $Context
    }

    $p = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        $psi.Arguments = $line
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true
        $psi.CreateNoWindow = $true
        try {
            $oem = [System.Text.Encoding]::GetEncoding(850)
            $psi.StandardOutputEncoding = $oem
            $psi.StandardErrorEncoding  = $oem
        } catch {}

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $psi
        if (-not $p.Start()) { throw "Le processus '$FilePath' n'a pas démarré." }
        # Lecture asynchrone des deux flux : évite le deadlock stdout/stderr classique.
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill() } catch {}
            try { $p.WaitForExit() } catch {}
            Write-Log "Délai dépassé après $TimeoutSec s : $FilePath" 'ERROR' $null $Context
            return [PSCustomObject]@{ ExitCode = 1460; Output = "Délai d'exécution dépassé ($TimeoutSec s)." }
        }
        # Second WaitForExit : garantit le vidage complet des événements/flux .NET.
        $p.WaitForExit()
        $out = $outTask.Result
        $err = $errTask.Result
        return [PSCustomObject]@{ ExitCode = $p.ExitCode; Output = (($out + $err).Trim()) }
    } catch {
        Write-Log "Process impossible à lancer : $FilePath" 'ERROR' $_ $Context
        return [PSCustomObject]@{ ExitCode = 999; Output = $_.Exception.Message }
    } finally {
        if ($p) { try { $p.Dispose() } catch {} }
    }
}

function ConvertTo-PestoTaskFailureCode {
    <# Classification commune (Get-PestoNativeFailureCode) : seul un HRESULT Win32 (0x8007xxxx) ou un NativeErrorCode
       donne un code Windows. Un HRESULT d'une autre famille (ex. SCHED_E_* 0x8004xxxx) n'est jamais tronqué en faux
       code Win32. Après une demande Run, seul un refus certain (2, 5, 1326) reste un refus ; sinon 1460 (indéterminé). #>
    param($ErrorRecord,[bool]$RunAttempted)
    $native=Get-PestoNativeFailureCode $ErrorRecord
    $code=if($null -ne $native -and $native -gt 0 -and $native -le 65535){[int]$native}else{999}
    if($RunAttempted -and $code -notin @(2,5,1326)){$code=1460}
    return $code
}

function Invoke-PestoSchtasks {
    <# Adaptateur du contrat historique : utilise désormais Task Scheduler COM.
       Les commandes de création/lancement/suppression sont les seules autorisées. #>
    param([string[]]$ArgList,[int[]]$MaskIndexes=@())
    $service=$null;$folder=$null;$task=$null;$instance=$null;$runAttempted=$false
    try {
        if($script:SIM -or $script:GUI -or $script:SimOn){throw 'Planificateur réel interdit en simulation.'}
        if(@($ArgList|Where-Object{$_ -iin @('/p','/rp','/u')}).Count){throw 'Ancien transport avec secret explicitement interdit.'}
        $computer=Get-PestoTaskArgument $ArgList '/s'; $name=Get-PestoTaskArgument $ArgList '/tn'
        if(-not $computer){$computer=$env:COMPUTERNAME}
        if(-not (Test-PestoComputerName $computer)){throw 'Cible de tâche invalide.'}
        if($name -notmatch '^\\Pesto_[A-Za-z0-9_]+$'){throw 'Nom de tâche hors espace Pesto.'}
        $service=New-PestoTaskService $computer; $folder=$service.GetFolder('\')
        switch($ArgList[0].ToLowerInvariant()) {
            '/create' {
                Assert-PestoWorkerMayContinue -Mutation
                Set-PestoWorkerStage 'Création de tâche Pesto' $name
                $path=Get-PestoTaskArgument $ArgList '/xml'
                $xmlText=[IO.File]::ReadAllText($path,[Text.Encoding]::Unicode)
                # XML produit par Pesto, jamais du XML fourni par le CSV.
                [xml]$doc=$xmlText
                $principal=[string]$doc.Task.Principals.Principal.UserId
                Set-PestoTaskEvidence -Computer $computer -Name $name -Phase Registering
                if($principal -eq 'S-1-5-18') {
                    $task=$folder.RegisterTask($name,$xmlText,2,'SYSTEM',$null,5,$null)
                } else {
                    if(-not $script:cred -or $principal -ine $script:cred.UserName){throw 'Principal de tâche différent du compte Pesto.'}
                    $task=$folder.RegisterTask($name,$xmlText,2,$script:cred.UserName,$script:cred.GetNetworkCredential().Password,1,$null)
                }
                Set-PestoTaskEvidence -Computer $computer -Name $name -Phase Registered -DefinitionHash (Get-PestoTaskDefinitionHash ([string]$task.Xml))
            }
            '/run' {
                $task=$folder.GetTask($name);Assert-PestoTaskDefinition $computer $name $task
                Assert-PestoWorkerMayContinue -Mutation;Set-PestoWorkerStage 'Lancement de tâche Pesto' $name
                Set-PestoTaskEvidence -Computer $computer -Name $name -Phase StartRequested
                $runAttempted=$true;$instance=$task.Run($null)
                Set-PestoTaskEvidence -Computer $computer -Name $name -Phase Started
            }
            '/delete' {
                $task=$folder.GetTask($name);Assert-PestoTaskDefinition $computer $name $task
                if([int]$task.State -notin @(1,3)){throw 'Tâche active ou état inconnu : suppression refusée.'}
                $folder.DeleteTask($name,0)
                $remaining=$null;$absent=$false
                try{$remaining=$folder.GetTask($name)}catch{if((Get-PestoNativeFailureCode $_) -eq 2){$absent=$true}else{throw}}
                finally{Release-PestoComObject $remaining}
                if(-not $absent){throw 'La suppression de la tâche n’’est pas confirmée par relecture.'}
                Set-PestoTaskEvidence -Computer $computer -Name $name -Phase Deleted
            }
            default {throw 'Opération du Planificateur non autorisée.'}
        }
        return [pscustomobject]@{ExitCode=0;Output='Task Scheduler COM : demande acceptée.';RunAttempted=$runAttempted;LaunchState=$(if($runAttempted){'Started'}else{'NotRequested'})}
    } catch {
        $ex=$_.Exception;while($ex.InnerException){$ex=$ex.InnerException}
        # Une perte de réponse à Run ne prouve pas que la tâche n'a pas démarré.
        $code=ConvertTo-PestoTaskFailureCode -ErrorRecord $_ -RunAttempted $runAttempted
        Write-Log "Planificateur COM en échec (code $code)." 'ERROR' $_ 'task'
        return [pscustomobject]@{ExitCode=$code;Output=(Protect-PestoLogText $ex.Message);RunAttempted=$runAttempted;LaunchState=$(if(-not $runAttempted){'NotRequested'}elseif($code -in @(2,5,1326)){'Rejected'}else{'Unknown'})}
    } finally {
        Release-PestoComObject $instance;Release-PestoComObject $task
        Release-PestoComObject $folder;Release-PestoComObject $service
    }
}

function Get-PestoSchtasksTransportArgs {
    param([string]$ComputerName)
    return @('/s',$ComputerName)
}

function Get-PestoSchtasksHint([int]$Code) {
    switch ($Code) {
        0     { 'OK' }
        1     { 'Erreur générique schtasks.' }
        2     { 'Fichier introuvable côté cible ou XML inaccessible.' }
        5     { 'Accès refusé : droits admin insuffisants sur la cible.' }
        53    { 'Chemin réseau introuvable : cible injoignable SMB/RPC.' }
        1219  { 'Connexions multiples au même serveur : nettoyer les sessions net use.' }
        1326  { 'Échec de connexion : identifiants incorrects.' }
        1460  { 'Délai dépassé : état distant potentiellement indéterminé.' }
        1722  { 'Serveur RPC indisponible : service Planificateur ou pare-feu RPC.' }
        999   { 'Process impossible à lancer depuis ce poste.' }
        default { 'Code schtasks non documenté dans Pesto.' }
    }
}

function Test-PestoIsAdministrator {
    try {
        $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function New-PestoRunOnceTaskXml {
    <# Tâche volontairement SANS trigger : seul un appel COM Run explicite la lance.
       Un ancien TimeTrigger placé dans le passé pouvait être considéré comme manqué
       et provoquer un démarrage automatique en plus du /run explicite. #>
    param(
        [string]$Command,
        [string]$Arguments,
        [string]$UserId,
        [string]$LogonType = 'Password',
        [string]$RunLevel = 'HighestAvailable',
        [string]$Description = 'Pesto - tâche à la demande'
    )
    $cmdX  = [System.Security.SecurityElement]::Escape($Command)
    $argX  = [System.Security.SecurityElement]::Escape($Arguments)
    $usrX  = [System.Security.SecurityElement]::Escape($UserId)
    $descX = [System.Security.SecurityElement]::Escape($Description)
    $logonBlock = if ($LogonType -eq 'ServiceAccount') { '' } else { "      <LogonType>$LogonType</LogonType>`r`n" }
@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$descX</Description>
    <Author>Pesto</Author>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$usrX</UserId>
$logonBlock      <RunLevel>$RunLevel</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Priority>5</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$cmdX</Command>
      <Arguments>$argX</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

function ConvertTo-PestoPowerShellLiteral {
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { return "''" }
    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-PestoTaskRunResult {
    <# Lecture numérique, indépendante de la langue de Windows.
       Result=0 n'est un succès qu'après une exécution effectivement terminée. #>
    param([string]$TaskName,[string[]]$Transport,[int]$TimeoutSec=30)
    $computer=Get-PestoTaskArgument $Transport '/s'
    $deadline=[DateTime]::UtcNow.AddSeconds([Math]::Max(1,$TimeoutSec))
    $last=[pscustomobject]@{State='UNKNOWN';ResultRaw='267009';ResultNum=267009;Hint='exécution non confirmée'}
    do {
        $service=$null;$folder=$null;$task=$null
        try {
            $service=New-PestoTaskService $computer;$folder=$service.GetFolder('\');$task=$folder.GetTask($TaskName)
            Assert-PestoTaskDefinition $computer $TaskName $task
            $state=[int]$task.State; $result=[int64]$task.LastTaskResult; $lastRun=[DateTime]$task.LastRunTime
            if($state -eq 3 -and $lastRun.Year -ge 2000 -and $result -notin @(267008,267009,267011)) {
                Set-PestoTaskEvidence -Computer $computer -Name $TaskName -Phase Finished -NativeCode $result
                return [pscustomobject]@{State='READY';ResultRaw=[string]$result;ResultNum=$result;Hint=$(if($result -eq 0){'terminée, succès confirmé'}else{'terminée avec code non nul'})}
            }
            $last=[pscustomobject]@{State=[string]$state;ResultRaw='267009';ResultNum=267009;Hint='en attente / en cours / fin non confirmée'}
        } catch { Write-Log 'Résultat de tâche momentanément inaccessible.' 'WARN' $_ 'task' }
        finally {Release-PestoComObject $task;Release-PestoComObject $folder;Release-PestoComObject $service}
        if([DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 500}
    } while([DateTime]::UtcNow -lt $deadline)
    return $last
}

function Invoke-PestoSystemTaskScript {
    <# Tâche SYSTEM via Task Scheduler COM/RPC, sans WinRM ni secret en argument.
       LaunchState distingue un refus avant Run d'un résultat devenu incertain. #>
    param([string]$ComputerName,[string]$InnerScript,[string]$TaskPrefix='Pesto_System',[int]$TimeoutSec=35)
    $taskName='';$launchState='NotRequested'
    $makeResult={param([int]$Code,[string]$Message,[string]$Outcome)
        $answer=New-ActionResult $Code $Message
        $answer|Add-Member NoteProperty LaunchState $launchState
        $answer|Add-Member NoteProperty TaskOutcome $Outcome
        $answer|Add-Member NoteProperty TaskName $taskName
        return $answer
    }
    if($script:SIM -or $script:GUI){return (& $makeResult 20 'SIMULATION : aucune tâche SYSTEM.' 'NotStarted')}
    $taskId=[guid]::NewGuid().ToString('N').Substring(0,12)
    $taskName="\${TaskPrefix}_$taskId"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($InnerScript))
    $xml=New-PestoRunOnceTaskXml -Command '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -Arguments "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" `
        -UserId 'S-1-5-18' -LogonType 'ServiceAccount' -RunLevel 'HighestAvailable' -Description "Pesto - $TaskPrefix"
    $xmlPath=Join-Path $env:TEMP ("pesto_{0}_{1}.xml" -f $TaskPrefix,$taskId)
    $transport=Get-PestoSchtasksTransportArgs -ComputerName $ComputerName
    $keepTask=$false
    try {
        [IO.File]::WriteAllText($xmlPath,$xml,[Text.Encoding]::Unicode)
        $create=@('/create')+$transport+@('/tn',$taskName,'/xml',$xmlPath,'/f')
        $r=Invoke-PestoSchtasks -ArgList $create -MaskIndexes (Get-PestoSecretArgIndexes $create)
        if(-not $r -or $r.ExitCode -ne 0){return (& $makeResult 21 ("Création SYSTEM refusée : "+[string]$r.Output) 'NotStarted')}
        $run=@('/run')+$transport+@('/tn',$taskName)
        # Une exception ou un retour incomplet après cet appel reste incertain.
        $launchState='Unknown';$keepTask=$true
        $r2=Invoke-PestoSchtasks -ArgList $run -MaskIndexes (Get-PestoSecretArgIndexes $run)
        if($r2 -and $r2.ExitCode -ne 0 -and $r2.LaunchState -in @('NotRequested','Rejected')){
            $launchState=[string]$r2.LaunchState;$keepTask=$false
            return (& $makeResult 21 ("Lancement SYSTEM refusé : "+[string]$r2.Output) 'NotStarted')
        }
        if(-not $r2 -or $r2.ExitCode -ne 0){
            return (& $makeResult 97 ("Lancement SYSTEM non confirmé : '$taskName'. Tâche conservée, aucune répétition automatique.") 'Unknown')
        }
        $launchState='Started'
        $probe=Get-PestoTaskRunResult -TaskName $taskName -Transport $transport -TimeoutSec $TimeoutSec
        if(-not $probe -or $probe.State -cne 'READY' -or $null -eq $probe.ResultNum -or $probe.ResultNum -in @(267008,267009,267011)){
            return (& $makeResult 97 ("Tâche SYSTEM '$taskName' non confirmée terminée. Tâche conservée pour vérification.") 'Unknown')
        }
        $keepTask=$false
        switch([long]$probe.ResultNum){
            0 {return (& $makeResult 20 'Tâche SYSTEM terminée (TaskResult=0).' 'Completed')}
            42 {return (& $makeResult 42 'Retrait Entra confirmé sur la cible (TaskResult=42).' 'Completed')}
            43 {return (& $makeResult 43 'État AD seul confirmé, aucun retrait Entra (TaskResult=43).' 'Completed')}
            44 {return (& $makeResult 44 'Préparation cible refusée avant tout retrait Entra (TaskResult=44).' 'Completed')}
            97 {return (& $makeResult 97 'Tâche terminée, résultat de mutation indéterminé (TaskResult=97).' 'Completed')}
            default {return (& $makeResult 21 ("Tâche terminée avec le code "+[string]$probe.ResultNum+'. Effet à vérifier selon la commande.') 'Completed')}
        }
    }catch{
        if($launchState -notin @('NotRequested','Rejected')){
            $keepTask=$true;return (& $makeResult 97 ('Résultat SYSTEM inconnu : '+$_.Exception.Message) 'Unknown')
        }
        return (& $makeResult 21 ('Tâche SYSTEM non lancée : '+$_.Exception.Message) 'NotStarted')
    }finally{
        if(-not $keepTask){
            try{$del=@('/delete')+$transport+@('/tn',$taskName,'/f');[void](Invoke-PestoSchtasks -ArgList $del -MaskIndexes (Get-PestoSecretArgIndexes $del))}catch{}
        }
        Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PestoDsregLeaveLocal {
    param([string]$ExpectedComputerName,[string]$ExpectedDomain,[bool]$AllowHybridLeave=$true,[string]$OperationId)
    $leavePending=$false;$leaveDone=$false;$log='';$receiptPath=''
    function Get-PestoEntraDisposition {
        param([string]$Status,[bool]$Allow)
        $aad=[regex]::Matches($Status,'(?im)^\s*AzureAdJoined\s*:\s*(YES|NO)\s*$')
        $dom=[regex]::Matches($Status,'(?im)^\s*DomainJoined\s*:\s*(YES|NO)\s*$')
        if($aad.Count -ne 1 -or $dom.Count -ne 1 -or $dom[0].Groups[1].Value -ine 'YES'){return 'Refuse'}
        if($aad[0].Groups[1].Value -ieq 'NO'){return 'Skip'}
        if($Allow){return 'Leave'}
        return 'Refuse'
    }
    function Invoke-DsregNative {
        param([string]$Argument,[int]$TimeoutSec=25)
        $p=$null
        try {
            $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$exe;$psi.Arguments=$Argument
            $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            $p=[Diagnostics.Process]::new();$p.StartInfo=$psi
            if(-not $p.Start()){throw 'dsregcmd non démarré.'}
            $stdout=$p.StandardOutput.ReadToEndAsync();$stderr=$p.StandardError.ReadToEndAsync()
            if(-not $p.WaitForExit($TimeoutSec*1000)){
                throw [TimeoutException]::new("dsregcmd $Argument : délai dépassé ; le processus peut encore terminer. PID=$($p.Id)")
            }
            return [pscustomobject]@{ExitCode=[int]$p.ExitCode;Output=($stdout.Result+"`r`n"+$stderr.Result).Trim()}
        } finally {if($p){$p.Dispose()}}
    }
    function Save-DsregReceipt {
        param([string]$Phase)
        $data=[ordered]@{Schema=1;OperationId=$id.ToString('N');Computer=$env:COMPUTERNAME;Utc=[DateTime]::UtcNow.ToString('o');Phase=$Phase}
        $tmp=$receiptPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
        try{
            $bytes=[Text.Encoding]::UTF8.GetBytes(($data|ConvertTo-Json -Compress))
            $f=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$f.Write($bytes,0,$bytes.Length);$f.Flush($true)}finally{$f.Dispose()}
            if([IO.File]::Exists($receiptPath)){[IO.File]::Replace($tmp,$receiptPath,[Management.Automation.Language.NullString]::Value)}
            else{[IO.File]::Move($tmp,$receiptPath)}
        }finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
    }
    try {
        if($ExpectedComputerName -ine $env:COMPUTERNAME){throw 'La préparation Entra ne s''exécute pas sur la cible attendue.'}
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        try{$admin=([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}finally{$identity.Dispose()}
        if(-not $admin){throw 'Préparation Entra non élevée.'}
        $cs=@(Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 15 -ErrorAction Stop)
        if($cs.Count -ne 1 -or -not $cs[0].PartOfDomain -or $cs[0].DomainRole -notin @(1,3) -or
            -not $ExpectedDomain -or $cs[0].Domain -ine $ExpectedDomain){throw 'Domaine ou rôle de la cible non conforme. Retrait refusé.'}
        $systemDir=if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){'Sysnative'}else{'System32'}
        $exe=Join-Path $env:SystemRoot ($systemDir+'\dsregcmd.exe')
        if(-not [IO.File]::Exists($exe)){throw 'dsregcmd.exe absent.'}
        # dsregcmd /status peut dépasser une minute sur un poste hybride (diagnostics réseau) : lecture seule, délai large.
        $before=Invoke-DsregNative -Argument '/status' -TimeoutSec 90
        if($before.ExitCode -ne 0){throw 'État Entra illisible.'}
        $disposition=Get-PestoEntraDisposition -Status $before.Output -Allow $AllowHybridLeave
        if($disposition -eq 'Refuse'){throw 'État Entra ambigu, non membre AD ou retrait non autorisé. Aucun retrait.'}
        if($disposition -eq 'Skip'){
            return [pscustomobject]@{ExitCode=20;Entra='Skipped';ExitMsg='AD seul confirmé : aucun dsregcmd /leave nécessaire ni exécuté.'}
        }
        if(-not $AllowHybridLeave){throw 'Poste hybride : le retrait préalable n''est pas autorisé par la configuration.'}
        $id=[Guid]::Empty
        if(-not [Guid]::TryParse($OperationId,[ref]$id) -or $id -eq [Guid]::Empty){throw 'Identifiant de préparation absent.'}
        $dir=[IO.Path]::Combine([Environment]::GetFolderPath('CommonApplicationData'),'GP','Entra')
        $parent=$dir
        while($parent){
            if(Test-Path -LiteralPath $parent){if((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Stockage Entra lié refusé.'}}
            $next=[IO.Path]::GetDirectoryName($parent);if($next -eq $parent){break};$parent=$next
        }
        $acl=[Security.AccessControl.DirectorySecurity]::new();$acl.SetAccessRuleProtection($true,$false)
        foreach($sid in @('S-1-5-18','S-1-5-32-544')){
            $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
        }
        [void][IO.Directory]::CreateDirectory($dir,$acl)
        Set-Acl -LiteralPath $dir -AclObject $acl -ErrorAction Stop
        $receiptPath=Join-Path $dir ($id.ToString('N')+'.json')
        if(Test-Path -LiteralPath $receiptPath){throw 'Préparation déjà enregistrée sous cet identifiant. Vérification requise, pas de nouveau retrait.'}
        Save-DsregReceipt 'LeaveRequested'
        $leavePending=$true
        $left=Invoke-DsregNative -Argument '/leave' -TimeoutSec 60
        $leaveDone=($left.ExitCode -eq 0)
        if(-not $leaveDone){throw ('Retour /leave non confirmé, code '+$left.ExitCode)}
        Save-DsregReceipt 'LeaveReturnedSuccess'
        # Contrôle après retrait : deux lectures seules au plus (120 s chacune), jamais un second /leave.
        $conform=$false;$lastRead=''
        foreach($attempt in 1..2){
            try{
                $after=Invoke-DsregNative -Argument '/status' -TimeoutSec 120
                $a=[regex]::Matches($after.Output,'(?im)^\s*AzureAdJoined\s*:\s*(YES|NO)\s*$')
                $d=[regex]::Matches($after.Output,'(?im)^\s*DomainJoined\s*:\s*(YES|NO)\s*$')
                if($after.ExitCode -eq 0 -and $a.Count -eq 1 -and $d.Count -eq 1 -and $a[0].Groups[1].Value -ieq 'NO' -and $d[0].Groups[1].Value -ieq 'YES'){$conform=$true;break}
                $lastRead='état relu non conforme'
            }catch{$lastRead=$_.Exception.Message}
            if($attempt -lt 2){Start-Sleep -Seconds 5}
        }
        if(-not $conform){throw ('Contrôle après retrait non conforme ('+$lastRead+'). Aucun renommage lancé.')}
        Save-DsregReceipt 'LeaveConfirmed_ReenrollmentPending'
        $leavePending=$false
        return [pscustomobject]@{ExitCode=20;Entra='Confirmed';ExitMsg='Retrait Entra confirmé sur la cible. Réinscription à vérifier séparément après intervention.'}
    }catch{
        $phase=if($leaveDone){'LeaveReturnedSuccess_VerificationFailed'}elseif($leavePending){'LeaveUncertain'}else{'NotStarted'}
        if($receiptPath){try{Save-DsregReceipt $phase}catch{}}
        return [pscustomobject]@{ExitCode=$(if($leavePending -or $leaveDone){97}else{21});Entra=$(if($leavePending -or $leaveDone){'Uncertain'}else{'NotRequested'});
            ExitMsg=('Préparation Entra : '+$_.Exception.Message+' Aucun renommage lancé. '+$(if($receiptPath){'Reçu cible : '+$receiptPath}else{''}))}
    }
}

function Invoke-PestoDsregLeaveBeforeRename {
    param([string]$ComputerName)
    if($script:SIM -or $script:GUI){return New-ActionResult 20 'SIMULATION : préparation conditionnelle Entra, aucune écriture.'}
    if(-not(Test-PestoComputerName $ComputerName)){return New-ActionResult 96 'Cible invalide.'}
    Assert-PestoWorkerMayContinue
    Set-PestoWorkerStage 'Contrôle Entra sur la cible' 'Retrait uniquement si hybride et autorisé'
    try {
        Set-PestoEffect -Name Entra -Value 'Requested'
        $id=$script:ActiveIntervention.OperationId
        $allowed=($script:EntraPolicy -eq 'HybridOnly')
        if($ComputerName -ieq $env:COMPUTERNAME){
            $r=Invoke-PestoDsregLeaveLocal -ExpectedComputerName $ComputerName -ExpectedDomain $script:DOMAINE -OperationId $id -AllowHybridLeave $allowed
        }else{
            $definition=(Get-Command Invoke-PestoDsregLeaveLocal -CommandType Function -ErrorAction Stop).Definition
            $taskArgs=@((ConvertTo-PestoPowerShellLiteral $ComputerName),(ConvertTo-PestoPowerShellLiteral $script:DOMAINE),(ConvertTo-PestoPowerShellLiteral $id))
            $boolean=if($allowed){'$true'}else{'$false'}
            $inner="function Invoke-PestoDsregLeaveLocal {`r`n$definition`r`n}`r`n"+
                "`$r=Invoke-PestoDsregLeaveLocal -ExpectedComputerName $($taskArgs[0]) -ExpectedDomain $($taskArgs[1]) -OperationId $($taskArgs[2]) -AllowHybridLeave $boolean`r`n"+
                'if($r.ExitCode -eq 20 -and $r.Entra -eq ''Skipped''){exit 43};if($r.ExitCode -eq 20 -and $r.Entra -eq ''Confirmed''){exit 42};if($r.ExitCode -eq 97){exit 97};if($r.ExitCode -eq 21 -and $r.Entra -eq ''NotRequested''){exit 44};exit 1'
            $task=Invoke-PestoSystemTaskScript -ComputerName $ComputerName -InnerScript $inner -TaskPrefix 'Pesto_DsregLeave' -TimeoutSec 450
            if($task -and $task.ExitCode -eq 43){$r=[pscustomobject]@{ExitCode=20;Entra='Skipped';ExitMsg='Cible AD seule : aucun retrait Entra exécuté.'}}
            elseif($task -and $task.ExitCode -eq 42){$r=[pscustomobject]@{ExitCode=20;Entra='Confirmed';ExitMsg='Retrait Entra confirmé sous SYSTEM sur la cible. Réinscription à vérifier.'}}
            elseif($task -and (($task.ExitCode -eq 44 -and $task.TaskOutcome -eq 'Completed') -or
                ($task.ExitCode -eq 21 -and $task.TaskOutcome -eq 'NotStarted' -and $task.LaunchState -in @('NotRequested','Rejected')))){
                $r=[pscustomobject]@{ExitCode=21;Entra='NotRequested';ExitMsg=('Aucun retrait Entra lancé : '+$task.ExitMsg)}
            }
            else{$r=[pscustomobject]@{ExitCode=97;Entra='Uncertain';ExitMsg='Préparation distante non confirmée. Consulter le reçu cible avant toute reprise.'}}
        }
        Set-PestoEffect -Name Entra -Value $r.Entra
        Write-Log $r.ExitMsg $(if($r.ExitCode -eq 20){'INFO'}else{'ERROR'}) $null 'dsreg'
        return $r
    }catch{return New-ActionResult 97 ('Préparation Entra non confirmée : '+$_.Exception.Message+'. Aucun renommage lancé.')}
}

function New-PestoRenameTaskScript {
    # Construction pure du script de la tâche de renommage ; littéraux déjà échappés par ConvertTo-PestoPowerShellLiteral.
    param([Parameter(Mandatory=$true)][string]$NewLiteral,[Parameter(Mandatory=$true)][string]$LogLiteral)
    $newLit=$NewLiteral;$logLit=$LogLiteral
    return @"
`$ErrorActionPreference='Stop'
`$new=$newLit
`$log=$logLit
try {
  New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName(`$log)) -Force | Out-Null
  ("START {0} {1} -> {2}" -f (Get-Date).ToString('o'),`$env:COMPUTERNAME,`$new) | Set-Content -LiteralPath `$log -Encoding UTF8

  # La tâche tourne déjà sous le compte AD saisi dans Pesto avec RunLevel=Highest.
  # Pour un appel LOCAL, Win32_ComputerSystem.Rename(NULL,NULL) utilise le contexte
  # de l'appelant : aucun secret n'est réinjecté dans ce script.
  `$cs=Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
  if(`$null -eq `$cs){ throw 'Win32_ComputerSystem introuvable.' }
  `$ret=`$cs.Rename(`$new,`$null,`$null)
  `$rv=if(`$ret -and `$ret.PSObject.Properties['ReturnValue']){[uint32]`$ret.ReturnValue}else{[uint32]4294967295}
  if(`$rv -eq [uint32]4294967295){ exit 97 }
  if(`$rv -ne 0){
    `$rvText=try{(New-Object ComponentModel.Win32Exception([int]`$rv)).Message}catch{'erreur Windows/WMI non traduite'}
    throw "Win32_ComputerSystem.Rename a renvoyé le code `$rv (`$rvText)."
  }

  ("OK {0} renommage WMI confirmé (ReturnValue=0) ; redémarrage requis." -f (Get-Date).ToString('o')) | Add-Content -LiteralPath `$log -Encoding UTF8
  exit 0
} catch {
  `$m=[string]`$_.Exception.Message
  ("ERROR {0} {1}: {2}" -f (Get-Date).ToString('o'),`$_.Exception.GetType().FullName,`$m) | Add-Content -LiteralPath `$log -Encoding UTF8
  if(`$m -match '(?i)(Azure\s*AD|Microsoft\s*Entra|nom d.?h[oô]te.*Azure|hostname.*Azure|update.*host.*Entra)'){
    "ENTRA_RENAME_BLOCK" | Add-Content -LiteralPath `$log -Encoding UTF8
    exit 43
  }
  if(`$m -match '(?i)(RPC|0x800706ba|timed?\s*out|d.lai|transport)'){exit 97}
  exit 1
}
"@
}

function Invoke-RenameComputerTaskFallback {
    <# Fallback local/distant : exécute Win32_ComputerSystem.Rename dans une tâche
       élevée directement sur la cible, sous le compte AD déjà saisi dans Pesto. Le processus
       Pesto peut donc rester non élevé : aucune seconde saisie interactive n'est requise,
       et l'erreur Azure AD / Entra d'origine reste détectable. #>
    param([string]$Computername,[string]$NewName,[switch]$DsregLeaveConfirmed)

    if (-not $script:cred) {
        return New-ActionResult 21 'Fallback tâche planifiée indisponible en mode Compte Windows sans élévation suffisante.'
    }
    if($script:SIM -or $script:GUI){return New-ActionResult 20 "SIMULATION : aucune tâche de renommage créée."}
    if(-not (Test-PestoComputerName $Computername) -or -not (Test-PestoGeneratedComputerName $NewName)){return New-ActionResult 21 "Paramètres du renommage invalides."}
    if(-not $DsregLeaveConfirmed){
        $leave=Invoke-PestoDsregLeaveBeforeRename -ComputerName $Computername
        if(-not $leave){return New-ActionResult 97 'Résultat dsregcmd absent : aucun repli de renommage lancé.'}
        if($leave.ExitCode -ne 20){return $leave}
    }
    Set-PestoEffect -Name Rename -Value 'Requested'
    $taskId=[guid]::NewGuid().ToString('N').Substring(0,12)
    $taskName="\Pesto_Rename_$taskId"
    $logLocal="C:\ProgramData\Pesto\rename_$taskId.log"
    $newLit=ConvertTo-PestoPowerShellLiteral $NewName
    $logLit=ConvertTo-PestoPowerShellLiteral $logLocal
    $inner=New-PestoRenameTaskScript -NewLiteral $newLit -LogLiteral $logLit
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))
    $xml=New-PestoRunOnceTaskXml -Command '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -Arguments "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -UserId $script:cred.UserName -Description 'Pesto - fallback RenameComputer'
    $xmlPath=Join-Path $env:TEMP ("pesto_rename_{0}.xml" -f $taskId)
    $transport=Get-PestoSchtasksTransportArgs -ComputerName $Computername
    $keepTask=$false;$runRequested=$false
    try {
      [IO.File]::WriteAllText($xmlPath,$xml,[Text.Encoding]::Unicode)
      $create=@('/create')+$transport+@('/tn',$taskName,'/xml',$xmlPath)
      $r=Invoke-PestoSchtasks -ArgList $create -MaskIndexes (Get-PestoSecretArgIndexes $create)
      if($r.ExitCode -ne 0){ return New-ActionResult 21 ("Fallback tâche planifiée : création KO (code {0}, {1}) : {2}" -f $r.ExitCode,(Get-PestoSchtasksHint $r.ExitCode),$r.Output) }
      $run=@('/run')+$transport+@('/tn',$taskName)
      $runRequested=$true
      $r2=Invoke-PestoSchtasks -ArgList $run -MaskIndexes (Get-PestoSecretArgIndexes $run)
      if($r2.ExitCode -eq 1460){
        $keepTask=$true
        return New-ActionResult 97 "ÉTAT INDÉTERMINÉ : la demande de lancement de la tâche de renommage '$taskName' a dépassé le délai. Elle a pu démarrer ; la tâche est conservée et la file doit s'arrêter."
      }
      if($r2.ExitCode -ne 0){ return New-ActionResult 21 ("Fallback tâche planifiée : lancement KO (code {0}, {1}) : {2}" -f $r2.ExitCode,(Get-PestoSchtasksHint $r2.ExitCode),$r2.Output) }
      $probe=Get-PestoTaskRunResult -TaskName $taskName -Transport $transport -TimeoutSec 35
      $tail=Get-PestoRemoteTaskLogTail -ComputerName $Computername -LocalLogPath $logLocal
      $tailMsg=if($tail){" | log cible : $tail"}else{''}
      if($probe -and $probe.ResultNum -eq 0){ return New-ActionResult 20 "`"$Computername`" renommé en `"$NewName`" via tâche élevée$tailMsg" }
      if($probe -and $probe.ResultNum -eq 97){return New-ActionResult 97 'La tâche ne peut pas confirmer le résultat WMI.'}
      if($probe -and $probe.ResultNum -eq 43){ return New-ActionResult 21 "Microsoft Entra/Azure AD bloque la mise à jour du nom d'hôte pendant le renommage élevé.$tailMsg" }
      if($probe -and $probe.ResultNum -in @(267008,267009,267011)){
        $keepTask=$true
        return New-ActionResult 97 ("ÉTAT INDÉTERMINÉ : la tâche de renommage '$taskName' n'est pas confirmée terminée ({0}, {1}). La file doit être arrêtée avant toute autre mutation. La tâche est conservée pour diagnostic.{2}" -f $probe.ResultRaw,$probe.Hint,$tailMsg)
      }
      if($probe){ return New-ActionResult 21 ("Fallback tâche planifiée terminé en erreur : {0} ({1}){2}" -f $probe.ResultRaw,$probe.Hint,$tailMsg) }
      $keepTask=$true
      return New-ActionResult 97 "ÉTAT INDÉTERMINÉ : tâche de renommage '$taskName' lancée, mais aucun résultat n'a pu être lu. Vérifiez le poste avant toute autre action ; la tâche est conservée pour diagnostic.$tailMsg"
    } catch {
      Write-Log "Fallback tâche planifiée a échoué ('$Computername' -> '$NewName')." 'ERROR' $_ 'rename-task'
      if($runRequested){$keepTask=$true;return New-ActionResult 97 "Résultat de la tâche inconnu après lancement : $($_.Exception.Message)"}
      return New-ActionResult 21 "Fallback tâche planifiée : $($_.Exception.Message)"
    } finally {
      if(-not $keepTask){
        try { $del=@('/delete')+$transport+@('/tn',$taskName,'/f'); [void](Invoke-PestoSchtasks -ArgList $del -MaskIndexes (Get-PestoSecretArgIndexes $del)) } catch {}
      }
      Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
    }
}

function Request-ComputerReboot {
    <# Demande un redémarrage après action réussie. Ne modifie pas le statut AD de
       la ligne : un reboot KO est journalisé en avertissement, sans transformer un
       rename/move réussi en échec métier. #>
    param([string]$ComputerName, [ValidateRange(0,86400)][int]$DelaySeconds = 0)

    if ([string]::IsNullOrWhiteSpace($ComputerName)) {
        return New-ActionResult 41 'Redémarrage impossible : nom de poste vide.'
    }
    if ($script:SIM -or $script:SimOn -or $script:GUI) {
        return New-ActionResult 40 "SIMU - redémarrage demandé pour `"$ComputerName`" dans $DelaySeconds s"
    }

    if($DelaySeconds -gt 0){
        return New-ActionResult 41 'Redémarrage différé non lancé : un délai shutdown impose la fermeture forcée. Utilisez Plus tard ou un redémarrage immédiat explicitement confirmé.'
    }
    $reason = 'Pesto : redémarrage demandé après renommage/déplacement.' 
    $isLocal = ($ComputerName -ieq $env:COMPUTERNAME -or $ComputerName -ieq 'localhost' -or $ComputerName -eq '.')
    $shutdownArgs = @('/r', '/t', [string]$DelaySeconds, '/c', $reason)

    if ($isLocal) {
        $exe = Join-Path $env:SystemRoot 'System32\shutdown.exe'
        $r = Invoke-PestoProcess -FilePath $exe -ArgList $shutdownArgs -DisplayName 'shutdown' -Context 'reboot'
        if ($r.ExitCode -eq 0) { return New-ActionResult 40 "Redémarrage local demandé dans $DelaySeconds s" }
        return New-ActionResult 41 ("Redémarrage local KO (code {0}) : {1}" -f $r.ExitCode, $r.Output)
    }

    $taskId   = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $taskName = "\Pesto_Reboot_$taskId"
    $argLine  = ($shutdownArgs | ForEach-Object { ConvertTo-PestoQuotedArg $_ }) -join ' '
    $xml      = New-PestoRunOnceTaskXml -Command '%SystemRoot%\System32\shutdown.exe' -Arguments $argLine -UserId 'S-1-5-18' -LogonType 'ServiceAccount' -Description 'Pesto - redémarrage demandé après action'
    $xmlPath  = Join-Path $env:TEMP ("pesto_reboot_{0}.xml" -f $taskId)
    $transport = Get-PestoSchtasksTransportArgs -ComputerName $ComputerName
    $keepTask=$true

    try {
        [System.IO.File]::WriteAllText($xmlPath, $xml, [System.Text.Encoding]::Unicode)

        $createArgs = @('/create') + $transport + @('/tn', $taskName, '/xml', $xmlPath, '/f')
        $r = Invoke-PestoSchtasks -ArgList $createArgs -MaskIndexes (Get-PestoSecretArgIndexes $createArgs)
        if ($r.ExitCode -ne 0) {
            return New-ActionResult 41 ("Redémarrage : création tâche KO pour `"{0}`" (code {1}, {2}) : {3}" -f $ComputerName, $r.ExitCode, (Get-PestoSchtasksHint $r.ExitCode), $r.Output)
        }

        $runArgs = @('/run') + $transport + @('/tn', $taskName)
        $r2 = Invoke-PestoSchtasks -ArgList $runArgs -MaskIndexes (Get-PestoSecretArgIndexes $runArgs)
        if ($r2.ExitCode -ne 0) {
            return New-ActionResult 41 ("Redémarrage : lancement tâche KO pour `"{0}`" (code {1}, {2}) : {3}" -f $ComputerName, $r2.ExitCode, (Get-PestoSchtasksHint $r2.ExitCode), $r2.Output)
        }

        $probe = Get-PestoTaskRunResult -TaskName $taskName -Transport $transport -TimeoutSec 8
        if(-not $probe -or $probe.ResultNum -in @(267008,267009,267011,267045)){return New-ActionResult 41 ('Demande distante transmise, résultat non confirmé. Tâche conservée : '+$taskName)}
        $keepTask=$false
        if ($probe.ResultNum -ne 0) {
            return New-ActionResult 41 ("Redémarrage demandé mais tâche en code non nul pour `"{0}`" : {1} ({2})" -f $ComputerName, $probe.ResultRaw, $probe.Hint)
        }
        return New-ActionResult 40 "Commande de redémarrage acceptée sur `"$ComputerName`". Le redémarrage effectif reste à constater."
    } catch {
        Write-Log "Demande de redémarrage a échoué ('$ComputerName')." 'ERROR' $_ 'reboot'
        return New-ActionResult 41 "Redémarrage KO pour `"$ComputerName`" : $($_.Exception.Message)"
    } finally {
        try {
            if(-not $keepTask){
            $delArgs = @('/delete') + $transport + @('/tn', $taskName, '/f')
            $cleanup=Invoke-PestoSchtasks -ArgList $delArgs -MaskIndexes (Get-PestoSecretArgIndexes $delArgs)
            if($cleanup.ExitCode -ne 0){Write-Log ('Tâche de redémarrage non supprimée : '+$taskName) 'WARN' $null 'cleanup'}
            }
        } catch {}
        Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PestoElevatedDomainJoin {
    param([string]$Domain,[string]$OUPath,[string]$NewName,[string]$DC,$Credential)
    return Invoke-PestoElevatedLocalChange -Action Join -Domain $Domain -OUPath $OUPath -NewName $NewName -DC $DC -Credential $Credential
}

function AddToDomain {
    <# Joint le poste local au domaine (mode hors-domaine uniquement).
       Pesto doit deja etre eleve au demarrage. Le credential AD saisi au login
       est reutilise ; aucune demande d'elevation n'est lancee pendant l'action. #>
    param($DC,$DOMAINE,$OU,$NEWNAME,$CRED)
    $NEWNAME = "$NEWNAME".Trim().ToUpperInvariant()
    $OU = "$OU".Trim()

    if (-not (Test-PestoGeneratedComputerName $NEWNAME)) {
        return New-ActionResult 11 "Nom de jonction invalide ou hors convention : '$NEWNAME'."
    }
    if (-not (Test-PestoOUPath $OU) -or -not (Test-PestoOUInConfiguredScope $OU) -or (Get-PestoDomainFromDN $OU) -ine $DOMAINE.TrimEnd('.')) {
        return New-ActionResult 11 "OU de jonction invalide : '$OU'."
    }
    if (-not $CRED) {
        return New-ActionResult 11 'Jonction impossible : un compte de domaine explicite est requis.'
    }
    $dcFqdn = "$DC".Trim().TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($dcFqdn) -or $dcFqdn -ieq "$DOMAINE".Trim().TrimEnd('.') -or $dcFqdn -notmatch '^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$') {
        return New-ActionResult 11 "Jonction bloquée : contrôleur de domaine FQDN invalide ou non résolu ('$DC')."
    }

    if ($script:SIM -or $script:GUI) {
        Show-MsgWarning "SIMU AddToDomain`nPréparer le nom local $NEWNAME, puis Add-Computer -DomainName $DOMAINE -Server $dcFqdn -OUPath `"$OU`" -Options JoinWithNewName,AccountCreate -Credential <cred> -PassThru" 'Add-Computer (SIMU)'
        return New-ActionResult 10 "SIMU - `"$env:COMPUTERNAME`" → domaine `"$DOMAINE`" / nom `"$NEWNAME`" / OU `"$OU`""
    }

    try { $existing = Find-ADComputerByName -Name $NEWNAME }
    catch {
        Write-Log "Vérification d'unicité impossible avant jonction ('$NEWNAME')." 'ERROR' $_ 'AD'
        return New-ActionResult 11 "Vérification du nom impossible : $($_.Exception.Message)"
    }
    if($existing){
        if(-not $script:AllowPrecreatedJoin -or -not $script:ExpectedJoinAccountGuid -or
           @($existing).Count -ne 1 -or ([Guid]$existing.ObjectGUID).ToString('D') -ine $script:ExpectedJoinAccountGuid -or
           (Get-PestoParentDN ([string]$existing.DistinguishedName)) -ine $OU){
            return New-ActionResult 13 'Compte déjà présent ou différent du compte précréé confirmé. Aucun objet supprimé.'
        }
    }elseif($script:AllowPrecreatedJoin){return New-ActionResult 13 'Le compte précréé confirmé a disparu. Refaire la préparation.'}

    # Add-Computer modifie la machine locale : le credential de domaine ne donne
    # PAS un jeton administrateur local au processus Pesto.
    if (-not (Test-PestoIsAdministrator)) {
        return New-ActionResult 96 'Jonction non lancée : Pesto n''est pas élevé. Relancez Pesto.exe pour autoriser l''UAC avant la connexion.'
    }

    $renameRequested=$false;$joinRequested=$false
    try {
        # Add-Computer -NewName peut joindre sous l'ancien nom avant le renommage.
        # Préparer le nom LOCAL, puis JoinWithNewName reprend ce nom sans reboot.
        # Microsoft Add-Computer, exemple 10. Aucun compte AD ancien n'est réutilisé.
        $before=Get-PestoJoinLocalStatus
        if(-not $before -or $before.PartOfDomain -isnot [bool] -or $before.PartOfDomain -or
           $before.PendingRename -isnot [bool] -or $before.PendingRename -or $before.DomainRole -notin @(0,2) -or
           $before.Admin -isnot [bool] -or -not $before.Admin -or -not $before.MachineId -or -not $before.BootUtc -or
           $before.Computer -ine $env:COMPUTERNAME -or $before.ActiveName -ine $before.Computer -or
           $before.ConfiguredName -ine $before.ActiveName){
            return New-ActionResult 96 'État local hors domaine non confirmé ou changement de nom déjà en attente. Aucune commande lancée.'
        }
        $machineId=[string]$before.MachineId;$bootUtc=[string]$before.BootUtc;$activeName=[string]$before.ActiveName
        if(-not $script:ActiveIntervention){return New-ActionResult 96 'Reçu d’’intervention absent. Aucune commande de jonction lancée.'}
        if(Test-PestoJoinIntervention $script:ActiveIntervention){
            $e=$script:ActiveIntervention.JoinEvidence
            if(-not $e -or $e.NativeStatus -ne 'Prepared' -or $e.MachineId -ine $machineId -or $e.BeforeBootUtc -ne $bootUtc -or
               $script:ActiveIntervention.TargetMachineId -ine $machineId){
                return New-ActionResult 96 'Identité ou reçu initial de jonction modifié. Aucune commande lancée.'
            }
        }
        if($activeName -ine $NEWNAME){
            Assert-PestoWorkerMayContinue -Mutation
            Set-PestoEffect -Name Rename -Value Requested
            Set-PestoWorkerStage 'Préparation locale du nom' ($activeName+' → '+$NEWNAME)
            Assert-PestoWorkerMayContinue
            $renameRequested=$true
            $renamed=@(Rename-Computer -NewName $NEWNAME -PassThru -Force -ErrorAction Stop -WarningAction SilentlyContinue)
            if(-not(Test-PestoConfirmedChange $renamed)){
                return New-ActionResult 97 'Préparation locale du nom non confirmée. Aucun ajout au domaine lancé ; vérifier le nom actif et le nom en attente avant toute reprise.'
            }
        }
        # Relecture obligatoire : un autre changement ou un redémarrage invalide le plan.
        $after=Get-PestoJoinLocalStatus
        if(-not $after -or $after.PartOfDomain -isnot [bool] -or $after.PartOfDomain -or $after.DomainRole -notin @(0,2) -or
           $after.Admin -isnot [bool] -or -not $after.Admin -or $after.MachineId -ine $machineId -or $after.BootUtc -ne $bootUtc -or
           $after.Computer -inotmatch ('^('+[regex]::Escape($activeName)+'|'+[regex]::Escape($NEWNAME)+')$') -or $after.ActiveName -ine $activeName -or $after.ConfiguredName -ine $NEWNAME -or
           $after.PendingRename -isnot [bool] -or $after.PendingRename -ne ($activeName -ine $NEWNAME)){
            return New-ActionResult $(if($renameRequested){97}else{96}) 'État Windows modifié ou nouveau nom local non confirmé. Aucun ajout au domaine lancé. Conserver le reçu et vérifier le poste.'
        }
        if($renameRequested){Set-PestoEffect -Name Rename -Value Confirmed}
        Assert-PestoWorkerMayContinue -Mutation
        $ac = @{
            DomainName = $DOMAINE
            OUPath = $OU
            Options = @('JoinWithNewName','AccountCreate')
            Credential = $CRED
            PassThru = $true
            Force = $true
            ErrorAction = 'Stop'
            WarningAction = 'SilentlyContinue'
        }
        $ac.Server = $dcFqdn
        Set-PestoWorkerStage 'Jonction Windows en cours' $NEWNAME
        if(Test-PestoJoinIntervention $script:ActiveIntervention){Set-PestoJoinNativeStatus -Status Requested}
        Assert-PestoWorkerMayContinue
        $joinRequested=$true
        $change = @(Add-Computer @ac)
        if (-not (Test-PestoConfirmedChange $change)) {
            if($change.Count -eq 1 -and $change[0].HasSucceeded -is [bool] -and -not $change[0].HasSucceeded){
                if($renameRequested){return New-ActionResult 97 'Ajout au domaine refusé après préparation du nouveau nom local. Le changement de nom reste à vérifier ; aucune reprise ni annulation automatique.'}
                return New-ActionResult 11 "Add-Computer a confirmé HasSucceeded=False."
            }
            return New-ActionResult 97 "Jonction indéterminée : Add-Computer n'a pas renvoyé de confirmation fiable. Vérifier aussi le nom local en attente."
        }
        return New-ActionResult 10 "`"$env:COMPUTERNAME`" ajouté au domaine `"$DOMAINE`" → nom `"$NEWNAME`" / OU `"$OU`""
    } catch {
        Write-Log "Préparation du nom ou jonction a échoué ('$env:COMPUTERNAME', domaine '$DOMAINE', nom '$NEWNAME', OU '$OU')." 'ERROR' $_ 'AD'
        $native=Get-PestoNativeFailureCode $_
        if($renameRequested){return New-ActionResult 97 ('Changement de nom local engagé, jonction non confirmée. Vérifier les noms actif/configuré et le domaine avant toute reprise. Code natif '+$native+' : '+$_.Exception.Message)}
        if(-not $joinRequested){return New-ActionResult 96 ('Jonction non lancée : '+$_.Exception.Message)}
        if($native -eq 2732){return New-ActionResult 11 'Réutilisation du compte ordinateur refusée par la politique Windows (2732). Consultez NetSetup.log ; aucun objet AD ne sera supprimé.'}
        if($native -in @(5,1314,1326)){return New-ActionResult 11 ("Refus Windows confirmé ($native) : "+$_.Exception.Message)}
        return New-ActionResult 97 ('Jonction engagée, résultat non confirmé. Code natif '+$native+' : '+$_.Exception.Message)
    }
}

function Assert-PestoTargetNameAvailable {
    <# Lecture ciblée sur le DC de l'opération : les SPN peuvent appartenir
       à un objet autre qu'un ordinateur. Aucun DNS/SPN n'est modifié. #>
    param([string]$Name,[string]$Domain,[string]$CurrentGuid='')
    if(-not (Test-PestoComputerName $Name) -or -not (Test-PestoDnsName $Domain)){throw 'Nom cible ou domaine invalide.'}
    $id=[Guid]::Empty
    if($CurrentGuid -and (-not [Guid]::TryParse($CurrentGuid,[ref]$id) -or $id -eq [Guid]::Empty)){throw 'GUID source invalide.'}
    $fqdn=$Name+'.'+$Domain
    # Valeurs validées ASCII sans métacaractère LDAP.
    $filter='(|(dNSHostName='+$fqdn+')(servicePrincipalName=HOST/'+$Name+')(servicePrincipalName=HOST/'+$fqdn+')(servicePrincipalName=RestrictedKrbHost/'+$Name+')(servicePrincipalName=RestrictedKrbHost/'+$fqdn+'))'
    if($CurrentGuid){
        $binary=($id.ToByteArray()|ForEach-Object{'\'+$_.ToString('x2')}) -join ''
        $filter='(&'+$filter+'(!(objectGUID='+$binary+')))'
    }
    $adp=Get-ADParams
    $found=@(Get-ADObject -LDAPFilter $filter -Properties ObjectGUID -ResultSetSize 1 -ErrorAction Stop @adp)
    if($found.Count){throw ('Nom DNS ou SPN déjà porté par un autre objet AD : '+$Name+'. Aucun renommage lancé.')}
}

function RenameComputer {
    param([string]$Computername,[string]$NewName)
    $Computername=$Computername.Trim();$NewName=$NewName.Trim().ToUpperInvariant()
    if(-not (Test-PestoComputerName $Computername)){return New-ActionResult 21 "Nom source invalide : '$Computername'."}
    if(-not (Test-PestoGeneratedComputerName $NewName)){return New-ActionResult 21 "Nouveau nom hors convention : '$NewName'."}
    if($Computername -ieq $NewName){return New-ActionResult 96 "Nom actuel identique au nom demandé : aucun renommage lancé. Ce cas n'est jamais un succès de renommage."}
    if($script:GUI){return New-ActionResult 20 "DÉMO : '$Computername' renommé en '$NewName'."}
    Assert-PestoWorkerMayContinue
    Set-PestoWorkerStage 'Précontrôle du renommage' ('Source '+$Computername+' / cible '+$NewName)
    try{
        $source=Find-ADComputerByName -Name $Computername
        if(-not $source){return New-ActionResult 99 "Poste source absent de l'AD : '$Computername'."}
        $drift=Get-PestoIdentityChangeReason -ExpectedGuid $script:ExpectedObjectGuid -ActualGuid ([string]$source.ObjectGUID) -ExpectedOU $script:ExpectedSourceOU -ActualOU (Get-PestoParentDN ([string]$source.DistinguishedName))
        if($drift){return New-ActionResult 21 $drift}
        if(-not (Test-PestoOUInConfiguredScope (Get-PestoParentDN ([string]$source.DistinguishedName)))){
            return New-ActionResult 21 "Poste source hors périmètre configuré : '$Computername'."
        }
        if(Find-ADComputerByName -Name $NewName){return New-ActionResult 69 "Le nom '$NewName' est déjà utilisé."}
        if(-not $script:SIM){Assert-PestoTargetNameAvailable -Name $NewName -Domain $script:DOMAINE -CurrentGuid ([string]$source.ObjectGUID)}
    }catch{return New-ActionResult 21 "Précontrôle AD impossible : $($_.Exception.Message)"}
    $local=$Computername -ieq $env:COMPUTERNAME
    try{Assert-PestoRenameTarget -ComputerName $Computername}catch{return New-ActionResult 96 ('Cible non validée : '+$_.Exception.Message)}
    if($script:SIM){return New-ActionResult 20 "SIMULATION : contrôle Entra conditionnel puis renommage '$Computername' vers '$NewName', aucune écriture."}
    # Le login a lieu dans le processus eleve. Aucun second UAC pendant l'action.
    if($local -and -not (Test-PestoIsAdministrator)){
        return New-ActionResult 96 'Renommage non lance : Pesto n''est pas eleve. Fermez Pesto et relancez Pesto.exe ; aucune nouvelle demande UAC pendant cette action.'
    }
    if($script:cred -isnot [Management.Automation.PSCredential]){
        if(-not $local){return New-ActionResult 96 'Renommage distant non lancé : utiliser Pesto.exe -AskCredential pour ce parcours RPC avec identifiants explicites. Le jeton UAC ne fournit pas un mot de passe à déléguer. Aucun dsregcmd lancé.'}
        return Invoke-PestoWindowsLocalRename -ComputerName $Computername -NewName $NewName
    }
    $leave=Invoke-PestoDsregLeaveBeforeRename -ComputerName $Computername
    if(-not $leave){return New-ActionResult 97 'Résultat dsregcmd absent : aucun renommage lancé.'}
    if($leave.ExitCode -ne 20){return $leave}
    $entraNote=if($leave.Entra -eq 'Confirmed'){' | Retrait Entra effectué : réinscription à vérifier séparément.'}else{' | Aucun retrait Entra nécessaire.'}
    $argsRename=@{NewName=$NewName;Force=$true;PassThru=$true;ErrorAction='Stop';WarningAction='SilentlyContinue'}
    if(-not $local){$argsRename.ComputerName=$Computername;if($script:cred){$argsRename.LocalCredential=$script:cred}}
    if($script:cred){$argsRename.DomainCredential=$script:cred}
    $message='';$nativeFailure=$null
    try{
        Assert-PestoWorkerMayContinue -Mutation
        Set-PestoWorkerStage 'Renommage Windows en cours' $(if($local){'Appel local élevé'}else{'Appel distant ; attente RPC/WMI'})
        Set-PestoEffect -Name Rename -Value 'Requested'
        $change=@(Rename-Computer @argsRename)
        if(Test-PestoConfirmedChange $change){Set-PestoEffect -Name Rename -Value 'Confirmed';return New-ActionResult 20 "'$Computername' renommé en '$NewName' ; redémarrage requis.$entraNote"}
        if($change.Count -eq 1 -and $change[0].HasSucceeded -is [bool] -and -not $change[0].HasSucceeded){
            Set-PestoEffect -Name Rename -Value 'Refused'
            return New-ActionResult 21 "Rename-Computer a confirmé HasSucceeded=False.$entraNote"
        }
        return New-ActionResult 97 "Rename-Computer n'a pas renvoyé de résultat fiable ; aucun repli automatique.$entraNote"
    }catch{
        $message=[string]$_.Exception.Message;Write-Log "Renommage direct refusé pour '$Computername'." 'ERROR' $_ 'rename'

        $nativeFailure=Get-PestoNativeFailureCode $_
    }
    # Only documented, definite refusals can permit a separately authorized fallback.
    if($nativeFailure -in @(5,1314,1326)){
        Set-PestoEffect -Name Rename -Value 'Refused'
        if(-not $local -and $script:cred -and $script:AllowPasswordTaskFallback -and $nativeFailure -in @(5,1314)){
            $fb=Invoke-RenameComputerTaskFallback -Computername $Computername -NewName $NewName -DsregLeaveConfirmed
            if(-not $fb){return New-ActionResult 97 ('Résultat du repli absent.'+$entraNote)}
            $fb.ExitMsg+=$entraNote
            return $fb
        }
        return New-ActionResult 21 ("Refus Windows confirmé ($nativeFailure) : $message. Aucun repli automatique non autorisé.$entraNote")
    }
    return New-ActionResult 97 ("Appel de renommage engagé, résultat non confirmé (code natif $nativeFailure). $message$entraNote")

}

function MoveComputer {
    param([string]$ComputerName,[string]$OU_Destination)
    $ComputerName=$ComputerName.Trim();$OU_Destination=$OU_Destination.Trim()
    if(-not (Test-PestoComputerName $ComputerName)){return New-ActionResult 99 "Nom source invalide."}
    if(-not (Test-PestoOUPath $OU_Destination) -or -not (Test-PestoOUInConfiguredScope $OU_Destination)){
        return New-ActionResult 31 "OU cible invalide ou hors périmètre."
    }
    if($script:GUI){return New-ActionResult 30 "DÉMO : déplacement de '$ComputerName'."}
    Assert-PestoWorkerMayContinue
    Set-PestoWorkerStage 'Précontrôle du déplacement' $ComputerName
    $adp=Get-ADParams
    try{
        $pc=Get-ADComputer -Identity $ComputerName -Properties DistinguishedName,ObjectGUID,ProtectedFromAccidentalDeletion,userAccountControl -ErrorAction Stop @adp
        if($null -eq $pc.userAccountControl){throw 'Rôle AD de la cible non confirmé.'}
        if(([long]$pc.userAccountControl -band 8192) -ne 0){throw 'Les contrôleurs de domaine sont exclus.'}
        $srcOU=Get-PestoParentDN ([string]$pc.DistinguishedName)
        $drift=Get-PestoIdentityChangeReason -ExpectedGuid $script:ExpectedObjectGuid -ActualGuid ([string]$pc.ObjectGUID) -ExpectedOU $script:ExpectedSourceOU -ActualOU $srcOU
        if($drift){return New-ActionResult 31 $drift}
        if(-not (Test-PestoOUInConfiguredScope $srcOU)){return New-ActionResult 31 "Objet source hors périmètre : '$srcOU'."}
        # Vérifie l'existence réelle de la cible sur le même DC avant de modifier la protection.
        $destination=Get-ADOrganizationalUnit -Identity $OU_Destination -Properties ObjectGUID -ErrorAction Stop @adp
        if(-not $destination.ObjectGUID){throw 'GUID de destination absent.'}
        $script:ObservedTargetOUGuid=[string]$destination.ObjectGUID
        if($script:ExpectedTargetOUGuid -and $script:ObservedTargetOUGuid -ine $script:ExpectedTargetOUGuid){throw 'Le GUID de destination a changé depuis la confirmation.'}
        $id=[Guid]$pc.ObjectGUID
        if($id -eq [Guid]::Empty){throw 'ObjectGUID manquant.'}
    }catch{return New-ActionResult 99 "Précontrôle du déplacement impossible : $($_.Exception.Message)"}
    if($srcOU -ieq $OU_Destination){return New-ActionResult 33 "'$ComputerName' est déjà dans l'OU cible."}
    if($script:SIM){return New-ActionResult 30 "SIMULATION : déplacement de '$ComputerName' vers '$OU_Destination', aucune écriture."}
    if($pc.ProtectedFromAccidentalDeletion -isnot [bool]){return New-ActionResult 96 'Protection initiale AD non confirmée.'}
    $protected=[bool]$pc.ProtectedFromAccidentalDeletion
    if(-not $script:ActiveIntervention.Plan.Objet_GUID -or [Guid]$script:ActiveIntervention.Plan.Objet_GUID -ne $id){return New-ActionResult 96 'Le plan confirmé ne possède pas l’’identité AD observée. Refaire le contrôle.'}
    $now=[DateTime]::UtcNow.ToString('o')
    Set-PestoInitialObservation -Observation ([pscustomobject]@{ObservedUtc=$now;ADUtc=$now;WindowsUtc='';Windows=$null;Health=$null;AD=[pscustomobject]@{Name=[string]$pc.Name;Guid=$id.ToString();OU=$srcOU;Protected=$protected}})
    Set-PestoEffect -Name InitialProtection -Value $protected
    Set-PestoEffect -Name TargetOUGuid -Value $script:ObservedTargetOUGuid
    if($protected -and -not $script:CLEAR_PROTECTION){return New-ActionResult 31 "Objet protégé ; levée temporaire interdite par la configuration."}
    $restoreRequired=$false;$moveStarted=$false;$moveError='';$protectionError='';$after=$null
    try {
        Assert-PestoWorkerMayContinue -Mutation
        Set-PestoWorkerStage 'Déplacement dans AD' 'Protection et déplacement par GUID'
        if($protected){
            # Même si cet appel lève une exception, tenter de restaurer le droit original.
            Set-PestoEffect -Name Protection -Value 'Lowering'
            $restoreRequired=$true
            Set-ADObject -Identity $id -ProtectedFromAccidentalDeletion:$false -ErrorAction Stop @adp
        }
        Assert-PestoWorkerMayContinue -Mutation
        Set-PestoEffect -Name Move -Value 'Requested'
        $moveStarted=$true
        Move-ADObject -Identity $id -TargetPath $OU_Destination -ErrorAction Stop @adp
    }catch{$moveError=[string]$_.Exception.Message}
    finally {
        if($restoreRequired){
            try{Set-ADObject -Identity $id -ProtectedFromAccidentalDeletion:$true -ErrorAction Stop @adp;Set-PestoEffect -Name Protection -Value 'Restored'}
            catch{$protectionError=[string]$_.Exception.Message}
        }
    }
    for($i=0;$i -lt 3;$i++){
        try{$after=Get-ADComputer -Identity $id -Properties DistinguishedName,ProtectedFromAccidentalDeletion -ErrorAction Stop @adp;break}
        catch{if($i -lt 2){Start-Sleep -Milliseconds 700}}
    }
    if(-not $after){return New-ActionResult 97 "État indéterminé : lecture finale par GUID impossible. Déplacement : $moveError. Protection : $protectionError"}
    $actualOU=Get-PestoParentDN ([string]$after.DistinguishedName)
    # L'effet observé est consigné AVANT le contrôle de protection : un échec de restauration (code 32)
    # ne doit jamais effacer un déplacement réellement constaté par relecture du GUID.
    $moved=($actualOU -ieq $OU_Destination)
    if($moved){Set-PestoEffect -Name Move -Value 'Confirmed'}
    if($after.ProtectedFromAccidentalDeletion -isnot [bool] -or $after.ProtectedFromAccidentalDeletion -ne $protected){
        return New-ActionResult 32 "Protection NON RÉTABLIE. OU observée : '$actualOU'. Vérification et réparation manuelles requises. $protectionError"
    }
    if($moved){return New-ActionResult 30 "Déplacement confirmé par GUID vers '$OU_Destination' ; protection d'origine vérifiée."}
    if($moveStarted -and $moveError){
        return New-ActionResult 97 "Déplacement non confirmé après erreur de transport. OU actuellement observée : '$actualOU'. Un effet différé reste possible ; vérifier avant relance. $moveError"
    }
    if($actualOU -ieq $srcOU -and ($moveError -or -not $moveStarted)){
        return New-ActionResult 31 "Déplacement refusé ; objet confirmé dans l'OU source et protection d'origine conservée. $moveError"
    }
    return New-ActionResult 97 "Résultat du déplacement incohérent : OU observée '$actualOU'. Ne relancez pas sans contrôle AD."
}

function GoJoinDomain {
    param($Nom_du_PC,$Nouveau_Nom,$OU_Destination,$Confirm)
    $OU_Dest = if ($script:PRD) { "$OU_Destination".Trim() } else { "$($script:OU['PREPROD'])".Trim() }
    if (-not (Test-PestoOUPath $OU_Dest)) { return New-ActionResult 11 "Jonction impossible : OU de destination absente ou invalide (PRD=$($script:PRD))" }
    if (-not (Test-PestoGeneratedComputerName "$Nouveau_Nom")) { return New-ActionResult 11 "Jonction impossible : nouveau nom invalide ('$Nouveau_Nom')." }

    $msg = "Joindre `"$Nom_du_PC`" au domaine `"$($script:DOMAINE)`"`nNom : `"$Nouveau_Nom`"`nOU  : `"$OU_Dest`" ?"
    if (-not (Confirm-YesNo -Msg $msg -Confirm $Confirm)) { return }

    try { $taken = Find-ADComputerByName -Name "$Nouveau_Nom" }
    catch { return New-ActionResult 11 "Vérification du nom impossible avant jonction : $($_.Exception.Message)" }
    if ($taken) {
        $script:Computers = Get-AllComputersInOU -ParentOU $script:OU_POSTES
        try { Update-ComputersNoms } catch {}
        return New-ActionResult 13 "Jonction impossible : le nom `"$Nouveau_Nom`" est déjà utilisé"
    }
    $r = AddToDomain -DC $script:DC -DOMAINE $script:DOMAINE -OU $OU_Dest -NEWNAME $Nouveau_Nom -CRED $script:cred
    if ($r -and $r.ExitCode -ne 10) { return New-ActionResult $r.ExitCode "Jonction échouée (code $($r.ExitCode)) : $($r.ExitMsg)" }
    return $r
}

function GoRenameOnly {
    param($Nom_du_PC,$Nouveau_Nom,$Confirm)
    if (-not (Confirm-YesNo -Msg "Renommer `"$Nom_du_PC`" en `"$Nouveau_Nom`" ?" -Confirm $Confirm)) { return }
    $r = RenameComputer -Computername $Nom_du_PC -NewName $Nouveau_Nom
    if ($r -and $r.ExitCode -ne 20) { return New-ActionResult $r.ExitCode "Renommage échoué (code $($r.ExitCode)) : $($r.ExitMsg)" }
    return $r
}

function GoMoveOnly {
    param($Nom_du_PC,$OU_Destination,$Confirm)
    $pc = try { Get-ComputerOU -Identity $Nom_du_PC }
          catch { return New-ActionResult 99 "Poste `"$Nom_du_PC`" introuvable dans l'AD ou contrôleur de domaine injoignable (déplacement annulé) : $($_.Exception.Message)" }
    if ($pc.OU -ieq $OU_Destination) { return New-ActionResult 33 "`"$Nom_du_PC`" est déjà dans `"$OU_Destination`"" }
    if (-not (Confirm-YesNo -Msg "Déplacer `"$Nom_du_PC`" dans `"$OU_Destination`" ?" -Confirm $Confirm)) { return }
    $r = MoveComputer -ComputerName $Nom_du_PC -OU_Destination $OU_Destination
    if ($r -and $r.ExitCode -notin @(30,32,33)) { return New-ActionResult $r.ExitCode "Déplacement échoué (code $($r.ExitCode)) : $($r.ExitMsg)" }
    return $r
}

function Wait-ADComputerVisible {
    <# Attend la visibilité du nouveau compte sur le DC de l'outil. Une panne AD
       est levée immédiatement et n'est plus maquillée en simple délai de réplication. #>
    param([string]$Identity, [int]$TimeoutSec = 60)
    if (-not (Test-PestoComputerName $Identity)) { throw "Nom AD invalide : '$Identity'." }
    $limit=[Math]::Max(1,$TimeoutSec)
    Set-PestoWorkerStage 'Attente du nouveau nom dans AD' "$Identity ; maximum $limit s hors appel AD bloqué"
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        Assert-PestoWorkerMayContinue
        try { $found = Find-ADComputerByName -Name $Identity }
        catch {
            Write-Log "Vérification de réplication impossible pour '$Identity'." 'ERROR' $_ 'AD'
            throw
        }
        if ($found) { return $true }
        Start-Sleep -Milliseconds 800
        try { Invoke-DoEvents } catch {}
    } while ($clock.Elapsed.TotalSeconds -lt $limit)
    return $false
}

function GoRenameAndMove {
    <# Renommer puis attendre la visibilité du nouveau nom sur le DC sélectionné,
       avant de déplacer. La réplication AD peut retarder cette observation ;
       elle ne constitue jamais une garantie de convergence immédiate. #>
    param($Nom_du_PC,$Nouveau_Nom,$OU_Destination,$OU_Actuelle,$Confirm)

    try { $taken = Find-ADComputerByName -Name "$Nouveau_Nom" }
    catch { return New-ActionResult 99 "Vérification du nouveau nom impossible : $($_.Exception.Message)" }
    if ($taken -and "$($taken.Name)" -ine "$Nom_du_PC") {
        $script:Computers = Get-AllComputersInOU -ParentOU $script:OU['ROOT']
        try { Update-ComputersNoms } catch {}
        return New-ActionResult 88 "Le nom `"$Nouveau_Nom`" est déjà utilisé"
    }

    $pc = try { Get-ComputerOU -Identity $Nom_du_PC }
          catch { return New-ActionResult 99 "Poste `"$Nom_du_PC`" introuvable dans l'AD ou contrôleur de domaine injoignable (action annulée) : $($_.Exception.Message)" }

    # Déjà dans la bonne OU → renommage seul (aucun déplacement à faire).
    if ($pc.OU -ieq $OU_Destination) {
        if (-not (Confirm-YesNo -Msg "Renommer `"$Nom_du_PC`" en `"$Nouveau_Nom`" ?" -Confirm $Confirm)) { return }
        $r = RenameComputer -Computername $Nom_du_PC -NewName $Nouveau_Nom
        if ($r -and $r.ExitCode -ne 20) { return New-ActionResult $r.ExitCode "Renommage échoué (code $($r.ExitCode)) : $($r.ExitMsg)" }
        return $r
    }

    if (-not (Confirm-YesNo -Msg "Renommer `"$Nom_du_PC`" en `"$Nouveau_Nom`"`npuis le déplacer dans `"$OU_Destination`" ?" -Confirm $Confirm)) { return }
    $suffix = if ($script:SIM) { 'SIMU - ' } else { '' }

    # 1) RENOMMAGE D'ABORD (opération fragile, côté machine). Échec → rien n'est déplacé.
    $renameResult = RenameComputer -Computername $Nom_du_PC -NewName $Nouveau_Nom
    if ($renameResult -and $renameResult.ExitCode -ne 20) {
        return New-ActionResult $renameResult.ExitCode "Renommage échoué (code $($renameResult.ExitCode)) : $($renameResult.ExitMsg) | Poste NON déplacé."
    }
    if(-not $renameResult){return New-ActionResult 97 "Résultat de renommage absent ; déplacement non tenté."}
    Assert-PestoWorkerMayContinue
    Set-PestoWorkerStage 'Renommage confirmé' 'Vérification AD avant déplacement'
    $moveName = if($script:SIM){$Nom_du_PC}else{$Nouveau_Nom}

    # 2) Attendre que le NOUVEAU nom soit visible sur le DC de l'outil (réplication depuis le DC
    #    de la machine). Cette attente facilite la résolution du nom ; le déplacement utilise ensuite le GUID.
    if (($moveName -ieq $Nouveau_Nom) -and -not $script:SIM) {
        try { $visible = Wait-ADComputerVisible -Identity $Nouveau_Nom -TimeoutSec 60 }
        catch {
            return New-ActionResult 89 "${suffix}`"$Nom_du_PC`" RENOMMÉ en `"$Nouveau_Nom`", mais la vérification AD a échoué ($($_.Exception.Message)) — DÉPLACEMENT NON TENTÉ."
        }
        if (-not $visible) {
            return New-ActionResult 89 "${suffix}`"$Nom_du_PC`" RENOMMÉ en `"$Nouveau_Nom`", mais l'objet n'est pas encore visible sur le DC $($script:DC) (réplication AD) — DÉPLACEMENT DIFFÉRÉ. Relancez un déplacement seul dans un instant."
        }
    }

    # 3) Déplacement sur le DC configuré, après confirmation du renommage.
    $moveResult = MoveComputer -ComputerName $moveName -OU_Destination $OU_Destination
    if(-not $moveResult){return New-ActionResult 97 "Renommage confirmé mais résultat de déplacement absent."}
    if($moveResult.ExitCode -eq 32){return New-ActionResult 32 ("Renommage confirmé ; protection AD non rétablie : "+$moveResult.ExitMsg)}
    if ($moveResult -and [int]$moveResult.ExitCode -eq 97) {
        return New-ActionResult 97 "${suffix}`"$Nom_du_PC`" a été RENOMMÉ en `"$Nouveau_Nom`", mais l'état du DÉPLACEMENT est INDÉTERMINÉ : $($moveResult.ExitMsg) | ARRÊT DE SÉCURITÉ : vérifiez l'AD avant toute relance."
    }
    if ($moveResult -and $moveResult.ExitCode -notin @(30,33)) {
        return New-ActionResult 89 "${suffix}`"$Nom_du_PC`" RENOMMÉ en `"$Nouveau_Nom`" mais DÉPLACEMENT ÉCHOUÉ (code $($moveResult.ExitCode)) : $($moveResult.ExitMsg) | Relancez un déplacement seul."
    }

    return New-ActionResult 77 "${suffix}`"$Nom_du_PC`" renommé en `"$Nouveau_Nom`" et déplacé dans `"$OU_Destination`""
}

function Go {
    <# Aiguillage principal selon les flags Renommer/Déplacer et le contexte. #>
    param($Renommer,$Deplacer,$Nom_du_PC,$Nouveau_Nom,$OU_Destination,$OU_Actuelle,$Confirm)

    # HORS DOMAINE : il s'agit forcément du poste local. Ne jamais conditionner
    # une jonction locale à la résolution DNS/ping de son hostname.
    if (-not $script:INDOMAIN) {
        return New-ActionResult 96 'La jonction utilise la page Ajouter au domaine, jamais la file.'
    }

    Assert-PestoWorkerMayContinue
    Set-PestoWorkerStage 'Lecture du poste dans AD' ([string]$Nom_du_PC)
    if($Renommer) {
        $pc=try { Get-ComputerOU -Identity $Nom_du_PC }
            catch { return New-ActionResult 21 "Précontrôle du renommage impossible : $($_.Exception.Message). Aucune mutation tentée." }
        $decision=Get-PestoRenameMoveDecision -Computer $Nom_du_PC -NewName $Nouveau_Nom -CurrentOU ([string]$pc.OU) `
            -TargetOU $OU_Destination -Rename $true -Move ([bool]$Deplacer)
        if(-not $decision.Valid){return New-ActionResult 21 $decision.Error}
        if($decision.Move -and -not $Deplacer) {
            return New-ActionResult 21 'Le site actuel impose un deplacement absent du plan confirme. Actualisez le poste et la file ; aucune mutation tentee.'
        }
        $Deplacer=[bool]$decision.Move;$OU_Actuelle=[string]$pc.OU
        Write-Log $decision.Reason 'INFO' $null 'plan'
    }

    # ICMP n'est qu'un indicateur. Beaucoup de postes bloquent le ping tout en
    # acceptant RPC/WMI/SMB : Rename-Computer reste l'autorité et doit être tenté.
    if ($Renommer -and $Nom_du_PC -ine $env:COMPUTERNAME -and -not $script:SIM -and -not $script:GUI -and -not $script:SimOn) {
        Set-PestoWorkerStage 'Vérification réseau indicative' ([string]$Nom_du_PC)
        if (-not (Test-Connection $Nom_du_PC -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            Write-Log "Ping absent pour '$Nom_du_PC' : tentative de renommage maintenue (ICMP peut être filtré)." 'WARN' $null 'rename'
        }
    }
    if ($Nouveau_Nom) {
        if ($Deplacer -and $Renommer)        { return GoRenameAndMove -Nom_du_PC $Nom_du_PC -Nouveau_Nom $Nouveau_Nom -OU_Destination $OU_Destination -OU_Actuelle $OU_Actuelle -Confirm $Confirm }
        elseif ($Deplacer -and -not $Renommer){ return GoMoveOnly      -Nom_du_PC $Nom_du_PC -OU_Destination $OU_Destination -Confirm $Confirm }
        elseif (-not $Deplacer -and $Renommer){ return GoRenameOnly    -Nom_du_PC $Nom_du_PC -Nouveau_Nom $Nouveau_Nom -Confirm $Confirm }
    } elseif ($Deplacer -and -not $Renommer) {
        return GoMoveOnly -Nom_du_PC $Nom_du_PC -OU_Destination $OU_Destination -Confirm $Confirm
    }
}

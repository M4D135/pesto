#requires -Version 5.1
# Jonction de task sequence : aucun chargement WPF, aucune mutation au chargement.
# Le moteur de jonction, les reçus et la barrière machine restent ceux de l'application.

function Get-PestoAutomationRuntimeSource {
    param([string]$RuntimeRoot)
    $builder=[Text.StringBuilder]::new()
    $files=@('Pesto-Core.ps1','Pesto-Common.ps1','Pesto-Contracts.ps1','Pesto-Configuration.ps1',
        'Pesto-ManagedPolicy.ps1','Pesto-Policy.ps1','Pesto-Directory.ps1','Pesto-Async.ps1','Pesto-Journal.ps1','Pesto-Operations.ps1',
        'Pesto-Safety.ps1','Pesto-Diagnostics.ps1','Pesto-Inspection.ps1','Pesto-JoinRecovery.ps1','Pesto-Recovery.ps1','Pesto-Preparation.ps1',
        'Pesto-Names.ps1','Pesto-Direct.ps1','Pesto-Join.ps1','Pesto-Enterprise.ps1','Pesto-Extensions.ps1')
    $approved=@(Get-PestoRuntimeFiles)
    foreach($file in $files){
        if(('wad/'+$file) -cnotin $approved){throw ('Composant absent du contrat runtime : '+$file)}
        $tokens=$null;$parseErrors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RuntimeRoot $file),[ref]$tokens,[ref]$parseErrors)
        if(@($parseErrors).Count){throw ('Syntaxe runtime invalide : '+$file)}
        # Uniquement les définitions à la racine. Aucun top-level Core, Add-Type, WPF ou worker exécuté.
        foreach($statement in $ast.EndBlock.Statements){
            if($statement -is [Management.Automation.Language.FunctionDefinitionAst]){[void]$builder.AppendLine($statement.Extent.Text)}
        }
    }
    [void]$builder.AppendLine(@'
function Write-Log {param($Message,$Level='INFO',$ErrorRecord,$Context='automatisation');Publish-PestoWorkerLog -Text ([string]$Message) -Level $Level -Context $Context}
function Show-MsgWarning {throw 'Une interaction graphique a été demandée en mode silencieux.'}
function Show-MsgInfo {throw 'Une interaction graphique a été demandée en mode silencieux.'}
function Show-MsgError {throw 'Une interaction graphique a été demandée en mode silencieux.'}
'@)
    return $builder.ToString()
}

function Assert-PestoAutomationPlatform {
    if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or
        $PSVersionTable.PSVersion.Minor -lt 1 -or [Environment]::OSVersion.Platform -ne 'Win32NT' -or -not [Environment]::Is64BitProcess){
        throw 'Utilisez Windows PowerShell 5.1 x64 sur Windows installé (pas WinPE ni PowerShell 7).'
    }
    if(-not (Test-PestoIsAdministrator)){throw 'Le processus doit déjà être administrateur local. Aucun dialogue UAC ne sera ouvert.'}
}

function New-PestoAutomationResult {
    param([int]$ExitCode,[string]$State,[string]$Message,$Plan=$null,[int]$CandidateCount=0,
        [string]$OperationId='',[bool]$MutationStarted=$false,$EngineCode=$null,[object[]]$Checks=@(),$PortablePlan=$null,$Metadata=$null)
    # Liste fermée : le Request, les credentials et les objets AD ne sont jamais renvoyés/sérialisés.
    $safePlan=$null
    if($Plan){$safePlan=[pscustomobject]@{Computer=[string]$Plan.Computer;NewName=[string]$Plan.NewName;
        Domain=[string]$Plan.Domain;DC=[string]$Plan.DC;TargetOU=[string]$Plan.TargetOU}}
    $safeChecks=@(foreach($check in $Checks){[pscustomobject]@{Check=[string]$check.Check;State=[string]$check.State;Detail=(Protect-PestoLogText ([string]$check.Detail))}})
    [pscustomobject]@{Schema=1;Mode='UnattendedJoin';State=$State;ExitCode=$ExitCode;EngineCode=$EngineCode;
        RestartRequired=($ExitCode -eq 3010);MutationStarted=$MutationStarted;OperationId=$OperationId;
        Utc=[DateTime]::UtcNow.ToString('o');Message=(Protect-PestoLogText $Message);Plan=$safePlan;
        CandidateCount=$CandidateCount;Checks=$safeChecks;PreparedPlan=$PortablePlan;Metadata=$Metadata}
}

function Get-PestoAutomationCandidates {
    param([string]$Type,[string]$SiteCode,[string]$ServiceCode,[string]$DomainDN)
    $first=New-PestoComputerName -Type $Type -Prefix $script:PREFIXE -Site $SiteCode -Service $ServiceCode -Number 1
    $series=Get-PestoNameSeriesBase $first
    $layout=Get-PestoNamingLayout
    $ldapSeries=$first.Remove($layout.NumberOffset,$layout.NumberWidth).Insert($layout.NumberOffset,'*')
    $used=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $adp=Get-ADParams
    # Domaine entier, résultat non tronqué, tous les alias. Une erreur de lecture interrompt le plan.
    Get-ADComputer -LDAPFilter ('(|(name='+$ldapSeries+')(sAMAccountName='+$ldapSeries+'$)(dNSHostName='+$ldapSeries+'.*))') `
        -SearchBase $DomainDN -SearchScope Subtree -Properties SamAccountName,DNSHostName -ResultSetSize $null -ErrorAction Stop @adp |
        ForEach-Object {
            foreach($alias in @([string]$_.Name,([string]$_.SamAccountName).TrimEnd('$'),(([string]$_.DNSHostName)-split '\.')[0])){
                $parts=ConvertTo-PestoNameParts -Name $alias -Prefix $script:PREFIXE
                if($parts -and $parts.Base -ceq $series){[void]$used.Add($parts.Name)}
            }
        }
    $free=[Collections.Generic.List[string]]::new()
    for($number=1;$number -le $layout.MaximumNumber;$number++){
        $name=New-PestoNameFromSeries $series $number
        if($used.Contains($name)){continue}
        $excluded=$false
        foreach($pattern in $script:PestoPolicy.ExcludedNames){
            if([Management.Automation.WildcardPattern]::new($pattern,'IgnoreCase').IsMatch($name)){$excluded=$true;break}
        }
        if(-not $excluded){$free.Add($name)}
    }
    return ,$free.ToArray()
}

function Invoke-PestoUnattendedJoin {
    [CmdletBinding()]
    param([string]$RuntimeRoot,[string]$ConfigPath,$Credential,
        [string]$Type,[string]$SiteCode,[string]$ServiceCode,[string]$TargetOU='',
        $PreparedPlan=$null,$Metadata=$null,$Approval=$null,[switch]$Execute)
    $ErrorActionPreference='Stop'
    # Seules les métadonnées validées dans cet appel peuvent être retournées.
    $plan=$null;$request=$null;$monitor=$null;$candidateCount=0;$checks=@();$safeMetadata=$null;$portable=$null
    try{
        Assert-PestoAutomationPlatform
        $exe=Join-Path (Split-Path -Parent $RuntimeRoot) 'Pesto.exe'
        $script:PestoBuildSHA256=if([IO.File]::Exists($exe)){(Get-FileHash -LiteralPath $exe -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}else{''}
        $safeMetadata=ConvertTo-PestoDeploymentMetadata $Metadata
        if($Credential -isnot [Management.Automation.PSCredential] -or -not $Credential.UserName -or $Credential.Password.Length -lt 1){
            throw 'Fournissez un PSCredential non vide en mémoire depuis le coffre de la task sequence. Aucune invite ni mot de passe en argument texte.'
        }
        if($env:PESTO_READONLY_SESSION -eq '1'){throw 'La session est en consultation : jonction silencieuse refusée.'}
        Assert-PestoPlainPath $ConfigPath
        $item=Get-Item -LiteralPath $ConfigPath -Force -ErrorAction Stop
        if($item.PSIsContainer -or $item.Length -gt 1MB){throw 'Configuration absente ou supérieure à 1 Mio.'}
        $script:CFG=[IO.File]::ReadAllText($item.FullName,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json -ErrorAction Stop
        [void](Set-PestoActiveNamingConvention $script:CFG.NamingConvention)
        if($Type -cnotin @('P','S','V') -or $SiteCode -notmatch (Get-PestoFacetPattern Site) -or $ServiceCode -notmatch (Get-PestoFacetPattern Service)){
            throw 'Filtres requis : Type P/S/V, SiteCode deux lettres, ServiceCode trois caractères alphanumériques.'
        }
        $errors=@(Test-CfgValid $script:CFG)
        if($errors.Count){throw ($errors -join ' ')}
        $script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY
        if(-not $script:PestoPolicy.UnattendedJoinEnabled){throw 'Jonction silencieuse désactivée : POLICY.UnattendedJoinEnabled doit être le booléen JSON true.'}
        # Ces parcours impliquent une préparation opérateur spécifique. Refus explicite avant toute écriture.
        if($script:PestoPolicy.CoordinationRoot -or $script:PestoPolicy.CoordinationRequired -or $script:PestoPolicy.ReserveNamesInAD){
            throw 'Le mode silencieux ne prend pas en charge la coordination partagée ni la réservation AD. Utilisez le parcours interactif ou une configuration dédiée sans ces options.'
        }
        foreach($flag in @('Simulation','GUI','HorsDomaine','MauvaiseOU','ForceADM','BPVerifNomAD')){
            if($script:CFG.DEBUG -and (Convert-Value-TF $script:CFG.DEBUG.$flag -Strict)){throw ('DEBUG.'+$flag+' doit être désactivé pour la task sequence.')}
        }
        $conf=@($script:CFG.CONF)[0]
        $script:SIM=$false;$script:GUI=$false;$script:PestoReadOnly=$false;$script:cred=$Credential
        $script:DOMAINE=([string]$conf.Domaine).Trim().TrimEnd('.');$script:PREFIXE=([string]$conf.Prefixe).Trim()
        $script:PREPRODSITE=([string]$conf.PreprodSite).Trim();$script:RuntimeTags=$null
        $script:PRD=Convert-Value-TF $conf.DirectProd -Strict
        $script:OU=@{};foreach($row in $script:CFG.OUBase){$script:OU[[string]$row.Nom]=[string]$row.OU}
        $script:OUV=@{};foreach($row in $script:CFG.OUSite){$script:OUV[[string]$row.Nom]=[string]$row.OU}
        $script:OU_POSTES=$script:OU.ROOT;$script:ActiveIntervention=$null
        $monitor=New-PestoQueueMonitor -Computer $env:COMPUTERNAME;$script:PestoQueueMonitor=$monitor
        if($Execute -and $script:PestoAuditWriter){Enable-PestoHeadlessEventStream $monitor}
        if(-not $script:PRD){
            if(-not $TargetOU){$TargetOU=$script:OU.PREPROD}
            if($TargetOU -ine $script:OU.PREPROD -or $SiteCode -ine (Get-SiteTag 'PREPROD') -or $ServiceCode -ine $script:PREPRODSITE){
                throw 'DirectProd=false impose l’’OU PREPROD, son tag et le service PreprodSite configurés.'
            }
        }
        if(-not (Test-PestoOUPath $TargetOU) -or -not (Test-PestoOUInConfiguredScope $TargetOU) -or
            (Get-PestoDomainFromDN $TargetOU) -ine $script:DOMAINE){throw 'OU cible absente ou hors du périmètre et du domaine configurés.'}
        foreach($excluded in $script:PestoPolicy.ExcludedOUs){if(Test-PestoDNWithinScope $TargetOU @($excluded)){throw 'OU cible exclue par la politique.'}}
        # Refus local et reçus antérieurs vérifiés avant la première lecture réseau.
        $local=Get-PestoJoinLocalStatus
        if($local.PartOfDomain -or $local.PendingRename -or -not $local.Admin -or $local.DomainRole -notin @(0,2)){
            throw 'Le PC doit être hors domaine, administrateur, sans renommage ni redémarrage de jonction en attente.'
        }
        $decision=Get-PestoJoinReceiptDecision -Receipt (Read-PestoJoinReceipt (Get-PestoJoinStatePath)) -Local $local -Domain $script:DOMAINE
        if($decision.Blocked){throw $decision.Message}
        Assert-PestoStoredMutationReady -Joining
        Initialize-PestoCommon -Root $RuntimeRoot
        Import-PestoADModule -ADModulePath (Join-Path $RuntimeRoot 'ActiveDirectory.psd1')
        $script:DC=Get-DomainController $script:DOMAINE
        $adp=Get-ADParams
        $domain=Get-ADDomain -ErrorAction Stop @adp
        if($domain.DNSRoot -ine $script:DOMAINE -or (Get-PestoDomainFromDN $domain.DistinguishedName) -ine $script:DOMAINE){throw 'Le contrôleur découvert ne correspond pas au domaine demandé.'}
        if($script:PRD){
            if(@($script:OUV.Values) -inotcontains (Get-PestoParentDN $TargetOU)){throw 'En production, choisissez une OU de site directement sous un organisme configuré.'}
            $target=Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop @adp
            if(-not $target -or $target.DistinguishedName -ine $TargetOU -or (Get-SiteTag ([string]$target.Name)) -ine $SiteCode){throw 'Le code site ne correspond pas à l’’OU de site confirmée dans AD.'}
        }
        $stamp=Get-PestoConfigurationSignature $script:CFG
        if($PreparedPlan){
            [void](Assert-PestoPortablePlan -Plan $PreparedPlan -ConfigStamp $stamp -MachineId $local.MachineId -Action Join)
            if($PreparedPlan.Computer -ine $local.Computer -or $PreparedPlan.Domain -ine $script:DOMAINE -or
                $PreparedPlan.TargetOU -ine $TargetOU -or $PreparedPlan.Type -cne $Type -or $PreparedPlan.SiteCode -ine $SiteCode -or
                $PreparedPlan.ServiceCode -ine $ServiceCode){throw 'Le plan importé diffère des paramètres ou de la machine.'}
        }
        $candidates=Get-PestoAutomationCandidates -Type $Type -SiteCode $SiteCode -ServiceCode $ServiceCode -DomainDN $domain.DistinguishedName
        $candidateCount=$candidates.Count
        if(-not $candidateCount){throw 'Aucun nom libre parmi les 999 candidats du filtre.'}
        $index=if($PreparedPlan){[Array]::IndexOf($candidates,[string]$PreparedPlan.NewName)}else{Get-PestoInitialNameIndex $candidateCount}
        if($index -lt 0 -or $index -ge $candidateCount){throw 'Le générateur n’’a pas fourni un index de candidat valide.'}
        $plan=[pscustomobject]@{Computer=$local.Computer;NewName=$candidates[$index];AllowExisting=$false;ReservedByPesto=$false;ReservedGuid='';
            Domain=$script:DOMAINE;DC=$script:DC;TargetOU=$TargetOU;DirectProd=[bool]$script:PRD;Account=$Credential.UserName}
        $request=[pscustomobject]@{Mode='Check';Plan=$plan;Policy=$script:PestoPolicy;ReadOnly=$false;
            ConfigStamp=(Get-PestoConfigurationSignature $script:CFG);OperationId=[Guid]::NewGuid().ToString('N');Credential=$Credential;
            StatePath=(Get-PestoJoinStatePath);Monitor=$monitor;Metadata=$safeMetadata;Approval=$Approval;ConfirmedTargetOUGuid='';ConfirmedExistingGuid='';ConfirmedMachineId=''}
        $monitor.OperationId=$request.OperationId
        $check=Get-PestoJoinPreflight -Request $request;$checks=@($check.Checks)
        if(-not $check -or $check.Valid -isnot [bool] -or -not $check.Valid){throw 'Contrôle bloqué. Aucun nom de remplacement n’’est choisi automatiquement.'}
        $ledgerPlan=[pscustomobject]@{Nom_du_PC=$plan.Computer;Nouveau_Nom=$plan.NewName;Domain=$plan.Domain;Objet_GUID='';OU_Destination=$TargetOU}
        foreach($previous in @(Get-PestoInterventions)){if(Test-PestoInterventionConflict $previous $ledgerPlan){throw ('Intervention antérieure à vérifier : '+$previous.OperationId)}}
        if($PreparedPlan -and $PreparedPlan.TargetOUGuid -ine [string]$check.TargetOUGuid){throw 'OU de destination remplacée depuis la préparation.'}
        $portable=New-PestoPortablePlan -Action Join -ConfigStamp $stamp -Computer $local.Computer -NewName $plan.NewName -TargetOU $TargetOU `
            -Domain $script:DOMAINE -TargetOUGuid ([string]$check.TargetOUGuid) -Type $Type -SiteCode $SiteCode -ServiceCode $ServiceCode `
            -Metadata $safeMetadata -MachineId $local.MachineId
        if(-not $Execute){return New-PestoAutomationResult -ExitCode 0 -State Prepared -Message 'Plan préparé en lecture seule. Nom non réservé. Exportez PreparedPlan pour conserver ce nom ; toute exécution le contrôlera à nouveau.' -Plan $plan -CandidateCount $candidateCount -Checks $checks -PortablePlan $portable -Metadata $safeMetadata}
        $request.Mode='Execute';$request.ConfirmedTargetOUGuid=[string]$check.TargetOUGuid
        $request.ConfirmedExistingGuid=[string]$check.ExistingGuid;$request.ConfirmedMachineId=[string]$check.Local.MachineId
        $result=Invoke-PestoJoinExecute -Request $request
        $action=$result.Action
        $code=if($action -and $action.ExitCode -is [int]){[int]$action.ExitCode}else{97}
        $state=Get-PestoOutcome -Code $code -Committed ([bool]$monitor.MutationStarted) -TimedOut ([bool]$monitor.TimedOut)
        $exitCode=$code
        # Le timeout et une phase Uncertain restent prioritaires, même après un succès natif tardif.
        # Une jonction silencieuse n'est acceptée que pour le code 10 avec reçu PendingRestart (3010).
        # Les codes 20, 30, 33 et 77, suffisants pour un renommage ou un déplacement, restent incertains ici.
        if($state -eq 'Uncertain' -or ($result.Receipt -and $result.Receipt.Phase -ceq 'Uncertain')){$exitCode=97;$state='Uncertain'}
        elseif($code -eq 10 -and $result.Receipt -and $result.Receipt.Phase -ceq 'PendingRestart'){$exitCode=3010;$state='PendingRestart'}
        elseif($code -eq 10 -or $code -in @(20,30,33,77)){$exitCode=97;$state='Uncertain'}
        return New-PestoAutomationResult -ExitCode $exitCode -State $state -Message ([string]$action.ExitMsg) -Plan $plan `
            -CandidateCount $candidateCount -OperationId $request.OperationId -MutationStarted ([bool]$monitor.MutationStarted) -EngineCode $code -Checks @($result.Check.Checks) -PortablePlan $portable -Metadata $safeMetadata
    }catch{
        $started=($monitor -and [bool]$monitor.MutationStarted)
        $uncertain=$started -or ($monitor -and [bool]$monitor.TimedOut)
        $code=if($uncertain){97}else{96};$state=if($uncertain){'Uncertain'}else{'NotStarted'}
        $op=if($request){[string]$request.OperationId}else{''}
        return New-PestoAutomationResult -ExitCode $code -State $state -Message $_.Exception.Message -Plan $plan -CandidateCount $candidateCount -OperationId $op -MutationStarted $started -Checks $checks -PortablePlan $portable -Metadata $safeMetadata
    }finally{
        # Le PSCredential fourni reste la propriété de l’’appelant ; aucune copie de mot de passe créée ici.
        if($request){$request.Credential=$null}
        try{Write-PestoHeadlessEvents $monitor}catch{}
        $script:cred=$null;$script:PestoQueueMonitor=$null
    }
}

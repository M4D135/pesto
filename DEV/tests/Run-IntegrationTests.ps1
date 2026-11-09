#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop';Set-StrictMode -Off
$runtime=Join-Path (Split-Path $PSScriptRoot -Parent) 'wad'
. (Join-Path $runtime 'Pesto-Integrity.ps1')
. (Join-Path $runtime 'Pesto-Automation.ps1')
. ([scriptblock]::Create((Get-PestoAutomationRuntimeSource $runtime)))
$cases=[Collections.Generic.List[object]]::new()
function Assert-Integration {param($Value,$Message='Condition fausse');if(-not $Value){throw $Message}}
function Reject-Integration {param([scriptblock]$Body);$threw=$false;try{& $Body|Out-Null}catch{$threw=$true};Assert-Integration $threw 'Un refus était attendu'}
function Case-Integration {param($Name,[scriptblock]$Body);try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host "PASS $Name"}catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "FAIL $Name : $($_.Exception.Message)"}}
$temp=Join-Path $PSScriptRoot ('.pesto-integration-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$oldReadOnly=$env:PESTO_READONLY_SESSION;$env:PESTO_READONLY_SESSION=''
$script:machine='11111111-1111-4111-8111-111111111111';$script:calls=0;$script:failWrite=0;$script:writes=0
function Get-PestoAutomationStore {return $temp}
function Get-PestoAutomationMachineId {return $script:machine}
function Write-PestoJoinReceipt {param($Path,$Receipt);$script:writes++;if($script:failWrite -eq $script:writes){throw 'Disque factice refusé'};[IO.File]::WriteAllText($Path,($Receipt|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))}
function New-TestPlan {New-PestoPortablePlan -Action Rename -ConfigStamp ('A'*64) -Computer 'PC-OLD' -NewName 'P123456PAINF001' -TargetOU 'OU=Paris,DC=example,DC=local' -Domain 'example.local' -SourceOU 'OU=Paris,DC=example,DC=local' -ObjectGuid '22222222-2222-4222-8222-222222222222' -MachineId $script:machine -Metadata ([pscustomobject]@{Campaign='C42';Stage='Prepare'})}
function Invoke-TestAction {$script:calls++;New-PestoIntegrationResult -Mode Rename -ExitCode 3010 -State PendingRestart -Message 'Commande acceptée' -MutationStarted $true -OperationId '33333333-3333-4333-8333-333333333333'}
try{
    Case-Integration 'Metadata liste fermée et limite' {
        $m=ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Campaign=' C42 ';Stage='Prepare'});Assert-Integration ($m.Campaign -ceq 'C42')
        Reject-Integration {ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Password='FAUX'})}
        Reject-Integration {ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Campaign=('x'*121)})}
        Reject-Integration {ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Stage="x`ny"})}
        Reject-Integration {ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Stage='token=FAUX'})}
    }
    Case-Integration 'Plan exportable fermé et non secret' {
        $p=New-TestPlan;$copy=Assert-PestoPortablePlan $p ('A'*64) $script:machine Rename
        Assert-Integration ($copy.NewName -ceq 'P123456PAINF001')
        Assert-Integration (($copy|ConvertTo-Json -Depth 10) -notmatch '(?i)credential|password|securestring')
    }
    Case-Integration 'Plan altéré, configuration et machine différents refusés' {
        $p=New-TestPlan;$p.NewName='P123456PAINF002';Reject-Integration {Assert-PestoPortablePlan $p ('A'*64) $script:machine Rename}
        $p=New-TestPlan;Reject-Integration {Assert-PestoPortablePlan $p ('B'*64) $script:machine Rename}
        Reject-Integration {Assert-PestoPortablePlan $p ('A'*64) '44444444-4444-4444-8444-444444444444' Rename}
        Reject-Integration {Assert-PestoPortablePlan $p ('A'*64) $script:machine Move}
    }
    Case-Integration 'Plan expiré refusé même avec empreinte recalculée' {
        $p=New-TestPlan;$p.CreatedUtc=[DateTime]::UtcNow.AddDays(-2).ToString('o');$p.ExpiresUtc=[DateTime]::UtcNow.AddDays(-1).ToString('o')
        $o=[ordered]@{};foreach($v in $p.PSObject.Properties){if($v.Name -ne 'Integrity'){$o[$v.Name]=$v.Value}}
        $p.Integrity=Get-PestoStableHash (ConvertTo-PestoCanonicalValue $o)
        Reject-Integration {Assert-PestoPortablePlan $p ('A'*64) $script:machine Rename}
    }
    Case-Integration 'Schéma plan entier uniquement même avec empreinte recalculée' {
        foreach($schema in @('1',[double]1,$true)){
            $p=New-TestPlan;$p.Schema=$schema
            $o=[ordered]@{};foreach($v in $p.PSObject.Properties){if($v.Name -ne 'Integrity'){$o[$v.Name]=$v.Value}}
            $p.Integrity=Get-PestoStableHash (ConvertTo-PestoCanonicalValue $o)
            Reject-Integration {Assert-PestoPortablePlan $p ('A'*64) $script:machine Rename}
        }
        $p=New-TestPlan;$p.Schema=[long]1
        [void](Assert-PestoPortablePlan $p ('A'*64) $script:machine Rename)
    }
    Case-Integration 'Export exclusif et UTF8 strict' {
        $p=New-TestPlan;$path=Join-Path $temp 'plan.json';Export-PestoPortablePlan $p $path
        $read=Read-PestoAutomationJson $path;[void](Assert-PestoPortablePlan $read ('A'*64) $script:machine Rename)
        Reject-Integration {Export-PestoPortablePlan $p $path}
        Reject-Integration {Read-PestoAutomationJson $path -MaximumBytes 2}
        Reject-Integration {Export-PestoPortablePlan $p 'relative.json'}
    }
    Case-Integration 'Clé idempotente restitue résultat sans deuxième appel' {
        $before=$script:calls;$payload=[ordered]@{Action='Rename';Target='PC001'}
        $a=Invoke-PestoIdempotentExecution -Key 'test/replay' -Payload $payload -Handler {Invoke-TestAction}
        $b=Invoke-PestoIdempotentExecution -Key 'test/replay' -Payload $payload -Handler {throw 'NE DOIT PAS ETRE APPELE'}
        Assert-Integration ($script:calls -eq ($before+1));Assert-Integration ($a.ExitCode -eq 3010 -and $b.ExitCode -eq 3010 -and $b.Replayed)
    }
    Case-Integration 'Rejeu jonction conserve PreparedPlan et refuse schéma marqueur texte' {
        $payload=@{Action='Join';Target='PC009'}
        $a=Invoke-PestoIdempotentExecution -Key 'test/join-fields' -Payload $payload -Handler {
            $r=Invoke-TestAction
            $r|Add-Member -NotePropertyName PreparedPlan -NotePropertyValue (New-TestPlan)
            $r
        }
        $b=Invoke-PestoIdempotentExecution -Key 'test/join-fields' -Payload $payload -Handler {throw 'INTERDIT'}
        Assert-Integration ($b.Replayed -and $b.PreparedPlan.NewName -ceq $a.PreparedPlan.NewName -and $b.PreparedPlan.Integrity -ceq $a.PreparedPlan.Integrity)
        $path=Join-Path $temp ((Get-PestoStableHash 'PestoAutomation|test/join-fields')+'.json')
        $saved=Read-PestoAutomationJson $path;$saved.Schema='1'
        [IO.File]::WriteAllText($path,($saved|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        Reject-Integration {Invoke-PestoIdempotentExecution -Key 'test/join-fields' -Payload $payload -Handler {throw 'INTERDIT'}}
    }
    Case-Integration 'Refus96 mémorisé exige une nouvelle clé après correction explicite' {
        $payload=@{Action='Move';Target='PC096'}
        $a=Invoke-PestoIdempotentExecution -Key 'test/refused96' -Payload $payload -Handler {New-PestoIntegrationResult -Mode Move -ExitCode 96 -State NotStarted -Message 'Refus factice'}
        $b=Invoke-PestoIdempotentExecution -Key 'test/refused96' -Payload $payload -Handler {throw 'NE DOIT PAS ETRE REJOUE'}
        Assert-Integration ($a.ExitCode -eq 96 -and $b.ExitCode -eq 96 -and $b.Replayed)
        $c=Invoke-PestoIdempotentExecution -Key 'test/refused96-corrected' -Payload $payload -Handler {Invoke-TestAction}
        Assert-Integration ($c.ExitCode -eq 3010 -and -not $c.Replayed)
    }
    Case-Integration 'Même clé autre payload refusée sans mutation' {
        Reject-Integration {Invoke-PestoIdempotentExecution -Key 'test/replay' -Payload @{Action='Rename';Target='PC002'} -Handler {throw 'INTERDIT'}}
    }
    Case-Integration 'Même clé autre machine refusée' {
        $script:machine='55555555-5555-4555-8555-555555555555'
        Reject-Integration {Invoke-PestoIdempotentExecution -Key 'test/replay' -Payload ([ordered]@{Action='Rename';Target='PC001'}) -Handler {throw 'INTERDIT'}}
        $script:machine='11111111-1111-4111-8111-111111111111'
    }
    Case-Integration 'Interruption après marqueur interdit rejeu' {
        $payload=@{Action='Move';Target='PC003'}
        $a=Invoke-PestoIdempotentExecution -Key 'test/interrupted' -Payload $payload -Handler {throw 'Coupure factice'}
        $b=Invoke-PestoIdempotentExecution -Key 'test/interrupted' -Payload $payload -Handler {throw 'INTERDIT'}
        Assert-Integration ($a.ExitCode -eq 97 -and $b.ExitCode -eq 97)
    }
    Case-Integration 'Disque refusé avant action interdit mutation' {
        $before=$script:calls;$script:failWrite=$script:writes+1
        Reject-Integration {Invoke-PestoIdempotentExecution -Key 'test/disk-before' -Payload @{Action='Move'} -Handler {Invoke-TestAction}}
        Assert-Integration ($script:calls -eq $before);$script:failWrite=0
    }
    Case-Integration 'Disque refusé après action devient incertain sans rejeu' {
        $before=$script:calls;$script:failWrite=$script:writes+2
        $a=Invoke-PestoIdempotentExecution -Key 'test/disk-after' -Payload @{Action='Move'} -Handler {Invoke-TestAction}
        $script:failWrite=0
        $b=Invoke-PestoIdempotentExecution -Key 'test/disk-after' -Payload @{Action='Move'} -Handler {throw 'INTERDIT'}
        Assert-Integration ($script:calls -eq $before+1 -and $a.ExitCode -eq 97 -and $b.ExitCode -eq 97)
    }
    Case-Integration 'Consultation et clés invalides refusées sans écriture' {
        $before=$script:writes;$env:PESTO_READONLY_SESSION='1'
        Reject-Integration {Invoke-PestoIdempotentExecution -Key 'test/readonly' -Payload @{Action='Join'} -Handler {throw 'INTERDIT'}}
        $env:PESTO_READONLY_SESSION=''
        Reject-Integration {Invoke-PestoIdempotentExecution -Key '../invalid key' -Payload @{} -Handler {throw 'INTERDIT'}}
        Assert-Integration ($script:writes -eq $before)
    }
    Case-Integration 'Résultat ambigu non marqué Completed' {
        $a=Invoke-PestoIdempotentExecution -Key 'test/ambiguous' -Payload @{Action='Join'} -Handler {(Invoke-TestAction);(Invoke-TestAction)}
        Assert-Integration ($a.ExitCode -eq 97)
    }
    foreach($stage in @('Init','InvalidMetadata','Preflight','BeforeMutation','AfterMutation')) {
        Case-Integration ('T010 orchestrateur réel : '+$stage) {
            $meta=[pscustomobject]@{Campaign='INHERITED'};$op='INHERITED';$portable=[pscustomobject]@{Invalid='INHERITED'}
            function Initialize-PestoHeadlessContext {
                param($RuntimeRoot,$ConfigPath,$Credential)
                if($stage -eq 'Init'){throw 'T010 init'}
                $script:CFG=[pscustomobject]@{CONF=@([pscustomobject]@{EntraPolicy='Never'})};$script:DOMAINE='example.local';$script:DC='dc.example.local'
                $script:PestoPolicy=[pscustomobject]@{AllowPasswordTaskFallback=$false};$script:PestoAuditWriter=$null;$script:OU=@{};$script:OUV=@{}
            }
            function Get-PestoConfigurationSignature {param($Config);'A'*64}
            function Get-ADParams {@{}}
            function Get-ADComputer {[CmdletBinding()]param($LDAPFilter,$ResultSetSize,$Properties);[pscustomobject]@{ObjectGUID=[guid]'22222222-2222-4222-8222-222222222222';DistinguishedName='CN=PC-OLD,OU=Paris,DC=example,DC=local'}}
            function Get-PestoRenameMoveDecision {param($Computer,$NewName,$CurrentOU,$TargetOU,$Rename,$Move,$InDomain);[pscustomobject]@{Valid=$true;Move=$false}}
            function Get-PestoExplicitCredentialRequirement {param($InDomain,$Rows,$LocalComputerName);''}
            function Assert-PestoOperationPolicy {param($Plan,$Policy)}
            function Assert-PestoStoredMutationReady {param($Plan)}
            function Get-PestoPreflightSource {''}
            function Get-PestoWorkerCoreSource {''}
            function Get-PestoDirectSupportSource {''}
            function Initialize-PestoHeadlessAudit {param($RuntimeRoot)}
            function Write-PestoHeadlessEvents {param($Monitor)}
            function Get-PestoEngineWorkerScriptBlock {
                param($Name)
                if($Name -eq 'Preflight'){return {
                    param($Request,$Source)
                    if($stage -eq 'Preflight'){throw 'T010 preflight'}
                    [pscustomobject]@{Results=@([pscustomobject]@{State='VÉRIFIÉ';Guid='22222222-2222-4222-8222-222222222222';Utc=[DateTime]::UtcNow.ToString('o');TargetOUGuid='';Detail='Double contrôle'})}
                }}
                if($Name -eq 'Direct'){return {
                    param($Request,$Source,$Queue,$Support)
                    $script:T010Operation=$Request.OperationId
                    if($stage -eq 'AfterMutation'){$Request.Telemetry.MutationStarted=$true}
                    throw ('T010 '+$stage)
                }}
                return {}
            }
            $metadata=if($stage -eq 'InvalidMetadata'){[pscustomobject]@{Password='FAKE-INVALID'}}else{[pscustomobject]@{Campaign=' C42 ';Stage='Prepare'}}
            $r=Invoke-PestoUnattendedOperation -RuntimeRoot $runtime -ConfigPath 'unused' -Action Rename -Computer PC-OLD -NewName PC-NEW -Metadata $metadata -Execute
            Assert-Integration ($r.ExitCode -eq $(if($stage -eq 'AfterMutation'){97}else{96})) $r.Message
            Assert-Integration ($r.MutationStarted -eq ($stage -eq 'AfterMutation'))
            if($stage -in @('BeforeMutation','AfterMutation')) {
                Assert-Integration ($r.OperationId -match '^[a-f0-9]{32}$' -and $r.OperationId -ceq $script:T010Operation) $r.Message
                Assert-Integration ($null -ne $r.Plan)
            }else{Assert-Integration (-not $r.OperationId);Assert-Integration ($null -eq $r.Plan)}
            if($stage -in @('Init','InvalidMetadata')){Assert-Integration (-not $r.Metadata.Campaign)}else{Assert-Integration ($r.Metadata.Campaign -ceq 'C42' -and $r.Metadata.Stage -ceq 'Prepare')}
            if($stage -ne 'InvalidMetadata'){Assert-Integration ($r.Message -match 'T010') $r.Message}
        }
    }
    # Contrat du point d’entrée ; le moteur est remplacé ici, jamais AD ou Windows.
    function Assert-PestoAutomationPlatform {}
    $cfgPath=Join-Path $temp 'cfg.json'
    [IO.File]::Copy((Join-Path (Split-Path $runtime -Parent) 'tools/cfg.modele-complet.json'),$cfgPath)
    function Invoke-PestoUnattendedOperation {
        param($RuntimeRoot,$ConfigPath,$Credential,$Action,$Computer,$NewName,$TargetOU,$PreparedPlan,$Metadata,[switch]$Execute)
        $script:dispatchCalls++
        $script:lastDispatch=[pscustomobject]@{Action=$Action;Computer=$Computer;NewName=$NewName;Execute=[bool]$Execute;Credential=$Credential}
        $cfg=Read-PestoAutomationJson $ConfigPath
        $p=New-PestoPortablePlan -Action $Action -ConfigStamp (Get-PestoConfigurationSignature $cfg) -Computer $Computer -NewName $NewName -TargetOU $TargetOU -Domain 'example.local' -ObjectGuid '22222222-2222-4222-8222-222222222222' -SourceOU $TargetOU -MachineId $script:machine -Metadata $Metadata
        New-PestoIntegrationResult -Mode $Action -ExitCode $(if($Execute){3010}else{0}) -State $(if($Execute){'PendingRestart'}else{'Prepared'}) -Message 'Double moteur' -Plan $p -Metadata $Metadata
    }
    Case-Integration 'CLI préparation puis plan réutilisé et clé sans masquage variable Action' {
        $script:dispatchCalls=0;$planFile=Join-Path $temp 'dispatch.json'
        $r=Invoke-PestoCommand -RuntimeRoot $runtime -ConfigPath $cfgPath -Action Rename -Computer PC001 -NewName P123456PAINF001 -TargetOU 'OU=Paris,DC=example,DC=local' -OutPlanPath $planFile
        Assert-Integration ($r.State -ceq 'Prepared' -and $script:dispatchCalls -eq 1 -and -not $script:lastDispatch.Execute)
        $r=Invoke-PestoCommand -RuntimeRoot $runtime -ConfigPath $cfgPath -Action Rename -PlanPath $planFile -IdempotencyKey 'cli/pc001' -Execute
        Assert-Integration ($r.ExitCode -eq 3010 -and $script:dispatchCalls -eq 2 -and $script:lastDispatch.Action -ceq 'Rename' -and $script:lastDispatch.Computer -ceq 'PC001')
        $r=Invoke-PestoCommand -RuntimeRoot $runtime -ConfigPath $cfgPath -Action Rename -PlanPath $planFile -IdempotencyKey 'cli/pc001' -Execute
        Assert-Integration ($r.ExitCode -eq 3010 -and $r.Replayed -and $script:dispatchCalls -eq 2)
    }
    Case-Integration 'CLI arguments différents du plan refusés avant moteur' {
        $before=$script:dispatchCalls
        $r=Invoke-PestoCommand -RuntimeRoot $runtime -ConfigPath $cfgPath -Action Rename -PlanPath (Join-Path $temp 'dispatch.json') -Computer PC002 -Execute
        Assert-Integration ($r.ExitCode -eq 96 -and $script:dispatchCalls -eq $before)
    }
    Case-Integration 'CLI refus export avec exécution et lecture avec Execute' {
        $before=$script:dispatchCalls
        $r=Invoke-PestoCommand -RuntimeRoot $runtime -ConfigPath $cfgPath -Action Rename -OutPlanPath (Join-Path $temp 'bad.json') -Execute
        Assert-Integration ($r.ExitCode -eq 96)
        $r=Invoke-PestoCommand -RuntimeRoot $runtime -ConfigPath $cfgPath -Action Inspect -Execute
        Assert-Integration ($r.ExitCode -eq 96 -and $script:dispatchCalls -eq $before)
    }
}finally{$env:PESTO_READONLY_SESSION=$oldReadOnly;if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}}
$report=[pscustomobject]@{Schema=1;Suite='Integration';HostOS=[Environment]::OSVersion.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=([Environment]::OSVersion.Platform -eq 'Win32NT');ADExecuted=$false;WPFExecuted=$false;Scope='Fonctions réelles, identité et écriture des reçus remplacées par doubles';Total=$cases.Count;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Cases=$cases.ToArray()}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))}
$report|Select-Object Suite,Total,Passed,Failed|Format-Table
if($report.Failed){exit 1}

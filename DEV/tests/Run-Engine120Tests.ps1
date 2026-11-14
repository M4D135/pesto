#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath)
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $root 'wad/Pesto.Engine.psd1') -Force -PassThru
# Fixture administrée vide : ne pas lire les stratégies de la machine de test.
& $module {function script:Get-PestoManagedPolicy {[pscustomobject]@{Values=[pscustomobject]@{};Configured=$false;Source='test'}}}
$cases=[Collections.Generic.List[object]]::new()
function Check-PestoCase {param([string]$Name,[scriptblock]$Body);try{& $Body;$cases.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$cases.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function Require {param($Condition,[string]$Message='Assertion refusée');if(-not $Condition){throw $Message}}
function Reject {param([scriptblock]$Body);$caught=$false;try{& $Body|Out-Null}catch{$caught=$true};Require $caught 'Un refus était attendu.'}
Check-PestoCase 'Import sans WPF ou AD' {Require (-not(Get-Module ActiveDirectory));Require (-not([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object{$_.GetName().Name -eq 'PresentationFramework'}))}
Check-PestoCase 'Trois workers réels exportables' {foreach($n in @('Direct','Queue','Preflight')){Require ((Get-PestoEngineWorkerScriptBlock $n) -is [scriptblock])}}
Check-PestoCase 'Source worker disponible sans interface' {Require ((Get-PestoWorkerCoreSource).Contains('function Invoke-PestoGuardedAction'))}
Check-PestoCase 'Contexte typé sans credential' {$c=Get-PestoExecutionContext -Domain example.test -DC dc.example.test;Require ($c.PSTypeNames -contains 'Pesto.Engine.Context');Require (-not $c.PSObject.Properties['Credential'])}
Check-PestoCase 'Contexte refuse DC invalide' {Reject {Get-PestoExecutionContext -Domain example.test -DC 'a;cmd'}}
Check-PestoCase 'Contexte refuse identifiant vide' {Reject {Get-PestoExecutionContext -Domain example.test -DC dc.example.test -OperationId 'x'}}
Check-PestoCase 'Incident et mode silencieux désactivés par défaut' {$p=ConvertTo-PestoPolicy $null;Require (-not $p.IncidentMode);Require (-not $p.UnattendedOperationsEnabled)}
Check-PestoCase 'Incident exige booléen JSON' {Reject {ConvertTo-PestoPolicy ([pscustomobject]@{Schema=1;IncidentMode='false'})}}
Check-PestoCase 'Incident bloque avant AD' {Reject {& $module {Assert-PestoOperationPolicy -Plan ([pscustomobject]@{}) -Policy ([pscustomobject]@{Schema=1;IncidentMode=$true})}}}
Check-PestoCase 'Incident bloque jonction préflight' {Reject {& $module {Get-PestoJoinPreflight ([pscustomobject]@{Policy=[pscustomobject]@{Schema=1;IncidentMode=$true}})}}}
Check-PestoCase 'Verified nécessite observation' {Require (-not(Test-PestoStateTransition Running Verified));Require (Test-PestoStateTransition Running Verified -ObservationConfirmed $true)}
Check-PestoCase 'Verified interdit pendant worker actif' {Require (-not(Test-PestoStateTransition Running Verified -ObservationConfirmed $true -MutationActive $true))}
Check-PestoCase 'Pas de rejeu après succès' {Require (-not(Test-PestoStateTransition Verified Running));Require (-not(Test-PestoStateTransition PendingRestart Running))}
Check-PestoCase 'Phase inconnue refusée' {Require (-not(Test-PestoStateTransition Arbitrary Verified -ObservationConfirmed $true))}
Check-PestoCase 'Erreur native typée accès refusé' {$e=New-PestoEngineError ([ComponentModel.Win32Exception]::new(5)) -Phase Write;Require ($e.Category -eq 'AccessDenied');Require (-not $e.RetryableRead)}
Check-PestoCase 'Erreur transport lecture bornable' {$e=New-PestoEngineError ([ComponentModel.Win32Exception]::new(1722)) -Phase Read;Require $e.RetryableRead}
Check-PestoCase 'Jamais reprise mutation sur erreur transport' {$e=New-PestoEngineError ([ComponentModel.Win32Exception]::new(1722)) -Phase Write -MutationPossible $true;Require (-not $e.RetryableRead)}
Check-PestoCase 'Message localisé ne décide pas du code' {$e=New-PestoEngineError ([Exception]::new('access denied RPC'));Require ($e.Category -eq 'Unknown');Require ($null -eq $e.NativeCode)}
Check-PestoCase 'Capabilities lecture ne certifie pas écriture' {$r=& $module {Get-PestoAccountCapability Join -ReadSucceeded $true};Require ($r.Read -eq 'Observed');Require ($r.Write -eq 'NotCertifiable')}
Check-PestoCase 'Capabilities refus natif connu' {$r=& $module {Get-PestoAccountCapability Move -NativeCode 5};Require ($r.Write -eq 'Refused')}
Check-PestoCase 'Transports adaptés sans WinRM' {$r=& $module {Get-PestoTransportRequirements Move};Require (@($r.Ports).Count -eq 2);Require (5985 -notin $r.Ports)}
Check-PestoCase 'Actions diagnostic sans écriture' {Require (@(Get-PestoDiagnosticActions|Where-Object Writes).Count -eq 0)}
$log=@('10/13/2026 10:00:00:000 Netp: joining PC001','10/13/2026 10:00:00:500 Netp status: 0xaac','10/13/2026 11:00:00:000 unrelated PC002')
Check-PestoCase 'NetSetup corrélé noms intervalle code' {$r=ConvertFrom-PestoNetSetupLog -Lines $log -Start '2026-10-13T10:00:00Z' -End '2026-10-13T10:00:01Z' -Names PC001 -LogTimeZone ([TimeZoneInfo]::Utc);Require ($r.Records.Count -eq 2);Require ($r.Correlation -eq 'TimeAndName');Require (2732 -in $r.Records[1].NativeCodes);Require (-not $r.ProvesSuccess)}
Check-PestoCase 'NetSetup absence nom non confirmée' {$r=ConvertFrom-PestoNetSetupLog -Lines $log -Start '2026-10-13T10:00:00Z' -End '2026-10-13T10:00:01Z' -Names PC009 -LogTimeZone ([TimeZoneInfo]::Utc);Require ($r.Correlation -eq 'Unconfirmed')}
Check-PestoCase 'NetSetup borné signale troncature' {$r=ConvertFrom-PestoNetSetupLog -Lines $log -Start '2026-10-13T10:00:00Z' -End '2026-10-13T10:00:01Z' -MaximumRecords 1 -LogTimeZone ([TimeZoneInfo]::Utc);Require $r.Truncated}
Check-PestoCase 'NetSetup intervalle inversé refusé' {Reject {ConvertFrom-PestoNetSetupLog -Lines $log -Start '2026-10-14Z' -End '2026-10-13Z'}}
Check-PestoCase 'Diagnostics invalides refusés avant réseau' {Reject {Invoke-PestoReadDiagnostics -Domain 'x;cmd' -DC dc.example.test}}
Check-PestoCase 'Diagnostics réseau avec doubles sans bascule' {
    $r=& $module {
        function Get-DomainController {param($Domain);'dc.example.test'}
        function Resolve-DnsName {[pscustomobject]@{Type='SRV';NameTarget='dc.example.test';Port=389;Priority=0;Weight=100}}
        function Test-PestoDiagnosticEndpoint {param($HostName,$Port);[pscustomobject]@{Host=$HostName;Port=$Port;Reachable=$true}}
        Invoke-PestoReadDiagnostics -Domain example.test -Action Move
    }
    Require ($r.DC -eq 'dc.example.test');Require $r.ReadOnly;Require (-not $r.MutationAuthorized)
}
Check-PestoCase 'Brouillon JSON int64 conserve contrat et sortie int32' {
    foreach($schema in @([int]1,[long]1)){
        $draft=[pscustomobject]@{Schema=$schema;Domain='example.test';Nom_du_PC='PC1';Nouveau_Nom='';Renommer=$false;Deplacer=$false}
        $r=& $module {param($d) ConvertTo-PestoDraft $d} $draft;Require ($r.Schema -is [int] -and $r.Schema -eq 1)
        $roundtrip=$draft|ConvertTo-Json|ConvertFrom-Json
        $r=& $module {param($d) ConvertTo-PestoDraft $d} $roundtrip;Require ($r.Schema -is [int] -and $r.Schema -eq 1)
    }
}
Check-PestoCase 'Brouillon refuse schema chaine booleen double et version inconnue' {
    foreach($schema in @('1',$true,[double]1,[int]2,[long]2)){
        $draft=[pscustomobject]@{Schema=$schema;Domain='example.test';Nom_du_PC='PC1';Nouveau_Nom='';Renommer=$false;Deplacer=$false}
        Reject {& $module {param($d) ConvertTo-PestoDraft $d} $draft}
    }
}
Check-PestoCase 'Migration garde original exact' {$j='{"Schema":1,"RandomNameChoice":5}';$m=ConvertTo-PestoSchemaMigration -Json $j -Kind Policy;Require ($m.OriginalJson -ceq $j);Require $m.Result.RandomNameEnabled;Require $m.RequiresExplicitSave}
Check-PestoCase 'NetSetup identifiant corrélé sans preuve de succès' {$id=[Guid]::NewGuid().ToString('N');$r=ConvertFrom-PestoNetSetupLog -Lines $log -Start '2026-10-13T10:00:00Z' -End '2026-10-13T10:00:01Z' -OperationId $id -LogTimeZone ([TimeZoneInfo]::Utc);Require ($r.OperationId -eq $id);Require (-not $r.ProvesSuccess)}
Check-PestoCase 'Migration schéma inconnu refusée' {Reject {ConvertTo-PestoSchemaMigration -Json '{"Schema":99}' -Kind Receipt}}
Check-PestoCase 'Migration configuration convertit RandomNameChoice sans le garder' {
    $cfg=[IO.File]::ReadAllText((Join-Path $root 'wad/cfg.example.json'))|ConvertFrom-Json
    $cfg|Add-Member NoteProperty POLICY ([pscustomobject]@{Schema=1;RandomNameChoice=5}) -Force
    $m=ConvertTo-PestoSchemaMigration -Json ($cfg|ConvertTo-Json -Depth 30) -Kind Configuration
    Require ($m.Result.POLICY.RandomNameEnabled -eq $true) 'RandomNameEnabled attendu'
    Require ($null -eq $m.Result.POLICY.PSObject.Properties['RandomNameChoice']) 'RandomNameChoice doit disparaître'
    Require ($null -eq $m.Result.PSObject.Properties['Policy'] -or $m.Result.PSObject.Properties['Policy'].Name -ceq 'POLICY') 'Aucune clé Policy ajoutée'
    Require $m.Changed;Require $m.RequiresExplicitSave
}
Check-PestoCase 'Politique fermée : options retirées refusées' {foreach($key in @('AllowDcRediscovery','SCENARIOS','ScenarioRequired')){$p=[pscustomobject]@{Schema=1};$p|Add-Member NoteProperty $key $false;Reject {ConvertTo-PestoPolicy $p -LocalOnly}}}
Check-PestoCase 'Historique vide oriente vers Interventions et reprises' {
    $t=& $module {Get-PestoHistoryEmptyText};Require ($t -like 'Aucun lot terminé*« Interventions et reprises »*');Require ($t -notlike '*reçu(s)*')
    $t=& $module {Get-PestoHistoryEmptyText -ReceiptCount 3};Require ($t -like '*(3 reçu(s) local(aux))*')
    $t=& $module {Get-PestoHistoryEmptyText -ReceiptCount 0};Require ($t -notlike '*reçu(s)*')
}
Check-PestoCase 'Relecture différée bornée et lecture seule' {
    $r=& $module {@((Get-PestoStateRetryDelay $null),(Get-PestoStateRetryDelay ([pscustomobject]@{Verified=$false})),(Get-PestoStateRetryDelay ([pscustomobject]@{RetryAfterSec=30})),(Get-PestoStateRetryDelay ([pscustomobject]@{RetryAfterSec=9999})),(Get-PestoStateRetryDelay ([pscustomobject]@{RetryAfterSec='x'})))}
    Require ($r[0] -eq 0 -and $r[1] -eq 0 -and $r[2] -eq 30 -and $r[3] -eq 0 -and $r[4] -eq 0) ('Délais inattendus : '+($r -join ','))
}
$temp=Join-Path $PSScriptRoot ('.engine120-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try{
    Check-PestoCase 'Migration sauve bytes originaux sans écrasement' {
        $source=Join-Path $temp 'policy.json';$out=Join-Path $temp 'migrated.json';[IO.File]::WriteAllText($source,'{"Schema":1,"RandomNameChoice":3}')
        $sha=(Get-FileHash $source).Hash;$r=Save-PestoSchemaMigration $source $out Policy
        Require ((Get-FileHash $source).Hash -eq $sha);Require ((Get-FileHash $r.OriginalBackup).Hash -eq $sha)
        Reject {Save-PestoSchemaMigration $source $out Policy}
    }
    Check-PestoCase 'Migration refuse UTF-8 invalide sans rien écrire' {
        $source=Join-Path $temp 'latin1.json';$out=Join-Path $temp 'latin1-migrated.json'
        $bytes=[Collections.Generic.List[byte]]::new();$bytes.AddRange([Text.Encoding]::ASCII.GetBytes('{"Schema":1,"ExcludedOUs":["OU=Si'));$bytes.Add(0xE8);$bytes.AddRange([Text.Encoding]::ASCII.GetBytes('ge,DC=example,DC=test"]}'))
        [IO.File]::WriteAllBytes($source,$bytes.ToArray())
        Reject {Save-PestoSchemaMigration $source $out Policy}
        Require (-not [IO.File]::Exists($out)) 'Sortie écrite malgré un octet invalide'
        Require (-not [IO.File]::Exists($out+'.original')) 'Sauvegarde écrite malgré un octet invalide'
        Require (@(Get-ChildItem -LiteralPath $temp -Filter 'latin1-migrated.json*').Count -eq 0) 'Fichier temporaire laissé'
    }
    Check-PestoCase 'Migration configuration sauvegardée sans RandomNameChoice' {
        $cfg=[IO.File]::ReadAllText((Join-Path $root 'wad/cfg.example.json'))|ConvertFrom-Json
        $cfg|Add-Member NoteProperty POLICY ([pscustomobject]@{Schema=1;RandomNameChoice=0}) -Force
        $source=Join-Path $temp 'cfg-legacy.json';$out=Join-Path $temp 'cfg-migrated.json'
        [IO.File]::WriteAllText($source,($cfg|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($true))
        $r=Save-PestoSchemaMigration $source $out Configuration
        $saved=[IO.File]::ReadAllText($r.OutputPath)|ConvertFrom-Json
        Require ($saved.POLICY.RandomNameEnabled -eq $false);Require ($null -eq $saved.POLICY.PSObject.Properties['RandomNameChoice'])
    }
    Check-PestoCase 'Écriture atomique : trois nouvelles tentatives sur verrou puis échec' {
        $target=Join-Path $temp 'atomic-locked.json'
        $r=& $module {param($Path)
            $script:PestoAtomicCalls=0;$failed=$false
            $script:PestoFileReplaceHook={param($Tmp,$Full,$Backup) $script:PestoAtomicCalls++;throw [IO.IOException]::new('verrou simulé',-2147024864)}
            try{Write-PestoAtomicText -Path $Path -Text '{}'}catch{$failed=$true}finally{$script:PestoFileReplaceHook=$null}
            [pscustomobject]@{Calls=$script:PestoAtomicCalls;Failed=$failed}
        } $target
        Require $r.Failed 'Échec attendu';Require ($r.Calls -eq 4) ('4 essais attendus, obtenu '+$r.Calls)
        Require (-not [IO.File]::Exists($target));Require (@(Get-ChildItem -LiteralPath $temp -Filter 'atomic-locked.json*').Count -eq 0) 'Fichier temporaire laissé'
    }
    Check-PestoCase 'Écriture atomique : réussite après deux verrous, autre erreur immédiate' {
        $target=Join-Path $temp 'atomic-retry.json'
        $r=& $module {param($Path)
            $script:PestoAtomicCalls=0
            $script:PestoFileReplaceHook={param($Tmp,$Full,$Backup) $script:PestoAtomicCalls++;if($script:PestoAtomicCalls -le 2){throw [IO.IOException]::new('verrou simulé',-2147024863)};[IO.File]::Move($Tmp,$Full)}
            try{Write-PestoAtomicText -Path $Path -Text '{"ok":1}'}finally{$script:PestoFileReplaceHook=$null}
            $first=$script:PestoAtomicCalls;$script:PestoAtomicCalls=0;$failed=$false
            $script:PestoFileReplaceHook={param($Tmp,$Full,$Backup) $script:PestoAtomicCalls++;throw [IO.IOException]::new('disque plein simulé',-2147024784)}
            try{Write-PestoAtomicText -Path ($Path+'.other') -Text '{}'}catch{$failed=$true}finally{$script:PestoFileReplaceHook=$null}
            [pscustomobject]@{First=$first;Second=$script:PestoAtomicCalls;Failed=$failed}
        } $target
        Require ($r.First -eq 3) ('3 essais attendus, obtenu '+$r.First);Require ([IO.File]::ReadAllText($target) -eq '{"ok":1}')
        Require $r.Failed;Require ($r.Second -eq 1) ('Aucune nouvelle tentative attendue, obtenu '+$r.Second)
    }
    $cache=New-PestoInterventionCatalogCache;$catalog=Join-Path $temp 'catalog';[void][IO.Directory]::CreateDirectory($catalog)
    $fixture=Join-Path $catalog 'a.json';[IO.File]::WriteAllText($fixture,'{"OperationId":"one","Phase":"PendingRestart"}')
    $reader={param($Directory,$State,$Force)
        function Read-PestoIntervention {param($Path);[IO.File]::ReadAllText($Path)|ConvertFrom-Json}
        Get-PestoInterventionCatalogCached -Root $Directory -Cache $State -Force:$Force
    }
    Check-PestoCase 'Cache première lecture puis hit' {$a=& $module $reader $catalog $cache $false;$b=& $module $reader $catalog $cache $false;Require ($a.ParsedFiles -eq 1);Require ($b.CacheHits -eq 1);Require ($a.Version -eq $b.Version)}
    Check-PestoCase 'Cache objets retournés indépendants' {$a=& $module $reader $catalog $cache $false;$a.Entries[0].Receipt.Phase='Verified';$b=& $module $reader $catalog $cache $false;Require ($b.Entries[0].Receipt.Phase -eq 'PendingRestart')}
    Check-PestoCase 'Cache actualisation forcée relit' {$a=& $module $reader $catalog $cache $true;Require ($a.ParsedFiles -eq 1);Require ($a.CacheHits -eq 0)}
    Check-PestoCase 'Cache suppression invalide index' {[IO.File]::Delete($fixture);$a=& $module $reader $catalog $cache $false;Require ($a.Entries.Count -eq 0);Require ($cache.Files.Count -eq 0)}
    Check-PestoCase 'Cache isole reçu invalide' {[IO.File]::WriteAllText($fixture,'bad-json');$a=& $module $reader $catalog $cache $false;Require ($a.InvalidCount -eq 1);Require (-not $a.Entries[0].Readable)}
    Check-PestoCase 'Cache invalidation explicite' {Clear-PestoInterventionCatalogCache $cache;Require ($cache.Files.Count -eq 0)}
}finally{Remove-Item -LiteralPath $temp -Force -Recurse}
Check-PestoCase 'Coalescence exception nettoie registre' {$c=New-PestoReadCoordinator;Reject {Invoke-PestoReadCoalesced -Coordinator $c -Key test -ReadAction {throw 'read failed'}};Require ($c.Active.Count -eq 0)}
Check-PestoCase 'Coalescence sessions isolées' {$a=New-PestoReadCoordinator;$b=New-PestoReadCoordinator;Require ($a.Scope -ne $b.Scope)}
Check-PestoCase 'Coalescence trois vrais runspaces une lecture' {
    $c=New-PestoReadCoordinator;$state=[hashtable]::Synchronized(@{Count=0});$workers=@()
    $source=& $module {'function Invoke-PestoReadCoalesced {'+${function:Invoke-PestoReadCoalesced}.ToString()+'}'}
    try{
        foreach($n in 1..3){$ps=[PowerShell]::Create();[void]$ps.AddScript('param($src,$c,$s);. ([scriptblock]::Create($src));Invoke-PestoReadCoalesced -Coordinator $c -Key same -ReadAction {param($x);$x.Count++;[Threading.Thread]::Sleep(400);42} -ArgumentList @($s)').AddArgument($source).AddArgument($c).AddArgument($state);$workers+=@{PowerShell=$ps;Handle=$ps.BeginInvoke()}}
        $results=@(foreach($worker in $workers){$worker.PowerShell.EndInvoke($worker.Handle)})
        Require ($state.Count -eq 1);Require (@($results|Where-Object Shared).Count -eq 2);Require (@($results|Where-Object{$_.Value -eq 42}).Count -eq 3)
    }finally{foreach($worker in $workers){$worker.PowerShell.Dispose()}}
}

Check-PestoCase 'Source worker préserve bootstrap sans WPF' {$src=Get-PestoWorkerCoreSource;Require (-not($src -match '(?m)^function (Write-Log|Confirm-YesNo|Show-MsgError)\s*\{'));Require ($src.Contains('function Merge-PestoManagedPolicy'))}
Check-PestoCase 'Résultat natif typé sans succès implicite' {$r=& $module {New-ActionResult -ExitCode '20' -ExitMsg 'bad type'};Require ($r.PSTypeNames -contains 'Pesto.ActionResult');Require ($r.ExitCode -eq 97);Require ($r.Outcome -eq 'Uncertain')}
Check-PestoCase 'Transitions matrice Verified interdit sans observation' {foreach($from in (Get-PestoStateTransitions).Keys){Require (-not(Test-PestoStateTransition $from Verified));Require (-not(Test-PestoStateTransition $from Verified -ObservationConfirmed $true -MutationActive $true))}}
Check-PestoCase 'Reprise déplacement conserve phases acquises' {Require (Test-PestoStateTransition Partial MoveReady);Require (Test-PestoStateTransition MoveReady PendingRestart);Require (-not(Test-PestoStateTransition MoveReady Running))}
Check-PestoCase 'Découverte domaine ne déclenche pas reprise transport' {$e=New-PestoEngineError ([ComponentModel.Win32Exception]::new(1355));Require (-not $e.RetryableRead)}
Check-PestoCase 'Retry lecture élimine sortie partielle de tentative' {$r=& $module {$state=@{Count=0};$items=@(Invoke-PestoReadRetry -Attempts 3 -DelayMs 0 -Read {$state.Count++;if($state.Count -eq 1){'partial';throw [ComponentModel.Win32Exception]::new(1722)};'complete'});[pscustomobject]@{Count=$state.Count;Items=$items}};Require ($r.Count -eq 2);Require ($r.Items.Count -eq 1);Require ($r.Items[0] -eq 'complete')}
Check-PestoCase 'Retry accès refusé reste une tentative' {$r=& $module {$state=@{Count=0};try{Invoke-PestoReadRetry -Attempts 3 -DelayMs 0 -Read {$state.Count++;throw [ComponentModel.Win32Exception]::new(5)}}catch{};$state.Count};Require ($r -eq 1)}
Check-PestoCase 'Retry borne trois tentatives et respecte annulation' {$r=& $module {$state=@{Count=0};try{Invoke-PestoReadRetry -Attempts 3 -DelayMs 0 -Read {$state.Count++;throw [ComponentModel.Win32Exception]::new(1722)}}catch{};$state.Count};Require ($r -eq 3);Reject {& $module {Invoke-PestoReadRetry -Read {throw 'must not start'} -Cancellation @{Cancelled=$true}}}}
Check-PestoCase 'DN générés préservent virgules échappées' {foreach($i in 1..40){$parts=& $module {param($n) @(Split-PestoDistinguishedName ('CN=PC'+$n+',OU=Site\,'+$n+',DC=example,DC=test'))} $i;Require ($parts.Count -eq 4);Require ($parts[1] -eq ('OU=Site\,'+$i))}}
Check-PestoCase 'DN contrôles et composant vide refusés' {foreach($dn in @('CN=X,,DC=example,DC=test','CN=X+OU=Y,DC=example,DC=test',"CN=X`nY,DC=test",'CN=X\')){Reject {& $module {param($v) Split-PestoDistinguishedName $v} $dn}}}
Check-PestoCase 'Métadonnées fermées et sans secrets' {$m=ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Stage='INC-120';Campaign='Test'});Require ($m.Stage -eq 'INC-120');foreach($bad in @([pscustomobject]@{Password='value'},[pscustomobject]@{Stage='token=secret'},[pscustomobject]@{Stage="a`nb"})){Reject {ConvertTo-PestoDeploymentMetadata $bad}}}
Check-PestoCase 'Plan conserve les métadonnées et omet la référence retirée' {$p=& $module {New-PestoExecutionPlan ([pscustomobject]@{Rename=$true;Move=$false;Reboot=$false;Computer='PC1';Reference='INC-120';Metadata=[pscustomobject]@{Stage='Prepare'}})};Require ($null -eq $p.PSObject.Properties['Reference']);Require ($p.Metadata.Stage -eq 'Prepare');Require ($p.PSTypeNames -contains 'Pesto.ExecutionPlan')}
Check-PestoCase 'Champs métier retirés refusés dans les métadonnées neuves' {foreach($field in @('Ticket','AssetId')){$v=[pscustomobject]@{};$v|Add-Member NoteProperty $field 'legacy';Reject {ConvertTo-PestoDeploymentMetadata $v}}}
Check-PestoCase 'Reçu jonction valide avec métadonnées objet' {$r=& $module {$v=[pscustomobject]@{Schema=1;OperationId=[Guid]::NewGuid().ToString('N');Phase='PendingRestart';Utc='2026-10-13T10:00:00Z';BootUtc='2026-10-13T09:00:00Z';MachineId='test-machine';Computer='PC1';NewName='P111301LY765128';Domain='example.test';OU='OU=Postes,DC=example,DC=test';Metadata=[pscustomobject]@{Stage='INC-120'}};Assert-PestoJoinReceiptData $v};Require ($r.Metadata.Stage -eq 'INC-120');Require ($r.Phase -eq 'PendingRestart')}
Check-PestoCase 'Migration reçu n invente ni phase ni identifiant' {foreach($j in @('{"Schema":"1","OperationId":"x","Phase":"Verified"}','{"Schema":1,"OperationId":"x","Phase":"Verified"}','{"Schema":1,"OperationId":"8db08778-72a9-4617-9759-65ef40b155ab","Phase":"Invented"}')){Reject {ConvertTo-PestoSchemaMigration $j Receipt}}}
Check-PestoCase 'Migration reçu garde PendingRestart inchangé' {$j='{"Schema":1,"OperationId":"8db08778-72a9-4617-9759-65ef40b155ab","Phase":"PendingRestart"}';$m=ConvertTo-PestoSchemaMigration $j Receipt;Require (-not $m.Changed);Require ($m.Result.Phase -eq 'PendingRestart')}
Check-PestoCase 'Journal masque token bearer et URL authentifiée' {$e=& $module {New-PestoStructuredEvent -Message 'authorization: Bearer abc password="hello world" https://user:pwd@example.test/x token=qrs' -OperationId '8db08778-72a9-4617-9759-65ef40b155ab'};Require ($e.Message -notmatch 'abc|hello|user:pwd|qrs');Require ($e.OperationId -eq '8db08778-72a9-4617-9759-65ef40b155ab')}
Check-PestoCase 'Journal corrèle opération worker étape build' {$r=& $module {$script:PestoQueueMonitor=New-PestoQueueMonitor -Computer PC1 -OperationId '8db08778-72a9-4617-9759-65ef40b155ab' -BuildSHA256 ('a'*64);Publish-PestoWorkerLog -Text 'read';$e=$null;[void]$script:PestoQueueMonitor.Events.TryDequeue([ref]$e);$script:PestoQueueMonitor=$null;$e};Require ($r.OperationId -eq '8db08778-72a9-4617-9759-65ef40b155ab');Require ($r.WorkerId.Length -eq 32);Require ($r.BuildSHA256 -eq ('a'*64));Require ([bool]$r.Stage)}
Check-PestoCase 'Journal borne texte et refuse empreinte invalide' {$r=& $module {New-PestoStructuredEvent -Message ('a'*5000)};Require ($r.Message.Length -lt 4100);Reject {& $module {New-PestoStructuredEvent -BuildSHA256 wrong}}}

Check-PestoCase 'Catalogue partagé trois runspaces une lecture forcée' {
    $tmp=Join-Path $PSScriptRoot ('.catalog-flight-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($tmp)
    [IO.File]::WriteAllText((Join-Path $tmp 'one.json'),'{}')
    $cache=New-PestoInterventionCatalogCache;$shared=[hashtable]::Synchronized(@{Count=0;Ready=0});$gate=[Threading.ManualResetEventSlim]::new($false);$workers=@();$source=Get-PestoWorkerCoreSource
    try{
        foreach($n in 1..3){
            $ps=[PowerShell]::Create();[void]$ps.AddScript(@'
param($Source,$Cache,$Root,$State,$Gate)
. ([scriptblock]::Create($Source))
$script:CatalogReadCounter=$State
function Read-PestoIntervention {param($Path);$script:CatalogReadCounter.Count++;[Threading.Thread]::Sleep(300);[pscustomobject]@{OperationId='one';Phase='PendingRestart'}}
[Threading.Monitor]::Enter($State.SyncRoot);try{$State.Ready++;$ordinal=$State.Ready}finally{[Threading.Monitor]::Exit($State.SyncRoot)}
if(-not $Gate.Wait(10000)){throw 'Gate timeout'}
if($ordinal -gt 1){$wait=[Diagnostics.Stopwatch]::StartNew();while($State.Count -eq 0 -and $wait.ElapsedMilliseconds -lt 5000){[Threading.Thread]::Sleep(1)}}
Get-PestoInterventionCatalogCached -Root $Root -Cache $Cache -Force
'@).AddArgument($source).AddArgument($cache).AddArgument($tmp).AddArgument($shared).AddArgument($gate)
            $workers+=@{PowerShell=$ps;Handle=$ps.BeginInvoke()}
        }
        $clock=[Diagnostics.Stopwatch]::StartNew();while($shared.Ready -lt 3 -and $clock.ElapsedMilliseconds -lt 10000){[Threading.Thread]::Sleep(5)};$gate.Set()
        $r=@(foreach($worker in $workers){$worker.PowerShell.EndInvoke($worker.Handle);if($worker.PowerShell.Streams.Error.Count){throw $worker.PowerShell.Streams.Error[0]}})
        Require ($shared.Count -eq 1) ('Lectures réelles : '+$shared.Count);Require ($r.Count -eq 3) ('Résultats : '+$r.Count);$r[0].Entries[0].Receipt.Phase='changed';Require ($r[1].Entries[0].Receipt.Phase -eq 'PendingRestart')
    }finally{$gate.Set();foreach($worker in $workers){$worker.PowerShell.Dispose()};$gate.Dispose();Remove-Item -LiteralPath $tmp -Recurse -Force}
}

Check-PestoCase 'Import refuse runtime généré altéré' {
    $tmp=Join-Path $PSScriptRoot ('.engine-tamper-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($tmp)
    try{foreach($name in @('Pesto.Engine.psd1','Pesto.Engine.psm1','Pesto.Engine.Runtime.ps1')){[IO.File]::Copy((Join-Path $root ('wad/'+$name)),(Join-Path $tmp $name))};[IO.File]::AppendAllText((Join-Path $tmp 'Pesto.Engine.Runtime.ps1'),'# tamper');Reject {Import-Module (Join-Path $tmp 'Pesto.Engine.psd1') -Force -ErrorAction Stop}}finally{Remove-Item -LiteralPath $tmp -Recurse -Force}
}

# Point 105 : corpus déterministe sur les vraies DLL et fonctions du module.
# Les compteurs décrivent des entrées vérifiées, pas des scénarios Windows/AD.
$generative=[ordered]@{Seed=1052026;Generator='LCG 31-bit + fixed Unicode classes';UnicodeSamples=0;JsonBoundaryChecks=0;InvalidJsonCases=0;DnSamples=0;InvalidDnCases=0;TextBoundaryChecks=0;StateCombinations=0;CorpusSHA256=''}
$atoms=@('ASCII','é',('e'+[char]0x301),'日本語',[char]::ConvertFromUtf32(0x1F642),[char]::ConvertFromUtf32(0x1D11E),('a'+[char]0x200D+'b'),([char]0x2066+'RTL'+[char]0x2069),'quote"','slash\',"line`nfeed","tab`t",[string][char]0x2028)
$corpus=[Collections.Generic.List[string]]::new();$randomState=[long]$generative.Seed
for($index=0;$index -lt 256;$index++){
    $value='entry-'+$index+':'+$atoms[$index%$atoms.Count]
    foreach($draw in 1..3){$randomState=([long]$randomState*1103515245+12345)%2147483648;$value+='|'+$atoms[[int]($randomState%$atoms.Count)]}
    $corpus.Add($value)
}
$generative.CorpusSHA256=& $module {param($Values) Get-PestoStableHash $Values} (,$corpus.ToArray())
Check-PestoCase 'Generated Unicode corpus roundtrips through actual Common JSON with exact byte boundaries' {
    & $module {param($Runtime) Initialize-PestoCommon -Root $Runtime} (Join-Path $root 'wad')
    $serialize=[M4D.Admin.Common.Core.BoundedJson].GetMethod('Serialize').MakeGenericMethod([string])
    $deserialize=[M4D.Admin.Common.Core.BoundedJson].GetMethod('Deserialize').MakeGenericMethod([string])
    foreach($value in $corpus){
        [byte[]]$bytes=$serialize.Invoke($null,[object[]]@($value,8192));$length=$bytes.Length
        Reject {$serialize.Invoke($null,[object[]]@($value,($length-1)))}
        Reject {$deserialize.Invoke($null,[object[]]@($bytes,($length-1)))}
        $generative.JsonBoundaryChecks+=2
        foreach($limit in @($length,($length+1))){
            [byte[]]$again=$serialize.Invoke($null,[object[]]@($value,$limit))
            Require ([Convert]::ToBase64String($again) -ceq [Convert]::ToBase64String($bytes))
            Require ([string]$deserialize.Invoke($null,[object[]]@($bytes,$limit)) -ceq $value)
            $generative.JsonBoundaryChecks+=2
        }
        $generative.UnicodeSamples++
    }
    Require ($generative.UnicodeSamples -eq 256 -and $generative.JsonBoundaryChecks -eq 1536)
}
Check-PestoCase 'Generated invalid UTF8 and malformed JSON are rejected by the real Common deserializer' {
    $deserialize=[M4D.Admin.Common.Core.BoundedJson].GetMethod('Deserialize').MakeGenericMethod([string])
    $invalid=@([byte[]]@(0x80),[byte[]]@(0xC0,0xAF),[byte[]]@(0xED,0xA0,0x80),[byte[]]@(0xE2,0x82),[byte[]]@(0xF4,0x90,0x80,0x80))
    foreach($bytes in $invalid){Reject {$deserialize.Invoke($null,[object[]]@($bytes,8192))};$generative.InvalidJsonCases++}
    foreach($text in @('"unterminated','{"x":','"bad\q"')){
        $bytes=[Text.Encoding]::UTF8.GetBytes($text);Reject {$deserialize.Invoke($null,[object[]]@($bytes,8192))};$generative.InvalidJsonCases++
    }
    Require ($generative.InvalidJsonCases -eq 8)
}
Check-PestoCase 'Generated DN values preserve Unicode and delimiter escape parity' {
    $special=@('comma,value','plus+value','slash\value','slash\\,value','quote"value',' semi;equal=value ','#hash','less<greater>')
    foreach($index in 0..63){
        $value='Site-'+$index+'-'+@('é',('e'+[char]0x301),'日本語',[char]::ConvertFromUtf32(0x1F642))[$index%4]+'-'+$special[$index%$special.Count]
        $encoded=& $module {param($Text) ConvertTo-PestoRdnValue $Text} $value
        $parts=& $module {param($Rdn) @(Split-PestoDistinguishedName ('CN=PC,OU='+$Rdn+',DC=example,DC=test'))} $encoded
        Require ($parts.Count -eq 4 -and $parts[1] -ceq ('OU='+$encoded))
        Require ([regex]::Replace($encoded,'\\(.)','$1') -ceq $value)
        $generative.DnSamples++
    }
    foreach($value in @(' leading','trailing ','#leading','slash\\,comma','hex\2cvalue')){
        $encoded=& $module {param($Text) ConvertTo-PestoRdnValue $Text} $value
        $parts=& $module {param($Rdn) @(Split-PestoDistinguishedName ('CN=PC,OU='+$Rdn+',DC=example,DC=test'))} $encoded
        Require ($parts.Count -eq 4 -and $parts[1] -ceq ('OU='+$encoded));$generative.DnSamples++
    }
    foreach($value in @('',',CN=PC,DC=test','CN=PC,DC=test,','CN=PC,,DC=test','CN=PC, ,DC=test','CN=PC+OU=X,DC=test','CN=PC\',"CN=P`0C,DC=test","CN=P`nC,DC=test")){
        Reject {& $module {param($Text) Split-PestoDistinguishedName $Text} $value};$generative.InvalidDnCases++
    }
    Require ($generative.DnSamples -eq 69 -and $generative.InvalidDnCases -eq 9)
}
Check-PestoCase 'Generated text boundaries use UTF16 code units and preserve valid Unicode' {
    $base=('é'*117)+[char]::ConvertFromUtf32(0x1F642)
    foreach($length in @(119,120,121)){
        $value=$base+('x'*($length-$base.Length));Require ($value.Length -eq $length)
        if($length -gt 120){
            Reject {& $module {param($Text) ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Stage=$Text})} $value}
            Reject {& $module {param($Text) New-PestoExecutionPlan ([pscustomobject]@{Rename=$true;Move=$false;Reboot=$false;Computer='PC1';Metadata=[pscustomobject]@{Campaign=$Text}})} $value}
        }else{
            $metadata=& $module {param($Text) ConvertTo-PestoDeploymentMetadata ([pscustomobject]@{Stage=$Text})} $value
            $plan=& $module {param($Text) New-PestoExecutionPlan ([pscustomobject]@{Rename=$true;Move=$false;Reboot=$false;Computer='PC1';Metadata=[pscustomobject]@{Campaign=$Text}})} $value
            Require ($metadata.Stage -ceq $value -and $plan.Metadata.Campaign -ceq $value)
        }
        $generative.TextBoundaryChecks+=2
    }
    Require ($generative.TextBoundaryChecks -eq 6)
}
Check-PestoCase 'Every central state pair and observation flag matches the explicit transition contract' {
    # Oracle explicite, indépendant du graphe rendu par la fonction testée.
    $expected=[ordered]@{
        Prepared=@('Running','NotStarted','Failed');Running=@('PendingRestart','Verified','Partial','Protection','Uncertain','Failed','NotStarted')
        PendingRestart=@('PendingRestart','Verified','MoveReady','Partial','Protection','Uncertain');Partial=@('Partial','MoveReady','PendingRestart','Verified','Protection','Uncertain')
        MoveReady=@('MoveReady','PendingRestart','Verified','Partial','Protection','Uncertain');Protection=@('Protection','Verified','Partial','Uncertain')
        Uncertain=@('Uncertain','Verified','MoveReady','Partial','Protection');Verified=@('Verified');Failed=@('Failed');NotStarted=@('NotStarted')
    }
    $actual=Get-PestoStateTransitions;Require (($actual.Keys -join '|') -ceq ($expected.Keys -join '|'))
    $states=@($expected.Keys)+@('__UNKNOWN__','')
    foreach($from in $states){foreach($to in $states){foreach($observed in @($false,$true)){foreach($active in @($false,$true)){
        $allowed=$expected.Contains($from) -and $to -cin $expected[$from]
        if($to -ceq 'Verified'){$allowed=$allowed -and $observed -and -not $active}
        Require ((Test-PestoStateTransition $from $to -ObservationConfirmed $observed -MutationActive $active) -eq $allowed) ('Transition '+$from+' -> '+$to)
        $generative.StateCombinations++
    }}}}
    Require ($generative.StateCombinations -eq 576)
}

# Point 61 : la suite portable repond du comportement du helper de mise a jour en place, cette suite
# repond de la surface livree. Sans ces deux cas, le helper pouvait disparaitre du produit charge, ou
# sa regle d empreinte diverger de celle du module, sans qu'aucun test executable ici n'en convienne.
Check-PestoCase 'Le produit charge atteint le helper livre de mise a jour en place' {
    $core=[IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Core.ps1'))
    Require ($core.Contains(". (Join-Path `$PSScriptRoot 'Pesto-Collections.ps1')")) 'Pesto-Core ne charge plus Pesto-Collections : le chemin livre ne serait jamais atteint.'
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Collections.ps1'),[ref]$tokens,[ref]$errors)
    Require (-not $errors.Count) ('Source livree invalide : '+(($errors|ForEach-Object{$_.Message}) -join '; '))
    $defined=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst]}|ForEach-Object{$_.Name})
    foreach($name in @('Get-PestoGridRowId','New-PestoGridRowCollection','Update-PestoGridRows')){Require ($name -in $defined) ('Helper livre absent au niveau racine de la source livree : '+$name)}
    Require (([IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Integrity.ps1'))).Contains("'wad/Pesto-Collections.ps1'")) 'Le fichier du helper est sorti de la garde d integrite : une copie alteree serait chargee sans refus.'
}
Check-PestoCase 'L empreinte de ligne est insensible a lordre des proprietes et reproductible d un runspace a lautre' {
    # Le cache d empreintes est pose par une projection et relu par la suivante, parfois depuis un autre
    # runspace. Une regle qui dependrait de l ordre de declaration, d un champ de recu, ou du processus,
    # notifierait toute la page a chaque rendu, ou n en notifierait aucune : les deux font echouer le point.
    $tokens=$null;$errors=$null
    $shipped=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Contracts.ps1'),[ref]$tokens,[ref]$errors)
    Require (-not $errors.Count) 'Source livree invalide : Pesto-Contracts.ps1'
    $definition=$null
    foreach($statement in $shipped.EndBlock.Statements){if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -ceq 'Get-PestoStableHash'){$definition=$statement.Extent.Text;break}}
    Require ($null -ne $definition) 'Get-PestoStableHash absente de la source livree : plus aucune empreinte de ligne.'
    function New-EngineRow {param([string]$Phase)[pscustomobject]@{RowId='r1';StatusLabel='En cours';Receipt=[pscustomobject]@{Phase=$Phase;Tasks=@([pscustomobject]@{Phase='Pending'})}}}
    $row=New-EngineRow 'Running'
    $reordered=[pscustomobject]@{Receipt=[pscustomobject]@{Tasks=@([pscustomobject]@{Phase='Pending'});Phase='Running'};StatusLabel='En cours';RowId='r1'}
    Require (& $module {param($A,$B)(Get-PestoStableHash $A) -ceq (Get-PestoStableHash $B)} $row $reordered) 'Deux rendus identiques declares dans un ordre different ne publient pas la meme empreinte : toute reprojection remplacerait toute la page.'
    $changed=New-EngineRow 'Verified'
    Require (& $module {param($A,$B)(Get-PestoStableHash $A) -cne (Get-PestoStableHash $B)} $row $changed) 'Un champ de recu modifie ne change pas l empreinte : la ligne concernee ne serait jamais remplacee.'
    $viaModule=& $module {param($A) Get-PestoStableHash $A} $row
    Require ((& ([scriptblock]::Create($definition+'; Get-PestoStableHash $args[0]')) $row) -ceq $viaModule) 'La regle d empreinte du module Engine ne rend plus la meme valeur que la source livree : le cache pose par une surface serait illisible par lautre.'
    $worker=[PowerShell]::Create()
    try{
        $remote=@($worker.AddScript('param($Definition,$Value) . ([scriptblock]::Create($Definition)); Get-PestoStableHash $Value').AddArgument($definition).AddArgument($row).Invoke())
        if($worker.Streams.Error.Count){throw [Exception]::new(('Runspace : '+$worker.Streams.Error[0].Exception.Message))}
        Require ($remote.Count -eq 1 -and $remote[0] -ceq $viaModule) 'L empreinte n est pas reproductible d un runspace a l autre : le cache pose par une projection serait rejete par la suivante.'
    }finally{$worker.Dispose()}
}

# Point 64 : la pagination du registre est branchee sur Common.Query (Offset, Limit, tri Updated
# decroissant, retour a la derniere page) depuis la base RC, mais rien ne la comparait au tri complet
# existant. Sans oracle independant, un changement de composant ou de cablage pouvait deplacer,
# dupliquer ou perdre une ligne d'une page a l'autre sans qu'aucun test executable n'en convienne.
# La fonction testee est relue de la source livree par analyse syntaxique, jamais recopiee ici : la
# suite repond du chemin branche sur les vraies DLL, pas d'une copie.
function New-PestoEngineQueryRows {
    # Jeu deterministe : deux dates inconnues en tete d'entree (le tri doit les laisser en dernier,
    # dans l'ordre d'entree), puis des groupes de trois lignes partageant le meme horodatage (le tri
    # doit rester l'ordre d'entree), etats et textes varies pour que les filtres mordent.
    param([int]$Count)
    $base=[DateTimeOffset]::new(2026,10,12,10,0,0,[TimeSpan]::Zero)
    $items=[object[]]::new($Count)
    for($i=0;$i -lt $Count;$i++){
        $utc=$null
        if($i -ge 2){$utc=$base.AddMinutes([Math]::Floor(($i-2)/3))}
        $items[$i]=[pscustomobject]@{RowId='q'+$i.ToString('D6');SearchText=('PC-'+$i.ToString('D4')+' nom-'+$i);StatusCode=@('Verified','Failed','PendingRestart','Uncertain')[$i%4];Unresolved=($i%4 -ge 2);OptionalPostCheck=$false;UpdatedUtc=$utc}
    }
    return ,$items
}
function Get-PestoEngineQueryFullSort {
    # Le tri complet existant, rendu independamment de Common.Query : filtre ordinal-ignore-case,
    # tri decroissant stable par LINQ (OrderByDescending est stable, les egalites gardent l'ordre
    # d'entree), dates inconnues en dernier dans l'ordre d'entree.
    param([object[]]$Rows,[string]$Search='',[string]$State='All',[int]$Offset=0,[int]$PageSize=100)
    $matched=@($Rows|Where-Object{
        if($Search -and ([string]$_.SearchText).IndexOf($Search,[StringComparison]::OrdinalIgnoreCase) -lt 0){return $false}
        if($State -eq 'Unresolved'){return [bool]$_.Unresolved}
        if($State -ne 'All' -and -not ([string]$_.StatusCode).Equals($State,[StringComparison]::OrdinalIgnoreCase)){return $false}
        $true})
    $known=@($matched|Where-Object{$null -ne $_.UpdatedUtc})
    $unknown=@($matched|Where-Object{$null -eq $_.UpdatedUtc})
    $ordered=@([Linq.Enumerable]::OrderByDescending([Collections.Generic.IEnumerable[object]]$known,[Func[object,object]]{param($row)$row.UpdatedUtc}))+@($unknown)
    $effective=$Offset
    if($effective -ge $ordered.Count -and $effective -gt 0){$effective=[Math]::Max(0,([Math]::Ceiling($ordered.Count/$PageSize)-1)*$PageSize)}
    $last=[Math]::Min($ordered.Count,$effective+$PageSize)
    $items=@();for($i=$effective;$i -lt $last;$i++){$items+=$ordered[$i]}
    [pscustomobject]@{Items=$items;MatchedCount=$ordered.Count;TotalCount=$Rows.Count;Offset=$effective}
}
$shippedInterventionsTokens=$null;$interventionsErrors=$null
$interventionsAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Interventions.ps1'),[ref]$shippedInterventionsTokens,[ref]$interventionsErrors)
Require (-not $interventionsErrors.Count) 'Source livree invalide : wad/Pesto-Interventions.ps1'
$shippedInterventionQuery=$null
foreach($statement in $interventionsAst.EndBlock.Statements){if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -ceq 'Get-PestoInterventionQuery'){$shippedInterventionQuery=$statement.Extent.Text;break}}
Require ($null -ne $shippedInterventionQuery) 'Get-PestoInterventionQuery absente de la source livree : plus aucune pagination branchee sur le registre.'
. ([scriptblock]::Create($shippedInterventionQuery))
Check-PestoCase 'La pagination integree rend la meme page que le tri complet existant' {
    $rows=New-PestoEngineQueryRows 250
    Require (@($rows|Where-Object{$null -eq $_.UpdatedUtc}).Count -eq 2) 'Jeu de donnees degenere : les deux dates inconnues attendues sont absentes.'
    foreach($scenario in @(
        @{Label='page 1 sans filtre';Search='';State='All';Offset=0;PageSize=100;Matched=250},
        @{Label='page 2 sans filtre';Search='';State='All';Offset=100;PageSize=100;Matched=250},
        @{Label='recherche PC-001';Search='PC-001';State='All';Offset=0;PageSize=10;Matched=10},
        @{Label='recherche et etat';Search='PC-001';State='Verified';Offset=0;PageSize=10;Matched=2},
        @{Label='etat Failed';Search='';State='Failed';Offset=0;PageSize=50;Matched=63}
    )){
        $integrated=Get-PestoInterventionQuery -Rows $rows -Search $scenario.Search -State $scenario.State -Offset $scenario.Offset -PageSize $scenario.PageSize
        $oracle=Get-PestoEngineQueryFullSort -Rows $rows -Search $scenario.Search -State $scenario.State -Offset $scenario.Offset -PageSize $scenario.PageSize
        Require ($integrated.TotalCount -eq $rows.Count) ('Total d instantane divergent ('+$scenario.Label+')')
        Require ($integrated.MatchedCount -eq $scenario.Matched -and $oracle.MatchedCount -eq $scenario.Matched) ('Compte de filtre divergent ('+$scenario.Label+') : integre '+$integrated.MatchedCount+', oracle '+$oracle.MatchedCount+', attendu '+$scenario.Matched)
        Require (((@($integrated.Items)|ForEach-Object{$_.RowId}) -join '|') -ceq ((@($oracle.Items)|ForEach-Object{$_.RowId}) -join '|')) ('Page divergente du tri complet existant ('+$scenario.Label+')')
    }
    $first=Get-PestoInterventionQuery -Rows $rows -Offset 0 -PageSize 2
    Require ((@($first.Items)|ForEach-Object{$_.RowId}) -join '|' -ceq 'q000248|q000249') 'Les ex-aequo de la page 1 ne rendent plus l ordre d entree : le tri pagine a perdu sa stabilite.'
}
Check-PestoCase 'La pagination recouvre le tri complet sans doublon ni omission' {
    $rows=New-PestoEngineQueryRows 250
    $oracle=Get-PestoEngineQueryFullSort -Rows $rows -Offset 0 -PageSize 250
    $walked=@();$offset=0
    while($offset -lt $oracle.MatchedCount){
        $page=Get-PestoInterventionQuery -Rows $rows -Offset $offset -PageSize 40
        Require ($page.Offset -eq $offset) ('Pagination deplacee hors de la page demandee a l offset '+$offset)
        $walked+=@($page.Items|ForEach-Object{$_.RowId});$offset+=40
    }
    Require ($walked.Count -eq $oracle.MatchedCount) ('Lignes perdues ou dupliquees par la pagination : '+$walked.Count+' contre '+$oracle.MatchedCount)
    Require (($walked|Select-Object -Unique).Count -eq $walked.Count) 'Doublon entre deux pages.'
    Require (($walked -join '|') -ceq ((@($oracle.Items)|ForEach-Object{$_.RowId}) -join '|')) 'Ordre recouvre divergent du tri complet existant'
    Require ($walked[-1] -ceq 'q000001' -and $walked[-2] -ceq 'q000000') 'Les dates inconnues ne ferment plus le tri dans l ordre d entree'
    $clamped=Get-PestoInterventionQuery -Rows $rows -Offset 250 -PageSize 40
    Require ($clamped.Offset -eq 240) ('Retour a la derniere page attendu a 240, obtenu '+$clamped.Offset)
    Require (((@($clamped.Items)|ForEach-Object{$_.RowId}) -join '|') -ceq (((@($oracle.Items[240..249]))|ForEach-Object{$_.RowId}) -join '|')) 'La derniere page rendue differe de la fin du tri complet'
}
Check-PestoCase 'Le registre reste branche sur la pagination Common.Query' {
    $text=[IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Interventions.ps1'))
    Require ($text.Contains("`$options.Offset=`$Offset")) 'La requete ne cablerait plus le decalage de page.'
    Require ($text.Contains("`$options.Limit=`$PageSize")) 'La requete ne cablerait plus la taille de page.'
    Require ($text.Contains("`$options.SortField='Updated'") -and $text.Contains("`$options.Descending=`$true")) 'Le tri pagine ne serait plus la date de mise a jour décroissante.'
    Require ($text.Contains('-Offset $ui.Offset -PageSize $ui.PageSize')) 'La page du registre ne passerait plus ni decalage ni taille de page a la requete.'
    Require ($text.Contains('-State $state -PageSize 5000')) 'L export ne relirait plus tout le filtre au-dela de la page affichee.'
}
Check-PestoCase 'Index compact C# charge par le parcours d inventaire' {
    $fixture=[pscustomobject[]]@(
        [pscustomobject]@{Name='P123456ABDEF001';DistinguishedName='CN=X1,OU=SiteA,OU=Org'},
        [pscustomobject]@{Name='P123456ABDEF002';DistinguishedName='CN=X2,OU=SiteA,OU=Org'},
        [pscustomobject]@{Name='hors convention';DistinguishedName='CN=Y,OU=SiteA,OU=Org'}
    )
    $r=& $module {
        param($c)
        $index=Get-PestoNameInventoryIndex $c
        [pscustomobject]@{Loaded=[bool]('Pesto.Inventory.CompactIndex' -as [type]);
            Compact=$index.ByBase -is [Collections.Generic.Dictionary[string,Collections.Generic.HashSet[int]]];
            Numbers=@($index.ByBase['P123456ABDEF']|Sort-Object) -join ',';Entries=$index.Entries.Count}
    } $fixture
    Require $r.Loaded 'Le type Pesto.Inventory.CompactIndex n est pas charge : le parcours d inventaire tournerait encore sur la seule table PowerShell.'
    Require $r.Compact 'Le parcours d inventaire ne rend pas l index compact C# : la structure livree aurait change de nature sans que la suite le voie.'
    Require ($r.Numbers -ceq '1,2') ('Les numeros de la base ne sont pas indexes : ['+$r.Numbers+']')
    Require ($r.Entries -eq 2) 'Les noms hors convention ne seraient pas filtres par le parcours d inventaire.'
}
Check-PestoCase 'Index compact et table PowerShell rendent le meme index' {
    $names=@('P123456ABDEF001','P123456ABDEF002','p123456abdef002','P123456ABDEF000','P123456ABDEG010','S654321XYZZ999',
        'V111111QQQAB123','hors convention','P123456ABDE','P123456ABDEF00A',[string]::new([char]0xE9,15),'P123456ABDEF001',
        '  P123456ABDEF007  ','',$null)
    $r=& $module {
        param($list)
        $make={param($names)[pscustomobject[]]@($names|ForEach-Object{[pscustomobject]@{Name=[string]$_;DistinguishedName=('CN='+[string]$_+',OU=Site')}})}
        $compact=Get-PestoNameInventoryIndexCompact (& $make $list)
        $table=Get-PestoNameInventoryIndexTable (& $make $list)
        if($null -eq $compact){throw 'Le chemin compact ne rend rien : type absent ou compilation en echec.'}
        $issues=[Collections.Generic.List[string]]::new()
        if($compact.ByBase.Count -ne $table.ByBase.Count){$issues.Add('compte de bases '+$compact.ByBase.Count+' contre '+$table.ByBase.Count)}
        foreach($base in $table.ByBase.Keys){
            if(-not $compact.ByBase.ContainsKey($base)){$issues.Add('base absente '+$base);continue}
            $a=@($compact.ByBase[$base]|Sort-Object) -join ',';$b=@($table.ByBase[$base]|Sort-Object) -join ','
            if($a -cne $b){$issues.Add('numeros divergents pour '+$base+' ['+$a+'] contre ['+$b+']')}
        }
        if($compact.BySite.Count -ne $table.BySite.Count){$issues.Add('compte de sites '+$compact.BySite.Count+' contre '+$table.BySite.Count)}
        foreach($site in $table.BySite.Keys){
            if(-not $compact.BySite.ContainsKey($site)){$issues.Add('site absent '+$site);continue}
            $a=@($compact.BySite[$site]|Sort-Object) -join ',';$b=@($table.BySite[$site]|Sort-Object) -join ','
            if($a -cne $b){$issues.Add('services divergents pour '+$site+' ['+$a+'] contre ['+$b+']')}
        }
        if($compact.Entries.Count -ne $table.Entries.Count){$issues.Add('compte d entrees '+$compact.Entries.Count+' contre '+$table.Entries.Count)}
        else {
            for($i=0;$i -lt $table.Entries.Count;$i++){
                $p=$table.Entries[$i].Parts;$q=$compact.Entries[$i].Parts
                foreach($prop in @('Name','Type','Prefix','Site','Service','Number','NumberText','Base','Series','Label')){
                    if([string]$p.$prop -cne [string]$q.$prop){$issues.Add('entree '+$i+' champ '+$prop+' ['+$p.$prop+'] contre ['+$q.$prop+']')}
                }
                if([string]$table.Entries[$i].Computer.Name -cne [string]$compact.Entries[$i].Computer.Name){$issues.Add('entree '+$i+' ordinateur different')}
            }
        }
        ,@($issues)
    } $names
    Require ($r.Count -eq 0) ('Index compact et table livres non equivalents : '+($r -join ' ; '))
}
Check-PestoCase 'Get-AvailableMachines rendu par l index compact du parcours inventaire' {
    $fixture=[pscustomobject[]]@('P123456ABDEF001','P123456ABDEF002','P123456ABDEF004','hors convention'|ForEach-Object{[pscustomobject]@{Name=$_}})
    $returned=& $module {param($c) Get-AvailableMachines -computers $c -baseName 'P123456' -site 'AB' -equipe 'DEF'} $fixture
    $available=@($returned)
    Require ($available.Count -eq 996) ('996 noms disponibles attendus, obtenu '+$available.Count)
    Require ('P123456ABDEF003' -in $available) 'Le numero libre 003 ne serait pas rendu disponible.'
    Require ('P123456ABDEF001' -notin $available) 'Un nom deja pose dans l inventaire serait rendu disponible.'
    Require ('P123456ABDEF004' -notin $available) 'Le dernier nom pose serait rendu disponible.'
}
Check-PestoCase 'Get-PestoSiteServiceCodes rendu par l index compact du parcours inventaire' {
    $fixture=[pscustomobject[]]@(
        [pscustomobject]@{Name='P123456ABDEF001';DistinguishedName='CN=X1,OU=SiteAlpha,OU=Org,DC=example,DC=test'},
        [pscustomobject]@{Name='P123456ABDEG002';DistinguishedName='CN=X2,OU=SiteAlpha,OU=Org,DC=example,DC=test'},
        [pscustomobject]@{Name='P123456XYDEF003';DistinguishedName='CN=X3,OU=SiteBeta,OU=Org,DC=example,DC=test'})
    $codes=& $module {
        param($c)
        $savedPrefixe=$script:PREFIXE
        try{$script:PREFIXE='123456';return ,@(Get-PestoSiteServiceCodes -OrganismeOU 'OU=Org,DC=example,DC=test' -Site 'SiteAlpha' -Computers $c)}
        finally{$script:PREFIXE=$savedPrefixe}
    } $fixture
    Require ((@($codes) -join ',') -ceq 'DEF,DEG') ('Codes service du site attendus DEF,DEG, obtenu ['+(@($codes) -join ',')+'] : la liste Entries de l index ne serait plus lue.')
}
Check-PestoCase 'Surface livree : le parcours inventaire atteint l index compact' {
    $text=[IO.File]::ReadAllText((Join-Path $root 'wad/Pesto-Directory.ps1'))
    Require ($text.Contains('function Get-PestoNameInventoryIndexTable')) 'Le repli PowerShell livre ne serait plus la.'
    Require ($text.Contains('Get-PestoNameInventoryIndexCompact $Computers')) 'Le parcours d inventaire n atteindrait plus l index compact.'
    Require ($text.Contains('Get-PestoNameInventoryIndexTable $Computers')) 'Le repli sur table ne serait plus branche.'
    Require ($text.Contains('Initialize-PestoRuntimeTypes')) 'Le type compact ne serait plus charge depuis la bibliotheque verifiee.'
    Require ($text.Contains('Pesto.Inventory.CompactIndex')) 'Le type compact livre serait absent du module.'
    $runtime=[IO.File]::ReadAllText((Join-Path $root 'wad/Pesto.Engine.Runtime.ps1'))
    Require ($runtime.Contains('Initialize-PestoRuntimeTypes')) 'Le module Engine genere ne chargerait plus la bibliotheque verifiee.'
    Require ($runtime.Contains('Get-PestoNameInventoryIndexCompact $Computers')) 'Le module Engine genere ne routerait plus l inventaire vers l index compact.'
    $suite=[IO.File]::ReadAllText($PSCommandPath)
    Require (-not($suite.Contains('namespace Pesto.'+'Inventory'))) 'La suite redefinirait le type compact chez elle au lieu d atteindre le produit.'
}

# Point 72 : admission et reprises des lectures transitoires bornees. Le moteur plafonne deja les
# lectures concurrentes (plafond d admission, creneaux interactif et fond issus de POLICY.MaxReaders,
# attente coupee a 30 secondes) et les reprises (tentatives et backoff bornes), mais rien de tout cela
# n etait executable hors fixture Windows : le plafond d admission et le partage des creneaux n
# etaient prouves que par Async-ScopeFixture.ps1, qui exige un DispatcherTimer WPF indisponible ici.
# Les morceaux d admission, de choix de creneau et de wrapper sont donc relus dans la source livree
# par analyse syntaxique puis rejoues tels quels, et les reprises sont lancees dans de vrais runspaces
# sur de vrais SemaphoreSlim : la suite repond du code livre, jamais d une copie.
function Get-PestoShippedFunctionText {
    param([string]$FileName,[string[]]$Names)
    $path=Join-Path (Join-Path $root 'wad') $FileName
    $tokens=$null;$parseErrors=$null
    $parsed=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    Require (-not $parseErrors.Count) ('Source livree invalide : '+$FileName)
    foreach($name in $Names){
        $found=$null
        foreach($statement in $parsed.EndBlock.Statements){if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -ceq $name){$found=$statement;break}}
        Require ($null -ne $found) ('Definition livree absente : '+$FileName+' :: '+$name)
        $found.Extent.Text
    }
}
$asyncTokens=$null;$asyncErrors=$null
$asyncAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wad/Pesto-Async.ps1'),[ref]$asyncTokens,[ref]$asyncErrors)
Require (-not $asyncErrors.Count) 'Source livree invalide : wad/Pesto-Async.ps1'
$asyncStart=$null
foreach($statement in $asyncAst.EndBlock.Statements){if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -ceq 'Start-PestoAsyncOperation'){$asyncStart=$statement;break}}
Require ($null -ne $asyncStart) 'Start-PestoAsyncOperation absente de la source livree.'
$asyncAdmission=$null;$asyncMutationBranch=$null
foreach($asyncIf in $asyncStart.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst]},$true)){
    $asyncText=$asyncIf.Extent.Text
    if($asyncText.StartsWith('if(-not $mutation)')){$asyncAdmission=$asyncText}
    if($asyncText.StartsWith('if($mutation)')){$asyncMutationBranch=$(if($asyncIf.ElseClause){$asyncText.Substring(0,$asyncIf.ElseClause.Extent.StartOffset-$asyncIf.Extent.StartOffset)}else{$asyncText})}
}
$asyncGate=$null;$asyncWrapper=$null;$asyncMutationFlag=$null
foreach($asyncAssign in $asyncStart.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst]},$true)){
    if($asyncAssign.Left.Extent.Text -ceq '$gate'){$asyncGate=$asyncAssign.Right.Extent.Text}
    if($asyncAssign.Left.Extent.Text -ceq '$mutation'){$asyncMutationFlag=$asyncAssign.Right.Extent.Text}
    if($asyncAssign.Left.Extent.Text -ceq '$wrapper'){$asyncWrapperText=$asyncAssign.Right.Extent.Text.Trim();$asyncWrapper=[scriptblock]::Create($asyncWrapperText.Substring(1,$asyncWrapperText.Length-2))}
}
Require ($asyncAdmission -and $asyncGate -and $asyncWrapper -and $asyncMutationBranch -and $asyncMutationFlag) 'Pieces d admission livrees introuvables : plafond, derive du drapeau mutation, creneaux ou wrapper de lecture.'
$asyncRetryDefinitions=@(Get-PestoShippedFunctionText -FileName 'Pesto-Contracts.ps1' -Names @('Get-PestoReadFailure','Get-PestoNativeGuidance','Invoke-PestoReadRetry'))
$asyncRetryDefinitions+=@(Get-PestoShippedFunctionText -FileName 'Pesto-Safety.ps1' -Names @('Get-PestoNativeFailureCode'))
$asyncMutationTest=Get-PestoShippedFunctionText -FileName 'Pesto-Async.ps1' -Names @('Test-PestoAsyncMutationName')
Require ($asyncMutationTest.Contains('QueueAction')) 'La liste livree des mutations ne serait plus atteignable par la suite.'
Check-PestoCase 'ADMISSION douze lectures puis refus' {
    $r=& $module {param($Text)
        $script:CFG=$null;$script:PestoBackgroundGate=$null;$script:PestoInteractiveGate=$null
        $script:PestoAsyncTimerOperations=[hashtable]::Synchronized(@{});$script:AdmissionRefus=$null
        $onError={param($a);$script:AdmissionRefus=$a}
        $admitted=0;$refus=''
        foreach($n in 1..13){
            $script:AdmissionRefus=$null
            $mutation=$false;$Name=('Read'+$n);$CallbackContext=$null
            . ([scriptblock]::Create($Text))
            if($null -eq $script:AdmissionRefus){$admitted++;$script:PestoAsyncTimerOperations[$Name]=[pscustomobject]@{Name=$Name;Completed=$false}}
            else{$refus=[string]$script:AdmissionRefus.Exception.Message}
        }
        [pscustomobject]@{Admitted=$admitted;Message=$refus;Registered=$script:PestoAsyncTimerOperations.Count}
    } $asyncAdmission
    Require ($r.Admitted -eq 12) ('Douze lectures admises attendues, obtenu '+$r.Admitted)
    Require ($r.Registered -eq 12) ('Aucun worker supplementaire attendu au-dela du plafond : '+$r.Registered)
    Require ($r.Message -like 'Trop de lectures encore actives*') ('Message de refus livre attendu, obtenu ['+$r.Message+']')
}
Check-PestoCase 'ADMISSION mutation jamais refusee' {
    # Le drapeau mutation est derive par l affectation livree, pas declare par la suite : retirer un nom
    # de la liste des mutations doit couter un echec ici, sinon la protection des mutations serait
    # affichee par la suite au lieu d etre verifiee dans le code livre.
    foreach($name in @('QueueAction','DomainJoin','DirectAction','RecoveryAction','JoinADReserve','JoinADRelease','JoinADInspect')){
        $r=& $module {param($Admission,$Flag,$Name,$MutationTest)
            $script:CFG=$null;$script:PestoBackgroundGate=$null;$script:PestoInteractiveGate=$null
            $script:PestoAsyncTimerOperations=[hashtable]::Synchronized(@{});$script:AdmissionRefus=$null
            foreach($n in 1..12){$script:PestoAsyncTimerOperations[('Read'+$n)]=[pscustomobject]@{Name=('Read'+$n);Completed=$false}}
            $onError={param($a);$script:AdmissionRefus=$a}
            . ([scriptblock]::Create($MutationTest))
            $mutation=$false;$CallbackContext=$null
            . ([scriptblock]::Create('$mutation='+$Flag))
            $derived=$mutation
            . ([scriptblock]::Create($Admission))
            [pscustomobject]@{Refused=($null -ne $script:AdmissionRefus);Derived=$derived;Gated=(Test-PestoAsyncMutationName $Name)}
        } $asyncAdmission $asyncMutationFlag $name $asyncMutationTest
        Require $r.Derived ($name+' ne serait plus reconnu comme mutation par la derivation livree.')
        Require $r.Gated ($name+' ne serait plus reconnu comme mutation par le module charge.')
        Require (-not $r.Refused) ($name+' serait refusee par l admission des lectures.')
    }
    $read=& $module {param($Admission,$Flag,$Name,$MutationTest)
        $script:CFG=$null;$script:PestoBackgroundGate=$null;$script:PestoInteractiveGate=$null
        $script:PestoAsyncTimerOperations=[hashtable]::Synchronized(@{});$script:AdmissionRefus=$null
        foreach($n in 1..12){$script:PestoAsyncTimerOperations[('Read'+$n)]=[pscustomobject]@{Name=('Read'+$n);Completed=$false}}
        $onError={param($a);$script:AdmissionRefus=$a}
        . ([scriptblock]::Create($MutationTest))
        $mutation=$false;$CallbackContext=$null
        . ([scriptblock]::Create('$mutation='+$Flag))
        $derived=$mutation
        . ([scriptblock]::Create($Admission))
        [pscustomobject]@{Refused=($null -ne $script:AdmissionRefus);Derived=$derived;Registered=$script:PestoAsyncTimerOperations.Count}
    } $asyncAdmission $asyncMutationFlag 'NamesProjection' $asyncMutationTest
    Require (-not $read.Derived) 'Une lecture ordinaire serait derivee comme mutation par la derivation livree.'
    Require $read.Refused 'La treizieme lecture ne serait pas refusee par le plafond livre.'
    Require ($read.Registered -eq 12) ('La lecture refusee a quand meme ete enregistree : '+$read.Registered+' workers en service.')
}
Check-PestoCase 'ADMISSION repartition des creneaux selon MaxReaders' {
    foreach($plan in @(@{Max=4;Background=3;Shared=$false},@{Max=1;Background=1;Shared=$true},@{Max=8;Background=7;Shared=$false})){
        $r=& $module {param($Text,$MaxReaders)
            $script:CFG=[pscustomobject]@{POLICY=[pscustomobject]@{Schema=1;MaxReaders=$MaxReaders}}
            $script:PestoBackgroundGate=$null;$script:PestoInteractiveGate=$null
            $script:PestoAsyncTimerOperations=[hashtable]::Synchronized(@{});$script:AdmissionRefus=$null
            $mutation=$false;$Name='Probe';$CallbackContext=$null
            . ([scriptblock]::Create($Text))
            [pscustomobject]@{Background=$script:PestoBackgroundGate.CurrentCount;Interactive=$script:PestoInteractiveGate.CurrentCount;Shared=[object]::ReferenceEquals($script:PestoBackgroundGate,$script:PestoInteractiveGate)}
        } $asyncAdmission $plan.Max
        Require ($r.Background -eq $plan.Background) ('MaxReaders='+$plan.Max+' : '+$plan.Background+' creneaux de fond attendus, obtenu '+$r.Background)
        Require ($r.Interactive -eq 1) ('MaxReaders='+$plan.Max+' : un creneau interactif attendu, obtenu '+$r.Interactive)
        Require ($r.Shared -eq $plan.Shared) ('MaxReaders='+$plan.Max+' : partage du creneau interactif attendu a '+$plan.Shared+', obtenu '+$r.Shared)
    }
}
Check-PestoCase 'ADMISSION classification interactive et fond' {
    foreach($probe in @(@{Name='PCProbe';Kind='Interactive'},@{Name='JoinStatus';Kind='Interactive'},@{Name='NamesProjection';Kind='Background'},@{Name='DirectoryRefresh';Kind='Background'})){
        $kind=& $module {param($Text,$Name)
            $script:PestoInteractiveGate=[Threading.SemaphoreSlim]::new(1,1)
            $script:PestoBackgroundGate=[Threading.SemaphoreSlim]::new(3,3)
            $Name=$Name
            . ([scriptblock]::Create('$gate='+$Text))
            if([object]::ReferenceEquals($gate,$script:PestoInteractiveGate)){'Interactive'}elseif([object]::ReferenceEquals($gate,$script:PestoBackgroundGate)){'Background'}else{'Unknown'}
        } $asyncGate $probe.Name
        Require ($kind -ceq $probe.Kind) ($probe.Name+' serait classe '+$kind+' au lieu de '+$probe.Kind+'.')
    }
}
Check-PestoCase 'SURCHARGE concurrence jamais au-dessus des creneaux' {
    $state=[hashtable]::Synchronized(@{InFlight=0;Peak=0;Runs=0})
    $gate=[Threading.SemaphoreSlim]::new(3,3)
    $source='param($S);[Threading.Monitor]::Enter($S.SyncRoot);try{$S.InFlight++;$S.Runs++;if($S.InFlight -gt $S.Peak){$S.Peak=$S.InFlight}}finally{[Threading.Monitor]::Exit($S.SyncRoot)};Start-Sleep -Milliseconds 60;[Threading.Monitor]::Enter($S.SyncRoot);try{$S.InFlight--}finally{[Threading.Monitor]::Exit($S.SyncRoot)};''lu'''
    $workers=@()
    foreach($n in 1..12){$ps=[PowerShell]::Create();$timing=[hashtable]::Synchronized(@{WaitMs=0L;WorkMs=0L;Phase='Starting'});[void]$ps.AddScript($asyncWrapper.ToString(),$true).AddArgument($source).AddArgument(@($state)).AddArgument($gate).AddArgument($timing);$workers+=@{PS=$ps;Handle=$ps.BeginInvoke();Timing=$timing}}
    $results=@(foreach($worker in $workers){$worker.PS.EndInvoke($worker.Handle)})
    foreach($worker in $workers){$worker.PS.Dispose()}
    Require (@($results|Where-Object{$_ -eq 'lu'}).Count -eq 12) 'Douze lectures attendues au travers du creneau.'
    Require ($state.Peak -le 3) ('La concurrence livree a depasse les creneaux : '+$state.Peak+' en cours pour 3.')
    Require ($gate.CurrentCount -eq 3) ('Un creneau est reste retenu apres la surcharge : '+$gate.CurrentCount+' libres sur 3.')
    Require (@($workers|Where-Object{$_.Timing.Phase -ne 'Ended'}).Count -eq 0) 'Le wrapper de lecture ne clot pas sa phase.'
}
Check-PestoCase 'SURCHARGE la reprise garde son creneau' {
    # La reprise dort a l interieur du creneau : le backoff est impute au lecteur qui detient le
    # creneau, pas au moteur. Sans ce cas, un glissement du sommeil hors du finally libererait le
    # creneau pendant la reprise et laisserait la surcharge passer sous couvert d une simple reprise.
    $gate=[Threading.SemaphoreSlim]::new(1,1)
    $retrySource=($asyncRetryDefinitions -join [Environment]::NewLine)+[Environment]::NewLine+'$s=@{N=0};$r=@(Invoke-PestoReadRetry -Attempts 3 -DelayMs 150 -Read {$s.N++;if($s.N -lt 3){throw [ComponentModel.Win32Exception]::new(1722)};''ok''});[string]$s.N+''|''+($r -join '''')'
    $first=[PowerShell]::Create();$second=[PowerShell]::Create()
    $t1=[hashtable]::Synchronized(@{WaitMs=0L;WorkMs=0L;Phase='Starting'});$t2=[hashtable]::Synchronized(@{WaitMs=0L;WorkMs=0L;Phase='Starting'})
    [void]$first.AddScript($asyncWrapper.ToString(),$true).AddArgument($retrySource).AddArgument(@($module)).AddArgument($gate).AddArgument($t1)
    [void]$second.AddScript($asyncWrapper.ToString(),$true).AddArgument('''seconde''').AddArgument(@()).AddArgument($gate).AddArgument($t2)
    $h1=$first.BeginInvoke()
    $handover=[Diagnostics.Stopwatch]::StartNew()
    while($t1.Phase -ne 'Running' -and $handover.Elapsed.TotalSeconds -lt 5){Start-Sleep -Milliseconds 5}
    Require ($t1.Phase -eq 'Running') 'Le premier lecteur n a pas obtenu le creneau de lecture.'
    $h2=$second.BeginInvoke()
    $r1=@($first.EndInvoke($h1));$r2=@($second.EndInvoke($h2))
    $first.Dispose();$second.Dispose()
    Require (((@($r2)|ForEach-Object{[string]$_}) -join '') -ceq 'seconde') 'La seconde lecture n a pas fini par passer.'
    Require ($gate.CurrentCount -eq 1) 'Le creneau rendu apres reprise attendu.'
    Require (((@($r1)|ForEach-Object{[string]$_}) -join '') -ceq '3|ok') ('Reprise attendue trois tentatives puis succes, obtenu ['+((@($r1)|ForEach-Object{[string]$_}) -join '')+']')
    Require ($t2.WaitMs -ge 400) ('Le retard de reprise n est pas impute au creneau : seconde attente '+$t2.WaitMs+' ms pour 450 ms de backoff.')
}
Check-PestoCase 'REPRISE backoff exponentiel et tentatives bornees' {
    $r=& $module {
        $state=@{Count=0};$clock=[Diagnostics.Stopwatch]::StartNew()
        $failed=$false
        try{[void](Invoke-PestoReadRetry -Attempts 3 -DelayMs 150 -Read {$state.Count++;throw [ComponentModel.Win32Exception]::new(1722)})}catch{$failed=$true}
        $clock.Stop();[pscustomobject]@{Count=$state.Count;Milliseconds=$clock.Elapsed.TotalMilliseconds;Failed=$failed}
    }
    Require ($r.Count -eq 3) ('Trois tentatives attendues, obtenu '+$r.Count)
    Require $r.Failed 'L echec persistant doit rester un echec.'
    Require ($r.Milliseconds -ge 400) ('Le backoff ne doublerait pas entre les tentatives : '+[int]$r.Milliseconds+' ms pour 150+300 attendus.')
    Require ($r.Milliseconds -lt 1200) ('Le backoff s envole au-dela de la borne livree : '+[int]$r.Milliseconds+' ms.')
    $retryText=[string](($asyncRetryDefinitions|Where-Object{$_ -match 'Invoke-PestoReadRetry'}))
    Require ($retryText -match 'ValidateRange\(1,3\)') 'Le nombre de tentatives ne serait plus borne a trois.'
    Require ($retryText -match 'ValidateRange\(0,2000\)') 'Le delai de reprise ne serait plus borne a deux secondes.'
    Require ($retryText.Contains('[Math]::Min(4000,')) 'Le plafond de sommeil par reprise ne serait plus borne a 4000 ms.'
    Require ($retryText.Contains('Pow(2,')) 'La reprise ne doublerait plus son delai a chaque tentative.'
}
Check-PestoCase 'MUTATION jamais repetee automatiquement' {
    Require (-not (Get-PestoEngineInfo).AutomaticMutationRetry) 'Le module annoncerait une repetition automatique des mutations.'
    Require (-not $asyncMutationBranch.Contains('$wrapper')) 'La branche mutation brancherait le creneau de lecture.'
    Require ($asyncMutationBranch.Contains('AddScript($ScriptBlock.ToString(),$true)')) 'La branche mutation ne lancerait plus son worker propre.'
    $sites=@()
    foreach($file in @(Get-ChildItem (Join-Path $root 'wad') -Filter '*.ps1'|Where-Object{$_.Name -ne 'Pesto.Engine.Runtime.ps1'})){
        $tokens=$null;$errors=$null
        $parsed=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Require (-not $errors.Count) ('Source livree invalide : '+$file.Name)
        foreach($command in $parsed.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)){
            if($command.GetCommandName() -ceq 'Invoke-PestoReadRetry'){
                $owner=$command;while($owner -and -not($owner -is [Management.Automation.Language.FunctionDefinitionAst])){$owner=$owner.Parent}
                $sites+=[pscustomobject]@{File=$file.Name;Function=$(if($owner){$owner.Name}else{'<hors fonction>'});Statement=$command.Extent.Text}
            }
        }
    }
    Require ($sites.Count -ge 1) 'Aucun appel livre de reprise de lecture : le chemin ne serait plus branche.'
    foreach($site in $sites){
        Require ($site.Function -cmatch '^(Get|Find|Read|Test)-') ('La reprise livre atteindrait '+$site.Function+' dans '+$site.File+', hors fonction de lecture.')
        Require ($site.Statement.Contains('Get-ADComputer')) ('La reprise livre n entourerait plus une lecture AD : '+$site.File+' :: '+$site.Statement)
    }
}

# --- Pool de lectures (point 56) : le pool doit etre emprunte par le chemin livre, pas seulement disponible.
# Les primitives etaient testees seules par Run-ReadPool56Tests.ps1. Rejouees dans un worktree, trois atteintes
# au branchement laissaient toutes les suites vertes : retirer l emprunt du pool par la lecture, y faire passer
# une mutation, ne jamais rendre le lease. Les morceaux ci-dessous sont donc relus dans la source livree par
# analyse syntaxique, puis rejoues tels quels sur de vrais runspaces et un vrai pool, sans copie locale.
$asyncPoolBranch=$null
$asyncStartReleaseText=$null
$asyncPoolPrefix='if(-not $mutation -and $ApartmentState -eq ''MTA'')'
foreach($asyncPoolNode in $asyncStart.FindAll({param($n)$n -is [Management.Automation.Language.IfStatementAst]},$true)){
    $asyncPoolNodeText=$asyncPoolNode.Extent.Text
    if(-not $asyncPoolBranch -and $asyncPoolNodeText.StartsWith($asyncPoolPrefix)){$asyncPoolBranch=$asyncPoolNodeText}
    if(-not $asyncStartReleaseText -and $asyncPoolNodeText.StartsWith('if($readLease){Exit-PestoReadRunspace')){$asyncStartReleaseText=$asyncPoolNodeText}
}
Require ($asyncPoolBranch) 'Le chemin livre n emprunterait plus le pool de lectures : chaque lecture creerait son propre runspace.'
Require ($asyncStartReleaseText) 'Le lease de lecture ne serait plus rendu quand le demarrage echoue : un runspace resterait retenu.'
$asyncTick=$null
foreach($statement in $asyncAst.EndBlock.Statements){if($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -ceq 'Invoke-PestoAsyncTimerTick'){$asyncTick=$statement;break}}
Require ($null -ne $asyncTick) 'Invoke-PestoAsyncTimerTick absente de la source livree.'
$asyncReleaseText=$null
foreach($asyncTry in $asyncTick.FindAll({param($n)$n -is [Management.Automation.Language.TryStatementAst]},$true)){
    if($asyncTry.Finally){
        $asyncFinallyText=$asyncTry.Finally.Extent.Text
        if($asyncFinallyText.Contains('Exit-PestoReadRunspace $op.ReadLease')){$asyncReleaseText=$asyncFinallyText.Substring(1,$asyncFinallyText.Length-2);break}
    }
}
Require ($asyncReleaseText) 'Le lease de lecture n est plus rendu dans le finally de fin d operation : un runspace resterait retenu apres chaque lecture.'
Check-PestoCase 'POOL la lecture livree emprunte le pool' {
    $credential=[pscustomobject]@{Identity='EXAMPLE\lecteur'}
    $r=& $module {param($Branch,$Credential)
        $script:DOMAINE='example.test';$script:DC='dc.example.test';$script:cred=$null
        $script:PoolCalls=@();$script:Leases=0
        function Get-PestoSessionReadPool {param($Credential,[string]$Domain,[string]$DC);$script:PoolCalls+=[pscustomobject]@{Credential=$Credential;Domain=$Domain;DC=$DC};[pscustomobject]@{Stub='pool'}}
        function Enter-PestoReadRunspace {param($Pool);$script:Leases++;[pscustomobject]@{Pool=$Pool;Slot=[pscustomobject]@{Runspace='creneau-emprunte'};Returned=$false}}
        $mutation=$false;$ApartmentState='MTA';$ArgumentList=@([pscustomobject]@{Credential=$Credential})
        $readLease=$null;$rs=$null
        . ([scriptblock]::Create($Branch))
        if($rs -is [System.Management.Automation.Runspaces.Runspace]){try{$rs.Dispose()}catch{}}
        [pscustomobject]@{Calls=@($script:PoolCalls);Leases=$script:Leases;Rs=$rs;Lease=$readLease}
    } $asyncPoolBranch $credential
    Require (@($r.Calls).Count -eq 1) ('La lecture ne consulterait le pool qu une seule fois : '+@($r.Calls).Count+' acces releves.')
    Require ([object]::ReferenceEquals($r.Calls[0].Credential,$credential)) 'Le credential porte par la demande ne serait pas transmis au pool : deux comptes partageraient les memes runspaces.'
    Require ($r.Calls[0].Domain -ceq 'example.test' -and $r.Calls[0].DC -ceq 'dc.example.test') ('Le domaine et le DC courants ne seraient pas transmis au pool : ['+$r.Calls[0].Domain+' / '+$r.Calls[0].DC+']')
    Require ($r.Leases -eq 1) 'La lecture n aurait emprunte aucun runspace au pool.'
    Require ($r.Rs -ceq 'creneau-emprunte') 'Le runspace de la lecture ne serait pas celui rendu par le pool.'
    Require ([object]::ReferenceEquals($r.Rs,$r.Lease.Slot.Runspace)) 'L operation garderait un runspace different de celui de son lease.'
}
Check-PestoCase 'POOL la mutation garde son runspace propre' {
    $r=& $module {param($Branch)
        $script:DOMAINE='example.test';$script:DC='dc.example.test';$script:cred=$null
        $script:PoolCalls=0;$script:Leases=0
        function Get-PestoSessionReadPool {param($Credential,[string]$Domain,[string]$DC);$script:PoolCalls++;[pscustomobject]@{Stub='pool'}}
        function Enter-PestoReadRunspace {param($Pool);$script:Leases++;[pscustomobject]@{Pool=$Pool;Slot=[pscustomobject]@{Runspace=$null};Returned=$false}}
        $mutation=$true;$ApartmentState='MTA';$ArgumentList=@()
        $readLease=$null;$rs=$null
        . ([scriptblock]::Create($Branch))
        $state=if($rs -is [System.Management.Automation.Runspaces.Runspace]){$rs.RunspaceStateInfo.State.ToString()}else{'<aucun>'}
        if($rs -is [System.Management.Automation.Runspaces.Runspace]){try{$rs.Dispose()}catch{}}
        [pscustomobject]@{Calls=$script:PoolCalls;Leases=$script:Leases;Lease=$readLease;State=$state}
    } $asyncPoolBranch
    Require ($r.Calls -eq 0 -and $r.Leases -eq 0) ('Une mutation emprunterait le pool de lectures : '+$r.Calls+' acces au pool, '+$r.Leases+' lease.')
    Require ($null -eq $r.Lease) 'Une mutation garderait un lease de lecture.'
    Require ($r.State -eq 'Opened') ('La mutation ne creerait plus son propre runspace ouvert : '+$r.State)
}
Check-PestoCase 'POOL le lease est rendu a chaque issue' {
    $r=& $module {param($Release)
        $script:PestoAsyncTimerOperations=[hashtable]::Synchronized(@{});$script:PestoAsyncOperations=[hashtable]::Synchronized(@{})
        $pool=New-PestoReadRunspacePool -Maximum 2
        try{
            $clean=Enter-PestoReadRunspace $pool
            $op=[pscustomobject]@{ReadLease=$clean;Runspace=$clean.Slot.Runspace;PowerShell=$null;Timer=$null;Name='Read56';Cancelled=$false;TimeoutReported=$false}
            $caught=$null
            . ([scriptblock]::Create($Release))
            $returnedIdle=$pool.Idle.Count;$returnedCount=$pool.Count
            $next=Enter-PestoReadRunspace $pool
            $reused=[object]::ReferenceEquals($next.Slot.Runspace,$clean.Slot.Runspace)
            Exit-PestoReadRunspace $next
            $faulted=Enter-PestoReadRunspace $pool
            $op=[pscustomobject]@{ReadLease=$faulted;Runspace=$faulted.Slot.Runspace;PowerShell=$null;Timer=$null;Name='Read56Erreur';Cancelled=$false;TimeoutReported=$false}
            $caught=[Exception]::new('Lecture interrompue')
            . ([scriptblock]::Create($Release))
            [pscustomobject]@{ReturnedIdle=$returnedIdle;ReturnedCount=$returnedCount;Reused=$reused;FaultedIdle=$pool.Idle.Count;FaultedCount=$pool.Count}
        }finally{Close-PestoReadRunspacePool $pool}
    } $asyncReleaseText
    Require ($r.ReturnedIdle -eq 1 -and $r.ReturnedCount -eq 1) ('La lecture terminee ne rend pas son runspace au pool : '+$r.ReturnedIdle+' creneau libre, pool a '+$r.ReturnedCount+'.')
    Require $r.Reused 'Le runspace rendu n est pas remis a la lecture suivante.'
    Require ($r.FaultedIdle -eq 0 -and $r.FaultedCount -eq 0) ('Le runspace d une lecture en erreur reviendrait au pool : '+$r.FaultedIdle+' creneau libre, pool a '+$r.FaultedCount+'.')
}
Check-PestoCase 'POOL un demarrage en echec ne retient aucun runspace' {
    $r=& $module {param($Release)
        $pool=New-PestoReadRunspacePool -Maximum 1
        try{
            $readLease=Enter-PestoReadRunspace $pool;$rs=$readLease.Slot.Runspace
            . ([scriptblock]::Create($Release))
            [pscustomobject]@{Count=$pool.Count;Idle=$pool.Idle.Count;State=$rs.RunspaceStateInfo.State.ToString()}
        }finally{Close-PestoReadRunspacePool $pool}
    } $asyncStartReleaseText
    Require ($r.Count -eq 0 -and $r.Idle -eq 0) ('Un demarrage en echec retiendrait un runspace : pool a '+$r.Count+', '+$r.Idle+' creneau libre.')
    Require ($r.State -ne 'Opened') ('Le runspace d un demarrage en echec resterait ouvert : '+$r.State)
}
Check-PestoCase 'POOL sature la lecture est refusee sans runspace de repli' {
    $r=& $module {param($Branch)
        $script:DOMAINE='example.test';$script:DC='dc.example.test';$script:cred=$null
        function Get-PestoSessionReadPool {param($Credential,[string]$Domain,[string]$DC);[pscustomobject]@{Stub='pool'}}
        function Enter-PestoReadRunspace {param($Pool);throw 'Pool de lectures sature.'}
        $mutation=$false;$ApartmentState='MTA';$ArgumentList=@()
        $readLease=$null;$rs=$null;$failure=$null
        try{. ([scriptblock]::Create($Branch))}catch{$failure=$_}
        [pscustomobject]@{Failure=[string]$failure.Exception.Message;Lease=$readLease;Rs=$rs}
    } $asyncPoolBranch
    Require ($r.Failure -like 'Pool de lectures sature*') ('La saturation du pool ne remonterait plus au demandeur : ['+$r.Failure+']')
    Require ($null -eq $r.Lease -and $null -eq $r.Rs) 'La lecture refuserait le pool puis creerait quand meme un runspace hors pool.'
}

$report=[pscustomobject]@{Schema=1;Suite='Engine120';Platform=[Environment]::OSVersion.Platform.ToString();PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=([Environment]::OSVersion.Platform -eq 'Win32NT');ADExecuted=$false;MutationExecuted=$false;Passed=@($cases|Where-Object Passed).Count;Failed=@($cases|Where-Object{-not $_.Passed}).Count;Skipped=0;Generative=[pscustomobject]$generative;RuntimeSHA256=(Get-FileHash (Join-Path $root 'wad/Pesto.Engine.Runtime.ps1') -Algorithm SHA256).Hash.ToLowerInvariant();CommonCoreSHA256=(Get-FileHash (Join-Path $root 'wad/M4D.Admin.Common.Core.dll') -Algorithm SHA256).Hash.ToLowerInvariant();TestSHA256=(Get-FileHash $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant();Checks=$cases.ToArray()}
if($OutputPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))}
$report|Select-Object Suite,Passed,Failed,Skipped
$cases|Where-Object{-not $_.Passed}|Format-List
if($report.Failed){exit 1}

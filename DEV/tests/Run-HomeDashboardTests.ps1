#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
# Modèle et vrais callbacks de l'accueil, I/O remplacées : aucun WPF, AD, CIM ou registre réel.
$ErrorActionPreference='Stop';Set-StrictMode -Off
$root=Split-Path $PSScriptRoot -Parent;$defs=@{};$results=[Collections.Generic.List[object]]::new()
foreach($file in @('Pesto-SuiteUI.ps1','Pesto-Interventions.ps1','Pesto-Contracts.ps1','Pesto-Policy.ps1','Pesto-Catalogue.ps1','Pesto-EngineContracts.ps1','Pesto-Directory.ps1','Pesto-Safety.ps1')){
 $tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root ('wad/'+$file)),[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count){throw ($parseErrors.Message -join '; ')}
 foreach($node in $ast.EndBlock.Statements){if($node -is [Management.Automation.Language.FunctionDefinitionAst]){$defs[$node.Name]=$node.Extent.Text}}
}
foreach($name in @('New-PestoReadCoordinator','New-PestoInterventionCatalogCache','Test-PestoOptionalPostCheckReceipt','Test-PestoAcknowledgedReceipt','Get-PestoHomeReceiptSummary','Get-PestoHomeDashboard','ConvertTo-PestoInterventionRow','Get-PestoStatePresentation','Get-PestoStageLabel','Get-PestoEffectLabel','Get-PestoHomeLocalSnapshot','Complete-PestoHomeRead','Fail-PestoHomeRead','Update-PestoHomeInterventions','Invoke-PestoSuitePulse','Get-PestoModeChip','Get-PestoBlockState','Get-PestoDataAgeText','Get-PestoSiteReadLabel','Get-PestoOperationStages','Get-PestoInterventionRoot','Test-PestoGlobalSafetyBarrier','Update-PestoStatusHeader')){if(-not $defs.ContainsKey($name)){throw ('Fonction absente : '+$name)};. ([scriptblock]::Create($defs[$name]))}
function Assert-Home {param($Condition,[string]$Message='Assertion accueil non satisfaite.');if(-not $Condition){throw $Message}}
function Equal-Home {param($Actual,$Expected);if($Actual -ne $Expected){throw ('Attendu '+$Expected+', obtenu '+$Actual)}}
function Case-Home {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}}
function New-HomeLocal {[pscustomobject]@{Computer='PC-LOCAL';Domain='lab.test';PartOfDomain=$true;ConfiguredName='PC-LOCAL';PendingRename=$false;CollectedUtc='2026-10-12T12:00:00Z'}}
function New-HomeEntry {param([string]$Phase='Verified',[string]$Date='2026-10-12T12:00:00Z',[string]$Name='PC-LOCAL',[int]$Code=30)
 $id=[Guid]::NewGuid().ToString('N');[pscustomobject]@{Id=$id;Readable=$true;Issue='';FileName=$id+'.json';Receipt=[pscustomobject]@{OperationId=$id;Phase=$Phase;UpdatedUtc=$Date;Plan=[pscustomobject]@{Nom_du_PC=$Name;Nouveau_Nom=$Name+'-NEW'};LastStage='Rename: Confirmed';Entra='NotRequested';Protection='NotChanged';Rename='Confirmed';Move='NotRequested';ResultCode=$Code}}
}
function New-HomeCatalogue {param([object[]]$Entries=@(),[bool]$Truncated=$false)
 [pscustomobject]@{Entries=$Entries;Truncated=$Truncated;ValidCount=@($Entries|Where-Object{$_.Readable}).Count;InvalidCount=@($Entries|Where-Object{-not $_.Readable}).Count}
}
Case-Home 'Unobserved local computer is never replaced by a fabricated name or workgroup' {$m=Get-PestoHomeDashboard -InDomain $true;Assert-Home (-not $m.LocalKnown);Assert-Home ($m.Computer -match 'non lu' -and $m.Domain -match 'non lu');Assert-Home ($m.Domain -notmatch 'Groupe de travail')}
Case-Home 'Unread receipts differ from a successfully read empty catalogue' {$u=Get-PestoHomeDashboard;$e=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue);Assert-Home ($u.EmptyRecent -match 'non lus');Assert-Home ($e.EmptyRecent -match 'Aucune intervention enregistrée');Assert-Home (-not $u.AttentionText -and -not $e.AttentionText);Assert-Home (-not $u.ReceiptsKnown -and $null -eq $u.AttentionCount);Assert-Home $e.ReceiptsKnown;Equal-Home $e.AttentionCount 0}
Case-Home 'Observed domain name comes from Windows instead of application domain assumptions' {$local=New-HomeLocal;$m=Get-PestoHomeDashboard -Local $local -InDomain $false;Assert-Home $m.LocalKnown;Equal-Home $m.Computer 'PC-LOCAL';Equal-Home $m.Domain 'Domaine Windows : lab.test'}
Case-Home 'A known workgroup is shown only after a boolean Windows observation' {$local=New-HomeLocal;$local.PartOfDomain=$false;$local.Domain='WORKGROUP';$m=Get-PestoHomeDashboard -Local $local;Assert-Home $m.LocalKnown;Assert-Home ($m.Domain -match '^Groupe de travail : WORKGROUP$' -and $m.Location -match 'groupe de travail')}
Case-Home 'Malformed domain membership cannot become a workgroup assertion' {$local=New-HomeLocal;$local.PartOfDomain='false';$m=Get-PestoHomeDashboard -Local $local;Assert-Home (-not $m.LocalKnown)}
Case-Home 'A local read failure takes precedence over a stale successful snapshot' {$m=Get-PestoHomeDashboard -Local (New-HomeLocal) -LocalError 'Lecture locale échouée';Assert-Home (-not $m.LocalKnown);Assert-Home ($m.ReadIssue -match 'Lecture locale échouée')}
Case-Home 'Observation timestamp is displayed; an invalid timestamp is not replaced by now' {$local=New-HomeLocal;$m=Get-PestoHomeDashboard -Local $local;Assert-Home ($m.LocalRead -match '12/10/2026');$local.CollectedUtc='invalid';Assert-Home ((Get-PestoHomeDashboard -Local $local).LocalRead -match 'date inconnue')}
Case-Home 'Pending configured name is clearly distinct from active Windows name' {$local=New-HomeLocal;$local.ConfiguredName='PC-NEXT';$local.PendingRename=$true;$m=Get-PestoHomeDashboard -Local $local;Equal-Home $m.Computer 'PC-LOCAL';Assert-Home ($m.Activity -match 'PC-NEXT' -and $m.Activity -match 'redémarrage')}
Case-Home 'Unknown configured-name observation never announces a pending reboot' {$local=New-HomeLocal;$local.PendingRename=$null;$local.ConfiguredName='';Assert-Home (-not (Get-PestoHomeDashboard -Local $local).Activity)}
Case-Home 'Non-boolean pending rename or empty configured name cannot invent a restart requirement' {foreach($pending in @('true',$true)){$local=New-HomeLocal;$local.PendingRename=$pending;$local.ConfiguredName=$(if($pending -is [string]){'PC-NEXT'}else{''});Assert-Home (-not (Get-PestoHomeDashboard -Local $local).Activity)}}
Case-Home 'No active operation produces no empty activity card message' {Assert-Home (-not (Get-PestoHomeDashboard -Local (New-HomeLocal)).Activity)}
Case-Home 'Supplied active-operation text is retained without inventing progress' {$m=Get-PestoHomeDashboard -Local (New-HomeLocal) -Busy $true -Activity 'Contrôle en cours';Equal-Home $m.Activity 'Contrôle en cours';Assert-Home (-not $m.CanPrepare)}
Case-Home 'Previously observed OU remains explicitly dated unknown when no linked stamp exists' {$m=Get-PestoHomeDashboard -Local (New-HomeLocal) -OU 'Postes / Lyon' -OUStamp '';Assert-Home ($m.Location -match 'déjà observé' -and $m.Location -match 'date inconnue' -and $m.Location -match 'ne l.actualise pas')}
Case-Home 'A failed receipt read cannot render an old catalogue as newly reliable' {$catalogue=New-HomeCatalogue @(New-HomeEntry);$m=Get-PestoHomeDashboard -Catalogue $catalogue -ReceiptsError 'Lecture des reçus échouée';Equal-Home @($m.Recent).Count 0;Assert-Home ($m.EmptyRecent -match 'indisponibles' -and $m.ReadIssue -match 'échouée')}
Case-Home 'Truncated receipt catalogue explicitly reports incomplete coverage' {$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue @(New-HomeEntry) $true);Assert-Home ($m.ReadIssue -match 'partiel' -and $m.ReadIssue -match 'pas exhaustifs')}
Case-Home 'Unreadable receipts remain actionable but are not listed as successful recent operations' {$bad=[pscustomobject]@{Id='invalid:broken';Readable=$false;Receipt=$null;FileName='broken.json';Issue='Reçu illisible'};$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue @($bad));Equal-Home $m.AttentionCount 1;Equal-Home @($m.Recent).Count 0;Assert-Home ($m.EmptyRecent -match 'Aucun reçu lisible' -and $m.AttentionText -match 'illisible')}
Case-Home 'Inconsistent pending, partial, uncertain and running states retain attention' {foreach($phase in @('PendingRestart','Partial','Uncertain','Running','MoveReady','Protection')){$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue @(New-HomeEntry $phase));Equal-Home $m.AttentionCount 1;Assert-Home $m.Recent[0].NextAction}}
Case-Home 'Completed command stays visible without a mandatory verification alert' {$entry=New-HomeEntry -Phase PendingRestart -Code 20;$before=$entry.Receipt|ConvertTo-Json -Depth 8;$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue @($entry));Equal-Home $m.AttentionCount 0;Equal-Home @($m.Recent).Count 1;Assert-Home ($m.Recent[0].NextAction -match 'facultatif');Equal-Home ($entry.Receipt|ConvertTo-Json -Depth 8) $before}
Case-Home 'Optional follow-up does not hide an uncertain intervention' {$entries=@((New-HomeEntry -Phase PendingRestart -Code 20),(New-HomeEntry -Phase Uncertain -Code 97));$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue $entries);Equal-Home $m.AttentionCount 1;Equal-Home @($m.Recent).Count 2;Assert-Home ($m.AttentionText -match 'incertain')}
Case-Home 'Verified, refused without uncertainty and not-started operations are not presented as running' {foreach($phase in @('Verified','Failed','NotStarted')){$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue @(New-HomeEntry $phase));Equal-Home $m.AttentionCount 0;Assert-Home (-not $m.AttentionText)}}
Case-Home 'Recent operations are the three newest readable receipts sorted by UTC' {$entries=@(for($n=1;$n -le 5;$n++){New-HomeEntry -Date ('2026-10-12T12:0'+$n+':00Z') -Name ('PC-'+$n)});$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue $entries);Equal-Home @($m.Recent).Count 3;Assert-Home ($m.Recent[0].Target -like 'PC-5*' -and $m.Recent[2].Target -like 'PC-3*')}
Case-Home 'Recent entries carry identity, readable state, date and next action' {$entry=New-HomeEntry 'Uncertain';$m=Get-PestoHomeDashboard -Catalogue (New-HomeCatalogue @($entry));Equal-Home $m.Recent[0].RowId $entry.Id;Assert-Home ($m.Recent[0].ResultLine -match 'incertain' -and $m.Recent[0].AccessibleText -match 'PC-LOCAL' -and $m.Recent[0].NextAction)}
Case-Home 'Demo and simulation cannot display real machine or receipt data' {foreach($mode in @('Demo','Simulation')){$options=@{Local=New-HomeLocal;Catalogue=New-HomeCatalogue @(New-HomeEntry)};$options[$mode]=$true;$m=Get-PestoHomeDashboard @options;Assert-Home (-not $m.LocalKnown);Equal-Home @($m.Recent).Count 0;Assert-Home ($m.EmptyRecent -match 'pas chargés') }}
Case-Home 'Out-of-domain and busy contexts cannot enable the two preparation shortcuts' {Assert-Home (-not (Get-PestoHomeDashboard -InDomain $false).CanPrepare);Assert-Home (-not (Get-PestoHomeDashboard -InDomain $true -Busy $true).CanPrepare);Assert-Home (Get-PestoHomeDashboard -InDomain $true).CanPrepare}

# Doubles strictement locaux des deux sources Windows et des reçus. Leur usage est compté.
function Get-CimInstance {param($ClassName,$OperationTimeoutSec,$ErrorAction);$script:HomeCimCalls++;$script:HomeCimTimeout=$OperationTimeoutSec;if($script:HomeCimFail){throw 'CIM indisponible'};return $script:HomeCimFixture}
function Get-ItemProperty {param($LiteralPath,$Name,$ErrorAction);$script:HomeRegistryCalls++;if($script:HomeRegistryFail){throw 'Registre indisponible'};[pscustomobject]@{ComputerName=$(if($LiteralPath -match 'ActiveComputerName'){'PC-LOCAL'}else{'PC-NEXT'})}}
function Get-PestoInterventionCatalogue {param($Cache);if($Cache -isnot [hashtable]){throw 'Cache partagé absent du worker.'};$script:HomeCatalogueCalls++;if($script:HomeCatalogueFail){throw 'Catalogue indisponible'};[pscustomobject]@{Entries=@();ValidCount=0;InvalidCount=0;Truncated=$false}}
function Update-PestoHomeDashboard {$script:HomeRenderCalls++}
function Get-PestoWorkerCoreSource {if($script:HomeSourceThrows){throw 'Source worker indisponible'};''}
function Test-PestoAsyncOperationRunning {param($Name);$script:HomeWorkerBusy}
function Start-PestoAsyncOperation {param($Name,$ScriptBlock,$ArgumentList,$TimeoutSec,$OnSuccess,$OnError);$script:HomeStartCalls++;$script:HomeWorkerScript=$ScriptBlock;$script:HomeWorkerArguments=$ArgumentList;$script:HomeWorkerSuccess=$OnSuccess;$script:HomeWorkerError=$OnError;if($script:HomeStartThrows){throw 'Worker non démarré'};return (-not $script:HomeStartRefused)}
function Reset-HomeRead {
 $script:HomeCimCalls=0;$script:HomeRegistryCalls=0;$script:HomeCatalogueCalls=0;$script:HomeRenderCalls=0;$script:HomeStartCalls=0
 $script:HomeCimFail=$false;$script:HomeRegistryFail=$false;$script:HomeCatalogueFail=$false;$script:HomeWorkerBusy=$false;$script:HomeStartRefused=$false;$script:HomeStartThrows=$false;$script:HomeSourceThrows=$false
 $script:HomeCimFixture=[pscustomobject]@{Name='PC-LOCAL';Domain='lab.test';PartOfDomain=$true}
 $script:HomeLocalSnapshot=$null;$script:HomeReceiptCatalogue=$null;$script:PestoReceiptCatalogCache=$null;$script:HomeLocalError='';$script:HomeReceiptsError='';$script:HomeReceiptsTick=0;$script:GUI=$false;$script:SIM=$false
}
Case-Home 'Local snapshot uses a bounded local CIM read and separates active/configured names' {Reset-HomeRead;$v=Get-PestoHomeLocalSnapshot;Equal-Home $script:HomeCimCalls 1;Equal-Home $script:HomeCimTimeout 15;Equal-Home $script:HomeRegistryCalls 2;Equal-Home $v.Computer 'PC-LOCAL';Equal-Home $v.ConfiguredName 'PC-NEXT';Assert-Home $v.PendingRename;Assert-Home ($v.PartOfDomain -is [bool])}
Case-Home 'CIM failure throws instead of guessing workgroup state' {Reset-HomeRead;$script:HomeCimFail=$true;$caught=$false;try{Get-PestoHomeLocalSnapshot|Out-Null}catch{$caught=$true};Assert-Home $caught;Equal-Home $script:HomeRegistryCalls 0}
Case-Home 'Malformed CIM domain flag is refused' {Reset-HomeRead;$script:HomeCimFixture.PartOfDomain='false';$caught=$false;try{Get-PestoHomeLocalSnapshot|Out-Null}catch{$caught=$true};Assert-Home $caught}
Case-Home 'Missing registry name retains CIM name and unknown pending status' {Reset-HomeRead;$script:HomeRegistryFail=$true;$v=Get-PestoHomeLocalSnapshot;Equal-Home $v.Computer 'PC-LOCAL';Assert-Home ($null -eq $v.PendingRename);Equal-Home $v.ConfiguredName ''}
Case-Home 'Home worker includes local snapshot function and runs it only without cache' {Reset-HomeRead;Update-PestoHomeInterventions;Equal-Home $script:HomeStartCalls 1;Assert-Home ($script:HomeWorkerArguments[0] -match 'function Get-PestoHomeLocalSnapshot');$r=& $script:HomeWorkerScript @script:HomeWorkerArguments;Assert-Home $r.Local;Equal-Home $script:HomeCimCalls 1;Equal-Home $script:HomeCatalogueCalls 1}
Case-Home 'Revisiting home reuses the local snapshot and only reads receipts' {Reset-HomeRead;$script:HomeLocalSnapshot=New-HomeLocal;Update-PestoHomeInterventions;$r=& $script:HomeWorkerScript @script:HomeWorkerArguments;Equal-Home $script:HomeCimCalls 0;Equal-Home $script:HomeCatalogueCalls 1;Equal-Home $r.Local.Computer 'PC-LOCAL'}
Case-Home 'Local read failure does not hide an independently successful receipt read' {Reset-HomeRead;$script:HomeCimFail=$true;Update-PestoHomeInterventions;$r=& $script:HomeWorkerScript @script:HomeWorkerArguments;Assert-Home (-not $r.Local -and $r.LocalError -and $r.Catalogue -and -not $r.ReceiptsError)}
Case-Home 'Receipt read failure does not invent an empty valid catalogue' {Reset-HomeRead;$script:HomeCatalogueFail=$true;Update-PestoHomeInterventions;$r=& $script:HomeWorkerScript @script:HomeWorkerArguments;Assert-Home ($r.Local -and -not $r.Catalogue -and $r.ReceiptsError)}
Case-Home 'Busy worker, recent visit and demo do not start duplicate background reads' {foreach($state in @('busy','recent','demo','simulation')){Reset-HomeRead;switch($state){'busy'{$script:HomeWorkerBusy=$true};'recent'{$script:HomeReceiptsTick=[Diagnostics.Stopwatch]::GetTimestamp()};'demo'{$script:GUI=$true};'simulation'{$script:SIM=$true}};Update-PestoHomeInterventions;Equal-Home $script:HomeStartCalls 0;Equal-Home $script:HomeCimCalls 0}}
Case-Home 'Successful callback publishes independently known results and refreshes once' {Reset-HomeRead;$r=[pscustomobject]@{Local=New-HomeLocal;Catalogue=New-HomeCatalogue;LocalError='';ReceiptsError=''};Complete-PestoHomeRead $r $null;Assert-Home ([object]::ReferenceEquals($script:HomeLocalSnapshot,$r.Local));Assert-Home ($script:HomeReceiptsTick -gt 0);Equal-Home $script:HomeRenderCalls 1}
Case-Home 'Failed callback marks receipts unknown and keeps a dated prior local observation' {Reset-HomeRead;$script:HomeLocalSnapshot=New-HomeLocal;$script:HomeReceiptCatalogue=New-HomeCatalogue;Fail-PestoHomeRead $null $null;Assert-Home ($null -eq $script:HomeReceiptCatalogue -and $script:HomeReceiptsError);Assert-Home $script:HomeLocalSnapshot;Equal-Home $script:HomeRenderCalls 1}
Case-Home 'Refused asynchronous start visibly reports unread receipts and allows retry' {Reset-HomeRead;$script:HomeStartRefused=$true;Update-PestoHomeInterventions;Assert-Home $script:HomeReceiptsError;Equal-Home $script:HomeReceiptsTick 0}
Case-Home 'Throwing asynchronous start reports the error without a successful read timestamp' {Reset-HomeRead;$script:HomeStartThrows=$true;Update-PestoHomeInterventions;Assert-Home $script:HomeReceiptsError;Equal-Home $script:HomeReceiptsTick 0}
Case-Home 'Worker source failure is contained and reports unread data without starting a worker' {Reset-HomeRead;$script:HomeSourceThrows=$true;Update-PestoHomeInterventions;Assert-Home $script:HomeReceiptsError;Equal-Home $script:HomeStartCalls 0;Equal-Home $script:HomeReceiptsTick 0}
Case-Home 'Idle UI pulses never request AD, CIM or receipt reads' {
 Reset-HomeRead
 $script:SuiteReady=$true;$script:DirectBusy=$false;$script:JoinBusy=$false;$script:Running=$false
 $script:PestoLogDirty=$false;$script:LogForceRefresh=$false;$script:MutationUncertain=$false;$script:QueueOperationIds=@()
 $script:PestoReadOnly=$false;$script:CfgRestartRequired=$false;$script:JoinLocked=$false;$script:PestoPolicy=@{IncidentMode=$false};$script:DC='dc.lab.test'
 $script:SiteLookupKey='SITE';$script:SiteLookupInfo=@{SITE=[pscustomobject]@{CollectedUtc=[DateTimeOffset]::UtcNow.ToString('o');Complete=$true}}
 $script:SiteLookupState=@{SITE=[pscustomobject]@{State='Ready';Error=''}}
 $history=[Collections.Concurrent.ConcurrentQueue[object]]::new();$history.Enqueue([pscustomobject]@{Name='Lecture';Milliseconds=1000})
 $script:PestoDisplayedMonitor=[pscustomobject]@{WorkerId='header-fixture';StageHistory=$history;Stage=[pscustomobject]@{Name='Résultat';Started='fixture'};TimedOut=$false}
 $script:PestoStagesKey=$null
 # Only the window is a memory fixture. Header, labels and safety policy are real product helpers.
 $controls=@{}
 foreach($name in @('PestoModeChip','PestoDcChip','PestoBlockBanner','PestoServiceState','PestoOperationStages','PestoStageDetails')){
  $controls[$name]=[pscustomobject]@{Text='';ToolTip='';Visibility='Visible';ItemsSource=$null}
 }
 $Win=[pscustomobject]@{Controls=$controls};$Win|Add-Member ScriptMethod FindName {param($Name);return $this.Controls[$Name]}
 1..20|ForEach-Object{Invoke-PestoSuitePulse $null $null}
 Equal-Home $script:HomeStartCalls 0;Equal-Home $script:HomeCimCalls 0;Equal-Home $script:HomeRegistryCalls 0;Equal-Home $script:HomeCatalogueCalls 0
 Equal-Home $controls.PestoModeChip.Text 'RÉEL';Equal-Home $controls.PestoDcChip.Text 'DC : dc.lab.test'
 Equal-Home $controls.PestoBlockBanner.Visibility 'Collapsed';Assert-Home ($controls.PestoServiceState.Text -match 'Services lus')
 Equal-Home @($controls.PestoOperationStages.ItemsSource).Count 2
 Equal-Home $controls.PestoOperationStages.ItemsSource[1].State 'Surveillance terminée : consulter le résultat'
}
Case-Home 'Home rendering reads no directory, Windows or receipt source' {Assert-Home ($defs['Update-PestoHomeDashboard'] -notmatch '(?i)\b(Get-AD\w+|Get-CimInstance|Get-WmiObject|Get-ItemProperty|Get-PestoInterventionCatalogue|Update-PestoHomeInterventions|Refresh-Names)\b');Assert-Home ($defs['Update-PestoHomeDashboard'] -notmatch '\$script:OU_ACTUELLE');Assert-Home ($defs['Update-PestoHomeDashboard'] -notmatch '-OUStamp\s+\(?\[string\]\$script:InventoryUtc')}
[xml]$shell=Get-Content -LiteralPath (Join-Path $root 'wad/Pesto-Shell.xaml') -Raw -Encoding UTF8
function Home-Node {param($Name);$shell.SelectSingleNode('//*[@*[local-name()="Name"]="'+$Name+'"]')}
Case-Home 'Empty cache/queue counters are hidden and useful dashboard fields exist' {Equal-Home (Home-Node 'HomeCounts').Visibility 'Collapsed';foreach($name in @('HomeLocalComputer','HomeLocalDomain','HomeLocalRead','HomeLocalLocation','HomeActivityCard','HomeActivityText','HomeAttentionCard','HomeInterventionSummary','HomeReadIssue','HomeRecentList','HomeRecentEmpty')){Assert-Home (Home-Node $name) $name}}
Case-Home 'New home actions carry tooltip and assistive help' {foreach($name in @('HomeRefresh','HomeOpenReceipt','HomePrepare','HomeQueue','HomeJoin','HomeNames')){$n=Home-Node $name;Assert-Home $n;Assert-Home $n.GetAttribute('ToolTip') $name;Assert-Home $n.GetAttribute('AutomationProperties.HelpText') $name}}
Case-Home 'The four home action buttons share one aligned row in the expected order' {
 $panel=Home-Node 'HomeActions';Equal-Home $panel.LocalName 'UniformGrid';Equal-Home $panel.GetAttribute('Columns') '4'
 $buttons=@($panel.SelectNodes('./*[local-name()="Button"]'));Equal-Home $buttons.Count 4
 $expected=@('HomePrepare','HomeQueue','HomeJoin','HomeNames');$labels=@('Un seul poste','Plusieurs postes','Ajouter au domaine','Noms disponibles')
 for($index=0;$index -lt 4;$index++){
  Equal-Home $buttons[$index].GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') $expected[$index]
  Equal-Home $buttons[$index].GetAttribute('Content') $labels[$index]
 }
 Equal-Home @($shell.SelectNodes('//*[@*[local-name()="Name"]="HomeQueue"]')).Count 1
}
Case-Home 'Several computers has the same button geometry and style as the other home actions' {
 foreach($name in @('HomePrepare','HomeQueue','HomeJoin','HomeNames')){
  $node=Home-Node $name;Equal-Home $node.GetAttribute('MinHeight') '42';Equal-Home $node.GetAttribute('Margin') '0,0,10,10'
  Equal-Home $node.GetAttribute('Style') (Home-Node 'HomePrepare').GetAttribute('Style')
  Assert-Home ($node.GetAttribute('Style') -notmatch 'BtnGhost')
  Equal-Home $node.GetAttribute('ToolTipService.ShowOnDisabled') 'True'
 }
}
# Rendu réel avec contrôles mémoire : aucune lecture Windows ni WPF, affectations comptées.
Case-Home 'Identical receipt catalogue renders once and preserves ItemsSource and selection' {
 . ([scriptblock]::Create($defs['Update-PestoHomeDashboard']))
 $script:HomeOriginalConvert=${function:ConvertTo-PestoInterventionRow}
 function ConvertTo-PestoInterventionRow {param($Entry);$script:HomeRowConversions++;& $script:HomeOriginalConvert $Entry}
 function Get-PestoCachedComputerProbe {param($Name,$Local);return $null}
 $script:HomeRowConversions=0
 $script:HomeControls=@{}
 $list=[pscustomobject]@{StoredItems=$null;AssignmentCount=0;SelectedItem=$null;SelectedIndex=-1;Items=@(1);Visibility='Collapsed'}
 $list|Add-Member ScriptProperty ItemsSource {return ,$this.StoredItems} {param($Value);$this.AssignmentCount++;$this.StoredItems=$Value}
 $script:HomeControls.HomeRecentList=$list
 foreach($name in @('HomeOpenReceipt','HomePrepare','HomeQueue','HomeRefresh')){$script:HomeControls[$name]=[pscustomobject]@{IsEnabled=$false}}
 $Win=[pscustomobject]@{};$Win|Add-Member ScriptMethod FindName {param($Name);return $script:HomeControls[$Name]}
 $script:HomeReceiptSummary=$null;$script:HomeReceiptSummaryCatalogue=$null;$script:HomeReceiptSummaryContext=''
 $script:HomeLocalSnapshot=New-HomeLocal;$script:HomeReceiptCatalogue=New-HomeCatalogue @(New-HomeEntry);$script:HomeLocalError='';$script:HomeReceiptsError='';$script:GUI=$false;$script:SIM=$false;$script:INDOMAIN=$true
 $script:DirectBusy=$false;$script:JoinBusy=$false;$script:Running=$false;$script:PreflightRunning=$false;$script:CfgRestartRequired=$false
 Update-PestoHomeDashboard
 Equal-Home $script:HomeRowConversions 1;Equal-Home $list.AssignmentCount 1
 $source=$list.ItemsSource;Equal-Home @($source).Count 1;$list.SelectedItem=$source[0];$selected=$list.SelectedItem
 Update-PestoHomeDashboard
 Equal-Home $script:HomeRowConversions 1;Equal-Home $list.AssignmentCount 1
 Assert-Home ([object]::ReferenceEquals($source,$list.ItemsSource));Assert-Home ([object]::ReferenceEquals($selected,$list.SelectedItem))
 # Un nouveau résultat worker refait la présentation et conserve l'identité sélectionnée.
 $script:HomeReceiptCatalogue=New-HomeCatalogue @($script:HomeReceiptCatalogue.Entries)
 Update-PestoHomeDashboard
 Equal-Home $script:HomeRowConversions 2;Equal-Home $list.AssignmentCount 2
 Equal-Home $list.SelectedItem.RowId $selected.RowId
 # L'erreur invalide la synthèse sans reconsommer le catalogue obsolète.
 $script:HomeReceiptsError='Lecture indisponible';Update-PestoHomeDashboard
 Equal-Home $script:HomeRowConversions 2;Equal-Home $list.AssignmentCount 3
 Assert-Home (-not $script:HomeReceiptSummary.ReceiptsKnown);Equal-Home @($list.ItemsSource).Count 0
}


Case-Home 'Real dashboard rendering disables both preparation buttons outside the domain in every mode' {
 . ([scriptblock]::Create($defs['Update-PestoHomeDashboard']))
 function Get-PestoCachedComputerProbe {param($Name,$Local);return $null}
 Reset-HomeRead
 $script:HomeControls=@{}
 foreach($name in @('HomePrepare','HomeQueue','HomeJoin','HomeNames')){$script:HomeControls[$name]=[pscustomobject]@{IsEnabled=$true}}
 $Win=[pscustomobject]@{};$Win|Add-Member ScriptMethod FindName {param($Name);return $script:HomeControls[$Name]}
 $script:HomeReceiptSummary=$null;$script:HomeReceiptSummaryCatalogue=$null;$script:HomeReceiptSummaryContext=''
 $script:CfgRestartRequired=$false;$script:PestoReadOnly=$false
 foreach($inDomain in @($false,$true)){foreach($simulation in @($false,$true)){foreach($demo in @($false,$true)){
  foreach($busy in @('None','DirectBusy','JoinBusy','Running','PreflightRunning')){
   $script:INDOMAIN=$inDomain;$script:SIM=$simulation;$script:GUI=$demo
   $script:DirectBusy=$false;$script:JoinBusy=$false;$script:Running=$false;$script:PreflightRunning=$false
   if($busy -ne 'None'){Set-Variable -Name $busy -Scope Script -Value $true}
   # Reset stale enabled state to prove every rendering reapplies the guard.
   $script:HomeControls.HomePrepare.IsEnabled=$true;$script:HomeControls.HomeQueue.IsEnabled=$true
   Update-PestoHomeDashboard
   foreach($name in @('HomePrepare','HomeQueue')){Equal-Home $script:HomeControls[$name].IsEnabled ($inDomain -and $busy -eq 'None')}
   Assert-Home $script:HomeControls.HomeJoin.IsEnabled;Assert-Home $script:HomeControls.HomeNames.IsEnabled
  }
 }}}
 Equal-Home $script:HomeCimCalls 0;Equal-Home $script:HomeRegistryCalls 0;Equal-Home $script:HomeCatalogueCalls 0
}

$failed=@($results|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{PowerShell=[string]$PSVersionTable.PSVersion;NoWpf=$true;NoAD=$true;NoRealCim=$true;NoRegistry=$true;Failed=$failed;Checks=$results.ToArray()}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 6
if($failed){exit 1}

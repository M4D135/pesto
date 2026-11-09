# Vue de jonction (WPF réel, 5.1) : registre partagé (noms des autres sautés, réservation après stabilité, nom suivant si
# détenu ailleurs), numéro au hasard, réservation dans l'AD (réserver, revérifier, confirmer ou annuler, nom pris entre-temps).
# Doubles : AD, workers et fenêtres modales. Les vraies fonctions sont extraites des fichiers livrés.
param([string]$Wad='C:\PestoTest\wad')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){ $script:R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''})) }
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e);if(@($e).Count){throw "Syntaxe $File : $($e[0].Message) @ $($e[0].Extent.StartLineNumber)"}
    $sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)};$sb.ToString()
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts','New-PestoComputerName','Assert-PestoClosedObject','Test-PestoPropertyPresent'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Operations.ps1' @('Test-PestoGeneratedComputerName','Test-PestoOUPath','Test-PestoDnsName','Test-PestoComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Directory.ps1' @('Split-PestoDistinguishedName','Get-PestoDomainFromDN'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Get-SiteTag','Get-AvailableMachines','Get-NameList','ConvertTo-PestoRdnValue'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Policy.ps1' @('ConvertTo-PestoPolicy'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Names.ps1' @('Get-PestoSharedNameSettings','Test-PestoNameReservedByOther','Get-PestoInitialNameIndex','Complete-PestoSharedNameOperation','Invoke-PestoSharedNameRefreshLists','Get-PestoSharedNameWanted','Invoke-PestoSharedNameTick','Update-PestoSharedNameStatus','Start-PestoSharedNameOperation'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Join.ps1' @('Set-PestoJoinMessage','Get-PestoJoinNameCandidates','Update-PestoJoinNames','New-PestoJoinPlanFromUI','Get-PestoJoinPlanKey','Get-PestoJoinPlanErrors','Test-PestoJoinNameTaken','Add-PestoTakenNames','Select-PestoJoinNextName','Request-PestoJoinAutoNextCheck','Invoke-PestoJoinAutoNextTick','Complete-PestoJoinCheck','Start-PestoJoinADReservation','Complete-PestoJoinADReservation','Stop-PestoJoinADReservation','Test-PestoJoinADReservationStale'))))
# Doubles
$script:Async=[Collections.Generic.List[object]]::new();$script:Starts=[Collections.Generic.List[string]]::new();$script:Confirm=$false;$script:Logs=[Collections.Generic.List[string]]::new()
function Start-PestoAsyncOperation {param($Name,$ScriptBlock,$ArgumentList,$OnSuccess,$OnError,[switch]$Replace,$TimeoutSec,$CallbackContext,$QueueMonitor,$ApartmentState) $script:Async.Add([pscustomobject]@{Name=$Name;Request=@($ArgumentList)[0];Context=$CallbackContext});$true}
function Test-PestoAsyncOperationRunning {param($Name) $false}
function Get-PestoADLoaderSource {'function Import-PestoADModule {}'}
function Start-PestoJoinCheck {param([switch]$ExecuteAfterCheck,[switch]$Auto) $script:Starts.Add([string]$ExecuteAfterCheck.IsPresent+':'+[string]$Auto.IsPresent+':'+[string]$script:JoinUI.Name.SelectedItem)}
function Update-PestoJoinUI {};function Set-PestoJoinBusy {param($b) $script:JoinBusy=[bool]$b}
function Add-LogLine {param($m,$k) $script:Logs.Add([string]$m)};function Write-Log {param($a,$b,$c,$d)}
function Confirm-YesNo {param($Msg,$Confirm) $script:LastConfirm=$Msg;$script:Confirm}
function Get-ComputersForNameGeneration {@($script:Inv|ForEach-Object{[pscustomobject]@{Name=$_}})}
function Update-NameList {};function Get-PestoJoinGuidance {param($m) ''};function Show-PestoJoinOutcome {};function Invalidate-PestoNameInventory {}
function Format-OUPath {param($ou) [string]$ou};function Test-PestoOUInConfiguredScope {param($ou) $true};function Test-PestoAuditWritable {$true}
$script:PREFIXE='123456';$script:PREPRODSITE='765';$script:RuntimeTags=$null;$script:GUI=$false;$script:SIM=$false;$script:INDOMAIN=$false;$script:PRD=$true
$script:DOMAINE='LAB.LOCAL';$script:DC='dc01.lab.local';$script:cred=$null;$script:AuthUser='LAB\tech';$script:Inv=@()
$script:OUV=@{Org='OU=Org,DC=lab,DC=local'};$script:OU=@{PREPROD='OU=Staging,DC=lab,DC=local'}
function Set-Policy($h){$p=[ordered]@{Schema=1};foreach($k in $h.Keys){$p[$k]=$h[$k]};$script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='PA'});POLICY=[pscustomobject]$p};$script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY}
Set-Policy @{CoordinationRoot='\\srv\partage\Pesto'}
$BasePath=$Wad
try { & {
    $reader=[Xml.XmlReader]::Create((Join-Path $Wad 'Pesto-Join.xaml'));try{$view=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $ui=@{};foreach($k in @{Type='JnType';Org='JnOrg';Site='JnSite';Service='JnService';Name='JnName';Existing='JnExisting';Status='JnStatus';Detail='JnDetail';Checks='JnChecks';Reference='JnReference'}.GetEnumerator()){$ui[$k.Key]=$view.FindName($k.Value)}
    $script:JoinUI=$ui;$script:JoinSuspend=$true
    [void]$ui.Type.Items.Add('Portable');$ui.Type.SelectedIndex=0;[void]$ui.Org.Items.Add('Org');$ui.Org.SelectedIndex=0;[void]$ui.Site.Items.Add('Paris');$ui.Site.SelectedIndex=0;$ui.Service.Text='INF'
    $script:JoinSuspend=$false;$script:JoinGeneration=1;$script:PestoTakenNames=$null;$script:JoinAutoNext=0
    # 1. Registre : nom proposé réservé après une seconde de stabilité.
    Update-PestoJoinNames
    Check 'Départ : 001 proposé' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF001') ([string]$ui.Name.SelectedItem)
    $script:SharedNameSnapshotUtc=[DateTime]::UtcNow
    Invoke-PestoSharedNameTick $null $null
    Check 'Registre : rien réservé au premier passage (stabilité)' (@($script:Async|Where-Object{$_.Request.Mode -eq 'Reserve'}).Count -eq 0)
    $script:SharedNameSeen['Join'].Utc=[DateTime]::UtcNow.AddSeconds(-2)
    Invoke-PestoSharedNameTick $null $null
    $res=@($script:Async|Where-Object{$_.Request.Mode -eq 'Reserve'})
    Check 'Registre : 001 réservé ensuite (chemin, domaine, poste, durée)' ($res.Count -eq 1 -and $res[0].Request.Name -eq 'P123456PAINF001' -and $res[0].Request.Root -eq '\\srv\partage\Pesto' -and $res[0].Request.Minutes -eq 15) ($res|ConvertTo-Json -Compress -Depth 3)
    # 2. Détenu par un autre poste : nom suivant proposé, puis réservé.
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='Held';Holder='POSTE-B · tech2';HolderExpiresUtc=[DateTime]::UtcNow.AddMinutes(10).ToString('o')}) -Context ([pscustomobject]@{Mode='Reserve';Name='P123456PAINF001';Context='Join'})
    Check 'Détenu ailleurs : 002 proposé' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF002' -and -not $ui.Name.Items.Contains('P123456PAINF001')) ([string]$ui.Name.SelectedItem)
    Check 'Détenu ailleurs : journal clair' (@($script:Logs|Where-Object{$_ -like '*P123456PAINF001 déjà réservé par POSTE-B*'}).Count -eq 1) ($script:Logs -join ' | ')
    Invoke-PestoSharedNameTick $null $null;$script:SharedNameSeen['Join'].Utc=[DateTime]::UtcNow.AddSeconds(-2);Invoke-PestoSharedNameTick $null $null
    $res=@($script:Async|Where-Object{$_.Request.Mode -eq 'Reserve'})
    Check '002 réservé à son tour' ($res[-1].Request.Name -eq 'P123456PAINF002') ($res[-1].Request.Name)
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='Reserved'}) -Context ([pscustomobject]@{Mode='Reserve';Name='P123456PAINF002';Context='Join'})
    Check 'Réservé : noté pour le parcours' ([string]$script:SharedNameMine['Join'].Name -eq 'P123456PAINF002')
    # 3. Relevé : les noms réservés par d'autres ne sont jamais proposés.
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='OK';Count=2;Others=@([pscustomobject]@{Name='P123456PAINF003';Station='POSTE-C';ExpiresUtc=[DateTime]::UtcNow.AddMinutes(5).ToString('o')},[pscustomobject]@{Name='P123456PAINF001';Station='POSTE-B';ExpiresUtc=[DateTime]::UtcNow.AddMinutes(5).ToString('o')})}) -Context ([pscustomobject]@{Mode='Snapshot'})
    Update-PestoJoinNames
    Check 'Relevé : 001 et 003 jamais proposés' (-not $ui.Name.Items.Contains('P123456PAINF001') -and -not $ui.Name.Items.Contains('P123456PAINF003') -and $ui.Name.Items.Contains('P123456PAINF004')) ((@($ui.Name.Items)|Select-Object -First 4) -join ',')
    # 4. Autre nom choisi : nouvelle réservation, l'ancienne est libérée une fois la nouvelle obtenue.
    $ui.Name.SelectedItem='P123456PAINF004';$n0=$script:Async.Count
    Invoke-PestoSharedNameTick $null $null;$script:SharedNameSeen['Join'].Utc=[DateTime]::UtcNow.AddSeconds(-2);Invoke-PestoSharedNameTick $null $null
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='Reserved'}) -Context ([pscustomobject]@{Mode='Reserve';Name='P123456PAINF004';Context='Join'})
    $rel=@($script:Async|Select-Object -Skip $n0|Where-Object{$_.Request.Mode -eq 'Release'})
    Check 'Changement de nom : 002 libéré après réservation de 004' ($rel.Count -eq 1 -and @($rel[0].Request.Names) -contains 'P123456PAINF002') ($rel|ConvertTo-Json -Compress -Depth 3)
    # 5. Simulation : relevé seulement, aucune réservation.
    $script:SIM=$true;$n0=$script:Async.Count;$ui.Name.SelectedItem='P123456PAINF005'
    Invoke-PestoSharedNameTick $null $null;$script:SharedNameSeen['Join']=[pscustomobject]@{Name='P123456PAINF005';Utc=[DateTime]::UtcNow.AddSeconds(-5)};Invoke-PestoSharedNameTick $null $null
    Check 'Simulation : aucune réservation écrite' (@($script:Async|Select-Object -Skip $n0|Where-Object{$_.Request.Mode -eq 'Reserve'}).Count -eq 0)
    $script:SIM=$false
    # 6. Sans dossier : rien.
    Set-Policy @{};$n0=$script:Async.Count;Invoke-PestoSharedNameTick $null $null
    Check 'Sans dossier partagé : aucune opération' ($script:Async.Count -eq $n0)
    # 7. Numéro au hasard parmi les 5 premiers libres.
    Set-Policy @{RandomNameChoice=5};$script:SharedNameOthers=@{};$seen=@{}
    foreach($i in 1..60){$script:JoinSuspend=$true;$ui.Name.SelectedIndex=-1;$script:JoinSuspend=$false;Update-PestoJoinNames;$seen[[string]$ui.Name.SelectedItem]=$true}
    $keys=@($seen.Keys|Sort-Object)
    Check 'Hasard (N=5) : seulement les 5 premiers libres, plusieurs tirés' ($keys.Count -ge 3 -and @($keys|Where-Object{$_ -notin @('P123456PAINF001','P123456PAINF002','P123456PAINF003','P123456PAINF004','P123456PAINF005')}).Count -eq 0) ($keys -join ',')
    Set-Policy @{RandomNameChoice=0};$script:JoinSuspend=$true;$ui.Name.SelectedIndex=-1;$script:JoinSuspend=$false;Update-PestoJoinNames
    Check 'Sans hasard : premier libre' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF001') ([string]$ui.Name.SelectedItem)
    # 7b. Registre : « détenu ailleurs » reçu pendant le contrôle (départs simultanés) -> nom suivant revérifié, AVANT la
    # réservation AD et la confirmation (correctif du 08/10 soir).
    Set-Policy @{CoordinationRoot='\\srv\partage\Pesto';ReserveNamesInAD=$true};$script:JoinGeneration=2;$script:JoinAutoNext=0;$script:LastConfirm=$null
    $script:SharedNameOthers=@{};$script:PestoTakenNames=$null;$script:JoinSuspend=$true;$ui.Name.SelectedIndex=-1;$script:JoinSuspend=$false;Update-PestoJoinNames
    $plan=New-PestoJoinPlanFromUI;$n0=$script:Async.Count
    $script:SharedNameOthers=@{'P123456PAINF001'=[pscustomobject]@{Name='P123456PAINF001';Station='POSTE-B';ExpiresUtc=[DateTime]::UtcNow.AddMinutes(10).ToString('o')}}
    Complete-PestoJoinCheck -Result ([pscustomobject]@{Valid=$true;Key=(Get-PestoJoinPlanKey $plan);Local=$null;Receipt=$null;Decision=$null;Checks=@()}) -Context ([pscustomobject]@{Plan=$plan;Execute=$true;Generation=2})
    $ad=@($script:Async|Select-Object -Skip $n0|Where-Object{$_.Name -eq 'JoinADReserve'})
    Check 'Registre : détenu ailleurs pendant le contrôle, nom suivant revérifié sans réservation AD ni confirmation' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF002' -and $script:JoinAutoNextTimer.IsEnabled -and $ad.Count -eq 0 -and -not $script:LastConfirm) ([string]$ui.Name.SelectedItem+' ad='+$ad.Count+' confirm='+[string]$script:LastConfirm)
    Check 'Registre : message du nom suivant explicite' ([string]$ui.Detail.Text -like '*réservé par un autre poste dans le registre partagé*') ([string]$ui.Detail.Text)
    $script:JoinAutoNextTimer.Stop();$script:SharedNameOthers=@{};$script:PestoTakenNames=$null;$script:JoinAutoNext=0
    $script:JoinSuspend=$true;$ui.Name.SelectedIndex=-1;$script:JoinSuspend=$false;Update-PestoJoinNames
    # 8. Réservation dans l'AD : après un contrôle réussi, avant la confirmation.
    Set-Policy @{ReserveNamesInAD=$true};$script:JoinGeneration=2
    $plan=New-PestoJoinPlanFromUI;$n0=$script:Async.Count
    Check 'Plan sans réservation : compte existant non demandé' (-not $plan.AllowExisting -and -not $plan.ReservedByPesto)
    Complete-PestoJoinCheck -Result ([pscustomobject]@{Valid=$true;Key=(Get-PestoJoinPlanKey $plan);Local=$null;Receipt=$null;Decision=$null;Checks=@()}) -Context ([pscustomobject]@{Plan=$plan;Execute=$true;Generation=2})
    $ad=@($script:Async|Select-Object -Skip $n0|Where-Object{$_.Name -eq 'JoinADReserve'})
    Check 'AD : réservation lancée (nom, OU cible, DC du plan), aucune confirmation encore' ($ad.Count -eq 1 -and $ad[0].Request.Name -eq 'P123456PAINF001' -and $ad[0].Request.OU -eq 'OU=Paris,OU=Org,DC=lab,DC=local' -and $ad[0].Request.DC -eq 'dc01.lab.local' -and -not $script:LastConfirm) ($ad|ConvertTo-Json -Compress -Depth 3)
    Complete-PestoJoinADReservation -Result ([pscustomobject]@{State='Reserved';Name='P123456PAINF001';Guid='11111111-2222-3333-4444-555555555555';DN='CN=P123456PAINF001,OU=Paris,OU=Org,DC=lab,DC=local'}) -Context $ad[0].Context
    $plan2=New-PestoJoinPlanFromUI
    Check 'AD : compte réservé repris par le plan (GUID)' ($plan2.AllowExisting -and $plan2.ReservedByPesto -and $plan2.ReservedGuid -eq '11111111-2222-3333-4444-555555555555') ($plan2|ConvertTo-Json -Compress)
    Check 'AD : nouvelle vérification complète lancée, puis confirmation' ($script:Starts[-1] -eq 'True:True:P123456PAINF001') ($script:Starts -join ';')
    Check 'AD : plan accepté (politique ReserveNamesInAD)' (@(Get-PestoJoinPlanErrors $plan2|Where-Object{$_ -like '*Réutilisation*'}).Count -eq 0)
    Set-Policy @{};Check 'Sans l''option : compte existant refusé' (@(Get-PestoJoinPlanErrors $plan2|Where-Object{$_ -like '*Réutilisation*'}).Count -eq 1);Set-Policy @{ReserveNamesInAD=$true}
    # Confirmation refusée : la réservation est retirée.
    $script:Confirm=$false;$n0=$script:Async.Count
    Complete-PestoJoinCheck -Result ([pscustomobject]@{Valid=$true;Key=(Get-PestoJoinPlanKey $plan2);Local=$null;Receipt=$null;Decision=$null;Checks=@()}) -Context ([pscustomobject]@{Plan=$plan2;Execute=$true;Generation=2})
    Check 'AD : récapitulatif signale le nom réservé' ($script:LastConfirm -like '*Nom réservé dans l''AD*') $script:LastConfirm
    $rel=@($script:Async|Select-Object -Skip $n0|Where-Object{$_.Request.Mode -eq 'Release'})
    Check 'AD : annulation = retrait de la réservation (même GUID)' ($rel.Count -eq 1 -and $rel[0].Request.Guid -eq '11111111-2222-3333-4444-555555555555' -and -not $script:JoinADReservation) ($rel|ConvertTo-Json -Compress -Depth 3)
    # Nom pris entre le contrôle et la réservation : nom suivant, revérifié.
    $script:JoinAutoNext=0;$plan=New-PestoJoinPlanFromUI
    Complete-PestoJoinADReservation -Result ([pscustomobject]@{State='Taken';Name='P123456PAINF001'}) -Context ([pscustomobject]@{Plan=$plan;Generation=2})
    Check 'AD : nom pris entre-temps, 002 proposé et revérifié' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF002' -and $script:JoinAutoNextTimer.IsEnabled) ([string]$ui.Name.SelectedItem)
    $script:JoinAutoNextTimer.Stop()
    # Formulaire modifié après réservation : retrait.
    $script:JoinADReservation=[pscustomobject]@{Name='P123456PAINF002';Guid='aaaaaaaa-2222-3333-4444-555555555555';OU='OU=Paris,OU=Org,DC=lab,DC=local';DC='dc01.lab.local';DN='';Utc=[DateTime]::UtcNow}
    $script:JoinBusy=$false;$ui.Name.SelectedItem='P123456PAINF004';$n0=$script:Async.Count
    Test-PestoJoinADReservationStale
    $rel=@($script:Async|Select-Object -Skip $n0|Where-Object{$_.Request.Mode -eq 'Release'})
    Check 'AD : autre nom choisi = réservation retirée' ($rel.Count -eq 1 -and $rel[0].Request.Guid -like 'aaaaaaaa*') ''
} *>&1 | ForEach-Object { if($_ -is [Management.Automation.ErrorRecord]){$script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber)} } } catch { $script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber) }
$script:R
$f=@($script:R|Where-Object{$_ -notlike 'PASS*'}).Count
'RESULTAT {0} reussis, {1} echecs' -f @($script:R|Where-Object{$_ -like 'PASS*'}).Count,$f

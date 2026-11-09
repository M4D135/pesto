# Correctifs du 08/10 (audit du banc de collisions) sur la vue de jonction WPF réelle, Windows PowerShell 5.1 :
# réservation au registre pendant le traitement (clic avant la seconde de stabilité, nom changé par Pesto), Held pendant le
# traitement, recalcul après, libération à la fermeture (registre réel sur disque, partage injoignable borné à 3 s),
# compte AD réservé retiré à la fermeture (8 s au plus), graine du tirage, message du nom suivant, connexion au partage avec
# le compte AD. Doubles : AD, opérations asynchrones, fenêtres. Les vraies fonctions sont extraites des fichiers livrés.
param([string]$Wad='C:\PestoTest\wad')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){ $script:R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''})) }
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e);if(@($e).Count){throw "Syntaxe $File : $($e[0].Message) @ $($e[0].Extent.StartLineNumber)"}
    $sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)};$sb.ToString()
}
function Import-Worker([string]$File,[string]$Var){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    [scriptblock]::Create(@($ast.FindAll({param($x) $x -is [Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq $Var},$true))[0].Right.Extent.Text.Trim().TrimStart('{').TrimEnd('}'))
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts','New-PestoComputerName','Assert-PestoClosedObject','Test-PestoPropertyPresent'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Operations.ps1' @('Test-PestoGeneratedComputerName','Test-PestoOUPath','Test-PestoDnsName','Test-PestoComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Directory.ps1' @('Split-PestoDistinguishedName','Get-PestoDomainFromDN'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Get-SiteTag','Get-AvailableMachines','Get-NameList','ConvertTo-PestoRdnValue'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Safety.ps1' @('Assert-PestoPlainPath'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Policy.ps1' @('ConvertTo-PestoPolicy','Add-PestoShareConnection','Connect-PestoCoordinationShare','Get-PestoCoordinationRoot'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Names.ps1' @('Get-PestoSharedNameSettings','Test-PestoNameReservedByOther','Get-PestoInitialNameIndex','Complete-PestoSharedNameOperation','Invoke-PestoSharedNameRefreshLists','Get-PestoSharedNameWanted','Invoke-PestoSharedNameTick','Update-PestoSharedNameStatus','Start-PestoSharedNameOperation','Stop-PestoSharedNameTimer','Close-PestoShareConnections'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Join.ps1' @('Set-PestoJoinMessage','Get-PestoJoinNameCandidates','Update-PestoJoinNames','Add-PestoTakenNames','Select-PestoJoinNextName','Stop-PestoJoinADReservationAtClose'))))
$script:PestoSharedNameWorker=Import-Worker 'Pesto-Names.ps1' '$script:PestoSharedNameWorker'
# Doubles
$script:Async=[Collections.Generic.List[object]]::new();$script:Logs=[Collections.Generic.List[string]]::new();$script:WLogs=[Collections.Generic.List[string]]::new()
function Start-PestoAsyncOperation {param($Name,$ScriptBlock,$ArgumentList,$OnSuccess,$OnError,[switch]$Replace,$TimeoutSec,$CallbackContext,$QueueMonitor,$ApartmentState) $script:Async.Add([pscustomobject]@{Name=$Name;Request=@($ArgumentList)[0];Context=$CallbackContext});$true}
function Test-PestoAsyncOperationRunning {param($Name) $false}
function Get-PestoADLoaderSource {'function Import-PestoADModule {}'}
function Update-PestoJoinUI {};function Add-LogLine {param($m,$k) $script:Logs.Add([string]$m)};function Write-Log {param($a,$b,$c,$d) $script:WLogs.Add([string]$b+' '+[string]$a)}
function Get-ComputersForNameGeneration {@($script:Inv|ForEach-Object{[pscustomobject]@{Name=$_}})}
function Update-NameList {}
$script:PREFIXE='123456';$script:PREPRODSITE='765';$script:RuntimeTags=$null;$script:GUI=$false;$script:SIM=$false;$script:INDOMAIN=$false;$script:PRD=$true
$script:DOMAINE='LAB.LOCAL';$script:DC='dc01.lab.local';$script:cred=$null;$script:AuthUser='LAB\tech';$script:Inv=@()
$script:OUV=@{Org='OU=Org,DC=lab,DC=local'};$script:OU=@{PREPROD='OU=Staging,DC=lab,DC=local'}
function Set-Policy($h){$p=[ordered]@{Schema=1};foreach($k in $h.Keys){$p[$k]=$h[$k]};$script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='PA'});POLICY=[pscustomobject]$p};$script:PestoPolicy=ConvertTo-PestoPolicy $script:CFG.POLICY}
function Reset-Registry{$script:SharedNameMine=@{};$script:SharedNamePending=@{};$script:SharedNameSeen=@{};$script:SharedNameOthers=@{};$script:SharedNameSnapshotUtc=[DateTime]::UtcNow;$script:Async.Clear();$script:Logs.Clear()}
function Reserves{,@($script:Async|Where-Object{$_.Request.Mode -eq 'Reserve'})}  # tableau même pour un seul élément (5.1 : pas de .Count sur un PSCustomObject)
Set-Policy @{CoordinationRoot='\\srv\partage\Pesto'}
$BasePath=$Wad
try { & {
    $reader=[Xml.XmlReader]::Create((Join-Path $Wad 'Pesto-Join.xaml'));try{$view=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $ui=@{};foreach($k in @{Type='JnType';Org='JnOrg';Site='JnSite';Service='JnService';Name='JnName';Existing='JnExisting';Status='JnStatus';Detail='JnDetail';Checks='JnChecks';Reference='JnReference'}.GetEnumerator()){$ui[$k.Key]=$view.FindName($k.Value)}
    $script:JoinUI=$ui;$script:JoinSuspend=$true
    [void]$ui.Type.Items.Add('Portable');$ui.Type.SelectedIndex=0;[void]$ui.Org.Items.Add('Org');$ui.Org.SelectedIndex=0;[void]$ui.Site.Items.Add('Paris');$ui.Site.SelectedIndex=0;$ui.Service.Text='INF'
    $script:JoinSuspend=$false;$script:JoinGeneration=1;$script:PestoTakenNames=$null;$script:JoinAutoNext=0

    # 1. Clic avant la seconde de stabilité : le traitement commence, le nom est réservé au tick suivant, sans attente.
    Reset-Registry;Update-PestoJoinNames;$script:JoinBusy=$true
    Invoke-PestoSharedNameTick $null $null
    $r=Reserves
    Check 'Clic immédiat : nom réservé au premier tick du traitement' ($r.Count -eq 1 -and $r[0].Request.Name -eq 'P123456PAINF001' -and $r[0].Request.Context -eq 'Join') ($r|ConvertTo-Json -Compress -Depth 3)
    Check 'Réservation transmise avec le compte AD de Pesto (champ Credential)' ($r.Count -eq 1 -and $r[0].Request.PSObject.Properties.Name -contains 'Credential')
    Invoke-PestoSharedNameTick $null $null
    Check 'Pendant la réservation en cours : pas de doublon de demande' ((Reserves).Count -eq 1)
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='Reserved'}) -Context ([pscustomobject]@{Mode='Reserve';Name='P123456PAINF001';Context='Join'})
    Invoke-PestoSharedNameTick $null $null
    Check 'Réservé : rien de plus tant que le nom ne change pas' ((Reserves).Count -eq 1)
    # 2. Pesto change le nom pendant le traitement (nom pris dans l'AD) : le nouveau nom est réservé tout de suite.
    $ui.Name.SelectedItem='P123456PAINF002'
    Invoke-PestoSharedNameTick $null $null
    $r=Reserves
    Check 'Nom suivant choisi par Pesto pendant le traitement : réservé aussitôt' ($r.Count -eq 2 -and $r[-1].Request.Name -eq 'P123456PAINF002') ($r[-1].Request.Name)
    Check 'Pendant le traitement : aucune libération' (@($script:Async|Where-Object{$_.Request.Mode -eq 'Release'}).Count -eq 0)
    # 3. Prolongation à mi-durée pendant une confirmation longue.
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='Reserved'}) -Context ([pscustomobject]@{Mode='Reserve';Name='P123456PAINF002';Context='Join'})
    $script:SharedNameMine['Join'].Utc=[DateTime]::UtcNow.AddMinutes(-8)
    Invoke-PestoSharedNameTick $null $null
    $r=Reserves
    Check 'Confirmation longue : réservation prolongée à mi-durée' ($r.Count -eq 3 -and $r[-1].Request.Name -eq 'P123456PAINF002') ($r.Count)
    # 4. Détenu ailleurs pendant le traitement : l'opération continue sur ce nom, message exact, aucune bascule.
    Reset-Registry;$script:JoinBusy=$false;Update-PestoJoinNames;$ui.Name.SelectedItem='P123456PAINF003';$script:JoinBusy=$true
    Invoke-PestoSharedNameTick $null $null
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='Held';Holder='POSTE-B · tech2';HolderExpiresUtc=[DateTime]::UtcNow.AddMinutes(10).ToString('o')}) -Context ([pscustomobject]@{Mode='Reserve';Name='P123456PAINF003';Context='Join'})
    Check 'Détenu pendant le traitement : nom inchangé' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF003') ([string]$ui.Name.SelectedItem)
    Check 'Détenu pendant le traitement : journal exact' (@($script:Logs|Where-Object{$_ -like '*P123456PAINF003 aussi réservé par POSTE-B*pendant votre opération*'}).Count -eq 1) ($script:Logs -join ' | ')
    $n=(Reserves).Count;Invoke-PestoSharedNameTick $null $null
    Check 'Détenu pendant le traitement : pas de nouvelle demande à chaque seconde' ((Reserves).Count -eq $n)
    # 5. Fin du traitement (annulation) : le nom détenu ailleurs est remplacé au tick suivant.
    $script:JoinBusy=$false;Invoke-PestoSharedNameTick $null $null
    Check 'Après le traitement : autre nom proposé' ([string]$ui.Name.SelectedItem -ne 'P123456PAINF003' -and -not $ui.Name.Items.Contains('P123456PAINF003')) ([string]$ui.Name.SelectedItem)
    # 6. Hors traitement, Held : message « autre nom proposé ».
    Complete-PestoSharedNameOperation -Result ([pscustomobject]@{State='Held';Holder='POSTE-C · tech3';HolderExpiresUtc=[DateTime]::UtcNow.AddMinutes(10).ToString('o')}) -Context ([pscustomobject]@{Mode='Reserve';Name=[string]$ui.Name.SelectedItem;Context='Join'})
    Check 'Hors traitement : « autre nom proposé »' (@($script:Logs|Where-Object{$_ -like '*déjà réservé par POSTE-C*autre nom proposé*'}).Count -eq 1) ($script:Logs -join ' | ')

    # 7. Fermeture : libération réelle, attendue (registre sur disque, vrai worker), réservations des autres intactes.
    $dir=Join-Path $env:TEMP ('pesto-reg-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
    Set-Policy @{CoordinationRoot=$dir};Reset-Registry;$script:SharedNameOwner='moi'+[Guid]::NewGuid().ToString('N')
    $req={param($m,$n,$o) [pscustomobject]@{Mode=$m;Root=$dir;Domain='LAB.LOCAL';Owner=$o;Station='PC';User='u';Minutes=15;Name=$n;Names=@($n);Context='Join';Credential=$null}}
    [void](& $script:PestoSharedNameWorker (& $req 'Prepare' '' 'x'))
    foreach($x in @(@('P123456PAINF010',$script:SharedNameOwner),@('P123456PAINF011',$script:SharedNameOwner),@('P123456PAINF012','autre-poste'))){[void](& $script:PestoSharedNameWorker (& $req 'Reserve' $x[0] $x[1]))}
    $script:SharedNameMine['Join']=[pscustomobject]@{Name='P123456PAINF010';Utc=[DateTime]::UtcNow};$script:SharedNamePending['Direct']='P123456PAINF011'
    $sw=[Diagnostics.Stopwatch]::StartNew();Stop-PestoSharedNameTimer;$ms=$sw.ElapsedMilliseconds
    $left=@([IO.Directory]::GetFiles((Join-Path $dir 'reservations'),'*.json')|ForEach-Object{[IO.Path]::GetFileNameWithoutExtension($_)})
    Check 'Fermeture : nos réservations retirées (proposée et en cours d''écriture)' (-not ($left -contains 'P123456PAINF010') -and -not ($left -contains 'P123456PAINF011')) ($left -join ',')
    Check 'Fermeture : réservation d''un autre poste intacte' ($left -contains 'P123456PAINF012') ($left -join ',')
    Check "Fermeture : libération faite avant de rendre la main ($ms ms)" ($ms -lt 3000) "$ms ms"
    Remove-Item $dir -Recurse -Force
    # 8. Fermeture, partage injoignable : la fermeture n'attend pas plus de 3 s.
    Set-Policy @{CoordinationRoot='\\10.255.255.1\pesto\registre'};Reset-Registry;$script:SharedNameMine['Join']=[pscustomobject]@{Name='P123456PAINF020';Utc=[DateTime]::UtcNow}
    $sw=[Diagnostics.Stopwatch]::StartNew();Stop-PestoSharedNameTimer;$ms=$sw.ElapsedMilliseconds
    Check "Fermeture, partage injoignable : bornée ($ms ms)" ($ms -lt 3800) "$ms ms"

    # 9. Compte AD réservé à la fermeture : retiré (worker), ou laissé et signalé au-delà de 8 s.
    $script:PestoJoinADReserveWorker={param($Request) [pscustomobject]@{State='Released';Name=$Request.Name;Mode=$Request.Mode;Guid=$Request.Guid}}
    $script:JoinADReservation=[pscustomobject]@{Name='P123456PAINF030';Guid=[Guid]::NewGuid().ToString('D');OU='OU=Paris,DC=lab,DC=local';DC='dc01.lab.local';DN='';Utc=[DateTime]::UtcNow}
    $script:WLogs.Clear();Stop-PestoJoinADReservationAtClose
    Check 'Fermeture : compte AD réservé retiré par le worker (mode Release, GUID)' ($null -eq $script:JoinADReservation -and @($script:WLogs|Where-Object{$_ -like '*P123456PAINF030 : Released*'}).Count -eq 1) ($script:WLogs -join ' | ')
    $script:PestoJoinADReserveWorker={param($Request) Start-Sleep -Seconds 30;[pscustomobject]@{State='Released'}}
    $script:JoinADReservation=[pscustomobject]@{Name='P123456PAINF031';Guid=[Guid]::NewGuid().ToString('D');OU='';DC='dc';DN='';Utc=[DateTime]::UtcNow}
    $script:WLogs.Clear();$sw=[Diagnostics.Stopwatch]::StartNew();Stop-PestoJoinADReservationAtClose;$ms=$sw.ElapsedMilliseconds
    Check "Fermeture : AD lent, attente bornée à 8 s ($ms ms) et signalée" ($ms -lt 9000 -and $ms -ge 7500 -and @($script:WLogs|Where-Object{$_ -like 'WARN*P123456PAINF031 non confirmé en 8 s*'}).Count -eq 1) ("$ms ms ; "+($script:WLogs -join ' | '))
    $script:JoinADReservation=$null;$script:WLogs.Clear();Stop-PestoJoinADReservationAtClose
    Check 'Fermeture sans réservation AD : rien' ($script:WLogs.Count -eq 0)

    # 10. Graine du tirage : 40 Pesto « lancés au même instant » ne tirent pas tous le même numéro.
    Set-Policy @{RandomNameChoice=50};$draws=@(1..40|ForEach-Object{$script:SharedNameRandom=$null;Get-PestoInitialNameIndex -Count 50})
    $distinct=@($draws|Sort-Object -Unique).Count
    Check "Graine : tirages variés au même instant ($distinct valeurs distinctes sur 40)" ($distinct -ge 15) ($draws -join ',')
    # 11. Message du nom suivant selon le réglage.
    Set-Policy @{RandomNameChoice=5};$script:JoinAutoNext=0;$script:JoinBusy=$false;Update-PestoJoinNames;$t0=[string]$ui.Name.SelectedItem
    [void](Select-PestoJoinNextName -TakenName $t0 -Reason 'vient d''être pris.')
    Check 'Hasard : message « tiré au hasard », pas « premier numéro libre »' ([string]$ui.Detail.Text -like '*tiré au hasard*' -and [string]$ui.Detail.Text -notlike '*premier numéro libre*') ([string]$ui.Detail.Text)
    Set-Policy @{};$script:JoinAutoNext=0;Update-PestoJoinNames;$t0=[string]$ui.Name.SelectedItem
    [void](Select-PestoJoinNextName -TakenName $t0 -Reason 'vient d''être pris.')
    Check 'Sans hasard : « premier numéro libre de la série »' ([string]$ui.Detail.Text -like '*premier numéro libre de la série*') ([string]$ui.Detail.Text)

    # 11b. Nom réservé au registre seulement (revue du 08/10) : pas écarté pour la session, journal exact.
    Set-Policy @{CoordinationRoot='\\srv\partage\Pesto'};$script:JoinAutoNext=0;$script:PestoTakenNames=$null;$script:Logs.Clear();Update-PestoJoinNames;$t0=[string]$ui.Name.SelectedItem
    $script:SharedNameOthers=@{$t0=[pscustomobject]@{Name=$t0;Station='POSTE-B';ExpiresUtc=[DateTime]::UtcNow.AddMinutes(10).ToString('o')}}
    [void](Select-PestoJoinNextName -TakenName $t0 -Reason 'est réservé par un autre poste dans le registre partagé.' -RegistryHeld)
    Check 'Registre seulement : nom suivant, mais pas écarté pour la session' ([string]$ui.Name.SelectedItem -ne $t0 -and -not ($script:PestoTakenNames -and $script:PestoTakenNames.Contains($t0))) ([string]$ui.Name.SelectedItem)
    Check 'Registre seulement : journal « registre partagé », pas « AD »' (@($script:Logs|Where-Object{$_ -like "*$t0 réservé par un autre poste (registre partagé)*"}).Count -eq 1 -and @($script:Logs|Where-Object{$_ -like '*déjà utilisé dans l''AD*'}).Count -eq 0) ($script:Logs -join ' | ')
    Check 'Registre seulement : titre explicite' ([string]$ui.Status.Text -eq 'Nom réservé par un autre poste : nom suivant proposé') ([string]$ui.Status.Text)
    $script:SharedNameOthers=@{};$script:JoinSuspend=$true;$ui.Name.SelectedIndex=-1;$script:JoinSuspend=$false;Update-PestoJoinNames
    Check 'Réservation expirée : le nom revient' ([string]$ui.Name.SelectedItem -eq $t0) ([string]$ui.Name.SelectedItem)
    # 11c. Fermeture : connexions notées puis oubliées (la suppression réelle est jouée par registre-hors-domaine.ps1).
    $script:INDOMAIN=$true;Add-PestoShareConnection '\\pesto-hote-inexistant.invalid\p';Close-PestoShareConnections
    Check 'Fermeture : connexions au partage traitées puis oubliées' ($null -eq $script:PestoShareConnections)
    $script:INDOMAIN=$false
    # 12. Partage du registre avec le compte AD (poste hors domaine).
    $cr=New-Object Management.Automation.PSCredential('LAB\tech',(ConvertTo-SecureString 'x' -AsPlainText -Force))
    Check 'Connexion au partage : sans compte AD, rien tenté' ((Connect-PestoCoordinationShare -Root '\\srv\p\r' -Credential $null) -eq $false)
    Check 'Connexion au partage : chemin local, rien tenté' ((Connect-PestoCoordinationShare -Root 'C:\PestoRegistre' -Credential $cr) -eq $false)
    $msg='';try{[void](Connect-PestoCoordinationShare -Root '\\pesto-hote-inexistant.invalid\p\r' -Credential $cr)}catch{$msg=$_.Exception.Message}
    Check 'Connexion au partage : échec expliqué avec le compte utilisé' ($msg -like 'Registre partagé inaccessible avec le compte LAB\tech*') $msg
    $script:cred=$null;$msg='';try{[void](Get-PestoCoordinationRoot -Policy ([pscustomobject]@{Schema=1;CoordinationRoot='\\pesto-hote-inexistant.invalid\p\r'}) -Domain 'LAB.LOCAL')}catch{$msg=$_.Exception.Message}
    Check 'Verrou sans compte AD : refus inchangé « Coordination non préparée »' ($msg -like 'Coordination non préparée*') $msg
    $req=[pscustomobject]@{Mode='Snapshot';Root='\\pesto-hote-inexistant.invalid\p\r';Domain='LAB.LOCAL';Owner='o';Station='PC';User='u';Minutes=15;Name='';Names=@();Context='';Credential=$cr}
    $msg='';try{[void](& $script:PestoSharedNameWorker $req)}catch{$msg=$_.Exception.Message}
    Check 'Worker du registre : connexion tentée avec le compte AD, échec expliqué' ($msg -like 'Partage du registre inaccessible avec le compte LAB\tech*') $msg
} } catch { $script:R.Add('FAIL exception : '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber) }
$script:R
$ok=@($script:R|Where-Object{$_ -like 'PASS*'}).Count;$ko=@($script:R|Where-Object{$_ -like 'FAIL*'}).Count
"RESULTAT $ok reussis, $ko echecs"

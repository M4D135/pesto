# Nom pris par un autre poste : bascule vers le nom suivant dans la vraie vue de jonction (WPF réel, PS 5.1, STA, sans bureau).
param([string]$Wad='C:\PestoTest\wad')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){ $script:R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''})) }
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e)
    if(@($e).Count){throw "Syntaxe $File : $($e[0].Message)"}
    $sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)};return $sb.ToString()
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('ConvertTo-PestoNameParts','New-PestoComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Operations.ps1' @('Test-PestoGeneratedComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Get-SiteTag','Get-AvailableMachines','Get-NameList'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Join.ps1' @('Set-PestoJoinMessage','Get-PestoJoinNameCandidates','Update-PestoJoinNames','Test-PestoJoinNameTaken','Select-PestoJoinNextName','Request-PestoJoinAutoNextCheck','Invoke-PestoJoinAutoNextTick','Complete-PestoJoinCheck','Complete-PestoJoinExecution'))))
# Doubles : pas d'AD, pas de worker, pas de fenêtre modale.
$script:Starts=[Collections.Generic.List[string]]::new();$script:Outcomes=0;$script:Logs=[Collections.Generic.List[string]]::new()
function Start-PestoJoinCheck {param([switch]$ExecuteAfterCheck) $script:Starts.Add([string]$ExecuteAfterCheck.IsPresent+':'+[string]$script:JoinUI.Name.SelectedItem)}
function Update-PestoJoinUI {}
function Set-PestoJoinBusy {param($b)}
function Add-LogLine {param($m,$k) $script:Logs.Add([string]$m)}
function Write-Log {param($a,$b,$c,$d)}
function Invalidate-PestoNameInventory {}
function Save-PestoJoinHistory {param($Request,$Code)}
function Show-PestoJoinOutcome {$script:Outcomes++}
function Get-PestoJoinGuidance {param($m) ''}
function Get-ComputersForNameGeneration {@([pscustomobject]@{Name='P123456PAINF001'})}
function New-PestoJoinPlanFromUI {[pscustomobject]@{NewName=[string]$script:JoinUI.Name.SelectedItem}}
function Get-PestoJoinPlanKey {param($Plan) [string]$Plan.NewName}
$script:PREFIXE='123456';$script:RuntimeTags=$null;$script:PREPRODSITE='765'
$script:CFG=[pscustomobject]@{TAGS=@([pscustomobject]@{Site='Paris';Tag='PA'})}
$script:GUI=$false;$script:SIM=$false
try { & {
    $reader=[Xml.XmlReader]::Create((Join-Path $Wad 'Pesto-Join.xaml'));try{$view=[Windows.Markup.XamlReader]::Load($reader)}finally{$reader.Dispose()}
    $ui=@{};foreach($k in @{Type='JnType';Site='JnSite';Service='JnService';Name='JnName';Existing='JnExisting';Status='JnStatus';Detail='JnDetail';Checks='JnChecks'}.GetEnumerator()){$ui[$k.Key]=$view.FindName($k.Value)}
    $script:JoinUI=$ui;$script:JoinSuspend=$true
    [void]$ui.Type.Items.Add('Portable');$ui.Type.SelectedIndex=0;[void]$ui.Site.Items.Add('Paris');$ui.Site.SelectedIndex=0;$ui.Service.Text='INF'
    $script:JoinSuspend=$false;$script:JoinGeneration=7;$script:PestoTakenNames=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);$script:JoinAutoNext=0
    Update-PestoJoinNames
    Check 'Nom proposé au départ' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF002') ([string]$ui.Name.SelectedItem)
    # 1. Contrôle : le nom vient d'être pris par un autre poste.
    $res=[pscustomobject]@{Valid=$false;Key='P123456PAINF002';Local=$null;Receipt=$null;Decision=$null;Checks=@([pscustomobject]@{Check='Nouveau nom';State='Bloqué';Detail='Nom déjà utilisé. Aucun objet supprimé.'})}
    Complete-PestoJoinCheck -Result $res -Context ([pscustomobject]@{Plan=[pscustomobject]@{NewName='P123456PAINF002'};Execute=$true;Generation=7})
    Check 'Contrôle : nom suivant sélectionné' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF003') ([string]$ui.Name.SelectedItem)
    Check 'Contrôle : nom pris jamais reproposé' (-not $ui.Name.Items.Contains('P123456PAINF002'))
    Check 'Contrôle : message clair (nom pris et nom proposé)' (([string]$ui.Detail.Text) -match 'P123456PAINF002' -and ([string]$ui.Detail.Text) -match 'P123456PAINF003') ([string]$ui.Detail.Text)
    Check 'Contrôle : relance prévue, rien lancé' ($script:JoinAutoNextTimer.IsEnabled -and $script:Starts.Count -eq 0)
    if($script:JoinAutoNextTimer){Invoke-PestoJoinAutoNextTick $null $null}
    $script:R.Add('DEBUG statut='+[string]$ui.Status.Text+' | detail='+[string]$ui.Detail.Text+' | items='+(@($ui.Name.Items) -join ','))
    Check 'Contrôle : revérification du nom suivant, puis confirmation' ($script:Starts.Count -eq 1 -and $script:Starts[0] -eq 'True:P123456PAINF003') ($script:Starts -join ';')
    # 2. Exécution : refus 13 juste avant Add-Computer (nom pris entre confirmation et ajout).
    $script:JoinGeneration=8;$req=[pscustomobject]@{OperationId='t';Plan=[pscustomobject]@{NewName='P123456PAINF003'}}
    Complete-PestoJoinExecution -Result ([pscustomobject]@{Action=[pscustomobject]@{ExitCode=13;ExitMsg='Compte déjà présent ou différent du compte précréé confirmé. Aucun objet supprimé.'};Receipt=$null;Check=$null}) -Request $req
    Check 'Exécution : nom suivant sélectionné' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF004') ([string]$ui.Name.SelectedItem)
    Check 'Exécution : pas de bilan final, relance avec confirmation' ($script:Outcomes -eq 0 -and $script:JoinAutoNextExecute -eq $true -and -not $script:JoinLocked)
    # 3. Borne : au-delà de 5 bascules d'affilée, arrêt et message.
    $script:JoinAutoNext=5
    $ok=Select-PestoJoinNextName -TakenName 'P123456PAINF004' -Reason 'est pris.'
    Check 'Borne : sixième bascule refusée' (-not $ok -and ([string]$ui.Detail.Text) -match 'actualisez')
    # 4. Code 96 sans nom pris : bilan normal, aucune bascule.
    $script:JoinAutoNext=0;$before=[string]$ui.Name.SelectedItem
    Complete-PestoJoinExecution -Result ([pscustomobject]@{Action=[pscustomobject]@{ExitCode=96;ExitMsg='L''etat Windows a change.'};Receipt=$null;Check=$null}) -Request ([pscustomobject]@{OperationId='u';Plan=[pscustomobject]@{NewName=$before}})
    Check 'Autre refus : bilan affiché, nom inchangé' ($script:Outcomes -eq 1 -and [string]$ui.Name.SelectedItem -eq $before)
} *>&1 | ForEach-Object { $_ } } catch { $script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber) }
$script:R
$f=@($script:R|Where-Object{$_ -like 'FAIL*'}).Count
'RESULTAT {0} reussis, {1} echecs' -f ($script:R.Count-$f),$f
if($f){exit 1}

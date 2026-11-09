# Nom pris (08/10) : série lue dans l'AD, inventaire arrivé pendant le contrôle, relances bornées (WPF réel, PS 5.1, STA, sans bureau).
# Reprend les cas du banc du 07/10 (preuves/vm-2026-10-07-noms-pris) et ajoute ceux du défaut « plusieurs essais puis abandon ».
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
. ([scriptblock]::Create((Import-Fn 'Pesto-Join.ps1' @('Set-PestoJoinMessage','Get-PestoJoinNameCandidates','Update-PestoJoinNames','Test-PestoJoinNameTaken','Add-PestoTakenNames','Select-PestoJoinNextName','Request-PestoJoinAutoNextCheck','Invoke-PestoJoinAutoNextTick','Complete-PestoJoinCheck','Complete-PestoJoinExecution'))))
# Doubles : pas d'AD, pas de worker, pas de fenêtre modale.
$script:Starts=[Collections.Generic.List[string]]::new();$script:Outcomes=0;$script:Logs=[Collections.Generic.List[string]]::new()
function Start-PestoJoinCheck {param([switch]$ExecuteAfterCheck,[switch]$Auto) $script:Starts.Add([string]$ExecuteAfterCheck.IsPresent+':'+[string]$script:JoinUI.Name.SelectedItem+':'+[string]$Auto.IsPresent)}
function Confirm-YesNo {param($Msg,$Confirm) $script:Confirms++;$false}
function Test-PestoNameReservedByOther {param($Name) $false}  # registre partagé (08/10 soir) : neutre ici
function Get-PestoInitialNameIndex {param($Count) 0}  # numéro au hasard (08/10 soir) : désactivé ici
function Get-PestoSharedNameSettings {[pscustomobject]@{Root='';Minutes=15;Random=0;ReserveInAD=$false}}  # réglages du registre (message du nom suivant, 08/10 soir) : sans registre ni hasard
function Update-PestoJoinUI {}
function Set-PestoJoinBusy {param($b)}
function Add-LogLine {param($m,$k) $script:Logs.Add([string]$m)}
function Write-Log {param($a,$b,$c,$d)}
function Invalidate-PestoNameInventory {}
function Save-PestoJoinHistory {param($Request,$Code)}
function Show-PestoJoinOutcome {$script:Outcomes++}
function Get-PestoJoinGuidance {param($m) ''}
function Get-ComputersForNameGeneration {@($script:Inv|ForEach-Object{[pscustomobject]@{Name=$_}})}
$script:Inv=@('P123456PAINF001');$script:Confirms=0
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
    Check 'Contrôle : revérification du nom suivant, puis confirmation' ($script:Starts.Count -eq 1 -and $script:Starts[0] -eq 'True:P123456PAINF003:True') ($script:Starts -join ';')
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

    # 5. Défaut du 08/10 : inventaire pas encore chargé, 001 à 006 et 009 pris dans l'AD. Un seul contrôle suffit :
    #    la série lue dans l'AD est écartée et le premier numéro réellement libre (007) est proposé directement.
    $script:JoinAutoNextTimer.Stop();$script:Inv=@();$script:PestoTakenNames.Clear();$script:JoinAutoNext=0;$script:JoinAutoRecheck=0;$script:Starts.Clear();$script:JoinGeneration=20
    $script:JoinSuspend=$true;$ui.Name.SelectedIndex=-1;$script:JoinSuspend=$false
    Update-PestoJoinNames
    Check 'Série : départ sans inventaire sur 001' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF001') ([string]$ui.Name.SelectedItem)
    $series=@(1..6+9|ForEach-Object{'P123456PAINF'+$_.ToString('D3')})
    $res=[pscustomobject]@{Valid=$false;Key='P123456PAINF001';Local=$null;Receipt=$null;Decision=$null;SeriesTaken=$series;Checks=@([pscustomobject]@{Check='Nouveau nom';State='Bloqué';Detail='Nom déjà utilisé. Aucun objet supprimé.'})}
    Complete-PestoJoinCheck -Result $res -Context ([pscustomobject]@{Plan=[pscustomobject]@{NewName='P123456PAINF001'};Execute=$true;Generation=20})
    Check 'Série : premier numéro libre proposé directement (007)' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF007') ([string]$ui.Name.SelectedItem)
    Check 'Série : aucun numéro pris reproposé' (@($series|Where-Object{$ui.Name.Items.Contains($_)}).Count -eq 0)
    Check 'Série : 009 pris sauté plus loin, 008 puis 010 proposés ensuite' ($ui.Name.Items.Count -ge 3 -and [string]$ui.Name.Items[1] -eq 'P123456PAINF008' -and [string]$ui.Name.Items[2] -eq 'P123456PAINF010') ((@($ui.Name.Items)|Select-Object -First 3) -join ',')
    Check 'Série : une seule bascule comptée' ($script:JoinAutoNext -eq 1) ([string]$script:JoinAutoNext)
    Invoke-PestoJoinAutoNextTick $null $null
    Check 'Série : 007 revérifié automatiquement puis confirmation' ($script:Starts.Count -eq 1 -and $script:Starts[0] -eq 'True:P123456PAINF007:True') ($script:Starts -join ';')
    # 6. L'inventaire arrive pendant le contrôle de 007 (007 et 008 y figurent) : la liste est recalculée, la sélection passe à 010.
    #    Avant : « Contrôle périmé », l'enchaînement s'arrêtait et il fallait relancer. Maintenant : relance sur 010.
    $script:Inv=@('P123456PAINF007','P123456PAINF008');Update-PestoJoinNames
    Check 'Inventaire : sélection recalculée (010)' ([string]$ui.Name.SelectedItem -eq 'P123456PAINF010') ([string]$ui.Name.SelectedItem)
    $res=[pscustomobject]@{Valid=$false;Key='P123456PAINF007';Local=$null;Receipt=$null;Decision=$null;SeriesTaken=@($series+'P123456PAINF007'+'P123456PAINF008');Checks=@([pscustomobject]@{Check='Nouveau nom';State='Bloqué';Detail='Nom déjà utilisé. Aucun objet supprimé.'})}
    Complete-PestoJoinCheck -Result $res -Context ([pscustomobject]@{Plan=[pscustomobject]@{NewName='P123456PAINF007'};Execute=$true;Generation=20})
    Check 'Inventaire : pas d''abandon (« Contrôle périmé » évité)' (([string]$ui.Status.Text) -notmatch 'périmé' -and $script:JoinAutoNextTimer.IsEnabled) ([string]$ui.Status.Text+' | '+[string]$ui.Detail.Text)
    Check 'Inventaire : nom vérifié annoncé' (([string]$ui.Detail.Text) -match 'P123456PAINF010') ([string]$ui.Detail.Text)
    Check 'Inventaire : 007 écarté pour la session' ($script:PestoTakenNames.Contains('P123456PAINF007') -and -not $ui.Name.Items.Contains('P123456PAINF007'))
    Invoke-PestoJoinAutoNextTick $null $null
    Check 'Inventaire : relance automatique sur 010, confirmation conservée' ($script:Starts.Count -eq 2 -and $script:Starts[1] -eq 'True:P123456PAINF010:True' -and $script:Confirms -eq 0) ($script:Starts -join ';')
    # 7. Résultat valide mais nom changé entre-temps (010 entré dans l'inventaire) : relance sur le nouveau nom, jamais de confirmation d'un ancien nom.
    $script:Inv=@($script:Inv+'P123456PAINF010');Update-PestoJoinNames
    $res=[pscustomobject]@{Valid=$true;Key='P123456PAINF010';Local=$null;Receipt=$null;Decision=$null;Checks=@([pscustomobject]@{Check='Nouveau nom';State='OK';Detail='Libre.'})}
    Complete-PestoJoinCheck -Result $res -Context ([pscustomobject]@{Plan=[pscustomobject]@{NewName='P123456PAINF010'};Execute=$true;Generation=20})
    Invoke-PestoJoinAutoNextTick $null $null
    Check 'Valide mais périmé : relance sur 011, aucune confirmation' ($script:Starts.Count -eq 3 -and $script:Starts[2] -eq 'True:P123456PAINF011:True' -and $script:Confirms -eq 0) ($script:Starts -join ';')
    # 8. Bornes : au-delà de 3 relances dues à l'inventaire, arrêt et message ; une saisie du technicien n'est jamais relancée.
    $script:JoinAutoRecheck=3;$script:Inv=@($script:Inv+'P123456PAINF011');Update-PestoJoinNames
    Complete-PestoJoinCheck -Result $res -Context ([pscustomobject]@{Plan=[pscustomobject]@{NewName='P123456PAINF010'};Execute=$true;Generation=20})
    Check 'Borne : quatrième relance refusée, message' (([string]$ui.Status.Text) -match 'périmé' -and -not $script:JoinAutoNextTimer.IsEnabled) ([string]$ui.Status.Text)
    $script:JoinAutoRecheck=0
    Complete-PestoJoinCheck -Result $res -Context ([pscustomobject]@{Plan=[pscustomobject]@{NewName='P123456PAINF010'};Execute=$true;Generation=19})
    Check 'Saisie du technicien : contrôle périmé, pas de relance' (([string]$ui.Status.Text) -match 'périmé' -and -not $script:JoinAutoNextTimer.IsEnabled) ([string]$ui.Status.Text)
    # 9. Refus 13 juste avant l'ajout, avec la série relue : tous ses numéros écartés.
    $script:JoinAutoNext=0;$script:JoinGeneration=21;$cur=[string]$ui.Name.SelectedItem
    $chk=[pscustomobject]@{SeriesTaken=@($cur,'P123456PAINF013');Checks=@([pscustomobject]@{Check='Nouveau nom';State='Bloqué';Detail='Nom déjà utilisé.'});Local=$null}
    Complete-PestoJoinExecution -Result ([pscustomobject]@{Action=[pscustomobject]@{ExitCode=13;ExitMsg='Compte déjà présent ou différent du compte précréé confirmé. Aucun objet supprimé.'};Receipt=$null;Check=$chk}) -Request ([pscustomobject]@{OperationId='v';Plan=[pscustomobject]@{NewName=$cur}})
    Check 'Exécution : série relue écartée (012 pris, 013 pris, 014 proposé)' ($cur -eq 'P123456PAINF012' -and [string]$ui.Name.SelectedItem -eq 'P123456PAINF014') ($cur+' -> '+[string]$ui.Name.SelectedItem)
} *>&1 | ForEach-Object { $_ } } catch { $script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber) }
$script:R
$f=@($script:R|Where-Object{$_ -like 'FAIL*'}).Count
'RESULTAT {0} reussis, {1} echecs' -f ($script:R.Count-$f),$f
if($f){exit 1}

# « Vérification requise » expliqué et actionnable ; « Enregistrer » sans changement sans redémarrage (08/10/2026).
# Vraies fonctions de Pesto (UXFlow, Configuration), vrais contrôles WPF, Windows PowerShell 5.1, STA, sans bureau.
param([string]$Wad='C:\PestoTest\wad',[string]$Cfg='C:\PestoTest-run\cfg.modele-complet.json')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:R=[Collections.Generic.List[string]]::new()
function Check([string]$N,[bool]$Ok,[string]$D=''){ $script:R.Add($(if($Ok){'PASS '}else{'FAIL '})+$N+$(if(-not $Ok -and $D){' :: '+$D}else{''})) }
function Import-Fn([string]$File,[string[]]$Names){
    $t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $Wad $File),[ref]$t,[ref]$e);if(@($e).Count){throw "Syntaxe $File"}
    $sb=[Text.StringBuilder]::new();foreach($n in $Names){$f=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n},$true));if(-not $f.Count){throw "Fonction absente : $n"};[void]$sb.AppendLine($f[0].Extent.Text)};$sb.ToString()
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Operations.ps1' @('Test-PestoComputerName'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-UXFlow.ps1' @('Get-PestoPrimaryStep','Get-PestoPrimaryContext','Invoke-PestoPrimaryAction'))))
$cfgFns=@('Get-PestoConfigurationSignature')
foreach($f in 'Pesto-Configuration.ps1','Pesto-Contracts.ps1','Pesto-Core.ps1','Pesto-Safety.ps1','Pesto-Operations.ps1'){
    $src=Get-Content (Join-Path $Wad $f) -Raw
    foreach($n in 'ConvertTo-PestoCanonicalValue','Get-PestoStableHash'){if($src -match "(?m)^function $n\b" -and -not (Get-Command $n -ErrorAction SilentlyContinue)){. ([scriptblock]::Create((Import-Fn $f @($n))))}}
}
. ([scriptblock]::Create((Import-Fn 'Pesto-Configuration.ps1' $cfgFns)))
# Depuis le 08/10 au soir, la signature lit aussi les booléens et la politique appliquée.
. ([scriptblock]::Create((Import-Fn 'Pesto-Core.ps1' @('Convert-Value-TF'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Contracts.ps1' @('Assert-PestoClosedObject','Test-PestoPropertyPresent'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Policy.ps1' @('ConvertTo-PestoPolicy'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Operations.ps1' @('Test-PestoOUPath'))))
. ([scriptblock]::Create((Import-Fn 'Pesto-Directory.ps1' @('Split-PestoDistinguishedName','Get-PestoDomainFromDN'))))
# Doubles d'état et d'actions (aucune fenêtre, aucune lecture).
$script:Calls=[Collections.Generic.List[string]]::new()
function Test-PestoAsyncOperationRunning {param($Name) $false}
function Test-PestoQueueWorkerStillActive {$false}
function Test-PestoGlobalSafetyBarrier {[bool]$script:Barrier}
function Test-PestoDirectTargetBarrier {param($Computer) [bool]$script:DirectBarrier}
function Invoke-PestoJoinReviewClick {param($a,$b) $script:Calls.Add('ReviewJoin')}
function Show-PestoInterventions {$script:Calls.Add('Interventions')}
function Show-PestoPostState {param($Mode) $script:Calls.Add('PostState:'+$Mode)}
function Update-AddButton {$script:Calls.Add('AddButton')}
function Update-PestoSuiteUI {}
function Show-PestoUsefulError {param($Title,$Message,$Stage,$MutationPossible) $script:Calls.Add('ERR '+$Message)}
$TxtPCName=[Windows.Controls.TextBox]::new();$TxtPCName.Text='P111301PAINF004'
$CbType=[Windows.Controls.ComboBox]::new();[void]$CbType.Items.Add('Portable');$CbType.SelectedIndex=0
$CbOrg=[Windows.Controls.ComboBox]::new();[void]$CbOrg.Items.Add('Org');$CbOrg.SelectedIndex=0
$CbSite=[Windows.Controls.ComboBox]::new();[void]$CbSite.Items.Add('Paris');$CbSite.SelectedIndex=0
$CbService=[Windows.Controls.ComboBox]::new();$CbService.IsEditable=$true;$CbService.Text='INF'
$CbName=[Windows.Controls.ComboBox]::new();[void]$CbName.Items.Add('P111301PAINF005');$CbName.SelectedIndex=0
$ChkRename=[Windows.Controls.CheckBox]::new();$ChkRename.IsChecked=$true;$ChkMove=[Windows.Controls.CheckBox]::new()
$BtnAdd=[Windows.Controls.Button]::new();$BtnAdd.IsEnabled=$false
$script:OU_ACTUELLE='OU=Paris,OU=Org,DC=lab,DC=local';$script:EDIT_ROW_INDEX=-1
function Reset-State {$script:CfgRestartRequired=$false;$script:JoinLocked=$false;$script:JoinReceipt=$null;$script:Barrier=$false;$script:DirectBarrier=$false;$script:EDIT_ROW_INDEX=-1;$script:DirectResumePlan=$null;$script:PestoReadOnly=$false;$script:Calls.Clear()}
try { & {
    # 1. Jonction faite par Pesto, PC redémarré dans le domaine : reçu à vérifier. Avant : « Vérification requise » grisé, texte général.
    Reset-State;$script:JoinLocked=$true;$script:JoinReceipt=[pscustomobject]@{OperationId=[Guid]::NewGuid().ToString('D');Phase='PendingRestart'}
    $s=Get-PestoPrimaryContext
    Check 'Jonction à vérifier : bouton « Vérifier la jonction » actif' ($s.Label -eq 'Vérifier la jonction' -and $s.Enabled -and $s.Action -eq 'ReviewJoin') ($s.Label+' / '+$s.Enabled)
    Check 'Jonction à vérifier : la cause est dite' ($s.Hint -like 'La mise au domaine de ce PC attend sa vérification*') $s.Hint
    Invoke-PestoPrimaryAction $null $null
    Check 'Jonction à vérifier : le clic ouvre la vérification, puis recalcule le formulaire' (($script:Calls -join ',') -eq 'ReviewJoin,AddButton') ($script:Calls -join ',')
    # 2. Sans reçu lisible : texte, mais pas d'action inventée.
    Reset-State;$script:JoinLocked=$true
    $s=Get-PestoPrimaryContext
    Check 'Jonction sans reçu : bouton grisé, cause dite' ($s.Label -eq 'Vérification requise' -and -not $s.Enabled -and $s.Hint -like 'La mise au domaine*') ($s.Label+' / '+$s.Hint)
    # 3. Paramètres enregistrés : relance demandée en clair.
    Reset-State;$script:CfgRestartRequired=$true
    $s=Get-PestoPrimaryContext
    Check 'Paramètres enregistrés : « fermez puis relancez Pesto »' (-not $s.Enabled -and $s.Hint -like '*fermez puis relancez Pesto*') $s.Hint
    # 4. Ancienne exécution : bouton « Ouvrir les interventions ».
    Reset-State;$script:Barrier=$true
    $s=Get-PestoPrimaryContext;Invoke-PestoPrimaryAction $null $null
    Check 'Ancienne exécution : « Ouvrir les interventions »' ($s.Label -eq 'Ouvrir les interventions' -and $s.Enabled -and $script:Calls[0] -eq 'Interventions') ($s.Label+' / '+($script:Calls -join ','))
    # 5. Dernière opération sur ce poste : « Vérifier l'opération ».
    Reset-State;$script:DirectBarrier=$true
    $s=Get-PestoPrimaryContext;Invoke-PestoPrimaryAction $null $null
    Check 'Opération unitaire : « Vérifier l''opération »' ($s.Label -eq 'Vérifier l''opération' -and $script:Calls[0] -eq 'PostState:Direct') ($s.Label+' / '+($script:Calls -join ','))
    # 6. Ligne de file en édition : cause dite, pas d'action.
    Reset-State;$script:EDIT_ROW_INDEX=0
    $s=Get-PestoPrimaryContext
    Check 'Ligne en édition : cause dite' (-not $s.Enabled -and $s.Hint -like 'Une ligne de la file*') $s.Hint
    # 7. Consultation : jamais d'action d'écriture proposée.
    Reset-State;$script:JoinLocked=$true;$script:JoinReceipt=[pscustomobject]@{OperationId='x'};$script:PestoReadOnly=$true
    $s=Get-PestoPrimaryContext
    Check 'Consultation : bouton grisé' (-not $s.Enabled -and $s.Label -eq 'Vérification requise') $s.Label
    # 8. Sans blocage, formulaire prêt : parcours normal inchangé.
    Reset-State;$BtnAdd.IsEnabled=$true
    $s=Get-PestoPrimaryContext
    Check 'Sans blocage : « Vérifier puis renommer »' ($s.Action -eq 'Execute' -and $s.Label -eq 'Vérifier puis renommer') $s.Label
    # 9. « Enregistrer » sans changement avec le cfg.json livré (sans EntraPolicy) : même signature, donc pas de redémarrage.
    # Ancien fichier (cas du cfg livré le 08/10) : modèle fictif sans EntraPolicy ni POLICY.
    function Get-Legacy {$o=Get-Content $Cfg -Raw -Encoding UTF8|ConvertFrom-Json;@($o.CONF)[0].PSObject.Properties.Remove('EntraPolicy');$o.PSObject.Properties.Remove('POLICY');$o}
    $loaded=Get-Legacy
    $conf=@($loaded.CONF)[0]
    Check 'Ancien fichier : EntraPolicy absent' (-not ($conf.PSObject.Properties.Name -contains 'EntraPolicy'))
    $a=Get-PestoConfigurationSignature $loaded
    $saved=Get-Legacy;@($saved.CONF)[0]|Add-Member -NotePropertyName EntraPolicy -NotePropertyValue 'HybridOnly'
    $b=Get-PestoConfigurationSignature $saved
    Check 'Enregistrer sans changement : signature identique (aucun redémarrage)' ($a -eq $b) ($a+' / '+$b)
    $dis=Get-Legacy;@($dis.CONF)[0]|Add-Member -NotePropertyName EntraPolicy -NotePropertyValue 'Disabled'
    Check 'Vrai changement (retrait Entra interdit) : signature différente' ($a -ne (Get-PestoConfigurationSignature $dis))
    $dom=Get-Legacy;@($dom.CONF)[0].Domaine='autre.local'
    Check 'Vrai changement (domaine) : signature différente' ($a -ne (Get-PestoConfigurationSignature $dom))
} *>&1 | ForEach-Object { if($_ -is [Management.Automation.ErrorRecord]){$script:R.Add('ERREUR '+$_.Exception.Message)} } } catch { $script:R.Add('ERREUR '+$_.Exception.Message+' @ '+$_.InvocationInfo.ScriptLineNumber) }
$script:R
$f=@($script:R|Where-Object{$_ -like 'FAIL*' -or $_ -like 'ERREUR*'}).Count
'RESULTAT {0} reussis, {1} echecs' -f @($script:R|Where-Object{$_ -like 'PASS*'}).Count,$f
if($f){exit 1}

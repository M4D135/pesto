#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportDirectory=(Join-Path $env:TEMP ('Pesto-RC15-Test-'+[Guid]::NewGuid().ToString('N'))),[switch]$Capture)
# Tests isolés : définitions AST uniquement. Le moteur Pesto n'est jamais exécuté.
# Aucun compte AD, UAC, dsregcmd, jonction, renommage ou redémarrage réels.
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess){throw 'Windows PowerShell 5.1 x64 requis.'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Lancer TESTER.cmd ou powershell.exe -STA.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
[void][IO.Directory]::CreateDirectory($ReportDirectory)
$results=[Collections.Generic.List[object]]::new();$defs=@{};$asts=@{}
function Assert {param($Value,[string]$Why='Condition fausse');if(-not $Value){throw $Why}}
function Equal {param($Actual,$Expected);if($Actual -cne $Expected){throw "Attendu [$Expected], obtenu [$Actual]"}}
function Throws {param([scriptblock]$Body);$ok=$false;try{& $Body}catch{$ok=$true};Assert $ok 'Exception attendue'}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''});Write-Host ('OK '+$Name)}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host ('KO '+$Name+' : '+$_.Exception.Message)}}
Case 'Parseur Windows PowerShell de tous les composants de livraison' {
 foreach($file in @(Get-Item (Join-Path $root 'Pesto.ps1'))+@(Get-ChildItem (Join-Path $root 'wad') -Filter 'Pesto-*.ps1' -File)){
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw ($file.Name+': '+(($errors|ForEach-Object{[string]$_.Extent.StartLineNumber+' '+$_.Message}) -join '; '))}
  $asts[$file.Name]=$ast
  foreach($fn in @($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst]})){
   if($defs.ContainsKey($fn.Name)){throw ('Fonction répétée : '+$fn.Name)}
   $defs[$fn.Name]=$fn.Extent.Text
  }
 }
}
if(-not $asts.ContainsKey('Pesto-Core.ps1')){throw 'Arrêt : sources non analysées.'}
foreach($name in $defs.Keys){. ([scriptblock]::Create($defs[$name]))}
# Environment and non-persistent spies used by pure tests.
$script:GUI=$true;$Demo=$true;$script:SIM=$false;$script:Pesto_VERSION='17.0-RC15'
$script:PestoAppearanceMemory=@{};$script:AppearanceOwnerSid='S-1-5-21-1-2-3-1001'
function Write-Log {param($Message,$Level,$ErrorRecord,$Context)}
function Write-AuditLine {param($Text,$Kind)}
function Test-PestoIsAdministrator {return $true}
Case 'Empreintes du paquet, sans UAC ni lecture AD' { $p=Test-PestoPackage -Root $root;Assert $p.Valid;Equal $p.Version '17.0-RC15' }
Case 'EXE réellement PE x64 graphique et version RC15' {
 $path=Join-Path $root 'Pesto.exe';$bytes=[IO.File]::ReadAllBytes($path);$pe=[BitConverter]::ToInt32($bytes,60)
 Equal ([BitConverter]::ToUInt16($bytes,$pe+4)) 0x8664
 Equal ([BitConverter]::ToUInt16($bytes,$pe+24+68)) 2
 Equal ([Diagnostics.FileVersionInfo]::GetVersionInfo($path).FileVersion) '17.0.0.15'
}
Case 'Thèmes : trois valeurs nommées, stockage isolé de démonstration' {
 foreach($mode in @('Light','Dark','System')){Set-PestoAppearanceValue Theme $mode;Equal (Get-PestoAppearanceValue Theme) $mode}
 Throws {Set-PestoAppearanceValue Theme '0'}
}
Case 'Disposition bornée sans identifiants ou cibles' {
 $p=ConvertTo-PestoLayoutPreference ([pscustomobject]@{WindowWidth=99999;WindowHeight=1;Maximized=$true;LogFontSize=99;Password='CANARY';Domain='secret.local';Target='PC';HelpVisible='true'})
 Equal $p.WindowWidth 7680;Equal $p.WindowHeight 560;Equal $p.LogFontSize 22
 Assert (-not $p.PSObject.Properties['Password']);Assert (-not $p.PSObject.Properties['Target']);Assert (-not $p.PSObject.Properties['HelpVisible'])
}
$cfg1=[pscustomobject]@{Conf=@([pscustomobject]@{Domaine='example.local';DarkMode=0;Prefixe='111301';Buffer=10});OUBase=@([pscustomobject]@{Nom='ROOT';OU='OU=Postes,DC=example,DC=local'})}
Case 'Empreinte : apparence sans invalidation métier' {
 $c=$cfg1|ConvertTo-Json -Depth 8|ConvertFrom-Json;$a=Get-PestoConfigurationSignature $c
 $c.Conf[0].DarkMode=1;$c.Conf[0].Buffer=30
 Equal (Get-PestoConfigurationSignature $c) $a
 $c.Conf[0].Domaine='other.local';Assert ((Get-PestoConfigurationSignature $c) -ne $a)
}
Case 'Sauvegarde/relecture cfg : sombre et file restent inchangés' {
 $script:CFG=$cfg1;$script:CurrentTheme='Dark';$script:ThemeMode='Dark';$script:JsonFile='FAKE-NO-IO'
 $script:SetLblStatus=[pscustomobject]@{Text=''};$script:table=New-QueueTable
 $row=$script:table.NewRow();$row.Nom_du_PC='P111301PR765001';[void]$script:table.Rows.Add($row)
 function Get-Content {param($LiteralPath,[switch]$Raw,$Encoding);return ($cfg1|ConvertTo-Json -Depth 8)}
 function Test-CfgValid {param($Config);return @()}
 function Sync-PestoAppearanceControls {}
 function Set-Theme {param($Theme);throw 'Le rendu du thème ne doit pas être appelé lors de la relecture de configuration.'}
 Assert (Apply-CfgHot);Equal $script:CurrentTheme 'Dark';Equal $script:ThemeMode 'Dark';Equal $script:table.Rows.Count 1;Equal $row.Nom_du_PC 'P111301PR765001'
}
Case 'Changement métier : plans conservés et contrôles invalidés' {
 function Save-PestoQueueCheckpointSafe {}
 function Sync-Grid {}
 function Add-LogLine {param($Text,$Kind)}
 $oldName=$script:table.Rows[0].Nom_du_PC;Invalidate-PestoConfigurationPlans
 Equal $script:table.Rows[0].Nom_du_PC $oldName;Assert $script:table.Rows[0].NeedsReview
}
$guid='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';$machine='machine-1'
$plan=[pscustomobject]@{Nom_du_PC='P111301PR765001';Nouveau_Nom='P111301VA765001';Objet_GUID=$guid;OU_Actuelle='OU=Old,DC=example,DC=local';OU_Destination='OU=New,DC=example,DC=local';Domain='example.local';Renommer=$true;Deplacer=$true;Reboot=$false}
function Observation {param($P);[pscustomobject]@{ObservedUtc=[DateTime]::UtcNow.ToString('o');AD=[pscustomobject]@{Guid=$P.Objet_GUID;Name=$P.Nouveau_Nom;OU=$P.OU_Destination;Protected=$true};Windows=[pscustomobject]@{MachineId='machine-1';PartOfDomain=$true;Domain=$P.Domain;ActiveName=$P.Nouveau_Nom;ConfiguredName=$P.Nouveau_Nom}}}
foreach($case in @(@(20,$true,$false,'PendingRestart'),@(77,$true,$false,'PendingRestart'),@(89,$true,$false,'Partial'),@(32,$true,$false,'Protection'),@(96,$true,$false,'NotStarted'),@(97,$false,$false,'Uncertain'),@(30,$false,$false,'Verified'),@(30,$false,$true,'Uncertain'),@(21,$true,$false,'Failed'))){
 Case ('Résultat -> phase '+$case[0]+'/'+$case[2]) {Equal (Get-PestoDirectPhase -Code $case[0] -Rename $case[1] -TimedOut $case[2]) $case[3]}
}
Case 'Observation complète : vérifiable sans rejouer' {$o=Observation $plan;Assert (Get-PestoObservationDecision $plan $o $machine 97).Verified}
Case 'Mauvais GUID : aucune reprise' {$o=Observation $plan;$o.AD.Guid='11111111-1111-1111-1111-111111111111';$d=Get-PestoObservationDecision $plan $o $machine 89;Assert (-not $d.Verified -and -not $d.ResumeMove)}
Case 'Nom Windows en attente de redémarrage' {$o=Observation $plan;$o.Windows.ActiveName=$plan.Nom_du_PC;$d=Get-PestoObservationDecision $plan $o $machine 97;Assert $d.PendingRestart;Assert (-not $d.Verified)}
Case 'Nom AD seul insuffisant pour valider un renommage incertain' {$o=Observation $plan;$o.Windows=$null;$d=Get-PestoObservationDecision $plan $o $machine 97;Assert (-not $d.Verified)}
Case 'Mauvaise identité Windows : aucune levée' {$o=Observation $plan;$o.Windows.MachineId='other';Assert (-not (Get-PestoObservationDecision $plan $o $machine 97).Verified)}
Case 'Partiel 89 : proposer uniquement le déplacement' {$o=Observation $plan;$o.AD.OU=$plan.OU_Actuelle;$o.Windows=$null;$d=Get-PestoObservationDecision $plan $o '' 89;Assert $d.ResumeMove;Assert (-not $d.Verified)}
Case 'Protection absente après code32 : aucune levée' {$o=Observation $plan;$o.AD.Protected=$false;Assert (-not (Get-PestoObservationDecision $plan $o $machine 32).Verified)}
Case 'Ancien nom présent : pas une preuve d’’annulation' {$o=Observation $plan;$o.AD.Name=$plan.Nom_du_PC;$d=Get-PestoObservationDecision $plan $o $machine 97;Assert (-not $d.Verified -and -not $d.ResumeMove)}
Case 'Reprise directe : identités exactes et déplacement seul' {
 $old=[pscustomobject]@{Phase='Partial';OperationId='resume';Plan=$plan}
 $p=$plan|ConvertTo-Json|ConvertFrom-Json;$p.Nom_du_PC=$p.Nouveau_Nom;$p.Renommer=$false
 Assert (Test-PestoDirectResumePlan $old $p 'resume');$p.Renommer=$true;Assert (-not(Test-PestoDirectResumePlan $old $p 'resume'))
 $p.Renommer=$false;$p.Reboot=$true;Assert (-not(Test-PestoDirectResumePlan $old $p 'resume'))
}
Case 'Erreurs : distinction précontrôle / mutation possible' {
 $e=Get-PestoErrorExplanation 'RPC indisponible' 'Lecture' $false;Assert ($e.Effect -match 'Aucune commande')
 $e=Get-PestoErrorExplanation 'Timeout' 'Renommage' $true;Assert ($e.Effect -match 'relance')
}
Case 'Diagnostic : aucun texte libre ni secret du journal collecté' {
 $BasePath='';$script:BasePath='';$script:AuthUser='TEST\\PRIVATE';$script:DOMAINE='private.local';$script:DC='private-dc';$script:JsonFile='C:\private\cfg.json'
 $script:LogEntries=[Collections.Generic.List[object]]::new();$script:LogEntries.Add([pscustomobject]@{Time='12:00:00';Kind='err';Text='SECRET-CANARY-DO-NOT-EXPORT password=ABC'})
 $json=Get-PestoDiagnosticText -Redact $true
 Assert ($json -notmatch 'SECRET-CANARY|private.local|private-dc|DO-NOT-EXPORT|password=ABC')
 Assert ($json -match 'IdentitiesMasked');[void]($json|ConvertFrom-Json)
}
Case 'Démarrage léger : scan seulement derrière FullInventory' {
 $source=[IO.File]::ReadAllText((Join-Path $root 'wad\Pesto-Directory.ps1'))
 Assert ($source -match 'if\(\[bool\]\$Request.FullInventory\)')
 Assert ($defs['New-PestoDirectorySnapshotRequest'] -notmatch 'FullInventory\s*=\s*\$true')
}
Case 'Saisie de poste : pas de démarrage réseau implicite' {
 Assert ($defs['Request-PestoUxComputerLookup'] -notmatch 'PCProbeTimer\.Start|Start-PestoAsyncOperation|Select-PCName')
}
Case 'Parcours direct : aucune insertion de DataRow' {
 $source=[IO.File]::ReadAllText((Join-Path $root 'wad\Pesto-Direct.ps1'))
 Assert ($source -notmatch 'Rows\.Add|Add-OrUpdateQueue|Run-Queue|Start-PestoNextQueueTask')
}
Case 'Retour tardif : jamais traité en succès UI' {
 Assert ($defs['Invoke-PestoAsyncTimerTick'] -match "'DirectAction'")
 Assert ($defs['Invoke-PestoAsyncTimerTick'] -match 'TimeoutReported')
}
function Save-PestoTestCapture {
 param($Window,[string]$Path)
 $Window.UpdateLayout();$width=[int][Math]::Ceiling($Window.ActualWidth);$height=[int][Math]::Ceiling($Window.ActualHeight)
 $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($Window)
 $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
 $stream=[IO.File]::Create($Path);try{$encoder.Save($stream)}finally{$stream.Dispose()}
}

# Real WPF parsing/layout, not a screenshot mockup. No Pesto startup code executed.
$windows=[Collections.Generic.List[object]]::new()
Case 'WPF : shell, ressources et jonction dédiés' {
 Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xml
 $script:Win=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad\Pesto-Shell.xaml')))
 $windows.Add($script:Win)
 $script:JoinPage=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'wad\Pesto-Join.xaml')))
 $script:Win.FindName('UxJoinHost').Content=$script:JoinPage
 Equal $script:Win.FindName('MainTabs').Items.Count 8
 foreach($key in @('Card','BtnRun','FgText','FgMuted','OkFg','WarnFg','ErrFg')){Assert ($script:Win.Resources.Contains($key)) ('Ressource absente : '+$key)}
 foreach($name in @('SuiteNavToggle','SuiteDirectRun','SuiteDirectCheck','SuiteDirectVerify','SuitePostState','SuiteHelpClose','SuiteLogFollow','SuiteLogWrap')){
  $c=$script:Win.FindName($name);Assert $c ('Contrôle absent : '+$name);Assert $c.ToolTip;Assert ([Windows.Controls.ToolTipService]::GetShowOnDisabled($c))
 }
}
Case 'WPF : login compact, saisie et thèmes' {
 Assert $script:Win
 $source=$defs['Show-LoginWindow'];$match=[regex]::Match($source,'(?s)\[xml\]\$[\w]+\s*=\s*@[''"]\r?\n(.*?)\r?\n[''"]@')
 Assert $match.Success 'XAML connexion absent'
 $xml=$match.Groups[1].Value
 Assert ($xml -notmatch '\$t\[') 'Couleurs non dynamiques restantes'
 $themesNode=$asts['Pesto-Core.ps1'].EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$script:Themes'}|Select-Object -First 1
 Assert $themesNode 'Palettes absentes';. ([scriptblock]::Create($themesNode.Extent.Text))
 foreach($theme in @('Light','Dark')){
  foreach($k in $script:Themes[$theme].Keys){$script:Win.Resources[$k]=[Windows.Media.BrushConverter]::new().ConvertFromString([string]$script:Themes[$theme][$k])}
  $w=[Windows.Markup.XamlReader]::Parse($xml);$windows.Add($w);$w.Resources=$script:Win.Resources
  $w.Title='APERÇU TEST · '+$theme;$w.ShowInTaskbar=$false;$w.MaxHeight=[Windows.SystemParameters]::WorkArea.Height-24
  Equal $w.ResizeMode ([Windows.ResizeMode]::NoResize)
  $w.Show();$w.UpdateLayout()
  [xml]$doc=$xml
  foreach($node in $doc.SelectNodes('//*[@*[local-name()="Name"]]')){
   $name=$node.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml');$c=$w.FindName($name)
   if($c -is [Windows.Controls.TextBox] -and -not $c.IsReadOnly){$c.Text='compte-test';$c.ApplyTemplate()|Out-Null;Assert ($c.ActualHeight -ge 40) 'Champ trop petit'}
   if($c -is [Windows.Controls.PasswordBox]){$c.Password='FAKE-VISUAL-TEST';$c.ApplyTemplate()|Out-Null;Assert ($c.ActualHeight -ge 40) 'Mot de passe trop petit';$c.Clear()}
  }
  $w.UpdateLayout()
  if($Capture){Save-PestoTestCapture -Window $w -Path (Join-Path $ReportDirectory ('login-'+$theme+'.png'))}
  $w.Close()
 }
}
Case 'WPF : pages en plusieurs largeurs et agrandissements de contenu' {
 Assert $script:Win
 $w=$script:Win;$w.ShowInTaskbar=$false;$w.MinWidth=600;$w.MinHeight=480;$w.Show()
 foreach($size in @(1024,1366,1600)){
  $w.Width=[Math]::Min($size,[Windows.SystemParameters]::WorkArea.Width-24);$w.Height=[Math]::Min(850,[Windows.SystemParameters]::WorkArea.Height-24)
  foreach($scale in @(1.0,1.25,1.5)){
   # ScaleTransform tests a larger content layout, not a real change of monitor DPI.
   $w.Content.LayoutTransform=[Windows.Media.ScaleTransform]::new($scale,$scale)
   foreach($tab in @(0,2,3,7)){
    $w.FindName('MainTabs').SelectedIndex=$tab;$w.UpdateLayout()
    Assert ($w.ActualWidth -gt 0 -and $w.ActualHeight -gt 0)
    if($Capture){Save-PestoTestCapture $w (Join-Path $ReportDirectory ('page-'+$tab+'-'+$size+'-'+([string]$scale).Replace(',','.').Replace('.','_')+'.png'))}
   }
  }
 }
 $w.Close()
}
foreach($w in $windows){try{$w.Close()}catch{}}
$failed=@($results|Where-Object{-not $_.Passed}).Count
$out=Join-Path $ReportDirectory 'windows-rc15.json'
[pscustomobject]@{Version='17.0-RC15';Utc=[DateTime]::UtcNow.ToString('o');NoRealAD=$true;Failed=$failed;Checks=$results.ToArray();Note='Les mesures WPF et captures ne remplacent pas une recette de fonctionnement sur domaine de test.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ('Rapport : '+$out)
Write-Warning 'Aucune validation d’’une mutation Windows/AD réelle. Une recette sur VM reste nécessaire.'
if($failed){exit 1}else{exit 0}

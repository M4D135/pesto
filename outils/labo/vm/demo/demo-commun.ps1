# Commun aux étapes de la démo réelle : fenêtre principale de Pesto, agrandissement, capture de la fenêtre seule.
$D = 'C:\PestoTest-preuves\demo-reelle\captures'; New-Item -ItemType Directory -Force $D | Out-Null
function Get-Pesto { Wait-Fenetre 'Pesto 1\.0$' 60 }
function Set-Agrandie($w) { Set-Premier $w; [void][PNat]::ShowWindow([IntPtr]$w.Current.NativeWindowHandle, 3); Start-Sleep -Seconds 2 }
function Save-Fenetre($w, [string]$Fichier) {
  Set-Premier $w; Start-Sleep -Milliseconds 700
  $r = $w.Current.BoundingRectangle
  # Fenêtre agrandie : le cadre déborde de quelques pixels ; on garde la partie visible, barre de titre comprise.
  $x = [Math]::Max(0, [int]$r.X); $y = [Math]::Max(0, [int]$r.Y)
  $sw = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $wd = [Math]::Min([int]$r.Width - ($x - [int]$r.X), $sw.Width - $x); $ht = [Math]::Min([int]$r.Height - ($y - [int]$r.Y), $sw.Height - $y)
  $bmp = New-Object System.Drawing.Bitmap $wd, $ht; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size); $bmp.Save($Fichier, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
  "capture $Fichier ${wd}x$ht"
}
function Get-El($w, [string]$Nom, [string]$Type = '') { Find-Element $w $Nom $Type }
function Click($w, [string]$Nom, [string]$Type = '') {
  $e = Find-Element $w $Nom $Type
  if (-not $e) { throw "élément introuvable : $Nom" }
  Invoke-Element $e | Out-Null; Start-Sleep -Milliseconds 800; "clic : $Nom"
}
function Find-Id($w, [string]$Id) { $w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id))) }
function Click-Id($w, [string]$Id, [int]$Delai = 20) { $fin=(Get-Date).AddSeconds($Delai); do { $e = Find-Id $w $Id; if ($e -and $e.Current.IsEnabled) { break }; Start-Sleep -Milliseconds 600 } while ((Get-Date) -lt $fin); if (-not $e) { throw "élément introuvable : #$Id" }; if (-not $e.Current.IsEnabled) { throw "élément inactif : #$Id ($($e.Current.Name))" }; Invoke-Element $e | Out-Null; Start-Sleep -Milliseconds 900; "clic : #$Id ($($e.Current.Name))" }
function Wait-Enabled($w, [string]$Id, [int]$Delai = 60) { $fin=(Get-Date).AddSeconds($Delai); while((Get-Date) -lt $fin){ $e=Find-Id $w $Id; if($e -and $e.Current.IsEnabled){return $e}; Start-Sleep -Milliseconds 700 }; throw "#$Id resté inactif" }
function Set-Combo($w, [string]$Id, [string]$Texte) {
  $c = Wait-Enabled $w $Id 90
  $p = $null
  if ($Texte -and $c.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$p) -and -not $p.Current.IsReadOnly) { $p.SetValue($Texte); Start-Sleep -Milliseconds 900; return "#$Id = $Texte (saisie)" }
  $x = $null; if ($c.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$x)) { $x.Expand(); Start-Sleep -Milliseconds 700 }
  $items = @($c.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem))))
  $cible = if ($Texte) { $items | Where-Object { $_.Current.Name -eq $Texte } | Select-Object -First 1 } else { $items | Select-Object -First 1 }
  if (-not $cible) { if ($x) { $x.Collapse() }; throw "#$Id : « $Texte » absent (choix : $(($items | ForEach-Object { $_.Current.Name }) -join ' | '))" }
  $s = $null; [void]$cible.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$s); $s.Select(); Start-Sleep -Milliseconds 500
  if ($x) { try { $x.Collapse() } catch {} }; Start-Sleep -Milliseconds 900
  "#$Id = $($cible.Current.Name)"
}
function Wait-Texte($w, [string]$Motif, [int]$Delai = 120) { $fin=(Get-Date).AddSeconds($Delai); while((Get-Date) -lt $fin){ foreach($e in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text)))){ if($e.Current.Name -match $Motif){return $e} }; Start-Sleep -Milliseconds 800 }; $null }
function Get-PanelText($w) { $b = Find-Id $w 'PanelBody'; if ($b) { $p=$null; if ($b.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$p)) { return $p.Current.Value } }; '' }

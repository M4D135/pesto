# Observe une fenêtre : titre, motifs de fenêtre, UAC, connexions au DC, processus, capture, arbre UIA.
param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$Motif,[int]$Delai=120,[int]$Prof=7)
Import-Module C:\PestoTest-run\pilote.psm1
$D = 'C:\PestoTest-preuves\phase2'; New-Item -ItemType Directory -Force $D | Out-Null
& {
  $w = Wait-Fenetre $Motif $Delai
  if (-not $w) { 'FENETRE ABSENTE : ' + $Motif; Get-Fenetres | Format-Table -AutoSize | Out-String -Width 200; Save-Ecran "$D\$Id-absente.png"; return }
  Start-Sleep 3
  'titre : ' + $w.Current.Name
  'rect : ' + $w.Current.BoundingRectangle
  $wp = $null
  if ($w.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$wp)) { 'CanMaximize={0} CanMinimize={1} Etat={2}' -f $wp.Current.CanMaximize, $wp.Current.CanMinimize, $wp.Current.WindowVisualState }
  'consent.exe (UAC) : ' + [bool](Get-Process consent -ErrorAction SilentlyContinue)
  'connexions TCP vers le DC : ' + @(Get-NetTCPConnection -RemoteAddress 10.77.0.10 -ErrorAction SilentlyContinue).Count
  Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'Pesto|powershell' } | ForEach-Object { '{0} {1} {2}' -f $_.ProcessId, $_.Name, $_.CommandLine }
  Save-Ecran "$D\$Id.png"
  '--- arbre UIA'
  Get-Arbre $w $Prof
} *> "$D\$Id.txt"

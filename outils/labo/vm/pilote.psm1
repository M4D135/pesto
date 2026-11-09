# Outils de pilotage dans la session interactive : capture, UI Automation, clavier.
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class PNat{[DllImport("user32.dll")]public static extern bool SetProcessDPIAware();[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int c);[DllImport("user32.dll")]public static extern bool IsIconic(IntPtr h);[DllImport("user32.dll",SetLastError=true)]public static extern IntPtr OpenInputDesktop(uint f,bool inherit,uint access);[DllImport("user32.dll",SetLastError=true,CharSet=CharSet.Unicode)]public static extern bool GetUserObjectInformation(IntPtr h,int index,System.Text.StringBuilder value,uint length,out uint needed);[DllImport("user32.dll")]public static extern bool CloseDesktop(IntPtr h);[DllImport("user32.dll")]public static extern void keybd_event(byte k,byte s,uint f,UIntPtr e);}'
[void][PNat]::SetProcessDPIAware()
$script:A = [System.Windows.Automation.AutomationElement]
$script:T = [System.Windows.Automation.TreeScope]
# Une session existante ne signifie pas que son bureau est déverrouillé.
# Refuser les gestes en arrière-plan et les captures de Winlogon comme preuves GUI.
function Assert-PestoInteractiveDesktop {
  $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
  if ($session -eq 0) { throw 'Recette GUI bloquée : session 0, sans bureau interactif.' }
  # Une tâche élevée peut encore ouvrir Default alors que LogonUI couvre la console.
  if (Get-Process LogonUI -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session }) { throw 'Recette GUI bloquée : écran de connexion présent dans cette session. Déverrouiller la console.' }
  $desktop = [PNat]::OpenInputDesktop(0, $false, 1)
  if ($desktop -eq [IntPtr]::Zero) { throw ('Recette GUI bloquée : bureau actif inaccessible ou verrouillé (Windows {0}). Déverrouiller la session.' -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) }
  try {
    $name = New-Object Text.StringBuilder 256
    [uint32]$needed = 0
    if (-not [PNat]::GetUserObjectInformation($desktop, 2, $name, 512, [ref]$needed)) { throw 'Recette GUI bloquée : impossible de vérifier le bureau actif.' }
    if ($name.ToString() -ne 'Default') { throw ('Recette GUI bloquée : bureau actif {0}. Déverrouiller la session ou traiter le dialogue sécurisé.' -f $name) }
  } finally { [void][PNat]::CloseDesktop($desktop) }
}
function Save-Ecran([string]$Fichier) {
  Assert-PestoInteractiveDesktop
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = $null
  try {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    Assert-PestoInteractiveDesktop
    $bmp.Save($Fichier, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { if ($g) { $g.Dispose() }; $bmp.Dispose() }
  "capture $Fichier $($b.Width)x$($b.Height)"
}
function Get-Fenetres { $script:A::RootElement.FindAll($script:T::Children, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $c = $_.Current; [pscustomobject]@{Nom=$c.Name; Pid=$c.ProcessId; Classe=$c.ClassName; Rect=$c.BoundingRectangle.ToString()} } }
function Wait-Fenetre([string]$Motif, [int]$Delai = 60) {
  $fin = (Get-Date).AddSeconds($Delai)
  while ((Get-Date) -lt $fin) { foreach ($w in $script:A::RootElement.FindAll($script:T::Children, [System.Windows.Automation.Condition]::TrueCondition)) { if ($w.Current.Name -match $Motif -and $w.Current.ClassName -ne 'ConsoleWindowClass' -and $w.Current.Name -notmatch 'Initialisation') { return $w } }; Start-Sleep -Milliseconds 500 }
  return $null
}
function Get-Arbre($Racine, [int]$Profondeur = 6, [int]$Niveau = 0) {
  if ($Niveau -gt $Profondeur) { return }
  $w = [System.Windows.Automation.TreeWalker]::ControlViewWalker; $e = $w.GetFirstChild($Racine)
  while ($e) { $c = $e.Current
    $ligne = ('  ' * $Niveau) + $c.ControlType.ProgrammaticName.Replace('ControlType.','') + ' "' + $c.Name + '"'
    if ($c.AutomationId) { $ligne += ' #' + $c.AutomationId }
    if (-not $c.IsEnabled) { $ligne += ' [inactif]' }
    if ($c.IsOffscreen) { $ligne += ' [hors-ecran]' }
    $ligne; Get-Arbre $e $Profondeur ($Niveau + 1); $e = $w.GetNextSibling($e) }
}
function Find-Element($Racine, [string]$Nom, [string]$Type = '') {
  foreach ($e in $Racine.FindAll($script:T::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
    if ($e.Current.Name -eq $Nom -and (-not $Type -or $e.Current.ControlType.ProgrammaticName -eq ('ControlType.' + $Type))) { return $e } }
  return $null
}
function Invoke-Element($e) {
  Assert-PestoInteractiveDesktop
  $p = $null
  if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return 'invoke' }
  if ($e.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $p.Select(); return 'select' }
  if ($e.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { $p.Toggle(); return 'toggle' }
  if ($e.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$p)) { $p.Expand(); return 'expand' }
  return 'aucun motif'
}
function Set-Premier($Fenetre) {
  Assert-PestoInteractiveDesktop
  $h = [IntPtr]$Fenetre.Current.NativeWindowHandle
  [PNat]::keybd_event(0x12, 0, 0, [UIntPtr]::Zero); [PNat]::keybd_event(0x12, 0, 2, [UIntPtr]::Zero)
  if ([PNat]::IsIconic($h)) { [void][PNat]::ShowWindow($h, 9) }; [void][PNat]::SetForegroundWindow($h); try { $Fenetre.SetFocus() } catch {}; Start-Sleep -Milliseconds 300
}
function Send-Touches($Fenetre, [string]$Touches) { Set-Premier $Fenetre; [System.Windows.Forms.SendKeys]::SendWait($Touches); Start-Sleep -Milliseconds 400 }
function Get-Focus { $f = $script:A::FocusedElement; if ($f) { $c = $f.Current; '{0} "{1}" #{2}' -f $c.ControlType.ProgrammaticName, $c.Name, $c.AutomationId } }
Export-ModuleMember -Function *

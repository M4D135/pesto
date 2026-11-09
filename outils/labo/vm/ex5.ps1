Import-Module C:\PestoTest-run\pilote.psm1
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class PIn{[DllImport("user32.dll")]public static extern void keybd_event(byte k,byte s,uint f,UIntPtr e);[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();}'
$D = 'C:\PestoTest-preuves\phase2'
function CtrlK { [PIn]::keybd_event(0x11,0,0,[UIntPtr]::Zero); [PIn]::keybd_event(0x4B,0,0,[UIntPtr]::Zero); [PIn]::keybd_event(0x4B,0,2,[UIntPtr]::Zero); [PIn]::keybd_event(0x11,0,2,[UIntPtr]::Zero); Start-Sleep 3 }
function Touche([byte]$vk) { [PIn]::keybd_event($vk,0,0,[UIntPtr]::Zero); [PIn]::keybd_event($vk,0,2,[UIntPtr]::Zero); Start-Sleep 2 }
function Ouverte($w) { [bool]$w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'PanelSearch'))) }
function Id($r,$id){ $r.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id))) }
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class HC{[StructLayout(LayoutKind.Sequential)]public struct HIGHCONTRAST{public int cbSize;public int dwFlags;public IntPtr lpszDefaultScheme;}[DllImport("user32.dll",SetLastError=true)]public static extern bool SystemParametersInfo(int a,int p,ref HIGHCONTRAST v,int w);public static int Get(){HIGHCONTRAST h=new HIGHCONTRAST();h.cbSize=Marshal.SizeOf(h);SystemParametersInfo(0x42,h.cbSize,ref h,0);return h.dwFlags;}public static bool Set(bool on){return Set(on?127:126);}public static bool Set(int f){HIGHCONTRAST h=new HIGHCONTRAST();h.cbSize=Marshal.SizeOf(h);h.dwFlags=f;return SystemParametersInfo(0x43,h.cbSize,ref h,2);}}'
function Id($r,$id){ $r.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id))) }
& {
  $w = Wait-Fenetre '^Pesto 1\.0 \|' 60; if (-not $w) { 'FENETRE ABSENTE'; return }
  'Parametres : ' + (Invoke-Element (Id $w 'NavSettings')); Start-Sleep 6
  $c = Id $w 'SetCmbDarkMode'; $p = $null; if ($c.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$p)) { $p.Expand(); Start-Sleep 2 }
  $s = @($c.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))) | Where-Object { $_.Current.Name -match 'Suivre' } | Select-Object -First 1
  if ($s) { $s.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); 'Suivre Windows' }; if ($p) { try { $p.Collapse() } catch {} }
  'Accueil : ' + (Invoke-Element (Id $w 'NavHome')); Start-Sleep 4
  'contraste : ' + [HC]::Set($true); Start-Sleep 30
  $r = $w.Current.BoundingRectangle; [void][PIn]::SetCursorPos([int]($r.X + 90), [int]($r.Y + 205)); Start-Sleep 3
  Save-Ecran "$D\x5-contraste-survol.png"
  Touche 0x09; Start-Sleep 2; Touche 0x09; Start-Sleep 2; 'focus : ' + (Get-Focus); Save-Ecran "$D\x5-contraste-focus.png"
  [void][PIn]::SetCursorPos(5, 5)
  'retour : ' + [HC]::Set($false) + ' flags=' + [HC]::Get(); Start-Sleep 25
  Save-Ecran "$D\x5-retour.png"
} *> "$D\x5.txt"

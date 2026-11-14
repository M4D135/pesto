Import-Module C:\PestoTest-run\pilote.psm1
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class PIn{[DllImport("user32.dll")]public static extern void keybd_event(byte k,byte s,uint f,UIntPtr e);[DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);[DllImport("user32.dll")]public static extern void mouse_event(uint f,uint x,uint y,uint d,UIntPtr e);[DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();}'
$D = 'C:\PestoTest-preuves\2026-10-04-final'
function CtrlK { [PIn]::keybd_event(0x11,0,0,[UIntPtr]::Zero); [PIn]::keybd_event(0x4B,0,0,[UIntPtr]::Zero); [PIn]::keybd_event(0x4B,0,2,[UIntPtr]::Zero); [PIn]::keybd_event(0x11,0,2,[UIntPtr]::Zero); Start-Sleep 3 }
function Touche([byte]$vk) { [PIn]::keybd_event($vk,0,0,[UIntPtr]::Zero); [PIn]::keybd_event($vk,0,2,[UIntPtr]::Zero); Start-Sleep 2 }
function Ouverte($w) { [bool]$w.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'PanelSearch'))) }
function Id($r,$id){ $r.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id))) }
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class HC{[StructLayout(LayoutKind.Sequential)]public struct HIGHCONTRAST{public int cbSize;public int dwFlags;public IntPtr lpszDefaultScheme;}[DllImport("user32.dll",SetLastError=true)]public static extern bool SystemParametersInfo(int a,int p,ref HIGHCONTRAST v,int w);public static int Get(){HIGHCONTRAST h=new HIGHCONTRAST();h.cbSize=Marshal.SizeOf(h);SystemParametersInfo(0x42,h.cbSize,ref h,0);return h.dwFlags;}public static bool Set(bool on){return Set(on?127:126);}public static bool Set(int f){HIGHCONTRAST h=new HIGHCONTRAST();h.cbSize=Marshal.SizeOf(h);h.dwFlags=f;return SystemParametersInfo(0x43,h.cbSize,ref h,2);}}'
function Id($r,$id){ $r.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id))) }
& {
 $app=Start-Process C:\PestoTest\Pesto.exe -ArgumentList '-Demo' -PassThru
 $handle=$app.Handle
 $w=Wait-Fenetre '^Pesto 1\.0 \|' 180
 if(-not $w){throw 'Fenetre absente'}
 $original=[HC]::Get()
 "Debut : $(Get-Date -Format o), flags=$original, pid=$($app.Id)"
 try {
  Invoke-Element (Id $w 'NavSettings');Start-Sleep 4
  $c=Id $w 'SetCmbDarkMode';$p=$null
  if($c.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$p)){$p.Expand();Start-Sleep 1}
  $s=@($c.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))) | Where-Object {$_.Current.Name -match 'Suivre'} | Select-Object -First 1
  if(-not $s){throw 'Option Suivre Windows absente'}
  $s.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
  if($p){try{$p.Collapse()}catch{}}
  if(-not [HC]::Set($true)){throw 'Contraste non active'}
  Start-Sleep 12
  [void][PIn]::SetCursorPos(1800,900)
  Get-Arbre $w 9 | Out-File "$D\x5-onglet-arbre.txt" -Encoding utf8 -Width 240
  Save-Ecran "$D\x5-onglet-actif.png"
  "Contraste effectif : $([HC]::Get())"
 }finally{
  [void][HC]::Set($original);Start-Sleep 3
  "Contraste restaure : $([HC]::Get())"
 }
 Save-Ecran "$D\x5-onglet-retour.png"
} *> "$D\x5-onglet.txt"

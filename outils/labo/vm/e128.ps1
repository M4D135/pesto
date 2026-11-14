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
  $p1 = Start-Process C:\PestoTest\Pesto.exe -ArgumentList '-Demo' -PassThru
  $w = Wait-Fenetre '^Pesto 1\.0 \|' 240; 'premiere instance : ' + [bool]$w
  Start-Sleep 20
  $p2 = Start-Process C:\PestoTest\Pesto.exe -ArgumentList '-Demo' -PassThru
  $m = Wait-Fenetre 'Deja ouvert|déjà ouvert' 60; 'message deja ouvert : ' + $(if ($m) { $m.Current.Name } else { 'absent' })
  if ($m) { Save-Ecran "$D\l4-128.png"; Send-Touches $m '{ENTER}' }
  if ($p2.WaitForExit(30000)) { 'seconde instance, code : ' + $p2.ExitCode } else { 'seconde instance toujours active' }
} *> "$D\l4-128.txt"

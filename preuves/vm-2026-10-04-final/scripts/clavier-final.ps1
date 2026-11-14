$ErrorActionPreference='Stop'
Import-Module C:\PestoTest-run\pilote.psm1
$D='C:\PestoTest-preuves\2026-10-04-final'
function Id($r,$n){$r.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,$n)))}
try {
 $w=Wait-Fenetre '^Pesto 1\.0 \|' 30
 if(-not $w){throw 'Pesto demo absent'}
 "Debut : $(Get-Date -Format o)"
 foreach($n in 1..4){
  [void][PNat]::SetForegroundWindow([IntPtr]$w.Current.NativeWindowHandle)
  [PNat]::keybd_event(0x11,0,0,[UIntPtr]::Zero)
  [PNat]::keybd_event([byte](0x30+$n),0,0,[UIntPtr]::Zero)
  [PNat]::keybd_event([byte](0x30+$n),0,2,[UIntPtr]::Zero)
  [PNat]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
  Start-Sleep 3
  "Ctrl+$n"
  Get-Arbre $w 5 | Out-File "$D\clavier-natif-ctrl$n-arbre.txt" -Width 240 -Encoding utf8
  Save-Ecran "$D\clavier-natif-ctrl$n.png"
 }
 Save-Ecran "$D\clavier-natif-ctrl4.png"
} catch {$_ | Format-List * -Force | Out-File "$D\clavier-natif-erreur.txt" -Encoding utf8;throw}

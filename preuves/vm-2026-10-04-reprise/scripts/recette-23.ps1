$ErrorActionPreference='Stop'
Import-Module C:\PestoTest-run\pilote.psm1
$D='C:\PestoTest-preuves\2026-10-04-reprise'
function ById($w,$id){$w.FindFirst([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,$id))}
try { & {
 Get-Date -Format o
 'Utilisateur='+[Environment]::UserName
 'Etat GP avant='+[bool](Test-Path "$env:LOCALAPPDATA\GP")+'; registre GP='+[bool](Test-Path 'HKCU:\Software\GP')
 $before=(Get-FileHash C:\PestoTest\wad\cfg.json).Hash
 $p=Start-Process cmd.exe -ArgumentList '/d /c "echo.|C:\PestoTest\APERCU_LOGIN.cmd"' -WindowStyle Hidden -PassThru -RedirectStandardOutput "$D\2.3-cmd-stdout.txt" -RedirectStandardError "$D\2.3-cmd-stderr.txt"
 $null=$p.Handle
 'CmdPid='+$p.Id
 $w=Wait-Fenetre 'TEST LOCAL SANS AD$' 240
 if(-not $w){throw 'Apercu absent'}
 'Titre='+$w.Current.Name+'; Pid='+$w.Current.ProcessId
 $wp=$w.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern)
 'CanMaximize='+$wp.Current.CanMaximize
 if($wp.Current.CanMaximize){throw 'Fenetre maximisable'}
 $u=ById $w 'TxtUser';$pw=ById $w 'TxtPwd';$ok=ById $w 'BtnOk';$windows=ById $w 'BtnWindows';$close=ById $w 'BtnCancel'
 if(-not $u -or -not $pw -or -not $close){throw 'Champs manquants'}
 if($ok.Current.IsEnabled -or $windows.Current.IsEnabled){throw 'Authentification active dans un apercu'}
 'Authentification desactivee=True; champ masque='+$pw.Current.IsPassword
 $v=$u.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern);$v.SetValue('TEST\PestoRecette')
 if($v.Current.Value -ne 'TEST\PestoRecette'){throw 'Saisie fictive non relue'}
 # Cliquer la barre de titre pour placer cette fenetre au premier plan.
 $rect=$w.Current.BoundingRectangle
 & C:\PestoTest-run\cliquer-recette.ps1 -X ([int]($rect.Left+100)) -Y ([int]($rect.Top+15))
 Start-Sleep -Seconds 2
 Get-Arbre $w 7
 Save-Ecran "$D\2.3-login.png"
 $close.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
 if(-not $p.WaitForExit(30000)){throw 'Apercu ferme, mais cmd encore actif'}
 'ExitCode='+$p.ExitCode
 if($p.ExitCode -ne 0){throw 'Code apercu non nul'}
 $after=(Get-FileHash C:\PestoTest\wad\cfg.json).Hash
 'Configuration inchangee='+($before -eq $after)
 'Etat GP apres='+[bool](Test-Path "$env:LOCALAPPDATA\GP")+'; registre GP='+[bool](Test-Path 'HKCU:\Software\GP')
 if($before -ne $after -or (Test-Path "$env:LOCALAPPDATA\GP") -or (Test-Path 'HKCU:\Software\GP')){throw 'Etat local inattendu apres apercu'}
 'RESULTAT=PASS'
} | Out-File "$D\2.3-login.txt" -Encoding utf8
}catch{$_ | Out-String | Out-File "$D\2.3-login.txt" -Encoding utf8 -Append;exit 1}

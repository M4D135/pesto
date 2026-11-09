$ErrorActionPreference='Stop'
Import-Module C:\PestoTest-run\pilote.psm1
$D='C:\PestoTest-preuves\2026-10-04-reprise'
& {
 Get-Date -Format o
 $w=Wait-Fenetre '^Pesto 1\.0 \| Demarrage$' 10
 if(-not $w -or $w.Current.ProcessId -ne 3816){throw 'Fenetre du test initial absente'}
 $p=Get-Process -Id 3816
 $null=$p.Handle
 'PID='+$p.Id
 Get-Arbre $w 6
 Save-Ecran "$D\2.11-erreur-120-visible.png"
 & C:\PestoTest-run\cliquer-recette.ps1 -X 1091 -Y 594
 if(-not $p.WaitForExit(30000)){throw 'Processus encore actif'}
 'ExitCode='+$p.ExitCode
 if($p.ExitCode -ne 120){throw 'Code different de 120'}
 'RESULTAT=PASS'
} | Out-File "$D\2.11-completion.txt" -Encoding utf8

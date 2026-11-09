#requires -Version 5.1
[CmdletBinding()]
param()
# VERIFIER_UAC.cmd (pack DEV) : vraie demande d'UAC par le vrai Pesto.exe et les composants intacts du dossier.
# Aucune copie, aucun composant remplacé, aucun manifeste reconstruit : le lanceur vérifie ses empreintes comme en
# production. La sonde est un jeton aléatoire posé dans PESTO_UAC_PROBE pour les seuls processus lancés ici ;
# Pesto-Startup.ps1 le lit avant l'UAC et le transmet au relais élevé (-UacProbe), qui s'arrête avant la reprise
# d'état, le mutex de session et Pesto-Core : aucun moteur, aucune connexion AD, aucune action.
#
# PASS prouve : Pesto.exe accepte les composants de ce dossier ; la sonde traverse ce Pesto.exe jusqu'à
# Pesto-Startup.ps1 (contrôle --check-json préalable, sans UAC) ; un lancement normal, sans argument, demande
# l'élévation ; le relais tourne avec un jeton administrateur et son code 0 remonte jusqu'au lanceur ; l'opérateur
# déclare avoir vu la demande de Windows.
# Ne prouve pas : le chargement élevé de Pesto-Core, la fenêtre principale, la connexion Windows ou AD, la reprise
# d'état entre deux comptes (Import-PestoStartupState), la signature de Pesto.exe ; l'affichage de l'invite est
# déclaré par l'opérateur, non mesuré.
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){throw 'Windows PowerShell 5.1 x64 requis.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$exe=Join-Path $root 'Pesto.exe'
if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Pesto.exe absent : lancer VERIFIER_UAC.cmd depuis le pack DEV complet.'}

$id=[Security.Principal.WindowsIdentity]::GetCurrent()
try{$admin=([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);$account=$id.Name}finally{$id.Dispose()}
if($admin){throw 'Session déjà élevée (console administrateur, UAC désactivée ou compte Administrateur intégré) : Windows ne demanderait pas l''UAC et le test ne prouverait rien. Relancer VERIFIER_UAC.cmd par double-clic depuis une session non élevée.'}
$policy=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue
if($policy -and $policy.EnableLUA -eq 0){throw 'UAC désactivée (EnableLUA=0) : aucune demande ne peut apparaître ; test sans objet.'}

# Même contrôle que le produit, sur le dossier réel ; rien n'est réécrit.
. (Join-Path $root 'wad\Pesto-Integrity.ps1')
[void](Test-PestoPackage -Root $root)

$probe=[Guid]::NewGuid().ToString('N')
function Start-PestoProbeLauncher {
    param([string[]]$Arguments)
    $info=[Diagnostics.ProcessStartInfo]::new($exe)
    $info.UseShellExecute=$false
    $info.WorkingDirectory=$env:SystemRoot
    # Posée pour ce seul processus enfant : ni cette console ni la session ne la conservent.
    $info.EnvironmentVariables['PESTO_UAC_PROBE']=$probe
    if($Arguments){$info.Arguments=(@($Arguments|ForEach-Object{'"'+$_+'"'}) -join ' ')}
    $process=[Diagnostics.Process]::Start($info)
    try{$process.WaitForExit();return [int]$process.ExitCode}finally{$process.Dispose()}
}

# 1. Sans UAC : le lanceur doit accepter les composants ET la sonde doit atteindre Pesto-Startup.ps1.
#    Sinon arrêt avant toute UAC, pour ne jamais ouvrir le vrai moteur élevé à la place de la sonde.
$check=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-sonde-uac-'+$probe+'-check.json')
$code=Start-PestoProbeLauncher @('--check-json',$check)
if($code -ne 0 -or -not(Test-Path -LiteralPath $check -PathType Leaf)){
    # Codes 120 à 139 : refus du lanceur (docs\V1_GUIDE.md, « Codes de sortie de Pesto.exe ») ; autres : Windows PowerShell.
    $cause='contrôle du pack en échec dans Windows PowerShell'
    if($code -eq 125){$cause='empreintes refusées par Pesto.exe : composant absent, modifié ou lié'}
    elseif($code -eq 126){$cause='verrou de mise à jour présent : ne pas l''effacer'}
    elseif($code -ge 120 -and $code -le 139){$cause='refus ou erreur du lanceur'}
    elseif($code -eq 0){$cause='code 0 mais rapport --check-json absent'}
    throw ('Contrôle préalable refusé (code '+$code+' : '+$cause+'). Lancer Pesto.exe --check pour voir la cause ; après une modification de wad\, reconstruire Pesto.exe puis wad\package.json. Aucune UAC demandée.')
}
$report=[IO.File]::ReadAllText($check,[Text.Encoding]::UTF8)|ConvertFrom-Json
if([string]$report.Runtime -cne 'PASS' -or [string]$report.UAC -cne 'NOT_REQUESTED' -or [string]$report.UacProbe -cne $probe){
    throw 'La sonde n''atteint pas Pesto-Startup.ps1 par ce Pesto.exe (écho absent du rapport --check-json) : test arrêté AVANT toute UAC. Aucun moteur chargé.'
}

# 2. Lancement normal, sans argument : seule différence avec un double-clic, la variable de sonde.
Write-Host 'Contrôle préalable : composants acceptés par Pesto.exe, sonde reçue par Pesto-Startup.ps1.'
Write-Host ('Compte de départ (non élevé) : '+$account)
if($policy -and $policy.ConsentPromptBehaviorAdmin -eq 0){Write-Host 'Attention : ConsentPromptBehaviorAdmin=0, Windows élève sans afficher d''invite pour un administrateur.'}
Write-Host 'Windows va demander une autorisation UAC pour « Windows PowerShell » (éditeur Microsoft Windows).'
Write-Host 'Accepter pour le test complet ; refuser pour vérifier l''annulation (code 1223). Le relais affiche ensuite'
Write-Host 'une fenêtre « Pesto - sonde UAC » : aucun moteur chargé, aucune connexion AD, aucune action.'
$code=Start-PestoProbeLauncher @()

$relative='wad\logs\Pesto-sonde-uac-'+$probe+'.txt'
$proof=Join-Path $root $relative
$fields=@{}
if(Test-Path -LiteralPath $proof -PathType Leaf){
    foreach($line in [IO.File]::ReadAllLines($proof,[Text.Encoding]::UTF8)){
        $m=[regex]::Match($line,'^([A-Za-z]+)=(.*)$')
        if($m.Success){$fields[$m.Groups[1].Value]=$m.Groups[2].Value}
    }
}
Write-Host ''
Write-Host ('Code de Pesto.exe : '+$code)
if($fields.Count){Write-Host ('Reçu : '+$relative);foreach($k in @('Resultat','Admin','RelaisEleve','Compte','Moteur','RepriseEtat','AD')){Write-Host ('  '+$k+' = '+$fields[$k])}}
Write-Host ('Journaux : wad\logs\Pesto-demarrage.log, wad\logs\Pesto-lanceur.log ; contrôle préalable : '+$check)
if($code -eq 1223){
    Write-Host 'UAC annulée ou refusée (code 1223) : demande émise, relais non démarré, aucun moteur chargé. Relancer et accepter pour un PASS.'
    exit 1223
}
$elevated=($code -eq 0 -and $fields['Sonde'] -ceq $probe -and $fields['Resultat'] -ceq 'UAC_OK' -and $fields['Admin'] -ceq 'True' -and $fields['RelaisEleve'] -ceq 'True')
if(-not $elevated){
    # Lanceur depuis L4 (04/10) : instance déjà ouverte = 128, ses autres refus 120 à 139 ; la sonde rend 0, 2 ou 3.
    if($code -eq 128){Write-Host 'ECHEC : Pesto est déjà ouvert depuis ce dossier (code 128 du lanceur) : aucune UAC demandée, aucune sonde lancée. Fermer Pesto et relancer.'}
    elseif($code -ge 120 -and $code -le 139){Write-Host ('ECHEC : refus ou erreur du lanceur (code '+$code+') : voir sa fenêtre et « Codes de sortie de Pesto.exe » dans docs\V1_GUIDE.md.')}
    elseif($code -eq 0 -and -not $fields.Count){Write-Host 'ECHEC : anomalie, code 0 sans reçu (sonde non exécutée par le relais, ou reçu effacé). Lire wad\logs\Pesto-demarrage.log avant toute relance.'}
    elseif($code -eq 2){Write-Host 'ECHEC : sonde non concluante (code 2) : relais sans jeton administrateur, ou session déjà administrateur. Voir Resultat ci-dessus.'}
    elseif($code -eq 3){Write-Host 'ECHEC : relais élevé annoncé à l''écran mais reçu non écrit (wad\logs inaccessible ou lié).'}
    else{Write-Host 'ECHEC : relais élevé non prouvé. Voir le reçu et les journaux ci-dessus.'}
    exit 1
}
$seen=Read-Host 'Avez-vous vu la demande d''autorisation de Windows (UAC) avant la fenêtre de la sonde ? (O/N)'
if($seen -notmatch '^\s*[oO]'){
    Write-Host 'PARTIEL : relais élevé avec jeton administrateur, mais invite UAC non vue (élévation sans invite ?).'
    exit 2
}
Write-Host 'PASS : Pesto.exe intact a demandé l''UAC ; relais élevé, Admin=True, code 0 remonté jusqu''au lanceur.'
Write-Host 'Non couvert : moteur élevé, fenêtre principale, connexion Windows ou AD, reprise d''état, signature.'
exit 0

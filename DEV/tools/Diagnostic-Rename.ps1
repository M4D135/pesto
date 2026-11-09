#requires -Version 5.1
[CmdletBinding()]
param([switch]$NoOpen)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Diagnostic local Windows uniquement.'}
$lines=[Collections.Generic.List[string]]::new()
function Line {param([string]$Text);$lines.Add($Text);Write-Host $Text}
function Safe-Text {param([string]$Text);return [regex]::Replace($Text,'(?i)(password|motdepasse|passwd|pwd)\s*[:=]\s*("[^"]*"|''[^'']*''|\S+)','$1=********')}
Line 'Pesto RC9 | État local du renommage (lecture seule)'
Line ('Date : '+[DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))
Line 'Aucune commande de renommage, déplacement, arrêt de processus ou redémarrage.'
Line ''
try{
    $base='HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName'
    $active=[string](Get-ItemProperty -LiteralPath ($base+'\ActiveComputerName') -Name ComputerName -ErrorAction Stop).ComputerName
    $configured=[string](Get-ItemProperty -LiteralPath ($base+'\ComputerName') -Name ComputerName -ErrorAction Stop).ComputerName
    Line ('Nom de cette session : '+$env:COMPUTERNAME)
    Line ('Nom Windows actif  : '+$active)
    Line ('Nom Windows inscrit: '+$configured)
    if($active -ine $configured){
        Line 'ATTENTION : noms différents. Un changement de nom est inscrit mais pas encore actif.'
        Line 'Ne relancez pas le renommage. Vérifiez le résultat AD et le traitement Pesto avant un redémarrage planifié.'
    }else{
        Line 'Les deux noms sont identiques au moment de la lecture.'
        Line 'Cela NE prouve PAS qu''aucune commande n''est encore en cours. Ne relancez pas sur ce seul constat.'
    }
}catch{Line ('Lecture des noms impossible : '+$_.Exception.Message)}
Line ''
Line 'Processus PowerShell visibles (aucun argument ni mot de passe collecté) :'
try{
    foreach($p in @(Get-Process -Name powershell,pwsh -ErrorAction SilentlyContinue)){
        $started=try{$p.StartTime.ToString('yyyy-MM-dd HH:mm:ss')}catch{'non accessible'}
        Line ('  PID {0} | {1} | démarrage {2}' -f $p.Id,$p.ProcessName,$started)
    }
}catch{Line ('Lecture des processus impossible : '+$_.Exception.Message)}
Line ''
Line 'Dernières lignes de NetSetup.log (journal Windows, pas une preuve isolée de réussite) :'
try{
    $path=Join-Path $env:SystemRoot 'debug\NetSetup.log'
    if(Test-Path -LiteralPath $path){foreach($l in @(Get-Content -LiteralPath $path -Tail 70 -ErrorAction Stop)){Line (Safe-Text $l)}}
    else{Line 'Journal absent.'}
}catch{Line ('Journal inaccessible : '+$_.Exception.Message)}
Line ''
Line 'Dernières lignes du journal Pesto de cette installation :'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logDir=Join-Path $root 'wad\logs'
try{
    $log=Get-ChildItem -LiteralPath $logDir -Filter 'Pesto_*.log' -File -ErrorAction Stop|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($log){foreach($l in @(Get-Content -LiteralPath $log.FullName -Tail 90 -Encoding UTF8)){Line (Safe-Text $l)}}else{Line 'Aucun journal local Pesto trouvé.'}
}catch{Line ('Journal Pesto non disponible : '+$_.Exception.Message)}
Line ''
Line 'Ce diagnostic ne lit pas AD et ne certifie ni la fin d''une commande, ni un déplacement d''OU.'
Line 'Le rapport contient des noms de postes/domaines ; le transmettre uniquement au support concerné.'
try{[void][IO.Directory]::CreateDirectory($logDir)}catch{$logDir=[IO.Path]::GetTempPath()}
$output=Join-Path $logDir ('Pesto_ETAT_RENAME_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.txt')
[IO.File]::WriteAllLines($output,$lines.ToArray(),[Text.UTF8Encoding]::new($true))
Write-Host "`nRapport : $output"
if(-not $NoOpen){Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\notepad.exe') -ArgumentList ('"'+$output+'"')}

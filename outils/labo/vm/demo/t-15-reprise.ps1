# Tests visibles : après redémarrage (sans RunOnce, décision de David), « Un poste » affiche « Vérifier l'opération » avec la
# cause sous le bouton ; un clic ouvre la vérification, puis « Consigner la vérification ».
Import-Module C:\PestoTest-run\pilote.psm1
. C:\PestoTest-run\demo-commun.ps1
$P='t15';$log="$D\$P-verification.txt"
& {
  try {
    if (-not (Wait-Fenetre 'Pesto 1\.0$' 3)) { $proc = Start-Process C:\PestoDemo\Pesto.exe -WorkingDirectory C:\PestoDemo -PassThru; "Pesto lancé (pid $($proc.Id))" }
    $w = Get-Pesto; $fin=(Get-Date).AddSeconds(240); while(-not $w -and (Get-Date) -lt $fin){ $w = Get-Pesto }
    if (-not $w) { throw 'fenêtre principale absente' }
    Start-Sleep -Seconds 50; Set-Agrandie $w
    Click-Id $w 'NavRename'; Start-Sleep -Seconds 4
    $run = Find-Id $w 'SuiteDirectRun'; "bouton principal : « $($run.Current.Name) » actif=$($run.Current.IsEnabled)"
    $hint = Find-Id $w 'SuiteDirectHint'; if ($hint) { "texte sous le bouton : $($hint.Current.Name)" }
    Save-Fenetre $w "$D\$P-1-bouton-verifier.png"
    if ($run.Current.Name -notmatch 'Vérifier l' -or -not $run.Current.IsEnabled) { throw 'bouton « Vérifier l''opération » attendu' }
    Invoke-Element $run | Out-Null
    $s=$null;$fin=(Get-Date).AddSeconds(120);while(-not $s -and (Get-Date) -lt $fin){ $s = Wait-Fenetre 'État du poste|Etat du poste' 5; if(-not $s -and (Find-Id $w 'StateRefresh')){$s=$w} }
    if (-not $s) { throw 'vérification non ouverte' }
    Start-Sleep -Seconds 30
    Save-Fenetre $s "$D\$P-2-verification.png"
    $n = Find-Id $s 'StateNext'; "bouton : « $($n.Current.Name) » actif=$($n.Current.IsEnabled)"
    $a = Find-Id $s 'StateAdvice'; if ($a) { "conseil : $($a.Current.Name)" }
    if ($n -and $n.Current.IsEnabled -and $n.Current.Name -match 'Consigner') {
      Invoke-Element $n | Out-Null; Start-Sleep -Seconds 4
      if (Find-Id $w 'PanelAccept') { Save-Fenetre $w "$D\$P-3-consigner.png"; "confirmation : " + (Get-PanelText $w); Click-Id $w 'PanelAccept'; Start-Sleep -Seconds 8 }
      'CONSIGNÉ'
    }
    Start-Sleep -Seconds 4; $run = Find-Id $w 'SuiteDirectRun'; "après : bouton principal « $($run.Current.Name) »"
    Save-Fenetre $w "$D\$P-4-apres.png"
  } catch { "ÉCHEC : $($_.Exception.Message)"; try { Save-Ecran "$D\$P-9-echec.png" } catch {} }
} *> $log

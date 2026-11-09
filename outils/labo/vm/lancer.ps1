# Lance une commande dans une session console existante, sans stocker de mot de passe.
# Code 0 : fin avec resultat 0 (-Attendre), ou demarrage constate (sans -Attendre).
# Code 1 : echec, resultat non nul ou delai depasse ; le resultat Windows reste affiche.
param(
 [Parameter(Mandatory=$true)][string]$Exe,
 [string]$Arguments='', [switch]$Attendre,
 [ValidateRange(1,18000)][int]$Delai=180, [switch]$Eleve,
 [string]$Dossier='C:\PestoTest-run',
 [ValidateNotNullOrEmpty()][string]$Compte='PESTO-W11-TEST\labadmin'
)
$ErrorActionPreference='Stop'
$nom='PestoPilote-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$nettoyer=$false
$code=1
try {
 if($Arguments){$a=New-ScheduledTaskAction -Execute $Exe -Argument $Arguments -WorkingDirectory $Dossier}
 else{$a=New-ScheduledTaskAction -Execute $Exe -WorkingDirectory $Dossier}
 $p=New-ScheduledTaskPrincipal -UserId $Compte -LogonType Interactive -RunLevel $(if($Eleve){'Highest'}else{'Limited'})
 $s=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 5) -MultipleInstances IgnoreNew
 Register-ScheduledTask -TaskName $nom -Action $a -Principal $p -Settings $s | Out-Null
 $avant=(Get-ScheduledTaskInfo -TaskName $nom).LastRunTime
 $chrono=[Diagnostics.Stopwatch]::StartNew()
 # Une erreur apres cette demande peut laisser une execution active : conserver sa trace.
 Start-ScheduledTask -TaskName $nom
 $demarree=$false
 while($true){
  $etat=[string](Get-ScheduledTask -TaskName $nom).State
  $info=Get-ScheduledTaskInfo -TaskName $nom
  $res=[long]$info.LastTaskResult
  if($etat -eq 'Running' -or $info.LastRunTime -ne $avant){$demarree=$true}
  $terminee=$demarree -and $etat -notin @('Running','Queued') -and $res -notin @(267009,267011)
  # Verifier la borne avant d'accepter le resultat : une lecture lente peut revenir apres le delai.
  if($chrono.Elapsed.TotalSeconds -ge $Delai){
   $nettoyer=$terminee -or (-not $demarree -and $etat -eq 'Ready' -and $res -eq 267011)
   $suite=if($nettoyer){'definition retiree'}else{'tache conservee, resultat final non etabli'}
   throw "Delai depasse : $nom etat=$etat resultat=$res ; $suite."
  }
  if($terminee){
   $nettoyer=$true
   "tache $nom etat=$etat resultat=$res"
   if($res -ne 0){throw "La commande a echoue (resultat Windows $res)."}
   $code=0;break
  }
  if(-not $Attendre -and $etat -eq 'Running'){
   "tache $nom demarrage constate ; resultat final non attendu"
   $nettoyer=$true;$code=0;break
  }
  Start-Sleep -Milliseconds 250
 }
}catch{
 Write-Error -Message ("Echec du pilote : $nom : "+$_.Exception.Message) -ErrorAction Continue
}finally{
 if($nettoyer){
  try{Unregister-ScheduledTask -TaskName $nom -Confirm:$false}
  catch{Write-Error -Message ("Nettoyage impossible : $nom : "+$_.Exception.Message) -ErrorAction Continue;$code=1}
 }
}
exit $code

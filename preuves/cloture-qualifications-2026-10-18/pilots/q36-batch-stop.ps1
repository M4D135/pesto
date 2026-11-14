. 'C:\PestoQual_20261018\pilot\commun.ps1'
$w=Get-Pesto;Set-Premier $w
$body=(Find-Id $w 'PanelBody').GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
if($body -notmatch 'RÉEL : exécuter 2 action' -or $body -notmatch 'Renommages : 0 \| Déplacements : 2' -or $body -notmatch 'Redémarrages demandés : 0'){throw 'Unexpected confirmation; no execution'}
$stop=Find-Id $w 'BtnStop';$status=Find-Id $w 'LblStatus'
$before=@(Get-ChildItem C:\ProgramData\GP\Interventions -Filter '*.json' -File|Select Name,LastWriteTimeUtc)
$acceptUtc=[datetime]::UtcNow.ToString('o')
(Find-Id $w 'PanelAccept').GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
$deadline=[datetime]::UtcNow.AddSeconds(20);$seen=''
while([datetime]::UtcNow -lt $deadline){
 $seen=$status.Current.Name
 if($seen -match 'RÉEL.+1/2.*P111301VA765158' -and $stop.Current.IsEnabled){break}
 Start-Sleep -Milliseconds 25
}
if($seen -notmatch 'RÉEL.+1/2.*P111301VA765158'){throw ('First running action was not observed: '+$seen)}
$stopUtc=[datetime]::UtcNow.ToString('o');$stop.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
Start-Sleep -Milliseconds 200
$ack=$status.Current.Name
@{AcceptUtc=$acceptUtc;StopUtc=$stopUtc;StatusBeforeStop=$seen;StatusAfterStop=$ack;StopDisabled=(-not $stop.Current.IsEnabled);BeforeReceipts=$before}|ConvertTo-Json -Depth 4|Set-Content "$D\q36-stop-request.json" -Encoding UTF8
$deadline=[datetime]::UtcNow.AddSeconds(65)
do{Start-Sleep -Milliseconds 500;$final=$status.Current.Name}while($final -notmatch 'action\(s\).*non lancée' -and [datetime]::UtcNow -lt $deadline)
$final|Set-Content "$D\q36-final-status.txt" -Encoding UTF8
Get-Texte $w|Set-Content "$D\q36-final-ui.txt" -Encoding UTF8
Save-Vue $w 'q36-final'
$final

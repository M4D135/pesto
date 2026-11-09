. 'C:\PestoQual_20261018\pilot\commun.ps1'
$w=Get-Pesto
Click $w 'Fermer' 'Button'
foreach($id in @('NavHome','NavHistory','NavLogs','NavSettings','NavHome')){Click-Id $w $id;Start-Sleep -Seconds 1}
$pidApp=$w.Current.ProcessId
[pscustomobject]@{ProcessId=$pidApp;ExecutableHash=(Get-FileHash "$R\candidate-final\PROD\Pesto.exe").Hash;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Workload='10 identical navigation and AD-read cycles, 15-minute observation'}|ConvertTo-Json|Set-Content "$D\session-final-target.json" -Encoding UTF8
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -File '+$R+'\tools\Measure-PestoSession.ps1 -TargetProcessId '+$pidApp+' -Samples 180 -IntervalSeconds 5 -MaxDurationSeconds 960 -ReportPath '+$D+'\session-final.json') -RedirectStandardOutput "$D\session-final.log" -RedirectStandardError "$D\session-final.err"
$cycleRows=@()
for($cycle=1;$cycle -le 10;$cycle++){
 foreach($id in @('NavHome','NavHistory','NavLogs','NavSettings','NavHome','NavRename')){Click-Id $w $id;Start-Sleep -Seconds 1}
 Click-Id $w 'BtnReadComputer';Start-Sleep -Seconds 6
 $p=Get-Process -Id $pidApp
 $cycleRows += [pscustomobject]@{Cycle=$cycle;Utc=[DateTime]::UtcNow.ToString('o');PrivateBytes=$p.PrivateMemorySize64;Handles=$p.HandleCount;Threads=$p.Threads.Count}
 Start-Sleep -Seconds 35
}
$cycleRows|ConvertTo-Json|Set-Content "$D\session-final-cycles.json" -Encoding UTF8
Save-Vue $w 'q50-final-cycles'

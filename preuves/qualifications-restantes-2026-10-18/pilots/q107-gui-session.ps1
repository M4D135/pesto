. 'C:\PestoQual_20261018\pilot\commun.ps1'
. 'C:\PestoQual_20261018\pilot\commun.ps1'
. 'C:\PestoQual_20261018\pilot\commun.ps1'
. 'C:\PestoQual_20261018\pilot\commun.ps1'
$w=Get-Pesto;$close=Find-Id $w 'Close';if($close -and -not $close.Current.IsOffscreen){Click-Id $w 'Close'}



$w=Get-Pesto;. "$R\pilot\gui-input.ps1"
function Invoke-ReadCycle {
 $w=Get-Pesto
 foreach($id in @('NavHome','NavHistory','NavLogs','NavSettings','NavHome','NavRename')){Click-Id $w $id|Out-Null}
 Click-Id $w 'SuiteRefreshSite'|Out-Null
 Start-Sleep -Seconds 6
 $deadline=[DateTime]::UtcNow.AddSeconds(30)
 while(-not (Find-Id $w 'SuiteRefreshSite').Current.IsEnabled -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 500}
 if(-not (Find-Id $w 'SuiteRefreshSite').Current.IsEnabled){throw 'AD read still running after bounded wait'}
 $fresh=(Find-Id $w 'PestoServiceState').Current.Name;if($fresh -notmatch 'récent'){throw ('Site refresh not fresh: '+$fresh)}
 return $w
}
for($warm=1;$warm -le 3;$warm++){$w=Invoke-ReadCycle;Write-Output "warmup $warm"}
$appPid=$w.Current.ProcessId
[pscustomobject]@{ProcessId=$appPid;ExecutableHash=(Get-FileHash "$R\..\PestoQualPersonal_20261018\candidate-fix\PROD\Pesto.exe").Hash;User=[Security.Principal.WindowsIdentity]::GetCurrent().Name;Workload='3 warmup cycles, then 10 identical cycles at 30-second intervals; UIA Invoke navigation and site refresh; freshness checked every cycle (Request-PestoSiteLookup -Force); prior p02/p23 read clicks may use cache; 72 samples at 5 seconds';StartedUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content "$D\q107-gui-target.json" -Encoding UTF8
Save-Vue $w 'q107-gui-warmed'
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -File '+$R+'\tools\Measure-PestoSession.ps1 -TargetProcessId '+$appPid+' -Samples 72 -IntervalSeconds 5 -MaxDurationSeconds 700 -ReportPath '+$D+'\q107-gui-session.json') -RedirectStandardOutput "$D\q107-gui-measure.log" -RedirectStandardError "$D\q107-gui-measure.err"
$cycleRows=@();$watch=[Diagnostics.Stopwatch]::StartNew()
try {
 for($cycle=1;$cycle -le 10;$cycle++){
  $w=Invoke-ReadCycle
  $app=Get-Process -Id $appPid
  $clr=Get-CimInstance Win32_PerfFormattedData_NETFramework_NETCLRMemory|Where-Object ProcessID -eq $appPid
  $clr|Select Name,ProcessID,NumberGen2Collections,NumberGCHandles,Gen2heapsize,LargeObjectHeapsize,NumberTotalcommittedBytes|ConvertTo-Json -Compress|Add-Content "$D\q107-gui-clr.jsonl" -Encoding UTF8
  $row=[pscustomobject]@{Cycle=$cycle;Utc=[DateTime]::UtcNow.ToString('o');ElapsedSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,2);PrivateBytes=$app.PrivateMemorySize64;Handles=$app.HandleCount;Threads=$app.Threads.Count;ReadButtonEnabled=(Find-Id $w 'SuiteRefreshSite').Current.IsEnabled;Locked=(@(Get-Process LogonUI -ErrorAction SilentlyContinue).Count -gt 0);SiteState=(Find-Id $w 'PestoServiceState').Current.Name}
  $cycleRows+=$row;$row|ConvertTo-Json -Compress|Add-Content "$D\q107-gui-cycles.jsonl" -Encoding UTF8
  Write-Output "cycle $cycle completed"
  if($row.Locked){throw 'Windows session locked'}
  if($cycle -eq 1 -or $cycle -eq 10){Save-Vue $w ('q107-gui-cycle-'+$cycle);Get-Texte $w|Set-Content "$D\q107-gui-ui-$cycle.txt" -Encoding UTF8}
  while($watch.Elapsed.TotalSeconds -lt ($cycle*30)){Start-Sleep -Seconds 1}
 }
 [pscustomobject]@{CompletedCycles=$cycleRows.Count;WarmupCycles=3;ElapsedSeconds=$watch.Elapsed.TotalSeconds;Locked=$false;Result='WORKLOAD_COMPLETED'}|ConvertTo-Json|Set-Content "$D\q107-gui-workload.json" -Encoding UTF8
}finally{$cycleRows|ConvertTo-Json|Set-Content "$D\q107-gui-cycles.json" -Encoding UTF8}

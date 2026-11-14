#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop'
$tool=Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Measure-PestoSession.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('Pesto-SessionTests-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$results=[Collections.Generic.List[object]]::new()
function Assert {param($Ok,[string]$Message='Assertion non satisfaite');if(-not $Ok){throw $Message}}
function Case {param([string]$Name,[scriptblock]$Body);try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error='' });Write-Host "OK $Name"}catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message});Write-Host "KO $Name : $($_.Exception.Message)"}}
try{
 Case 'A real local process produces complete counters and identity' {
  $out=Join-Path $temp 'normal.json';$result=& $tool -TargetProcessId $PID -Samples 1 -ReportPath $out
  $disk=[IO.File]::ReadAllText($out)|ConvertFrom-Json
  Assert ($disk.Schema -eq 2 -and $disk.StopReason -eq 'SamplesCollected')
  Assert (@($disk.Samples).Count -eq 1 -and $disk.ProcessId -eq $PID -and $disk.ProcessStartUtc)
  Assert ($disk.Samples[0].PrivateBytes -ge 0 -and $disk.Samples[0].WorkingSet -gt 0)
  Assert ($disk.Samples[0].Threads -gt 0 -and $disk.Samples[0].CpuSeconds -ge 0)
  Assert ($result.Verdict -eq 'MEASURED_ONLY')
 }
 Case 'The duration bound stops a long requested series and retains its first sample' {
  $clock=[Diagnostics.Stopwatch]::StartNew();$out=Join-Path $temp 'bounded.json'
  $r=& $tool -TargetProcessId $PID -Samples 3600 -IntervalSeconds 60 -MaxDurationSeconds 1 -ReportPath $out
  Assert ($r.StopReason -eq 'DurationLimit' -and @($r.Samples).Count -eq 1)
  Assert ($clock.Elapsed.TotalSeconds -lt 10) 'Measurement ignored its duration bound'
 }
 Case 'A deadline-shortened wait never starts another sampling interval after an early wake' {
  function Start-Sleep {param($Milliseconds)}
  try{
   $r=& $tool -TargetProcessId $PID -Samples 3600 -IntervalSeconds 60 -MaxDurationSeconds 1 -ReportPath (Join-Path $temp 'early-wake.json')
   Assert ($r.StopReason -eq 'DurationLimit' -and @($r.Samples).Count -eq 1)
  }finally{Remove-Item Function:Start-Sleep}
 }
 Case 'An existing report remains byte-identical' {
  $out=Join-Path $temp 'existing.json';[IO.File]::WriteAllText($out,'existing evidence')
  $threw=$false;try{& $tool -TargetProcessId $PID -Samples 1 -ReportPath $out|Out-Null}catch{$threw=$true}
  Assert $threw;Assert ([IO.File]::ReadAllText($out) -ceq 'existing evidence')
 }
 Case 'A concurrent writer wins without overwrite or abandoned temporary files' {
  $script:sessionCollision=Join-Path $temp 'collision.json'
  $collisionPath=$script:sessionCollision
  ${function:Start-Sleep}={param($Milliseconds);[IO.File]::WriteAllText($collisionPath,'concurrent evidence')}.GetNewClosure()
  try{$threw=$false;try{& $tool -TargetProcessId $PID -Samples 2 -ReportPath $script:sessionCollision|Out-Null}catch{$threw=$true}
   Assert $threw;Assert ([IO.File]::ReadAllText($script:sessionCollision) -ceq 'concurrent evidence')
   Assert (@(Get-ChildItem -LiteralPath $temp -Filter '.pesto-session-*.tmp' -Force).Count -eq 0)
  }finally{Remove-Item Function:Start-Sleep}
 }
 Case 'Actual process exit preserves completed samples in a readable report' {
  $exe=(Get-Process -Id $PID).Path
  $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=$exe;$start.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"';$start.UseShellExecute=$false;$start.CreateNoWindow=$true
  $script:sessionChild=[Diagnostics.Process]::Start($start)
  $childToStop=$script:sessionChild
  ${function:Start-Sleep}={param($Milliseconds);if(-not $childToStop.HasExited){$childToStop.Kill()};if(-not $childToStop.WaitForExit(10000)){throw 'Child exit was not observed'}}.GetNewClosure()
  try{
   $out=Join-Path $temp 'exited.json';$r=& $tool -TargetProcessId $script:sessionChild.Id -Samples 3 -ReportPath $out
   $disk=[IO.File]::ReadAllText($out)|ConvertFrom-Json
   Assert ($r.StopReason -eq 'ProcessExited') $r.StopReason;Assert (@($disk.Samples).Count -eq 1)
  }finally{Remove-Item Function:Start-Sleep;if(-not $script:sessionChild.HasExited){$script:sessionChild.Kill()};$script:sessionChild.Dispose()}
 }
 Case 'An exited process returned by enumeration never becomes a sample' {
  $script:sessionExitedDouble=[pscustomobject]@{HasExited=$true;StartTime=[datetime]::Now;PrivateMemorySize64=1;WorkingSet64=1;HandleCount=1;Threads=@(1);TotalProcessorTime=[timespan]::Zero}
  $script:sessionExitedDouble|Add-Member ScriptMethod Refresh {}
  $script:sessionExitedDouble|Add-Member ScriptMethod Dispose {}
  $returnedProcess=$script:sessionExitedDouble
  ${function:Get-Process}={param($Id,$ErrorAction);return $returnedProcess}.GetNewClosure()
  try{$r=& $tool -TargetProcessId $PID -Samples 1 -ReportPath (Join-Path $temp 'returned-exited.json');Assert ($r.StopReason -eq 'ProcessExited' -and @($r.Samples).Count -eq 0)}
  finally{Remove-Item Function:Get-Process;Remove-Variable sessionExitedDouble -Scope Script}
 }
 Case 'Missing target produces a truthful empty report' {
  $r=& $tool -TargetProcessId 2147483647 -Samples 1 -ReportPath (Join-Path $temp 'missing.json')
  Assert ($r.StopReason -eq 'ProcessExited' -and @($r.Samples).Count -eq 0)
 }
 Case 'Sampling failure preserves prior samples and does not claim process exit' {
  $script:sessionLookups=0
  function Get-Process {param($Id,$ErrorAction);$script:sessionLookups++;if($script:sessionLookups -gt 1){throw [UnauthorizedAccessException]::new('Synthetic counter access denial')};Microsoft.PowerShell.Management\Get-Process -Id $Id -ErrorAction Stop}
  function Start-Sleep {param($Milliseconds)}
  try{$r=& $tool -TargetProcessId $PID -Samples 3 -ReportPath (Join-Path $temp 'denied.json');Assert ($r.StopReason -eq 'CounterUnavailable' -and @($r.Samples).Count -eq 1)}
  finally{Remove-Item Function:Get-Process;Remove-Item Function:Start-Sleep}
 }
}finally{
 $failed=@($results|Where-Object{-not $_.Passed})
 $report=[ordered]@{Suite='Session measurement';Utc=[DateTime]::UtcNow.ToString('o');Total=$results.Count;Passed=$results.Count-$failed.Count;Failed=$failed.Count;Tests=$results.ToArray();Scope='Local process counters and filesystem publication; no Pesto, AD or VM.'}
 if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
 Remove-Item -LiteralPath $temp -Recurse -Force
}
if($failed.Count){exit 1}
Write-Host ('Session measurement: '+$results.Count+' passed.')

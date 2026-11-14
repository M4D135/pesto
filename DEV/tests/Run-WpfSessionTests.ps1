#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='',[ValidateRange(0,600)][int]$MinimumDurationSeconds=0)
$ErrorActionPreference='Stop'
$tool=Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Measure-PestoWpfSession.ps1'
$report=& $tool -Cycles 32 -WarmupCycles 4 -SampleEvery 8 -MaxDurationSeconds ([Math]::Min(900,$MinimumDurationSeconds+180)) -MinimumDurationSeconds $MinimumDurationSeconds -MaxCycles 5000 -ReportPath $ReportPath
$m=$report.Measurement
if($m.CompletedCycles -lt 32 -or $m.WarmupCycles -ne 4 -or $m.StopReason -ne 'CyclesCollected' -or $m.WorkloadSeconds -lt $MinimumDurationSeconds){throw ('Incomplete isolated WPF workload: '+$m.StopReason+' / '+$m.CompletedCycles)}
if($m.BeforeWarmup.TrackedWindows -ne 0 -or $m.Samples.Count -lt 5 -or $m.Samples[0].CompletedCycles -ne 0 -or $m.Samples[$m.Samples.Count-1].CompletedCycles -ne $m.CompletedCycles){throw 'Missing baseline or final measurement.'}
foreach($row in $m.Samples){
 if($row.ManagedBytes -le 0 -or $row.PrivateBytes -le 0 -or $row.Handles -le 0 -or $row.Threads -le 0){throw 'Invalid process counters.'}
 if($row.LiveWindowReferences -lt 0 -or $row.LiveWindowReferences -gt $row.TrackedWindows){throw 'Invalid weak reference observation.'}
}
# Do not invent a universal leak threshold: retain raw baseline and samples for comparison.
$last=$m.Samples[$m.Samples.Count-1]
Write-Host ('WPF lifecycle: '+$m.WarmupCycles+' warmups, '+$m.CompletedCycles+' shell cycles, '+($m.CompletedCycles*8)+' page selections, '+$m.WorkloadSeconds+' workload seconds, '+$m.Samples.Count+' post-warmup samples. Final tracked windows alive: '+$last.LiveWindowReferences+'/'+$last.TrackedWindows+'. MEASURED_ONLY; not a full-application soak qualification.')
$m.Samples|Format-Table CompletedCycles,LiveWindowReferences,ManagedBytes,PrivateBytes,Handles,Threads -AutoSize|Out-Host

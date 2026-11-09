#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$TargetProcessId,
    [ValidateRange(1,3600)][int]$Samples=60,
    [ValidateRange(1,60)][int]$IntervalSeconds=5,
    [ValidateRange(1,86400)][int]$MaxDurationSeconds=3600,
    [Parameter(Mandatory)][string]$ReportPath
)
# Observation only: no command is sent to the process. A completed measurement is not a leak verdict.
$ErrorActionPreference='Stop'
$reportFullPath=[IO.Path]::GetFullPath($ReportPath)
if([IO.File]::Exists($reportFullPath) -or [IO.Directory]::Exists($reportFullPath)){throw 'Rapport existant.'}
if(-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($reportFullPath))){throw 'Dossier du rapport absent.'}
$rows=[Collections.Generic.List[object]]::new()
$watch=[Diagnostics.Stopwatch]::StartNew()
$startedUtc=[DateTime]::UtcNow.ToString('o')
$processStartUtc=$null;$stopReason='SamplesCollected';$errorType=$null
try{
    for($sample=0;$sample -lt $Samples;$sample++){
        if($watch.Elapsed.TotalSeconds -ge $MaxDurationSeconds){$stopReason='DurationLimit';break}
        $observed=$null
        try{
            $observed=Get-Process -Id $TargetProcessId -ErrorAction Stop
            $observed.Refresh()
            if($observed.HasExited){$stopReason='ProcessExited';break}
            $start=$observed.StartTime.ToUniversalTime().ToString('o')
            if($null -eq $processStartUtc){$processStartUtc=$start}
            elseif($start -ne $processStartUtc){$stopReason='ProcessReplaced';break}
            $observation=[pscustomobject][ordered]@{
                Utc=[DateTime]::UtcNow.ToString('o');ElapsedSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,3)
                PrivateBytes=$observed.PrivateMemorySize64;WorkingSet=$observed.WorkingSet64
                Handles=$observed.HandleCount;Threads=$observed.Threads.Count;CpuSeconds=$observed.TotalProcessorTime.TotalSeconds
            }
            if($observed.HasExited){$stopReason='ProcessExited';break}
            $rows.Add($observation)
        }catch{
            # Get-Process may fail between two samples, or the process may exit while reading its counters.
            # Keep every complete sample; an access error must not be presented as a successful measurement.
            $errorType=$_.Exception.GetType().FullName
            if($_.FullyQualifiedErrorId -like 'NoProcessFoundForGivenId*'){$stopReason='ProcessExited'}
            else{$stopReason='CounterUnavailable'}
            break
        }finally{if($null -ne $observed){$observed.Dispose()}}
        if($sample+1 -lt $Samples){
            $untilLimitMilliseconds=[Math]::Max(0,($MaxDurationSeconds-$watch.Elapsed.TotalSeconds)*1000)
            $lastWait=($untilLimitMilliseconds -le $IntervalSeconds*1000)
            $remainingMilliseconds=[Math]::Min($IntervalSeconds*1000,$untilLimitMilliseconds)
            if($remainingMilliseconds -gt 0){Start-Sleep -Milliseconds ([int][Math]::Ceiling($remainingMilliseconds))}
            # A deadline-shortened wait is not another sampling interval. Windows can wake
            # just before the requested millisecond; never collect an early extra sample.
            if($lastWait){$stopReason='DurationLimit';break}
        }
    }
}catch{$stopReason='ObservationInterrupted';$errorType=$_.Exception.GetType().FullName;throw}
finally{
    $watch.Stop()
    $report=[pscustomobject][ordered]@{
        Schema=2;ProcessId=$TargetProcessId;ProcessStartUtc=$processStartUtc;StartedUtc=$startedUtc
        ToolSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;PowerShell=$PSVersionTable.PSVersion.ToString();Culture=[Globalization.CultureInfo]::CurrentCulture.Name;OperatingSystem=[Environment]::OSVersion.VersionString
        Platform=[Environment]::OSVersion.Platform.ToString();CounterAvailability='PrivateBytes and Handles may be zero when the platform does not expose these counters.'
        FinishedUtc=[DateTime]::UtcNow.ToString('o');RequestedSamples=$Samples;IntervalSeconds=$IntervalSeconds
        MaxDurationSeconds=$MaxDurationSeconds;ElapsedSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,3)
        StopReason=$stopReason;CounterErrorType=$errorType;Samples=$rows.ToArray();Verdict='MEASURED_ONLY'
        Limit='Counters only; no leak diagnosis, no event-subscription inventory. Compare identical workloads after warm-up. Partial samples are preserved when the process exits.'
    }
    # Publish an entirely written JSON on the same volume. File.Move without overwrite also protects
    # a report created by another writer after the initial check. Never remove that writer's file.
    $tempPath=Join-Path ([IO.Path]::GetDirectoryName($reportFullPath)) ('.pesto-session-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $stream=[IO.File]::Open($tempPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 5));$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        [IO.File]::Move($tempPath,$reportFullPath)
    }finally{if([IO.File]::Exists($tempPath)){[IO.File]::Delete($tempPath)}}
}
$report

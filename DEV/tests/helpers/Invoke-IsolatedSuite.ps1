# Windows PowerShell 5.1 only. The unnamed job owns the launcher and every descendant.
function Invoke-PestoIsolatedSuite {
    param([Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$OutputDirectory,
        [ValidateRange(1,3600)][int]$TimeoutSeconds=600)
    if(-not ('PestoIsolatedSuiteJob' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'IsolatedSuiteJob.cs')}
    $Path=[IO.Path]::GetFullPath($Path)
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $name=[IO.Path]::GetFileNameWithoutExtension($Path)
    $stdoutPath=Join-Path $OutputDirectory ($name+'.stdout.log')
    $stderrPath=Join-Path $OutputDirectory ($name+'.stderr.log')
    $process=[Diagnostics.Process]::new();$job=$null;$started=$false
    $stdout=$null;$stderr=$null;$logsWritten=$false
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try{
        $job=[PestoIsolatedSuiteJob]::new()
        $info=[Diagnostics.ProcessStartInfo]::new()
        $info.FileName=Join-Path $PSHOME 'powershell.exe'
        $escaped=$Path.Replace("'","''")
        $command="if([Console]::ReadLine() -cne 'go'){exit 125}; & (Join-Path `$PSHOME 'powershell.exe') -NoLogo -NoProfile -STA -ExecutionPolicy RemoteSigned -File '$escaped'; exit `$LASTEXITCODE"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $info.Arguments='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy RemoteSigned -EncodedCommand '+$encoded
        $info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $process.StartInfo=$info
        if(-not $process.Start()){throw 'Impossible de lancer la suite isolee.'};$started=$true
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        # The launcher waits for a one-line permit. EOF or a parent crash never admits the suite.
        $job.Attach($process)
        $process.StandardInput.WriteLine('go')
        $process.StandardInput.Close()
        $timedOut=-not $process.WaitForExit($TimeoutSeconds*1000)
        $exitCode=if($timedOut){-1}else{$process.ExitCode}
        # Closing this exact handle kills only this suite's remaining processes, including on success.
        $job.Dispose();$job=$null
        if(-not $process.WaitForExit(10000)){throw 'Le processus de la suite ne termine pas apres fermeture de son job.'}
        if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),10000)){throw 'Les flux de la suite ne se ferment pas.'}
        [IO.File]::WriteAllText($stdoutPath,$stdout.Result,[Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($stderrPath,$stderr.Result,[Text.UTF8Encoding]::new($false))
        $logsWritten=$true
        [pscustomobject]@{Suite=[IO.Path]::GetFileName($Path);ExitCode=$exitCode;TimedOut=$timedOut;DurationSeconds=[Math]::Round($watch.Elapsed.TotalSeconds,3);Stdout=$stdoutPath;Stderr=$stderrPath}
    }finally{
        if($job){$job.Dispose()}
        # Assignment failure happens before any test command; kill the exact started process via its handle.
        if($started -and -not $process.HasExited){$process.Kill();[void]$process.WaitForExit(10000)}
        # Even a failed attachment/permit leaves the launcher's diagnostic streams in the evidence.
        if(-not $logsWritten -and $stdout -and $stderr){
            try{
                if([Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout,$stderr),10000)){
                    [IO.File]::WriteAllText($stdoutPath,$stdout.Result,[Text.UTF8Encoding]::new($false))
                    [IO.File]::WriteAllText($stderrPath,$stderr.Result,[Text.UTF8Encoding]::new($false))
                }
            }catch{Write-Warning 'Les flux du lanceur interrompu n''ont pas pu etre conserves.'}
        }
        $process.Dispose()
    }
}

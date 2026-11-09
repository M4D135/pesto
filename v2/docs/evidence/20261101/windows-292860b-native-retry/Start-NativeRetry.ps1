#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root='C:\Users\degun\actions-runner\PestoTargetedDiag-20261101';$repo='C:\Users\degun\actions-runner\_work\pesto\pesto';$dotnet='C:\Users\degun\actions-runner\_dotnet\dotnet.exe'
$result=[ordered]@{kind='pesto.isolated-native-update-run';sourceCommit='292860b934bcdff0f1321b0839158bf38b58816e';fullReleaseQualification=$false;success=$false;startedUtc=[DateTimeOffset]::UtcNow.ToString('O');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;channels=@()}
try{
 Set-Location $root
 if((& 'C:\Program Files\Git\cmd\git.exe' -C $repo rev-parse HEAD).Trim() -cne $result.sourceCommit){throw 'Source checkout changed'}
 if([Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS')){throw 'Unexpected startup hook environment'}
 $inputs=Get-Content (Join-Path $root 'native-retry-inputs.json') -Raw|ConvertFrom-Json
 foreach($file in $inputs.files){if((Get-FileHash -LiteralPath (Join-Path $repo $file.path)).Hash.ToLowerInvariant() -cne $file.sha256){throw 'An observed qualification input changed'}}
 $runner=Join-Path $repo 'v2\tools\qualification\Pesto.UpdateQualification\bin\Release\net10.0\Pesto.UpdateQualification.dll'
 $script=Join-Path $repo 'v2\tools\qualification\Invoke-NativeUpdateQualification.ps1'
 $result |ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'native-retry-start.json') -Encoding utf8
 foreach($channel in @('PROD','DEV')){
  $report=Join-Path $root ('native-retry-'+$channel)
  if(Test-Path $report){throw 'Report destination already exists'}
  $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-BasePack',(Join-Path $repo ('v2\out\baseline-'+$channel)),'-CandidatePack',(Join-Path $repo ('v2\out\'+$channel)),'-CandidateZip',(Join-Path $repo ('v2\out\Pesto_V2_'+$channel+'_candidate.zip')),'-RunnerDll',$runner,'-DotNet',$dotnet,'-ReportDirectory',$report)
  $quoted=@($arguments|ForEach-Object{if($_ -match '["\x00-\x1f]'){throw 'Invalid fixed launcher argument'};'"'+[regex]::Replace($_,'(\\+)$','$1$1')+'"'})
  $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe";$start.Arguments=$quoted -join ' ';$start.WorkingDirectory=$root;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $p=[Diagnostics.Process]::Start($start)
  try{$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$p.WaitForExit();$exitCode=$p.ExitCode;$text=$out.GetAwaiter().GetResult()+$err.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $root ('native-retry-'+$channel+'.log')),$text,[Text.UTF8Encoding]::new($false))}finally{$p.Dispose()}
  $result.channels+=@([ordered]@{channel=$channel;exitCode=$exitCode;finishedUtc=[DateTimeOffset]::UtcNow.ToString('O')})
  $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'native-retry-progress.json') -Encoding utf8
  if($exitCode -ne 0){throw ('Native update qualification failed for '+$channel)}
 }
 $result.success=$true
}catch{$result.error=$_.Exception.Message}
finally{$result.finishedUtc=[DateTimeOffset]::UtcNow.ToString('O');$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'native-retry-result.json') -Encoding utf8}
if(-not $result.success){exit 2}

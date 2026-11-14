#Requires -Version 7.0
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='C:\Users\degun\actions-runner\PestoTargetedDiag-20261101';$repo='C:\Users\degun\actions-runner\_work\pesto\pesto';$dotnet='C:\Users\degun\actions-runner\_dotnet\dotnet.exe'
$result=[ordered]@{kind='pesto.isolated-native-update-ui-run';sourceCommit='292860b934bcdff0f1321b0839158bf38b58816e';fullReleaseQualification=$false;success=$false;startedUtc=[DateTimeOffset]::UtcNow.ToString('O');sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;channels=@()}
try{
 Set-Location $root
 $prior=Get-Content (Join-Path $root 'native-retry-result.json') -Raw|ConvertFrom-Json
 if(-not $prior.success){throw 'Native update component did not pass'}
 if((& 'C:\Program Files\Git\cmd\git.exe' -C $repo rev-parse HEAD).Trim() -cne $result.sourceCommit){throw 'Source checkout changed'}
 & 'C:\Program Files\Git\cmd\git.exe' -C $repo diff --quiet
 if($LASTEXITCODE -ne 0){throw 'Tracked sources changed'}
 & 'C:\Program Files\Git\cmd\git.exe' -C $repo diff --cached --quiet
 if($LASTEXITCODE -ne 0){throw 'Staged sources changed'}
 if([Environment]::GetEnvironmentVariable('DOTNET_STARTUP_HOOKS')){throw 'Unexpected startup hook environment'}
 $inputs=Get-Content (Join-Path $root 'native-retry-inputs.json') -Raw|ConvertFrom-Json
 foreach($file in $inputs.files){if((Get-FileHash -LiteralPath (Join-Path $repo $file.path)).Hash.ToLowerInvariant() -cne $file.sha256){throw 'An observed qualification input changed'}}
 $runner=Join-Path $repo 'v2\tools\qualification\Pesto.UpdateQualification\bin\Release\net10.0\Pesto.UpdateQualification.dll'
 $script=Join-Path $repo 'v2\tools\qualification\Invoke-NativeUpdateUiQualification.ps1'
 $node='C:\Users\degun\Codex\vigie-xlsx-20261018\node-v24.22.0-win-x64\node.exe'
 if((& $node --version).Trim() -cne 'v24.22.0'){throw 'Unexpected Node version'}
 $result.uiScriptSha256=(Get-FileHash -LiteralPath $script).Hash.ToLowerInvariant()
 $result.nodeVersion=(& $node --version).Trim()
 $result.powershellVersion=$PSVersionTable.PSVersion.ToString()
 $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'ui-retry2-preparation-start.json') -Encoding utf8
 $prepared=@(Get-Content (Join-Path $root 'ui-retry-inputs\prepared.json') -Raw|ConvertFrom-Json)
 foreach($entry in $prepared){ & $node (Join-Path $repo 'v2/tools/pack/make-pack.mjs') --verify $entry.currentPack | Out-Null; if($LASTEXITCODE -ne 0){throw 'Published input pack changed'} }
 $result.childModulePathPolicy='Remove inherited PSModulePath so Windows PowerShell5.1 builds its own defaults'
 if($prepared.Count -ne 2){throw 'Incomplete release preparation'}
 $result |ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'ui-retry2-start.json') -Encoding utf8
 foreach($entry in $prepared){
  $channel=$entry.channel
  $report=Join-Path $root ('ui-retry2-'+$channel)
  if(Test-Path $report){throw 'Report destination already exists'}
  $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-CurrentPack',$entry.currentPack,'-TargetPack',$entry.targetPack,'-TargetZip',$entry.targetZip,'-RunnerDll',$runner,'-DotNet',$dotnet,'-ReportDirectory',$report)
  $quoted=@($arguments|ForEach-Object{if($_ -match '["\x00-\x1f]'){throw 'Invalid fixed launcher argument'};'"'+[regex]::Replace($_,'(\\+)$','$1$1')+'"'})
  $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName="$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe";$start.Arguments=$quoted -join ' ';$start.WorkingDirectory=$root;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $start.EnvironmentVariables.Remove('PSModulePath')
  $p=[Diagnostics.Process]::Start($start)
  try{$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$p.WaitForExit();$exitCode=$p.ExitCode;$text=$out.GetAwaiter().GetResult()+$err.GetAwaiter().GetResult();[IO.File]::WriteAllText((Join-Path $root ('ui-retry2-'+$channel+'.log')),$text,[Text.UTF8Encoding]::new($false))}finally{$p.Dispose()}
  $result.channels+=@([ordered]@{channel=$channel;exitCode=$exitCode;finishedUtc=[DateTimeOffset]::UtcNow.ToString('O')})
  $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'ui-retry2-progress.json') -Encoding utf8
  if($exitCode -ne 0){throw ('Native UI update qualification failed for '+$channel)}
 }
 $result.success=$true
}catch{$result.error=$_.Exception.Message}
finally{$result.finishedUtc=[DateTimeOffset]::UtcNow.ToString('O');$result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $root 'ui-retry2-result.json') -Encoding utf8}
if(-not $result.success){exit 2}

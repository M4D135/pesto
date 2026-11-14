. 'C:\PestoQual_20261018\pilot\commun.ps1'
. 'C:\PestoQual_20261018\pilot\commun.ps1'
$ErrorActionPreference='Stop'
$dir='C:\PestoQualPersonal_20261018\policy98-new';$meta=Get-Content "$dir\prepared.json" -Raw|ConvertFrom-Json
$id=$meta.PolicyId;$ci="$env:windir\System32\CiTool.exe";$exe='C:\PestoQualPersonal_20261018\candidate-fix\PROD\Pesto.exe'
if((Get-FileHash $exe).Hash -cne $meta.TargetHash){throw 'Build changed'}
$baseline=& $ci -lp -json;$baseline|Set-Content "$dir\before-policies.json" -Encoding UTF8
if(@(($baseline|ConvertFrom-Json).Policies|Where-Object {$_.PolicyID.Trim('{}') -eq $id.Trim('{}')}).Count){throw 'Policy ID already present'}
$receipts=@(Get-ChildItem 'C:\ProgramData\GP\Interventions','C:\ProgramData\GP\Operations','C:\ProgramData\GP\Join' -File -Recurse -ErrorAction SilentlyContinue|ForEach-Object{[pscustomobject]@{Path=$_.FullName;Hash=(Get-FileHash $_.FullName).Hash}})
$receipts|ConvertTo-Json -Depth 4|Set-Content "$dir\receipts-before.json" -Encoding UTF8
$gui=Get-Process -Id 6020;$guiStart=$gui.StartTime.ToUniversalTime().ToString('o')
$watchdog='Pesto-Qual98-Remove-'+$id.Trim('{}')
$a=New-ScheduledTaskAction -Execute "$env:windir\System32\cmd.exe" -Argument ('/c ""'+$ci+'" -rp '+$id+' -json & "'+$ci+'" -r -json"')
$t=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(3)
Register-ScheduledTask -TaskName $watchdog -Action $a -Trigger $t -User 'SYSTEM' -RunLevel Highest|Out-Null
[void][IO.Directory]::CreateDirectory("$dir\attempt1");foreach($f in @('before-policies.json','audit-apply.json','audit-active.json','audit-language-mode.txt','audit-launch.stdout','audit-launch.stderr','receipts-before.json','cleanup.json','after-policies.json','remove.json')){if(Test-Path "$dir\$f"){Copy-Item "$dir\$f" "$dir\attempt1\$f"}}
$start=[DateTime]::UtcNow
try{
 foreach($phase in @('audit','enforced')){
  & $ci -up "$dir\$phase.cip" -json|Set-Content "$dir\$phase-apply.json" -Encoding UTF8
  if($LASTEXITCODE -ne 0){throw 'Deployment failed'}
  & $ci -r -json|Out-Null;Start-Sleep -Seconds 2
  & $ci -lp -json|Set-Content "$dir\$phase-active.json" -Encoding UTF8
  $mode=& "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Command '$ExecutionContext.SessionState.LanguageMode'
  $mode|Set-Content "$dir\$phase-language-mode.txt" -Encoding UTF8
  $started=$false;$refused=$false;$native=$null;$exitCode=$null
  try{
   $attempt=Start-Process -FilePath $exe -ArgumentList '-PestoQualificationNoSuchParameter' -WorkingDirectory (Split-Path $exe) -PassThru -RedirectStandardOutput "$dir\$phase-launch.stdout" -RedirectStandardError "$dir\$phase-launch.stderr" -ErrorAction Stop
   $started=$true
   Start-Sleep -Seconds 2;$attempt.Refresh();$nativeDialog=$attempt.MainWindowTitle;if(-not $attempt.HasExited){[void]$attempt.CloseMainWindow()}
   if(-not $attempt.WaitForExit(10000)){throw 'Unexpected surviving diagnostic launcher; inspect before cleanup'}
   $attempt.Refresh();$exitCode=$attempt.ExitCode
  }catch{if(-not $started){$refused=$true;$native=$_.Exception.NativeErrorCode}else{throw}}
  [pscustomobject]@{Phase=$phase;Started=$started;Refused=$refused;NativeError=$native;ExitCode=$exitCode;LanguageMode=[string]$mode;Build=$meta.TargetHash;NativeDialog=$nativeDialog;Arguments='Invalid qualification-only parameter; no operational command requested';Utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content "$dir\$phase-launch.json" -Encoding UTF8
 }
 $events=@(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-CodeIntegrity/Operational';StartTime=$start.ToLocalTime();Id=3076,3077} -ErrorAction SilentlyContinue|Where-Object {$_.Message -match 'Pesto.exe'}|ForEach-Object{[pscustomobject]@{Id=$_.Id;Utc=$_.TimeCreated.ToUniversalTime().ToString('o');Xml=$_.ToXml()}})
 $events|ConvertTo-Json -Depth 5|Set-Content "$dir\events.json" -Encoding UTF8
}finally{
 & $ci -rp $id -json|Set-Content "$dir\remove.json" -Encoding UTF8;& $ci -r -json|Out-Null
 $after=& $ci -lp -json;$after|Set-Content "$dir\after-policies.json" -Encoding UTF8
 $beforeObjects=@(($baseline|ConvertFrom-Json).Policies|Sort-Object PolicyID);$afterObjects=@(($after|ConvertFrom-Json).Policies|Sort-Object PolicyID)
 $restored=(($beforeObjects|ConvertTo-Json -Depth 10 -Compress) -ceq ($afterObjects|ConvertTo-Json -Depth 10 -Compress))
 $afterReceipts=@(Get-ChildItem 'C:\ProgramData\GP\Interventions','C:\ProgramData\GP\Operations','C:\ProgramData\GP\Join' -File -Recurse -ErrorAction SilentlyContinue|ForEach-Object{[pscustomobject]@{Path=$_.FullName;Hash=(Get-FileHash $_.FullName).Hash}})
 $unchanged=(($receipts|ConvertTo-Json -Compress) -ceq ($afterReceipts|ConvertTo-Json -Compress))
 $g=Get-Process -Id 6020;$same=($g.StartTime.ToUniversalTime().ToString('o') -ceq $guiStart)
 [pscustomobject]@{BaselineRestored=$restored;BeforeCount=$beforeObjects.Count;AfterCount=$afterObjects.Count;ReceiptsUnchanged=$unchanged;ReceiptCount=$receipts.Count;SameGuiProcess=$same;LanguageMode=(& powershell.exe -NoProfile -Command '$ExecutionContext.SessionState.LanguageMode')}|ConvertTo-Json|Set-Content "$dir\cleanup.json" -Encoding UTF8
 if($restored){Unregister-ScheduledTask -TaskName $watchdog -Confirm:$false}else{throw 'Baseline not identical; cleanup watchdog retained'}
 if(-not $same -or -not $unchanged){throw 'Unexpected GUI or receipts change'}
}
Get-Content "$dir\audit-launch.json","$dir\enforced-launch.json","$dir\cleanup.json" -Raw

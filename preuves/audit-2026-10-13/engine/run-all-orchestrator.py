import sys,pathlib,json
sys.path.insert(0,str(pathlib.Path(__file__).parent));from pesto_lab import remote
script=r'''$d='C:\PestoAudit20261013\engine';$env:TEMP=$d+'\temp';$env:TMP=$env:TEMP
$runArgs=@('-NoLogo','-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',($d+'\tests\Run-AllTests.ps1'))
$timer=[Diagnostics.Stopwatch]::StartNew();$p=Start-Process powershell.exe -ArgumentList $runArgs -PassThru -RedirectStandardOutput ($d+'\reports\All.log') -RedirectStandardError ($d+'\reports\All.err');$handle=$p.Handle
$done=$p.WaitForExit(450000);if(-not $done){$p.Kill();$p.WaitForExit()};$p.Refresh()
$record=[pscustomobject]@{Suite='Run-AllTests';PowerShell=$PSVersionTable.PSVersion.ToString();Session=(Get-Process -Id $PID).SessionId;ExitCode=$p.ExitCode;TimedOut=(-not $done);Ms=$timer.ElapsedMilliseconds;ExeSHA256=(Get-FileHash ($d+'\Pesto.exe') -Algorithm SHA256).Hash;Utc=[datetime]::UtcNow.ToString('o')}
$record|ConvertTo-Json|Set-Content ($d+'\reports\All.json') -Encoding UTF8;$record|ConvertTo-Json
'''
remote(script,timeout=475)

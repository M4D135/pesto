#requires -Version 5.1
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop'){throw 'Windows PowerShell 5.1 requis.'}
. (Join-Path $PSScriptRoot 'helpers/Invoke-IsolatedSuite.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('pesto-suite-runner-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $ok=Join-Path $root "suite's success.ps1"
    [IO.File]::WriteAllText($ok, '1..2000|ForEach-Object{[Console]::Out.WriteLine("stdout-$_-end");[Console]::Error.WriteLine("stderr-$_-end")};exit 0')
    $result=Invoke-PestoIsolatedSuite -Path $ok -OutputDirectory $root -TimeoutSeconds 30
    if($result.ExitCode -ne 0 -or $result.TimedOut){throw 'La suite temoin echoue.'}
    $outText=[IO.File]::ReadAllText($result.Stdout);$errText=[IO.File]::ReadAllText($result.Stderr)
    foreach($i in 1..2000){if(-not $outText.Contains(('stdout-'+$i+'-end')) -or -not $errText.Contains(('stderr-'+$i+'-end'))){throw 'Une sortie est tronquee ou melangee.'}}
    $fail=Join-Path $root 'failure.ps1';[IO.File]::WriteAllText($fail,'exit 7')
    $result=Invoke-PestoIsolatedSuite -Path $fail -OutputDirectory $root -TimeoutSeconds 30
    if($result.ExitCode -ne 7 -or $result.TimedOut){throw 'Le code de sortie est perdu.'}
    $pidFile=Join-Path $root 'grandchild.json'
    $child="[IO.File]::WriteAllText('"+$pidFile.Replace("'","''")+"', (([pscustomobject]@{Id=`$PID;StartTicks=(Get-Process -Id `$PID).StartTime.Ticks})|ConvertTo-Json));Start-Sleep -Seconds 300"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($child))
    $hang=Join-Path $root 'timeout.ps1'
    [IO.File]::WriteAllText($hang,('& (Join-Path $PSHOME ''powershell.exe'') -NoProfile -EncodedCommand '+$encoded))
    $result=Invoke-PestoIsolatedSuite -Path $hang -OutputDirectory $root -TimeoutSeconds 10
    if(-not $result.TimedOut -or $result.ExitCode -ne -1){throw 'Le delai ne provoque pas un echec explicite.'}
    if(-not [IO.File]::Exists($pidFile)){throw 'Le petit-enfant du temoin ne s''est pas lance.'}
    $identity=Get-Content $pidFile -Raw|ConvertFrom-Json
    $alive=Get-Process -Id $identity.Id -ErrorAction SilentlyContinue
    if($alive -and $alive.StartTime.Ticks -eq $identity.StartTicks){throw 'Un descendant de la suite expiree survit.'}
    Write-Host 'IsolatedSuiteRunner: sorties, code non nul, delai et fermeture des descendants verifies.'
}finally{Remove-Item -LiteralPath $root -Recurse -Force}

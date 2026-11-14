param([string]$SourcePath,[string]$ReportPath)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
$assignment=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$script:PestoSharedNameWorker'})
if($assignment.Count -ne 1){throw 'Worker missing'}
$folder=Join-Path $PSScriptRoot ('shared-race-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($folder)
$workerPath=Join-Path $folder 'worker.ps1';$workerCode=$assignment[0].Extent.Text
[IO.File]::WriteAllText($workerPath,$workerCode,[Text.UTF8Encoding]::new($true))
. $workerPath
$script:raceRoot=$folder
$req=[pscustomobject]@{Mode='Prepare';Root=$folder;Domain='example.invalid';Owner='old';Station='pc-old';User='fixture';Context='test';Minutes=5;Name='P111301AA765001';Names=@('P111301AA765001');Credential=$null}
& $script:PestoSharedNameWorker $req|Out-Null
$req.Mode='Reserve';& $script:PestoSharedNameWorker $req|Out-Null
$path=Join-Path $folder 'reservations\P111301AA765001.json'
$entry=[IO.File]::ReadAllText($path)|ConvertFrom-Json;$entry.ExpiresUtc=[datetime]::UtcNow.AddMinutes(-1).ToString('o');[IO.File]::WriteAllText($path,($entry|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$line=0;$lines=$workerCode -split '\r?\n'
for($i=0;$i -lt $lines.Length;$i++){if($lines[$i].Contains("if(`$e -and [string]`$e.Owner -eq `$owner){try{[IO.File]::Delete")){$line=$i+1}}
if(-not $line){throw 'Release ownership decision not found'}
$script:raceAttempt='not triggered'
$bp=Set-PSBreakpoint -Script $workerPath -Line $line -Action {
    $new=[pscustomobject]@{Mode='Reserve';Root=$script:raceRoot;Domain='example.invalid';Owner='new';Station='pc-new';User='fixture';Context='test';Minutes=5;Name='P111301AA765001';Names=@();Credential=$null}
    $taken=& $script:PestoSharedNameWorker $new
    $script:raceAttempt=$taken.State
}
try{
    $req.Mode='Release';$released=& $script:PestoSharedNameWorker $req
    $result=[pscustomobject]@{PowerShell=$PSVersionTable.PSVersion.ToString();NewOwnerTakeover=$script:raceAttempt;ReleaseState=$released.State;Released=@($released.Others);ReservationExists=[IO.File]::Exists($path);SourceHash=(Get-FileHash $SourcePath -Algorithm SHA256).Hash;Scope='Actual worker, local NTFS only; breakpoint schedules the other worker between owner read and delete'}
    $result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8
    $result|ConvertTo-Json -Depth 6
}finally{Remove-PSBreakpoint $bp;Remove-Item -LiteralPath $folder -Recurse -Force}

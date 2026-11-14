#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='',[string]$SourcePath='')
# Worker réel, fichiers temporaires locaux et concurrence déterministe. Aucun partage réseau ni AD.
$ErrorActionPreference='Stop';Set-StrictMode -Off
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Windows PowerShell 5.1 requis pour le verrouillage NTFS.'}
if(-not $SourcePath){$SourcePath=Join-Path (Split-Path $PSScriptRoot -Parent) 'wad\Pesto-Names.ps1'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($SourcePath,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors.Message -join '; ')}
$assignment=@($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$script:PestoSharedNameWorker'})
if($assignment.Count -ne 1){throw 'Worker de réservation partagé absent ou ambigu.'}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('PestoSharedNames-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$workerPath=Join-Path $fixture 'worker.ps1';$code=$assignment[0].Extent.Text
[IO.File]::WriteAllText($workerPath,$code,[Text.UTF8Encoding]::new($true))
. $workerPath
$checks=[Collections.Generic.List[object]]::new()
$script:SharedRaceRoot='';$script:SharedRaceState='';$script:SharedRaceCount=0
function Assert {param($Value,[string]$Message='Assertion failed');if(-not $Value){throw $Message}}
function Request {
    param([string]$Mode='Reserve',[string]$Owner='first')
    [pscustomobject]@{Mode=$Mode;Root=$script:SharedRaceRoot;Domain='example.invalid';Owner=$Owner;Station=('pc-'+$Owner);User='fixture';Context='test';Minutes=5;Name='P111301AA765001';Names=@('P111301AA765001');Credential=$null}
}
function EntryPath {Join-Path $script:SharedRaceRoot 'reservations\P111301AA765001.json'}
function ReadEntry {([IO.File]::ReadAllText((EntryPath),[Text.Encoding]::UTF8)|ConvertFrom-Json)}
function WriteEntry {param($Entry);[IO.File]::WriteAllText((EntryPath),($Entry|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
function ExpireEntry {$e=ReadEntry;$e.ExpiresUtc=[DateTime]::UtcNow.AddMinutes(-1).ToString('o');WriteEntry $e}
function Case {
    param([string]$Name,[scriptblock]$Body)
    $script:SharedRaceRoot=Join-Path $fixture ([Guid]::NewGuid().ToString('N'))
    try{
        & $script:PestoSharedNameWorker (Request Prepare)|Out-Null
        & $Body
        $checks.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})
    }catch{$checks.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}
}
try{
    Case 'Prepare creates only the requested local registry' {
        Assert ([IO.File]::Exists((Join-Path $script:SharedRaceRoot 'pesto-coordination.json')))
        Assert ([IO.Directory]::Exists((Join-Path $script:SharedRaceRoot 'reservations')))
    }
    Case 'Exclusive initial reserve returns its owner' {
        $r=& $script:PestoSharedNameWorker (Request);Assert ($r.State -ceq 'Reserved');Assert ((ReadEntry).Owner -ceq 'first')
    }
    Case 'Same owner renews the existing reservation' {
        & $script:PestoSharedNameWorker (Request)|Out-Null
        $r=& $script:PestoSharedNameWorker (Request);Assert ($r.State -ceq 'Renewed')
    }
    Case 'Other owner cannot take a live reservation' {
        & $script:PestoSharedNameWorker (Request)|Out-Null
        $r=& $script:PestoSharedNameWorker (Request Reserve second);Assert ($r.State -ceq 'Held');Assert ((ReadEntry).Owner -ceq 'first')
    }
    Case 'Expired reservation can be taken under the existing write lock' {
        & $script:PestoSharedNameWorker (Request)|Out-Null;ExpireEntry
        $r=& $script:PestoSharedNameWorker (Request Reserve second);Assert ($r.State -ceq 'Reserved');Assert ((ReadEntry).Owner -ceq 'second')
    }
    Case 'Owner release removes its file and reports exactly that name' {
        & $script:PestoSharedNameWorker (Request)|Out-Null
        $r=& $script:PestoSharedNameWorker (Request Release);Assert (-not [IO.File]::Exists((EntryPath)))
        Assert ($r.Others.Count -eq 1 -and $r.Others[0] -ceq 'P111301AA765001')
    }
    Case 'Other owner release preserves byte-for-byte the file' {
        & $script:PestoSharedNameWorker (Request)|Out-Null;$before=[IO.File]::ReadAllText((EntryPath))
        $r=& $script:PestoSharedNameWorker (Request Release second);Assert ($r.Others.Count -eq 0)
        Assert ($before -ceq [IO.File]::ReadAllText((EntryPath)))
    }
    Case 'Unreadable owner is retained and never announced as released' {
        [IO.File]::WriteAllText((EntryPath),'{invalid')
        $r=& $script:PestoSharedNameWorker (Request Release);Assert ($r.Others.Count -eq 0);Assert ([IO.File]::Exists((EntryPath)))
    }
    Case 'Oversized owner file is retained without parsing unbounded data' {
        [IO.File]::WriteAllText((EntryPath),('x'*8193))
        $r=& $script:PestoSharedNameWorker (Request Release);Assert ($r.Others.Count -eq 0);Assert ([IO.File]::Exists((EntryPath)))
    }
    Case 'Already absent release is idempotent' {$r=& $script:PestoSharedNameWorker (Request Release);Assert ($r.Others.Count -eq 0)}
    Case 'Active writer prevents release and keeps the reservation' {
        & $script:PestoSharedNameWorker (Request)|Out-Null
        $h=[IO.File]::Open((EntryPath),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        try{$r=& $script:PestoSharedNameWorker (Request Release);Assert ($r.Others.Count -eq 0)}finally{$h.Dispose()}
        Assert ((ReadEntry).Owner -ceq 'first')
    }
    Case 'Read-only file makes failed deletion explicit in the returned name list' {
        & $script:PestoSharedNameWorker (Request)|Out-Null
        $path=EntryPath;[IO.File]::SetAttributes($path,[IO.FileAttributes]::ReadOnly)
        try{$r=& $script:PestoSharedNameWorker (Request Release);Assert ($r.Others.Count -eq 0);Assert ((ReadEntry).Owner -ceq 'first')}
        finally{[IO.File]::SetAttributes($path,[IO.FileAttributes]::Normal)}
    }
    Case 'A competing takeover cannot be deleted between owner read and release' {
        & $script:PestoSharedNameWorker (Request)|Out-Null;ExpireEntry
        $line=0;$lines=$code -split '\r?\n'
        for($i=0;$i -lt $lines.Length;$i++){if($lines[$i].Contains('if($e -and [string]$e.Owner -eq $owner){')){$line=$i+1}}
        Assert ($line -gt 0) 'Release ownership decision missing'
        $script:SharedRaceState='';$script:SharedRaceCount=0
        $bp=Set-PSBreakpoint -Script $workerPath -Line $line -Action {
            $script:SharedRaceCount++
            $other=[pscustomobject]@{Mode='Reserve';Root=$script:SharedRaceRoot;Domain='example.invalid';Owner='second';Station='pc-second';User='fixture';Context='test';Minutes=5;Name='P111301AA765001';Names=@();Credential=$null}
            $takeover=& $script:PestoSharedNameWorker $other
            $script:SharedRaceState=[string]$takeover.State
        }
        try{$r=& $script:PestoSharedNameWorker (Request Release)}finally{Remove-PSBreakpoint $bp}
        Assert ($script:SharedRaceCount -eq 1) 'Race barrier was not hit exactly once'
        Assert ($script:SharedRaceState -ceq 'Held') ('A competing worker acquired the file: '+$script:SharedRaceState)
        Assert ($r.Others.Count -eq 1 -and -not [IO.File]::Exists((EntryPath)))
        # Once the old handle is disposed the next owner can create and retain its own reservation.
        $next=& $script:PestoSharedNameWorker (Request Reserve second)
        Assert ($next.State -ceq 'Reserved' -and (ReadEntry).Owner -ceq 'second')
    }
    Case 'Snapshot includes other owners without changing their data' {
        & $script:PestoSharedNameWorker (Request)|Out-Null
        $before=[IO.File]::ReadAllText((EntryPath));$r=& $script:PestoSharedNameWorker (Request Snapshot second)
        Assert ($r.Count -eq 1 -and $r.Others[0].Name -ceq 'P111301AA765001');Assert ($before -ceq [IO.File]::ReadAllText((EntryPath)))
    }
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop}
$failed=@($checks|Where-Object{-not $_.Passed}).Count
$report=[pscustomobject]@{Suite='SharedNameReservation';PowerShell=$PSVersionTable.PSVersion.ToString();WindowsExecuted=($env:OS -eq 'Windows_NT');ADExecuted=$false;NetworkExecuted=$false;SourceHash=(Get-FileHash $SourcePath -Algorithm SHA256).Hash;Passed=$checks.Count-$failed;Failed=$failed;Checks=$checks.ToArray();Scope='Actual shared-name worker, temporary local files; a debugger action schedules the competing worker at the owner/delete boundary'}
if($ReportPath){$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
$report|ConvertTo-Json -Depth 6
if($failed){exit 1}

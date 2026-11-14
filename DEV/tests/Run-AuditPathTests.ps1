#requires -Version 5.1
[CmdletBinding()]
param([string]$ReportPath='')
$ErrorActionPreference='Stop'
$runtime=Join-Path (Split-Path $PSScriptRoot -Parent) 'wad'
$root=Join-Path $PSScriptRoot ('.audit-path-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$results=[Collections.Generic.List[object]]::new()
# Definitions only: no UI, network, domain or production storage is loaded.
. (Join-Path $runtime 'Pesto-Safety.ps1')
. (Join-Path $runtime 'Pesto-Journal.ps1')
. (Join-Path $runtime 'Pesto-Common.ps1');Initialize-PestoRuntimeTypes -Root $runtime
function Require {param($Ok,[string]$Why);if(-not $Ok){throw $Why}}
function Case {param([string]$Name,[scriptblock]$Body)
    try{& $Body;$results.Add([pscustomobject]@{Name=$Name;Passed=$true;Error=''})}
    catch{$results.Add([pscustomobject]@{Name=$Name;Passed=$false;Error=$_.Exception.Message})}
    finally{if($script:PestoAuditWriter){[void]$script:PestoAuditWriter.Close(2000)};$script:PestoAuditWriter=$null;$script:AuditFile=$null;$script:PestoAuditClock=$null;$script:PestoAuditLost=$false}
}
$oldLocal=$env:LOCALAPPDATA;$oldTemp=$env:TEMP
$env:LOCALAPPDATA=Join-Path $root 'local';$env:TEMP=Join-Path $root 'temp'
try{
    Case 'Plain directory creates a working audit writer' {
        $preferred=Join-Path $root 'plain';Initialize-AuditLog $preferred
        Require ($script:AuditFile -and (Split-Path $script:AuditFile -Parent) -eq $preferred) 'Preferred path not selected'
        Require (Test-PestoAuditWritable) 'Writer not usable'
    }
    Case 'Linked ancestor rejected before creating its descendant' {
        $outside=Join-Path $root 'outside';[void][IO.Directory]::CreateDirectory($outside)
        $link=Join-Path $root 'linked';[void](New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop)
        $preferred=Join-Path $link 'never-created'
        Initialize-AuditLog $preferred
        Require (-not [IO.Directory]::Exists((Join-Path $outside 'never-created'))) 'Created a directory through a link'
        Require ($script:AuditFile -and (Split-Path $script:AuditFile -Parent) -ne $preferred) 'Linked path selected'
        Require (Test-PestoAuditWritable) 'Safe fallback not usable'
    }
    Case 'Existing linked directory receives no new daily journal' {
        $outside=Join-Path $root 'outside';$link=Join-Path $root 'linked'
        Initialize-AuditLog $link
        Require (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'Wrote through linked directory'
        Require (Test-PestoAuditWritable) 'Safe fallback not usable'
    }
    Case 'Day rollover without loss: new daily file from the audit clock, writer usable' {
        $script:PestoAuditClock={[DateTime]'2026-03-01T23:59:58'}
        $dir=Join-Path $root 'rollover-ok';Initialize-AuditLog $dir
        Require ((Split-Path $script:AuditFile -Leaf) -eq 'Pesto_2026-03-01.log') 'File date not taken from the audit clock'
        Require (Write-PestoAuditQueued -Text "avant`n") 'Write before midnight failed'
        $script:PestoAuditClock={[DateTime]'2026-03-02T00:00:01'}
        Require (Write-PestoAuditQueued -Text "apres`n") 'Write after midnight failed'
        Require ((Split-Path $script:AuditFile -Leaf) -eq 'Pesto_2026-03-02.log') 'No new daily file'
        Require ((Get-Content -LiteralPath (Join-Path $dir 'Pesto_2026-03-01.log') -Raw) -match 'Suite dans Pesto_2026-03-02\.log') 'Transition line missing'
        Require (Test-PestoAuditWritable) 'Clean rollover blocked mutations'
    }
    Case 'Audit loss before midnight stays blocking after the day rollover' {
        $script:PestoAuditClock={[DateTime]'2026-03-01T23:59:58'}
        $dir=Join-Path $root 'rollover-lost';Initialize-AuditLog $dir
        Require (Test-PestoAuditWritable) 'Writer not usable before the forced loss'
        # Real writer failure: the daily file becomes a directory and the queued line is lost.
        $file=$script:AuditFile;Remove-Item -LiteralPath $file -Force;[void][IO.Directory]::CreateDirectory($file)
        [void](Write-PestoAuditQueued -Text "perdue`n")
        $deadline=[DateTime]::UtcNow.AddSeconds(5);while(-not $script:PestoAuditWriter.Error -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 20}
        Require ($script:PestoAuditWriter.Error -and $script:PestoAuditWriter.Dropped -gt 0) 'Loss not observed'
        Require (-not (Test-PestoAuditWritable)) 'Loss not blocking before midnight'
        $script:PestoAuditClock={[DateTime]'2026-03-02T00:00:01'}
        [void](Write-PestoAuditQueued -Text "apres`n")
        Require ((Split-Path $script:AuditFile -Leaf) -eq 'Pesto_2026-03-02.log') 'No new daily file'
        Require (-not $script:PestoAuditWriter.Error -and $script:PestoAuditWriter.Dropped -eq 0) 'Fresh writer expected after rollover'
        Require (-not (Test-PestoAuditWritable)) 'Rollover cleared the audit-loss barrier'
        Require (-not (Get-PestoAuditHealth).Ready) 'Health reports ready after a loss'
        $script:PestoAuditClock={[DateTime]'2026-03-03T00:00:01'}
        [void](Write-PestoAuditQueued -Text "lendemain`n")
        Require (-not (Test-PestoAuditWritable)) 'Second rollover cleared the audit-loss barrier'
    }
}finally{
    $env:LOCALAPPDATA=$oldLocal;$env:TEMP=$oldTemp
    # Remove the link itself first; never recurse into its target.
    $link=Join-Path $root 'linked';if(Test-Path -LiteralPath $link){Remove-Item -LiteralPath $link -Force}
    Remove-Item -LiteralPath $root -Recurse -Force
}
$report=[pscustomobject]@{Suite='AuditPath';Total=$results.Count;Passed=@($results|Where-Object Passed).Count;Failed=@($results|Where-Object{-not $_.Passed}).Count;Cases=$results.ToArray();PowerShell=[string]$PSVersionTable.PSVersion;WindowsExecuted=($env:OS -eq 'Windows_NT');ADExecuted=$false;Scope='Real journal initializer and writer, isolated directories and real symlink; no production audit files'}
if($ReportPath){[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath),($report|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))}
$report|ConvertTo-Json -Depth 6
if($report.Failed){exit 1}

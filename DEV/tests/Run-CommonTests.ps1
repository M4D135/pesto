#requires -Version 5.1
# Pure DLL loading tests on local copies. No application startup or AD.
param([string]$Root='',[string]$ReportPath='')
if(-not $Root){$Root=Split-Path $PSScriptRoot -Parent}
$ErrorActionPreference='Stop'
. (Join-Path (Join-Path $root 'wad') 'Pesto-Common.ps1')
$tempBase=[IO.Path]::GetTempPath()
if([Environment]::OSVersion.Platform -ne 'Win32NT'){$tempBase=$HOME} # macOS /var is a symlink; exercise hashes on a plain path.
$temp=Join-Path $tempBase ('pesto-common-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$count=0
function Reject-Common {param([scriptblock]$Action);$caught=$false;try{& $Action}catch{$caught=$true};if(-not $caught){throw 'Invalid bundle accepted.'};$script:count++}
try{
    foreach($file in @('common.lock.json','M4D.Admin.Common.Core.dll','M4D.Admin.Common.Query.dll','M4D.Admin.Common.IO.dll','M4D.Admin.Common.Diagnostics.dll')+@(if(Test-Path (Join-Path $root 'wad/M4D.Admin.Common.Wpf.dll')){'M4D.Admin.Common.Wpf.dll'})){Copy-Item -LiteralPath (Join-Path (Join-Path $root 'wad') $file) -Destination $temp}
    $lockPath=Join-Path $temp 'common.lock.json';$original=[IO.File]::ReadAllText($lockPath)
    $lock=$original|ConvertFrom-Json;$lock.Version='99.0';$lock|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $lockPath -Encoding UTF8
    Reject-Common {Initialize-PestoCommon -Root $temp}
    [IO.File]::WriteAllText($lockPath,$original)
    $lock=$original|ConvertFrom-Json;$lock.SourceDirty=$true;$lock|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $lockPath -Encoding UTF8
    Reject-Common {Initialize-PestoCommon -Root $temp}
    [IO.File]::WriteAllText($lockPath,$original)
    $queryPath=Join-Path $temp 'M4D.Admin.Common.Query.dll';$bytes=[IO.File]::ReadAllBytes($queryPath)
    $changed=[byte[]]$bytes.Clone();$changed[200]=$changed[200] -bxor 1;[IO.File]::WriteAllBytes($queryPath,$changed)
    Reject-Common {Initialize-PestoCommon -Root $temp}
    if(@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -like 'M4D.Admin.Common.*'}).Count){throw 'A DLL loaded before the whole bundle was checked.'};$count++
    [IO.File]::WriteAllBytes($queryPath,$bytes)
    $wpfPath=Join-Path $temp 'M4D.Admin.Common.Wpf.dll'
    if(Test-Path -LiteralPath $wpfPath){
        $wpfBytes=[IO.File]::ReadAllBytes($wpfPath);$wpfChanged=[byte[]]$wpfBytes.Clone();$wpfChanged[200]=$wpfChanged[200] -bxor 1
        [IO.File]::WriteAllBytes($wpfPath,$wpfChanged)
        Reject-Common {Initialize-PestoCommon -Root $temp} # also when WPF is not requested
        [IO.File]::WriteAllBytes($wpfPath,$wpfBytes)
    }
    $lock=$original|ConvertFrom-Json;$lock.Files[1]=$lock.Files[0];$lock|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $lockPath -Encoding UTF8
    Reject-Common {Initialize-PestoCommon -Root $temp}
    [IO.File]::WriteAllText($lockPath,$original)
    # Real child scripts have independent script scopes; assembly provenance must
    # remain valid when the second child runs in the same PowerShell process.
    $runtimeRoot=Join-Path $root 'wad'
    $loader=Join-Path $runtimeRoot 'Pesto-Common.ps1'
    $childPath=Join-Path $temp 'load-common-child.ps1'
    $childSource="param([string]`$Loader,[string]`$RuntimeRoot)`n. `$Loader`nInitialize-PestoCommon -Root `$RuntimeRoot`n'Loaded'"
    [IO.File]::WriteAllText($childPath,$childSource,[Text.UTF8Encoding]::new($true))
    foreach($attempt in 1..2){
        $answer=& $childPath -Loader $loader -RuntimeRoot $runtimeRoot
        if($answer -cne 'Loaded'){throw 'Child script could not reuse verified assemblies.'};$count++
    }
    Initialize-PestoCommon -Root $runtimeRoot
    if([M4D.Admin.Common.Core.RandomSelection]::NextIndex(1) -ne 0){throw 'Core API unavailable.'};$count++
    Initialize-PestoCommon -Root (Join-Path $root 'wad');$count++
    if([M4D.Admin.Common.Core.Validation]::RequiredText('Pesto','name',5) -cne 'Pesto'){throw 'Common validation unavailable.'};$count++
    $buffer=[M4D.Admin.Common.Diagnostics.BoundedEventBuffer]::new(1);$buffer.Add('old');$buffer.Add('new')
    if($buffer.Discarded -ne 1 -or $buffer.Snapshot()[0] -cne 'new'){throw 'Bounded diagnostics unavailable.'};$count++
    if([M4D.Admin.Common.Diagnostics.Redaction]::Mask('token=CANARY_COMMON') -match 'CANARY_COMMON'){throw 'Common redaction failed.'};$count++
    $atomic=Join-Path $temp 'atomic.txt';[void][M4D.Admin.Common.IO.AtomicFile]::WriteWithBackup($atomic,[Text.Encoding]::UTF8.GetBytes('first'))
    $backup=[M4D.Admin.Common.IO.AtomicFile]::WriteWithBackup($atomic,[Text.Encoding]::UTF8.GetBytes('second'))
    if([IO.File]::ReadAllText($atomic) -cne 'second' -or [IO.File]::ReadAllText($backup) -cne 'first'){throw 'Common atomic backup failed.'};$count++
    if(@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -eq 'M4D.Admin.Common.Wpf'}).Count){throw 'WPF was implicitly loaded.'};$count++
    if([Environment]::OSVersion.Platform -ne 'Win32NT'){Reject-Common {Initialize-PestoCommon -Root $runtimeRoot -IncludeWpf}}
    $diagnosticSource=Join-Path $runtimeRoot 'Pesto-Diagnostics.ps1';$tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($diagnosticSource,[ref]$tokens,[ref]$errors)
    $finding=$ast.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-PestoDiagnosticFinding'},$true)
    if(-not $finding -or $errors.Count){throw 'Diagnostic finding definition invalid.'}
    . ([scriptblock]::Create($finding.Extent.Text))
    function Protect-PestoLogText {param([string]$Text);return $Text}
    $payload=[pscustomobject]@{Unchanged='structured'}
    $result=New-PestoDiagnosticFinding -Name Fixture -State Observed -Detail 'password=CANARY_COMMON' -Data $payload
    if($result.Detail -match 'CANARY_COMMON' -or -not [object]::ReferenceEquals($result.Data,$payload)){throw 'Verified common diagnostic reuse failed.'};$count++

    # The persistent record must not make another location or modified bytes valid.
    Reject-Common {Initialize-PestoCommon -Root $temp}
    [IO.File]::WriteAllBytes($queryPath,$changed)
    Reject-Common {Initialize-PestoCommon -Root $temp}
    [IO.File]::WriteAllBytes($queryPath,$bytes)
    # A fresh process with a foreign preloaded DLL has no verified provenance.
    $foreignPath=Join-Path $temp 'foreign-common-child.ps1'
    $foreignSource="param([string]`$Loader,[string]`$RuntimeRoot)`n`$ErrorActionPreference='Stop'`n[void][Reflection.Assembly]::LoadFrom((Join-Path `$RuntimeRoot 'M4D.Admin.Common.Core.dll'))`n. `$Loader`ntry{Initialize-PestoCommon -Root `$RuntimeRoot}catch{'Rejected';exit 0}`nthrow 'Foreign assembly accepted.'"
    [IO.File]::WriteAllText($foreignPath,$foreignSource,[Text.UTF8Encoding]::new($true))
    $hostPath=(Get-Process -Id $PID).Path
    $foreignAnswer=& $hostPath -NoLogo -NoProfile -NonInteractive -File $foreignPath -Loader $loader -RuntimeRoot $runtimeRoot
    if($LASTEXITCODE -ne 0 -or $foreignAnswer -cne 'Rejected'){throw 'Preloaded foreign assembly was not rejected.'};$count++
    $report=[pscustomobject]@{Passed=$count;Scope='Local DLL/hash and pure primitives; no application/AD';PowerShell=$PSVersionTable.PSVersion.ToString();Target='net472';WindowsExecuted=([Environment]::OSVersion.Platform -eq 'Win32NT');WpfExecuted=$false}
    if($ReportPath){$report|ConvertTo-Json|Set-Content -LiteralPath $ReportPath -Encoding UTF8}
    $report|ConvertTo-Json
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}

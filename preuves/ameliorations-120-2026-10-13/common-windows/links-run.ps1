$ErrorActionPreference='Stop'
$root='C:\PestoCommon020_20261013'
[void][Reflection.Assembly]::LoadFrom(($root+'\M4D.Admin.Common.IO.dll'))
$fixture=$root+'\link-fixture'
if(Test-Path $fixture){throw 'Existing fixture'}
[void][IO.Directory]::CreateDirectory(($fixture+'\child\nested'))
[IO.File]::WriteAllText(($fixture+'\child\marker.txt'),'KEEP')
[void](New-Item -ItemType SymbolicLink -Path ($fixture+'\alias') -Value ($fixture+'\child') -ErrorAction Stop)
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Ok){$checks.Add([pscustomobject]@{Name=$Name;Passed=$Ok});if(-not $Ok){throw $Name}}
function Refuse([string]$Name,[scriptblock]$Body){$rejected=$false;try{& $Body|Out-Null}catch{$e=$_.Exception;while($e.InnerException){$e=$e.InnerException};$rejected=$e -is [IO.IOException]};Check $Name $rejected}
$r=[M4D.Admin.Common.IO.FileFootprint]::Scan($fixture,100,30,[Threading.CancellationToken]::None)
Check 'Directory symlink skipped without double counting' (-not $r.Complete -and $r.OtherLinks -eq 1 -and $r.Bytes -eq 4)
Refuse 'Reparse root refused' {[M4D.Admin.Common.IO.FileFootprint]::Scan(($fixture+'\alias'),100,30,[Threading.CancellationToken]::None)}
Refuse 'Reparse ancestor refused' {[M4D.Admin.Common.IO.FileFootprint]::Scan(($fixture+'\alias\nested'),100,30,[Threading.CancellationToken]::None)}
Refuse 'Atomic write through linked parent refused' {[M4D.Admin.Common.IO.AtomicFile]::WriteWithBackup(($fixture+'\alias\marker.txt'),[Text.Encoding]::UTF8.GetBytes('REPLACE'))}
Check 'Original contents preserved' ([IO.File]::ReadAllText(($fixture+'\child\marker.txt')) -ceq 'KEEP')
[ordered]@{Status='PASS';Scope='Real NTFS symbolic links created by PowerShell; fixture only';PS=$PSVersionTable.PSVersion.ToString();Computer=$env:COMPUTERNAME;SHA256=(Get-FileHash ($root+'\M4D.Admin.Common.IO.dll')).Hash;Checks=$checks.ToArray()}|ConvertTo-Json -Depth 6
# Leave fixture as auditable evidence; no broad recursive deletion through links.

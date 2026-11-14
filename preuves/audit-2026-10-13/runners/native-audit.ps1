param([string]$Root='C:\PestoAudit20261013\interactive')
$ErrorActionPreference='Stop'
$proof=Join-Path $Root 'preuves';$source=Join-Path $Root 'PROD'
$cases=Join-Path $Root 'native-cases';if(Test-Path $cases){throw 'Choose a fresh audit directory.'}
[void](New-Item -ItemType Directory $cases)
$results=[Collections.Generic.List[object]]::new()
function Invoke-Case([string]$Name,[string]$Folder,[string]$Arguments,[int]$Expected){
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $p=Start-Process -FilePath (Join-Path $Folder 'Pesto.exe') -ArgumentList $Arguments -WorkingDirectory $Folder -PassThru
 if(-not $p.WaitForExit(60000)){$p.Kill();throw ('Timed out: '+$Name)}
 $p.Refresh();$code=$p.ExitCode;$timer.Stop()
 $results.Add([pscustomobject]@{Name=$Name;Expected=$Expected;ExitCode=$code;Passed=($code-eq$Expected);Milliseconds=$timer.ElapsedMilliseconds})
}
function Copy-Case([string]$Name){$dest=Join-Path $cases $Name;Copy-Item -LiteralPath $source -Destination $dest -Recurse;return $dest}
$report=Join-Path $proof 'native-prod-check.json'
Invoke-Case 'Published PROD full integrity and syntax check' $source ('--check-json "'+$report+'"') 0
Invoke-Case 'Published DEV full integrity and syntax check' (Join-Path $Root 'DEV') ('--check-json "'+(Join-Path $proof 'native-dev-check.json')+'"') 0
$before=(Get-FileHash $report).Hash
Invoke-Case 'Existing report is refused without overwriting' $source ('--check-json "'+$report+'"') 1
if((Get-FileHash $report).Hash-cne$before){throw 'Existing report changed'}
Invoke-Case 'Unknown argument is rejected quietly' $source '--unknown --check --quiet' 120
Invoke-Case 'Missing report argument is rejected quietly' $source '--check-json' 120
Invoke-Case 'Missing external configuration is rejected' $source '-ConfigPath C:\PestoAudit20261013\interactive\absent-cfg.json --check --quiet' 121
Invoke-Case 'Conflicting consult and credential flags are rejected' $source '--consult -AskCredential --check --quiet' 120
$d=Copy-Case 'missing-startup';Remove-Item -LiteralPath (Join-Path $d 'wad\Pesto-Startup.ps1');Invoke-Case 'Missing startup fails before PowerShell' $d '--check --quiet' 124
$d=Copy-Case 'missing-core';Remove-Item -LiteralPath (Join-Path $d 'wad\Pesto-Core.ps1');Invoke-Case 'Missing runtime component fails integrity' $d '--check --quiet' 125
$d=Copy-Case 'changed-core';[IO.File]::AppendAllText((Join-Path $d 'wad\Pesto-Core.ps1'),"`r`n# audit modification");Invoke-Case 'Modified script fails integrity' $d '--check --quiet' 125
$d=Copy-Case 'changed-dll';$f=Join-Path $d 'wad\M4D.Admin.Common.Core.dll';$b=[IO.File]::ReadAllBytes($f);$b[$b.Length-1]=$b[$b.Length-1]-bxor1;[IO.File]::WriteAllBytes($f,$b);Invoke-Case 'Modified DLL fails integrity' $d '--check --quiet' 125
$d=Copy-Case 'update-lock';[IO.File]::WriteAllText((Join-Path $d '.pesto-update.lock'),'audit lock');Invoke-Case 'Update lock prevents execution' $d '--check --quiet' 126
$d=Copy-Case 'été avec espaces';Invoke-Case 'Unicode and spaces in installation path' $d '--check --quiet' 0
$draft=Join-Path $cases 'valid-draft.json';[IO.File]::WriteAllText($draft,'{"Schema":1,"Domain":"example.local","Nom_du_PC":"PC-SOURCE","Nouveau_Nom":"P123456LY765001","Renommer":true,"Deplacer":false}')
Invoke-Case 'Valid draft remains unauthorized and contacts no domain' $source ('--validate-plan "'+$draft+'" "'+(Join-Path $proof 'valid-draft-report.json')+'"') 0
$r=Get-Content (Join-Path $proof 'valid-draft-report.json') -Raw|ConvertFrom-Json;if(-not$r.ValidDraft -or $r.Authorized -or $r.AD-ne'NOT_CONTACTED'){throw 'Invalid draft security contract'}
[IO.File]::WriteAllText($draft,'{"Schema":1,"Domain":"example.local","Nom_du_PC":"PC-SOURCE","Nouveau_Nom":"BAD","Renommer":true,"Deplacer":false,"Authorized":true}')
Invoke-Case 'Unknown authorization field and invalid name are rejected' $source ('--validate-plan "'+$draft+'" "'+(Join-Path $proof 'invalid-draft-report.json')+'"') 20
$r=Get-Content (Join-Path $proof 'invalid-draft-report.json') -Raw|ConvertFrom-Json;if($r.ValidDraft -or $r.Authorized -or $r.AD-ne'NOT_CONTACTED'){throw 'Invalid rejection contract'}
$failed=@($results|Where-Object{-not$_.Passed}).Count
[pscustomobject]@{ExeSHA256=(Get-FileHash (Join-Path $source 'Pesto.exe')).Hash;PowerShell=$PSVersionTable.PSVersion.ToString();ADMutations=$false;UACRequested=$false;ExistingReportPreserved=$true;Total=$results.Count;Passed=$results.Count-$failed;Failed=$failed;Checks=$results.ToArray()}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $proof 'native-summary.json') -Encoding UTF8
if($failed){exit 1}
